import XCTest
@testable import ChargeCore
final class ChargePowerTransitionTests: XCTestCase {
 func testLateControlCannotReplaceSleepPreparation() {
  var transition = ChargePowerTransition()
  let controls = ["allowCharge","inhibitCharge","forceDischarge","sleepPolicyOn","sleepPolicyOff","sleepOverrideOn","sleepOverrideDisplayOn"]
  for command in controls { do { try transition.requireAdmission(command) } catch { XCTFail("awake rejection") } }
  transition.willSleep(); transition.willSleep()
  for command in controls {
   do { try transition.requireAdmission(command); XCTFail("late control accepted: \(command)") }
   catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong rejection") }
  }
  transition.didWake(); transition.didWake()
  for command in controls { do { try transition.requireAdmission(command) } catch { XCTFail("wake must resume") } }
 }
 func testEveryFixedFirmwareCommandHasExplicitSleepAdmission() {
  var transition = ChargePowerTransition(); transition.willSleep()
  for value in FirmwareCommand.supportedActions {
   let command = FirmwareCommand.parse(value)!
   let allowed: Bool
   switch command { case .status,.sessionStatus,.exit: allowed = true; default: allowed = false }
   do { try transition.requireAdmission(value); XCTAssertTrue(allowed,"unexpected sleeping command: \(value)") }
   catch ChargeControlSuspension.systemSleep { XCTAssertFalse(allowed) }
   catch { XCTFail("wrong rejection") }
  }
 }
 func testCleanupAndIndependentPowerModeRemainAvailableDuringSleep() {
  var transition = ChargePowerTransition(); transition.willSleep()
  for command in ["capabilities","restore","sleepOverrideRestore","retainChargeInhibit","magSafeStatus","magSafeRestore","lowPowerStatus","lowPowerOn","lowPowerBatteryOff"] {
   do { try transition.requireAdmission(command) } catch { XCTFail("blocked cleanup or independent control: \(command)") }
  }
  XCTAssertTrue(transition.sleeping,"cleanup admission cannot reopen normal control")
 }
 func testCompletedSleepWakeBetweenRequestsInvalidatesTheWholeRound() {
  var transition = ChargePowerTransition(); let context = ChargeRequestContext(reply:transition.contextReply)!
  do {
   let protect = try context.envelope("sleepOverrideOn")
   XCTAssertEqual(tryAccepted(transition,protect),"sleepOverrideOn")
   transition.willSleep(); transition.didWake()
   for command in ["forceDischarge","firmwareSessionStatus","firmwarePlan:discharge:15","sleepPolicyOff"] {
    do { _ = try transition.admittedCommand(try context.envelope(command)); XCTFail("stale round accepted") }
    catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong stale rejection") }
   }
   let next = ChargeRequestContext(reply:transition.contextReply)!
   XCTAssertNotEqual(next.token,context.token)
   let nextWire = try next.envelope("sleepOverrideOn")
   XCTAssertEqual(tryAccepted(transition,nextWire),"sleepOverrideOn")
  } catch { XCTFail("context setup") }
 }
 private func tryAccepted(_ transition: ChargePowerTransition,_ wire: String) -> String {
  do { return try transition.admittedCommand(wire) } catch { XCTFail("unexpected admission failure"); return "" }
 }
 func testHelperRestartCannotReuseAnAwakeEpoch() {
  let first = ChargePowerTransition(), replacement = ChargePowerTransition()
  let context = ChargeRequestContext(reply:first.contextReply)!
  XCTAssertNotEqual(context.token,ChargeRequestContext(reply:replacement.contextReply)!.token)
  do { _ = try replacement.admittedCommand(try context.envelope("allowCharge")); XCTFail("old helper context") }
  catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong stale rejection") }
 }
 func testContextGrammarAndWrappedAlphabetAreBounded() {
  let token = String(repeating:"a",count:32)+"-0"
  for invalid in ["epoch=\(token),state=awake,extra=1","state=awake,epoch=\(token)","epoch=\(token),state=awake\n","epoch=\(token),state=unknown","epoch="+String(repeating:"a",count:32)+"-00,state=awake","epoch="+String(repeating:"A",count:32)+"-0,state=awake"] { XCTAssertNil(ChargeRequestContext(reply:invalid)) }
  for invalid in ["chargeRequest:\(token):ACLC","chargeRequest:\(token):restore","chargeRequest:\(token):firmwareExit:80","chargeRequest:\(token):forceDischarge\n","chargeRequest:\(token):chargeRequest:\(token):allowCharge","chargeRequest:"+String(repeating:"b",count:129)] { XCTAssertNil(ChargeRequestContext.parseEnvelope(invalid)) }
  var transition = ChargePowerTransition(); transition.willSleep()
  let sleeping = ChargeRequestContext(reply:transition.contextReply)!
  do { _ = try sleeping.envelope("forceDischarge"); XCTFail("sleeping context") }
  catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong suspension") }
 }
 func testEveryScopedFirmwareCommandRetainsItsExactFixedAction() {
  let transition = ChargePowerTransition(); let context = ChargeRequestContext(reply:transition.contextReply)!
  for command in FirmwareCommand.supportedActions {
   do {
    let wire = try context.envelope(command)
    XCTAssertTrue(wire.utf8.count < 128)
    if case .exit? = FirmwareCommand.parse(command) { XCTAssertEqual(wire,command) }
    else { XCTAssertNotEqual(wire,command); XCTAssertTrue(ChargeRequestContext.parseEnvelope(wire) != nil) }
    XCTAssertEqual(tryAccepted(transition,wire),command)
   } catch { XCTFail("valid fixed action lost") }
  }
 }
 func testContextCapabilityIsAnIndependentExactExtension() {
  XCTAssertTrue(ChargeRequestContext.supportsHelper("chargeControl:fixture, chargeTransition:epochV1"))
  for value in ["chargeTransition:epochV2","chargeTransition:epochV1,chargeTransition:epochV1","chargeTransition:epochV1\n","chargeTransition:unavailable",""] { XCTAssertFalse(ChargeRequestContext.supportsHelper(value)) }
 }
 func testDuplicateNotificationsDoNotCreateExtraAwakeRounds() {
  var transition = ChargePowerTransition(); let first = transition.contextReply
  transition.didWake(); XCTAssertEqual(transition.contextReply,first)
  transition.willSleep(); let sleeping = transition.contextReply
  transition.willSleep(); XCTAssertEqual(transition.contextReply,sleeping)
  transition.didWake(); let awake = transition.contextReply
  transition.didWake(); XCTAssertEqual(transition.contextReply,awake)
  XCTAssertNotEqual(first,awake)
 }

 func testAwakeCleanupInvalidatesProtectionFromAnEarlierRound() {
  var transition = ChargePowerTransition(); let context = ChargeRequestContext(reply:transition.contextReply)!
  transition.invalidate()
  XCTAssertFalse(transition.sleeping)
  do { _ = try transition.admittedCommand(try context.envelope("forceDischarge")); XCTFail("retired protection reused") }
  catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong rejection") }
  XCTAssertEqual(tryAccepted(transition,"restore"),"restore")
 }

}
