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
 let records: [PowerSample]

 var plotDates: ClosedRange<Date> {
  guard let first = records.first?.date, let last = records.last?.date else { return start...end }
  return first == last ? first.addingTimeInterval(-30)...last.addingTimeInterval(30) : first...last
 }

 // Compression can leave a long plateau. Check raw coverage rather than
 // treating every long interval between query records as missing telemetry.
 func connects(_ first: Date, _ last: Date) -> Bool {
  guard first < last else { return first == last }
  var covered = first
  for interval in intervals where interval.end > first && interval.start < last {
   guard interval.start <= covered else { return false }
   covered = max(covered, interval.end)
   if covered >= last { return true }
  }
  return false
 }
 let average: SampleAverage?
 let currentWatts: Double?
 let currentMinutes: Double?
 let averageMinutes: Double?
 let averageDateRange: ClosedRange<Date>?

 func selectedWatts(_ mode: PowerCalculationMode) -> Double? { mode == .average ? average?.watts : currentWatts }
 func selectedMinutes(_ mode: PowerCalculationMode) -> Double? { mode == .average ? averageMinutes : currentMinutes }

 var plotRange: ClosedRange<Double> { GraphValueRange.range(records.compactMap(\.watts)) }

 init(reading: BatteryReading?, history: [HistoryPoint], minutes: Int, end: Date) {
  let start = end.addingTimeInterval(-60 * Double(minutes))
  self.end = end; self.start = start
  // Later readings replace earlier readings at an identical timestamp, including missing values.
  var byDate: [Date: PowerSample] = [:]
  let oldest = start.addingTimeInterval(-TelemetryMath.powerSampleMaxAgeSeconds)
  for point in history where point.date >= oldest && point.date <= end {
   byDate[point.date] = PowerSample(date: point.date, watts: point.systemWatts)
  }
  // Display polling is independent of recording. Only persisted observations
  // contribute to the curve, its mean and coverage; live power drives Instant.
  let points = byDate.values.sorted { $0.date < $1.date }
  intervals = points.indices.compactMap { index in
   let point = points[index]
   let next = index + 1 < points.count ? points[index + 1].date : end
   let right = min(next, point.date.addingTimeInterval(TelemetryMath.powerSampleMaxAgeSeconds))
   let left = max(start, point.date)
   guard let watts = point.watts, watts.isFinite, watts >= 0, left < right else { return nil }
   return Interval(start: left, end: right, watts: watts)
  }
  // Query-record averaging and time coverage are distinct projections.
  // Keep original observations for coverage and detecting real telemetry gaps.
  let coverage = TelemetryMath.weightedAverage(samples: points, endingAt: end, windowMinutes: Double(minutes))?.coverageFraction ?? 0
  let meanCandidates = points.filter {
   guard $0.date >= start, $0.date <= end, let watts = $0.watts else { return false }
   return watts.isFinite && watts >= 0
  }
  let meanSamples = Self.meanQueryRecords(meanCandidates, end: end)
  records = meanSamples
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

 /// In-window records arrive chronologically. The query-time seed cannot emit
 /// an older first record. A value change can emit the previous plateau end or
 /// the new observation, and the last accepted record is appended at completion.
 /// Missing data remains unavailable rather than creating a synthetic zero.
 static func meanQueryRecords(_ samples: [PowerSample], end: Date) -> [PowerSample] {
  GraphQueryRecords.project(samples.filter { ($0.watts ?? -1) >= 0 }, endingAt: end,
   spacing: 0, date: { $0.date }, value: { $0.watts ?? .nan })
 }
}

