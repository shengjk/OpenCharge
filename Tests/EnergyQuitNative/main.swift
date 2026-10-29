// Disposable target/controller. No ChargeModel, telemetry, helper or user-app operations.
import AppKit
import Foundation

@MainActor final class EnergyQuitFixtureDelegate: NSObject, NSApplicationDelegate {
 let root: URL
 let scenario: String
 var timer: Timer?
 init(root: URL, scenario: String) { self.root=root; self.scenario=scenario }
 func record(_ event: String) {
  let data = try! JSONSerialization.data(withJSONObject:["event":event,"pid":ProcessInfo.processInfo.processIdentifier])+Data([10])
  let url=root.appendingPathComponent("events.jsonl")
  if !FileManager.default.fileExists(atPath:url.path) { _=FileManager.default.createFile(atPath:url.path,contents:nil) }
  let handle=try! FileHandle(forWritingTo:url);handle.seekToEndOfFile();handle.write(data);try! handle.close()
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  let own = NSRunningApplication.current
  guard let target=EnergyApplicationQuit.snapshot(own)?.target else {
   let description="fixture identity unavailable: pid=\(own.processIdentifier) bundle=\(own.bundleIdentifier ?? "nil") launch=\(String(describing:own.launchDate)) policy=\(own.activationPolicy.rawValue)\n"
   FileHandle.standardError.write(Data(description.utf8));exit(115)
  }
  try! JSONSerialization.data(withJSONObject:["pid":target.pid,"bundle":target.bundleIdentifier,"launch":target.startTimeMicroseconds]).write(to:root.appendingPathComponent("ready.json"),options:.atomic)
  record("ready")
  let deadline=ProcessInfo.processInfo.systemUptime+20
  timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in MainActor.assumeIsolated {
   if FileManager.default.fileExists(atPath:self.root.appendingPathComponent("finish").path) { NSApp.terminate(nil) }
   else if ProcessInfo.processInfo.systemUptime > deadline { exit(113) }
  } }
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if FileManager.default.fileExists(atPath:root.appendingPathComponent("finish").path) { return .terminateNow }
  record("normal-quit-request")
  return scenario == "cancel" ? .terminateCancel : .terminateNow
 }
 func applicationWillTerminate(_ notification: Notification) { timer?.invalidate();record("terminated") }
}

@main struct EnergyQuitNativeFixture {
 @MainActor static func main() {
  guard Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.energyquitfixture.") == true,
        let path=ProcessInfo.processInfo.environment["OPENCHARGE_ENERGY_QUIT_DIR"],path.hasPrefix("/"),path.contains("/native-energy-quit-run-"),
        let scenario=ProcessInfo.processInfo.environment["OPENCHARGE_ENERGY_QUIT_SCENARIO"],["allow","cancel"].contains(scenario) else { exit(112) }
  let root=URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL
  if CommandLine.arguments.contains("--request") {
   let object=try! JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("ready.json"))) as! [String:Any]
   let pid=(object["pid"] as! NSNumber).int32Value
   guard let app=NSRunningApplication(processIdentifier:pid),app.executableURL?.standardizedFileURL == Bundle.main.executableURL?.standardizedFileURL,
         let snapshot=EnergyApplicationQuit.snapshot(app),snapshot.target.bundleIdentifier == Bundle.main.bundleIdentifier,
         snapshot.target.startTimeMicroseconds == (object["launch"] as! NSNumber).uint64Value else { exit(114) }
   print(EnergyApplicationQuit.request(snapshot.target).rawValue);return
  }
  let application=NSApplication.shared;application.setActivationPolicy(.regular)
  let delegate=EnergyQuitFixtureDelegate(root:root,scenario:scenario);application.delegate=delegate
  withExtendedLifetime(delegate) { application.run() }
 }
}
