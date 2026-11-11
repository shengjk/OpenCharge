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
  let values = points.filter { $0.date >= start && $0.date <= end }.compactMap(\.watts)
   .filter { $0.isFinite && $0 >= 0 }
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
  let peak = max(1, (loads.max() ?? 0).rounded(.up))
  return VStack(spacing: 3) {
   HStack(spacing: 6) {
    VStack {
     Text(watts(peak)); Spacer(); Text(watts(0))
    }.font(.caption2.monospacedDigit()).presentationSecondary()
    GeometryReader { geometry in
     Path { path in
      let span = data.end.timeIntervalSince(data.start)
      var previousEnd: Date?
      for interval in data.intervals {
       let y = (1 - interval.watts / peak) * max(0, geometry.size.height - 2) + 1
       let start = CGPoint(x: interval.start.timeIntervalSince(data.start) / span * geometry.size.width, y: y)
       if previousEnd == interval.start { path.addLine(to: start) }
       else { path.move(to: start) }
       previousEnd = interval.end
       path.addLine(to: CGPoint(x: interval.end.timeIntervalSince(data.start) / span * geometry.size.width, y: y))
      }
     }.stroke(PresentationPalette.mint, lineWidth: 2)
    }
   }.frame(height: 90)
   HStack {
    Text(data.start, style: .time); Spacer(); Text(data.end, style: .time)
   }.font(.caption2.monospacedDigit()).presentationSecondary()
  }.accessibilityElement(children: .ignore)
   .accessibilityLabel(Text(NSLocalizedString("系统负载曲线", comment: "")))
   .accessibilityValue(Text(String.localizedStringWithFormat(NSLocalizedString("记录范围 %@ 至 %@", comment: ""),
    watts(loads.min()), watts(loads.max()))))
 }

 private func valueRow(label: String, value: String) -> some View {
  HStack {
   Text(label); Spacer()
   Text(value).font(.caption.monospacedDigit())
  }.font(.caption)
 }

 private func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "—" }

 private func duration(_ value: Double?) -> String {
  guard let value else { return "—" }
  if value > 1440 { return NSLocalizedString("超过 24 小时", comment: "") }
  return String.localizedStringWithFormat(NSLocalizedString("%lld 分钟", comment: ""), Int64(value.rounded()))
 }
}
