import Foundation
import ChargeCore
import ChargeHardware

@MainActor func quitRestartRecoveryChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.quit-restart."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); defaults.removePersistentDomain(forName:suite); PolicyStateRuntime.provider = provider }
 enum Failure: Error { case service, storage }
 func model(request: (String) throws -> String, persist: (Configuration) throws -> Void = {try $0.save()}) -> ChargeModel {
  ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no screen lock")},readBattery:{BatteryReading(percent:50,connected:true,charging:false)},startupRecoveryRequest:request,startupRecoveryPersist:persist)
 }
 var fresh = Configuration(); fresh.historyEnabled = false; try fresh.save()
 let first = model(request:{ _ in preconditionFailure("fresh startup IPC") })
 first.config.hardwareEnabled = true; first.config.policy.stopOnQuit = true
 try first.prepareForQuit(request:{ _ in "retained fixture" })
 first.cancelQuit(request:{ command in
  precondition(command == "restore")
  let stored = try Configuration.load()
  precondition(stored.pendingOrdinaryQuitRecovery == true && !stored.hardwareEnabled)
  throw Failure.service
 },refresh:{})
 let storedRecovery1 = try Configuration.load()
 precondition(storedRecovery1.pendingOrdinaryQuitRecovery == true)
 var calls: [String] = []
 let restarted = model(request:{ calls.append($0); return "restored fixture" })
 precondition(calls == ["restore"] && !restarted.config.hardwareEnabled && !restarted.needsQuitPreparation)
 let storedRecovery2 = try Configuration.load()
 precondition(storedRecovery2.pendingOrdinaryQuitRecovery == nil)
 first.reloadExternalConfiguration()
 first.cancelQuit(request:{ _ in preconditionFailure("peer already completed recovery") },refresh:{})
 // A stored cancellation wins over even a contradictory old opt-in.
 fresh.hardwareEnabled = true; fresh.pendingOrdinaryQuitRecovery = true; try fresh.save()
 calls = []
 let unavailable = model(request:{ calls.append($0); throw Failure.service })
 precondition(calls == ["restore"] && !unavailable.config.hardwareEnabled && unavailable.needsQuitPreparation)
 calls = []
 unavailable.enableHardware(true,request:{ calls.append($0); throw Failure.service },refresh:{})
 precondition(calls == ["restore"] && !unavailable.config.hardwareEnabled)
 // LED grants follow the same restoration gate; automatic refresh cannot bypass it.
 calls = []
 unavailable.setMagSafe(.green,request:{ calls.append($0); throw Failure.service })
 precondition(calls == ["restore"] && !unavailable.config.hardwareEnabled)
 calls = []
 unavailable.useMagSafePolicy(request:{ calls.append($0); throw Failure.service })
 precondition(calls == ["restore"])
 unavailable.updateMagSafe(request:{ _ in preconditionFailure("pending recovery must block automatic LED control") })
 // A helper acknowledgement cannot erase the marker if its clear save fails.
 calls = []
 let storageFailure = model(request:{ calls.append($0); return "restored fixture" },persist:{ _ in throw Failure.storage })
 precondition(calls == ["restore"] && storageFailure.config.pendingOrdinaryQuitRecovery == true && storageFailure.needsQuitPreparation)
 let storedRecovery3 = try Configuration.load()
 precondition(storedRecovery3.pendingOrdinaryQuitRecovery == true)
 try storageFailure.restoreChargeControl(request:{ command in precondition(command == "restore"); return "retry fixture" })
 precondition(!storageFailure.needsQuitPreparation && !storageFailure.config.hardwareEnabled)
 let storedRecovery4 = try Configuration.load()
 precondition(storedRecovery4.pendingOrdinaryQuitRecovery == nil)
 print("PASS cancelled ordinary quit restart: persisted intent precedes IPC, startup recovery/disabled opt-in, failed service/storage retention, peer completion and retry; isolated files and injected helper only")
}
