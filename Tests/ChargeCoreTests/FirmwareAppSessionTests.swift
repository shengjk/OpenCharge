import XCTest
@testable import ChargeCore

private let appCapabilities = "firmwareProtocol:fixedV1,firmwareRead:CH0B+BCLM,firmwareWrite:fixedV1,internalBattery:present,chargeRecovery:ready,firmwarePlan:atomicSleepV1,firmwareDischarge:inflowV1"
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
 func testExitUsesCurrentExitPhaseAndAmbiguousFailureRecovers() {
  let f = AppFixture(); var p = ChargePolicy(); p.sailing = true
  do {
   try f.app.apply(.inhibitCharge,policy:p,phase:.sailing,request:f.request); f.calls = []; f.failure = "firmwareExit:80"
   do { try f.app.finishExit(policy:p,phase:.exit,active:true,request:f.request); XCTFail("delivery failure") } catch {}
   XCTAssertEqual(f.calls,["firmwareExit:80"]); XCTAssertTrue(f.app.cleanupPending); XCTAssertTrue(f.app.mayOwnSession)
   f.failure = nil; f.calls = []; try f.app.finishExit(policy:p,phase:.exit,active:true,request:f.request)
   XCTAssertEqual(f.calls,["restore"]); XCTAssertFalse(f.app.mayOwnSession)
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
