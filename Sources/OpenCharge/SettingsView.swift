import SwiftUI
import AppKit
import Charts
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
 @State private var loginError: String?
 var body: some View {
  ChargeSettingsLockNotice(model: m)
  Card(String(localized:"界面与能耗")) {
   PopoverActivityView(monitor: m.energyMonitor, popoverVisible: m.popoverVisible)
   Text(String(localized:"只有可见界面需要能耗列表时才读取；暂停界面更新不会停止充电策略和定时任务。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"硬件服务")) {
   Toggle(String(localized:"启用真实充电控制"), isOn: Binding(get: { m.config.hardwareEnabled }, set: { m.enableHardware($0) }))
   Text(m.helperStatus).foregroundStyle(.secondary)
   HelperServiceView(service: m.helperService)
   Text(String(localized:"服务仅接受当前登录用户的固定动作，45 秒没有心跳时尝试恢复系统充电。安装服务不会自动开启控制。")).font(.caption).foregroundStyle(.secondary)
   Button(String(localized:"检测服务能力")) { m.inspectServiceCapabilities() }
   Text(m.firmwareStatus).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"MagSafe 灯光")) {
   Picker(String(localized:"自动灯光"), selection: Binding(get: { m.config.magSafeMode ?? .system }, set: { m.config.magSafeMode = $0; m.save(); m.useMagSafePolicy() })) { ForEach(MagSafeMode.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   Toggle(String(localized:"主动放电时橙色闪烁"), isOn: Binding(get: { m.config.magSafeBlinkDischarge ?? true }, set: { m.config.magSafeBlinkDischarge = $0; m.save(); m.useMagSafePolicy() }))
   Toggle(String(localized:"睡眠期间熄灭灯光"), isOn: Binding(get: { m.config.magSafeOffDuringSleep ?? false }, set: { m.config.magSafeOffDuringSleep = $0; m.save(); m.useMagSafePolicy() }))
   Text(m.magSafeStatus).font(.callout).foregroundStyle(.secondary)
   HStack { Button(String(localized:"读取状态")) { m.inspectMagSafe() }; Button(String(localized:"绿色")) { m.setMagSafe(.green) }; Button(String(localized:"橙色")) { m.setMagSafe(.orange) }; Button(String(localized:"闪烁橙色")) { m.setMagSafe(.orangeBlinking) }; Button(String(localized:"熄灭")) { m.setMagSafe(.off) }; Button(String(localized:"恢复原值")) { m.setMagSafe(nil) }; Button(String(localized:"使用自动策略")) { m.useMagSafePolicy() } }
   Text(String(localized:"需要服务及可识别的 ACLC 硬件键。手动颜色优先于自动指示；睡眠熄灯优先于手动颜色。应用运行时续期，退出或 45 秒无心跳后尝试恢复原值。灯光效果依赖适配器，尚未完成实机验收。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"低电量模式")) {
   Toggle(String(localized:"允许定时任务与菜单栏快捷操作改变系统模式"), isOn: Binding(get: { m.config.systemActionsEnabled ?? false }, set: { enabled in
    if enabled { do { m.lowPowerStatus = try HelperClient.request("lowPowerStatus"); m.config.systemActionsEnabled = true } catch { m.error = error.localizedDescription; m.config.systemActionsEnabled = false } }
    else { m.config.systemActionsEnabled = false }
    m.save()
   }))
   Text(m.lowPowerStatus).font(.callout).foregroundStyle(.secondary)
   HStack { Button(String(localized:"全部开启")) { m.setLowPower(true) }; Button(String(localized:"全部关闭")) { m.setLowPower(false) }; Button(String(localized:"读取状态")) { m.inspectLowPower() } }
   HStack { Text(String(localized:"电池供电")); Button(String(localized:"开启")) { m.setLowPower(true, source: "battery") }; Button(String(localized:"关闭")) { m.setLowPower(false, source: "battery") }; Spacer() }
   HStack { Text(String(localized:"电源适配器")); Button(String(localized:"开启")) { m.setLowPower(true, source: "ac") }; Button(String(localized:"关闭")) { m.setLowPower(false, source: "ac") }; Spacer() }
   Text(String(localized:"需要硬件服务。此项是持久系统偏好，仅明确操作或定时任务会改变；退出应用不会自动重置。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"外观")) {
   MenuBarActionSettingsView(preferences: m.menuBarActions)
   Picker(String(localized:"主题"), selection: $appearance) { Text(String(localized:"跟随系统")).tag("system"); Text(String(localized:"浅色")).tag("light"); Text(String(localized:"深色")).tag("dark") }
   Picker(String(localized:"菜单栏显示"), selection: $menuDisplay) { Text(String(localized:"动态状态与电量")).tag("status"); Text(String(localized:"仅图标")).tag("icon"); Text(String(localized:"macOS 电量")).tag("percentage"); Text(String(localized:"硬件电量")).tag("hardware") }
   Picker(String(localized:"菜单栏图标样式"), selection: $menuIconStyle) { ForEach(MenuIconStyle.allCases) { Text($0.title).tag($0) } }
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Toggle(String(localized:"低电量模式时图标显示黄色"), isOn: $menuTintLowPower)
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Text(String(localized:"电池图形按 macOS 电量填充；接电状态来自实际读数。染色只跟随系统低电量模式，不会更改电源设置。")).font(.caption).foregroundStyle(.secondary)
   Toggle(String(localized:"显示 Dock 图标"), isOn: $showDockIcon).onChange(of: showDockIcon) { value in NSApp.setActivationPolicy(value ? .regular : .accessory) }
  }
  PopoverSettingsView(preferences: m.popoverPreferences, preview: { m.openPopoverPreview() }, openEditor: { m.openStatusPopoverEditor?() })
  DashboardSettingsView(preferences: m.dashboardPreferences)
  Card(String(localized:"系统与隐私")) {
   Toggle(String(localized:"记录本地电池历史"), isOn: $m.config.historyEnabled).onChange(of: m.config.historyEnabled) { _ in m.save() }
   Toggle(String(localized:"状态变化通知"), isOn: $m.config.notifications).onChange(of: m.config.notifications) { enabled in m.save(); if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } } }
   Button(SMAppService.mainApp.status == .enabled ? String(localized:"关闭登录启动") : String(localized:"启用登录启动")) { do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { loginError = error.localizedDescription } }
   if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
   Text(String(localized:"所有记录保存在本机，不上传遥测。当前系统：\(ProcessInfo.processInfo.operatingSystemVersionString)")).font(.caption).foregroundStyle(.secondary)
  }
  UpdateView(updates: m.updates)
  Card(String(localized:"本地诊断")) {
   Button(String(localized:"导出诊断文件…")) { m.exportDiagnostics() }
   Text(String(localized:"包含应用与系统版本、机型、当前电池读数、策略摘要和服务状态。不包含序列号、用户名、路径、定时任务日期或历史明细；文件保存在你选择的位置，不自动上传。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"配置备份")) {
   HStack { Button(String(localized:"导出配置备份")) { m.backupConfiguration() }; Button(String(localized:"从备份恢复…")) { m.restoreConfiguration() }.disabled(m.settingsLocked) }
   Text(String(localized:"备份包含策略和时间表。恢复会替换当前配置，进入监测模式并停用导入的任务；重新启用前请检查时间和操作。电池历史不在备份中。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"兼容性与边界")) {
   Text(String(localized:"请先退出其他充电管理程序，再启用硬件控制；多个控制器可能相互覆盖。"))
   Text(String(localized:"MagSafe LED 已实现自动指示、闪烁与睡眠熄灯策略，仍待实机验证；关机策略尚未完成；Shortcuts 的 11 个操作已被系统发现，4 个只读操作已实测；不会显示虚假的成功状态。"))
   Text(String(localized:"睡眠由系统通知协调；可选退出后保持停充。合盖强制保持唤醒及实际睡眠充电效果仍待硬件验证。"))
   Text(String(localized:"OpenCharge \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") · MIT · 本地运行 · 无账户 · 无遥测")).font(.caption).foregroundStyle(.secondary)
  }.font(.callout)
 }
}

struct MenuBarActionSettingsView: View {
 @ObservedObject var preferences: MenuBarActionPreferences
 var body: some View {
  Picker(String(localized:"菜单栏右键"), selection: $preferences.rightClick) {
   ForEach(MenuBarRightClickAction.allCases) { Text($0.title).tag($0) }
  }
  Text(String(localized:"左键与 ⌘3 始终切换弹窗。充电切换会将日常上限设为当前电量或 100%；低电量模式需要上方系统模式许可与服务支持。")).font(.caption).foregroundStyle(.secondary)
 }
}

struct PopoverActivityView: View {
 @ObservedObject var monitor: EnergyMonitor
 let popoverVisible: Bool
 var body: some View {
  HStack {
   Label(monitor.paused ? String(localized:"能耗列表已暂停") : String(localized:"能耗列表按需更新"), systemImage: monitor.paused ? "pause.circle" : "arrow.clockwise")
   Spacer()
   Text(popoverVisible ? String(localized:"弹窗处于前台") : String(localized:"弹窗未在前台")).foregroundStyle(.secondary)
  }
 }
}

struct HelperServiceView: View {
 @ObservedObject var service: HelperService
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text(service.statusText).font(.callout)
   Text(service.preflightText).font(.caption).foregroundStyle(.secondary)
   HStack {
    Button(String(localized:"注册硬件服务")) { do { try service.register() } catch { m.error = error.localizedDescription } }.disabled(!service.registrationAllowed || service.busy)
    Button(String(localized:"刷新状态")) { service.refresh() }
    Button(String(localized:"查看安装说明")) { if let url = Bundle.main.url(forResource: "HELPER-SETUP", withExtension: "md") { NSWorkspace.shared.open(url) } }
    if service.status == .requiresApproval { Button(String(localized:"打开系统批准设置")) { service.openApprovalSettings() } }
    if !service.legacyInstalled && (service.status == .enabled || service.status == .requiresApproval) { Button(String(localized:"注销服务"), role: .destructive) { Task { await m.removeHelperService() } }.disabled(service.busy) }
   }
  }.onAppear { service.refresh() }
 }
}
