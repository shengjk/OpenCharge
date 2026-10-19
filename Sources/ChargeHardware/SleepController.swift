import Foundation
import IOKit.pwr_mgt

/// Public idle-sleep capability only. Apple explicitly allows lid/menu/low-battery sleep
/// despite this assertion. It must never be presented as clamshell sleep suppression.
public final class SleepController {
 public typealias Create = () throws -> IOPMAssertionID
 public typealias Release = (IOPMAssertionID) throws -> Void
 private let create: Create
 private let release: Release
 private var assertion: IOPMAssertionID?
 public var active: Bool { assertion != nil }
 public init(create: Create? = nil, release: Release? = nil) {
  self.create = create ?? {
   var id: IOPMAssertionID = 0
   let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "OpenCharge charging to target" as CFString, &id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }
   return id
  }
  self.release = release ?? { id in
   let result = IOPMAssertionRelease(id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }
  }
 }
 public func setPreventIdleSleep(_ enabled: Bool) throws {
  if enabled, assertion == nil { assertion = try create() }
  else if !enabled, let id = assertion { try release(id); assertion = nil }
 }
 deinit { if let id = assertion { try? release(id) } }
}
