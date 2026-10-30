import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct ControlView: View {
 @EnvironmentObject var m: ChargeModel
 @State private var limitDraft = ""
 @State private var sliderDraft = 80.0
 @State private var editingSlider = false
 var body: some View {
  ChargeSettingsLockNotice(model: m)
  Card(NSLocalizedString("充电上限", comment: "")) { HStack { Text(NSLocalizedString("日常目标", comment: "")); Spacer(); Text("\(Int(editingSlider ? sliderDraft : m.config.policy.limit))%").font(.title.bold()).presentationMint() }; Slider(value: $sliderDraft, in: 20...100, step: 1) { Text(NSLocalizedString("充电上限", comment: "")) } onEditingChanged: { editing in
    editingSlider = editing
    if !editing {
     if m.setChargeLimitFromGUI(sliderDraft) { m.applyChargeSettingsFromGUI() }
     sliderDraft = m.config.policy.limit
    }
   }.disabled(m.config.policy.mode == .calibration || m.settingsLocked)
    .accessibilityIdentifier("charge-limit-slider")
    .onChange(of:sliderDraft) { value in
     // Keyboard/accessibility steps can arrive without a tracked drag.
     if !editingSlider && value != m.config.policy.limit {
      if m.setChargeLimitFromGUI(value) { m.applyChargeSettingsFromGUI() }
      sliderDraft = m.config.policy.limit
     }
    }
    .onAppear { sliderDraft = m.config.policy.limit }
    .onChange(of:m.config.policy.limit) { value in if !editingSlider { sliderDraft = value } }; HStack { Text("20%"); Spacer(); Text("100%") }.font(.caption).presentationSecondary()
   HStack { Text(NSLocalizedString("精确上限", comment: "")); CommitTextField(title: "20–100", text: $limitDraft) {
    guard let value = Double(limitDraft), value.isFinite, (20...100).contains(value) else { m.error = NSLocalizedString("充电上限必须在 20–100%", comment: ""); return }
    if m.setChargeLimitFromGUI(value) { m.applyChargeSettingsFromGUI() }
   }.frame(width: 70).disabled(m.config.policy.mode == .calibration || m.settingsLocked).onAppear { limitDraft = String(Int(m.config.policy.limit)) }.onChange(of: m.config.policy.limit) { value in limitDraft = String(Int(value)) }; Text("%"); Spacer() }
  }
  Card(NSLocalizedString("航行与温度", comment: "")) {
   Toggle(NSLocalizedString("航行模式", comment: ""), isOn: m.chargeSetting(\.sailing)).disabled(m.settingsLocked)
   HStack { Text(NSLocalizedString("保持区间", comment: "")); Spacer(); Stepper("\(Int(m.config.policy.sailingWidth))%", value: m.chargeSetting(\.sailingWidth), in: 1...20) }.disabled(!m.config.policy.sailing).disabled(m.settingsLocked)
   Text(NSLocalizedString("电量自然下降至下限再充电，避免频繁补充。", comment: "")).font(.caption).presentationSecondary()
   Divider(); Toggle(NSLocalizedString("热保护", comment: ""), isOn: m.chargeSetting(\.heatProtection)).disabled(m.settingsLocked)
   HStack { Text(NSLocalizedString("暂停充电温度", comment: "")); Spacer(); Stepper("\(Int(m.config.policy.maxTemperature))°C", value: m.chargeSetting(\.maxTemperature), in: 25...50) }.disabled(!m.config.policy.heatProtection).disabled(m.settingsLocked)
   Text(NSLocalizedString("普通充电使用热保护，不拦截主动放电；充至满电与校准的温控由下方增强选项决定。", comment: "")).font(.caption).presentationSecondary()
   Picker(NSLocalizedString("温控恢复规则", comment: ""), selection: Binding(get: { m.config.policy.thermalBehavior ?? .fiveMinuteWindows }, set: { value in m.editChargeSettings { m.config.policy.thermalBehavior = value } })) { Text(NSLocalizedString("五分钟窗口", comment: "")).tag(ThermalBehavior.fiveMinuteWindows); Text(NSLocalizedString("降温 2°C", comment: "")).tag(ThermalBehavior.degreeHysteresis) }.disabled(m.settingsLocked)
   Toggle(NSLocalizedString("充至满电期间也启用温控（可选增强）", comment: ""), isOn: Binding(get: { m.config.policy.topUpThermalProtection }, set: { value in m.editChargeSettings { m.config.policy.protectDuringTopUp = value } })).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("校准期间也启用温控（可选增强）", comment: ""), isOn: Binding(get: { m.config.policy.protectDuringCalibration ?? false }, set: { value in m.editChargeSettings { m.config.policy.protectDuringCalibration = value } })).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("高于上限时自动放电", comment: ""), isOn: m.chargeSetting(\.automaticDischarge)).disabled(m.settingsLocked)
  }
  Card(NSLocalizedString("电量基准与睡眠", comment: "")) {
   Toggle(NSLocalizedString("使用硬件电量作为控制基准", comment: ""), isOn: Binding(get: { m.config.policy.useHardwarePercent ?? false }, set: { value in m.editChargeSettings { m.config.policy.useHardwarePercent = value } })).disabled(m.settingsLocked)
   Text(NSLocalizedString("普通充电上限和放电目标按整数电量判断；航行下限保留小数精度。", comment: "")).font(.caption).presentationSecondary()
   Text(String.localizedStringWithFormat(NSLocalizedString("macOS %@ · 硬件 %@", comment: ""), m.title, m.reading?.hardwarePercent.map { String(format: "%.1f%%", $0) } ?? NSLocalizedString("不可用", comment: ""))).font(.caption).presentationSecondary()
   Toggle(NSLocalizedString("充到目标前阻止空闲睡眠", comment: ""), isOn: Binding(get: { m.config.policy.keepAwakeUntilLimit ?? false }, set: { value in m.editChargeSettings { m.config.policy.keepAwakeUntilLimit = value } })).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("日常充到上限前阻止系统与合盖睡眠（可选）", comment: ""), isOn: Binding(get: { m.config.policy.keepAwakeWithLidClosed ?? false }, set: { value in m.editChargeSettings { m.config.policy.keepAwakeWithLidClosed = value; if value { m.config.policy.stopInSleep = false } } })).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("阻止系统睡眠时允许显示器休眠", comment: ""), isOn: Binding(get: { m.config.policy.allowDisplaySleep ?? true }, set: { value in m.editChargeSettings { m.config.policy.allowDisplaySleep = value } })).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("阻止系统睡眠期间合盖锁屏", comment: ""), isOn: Binding(get: { m.config.policy.lockScreenWhenClosed ?? false }, set: { value in m.editChargeSettings { m.config.policy.lockScreenWhenClosed = value } })).disabled(m.settingsLocked)
   Text(m.lidLockStatus).font(.caption).presentationSecondary()
   Button(NSLocalizedString("检测锁屏接口（只读）", comment: "")) { m.inspectLidLock() }
   Text(NSLocalizedString("仅在完整睡眠控制已确认启用且当前用户处于前台时请求锁屏；每次合盖最多请求一次。私有接口不可用时不会模拟锁屏或隐藏窗口，系统锁定效果仍需实测。", comment: "")).font(.caption).presentationSecondary()
   Text(m.sleepStatus).font(.caption).presentationSecondary()
   Button(NSLocalizedString("检测睡眠接口", comment: "")) { m.inspectSleepInterfaces() }
   Toggle(NSLocalizedString("睡眠时停止充电", comment: ""), isOn: m.chargeSetting(\.stopInSleep)).disabled(m.config.policy.keepAwakeWithLidClosed == true || m.usesNumericFirmware).disabled(m.settingsLocked)
   Toggle(NSLocalizedString("退出应用后保持停充", comment: ""), isOn: m.chargeSetting(\.stopOnQuit)).disabled(m.usesNumericFirmware).disabled(m.settingsLocked)
   if m.usesNumericFirmware { Text(NSLocalizedString("此通道按当前状态设置睡眠目标，退出时保留数值充电上限；以上两项普通停充选项不适用。", comment: "")).font(.caption).presentationSecondary() }
   Text(NSLocalizedString("退出后停充是显式持久状态，可重新打开应用并关闭硬件控制来恢复。服务重启或机器关机后的恢复能力依硬件而定。", comment: "")).font(.caption).presentationSecondary()
   Text(NSLocalizedString("普通充放电的空闲睡眠由上方选项控制。合盖主动放电需要系统睡眠保护；校准全程需要系统保护并保持显示器开启。启用充到上限保护后，温控暂停仍保留保护，航行保持和手动暂停则释放。所需保护必须在充放电命令前确认；接口不可用或控制失败时停止硬件控制并尝试恢复。物理效果仍待实测；拔线、完成、退出或心跳超时会尝试释放。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("操作与校准", comment: "")) {
   Picker(NSLocalizedString("当前模式", comment: ""), selection: m.controlModeSelection) { ForEach(ChargeMode.allCases, id: \.self) { Text(modeName($0)).tag($0) } }.pickerStyle(.segmented)
   if m.calibrationPending { HStack { Text(NSLocalizedString("上次校准中断", comment: "")); Button(NSLocalizedString("继续", comment: "")) { m.resumeCalibration() }; Button(NSLocalizedString("取消", comment: "")) { m.changeMode(.automatic) } } }
   if let last = m.config.lastCalibration { Text(String.localizedStringWithFormat(NSLocalizedString("上次完成：%@", comment: ""), DateDisplay.string(last))).font(.caption).presentationSecondary() }
   Text(NSLocalizedString("日常上限为 100% 或临时充满时，通常由系统管理补电；手动暂停与热保护结束后的目标暂停仍会停充。临时充满在拔线后结束。", comment: "")).font(.caption).presentationSecondary()
   Text(String.localizedStringWithFormat(NSLocalizedString("校准阶段：%@", comment: ""), m.calibration.displayName)).font(.caption).presentationSecondary()
   Text(NSLocalizedString("校准顺序：充满 → 放电至 10% → 充满 → 保持一小时 → 恢复日常目标；默认校准期间暂停应用温控，可启用增强保护；可随时切回自动模式。", comment: "")).font(.caption).presentationSecondary()
   Stepper(String.localizedStringWithFormat(NSLocalizedString("主动放电保底：%lld%%", comment: ""), Int64(Int(m.config.policy.reserve))), value: m.chargeSetting(\.reserve), in: 10...40).disabled(m.settingsLocked)
   Text(NSLocalizedString("保底仅用于普通放电。电量已高于目标时保持停充，避免在保底与目标之间反复充放电。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("出行准备 · 新功能", comment: "")) {
   Toggle(NSLocalizedString("启用出行充电计划", comment: ""), isOn: Binding(get: { m.config.policy.departure != nil }, set: { value in m.editChargeSettings { m.config.policy.departure = value ? Date().addingTimeInterval(7200) : nil } })).disabled(m.settingsLocked)
   Group { if m.config.policy.departure != nil { DatePicker(NSLocalizedString("出发时间", comment: ""), selection: Binding(get: { m.config.policy.departure ?? Date() }, set: { value in m.editChargeSettings { m.config.policy.departure = value } })); Stepper(String.localizedStringWithFormat(NSLocalizedString("出行目标 %lld%%", comment: ""), Int64(Int(m.config.policy.departureTarget))), value: m.chargeSetting(\.departureTarget), in: 20...100); Stepper(String.localizedStringWithFormat(NSLocalizedString("估算充电速度 %lld%% / 小时", comment: ""), Int64(Int(m.config.policy.estimatedPercentPerHour))), value: m.chargeSetting(\.estimatedPercentPerHour), in: 5...100, step: 5) } }.disabled(m.settingsLocked)
   Text(NSLocalizedString("按设定速度估算开始充电时间，预留 30 分钟；无法保证到点充满，电脑必须保持运行。", comment: "")).font(.caption).presentationSecondary()
  }
  Button(NSLocalizedString("保存并应用策略", comment: "")) { m.applyChargeSettingsFromGUI() }.presentationProminentButton().presentationTint(PresentationPalette.mint).disabled(m.settingsLocked)
 }
 func modeName(_ mode: ChargeMode) -> String { switch mode { case .automatic: return NSLocalizedString("自动", comment: ""); case .paused: return NSLocalizedString("暂停", comment: ""); case .discharge: return NSLocalizedString("放电", comment: ""); case .topUp: return NSLocalizedString("充满", comment: ""); case .calibration: return NSLocalizedString("校准", comment: "") } }
}
