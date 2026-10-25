import Foundation
import CryptoKit
import CoreServices
import ChargeCore
import Darwin

enum ReleaseRedirects {
 static func allowed(_ url: URL) -> Bool {
  let hosts = ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"]
  return url.scheme == "https" && hosts.contains(url.host ?? "") && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
 }
}
enum ReleaseHTTP {
 /// No cookies, credentials, telemetry, arbitrary endpoints or launch commands.
 static func transfer(_ url: URL, limit: Int, destination: URL? = nil, progress: (@Sendable (Double) -> Void)? = nil,
                      configuration: URLSessionConfiguration? = nil) async throws -> Data {
  guard ReleaseRedirects.allowed(url), limit > 0 else { throw ReleaseUpdateError.invalidURL }
  try Task.checkCancellation()
  var request = URLRequest(url: url); request.setValue("OpenCharge", forHTTPHeaderField: "User-Agent")
  request.setValue(url.host == "api.github.com" ? "application/vnd.github+json" : "application/octet-stream", forHTTPHeaderField: "Accept")
  if url.host == "api.github.com" { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
  let transfer = ReleaseTransfer(limit: limit, destination: destination, progress: progress, configuration: configuration)
  let data = try await withTaskCancellationHandler(operation: { try await transfer.start(request) }, onCancel: { transfer.cancel() })
  try Task.checkCancellation(); return data
 }
 static func pages() async throws -> [Data] {
  var pages: [Data] = []
  for page in 1...5 {
   let data = try await transfer(URL(string: "https://api.github.com/repos/shengjk/OpenCharge/releases?per_page=100&page=\(page)")!, limit: 2 * 1024 * 1024)
   let count = try ReleaseCatalog.pageCount(data); pages.append(data)
   if count < 100 { return pages }
  }
  throw ReleaseUpdateError.releaseLimit
 }
 static func verifiedDownload(_ package: ReleasePackage, directory: URL, progress: (@Sendable (Double) -> Void)? = nil, configuration: URLSessionConfiguration? = nil) async throws -> URL {
  let data = try await transfer(package.checksumURL, limit: 65_536, configuration: configuration)
  let expected = try ReleaseCatalog.expectedChecksum(data, filename: package.filename)
  if let api = package.apiDigest, api != expected { throw ReleaseUpdateError.digestMismatch }
  try Task.checkCancellation()
  let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let partial = folder.appendingPathComponent(package.filename + ".partial")
  var complete = false
  defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
  _ = try await transfer(package.archiveURL, limit: min(package.size, ReleaseCatalog.maximumArchiveBytes), destination: partial, progress: progress, configuration: configuration)
  let verification = Task.detached(priority: .utility) { try verify(partial, size: package.size, expected: expected) }
  try await withTaskCancellationHandler(operation: { try await verification.value }, onCancel: { verification.cancel() })
  try Task.checkCancellation()
  try markQuarantine(partial, package: package)
  try Task.checkCancellation()
  let final = folder.appendingPathComponent(package.filename)
  try FileManager.default.moveItem(at: partial, to: final); complete = true; return final
 }
 static func markQuarantine(_ url: URL, package: ReleasePackage) throws {
  var item = url, values = URLResourceValues()
  values.quarantineProperties = [
   kLSQuarantineAgentNameKey as String: "OpenCharge",
   kLSQuarantineAgentBundleIdentifierKey as String: "org.opencharge.app",
   kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
   kLSQuarantineOriginURLKey as String: package.releaseURL,
   kLSQuarantineDataURLKey as String: package.archiveURL
  ]
  try item.setResourceValues(values)
  let fresh = URL(fileURLWithPath: url.path)
  guard try fresh.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties != nil else { throw CocoaError(.fileWriteUnknown) }
 }
 static func verify(_ url: URL, size: Int, expected: String) throws {
  let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
  var digest = SHA256(); var count = 0
  try Task.checkCancellation()
  while let data = try file.read(upToCount: 65_536), !data.isEmpty {
   try Task.checkCancellation()
   count += data.count; guard count <= size else { throw ReleaseUpdateError.sizeMismatch }; digest.update(data: data)
  }
  guard count == size else { throw ReleaseUpdateError.sizeMismatch }
  let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
  guard actual == expected.lowercased() else { throw ReleaseUpdateError.digestMismatch }
 }
}
