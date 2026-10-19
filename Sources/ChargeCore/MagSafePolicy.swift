import Foundation

public enum MagSafeMode: String, Codable, CaseIterable { case system, chargeState, off, green, orange
 public var displayName: String { switch self { case .system: return "系统灯光"; case .chargeState: return "指示充电状态"; case .off: return "始终熄灭"; case .green: return "固定绿色"; case .orange: return "固定橙色" } }
}
public enum MagSafePolicy {
 /// Physical adapter presence matters during forced discharge, where logical AC can be false.
 public static func command(mode: MagSafeMode, connected: Bool, charging: Bool, action: ChargeAction, controlEnabled: Bool, blinkDischarge: Bool, percent: Double, target: Double, sailingHold: Bool = false, calibrating: Bool = false) -> String {
  guard connected else { return "magSafeSystem" }
  if mode == .off { return "magSafeOff" }
  if mode == .green { return "magSafeGreen" }; if mode == .orange { return "magSafeOrange" }
  guard mode == .chargeState else { return "magSafeSystem" }
  if controlEnabled && action == .forceDischarge { return blinkDischarge ? "magSafeBlinkOrange" : "magSafeOrange" }
  if calibrating { return "magSafeOrange" }
  if percent.isFinite && target.isFinite && (percent >= target || (controlEnabled && sailingHold)) { return "magSafeGreen" }
  return "magSafeOrange"
 }
}
