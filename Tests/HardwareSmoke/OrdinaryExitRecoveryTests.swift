import Foundation

private final class ExitStore: ChargeRecoveryStore {
 var bytes: Data?
 func load() throws -> Data? { bytes }
 func save(_ data: Data?) throws { bytes = data }
}
@main struct OrdinaryExitRecoveryTests {
 static func main() throws {
  for modern in [true,false] {
   for committed in [false,true] {
    let store = ExitStore(), boot = UUID().uuidString
    let initial: [String:[UInt8]] = modern ? ["CHTE":[0,0,0,0],"CHIE":[0]] : ["CH0B":[0],"CH0C":[0],"CH0I":[0]]
    var values = initial, writes = 0
    func controller() -> SMCChargeController {
     SMCChargeController(batteryPresent:true,read:{values[$0]},write:{values[$0] = $1;writes += 1},authorized:{true},recoveryStore:store,bootSession:boot)
    }
    let owned = controller(), exit = OrdinaryExitSession(), id = UUID()
    try owned.apply(.forceDischarge)
    precondition(store.bytes != nil)
    _ = try exit.execute(.prepare(id),recoveryPending:false,available:true,prepare:{try owned.apply(.retainInhibit)},renew:{},commit:{})
    precondition(values[modern ? "CHIE" : "CH0I"] == [0],"preparation must restore adapter inflow")
    if committed { _ = try exit.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{}) }
    let journal = store.bytes, oldWrites = writes; var cleanup: [String] = []
    try exit.cleanupForServiceExit(recoveryPending:false,restoreCharge:{try owned.apply(.restore)},restoreLED:{cleanup.append("LED")},restoreSleep:{cleanup.append("sleep")})
    precondition(cleanup == ["LED","sleep"])
    if committed {
     precondition(writes == oldWrites && store.bytes == journal,"service exit must preserve charge and its original-value journal")
     // A restarted controller has no receipt; it recovers the actual production journal.
     try controller().apply(.restore)
    }
    precondition(values == initial && store.bytes == nil,"uncommitted exit or same-boot startup must restore captured originals")
   }
  }
  // Retention must not broaden compare-and-restore ownership over external changes.
  let store = ExitStore(), boot = UUID().uuidString
  var values: [String:[UInt8]] = ["CH0B":[0],"CH0C":[0],"CH0I":[0]]
  func controller() -> SMCChargeController {
   SMCChargeController(batteryPresent:true,platform:.appleSilicon,read:{values[$0]},write:{values[$0] = $1},authorized:{true},recoveryStore:store,bootSession:boot)
  }
  let c = controller(), exit = OrdinaryExitSession(), id = UUID()
  try c.apply(.forceDischarge)
  _ = try exit.execute(.prepare(id),recoveryPending:false,available:true,prepare:{try c.apply(.retainInhibit)},renew:{},commit:{})
  _ = try exit.execute(.commit(id),recoveryPending:false,available:true,prepare:{},renew:{},commit:{})
  values["CH0C"] = [2]
  try exit.cleanupForServiceExit(recoveryPending:false,restoreCharge:{preconditionFailure("committed state")},restoreLED:{},restoreSleep:{})
  try controller().apply(.restore)
  precondition(values["CH0C"] == [2] && store.bytes == nil,"external state must survive same-boot recovery")
  print("PASS ordinary exit with production fixed-key planner/journal: modern and legacy discharge cleanup, staged versus committed service exit, same-boot startup and external interference; all SMC reads/writes injected")
 }
}
