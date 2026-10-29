import AppKit
import Foundation

enum LowChargeLimitNotice {
 static let key = "lowChargeLimitWarningShown"
 @MainActor static func showIfNeeded(limit: Double, defaults: UserDefaults, present: @MainActor () -> Void = LowChargeLimitNotice.present) {
  guard limit.isFinite, (20...75).contains(limit), !defaults.bool(forKey:key) else { return }
  // Remember before presentation so reentrant UI callbacks cannot show a second alert.
  defaults.set(true,forKey:key)
  present()
 }
 @MainActor static func makeAlert() -> NSAlert {
  let alert = NSAlert()
  alert.messageText = NSLocalizedString("较低充电上限提醒", comment: "")
  alert.informativeText = NSLocalizedString("长期维持较低电量可能导致电量估算失准，严重时可能意外关机。请留意电量读数，并按需使用校准功能。此提醒只显示一次，不会更改充电策略。", comment: "")
  alert.alertStyle = .informational
  alert.addButton(withTitle:NSLocalizedString("知道了", comment: ""))
  return alert
 }
 @MainActor static func present() { _ = makeAlert().runModal() }
}
