import Foundation
import IOKit
import IOKit.pwr_mgt
import ApplePowerConstants

/// Read-only root-domain interest notification, delivered on the main queue.
public final class LidStateObserver {
 private final class Callback {
  let receive: () -> Void
  init(_ receive: @escaping () -> Void) { self.receive = receive }
 }
 private var port: IONotificationPortRef?
 private var notification: io_object_t = 0
 private let callback: Callback
 public static func currentState() -> Bool? {
  let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
  guard root != 0 else { return nil }; defer { IOObjectRelease(root) }
  guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
  return value as? Bool
 }
 public init(receive: @escaping () -> Void) throws {
  callback = Callback(receive)
  let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
  guard root != 0 else { throw HardwareError.unavailable(String(localized:"合盖状态不可用")) }; defer { IOObjectRelease(root) }
  guard let port = IONotificationPortCreate(kIOMainPortDefault) else { throw HardwareError.unavailable(String(localized:"无法监听合盖状态")) }
  self.port = port
  let result = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { ref, _, message, _ in
   guard message == opencharge_clamshell_state_changed(), let ref else { return }
   Unmanaged<Callback>.fromOpaque(ref).takeUnretainedValue().receive()
  }, Unmanaged.passUnretained(callback).toOpaque(), &notification)
  guard result == kIOReturnSuccess else { IONotificationPortDestroy(port); self.port = nil; throw HardwareError.driver(result, 0) }
  IONotificationPortSetDispatchQueue(port, .main)
 }
 deinit {
  if notification != 0 { IOObjectRelease(notification) }
  if let port { IONotificationPortSetDispatchQueue(port, nil); IONotificationPortDestroy(port) }
 }
}
