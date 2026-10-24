import XCTest
@testable import ChargeCore

private final class FirmwareFixture {
 var events: [String] = []
 var failure: String?
 var lease = ControlLease()
 var now: TimeInterval = 100
 func event(_ value: String) throws { events.append(value); if failure == value { throw FirmwareSessionError.rejected("injected") } }
 lazy var session = FirmwareControlSession(status: { try self.event("status"); return "fixture status" }, preflight: { try self.event("preflight") }, beforeMutation: { try self.event("arm"); self.lease.request(at:self.now) }, limit: { try self.event("limit:\($0)") }, inhibit: { try self.event("inhibit") }, discharge: { try self.event("discharge") }, beforeExit: { try self.event("releaseSleep") }, exit: { try self.event("exit:\($0)") })
 func execute(_ value: FirmwareCommand, pending: Bool = false, observer: Bool = true) throws { _ = try session.execute(value,recoveryPending:pending,sleepObserverAvailable:observer) }
}
final class FirmwareControlSessionTests: XCTestCase {
 func testReadOnlySessionStatusDoesNotCreateOrRenewOwnership() {
  let f = FirmwareFixture()
  do {
   let inactive = try f.session.execute(.sessionStatus,recoveryPending:true,sleepObserverAvailable:false)
   XCTAssertTrue(inactive.hasPrefix("session=inactive,")); XCTAssertEqual(f.events,["status"]); XCTAssertFalse(f.session.active)
   try f.execute(.plan(.inhibit,sleepTarget:15)); let last = f.lease.lastRequest; f.events = []; f.now = 150
   let active = try f.session.execute(.sessionStatus,recoveryPending:true,sleepObserverAvailable:false)
   XCTAssertTrue(active.hasPrefix("session=active,")); XCTAssertEqual(f.events,["status"]); XCTAssertEqual(f.lease.lastRequest,last)
  } catch { XCTFail("\(error)") }
 }
 func testAtomicPlanCreatesFirstSessionWithTargetAndRequiresObserver() {
  let f = FirmwareFixture()
  do { try f.execute(.plan(.allow,sleepTarget:80),observer:false); XCTFail("observer") } catch {}
  XCTAssertTrue(f.events.isEmpty); XCTAssertFalse(f.session.active)
  do {
   try f.execute(.plan(.inhibit,sleepTarget:15)); XCTAssertTrue(f.session.active); XCTAssertEqual(f.session.sleepTarget,15)
   f.events = []; try f.execute(.plan(.discharge,sleepTarget:65)); XCTAssertTrue(f.session.discharging); XCTAssertEqual(f.session.sleepTarget,65)
   XCTAssertEqual(f.events,["preflight","arm","discharge"])
   f.events = []; _ = try f.session.applySleep(recoveryPending:false); XCTAssertEqual(f.events,["preflight","arm","limit:65"])
   XCTAssertFalse(f.session.discharging)
  } catch { XCTFail("\(error)") }
 }
 func testAtomicPlanFailureKeepsPreviousStateForRecovery() {
  let f = FirmwareFixture()
  do { try f.execute(.plan(.discharge,sleepTarget:65)); XCTFail("inactive") } catch {}
  XCTAssertTrue(f.events.isEmpty)
  do {
   try f.execute(.plan(.inhibit,sleepTarget:15)); f.failure = "limit:100"
   do { try f.execute(.plan(.allow,sleepTarget:80)); XCTFail("failed action") } catch {}
   XCTAssertEqual(f.session.sleepTarget,15); XCTAssertTrue(f.session.active)
   f.failure = nil; try f.execute(.plan(.discharge,sleepTarget:65))
   XCTAssertTrue(f.session.requiresRecoveryAfterFailure(.plan(.allow,sleepTarget:80)))
  } catch { XCTFail("\(error)") }
 }
 func testPendingSleepRetriesCleanupAndRetainsStateOnFailure() {
  let f = FirmwareFixture()
  do {
   try f.execute(.limit(80)); try f.execute(.sleepTarget(65)); try f.execute(.discharge); f.events = []
   do { _ = try f.session.reconcileSleep(recoveryPending:true,restore:{try f.event("restore"); throw FirmwareSessionError.rejected("cleanup")}); XCTFail("must fail") } catch {}
   XCTAssertEqual(f.events,["restore"]); XCTAssertTrue(f.session.discharging); XCTAssertEqual(f.session.sleepTarget,65)
   f.events = []; let result = try f.session.reconcileSleep(recoveryPending:true,restore:{try f.event("restore")})
   XCTAssertEqual(result,.restored); XCTAssertEqual(f.events,["restore"]); XCTAssertFalse(f.session.active); XCTAssertFalse(f.session.discharging); XCTAssertNil(f.session.sleepTarget)
  } catch { XCTFail("\(error)") }
 }
 func testSleepPolicyFailureImmediatelyAttemptsCleanup() {
  for cleanupFails in [false,true] {
   let f = FirmwareFixture()
   do {
    try f.execute(.limit(80)); try f.execute(.sleepTarget(65)); try f.execute(.discharge); f.events = []; f.failure = "limit:65"
    do {
     let result = try f.session.reconcileSleep(recoveryPending:false,restore:{try f.event("restore"); if cleanupFails { throw FirmwareSessionError.rejected("cleanup") }})
     XCTAssertFalse(cleanupFails); XCTAssertEqual(result,.restored); XCTAssertFalse(f.session.active)
    } catch { XCTAssertTrue(cleanupFails); XCTAssertTrue(f.session.active); XCTAssertTrue(f.session.discharging) }
    XCTAssertEqual(f.events,["preflight","arm","limit:65","restore"])
   } catch { XCTFail("\(error)") }
  }
 }
 func testFailedDischargeControlPreflightStillRequiresRootRecovery() {
  let f = FirmwareFixture()
  do {
   try f.execute(.limit(80)); try f.execute(.sleepTarget(65)); try f.execute(.discharge)
   let request = f.lease.lastRequest; f.events = []; f.failure = "preflight"
   do { try f.execute(.limit(70)); XCTFail("must fail") } catch {}
   XCTAssertEqual(f.events,["preflight"]); XCTAssertEqual(f.lease.lastRequest,request)
   for command in [FirmwareCommand.allow,.inhibit,.limit(70),.discharge,.exit(75)] { XCTAssertTrue(f.session.requiresRecoveryAfterFailure(command)) }
   for command in [FirmwareCommand.status,.sleepOff,.sleepTarget(65)] { XCTAssertFalse(f.session.requiresRecoveryAfterFailure(command)) }
   f.session.reset(); XCTAssertFalse(f.session.requiresRecoveryAfterFailure(.discharge))
  } catch { XCTFail("\(error)") }
 }
 func testDischargeRequiresOwnedSessionObserverAndSleepTarget() {
  let f = FirmwareFixture()
  do { try f.execute(.discharge); XCTFail("inactive") } catch {}
  XCTAssertTrue(f.events.isEmpty)
  do {
   try f.execute(.limit(80)); f.events = []
   do { try f.execute(.discharge); XCTFail("no sleep target") } catch {}
   XCTAssertTrue(f.events.isEmpty)
   try f.execute(.sleepTarget(65))
   do { try f.execute(.discharge,observer:false); XCTFail("no observer") } catch {}
   XCTAssertTrue(f.events.isEmpty)
   try f.execute(.discharge); XCTAssertEqual(f.events,["preflight","arm","discharge"]); XCTAssertTrue(f.session.discharging)
   f.events = []; do { try f.execute(.sleepOff); XCTFail("must retain sleep target") } catch {}
   XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.session.sleepTarget,65)
   _ = try f.session.applySleep(recoveryPending:false)
   XCTAssertEqual(f.events,["preflight","arm","limit:65"]); XCTAssertFalse(f.session.discharging)
   try f.execute(.sleepOff); XCTAssertNil(f.session.sleepTarget)
  } catch { XCTFail("\(error)") }
 }
 func testDischargeFailureNeverPublishesNewSuccessAndKeepsCleanupState() {
  let f = FirmwareFixture()
  do {
   try f.execute(.limit(80)); try f.execute(.sleepTarget(15)); f.events = []; f.failure = "discharge"
   do { try f.execute(.discharge); XCTFail("must fail") } catch {}
   XCTAssertFalse(f.session.discharging); XCTAssertTrue(f.session.active)
   XCTAssertEqual(f.events,["preflight","arm","discharge"])
   f.failure = nil; try f.execute(.discharge); f.failure = "inhibit"
   do { _ = try f.session.applySleep(recoveryPending:false); XCTFail("must fail") } catch {}
   XCTAssertTrue(f.session.discharging); XCTAssertEqual(f.session.sleepTarget,15)
   f.failure = nil; try f.execute(.inhibit); XCTAssertFalse(f.session.discharging)
   try f.execute(.discharge); try f.execute(.exit(75)); XCTAssertFalse(f.session.active); XCTAssertFalse(f.session.discharging)
  } catch { XCTFail("\(error)") }
 }
 func testReadOnlyStatusDoesNotArmOrRenewLease() {
  let f = FirmwareFixture()
  do { try f.execute(.limit(65)); let request = f.lease.lastRequest; f.events = []; f.now = 140; try f.execute(.status,pending:true)
   XCTAssertEqual(f.events,["status"]); XCTAssertEqual(f.lease.lastRequest,request); XCTAssertTrue(f.session.active)
  } catch { XCTFail("\(error)") }
 }
 func testMutationOrderingAndRejectedPreflight() {
  for command in [FirmwareCommand.allow,.inhibit,.limit(20),.limit(100)] {
   let f = FirmwareFixture()
   do { try f.execute(command); XCTAssertEqual(Array(f.events.prefix(2)),["preflight","arm"]); XCTAssertEqual(f.events.count,3); XCTAssertTrue(f.session.active) } catch { XCTFail("\(error)") }
  }
  let f = FirmwareFixture(); f.failure = "preflight"
  do { try f.execute(.limit(80)); XCTFail("must fail") } catch {}
  XCTAssertEqual(f.events,["preflight"]); XCTAssertFalse(f.session.active); XCTAssertTrue(f.lease.expired(at:100))
 }
 func testInvalidAndPendingRequestsHaveNoCallbacks() {
  for command in [FirmwareCommand.limit(19),.exit(15),.sleepTarget(16)] {
   let f = FirmwareFixture(); do { try f.execute(command); XCTFail("must reject") } catch {}
   XCTAssertTrue(f.events.isEmpty)
  }
  for command in [FirmwareCommand.allow,.inhibit,.limit(65),.exit(65),.sleepTarget(65)] {
   let f = FirmwareFixture(); do { try f.execute(command,pending:true); XCTFail("must reject") } catch {}
   XCTAssertTrue(f.events.isEmpty)
  }
 }
 func testSleepTargetRequiresSessionAndObserver() {
  let f = FirmwareFixture()
  do { try f.execute(.sleepTarget(65)); XCTFail("inactive") } catch {}
  do {
   try f.execute(.limit(80)); f.events = []
   do { try f.execute(.sleepTarget(65),observer:false); XCTFail("missing observer") } catch {}
   XCTAssertNil(f.session.sleepTarget); XCTAssertTrue(f.events.isEmpty)
   try f.execute(.sleepTarget(65)); XCTAssertEqual(f.session.sleepTarget,65)
   let blocked = try f.session.applySleep(recoveryPending:true); XCTAssertFalse(blocked); XCTAssertTrue(f.events.isEmpty)
   f.lease.beginSleep(); f.now = 1000
   let applied = try f.session.applySleep(recoveryPending:false); XCTAssertTrue(applied); XCTAssertEqual(f.events,["preflight","arm","limit:65"])
   XCTAssertFalse(f.lease.expired(at:2000)); f.lease.wake(at:2000); XCTAssertFalse(f.lease.expired(at:2045)); XCTAssertTrue(f.lease.expired(at:2046))
   f.events = []; try f.execute(.sleepTarget(15)); let inhibited = try f.session.applySleep(recoveryPending:false); XCTAssertTrue(inhibited); XCTAssertEqual(f.events,["preflight","arm","inhibit"])
   try f.execute(.sleepOff); f.events = []; let idle = try f.session.applySleep(recoveryPending:false); XCTAssertFalse(idle); XCTAssertTrue(f.events.isEmpty)
  } catch { XCTFail("\(error)") }
 }
 func testOrderlyExitClearsStateOnlyAfterSuccessfulCommit() {
  let f = FirmwareFixture()
  do { try f.execute(.exit(75)); XCTFail("inactive") } catch {}
  XCTAssertTrue(f.events.isEmpty)
  do {
   try f.execute(.limit(80)); try f.execute(.sleepTarget(65)); f.events = []
   try f.execute(.exit(75)); XCTAssertEqual(f.events,["preflight","arm","releaseSleep","exit:75"])
   XCTAssertFalse(f.session.active); XCTAssertNil(f.session.sleepTarget)
   let inactive = try f.session.applySleep(recoveryPending:false); XCTAssertFalse(inactive)
  } catch { XCTFail("\(error)") }
 }
 func testFailedExitAndSleepKeepStateForRecovery() {
  for point in ["releaseSleep","exit:75"] {
   let f = FirmwareFixture()
   do { try f.execute(.limit(80)); try f.execute(.sleepTarget(65)); f.events = []; f.failure = point
    do { try f.execute(.exit(75)); XCTFail("must fail") } catch {}
    XCTAssertTrue(f.session.active); XCTAssertEqual(f.session.sleepTarget,65); XCTAssertEqual(Array(f.events.prefix(2)),["preflight","arm"])
    f.session.reset(); XCTAssertFalse(f.session.active); XCTAssertNil(f.session.sleepTarget)
   } catch { XCTFail("\(error)") }
  }
  let f = FirmwareFixture()
  do { try f.execute(.inhibit); try f.execute(.sleepTarget(65)); f.failure = "limit:65"
   do { try f.session.applySleep(recoveryPending:false); XCTFail("must fail") } catch {}
   XCTAssertTrue(f.session.active); XCTAssertEqual(f.session.sleepTarget,65)
  } catch { XCTFail("\(error)") }
 }
}
