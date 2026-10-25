import Foundation

/// Current effective state, independent of the helper's per-source preferences.
/// An unavailable system interface is not an observed off state.
public enum LowPowerObservation {
 public static var current: Bool? {
  if #available(macOS 12.0, *) { return ProcessInfo.processInfo.isLowPowerModeEnabled }
  return nil
 }
 public static var changeNotification: Notification.Name? {
  if #available(macOS 12.0, *) { return .NSProcessInfoPowerStateDidChange }
  return nil
 }
}
