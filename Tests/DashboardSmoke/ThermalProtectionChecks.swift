import Foundation
import ChargeCore

@MainActor func thermalProtectionChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy = ChargePolicy(); fixture.policy.sailing = true
 fixture.policy.keepAwakeWithLidClosed = true; fixture.calibrationCheckpoint = nil
 try fixture.save()
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  screenLockRequest: { preconditionFailure("no locks in thermal fixture") })
 model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
 model.config.hardwareEnabled = true
 var engine = ChargeEngine(); let start = Date(timeIntervalSince1970: 1_700_000_000)
 let samples = [ChargeSample(date: start, percent: 50, temperature: 40),
  ChargeSample(date: start.addingTimeInterval(100), percent: 79, temperature: nil),
  ChargeSample(date: start.addingTimeInterval(299), percent: 79, temperature: 30),
  ChargeSample(date: start.addingTimeInterval(300), percent: 79, temperature: 30),
  ChargeSample(date: start.addingTimeInterval(602), percent: 80, temperature: 30)]
 for (index, sample) in samples.enumerated() {
  let decision = engine.decide(sample, policy: fixture.policy); model.decision = decision
  if index < 3 { precondition(decision.phase == .heatProtect && decision.thermalHold == true && decision.sailingHold == false) }
  let plan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
   action: decision.action, percent: sample.percent, target: decision.effectiveLimit, calibrating: false,
   idleUntilTarget: false, systemUntilTarget: true, allowDisplaySleep: true, thermalHold: decision.thermalHold == true)
  precondition(plan.preventSystemAndLidSleep == (index < 4) && !plan.preventIdleSleep)
  var events: [String] = []
  model.applyHardwareDecision(plan, request: { events.append($0); return "fixture acknowledgement" },
   setIdleSleep: { events.append("idle:\($0)") })
  if !plan.preventSystemAndLidSleep {
   model.updateSleepOverride(plan, request: { events.append($0); return "fixture release" })
  }
  let action = index == 3 ? "allowCharge" : "inhibitCharge"
  let expected = index < 4 ? ["sleepOverrideOn", "sleepPolicyOff", action, "idle:false"] : ["sleepPolicyOff", action, "idle:false", "sleepOverrideRestore"]
  precondition(events == (index == 0 ? ["inhibitCharge"] : []) + expected && model.config.hardwareEnabled)
 }
 model.config.hardwareEnabled = false
 print("Confirmed heat wait survives the Sailing band and unavailable temperature, retains selected protection, resumes on cooling and releases at target; all actuators injected")
}
