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
}
