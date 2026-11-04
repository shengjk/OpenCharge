import XCTest
@testable import ChargeCore

final class AutomationConfigurationTests: XCTestCase {
 func testExplicitModeNeverReusesCalibrationCheckpoint() {
  for stage in [CalibrationStage.draining,.holding,.returning] {
   for mode in [ChargeMode.automatic,.paused,.discharge,.topUp,.calibration] {
    var config = Configuration()
    config.policy.mode = .calibration;config.policy.pauseAtCurrent = true
    config.calibrationCheckpoint = CalibrationCheckpoint(stage:stage,holdingSince:Date(timeIntervalSince1970:123))
    config.lastCalibration = Date(timeIntervalSince1970:456)
    config.pendingOrdinaryQuitRecovery = true;config.hardwareEnabled = false
    let savedLimit = config.policy.limit, savedCalibration = config.lastCalibration
    config.setAutomationMode(mode)
    XCTAssertEqual(config.policy.mode,mode)
    XCTAssertNil(config.policy.pauseAtCurrent)
    XCTAssertNil(config.calibrationCheckpoint)
    XCTAssertEqual(config.policy.limit,savedLimit)
    XCTAssertEqual(config.lastCalibration,savedCalibration)
    XCTAssertEqual(config.pendingOrdinaryQuitRecovery,true)
    XCTAssertFalse(config.hardwareEnabled)
   }
  }
 }
 func testExplicitDischargeKeepsItsTargetWhenDepartureIsDue() {
  let now = Date(timeIntervalSince1970:1_700_000_000)
  for scheduled in [false,true] {
   var config = Configuration(); config.policy.limit = 40
   config.policy.departure = now.addingTimeInterval(60); config.policy.departureTarget = 100
   if scheduled {
    var schedule = ChargeSchedule(); schedule.action = .discharge; schedule.value = 40
    _ = schedule.apply(policy:&config.policy)
   } else { config.setAutomationMode(.discharge) }
   XCTAssertNil(config.policy.departure)
   XCTAssertFalse(config.hardwareEnabled)
   var engine = ChargeEngine()
   let decision = engine.decide(ChargeSample(date:now,percent:80,temperature:25,connected:true),policy:config.policy)
   XCTAssertEqual(decision.action,.forceDischarge)
   XCTAssertEqual(decision.effectiveLimit,40)
   XCTAssertEqual(engine.decide(ChargeSample(date:now,percent:40,temperature:25,connected:true),policy:config.policy).action,.inhibitCharge)
  }
  for mode in [ChargeMode.automatic,.paused,.topUp,.calibration] {
   var config = Configuration(); config.policy.departure = now
   config.setAutomationMode(mode)
   XCTAssertEqual(config.policy.departure,now)
  }
 }

}
