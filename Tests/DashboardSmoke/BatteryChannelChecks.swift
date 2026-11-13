import Foundation
import SQLite3
import ChargeHardware
import ChargeCore

@MainActor func batteryChannelChecks() async throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let root = Configuration.directory.appendingPathComponent("channel-"+UUID().uuidString)
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:root) }
 let archive = BatteryStatisticArchive(url:root.appendingPathComponent("statistics.sqlite3"))
 let start = Date(timeIntervalSince1970:1_800_000_000), day: TimeInterval = 86400
 func edit(_ archive: BatteryStatisticArchive, _ sql: String) throws {
  var db: OpaquePointer?; precondition(sqlite3_open(archive.url.path,&db) == SQLITE_OK)
  defer { sqlite3_close(db) }
  precondition(sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK)
 }
 func scalar(_ archive: BatteryStatisticArchive, _ sql: String) -> Int64 {
  var db: OpaquePointer?; precondition(sqlite3_open_v2(archive.url.path,&db,SQLITE_OPEN_READONLY,nil) == SQLITE_OK)
  defer { sqlite3_close(db) }; var s: OpaquePointer?
  precondition(sqlite3_prepare_v2(db,sql,-1,&s,nil) == SQLITE_OK); defer { sqlite3_finalize(s) }
  precondition(sqlite3_step(s) == SQLITE_ROW); return sqlite3_column_int64(s,0)
 }
 func sample(raw: Double? = 4500, cycles: Int? = 100) -> BatteryReading {
  BatteryReading(percent:70,cycleCount:cycles,healthPercent:88.5,connected:false,charging:false,
   designCapacityMAH:5000,fullCapacityMAH:4800,nominalCapacityMAH:4700,rawFullCapacityMAH:raw)
 }
 var cache = BatteryStatisticArchive.ChannelCache()
 let missing = sample(raw:nil,cycles:nil)
 precondition(try! !archive.appendChannels(missing,at:start,cache:&cache))
 precondition(!FileManager.default.fileExists(atPath:archive.url.path),"fallback capacity must not manufacture a native raw channel")
 let encoded = try JSONEncoder().encode(sample()); let decoded = try JSONDecoder().decode(BatteryReading.self,from:encoded)
 precondition(decoded.rawFullCapacityMAH == 4500 && decoded.fullCapacityMAH == 4800)
 var object = try JSONSerialization.jsonObject(with:encoded) as! [String:Any]; object.removeValue(forKey:"rawFullCapacityMAH")
 precondition(try! JSONDecoder().decode(BatteryReading.self,from:JSONSerialization.data(withJSONObject:object)).rawFullCapacityMAH == nil)
 // A version-one archive is read without mutation. Migration never imports
 // fallback legacy capacity/health as a proven live raw-channel observation.
 try edit(archive,"CREATE TABLE observations(date REAL PRIMARY KEY,health REAL,capacity REAL,cycles INTEGER); CREATE TABLE metadata(key TEXT PRIMARY KEY,value INTEGER NOT NULL); INSERT INTO metadata VALUES('legacy_imported',1); INSERT INTO observations VALUES(1800000000,88.5,4800,100); PRAGMA application_id=0x4f434853; PRAGMA user_version=1;")
 let before = try Data(contentsOf:archive.url)
 precondition(try! archive.loadChannels(hours:24,endingAt:start,metric:.health,designCapacity:5000).isEmpty)
 precondition(try! Data(contentsOf:archive.url) == before)
 precondition(try! archive.appendChannels(sample(),at:start,cache:&cache))
 precondition(scalar(archive,"PRAGMA user_version") == 2 && scalar(archive,"SELECT COUNT(*) FROM observations") == 1)
 precondition(try! archive.load(hours:24,endingAt:start).first?.health == 88.5)
 precondition(try! archive.appendChannels(sample(),at:start.addingTimeInterval(2),cache:&cache),"inclusive first-anchor equality must admit the next unchanged value")
 precondition(try! !archive.appendChannels(sample(),at:start.addingTimeInterval(4),cache:&cache))
 let first = try archive.loadChannels(hours:24,endingAt:start.addingTimeInterval(4),metric:.health,designCapacity:5000)
 precondition(first.count == 2 && first.allSatisfy { $0.health == 90 && $0.fullCapacityMAH == 4500 })
 let renormalized = try archive.loadChannels(hours:24,endingAt:start.addingTimeInterval(4),metric:.health,designCapacity:6000)
 precondition(renormalized.allSatisfy { $0.health == 75 },"query must use current design capacity, not saved old health")
 precondition(try! archive.loadChannels(hours:24,endingAt:start.addingTimeInterval(4),metric:.health,designCapacity:nil).allSatisfy { $0.health == nil })
 precondition(try! archive.appendChannels(sample(),at:start.addingTimeInterval(day+1),cache:&cache))
 precondition(try! !archive.appendChannels(sample(),at:start.addingTimeInterval(day+2),cache:&cache))
 precondition(try! !archive.appendChannels(sample(),at:start.addingTimeInterval(-1),cache:&cache),"clock rollback must not write a future grid boundary")
 let cyclesOnly = sample(raw:nil,cycles:101)
 precondition(try! archive.appendChannels(cyclesOnly,at:start.addingTimeInterval(2*day+1),cache:&cache))
 precondition(try! archive.appendChannels(sample(),at:start.addingTimeInterval(2*day+2),cache:&cache),"a missing raw channel must not share the cycles admission clock")
 precondition(scalar(archive,"SELECT COUNT(*) FROM channel_observations WHERE channel='rawCapacity'") == 4)
 precondition(scalar(archive,"SELECT COUNT(*) FROM channel_observations WHERE channel='cycles'") == 4)
 // Entire batch and cache roll back when the second channel fails.
 let failing = BatteryStatisticArchive(url:root.appendingPathComponent("failure.sqlite3"))
 let old = HistoryPoint(date:start,percent:70,temperature:nil,watts:nil,reason:"fixture",health:88.5)
 try failing.append(old,migrating:[])
 try edit(failing,"CREATE TRIGGER reject_cycles BEFORE INSERT ON channel_observations WHEN new.channel='cycles' BEGIN SELECT RAISE(FAIL,'fixture'); END;")
 var retryCache = BatteryStatisticArchive.ChannelCache()
 do { try failing.appendChannels(sample(),at:start,cache:&retryCache); preconditionFailure("failed batch accepted") } catch {}
 precondition(retryCache.entries.isEmpty && scalar(failing,"SELECT COUNT(*) FROM channel_observations") == 0)
 try edit(failing,"DROP TRIGGER reject_cycles")
 precondition(try! failing.appendChannels(sample(),at:start,cache:&retryCache))
 try edit(failing,"CREATE TRIGGER reject_clear BEFORE DELETE ON channel_observations BEGIN SELECT RAISE(FAIL,'fixture'); END;")
 do { try failing.clear(); preconditionFailure("failed paired clear accepted") } catch {}
 precondition(scalar(failing,"SELECT COUNT(*) FROM observations") == 1 && scalar(failing,"SELECT COUNT(*) FROM channel_observations") == 2)
 try edit(failing,"DROP TRIGGER reject_clear"); try failing.clear()
 precondition(scalar(failing,"SELECT COUNT(*) FROM channel_observations") == 0 && scalar(failing,"SELECT COUNT(*) FROM observations") == 0)
 // Exercise the real 3650-row cap and oldest-row UPDATE, including retained IDs.
 let ring = BatteryStatisticArchive(url:root.appendingPathComponent("ring.sqlite3")); try ring.append(old,migrating:[])
 let rows = (0..<3650).map { "INSERT INTO channel_observations(channel,date,value) VALUES('cycles',\(start.addingTimeInterval(Double($0)*day+($0 == 1 ? 19 : 1)).timeIntervalSince1970),100);" }.joined()
 try edit(ring,"BEGIN;"+rows+"COMMIT;")
 var ringCache = BatteryStatisticArchive.ChannelCache()
 precondition(try! ring.appendChannels(cyclesOnly,at:start.addingTimeInterval(3650*day+2),cache:&ringCache))
 precondition(scalar(ring,"SELECT COUNT(*) FROM channel_observations") == 3650 && scalar(ring,"SELECT MAX(id) FROM channel_observations") == 3650)
 precondition(scalar(ring,"SELECT value FROM channel_observations WHERE id=1") == 101)
 precondition(ringCache.entries[.cycles]?.anchor == start.addingTimeInterval(1))
 var restarted = BatteryStatisticArchive.ChannelCache()
 _ = try ring.appendChannels(cyclesOnly,at:start.addingTimeInterval(3650*day+3),cache:&restarted)
 precondition(restarted.entries[.cycles]?.anchor == start.addingTimeInterval(day+19),"restart reanchors from oldest currently retained row")
 // The actual asynchronous UI loader keeps channel and observation semantics separate.
 let loader = BatteryStatisticArchiveLoader()
 loader.load(archive:archive,hours:24,endingAt:start.addingTimeInterval(4),active:true,metric:.health,series:.channels,designCapacity:5000)
 for _ in 0..<600 where loader.loading { try await Task.sleep(nanoseconds:5_000_000) }
 precondition(!loader.loading && loader.error == nil && loader.records.count == 2 && loader.records.first?.health == 90)
 loader.load(archive:archive,hours:24,endingAt:start.addingTimeInterval(4),active:false,metric:.health,series:.observations)
 precondition(loader.records.isEmpty,"source changes cannot display stale records under the new label")
 loader.load(archive:archive,hours:24,endingAt:start.addingTimeInterval(4),active:true,metric:.health,series:.observations)
 for _ in 0..<600 where loader.loading { try await Task.sleep(nanoseconds:5_000_000) }
 precondition(loader.records.count == 1 && loader.records.first?.health == 88.5)
 // Production model records each accepted read independently of minute history.
 let savedConfig = try? Data(contentsOf:Configuration.url)
 let historyURL = Configuration.directory.appendingPathComponent("history.json")
 let savedHistory = try? Data(contentsOf:historyURL)
 defer {
  if let savedConfig { try? savedConfig.write(to:Configuration.url,options:.atomic) }
  else { try? FileManager.default.removeItem(at:Configuration.url) }
  if let savedHistory { try? savedHistory.write(to:historyURL,options:.atomic) }
  else { try? FileManager.default.removeItem(at:historyURL) }
 }
 var config = Configuration(); config.hardwareEnabled = false; config.historyEnabled = true
 config.notifications = false; config.systemActionsEnabled = false; try config.save()
 try Data("[]".utf8).write(to:historyURL,options:.atomic)
 let suite = "org.opencharge.channel-model."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 let modelArchive = BatteryStatisticArchive(url:root.appendingPathComponent("model.sqlite3"))
 var supplied = sample()
 let model = ChargeModel(automaticRead:nil,dashboardDefaults:defaults,observeLid:false,readBattery:{ supplied },statisticArchive:modelArchive)
 precondition(model.history.count == 1 && scalar(modelArchive,"SELECT COUNT(*) FROM channel_observations") == 2)
 let modelError = model.error, revision = model.statisticRevision
 model.config.historyEnabled = false; supplied = sample(raw:4600,cycles:101); model.refresh()
 precondition(scalar(modelArchive,"SELECT COUNT(*) FROM channel_observations") == 2 && model.statisticRevision == revision)
 try edit(modelArchive,"CREATE TRIGGER deny_channel BEFORE INSERT ON channel_observations BEGIN SELECT RAISE(FAIL,'fixture'); END;")
 model.config.historyEnabled = true; model.refresh()
 precondition(model.statisticArchiveError != nil && model.error == modelError && !model.config.hardwareEnabled && model.history.count == 1)
 try edit(modelArchive,"DROP TRIGGER deny_channel"); model.refresh()
 precondition(model.statisticArchiveError == nil && model.error == modelError && model.history.count == 1)
 precondition(scalar(modelArchive,"SELECT COUNT(*) FROM channel_observations") == 4)
 let recent = try modelArchive.loadChannels(hours:24,endingAt:Date(),metric:.health,designCapacity:5000)
 precondition(recent.map(\.health) == [90,92])
 model.clearHistory(); precondition(model.history.isEmpty && scalar(modelArchive,"SELECT COUNT(*) FROM channel_observations") == 0)
 model.refresh(); precondition(scalar(modelArchive,"SELECT COUNT(*) FROM channel_observations") == 2,"clear must also reset process-lifetime admission anchors")
 print("PASS daily independent channel admission, inclusive grid edges, unchanged values, rollback, real3650 ring, restart, provenance-preserving schema migration, current-design normalization, atomic clear and actual loader source separation; isolated fixtures only")
}
