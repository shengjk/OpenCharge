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
     Text(String.localizedStringWithFormat(NSLocalizedString("能耗指标 %@", comment: ""), String(format: "%.0f", row.impact))).monospacedDigit()
     Text(row.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU —").monospacedDigit().foregroundStyle(.secondary)
    }
   }
   Text(monitor.status).font(.caption).foregroundStyle(.secondary)
   if let date = monitor.updatedAt { Text(String.localizedStringWithFormat(NSLocalizedString("更新于 %@", comment: ""), DateDisplay.string(date, style:.time))).font(.caption).foregroundStyle(.secondary) }
   Text(NSLocalizedString("仅在本机读取，约每 30 秒更新。系统能耗指标不等于瓦数；接口不可用时显示原因。", comment: "")).font(.caption).foregroundStyle(.secondary)
  }
 }
 private func refresh() { monitor.refresh(sensitivity: EnergySensitivity(rawValue: sensitivity) ?? .balanced, force: true) }
}
