import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

@MainActor enum OpenChargeRuntime { static let model = ChargeModel() }
final class OpenChargeDelegate: NSObject, NSApplicationDelegate {
 weak var model: ChargeModel?
 var menuBar: MenuBarController?
 var quitFlow: QuitFlow?
 func applicationDidFinishLaunching(_ notification: Notification) {
  let model = OpenChargeRuntime.model; self.model = model
  let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
  NSApp.setActivationPolicy(showDock ? .regular : .accessory)
  menuBar = MenuBarController(model: model)
  model.updates.start()
  if model.dashboardPreferences.showOnStartup { model.openDashboardWindow() }
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if quitFlow != nil { return .terminateLater }
  guard let model, model.needsQuitPreparation else { return .terminateNow }
  let flow = QuitFlow(waitForPower: model.needsDischargeExitWait, prepare: { try model.prepareForQuit() }, cancelControl: { model.cancelQuit() }, reply: { [weak self] allowed in
   self?.quitFlow = nil; sender.reply(toApplicationShouldTerminate: allowed)
  })
  quitFlow = flow; flow.start(); return .terminateLater
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model?.openDashboardWindow(); return true }
 func application(_ application: NSApplication, open urls: [URL]) { for url in urls { (model ?? OpenChargeRuntime.model).handleURL(url) } }
 func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { menuBar?.close(); model?.cleanupOnQuit() } }
}
struct DashboardRootView: View {
 @ObservedObject var model: ChargeModel
 @AppStorage("appearance") private var appearance = "system"
 var body: some View {
  MainView().environmentObject(model)
   .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
   .background(DashboardWindowObserver(model: model).frame(width: 0, height: 0))
 }
}
struct AppSettingsView: View {
 @ObservedObject var model: ChargeModel
 @AppStorage("appearance") private var appearance = "system"
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 24) {
    if let error = model.error {
     HStack { Image(systemName: "exclamationmark.triangle"); Text(error).font(.callout); Spacer(); Button(String(localized:"关闭")) { model.error = nil } }
      .padding().background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
    SettingsView().environmentObject(model)
   }.padding(24)
  }.frame(width: 780, height: 650)
   .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
 }
}
#if !OPENCHARGE_DASHBOARD_SMOKE
@main struct OpenChargeApp: App {
 @NSApplicationDelegateAdaptor(OpenChargeDelegate.self) private var delegate
 @StateObject private var model = OpenChargeRuntime.model
 init() { OpenChargeShortcuts.updateAppShortcutParameters() }
 var body: some Scene {
  Settings {
   AppSettingsView(model: model)
  }.commands {
   CommandGroup(after: .appInfo) { Button(String(localized:"检查更新…")) { model.updates.showAndCheck() } }
   CommandMenu(String(localized:"窗口")) {
    Button(String(localized:"打开控制台")) { model.openDashboardWindow() }.keyboardShortcut("1")
    Button(String(localized:"预览菜单栏弹窗")) { model.openPopoverPreview() }.keyboardShortcut("2")
    Button(String(localized:"打开菜单栏弹窗")) { delegate.menuBar?.clickStatusItem() }.keyboardShortcut("3")
    Button(String(localized:"编辑菜单栏弹窗")) { delegate.menuBar?.openEditor() }.keyboardShortcut("4")
   }
  }
 }
}
#endif
