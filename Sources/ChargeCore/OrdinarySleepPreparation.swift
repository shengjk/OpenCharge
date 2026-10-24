import Foundation

/// Ordinary sleep keeps charge ownership. Opting out does not request a charge
/// setter; opting in attempts inhibition before releasing sleep protection.
public enum OrdinarySleepPreparation {
 public enum Step: String, CaseIterable, Sendable { case inhibit, releaseProtection }
 public struct Outcome: Sendable {
  public let failures: [Step: String]
  public var succeeded: Bool { failures.isEmpty }
 }
 public static func perform(stopInSleep: Bool, sessionActive: Bool, inhibit: () throws -> Void, releaseProtection: () throws -> Void) -> Outcome {
  var failures: [Step: String] = [:]
  if stopInSleep && sessionActive {
   do { try inhibit() } catch { failures[.inhibit] = error.localizedDescription }
  }
  do { try releaseProtection() } catch { failures[.releaseProtection] = error.localizedDescription }
  return Outcome(failures:failures)
 }
}
