import SwiftUI
import ChargeCore

struct SignificantEnergyView: View {
 @ObservedObject var monitor: EnergyMonitor
 @AppStorage("energySensitivity") private var sensitivity = EnergySensitivity.balanced.rawValue
 var body: some View {
  Card("高耗能应用") {
   HStack {
    Picker("灵敏度", selection: $sensitivity) {
     ForEach(EnergySensitivity.allCases) { Text($0.displayName).tag($0.rawValue) }
    }.frame(maxWidth: 260)
    Spacer()
    Button("刷新能耗") { refresh() }.disabled(monitor.paused)
   }.onChange(of: sensitivity) { _ in refresh() }
   ForEach(monitor.rows) { row in
    HStack(spacing: 12) {
     if let icon = row.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
     Text(row.name).lineLimit(1)
     Spacer()
     Text("能耗指标 \(String(format: "%.0f", row.impact))").monospacedDigit()
     Text(row.cpuPercent.map { String(format: "CPU %.1f%%", $0) } ?? "CPU —").monospacedDigit().foregroundStyle(.secondary)
    }
   }
   Text(monitor.status).font(.caption).foregroundStyle(.secondary)
   if let date = monitor.updatedAt { Text("更新于 \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
   Text("仅在本机读取，约每 30 秒更新。系统能耗指标不等于瓦数；接口不可用时显示原因。").font(.caption).foregroundStyle(.secondary)
  }
 }
 private func refresh() { monitor.refresh(sensitivity: EnergySensitivity(rawValue: sensitivity) ?? .balanced, force: true) }
}
