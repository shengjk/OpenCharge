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
 var body: some View { if points.isEmpty { Text(String(localized:"开始记录后，电量趋势将在这里显示。")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) } else { Chart(points) { p in AreaMark(x: .value(String(localized:"时间"), p.date), y: .value(String(localized:"电量"), p.percent)).foregroundStyle(.mint.opacity(0.12)); LineMark(x: .value(String(localized:"时间"), p.date), y: .value(String(localized:"电量"), p.percent), series: .value(String(localized:"类型"), String(localized:"电量"))).foregroundStyle(.mint).interpolationMethod(.monotone); if let limit = p.limit { LineMark(x: .value(String(localized:"时间"), p.date), y: .value(String(localized:"上限"), limit), series: .value(String(localized:"类型"), String(localized:"上限"))).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])) } }.chartYScale(domain: 0...100) } }
}
struct HistoryView: View {
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  Card(String(localized:"电池趋势 · 最多 7 天")) { TrendChart(points: m.history).frame(height: 260); HStack { Text(String(localized:"\(m.history.count) 个本地采样")).foregroundStyle(.secondary); Spacer(); Button(String(localized:"导出 CSV")) { m.export() }; Button(String(localized:"清空记录"), role: .destructive) { m.clearHistory() } } }
  Card(String(localized:"决策日志 · 新功能")) { ForEach(Array(m.history.suffix(30).reversed())) { point in HStack { Text(point.date, style: .time).monospacedDigit().foregroundStyle(.secondary); Text(point.reason); Spacer(); Text("\(Int(point.percent))%").monospacedDigit() }.font(.caption) } }
 }
}
