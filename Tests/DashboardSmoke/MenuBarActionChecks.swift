import Foundation
import ChargeCore
import ChargeHardware

@MainActor func menuBarActionChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(); let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider; defaults.removeObject(forKey: "menuRightClickAction") }
 let preferences = MenuBarActionPreferences(defaults: defaults)
 precondition(preferences.rightClick == .popover)
 for action in MenuBarRightClickAction.allCases {
  preferences.rightClick = action
  precondition(MenuBarActionPreferences(defaults: defaults).rightClick == action)
  for click: StatusItemClick in [.primary, .secondary, .programmatic] {
   var events: [String] = []
   StatusItemActionRouter.route(click, preference: action, togglePopover: { events.append("popover") }, closePopover: { events.append("close") }, openSettings: { events.append("settings") }, toggleCharging: { events.append("charge") }, toggleLowPower: { events.append("lpm") })
   let expected = click != .secondary || action == .popover ? ["popover"] : action == .settings ? ["close", "settings"] : action == .toggleCharging ? ["charge"] : ["lpm"]
   precondition(events == expected)
  }
 }
 defaults.set("unknown", forKey: "menuRightClickAction")
 precondition(MenuBarActionPreferences(defaults: defaults).rightClick == .popover)
 var sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 func fixture(mode: ChargeMode = .automatic, limit: Double = 80, hardware: Bool = false, checkpoint: CalibrationCheckpoint? = nil) throws -> ChargeModel {
  var config = Configuration(); config.policy.mode = mode; config.policy.limit = limit
  config.policy.useHardwarePercent = hardware; config.calibrationCheckpoint = checkpoint
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false; try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("menu fixture must not lock") }, readBattery: { sample })
 }
 let model = try fixture()
 model.toggleChargingFromMenu()
 precondition(model.config.policy.mode == .paused && model.config.policy.limit == 50 && model.config.policy.pauseAtCurrent == true)
 model.toggleChargingFromMenu()
 precondition(model.config.policy.mode == .automatic && model.config.policy.limit == 100 && model.automationPhase == .charging)
 sample = BatteryReading(percent: 99.8, temperature: 30, connected: true, charging: false)
 model.refresh(); model.refresh()
 precondition(model.decision.action == .allowCharge && model.automationPhase == .charging)
 model.selectSettingsPage(); precondition(model.dashboardPage == .settings)
 sample = BatteryReading(percent: 80, temperature: 30, connected: true, charging: false, hardwarePercent: 49.75)
 let hardware = try fixture(hardware: true); hardware.toggleChargingFromMenu()
 precondition(hardware.config.policy.limit == 49.75)
 sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 let missing = try fixture(hardware: true); let before = missing.config.policy
 missing.toggleChargingFromMenu(); precondition(missing.config.policy == before && missing.error != nil)
 let pending = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining))
 pending.toggleChargingFromMenu(); precondition(pending.calibrationPending && pending.config.calibrationCheckpoint?.stage == .draining)
 let power = try fixture(); var requests: [String] = []
 power.toggleLowPowerFromMenu(request: { requests.append($0); return "battery=0 ac=0" }, isActive: { preconditionFailure("disabled shortcut must not query activity") })
 precondition(requests.isEmpty && power.config.policy.lowPowerMode == nil)
 power.config.systemActionsEnabled = true
 for active in [false, true] {
  requests = []; power.error = nil
  power.toggleLowPowerFromMenu(request: { requests.append($0); return $0 == "lowPowerOn" ? "battery=1 ac=unknown" : "battery=0 ac=unknown" }, isActive: { active })
  precondition(requests == ["lowPowerStatus", active ? "lowPowerOff" : "lowPowerOn"])
  precondition(power.config.policy.lowPowerMode == !active && power.error == nil)
 }
 for status in ["battery=unknown ac=unknown", "battery=0 ac=2", "fixture", "battery=0 battery=1"] {
  requests = []; power.error = nil; let before = power.config.policy
  power.toggleLowPowerFromMenu(request: { requests.append($0); return status }, isActive: { preconditionFailure("unavailable shortcut must not toggle") })
  precondition(requests == ["lowPowerStatus"] && power.config.policy == before && power.error != nil)
 }
 requests = []; power.error = nil; let beforeFailure = power.config.policy
 let beforeUnavailable = power.config.policy
 power.toggleLowPowerFromMenu(request: { requests.append($0); return "battery=0 ac=0" }, isActive: { nil })
 precondition(requests == ["lowPowerStatus"] && power.config.policy == beforeUnavailable && power.error != nil)
 requests = []; power.error = nil
 power.toggleLowPowerFromMenu(request: { requests.append($0); if $0 == "lowPowerStatus" { return "battery=0 ac=0" }; throw HelperError.rejected("fixture write failed") }, isActive: { false })
 precondition(requests == ["lowPowerStatus", "lowPowerOn"] && power.config.policy == beforeFailure && power.error != nil)
 precondition(!power.config.hardwareEnabled)
 print("Menu-bar right-click persistence/routing, current-percent/full-charge toggle and gated Low Power Mode checked with injected telemetry/IPC; no real status-item or system setter")
}
