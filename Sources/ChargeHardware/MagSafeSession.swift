import Foundation

public enum MagSafePattern: String { case system, off, green, orange, blinkOrange }

/// Called exclusively on the helper's serial queue. Time is monotonic uptime.
public final class MagSafeSession {
 private let controller: MagSafeController
 private var pattern = MagSafePattern.system
 private var anchor: TimeInterval = 0
 private var sleeping = false
 private var offDuringSleep = false
 public init(controller: MagSafeController) { self.controller = controller }
 public func select(_ next: MagSafePattern, now: TimeInterval) throws {
  if pattern != next { pattern = next; anchor = now }
  try tick(now: now)
 }
 public func setOffDuringSleep(_ enabled: Bool, now: TimeInterval) throws {
  offDuringSleep = enabled; try tick(now: now)
 }
 public func sleep(now: TimeInterval) throws { sleeping = true; try tick(now: now) }
 public func wake(now: TimeInterval) throws { sleeping = false; anchor = now; try tick(now: now) }
 public func tick(now: TimeInterval) throws {
  if sleeping {
   if offDuringSleep { try controller.set(.off) }
   // No flashing or wakeup writes while sleeping unless explicitly suppressing the LED.
   return
  }
  switch pattern {
  case .system: try controller.restore()
  case .off: try controller.set(.off)
  case .green: try controller.set(.green)
  case .orange: try controller.set(.orange)
  case .blinkOrange:
   let elapsed = max(0, now - anchor)
   try controller.set(Int(elapsed.truncatingRemainder(dividingBy: 2)) == 0 ? .orange : .off)
  }
 }
 public func restore() throws {
  try controller.restore()
  pattern = .system; offDuringSleep = false; sleeping = false
 }
}
