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
 @discardableResult func setChargeLimitFromGUI(_ value: Double) -> Bool {
  guard !settingsResetPending else { error = NSLocalizedString("设置重置未完成，请重试；自动控制与任务已暂停",comment:""); return false }
  guard config.policy.mode != .calibration, !calibrationPending else { error = NSLocalizedString("校准期间不能修改上限",comment:""); return false }
  guard allowChargeSettingsEdit() else { return false }
  config.setChargeLimit(value); return true
 }
 func applyChargeSettingsFromGUI(presentLowLimitNotice: @MainActor () -> Void = LowChargeLimitNotice.present) {
  editChargeSettings { self.config.policy.normalize(); self.save(); self.refresh(); self.showLowChargeLimitNotice(present:presentLowLimitNotice) }
 }
 func profileFromGUI(_ limit: Double, _ width: Double, _ heat: Double) {
  editChargeSettings { self.profile(limit, width, heat) }
 }
}

struct ChargeSettingsLockNotice: View {
 @ObservedObject var model: ChargeModel
 var body: some View {
  if model.settingsLocked {
   Label(NSLocalizedString("充电设置已锁定 · 请联系管理员调整配置", comment: ""), systemImage: "lock.fill")
    .font(.caption).presentationSecondary()
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
