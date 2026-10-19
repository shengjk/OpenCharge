import XCTest
@testable import ChargeCore

final class ReleaseUpdateTests: XCTestCase {
 private func release(_ tag: String = "v0.3.11", preview: Bool = false, draft: Bool = false, assets: [[String: Any]]? = nil, page: String? = nil) -> [String: Any] {
  ["tag_name": tag, "html_url": page ?? "https://github.com/shengjk/OpenCharge/releases/tag/\(tag)", "draft": draft, "prerelease": preview,
   "assets": assets ?? [asset("OpenCharge-macOS-arm64.zip", tag: tag), asset("OpenCharge-macOS-universal.zip", tag: tag), asset("SHA256SUMS.txt", tag: tag, size: 190)]]
 }
 private func asset(_ name: String, tag: String = "v0.3.11", size: Int = 1000, url: String? = nil, digest: String? = nil) -> [String: Any] {
  var value: [String: Any] = ["name": name, "size": size, "state": "uploaded", "browser_download_url": url ?? "https://github.com/shengjk/OpenCharge/releases/download/\(tag)/\(name)"]
  if let digest { value["digest"] = digest }; return value
 }
 private func select(_ releases: [[String: Any]], current: String = "0.3.10", previews: Bool = true, arch: UpdateArchitecture = .appleSilicon) throws -> ReleaseSelection {
  try ReleaseCatalog.evaluate(pages: [JSONSerialization.data(withJSONObject: releases)], currentVersion: current, includePreviews: previews, architecture: arch)
 }
 private func rejects(_ run: () throws -> Void) { do { try run(); XCTFail("unexpected update acceptance") } catch {} }
 func testNumericVersionOrdering() {
  XCTAssertTrue(ReleaseVersion("v0.3.9")! < ReleaseVersion("0.3.10")!)
  XCTAssertTrue(ReleaseVersion("1.10.0")! < ReleaseVersion("2.0.0")!)
  XCTAssertEqual(ReleaseVersion("v1.2.3+one"), ReleaseVersion("1.2.3+two"))
 }
 func testPrereleaseOrdering() {
  let values = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"].map { ReleaseVersion($0)! }
  for pair in zip(values, values.dropFirst()) { XCTAssertTrue(pair.0 < pair.1) }
  XCTAssertTrue(ReleaseVersion("1.0.0-99999999999999999999")! < ReleaseVersion("1.0.0-100000000000000000000")!)
 }
 func testRejectsMalformedVersions() {
  for value in ["", "V1.2.3", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "-1.2.3", "1.2.3-", "1.2.3-alpha..one", "1.2.3-01", "1.2.3+", "1.2.3+one+two", "1.2.3/../4", "1.2.3-β", String(repeating: "1", count: 129)] { XCTAssertNil(ReleaseVersion(value)) }
 }
 func testHighestVersionNotListOrder() {
  guard case .available(let package)? = try? select([release("v0.3.9"), release("v0.3.12"), release("v0.3.11")]) else { return XCTFail("missing candidate") }
  XCTAssertEqual(package.version, "0.3.12")
 }
 func testDraftsAndPreviewChannel() {
  XCTAssertEqual(try? select([release("v99.0.0", draft: true), release("v0.3.11", preview: true)], previews: false), .noReleases)
  XCTAssertEqual(try? select([release("v0.3.11-rc.1")], previews: false), .noReleases)
  guard case .available? = try? select([release("v0.3.11", preview: true)]) else { return XCTFail("preview not selected") }
 }
 func testCurrentAheadAndNoRelease() {
  XCTAssertEqual(try? select([release("v0.3.10")]), .current("0.3.10"))
  XCTAssertEqual(try? select([release("v0.3.9")]), .ahead("0.3.9"))
  XCTAssertEqual(try? select([]), .noReleases)
  rejects { _ = try select([release()], current: "development") }
 }
 func testArchitectureAndFallback() {
  guard case .available(let arm)? = try? select([release()]), case .available(let intel)? = try? select([release()], arch: .intel),
        case .available(let fallback)? = try? select([release(assets: [asset("OpenCharge-macOS-universal.zip"), asset("SHA256SUMS.txt")])]) else { return XCTFail("missing packages") }
  XCTAssertEqual(arm.filename, "OpenCharge-macOS-arm64.zip")
  XCTAssertEqual(intel.filename, "OpenCharge-macOS-universal.zip")
  XCTAssertEqual(fallback.filename, intel.filename)
 }
 func testMissingNewPackageDoesNotOfferOlderRelease() {
  let expected = URL(string: "https://github.com/shengjk/OpenCharge/releases/tag/v0.3.12")!
  XCTAssertEqual(try? select([release("v0.3.12", assets: []), release("v0.3.11")]), .missingPackage("0.3.12", expected))
 }
 func testPinnedURLsRejectOtherHostsPathsAndCredentials() {
  for url in ["http://github.com/shengjk/OpenCharge/releases/download/v0.3.11/OpenCharge-macOS-arm64.zip", "https://github.com.evil.test/file.zip", "https://token@github.com/shengjk/OpenCharge/releases/download/v0.3.11/OpenCharge-macOS-arm64.zip", "https://github.com/other/repo/releases/download/v0.3.11/OpenCharge-macOS-arm64.zip", "https://github.com/shengjk/OpenCharge/releases/download/v0.3.11/OpenCharge-macOS-arm64.zip?extra=1"] {
   rejects { _ = try select([release(assets: [asset("OpenCharge-macOS-arm64.zip", url: url), asset("SHA256SUMS.txt")])]) }
  }
  rejects { _ = try select([release(page: "https://example.test/releases")]) }
 }
 func testSizeChecksumAndDuplicateAssets() {
  for size in [0, -1, ReleaseCatalog.maximumArchiveBytes + 1] {
   rejects { _ = try select([release(assets: [asset("OpenCharge-macOS-arm64.zip", size: size), asset("SHA256SUMS.txt")])]) }
  }
  rejects { _ = try select([release(assets: [asset("OpenCharge-macOS-arm64.zip")])]) }
  rejects { _ = try select([release(assets: [asset("OpenCharge-macOS-arm64.zip"), asset("OpenCharge-macOS-arm64.zip"), asset("SHA256SUMS.txt")])]) }
  rejects { _ = try select([release(assets: [asset("OpenCharge-macOS-arm64.zip", digest: "sha256:bad"), asset("SHA256SUMS.txt")])]) }
 }
 func testFeedAndPageBounds() {
  rejects { _ = try ReleaseCatalog.pageCount(Data("bad".utf8)) }
  rejects { _ = try ReleaseCatalog.pageCount(Data(repeating: 32, count: 2 * 1024 * 1024 + 1)) }
  rejects { _ = try select(Array(repeating: release(), count: 101)) }
  rejects { _ = try ReleaseCatalog.evaluate(pages: Array(repeating: Data("[]".utf8), count: 6), currentVersion: "1.0.0", includePreviews: true, architecture: .intel) }
 }
 func testChecksumParsingAndAmbiguity() {
  let hash = String(repeating: "A", count: 64), name = "OpenCharge-macOS-arm64.zip"
  XCTAssertEqual(try? ReleaseCatalog.expectedChecksum(Data((hash + "  " + name + "\n").utf8), filename: name), hash.lowercased())
  XCTAssertEqual(try? ReleaseCatalog.expectedChecksum(Data((hash + " *" + name + "\n").utf8), filename: name), hash.lowercased())
  for value in ["bad  " + name, hash + "  ../" + name, hash + "  " + name + "\n" + hash + "  " + name, hash + "  other.zip"] {
   rejects { _ = try ReleaseCatalog.expectedChecksum(Data(value.utf8), filename: name) }
  }
 }
 func testCadenceAndClockRollback() {
  XCTAssertTrue(ReleaseCheckCadence.due(now: 100, lastAttempt: nil, interval: 60))
  XCTAssertFalse(ReleaseCheckCadence.due(now: 100, lastAttempt: 90, interval: 60))
  XCTAssertTrue(ReleaseCheckCadence.due(now: 150, lastAttempt: 90, interval: 60))
  XCTAssertTrue(ReleaseCheckCadence.due(now: 100, lastAttempt: 200, interval: 60))
  XCTAssertTrue(ReleaseCheckCadence.due(now: 100, lastAttempt: .nan, interval: 60))
  XCTAssertFalse(ReleaseCheckCadence.due(now: .infinity, lastAttempt: nil, interval: 60))
 }
}
