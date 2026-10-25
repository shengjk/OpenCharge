import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct SettingsView: View {
 @EnvironmentObject var m: ChargeModel
 @AppStorage("appearance") private var appearance = "system"
 @AppStorage("menuDisplay") private var menuDisplay = "status"
 @AppStorage("menuIconStyle") private var menuIconStyle = MenuIconStyle.status
 @AppStorage("menuTintLowPower") private var menuTintLowPower = false
 @AppStorage("showDockIcon") private var showDockIcon = true
 @StateObject private var loginStartup = LoginStartup()
 var body: some View {
  ChargeSettingsLockNotice(model: m)
  Card(NSLocalizedString("界面与能耗", comment: "")) {
   PopoverActivityView(monitor: m.energyMonitor, popoverVisible: m.popoverVisible)
   Text(NSLocalizedString("只有可见界面需要能耗列表时才读取；暂停界面更新不会停止充电策略和定时任务。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("硬件服务", comment: "")) {
   Toggle(NSLocalizedString("启用真实充电控制", comment: ""), isOn: Binding(get: { m.config.hardwareEnabled }, set: { m.enableHardware($0) }))
   Text(m.helperStatus).presentationSecondary()
   HelperServiceView(service: m.helperService)
   Text(NSLocalizedString("服务仅接受当前登录用户的固定动作，45 秒没有心跳时尝试恢复系统充电。安装服务不会自动开启控制。", comment: "")).font(.caption).presentationSecondary()
   Button(NSLocalizedString("检测服务能力", comment: "")) { m.inspectServiceCapabilities() }
   Text(m.firmwareStatus).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("MagSafe 灯光", comment: "")) {
   Picker(NSLocalizedString("自动灯光", comment: ""), selection: Binding(get: { m.config.magSafeMode ?? .system }, set: { m.config.magSafeMode = $0; m.save(); m.useMagSafePolicy() })) { ForEach(MagSafeMode.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   Toggle(NSLocalizedString("主动放电时橙色闪烁", comment: ""), isOn: Binding(get: { m.config.magSafeBlinkDischarge ?? true }, set: { m.config.magSafeBlinkDischarge = $0; m.save(); m.useMagSafePolicy() }))
   Toggle(NSLocalizedString("睡眠期间熄灭灯光", comment: ""), isOn: Binding(get: { m.config.magSafeOffDuringSleep ?? false }, set: { m.config.magSafeOffDuringSleep = $0; m.save(); m.useMagSafePolicy() }))
   Text(m.magSafeStatus).font(.callout).presentationSecondary()
   HStack { Button(NSLocalizedString("读取状态", comment: "")) { m.inspectMagSafe() }; Button(NSLocalizedString("绿色", comment: "")) { m.setMagSafe(.green) }; Button(NSLocalizedString("橙色", comment: "")) { m.setMagSafe(.orange) }; Button(NSLocalizedString("闪烁橙色", comment: "")) { m.setMagSafe(.orangeBlinking) }; Button(NSLocalizedString("熄灭", comment: "")) { m.setMagSafe(.off) }; Button(NSLocalizedString("恢复原值", comment: "")) { m.setMagSafe(nil) }; Button(NSLocalizedString("使用自动策略", comment: "")) { m.useMagSafePolicy() } }
   Text(NSLocalizedString("需要服务及可识别的 ACLC 硬件键。手动颜色优先于自动指示；睡眠熄灯优先于手动颜色。应用运行时续期，退出或 45 秒无心跳后尝试恢复原值。灯光效果依赖适配器，尚未完成实机验收。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("低电量模式", comment: "")) {
   Toggle(NSLocalizedString("允许定时任务与菜单栏快捷操作改变系统模式", comment: ""), isOn: Binding(get: { m.config.systemActionsEnabled ?? false }, set: { enabled in
    if enabled { do { m.lowPowerStatus = try HelperClient.request("lowPowerStatus"); m.config.systemActionsEnabled = true } catch { m.error = error.localizedDescription; m.config.systemActionsEnabled = false } }
    else { m.config.systemActionsEnabled = false }
    m.save()
   }))
   Text(m.lowPowerStatus).font(.callout).presentationSecondary()
   HStack { Button(NSLocalizedString("全部开启", comment: "")) { m.setLowPower(true) }; Button(NSLocalizedString("全部关闭", comment: "")) { m.setLowPower(false) }; Button(NSLocalizedString("读取状态", comment: "")) { m.inspectLowPower() } }
   HStack { Text(NSLocalizedString("电池供电", comment: "")); Button(NSLocalizedString("开启", comment: "")) { m.setLowPower(true, source: "battery") }; Button(NSLocalizedString("关闭", comment: "")) { m.setLowPower(false, source: "battery") }; Spacer() }
   HStack { Text(NSLocalizedString("电源适配器", comment: "")); Button(NSLocalizedString("开启", comment: "")) { m.setLowPower(true, source: "ac") }; Button(NSLocalizedString("关闭", comment: "")) { m.setLowPower(false, source: "ac") }; Spacer() }
   Text(NSLocalizedString("需要硬件服务。此项是持久系统偏好，仅明确操作或定时任务会改变；退出应用不会自动重置。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("外观", comment: "")) {
   MenuBarActionSettingsView(preferences: m.menuBarActions)
   Picker(NSLocalizedString("主题", comment: ""), selection: $appearance) { Text(NSLocalizedString("跟随系统", comment: "")).tag("system"); Text(NSLocalizedString("浅色", comment: "")).tag("light"); Text(NSLocalizedString("深色", comment: "")).tag("dark") }
   Picker(NSLocalizedString("菜单栏显示", comment: ""), selection: $menuDisplay) { Text(NSLocalizedString("动态状态与电量", comment: "")).tag("status"); Text(NSLocalizedString("仅图标", comment: "")).tag("icon"); Text(NSLocalizedString("macOS 电量", comment: "")).tag("percentage"); Text(NSLocalizedString("硬件电量", comment: "")).tag("hardware") }
   Picker(NSLocalizedString("菜单栏图标样式", comment: ""), selection: $menuIconStyle) { ForEach(MenuIconStyle.allCases) { Text($0.title).tag($0) } }
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Toggle(NSLocalizedString("低电量模式时图标显示黄色", comment: ""), isOn: $menuTintLowPower)
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Text(NSLocalizedString("电池图形按 macOS 电量填充；接电状态来自实际读数。染色只跟随系统低电量模式，不会更改电源设置。", comment: "")).font(.caption).presentationSecondary()
   Toggle(NSLocalizedString("显示 Dock 图标", comment: ""), isOn: $showDockIcon).onChange(of: showDockIcon) { value in NSApp.setActivationPolicy(value ? .regular : .accessory) }
  }
  PopoverSettingsView(preferences: m.popoverPreferences, preview: { m.openPopoverPreview() }, openEditor: { m.openStatusPopoverEditor?() })
  DashboardSettingsView(preferences: m.dashboardPreferences)
  Card(NSLocalizedString("系统与隐私", comment: "")) {
   Toggle(NSLocalizedString("记录本地电池历史", comment: ""), isOn: $m.config.historyEnabled).onChange(of: m.config.historyEnabled) { _ in m.save() }
   Toggle(NSLocalizedString("状态变化通知", comment: ""), isOn: $m.config.notifications).onChange(of: m.config.notifications) { enabled in m.save(); if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } } }
   Button(loginStartup.enabled == true ? NSLocalizedString("关闭登录启动", comment: "") : NSLocalizedString("启用登录启动", comment: "")) { loginStartup.toggle() }
    .disabled(loginStartup.enabled == nil)
    .onAppear { loginStartup.reload() }
    .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in loginStartup.reload() }
   if let error = loginStartup.error { Text(error).font(.caption).presentationOrange() }
   Text(NSLocalizedString("登录启动设置将在下次登录时生效。", comment: "")).font(.caption).presentationSecondary()
   Text(String.localizedStringWithFormat(NSLocalizedString("所有记录保存在本机，不上传遥测。当前系统：%@", comment: ""), ProcessInfo.processInfo.operatingSystemVersionString)).font(.caption).presentationSecondary()
  }
  UpdateView(updates: m.updates)
  Card(NSLocalizedString("本地诊断", comment: "")) {
   Button(NSLocalizedString("导出诊断文件…", comment: "")) { m.exportDiagnostics() }
   Text(NSLocalizedString("包含应用与系统版本、机型、当前电池读数、策略摘要和服务状态。不包含序列号、用户名、路径、定时任务日期或历史明细；文件保存在你选择的位置，不自动上传。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("配置备份", comment: "")) {
   HStack { Button(NSLocalizedString("导出配置备份", comment: "")) { m.backupConfiguration() }; Button(NSLocalizedString("从备份恢复…", comment: "")) { m.restoreConfiguration() }.disabled(m.settingsLocked) }
   Text(NSLocalizedString("备份包含策略和时间表。恢复会替换当前配置，进入监测模式并停用导入的任务；重新启用前请检查时间和操作。电池历史不在备份中。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("兼容性与边界", comment: "")) {
   Text(NSLocalizedString("请先退出其他充电管理程序，再启用硬件控制；多个控制器可能相互覆盖。", comment: ""))
   Text(NSLocalizedString("MagSafe LED 已实现自动指示、闪烁与睡眠熄灯策略，仍待实机验证；关机策略尚未完成；Shortcuts 的 11 个操作已被系统发现，4 个只读操作已实测；不会显示虚假的成功状态。", comment: ""))
   Text(NSLocalizedString("睡眠由系统通知协调；可选退出后保持停充。合盖强制保持唤醒及实际睡眠充电效果仍待硬件验证。", comment: ""))
   Text(String.localizedStringWithFormat(NSLocalizedString("OpenCharge %@ · MIT · 本地运行 · 无账户 · 无遥测", comment: ""), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")).font(.caption).presentationSecondary()
  }.font(.callout)
 }
}

struct MenuBarActionSettingsView: View {
 @ObservedObject var preferences: MenuBarActionPreferences
 var body: some View {
  Picker(NSLocalizedString("菜单栏右键", comment: ""), selection: $preferences.rightClick) {
   ForEach(MenuBarRightClickAction.allCases) { Text($0.title).tag($0) }
  }
  Text(NSLocalizedString("左键与 ⌘3 始终切换弹窗。充电切换会将日常上限设为当前电量或 100%；低电量模式需要上方系统模式许可与服务支持。", comment: "")).font(.caption).presentationSecondary()
 }
}

struct PopoverActivityView: View {
 @ObservedObject var monitor: EnergyMonitor
 let popoverVisible: Bool
 var body: some View {
  HStack {
   Label(monitor.paused ? NSLocalizedString("能耗列表已暂停", comment: "") : NSLocalizedString("能耗列表按需更新", comment: ""), systemImage: monitor.paused ? "pause.circle" : "arrow.clockwise")
   Spacer()
   Text(popoverVisible ? NSLocalizedString("弹窗处于前台", comment: "") : NSLocalizedString("弹窗未在前台", comment: "")).presentationSecondary()
  }
 }
}

struct HelperServiceView: View {
 @ObservedObject var service: HelperService
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text(service.statusText).font(.callout)
   Text(service.preflightText).font(.caption).presentationSecondary()
   HStack {
    Button(NSLocalizedString("注册硬件服务", comment: "")) { do { try service.register() } catch { m.error = error.localizedDescription } }.disabled(!service.registrationAllowed || service.busy)
    Button(NSLocalizedString("刷新状态", comment: "")) { service.refresh() }
    Button(NSLocalizedString("查看安装说明", comment: "")) { if let url = Bundle.main.url(forResource: "HELPER-SETUP", withExtension: "md") { NSWorkspace.shared.open(url) } }
    if service.status == .requiresApproval { Button(NSLocalizedString("打开系统批准设置", comment: "")) { service.openApprovalSettings() } }
    if !service.legacyInstalled && (service.status == .enabled || service.status == .requiresApproval) { DestructiveButton(NSLocalizedString("注销服务", comment: "")) { Task { await m.removeHelperService() } }.disabled(service.busy) }
   }
  }.onAppear { service.refresh() }
 }
}
