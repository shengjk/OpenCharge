import Foundation

public struct ReleaseVersion: Comparable, Sendable {
 public let text: String
 public let prerelease: [String]
 private let numbers: [Int]
 public init?(_ raw: String) {
  let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
  guard !value.isEmpty, value.utf8.count <= 128, value.utf8.allSatisfy({ $0 < 128 }) else { return nil }
  let metadata = value.split(separator: "+", omittingEmptySubsequences: false)
  guard metadata.count <= 2 else { return nil }
  func validIdentifiers(_ part: Substring, numericZeros: Bool) -> Bool {
   part.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { token in
    !token.isEmpty && token.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } &&
    (numericZeros || !token.utf8.allSatisfy { (48...57).contains($0) } || token.count == 1 || token.first != "0")
   }
  }
  if metadata.count == 2 && !validIdentifiers(metadata[1], numericZeros: true) { return nil }
  let parts = metadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
  let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
  guard core.count == 3 else { return nil }
  var parsed: [Int] = []
  for item in core {
   guard !item.isEmpty, item.utf8.allSatisfy({ (48...57).contains($0) }), item.count == 1 || item.first != "0", let n = Int(item) else { return nil }
   parsed.append(n)
  }
  if parts.count == 2 && !validIdentifiers(parts[1], numericZeros: false) { return nil }
  numbers = parsed; prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []; text = value
 }
 public static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers && lhs.prerelease == rhs.prerelease }
 public static func < (lhs: Self, rhs: Self) -> Bool {
  if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
  if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
  for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
   let an = a.utf8.allSatisfy { (48...57).contains($0) }, bn = b.utf8.allSatisfy { (48...57).contains($0) }
   if an != bn { return an }
   if an && a.count != b.count { return a.count < b.count }
   return a < b
  }
  return lhs.prerelease.count < rhs.prerelease.count
 }
}
public enum UpdateArchitecture: Sendable { case appleSilicon, intel }
public struct ReleasePackage: Equatable, Sendable {
 public let version: String
 public let releaseURL: URL
 public let archiveURL: URL
 public let checksumURL: URL
 public let filename: String
 public let size: Int
 public let apiDigest: String?
}
public enum ReleaseSelection: Equatable, Sendable {
 case available(ReleasePackage), current(String), ahead(String), noReleases, missingPackage(String, URL)
}
public enum ReleaseUpdateError: Error, LocalizedError {
 case invalidVersion, invalidFeed, invalidURL, missingChecksum, invalidChecksum, transferTooLarge, http(Int), digestMismatch, sizeMismatch, releaseLimit
 public var errorDescription: String? {
  switch self {
  case .invalidVersion: return "无法识别当前应用版本"
  case .invalidFeed: return "发布信息格式不受支持"
  case .invalidURL: return "发布下载地址不属于受支持的官方地址"
  case .missingChecksum: return "发布版本未提供适用的校验文件"
  case .invalidChecksum: return "校验文件格式无效或存在重复条目"
  case .transferTooLarge: return "下载内容超过允许大小"
  case .http(let status): return status == 403 || status == 429 ? "GitHub 请求受限，请稍后重试" : "GitHub 返回 HTTP \(status)"
  case .digestMismatch: return "下载内容与发布校验和不一致，文件未保留"
  case .sizeMismatch: return "下载大小与发布记录不一致"
  case .releaseLimit: return "发布列表超过检查范围，请在 GitHub 查看"
  }
 }
}
public enum ReleaseCatalog {
 public static let repositoryURL = URL(string: "https://github.com/shengjk/OpenCharge/releases")!
 public static let maximumArchiveBytes = 64 * 1024 * 1024
 private struct Asset: Decodable { let name: String; let size: Int; let browser_download_url: String; let state: String; let digest: String? }
 private struct Release: Decodable { let tag_name: String; let html_url: String; let draft: Bool; let prerelease: Bool; let assets: [Asset] }
 private static func decode(_ data: Data) throws -> [Release] {
  guard data.count <= 2 * 1024 * 1024 else { throw ReleaseUpdateError.transferTooLarge }
  let releases = try JSONDecoder().decode([Release].self, from: data)
  guard releases.count <= 100 else { throw ReleaseUpdateError.invalidFeed }; return releases
 }
 public static func pageCount(_ data: Data) throws -> Int { try decode(data).count }
 private static func url(_ raw: String, path: String) throws -> URL {
  guard let value = URL(string: raw), value.scheme == "https", value.host == "github.com", value.user == nil, value.password == nil,
        value.port == nil, value.query == nil, value.fragment == nil, value.path == path else { throw ReleaseUpdateError.invalidURL }
  return value
 }
 public static func evaluate(pages: [Data], currentVersion: String, includePreviews: Bool, architecture: UpdateArchitecture) throws -> ReleaseSelection {
  guard let current = ReleaseVersion(currentVersion) else { throw ReleaseUpdateError.invalidVersion }
  guard pages.count <= 5 else { throw ReleaseUpdateError.releaseLimit }
  var best: (ReleaseVersion, Release)?
  for data in pages { for release in try decode(data) {
   guard !release.draft, let version = ReleaseVersion(release.tag_name), includePreviews || (!release.prerelease && version.prerelease.isEmpty) else { continue }
   if best == nil || best!.0 < version { best = (version, release) }
  } }
  guard let (version, release) = best else { return .noReleases }
  if version == current { return .current(version.text) }
  if version < current { return .ahead(version.text) }
  let page = try url(release.html_url, path: "/shengjk/OpenCharge/releases/tag/" + release.tag_name)
  guard release.assets.count <= 32 else { throw ReleaseUpdateError.invalidFeed }
  let names = architecture == .appleSilicon ? ["OpenCharge-macOS-arm64.zip", "OpenCharge-macOS-universal.zip"] : ["OpenCharge-macOS-universal.zip"]
  func asset(_ name: String) throws -> Asset? {
   let matches = release.assets.filter { $0.name == name }; guard matches.count <= 1 else { throw ReleaseUpdateError.invalidFeed }
   return matches.first.flatMap { $0.state == "uploaded" ? $0 : nil }
  }
  var archive: Asset?
  for name in names { if let found = try asset(name) { archive = found; break } }
  guard let archive else { return .missingPackage(version.text, page) }
  guard archive.size > 0, archive.size <= maximumArchiveBytes else { throw ReleaseUpdateError.transferTooLarge }
  guard let checksum = try asset("SHA256SUMS.txt"), checksum.size > 0, checksum.size <= 65_536 else { throw ReleaseUpdateError.missingChecksum }
  let prefix = "/shengjk/OpenCharge/releases/download/" + release.tag_name + "/"
  var digest: String?
  if let provided = archive.digest {
   guard provided.hasPrefix("sha256:"), validHash(String(provided.dropFirst(7))) else { throw ReleaseUpdateError.invalidChecksum }
   digest = String(provided.dropFirst(7)).lowercased()
  }
  return .available(ReleasePackage(version: version.text, releaseURL: page,
   archiveURL: try url(archive.browser_download_url, path: prefix + archive.name), checksumURL: try url(checksum.browser_download_url, path: prefix + checksum.name),
   filename: archive.name, size: archive.size, apiDigest: digest))
 }
 public static func validHash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) } }
 public static func expectedChecksum(_ data: Data, filename: String) throws -> String {
  guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else { throw ReleaseUpdateError.invalidChecksum }
  var selected: String?; var names = Set<String>()
  for line in text.split(whereSeparator: \.isNewline) {
   let fields = line.split(whereSeparator: \.isWhitespace)
   guard fields.count == 2, validHash(String(fields[0])) else { throw ReleaseUpdateError.invalidChecksum }
   let name = fields[1].hasPrefix("*") ? String(fields[1].dropFirst()) : String(fields[1])
   guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw ReleaseUpdateError.invalidChecksum }
   guard names.insert(name).inserted else { throw ReleaseUpdateError.invalidChecksum }
   if name == filename { guard selected == nil else { throw ReleaseUpdateError.invalidChecksum }; selected = fields[0].lowercased() }
  }
  guard let selected else { throw ReleaseUpdateError.missingChecksum }; return selected
 }
}

public enum ReleaseCheckCadence {
 public static func due(now: TimeInterval, lastAttempt: TimeInterval?, interval: TimeInterval) -> Bool {
  guard now.isFinite, interval.isFinite, interval > 0 else { return false }
  guard let lastAttempt, lastAttempt.isFinite, now >= lastAttempt else { return true }
  return now - lastAttempt >= interval
 }
}
