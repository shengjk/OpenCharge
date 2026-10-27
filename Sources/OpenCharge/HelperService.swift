import Foundation
import Combine
import ServiceManagement
import Security

enum HelperRegistrationStatus: Equatable {
 case enabled, requiresApproval, notRegistered, notFound, unavailable, unknown
}
enum HelperRegistrationRoute { case bundledDaemon, blessedHelper }
@MainActor protocol HelperRegistrationBackend: AnyObject {
 var route: HelperRegistrationRoute { get }
 var status: HelperRegistrationStatus { get }
 func register() async throws
 func unregister() async throws
 func openApprovalSettings()
}
extension HelperRegistrationBackend { var route: HelperRegistrationRoute { .bundledDaemon } }
@available(macOS 13.0, *)
@MainActor private final class NativeHelperRegistration: HelperRegistrationBackend {
 private let service = SMAppService.daemon(plistName: HelperService.plistName)
 var status: HelperRegistrationStatus {
  switch service.status {
  case .enabled: return .enabled
  case .requiresApproval: return .requiresApproval
  case .notRegistered: return .notRegistered
  case .notFound: return .notFound
  @unknown default: return .unknown
  }
 }
 func register() async throws { try service.register() }
 func unregister() async throws {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
   service.unregister { error in
    if let error { continuation.resume(throwing:error) } else { continuation.resume() }
   }
  }
 }
 func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Read-only status/preflight until an explicit button calls register or unregister.
