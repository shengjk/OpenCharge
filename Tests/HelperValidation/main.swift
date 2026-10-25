import Foundation

@MainActor private final class FakeRegistration: HelperRegistrationBackend {
 var status: HelperRegistrationStatus = .notRegistered
 var events: [String] = []
 var fail = false
 var onUnregister: (() -> Void)?
 func register() throws { events.append("register"); if fail { throw CocoaError(.fileWriteUnknown) }; status = .enabled }
 func unregister() async throws { events.append("unregister"); onUnregister?(); if fail { throw CocoaError(.fileWriteUnknown) }; status = .notRegistered }
 func openApprovalSettings() { events.append("settings") }
}
@main struct HelperValidation {
 @MainActor static func main() async throws {
  let app = URL(fileURLWithPath:CommandLine.arguments[1])
  guard let bundle = Bundle(url:app) else { fatalError("missing app bundle") }
  let production = HelperService(bundle:bundle)
  precondition(!production.registrationAllowed)
  precondition(production.preflightText.contains(production.legacyInstalled ? "开发脚本" : "本地签名"))
  do { try production.register(); preconditionFailure("local build registered") }
  catch HelperServiceError.ineligible { }
  func signatureMustNotRun(_: URL) -> Bool { preconditionFailure("Unavailable/legacy route reached signature checking") }
  let unsupported = HelperService(bundle:bundle,backend:nil,legacyCheck:{ false },signatureCheck:signatureMustNotRun)
  precondition(unsupported.status == .unavailable && !unsupported.registrationAllowed && !unsupported.busy)
  do { try unsupported.register(); preconditionFailure("Unavailable route registered") } catch HelperServiceError.ineligible { }
  do { try await unsupported.unregister(); preconditionFailure("Unavailable route unregistered") } catch HelperServiceError.ineligible { }
  unsupported.openApprovalSettings()
  let legacyBackend = FakeRegistration()
  let legacy = HelperService(bundle:bundle,backend:legacyBackend,legacyCheck:{ true },signatureCheck:signatureMustNotRun)
  precondition(legacy.legacyInstalled && !legacy.registrationAllowed)
  do { try legacy.register(); preconditionFailure("Legacy route registered") } catch HelperServiceError.ineligible { }
  do { try await legacy.unregister(); preconditionFailure("Legacy route unregistered") } catch HelperServiceError.ineligible { }
  precondition(legacyBackend.events.isEmpty)
  for status in [HelperRegistrationStatus.unknown, .unavailable] {
   let backend = FakeRegistration(); backend.status = status
   let service = HelperService(bundle:bundle,backend:backend,legacyCheck:{ false },signatureCheck:signatureMustNotRun)
   precondition(!service.registrationAllowed)
   do { try service.register(); preconditionFailure("Unknown backend registered") } catch HelperServiceError.ineligible { }
   do { try await service.unregister(); preconditionFailure("Unknown backend unregistered") } catch HelperServiceError.ineligible { }
   precondition(backend.events.isEmpty)
  }
  let incompleteBackend = FakeRegistration()
  let incomplete = HelperService(bundle:.main,backend:incompleteBackend,legacyCheck:{ false },signatureCheck:signatureMustNotRun)
  precondition(!incomplete.registrationAllowed)
  do { try incomplete.register(); preconditionFailure("Incomplete bundle registered") } catch HelperServiceError.ineligible { }
  precondition(incompleteBackend.events.isEmpty)
  let unsignedBackend = FakeRegistration()
  let unsigned = HelperService(bundle:bundle,backend:unsignedBackend,legacyCheck:{ false },signatureCheck:{ _ in false })
  precondition(!unsigned.registrationAllowed)
  do { try unsigned.register(); preconditionFailure("Unsigned fixture registered") } catch HelperServiceError.ineligible { }
  precondition(unsignedBackend.events.isEmpty)
  let backend = FakeRegistration()
  let valid = HelperService(bundle:bundle,backend:backend,legacyCheck:{ false },signatureCheck:{ $0 == app })
  precondition(valid.registrationAllowed && valid.status == .notRegistered)
  try valid.register(); precondition(backend.events == ["register"] && valid.status == .enabled)
  try valid.register(); precondition(backend.events == ["register"],"Enabled registration was repeated")
  backend.onUnregister = { [weak valid] in precondition(valid?.busy == true) }
  try await valid.unregister()
  precondition(!valid.busy && valid.status == .notRegistered && backend.events == ["register","unregister"])
  backend.fail = true
  do { try valid.register(); preconditionFailure("Register error discarded") } catch is CocoaError { }
  backend.status = .enabled
  do { try await valid.unregister(); preconditionFailure("Unregister error discarded") } catch is CocoaError { }
  precondition(!valid.busy && valid.status == .enabled)
  valid.openApprovalSettings(); precondition(backend.events.last == "settings")
  print("PASS actual ad-hoc/legacy preflight plus unavailable/legacy/signature/fake native registration, busy state and failure propagation; no OS registration changes")
 }
}
