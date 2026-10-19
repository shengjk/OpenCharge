import Foundation
import ChargeCore
import ChargeHardware

@main struct DashboardSmoke {
 @MainActor static func main() throws {
  let labelReading = BatteryReading(percent: 80.9, connected: true, charging: false, hardwarePercent: 77.4)
  let statusLabel = MenuBarLabel(display: "status", reading: labelReading)
  precondition(statusLabel.text == "80%" && statusLabel.symbol == "pause.circle")
  let percentageLabel = MenuBarLabel(display: "percentage", reading: labelReading)
  precondition(percentageLabel.text == "80%" && percentageLabel.symbol == nil)
  let hardwareLabel = MenuBarLabel(display: "hardware", reading: labelReading)
  precondition(hardwareLabel.text == "77%" && hardwareLabel.symbol == nil)
  let iconLabel = MenuBarLabel(display: "icon", reading: labelReading)
  precondition(iconLabel.text.isEmpty && iconLabel.symbol == "battery.75percent" && iconLabel.accessibilityText.contains("80%"))
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
  let model = ChargeModel(dashboardDefaults: defaults)
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
  precondition(model.reading != nil && model.dashboard.paused)
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
