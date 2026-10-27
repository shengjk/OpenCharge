import Foundation
import Security
import ServiceManagement
import ApplePowerConstants
import ChargeCore
import Darwin

enum LegacyHelperOperation { case install, remove, uninstall }
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
 private enum RemovalPhase { case none, attempted, acknowledged }
 private var removalPhase = RemovalPhase.none
 var removalPending: Bool { removalPhase != .none }
 init(operations: LegacyHelperOperations = .system) { self.operations = operations }
 var status: HelperRegistrationStatus { operations.status() }
 func register() async throws { try await perform(.install) }
 func unregister() async throws { try await perform(.remove) }
 func uninstall() async throws {
  if removalPhase == .acknowledged,operations.filesAbsent(),status == .notRegistered || status == .notFound { removalPhase = .none; return }
  try await perform(.uninstall)
 }
 func openApprovalSettings() { }
 private struct Failure: Error { let error: Error; let phase: RemovalPhase }
 private func perform(_ operation: LegacyHelperOperation) async throws {
  let operations = operations, initialPhase = removalPhase
  do {
   try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    DispatchQueue.global(qos:.userInitiated).async {
     var phase = initialPhase
     do {
      let needsFiles = operation == .uninstall && !(phase == .acknowledged && operations.filesAbsent())
      if needsFiles, try !operations.removalSupport() { throw HelperServiceError.ineligible(NSLocalizedString("当前服务不支持完整文件移除，请先更新服务或使用卸载说明",comment:"")) }
      let reference = try operations.authorize(operation)
      defer { operations.release(reference) }
      if operation == .install { try operations.install(reference) }
      else {
       if needsFiles { phase = .attempted; try operations.deleteFiles(reference); phase = .acknowledged }
       try operations.remove(reference)
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
