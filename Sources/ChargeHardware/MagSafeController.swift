import Foundation

public enum MagSafeColor: String, CaseIterable, Codable { case off, green, orange, orangeBlinking
 public var command: String { switch self { case .off: return "magSafeOff"; case .green: return "magSafeGreen"; case .orange: return "magSafeOrange"; case .orangeBlinking: return "magSafeBlinkOrange" } }
 var byte: UInt8 { switch self { case .off: return 1; case .green: return 2; case .orange: return 4; case .orangeBlinking: return 6 } }
}

/// ACLC has no documented automatic/reset value. Restore the captured value instead.
/// Serialized by its caller; injected byte access permits verification without SMC writes.
public final class MagSafeController {
 private let read: () throws -> [UInt8]?
 private let write: ([UInt8]) throws -> Void
 private let recoveryStore: ChargeRecoveryStore?
 private let bootSession: String
 private var recoveryLoaded: Bool
 private var interruptedRecoveryPending = false
 private var persistedOriginal: [UInt8]?
 private var persistedStates = Set<[UInt8]>()
 private var original: [UInt8]?
 private var expected: [UInt8]?
 private var previous: [UInt8]?
 public init(read: @escaping () throws -> [UInt8]?, write: @escaping ([UInt8]) throws -> Void, recoveryStore: ChargeRecoveryStore? = nil, bootSession: String = "") {
  self.read = read; self.write = write; self.recoveryStore = recoveryStore; self.bootSession = bootSession
  recoveryLoaded = recoveryStore == nil
 }
 private struct RecoveryRecord: Codable {
  let version: Int
  let bootSession: String
  let original: [UInt8]
  let expected: [UInt8]
  let previous: [UInt8]?
 }
 private func loadRecovery() throws {
  guard !recoveryLoaded, let recoveryStore else { return }
  guard UUID(uuidString: bootSession) != nil else { throw HardwareError.invalidData("Missing LED boot identity") }
  if let data = try recoveryStore.load() {
   guard data.count <= 8192 else { throw HardwareError.invalidData("LED recovery record too large") }
   let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
   func valid(_ bytes: [UInt8]) -> Bool { bytes.count == 1 && [0,1,2,3,4,6].contains(bytes[0]) }
   guard record.version == 1, UUID(uuidString: record.bootSession) != nil,
         valid(record.original), record.expected.count == 1, [1,2,3,4,6].contains(record.expected[0]),
         record.previous.map(valid) ?? true else { throw HardwareError.invalidData("Invalid LED recovery record") }
   if UUID(uuidString: record.bootSession) == UUID(uuidString: bootSession) {
    original = record.original; expected = record.expected; previous = record.previous
    persistedOriginal = record.original; persistedStates = Set([record.expected] + (record.previous.map { [$0] } ?? []))
    interruptedRecoveryPending = true
   } else { try recoveryStore.save(nil) }
  }
  recoveryLoaded = true
 }
 private func persist() throws {
  guard let recoveryStore, let original, let expected else { return }
  let states = Set([expected] + (previous.map { [$0] } ?? []))
  // Alternating LED states can reuse a durable record that already covers both sides.
  if persistedOriginal == original && states.isSubset(of: persistedStates) { return }
  try recoveryStore.save(JSONEncoder().encode(RecoveryRecord(version: 1, bootSession: bootSession, original: original, expected: expected, previous: previous)))
  persistedOriginal = original; persistedStates = states
 }
 private func value() throws -> [UInt8] {
  guard let bytes = try read(), bytes.count == 1, [0,1,2,3,4,6].contains(bytes[0]) else { throw HardwareError.unsupported("MagSafe ACLC unavailable or unrecognized") }
  return bytes
 }
 public func status() throws -> String {
  let bytes = try value()
  let name = bytes == [1] ? "off" : bytes == [2] ? "green" : bytes == [4] ? "orange" : bytes == [6] ? "orange-blinking" : "system/legacy/unknown"
  return "ACLC=\(bytes[0]); color=\(name); ownership=\(original != nil && (bytes == expected || bytes == previous) ? "OpenCharge" : "external")"
 }
 public func set(_ color: MagSafeColor) throws {
  try loadRecovery()
  guard !interruptedRecoveryPending else { throw HardwareError.unavailable("Interrupted LED recovery pending") }
  let before = try value(), target = [color.byte]
  // An external writer ends the old ownership interval.
  if expected != nil && before != expected {
   try recoveryStore?.save(nil)
   original = nil; expected = nil; previous = nil; persistedOriginal = nil; persistedStates = []
  }
  guard before != target else { return }
  if original == nil { original = before }
  expected = target; previous = before
  do {
   try persist()
   try write(target)
   guard try value() == target else { throw HardwareError.invalidData("MagSafe readback mismatch") }
   previous = nil
  } catch {
   let actionError = error
   do { try restore() } catch { throw HardwareError.invalidData("MagSafe action failed: \(actionError.localizedDescription); restoration incomplete: \(error.localizedDescription)") }
   throw actionError
  }
 }
 public func restore() throws {
  try loadRecovery()
  guard let original else { interruptedRecoveryPending = false; return }
  let current = try value()
  if (current == expected || current == previous) && current != original {
   try write(original)
   guard try value() == original else { throw HardwareError.invalidData("MagSafe restore readback mismatch") }
  }
  try recoveryStore?.save(nil)
  self.original = nil; expected = nil; previous = nil; persistedOriginal = nil; persistedStates = []; interruptedRecoveryPending = false
 }
}
