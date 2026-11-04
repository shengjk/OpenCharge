import Foundation
import Security
import ServiceManagement
import ApplePowerConstants
import ChargeCore
import Darwin

enum LegacyHelperOperation { case install, remove, uninstall }
enum LegacyHelperRemovalPhase: String, Codable { case none, attempted, acknowledged }
struct LegacyHelperRemovalStore {
 var load: () throws -> LegacyHelperRemovalPhase
 var save: (LegacyHelperRemovalPhase) throws -> Void
 var pending: Bool { do { return try load() != .none } catch { return true } }
 static func memory() -> Self {
  var phase = LegacyHelperRemovalPhase.none
  return Self(load:{phase},save:{phase = $0})
 }
 static var system: Self { file(at:Configuration.directory.appendingPathComponent("legacy-helper-removal.json")) }
 static func file(at url: URL) -> Self {
  struct Record: Codable { let schema: Int; let phase: LegacyHelperRemovalPhase }
  func read() throws -> LegacyHelperRemovalPhase {
   var info = stat()
   guard lstat(url.path,&info) == 0 else {
    if errno == ENOENT { return .none }
    throw CocoaError(.fileReadUnknown)
   }
   guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
   let record = try JSONDecoder().decode(Record.self,from:Data(contentsOf:url))
   guard record.schema == 1, record.phase != .none else { throw CocoaError(.fileReadCorruptFile) }
   return record.phase
  }
  return Self(load:read,save:{ phase in
   // Validate an existing record before replacing or removing it. A journal
   // is a retry hint, never authorization or proof of installed-file ownership.
   _ = try read()
   if phase == .none {
    if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
   } else {
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    try JSONEncoder().encode(Record(schema:1,phase:phase)).write(to:url,options:.atomic)
    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
   }
  })
 }
}
struct LegacyHelperOperations {
 var status: () -> HelperRegistrationStatus
 var authorize: (LegacyHelperOperation) throws -> AuthorizationRef
 var release: (AuthorizationRef) -> Void
 var install: (AuthorizationRef) throws -> Void
 var remove: (AuthorizationRef) throws -> Void
 var removalSupport: () throws -> Bool = { false }
 var deleteFiles: (AuthorizationRef) throws -> Void = { _ in throw HelperServiceError.ineligible(NSLocalizedString("当前服务不支持完整文件移除，请先更新服务或使用卸载说明",comment:"")) }
 var filesAbsent: () -> Bool = { false }
 static let system = LegacyHelperOperations(status: {
  switch opencharge_legacy_helper_status() { case 0: return .notRegistered; case 1: return .enabled; default: return .unknown }
 }, authorize: { operation in
  var reference: AuthorizationRef?
  let created = AuthorizationCreate(nil,nil,[],&reference)
  guard created == errAuthorizationSuccess, let reference else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(created)) }
  do {
   let right = operation == .install ? kSMRightBlessPrivilegedHelper : kSMRightModifySystemDaemons
   let result = right.withCString { name -> OSStatus in
    var item = AuthorizationItem(name:name,valueLength:0,value:nil,flags:0)
    return withUnsafeMutablePointer(to:&item) { pointer in
     var rights = AuthorizationRights(count:1,items:pointer)
     let flags: AuthorizationFlags = operation == .uninstall ? [.interactionAllowed,.extendRights] : [.interactionAllowed,.extendRights,.preAuthorize]
     return AuthorizationCopyRights(reference,&rights,nil,flags,nil)
    }
   }
   guard result == errAuthorizationSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(result)) }
   return reference
  } catch { AuthorizationFree(reference,[.destroyRights]); throw error }
 }, release: { AuthorizationFree($0,[.destroyRights]) }, install: { reference in
  var error: Unmanaged<CFError>?
  let success = opencharge_bless_legacy_helper(reference,&error) != 0
  let failure = error?.takeRetainedValue()
  guard success else { throw failure.map { $0 as Error } ?? NSError(domain:NSOSStatusErrorDomain,code:Int(errAuthorizationDenied)) }
 }, remove: { reference in
  var error: Unmanaged<CFError>?
  let success = opencharge_remove_legacy_helper_job(reference,&error) != 0
  let failure = error?.takeRetainedValue()
  guard success else { throw failure.map { $0 as Error } ?? NSError(domain:NSOSStatusErrorDomain,code:Int(errAuthorizationDenied)) }
 }, removalSupport: { ServiceFileRemovalRequest.supports(try HelperClient.request("capabilities")) }, deleteFiles: { reference in
  var form = AuthorizationExternalForm()
  guard AuthorizationMakeExternalForm(reference,&form) == errAuthorizationSuccess else { throw HelperServiceError.ineligible(NSLocalizedString("无法传递系统移除授权，请重试",comment:"")) }
  let data = withUnsafeBytes(of:&form) { Data($0) }
  guard let request = ServiceFileRemovalRequest(externalForm:data),try HelperClient.request(request.wireValue) == ServiceFileRemovalRequest.reply else { throw HelperServiceError.ineligible(NSLocalizedString("服务未确认文件移除完成，请重试",comment:"")) }
 }, filesAbsent: {
  for path in ["/Library/LaunchDaemons/org.opencharge.charged.plist","/Library/PrivilegedHelperTools/org.opencharge.charged"] {
   var info = stat()
   if lstat(path,&info) == 0 || errno != ENOENT { return false }
  }
  return true
 })
}

