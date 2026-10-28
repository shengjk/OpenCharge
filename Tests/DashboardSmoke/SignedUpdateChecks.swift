import Foundation
import ChargeCore
import Sparkle

@MainActor private final class FakeSignedUpdates: SignedUpdateClient {
 var changed: ((SignedUpdateSnapshot) -> Void)?
 var starts = 0, checks = 0
 var configurations: [[Bool]] = []
 var failStart = false
 func start(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) throws {
  starts += 1
  if failStart { throw CocoaError(.fileReadUnknown) }
  configurations.append([automaticChecks,automaticDownloads,includePreviews])
  changed?(SignedUpdateSnapshot(canCheck:true))
 }
 func configure(automaticChecks: Bool, automaticDownloads: Bool, includePreviews: Bool) { configurations.append([automaticChecks,automaticDownloads,includePreviews]) }
 func check() { checks += 1 }
}

@MainActor func signedUpdateChecks() async throws {
 let suite = "org.opencharge.signed-updates.fixture."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 var info: [String:Any] = ["CFBundleIdentifier":"org.opencharge.app","SUPublicEDKey":Data(0..<32).base64EncodedString(),"SUFeedURL":SignedUpdateConfiguration.feedURL.absoluteString,"SUSignedFeedFailureExpirationInterval":0]
 for (key,value) in SignedUpdateConfiguration.requiredBooleans { info[key] = value }
 let readiness = SignedUpdateConfiguration.evaluate(info)
 guard case .ready = readiness else { preconditionFailure("fixture configuration") }
 let fake = FakeSignedUpdates()
 let updates = AppUpdates(defaults:defaults,currentVersion:"1.2.3",signedConfiguration:readiness,signedDriver:fake)
 precondition(updates.usesSignedUpdates && !updates.automaticChecks && !updates.automaticDownloads && !updates.busy)
 updates.start(); updates.start()
 precondition(fake.starts==1 && fake.configurations==[[false,false,true]] && updates.canCheck)
 await updates.check(loadPages:{ preconditionFailure("signed route used unsigned feed") })
 precondition(fake.checks==1)
 updates.automaticChecks=true; updates.automaticDownloads=true; updates.includePreviews=false
 precondition(fake.configurations.last == [true,true,false])
 precondition(defaults.bool(forKey:"updatesAutomaticDownloads"))
 // Native updater UI preference changes must survive the next app launch.
 fake.changed?(SignedUpdateSnapshot(canCheck:true,automaticChecks:false,automaticDownloads:false))
 precondition(!updates.automaticChecks && !updates.automaticDownloads && !defaults.bool(forKey:"updatesAutomaticDownloads"))
 // A prepared installer can outlive the SDK's active check session. Keep reset
 // blocked, but allow the native update UI to be reopened for installation.
 fake.changed?(SignedUpdateSnapshot(canCheck:true,sessionInProgress:false,installationPending:true))
 precondition(updates.busy && updates.canCheck)
 await updates.check(); precondition(fake.checks==2)
 updates.maintenanceBusy = { true }
 await updates.check(); precondition(fake.checks==2 && !updates.canCheck)
 fake.changed?(SignedUpdateSnapshot(canCheck:false,sessionInProgress:true))
 precondition(updates.busy)
 fake.changed?(SignedUpdateSnapshot(canCheck:true))
 precondition(!updates.busy)
 AppPreferenceReset.removeOverrides(from:defaults); updates.reloadAfterReset()
 precondition(!updates.automaticChecks && !updates.automaticDownloads && updates.includePreviews)
 precondition(fake.configurations.last == [false,false,true])
 let invalidFake = FakeSignedUpdates()
 let invalid = AppUpdates(defaults:defaults,currentVersion:"1.2.3",signedConfiguration:.invalid,signedDriver:invalidFake)
 invalid.start(); await invalid.check(loadPages:{ preconditionFailure("invalid config reached network") })
 precondition(invalidFake.starts==0 && invalidFake.checks==0)
 let retryFake = FakeSignedUpdates(); retryFake.failStart=true
 let retry = AppUpdates(defaults:defaults,currentVersion:"1.2.3",signedConfiguration:readiness,signedDriver:retryFake)
 retry.start(); precondition(retryFake.starts==1 && !retry.busy)
 retryFake.failStart=false; await retry.check()
 precondition(retryFake.starts==2 && retryFake.checks==1)
 var maintenance = false
 let driver = SignedUpdateDriver(maintenanceBusy:{ maintenance },architecture:.intel)
 let inert = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:driver,userDriverDelegate:nil)
 let updater = inert.updater
 precondition(!updater.sessionInProgress)
 precondition(driver.feedURLString(for:updater)==SignedUpdateConfiguration.feedURL.absoluteString)
 precondition(driver.allowedChannels(for:updater)==["preview"])
 // Manual/informational checks remain available; background admission follows
 // both product preferences and SDK-owned KVO changes, never a cycle-reset hint.
 do { try driver.updater(updater,mayPerform:.updatesInBackground); preconditionFailure("opt-out background admitted") } catch {}
 try driver.updater(updater,mayPerform:.updates)
 try driver.updater(updater,mayPerform:.updateInformation)
 driver.configure(automaticChecks:true,automaticDownloads:false,includePreviews:true)
 try driver.updater(updater,mayPerform:.updatesInBackground)
 driver.receiveSessionState(SignedUpdateSnapshot(automaticChecks:false))
 do { try driver.updater(updater,mayPerform:.updatesInBackground); preconditionFailure("SDK opt-out ignored") } catch {}
 driver.receiveSessionState(SignedUpdateSnapshot(automaticChecks:true))
 try driver.updater(updater,mayPerform:.updatesInBackground)
 driver.configure(automaticChecks:false,automaticDownloads:false,includePreviews:true)

 maintenance=true
 do { try driver.updater(updater,mayPerform:.updatesInBackground); preconditionFailure("maintenance admitted") } catch {}
 maintenance=false
 let empty = SUAppcastItem.empty()
 do { try driver.updater(updater,shouldProceedWithUpdate:empty,updateCheck:.updates); preconditionFailure("invalid enclosure accepted") } catch {}
 precondition(!driver.updater(updater,shouldDownloadReleaseNotesForUpdate:empty))
 var forced = false
 precondition(!driver.updater(updater,willInstallUpdateOnQuit:empty,immediateInstallationBlock:{ forced=true }))
 precondition(driver.snapshot.installationPending && !forced)
 driver.updater(updater,didFinishUpdateCycleFor:.updatesInBackground,error:nil)
 precondition(driver.snapshot.installationPending)
 // Declining an unwanted background check must retain the prepared-install
 // barrier until the SDK actually dismisses that installer.
 do { try driver.updater(updater,mayPerform:.updatesInBackground); preconditionFailure("pending opt-out background admitted") } catch {
  driver.updater(updater,didAbortWithError:error)
  driver.updater(updater,didFinishUpdateCycleFor:.updatesInBackground,error:error)
 }
 precondition(driver.snapshot.installationPending)
 // The prepared installer survives a rejected new check: neither SDK abort
 // nor cycle completion may make settings reset available prematurely.
 maintenance=true
 do { try driver.updater(updater,mayPerform:.updateInformation); preconditionFailure("pending maintenance admitted") } catch {
  driver.updater(updater,didAbortWithError:error)
  precondition(driver.snapshot.installationPending)
  driver.updater(updater,didFinishUpdateCycleFor:.updateInformation,error:error)
 }
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true))
 precondition(driver.snapshot.installationPending && driver.snapshot.error != nil)
 maintenance=false
 try driver.updater(updater,mayPerform:.updateInformation)
 driver.updater(updater,didAbortWithError:CocoaError(.fileReadUnknown))
 precondition(!driver.snapshot.installationPending && driver.snapshot.error != nil)
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true,sessionInProgress:true))
 precondition(driver.snapshot.error == nil)
 driver.updater(updater,didAbortWithError:CocoaError(.fileReadUnknown))
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true,sessionInProgress:true))
 precondition(driver.snapshot.error != nil,"same-cycle KVO must retain a reported failure")
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true))
 precondition(driver.snapshot.error != nil,"cycle completion must retain a reported failure")
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true,sessionInProgress:true))
 precondition(driver.snapshot.error == nil,"a later SDK-owned check must clear a stale failure")
 precondition(!driver.updater(updater,willInstallUpdateOnQuit:empty,immediateInstallationBlock:{ forced=true }))
 driver.receiveSessionState(SignedUpdateSnapshot(canCheck:true))
 precondition(driver.snapshot.installationPending && driver.snapshot.canCheck && !driver.snapshot.sessionInProgress)
 driver.updater(updater,didAbortWithError:CocoaError(.fileReadUnknown))
 driver.configure(automaticChecks:false,automaticDownloads:false,includePreviews:false)
 precondition(driver.allowedChannels(for:updater).isEmpty)
 do { try driver.start(automaticChecks:false,automaticDownloads:false,includePreviews:false); preconditionFailure("unconfigured fixture started updater") } catch {}
 precondition(!updater.sessionInProgress && !forced)
 print("PASS real SDK adapter delegate: fixed feed/channel, maintenance and enclosure rejection, disabled remote notes, pending-cycle state, normal quit route and unconfigured-start refusal; updater never started")
 print("PASS signed update facade: opt-in defaults, signed/manual separation, native preference sync, persistent pending gate, maintenance admission, reset and startup retry; fake client only")
}
