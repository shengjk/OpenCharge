import XCTest
@testable import ChargeCore

final class SleepProtectionTests: XCTestCase {
 private func plan(enabled: Bool = true, connected: Bool = true, physical: Bool? = true, action: ChargeAction = .allowCharge, percent: Double = 50, target: Double = 80, calibration: Bool = false, idle: Bool = true, full: Bool = true, display: Bool = true) -> SleepProtectionPlan {
  .evaluate(controlEnabled: enabled, connected: connected, physicalAdapterConnected: physical, action: action, percent: percent, target: target, calibrating: calibration, idleUntilTarget: idle, systemUntilTarget: full, allowDisplaySleep: display)
 }
 func testMonitoringUnplugAndUnknownDoNotAssert() {
  for p in [plan(enabled: false), plan(physical: false), plan(connected: false, physical: nil)] {
   XCTAssertFalse(p.preventIdleSleep); XCTAssertFalse(p.preventSystemAndLidSleep); XCTAssertFalse(p.preventDisplaySleep)
  }
 }
 func testOwnedDischargeUsesPhysicalAdapter() {
  let p = plan(connected: false, action: .forceDischarge, percent: 90)
  XCTAssertTrue(p.preventIdleSleep); XCTAssertTrue(p.preventSystemAndLidSleep)
  XCTAssertFalse(plan(connected: false, physical: false, action: .forceDischarge).preventSystemAndLidSleep)
 }
 func testCompletionPauseAndInvalidValuesRelease() {
  for p in [plan(percent: 80), plan(action: .inhibitCharge), plan(action: .restore), plan(action: .restore, calibration: true), plan(percent: .nan), plan(target: .infinity)] {
   XCTAssertFalse(p.preventIdleSleep); XCTAssertFalse(p.preventSystemAndLidSleep)
  }
 }
 func testSeparateOptInsAndCalibrationDisplayPrecedence() {
  let idle = plan(full: false); XCTAssertTrue(idle.preventIdleSleep); XCTAssertFalse(idle.preventSystemAndLidSleep)
  let full = plan(idle: false, display: false); XCTAssertFalse(full.preventIdleSleep); XCTAssertTrue(full.preventSystemAndLidSleep); XCTAssertTrue(full.preventDisplaySleep)
  let calibration = plan(action: .inhibitCharge, percent: 100, calibration: true, idle: false)
  XCTAssertTrue(calibration.preventIdleSleep); XCTAssertTrue(calibration.preventSystemAndLidSleep); XCTAssertTrue(calibration.preventDisplaySleep)
  let publicOnly = plan(calibration: true, idle: false, full: false)
  XCTAssertTrue(publicOnly.preventIdleSleep); XCTAssertFalse(publicOnly.preventDisplaySleep)
 }
 func testMutuallyExclusiveSleepPolicyAndImportedOverride() {
  var c = Configuration(); c.hardwareEnabled = true; c.policy.keepAwakeWithLidClosed = true; c.policy.stopInSleep = true
  c.policy.normalize(); XCTAssertFalse(c.policy.stopInSleep)
  let restored = try? ConfigurationBackup.restored(from: ConfigurationBackup(configuration: c).encoded())
  XCTAssertEqual(restored?.policy.keepAwakeWithLidClosed, false); XCTAssertEqual(restored?.policy.allowDisplaySleep, true); XCTAssertEqual(restored?.hardwareEnabled, false)
 }
}
