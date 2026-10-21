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
  Card("界面与能耗") {
   PopoverActivityView(monitor: m.energyMonitor, popoverVisible: m.popoverVisible)
   Text("只有可见界面需要能耗列表时才读取；暂停界面更新不会停止充电策略和定时任务。").font(.caption).foregroundStyle(.secondary)
  }
  Card("硬件服务") {
   Toggle("启用真实充电控制", isOn: Binding(get: { m.config.hardwareEnabled }, set: { m.enableHardware($0) }))
   Text(m.helperStatus).foregroundStyle(.secondary)
   HelperServiceView(service: m.helperService)
   Text("服务仅接受当前登录用户的固定动作，45 秒没有心跳时尝试恢复系统充电。安装服务不会自动开启控制。").font(.caption).foregroundStyle(.secondary)
   Button("检测服务能力") { do { m.helperStatus = try HelperClient.request("capabilities") } catch { m.error = error.localizedDescription } }
  }
  Card("MagSafe 灯光") {
   Picker("自动灯光", selection: Binding(get: { m.config.magSafeMode ?? .system }, set: { m.config.magSafeMode = $0; m.save(); m.useMagSafePolicy() })) { ForEach(MagSafeMode.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   Toggle("主动放电时橙色闪烁", isOn: Binding(get: { m.config.magSafeBlinkDischarge ?? true }, set: { m.config.magSafeBlinkDischarge = $0; m.save(); m.useMagSafePolicy() }))
   Toggle("睡眠期间熄灭灯光", isOn: Binding(get: { m.config.magSafeOffDuringSleep ?? false }, set: { m.config.magSafeOffDuringSleep = $0; m.save(); m.useMagSafePolicy() }))
   Text(m.magSafeStatus).font(.callout).foregroundStyle(.secondary)
   HStack { Button("读取状态") { m.inspectMagSafe() }; Button("绿色") { m.setMagSafe(.green) }; Button("橙色") { m.setMagSafe(.orange) }; Button("闪烁橙色") { m.setMagSafe(.orangeBlinking) }; Button("熄灭") { m.setMagSafe(.off) }; Button("恢复原值") { m.setMagSafe(nil) }; Button("使用自动策略") { m.useMagSafePolicy() } }
   Text("需要服务及可识别的 ACLC 硬件键。手动颜色优先于自动指示；睡眠熄灯优先于手动颜色。应用运行时续期，退出或 45 秒无心跳后尝试恢复原值。灯光效果依赖适配器，尚未完成实机验收。").font(.caption).foregroundStyle(.secondary)
  }
  Card("低电量模式") {
   Toggle("允许定时任务改变系统模式", isOn: Binding(get: { m.config.systemActionsEnabled ?? false }, set: { enabled in
    if enabled { do { m.lowPowerStatus = try HelperClient.request("lowPowerStatus"); m.config.systemActionsEnabled = true } catch { m.error = error.localizedDescription; m.config.systemActionsEnabled = false } }
    else { m.config.systemActionsEnabled = false }
    m.save()
   }))
   Text(m.lowPowerStatus).font(.callout).foregroundStyle(.secondary)
   HStack { Button("全部开启") { m.setLowPower(true) }; Button("全部关闭") { m.setLowPower(false) }; Button("读取状态") { m.inspectLowPower() } }
   HStack { Text("电池供电"); Button("开启") { m.setLowPower(true, source: "battery") }; Button("关闭") { m.setLowPower(false, source: "battery") }; Spacer() }
   HStack { Text("电源适配器"); Button("开启") { m.setLowPower(true, source: "ac") }; Button("关闭") { m.setLowPower(false, source: "ac") }; Spacer() }
   Text("需要硬件服务。此项是持久系统偏好，仅明确操作或定时任务会改变；退出应用不会自动重置。").font(.caption).foregroundStyle(.secondary)
  }
  Card("外观") {
   Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
   Picker("菜单栏显示", selection: $menuDisplay) { Text("动态状态与电量").tag("status"); Text("仅图标").tag("icon"); Text("macOS 电量").tag("percentage"); Text("硬件电量").tag("hardware") }
   Picker("菜单栏图标样式", selection: $menuIconStyle) { ForEach(MenuIconStyle.allCases) { Text($0.title).tag($0) } }
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Toggle("低电量模式时图标显示黄色", isOn: $menuTintLowPower)
    .disabled(menuDisplay == "percentage" || menuDisplay == "hardware")
   Text("电池图形按 macOS 电量填充；接电状态来自实际读数。染色只跟随系统低电量模式，不会更改电源设置。").font(.caption).foregroundStyle(.secondary)
   Toggle("显示 Dock 图标", isOn: $showDockIcon).onChange(of: showDockIcon) { value in NSApp.setActivationPolicy(value ? .regular : .accessory) }
  }
  PopoverSettingsView(preferences: m.popoverPreferences, preview: { m.openPopoverPreview() }, openEditor: { m.openStatusPopoverEditor?() })
  DashboardSettingsView(preferences: m.dashboardPreferences)
  Card("系统与隐私") {
   Toggle("记录本地电池历史", isOn: $m.config.historyEnabled).onChange(of: m.config.historyEnabled) { _ in m.save() }
   Toggle("状态变化通知", isOn: $m.config.notifications).onChange(of: m.config.notifications) { enabled in m.save(); if enabled { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } } }
   Button(SMAppService.mainApp.status == .enabled ? "关闭登录启动" : "启用登录启动") { do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { loginError = error.localizedDescription } }
   if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
   Text("所有记录保存在本机，不上传遥测。当前系统：\(ProcessInfo.processInfo.operatingSystemVersionString)").font(.caption).foregroundStyle(.secondary)
  }
  UpdateView(updates: m.updates)
  Card("本地诊断") {
   Button("导出诊断文件…") { m.exportDiagnostics() }
   Text("包含应用与系统版本、机型、当前电池读数、策略摘要和服务状态。不包含序列号、用户名、路径、定时任务日期或历史明细；文件保存在你选择的位置，不自动上传。").font(.caption).foregroundStyle(.secondary)
  }
  Card("配置备份") {
   HStack { Button("导出配置备份") { m.backupConfiguration() }; Button("从备份恢复…") { m.restoreConfiguration() } }
   Text("备份包含策略和时间表。恢复会替换当前配置，进入监测模式并停用导入的任务；重新启用前请检查时间和操作。电池历史不在备份中。").font(.caption).foregroundStyle(.secondary)
  }
  Card("兼容性与边界") {
   Text("请先退出其他充电管理程序，再启用硬件控制；多个控制器可能相互覆盖。")
   Text("MagSafe LED 已实现自动指示、闪烁与睡眠熄灯策略，仍待实机验证；关机策略尚未完成；Shortcuts 的 11 个操作已被系统发现，4 个只读操作已实测；不会显示虚假的成功状态。")
   Text("睡眠由系统通知协调；可选退出后保持停充。合盖强制保持唤醒及实际睡眠充电效果仍待硬件验证。")
   Text("OpenCharge \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") · MIT · 本地运行 · 无账户 · 无遥测").font(.caption).foregroundStyle(.secondary)
  }.font(.callout)
 }
}

struct PopoverActivityView: View {
 @ObservedObject var monitor: EnergyMonitor
 let popoverVisible: Bool
 var body: some View {
  HStack {
   Label(monitor.paused ? "能耗列表已暂停" : "能耗列表按需更新", systemImage: monitor.paused ? "pause.circle" : "arrow.clockwise")
   Spacer()
   Text(popoverVisible ? "弹窗处于前台" : "弹窗未在前台").foregroundStyle(.secondary)
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
    Button("注册硬件服务") { do { try service.register() } catch { m.error = error.localizedDescription } }.disabled(!service.registrationAllowed || service.busy)
    Button("刷新状态") { service.refresh() }
    Button("查看安装说明") { if let url = Bundle.main.url(forResource: "HELPER-SETUP", withExtension: "md") { NSWorkspace.shared.open(url) } }
    if service.status == .requiresApproval { Button("打开系统批准设置") { service.openApprovalSettings() } }
    if !service.legacyInstalled && (service.status == .enabled || service.status == .requiresApproval) { Button("注销服务", role: .destructive) { Task { await m.removeHelperService() } }.disabled(service.busy) }
   }
  }.onAppear { service.refresh() }
 }
}
