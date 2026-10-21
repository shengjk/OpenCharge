import XCTest
@testable import ChargeCore

final class SailingCheckpointTests: XCTestCase {
 private func sample(_ percent: Double, connected: Bool = true, temperature: Double = 30) -> ChargeSample {
  ChargeSample(percent: percent, temperature: temperature, connected: connected)
 }
 func testMissingCheckpointRetainsFreshHold() {
  var engine = ChargeEngine()
  XCTAssertNil(engine.sailingCheckpoint)
  XCTAssertEqual(engine.decide(sample(78), policy: ChargePolicy()).phase, .sailing)
  XCTAssertNil(engine.sailingCheckpoint)
 }
 func testRestartRetainsChargingHistoryInsideBand() {
  let p = ChargePolicy(); var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(70), policy: p).phase, .charging)
  XCTAssertEqual(engine.sailingCheckpoint, false)
  XCTAssertEqual(engine.decide(sample(78), policy: p).phase, .charging)
  var resumed = ChargeEngine(sailingCheckpoint: engine.sailingCheckpoint)
  XCTAssertEqual(resumed.decide(sample(78), policy: p).phase, .charging)
 }
 func testRestartRetainsReachedTargetHistory() {
  let p = ChargePolicy(); var engine = ChargeEngine(sailingCheckpoint: false)
  XCTAssertEqual(engine.decide(sample(80), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.sailingCheckpoint, true)
  var resumed = ChargeEngine(sailingCheckpoint: engine.sailingCheckpoint)
  XCTAssertEqual(resumed.decide(sample(78), policy: p).phase, .sailing)
 }
 func testFractionalRuntimeAndWholeCheckpointRemainIndependent() {
  var p = ChargePolicy(); p.limit = 80.8; p.sailingWidth = 5
  var engine = ChargeEngine(sailingCheckpoint: true)
  XCTAssertEqual(engine.decide(sample(75.9), policy: p).phase, .sailing)
  XCTAssertEqual(engine.sailingCheckpoint, false)
  XCTAssertEqual(engine.decide(sample(75.9), policy: p).phase, .sailing)
  var resumed = ChargeEngine(sailingCheckpoint: engine.sailingCheckpoint)
  XCTAssertEqual(resumed.decide(sample(75.9), policy: p).phase, .charging)
 }
 func testLowerBranchPrecedesUpperAtMinimumTarget() {
  for limit in [20.0, 20.8] {
   var p = ChargePolicy(); p.limit = limit
   var engine = ChargeEngine(sailingCheckpoint: true)
   _ = engine.decide(sample(20.9), policy: p)
   XCTAssertEqual(engine.sailingCheckpoint, false)
   _ = engine.decide(sample(21), policy: p)
   XCTAssertEqual(engine.sailingCheckpoint, true)
  }
 }
 func testTopUpKeepsLowerCheckpointButRecordsDailyUpper() {
  var p = ChargePolicy(); p.mode = .topUp
  var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(50), policy: p).phase, .topUp)
  XCTAssertNil(engine.sailingCheckpoint)
  _ = engine.decide(sample(80), policy: p)
  XCTAssertEqual(engine.sailingCheckpoint, true)
  _ = engine.decide(sample(50), policy: p)
  XCTAssertEqual(engine.sailingCheckpoint, true)
 }
 func testResultingHeatStateDoesNotReceiveTopUpException() {
  var p = ChargePolicy(); p.mode = .topUp; p.protectDuringTopUp = true
  var engine = ChargeEngine(sailingCheckpoint: true)
  XCTAssertEqual(engine.decide(sample(50, temperature: 40), policy: p).phase, .heatProtect)
  XCTAssertEqual(engine.sailingCheckpoint, false)
 }
 func testDepartureKeepsCheckpointBasedOnDailyTarget() {
  var p = ChargePolicy(); p.departure = Date().addingTimeInterval(60); p.departureTarget = 100
  var engine = ChargeEngine(sailingCheckpoint: false)
  XCTAssertEqual(engine.decide(sample(85), policy: p).effectiveLimit, 100)
  XCTAssertEqual(engine.sailingCheckpoint, true)
 }
 func testOtherStatesAlsoRecordSampleHistory() {
  for mode in [ChargeMode.paused, .calibration, .discharge, .automatic] {
   var p = ChargePolicy(); p.mode = mode; p.sailing = false
   var engine = ChargeEngine(sailingCheckpoint: true)
   _ = engine.decide(sample(50), policy: p)
   XCTAssertEqual(engine.sailingCheckpoint, false)
   _ = engine.decide(sample(85), policy: p)
   XCTAssertEqual(engine.sailingCheckpoint, true)
  }
 }
 func testInvalidSamplesDoNotChangeRecord() {
  for value in [Double.nan, .infinity, -1, 101] {
   var engine = ChargeEngine(sailingCheckpoint: true)
   XCTAssertEqual(engine.decide(sample(value), policy: ChargePolicy()).action, .restore)
   XCTAssertEqual(engine.sailingCheckpoint, true)
  }
 }
 func testUnpluggedSampleStillRecordsWithoutActuation() {
  var engine = ChargeEngine(sailingCheckpoint: true)
  XCTAssertEqual(engine.decide(sample(70, connected: false), policy: ChargePolicy()).action, .restore)
  XCTAssertEqual(engine.sailingCheckpoint, false)
 }
 func testChangedDailyTargetResetsInBandRecord() {
  var p = ChargePolicy(); var engine = ChargeEngine(sailingCheckpoint: false)
  XCTAssertEqual(engine.decide(sample(78), policy: p).phase, .charging)
  p.limit = 81
  XCTAssertEqual(engine.decide(sample(78), policy: p).phase, .sailing)
  XCTAssertEqual(engine.sailingCheckpoint, true)
 }
 func testExplicitTargetEventSurvivesAChangeBackToPreviousValue() {
  let p = ChargePolicy(); var engine = ChargeEngine(sailingCheckpoint: false)
  XCTAssertEqual(engine.decide(sample(78), policy: p).phase, .charging)
  engine.chargeLimitChanged()
  XCTAssertEqual(engine.decide(sample(78), policy: p).phase, .sailing)
  XCTAssertEqual(engine.sailingCheckpoint, true)
 }
 func testTargetChangeAtFullHoldsAcrossUpdatesAndRestart() {
  for sailing in [false, true] {
   var p = ChargePolicy(); p.sailing = sailing; p.heatProtection = false
   var engine = ChargeEngine(sailingCheckpoint: false)
   _ = engine.decide(sample(100), policy: p)
   p.limit = 100
   for _ in 0..<2 {
    let decision = engine.decide(sample(100), policy: p)
    XCTAssertEqual(decision.action, .inhibitCharge)
    XCTAssertEqual(decision.phase, sailing ? .sailing : .pause)
    XCTAssertEqual(decision.fullChargeHold, false)
   }
   var restarted = ChargeEngine(sailingCheckpoint: engine.sailingCheckpoint)
   XCTAssertEqual(restarted.decide(sample(100), policy: p).action, .inhibitCharge)
   XCTAssertEqual(restarted.decide(sample(99), policy: p).action, sailing ? .inhibitCharge : .allowCharge)
  }
 }
 func testTargetEventUsesFractionalAutomaticDischargeOnce() {
  var p = ChargePolicy(); p.limit = 81; p.automaticDischarge = true
  var engine = ChargeEngine(sailingCheckpoint: false)
  _ = engine.decide(sample(80.9), policy: p)
  p.limit = 80.8
  XCTAssertEqual(engine.decide(sample(80.9), policy: p).phase, .discharging)
  XCTAssertEqual(engine.decide(sample(80.9), policy: p).action, .inhibitCharge)
  var restarted = ChargeEngine(sailingCheckpoint: true)
  XCTAssertEqual(restarted.decide(sample(80.9), policy: p).action, .inhibitCharge)
 }
 func testNonautomaticEarlyReturnsClearTargetEvent() {
  for mode in [ChargeMode.paused, .topUp, .discharge] {
   var p = ChargePolicy(); p.limit = 100; p.heatProtection = false
   var engine = ChargeEngine(); engine.chargeLimitChanged()
   XCTAssertEqual(engine.decide(sample(100), policy: p).action, .inhibitCharge)
   p.mode = mode
   _ = engine.decide(sample(100, connected: mode == .paused), policy: p)
   p.mode = .automatic
   XCTAssertEqual(engine.decide(sample(100), policy: p).action, .allowCharge)
  }
 }
 func testConfigurationRoundtripAndMissingField() {
  for value: Bool? in [nil, false, true] {
   var config = Configuration(); config.sailingCheckpoint = value
   let data = try! JSONEncoder().encode(config)
   XCTAssertEqual(try! JSONDecoder().decode(Configuration.self, from: data).sailingCheckpoint, value)
  }
  var config = Configuration(); config.sailingCheckpoint = false
  config.setChargeLimit(80); XCTAssertEqual(config.sailingCheckpoint, false); XCTAssertNil(config.chargeLimitChangeID)
  config.setChargeLimit(81); XCTAssertEqual(config.sailingCheckpoint, true)
  let first = config.chargeLimitChangeID; XCTAssertNotEqual(first, nil)
  config.setChargeLimit(80); XCTAssertNotEqual(config.chargeLimitChangeID, first)
 }
 func testPortableRestoreClearsMachineCheckpoint() {
  var config = Configuration(); config.sailingCheckpoint = false; config.hardwareEnabled = true; config.chargeLimitChangeID = UUID()
  let data = try! ConfigurationBackup(configuration: config).encoded()
  let restored = try! ConfigurationBackup.restored(from: data)
  XCTAssertNil(restored.sailingCheckpoint); XCTAssertNil(restored.chargeLimitChangeID)
  XCTAssertFalse(restored.hardwareEnabled)
 }
}
