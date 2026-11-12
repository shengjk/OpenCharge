import Foundation
import SQLite3
import ChargeCore
import ChargeHardware

private final class ArchiveReadCounter: @unchecked Sendable {
 private let lock = NSLock()
 private var value = 0
 func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
 var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor func batteryStatisticArchiveChecks(defaults: UserDefaults) async throws {
 let root = Configuration.directory.appendingPathComponent("archive-fixture-" + UUID().uuidString)
 defer { try? FileManager.default.removeItem(at: root) }
 let end = Date(timeIntervalSince1970: 1_800_000_000)
 func point(_ seconds: Double, health: Double? = 98, cycles: Int? = 120, capacity: Double? = 4400) -> HistoryPoint {
  HistoryPoint(date: end.addingTimeInterval(seconds), percent: 70, temperature: 31, watts: nil,
   reason: "fixture", health: health, cycles: cycles, fullCapacityMAH: capacity)
 }
 func edit(_ url: URL, _ sql: String) throws {
  var db: OpaquePointer?
  guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw CocoaError(.fileWriteUnknown) }
  defer { sqlite3_close(db) }
  guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
 }
 func rejected(_ action: () throws -> Void) {
  do { try action(); preconditionFailure("invalid or foreign statistics storage was accepted") } catch {}
 }
 let archive = BatteryStatisticArchive(url: root.appendingPathComponent("year/statistics.sqlite3"))
 precondition(try! archive.load(hours: 8640, endingAt: end).isEmpty)
 try archive.clear()
 precondition(!FileManager.default.fileExists(atPath: root.path), "read and missing clear must not create a database or directory")
 rejected { try archive.append(point(.nan), migrating: []) }
 precondition(!FileManager.default.fileExists(atPath: root.path))
 let legacy = [point(-361 * 86400, health: 100, cycles: 1), point(-360 * 86400, health: 99, cycles: 10),
  point(-180 * 86400, health: 98, cycles: 50), point(-86400, health: 97, cycles: 119), point(86400, health: 95, cycles: 130)]
 try archive.append(point(0, health: 96), migrating: legacy)
 let rows = try archive.load(hours: 8640, endingAt: end)
 precondition(rows.map(\.date) == [legacy[1].date, legacy[2].date, legacy[3].date, end])
 precondition(rows.first?.cycles == 10 && rows.last?.health == 96)
 precondition(try! archive.load(hours: 24, endingAt: end).count == 2)
 let reopened = BatteryStatisticArchive(url: archive.url)
 precondition(try! reopened.load(hours: 8640, endingAt: end) == rows)
 let permissions = try FileManager.default.attributesOfItem(atPath: archive.url.path)[.posixPermissions] as! NSNumber
 precondition(permissions.intValue & 0o777 == 0o600)
 try archive.append(point(0, health: nil, cycles: nil, capacity: nil), migrating: [point(-180 * 86400, health: 1)])
 let replaced = try archive.load(hours: 8640, endingAt: end)
 precondition(replaced[1].health == 98, "legacy migration must be one-time")
 precondition(replaced.last?.health == nil && replaced.last?.cycles == nil && replaced.last?.fullCapacityMAH == nil)
 // Moving a query clock does not delete old or future observations.
 precondition(try! archive.load(hours: 8640, endingAt: end.addingTimeInterval(86400)).last?.cycles == 130)
 let earlierClock = try archive.load(hours: 8640, endingAt: end.addingTimeInterval(-86400))
 precondition(earlierClock.first?.cycles == 1 && earlierClock.last?.cycles == 119)
 rejected { _ = try archive.load(hours: 0, endingAt: end) }
 rejected { _ = try archive.load(hours: 8641, endingAt: end) }
 try archive.clear()
 precondition(try! archive.load(hours: 8640, endingAt: end).isEmpty)
 try archive.append(point(60), migrating: legacy)
 precondition(try! archive.load(hours: 8640, endingAt: end.addingTimeInterval(60)).count == 1,
  "cleared rows must not return through a second legacy import")
 // A failed migration is atomic, including its import-complete marker.
 try edit(archive.url, "UPDATE metadata SET value=0 WHERE key='legacy_imported'; CREATE TRIGGER deny_date BEFORE INSERT ON observations WHEN new.date=\(end.addingTimeInterval(-86400).timeIntervalSince1970) BEGIN SELECT RAISE(FAIL,'fixture'); END;")
 let beforeFailure = try archive.load(hours: 8640, endingAt: end.addingTimeInterval(60))
 rejected { try archive.append(point(120), migrating: [legacy[2], legacy[3]]) }
 precondition(try! archive.load(hours: 8640, endingAt: end.addingTimeInterval(60)) == beforeFailure)
 try edit(archive.url, "DROP TRIGGER deny_date")
 try archive.append(point(120), migrating: [legacy[2], legacy[3]])
 precondition(try! archive.load(hours: 8640, endingAt: end.addingTimeInterval(120)).count == 4)
 // Compaction affects only rendering. Every raw observation remains queryable.
 let dense = BatteryStatisticArchive(url: root.appendingPathComponent("dense.sqlite3"))
 let steady = (0..<10_080).map { point(Double($0 - 10_080) * 60, health: 98, cycles: 120, capacity: 4400) }
 try dense.append(point(0), migrating: steady)
 precondition(try! dense.load(hours: 8640, endingAt: end).count == 10_081)
 let compact = try dense.load(hours: 8640, endingAt: end, compactFor: .cycles)
 precondition(compact.count == 2 && compact.first?.date == steady.first?.date && compact.last?.date == end)
 precondition(try! dense.load(hours: 8640, endingAt: end).count == 10_081)
 for (name, sql) in [
  ("future", "PRAGMA user_version=999; PRAGMA application_id=1329817683;"),
  ("foreign", "CREATE TABLE other(value INTEGER); INSERT INTO other VALUES(42);")] {
  let url = root.appendingPathComponent(name + ".sqlite3")
  try edit(url, sql)
  let bytes = try Data(contentsOf: url)
  let foreign = BatteryStatisticArchive(url: url)
  rejected { _ = try foreign.load(hours: 24, endingAt: end) }
  rejected { try foreign.append(point(0), migrating: []) }
  rejected { try foreign.clear() }
  precondition(try! Data(contentsOf: url) == bytes, "unknown databases must be byte-preserved")
 }
 let brokenURL = root.appendingPathComponent("broken.sqlite3")
 let brokenBytes = Data("not a database".utf8); try brokenBytes.write(to: brokenURL)
 let broken = BatteryStatisticArchive(url: brokenURL)
 rejected { _ = try broken.load(hours: 24, endingAt: end) }
 rejected { try broken.append(point(0), migrating: []) }
 rejected { try broken.clear() }
 precondition(try! Data(contentsOf: brokenURL) == brokenBytes)

