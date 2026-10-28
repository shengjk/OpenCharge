import Foundation
import Darwin

private enum Failure: Error { case injected }
private final class Fixture {
 let directory: URL
 let store: ChargeRecoveryFileStore
 let boot = UUID().uuidString
 var values: [String:[UInt8]] = ["CH0B":[0],"CH0C":[0],"CH0I":[0],"BCLM":[80],"BSIn":[0]]
 var events: [String] = []
 var token: UInt32?
 var next: UInt32 = 31
 var failCreate = false, failInspect = false, failRelease = false, failWrite = false
 var failPreflight = false, failHelperPreflight = false
 var eligible = true
 init() throws {
  directory = FileManager.default.temporaryDirectory.appendingPathComponent("opencharge-inflow-session-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  store = try ChargeRecoveryFileStore(directory:directory.path,owner:geteuid())
 }
 deinit { try? FileManager.default.removeItem(at:directory) }
 func write(_ key: String, _ bytes: [UInt8]) throws {
  events.append("write:\(key):\(bytes[0])")
  if failWrite { throw Failure.injected }; values[key] = bytes
 }
 lazy var numeric = SMCFirmwareChargeController(eligibleHost:eligible,batteryPresent:true,keyProfile:FirmwareDischargeSessionTests.keyProfile,
  read:{ self.values[$0].map { SMCByteReading(dataType:"ui8 ",bytes:$0) } },write:{ try self.write($0,[$1]) },
  authorized:{true},recoveryStore:store.firmwareStore(),bootSession:boot)
 lazy var ordinary = SMCChargeController(batteryPresent:true,read:{self.values[$0]},write:write,
  authorized:{true},recoveryStore:store,bootSession:boot)
 lazy var inflow = FirmwareInflowAssertion(authorize:{self.events.append("authorize")},create:{
  self.events.append("create")
  precondition(self.values["CH0B"] == [0] && self.values["BCLM"] == [15])
  let recorded = try self.store.firmwareStore().load(); precondition(recorded != nil)
  if self.failCreate { throw Failure.injected }
  precondition(self.token == nil); self.token = self.next; self.next += 1; return self.token!
 },inspect:{ id in self.events.append("inspect:\(id)"); return !self.failInspect && self.token == id },release:{ id in
  self.events.append("release:\(id)"); precondition(self.token == id)
  if self.failRelease { throw Failure.injected }; self.token = nil
 })
 lazy var backend = ChargeBackendSession(ordinaryPending:{try self.store.load() != nil},firmwarePending:{try self.store.firmwareStore().load() != nil},
  ordinary:ordinary.apply,firmwareEligible:eligible,firmwareInspect:{ if self.failPreflight { throw Failure.injected }; _ = try self.numeric.inspect() },
  firmwareLimit:numeric.setLimit,firmwareInhibit:numeric.inhibitCharging,firmwareExit:{try self.numeric.finishExit(limit:$0)},firmwareRestore:numeric.restore,inflow:inflow)
 lazy var helper = FirmwareControlSession(status:{"fixture status"},preflight:{if self.failHelperPreflight { throw Failure.injected }; _ = try self.numeric.inspect()},beforeMutation:{self.events.append("arm")},
  limit:backend.setFirmwareLimit,inhibit:backend.inhibitFirmware,discharge:backend.dischargeFirmware,beforeExit:{self.events.append("releaseSleep")},exit:backend.finishFirmwareExit)
 func ready() throws { _ = try helper.execute(.limit(65),recoveryPending:false,sleepObserverAvailable:true); _ = try helper.execute(.sleepTarget(65),recoveryPending:false,sleepObserverAvailable:true) }
 func force() throws { _ = try helper.execute(.discharge,recoveryPending:backend.recoveryRequired,sleepObserverAvailable:true) }
 func record() throws -> Bool { try store.firmwareStore().load() != nil }
}
@main struct FirmwareDischargeSessionTests {
 static let keyProfile: SMCFirmwareKeyProfile = CommandLine.arguments.contains("--bclm-only") ? .limitOnly : .chargeAndLimit
 static var checks = 0
 static func check(_ value: Bool) { precondition(value); checks += 1 }
 static func rejects(_ action: () throws -> Void) { do { try action(); preconditionFailure("unexpected success") } catch { checks += 1 } }
 static func main() throws {
  // Actual numeric/ordinary journals and helper state, injected SMC and IOPM only.
  let f = try Fixture(); try f.ready(); f.events = []; try f.force()
  check(f.values["BCLM"] == [15] && f.token == 31 && f.helper.discharging)
  check(f.events.first == "arm" && f.events.firstIndex(of:"write:BCLM:15")! < f.events.firstIndex(of:"create")!)
  check(try f.record()); check(try f.store.load() == nil)
  f.events = []; try f.force(); check(!f.events.contains("create") && f.events.contains("inspect:31"))
  f.events = []; let applied = try f.helper.applySleep(recoveryPending:false)
  check(applied && !f.helper.discharging && f.token == nil && f.values["BCLM"] == [65])
  check(f.events.firstIndex(of:"release:31")! < f.events.firstIndex(of:"write:BCLM:65")!)
  try f.force(); check(f.token == 32); f.events = []
  _ = try f.helper.execute(.exit(75),recoveryPending:false,sleepObserverAvailable:true)
  check(f.token == nil && f.values["BCLM"] == [75] && !f.helper.active)
  check(f.events.firstIndex(of:"release:32")! < f.events.firstIndex(of:"write:BCLM:75")!)
  check(try !f.record()); try f.backend.restore(); check(f.values["BCLM"] == [75])

  // Two-phase exit retains the real journal until an explicit matching commit.
  for outcome in ["cancel","commit","restart","external"] {
   let x = try Fixture(), id = UUID(); try x.ready(); try x.force(); x.events = []
   _ = try x.helper.execute(.exitPrepare(75,id),recoveryPending:false,sleepObserverAvailable:true)
   check(x.token == nil && x.values["BCLM"] == [75] && x.helper.active && x.helper.pendingExit?.id == id)
   check(try x.record()); check(x.events.firstIndex(of:"release:31")! < x.events.firstIndex(of:"write:BCLM:75")!)
   x.events = []
   _ = try x.helper.execute(.exitPrepare(75,id),recoveryPending:false,sleepObserverAvailable:true)
   check(x.events.isEmpty)
   if outcome == "commit" {
    _ = try x.helper.execute(.exitCommit(id),recoveryPending:false,sleepObserverAvailable:true)
    check(try !x.record()); check(!x.helper.active && x.values["BCLM"] == [75])
    try x.backend.restore(); check(x.values["BCLM"] == [75])
   } else if outcome == "restart" {
    let recovered = SMCFirmwareChargeController(eligibleHost:true,batteryPresent:true,keyProfile:keyProfile,
     read:{x.values[$0].map {SMCByteReading(dataType:"ui8 ",bytes:$0)}},write:{try x.write($0,[$1])},
     authorized:{true},recoveryStore:x.store.firmwareStore(),bootSession:x.boot)
    try recovered.restore(); check(x.values["BCLM"] == [80]); check(try !x.record())
   } else if outcome == "external" {
    x.values["BCLM"] = [90]
    rejects { _ = try x.helper.execute(.exitCommit(id),recoveryPending:false,sleepObserverAvailable:true) }
    try x.backend.restore(); check(x.values["BCLM"] == [90]); check(try !x.record())
   } else {
    try x.backend.restore(); x.helper.reset()
    check(x.values["BCLM"] == [80]); check(try !x.record())
    rejects { _ = try x.helper.execute(.exitCommit(id),recoveryPending:false,sleepObserverAvailable:true) }
   }
  }

  for destination in ["limit","inhibit","ordinary","restore","exit"] {
   let x = try Fixture(); try x.ready(); try x.force(); x.events = []
   switch destination {
   case "limit": try x.backend.setFirmwareLimit(70)
   case "inhibit": try x.backend.inhibitFirmware()
   case "ordinary": try x.backend.apply(.inhibitCharge)
   case "exit": try x.backend.finishFirmwareExit(75)
   default: try x.backend.restore()
   }
   check(x.token == nil && x.inflow.ownedID == nil)
   if let write = x.events.firstIndex(where:{$0.hasPrefix("write:")}) { check(x.events.firstIndex(of:"release:31")! < write) }
   try x.backend.restore(); check(try x.store.load() == nil); check(try !x.record())
  }
  for failure in ["create","inspect","release"] {
   let x = try Fixture(); try x.ready()
   x.failCreate = failure == "create"; x.failInspect = failure != "create"; x.failRelease = failure == "release"
   rejects { try x.force() }
   check(!x.helper.discharging)
   if failure == "release" {
    check(x.token == 31 && x.inflow.ownedID == 31 && x.backend.recoveryRequired)
    check(x.values["BCLM"] == [15]); check(try x.record())
    x.events = []; rejects { try x.backend.setFirmwareLimit(70) }; check(x.events.isEmpty)
    // A previous failed request is retried at sleep entry, before policy writes.
    x.events = []; rejects { _ = try x.helper.reconcileSleep(recoveryPending:true,restore:x.backend.restore) }
    check(!x.events.contains(where:{$0.hasPrefix("write:")})); check(x.token == 31)
    x.failRelease = false; x.failInspect = false
    let result = try x.helper.reconcileSleep(recoveryPending:true,restore:x.backend.restore)
    check(result == .restored && !x.helper.active)
   }
   check(x.token == nil && x.inflow.ownedID == nil && !x.backend.recoveryRequired)
   check(x.values["BCLM"] == [80]); check(try !x.record())
  }
  // Failed release must precede and prevent every later hardware transaction.
  for destination in ["limit","inhibit","ordinary","restore","exit"] {
   let x = try Fixture(); try x.ready(); try x.force(); x.failRelease = true; x.events = []
   rejects {
    switch destination { case "limit": try x.backend.setFirmwareLimit(70)
    case "inhibit": try x.backend.inhibitFirmware()
    case "ordinary": try x.backend.apply(.allowCharge)
    case "exit": try x.backend.finishFirmwareExit(75)
    default: try x.backend.restore() }
   }
   check(x.token == 31 && x.backend.recoveryRequired && x.values["BCLM"] == [15])
   check(!x.events.contains(where:{$0.hasPrefix("write:")})); check(try x.record())
   x.failRelease = false; try x.backend.restore(); check(x.token == nil && x.values["BCLM"] == [80])
  }
  let denied = try Fixture(); denied.eligible = false
  rejects { try denied.backend.dischargeFirmware() }; check(denied.events.isEmpty && denied.token == nil)
  let broken = try Fixture(); try broken.ready(); broken.failWrite = true
  rejects { try broken.force() }; check(!broken.events.contains("create") && broken.token == nil)
  broken.failWrite = false; try broken.backend.restore(); check(broken.values["BCLM"] == [80])
  let preflight = try Fixture(); try preflight.ready(); try preflight.force(); preflight.failPreflight = true; preflight.events = []
  rejects { try preflight.backend.dischargeFirmware() }
  check(preflight.token == nil && preflight.values["BCLM"] == [80] && !preflight.backend.recoveryRequired)
  check(!preflight.events.contains("create")); check(try !preflight.record())
  let old = try Fixture(); try old.backend.apply(.inhibitCharge); let ordinaryState = old.values
  old.failPreflight = true; old.events = []; rejects { try old.backend.dischargeFirmware() }
  check(old.values == ordinaryState && old.backend.active == .ordinary && old.token == nil && old.events.isEmpty)
  try old.backend.restore()
  let root = try Fixture(); try root.ready(); try root.force(); root.failHelperPreflight = true; root.events = []
  rejects { try root.force() }; check(root.helper.requiresRecoveryAfterFailure(.discharge))
  check(root.events.isEmpty && root.token == 31)
  _ = try root.helper.reconcileSleep(recoveryPending:true,restore:root.backend.restore)
  check(root.token == nil && root.values["BCLM"] == [80] && !root.helper.active)
  let atomic = try Fixture()
  _ = try atomic.helper.execute(.plan(.allow,sleepTarget:80),recoveryPending:false,sleepObserverAvailable:true)
  check(atomic.values["BCLM"] == [100] && atomic.helper.active && atomic.helper.sleepTarget == 80)
  check(try atomic.record())
  _ = try atomic.helper.execute(.plan(.inhibit,sleepTarget:15),recoveryPending:false,sleepObserverAvailable:true)
  _ = try atomic.helper.execute(.plan(.discharge,sleepTarget:65),recoveryPending:false,sleepObserverAvailable:true)
  check(atomic.values["BCLM"] == [15] && atomic.token == 31 && atomic.helper.sleepTarget == 65)
  let result = try atomic.helper.reconcileSleep(recoveryPending:false,restore:atomic.backend.restore)
  check(result == .applied && atomic.token == nil && atomic.values["BCLM"] == [65])
  try atomic.backend.restore(); check(atomic.values["BCLM"] == [80]); check(try !atomic.record())
  print("Firmware discharge composition (\(keyProfile.rawValue)): \(checks) helper/backend/ownership checks passed; injected SMC and IOPM only")
 }
}
