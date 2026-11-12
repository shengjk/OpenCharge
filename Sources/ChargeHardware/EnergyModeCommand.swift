import Foundation

/// Fixed CLI arguments share the helper's tri-state command protocol.
public enum EnergyModeCommand {
 public enum Failure: Error, LocalizedError {
  case invalidArguments, unexpectedReadback
  public var errorDescription: String? {
   switch self {
   case .invalidArguments: return "power-mode status | automatic|low|high [battery|ac] --confirm"
   case .unexpectedReadback: return "Power mode readback did not confirm every requested source. Read power-mode status before retrying."
   }
  }
 }
 public static func run(arguments: [String], readStatus: () throws -> EnergyModeStatus,
                        request: (String) throws -> String) throws -> String {
  if arguments == ["status"] { return try readStatus().description }
  guard (arguments.count == 2 || arguments.count == 3), arguments.last == "--confirm",
        let mode = ["automatic": EnergyMode.automatic, "low": .low, "high": .high][arguments[0]] else {
   throw Failure.invalidArguments
  }
  let source: PowerSource?
  if arguments.count == 3 {
   guard let selected = PowerSource(rawValue: arguments[1]) else { throw Failure.invalidArguments }
   source = selected
  } else { source = nil }
  let status = try EnergyModeStatus(helperResponse: request(EnergyModeRequest(mode: mode, source: source).command))
  let selected = source.map { [$0] } ?? PowerSource.allCases.filter { status.mode(for: $0) != nil }
  guard !selected.isEmpty, selected.allSatisfy({ status.mode(for: $0) == mode }) else {
   throw Failure.unexpectedReadback
  }
  return status.description
 }
}
