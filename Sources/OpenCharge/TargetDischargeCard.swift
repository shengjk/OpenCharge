import SwiftUI
import ChargeCore

struct TargetDischargeCard: View {
 @ObservedObject var model: ChargeModel
 private var m: ChargeModel { model }
 @State private var dischargeDraft = 80.0
 var body: some View {
  Card(NSLocalizedString("放电至指定电量", comment: "")) {
   Stepper(String.localizedStringWithFormat(NSLocalizedString("目标电量：%lld%%",comment:""),Int64(dischargeDraft)),value:$dischargeDraft,in:20...100,step:1)
    .disabled(m.config.policy.mode == .discharge || m.settingsLocked)
    .accessibilityIdentifier("discharge-target-stepper")
    .onAppear { dischargeDraft = m.config.policy.limit.rounded(.towardZero) }
    .onChange(of:m.config.policy.limit) { value in dischargeDraft = value.rounded(.towardZero) }
   Text(NSLocalizedString("与日常充电上限共用目标；调整这里的数值不会立即放电，点击开始后才应用。",comment:"")).font(.caption).presentationSecondary()
   if m.config.policy.mode == .discharge {
    Text(String.localizedStringWithFormat(NSLocalizedString("手动放电目标：%lld%%",comment:""),Int64(m.config.policy.limit))).font(.caption)
    Button(NSLocalizedString("停止放电",comment:"")) { m.stopTargetDischargeFromGUI() }.accessibilityIdentifier("stop-target-discharge").disabled(m.settingsLocked)
   } else {
    Button(String.localizedStringWithFormat(NSLocalizedString("放电至 %lld%%",comment:""),Int64(dischargeDraft))) { m.startTargetDischargeFromGUI(dischargeDraft) }
     .accessibilityIdentifier("start-target-discharge")
     .disabled(!m.config.hardwareEnabled || m.settingsLocked || m.config.policy.automaticDischarge || m.config.policy.mode == .calibration || m.calibrationPending)
   }
   if !m.config.hardwareEnabled { Text(NSLocalizedString("请先在设置中开启硬件控制，再开始放电",comment:"")).font(.caption).presentationSecondary() }
   if m.config.policy.automaticDischarge { Text(NSLocalizedString("请先关闭自动放电，再开始手动放电",comment:"")).font(.caption).presentationSecondary() }
   if m.config.policy.mode == .calibration || m.calibrationPending { Text(NSLocalizedString("请先结束校准，再开始手动放电",comment:"")).font(.caption).presentationSecondary() }
   if m.config.policy.departure != nil { Text(NSLocalizedString("开始手动放电会关闭出行充电计划，避免计划改变本次目标。",comment:"")).font(.caption).presentationSecondary() }
   Text(NSLocalizedString("接电时使用电池供电，降至目标后停止主动放电；放电速度取决于电脑耗电。",comment:"")).font(.caption).presentationSecondary()
   Divider()
   Toggle(NSLocalizedString("高于上限时自动放电", comment: ""), isOn: m.chargeSetting(\.automaticDischarge)).disabled(m.settingsLocked)
   Text(NSLocalizedString("自动放电开启时按日常上限运行；关闭后可使用上方手动按钮。",comment:"")).font(.caption).presentationSecondary()
  }
 }
}
