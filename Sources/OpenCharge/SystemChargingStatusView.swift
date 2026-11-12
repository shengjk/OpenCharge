import SwiftUI
import AppKit
import Combine
import ChargeHardware

enum OptimizedChargingEngagement: Equatable {
 case engaged, notEngaged, unavailable, waitingForFreshReading
 init(_ reported: Bool?) {
  switch reported { case .some(true): self = .engaged; case .some(false): self = .notEngaged; case .none: self = .unavailable }
 }
 init(reading: BatteryReading?, at date: Date) {
  guard let reading else { self = .unavailable; return }
  let age = date.timeIntervalSince(reading.date)
  guard age.isFinite, (0...30).contains(age) else { self = .waitingForFreshReading; return }
  self.init(reading.optimizedChargingEngaged)
 }
 var title: String {
  switch self {
  case .engaged: return NSLocalizedString("当前介入", comment: "")
  case .notEngaged: return NSLocalizedString("当前未介入", comment: "")
  case .unavailable: return NSLocalizedString("系统未提供", comment: "")
  case .waitingForFreshReading: return NSLocalizedString("等待读数更新", comment: "")
  }
 }
}

struct SystemChargingStatusView: View {
 let reading: BatteryReading?
 @State private var openFailed = false
 @State private var now = Date()
 private var engagement: OptimizedChargingEngagement { OptimizedChargingEngagement(reading: reading, at: max(now, Date())) }
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   HStack {
    Text(NSLocalizedString("系统优化充电", comment: "")); Spacer()
    Text(engagement.title).font(.callout.monospacedDigit())
     .accessibilityIdentifier("optimized-charging-engagement")
   }.accessibilityElement(children: .combine)
   if engagement == .engaged {
    Text(NSLocalizedString("macOS 报告优化充电正在介入，可能按使用习惯延后充电。", comment: ""))
     .font(.caption).presentationOrange()
   }
   Text(NSLocalizedString("此处显示系统当前报告的介入状态；优化充电开关和系统充电上限请在电池设置中确认。", comment: ""))
    .font(.caption).presentationSecondary()
   HStack {
    Button(NSLocalizedString("打开电池设置", comment: "")) {
     if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
      openFailed = !NSWorkspace.shared.open(url)
     }
    }
    Link(NSLocalizedString("Apple 充电设置说明", comment: ""), destination: URL(string: "https://support.apple.com/102338")!)
   }
   if openFailed {
    Text(NSLocalizedString("请从 Apple 菜单手动打开系统电池设置。", comment: "")).font(.caption).presentationOrange()
   }
  }.onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now = $0 }
 }
}
