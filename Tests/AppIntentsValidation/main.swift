import Foundation
import AppIntents
import ChargeCore

@main struct AppIntentsValidation {
 static func main() async {
  var failures = 0
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
   let limit = SetChargeLimitIntent(); limit.percentage = 75; _ = try await limit.perform()
   if try Configuration.load().policy.limit != 75 { failures += 1; print("FAIL valid limit did not persist") }
   _ = try await StopChargingIntent().perform()
   if try Configuration.load().policy.mode != .paused { failures += 1; print("FAIL pause did not persist") }
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
