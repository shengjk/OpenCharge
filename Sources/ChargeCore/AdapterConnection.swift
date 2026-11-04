import Foundation

/// Availability of the acknowledged control session, not proof of cable presence.
/// AppleRawExternalConnected can become false when our own input cutoff takes effect.
public enum AdapterConnection {
 public static func available(connected: Bool, rawConnected: Bool?, ownInputInhibited: Bool) -> Bool {
  ownInputInhibited || (rawConnected ?? connected)
 }
}
