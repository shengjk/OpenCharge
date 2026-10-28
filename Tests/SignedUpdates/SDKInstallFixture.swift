// Standalone SDK mechanics fixture. Only this random-identity app can be
// downloaded/replaced. Production URL and identity guards are not modified.
import Foundation
import AppKit
import Sparkle

@MainActor final class InstallFixtureDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
 var controller: SPUStandardUpdaterController?
 var install: (() -> Void)?
 var failed = false
 var quitCount = 0
 let info = Bundle.main.infoDictionary!
 var scheduledQuit: Bool { (info["FixtureQuitMode"] as? String)?.hasSuffix("on-quit") == true }
 var version: String { info["CFBundleShortVersionString"] as! String }
 var directory: URL { URL(fileURLWithPath:info["FixtureEvidenceDirectory"] as! String,isDirectory:true) }
 func record(_ event: String, _ fields: [String:Any] = [:]) {
  var value=fields;value["event"]=event;value["version"]=version;value["pid"]=ProcessInfo.processInfo.processIdentifier;value["time"]=Date().timeIntervalSince1970
  let data=try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])+Data([10])
  let path=directory.appendingPathComponent("events.jsonl")
  if !FileManager.default.fileExists(atPath:path.path) { _ = FileManager.default.createFile(atPath:path.path,contents:nil) }
  let handle=try! FileHandle(forWritingTo:path);handle.seekToEndOfFile();handle.write(data);try! handle.synchronize();try! handle.close()
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  record("launched")
  if version == "1.0.1" { record("relaunched-new-version"); NSApp.terminate(nil); return }
  let controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil);self.controller=controller
  let updater=controller.updater
  updater.automaticallyChecksForUpdates=false;updater.automaticallyDownloadsUpdates=true;updater.sendsSystemProfile=false
  do { try updater.start();record("check-background");updater.checkForUpdatesInBackground() }
  catch { failed=true;record("start-error",["description":error.localizedDescription]);NSApp.terminate(nil) }
 }
 func feedURLString(for updater: SPUUpdater) -> String? { info["SUFeedURL"] as? String }
 func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
  let feed=URL(string:info["SUFeedURL"] as! String)!
  guard let url=item.fileURL,url.scheme=="http",url.host=="127.0.0.1",url.port==feed.port,url.path=="/archive.zip",item.displayVersionString=="1.0.1",item.versionString=="2",item.installationType=="application",!item.isDeltaUpdate else { throw CocoaError(.fileReadCorruptFile) }
  record("candidate")
 }
 func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
 func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) { record("download-begin") }
 func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { record("download-end") }
 func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) { record("will-extract-callback") }
 func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) { record("did-extract-callback") }
 func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
  record("ready")
  if scheduledQuit {
   // Match the product's NO return: keep the SDK scheduler, never retain or
   // invoke its immediate-install handler. Only this fixture app is quit.
   DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { self.record("request-normal-quit");NSApp.terminate(nil) }
   return false
  }
  install=immediateInstallationBlock
  DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { self.record("request-install");self.install?() }
  return true
 }
 func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { record("install-begin") }
 func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
  failed=true;let e=error as NSError;record("update-error",["domain":e.domain,"code":e.code,"description":e.localizedDescription]);NSApp.terminate(nil)
 }
 func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor check: SPUUpdateCheck, error: Error?) {
  record("cycle-end",["error":error?.localizedDescription as Any? ?? NSNull()])
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if version == "1.0.1" || failed { return .terminateNow }
  quitCount += 1;record("quit-request",["attempt":quitCount])
  if (info["FixtureQuitMode"] as? String)?.hasPrefix("cancel-once") == true && quitCount == 1 {
   record("quit-cancelled")
   DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
    if self.scheduledQuit { self.record("retry-normal-quit");NSApp.terminate(nil) }
    else { self.record("retry-install");self.install?() }
   }
   return .terminateCancel
  }
  record("cleanup-begin")
  // Like product QuitFlow, service deferred termination in AppKit's modal
  // run loop. A main-queue delay can stall after an ordinary user quit.
  let timer=Timer(timeInterval:0.2,repeats:false) { _ in
   MainActor.assumeIsolated { self.record("cleanup-complete");sender.reply(toApplicationShouldTerminate:true) }
  }
  RunLoop.main.add(timer,forMode:.common);RunLoop.main.add(timer,forMode:.modalPanel)
  return .terminateLater
 }
 func applicationWillTerminate(_ notification: Notification) { record("terminated") }
}

@main struct SDKInstallFixture {
 @MainActor static func main() {
  precondition(Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.sdk-install.")==true)
  let evidence=Bundle.main.infoDictionary?["FixtureEvidenceDirectory"] as! String
  precondition(evidence.hasPrefix("/private/tmp/opencharge-sdk-install-"))
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let delegate=InstallFixtureDelegate();app.delegate=delegate
  withExtendedLifetime(delegate) { app.run() }
 }
}
