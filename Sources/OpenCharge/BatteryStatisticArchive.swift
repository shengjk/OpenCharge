import Foundation
import SQLite3
import Darwin

struct BatteryStatisticRecord: Equatable, Sendable {
 let date: Date
 let health: Double?
 let fullCapacityMAH: Double?
 let cycles: Int?

 init(point: HistoryPoint) {
  date = point.date
  health = BatteryStatistic.health.value(point)
  fullCapacityMAH = BatteryStatistic.fullCapacity.value(point)
  cycles = BatteryStatistic.cycles.value(point).map(Int.init)
 }
 init(date: Date, health: Double?, fullCapacityMAH: Double?, cycles: Int?) {
  self.date = date; self.health = health; self.fullCapacityMAH = fullCapacityMAH; self.cycles = cycles
 }
 func value(for metric: BatteryStatistic) -> Double? {
  let value: Double?
  let range: ClosedRange<Double>
  switch metric {
  case .temperature: return nil
  case .health: value = health; range = 0...200
  case .fullCapacity: value = fullCapacityMAH; range = 1...100_000
  case .cycles: value = cycles.map(Double.init); range = 0...1_000_000
  }
  return value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
 }
}

struct BatteryStatisticArchive: Equatable, Sendable {
 let url: URL
 static let maximumQueryHours = 360 * 24

 /// Recording is explicitly invoked by the existing history opt-in.
 /// Old observations are retained until Clear History; wall-clock changes cannot age them out.
 func append(_ point: HistoryPoint, migrating legacy: [HistoryPoint]) throws {
  guard point.date.timeIntervalSince1970.isFinite else { throw Failure(detail: "Invalid observation date") }
  let db = try Database(url: url, writable: true)
  try db.transaction {
   let statement = try db.prepare("INSERT OR REPLACE INTO observations(date,health,capacity,cycles) VALUES(?,?,?,?)")
   defer { sqlite3_finalize(statement) }
   func insert(_ record: BatteryStatisticRecord) throws {
    guard record.date.timeIntervalSince1970.isFinite else { return }
    try db.check(sqlite3_reset(statement), expected: SQLITE_OK); try db.check(sqlite3_clear_bindings(statement), expected: SQLITE_OK)
    try db.check(sqlite3_bind_double(statement, 1, record.date.timeIntervalSince1970), expected: SQLITE_OK)
    if let value = record.health { try db.check(sqlite3_bind_double(statement, 2, value), expected: SQLITE_OK) }
    else { try db.check(sqlite3_bind_null(statement, 2), expected: SQLITE_OK) }
    if let value = record.fullCapacityMAH { try db.check(sqlite3_bind_double(statement, 3, value), expected: SQLITE_OK) }
    else { try db.check(sqlite3_bind_null(statement, 3), expected: SQLITE_OK) }
    if let value = record.cycles { try db.check(sqlite3_bind_int64(statement, 4, Int64(value)), expected: SQLITE_OK) }
    else { try db.check(sqlite3_bind_null(statement, 4), expected: SQLITE_OK) }
    try db.check(sqlite3_step(statement), expected: SQLITE_DONE)
   }
   if try db.scalar("SELECT value FROM metadata WHERE key='legacy_imported'") == 0 {
    for old in legacy { try insert(BatteryStatisticRecord(point: old)) }
    try db.execute("UPDATE metadata SET value=1 WHERE key='legacy_imported'")
   }
   // A later missing observation replaces an earlier value at an identical date.
   try insert(BatteryStatisticRecord(point: point))
  }
 }

