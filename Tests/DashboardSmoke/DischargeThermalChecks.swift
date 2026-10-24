import Foundation
import ChargeCore

@MainActor func dischargeThermalChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy = ChargePolicy(); fixture.calibrationCheckpoint = nil
 try fixture.save()
 for mode in [ChargeMode.discharge, .automatic] {
  for closed in [false, true] {
   let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
    screenLockRequest: { preconditionFailure("no locks in discharge/temperature fixture") })
   var policy = fixture.policy; policy.mode = mode; policy.automaticDischarge = mode == .automatic
   var engine = ChargeEngine()
   let sample = ChargeSample(percent: 90, temperature: 40, lidClosed: closed)
   let decision = engine.decide(sample, policy: policy)
   precondition(decision.action == .forceDischarge && decision.thermalHold == false)
   model.config.policy = policy; model.decision = decision
   model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
   model.config.hardwareEnabled = true
   let protection = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
    action: decision.action, percent: sample.percent, target: decision.effectiveLimit, calibrating: false,
    idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true, lidClosed: closed,
    thermalHold: decision.thermalHold == true)
   var events: [String] = []
   model.applyHardwareDecision(protection, request: { events.append($0); return "fixture acknowledgement" },
    setIdleSleep: { events.append("idle:\($0)") })
   precondition(events == (closed ? ["inhibitCharge", "sleepOverrideOn", "sleepPolicyOff", "forceDischarge", "idle:false"] : ["sleepPolicyOff", "forceDischarge", "idle:false"]))
   model.config.hardwareEnabled = false
   let released = SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true,
    action: .restore, percent: 90, target: 80, calibrating: false,
    idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true)
   model.updateSleepOverride(released, request: { _ in "fixture release" })
  }
 }
 print("Charging temperature does not block ordinary discharge; actual policy decisions retain required lid preflight; all actuators injected")
}

@MainActor func fractionalDischargeChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy = ChargePolicy(); fixture.calibrationCheckpoint = nil
 try fixture.save()
 for mode in [ChargeMode.discharge, .automatic] {
  let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("no locks in fractional discharge fixture") })
  model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  var policy = fixture.policy; policy.mode = mode; policy.automaticDischarge = mode == .automatic
  model.config.policy = policy; model.config.hardwareEnabled = true
  var engine = ChargeEngine()
  for percent in [90.0, 80.6] {
   let decision = engine.decide(ChargeSample(percent: percent, temperature: 40, lidClosed: true), policy: policy)
   model.decision = decision
   let running = percent == 90
   precondition(decision.action == (running ? .forceDischarge : .inhibitCharge))
   if !running { precondition(engine.completedMode == (mode == .discharge ? .discharge : nil)) }
   let plan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
    action: decision.action, percent: percent, target: decision.effectiveLimit, calibrating: false,
    idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true, lidClosed: true,
    thermalHold: decision.thermalHold == true)
   var events: [String] = []
   model.applyHardwareDecision(plan, request: { events.append($0); return "fixture acknowledgement" },
    setIdleSleep: { events.append("idle:\($0)") })
   if !plan.preventSystemAndLidSleep { model.updateSleepOverride(plan, request: { events.append($0); return "fixture release" }) }
   let expected = running ? ["inhibitCharge", "idle:true", "sleepOverrideOn", "sleepPolicyOff", "forceDischarge"] : ["sleepPolicyOff", "inhibitCharge", "idle:false", "sleepOverrideRestore"]
   precondition(events == expected && model.config.hardwareEnabled)
  }
  model.config.hardwareEnabled = false
 }
 print("Fractional discharge completes in its target percentage bin and releases selected lid/idle protection; all actuators injected")
}
