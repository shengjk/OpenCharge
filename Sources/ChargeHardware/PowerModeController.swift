import Foundation
import Darwin
import IOKit.ps

/// Fixed pmset sources: battery (-b) and charger (-c). Unknown preferences are never overwritten.
public enum PowerSource: String, Codable, CaseIterable, Sendable {
    case battery, ac
    fileprivate var flag: String { self == .battery ? "-b" : "-c" }
}
public struct LowPowerStatus: Codable, Sendable {
    public var battery: Bool?
    public var ac: Bool?
    public var description: String {
        func value(_ mode: Bool?) -> String { mode.map { $0 ? "1" : "0" } ?? "unknown" }
        return "battery=\(value(battery)) ac=\(value(ac))"
    }
    public init(helperResponse: String) throws {
        let fields = helperResponse.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 2, fields[0].hasPrefix("battery="), fields[1].hasPrefix("ac=") else {
            throw PowerModeError.invalidOutput("missing power-source preferences")
        }
        func value(_ text: Substring) throws -> Bool? {
            switch text {
            case "0": return false
            case "1": return true
            case "unknown": return nil
            default: throw PowerModeError.invalidOutput("invalid power-source preference")
            }
        }
        battery = try value(fields[0].dropFirst(8)); ac = try value(fields[1].dropFirst(3))
    }
    public init(battery: Bool?, ac: Bool?) { self.battery = battery; self.ac = ac }
    fileprivate subscript(_ source: PowerSource) -> Bool? { source == .battery ? battery : ac }
}
public enum PowerModeError: Error, LocalizedError {
    case invalidOutput(String), unavailable(String), permissionRequired
    public var errorDescription: String? {
        switch self {
        case .invalidOutput(let detail): return "Invalid pmset output: \(detail)"
        case .unavailable(let detail): return "Power mode unavailable: \(detail)"
        case .permissionRequired: return "Changing power mode requires the privileged helper."
        }
    }
}

public enum EnergyMode: Int, Codable, CaseIterable, Sendable {
    case automatic = 0, low = 1, high = 2
}
public struct EnergyModeRequest: Sendable {
    public let mode: EnergyMode
    public let source: PowerSource?
    public init(mode: EnergyMode, source: PowerSource? = nil) { self.mode = mode; self.source = source }
    public var command: String {
        let scope = source == .battery ? "Battery" : source == .ac ? "AC" : ""
        return "energyMode" + scope + ["Automatic", "Low", "High"][mode.rawValue]
    }
    public init?(command: String) {
        for mode in EnergyMode.allCases {
            for source: PowerSource? in [nil, .battery, .ac] {
                let candidate = Self(mode: mode, source: source)
                if candidate.command == command { self = candidate; return }
            }
        }
        return nil
    }
}
public struct EnergyModeStatus: Sendable {
    public var battery: EnergyMode?
    public var ac: EnergyMode?
    public var highBattery: Bool?
    public var highAC: Bool?
    fileprivate var triStateSources = Set<PowerSource>()
    public var current: EnergyMode?
    public var hasHighPower: Bool { highBattery == true || highAC == true }
    public var usesEnergyModes: Bool { hasHighPower || battery == .high || ac == .high || current == .high }
    public func mode(for source: PowerSource) -> EnergyMode? { source == .battery ? battery : ac }
    public func supportsHigh(on source: PowerSource) -> Bool { (source == .battery ? highBattery : highAC) == true }
    public var lowPower: LowPowerStatus {
        LowPowerStatus(battery: battery.map { $0 == .low }, ac: ac.map { $0 == .low })
    }
    public init(battery: EnergyMode?, ac: EnergyMode?, highBattery: Bool?, highAC: Bool?, current: EnergyMode? = nil) {
        self.battery = battery; self.ac = ac; self.highBattery = highBattery; self.highAC = highAC; self.current = current
        triStateSources = Set(PowerSource.allCases.filter { ($0 == .battery ? highBattery : highAC) == true || self.mode(for: $0) == .high })
    }
    public var description: String {
        func value(_ mode: EnergyMode?) -> String { mode.map { String($0.rawValue) } ?? "unknown" }
        func capability(_ flag: Bool?) -> String { flag.map { $0 ? "1" : "0" } ?? "unknown" }
        return "battery=\(value(battery)) ac=\(value(ac)) highBattery=\(capability(highBattery)) highAC=\(capability(highAC)) current=\(value(current))"
    }
    public init(helperResponse: String) throws {
        let fields = helperResponse.split(whereSeparator: { $0.isWhitespace })
        let keys = ["battery=", "ac=", "highBattery=", "highAC=", "current="]
        guard fields.count == keys.count, zip(fields, keys).allSatisfy({ $0.hasPrefix($1) }) else {
            throw PowerModeError.invalidOutput("missing energy-mode fields")
        }
        func mode(_ text: Substring) throws -> EnergyMode? {
            if text == "unknown" { return nil }
            guard let raw = Int(text), let mode = EnergyMode(rawValue: raw), text == String(raw) else {
                throw PowerModeError.invalidOutput("invalid energy mode")
            }
            return mode
        }
        func flag(_ text: Substring) throws -> Bool? {
            if text == "unknown" { return nil }
            guard text == "0" || text == "1" else { throw PowerModeError.invalidOutput("invalid energy-mode capability") }
            return text == "1"
        }
        battery = try mode(fields[0].dropFirst(keys[0].count)); ac = try mode(fields[1].dropFirst(keys[1].count))
        highBattery = try flag(fields[2].dropFirst(keys[2].count)); highAC = try flag(fields[3].dropFirst(keys[3].count))
        current = try mode(fields[4].dropFirst(keys[4].count))
        triStateSources = Set(PowerSource.allCases.filter { ($0 == .battery ? highBattery : highAC) == true || self.mode(for: $0) == .high })
        guard (highBattery != true || battery != nil), (highAC != true || ac != nil) else {
            throw PowerModeError.invalidOutput("inconsistent energy-mode capability")
        }
    }
}

