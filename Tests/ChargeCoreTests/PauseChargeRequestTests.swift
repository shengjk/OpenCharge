import XCTest
@testable import ChargeCore

final class PauseChargeRequestTests: XCTestCase {
 func testPauseUsesCurrentControlPercentageAndCancelsTemporaryTargets() {
  for percent in [20.0, 80.6, 100] {
   var p = ChargePolicy(); p.mode = .topUp; p.departure = Date().addingTimeInterval(3600)
   do { try PauseChargeRequest.apply(percent: percent, policy: &p) } catch { XCTFail(error.localizedDescription) }
   XCTAssertEqual(p.limit, Double(Float(percent))); XCTAssertEqual(p.mode, .paused); XCTAssertEqual(p.pauseAtCurrent, true); XCTAssertNil(p.departure)
   var engine = ChargeEngine()
   XCTAssertEqual(engine.decide(ChargeSample(percent: percent, temperature: 30), policy: p).action, .inhibitCharge)
  }
 }
 func testCurrentPauseResumesThroughOrdinarySailingAndCharging() {
  var p = ChargePolicy(); var engine = ChargeEngine()
  do { try PauseChargeRequest.apply(percent: 80.6, policy: &p) } catch { XCTFail(error.localizedDescription) }
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80.6, temperature: 30), policy: p).action, .inhibitCharge)
  XCTAssertNil(engine.completedMode)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 79.9, temperature: 30), policy: p).sailingHold, true)
  XCTAssertEqual(engine.completedMode, .paused)
  p.mode = .automatic; p.pauseAtCurrent = nil
  XCTAssertEqual(engine.decide(ChargeSample(percent: 75.7, temperature: 30), policy: p).sailingHold, true)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 75.6, temperature: 30), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 79.9, temperature: 30), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 80.6, temperature: 30), policy: p).action, .inhibitCharge)
 }
 func testCurrentPauseAtFullStopsUntilBelowLimitWithoutSailing() {
  var p = ChargePolicy(); p.sailing = false; var engine = ChargeEngine()
  do { try PauseChargeRequest.apply(percent: 100, policy: &p) } catch { XCTFail(error.localizedDescription) }
  let full = engine.decide(ChargeSample(percent: 100, temperature: 30), policy: p)
  XCTAssertEqual(full.action, .inhibitCharge); XCTAssertEqual(full.fullChargeHold, false)
  XCTAssertEqual(engine.decide(ChargeSample(percent: 99.5, temperature: 30), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.completedMode, .paused)
 }
 func testInvalidPauseDoesNotChangePolicy() {
  for percent in [19.9, 100.1, Double.nan, .infinity, -.infinity] {
   var p = ChargePolicy(); p.mode = .calibration; let original = p
   do { try PauseChargeRequest.apply(percent: percent, policy: &p); XCTFail("invalid percentage accepted") } catch {}
   XCTAssertEqual(p, original)
  }
 }
}
