import XCTest
@testable import ChargeCore

final class DirectChargeCommandTests: XCTestCase {
 private enum FixtureError: Error { case unavailable }
 private func expectRejection(_ operation: () throws -> String) {
  do { _ = try operation(); XCTFail("Unexpectedly accepted direct command") } catch {}
 }
 func testRejectsInternalMalformedAndUnconfirmedActionsBeforeInspectionOrIPC() {
  let rejected = [[], ["allowCharge"], ["restore"], ["retainChargeInhibit", "--confirm"],
   ["firmwareAllow", "--confirm"], ["sleepPolicyOn", "--confirm"], ["ALLOWCHARGE", "--confirm"],
   ["allowCharge", "--confirm", "extra"], ["--confirm", "allowCharge"], ["unknown", "--confirm"]]
  for args in rejected {
   expectRejection { try DirectChargeCommand.run(arguments: args, numericRequired: {
    XCTFail("Invalid syntax reached model inspection"); return false
   }, request: { _ in XCTFail("Invalid syntax reached IPC"); return "unexpected" }) }
  }
 }
 func testNumericModelsCannotFallBackToOrdinaryActions() {
  for action in ["allowCharge", "inhibitCharge", "forceDischarge"] {
   var inspections = 0
   expectRejection { try DirectChargeCommand.run(arguments: [action, "--confirm"], numericRequired: {
    inspections += 1; return true
   }, request: { _ in XCTFail("Numeric model reached ordinary IPC"); return "unexpected" }) }
   XCTAssertEqual(inspections, 1)
  }
 }
 func testModelInspectionFailureNeverReachesIPC() {
  expectRejection { try DirectChargeCommand.run(arguments: ["allowCharge", "--confirm"], numericRequired: {
   throw FixtureError.unavailable
  }, request: { _ in XCTFail("Unknown model reached IPC"); return "unexpected" }) }
 }
 func testOrdinaryActionsKeepExactRequestAndReplyAndPropagateFailure() {
  for action in ["allowCharge", "inhibitCharge", "forceDischarge"] {
   var requests = [String]()
   let result = try? DirectChargeCommand.run(arguments: [action, "--confirm"], numericRequired: { false }, request: {
    requests.append($0); return "acknowledged"
   })
   XCTAssertEqual(requests, [action]); XCTAssertEqual(result, Optional("acknowledged"))
   expectRejection { try DirectChargeCommand.run(arguments: [action, "--confirm"], numericRequired: { false }, request: { _ in throw FixtureError.unavailable }) }
  }
 }
 func testRestoreRemainsAvailableWithoutModelInspection() {
  var requests = [String]()
  let result = try? DirectChargeCommand.run(arguments: ["restore", "--confirm"], numericRequired: {
   XCTFail("Recovery must not depend on model discovery"); throw FixtureError.unavailable
  }, request: { requests.append($0); return "restored" })
  XCTAssertEqual(requests, ["restore"]); XCTAssertEqual(result, Optional("restored"))
 }
}
