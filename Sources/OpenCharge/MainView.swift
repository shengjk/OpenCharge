import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

enum Page: String, CaseIterable, Identifiable { case overview = "概览", control = "充电控制", schedules = "时间表", history = "历史记录", settings = "设置与诊断"
 var id: Self { self }
 var title: String { switch self {
  case .overview: return NSLocalizedString("概览", comment: "")
  case .control: return NSLocalizedString("充电控制", comment: "")
  case .schedules: return NSLocalizedString("时间表", comment: "")
  case .history: return NSLocalizedString("历史记录", comment: "")
  case .settings: return NSLocalizedString("设置与诊断", comment: "")
 } }
 var icon: String { switch self { case .overview: return "square.grid.2x2"; case .control: return "bolt.shield"; case .schedules: return "calendar"; case .history: return "chart.xyaxis.line"; case .settings: return "slider.horizontal.3" } }
}
struct MainView: View {
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  NavigationSplitView {
   VStack(alignment: .leading, spacing: 24) {
    HStack(spacing: 12) { Image(systemName: "bolt.circle.fill").font(.largeTitle).presentationMint(); VStack(alignment: .leading) { Text("OpenCharge").font(.headline); Text(NSLocalizedString("让电池从容一点", comment: "")).font(.caption).presentationSecondary() } }.padding(.horizontal, 12).padding(.top, 22)
    List(Page.allCases, selection: $m.dashboardPage) { p in Label(p.title, systemImage: p.icon).padding(.vertical, 6).tag(p) }.listStyle(.sidebar)
    VStack(alignment: .leading, spacing: 6) { Label(m.config.hardwareEnabled ? NSLocalizedString("硬件控制已启用", comment: "") : NSLocalizedString("只读监测", comment: ""), systemImage: m.config.hardwareEnabled ? "checkmark.shield" : "eye").presentationMint(); Text(NSLocalizedString("本地运行 · 无账户 · 开源", comment: "")).presentationSecondary() }.font(.caption).padding(20)
   }.navigationSplitViewColumnWidth(220)
  } detail: {
   ScrollView {
    VStack(alignment: .leading, spacing: 24) {
     HStack { VStack(alignment: .leading, spacing: 6) { Text((m.dashboardPage ?? .overview).title).font(.system(size: 30, weight: .bold, design: .rounded)); Text(NSLocalizedString("电池照顾，清楚可见。", comment: "")).presentationSecondary() }; Spacer(); Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered) }
     if let error = m.error { HStack { Image(systemName: "exclamationmark.triangle"); Text(error).font(.callout); Spacer(); Button(NSLocalizedString("关闭", comment: "")) { m.error = nil } }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) }
     switch m.dashboardPage ?? .overview { case .overview: OverviewView(m: m, d: m.dashboard, preferences: m.dashboardPreferences); case .control: ControlView(); case .schedules: ScheduleView(); case .history: HistoryView(); case .settings: SettingsView() }
    }.padding(30).frame(maxWidth: 1100, alignment: .leading)
   }.background(Color(NSColor.windowBackgroundColor))
  }.frame(minWidth: 900, minHeight: 650)
 }
}
