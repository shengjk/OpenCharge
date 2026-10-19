import Foundation

public enum MagSafeColor: String, CaseIterable, Codable { case off, green, orange
 var byte: UInt8 { switch self { case .off: return 1; case .green: return 3; case .orange: return 4 } }
}

/// ACLC has no documented automatic/reset value. Restore the captured value instead.
/// Serialized by its caller; injected byte access permits verification without SMC writes.
public final class MagSafeController {
 private let read: () throws -> [UInt8]?
 private let write: ([UInt8]) throws -> Void
 private var original: [UInt8]?
 private var expected: [UInt8]?
 private var previous: [UInt8]?
 public init(read: @escaping () throws -> [UInt8]?, write: @escaping ([UInt8]) throws -> Void) { self.read = read; self.write = write }
 private func value() throws -> [UInt8] {
  guard let bytes = try read(), bytes.count == 1, bytes[0] <= 4 else { throw HardwareError.unsupported("MagSafe ACLC unavailable or unrecognized") }
  return bytes
 }
 public func status() throws -> String {
  let bytes = try value()
  let name = bytes == [1] ? "off" : bytes == [3] ? "green" : bytes == [4] ? "orange" : "system/unknown"
  return "ACLC=\(bytes[0]); color=\(name); ownership=\(original != nil && (bytes == expected || bytes == previous) ? "OpenCharge" : "external")"
 }
 public func set(_ color: MagSafeColor) throws {
  let before = try value(), target = [color.byte]
  // An external writer ends the old ownership interval.
  if expected != nil && before != expected { original = nil; expected = nil; previous = nil }
  guard before != target else { return }
  if original == nil { original = before }
  expected = target; previous = before
  do {
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
  guard let original else { return }
  let current = try value()
  if (current == expected || current == previous) && current != original {
   try write(original)
   guard try value() == original else { throw HardwareError.invalidData("MagSafe restore readback mismatch") }
  }
  self.original = nil; expected = nil; previous = nil
 }
}
