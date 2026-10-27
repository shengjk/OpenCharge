import Foundation
import Darwin
public enum HelperError: Error, LocalizedError {
 case unavailable, rejected(String)
 public var errorDescription: String? { switch self { case .unavailable: return NSLocalizedString("硬件服务未安装或不可达，请查看安装文档", comment: ""); case .rejected(let s): return s } }
}

/// Bounded newline-framed Unix stream transport. One absolute deadline covers all fragments.
/// MSG_DONTWAIT prevents a slow peer from resetting a timeout and starving the helper watchdog.
public enum HelperSocketIO {
 public static func readLine(_ fd: Int32, limit: Int, deadline: TimeInterval) throws -> String {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 256)
  while data.count < limit {
   try ready(fd, event: Int16(POLLIN), deadline: deadline)
   let n = recv(fd, &buffer, min(buffer.count, limit - data.count), MSG_DONTWAIT)
   if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
   guard n > 0 else { throw HelperError.unavailable }
   data.append(contentsOf: buffer.prefix(n))
   if let newline = data.firstIndex(of: 10) {
    guard newline == data.index(before: data.endIndex),
          let line = String(data: data.prefix(upTo: newline), encoding: .utf8) else {
     throw HelperError.rejected("invalid IPC frame")
    }
    return line
   }
  }
  throw HelperError.rejected("IPC frame exceeds limit")
 }
 public static func writeLine(_ line: String, to fd: Int32, deadline: TimeInterval) throws {
  guard !line.contains("\n"), !line.contains("\r") else { throw HelperError.rejected("invalid IPC line") }
  let data = Array((line + "\n").utf8)
  var sent = 0
  while sent < data.count {
   try ready(fd, event: Int16(POLLOUT), deadline: deadline)
   let n = data.withUnsafeBytes { send(fd, $0.baseAddress!.advanced(by: sent), data.count - sent, MSG_DONTWAIT) }
   if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
   guard n > 0 else { throw HelperError.unavailable }
   sent += n
  }
 }
 private static func ready(_ fd: Int32, event: Int16, deadline: TimeInterval) throws {
  while true {
   let remaining = deadline - ProcessInfo.processInfo.systemUptime
   guard remaining > 0 else { throw HelperError.unavailable }
   var descriptor = pollfd(fd: fd, events: event, revents: 0)
   let result = poll(&descriptor, 1, Int32(max(1, min(remaining * 1000, Double(Int32.max)))))
   if result < 0 && errno == EINTR { continue }
   guard result > 0, descriptor.revents & event != 0 else { throw HelperError.unavailable }
   return
  }
 }
}
public enum HelperClient {
 public static let socketPath = "/var/run/opencharge.sock"
 public static let supportedActions: Set<String> = Set(["sleepOverrideOn", "sleepOverrideDisplayOn", "sleepOverrideRestore", "sleepPolicyOn", "sleepPolicyOff", "retainChargeInhibit", "chargeContext", "capabilities", "allowCharge", "inhibitCharge", "forceDischarge", "restore",
         "lowPowerOn", "lowPowerOff", "lowPowerRestore", "lowPowerStatus",
         "lowPowerBatteryOn", "lowPowerBatteryOff", "lowPowerACOn", "lowPowerACOff",
         "magSafeSystem", "magSafeBlinkOrange", "magSafeSleepOn", "magSafeSleepOff", "magSafeStatus", "magSafeOff", "magSafeGreen", "magSafeOrange", "magSafeRestore"]).union(FirmwareCommand.supportedActions)
 public static func request(_ command: FirmwareCommand) throws -> String {
  guard let value = command.wireValue else { throw HelperError.rejected("invalid firmware command") }
  return try request(value)
 }
 public static func request(_ action: String) throws -> String {
  guard supportedActions.contains(action) || ServiceFileRemovalRequest.parse(action) != nil || DischargeSleepRequest.underlying(action) != nil || ChargeRequestContext.parseEnvelope(action) != nil else {
   throw HelperError.rejected("unknown helper action")
  }
  let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { throw HelperError.unavailable }; defer { close(fd) }
  var timeout = timeval(tv_sec: 3, tv_usec: 0)
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  var noSig: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
  let deadline = ProcessInfo.processInfo.systemUptime + (action.hasPrefix("lowPower") ? 6 : 3)
  let flags = fcntl(fd, F_GETFL)
  guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw HelperError.unavailable }
  var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(socketPath.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { dest in dest.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
  address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
  if ok != 0 {
   guard errno == EINPROGRESS else { throw HelperError.unavailable }
   var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
   let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
   guard poll(&descriptor, 1, Int32(remaining * 1000)) > 0 else { throw HelperError.unavailable }
   var socketError: Int32 = 0; var errorLength = socklen_t(MemoryLayout<Int32>.size)
   guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0, socketError == 0 else { throw HelperError.unavailable }
  }
  var peerUID: uid_t = 0; var peerGID: gid_t = 0
  guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == 0 else { throw HelperError.rejected("helper peer is not root") }
  try HelperSocketIO.writeLine(action, to: fd, deadline: deadline)
  shutdown(fd, SHUT_WR)
  let reply = try HelperSocketIO.readLine(fd, limit: 4096, deadline: deadline)
  return try decodeReply(reply)
 }
 /// Framing and root-peer authentication precede this decoder in production.
 public static func decodeReply(_ reply: String) throws -> String {
  if reply == ChargeControlSuspension.reply { throw ChargeControlSuspension.systemSleep }
  guard reply.hasPrefix("OK ") else { throw HelperError.rejected(reply) }
  return String(reply.dropFirst(3))
 }
}
