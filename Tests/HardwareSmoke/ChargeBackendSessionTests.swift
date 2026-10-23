import Foundation
import Darwin

private final class Registers {
 var values: [String:[UInt8]] = ["CH0B":[0],"CH0C":[0],"CH0I":[0],"BCLM":[80],"BSIn":[0]]
 var writes: [(String,[UInt8])] = []
 var failure: ((String,[UInt8]) -> Bool)?
 var badType = false
 var reads = 0
 func read(_ key: String) -> [UInt8]? { reads += 1; return values[key] }
 func typed(_ key: String) -> SMCByteReading? { reads += 1; return values[key].map { SMCByteReading(dataType:badType ? "flt " : "ui8 ",bytes:$0) } }
 func write(_ key: String, _ bytes: [UInt8]) throws {
  if failure?(key,bytes) == true { throw HardwareError.unavailable("injected write failure") }
  writes.append((key,bytes)); values[key] = bytes
 }
}
private final class SessionFixture {
 let directory: URL
 let store: ChargeRecoveryFileStore
 let registers: Registers
 let boot: String
 let eligible: Bool
 init(registers: Registers = Registers(), eligible: Bool = true) throws {
  directory = FileManager.default.temporaryDirectory.appendingPathComponent("opencharge-backend-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  store = try ChargeRecoveryFileStore(directory:directory.path,owner:geteuid())
  self.registers = registers; boot = UUID().uuidString; self.eligible = eligible
 }
 deinit { try? FileManager.default.removeItem(at:directory) }
 func ordinary() -> SMCChargeController {
  SMCChargeController(batteryPresent:true,read:registers.read,write:registers.write,authorized:{true},recoveryStore:store,bootSession:boot)
 }
 func numeric() -> SMCFirmwareChargeController {
  SMCFirmwareChargeController(eligibleHost:eligible,batteryPresent:true,read:registers.typed,write:{ try self.registers.write($0,[$1]) },authorized:{true},recoveryStore:store.firmwareStore(),bootSession:boot)
 }
 func session() -> ChargeBackendSession {
  let old = ordinary(), numeric = numeric()
  return ChargeBackendSession(ordinaryPending:{ try self.store.load() != nil },firmwarePending:{ try self.store.firmwareStore().load() != nil },ordinary:old.apply,firmwareEligible:eligible,firmwareInspect:{ _ = try numeric.inspect() },firmwareLimit:numeric.setLimit,firmwareInhibit:numeric.inhibitCharging,firmwareExit:{ try numeric.finishExit(limit:$0) },firmwareRestore:numeric.restore)
 }
}
@main struct ChargeBackendSessionTests {
 static var checks = 0
 static func check(_ value: Bool) { precondition(value); checks += 1 }
 static func rejects(_ action: () throws -> Void) { do { try action(); preconditionFailure("unexpected success") } catch { checks += 1 } }
 static func main() throws {
  let f = try SessionFixture(), r = f.registers, s = f.session(), initial = r.values
  try s.restore(); check(r.writes.isEmpty && s.active == nil)
  try s.apply(.forceDischarge); check(r.values["CH0B"] == [2] && r.values["CH0C"] == [2] && r.values["CH0I"] == [1])
  let ordinaryRecord = try f.store.load(), numericRecord = try f.store.firmwareStore().load()
  check(ordinaryRecord != nil && numericRecord == nil)
  let offset = r.writes.count
  try s.setFirmwareLimit(65)
  check(r.values["BCLM"] == [65] && r.values["CH0B"] == [0] && r.values["CH0C"] == [0] && r.values["CH0I"] == [0])
  check(r.writes.dropFirst(offset).last?.0 == "BCLM")
  let cleared = try f.store.load(), owned = try f.store.firmwareStore().load(); check(cleared == nil && owned != nil && s.active == .firmware)
  try s.apply(.inhibitCharge); check(r.values["BCLM"] == [80] && r.values["CH0B"] == [2] && r.values["CH0C"] == [2] && s.active == .ordinary)
  let oldAgain = try f.store.load(), numericClear = try f.store.firmwareStore().load(); check(oldAgain != nil && numericClear == nil)
  try s.restore(); check(r.values == initial && s.active == nil)
  // A rejected unsupported/invalid numeric request preserves ordinary ownership.
  let unsupported = try SessionFixture(eligible:false), us = unsupported.session()
  try us.apply(.inhibitCharge); let uw = unsupported.registers.writes.count, ur = unsupported.registers.reads
  rejects { try us.setFirmwareLimit(65) }; check(unsupported.registers.writes.count == uw && unsupported.registers.reads == ur && us.active == .ordinary && !us.recoveryRequired)
  for value in [Int.min,0,15,19,101,Int.max] { rejects { try us.setFirmwareLimit(value) }; rejects { try us.finishFirmwareExit(value) } }
  check(unsupported.registers.writes.count == uw); try us.restore()
  try s.apply(.inhibitCharge); r.badType = true; let beforeType = r.writes.count
  rejects { try s.setFirmwareLimit(65) }; check(r.writes.count == beforeType && s.active == .ordinary && !s.recoveryRequired)
  r.badType = false; try s.restore()
  // Failed old-backend cleanup cannot be followed by any new-backend write.
  try s.apply(.inhibitCharge); r.failure = { key,bytes in key == "CH0B" && bytes == [0] }
  rejects { try s.setFirmwareLimit(65) }; check(s.recoveryRequired && r.values["BCLM"] == [80])
  let failedWrites = r.writes.count; rejects { try s.apply(.allowCharge) }; rejects { try s.inhibitFirmware() }; check(r.writes.count == failedWrites)
  r.failure = nil; try s.restore(); check(!s.recoveryRequired && r.values == initial)
  // Failed numeric mutation remains blocked until explicit recovery, even if its
  // local rollback succeeded; this is the helper's conservative session boundary.
  r.failure = { key,_ in key == "BCLM" }
  rejects { try s.setFirmwareLimit(65) }; check(s.recoveryRequired)
  r.failure = nil; try s.restore(); try s.setFirmwareLimit(65); try s.finishFirmwareExit(75)
  check(s.active == nil && !s.recoveryRequired && r.values["BCLM"] == [75])
  let committed = r.writes.count; try s.restore(); check(r.writes.count == committed && r.values["BCLM"] == [75])
  // Cold restart recovers exactly the journal that owns hardware.
  for numeric in [false,true] {
   let cold = try SessionFixture(), live = cold.session()
   if numeric { try live.setFirmwareLimit(60) } else { try live.apply(.forceDischarge) }
   let recovered = cold.session(); try recovered.restore()
   check(cold.registers.values["CH0B"] == [0] && cold.registers.values["BCLM"] == [80] && cold.registers.values["CH0I"] == [0])
   let a = try cold.store.load(), b = try cold.store.firmwareStore().load(); check(a == nil && b == nil)
  }
  let conflict = try SessionFixture()
  try conflict.ordinary().apply(.inhibitCharge); try conflict.numeric().setLimit(65)
  let both = conflict.session(), conflictWrites = conflict.registers.writes.count
  rejects { try both.restore() }; check(both.recoveryRequired && conflict.registers.writes.count == conflictWrites)
  rejects { try both.apply(.allowCharge) }; rejects { try both.setFirmwareLimit(70) }; check(conflict.registers.writes.count == conflictWrites)
  let oa = try conflict.store.load(), ob = try conflict.store.firmwareStore().load(); check(oa != nil && ob != nil)
  // A malformed one-sided record is preserved, with no attempted hardware write.
  let malformed = try SessionFixture(); try malformed.store.firmwareStore().save(Data("{}".utf8)); let ms = malformed.session()
  rejects { try ms.restore() }; check(ms.recoveryRequired && malformed.registers.writes.isEmpty)
  let retained = try malformed.store.firmwareStore().load(); check(retained == Data("{}".utf8))
  // Fixed view isolation: firmware save/remove cannot overwrite another journal.
  let views = try SessionFixture(), payload = Data("other-owned-record".utf8)
  try views.store.save(payload); try views.store.magSafeStore().save(payload); try views.store.sleepStore().save(payload)
  try views.store.firmwareStore().save(Data("numeric-owned-record".utf8)); try views.store.firmwareStore().save(nil)
  let a = try views.store.load(), b = try views.store.magSafeStore().load(), c = try views.store.sleepStore().load()
  check(a == payload && b == payload && c == payload)
  let file = views.directory.appendingPathComponent("firmware-recovery.json")
  try FileManager.default.createSymbolicLink(atPath:file.path,withDestinationPath:"missing-target")
  rejects { _ = try views.store.firmwareStore().load() }; rejects { try views.store.firmwareStore().save(nil) }
  check((try? FileManager.default.destinationOfSymbolicLink(atPath:file.path)) == "missing-target")
  print("PASS exclusive charge backends / fixed firmware journal: \(checks) checks; current-user files and injected registers only")
 }
}
