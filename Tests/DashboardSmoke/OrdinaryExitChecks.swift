import Foundation
import ChargeCore
import ChargeHardware

@MainActor func ordinaryExitChecks(defaults: UserDefaults) throws {
 let before = try Configuration.load()
 defer { try? before.save() }
 var c = Configuration(); c.historyEnabled = false; c.policy.stopOnQuit = true; try c.save()
 let m = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no lock")},readBattery:{BatteryReading(percent:90,connected:true,charging:false)})
 let root = OrdinaryExitSession(); var calls: [String] = [], writes = 0, held = false, originalJournal = true
 var loseCommit = false
 func request(_ wire: String) throws -> String {
  calls.append(wire)
  if wire == "capabilities" { return "chargeControl:fixture,ordinaryExit:preparedV1" }
  if wire == "restore" { root.reset(); held = false; originalJournal = false; return "restored" }
  guard let command = OrdinaryExitCommand.parse(wire) else { preconditionFailure("unexpected real control request") }
  let reply = try root.execute(command,recoveryPending:false,available:true,prepare:{writes += 1;held = true;originalJournal = true},renew:{},commit:{})
  if case .commit = command, loseCommit { loseCommit = false; throw HelperError.unavailable }
  return reply
 }
 m.enableHardware(true,request:request,refresh:{})
 calls = []; try m.prepareForQuit(request:request)
 precondition(writes == 1 && held && originalJournal)
 guard calls.count == 1, case .prepare(let id)? = OrdinaryExitCommand.parse(calls[0]) else { preconditionFailure("ordinary exit must prepare") }
 try m.renewPreparedQuit(request:request)
 precondition(writes == 1 && calls.last == OrdinaryExitCommand.prepare(id).wireValue)
 loseCommit = true
 do { try m.commitQuit(request:request); preconditionFailure("lost commit reply") } catch {}
 precondition(root.committedID == id && !m.numericExitCommitStarted,"ordinary commit keeps recoverable original-value ownership")
 m.cancelQuit(request:request,refresh:{})
 precondition(!m.config.hardwareEnabled && !m.needsQuitPreparation && !held && !originalJournal && root.committedID == nil)
 m.enableHardware(true,request:request,refresh:{})
 calls = []; try m.prepareForQuit(request:request); try m.commitQuit(request:request)
 precondition(held && originalJournal && root.committedID != nil)
 var cleanup: [String] = []
 try root.cleanupForServiceExit(recoveryPending:false,restoreCharge:{preconditionFailure("committed charge journal must remain")},restoreLED:{cleanup.append("LED")},restoreSleep:{cleanup.append("sleep")})
 precondition(cleanup == ["LED","sleep"] && held && originalJournal)
 m.cancelQuit(request:request,refresh:{})
 precondition(!held && !originalJournal && !m.config.hardwareEnabled)
 print("PASS ordinary prepared exit: actual model negotiation, no-write renewal, ambiguous commit cancellation, graceful service retention and original journal; injected actuators only")
}
