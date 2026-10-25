import Foundation
import Combine
import ServiceManagement
import Darwin

@MainActor protocol LoginStartupBackend: AnyObject {
 func enabled() throws -> Bool
 func setEnabled(_ value: Bool) throws
}
enum LoginStartupError: Error, LocalizedError {
 case invalidRegistration
 var errorDescription: String? { NSLocalizedString("无法安全配置登录启动；请检查应用位置与现有登录项。", comment: "") }
}
@available(macOS 13.0, *)
@MainActor private final class NativeLoginStartup: LoginStartupBackend {
 func enabled() throws -> Bool { SMAppService.mainApp.status == .enabled }
 func setEnabled(_ value: Bool) throws {
  let status = SMAppService.mainApp.status
  if value {
   if status != .enabled { try SMAppService.mainApp.register() }
  } else if status == .enabled || status == .requiresApproval { try SMAppService.mainApp.unregister() }
 }
}

/// An owned one-shot user agent for the next login. This never loads a job or
/// launches a process in the current session. No root directory is touched.
@MainActor final class LegacyLoginStartup: LoginStartupBackend {
 static let label = "org.opencharge.login"
 private let directory: URL
 private let app: URL
 private let file = label+".plist"
 init(directory: URL, app: URL) { self.directory = directory; self.app = app.standardizedFileURL }
 private struct Record { let data: Data; let path: String }
 private func directoryHandle(create: Bool) throws -> Int32? {
  if create { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755]) }
  let fd = open(directory.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  if fd < 0 { if !create && errno == ENOENT { return nil }; throw LoginStartupError.invalidRegistration }
  var info = stat()
  guard fstat(fd,&info) == 0, info.st_uid == geteuid(), (info.st_mode & 0o022) == 0 else { close(fd); throw LoginStartupError.invalidRegistration }
  return fd
 }
 private func read(_ directory: Int32) throws -> Record? {
  let fd = openat(directory,file,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
  if fd < 0 { if errno == ENOENT { return nil }; throw LoginStartupError.invalidRegistration }
  let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true); defer { try? handle.close() }
  var info = stat()
  guard fstat(fd,&info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
        info.st_uid == geteuid(), info.st_nlink == 1, (info.st_mode & 0o022) == 0,
        info.st_size >= 0, info.st_size <= 16_384 else { throw LoginStartupError.invalidRegistration }
  let data = try handle.read(upToCount:16_385) ?? Data()
  guard data.count <= 16_384,
        let value = try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any],
        Set(value.keys) == Set(["Label","ProgramArguments","RunAtLoad","KeepAlive","OpenChargeLoginVersion"]),
        let version = value["OpenChargeLoginVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
        let run = value["RunAtLoad"] as? NSNumber, CFGetTypeID(run) == CFBooleanGetTypeID(),
        let keep = value["KeepAlive"] as? NSNumber, CFGetTypeID(keep) == CFBooleanGetTypeID(),
        value["Label"] as? String == Self.label, value["OpenChargeLoginVersion"] as? Int == 1,
        value["RunAtLoad"] as? Bool == true, value["KeepAlive"] as? Bool == false,
        let args = value["ProgramArguments"] as? [String], args.count == 3,
        args[0] == "/usr/bin/open", args[1] == "-g", args[2].hasPrefix("/"),
        !args[2].contains("\0"), URL(fileURLWithPath:args[2]).pathExtension == "app" else { throw LoginStartupError.invalidRegistration }
  return Record(data:data,path:args[2])
 }
 func enabled() throws -> Bool {
  guard let fd = try directoryHandle(create:false) else { return false }; defer { close(fd) }
  return try read(fd)?.path == app.path
 }
 func setEnabled(_ value: Bool) throws {
  guard let fd = try directoryHandle(create:value) else { return }; defer { close(fd) }
  let before = try read(fd)
  if !value {
   guard let before else { return }
   guard try read(fd)?.data == before.data, unlinkat(fd,file,0) == 0 else { throw LoginStartupError.invalidRegistration }
   return
  }
  var isDirectory: ObjCBool = false
  guard app.isFileURL, app.pathExtension == "app", app.path.hasPrefix("/"),
        FileManager.default.fileExists(atPath:app.path,isDirectory:&isDirectory), isDirectory.boolValue,
        Bundle(url:app)?.bundleIdentifier == "org.opencharge.app" else { throw LoginStartupError.invalidRegistration }
  if before?.path == app.path { return }
  let values: [String:Any] = ["Label":Self.label,"ProgramArguments":["/usr/bin/open","-g",app.path],"RunAtLoad":true,"KeepAlive":false,"OpenChargeLoginVersion":1]
  let data = try PropertyListSerialization.data(fromPropertyList:values,format:.xml,options:0)
  let temporary = "."+Self.label+"."+UUID().uuidString+".tmp"
  let output = openat(fd,temporary,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
  guard output >= 0 else { throw LoginStartupError.invalidRegistration }
  defer { unlinkat(fd,temporary,0) }
  let handle = FileHandle(fileDescriptor:output,closeOnDealloc:true)
  do { try handle.write(contentsOf:data); try handle.synchronize(); try handle.close() }
  catch { try? handle.close(); throw error }
  guard try read(fd)?.data == before?.data else { throw LoginStartupError.invalidRegistration }
  if before == nil {
   guard linkat(fd,temporary,fd,file,0) == 0 else { throw LoginStartupError.invalidRegistration }
   guard unlinkat(fd,temporary,0) == 0 else { throw LoginStartupError.invalidRegistration }
  } else {
   guard renameat(fd,temporary,fd,file) == 0 else { throw LoginStartupError.invalidRegistration }
  }
  guard try read(fd)?.path == app.path else { throw LoginStartupError.invalidRegistration }
 }
}

/// Keep an owned older agent visible after an OS upgrade. Explicit disable clears
/// both routes; explicit native enable retires the old agent only after readback.
@MainActor final class CoordinatedLoginStartup: LoginStartupBackend {
 private let native: LoginStartupBackend?
 private let legacy: LoginStartupBackend
 init(native: LoginStartupBackend?, legacy: LoginStartupBackend) { self.native = native; self.legacy = legacy }
 func enabled() throws -> Bool {
  let native = try self.native?.enabled() ?? false
  let legacy = try self.legacy.enabled()
  return native || legacy
 }
 func setEnabled(_ value: Bool) throws {
  if let native {
   try native.setEnabled(value)
   if !value { try legacy.setEnabled(false) }
   else if try native.enabled() { try legacy.setEnabled(false) }
   else if try !legacy.enabled() { throw LoginStartupError.invalidRegistration }
  } else { try legacy.setEnabled(value) }
 }
}
@MainActor final class LoginStartup: ObservableObject {
 private let backend: LoginStartupBackend
 @Published private(set) var enabled: Bool?
 @Published private(set) var error: String?
 convenience init(bundle: Bundle = .main) {
  let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents",isDirectory:true)
  let legacy = LegacyLoginStartup(directory:directory,app:bundle.bundleURL)
  let native: LoginStartupBackend?
  if #available(macOS 13.0, *) { native = NativeLoginStartup() } else { native = nil }
  self.init(backend:CoordinatedLoginStartup(native:native,legacy:legacy))
 }
 init(backend: LoginStartupBackend) { self.backend = backend; reload() }
 func reload() {
  do { enabled = try backend.enabled(); error = nil }
  catch { enabled = nil; self.error = error.localizedDescription }
 }
 func toggle() {
  do { try backend.setEnabled(!backend.enabled()); reload() }
  catch { self.error = error.localizedDescription; enabled = try? backend.enabled() }
 }
}
