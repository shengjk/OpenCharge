import Foundation

/// The battery-health assessment published by macOS, distinct from the raw
/// full-charge-capacity/design-capacity ratio exposed by AppleSmartBattery.
public struct MacOSBatteryHealth: Codable, Equatable, Sendable {
    public let maximumCapacityPercent: Double?
    public let condition: String?

    public init(maximumCapacityPercent: Double?, condition: String?) {
        self.maximumCapacityPercent = maximumCapacityPercent.flatMap { value in
            value.isFinite && (0...100).contains(value) ? value : nil
        }
        self.condition = condition?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Parses only the documented structured System Profiler output. Text-mode
/// output is localized and is therefore deliberately not accepted here.
public enum MacOSBatteryHealthParser {
    public static func parse(_ data: Data) -> MacOSBatteryHealth? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [[String: Any]] else { return nil }
        for report in root {
            guard let items = report["_items"] as? [[String: Any]] else { continue }
            for item in items where item["_name"] as? String == "spbattery_information" {
                guard let health = item["sppower_battery_health_info"] as? [String: Any] else { continue }
                let maximum = percentage(health["sppower_battery_health_maximum_capacity"])
                let condition = health["sppower_battery_health"] as? String
                guard maximum != nil || condition?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
                return MacOSBatteryHealth(maximumCapacityPercent: maximum, condition: condition)
            }
        }
        return nil
    }

    private static func percentage(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "%"))
        guard let value = Double(trimmed), value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
}

/// A non-blocking, low-frequency cache. Calling this API never waits for the
/// profiler process and does not affect charge-control decisions.
public final class MacOSBatteryHealthCache: @unchecked Sendable {
    public typealias Read = @Sendable () throws -> MacOSBatteryHealth?
    public static let refreshInterval: TimeInterval = 6 * 60 * 60
    public static let shared = MacOSBatteryHealthCache()

    private let lock = NSLock()
    private let read: Read
    private var snapshot: MacOSBatteryHealth?
    private var nextRefresh = Date.distantPast
    private var refreshing = false

    public convenience init() {
        self.init(read: { try Self.readSystemProfiler() })
    }

    public init(read: @escaping Read) {
        self.read = read
    }

    /// Returns the last known value and schedules at most one refresh per six
    /// hours. A failed read is retried on the next cadence, never surfaced as a
    /// fabricated health value.
    public func value(now: Date = Date()) -> MacOSBatteryHealth? {
        lock.lock()
        let current = snapshot
        let shouldRefresh = !refreshing && now >= nextRefresh
        if shouldRefresh {
            refreshing = true
            nextRefresh = now.addingTimeInterval(Self.refreshInterval)
        }
        lock.unlock()
        guard shouldRefresh else { return current }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = try? self.read()
            self.lock.lock()
            if let result { self.snapshot = result }
            self.refreshing = false
            self.lock.unlock()
        }
        return current
    }

    private static func readSystemProfiler() throws -> MacOSBatteryHealth? {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-nospawn", "-xml", "SPPowerDataType"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return MacOSBatteryHealthParser.parse(data)
    }
}
