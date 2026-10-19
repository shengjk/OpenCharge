import Foundation
import AppKit
import Darwin
import ChargeCore

enum EnergyQueryResult: Sendable {
 case available([EnergyImpact])
 case unavailable(String)
}
enum SystemEnergyReader {
 // Observed arm64 ABI: two 32-bit scalar arguments; autoreleased ObjC return.
 // This is a private OS symbol, so failure is an ordinary unavailable state.
 private typealias Query = @convention(c) (UInt32, UInt32) -> Unmanaged<AnyObject>?
 private static let library = dlopen("/usr/lib/libsystemstats.dylib", RTLD_LAZY | RTLD_LOCAL)
 static func read(threshold: Double) -> EnergyQueryResult {
  autoreleasepool {
   guard let library, let symbol = dlsym(library, "systemstats_get_top_coalitions") else { return .unavailable("此系统未提供应用能耗接口") }
   let query = unsafeBitCast(symbol, to: Query.self)
   guard let object = query(30, 1000)?.takeUnretainedValue(), let dictionary = object as? NSDictionary else { return .unavailable("系统暂未提供应用能耗数据") }
   guard let identifiers = dictionary["bundle_identifiers"] as? [String],
         let impacts = dictionary["energy_impacts"] as? [Double],
         let selected = try? EnergyImpactSelection.select(bundleIdentifiers: identifiers, impacts: impacts, threshold: threshold) else { return .unavailable("系统应用能耗数据格式不受支持") }
   return .available(selected)
  }
 }
 static func cpuPercent(pid: Int32) -> Double? {
  guard pid > 0 else { return nil }
  let process = Process(), pipe = Pipe(), done = DispatchSemaphore(value: 0)
  process.executableURL = URL(fileURLWithPath: "/bin/ps")
  process.arguments = ["-p", String(pid), "-o", "%cpu="]
  process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
  process.terminationHandler = { _ in done.signal() }
  do { try process.run() } catch { return nil }
  guard done.wait(timeout: .now() + 2) == .success else { process.terminate(); return nil }
  guard process.terminationStatus == 0,
        let data = try? pipe.fileHandleForReading.read(upToCount: 128),
        let text = String(data: data, encoding: .utf8),
        let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, value >= 0 else { return nil }
  return value
 }
}

@MainActor final class EnergyMonitor: ObservableObject {
 struct Row: Identifiable {
  let id: String; let name: String; let icon: NSImage?; let impact: Double; let cpuPercent: Double?
 }
 @Published private(set) var rows: [Row] = []
 @Published private(set) var status = "等待应用能耗数据"
 @Published private(set) var updatedAt: Date?
 @Published var paused = false
 private var pending = false
 private var lastAttempt: Date?
 private var queuedSensitivity: EnergySensitivity?
 func refresh(sensitivity: EnergySensitivity, force: Bool = false) {
  guard !paused else { return }
  if pending { if force { queuedSensitivity = sensitivity }; return }
  guard force || lastAttempt.map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { return }
  pending = true; lastAttempt = Date()
  Task {
   let result = await Task.detached(priority: .utility) { SystemEnergyReader.read(threshold: sensitivity.threshold) }.value
   guard !paused else { pending = false; queuedSensitivity = nil; return }
   switch result {
   case .unavailable(let message): rows = []; status = message; updatedAt = nil
   case .available(let candidates):
    // Resolve on the main actor. Missing/non-GUI applications do not backfill
    // from outside the selected top-five energy candidates.
    let apps = candidates.compactMap { candidate -> (EnergyImpact, NSRunningApplication)? in
     guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier).first else { return nil }
     return (candidate, app)
    }
    let pids = apps.map { $0.1.processIdentifier }
    let cpu = await Task.detached(priority: .utility) { pids.map { SystemEnergyReader.cpuPercent(pid: $0) } }.value
    guard !paused else { pending = false; queuedSensitivity = nil; return }
    rows = zip(apps, cpu).compactMap { pair, percent in
     guard let percent else { return nil }
     return Row(id: pair.0.bundleIdentifier, name: pair.1.localizedName ?? "未知应用", icon: pair.1.icon, impact: pair.0.impact, cpuPercent: percent)
    }
    status = rows.isEmpty ? "当前没有可显示的高耗能应用" : "按系统能耗排序 · CPU 为辅助读数"
    updatedAt = Date()
   }
   pending = false
   if let queued = queuedSensitivity { queuedSensitivity = nil; refresh(sensitivity: queued, force: true) }
  }
 }
}
