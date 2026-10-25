import Foundation
import ChargeCore
import ChargeHardware

@main struct AutomationAvailability {
 @MainActor static func main() async throws {
  let previous = PolicyStateRuntime.provider, telemetry = PauseIntentTelemetry.read
  defer { PolicyStateRuntime.provider = previous; PauseIntentTelemetry.read = telemetry }
  PolicyStateRuntime.provider = nil
  do { _ = try PolicyStateRuntime.read(); preconditionFailure("Unavailable provider fabricated a state") }
  catch HelperError.rejected { }
  var expected = PolicyPhase.pause
  PolicyStateRuntime.provider = { expected }
  for phase in PolicyPhase.allCases {
   expected = phase
   let actual = try PolicyStateRuntime.read()
   precondition(actual == phase)
   if #available(macOS 13.0, *) {
    let result = try await GetPolicyStateIntent().perform()
    precondition(result.value == phase.rawValue)
   }
  }
  PolicyStateRuntime.provider = { throw HelperError.unavailable }
  do { _ = try PolicyStateRuntime.read(); preconditionFailure("Failed provider fabricated a state") }
  catch HelperError.unavailable { }
  PauseIntentTelemetry.read = { BatteryReading(percent:75.6,connected:true,charging:false,hardwarePercent:55.8) }
  let reading = try PauseIntentTelemetry.read()
  precondition(reading.percent == 75.6 && reading.hardwarePercent == 55.8)
  if #available(macOS 12.0, *) {
   precondition(LowPowerObservation.current != nil)
   precondition(LowPowerObservation.changeNotification == .NSProcessInfoPowerStateDidChange)
  } else {
   precondition(LowPowerObservation.current == nil && LowPowerObservation.changeNotification == nil)
  }
  for style in DateDisplay.Style.allCases {
   precondition(!DateDisplay.string(Date(timeIntervalSince1970:1782630145),style:style).isEmpty)
  }
  try menuBarAppearanceChecks()
  print("PASS macOS 11-target automation binary: injected providers, errors and guarded current-system policy getter; no configuration, hardware or indexing changes")
 }
}
