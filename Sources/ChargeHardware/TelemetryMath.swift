import Foundation

public struct PowerSample: Sendable {
    public var date: Date
    public var watts: Double?
    public init(date: Date, watts: Double?) { self.date = date; self.watts = watts }
}
public struct WeightedPowerAverage: Sendable {
    public var watts: Double
    public var coveredSeconds: Double
    public var windowSeconds: Double
    public var coverageFraction: Double { coveredSeconds / windowSeconds }
}
public enum TelemetryMath {
    /// sp78 is signed big-endian 8.8 fixed point; Apple Silicon flt payloads are IEEE little-endian.
    /// Only exact known layouts are accepted; unknown types and non-finite values remain unavailable.
    public static func smcTemperatureCelsius(dataType: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch dataType {
        case "sp78":
            guard bytes.count == 2 else { return nil }
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "flt ":
            guard bytes.count == 4 else { return nil }
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        default: return nil
        }
        guard value.isFinite, (-40...100).contains(value) else { return nil }; return value
    }

    public static func batteryTemperatureCelsius(raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        let value = raw / 100
        return (-40...100).contains(value) ? value : nil
    }
    /// Time integral of sample-and-hold values divided by covered duration.
    /// A reading represents [its timestamp, next timestamp), capped by maxSampleAgeSeconds.
    /// Unknown readings break coverage; no interpolation across sleep/stale gaps or future data.
    /// Equal timestamps use the final input reading. Partial windows report actual coverage.
    public static func weightedAverage(samples: [PowerSample], endingAt end: Date,
        windowMinutes: Double, maxSampleAgeSeconds: Double = 120) -> WeightedPowerAverage? {
        guard end.timeIntervalSince1970.isFinite, windowMinutes.isFinite, windowMinutes > 0,
              maxSampleAgeSeconds.isFinite, maxSampleAgeSeconds > 0 else { return nil }
        let window = windowMinutes * 60
        guard window.isFinite else { return nil }
        let start = end.addingTimeInterval(-window)
        let sorted = samples.enumerated().filter { $0.element.date.timeIntervalSince1970.isFinite && $0.element.date <= end }
            .sorted { $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date }
        var unique: [PowerSample] = []
        for item in sorted {
            if unique.last?.date == item.element.date { unique[unique.count - 1] = item.element }
            else { unique.append(item.element) }
        }
        var energy = 0.0, covered = 0.0
        for index in unique.indices {
            let sample = unique[index]
            guard let power = sample.watts, power.isFinite, power >= 0 else { continue }
            let next = index + 1 < unique.count ? unique[index + 1].date : end
            let left = max(sample.date, start)
            let right = min(end, next, sample.date.addingTimeInterval(maxSampleAgeSeconds))
            let seconds = right.timeIntervalSince(left)
            guard seconds > 0 else { continue }
            energy += power * seconds; covered += seconds
        }
        guard covered > 0, energy.isFinite else { return nil }
        return WeightedPowerAverage(watts: energy / covered, coveredSeconds: covered, windowSeconds: window)
    }
    /// Energy estimate needs the pack's nominal voltage supplied by the caller. Do not silently
    /// substitute its instantaneous terminal voltage, adapter rating, or a different battery's voltage.
    public static func remainingEnergyWH(fullCapacityMAH: Double?, percent: Double?, nominalVoltageMV: Double?) -> Double? {
        guard let capacity = fullCapacityMAH, let percent, let voltage = nominalVoltageMV,
              capacity.isFinite, capacity > 0, voltage.isFinite, voltage > 0,
              percent.isFinite, (0...100).contains(percent) else { return nil }
        let energy = capacity * voltage / 1_000_000 * percent / 100
        return energy.isFinite ? energy : nil
    }
    /// Positive battery discharge magnitude from signed battery current, never adapter input power.
    public static func batteryDischargePowerW(currentMA: Double?, voltageMV: Double?) -> Double? {
        guard let current = currentMA, let voltage = voltageMV, current.isFinite, voltage.isFinite,
              current < 0, voltage > 0 else { return nil }
        let watts = -current * voltage / 1_000_000
        return watts.isFinite ? watts : nil
    }
    public static func remainingTimeMinutes(remainingEnergyWH: Double?, dischargePowerW: Double?) -> Double? {
        guard let energy = remainingEnergyWH, let watts = dischargePowerW,
              energy.isFinite, energy >= 0, watts.isFinite, watts > 0 else { return nil }
        let minutes = energy / watts * 60
        return minutes.isFinite ? minutes : nil
    }
}
