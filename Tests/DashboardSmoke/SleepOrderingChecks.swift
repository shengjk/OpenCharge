import Foundation
import ChargeCore

@MainActor func sleepOrderingChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy.mode = .automatic; fixture.calibrationCheckpoint = nil
 try fixture.save()
 for action in [ChargeAction.allowCharge, .forceDischarge] {
  let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in ordering fixture") })
  model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  model.config.hardwareEnabled = true
  model.decision = Decision(action, "fixture", limit: 80)
  let plan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
   action: action, percent: 90, target: 80, calibrating: true,
   idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true)
  var commands: [String] = []
  model.applyHardwareDecision(plan, request: { command in
   commands.append(command)
   if command == "sleepOverrideDisplayOn" { throw CocoaError(.fileWriteUnknown) }
   return "fixture acknowledgement"
  }, setIdleSleep: { _ in })
  if commands.contains(action.rawValue) {
   print("REGRESSION: charge command was sent before required sleep protection succeeded")
   exit(2)
  }
  precondition(commands == ["sleepOverrideDisplayOn", "restore"] && !model.config.hardwareEnabled)
  for failureAfterProtection in [false, true] {
   let protected = ChargeModel(dashboardDefaults: defaults, observeLid: false,
    screenLockRequest: { preconditionFailure("no locks in protected-order fixture") })
   protected.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
   protected.config.hardwareEnabled = true
   protected.decision = Decision(action, "fixture", limit: 80)
   var successful: [String] = []
   protected.applyHardwareDecision(plan, request: { command in
    successful.append(command)
    if failureAfterProtection && command == action.rawValue { throw CocoaError(.fileWriteUnknown) }
    return "fixture acknowledgement"
   }, setIdleSleep: { _ in })
   precondition(successful == ["sleepOverrideDisplayOn", "sleepPolicyOff", action.rawValue] + (failureAfterProtection ? ["restore"] : []))
   precondition(protected.config.hardwareEnabled != failureAfterProtection)
   protected.config.hardwareEnabled = false
   let release = SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true,
    action: .restore, percent: 90, target: 80, calibrating: false,
    idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true)
   var cleanup: [String] = []
   protected.updateSleepOverride(release, request: { cleanup.append($0); return "fixture release" })
   precondition(cleanup == (failureAfterProtection ? [] : ["sleepOverrideRestore"]))
  }
 }
 print("Required sleep protection precedes charge commands, blocks on failure, and restores after later failure; injected calls only")
}
