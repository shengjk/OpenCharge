import SwiftUI
import ChargeHardware

enum BatteryStatistic: String, CaseIterable, Identifiable {
 case temperature, health, fullCapacity, cycles
 var id: Self { self }
 var title: String {
  switch self {
  case .temperature: return NSLocalizedString("电池温度", comment: "")
  case .health: return NSLocalizedString("容量健康比例", comment: "")
  case .fullCapacity: return NSLocalizedString("满充容量", comment: "")
  case .cycles: return NSLocalizedString("循环次数", comment: "")
  }
 }
 func value(_ point: HistoryPoint) -> Double? {
  let value: Double?
  let range: ClosedRange<Double>
  switch self {
  case .temperature: value = point.temperature; range = -40...100
  case .health: value = point.health; range = 0...200
  case .fullCapacity: value = point.fullCapacityMAH; range = 1...100000
  case .cycles: value = point.cycles.map(Double.init); range = 0...1000000
  }
  return value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
 }
 func formatted(_ value: Double) -> String {
  switch self {
  case .temperature: return String(format: "%.1f°C", value)
  case .health: return String(format: "%.1f%%", value)
  case .fullCapacity: return String(format: "%.0f mAh", value)
  case .cycles: return String(format: "%.0f", value)
  }
 }
}

struct BatteryStatisticPlot {
 struct Sample {
  let date: Date
  let value: Double
  let startsSegment: Bool
 }
 let start: Date
 let end: Date
 let samples: [Sample]
 let minimum: Double?
 let maximum: Double?
 let lower: Double
 let upper: Double

 init(points: [HistoryPoint], metric: BatteryStatistic, hours: Int, end: Date) {
  self.end = end; start = end.addingTimeInterval(-Double(hours) * 3600)
  var byDate: [Date: HistoryPoint] = [:]
  for point in points where point.date >= start && point.date <= end { byDate[point.date] = point }
  let ordered = byDate.values.sorted { $0.date < $1.date }
  var samples: [Sample] = []
  var previous: Date?
  for point in ordered {
   guard let value = metric.value(point) else { previous = nil; continue }
   let startsSegment = previous.map { point.date.timeIntervalSince($0) > TelemetryMath.powerSampleMaxAgeSeconds } ?? true
   samples.append(Sample(date: point.date, value: value, startsSegment: startsSegment))
   previous = point.date
  }
  self.samples = samples
  minimum = samples.map(\.value).min(); maximum = samples.map(\.value).max()
  let padding = max(metric == .cycles || metric == .fullCapacity ? 1 : 0.5, ((maximum ?? 0) - (minimum ?? 0)) * 0.1)
  lower = max(metric == .temperature ? -40 : 0, (minimum ?? 0) - padding)
  upper = max(lower + 1, (maximum ?? 0) + padding)
 }
}

struct BatteryStatisticChart: View {
 let metric: BatteryStatistic
 let points: [HistoryPoint]
 @State private var hours = 24

 var body: some View {
  let data = BatteryStatisticPlot(points: points, metric: metric, hours: hours,
   end: points.lazy.map(\.date).filter { $0.timeIntervalSinceReferenceDate.isFinite }.max() ?? Date())
  VStack(alignment: .leading, spacing: 8) {
   Picker(NSLocalizedString("统计时间窗口", comment: ""), selection: $hours) {
    Text(NSLocalizedString("1 小时", comment: "")).tag(1)
    Text(NSLocalizedString("24 小时", comment: "")).tag(24)
    Text(NSLocalizedString("7 天", comment: "")).tag(168)
   }.pickerStyle(.segmented)
   if let latest = data.samples.last, let minimum = data.minimum, let maximum = data.maximum {
    plot(data)
    HStack {
     Text(String.localizedStringWithFormat(NSLocalizedString("最新 %@", comment: ""), metric.formatted(latest.value)))
     Spacer()
     Text(String.localizedStringWithFormat(NSLocalizedString("范围 %@ 至 %@", comment: ""),
      metric.formatted(minimum), metric.formatted(maximum)))
    }.font(.caption.monospacedDigit())
   } else {
    Text(NSLocalizedString("此时间段尚无该指标的记录", comment: "")).font(.caption).presentationSecondary()
   }
  }
 }

 private func plot(_ data: BatteryStatisticPlot) -> some View {
  VStack(spacing: 3) {
   HStack(spacing: 6) {
    VStack { Text(metric.formatted(data.upper)); Spacer(); Text(metric.formatted(data.lower)) }
     .font(.caption2.monospacedDigit()).presentationSecondary()
    GeometryReader { geometry in
     let span = data.end.timeIntervalSince(data.start)
     let range = data.upper - data.lower
     Path { path in
      for sample in data.samples {
       let position = CGPoint(x: sample.date.timeIntervalSince(data.start) / span * geometry.size.width,
        y: (1 - (sample.value - data.lower) / range) * max(0, geometry.size.height - 4) + 2)
       if sample.startsSegment { path.move(to: position) }
       else { path.addLine(to: position) }
       if sample.startsSegment { path.addEllipse(in: CGRect(x: position.x - 1, y: position.y - 1, width: 2, height: 2)) }
       path.move(to: position)
      }
     }.stroke(PresentationPalette.mint, lineWidth: 1.5)
    }
   }.frame(height: 120)
   HStack { Text(data.start, style: .date); Text(data.start, style: .time); Spacer(); Text(data.end, style: .date); Text(data.end, style: .time) }
    .font(.caption2.monospacedDigit()).presentationSecondary()
  }.accessibilityElement(children: .ignore).accessibilityLabel(Text(metric.title))
   .accessibilityValue(Text(String.localizedStringWithFormat(NSLocalizedString("范围 %@ 至 %@", comment: ""),
    metric.formatted(data.minimum ?? 0), metric.formatted(data.maximum ?? 0))))
 }
}
