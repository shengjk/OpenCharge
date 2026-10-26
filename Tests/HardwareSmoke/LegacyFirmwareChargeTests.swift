import Foundation

private final class Journal: ChargeRecoveryStore {
 var data: Data?
 var loads = 0, saves = 0
 var afterSave: (() -> Void)?
 var rejectClear = false
 func load() throws -> Data? { loads += 1; return data }
 func save(_ value: Data?) throws {
  if value == nil && rejectClear { throw HardwareError.unavailable("fixture clear failure") }
  saves += 1; data = value; afterSave?()
 }
}
private final class Backend {
 var limit = SMCByteReading(dataType:"ui8 ",bytes:[80])
 var input: SMCByteReading? = SMCByteReading(dataType:"ui8 ",bytes:[0])
 var reads: [String] = [], writes: [UInt8] = []
 var failAfterWrite = false
 let journal = Journal()
 func controller(_ profile: SMCFirmwareKeyProfile = .limitOnly, authorized: Bool = true, battery: Bool = true, eligible: Bool = true) -> SMCFirmwareChargeController {
  SMCFirmwareChargeController(eligibleHost:eligible,batteryPresent:battery,keyProfile:profile,read:{ key in
   self.reads.append(key)
   precondition(key == "BCLM" || key == "BSIn","limit-only control queried an unrelated key")
   return key == "BCLM" ? self.limit : self.input
  },write:{ key,value in
   precondition(key == "BCLM","limit-only control wrote an unrelated key")
   self.writes.append(value); self.limit = SMCByteReading(dataType:"ui8 ",bytes:[value])
   if self.failAfterWrite { self.failAfterWrite = false; throw HardwareError.unavailable("ambiguous write") }
  },authorized:{authorized},recoveryStore:journal,bootSession:LegacyFirmwareChargeTests.boot)
 }
}
@main struct LegacyFirmwareChargeTests {
 static let boot = "11111111-1111-1111-1111-111111111111"
 static var checks = 0
 static func check(_ value: Bool) { precondition(value); checks += 1 }
 static func rejects(_ action: () throws -> Void) { do { try action(); preconditionFailure("unexpected success") } catch { checks += 1 } }
 static func record(kind: String, key: String = "BCLM", recordedBoot: String = boot) throws -> Data {
  try JSONSerialization.data(withJSONObject:["kind":kind,"version":1,"bootSession":recordedBoot,"entries":[["key":key,"original":80,"expected":15,"previous":80]]])
 }
 static func main() throws {
  for model in ["MacBookPro11,4","MacBook10,1","MacBookAir7,2","MacBookPro12,1"] {
   let b = Backend()
   let observed = try SMCFirmwareProbe.inspect(model:model,architecture:"x86_64",internalBattery:true,read:{ key in
    b.reads.append(key); precondition(key == "BCLM"); return b.limit
   })
   check(observed.limit == 80 && observed.chargingAllowed == true && b.writes.isEmpty && b.reads == ["BCLM"])
   check(SMCFirmwareProbe.selectedProfile(model:model,architecture:"x86_64",internalBattery:true) == .limitOnly)
   for (arch,battery) in [("arm64",true),("unknown",true),("x86_64",false)] {
    rejects { _ = try SMCFirmwareProbe.inspect(model:model,architecture:arch,internalBattery:battery,read:{ _ in preconditionFailure("rejected host queried SMC") }) }
   }
  }
  for target in 20...100 {
   let b = Backend(), controller = b.controller()
   try controller.setLimit(target); check(b.limit.bytes == [UInt8(target)])
   if target != 80 {
    let data = try JSONSerialization.jsonObject(with:b.journal.data!) as! [String:Any]
    check(data["kind"] as? String == "bclmOnlyFirmwareV1")
    let entries = data["entries"] as! [[String:Any]]; check(entries.count == 1 && entries[0]["key"] as? String == "BCLM")
   }
   try controller.restore(); check(b.limit.bytes == [80] && b.journal.data == nil)
   check(b.reads.allSatisfy { $0 == "BCLM" })
  }
  let b = Backend(), controller = b.controller()
  try controller.inhibitCharging(); check(b.limit.bytes == [15]); check(try controller.inspect().chargingAllowed == false)
  for input: UInt8 in [1,2,3,254,255] {
   b.input = SMCByteReading(dataType:"ui8 ",bytes:[input])
   check(try controller.inspect().chargingAllowed == (input & 1 != 0))
  }
  b.input = nil; let saves = b.journal.saves
  check(try controller.inspect().chargingAllowed == nil); check(b.journal.saves == saves)
  try controller.allowCharging(); check(b.limit.bytes == [100]); try controller.restore(); check(b.limit.bytes == [80])
  for reading in [SMCByteReading(dataType:"flt ",bytes:[80]),SMCByteReading(dataType:"ui8 ",bytes:[80,0]),SMCByteReading(dataType:"ui8 ",bytes:[]),SMCByteReading(dataType:"ui8 ",bytes:[16]),SMCByteReading(dataType:"ui8 ",bytes:[101])] {
   let bad = Backend(); bad.limit = reading
   rejects { _ = try bad.controller().inspect() }; check(bad.journal.loads == 0 && bad.journal.saves == 0 && bad.writes.isEmpty)
  }
  for flags in [(false,true,true),(true,false,true),(true,true,false)] {
   let denied = Backend(); rejects { try denied.controller(authorized:flags.0,battery:flags.1,eligible:flags.2).inhibitCharging() }
   check(denied.reads.isEmpty && denied.writes.isEmpty && denied.journal.saves == 0)
  }
  for (selected,kind,key): (SMCFirmwareKeyProfile,String,String) in [(.limitOnly,"numericFirmwareV1","BCLM"),(.chargeAndLimit,"bclmOnlyFirmwareV1","BCLM"),(.limitOnly,"bclmOnlyFirmwareV1","CH0B")] {
   let bad = Backend(); bad.journal.data = try record(kind:kind,key:key); let before = bad.journal.data
   rejects { try bad.controller(selected).restore() }
   check(bad.reads.isEmpty && bad.writes.isEmpty && bad.journal.data == before)
  }
  let previousBoot = Backend(); previousBoot.journal.data = try record(kind:"bclmOnlyFirmwareV1",recordedBoot:"22222222-2222-2222-2222-222222222222")
  try previousBoot.controller().restore(); check(previousBoot.journal.data == nil && previousBoot.reads.isEmpty && previousBoot.writes.isEmpty)
  let raced = Backend(), racing = raced.controller()
  raced.journal.afterSave = { if raced.journal.data != nil { raced.limit = SMCByteReading(dataType:"ui8 ",bytes:[70]) } }
  rejects { try racing.inhibitCharging() }; check(raced.limit.bytes == [70] && raced.writes.isEmpty)
  let ambiguous = Backend(), attempt = ambiguous.controller(); ambiguous.failAfterWrite = true
  rejects { try attempt.inhibitCharging() }; check(ambiguous.limit.bytes == [80] && ambiguous.journal.data == nil)
  let interrupted = Backend(), owner = interrupted.controller(); try owner.inhibitCharging(); interrupted.journal.rejectClear = true
  rejects { try owner.restore() }; check(interrupted.journal.data != nil)
  rejects { try owner.allowCharging() }; interrupted.journal.rejectClear = false; try owner.restore(); check(interrupted.journal.data == nil)
  let exit = Backend(), exiting = exit.controller(); try exiting.inhibitCharging(); try exiting.finishExit(limit:75)
  check(exit.limit.bytes == [75] && exit.journal.data == nil); let writes = exit.writes.count
  try exit.controller().restore(); check(exit.limit.bytes == [75] && exit.writes.count == writes)
  print("PASS limit-only firmware: \(checks) typed model/state/journal/ownership/rollback/exit checks; injected bytes only")
 }
}
