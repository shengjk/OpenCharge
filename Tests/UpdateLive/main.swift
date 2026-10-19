import Foundation
import ChargeCore
import Darwin

@main struct UpdateLive {
 static func main() async throws {
  let started = Date()
  let pages = try await ReleaseHTTP.pages()
  let selected = try ReleaseCatalog.evaluate(pages: pages, currentVersion: "0.0.0", includePreviews: true, architecture: .appleSilicon)
  guard case .available(let package) = selected else { fatalError("Live public feed did not provide a package") }
  precondition(package.version != "0.3.9", "withdrawn draft must not be selected")
  print("LIVE public catalog selected",package.version,package.filename)
  var rejectedLimit = false
  do { _ = try await ReleaseHTTP.transfer(package.archiveURL, limit: 16) }
  catch ReleaseUpdateError.transferTooLarge { rejectedLimit = true }
  precondition(rejectedLimit, "oversized response must be stopped")
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-live-update-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = try await ReleaseHTTP.verifiedDownload(package, directory: folder)
  let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! NSNumber
  precondition(size.intValue == package.size)
  let quarantine = getxattr(file.path, "com.apple.quarantine", nil, 0, 0, 0)
  precondition(quarantine > 0, "download must retain quarantine metadata")
  print("LIVE archive streamed, size/SHA-256/API digest and quarantine verified:",size.intValue,"bytes")
  print(String(format: "Live update check/download completed in %.2fs; no application/helper installation, no hardware actions", Date().timeIntervalSince(started)))
 }
}
