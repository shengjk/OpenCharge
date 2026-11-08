import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func energyModeChecks() throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 let suite = "org.opencharge.energy-mode-test."+UUID().uuidString
 let defaults = UserDefaults(suiteName: suite)!
 defer { try? original.save(); defaults.removePersistentDomain(forName: suite); PolicyStateRuntime.provider = originalProvider }
 var config = Configuration(); config.hardwareEnabled = false; config.historyEnabled = false; config.systemActionsEnabled = false
 try config.save()
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  readBattery: { BatteryReading(percent: 60, connected: true, charging: false) })
 let before = EnergyModeStatus(battery: .low, ac: .automatic, highBattery: true, highAC: true, current: .automatic)
 let high = EnergyModeStatus(battery: .low, ac: .high, highBattery: true, highAC: true, current: .high)
 var requests: [String] = []
 func request(_ command: String) -> String {
  requests.append(command); return command == "energyModeStatus" ? before.description : high.description
 }
 model.setEnergyMode(.high, source: .ac, request: request)
 precondition(requests.isEmpty && model.error != nil)
 model.config.systemActionsEnabled = true
 model.setEnergyMode(.high, source: .ac, request: request)
 precondition(requests == ["energyModeStatus", "energyModeACHigh"] && model.energyModes?.ac == .high && model.config.policy.lowPowerMode == false)
 let policy = model.config.policy
 requests = []
 let unsupported = EnergyModeStatus(battery: .automatic, ac: .low, highBattery: false, highAC: true)
 model.setEnergyMode(.high, source: .battery, request: { command in requests.append(command); return unsupported.description })
 precondition(requests == ["energyModeStatus"] && model.config.policy == policy)
 requests = []
 model.setEnergyMode(.low, source: .ac, request: { command in requests.append(command); return before.description })
 precondition(requests == ["energyModeStatus", "energyModeACLow"] && model.error != nil && model.config.policy == policy)
 requests = []
 model.inspectEnergyModes(request: { command in
  requests.append(command)
  if command == "energyModeStatus" { throw HelperError.rejected("old helper") }
  return "battery=1 ac=0"
 })
 precondition(requests == ["energyModeStatus", "lowPowerStatus"] && model.energyModes == nil && model.lowPowerPreferences?.battery == true)
 model.inspectEnergyModes(request: { _ in high.description })
 precondition(model.energyModes?.current == .high)
 for mode in EnergyMode.allCases {
  for source: PowerSource? in [nil, .battery, .ac] {
   let command = EnergyModeRequest(mode: mode, source: source).command
   precondition(HelperClient.supportedActions.contains(command), "normal IPC client must admit every fixed energy-mode route")
  }
 }
 precondition(HelperClient.supportedActions.contains("energyModeStatus"))
 model.error = nil
 for compact in [true, false] {
  let host = NSHostingView(rootView: LowPowerWidget(model: model, active: false, compact: compact))
  host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
  host.layoutSubtreeIfNeeded(); precondition(host.fittingSize.height > 0)
 }
 print("PASS energy-mode IPC routes, opt-in/capability gates, readback, old-helper fallback and high-power native layouts; injected service only")
}
