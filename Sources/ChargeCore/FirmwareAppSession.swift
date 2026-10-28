import Foundation

/// App-side ownership follows acknowledged requests, never a matching register
/// value. An ambiguous failure retains cleanup responsibility until restore is
/// acknowledged. The root helper independently owns the lease and recovery.
public final class FirmwareAppSession {
 public private(set) var mayOwnSession = false
 public private(set) var cleanupPending = false
 public private(set) var sleepTarget: UInt8?
 public private(set) var status: FirmwareHelperState?
 private var lastAction: FirmwareControlAction?
 public private(set) var preparedExit: FirmwareControlSession.ExitPreparation?
 public private(set) var exitCommitAttempted = false
 private let cancellableExitAvailable: Bool
 private let dischargeAvailable: Bool
 public init(capabilities: String) throws {
  guard FirmwareHelperCapabilities.supportsAtomicSleepPlan(capabilities) else { throw FirmwareSessionError.rejected("Atomic numeric firmware protocol unavailable") }
  cancellableExitAvailable = FirmwareHelperCapabilities.supportsCancellableExit(capabilities)
  dischargeAvailable = FirmwareHelperCapabilities.supportsNumericDischarge(capabilities)
 }
 private func send(_ command: FirmwareCommand, request: (String) throws -> String) throws {
  guard let value = command.wireValue else { throw FirmwareSessionError.rejected("Invalid firmware command") }
  let previouslyOwned = mayOwnSession
  mayOwnSession = true
  do { _ = try request(value) }
  catch ChargeControlSuspension.systemSleep { mayOwnSession = previouslyOwned; throw ChargeControlSuspension.systemSleep }
  catch { cleanupPending = true; throw error }
 }
 private func plan(_ action: FirmwareControlAction, target: UInt8, request: (String) throws -> String) throws {
  try send(.plan(action,sleepTarget:Int(target)),request:request)
  lastAction = action; sleepTarget = target
 }
 private func inspect(request: (String) throws -> String) throws -> FirmwareHelperState {
  let reply = try request("firmwareSessionStatus")
  guard reply.hasPrefix("session=active,") else { throw FirmwareSessionError.rejected("Firmware session lost or invalid status; control must be re-enabled") }
  guard let value = FirmwareHelperState(reply:String(reply.dropFirst("session=active,".count))) else { throw FirmwareSessionError.rejected("Invalid firmware status") }
  status = value; return value
 }
 /// Establish only inhibition before requesting protection that itself requires
 /// an active root charge session. This never starts charging or inflow-off.
 public func prepareProtection(request: (String) throws -> String) throws {
  guard !cleanupPending, preparedExit == nil, !exitCommitAttempted else { throw FirmwareSessionError.rejected("Firmware cleanup or exit pending") }
  if lastAction == nil { try plan(.inhibit,target:15,request:request) }
 }
 public func apply(_ action: ChargeAction, policy: ChargePolicy, phase: PolicyPhase, request: (String) throws -> String) throws {
  guard !cleanupPending, preparedExit == nil, !exitCommitAttempted else { throw FirmwareSessionError.rejected("Firmware cleanup or exit pending") }
  if action == .restore { try restore(request:request); return }
  guard phase != .intelMode, policy.limit.isFinite, (20...100).contains(policy.limit) else { throw FirmwareSessionError.rejected("Invalid firmware policy") }
  if action == .forceDischarge && !dischargeAvailable { throw FirmwareSessionError.rejected("Firmware inflow protocol unavailable") }
  do {
   let desired: FirmwareControlAction = action == .allowCharge ? .allow : action == .forceDischarge ? .discharge : .inhibit
   var observed: FirmwareHelperState?
   if lastAction != nil { observed = try inspect(request:request) }
   if desired == .allow {
    // A validated allow transaction has BCLM=100 (and CH0B=0 for paired profiles), so this control
    // state is known independently of OS charging or measured battery power.
    guard let target = FirmwareLimitProjection.onSleep(policy:policy,phase:phase,smcCharging:true) else { throw FirmwareSessionError.rejected("Invalid firmware sleep projection") }
    try plan(.allow,target:target,request:request); status = nil; return
   }
   // Bootstrap safely with inhibition and a sleep target in one root operation.
   // Do not release/recreate a healthy inflow assertion on every heartbeat.
   if lastAction == nil || lastAction == .allow || (desired == .inhibit && lastAction == .discharge) {
    try plan(.inhibit,target:15,request:request)
    observed = nil
   }
   if observed == nil { observed = try inspect(request:request) }
   if observed?.limit != 15 { try plan(.inhibit,target:15,request:request); observed = try inspect(request:request) }
   guard let target = FirmwareLimitProjection.onSleep(policy:policy,phase:phase,smcCharging:observed?.chargingAllowed) else { throw FirmwareSessionError.rejected("Firmware charging-control state is unknown") }
   try plan(desired,target:target,request:request)
  } catch ChargeControlSuspension.systemSleep { throw ChargeControlSuspension.systemSleep }
  catch { if mayOwnSession { cleanupPending = true }; throw error }
 }
 public func restore(request: (String) throws -> String) throws {
  guard !exitCommitAttempted else { throw FirmwareSessionError.rejected("Final firmware exit may already be committed; restoration cannot prove rollback") }
  do { _ = try request("restore"); clear() }
  catch { mayOwnSession = true; cleanupPending = true; throw error }
 }
 /// Preparation retains the helper journal. Retrying an ambiguous preparation
 /// uses the same identity and target; it never starts a new transaction.
 public func prepareExit(policy: ChargePolicy, phase: PolicyPhase, active: Bool, request: (String) throws -> String) throws {
  guard !exitCommitAttempted else { throw FirmwareSessionError.rejected("Final firmware exit confirmation already started") }
  if preparedExit == nil {
   guard mayOwnSession, !cleanupPending, lastAction != nil else { try restore(request:request); return }
   guard cancellableExitAvailable else { throw FirmwareSessionError.rejected(NSLocalizedString("数值退出需要更新辅助服务以支持可取消退出",comment:"")) }
   guard let target = FirmwareLimitProjection.onExit(policy:policy,phase:phase,active:active) else { throw FirmwareSessionError.rejected("Invalid firmware exit projection") }
   preparedExit = FirmwareControlSession.ExitPreparation(target:Int(target),id:UUID())
  }
  let intent = preparedExit!
  try send(.exitPrepare(intent.target,intent.id),request:request)
  cleanupPending = false; sleepTarget = nil; status = nil
 }
 /// A live confirmation dialog renews only the already-acknowledged prepared
 /// transaction. The helper treats its identical prepare as a no-write retry.
 public func renewExitPreparation(request: (String) throws -> String) throws {
  guard let intent = preparedExit, !cleanupPending, !exitCommitAttempted else { return }
  try send(.exitPrepare(intent.target,intent.id),request:request)
 }
 /// After delivery starts, restoration cannot prove rollback: an acknowledgement
 /// may have been lost after journal removal. Only retry this same commit or exit.
 public func commitExit(request: (String) throws -> String) throws {
  guard let intent = preparedExit else { return }
  guard !cleanupPending || exitCommitAttempted else { throw FirmwareSessionError.rejected("Firmware exit preparation has not been acknowledged") }
  exitCommitAttempted = true
  try send(.exitCommit(intent.id),request:request)
  clear(); exitCommitAttempted = true
 }
 private func clear() { mayOwnSession = false; cleanupPending = false; sleepTarget = nil; lastAction = nil; status = nil; preparedExit = nil; exitCommitAttempted = false }
}
