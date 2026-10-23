import Foundation
import Darwin

private final class CrashJournal: ChargeRecoveryStore {
 let file: ChargeRecoveryFileStore
 var before: (() -> Void)?
 var after: (() -> Void)?
 init(_ path: String) throws { file = try ChargeRecoveryFileStore(directory: path, owner: geteuid()) }
 func load() throws -> Data? { try file.load() }
 func save(_ data: Data?) throws { before?(); try file.save(data); after?() }
}
private final class CrashScenario {
 let directory: URL
 let stage: String
 var phase = "apply"
 var saves = 0
 var writes = 0
 var pending: (String, Int)?
 init(_ directory: URL, stage: String) { self.directory = directory; self.stage = stage }
 var backend: URL { directory.appendingPathComponent("fake-firmware.json") }
 func values() throws -> [String: UInt8] { try JSONDecoder().decode([String: UInt8].self, from: Data(contentsOf: backend)) }
 func writeValues(_ values: [String: UInt8]) throws { try JSONEncoder().encode(values).write(to: backend, options: .atomic) }
 func stop(_ point: String, _ number: Int) { if stage == "\(phase)-\(point)-\(number)" { _exit(73) } }
 func child() throws {
  let store = try CrashJournal(directory.appendingPathComponent("recovery").path)
  store.before = { self.saves += 1; self.stop("save-before", self.saves) }
  store.after = { self.stop("save-after", self.saves) }
  let controller = SMCFirmwareChargeController(eligibleHost: true, batteryPresent: true, read: { key in
   let readback = self.pending.flatMap { $0.0 == key ? $0.1 : nil }
   if let readback { self.stop("readback-before", readback) }
   let value = try self.values()[key].map { SMCByteReading(dataType: "ui8 ", bytes: [$0]) }
   if let readback { self.stop("readback-after", readback); self.pending = nil }
   return value
  }, write: { key, value in
   self.writes += 1; self.stop("write-before", self.writes)
   var values = try self.values(); values[key] = value; try self.writeValues(values)
   self.pending = (key, self.writes); self.stop("write-after", self.writes)
  }, authorized: { true }, recoveryStore: store, bootSession: FirmwareChargeCrashTests.boot)
  try controller.inhibitCharging()
  if stage.hasPrefix("restore-") {
   phase = "restore"; saves = 0; writes = 0; pending = nil
   try controller.restore()
  } else if stage.hasPrefix("exit-") {
   phase = "exit"; saves = 0; writes = 0; pending = nil
   try controller.finishExit(limit: 75)
  }
  _exit(74) // Every selected interruption point must actually be reached.
 }
}
@main struct FirmwareChargeCrashTests {
 static let boot = "11111111-1111-1111-1111-111111111111"
 static func main() throws {
  if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--child" {
   try CrashScenario(URL(fileURLWithPath: CommandLine.arguments[2]), stage: CommandLine.arguments[3]).child()
   return
  }
  let base = FileManager.default.temporaryDirectory.appendingPathComponent("opencharge-firmware-crash-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: base) }
  var count = 0
  for phase in ["apply", "restore", "exit"] {
   for point in ["save-before", "save-after", "write-before", "write-after", "readback-before", "readback-after"] {
    for index in (phase == "exit" && !point.hasPrefix("save") ? [1] : [1, 2]) {
     let stage = "\(phase)-\(point)-\(index)"
     let folder = base.appendingPathComponent(stage)
     try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
     let scenario = CrashScenario(folder, stage: stage)
     let original: [String: UInt8] = ["CH0B": 2, "BCLM": 80, "BSIn": 0]
     try scenario.writeValues(original)
     let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
     child.arguments = ["--child", folder.path, stage]
     try child.run(); child.waitUntilExit()
     precondition(child.terminationReason == .exit && child.terminationStatus == 73, "fixture did not reach \(stage)")
     let store = try CrashJournal(folder.appendingPathComponent("recovery").path)
     var writes = 0
     let recovered = SMCFirmwareChargeController(eligibleHost: true, batteryPresent: true, read: { key in
      try scenario.values()[key].map { SMCByteReading(dataType: "ui8 ", bytes: [$0]) }
     }, write: { key, value in
      writes += 1; var values = try scenario.values(); values[key] = value; try scenario.writeValues(values)
     }, authorized: { true }, recoveryStore: store, bootSession: boot)
     try recovered.restore()
     let values = try scenario.values(), journal = try store.load()
     let expected: [String: UInt8] = stage == "exit-save-after-2" ? ["CH0B": 0, "BCLM": 75, "BSIn": 0] : original
     precondition(values == expected && journal == nil, "cold recovery failed at \(stage)")
     let completed = writes
     try recovered.restore(); precondition(writes == completed, "recovery must be idempotent")
     count += 1
    }
   }
  }
  print("PASS numeric firmware crash recovery: \(count) terminated subprocesses around actual fixture journal saves/deletions and fake-register writes/readbacks; no hardware")
 }
}
