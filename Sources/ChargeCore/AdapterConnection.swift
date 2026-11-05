import Foundation

/// Availability of the acknowledged control session, not proof of cable presence.
/// AppleRawExternalConnected can become false when our own input cutoff takes effect.
public enum AdapterConnection {
 public static func available(connected: Bool, rawConnected: Bool?, ownInputInhibited: Bool) -> Bool {
  ownInputInhibited || (rawConnected ?? connected)
 }
}

/// Monotonic startup and reconnect windows for closed-lid calibration discharge.
public struct CalibrationDischargeGate: Sendable {
 private let startedAt: TimeInterval
 private var pluggedInAt: TimeInterval?
 private var lastConnected: Bool?

 public init(startedAt: TimeInterval) { self.startedAt = startedAt }

 public mutating func observe(connected: Bool, rawConnected: Bool?, ownInputInhibited: Bool, now: TimeInterval) {
  guard !ownInputInhibited else { return }
  let connected = rawConnected ?? connected
  if connected && lastConnected == false { pluggedInAt = now }
  lastConnected = connected
 }

 public func shouldDefer(lidClosed: Bool?, now: TimeInterval) -> Bool {
  lidClosed == true && (now - startedAt < 30 || pluggedInAt.map { now - $0 < 15 } == true)
 }
}
