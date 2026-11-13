import Foundation
import ChargeHardware

/// One automatic read at a time, independent of dashboard visibility. A slow
/// provider is never duplicated or allowed to build an unbounded queue.
@MainActor final class BatterySampleMonitor {
 typealias Read = @Sendable () throws -> BatteryReading
 typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)
 private let read: Read
 private let schedule: Schedule
 private let isEligible: @MainActor () -> Bool
 private let receive: @MainActor (Result<BatteryReading, Error>) -> Void
 private let queue = DispatchQueue(label:"org.opencharge.battery-sampling",qos:.utility)
 private var cancelTimer: (() -> Void)?
 private var request: Ticket?
 private var generation = 0
 private(set) var active = false
 var loading: Bool { request != nil }

 init(read: @escaping Read, schedule: Schedule? = nil, isEligible: @escaping @MainActor () -> Bool = { true },
      receive: @escaping @MainActor (Result<BatteryReading, Error>) -> Void) {
  self.read = read; self.schedule = schedule ?? Self.makeTimer; self.receive = receive; self.isEligible = isEligible
 }
 deinit { cancelTimer?(); request?.cancel() }
 func start() {
  guard !active else { return }
  active = true
  let token = generation
  cancelTimer = schedule(2) { [weak self] in
   guard let self, self.active, self.generation == token else { return }
   self.refresh()
  }
 }
 func stop() {
  active = false; generation &+= 1
  cancelTimer?(); cancelTimer = nil
  invalidate()
 }
 func invalidate() {
  // Keep the slot occupied until the worker actually finishes. Invalidating a
  // result cannot cancel an OS read that has already entered the provider.
  request?.cancel()
 }
 func refresh() {
  guard active, isEligible(), request == nil else { return }
  let ticket = Ticket(); request = ticket
  let read = read
  queue.async { [weak self] in
   let result: Result<BatteryReading, Error>? = ticket.valid ? Result { try read() } : nil
   DispatchQueue.main.async { [weak self] in
    guard let self, self.request === ticket else { return }
    self.request = nil
    guard self.active, self.isEligible(), ticket.valid, let result else { return }
    self.receive(result)
   }
  }
 }
 private static func makeTimer(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> () -> Void {
  let timer = Timer(timeInterval:interval,repeats:true) { _ in MainActor.assumeIsolated { tick() } }
  for mode in [RunLoop.Mode.common,.modalPanel,.eventTracking] { RunLoop.main.add(timer,forMode:mode) }
  return { timer.invalidate() }
 }
 private final class Ticket: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var valid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
 }
}
