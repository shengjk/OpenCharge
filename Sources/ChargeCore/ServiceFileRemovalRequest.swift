import Foundation

/// Fixed service identity and a bounded Authorization Services external form; never paths or commands.
public struct ServiceFileRemovalRequest {
 public static let prefix = "removeServiceFiles:"
 public static let reply = "service files removed"
 public let externalForm: Data
 public init?(externalForm: Data) { guard externalForm.count == 32 else { return nil }; self.externalForm = externalForm }
 public var wireValue: String { Self.prefix+externalForm.base64EncodedString() }
 public static func parse(_ value: String) -> Self? {
  guard value.hasPrefix(prefix), let data = Data(base64Encoded:String(value.dropFirst(prefix.count))),
        let result = Self(externalForm:data), result.wireValue == value else { return nil }
  return result
 }
 public static func supports(_ capabilities: String) -> Bool {
  let fields = capabilities.split { $0 == "," || $0.isWhitespace }
  let versions = fields.filter { $0.hasPrefix("serviceRemoval:") }
  return versions.count == 1 && (versions[0] == "serviceRemoval:ownedV1" || versions[0] == "serviceRemoval:pendingV1")
 }
 public static func permitsWhilePending(_ command: String) -> Bool {
  if parse(command) != nil { return true }
  return ["capabilities","chargeContext","restore","magSafeRestore","magSafeStatus","sleepOverrideRestore","lowPowerStatus","lowPowerRestore","firmwareStatus","firmwareSessionStatus"].contains(command)
 }
}
