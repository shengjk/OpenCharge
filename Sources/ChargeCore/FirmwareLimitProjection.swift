import Foundation

/// Numeric firmware targets are distinct from active charge inhibition.
/// This projection performs no hardware access; nil requires the caller to stop
/// rather than substitute observed amperage or an OS charging flag.
public enum FirmwareLimitProjection {
 public static let inhibited: UInt8 = 15
 public static let unrestricted: UInt8 = 100

 public static func onSleep(policy: ChargePolicy, phase: PolicyPhase, smcCharging: Bool?) -> UInt8? {
  guard phase != .intelMode, let upper = upperLimit(policy) else { return nil }
  if phase == .sailing {
   guard let lower = lowerLimit(policy) else { return nil }
   if lower >= 20 { return UInt8(lower) }
  }
  // Both possible charge-control readings converge on the daily limit here.
  if phase == .heatProtect { return upper }
  guard let smcCharging else { return nil }
  return smcCharging ? upper : inhibited
 }

 /// The intended reset target for an orderly exit, not an observed write or a
 /// promise that firmware preserves the target after shutdown.
 public static func onExit(policy: ChargePolicy, phase: PolicyPhase, active: Bool, resetToFull: Bool = false) -> UInt8? {
  if !active || resetToFull { return unrestricted }
  guard phase != .intelMode, let upper = upperLimit(policy) else { return nil }
  if policy.sailing && phase == .sailing {
   guard let lower = lowerLimit(policy) else { return nil }
   if lower >= 20 { return UInt8(lower) }
  }
  return upper
 }

 private static func upperLimit(_ policy: ChargePolicy) -> UInt8? {
  guard policy.limit.isFinite, (20...100).contains(policy.limit) else { return nil }
  return UInt8(Float(policy.limit))
 }
 private static func lowerLimit(_ policy: ChargePolicy) -> Float? {
  guard policy.sailingWidth.isFinite, (1...20).contains(policy.sailingWidth) else { return nil }
  return Float(policy.limit) - Float(policy.sailingWidth)
 }
}
