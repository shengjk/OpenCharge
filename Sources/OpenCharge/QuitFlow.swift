import SwiftUI
import AppKit
import IOKit.ps
import ChargeCore
import ChargeHardware

@MainActor final class QuitFlow: NSObject, ObservableObject, NSWindowDelegate {
 @Published private(set) var phase: DischargeExit.Phase = .idle
 @Published private(set) var message = NSLocalizedString("正在结束控制会话…", comment: "")
 private var machine: DischargeExit
 private let prepare: () throws -> Void
 private let readPower: () -> DischargeExit.Power
 private let cancelControl: () -> Void
 private let reply: (Bool) -> Void
 private let clock: () -> TimeInterval
 private var timer: Timer?
 private var window: NSWindow?
 private var finished = false
 init(waitForPower: Bool, timeout: TimeInterval = 15, prepare: @escaping () throws -> Void, readPower: @escaping () -> DischargeExit.Power = QuitFlow.systemPower, cancelControl: @escaping () -> Void, reply: @escaping (Bool) -> Void, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
  machine = DischargeExit(waitForPower: waitForPower, timeout: timeout)
  self.prepare = prepare; self.readPower = readPower; self.cancelControl = cancelControl; self.reply = reply; self.clock = clock
 }
 func start() {
  guard phase == .idle else { return }
  machine.begin(); phase = machine.phase
  let view = NSHostingController(rootView: QuitView(flow: self).padding(24).frame(width: 470))
  let window = NSWindow(contentViewController: view); self.window = window
  window.title = NSLocalizedString("OpenCharge · 正在退出", comment: ""); window.identifier = NSUserInterfaceItemIdentifier("OpenChargeQuit")
  window.styleMask = [.titled, .closable]; window.isReleasedWhenClosed = false; window.delegate = self; window.center()
  window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  startTimer()
 }
 private func startTimer() {
  guard timer == nil, !finished else { return }
  // AppKit's terminateLater runs the modal-panel loop. Register explicitly for it.
  let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
  self.timer = timer; RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .modalPanel)
 }
 private func tick() {
  guard !finished else { return }
  if machine.phase == .preparing {
   do { try prepare(); machine.prepared(now: clock()); message = NSLocalizedString("已发出退出恢复请求，等待 macOS 确认主动放电已结束…", comment: "") }
   catch { machine.preparationFailed(); message = NSLocalizedString("退出恢复失败：", comment: "") + error.localizedDescription }
  } else if machine.phase == .waiting {
   machine.observe(readPower(), now: clock())
   if machine.phase == .needsDecision { message = NSLocalizedString("尚未确认电源状态恢复。你可以重试、取消退出，或选择仍然退出。", comment: "") }
  }
  if phase != machine.phase { phase = machine.phase }
  if phase == .ready { finish(true) }
  else if phase == .needsDecision { timer?.invalidate(); timer = nil }
 }
 func retry() { guard phase == .needsDecision else { return }; machine.begin(); phase = machine.phase; message = NSLocalizedString("正在重试退出恢复…", comment: ""); startTimer() }
 func cancel() { guard !finished else { return }; machine.cancel(); phase = machine.phase; cancelControl(); finish(false) }
 func force() { guard phase == .needsDecision else { return }; machine.force(); phase = machine.phase; finish(true) }
 private func finish(_ allowed: Bool) {
  guard !finished else { return }; finished = true; timer?.invalidate(); timer = nil
  window?.orderOut(nil); window?.contentViewController = nil; window = nil
  reply(allowed)
 }
 func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
 nonisolated static func systemPower() -> DischargeExit.Power {
  guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else { return .unknown }
  if source == kIOPSACPowerValue { return .external }
  guard source == kIOPSBatteryPowerValue else { return .unknown }
  // Physical absence must be explicit; a missing property never proves unplugging.
  return (try? BatteryReader.read().physicalAdapterConnected) == false ? .batteryWithAdapterAbsent : .battery
 }
}
private struct QuitView: View {
 @ObservedObject var flow: QuitFlow
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   Text(NSLocalizedString("正在退出 OpenCharge", comment: "")).font(.headline)
   SelectableStatusText(text: flow.message)
   if flow.phase == .preparing || flow.phase == .waiting { ProgressView().controlSize(.small) }
   Text(NSLocalizedString("取消退出后会保留应用并进入监测模式，需要你明确重新启用充电控制。尚未确认恢复时仍然退出，可能导致显示短暂黑屏；服务恢复仍可能等待心跳超时。", comment: "")).font(.caption).presentationSecondary()
   HStack {
    Button(NSLocalizedString("取消退出", comment: "")) { flow.cancel() }.keyboardShortcut(.cancelAction)
    if flow.phase == .needsDecision {
     Button(NSLocalizedString("重试", comment: "")) { flow.retry() }.keyboardShortcut(.defaultAction)
     Button(NSLocalizedString("仍然退出", comment: "")) { flow.force() }
    }
   }
  }
 }
}
