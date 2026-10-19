import Foundation
import IOKit.ps
import ChargeHardware

@main struct TelemetryReaderTests {
 static func main() throws {
  var count = 0
  func check(_ condition: Bool, _ message: String) {
   precondition(condition, message); count += 1
  }
  func decode(_ properties: [String: Any], source: [String: Any]? = nil) throws -> BatteryReading {
   try BatteryReader.decode(properties: properties, source: source)
  }
  let properties: [String: Any] = ["CurrentCapacity": 80, "MaxCapacity": 100,
   "Temperature": 3000, "VirtualTemperature": 3500, "AppleRawMaxCapacity": 4200,
   "NominalChargeCapacity": 4400, "DesignCapacity": 5000, "ExternalConnected": true]
  let source: [String: Any] = [kIOPSBatteryHealthKey: "Normal", kIOPSBatteryHealthConditionKey: "CheckBattery"]
  let base = try decode(properties, source: source)
  check(base.fullCapacityMAH == 4200 && base.nominalCapacityMAH == 4400 && base.healthPercent == 84, "raw and nominal capacities must remain distinct")
  check(base.condition == "Normal" && base.healthCondition == "CheckBattery", "health assessment must not be replaced by a service hint")
  check(base.temperature == 30 && base.registryTemperature == 30 && base.virtualTemperature == 35 && base.temperatureSource == .registry, "registry and virtual sensors must remain distinct")
  let preferred = try BatteryTelemetryReader.read(base: { base }, smcTemperature: { 33.5 })
  check(preferred.temperature == 33.5 && preferred.temperatureSource == .smc && preferred.registryTemperature == 30 && preferred.virtualTemperature == 35, "SMC source selection must preserve alternate sensor values")
  for invalid: Double? in [nil, .nan, .infinity, -41, 101] {
   let fallback = try BatteryTelemetryReader.read(base: { base }, smcTemperature: { invalid })
   check(fallback.temperature == 30 && fallback.temperatureSource == .registry, "invalid SMC values must preserve the identified fallback")
  }
  let denied = try BatteryTelemetryReader.read(base: { base }, smcTemperature: { throw HardwareError.permissionRequired })
  check(denied.temperature == 30 && denied.temperatureSource == .registry, "read failure must preserve fallback")
  var queriedSMC = false
  do {
   _ = try BatteryTelemetryReader.read(base: { throw HardwareError.unavailable("fixture") }, smcTemperature: { queriedSMC = true; return 33 })
   preconditionFailure("missing base battery must fail")
  } catch { check(!queriedSMC, "missing battery must not trigger an SMC query") }
  var missingSensor = properties; missingSensor.removeValue(forKey: "Temperature")
  let unavailable = try BatteryTelemetryReader.read(base: { try decode(missingSensor) }, smcTemperature: { nil })
  check(unavailable.temperature == nil && unavailable.temperatureSource == nil && unavailable.virtualTemperature == 35, "virtual sensor must not silently replace the battery sensor")
  var invalidRaw = properties; invalidRaw["AppleRawMaxCapacity"] = Double.nan
  let nominalFallback = try decode(invalidRaw)
  check(nominalFallback.fullCapacityMAH == 4400 && nominalFallback.healthPercent == 88, "invalid raw capacity must not hide a valid nominal fallback")
  invalidRaw.removeValue(forKey: "NominalChargeCapacity")
  let percentIsNotCapacity = try decode(invalidRaw)
  check(percentIsNotCapacity.fullCapacityMAH == nil && percentIsNotCapacity.healthPercent == nil, "pinned percent must not become mAh")
  invalidRaw["MaxCapacity"] = 4300
  let legacyCapacity = try decode(invalidRaw)
  check(legacyCapacity.fullCapacityMAH == 4300, "legacy capacity may fall back to actual mAh")
  var invalidDesign = properties; invalidDesign["DesignCapacity"] = 0
  let noHealth = try decode(invalidDesign)
  check(noHealth.designCapacityMAH == nil && noHealth.healthPercent == nil, "invalid design capacity must not yield a health ratio")
  let encoder = JSONEncoder(); let data = try encoder.encode(preferred)
  let roundTrip = try JSONDecoder().decode(BatteryReading.self, from: data)
  check(roundTrip.temperatureSource == .smc && roundTrip.nominalCapacityMAH == 4400 && roundTrip.healthCondition == "CheckBattery", "new provenance fields must round-trip")
  var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  for field in ["temperatureSource", "registryTemperature", "virtualTemperature", "nominalCapacityMAH", "healthCondition"] { legacy.removeValue(forKey: field) }
  let old = try JSONDecoder().decode(BatteryReading.self, from: JSONSerialization.data(withJSONObject: legacy))
  check(old.temperature == 33.5 && old.temperatureSource == nil && old.nominalCapacityMAH == nil, "legacy telemetry must decode without inventing provenance")
  check(TelemetryMath.smcTemperatureCelsius(dataType: "sp78", bytes: [0x21, 0x80]) == 33.5, "signed 8.8 fixed point")
  check(TelemetryMath.smcTemperatureCelsius(dataType: "sp78", bytes: [0xF5, 0x80]) == -10.5, "negative signed fixed point")
  check(TelemetryMath.smcTemperatureCelsius(dataType: "flt ", bytes: [0, 0, 6, 66]) == 33.5, "little-endian float payload")
  for (type, bytes): (String, [UInt8]) in [("sp78", [0]), ("flt ", [0, 0]), ("ui16", [0, 33]), ("flt ", [0, 0, 128, 127]), ("sp78", [127, 255])] {
   check(TelemetryMath.smcTemperatureCelsius(dataType: type, bytes: bytes) == nil, "unknown, malformed, nonfinite or implausible temperatures must be rejected")
  }
  print("Telemetry source/capacity/legacy decoding: \(count) fixture checks passed; no hardware access")
 }
}
