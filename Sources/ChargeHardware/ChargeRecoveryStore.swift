import Foundation
import Darwin

/// Only the helper supplies a store; read-only clients never create recovery files.
public protocol ChargeRecoveryStore: AnyObject {
 func load() throws -> Data?
 func save(_ data: Data?) throws
}

/// A private directory and descriptor-relative operations keep recovery outside user-controlled paths.
public final class ChargeRecoveryFileStore: ChargeRecoveryStore {
 private let directory: Int32
 private let owner: uid_t
 private enum Record: String { case charge = "charge-recovery.json", magSafe = "magsafe-recovery.json", sleep = "sleep-recovery.json" }
 private static let limit = 8192
 public init(directory path: String = "/var/db/org.opencharge.charged", owner: uid_t = 0) throws {
  self.owner = owner
  if mkdir(path, 0o700) != 0 && errno != EEXIST { throw Self.failure("create recovery directory") }
  let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  guard fd >= 0 else { throw Self.failure("open recovery directory") }
  var info = stat()
  guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & 0o077 == 0,
        info.st_mode & S_IFMT == S_IFDIR else {
   close(fd); throw HardwareError.invalidData("Unsafe recovery directory")
  }
  guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw Self.failure("lock recovery directory") }
  directory = fd
 }
 deinit { close(directory) }
 public static func bootSession() throws -> String {
  var count = 128
  var bytes = [CChar](repeating: 0, count: count)
  let result = bytes.withUnsafeMutableBytes { sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &count, nil, 0) }
  guard result == 0, count > 1, count <= bytes.count, bytes[count - 1] == 0,
        let uuid = UUID(uuidString: String(cString: bytes)) else {
   throw HardwareError.unavailable("Boot session identity")
  }
  return uuid.uuidString
 }
 public func load() throws -> Data? { try load(.charge) }
 public func save(_ data: Data?) throws { try save(data, record: .charge) }
 /// Shares the lifetime lock and directory descriptor; filenames are fixed, never provided by IPC.
 public func magSafeStore() -> ChargeRecoveryStore { MagSafeFileView(parent: self) }
 private final class MagSafeFileView: ChargeRecoveryStore {
  let parent: ChargeRecoveryFileStore
  init(parent: ChargeRecoveryFileStore) { self.parent = parent }
  func load() throws -> Data? { try parent.load(.magSafe) }
  func save(_ data: Data?) throws { try parent.save(data, record: .magSafe) }
 }
 public func sleepStore() -> ChargeRecoveryStore { SleepFileView(parent: self) }
 private final class SleepFileView: ChargeRecoveryStore {
  let parent: ChargeRecoveryFileStore
  init(parent: ChargeRecoveryFileStore) { self.parent = parent }
  func load() throws -> Data? { try parent.load(.sleep) }
  func save(_ data: Data?) throws { try parent.save(data, record: .sleep) }
 }
 private func load(_ record: Record) throws -> Data? {
  let fd = openat(directory, record.rawValue, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
  if fd < 0 { if errno == ENOENT { return nil }; throw Self.failure("open recovery record") }
  defer { close(fd) }
  var info = stat()
  guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & 0o077 == 0,
        info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
        info.st_size >= 0, info.st_size <= Self.limit else { throw HardwareError.invalidData("Unsafe recovery record") }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 1024)
  while true {
   let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
   if count < 0 { if errno == EINTR { continue }; throw Self.failure("read recovery record") }
   if count == 0 { return data }
   guard data.count + count <= Self.limit else { throw HardwareError.invalidData("Recovery record too large") }
   data.append(contentsOf: buffer.prefix(count))
  }
 }
 private func save(_ data: Data?, record: Record) throws {
  let name = record.rawValue
  // Refuse unexpected existing paths before either replacing or removing the record.
  _ = try load(record)
  guard let data else {
   if unlinkat(directory, name, 0) != 0 && errno != ENOENT { throw Self.failure("remove recovery record") }
   guard fsync(directory) == 0 else { throw Self.failure("sync recovery directory") }
   return
  }
  guard data.count <= Self.limit else { throw HardwareError.invalidData("Recovery record too large") }
  let temporary = ".charge-recovery-" + UUID().uuidString
  let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
  guard fd >= 0 else { throw Self.failure("create recovery record") }
  defer { close(fd); unlinkat(directory, temporary, 0) }
  var offset = 0
  while offset < data.count {
   let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
   if count < 0 { if errno == EINTR { continue }; throw Self.failure("write recovery record") }
   guard count > 0 else { throw HardwareError.unavailable("Incomplete recovery write") }
   offset += count
  }
  guard fsync(fd) == 0 else { throw Self.failure("sync recovery record") }
  guard renameat(directory, temporary, directory, name) == 0 else { throw Self.failure("replace recovery record") }
  guard fsync(directory) == 0 else { throw Self.failure("sync recovery directory") }
 }
 private static func failure(_ operation: String) -> HardwareError {
  .unavailable("\(operation): errno \(errno)")
 }
}
