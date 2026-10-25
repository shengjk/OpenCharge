import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct HistoryView: View {
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  Card(NSLocalizedString("电池趋势 · 最多 7 天", comment: "")) { TrendChart(points: m.history).frame(height: 260); HStack { Text(String.localizedStringWithFormat(NSLocalizedString("%lld 个本地采样", comment: ""), Int64(m.history.count))).presentationSecondary(); Spacer(); Button(NSLocalizedString("导出 CSV", comment: "")) { m.export() }; DestructiveButton(NSLocalizedString("清空记录", comment: "")) { m.clearHistory() } } }
  Card(NSLocalizedString("决策日志 · 新功能", comment: "")) { ForEach(Array(m.history.suffix(30).reversed())) { point in HStack { Text(point.date, style: .time).font(.caption.monospacedDigit()).presentationSecondary(); Text(point.reason); Spacer(); Text("\(Int(point.percent))%").font(.caption.monospacedDigit()) }.font(.caption) } }
 }
}
