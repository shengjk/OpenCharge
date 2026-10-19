import XCTest
@testable import ChargeCore

final class DischargeExitTests: XCTestCase {
 func testMonitoringCanExitAfterPreparation() {
  var flow = DischargeExit(waitForPower: false); flow.begin(); flow.prepared(now: 0)
  XCTAssertEqual(flow.phase, .ready)
 }
 func testDischargeWaitsForStableExternalSource() {
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: 10)
  flow.observe(.external, now: 10); XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.external, now: 10); XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.external, now: 10.49); XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.external, now: 10.5); XCTAssertEqual(flow.phase, .ready)
 }
 func testExplicitUnplugCanFinishOnBattery() {
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: 0)
  flow.observe(.batteryWithAdapterAbsent, now: 1); flow.observe(.batteryWithAdapterAbsent, now: 1.5)
  XCTAssertEqual(flow.phase, .ready)
 }
 func testUnknownAndBatteryBreakStability() {
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: 0)
  flow.observe(.external, now: 1); flow.observe(.unknown, now: 1.5); flow.observe(.external, now: 2)
  XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.battery, now: 2.5); flow.observe(.external, now: 3); XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.external, now: 3.5); XCTAssertEqual(flow.phase, .ready)
 }
 func testTimeoutNeverForcesExit() {
  var flow = DischargeExit(waitForPower: true, timeout: 2); flow.begin(); flow.prepared(now: 0)
  flow.observe(.unknown, now: 1.99); XCTAssertEqual(flow.phase, .waiting)
  flow.observe(.unknown, now: 2); XCTAssertEqual(flow.phase, .needsDecision)
  flow.observe(.external, now: 3); flow.observe(.external, now: 4); XCTAssertEqual(flow.phase, .needsDecision)
  flow.force(); XCTAssertEqual(flow.phase, .ready)
 }
 func testFailureRequiresDecisionAndRetryPreparesAgain() {
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.preparationFailed()
  XCTAssertEqual(flow.phase, .needsDecision)
  flow.observe(.external, now: 1); XCTAssertEqual(flow.phase, .needsDecision)
  flow.begin(); XCTAssertEqual(flow.phase, .preparing)
  flow.prepared(now: 2); flow.observe(.external, now: 2); flow.observe(.external, now: 2.5)
  XCTAssertEqual(flow.phase, .ready)
 }
 func testCancelIsTerminalAndForceUnavailableDuringWait() {
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: 0); flow.force()
  XCTAssertEqual(flow.phase, .waiting)
  flow.cancel(); flow.begin(); flow.prepared(now: 1); flow.observe(.external, now: 2); flow.force()
  XCTAssertEqual(flow.phase, .cancelled)
 }
 func testInvalidMonotonicTimesAndConfigurationNeedDecision() {
  for now in [Double.nan, .infinity] {
   var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: now)
   XCTAssertEqual(flow.phase, .needsDecision)
  }
  for timeout in [0.0, -1, .infinity] {
   var flow = DischargeExit(waitForPower: true, timeout: timeout); flow.begin(); flow.prepared(now: 0)
   XCTAssertEqual(flow.phase, .needsDecision)
  }
  var flow = DischargeExit(waitForPower: true); flow.begin(); flow.prepared(now: 5); flow.observe(.external, now: 4)
  XCTAssertEqual(flow.phase, .needsDecision)
 }
}
