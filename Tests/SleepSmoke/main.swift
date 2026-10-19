// All default tests use fake state and private files. Never calls production power setters.
import Foundation
import Darwin
import ChargeCore
import ChargeHardware

let bootA = "00000000-0000-4000-8000-000000000001"
let bootB = "00000000-0000-4000-8000-000000000002"
enum FakeError: Error { case requested }
final class MemoryStore: ChargeRecoveryStore {
 var data: Data?
 var saves = 0
 var failSaves = Set<Int>()
 func load() throws -> Data? { data }
 func save(_ data: Data?) throws { saves += 1; if failSaves.contains(saves) { throw FakeError.requested }; self.data = data }
}
final class FakePower {
 var global = false, lid = false, display = false
 var events: [String] = []
 var fail: String?
 var ignoreGlobalEnable = false
 var onEvent: ((String) -> Void)?
 func event(_ value: String) throws { events.append(value); onEvent?(value); if fail == value { throw FakeError.requested } }
 var transport: SleepOverrideTransport {
  SleepOverrideTransport(captureGlobal: { self.global }, readGlobal: { self.global }, setGlobal: {
   try self.event("global:\($0)"); if !($0 && self.ignoreGlobalEnable) { self.global = $0 }
  }, setLid: { try self.event("lid:\($0)"); self.lid = $0 }, setDisplay: { try self.event("display:\($0)"); self.display = $0 })
 }
}
func rejects(_ run: () throws -> Void) { do { try run(); preconditionFailure("expected rejection") } catch {} }
func controller(_ f: FakePower, _ s: ChargeRecoveryStore, boot: String = bootA) -> SleepOverrideController { .init(transport: f.transport, store: s, bootSession: boot) }

