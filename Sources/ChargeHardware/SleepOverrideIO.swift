import Foundation
import IOKit
import IOKit.pwr_mgt
import Darwin

/// Independent fixed SPI adapter. Initialization and inspection do not mutate power state.
public final class SleepOverrideIO {
 private typealias CopySettings = @convention(c) () -> Unmanaged<CFDictionary>?
 private typealias SetSetting = @convention(c) (CFString, CFTypeRef) -> IOReturn
 private let library: UnsafeMutableRawPointer
 private let copySettings: CopySettings
 private let setSetting: SetSetting
 private var displayAssertion: IOPMAssertionID?
 public init() throws {
  guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL) else { throw SleepOverrideError.unavailable("IOKit") }
  guard let copy = dlsym(library, "IOPMCopySystemPowerSettings"), let set = dlsym(library, "IOPMSetSystemPowerSetting") else { dlclose(library); throw SleepOverrideError.unavailable("system power SPI symbols") }
  self.library = library; copySettings = unsafeBitCast(copy, to: CopySettings.self); setSetting = unsafeBitCast(set, to: SetSetting.self)
 }
 deinit { if let displayAssertion { IOPMAssertionRelease(displayAssertion) }; dlclose(library) }
 public var transport: SleepOverrideTransport {
  SleepOverrideTransport(captureGlobal: { try self.captureGlobal() }, readGlobal: { try self.readGlobal() }, setGlobal: { try self.setGlobal($0) }, setLid: { try self.setLid($0) }, setDisplay: { try self.setDisplay($0) })
 }
 private func root() throws -> io_registry_entry_t {
  let service = IOServiceGetMatchingService(RegistryPort.defaultValue, IOServiceMatching("IOPMrootDomain"))
  guard service != 0 else { throw SleepOverrideError.unavailable("power root domain") }; return service
 }
 private func readGlobal() throws -> Bool {
  guard let settings = copySettings()?.takeRetainedValue() else { return false }
  let value = (settings as NSDictionary)["SleepDisabled"]
  guard let value else { return false }
  guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(), let result = value as? Bool else { throw SleepOverrideError.unavailable("unrecognized global preference") }
  return result
 }
 public func captureGlobal() throws -> Bool {
  let service = try root(); defer { IOObjectRelease(service) }
  guard let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(), CFGetTypeID(value) == CFBooleanGetTypeID(), let effective = value as? Bool else { throw SleepOverrideError.unavailable("effective sleep setting unreadable") }
  let stored = try readGlobal()
  guard effective == stored else { throw SleepOverrideError.unavailable("effective and stored sleep settings disagree") }
  return stored
 }
 private func privileged() throws { guard geteuid() == 0 else { throw HardwareError.permissionRequired } }
 private func setGlobal(_ disabled: Bool) throws {
  try privileged()
  let status = setSetting("SleepDisabled" as CFString, disabled ? kCFBooleanTrue : kCFBooleanFalse)
  guard status == kIOReturnSuccess else { throw HardwareError.driver(status, 0) }
 }
 private func setLid(_ disabled: Bool) throws {
  try privileged()
  let service = try root(); defer { IOObjectRelease(service) }
  var connection: io_connect_t = 0
  let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
  guard opened == kIOReturnSuccess else { throw HardwareError.driver(opened, 0) }
  defer { IOServiceClose(connection) }
  var value: UInt64 = disabled ? 1 : 0
  let result = IOConnectCallScalarMethod(connection, 12, &value, 1, nil, nil)
  guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }
 }
 private func setDisplay(_ prevented: Bool) throws {
  try privileged()
  if prevented && displayAssertion == nil {
   var id: IOPMAssertionID = 0
   let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "OpenCharge active charge session" as CFString, &id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }; displayAssertion = id
  } else if !prevented, let id = displayAssertion {
   let result = IOPMAssertionRelease(id)
   guard result == kIOReturnSuccess else { throw HardwareError.driver(result, 0) }; displayAssertion = nil
  }
 }
}
