import Foundation
import Darwin

public struct SMCByteReading: Sendable {
 public let dataType: String
 public let bytes: [UInt8]
 public init(dataType: String, bytes: [UInt8]) { self.dataType = dataType; self.bytes = bytes }
}

public struct FirmwareChargeStatus: Equatable, Sendable {
 public let limit: UInt8
 /// Firmware control state, distinct from OS charging or measured power flow.
 public let chargingAllowed: Bool?
}

/// Fixed CH0B/BCLM transactions for an explicitly selected numeric firmware profile.
/// The caller must establish host eligibility; readable bytes alone do not prove it.
/// Production helper access is serialized with ordinary charge sessions.
public final class SMCFirmwareChargeController {
 private enum Key: String, Codable, Hashable { case charge = "CH0B", limit = "BCLM" }
 private struct Entry: Codable {
  let key: Key
  let original: UInt8
  var expected: UInt8
  var previous: UInt8?
 }
 private struct Record: Codable {
  let kind: String
  let version: Int
  let bootSession: String
  let entries: [Entry]
 }
 private let lock = NSLock()
 private let eligibleHost: Bool
 private let batteryPresent: Bool
 private let read: (String) throws -> SMCByteReading?
 private let write: (String, UInt8) throws -> Void
 private let authorized: () -> Bool
 private let store: ChargeRecoveryStore?
 private let bootSession: String
 private var loaded: Bool
 private var interrupted = false
 private var entries: [Entry] = []

 public init(eligibleHost: Bool, batteryPresent: Bool,
             read: @escaping (String) throws -> SMCByteReading?,
             write: @escaping (String, UInt8) throws -> Void,
             authorized: @escaping () -> Bool = { geteuid() == 0 },
             recoveryStore: ChargeRecoveryStore? = nil, bootSession: String = "") {
  self.eligibleHost = eligibleHost; self.batteryPresent = batteryPresent
  self.read = read; self.write = write; self.authorized = authorized
  store = recoveryStore; self.bootSession = bootSession; loaded = recoveryStore == nil
 }

 /// Read-only: does not load, rewrite or clear a recovery journal.
 public func inspect() throws -> FirmwareChargeStatus {
  lock.lock(); defer { lock.unlock() }
  let values = try profile()
  if values.charge != 0 { return FirmwareChargeStatus(limit: values.limit, chargingAllowed: false) }
  if values.limit > 15 { return FirmwareChargeStatus(limit: values.limit, chargingAllowed: true) }
  let input = try optionalByte("BSIn")
  return FirmwareChargeStatus(limit: values.limit, chargingAllowed: input.map { $0 & 1 != 0 })
 }

 public func setLimit(_ percent: Int) throws {
  guard (20...100).contains(percent) else { throw HardwareError.invalidData("Firmware limit must be 20...100") }
  lock.lock(); defer { lock.unlock() }
  try beginMutation(); try transact(UInt8(percent))
 }
 public func allowCharging() throws { try setLimit(100) }
 public func inhibitCharging() throws {
  lock.lock(); defer { lock.unlock() }
  try beginMutation(); try transact(15)
 }

 /// Applies an explicit orderly-exit target and relinquishes this session only
 /// after readback and journal removal succeed. Crash cleanup uses restore instead.
 public func finishExit(limit percent: Int) throws {
  guard (20...100).contains(percent) else { throw HardwareError.invalidData("Firmware exit limit must be 20...100") }
  lock.lock(); defer { lock.unlock() }
  try beginMutation(); try transact(UInt8(percent))
  do { try store?.save(nil) }
  catch { interrupted = true; throw error }
  entries.removeAll()
 }

 public func restore() throws {
  lock.lock(); defer { lock.unlock() }
  guard authorized() else { throw HardwareError.permissionRequired }
  try loadRecovery()
  do { try restoreOwned() }
  catch { interrupted = true; throw error }
  interrupted = false
 }

