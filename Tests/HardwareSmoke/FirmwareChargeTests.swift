import Foundation

private final class FirmwareJournal: ChargeRecoveryStore {
 var data: Data?
 var loads = 0
 var saves = 0
 var fail: ((Data?) -> Bool)?
 var afterSave: ((Data?) -> Void)?
 func load() throws -> Data? { loads += 1; return data }
 func save(_ value: Data?) throws {
  saves += 1
  if fail?(value) == true { throw HardwareError.unavailable("injected journal failure") }
  data = value; afterSave?(value)
 }
}
private final class FirmwareBackend {
 var values: [String: SMCByteReading]
 var writes: [(String, UInt8)] = []
 var readCount = 0
 var beforeRead: ((String) throws -> Void)?
 var beforeWrite: ((String, UInt8) throws -> Void)?
 var afterWrite: ((String, UInt8) throws -> Void)?
 var ignoreWrite: String?
 init(charge: UInt8 = 2, limit: UInt8 = 80) {
  values = ["CH0B": Self.value(charge), "BCLM": Self.value(limit), "BSIn": Self.value(0)]
 }
 static func value(_ value: UInt8) -> SMCByteReading { SMCByteReading(dataType: "ui8 ", bytes: [value]) }
 var bytes: [String: [UInt8]] { values.mapValues(\.bytes) }
 func controller(_ store: FirmwareJournal? = nil, boot: String = FirmwareChargeTests.boot,
                 eligible: Bool = true, battery: Bool = true, allowed: Bool = true) -> SMCFirmwareChargeController {
  SMCFirmwareChargeController(eligibleHost: eligible, batteryPresent: battery, read: { key in
   self.readCount += 1; try self.beforeRead?(key); return self.values[key]
  }, write: { key, value in
   try self.beforeWrite?(key, value)
   self.writes.append((key, value))
   if self.ignoreWrite != key { self.values[key] = Self.value(value) }
   try self.afterWrite?(key, value)
  }, authorized: { allowed }, recoveryStore: store, bootSession: boot)
 }
}
@main struct FirmwareChargeTests {
 static let boot = "11111111-1111-1111-1111-111111111111"
 static var scenarios = 0
 static func rejects(_ body: () throws -> Void) {
  do { try body(); preconditionFailure("unexpected success") } catch {}
 }
 static func record(key: String = "CH0B", original: Int = 2, expected: Int = 0, previous: Int? = 2,
                    kind: String = "numericFirmwareV1", version: Int = 1, duplicate: Bool = false) throws -> Data {
  var entry: [String: Any] = ["key": key, "original": original, "expected": expected]
  if let previous { entry["previous"] = previous }
  return try JSONSerialization.data(withJSONObject: ["kind": kind, "version": version, "bootSession": boot, "entries": duplicate ? [entry, entry] : [entry]])
 }
 static func noOpKeyRace() throws {
  for exit in [false, true] {
   let fake = FirmwareBackend(charge: 0), store = FirmwareJournal(), controller = fake.controller(store)
   fake.beforeRead = { key in
    if key == "BCLM" && fake.values[key]?.bytes == [60] { fake.values["CH0B"] = FirmwareBackend.value(2) }
   }
   rejects { if exit { try controller.finishExit(limit: 60) } else { try controller.setLimit(60) } }
   precondition(fake.values["CH0B"]?.bytes == [2] && fake.values["BCLM"]?.bytes == [80] && store.data == nil,
                "no-op-key interference must fail and preserve the external change")
  }
 }
 static func knownConflictPreflight() throws {
  let fake = FirmwareBackend(charge: 0), store = FirmwareJournal(), controller = fake.controller(store)
  try controller.inhibitCharging()
  fake.values["CH0B"] = FirmwareBackend.value(2); fake.values["BCLM"] = FirmwareBackend.value(70)
  let writes = fake.writes.count
  rejects { try controller.setLimit(60) }
  precondition(fake.writes.count == writes && fake.values["CH0B"]?.bytes == [2] && fake.values["BCLM"]?.bytes == [70],
               "a known second-key ownership conflict must prevent all new writes")
 }
 static func main() throws {
  if CommandLine.arguments.last == "noop-race" { try noOpKeyRace(); return }
  if CommandLine.arguments.last == "known-conflict" { try knownConflictPreflight(); return }
  // Status reads are pure, including when an interrupted journal exists.
  let statusBackend = FirmwareBackend(), statusStore = FirmwareJournal()
  statusStore.data = try record()
  let statusController = statusBackend.controller(statusStore, allowed: false)
  let initialStatus = try statusController.inspect()
  precondition(initialStatus == FirmwareChargeStatus(limit: 80, chargingAllowed: false))
  precondition(statusStore.loads == 0 && statusStore.saves == 0 && statusBackend.writes.isEmpty)
  scenarios += 1
  for charge: UInt8 in [0, 2] {
   for limit: UInt8 in [15, 20, 100] {
    for input: UInt8 in [0, 1, 2, 3, 254, 255] {
     let fake = FirmwareBackend(charge: charge, limit: limit)
     fake.values["BSIn"] = FirmwareBackend.value(input)
     let status = try fake.controller().inspect()
     precondition(status.chargingAllowed == (charge == 0 && (limit > 15 || input & 1 != 0)))
     precondition(fake.writes.isEmpty)
    }
   }
  }; scenarios += 1
  let missingInput = FirmwareBackend(charge: 0, limit: 15)
  missingInput.values.removeValue(forKey: "BSIn")
  let unavailableStatus = try missingInput.controller().inspect()
  precondition(unavailableStatus.chargingAllowed == nil)
  missingInput.values["BCLM"] = FirmwareBackend.value(80)
  let allowedStatus = try missingInput.controller().inspect()
  precondition(allowedStatus.chargingAllowed == true)
  missingInput.values["BCLM"] = FirmwareBackend.value(15)
  missingInput.values["BSIn"] = SMCByteReading(dataType: "ui16", bytes: [0, 1])
  rejects { _ = try missingInput.controller().inspect() }; scenarios += 1
  for kind in ["CH0B", "BCLM"] {
   for reading in [nil, SMCByteReading(dataType: "si8 ", bytes: [0]), SMCByteReading(dataType: "ui8 ", bytes: [0, 0]), FirmwareBackend.value(255)] as [SMCByteReading?] {
    let fake = FirmwareBackend(), store = FirmwareJournal(); fake.values[kind] = reading
    rejects { try fake.controller(store).setLimit(60) }
    precondition(fake.writes.isEmpty && store.data == nil)
   }
  }; scenarios += 1
  for key in ["CH0B", "BCLM", "BSIn"] {
   let fake = FirmwareBackend(charge: 0, limit: key == "BSIn" ? 15 : 80), store = FirmwareJournal()
   fake.beforeRead = { requested in if key == requested { throw HardwareError.unavailable("injected read failure") } }
   rejects { _ = try fake.controller(store).inspect() }
   if key != "BSIn" { rejects { try fake.controller(store).setLimit(60) } }
   precondition(fake.writes.isEmpty && store.data == nil)
  }; scenarios += 1
  for (eligible, battery, allowed) in [(false, true, true), (true, false, true), (true, true, false)] {
   let fake = FirmwareBackend(), store = FirmwareJournal()
   rejects { try fake.controller(store, eligible: eligible, battery: battery, allowed: allowed).setLimit(70) }
   precondition(fake.readCount == 0 && store.loads == 0 && store.saves == 0 && fake.writes.isEmpty)
  }; scenarios += 1
  for invalid in [Int.min, -1, 0, 15, 19, 101, Int.max] {
   let fake = FirmwareBackend(), store = FirmwareJournal(), controller = fake.controller(store)
   rejects { try controller.setLimit(invalid) }; rejects { try controller.finishExit(limit: invalid) }
   precondition(fake.readCount == 0 && store.loads == 0 && store.saves == 0 && fake.writes.isEmpty)
  }; scenarios += 1
  for target in [20, 100] {
   let fake = FirmwareBackend(), original = fake.bytes, store = FirmwareJournal(), controller = fake.controller(store)
   try controller.setLimit(target)
   precondition(fake.writes.map(\.0) == ["CH0B", "BCLM"])
   precondition(fake.values["CH0B"]?.bytes == [0] && fake.values["BCLM"]?.bytes == [UInt8(target)])
   try controller.restore(); precondition(fake.bytes == original && store.data == nil)
  }; scenarios += 1
  let repeated = FirmwareBackend(), originalRepeated = repeated.bytes, repeatedStore = FirmwareJournal()
  let repeatedController = repeated.controller(repeatedStore)
  try repeatedController.allowCharging(); try repeatedController.inhibitCharging(); try repeatedController.setLimit(65)
  try repeatedController.restore(); precondition(repeated.bytes == originalRepeated && repeatedStore.data == nil)
  scenarios += 1
  let noOp = FirmwareBackend(charge: 0, limit: 80), noOpStore = FirmwareJournal(), noOpController = noOp.controller(noOpStore)
  try noOpController.setLimit(80); try noOpController.restore()
  precondition(noOp.writes.isEmpty && noOpStore.saves == 0); scenarios += 1
  // Capture every visible write-ahead/readback window and cold-recover its bytes.
  let crashBackend = FirmwareBackend(), crashOriginal = crashBackend.bytes, crashStore = FirmwareJournal()
  var snapshots: [(Data?, [String: SMCByteReading])] = []
  crashStore.afterSave = { _ in snapshots.append((crashStore.data, crashBackend.values)) }
  crashBackend.beforeRead = { _ in snapshots.append((crashStore.data, crashBackend.values)) }
  crashBackend.beforeWrite = { _, _ in snapshots.append((crashStore.data, crashBackend.values)) }
  crashBackend.afterWrite = { _, _ in snapshots.append((crashStore.data, crashBackend.values)) }
  try crashBackend.controller(crashStore).inhibitCharging()
  precondition(snapshots.count >= 10)
  for (data, values) in snapshots {
   let recovered = FirmwareBackend(), journal = FirmwareJournal(); recovered.values = values; journal.data = data
   try recovered.controller(journal).restore()
   precondition(recovered.bytes == crashOriginal && journal.data == nil)
  }; scenarios += 1
  let cold = FirmwareBackend(), coldOriginal = cold.bytes, coldStore = FirmwareJournal()
  try cold.controller(coldStore).allowCharging()
  let beforeCold = cold.writes.count, coldController = cold.controller(coldStore)
  rejects { try coldController.setLimit(60) }; precondition(cold.writes.count == beforeCold)
  try coldController.restore(); precondition(cold.bytes == coldOriginal && coldStore.data == nil); scenarios += 1
  let reboot = FirmwareBackend(), rebootStore = FirmwareJournal()
  try reboot.controller(rebootStore).inhibitCharging(); let beforeReboot = reboot.bytes, rebootWrites = reboot.writes.count
  try reboot.controller(rebootStore, boot: "22222222-2222-2222-2222-222222222222").restore()
  precondition(reboot.bytes == beforeReboot && reboot.writes.count == rebootWrites && rebootStore.data == nil); scenarios += 1
  for data in [try record(kind: "activeCharge"), try record(version: 2), try record(key: "CHTE"), try record(duplicate: true),
               try record(key: "BCLM", original: 19, expected: 80), try record(original: 256), try record(previous: 9),
               Data("broken".utf8), Data(repeating: 32, count: 8193)] {
   let fake = FirmwareBackend(), journal = FirmwareJournal(); journal.data = data
   rejects { try fake.controller(journal).restore() }
   precondition(journal.data == data && journal.saves == 0 && fake.writes.isEmpty)
  }; scenarios += 1
  let deniedStore = FirmwareJournal(), deniedFake = FirmwareBackend()
  deniedStore.fail = { _ in true }
  rejects { try deniedFake.controller(deniedStore).inhibitCharging() }
  precondition(deniedFake.writes.isEmpty); scenarios += 1
  for failedKey in ["CH0B", "BCLM"] {
   let fake = FirmwareBackend(), original = fake.bytes, journal = FirmwareJournal(), controller = fake.controller(journal)
   var first = true
   fake.beforeWrite = { key, _ in if first && key == failedKey { first = false; throw HardwareError.unavailable("injected write failure") } }
   rejects { try controller.inhibitCharging() }
   precondition(fake.bytes == original && journal.data == nil)
  }; scenarios += 1
  let ignored = FirmwareBackend(), ignoredOriginal = ignored.bytes, ignoredStore = FirmwareJournal()
  ignored.ignoreWrite = "BCLM"
  rejects { try ignored.controller(ignoredStore).inhibitCharging() }
  precondition(ignored.bytes == ignoredOriginal && ignoredStore.data == nil); scenarios += 1
  let ambiguous = FirmwareBackend(), ambiguousOriginal = ambiguous.bytes, ambiguousStore = FirmwareJournal()
  var ambiguousFirst = true
  ambiguous.afterWrite = { _, _ in if ambiguousFirst { ambiguousFirst = false; throw HardwareError.unavailable("write completed but response lost") } }
  rejects { try ambiguous.controller(ambiguousStore).inhibitCharging() }
  precondition(ambiguous.bytes == ambiguousOriginal && ambiguousStore.data == nil); scenarios += 1
  let rollback = FirmwareBackend(), rollbackOriginal = rollback.bytes, rollbackStore = FirmwareJournal(), rollbackController = rollback.controller(rollbackStore)
  rollback.beforeWrite = { key, value in if (key == "BCLM" && value == 15) || (key == "CH0B" && value == 2) { throw HardwareError.unavailable("injected rollback failure") } }
  rejects { try rollbackController.inhibitCharging() }; precondition(rollbackStore.data != nil)
  let beforeRetry = rollback.writes.count
  rejects { try rollbackController.setLimit(70) }; precondition(rollback.writes.count == beforeRetry)
  rollback.beforeWrite = nil; try rollbackController.restore()
  precondition(rollback.bytes == rollbackOriginal && rollbackStore.data == nil); scenarios += 1
  let changedType = FirmwareBackend(), changedTypeStore = FirmwareJournal(), changedTypeController = changedType.controller(changedTypeStore)
  changedTypeStore.afterSave = { data in if data != nil { changedType.values["CH0B"] = SMCByteReading(dataType: "ui32", bytes: [2, 0, 0, 0]) } }
  rejects { try changedTypeController.inhibitCharging() }; precondition(changedType.writes.isEmpty && changedTypeStore.data != nil)
  changedTypeStore.afterSave = nil; changedType.values["CH0B"] = FirmwareBackend.value(2)
  try changedTypeController.restore(); precondition(changedTypeStore.data == nil); scenarios += 1
  let external = FirmwareBackend(), externalStore = FirmwareJournal(), externalController = external.controller(externalStore)
  try externalController.inhibitCharging()
  external.values["BCLM"] = FirmwareBackend.value(70)
  try externalController.restore()
  precondition(external.values["CH0B"]?.bytes == [2] && external.values["BCLM"]?.bytes == [70] && externalStore.data == nil); scenarios += 1
  let unknownExternal = FirmwareBackend(), unknownStore = FirmwareJournal(), unknownController = unknownExternal.controller(unknownStore)
  try unknownController.inhibitCharging()
  unknownExternal.values["CH0B"] = FirmwareBackend.value(9); unknownExternal.values["BCLM"] = FirmwareBackend.value(200)
  let unknownWrites = unknownExternal.writes.count
  try unknownController.restore(); precondition(unknownExternal.writes.count == unknownWrites && unknownStore.data == nil); scenarios += 1
  let exiting = FirmwareBackend(), exitStore = FirmwareJournal(), exitController = exiting.controller(exitStore)
  try exitController.inhibitCharging(); try exitController.finishExit(limit: 75)
  precondition(exiting.values["CH0B"]?.bytes == [0] && exiting.values["BCLM"]?.bytes == [75] && exitStore.data == nil)
  let exitWrites = exiting.writes.count
  try exitController.restore(); try exiting.controller(exitStore).restore()
  precondition(exiting.writes.count == exitWrites && exiting.values["BCLM"]?.bytes == [75]); scenarios += 1
  let sameExit = FirmwareBackend(charge: 0, limit: 80), sameExitStore = FirmwareJournal(), sameExitController = sameExit.controller(sameExitStore)
  try sameExitController.finishExit(limit: 80); try sameExitController.restore()
  precondition(sameExit.writes.isEmpty && sameExitStore.data == nil); scenarios += 1
  let failedExit = FirmwareBackend(), failedExitOriginal = failedExit.bytes, failedExitStore = FirmwareJournal(), failedExitController = failedExit.controller(failedExitStore)
  try failedExitController.inhibitCharging()
  failedExit.beforeWrite = { key, value in if key == "BCLM" && value == 75 { throw HardwareError.unavailable("exit write failed") } }
  rejects { try failedExitController.finishExit(limit: 75) }
  precondition(failedExit.bytes == failedExitOriginal && failedExitStore.data == nil); scenarios += 1
  let clearFailure = FirmwareBackend(), clearOriginal = clearFailure.bytes, clearStore = FirmwareJournal(), clearController = clearFailure.controller(clearStore)
  try clearController.inhibitCharging(); clearStore.fail = { $0 == nil }
  rejects { try clearController.finishExit(limit: 75) }; precondition(clearStore.data != nil)
  let clearWrites = clearFailure.writes.count
  rejects { try clearController.setLimit(60) }; precondition(clearFailure.writes.count == clearWrites)
  clearStore.fail = nil; try clearController.restore()
  precondition(clearFailure.bytes == clearOriginal && clearStore.data == nil); scenarios += 1
  try noOpKeyRace(); scenarios += 1
  try knownConflictPreflight(); scenarios += 1
  print("\(scenarios) numeric firmware transaction/status/recovery/exit scenarios passed; injected bytes and journal only, no hardware or helper requests")
 }
}