@MainActor struct PowerConsumptionView: View {
 let reading: BatteryReading?
 let history: [HistoryPoint]
 let active: Bool
 @ObservedObject private var preferences: PowerGraphPreferences
 @StateObject private var monitor: PowerGraphMonitor
 @State private var visible = false
 @State private var initialQueryDate: Date
 init(reading: BatteryReading?, history: [HistoryPoint], preferences: PowerGraphPreferences? = nil,
      active: Bool = false, read: PowerGraphMonitor.Read? = nil, monitor: PowerGraphMonitor? = nil,
      queryDate: Date = Date()) {
  self.reading = reading; self.history = history; self.active = active
  _initialQueryDate = State(initialValue: queryDate)
  _preferences = ObservedObject(wrappedValue: preferences ?? PowerGraphPreferences())
  _monitor = StateObject(wrappedValue: monitor ?? PowerGraphMonitor(read: read))
 }
 private var minutes: Int { preferences.period.rawValue }
 private var displayedReading: BatteryReading? { monitor.attempted ? monitor.reading : reading }
 var body: some View {
  let data = PowerConsumptionSnapshot(reading: displayedReading, history: history, minutes: minutes, end: monitor.queryDate ?? initialQueryDate)
  VStack(alignment: .leading, spacing: 8) {
   Picker(NSLocalizedString("续航估算方式", comment: ""), selection: $preferences.mode) {
    ForEach(PowerCalculationMode.allCases) { mode in Text(mode.title).tag(mode) }
   }.pickerStyle(.segmented)
   Picker(NSLocalizedString("功耗时间窗口", comment: ""), selection: $preferences.period) {
    ForEach(PowerGraphPeriod.allCases) { period in Text(period.title).tag(period) }
   }.pickerStyle(.segmented)
   if data.records.isEmpty {
    Text(NSLocalizedString("记录系统负载后，功耗曲线将在这里显示。", comment: "")).font(.caption).presentationSecondary()
   } else {
    graph(data)
   }
   valueRow(label: NSLocalizedString("估算采用的功耗", comment: ""), value: watts(data.selectedWatts(preferences.mode)))
   valueRow(label: NSLocalizedString("预计电池续航", comment: ""), value: duration(data.selectedMinutes(preferences.mode)))
   if let average = data.average {
    Text(String.localizedStringWithFormat(NSLocalizedString("%lld 分钟平均：%@ · 数据覆盖 %@", comment: ""),
     Int64(minutes), watts(average.watts), String(format: "%.0f%%", average.coverageFraction * 100)))
     .font(.caption).presentationSecondary()
   }
   valueRow(label: DashboardSpecification.timeToEmpty.title, value: BatterySpecificationFormatter.value(.timeToEmpty, reading: displayedReading))
   if let error = monitor.error { Text(error).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
   Text(NSLocalizedString("平均模式采用所选窗口的记录平均值；即时模式采用当前系统负载。", comment: ""))
    .font(.caption).presentationSecondary().fixedSize(horizontal: false, vertical: true)
   Text(NSLocalizedString("续航优先使用已知机型的标称电压；否则使用系统设计电压，最后回退到当前端电压。平均功耗为记录值平均，不是时间加权值；覆盖率单独反映有效观测时长。", comment: ""))
    .font(.caption).presentationSecondary().fixedSize(horizontal: false, vertical: true)
  }.onAppear { visible = true; monitor.configure(active: active, mode: preferences.mode) }
   .onChange(of: active) { monitor.configure(active: visible && $0, mode: preferences.mode) }
   .onChange(of: preferences.mode) { monitor.configure(active: visible && active, mode: $0) }
   .onChange(of: preferences.period) { _ in if visible && active { monitor.refresh() } }
   .onDisappear { visible = false; monitor.stop() }
 }

 private func graph(_ data: PowerConsumptionSnapshot) -> some View {
  let loads = data.records.compactMap(\.watts)
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
     let dates = data.plotDates
     let span = dates.upperBound.timeIntervalSince(dates.lowerBound)
     let width = geometry.size.width
     let height = geometry.size.height
     let positions = data.records.map { sample in
      CGPoint(x: sample.date.timeIntervalSince(dates.lowerBound) / span * width,
       y: y(sample.watts ?? 0, height: height))
     }
     Path { path in
      for index in positions.indices {
       if index > 0 && data.connects(data.records[index - 1].date, data.records[index].date) {
        path.addLine(to: positions[index])
       } else { path.move(to: positions[index]) }
      }
     }.stroke(PresentationPalette.mint, lineWidth: 2)
     // Isolated observations stay visible without inventing a connecting line.
     ForEach(positions.indices, id: \.self) { index in
      Circle().fill(PresentationPalette.mint).frame(width: 3, height: 3)
       .position(positions[index])
     }
     if let average = data.average, let dates = data.averageDateRange {
      Path { path in
       let positionY = y(average.watts, height: geometry.size.height)
       let domain = data.plotDates
       let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
       let firstX = dates.lowerBound.timeIntervalSince(domain.lowerBound) / span * geometry.size.width
       let lastX = dates.upperBound.timeIntervalSince(domain.lowerBound) / span * geometry.size.width
       path.move(to: CGPoint(x: firstX, y: positionY))
       path.addLine(to: CGPoint(x: lastX, y: positionY))
      }.stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
     }
     GraphInspectionOverlay(samples: data.records.indices.map { index in
      GraphInspectionSample(date: data.records[index].date, position: positions[index],
       value: watts(data.records[index].watts),
       secondary: data.average.map { NSLocalizedString("窗口平均", comment: "") + " " + watts($0.watts) })
     }, size: geometry.size)
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
    Text(data.plotDates.lowerBound, style: .time); Spacer(); Text(data.plotDates.upperBound, style: .time)
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
