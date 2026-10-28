import XCTest
@testable import ChargeCore

final class OrdinaryQuitRecoveryTests: XCTestCase {
 private enum Failure: Error { case service, storage }
 func testIntentPrecedesCompensationAndClearFollowsAcknowledgement() {
  var config = Configuration(); config.hardwareEnabled = true
  var events: [String] = []; var stored: Configuration?
  do {
   try OrdinaryQuitRecovery.begin(configuration:&config,persist:{ stored=$0; events.append("intent") })
   let reply = try OrdinaryQuitRecovery.restoreIfNeeded(configuration:&config,request:{ command in
    XCTAssertEqual(command,"restore"); XCTAssertEqual(stored?.pendingOrdinaryQuitRecovery,true)
    XCTAssertEqual(stored?.hardwareEnabled,false); events.append("restore"); return "ack"
   },persist:{ stored=$0; events.append("clear") })
   XCTAssertEqual(reply,Optional("ack")); XCTAssertEqual(events,["intent","restore","clear"])
   XCTAssertNil(config.pendingOrdinaryQuitRecovery); XCTAssertFalse(config.hardwareEnabled)
  } catch { XCTFail("\(error)") }
 }
 func testServiceAndClearStorageFailuresKeepRecoveryAndBlockNewDirectMutation() {
  for serviceFails in [true,false] {
   var config = Configuration(); var calls: [String] = []
   do { try OrdinaryQuitRecovery.begin(configuration:&config,persist:{ _ in }) } catch { XCTFail("\(error)") }
   do {
    _ = try DirectChargeCommand.run(arguments:["allowCharge","--confirm"],numericRequired:{false},request:{ command in
     _ = try OrdinaryQuitRecovery.restoreIfNeeded(configuration:&config,request:{ value in
      calls.append(value); if serviceFails { throw Failure.service }; return "ack"
     },persist:{ _ in throw Failure.storage })
     calls.append(command); return "new mutation"
    }); XCTFail("recovery failure admitted a new mutation")
   } catch {}
   XCTAssertEqual(calls,["restore"]); XCTAssertEqual(config.pendingOrdinaryQuitRecovery,true); XCTAssertFalse(config.hardwareEnabled)
   do { _ = try OrdinaryQuitRecovery.restoreIfNeeded(configuration:&config,request:{ _ in "ack" },persist:{ _ in }) }
   catch { XCTFail("\(error)") }
   XCTAssertNil(config.pendingOrdinaryQuitRecovery)
  }
 }
 func testFailedIntentSaveStillDisablesTheLiveConfiguration() {
  var config = Configuration(); config.hardwareEnabled = true
  do { try OrdinaryQuitRecovery.begin(configuration:&config,persist:{ _ in throw Failure.storage }); XCTFail("storage failure") } catch {}
  XCTAssertFalse(config.hardwareEnabled); XCTAssertEqual(config.pendingOrdinaryQuitRecovery,true)
  var fresh = Configuration()
  do {
   let reply = try OrdinaryQuitRecovery.restoreIfNeeded(configuration:&fresh,request:{ _ in XCTFail("no intent must not send IPC"); return "unexpected" },persist:{ _ in XCTFail("no intent must not write") })
   XCTAssertNil(reply)
  } catch { XCTFail("\(error)") }
 }
 func testPortableBackupCannotCarryOrImportARecoveryObligation() {
  var config = Configuration(); config.pendingOrdinaryQuitRecovery = true; config.hardwareEnabled = true
  do {
   var backup = ConfigurationBackup(configuration:config)
   backup.configuration.pendingOrdinaryQuitRecovery = true
   let portable = try JSONDecoder().decode(ConfigurationBackup.self,from:backup.encoded())
   XCTAssertNil(portable.configuration.pendingOrdinaryQuitRecovery)
   let crafted = try JSONEncoder().encode(backup)
   let imported = try ConfigurationBackup.restored(from:crafted)
   XCTAssertNil(imported.pendingOrdinaryQuitRecovery); XCTAssertFalse(imported.hardwareEnabled)
  } catch { XCTFail("\(error)") }
 }
}
