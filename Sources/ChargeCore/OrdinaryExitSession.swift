import Foundation

public enum OrdinaryExitError: Error, LocalizedError {
 case rejected(String)
 public var errorDescription: String? { switch self { case .rejected(let message): return message } }
}

/// Fixed ordinary-backend exit requests. UUIDs correlate retries; the helper's
/// existing active-console peer checks remain the authorization boundary.
public enum OrdinaryExitCommand: Equatable, Sendable {
 case prepare(UUID), commit(UUID)
 public var wireValue: String {
  switch self { case .prepare(let id): return "ordinaryExitPrepare:\(id.uuidString)"
  case .commit(let id): return "ordinaryExitCommit:\(id.uuidString)" }
 }
 public static func parse(_ value: String) -> Self? {
  guard value.utf8.count < 128 else { return nil }
  let parts = value.split(separator:":",omittingEmptySubsequences:false)
  guard parts.count == 2, let id = UUID(uuidString:String(parts[1])), id.uuidString == parts[1] else { return nil }
  switch parts[0] { case "ordinaryExitPrepare": return .prepare(id)
  case "ordinaryExitCommit": return .commit(id)
  default: return nil }
 }
 public static func supportsHelper(_ capabilities: String) -> Bool {
  capabilities.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }.filter { $0.hasPrefix("ordinaryExit:") } == ["ordinaryExit:preparedV1"]
 }
}

/// Serialized by the root helper. Preparation keeps both the ordinary recovery
/// journal and awake watchdog. Only final commit permits graceful service exit
/// to leave the already-inhibited charge values in place. Explicit restore and
/// the next helper startup still recover the captured original values.
public final class OrdinaryExitSession {
 public private(set) var preparedID: UUID?
 public private(set) var committedID: UUID?
 public init() {}
 public func reset() { preparedID = nil; committedID = nil }
 public func requireExternalAdmission(_ command: String) throws {
  guard preparedID != nil else { return }
  if let firmware = FirmwareCommand.parse(command) {
   switch firmware { case .status, .sessionStatus: return
   default: throw OrdinaryExitError.rejected("Ordinary exit preparation pending") }
  }
  if ["allowCharge","inhibitCharge","forceDischarge","retainChargeInhibit","sleepPolicyOn","sleepPolicyOff","sleepOverrideOn","sleepOverrideDisplayOn"].contains(command) {
   throw OrdinaryExitError.rejected("Ordinary exit preparation pending; restore before new control")
  }
 }
 public func execute(_ command: OrdinaryExitCommand, recoveryPending: Bool, available: Bool,
                     prepare: () throws -> Void, renew: () -> Void, commit: () -> Void) throws -> String {
  guard !recoveryPending else { throw OrdinaryExitError.rejected("Charge recovery pending") }
  switch command {
  case .prepare(let id):
   guard available else { throw OrdinaryExitError.rejected("Ordinary exit requires an available ordinary backend") }
   if let preparedID {
    guard preparedID == id else { throw OrdinaryExitError.rejected("Different ordinary exit already prepared") }
    renew(); return "ordinary exit prepared"
   }
   guard committedID != id else { throw OrdinaryExitError.rejected("Ordinary exit already committed") }
   committedID = nil
   try prepare(); preparedID = id
   return "ordinary exit prepared"
  case .commit(let id):
   if committedID == id { return "ordinary exit committed" }
   guard available, preparedID == id else { throw OrdinaryExitError.rejected("No matching prepared ordinary exit") }
   commit(); preparedID = nil; committedID = id
   return "ordinary exit committed"
  }
 }
 /// All independent cleanup attempts run even when one fails. Skipping ordinary
 /// charge restoration preserves its journal; it never discards ownership or
 /// writes a caller-provided reset value. A pending recovery overrides retention.
 public func cleanupForServiceExit(recoveryPending: Bool, restoreCharge: () throws -> Void,
                                   restoreLED: () throws -> Void, restoreSleep: () throws -> Void) throws {
  var failure: Error?
  if committedID == nil || recoveryPending { do { try restoreCharge() } catch { failure = error } }
  do { try restoreLED() } catch { failure = failure ?? error }
  do { try restoreSleep() } catch { failure = failure ?? error }
  if let failure { throw failure }
 }
}
