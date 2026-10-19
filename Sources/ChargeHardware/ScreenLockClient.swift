import Foundation
import CoreGraphics
import Darwin

/// Fixed, dynamically resolved login SPI. Inspection never invokes the entry point.
public enum ScreenLockClient {
 private typealias Lock = @convention(c) () -> Void
 private static let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
 private static func withEntry<T>(_ body: (Lock) throws -> T) throws -> T {
  guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { throw HardwareError.unavailable("锁屏接口不可用") }
  defer { dlclose(library) }
  guard let symbol = dlsym(library, "SACLockScreenImmediate") else { throw HardwareError.unavailable("锁屏入口不可用") }
  return try body(unsafeBitCast(symbol, to: Lock.self))
 }
 public static func inspect() throws { try withEntry { _ in } }
 public static var consoleSessionActive: Bool {
  guard let state = CGSessionCopyCurrentDictionary() as? [String: Any],
        state[kCGSessionOnConsoleKey as String] as? Bool == true,
        state[kCGSessionLoginDoneKey as String] as? Bool == true,
        let uid = state[kCGSessionUserIDKey as String] as? NSNumber else { return false }
  return uid.uint32Value == getuid()
 }
 public static func requestLock() throws {
  guard consoleSessionActive else { throw HardwareError.unavailable("当前用户不是前台登录会话") }
  try withEntry { lock in lock() }
 }
}
