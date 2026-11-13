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
 let data = PowerConsumptionSnapshot(reading: reading, history: history, minutes: 5, end: end)
 precondition(data.intervals.map(\.watts) == [5, 20, 15])
 precondition(data.intervals.map { $0.end.timeIntervalSince($0.start) } == [60, 90, 30])
 precondition(abs((data.average?.watts ?? 0) - 15.0) < 0.00001 && data.average?.sampleCount == 2 && data.average?.coverageFraction == 0.6)
 precondition(data.plotRange.lowerBound == 15 && data.plotRange.upperBound == 18)
 precondition(data.records.compactMap(\.watts) == [15, 15])
 precondition(data.plotDates == (end.addingTimeInterval(-60)...end))
 precondition(data.connects(end.addingTimeInterval(-30), end))
 precondition(!data.connects(end.addingTimeInterval(-150), end))
 precondition(data.averageDateRange == (end.addingTimeInterval(-30)...end.addingTimeInterval(-30)))
 // Query records preserve changes and plateau endpoints; they are not every observation.
 var plateauReading = reading; plateauReading.systemPowerW = 20
 let repeated = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-120,10),point(-90,10),point(-60,10),point(-30,20)],minutes:5, end: end)
 precondition(repeated.average?.watts == 20 && repeated.average?.sampleCount == 2)
 precondition(repeated.averageDateRange == (end.addingTimeInterval(-30)...end.addingTimeInterval(-30)))
 let plateauEnd = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-180,5),point(-120,10),point(-90,10),point(-60,20)],minutes:5, end: end)
 precondition(abs((plateauEnd.average?.watts ?? 0) - 40.0 / 3) < 0.00001 && plateauEnd.average?.sampleCount == 3)
 precondition(plateauEnd.averageDateRange == (end.addingTimeInterval(-120)...end.addingTimeInterval(-60)))
 let changing = PowerConsumptionSnapshot(reading:plateauReading,
  history:[point(-180,5),point(-120,10),point(-60,15)],minutes:5, end: end)
 precondition(abs((changing.average?.watts ?? 0) - 40.0 / 3) < 0.00001 && changing.average?.sampleCount == 3)
 let continuousPlateau = PowerConsumptionSnapshot(reading: plateauReading,
  history: stride(from: -270, through: -30, by: 30).map { point(Double($0), $0 < -240 ? 5 : 10) }, minutes: 5, end: end)
 precondition(continuousPlateau.connects(end.addingTimeInterval(-240), end))
 let constant = PowerConsumptionSnapshot(reading:reading,
  history:[point(-180,10),point(-120,10),point(-60,10)],minutes:5, end: end)
 precondition(constant.average?.watts == 10 && constant.average?.sampleCount == 1)
 precondition(PowerConsumptionSnapshot(reading:nil,history:[],minutes:5,end:end).average == nil)
 let flat = PowerConsumptionSnapshot(reading: reading, history: [], minutes: 5, end: end)
 precondition(flat.plotRange == (0.0...1.0) && flat.average == nil && flat.averageMinutes == nil)
 var flatZero = reading; flatZero.systemPowerW = 0
 precondition(PowerConsumptionSnapshot(reading: flatZero, history: [], minutes: 5, end: end).plotRange == (0.0...1.0))
 for (value, hours, minutes): (Double, Int64, Int64) in [(394.455,6,34),(59.999,0,59),(60,1,0),(1565,26,5),(0,0,0)] {
  let duration = PowerRuntimeDuration(minutes: value)
  precondition(duration?.hours == hours && duration?.minutes == minutes)
 }
 for value: Double? in [nil, .nan, .infinity, -1, Double(Int64.max)] {
  precondition(PowerRuntimeDuration(minutes: value) == nil)
 }
 precondition(data.currentMinutes == 120 && abs((data.averageMinutes ?? 0) - 80) < 0.00001)
 var noDesign = reading; noDesign.designVoltageMV = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5, end: end).currentMinutes == 144)
 noDesign.remainingCapacityMAH = nil
 precondition(PowerConsumptionSnapshot(reading: noDesign, history: [], minutes: 5, end: end).currentMinutes == nil)
 var modelVoltage = BatteryReading(date: end, percent: 80, voltageMV: 11_955, connected: true, charging: false,
  systemPowerW: 5.65, remainingCapacityMAH: 3288, designVoltageMV: 14_000,
  modelNominalVoltageMV: ModelNominalBatteryVoltage.millivolts(for: "MacBookPro17,1"))
 let nominal = PowerConsumptionSnapshot(reading: modelVoltage, history: [], minutes: 15, end: end)
 precondition(abs((nominal.currentMinutes ?? 0) - 394.45524715997476) < 0.00001)
 precondition(nominal.average == nil && nominal.records.isEmpty && nominal.averageMinutes == nil)
 modelVoltage.voltageMV = 10_000
 precondition(PowerConsumptionSnapshot(reading: modelVoltage, history: [], minutes: 15, end: end).currentMinutes == nominal.currentMinutes)
 // A display-only read cannot replace a recorded point, even at the same date.
 var changedLive = reading; changedLive.systemPowerW = 100
 let recorded = [point(-120, 5), point(-60, 10), point(0, 15)]
 let recordedSnapshot = PowerConsumptionSnapshot(reading: reading, history: recorded, minutes: 5, end: end)
 let changedSnapshot = PowerConsumptionSnapshot(reading: changedLive, history: recorded, minutes: 5, end: end)
 precondition(recordedSnapshot.records.map(\.watts) == changedSnapshot.records.map(\.watts))
 precondition(recordedSnapshot.average?.watts == changedSnapshot.average?.watts)
 precondition(recordedSnapshot.averageMinutes == changedSnapshot.averageMinutes)
 precondition(recordedSnapshot.currentWatts == 10 && changedSnapshot.currentWatts == 100)
 precondition(changedSnapshot.currentMinutes == 12)
 let missingAtEnd = PowerConsumptionSnapshot(reading: changedLive, history: [point(-60, 5), point(0, nil)], minutes: 5, end: end)
 precondition(!missingAtEnd.records.contains { $0.date == end }, "live telemetry cannot fill a recorded gap")
 var missingLive = reading; missingLive.systemPowerW = nil
 let retained = PowerConsumptionSnapshot(reading: missingLive, history: recorded, minutes: 5, end: end)
 precondition(retained.average?.watts == recordedSnapshot.average?.watts && retained.currentWatts == nil)
 // Query time remains independent of old, future or absent sensor timestamps.
 var delayed = reading; delayed.date = end.addingTimeInterval(-600)
 var future = reading; future.date = end.addingTimeInterval(600)
 for sensor in [delayed, future] {
  let snapshot = PowerConsumptionSnapshot(reading: sensor, history: recorded, minutes: 5, end: end)
  precondition(snapshot.end == end && snapshot.records.map(\.date) == recordedSnapshot.records.map(\.date))
  precondition(snapshot.average?.watts == recordedSnapshot.average?.watts)
 }
 let failedRead = PowerConsumptionSnapshot(reading: nil, history: recorded, minutes: 5, end: end)
 precondition(failedRead.average?.watts == recordedSnapshot.average?.watts && failedRead.currentWatts == nil)
 let aged = PowerConsumptionSnapshot(reading: delayed, history: recorded, minutes: 5, end: end.addingTimeInterval(301))
 precondition(aged.records.isEmpty && aged.average == nil)
 let rollback = PowerConsumptionSnapshot(reading: future, history: recorded, minutes: 5, end: end.addingTimeInterval(-90))
 precondition(rollback.average?.watts == 5 && rollback.records.allSatisfy { $0.date <= end.addingTimeInterval(-90) })
 let invalidHistory = [point(-100, .nan), point(-90, -.infinity), point(-80, -5), point(-600, 1000)]
 precondition(PowerConsumptionSnapshot(reading: modelVoltage, history: invalidHistory, minutes: 5, end: end).average == nil)
 var zeroLoad = reading; zeroLoad.systemPowerW = 0
 precondition(PowerConsumptionSnapshot(reading: zeroLoad, history: [], minutes: 5, end: end).currentMinutes == nil)
 let historyOnly = PowerConsumptionSnapshot(reading: nil, history: history, minutes: 5, end: end)
 precondition(historyOnly.average != nil && historyOnly.currentMinutes == nil && historyOnly.averageMinutes == nil)
 for samples in [history, []] {
  let view = NSHostingView(rootView: PowerConsumptionView(reading: reading, history: samples, queryDate: end))
  view.frame = NSRect(x: 0, y: 0, width: 480, height: 300)
  view.layoutSubtreeIfNeeded()
  precondition(view.fittingSize.width > 0 && view.fittingSize.height > 0)
 }
 graphInspectionChecks()
 print("PASS dashboard power intervals, coverage gaps, query-record averages with plateau endpoints/query seed/final record, persisted-only graph/mean with independent live runtime, recorded-gap preservation, independent time coverage, current/average runtime, known nominal voltage precedence, query-record plot bounds/domain and coverage-aware connections, dynamic/flat plot bounds, hour/minute duration boundaries, absent sensors and voltage fallback")
}
