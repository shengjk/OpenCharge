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
 let scripted = ProcessInfo.processInfo.environment["OPENCHARGE_QUIT_SCRIPT"]
 var scriptTimer: Timer?
 var finalCalls = 0
 var commitAttempted = false
 let log: URL = {
  if let value = ProcessInfo.processInfo.environment["OPENCHARGE_QUIT_LOG"] { return URL(fileURLWithPath:value) }
  return FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-quit-fixture-"+UUID().uuidString+".json")
 }()
 func record(_ text: String) {
  events.append(text)
  try! JSONSerialization.data(withJSONObject: events, options: .prettyPrinted).write(to: log, options: .atomic)
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root); let app = NSMenu(); root.submenu = app
  app.addItem(withTitle: "Quit Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); NSApp.mainMenu = menu
  if let scripted {
   precondition(["commit-success","prepare-cancel","commit-retry","commit-force","prepare-retry","local-final-cancel","lease-renew-cancel"].contains(scripted))
   scenario = scripted; record("started")
   let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.driveScript() } }
   scriptTimer = timer; RunLoop.main.add(timer,forMode:.common); RunLoop.main.add(timer,forMode:.modalPanel)
   // terminateLater enters a nested loop before terminate returns. Its initiating
   // timer must be distinct from the timer driving choices inside that loop.
   let launch = Timer(timeInterval:0.05,repeats:false) { _ in MainActor.assumeIsolated { NSApp.terminate(nil) } }
   RunLoop.main.add(launch,forMode:.common); RunLoop.main.add(launch,forMode:.modalPanel)
   return
  }
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
 func driveScript() {
  guard let flow else { return }
  if scenario == "prepare-cancel", flow.phase == .waiting { flow.cancel() }
  else if scenario == "lease-renew-cancel", flow.phase == .needsDecision, events.contains("renew") { flow.cancel() }
  else if scenario == "prepare-retry", flow.phase == .needsDecision { flow.retry() }
  else if flow.finalizationFailed {
   if scenario == "commit-retry" { precondition(!flow.canCancel); flow.cancel(); flow.retry() }
   else if scenario == "commit-force" { precondition(!flow.canCancel); flow.force() }
   else if scenario == "local-final-cancel" { precondition(flow.canCancel); flow.cancel() }
  }
 }
 @objc func success() { scenario = "success"; attempts = 0; NSApp.terminate(nil) }
 @objc func failure() { scenario = "failure"; attempts = 0; NSApp.terminate(nil) }
 @objc func timeout() { scenario = "timeout"; attempts = 0; NSApp.terminate(nil) }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  guard scenario != "ordinary" else { record("ordinary-quit"); return .terminateNow }
  if flow != nil { record("duplicate-quit"); return .terminateLater }
  started = ProcessInfo.processInfo.systemUptime; record("request-" + scenario)
  let flow = QuitFlow(waitForPower: !["commit-success","commit-retry","commit-force","local-final-cancel"].contains(scenario), timeout: 2, prepare: { [self] in
   attempts += 1; record("prepare-\(attempts)")
   if (scenario == "failure" || scenario == "prepare-retry") && attempts == 1 { throw NSError(domain: "FakeHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "假服务暂不可用（未发送硬件请求）"]) }
  }, readPower: { [self] in
   record("power-read")
   return scenario != "timeout" && scenario != "lease-renew-cancel" && ProcessInfo.processInfo.systemUptime - started >= 1 ? .external : .unknown
  }, cancelControl: { [self] in precondition(!commitAttempted); record("cancel-control") }, renewPreparation:{ [self] in record("renew") }, finalize: { [self] in
   finalCalls += 1; record("confirm-\(finalCalls)")
   if scenario == "local-final-cancel" { throw NSError(domain:"FakeHelper",code:2) }
   commitAttempted = true
   if ["commit-retry","commit-force"].contains(scenario), finalCalls == 1 { throw NSError(domain:"FakeHelper",code:3,userInfo:[NSLocalizedDescriptionKey:"Simulated lost commit reply"]) }
  }, commitStarted:{ [self] in commitAttempted }, reply: { [weak self] allowed in
   guard let self else { return }; record(allowed ? "reply-yes" : "reply-no"); self.flow = nil; scenario = "ordinary"
   sender.reply(toApplicationShouldTerminate: allowed)
   if !allowed, scripted != nil {
    scriptTimer?.invalidate()
    let timer = Timer(timeInterval:0.2,repeats:false) { _ in MainActor.assumeIsolated { NSApp.terminate(nil) } }
    scriptTimer = timer; RunLoop.main.add(timer,forMode:.common); RunLoop.main.add(timer,forMode:.modalPanel)
   }
  })
  self.flow = flow; flow.start(); return .terminateLater
 }
 func applicationWillTerminate(_ notification: Notification) { record("terminated") }
}
@main struct QuitFixture {
 @MainActor static func main() { let app = NSApplication.shared; let delegate = FixtureDelegate(); app.delegate = delegate; withExtendedLifetime(delegate) { app.run() } }
}
