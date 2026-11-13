import Foundation
import ChargeCore
import ChargeHardware

@MainActor func scheduledPauseChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider }
 var sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 func task(_ action: ScheduleAction, value: Double = 80, repeating: Bool = false) -> ChargeSchedule {
  var task = ChargeSchedule(); task.action = action; task.value = value
  task.date = Date().addingTimeInterval(-60); task.repeatRule = repeating ? .daily : .once
  return task
 }
 func fixture(mode: ChargeMode = .automatic, limit: Double = 80, sailing: Bool = true, hardwarePercent: Bool = false, checkpoint: CalibrationCheckpoint? = nil, departure: Date? = nil, tasks: [ChargeSchedule] = []) throws -> ChargeModel {
  var config = Configuration(); config.policy.mode = mode; config.policy.limit = limit; config.policy.sailing = sailing
  config.policy.useHardwarePercent = hardwarePercent; config.calibrationCheckpoint = checkpoint; config.policy.departure = departure
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
  config.schedules = tasks; try config.save()
  return ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false,
   screenLockRequest: { preconditionFailure("scheduled pause fixture must not lock") }, readBattery: { sample })
 }
 // A due task on the first refresh must use the live policy projection, not initial Pause.
 let startup = try fixture(tasks: [task(.pause)])
 precondition(startup.config.policy.mode == .paused && startup.config.policy.limit == 50 && startup.config.policy.pauseAtCurrent == true)
 precondition(startup.automationPhase == .pause && startup.config.schedules[0].enabled == false)
 precondition(startup.config.scheduleHistory?.last?.result.contains("未确认硬件停充") == true)
 sample = BatteryReading(percent: 49, temperature: 30, connected: true, charging: false)
 startup.refresh()
 precondition(startup.config.policy.mode == .automatic && startup.config.scheduleHistory?.count == 1)

 sample = BatteryReading(percent: 78, temperature: 30, connected: true, charging: false)
 let sailing = try fixture(tasks: [task(.pause, repeating: true)])
 precondition(sailing.config.policy.mode == .automatic && sailing.config.policy.limit == 80)
 precondition(sailing.config.scheduleHistory?.last?.result.contains("不适用") == true)
 precondition(sailing.config.schedules[0].date > Date())
 sailing.refresh(); precondition(sailing.config.scheduleHistory?.count == 1)

 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 for mode: ChargeMode in [.topUp, .discharge, .calibration] {
  let active = try fixture(mode: mode, tasks: [task(.pause)])
  precondition(active.config.policy.mode == .paused && active.config.policy.limit == 90)
  precondition(active.config.calibrationCheckpoint == nil && !active.calibrationPending && active.calibration == .idle)
 }
 let pending = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining), tasks: [task(.pause)])
 precondition(pending.calibrationPending && pending.config.policy.mode == .calibration && pending.config.calibrationCheckpoint?.stage == .draining)
 precondition(pending.config.scheduleHistory?.last?.result.contains("校准已中断") == true)
 let pendingDuplicate = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining),
  tasks: [task(.calibrate, repeating: true)])
 precondition(pendingDuplicate.calibrationPending && pendingDuplicate.config.calibrationCheckpoint?.stage == .draining)
 precondition(pendingDuplicate.config.scheduleHistory?.last?.result.contains("校准已中断") == true)
 precondition(pendingDuplicate.config.schedules[0].date > Date())
 let pendingExit = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining),
  tasks: [task(.automatic)])
 precondition(!pendingExit.calibrationPending && pendingExit.config.policy.mode == .automatic)
 precondition(pendingExit.config.calibrationCheckpoint == nil && pendingExit.calibration == .idle)

 sample = BatteryReading(percent: 90, temperature: 30, connected: false, charging: false)
 let offline = try fixture(tasks: [task(.calibrate)])
 precondition(offline.config.policy.mode == .calibration && offline.decision.action == .restore)
 precondition(offline.config.scheduleHistory?.last?.result.contains("等待接电") == true)
 let waitingAfterRestart = ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false, readBattery: { sample })
 precondition(waitingAfterRestart.config.policy.mode == .calibration && waitingAfterRestart.decision.action == .restore)
 precondition(!waitingAfterRestart.config.schedules[0].enabled && waitingAfterRestart.config.scheduleHistory?.count == 1)
 sample.connected = true
 waitingAfterRestart.refresh()
 precondition(waitingAfterRestart.calibration == .filling && waitingAfterRestart.config.scheduleHistory?.count == 1)

 sample = BatteryReading(percent: 50, temperature: 40, connected: true, charging: false)
 let ordinaryHeat = try fixture(tasks: [task(.pause)])
 precondition(ordinaryHeat.automationPhase == .heatProtect && ordinaryHeat.config.policy.limit == 80)
 precondition(ordinaryHeat.config.scheduleHistory?.last?.result.contains("不适用") == true)
 let fullHeat = try fixture(limit: 100, tasks: [task(.pause)])
 precondition(fullHeat.config.policy.mode == .paused && fullHeat.config.policy.limit == 50)

 sample = BatteryReading(percent: 80, temperature: 30, connected: true, charging: false, hardwarePercent: 49.75)
 let hardware = try fixture(hardwarePercent: true, tasks: [task(.pause)])
 precondition(hardware.config.policy.limit == 49.75 && hardware.config.policy.pauseAtCurrent == true)
 sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 let missing = try fixture(hardwarePercent: true, tasks: [task(.pause)])
 precondition(missing.config.policy.mode == .automatic && missing.config.policy.limit == 80 && missing.config.policy.pauseAtCurrent != true)
 precondition(missing.config.scheduleHistory?.last?.result.contains("控制电量不可读") == true && missing.config.schedules[0].enabled == false)
 precondition(missing.error != nil)

 // Every task receives the previous task's result, even within the first refresh.
 sample = BatteryReading(percent: 78, temperature: 30, connected: true, charging: false)
 let ordered = try fixture(tasks: [task(.topUp), task(.pause), task(.pause)])
 precondition(ordered.config.policy.mode == .paused && ordered.config.policy.limit == 78)
 precondition(ordered.config.scheduleHistory?.count == 3)
 precondition(ordered.config.scheduleHistory?[1].result.contains("已接受") == true && ordered.config.scheduleHistory?[2].result.contains("不适用") == true)
 let reversed = try fixture(tasks: [task(.pause), task(.topUp)])
 precondition(reversed.config.policy.mode == .topUp && reversed.config.policy.limit == 80)
 precondition(reversed.config.scheduleHistory?[0].result.contains("不适用") == true)
 let calibration = try fixture(tasks: [task(.calibrate), task(.pause)])
 precondition(calibration.config.policy.mode == .paused && calibration.config.calibrationCheckpoint == nil)
 let restarted = try fixture(mode: .calibration)
 sample = BatteryReading(percent: 100, temperature: 30, connected: true, charging: false)
 restarted.refresh(); precondition(restarted.calibration == .draining)
 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 restarted.config.schedules = [task(.pause), task(.calibrate)]; restarted.save(); restarted.refresh()
 precondition(restarted.calibration == .filling && restarted.config.calibrationCheckpoint?.stage == .filling, "accepted Pause must cancel the old run before a same-batch calibration starts")
 precondition(restarted.config.policy.pauseAtCurrent == nil, "new explicit mode must not inherit current-limit Pause")
 sample.percent = 100
 restarted.refresh(); precondition(restarted.calibration == .draining)
 sample.percent = 90
 restarted.config.schedules = [task(.calibrate)]
 restarted.refresh()
 precondition(restarted.calibration == .draining && restarted.config.scheduleHistory?.last?.result.contains("已有校准任务") == true)
 restarted.config.schedules = [task(.automatic), task(.calibrate)]
 restarted.refresh()
 precondition(restarted.calibration == .filling && restarted.config.calibrationCheckpoint?.stage == .filling,
  "Automatic must discard the old checkpoint before the same-round calibration starts")
 sample = BatteryReading(percent: 78, temperature: 30, connected: true, charging: false)
 let targetThenPause = try fixture(tasks: [task(.limit, value: 100), task(.pause)])
 precondition(targetThenPause.config.policy.mode == .paused && targetThenPause.config.policy.limit == 78)
 for model in [startup, sailing, pending, ordinaryHeat, fullHeat, hardware, missing, ordered, reversed, calibration, restarted, targetThenPause] {
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 let saved = try Configuration.load(); precondition(saved.policy.mode == .paused && saved.policy.limit == 78)
 precondition(saved.policy.pauseAtCurrent == true && saved.calibrationCheckpoint == nil)
 // Exercise the production scheduler, including persistence and completion,
 // rather than only applying an isolated ChargeSchedule to a policy value.
 sample = BatteryReading(percent:80,temperature:25,connected:true,charging:false)
 let dueDeparture = Date().addingTimeInterval(60)
 let scheduledDischarge = try fixture(departure:dueDeparture,tasks:[task(.discharge,value:40)])
 precondition(scheduledDischarge.config.policy.departure == nil && scheduledDischarge.config.policy.limit == 40)
 precondition(scheduledDischarge.config.policy.mode == .discharge && scheduledDischarge.decision.action == .forceDischarge && scheduledDischarge.decision.effectiveLimit == 40)
 precondition(!scheduledDischarge.config.schedules[0].enabled && scheduledDischarge.config.scheduleHistory?.count == 1)
 let acceptedDischarge = try Configuration.load()
 precondition(acceptedDischarge.policy.mode == .discharge && acceptedDischarge.policy.limit == 40 && acceptedDischarge.policy.departure == nil && !acceptedDischarge.hardwareEnabled)
 sample.percent = 40;scheduledDischarge.refresh()
 precondition(scheduledDischarge.config.policy.mode == .automatic && scheduledDischarge.decision.action == .inhibitCharge)
 sample.percent = 39.5;scheduledDischarge.refresh()
 precondition(scheduledDischarge.decision.action == .inhibitCharge && scheduledDischarge.automationPhase == .sailing)
 precondition(scheduledDischarge.config.scheduleHistory?.count == 1,"completed one-shot discharge must not run again")
 // A restarted model must retain the completed task and Sailing hold.
 let afterRestart = ChargeModel(automaticRead: nil, dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no locks")},readBattery:{sample})
 precondition(afterRestart.config.policy.mode == .automatic && afterRestart.decision.action == .inhibitCharge && afterRestart.automationPhase == .sailing)
 precondition(afterRestart.config.scheduleHistory?.count == 1 && !afterRestart.config.schedules[0].enabled)
 // The selected raw control percentage, not the displayed OS value, ends discharge.
 sample = BatteryReading(percent:90,temperature:25,connected:true,charging:false,hardwarePercent:70)
 let rawDischarge = try fixture(hardwarePercent:true,departure:dueDeparture,tasks:[task(.discharge,value:40,repeating:true)])
 precondition(rawDischarge.decision.action == .forceDischarge && rawDischarge.config.policy.mode == .discharge)
 sample.hardwarePercent = 40;rawDischarge.refresh()
 precondition(rawDischarge.decision.action == .inhibitCharge && rawDischarge.config.policy.mode == .automatic)
 precondition(rawDischarge.config.schedules[0].date > Date() && rawDischarge.config.scheduleHistory?.count == 1)
 rawDischarge.refresh();precondition(rawDischarge.config.scheduleHistory?.count == 1 && rawDischarge.config.policy.mode == .automatic)
 // A due discharge already at/below target must not request input cutoff.
 // Preserve the ordinary Sailing band instead of imposing newer schedule semantics.
 sample = BatteryReading(percent:78,temperature:25,connected:true,charging:false)
 let higherTarget = try fixture(limit:60,tasks:[task(.discharge,value:80)])
 precondition(higherTarget.config.policy.mode == .automatic && higherTarget.config.policy.limit == 80)
 precondition(higherTarget.decision.action == .inhibitCharge && higherTarget.automationPhase == .sailing)
 higherTarget.refresh()
 precondition(higherTarget.decision.action == .inhibitCharge && higherTarget.automationPhase == .sailing)
 let higherTargetRestart = ChargeModel(automaticRead: nil, dashboardDefaults:defaults,observeLid:false,
  screenLockRequest:{preconditionFailure("no locks")},readBattery:{sample})
 precondition(higherTargetRestart.config.policy.mode == .automatic && higherTargetRestart.decision.action == .inhibitCharge)
 precondition(higherTargetRestart.config.scheduleHistory?.count == 1 && !higherTargetRestart.config.schedules[0].enabled)
 sample.percent = 75;higherTargetRestart.refresh()
 precondition(higherTargetRestart.decision.action == .allowCharge && higherTargetRestart.automationPhase == .charging)
 // Without Sailing, completion returns to ordinary charging on the next refresh.
 sample.percent = 78
 let higherTargetNoSailing = try fixture(limit:60,sailing:false,tasks:[task(.discharge,value:80)])
 precondition(higherTargetNoSailing.config.policy.mode == .automatic && higherTargetNoSailing.decision.action == .inhibitCharge)
 higherTargetNoSailing.refresh()
 precondition(higherTargetNoSailing.decision.action == .allowCharge && higherTargetNoSailing.automationPhase == .charging)
 // Equal whole-percent target completes, even with a fractional telemetry value.
 sample.percent = 80.75
 let equalTarget = try fixture(tasks:[task(.discharge,value:80)])
 precondition(equalTarget.config.policy.mode == .automatic && equalTarget.decision.action == .inhibitCharge)
 equalTarget.refresh();precondition(equalTarget.decision.action == .inhibitCharge && equalTarget.config.scheduleHistory?.count == 1)
 // A higher target is measured against the selected control percentage.
 sample = BatteryReading(percent:90,temperature:25,connected:true,charging:false,hardwarePercent:70)
 let rawHigherTarget = try fixture(limit:60,hardwarePercent:true,tasks:[task(.discharge,value:80,repeating:true)])
 precondition(rawHigherTarget.config.policy.mode == .automatic && rawHigherTarget.decision.action == .inhibitCharge)
 rawHigherTarget.refresh();precondition(rawHigherTarget.decision.action == .allowCharge)
 precondition(rawHigherTarget.config.schedules[0].date > Date() && rawHigherTarget.config.scheduleHistory?.count == 1)
 for model in [higherTarget,higherTargetRestart,higherTargetNoSailing,equalTarget,rawHigherTarget] {
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 print("PASS production scheduled discharge already at/below target: Sailing hold/restart/lower-bound release, non-Sailing resume, whole-percent equality, selected raw percentage and one-shot/repeating history; fake telemetry only")
 // Same-round tasks still run in order: a following Pause uses the live level.
 sample = BatteryReading(percent:80,temperature:25,connected:true,charging:false)
 let dischargeThenPause = try fixture(departure:dueDeparture,tasks:[task(.discharge,value:40),task(.pause)])
 precondition(dischargeThenPause.config.policy.mode == .paused && dischargeThenPause.config.policy.limit == 80 && dischargeThenPause.config.policy.departure == nil)
 precondition(dischargeThenPause.config.scheduleHistory?.count == 2 && dischargeThenPause.decision.action == .inhibitCharge)
 for model in [scheduledDischarge,afterRestart,rawDischarge,dischargeThenPause] {
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 print("PASS production scheduled discharge: due departure removal, shared target, one-shot persistence, completion/Sailing/restart, raw percentage, repeating-task advance and same-batch Pause; isolated fake telemetry, no hardware actions")
 print("Scheduled Pause uses live selected control percent and ordered projected policy states, consumes skipped tasks once and preserves interrupted calibration; isolated telemetry only, no actuators")
}
