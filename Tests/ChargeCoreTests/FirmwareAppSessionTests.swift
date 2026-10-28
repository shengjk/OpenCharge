import XCTest
@testable import ChargeCore

private let appCapabilities = "firmwareProtocol:fixedV1,firmwareRead:CH0B+BCLM,firmwareWrite:fixedV1,internalBattery:present,chargeRecovery:ready,firmwarePlan:atomicSleepV1,firmwareDischarge:inflowV1,firmwareExit:preparedV1"
private final class AppFixture {
 var calls: [String] = []
 var failure: String?
 var allowed: String = "inhibited"
 var value = 80
 var active = true
 lazy var app = try! FirmwareAppSession(capabilities:appCapabilities)
 func request(_ command: String) throws -> String {
  calls.append(command)
  if failure == command { throw FirmwareSessionError.rejected("fixture") }
  if command == "firmwareSessionStatus" { return "session=\(active ? "active" : "inactive"),limit=\(value),charging=\(allowed)" }
  if case .plan(let action, _)? = FirmwareCommand.parse(command) { value = action == .allow ? 100 : 15 }
  return "fixture acknowledgment"
 }
}
final class FirmwareAppSessionTests: XCTestCase {
 func testUnexecutedSleepRejectionDoesNotInventNumericOwnership() {
  let f = AppFixture(); let p = ChargePolicy()
  do {
   do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:{ _ in throw ChargeControlSuspension.systemSleep }); XCTFail("suspended action") }
   catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong rejection") }
   XCTAssertFalse(f.app.mayOwnSession); XCTAssertFalse(f.app.cleanupPending); XCTAssertNil(f.app.sleepTarget)
   try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
   XCTAssertTrue(f.app.mayOwnSession); XCTAssertFalse(f.app.cleanupPending)
  } catch { XCTFail("wake retry failed") }
 }
 func testSleepRejectionPreservesExistingSessionWithoutMarkingItAmbiguous() {
  let f = AppFixture(); let p = ChargePolicy()
  do {
   try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
   let target = f.app.sleepTarget
   do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:{ value in
    if value == "firmwareSessionStatus" { return "session=active,limit=15,charging=inhibited" }
    throw ChargeControlSuspension.systemSleep
   }); XCTFail("suspended action") } catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong rejection") }
   XCTAssertTrue(f.app.mayOwnSession); XCTAssertFalse(f.app.cleanupPending); XCTAssertEqual(f.app.sleepTarget,target)
   try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
   XCTAssertFalse(f.app.cleanupPending)
  } catch { XCTFail("existing session lost") }
 }

 func testLostRootSessionStopsEveryCachedActionRegardlessOfRegisterValue() {
  for action in [ChargeAction.allowCharge,.inhibitCharge,.forceDischarge] {
   for limit in [15,80] {
    let f = AppFixture(); let p = ChargePolicy()
    do {
     try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
     f.active = false; f.value = limit; f.calls = []
     do { try f.app.apply(action,policy:p,phase:.charging,request:f.request); XCTFail("lost session") } catch {}
     XCTAssertEqual(f.calls,["firmwareSessionStatus"]); XCTAssertTrue(f.app.cleanupPending); XCTAssertTrue(f.app.mayOwnSession)
     try f.app.restore(request:f.request); XCTAssertFalse(f.app.mayOwnSession)
    } catch { XCTFail("\(error)") }
   }
  }
 }
 func testOldProtocolCannotSelectAppControl() {
  do { _ = try FirmwareAppSession(capabilities:appCapabilities.replacingOccurrences(of:",firmwarePlan:atomicSleepV1",with:"")); XCTFail("old helper") } catch {}
  do { _ = try FirmwareAppSession(capabilities:appCapabilities.replacingOccurrences(of:"ready",with:"pending")); XCTFail("pending helper") } catch {}
 }
 func testFirstAllowRegistersSleepTargetInSameRequest() {
  let f = AppFixture(); var p = ChargePolicy(); p.limit = 80; p.stopInSleep = true
  do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
   XCTAssertEqual(f.calls,["firmwarePlan:allow:80"]); XCTAssertTrue(f.app.mayOwnSession); XCTAssertEqual(f.app.sleepTarget,80)
  } catch { XCTFail("\(error)") }
 }
 func testSafeBootstrapPrecedesRequiredProtectionAndNeverAllowsCharge() {
  let f = AppFixture()
  do {
   try f.app.prepareProtection(request:f.request)
   XCTAssertEqual(f.calls,["firmwarePlan:inhibit:15"])
   f.calls = []; try f.app.prepareProtection(request:f.request); XCTAssertTrue(f.calls.isEmpty)
   try f.app.apply(.allowCharge,policy:ChargePolicy(),phase:.charging,request:f.request)
   XCTAssertEqual(f.calls,["firmwareSessionStatus","firmwarePlan:allow:80"])
  } catch { XCTFail("\(error)") }
 }
 func testDischargeBootstrapAndHeartbeatsPreserveOwnedInflow() {
  let f = AppFixture(); let p = ChargePolicy()
  do {
   try f.app.apply(.forceDischarge,policy:p,phase:.discharging,request:f.request)
   XCTAssertEqual(f.calls,["firmwarePlan:inhibit:15","firmwareSessionStatus","firmwarePlan:discharge:15"])
   f.calls = []; try f.app.apply(.forceDischarge,policy:p,phase:.discharging,request:f.request)
   XCTAssertEqual(f.calls,["firmwareSessionStatus","firmwarePlan:discharge:15"])
   // The root may have applied a different registered limit during sleep.
   f.value = 80; f.calls = []; try f.app.apply(.forceDischarge,policy:p,phase:.discharging,request:f.request)
   XCTAssertEqual(f.calls,["firmwareSessionStatus","firmwarePlan:inhibit:15","firmwareSessionStatus","firmwarePlan:discharge:15"])
  } catch { XCTFail("\(error)") }
 }
 func testUnknownStatusFailsAndConvergentProjectionDoesNotInventBoolean() {
  let f = AppFixture(); var p = ChargePolicy(); f.allowed = "unknown"
  do { try f.app.apply(.inhibitCharge,policy:p,phase:.pause,request:f.request); XCTFail("unknown") } catch {}
  XCTAssertTrue(f.app.mayOwnSession); XCTAssertTrue(f.app.cleanupPending); XCTAssertNil(f.app.status?.chargingAllowed)
  do {
   try f.app.restore(request:f.request); p.sailing = true; f.calls = []
   try f.app.apply(.inhibitCharge,policy:p,phase:.sailing,request:f.request)
   XCTAssertEqual(f.calls.last,"firmwarePlan:inhibit:75"); XCTAssertNil(f.app.status?.chargingAllowed)
  } catch { XCTFail("\(error)") }
 }
 func testExitUsesCurrentExitPhaseAndAmbiguousPreparationRetriesSameIdentity() {
  let f = AppFixture(); var p = ChargePolicy(); p.sailing = true
  do {
   try f.app.apply(.inhibitCharge,policy:p,phase:.sailing,request:f.request); f.calls = []
   do { try f.app.prepareExit(policy:p,phase:.exit,active:true,request:{f.calls.append($0);throw FirmwareSessionError.rejected("lost reply")}); XCTFail("delivery failure") } catch {}
   let first = f.calls[0]
   XCTAssertEqual(FirmwareCommand.parse(first),.exitPrepare(80,f.app.preparedExit!.id))
   XCTAssertTrue(f.app.cleanupPending); XCTAssertTrue(f.app.mayOwnSession)
   f.calls = []; try f.app.prepareExit(policy:p,phase:.exit,active:true,request:f.request)
   XCTAssertEqual(f.calls,[first]); XCTAssertFalse(f.app.cleanupPending); XCTAssertTrue(f.app.mayOwnSession)
   f.calls = []; try f.app.renewExitPreparation(request:f.request); XCTAssertEqual(f.calls,[first])
   try f.app.restore(request:f.request); XCTAssertFalse(f.app.mayOwnSession); XCTAssertNil(f.app.preparedExit)
  } catch { XCTFail("\(error)") }
 }
 func testFinalCommitFailureRetriesSameTokenAndCannotClaimCancellationRollback() {
  let f = AppFixture(), p = ChargePolicy()
  do {
   try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request)
   try f.app.prepareExit(policy:p,phase:.exit,active:true,request:f.request)
   let command = FirmwareCommand.exitCommit(f.app.preparedExit!.id).wireValue!
   f.failure = command; f.calls = []
   do { try f.app.commitExit(request:f.request); XCTFail("lost commit reply") } catch {}
   XCTAssertTrue(f.app.exitCommitAttempted); XCTAssertTrue(f.app.cleanupPending)
   XCTAssertEqual(f.calls,[command]); f.calls = []
   do { try f.app.restore(request:f.request); XCTFail("cannot prove committed target rollback") } catch {}
   do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request); XCTFail("new control while confirming") } catch {}
   try f.app.renewExitPreparation(request:f.request)
   XCTAssertTrue(f.calls.isEmpty)
   f.failure = nil; try f.app.commitExit(request:f.request)
   XCTAssertEqual(f.calls,[command]); XCTAssertFalse(f.app.mayOwnSession); XCTAssertTrue(f.app.exitCommitAttempted)
   f.calls = []; try f.app.commitExit(request:f.request); XCTAssertTrue(f.calls.isEmpty)
  } catch { XCTFail("\(error)") }
 }
 func testOldHelperCannotSilentlyFallBackToIrreversibleExit() {
  do {
   let app = try FirmwareAppSession(capabilities:appCapabilities.replacingOccurrences(of:",firmwareExit:preparedV1",with:""))
   try app.apply(.allowCharge,policy:ChargePolicy(),phase:.charging,request:{_ in "ack"})
   var calls: [String] = []
   do { try app.prepareExit(policy:ChargePolicy(),phase:.exit,active:true,request:{calls.append($0);return "unexpected"}); XCTFail("old helper") } catch {}
   XCTAssertTrue(calls.isEmpty); XCTAssertTrue(app.mayOwnSession); XCTAssertNil(app.preparedExit)
   try app.restore(request:{calls.append($0);return "ack"}); XCTAssertEqual(calls,["restore"])
  } catch { XCTFail("\(error)") }
 }

 func testFailedMutationAndFailedRestoreRetainCleanupResponsibility() {
  let f = AppFixture(); let p = ChargePolicy(); f.failure = "firmwarePlan:allow:80"
  do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request); XCTFail("must fail") } catch {}
  XCTAssertTrue(f.app.mayOwnSession); XCTAssertTrue(f.app.cleanupPending)
  f.calls = []; do { try f.app.apply(.allowCharge,policy:p,phase:.charging,request:f.request); XCTFail("pending") } catch {}
  XCTAssertTrue(f.calls.isEmpty)
  f.failure = "restore"; do { try f.app.restore(request:f.request); XCTFail("restore failure") } catch {}
  XCTAssertTrue(f.app.mayOwnSession); XCTAssertTrue(f.app.cleanupPending)
  f.failure = nil; do { try f.app.restore(request:f.request) } catch { XCTFail("\(error)") }
  XCTAssertFalse(f.app.mayOwnSession); XCTAssertFalse(f.app.cleanupPending)
 }
 func testMissingDischargeExtensionAndInvalidPolicyDoNotMutate() {
  do {
   let s = try FirmwareAppSession(capabilities:appCapabilities.replacingOccurrences(of:",firmwareDischarge:inflowV1",with:"")); var calls: [String] = []
   do { try s.apply(.forceDischarge,policy:ChargePolicy(),phase:.discharging,request:{calls.append($0);return "fixture"}); XCTFail("unsupported") } catch {}
   XCTAssertTrue(calls.isEmpty); XCTAssertFalse(s.mayOwnSession)
   var p = ChargePolicy(); p.limit = .nan
   do { try s.apply(.allowCharge,policy:p,phase:.charging,request:{calls.append($0);return "fixture"}); XCTFail("invalid") } catch {}
   XCTAssertTrue(calls.isEmpty)
  } catch { XCTFail("\(error)") }
 }
}
