import XCTest
@testable import ChargeCore

final class DischargeSleepEntryTests: XCTestCase {
 func testOnlyDischargingPhaseCanAttachFiniteMetadata() {
  let numeric = FirmwareCommand.plan(.discharge,sleepTarget:80).wireValue!
  for phase in PolicyPhase.allCases {
   for count in [-1,0,1,2,5] {
    for command in ["forceDischarge",numeric] {
     let wire = DischargeSleepRequest.wrap(command,phase:phase,screenCount:count)
     XCTAssertEqual(DischargeSleepRequest.underlying(wire),phase == .discharging && count >= 2 ? command : nil)
    }
   }
  }
  for command in ["allowCharge","restore","firmwareDischarge","firmwarePlan:allow:80","forceDischarge\n","multiDisplayDischarge:forceDischarge","firmwarePlan:discharge:080","firmwarePlan:discharge:19"] {
   XCTAssertNil(DischargeSleepRequest.underlying("multiDisplayDischarge:system:"+command))
  }
 }
 func testEnvelopeRetainsEpochAdmissionForEveryFiniteDischargePlan() {
  do {
  var transition = ChargePowerTransition()
  let context = ChargeRequestContext(reply:transition.contextReply)!
  let largest = ChargeRequestContext(reply:"epoch="+String(repeating:"a",count:32)+"-18446744073709551615,state=awake")!
  for command in ["forceDischarge"] + ([15]+Array(20...100)).map({ FirmwareCommand.plan(.discharge,sleepTarget:$0).wireValue! }) {
   let payload = DischargeSleepRequest.wrap(command,phase:.discharging,screenCount:2)
   let wire = try context.envelope(payload)
   XCTAssertTrue(wire.utf8.count < 128)
   let largestWire = try largest.envelope(DischargeSleepRequest.wrap(command,phase:.discharging,screenCount:2,preventDisplaySleep:true))
   XCTAssertTrue(ChargeRequestContext.parseEnvelope(largestWire) != nil); XCTAssertTrue(largestWire.utf8.count < 128)
   let admitted = try transition.admittedCommand(wire)
   XCTAssertEqual(admitted,payload)
  }
  let payload = DischargeSleepRequest.wrap("forceDischarge",phase:.discharging,screenCount:2)
  let stale = try context.envelope(payload)
  transition.willSleep()
  do { _ = try transition.admittedCommand(payload); XCTFail("sleep accepted") } catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong error") }
  do { _ = try transition.admittedCommand(stale); XCTFail("stale accepted") } catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong error") }
  transition.didWake()
  do { _ = try transition.admittedCommand(stale); XCTFail("stale accepted") } catch ChargeControlSuspension.systemSleep {} catch { XCTFail("wrong error") }
  } catch { XCTFail("unexpected context error") }
 }
 func testSnapshotRequiresFreshKnownInputsAndExplicitOwnership() {
  var entry = DischargeSleepEntry()
  func selected(_ time: Double = 100, discharge: Bool = true, connected: Bool? = true, lid: Bool? = true, pending: Bool = false) -> Bool {
   entry.qualifies(at:time,discharging:discharge,connected:connected,lidClosed:lid,recoveryPending:pending)
  }
  XCTAssertFalse(selected())
  entry.accept(multipleDisplays:true,at:100)
  XCTAssertTrue(selected()); XCTAssertTrue(selected(145))
  for time in [99,145.001,.infinity,.nan] { XCTAssertFalse(selected(time)) }
  XCTAssertFalse(selected(discharge:false)); XCTAssertFalse(selected(connected:false)); XCTAssertFalse(selected(connected:nil))
  XCTAssertFalse(selected(lid:false)); XCTAssertFalse(selected(lid:nil)); XCTAssertFalse(selected(pending:true))
  entry.accept(multipleDisplays:false,at:101); XCTAssertFalse(selected(101))
  entry.accept(multipleDisplays:true,at:.nan); XCTAssertFalse(selected())
  entry.accept(multipleDisplays:true,at:100); entry.clear(); XCTAssertFalse(selected())
 }
 func testEveryFailureCombinationStillAttemptsIndependentRequests() {
  enum Fault: Error { case requested }
  for mask in 0..<8 {
   var events: [DischargeSleepEntry.Step] = []
   func act(_ step: DischargeSleepEntry.Step, _ bit: Int) throws {
    events.append(step); if mask & bit != 0 { throw Fault.requested }
   }
   let result = DischargeSleepEntry.perform(allow:{try act(.allow,1)},protect:{try act(.protection,2)},activity:{try act(.activity,4)})
   XCTAssertEqual(events,[.allow,.protection,.activity])
   XCTAssertEqual(result.succeeded,mask == 0)
   for (step,bit) in zip(DischargeSleepEntry.Step.allCases,[1,2,4]) { XCTAssertEqual(result.failures[step] != nil,mask & bit != 0) }
  }
 }
 func testCapabilityRequiresIndependentEpochAndExactExtension() {
  let cap = "chargeTransition:epochV1,dischargeSleep:displaySnapshotV1"
  XCTAssertTrue(DischargeSleepRequest.supportsHelper(cap))
  for bad in ["dischargeSleep:displaySnapshotV1",cap+",dischargeSleep:future",cap+",dischargeSleep:displaySnapshotV1",cap+"\n"] {
   XCTAssertFalse(DischargeSleepRequest.supportsHelper(bad))
  }
 }
}
