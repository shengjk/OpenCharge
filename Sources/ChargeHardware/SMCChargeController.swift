// Independent fixed-key charge protocol. Production byte transport remains in SMCController.
import Foundation
import Darwin

public enum HardwareAction: String, Codable, Sendable {
 case allowCharge, inhibitCharge, forceDischarge, restore
}

/// Injectable transport; no caller-supplied key/value operation is exposed by apply.
public final class SMCChargeController {
 private let lock = NSLock()
 private let batteryPresent: Bool
 private let read: (String) throws -> [UInt8]?
 private let write: (String, [UInt8]) throws -> Void
 private let authorized: () -> Bool
 private let recoveryStore: ChargeRecoveryStore?
 private let bootSession: String
 private var recoveryLoaded: Bool
 private var interruptedRecoveryPending = false
 public init(batteryPresent: Bool, read: @escaping (String) throws -> [UInt8]?, write: @escaping (String, [UInt8]) throws -> Void, authorized: @escaping () -> Bool = { geteuid() == 0 }, recoveryStore: ChargeRecoveryStore? = nil, bootSession: String = "") {
  self.recoveryStore = recoveryStore; self.bootSession = bootSession; recoveryLoaded = recoveryStore == nil
  self.batteryPresent = batteryPresent; self.read = read; self.write = write; self.authorized = authorized
 }
 private func optionalKey(_ key: String) throws -> [UInt8]? { try read(key) }
 private func readKey(_ key: String) throws -> [UInt8] {
  guard let value = try read(key) else { throw HardwareError.unavailable("Missing SMC key: \(key)") }; return value
 }
 private func writeKey(_ key: String, _ value: [UInt8]) throws { try write(key, value) }
 public func capabilities() -> [String] {
  lock.lock(); defer { lock.unlock() }
  guard batteryPresent else { return ["chargeControl:unavailable", "internalBattery:absent"] }
  do {
   let profile = try detectedProfile()
   var values = ["chargeControl:" + profile.chargeKeys.joined(separator: "+"), "profile:recognizedFormat", "physicalEffects:unverified"]
   if let key = profile.dischargeKey { values.append("forceDischarge:" + key) }
   if !authorized() { values.append("writesRequirePrivilegedHelper") }
   return values
  } catch { return ["chargeControl:unavailable", "readOnly:" + error.localizedDescription] }
 }
    private struct OwnedWrite: Codable {
        let original: [UInt8]
        var expected: [UInt8]
        // Until readback succeeds, a rejected write may have left our previous value in place.
        var previous: [UInt8]?
    }
    // Never infer ownership from a key value left by another application.
    private var ownedWrites: [String: OwnedWrite] = [:]
    private var writeOrder: [String] = []

    private struct RecoveryRecord: Codable {
        let version: Int
        let bootSession: String
        let entries: [RecoveryEntry]
    }
    private struct RecoveryEntry: Codable { let key: String; let write: OwnedWrite }
    private func persist(excluding removedKey: String? = nil) throws {
        guard let recoveryStore else { return }
        let entries = writeOrder.filter { $0 != removedKey }.compactMap { key in
            ownedWrites[key].map { RecoveryEntry(key: key, write: $0) }
        }
        try recoveryStore.save(entries.isEmpty ? nil : JSONEncoder().encode(RecoveryRecord(version: 1, bootSession: bootSession, entries: entries)))
    }
    private func loadRecovery() throws {
        guard !recoveryLoaded, let recoveryStore else { return }
        guard UUID(uuidString: bootSession) != nil else { throw HardwareError.invalidData("Missing boot session identity") }
        if let data = try recoveryStore.load() {
            guard data.count <= 8192 else { throw HardwareError.invalidData("Recovery record too large") }
            let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
            guard record.version == 1, UUID(uuidString: record.bootSession) != nil, record.entries.count <= 6,
                  Set(record.entries.map(\.key)).count == record.entries.count else {
                throw HardwareError.invalidData("Invalid charge recovery record")
            }
            for entry in record.entries {
                let allowed = Self.allowedStates(entry.key)
                guard !allowed.isEmpty, allowed.contains(entry.write.original), allowed.contains(entry.write.expected),
                      entry.write.previous.map({ allowed.contains($0) }) ?? true else {
                    throw HardwareError.invalidData("Unrecognized charge recovery entry")
                }
            }
            if UUID(uuidString: record.bootSession) == UUID(uuidString: bootSession) {
                guard batteryPresent || record.entries.isEmpty else { throw HardwareError.unsupported("Recovery requires internal battery") }
                for entry in record.entries { ownedWrites[entry.key] = entry.write; writeOrder.append(entry.key) }
                interruptedRecoveryPending = !record.entries.isEmpty
            } else {
                // Firmware may have reset or changed at reboot. Never replay an earlier boot's writes.
                try recoveryStore.save(nil)
            }
        }
        recoveryLoaded = true
    }
    private static func allowedStates(_ key: String) -> [[UInt8]] {
        switch key {
        case "CHTE": return [[0, 0, 0, 0], [1, 0, 0, 0]]
        case "CH0B", "CH0C": return [[0], [2]]
        case "CHIE": return [[0], [8]]
        case "CH0J", "CH0I": return [[0], [1]]
        default: return []
        }
    }

