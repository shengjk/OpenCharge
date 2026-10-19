import XCTest
@testable import ChargeCore

final class SleepProtectionTests: XCTestCase {
 func testHelperRequiresExactInterfaceAndRecoveryProtocol() {
  XCTAssertTrue(SleepProtectionPlan.supportsHelper("model:fixture, sleepOverride:interfacesDetected, sleepRecovery:phasesV1"))
  for caps in ["sleepOverride:interfacesDetected", "sleepRecovery:phasesV1", "sleepOverride:interfacesDetected, sleepRecovery:phasesV10", "prefixsleepOverride:interfacesDetected, sleepRecovery:phasesV1"] {
   XCTAssertFalse(SleepProtectionPlan.supportsHelper(caps))
  }
 }
 private func plan(enabled: Bool = true, connected: Bool = true, physical: Bool? = true, action: ChargeAction = .allowCharge, percent: Double = 50, target: Double = 80, calibration: Bool = false, idle: Bool = true, full: Bool = true, display: Bool = true) -> SleepProtectionPlan {
  .evaluate(controlEnabled: enabled, connected: connected, physicalAdapterConnected: physical, action: action, percent: percent, target: target, calibrating: calibration, idleUntilTarget: idle, systemUntilTarget: full, allowDisplaySleep: display)
 }
 func testMonitoringUnplugAndUnknownDoNotAssert() {
  for p in [plan(enabled: false), plan(enabled: false, calibration: true), plan(physical: false, calibration: true), plan(physical: false), plan(connected: false, physical: nil)] {
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
  XCTAssertTrue(publicOnly.preventIdleSleep); XCTAssertTrue(publicOnly.preventSystemAndLidSleep); XCTAssertTrue(publicOnly.preventDisplaySleep)
 }
 func testCalibrationDischargesClosedLidWithoutOrdinaryDischargeOptIn() {
  var e = ChargeEngine(); var p = ChargePolicy(); p.mode = .calibration
  _ = e.decide(ChargeSample(percent: 100), policy: p)
  XCTAssertEqual(e.decide(ChargeSample(percent: 80, lidClosed: true), policy: p).action, .forceDischarge)
  var returning = ChargeEngine(checkpoint: CalibrationCheckpoint(stage: .returning))
  XCTAssertEqual(returning.decide(ChargeSample(percent: 90, lidClosed: true), policy: p).action, .forceDischarge)
 }
 func testClamshellDischargeNeedsFullProtectionWithoutOptionalLimitSetting() {
  let p = SleepProtectionPlan.evaluate(controlEnabled: true, connected: false, physicalAdapterConnected: true, action: .forceDischarge, percent: 90, target: 80, calibrating: false, idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true, clamshellDischarge: true)
  XCTAssertTrue(p.preventSystemAndLidSleep); XCTAssertFalse(p.preventDisplaySleep)
  XCTAssertFalse(plan(action: .forceDischarge, full: false).preventSystemAndLidSleep)
 }
 func testMutuallyExclusiveSleepPolicyAndImportedOverride() {
  var c = Configuration(); c.hardwareEnabled = true; c.policy.keepAwakeWithLidClosed = true; c.policy.stopInSleep = true; c.policy.lockScreenWhenClosed = true
  c.policy.normalize(); XCTAssertFalse(c.policy.stopInSleep)
  let restored = try? ConfigurationBackup.restored(from: ConfigurationBackup(configuration: c).encoded())
  XCTAssertEqual(restored?.policy.keepAwakeWithLidClosed, false); XCTAssertEqual(restored?.policy.allowDisplaySleep, true); XCTAssertEqual(restored?.hardwareEnabled, false); XCTAssertEqual(restored?.policy.lockScreenWhenClosed, false)
 }
}
