import Foundation
import AppIntents
import ChargeCore

@MainActor func automationReloadChecks(defaults: UserDefaults) async throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var interrupted = original
 interrupted.hardwareEnabled = false; interrupted.systemActionsEnabled = false
 interrupted.policy.mode = .calibration
 interrupted.calibrationCheckpoint = CalibrationCheckpoint(stage: .draining)
 try interrupted.save()
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("no real locks in automation fixture") })
 precondition(model.calibrationPending && model.calibration == .draining && !model.config.hardwareEnabled)
 var preferencesOnly = try Configuration.load()
 preferencesOnly.policy.maxTemperature = 37; preferencesOnly.hardwareEnabled = true
 try preferencesOnly.save(); model.reloadExternalConfiguration()
 precondition(model.calibrationPending && model.calibration == .draining && !model.config.hardwareEnabled,
  "an ordinary checkpoint-bearing update must preserve interruption and cannot enable hardware")
 let corrected = try Configuration.load(); precondition(!corrected.hardwareEnabled,
  "the preserved disabled opt-in must also be written back for later relaunch")
 // Invoke the real intent. The isolated directory disables distributed transport;
 // explicitly deliver its production reload callback rather than assuming notification timing.
 _ = try await StartCalibrationIntent().perform()
 let saved = try Configuration.load(); precondition(saved.calibrationCheckpoint == nil)
 model.reloadExternalConfiguration()
 if model.calibrationPending || model.calibration != .idle {
  print("REGRESSION: fresh calibration intent cleared disk checkpoint but live model kept interrupted state")
  exit(2)
 }
 precondition(!model.config.hardwareEnabled && model.config.policy.mode == .calibration)
 model.reloadExternalConfiguration()
 precondition(!model.calibrationPending && model.calibration == .idle && !model.config.hardwareEnabled,
  "duplicate notifications must not reintroduce the interrupted state")
 var leave = try Configuration.load(); leave.policy.mode = .automatic; leave.hardwareEnabled = true
 try leave.save(); model.reloadExternalConfiguration()
 precondition(model.config.policy.mode == .automatic && !model.calibrationPending && !model.config.hardwareEnabled)
 let snapshot = model.config.policy.limit
 try Data("invalid".utf8).write(to: Configuration.url, options: .atomic)
 model.reloadExternalConfiguration()
 precondition(model.error != nil && model.config.policy.limit == snapshot && !model.config.hardwareEnabled,
  "a failed reload must retain the last configuration")
 var holding = original
 holding.hardwareEnabled = false; holding.systemActionsEnabled = false
 holding.policy.mode = .calibration; holding.policy.protectDuringCalibration = false
 holding.calibrationCheckpoint = CalibrationCheckpoint(stage: .holding, holdingSince: Date())
 try holding.save()
 let active = ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("no locks in active-calibration fixture") })
 active.resumeCalibration()
 precondition(!active.calibrationPending && active.calibration == .holding && !active.config.hardwareEnabled)
 let restart = SetChargeModeIntent(); restart.mode = .calibration
 _ = try await restart.perform(); active.reloadExternalConfiguration()
 precondition(active.calibration == .idle && !active.calibrationPending && !active.config.hardwareEnabled)
 active.refresh()
 precondition(active.calibration != .holding,
  "the engine itself must restart; clearing only the displayed phase cannot pass this check")
 let phase = active.calibration
 active.reloadExternalConfiguration()
 precondition(active.calibration == phase, "a duplicate reload must preserve the new run's engine state")
 print("Fresh calibration intents restart interrupted and holding engine state; reload guards and opt-in persistence passed in isolated configuration; no helper or lock requests")
}
