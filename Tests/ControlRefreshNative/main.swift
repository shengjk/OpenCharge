// Real production model/timer under AppKit modal and event-tracking loops.
// Isolated configuration, injected battery, disabled hardware/system actions.
import AppKit
import Foundation
import ChargeCore
import ChargeHardware

@MainActor final class RefreshFixtureDelegate: NSObject, NSApplicationDelegate {
 let root: URL
 var model: ChargeModel!
 var reads: [Double]=[]
 var defaults: UserDefaults!
 var suite=""
 init(root: URL) {self.root=root}
 func applicationDidFinishLaunching(_ notification: Notification) {
  suite="org.opencharge.refresh-defaults."+UUID().uuidString;defaults=UserDefaults(suiteName:suite)!
  defaults.set(false,forKey:"dashboardBackgroundUpdates");defaults.set(false,forKey:"updatesAutomatic")
  var config=Configuration();config.historyEnabled=false;config.notifications=false;config.systemActionsEnabled=false;try! config.save()
  model=ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{[weak self] in
   self?.reads.append(ProcessInfo.processInfo.systemUptime)
   return BatteryReading(percent:50,connected:true,charging:false)
  })
  precondition(!model.config.hardwareEnabled)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:460,height:130),styleMask:[.titled],backing:.buffered,defer:false)
  window.title="OpenCharge 刷新验证（模拟电池）"
  let text=NSTextField(labelWithString:"仅使用模拟电量。此测试窗口会自动关闭。")
  text.frame=NSRect(x:24,y:50,width:410,height:28);window.contentView?.addSubview(text);window.center()
  let beforeModal=reads.count;var modalEnded=false
  let closer=Timer(timeInterval:12,repeats:false) {_ in MainActor.assumeIsolated {modalEnded=true;NSApp.abortModal()}}
  RunLoop.main.add(closer,forMode:.common);RunLoop.main.add(closer,forMode:.modalPanel)
  NSApp.runModal(for:window);window.orderOut(nil);closer.invalidate()
  let duringModal=reads.count-beforeModal
  let beforeTracking=reads.count;var trackingEnded=false
  let tracking=Timer(timeInterval:12,repeats:false) {_ in MainActor.assumeIsolated {trackingEnded=true}}
  RunLoop.main.add(tracking,forMode:.eventTracking)
  while !trackingEnded { _=RunLoop.main.run(mode:.eventTracking,before:Date().addingTimeInterval(13)) }
  tracking.invalidate()
  let result:[String:Any]=["pid":ProcessInfo.processInfo.processIdentifier,"modal_finished":modalEnded,"modal_refreshes":duringModal,"tracking_refreshes":reads.count-beforeTracking,"read_times":reads,"hardware_enabled":model.config.hardwareEnabled]
  try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]).write(to:root.appendingPathComponent("result.json"),options:.atomic)
  defaults.removePersistentDomain(forName:suite)
  NSApp.terminate(nil)
 }

}

@main struct ControlRefreshNativeFixture {
 @MainActor static func main() {
  guard Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.refreshfixture.")==true,
        let path=ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"],path.hasPrefix("/"),path.contains("/modal-heartbeat-run-") else {exit(112)}
  let root=URL(fileURLWithPath:path,isDirectory:true)
  let app=NSApplication.shared;app.setActivationPolicy(.regular)
  let delegate=RefreshFixtureDelegate(root:root);app.delegate=delegate
  withExtendedLifetime(delegate) {app.run()}
 }
}
