import Foundation

public enum MenuBarRightClickAction: String, CaseIterable, Codable, Identifiable, Sendable {
 case toggleCharging, toggleLowPower, popover, settings
 public var id: Self { self }
 public var title: String {
  switch self {
  case .toggleCharging: return String(localized:"切换充电开始／暂停")
  case .toggleLowPower: return String(localized:"切换低电量模式")
  case .popover: return String(localized:"显示菜单栏弹窗")
  case .settings: return String(localized:"打开设置")
  }
 }
 public static func stored(_ value: String?) -> Self { value.flatMap(Self.init(rawValue:)) ?? .popover }
}
public enum MenuBarChargeToggleResult: Equatable, Sendable { case pausedAtCurrent(Double), chargingToFull }
public enum MenuBarChargeToggleError: LocalizedError {
 case unavailablePercentage
 public var errorDescription: String? { String(localized:"无法读取有效电池百分比，未更改充电策略") }
}
public enum MenuBarChargeToggleRequest {
 public static func apply(phase: PolicyPhase, percent: Double, policy: inout ChargePolicy) throws -> MenuBarChargeToggleResult {
  let control = Float(percent)
  guard percent.isFinite, control.isFinite, (0...100).contains(control) else { throw MenuBarChargeToggleError.unavailablePercentage }
  let pausable = phase == .charging || phase == .topUp || (phase == .heatProtect && Float(policy.limit) == 100)
  if pausable && control >= 20 {
   try PauseChargeRequest.apply(percent: Double(control), policy: &policy)
   return .pausedAtCurrent(Double(control))
  }
  policy.limit = 100; policy.mode = .automatic; policy.pauseAtCurrent = nil; policy.departure = nil
  return .chargingToFull
 }
}
