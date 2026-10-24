import Foundation
import IOKit.pwr_mgt

/// Fixed local-user activity only; no assertion types or identifiers cross IPC.
/// Declaring activity is a display request, not proof that system sleep was vetoed.
public final class UserActivityController {
 public typealias Declare = (inout IOPMAssertionID) throws -> Void
 public typealias Release = (IOPMAssertionID) throws -> Void
 private let declare: Declare
 private let release: Release
 private var identifier: IOPMAssertionID = 0
 private var cleanupPending = false
 private var owned = Set<IOPMAssertionID>()
 public var active: Bool { !owned.isEmpty }
 public init(declare: Declare? = nil, release: Release? = nil) {
  self.declare = declare ?? { id in
   let result = IOPMAssertionDeclareUserActivity("OpenCharge discharge sleep entry" as CFString, kIOPMUserActiveLocal, &id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result,0) }
  }
  self.release = release ?? { id in
   let result = IOPMAssertionRelease(id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result,0) }
  }
 }
 public func request() throws {
  guard !cleanupPending else { throw HardwareError.unavailable("user activity cleanup pending") }
  var candidate = identifier
  do {
   try declare(&candidate)
   guard candidate != 0 else { throw HardwareError.unavailable("missing user activity assertion") }
   // The API explicitly permits a new identifier on a successful refresh.
   identifier = candidate; owned = [candidate]
  } catch {
   if identifier != 0 { owned.insert(identifier) }
   if candidate != 0 { owned.insert(candidate) }
   cleanupPending = true; throw error
  }
 }
 public func restore() throws {
  var failure: Error?
  for id in owned.sorted() {
   do { try release(id); owned.remove(id) } catch { failure = failure ?? error }
  }
  if let failure { throw failure }
  identifier = 0; cleanupPending = false
 }
 deinit { for id in owned { try? release(id) } }
}
