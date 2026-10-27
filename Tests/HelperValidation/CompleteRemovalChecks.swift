import Foundation
import Security

@MainActor private final class RemovalFacadeBackend: HelperRegistrationBackend {
 var route: HelperRegistrationRoute = .blessedHelper
 var status: HelperRegistrationStatus = .enabled
 var removalPending = false
 var perform: () throws -> Void = { }
 func register() async throws { status = .enabled }
 func unregister() async throws { status = .notRegistered }
 func uninstall() async throws { try perform();status = .notRegistered;removalPending = false }
 func openApprovalSettings() { }
}
@MainActor func completeRemovalChecks(bundle:Bundle) async throws {
 var events: [String] = [], support = true, cancel = false, failFiles = false, failStop = false, absent = false
 var job = HelperRegistrationStatus.enabled
 let reference = AuthorizationRef(bitPattern:2)!
 let ops = LegacyHelperOperations(status:{job},authorize:{_ in events.append("auth");if cancel {throw CocoaError(.userCancelled)};return reference},release:{_ in events.append("free")},install:{_ in preconditionFailure("uninstall must not install")},remove:{_ in
  events.append("stop");if failStop {throw CocoaError(.fileWriteUnknown)};job = .notRegistered
 },removalSupport:{events.append("capability");return support},deleteFiles:{_ in events.append("files");if failFiles {throw CocoaError(.fileWriteNoPermission)};absent = true},filesAbsent:{absent})
 let actual = LegacyHelperRegistration(operations:ops)
 support = false
 do {try await actual.uninstall();preconditionFailure("unsupported helper reached authorization")}catch HelperServiceError.ineligible{}
 precondition(events == ["capability"] && !actual.removalPending)
 events = [];support = true;cancel = true
 do {try await actual.uninstall();preconditionFailure("cancel ignored")}catch is CocoaError{}
 precondition(events == ["capability","auth"] && !actual.removalPending)
 events = [];cancel = false;failFiles = true
 do {try await actual.uninstall();preconditionFailure("file error ignored")}catch is CocoaError{}
 precondition(events == ["capability","auth","files","free"] && actual.removalPending && job == .enabled)
 events = [];failFiles = false;failStop = true
 do {try await actual.uninstall();preconditionFailure("job error ignored")}catch is CocoaError{}
 precondition(events == ["capability","auth","files","stop","free"] && actual.removalPending && absent)
 events = [];failStop = false
 try await actual.uninstall()
 precondition(events == ["auth","stop","free"] && !actual.removalPending && job == .notRegistered)
 // An ambiguous stop reply after a confirmed file-removal ack may complete through a read-only retry.
 absent = false;job = .enabled;events = [];failStop = true
 do {try await actual.uninstall();preconditionFailure("job error ignored")}catch is CocoaError{}
 precondition(actual.removalPending);job = .notRegistered;events = []
 try await actual.uninstall();precondition(events.isEmpty && !actual.removalPending)
 let legacy = RemovalFacadeBackend(), modern = RemovalFacadeBackend();modern.route = .bundledDaemon;modern.status = .notRegistered
 var installation = HelperInstallation.olderNative(ownedByApp:true)
 let facade = HelperService(bundle:bundle,backend:legacy,installationCheck:{installation},signatureCheck:{_ in true},legacyPackageCheck:{_ in true},backendFactory:{ $0 == .none ? modern:legacy })
 precondition(facade.canUninstall && facade.canUnregister)
 legacy.perform = {installation = .none}
 try await facade.uninstall()
 precondition(!facade.busy && !facade.legacyInstalled && !facade.canUninstall && facade.registrationAllowed,"finished removal must switch to bundled registration on modern systems")
 // Failed partial deletion retains the original route; it cannot silently switch to a different backend.
 installation = .olderNative(ownedByApp:true);facade.refresh();legacy.status = .enabled
 legacy.perform = {installation = .unrecognized;legacy.removalPending = true;throw CocoaError(.fileWriteUnknown)}
 do {try await facade.uninstall();preconditionFailure("partial error discarded")}catch is CocoaError{}
 precondition(!facade.busy && facade.canUninstall && !facade.canUnregister && !facade.registrationAllowed)
 do {try await facade.register();preconditionFailure("partial removal allowed registration")}catch HelperServiceError.ineligible{}
 legacy.perform = {installation = .none}
 try await facade.uninstall();precondition(!facade.canUninstall && !facade.legacyInstalled)
 print("PASS complete native removal coordinator: protocol preflight before auth, cancellation, file-before-job ordering, retained failure stage, acknowledged retry and modern route handoff; all authorization/IPC/service operations injected")
}
