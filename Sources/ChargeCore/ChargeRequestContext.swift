import Foundation

public enum ChargeContextError: Error, LocalizedError {
 case invalidEnvelope
 public var errorDescription: String? { "Invalid charge-control context" }
}

/// One root-issued context covers every control request in an app policy round.
/// The token is an event identity, not authorization; peer/console checks remain mandatory.
public struct ChargeRequestContext: Equatable, Sendable {
 public let token: String
 public let sleeping: Bool
 public init?(reply: String) {
  let parts = reply.split(separator:",",omittingEmptySubsequences:false)
  guard parts.count == 2, parts[0].hasPrefix("epoch="),
   parts[1] == "state=awake" || parts[1] == "state=sleeping" else { return nil }
  let token = String(parts[0].dropFirst(6))
  guard Self.validToken(token) else { return nil }
  self.token = token; sleeping = parts[1] == "state=sleeping"
 }
 public static func supportsHelper(_ capabilities: String) -> Bool {
  capabilities.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }.filter { $0.hasPrefix("chargeTransition:") } == ["chargeTransition:epochV1"]
 }
 private static func validToken(_ token: String) -> Bool {
  let parts = token.split(separator:"-",omittingEmptySubsequences:false)
  guard parts.count == 2, parts[0].utf8.count == 32,
   parts[0].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
   let counter = UInt64(parts[1]), String(counter) == parts[1] else { return false }
  return true
 }
 public static func requiresScope(_ command: String) -> Bool {
  if let firmware = FirmwareCommand.parse(command) {
   if case .exit = firmware { return false }
   return true
  }
  return ["allowCharge","inhibitCharge","forceDischarge","sleepPolicyOn","sleepPolicyOff","sleepOverrideOn","sleepOverrideDisplayOn"].contains(command)
 }
 public func envelope(_ command: String) throws -> String {
  guard !sleeping else { throw ChargeControlSuspension.systemSleep }
  return Self.requiresScope(command) ? "chargeRequest:\(token):\(command)" : command
 }
 public static func parseEnvelope(_ wire: String) -> (token: String, command: String)? {
  guard wire.utf8.count < 128 else { return nil }
  let parts = wire.split(separator:":",maxSplits:2,omittingEmptySubsequences:false)
  guard parts.count == 3, parts[0] == "chargeRequest", validToken(String(parts[1])),
   requiresScope(String(parts[2])) else { return nil }
  return (String(parts[1]),String(parts[2]))
 }
}