struct FilePower {
 let file: URL
 let crashAt: String?
 func read() throws -> [String: Bool] { try JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: file)) }
 func crash(_ point: String) { if crashAt == point { _exit(91) } }
 func set(_ key: String, _ value: Bool) throws {
  let suffix = key + (value ? "-on" : "-off"); crash("before-" + suffix)
  var values = try read(); values[key] = value; try JSONEncoder().encode(values).write(to: file, options: .atomic)
  crash("after-" + suffix)
 }
 var transport: SleepOverrideTransport {
  SleepOverrideTransport(captureGlobal: { try self.read()["global"]! }, readGlobal: { try self.read()["global"]! }, setGlobal: { try self.set("global", $0) }, setLid: { try self.set("lid", $0) }, setDisplay: { _ in })
 }
}
@main struct SleepSmoke {
 static func main() throws {
  if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--crash" {
   let folder = URL(fileURLWithPath: CommandLine.arguments[2]); let point = CommandLine.arguments[3]
   let store = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("journal").path, owner: geteuid())
   let io = FilePower(file: folder.appendingPathComponent("fake-registers.json"), crashAt: point)
   let c = SleepOverrideController(transport: io.transport, store: store.sleepStore(), bootSession: bootA)
   try c.apply(preventDisplaySleep: false); try c.restore(); preconditionFailure("crash point not reached")
  }
  if CommandLine.arguments.dropFirst().first == "--read-only-api" {
   do { let io = try SleepOverrideIO(); _ = try io.captureGlobal(); print("Sleep SPI symbols/effective+stored baseline inspected read-only; write support and physical effects remain unverified") }
   catch { print("Sleep read-only inspection unavailable:", error.localizedDescription) }
   return
  }
  var scenarios = 0
  for command in ["sleepOverrideOn", "sleepOverrideDisplayOn", "sleepOverrideRestore"] { precondition(HelperClient.supportedActions.contains(command)) }
  for command in ["sleepOverrideOn arbitrary", "sleepOverrideRaw", "sleepOverrideOn\nrestore"] { rejects { _ = try HelperClient.request(command) } }
  scenarios += 1
  do {
   let f = FakePower(), s = MemoryStore(), c = controller(f, s)
   try c.apply(preventDisplaySleep: false); precondition(f.global && f.lid && !f.display && c.active)
   let initial = s.saves; precondition(initial == 2)
   for _ in 0..<1000 { try c.apply(preventDisplaySleep: false) }
   precondition(s.saves == initial && f.events.filter { $0 == "global:true" }.count == 1 && f.events.filter { $0 == "lid:true" }.count == 1)
   try c.apply(preventDisplaySleep: true); precondition(f.display)
   try c.restore(); precondition(!f.global && !f.lid && !f.display && !c.active && s.data == nil); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore(); f.global = true; let c = controller(f, s)
   try c.apply(preventDisplaySleep: true); try c.restore()
   precondition(f.global && !f.lid && !f.display && !f.events.contains("global:false")); scenarios += 1
  }
  for failAt in [1, 2] {
   let f = FakePower(), s = MemoryStore(); s.failSaves = [failAt]; let c = controller(f, s)
   rejects { try c.apply(preventDisplaySleep: true) }
   precondition(!f.global && !f.lid && !f.display)
   if failAt == 1 { precondition(f.events.isEmpty) }
   else { precondition(!f.events.contains("lid:true") && !f.events.contains("lid:false")) }
   scenarios += 1
  }
  for step in ["global:true", "lid:true", "display:true"] {
   let f = FakePower(), s = MemoryStore(); f.fail = step; let c = controller(f, s)
   rejects { try c.apply(preventDisplaySleep: true) }; f.fail = nil; try c.restore()
   precondition(!f.global && !f.lid && !f.display && s.data == nil); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore(); f.ignoreGlobalEnable = true; let c = controller(f, s)
   rejects { try c.apply(preventDisplaySleep: false) }; precondition(!f.events.contains("lid:true") && s.data == nil); scenarios += 1
  }
  for step in ["lid:false", "global:false", "display:false"] {
   let f = FakePower(), s = MemoryStore(), c = controller(f, s); try c.apply(preventDisplaySleep: true); f.fail = step
   rejects { try c.restore() }; f.fail = nil; try c.restore()
   precondition(!f.global && !f.lid && !f.display && s.data == nil); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore(), c = controller(f, s); try c.apply(preventDisplaySleep: false)
   f.global = false; let before = f.events.count; try c.restore()
   precondition(!f.events.dropFirst(before).contains("global:false") && s.data == nil); scenarios += 1
  }
  for reboot in [false, true] {
   let f = FakePower(), s = MemoryStore(); try controller(f, s).apply(preventDisplaySleep: false)
   f.events = []; if reboot { f.lid = false }
   try controller(f, s, boot: reboot ? bootB : bootA).recover()
   precondition(!f.global && !f.lid && s.data == nil)
   precondition(f.events.contains("lid:false") != reboot); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore(), c = controller(f, s); try c.apply(preventDisplaySleep: false)
   s.failSaves = [s.saves + 1, s.saves + 2, s.saves + 3]; rejects { try c.restore() }
   s.failSaves = []; try c.restore(); precondition(s.data == nil && !f.global && !f.lid); scenarios += 1
  }
  for bytes in [Data("bad".utf8), Data(repeating: 32, count: 2049), try JSONSerialization.data(withJSONObject: ["version": 9, "boot": bootA, "originalGlobal": false, "globalPending": true, "lidPending": true]), try JSONSerialization.data(withJSONObject: ["version": 1, "boot": "bad", "originalGlobal": false, "globalPending": true, "lidPending": true]), try JSONSerialization.data(withJSONObject: ["version": 1, "boot": bootA, "originalGlobal": true, "globalPending": true, "lidPending": true])] {
   let f = FakePower(), s = MemoryStore(); s.data = bytes; let c = controller(f, s)
   rejects { try c.recover() }; precondition(f.events.isEmpty && s.data == bytes); scenarios += 1
  }
  // Model a write that changes the API's cached value but fails to commit.
  for recoveryBoot in [bootA, bootB] {
   let store = MemoryStore()
   var cached = false, committed = false, failRelease = false
   let io = SleepOverrideTransport(captureGlobal: { cached }, readGlobal: { cached }, setGlobal: { value in
    cached = value
    if !value && failRelease { throw FakeError.requested }
    committed = value
   }, setLid: { _ in }, setDisplay: { _ in })
   let c = SleepOverrideController(transport: io, store: store, bootSession: bootA)
   try c.apply(preventDisplaySleep: false); failRelease = true
   rejects { try c.restore() }
   var retryFailed = false
   do { try c.restore() } catch { retryFailed = true }
   if !retryFailed || store.data == nil || !committed {
    print("REGRESSION: cached false cleared recovery after a failed persistent restore; durable state:", committed, "record retained:", store.data != nil)
    exit(2)
   }
   failRelease = false
   let retry = SleepOverrideController(transport: io, store: store, bootSession: recoveryBoot)
   try retry.recover(); precondition(!committed && !cached && store.data == nil); scenarios += 1
  }
  // A failed enable may commit while its readback still reports the old value.
  do {
   let store = MemoryStore(); var committed = false; var releases = 0
   let io = SleepOverrideTransport(captureGlobal: { false }, readGlobal: { false }, setGlobal: { value in
    committed = value; if value { throw FakeError.requested }; releases += 1
   }, setLid: { _ in }, setDisplay: { _ in })
   let c = SleepOverrideController(transport: io, store: store, bootSession: bootA)
   rejects { try c.apply(preventDisplaySleep: false) }
   precondition(!committed && releases == 1 && store.data == nil); scenarios += 1
  }
  // Legacy records lack phases: a false cache is not proof of durable restoration.
  do {
   let s = MemoryStore(); s.data = try JSONSerialization.data(withJSONObject: ["version": 1, "boot": bootA, "originalGlobal": false, "globalPending": true, "lidPending": false])
   var committed = true
   let io = SleepOverrideTransport(captureGlobal: { false }, readGlobal: { false }, setGlobal: { committed = $0 }, setLid: { _ in }, setDisplay: { _ in })
   try SleepOverrideController(transport: io, store: s, bootSession: bootB).recover()
   precondition(!committed && s.data == nil); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore(), c = controller(f, s); try c.apply(preventDisplaySleep: false)
   s.failSaves = [s.saves + 2]; rejects { try c.restore() }
   precondition(!f.events.contains("global:false") && f.global && s.data != nil)
   s.failSaves = []; try c.restore(); precondition(!f.global && s.data == nil); scenarios += 1
  }
  do {
   let f = FakePower(), s = MemoryStore()
   s.data = try JSONSerialization.data(withJSONObject: ["version": 1, "boot": bootA, "originalGlobal": false, "globalPending": true, "lidPending": false, "globalPhase": "unknown"])
   let before = s.data; rejects { try controller(f, s).recover() }
   precondition(f.events.isEmpty && s.data == before); scenarios += 1
  }
  let temp = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-sleep-fixture-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false); defer { try? FileManager.default.removeItem(at: temp) }
  do {
   let path = temp.appendingPathComponent("isolation")
   let store = try ChargeRecoveryFileStore(directory: path.path, owner: geteuid())
   let sleep = store.sleepStore(), led = store.magSafeStore(); try store.save(Data("charge".utf8)); try led.save(Data("led".utf8))
   let f = FakePower(), c = controller(f, sleep); try c.apply(preventDisplaySleep: false); try c.restore()
   let chargeBytes = try store.load(), ledBytes = try led.load(), sleepBytes = try sleep.load()
   precondition(chargeBytes == Data("charge".utf8) && ledBytes == Data("led".utf8) && sleepBytes == nil); scenarios += 1
   try FileManager.default.createSymbolicLink(atPath: path.appendingPathComponent("sleep-recovery.json").path, withDestinationPath: path.appendingPathComponent("charge-recovery.json").path)
   rejects { _ = try sleep.load() }; let unchanged = try store.load(); precondition(unchanged == Data("charge".utf8)); scenarios += 1
  }
  let crashPoints = ["before-global-on", "after-global-on", "before-lid-on", "after-lid-on", "before-lid-off", "after-lid-off", "before-global-off", "after-global-off"]
  for point in crashPoints {
   let folder = temp.appendingPathComponent(point); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
   let file = folder.appendingPathComponent("fake-registers.json"); try JSONEncoder().encode(["global": false, "lid": false]).write(to: file)
   let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["--crash", folder.path, point]
   try child.run(); child.waitUntilExit(); precondition(child.terminationReason == .exit && child.terminationStatus == 91)
   let store = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("journal").path, owner: geteuid())
   let io = FilePower(file: file, crashAt: nil), c = SleepOverrideController(transport: FilePower(file: file, crashAt: nil).transport, store: store.sleepStore(), bootSession: bootA)
   try c.recover(); let values = try io.read(), recovered = try store.sleepStore().load(); precondition(values["global"] == false && values["lid"] == false && recovered == nil); scenarios += 1
  }
  print("Sleep override:",scenarios,"fake/file scenarios including",crashPoints.count,"abrupt subprocesses; no system power writes or assertions")
 }
}