 // Validate model integration with an isolated archive and disabled live controls.
 let originalConfig = try? Data(contentsOf: Configuration.url)
 let historyURL = Configuration.directory.appendingPathComponent("history.json")
 let originalHistory = try? Data(contentsOf: historyURL)
 defer {
  if let originalConfig { try? originalConfig.write(to: Configuration.url, options: .atomic) }
  else { try? FileManager.default.removeItem(at: Configuration.url) }
  if let originalHistory { try? originalHistory.write(to: historyURL, options: .atomic) }
  else { try? FileManager.default.removeItem(at: historyURL) }
 }
 var config = Configuration(); config.historyEnabled = false; config.hardwareEnabled = false; config.systemActionsEnabled = false
 try config.save()
 let modelArchive = BatteryStatisticArchive(url: root.appendingPathComponent("model.sqlite3"))
 let reading = BatteryReading(date: end, percent: 70, connected: false, charging: false)
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("no screen lock") },
  readBattery: { reading }, statisticArchive: modelArchive, startupRecoveryRequest: { _ in preconditionFailure("no helper calls") })
 precondition(!FileManager.default.fileExists(atPath: modelArchive.url.path), "disabled recording must not create an archive")
 let errorBefore = model.error, actionBefore = model.decision.action
 model.config.hardwareEnabled = true
 model.recordStatistics(point(0), migrating: []) { _,_ in throw CocoaError(.fileWriteUnknown) }
 precondition(model.config.hardwareEnabled && model.error == errorBefore && model.decision.action == actionBefore && model.statisticArchiveError != nil)
 model.config.hardwareEnabled = false // No await or run-loop pump while the fixture opt-in is true.
 model.recordStatistics(point(0), migrating: [legacy[2]])
 precondition(model.statisticRevision == 1 && model.statisticArchiveError == nil)
 model.dashboard.capture(model)
 precondition(model.dashboard.statisticArchive == modelArchive && model.dashboard.statisticRevision == 1)
 model.history = [point(0)]; try JSONEncoder().encode(model.history).write(to: historyURL, options: .atomic)
 model.clearHistory()
 precondition(model.history.isEmpty && (try! modelArchive.load(hours: 8640, endingAt: end)).isEmpty)
 precondition(try! JSONDecoder().decode([HistoryPoint].self, from: Data(contentsOf: historyURL)).isEmpty)
 model.recordStatistics(point(0), migrating: [])
 model.history = [point(0)]; let recentBytes = try JSONEncoder().encode(model.history)
 try recentBytes.write(to: historyURL, options: .atomic)
 try edit(modelArchive.url, "CREATE TRIGGER deny_clear BEFORE DELETE ON observations BEGIN SELECT RAISE(FAIL,'fixture'); END;")
 model.clearHistory()
 precondition(model.history.count == 1 && model.error != nil && (try! Data(contentsOf: historyURL)) == recentBytes)
 try edit(modelArchive.url, "DROP TRIGGER deny_clear")

 // Out-of-order asynchronous readers cannot overwrite a newer selection.
 let oldStarted = DispatchSemaphore(value: 0), oldRelease = DispatchSemaphore(value: 0), oldReturned = DispatchSemaphore(value: 0)
 let old = BatteryStatisticRecord(point: point(-60)), new = BatteryStatisticRecord(point: point(0))
 let loader = BatteryStatisticArchiveLoader { _,hours,_,_ in
  if hours == 1 { oldStarted.signal(); oldRelease.wait(); oldReturned.signal(); return [old] }
  return [new]
 }
 loader.load(archive: archive, hours: 1, endingAt: end, active: true)
 precondition(oldStarted.wait(timeout: .now() + 2) == .success)
 loader.load(archive: archive, hours: 24, endingAt: end, active: true)
 for _ in 0..<200 where loader.loading { try await Task.sleep(nanoseconds: 5_000_000) }
 precondition(loader.records == [new])
 oldRelease.signal(); precondition(oldReturned.wait(timeout: .now() + 2) == .success)
 try await Task.sleep(nanoseconds: 30_000_000)
 precondition(loader.records == [new])
 loader.load(archive: archive, hours: 24, endingAt: end, active: false)
 precondition(!loader.loading && loader.records == [new])
 let reads = ArchiveReadCounter()
 let retry = BatteryStatisticArchiveLoader { _,_,_,_ in
  if reads.next() == 1 { throw CocoaError(.fileReadCorruptFile) }
  return [new]
 }
 retry.load(archive: archive, hours: 24, endingAt: end, active: false)
 precondition(reads.count == 0)
 retry.load(archive: archive, hours: 24, endingAt: end, active: true)
 for _ in 0..<200 where retry.loading { try await Task.sleep(nanoseconds: 5_000_000) }
 precondition(retry.error != nil && retry.records.isEmpty)
 retry.load(archive: archive, hours: 24, endingAt: end, active: true)
 for _ in 0..<200 where retry.loading { try await Task.sleep(nanoseconds: 5_000_000) }
 precondition(retry.error == nil && retry.records == [new])
 print("PASS annual statistics: private/read-only SQLite, 360-day/future boundaries, one-time legacy migration, NULL replacement, restart and clock-safe retained rows, atomic import rollback, raw retention/endpoint compaction, unknown/corrupt database preservation, paired clear/failure, disabled opt-in, isolated model archive failure without charging rollback, snapshot revision and stale-reader/retry/focus gates; no hardware or helper calls")
}
