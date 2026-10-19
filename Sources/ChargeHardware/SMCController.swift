// Independent implementation of the 80-byte AppleSMC ABI documented by beltex/SMCKit (MIT).
// Charge-control semantics: actuallymentor/battery (MIT). See docs/licenses and docs/HARDWARE.md.
import Foundation
import IOKit
import Darwin

/// A narrow, serialized SMC client. Creating this object and inspecting capabilities are read-only.
/// Only a privileged process may call apply. Missing internal batteries and unknown key formats/states fail closed.
public struct SMCTemperatureReading: Sendable {
    public let dataType: String
    public let bytes: [UInt8]
    public var celsius: Double? { TelemetryMath.smcTemperatureCelsius(dataType: dataType, bytes: bytes) }
}
public final class SMCController {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    public let model: String
    private let internalBattery: Bool
    private let recoveryStore: ChargeRecoveryStore?
    private let bootSession: String
    private lazy var chargeController = SMCChargeController(batteryPresent: internalBattery,
        read: { [unowned self] in try self.optionalKey($0) },
        write: { [unowned self] in try self.writeKey($0, $1) }, recoveryStore: recoveryStore, bootSession: bootSession)

    public init(recoveryStore: ChargeRecoveryStore? = nil, bootSession: String = "") throws {
        self.recoveryStore = recoveryStore; self.bootSession = bootSession
        model = try HardwareIdentity.model()
        // A real internal battery and recognized key layout determine eligibility.
        // Model names do not prove firmware behavior and are retained only for diagnostics.
        internalBattery = (try? BatteryReader.read()) != nil
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw HardwareError.unavailable("AppleSMC") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw HardwareError.driver(result, 0) }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    /// Reports observed readable keys separately from recognized key profiles.
    public func capabilities() -> [String] {
        lock.lock(); defer { lock.unlock() }
        var values = ["model:\(model)", "internalBattery:\(internalBattery ? "present" : "absent")"]
        if let bytes = try? optionalKey("ACLC"), bytes.count == 1, bytes[0] <= 4 { values.append("magSafeKey:ACLC") }
        return values + chargeController.capabilities()
    }

    /// Fixed, read-only temperature key. This does not inspect or change charge control.
    public func batteryTemperatureReading() throws -> SMCTemperatureReading {
        lock.lock(); defer { lock.unlock() }
        let metadata = try call("TB0T", command: 9)
        let count = metadata.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 28, as: UInt32.self)) }
        guard (1...32).contains(count) else { throw HardwareError.invalidData("TB0T length") }
        let type = metadata.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self) }
        let name = String(bytes: [UInt8(truncatingIfNeeded: type >> 24), UInt8(truncatingIfNeeded: type >> 16), UInt8(truncatingIfNeeded: type >> 8), UInt8(truncatingIfNeeded: type)], encoding: .ascii) ?? "unknown"
        let output = try call("TB0T", command: 5, count: count)
        return SMCTemperatureReading(dataType: name, bytes: Array(output[48..<(48 + count)]))
    }

    /// ACLC capability is separate from the charge-control protocol profile.
    public func magSafeController(recoveryStore: ChargeRecoveryStore? = nil, bootSession: String = "") -> MagSafeController {
        MagSafeController(read: { [self] in
            lock.lock(); defer { lock.unlock() }; return try optionalKey("ACLC")
        }, write: { [self] bytes in
            lock.lock(); defer { lock.unlock() }
            guard geteuid() == 0 else { throw HardwareError.permissionRequired }
            guard bytes.count == 1, bytes[0] <= 4 else { throw HardwareError.invalidData("ACLC bounds") }
            try writeKey("ACLC", bytes)
        }, recoveryStore: recoveryStore, bootSession: bootSession)
    }

    public func apply(_ action: HardwareAction) throws {
        lock.lock(); defer { lock.unlock() }
        try chargeController.apply(action)
    }

    private func optionalKey(_ key: String) throws -> [UInt8]? {
        do { return try readKey(key) }
        catch HardwareError.driver(let code, let result) where code == KERN_SUCCESS && result == 132 { return nil }
    }

    private func info(_ key: String) throws -> Int {
        let output = try call(key, command: 9)
        let size = output.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self) }
        guard (1...32).contains(size) else { throw HardwareError.invalidData("SMC length: \(key)") }
        return Int(size)
    }

    private func readKey(_ key: String) throws -> [UInt8] {
        let count = try info(key)
        let output = try call(key, command: 5, count: count)
        return Array(output[48..<(48 + count)])
    }

    private func writeKey(_ key: String, _ bytes: [UInt8]) throws {
        guard try info(key) == bytes.count else { throw HardwareError.invalidData("SMC size changed: \(key)") }
        _ = try call(key, command: 6, count: bytes.count, bytes: bytes)
    }

    private func call(_ key: String, command: UInt8, count: Int = 0, bytes: [UInt8] = []) throws -> [UInt8] {
        // Canonical C ABI: key@0, keyInfo.size@28, result@40, command@42, bytes@48; total 80.
        // Raw initialized buffers avoid Swift's unstable nested-struct memory layout.
        guard key.utf8.count == 4, count <= 32, bytes.count <= 32 else {
            throw HardwareError.invalidData("SMC request bounds")
        }
        var input = [UInt8](repeating: 0, count: 80)
        input.withUnsafeMutableBytes { pointer in
            pointer.storeBytes(of: key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }, as: UInt32.self)
            pointer.storeBytes(of: UInt32(count), toByteOffset: 28, as: UInt32.self)
        }
        input[42] = command
        for (index, byte) in bytes.enumerated() { input[48 + index] = byte }
        var output = [UInt8](repeating: 0, count: 80)
        var size = 80
        let result = input.withUnsafeBytes { inputPointer in
            output.withUnsafeMutableBytes { outputPointer in
                IOConnectCallStructMethod(connection, 2, inputPointer.baseAddress, 80,
                                          outputPointer.baseAddress, &size)
            }
        }
        guard result == KERN_SUCCESS, size == 80, output[40] == 0 else {
            throw HardwareError.driver(result, output[40])
        }
        return output
    }
}
