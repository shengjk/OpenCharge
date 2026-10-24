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
 private let dischargeAvailable: Bool
 public init(capabilities: String) throws {
  guard FirmwareHelperCapabilities.supportsAtomicSleepPlan(capabilities) else { throw FirmwareSessionError.rejected("Atomic numeric firmware protocol unavailable") }
  dischargeAvailable = FirmwareHelperCapabilities.supportsNumericDischarge(capabilities)
 }
 private func send(_ command: FirmwareCommand, request: (String) throws -> String) throws {
  guard let value = command.wireValue else { throw FirmwareSessionError.rejected("Invalid firmware command") }
  mayOwnSession = true
  do { _ = try request(value) } catch { cleanupPending = true; throw error }
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
  guard !cleanupPending else { throw FirmwareSessionError.rejected("Firmware cleanup pending") }
  if lastAction == nil { try plan(.inhibit,target:15,request:request) }
 }
 public func apply(_ action: ChargeAction, policy: ChargePolicy, phase: PolicyPhase, request: (String) throws -> String) throws {
  guard !cleanupPending else { throw FirmwareSessionError.rejected("Firmware cleanup pending") }
  if action == .restore { try restore(request:request); return }
  guard phase != .intelMode, policy.limit.isFinite, (20...100).contains(policy.limit) else { throw FirmwareSessionError.rejected("Invalid firmware policy") }
  if action == .forceDischarge && !dischargeAvailable { throw FirmwareSessionError.rejected("Firmware inflow protocol unavailable") }
  do {
   let desired: FirmwareControlAction = action == .allowCharge ? .allow : action == .forceDischarge ? .discharge : .inhibit
   var observed: FirmwareHelperState?
   if lastAction != nil { observed = try inspect(request:request) }
   if desired == .allow {
    // A validated allow transaction has CH0B=0 and BCLM=100, so this control
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
  } catch { if mayOwnSession { cleanupPending = true }; throw error }
 }
 public func restore(request: (String) throws -> String) throws {
  do { _ = try request("restore"); clear() }
  catch { mayOwnSession = true; cleanupPending = true; throw error }
 }
 public func finishExit(policy: ChargePolicy, phase: PolicyPhase, active: Bool, request: (String) throws -> String) throws {
  guard mayOwnSession, !cleanupPending, lastAction != nil else { try restore(request:request); return }
  guard let target = FirmwareLimitProjection.onExit(policy:policy,phase:phase,active:active) else { throw FirmwareSessionError.rejected("Invalid firmware exit projection") }
  try send(.exit(Int(target)),request:request); clear()
 }
 private func clear() { mayOwnSession = false; cleanupPending = false; sleepTarget = nil; lastAction = nil; status = nil }
}
