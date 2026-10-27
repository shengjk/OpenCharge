import Foundation
import AppKit

/// Explicit application-owned preferences only. OS, managed and unknown keys are retained.
enum AppPreferenceReset {
 static let keys = ["appearance", "menuDisplay", "menuIconStyle", "menuTintLowPower", "showDockIcon",
  "energySensitivity", "dashboardShowOnStartup", "dashboardBackgroundUpdates", "dashboardLayout",
  "popoverAnimationsEnabled", "popoverShowPercentage", "popoverLayout", "menuRightClickAction",
  "updatesAutomatic", "updatesAutomaticDownloads", "updatesPreviews", "updatesLastAttempt", SetupWizardPresentation.key]
 static func removeOverrides(from defaults: UserDefaults) {
  for key in keys where !defaults.objectIsForced(forKey:key) { defaults.removeObject(forKey:key) }
 }
}

@MainActor enum SettingsResetConfirmation {
 static func makeAlert() -> NSAlert {
  let alert = NSAlert()
  alert.messageText = NSLocalizedString("恢复 OpenCharge 默认设置？", comment: "")
  alert.informativeText = NSLocalizedString("将重置充电策略、任务、外观和组件布局，并关闭充电控制及系统模式操作。保留电池历史、校准记录和任务执行历史。服务、登录启动和系统低电量模式需分别管理。", comment: "")
  alert.alertStyle = .warning
  alert.addButton(withTitle:NSLocalizedString("取消", comment: ""))
  alert.addButton(withTitle:NSLocalizedString("恢复默认设置", comment: ""))
  return alert
 }
 static func confirm() -> Bool { makeAlert().runModal() == .alertSecondButtonReturn }
}
