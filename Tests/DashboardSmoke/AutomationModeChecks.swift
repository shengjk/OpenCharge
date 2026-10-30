import Foundation
import AppIntents
import ChargeCore
import ChargeHardware

@MainActor func automationModeChecks() async throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.automation-mode-check."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); PolicyStateRuntime.provider = provider; defaults.removePersistentDomain(forName:suite) }
 for mode in [AutomationMode.automatic,.paused,.discharge,.topUp,.calibration] {
  var config = Configuration();config.historyEnabled=false;config.notifications=false;config.systemActionsEnabled=false
  config.policy.mode = .calibration;config.policy.pauseAtCurrent=true
  config.calibrationCheckpoint=CalibrationCheckpoint(stage:.draining)
  try config.save()
  var intent=SetChargeModeIntent();intent.mode=mode
  _ = try await intent.perform()
  let saved=try Configuration.load()
  precondition(saved.policy.mode.rawValue==mode.rawValue && saved.calibrationCheckpoint==nil && saved.policy.pauseAtCurrent==nil && !saved.hardwareEnabled)
 }
 var config=Configuration();config.historyEnabled=false;config.notifications=false;config.systemActionsEnabled=false
 config.policy.mode = .calibration;config.calibrationCheckpoint=CalibrationCheckpoint(stage:.draining);try config.save()
 let model=ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{BatteryReading(percent:50,connected:true,charging:false)})
 precondition(model.calibrationPending && model.calibration == .draining)
 var intent=SetChargeModeIntent();intent.mode = .calibration
 _ = try await intent.perform()
 model.reloadExternalConfiguration()
 precondition(!model.calibrationPending && model.calibration == .idle)
 model.evaluatePolicy(ChargeSample(percent:50,temperature:25,connected:true))
 precondition(model.calibration == .filling && !model.config.hardwareEnabled)
 config.policy.mode = .calibration; config.policy.pauseAtCurrent = true
 config.calibrationCheckpoint = CalibrationCheckpoint(stage: .draining); try config.save()
 model.reloadExternalConfiguration()
 _ = try await StartCalibrationIntent().perform()
 model.reloadExternalConfiguration()
 precondition(model.calibration == .idle && !model.calibrationPending && model.config.policy.pauseAtCurrent == nil)
 model.evaluatePolicy(ChargeSample(percent:50,temperature:25,connected:true))
 precondition(model.calibration == .filling && !model.config.hardwareEnabled)
 print("PASS explicit automation mode: actual intent clears old calibration/pause state for all modes; interrupted production model starts a new filling phase after reload; fake telemetry, no helper or global configuration")
}
