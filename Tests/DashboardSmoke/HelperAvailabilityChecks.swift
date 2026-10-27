import Foundation
import AppKit
import ChargeCore
import ChargeHardware

@MainActor func unavailableHelperChecks() async throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = Configuration(); fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 try fixture.save()
 let suite = "org.opencharge.helper-availability."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 let service = HelperService(bundle:.main,backend:nil,legacyCheck:{ false },signatureCheck:{ _ in preconditionFailure("unavailable backend cannot verify or register") })
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{ preconditionFailure("no locks") },readBattery:{ BatteryReading(percent:50,connected:true,charging:false) },helperService:service)
 model.config.hardwareEnabled = true
 let bytes = try Data(contentsOf:Configuration.url)
 await model.removeHelperService(request:{_ in preconditionFailure("unavailable removal must not invoke helper")})
 precondition(model.config.hardwareEnabled && model.error != nil)
 let after = try Data(contentsOf:Configuration.url)
 precondition(after == bytes,"Unavailable removal rewrote configuration before rejecting")
 model.config.hardwareEnabled = false
 print("Unavailable service removal preserves opt-in and disk state before cleanup; injected backend, no helper or system setter")
}


@MainActor private final class PendingHelperRemoval: HelperRegistrationBackend {
 var status: HelperRegistrationStatus = .enabled
 var pending: CheckedContinuation<Void, Error>?
 var registrations = 0
 func register() async throws { registrations += 1 }
 func unregister() async throws { try await withCheckedThrowingContinuation { pending = $0 } }
 func openApprovalSettings() { }
}
@MainActor func helperOperationQuitChecks() async throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var c = Configuration(); c.historyEnabled = false; try c.save()
 let suite = "org.opencharge.helper-quit-fixture."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 let backend = PendingHelperRemoval()
 let service = HelperService(bundle:.main,backend:backend,legacyCheck:{false},signatureCheck:{_ in false})
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no screen lock")},readBattery:{BatteryReading(percent:50,connected:true,charging:false)},helperService:service)
 let operation = Task { do { try await service.unregister() } catch {} }
 let deadline = Date().addingTimeInterval(5)
 while backend.pending == nil && Date() < deadline { await Task.yield() }
 precondition(backend.pending != nil && service.busy)
 let delegate = OpenChargeDelegate(); delegate.model = model
 // Inspect only the delegate's return value; never ask NSApplication to terminate.
 precondition(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
 backend.pending?.resume(throwing:CocoaError(.userCancelled)); backend.pending = nil
 await operation.value
 precondition(!service.busy && delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
 try model.prepareForQuit(request:{_ in preconditionFailure("fixture must not contact helper")})
 await model.registerHelperService()
 precondition(backend.registrations == 0,"quitting model must not start registration")
 print("PASS helper operation quit admission: pending service operation cancels normal termination, completion permits it and quitting refuses registration; no actual termination, authorization or service action")
}


@MainActor private final class AcknowledgedFileRemoval: HelperRegistrationBackend {
 let route = HelperRegistrationRoute.blessedHelper
 var status: HelperRegistrationStatus = .enabled
 var removalPending = true
 var finished = false
 func register() async throws { preconditionFailure("must not register") }
 func unregister() async throws { preconditionFailure("must complete file removal") }
 func uninstall() async throws { finished = true; removalPending = false; status = .notRegistered }
 func openApprovalSettings() { }
}
@MainActor func acknowledgedRemovalRetryChecks() async throws {
 let original = try Configuration.load();defer {try? original.save()}
 var c=Configuration();c.historyEnabled=false;try c.save()
 let suite="org.opencharge.removal-retry-fixture."+UUID().uuidString, backend=AcknowledgedFileRemoval()
 let defaults=UserDefaults(suiteName:suite)!;defer {defaults.removePersistentDomain(forName:suite)}
 let service=HelperService(bundle:.main,backend:backend,legacyCheck:{false},signatureCheck:{_ in preconditionFailure("pending removal cannot require a fresh package")})
 let m=ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no lock")},readBattery:{BatteryReading(percent:50,connected:true,charging:false)},helperService:service)
 m.enableHardware(true,request:{_ in preconditionFailure("pending removal must not query or change hardware")},refresh:{preconditionFailure("pending removal must not refresh control")})
 precondition(!m.config.hardwareEnabled && m.error != nil)
 await m.removeHelperService(deleteFiles:true,request:{_ in preconditionFailure("acknowledged retry must not need a live daemon for redundant restoration")})
 precondition(backend.finished && !m.config.hardwareEnabled && m.error == nil)
 print("PASS acknowledged removal app retry: inactive owned state does not require redundant IPC, pending completion and file/job absence precede success; all backend operations injected")
}
