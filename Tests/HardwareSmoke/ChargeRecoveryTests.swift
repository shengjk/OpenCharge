import Foundation
import Darwin

private final class MemoryRecovery: ChargeRecoveryStore {
 var data: Data?
 var failSave = false
 var loads = 0
 func load() throws -> Data? { loads += 1; return data }
 func save(_ data: Data?) throws {
  if failSave { throw HardwareError.unavailable("injected journal failure") }
  self.data = data
 }
}
private final class RecoveryBackend {
 var values: [String: [UInt8]]
 var writes: [String] = []
 init(_ values: [String: [UInt8]]) { self.values = values }
 func controller(_ store: ChargeRecoveryStore, boot: String, battery: Bool = true, allowed: Bool = true) -> SMCChargeController {
  SMCChargeController(batteryPresent: battery, read: { self.values[$0] }, write: {
   self.writes.append($0); self.values[$0] = $1
  }, authorized: { allowed }, recoveryStore: store, bootSession: boot)
 }
}
@main struct ChargeRecoveryTests {
 static let boot = "11111111-1111-1111-1111-111111111111"
 static func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("unexpected success") } catch {} }
 static func record(key: String = "CHTE", original: [Int] = [0,0,0,0], expected: [Int] = [1,0,0,0], bootSession: String = boot, version: Int = 1, duplicate: Bool = false) throws -> Data {
  let entry: [String: Any] = ["key": key, "write": ["original": original, "expected": expected, "previous": original]]
  return try JSONSerialization.data(withJSONObject: ["version": version, "bootSession": bootSession, "entries": duplicate ? [entry, entry] : [entry]])
 }
 static func child(_ directory: String, stage: String) throws {
  let folder = URL(fileURLWithPath: directory)
  let state = folder.appendingPathComponent("backend.json")
  var values = try JSONDecoder().decode([String: [UInt8]].self, from: Data(contentsOf: state))
  let store = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("recovery").path, owner: geteuid())
  var writes = 0
  let controller = SMCChargeController(batteryPresent: true, read: { values[$0] }, write: { key, value in
   writes += 1
   if stage == "before-first" { _exit(73) }
   values[key] = value
   try JSONEncoder().encode(values).write(to: state, options: .atomic)
   if (stage == "after-first" && writes == 1) || (stage == "after-second" && writes == 2) || (stage == "during-restore" && writes == values.count + 1) { _exit(73) }
  }, authorized: { true }, recoveryStore: store, bootSession: boot)
  try controller.apply(.forceDischarge)
  if stage == "during-restore" { try controller.apply(.restore) }
  preconditionFailure("child did not reach crash boundary")
 }
 static func main() throws {
  if CommandLine.arguments.dropFirst().first == "--boot-identity" {
   let identity = try ChargeRecoveryFileStore.bootSession(); precondition(UUID(uuidString: identity) != nil)
   print("PASS current boot identity readable; identifier omitted"); return
  }
  if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--crash" {
   try child(CommandLine.arguments[2], stage: CommandLine.arguments[3]); return
  }
  let base = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-recovery-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: base) }
  var scenarios = 0
  // Real subprocess termination, using file-backed fake registers and the production journal/planner.
  for charge in [["CHTE": [UInt8](arrayLiteral: 0,0,0,0)], ["CH0B": [UInt8](arrayLiteral: 0), "CH0C": [UInt8](arrayLiteral: 0)]] {
   for adapter in ["CHIE", "CH0J", "CH0I"] {
    for stage in ["before-first", "after-first", "after-second", "during-restore"] {
     let folder = base.appendingPathComponent(UUID().uuidString)
     try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
     var original = charge; original[adapter] = [0]
     try JSONEncoder().encode(original).write(to: folder.appendingPathComponent("backend.json"))
     let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
     process.arguments = ["--crash", folder.path, stage]
     try process.run(); process.waitUntilExit()
     precondition(process.terminationStatus == 73)
     let values = try JSONDecoder().decode([String: [UInt8]].self, from: Data(contentsOf: folder.appendingPathComponent("backend.json")))
     let store = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("recovery").path, owner: geteuid())
     let backend = RecoveryBackend(values)
     try backend.controller(store, boot: boot).apply(.restore)
     precondition(backend.values == original, "interrupted session did not restore \(stage)")
     let remaining = try store.load(); precondition(remaining == nil)
     if stage == "before-first" { precondition(backend.writes.isEmpty) }
     scenarios += 1
    }
   }
  }
  let store = MemoryRecovery(), backend = RecoveryBackend(["CHTE": [0,0,0,0]])
  let client = backend.controller(store, boot: boot)
  _ = client.capabilities(); precondition(store.loads == 0 && backend.writes.isEmpty)
  try client.apply(.inhibitCharge)
  let fresh = backend.controller(store, boot: boot)
  rejects { try fresh.apply(.allowCharge) }; precondition(backend.values["CHTE"] == [1,0,0,0])
  try fresh.apply(.restore); precondition(backend.values["CHTE"] == [0,0,0,0] && store.data == nil); scenarios += 1

  store.data = try record(); backend.values["CHTE"] = [9,0,0,0]; backend.writes = []
  try backend.controller(store, boot: boot).apply(.restore)
  precondition(backend.writes.isEmpty && backend.values["CHTE"] == [9,0,0,0] && store.data == nil); scenarios += 1
  store.data = try record(bootSession: "22222222-2222-2222-2222-222222222222")
  try backend.controller(store, boot: boot).apply(.restore)
  precondition(backend.writes.isEmpty && store.data == nil); scenarios += 1

  for invalid in [Data("broken".utf8), try record(key: "ABCD"), try record(version: 2), try record(duplicate: true), try record(expected: [9,0,0,0]), try record(original: [0]), try record(bootSession: "invalid"), Data(repeating: 32, count: 8193)] {
   store.data = invalid; backend.writes = []
   rejects { try backend.controller(store, boot: boot).apply(.restore) }
   precondition(backend.writes.isEmpty && store.data == invalid); scenarios += 1
  }
  store.data = try record(); backend.writes = []
  rejects { try backend.controller(store, boot: boot, battery: false).apply(.restore) }
  let previousLoads = store.loads
  rejects { try backend.controller(store, boot: boot, allowed: false).apply(.restore) }
  precondition(store.loads == previousLoads && backend.writes.isEmpty); scenarios += 1
  store.data = nil; store.failSave = true; backend.values["CHTE"] = [0,0,0,0]
  rejects { try backend.controller(store, boot: boot).apply(.inhibitCharge) }
  precondition(backend.writes.isEmpty && backend.values["CHTE"] == [0,0,0,0]); scenarios += 1

  store.failSave = false
  let removalClient = backend.controller(store, boot: boot)
  try removalClient.apply(.inhibitCharge); store.failSave = true
  rejects { try removalClient.apply(.restore) }
  precondition(backend.values["CHTE"] == [0,0,0,0] && store.data != nil)
  backend.writes = []; store.failSave = false
  try backend.controller(store, boot: boot).apply(.restore)
  precondition(backend.writes.isEmpty && store.data == nil); scenarios += 1

  store.data = try record(); backend.values.removeValue(forKey: "CHTE")
  let missingClient = backend.controller(store, boot: boot)
  rejects { try missingClient.apply(.restore) }; precondition(store.data != nil)
  backend.values["CHTE"] = [1,0,0,0]; try missingClient.apply(.restore)
  precondition(backend.values["CHTE"] == [0,0,0,0] && store.data == nil); scenarios += 1

  // File safety checks use only a disposable fixture directory, under the current user.
  let safe = base.appendingPathComponent("safe")
  let files = try ChargeRecoveryFileStore(directory: safe.path, owner: geteuid())
  let savedRecord = try record(); try files.save(savedRecord)
  let loadedRecord = try files.load(); precondition(loadedRecord == savedRecord)
  let file = safe.appendingPathComponent("charge-recovery.json")
  let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
  precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  try files.save(nil); let removedRecord = try files.load(); precondition(removedRecord == nil); scenarios += 1
  rejects { _ = try ChargeRecoveryFileStore(directory: safe.path, owner: geteuid() + 1) }; scenarios += 1
  try files.save(savedRecord); chmod(file.path, 0o644)
  rejects { _ = try files.load() }; rejects { try files.save(nil) }
  chmod(file.path, 0o600); try files.save(nil); scenarios += 1
  precondition(mkfifo(file.path, 0o600) == 0)
  rejects { _ = try files.load() }; try FileManager.default.removeItem(at: file); scenarios += 1
  let symlink = base.appendingPathComponent("symlink")
  try FileManager.default.createSymbolicLink(atPath: symlink.path, withDestinationPath: safe.path)
  rejects { _ = try ChargeRecoveryFileStore(directory: symlink.path, owner: geteuid()) }; scenarios += 1
  let unsafe = base.appendingPathComponent("unsafe")
  try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
  rejects { _ = try ChargeRecoveryFileStore(directory: unsafe.path, owner: geteuid()) }; scenarios += 1
  try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: base.appendingPathComponent("unrelated").path)
  rejects { _ = try files.load() }; rejects { try files.save(nil) }
  let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: file.path); precondition(!linkTarget.isEmpty)
  try FileManager.default.removeItem(at: file); scenarios += 1
  try Data(repeating: 1, count: 8193).write(to: file)
  chmod(file.path, 0o600); rejects { _ = try files.load() }
  try FileManager.default.removeItem(at: file); scenarios += 1
  rejects { _ = try ChargeRecoveryFileStore(directory: safe.path, owner: geteuid()) }; scenarios += 1
  try files.save(try record())
  let link = safe.appendingPathComponent("hardlink")
  precondition(Darwin.link(file.path, link.path) == 0)
  rejects { _ = try files.load() }; scenarios += 1
  print("PASS charge recovery: \(scenarios) scenarios including 24 terminated subprocesses; fake registers only")
 }
}
