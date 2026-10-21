import Foundation
import ChargeCore

@MainActor func thermalExitChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider }
 var fixture = original
 fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.magSafeMode = .system; fixture.magSafeOffDuringSleep = false
 fixture.policy = ChargePolicy(); fixture.policy.limit = 100; fixture.policy.sailing = false
 fixture.policy.keepAwakeUntilLimit = true; fixture.policy.keepAwakeWithLidClosed = true
 fixture.policy.allowDisplaySleep = true; fixture.calibrationCheckpoint = nil
 try fixture.save()
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  screenLockRequest: { preconditionFailure("no locks in thermal-exit fixture") })
 model.inspectSleepInterfaces(request: { command in
  precondition(command == "capabilities")
  return "sleepOverride:interfacesDetected, sleepRecovery:phasesV1"
 })
 // All calls below are synchronous on the main actor, with both actuator paths injected.
 // The saved configuration remains monitoring-only throughout the fixture.
 model.config.hardwareEnabled = true
 defer { model.config.hardwareEnabled = false }
 var policy = fixture.policy; var engine = ChargeEngine()
 let start = Date(timeIntervalSince1970: 1_700_000_000)
 let samples = [ChargeSample(date: start, percent: 99, temperature: 40),
  ChargeSample(date: start.addingTimeInterval(10), percent: 100, temperature: 40),
  ChargeSample(date: start.addingTimeInterval(11), percent: 100, temperature: 30),
  ChargeSample(date: start.addingTimeInterval(400), percent: 100, temperature: 30),
  ChargeSample(date: start.addingTimeInterval(401), percent: 99.9, temperature: 30)]
 for (index, sample) in samples.enumerated() {
  if index == 1 { policy.heatProtection = false }
  model.config.policy = policy
  let decision = engine.decide(sample, policy: policy); model.decision = decision
  let selectedProtection = index == 0 || index == 4
  precondition(decision.phase == (index == 0 ? .heatProtect : index == 4 ? .charging : .pause))
  precondition(decision.action == (index == 4 ? .allowCharge : .inhibitCharge))
  precondition(decision.thermalHold == (index == 0) && decision.fullChargeHold == false)
  let plan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true,
   action: decision.action, percent: sample.percent, target: decision.effectiveLimit, calibrating: false,
   idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true,
   thermalHold: decision.thermalHold == true, fullChargeHold: decision.fullChargeHold == true)
  precondition(plan.preventIdleSleep == selectedProtection)
  precondition(plan.preventSystemAndLidSleep == selectedProtection && !plan.preventDisplaySleep)
  var events: [String] = []
  model.applyHardwareDecision(plan, request: { events.append($0); return "fixture acknowledgement" },
   setIdleSleep: { events.append("idle:\($0)") })
  if !plan.preventSystemAndLidSleep {
   model.updateSleepOverride(plan, request: { events.append($0); return "fixture release" })
  }
  let expected: [String]
  switch index {
  case 0: expected = ["idle:true", "sleepOverrideOn", "sleepPolicyOff", "inhibitCharge"]
  case 1: expected = ["sleepPolicyOff", "inhibitCharge", "idle:false", "sleepOverrideRestore"]
  case 4: expected = ["idle:true", "sleepOverrideOn", "sleepPolicyOff", "allowCharge"]
  default: expected = ["sleepPolicyOff", "inhibitCharge", "idle:false"]
  }
  precondition(events == expected && model.config.hardwareEnabled)
 }
 let released = SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true,
  action: .restore, percent: 99.9, target: 100, calibrating: false,
  idleUntilTarget: true, systemUntilTarget: true, allowDisplaySleep: true)
 model.config.hardwareEnabled = false
 var cleanup: [String] = []
 model.updateSleepOverride(released, request: { cleanup.append($0); return "fixture cleanup" })
 precondition(cleanup == ["sleepOverrideRestore"])
 print("Thermal opt-out at full keeps Pause, releases selected protection once, and reacquires it before later charging; all actuators injected")
}
