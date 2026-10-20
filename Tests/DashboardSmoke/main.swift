import Foundation
import ChargeCore
import ChargeHardware

@main struct DashboardSmoke {
 @MainActor static func main() async throws {
  try menuBarAppearanceChecks()
  try updateChecks()
  let labelReading = BatteryReading(percent: 80.9, connected: true, charging: false, hardwarePercent: 77.4)
  let statusLabel = MenuBarLabel(display: "status", reading: labelReading)
  precondition(statusLabel.text == "80%" && statusLabel.symbol == "pause.circle")
  let percentageLabel = MenuBarLabel(display: "percentage", reading: labelReading)
  precondition(percentageLabel.text == "80%" && percentageLabel.symbol == nil)
  let hardwareLabel = MenuBarLabel(display: "hardware", reading: labelReading)
  precondition(hardwareLabel.text == "77%" && hardwareLabel.symbol == nil)
  let iconLabel = MenuBarLabel(display: "icon", reading: labelReading)
  precondition(iconLabel.text.isEmpty && iconLabel.symbol == "pause.circle" && iconLabel.accessibilityText.contains("80%"))
  let chargingLabel = MenuBarLabel(display: "status", reading: BatteryReading(percent: 80, connected: true, charging: true))
  precondition(chargingLabel.symbol == "battery.100percent.bolt")
  precondition(MenuBarLabel(display: "hardware", reading: BatteryReading(percent: 80, connected: false, charging: false)).text == "—")
  precondition(MenuBarLabel(display: "unknown", reading: labelReading).text == "80%")
  precondition(MenuBarLabel(display: "percentage", reading: nil).text == "—")
  precondition(MenuBarLabel(display: "hardware", reading: BatteryReading(percent: 80, connected: true, charging: false, hardwarePercent: .nan)).text == "—")
  let point = HistoryPoint(date: Date(), percent: 80, temperature: 33.5, watts: 0, reason: "fixture", temperatureSource: .smc)
  let encodedPoint = try JSONEncoder().encode(point)
  let newPoint = try JSONDecoder().decode(HistoryPoint.self, from: encodedPoint)
  precondition(newPoint.temperatureSource == .smc)
  var oldObject = try JSONSerialization.jsonObject(with: encodedPoint) as! [String: Any]
  oldObject.removeValue(forKey: "temperatureSource")
  let oldPoint = try JSONDecoder().decode(HistoryPoint.self, from: JSONSerialization.data(withJSONObject: oldObject))
  precondition(oldPoint.temperature == 33.5 && oldPoint.temperatureSource == nil, "legacy history must not invent a source")
  let suite = "org.opencharge.dashboard-test." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(false, forKey: "dashboardBackgroundUpdates")
  let preferences = DashboardPreferences(defaults: defaults)
  preferences.showOnStartup = false
  preferences.layout = DashboardLayout(widgets: [.battery, .specifications], specifications: [.voltage, .current])
  let popup = PopoverPreferences(defaults: defaults)
  popup.showPercentage = false; popup.layout = PopoverLayout(widgets: [.specifications], specifications: [.current])
  let popupReload = PopoverPreferences(defaults: defaults)
  precondition(!popupReload.showPercentage && popupReload.layout == popup.layout)
  popup.setEditing(true, consumer: .preview)
  popup.setEditing(true, consumer: .statusItem)
  popup.setEditing(false, consumer: .statusItem)
  precondition(popup.isEditing(.preview) && !popup.isEditing(.statusItem), "closing real editor must preserve preview editing")
  precondition(!popupReload.isEditing(.preview), "editing sessions must not survive relaunch")
  let reload = DashboardPreferences(defaults: defaults)
  precondition(!reload.showOnStartup && reload.layout == preferences.layout)
  defaults.set(Data("{invalid".utf8), forKey: "dashboardLayout")
  precondition(DashboardPreferences(defaults: defaults).layout == DashboardLayout())
  preferences.layout = DashboardLayout(widgets: [.battery, .specifications], specifications: [.voltage, .current])
  var config = Configuration(); config.policy.limit = 80; config.historyEnabled = false
  try config.save()
  try await automationReloadChecks(defaults: defaults)
  try sleepOrderingChecks(defaults: defaults)
  try lidDischargeChecks(defaults: defaults)
  let model = ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("fixture must never invoke an uninjected lock") })
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
  precondition(model.reading != nil && model.dashboard.paused)
  model.inspectSleepInterfaces(request: { _ in "chargeControl:fixture" })
  let unavailableSleepStatus = model.sleepStatus
  model.refresh(); precondition(model.sleepStatus == unavailableSleepStatus && model.sleepStatus.contains("未提供"), "read-only capability result must survive monitoring refresh")
  let requiredPlan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true, action: .allowCharge, percent: 50, target: 100, calibrating: true, idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true)
  model.config.hardwareEnabled = true; model.config.policy.mode = .calibration
  var unsupportedCommands: [String] = []
  model.applyHardwareDecision(requiredPlan, request: { unsupportedCommands.append($0); return "fixture" })
  precondition(unsupportedCommands.isEmpty && !model.config.hardwareEnabled && model.calibrationPending, "missing required sleep capability must stop before any charge command")
  model.config.policy.mode = .automatic; model.calibrationPending = false
  model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  let detectedSleepStatus = model.sleepStatus
  model.refresh(); precondition(model.sleepStatus == detectedSleepStatus && model.sleepStatus.contains("仍待"))
  precondition(!model.config.hardwareEnabled && model.config.policy.keepAwakeWithLidClosed != true)
  let sleepPlan = SleepProtectionPlan.evaluate(controlEnabled: true, connected: true, physicalAdapterConnected: true, action: .allowCharge, percent: 50, target: 80, calibrating: false, idleUntilTarget: false, systemUntilTarget: true, allowDisplaySleep: true)
  var lockRequests = 0
  model.inspectLidLock(request: {}); precondition(model.lidLockStatus.contains("未请求"))
  model.handleLidState(true, consoleActive: true, request: { lockRequests += 1 })
  precondition(lockRequests == 0)
  model.config.hardwareEnabled = true; model.config.policy.keepAwakeWithLidClosed = true; model.config.policy.lockScreenWhenClosed = true
  model.handleLidState(true, consoleActive: true, request: { lockRequests += 1 }); precondition(lockRequests == 0, "no acknowledged sleep session must not lock")
  model.config.policy.stopInSleep = true
  var protectedCommands: [String] = []
  model.decision = Decision(.allowCharge, "fixture", limit: 80)
  model.applyHardwareDecision(sleepPlan, request: { protectedCommands.append($0); return "fixture acknowledgement" })
  precondition(protectedCommands == ["sleepOverrideOn", "sleepPolicyOff", "allowCharge"], "required full protection must succeed before suppressing sleep-entry policy and charging")
  model.config.policy.stopInSleep = false
  model.updateSleepOverride(sleepPlan, request: { _ in "fixture acknowledgement" })
  model.handleLidState(true, consoleActive: false, request: { lockRequests += 1 }); precondition(lockRequests == 0)
  model.handleLidState(true, consoleActive: true, request: { lockRequests += 1 }); precondition(lockRequests == 1 && model.lidLockStatus.contains("尚未确认"))
  for _ in 0..<1000 { model.handleLidState(true, consoleActive: true, request: { lockRequests += 1 }) }
  precondition(lockRequests == 1)
  model.handleLidState(false, consoleActive: true, request: { lockRequests += 1 })
  model.handleLidState(true, consoleActive: true, request: { throw CocoaError(.fileReadUnknown) })
  precondition(model.lidLockStatus.contains("失败"))
  model.inspectLidLock(request: {})
  model.handleLidState(true, consoleActive: true, request: { lockRequests += 1 }); precondition(lockRequests == 1, "inspection must not rearm locking")
  model.updateSleepOverride(SleepProtectionPlan.evaluate(controlEnabled: false, connected: true, physicalAdapterConnected: true, action: .restore, percent: 50, target: 80, calibrating: false, idleUntilTarget: false, systemUntilTarget: false, allowDisplaySleep: true), request: { _ in "fixture release" })
  model.config.hardwareEnabled = false; model.config.policy.keepAwakeWithLidClosed = false; model.config.policy.lockScreenWhenClosed = false
  print("Lid-lock opt-in/session/console gating, duplicate suppression and read-only inspection checked with injected calls; no real lock")
  var sleepAttempts = 0
  model.config.hardwareEnabled = true
  model.updateSleepOverride(sleepPlan, request: { _ in sleepAttempts += 1; throw CocoaError(.fileReadUnknown) })
  precondition(sleepAttempts == 2 && !model.config.hardwareEnabled && model.sleepStatus.contains("控制失败"))
  model.inspectSleepInterfaces(request: { _ in "sleepOverride:interfacesDetected, sleepRecovery:phasesV1" })
  model.config.hardwareEnabled = true
  model.updateSleepOverride(sleepPlan, request: { _ in sleepAttempts += 1; return "fixture only" })
  precondition(sleepAttempts == 2 && model.sleepStatus.contains("上次控制失败"), "read-only inspection must not resume failed writes")
  model.config.hardwareEnabled = false
  model.updateSleepOverride(sleepPlan, request: { command in precondition(command == "sleepOverrideRestore"); return "fixture pending recovery released" })
  print("Required sleep preflight, projection/persistence, rollback and read-only retry boundary checked with injected responses; no helper requests")
  var quitCommands: [String] = []
  model.config.hardwareEnabled = true
  try model.prepareForQuit(request: { quitCommands.append($0); return "fixture restored" })
  precondition(quitCommands == ["restore"])
  let quitReading = model.reading!.date
  model.refresh(); precondition(model.reading!.date == quitReading, "quit preparation must stop policy refreshes")
  model.cancelQuit(); precondition(!model.config.hardwareEnabled && model.reading!.date > quitReading)
  model.config.hardwareEnabled = true; model.config.policy.stopOnQuit = true
  try model.prepareForQuit(request: { quitCommands.append($0); return "fixture retained" })
  precondition(quitCommands.last == "retainChargeInhibit")
  model.cancelQuit(); model.config.policy.stopOnQuit = false; model.error = nil
  print("Quit preparation policy/suspension/cancel checks passed; injected helper only")
  model.setDashboardFocused(true)
  precondition(!model.dashboard.paused && model.dashboard.limit == 80)
  model.setDashboardFocused(false)
  let snapshotDate = model.dashboard.reading!.date
  var task = ChargeSchedule(); task.date = Date().addingTimeInterval(-60); task.action = .limit; task.value = 65
  model.config.schedules = [task]
  model.refresh()
  precondition(model.config.policy.limit == 65, "scheduling must continue while dashboard pauses")
  precondition(model.reading!.date > snapshotDate, "control telemetry must continue")
  precondition(model.dashboard.reading!.date == snapshotDate && model.dashboard.limit == 80, "paused display must freeze")
  model.setDashboardFocused(true)
  precondition(model.dashboard.limit == 65 && model.dashboard.reading!.date == model.reading!.date)
  model.dashboardPreferences.backgroundUpdates = true
  model.setDashboardFocused(false)
  precondition(!model.dashboard.paused)
  model.config.policy.limit = 70; model.refresh()
  precondition(model.dashboard.limit == 70)
  precondition(model.energyMonitor.paused, "hidden energy widget must not query")
  model.dashboardPreferences.backgroundUpdates = false
  precondition(model.dashboard.paused)
  model.popoverPreferences.layout = PopoverLayout(widgets: [.energyApps])
  model.setPopoverVisible(true); precondition(!model.energyMonitor.paused, "visible popup must keep its energy consumer active")
  precondition(model.dashboard.paused, "popup must not unpause the dashboard snapshot")
  model.popoverPreferences.layout = PopoverLayout(widgets: [])
  precondition(model.energyMonitor.paused, "hidden popup energy widget must stop querying")
  model.setPopoverVisible(false)
  model.popoverPreferences.layout = PopoverLayout(widgets: [.energyApps])
  model.setPopoverVisible(true, consumer: .preview)
  model.setPopoverVisible(true, consumer: .statusItem)
  model.setPopoverVisible(false, consumer: .preview)
  precondition(model.popoverVisible && !model.energyMonitor.paused, "closing preview must preserve an active status popover consumer")
  model.setPopoverVisible(false, consumer: .statusItem)
  precondition(!model.popoverVisible && model.energyMonitor.paused, "closing the last popover must pause energy reads")
  model.setPopoverVisible(true, consumer: .preview)
  model.setPopoverVisible(false, consumer: .statusItem)
  precondition(model.popoverVisible && !model.energyMonitor.paused, "a status close callback must not hide an active preview consumer")
  model.setPopoverVisible(false, consumer: .preview)
  print("production dashboard focus/background/schedule isolation and preference persistence passed; fixture only, no hardware control")
 }
}
