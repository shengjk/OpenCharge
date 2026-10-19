import SwiftUI
import ChargeCore

struct DashboardSettingsView: View {
 @ObservedObject var preferences: DashboardPreferences
 var body: some View {
  Card("仪表盘") {
   Toggle("启动时显示窗口", isOn: $preferences.showOnStartup)
   Toggle("窗口失焦后继续更新仪表盘", isOn: $preferences.backgroundUpdates)
   Text("关闭后台更新只暂停仪表盘与能耗列表；充电控制、定时任务、菜单栏电量和本地历史继续运行。").font(.caption).foregroundStyle(.secondary)
   Divider()
   Text("卡片与顺序").font(.subheadline.bold())
   ForEach(preferences.layout.widgets) { widget in
    HStack {
     Toggle(widget.title, isOn: visibility(widget))
     Spacer()
     Button { preferences.layout.move(widget, by: -1) } label: { Image(systemName: "arrow.up") }.help("上移 \(widget.title)").disabled(preferences.layout.widgets.first == widget)
     Button { preferences.layout.move(widget, by: 1) } label: { Image(systemName: "arrow.down") }.help("下移 \(widget.title)").disabled(preferences.layout.widgets.last == widget)
    }
   }
   ForEach(DashboardWidget.allCases.filter { !preferences.layout.widgets.contains($0) }) { widget in Toggle(widget.title, isOn: visibility(widget)) }
   Divider()
   Text("规格指标").font(.subheadline.bold())
   LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
    ForEach(DashboardSpecification.allCases) { spec in Toggle(spec.title, isOn: Binding(get: { preferences.layout.specifications.contains(spec) }, set: { preferences.layout.setVisible(spec, visible: $0) })) }
   }
   Button("恢复默认卡片与指标") { preferences.layout = DashboardLayout() }
  }
 }
 private func visibility(_ widget: DashboardWidget) -> Binding<Bool> { Binding(get: { preferences.layout.widgets.contains(widget) }, set: { preferences.layout.setVisible(widget, visible: $0) }) }
}
