import Foundation

/// One request per observed closed-lid interval. This never claims a successful lock.
public struct LidLockPolicy: Sendable {
 private var attempted = false
 public init() {}
 public mutating func shouldRequest(lidClosed: Bool?, enabled: Bool, sleepOverrideActive: Bool, consoleSessionActive: Bool) -> Bool {
  if lidClosed == false { attempted = false; return false }
  guard lidClosed == true, enabled, sleepOverrideActive, consoleSessionActive, !attempted else { return false }
  attempted = true
  return true
 }
}
