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
 var backgroundAdmissions = 0
 var backgroundRejections = 0
 var blockBackgroundEnclosures = false
 var admitted = 0
 var policyChecks = 0
 var denied = false
 var profileEnabled: Bool?
 weak var observedUpdater: SPUUpdater?
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
  observedUpdater = updater;profileEnabled = updater.sendsSystemProfile
  do { try policy.updater(updater,mayPerform:check); if check == .updatesInBackground { backgroundAdmissions += 1 } }
  catch { if check == .updatesInBackground { backgroundRejections += 1 }; denied = true; self.error = error as NSError; throw error }
 }
 func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
  if blockBackgroundEnclosures && updateCheck == .updatesInBackground { throw NSError(domain:"org.opencharge.sdk-probe",code:2,userInfo:[NSLocalizedDescriptionKey:"Fixture blocks every background archive before download"]) }
  policyChecks += 1
  try policy.updater(updater,shouldProceedWithUpdate:item,updateCheck:updateCheck); admitted += 1
 }
 func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { policy.updater(updater,shouldDownloadReleaseNotesForUpdate:item) }
 func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { found = item.displayVersionString }
 func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { policy.updater(updater,didAbortWithError:error) }
 func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor check: SPUUpdateCheck, error: Error?) {
  policy.updater(updater,didFinishUpdateCycleFor:check,error:error)
  self.error = error as NSError?; finished = true
 }
}

@MainActor final class ProbeClient: SignedUpdateClient {
 let delegate: ProbeDelegate
 lazy var session = SparkleUpdateSession(delegate:delegate)
 private var configuredPreviews: Bool?
 var snapshots: [SignedUpdateSnapshot] = []
 var changed: ((SignedUpdateSnapshot) -> Void)?
 var afterChange: (() -> Void)?
 init(delegate: ProbeDelegate) {
  self.delegate=delegate
  delegate.policy.changed = { [weak self] value in self?.changed?(value);self?.afterChange?() }
 }
 func start(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) throws {
  configuredPreviews = includePreviews
  delegate.policy.configure(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads,includePreviews:includePreviews)
  session.changed = { [weak self] value in
   guard let self else { return }; self.snapshots.append(value); self.delegate.policy.receiveSessionState(value)
  }
  try session.start(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads)
 }
 func configure(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) {
  let changed = configuredPreviews != includePreviews; configuredPreviews = includePreviews
  delegate.policy.configure(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads,includePreviews:includePreviews)
  session.configure(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads,resetCycle:changed)
 }
 func check() { session.check(.informational) }
}

