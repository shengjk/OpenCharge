import XCTest
@testable import ChargeCore

final class PolicyPhaseTests: XCTestCase {
 func testOrdinaryLifecycleRetainsPhaseAcrossUnavailableTelemetry() {
  var p = ChargePolicy(); var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(ChargeSample(percent: 79, temperature: 30), policy: p).phase, .sailing)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 75, temperature: 30), policy: p).phase, .charging)
  XCTAssertEqual(engine.decide(ChargeSample(percent: .nan), policy: p).phase, .charging)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 79, temperature: 30), policy: p).phase, .charging)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 30), policy: p).phase, .sailing)
  p.sailing = false
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 30), policy: p).phase, .pause)
  XCTAssertEqual(engine.phase, .pause)
 }
 func testFullAndTopUpPhasesRemainDistinctFromObservedFlow() {
  var p = ChargePolicy(); p.limit = 100; var engine = ChargeEngine()
  let full = engine.decide(ChargeSample(percent: 100, temperature: 30), policy: p)
  XCTAssertEqual(full.phase, .charging); XCTAssertEqual(full.fullChargeHold, true)
  p.mode = .topUp
  XCTAssertEqual(engine.decide(ChargeSample(percent: 100, temperature: 30), policy: p).phase, .topUp)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 99, connected: false, physicalAdapterConnected: false), policy: p).phase, .sailing)
  XCTAssertEqual(engine.completedMode, .topUp)
 }
 func testThermalPauseAndManualDischargeHaveDifferentPhases() {
  var p = ChargePolicy(); p.thermalBehavior = .degreeHysteresis; var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(ChargeSample(percent: 60, temperature: 40), policy: p).phase, .heatProtect)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 60, temperature: 30), policy: p).phase, .charging)
  p.mode = .discharge
  XCTAssertEqual(engine.decide(ChargeSample(percent: 90, temperature: 40), policy: p).phase, .discharging)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 40), policy: p).phase, .sailing)
  XCTAssertEqual(engine.completedMode, .discharge)
  p.mode = .paused
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 40), policy: p).phase, .pause)
 }
 func testCurrentPauseResumesAndCalibrationDoesNotBecomeOrdinaryDischarge() {
  var p = ChargePolicy(); p.mode = .paused; p.pauseAtCurrent = true; var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 30), policy: p).phase, .pause)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 79, temperature: 30), policy: p).phase, .sailing)
  p.mode = .calibration; p.protectDuringCalibration = true
  engine = ChargeEngine(checkpoint: CalibrationCheckpoint(stage: .draining))
  XCTAssertEqual(engine.phase, .calibration)
  let thermal = engine.decide(ChargeSample(percent: 60, temperature: 40), policy: p)
  XCTAssertEqual(thermal.phase, .calibration); XCTAssertEqual(thermal.thermalHold, true)
  p.protectDuringCalibration = false
  let draining = engine.decide(ChargeSample(percent: 60, temperature: 40), policy: p)
  XCTAssertEqual(draining.phase, .calibration); XCTAssertEqual(draining.action, .forceDischarge)
  engine = ChargeEngine(checkpoint: CalibrationCheckpoint(stage: .returning))
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80, temperature: 30), policy: p).phase, .sailing)
 }
 func testLegacyDecisionDecodesWithoutPhaseAndNewPhaseRoundTrips() {
  do {
   let legacy = Data(#"{"action":"inhibitCharge","reason":"old","effectiveLimit":80}"#.utf8)
   let oldValue = try JSONDecoder().decode(Decision.self, from: legacy)
   XCTAssertNil(oldValue.phase)
   for phase in PolicyPhase.allCases {
    var value = Decision(.restore, "unrelated presentation text", limit: 80); value.phase = phase
    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Decision.self, from: encoded)
    XCTAssertEqual(decoded.phase, phase)
   }
  } catch { XCTFail(error.localizedDescription) }
 }
}
