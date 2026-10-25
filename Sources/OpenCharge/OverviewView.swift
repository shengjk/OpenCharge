import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct OverviewView: View {
 let m: ChargeModel
 @ObservedObject var d: DashboardPresentation
 @ObservedObject var preferences: DashboardPreferences
 var body: some View {
  if d.paused { Label(NSLocalizedString("更新已暂停 · 窗口未聚焦", comment: ""), systemImage: "pause.circle").font(.caption).presentationSecondary() }
  if preferences.layout.widgets.isEmpty { Card(NSLocalizedString("仪表盘", comment: "")) { Text(NSLocalizedString("所有卡片均已隐藏，可在设置与诊断中重新显示。", comment: "")).presentationSecondary() } }
  ForEach(preferences.layout.widgets) { item in widget(item) }
 }
 @ViewBuilder private func widget(_ item: DashboardWidget) -> some View {
  switch item {
  case .battery:
   Card(NSLocalizedString("当前电量", comment: "")) {
   HStack(spacing: 30) {
    ZStack { Circle().stroke(PresentationPalette.mint.opacity(0.12), lineWidth: 13); Circle().trim(from: 0, to: (d.reading?.percent ?? 0) / 100).stroke(PresentationPalette.mint, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90)); VStack { Text(d.title).font(.system(size: 38, weight: .bold, design: .rounded)); Text(d.reading?.connected == true ? NSLocalizedString("已接入电源", comment: "") : NSLocalizedString("使用电池", comment: "")).font(.caption).presentationSecondary() } }.frame(width: 160, height: 160)
    VStack(alignment: .leading, spacing: 14) { Text(d.decision.reason).font(.title3.bold()); Text(String.localizedStringWithFormat(NSLocalizedString("日常上限 %lld%% · 本次目标 %lld%%", comment: ""), Int64(Int(d.limit)), Int64(Int(d.decision.effectiveLimit)))).presentationSecondary(); Text(d.helperStatus).font(.caption).presentationSecondary(); HStack { Button(d.decision.phase == .topUp ? NSLocalizedString("停止充满", comment: "") : NSLocalizedString("充至满电", comment: "")) { m.toggleTopUp() }.buttonStyle(.borderedProminent).tint(PresentationPalette.mint); Button(NSLocalizedString("暂停", comment: "")) { m.changeMode(.paused) }; Button(NSLocalizedString("自动", comment: "")) { m.changeMode(.automatic) } }
   }
  }
  }
  case .metrics:
   HStack { Metric(label: NSLocalizedString("电池温度", comment: ""), value: d.reading?.temperature.map { String(format: "%.1f°C", $0) } ?? "—", icon: "thermometer.medium"); Metric(label: NSLocalizedString("电池功率", comment: ""), value: d.watts.map { String(format: "%+.1f W", $0) } ?? "—", icon: "bolt"); Metric(label: NSLocalizedString("循环次数", comment: ""), value: d.reading?.cycleCount.map(String.init) ?? "—", icon: "arrow.triangle.2.circlepath") }
   Text(String.localizedStringWithFormat(NSLocalizedString("温度来源：%@", comment: ""), d.reading?.temperatureSource?.displayName ?? NSLocalizedString("不可用", comment: ""))).font(.caption).presentationSecondary()
  case .profiles:
   Card(NSLocalizedString("快速配置", comment: "")) { HStack { profile(NSLocalizedString("桌面办公", comment: ""), subtitle: NSLocalizedString("70% · 宽松保持", comment: ""), limit: 70, width: 10, heat: 35); profile(NSLocalizedString("日常均衡", comment: ""), subtitle: NSLocalizedString("80% · 温控优先", comment: ""), limit: 80, width: 5, heat: 35); profile(NSLocalizedString("外出准备", comment: ""), subtitle: NSLocalizedString("100% · 充足电量", comment: ""), limit: 100, width: 5, heat: 35) }; Text(NSLocalizedString("配置只改变策略；硬件控制需要在设置中启用。", comment: "")).font(.caption).presentationSecondary() }
  case .powerFlow:
   Card(NSLocalizedString("能量流向", comment: "")) { PowerFlowView(snapshot: PowerFlowSnapshot(adapterWatts: d.reading?.adapterPowerW, batteryWatts: d.watts, systemWatts: d.reading?.systemPowerW), animationEnabled: d.focused, adapterConnected: d.reading?.physicalAdapterConnected ?? (d.reading?.connected ?? false)) }
  case .specifications:
   Card(NSLocalizedString("电池规格", comment: "")) {
   if preferences.layout.specifications.isEmpty { Text(NSLocalizedString("未选择规格指标", comment: "")).presentationSecondary() }
   LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 24) {
    ForEach(preferences.layout.specifications) { spec in Metric(label: spec.title, value: d.value(spec), icon: "info.circle") }
   }
   if let nominal = d.reading?.nominalCapacityMAH { Text(String(format: NSLocalizedString("系统标称容量：%.0f mAh · 与满充容量分别记录", comment: ""), nominal)).font(.caption).presentationSecondary() }
   if let hint = d.reading?.healthCondition { Text(String.localizedStringWithFormat(NSLocalizedString("系统维护提示：%@", comment: ""), hint)).font(.caption).presentationSecondary() }
  }
  case .adapter:
   Card(NSLocalizedString("适配器与功耗", comment: "")) {
   Text(d.reading?.adapterName ?? NSLocalizedString("适配器名称不可用", comment: "")).font(.headline)
   Text(d.reading?.adapterManufacturer ?? NSLocalizedString("制造商不可用", comment: "")).font(.caption).presentationSecondary()
   HStack { Metric(label: NSLocalizedString("适配器额定", comment: ""), value: d.reading?.adapterWatts.map { String(format: "%.0f W", $0) } ?? "—", icon: "powerplug"); Metric(label: NSLocalizedString("实际电源输入", comment: ""), value: d.reading?.adapterPowerW.map { String(format: "%.1f W", $0) } ?? "—", icon: "bolt"); Metric(label: NSLocalizedString("系统负载", comment: ""), value: d.reading?.systemPowerW.map { String(format: "%.1f W", $0) } ?? "—", icon: "laptopcomputer") }
   ForEach([5.0, 15, 30], id: \.self) { minutes in
    if let average = d.powerAverages[minutes] { Text(String.localizedStringWithFormat(NSLocalizedString("%lld 分钟平均：%@ · 数据覆盖 %@", comment: ""), Int64(Int(minutes)), String(format: "%.1f W", average.watts), String(format: "%.1f%%", average.coverageFraction * 100))).font(.caption).presentationSecondary() }
   }
   Text(NSLocalizedString("额定输出与实际输入分开显示；字段不可读时不估填功率。平均值按采样持续时间加权。", comment: "")).font(.caption).presentationSecondary()
  }
  case .energyApps:
   SignificantEnergyView(monitor: m.energyMonitor)
  case .trend:
   Card(NSLocalizedString("最近趋势", comment: "")) { TrendChart(points: Array(d.history.suffix(120))).frame(height: 150) }
  }
 }
 func profile(_ title: String, subtitle: String, limit: Double, width: Double, heat: Double) -> some View { Button { m.profileFromGUI(limit, width, heat) } label: { VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(subtitle).font(.caption).presentationSecondary() }.frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.bordered).disabled(m.settingsLocked) }
}
