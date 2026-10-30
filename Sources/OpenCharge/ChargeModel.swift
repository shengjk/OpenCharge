import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

enum PopoverConsumer: Hashable { case preview, statusItem }
@MainActor final class ChargeModel: ObservableObject {
 let setupOnLaunch: Bool
 private var setupWindow: NSWindowController?
 private var setupWindowDelegate: SetupWizardWindowDelegate?
 let updates: AppUpdates
 let helperService: HelperService
 let energyMonitor = EnergyMonitor()
 var openStatusPopoverEditor: (() -> Void)?
 let popoverPreferences: PopoverPreferences
 let menuBarActions: MenuBarActionPreferences
 @Published var dashboardPage: Page? = .overview
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
   window.title = NSLocalizedString("OpenCharge · 弹窗预览", comment: ""); window.identifier = NSUserInterfaceItemIdentifier("OpenChargePopoverPreview")
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
 var setupDefaultCalibration: Bool {
  settingsDefaults.string(forKey:SetupWizardPresentation.key) == SetupWizardPresentation.State.pending.rawValue || config.schedules.contains { $0.action == .calibrate && $0.enabled }
 }
 func setupLidClosed() -> Bool { LidStateObserver.currentState() ?? observedLidState ?? false }
 func openSetupWizard() {
  if setupWindow == nil {
   let content = NSHostingController(rootView:SetupWizardView(model:self))
   let window = NSWindow(contentViewController:content)
   window.title = NSLocalizedString("OpenCharge · 设置向导",comment:""); window.identifier = NSUserInterfaceItemIdentifier("OpenChargeSetupWizard")
   window.styleMask = [.titled,.closable,.resizable]; window.isReleasedWhenClosed = false
   window.setContentSize(NSSize(width:720,height:650)); window.center()
   setupWindowDelegate = SetupWizardWindowDelegate { [weak self] in
    guard let self else { return }
    if self.settingsDefaults.string(forKey:SetupWizardPresentation.key) == SetupWizardPresentation.State.pending.rawValue {
     SetupWizardPresentation.finish(.skipped,defaults:self.settingsDefaults)
    }
    self.setupWindow = nil; self.setupWindowDelegate = nil
   }
   window.delegate = setupWindowDelegate; setupWindow = NSWindowController(window:window)
  }
  setupWindow?.showWindow(nil); setupWindow?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
 }
 func finishSetupWizard(applied: Bool) {
  SetupWizardPresentation.finish(applied ? .completed : .skipped,defaults:settingsDefaults)
  setupWindow?.close(); openDashboardWindow()
 }
 func applySetupSurvey(_ answers: SetupAnswers, lidClosed: Bool, now: Date = Date(),
                       persist: (Configuration) throws -> Void = { try $0.save() },refresh: (() -> Void)? = nil) throws {
  guard allowChargeSettingsEdit() else { throw HelperServiceError.ineligible(error ?? "") }
  guard !settingsResetPending else { throw HelperServiceError.ineligible(NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停",comment:"")) }
  guard config.policy.mode != .calibration, !calibrationPending else { throw HelperServiceError.ineligible(NSLocalizedString("请先结束校准，再应用设置向导",comment:"")) }
  let plan = try SetupRecommendation(answers:answers,lidClosed:lidClosed,now:now)
  let next = plan.applying(to:config,calibrationName:NSLocalizedString("自动校准",comment:""))
  try persist(next); config = next
  SetupWizardPresentation.finish(.completed,defaults:settingsDefaults)
  (refresh ?? { self.refresh() })()
 }
 func selectSettingsPage() { dashboardPage = .settings }
 func openSettingsPage() { selectSettingsPage(); openDashboardWindow() }
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
 @Published private(set) var settingsLocked = false
 private let settingsDefaults: UserDefaults
 private var settingsPreferenceObservation: SettingsLockObservation?
 @Published var config: Configuration
 @Published var reading: BatteryReading?
 @Published var decision = Decision(.restore, NSLocalizedString("正在读取电池…", comment: ""), limit: 80)
 @Published var error: String?
 @Published private(set) var settingsResetStatus: String?
 @Published private(set) var settingsResetPending = false
 @Published var helperStatus = NSLocalizedString("监测模式", comment: "")
 @Published private(set) var firmwareInspection: FirmwareHelperState?
 @Published private(set) var firmwareStatus = NSLocalizedString("尚未检测数值固件通道", comment: "")
 @Published var history: [HistoryPoint] = []
 @Published var calibration = CalibrationStage.idle
 @Published var calibrationPending = false
 @Published var magSafeStatus = NSLocalizedString("尚未读取灯光能力", comment: "")
 private var magSafeSelection: MagSafeColor?
 private var sleepOverrideSessionActive = false
 private var sleepOverrideFailed = false
 private var sleepOverrideCapability: Bool?
 private var chargeContextEnabled = false
 private var multiDisplaySleepEnabled = false
 private let screenLockRequest: () throws -> Void
 private var lidLockPolicy = LidLockPolicy()
 private var lidObserver: LidStateObserver?
 private var observedLidState: Bool?
 @Published var lidLockStatus = NSLocalizedString("默认关闭 · 未请求锁屏", comment: "")
 @Published var sleepStatus = NSLocalizedString("尚未使用合盖睡眠控制", comment: "")
 private var magSafeSessionActive = false
 private var magSafePolicyFailed = false
 @Published var lowPowerStatus = LowPowerObservation.current.map { $0 ? NSLocalizedString("当前电源：已开启", comment: "") : NSLocalizedString("当前电源：已关闭", comment: "") } ?? NSLocalizedString("不可用", comment: "")
 private let readBattery: () throws -> BatteryReading
 private var engine = ChargeEngine()
 private var appliedChargeLimitChangeID: UUID?
 private let sleepController = SleepController()
 private var lastHardwareAction: ChargeAction = .restore
 private var firmwareControl: FirmwareAppSession?
 var usesNumericFirmware: Bool { firmwareControl != nil }
 private var dischargeExitPending = false
 private var quitting = false
 private var quitCleanupPrepared = false
 private var quitChargeRecoveryPending = false
 private var quitRecoveryIntentStored = false
 var automationPhase: PolicyPhase { quitting ? .exit : calibrationPending ? .calibration : decision.phase ?? engine.phase }
 var needsQuitPreparation: Bool { quitChargeRecoveryPending || config.hardwareEnabled || firmwareControl?.mayOwnSession == true || dischargeExitPending || lastHardwareAction == .forceDischarge || magSafeSessionActive || sleepOverrideSessionActive || sleepController.active }
 var needsDischargeExitWait: Bool { dischargeExitPending }
 private var timer: Timer?
 private var observers: [NSObjectProtocol] = []
 private var lastNotice = ""
 private let historyURL = Configuration.directory.appendingPathComponent("history.json")
 init(dashboardDefaults: UserDefaults = .standard, observeLid: Bool = true, screenLockRequest: @escaping () throws -> Void = ScreenLockClient.requestLock, readBattery: @escaping () throws -> BatteryReading = { try BatteryTelemetryReader.read() }, helperService: HelperService? = nil, appUpdates: AppUpdates? = nil, startupRecoveryRequest: (String) throws -> String = HelperClient.request, startupRecoveryPersist: (Configuration) throws -> Void = { try $0.save() }) {
  self.helperService = helperService ?? HelperService()
  settingsDefaults = dashboardDefaults
  setupOnLaunch = SetupWizardPresentation.shouldShow(configurationExists:FileManager.default.fileExists(atPath:Configuration.url.path),defaults:dashboardDefaults)
  self.readBattery = readBattery
  self.screenLockRequest = screenLockRequest
  updates = appUpdates ?? AppUpdates(defaults: dashboardDefaults)
  dashboardPreferences = DashboardPreferences(defaults: dashboardDefaults)
  popoverPreferences = PopoverPreferences(defaults: dashboardDefaults)
  menuBarActions = MenuBarActionPreferences(defaults: dashboardDefaults)
  do { config = try Configuration.load() } catch { config = Configuration(); self.error = String.localizedStringWithFormat(NSLocalizedString("配置文件无法读取：%@", comment: ""), error.localizedDescription) }
  if config.pendingOrdinaryQuitRecovery == true {
   config.hardwareEnabled = false; quitChargeRecoveryPending = true; quitRecoveryIntentStored = true
  }
  engine = ChargeEngine(sailingCheckpoint: config.sailingCheckpoint)
  appliedChargeLimitChangeID = config.chargeLimitChangeID
  // An explicit opt-in persists; an interrupted calibration prevents resumption.
  if config.policy.mode == .calibration, let checkpoint = config.calibrationCheckpoint, checkpoint.stage != .idle && checkpoint.stage != .complete { calibrationPending = true; calibration = checkpoint.stage; config.hardwareEnabled = false }
  if let data = try? Data(contentsOf: historyURL), let points = try? JSONDecoder().decode([HistoryPoint].self, from: data) { history = Array(points.suffix(10080)) }
  DistributedNotificationCenter.default().addObserver(forName: Notification.Name("org.opencharge.configurationChanged"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
   self?.reloadExternalConfiguration()
  } }
  dashboardPreferences.changed = { [weak self] in self?.syncDashboard() }
  popoverPreferences.changed = { [weak self] in self?.syncDashboard() }
  if observeLid { observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in
   guard let self, self.config.hardwareEnabled, !self.quitting else { return }; self.refresh()
  } }) }
  if observeLid { do { lidObserver = try LidStateObserver { [weak self] in
   Task { @MainActor [weak self] in self?.handleLidStateNotification(LidStateObserver.currentState()) }
  } } catch { lidLockStatus = NSLocalizedString("合盖监听不可用：", comment: "") + error.localizedDescription } }
  reloadSettingsLock()
  settingsPreferenceObservation = SettingsLockObservation(defaults: dashboardDefaults) { [weak self] in self?.reloadSettingsLock() }
  if config.pendingOrdinaryQuitRecovery == true {
   do { try restoreChargeControl(request:startupRecoveryRequest,persist:startupRecoveryPersist) }
   catch { self.error = NSLocalizedString("恢复仍待重试：",comment:"")+error.localizedDescription }
  }
  if config.hardwareEnabled {
   do { try configureHardwareChannel(capabilities:HelperClient.request("capabilities"),numericRequired:requiresNumericFirmware()) }
   catch { config.hardwareEnabled = false; self.error = error.localizedDescription; try? config.save() }
  }
  refresh()
  PolicyStateRuntime.provider = { [weak self] in
   guard let self else { throw HelperError.rejected(NSLocalizedString("应用策略实例已结束", comment: "")) }
   return self.automationPhase
  }
  // Policy and helper-lease refresh must continue inside native panels and tracking.
  let timer = Timer(timeInterval:10,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
  self.timer = timer
  for mode in [RunLoop.Mode.common,.modalPanel,.eventTracking] { RunLoop.main.add(timer,forMode:mode) }
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
 func reloadExternalConfiguration() {
  do {
   let incoming = try Configuration.load()
   let startsFreshCalibration = incoming.policy.mode == .calibration && incoming.calibrationCheckpoint == nil &&
    (config.policy.mode != .calibration || config.calibrationCheckpoint != nil || calibrationPending)
   let enabled = config.hardwareEnabled; let previousLED = config.magSafeMode
   let peerCompletedRecovery = quitRecoveryIntentStored && config.pendingOrdinaryQuitRecovery == true && incoming.pendingOrdinaryQuitRecovery != true
   let correctSavedOptIn = incoming.hardwareEnabled != enabled
   config = incoming; config.hardwareEnabled = enabled
   if incoming.pendingOrdinaryQuitRecovery == true {
    config.hardwareEnabled = false; quitChargeRecoveryPending = true; quitRecoveryIntentStored = true
   } else if peerCompletedRecovery {
    quitChargeRecoveryPending = false; quitRecoveryIntentStored = false; lastHardwareAction = .restore
   }
   if startsFreshCalibration {
    engine = ChargeEngine(sailingCheckpoint: config.sailingCheckpoint)
  appliedChargeLimitChangeID = config.chargeLimitChangeID; calibration = .idle; calibrationPending = false
   }
   if previousLED != config.magSafeMode { magSafeSelection = nil; magSafePolicyFailed = false }
   if config.policy.mode != .calibration { calibrationPending = false }
   // An interrupted run may have disabled control only in memory. Keep that
   // opt-in on disk too, so a fresh intent cannot rearm it on a later relaunch.
   if correctSavedOptIn { try config.save() }
  } catch { self.error = error.localizedDescription }
 }
 func save() { do { try config.save() } catch { self.error = error.localizedDescription } }
 func showLowChargeLimitNotice(present: @MainActor () -> Void = LowChargeLimitNotice.present) {
  guard !quitting, !settingsResetPending, !calibrationPending, config.policy.mode != .calibration else { return }
  LowChargeLimitNotice.showIfNeeded(limit:config.policy.limit,defaults:settingsDefaults,present:present)
 }
 func reloadSettingsLock() {
  let locked = settingsDefaults.bool(forKey: "settingsLock")
  if settingsLocked != locked { settingsLocked = locked }
 }
 @discardableResult func allowChargeSettingsEdit() -> Bool {
  guard !quitting else { return false }
  reloadSettingsLock()
  guard !settingsLocked else { error = NSLocalizedString("充电设置已锁定，请联系管理员调整配置", comment: ""); return false }
  return true
 }
 func toggleTopUp() { changeMode(automationPhase == .topUp ? .paused : .topUp) }
 func toggleDischarge() { changeMode(automationPhase == .discharging ? .paused : .discharge) }
 func toggleDischargeFromPopover() {
  guard !config.policy.automaticDischarge else { return }
  toggleDischarge()
 }
 func toggleChargingFromMenu() {
  guard !quitting, allowChargeSettingsEdit() else { return }
  guard !calibrationPending else { error = NSLocalizedString("校准已中断，请先选择继续或取消", comment: ""); return }
  do {
   let sample = try readBattery()
   let percent = config.policy.useHardwarePercent == true ? sample.hardwarePercent : sample.percent
   guard let percent else { throw MenuBarChargeToggleError.unavailablePercentage }
   var policy = config.policy
   let result = try MenuBarChargeToggleRequest.apply(phase: automationPhase, percent: percent, policy: &policy)
   config.setChargeLimit(policy.limit); config.policy = policy; config.calibrationCheckpoint = nil
   switch result {
   case .pausedAtCurrent: engine.modeChanged(to: .paused)
   case .chargingToFull:
    engine.startChargingAtFullTarget(); appliedChargeLimitChangeID = config.chargeLimitChangeID
   }
   save(); refresh()
  } catch { self.error = error.localizedDescription }
 }
 func toggleLowPowerFromMenu(request: (String) throws -> String = HelperClient.request,
                             isActive: () -> Bool? = { LowPowerObservation.current }) {
  guard !quitting, !settingsResetPending else { return }
  guard config.systemActionsEnabled == true else { error = NSLocalizedString("请先允许菜单栏快捷操作改变系统模式", comment: ""); return }
  do {
   let status = try request("lowPowerStatus")
   let fields = status.split(separator: " ")
   guard fields.count == 2, fields[0].hasPrefix("battery="), fields[1].hasPrefix("ac="),
         ["0", "1", "unknown"].contains(String(fields[0].dropFirst(8))),
         ["0", "1", "unknown"].contains(String(fields[1].dropFirst(3))),
         fields[0] != "battery=unknown" || fields[1] != "ac=unknown" else {
    throw HelperError.rejected(NSLocalizedString("低电量模式能力不可用", comment: ""))
   }
   guard let active = isActive() else { throw HelperError.rejected(NSLocalizedString("低电量模式能力不可用", comment: "")) }
   let enabled = !active
   lowPowerStatus = try request(enabled ? "lowPowerOn" : "lowPowerOff")
   config.policy.lowPowerMode = enabled; save()
  } catch { self.error = error.localizedDescription }
 }
 var controlModeSelection: Binding<ChargeMode> {
  Binding(get: { self.config.policy.mode }, set: { self.changeMode($0) })
 }
 func changeMode(_ mode: ChargeMode) {
  guard !quitting else { return }
  if mode == .calibration && calibrationPending { error = NSLocalizedString("校准已中断，请先选择继续或取消", comment: ""); return }
  if (mode == .topUp || mode == .calibration) && reading?.connected != true { error = NSLocalizedString("请连接电源后开始此操作", comment: ""); return }
  if mode == .topUp && config.policy.mode == .calibration { error = NSLocalizedString("请先结束校准，再开始充至满电", comment: ""); return }
  calibrationPending = false
  if mode != .calibration { config.calibrationCheckpoint = nil }
  engine.modeChanged(to: mode); calibration = engine.calibration
  config.policy.mode = mode; config.policy.pauseAtCurrent = nil; save(); refresh()
 }
 func resumeCalibration() { engine = ChargeEngine(checkpoint: config.calibrationCheckpoint, sailingCheckpoint: config.sailingCheckpoint); calibrationPending = false; refresh() }
 func setLowPower(_ enabled: Bool, source: String? = nil) {
  guard !quitting, !settingsResetPending else { return }
  let command = source == "battery" ? (enabled ? "lowPowerBatteryOn" : "lowPowerBatteryOff") : source == "ac" ? (enabled ? "lowPowerACOn" : "lowPowerACOff") : (enabled ? "lowPowerOn" : "lowPowerOff")
  do { lowPowerStatus = try HelperClient.request(command); config.policy.lowPowerMode = enabled; save() } catch { self.error = error.localizedDescription }
 }
 func setMagSafe(_ color: MagSafeColor?, request: (String) throws -> String = HelperClient.request) {
  guard !settingsResetPending else { return }
  if quitChargeRecoveryPending || config.pendingOrdinaryQuitRecovery == true {
   do { try restoreChargeControl(request:request) }
   catch { self.error = NSLocalizedString("恢复仍待重试：",comment:"")+error.localizedDescription; return }
  }
  magSafeSelection = color; magSafePolicyFailed = false
  if color == nil { config.magSafeMode = .system; config.magSafeOffDuringSleep = false; save() }
  updateMagSafe(request:request)
 }
 func useMagSafePolicy(request: (String) throws -> String = HelperClient.request) {
  if quitChargeRecoveryPending || config.pendingOrdinaryQuitRecovery == true {
   do { try restoreChargeControl(request:request) }
   catch { self.error = NSLocalizedString("恢复仍待重试：",comment:"")+error.localizedDescription; return }
  }
  magSafeSelection = nil; magSafePolicyFailed = false; updateMagSafe(request:request)
 }
 func updateMagSafe(request: (String) throws -> String = HelperClient.request) {
  guard !quitting, !settingsResetPending, !magSafePolicyFailed, !quitChargeRecoveryPending else { return }
  let mode = config.magSafeMode ?? .system
  let wantsControl = magSafeSelection != nil || mode != .system || config.magSafeOffDuringSleep == true
  do {
   if !wantsControl {
    if magSafeSessionActive { magSafeStatus = try request("magSafeRestore"); magSafeSessionActive = false }
    return
   }
   let command: String
   if let color = magSafeSelection { command = color.command }
   else { command = MagSafePolicy.command(mode: mode, connected: reading?.physicalAdapterConnected ?? (reading?.connected == true || lastHardwareAction == .forceDischarge), charging: reading?.charging ?? false, action: decision.action, controlEnabled: config.hardwareEnabled, blinkDischarge: config.magSafeBlinkDischarge ?? true, percent: config.policy.useHardwarePercent == true ? (reading?.hardwarePercent ?? .nan) : (reading?.percent ?? .nan), target: decision.effectiveLimit, sailingHold: decision.sailingHold ?? false, calibrating: calibration != .idle && calibration != .complete, fullChargeHold: decision.fullChargeHold == true) }
   try MagSafePolicy.validateNativeEncoding(command: command, capabilities: { try request("capabilities") })
   _ = try request(config.magSafeOffDuringSleep == true ? "magSafeSleepOn" : "magSafeSleepOff")
   magSafeSessionActive = true
   magSafeStatus = try request(command)
  } catch { magSafeStatus = error.localizedDescription; magSafePolicyFailed = true }
 }
 func inspectMagSafe() { do { magSafeStatus = try HelperClient.request("magSafeStatus") } catch { magSafeStatus = error.localizedDescription } }
 func inspectLowPower() { do { lowPowerStatus = try HelperClient.request("lowPowerStatus") } catch { self.error = error.localizedDescription } }

 func profile(_ limit: Double, _ sailing: Double, _ heat: Double) { config.setChargeLimit(limit); config.policy.sailingWidth = sailing; config.policy.maxTemperature = heat; changeMode(.automatic) }
 // Shared by refresh and isolated sample fixtures; actuator work follows in refresh.
 func evaluatePolicy(_ sample: ChargeSample) {
  guard !calibrationPending && !quitting else { return }
  if config.chargeLimitChangeID != appliedChargeLimitChangeID {
   if config.chargeLimitChangeID != nil { engine.chargeLimitChanged() }
   appliedChargeLimitChangeID = config.chargeLimitChangeID
  }
  decision = engine.decide(sample, policy: config.policy)
  calibration = engine.calibration
  var changed = false
  if config.sailingCheckpoint != engine.sailingCheckpoint { config.sailingCheckpoint = engine.sailingCheckpoint; changed = true }
  if config.policy.mode == .calibration && config.calibrationCheckpoint != engine.checkpoint { config.calibrationCheckpoint = engine.checkpoint; changed = true }
  if calibration == .complete { config.lastCalibration = sample.date; config.policy.mode = .automatic; config.calibrationCheckpoint = nil; changed = true }
  if engine.completedMode != nil { config.policy.mode = .automatic; config.policy.pauseAtCurrent = nil; changed = true }
  if changed { save() }
 }
 func refresh() {
  guard !quitting else { return }
  reloadSettingsLock()
  defer { syncDashboard() }
  guard !settingsResetPending else {
   decision = Decision(.restore,NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停", comment: ""),limit:config.policy.limit); return
  }
  do {
   let r = try readBattery(); reading = r
   let lid = LidStateObserver.currentState()
   if let lid { observedLidState = lid }
   let controlPercent = config.policy.useHardwarePercent == true ? r.hardwarePercent : r.percent
   let scheduleSample = controlPercent.map { ChargeSample(percent: $0, temperature: r.temperature, connected: r.connected, lidClosed: lid ?? false, physicalAdapterConnected: r.physicalAdapterConnected, ownAdapterInhibited: lastHardwareAction == .forceDischarge) }
   // Project on a copy: eligibility must reflect this sample and earlier tasks,
   // without advancing production calibration/thermal state an extra time.
   var scheduleEngine = engine
   if config.chargeLimitChangeID != appliedChargeLimitChangeID && config.chargeLimitChangeID != nil { scheduleEngine.chargeLimitChanged() }
   var scheduledPhase: PolicyPhase?
   var needsScheduleProjection = true
   var scheduledPolicy = config.policy
   var changed = false
   var scheduledLimitChanged = false
   var runs: [ScheduleExecution] = []
   let now = Date()
   for i in config.schedules.indices {
    let task = config.schedules[i]
    if config.schedules[i].consume(now: now, runMissedTasks: config.runMissedTasks ?? true) {
     changed = true
     if needsScheduleProjection {
      scheduledPhase = nil
      if !calibrationPending, let sample = scheduleSample, sample.percent.isFinite, (0...100).contains(sample.percent) {
       scheduledPhase = scheduleEngine.decide(sample, policy: scheduledPolicy).phase
      }
      needsScheduleProjection = false
     }
     let previousPolicy = scheduledPolicy
     let outcome = task.apply(policy: &scheduledPolicy, pauseContext: ScheduledPauseContext(phase: scheduledPhase, percent: controlPercent, calibrationInterrupted: calibrationPending))
     if case .pausedAtCurrent = outcome {
      engine.modeChanged(to: .paused)
      config.calibrationCheckpoint = nil; calibrationPending = false
     }
     if scheduledPolicy != previousPolicy {
      needsScheduleProjection = true
      if scheduledPolicy.limit != previousPolicy.limit { scheduledLimitChanged = true; scheduleEngine.chargeLimitChanged() }
     }
     var result = outcome.historyMessage
     if task.action == .lowPowerOn || task.action == .lowPowerOff {
      if config.systemActionsEnabled == true {
       do { lowPowerStatus = try HelperClient.request(task.action == .lowPowerOn ? "lowPowerOn" : "lowPowerOff"); result = NSLocalizedString("系统模式已读回：", comment: "") + lowPowerStatus }
       catch { result = NSLocalizedString("执行失败：", comment: "") + error.localizedDescription; self.error = result }
      } else { result = NSLocalizedString("只读监测：未改变系统模式", comment: "") }
     }
     runs.append(ScheduleExecution(scheduleID: task.id, action: task.action, scheduledAt: task.date, result: result, scheduleName:task.name))
    }
    if config.schedules[i].date != task.date || config.schedules[i].enabled != task.enabled { changed = true }
   }
   if changed {
    config.policy = scheduledPolicy
    if scheduledLimitChanged { config.sailingCheckpoint = true; config.chargeLimitChangeID = UUID() }
    config.scheduleHistory = Array(((config.scheduleHistory ?? []) + runs).suffix(1000)); save()
   }
   if calibrationPending { decision = Decision(.restore, NSLocalizedString("校准已中断：请选择继续或取消", comment: ""), limit: config.policy.limit) }
   else {
    let reference: Double
    if config.policy.useHardwarePercent == true { guard let raw = r.hardwarePercent else { throw HardwareError.unavailable(NSLocalizedString("硬件电量不可读，已停止策略执行", comment: "")) }; reference = raw } else { reference = r.percent }
    evaluatePolicy(ChargeSample(percent: reference, temperature: r.temperature, connected: r.connected, lidClosed: lid ?? false, physicalAdapterConnected: r.physicalAdapterConnected, ownAdapterInhibited: lastHardwareAction == .forceDischarge))
   }
   let plan = SleepProtectionPlan.evaluate(controlEnabled: config.hardwareEnabled, connected: r.connected, physicalAdapterConnected: r.physicalAdapterConnected, action: decision.action, percent: config.policy.useHardwarePercent == true ? (r.hardwarePercent ?? .nan) : r.percent, target: decision.effectiveLimit, calibrating: config.policy.mode == .calibration && !calibrationPending, idleUntilTarget: config.policy.keepAwakeUntilLimit == true, systemUntilTarget: config.policy.keepAwakeWithLidClosed == true, allowDisplaySleep: config.policy.allowDisplaySleep ?? true, lidClosed: lid, ownAdapterInhibited: lastHardwareAction == .forceDischarge, thermalHold: decision.thermalHold == true, fullChargeHold: decision.fullChargeHold == true)
   applyHardwareDecision(plan)
   updateMagSafe()
   if !plan.preventSystemAndLidSleep { updateSleepOverride(plan) }
   handleLidState(lid)
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
  } catch { self.error = error.localizedDescription; if config.hardwareEnabled { try? restoreChargeControl() }; try? sleepController.setPreventIdleSleep(false) }
 }
 func applyHardwareDecision(_ plan: SleepProtectionPlan, request: @escaping (String) throws -> String = HelperClient.request, setIdleSleep: ((Bool) throws -> Void)? = nil, screenCount: () -> Int = { NSScreen.screens.count }) {
  let idle = setIdleSleep ?? { try self.sleepController.setPreventIdleSleep($0) }
  guard config.hardwareEnabled else {
   do { try idle(false) } catch { self.error = error.localizedDescription }
   helperStatus = NSLocalizedString("监测模式 · 未改变充电状态", comment: ""); return
  }
  var attempted = false
  let previousDischargeExitPending = dischargeExitPending
  do {
   let context: ChargeRequestContext?
   if chargeContextEnabled {
    guard let current = ChargeRequestContext(reply:try request("chargeContext")) else { throw ChargeContextError.invalidEnvelope }
    guard !current.sleeping else { throw ChargeControlSuspension.systemSleep }
    context = current
   } else { context = nil }
   let displayCount = multiDisplaySleepEnabled ? screenCount() : 0
   let phase = automationPhase
   let scopedRequest: (String) throws -> String = { command in
    let action = self.multiDisplaySleepEnabled ? DischargeSleepRequest.wrap(command,phase:phase,screenCount:displayCount,preventDisplaySleep:plan.preventDisplaySleep) : command
    return try request(try context?.envelope(action) ?? action)
   }
   if plan.preventSystemAndLidSleep {
    guard !sleepOverrideFailed else { throw HelperError.rejected(NSLocalizedString("睡眠控制上次失败，请重新启用硬件控制后重试", comment: "")) }
    if sleepOverrideCapability == nil { inspectSleepInterfaces(request: scopedRequest) }
    guard sleepOverrideCapability == true else { throw HelperError.rejected(NSLocalizedString("此操作需要兼容的睡眠控制服务，请先更新服务", comment: "")) }
    if let firmwareControl {
     attempted = true
     try firmwareControl.prepareProtection(request:scopedRequest)
    } else if lastHardwareAction == .restore {
     // The helper requires an owned charge session before sleep protection.
     // Bootstrap with inhibition, never with charging or adapter cutoff.
     attempted = true
     _ = try scopedRequest(ChargeAction.inhibitCharge.rawValue)
     lastHardwareAction = .inhibitCharge
    }
   }
   if plan.preventIdleSleep { try idle(true) }
   if plan.preventSystemAndLidSleep {
    // Wait for required protection before changing charging or adapter input.
    let protectionCompleted = updateSleepOverride(plan, request: scopedRequest)
    guard config.hardwareEnabled else { try? idle(false); helperStatus = NSLocalizedString("控制失败", comment: ""); return }
    guard protectionCompleted else { throw ChargeControlSuspension.systemSleep }
   }
   attempted = true
   if decision.action == .forceDischarge { dischargeExitPending = true }
   if let firmwareControl {
    try firmwareControl.apply(decision.action,policy:config.policy,phase:automationPhase,request:scopedRequest)
    firmwareInspection = firmwareControl.status
    firmwareStatus = String.localizedStringWithFormat(NSLocalizedString("数值固件通道 · 睡眠目标 %@%% · 物理效果待验证", comment: ""), firmwareControl.sleepTarget.map(String.init) ?? "—")
   } else {
    _ = try scopedRequest(config.policy.stopInSleep ? "sleepPolicyOn" : "sleepPolicyOff")
    _ = try scopedRequest(decision.action.rawValue)
   }
   if !plan.preventIdleSleep { try idle(false) }
   helperStatus = NSLocalizedString("服务已确认：", comment: "") + decision.action.displayName; lastHardwareAction = decision.action
  } catch ChargeControlSuspension.systemSleep {
   dischargeExitPending = previousDischargeExitPending
   try? idle(false)
   helperStatus = ChargeControlSuspension.systemSleep.localizedDescription
  } catch {
   helperStatus = NSLocalizedString("控制失败", comment: ""); self.error = error.localizedDescription
   config.hardwareEnabled = false
   try? idle(false)
   if config.policy.mode == .calibration { calibrationPending = true }
   if attempted || firmwareControl?.mayOwnSession == true || lastHardwareAction != .restore || sleepOverrideSessionActive {
    do { try restoreChargeControl(request:request); lastHardwareAction = .restore; sleepOverrideSessionActive = false }
    catch { self.error = (self.error ?? "") + NSLocalizedString("；恢复待重试：", comment: "") + error.localizedDescription }
   }
   try? config.save()
  }
 }
 func inspectLidLock(request: () throws -> Void = ScreenLockClient.inspect) {
  do { try request(); lidLockStatus = NSLocalizedString("已检测到锁屏入口；", comment: "") + (ScreenLockClient.consoleSessionActive ? NSLocalizedString("前台登录会话可用", comment: "") : NSLocalizedString("当前前台登录会话不可用", comment: "")) + NSLocalizedString("；未请求锁屏，实际效果待验证", comment: "") }
  catch { lidLockStatus = error.localizedDescription }
 }
 func handleLidStateNotification(_ closed: Bool?, refresh: (() -> Void)? = nil) {
  guard !quitting else { return }
  if let closed {
   let changed = observedLidState != closed
   observedLidState = closed
   if changed && config.hardwareEnabled { (refresh ?? { self.refresh() })(); return }
  }
  handleLidState(closed)
 }
 func handleLidState(_ closed: Bool?, consoleActive: Bool = ScreenLockClient.consoleSessionActive, request: (() throws -> Void)? = nil) {
  guard !quitting else { return }
  let enabled = config.hardwareEnabled && config.policy.lockScreenWhenClosed == true
  guard lidLockPolicy.shouldRequest(lidClosed: closed, enabled: enabled, sleepOverrideActive: sleepOverrideSessionActive && !sleepOverrideFailed, consoleSessionActive: consoleActive) else { return }
  do { try (request ?? screenLockRequest)(); lidLockStatus = NSLocalizedString("已向系统发送锁屏请求；尚未确认锁定结果", comment: "") }
  catch { lidLockStatus = NSLocalizedString("锁屏请求失败：", comment: "") + error.localizedDescription + NSLocalizedString("；重新开合盖后可再试", comment: "") }
 }
 func inspectServiceCapabilities(request: (String) throws -> String = HelperClient.request) {
  guard !quitting else { return }
  firmwareInspection = nil
  do {
   let capabilities = try request("capabilities"); helperStatus = capabilities
   guard FirmwareHelperCapabilities.supportsNumericControl(capabilities) else {
    firmwareStatus = NSLocalizedString("当前服务或硬件未提供已恢复的数值固件通道", comment: ""); return
   }
   let reply = try request("firmwareStatus")
   guard let state = FirmwareHelperState(reply: reply) else { throw HelperError.rejected(NSLocalizedString("固件状态回复格式无效", comment: "")) }
   firmwareInspection = state
   let control = state.chargingAllowed.map { $0 ? NSLocalizedString("允许充电", comment: "") : NSLocalizedString("限制充电", comment: "") } ?? NSLocalizedString("未知", comment: "")
   let usage = usesNumericFirmware && config.hardwareEnabled ? NSLocalizedString("当前策略使用数值固件通道；物理效果待验证", comment: "") : NSLocalizedString("尚未启用数值固件控制", comment: "")
   firmwareStatus = String.localizedStringWithFormat(NSLocalizedString("固件上限 %u%% · 控制状态：%@ · ", comment: ""), UInt32(state.limit), control) + usage
  } catch { firmwareStatus = NSLocalizedString("固件检测失败：", comment: "") + error.localizedDescription; self.error = error.localizedDescription }
 }
 func inspectSleepInterfaces(request: (String) throws -> String = HelperClient.request) {
  do {
   let result = try request("capabilities")
   sleepOverrideCapability = SleepProtectionPlan.supportsHelper(result)
   sleepStatus = sleepOverrideCapability == true ? NSLocalizedString("已检测到私有接口；物理效果仍待实机验证", comment: "") : NSLocalizedString("已安装服务未提供所需睡眠接口或恢复协议，请更新服务", comment: "")
   if sleepOverrideFailed { sleepStatus += NSLocalizedString("；上次控制失败，需重新启用硬件控制后再试", comment: "") }
  } catch { sleepOverrideCapability = false; sleepStatus = error.localizedDescription }
 }
 @discardableResult func updateSleepOverride(_ plan: SleepProtectionPlan, request: (String) throws -> String = HelperClient.request) -> Bool {
  guard !quitting else { return false }
  let previouslyActive = sleepOverrideSessionActive
  do {
   if plan.preventSystemAndLidSleep && config.hardwareEnabled {
    guard !sleepOverrideFailed else { return false }
    if sleepOverrideCapability == nil { inspectSleepInterfaces(request: request) }
    guard sleepOverrideCapability == true else { throw HelperError.rejected(NSLocalizedString("所需睡眠控制接口或恢复协议不可用", comment: "")) }
    sleepOverrideSessionActive = true
    sleepStatus = try request(plan.preventDisplaySleep ? "sleepOverrideDisplayOn" : "sleepOverrideOn")
   } else if sleepOverrideSessionActive {
    _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false
    sleepStatus = NSLocalizedString("合盖睡眠控制已释放", comment: "")
   } else if !config.hardwareEnabled && sleepOverrideCapability == nil { sleepStatus = NSLocalizedString("监测模式 · 未修改睡眠设置", comment: "") }
   return true
  } catch ChargeControlSuspension.systemSleep {
   sleepOverrideSessionActive = previouslyActive
   sleepStatus = ChargeControlSuspension.systemSleep.localizedDescription
   return false
  } catch {
   sleepOverrideFailed = true; sleepStatus = NSLocalizedString("睡眠控制失败：", comment: "") + error.localizedDescription
   config.hardwareEnabled = false
   if config.policy.mode == .calibration { calibrationPending = true }
   do { try restoreChargeControl(request:request); sleepOverrideSessionActive = false; lastHardwareAction = .restore }
   catch { sleepStatus += NSLocalizedString("；恢复待重试：", comment: "") + error.localizedDescription }
   try? sleepController.setPreventIdleSleep(false); try? config.save()
   return false
  }
 }
 private func requiresNumericFirmware() throws -> Bool {
  #if arch(x86_64)
  return SMCFirmwareProbe.eligible(model:try HardwareIdentity.model(),architecture:"x86_64",internalBattery:true)
  #else
  return false
  #endif
 }
 func configureHardwareChannel(capabilities: String, numericRequired: Bool = false) throws {
  guard firmwareControl?.mayOwnSession != true else { throw HelperError.rejected(NSLocalizedString("请先完成上次数值固件会话的恢复", comment: "")) }
  if FirmwareHelperCapabilities.supportsAtomicSleepPlan(capabilities) {
   firmwareControl = try FirmwareAppSession(capabilities:capabilities)
  } else {
   guard !numericRequired, !FirmwareHelperCapabilities.supportsNumericControl(capabilities),
    capabilities.split(separator:",").contains(where: { $0.trimmingCharacters(in:.whitespaces).hasPrefix("chargeControl:") && !$0.contains("unavailable") }) else {
    throw HelperError.rejected(NSLocalizedString("此硬件需要兼容的充电协议、恢复服务和数值睡眠目标接口", comment: ""))
   }
   firmwareControl = nil
  }
  chargeContextEnabled = ChargeRequestContext.supportsHelper(capabilities)
  multiDisplaySleepEnabled = DischargeSleepRequest.supportsHelper(capabilities)
 }
 func restoreChargeControl(request: (String) throws -> String = HelperClient.request, persist: (Configuration) throws -> Void = { try $0.save() }) throws {
  if let firmwareControl {
   try firmwareControl.restore(request:request); firmwareInspection = nil; firmwareStatus = NSLocalizedString("数值固件会话已恢复 · 监测模式", comment: "")
  }
  else { _ = try request("restore") }
  try OrdinaryQuitRecovery.acknowledgeRestore(configuration:&config,persist:persist)
  quitChargeRecoveryPending = false; quitRecoveryIntentStored = false; lastHardwareAction = .restore
 }
 func enableHardware(_ enabled: Bool, request: (String) throws -> String = HelperClient.request, refresh: (() -> Void)? = nil) {
  guard !quitting else { return }
  if enabled && helperService.removalPending { error = NSLocalizedString("请先重试完整文件移除",comment:""); return }
  if enabled && settingsResetPending { error = NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停", comment: ""); return }
  if enabled { do {
   sleepOverrideFailed = false
   guard !calibrationPending else { throw HelperError.rejected(NSLocalizedString("请先选择继续或取消上次校准", comment: "")) }
   if quitChargeRecoveryPending || firmwareControl?.mayOwnSession == true { try restoreChargeControl(request:request) }
   helperStatus = try request("capabilities"); sleepOverrideCapability = SleepProtectionPlan.supportsHelper(helperStatus)
   try configureHardwareChannel(capabilities:helperStatus,numericRequired:requiresNumericFirmware()); config.hardwareEnabled = true } catch { self.error = error.localizedDescription; config.hardwareEnabled = false } }
  else { do { try restoreChargeControl(request:request); helperStatus = NSLocalizedString("服务已确认恢复", comment: ""); lastHardwareAction = .restore; config.hardwareEnabled = false } catch { self.error = String.localizedStringWithFormat(NSLocalizedString("恢复请求失败；服务会在心跳超时后尝试恢复：%@", comment: ""), error.localizedDescription); config.hardwareEnabled = false } }
  save(); (refresh ?? { self.refresh() })()
 }
 func sleep(request: (String) throws -> String = HelperClient.request) { guard !quitting, config.hardwareEnabled else { return }
  // Coordinated helpers own sleep preparation for both charge backends. App
  // notifications must not race it with an unscoped action after a wake cycle.
  if firmwareControl != nil || chargeContextEnabled { return }
  // Legacy notifications share the same ordinary ordering as the updated root.
  // Older helpers may still have their own incompatible forced-discharge fallback.
  let outcome = OrdinarySleepPreparation.perform(stopInSleep:config.policy.stopInSleep,
   sessionActive:lastHardwareAction != .restore, inhibit: {
    _ = try request("inhibitCharge"); lastHardwareAction = .inhibitCharge
   }, releaseProtection: {
    _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false
   })
  if outcome.succeeded { sleepStatus = config.policy.stopInSleep ? NSLocalizedString("睡眠充电策略已确认；睡眠保护已释放", comment: "") : NSLocalizedString("睡眠保护已释放；充电状态未修改", comment: "") }
  else { sleepStatus = OrdinarySleepPreparation.Step.allCases.compactMap { outcome.failures[$0] }.joined(separator:"；") }

 }
 func prepareForQuit(request: (String) throws -> String = HelperClient.request) throws {
  quitting = true
  var failures: [String] = []
  if sleepOverrideSessionActive { do { _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false } catch { failures.append(error.localizedDescription) } }
  if magSafeSessionActive { do { _ = try request("magSafeRestore"); magSafeSessionActive = false } catch { failures.append(error.localizedDescription) } }
  do { try sleepController.setPreventIdleSleep(false) } catch { failures.append(error.localizedDescription) }
  // A cancelled/ambiguous earlier exit must be restored before another attempt.
  if quitChargeRecoveryPending {
   do { try restoreChargeControl(request:request) } catch { failures.append(error.localizedDescription) }
  }
  if !quitChargeRecoveryPending && (config.hardwareEnabled || firmwareControl?.mayOwnSession == true || lastHardwareAction == .forceDischarge) {
   do {
    if let firmwareControl {
     try firmwareControl.prepareExit(policy:config.policy,phase:automationPhase,active:config.hardwareEnabled,request:request)
     lastHardwareAction = .restore
    }
    else {
     // Set before delivery: an error may arrive after the helper applied it.
     quitChargeRecoveryPending = true
     _ = try request(config.policy.stopOnQuit ? "retainChargeInhibit" : "restore")
     quitChargeRecoveryPending = config.policy.stopOnQuit
     lastHardwareAction = config.policy.stopOnQuit ? .inhibitCharge : .restore
    }
   }
   catch { failures.append(error.localizedDescription) }
  }
  quitCleanupPrepared = failures.isEmpty
  if !failures.isEmpty { throw HelperError.rejected(failures.joined(separator: "; ")) }
 }
 var numericExitCommitStarted: Bool { firmwareControl?.exitCommitAttempted == true }
 func renewPreparedQuit(request: (String) throws -> String = HelperClient.request) throws {
  try firmwareControl?.renewExitPreparation(request:request)
 }
 func commitQuit(request: (String) throws -> String = HelperClient.request) throws {
  try firmwareControl?.commitExit(request:request)
 }
 func cancelQuit(request: (String) throws -> String = HelperClient.request, persist: (Configuration) throws -> Void = { try $0.save() }, refresh: (() -> Void)? = nil) {
  guard !numericExitCommitStarted else {
   error = NSLocalizedString("退出确认已开始，可能已经写入最终限额。可重试确认或仍然退出；此时取消无法保证恢复原值。",comment:""); return
  }
  // Never resume a discharge/calibration automatically after a cancelled exit.
  let needsRecovery = quitChargeRecoveryPending || config.pendingOrdinaryQuitRecovery == true || firmwareControl?.mayOwnSession == true || lastHardwareAction != .restore
  let ordinary = needsRecovery && (firmwareControl == nil || config.pendingOrdinaryQuitRecovery == true)
  config.hardwareEnabled = false
  if config.policy.mode == .calibration { calibrationPending = true }
  var persistenceFailure: String?
  do {
   if ordinary {
    quitChargeRecoveryPending = true
    try OrdinaryQuitRecovery.begin(configuration:&config,persist:persist)
    quitRecoveryIntentStored = true
   } else { try persist(config) }
  } catch { persistenceFailure = error.localizedDescription }
  var recoveryFailure: String?
  if needsRecovery {
   do {
    try restoreChargeControl(request:request,persist:persist)
    if ordinary { persistenceFailure = nil }
   }
   catch { quitChargeRecoveryPending = true; recoveryFailure = error.localizedDescription }
  }
  quitting = false; quitCleanupPrepared = false
  error = NSLocalizedString("已取消退出，充电控制已关闭；请确认电源状态后手动重新启用。", comment: "")
  if let recoveryFailure { error! += NSLocalizedString("恢复仍待重试：", comment: "") + recoveryFailure }
  if let persistenceFailure { error! += "\n"+persistenceFailure }
  (refresh ?? { self.refresh() })()
 }
 func cleanupOnQuit() { if needsQuitPreparation && !quitCleanupPrepared && !numericExitCommitStarted { try? restoreChargeControl() } }
 func quit() { NSApp.terminate(nil) }

 func handleURL(_ url: URL, refresh: (() -> Void)? = nil) {
  guard !quitting else { return }
  guard !settingsResetPending else { error = NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停",comment:""); return }
  guard url.scheme == "opencharge", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
  if url.host == "limit", let text = components.queryItems?.first(where: { $0.name == "value" })?.value, let value = Double(text), value.isFinite, (20...100).contains(value) {
   guard config.policy.mode != .calibration, !calibrationPending else { error = NSLocalizedString("校准期间不能修改上限",comment:""); return }
   config.setChargeLimit(value); save(); (refresh ?? { self.refresh() })()
  }
  else if url.host == "mode", let value = components.queryItems?.first(where: { $0.name == "value" })?.value, let mode = ChargeMode(rawValue: value) { changeMode(mode) }
  else { error = NSLocalizedString("自动化 URL 参数无效", comment: "") }
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
 func confirmSettingsReset(confirm: @MainActor () -> Bool = SettingsResetConfirmation.confirm) {
  guard allowChargeSettingsEdit(), confirm() else { return }
  do { try resetSettings() } catch { self.error = error.localizedDescription }
 }
 /// Stop policy actuation durably before releasing owned sessions. A cleanup or
 /// storage failure retains settings for retry; no preference reset is reported.
 func resetSettings(request: (String) throws -> String = HelperClient.request,
                    releaseIdle: (() throws -> Void)? = nil,
                    persist: (Configuration) throws -> Void = { try $0.save() },
                    applyDock: @MainActor (Bool) -> Void = { NSApp.setActivationPolicy($0 ? .regular : .accessory) }) throws {
  guard allowChargeSettingsEdit() else { throw HelperServiceError.ineligible(error ?? "") }
  guard !updates.busy else { throw HelperServiceError.ineligible(NSLocalizedString("请等待更新检查或下载结束后再重置设置", comment: "")) }
  settingsResetStatus = nil; settingsResetPending = true
  let restoreCharge = quitChargeRecoveryPending || config.hardwareEnabled || firmwareControl?.mayOwnSession == true || lastHardwareAction != .restore || dischargeExitPending
  var stopped = config; stopped.hardwareEnabled = false; stopped.systemActionsEnabled = false
  // Stop this live model even when storage fails, so its next timer cannot rearm control.
  config = stopped
  if config.policy.mode == .calibration { calibrationPending = true }
  try persist(stopped)
  var failures: [String] = []
  if restoreCharge {
   do { try restoreChargeControl(request:request); lastHardwareAction = .restore; dischargeExitPending = false }
   catch { failures.append(error.localizedDescription) }
  }
  if magSafeSessionActive {
   do { _ = try request("magSafeRestore"); magSafeSessionActive = false }
   catch { failures.append(error.localizedDescription) }
  }
  if sleepOverrideSessionActive {
   do { _ = try request("sleepOverrideRestore"); sleepOverrideSessionActive = false }
   catch { failures.append(error.localizedDescription) }
  }
  do { try (releaseIdle ?? { try self.sleepController.setPreventIdleSleep(false) })() }
  catch { failures.append(error.localizedDescription) }
  guard failures.isEmpty else { throw HelperServiceError.ineligible(NSLocalizedString("恢复尚未完成，设置已保留；请解决问题后重试：", comment: "")+failures.joined(separator:"; ")) }
  // Observation records are not preferences. Preserve their factual history.
  var fresh = Configuration(); fresh.systemActionsEnabled = false
  fresh.lastCalibration = stopped.lastCalibration; fresh.scheduleHistory = stopped.scheduleHistory
  try persist(fresh)
  config = fresh; settingsResetPending = false; engine = ChargeEngine(); appliedChargeLimitChangeID = nil
  calibration = .idle; calibrationPending = false; firmwareControl = nil
  firmwareInspection = nil; lastHardwareAction = .restore; dischargeExitPending = false
  magSafeSelection = nil; magSafePolicyFailed = false
  sleepOverrideFailed = false; sleepOverrideCapability = nil
  chargeContextEnabled = false; multiDisplaySleepEnabled = false; lidLockPolicy = LidLockPolicy()
  AppPreferenceReset.removeOverrides(from:settingsDefaults)
  dashboardPreferences.reloadAfterReset(); popoverPreferences.reloadAfterReset(); menuBarActions.reloadAfterReset(); updates.reloadAfterReset()
  applyDock(settingsDefaults.object(forKey:"showDockIcon") as? Bool ?? true)
  decision = Decision(.restore,NSLocalizedString("监测模式", comment: ""),limit:config.policy.limit)
  helperStatus = NSLocalizedString("监测模式", comment: "")
  firmwareStatus = NSLocalizedString("尚未检测数值固件通道", comment: "")
  error = nil; settingsResetStatus = NSLocalizedString("已恢复默认设置，充电控制保持关闭", comment: "")
  syncDashboard()
 }
 func backupConfiguration() {
  let panel = NSSavePanel(); panel.nameFieldStringValue = "opencharge-settings.json"; panel.allowedContentTypes = [.json]
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do { try ConfigurationBackup(configuration: config).encoded().write(to: url, options: .atomic) }
  catch { self.error = error.localizedDescription }
 }
 func restoreConfiguration() {
  guard !quitting, allowChargeSettingsEdit() else { return }
  guard !settingsResetPending else { error = NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停", comment: ""); return }
  let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do {
   let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
   guard size <= 1_048_576 else { throw ConfigurationBackupError.tooLarge }
   let restored = try ConfigurationBackup.restored(from: Data(contentsOf: url))
   guard allowChargeSettingsEdit() else { return }
   // Validate before touching current hardware or configuration.
   if magSafeSessionActive { _ = try HelperClient.request("magSafeRestore"); magSafeSessionActive = false }
   magSafeSelection = nil; magSafePolicyFailed = false
   if quitChargeRecoveryPending || config.hardwareEnabled || firmwareControl?.mayOwnSession == true { try restoreChargeControl() }
   try sleepController.setPreventIdleSleep(false)
   try restored.save(); config = restored; engine = ChargeEngine(sailingCheckpoint: restored.sailingCheckpoint); appliedChargeLimitChangeID = restored.chargeLimitChangeID; calibrationPending = false
   lastHardwareAction = .restore; refresh()
  } catch { self.error = error.localizedDescription }
 }
 func registerHelperService() async {
  guard !quitting else { return }
  do { try await helperService.register() } catch { self.error = error.localizedDescription }
 }
 func removeHelperService(deleteFiles: Bool = false, request: (String) throws -> String = HelperClient.request) async {
  guard !quitting else { return }
  do {
   if deleteFiles { try helperService.validateFullRemoval() } else { try helperService.validateRemoval() }
   // SMAppService unregister terminates the daemon: restore while its journal is alive.
   if quitChargeRecoveryPending || (!deleteFiles && helperService.status == .enabled) || config.hardwareEnabled || firmwareControl?.mayOwnSession == true || magSafeSessionActive || sleepOverrideSessionActive {
    try restoreChargeControl(request:request)
    _ = try request("magSafeRestore")
   }
   config.hardwareEnabled = false; magSafeSessionActive = false; magSafeSelection = nil
   try sleepController.setPreventIdleSleep(false); save()
   if deleteFiles { try await helperService.uninstall(); helperStatus = NSLocalizedString("旧服务及安装文件已移除",comment:"") }
   else { try await helperService.unregister(); helperStatus = NSLocalizedString("硬件服务已注销", comment: "") }
   error = nil
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
