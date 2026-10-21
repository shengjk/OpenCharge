import XCTest
@testable import ChargeCore

final class ScheduledPauseTests: XCTestCase {
 func testEligibilityMatrixAndDailyHeatTarget() {
  for phase in PolicyPhase.allCases {
   for limit in [80.0, 99.9, 100.0] {
    var policy = ChargePolicy(); policy.limit = limit
    policy.departure = Date(timeIntervalSince1970: 1234)
    let original = policy
    let eligible = [.charging, .topUp, .discharging, .calibration].contains(phase) || (phase == .heatProtect && limit == 100)
    let outcome = ScheduledPauseRequest.apply(context: ScheduledPauseContext(phase: phase, percent: 56.75), policy: &policy)
    if eligible {
     XCTAssertEqual(outcome, .pausedAtCurrent(56.75)); XCTAssertEqual(policy.limit, 56.75)
     XCTAssertEqual(policy.mode, .paused); XCTAssertEqual(policy.pauseAtCurrent, true); XCTAssertNil(policy.departure)
    } else { XCTAssertEqual(outcome, .skippedPause(.ineligiblePhase)); XCTAssertEqual(policy, original) }
   }
  }
 }
 func testFloatBoundariesAndUnavailableSamplesAreNonMutating() {
  for percent: Double? in [nil, .nan, .infinity, -.infinity, -1, 101, 19.9] {
   var policy = ChargePolicy(); policy.mode = .calibration
   let original = policy
   let result = ScheduledPauseRequest.apply(context: ScheduledPauseContext(phase: .calibration, percent: percent), policy: &policy)
   XCTAssertEqual(result, .skippedPause(percent == 19.9 ? .belowMinimum : .unavailablePercentage))
   XCTAssertEqual(policy, original)
  }
  for percent in [20.0, Double(Float(20).nextDown), 19.9999999, 57.123456789, 100] {
   var policy = ChargePolicy(); let original = policy
   let result = ScheduledPauseRequest.apply(context: ScheduledPauseContext(phase: .charging, percent: percent), policy: &policy)
   if Float(percent) < 20 { XCTAssertEqual(result, .skippedPause(.belowMinimum)); XCTAssertEqual(policy, original) }
   else { XCTAssertEqual(result, .pausedAtCurrent(Double(Float(percent)))); XCTAssertEqual(policy.limit, Double(Float(percent))) }
  }
 }
 func testMissingContextAndInterruptedCalibrationDoNotChangePolicy() {
  var policy = ChargePolicy(); policy.mode = .calibration; let original = policy
  XCTAssertEqual(ScheduledPauseRequest.apply(context: nil, policy: &policy), .skippedPause(.unavailableContext))
  XCTAssertEqual(ScheduledPauseRequest.apply(context: ScheduledPauseContext(phase: .calibration, percent: 50, calibrationInterrupted: true), policy: &policy), .skippedPause(.interruptedCalibration))
  XCTAssertEqual(policy, original)
 }
 func testSkippedPauseStillConsumesOnceAndRepeatsWithoutDuplicateExecution() {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  for rule in RepeatRule.allCases {
   var task = ChargeSchedule(); task.action = .pause; task.date = now; task.repeatRule = rule
   var policy = ChargePolicy(); let original = policy
   // Use a non-weekend instant for weekday normalization.
   XCTAssertTrue(task.consume(now: now, policy: &policy))
   XCTAssertEqual(policy, original)
   XCTAssertFalse(task.consume(now: now, policy: &policy))
   XCTAssertEqual(policy, original)
  }
 }
 func testTimingCanBeConsumedWithoutApplyingPolicy() {
  var task = ChargeSchedule(); task.action = .pause; task.date = Date(timeIntervalSince1970: 1)
  XCTAssertTrue(task.consume(now: task.date)); XCTAssertFalse(task.enabled)
  var policy = ChargePolicy()
  XCTAssertEqual(task.apply(policy: &policy, pauseContext: ScheduledPauseContext(phase: .charging, percent: 66)), .pausedAtCurrent(66))
  XCTAssertEqual(policy.limit, 66)
 }
 func testAcceptedModeEventCancelsCalibrationWithoutAdvancingSamples() {
  for stage: CalibrationStage in [.draining, .holding] {
   var engine = ChargeEngine(checkpoint: CalibrationCheckpoint(stage: stage, holdingSince: Date()), sailingCheckpoint: false)
   var policy = ChargePolicy(); policy.mode = .calibration
   _ = engine.decide(ChargeSample(percent: 50, temperature: 30), policy: policy)
   XCTAssertEqual(engine.calibration, stage)
   let checkpoint = engine.sailingCheckpoint
   engine.modeChanged(to: .paused)
   XCTAssertEqual(engine.calibration, .idle); XCTAssertNil(engine.holdingSince); XCTAssertEqual(engine.phase, .pause)
   XCTAssertEqual(engine.sailingCheckpoint, checkpoint)
   _ = engine.decide(ChargeSample(percent: 50, temperature: 30), policy: policy)
   XCTAssertEqual(engine.calibration, .filling)
  }
 }
 func testOtherExplicitScheduleModesClearOnlyPauseFlag() {
  for action in ScheduleAction.allCases where action != .pause {
   var policy = ChargePolicy(); policy.pauseAtCurrent = true
   var task = ChargeSchedule(); task.action = action
   XCTAssertEqual(task.apply(policy: &policy), .updated)
   if action == .lowPowerOn || action == .lowPowerOff { XCTAssertEqual(policy.pauseAtCurrent, true) }
   else { XCTAssertNil(policy.pauseAtCurrent) }
  }
 }
}
