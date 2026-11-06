import SwiftUI
import ChargeCore

struct CalibrationSummary: Equatable {
 var stage: CalibrationStage = .idle
 var active = false
 var interrupted = false
 var adapterAvailable = false
 var canStart = false
 var remainingHoldMinutes: Int?
 var lastCompleted: Date?

 var showsInPopover: Bool { active || interrupted }
 var status: String {
  if interrupted { return NSLocalizedString("上次校准中断", comment: "") }
  if active && !adapterAvailable { return NSLocalizedString("校准：等待接电", comment: "") }
  return stage.displayName
 }
}

struct CalibrationSummaryView: View {
 let model: ChargeModel
 let summary: CalibrationSummary
 var compact = false

 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text(summary.status).font(.callout)
   if let minutes = summary.remainingHoldMinutes {
    Text(String.localizedStringWithFormat(NSLocalizedString("满电保持剩余 %lld 分钟", comment: ""), Int64(minutes)))
     .font(.caption.monospacedDigit()).presentationSecondary()
   }
   if !compact {
    HStack(alignment: .top, spacing: 12) {
     ForEach([CalibrationStage.filling, .draining, .refilling, .holding, .returning], id: \.self) { stage in
      Text(stage.displayName)
       .font(.caption.weight(summary.stage == stage ? .bold : .regular))
       .frame(maxWidth: .infinity, alignment: .leading)
     }
    }
    if let date = summary.lastCompleted {
     Text(String.localizedStringWithFormat(NSLocalizedString("上次完成：%@", comment: ""), DateDisplay.string(date)))
      .font(.caption).presentationSecondary()
    }
   }
   if summary.interrupted {
    HStack {
     Button(NSLocalizedString("继续", comment: "")) { model.resumeCalibration() }
     Button(NSLocalizedString("取消校准", comment: "")) { model.resolveInterruptedCalibration(resume: false) }
    }
   } else if summary.active {
    Button(NSLocalizedString("停止校准", comment: "")) {
     if model.config.policy.mode == .calibration, !model.calibrationPending { model.changeMode(.automatic) }
    }
   } else {
    Button(NSLocalizedString("开始校准", comment: "")) {
     if model.config.policy.mode != .calibration { model.changeMode(.calibration) }
    }.disabled(!summary.canStart)
   }
  }
 }
}
