import Foundation

public struct SleepProtectionPlan: Equatable, Sendable {
 public let preventIdleSleep: Bool
 public let preventSystemAndLidSleep: Bool
 public let preventDisplaySleep: Bool
 public static func supportsHelper(_ capabilities: String) -> Bool {
  let fields = Set(capabilities.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
  return fields.contains("sleepOverride:interfacesDetected") && fields.contains("sleepRecovery:phasesV1")
 }
 public static func evaluate(controlEnabled: Bool, connected: Bool, physicalAdapterConnected: Bool?, action: ChargeAction, percent: Double, target: Double, calibrating: Bool, idleUntilTarget: Bool, systemUntilTarget: Bool, allowDisplaySleep: Bool, lidClosed: Bool? = false, ownAdapterInhibited: Bool = false) -> Self {
  let adapterPresent = physicalAdapterConnected ?? (connected || ownAdapterInhibited)
  guard controlEnabled, action != .restore, adapterPresent else { return Self(preventIdleSleep: false, preventSystemAndLidSleep: false, preventDisplaySleep: false) }
  let moving = action == .forceDischarge || (action == .allowCharge && percent.isFinite && target.isFinite && percent < target)
  let needed = moving || calibrating
  let discharging = action == .forceDischarge
  // An unreadable lid must not silently remove protection during discharge.
  let full = calibrating || (discharging && lidClosed != false) || (needed && systemUntilTarget)
  return Self(preventIdleSleep: needed && (idleUntilTarget || calibrating || discharging), preventSystemAndLidSleep: full, preventDisplaySleep: full && (calibrating || !allowDisplaySleep))
 }
}
