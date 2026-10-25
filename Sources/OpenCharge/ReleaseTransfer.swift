import Foundation
import ChargeCore
import Darwin

/// A serial response/body sink with cancellation synchronized against callbacks.
/// URLSession's delegate transport is available before its async byte iterator.
final class ReleaseTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
 private let lock = NSLock()
 private let limit: Int
 private let destination: URL?
 private let progress: (@Sendable (Double) -> Void)?
 private let configuration: URLSessionConfiguration
 private var continuation: CheckedContinuation<Data, Error>?
 private var session: URLSession?
 private var task: URLSessionDataTask?
 private var file: FileHandle?
 private var result = Data()
 private var received = 0
 private var reported = 0
 private var expected: Int64 = -1
 private var accepted = false
 private var finished = false

 init(limit: Int, destination: URL?, progress: (@Sendable (Double) -> Void)?, configuration: URLSessionConfiguration?) {
  self.limit = limit; self.destination = destination; self.progress = progress
  let config = (configuration?.copy() as? URLSessionConfiguration) ?? .ephemeral
  config.httpCookieStorage = nil; config.httpShouldSetCookies = false
  config.urlCredentialStorage = nil; config.urlCache = nil; config.httpAdditionalHeaders = nil
  config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
  self.configuration = config
 }
 private func locked<T>(_ operation: () throws -> T) rethrows -> T {
  lock.lock(); defer { lock.unlock() }; return try operation()
 }
 func start(_ request: URLRequest) async throws -> Data {
  try await withCheckedThrowingContinuation { continuation in
   let task: URLSessionDataTask? = locked {
    guard !finished else { return nil }
    self.continuation = continuation
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    let task = session.dataTask(with: request)
    self.session = session; self.task = task; return task
   }
   if let task { task.resume() }
   else { continuation.resume(throwing: CancellationError()) }
  }
 }
 func cancel() { finish(.failure(CancellationError())) }
 private func finish(_ outcome: Result<Data, Error>) {
  let completion = locked { () -> (CheckedContinuation<Data, Error>?, URLSession?, URLSessionDataTask?, Result<Data, Error>)? in
   guard !finished else { return nil }
   finished = true
   var outcome = outcome
   if case .success = outcome {
    do { try file?.synchronize() } catch { outcome = .failure(error) }
   }
   do { try file?.close() } catch { if case .success = outcome { outcome = .failure(error) } }
   file = nil
   let values = (continuation, session, task, outcome)
   continuation = nil; session = nil; task = nil; result.removeAll()
   return values
  }
  guard let (continuation, session, task, outcome) = completion else { return }
  task?.cancel(); session?.invalidateAndCancel()
  if case .success = outcome { progress?(1) }
  continuation?.resume(with: outcome)
 }
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                 newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
  guard request.url.map(ReleaseRedirects.allowed) == true else {
   finish(.failure(ReleaseUpdateError.invalidURL)); completionHandler(nil); return
  }
  completionHandler(request)
 }
 func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                 completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
  do {
   let accept = try locked { () throws -> Bool in
    guard !finished else { return false }
    guard !accepted, let http = response as? HTTPURLResponse, let url = http.url, ReleaseRedirects.allowed(url) else { throw ReleaseUpdateError.invalidURL }
    guard http.statusCode == 200 else { throw ReleaseUpdateError.http(http.statusCode) }
    guard response.expectedContentLength <= Int64(limit) else { throw ReleaseUpdateError.transferTooLarge }
    if let destination {
     let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
     guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
     file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    expected = response.expectedContentLength; accepted = true; return true
   }
   completionHandler(accept ? .allow : .cancel)
  } catch { finish(.failure(error)); completionHandler(.cancel) }
 }
 func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
  do {
   let fraction: Double? = try locked {
    guard !finished else { return nil }
    guard accepted else { throw ReleaseUpdateError.invalidURL }
    guard data.count <= limit - received else { throw ReleaseUpdateError.transferTooLarge }
    received += data.count
    if let file { try file.write(contentsOf: data) } else { result.append(data) }
    guard expected > 0, received - reported >= 65_536 else { return nil }
    reported = received; return min(1, Double(received) / Double(expected))
   }
   if let fraction { progress?(fraction) }
  } catch { finish(.failure(error)) }
 }
 func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
  if let error { finish(.failure(error)); return }
  let data: Data? = locked { finished ? nil : (accepted ? result : nil) }
  if let data { finish(.success(data)) }
  else { finish(.failure(ReleaseUpdateError.invalidURL)) }
 }
}