    public func apply(_ action: HardwareAction) throws {
        lock.lock(); defer { lock.unlock() }
        guard authorized() else { throw HardwareError.permissionRequired }
        try loadRecovery()
        if action == .restore {
            try restoreOwnedWrites()
            interruptedRecoveryPending = false
            return
        }
        guard !interruptedRecoveryPending else { throw HardwareError.unavailable("Interrupted charge recovery pending") }
        guard batteryPresent else { throw HardwareError.unsupported("No internal battery") }
        let profile = try detectedProfile()
        if action == .forceDischarge, profile.dischargeKey == nil {
            throw HardwareError.unsupported("No recognized discharge key")
        }
        // Build and validate the whole plan before the first write. No caller may supply raw keys.
        var plan: [(String, [UInt8])] = []
        if action != .forceDischarge, let key = profile.dischargeKey {
            plan.append((key, [0]))
        }
        let inhibit = action == .inhibitCharge || action == .forceDischarge
        for key in profile.chargeKeys {
            plan.append((key, key == "CHTE" ? [inhibit ? 1 : 0, 0, 0, 0] : [inhibit ? 2 : 0]))
        }
        if action == .forceDischarge, let key = profile.dischargeKey {
            plan.append((key, [key == "CHIE" ? 8 : 1]))
        }
        let original = try plan.map { operation -> (String, [UInt8]) in
            let key = operation.0, current = try readKey(key)
            let allowed = Self.allowedStates(key)
            guard allowed.contains(current) else { throw HardwareError.invalidData("SMC state changed before plan: \(key)") }
            return (key, current)
        }
        do {
            for (index, operation) in plan.enumerated() {
                let (key, value) = operation
                let before = original[index].1
                guard value != before else { continue }
                if let existing = ownedWrites[key], before != existing.expected {
                    // Another controller changed this key. Start a new ownership interval.
                    ownedWrites.removeValue(forKey: key)
                    writeOrder.removeAll { $0 == key }
                }
                if ownedWrites[key] == nil {
                    ownedWrites[key] = OwnedWrite(original: before, expected: value, previous: before)
                    writeOrder.append(key)
                } else {
                    ownedWrites[key]?.previous = before
                    ownedWrites[key]?.expected = value
                }
                // Write-ahead record covers both a crash before write and before readback.
                try persist()
                try writeKey(key, value)
                guard try readKey(key) == value else {
                    throw HardwareError.invalidData("SMC readback mismatch: \(key)")
                }
                // Keep the conservative previous value on disk until the next transaction.
                // It is harmless after readback and avoids a second fsync on every heartbeat.
                ownedWrites[key]?.previous = nil
            }
        } catch {
            // On failure release this controller's entire session, preserving externally changed keys.
            // Keep failed entries so a living helper's watchdog can retry; surface cleanup failures.
            do { try restoreOwnedWrites() }
            catch let cleanupError {
                throw HardwareError.invalidData("Action failed: \(error.localizedDescription); cleanup incomplete: \(cleanupError.localizedDescription)")
            }
            throw error
        }
    }

    /// Restores only owned writes, including a validated same-boot interrupted record.
    /// Compare-and-restore is best effort; AppleSMC supplies no atomic compare-and-swap.
    private func restoreOwnedWrites() throws {
        var failures: [String] = []
        for key in writeOrder.reversed() {
            guard let entry = ownedWrites[key] else { continue }
            do {
                let current = try readKey(key)
                if (current == entry.expected || current == entry.previous) && current != entry.original {
                    try writeKey(key, entry.original)
                    guard try readKey(key) == entry.original else {
                        throw HardwareError.invalidData("Restore readback mismatch: \(key)")
                    }
                }
                // A different present value belongs to an external writer: leave it alone.
                try persist(excluding: key)
                ownedWrites.removeValue(forKey: key)
            } catch { failures.append("\(key): \(error.localizedDescription)") }
        }
        writeOrder.removeAll { ownedWrites[$0] == nil }
        if !failures.isEmpty { throw HardwareError.invalidData(failures.joined(separator: "; ")) }
    }

    private struct Profile { var chargeKeys: [String]; var dischargeKey: String? }

    private func detectedProfile() throws -> Profile {
        let chargeKeys: [String]
        if let value = try optionalKey("CHTE") {
            guard [[UInt8](repeating: 0, count: 4), [1, 0, 0, 0]].contains(value) else {
                throw HardwareError.invalidData("Unrecognized CHTE format or state")
            }
            chargeKeys = ["CHTE"]
        } else {
            for key in ["CH0B", "CH0C"] {
                guard let value = try optionalKey(key), [[UInt8](arrayLiteral: 0), [2]].contains(value) else {
                    throw HardwareError.unsupported("Missing or unrecognized \(key)")
                }
            }
            chargeKeys = ["CH0B", "CH0C"]
        }
        var dischargeKey: String?
        for (key, enabled) in [("CHIE", UInt8(8)), ("CH0J", UInt8(1)), ("CH0I", UInt8(1))] {
            if let value = try optionalKey(key) {
                guard value == [0] || value == [enabled] else {
                    throw HardwareError.invalidData("Unrecognized \(key) format or state")
                }
                dischargeKey = key; break
            }
        }
        return Profile(chargeKeys: chargeKeys, dischargeKey: dischargeKey)
    }

}
