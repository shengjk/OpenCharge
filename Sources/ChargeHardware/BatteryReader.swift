import Foundation
import IOKit
import IOKit.ps

/// The default IOKit port was renamed in macOS 12. Keep the SDK's legacy
/// constant on older systems; both branches request the same default port.
enum RegistryPort {
    static var defaultValue: mach_port_t {
        if #available(macOS 12.0, *) { return kIOMainPortDefault }
        else { return kIOMasterPortDefault }
    }
}

public enum BatteryTemperatureSource: String, Codable, Sendable {
    case smc = "smc.TB0T"
    case registry = "ioregistry.Temperature"
    public var displayName: String { self == .smc ? "SMC TB0T" : NSLocalizedString("系统电池传感器", comment: "") }
}

public struct BatteryReading: Codable, Sendable {
    public var date: Date
    public var percent: Double
    /// Degrees Celsius; nil if unavailable or outside the plausible sensor range.
    public var temperature: Double?
    /// Signed milliamps: negative means discharge.
    public var currentMA: Double?
    public var voltageMV: Double?
    public var cycleCount: Int?
    public var healthPercent: Double?
    public var connected: Bool
    public var charging: Bool
    public var physicalAdapterConnected: Bool?
    public var hardwarePercent: Double?
    public var designCapacityMAH: Double?
    /// Raw full-charge capacity when valid; nominal/legacy capacity otherwise.
    public var fullCapacityMAH: Double?
    public var condition: String?
    public var timeToFullMinutes: Double?
    public var timeToEmptyMinutes: Double?
    public var adapterName: String?
    public var adapterManufacturer: String?
    /// Negotiated/rated adapter output, not measured consumption.
    public var adapterWatts: Double?
    /// Negotiated adapter profile in mV/mA, not measured instantaneous input.
    public var adapterVoltageMV: Double?
    public var adapterCurrentMA: Double?
    /// OS-reported system load and actual DC adapter input, converted from mW.
    /// These undocumented telemetry fields can refresh slower than the app polls.
    public var systemPowerW: Double?
    public var adapterPowerW: Double?
    public var temperatureSource: BatteryTemperatureSource?
    public var registryTemperature: Double?
    public var virtualTemperature: Double?
    public var nominalCapacityMAH: Double?
    /// Separate service recommendation; not the macOS battery health assessment.
    public var healthCondition: String?

    public init(date: Date = Date(), percent: Double, temperature: Double? = nil,
                currentMA: Double? = nil, voltageMV: Double? = nil, cycleCount: Int? = nil,
                healthPercent: Double? = nil, connected: Bool, charging: Bool,
                physicalAdapterConnected: Bool? = nil, hardwarePercent: Double? = nil, designCapacityMAH: Double? = nil,
                fullCapacityMAH: Double? = nil, condition: String? = nil,
                timeToFullMinutes: Double? = nil, timeToEmptyMinutes: Double? = nil,
                adapterName: String? = nil, adapterManufacturer: String? = nil,
                adapterWatts: Double? = nil, adapterVoltageMV: Double? = nil,
                adapterCurrentMA: Double? = nil, systemPowerW: Double? = nil,
                adapterPowerW: Double? = nil, temperatureSource: BatteryTemperatureSource? = nil,
                registryTemperature: Double? = nil, virtualTemperature: Double? = nil,
                nominalCapacityMAH: Double? = nil, healthCondition: String? = nil) {
        self.date = date; self.percent = percent; self.temperature = temperature
        self.currentMA = currentMA; self.voltageMV = voltageMV; self.cycleCount = cycleCount
        self.healthPercent = healthPercent; self.connected = connected; self.charging = charging
        self.physicalAdapterConnected = physicalAdapterConnected
        self.hardwarePercent = hardwarePercent; self.designCapacityMAH = designCapacityMAH
        self.fullCapacityMAH = fullCapacityMAH; self.condition = condition
        self.timeToFullMinutes = timeToFullMinutes; self.timeToEmptyMinutes = timeToEmptyMinutes
        self.adapterName = adapterName; self.adapterManufacturer = adapterManufacturer
        self.adapterWatts = adapterWatts; self.adapterVoltageMV = adapterVoltageMV
        self.adapterCurrentMA = adapterCurrentMA; self.systemPowerW = systemPowerW
        self.adapterPowerW = adapterPowerW
        self.temperatureSource = temperatureSource; self.registryTemperature = registryTemperature
        self.virtualTemperature = virtualTemperature; self.nominalCapacityMAH = nominalCapacityMAH
        self.healthCondition = healthCondition
    }
}

