import Foundation

private final class Journal: ChargeRecoveryStore {
 var data: Data?
 func load() throws -> Data? { data }
 func save(_ data: Data?) throws { self.data = data }
}
private final class Bytes {
 var values: [String:[UInt8]]
 var reads: [String] = []
 var writes: [(String,[UInt8])] = []
 var failRead: String?
 var failWrite: ((String,[UInt8]) -> Bool)?
 init(_ values: [String:[UInt8]]) { self.values = values }
 func controller(platform: SMCChargePlatform = .appleSilicon, battery: Bool = true, permission: Bool = true, journal: Journal? = nil, boot: String = "11111111-2222-3333-4444-555555555555") -> SMCChargeController {
  SMCChargeController(batteryPresent:battery,platform:platform,read:{ key in
   self.reads.append(key)
   if self.failRead == key { throw HardwareError.unavailable("injected read error") }
   return self.values[key]
  },write:{ key,value in
   if self.failWrite?(key,value) == true { throw HardwareError.unavailable("injected write error") }
   self.writes.append((key,value)); self.values[key]=value
  },authorized:{permission},recoveryStore:journal,bootSession:boot)
 }
}
@main struct AppleSiliconChargeTests {
 static var checks = 0
 static func check(_ value: Bool) { precondition(value); checks += 1 }
 static func rejects(_ operation: () throws -> Void) { do { try operation(); preconditionFailure("unexpected success") } catch { checks += 1 } }
 static func main() throws {
  let models = ["MacBookAir10,1","MacBookPro17,1","Mac14,2","Mac14,15","MacBookPro18,1","MacBookPro18,2","MacBookPro18,3","MacBookPro18,4","Mac14,5","Mac14,6","Mac14,7","Mac14,9","Mac14,10","Mac15,3","Mac15,6","Mac15,7","Mac15,8","Mac15,9","Mac15,10","Mac15,11","Mac15,12","Mac15,13","Mac16,1","Mac16,3","Mac16,5","Mac16,6","Mac16,7","Mac16,8","Mac16,12"]
  for model in models {
   for arch in ["arm64","x86_64"] { check(SMCChargePlatform.selected(model:model,architecture:arch) == .appleSilicon) }
   check(SMCChargePlatform.selected(model:model,architecture:"unknown") == .generic)
  }
  for model in ["MacBookAir9,1","MacBookPro16,1","MacBookPro14,3","unknown","MacBookPro17,1 "] {
   check(SMCChargePlatform.selected(model:model,architecture:"arm64") == .generic)
  }
  let legacy = ["CH0B":[UInt8](arrayLiteral:0),"CH0C":[UInt8](arrayLiteral:0),"CH0I":[UInt8](arrayLiteral:0)]
  for state: UInt8 in [0,1,2] {
   var initial=legacy; initial["CH0C"]=[state]
   let f=Bytes(initial), c=f.controller()
   check(c.capabilities().contains("chargeControl:CH0C") && f.writes.isEmpty)
   try c.apply(.inhibitCharge)
   check(f.values["CH0B"] == [0] && f.values["CH0C"] == [2])
   try c.apply(.forceDischarge)
   check(f.values["CH0C"] == [1] && f.values["CH0I"] == [1] && f.values["CH0B"] == [0])
   let count=f.writes.count; try c.apply(.forceDischarge); check(f.writes.count == count)
   try c.apply(.inhibitCharge); check(f.values["CH0C"] == [2] && f.values["CH0I"] == [0])
   try c.apply(.restore); check(f.values == initial)
  }
  var coexist=legacy; coexist["CHTE"]=[9,0,0,0]; coexist["CHIE"]=[99]
  let co=Bytes(coexist), cc=co.controller(); try cc.apply(.inhibitCharge)
  check(co.values["CH0C"] == [2] && co.values["CHTE"] == [9,0,0,0] && !co.reads.contains("CHTE") && !co.reads.contains("CHIE"))
  let only=Bytes(["CH0C":[0],"CH0I":[0]]), oc=only.controller()
  try oc.apply(.inhibitCharge); try oc.apply(.forceDischarge); check(only.values == ["CH0C":[1],"CH0I":[1]])
  try oc.apply(.allowCharge); check(only.values == ["CH0C":[0],"CH0I":[0]])
  let reset=Bytes(["CH0B":[2],"CH0C":[2],"CH0I":[1]]), rc=reset.controller()
  try rc.apply(.allowCharge); check(reset.writes.map(\.0) == ["CH0B","CH0I","CH0C"])
  check(reset.values == legacy); try rc.apply(.restore); check(reset.values == ["CH0B":[2],"CH0C":[2],"CH0I":[1]])
  let unused=Bytes(["CH0B":[99],"CH0C":[0],"CH0I":[0]]), uc=unused.controller()
  try uc.apply(.inhibitCharge); check(!unused.reads.contains("CH0B") && unused.values["CH0B"] == [99])
  try uc.apply(.restore); let before=unused.writes.count
  rejects { try uc.apply(.allowCharge) }; check(unused.writes.count == before)
  for invalid: [UInt8] in [[],[3],[0,0]] {
   let f=Bytes(["CH0C":invalid,"CHTE":[0,0,0,0],"CH0I":[0]])
   rejects { try f.controller().apply(.inhibitCharge) }; check(f.writes.isEmpty && !f.reads.contains("CHTE"))
  }
  let failed=Bytes(["CHTE":[0,0,0,0],"CHIE":[0]]); failed.failRead="CH0C"
  rejects { try failed.controller().apply(.inhibitCharge) }; check(failed.writes.isEmpty && !failed.reads.contains("CHTE"))
  for (battery,permission) in [(false,true),(true,false)] {
   let f=Bytes(legacy); rejects { try f.controller(battery:battery,permission:permission).apply(.inhibitCharge) }; check(f.reads.isEmpty && f.writes.isEmpty)
  }
  let modern=Bytes(["CHTE":[0,0,0,0],"CHIE":[0],"CH0I":[99]]), mc=modern.controller()
  check(mc.capabilities().contains("chargeControl:CHTE")); try mc.apply(.forceDischarge)
  check(modern.values["CHTE"] == [1,0,0,0] && modern.values["CHIE"] == [8] && !modern.reads.contains("CH0I"))
  try mc.apply(.restore); check(modern.values["CHTE"] == [0,0,0,0] && modern.values["CHIE"] == [0])
  for initial in [["CH0C":[UInt8](arrayLiteral:0),"CH0I":[8],"CHIE":[0]],["CHTE":[UInt8](arrayLiteral:0,0,0,0),"CHIE":[1],"CH0I":[0]]] {
   let f=Bytes(initial); rejects { try f.controller().apply(.forceDischarge) }; check(f.writes.isEmpty)
  }
  for state: UInt8 in [0,1,2] {
   let f=Bytes(["CH0B":[2],"CH0C":[state],"CH0I":[1]]), c=f.controller()
   try c.apply(.retainInhibit)
   check(f.values == ["CH0B":[2],"CH0C":[1],"CH0I":[0]])
   try c.apply(.restore); check(f.values == ["CH0B":[2],"CH0C":[state],"CH0I":[1]])
  }
  for platform in [SMCChargePlatform.generic, .appleSilicon] {
   let f=Bytes(["CHTE":[0,0,0,0],"CHIE":[8]]), c=f.controller(platform:platform)
   try c.apply(.retainInhibit); check(f.values == ["CHTE":[1,0,0,0],"CHIE":[0]])
   try c.apply(.restore); check(f.values == ["CHTE":[0,0,0,0],"CHIE":[8]])
  }
  let gi=Bytes(legacy), gc=gi.controller(platform:.generic)
  try gc.apply(.retainInhibit); check(gi.values["CH0B"] == [2] && gi.values["CH0C"] == [2])
  try gc.apply(.restore); check(gi.values == legacy)
  let noInput=Bytes(["CH0C":[0]]), ni=noInput.controller()
  rejects { try ni.apply(.forceDischarge) }; check(noInput.writes.isEmpty)
  try ni.apply(.inhibitCharge); check(noInput.values["CH0C"] == [2])
  // Migrate an interrupted generic journal without losing ownership of CH0B.
  let old=Bytes(legacy), oldStore=Journal(); try old.controller(platform:.generic,journal:oldStore).apply(.inhibitCharge)
  check(old.values["CH0B"] == [2] && oldStore.data != nil)
  try old.controller(journal:oldStore).apply(.restore); check(old.values == legacy && oldStore.data == nil)
  let crash=Bytes(legacy), store=Journal(); try crash.controller(journal:store).apply(.forceDischarge)
  check(crash.values["CH0C"] == [1] && store.data != nil)
  let saved=store.data
  rejects { try crash.controller(platform:.generic,journal:store).apply(.restore) }
  check(store.data == saved && crash.values["CH0C"] == [1])
  let restarted=crash.controller(journal:store)
  rejects { try restarted.apply(.allowCharge) }; try restarted.apply(.restore)
  check(crash.values == legacy && store.data == nil)
  let partial=Bytes(["CH0B":[2],"CH0C":[2],"CH0I":[1]]), ps=Journal()
  var fail=true; partial.failWrite={ key,value in if key == "CH0I", value == [0], fail { fail=false; return true }; return false }
  rejects { try partial.controller(journal:ps).apply(.allowCharge) }
  check(partial.values == ["CH0B":[2],"CH0C":[2],"CH0I":[1]] && ps.data == nil)
  let forceFailure=Bytes(legacy), fs=Journal(); var inputFailure=true
  forceFailure.failWrite={ key,value in if key == "CH0I", value == [1], inputFailure { inputFailure=false; return true }; return false }
  rejects { try forceFailure.controller(journal:fs).apply(.forceDischarge) }
  check(forceFailure.values == legacy && fs.data == nil)
  let retry=Bytes(legacy), retryStore=Journal(); var cleanupFails=true
  retry.failWrite={ key,value in cleanupFails && ((key == "CH0I" && value == [1]) || (key == "CH0C" && value == [0])) }
  let retryClient=retry.controller(journal:retryStore)
  rejects { try retryClient.apply(.forceDischarge) }
  check(retry.values["CH0C"] == [1] && retryStore.data != nil)
  cleanupFails=false; try retryClient.apply(.restore)
  check(retry.values == legacy && retryStore.data == nil)
  print("PASS Apple silicon charge profiles: \(checks) checks; fixed fake bytes/journals only, no hardware or OS actions")
 }
}
