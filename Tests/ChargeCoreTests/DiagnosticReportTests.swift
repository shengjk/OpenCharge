import XCTest
@testable import ChargeCore
final class DiagnosticReportTests: XCTestCase {
 func testProjectionExcludesSchedulesDepartureAndHistory() {
  var config = Configuration(); var task = ChargeSchedule(); task.id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  task.date = Date(timeIntervalSince1970: 2_000_000_000); config.schedules = [task]; config.policy.departure = task.date
  let report = DiagnosticReport(appVersion: "test", systemVersion: "test", architecture: "arm64", model: "MacBookPro17,1", battery: nil, configuration: config, registrationStatus: "notRegistered", helperCapabilities: "chargeControl:CHTE", decision: .restore, errorPresent: false, generatedAt: Date(timeIntervalSince1970: 0))
  do {
   let text = String(decoding: try report.encoded(), as: UTF8.self)
   XCTAssertFalse(text.contains(task.id.uuidString)); XCTAssertFalse(text.contains("departure")); XCTAssertFalse(text.contains("scheduleHistory"))
   XCTAssertEqual(report.policy.scheduleCount, 1); XCTAssertEqual(report.schemaVersion, 1)
  } catch { XCTFail(error.localizedDescription) }
 }
 func testUnstructuredHelperMessagesAreExcluded() {
  let report = DiagnosticReport(appVersion: "test", systemVersion: "test", architecture: "arm64", model: "MacBookPro17,1", battery: nil, configuration: Configuration(), registrationStatus: "notRegistered", helperCapabilities: "chargeControl:CHTE, error:/Users/private-person/Documents/secret, serial:ABC123, forceDischarge:CHIE", decision: .restore, errorPresent: true)
  XCTAssertEqual(report.helperCapabilities, "chargeControl:CHTE, forceDischarge:CHIE")
 }
}
