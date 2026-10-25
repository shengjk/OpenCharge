import Foundation
import CryptoKit
import ChargeCore

private func require(_ value: Bool, _ message: String = "fixture assertion", file: StaticString = #filePath, line: UInt = #line) { precondition(value, message, file:(file), line:line) }

private struct ResponsePlan {
 var status = 200
 var headers: [String: String] = [:]
 var chunks: [Data] = []
 var error: URLError?
 var hold = false
 var redirect: URL?
 var responseURL: URL?
 var http = true
}
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
 private static let lock = NSLock()
 private static var plans: [String: ResponsePlan] = [:]
 private static var requests: [URLRequest] = []
 private static var stops = 0
 private let state = NSLock()
 private var stopped = false
 static func reset(_ values: [URL: ResponsePlan]) {
  lock.lock(); defer { lock.unlock() }
  plans = Dictionary(uniqueKeysWithValues: values.map { ($0.key.absoluteString, $0.value) }); requests = []; stops = 0
 }
 static var visits: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
 static var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.lock.lock(); Self.requests.append(request)
  let plan = Self.plans[request.url!.absoluteString] ?? ResponsePlan(status: 404)
  Self.lock.unlock()
  let url = plan.responseURL ?? request.url!
  let headers = ["Content-Type":"application/octet-stream"].merging(plan.headers) { _, new in new }
  let response: URLResponse = plan.http ? HTTPURLResponse(url: url, statusCode: plan.status, httpVersion: "HTTP/1.1", headerFields: headers)! : URLResponse(url: url, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)
  if let redirect = plan.redirect {
   client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response as! HTTPURLResponse); return
  }
  client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
  for chunk in plan.chunks {
   state.lock(); let stopped = self.stopped; state.unlock(); if stopped { return }
   client?.urlProtocol(self, didLoad: chunk)
  }
  if !plan.hold {
   if let error = plan.error { client?.urlProtocol(self, didFailWithError: error) }
   else { client?.urlProtocolDidFinishLoading(self) }
  }
 }
 override func stopLoading() {
  state.lock(); stopped = true; state.unlock()
  Self.lock.lock(); Self.stops += 1; Self.lock.unlock()
 }
}
private final class ProgressValues: @unchecked Sendable {
 private let lock = NSLock(); private var values: [Double] = []
 func append(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
 var snapshot: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}
private final class TaskSlot<Value: Sendable>: @unchecked Sendable {
 private let lock = NSLock(); private var task: Task<Value, Error>?
 func set(_ task: Task<Value, Error>) { lock.lock(); self.task = task; lock.unlock() }
 func cancel() { lock.lock(); let task = task; lock.unlock(); task?.cancel() }
}
@main struct UpdateTransportChecks {
 private enum FixtureError: Error { case timeout }
 private static let endpoint = URL(string: "https://api.github.com/repos/shengjk/OpenCharge/releases")!
 private static func configuration() -> URLSessionConfiguration {
  let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
  config.httpAdditionalHeaders = ["Authorization": "fixture-must-not-be-forwarded", "Cookie": "fixture=private"]
  return config
 }
 private static func expectFailure(_ operation: () async throws -> Void, matching: (Error) -> Bool) async throws {
  do { try await operation(); preconditionFailure("Unexpected transfer success") }
  catch { require(matching(error), "Unexpected error: \(error)") }
 }
 private static func waitUntil(_ condition: () -> Bool) async throws {
  let end = ProcessInfo.processInfo.systemUptime + 5
  while !condition() { guard ProcessInfo.processInfo.systemUptime < end else { throw FixtureError.timeout }; try await Task.sleep(nanoseconds: 5_000_000) }
 }
 private static func package(data: Data, size: Int? = nil, checksum: String? = nil, apiDigest: String? = nil) throws -> ReleasePackage {
  let filename = "OpenCharge-macOS-arm64.zip", prefix = "https://github.com/shengjk/OpenCharge/releases/download/v0.3.99/"
  var archive: [String: Any] = ["name":filename,"size":size ?? data.count,"browser_download_url":prefix+filename,"state":"uploaded"]
  if let apiDigest { archive["digest"] = "sha256:" + apiDigest }
  let feed: [[String: Any]] = [["tag_name":"v0.3.99","html_url":"https://github.com/shengjk/OpenCharge/releases/tag/v0.3.99","draft":false,"prerelease":true,"assets":[archive,["name":"SHA256SUMS.txt","size":100,"browser_download_url":prefix+"SHA256SUMS.txt","state":"uploaded"]]]]
  guard case .available(let result) = try ReleaseCatalog.evaluate(pages:[JSONSerialization.data(withJSONObject:feed)],currentVersion:"0.0.0",includePreviews:true,architecture:.appleSilicon) else { fatalError("fixture package unavailable") }
  let hash = checksum ?? SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
  FixtureProtocol.reset([result.checksumURL:ResponsePlan(chunks:[Data((hash+"  "+filename+"\n").utf8)]),result.archiveURL:ResponsePlan(chunks:[data])])
  return result
 }
 private static func note(_ text: String) { FileHandle.standardError.write(Data(("CHECK "+text+"\n").utf8)) }
 @MainActor static func main() async throws {
  let config = configuration(), fm = FileManager.default
  let folder = fm.temporaryDirectory.appendingPathComponent("OpenCharge-transport-"+UUID().uuidString)
  try fm.createDirectory(at:folder,withIntermediateDirectories:true); defer { try? fm.removeItem(at:folder) }
  note("fragmented body and sanitized headers")
  let body = Data("abc".utf8)
  FixtureProtocol.reset([endpoint:ResponsePlan(chunks:[Data("a".utf8),Data("bc".utf8)])])
  let received = try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config)
  require(received == body)
  let request = FixtureProtocol.visits[0]
  require(request.value(forHTTPHeaderField:"User-Agent") == "OpenCharge")
  require(request.value(forHTTPHeaderField:"Accept") == "application/vnd.github+json")
  require(request.value(forHTTPHeaderField:"X-GitHub-Api-Version") == "2022-11-28")
  require(request.value(forHTTPHeaderField:"Authorization") == nil && request.value(forHTTPHeaderField:"Cookie") == nil)
  note("length and chunk bounds")
  for plan in [ResponsePlan(headers:["Content-Length":"4"],chunks:[body]),ResponsePlan(chunks:[body,Data([0])])] {
   FixtureProtocol.reset([endpoint:plan]); let file = folder.appendingPathComponent(UUID().uuidString)
   try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:3,destination:file,configuration:config) },matching:{ if case ReleaseUpdateError.transferTooLarge = $0 { return true }; return false })
   if fm.fileExists(atPath:file.path) { require((try Data(contentsOf:file)).count <= 3) }
  }
  note("HTTP rejection")
  for status in [302,403,404,500] {
   FixtureProtocol.reset([endpoint:ResponsePlan(status:status,chunks:[body])]);let file = folder.appendingPathComponent(UUID().uuidString)
   try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:3,destination:file,configuration:config) },matching:{ if case ReleaseUpdateError.http(let code) = $0 { return code == status }; return false })
   require(!fm.fileExists(atPath:file.path))
  }
  note("response URL and response type")
  for plan in [ResponsePlan(responseURL:URL(string:"https://example.invalid/a")),ResponsePlan(http:false)] {
   FixtureProtocol.reset([endpoint:plan])
   try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config) },matching:{ if case ReleaseUpdateError.invalidURL = $0 { return true }; return false })
  }
  FixtureProtocol.reset([:])
  for address in ["http://github.com/a","https://token@github.com/a","https://example.invalid/a"] {
   try await expectFailure({ _ = try await ReleaseHTTP.transfer(URL(string:address)!,limit:3,configuration:config) },matching:{ if case ReleaseUpdateError.invalidURL = $0 { return true }; return false })
  }
  require(FixtureProtocol.visits.isEmpty)
  note("allowed redirect")
  let final = URL(string:"https://release-assets.githubusercontent.com/fixture")!
  FixtureProtocol.reset([endpoint:ResponsePlan(status:302,redirect:final),final:ResponsePlan(chunks:[body])])
  require(try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config) == body)
  note("forbidden redirect")
  let forbidden = URL(string:"https://example.invalid/redirect")!
  FixtureProtocol.reset([endpoint:ResponsePlan(status:302,redirect:forbidden)])
  try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config) },matching:{ if case ReleaseUpdateError.invalidURL = $0 { return true }; return false })
  require(!FixtureProtocol.visits.contains { $0.url == forbidden })
  note("exclusive files and symlinks")
  let existing = folder.appendingPathComponent("existing")
  try body.write(to:existing); FixtureProtocol.reset([endpoint:ResponsePlan(chunks:[Data("overwrite".utf8)])])
  try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:16,destination:existing,configuration:config) },matching:{ $0 is CocoaError })
  require(try Data(contentsOf:existing) == body)
  let link = folder.appendingPathComponent("link");try fm.createSymbolicLink(at:link,withDestinationURL:existing)
  try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:16,destination:link,configuration:config) },matching:{ $0 is CocoaError })
  require(try Data(contentsOf:existing) == body)
  note("network failure and cancellation")
  FixtureProtocol.reset([endpoint:ResponsePlan(error:URLError(.networkConnectionLost))])
  try await expectFailure({ _ = try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config) },matching:{ ($0 as? URLError)?.code == .networkConnectionLost })
  FixtureProtocol.reset([:])
  let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await ReleaseHTTP.transfer(endpoint,limit:3,configuration:config) }
  try await expectFailure({ _ = try await cancelled.value },matching:{ $0 is CancellationError })
  require(FixtureProtocol.visits.isEmpty)
  let heldFile = folder.appendingPathComponent("held")
  FixtureProtocol.reset([endpoint:ResponsePlan(chunks:[Data([0])],hold:true)])
  let held = Task { try await ReleaseHTTP.transfer(endpoint,limit:3,destination:heldFile,configuration:config) }
  note("cancel after response/body delivery")
  try await waitUntil { fm.fileExists(atPath:heldFile.path) };held.cancel()
  try await expectFailure({ _ = try await held.value },matching:{ $0 is CancellationError })
  note("cancel reaches URLProtocol stop")
  try await waitUntil { FixtureProtocol.stopCount > 0 }
  note("file streaming and progress")
  let large = Data(repeating:7,count:70_001), progress = ProgressValues(), streamed = folder.appendingPathComponent("streamed")
  FixtureProtocol.reset([endpoint:ResponsePlan(headers:["Content-Length":String(large.count)],chunks:[large.prefix(65_536),large.suffix(large.count-65_536)])])
  let memory = try await ReleaseHTTP.transfer(endpoint,limit:large.count,destination:streamed,progress:{ progress.append($0) },configuration:config)
  let streamedData = try Data(contentsOf:streamed)
  require(memory.isEmpty && streamedData == large)
  require(progress.snapshot.last == 1 && progress.snapshot.allSatisfy { (0...1).contains($0) })
  note("verified download and quarantine")
  let packages = folder.appendingPathComponent("packages")
  let valid = try package(data:body)
  let archive = try await ReleaseHTTP.verifiedDownload(valid,directory:packages,configuration:config)
  require(try Data(contentsOf:archive) == body)
  require(try archive.resourceValues(forKeys:[.quarantinePropertiesKey]).quarantineProperties != nil)
  try fm.removeItem(at:packages)
  for (size,checksum,api) in [(4,Optional<String>.none,Optional<String>.none),(3,String(repeating:"0",count:64),nil),(3,nil,String(repeating:"0",count:64))] {
   let invalid = try package(data:body,size:size,checksum:checksum,apiDigest:api)
   try await expectFailure({ _ = try await ReleaseHTTP.verifiedDownload(invalid,directory:packages,configuration:config) },matching:{ if case ReleaseUpdateError.sizeMismatch = $0 { return true }; if case ReleaseUpdateError.digestMismatch = $0 { return true }; return false })
   if fm.fileExists(atPath:packages.path) { require(try fm.contentsOfDirectory(atPath:packages.path).isEmpty) }
  }
  note("cancellation during completion")
  let cancelledHash = Task {
   withUnsafeCurrentTask { $0?.cancel() }
   try ReleaseHTTP.verify(existing,size:body.count,expected:SHA256.hash(data:body).map { String(format:"%02x",$0) }.joined())
  }
  try await expectFailure({ try await cancelledHash.value },matching:{ $0 is CancellationError })
  let cancelPackage = try package(data:body), slot = TaskSlot<URL>()
  let download = Task { try await ReleaseHTTP.verifiedDownload(cancelPackage,directory:packages,progress:{ _ in slot.cancel() },configuration:config) }
  slot.set(download)
  try await expectFailure({ _ = try await download.value },matching:{ $0 is CancellationError })
  require((try fm.contentsOfDirectory(atPath:packages.path)).isEmpty)
  print("PASS update transport: headers, bounded memory/file streams, HTTP/redirect rejection, exclusive files, network errors, cancellation, size/hash/API digest, quarantine and failed-download cleanup; URLProtocol fixtures only")
 }
}
