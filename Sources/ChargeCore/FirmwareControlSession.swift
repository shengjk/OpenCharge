import Foundation

public enum FirmwareSessionError: Error, LocalizedError {
 case rejected(String)
 public var errorDescription: String? { switch self { case .rejected(let value): return value } }
}

/// Helper-owned state, serialized by the helper's main queue. No hardware or IPC
/// implementation lives here; production callbacks and fixture callbacks share it.
public final class FirmwareControlSession {
 public private(set) var active = false
 public private(set) var sleepTarget: Int?
 private let status: () throws -> String
 private let preflight: () throws -> Void
 private let beforeMutation: () throws -> Void
 private let limit: (Int) throws -> Void
 private let inhibit: () throws -> Void
 private let beforeExit: () throws -> Void
 private let exit: (Int) throws -> Void
 public init(status: @escaping () throws -> String, preflight: @escaping () throws -> Void,
             beforeMutation: @escaping () throws -> Void, limit: @escaping (Int) throws -> Void,
             inhibit: @escaping () throws -> Void, beforeExit: @escaping () throws -> Void,
             exit: @escaping (Int) throws -> Void) {
  self.status = status; self.preflight = preflight; self.beforeMutation = beforeMutation
  self.limit = limit; self.inhibit = inhibit; self.beforeExit = beforeExit; self.exit = exit
 }
 public func reset() { active = false; sleepTarget = nil }
 public func execute(_ command: FirmwareCommand, recoveryPending: Bool, sleepObserverAvailable: Bool) throws -> String {
  guard command.wireValue != nil else { throw FirmwareSessionError.rejected("Invalid firmware command") }
  switch command {
  case .status: return try status()
  case .sleepOff: sleepTarget = nil; return "firmware sleep policy cleared"
  case .sleepTarget(let value):
   guard !recoveryPending, active, sleepObserverAvailable else { throw FirmwareSessionError.rejected("Firmware sleep policy requires an active recovered session and observer") }
   sleepTarget = value; return "firmware sleep target accepted"
  case .allow, .inhibit, .limit, .exit:
   guard !recoveryPending else { throw FirmwareSessionError.rejected("Charge recovery pending") }
   if case .exit = command { guard active else { throw FirmwareSessionError.rejected("Firmware exit requires a current session") } }
   try preflight()
   // Ownership/watchdog must be armed before a callback can write or release state.
   try beforeMutation()
   switch command {
   case .allow: try limit(100)
   case .inhibit: try inhibit()
   case .limit(let value): try limit(value)
   case .exit(let value): try beforeExit(); try exit(value); reset(); return "firmware exit target committed"
   default: break
   }
   active = true
   return "firmware request accepted; physical effects unverified"
  }
 }
 /// Sleeping preserves the session lease. Wake and interrupted-client recovery are
 /// handled by the same helper lease used for ordinary charge sessions.
 @discardableResult public func applySleep(recoveryPending: Bool) throws -> Bool {
  guard active, !recoveryPending, let sleepTarget else { return false }
  try preflight(); try beforeMutation()
  if sleepTarget == 15 { try inhibit() } else { try limit(sleepTarget) }
  return true
 }
}
