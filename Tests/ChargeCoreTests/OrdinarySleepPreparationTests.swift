import XCTest
@testable import ChargeCore

final class OrdinarySleepPreparationTests: XCTestCase {
 func testOptOutReleasesProtectionWithoutAnyChargeRequest() {
  for active in [false,true] {
   var events: [String] = []
   let result = OrdinarySleepPreparation.perform(stopInSleep:false,sessionActive:active,inhibit:{events.append("inhibit")},releaseProtection:{events.append("release")})
   XCTAssertEqual(events,["release"]); XCTAssertTrue(result.succeeded)
  }
 }
 func testInhibitAndReleaseHaveOrderedIndependentFailures() {
  enum Fault: Error { case requested }
  for mask in 0..<4 {
   var events: [String] = []
   let result = OrdinarySleepPreparation.perform(stopInSleep:true,sessionActive:true,inhibit:{
    events.append("inhibit"); if mask & 1 != 0 { throw Fault.requested }
   },releaseProtection:{
    events.append("release"); if mask & 2 != 0 { throw Fault.requested }
   })
   XCTAssertEqual(events,["inhibit","release"])
   XCTAssertEqual(result.failures[.inhibit] != nil,mask & 1 != 0)
   XCTAssertEqual(result.failures[.releaseProtection] != nil,mask & 2 != 0)
   XCTAssertEqual(result.succeeded,mask == 0)
  }
 }
 func testSleepPolicyDoesNotEstablishAnUnownedChargeSession() {
  enum Fault: Error { case requested }
  var operations = 0
  let result = OrdinarySleepPreparation.perform(stopInSleep:true,sessionActive:false,inhibit:{operations += 1},releaseProtection:{throw Fault.requested})
  XCTAssertEqual(operations,0); XCTAssertTrue(result.failures[.inhibit] == nil)
  XCTAssertTrue(result.failures[.releaseProtection] != nil); XCTAssertFalse(result.succeeded)
 }
}