 private func beginMutation() throws {
  guard authorized() else { throw HardwareError.permissionRequired }
  guard eligibleHost, batteryPresent else { throw HardwareError.unsupported("Numeric firmware profile requires eligible hardware") }
  try loadRecovery()
  guard !interrupted else { throw HardwareError.unavailable("Interrupted firmware recovery pending") }
 }
 private static func valid(_ value: UInt8, for key: Key) -> Bool {
  switch key { case .charge: return value == 0 || value == 2
  case .limit: return value == 15 || (20...100).contains(value) }
 }
 private func optionalByte(_ key: String) throws -> UInt8? {
  guard let value = try read(key) else { return nil }
  guard value.dataType == "ui8 ", value.bytes.count == 1 else {
   throw HardwareError.invalidData("Unrecognized firmware key type or size: \(key)")
  }
  return value.bytes[0]
 }
 private func byte(_ key: Key) throws -> UInt8 {
  guard let value = try optionalByte(key.rawValue), Self.valid(value, for: key) else {
   throw HardwareError.invalidData("Missing or unrecognized firmware state: \(key.rawValue)")
  }
  return value
 }
 private func profile() throws -> (charge: UInt8, limit: UInt8) {
  guard eligibleHost, batteryPresent else { throw HardwareError.unsupported("Numeric firmware profile requires an eligible host and internal battery") }
  return (try byte(.charge), try byte(.limit))
 }
 private func save(_ values: [Entry]) throws {
  guard let store else { return }
  let data = values.isEmpty ? nil : try JSONEncoder().encode(Record(kind: "numericFirmwareV1", version: 1, bootSession: bootSession, entries: values))
  try store.save(data)
 }
 private func loadRecovery() throws {
  guard !loaded, let store else { return }
  guard let currentBoot = UUID(uuidString: bootSession) else { throw HardwareError.invalidData("Missing firmware boot session") }
  if let data = try store.load() {
   guard data.count <= 8192 else { throw HardwareError.invalidData("Firmware journal too large") }
   let record = try JSONDecoder().decode(Record.self, from: data)
   guard record.kind == "numericFirmwareV1", record.version == 1, let recordedBoot = UUID(uuidString: record.bootSession), record.entries.count <= 2,
         Set(record.entries.map(\.key)).count == record.entries.count,
         record.entries.allSatisfy({ entry in Self.valid(entry.original, for: entry.key) && Self.valid(entry.expected, for: entry.key) }) else {
    throw HardwareError.invalidData("Invalid firmware recovery record")
   }
   for entry in record.entries {
    if let previous = entry.previous, !Self.valid(previous, for: entry.key) { throw HardwareError.invalidData("Invalid previous firmware state") }
   }
   if currentBoot == recordedBoot && !record.entries.isEmpty {
    entries = record.entries; interrupted = !entries.isEmpty
   } else { try store.save(nil) }
  }
  loaded = true
 }
 private func transact(_ target: UInt8) throws {
  do {
   let values = try profile()
   let plan: [(Key, UInt8, UInt8)] = [(.charge, 0, values.charge), (.limit, target, values.limit)]
   for (key, _, before) in plan {
    if let owned = entries.first(where: { $0.key == key }), owned.expected != before {
     throw HardwareError.invalidData("External firmware state changed: \(key.rawValue)")
    }
   }
   for (key, wanted, before) in plan {
    guard wanted != before else { continue }
    // Recheck the captured state immediately before recording the intended write.
    guard try byte(key) == before else { throw HardwareError.invalidData("Firmware state changed before write: \(key.rawValue)") }
    if let index = entries.firstIndex(where: { $0.key == key }) {
     entries[index].previous = before; entries[index].expected = wanted
    } else { entries.append(Entry(key: key, original: before, expected: wanted, previous: before)) }
    try save(entries)
    guard try byte(key) == before else { throw HardwareError.invalidData("Firmware state changed after journal save: \(key.rawValue)") }
    try write(key.rawValue, wanted)
    guard try byte(key) == wanted else { throw HardwareError.invalidData("Firmware readback mismatch: \(key.rawValue)") }
    if let index = entries.firstIndex(where: { $0.key == key }) { entries[index].previous = nil }
   }
   let final = try profile()
   guard final.charge == 0 && final.limit == target else {
    throw HardwareError.invalidData("Firmware transaction final state mismatch")
   }
  } catch {
   let failure = error
   do { try restoreOwned() }
   catch { interrupted = true; throw HardwareError.invalidData("Firmware action failed: \(failure.localizedDescription); recovery pending: \(error.localizedDescription)") }
   throw failure
  }
 }
 private func restoreOwned() throws {
  guard entries.isEmpty || (eligibleHost && batteryPresent) else { throw HardwareError.unsupported("Firmware recovery requires eligible hardware") }
  var failures: [String] = []
  for entry in entries.reversed() {
   do {
    guard let current = try optionalByte(entry.key.rawValue) else { throw HardwareError.unavailable("Firmware recovery key missing: \(entry.key.rawValue)") }
    if (current == entry.expected || current == entry.previous) && current != entry.original {
     try write(entry.key.rawValue, entry.original)
     guard try byte(entry.key) == entry.original else { throw HardwareError.invalidData("Firmware restore readback mismatch") }
    }
    let remaining = entries.filter { $0.key != entry.key }
    try save(remaining)
    entries = remaining
   } catch { failures.append("\(entry.key.rawValue): \(error.localizedDescription)") }
  }
  if !failures.isEmpty { throw HardwareError.unavailable(failures.joined(separator: "; ")) }
 }
}