@MainActor final class HelperService: ObservableObject {
 static let plistName = "org.opencharge.charged.plist"
 private let bundle: Bundle
 private let backend: HelperRegistrationBackend?
 private let installationCheck: () -> HelperInstallation
 @Published private(set) var installation: HelperInstallation = .none
 private let legacyPackageCheck: (Bundle) -> Bool
 private let signatureCheck: (URL) -> Bool
 @Published private(set) var statusText = NSLocalizedString("尚未检查", comment: "")
 @Published private(set) var registrationAllowed = false
 @Published private(set) var preflightText = ""
 @Published private(set) var busy = false
 var status: HelperRegistrationStatus { backend?.status ?? .unavailable }
 var legacyInstalled: Bool { installation.present }
 convenience init(bundle: Bundle = .main) {
  let backend: HelperRegistrationBackend?
  if #available(macOS 13.0, *) { backend = NativeHelperRegistration() } else { backend = LegacyHelperRegistration() }
  let inspector = HelperInstallationInspector(app: bundle)
  self.init(bundle:bundle,backend:backend,installationCheck:{ inspector.inspect() },signatureCheck:Self.validSignature)
 }
 convenience init(bundle: Bundle, backend: HelperRegistrationBackend?, legacyCheck: @escaping () -> Bool, signatureCheck: @escaping (URL) -> Bool) {
  self.init(bundle: bundle, backend: backend, installationCheck: { legacyCheck() ? .developmentLayout : .none }, signatureCheck: signatureCheck)
 }
 init(bundle: Bundle, backend: HelperRegistrationBackend?, installationCheck: @escaping () -> HelperInstallation, signatureCheck: @escaping (URL) -> Bool, legacyPackageCheck: @escaping (Bundle) -> Bool = LegacyHelperPackage.valid) {
  self.legacyPackageCheck = legacyPackageCheck
  self.bundle = bundle; self.backend = backend; self.installationCheck = installationCheck; self.signatureCheck = signatureCheck; refresh()
 }
 private var unsupportedText: String { NSLocalizedString("此系统尚不支持应用内服务注册；可按安装说明使用开发服务。", comment: "") }
 func refresh() {
  installation = installationCheck()
  switch status {
  case .enabled: statusText = NSLocalizedString("已注册，可运行（服务连接需另外检查）", comment: "")
  case .requiresApproval: statusText = NSLocalizedString("已注册，等待管理员在系统设置批准", comment: "")
  case .notRegistered: statusText = NSLocalizedString("尚未注册", comment: "")
  case .notFound: statusText = NSLocalizedString("系统未找到服务", comment: "")
  case .unavailable: statusText = NSLocalizedString("不可用", comment: "")
  case .unknown: statusText = NSLocalizedString("未知注册状态", comment: "")
  }
  registrationAllowed = false
  switch installation {
  case .developmentLayout:
   statusText = NSLocalizedString("检测到开发服务布局（不属于应用内注册）", comment: "")
   preflightText = backend == nil ? unsupportedText : NSLocalizedString("检测到开发脚本安装的服务，请先按安装文档移除，再使用应用内注册。", comment: ""); return
  case .olderNative(let owned) where !(owned && backend?.route == .blessedHelper):
   statusText = NSLocalizedString("检测到旧原生服务文件（注册状态需另外检查）", comment: "")
   preflightText = owned ? NSLocalizedString("已验证与当前应用的签名归属；旧安装的迁移与移除流程尚未接入。", comment: "") : NSLocalizedString("无法验证当前应用拥有此旧服务；不会覆盖或移除这些文件。", comment: ""); return
  case .unrecognized:
   statusText = NSLocalizedString("发现无法确认归属的硬件服务文件", comment: "")
   preflightText = NSLocalizedString("服务文件的权限、布局或签名不匹配；请按原安装方式确认后再操作。", comment: ""); return
  case .none, .olderNative: break
  }
  guard backend != nil else { preflightText = unsupportedText; return }
  guard status != .unavailable && status != .unknown else { preflightText = unsupportedText; return }
  let root = bundle.bundleURL
  let plist = root.appendingPathComponent("Contents/Library/LaunchDaemons/"+Self.plistName)
  let executable = root.appendingPathComponent("Contents/MacOS/charged")
  let legacyExecutable = root.appendingPathComponent("Contents/Library/LaunchServices/org.opencharge.charged")
  let complete = backend?.route == .blessedHelper ? FileManager.default.isExecutableFile(atPath:legacyExecutable.path) : (FileManager.default.fileExists(atPath:plist.path) && FileManager.default.isExecutableFile(atPath:executable.path))
  guard complete else { preflightText = NSLocalizedString("此应用未包含完整硬件服务，请使用打包后的 OpenCharge.app。", comment: ""); return }
  guard signatureCheck(root) else { preflightText = NSLocalizedString("当前为本地签名构建，不能应用内注册。可按开发安装文档安装；正式版本需开发者签名、公证和管理员批准。", comment: ""); return }
  if backend?.route == .blessedHelper {
   guard legacyPackageCheck(bundle) else { preflightText = NSLocalizedString("旧版系统安装需要当前应用与内嵌服务的匹配开发者签名。",comment:""); return }
   registrationAllowed = true
   preflightText = status == .enabled ? NSLocalizedString("旧原生服务已注册；注销会停止服务，已安装文件需按卸载说明另行移除。",comment:"") : NSLocalizedString("点击注册后由系统请求管理员授权；安装不会开启充电控制。",comment:"")
   return
  }
  registrationAllowed = true
  preflightText = NSLocalizedString("系统注册仍会检查公证并要求管理员批准。建议先将应用放入“应用程序”，以便登录前可用。", comment: "")
 }
 private static func validSignature(_ root: URL) -> Bool {
  var code: SecStaticCode?, requirement: SecRequirement?
  let flags = SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
  guard SecStaticCodeCreateWithPath(root as CFURL, [], &code) == errSecSuccess,
        SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
        let code, let requirement else { return false }
  return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
 }
 func register() async throws {
  guard !busy else { throw HelperServiceError.ineligible(NSLocalizedString("服务操作正在进行，请稍候",comment:"")) }
  refresh()
  guard registrationAllowed, let backend else { throw HelperServiceError.ineligible(preflightText) }
  guard status == .notRegistered || status == .notFound else { return }
  busy = true; defer { busy = false; refresh() }
  try await backend.register()
 }
 func validateRemoval() throws {
  guard !busy else { throw HelperServiceError.ineligible(NSLocalizedString("服务操作正在进行，请稍候",comment:"")) }
  refresh()
  switch installation {
  case .developmentLayout: throw HelperServiceError.ineligible(NSLocalizedString("开发脚本安装的服务需使用对应卸载脚本移除", comment: ""))
  case .olderNative(let owned) where owned && backend?.route == .blessedHelper: break
  case .olderNative, .unrecognized: throw HelperServiceError.ineligible(preflightText)
  case .none:
   guard backend?.route != .blessedHelper else { throw HelperServiceError.ineligible(NSLocalizedString("无法验证当前应用拥有此旧服务；不会覆盖或移除这些文件。",comment:"")) }
  }
  guard backend != nil, status != .unavailable, status != .unknown else { throw HelperServiceError.ineligible(unsupportedText) }
 }
 func unregister() async throws {
  try validateRemoval()
  guard let backend else { throw HelperServiceError.ineligible(unsupportedText) }
  busy = true; defer { busy = false; refresh() }
  try await backend.unregister()
 }
 var canUnregister: Bool {
  guard status == .enabled || status == .requiresApproval else { return false }
  if installation == .none { return backend?.route != .blessedHelper }
  return installation == .olderNative(ownedByApp:true) && backend?.route == .blessedHelper
 }
 func openApprovalSettings() { backend?.openApprovalSettings() }
}
enum HelperServiceError: LocalizedError {
 case ineligible(String)
 var errorDescription: String? { if case .ineligible(let message) = self { return message }; return nil }
}
