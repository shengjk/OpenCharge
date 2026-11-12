import SwiftUI
import ChargeCore
import ChargeHardware

struct PowerConsumptionSnapshot {
 struct SampleAverage {
  let watts: Double
  let sampleCount: Int
  let coverageFraction: Double
 }
 struct Interval {
  let start: Date
  let end: Date
  let watts: Double
 }
 let start: Date
 let end: Date
 let intervals: [Interval]
 let average: SampleAverage?
 let currentWatts: Double?
 let currentMinutes: Double?
 let averageMinutes: Double?
 let averageDateRange: ClosedRange<Date>?

 var plotRange: ClosedRange<Double> {
  let values = intervals.map(\.watts) + [currentWatts, average?.watts].compactMap { $0 }
  guard let low = values.min(), let high = values.max() else { return 0...1 }
  let span = high - low
  let upper = span > 0 ? low + span * 1.2 : high + max(1, abs(high) * 0.2)
  if upper.isFinite && upper > low { return low...upper }
  return 0...max(1, high)
 }

 init(reading: BatteryReading?, history: [HistoryPoint], minutes: Int, end fallbackEnd: Date = Date()) {
  let end = reading?.date ?? fallbackEnd
  let start = end.addingTimeInterval(-60 * Double(minutes))
  self.end = end; self.start = start
  // Later readings replace earlier readings at an identical timestamp, including missing values.
  var byDate: [Date: PowerSample] = [:]
  let oldest = start.addingTimeInterval(-TelemetryMath.powerSampleMaxAgeSeconds)
  for point in history where point.date >= oldest && point.date <= end {
   byDate[point.date] = PowerSample(date: point.date, watts: point.systemWatts)
  }
  if let reading { byDate[end] = PowerSample(date: end, watts: reading.systemPowerW) }
  let points = byDate.values.sorted { $0.date < $1.date }
  intervals = points.indices.compactMap { index in
   let point = points[index]
   let next = index + 1 < points.count ? points[index + 1].date : end
   let right = min(next, point.date.addingTimeInterval(TelemetryMath.powerSampleMaxAgeSeconds))
   let left = max(start, point.date)
   guard let watts = point.watts, watts.isFinite, watts >= 0, left < right else { return nil }
   return Interval(start: left, end: right, watts: watts)
  }
  // The displayed average counts valid observations in the selected window.
  // Time coverage remains separate, with the same stale-gap rule as the graph.
  let coverage = TelemetryMath.weightedAverage(samples: points, endingAt: end, windowMinutes: Double(minutes))?.coverageFraction ?? 0
  let meanSamples = points.filter {
   guard $0.date >= start, $0.date <= end, let watts = $0.watts else { return false }
   return watts.isFinite && watts >= 0
  }
  let values = meanSamples.compactMap(\.watts)
  if let first = meanSamples.first, let last = meanSamples.last { averageDateRange = first.date...last.date }
  else { averageDateRange = nil }
  var mean = 0.0
  for (index, value) in values.enumerated() { mean += (value - mean) / Double(index + 1) }
  let average = values.isEmpty ? nil : SampleAverage(watts: mean, sampleCount: values.count, coverageFraction: coverage)
  self.average = average
  currentWatts = reading?.systemPowerW.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
  // Known model nominal voltage matches the pack's estimation profile. Explicit
  // design telemetry and measured terminal voltage remain distinct fallback sources.
  let energy = TelemetryMath.remainingEnergyWH(remainingCapacityMAH: reading?.remainingCapacityMAH,
   voltageMV: reading?.modelNominalVoltageMV ?? reading?.designVoltageMV ?? reading?.voltageMV)
  currentMinutes = TelemetryMath.remainingTimeMinutes(remainingEnergyWH: energy, dischargePowerW: currentWatts)
  averageMinutes = TelemetryMath.remainingTimeMinutes(remainingEnergyWH: energy, dischargePowerW: average?.watts)
 }
}

struct PowerConsumptionView: View {
 let reading: BatteryReading?
 let history: [HistoryPoint]
 @State private var minutes = 15

