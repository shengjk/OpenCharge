import SwiftUI
import ChargeHardware

enum BatteryStatistic: String, CaseIterable, Identifiable, Sendable {
 case temperature, health, fullCapacity, cycles
 var id: Self { self }
 var supportsArchive: Bool { self != .temperature }
 var defaultHours: Int { supportsArchive ? BatteryStatisticArchive.maximumQueryHours : 24 }
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

 var plotDates: ClosedRange<Date> {
  guard let first = samples.first?.date, let last = samples.last?.date else { return start...end }
  return first == last ? first.addingTimeInterval(-30)...last.addingTimeInterval(30) : first...last
 }

 init(points: [HistoryPoint], metric: BatteryStatistic, hours: Int, end: Date, archived: [BatteryStatisticRecord] = []) {
  self.end = end; start = end.addingTimeInterval(-Double(hours) * 3600)
  var byDate: [Date: Double?] = [:]
  if metric.supportsArchive {
   for point in archived where point.date >= start && point.date <= end {
    byDate.updateValue(point.value(for: metric), forKey: point.date)
   }
  }
  for point in points where point.date >= start && point.date <= end {
   byDate.updateValue(metric.value(point), forKey: point.date)
  }
  let ordered = byDate.sorted { $0.key < $1.key }
  var samples: [Sample] = []
  var previous: Date?
  for point in ordered {
   guard let value = point.value else { previous = nil; continue }
   let startsSegment = previous.map { metric == .temperature && point.key.timeIntervalSince($0) > TelemetryMath.powerSampleMaxAgeSeconds } ?? true
   samples.append(Sample(date: point.key, value: value, startsSegment: startsSegment))
   previous = point.key
  }
  self.samples = samples
  minimum = samples.map(\.value).min(); maximum = samples.map(\.value).max()
  let range = GraphValueRange.range(samples.map(\.value))
  lower = range.lowerBound; upper = range.upperBound
 }
}

@MainActor struct BatteryStatisticChart: View {
 let metric: BatteryStatistic
 let points: [HistoryPoint]
 let archive: BatteryStatisticArchive?
 let revision: Int
 let active: Bool
 let endingAt: Date
 let archiveWriteError: String?
 @State private var hours: Int
 @StateObject private var archived: BatteryStatisticArchiveLoader

 init(metric: BatteryStatistic, points: [HistoryPoint], archive: BatteryStatisticArchive? = nil,
      revision: Int = 0, active: Bool = true, endingAt: Date? = nil, archiveWriteError: String? = nil, archiveLoader: BatteryStatisticArchiveLoader? = nil) {
  self.metric = metric; self.points = points; self.archive = archive
  self.revision = revision; self.active = active; self.archiveWriteError = archiveWriteError
  self.endingAt = endingAt ?? points.lazy.map(\.date).filter { $0.timeIntervalSinceReferenceDate.isFinite }.max() ?? Date()
  _hours = State(initialValue: metric.defaultHours)
  _archived = StateObject(wrappedValue: archiveLoader ?? BatteryStatisticArchiveLoader())
 }
 private var end: Date { endingAt }
 private var request: BatteryStatisticArchiveRequest {
  BatteryStatisticArchiveRequest(url: archive?.url, hours: hours, revision: revision, active: active && metric.supportsArchive, metric: metric, endingAt: end)
 }
 private func reloadArchive() { archived.load(archive: archive, hours: hours, endingAt: end, active: request.active, metric: metric) }


 var body: some View {
  let data = BatteryStatisticPlot(points: points, metric: metric, hours: hours,
   end: end, archived: archived.records)
  VStack(alignment: .leading, spacing: 8) {
   Picker(NSLocalizedString("统计时间窗口", comment: ""), selection: $hours) {
    Text(NSLocalizedString("1 小时", comment: "")).tag(1)
    Text(NSLocalizedString("24 小时", comment: "")).tag(24)
    Text(NSLocalizedString("7 天", comment: "")).tag(168)
    if metric.supportsArchive { Text(NSLocalizedString("360 天", comment: "")).tag(BatteryStatisticArchive.maximumQueryHours) }
   }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(Text(NSLocalizedString("统计时间窗口", comment: "")))
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
   if archived.loading {
    HStack(spacing: 6) { ProgressView().scaleEffect(0.6).frame(width: 12, height: 12); Text(NSLocalizedString("正在读取长期记录…", comment: "")) }
     .font(.caption).presentationSecondary()
   }
   if let message = archived.error ?? archiveWriteError {
    HStack {
     Text(message).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
     if archived.error != nil { Button(NSLocalizedString("重试", comment: "")) { reloadArchive() } }
    }
   }
  }.onAppear { reloadArchive() }
   .onChange(of: request) { _ in reloadArchive() }
   .onChange(of: metric) { hours = $0.defaultHours }
   .onDisappear { archived.cancel() }
 }

 private func plot(_ data: BatteryStatisticPlot) -> some View {
  VStack(spacing: 3) {
   HStack(spacing: 6) {
    VStack { Text(metric.formatted(data.upper)); Spacer(); Text(metric.formatted(data.lower)) }
     .font(.caption2.monospacedDigit()).presentationSecondary()
    GeometryReader { geometry in
     let span = data.plotDates.upperBound.timeIntervalSince(data.plotDates.lowerBound)
     let range = data.upper - data.lower
     let positions = data.samples.map { sample in
      CGPoint(x: sample.date.timeIntervalSince(data.plotDates.lowerBound) / span * geometry.size.width,
       y: (1 - (sample.value - data.lower) / range) * max(0, geometry.size.height - 4) + 2)
     }
     ZStack(alignment: .topLeading) {
      Path { path in
       for index in data.samples.indices {
        let sample = data.samples[index], position = positions[index]
        if sample.startsSegment { path.move(to: position) }
        else { path.addLine(to: position) }
        if sample.startsSegment { path.addEllipse(in: CGRect(x: position.x - 1, y: position.y - 1, width: 2, height: 2)) }
        path.move(to: position)
       }
      }.stroke(PresentationPalette.mint, lineWidth: 1.5)
      GraphInspectionOverlay(samples: data.samples.indices.map { index in
       GraphInspectionSample(date: data.samples[index].date, position: positions[index],
        value: metric.formatted(data.samples[index].value), secondary: nil)
      }, size: geometry.size)
     }
    }
   }.frame(height: 120)
   HStack { Text(data.plotDates.lowerBound, style: .date); Text(data.plotDates.lowerBound, style: .time); Spacer(); Text(data.plotDates.upperBound, style: .date); Text(data.plotDates.upperBound, style: .time) }
    .font(.caption2.monospacedDigit()).presentationSecondary()
  }.accessibilityElement(children: .ignore).accessibilityLabel(Text(metric.title))
   .accessibilityValue(Text(String.localizedStringWithFormat(NSLocalizedString("范围 %@ 至 %@", comment: ""),
    metric.formatted(data.minimum ?? 0), metric.formatted(data.maximum ?? 0))))
 }
}
