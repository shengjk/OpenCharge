import Foundation
import IOKit
import ApplePowerConstants
import IOKit.pwr_mgt

/// Observes actual system sleep/wake in the launch daemon. Sleep is always acknowledged;
/// a failed charge operation must never trap the OS waiting for this utility.
public final class SystemPowerObserver {
 private var root: io_connect_t = 0
 private var port: IONotificationPortRef?
 private var notifier: io_object_t = 0
 private let onSleep: () -> Void
 private let onWake: () -> Void
 public init(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) throws {
  self.onSleep = onSleep; self.onWake = onWake
  let context = Unmanaged.passUnretained(self).toOpaque()
  root = IORegisterForSystemPower(context, &port, { context, _, message, argument in
   guard let context else { return }
   let owner = Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
   switch message {
   case opencharge_can_system_sleep(): IOAllowPowerChange(owner.root, Int(bitPattern: argument))
   case opencharge_system_will_sleep():
    owner.onSleep()
    IOAllowPowerChange(owner.root, Int(bitPattern: argument))
   case opencharge_system_has_powered_on(): owner.onWake()
   default: break
   }
  }, &notifier)
  guard root != 0, let port else { if let port = self.port { IONotificationPortDestroy(port); self.port = nil }; throw HardwareError.unavailable("system power notifications") }
  IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
 }
 deinit {
  if notifier != 0 { IODeregisterForSystemPower(&notifier) }
  if root != 0 { IOServiceClose(root) }
  if let port { IONotificationPortDestroy(port) }
 }
}