/// Persistent preferences share one journal for legacy low-power and tri-state operations.
/// Explicit restore preserves the complete original mode, including High Power Mode.
public final class PowerModeController {
    public typealias Runner = (_ arguments: [String], _ deadline: TimeInterval) throws -> String
    private let runner: Runner
    private let authorizeWrites: () -> Bool
    private let highPowerAvailability: (PowerSource) -> Bool?
    private let lock = NSLock()
    private struct Owned { let original: EnergyMode; var expected: EnergyMode; var previous: EnergyMode? }
    private var owned: [PowerSource: Owned] = [:]

    public init(runner: Runner? = nil, authorizeWrites: @escaping () -> Bool = { geteuid() == 0 },
                highPowerAvailability: @escaping (PowerSource) -> Bool? = PowerModeController.highPowerAvailable) {
        self.runner = runner ?? Self.runPMSet
        self.authorizeWrites = authorizeWrites; self.highPowerAvailability = highPowerAvailability
    }

    public static func highPowerAvailable(on source: PowerSource) -> Bool? {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL) else { return nil }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "IOPMFeatureIsAvailable") else { return nil }
        typealias Query = @convention(c) (CFString, CFString) -> Bool
        let query = unsafeBitCast(symbol, to: Query.self)
        let powerSource = source == .battery ? kIOPSBatteryPowerValue : kIOPSACPowerValue
        return query("HighPowerMode" as CFString, powerSource as CFString)
    }

    public static func parseEnergyCustom(_ output: String, highPowerAvailability: ((PowerSource) -> Bool?)? = nil) throws -> EnergyModeStatus {
        var current: PowerSource?
        var values: [PowerSource: EnergyMode] = [:]
        var triStateSources = Set<PowerSource>()
        var highSupport: [PowerSource: Bool] = [:]
        var headers = Set<PowerSource>()
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix(":") {
                switch line {
                case "Battery Power:": current = .battery
                case "AC Power:": current = .ac
                default: current = nil
                }
                if let current, !headers.insert(current).inserted {
                    throw PowerModeError.invalidOutput("duplicate power-source section")
                }
                continue
            }
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard let key = fields.first, key == "lowpowermode" || key == "powermode", let current else { continue }
            guard values[current] == nil else { throw PowerModeError.invalidOutput("duplicate power-mode setting") }
            let supported = highPowerAvailability?(current)
            let mode = try parseSetting(fields, allowLegacyHigh: supported == true)
            values[current] = mode; highSupport[current] = supported
            if key == "powermode" || supported == true { triStateSources.insert(current) }
        }
        var status = EnergyModeStatus(battery: values[.battery], ac: values[.ac],
            highBattery: highSupport[.battery], highAC: highSupport[.ac])
        status.triStateSources = triStateSources
        return status
    }
    public static func parseCustom(_ output: String) throws -> LowPowerStatus {
        try parseEnergyCustom(output).lowPower
    }
    public static func parseCurrent(_ output: String) throws -> EnergyMode? {
        var mode: EnergyMode?
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.first == "lowpowermode" || fields.first == "powermode" else { continue }
            guard mode == nil else { throw PowerModeError.invalidOutput("duplicate active power mode") }
            mode = try parseSetting(fields)
        }
        return mode
    }
    private static func parseSetting(_ fields: [Substring], allowLegacyHigh: Bool = false) throws -> EnergyMode {
        guard fields.count == 2, let raw = Int(fields[1]), let mode = EnergyMode(rawValue: raw),
              fields[0] == "powermode" || mode != .high || allowLegacyHigh else {
            throw PowerModeError.invalidOutput("invalid power-mode setting")
        }
        return mode
    }
    public func status() throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        return try read(deadline: ProcessInfo.processInfo.systemUptime + 2).lowPower
    }
    public func energyStatus() throws -> EnergyModeStatus {
        lock.lock(); defer { lock.unlock() }
        var status = try read(deadline: ProcessInfo.processInfo.systemUptime + 2)
        status.current = try? Self.parseCurrent(runner(["-g", "live"], ProcessInfo.processInfo.systemUptime + 2))
        return status
    }
    @discardableResult public func setEnabled(_ enabled: Bool, source: PowerSource? = nil) throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        return try apply(enabled ? .low : .automatic, source: source, lowPowerOnly: true).lowPower
    }
    @discardableResult public func setMode(_ mode: EnergyMode, source: PowerSource? = nil) throws -> EnergyModeStatus {
        lock.lock(); defer { lock.unlock() }
        var status = try apply(mode, source: source, lowPowerOnly: false)
        status.current = try? Self.parseCurrent(runner(["-g", "live"], ProcessInfo.processInfo.systemUptime + 2))
        return status
    }
    private func apply(_ mode: EnergyMode, source: PowerSource?, lowPowerOnly: Bool) throws -> EnergyModeStatus {
        guard authorizeWrites() else { throw PowerModeError.permissionRequired }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        let original = try read(deadline: deadline)
        if let source, original.mode(for: source) == nil {
            throw PowerModeError.unavailable("unobservable power mode for \(source.rawValue)")
        }
        let selected = source.map { [$0] } ?? PowerSource.allCases.filter { original.mode(for: $0) != nil }
        guard !selected.isEmpty else { throw PowerModeError.unavailable("no observable power mode") }
        guard mode != .high || selected.allSatisfy({ original.supportsHigh(on: $0) }) else {
            throw PowerModeError.unavailable("High Power Mode is not reported for the requested source")
        }
        var attempted: [PowerSource] = []
        var priorEntries: [PowerSource: Owned] = [:]
        do {
            for source in selected {
                guard let before = original.mode(for: source) else { continue }
                // Disabling Low Power Mode leaves an existing High Power Mode unchanged.
                let target = lowPowerOnly && mode == .automatic && before == .high ? before : mode
                guard before != target else { continue }
                if let existing = owned[source], existing.expected != before { owned.removeValue(forKey: source) }
                priorEntries[source] = owned[source]
                attempted.append(source)
                if owned[source] == nil { owned[source] = Owned(original: before, expected: target, previous: before) }
                else { owned[source]?.previous = before; owned[source]?.expected = target }
                try write(source, mode: target, status: original, deadline: deadline)
                guard try read(deadline: deadline).mode(for: source) == target else {
                    throw PowerModeError.invalidOutput("write readback mismatch for \(source.rawValue)")
                }
                owned[source]?.previous = nil
            }
            return try read(deadline: deadline)
        } catch {
            do {
                let recoveryDeadline = ProcessInfo.processInfo.systemUptime + 2
                if lowPowerOnly { try restoreOwned(deadline: recoveryDeadline, sources: selected) }
                else { try rollbackModeOperation(original, priorEntries: priorEntries, sources: attempted, deadline: recoveryDeadline) }
            }
            catch let cleanup { throw PowerModeError.unavailable("action failed: \(error.localizedDescription); cleanup incomplete: \(cleanup.localizedDescription)") }
            throw error
        }
    }
    private func rollbackModeOperation(_ before: EnergyModeStatus, priorEntries: [PowerSource: Owned],
        sources: [PowerSource], deadline: TimeInterval) throws {
        let present = try read(deadline: deadline)
        var failures: [String] = []
        for source in sources.reversed() {
            guard let entry = owned[source], let original = before.mode(for: source) else { continue }
            do {
                guard let current = present.mode(for: source) else { throw PowerModeError.unavailable("source disappeared during rollback") }
                if current == entry.expected || current == entry.previous {
                    if current != original {
                        try write(source, mode: original, status: present, deadline: deadline)
                        guard try read(deadline: deadline).mode(for: source) == original else {
                            throw PowerModeError.invalidOutput("energy-mode rollback readback mismatch")
                        }
                    }
                    owned[source] = priorEntries[source]
                } else { owned.removeValue(forKey: source) }
            } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { throw PowerModeError.unavailable(failures.joined(separator: "; ")) }
    }
    @discardableResult public func restore() throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        guard authorizeWrites() else { throw PowerModeError.permissionRequired }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        try restoreOwned(deadline: deadline)
        return try read(deadline: deadline).lowPower
    }
    private func restoreOwned(deadline: TimeInterval, sources: [PowerSource] = PowerSource.allCases) throws {
        guard !owned.isEmpty else { return }
        let present = try read(deadline: deadline)
        var errors: [String] = []
        for source in sources.reversed() {
            guard let entry = owned[source] else { continue }
            do {
                guard let current = present.mode(for: source) else { throw PowerModeError.unavailable("source disappeared: \(source.rawValue)") }
                if (current == entry.expected || current == entry.previous) && current != entry.original {
                    try write(source, mode: entry.original, status: present, deadline: deadline)
                    guard try read(deadline: deadline).mode(for: source) == entry.original else {
                        throw PowerModeError.invalidOutput("restore readback mismatch for \(source.rawValue)")
                    }
                }
                owned.removeValue(forKey: source)
            } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw PowerModeError.unavailable(errors.joined(separator: "; ")) }
    }
    private func read(deadline: TimeInterval) throws -> EnergyModeStatus {
        try Self.parseEnergyCustom(runner(["-g", "custom"], deadline), highPowerAvailability: highPowerAvailability)
    }
    private func write(_ source: PowerSource, mode: EnergyMode, status: EnergyModeStatus, deadline: TimeInterval) throws {
        guard mode != .high || status.supportsHigh(on: source) else {
            throw PowerModeError.unavailable("High Power Mode is no longer supported")
        }
        _ = try runner([source.flag, status.triStateSources.contains(source) ? "powermode" : "lowpowermode", String(mode.rawValue)], deadline)
    }
    private static func runPMSet(_ arguments: [String], deadline: TimeInterval) throws -> String {
        // Even an accidental internal caller cannot turn this runner into arbitrary pmset access.
        let allowed = arguments == ["-g", "custom"] || arguments == ["-g", "live"] ||
            (arguments.count == 3 && ["-b", "-c"].contains(arguments[0]) &&
             ((arguments[1] == "lowpowermode" && ["0", "1"].contains(arguments[2])) ||
              (arguments[1] == "powermode" && ["0", "1", "2"].contains(arguments[2]))))
        guard allowed, ProcessInfo.processInfo.systemUptime < deadline else {
            throw PowerModeError.unavailable("command or deadline rejected")
        }
        var template = Array("/private/tmp/opencharge-pmset.XXXXXX".utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw PowerModeError.unavailable("cannot create command output") }
        template.withUnsafeBufferPointer { _ = unlink($0.baseAddress!) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = output; process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            throw PowerModeError.unavailable("pmset command timed out")
        }
        process.waitUntilExit()
        try output.seek(toOffset: 0)
        let data = try output.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else {
            throw PowerModeError.invalidOutput("output exceeds bound or is not UTF-8")
        }
        guard process.terminationStatus == 0 else {
            let detail = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").prefix(256)
            throw PowerModeError.unavailable("pmset exit \(process.terminationStatus): \(detail)")
        }
        return text
    }
}
