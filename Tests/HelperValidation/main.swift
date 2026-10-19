import Foundation
@main struct HelperValidation {
 @MainActor static func main() throws {
  let app = URL(fileURLWithPath: CommandLine.arguments[1])
  guard let bundle = Bundle(url: app) else { fatalError("missing app bundle") }
  let service = HelperService(bundle: bundle)
  precondition(!service.registrationAllowed)
  precondition(service.preflightText.contains(service.legacyInstalled ? "开发脚本" : "本地签名"))
  do { try service.register(); preconditionFailure("local build registered") }
  catch HelperServiceError.ineligible { }
  print("PASS \(service.legacyInstalled ? "legacy installation" : "ad-hoc signature") preflight refuses registration before OS mutation")
 }
}
