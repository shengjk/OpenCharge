import Foundation

/// Fixed read-only telemetry. A missing sensor never prevents unrelated sensors from being used.
/// Types are read from key metadata; no control keys, write operations or helper requests are used.
public struct SMCTelemetryReading: Sendable {
    public var temperature: Double?
    public var systemPowerW: Double?
    public var adapterPowerW: Double?

    public init(temperature: Double? = nil, systemPowerW: Double? = nil, adapterPowerW: Double? = nil) {
        self.temperature = temperature; self.systemPowerW = systemPowerW; self.adapterPowerW = adapterPowerW
    }

    public static func capture(read: (String) throws -> (dataType: String, bytes: [UInt8])) -> Self {
        func scalar(_ key: String, types: Set<String>, range: ClosedRange<Double>) -> Double? {
            guard let raw = try? read(key), types.contains(raw.dataType),
                  let value = TelemetryMath.smcScalar(dataType: raw.dataType, bytes: raw.bytes),
                  range.contains(value) else { return nil }
            return value
        }
        let temperature = scalar("TB0T", types: ["flt ", "sp78"], range: -40...100)
        let system = scalar("PSTR", types: ["flt ", "sp78"], range: 0...1000)
        // These fixed sensors are volts and amps, not the adapter's negotiated profile.
        let voltage = scalar("VD0R", types: ["flt "], range: 0...100)
        let current = scalar("ID0R", types: ["flt "], range: 0...100)
        let input: Double?
        if let voltage, let current, voltage * current <= 1000 { input = voltage * current }
        else { input = nil }
        return Self(temperature: temperature, systemPowerW: system, adapterPowerW: input)
    }
}
