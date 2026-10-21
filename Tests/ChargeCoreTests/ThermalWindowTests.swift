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
  XCTAssertEqual(engine.decide(sample(19, 600), policy: p).phase, .pause)
  XCTAssertEqual(engine.decide(sample(19, 601), policy: p).action, .allowCharge)
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
 func testExistingThermalWindowCannotBeReplacedBySailing() {
  var p = ChargePolicy(); var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(60), policy: p).phase, .heatProtect)
  let held = engine.decide(sample(79, 10, temperature: 30), policy: p)
  XCTAssertEqual(held.phase, .heatProtect); XCTAssertEqual(held.thermalHold, true)
  XCTAssertEqual(held.sailingHold, false)
  let cooled = engine.decide(sample(79, 300, temperature: 30), policy: p)
  XCTAssertEqual(cooled.action, .allowCharge); XCTAssertEqual(cooled.phase, .charging)
 }
 func testThermalTargetComparisonDoesNotTruncateFractionalTarget() {
  var p = ChargePolicy(); p.limit = 80.8; var engine = ChargeEngine()
  _ = engine.decide(sample(60), policy: p)
  XCTAssertEqual(engine.decide(sample(80.7, 10), policy: p).phase, .heatProtect)
  let reached = engine.decide(sample(80.8, 11), policy: p)
  XCTAssertEqual(reached.phase, .pause); XCTAssertEqual(reached.thermalHold, false)
  XCTAssertEqual(reached.action, .inhibitCharge)
 }
 func testHotFullTargetBecomesPauseUntilBelowTarget() {
  var p = ChargePolicy(); p.limit = 100; p.sailing = false; var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(99), policy: p).phase, .heatProtect)
  let full = engine.decide(sample(100, 10), policy: p)
  XCTAssertEqual(full.phase, .pause); XCTAssertEqual(full.action, .inhibitCharge)
  XCTAssertEqual(full.thermalHold, false); XCTAssertEqual(full.fullChargeHold, false)
  XCTAssertEqual(engine.decide(sample(100, 310, temperature: 30), policy: p).phase, .pause)
  let resumed = engine.decide(sample(99.5, 311, temperature: 30), policy: p)
  XCTAssertEqual(resumed.action, .allowCharge); XCTAssertEqual(resumed.phase, .charging)
 }
 func testUnavailableTemperatureRetainsConfirmedWindowAndPhase() {
  var p = ChargePolicy(); p.sailing = false; var engine = ChargeEngine()
  _ = engine.decide(sample(60), policy: p)
  for temperature in [Double?.none, .some(.nan)] {
   let held = engine.decide(ChargeSample(date: start.addingTimeInterval(400), percent: 60, temperature: temperature), policy: p)
   XCTAssertEqual(held.phase, .heatProtect); XCTAssertEqual(held.thermalHold, true)
   XCTAssertEqual(held.action, .inhibitCharge)
  }
  XCTAssertEqual(engine.decide(sample(60, 401, temperature: 30), policy: p).action, .allowCharge)
 }
 func testExplicitDischargePreemptsWindowWithoutLeavingStaleWait() {
  var p = ChargePolicy(); var engine = ChargeEngine()
  _ = engine.decide(sample(60), policy: p)
  p.mode = .discharge; p.limit = 50
  XCTAssertEqual(engine.decide(sample(60, 10), policy: p).phase, .discharging)
  p.mode = .automatic; p.limit = 80
  XCTAssertEqual(engine.decide(sample(60, 11, temperature: 30), policy: p).action, .allowCharge)
 }
}
