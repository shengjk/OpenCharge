import XCTest
@testable import ChargeCore
final class MagSafePolicyTests: XCTestCase {
 func testSharedAppAndCLINativeEncodingPreflightIsReadOnly() {
  for command in ["magSafeGreen", "magSafeBlinkOrange"] {
   var reads = 0
   do { try MagSafePolicy.validateNativeEncoding(command: command, capabilities: { reads += 1; return "magSafe:legacy" }); XCTFail("legacy service accepted") }
   catch MagSafeEncodingError.outdatedService {} catch { XCTFail(error.localizedDescription) }
   XCTAssertEqual(reads, 1)
   do { try MagSafePolicy.validateNativeEncoding(command: command, capabilities: { "magSafe:unavailable" }); XCTFail("missing hardware accepted") }
   catch MagSafeEncodingError.unavailableInterface {} catch { XCTFail(error.localizedDescription) }
   do { try MagSafePolicy.validateNativeEncoding(command: command, capabilities: { "magSafeEncoding:aclcNativeV2" }) } catch { XCTFail(error.localizedDescription) }
  }
  var reads = 0
  do { try MagSafePolicy.validateNativeEncoding(command: "magSafeRestore", capabilities: { reads += 1; return "legacy" }) } catch { XCTFail(error.localizedDescription) }
  XCTAssertEqual(reads, 0)
 }

 func testNativeEncodingRequiresExactCapabilityAndBlinkChoiceIsFixed() {
  XCTAssertTrue(MagSafePolicy.supportsNativeEncoding("magSafe:ACLC, magSafeEncoding:aclcNativeV2"))
  for caps in ["magSafe:ACLC", "prefixmagSafeEncoding:aclcNativeV2", "magSafeEncoding:aclcNativeV20"] {
   XCTAssertFalse(MagSafePolicy.supportsNativeEncoding(caps))
  }
  XCTAssertEqual(MagSafePolicy.command(mode: .orangeBlinking, connected: true, charging: false, action: .restore,
   controlEnabled: false, blinkDischarge: false, percent: 80, target: 80), "magSafeBlinkOrange")
 }

 func testFullChargeFlagUsesGreenOnlyWithControlAndOutsideCalibration() {
  for enabled in [false, true] {
   XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: true,
    action: .allowCharge, controlEnabled: enabled, blinkDischarge: true, percent: 99.999998,
    target: 100, fullChargeHold: true), enabled ? "magSafeGreen" : "magSafeOrange")
  }
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: true,
   action: .allowCharge, controlEnabled: true, blinkDischarge: true, percent: 99.999998,
   target: 100, calibrating: true, fullChargeHold: true), "magSafeOrange")
 }

 func testPhysicalPresenceAndControlOwnershipChangeIndicator() {
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: false, charging: true, action: .allowCharge, controlEnabled: true, blinkDischarge: true, percent: 70, target: 80), "magSafeSystem")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .forceDischarge, controlEnabled: true, blinkDischarge: true, percent: 70, target: 80), "magSafeBlinkOrange")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .forceDischarge, controlEnabled: true, blinkDischarge: false, percent: 70, target: 80), "magSafeOrange")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: true, action: .inhibitCharge, controlEnabled: false, blinkDischarge: true, percent: 70, target: 80), "magSafeOrange")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: true, action: .inhibitCharge, controlEnabled: true, blinkDischarge: true, percent: 70, target: 80), "magSafeOrange")
 }
 func testSystemAndOffModesOverrideChargeDecision() {
  XCTAssertEqual(MagSafePolicy.command(mode: .system, connected: true, charging: true, action: .forceDischarge, controlEnabled: true, blinkDischarge: true, percent: 70, target: 80), "magSafeSystem")
  XCTAssertEqual(MagSafePolicy.command(mode: .off, connected: true, charging: true, action: .forceDischarge, controlEnabled: true, blinkDischarge: true, percent: 70, target: 80), "magSafeOff")
 }
 func testHeatSailingTopUpAndCalibrationHaveDifferentIndicators() {
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .inhibitCharge, controlEnabled: true, blinkDischarge: true, percent: 78, target: 80, sailingHold: true), "magSafeGreen")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .inhibitCharge, controlEnabled: true, blinkDischarge: true, percent: 78, target: 80), "magSafeOrange")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .allowCharge, controlEnabled: true, blinkDischarge: true, percent: 100, target: 100), "magSafeGreen")
  XCTAssertEqual(MagSafePolicy.command(mode: .chargeState, connected: true, charging: false, action: .allowCharge, controlEnabled: true, blinkDischarge: true, percent: 100, target: 100, calibrating: true), "magSafeOrange")
  var engine = ChargeEngine(); let decision = engine.decide(ChargeSample(percent: 78, temperature: 25), policy: ChargePolicy())
  XCTAssertEqual(decision.sailingHold, true)
 }

}
