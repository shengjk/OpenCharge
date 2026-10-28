import Foundation
import ChargeCore
import ChargeHardware

private final class ResetManagedDefaults: UserDefaults {
 var forced = Set<String>()
 override func objectIsForced(forKey key: String) -> Bool { forced.contains(key) }
}

@MainActor func settingsResetChecks() async throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 func canonical<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
 }
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.reset-fixture."+UUID().uuidString
 let defaults = ResetManagedDefaults(suiteName:suite)!
 let historyURL = Configuration.directory.appendingPathComponent("history.json")
 let priorHistory = try? Data(contentsOf:historyURL)
 defer {
  try? original.save(); PolicyStateRuntime.provider = provider
  defaults.removePersistentDomain(forName:suite)
  if let priorHistory { try? priorHistory.write(to:historyURL) } else { try? FileManager.default.removeItem(at:historyURL) }
 }
 let point = HistoryPoint(date:Date(timeIntervalSince1970:12345),percent:50,temperature:30,watts:1,reason:"reset fixture")
 let historyBytes = try canonical([point]); try historyBytes.write(to:historyURL)
 func clean() throws {
  defaults.removePersistentDomain(forName:suite); defaults.forced = []
  var c = Configuration(); c.historyEnabled = false; try c.save()
 }
 func model() -> ChargeModel {
  ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no lock")},readBattery:{BatteryReading(percent:90,connected:true,charging:false)})
 }
 func custom(_ m: ChargeModel) {
  m.config.policy.limit = 65; m.config.policy.mode = .calibration
  m.config.calibrationCheckpoint = CalibrationCheckpoint(stage:.holding,holdingSince:Date(timeIntervalSince1970:456))
  m.calibration = .holding; m.calibrationPending = true
  m.config.sailingCheckpoint = true; m.config.chargeLimitChangeID = UUID()
  m.config.lastCalibration = Date(timeIntervalSince1970:789)
  var task = ChargeSchedule(); task.date = Date().addingTimeInterval(3600); m.config.schedules = [task]
  m.config.scheduleHistory = [ScheduleExecution(scheduleID:task.id,action:.limit,scheduledAt:Date(timeIntervalSince1970:400),result:"fixture")]
  m.dashboardPreferences.layout = DashboardLayout(widgets:[.battery],specifications:[.voltage])
  m.dashboardPreferences.showOnStartup = false; m.dashboardPreferences.backgroundUpdates = true
  m.popoverPreferences.layout = PopoverLayout(widgets:[.specifications],specifications:[.current])
  m.popoverPreferences.animationsEnabled = false; m.popoverPreferences.showPercentage = false
  m.popoverPreferences.setEditing(true,consumer:.statusItem); m.popoverPreferences.dragging = true
  m.menuBarActions.rightClick = .toggleCharging
  defaults.set("dark",forKey:"appearance"); defaults.set(false,forKey:"showDockIcon")
  defaults.set("percentage",forKey:"menuDisplay"); defaults.set("unknown preserved",forKey:"thirdPartyKey")
  defaults.set(false,forKey:"updatesPreviews"); defaults.set(123.0,forKey:"updatesLastAttempt")
  m.updates.includePreviews = false
 }
 func rejects(_ body: () throws -> Void) {
  do { try body(); preconditionFailure("reset should reject fixture failure") } catch {}
 }
 var scenarios = 0
 for profile in ["ordinary","CH0B+BCLM","BCLM"] {
  for failure in ["none","stop-save","restore","magSafeRestore","sleepOverrideRestore","idle","defaults-save"] {
   try clean(); let m = model()
   let caps = profile == "ordinary" ? "chargeControl:fixture,sleepOverride:interfacesDetected,sleepRecovery:phasesV1" : "firmwareProtocol:fixedV1,firmwareRead:\(profile),firmwareWrite:fixedV1,chargeRecovery:ready,internalBattery:present,firmwarePlan:atomicSleepV1,firmwareDischarge:inflowV1,sleepOverride:interfacesDetected,sleepRecovery:phasesV1"
   var events: [String] = [], failing = "none"
   func request(_ command: String) throws -> String {
    events.append(command)
    if command == failing { throw HelperError.unavailable }
    if command == "capabilities" { return caps }
    if command == "firmwareSessionStatus" { return "session=active,limit=15,charging=inhibited" }
    return "fixture"
   }
   m.enableHardware(true,request:request,refresh:{})
   precondition(m.config.hardwareEnabled)
   m.config.magSafeMode = .off; m.updateMagSafe(request:request)
   m.decision = Decision(.forceDischarge,"fixture",limit:80); m.decision.phase = .discharging
   let plan = SleepProtectionPlan.evaluate(controlEnabled:true,connected:true,physicalAdapterConnected:true,action:.forceDischarge,percent:90,target:80,calibrating:false,idleUntilTarget:false,systemUntilTarget:false,allowDisplaySleep:true,lidClosed:true)
   m.applyHardwareDecision(plan,request:request,setIdleSleep:{_ in})
   precondition(m.config.hardwareEnabled)
   custom(m); try m.config.save()
   let oldPolicy = m.config.policy, oldSchedules = try canonical(m.config.schedules)
   let oldHistory = try canonical(m.config.scheduleHistory), oldLayout = m.dashboardPreferences.layout
   events = []; failing = failure
   var saves = 0, docks: [Bool] = []
   func persist(_ c: Configuration) throws {
    saves += 1; events.append(saves == 1 ? "stop-save" : "defaults-save")
    precondition(!c.hardwareEnabled && c.systemActionsEnabled == false)
    if (failure == "stop-save" && saves == 1) || (failure == "defaults-save" && saves == 2) { throw CocoaError(.fileWriteNoPermission) }
    try c.save()
   }
   func reset() throws {
    try m.resetSettings(request:request,releaseIdle:{events.append("idle"); if failure == "idle" { throw HelperError.unavailable }},persist:persist,applyDock:{docks.append($0)})
   }
   if failure == "none" {
    try reset()
    precondition(events == ["stop-save","restore","magSafeRestore","sleepOverrideRestore","idle","defaults-save"])
   } else {
    rejects { try reset() }
    if failure == "stop-save" { precondition(events == ["stop-save"]) }
    else {
     precondition(Array(events.prefix(5)) == ["stop-save","restore","magSafeRestore","sleepOverrideRestore","idle"],"independent cleanup must continue after a failure")
     precondition(events.contains("defaults-save") == (failure == "defaults-save"))
    }
    precondition(m.settingsResetPending && m.settingsResetStatus == nil && !m.config.hardwareEnabled && m.config.systemActionsEnabled == false)
    precondition(m.config.policy == oldPolicy && m.dashboardPreferences.layout == oldLayout && defaults.string(forKey:"appearance") == "dark" && docks.isEmpty)
    let stillScheduled = try canonical(m.config.schedules); precondition(stillScheduled == oldSchedules)
    let prior = events
    m.restoreConfiguration() // A pending reset must reject before opening a file picker.
    let untouched = try canonical(m.config.schedules); precondition(untouched == oldSchedules && m.settingsResetPending)
    m.refresh(); m.updateMagSafe(request:request); m.enableHardware(true,request:request,refresh:{})
    m.toggleLowPowerFromMenu(request:request,isActive:{false})
    precondition(events == prior && !m.config.hardwareEnabled,"failed reset must not rearm sessions on refresh or shortcuts")
    failing = "none"; saves = 0
    try m.resetSettings(request:request,releaseIdle:{events.append("retry-idle")},persist:{c in precondition(!c.hardwareEnabled); try c.save()},applyDock:{docks.append($0)})
   }
   precondition(events.first == "stop-save", "stop actuation must persist before any cleanup")
   if failure == "stop-save" { precondition(events.dropFirst().first == "restore","no cleanup before failed stop save; retry restores") }
   precondition(!m.settingsResetPending && m.settingsResetStatus != nil && m.error == nil && !m.config.hardwareEnabled && m.config.policy == ChargePolicy())
   precondition(m.config.schedules.isEmpty && m.config.calibrationCheckpoint == nil && m.calibration == .idle && !m.calibrationPending && !m.usesNumericFirmware)
   precondition(m.config.lastCalibration == Date(timeIntervalSince1970:789))
   let kept = try canonical(m.config.scheduleHistory); precondition(kept == oldHistory)
   precondition(m.history.count == 1 && m.history[0].date == point.date)
   let diskHistory = try Data(contentsOf:historyURL); precondition(diskHistory == historyBytes)
   precondition(m.dashboardPreferences.showOnStartup && !m.dashboardPreferences.backgroundUpdates && m.dashboardPreferences.layout == DashboardLayout())
   precondition(m.popoverPreferences.animationsEnabled && m.popoverPreferences.showPercentage && m.popoverPreferences.layout == PopoverLayout() && !m.popoverPreferences.isEditing(.statusItem) && !m.popoverPreferences.dragging)
   precondition(m.menuBarActions.rightClick == .popover && !m.updates.automaticChecks && m.updates.includePreviews)
   precondition(defaults.string(forKey:"thirdPartyKey") == "unknown preserved" && defaults.object(forKey:"appearance") == nil && docks == [true])
   let saved = try Configuration.load(); precondition(!saved.hardwareEnabled && saved.schedules.isEmpty && saved.policy == ChargePolicy())
   let after = events; m.updateMagSafe(request:request); precondition(events == after)
   scenarios += 1
  }
 }
 // The real confirmation factory defaults to Cancel, and cancelling does not begin reset.
 try clean(); let cancelled = model(); custom(cancelled)
 let alert = SettingsResetConfirmation.makeAlert()
 precondition(alert.buttons.count == 2 && alert.buttons[0].title == NSLocalizedString("取消",comment:"") && alert.buttons[1].title == NSLocalizedString("恢复默认设置",comment:""))
 let beforeCancel = try Data(contentsOf:Configuration.url)
 cancelled.confirmSettingsReset(confirm:{false})
 let afterCancel = try Data(contentsOf:Configuration.url)
 precondition(beforeCancel == afterCancel && !cancelled.settingsResetPending && cancelled.config.policy.limit == 65 && defaults.string(forKey:"appearance") == "dark")
 // A lock arriving while the modal confirmation is visible must be checked after it returns.
 cancelled.confirmSettingsReset(confirm:{defaults.set(true,forKey:"settingsLock"); return true})
 precondition(!cancelled.settingsResetPending && cancelled.error != nil && cancelled.config.policy.limit == 65)
 // Monitoring-only reset needs no installed service or IPC, and stale confirmation must honor the lock.
 try clean(); let m = model(); custom(m)
 defaults.set(true,forKey:"settingsLock")
 rejects { try m.resetSettings(request:{_ in preconditionFailure("locked reset IPC")},persist:{_ in preconditionFailure("locked reset persistence")},applyDock:{_ in preconditionFailure("locked dock")}) }
 precondition(!m.settingsResetPending && m.config.policy.limit == 65 && defaults.bool(forKey:"settingsLock"))
 defaults.removeObject(forKey:"settingsLock")
 defaults.set("light",forKey:"appearance"); defaults.forced = ["appearance"]
 try m.resetSettings(request:{_ in preconditionFailure("monitoring reset must not require service")},releaseIdle:{},applyDock:{_ in})
 precondition(defaults.string(forKey:"appearance") == "light" && defaults.string(forKey:"thirdPartyKey") == "unknown preserved")
 // An ambiguous retained-exit request can leave recovery while both the
 // configuration and last acknowledged ordinary action look like monitoring.
 try clean(); let retained = model()
 retained.config.hardwareEnabled = true; retained.config.policy.stopOnQuit = true
 rejects { try retained.prepareForQuit(request:{ _ in throw HelperError.unavailable }) }
 retained.cancelQuit(request:{ _ in throw HelperError.unavailable })
 precondition(!retained.config.hardwareEnabled && retained.needsQuitPreparation)
 var retainedCalls: [String] = []
 try retained.resetSettings(request:{ retainedCalls.append($0); return "fixture recovered" },releaseIdle:{},applyDock:{_ in})
 precondition(retainedCalls == ["restore"] && !retained.needsQuitPreparation)
 // Busy update work is an independent reset gate, with an entirely injected response.
 try clean()
 let updates = AppUpdates(defaults:defaults,currentVersion:"0.3.40")
 let busyModel = ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{BatteryReading(percent:50,connected:true,charging:false)},appUpdates:updates)
 var continuation: CheckedContinuation<[Data],Error>?
 let job = Task { await updates.check(loadPages:{try await withCheckedThrowingContinuation { continuation = $0 }}) }
 while continuation == nil { await Task.yield() }
 precondition(updates.busy)
 rejects { try busyModel.resetSettings(request:{_ in preconditionFailure("busy reset IPC")},persist:{_ in preconditionFailure("busy reset persistence")}) }
 precondition(!busyModel.settingsResetPending)
 continuation?.resume(returning:[]); await job.value
 print("PASS settings reset: \(scenarios) ordinary/paired/BCLM cleanup and persistence outcomes, retries, retained history, live preferences, managed/unknown keys, stale lock, monitoring without service and busy update; isolated files and injected actuators only")
}
