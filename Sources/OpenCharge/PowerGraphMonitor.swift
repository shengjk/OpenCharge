import Foundation
import Combine
import ChargeHardware

/// Reads display telemetry only. It has no model refresh, configuration writer or helper channel.
@MainActor final class PowerGraphMonitor: ObservableObject {
 typealias Read = @Sendable () throws -> BatteryReading
 typealias Schedule = @MainActor (_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> (() -> Void)
 static let liveRead: Read = { try BatteryReader.read() }
 @Published private(set) var reading: BatteryReading?
 @Published private(set) var error: String?
 @Published private(set) var attempted = false
 @Published private(set) var loading = false
 private(set) var active = false
 private(set) var mode: PowerCalculationMode = .average
 private let read: Read?
 private let schedule: Schedule
 private let queue = DispatchQueue(label: "org.opencharge.power-graph", qos: .utility)
 private var cancelTimer: (() -> Void)?
 private var generation = 0
 private var ticket: ReadTicket?

 init(read: Read? = nil, schedule: Schedule? = nil) {
  self.read = read; self.schedule = schedule ?? Self.makeTimer
 }
 deinit { cancelTimer?(); ticket?.cancel() }

 func configure(active: Bool, mode: PowerCalculationMode) {
  guard self.active != active || self.mode != mode else { return }
  stop(); self.mode = mode
  guard active, read != nil else { return }
  self.active = true
  let token = generation
  cancelTimer = schedule(mode.interval) { [weak self] in
   guard let self, self.active, self.generation == token else { return }
   self.refresh()
  }
  refresh()
 }
 func stop() {
  generation &+= 1; active = false
  cancelTimer?(); cancelTimer = nil
  ticket?.cancel(); ticket = nil; loading = false
 }
 func refresh() {
  guard active, ticket == nil, let read else { return }
  let request = ReadTicket(); ticket = request; loading = true
  queue.async { [weak self] in
   guard request.valid else { return }
   let result = Result { try read() }
   DispatchQueue.main.async { [weak self] in
    guard let self, self.active, request.valid, self.ticket === request else { return }
    self.ticket = nil; self.loading = false; self.attempted = true
    switch result {
    case .success(let reading): self.reading = reading; self.error = nil
    case .failure(let failure):
     self.reading = nil
     self.error = String.localizedStringWithFormat(NSLocalizedString("功耗读取失败：%@", comment: ""), failure.localizedDescription)
    }
   }
  }
 }
 private static func makeTimer(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> () -> Void {
  let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
  for mode in [RunLoop.Mode.common, .modalPanel, .eventTracking] { RunLoop.main.add(timer, forMode: mode) }
  return { timer.invalidate() }
 }
 private final class ReadTicket: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var valid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
 }
}
