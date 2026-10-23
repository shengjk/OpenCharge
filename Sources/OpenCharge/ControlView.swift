import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct ControlView: View {
 @EnvironmentObject var m: ChargeModel
 @State private var limitDraft = ""
 var body: some View {
  ChargeSettingsLockNotice(model: m)
  Card("充电上限") { HStack { Text("日常目标"); Spacer(); Text("\(Int(m.config.policy.limit))%").font(.title.bold()).foregroundStyle(.mint) }; Slider(value: Binding(get: { m.config.policy.limit }, set: { m.setChargeLimitFromGUI($0) }), in: 20...100, step: 1) { Text("充电上限") } onEditingChanged: { editing in if !editing { m.applyChargeSettingsFromGUI() } }.disabled(m.config.policy.mode == .calibration || m.settingsLocked); HStack { Text("20%"); Spacer(); Text("100%") }.font(.caption).foregroundStyle(.secondary)
   HStack { Text("精确上限"); TextField("20–100", text: $limitDraft).frame(width: 70).disabled(m.config.policy.mode == .calibration || m.settingsLocked).onAppear { limitDraft = String(Int(m.config.policy.limit)) }.onSubmit {
    guard let value = Double(limitDraft), value.isFinite, (20...100).contains(value) else { m.error = "充电上限必须在 20–100%"; return }
    m.setChargeLimitFromGUI(value); m.applyChargeSettingsFromGUI()
   }.onChange(of: m.config.policy.limit) { value in limitDraft = String(Int(value)) }; Text("%"); Spacer() }
  }
  Card("航行与温度") {
   Toggle("航行模式", isOn: m.chargeSetting(\.sailing)).disabled(m.settingsLocked)
   HStack { Text("保持区间"); Spacer(); Stepper("\(Int(m.config.policy.sailingWidth))%", value: m.chargeSetting(\.sailingWidth), in: 1...20) }.disabled(!m.config.policy.sailing).disabled(m.settingsLocked)
   Text("电量自然下降至下限再充电，避免频繁补充。").font(.caption).foregroundStyle(.secondary)
   Divider(); Toggle("热保护", isOn: m.chargeSetting(\.heatProtection)).disabled(m.settingsLocked)
   HStack { Text("暂停充电温度"); Spacer(); Stepper("\(Int(m.config.policy.maxTemperature))°C", value: m.chargeSetting(\.maxTemperature), in: 25...45) }.disabled(!m.config.policy.heatProtection).disabled(m.settingsLocked)
   Text("普通充电使用热保护，不拦截主动放电；充至满电与校准的温控由下方增强选项决定。").font(.caption).foregroundStyle(.secondary)
   Picker("温控恢复规则", selection: Binding(get: { m.config.policy.thermalBehavior ?? .fiveMinuteWindows }, set: { value in m.editChargeSettings { m.config.policy.thermalBehavior = value } })) { Text("五分钟窗口").tag(ThermalBehavior.fiveMinuteWindows); Text("降温 2°C").tag(ThermalBehavior.degreeHysteresis) }.disabled(m.settingsLocked)
   Toggle("充至满电期间也启用温控（可选增强）", isOn: Binding(get: { m.config.policy.topUpThermalProtection }, set: { value in m.editChargeSettings { m.config.policy.protectDuringTopUp = value } })).disabled(m.settingsLocked)
   Toggle("校准期间也启用温控（可选增强）", isOn: Binding(get: { m.config.policy.protectDuringCalibration ?? false }, set: { value in m.editChargeSettings { m.config.policy.protectDuringCalibration = value } })).disabled(m.settingsLocked)
   Toggle("高于上限时自动放电", isOn: m.chargeSetting(\.automaticDischarge)).disabled(m.settingsLocked)
  }
  Card("电量基准与睡眠") {
   Toggle("使用硬件电量作为控制基准", isOn: Binding(get: { m.config.policy.useHardwarePercent ?? false }, set: { value in m.editChargeSettings { m.config.policy.useHardwarePercent = value } })).disabled(m.settingsLocked)
   Text("普通充电上限和放电目标按整数电量判断；航行下限保留小数精度。").font(.caption).foregroundStyle(.secondary)
   Text("macOS \(m.title) · 硬件 \(m.reading?.hardwarePercent.map { String(format: "%.1f%%", $0) } ?? "不可用")").font(.caption).foregroundStyle(.secondary)
   Toggle("充到目标前阻止空闲睡眠", isOn: Binding(get: { m.config.policy.keepAwakeUntilLimit ?? false }, set: { value in m.editChargeSettings { m.config.policy.keepAwakeUntilLimit = value } })).disabled(m.settingsLocked)
   Toggle("日常充到上限前阻止系统与合盖睡眠（可选）", isOn: Binding(get: { m.config.policy.keepAwakeWithLidClosed ?? false }, set: { value in m.editChargeSettings { m.config.policy.keepAwakeWithLidClosed = value; if value { m.config.policy.stopInSleep = false } } })).disabled(m.settingsLocked)
   Toggle("阻止系统睡眠时允许显示器休眠", isOn: Binding(get: { m.config.policy.allowDisplaySleep ?? true }, set: { value in m.editChargeSettings { m.config.policy.allowDisplaySleep = value } })).disabled(m.settingsLocked)
   Toggle("阻止系统睡眠期间合盖锁屏", isOn: Binding(get: { m.config.policy.lockScreenWhenClosed ?? false }, set: { value in m.editChargeSettings { m.config.policy.lockScreenWhenClosed = value } })).disabled(m.settingsLocked)
   Text(m.lidLockStatus).font(.caption).foregroundStyle(.secondary)
   Button("检测锁屏接口（只读）") { m.inspectLidLock() }
   Text("仅在完整睡眠控制已确认启用且当前用户处于前台时请求锁屏；每次合盖最多请求一次。私有接口不可用时不会模拟锁屏或隐藏窗口，系统锁定效果仍需实测。").font(.caption).foregroundStyle(.secondary)
   Text(m.sleepStatus).font(.caption).foregroundStyle(.secondary)
   Button("检测睡眠接口") { m.inspectSleepInterfaces() }
   Toggle("睡眠时停止充电", isOn: m.chargeSetting(\.stopInSleep)).disabled(m.config.policy.keepAwakeWithLidClosed == true).disabled(m.settingsLocked)
   Toggle("退出应用后保持停充", isOn: m.chargeSetting(\.stopOnQuit)).disabled(m.settingsLocked)
   Text("退出后停充是显式持久状态，可重新打开应用并关闭硬件控制来恢复。服务重启或机器关机后的恢复能力依硬件而定。").font(.caption).foregroundStyle(.secondary)
   Text("普通充放电的空闲睡眠由上方选项控制。合盖主动放电需要系统睡眠保护；校准全程需要系统保护并保持显示器开启。启用充到上限保护后，温控暂停仍保留保护，航行保持和手动暂停则释放。所需保护必须在充放电命令前确认；接口不可用或控制失败时停止硬件控制并尝试恢复。物理效果仍待实测；拔线、完成、退出或心跳超时会尝试释放。").font(.caption).foregroundStyle(.secondary)
  }
  Card("操作与校准") {
   Picker("当前模式", selection: m.controlModeSelection) { ForEach(ChargeMode.allCases, id: \.self) { Text(modeName($0)).tag($0) } }.pickerStyle(.segmented)
   if m.calibrationPending { HStack { Text("上次校准中断"); Button("继续") { m.resumeCalibration() }; Button("取消") { m.changeMode(.automatic) } } }
   if let last = m.config.lastCalibration { Text("上次完成：\(last.formatted())").font(.caption).foregroundStyle(.secondary) }
   Text("日常上限为 100% 或临时充满时，通常由系统管理补电；手动暂停与热保护结束后的目标暂停仍会停充。临时充满在拔线后结束。").font(.caption).foregroundStyle(.secondary)
   Text("校准阶段：\(m.calibration.displayName)").font(.caption).foregroundStyle(.secondary)
   Text("校准顺序：充满 → 放电至 10% → 充满 → 保持一小时 → 恢复日常目标；默认校准期间暂停应用温控，可启用增强保护；可随时切回自动模式。").font(.caption).foregroundStyle(.secondary)
   Stepper("主动放电保底：\(Int(m.config.policy.reserve))%", value: m.chargeSetting(\.reserve), in: 10...40).disabled(m.settingsLocked)
   Text("保底仅用于普通放电。电量已高于目标时保持停充，避免在保底与目标之间反复充放电。").font(.caption).foregroundStyle(.secondary)
  }
  Card("出行准备 · 新功能") {
   Toggle("启用出行充电计划", isOn: Binding(get: { m.config.policy.departure != nil }, set: { value in m.editChargeSettings { m.config.policy.departure = value ? Date().addingTimeInterval(7200) : nil } })).disabled(m.settingsLocked)
   Group { if m.config.policy.departure != nil { DatePicker("出发时间", selection: Binding(get: { m.config.policy.departure ?? Date() }, set: { value in m.editChargeSettings { m.config.policy.departure = value } })); Stepper("出行目标 \(Int(m.config.policy.departureTarget))%", value: m.chargeSetting(\.departureTarget), in: 20...100); Stepper("估算充电速度 \(Int(m.config.policy.estimatedPercentPerHour))% / 小时", value: m.chargeSetting(\.estimatedPercentPerHour), in: 5...100, step: 5) } }.disabled(m.settingsLocked)
   Text("按设定速度估算开始充电时间，预留 30 分钟；无法保证到点充满，电脑必须保持运行。").font(.caption).foregroundStyle(.secondary)
  }
  Button("保存并应用策略") { m.applyChargeSettingsFromGUI() }.buttonStyle(.borderedProminent).tint(.mint).disabled(m.settingsLocked)
 }
 func modeName(_ mode: ChargeMode) -> String { switch mode { case .automatic: return "自动"; case .paused: return "暂停"; case .discharge: return "放电"; case .topUp: return "充满"; case .calibration: return "校准" } }
}
