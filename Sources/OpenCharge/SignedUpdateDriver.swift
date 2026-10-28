import AppKit
import ChargeCore
import Sparkle

struct SignedUpdateSnapshot: Equatable {
 var canCheck = false
 var sessionInProgress = false
 var installationPending = false
 var automaticChecks: Bool?
 var automaticDownloads: Bool?
 var checkedAt: Date?
 var error: String?
}

@MainActor protocol SignedUpdateClient: AnyObject {
 var changed: ((SignedUpdateSnapshot) -> Void)? { get set }
 func start(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) throws
 func configure(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool)
 func check()
}

/// The SDK owns authenticated download, extraction and replacement. Application
/// termination still goes through OpenChargeDelegate and QuitFlow.
@MainActor final class SignedUpdateDriver: NSObject, SPUUpdaterDelegate, SignedUpdateClient {
 private var session: SparkleUpdateSession?
 private var started = false
 private var sdkSnapshot = SignedUpdateSnapshot()
 private var previews = true
 private let maintenanceBusy: () -> Bool
 private let architecture: UpdateArchitecture
 private(set) var snapshot = SignedUpdateSnapshot()
 var changed: ((SignedUpdateSnapshot) -> Void)?
 init(maintenanceBusy: @escaping () -> Bool, architecture: UpdateArchitecture) {
  self.maintenanceBusy = maintenanceBusy; self.architecture = architecture; super.init()
 }
 func start(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) throws {
  guard !started else { return }
  guard case .ready = SignedUpdateConfiguration.evaluate(Bundle.main.infoDictionary ?? [:]) else { throw ReleaseUpdateError.invalidFeed }
  previews = includePreviews; snapshot.error = nil
  let session = SparkleUpdateSession(delegate:self); self.session = session
  session.changed = { [weak self] value in self?.receiveSessionState(value) }
  do { try session.start(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads); started = true; refresh() }
  catch { self.session = nil; sdkSnapshot = SignedUpdateSnapshot(); snapshot.error = error.localizedDescription; refresh(); throw error }
 }
 func configure(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) {
  let channelChanged = previews != includePreviews; previews = includePreviews
  session?.configure(automaticChecks:automaticChecks,automaticDownloads:automaticDownloads,resetCycle:channelChanged)
  refresh()
 }
 func check() {
  guard let session, session.snapshot.canCheck, !maintenanceBusy() else { return }
  snapshot.error = nil; session.check(); refresh()
 }
 // A status-only sink shared with the SDK session; it never starts a session
 // or changes identity/feed/archive admission. Keep pending/error delegate
 // state even when KVO reports the active check session has finished.
 func receiveSessionState(_ value: SignedUpdateSnapshot) {
  if value.sessionInProgress && !sdkSnapshot.sessionInProgress { snapshot.error = nil }
  sdkSnapshot = value; refresh()
 }
 private func refresh() {
  let pending = snapshot.installationPending, error = snapshot.error
  snapshot = sdkSnapshot
  snapshot.installationPending = pending; snapshot.error = error
  changed?(snapshot)
 }
 private func requireIdleMaintenance() throws {
  guard !maintenanceBusy() else { throw NSError(domain:"org.opencharge.updates",code:1,userInfo:[NSLocalizedDescriptionKey:NSLocalizedString("服务操作正在进行，请稍候",comment:"")]) }
 }
 func feedURLString(for updater: SPUUpdater) -> String? { SignedUpdateConfiguration.feedURL.absoluteString }
 func allowedChannels(for updater: SPUUpdater) -> Set<String> { previews ? ["preview"] : [] }
 func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws { try requireIdleMaintenance() }
 func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
  try requireIdleMaintenance()
  try SignedUpdateItemPolicy.validate(version:item.displayVersionString,currentVersion:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",build:item.versionString,url:item.fileURL,size:item.contentLength,
   installationType:item.installationType,delta:item.isDeltaUpdate,channel:item.channel,includePreviews:previews,architecture:architecture)
 }
 func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
 func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
  snapshot.installationPending = true; refresh()
  // Keep the SDK's scheduler and its normal quit request. It cannot bypass the
  // app delegate's maintenance/cleanup gate. Do not invoke a force-quit route.
  return false
 }
 func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
  if choice == .skip || (choice == .dismiss && state.stage == .notDownloaded) { snapshot.installationPending = false }
  refresh()
 }
 func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
  snapshot.installationPending = false; snapshot.error = error.localizedDescription; refresh()
 }
 func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
  if let error { snapshot.installationPending = false; snapshot.error = error.localizedDescription }
  refresh()
 }
}
