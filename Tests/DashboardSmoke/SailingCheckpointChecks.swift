import Foundation
import ChargeCore
import ChargeHardware

@MainActor func sailingCheckpointChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider }
 func fixture(_ checkpoint: Bool?, percent: Double) throws -> ChargeModel {
  var config = Configuration(); config.sailingCheckpoint = checkpoint
  config.historyEnabled = false; config.hardwareEnabled = false; config.systemActionsEnabled = false
  try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in sailing checkpoint fixture") },
   readBattery: { BatteryReading(percent: percent, temperature: 30, connected: true, charging: false) })
 }
 for checkpoint: Bool? in [nil, false, true] {
  let model = try fixture(checkpoint, percent: 78)
  precondition(model.decision.phase == (checkpoint == false ? .charging : .sailing))
  precondition(model.config.sailingCheckpoint == checkpoint)
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 let charging = try fixture(nil, percent: 70)
 precondition(charging.decision.phase == .charging)
 let savedCharging = try Configuration.load(); precondition(savedCharging.sailingCheckpoint == false)
 // An external command reads and writes the current checkpoint with its settings.
 var incoming = try Configuration.load(); incoming.notifications = true; try incoming.save()
 charging.reloadExternalConfiguration()
 charging.evaluatePolicy(ChargeSample(percent: 78, temperature: 30))
 precondition(charging.decision.phase == .charging && charging.config.sailingCheckpoint == false)
 let restored = try fixture(try Configuration.load().sailingCheckpoint, percent: 78)
 precondition(restored.decision.phase == .charging)
 // Stable samples must not churn the configuration file or its own notifications.
 let stamp = Date(timeIntervalSince1970: 1_700_000_000)
 try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: Configuration.url.path)
 restored.refresh(); restored.refresh()
 let modified = try FileManager.default.attributesOfItem(atPath: Configuration.url.path)[.modificationDate] as! Date
 precondition(abs(modified.timeIntervalSince(stamp)) < 1)
 incoming = try Configuration.load(); incoming.setChargeLimit(81); try incoming.save()
 restored.reloadExternalConfiguration(); restored.refresh()
 precondition(restored.config.sailingCheckpoint == true && restored.decision.phase == .sailing)
 let savedHolding = try Configuration.load(); precondition(savedHolding.sailingCheckpoint == true)
 let roundTrip = try fixture(false, percent: 78)
 roundTrip.config.setChargeLimit(81); roundTrip.config.setChargeLimit(80)
 roundTrip.save(); roundTrip.refresh()
 precondition(roundTrip.decision.phase == .sailing && roundTrip.config.sailingCheckpoint == true)
 let externalRoundTrip = try fixture(false, percent: 78)
 incoming = try Configuration.load(); incoming.setChargeLimit(81); try incoming.save()
 incoming = try Configuration.load(); incoming.setChargeLimit(80); try incoming.save()
 externalRoundTrip.reloadExternalConfiguration(); externalRoundTrip.refresh()
 precondition(externalRoundTrip.decision.phase == .sailing && externalRoundTrip.config.sailingCheckpoint == true)
 // A calibration interruption remains monitoring-only while carrying this independent record.
 var calibration = try Configuration.load(); calibration.sailingCheckpoint = false
 calibration.policy.mode = .calibration
 calibration.calibrationCheckpoint = CalibrationCheckpoint(stage: .draining)
 try calibration.save()
 let pending = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  screenLockRequest: { preconditionFailure("no locks in sailing calibration fixture") },
  readBattery: { BatteryReading(percent: 78, temperature: 30, connected: true, charging: false) })
 precondition(pending.calibrationPending && !pending.config.hardwareEnabled)
 pending.resumeCalibration()
 precondition(pending.calibration == .draining && pending.config.sailingCheckpoint == false && !pending.config.hardwareEnabled)
 calibration.calibrationCheckpoint = nil; try calibration.save()
 pending.reloadExternalConfiguration(); pending.refresh()
 precondition(pending.calibration == .filling && pending.config.sailingCheckpoint == false && !pending.config.hardwareEnabled)
 print("Sailing startup restores independent charge/hold history; external limits, stable saves and calibration reconstruction checked with injected telemetry and monitoring-only configuration")
}