 /// A missing archive is empty, and a read never creates a file or initializes a schema.
 func load(hours: Int, endingAt end: Date, compactFor metric: BatteryStatistic? = nil) throws -> [BatteryStatisticRecord] {
  guard (1...Self.maximumQueryHours).contains(hours), end.timeIntervalSince1970.isFinite else {
   throw Failure(detail: "Invalid statistics window")
  }
  guard FileManager.default.fileExists(atPath: url.path) else { return [] }
  let db = try Database(url: url, writable: false)
  let statement = try db.prepare("SELECT date,health,capacity,cycles FROM observations WHERE date>=? AND date<=? ORDER BY date")
  defer { sqlite3_finalize(statement) }
  try db.check(sqlite3_bind_double(statement, 1, end.addingTimeInterval(-Double(hours) * 3600).timeIntervalSince1970), expected: SQLITE_OK)
  try db.check(sqlite3_bind_double(statement, 2, end.timeIntervalSince1970), expected: SQLITE_OK)
  var records: [BatteryStatisticRecord] = []
  var pending: BatteryStatisticRecord?
  while true {
   let status = sqlite3_step(statement)
   if status == SQLITE_DONE { break }
   try db.check(status, expected: SQLITE_ROW)
   func numeric(_ column: Int32, range: ClosedRange<Double>) throws -> Double? {
    let kind = sqlite3_column_type(statement, column)
    if kind == SQLITE_NULL { return nil }
    let value = sqlite3_column_double(statement, column)
    guard (kind == SQLITE_FLOAT || kind == SQLITE_INTEGER), value.isFinite, range.contains(value) else {
     throw Failure(detail: "Invalid statistics value")
    }
    return value
   }
   let seconds = sqlite3_column_double(statement, 0)
   guard seconds.isFinite, [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 0)) else {
    throw Failure(detail: "Invalid stored date")
   }
   let health = try numeric(1, range: 0...200)
   let capacity = try numeric(2, range: 1...100_000)
   let cycleValue = try numeric(3, range: 0...1_000_000)
   guard cycleValue == nil || cycleValue!.rounded(.towardZero) == cycleValue! else {
    throw Failure(detail: "Invalid cycle count")
   }
   let record = BatteryStatisticRecord(date: Date(timeIntervalSince1970: seconds),
    health: health, fullCapacityMAH: capacity, cycles: cycleValue.map(Int.init))
   if let metric {
    // Keep both endpoints of each constant run. The database retains every row.
    if let previous = pending, record.value(for: metric) == previous.value(for: metric) {
     pending = record; continue
    }
    if let previous = pending, records.last?.date != previous.date { records.append(previous) }
    pending = record
   }
   records.append(record)
  }
  if metric != nil, let pending, records.last?.date != pending.date { records.append(pending) }
  return records
 }

 func clear() throws {
  guard FileManager.default.fileExists(atPath: url.path) else { return }
  let db = try Database(url: url, writable: true)
  try db.transaction {
   try db.execute("DELETE FROM observations")
   // A partially failed legacy-file clear must not import old records again.
   try db.execute("INSERT OR REPLACE INTO metadata(key,value) VALUES('legacy_imported',1)")
  }
 }

 struct Failure: LocalizedError {
  let detail: String
  var errorDescription: String? {
   String.localizedStringWithFormat(NSLocalizedString("长期统计记录不可用：%@", comment: ""), detail)
  }
 }

 private final class Database {
  static let applicationID: Int64 = 0x4f434853
  private var connection: OpaquePointer?
  var handle: OpaquePointer { connection! }

  init(url: URL, writable: Bool) throws {
   if writable {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    if descriptor >= 0 { Darwin.close(descriptor) }
    else if errno != EEXIST { throw Failure(detail: String(cString: strerror(errno))) }
   }
   var opened: OpaquePointer?
   let flags = (writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX
   let status = sqlite3_open_v2(url.path, &opened, flags, nil)
   guard status == SQLITE_OK, let opened else {
    let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open statistics"
    if let opened { sqlite3_close(opened) }
    throw Failure(detail: message)
   }
   connection = opened
   do {
    try check(sqlite3_busy_timeout(opened, 2000), expected: SQLITE_OK)
    let version = try scalar("PRAGMA user_version")
    let identity = try scalar("PRAGMA application_id")
    let tables = try scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
    if writable && version == 0 && identity == 0 && tables == 0 {
     try transaction {
      try execute("CREATE TABLE IF NOT EXISTS observations(date REAL PRIMARY KEY NOT NULL,health REAL,capacity REAL,cycles INTEGER,CHECK(typeof(date) IN ('real','integer')),CHECK(health IS NULL OR health BETWEEN 0 AND 200),CHECK(capacity IS NULL OR capacity BETWEEN 1 AND 100000),CHECK(cycles IS NULL OR (typeof(cycles)='integer' AND cycles BETWEEN 0 AND 1000000))) WITHOUT ROWID")
      try execute("CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value INTEGER NOT NULL) WITHOUT ROWID")
      try execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('legacy_imported',0)")
      try execute("PRAGMA application_id=\(Self.applicationID)")
      try execute("PRAGMA user_version=1")
     }
    }
    guard try scalar("PRAGMA user_version") == 1, try scalar("PRAGMA application_id") == Self.applicationID else {
     throw Failure(detail: NSLocalizedString("记录格式不受支持，请使用更新版本", comment: ""))
    }
   } catch {
    sqlite3_close(opened); connection = nil; throw error
   }
  }
  deinit { if let connection { sqlite3_close(connection) } }
  func check(_ status: Int32, expected: Int32) throws {
   guard status == expected else { throw Failure(detail: String(cString: sqlite3_errmsg(handle))) }
  }
  func execute(_ sql: String) throws { try check(sqlite3_exec(handle, sql, nil, nil, nil), expected: SQLITE_OK) }
  func prepare(_ sql: String) throws -> OpaquePointer {
   var statement: OpaquePointer?
   try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil), expected: SQLITE_OK)
   guard let statement else { throw Failure(detail: "Empty statistics statement") }
   return statement
  }
  func scalar(_ sql: String) throws -> Int64 {
   let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
   let result = sqlite3_step(statement)
   if result == SQLITE_DONE { throw Failure(detail: "Statistics metadata is missing") }
   try check(result, expected: SQLITE_ROW)
   return sqlite3_column_int64(statement, 0)
  }
  func transaction(_ body: () throws -> Void) throws {
   try execute("BEGIN IMMEDIATE")
   do { try body(); try execute("COMMIT") }
   catch { try? execute("ROLLBACK"); throw error }
  }
 }
}
