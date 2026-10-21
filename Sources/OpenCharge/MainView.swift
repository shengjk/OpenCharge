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
 var icon: String { switch self { case .overview: return "square.grid.2x2"; case .control: return "bolt.shield"; case .schedules: return "calendar"; case .history: return "chart.xyaxis.line"; case .settings: return "slider.horizontal.3" } }
}
struct MainView: View {
 @EnvironmentObject var m: ChargeModel
 var body: some View {
  NavigationSplitView {
   VStack(alignment: .leading, spacing: 24) {
    HStack(spacing: 12) { Image(systemName: "bolt.circle.fill").font(.largeTitle).foregroundStyle(.mint); VStack(alignment: .leading) { Text("OpenCharge").font(.headline); Text("让电池从容一点").font(.caption).foregroundStyle(.secondary) } }.padding(.horizontal, 12).padding(.top, 22)
    List(Page.allCases, selection: $m.dashboardPage) { p in Label(p.rawValue, systemImage: p.icon).padding(.vertical, 6).tag(p) }.listStyle(.sidebar)
    VStack(alignment: .leading, spacing: 6) { Label(m.config.hardwareEnabled ? "硬件控制已启用" : "只读监测", systemImage: m.config.hardwareEnabled ? "checkmark.shield" : "eye").foregroundStyle(.mint); Text("本地运行 · 无账户 · 开源").foregroundStyle(.secondary) }.font(.caption).padding(20)
   }.navigationSplitViewColumnWidth(220)
  } detail: {
   ScrollView {
    VStack(alignment: .leading, spacing: 24) {
     HStack { VStack(alignment: .leading, spacing: 6) { Text((m.dashboardPage ?? .overview).rawValue).font(.system(size: 30, weight: .bold, design: .rounded)); Text("电池照顾，清楚可见。").foregroundStyle(.secondary) }; Spacer(); Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered) }
     if let error = m.error { HStack { Image(systemName: "exclamationmark.triangle"); Text(error).font(.callout); Spacer(); Button("关闭") { m.error = nil } }.padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) }
     switch m.dashboardPage ?? .overview { case .overview: OverviewView(m: m, d: m.dashboard, preferences: m.dashboardPreferences); case .control: ControlView(); case .schedules: ScheduleView(); case .history: HistoryView(); case .settings: SettingsView() }
    }.padding(30).frame(maxWidth: 1100, alignment: .leading)
   }.background(Color(nsColor: .windowBackgroundColor))
  }.frame(minWidth: 900, minHeight: 650)
 }
}
