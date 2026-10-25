import SwiftUI
import ChargeCore

struct DashboardSettingsView: View {
 @ObservedObject var preferences: DashboardPreferences
 var body: some View {
  Card(NSLocalizedString("仪表盘", comment: "")) {
   Toggle(NSLocalizedString("启动时显示窗口", comment: ""), isOn: $preferences.showOnStartup)
   Toggle(NSLocalizedString("窗口失焦后继续更新仪表盘", comment: ""), isOn: $preferences.backgroundUpdates)
   Text(NSLocalizedString("关闭后台更新只暂停仪表盘与能耗列表；充电控制、定时任务、菜单栏电量和本地历史继续运行。", comment: "")).font(.caption).foregroundStyle(.secondary)
   Divider()
   Text(NSLocalizedString("卡片与顺序", comment: "")).font(.subheadline.bold())
   ForEach(preferences.layout.widgets) { widget in
    HStack {
     Toggle(widget.title, isOn: visibility(widget))
     Spacer()
     Button { preferences.layout.move(widget, by: -1) } label: { Image(systemName: "arrow.up") }.help(String.localizedStringWithFormat(NSLocalizedString("上移 %@", comment: ""), widget.title)).disabled(preferences.layout.widgets.first == widget)
     Button { preferences.layout.move(widget, by: 1) } label: { Image(systemName: "arrow.down") }.help(String.localizedStringWithFormat(NSLocalizedString("下移 %@", comment: ""), widget.title)).disabled(preferences.layout.widgets.last == widget)
    }
   }
   ForEach(DashboardWidget.allCases.filter { !preferences.layout.widgets.contains($0) }) { widget in Toggle(widget.title, isOn: visibility(widget)) }
   Divider()
   Text(NSLocalizedString("规格指标", comment: "")).font(.subheadline.bold())
   LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
    ForEach(DashboardSpecification.allCases) { spec in Toggle(spec.title, isOn: Binding(get: { preferences.layout.specifications.contains(spec) }, set: { preferences.layout.setVisible(spec, visible: $0) })) }
   }
   Button(NSLocalizedString("恢复默认卡片与指标", comment: "")) { preferences.layout = DashboardLayout() }
  }
 }
 private func visibility(_ widget: DashboardWidget) -> Binding<Bool> { Binding(get: { preferences.layout.widgets.contains(widget) }, set: { preferences.layout.setVisible(widget, visible: $0) }) }
}
