import XCTest
@testable import ChargeCore

final class ConfigurationBackupTests: XCTestCase {
 func testRestoreCannotResumeHardwareOrOverdueActions() {
  var original = Configuration(); original.hardwareEnabled = true; original.systemActionsEnabled = true
  original.magSafeMode = .orange; original.magSafeOffDuringSleep = true
  original.policy.mode = .discharge; original.policy.departure = Date()
  var task = ChargeSchedule(); task.action = .lowPowerOn; task.date = Date(timeIntervalSince1970: 1)
  original.schedules = [task]
  do {
   let restored = try ConfigurationBackup.restored(from: ConfigurationBackup(configuration: original).encoded())
   XCTAssertEqual(restored.magSafeMode, .system); XCTAssertEqual(restored.magSafeOffDuringSleep, false)
   XCTAssertFalse(restored.hardwareEnabled); XCTAssertEqual(restored.systemActionsEnabled, false)
   XCTAssertEqual(restored.policy.mode, .automatic); XCTAssertNil(restored.policy.departure)
   XCTAssertEqual(restored.schedules.first?.id, task.id); XCTAssertEqual(restored.schedules.first?.enabled, false)
   var policy = restored.policy; var inactive = restored.schedules[0]
   XCTAssertFalse(inactive.consume(now: Date(), policy: &policy))
  } catch { XCTFail(error.localizedDescription) }
 }
 func testRejectUnknownVersionDuplicateTasksAndOversizedFiles() {
  var backup = ConfigurationBackup(configuration: Configuration()); backup.schemaVersion = 2
  do { _ = try ConfigurationBackup.restored(from: backup.encoded()); XCTFail("accepted future schema") } catch {}
  backup.schemaVersion = 1; let task = ChargeSchedule(); backup.configuration.schedules = [task, task]
  do { _ = try ConfigurationBackup.restored(from: backup.encoded()); XCTFail("accepted duplicate task IDs") } catch {}
  do { _ = try ConfigurationBackup.restored(from: Data(repeating: 32, count: 1_048_577)); XCTFail("accepted oversized input") } catch {}
 }
 func testEditingKeepsIdentityAndResetsOldCalendarAnchor() {
  var config = Configuration(); var task = ChargeSchedule(); task.anchorDay = 31; task.anchorMonth = 1
  config.schedules = [task]
  task.value = 200; task.date = Date(timeIntervalSince1970: 1_700_000_000); task.repeatRule = .monthly
  config.saveSchedule(task)
  XCTAssertEqual(config.schedules.count, 1); XCTAssertEqual(config.schedules[0].id, task.id)
  XCTAssertEqual(config.schedules[0].value, 100); XCTAssertNil(config.schedules[0].anchorDay); XCTAssertNil(config.schedules[0].anchorMonth)
 }
}
