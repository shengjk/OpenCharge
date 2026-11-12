import SwiftUI
import Charts

enum TrendWindow {
 static func day(_ points: [HistoryPoint], endingAt end: Date) -> [HistoryPoint] {
  let start = end.addingTimeInterval(-86400)
  return points.filter { $0.date >= start && $0.date <= end && $0.date.timeIntervalSinceReferenceDate.isFinite }
 }
}

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
 var body: some View {
  let plot = TrendPlot(samples: points.map { TrendSample(date: $0.date, percent: $0.percent, limit: $0.limit) }, size: CGSize(width: 1, height: 1))
  Chart(Array(plot.samples.enumerated()), id: \.offset) { entry in
   let sample = entry.element
   AreaMark(x: .value(NSLocalizedString("时间", comment: ""), sample.date),
    y: .value(NSLocalizedString("电量", comment: ""), sample.percent))
    .foregroundStyle(PresentationPalette.mint.opacity(0.12))
   LineMark(x: .value(NSLocalizedString("时间", comment: ""), sample.date),
    y: .value(NSLocalizedString("电量", comment: ""), sample.percent),
    series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("电量", comment: "")))
    .foregroundStyle(PresentationPalette.mint).interpolationMethod(.linear)
   if let limit = sample.limit, limit.isFinite {
    LineMark(x: .value(NSLocalizedString("时间", comment: ""), sample.date),
     y: .value(NSLocalizedString("上限", comment: ""), limit),
     series: .value(NSLocalizedString("类型", comment: ""), NSLocalizedString("上限", comment: "")))
     .foregroundStyle(.orange).interpolationMethod(.stepEnd).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
   }
  }.chartYScale(domain: 0...100).chartXScale(domain: plot.domain)
   .chartXAxis {
    AxisMarks(values: plot.tickDates) { value in
     AxisGridLine(); AxisTick()
     AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top) {
      if let date = value.as(Date.self) { Text(plot.tickLabel(date)) }
     }
    }
   }
   .chartOverlay { proxy in
    GeometryReader { geometry in
     let frame = geometry[proxy.plotAreaFrame]
     let samples = plot.samples.compactMap { sample -> GraphInspectionSample? in
      guard let x = proxy.position(forX: sample.date),
            let y = proxy.position(forY: sample.percent) else { return nil }
      return GraphInspectionSample(date: sample.date, position: CGPoint(x: x, y: y),
       value: TrendPlot.accessiblePercent(sample.percent),
       secondary: sample.limit.flatMap { value in
        value.isFinite ? NSLocalizedString("上限", comment: "") + " " + TrendPlot.accessiblePercent(value) : nil
       })
     }
     GraphInspectionOverlay(samples: samples, size: frame.size).offset(x: frame.minX, y: frame.minY)
    }
   }
 }
}
