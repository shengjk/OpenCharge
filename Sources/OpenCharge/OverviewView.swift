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
  if d.paused { Label("更新已暂停 · 窗口未聚焦", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary) }
  if preferences.layout.widgets.isEmpty { Card("仪表盘") { Text("所有卡片均已隐藏，可在设置与诊断中重新显示。").foregroundStyle(.secondary) } }
  ForEach(preferences.layout.widgets) { item in widget(item) }
 }
 @ViewBuilder private func widget(_ item: DashboardWidget) -> some View {
  switch item {
  case .battery:
   Card("当前电量") {
   HStack(spacing: 30) {
    ZStack { Circle().stroke(.mint.opacity(0.12), lineWidth: 13); Circle().trim(from: 0, to: (d.reading?.percent ?? 0) / 100).stroke(.mint, style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90)); VStack { Text(d.title).font(.system(size: 38, weight: .bold, design: .rounded)); Text(d.reading?.connected == true ? "已接入电源" : "使用电池").font(.caption).foregroundStyle(.secondary) } }.frame(width: 160, height: 160)
    VStack(alignment: .leading, spacing: 14) { Text(d.decision.reason).font(.title3.bold()); Text("日常上限 \(Int(d.limit))% · 本次目标 \(Int(d.decision.effectiveLimit))%").foregroundStyle(.secondary); Text(d.helperStatus).font(.caption).foregroundStyle(.secondary); HStack { Button(d.decision.phase == .topUp ? "停止充满" : "充至满电") { m.toggleTopUp() }.buttonStyle(.borderedProminent).tint(.mint); Button("暂停") { m.changeMode(.paused) }; Button("自动") { m.changeMode(.automatic) } }
   }
  }
  }
  case .metrics:
   HStack { Metric(label: "电池温度", value: d.reading?.temperature.map { String(format: "%.1f°C", $0) } ?? "—", icon: "thermometer.medium"); Metric(label: "电池功率", value: d.watts.map { String(format: "%+.1f W", $0) } ?? "—", icon: "bolt"); Metric(label: "循环次数", value: d.reading?.cycleCount.map(String.init) ?? "—", icon: "arrow.triangle.2.circlepath") }
   Text("温度来源：\(d.reading?.temperatureSource?.displayName ?? "不可用")").font(.caption).foregroundStyle(.secondary)
  case .profiles:
   Card("快速配置") { HStack { profile("桌面办公", subtitle: "70% · 宽松保持", limit: 70, width: 10, heat: 35); profile("日常均衡", subtitle: "80% · 温控优先", limit: 80, width: 5, heat: 35); profile("外出准备", subtitle: "100% · 充足电量", limit: 100, width: 5, heat: 35) }; Text("配置只改变策略；硬件控制需要在设置中启用。").font(.caption).foregroundStyle(.secondary) }
  case .powerFlow:
   Card("能量流向") { PowerFlowView(snapshot: PowerFlowSnapshot(adapterWatts: d.reading?.adapterPowerW, batteryWatts: d.watts, systemWatts: d.reading?.systemPowerW), animationEnabled: d.focused, adapterConnected: d.reading?.physicalAdapterConnected ?? (d.reading?.connected ?? false)) }
  case .specifications:
   Card("电池规格") {
   if preferences.layout.specifications.isEmpty { Text("未选择规格指标").foregroundStyle(.secondary) }
   LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 24) {
    ForEach(preferences.layout.specifications) { spec in Metric(label: spec.title, value: d.value(spec), icon: "info.circle") }
   }
   if let nominal = d.reading?.nominalCapacityMAH { Text(String(format: "系统标称容量：%.0f mAh · 与满充容量分别记录", nominal)).font(.caption).foregroundStyle(.secondary) }
   if let hint = d.reading?.healthCondition { Text("系统维护提示：\(hint)").font(.caption).foregroundStyle(.secondary) }
  }
  case .adapter:
   Card("适配器与功耗") {
   Text(d.reading?.adapterName ?? "适配器名称不可用").font(.headline)
   Text(d.reading?.adapterManufacturer ?? "制造商不可用").font(.caption).foregroundStyle(.secondary)
   HStack { Metric(label: "适配器额定", value: d.reading?.adapterWatts.map { String(format: "%.0f W", $0) } ?? "—", icon: "powerplug"); Metric(label: "实际电源输入", value: d.reading?.adapterPowerW.map { String(format: "%.1f W", $0) } ?? "—", icon: "bolt"); Metric(label: "系统负载", value: d.reading?.systemPowerW.map { String(format: "%.1f W", $0) } ?? "—", icon: "laptopcomputer") }
   ForEach([5.0, 15, 30], id: \.self) { minutes in
    if let average = d.powerAverages[minutes] { Text("\(Int(minutes)) 分钟平均：\(String(format: "%.1f W", average.watts)) · 数据覆盖 \(String(format: "%.1f%%", average.coverageFraction * 100))").font(.caption).foregroundStyle(.secondary) }
   }
   Text("额定输出与实际输入分开显示；字段不可读时不估填功率。平均值按采样持续时间加权。").font(.caption).foregroundStyle(.secondary)
  }
  case .energyApps:
   SignificantEnergyView(monitor: m.energyMonitor)
  case .trend:
   Card("最近趋势") { TrendChart(points: Array(d.history.suffix(120))).frame(height: 150) }
  }
 }
 func profile(_ title: String, subtitle: String, limit: Double, width: Double, heat: Double) -> some View { Button { m.profileFromGUI(limit, width, heat) } label: { VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.bordered).disabled(m.settingsLocked) }
}
