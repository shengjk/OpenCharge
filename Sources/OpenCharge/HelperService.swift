import Foundation
import Combine
import ServiceManagement
import Security

/// Read-only status/preflight until an explicit button calls register or unregister.
@MainActor final class HelperService: ObservableObject {
 static let plistName = "org.opencharge.charged.plist"
 private let bundle: Bundle
 private let service = SMAppService.daemon(plistName: plistName)
 @Published private(set) var statusText = NSLocalizedString("尚未检查", comment: "")
 @Published private(set) var registrationAllowed = false
 @Published private(set) var preflightText = ""
 @Published private(set) var busy = false
 var status: SMAppService.Status { service.status }
 var legacyInstalled: Bool { FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/" + Self.plistName) }
 init(bundle: Bundle = .main) { self.bundle = bundle; refresh() }
 func refresh() {
  switch service.status {
  case .enabled: statusText = NSLocalizedString("已注册，可运行（服务连接需另外检查）", comment: "")
  case .requiresApproval: statusText = NSLocalizedString("已注册，等待管理员在系统设置批准", comment: "")
  case .notRegistered: statusText = NSLocalizedString("尚未注册", comment: "")
  case .notFound: statusText = NSLocalizedString("系统未找到服务", comment: "")
  @unknown default: statusText = NSLocalizedString("未知注册状态", comment: "")
  }
  registrationAllowed = false
  if legacyInstalled { statusText = NSLocalizedString("开发脚本服务已安装（不属于应用内注册）", comment: ""); preflightText = NSLocalizedString("检测到开发脚本安装的服务，请先按安装文档移除，再使用应用内注册。", comment: ""); return }
  let root = bundle.bundleURL
  let plist = root.appendingPathComponent("Contents/Library/LaunchDaemons/" + Self.plistName)
  let executable = root.appendingPathComponent("Contents/MacOS/charged")
  guard FileManager.default.fileExists(atPath: plist.path), FileManager.default.isExecutableFile(atPath: executable.path) else { preflightText = NSLocalizedString("此应用未包含完整硬件服务，请使用打包后的 OpenCharge.app。", comment: ""); return }
  var code: SecStaticCode?
  var requirement: SecRequirement?
  let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
  guard SecStaticCodeCreateWithPath(root as CFURL, [], &code) == errSecSuccess,
        SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
        let code, let requirement,
        SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
  else { preflightText = NSLocalizedString("当前为本地签名构建，不能应用内注册。可按开发安装文档安装；正式版本需开发者签名、公证和管理员批准。", comment: ""); return }
  registrationAllowed = true
  preflightText = NSLocalizedString("系统注册仍会检查公证并要求管理员批准。建议先将应用放入“应用程序”，以便登录前可用。", comment: "")
 }
 func register() throws {
  refresh()
  guard registrationAllowed else { throw HelperServiceError.ineligible(preflightText) }
  guard service.status == .notRegistered || service.status == .notFound else { return }
  try service.register(); refresh()
 }
 func unregister() async throws {
  guard !legacyInstalled else { throw HelperServiceError.ineligible(NSLocalizedString("开发脚本安装的服务需使用对应卸载脚本移除", comment: "")) }
  busy = true; defer { busy = false; refresh() }
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
   service.unregister { error in
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
   }
  }
 }
 func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}
enum HelperServiceError: LocalizedError {
 case ineligible(String)
 var errorDescription: String? { if case .ineligible(let message) = self { return message }; return nil }
}
