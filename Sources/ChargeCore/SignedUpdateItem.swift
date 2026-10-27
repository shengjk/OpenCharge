import Foundation

/// Additional repository/archive policy. Sparkle must still authenticate the feed and archive.
public enum SignedUpdateItemPolicy {
 public static func validate(version: String, currentVersion: String, build: String, url: URL?, size: UInt64, installationType: String,
                             delta: Bool, channel: String?, includePreviews: Bool, architecture: UpdateArchitecture) throws {
  guard let semantic = ReleaseVersion(version), semantic.text == version,
        let current = ReleaseVersion(currentVersion), current < semantic,
        !build.isEmpty, build.count <= 18, build.first != "0", build.utf8.allSatisfy({ (48...57).contains($0) }),
        installationType == "application", !delta,
        channel == nil || channel == "preview", includePreviews || (channel == nil && semantic.prerelease.isEmpty) else { throw ReleaseUpdateError.invalidFeed }
  guard size > 0, size <= UInt64(ReleaseCatalog.maximumArchiveBytes) else { throw ReleaseUpdateError.transferTooLarge }
  let names = architecture == .appleSilicon ? ["OpenCharge-macOS-arm64.zip", "OpenCharge-macOS-universal.zip"] : ["OpenCharge-macOS-universal.zip"]
  guard let url, let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
        parts.scheme == "https", parts.host == "github.com", parts.user == nil, parts.password == nil,
        parts.port == nil, parts.query == nil, parts.fragment == nil,
        names.contains(where: { parts.percentEncodedPath == "/shengjk/OpenCharge/releases/download/v" + version + "/" + $0 }) else { throw ReleaseUpdateError.invalidURL }
 }
}
