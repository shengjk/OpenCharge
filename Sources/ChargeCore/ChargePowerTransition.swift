import Foundation

/// An authenticated helper can distinguish a rejected, unexecuted request from
/// an ambiguous transport failure. Only the exact reply has this meaning.
public enum ChargeControlSuspension: Error, LocalizedError, Equatable {
 case systemSleep
 public static let reply = "SUSPENDED sleep-transition"
 public var errorDescription: String? { NSLocalizedString("系统睡眠或控制阶段已变化，稍后重新确认", comment: "") }
}

/// Serialized with charge actions on the helper's main queue. Sleep preparation
/// has already selected the sleeping target; late client requests cannot replace it.
public struct ChargePowerTransition: Sendable {
 public private(set) var sleeping = false
 private var sessionID = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
 private var generation: UInt64 = 0
 public init() {}
 private var token: String { "\(sessionID)-\(generation)" }
 public var contextReply: String { "epoch=\(token),state=\(sleeping ? "sleeping" : "awake")" }
 private mutating func advance() {
  if generation == .max { sessionID = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(); generation = 0 }
  else { generation += 1 }
 }
 /// Recovery or a console-owner change can retire previously confirmed protection while awake.
 public mutating func invalidate() { advance() }
 public mutating func willSleep() { if !sleeping { advance(); sleeping = true } }
 public mutating func didWake() { if sleeping { advance(); sleeping = false } }
 public func requireAdmission(_ command: String) throws { _ = try admittedCommand(command) }
 public func admittedCommand(_ wire: String) throws -> String {
  if wire.hasPrefix("chargeRequest:") {
   guard let request = ChargeRequestContext.parseEnvelope(wire) else { throw ChargeContextError.invalidEnvelope }
   guard !sleeping, request.token == token else { throw ChargeControlSuspension.systemSleep }
   return request.command
  }
  try requireUnscopedAdmission(wire)
  return wire
 }
 private func requireUnscopedAdmission(_ command: String) throws {
  guard sleeping else { return }
  if DischargeSleepRequest.underlying(command) != nil { throw ChargeControlSuspension.systemSleep }
  if let firmware = FirmwareCommand.parse(command) {
   switch firmware {
   case .status, .sessionStatus, .exit: return
   default: throw ChargeControlSuspension.systemSleep
   }
  }
  if ["allowCharge", "inhibitCharge", "forceDischarge", "sleepPolicyOn", "sleepPolicyOff", "sleepOverrideOn", "sleepOverrideDisplayOn"].contains(command) {
   throw ChargeControlSuspension.systemSleep
  }
 }
}