public extension BatteryReading {
 func applyingSMCTemperature(_ value: Double?) -> BatteryReading {
  guard let value, value.isFinite, (-40...100).contains(value) else { return self }
  var result = self; result.temperature = value; result.temperatureSource = .smc; return result
 }
 func controlPercentage(useHardware: Bool) throws -> Double {
  if useHardware { guard let value = hardwarePercent, value.isFinite, (0...100).contains(value) else { throw HardwareError.unavailable("hardware battery percentage") }; return value }
  return percent
 }
}
public enum HardwareError: Error, LocalizedError {
    case unavailable(String)
    case unsupported(String)
    case invalidData(String)
    case permissionRequired
    case driver(Int32, UInt8)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return "Hardware unavailable: \(detail)"
        case .unsupported(let detail): return "Unsupported hardware: \(detail)"
        case .invalidData(let detail): return "Invalid hardware data: \(detail)"
        case .permissionRequired: return "SMC writes require the installed privileged helper."
        case .driver(let code, let result): return "SMC driver error \(code), result \(result)."
        }
    }
}

public enum BatteryReader {
    public static func read() throws -> BatteryReading {
        let properties = try registryProperties("AppleSmartBattery")
        guard (properties["BatteryInstalled"] as? NSNumber)?.boolValue != false else {
            throw HardwareError.unavailable("No built-in battery")
        }
        // Prefer the public power-source percentage; registry capacity can mean mAh or percent.
        var source: [String: Any]?
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                guard let description = IOPSGetPowerSourceDescription(snapshot, item)?.takeUnretainedValue()
                        as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                source = description
                break
            }
        }
        return try decode(properties: properties, source: source)
    }

    /// Converts one snapshot without accessing hardware; shared by production and fixtures.
    public static func decode(properties: [String: Any], source: [String: Any]?) throws -> BatteryReading {
        guard (properties["BatteryInstalled"] as? NSNumber)?.boolValue != false else {
            throw HardwareError.unavailable("No built-in battery")
        }
        func number(_ key: String) -> Double? { (properties[key] as? NSNumber)?.doubleValue }
        let percent: Double
        if let now = (source?[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
           let max = (source?[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue, max > 0 {
            percent = 100 * now / max
        } else if let now = number("CurrentCapacity"), let max = number("MaxCapacity"), max > 0 {
            percent = 100 * now / max
        } else {
            throw HardwareError.invalidData("Missing battery capacity")
        }
        guard percent.isFinite, (0...100).contains(percent) else {
            throw HardwareError.invalidData("Battery percentage is out of range")
        }
        // AppleSmartBattery IORegistry Temperature is exposed in centi-Celsius.
        // Primary implementations: beltex/SystemKit Battery.swift, exelban/stats Battery/readers.swift.
        // This field is not the raw Smart Battery protocol temperature in tenths of Kelvin.
        let temperature = TelemetryMath.batteryTemperatureCelsius(raw: number("Temperature"))
        let design = valid(number("DesignCapacity"), 1...100000)
        // Modern Apple Silicon MaxCapacity is a percentage, not the full-charge capacity in mAh.
        let nominal = valid(number("NominalChargeCapacity"), 1...100000)
        let full = valid(number("AppleRawMaxCapacity"), 1...100000) ?? nominal
            ?? valid(number("MaxCapacity"), 101...100000)
        let health: Double? = if let full, let design, design > 0 { 100 * full / design } else { nil }
        let amps = (properties["InstantAmperage"] ?? properties["Amperage"]) as? NSNumber
        // IORegistry sometimes exposes a negative signed integer with an unsigned NSNumber type.
        let current = amps.map { Double($0.int64Value) }
        let connected = (properties["ExternalConnected"] as? NSNumber)?.boolValue
            ?? (source?[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        let charging = (properties["IsCharging"] as? NSNumber)?.boolValue
            ?? (source?[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
        let adapter = connected ? properties["AdapterDetails"] as? [String: Any] : nil
        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
            guard let value, value.isFinite, range.contains(value) else { return nil }; return value
        }
        func adapterNumber(_ key: String) -> Double? { (adapter?[key] as? NSNumber)?.doubleValue }
        func watts(_ key: String) -> Double? {
            valid(((telemetry?[key] as? NSNumber)?.doubleValue).map { $0 / 1000 }, 0...1000)
        }
        func minutes(_ key: String) -> Double? {
            // IOPS documents -1 as calculating; Smart Battery uses 65535 as unavailable.
            valid((source?[key] as? NSNumber)?.doubleValue, 0...65534)
        }
        let rawPercent: Double? = if let raw = number("AppleRawCurrentCapacity"),
            let maxRaw = number("AppleRawMaxCapacity"), maxRaw > 0 {
            valid(raw / maxRaw * 100, 0...100)
        } else { nil }
        return BatteryReading(percent: percent, temperature: temperature,
            currentMA: current, voltageMV: number("Voltage") ?? number("AppleRawBatteryVoltage"),
            cycleCount: (properties["CycleCount"] as? NSNumber)?.intValue,
            healthPercent: health,
            connected: connected, charging: charging,
            physicalAdapterConnected: (properties["AppleRawExternalConnected"] as? NSNumber)?.boolValue,
            hardwarePercent: rawPercent, designCapacityMAH: valid(design, 1...100000),
            fullCapacityMAH: valid(full, 1...100000),
            condition: [source?[kIOPSBatteryHealthKey] as? String, source?[kIOPSBatteryHealthConditionKey] as? String].compactMap { $0 }.first { !$0.isEmpty },
            timeToFullMinutes: charging ? minutes(kIOPSTimeToFullChargeKey) : nil,
            timeToEmptyMinutes: !charging && source?[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue ? minutes(kIOPSTimeToEmptyKey) : nil,
            adapterName: adapter?["Name"] as? String,
            adapterManufacturer: adapter?["Manufacturer"] as? String,
            adapterWatts: valid(adapterNumber("Watts"), 0...1000),
            adapterVoltageMV: valid(adapterNumber("AdapterVoltage"), 1...100000),
            adapterCurrentMA: valid(adapterNumber("Current"), 0...100000),
            systemPowerW: watts("SystemLoad"),
            adapterPowerW: connected ? watts("SystemPowerIn") : nil,
            temperatureSource: temperature == nil ? nil : .registry,
            registryTemperature: temperature,
            virtualTemperature: TelemetryMath.batteryTemperatureCelsius(raw: number("VirtualTemperature")),
            nominalCapacityMAH: nominal,
            healthCondition: (source?[kIOPSBatteryHealthConditionKey] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
}

func registryProperties(_ className: String) throws -> [String: Any] {
    let service = IOServiceGetMatchingService(RegistryPort.defaultValue, IOServiceMatching(className))
    guard service != 0 else { throw HardwareError.unavailable(className) }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS, let resultProperties = properties?.takeRetainedValue() as? [String: Any]
    else { throw HardwareError.unavailable("Cannot read \(className): \(result)") }
    return resultProperties
}
