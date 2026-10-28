import XCTest
@testable import ChargeCore

private final class PreparedExitFixture {
 var events: [String] = []
 var failure: String?
 func event(_ value: String) throws { events.append(value); if failure == value { throw FirmwareSessionError.rejected("fixture") } }
 lazy var session = FirmwareControlSession(status:{try self.event("status");return "limit=75, charging=allowed"},preflight:{try self.event("preflight")},beforeMutation:{try self.event("arm")},limit:{try self.event("limit:\($0)")},inhibit:{try self.event("inhibit")},discharge:{try self.event("discharge")},beforeExit:{try self.event("releaseSleep")},exit:{try self.event("commit:\($0)")})
 @discardableResult func run(_ command: FirmwareCommand, pending: Bool = false, observer: Bool = true) throws -> String { try session.execute(command,recoveryPending:pending,sleepObserverAvailable:observer) }
 func prepare(_ id: UUID) throws { try run(.plan(.discharge,sleepTarget:65)); try run(.exitPrepare(75,id)) }
}
final class PreparedFirmwareExitTests: XCTestCase {
 func testCanonicalBoundedTransactionCommandsAndIndependentCapability() {
  let id = UUID(uuidString:"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
  for command in [FirmwareCommand.exitPrepare(20,id),.exitPrepare(100,id),.exitCommit(id)] {
   XCTAssertEqual(FirmwareCommand.parse(command.wireValue!),command)
   XCTAssertTrue(command.wireValue!.utf8.count < 128)
  }
  for value in ["firmwareExitPrepare:15:\(id)","firmwareExitPrepare:075:\(id)","firmwareExitPrepare:101:\(id)","firmwareExitPrepare:75:\(id.uuidString.lowercased())","firmwareExitPrepare:75:\(id):extra","firmwareExitCommit:\(id)\n","firmwareExitCommit:garbage","firmwareExitCommit:\(id.uuidString.lowercased())"] { XCTAssertNil(FirmwareCommand.parse(value)) }
  let caps = "firmwareProtocol:fixedV1,firmwareRead:BCLM,firmwareWrite:fixedV1,chargeRecovery:ready,internalBattery:present,firmwarePlan:atomicSleepV1"
  XCTAssertFalse(FirmwareHelperCapabilities.supportsCancellableExit(caps))
  XCTAssertTrue(FirmwareHelperCapabilities.supportsCancellableExit(caps+",firmwareExit:preparedV1"))
  XCTAssertFalse(FirmwareHelperCapabilities.supportsCancellableExit(caps+",firmwareExit:preparedV1,firmwareExit:preparedV1"))
  var transition = ChargePowerTransition(); transition.willSleep()
  do { try transition.requireAdmission(FirmwareCommand.exitPrepare(75,id).wireValue!); try transition.requireAdmission(FirmwareCommand.exitCommit(id).wireValue!) } catch { XCTFail("orderly exit may finish during sleep") }
 }
 func testPreparationRetainsResponsibilityAndRetryDoesNotWriteAgain() {
  let f = PreparedExitFixture(), id = UUID()
  do {
   try f.run(.plan(.inhibit,sleepTarget:65)); try f.run(.plan(.discharge,sleepTarget:65)); f.events = []
   do { try f.run(.exitPrepare(75,id),observer:false); XCTFail("missing sleep observer") } catch {}
   XCTAssertTrue(f.events.isEmpty); XCTAssertNil(f.session.pendingExit)
   try f.run(.exitPrepare(75,id))
   XCTAssertEqual(f.events,["preflight","arm","releaseSleep","limit:75"])
   XCTAssertTrue(f.session.active); XCTAssertFalse(f.session.discharging); XCTAssertNil(f.session.sleepTarget)
   XCTAssertEqual(f.session.pendingExit?.id,id)
   f.events = []; try f.run(.exitPrepare(75,id)); XCTAssertTrue(f.events.isEmpty)
   let applied = try f.session.applySleep(recoveryPending:false); XCTAssertFalse(applied); XCTAssertTrue(f.events.isEmpty)
   for command in [FirmwareCommand.allow,.exit(80),.limit(80),.sleepOff,.sleepTarget(65),.plan(.allow,sleepTarget:80),.exitPrepare(80,id),.exitPrepare(75,UUID()),.exitCommit(UUID())] {
    do { try f.run(command); XCTFail("staged target was replaced") } catch {}
    XCTAssertTrue(f.events.isEmpty)
   }
   for command in ["allowCharge","inhibitCharge","forceDischarge","retainChargeInhibit","sleepPolicyOn","sleepOverrideOn","sleepOverrideDisplayOn"] {
    do { try f.session.requireExternalAdmission(command); XCTFail("external grant while staged") } catch {}
   }
   for command in ["restore","capabilities","magSafeRestore","sleepOverrideRestore"] { try f.session.requireExternalAdmission(command) }
   f.session.reset(); XCTAssertNil(f.session.pendingExit)
   do { try f.run(.exitCommit(id)); XCTFail("restored transaction must not commit") } catch {}
  } catch { XCTFail("\(error)") }
 }
 func testCommitIsExplicitIdempotentAndCannotReplayIntoNewSession() {
  let f = PreparedExitFixture(), id = UUID()
  do {
   try f.run(.plan(.inhibit,sleepTarget:65)); try f.prepare(id); f.events = []
   try f.run(.exitCommit(id)); XCTAssertEqual(f.events,["preflight","arm","commit:75"])
   XCTAssertFalse(f.session.active); XCTAssertNil(f.session.pendingExit)
   f.events = []; try f.run(.exitCommit(id)); XCTAssertTrue(f.events.isEmpty)
   try f.run(.plan(.allow,sleepTarget:80)); f.events = []
   do { try f.run(.exitCommit(id)); XCTFail("old commit entered new session") } catch {}
   XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.session.active)
  } catch { XCTFail("\(error)") }
 }
 func testPreparationAndCommitFailuresRetainRecoverableState() {
  for failure in ["releaseSleep","limit:75","commit:75"] {
   let f = PreparedExitFixture(), id = UUID()
   do {
    try f.run(.plan(.inhibit,sleepTarget:65)); f.failure = failure
    if failure == "commit:75" { try f.run(.exitPrepare(75,id)); do { try f.run(.exitCommit(id)); XCTFail("commit failure") } catch {} }
    else { do { try f.run(.exitPrepare(75,id)); XCTFail("prepare failure") } catch {} }
    XCTAssertTrue(f.session.active)
    if failure == "commit:75" { XCTAssertEqual(f.session.pendingExit?.id,id) }
    f.events = []
    do { try f.run(.exitCommit(id),pending:true); XCTFail("pending recovery") } catch {}
    XCTAssertTrue(f.events.isEmpty)
    f.session.reset(); XCTAssertNil(f.session.pendingExit)
   } catch { XCTFail("\(error)") }
  }
 }
}
