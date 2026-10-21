import Foundation
import Darwin

private final class LEDMemoryRecovery: ChargeRecoveryStore {
 var data: Data?
 var saves = 0
 var loads = 0
 var failSave = false
 func load() throws -> Data? { loads += 1; return data }
 func save(_ data: Data?) throws {
  if failSave { throw HardwareError.unavailable("injected LED journal failure") }
  self.data = data; saves += 1
 }
}
@main struct MagSafeRecoveryTests {
 static let boot = "11111111-1111-1111-1111-111111111111"
 static func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("unexpected success") } catch {} }
 static func record(original: [Int] = [0], expected: [Int] = [2], previous: [Int]? = [0], version: Int = 1, identity: String = boot) throws -> Data {
  var object: [String: Any] = ["version": version, "bootSession": identity, "original": original, "expected": expected]
  if let previous { object["previous"] = previous }
  return try JSONSerialization.data(withJSONObject: object)
 }
 static func child(_ folder: URL, stage: String) throws {
  let stateURL = folder.appendingPathComponent("fake-led")
  var state = Array(try Data(contentsOf: stateURL))
  let initial = state[0]
  let files = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("recovery").path, owner: geteuid())
  var writes = 0
  let controller = MagSafeController(read: { state }, write: { bytes in
   writes += 1
   if stage == "before-first" { _exit(73) }
   state = bytes; try Data(bytes).write(to: stateURL, options: .atomic)
   if stage == "after-first" && writes == 1 || stage == "after-second" && writes == 2 || stage == "during-restore" && writes == 3 { _exit(73) }
  }, recoveryStore: files.magSafeStore(), bootSession: boot)
  if stage == "blink-cache" {
   let session = MagSafeSession(controller: controller)
   try session.select(.blinkOrange, now: 0)
   try session.tick(now: 1); try session.tick(now: 2)
   _exit(73)
  }
  try controller.set(initial == 2 ? .orange : .green)
  try controller.set(initial == 1 ? .orange : .off)
  try controller.restore()
  preconditionFailure("LED crash boundary not reached")
 }
 static func main() throws {
  if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--crash" {
   try child(URL(fileURLWithPath: CommandLine.arguments[2]), stage: CommandLine.arguments[3]); return
  }
  let base = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-led-recovery-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: base) }
  var scenarios = 0
  for original: UInt8 in [0, 1, 2, 3, 4, 6] {
   for stage in ["before-first", "after-first", "after-second", "during-restore", "blink-cache"] {
    let folder = base.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    try Data([original]).write(to: folder.appendingPathComponent("fake-led"))
    let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--crash", folder.path, stage]
    try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 73)
    var state = Array(try Data(contentsOf: folder.appendingPathComponent("fake-led"))); var writes = 0
    let files = try ChargeRecoveryFileStore(directory: folder.appendingPathComponent("recovery").path, owner: geteuid())
    let store = files.magSafeStore()
    let controller = MagSafeController(read: { state }, write: { state = $0; writes += 1 }, recoveryStore: store, bootSession: boot)
    try controller.restore(); precondition(state == [original])
    let remaining = try store.load(); precondition(remaining == nil)
    if stage == "before-first" || stage == "during-restore" { precondition(writes == 0) }
    scenarios += 1
   }
  }
  let store = LEDMemoryRecovery()
  var state: [UInt8]? = [0], writes = 0
  var failWrite = false
  func controller(identity: String = boot) -> MagSafeController {
   MagSafeController(read: { state }, write: {
    if failWrite { throw HardwareError.unavailable("injected LED write failure") }
    state = $0; writes += 1
   }, recoveryStore: store, bootSession: identity)
  }
  let first = controller(); _ = try first.status(); precondition(store.loads == 0)
  try first.set(.green)
  let pending = controller(); rejects { try pending.set(.orange) }; precondition(state == [2])
  try pending.restore(); precondition(state == [0] && store.data == nil); scenarios += 1
  store.data = try record(); state = [1]; writes = 0
  try controller().restore(); precondition(state == [1] && writes == 0 && store.data == nil); scenarios += 1
  store.data = try record(identity: "22222222-2222-2222-2222-222222222222"); state = [2]
  try controller().restore(); precondition(state == [2] && writes == 0 && store.data == nil); scenarios += 1
  for invalid in [Data("broken".utf8), try record(version: 2), try record(original: []), try record(original: [5]), try record(expected: [0]), try record(expected: [5]), try record(expected: [3,4]), try record(previous: [9]), try record(identity: "invalid"), Data(repeating: 32, count: 8193)] {
   store.data = invalid; rejects { try controller().restore() }; precondition(writes == 0 && store.data == invalid); scenarios += 1
  }
  store.data = nil; state = [0]; store.failSave = true
  rejects { try controller().set(.orange) }; precondition(writes == 0 && state == [0]); store.failSave = false; scenarios += 1
  store.data = try record(); state = nil
  let missing = controller(); rejects { try missing.restore() }; precondition(store.data != nil)
  state = [2]; try missing.restore(); precondition(state == [0] && store.data == nil); scenarios += 1
  store.data = try record(); state = [2]; failWrite = true
  let retry = controller(); rejects { try retry.restore() }; precondition(store.data != nil && state == [2])
  failWrite = false; try retry.restore(); precondition(state == [0] && store.data == nil); scenarios += 1
  store.data = try record(); state = [2]; store.failSave = true
  rejects { try controller().restore() }; precondition(state == [0] && store.data != nil)
  writes = 0; store.failSave = false; try controller().restore(); precondition(writes == 0 && store.data == nil); scenarios += 1
  state = [2]; let noOp = controller(); let savesBefore = store.saves
  try noOp.set(.green); try noOp.restore(); precondition(writes == 0 && store.saves == savesBefore && store.data == nil); scenarios += 1
  state = [0]; let external = controller(); try external.set(.green); state = [4]
  try external.set(.orange); precondition(store.data == nil && state == [4]); scenarios += 1
  state = [0]; store.saves = 0
  let blinking = MagSafeSession(controller: controller())
  try blinking.select(.blinkOrange, now: 0)
  for tick in 1...1000 { try blinking.tick(now: Double(tick)) }
  precondition(store.saves == 1, "native blinking must not fsync every tick")
  try controller().restore(); precondition(state == [0] && store.data == nil); scenarios += 1
  for expected in [3, 6] {
   store.data = try record(original: [0], expected: [expected], previous: [0]); state = [UInt8(expected)]
   try controller().restore(); precondition(state == [0] && store.data == nil); scenarios += 1
  }
  let files = try ChargeRecoveryFileStore(directory: base.appendingPathComponent("shared").path, owner: geteuid())
  let sentinel = Data("charge record remains independent".utf8)
  try files.save(sentinel)
  let ledFiles = files.magSafeStore(); let ledRecord = try record(); try ledFiles.save(ledRecord)
  let chargeData = try files.load(), ledData = try ledFiles.load()
  precondition(chargeData == sentinel && ledData == ledRecord)
  try ledFiles.save(nil); let stillCharge = try files.load(); precondition(stillCharge == sentinel); scenarios += 1
  let ledPath = base.appendingPathComponent("shared/magsafe-recovery.json")
  try FileManager.default.createSymbolicLink(atPath: ledPath.path, withDestinationPath: base.appendingPathComponent("unrelated").path)
  rejects { _ = try ledFiles.load() }; rejects { try ledFiles.save(nil) }
  let untouchedCharge = try files.load(); precondition(untouchedCharge == sentinel); scenarios += 1
  print("PASS LED recovery: \(scenarios) scenarios including 30 terminated subprocesses; fake ACLC only")
 }
}
