import Foundation
import Darwin

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
    fileprivate subscript(_ source: PowerSource) -> Bool? { source == .battery ? battery : ac }
}
public enum PowerModeError: Error, LocalizedError {
    case invalidOutput(String), unavailable(String), permissionRequired
    public var errorDescription: String? {
        switch self {
        case .invalidOutput(let detail): return "Invalid pmset output: \(detail)"
        case .unavailable(let detail): return "Power mode unavailable: \(detail)"
        case .permissionRequired: return "Changing Low Power Mode requires the privileged helper."
        }
    }
}

/// Persistent user preference: neither app shutdown nor the charging watchdog calls restore.
/// Explicit restore uses this instance's in-memory journal, which does not survive helper restart.
public final class PowerModeController {
    public typealias Runner = (_ arguments: [String], _ deadline: TimeInterval) throws -> String
    private let runner: Runner
    private let authorizeWrites: () -> Bool
    private let lock = NSLock()
    private struct Owned { let original: Bool; var expected: Bool; var previous: Bool? }
    private var owned: [PowerSource: Owned] = [:]

    public init(runner: Runner? = nil, authorizeWrites: @escaping () -> Bool = { geteuid() == 0 }) {
        self.runner = runner ?? Self.runPMSet
        self.authorizeWrites = authorizeWrites
    }

    /// Strict, pure parsing. Missing sources/keys remain unknown; duplicate or nonboolean keys fail.
    public static func parseCustom(_ output: String) throws -> LowPowerStatus {
        var current: PowerSource?
        var values: [PowerSource: Bool] = [:]
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
            guard fields.first == "lowpowermode", let current else { continue }
            guard fields.count == 2, let mode = Int(fields[1]), mode == 0 || mode == 1,
                  values[current] == nil else { throw PowerModeError.invalidOutput("lowpowermode must appear once as 0 or 1") }
            values[current] = mode == 1
        }
        return LowPowerStatus(battery: values[.battery], ac: values[.ac])
    }
    public func status() throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        return try read(deadline: ProcessInfo.processInfo.systemUptime + 2)
    }
    /// Sets the requested source, or all observable supported sources when source is nil.
    /// A specifically requested missing source fails instead of changing another source.
    @discardableResult public func setEnabled(_ enabled: Bool, source: PowerSource? = nil) throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        guard authorizeWrites() else { throw PowerModeError.permissionRequired }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        let original = try read(deadline: deadline)
        if let source, original[source] == nil {
            throw PowerModeError.unavailable("unobservable lowpowermode setting for \(source.rawValue)")
        }
        let selectedSources = source.map { [$0] } ?? PowerSource.allCases
        guard original.battery != nil || original.ac != nil else {
            throw PowerModeError.unavailable("no observable lowpowermode setting")
        }
        do {
            for source in selectedSources {
                guard let before = original[source], before != enabled else { continue }
                if let existing = owned[source], existing.expected != before { owned.removeValue(forKey: source) }
                if owned[source] == nil { owned[source] = Owned(original: before, expected: enabled, previous: before) }
                else { owned[source]?.previous = before; owned[source]?.expected = enabled }
                try write(source, enabled: enabled, deadline: deadline)
                guard try read(deadline: deadline)[source] == enabled else {
                    throw PowerModeError.invalidOutput("write readback mismatch for \(source.rawValue)")
                }
                owned[source]?.previous = nil
            }
            return try read(deadline: deadline)
        } catch {
            do { try restoreOwned(deadline: ProcessInfo.processInfo.systemUptime + 2, sources: selectedSources) }
            catch let cleanup { throw PowerModeError.unavailable("action failed: \(error.localizedDescription); cleanup incomplete: \(cleanup.localizedDescription)") }
            throw error
        }
    }
    @discardableResult public func restore() throws -> LowPowerStatus {
        lock.lock(); defer { lock.unlock() }
        guard authorizeWrites() else { throw PowerModeError.permissionRequired }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        try restoreOwned(deadline: deadline)
        return try read(deadline: deadline)
    }
    private func restoreOwned(deadline: TimeInterval, sources: [PowerSource] = PowerSource.allCases) throws {
        // No ownership means no write and no unnecessary subprocess.
        guard !owned.isEmpty else { return }
        let present = try read(deadline: deadline)
        var errors: [String] = []
        for source in sources.reversed() {
            guard let entry = owned[source] else { continue }
            do {
                guard let current = present[source] else { throw PowerModeError.unavailable("source disappeared: \(source.rawValue)") }
                if (current == entry.expected || current == entry.previous) && current != entry.original {
                    try write(source, enabled: entry.original, deadline: deadline)
                    guard try read(deadline: deadline)[source] == entry.original else {
                        throw PowerModeError.invalidOutput("restore readback mismatch for \(source.rawValue)")
                    }
                }
                // A third-party preference change is not ours to restore.
                owned.removeValue(forKey: source)
            } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw PowerModeError.unavailable(errors.joined(separator: "; ")) }
    }
    private func read(deadline: TimeInterval) throws -> LowPowerStatus {
        try Self.parseCustom(runner(["-g", "custom"], deadline))
    }
    private func write(_ source: PowerSource, enabled: Bool, deadline: TimeInterval) throws {
        _ = try runner([source.flag, "lowpowermode", enabled ? "1" : "0"], deadline)
    }
    private static func runPMSet(_ arguments: [String], deadline: TimeInterval) throws -> String {
        // Even an accidental internal caller cannot turn this runner into arbitrary pmset access.
        let allowed = arguments == ["-g", "custom"] ||
            (arguments.count == 3 && ["-b", "-c"].contains(arguments[0]) &&
             arguments[1] == "lowpowermode" && ["0", "1"].contains(arguments[2]))
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
