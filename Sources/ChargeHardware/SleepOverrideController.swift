import Foundation

/// Fixed operations only. Production transport uses SPI; fixtures inject all operations.
public struct SleepOverrideTransport {
 public let captureGlobal: () throws -> Bool
 public let readGlobal: () throws -> Bool
 public let setGlobal: (Bool) throws -> Void
 public let setLid: (Bool) throws -> Void
 public let setDisplay: (Bool) throws -> Void
 public init(captureGlobal: @escaping () throws -> Bool, readGlobal: @escaping () throws -> Bool, setGlobal: @escaping (Bool) throws -> Void, setLid: @escaping (Bool) throws -> Void, setDisplay: @escaping (Bool) throws -> Void) {
  self.captureGlobal = captureGlobal; self.readGlobal = readGlobal; self.setGlobal = setGlobal; self.setLid = setLid; self.setDisplay = setDisplay
 }
}
public enum SleepOverrideError: Error, LocalizedError {
 case unavailable(String), invalidRecord, cleanup(String)
 public var errorDescription: String? {
  switch self {
  case .unavailable(let text): return "Sleep control unavailable: " + text
  case .invalidRecord: return "Invalid sleep recovery record"
  case .cleanup(let text): return "Sleep restoration incomplete: " + text
  }
 }
}
/// Serialized by the helper's main queue. SleepDisabled persists across boot; lid state does not.
public final class SleepOverrideController {
 private struct Record: Codable {
  var version: Int = 1
  var boot: String
  var originalGlobal: Bool
  var globalPending: Bool
  var lidPending: Bool
 }
 private let transport: SleepOverrideTransport
 private let store: ChargeRecoveryStore
 private let boot: String
 private var loaded = false
 private var record: Record?
 private var displayMayBeActive = false
 public private(set) var active = false
 public init(transport: SleepOverrideTransport, store: ChargeRecoveryStore, bootSession: String) {
  self.transport = transport; self.store = store; boot = bootSession
 }
 private func load() throws {
  guard !loaded else { return }
  guard UUID(uuidString: boot) != nil else { throw SleepOverrideError.invalidRecord }
  if let data = try store.load() {
   guard data.count <= 2048 else { throw SleepOverrideError.invalidRecord }
   let value = try JSONDecoder().decode(Record.self, from: data)
   guard value.version == 1, UUID(uuidString: value.boot) != nil, !value.globalPending || !value.originalGlobal else { throw SleepOverrideError.invalidRecord }
   record = value
  }
  loaded = true
 }
 private func persist() throws {
  if let record, record.globalPending || record.lidPending { try store.save(JSONEncoder().encode(record)) }
  else { try store.save(nil); record = nil }
 }
 public func recover() throws { try load(); try restore() }
 public func apply(preventDisplaySleep: Bool) throws {
  try load()
  if !active && (record != nil || displayMayBeActive) { try restore() }
  if !active {
   let previous = try transport.captureGlobal()
   var intent = Record(boot: boot, originalGlobal: previous, globalPending: !previous, lidPending: false)
   do {
    if !previous {
     try store.save(JSONEncoder().encode(intent)); record = intent
     try transport.setGlobal(true)
     guard try transport.readGlobal() else { throw SleepOverrideError.unavailable("global setting readback") }
    }
    // Journal the lid intent only after the global step, before its own write.
    intent.lidPending = true
    try store.save(JSONEncoder().encode(intent)); record = intent
    try transport.setLid(true)
    active = true
   } catch {
    let original = error
    if record != nil { do { try restore() } catch { throw SleepOverrideError.cleanup(original.localizedDescription + "; " + error.localizedDescription) } }
    throw original
   }
  }
  do {
   guard try transport.readGlobal() else { throw SleepOverrideError.unavailable("global setting changed externally") }
   if preventDisplaySleep { displayMayBeActive = true }
   try transport.setDisplay(preventDisplaySleep)
   displayMayBeActive = preventDisplaySleep
  } catch {
   let original = error
   do { try restore() } catch { throw SleepOverrideError.cleanup(original.localizedDescription + "; " + error.localizedDescription) }
   throw original
  }
 }
 public func restore() throws {
  try load(); active = false
  var failures: [String] = []
  if displayMayBeActive {
   do { try transport.setDisplay(false); displayMayBeActive = false }
   catch { failures.append(error.localizedDescription) }
  }
  if let value = record, value.lidPending {
   do {
    // The kernel's shared lid flag is not persistent. Never replay it into a later boot.
    if UUID(uuidString: value.boot) == UUID(uuidString: boot) { try transport.setLid(false) }
    record?.lidPending = false; try persist()
   } catch { failures.append(error.localizedDescription) }
  }
  if let value = record, value.globalPending {
   do {
    // An external false value is already released; never re-enable it during cleanup.
    if try transport.readGlobal() { try transport.setGlobal(value.originalGlobal); guard try transport.readGlobal() == value.originalGlobal else { throw SleepOverrideError.unavailable("global restore readback") } }
    record?.globalPending = false; try persist()
   } catch { failures.append(error.localizedDescription) }
  }
  if let record, !record.globalPending && !record.lidPending {
   do { try persist() } catch { failures.append(error.localizedDescription) }
  }
  if !failures.isEmpty { throw SleepOverrideError.cleanup(failures.joined(separator: "; ")) }
 }
}
