import Foundation
import ChargeCore

@MainActor func lidDischargeChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy.mode = .automatic; fixture.policy.lockScreenWhenClosed = false
 fixture.policy.stopInSleep = false; fixture.calibrationCheckpoint = nil
 try fixture.save()
 func model() -> ChargeModel {
  ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in lid/discharge fixture") })
 }
 func plan(_ action: ChargeAction, lid: Bool?) -> SleepProtectionPlan {
  .evaluate(controlEnabled: true, connected: false, physicalAdapterConnected: true,
   action: action, percent: 90, target: 80, calibrating: false,
   idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true, lidClosed: lid)
 }
 let observer = model(); var refreshes = 0
 observer.handleLidStateNotification(false, refresh: { refreshes += 1 })
 observer.handleLidStateNotification(true, refresh: { refreshes += 1 })
 precondition(refreshes == 0, "monitoring must not apply hardware decisions on lid events")
 observer.config.hardwareEnabled = true
 observer.handleLidStateNotification(true, refresh: { refreshes += 1 })
 observer.handleLidStateNotification(nil, refresh: { refreshes += 1 })
 precondition(refreshes == 0)
 observer.handleLidStateNotification(false, refresh: { refreshes += 1 })
 observer.handleLidStateNotification(true, refresh: { refreshes += 1 })
 observer.handleLidStateNotification(true, refresh: { refreshes += 1 })
 precondition(refreshes == 2, "each actual lid edge must refresh without waiting for the periodic timer")
 try observer.prepareForQuit(request: { _ in "fixture cleanup" })
 observer.handleLidStateNotification(false, refresh: { refreshes += 1 })
 precondition(refreshes == 2, "quit preparation must suppress event-driven hardware work")
 observer.config.hardwareEnabled = false

 let failed = model(); failed.config.hardwareEnabled = true
 failed.decision = Decision(.forceDischarge, "fixture", limit: 80)
 var failedCommands: [String] = []; var failedIdle: [Bool] = []
 failed.applyHardwareDecision(plan(.forceDischarge, lid: false), request: { failedCommands.append($0); return "fixture" }, setIdleSleep: {
  failedIdle.append($0); if $0 { throw CocoaError(.fileWriteUnknown) }
 })
 precondition(failedCommands.isEmpty && failedIdle == [true, false] && !failed.config.hardwareEnabled,
  "a failed mandatory idle assertion must stop before any discharge command")

 let active = model()
 active.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
 active.config.hardwareEnabled = true
 var events: [String] = []
 for lid in [true, false, true] {
  events = []; active.decision = Decision(.forceDischarge, "fixture", limit: 80)
  let protection = plan(.forceDischarge, lid: lid)
  active.applyHardwareDecision(protection, request: { events.append($0); return "fixture" }, setIdleSleep: { events.append("idle:\($0)") })
  if !protection.preventSystemAndLidSleep {
   active.updateSleepOverride(protection, request: { events.append($0); return "fixture release" })
  }
  let expected = lid ? ["idle:true", "sleepOverrideOn", "sleepPolicyOff", "forceDischarge"] : ["idle:true", "sleepPolicyOff", "forceDischarge", "sleepOverrideRestore"]
  precondition(events == expected)
 }
 events = []; active.decision = Decision(.inhibitCharge, "fixture complete", limit: 80)
 let complete = plan(.inhibitCharge, lid: true)
 active.applyHardwareDecision(complete, request: { events.append($0); return "fixture" }, setIdleSleep: { events.append("idle:\($0)") })
 active.updateSleepOverride(complete, request: { events.append($0); return "fixture release" })
 precondition(events == ["sleepPolicyOff", "inhibitCharge", "idle:false", "sleepOverrideRestore"])
 active.config.hardwareEnabled = false
 print("Discharge lid-edge refresh, required idle failure, open/closed protection and completion ordering passed; all actuators injected")
}
