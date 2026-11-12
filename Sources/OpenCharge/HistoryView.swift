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
 @State private var metric = BatteryStatistic.temperature
 var body: some View {
  Card(NSLocalizedString("电池趋势 · 最多 7 天", comment: "")) { TrendChart(points: m.history).frame(height: 260); HStack { Text(String.localizedStringWithFormat(NSLocalizedString("%lld 个本地采样", comment: ""), Int64(m.history.count))).presentationSecondary(); Spacer(); Button(NSLocalizedString("导出 CSV", comment: "")) { m.export() }; DestructiveButton(NSLocalizedString("清空记录", comment: "")) { m.clearHistory() } } }
  Card(NSLocalizedString("电池统计", comment: "")) {
   Picker(NSLocalizedString("统计指标", comment: ""), selection: $metric) {
    ForEach(BatteryStatistic.allCases) { item in Text(item.title).tag(item) }
   }.pickerStyle(.segmented)
   BatteryStatisticChart(metric: metric, points: m.history, archive: m.statisticArchive,
    revision: m.statisticRevision, active: !m.dashboard.paused, endingAt: m.reading?.date ?? Date(), archiveWriteError: m.statisticArchiveError).id(metric)
   Text(NSLocalizedString("容量与循环次数支持查询最近 360 天的已有记录；清空记录会同时删除长期统计。", comment: ""))
    .font(.caption).presentationSecondary().fixedSize(horizontal: false, vertical: true)
  }
  Card(NSLocalizedString("决策日志 · 新功能", comment: "")) { ForEach(Array(m.history.suffix(30).reversed())) { point in HStack { Text(point.date, style: .time).font(.caption.monospacedDigit()).presentationSecondary(); Text(point.reason); Spacer(); Text("\(Int(point.percent))%").font(.caption.monospacedDigit()) }.font(.caption) } }
 }
}
