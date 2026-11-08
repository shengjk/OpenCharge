import SwiftUI
import ChargeHardware

extension EnergyMode {
 var title: String {
  switch self {
  case .automatic: return NSLocalizedString("自动电源模式", comment: "")
  case .low: return NSLocalizedString("低电量模式", comment: "")
  case .high: return NSLocalizedString("高功率模式", comment: "")
  }
 }
}

struct EnergyModeControls: View {
 @ObservedObject var model: ChargeModel
 let modes: EnergyModeStatus

 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   sourceRow(.battery, title: NSLocalizedString("电池供电", comment: ""))
   sourceRow(.ac, title: NSLocalizedString("电源适配器", comment: ""))
   Button(NSLocalizedString("读取状态", comment: "")) { model.inspectEnergyModes() }
   if let error = model.error { Text(error).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
   if model.config.systemActionsEnabled != true {
    Text(NSLocalizedString("请先允许菜单栏快捷操作改变系统模式", comment: "")).font(.caption).presentationSecondary()
    Button(NSLocalizedString("打开设置", comment: "")) { model.selectSettingsPage(); model.openDashboardWindow() }
   }
  }
 }
 @ViewBuilder private func sourceRow(_ source: PowerSource, title: String) -> some View {
  if let observed = modes.mode(for: source) {
   Picker(title, selection: Binding(get: { observed }, set: { model.setEnergyMode($0, source: source) })) {
    ForEach(EnergyMode.allCases, id: \.self) { mode in
     Text(mode.title).tag(mode).disabled(mode == .high && !modes.supportsHigh(on: source))
    }
   }.disabled(model.config.systemActionsEnabled != true)
  } else {
   HStack { Text(title); Spacer(); Text(NSLocalizedString("不可用", comment: "")) }.font(.caption).presentationSecondary()
  }
 }
}
