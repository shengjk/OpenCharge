import XCTest
@testable import ChargeCore
final class CompatibilityTests: XCTestCase {
 private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
 private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
 private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))! }
 private func sample(_ percent: Double, temperature: Double = 30, seconds: Double = 0, connected: Bool = true) -> ChargeSample { ChargeSample(date: epoch.addingTimeInterval(seconds), percent: percent, temperature: temperature, connected: connected) }
 func testFiveMinuteThermalWindowsDoNotToggleEarly() {
  var engine = ChargeEngine(); let p = ChargePolicy()
  XCTAssertEqual(engine.decide(sample(50, temperature: 36), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 30, seconds: 299), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 34, seconds: 300), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 36, seconds: 599), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 36, seconds: 600), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 36, seconds: 900), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 30, seconds: 1199), policy: p).action, .inhibitCharge)
  XCTAssertEqual(engine.decide(sample(50, temperature: 30, seconds: 1200), policy: p).action, .allowCharge)
 }
 func testLowChargeBypassesHeatAndSailing() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.limit = 20; p.sailingWidth = 20
  XCTAssertEqual(engine.decide(sample(19, temperature: 40), policy: p).action, .allowCharge)
  XCTAssertEqual(engine.decide(sample(20, temperature: 40), policy: p).action, .inhibitCharge)
 }
 func testCalibrationHeatCompatibilityAndOptionalProtection() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .calibration
  XCTAssertEqual(engine.decide(sample(50, temperature: 40), policy: p).action, .allowCharge)
  p.protectDuringCalibration = true
  XCTAssertEqual(engine.decide(sample(50, temperature: 40, seconds: 1), policy: p).action, .inhibitCharge)
 }
 func testTopUpPersistsAtFullUntilUnplugged() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .topUp
  XCTAssertEqual(engine.decide(sample(100), policy: p).action, .inhibitCharge); XCTAssertNil(engine.completedMode)
  XCTAssertEqual(engine.decide(sample(99, seconds: 10), policy: p).action, .allowCharge); XCTAssertNil(engine.completedMode)
  XCTAssertEqual(engine.decide(sample(99, seconds: 20, connected: false), policy: p).action, .restore)
  XCTAssertEqual(engine.completedMode, .topUp)
 }
 func testManualDischargeSignalsCompletionAtTargetAndReserve() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .discharge
  _ = engine.decide(sample(90), policy: p); XCTAssertNil(engine.completedMode)
  _ = engine.decide(sample(80), policy: p); XCTAssertEqual(engine.completedMode, .discharge)
  _ = engine.decide(sample(10), policy: p); XCTAssertEqual(engine.completedMode, .discharge)
 }
 func testYearlyLeapDaySkipsNonLeapYearsAndIsIdempotent() {
  var schedule = ChargeSchedule(); var p = ChargePolicy()
  schedule.date = date(2024,2,29); schedule.repeatRule = .yearly
  XCTAssertTrue(schedule.consume(now: schedule.date, policy: &p, calendar: calendar))
  XCTAssertEqual(schedule.date, date(2028,2,29))
  XCTAssertFalse(schedule.consume(now: date(2024,3,1), policy: &p, calendar: calendar))
 }
 func testLegacyConfigurationDecodesNewOptionalFields() {
  let legacy = Data(#"{"policy":{"limit":80,"sailing":true,"sailingWidth":5,"automaticDischarge":false,"heatProtection":true,"maxTemperature":35,"mode":"automatic","reserve":15,"stopInSleep":false,"stopOnQuit":false,"clamshellDischarge":false,"departureTarget":100,"estimatedPercentPerHour":30},"schedules":[],"notifications":false,"hardwareEnabled":false,"historyEnabled":true}"#.utf8)
  let config = try? JSONDecoder().decode(Configuration.self, from: legacy)
  XCTAssertEqual(config?.policy.limit, 80)
  XCTAssertNil(config?.policy.thermalBehavior); XCTAssertNil(config?.policy.protectDuringCalibration); XCTAssertNil(config?.policy.lowPowerMode)
 }
 func testMissedTaskCanAdvanceWithoutExecuting() {
  var task = ChargeSchedule(); var p = ChargePolicy(); task.date = epoch; task.repeatRule = .daily; task.action = .topUp
  XCTAssertFalse(task.consume(now: epoch.addingTimeInterval(60), policy: &p, calendar: calendar, runMissedTasks: false))
  XCTAssertEqual(p.mode, .automatic)
  XCTAssertEqual(task.date, epoch.addingTimeInterval(86400))
  var once = ChargeSchedule(); once.date = epoch
  XCTAssertFalse(once.consume(now: epoch.addingTimeInterval(60), policy: &p, calendar: calendar, runMissedTasks: false))
  XCTAssertFalse(once.enabled)
 }
 func testCheckpointContinuesFullChargeHoldWithoutRestartingCycle() {
  var p = ChargePolicy(); p.mode = .calibration
  var original = ChargeEngine()
  _ = original.decide(sample(100), policy: p)
  _ = original.decide(sample(10, seconds: 10), policy: p)
  _ = original.decide(sample(100, seconds: 20), policy: p)
  let encoded = try? JSONEncoder().encode(original.checkpoint)
  let checkpoint = encoded.flatMap { try? JSONDecoder().decode(CalibrationCheckpoint.self, from: $0) }
  XCTAssertEqual(checkpoint?.stage, .holding)
  var restored = ChargeEngine(checkpoint: checkpoint)
  _ = restored.decide(sample(100, seconds: 3619), policy: p)
  XCTAssertEqual(restored.calibration, .holding)
  _ = restored.decide(sample(100, seconds: 3620), policy: p)
  XCTAssertEqual(restored.calibration, .returning)
 }

 func testOwnAdapterInhibitionIsNotMistakenForUnplugging() {
  var engine = ChargeEngine(); var p = ChargePolicy(); p.mode = .discharge
  let ownCut = ChargeSample(date: epoch, percent: 90, temperature: 30, connected: false, ownAdapterInhibited: true)
  XCTAssertEqual(engine.decide(ownCut, policy: p).action, .forceDischarge)
  let unplugged = ChargeSample(date: epoch, percent: 90, temperature: 30, connected: false, physicalAdapterConnected: false, ownAdapterInhibited: true)
  XCTAssertEqual(engine.decide(unplugged, policy: p).action, .restore)
 }

}
