import Foundation

public enum FirmwareControlAction: String, CaseIterable, Equatable, Sendable { case allow, inhibit, discharge }

/// Canonical finite commands; no key names, paths, arbitrary bytes or reset records.
public enum FirmwareCommand: Equatable, Sendable {
 case status, sessionStatus, allow, inhibit, discharge, sleepOff
 case limit(Int), exit(Int), sleepTarget(Int)
 case plan(FirmwareControlAction, sleepTarget: Int)
 public var wireValue: String? {
  switch self {
  case .status: return "firmwareStatus"
  case .sessionStatus: return "firmwareSessionStatus"
  case .allow: return "firmwareAllow"
  case .inhibit: return "firmwareInhibit"
  case .discharge: return "firmwareDischarge"
  case .sleepOff: return "firmwareSleepOff"
  case .limit(let n): return (20...100).contains(n) ? "firmwareLimit:\(n)" : nil
  case .exit(let n): return (20...100).contains(n) ? "firmwareExit:\(n)" : nil
  case .sleepTarget(let n): return n == 15 || (20...100).contains(n) ? "firmwareSleep:\(n)" : nil
  case .plan(let action, let n): return n == 15 || (20...100).contains(n) ? "firmwarePlan:\(action.rawValue):\(n)" : nil
  }
 }
 public static func parse(_ value: String) -> Self? {
  switch value {
  case "firmwareStatus": return .status
  case "firmwareSessionStatus": return .sessionStatus
  case "firmwareAllow": return .allow
  case "firmwareInhibit": return .inhibit
  case "firmwareDischarge": return .discharge
  case "firmwareSleepOff": return .sleepOff
  default: break
  }
  let parts = value.split(separator: ":", omittingEmptySubsequences: false)
  if parts.count == 3, parts[0] == "firmwarePlan", let action = FirmwareControlAction(rawValue:String(parts[1])),
     let n = Int(parts[2]), String(n) == parts[2] {
   let result = Self.plan(action,sleepTarget:n); return result.wireValue == value ? result : nil
  }
  guard parts.count == 2, let n = Int(parts[1]), String(n) == parts[1] else { return nil }
  let result: Self
  switch parts[0] { case "firmwareLimit": result = .limit(n)
  case "firmwareExit": result = .exit(n)
  case "firmwareSleep": result = .sleepTarget(n)
  default: return nil }
  return result.wireValue == value ? result : nil
 }
 public static var supportedActions: Set<String> {
  var values = Set([Self.status, .sessionStatus, .allow, .inhibit, .discharge, .sleepOff, .sleepTarget(15)].compactMap(\.wireValue))
  for n in 20...100 { for item in [Self.limit(n), .exit(n), .sleepTarget(n)] { values.insert(item.wireValue!) } }
  for n in [15]+Array(20...100) { for action in FirmwareControlAction.allCases { values.insert(Self.plan(action,sleepTarget:n).wireValue!) } }
  return values
 }
}
