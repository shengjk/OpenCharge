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
 var events: [String] = [], support = true, cancel = false, failFiles = false, failStop = false, absent = false, loseFileReply = false
 var job = HelperRegistrationStatus.enabled
 let reference = AuthorizationRef(bitPattern:2)!
 let ops = LegacyHelperOperations(status:{job},authorize:{_ in events.append("auth");if cancel {throw CocoaError(.userCancelled)};return reference},release:{_ in events.append("free")},install:{_ in preconditionFailure("uninstall must not install")},remove:{_ in
  events.append("stop");if failStop {throw CocoaError(.fileWriteUnknown)};job = .notRegistered
 },removalSupport:{events.append("capability");return support},deleteFiles:{_ in events.append("files");if failFiles {throw CocoaError(.fileWriteNoPermission)};absent = true;if loseFileReply {throw CocoaError(.fileWriteUnknown)}},filesAbsent:{absent})
 let directory = FileManager.default.temporaryDirectory.appendingPathComponent("opencharge-removal-"+UUID().uuidString)
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 defer {try? FileManager.default.removeItem(at:directory)}
 let journal = directory.appendingPathComponent("pending.json")
 let store = LegacyHelperRemovalStore.file(at:journal)
 var actual = LegacyHelperRegistration(operations:ops,store:store)
 precondition(!store.pending && !actual.removalPending && !FileManager.default.fileExists(atPath:journal.path))
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
 let recreated = LegacyHelperRegistration(operations:ops,store:store)
 precondition(recreated.removalPending,"partial native removal must remain retryable after application reconstruction")
 actual = recreated
 events = [];failStop = false
 try await actual.uninstall()
 precondition(events == ["auth","stop","free"] && !actual.removalPending && job == .notRegistered)
 // An ambiguous stop reply after a confirmed file-removal ack may complete through a read-only retry.
 absent = false;job = .enabled;events = [];failStop = true
 do {try await actual.uninstall();preconditionFailure("job error ignored")}catch is CocoaError{}
 precondition(actual.removalPending);job = .notRegistered;events = []
 try await actual.uninstall();precondition(events.isEmpty && !actual.removalPending)
 // A lost file-deletion acknowledgement leaves the durable attempted stage.
 // Reconstructing must use absence checks, authorize again and finish only the job.
 absent = false;job = .enabled;failStop = false;loseFileReply = true;events = []
 do {try await actual.uninstall();preconditionFailure("lost reply ignored")}catch is CocoaError{}
 let attempted = try store.load();precondition(attempted == .attempted)
 let permissions = try FileManager.default.attributesOfItem(atPath:journal.path)[.posixPermissions] as! NSNumber
 precondition(permissions.intValue == 0o600)
 let pendingBytes = try Data(contentsOf:journal)
 actual = LegacyHelperRegistration(operations:ops,store:store)
 let loadedBytes = try Data(contentsOf:journal);precondition(pendingBytes == loadedBytes,"construction must be read-only")
 events = [];loseFileReply = false
 try await actual.uninstall()
 precondition(events == ["auth","stop","free"] && !store.pending && !actual.removalPending)
 // Journal storage must succeed before destructive helper operations.
 events = [];absent = false;job = .enabled
 let unwritable = LegacyHelperRemovalStore(load:{.none},save:{_ in throw CocoaError(.fileWriteNoPermission)})
 let failedStorage = LegacyHelperRegistration(operations:ops,store:unwritable)
 do {try await failedStorage.uninstall();preconditionFailure("failed persistence allowed deletion")}catch is CocoaError{}
 precondition(events == ["capability","auth","free"] && !absent && failedStorage.removalPending)
 // Corrupt or symlink records block registration/removal and are never replaced.
 try Data("invalid".utf8).write(to:journal)
 events = [];actual = LegacyHelperRegistration(operations:ops,store:store)
 precondition(actual.removalPending && store.pending)
 do {try await actual.uninstall();preconditionFailure("corrupt state accepted")}catch{}
 do {try await actual.register();preconditionFailure("corrupt state allowed install")}catch{}
 let corruptBytes = try Data(contentsOf:journal);precondition(events.isEmpty && corruptBytes == Data("invalid".utf8))
 try FileManager.default.removeItem(at:journal)
 let target = directory.appendingPathComponent("external");try Data("untouched".utf8).write(to:target)
 try FileManager.default.createSymbolicLink(at:journal,withDestinationURL:target)
 precondition(store.pending)
 do {try store.save(.attempted);preconditionFailure("symlink overwritten")}catch{}
 let externalBytes = try Data(contentsOf:target);precondition(externalBytes == Data("untouched".utf8))
 try FileManager.default.removeItem(at:journal)
 // A failed final journal clear remains retryable even after files and job are gone.
 var clearFails = true
 let clearFailure = LegacyHelperRemovalStore(load:store.load,save:{phase in
  if phase == .none && clearFails {throw CocoaError(.fileWriteUnknown)}
  try store.save(phase)
 })
 events = [];absent = false;job = .enabled
 actual = LegacyHelperRegistration(operations:ops,store:clearFailure)
 do {try await actual.uninstall();preconditionFailure("clear failure ignored")}catch is CocoaError{}
 precondition(actual.removalPending && absent && job == .notRegistered)
 actual = LegacyHelperRegistration(operations:ops,store:clearFailure);events = [];clearFails = false
 try await actual.uninstall();precondition(events.isEmpty && !store.pending && !actual.removalPending)
 print("PASS durable native removal: atomic isolated record, reconstruction after acknowledged/lost deletion reply, fail-before-delete storage, read-only startup, corrupt/symlink rejection and retry after failed final clear; injected privileged operations only")
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
