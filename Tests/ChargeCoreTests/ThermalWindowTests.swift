import XCTest
@testable import ChargeCore

final class ThermalWindowTests: XCTestCase {
 private let start = Date(timeIntervalSince1970: 1_700_000_000)
 private func sample(_ percent: Double, _ seconds: Double = 0, temperature: Double = 40) -> ChargeSample {
  ChargeSample(date: start.addingTimeInterval(seconds), percent: percent, temperature: temperature)
 }
 func testExistingWindowSurvivesEntryExemptionUntilEmergencyExit() {
  var p = ChargePolicy(); p.sailing = false; var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(21), policy: p).phase, .heatProtect)
  for percent in [20.0, 19, 15] {
   let held = engine.decide(sample(percent, 100), policy: p)
   XCTAssertEqual(held.action, .inhibitCharge); XCTAssertEqual(held.thermalHold, true)
   XCTAssertEqual(held.phase, .heatProtect)
  }
  let emergency = engine.decide(sample(14.9, 101), policy: p)
  XCTAssertEqual(emergency.action, .allowCharge); XCTAssertEqual(emergency.thermalHold, false)
  XCTAssertEqual(emergency.phase, .charging)
  XCTAssertEqual(engine.decide(sample(20, 102), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(20.1, 103), policy: p).phase, .heatProtect)
 }
 func testCoolingAtLowChargeStillWaitsUntilWindowEnds() {
  var p = ChargePolicy(); p.sailing = false; var engine = ChargeEngine()
  _ = engine.decide(sample(21), policy: p)
  XCTAssertEqual(engine.decide(sample(19, 299, temperature: 30), policy: p).thermalHold, true)
  XCTAssertEqual(engine.decide(sample(19, 300, temperature: 30), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(19, 301), policy: p).thermalHold, false)
 }
 func testHotWindowRenewsAtLowChargeAndOptOutReleasesIt() {
  var p = ChargePolicy(); p.sailing = false; var engine = ChargeEngine()
  _ = engine.decide(sample(21), policy: p)
  XCTAssertEqual(engine.decide(sample(19, 300), policy: p).thermalHold, true)
  XCTAssertEqual(engine.decide(sample(19, 599, temperature: 30), policy: p).thermalHold, true)
  p.heatProtection = false
  XCTAssertEqual(engine.decide(sample(19, 600), policy: p).action, .allowCharge)
 }
 func testSwitchFromDegreeHysteresisDoesNotCreateLowChargeWindow() {
  var p = ChargePolicy(); p.sailing = false; p.thermalBehavior = .degreeHysteresis
  var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(21), policy: p).thermalHold, true)
  p.thermalBehavior = .fiveMinuteWindows
  let low = engine.decide(sample(19, 1), policy: p)
  XCTAssertEqual(low.action, .allowCharge); XCTAssertEqual(low.thermalHold, false)
  XCTAssertEqual(low.phase, .charging)
 }
 func testFreshLowChargeAndOtherThermalModeDoNotInheritWindow() {
  var p = ChargePolicy(); p.sailing = false
  for percent in [15.0, 19, 20] {
   var fresh = ChargeEngine()
   XCTAssertEqual(fresh.decide(sample(percent), policy: p).action, .allowCharge)
  }
  var engine = ChargeEngine(); _ = engine.decide(sample(21), policy: p)
  p.mode = .paused
  XCTAssertEqual(engine.decide(sample(19, 1), policy: p).phase, .pause)
  p.mode = .automatic
  XCTAssertEqual(engine.decide(sample(19, 2), policy: p).action, .allowCharge)
  _ = engine.decide(sample(21, 3), policy: p)
  p.thermalBehavior = .degreeHysteresis
  XCTAssertEqual(engine.decide(sample(19, 4), policy: p).action, .allowCharge)
 }
}
