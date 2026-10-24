import Foundation
import ChargeCore
import ChargeHardware

@MainActor private final class NumericRoot {
 let capabilities = "chargeControl:fixture,firmwareProtocol:fixedV1,firmwareRead:CH0B+BCLM,firmwareWrite:fixedV1,internalBattery:present,chargeRecovery:ready,firmwarePlan:atomicSleepV1,firmwareDischarge:inflowV1,sleepOverride:interfacesDetected,sleepRecovery:phasesV1"
 var calls: [String] = []
 var limit = 80
 var inflow = false
 var protected = false
 var creates = 0
 var dropAfter: String?
 var restoreFails = false
 var protectionFails = false
 lazy var helper = FirmwareControlSession(status:{"limit=\(self.limit),charging=inhibited"},preflight:{},beforeMutation:{},
  limit:{self.inflow = false;self.limit = $0},inhibit:{self.inflow = false;self.limit = 15},
  discharge:{precondition(self.protected,"required sleep protection must precede inflow-off");self.limit = 15;if !self.inflow { self.creates += 1 };self.inflow = true},
  beforeExit:{self.protected = false},exit:{self.inflow = false;self.limit = $0})
 func request(_ command: String) throws -> String {
  calls.append(command)
  if command == "capabilities" { return capabilities }
  if command == "restore" {
   if restoreFails { throw HelperError.unavailable }
   inflow = false; protected = false; if helper.active { limit = 80 }; helper.reset(); return "restored"
  }
  if command == "sleepOverrideOn" || command == "sleepOverrideDisplayOn" {
   guard helper.active else { throw HelperError.rejected("a current charge session is required") }
   if protectionFails { throw HelperError.unavailable }
   protected = true; return "protected"
  }
  if command == "sleepOverrideRestore" { protected = false; return "released" }
  guard let value = FirmwareCommand.parse(command) else { preconditionFailure("unexpected ordinary setter: "+command) }
  let result = try helper.execute(value,recoveryPending:false,sleepObserverAvailable:true)
  if dropAfter == command { throw HelperError.unavailable }
  return result
 }
}
@MainActor func firmwareControlChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var config = Configuration(); config.historyEnabled = false; try config.save()
 func model() -> ChargeModel { ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no locks")},readBattery:{BatteryReading(percent:90,connected:true,charging:false)}) }
 let m = model(), root = NumericRoot()
 for old in ["chargeControl:fixture",root.capabilities.replacingOccurrences(of:",firmwarePlan:atomicSleepV1",with:"")] {
  do { try m.configureHardwareChannel(capabilities:old,numericRequired:true); preconditionFailure("must not fall back") } catch {}
 }
 m.enableHardware(true,request:root.request,refresh:{})
 precondition(m.usesNumericFirmware && m.config.hardwareEnabled && root.calls == ["capabilities"])
 m.decision = Decision(.forceDischarge,"fixture",limit:80); m.decision.phase = .discharging
 let plan = SleepProtectionPlan.evaluate(controlEnabled:true,connected:true,physicalAdapterConnected:true,action:.forceDischarge,percent:90,target:80,calibrating:false,idleUntilTarget:false,systemUntilTarget:false,allowDisplaySleep:true,lidClosed:true)
 root.calls = []; m.applyHardwareDecision(plan,request:root.request,setIdleSleep:{_ in})
 precondition(root.calls == ["firmwarePlan:inhibit:15","sleepOverrideOn","firmwareSessionStatus","firmwarePlan:discharge:15"])
 precondition(root.inflow && root.creates == 1 && m.config.hardwareEnabled)
 root.calls = []; m.applyHardwareDecision(plan,request:root.request,setIdleSleep:{_ in})
 precondition(root.calls == ["sleepOverrideOn","firmwareSessionStatus","firmwarePlan:discharge:15"] && root.creates == 1)
 root.calls = []; m.sleep(request:root.request); precondition(root.calls.isEmpty)
 _ = try root.helper.reconcileSleep(recoveryPending:false,restore:{_ = try root.request("restore")})
 precondition(!root.inflow && root.helper.active)
 root.calls = []; m.applyHardwareDecision(plan,request:root.request,setIdleSleep:{_ in})
 precondition(root.inflow && root.creates == 2)
 m.config.policy.sailing = true; m.config.policy.stopOnQuit = true
 root.calls = []; try m.prepareForQuit(request:root.request)
 precondition(root.calls == ["sleepOverrideRestore","firmwareExit:80"] && !root.inflow && root.limit == 80)
 precondition(m.automationPhase == .exit)

 var clean = Configuration(); clean.historyEnabled = false; try clean.save()
 let failed = model(), ambiguous = NumericRoot()
 failed.enableHardware(true,request:ambiguous.request,refresh:{})
 failed.decision = Decision(.allowCharge,"fixture",limit:80); failed.decision.phase = .charging
 ambiguous.dropAfter = "firmwarePlan:allow:80"; ambiguous.restoreFails = true
 let charging = SleepProtectionPlan.evaluate(controlEnabled:true,connected:true,physicalAdapterConnected:true,action:.allowCharge,percent:50,target:80,calibrating:false,idleUntilTarget:false,systemUntilTarget:false,allowDisplaySleep:true)
 failed.applyHardwareDecision(charging,request:ambiguous.request,setIdleSleep:{_ in})
 precondition(!failed.config.hardwareEnabled && failed.needsQuitPreparation)
 do { try failed.configureHardwareChannel(capabilities:ambiguous.capabilities); preconditionFailure("cannot discard pending ownership") } catch {}
 ambiguous.restoreFails = false; ambiguous.dropAfter = nil; ambiguous.calls = []
 try failed.prepareForQuit(request:ambiguous.request)
 precondition(ambiguous.calls == ["restore"] && !failed.needsQuitPreparation)

 try clean.save(); let disabled = model(), last = NumericRoot()
 disabled.enableHardware(true,request:last.request,refresh:{})
 disabled.decision = Decision(.allowCharge,"fixture",limit:80); disabled.applyHardwareDecision(charging,request:last.request,setIdleSleep:{_ in})
 last.calls = []; disabled.enableHardware(false,request:last.request,refresh:{})
 precondition(last.calls == ["restore"] && !disabled.config.hardwareEnabled && !disabled.needsQuitPreparation)
 try clean.save(); let rejected = model(), denied = NumericRoot(); denied.protectionFails = true
 rejected.enableHardware(true,request:denied.request,refresh:{})
 rejected.decision = Decision(.forceDischarge,"fixture",limit:80); rejected.decision.phase = .discharging
 denied.calls = []; rejected.applyHardwareDecision(plan,request:denied.request,setIdleSleep:{_ in})
 precondition(denied.calls == ["firmwarePlan:inhibit:15","sleepOverrideOn","restore"] && denied.creates == 0 && !rejected.config.hardwareEnabled)
 try clean.save(); let cancelled = model(), exitLoss = NumericRoot()
 cancelled.enableHardware(true,request:exitLoss.request,refresh:{})
 cancelled.config.policy.limit = 75; cancelled.decision = Decision(.allowCharge,"fixture",limit:75)
 cancelled.applyHardwareDecision(charging,request:exitLoss.request,setIdleSleep:{_ in})
 exitLoss.dropAfter = "firmwareExit:75"
 do { try cancelled.prepareForQuit(request:exitLoss.request); preconditionFailure("lost exit acknowledgement") } catch {}
 precondition(exitLoss.limit == 75 && cancelled.needsQuitPreparation)
 exitLoss.dropAfter = nil; exitLoss.calls = []; cancelled.cancelQuit(request:exitLoss.request)
 precondition(exitLoss.calls == ["restore"] && exitLoss.limit == 75 && !cancelled.config.hardwareEnabled && !cancelled.needsQuitPreparation)
 print("Numeric app selection, protected bootstrap, repeated discharge/wake, current Exit target, ambiguous-response recovery and disable use injected actual helper state; no hardware/IOPM/service requests")
}
