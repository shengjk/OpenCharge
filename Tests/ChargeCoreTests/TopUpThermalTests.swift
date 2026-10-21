import XCTest
@testable import ChargeCore

final class TopUpThermalTests: XCTestCase {
 private let start = Date(timeIntervalSince1970: 1_700_000_000)
 private func sample(_ temperature: Double?, percent: Double = 60, seconds: Double = 0) -> ChargeSample {
  ChargeSample(date: start.addingTimeInterval(seconds), percent: percent, temperature: temperature)
 }
 private func legacyConfiguration() throws -> Configuration {
  var original = Configuration(); original.policy.mode = .topUp
  var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
  var policy = object["policy"] as! [String: Any]
  policy.removeValue(forKey: "protectDuringTopUp"); object["policy"] = policy
  return try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
 }
 func testNewTopUpAllowsChargingRegardlessOfHotOrUnavailableTemperature() {
  var p = ChargePolicy(); p.mode = .topUp
  XCTAssertEqual(p.protectDuringTopUp, false); XCTAssertFalse(p.topUpThermalProtection)
  for temperature in [Double?.some(40), .none, .some(.nan)] {
   var engine = ChargeEngine()
   let decision = engine.decide(sample(temperature), policy: p)
   XCTAssertEqual(decision.action, .allowCharge); XCTAssertEqual(decision.phase, .topUp)
   XCTAssertEqual(decision.thermalHold, false); XCTAssertEqual(decision.effectiveLimit, 100)
  }
 }
 func testNewTopUpKeepsFullChargeHoldWhenHotOrTemperatureUnavailable() {
  var p = ChargePolicy(); p.mode = .topUp
  for temperature in [Double?.some(40), .none, .some(.nan)] {
   var engine = ChargeEngine()
   let full = engine.decide(sample(temperature, percent: 100), policy: p)
   XCTAssertEqual(full.action, .allowCharge); XCTAssertEqual(full.phase, .topUp)
   XCTAssertEqual(full.fullChargeHold, true); XCTAssertEqual(full.thermalHold, false)
   XCTAssertNil(engine.completedMode)
  }
 }
 func testExplicitTopUpProtectionUsesHeatWindowAndRejectsMissingTemperature() {
  var p = ChargePolicy(); p.mode = .topUp; p.protectDuringTopUp = true
  var engine = ChargeEngine()
  let hot = engine.decide(sample(40), policy: p)
  XCTAssertEqual(hot.action, .inhibitCharge); XCTAssertEqual(hot.thermalHold, true)
  XCTAssertEqual(hot.phase, .heatProtect)
  XCTAssertEqual(engine.decide(sample(30, seconds: 299), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(30, seconds: 300), policy: p).action, .allowCharge)
  for temperature in [Double?.none, .some(.nan)] {
   var fresh = ChargeEngine()
   XCTAssertEqual(fresh.decide(sample(temperature), policy: p).action, .inhibitCharge)
  }
 }
 func testGlobalHeatOptOutOverridesTopUpProtection() {
  var p = ChargePolicy(); p.mode = .topUp; p.protectDuringTopUp = true; p.heatProtection = false
  for temperature in [Double?.some(40), .none, .some(.nan)] {
   var engine = ChargeEngine()
   let decision = engine.decide(sample(temperature), policy: p)
   XCTAssertEqual(decision.action, .allowCharge); XCTAssertEqual(decision.phase, .topUp)
   XCTAssertEqual(decision.thermalHold, false)
  }
 }
 func testLegacyMissingFieldRetainsEffectiveProtection() {
  do {
   let old = try legacyConfiguration()
   XCTAssertNil(old.policy.protectDuringTopUp); XCTAssertTrue(old.policy.topUpThermalProtection)
   var engine = ChargeEngine()
   let hot = engine.decide(sample(40), policy: old.policy)
   XCTAssertEqual(hot.action, .inhibitCharge); XCTAssertEqual(hot.thermalHold, true)
  } catch { XCTFail(error.localizedDescription) }
 }
 func testLegacyRoundTripPreservesMissingFieldAndEffectiveProtection() {
  do {
   let old = try legacyConfiguration()
   let encoded = try JSONEncoder().encode(old)
   let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
   XCTAssertNil((object["policy"] as! [String: Any])["protectDuringTopUp"])
   let decoded = try JSONDecoder().decode(Configuration.self, from: encoded)
   XCTAssertNil(decoded.policy.protectDuringTopUp); XCTAssertTrue(decoded.policy.topUpThermalProtection)
  } catch { XCTFail(error.localizedDescription) }
 }
 func testNewRoundTripPersistsExplicitFalse() {
  do {
   var original = Configuration(); original.policy.mode = .topUp
   let encoded = try JSONEncoder().encode(original)
   let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
   XCTAssertEqual((object["policy"] as! [String: Any])["protectDuringTopUp"] as? Bool, false)
   let decoded = try JSONDecoder().decode(Configuration.self, from: encoded)
   XCTAssertEqual(decoded.policy.protectDuringTopUp, false); XCTAssertFalse(decoded.policy.topUpThermalProtection)
   var engine = ChargeEngine()
   XCTAssertEqual(engine.decide(sample(40), policy: decoded.policy).action, .allowCharge)
  } catch { XCTFail(error.localizedDescription) }
 }
 func testBackupPreservesLegacyAndExplicitTopUpThermalPreferences() {
  do {
   for preference in [Bool?.none, .some(false), .some(true)] {
    var original = try legacyConfiguration(); original.policy.protectDuringTopUp = preference
    let restored = try ConfigurationBackup.restored(from: ConfigurationBackup(configuration: original).encoded())
    XCTAssertEqual(restored.policy.protectDuringTopUp, preference)
    XCTAssertEqual(restored.policy.topUpThermalProtection, preference ?? true)
    XCTAssertEqual(restored.policy.mode, .automatic)
    var topUpPolicy = restored.policy; topUpPolicy.mode = .topUp
    var engine = ChargeEngine()
    XCTAssertEqual(engine.decide(sample(40), policy: topUpPolicy).action, (preference ?? true) ? .inhibitCharge : .allowCharge)
   }
  } catch { XCTFail(error.localizedDescription) }
 }
 func testAutomaticHeatProtectionDoesNotDependOnTopUpPreference() {
  for preference in [Bool?.none, .some(false), .some(true)] {
   var p = ChargePolicy(); p.sailing = false; p.protectDuringTopUp = preference
   var engine = ChargeEngine()
   let hot = engine.decide(sample(40), policy: p)
   XCTAssertEqual(hot.action, .inhibitCharge); XCTAssertEqual(hot.phase, .heatProtect)
   XCTAssertEqual(hot.thermalHold, true)
   p.heatProtection = false
   var unprotected = ChargeEngine()
   XCTAssertEqual(unprotected.decide(sample(40), policy: p).action, .allowCharge)
  }
 }
 func testCalibrationProtectionRemainsIndependentOfTopUpPreference() {
  for preference in [Bool?.none, .some(false), .some(true)] {
   for calibrationProtection in [false, true] {
    var p = ChargePolicy(); p.mode = .calibration
    p.protectDuringTopUp = preference; p.protectDuringCalibration = calibrationProtection
    var engine = ChargeEngine()
    let hot = engine.decide(sample(40), policy: p)
    XCTAssertEqual(hot.action, calibrationProtection ? .inhibitCharge : .allowCharge)
    XCTAssertEqual(hot.phase, .calibration)
    XCTAssertEqual(hot.thermalHold, calibrationProtection)
   }
  }
 }
}
