import AppKit
import QuartzCore
import ChargeCore

@MainActor func powerFlowAnimationChecks() {
 // Inspect a private, never-shown view/layer tree. No user settings or actuators.
 let view = PowerFlowArrowView(frame: NSRect(x: 0, y: 0, width: 640, height: 135))
 let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
 window.isReleasedWhenClosed = false; window.contentView = view
 let layers = view.layer!.sublayers! as! [CAShapeLayer]
 precondition(layers.count == 2)
 let adapter = layers[0], battery = layers[1]
 func configure(_ watts: Double?, enabled: Bool = true, reduced: Bool = false, compact: Bool = false, input: Double? = 40) {
  view.configure(snapshot: PowerFlowSnapshot(adapterWatts: input, batteryWatts: watts, systemWatts: 20), compact: compact, enabled: enabled, reduceMotion: reduced)
 }
 func motion(_ layer: CAShapeLayer) -> CABasicAnimation { layer.animation(forKey: "flow") as! CABasicAnimation }
 configure(nil, input: nil)
 precondition(layers.allSatisfy { $0.isHidden && $0.animation(forKey: "flow") == nil })
 configure(15)
 precondition(!adapter.isHidden && !battery.isHidden && adapter.path != nil && battery.path != nil)
 precondition((motion(adapter).fromValue as! NSValue).pointValue == CGPoint(x: 107, y: 70))
 precondition((motion(adapter).toValue as! NSValue).pointValue == CGPoint(x: 268, y: 70))
 precondition((motion(battery).fromValue as! NSValue).pointValue.x == 372)
 precondition((motion(battery).toValue as! NSValue).pointValue.x == 533)
 precondition(motion(adapter).duration == 2 && motion(adapter).repeatCount == .infinity)
 let started = motion(adapter).beginTime
 configure(25, input: 60)
 precondition(motion(adapter).beginTime == started, "telemetry updates must not restart the animation")
 configure(-15)
 precondition((motion(battery).fromValue as! NSValue).pointValue.x == 533)
 precondition((motion(battery).toValue as! NSValue).pointValue.x == 372)
 precondition(battery.path!.boundingBoxOfPath.minX == 0)
 configure(0)
 precondition(battery.isHidden && battery.animation(forKey: "flow") == nil)
 configure(15)
 precondition(battery.path!.boundingBoxOfPath.minX == -6 && !battery.isHidden)
 configure(15, enabled: false)
 precondition(layers.allSatisfy { $0.animation(forKey: "flow") == nil })
 let frozen = adapter.position
 configure(25, enabled: false)
 precondition(adapter.position == frozen)
 configure(15, reduced: true)
 precondition(layers.allSatisfy { $0.animation(forKey: "flow") == nil })
 precondition(adapter.position == CGPoint(x: 187.5, y: 70) && battery.position.x == 452.5)
 configure(15, compact: true)
 precondition((motion(adapter).fromValue as! NSValue).pointValue.x == 69)
 precondition((motion(adapter).toValue as! NSValue).pointValue.x == 286)
 view.setFrameSize(NSSize(width: 800, height: 135)); view.layout()
 precondition((motion(adapter).toValue as! NSValue).pointValue.x == 366)
 view.isHidden = true
 precondition(layers.allSatisfy { $0.animation(forKey: "flow") == nil })
 view.isHidden = false
 precondition(adapter.animation(forKey: "flow") != nil)
 view.setFrameSize(.zero); view.layout()
 precondition(layers.allSatisfy { $0.animation(forKey: "flow") == nil }, "zero-sized hosts must stop compositor animation")
 view.setFrameSize(NSSize(width: 800, height: 135)); view.layout()
 precondition(adapter.animation(forKey: "flow") != nil)
 window.contentView = nil
 precondition(layers.allSatisfy { $0.animation(forKey: "flow") == nil })
 print("Power-flow layers preserve direction, two-second motion, live widths' independent updates, compact/resize geometry, reduced motion and pause/zero-size/detach lifecycle; private never-shown layer fixture")
}
