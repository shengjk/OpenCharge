import Foundation

/// A successful protocol advertisement is separate from an available, recovered
/// numeric profile. Ordinary charge support is never a numeric fallback.
public enum FirmwareHelperCapabilities {
 public static func supportsNumericControl(_ reply: String) -> Bool {
  supports(reply, discharge: false)
 }
 /// A distinct command extension; fixedV1 alone predates inflow control.
 public static func supportsNumericDischarge(_ reply: String) -> Bool {
  supports(reply, discharge: true)
 }
 private static func supports(_ reply: String, discharge: Bool) -> Bool {
  guard reply.utf8.count <= 4096, !reply.contains("\n"), !reply.contains("\r") else { return false }
  var expected = ["firmwareProtocol":"fixedV1", "firmwareRead":"CH0B+BCLM", "firmwareWrite":"fixedV1", "chargeRecovery":"ready", "internalBattery":"present"]
  if discharge { expected["firmwareDischarge"] = "inflowV1" }
  var found: [String:String] = [:]
  for part in reply.split(separator:",",omittingEmptySubsequences:false) {
   let item = part.trimmingCharacters(in:.whitespaces)
   guard let colon = item.firstIndex(of:":") else { continue }
   let key = String(item[..<colon])
   guard expected[key] != nil else { continue }
   guard found[key] == nil else { return false }
   found[key] = String(item[item.index(after:colon)...])
  }
  return expected.allSatisfy { found[$0.key] == $0.value }
 }
}

/// Fixed helper status, distinct from OS charging or measured battery power.
public struct FirmwareHelperState: Equatable, Sendable {
 public let limit: UInt8
 public let chargingAllowed: Bool?
 public init?(reply: String) {
  guard reply.utf8.count <= 128, !reply.contains("\n"), !reply.contains("\r") else { return nil }
  let parts = reply.split(separator:",",omittingEmptySubsequences:false)
  guard parts.count == 2 else { return nil }
  var fields: [String:String] = [:]
  for part in parts {
   let item = part.trimmingCharacters(in:.whitespaces)
   let pair = item.split(separator:"=",omittingEmptySubsequences:false)
   guard pair.count == 2, ["limit","charging"].contains(pair[0]), fields[String(pair[0])] == nil else { return nil }
   fields[String(pair[0])] = String(pair[1])
  }
  guard let text = fields["limit"], let number = Int(text), String(number) == text,
        number == 15 || (20...100).contains(number), let state = fields["charging"] else { return nil }
  switch state { case "allowed": chargingAllowed = true
  case "inhibited": chargingAllowed = false
  case "unknown": chargingAllowed = nil
  default: return nil }
  limit = UInt8(number)
 }
}
