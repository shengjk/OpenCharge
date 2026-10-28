import Foundation

public enum FirmwareSessionError: Error, LocalizedError {
 case rejected(String)
 public var errorDescription: String? { switch self { case .rejected(let value): return value } }
}

/// Helper-owned state, serialized by the helper's main queue. No hardware or IPC
/// implementation lives here; production callbacks and fixture callbacks share it.
public final class FirmwareControlSession {
 public struct ExitPreparation: Equatable {
  public let target: Int
  public let id: UUID
 }
 public private(set) var pendingExit: ExitPreparation?
 private var committedExit: UUID?
 public private(set) var active = false
 public private(set) var discharging = false
 public private(set) var sleepTarget: Int?
 private let status: () throws -> String
 private let preflight: () throws -> Void
 private let beforeMutation: () throws -> Void
 private let limit: (Int) throws -> Void
 private let inhibit: () throws -> Void
 private let discharge: () throws -> Void
 private let beforeExit: () throws -> Void
 private let exit: (Int) throws -> Void
 public init(status: @escaping () throws -> String, preflight: @escaping () throws -> Void,
             beforeMutation: @escaping () throws -> Void, limit: @escaping (Int) throws -> Void,
             inhibit: @escaping () throws -> Void, discharge: @escaping () throws -> Void, beforeExit: @escaping () throws -> Void,
             exit: @escaping (Int) throws -> Void) {
  self.status = status; self.preflight = preflight; self.beforeMutation = beforeMutation
  self.limit = limit; self.inhibit = inhibit; self.discharge = discharge; self.beforeExit = beforeExit; self.exit = exit
 }
 public func reset() { active = false; discharging = false; sleepTarget = nil; pendingExit = nil; committedExit = nil }
 /// A rejected read-only query cannot tear down a healthy session. A failed
 /// control transition while discharging must enter the helper recovery loop,
 /// even when it failed before the mutation/watchdog callback was reached.
 public func requiresRecoveryAfterFailure(_ command: FirmwareCommand) -> Bool {
  guard discharging else { return false }
  switch command { case .allow, .inhibit, .discharge, .limit, .exit, .exitPrepare, .plan: return true
  default: return false }
 }
 /// The root dispatcher calls this after unwrapping scoped/display requests.
 /// Restoration and independent inspection/LED/power preferences remain usable.
 public func requireExternalAdmission(_ command: String) throws {
  if pendingExit != nil, ["allowCharge","inhibitCharge","forceDischarge","retainChargeInhibit","sleepPolicyOn","sleepOverrideOn","sleepOverrideDisplayOn"].contains(command) {
   throw FirmwareSessionError.rejected("Firmware exit preparation pending; restore before new control")
  }
 }
 public func execute(_ command: FirmwareCommand, recoveryPending: Bool, sleepObserverAvailable: Bool) throws -> String {
  guard command.wireValue != nil else { throw FirmwareSessionError.rejected("Invalid firmware command") }
  // A prepared exit may only be inspected, retried with the same identity, or
  // committed. Root restoration remains the cancellation path. Other clients
  // cannot replace its target through an ordinary numeric plan.
  if pendingExit != nil {
   switch command { case .status, .sessionStatus, .exitPrepare, .exitCommit: break
   default: throw FirmwareSessionError.rejected("Firmware exit preparation pending") }
  }
  switch command {
  case .exitPrepare(let target, let id):
   guard !recoveryPending, active, sleepObserverAvailable else { throw FirmwareSessionError.rejected("Firmware exit preparation requires an active recovered session and sleep observer") }
   let intent = ExitPreparation(target:target,id:id)
   if let pendingExit {
    guard pendingExit == intent else { throw FirmwareSessionError.rejected("Different firmware exit already prepared") }
    return "firmware exit prepared; journal retained"
   }
   try preflight(); try beforeMutation(); committedExit = nil
   // Retain the actual controller journal. This ends inflow-off and releases
   // sleep protection, but is still undoable by the ordinary restore path.
   try beforeExit(); try limit(target)
   pendingExit = intent; discharging = false; sleepTarget = nil
   return "firmware exit prepared; journal retained"
  case .exitCommit(let id):
   guard !recoveryPending else { throw FirmwareSessionError.rejected("Charge recovery pending") }
   if !active, committedExit == id { return "firmware exit target committed" }
   guard active, let pendingExit, pendingExit.id == id else { throw FirmwareSessionError.rejected("No matching prepared firmware exit") }
   try preflight(); try beforeMutation()
   try exit(pendingExit.target)
   reset(); committedExit = id
   return "firmware exit target committed"
  case .plan(let action, let target):
   guard !recoveryPending, sleepObserverAvailable else { throw FirmwareSessionError.rejected("Atomic firmware plan requires a recovered helper and sleep observer") }
   if action == .discharge { guard active else { throw FirmwareSessionError.rejected("Firmware discharge requires a current session") } }
   try preflight(); try beforeMutation(); committedExit = nil
   // Serialized with the root sleep observer: it cannot run between the action
   // and target assignment, including when creating the first charge session.
   switch action { case .allow: try limit(100)
   case .inhibit: try inhibit()
   case .discharge: try discharge() }
   active = true; discharging = action == .discharge; sleepTarget = target
   return "firmware action and sleep target accepted; physical effects unverified"
  case .status: return try status()
  case .sessionStatus: return "session=\(active ? "active" : "inactive")," + (try status())
  case .sleepOff:
   guard !discharging else { throw FirmwareSessionError.rejected("Stop firmware discharge before clearing its sleep target") }
   sleepTarget = nil; return "firmware sleep policy cleared"
  case .sleepTarget(let value):
   guard !recoveryPending, active, sleepObserverAvailable else { throw FirmwareSessionError.rejected("Firmware sleep policy requires an active recovered session and observer") }
   sleepTarget = value; return "firmware sleep target accepted"
  case .allow, .inhibit, .discharge, .limit, .exit:
   guard !recoveryPending else { throw FirmwareSessionError.rejected("Charge recovery pending") }
   if case .exit = command { guard active else { throw FirmwareSessionError.rejected("Firmware exit requires a current session") } }
   if case .discharge = command {
    guard active, sleepObserverAvailable, sleepTarget != nil else { throw FirmwareSessionError.rejected("Firmware discharge requires an active session, observer and sleep target") }
   }
   try preflight()
   // Ownership/watchdog must be armed before a callback can write or release state.
   try beforeMutation(); committedExit = nil
   switch command {
   case .allow: try limit(100)
   case .inhibit: try inhibit()
   case .discharge: try discharge()
   case .limit(let value): try limit(value)
   case .exit(let value): try beforeExit(); try exit(value); reset(); return "firmware exit target committed"
   default: break
   }
   active = true
   discharging = command == .discharge
   return "firmware request accepted; physical effects unverified"
  }
 }
 /// Sleeping preserves the session lease. Wake and interrupted-client recovery are
 /// handled by the same helper lease used for ordinary charge sessions.
 @discardableResult public func applySleep(recoveryPending: Bool) throws -> Bool {
  guard active, pendingExit == nil, !recoveryPending, let sleepTarget else { return false }
  try preflight(); try beforeMutation()
  if sleepTarget == 15 { try inhibit() } else { try limit(sleepTarget) }
  discharging = false
  return true
 }
 public enum SleepResult: Equatable { case unchanged, applied, restored }
 /// The actual helper uses this before acknowledging OS sleep. Pending cleanup
 /// is retried at entry, and a failed policy update immediately attempts cleanup.
 public func reconcileSleep(recoveryPending: Bool, restore: () throws -> Void) throws -> SleepResult {
  if recoveryPending { try restore(); reset(); return .restored }
  do { return try applySleep(recoveryPending:false) ? .applied : .unchanged }
  catch {
   let original = error
   do { try restore(); reset(); return .restored }
   catch { throw FirmwareSessionError.rejected("Firmware sleep update failed: \(original.localizedDescription); cleanup pending: \(error.localizedDescription)") }
  }
 }
}
