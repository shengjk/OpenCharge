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
    private let firmwareStore: ChargeRecoveryStore?
    private let bootSession: String
    private lazy var keyIO = SMCKeyIO { [unowned self] key, command, count, bytes in
        try self.call(key, command: command, count: count, bytes: bytes)
    }
    private var processArchitecture: String {
        #if arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }
    private lazy var chargeController = SMCChargeController(batteryPresent: internalBattery,
        platform: SMCChargePlatform.selected(model: model, architecture: processArchitecture),
        read: { [unowned self] in try self.optionalKey($0) },
        write: { [unowned self] in try self.writeKey($0, $1) }, recoveryStore: recoveryStore, bootSession: bootSession)

    private var firmwareEligible: Bool { SMCFirmwareProbe.eligible(model: model, architecture: processArchitecture, internalBattery: internalBattery) }
    private lazy var firmwareController = SMCFirmwareChargeController(eligibleHost: firmwareEligible, batteryPresent: internalBattery,
        read: { [unowned self] in try self.keyIO.optionalRead($0) },
        write: { [unowned self] in try self.keyIO.writeFirmwareByte($0, value: $1) },
        recoveryStore: firmwareStore, bootSession: bootSession)
    private lazy var firmwareInflow = FirmwareInflowAssertion()
    private lazy var chargeSession = ChargeBackendSession(
        ordinaryPending: { [unowned self] in try self.recoveryStore?.load() != nil },
        firmwarePending: { [unowned self] in try self.firmwareStore?.load() != nil },
        ordinary: { [unowned self] in try self.chargeController.apply($0) }, firmwareEligible: firmwareEligible,
        firmwareInspect: { [unowned self] in _ = try self.firmwareController.inspect() },
        firmwareLimit: { [unowned self] in try self.firmwareController.setLimit($0) },
        firmwareInhibit: { [unowned self] in try self.firmwareController.inhibitCharging() },
        firmwareExit: { [unowned self] in try self.firmwareController.finishExit(limit: $0) },
        firmwareRestore: { [unowned self] in try self.firmwareController.restore() }, inflow: firmwareInflow)

    public init(recoveryStore: ChargeRecoveryStore? = nil, firmwareStore: ChargeRecoveryStore? = nil, bootSession: String = "") throws {
        self.recoveryStore = recoveryStore; self.firmwareStore = firmwareStore; self.bootSession = bootSession
        model = try HardwareIdentity.model()
        // Ordinary charge profiles require an internal battery and recognized key layout.
        // Numeric firmware probing additionally requires an explicitly selected model.
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
        let numericStatus = try? firmwareStatusUnlocked()
        if let status = numericStatus {
            values.append("firmwareRead:CH0B+BCLM")
            values.append("firmwareLimit:\(status.limit)")
            values.append("firmwareCharging:\(status.chargingAllowed.map { $0 ? "allowed" : "inhibited" } ?? "unknown")")
        } else { values.append("firmwareRead:unavailable") }
        values.append(numericStatus != nil && firmwareStore != nil ? "firmwareWrite:fixedV1" : "firmwareWrite:unavailable")
        // Compiled request protocol, not evidence that powerd honors the assertion.
        values.append(numericStatus != nil && firmwareStore != nil ? "firmwareDischarge:inflowV1" : "firmwareDischarge:unavailable")
        return values + chargeController.capabilities()
    }

    /// Fixed, read-only temperature key. This does not inspect or change charge control.
    public func batteryTemperatureReading() throws -> SMCTemperatureReading {
        lock.lock(); defer { lock.unlock() }
        let reading = try keyIO.read("TB0T")
        return SMCTemperatureReading(dataType: reading.dataType, bytes: reading.bytes)
    }

    /// Explicit numeric-profile observation only; never loads a recovery journal.
    /// Architecture is the current process architecture; the exact physical model
    /// check also prevents Rosetta on an Apple Silicon model from selecting Intel.
    public func firmwareStatus() throws -> FirmwareChargeStatus {
        lock.lock(); defer { lock.unlock() }
        return try firmwareStatusUnlocked()
    }
    private func firmwareStatusUnlocked() throws -> FirmwareChargeStatus {
        try SMCFirmwareProbe.inspect(model: model, architecture: processArchitecture, internalBattery: internalBattery,
            read: { [self] in try keyIO.optionalRead($0) })
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
        guard geteuid() == 0 else { throw HardwareError.permissionRequired }
        try chargeSession.apply(action)
    }

    public func setFirmwareLimit(_ percent: Int) throws {
        lock.lock(); defer { lock.unlock() }; try requireFirmwareWriter(); try chargeSession.setFirmwareLimit(percent)
    }
    public func inhibitFirmware() throws {
        lock.lock(); defer { lock.unlock() }; try requireFirmwareWriter(); try chargeSession.inhibitFirmware()
    }
    public func dischargeFirmware() throws {
        lock.lock(); defer { lock.unlock() }; try requireFirmwareWriter(); try chargeSession.dischargeFirmware()
    }
    public func finishFirmwareExit(_ percent: Int) throws {
        lock.lock(); defer { lock.unlock() }; try requireFirmwareWriter(); try chargeSession.finishFirmwareExit(percent)
    }

    private func requireFirmwareWriter() throws {
        guard geteuid() == 0 else { throw HardwareError.permissionRequired }
        guard firmwareStore != nil else { throw HardwareError.unavailable("Firmware recovery store required") }
    }

    private func optionalKey(_ key: String) throws -> [UInt8]? {
        try keyIO.optionalRead(key)?.bytes
    }

    private func writeKey(_ key: String, _ bytes: [UInt8]) throws {
        try keyIO.write(key, bytes: bytes)
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
