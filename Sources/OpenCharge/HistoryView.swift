import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct TrendChart: View {
 var points: [HistoryPoint]
 var body: some View { if points.isEmpty { Text(NSLocalizedString("开始记录后，电量趋势将在这里显示。", comment: "")).presentationSecondary().frame(maxWidth: .infinity, maxHeight: .infinity) } else { Chart(points) { p in AreaMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("电量", comment: ""), p.percent)).foregroundStyle(PresentationPalette.mint.opacity(0.12)); LineMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("电量", comment: ""), p.percent), series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("电量", comment: ""))).foregroundStyle(PresentationPalette.mint).interpolationMethod(.monotone); if let limit = p.limit { LineMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("上限", comment: ""), limit), series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("上限", comment: ""))).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])) } }.chartYScale(domain: 0...100) } }
}
struct HistoryView: View {
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  Card(NSLocalizedString("电池趋势 · 最多 7 天", comment: "")) { TrendChart(points: m.history).frame(height: 260); HStack { Text(String.localizedStringWithFormat(NSLocalizedString("%lld 个本地采样", comment: ""), Int64(m.history.count))).presentationSecondary(); Spacer(); Button(NSLocalizedString("导出 CSV", comment: "")) { m.export() }; DestructiveButton(NSLocalizedString("清空记录", comment: "")) { m.clearHistory() } } }
  Card(NSLocalizedString("决策日志 · 新功能", comment: "")) { ForEach(Array(m.history.suffix(30).reversed())) { point in HStack { Text(point.date, style: .time).font(.caption.monospacedDigit()).presentationSecondary(); Text(point.reason); Spacer(); Text("\(Int(point.percent))%").font(.caption.monospacedDigit()) }.font(.caption) } }
 }
}
