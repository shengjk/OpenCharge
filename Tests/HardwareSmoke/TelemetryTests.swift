import Foundation
import IOKit.pwr_mgt
@main struct TelemetryTests {
 static func main() throws {
  var failures = 0
  func check(_ value: Bool, _ name: String) { if !value { failures += 1; print("FAIL \(name)") } else { print("PASS \(name)") } }
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)
  let samples = [PowerSample(date: epoch, watts: 10), PowerSample(date: epoch.addingTimeInterval(30), watts: 40)]
  let average = TelemetryMath.weightedAverage(samples: samples, endingAt: epoch.addingTimeInterval(120), windowMinutes: 2)
  check(average?.watts == 32.5 && average?.coveredSeconds == 120, "irregular samples use elapsed-time weights")
  let gaps = TelemetryMath.weightedAverage(samples: samples, endingAt: epoch.addingTimeInterval(120), windowMinutes: 2, maxSampleAgeSeconds: 30)
  check(gaps?.watts == 25 && gaps?.coverageFraction == 0.5, "stale gaps report partial coverage")
  let unknown = TelemetryMath.weightedAverage(samples: [samples[0], PowerSample(date: epoch.addingTimeInterval(30), watts: nil)], endingAt: epoch.addingTimeInterval(120), windowMinutes: 2)
  check(unknown?.watts == 10 && unknown?.coveredSeconds == 30, "unknown sample breaks coverage")
  check(TelemetryMath.weightedAverage(samples: [PowerSample(date: epoch, watts: .nan)], endingAt: epoch.addingTimeInterval(60), windowMinutes: 1) == nil, "nonfinite sample rejected")
  let tied = TelemetryMath.weightedAverage(samples: [samples[0], PowerSample(date: epoch, watts: 20)], endingAt: epoch.addingTimeInterval(60), windowMinutes: 1)
  check(tied?.watts == 20, "last equal-timestamp sample wins")
  check(TelemetryMath.batteryTemperatureCelsius(raw: 3077) == 30.77, "IORegistry centi-Celsius decoder")
  check(TelemetryMath.batteryTemperatureCelsius(raw: nil) == nil && TelemetryMath.batteryTemperatureCelsius(raw: .infinity) == nil, "missing temperature is unknown")
  let energy = TelemetryMath.remainingEnergyWH(fullCapacityMAH: 5000, percent: 50, nominalVoltageMV: 11000)
  check(energy == 27.5, "nominal battery energy units")
  check(TelemetryMath.remainingTimeMinutes(remainingEnergyWH: energy, dischargePowerW: 11) == 150, "remaining minutes from real discharge magnitude")
  check(TelemetryMath.remainingTimeMinutes(remainingEnergyWH: energy, dischargePowerW: 0) == nil, "zero power does not imply infinite runtime")
  let reading = BatteryReading(percent: 80, connected: true, charging: false, hardwarePercent: 77)
  check(try reading.controlPercentage(useHardware: true) == 77 && reading.controlPercentage(useHardware: false) == 80, "explicit control percentage reference")
  do { _ = try BatteryReading(percent: 80, connected: true, charging: false).controlPercentage(useHardware: true); check(false, "unknown raw percentage rejected") } catch { check(true, "unknown raw percentage rejected") }
  var created = 0; var released = 0; var failRelease = true
  let sleep = SleepController(create: { created += 1; return 77 }, release: { id in if failRelease { throw HardwareError.unavailable("fake release failure") }; if id == 77 { released += 1 } })
  try sleep.setPreventIdleSleep(true); try sleep.setPreventIdleSleep(true)
  check(created == 1 && sleep.active, "one idle assertion per owner")
  do { try sleep.setPreventIdleSleep(false); check(false, "release failure must propagate") } catch { check(sleep.active, "failed release retains ownership for retry") }
  failRelease = false; try sleep.setPreventIdleSleep(false); try sleep.setPreventIdleSleep(false)
  check(released == 1 && !sleep.active, "successful cleanup is idempotent")
  print("Telemetry/sleep fake checks: \(failures) failures; no hardware or real assertions changed")
  exit(failures == 0 ? 0 : 1)
 }
}
