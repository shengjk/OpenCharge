import Foundation

/// Independent fixtures for the documented 80-byte AppleSMC C ABI; no service is opened.
private final class Frames {
 var sizes: [String: UInt32] = ["CH0B": 1, "BCLM": 1, "BSIn": 1, "TB0T": 2]
 var types: [String: [UInt8]] = ["CH0B": [0x75,0x69,0x38,0x20], "BCLM": [0x75,0x69,0x38,0x20], "BSIn": [0x75,0x69,0x38,0x20], "TB0T": [0x73,0x70,0x37,0x38]]
 var values: [String: [UInt8]] = ["CH0B": [2], "BCLM": [80], "BSIn": [0], "TB0T": [0x21,0x80]]
 var calls: [(String, UInt8, Int, [UInt8])] = []
 var fault: ((String, UInt8) throws -> [UInt8]?)?
 lazy var io = SMCKeyIO { [unowned self] in try self.call($0,$1,$2,$3) }
 func call(_ key: String, _ command: UInt8, _ count: Int, _ bytes: [UInt8]) throws -> [UInt8] {
  calls.append((key,command,count,bytes))
  if let output = try fault?(key,command) { return output }
  var out = [UInt8](repeating:0,count:80)
  guard let size = sizes[key] else { out[40] = 132; return out }
  switch command {
  case 9:
   out[28] = UInt8(truncatingIfNeeded:size); out[29] = UInt8(truncatingIfNeeded:size >> 8)
   out[30] = UInt8(truncatingIfNeeded:size >> 16); out[31] = UInt8(truncatingIfNeeded:size >> 24)
   for (i,v) in (types[key] ?? [0,0,0,0]).reversed().enumerated() { out[32+i] = v }
  case 5:
   precondition(count == Int(size) && bytes.isEmpty)
   for (i,v) in (values[key] ?? []).enumerated() { out[48+i] = v }
  case 6:
   precondition(count == Int(size) && bytes.count == count); values[key] = bytes
  default: preconditionFailure("unexpected command")
  }
  return out
 }
 var writes: [(String, UInt8, Int, [UInt8])] { calls.filter { $0.1 == 6 } }
}
private final class MemoryJournal: ChargeRecoveryStore {
 var data: Data?
 var saved: (() -> Void)?
 func load() throws -> Data? { data }
 func save(_ data: Data?) throws { self.data = data; saved?() }
}
@main struct SMCKeyIOTests {
 static var count = 0
 static func check(_ condition: Bool) { precondition(condition); count += 1 }
 static func rejects(_ action: () throws -> Void) { do { try action(); preconditionFailure("unexpected success") } catch { count += 1 } }
 static func main() throws {
  let temperature = Frames(), reading = try temperature.io.read("TB0T")
  check(reading.dataType == "sp78" && reading.bytes == [0x21,0x80])
  check(TelemetryMath.smcTemperatureCelsius(dataType:reading.dataType,bytes:reading.bytes) == 33.5)
  check(temperature.calls.map { $0.1 } == [9,5] && temperature.calls[1].2 == 2)
  let text = Frames(), byte = try text.io.read("BCLM"); check(byte.dataType == "ui8 " && byte.bytes == [80])
  text.types["BCLM"] = [255,254,253,252]
  let unknown = try text.io.read("BCLM"); check(unknown.dataType == "unknown")
  rejects { try text.io.writeFirmwareByte("BCLM",value:75) }; check(text.writes.isEmpty)
  for size: UInt32 in [0,33,0x01000000,UInt32.max] {
   let f = Frames(); f.sizes["BCLM"] = size
   rejects { _ = try f.io.read("BCLM") }; check(f.calls.count == 1)
   rejects { try f.io.writeFirmwareByte("BCLM",value:75) }; check(f.writes.isEmpty)
  }
  for command: UInt8 in [9,5] {
   for length in [0,40,79,81] {
    let f = Frames(); f.fault = { _, c in c == command ? [UInt8](repeating:0,count:length) : nil }
    rejects { _ = try f.io.read("BCLM") }; check(f.writes.isEmpty)
   }
   let absent = Frames(); absent.fault = { _, c in
    guard c == command else { return nil }; var out = [UInt8](repeating:0,count:80); out[40] = 132; return out
   }
   let missing = try absent.io.optionalRead("BCLM"); check(missing == nil && absent.writes.isEmpty)
   let denied = Frames(); denied.fault = { _, c in if c == command { throw HardwareError.driver(-1,132) }; return nil }
   rejects { _ = try denied.io.optionalRead("BCLM") }
   for result: UInt8 in [1,133,255] {
    let f = Frames(); f.fault = { _, c in guard c == command else { return nil }; var out = [UInt8](repeating:0,count:80); out[40] = result; return out }
    rejects { _ = try f.io.optionalRead("BCLM") }
   }
  }
  for key in ["", "ABC", "ABCDE", "éAB", "A\u{0}BC", "AB\nD"] {
   let f = Frames(); rejects { _ = try f.io.read(key) }; check(f.calls.isEmpty)
  }
  for (key,value): (String,UInt8) in [("CH0B",0),("CH0B",2),("BCLM",15),("BCLM",20),("BCLM",100)] {
   let f = Frames(); try f.io.writeFirmwareByte(key,value:value)
   check(f.calls.map { $0.1 } == [9,6] && f.writes.count == 1 && f.values[key] == [value])
  }
  for (key,value): (String,UInt8) in [("BSIn",0),("CH0C",0),("ACLC",0),("CH0B",1),("CH0B",255),("BCLM",0),("BCLM",19),("BCLM",101)] {
   let f = Frames(); rejects { try f.io.writeFirmwareByte(key,value:value) }; check(f.calls.isEmpty)
  }
  for (type,size): ([UInt8],UInt32) in [([0x75,0x69,0x38,0],1),([0x75,0x69,0x31,0x36],1),([0x75,0x69,0x38,0x20],2)] {
   let f = Frames(); f.types["BCLM"] = type; f.sizes["BCLM"] = size
   rejects { try f.io.writeFirmwareByte("BCLM",value:75) }; check(f.calls.map { $0.1 } == [9])
  }
  let failedWrite = Frames(); failedWrite.fault = { _, c in
   guard c == 6 else { return nil }; var out = [UInt8](repeating:0,count:80); out[40] = 133; return out
  }
  rejects { try failedWrite.io.writeFirmwareByte("BCLM",value:75) }; check(failedWrite.values["BCLM"] == [80])
  let legacy = Frames(); try legacy.io.write("TB0T",bytes:[1,2]); check(legacy.values["TB0T"] == [1,2])
  for bytes: [UInt8] in [[],[0],[UInt8](repeating:0,count:33)] {
   let f = Frames(); rejects { try f.io.write("TB0T",bytes:bytes) }; check(f.writes.isEmpty)
  }
  let numericModels = ["MacBookAir8,1","MacBookAir8,2","MacBookAir9,1",
   "MacBookPro15,1","MacBookPro15,2","MacBookPro15,3","MacBookPro15,4",
   "MacBookPro16,1","MacBookPro16,2","MacBookPro16,3","MacBookPro16,4",
   "MacBookPro13,1","MacBookPro13,2","MacBookPro13,3","MacBookPro14,1","MacBookPro14,2","MacBookPro14,3"]
  for model in numericModels {
   let f = Frames()
   let state = try SMCFirmwareProbe.inspect(model:model,architecture:"x86_64",internalBattery:true,read:f.io.optionalRead)
   check(state.limit == 80 && state.chargingAllowed == false && f.writes.isEmpty)
   check(f.calls.map { $0.0 } == ["CH0B","CH0B","BCLM","BCLM"])
   // A model match must never bypass architecture/battery qualification or
   // start a read on a rejected host.
   for (arch,battery) in [("arm64",true),("unknown",true),("x86_64",false)] {
    let rejected = Frames()
    rejects { _ = try SMCFirmwareProbe.inspect(model:model,architecture:arch,internalBattery:battery,read:rejected.io.optionalRead) }
    check(rejected.calls.isEmpty)
   }
   for key in ["CH0B","BCLM"] {
    let invalid = Frames(); invalid.types[key] = [0x66,0x6c,0x74,0x20]
    rejects { _ = try SMCFirmwareProbe.inspect(model:model,architecture:"x86_64",internalBattery:true,read:invalid.io.optionalRead) }
    check(invalid.writes.isEmpty)
   }
  }
  for (model,arch,battery) in [("MacBookAir8,1","arm64",true),("MacBookAir8,1","unknown",true),("MacBookAir8,1","x86_64",false),("MacBookAir10,1","x86_64",true),("MacBookPro12,2","x86_64",true),("MacBookPro13,4","x86_64",true),("MacBookPro14,4","x86_64",true),("MacBookPro15,5","x86_64",true),("MacBookPro16,5","x86_64",true),("MacBookPro17,1","x86_64",true),("Mac16,1","x86_64",true),("MacBookPro15,1 ","x86_64",true),("unknown","x86_64",true)] {
   let f = Frames(); rejects { _ = try SMCFirmwareProbe.inspect(model:model,architecture:arch,internalBattery:battery,read:f.io.optionalRead) }; check(f.calls.isEmpty)
  }
  for bit: UInt8 in [0,1,2,3,254,255] {
   let f = Frames(); f.values["CH0B"] = [0]; f.values["BCLM"] = [15]; f.values["BSIn"] = [bit]
   let s = try SMCFirmwareProbe.inspect(model:"MacBookAir9,1",architecture:"x86_64",internalBattery:true,read:f.io.optionalRead)
   check(s.chargingAllowed == (bit & 1 != 0) && f.writes.isEmpty)
  }
  let input = Frames(); input.values["CH0B"] = [0]; input.values["BCLM"] = [15]; input.sizes.removeValue(forKey:"BSIn")
  let unknownInput = try SMCFirmwareProbe.inspect(model:"MacBookAir9,1",architecture:"x86_64",internalBattery:true,read:input.io.optionalRead)
  check(unknownInput.chargingAllowed == nil && input.writes.isEmpty)
  for key in ["CH0B","BCLM"] {
   let f = Frames(); f.types[key] = [0x66,0x6c,0x74,0x20]
   rejects { _ = try SMCFirmwareProbe.inspect(model:"MacBookAir8,1",architecture:"x86_64",internalBattery:true,read:f.io.optionalRead) }; check(f.writes.isEmpty)
  }
  let f = Frames(), store = MemoryJournal(), boot = UUID().uuidString
  let client = SMCFirmwareChargeController(eligibleHost:true,batteryPresent:true,read:f.io.optionalRead,write:{ try f.io.writeFirmwareByte($0,value:$1) },authorized:{true},recoveryStore:store,bootSession:boot)
  try client.setLimit(65); check(f.values["CH0B"] == [0] && f.values["BCLM"] == [65] && store.data != nil)
  try client.restore(); check(f.values["CH0B"] == [2] && f.values["BCLM"] == [80] && store.data == nil)
  store.saved = { if store.data != nil { f.types["CH0B"] = [0x66,0x6c,0x74,0x20] } }
  let before = f.writes.count
  rejects { try client.setLimit(65) }; check(f.writes.count == before && store.data != nil)
  store.saved = nil; f.types["CH0B"] = [0x75,0x69,0x38,0x20]
  let recovered = SMCFirmwareChargeController(eligibleHost:true,batteryPresent:true,read:f.io.optionalRead,write:{ try f.io.writeFirmwareByte($0,value:$1) },authorized:{true},recoveryStore:store,bootSession:boot)
  try recovered.restore(); check(store.data == nil && f.values["CH0B"] == [2] && f.values["BCLM"] == [80])
  // A metadata change after the controller's last pre-write read is still refused
  // by the transport immediately before command 6, retaining recovery for retry.
  let raced = Frames(), raceStore = MemoryJournal()
  raced.fault = { key, command in
   if key == "CH0B" && command == 9 && raced.calls.filter({ $0.0 == "CH0B" && $0.1 == 9 }).count == 4 {
    raced.types["CH0B"] = [0x66,0x6c,0x74,0x20]
   }
   return nil
  }
  let racingClient = SMCFirmwareChargeController(eligibleHost:true,batteryPresent:true,read:raced.io.optionalRead,write:{ try raced.io.writeFirmwareByte($0,value:$1) },authorized:{true},recoveryStore:raceStore,bootSession:boot)
  rejects { try racingClient.setLimit(65) }
  check(raced.writes.isEmpty && raceStore.data != nil)
  raced.fault = nil; raced.types["CH0B"] = [0x75,0x69,0x38,0x20]
  try racingClient.restore(); check(raceStore.data == nil && raced.values["CH0B"] == [2])
  print("PASS SMC wire metadata / numeric probe: \(count) checks; raw frame fixtures only, no service or hardware access")
 }
}
