import Foundation
import ChargeCore
import ChargeHardware

@MainActor func lidDischargeChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy.mode = .automatic; fixture.policy.lockScreenWhenClosed = false
 fixture.policy.stopInSleep = false; fixture.calibrationCheckpoint = nil
 try fixture.save()
 func model() -> ChargeModel {
  ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in lid/discharge fixture") })
 }
 func plan(_ action: ChargeAction, lid: Bool?, idle: Bool = false) -> SleepProtectionPlan {
  .evaluate(controlEnabled: true, connected: false, physicalAdapterConnected: true,
   action: action, percent: 90, target: 80, calibrating: false,
   idleUntilTarget: idle, systemUntilTarget: false, allowDisplaySleep: true, lidClosed: lid)
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
 failed.applyHardwareDecision(plan(.forceDischarge, lid: false, idle: true), request: { failedCommands.append($0); return "fixture" }, setIdleSleep: {
  failedIdle.append($0); if $0 { throw CocoaError(.fileWriteUnknown) }
 })
 precondition(failedCommands.isEmpty && failedIdle == [true, false] && !failed.config.hardwareEnabled,
  "a failed requested idle assertion must stop before any discharge command")

 let active = model()
 active.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
 active.config.hardwareEnabled = true
 var events: [String] = []
 for (index, lid) in [true, false, true].enumerated() {
  events = []; active.decision = Decision(.forceDischarge, "fixture", limit: 80)
  let protection = plan(.forceDischarge, lid: lid)
  active.applyHardwareDecision(protection, request: { events.append($0); return "fixture" }, setIdleSleep: { events.append("idle:\($0)") })
  if !protection.preventSystemAndLidSleep {
   active.updateSleepOverride(protection, request: { events.append($0); return "fixture release" })
  }
  let expected = lid ? ["sleepOverrideOn", "sleepPolicyOff", "forceDischarge", "idle:false"] : ["sleepPolicyOff", "forceDischarge", "idle:false", "sleepOverrideRestore"]
  precondition(events == (index == 0 ? ["inhibitCharge"] : []) + expected)
 }
 events = []; active.decision = Decision(.inhibitCharge, "fixture complete", limit: 80)
 let complete = plan(.inhibitCharge, lid: true)
 active.applyHardwareDecision(complete, request: { events.append($0); return "fixture" }, setIdleSleep: { events.append("idle:\($0)") })
 active.updateSleepOverride(complete, request: { events.append($0); return "fixture release" })
 precondition(events == ["sleepPolicyOff", "inhibitCharge", "idle:false", "sleepOverrideRestore"])
 active.config.hardwareEnabled = false

 for target in [10.0, 80.0] {
  let calibrating = model()
  let now = ProcessInfo.processInfo.systemUptime
  calibrating.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  calibrating.config.policy.mode = .calibration
  calibrating.config.hardwareEnabled = true
  calibrating.decision = Decision(.forceDischarge, "fixture", limit: target)
  let closed = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
   action: .forceDischarge, percent: 95, target: target, calibrating: true,
   idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true, lidClosed: true)
  func round(_ time: TimeInterval, lid: Bool = true) -> [String] {
   var sent: [String] = []
   calibrating.applyHardwareDecision(closed, request: { sent.append($0); return "fixture" },
    setIdleSleep: { sent.append("idle:\($0)") }, lidClosed: lid, uptime: now + time)
   return sent
  }
  precondition(round(1).isEmpty, "closed-lid calibration must defer fresh discharge at startup")
  calibrating.observeCalibrationAdapter(BatteryReading(percent: 95, connected: false, charging: false), uptime: now + 45)
  calibrating.observeCalibrationAdapter(BatteryReading(percent: 95, connected: true, charging: false), uptime: now + 50)
  precondition(round(64).isEmpty, "closed-lid calibration must defer new discharge after reconnect")
  precondition(round(65) == ["inhibitCharge", "idle:true", "sleepOverrideDisplayOn", "sleepPolicyOff", "forceDischarge"])
  calibrating.observeCalibrationAdapter(BatteryReading(percent: 94, connected: false, charging: false), uptime: now + 66)
  precondition(round(67) == ["idle:true", "sleepOverrideDisplayOn", "sleepPolicyOff", "forceDischarge"])
  calibrating.config.hardwareEnabled = false
 }
 print("Discharge lid-edge refresh, selected idle failure, open/closed protection and completion ordering passed; all actuators injected")
}
