import XCTest
@testable import ChargeCore

final class ThermalExitTests: XCTestCase {
 private let start = Date(timeIntervalSince1970: 1_700_000_000)
 private func sample(_ percent: Double, _ seconds: Double, temperature: Double = 40) -> ChargeSample {
  ChargeSample(date: start.addingTimeInterval(seconds), percent: percent, temperature: temperature)
 }
 private func policy(_ limit: Double) -> ChargePolicy {
  var value = ChargePolicy(); value.limit = limit; value.sailing = false
  return value
 }
 func testDisablingHeatAtFullTargetKeepsPauseUntilWholePercentDrops() {
  var p = policy(100); var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(99, 0), policy: p).phase, .heatProtect)
  p.heatProtection = false
  let exit = engine.decide(sample(100, 10), policy: p)
  XCTAssertEqual(exit.phase, .pause); XCTAssertEqual(exit.action, .inhibitCharge)
  for seconds in [11.0, 310, 900] {
   let held = engine.decide(sample(100, seconds, temperature: 30), policy: p)
   XCTAssertEqual(held.phase, .pause); XCTAssertEqual(held.action, .inhibitCharge)
   XCTAssertEqual(held.thermalHold, false); XCTAssertEqual(held.fullChargeHold, false)
  }
  let resumed = engine.decide(sample(99.9, 901, temperature: 30), policy: p)
  XCTAssertEqual(resumed.phase, .charging); XCTAssertEqual(resumed.action, .allowCharge)
 }
 func testDisablingHeatUsesPauseWholePercentageAfterFractionalTarget() {
  var p = policy(80.8); var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(60, 0), policy: p).phase, .heatProtect)
  p.heatProtection = false
  XCTAssertEqual(engine.decide(sample(80.7, 10), policy: p).phase, .pause)
  let sameWholePercentage = engine.decide(sample(80.1, 11, temperature: 30), policy: p)
  XCTAssertEqual(sameWholePercentage.phase, .pause)
  XCTAssertEqual(sameWholePercentage.action, .inhibitCharge)
  XCTAssertEqual(sameWholePercentage.effectiveLimit, 80.8)
  let resumed = engine.decide(sample(79.9, 12, temperature: 30), policy: p)
  XCTAssertEqual(resumed.phase, .charging); XCTAssertEqual(resumed.action, .allowCharge)
 }
 func testTargetExitUsesFractionalBoundaryThenPauseWholeBoundary() {
  let p = policy(80.8); var engine = ChargeEngine()
  _ = engine.decide(sample(60, 0), policy: p)
  XCTAssertEqual(engine.decide(sample(80.7, 10), policy: p).phase, .heatProtect)
  XCTAssertEqual(engine.decide(sample(80.8, 11), policy: p).phase, .pause)
  XCTAssertEqual(engine.decide(sample(80.1, 12, temperature: 30), policy: p).phase, .pause)
  let resumed = engine.decide(sample(79.9, 13, temperature: 30), policy: p)
  XCTAssertEqual(resumed.phase, .charging); XCTAssertEqual(resumed.action, .allowCharge)
 }
 func testModeChangeClearsThermalExitPause() {
  var p = policy(100); var engine = ChargeEngine()
  _ = engine.decide(sample(99, 0), policy: p)
  XCTAssertEqual(engine.decide(sample(100, 10), policy: p).phase, .pause)
  p.mode = .topUp; p.heatProtection = false
  let topUp = engine.decide(sample(100, 11, temperature: 30), policy: p)
  XCTAssertEqual(topUp.phase, .topUp); XCTAssertEqual(topUp.action, .allowCharge)
  XCTAssertEqual(topUp.fullChargeHold, true)
 }
 func testChangingThermalBehaviorClearsFiveMinuteTargetPause() {
  var p = policy(100); var engine = ChargeEngine()
  _ = engine.decide(sample(99, 0), policy: p)
  XCTAssertEqual(engine.decide(sample(100, 10), policy: p).phase, .pause)
  p.thermalBehavior = .degreeHysteresis
  let changed = engine.decide(sample(100, 11, temperature: 30), policy: p)
  XCTAssertEqual(changed.phase, .charging); XCTAssertEqual(changed.action, .allowCharge)
  XCTAssertEqual(changed.fullChargeHold, true)
 }
}
