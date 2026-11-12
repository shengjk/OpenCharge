import SwiftUI

@MainActor func batteryStatisticChecks() throws {
 let end = Date(timeIntervalSince1970: 10000)
 func point(_ seconds: Double, _ temperature: Double?) -> HistoryPoint {
  HistoryPoint(date: end.addingTimeInterval(seconds), percent: 70, temperature: temperature,
   watts: nil, reason: "fixture", health: 96, cycles: 120, fullCapacityMAH: 4200)
 }
 let points = [point(-180, 30), point(-120, 31), point(-60, nil), point(0, 32)]
 let data = BatteryStatisticPlot(points: points, metric: .temperature, hours: 1, end: end)
 precondition(data.samples.map(\.value) == [30, 31, 32] && data.samples.map(\.startsSegment) == [true, false, true])
 precondition(data.plotDates == (end.addingTimeInterval(-180)...end))
 let singleton = BatteryStatisticPlot(points: [point(0, 31)], metric: .temperature, hours: 168, end: end)
 precondition(singleton.plotDates == (end.addingTimeInterval(-30)...end.addingTimeInterval(30)))
 precondition(data.minimum == 30 && data.maximum == 32 && data.lower < 30 && data.upper > 32)
 let duplicates = BatteryStatisticPlot(points: points + [point(0, nil)], metric: .temperature, hours: 1, end: end)
 precondition(duplicates.samples.count == 2)
 let gap = BatteryStatisticPlot(points: [point(-240, 30), point(0, 31), point(1, 99), point(-3601, 20)],
  metric: .temperature, hours: 1, end: end)
 precondition(gap.samples.count == 2 && gap.samples.allSatisfy(\.startsSegment))
 let old = try JSONDecoder().decode(HistoryPoint.self, from: Data("""
 {"date":100,"percent":50,"reason":"legacy"}
 """.utf8))
 precondition(old.fullCapacityMAH == nil && BatteryStatistic.fullCapacity.value(old) == nil)
 let encoded = try JSONEncoder().encode(points[0])
 let decoded = try JSONDecoder().decode(HistoryPoint.self, from: encoded)
 precondition(decoded.fullCapacityMAH == 4200)
 for metric in BatteryStatistic.allCases {
  let projection = BatteryStatisticPlot(points: points, metric: metric, hours: 24, end: end)
  precondition(projection.samples.count == (metric == .temperature ? 3 : 4))
  precondition(projection.lower < projection.upper)
  for source in [points, []] {
   let host = NSHostingView(rootView: BatteryStatisticChart(metric: metric, points: source))
   host.frame = NSRect(x: 0, y: 0, width: 600, height: 240)
   host.layoutSubtreeIfNeeded()
   precondition(host.fittingSize.height > 0)
  }
 }
 print("PASS battery statistic units, sparse and duplicate records, stale gaps, first/last record dates and singleton domain, legacy capacity history and native layouts")
}
