import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct HistoryPoint: Codable, Identifiable {
 var id: Date { date }; var date: Date; var percent: Double; var temperature: Double?; var watts: Double?; var reason: String
 var temperatureSource: BatteryTemperatureSource? = nil; var systemWatts: Double? = nil; var adapterWatts: Double? = nil; var limit: Double? = nil; var hardwarePercent: Double? = nil; var health: Double? = nil; var cycles: Int? = nil
}
enum PopoverConsumer: Hashable { case preview, statusItem }
@MainActor final class ChargeModel: ObservableObject {
 let updates: AppUpdates
 let helperService = HelperService()
 let energyMonitor = EnergyMonitor()
 var openStatusPopoverEditor: (() -> Void)?
 let popoverPreferences: PopoverPreferences
 @Published private(set) var popoverVisible = false
 private var visiblePopovers = Set<PopoverConsumer>()
 func setPopoverVisible(_ visible: Bool, consumer: PopoverConsumer = .preview) {
  if visible { visiblePopovers.insert(consumer) } else { visiblePopovers.remove(consumer) }
  let anyVisible = !visiblePopovers.isEmpty
  guard popoverVisible != anyVisible else { return }
  popoverVisible = anyVisible; syncDashboard()
 }
 let dashboardPreferences: DashboardPreferences
 let dashboard = DashboardPresentation()
 private var dashboardFocused = false
 private var dashboardWindowController: NSWindowController?
 func attachDashboardWindow(_ window: NSWindow) { setDashboardFocused(window.isKeyWindow && !window.isMiniaturized) }
 private var popoverPreviewController: NSWindowController?
 func openPopoverPreview() {
  if popoverPreviewController == nil {
   let window = NSWindow(contentViewController: NSHostingController(rootView: MenuView().environmentObject(self)))
   window.title = "OpenCharge · 弹窗预览"; window.identifier = NSUserInterfaceItemIdentifier("OpenChargePopoverPreview")
   window.styleMask = [.titled, .closable]; window.isReleasedWhenClosed = false
   window.center(); popoverPreviewController = NSWindowController(window: window)
  }
  popoverPreviewController?.showWindow(nil); popoverPreviewController?.window?.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true)
 }
 func openDashboardWindow() {
  if dashboardWindowController == nil {
   let controller = NSHostingController(rootView: DashboardRootView(model: self))
   let window = NSWindow(contentViewController: controller)
   window.title = "OpenCharge"; window.identifier = NSUserInterfaceItemIdentifier("OpenChargeDashboard")
   window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
   window.minSize = NSSize(width: 900, height: 650)
   window.setContentSize(NSSize(width: 980, height: 720)); window.center()
   window.setFrameAutosaveName("OpenChargeDashboard")
   window.isReleasedWhenClosed = false
   dashboardWindowController = NSWindowController(window: window)
  }
  dashboardWindowController?.showWindow(nil)
  dashboardWindowController?.window?.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true)
 }
 func setDashboardFocused(_ focused: Bool) { dashboardFocused = focused; syncDashboard() }
 func syncDashboard() {
  let active = DashboardRefreshPolicy.shouldUpdate(windowFocused: dashboardFocused, backgroundUpdates: dashboardPreferences.backgroundUpdates)
  if dashboard.paused == active { dashboard.paused = !active }
  let wantsEnergy = EnergyConsumerPolicy.shouldQuery(dashboardActive: active, dashboardHasWidget: dashboardPreferences.layout.widgets.contains(.energyApps), popoverVisible: popoverVisible, popoverHasWidget: popoverPreferences.layout.widgets.contains(.energyApps))
  if energyMonitor.paused == wantsEnergy { energyMonitor.paused = !wantsEnergy }
  if dashboard.focused != dashboardFocused { dashboard.focused = dashboardFocused }
  if active || dashboard.reading == nil { dashboard.capture(self) }
  if wantsEnergy { energyMonitor.refresh(sensitivity: EnergySensitivity(rawValue: UserDefaults.standard.string(forKey: "energySensitivity") ?? "balanced") ?? .balanced) }
 }
 @Published var config: Configuration
 @Published var reading: BatteryReading?
 @Published var decision = Decision(.restore, "正在读取电池…", limit: 80)
 @Published var error: String?
 @Published var helperStatus = "监测模式"
 @Published var history: [HistoryPoint] = []
 @Published var calibration = CalibrationStage.idle
 @Published var calibrationPending = false
 @Published var magSafeStatus = "尚未读取灯光能力"
 private var magSafeSelection: MagSafeColor?
 private var sleepOverrideSessionActive = false
 private var sleepOverrideFailed = false
 private var sleepOverrideCapability: Bool?
 @Published var sleepStatus = "尚未使用合盖睡眠控制"
 private var magSafeSessionActive = false
 private var magSafePolicyFailed = false
 @Published var lowPowerStatus = ProcessInfo.processInfo.isLowPowerModeEnabled ? "当前电源：已开启" : "当前电源：已关闭"
 private var engine = ChargeEngine()
 private let sleepController = SleepController()
 private var lastHardwareAction: ChargeAction = .restore
 private var dischargeExitPending = false
 private var quitting = false
 private var quitCleanupPrepared = false
 var needsQuitPreparation: Bool { config.hardwareEnabled || dischargeExitPending || lastHardwareAction == .forceDischarge || magSafeSessionActive || sleepOverrideSessionActive || sleepController.active }
 var needsDischargeExitWait: Bool { dischargeExitPending }
 private var timer: Timer?
 private var observers: [NSObjectProtocol] = []
 private var lastNotice = ""
 private let historyURL = Configuration.directory.appendingPathComponent("history.json")
 init(dashboardDefaults: UserDefaults = .standard) {
  updates = AppUpdates(defaults: dashboardDefaults)
  dashboardPreferences = DashboardPreferences(defaults: dashboardDefaults)
  popoverPreferences = PopoverPreferences(defaults: dashboardDefaults)
  do { config = try Configuration.load() } catch { config = Configuration(); self.error = "配置文件无法读取：\(error.localizedDescription)" }
  // An explicit opt-in persists; an interrupted calibration prevents resumption.
  if config.policy.mode == .calibration, let checkpoint = config.calibrationCheckpoint, checkpoint.stage != .idle && checkpoint.stage != .complete { calibrationPending = true; calibration = checkpoint.stage; config.hardwareEnabled = false }
  if let data = try? Data(contentsOf: historyURL), let points = try? JSONDecoder().decode([HistoryPoint].self, from: data) { history = Array(points.suffix(10080)) }
  DistributedNotificationCenter.default().addObserver(forName: Notification.Name("org.opencharge.configurationChanged"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
   guard let self else { return }; do { let enabled = self.config.hardwareEnabled; let previousLED = self.config.magSafeMode; self.config = try Configuration.load(); self.config.hardwareEnabled = enabled; if previousLED != self.config.magSafeMode { self.magSafeSelection = nil; self.magSafePolicyFailed = false }; if self.config.policy.mode != .calibration { self.calibrationPending = false } } catch { self.error = error.localizedDescription }
  } }
  dashboardPreferences.changed = { [weak self] in self?.syncDashboard() }
  popoverPreferences.changed = { [weak self] in self?.syncDashboard() }
  refresh()
  timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
  observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleep() } })
  observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
 }
 var powerAverages: [Double: WeightedPowerAverage] {
  let points = history.map { PowerSample(date: $0.date, watts: $0.systemWatts) }
  var result: [Double: WeightedPowerAverage] = [:]
  for minutes in [5.0, 15, 30] { result[minutes] = TelemetryMath.weightedAverage(samples: points, endingAt: Date(), windowMinutes: minutes) }
  return result
 }
 var title: String { if let r = reading { return "\(Int(r.percent))%" }; return "—" }
 var watts: Double? { guard let r = reading, let i = r.currentMA, let v = r.voltageMV else { return nil }; return i * v / 1_000_000 }
 func save() { do { try config.save() } catch { self.error = error.localizedDescription } }
 func changeMode(_ mode: ChargeMode) {
  if (mode == .topUp || mode == .calibration) && reading?.connected != true { error = "请连接电源后开始此操作"; return }
  if mode == .topUp && config.policy.mode == .calibration { error = "请先结束校准，再开始充至满电"; return }
  calibrationPending = false
  if mode != .calibration { config.calibrationCheckpoint = nil }
  config.policy.mode = mode; save(); refresh()
 }
 func resumeCalibration() { engine = ChargeEngine(checkpoint: config.calibrationCheckpoint); calibrationPending = false; refresh() }
 func setLowPower(_ enabled: Bool, source: String? = nil) {
  guard !quitting else { return }
  let command = source == "battery" ? (enabled ? "lowPowerBatteryOn" : "lowPowerBatteryOff") : source == "ac" ? (enabled ? "lowPowerACOn" : "lowPowerACOff") : (enabled ? "lowPowerOn" : "lowPowerOff")
  do { lowPowerStatus = try HelperClient.request(command); config.policy.lowPowerMode = enabled; save() } catch { self.error = error.localizedDescription }
 }
 func setMagSafe(_ color: MagSafeColor?) {
  magSafeSelection = color; magSafePolicyFailed = false
  if color == nil { config.magSafeMode = .system; config.magSafeOffDuringSleep = false; save() }
  updateMagSafe()
 }
 func useMagSafePolicy() { magSafeSelection = nil; magSafePolicyFailed = false; updateMagSafe() }
 func updateMagSafe() {
  guard !quitting, !magSafePolicyFailed else { return }
  let mode = config.magSafeMode ?? .system
  let wantsControl = magSafeSelection != nil || mode != .system || config.magSafeOffDuringSleep == true
  do {
   if !wantsControl {
    if magSafeSessionActive { magSafeStatus = try HelperClient.request("magSafeRestore"); magSafeSessionActive = false }
    return
   }
   let command: String
   if let color = magSafeSelection { command = color == .off ? "magSafeOff" : color == .green ? "magSafeGreen" : "magSafeOrange" }
   else { command = MagSafePolicy.command(mode: mode, connected: reading?.physicalAdapterConnected ?? (reading?.connected == true || lastHardwareAction == .forceDischarge), charging: reading?.charging ?? false, action: decision.action, controlEnabled: config.hardwareEnabled, blinkDischarge: config.magSafeBlinkDischarge ?? true, percent: config.policy.useHardwarePercent == true ? (reading?.hardwarePercent ?? .nan) : (reading?.percent ?? .nan), target: decision.effectiveLimit, sailingHold: decision.sailingHold ?? false, calibrating: calibration != .idle && calibration != .complete) }
   _ = try HelperClient.request(config.magSafeOffDuringSleep == true ? "magSafeSleepOn" : "magSafeSleepOff")
   magSafeSessionActive = true
   magSafeStatus = try HelperClient.request(command)
  } catch { magSafeStatus = error.localizedDescription; magSafePolicyFailed = true }
 }
 func inspectMagSafe() { do { magSafeStatus = try HelperClient.request("magSafeStatus") } catch { magSafeStatus = error.localizedDescription } }
 func inspectLowPower() { do { lowPowerStatus = try HelperClient.request("lowPowerStatus") } catch { self.error = error.localizedDescription } }

 func profile(_ limit: Double, _ sailing: Double, _ heat: Double) { config.policy.limit = limit; config.policy.sailingWidth = sailing; config.policy.maxTemperature = heat; config.policy.mode = .automatic; save(); refresh() }
 func refresh() {
  guard !quitting else { return }
  defer { syncDashboard() }
  do {
   let r = try BatteryTelemetryReader.read(); reading = r

   var scheduledPolicy = config.policy
   var changed = false
   var runs: [ScheduleExecution] = []
   for i in config.schedules.indices {
    let task = config.schedules[i]
    if config.schedules[i].consume(now: Date(), policy: &scheduledPolicy, runMissedTasks: config.runMissedTasks ?? true) {
     changed = true
     var result = "策略已更新"
     if task.action == .lowPowerOn || task.action == .lowPowerOff {
      if config.systemActionsEnabled == true {
       do { lowPowerStatus = try HelperClient.request(task.action == .lowPowerOn ? "lowPowerOn" : "lowPowerOff"); result = "系统模式已读回：" + lowPowerStatus }
       catch { result = "执行失败：" + error.localizedDescription; self.error = result }
      } else { result = "只读监测：未改变系统模式" }
     }
     runs.append(ScheduleExecution(scheduleID: task.id, action: task.action, scheduledAt: task.date, result: result))
    }
    if config.schedules[i].date != task.date || config.schedules[i].enabled != task.enabled { changed = true }
   }
   if changed { config.policy = scheduledPolicy; config.scheduleHistory = Array(((config.scheduleHistory ?? []) + runs).suffix(1000)); save() }
   let lid = Self.lidClosed()
   if calibrationPending { decision = Decision(.restore, "校准已中断：请选择继续或取消", limit: config.policy.limit) }
   else {
    let reference: Double
    if config.policy.useHardwarePercent == true { guard let raw = r.hardwarePercent else { throw HardwareError.unavailable("硬件电量不可读，已停止策略执行") }; reference = raw } else { reference = r.percent }
    decision = engine.decide(ChargeSample(percent: reference, temperature: r.temperature, connected: r.connected, lidClosed: lid, physicalAdapterConnected: r.physicalAdapterConnected, ownAdapterInhibited: lastHardwareAction == .forceDischarge), policy: config.policy)
    calibration = engine.calibration
    if config.policy.mode == .calibration && config.calibrationCheckpoint != engine.checkpoint { config.calibrationCheckpoint = engine.checkpoint; save() }
    if calibration == .complete { config.lastCalibration = Date(); config.policy.mode = .automatic; config.calibrationCheckpoint = nil; save() }
    if engine.completedMode != nil { config.policy.mode = .automatic; save() }
   }
   if config.hardwareEnabled {
    do { _ = try HelperClient.request(config.policy.stopInSleep ? "sleepPolicyOn" : "sleepPolicyOff"); _ = try HelperClient.request(decision.action.rawValue); helperStatus = "服务已确认：" + decision.action.displayName; lastHardwareAction = decision.action; if decision.action == .forceDischarge { dischargeExitPending = true } }
    catch { helperStatus = "控制失败"; self.error = error.localizedDescription; config.hardwareEnabled = false; try? config.save() }
   } else { helperStatus = "监测模式 · 未改变充电状态" }
   updateMagSafe()
   let plan = SleepProtectionPlan.evaluate(controlEnabled: config.hardwareEnabled, connected: r.connected, physicalAdapterConnected: r.physicalAdapterConnected, action: decision.action, percent: config.policy.useHardwarePercent == true ? (r.hardwarePercent ?? .nan) : r.percent, target: decision.effectiveLimit, calibrating: config.policy.mode == .calibration && !calibrationPending, idleUntilTarget: config.policy.keepAwakeUntilLimit == true, systemUntilTarget: config.policy.keepAwakeWithLidClosed == true, allowDisplaySleep: config.policy.allowDisplaySleep ?? true)
   do { try sleepController.setPreventIdleSleep(plan.preventIdleSleep) } catch { self.error = error.localizedDescription }
   updateSleepOverride(plan)
   if config.historyEnabled && (history.last.map { Date().timeIntervalSince($0.date) >= 60 } ?? true) {
    history.append(HistoryPoint(date: Date(), percent: r.percent, temperature: r.temperature, watts: watts, reason: decision.reason, temperatureSource: r.temperatureSource, systemWatts: r.systemPowerW, adapterWatts: r.adapterPowerW, limit: config.policy.limit, hardwarePercent: r.hardwarePercent, health: r.healthPercent, cycles: r.cycleCount))
    history = Array(history.suffix(10080)); try FileManager.default.createDirectory(at: Configuration.directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
   }
   if config.notifications && decision.reason != lastNotice {
    lastNotice = decision.reason
    let content = UNMutableNotificationContent(); content.title = "OpenCharge"; content.body = decision.reason
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "charge-state", content: content, trigger: nil))
   }
  } catch { self.error = error.localizedDescription; if config.hardwareEnabled { _ = try? HelperClient.request("restore") }; try? sleepController.setPreventIdleSleep(false) }
 }
 static func lidClosed() -> Bool {
  let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")); guard service != 0 else { return false }; defer { IOObjectRelease(service) }
  return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
 }
 func inspectSleepInterfaces(request: (String) throws -> String = HelperClient.request) {
  do {
   let result = try request("capabilities")
   sleepOverrideCapability = SleepProtectionPlan.supportsHelper(result)
   sleepStatus = sleepOverrideCapability == true ? "已检测到私有接口；物理效果仍待实机验证" : "已安装服务未提供所需睡眠接口或恢复协议，请更新服务"
   if sleepOverrideFailed { sleepStatus += "；上次控制失败，需重新启用硬件控制后再试" }
  } catch { sleepOverrideCapability = false; sleepStatus = error.localizedDescription }
 }
 func updateSleepOverride(_ plan: SleepProtectionPlan, request: (String) throws -> String = HelperClient.request) {
  guard !quitting else { return }
  do {
   if plan.preventSystemAndLidSleep {
    guard !sleepOverrideFailed else { return }
    if sleepOverrideCapability == nil { inspectSleepInterfaces() }
    guard sleepOverrideCapability == true else { return }
    sleepStatus = try request(plan.preventDisplaySleep ? "sleepOverrideDisplayOn" : "sleepOverrideOn")
    sleepOverrideSessionActive = true
   } else if sleepOverrideSessionActive {
    _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false
    sleepStatus = "合盖睡眠控制已释放"
   } else if !config.hardwareEnabled && sleepOverrideCapability == nil { sleepStatus = "监测模式 · 未修改睡眠设置" }
  } catch { sleepOverrideFailed = true; sleepStatus = "睡眠控制失败：" + error.localizedDescription }
 }
 func enableHardware(_ enabled: Bool) {
  guard !quitting else { return }
  if enabled { do {
   sleepOverrideFailed = false
   guard !calibrationPending else { throw HelperError.rejected("请先选择继续或取消上次校准") }
   helperStatus = try HelperClient.request("capabilities"); sleepOverrideCapability = SleepProtectionPlan.supportsHelper(helperStatus); guard helperStatus.split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("chargeControl:") && !$0.contains("unavailable") }) else { throw HelperError.rejected(helperStatus) }; config.hardwareEnabled = true } catch { self.error = error.localizedDescription; config.hardwareEnabled = false } }
  else { do { helperStatus = try HelperClient.request("restore"); lastHardwareAction = .restore; config.hardwareEnabled = false } catch { self.error = "恢复请求失败；服务会在心跳超时后尝试恢复：\(error.localizedDescription)"; config.hardwareEnabled = false } }
  save(); refresh()
 }
 func sleep() { guard !quitting, config.hardwareEnabled else { return }
  // The root observer also reconciles sleep and acknowledges it. Paused/discharging states stay paused.
  let inhibit = config.policy.stopInSleep || decision.action == .inhibitCharge || decision.action == .forceDischarge
  _ = try? HelperClient.request(inhibit ? "inhibitCharge" : "restore")
 }
 func prepareForQuit(request: (String) throws -> String = HelperClient.request) throws {
  quitting = true
  var failures: [String] = []
  if sleepOverrideSessionActive { do { _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false } catch { failures.append(error.localizedDescription) } }
  if magSafeSessionActive { do { _ = try request("magSafeRestore"); magSafeSessionActive = false } catch { failures.append(error.localizedDescription) } }
  do { try sleepController.setPreventIdleSleep(false) } catch { failures.append(error.localizedDescription) }
  if config.hardwareEnabled || lastHardwareAction == .forceDischarge {
   do { _ = try request(config.policy.stopOnQuit ? "retainChargeInhibit" : "restore"); lastHardwareAction = config.policy.stopOnQuit ? .inhibitCharge : .restore }
   catch { failures.append(error.localizedDescription) }
  }
  quitCleanupPrepared = failures.isEmpty
  if !failures.isEmpty { throw HelperError.rejected(failures.joined(separator: "; ")) }
 }
 func cancelQuit() {
  // Never resume a discharge/calibration automatically after a cancelled exit.
  config.hardwareEnabled = false
  if config.policy.mode == .calibration { calibrationPending = true }
  quitting = false; quitCleanupPrepared = false
  error = "已取消退出，充电控制已关闭；请确认电源状态后手动重新启用。"
  save(); refresh()
 }
 func cleanupOnQuit() { if !quitCleanupPrepared { try? prepareForQuit() } }
 func quit() { NSApp.terminate(nil) }

 func handleURL(_ url: URL) {
  guard url.scheme == "opencharge", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
  if url.host == "limit", let text = components.queryItems?.first(where: { $0.name == "value" })?.value, let value = Double(text), value.isFinite, (20...100).contains(value) { config.policy.limit = value; save(); refresh() }
  else if url.host == "mode", let value = components.queryItems?.first(where: { $0.name == "value" })?.value, let mode = ChargeMode(rawValue: value) { changeMode(mode) }
  else { error = "自动化 URL 参数无效" }
 }
 func export() {
  let panel = NSSavePanel(); panel.nameFieldStringValue = "opencharge-history.csv"; panel.allowedContentTypes = [.commaSeparatedText]
  guard panel.runModal() == .OK, let url = panel.url else { return }
  let iso = ISO8601DateFormatter()
  let text = "timestamp,percent,temperature_c,power_w,reason,temperature_source\n" + history.map { p in
   "\(iso.string(from: p.date)),\(p.percent),\(p.temperature.map(String.init(describing:)) ?? ""),\(p.watts.map(String.init(describing:)) ?? ""),\"\(p.reason.replacingOccurrences(of: "\"", with: "\"\""))\",\(p.temperatureSource?.rawValue ?? "")"
  }.joined(separator: "\n")
  do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
 }
 func backupConfiguration() {
  let panel = NSSavePanel(); panel.nameFieldStringValue = "opencharge-settings.json"; panel.allowedContentTypes = [.json]
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do { try ConfigurationBackup(configuration: config).encoded().write(to: url, options: .atomic) }
  catch { self.error = error.localizedDescription }
 }
 func restoreConfiguration() {
  guard !quitting else { return }
  let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do {
   let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
   guard size <= 1_048_576 else { throw ConfigurationBackupError.tooLarge }
   let restored = try ConfigurationBackup.restored(from: Data(contentsOf: url))
   // Validate before touching current hardware or configuration.
   if magSafeSessionActive { _ = try HelperClient.request("magSafeRestore"); magSafeSessionActive = false }
   magSafeSelection = nil; magSafePolicyFailed = false
   if config.hardwareEnabled { _ = try HelperClient.request("restore") }
   try sleepController.setPreventIdleSleep(false)
   try restored.save(); config = restored; engine = ChargeEngine(); calibrationPending = false
   lastHardwareAction = .restore; refresh()
  } catch { self.error = error.localizedDescription }
 }
 func removeHelperService() async {
  guard !quitting else { return }
  do {
   guard !helperService.legacyInstalled else { throw HelperServiceError.ineligible("开发脚本服务需使用对应卸载脚本移除") }
   // SMAppService unregister terminates the daemon: restore while its journal is alive.
   if helperService.status == .enabled {
    _ = try HelperClient.request("restore")
    _ = try HelperClient.request("magSafeRestore")
   }
   config.hardwareEnabled = false; magSafeSessionActive = false; magSafeSelection = nil
   try sleepController.setPreventIdleSleep(false); save()
   try await helperService.unregister(); helperStatus = "硬件服务已注销"
  } catch { self.error = error.localizedDescription }
 }
 func exportDiagnostics() {
  let panel = NSSavePanel(); panel.nameFieldStringValue = "opencharge-diagnostics.json"; panel.allowedContentTypes = [.json]
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do {
   let model = (try? HardwareIdentity.model()) ?? "unknown"
   #if arch(arm64)
   let architecture = "arm64"
   #elseif arch(x86_64)
   let architecture = "x86_64"
   #else
   let architecture = "unknown"
   #endif
   let capabilities = (try? HelperClient.request("capabilities")) ?? "unavailable"
   let battery = reading.map { DiagnosticReport.Battery(percent: $0.percent, temperature: $0.temperature, connected: $0.connected, charging: $0.charging, cycles: $0.cycleCount) }
   let report = DiagnosticReport(appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development", systemVersion: ProcessInfo.processInfo.operatingSystemVersionString, architecture: architecture, model: model, battery: battery, configuration: config, registrationStatus: helperService.statusText, helperCapabilities: capabilities, decision: decision.action, errorPresent: error != nil)
   try report.encoded().write(to: url, options: .atomic)
  } catch { self.error = error.localizedDescription }
 }
 func clearHistory() { history = []; do { try Data("[]".utf8).write(to: historyURL, options: .atomic) } catch { self.error = error.localizedDescription } }
}
