import Foundation
import ChargeHardware
import ChargeCore

private final class PowerGraphFixtureReader: @unchecked Sendable {
 private let lock = NSLock()
 private var calls = 0
 private var failNext = false
 let firstGate: DispatchSemaphore?
 init(blockFirst: Bool = false) { firstGate = blockFirst ? DispatchSemaphore(value: 0) : nil }
 var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
 func fail() { lock.lock(); failNext = true; lock.unlock() }
 func read() throws -> BatteryReading {
  lock.lock(); calls += 1; let count = calls; let fail = failNext; failNext = false; lock.unlock()
  if count == 1, let firstGate {
   guard firstGate.wait(timeout: .now() + 5) == .success else { throw CocoaError(.userCancelled) }
  }
  if fail { throw CocoaError(.fileReadUnknown) }
  return BatteryReading(date: Date(timeIntervalSince1970: 1000 + Double(count)), percent: 70,
   voltageMV: 12000, connected: true, charging: false, systemPowerW: Double(count) * 5,
   remainingCapacityMAH: 2000, designVoltageMV: 10000)
 }
}

@MainActor private final class PowerGraphFixtureSchedule {
 var intervals: [TimeInterval] = []
 var ticks: [@MainActor () -> Void] = []
 var cancelled = 0
 func install(_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> () -> Void {
  intervals.append(interval); ticks.append(tick)
  return { self.cancelled += 1 }
 }
}

@MainActor func powerGraphModeChecks() async throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let configurationBytes = try? Data(contentsOf: Configuration.url)
 let historyURL = Configuration.directory.appendingPathComponent("history.json")
 let historyBytes = try? Data(contentsOf: historyURL)
 let suite = "org.opencharge.power-graph-fixture." + UUID().uuidString
 let defaults = UserDefaults(suiteName: suite)!
 defer { defaults.removePersistentDomain(forName: suite) }
 let preferences = PowerGraphPreferences(defaults: defaults)
 precondition(preferences.mode == .average && preferences.period == .fifteen)
 precondition(defaults.object(forKey: PowerGraphPreferences.modeKey) == nil)
 preferences.mode = .instant; preferences.period = .thirty
 let reopened = PowerGraphPreferences(defaults: defaults)
 precondition(reopened.mode == .instant && reopened.period == .thirty)
 defaults.set(900, forKey: PowerGraphPreferences.modeKey); defaults.set("invalid", forKey: PowerGraphPreferences.periodKey)
 let invalid = PowerGraphPreferences(defaults: defaults)
 precondition(invalid.mode == .average && invalid.period == .fifteen)
 precondition(defaults.integer(forKey: PowerGraphPreferences.modeKey) == 900, "loading must not rewrite unknown saved values")
 defaults.set("retained", forKey: "unrelatedPreference")
 AppPreferenceReset.removeOverrides(from: defaults); reopened.reloadAfterReset()
 precondition(reopened.mode == .average && reopened.period == .fifteen && defaults.string(forKey: "unrelatedPreference") == "retained")
 let end = Date(timeIntervalSince1970: 1000)
 let reading = BatteryReading(date: end, percent: 70, voltageMV: 12000, connected: true, charging: false,
  systemPowerW: 20, remainingCapacityMAH: 2000, designVoltageMV: 10000)
 let history = [-120.0,-60].map { offset in
  HistoryPoint(date: end.addingTimeInterval(offset), percent: 70, temperature: nil, watts: nil,
   reason: "fixture", systemWatts: offset == -120 ? 5 : 10)
 }
 let data = PowerConsumptionSnapshot(reading: reading, history: history, minutes: 15)
 precondition(data.selectedWatts(.instant) == 20 && data.selectedMinutes(.instant) == 60)
 precondition(data.selectedWatts(.average) == 50.0 / 3 && abs((data.selectedMinutes(.average) ?? 0) - 72) < 0.000001)
 let missing = PowerConsumptionSnapshot(reading: nil, history: [], minutes: 15, end: end)
 precondition(missing.selectedWatts(.average) == nil && missing.selectedMinutes(.instant) == nil)
 func wait(_ condition: @MainActor () -> Bool) async throws {
  for _ in 0..<600 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
  preconditionFailure("power graph fixture did not settle")
 }
 let source = PowerGraphFixtureReader(), schedule = PowerGraphFixtureSchedule()
 let monitor = PowerGraphMonitor(read: { try source.read() }, schedule: schedule.install)
 monitor.configure(active: false, mode: .average)
 precondition(source.count == 0 && schedule.intervals.isEmpty)
 monitor.configure(active: true, mode: .average); try await wait { !monitor.loading }
 precondition(schedule.intervals == [10] && source.count == 1 && monitor.attempted && monitor.reading?.systemPowerW == 5)
 let oldTick = schedule.ticks[0]
 monitor.configure(active: true, mode: .average)
 precondition(schedule.intervals.count == 1 && source.count == 1)
 monitor.configure(active: true, mode: .instant); try await wait { !monitor.loading }
 precondition(schedule.intervals == [10,2] && schedule.cancelled == 1 && source.count == 2)
 oldTick(); try await Task.sleep(nanoseconds: 20_000_000)
 precondition(source.count == 2, "cancelled timer callbacks must not read under a new mode")
 source.fail(); schedule.ticks.last!(); try await wait { !monitor.loading }
 precondition(monitor.reading == nil && monitor.error != nil && monitor.attempted)
 schedule.ticks.last!(); try await wait { !monitor.loading }
 precondition(monitor.error == nil && monitor.reading?.systemPowerW == 20)
 let frozenDate = monitor.reading?.date
 monitor.stop(); schedule.ticks.last!(); try await Task.sleep(nanoseconds: 20_000_000)
 precondition(!monitor.active && source.count == 4 && monitor.reading?.date == frozenDate && schedule.cancelled == 2)
 monitor.configure(active: true, mode: .instant); try await wait { !monitor.loading }
 precondition(source.count == 5 && schedule.intervals.last == 2)
 monitor.stop()
 // A slow old read cannot overwrite a later mode. A cancelled queued read must
 // not call its provider after focus is lost; only the new active request runs.
 let blocked = PowerGraphFixtureReader(blockFirst: true), queuedSchedule = PowerGraphFixtureSchedule()
 defer { blocked.firstGate?.signal() }
 let queued = PowerGraphMonitor(read: { try blocked.read() }, schedule: queuedSchedule.install)
 queued.configure(active: true, mode: .average); try await wait { blocked.count == 1 }
 queued.configure(active: true, mode: .instant); queued.stop()
 queued.configure(active: true, mode: .instant)
 blocked.firstGate?.signal(); try await wait { !queued.loading }
 precondition(blocked.count == 2 && queued.reading?.systemPowerW == 10 && queued.active)
 queued.stop()
 let disabled = PowerGraphMonitor(schedule: schedule.install)
 disabled.configure(active: true, mode: .instant)
 precondition(!disabled.active && !disabled.loading && !disabled.attempted)
 var released: PowerGraphMonitor? = PowerGraphMonitor(read: { try source.read() }, schedule: schedule.install)
 weak var weakReleased = released
 released?.configure(active: true, mode: .instant); try await wait { released?.loading == false }
 let cancellations = schedule.cancelled
 released = nil
 precondition(weakReleased == nil && schedule.cancelled == cancellations + 1)
 precondition((try? Data(contentsOf: Configuration.url)) == configurationBytes)
 precondition((try? Data(contentsOf: historyURL)) == historyBytes, "display sampling must not persist history")
 print("PASS power graph modes: persisted defaults/validation/reset, selected runtime source, 10s/2s scheduling, inactive/focus/re-entry gates, stale timer/read suppression, queued cancellation, failure/retry and lifetime cleanup; injected read-only providers only")
}