 var body: some View {
  let data = PowerConsumptionSnapshot(reading: reading, history: history, minutes: minutes)
  VStack(alignment: .leading, spacing: 8) {
   Picker(NSLocalizedString("功耗时间窗口", comment: ""), selection: $minutes) {
    ForEach([5, 15, 30], id: \.self) { value in
     Text(String.localizedStringWithFormat(NSLocalizedString("%lld 分钟", comment: ""), Int64(value))).tag(value)
    }
   }.pickerStyle(.segmented)
   if data.intervals.isEmpty {
    Text(NSLocalizedString("记录系统负载后，功耗曲线将在这里显示。", comment: "")).font(.caption).presentationSecondary()
   } else {
    graph(data)
   }
   valueRow(label: NSLocalizedString("当前系统负载", comment: ""), value: watts(data.currentWatts))
   valueRow(label: NSLocalizedString("按当前负载估算续航", comment: ""), value: duration(data.currentMinutes))
   if let average = data.average {
    Text(String.localizedStringWithFormat(NSLocalizedString("%lld 分钟平均：%@ · 数据覆盖 %@", comment: ""),
     Int64(minutes), watts(average.watts), String(format: "%.0f%%", average.coverageFraction * 100)))
     .font(.caption).presentationSecondary()
   }
   valueRow(label: NSLocalizedString("按平均负载估算续航", comment: ""), value: duration(data.averageMinutes))
   valueRow(label: DashboardSpecification.timeToEmpty.title, value: BatterySpecificationFormatter.value(.timeToEmpty, reading: reading))
   Text(NSLocalizedString("续航优先使用已知机型的标称电压；否则使用系统设计电压，最后回退到当前端电压。平均功耗按有效样本计算，覆盖率单独反映记录时长。", comment: ""))
    .font(.caption).presentationSecondary()
  }
 }

 private func graph(_ data: PowerConsumptionSnapshot) -> some View {
  let loads = data.intervals.map(\.watts)
  let range = data.plotRange
  let spanY = range.upperBound - range.lowerBound
  func y(_ watts: Double, height: CGFloat) -> CGFloat {
   CGFloat(1 - (watts - range.lowerBound) / spanY) * max(0, height - 2) + 1
  }
  return VStack(spacing: 3) {
   HStack(spacing: 6) {
    VStack {
     Text(watts(range.upperBound)); Spacer(); Text(watts(range.lowerBound))
    }.font(.caption2.monospacedDigit()).presentationSecondary()
    GeometryReader { geometry in
     ZStack(alignment: .topLeading) {
     Path { path in
      let span = data.end.timeIntervalSince(data.start)
      var previousEnd: Date?
      for interval in data.intervals {
       let positionY = y(interval.watts, height: geometry.size.height)
       let start = CGPoint(x: interval.start.timeIntervalSince(data.start) / span * geometry.size.width, y: positionY)
       if previousEnd == interval.start { path.addLine(to: start) }
       else { path.move(to: start) }
       previousEnd = interval.end
       path.addLine(to: CGPoint(x: interval.end.timeIntervalSince(data.start) / span * geometry.size.width, y: positionY))
      }
     }.stroke(PresentationPalette.mint, lineWidth: 2)
     if let average = data.average, let dates = data.averageDateRange {
      Path { path in
       let positionY = y(average.watts, height: geometry.size.height)
       let span = data.end.timeIntervalSince(data.start)
       let firstX = dates.lowerBound.timeIntervalSince(data.start) / span * geometry.size.width
       let lastX = dates.upperBound.timeIntervalSince(data.start) / span * geometry.size.width
       path.move(to: CGPoint(x: firstX, y: positionY))
       path.addLine(to: CGPoint(x: lastX, y: positionY))
      }.stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
     }
     }
    }
   }.frame(height: 90)
   HStack(spacing: 6) {
    Rectangle().fill(PresentationPalette.mint).frame(width: 18, height: 2)
    Text(NSLocalizedString("负载曲线", comment: ""))
    if data.average != nil {
     Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 18, y: 0)) }
      .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).frame(width: 18, height: 2)
     Text(NSLocalizedString("窗口平均", comment: ""))
    }
    Spacer()
   }.font(.caption2).presentationSecondary()
   HStack {
    Text(data.start, style: .time); Spacer(); Text(data.end, style: .time)
   }.font(.caption2.monospacedDigit()).presentationSecondary()
  }.accessibilityElement(children: .ignore)
   .accessibilityLabel(Text(NSLocalizedString("系统负载曲线", comment: "")))
   .accessibilityValue(Text(String.localizedStringWithFormat(NSLocalizedString("记录范围 %@ 至 %@；窗口平均 %@", comment: ""),
    watts(loads.min()), watts(loads.max()), watts(data.average?.watts))))
 }

 private func valueRow(label: String, value: String) -> some View {
  HStack {
   Text(label); Spacer()
   Text(value).font(.caption.monospacedDigit())
  }.font(.caption)
 }

 private func watts(_ value: Double?) -> String { value.map { String(format: "%.2f W", $0) } ?? "—" }

 private func duration(_ value: Double?) -> String {
  guard let duration = PowerRuntimeDuration(minutes: value) else { return "—" }
  return String.localizedStringWithFormat(NSLocalizedString("%lld 小时 %lld 分钟", comment: ""), duration.hours, duration.minutes)
 }
}

struct PowerRuntimeDuration {
 let hours: Int64
 let minutes: Int64
 init?(minutes value: Double?) {
  guard let value, value.isFinite, value >= 0, value < Double(Int64.max) else { return nil }
  let wholeMinutes = Int64(value)
  hours = wholeMinutes / 60; minutes = wholeMinutes % 60
 }
}
