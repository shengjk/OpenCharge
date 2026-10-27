import Foundation
import CoreFoundation

/// The shape and default policy of the app's signed-update configuration.
/// This does not authenticate an archive; the updater must verify its EdDSA signature.
public struct SignedUpdateConfiguration: Equatable, Sendable {
 public static let feedURL = URL(string:"https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml")!
 public static let requiredBooleans: [String:Bool] = [
  "SUEnableAutomaticChecks":false, "SUAutomaticallyUpdate":false,
  "SUAllowsAutomaticUpdates":true, "SUEnableSystemProfiling":false,
  "SUVerifyUpdateBeforeExtraction":true, "SURequireSignedFeed":true,
  "SUEnableJavaScript":false, "SUEnableInstallerLauncherService":false,
  "SUEnableDownloaderService":false
 ]
 public let publicKey: Data
 public let feed: URL
 public enum Readiness: Equatable, Sendable {
  case unconfigured, invalid, ready(SignedUpdateConfiguration)
 }
 public static func evaluate(_ info: [String:Any]) -> Readiness {
  guard info["SUPublicEDKey"] != nil else { return .unconfigured }
  guard info["CFBundleIdentifier"] as? String == "org.opencharge.app",
        let encoded = info["SUPublicEDKey"] as? String, encoded.utf8.count == 44,
        let key = Data(base64Encoded:encoded), key.count == 32,
        key.base64EncodedString() == encoded,
        let feedString = info["SUFeedURL"] as? String,
        feedString == feedURL.absoluteString else { return .invalid }
  for (name,expected) in requiredBooleans {
   guard let value = info[name] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID(), value.boolValue == expected else { return .invalid }
  }
  guard let expiry = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
        CFGetTypeID(expiry) != CFBooleanGetTypeID(), expiry.doubleValue.isFinite,
        expiry.doubleValue == 0 else { return .invalid }
  return .ready(Self(publicKey:key,feed:feedURL))
 }
}
