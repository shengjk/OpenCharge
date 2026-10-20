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
  Card("充电上限") { HStack { Text("日常目标"); Spacer(); Text("\(Int(m.config.policy.limit))%").font(.title.bold()).foregroundStyle(.mint) }; Slider(value: $m.config.policy.limit, in: 20...100, step: 1) { Text("充电上限") } onEditingChanged: { editing in if !editing { m.save(); m.refresh() } }.disabled(m.config.policy.mode == .calibration); HStack { Text("20%"); Spacer(); Text("100%") }.font(.caption).foregroundStyle(.secondary)
   HStack { Text("精确上限"); TextField("20–100", text: $limitDraft).frame(width: 70).disabled(m.config.policy.mode == .calibration).onAppear { limitDraft = String(Int(m.config.policy.limit)) }.onSubmit {
    guard let value = Double(limitDraft), value.isFinite, (20...100).contains(value) else { m.error = "充电上限必须在 20–100%"; return }
    m.config.policy.limit = value; m.save(); m.refresh()
   }.onChange(of: m.config.policy.limit) { value in limitDraft = String(Int(value)) }; Text("%"); Spacer() }
  }
  Card("航行与温度") {
   Toggle("航行模式", isOn: $m.config.policy.sailing)
   HStack { Text("保持区间"); Spacer(); Stepper("\(Int(m.config.policy.sailingWidth))%", value: $m.config.policy.sailingWidth, in: 1...20) }.disabled(!m.config.policy.sailing)
   Text("电量自然下降至下限再充电，避免频繁补充。").font(.caption).foregroundStyle(.secondary)
   Divider(); Toggle("热保护", isOn: $m.config.policy.heatProtection)
   HStack { Text("暂停充电温度"); Spacer(); Stepper("\(Int(m.config.policy.maxTemperature))°C", value: $m.config.policy.maxTemperature, in: 25...45) }.disabled(!m.config.policy.heatProtection)
   Picker("温控恢复规则", selection: Binding(get: { m.config.policy.thermalBehavior ?? .fiveMinuteWindows }, set: { m.config.policy.thermalBehavior = $0 })) { Text("五分钟窗口").tag(ThermalBehavior.fiveMinuteWindows); Text("降温 2°C").tag(ThermalBehavior.degreeHysteresis) }
   Toggle("校准期间也启用温控（可选增强）", isOn: Binding(get: { m.config.policy.protectDuringCalibration ?? false }, set: { m.config.policy.protectDuringCalibration = $0 }))
   Toggle("高于上限时自动放电", isOn: $m.config.policy.automaticDischarge)
  }
  Card("电量基准与睡眠") {
   Toggle("使用硬件电量作为控制基准", isOn: Binding(get: { m.config.policy.useHardwarePercent ?? false }, set: { m.config.policy.useHardwarePercent = $0 }))
   Text("macOS \(m.title) · 硬件 \(m.reading?.hardwarePercent.map { String(format: "%.1f%%", $0) } ?? "不可用")").font(.caption).foregroundStyle(.secondary)
   Toggle("充到目标前阻止空闲睡眠", isOn: Binding(get: { m.config.policy.keepAwakeUntilLimit ?? false }, set: { m.config.policy.keepAwakeUntilLimit = $0 }))
   Toggle("日常充到上限前阻止系统与合盖睡眠（可选）", isOn: Binding(get: { m.config.policy.keepAwakeWithLidClosed ?? false }, set: { m.config.policy.keepAwakeWithLidClosed = $0; if $0 { m.config.policy.stopInSleep = false } }))
   Toggle("阻止系统睡眠时允许显示器休眠", isOn: Binding(get: { m.config.policy.allowDisplaySleep ?? true }, set: { m.config.policy.allowDisplaySleep = $0 }))
   Toggle("阻止系统睡眠期间合盖锁屏", isOn: Binding(get: { m.config.policy.lockScreenWhenClosed ?? false }, set: { m.config.policy.lockScreenWhenClosed = $0 }))
   Text(m.lidLockStatus).font(.caption).foregroundStyle(.secondary)
   Button("检测锁屏接口（只读）") { m.inspectLidLock() }
   Text("仅在完整睡眠控制已确认启用且当前用户处于前台时请求锁屏；每次合盖最多请求一次。私有接口不可用时不会模拟锁屏或隐藏窗口，系统锁定效果仍需实测。").font(.caption).foregroundStyle(.secondary)
   Text(m.sleepStatus).font(.caption).foregroundStyle(.secondary)
   Button("检测睡眠接口") { m.inspectSleepInterfaces() }
   Toggle("睡眠时停止充电", isOn: $m.config.policy.stopInSleep).disabled(m.config.policy.keepAwakeWithLidClosed == true)
   Toggle("退出应用后保持停充", isOn: $m.config.policy.stopOnQuit)
   Text("退出后停充是显式持久状态，可重新打开应用并关闭硬件控制来恢复。服务重启或机器关机后的恢复能力依硬件而定。").font(.caption).foregroundStyle(.secondary)
   Text("主动放电期间自动阻止空闲睡眠，合盖时另需系统睡眠保护，无须单独开启合盖放电。校准必须阻止系统睡眠并保持显示器开启。日常充到上限前的系统睡眠选项独立生效。所需保护必须在充放电命令前确认；接口不可用或控制失败时停止硬件控制并尝试恢复。物理效果仍待实测；拔线、完成、退出或心跳超时会尝试释放。").font(.caption).foregroundStyle(.secondary)
  }
  Card("操作与校准") {
   Picker("当前模式", selection: $m.config.policy.mode) { ForEach(ChargeMode.allCases, id: \.self) { Text(modeName($0)).tag($0) } }.pickerStyle(.segmented)
   if m.calibrationPending { HStack { Text("上次校准中断"); Button("继续") { m.resumeCalibration() }; Button("取消") { m.changeMode(.automatic) } } }
   if let last = m.config.lastCalibration { Text("上次完成：\(last.formatted())").font(.caption).foregroundStyle(.secondary) }
   Text("校准阶段：\(m.calibration.displayName)").font(.caption).foregroundStyle(.secondary)
   Text("校准顺序：充满 → 放电至 10% → 充满 → 保持一小时 → 恢复日常目标；默认校准期间暂停应用温控，可启用增强保护；可随时切回自动模式。").font(.caption).foregroundStyle(.secondary)
   Stepper("主动放电保底：\(Int(m.config.policy.reserve))%", value: $m.config.policy.reserve, in: 10...40)
  }
  Card("出行准备 · 新功能") {
   Toggle("启用出行充电计划", isOn: Binding(get: { m.config.policy.departure != nil }, set: { m.config.policy.departure = $0 ? Date().addingTimeInterval(7200) : nil }))
   if m.config.policy.departure != nil { DatePicker("出发时间", selection: Binding(get: { m.config.policy.departure ?? Date() }, set: { m.config.policy.departure = $0 })); Stepper("出行目标 \(Int(m.config.policy.departureTarget))%", value: $m.config.policy.departureTarget, in: 20...100); Stepper("估算充电速度 \(Int(m.config.policy.estimatedPercentPerHour))% / 小时", value: $m.config.policy.estimatedPercentPerHour, in: 5...100, step: 5) }
   Text("按设定速度估算开始充电时间，预留 30 分钟；无法保证到点充满，电脑必须保持运行。").font(.caption).foregroundStyle(.secondary)
  }
  Button("保存并应用策略") { m.config.policy.normalize(); m.save(); m.refresh() }.buttonStyle(.borderedProminent).tint(.mint)
 }
 func modeName(_ mode: ChargeMode) -> String { switch mode { case .automatic: return "自动"; case .paused: return "暂停"; case .discharge: return "放电"; case .topUp: return "充满"; case .calibration: return "校准" } }
}
