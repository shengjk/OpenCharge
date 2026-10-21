import Foundation
import ChargeCore

@MainActor func fullChargeChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy = ChargePolicy(); fixture.calibrationCheckpoint = nil
 try fixture.save()
 for mode in [ChargeMode.automatic, .topUp] {
  let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in full-charge fixture") })
  model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  var policy = fixture.policy; policy.mode = mode
  if mode == .automatic { policy.limit = 100 }
  model.config.policy = policy; model.config.hardwareEnabled = true
  var engine = ChargeEngine()
  for percent in [90.0, 100, 99.5] {
   let decision = engine.decide(ChargeSample(percent: percent, temperature: 30), policy: policy)
   model.decision = decision
   precondition(decision.action == .allowCharge && engine.completedMode == nil)
   let full = percent == 100
   precondition(decision.fullChargeHold == full)
   let plan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
    action: decision.action, percent: percent, target: decision.effectiveLimit, calibrating: false,
    idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true,
    fullChargeHold: decision.fullChargeHold == true)
   var events: [String] = []
   model.applyHardwareDecision(plan, request: { events.append($0); return "fixture acknowledgement" },
    setIdleSleep: { events.append("idle:\($0)") })
   if !plan.preventSystemAndLidSleep { model.updateSleepOverride(plan, request: { events.append($0); return "fixture release" }) }
   let expected = full ? ["sleepPolicyOff", "allowCharge", "idle:false", "sleepOverrideRestore"] : ["idle:true", "sleepOverrideOn", "sleepPolicyOff", "allowCharge"]
   precondition(events == expected && model.config.hardwareEnabled)
  }
  model.config.hardwareEnabled = false
  let released = SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true,
   action: .restore, percent: 99.5, target: 100, calibrating: false,
   idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true)
  model.updateSleepOverride(released, request: { _ in "fixture cleanup" })
 }
 print("Ordinary full targets and Top Up allow system top-off, release selected protection at full and reacquire before later charging; all actuators injected")
}
