import Foundation
import ChargeCore
import ChargeHardware

@MainActor func settingsLockChecks(defaults: UserDefaults) async throws {
 let original = try Configuration.load(); let provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider; defaults.removeObject(forKey: "settingsLock") }
 defaults.removeObject(forKey: "settingsLock")
 var config = Configuration(); config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
 try config.save()
 var reads = 0
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("no lock requests") }, readBattery: {
  reads += 1; return BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 })
 precondition(!model.settingsLocked)
 let sailing = model.chargeSetting(\.sailing)
 defaults.set(true, forKey: "settingsLock")
 for _ in 0..<20 where !model.settingsLocked { await Task.yield() }
 precondition(model.settingsLocked, "default changes must reach the observed UI state without a policy refresh")
 // Use a binding created while unlocked: its setter must read the current preference.
 let before = model.config.policy; let limitID = model.config.chargeLimitChangeID
 let disk = try Data(contentsOf: Configuration.url); let initialReads = reads
 sailing.wrappedValue = false
 model.chargeSetting(\.sailingWidth).wrappedValue = 17
 model.chargeSetting(\.heatProtection).wrappedValue = false
 model.chargeSetting(\.maxTemperature).wrappedValue = 44
 model.chargeSetting(\.automaticDischarge).wrappedValue = true
 model.chargeSetting(\.useHardwarePercent).wrappedValue = true
 model.chargeSetting(\.stopInSleep).wrappedValue = true
 model.chargeSetting(\.stopOnQuit).wrappedValue = true
 model.chargeSetting(\.keepAwakeUntilLimit).wrappedValue = true
 model.chargeSetting(\.keepAwakeWithLidClosed).wrappedValue = true
 model.chargeSetting(\.allowDisplaySleep).wrappedValue = false
 model.chargeSetting(\.lockScreenWhenClosed).wrappedValue = true
 model.chargeSetting(\.thermalBehavior).wrappedValue = .degreeHysteresis
 model.chargeSetting(\.protectDuringTopUp).wrappedValue = true
 model.chargeSetting(\.protectDuringCalibration).wrappedValue = true
 model.chargeSetting(\.reserve).wrappedValue = 40
 model.chargeSetting(\.departure).wrappedValue = Date().addingTimeInterval(3600)
 model.chargeSetting(\.departureTarget).wrappedValue = 95
 model.chargeSetting(\.estimatedPercentPerHour).wrappedValue = 20
 model.editChargeSettings { preconditionFailure("locked custom editor must not execute") }
 model.setChargeLimitFromGUI(65)
 model.applyChargeSettingsFromGUI(presentLowLimitNotice:{})
 model.profileFromGUI(70, 10, 40)
 model.toggleChargingFromMenu()
 precondition(model.settingsLocked && model.error != nil && reads == initialReads)
 precondition(model.config.policy == before && model.config.chargeLimitChangeID == limitID)
 let unchanged = try Data(contentsOf: Configuration.url); precondition(unchanged == disk)
 // A normal background save and scheduled occurrence remain usable while locked.
 var task = ChargeSchedule(); task.action = .limit; task.value = 70; task.date = Date().addingTimeInterval(-60)
 model.config.schedules = [task]; model.save(); model.refresh()
 precondition(model.settingsLocked && model.config.policy.limit == 70 && !model.config.schedules[0].enabled)
 let scheduled = try Configuration.load(); precondition(scheduled.policy.limit == 70 && scheduled.scheduleHistory?.count == 1)
 model.toggleTopUp(); precondition(model.config.policy.mode == .topUp && model.config.policy.limit == 70)
 model.toggleTopUp(); precondition(model.config.policy.mode == .paused)
 model.controlModeSelection.wrappedValue = .automatic
 precondition(model.config.policy.mode == .automatic)
 model.config.systemActionsEnabled = true; var commands: [String] = []
 model.toggleLowPowerFromMenu(request: { command in commands.append(command); return command == "lowPowerStatus" ? "battery=0 ac=0" : "battery=1 ac=1" }, isActive: { false })
 precondition(commands == ["lowPowerStatus", "lowPowerOn"] && model.config.policy.lowPowerMode == true)
 // Automation keeps its separate entry point; this preference is a GUI restriction.
 model.handleURL(URL(string: "opencharge://limit?value=75")!)
 precondition(model.config.policy.limit == 75 && model.settingsLocked)
 defaults.removeObject(forKey: "settingsLock")
 model.reloadSettingsLock(); precondition(!model.settingsLocked)
 sailing.wrappedValue = false
 model.setChargeLimitFromGUI(65); model.applyChargeSettingsFromGUI(presentLowLimitNotice:{})
 let unlocked = try Configuration.load(); precondition(!unlocked.policy.sailing && unlocked.policy.limit == 65)
 precondition(defaults.object(forKey: "settingsLock") == nil && !model.config.hardwareEnabled)
 print("Administrator charging-settings preference blocks fresh and stale GUI edits/right-click without touching backend saves, schedules, modes, injected LPM or URL automation; isolated defaults/configuration only")
}
