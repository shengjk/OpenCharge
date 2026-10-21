import Foundation
import AppIntents
import ChargeCore
import ChargeHardware

@main @MainActor struct AppIntentsValidation {
 static func main() async {
  var failures = 0
  PauseIntentTelemetry.read = { BatteryReading(percent: 75.6, connected: true, charging: true) }
  defer { PauseIntentTelemetry.read = { try BatteryTelemetryReader.read() } }
  for value in [-100, 0, 19, 101, Int.max] {
   let intent = SetChargeLimitIntent(); intent.percentage = value
   do { _ = try await intent.perform(); failures += 1; print("FAIL accepted invalid charge limit \(value)") }
   catch { print("PASS rejected invalid charge limit \(value)") }
  }
  for value in AutomationMode.allCases {
   if ChargeMode(rawValue: value.rawValue) == nil { failures += 1; print("FAIL mode mapping \(value)") }
  }
  let intent = SetChargeLimitIntent()
  if intent.percentage != 80 { failures += 1; print("FAIL default charge limit") }
  guard let fixture = ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"], fixture.contains("/.build/appintents-validation/") else { print("FAIL isolated fixture missing"); exit(1) }
  do {
   var base = Configuration(); try base.save()
   let previousProvider = PolicyStateRuntime.provider
   defer { PolicyStateRuntime.provider = previousProvider }
   let originalBytes = try Data(contentsOf: Configuration.url)
   var livePhase = PolicyPhase.pause
   PolicyStateRuntime.provider = { livePhase }
   for phase in PolicyPhase.allCases {
    livePhase = phase
    let result = try await GetPolicyStateIntent().perform()
    if result.value != phase.rawValue { failures += 1; print("FAIL live policy state mapping \(phase)") }
   }
   PolicyStateRuntime.provider = nil
   do { _ = try await GetPolicyStateIntent().perform(); failures += 1; print("FAIL unavailable policy state fabricated a result") } catch {}
   PolicyStateRuntime.provider = { throw HelperError.rejected("fixture unavailable") }
   do { _ = try await GetPolicyStateIntent().perform(); failures += 1; print("FAIL failed policy provider fabricated a result") } catch {}
   if try Data(contentsOf: Configuration.url) != originalBytes { failures += 1; print("FAIL read-only policy getter changed configuration") }
   print("PASS live policy getter, unavailable-provider errors and configuration isolation")
   let limit = SetChargeLimitIntent(); limit.percentage = 75; _ = try await limit.perform()
   if try Configuration.load().policy.limit != 75 { failures += 1; print("FAIL valid limit did not persist") }
   _ = try await StopChargingIntent().perform()
   let paused = try Configuration.load()
   if paused.policy.mode != .paused || paused.policy.pauseAtCurrent != true || paused.policy.limit != Double(Float(75.6)) { failures += 1; print("FAIL pause did not set current percentage") }
   for percent in [19.9, 101, Double.nan, .infinity] {
    PauseIntentTelemetry.read = { BatteryReading(percent: percent, connected: true, charging: true) }
    let before = try Configuration.load().policy
    do { _ = try await StopChargingIntent().perform(); failures += 1; print("FAIL invalid pause accepted") } catch {}
    if try Configuration.load().policy != before { failures += 1; print("FAIL invalid pause changed policy") }
   }
   var hardwarePause = try Configuration.load(); hardwarePause.policy.useHardwarePercent = true
   hardwarePause.policy.mode = .calibration; hardwarePause.calibrationCheckpoint = CalibrationCheckpoint(stage: .holding)
   try hardwarePause.save()
   PauseIntentTelemetry.read = { BatteryReading(percent: 80, connected: true, charging: false, hardwarePercent: 55.8) }
   _ = try await StopChargingIntent().perform()
   let hardwarePaused = try Configuration.load()
   if hardwarePaused.policy.limit != Double(Float(55.8)) || hardwarePaused.policy.mode != .paused || hardwarePaused.policy.pauseAtCurrent != true || hardwarePaused.calibrationCheckpoint != nil { failures += 1; print("FAIL hardware pause or calibration cancellation") }
   PauseIntentTelemetry.read = { BatteryReading(percent: 80, connected: true, charging: false) }
   do { _ = try await StopChargingIntent().perform(); failures += 1; print("FAIL missing hardware percentage accepted") } catch {}
   let indefinite = SetChargeModeIntent(); indefinite.mode = .paused; _ = try await indefinite.perform()
   if try Configuration.load().policy.pauseAtCurrent != nil { failures += 1; print("FAIL explicit manual pause retained temporary semantics") }
   print("PASS current-percentage pause, invalid-reading isolation and calibration cancellation")
   _ = try await StartCalibrationIntent().perform()
   let blocked = SetChargeLimitIntent(); blocked.percentage = 80
   do { _ = try await blocked.perform(); failures += 1; print("FAIL changed limit during calibration") } catch { print("PASS limit blocked during calibration") }
   base = try Configuration.load(); base.policy.mode = .automatic; try base.save()
   for color in AutomationLEDColor.allCases {
    let led = SetMagSafeLEDIntent(); led.color = color; _ = try await led.perform()
    if try Configuration.load().magSafeMode?.rawValue != color.rawValue { failures += 1; print("FAIL LED setter mapping") }
   }
   print("PASS valid setters and LED colors persisted only in isolated fixture")
  } catch { failures += 1; print("FAIL valid setter: \(error.localizedDescription)") }
  print("App Intents validation: \(failures) failures. Only isolated fixture configuration was changed; no hardware executed.")
  exit(failures == 0 ? 0 : 1)
 }
}
