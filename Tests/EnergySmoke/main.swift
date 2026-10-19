import Foundation
import Darwin
import ChargeCore

// Local read-only smoke test; output deliberately excludes app identities.
let start = Date()
let result = SystemEnergyReader.read(threshold: EnergySensitivity.balanced.threshold)
switch result {
case .available(let rows): print("energy query available; selected rows=\(rows.count)")
case .unavailable(let reason): print("energy query unavailable: \(reason)")
}
guard Date().timeIntervalSince(start) < 10 else { fatalError("read-only query took unexpectedly long") }
guard SystemEnergyReader.cpuPercent(pid: getpid()) != nil else { fatalError("self CPU query failed") }
guard SystemEnergyReader.cpuPercent(pid: -1) == nil else { fatalError("invalid PID accepted") }
print("read-only energy/CPU smoke passed; no hardware IPC used")
