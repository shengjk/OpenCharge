import AppKit

@MainActor enum CalibrationRecoveryAlert {
 static func makeAlert(allowRemember: Bool = true) -> NSAlert {
  let alert = NSAlert()
  alert.messageText = NSLocalizedString("上次校准中断", comment: "")
  alert.informativeText = NSLocalizedString("继续上次校准，还是返回日常充电策略？", comment: "")
  alert.addButton(withTitle: NSLocalizedString("继续", comment: ""))
  alert.addButton(withTitle: NSLocalizedString("取消校准", comment: ""))
  let remember = NSButton(checkboxWithTitle: NSLocalizedString("记住我的选择", comment: ""), target: nil, action: nil)
  remember.isEnabled = allowRemember
  remember.sizeToFit()
  alert.accessoryView = remember
  return alert
 }

 static func present(allowRemember: Bool) -> (resume: Bool, remember: Bool)? {
  let alert = makeAlert(allowRemember: allowRemember)
  let response = alert.runModal()
  guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return nil }
  return (response == .alertFirstButtonReturn, (alert.accessoryView as? NSButton)?.state == .on)
 }
}
