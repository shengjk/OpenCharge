import Foundation

/// Monotonic-clock charging ownership lease. Deliberate retain-on-quit is distinct from
/// an interrupted client; sleeping time cannot cause the awake watchdog to undo pause-on-sleep.
public struct ControlLease: Sendable {
 public private(set) var lastRequest: TimeInterval = -.infinity
 public private(set) var retained = false
 public private(set) var sleeping = false
 public init() {}
 public mutating func request(at now: TimeInterval, retained: Bool = false) { lastRequest = now; self.retained = retained }
 public mutating func beginSleep() { sleeping = true }
 public mutating func wake(at now: TimeInterval) { sleeping = false; lastRequest = now }
 public mutating func clear() { self = Self() }
 public func expired(at now: TimeInterval) -> Bool { !sleeping && !retained && now.isFinite && now - lastRequest > 45 }
}
