import SwiftUI
import ChargeCore

struct MenuView: View {
 @EnvironmentObject var m: ChargeModel
 var consumer: PopoverConsumer = .preview
 var dismiss: (() -> Void)? = nil
 @AppStorage("appearance") private var appearance = "system"
 var body: some View {
  PopoverContents(m: m, preferences: m.popoverPreferences, consumer: consumer, dismiss: dismiss)
   .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
 }
}
struct PopoverContents: View {
 @ObservedObject var m: ChargeModel
 @ObservedObject var preferences: PopoverPreferences
 let consumer: PopoverConsumer
 let dismiss: (() -> Void)?
 private var editing: Bool { preferences.isEditing(consumer) }
 private func setEditing(_ value: Bool) { preferences.setEditing(value, consumer: consumer) }
 private var height: CGFloat {
  if editing { return 460 }
  let energyRows = preferences.layout.widgets.contains(.energyApps) ? min(m.energyMonitor.rows.count, 5) : 0
  return min(640, 210 + CGFloat(preferences.layout.widgets.count * 155 + energyRows * 30))
 }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 14) {
    HStack { Text("OpenCharge").font(.headline); Spacer(); if preferences.showPercentage { Text(m.title).font(.title2.monospacedDigit()) } }
    ChargeSettingsLockNotice(model: m)
    ProgressView(value: m.reading?.percent ?? 0, total: 100).tint(PresentationPalette.mint)
    Text(String.localizedStringWithFormat(NSLocalizedString("目标 %lld%% · %@", comment: ""), Int64(Int(m.decision.effectiveLimit)), m.decision.reason)).font(.callout)
    Text(m.helperStatus).font(.caption).presentationSecondary()
    HStack { Button(m.automationPhase == .topUp ? NSLocalizedString("停止充满", comment: "") : NSLocalizedString("充至满电", comment: "")) { m.toggleTopUp() }; PopoverDischargeButton(model: m); Button(NSLocalizedString("自动", comment: "")) { m.changeMode(.automatic) } }
    if editing {
     Text(NSLocalizedString("拖动调整顺序，也可使用上下按钮。关闭勾选隐藏组件。", comment: "")).font(.caption).presentationSecondary()
     ForEach(preferences.layout.widgets) { widget in editor(widget) }
     ForEach(PopoverWidget.allCases.filter { !preferences.layout.widgets.contains($0) }) { widget in
      Toggle(widget.title, isOn: Binding(get: { false }, set: { preferences.layout.setVisible(widget, visible: $0) }))
     }
     Button(NSLocalizedString("完成编辑", comment: "")) { setEditing(false) }
    } else {
     ForEach(preferences.layout.widgets) { widget in
      VStack(alignment: .leading, spacing: 10) { Text(widget.title).font(.subheadline.bold()); content(widget) }
       .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
       .onLongPressGesture(minimumDuration: 0.6) { setEditing(true) }
     }
    }
    Divider()
    HStack { Button(NSLocalizedString("打开控制台", comment: "")) { m.openDashboardWindow(); dismiss?() }; Spacer(); Button(editing ? NSLocalizedString("完成编辑", comment: "") : NSLocalizedString("编辑组件", comment: "")) { setEditing(!editing) }; Button(NSLocalizedString("退出", comment: "")) { m.quit() } }
   }.padding(18)
  }.frame(width: 380, height: height)
   .background(Group { if consumer == .preview { PopoverWindowObserver(model: m, consumer: consumer).frame(width: 0, height: 0) } })
   .onAppear { if consumer == .preview { m.setPopoverVisible(true, consumer: consumer) } }
   .onDisappear { if consumer == .preview { m.setPopoverVisible(false, consumer: consumer); setEditing(false) } }
 }
 private func editor(_ widget: PopoverWidget) -> some View {
  PopoverDropRow(widget: widget, preferences: preferences) {
  HStack {
   PopoverDragHandle(widget: widget, preferences: preferences).frame(width: 20, height: 24)
   Toggle(widget.title, isOn: Binding(get: { preferences.layout.widgets.contains(widget) }, set: { preferences.layout.setVisible(widget, visible: $0) }))
   Spacer()
   Button { preferences.layout.move(widget, by: -1) } label: { Image(systemName: "arrow.up") }.help(String.localizedStringWithFormat(NSLocalizedString("上移 %@", comment: ""), widget.title)).disabled(preferences.layout.widgets.first == widget)
   Button { preferences.layout.move(widget, by: 1) } label: { Image(systemName: "arrow.down") }.help(String.localizedStringWithFormat(NSLocalizedString("下移 %@", comment: ""), widget.title)).disabled(preferences.layout.widgets.last == widget)
  }.padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
  }.frame(height: 44)
 }
 @ViewBuilder private func content(_ widget: PopoverWidget) -> some View {
  switch widget {
  case .specifications:
   if preferences.layout.specifications.isEmpty { Text(NSLocalizedString("未选择规格指标", comment: "")).font(.caption).presentationSecondary() }
   ForEach(preferences.layout.specifications) { spec in HStack { Text(spec.title).font(.caption); Spacer(); Text(BatterySpecificationFormatter.value(spec, reading: m.reading)).font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65) } }
  case .powerFlow:
   PowerFlowView(snapshot: PowerFlowSnapshot(adapterWatts: m.reading?.adapterPowerW, batteryWatts: m.watts, systemWatts: m.reading?.systemPowerW), animationEnabled: m.popoverVisible, compact: true, adapterConnected: m.reading?.physicalAdapterConnected ?? (m.reading?.connected ?? false))
  case .energyApps:
   PopoverEnergyView(monitor: m.energyMonitor)
  }
 }
}
struct PopoverDischargeButton: View {
 @ObservedObject var model: ChargeModel
 var body: some View {
  Button(model.automationPhase == .discharging ? NSLocalizedString("停止放电", comment: "") : NSLocalizedString("放电", comment: "")) { model.toggleDischargeFromPopover() }
   .disabled(model.config.policy.automaticDischarge)
   .help(model.config.policy.automaticDischarge ? NSLocalizedString("自动放电已开启；请在充电控制中关闭后使用手动按钮。", comment: "") : NSLocalizedString("开始或停止手动放电", comment: ""))
 }
}
struct PopoverEnergyView: View {
 @ObservedObject var monitor: EnergyMonitor
 var body: some View {
  VStack(alignment: .leading, spacing: 9) {
   ForEach(monitor.rows) { row in
    HStack { if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }; Text(row.name).lineLimit(1); Spacer(); Text(row.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "—").presentationSecondary() }.font(.caption)
   }
   Text(monitor.status).font(.caption).presentationSecondary()
  }
 }
}
struct PopoverSettingsView: View {
 @ObservedObject var preferences: PopoverPreferences
 let preview: () -> Void
 let openEditor: () -> Void
 var body: some View {
  Card(NSLocalizedString("菜单栏弹窗", comment: "")) {
   Toggle(NSLocalizedString("弹窗显示当前电量百分比", comment: ""), isOn: $preferences.showPercentage)
   Toggle(NSLocalizedString("弹窗动画", comment: ""), isOn: $preferences.animationsEnabled)
   Text(NSLocalizedString("系统开启“减少动态效果”时，弹窗也会关闭动画。", comment: "")).font(.caption).presentationSecondary()
   Button(NSLocalizedString("打开真实弹窗编辑器", comment: "")) { openEditor() }
   ForEach(PopoverWidget.allCases) { widget in Toggle(widget.title, isOn: Binding(get: { preferences.layout.widgets.contains(widget) }, set: { preferences.layout.setVisible(widget, visible: $0) })) }
   Text(NSLocalizedString("在菜单栏弹窗中点击“编辑组件”或长按组件，可拖动调整顺序。组件设置与主仪表盘分别保存。", comment: "")).font(.caption).presentationSecondary()
   Divider(); Text(NSLocalizedString("弹窗规格指标", comment: "")).font(.subheadline.bold())
   ForEach(DashboardSpecification.allCases) { spec in Toggle(spec.title, isOn: Binding(get: { preferences.layout.specifications.contains(spec) }, set: { value in preferences.layout.specifications.removeAll { $0 == spec }; if value { preferences.layout.specifications.append(spec) } })) }
   Button(NSLocalizedString("预览弹窗", comment: "")) { preview() }
   Button(NSLocalizedString("恢复默认弹窗", comment: "")) { preferences.layout = PopoverLayout(); preferences.showPercentage = true; preferences.animationsEnabled = true }
  }
 }
}
