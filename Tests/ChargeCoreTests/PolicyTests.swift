import XCTest
@testable import ChargeCore

final class PolicyTests: XCTestCase {
 private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
 private var calendar: Calendar {
  var value = Calendar(identifier: .gregorian)
  value.timeZone = TimeZone(secondsFromGMT: 0)!
  return value
 }
 private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
  calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
 }
 private func sample(_ percent: Double, temperature: Double? = 30, seconds: Double = 0, connected: Bool = true, closed: Bool = false) -> ChargeSample {
  ChargeSample(date: epoch.addingTimeInterval(seconds), percent: percent, temperature: temperature, connected: connected, lidClosed: closed)
 }
 func testSailingHoldsUntilLowerBoundaryThenChargesToUpperBoundary() {
  var engine = ChargeEngine(); let p = ChargePolicy()
  XCTAssertEqual(engine.decide(sample(80), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(79), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(75.1), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(75), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(78), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(80), policy: p).action, .inhibitCharge)
 }
 func testDisablingSailingResumesBelowLimit() {
  var engine = ChargeEngine(); var p = ChargePolicy()
  _ = engine.decide(sample(80), policy: p); p.sailing = false
  XCTAssertEqual(engine.decide(sample(79), policy: p).action, .allowCharge)
 }
 func testHeatHysteresisRequiresTwoDegreeCooling() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.thermalBehavior = .degreeHysteresis
  XCTAssertEqual(engine.decide(sample(50, temperature: 35), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 34), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 33), policy: p).action, .allowCharge)
 }
 func testMissingOrNonfiniteTemperatureInhibitsCharging() {
  for temperature: Double? in [nil, .nan, .infinity] {
   var engine = ChargeEngine()
   XCTAssertEqual(engine.decide(sample(50, temperature: temperature), policy: ChargePolicy()).action, .inhibitCharge)
  }
 }
 func testDisablingHeatProtectionAllowsMissingTemperatureAndClearsLatch() {
  var engine = ChargeEngine(); var p = ChargePolicy()
  _ = engine.decide(sample(50, temperature: 40), policy: p)
  p.heatProtection = false
  XCTAssertEqual(engine.decide(sample(50, temperature: nil), policy: p).action, .allowCharge)
  p.heatProtection = true
  XCTAssertEqual(engine.decide(sample(50, temperature: 34), policy: p).action, .allowCharge)
 }
 func testInvalidBatteryPercentageRestoresSystemControl() {
  for percent in [-0.1, 100.1, .nan, .infinity, -.infinity] {
   var engine = ChargeEngine()
   XCTAssertEqual(engine.decide(sample(percent), policy: ChargePolicy()).action, .restore)
  }
 }
 func testDisconnectedRestoresEvenWithMissingTemperature() {
  var engine = ChargeEngine()
  XCTAssertEqual(engine.decide(sample(50, temperature: nil, connected: false), policy: ChargePolicy()).action, .restore)
 }
 func testPolicyNormalizesNonfiniteAndOutOfBoundsSettings() {
  var p = ChargePolicy(); p.limit = .nan; p.sailingWidth = 99; p.reserve = -20
  p.maxTemperature = .infinity; p.departureTarget = 500; p.estimatedPercentPerHour = 0
  p.normalize()
  XCTAssertEqual(p.limit, 80); XCTAssertEqual(p.sailingWidth, 20); XCTAssertEqual(p.reserve, 10)
  XCTAssertEqual(p.maxTemperature, 35); XCTAssertEqual(p.departureTarget, 100); XCTAssertEqual(p.estimatedPercentPerHour, 5)
 }
 func testDischargeStopsAtTargetAndReserveOverridesDischarge() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .discharge
  XCTAssertEqual(engine.decide(sample(90), policy: p).action, .forceDischarge)
  XCTAssertEqual(engine.decide(sample(80), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(15), policy: p).action, .allowCharge)
 }
 func testAutomaticDischargeAndClamshellGate() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.automaticDischarge = true
  XCTAssertEqual(engine.decide(sample(90, closed: true), policy: p).action, .inhibitCharge)
  p.clamshellDischarge = true
  XCTAssertEqual(engine.decide(sample(90, closed: true), policy: p).action, .forceDischarge)
 }
 func testTopUpBypassesSailingAndUsesFullTarget() {
  var engine = ChargeEngine(); var p = ChargePolicy()
  _ = engine.decide(sample(80), policy: p); p.mode = .topUp
  XCTAssertEqual(engine.decide(sample(80), policy: p).effectiveLimit, 100)
  XCTAssertEqual(engine.decide(sample(95), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(100), policy: p).action, .inhibitCharge)
 }
 func testCalibrationPublishedSequenceAndOneHourHold() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .calibration
  XCTAssertEqual(engine.decide(sample(50), policy: p).effectiveLimit, 100)
  XCTAssertEqual(engine.calibration, .filling)
  _ = engine.decide(sample(100), policy: p)
  XCTAssertEqual(engine.calibration, .draining)
  XCTAssertEqual(engine.decide(sample(90, seconds: 1), policy: p).action, .forceDischarge)
  _ = engine.decide(sample(10, seconds: 3600), policy: p)
  XCTAssertEqual(engine.calibration, .refilling)
  XCTAssertEqual(engine.decide(sample(80, seconds: 7200), policy: p).effectiveLimit, 100)
  _ = engine.decide(sample(100, seconds: 9000), policy: p)
  XCTAssertEqual(engine.calibration, .holding)
  XCTAssertEqual(engine.decide(sample(100, seconds: 12599), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.calibration, .holding)
  _ = engine.decide(sample(100, seconds: 12600), policy: p)
  XCTAssertNotEqual(engine.calibration, .holding)
  XCTAssertEqual(engine.decide(sample(90, seconds: 12601), policy: p).action, .forceDischarge)
  _ = engine.decide(sample(80, seconds: 14000), policy: p)
  XCTAssertEqual(engine.calibration, .complete)
  XCTAssertEqual(engine.decide(sample(60, seconds: 15000), policy: p).action, .allowCharge)
  p.mode = .automatic; _ = engine.decide(sample(70), policy: p)
  XCTAssertEqual(engine.calibration, .idle); XCTAssertNil(engine.holdingSince)
 }
 func testSailingStartsPausedInsideBand() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.sailingWidth = 10
  XCTAssertEqual(engine.decide(sample(77), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(70), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(75), policy: p).action, .allowCharge)
 }
 func testMonthlyThirtyFirstSkipsMonthsWithoutDate() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.date = date(2026,1,31); schedule.repeatRule = .monthly
  XCTAssertTrue(schedule.consume(now: schedule.date, policy: &p, calendar: calendar))
  XCTAssertEqual(schedule.date, date(2026,3,31))
  XCTAssertTrue(schedule.consume(now: schedule.date, policy: &p, calendar: calendar))
  XCTAssertEqual(schedule.date, date(2026,5,31))
 }
 func testWeekdayRuleDoesNotExecuteOnInitiallySelectedWeekend() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.date = date(2026,10,17); schedule.repeatRule = .weekdays
  XCTAssertFalse(schedule.consume(now: schedule.date, policy: &p, calendar: calendar))
  XCTAssertEqual(p.mode, .automatic)
 }
 func testDeparturePlanningIncludesThirtyMinuteBuffer() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.sailing = false
  // 40% needed / 20% per hour + 0.5h safety buffer = 2.5h.
  p.departureTarget = 100; p.estimatedPercentPerHour = 20
  p.departure = epoch.addingTimeInterval(9001)
  XCTAssertEqual(engine.decide(sample(60), policy: p).effectiveLimit, 80)
  p.departure = epoch.addingTimeInterval(9000)
  XCTAssertEqual(engine.decide(sample(60), policy: p).effectiveLimit, 100)
  p.departure = epoch.addingTimeInterval(-1)
  XCTAssertEqual(engine.decide(sample(60), policy: p).effectiveLimit, 80)
 }
 func testOneTimeScheduleIsIdempotentAndNotEarly() {
  var schedule = ChargeSchedule(); var p = ChargePolicy(); schedule.date = epoch
  schedule.action = .limit; schedule.value = 75
  XCTAssertFalse(schedule.consume(now: epoch.addingTimeInterval(-1), policy: &p, calendar: calendar))
  XCTAssertEqual(p.limit, 80)
  XCTAssertTrue(schedule.consume(now: epoch, policy: &p, calendar: calendar))
  XCTAssertEqual(p.limit, 75); XCTAssertFalse(schedule.enabled)
  p.limit = 60
  XCTAssertFalse(schedule.consume(now: epoch.addingTimeInterval(100), policy: &p, calendar: calendar))
  XCTAssertEqual(p.limit, 60)
 }
 func testEveryRepeatRuleAdvancesAndIsIdempotentAtSameInstant() {
  let start = date(2026, 10, 15)
  let expected: [(RepeatRule, Date)] = [(.daily, date(2026,10,16)), (.weekdays, date(2026,10,16)), (.weekly, date(2026,10,22)), (.biweekly, date(2026,10,29)), (.monthly, date(2026,11,15)), (.yearly, date(2027,10,15))]
  for (rule, next) in expected {
   var schedule = ChargeSchedule(); var p = ChargePolicy()
   schedule.date = start; schedule.repeatRule = rule
   XCTAssertTrue(schedule.consume(now: start, policy: &p, calendar: calendar), "\(rule)")
   XCTAssertEqual(schedule.date, next, "\(rule)")
   XCTAssertFalse(schedule.consume(now: start, policy: &p, calendar: calendar), "\(rule)")
  }
  XCTAssertEqual(Set(RepeatRule.allCases), Set(expected.map(\.0) + [.once]))
 }
 func testWeekdaysSkipsWeekendOnAdvance() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.date = date(2026,10,16); schedule.repeatRule = .weekdays
  XCTAssertTrue(schedule.consume(now: schedule.date, policy: &p, calendar: calendar))
  XCTAssertEqual(schedule.date, date(2026,10,19))
 }
 func testDelayedScheduleCatchesUpOnceWithoutTimeDrift() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.date = date(2026,10,1); schedule.repeatRule = .daily
  let now = date(2026,10,15, hour: 12)
  XCTAssertTrue(schedule.consume(now: now, policy: &p, calendar: calendar))
  XCTAssertEqual(schedule.date, date(2026,10,16))
  XCTAssertFalse(schedule.consume(now: now, policy: &p, calendar: calendar))
 }
 func testDisabledScheduleDoesNothing() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.enabled = false; schedule.date = epoch
  XCTAssertFalse(schedule.consume(now: epoch, policy: &p, calendar: calendar))
  XCTAssertEqual(p.mode, .automatic)
 }
 func testConfigurationRoundTripsInMemoryWithoutUserDirectoryAccess() {
  do {
   var config = Configuration(); config.policy.limit = 73; config.policy.mode = .discharge
   config.policy.departure = epoch; config.policy.clamshellDischarge = true
   config.notifications = true; config.hardwareEnabled = true; config.historyEnabled = false
   var schedule = ChargeSchedule(); schedule.date = epoch; schedule.repeatRule = .monthly
   schedule.anchorDay = 31; schedule.action = .limit; schedule.value = 73
   config.schedules = [schedule]
   let data = try JSONEncoder().encode(config)
   let decoded = try JSONDecoder().decode(Configuration.self, from: data)
   XCTAssertEqual(decoded.policy, config.policy)
   XCTAssertEqual(decoded.notifications, true); XCTAssertEqual(decoded.hardwareEnabled, true)
   XCTAssertEqual(decoded.historyEnabled, false); XCTAssertEqual(decoded.schedules.count, 1)
   XCTAssertEqual(decoded.schedules[0].id, schedule.id)
   XCTAssertEqual(decoded.schedules[0].date, epoch)
   XCTAssertEqual(decoded.schedules[0].anchorDay, 31)
   XCTAssertEqual(decoded.schedules[0].repeatRule, .monthly)
   XCTAssertEqual(decoded.schedules[0].action, .limit)
   XCTAssertEqual(decoded.schedules[0].value, 73)
  } catch { XCTFail("Configuration roundtrip failed: \(error)") }
 }
 func testEachScheduleActionExecutesOnceForEveryRepeatRule() {
  for rule in RepeatRule.allCases {
   for action in ScheduleAction.allCases {
    var schedule = ChargeSchedule(); var p = ChargePolicy()
    schedule.date = date(2026,10,15); schedule.repeatRule = rule
    schedule.action = action; schedule.value = 65
    let now = schedule.date
    XCTAssertTrue(schedule.consume(now: now, policy: &p, calendar: calendar), "\(rule)/\(action)")
    switch action {
    case .limit: XCTAssertEqual(p.mode, .automatic); XCTAssertEqual(p.limit, 65)
    case .topUp: XCTAssertEqual(p.mode, .topUp)
    case .pause: XCTAssertEqual(p.mode, .paused)
    case .discharge: XCTAssertEqual(p.mode, .discharge); XCTAssertEqual(p.limit, 65)
    case .calibrate: XCTAssertEqual(p.mode, .calibration)
    case .automatic: XCTAssertEqual(p.mode, .automatic)
    case .lowPowerOn: XCTAssertEqual(p.lowPowerMode, true)
    case .lowPowerOff: XCTAssertEqual(p.lowPowerMode, false)
    }
    p.mode = .paused; p.limit = 42
    XCTAssertFalse(schedule.consume(now: now, policy: &p, calendar: calendar), "\(rule)/\(action)")
    XCTAssertEqual(p.mode, .paused); XCTAssertEqual(p.limit, 42)
   }
  }
 }

 func testCompletedCalibrationDoesNotRestartWhenAutomaticDischargeAndBatteryLow() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .calibration
  _ = engine.decide(sample(100), policy: p)
  _ = engine.decide(sample(10, seconds: 1), policy: p)
  _ = engine.decide(sample(100, seconds: 2), policy: p)
  _ = engine.decide(sample(100, seconds: 3602), policy: p)
  _ = engine.decide(sample(80, seconds: 3603), policy: p)
  XCTAssertEqual(engine.calibration, .complete)
  p.automaticDischarge = true
  XCTAssertEqual(engine.decide(sample(10, seconds: 4000), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.calibration, .complete)
 }

 func testInvalidMonthlyAnchorIsRepairedInsteadOfHanging() {
  for anchor in [0, 32, -1, Int.max] {
   var schedule = ChargeSchedule(); var p = ChargePolicy()
   schedule.date = date(2026,1,31); schedule.repeatRule = .monthly; schedule.anchorDay = anchor
   let now = schedule.date
   XCTAssertTrue(schedule.consume(now: now, policy: &p, calendar: calendar))
   XCTAssertEqual(schedule.anchorDay, 31)
   XCTAssertEqual(schedule.date, date(2026,3,31))
   XCTAssertFalse(schedule.consume(now: now, policy: &p, calendar: calendar))
  }
 }

}
