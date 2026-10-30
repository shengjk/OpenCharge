import XCTest
@testable import ChargeCore

private func ordinaryReject<T>(_ expression: @autoclosure () throws -> T) {
 do { _ = try expression(); XCTFail("Expected rejection") } catch {}
}

final class OrdinaryExitTests: XCTestCase {
 func testCanonicalIdentityAndUnambiguousCapability() {
  do {
  let id = UUID(uuidString:"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
  for c in [OrdinaryExitCommand.prepare(id),.commit(id)] {
   XCTAssertEqual(OrdinaryExitCommand.parse(c.wireValue),c)
   XCTAssertTrue(c.wireValue.utf8.count < 128)
   XCTAssertFalse(ChargeRequestContext.requiresScope(c.wireValue))
   var power = ChargePowerTransition(); power.willSleep(); try power.requireAdmission(c.wireValue)
  }
  for v in ["ordinaryExitPrepare:\(id.uuidString.lowercased())","ordinaryExitCommit:\(id):extra","ordinaryExitCommit:\(id)\n","ordinaryExitPrepare:invalid","ordinaryExitCommit:"] { XCTAssertNil(OrdinaryExitCommand.parse(v)) }
  XCTAssertTrue(OrdinaryExitCommand.supportsHelper("chargeRecovery:ready,ordinaryExit:preparedV1"))
  XCTAssertFalse(OrdinaryExitCommand.supportsHelper("ordinaryExit:preparedV1,ordinaryExit:preparedV1"))
  XCTAssertFalse(OrdinaryExitCommand.supportsHelper("ordinaryExit:preparedV1,ordinaryExit:future"))
  } catch { XCTFail("\(error)") }
 }
 func testPrepareRenewCommitAndRestartRetainOriginalJournal() {
  do {
  let s = OrdinaryExitSession(), id = UUID()
  var register = 0, journal: Int?, events: [String] = [], lease = ControlLease()
  func prepare() { events.append("prepare"); journal = register; register = 1; lease.request(at:0) }
  func run(_ c: OrdinaryExitCommand) throws {
   _ = try s.execute(c,recoveryPending:false,available:true,prepare:prepare,renew:{events.append("renew");lease.request(at:30)},commit:{events.append("commit");lease.request(at:30,retained:true)})
  }
  try run(.prepare(id)); XCTAssertEqual(journal,0); XCTAssertEqual(register,1)
  XCTAssertFalse(lease.retained); XCTAssertTrue(lease.expired(at:46))
  try run(.prepare(id)); XCTAssertEqual(events,["prepare","renew"]); XCTAssertFalse(lease.expired(at:60))
  for command in ["allowCharge","inhibitCharge","forceDischarge","retainChargeInhibit","sleepPolicyOn","sleepPolicyOff","sleepOverrideOn","firmwareAllow", "firmwareExit:80"] { ordinaryReject(try s.requireExternalAdmission(command)) }
  for command in ["restore","capabilities","firmwareStatus","sleepOverrideRestore","magSafeRestore"] { try s.requireExternalAdmission(command) }
  ordinaryReject(try run(.prepare(UUID()))); ordinaryReject(try run(.commit(UUID())))
  try run(.commit(id)); XCTAssertTrue(lease.retained); XCTAssertFalse(lease.expired(at:1000))
  events = []; try run(.commit(id)); XCTAssertTrue(events.isEmpty,"lost commit reply retries must not write or replace ownership")
  try s.cleanupForServiceExit(recoveryPending:false,restoreCharge:{XCTFail("committed service exit restored charge")},restoreLED:{events.append("LED")},restoreSleep:{events.append("sleep")})
  XCTAssertEqual(events,["LED","sleep"]); XCTAssertEqual(register,1); XCTAssertEqual(journal,0)
  // A new helper has no in-memory commit receipt and recovers the retained journal.
  let restarted = OrdinaryExitSession()
  try restarted.cleanupForServiceExit(recoveryPending:false,restoreCharge:{register = journal!;journal = nil},restoreLED:{},restoreSleep:{})
  XCTAssertEqual(register,0); XCTAssertNil(journal)
  // New app instances may prepare another exit without first starting charging.
  let next = UUID(); try run(.prepare(next))
  ordinaryReject(try run(.commit(id)))
  try run(.commit(next)); XCTAssertEqual(s.committedID,next)
  ordinaryReject(try restarted.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{}))
  } catch { XCTFail("\(error)") }
 }
 func testUncommittedAndRecoveryCleanupRestoreDespiteOtherFailures() {
  do {
  for committed in [false,true] {
   let s = OrdinaryExitSession(), id = UUID(); var events: [String] = []
   _ = try s.execute(.prepare(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{})
   if committed { _ = try s.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{}) }
   ordinaryReject(try s.cleanupForServiceExit(recoveryPending:committed,restoreCharge:{events.append("charge");throw OrdinaryExitError.rejected("fixture")},restoreLED:{events.append("LED");throw OrdinaryExitError.rejected("fixture")},restoreSleep:{events.append("sleep")}))
   XCTAssertEqual(events,["charge","LED","sleep"])
  }
  } catch { XCTFail("\(error)") }
 }
 func testRejectedAndFailedPreparationCannotGrantRetention() {
  do {
  let s = OrdinaryExitSession(), id = UUID(); var mutations = 0
  for args in [(true,true),(false,false)] {
   ordinaryReject(try s.execute(.prepare(id),recoveryPending:args.0,available:args.1,prepare:{mutations += 1},renew:{},commit:{mutations += 1}))
  }
  XCTAssertEqual(mutations,0)
  ordinaryReject(try s.execute(.prepare(id),recoveryPending:false,available:true,prepare:{throw OrdinaryExitError.rejected("fixture")},renew:{},commit:{}))
  XCTAssertNil(s.preparedID); XCTAssertNil(s.committedID)
  ordinaryReject(try s.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{}))
  _ = try s.execute(.prepare(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{})
  s.reset()
  ordinaryReject(try s.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{}))
  } catch { XCTFail("\(error)") }
 }
 func testAppAmbiguityKeepsIdentityAndAcknowledgedRestoreAllowsCancellation() {
  do {
  let app = OrdinaryExitAppSession(); var wire: [String] = []
  ordinaryReject(try app.prepare { wire.append($0);throw OrdinaryExitError.rejected("fixture") })
  let id = app.id; XCTAssertTrue(id != nil)
  try app.prepare { wire.append($0);return "ordinary exit prepared" }
  XCTAssertEqual(wire[0],wire[1]); XCTAssertEqual(app.id,id)
  ordinaryReject(try app.commit { wire.append($0);throw OrdinaryExitError.rejected("fixture") })
  let lostCommit = wire.last
  try app.commit { wire.append($0);return "ordinary exit committed" }
  XCTAssertEqual(wire.last,lostCommit)
  try app.renew { _ in XCTFail("committed exit must not become an unretained preparation");return "" }
  app.restored(); XCTAssertNil(app.id)
  try app.prepare { wire.append($0);return "ordinary exit prepared" }; XCTAssertNotEqual(app.id,id)
  ordinaryReject(try OrdinaryExitAppSession().prepare { _ in "unexpected" })
  } catch { XCTFail("\(error)") }
 }
}
