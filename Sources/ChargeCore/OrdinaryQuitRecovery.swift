import Foundation

/// The intent is stored before ordinary cancellation compensation. Clearing it
/// requires both a helper acknowledgement and a successful configuration save.
/// It does not describe a numeric exit target already committed to firmware.
public enum OrdinaryQuitRecovery {
 public static func begin(configuration: inout Configuration, persist: (Configuration) throws -> Void) throws {
  configuration.hardwareEnabled = false
  configuration.pendingOrdinaryQuitRecovery = true
  try persist(configuration)
 }
 public static func acknowledgeRestore(configuration: inout Configuration, persist: (Configuration) throws -> Void) throws {
  guard configuration.pendingOrdinaryQuitRecovery == true else { return }
  var cleared = configuration
  cleared.hardwareEnabled = false; cleared.pendingOrdinaryQuitRecovery = nil
  try persist(cleared)
  configuration = cleared
 }
 @discardableResult public static func restoreIfNeeded(configuration: inout Configuration, request: (String) throws -> String, persist: (Configuration) throws -> Void) throws -> String? {
  guard configuration.pendingOrdinaryQuitRecovery == true else { return nil }
  let reply = try request("restore")
  try acknowledgeRestore(configuration:&configuration,persist:persist)
  return reply
 }
}
