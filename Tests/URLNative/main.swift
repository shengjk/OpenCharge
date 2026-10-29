// Native URL delivery fixture. Production URL delegate/model, isolated files,
// injected telemetry and disabled actuators. No product startup or registration.
import AppKit
import CryptoKit
import ChargeCore
import ChargeHardware

@MainActor final class URLFixtureDelegate: NSObject, NSApplicationDelegate {
 let production = OpenChargeDelegate()
 var model: ChargeModel!
 var defaults: UserDefaults!
 var domain = ""
 var reads = 0
 var watchdog: Timer?
 let directory: URL
 let scenario: String
 init(directory: URL, scenario: String) { self.directory=directory; self.scenario=scenario }
 func record(_ event: String, extra: [String:Any] = [:]) {
  var value=extra;value["event"]=event;value["pid"]=ProcessInfo.processInfo.processIdentifier
  if let model {
   value["limit"]=model.config.policy.limit;value["mode"]=model.config.policy.mode.rawValue
   value["checkpoint"]=model.config.calibrationCheckpoint?.stage.rawValue as Any? ?? NSNull()
   value["changeID"]=model.config.chargeLimitChangeID?.uuidString as Any? ?? NSNull()
   value["hardware"]=model.config.hardwareEnabled;value["reads"]=reads;value["locked"]=model.settingsLocked
   let contents=try! Data(contentsOf:Configuration.url)
   value["hash"]=SHA256.hash(data:contents).map {String(format:"%02x",$0)}.joined()
  }
  let data=try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])+Data([10])
  let file=directory.appendingPathComponent("events.jsonl")
  if !FileManager.default.fileExists(atPath:file.path) { _=FileManager.default.createFile(atPath:file.path,contents:nil) }
  let handle=try! FileHandle(forWritingTo:file);handle.seekToEndOfFile();handle.write(data);try! handle.close()
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  domain="org.opencharge.url-defaults."+UUID().uuidString;defaults=UserDefaults(suiteName:domain)!
  var config=Configuration();config.historyEnabled=false;config.notifications=false;config.systemActionsEnabled=false
  if scenario == "calibration" || scenario == "interrupted" { config.policy.mode = .calibration }
  if scenario == "interrupted" { config.calibrationCheckpoint=CalibrationCheckpoint(stage:.draining) }
  if scenario == "locked" { defaults.set(true,forKey:"settingsLock") }
  try! config.save()
  model=ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no screen lock")},readBattery:{ [weak self] in self?.reads += 1; return BatteryReading(percent:50,connected:true,charging:false) })
  production.model=model
  if scenario == "quit" { try! model.prepareForQuit(request:{_ in preconditionFailure("no quit IPC")}) }
  if scenario == "reset" {
   do { try model.resetSettings(request:{_ in preconditionFailure("no reset IPC")},releaseIdle:{},persist:{_ in throw CocoaError(.fileWriteUnknown)},applyDock:{_ in});preconditionFailure("storage failure") } catch {}
  }
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
  record("ready",extra:["scenario":scenario,"identity":Bundle.main.bundleIdentifier!])
  let deadline=ProcessInfo.processInfo.systemUptime+20
  watchdog=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in MainActor.assumeIsolated {
   if FileManager.default.fileExists(atPath:self.directory.appendingPathComponent("finish").path) { NSApp.terminate(nil) }
   else if ProcessInfo.processInfo.systemUptime > deadline { self.record("watchdog");NSApp.terminate(nil) }
  } }
 }
 func application(_ application: NSApplication, open urls: [URL]) {
  precondition(model != nil && production.model === model)
  production.application(application,open:urls)
  precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true)
  record("url",extra:["urls":urls.map(\.absoluteString)])
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
 func applicationWillTerminate(_ notification: Notification) { watchdog?.invalidate();defaults?.removePersistentDomain(forName:domain);record("terminated") }
}
@main struct URLNativeFixture {
 @MainActor static func main() {
  precondition(Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.urlfixture.")==true)
  if CommandLine.arguments.contains("--query-default-handler") {
   let application=NSWorkspace.shared.urlForApplication(toOpen:URL(string:"opencharge://limit?value=75")!)
   print(application.flatMap { Bundle(url:$0)?.bundleIdentifier } ?? "<none>");return
  }
  let env=ProcessInfo.processInfo.environment
  guard let root=env["OPENCHARGE_DATA_DIR"], let scenario=env["OPENCHARGE_URL_SCENARIO"], ["normal","locked","calibration","interrupted","quit","reset"].contains(scenario),root.hasPrefix("/"),root.contains("/native-url-run-") else { exit(112) }
  let directory=URL(fileURLWithPath:root,isDirectory:true).standardizedFileURL
  precondition(FileManager.default.fileExists(atPath:directory.path))
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let delegate=URLFixtureDelegate(directory:directory,scenario:scenario);app.delegate=delegate
  withExtendedLifetime(delegate) { app.run() }
 }
}
