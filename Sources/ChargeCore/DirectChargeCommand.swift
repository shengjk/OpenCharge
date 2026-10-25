import Foundation

/// The CLI's one-shot interface does not own a policy, numeric sleep target or
/// continuous heartbeat. Internal lifecycle commands must not become CLI verbs.
public enum DirectChargeCommand {
 public enum Failure: Error, LocalizedError {
  case invalidArguments, numericSessionRequired
  public var errorDescription: String? {
   switch self {
   case .invalidArguments: return "hardware allowCharge|inhibitCharge|forceDischarge|restore --confirm"
   case .numericSessionRequired: return "This model requires a numeric firmware session. Use mode/limit configuration commands and enable control in the app with a compatible helper."
   }
  }
 }
 public static func run(arguments: [String], numericRequired: () throws -> Bool,
                        request: (String) throws -> String) throws -> String {
  guard arguments.count == 2, arguments[1] == "--confirm",
        ["allowCharge", "inhibitCharge", "forceDischarge", "restore"].contains(arguments[0]) else {
   throw Failure.invalidArguments
  }
  let action = arguments[0]
  if action != "restore", try numericRequired() {
   throw Failure.numericSessionRequired
  }
  return try request(action)
 }
}
