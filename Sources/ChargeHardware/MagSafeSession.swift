import Foundation

public enum MagSafePattern: String { case system, off, green, orange, blinkOrange }

/// Called exclusively on the helper's serial queue. Firmware owns the blink cadence.
public final class MagSafeSession {
 private let controller: MagSafeController
 private var pattern = MagSafePattern.system
 private var sleeping = false
 private var offDuringSleep = false
 public init(controller: MagSafeController) { self.controller = controller }
 public func select(_ next: MagSafePattern, now: TimeInterval) throws {
  pattern = next
  try tick(now: now)
 }
 public func setOffDuringSleep(_ enabled: Bool, now: TimeInterval) throws {
  offDuringSleep = enabled; try tick(now: now)
 }
 public func sleep(now: TimeInterval) throws {
  sleeping = true
  if pattern == .blinkOrange && !offDuringSleep { try controller.set(.orange) }
  try tick(now: now)
 }
 public func wake(now: TimeInterval) throws { sleeping = false; try tick(now: now) }
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
   try controller.set(.orangeBlinking)
  }
 }
 public func restore() throws {
  try controller.restore()
  pattern = .system; offDuringSleep = false; sleeping = false
 }
}
