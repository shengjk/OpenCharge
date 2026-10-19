import Foundation
import CryptoKit
import CoreServices
import ChargeCore
import Darwin

final class ReleaseRedirects: NSObject, URLSessionTaskDelegate {
 static func allowed(_ url: URL) -> Bool {
  let hosts = ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"]
  return url.scheme == "https" && hosts.contains(url.host ?? "") && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
 }
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
  completionHandler(request.url.map(Self.allowed) == true ? request : nil)
 }
}
enum ReleaseHTTP {
 /// No cookies, credentials, telemetry, arbitrary endpoints or launch commands.
 private static func session() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
  config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
  return URLSession(configuration: config, delegate: ReleaseRedirects(), delegateQueue: nil)
 }
 static func transfer(_ url: URL, limit: Int, destination: URL? = nil, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
  guard ReleaseRedirects.allowed(url), limit > 0 else { throw ReleaseUpdateError.invalidURL }
  let client = session(); defer { client.invalidateAndCancel() }
  var request = URLRequest(url: url); request.setValue("OpenCharge", forHTTPHeaderField: "User-Agent")
  request.setValue(url.host == "api.github.com" ? "application/vnd.github+json" : "application/octet-stream", forHTTPHeaderField: "Accept")
  if url.host == "api.github.com" { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
  let (stream, response) = try await client.bytes(for: request)
  defer { stream.task.cancel() }
  guard let http = response as? HTTPURLResponse, let final = http.url, ReleaseRedirects.allowed(final) else { throw ReleaseUpdateError.invalidURL }
  guard http.statusCode == 200 else { throw ReleaseUpdateError.http(http.statusCode) }
  guard response.expectedContentLength <= limit else { throw ReleaseUpdateError.transferTooLarge }
  let file: FileHandle?
  if let destination {
   let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
   guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
   file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
  } else { file = nil }
  defer { try? file?.close() }
  var result = Data(), chunk = Data(); chunk.reserveCapacity(65_536)
  var count = 0
  for try await byte in stream {
   count += 1; guard count <= limit else { throw ReleaseUpdateError.transferTooLarge }
   chunk.append(byte)
   if chunk.count >= 65_536 {
    try Task.checkCancellation()
    if let file { try file.write(contentsOf: chunk) } else { result.append(chunk) }
    chunk.removeAll(keepingCapacity: true)
    if response.expectedContentLength > 0 { progress?(min(1, Double(count) / Double(response.expectedContentLength))) }
   }
  }
  if let file { try file.write(contentsOf: chunk); try file.synchronize() } else { result.append(chunk) }
  progress?(1); return result
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
 static func verifiedDownload(_ package: ReleasePackage, directory: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
  let data = try await transfer(package.checksumURL, limit: 65_536)
  let expected = try ReleaseCatalog.expectedChecksum(data, filename: package.filename)
  if let api = package.apiDigest, api != expected { throw ReleaseUpdateError.digestMismatch }
  let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let partial = folder.appendingPathComponent(package.filename + ".partial")
  var complete = false
  defer { if !complete { try? FileManager.default.removeItem(at: folder) } }
  _ = try await transfer(package.archiveURL, limit: min(package.size, ReleaseCatalog.maximumArchiveBytes), destination: partial, progress: progress)
  try await Task.detached(priority: .utility) { try verify(partial, size: package.size, expected: expected) }.value
  try markQuarantine(partial, package: package)
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
  while let data = try file.read(upToCount: 65_536), !data.isEmpty {
   count += data.count; guard count <= size else { throw ReleaseUpdateError.sizeMismatch }; digest.update(data: data)
  }
  guard count == size else { throw ReleaseUpdateError.sizeMismatch }
  let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
  guard actual == expected.lowercased() else { throw ReleaseUpdateError.digestMismatch }
 }
}
