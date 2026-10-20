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
   precondition(events == (closed ? ["sleepOverrideOn", "sleepPolicyOff", "forceDischarge", "idle:false"] : ["sleepPolicyOff", "forceDischarge", "idle:false"]))
   model.config.hardwareEnabled = false
   let released = SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true,
    action: .restore, percent: 90, target: 80, calibrating: false,
    idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true)
   model.updateSleepOverride(released, request: { _ in "fixture release" })
  }
 }
 print("Charging temperature does not block ordinary discharge; actual policy decisions retain required lid preflight; all actuators injected")
}
