import XCTest
@testable import ChargeCore

final class FirmwareLimitProjectionTests: XCTestCase {
 func testSailingSleepUsesLowerEvenWithNoChargeControlReading() {
  let policy = ChargePolicy()
  for charging in [true, false, nil] as [Bool?] {
   XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: charging), 75)
  }
 }
 func testSleepAndExitHaveDifferentSailingFlagInputs() {
  var policy = ChargePolicy(); policy.sailing = false
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: true), 75)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: true), 80)
 }
 func testLowerBelowTwentyFallsThroughInsteadOfClamping() {
  var policy = ChargePolicy(); policy.limit = 25; policy.sailingWidth = 6
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: false), 15)
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: true), 25)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: true), 25)
 }
 func testTwentyBoundaryAndFloatSubtractionPrecedeTruncation() {
  var policy = ChargePolicy(); policy.limit = 21; policy.sailingWidth = 1.0000001
  // Float subtraction rounds to exactly 20; Double subtraction is below 20.
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: false), 20)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: true), 20)
  policy.limit = 80.9; policy.sailingWidth = 5.2
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: true), 75)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .charging, active: true), 80)
 }
 func testOrdinarySleepUsesControlStateRatherThanModeName() {
  let policy = ChargePolicy()
  for phase in [PolicyPhase.charging, .pause, .topUp, .calibration, .discharging] {
   XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: phase, smcCharging: true), 80)
   XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: phase, smcCharging: false), 15)
   XCTAssertNil(FirmwareLimitProjection.onSleep(policy: policy, phase: phase, smcCharging: nil))
  }
 }
 func testHeatStateUsesDailyTargetForBothControlStates() {
  let policy = ChargePolicy()
  for charging in [true, false, nil] as [Bool?] {
   XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .heatProtect, smcCharging: charging), 80)
  }
 }
 func testSleepAndQuitFlagsDoNotReplaceNumericFirmwareTargets() {
  var policy = ChargePolicy(); policy.stopInSleep = true; policy.stopOnQuit = true
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .charging, smcCharging: true), 80)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .charging, active: true), 80)
 }
 func testInactiveAndExplicitResetSelectFullIndependentlyOfPolicy() {
  var policy = ChargePolicy(); policy.limit = .nan; policy.sailingWidth = .infinity
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: false), 100)
  XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: true, resetToFull: true), 100)
 }
 func testInvalidTargetsAndUnsupportedStateHaveNoProjection() {
  for limit in [Double.nan, .infinity, -.infinity, 19.99, 100.01] {
   var policy = ChargePolicy(); policy.limit = limit
   XCTAssertNil(FirmwareLimitProjection.onSleep(policy: policy, phase: .charging, smcCharging: true))
   XCTAssertNil(FirmwareLimitProjection.onExit(policy: policy, phase: .charging, active: true))
  }
  let policy = ChargePolicy()
  XCTAssertNil(FirmwareLimitProjection.onSleep(policy: policy, phase: .intelMode, smcCharging: true))
  XCTAssertNil(FirmwareLimitProjection.onExit(policy: policy, phase: .intelMode, active: true))
 }
 func testOnlySailingProjectionReadsSailingWidth() {
  for width in [Double.nan, .infinity, 0, 21] {
   var policy = ChargePolicy(); policy.sailingWidth = width
   XCTAssertNil(FirmwareLimitProjection.onSleep(policy: policy, phase: .sailing, smcCharging: true))
   XCTAssertNil(FirmwareLimitProjection.onExit(policy: policy, phase: .sailing, active: true))
   XCTAssertEqual(FirmwareLimitProjection.onSleep(policy: policy, phase: .heatProtect, smcCharging: false), 80)
   XCTAssertEqual(FirmwareLimitProjection.onExit(policy: policy, phase: .charging, active: true), 80)
  }
 }
}
