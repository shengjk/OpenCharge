import XCTest
@testable import ChargeCore
final class LeaseTests: XCTestCase {
 func testInterruptedClientRestoresAfterFortyFiveAwakeSeconds() {
  var lease = ControlLease(); lease.request(at: 100)
  XCTAssertFalse(lease.expired(at: 145)); XCTAssertTrue(lease.expired(at: 145.001))
 }
 func testSleepPreservesPauseAndWakeGrantsClientGrace() {
  var lease = ControlLease(); lease.request(at: 100); lease.beginSleep()
  XCTAssertFalse(lease.expired(at: 10000)); lease.wake(at: 10000)
  XCTAssertFalse(lease.expired(at: 10045)); XCTAssertTrue(lease.expired(at: 10046))
 }
 func testExplicitRetainIsDifferentFromCrash() {
  var lease = ControlLease(); lease.request(at: 100, retained: true)
  XCTAssertFalse(lease.expired(at: 10000)); lease.beginSleep(); lease.wake(at: 20000)
  XCTAssertFalse(lease.expired(at: 30000)); lease.request(at: 30000)
  XCTAssertTrue(lease.expired(at: 30046))
 }
}
