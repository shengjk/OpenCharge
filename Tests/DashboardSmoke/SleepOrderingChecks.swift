import Foundation
import ChargeCore
import ChargeHardware

@MainActor func sleepOrderingChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy.mode = .automatic; fixture.calibrationCheckpoint = nil
 try fixture.save()
 for action in [ChargeAction.allowCharge, .forceDischarge] {
  let model = ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false,
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
  precondition(commands == ["inhibitCharge", "sleepOverrideDisplayOn", "restore"] && !model.config.hardwareEnabled)
  for failureAfterProtection in [false, true] {
   let protected = ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false,
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
   precondition(successful == ["inhibitCharge", "sleepOverrideDisplayOn", "sleepPolicyOff", action.rawValue] + (failureAfterProtection ? ["restore"] : []))
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

@MainActor func ordinaryProtectionBootstrapChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 for failure in ["none", "inhibitCharge", "sleepOverrideOn", "forceDischarge", "suspend-bootstrap", "suspend-protection"] {
  var config = Configuration(); config.hardwareEnabled = false; config.systemActionsEnabled = false
  config.historyEnabled = false; config.notifications = false; try config.save()
  let model = ChargeModel(automaticRead: nil, dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no locks")},readBattery:{BatteryReading(percent:90,connected:true,charging:false)})
  var session = false, protection = false, failed = false
  var accepted: [String] = []; var transition = ChargePowerTransition()
  func request(_ wire: String) throws -> String {
   let command = try transition.admittedCommand(wire)
   if command == "capabilities" { return "chargeControl:fixture,sleepOverride:interfacesDetected,sleepRecovery:phasesV1,chargeTransition:epochV1" }
   if command == "chargeContext" { return transition.contextReply }
   if !failed && ((failure == "suspend-bootstrap" && command == "inhibitCharge") || (failure == "suspend-protection" && command == "sleepOverrideOn")) {
    failed = true; transition.willSleep(); transition.didWake()
    throw ChargeControlSuspension.systemSleep
   }
   accepted.append(command)
   if command == "restore" { session = false; protection = false; return "restored" }
   if command == "sleepOverrideOn" {
    guard session else { throw HelperError.rejected("no charge session") }
    protection = true
   }
   if command == "inhibitCharge" { session = true }
   if command == "forceDischarge" { precondition(session && protection) }
   // A lost acknowledgement may follow an applied operation.
   if command == failure && !failed { failed = true; throw HelperError.unavailable }
   return "accepted"
  }
  model.enableHardware(true,request:request,refresh:{})
  model.decision = Decision(.forceDischarge,"fixture",limit:80); model.decision.phase = .discharging
  let plan = SleepProtectionPlan.evaluate(controlEnabled:true,connected:true,physicalAdapterConnected:true,action:.forceDischarge,percent:90,target:80,calibrating:false,idleUntilTarget:false,systemUntilTarget:false,allowDisplaySleep:true,lidClosed:true)
  model.applyHardwareDecision(plan,request:request,setIdleSleep:{_ in})
  if failure.hasPrefix("suspend-") {
   precondition(model.config.hardwareEnabled && !model.needsDischargeExitWait)
   precondition(!accepted.contains("forceDischarge") && !accepted.contains("restore"))
   let alreadyBootstrapped = session; accepted = []
   model.applyHardwareDecision(plan,request:request,setIdleSleep:{_ in})
   precondition(accepted == (alreadyBootstrapped ? [] : ["inhibitCharge"]) + ["sleepOverrideOn","sleepPolicyOff","forceDischarge"])
  } else if failure != "none" {
   precondition(!model.config.hardwareEnabled && !session && !protection && accepted.last == "restore")
   if failure != "forceDischarge" { precondition(!accepted.contains("forceDischarge")) }
   continue
  } else {
   precondition(accepted == ["inhibitCharge","sleepOverrideOn","sleepPolicyOff","forceDischarge"])
  }
  precondition(session && protection && model.config.hardwareEnabled)
  accepted = []; model.applyHardwareDecision(plan,request:request,setIdleSleep:{_ in})
  precondition(accepted == ["sleepOverrideOn","sleepPolicyOff","forceDischarge"],"a healthy repeated round must not interrupt discharge with bootstrap inhibition")
 }
 print("Fresh ordinary protection bootstraps an owned inhibited session, protects before force, restores ambiguous failures, retries unexecuted suspensions, and avoids repeat bootstrap; injected operations only")
}

@MainActor func ordinarySleepNotificationChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(); let provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider }
 for action in [ChargeAction.allowCharge,.inhibitCharge,.forceDischarge] {
 for fails in [false,true] {
  var config = Configuration(); config.hardwareEnabled = false; config.historyEnabled = false
  config.notifications = false; config.systemActionsEnabled = false; try config.save()
  let model = ChargeModel(automaticRead: nil, dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no locks")},readBattery:{BatteryReading(percent:90,connected:true,charging:false)})
  model.inspectSleepInterfaces(request:{_ in "sleepOverride:interfacesDetected,sleepRecovery:phasesV1"})
  model.config.hardwareEnabled = true; model.config.policy.stopInSleep = false
  model.decision = Decision(action,"fixture",limit:80)
  let plan = SleepProtectionPlan.evaluate(controlEnabled:true,connected:true,physicalAdapterConnected:true,action:action,percent:50,target:80,calibrating:true,idleUntilTarget:false,systemUntilTarget:false,allowDisplaySleep:true)
  var actual = ChargeAction.restore; var protected = false
  model.applyHardwareDecision(plan,request:{command in
   if let value = ChargeAction(rawValue:command) { actual = value }
   if command == "sleepOverrideDisplayOn" { protected = true }
   return "fixture"
  },setIdleSleep:{_ in})
  precondition(actual == action && protected && model.config.hardwareEnabled)
  let before = try Data(contentsOf:Configuration.url); let previousPending = model.needsDischargeExitWait
  var commands: [String] = []
  model.sleep(request:{command in
   commands.append(command)
   if fails { throw HelperError.unavailable }
   precondition(command == "sleepOverrideRestore"); protected = false; return "released"
  })
  precondition(commands == ["sleepOverrideRestore"] && actual == action && model.needsDischargeExitWait == previousPending)
  precondition(model.config.hardwareEnabled && protected == fails)
  let after = try Data(contentsOf:Configuration.url); precondition(before == after)
  if fails {
   commands = []; model.sleep(request:{ commands.append($0); protected = false; return "released" })
   precondition(commands == ["sleepOverrideRestore"] && !protected)
  }
  model.config.policy.stopInSleep = true; commands = []
  model.sleep(request:{ command in commands.append(command); if command == "inhibitCharge" { actual = .inhibitCharge }; return "paused" })
  precondition(commands == ["inhibitCharge","sleepOverrideRestore"] && actual == .inhibitCharge)
  commands = []
  model.sleep(request:{ command in
   commands.append(command)
   if command == "inhibitCharge" { throw HelperError.unavailable }
   precondition(command == "sleepOverrideRestore"); return "released"
  })
  precondition(commands == ["inhibitCharge","sleepOverrideRestore"] && model.config.hardwareEnabled)
 }
 }
 print("Ordinary sleep opt-out releases protection without charge mutation, preserves policy and retries release failures; legacy notification stop opt-in still inhibits; all IPC injected")
}

@MainActor func manualAwakeChecks() {
 var now: TimeInterval = 0
 var modes: [Bool] = []
 var released: [UInt32] = []
 var rejectRelease = false
 let session = ManualAwakeSession(makeController: { display in
  modes.append(display)
  return SleepController(create: { 42 }, release: { id in
   if rejectRelease { throw CocoaError(.fileWriteUnknown) }
   released.append(id)
  })
 }, clock: { now })
 func start(_ duration: Int?, _ percent: Double = 60, _ connected: Bool = true, _ acOnly: Bool = false, _ display: Bool = false) {
  session.start(minutes: duration, percent: percent, connected: connected, floor: 20,
   endsOnBattery: acOnly, keepDisplayAwake: display)
 }
 func observe(_ percent: Double = 60, _ connected: Bool = true, _ acOnly: Bool = false) {
  session.observe(percent: percent, connected: connected, floor: 20, endsOnBattery: acOnly)
 }
 start(0); start(1441); start(30, 20); start(30, .nan); start(nil, 60, false, true)
 precondition(!session.active && modes.isEmpty)
 start(3); precondition(session.active && session.remainingMinutes == 3 && modes == [false])
 now = 65; observe(); precondition(session.remainingMinutes == 2)
 start(2); precondition(modes == [false])
 now = 185; observe(); precondition(!session.active && released == [42])
 start(nil, 60, true, true, true)
 precondition(session.active && session.remainingMinutes == nil && modes == [false, true])
 observe(60, false, true); precondition(!session.active && released.count == 2)
 start(nil, 60, false); observe(20, false); precondition(!session.active && released.count == 3)
 start(nil); session.reportReadFailure(CocoaError(.fileReadUnknown))
 precondition(!session.active && released.count == 4 && session.error != nil)
 start(nil); rejectRelease = true; session.stop()
 precondition(session.active && session.error != nil)
 start(30); precondition(session.remainingMinutes == nil)
 rejectRelease = false; observe()
 precondition(!session.active && session.error == nil && released.count == 5)
 precondition(DashboardLayout().widgets.contains(.manualAwake) && !PopoverLayout().widgets.contains(.manualAwake))
 print("PASS Keep Awake countdown, floor, AC-only stop, telemetry failure, display mode, and assertion-release retry")
}
