import SwiftUI
import ChargeCore

/// One projection is consumed by both renderers, including unknown/inactive channels.
struct PowerFlowConnection {
 enum Ink { case mint, orange, secondary }
 let start: CGPoint
 let end: CGPoint
 let lineWidth: CGFloat
 let dash: [CGFloat]
 let ink: Ink
 let opacity: Double

 private init(start: CGPoint, end: CGPoint, watts: Double?, active: Bool, ink: Ink) {
  self.start = start; self.end = end
  lineWidth = active ? min(12, max(3, (watts ?? 0) / 4)) : 2
  dash = watts == nil ? [4, 5] : []
  self.ink = active ? ink : .secondary
  opacity = active ? 0.22 : 0.18
 }

 static func project(_ snapshot: PowerFlowSnapshot, width: CGFloat, compact: Bool) -> [Self] {
  guard width.isFinite, width > 0 else { return [] }
  let inset: CGFloat = compact ? 35 : 55
  let edge: CGFloat = compact ? 34 : 52
  let adapter = Self(start: CGPoint(x: inset + edge, y: 70), end: CGPoint(x: width / 2 - edge, y: 70),
   watts: snapshot.adapterWatts, active: snapshot.adapterSupplying == true, ink: .mint)
  let charging = snapshot.batteryFlow == .charging
  let left = CGPoint(x: width / 2 + edge, y: 70)
  let right = CGPoint(x: width - inset - edge, y: 70)
  let battery = Self(start: charging ? left : right, end: charging ? right : left,
   watts: snapshot.batteryWatts.map(abs), active: charging || snapshot.batteryFlow == .supplyingSystem,
   ink: charging ? .mint : .orange)
  return [adapter, battery]
 }
}

struct PowerFlowConnections: View {
 var snapshot: PowerFlowSnapshot
 var width: CGFloat
 var compact: Bool
 private var connections: [PowerFlowConnection] { PowerFlowConnection.project(snapshot, width: width, compact: compact) }
 var body: some View {
  if #available(macOS 12, *) {
   return AnyView(Canvas { context, _ in
    for line in connections {
     context.stroke(path(line), with: .color(color(line)), style: style(line))
    }
   }.accessibilityHidden(true))
  } else {
   return AnyView(ZStack {
    ForEach(connections.indices, id: \.self) { index in
     let line = connections[index]
     path(line).stroke(color(line), style: style(line))
    }
   }.accessibilityHidden(true))
  }
 }
 private func path(_ line: PowerFlowConnection) -> Path {
  var path = Path(); path.move(to: line.start); path.addLine(to: line.end); return path
 }
 private func style(_ line: PowerFlowConnection) -> StrokeStyle {
  StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, dash: line.dash)
 }
 private func color(_ line: PowerFlowConnection) -> Color {
  let base: Color
  switch line.ink { case .mint: base = PresentationPalette.mint; case .orange: base = .orange; case .secondary: base = .secondary }
  return base.opacity(line.opacity)
 }
}
