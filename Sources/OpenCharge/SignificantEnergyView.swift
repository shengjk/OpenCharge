import SwiftUI
import ChargeCore

struct SignificantEnergyView: View {
 @ObservedObject var monitor: EnergyMonitor
 @AppStorage("energySensitivity") private var sensitivity = EnergySensitivity.balanced.rawValue
 var body: some View {
  Card(NSLocalizedString("高耗能应用", comment: "")) {
   HStack {
    Picker(NSLocalizedString("灵敏度", comment: ""), selection: $sensitivity) {
     ForEach(EnergySensitivity.allCases) { Text($0.displayName).tag($0.rawValue) }
    }.frame(maxWidth: 260)
    Spacer()
    Button(NSLocalizedString("刷新能耗", comment: "")) { refresh() }.disabled(monitor.paused)
   }.onChange(of: sensitivity) { _ in refresh() }
   ForEach(monitor.rows) { row in
    HStack(spacing: 12) {
     if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
     Text(row.name).lineLimit(1)
     Spacer()
     Text(String.localizedStringWithFormat(NSLocalizedString("能耗指标 %@", comment: ""), String(format: "%.0f", row.impact))).font(.body.monospacedDigit())
     Text(row.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU —").font(.body.monospacedDigit()).presentationSecondary()
     if let target = row.quitTarget { EnergyQuitButton(monitor:monitor,target:target,name:row.name) }
    }
   }
   Text(monitor.status).font(.caption).presentationSecondary()
   if let date = monitor.updatedAt { Text(String.localizedStringWithFormat(NSLocalizedString("更新于 %@", comment: ""), DateDisplay.string(date, style:.time))).font(.caption).presentationSecondary() }
   Text(NSLocalizedString("能耗信息仅在本机读取，约每 30 秒更新；系统指标不等于瓦数。退出按钮会请求应用正常退出。", comment: "")).font(.caption).presentationSecondary()
  }
 }
 private func refresh() { monitor.refresh(sensitivity: EnergySensitivity(rawValue: sensitivity) ?? .balanced, force: true) }
}


struct EnergyQuitButton: View {
 @ObservedObject var monitor: EnergyMonitor
 let target: EnergyQuitTarget
 let name: String
 var body: some View {
  Button(monitor.quitRequested.contains(target) ? NSLocalizedString("已请求退出", comment: "") : NSLocalizedString("退出", comment: "")) { monitor.requestQuit(target) }
   .disabled(monitor.quitRequested.contains(target))
   .help(NSLocalizedString("请求应用正常退出；应用可以要求保存文件或取消。", comment: ""))
   .accessibilityLabel(String.localizedStringWithFormat(NSLocalizedString("退出应用 %@", comment: ""),name))
 }
}