/// Only explicit registration/removal calls authorize. Snapshot construction is read-only.
@MainActor final class LegacyHelperRegistration: HelperRegistrationBackend {
 let route = HelperRegistrationRoute.blessedHelper
 private let operations: LegacyHelperOperations
 private let store: LegacyHelperRemovalStore
 private typealias RemovalPhase = LegacyHelperRemovalPhase
 private var removalPhase: RemovalPhase
 var removalPending: Bool { removalPhase != .none }
 convenience init() { self.init(operations:.system,store:.system) }
 init(operations: LegacyHelperOperations, store: LegacyHelperRemovalStore = .memory()) {
  self.operations = operations; self.store = store
  removalPhase = (try? store.load()) ?? .attempted
 }
 var status: HelperRegistrationStatus { operations.status() }
 func register() async throws { try await perform(.install) }
 func unregister() async throws { try await perform(.remove) }
 func uninstall() async throws {
  removalPhase = try store.load()
  if removalPhase != .none,operations.filesAbsent(),status == .notRegistered || status == .notFound {
   try store.save(.none); removalPhase = .none; return
  }
  try await perform(.uninstall)
 }
 func openApprovalSettings() { }
 private struct Failure: Error { let error: Error; let phase: RemovalPhase }
 private func perform(_ operation: LegacyHelperOperation) async throws {
  let operations = operations, store = store
  let initialPhase = try store.load()
  guard operation == .uninstall || initialPhase == .none else { throw HelperServiceError.ineligible(NSLocalizedString("请先重试完整文件移除",comment:"")) }
  do {
   try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    DispatchQueue.global(qos:.userInitiated).async {
     var phase = initialPhase
     do {
      let needsFiles = operation == .uninstall && !(phase != .none && operations.filesAbsent())
      if needsFiles, try !operations.removalSupport() { throw HelperServiceError.ineligible(NSLocalizedString("当前服务不支持完整文件移除，请先更新服务或使用卸载说明",comment:"")) }
      let reference = try operations.authorize(operation)
      defer { operations.release(reference) }
      if operation == .install { try operations.install(reference) }
      else {
       if needsFiles {
        phase = .attempted; try store.save(phase)
        try operations.deleteFiles(reference)
        phase = .acknowledged; try store.save(phase)
       }
       try operations.remove(reference)
       if operation == .uninstall { try store.save(.none); phase = .none }
      }
      continuation.resume()
     } catch { continuation.resume(throwing:Failure(error:error,phase:phase)) }
    }
   }
   if operation == .uninstall { removalPhase = .none }
  } catch let failure as Failure {
   if operation == .uninstall { removalPhase = failure.phase }
   throw failure.error
  }
 }

}

enum LegacyHelperPackage {
 static func valid(_ bundle: Bundle) -> Bool {
  guard bundle.bundleIdentifier == "org.opencharge.app",
        let version = bundle.infoDictionary?["CFBundleVersion"] as? String,
        version.range(of:"^[0-9]+(?:\\.[0-9]+){0,2}$",options:.regularExpression) != nil,
        let app = identity(bundle.bundleURL), let team = app.team,
        team.range(of:"^[A-Z0-9]{10}$",options:.regularExpression) != nil else { return false }
  let common = " and anchor apple generic and certificate leaf[subject.OU] = \""+team+"\""
  let helperRequirement = "identifier \"org.opencharge.charged\""+common
  let clientRequirement = "identifier \"org.opencharge.app\""+common
  let url = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/org.opencharge.charged")
  guard !((try? url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) ?? true),
        FileManager.default.isExecutableFile(atPath:url.path),
        bundle.infoDictionary?["SMPrivilegedExecutables"] as? [String:String] == ["org.opencharge.charged":helperRequirement],
        HelperInstallationInspector.matchesRequirement(bundle.bundleURL,clientRequirement),
        HelperInstallationInspector.matchesRequirement(url,helperRequirement),
        let helper = identity(url), helper.identifier == "org.opencharge.charged", helper.team == team,
        helper.info["CFBundleIdentifier"] as? String == "org.opencharge.charged",
        helper.info["CFBundleVersion"] as? String == version,
        helper.info["OpenChargeInstallRoute"] as? String == "blessedV1",
        helper.info["SMAuthorizedClients"] as? [String] == [clientRequirement] else { return false }
  return true
 }
 private static func identity(_ url: URL) -> HelperSliceIdentity? {
  var code: SecStaticCode?, info: CFDictionary?
  guard SecStaticCodeCreateWithPath(url as CFURL,[],&code) == errSecSuccess, let code,
        SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info) == errSecSuccess,
        let values = info as? [String:Any], let id = values[kSecCodeInfoIdentifier as String] as? String else { return nil }
  return HelperSliceIdentity(identifier:id,team:values[kSecCodeInfoTeamIdentifier as String] as? String,info:values[kSecCodeInfoPList as String] as? [String:Any] ?? [:])
 }
}
