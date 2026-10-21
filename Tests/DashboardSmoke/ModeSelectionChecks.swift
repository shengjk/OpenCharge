import Foundation
import ChargeCore
import ChargeHardware

@MainActor func modeSelectionChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(); let provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider }
 var sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 var failReading = false
 func fixture(mode: ChargeMode = .automatic, currentPause: Bool = false, checkpoint: CalibrationCheckpoint? = nil) throws -> ChargeModel {
  var config = Configuration(); config.policy.limit = 50; config.policy.mode = mode
  config.policy.pauseAtCurrent = currentPause ? true : nil; config.calibrationCheckpoint = checkpoint
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
  try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("mode fixture must not lock") }, readBattery: {
   if failReading { throw HardwareError.unavailable("fixture telemetry unavailable") }; return sample
  })
 }
 let pause = try fixture(mode: .paused, currentPause: true)
 pause.controlModeSelection.wrappedValue = .automatic
 pause.controlModeSelection.wrappedValue = .paused
 sample = BatteryReading(percent: 49, temperature: 30, connected: true, charging: false)
 pause.refresh()
 precondition(pause.config.policy.mode == .paused && pause.config.policy.pauseAtCurrent == nil && pause.decision.action == .inhibitCharge, "explicit picker Pause must stay paused below the old current-limit boundary")
 let saved = try Configuration.load(); precondition(saved.policy.mode == .paused && saved.policy.pauseAtCurrent == nil)

 // The picker uses the same connection guard as other explicit GUI requests.
 sample = BatteryReading(percent: 49, temperature: 30, connected: false, charging: false)
 for mode: ChargeMode in [.topUp, .calibration] {
  let unplugged = try fixture(); let before = unplugged.config.policy
  unplugged.controlModeSelection.wrappedValue = mode
  precondition(unplugged.config.policy == before && unplugged.error != nil)
  let persisted = try Configuration.load(); precondition(persisted.policy == before)
 }
 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 let pending = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining))
 pending.controlModeSelection.wrappedValue = .calibration
 precondition(pending.calibrationPending && pending.config.calibrationCheckpoint?.stage == .draining && pending.error != nil)
 pending.controlModeSelection.wrappedValue = .topUp
 precondition(pending.calibrationPending && pending.config.policy.mode == .calibration)
 pending.controlModeSelection.wrappedValue = .automatic
 precondition(!pending.calibrationPending && pending.calibration == .idle && pending.config.calibrationCheckpoint == nil)
 pending.controlModeSelection.wrappedValue = .calibration
 precondition(pending.calibration == .filling && !pending.calibrationPending)
 pending.controlModeSelection.wrappedValue = .paused
 precondition(pending.calibration == .idle && pending.config.calibrationCheckpoint == nil)

 // An accepted cancellation must reach the engine even if the refresh fails.
 let active = try fixture(mode: .calibration)
 sample = BatteryReading(percent: 100, temperature: 30, connected: true, charging: false)
 active.refresh(); precondition(active.calibration == .draining)
 failReading = true
 active.controlModeSelection.wrappedValue = .paused
 precondition(active.calibration == .idle && active.config.calibrationCheckpoint == nil)
 active.controlModeSelection.wrappedValue = .calibration
 failReading = false
 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 active.refresh()
 precondition(active.calibration == .filling && active.config.calibrationCheckpoint?.stage == .filling, "cancelled calibration must not resume its old draining stage after unavailable telemetry")
 active.controlModeSelection.wrappedValue = .calibration
 precondition(active.calibration == .filling, "selecting an active mode is idempotent")

 let profile = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .holding, holdingSince: Date()))
 profile.profile(70, 5, 35)
 precondition(profile.config.policy.mode == .automatic && !profile.calibrationPending && profile.calibration == .idle && profile.config.calibrationCheckpoint == nil)
 precondition(profile.config.policy.limit == 70 && profile.config.policy.pauseAtCurrent == nil)
 let profileSaved = try Configuration.load()
 precondition(profileSaved.policy.mode == .automatic && profileSaved.calibrationCheckpoint == nil)
 for model in [pause, pending, active, profile] { precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true) }
 print("Explicit mode picker clears current-limit Pause state, enforces connection/interruption guards, cancels calibration across failed telemetry and shares profile cleanup; isolated telemetry, no hardware")
}
