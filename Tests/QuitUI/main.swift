// Native AppKit termination harness. No ChargeModel, helper, telemetry or hardware access.
import AppKit
import ChargeCore

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
 var window: NSWindow!
 var flow: QuitFlow?
 var scenario = "ordinary"
 var attempts = 0
 var started = 0.0
 var events: [String] = []
 let log = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-quit-fixture-" + UUID().uuidString + ".json")
 func record(_ text: String) {
  events.append(text)
  try! JSONSerialization.data(withJSONObject: events, options: .prettyPrinted).write(to: log, options: .atomic)
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root); let app = NSMenu(); root.submenu = app
  app.addItem(withTitle: "Quit Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); NSApp.mainMenu = menu
  let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 16; stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
  stack.addArrangedSubview(NSTextField(labelWithString: "OpenCharge 退出验证 · 全部为假服务与假电源读数"))
  for (title, action) in [("等待后成功退出", #selector(success)), ("恢复失败，可重试/取消", #selector(failure)), ("电源超时，可仍然退出", #selector(timeout))] {
   stack.addArrangedSubview(NSButton(title: title, target: self, action: action))
  }
  stack.addArrangedSubview(NSTextField(labelWithString: log.path))
  window = NSWindow(contentViewController: NSViewController()); window.contentView = stack
  window.title = "OpenCharge Exit Fixture"; window.setContentSize(NSSize(width: 650, height: 260)); window.styleMask = [.titled, .closable]; window.center(); window.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true); record("started")
 }
 @objc func success() { scenario = "success"; attempts = 0; NSApp.terminate(nil) }
 @objc func failure() { scenario = "failure"; attempts = 0; NSApp.terminate(nil) }
 @objc func timeout() { scenario = "timeout"; attempts = 0; NSApp.terminate(nil) }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  guard scenario != "ordinary" else { record("ordinary-quit"); return .terminateNow }
  if flow != nil { record("duplicate-quit"); return .terminateLater }
  started = ProcessInfo.processInfo.systemUptime; record("request-" + scenario)
  let flow = QuitFlow(waitForPower: true, timeout: 2, prepare: { [self] in
   attempts += 1; record("prepare-\(attempts)")
   if scenario == "failure" && attempts == 1 { throw NSError(domain: "FakeHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "假服务暂不可用（未发送硬件请求）"]) }
  }, readPower: { [self] in
   record("power-read")
   return scenario != "timeout" && ProcessInfo.processInfo.systemUptime - started >= 1 ? .external : .unknown
  }, cancelControl: { [self] in record("cancel-control") }, reply: { [weak self] allowed in
   guard let self else { return }; record(allowed ? "reply-yes" : "reply-no"); self.flow = nil; scenario = "ordinary"
   sender.reply(toApplicationShouldTerminate: allowed)
  })
  self.flow = flow; flow.start(); return .terminateLater
 }
 func applicationWillTerminate(_ notification: Notification) { record("terminated") }
}
@main struct QuitFixture {
 @MainActor static func main() { let app = NSApplication.shared; let delegate = FixtureDelegate(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
}
