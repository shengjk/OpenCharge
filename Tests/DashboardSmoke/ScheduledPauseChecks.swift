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
 func fixture(mode: ChargeMode = .automatic, limit: Double = 80, hardwarePercent: Bool = false, checkpoint: CalibrationCheckpoint? = nil, tasks: [ChargeSchedule] = []) throws -> ChargeModel {
  var config = Configuration(); config.policy.mode = mode; config.policy.limit = limit
  config.policy.useHardwarePercent = hardwarePercent; config.calibrationCheckpoint = checkpoint
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
  config.schedules = tasks; try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false,
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
 sample = BatteryReading(percent: 78, temperature: 30, connected: true, charging: false)
 let targetThenPause = try fixture(tasks: [task(.limit, value: 100), task(.pause)])
 precondition(targetThenPause.config.policy.mode == .paused && targetThenPause.config.policy.limit == 78)
 for model in [startup, sailing, pending, ordinaryHeat, fullHeat, hardware, missing, ordered, reversed, calibration, restarted, targetThenPause] {
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
 }
 let saved = try Configuration.load(); precondition(saved.policy.mode == .paused && saved.policy.limit == 78)
 precondition(saved.policy.pauseAtCurrent == true && saved.calibrationCheckpoint == nil)
 print("Scheduled Pause uses live selected control percent and ordered projected policy states, consumes skipped tasks once and preserves interrupted calibration; isolated telemetry only, no actuators")
}
