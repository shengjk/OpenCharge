import Foundation
import Security

@MainActor private final class SuspendedRegistration: HelperRegistrationBackend {
 let route = HelperRegistrationRoute.blessedHelper
 var status: HelperRegistrationStatus = .notRegistered
 var pending: CheckedContinuation<Void, Error>?
 var calls = 0
 func register() async throws {
  calls += 1
  try await withCheckedThrowingContinuation { pending = $0 }
  status = .enabled
 }
 func unregister() async throws { calls += 1; status = .notRegistered }
 func openApprovalSettings() { }
}
@MainActor func legacyRegistrationChecks(bundle: Bundle) async throws {
 precondition(!LegacyHelperPackage.valid(bundle),"ad-hoc package cannot satisfy legacy authorization")
 let backend = SuspendedRegistration()
 var installation = HelperInstallation.none
 var packageAllowed = true
 let service = HelperService(bundle:bundle,backend:backend,installationCheck:{installation},signatureCheck:{_ in true},legacyPackageCheck:{_ in packageAllowed})
 precondition(service.registrationAllowed && !service.canUnregister)
 let first = Task { try await service.register() }
 while backend.pending == nil { await Task.yield() }
 precondition(service.busy && backend.calls == 1)
 do { try await service.register(); preconditionFailure("overlapping registration accepted") } catch HelperServiceError.ineligible { }
 do { try await service.unregister(); preconditionFailure("overlapping removal accepted") } catch HelperServiceError.ineligible { }
 precondition(backend.calls == 1)
 backend.pending?.resume(); backend.pending = nil
 try await first.value
 precondition(!service.busy && !service.canUnregister,"job without verified installed ownership cannot be removed")
 do { try await service.unregister(); preconditionFailure("unowned running job removed") } catch HelperServiceError.ineligible { }
 installation = .olderNative(ownedByApp:true); service.refresh()
 precondition(service.registrationAllowed && service.canUnregister)
 try await service.unregister()
 precondition(backend.status == .notRegistered && service.legacyInstalled && !service.canUnregister)
 packageAllowed = false; service.refresh(); precondition(!service.registrationAllowed)
 for state in [HelperInstallation.olderNative(ownedByApp:false),.unrecognized,.developmentLayout] {
  installation = state; service.refresh()
  precondition(!service.registrationAllowed && !service.canUnregister)
  do { try await service.register(); preconditionFailure("conflicting route installed") } catch HelperServiceError.ineligible { }
  do { try await service.unregister(); preconditionFailure("conflicting route removed") } catch HelperServiceError.ineligible { }
 }
 // The actual async worker uses injected authorization/installer functions only.
 var events: [String] = [], cancelled = false, fail = false
 let reference = AuthorizationRef(bitPattern:1)!
 let operations = LegacyHelperOperations(status:{.notRegistered},authorize:{ op in
  precondition(!Thread.isMainThread); events.append(op == .install ? "authorize-install" : "authorize-remove")
  if cancelled { throw NSError(domain:NSOSStatusErrorDomain,code:Int(errAuthorizationCanceled)) }
  return reference
 },release:{ value in precondition(value == reference); events.append("free") },install:{ _ in
  events.append("install"); if fail { throw CocoaError(.fileWriteUnknown) }
 },remove:{ _ in events.append("remove"); if fail { throw CocoaError(.fileWriteUnknown) } })
 let actual = LegacyHelperRegistration(operations:operations)
 precondition(actual.status == .notRegistered && events.isEmpty)
 try await actual.register(); precondition(events == ["authorize-install","install","free"])
 events = []; try await actual.unregister(); precondition(events == ["authorize-remove","remove","free"])
 events = []; cancelled = true
 do { try await actual.register(); preconditionFailure("cancel ignored") } catch { precondition((error as NSError).code == Int(errAuthorizationCanceled)) }
 precondition(events == ["authorize-install"])
 events = []; cancelled = false; fail = true
 do { try await actual.register(); preconditionFailure("install failure ignored") } catch is CocoaError { }
 precondition(events == ["authorize-install","install","free"])
 events = []
 do { try await actual.unregister(); preconditionFailure("remove failure ignored") } catch is CocoaError { }
 precondition(events == ["authorize-remove","remove","free"])
 print("PASS legacy native registration: ownership/package/conflict gates, async single-operation admission, off-main authorization, cancellation and authorization cleanup; all system functions injected")
}
