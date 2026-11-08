import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func lowPowerWidgetChecks() throws {
 let suite = "org.opencharge.low-power-test."+UUID().uuidString
 let defaults = UserDefaults(suiteName: suite)!
 defer { defaults.removePersistentDomain(forName: suite) }
 let original = try Configuration.load()
 defer { try? original.save(); defaults.removeObject(forKey: "popoverCompactLowPower") }
 var configuration = Configuration(); configuration.hardwareEnabled = false
 configuration.systemActionsEnabled = false; configuration.historyEnabled = false
 try configuration.save()
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  readBattery: { BatteryReading(percent: 60, connected: true, charging: false) })
 var commands: [String] = []
 func request(_ command: String) -> String {
  commands.append(command)
  return command == "lowPowerStatus" ? "battery=0 ac=1" : "battery=0 ac=0"
 }
 model.setLowPowerFromPopover(false, request: request)
 precondition(commands.isEmpty && model.error != nil)
 model.config.systemActionsEnabled = true
 model.setLowPowerFromPopover(false, request: request)
 precondition(commands == ["lowPowerStatus", "lowPowerOff"] && model.config.policy.lowPowerMode == false)
 commands = []
 model.setLowPowerFromPopover(true, source: .battery, request: { command in
  commands.append(command); return command == "lowPowerStatus" ? "battery=0 ac=1" : "battery=1 ac=1"
 })
 precondition(commands == ["lowPowerStatus", "lowPowerBatteryOn"] && model.lowPowerPreferences?.battery == true)
 commands = []; let before = model.config.policy
 model.setLowPowerFromPopover(false, source: .ac, request: { command in
  commands.append(command); return "battery=1 ac=unknown"
 })
 precondition(commands == ["lowPowerStatus"] && model.config.policy == before && model.error != nil)
 commands = []
 model.setLowPowerFromPopover(false, source: .ac, request: { command in
  commands.append(command); return "battery=1 ac=1"
 })
 precondition(commands == ["lowPowerStatus", "lowPowerACOff"] && model.config.policy == before && model.error != nil)
 for invalid in ["", "battery=0 battery=1", "ac=1 battery=0", "battery=2 ac=0", "battery=0 ac=0 extra"] {
  do { _ = try LowPowerStatus(helperResponse: invalid); preconditionFailure("malformed status accepted") } catch {}
 }
 let unavailable = try LowPowerStatus(helperResponse: "battery=unknown ac=unknown")
 precondition(unavailable.battery == nil && unavailable.ac == nil)
 let preferences = PopoverPreferences(defaults: defaults)
 preferences.compactLowPower = true
 precondition(PopoverPreferences(defaults: defaults).compactLowPower)
 defaults.removeObject(forKey: "popoverCompactLowPower")
 preferences.reloadAfterReset(); precondition(!preferences.compactLowPower)
 model.error = nil
 for active: Bool? in [true, false, nil] {
  for compact in [true, false] {
   let host = NSHostingView(rootView: LowPowerWidget(model: model, active: active, compact: compact))
   host.frame = NSRect(x: 0, y: 0, width: 340, height: 260)
   host.layoutSubtreeIfNeeded(); precondition(host.fittingSize.height > 0)
  }
 }
 print("PASS Low Power widget explicit-off, permission and capability gates, strict readback, preferences, unknown state and native layouts; injected IPC only")
}
