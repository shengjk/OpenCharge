import XCTest
@testable import ChargeCore

final class SleepProtectionTests: XCTestCase {
 func testFullChargeHoldReleasesSelectedProtectionWithoutInterruptingCalibration() {
  for calibration in [false, true] {
   let full = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
    action: .allowCharge, percent: 99.999998, target: 100, calibrating: calibration,
    idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true, fullChargeHold: true)
   XCTAssertEqual(full.preventIdleSleep, calibration)
   XCTAssertEqual(full.preventSystemAndLidSleep, calibration)
   XCTAssertEqual(full.preventDisplaySleep, calibration)
  }
 }
 func testHelperRequiresExactInterfaceAndRecoveryProtocol() {
  XCTAssertTrue(SleepProtectionPlan.supportsHelper("model:fixture, sleepOverride:interfacesDetected, sleepRecovery:phasesV1"))
  for caps in ["sleepOverride:interfacesDetected", "sleepRecovery:phasesV1", "sleepOverride:interfacesDetected, sleepRecovery:phasesV10", "prefixsleepOverride:interfacesDetected, sleepRecovery:phasesV1"] {
   XCTAssertFalse(SleepProtectionPlan.supportsHelper(caps))
  }
 }
 private func plan(enabled: Bool = true, connected: Bool = true, physical: Bool? = true, action: ChargeAction = .allowCharge, percent: Double = 50, target: Double = 80, calibration: Bool = false, idle: Bool = true, full: Bool = true, display: Bool = true, lid: Bool? = false) -> SleepProtectionPlan {
  .evaluate(controlEnabled: enabled, connected: connected, physicalAdapterConnected: physical, action: action, percent: percent, target: target, calibrating: calibration, idleUntilTarget: idle, systemUntilTarget: full, allowDisplaySleep: display, lidClosed: lid)
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
 func testOrdinaryOpenLidDischargeLeavesIdleProtectionOptional() {
  let p = plan(action: .forceDischarge, idle: false, full: false)
  XCTAssertFalse(p.preventIdleSleep)
  XCTAssertFalse(p.preventSystemAndLidSleep)
 }
 func testOwnedInputCutKeepsProtectionUnlessExplicitlyUnplugged() {
  for physical in [true, false, nil] as [Bool?] {
   let p = SleepProtectionPlan.evaluate(controlEnabled: true, connected: false, physicalAdapterConnected: physical,
    action: .forceDischarge, percent: 90, target: 80, calibrating: false,
    idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true, lidClosed: true, ownAdapterInhibited: true)
   XCTAssertFalse(p.preventIdleSleep)
   XCTAssertEqual(p.preventSystemAndLidSleep, physical != false)
  }
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
 func testCalibrationDischargesClosedLid() {
  var e = ChargeEngine(); var p = ChargePolicy(); p.mode = .calibration
  _ = e.decide(ChargeSample(percent: 100), policy: p)
  XCTAssertEqual(e.decide(ChargeSample(percent: 80, lidClosed: true), policy: p).action, .forceDischarge)
  var returning = ChargeEngine(checkpoint: CalibrationCheckpoint(stage: .returning))
  XCTAssertEqual(returning.decide(ChargeSample(percent: 90, lidClosed: true), policy: p).action, .forceDischarge)
 }
 func testClamshellDischargeNeedsFullProtectionWithoutOptionalLimitSetting() {
  let p = plan(connected: false, action: .forceDischarge, percent: 90, idle: false, full: false, lid: true)
  XCTAssertFalse(p.preventIdleSleep); XCTAssertTrue(p.preventSystemAndLidSleep); XCTAssertFalse(p.preventDisplaySleep)
  XCTAssertFalse(plan(action: .forceDischarge, full: false).preventSystemAndLidSleep)
 }
 func testDischargeLidAndDisplayTransitionsReleaseAtCompletion() {
  let lids: [Bool?] = [false, true, nil]
  for lid in lids {
   for allowDisplay in [false, true] {
    let p = plan(action: .forceDischarge, idle: false, full: false, display: allowDisplay, lid: lid)
    XCTAssertFalse(p.preventIdleSleep)
    XCTAssertEqual(p.preventSystemAndLidSleep, lid != false)
    XCTAssertEqual(p.preventDisplaySleep, lid != false && !allowDisplay)
    for released in [plan(enabled: false, action: .forceDischarge, lid: lid), plan(physical: false, action: .forceDischarge, lid: lid), plan(action: .inhibitCharge, lid: lid), plan(action: .restore, lid: lid)] {
     XCTAssertFalse(released.preventIdleSleep); XCTAssertFalse(released.preventSystemAndLidSleep); XCTAssertFalse(released.preventDisplaySleep)
    }
   }
  }
 }
 func testConfirmedThermalWaitKeepsOnlySelectedUntilTargetProtection() {
  for idle in [false, true] {
   for full in [false, true] {
    let p = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
     action: .inhibitCharge, percent: 50, target: 80, calibrating: false,
     idleUntilTarget: idle, systemUntilTarget: full, allowDisplaySleep: true, thermalHold: true)
    XCTAssertEqual(p.preventIdleSleep, idle); XCTAssertEqual(p.preventSystemAndLidSleep, full)
   }
  }
  for percent in [80.0, 90, .nan] {
   let p = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
    action: .inhibitCharge, percent: percent, target: 80, calibrating: false,
    idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true, thermalHold: true)
   XCTAssertFalse(p.preventIdleSleep); XCTAssertFalse(p.preventSystemAndLidSleep)
  }
 }
 func testMutuallyExclusiveSleepPolicyAndImportedOverride() {
  var c = Configuration(); c.hardwareEnabled = true; c.policy.keepAwakeWithLidClosed = true; c.policy.stopInSleep = true; c.policy.lockScreenWhenClosed = true
  c.policy.normalize(); XCTAssertFalse(c.policy.stopInSleep)
  let restored = try? ConfigurationBackup.restored(from: ConfigurationBackup(configuration: c).encoded())
  XCTAssertEqual(restored?.policy.keepAwakeWithLidClosed, false); XCTAssertEqual(restored?.policy.allowDisplaySleep, true); XCTAssertEqual(restored?.hardwareEnabled, false); XCTAssertEqual(restored?.policy.lockScreenWhenClosed, false)
 }
}
