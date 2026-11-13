import Foundation
import ChargeCore
import ChargeHardware

private final class SampleFixture: @unchecked Sendable {
 private let lock = NSLock()
 private var calls = 0
 private var gate: DispatchSemaphore?
 private var failure = false
 func blockNext() -> DispatchSemaphore {
  let gate = DispatchSemaphore(value:0)
  lock.lock(); self.gate = gate; lock.unlock(); return gate
 }
 func failNext() { lock.lock(); failure = true; lock.unlock() }
 var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
 func read() throws -> BatteryReading {
  precondition(!Thread.isMainThread, "automatic provider must run off the UI thread")
  lock.lock(); calls += 1; let n = calls; let gate = gate; self.gate = nil
  let failure = failure; self.failure = false; lock.unlock()
  if let gate { precondition(gate.wait(timeout:.now()+5) == .success) }
  if failure { throw CocoaError(.fileReadUnknown) }
  return BatteryReading(date:Date(timeIntervalSince1970:Double(n)),percent:Double(60+n),connected:true,charging:false)
 }
}
@MainActor private final class SampleSchedule {
 var ticks: [@MainActor () -> Void] = []
 var intervals: [TimeInterval] = []
 var cancellations = 0
 func install(_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> () -> Void {
  intervals.append(interval); ticks.append(tick)
  return { self.cancellations += 1 }
 }
 func tick() { ticks.last!() }
}
@MainActor func batterySampleChecks() async throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 func wait(_ condition: @MainActor () -> Bool) async throws {
  for _ in 0..<600 { if condition() { return }; try await Task.sleep(nanoseconds:5_000_000) }
  preconditionFailure("automatic sampling fixture did not settle")
 }
 let source = SampleFixture(), schedule = SampleSchedule()
 var accepted: [Double] = []; var failures = 0; var eligible = true
 var monitor: BatterySampleMonitor? = BatterySampleMonitor(read:{ try source.read() },schedule:schedule.install,isEligible:{ eligible }) {
  switch $0 { case .success(let r): accepted.append(r.percent); case .failure: failures += 1 }
 }
 weak var weakMonitor = monitor
 monitor!.start(); monitor!.start()
 precondition(schedule.intervals == [2] && source.count == 0)
 let gate = source.blockNext(); schedule.tick(); try await wait { source.count == 1 }
 for _ in 0..<100 { schedule.tick() }
 precondition(source.count == 1)
 monitor!.invalidate(); schedule.tick(); gate.signal(); try await wait { !monitor!.loading }
 precondition(accepted.isEmpty, "invalidated slow reads must never reach policy")
 schedule.tick(); try await wait { !monitor!.loading }
 precondition(accepted == [62])
 source.failNext(); schedule.tick(); try await wait { !monitor!.loading }; precondition(failures == 1)
 schedule.tick(); try await wait { !monitor!.loading }; precondition(accepted.last == 64)
 eligible = false; schedule.tick(); precondition(source.count == 4)
 eligible = true
 let stopGate = source.blockNext(); schedule.tick(); try await wait { source.count == 5 }
 let oldTick = schedule.ticks.last!; monitor!.stop(); monitor!.start(); oldTick(); schedule.tick()
 precondition(source.count == 5 && schedule.intervals == [2,2])
 stopGate.signal(); try await wait { !monitor!.loading }; precondition(accepted.last == 64)
 schedule.tick(); try await wait { !monitor!.loading }; precondition(accepted.last == 66)
 monitor = nil; precondition(weakMonitor == nil && schedule.cancellations == 2)
 oldTick(); schedule.tick(); precondition(source.count == 6)

 // The real model consumes accepted automatic data, without a second sensor
 // read, even when its dashboard is unfocused. Existing manual APIs stay fresh.
 let suite = "org.opencharge.sampling-fixture."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 var config = Configuration(); config.hardwareEnabled = false; config.historyEnabled = false; config.notifications = false
 config.systemActionsEnabled = false; try config.save()
 let provider = SampleFixture(), ticks = SampleSchedule()
 var synchronousReads = 0
 let model = ChargeModel(automaticRead:{ try provider.read() },automaticSchedule:ticks.install,dashboardDefaults:defaults,observeLid:false,
  readBattery:{ synchronousReads += 1; return BatteryReading(percent:80,connected:true,charging:false) })
 precondition(synchronousReads == 1 && provider.count == 0 && ticks.intervals == [2])
 model.setDashboardFocused(false)
 ticks.tick(); try await wait { model.reading?.percent == 61 }
 precondition(synchronousReads == 1 && model.decision.effectiveLimit == 80 && model.history.isEmpty)
 let beforeManual = provider.blockNext(); ticks.tick(); try await wait { provider.count == 2 }
 model.refresh(); precondition(model.reading?.percent == 80 && synchronousReads == 2)
 beforeManual.signal(); try await wait { !model.automaticSamplePending }
 precondition(model.reading?.percent == 80, "old automatic reply overwrote a fresh manual decision")
 ticks.tick(); try await wait { model.reading?.percent == 63 }
 let beforeConfig = provider.blockNext(); ticks.tick(); try await wait { provider.count == 4 }
 model.config.policy.limit = 75; beforeConfig.signal(); try await wait { !model.automaticSamplePending }
 precondition(model.reading?.percent == 63 && model.decision.effectiveLimit == 80)
 ticks.tick(); try await wait { model.reading?.percent == 65 }; precondition(model.decision.effectiveLimit == 75)
 let beforeSleep = provider.blockNext(); ticks.tick(); try await wait { provider.count == 6 }
 let sleepingTick = ticks.ticks.last!; model.sleep(request:{ _ in preconditionFailure("monitoring sleep wrote hardware") })
 beforeSleep.signal(); try await wait { !model.automaticSamplePending }
 sleepingTick(); model.refresh(); precondition(provider.count == 6 && synchronousReads == 2 && model.reading?.percent == 65)
 model.wake(); precondition(synchronousReads == 3 && ticks.intervals == [2,2])
 provider.failNext(); ticks.tick(); try await wait { model.error != nil }
 precondition(synchronousReads == 3 && !model.config.hardwareEnabled)
 ticks.tick(); try await wait { model.reading?.percent == 68 }
 // Failed resets suppress acquisition until the pending reset is resolved.
 do { try model.resetSettings(persist:{ _ in throw CocoaError(.fileWriteUnknown) }); preconditionFailure("reset accepted failed storage") } catch {}
 let beforePending = provider.count; ticks.tick(); precondition(provider.count == beforePending)
 try model.resetSettings(request:{ _ in preconditionFailure("read-only reset wrote hardware") },releaseIdle:{},persist:{ _ in },applyDock:{ _ in })
 let beforeQuit = provider.blockNext(); ticks.tick(); try await wait { provider.count == 9 }
 let quitTick = ticks.ticks.last!; try model.prepareForQuit(request:{ _ in preconditionFailure("monitoring quit wrote hardware") })
 beforeQuit.signal(); try await wait { !model.automaticSamplePending }; quitTick()
 precondition(provider.count == 9)
 model.cancelQuit(request:{ _ in preconditionFailure("clean cancellation wrote hardware") },persist:{ _ in })
 precondition(synchronousReads == 4 && !model.config.hardwareEnabled)
 quitTick(); precondition(provider.count == 9)
 ticks.tick(); try await wait { model.reading?.percent == 70 }
 try model.prepareForQuit(request:{ _ in preconditionFailure("monitoring cleanup wrote hardware") })
 print("serial 2-second automatic acquisition, production model freshness and sleep/reset/quit isolation passed; fake providers only")
}
