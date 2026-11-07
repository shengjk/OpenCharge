import SwiftUI
import ChargeHardware

@MainActor func powerConsumptionChecks() {
 let end = Date(timeIntervalSince1970: 1000)
 func point(_ seconds: Double, _ watts: Double?) -> HistoryPoint {
  HistoryPoint(date: end.addingTimeInterval(seconds), percent: 80, temperature: nil,
   watts: -80, reason: "fixture", systemWatts: watts, adapterWatts: 80)
 }
 let reading = BatteryReading(date: end, percent: 40, voltageMV: 12_000, connected: true, charging: true,
  systemPowerW: 10, remainingCapacityMAH: 2000, designVoltageMV: 10_000)
 let history = [point(-30, 15), point(-360, 5), point(-150, 20), point(-60, 60), point(-60, nil), point(1, 100)]
 let data = PowerConsumptionSnapshot(reading: reading, history: history, minutes: 5)
 precondition(data.intervals.map(\.watts) == [5, 20, 15])
 precondition(data.intervals.map { $0.end.timeIntervalSince($0.start) } == [60, 90, 30])
 precondition(data.average?.watts == 2550 / 180.0 && data.average?.coverageFraction == 0.6)
 precondition(data.currentMinutes == 120 && abs((data.averageMinutes ?? 0) - 1200 / (2550 / 180.0)) < 0.00001)
 var noDesign = reading; noDesign.designVoltageMV = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5).currentMinutes == 144)
 noDesign.remainingCapacityMAH = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5).currentMinutes == nil)
 var zeroLoad = reading; zeroLoad.systemPowerW = 0
 precondition(PowerConsumptionSnapshot(reading: zeroLoad, history: [], minutes: 5).currentMinutes == nil)
 let historyOnly = PowerConsumptionSnapshot(reading: nil, history: history, minutes: 5, end: end)
 precondition(historyOnly.average != nil && historyOnly.currentMinutes == nil && historyOnly.averageMinutes == nil)
 for samples in [history, []] {
  let view = NSHostingView(rootView: PowerConsumptionView(reading: reading, history: samples))
  view.frame = NSRect(x: 0, y: 0, width: 480, height: 300)
  view.layoutSubtreeIfNeeded()
  precondition(view.fittingSize.width > 0 && view.fittingSize.height > 0)
 }
 print("PASS dashboard power intervals, coverage gaps, current/average runtime, absent sensors and voltage fallback")
}
