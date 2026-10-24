import XCTest
@testable import ChargeCore

final class FirmwareCommandTests: XCTestCase {
 func testEveryFiniteCommandRoundTrips() {
  XCTAssertEqual(FirmwareCommand.supportedActions.count, 249)
  for value in FirmwareCommand.supportedActions { XCTAssertEqual(FirmwareCommand.parse(value)?.wireValue, value) }
  for n in 20...100 { XCTAssertEqual(FirmwareCommand.parse("firmwareLimit:\(n)"), .limit(n)); XCTAssertEqual(FirmwareCommand.parse("firmwareExit:\(n)"), .exit(n)); XCTAssertEqual(FirmwareCommand.parse("firmwareSleep:\(n)"), .sleepTarget(n)) }
  XCTAssertEqual(FirmwareCommand.parse("firmwareSleep:15"), .sleepTarget(15))
 }
 func testNoncanonicalAndUnboundedCommandsAreRejected() {
  for value in ["firmwareLimit:15","firmwareExit:15","firmwareLimit:19","firmwareSleep:19","firmwareLimit:101","firmwareExit:256","firmwareLimit:-1","firmwareLimit:+20","firmwareLimit:020","firmwareLimit:20 "," firmwareAllow","firmwareLimit:２０","firmwareLimit:20\nrestore","firmwareLimit:20\r","firmwareLimit:20:30","firmwareLimit:","firmwareLimit:9999999999999999999999999999","CH0B:0","BCLM:80","firmwareReset:/tmp/x",""] { XCTAssertNil(FirmwareCommand.parse(value)); XCTAssertFalse(FirmwareCommand.supportedActions.contains(value)) }
 }
 func testInvalidConstructedValuesHaveNoWireRepresentation() {
  for value in [Int.min,0,15,19,101,Int.max] { XCTAssertNil(FirmwareCommand.limit(value).wireValue); XCTAssertNil(FirmwareCommand.exit(value).wireValue) }
  for value in [Int.min,0,14,16,19,101,Int.max] { XCTAssertNil(FirmwareCommand.sleepTarget(value).wireValue) }
 }
}
