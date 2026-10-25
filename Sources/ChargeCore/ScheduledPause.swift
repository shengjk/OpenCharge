import Foundation

public struct ScheduledPauseContext: Sendable {
 public var phase: PolicyPhase?
 public var percent: Double?
 public var calibrationInterrupted: Bool
 public init(phase: PolicyPhase?, percent: Double?, calibrationInterrupted: Bool = false) {
  self.phase = phase; self.percent = percent; self.calibrationInterrupted = calibrationInterrupted
 }
}
public enum ScheduleApplicationResult: Equatable, Sendable {
 case updated, pausedAtCurrent(Double), skippedPause(ScheduledPauseSkip)
 public var historyMessage: String {
  switch self {
  case .updated: return NSLocalizedString("策略已更新", comment: "")
  case .pausedAtCurrent(let percent): return String(format: NSLocalizedString("已接受按当前电量暂停策略：上限 %.2f%%（未确认硬件停充）", comment: ""), percent)
  case .skippedPause(let reason): return NSLocalizedString("已跳过暂停：", comment: "") + reason.historyMessage
  }
 }
}
public enum ScheduledPauseSkip: Equatable, Sendable {
 case unavailableContext, interruptedCalibration, ineligiblePhase, unavailablePercentage, belowMinimum
 public var historyMessage: String {
  switch self {
  case .unavailableContext: return NSLocalizedString("缺少当前状态与控制电量", comment: "")
  case .interruptedCalibration: return NSLocalizedString("校准已中断，需明确继续或取消", comment: "")
  case .ineligiblePhase: return NSLocalizedString("当前策略状态不适用", comment: "")
  case .unavailablePercentage: return NSLocalizedString("选定控制电量不可读或无效", comment: "")
  case .belowMinimum: return NSLocalizedString("控制电量低于 20%", comment: "")
  }
 }
}
public enum ScheduledPauseRequest {
 public static func apply(context: ScheduledPauseContext?, policy: inout ChargePolicy) -> ScheduleApplicationResult {
  guard let context else { return .skippedPause(.unavailableContext) }
  guard !context.calibrationInterrupted else { return .skippedPause(.interruptedCalibration) }
  guard let percent = context.percent, percent.isFinite else { return .skippedPause(.unavailablePercentage) }
  let control = Float(percent)
  guard control.isFinite, (0...100).contains(control) else { return .skippedPause(.unavailablePercentage) }
  let eligible: Bool
  switch context.phase {
  case .charging, .topUp, .discharging, .calibration: eligible = true
  case .heatProtect: eligible = Float(policy.limit) == 100
  default: eligible = false
  }
  guard eligible else { return .skippedPause(.ineligiblePhase) }
  guard control >= 20 else { return .skippedPause(.belowMinimum) }
  // The scheduling interface consumes single-precision control telemetry.
  do { try PauseChargeRequest.apply(percent: Double(control), policy: &policy) }
  catch { return .skippedPause(.unavailablePercentage) }
  return .pausedAtCurrent(Double(control))
 }
}

public extension ChargeSchedule {
 func apply(policy: inout ChargePolicy, pauseContext: ScheduledPauseContext? = nil) -> ScheduleApplicationResult {
  if action == .pause { return ScheduledPauseRequest.apply(context: pauseContext, policy: &policy) }
  switch action {
  case .limit: policy.limit = value; policy.mode = .automatic
  case .topUp: policy.mode = .topUp
  case .discharge: policy.limit = value; policy.mode = .discharge
  case .calibrate: policy.mode = .calibration
  case .automatic: policy.mode = .automatic
  case .lowPowerOn: policy.lowPowerMode = true
  case .lowPowerOff: policy.lowPowerMode = false
  case .pause: break
  }
  switch action {
  case .limit, .topUp, .discharge, .calibrate, .automatic: policy.pauseAtCurrent = nil
  default: break
  }
  policy.normalize()
  return .updated
 }
}
