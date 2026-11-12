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
 precondition(abs((data.average?.watts ?? 0) - 35.0 / 3) < 0.00001 && data.average?.sampleCount == 3 && data.average?.coverageFraction == 0.6)
 precondition(data.plotRange.lowerBound == 5 && data.plotRange.upperBound == 23)
 precondition(data.averageDateRange == (end.addingTimeInterval(-30)...end))
 // Query records preserve changes and plateau endpoints; they are not every observation.
 var plateauReading = reading; plateauReading.systemPowerW = 20
 let repeated = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-120,10),point(-90,10),point(-60,10),point(-30,20)],minutes:5)
 precondition(repeated.average?.watts == 20 && repeated.average?.sampleCount == 2)
 precondition(repeated.averageDateRange == (end.addingTimeInterval(-30)...end))
 let plateauEnd = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-180,5),point(-120,10),point(-90,10),point(-60,20)],minutes:5)
 precondition(abs((plateauEnd.average?.watts ?? 0) - 40.0 / 3) < 0.00001 && plateauEnd.average?.sampleCount == 3)
 precondition(plateauEnd.averageDateRange == (end.addingTimeInterval(-120)...end))
 let changing = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-180,5),point(-120,10),point(-60,15)],minutes:5)
 precondition(changing.average?.watts == 16.25 && changing.average?.sampleCount == 4)
 let constant = PowerConsumptionSnapshot(reading:reading,
  history:[point(-180,10),point(-120,10),point(-60,10)],minutes:5)
 precondition(constant.average?.watts == 10 && constant.average?.sampleCount == 1)
 precondition(PowerConsumptionSnapshot(reading:nil,history:[],minutes:5,end:end).average == nil)
 let flat = PowerConsumptionSnapshot(reading: reading, history: [], minutes: 5)
 precondition(flat.plotRange.lowerBound == 10 && flat.plotRange.upperBound == 12)
 var flatZero = reading; flatZero.systemPowerW = 0
 precondition(PowerConsumptionSnapshot(reading: flatZero, history: [], minutes: 5).plotRange == (0.0...1.0))
 for (value, hours, minutes): (Double, Int64, Int64) in [(394.455,6,34),(59.999,0,59),(60,1,0),(1565,26,5),(0,0,0)] {
  let duration = PowerRuntimeDuration(minutes: value)
  precondition(duration?.hours == hours && duration?.minutes == minutes)
 }
 for value: Double? in [nil, .nan, .infinity, -1, Double(Int64.max)] {
  precondition(PowerRuntimeDuration(minutes: value) == nil)
 }
 precondition(data.currentMinutes == 120 && abs((data.averageMinutes ?? 0) - 1200 / (35.0 / 3)) < 0.00001)
 var noDesign = reading; noDesign.designVoltageMV = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5).currentMinutes == 144)
 noDesign.remainingCapacityMAH = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5).currentMinutes == nil)
 var modelVoltage = BatteryReading(date: end, percent: 80, voltageMV: 11_955, connected: true, charging: false,
  systemPowerW: 5.65, remainingCapacityMAH: 3288, designVoltageMV: 14_000,
  modelNominalVoltageMV: ModelNominalBatteryVoltage.millivolts(for: "MacBookPro17,1"))
 let nominal = PowerConsumptionSnapshot(reading: modelVoltage, history: [], minutes: 15)
 precondition(abs((nominal.currentMinutes ?? 0) - 394.45524715997476) < 0.00001)
 precondition(nominal.average?.watts == 5.65 && nominal.average?.sampleCount == 1 && nominal.average?.coverageFraction == 0)
 modelVoltage.voltageMV = 10_000
 precondition(PowerConsumptionSnapshot(reading: modelVoltage, history: [], minutes: 15).currentMinutes == nominal.currentMinutes)
 let invalidHistory = [point(-100, .nan), point(-90, -.infinity), point(-80, -5), point(-600, 1000)]
 precondition(PowerConsumptionSnapshot(reading: modelVoltage, history: invalidHistory, minutes: 5).average?.watts == 5.65)
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
 print("PASS dashboard power intervals, coverage gaps, query-record averages with plateau endpoints/query seed/final record, independent time coverage, current/average runtime, known nominal voltage precedence, dynamic/flat plot bounds, hour/minute duration boundaries, absent sensors and voltage fallback")
}
