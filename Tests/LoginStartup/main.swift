import Foundation
import Darwin

@MainActor private final class FakeStartup: LoginStartupBackend {
 var value = false
 var failRead = false
 var failWrite = false
 var acknowledge = true
 var writes: [Bool] = []
 func enabled() throws -> Bool { if failRead { throw LoginStartupError.invalidRegistration }; return value }
 func setEnabled(_ value: Bool) throws { writes.append(value); if failWrite { throw LoginStartupError.invalidRegistration }; if acknowledge { self.value = value } }
}
@main struct LoginStartupChecks {
 private static func require(_ value: Bool, _ message: String = "fixture assertion", file: StaticString = #filePath, line: UInt = #line) { precondition(value,message,file:(file),line:line) }
 @MainActor static func main() throws {
  let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("OpenCharge-login-fixture-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
  func app(_ name: String) throws -> URL {
   let url = root.appendingPathComponent(name+".app"), contents = url.appendingPathComponent("Contents")
   try fm.createDirectory(at:contents,withIntermediateDirectories:true)
   let data = try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":"org.opencharge.app","CFBundleName":"OpenCharge","CFBundlePackageType":"APPL"],format:.xml,options:0)
   try data.write(to:contents.appendingPathComponent("Info.plist")); return url
  }
  let first = try app("Open Charge & \"Fixture\""), second = try app("Moved OpenCharge")
  let directory = root.appendingPathComponent("agents"), file = directory.appendingPathComponent(LegacyLoginStartup.label+".plist")
  let backend = LegacyLoginStartup(directory:directory,app:first)
  require(try backend.enabled() == false)
  require(!fm.fileExists(atPath:directory.path),"read created registration directory")
  try backend.setEnabled(false); require(!fm.fileExists(atPath:directory.path))
  try backend.setEnabled(true); require(try backend.enabled())
  let original = try Data(contentsOf:file)
  let record = try PropertyListSerialization.propertyList(from:original,options:[],format:nil) as! [String:Any]
  require(record["Label"] as? String == LegacyLoginStartup.label)
  require(record["ProgramArguments"] as? [String] == ["/usr/bin/open","-g",first.path])
  require(record["RunAtLoad"] as? Bool == true && record["KeepAlive"] as? Bool == false)
  try backend.setEnabled(true); require(try Data(contentsOf:file) == original)
  let relocated = LegacyLoginStartup(directory:directory,app:second)
  require(try relocated.enabled() == false)
  try relocated.setEnabled(true); require(try relocated.enabled())
  try relocated.setEnabled(false); require(!fm.fileExists(atPath:file.path))
  for data in [Data("foreign".utf8),Data(repeating:65,count:16_385)] {
   try data.write(to:file)
   for enabled in [true,false] {
    do { try backend.setEnabled(enabled); preconditionFailure("Unowned/corrupt record changed") } catch {}
    require(try Data(contentsOf:file) == data)
   }
   try fm.removeItem(at:file)
  }
  let sentinel = root.appendingPathComponent("sentinel"); try original.write(to:sentinel)
  try fm.createSymbolicLink(at:file,withDestinationURL:sentinel)
  do { try backend.setEnabled(true); preconditionFailure("Symlink changed") } catch {}
  require(try Data(contentsOf:sentinel) == original); try fm.removeItem(at:file)
  try original.write(to:file)
  let hardlink = root.appendingPathComponent("hardlink")
  require(link(file.path,hardlink.path) == 0)
  do { try backend.setEnabled(false); preconditionFailure("Hardlinked record removed") } catch {}
  try fm.removeItem(at:hardlink); try fm.removeItem(at:file)
  try original.write(to:file); try fm.setAttributes([.posixPermissions:0o666],ofItemAtPath:file.path)
  do { _ = try backend.enabled(); preconditionFailure("Writable-by-others record accepted") } catch {}
  try fm.removeItem(at:file)
  try fm.setAttributes([.posixPermissions:0o777],ofItemAtPath:directory.path)
  do { try backend.setEnabled(true); preconditionFailure("Writable-by-others directory accepted") } catch {}
  try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:directory.path)
  let directoryLink = root.appendingPathComponent("directory-link")
  try fm.createSymbolicLink(at:directoryLink,withDestinationURL:directory)
  let linkedDirectory = LegacyLoginStartup(directory:directoryLink,app:first)
  do { try linkedDirectory.setEnabled(true); preconditionFailure("Symlinked registration directory accepted") } catch {}
  let native = FakeStartup(), legacy = FakeStartup()
  let coordinator = CoordinatedLoginStartup(native:native,legacy:legacy)
  legacy.value = true
  require(try coordinator.enabled())
  try coordinator.setEnabled(false); require(native.writes == [false] && legacy.writes == [false])
  legacy.value = true; native.acknowledge = false
  try coordinator.setEnabled(true); require(legacy.value,"Unacknowledged native registration erased old route")
  native.acknowledge = true
  try coordinator.setEnabled(true); require(!legacy.value && native.value)
  let unacknowledged = FakeStartup(); unacknowledged.acknowledge = false
  let noFallback = CoordinatedLoginStartup(native:unacknowledged,legacy:FakeStartup())
  do { try noFallback.setEnabled(true); preconditionFailure("Unacknowledged registration reported success") } catch {}
  let fresh = FakeStartup(), model = LoginStartup(backend:fresh)
  require(model.enabled == false && fresh.writes.isEmpty)
  fresh.failRead = true; model.toggle(); require(fresh.writes.isEmpty && model.enabled == nil && model.error != nil)
  fresh.failRead = false; fresh.failWrite = true; model.toggle(); require(model.enabled == false && model.error != nil)
  fresh.failWrite = false; model.toggle(); require(model.enabled == true && model.error == nil)
  model.toggle(); require(model.enabled == false)
  print("PASS login startup: isolated user-agent ownership/bounds/files/symlinks/relocation, native migration/readback, state/error handling; no real login preferences or jobs changed")
 }
}
