import Foundation

/// Metadata and payload decoding shared by the real AppleSMC client and frame fixtures.
/// The owner serializes access to its connection. This type opens no service itself.
final class SMCKeyIO {
 typealias Call = (String, UInt8, Int, [UInt8]) throws -> [UInt8]
 private let call: Call
 init(call: @escaping Call) { self.call = call }

 private func frame(_ key: String, command: UInt8, count: Int = 0, bytes: [UInt8] = []) throws -> [UInt8] {
  guard key.utf8.count == 4, key.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }),
        (0...32).contains(count), bytes.count <= 32 else { throw HardwareError.invalidData("SMC request bounds") }
  let output = try call(key, command, count, bytes)
  guard output.count == 80 else { throw HardwareError.invalidData("SMC response size") }
  guard output[40] == 0 else { throw HardwareError.driver(0, output[40]) }
  return output
 }
 private func metadata(_ key: String) throws -> (count: Int, type: String) {
  let output = try frame(key, command: 9)
  let size = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) }
  guard (1...32).contains(size) else { throw HardwareError.invalidData("SMC length: \(key)") }
  let type = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
  let bytes = [UInt8(truncatingIfNeeded: type >> 24), UInt8(truncatingIfNeeded: type >> 16), UInt8(truncatingIfNeeded: type >> 8), UInt8(truncatingIfNeeded: type)]
  // Preserve all four bytes, including a trailing space, without guessing an encoding.
  let name = String(bytes: bytes, encoding: .ascii) ?? "unknown"
  return (Int(size), name)
 }
 func read(_ key: String) throws -> SMCByteReading {
  let info = try metadata(key)
  let output = try frame(key, command: 5, count: info.count)
  return SMCByteReading(dataType: info.type, bytes: Array(output[48..<(48 + info.count)]))
 }
 func optionalRead(_ key: String) throws -> SMCByteReading? {
  do { return try read(key) }
  catch HardwareError.driver(let code, let result) where code == 0 && result == 132 { return nil }
 }
 func write(_ key: String, bytes: [UInt8]) throws {
  guard !bytes.isEmpty, bytes.count <= 32 else { throw HardwareError.invalidData("SMC write length") }
  guard try metadata(key).count == bytes.count else { throw HardwareError.invalidData("SMC size changed: \(key)") }
  _ = try frame(key, command: 6, count: bytes.count, bytes: bytes)
 }
 /// Rechecks the numeric profile's type immediately before its fixed byte write.
 func writeFirmwareByte(_ key: String, value: UInt8) throws {
  guard (key == "CH0B" && (value == 0 || value == 2)) ||
        (key == "BCLM" && (value == 15 || (20...100).contains(value))) else {
   throw HardwareError.invalidData("Fixed firmware key/value required")
  }
  let info = try metadata(key)
  guard info.count == 1, info.type == "ui8 " else { throw HardwareError.invalidData("Firmware metadata changed: \(key)") }
  _ = try frame(key, command: 6, count: 1, bytes: [value])
 }
}
