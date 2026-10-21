import SwiftUI
import AppKit
import QuartzCore
import ChargeCore

/// Only the two moving arrows live in AppKit. Labels and power-width paths remain SwiftUI.
struct PowerFlowArrows: NSViewRepresentable {
 var snapshot: PowerFlowSnapshot
 var compact: Bool
 var enabled: Bool
 var reduceMotion: Bool
 func makeNSView(context: Context) -> PowerFlowArrowView { PowerFlowArrowView() }
 func updateNSView(_ view: PowerFlowArrowView, context: Context) {
  view.configure(snapshot: snapshot, compact: compact, enabled: enabled, reduceMotion: reduceMotion)
 }
}

final class PowerFlowArrowView: NSView {
 override var isFlipped: Bool { true }
 private let adapter = CAShapeLayer()
 private let battery = CAShapeLayer()
 private var snapshot = PowerFlowSnapshot(adapterWatts: nil, batteryWatts: nil, systemWatts: nil)
 private var compact = false
 private var enabled = false
 private var reduceMotion = false
 private var endpoints: [ObjectIdentifier: (CGPoint, CGPoint)] = [:]
 override init(frame frameRect: NSRect) {
  super.init(frame: frameRect)
  wantsLayer = true
  layer?.isGeometryFlipped = true
  for arrow in [adapter, battery] {
   arrow.bounds = CGRect(x: -6, y: -4, width: 12, height: 8)
   arrow.fillColor = nil; arrow.lineWidth = 2
   arrow.lineCap = .round; arrow.lineJoin = .round
   arrow.isHidden = true
   layer?.addSublayer(arrow)
  }
  setAccessibilityElement(false)
 }
 convenience init() { self.init(frame: .zero) }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 func configure(snapshot: PowerFlowSnapshot, compact: Bool, enabled: Bool, reduceMotion: Bool) {
  self.snapshot = snapshot; self.compact = compact; self.enabled = enabled; self.reduceMotion = reduceMotion
  updateArrows()
 }
 override func layout() { super.layout(); updateArrows() }
 override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateArrows() }
 override func viewDidHide() { super.viewDidHide(); updateArrows() }
 override func viewDidUnhide() { super.viewDidUnhide(); updateArrows() }
 override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateArrows() }
 private func updateArrows() {
  guard bounds.width > 0, bounds.height > 0 else {
   adapter.removeAnimation(forKey: "flow"); battery.removeAnimation(forKey: "flow")
   return
  }
  let inset: CGFloat = compact ? 35 : 55
  let edge: CGFloat = compact ? 34 : 52
  let middle = bounds.width / 2
  let running = enabled && !reduceMotion && window != nil && !isHiddenOrHasHiddenAncestor
  CATransaction.begin(); CATransaction.setDisableActions(true)
  effectiveAppearance.performAsCurrentDrawingAppearance {
   update(adapter, from: CGPoint(x: inset + edge, y: 70), to: CGPoint(x: middle - edge, y: 70),
    active: snapshot.adapterSupplying == true, color: .systemMint, running: running)
   let charging = snapshot.batteryFlow == .charging
   let left = CGPoint(x: middle + edge, y: 70), right = CGPoint(x: bounds.width - inset - edge, y: 70)
   update(battery, from: charging ? left : right, to: charging ? right : left,
    active: charging || snapshot.batteryFlow == .supplyingSystem,
    color: charging ? .systemMint : .systemOrange, running: running)
  }
  CATransaction.commit()
 }
 private func update(_ arrow: CAShapeLayer, from: CGPoint, to: CGPoint, active: Bool, color: NSColor, running: Bool) {
  let key = ObjectIdentifier(arrow)
  let old = endpoints[key]
  let changed = old == nil || old!.0 != from || old!.1 != to
  endpoints[key] = (from, to)
  arrow.strokeColor = color.cgColor
  if changed {
   let sign: CGFloat = to.x >= from.x ? 1 : -1
   let path = CGMutablePath()
   path.move(to: CGPoint(x: -sign * 6, y: -4)); path.addLine(to: .zero)
   path.addLine(to: CGPoint(x: -sign * 6, y: 4)); arrow.path = path
  }
  guard active else { arrow.removeAnimation(forKey: "flow"); arrow.isHidden = true; return }
  arrow.isHidden = false
  if running {
   if changed || arrow.animation(forKey: "flow") == nil {
    let motion = CABasicAnimation(keyPath: "position")
    motion.fromValue = NSValue(point: from); motion.toValue = NSValue(point: to)
    motion.duration = 2; motion.repeatCount = .infinity
    motion.timingFunction = CAMediaTimingFunction(name: .linear)
    let phase = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
    motion.beginTime = arrow.convertTime(CACurrentMediaTime(), from: nil) - phase
    arrow.position = from
    arrow.add(motion, forKey: "flow")
   }
  } else {
   let progress = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
   let fallback = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y)
   let midpoint = CGPoint(x: (from.x + to.x) / 2, y: from.y)
   let frozen = changed ? fallback : (arrow.animation(forKey: "flow") != nil ? (arrow.presentation()?.position ?? fallback) : arrow.position)
   arrow.removeAnimation(forKey: "flow")
   arrow.position = reduceMotion ? midpoint : frozen
  }
 }
}
