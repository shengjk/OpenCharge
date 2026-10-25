import Foundation
import SwiftUI
import ChargeCore

extension ChargeModel {
 func editChargeSettings(_ edit: () -> Void) {
  guard allowChargeSettingsEdit() else { return }; edit()
 }
 func chargeSetting<T>(_ keyPath: WritableKeyPath<ChargePolicy, T>) -> Binding<T> {
  Binding(get: { self.config.policy[keyPath: keyPath] }, set: { value in
   self.editChargeSettings { self.config.policy[keyPath: keyPath] = value }
  })
 }
 func setChargeLimitFromGUI(_ value: Double) {
  editChargeSettings { self.config.setChargeLimit(value) }
 }
 func applyChargeSettingsFromGUI() {
  editChargeSettings { self.config.policy.normalize(); self.save(); self.refresh() }
 }
 func profileFromGUI(_ limit: Double, _ width: Double, _ heat: Double) {
  editChargeSettings { self.profile(limit, width, heat) }
 }
}

struct ChargeSettingsLockNotice: View {
 @ObservedObject var model: ChargeModel
 var body: some View {
  if model.settingsLocked {
   Label(String(localized:"充电设置已锁定 · 请联系管理员调整配置"), systemImage: "lock.fill")
    .font(.caption).foregroundStyle(.secondary)
  }
 }
}

// UserDefaults KVO includes changes originating outside the app; editing guards also re-read.
final class SettingsLockObservation: NSObject {
 private let defaults: UserDefaults
 private let changed: @MainActor () -> Void
 init(defaults: UserDefaults, changed: @escaping @MainActor () -> Void) {
  self.defaults = defaults; self.changed = changed
  super.init()
  defaults.addObserver(self, forKeyPath: "settingsLock", options: [.new], context: nil)
 }
 override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
  guard keyPath == "settingsLock" else { super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context); return }
  let callback = changed
  Task { @MainActor in callback() }
 }
 deinit { defaults.removeObserver(self, forKeyPath: "settingsLock") }
}