@main struct SDKProbe {
 @MainActor static func main() throws {
  let arguments = CommandLine.arguments
  precondition(arguments.count == 4)
  precondition(Bundle.main.bundleIdentifier?.hasPrefix("org.opencharge.sdk-probe.") == true)
  let preferenceCase = arguments[1].hasPrefix("channel-")
  precondition(arguments[1] == "informational" || ["channel-optout","channel-optout-downloads","channel-disable","channel-enable"].contains(arguments[1]))
  let feed = URL(string:Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? "")!
  precondition(feed.scheme == "http" && feed.host == "127.0.0.1")
  let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
  let delegate = ProbeDelegate(previews:arguments[2]=="preview",maintenance:arguments[3]=="busy")
  delegate.blockBackgroundEnclosures = preferenceCase
  let client=ProbeClient(delegate:delegate)
  let domain="org.opencharge.sdk-model."+UUID().uuidString
  let defaults=UserDefaults(suiteName:domain)!
  defer { defaults.removePersistentDomain(forName:domain) }
  var info=Bundle.main.infoDictionary!
  info["CFBundleIdentifier"]="org.opencharge.app";info["SUFeedURL"]=SignedUpdateConfiguration.feedURL.absoluteString
  let readiness=SignedUpdateConfiguration.evaluate(info)
  guard case .ready = readiness else { preconditionFailure("fixture configuration") }
  defaults.set(arguments[2]=="preview",forKey:"updatesPreviews")
  let updates=AppUpdates(defaults:defaults,currentVersion:"1.0.0",signedConfiguration:readiness,signedDriver:client)
  var sawBusy=false
  client.afterChange = { [weak updates] in if updates?.busy == true { sawBusy=true } }
  updates.start();updates.start()
  precondition(updates.canCheck && !updates.automaticChecks && !updates.automaticDownloads)
  // Drive actual SDK setters as the native SDK UI would; observe the shared
  // KVO session updating production AppUpdates and its own preference domain.
  client.session.configure(automaticChecks:false,automaticDownloads:true,resetCycle:false)
  precondition(updates.automaticDownloads && defaults.bool(forKey:"updatesAutomaticDownloads"))
  client.session.configure(automaticChecks:false,automaticDownloads:false,resetCycle:false)
  precondition(!updates.automaticDownloads && !defaults.bool(forKey:"updatesAutomaticDownloads"))
  let before=client.snapshots.count
  try client.session.start(automaticChecks:true,automaticDownloads:true)
  precondition(client.snapshots.count==before && !updates.automaticChecks && !updates.automaticDownloads)
  Task { await updates.check(loadPages:{ preconditionFailure("signed check reached manual catalog") }) }
  let deadline = Date().addingTimeInterval(20)
  while !delegate.finished && !delegate.denied && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.025)) }
  // Let the SDK finish its session-end KVO after its delegate completion.
  RunLoop.main.run(until:Date().addingTimeInterval(0.05))
  let idle = !updates.busy && !client.session.snapshot.sessionInProgress
  precondition(idle)
  precondition(updates.checkedAt == client.session.snapshot.checkedAt)
  if !delegate.denied, let error=delegate.error { precondition(updates.status == error.localizedDescription) }
  if preferenceCase {
   precondition(delegate.finished && delegate.error == nil && !delegate.denied)
   if arguments[1] == "channel-optout-downloads" { updates.automaticDownloads = true }
   if arguments[1] == "channel-disable" || arguments[1] == "channel-enable" { updates.automaticChecks = true }
   updates.includePreviews = true
   if arguments[1] == "channel-disable" { updates.automaticChecks = false }
   // Pinned SDK resetUpdateCycleAfterShortDelay fires after one second.
   // Background enclosures are always rejected above before any download.
   let settle = Date().addingTimeInterval(4)
   while Date() < settle { RunLoop.main.run(until:Date().addingTimeInterval(0.025)) }
   let result: [String:Any] = ["identity":Bundle.main.bundleIdentifier!,"case":arguments[1],"automaticChecks":updates.automaticChecks,"automaticDownloads":updates.automaticDownloads,"sendsSystemProfile":delegate.profileEnabled as Any? ?? NSNull(),"backgroundAdmissions":delegate.backgroundAdmissions,"backgroundRejections":delegate.backgroundRejections]
   print("SDK_PREFERENCES "+String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
   return
  }
  var pendingVerified=false
  if delegate.found != nil && delegate.error == nil, let updater=delegate.observedUpdater {
   // Inject the production ready/finish/abort callbacks after a real completed
   // SDK cycle. This tests state composition, not a resumed installer process.
   let handled=delegate.policy.updater(updater,willInstallUpdateOnQuit:SUAppcastItem.empty(),immediateInstallationBlock:{ preconditionFailure("production delegate invoked fixture install") })
   precondition(!handled && updates.busy && updates.canCheck)
   client.session.configure(automaticChecks:false,automaticDownloads:false,resetCycle:false)
   delegate.policy.updater(updater,didFinishUpdateCycleFor:.updateInformation,error:nil)
   precondition(updates.busy && updates.signedSnapshot.installationPending && !updates.signedSnapshot.sessionInProgress)
   delegate.policy.updater(updater,didAbortWithError:CocoaError(.fileReadUnknown))
   precondition(!updates.busy && !updates.signedSnapshot.installationPending && updates.status==delegate.policy.snapshot.error)
   // A later SDK-owned cycle must clear the previous error even when it did
   // not pass through the product's manual-check action.
   delegate.finished=false;delegate.error=nil;delegate.found=nil
   client.session.check(.informational)
   let retryDeadline=Date().addingTimeInterval(20)
   while !delegate.finished && Date()<retryDeadline { RunLoop.main.run(until:Date().addingTimeInterval(0.025)) }
   RunLoop.main.run(until:Date().addingTimeInterval(0.05))
   precondition(delegate.finished && delegate.error == nil && delegate.found != nil && !updates.busy && updates.signedSnapshot.error == nil)
   pendingVerified=true
  }
  AppPreferenceReset.removeOverrides(from:defaults);updates.reloadAfterReset()
  precondition(!updates.automaticChecks && !updates.automaticDownloads && updates.includePreviews)
  let result: [String:Any] = ["finished":delegate.finished,"found":delegate.found as Any? ?? NSNull(),"errorCode":delegate.error?.code as Any? ?? NSNull(),"errorDomain":delegate.error?.domain as Any? ?? NSNull(),"error":delegate.error?.localizedDescription as Any? ?? NSNull(),"admitted":delegate.admitted,"policyChecks":delegate.policyChecks,"denied":delegate.denied,"identity":Bundle.main.bundleIdentifier!,"automaticChecks":updates.automaticChecks,"automaticDownloads":updates.automaticDownloads,"sendsSystemProfile":delegate.profileEnabled as Any? ?? NSNull(),"observedBusy":sawBusy,"observedIdle":idle,"sessionSnapshots":client.snapshots.count,"pendingStateComposition":pendingVerified]
  let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
  print("SDK_PROBE "+String(decoding:data,as:UTF8.self))
  if !delegate.finished && !delegate.denied { exit(2) }
 }
}
