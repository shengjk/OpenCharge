import XCTest
@testable import ChargeCore

final class DateDisplayTests: XCTestCase {
 func testCurrentSystemStylesPreserveOriginalDisplays() {
  if #available(macOS 12.0, *) {
   for seconds in [-1.0, 0, 1782630145] {
    let date = Date(timeIntervalSince1970:seconds)
    XCTAssertEqual(DateDisplay.string(date),date.formatted())
    XCTAssertEqual(DateDisplay.string(date,style:.abbreviated),date.formatted(date:.abbreviated,time:.shortened))
    XCTAssertEqual(DateDisplay.string(date,style:.time),date.formatted(date:.omitted,time:.standard))
   }
  }
 }
 func testLegacyCalendarYearAndDisplayStyles() {
  let locale = Locale(identifier:"en_US_POSIX"), zone = TimeZone(secondsFromGMT:0)!
  let calendar = Calendar(identifier:.gregorian), date = Date(timeIntervalSince1970:1782630145)
  let numeric = DateDisplay.legacy(date,style:.standard,locale:locale,calendar:calendar,timeZone:zone)
  let abbreviated = DateDisplay.legacy(date,style:.abbreviated,locale:locale,calendar:calendar,timeZone:zone)
  let time = DateDisplay.legacy(date,style:.time,locale:locale,calendar:calendar,timeZone:zone)
  XCTAssertTrue(numeric.contains("2026")); XCTAssertFalse(numeric.contains("Jun"))
  XCTAssertTrue(abbreviated.contains("Jun")); XCTAssertTrue(abbreviated.contains("2026"))
  XCTAssertTrue(time.contains(":25")); XCTAssertFalse(time.contains("2026"))
  let buddhist = DateDisplay.legacy(date,style:.standard,locale:Locale(identifier:"th_TH"),calendar:Calendar(identifier:.buddhist),timeZone:zone)
  XCTAssertTrue(buddhist.contains("2569"),"Calendar identifier must be honored")
 }
 func testLegacyDaylightSavingAndMidnightBoundaries() {
  let locale = Locale(identifier:"en_US_POSIX"), calendar = Calendar(identifier:.gregorian)
  let utc = TimeZone(secondsFromGMT:0)!, la = TimeZone(identifier:"America/Los_Angeles")!
  let parser = ISO8601DateFormatter()
  let before = parser.date(from:"2026-03-08T09:59:30Z")!, after = parser.date(from:"2026-03-08T10:00:30Z")!
  let first = DateDisplay.legacy(before,style:.time,locale:locale,calendar:calendar,timeZone:la)
  let second = DateDisplay.legacy(after,style:.time,locale:locale,calendar:calendar,timeZone:la)
  XCTAssertTrue(first.contains("1:59:30")); XCTAssertTrue(second.contains("3:00:30"))
  let midnight = parser.date(from:"2026-06-28T00:02:25Z")!
  let local = DateDisplay.legacy(midnight,style:.standard,locale:locale,calendar:calendar,timeZone:la)
  let universal = DateDisplay.legacy(midnight,style:.standard,locale:locale,calendar:calendar,timeZone:utc)
  XCTAssertTrue(local.contains("6/27/2026")); XCTAssertTrue(universal.contains("6/28/2026"))
 }
}
