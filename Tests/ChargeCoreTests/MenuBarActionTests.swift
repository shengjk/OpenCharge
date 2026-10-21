import XCTest
@testable import ChargeCore

final class MenuBarActionTests: XCTestCase {
 func testUnknownPreferenceDefaultsToPopover() {
  for value: String? in [nil, "", "unknown", "1", "true"] { XCTAssertEqual(MenuBarRightClickAction.stored(value), .popover) }
  for value in MenuBarRightClickAction.allCases { XCTAssertEqual(MenuBarRightClickAction.stored(value.rawValue), value) }
 }
 func testChargeToggleMatrixUsesOrdinaryFullCharging() {
  for phase in PolicyPhase.allCases {
   for limit in [80.0, 99.9, 100.0] {
    for percent in [0.0, 19.9, 20.0, 57.25, 100.0] {
     var policy = ChargePolicy(); policy.limit = limit; policy.mode = .calibration
     policy.departure = Date(timeIntervalSince1970: 1234)
     let pausable = phase == .charging || phase == .topUp || (phase == .heatProtect && limit == 100)
     do {
      let result = try MenuBarChargeToggleRequest.apply(phase: phase, percent: percent, policy: &policy)
      if pausable && Float(percent) >= 20 {
       XCTAssertEqual(result, .pausedAtCurrent(Double(Float(percent))))
       XCTAssertEqual(policy.mode, .paused); XCTAssertEqual(policy.pauseAtCurrent, true)
       XCTAssertEqual(policy.limit, Double(Float(percent)))
      } else {
       XCTAssertEqual(result, .chargingToFull); XCTAssertEqual(policy.mode, .automatic)
       XCTAssertEqual(policy.limit, 100); XCTAssertNil(policy.pauseAtCurrent)
      }
      XCTAssertNil(policy.departure)
     } catch { XCTFail(error.localizedDescription) }
    }
   }
  }
 }
 func testInvalidChargeToggleDoesNotMutatePolicy() {
  for percent in [Double.nan, .infinity, -.infinity, -1, 101] {
   var policy = ChargePolicy(); let original = policy
   do { _ = try MenuBarChargeToggleRequest.apply(phase: .charging, percent: percent, policy: &policy); XCTFail("invalid toggle accepted") }
   catch { XCTAssertEqual(policy, original) }
  }
 }
 func testExplicitFullChargingAvoidsSailingHoldAcrossUpdates() {
  var policy = ChargePolicy(); var engine = ChargeEngine(sailingCheckpoint: true)
  _ = engine.decide(ChargeSample(percent: 99.8, temperature: 30), policy: policy)
  policy.limit = 100; engine.startChargingAtFullTarget()
  for percent in [99.8, 99.9, 100, 99.8] {
   let result = engine.decide(ChargeSample(percent: percent, temperature: 30), policy: policy)
   XCTAssertEqual(result.action, .allowCharge); XCTAssertEqual(result.phase, .charging)
  }
  XCTAssertEqual(policy.mode, .automatic)
 }
}
