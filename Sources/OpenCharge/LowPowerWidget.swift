import SwiftUI
import ChargeHardware

struct LowPowerWidget: View {
 @ObservedObject var model: ChargeModel
 let active: Bool?
 let compact: Bool

 var body: some View {
  VStack(alignment: .leading, spacing: 8) {
   Text(active.map { $0 ? NSLocalizedString("低电量模式已开启", comment: "") : NSLocalizedString("低电量模式已关闭", comment: "") } ?? NSLocalizedString("低电量模式能力不可用", comment: ""))
    .font(.caption)
   if compact {
    Button(NSLocalizedString("关闭低电量模式", comment: "")) { model.setLowPowerFromPopover(false) }
     .disabled(model.config.systemActionsEnabled != true || active != true)
   } else {
    sourceRow(.battery, title: NSLocalizedString("电池供电", comment: ""), value: model.lowPowerPreferences?.battery)
    sourceRow(.ac, title: NSLocalizedString("电源适配器", comment: ""), value: model.lowPowerPreferences?.ac)
    Button(NSLocalizedString("读取状态", comment: "")) { model.inspectLowPower() }
   }
   if let error = model.error { Text(error).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
   if model.config.systemActionsEnabled != true {
    Text(NSLocalizedString("请先允许菜单栏快捷操作改变系统模式", comment: "")).font(.caption).presentationSecondary()
    Button(NSLocalizedString("打开设置", comment: "")) { model.selectSettingsPage(); model.openDashboardWindow() }
   }
  }
 }

 private func sourceRow(_ source: PowerSource, title: String, value: Bool?) -> some View {
  HStack {
   Text(title).font(.caption)
   Spacer()
   Text(value.map { $0 ? NSLocalizedString("开启", comment: "") : NSLocalizedString("关闭", comment: "") } ?? NSLocalizedString("不可用", comment: "")).font(.caption).presentationSecondary()
   Button(NSLocalizedString("开启", comment: "")) { model.setLowPowerFromPopover(true, source: source) }
    .disabled(model.config.systemActionsEnabled != true || value == nil || value == true)
   Button(NSLocalizedString("关闭", comment: "")) { model.setLowPowerFromPopover(false, source: source) }
    .disabled(model.config.systemActionsEnabled != true || value == nil || value == false)
  }
 }
}
