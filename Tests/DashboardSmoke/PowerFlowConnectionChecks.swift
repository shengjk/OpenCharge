import Foundation
import ChargeCore

func powerFlowConnectionChecks() {
 func lines(_ adapter: Double?, _ battery: Double?, width: CGFloat = 640, compact: Bool = false) -> [PowerFlowConnection] {
  PowerFlowConnection.project(PowerFlowSnapshot(adapterWatts: adapter, batteryWatts: battery, systemWatts: nil), width: width, compact: compact)
 }
 let unknown = lines(nil, nil)
 precondition(unknown.count == 2)
 precondition(unknown.allSatisfy { $0.ink == .secondary && $0.dash == [4, 5] && $0.lineWidth == 2 && $0.opacity == 0.18 })
 let charging = lines(40, 15)
 precondition(charging[0].start == CGPoint(x: 107, y: 70) && charging[0].end == CGPoint(x: 268, y: 70))
 precondition(charging[0].lineWidth == 10 && charging[0].ink == .mint && charging[0].dash.isEmpty)
 precondition(charging[1].start.x == 372 && charging[1].end.x == 533)
 precondition(charging[1].lineWidth == 3.75 && charging[1].ink == .mint && charging[1].opacity == 0.22)
 let discharge = lines(0, -15)
 precondition(discharge[0].ink == .secondary && discharge[0].lineWidth == 2 && discharge[0].dash.isEmpty)
 precondition(discharge[1].start == charging[1].end && discharge[1].end == charging[1].start)
 precondition(discharge[1].lineWidth == charging[1].lineWidth && discharge[1].ink == .orange)
 precondition(lines(0.1, 0.1).allSatisfy { $0.lineWidth == 3 && $0.ink == .mint })
 precondition(lines(1000, -1000).allSatisfy { $0.lineWidth == 12 })
 precondition(lines(0.09, 0.09).allSatisfy { $0.ink == .secondary && $0.lineWidth == 2 })
 precondition(lines(.infinity, .nan).allSatisfy { $0.dash == [4, 5] && $0.ink == .secondary })
 let compact = lines(40, -15, width: 360, compact: true)
 precondition(compact[0].start.x == 69 && compact[0].end.x == 146)
 precondition(compact[1].start.x == 291 && compact[1].end.x == 214)
 for width: CGFloat in [0, -1, .infinity, .nan] { precondition(lines(40, 15, width: width).isEmpty) }
 print("PASS shared power-flow projection: directed channels, idle/unknown distinctions, power-width bounds and compact geometry; no UI or actuators")
}
