import Foundation
import ChargeCore
import ChargeHardware

@MainActor func temporaryActionChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider }
 var sample = BatteryReading(percent: 85, temperature: 30, connected: true, charging: false)
 func fixture(automaticDischarge: Bool = false, topUpHeat: Bool = false) throws -> ChargeModel {
  var config = Configuration()
  config.policy.limit = 80; config.policy.automaticDischarge = automaticDischarge
  config.policy.protectDuringTopUp = topUpHeat
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
  try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("temporary action fixture must not lock") }, readBattery: { sample })
 }
 let topUp = try fixture()
 topUp.toggleTopUp()
 precondition(topUp.config.policy.mode == .topUp && topUp.automationPhase == .topUp)
 // An explicit mode request remains idempotent; only a button toggles.
 topUp.changeMode(.topUp)
 precondition(topUp.automationPhase == .topUp)
 topUp.toggleTopUp()
 precondition(topUp.config.policy.mode == .paused && topUp.automationPhase == .pause)
 precondition(topUp.config.policy.limit == 80 && topUp.config.policy.pauseAtCurrent != true)
 sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 topUp.refresh()
 precondition(topUp.decision.action == .inhibitCharge && topUp.automationPhase == .pause)
 let persisted = try Configuration.load()
 precondition(persisted.policy.mode == .paused && persisted.policy.limit == 80 && persisted.policy.pauseAtCurrent != true)
 sample = BatteryReading(percent: 100, temperature: 30, connected: true, charging: false)
 topUp.toggleTopUp()
 precondition(topUp.automationPhase == .topUp && topUp.decision.fullChargeHold == true)
 topUp.toggleTopUp()
 precondition(topUp.automationPhase == .pause && topUp.config.policy.limit == 80)

 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 let discharge = try fixture()
 discharge.toggleDischarge()
 precondition(discharge.config.policy.mode == .discharge && discharge.automationPhase == .discharging)
 discharge.toggleDischarge()
 precondition(discharge.config.policy.mode == .paused && discharge.automationPhase == .pause)
 precondition(discharge.config.policy.limit == 80 && discharge.config.policy.pauseAtCurrent != true)
 let automatic = try fixture(automaticDischarge: true)
 precondition(automatic.config.policy.mode == .automatic && automatic.automationPhase == .discharging)
 automatic.toggleDischarge()
 precondition(automatic.config.policy.mode == .paused && automatic.automationPhase == .pause)

 // Thermal protection has its own phase; a stored Top Up mode alone must not select Stop.
 sample = BatteryReading(percent: 50, temperature: 40, connected: true, charging: false)
 let hot = try fixture(topUpHeat: true)
 hot.toggleTopUp()
 precondition(hot.automationPhase == .heatProtect && hot.config.policy.mode == .topUp)
 hot.toggleTopUp()
 precondition(hot.automationPhase == .heatProtect && hot.config.policy.mode == .topUp)
 sample = BatteryReading(percent: 50, temperature: 30, connected: false, charging: false)
 let unplugged = try fixture()
 unplugged.toggleTopUp()
 precondition(unplugged.config.policy.mode == .automatic && unplugged.error != nil)
 for model in [topUp, discharge, automatic, hot, unplugged] {
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 print("Temporary GUI actions toggle active Top Up/discharge into persistent pause without moving the daily limit; explicit requests, full state, automatic discharge, thermal state and unplug guards checked with injected telemetry")
}
