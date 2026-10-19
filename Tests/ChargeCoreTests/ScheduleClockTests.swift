import XCTest
@testable import ChargeCore
final class ScheduleClockTests: XCTestCase {
 func calendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
 func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 2, _ minute: Int = 30) -> Date { calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))! }
 func testDailySpringGapRestoresWallClockAfterReload() {
  var task = ChargeSchedule(); task.date = date(2026, 3, 7); task.repeatRule = .daily; var policy = ChargePolicy()
  XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar()))
  XCTAssertEqual(task.date, date(2026, 3, 8, 3)); XCTAssertEqual(task.anchorHour, 2)
  do { task = try JSONDecoder().decode(ChargeSchedule.self, from: JSONEncoder().encode(task)) } catch { XCTFail(error.localizedDescription) }
  XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar()))
  XCTAssertEqual(task.date, date(2026, 3, 9)); XCTAssertEqual(task.anchorHour, 2)
 }
 func testFallFoldExecutesOnlyFirstOccurrence() {
  var task = ChargeSchedule(); task.date = date(2026, 10, 31, 1); task.repeatRule = .daily; var policy = ChargePolicy()
  XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar()))
  let first = ISO8601DateFormatter().date(from: "2026-11-01T08:30:00Z")!
  XCTAssertEqual(task.date, first)
  XCTAssertTrue(task.consume(now: first, policy: &policy, calendar: calendar()))
  XCTAssertFalse(task.consume(now: first.addingTimeInterval(3600), policy: &policy, calendar: calendar()))
  XCTAssertEqual(task.date, date(2026, 11, 2, 1))
 }
 func testWeekdayWeeklyAndBiweeklyRetainOriginalClock() {
  for (rule, start, expected) in [(RepeatRule.weekdays, date(2026,3,6), date(2026,3,9)), (.weekly, date(2026,3,1), date(2026,3,8,3)), (.biweekly, date(2026,2,22), date(2026,3,8,3))] {
   var task = ChargeSchedule(); task.date = start; task.repeatRule = rule; var policy = ChargePolicy()
   XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar())); XCTAssertEqual(task.date, expected)
   XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar())); XCTAssertEqual(calendar().component(.hour, from: task.date), 2)
  }
 }
 func testMonthlyAndYearlyGapDoesNotPersistIntoNextOccurrence() {
  for (rule, start) in [(RepeatRule.monthly, date(2026,2,8)), (.yearly, date(2025,3,8))] {
   var task = ChargeSchedule(); task.date = start; task.repeatRule = rule; var policy = ChargePolicy()
   XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar())); XCTAssertEqual(task.date, date(2026,3,8,3))
   XCTAssertTrue(task.consume(now: task.date, policy: &policy, calendar: calendar())); XCTAssertEqual(calendar().component(.hour, from: task.date), 2)
  }
 }
 func testEditValueAndBackupPreserveClockButEditTimeResetsIt() {
  var config = Configuration(); var task = ChargeSchedule(); task.date = date(2026,3,8,3); task.repeatRule = .daily; task.anchorHour = 2; task.anchorMinute = 30
  config.schedules = [task]; task.value = 75; config.saveSchedule(task); XCTAssertEqual(config.schedules[0].anchorHour, 2)
  do { let restored = try ConfigurationBackup.restored(from: ConfigurationBackup(configuration: config).encoded()); XCTAssertEqual(restored.schedules[0].anchorHour, 2); XCTAssertFalse(restored.schedules[0].enabled) } catch { XCTFail(error.localizedDescription) }
  task.date = date(2026,3,10,4); config.saveSchedule(task); XCTAssertNil(config.schedules[0].anchorHour)
 }
 func testLongBacklogKeepsWeeklyPhaseAndExecutesOnce() {
  var task = ChargeSchedule(); task.date = date(1980,3,17); task.repeatRule = .weekly; var policy = ChargePolicy()
  let now = date(2026,3,13,12)
  XCTAssertTrue(task.consume(now: now, policy: &policy, calendar: calendar()))
  XCTAssertEqual(task.date, date(2026,3,16)); XCTAssertFalse(task.consume(now: now, policy: &policy, calendar: calendar()))
 }

 func testWeekdayCatchupNeverLeavesUpcomingWeekendOccurrence() {
  var task = ChargeSchedule(); task.date = date(2026,3,6); task.repeatRule = .weekdays; var policy = ChargePolicy()
  XCTAssertTrue(task.consume(now: date(2026,3,8,1), policy: &policy, calendar: calendar()))
  XCTAssertEqual(task.date, date(2026,3,9)); XCTAssertFalse(calendar().isDateInWeekend(task.date))
 }

}
