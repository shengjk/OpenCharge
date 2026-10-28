import AppKit
import Sparkle

/// SDK lifecycle and KVO only. Product identity, feed and archive admission are
/// enforced by SignedUpdateDriver before constructing/starting this session.
@MainActor final class SparkleUpdateSession {
 enum Check { case userInitiated, informational, background }
 private weak var delegate: SPUUpdaterDelegate?
 private var controller: SPUStandardUpdaterController?
 private var observations: [NSKeyValueObservation] = []
 private var started = false
 private(set) var snapshot = SignedUpdateSnapshot()
 var changed: ((SignedUpdateSnapshot) -> Void)?
 init(delegate: SPUUpdaterDelegate) { self.delegate = delegate }
 func start(automaticChecks: Bool, automaticDownloads: Bool) throws {
  guard !started else { return }
  let controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:delegate,userDriverDelegate:nil)
  self.controller = controller
  let updater = controller.updater
  updater.automaticallyChecksForUpdates = automaticChecks
  updater.automaticallyDownloadsUpdates = automaticDownloads
  updater.updateCheckInterval = 12 * 3600
  updater.sendsSystemProfile = false
  observations = [updater.observe(\.canCheckForUpdates,options:[.initial,.new]) { [weak self] _,_ in
   MainActor.assumeIsolated { self?.refresh() }
  }, updater.observe(\.sessionInProgress,options:[.initial,.new]) { [weak self] _,_ in
   MainActor.assumeIsolated { self?.refresh() }
  }, updater.observe(\.automaticallyChecksForUpdates,options:[.new]) { [weak self] _,_ in
   MainActor.assumeIsolated { self?.refresh() }
  }, updater.observe(\.automaticallyDownloadsUpdates,options:[.new]) { [weak self] _,_ in
   MainActor.assumeIsolated { self?.refresh() }
  }, updater.observe(\.lastUpdateCheckDate,options:[.initial,.new]) { [weak self] _,_ in
   MainActor.assumeIsolated { self?.refresh() }
  }]
  do { try updater.start(); started = true; refresh() }
  catch { observations.removeAll(); self.controller = nil; refresh(); throw error }
 }
 func configure(automaticChecks: Bool, automaticDownloads: Bool, resetCycle: Bool) {
  guard let updater = controller?.updater else { return }
  updater.automaticallyChecksForUpdates = automaticChecks
  updater.automaticallyDownloadsUpdates = automaticDownloads
  updater.sendsSystemProfile = false
  if resetCycle { updater.resetUpdateCycleAfterShortDelay() }
  refresh()
 }
 func check(_ kind: Check = .userInitiated) {
  guard started, let updater = controller?.updater, updater.canCheckForUpdates else { return }
  switch kind {
  case .userInitiated: updater.checkForUpdates()
  case .informational: updater.checkForUpdateInformation()
  case .background: updater.checkForUpdatesInBackground()
  }
  refresh()
 }
 private func refresh() {
  snapshot.canCheck = controller?.updater.canCheckForUpdates ?? false
  snapshot.sessionInProgress = controller?.updater.sessionInProgress ?? false
  snapshot.automaticChecks = controller?.updater.automaticallyChecksForUpdates
  snapshot.automaticDownloads = controller?.updater.automaticallyDownloadsUpdates
  snapshot.checkedAt = controller?.updater.lastUpdateCheckDate
  changed?(snapshot)
 }
}
