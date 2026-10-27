// A unique-identity informational SDK probe. Never constructs AppModel,
// downloads an archive, or requests installation. Transport is a fixture-owned loopback server.
import Foundation
import AppKit
import ChargeCore
import Sparkle

@MainActor final class ProbeDelegate: NSObject, SPUUpdaterDelegate {
 let policy: SignedUpdateDriver
 var finished = false
 var found: String?
 var error: NSError?
 var admitted = 0
 var policyChecks = 0
 var denied = false
 init(previews: Bool, maintenance: Bool) {
  policy = SignedUpdateDriver(maintenanceBusy:{ maintenance },architecture: {
   #if arch(arm64)
   return .appleSilicon
   #else
   return .intel
   #endif
  }())
  super.init()
  policy.configure(automaticChecks:false,automaticDownloads:false,includePreviews:previews)
 }
 func feedURLString(for updater: SPUUpdater) -> String? { Bundle.main.infoDictionary?["SUFeedURL"] as? String }
 func allowedChannels(for updater: SPUUpdater) -> Set<String> { policy.allowedChannels(for:updater) }
 func updater(_ updater: SPUUpdater, mayPerform check: SPUUpdateCheck) throws {
  do { try policy.updater(updater,mayPerform:check) }
  catch { denied = true; self.error = error as NSError; throw error }
 }
 func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
  policyChecks += 1
  try policy.updater(updater,shouldProceedWithUpdate:item,updateCheck:updateCheck); admitted += 1
 }
 func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { policy.updater(updater,shouldDownloadReleaseNotesForUpdate:item) }
 func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found = item.displayVersionString }
 func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor check: SPUUpdateCheck, error: Error?) {
  self.error = error as NSError?; finished = true
 }
}

@main struct SDKProbe {
 @MainActor static func main() throws {
  let arguments = CommandLine.arguments
  precondition(arguments.count == 4)
  precondition(Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.sdk-probe.") == true)
  precondition(arguments[1] == "informational")
  let feed = URL(string:Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? "")!
  precondition(feed.scheme == "http" && feed.host == "127.0.0.1")
  let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
  let delegate = ProbeDelegate(previews:arguments[2]=="preview",maintenance:arguments[3]=="busy")
  let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:delegate,userDriverDelegate:nil)
  let updater = controller.updater
  updater.automaticallyChecksForUpdates = false; updater.automaticallyDownloadsUpdates = false; updater.sendsSystemProfile = false
  try updater.start(); updater.checkForUpdateInformation()
  let deadline = Date().addingTimeInterval(20)
  while !delegate.finished && !delegate.denied && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.025)) }
  let result: [String:Any] = ["finished":delegate.finished,"found":delegate.found as Any? ?? NSNull(),"errorCode":delegate.error?.code as Any? ?? NSNull(),"errorDomain":delegate.error?.domain as Any? ?? NSNull(),"error":delegate.error?.localizedDescription as Any? ?? NSNull(),"admitted":delegate.admitted,"policyChecks":delegate.policyChecks,"denied":delegate.denied,"identity":Bundle.main.bundleIdentifier!,"automaticChecks":updater.automaticallyChecksForUpdates,"automaticDownloads":updater.automaticallyDownloadsUpdates,"sendsSystemProfile":updater.sendsSystemProfile]
  let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
  print("SDK_PROBE "+String(decoding:data,as:UTF8.self))
  if !delegate.finished && !delegate.denied { exit(2) }
 }
}
