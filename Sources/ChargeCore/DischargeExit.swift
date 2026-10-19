import Foundation

/// Pure exit policy. No helper, system settings, wall clock or UI operations.
public struct DischargeExit: Sendable {
 public enum Phase: Equatable, Sendable { case idle, preparing, waiting, needsDecision, ready, cancelled }
 public enum Power: Sendable { case external, batteryWithAdapterAbsent, battery, unknown }
 public private(set) var phase: Phase = .idle
 private let waitForPower: Bool
 private let timeout: TimeInterval
 private var started: TimeInterval?
 private var safeSince: TimeInterval?
 private var lastTime: TimeInterval?
 public init(waitForPower: Bool, timeout: TimeInterval = 15) { self.waitForPower = waitForPower; self.timeout = timeout }
 public mutating func begin() { guard phase == .idle || phase == .needsDecision else { return }; phase = .preparing; started = nil; safeSince = nil; lastTime = nil }
 public mutating func prepared(now: TimeInterval) {
  guard phase == .preparing else { return }
  guard waitForPower else { phase = .ready; return }
  guard now.isFinite, timeout.isFinite, timeout > 0 else { phase = .needsDecision; return }
  phase = .waiting; started = now; lastTime = now
 }
 public mutating func preparationFailed() { guard phase == .preparing else { return }; phase = .needsDecision }
 public mutating func observe(_ power: Power, now: TimeInterval) {
  guard phase == .waiting, let started, let lastTime else { return }
  guard now.isFinite, now >= lastTime else { phase = .needsDecision; return }
  if now - lastTime > 1 { safeSince = nil }
  self.lastTime = now
  switch power {
  case .external, .batteryWithAdapterAbsent:
   if let safeSince, now - safeSince >= 0.5 { phase = .ready; return }
   if safeSince == nil { safeSince = now }
  case .battery, .unknown: safeSince = nil
  }
  if now - started >= timeout { phase = .needsDecision }
 }
 public mutating func cancel() { guard phase != .ready && phase != .cancelled && phase != .idle else { return }; phase = .cancelled }
 public mutating func force() { guard phase == .needsDecision else { return }; phase = .ready }
}
