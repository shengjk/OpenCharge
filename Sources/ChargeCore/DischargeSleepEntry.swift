import Foundation

/// Display/phase metadata travels atomically with a fixed discharge action.
/// It cannot request an arbitrary operation or establish ownership by itself.
public enum DischargeSleepRequest {
 private static let prefix = "multiDisplayDischarge:"
 public static func underlying(_ command: String) -> String? {
  guard command.hasPrefix(prefix) else { return nil }
  let parts = command.dropFirst(prefix.count).split(separator:":",maxSplits:1,omittingEmptySubsequences:false)
  guard parts.count == 2, parts[0] == "display" || parts[0] == "system" else { return nil }
  let action = String(parts[1])
  if action == "forceDischarge" { return action }
  if case .plan(.discharge, _)? = FirmwareCommand.parse(action) { return action }
  return nil
 }
 public static func preventsDisplaySleep(_ command: String) -> Bool { underlying(command) != nil && command.hasPrefix(prefix+"display:") }
 public static func wrap(_ command: String, phase: PolicyPhase, screenCount: Int, preventDisplaySleep: Bool = false) -> String {
  let candidate = prefix + (preventDisplaySleep ? "display:" : "system:") + command
  return phase == .discharging && screenCount >= 2 && underlying(candidate) != nil ? candidate : command
 }
 public static func supportsHelper(_ capabilities: String) -> Bool {
  ChargeRequestContext.supportsHelper(capabilities) && capabilities.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }.filter { $0.hasPrefix("dischargeSleep:") } == ["dischargeSleep:displaySnapshotV1"]
 }
}

/// Helper-owned, console-session scoped snapshot. Never persisted or renewed by queries.
public struct DischargeSleepEntry: Sendable {
 private var acceptedAt: TimeInterval?
 public private(set) var preventDisplaySleep = false
 public init() {}
 public mutating func accept(multipleDisplays: Bool, at now: TimeInterval, preventDisplaySleep: Bool = false) {
  acceptedAt = multipleDisplays && now.isFinite ? now : nil
  self.preventDisplaySleep = acceptedAt != nil && preventDisplaySleep
 }
 public mutating func clear() { acceptedAt = nil; preventDisplaySleep = false }
 public func qualifies(at now: TimeInterval, discharging: Bool, connected: Bool?, lidClosed: Bool?, recoveryPending: Bool) -> Bool {
  guard !recoveryPending, discharging, connected == true, lidClosed == true,
   let acceptedAt, now.isFinite, (0...45).contains(now - acceptedAt) else { return false }
  return true
 }
 public enum Step: String, CaseIterable, Sendable { case allow, protection, activity }
 public struct Outcome: Sendable {
  public let failures: [Step: String]
  public var succeeded: Bool { failures.isEmpty }
 }
 /// The activity callback follows the protection attempt, including failure.
 /// Allow and protection have independent results; no dependency on allow success.
 public static func perform(allow: () throws -> Void, protect: () throws -> Void, activity: () throws -> Void) -> Outcome {
  var failures: [Step: String] = [:]
  do { try allow() } catch { failures[.allow] = error.localizedDescription }
  do { try protect() } catch { failures[.protection] = error.localizedDescription }
  do { try activity() } catch { failures[.activity] = error.localizedDescription }
  return Outcome(failures:failures)
 }
}
