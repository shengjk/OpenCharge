import Foundation

public enum PauseChargeError: LocalizedError {
 case unavailablePercentage
 public var errorDescription: String? { String(localized:"当前电量须为 20–100%，才能按当前电量暂停充电") }
}
public enum PauseChargeRequest {
 public static func apply(percent: Double, policy: inout ChargePolicy) throws {
  guard percent.isFinite, (20...100).contains(percent) else { throw PauseChargeError.unavailablePercentage }
  policy.limit = Double(Float(percent)); policy.mode = .paused; policy.pauseAtCurrent = true
  policy.departure = nil
 }
}
