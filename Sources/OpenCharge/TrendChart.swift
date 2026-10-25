import SwiftUI
import Charts

struct TrendChart: View {
 var points: [HistoryPoint]
 var body: some View {
  if points.isEmpty {
   return AnyView(Text(NSLocalizedString("开始记录后，电量趋势将在这里显示。", comment: "")).presentationSecondary().frame(maxWidth: .infinity, maxHeight: .infinity))
  }
  if #available(macOS 13, *) { return AnyView(NativeTrendChart(points: points)) }
  return AnyView(LegacyTrendChart(samples: points.map { TrendSample(date: $0.date, percent: $0.percent, limit: $0.limit) }))
 }
}

@available(macOS 13, *)
private struct NativeTrendChart: View {
 var points: [HistoryPoint]
 var body: some View { Chart(points) { p in AreaMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("电量", comment: ""), p.percent)).foregroundStyle(PresentationPalette.mint.opacity(0.12)); LineMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("电量", comment: ""), p.percent), series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("电量", comment: ""))).foregroundStyle(PresentationPalette.mint).interpolationMethod(.monotone); if let limit = p.limit { LineMark(x: .value(NSLocalizedString("时间", comment: ""), p.date), y: .value(NSLocalizedString("上限", comment: ""), limit), series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("上限", comment: ""))).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])) } }.chartYScale(domain: 0...100) }
}
