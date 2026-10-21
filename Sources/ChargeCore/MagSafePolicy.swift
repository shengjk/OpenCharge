import Foundation

public enum MagSafeMode: String, Codable, CaseIterable { case system, chargeState, off, green, orange, orangeBlinking
 public var displayName: String { switch self { case .system: return "系统灯光"; case .chargeState: return "指示充电状态"; case .off: return "始终熄灭"; case .green: return "固定绿色"; case .orange: return "固定橙色"; case .orangeBlinking: return "橙色闪烁" } }
}
public enum MagSafeEncodingError: LocalizedError {
 case unavailableInterface, outdatedService
 public var errorDescription: String? {
  switch self {
  case .unavailableInterface: return "未检测到可识别的 MagSafe 灯光接口"
  case .outdatedService: return "灯光服务版本较旧，请更新服务以使用正确颜色和原生闪烁"
  }
 }
}
public enum MagSafePolicy {
 public static func validateNativeEncoding(command: String, capabilities: () throws -> String) throws {
  guard command == "magSafeGreen" || command == "magSafeBlinkOrange" else { return }
  let fields = try capabilities()
  if fields.split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "magSafe:unavailable" }) {
   throw MagSafeEncodingError.unavailableInterface
  }
  guard supportsNativeEncoding(fields) else { throw MagSafeEncodingError.outdatedService }
 }
 public static func supportsNativeEncoding(_ capabilities: String) -> Bool {
  capabilities.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "magSafeEncoding:aclcNativeV2" }
 }
 /// Physical adapter presence matters during forced discharge, where logical AC can be false.
 public static func command(mode: MagSafeMode, connected: Bool, charging: Bool, action: ChargeAction, controlEnabled: Bool, blinkDischarge: Bool, percent: Double, target: Double, sailingHold: Bool = false, calibrating: Bool = false, fullChargeHold: Bool = false) -> String {
  guard connected else { return "magSafeSystem" }
  if mode == .orangeBlinking { return "magSafeBlinkOrange" }
  if mode == .off { return "magSafeOff" }
  if mode == .green { return "magSafeGreen" }; if mode == .orange { return "magSafeOrange" }
  guard mode == .chargeState else { return "magSafeSystem" }
  if controlEnabled && action == .forceDischarge { return blinkDischarge ? "magSafeBlinkOrange" : "magSafeOrange" }
  if calibrating { return "magSafeOrange" }
  if percent.isFinite && target.isFinite && (percent >= target || (controlEnabled && (sailingHold || fullChargeHold))) { return "magSafeGreen" }
  return "magSafeOrange"
 }
}
