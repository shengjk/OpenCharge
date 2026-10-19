import XCTest
@testable import ChargeCore

final class LidLockTests: XCTestCase {
 func testRequiresAllIndependentConditions() {
  for tuple in [(false, true, true), (true, false, true), (true, true, false)] {
   var p = LidLockPolicy()
   XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: tuple.0, sleepOverrideActive: tuple.1, consoleSessionActive: tuple.2))
   XCTAssertTrue(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  }
 }
 func testOneAttemptUntilAnObservedOpen() {
  var p = LidLockPolicy()
  XCTAssertTrue(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  for _ in 0..<1000 { XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true)) }
  XCTAssertFalse(p.shouldRequest(lidClosed: nil, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: false, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertTrue(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
 }
 func testUnknownLidAndDisabledTransitionsDoNotRequest() {
  var p = LidLockPolicy()
  XCTAssertFalse(p.shouldRequest(lidClosed: nil, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: false, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: false, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertTrue(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: false, sleepOverrideActive: true, consoleSessionActive: true))
  XCTAssertFalse(p.shouldRequest(lidClosed: true, enabled: true, sleepOverrideActive: true, consoleSessionActive: true))
 }
}
