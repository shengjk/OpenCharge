import SwiftUI
import ChargeCore

struct PowerFlowView: View {
 var snapshot: PowerFlowSnapshot
 var animationEnabled = true
 var compact = false
 var adapterConnected: Bool
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 var body: some View {
  VStack(spacing: 8) {
   GeometryReader { geometry in
    let size = geometry.size
    let inset: CGFloat = compact ? 35 : 55
    let edge: CGFloat = compact ? 34 : 52
    let left = CGPoint(x: inset, y: 70), middle = CGPoint(x: size.width / 2, y: 70), right = CGPoint(x: size.width - inset, y: 70)
    Canvas { context, _ in
     draw(context: &context, from: CGPoint(x: left.x + edge, y: left.y), to: CGPoint(x: middle.x - edge, y: middle.y), watts: snapshot.adapterWatts, active: snapshot.adapterSupplying == true, color: .mint)
     let charging = snapshot.batteryFlow == .charging
     let start = charging ? CGPoint(x: middle.x + edge, y: middle.y) : CGPoint(x: right.x - edge, y: right.y)
     let end = charging ? CGPoint(x: right.x - edge, y: right.y) : CGPoint(x: middle.x + edge, y: middle.y)
     draw(context: &context, from: start, to: end, watts: snapshot.batteryWatts.map(abs), active: charging || snapshot.batteryFlow == .supplyingSystem, color: charging ? .mint : .orange)
    }.accessibilityHidden(true)
    PowerFlowArrows(snapshot: snapshot, compact: compact, enabled: animationEnabled, reduceMotion: reduceMotion)
     .frame(width: size.width, height: size.height).accessibilityHidden(true).allowsHitTesting(false)
    node(String(localized:"适配器"), icon: "powerplug", detail: adapterConnected ? String(localized:"已连接") : String(localized:"未连接")).position(left)
    node("Mac", icon: "laptopcomputer", detail: watts(snapshot.systemWatts)).position(middle)
    node(String(localized:"电池"), icon: "battery.75percent", detail: batteryLabel).position(right)
    Text(watts(snapshot.adapterWatts)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).position(x: (left.x + middle.x) / 2, y: 106)
    Text(watts(snapshot.batteryWatts.map(abs))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).position(x: (middle.x + right.x) / 2, y: 106)
   }.frame(height: 135)
   if !compact { Text(String(localized:"线宽按最新功率缩放；箭头表示供电方向。未知读数显示为 —。各通道可能异步采样，图中不推算能量损耗。")).font(.caption).foregroundStyle(.secondary) }
  }
 }
 private var batteryLabel: String {
  switch snapshot.batteryFlow { case .charging: return String(localized:"正在充电"); case .supplyingSystem: return String(localized:"向 Mac 供电"); case .idle: return String(localized:"接近零功率"); case .unknown: return String(localized:"功率未知") }
 }
 private func watts(_ value: Double?) -> String { value.map { String(format: "%.1f W", $0) } ?? "—" }
 private func node(_ name: String, icon: String, detail: String) -> some View {
  VStack(spacing: 6) { Image(systemName: icon).font(compact ? .headline : .title2); Text(name).font(compact ? .caption.bold() : .callout.bold()); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65) }.frame(width: compact ? 64 : 100, height: compact ? 70 : 90).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))
 }
 private func draw(context: inout GraphicsContext, from: CGPoint, to: CGPoint, watts: Double?, active: Bool, color: Color) {
  let width = active ? min(12, max(3, (watts ?? 0) / 4)) : 2
  var path = Path(); path.move(to: from); path.addLine(to: to)
  context.stroke(path, with: .color(active ? color.opacity(0.22) : .secondary.opacity(0.18)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: watts == nil ? [4, 5] : []))
 }
}
