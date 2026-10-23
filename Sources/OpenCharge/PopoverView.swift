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
    ProgressView(value: m.reading?.percent ?? 0, total: 100).tint(.mint)
    Text("目标 \(Int(m.decision.effectiveLimit))% · \(m.decision.reason)").font(.callout)
    Text(m.helperStatus).font(.caption).foregroundStyle(.secondary)
    HStack { Button(m.automationPhase == .topUp ? "停止充满" : "充至满电") { m.toggleTopUp() }; Button(m.automationPhase == .discharging ? "停止放电" : "放电") { m.toggleDischarge() }; Button("自动") { m.changeMode(.automatic) } }
    if editing {
     Text("拖动调整顺序，也可使用上下按钮。关闭勾选隐藏组件。").font(.caption).foregroundStyle(.secondary)
     ForEach(preferences.layout.widgets) { widget in editor(widget) }
     ForEach(PopoverWidget.allCases.filter { !preferences.layout.widgets.contains($0) }) { widget in
      Toggle(widget.title, isOn: Binding(get: { false }, set: { preferences.layout.setVisible(widget, visible: $0) }))
     }
     Button("完成编辑") { setEditing(false) }
    } else {
     ForEach(preferences.layout.widgets) { widget in
      VStack(alignment: .leading, spacing: 10) { Text(widget.title).font(.subheadline.bold()); content(widget) }
       .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
       .onLongPressGesture(minimumDuration: 0.6) { setEditing(true) }
     }
    }
    Divider()
    HStack { Button("打开控制台") { m.openDashboardWindow(); dismiss?() }; Spacer(); Button(editing ? "完成编辑" : "编辑组件") { setEditing(!editing) }; Button("退出") { m.quit() } }
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
   Button { preferences.layout.move(widget, by: -1) } label: { Image(systemName: "arrow.up") }.help("上移 \(widget.title)").disabled(preferences.layout.widgets.first == widget)
   Button { preferences.layout.move(widget, by: 1) } label: { Image(systemName: "arrow.down") }.help("下移 \(widget.title)").disabled(preferences.layout.widgets.last == widget)
  }.padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
  }.frame(height: 44)
 }
 @ViewBuilder private func content(_ widget: PopoverWidget) -> some View {
  switch widget {
  case .specifications:
   if preferences.layout.specifications.isEmpty { Text("未选择规格指标").font(.caption).foregroundStyle(.secondary) }
   ForEach(preferences.layout.specifications) { spec in HStack { Text(spec.title).font(.caption); Spacer(); Text(BatterySpecificationFormatter.value(spec, reading: m.reading)).font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65) } }
  case .powerFlow:
   PowerFlowView(snapshot: PowerFlowSnapshot(adapterWatts: m.reading?.adapterPowerW, batteryWatts: m.watts, systemWatts: m.reading?.systemPowerW), animationEnabled: m.popoverVisible, compact: true, adapterConnected: m.reading?.physicalAdapterConnected ?? (m.reading?.connected ?? false))
  case .energyApps:
   PopoverEnergyView(monitor: m.energyMonitor)
  }
 }
}
struct PopoverEnergyView: View {
 @ObservedObject var monitor: EnergyMonitor
 var body: some View {
  VStack(alignment: .leading, spacing: 9) {
   ForEach(monitor.rows) { row in
    HStack { if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }; Text(row.name).lineLimit(1); Spacer(); Text(row.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "—").foregroundStyle(.secondary) }.font(.caption)
   }
   Text(monitor.status).font(.caption).foregroundStyle(.secondary)
  }
 }
}
struct PopoverSettingsView: View {
 @ObservedObject var preferences: PopoverPreferences
 let preview: () -> Void
 let openEditor: () -> Void
 var body: some View {
  Card("菜单栏弹窗") {
   Toggle("弹窗显示当前电量百分比", isOn: $preferences.showPercentage)
   Toggle("弹窗动画", isOn: $preferences.animationsEnabled)
   Text("系统开启“减少动态效果”时，弹窗也会关闭动画。").font(.caption).foregroundStyle(.secondary)
   Button("打开真实弹窗编辑器") { openEditor() }
   ForEach(PopoverWidget.allCases) { widget in Toggle(widget.title, isOn: Binding(get: { preferences.layout.widgets.contains(widget) }, set: { preferences.layout.setVisible(widget, visible: $0) })) }
   Text("在菜单栏弹窗中点击“编辑组件”或长按组件，可拖动调整顺序。组件设置与主仪表盘分别保存。").font(.caption).foregroundStyle(.secondary)
   Divider(); Text("弹窗规格指标").font(.subheadline.bold())
   ForEach(DashboardSpecification.allCases) { spec in Toggle(spec.title, isOn: Binding(get: { preferences.layout.specifications.contains(spec) }, set: { value in preferences.layout.specifications.removeAll { $0 == spec }; if value { preferences.layout.specifications.append(spec) } })) }
   Button("预览弹窗") { preview() }
   Button("恢复默认弹窗") { preferences.layout = PopoverLayout(); preferences.showPercentage = true; preferences.animationsEnabled = true }
  }
 }
}
