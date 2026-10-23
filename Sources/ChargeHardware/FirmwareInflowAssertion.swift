import Foundation
import IOKit.pwr_mgt

/// Process-local ownership of the fixed Intel inflow assertion. An accepted
/// assertion is not proof of battery discharge. This is not a generic assertion API.
/// The helper must serialize calls and release ownership before switching backends.
final class FirmwareInflowAssertion {
 typealias ID = IOPMAssertionID
 private let authorize: () throws -> Void
 private let create: () throws -> ID
 private let inspect: (ID) throws -> Bool
 private let release: (ID) throws -> Void
 private(set) var ownedID: ID?
 private(set) var recoveryRequired = false

 init(authorize: @escaping () throws -> Void = {
  guard geteuid() == 0 else { throw HardwareError.unavailable("Inflow control requires the privileged helper") }
 }, create: @escaping () throws -> ID = {
  var id: ID = 0
  let result = IOPMAssertionCreateWithName("DisableInflow" as CFString,
   IOPMAssertionLevel(kIOPMAssertionLevelOn), "OpenCharge Intel power inflow control" as CFString, &id)
  guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }
  return id
 }, inspect: @escaping (ID) throws -> Bool = { id in
  guard let value = IOPMAssertionCopyProperties(id)?.takeRetainedValue() else { return false }
  return matches(value as NSDictionary)
 }, release: @escaping (ID) throws -> Void = { id in
  let result = IOPMAssertionRelease(id)
  guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }
 }) {
  self.authorize = authorize; self.create = create; self.inspect = inspect; self.release = release
 }

 static func matches(_ properties: NSDictionary) -> Bool {
  guard let type = properties[kIOPMAssertionTypeKey] as? String, type == "DisableInflow",
        let level = properties[kIOPMAssertionLevelKey] as? NSNumber,
        CFGetTypeID(level) == CFNumberGetTypeID() else { return false }
  return level.doubleValue == Double(kIOPMAssertionLevelOn)
 }

 func acquire() throws {
  try authorize()
  guard !recoveryRequired else { throw HardwareError.unavailable("Inflow assertion cleanup pending") }
  if ownedID == nil {
   let id = try create()
   guard id != 0 else { throw HardwareError.unavailable("Invalid inflow assertion identifier") }
   // Keep the identifier even if inspection fails, so cleanup can be retried.
   ownedID = id
  }
  do {
   guard let id = ownedID, try inspect(id) else { throw HardwareError.unavailable("Inflow assertion readback failed") }
  } catch { recoveryRequired = true; throw error }
 }

 func restore() throws {
  try authorize()
  guard let id = ownedID else { recoveryRequired = false; return }
  do { try release(id); ownedID = nil; recoveryRequired = false }
  catch { recoveryRequired = true; throw error }
 }
}
