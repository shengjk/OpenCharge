import XCTest
@testable import ChargeCore

final class SignedUpdateItemTests: XCTestCase {
 private func accepts(version: String = "1.2.3", currentVersion: String = "1.2.2", build: String = "59", url: String = "https://github.com/shengjk/OpenCharge/releases/download/v1.2.3/OpenCharge-macOS-universal.zip", size: UInt64 = 1234, kind: String = "application", delta: Bool = false, channel: String? = nil, previews: Bool = true, architecture: UpdateArchitecture = .intel) -> Bool {
  do { try SignedUpdateItemPolicy.validate(version:version,currentVersion:currentVersion,build:build,url:URL(string:url),size:size,installationType:kind,delta:delta,channel:channel,includePreviews:previews,architecture:architecture); return true } catch { return false }
 }
 func testFullUniversalArchiveWorksOnBothArchitectures() { XCTAssertTrue(accepts()); XCTAssertTrue(accepts(architecture:.appleSilicon)) }
 func testHigherBuildCannotDowngradeDisplayVersion() {
  XCTAssertFalse(accepts(currentVersion:"1.2.4",build:"999")); XCTAssertFalse(accepts(currentVersion:"1.2.3",build:"999")); XCTAssertFalse(accepts(currentVersion:"development")); XCTAssertTrue(accepts(currentVersion:"1.2.3-beta.1"))
 }
 func testArmArchiveNeverSelectedForIntel() {
  let url = "https://github.com/shengjk/OpenCharge/releases/download/v1.2.3/OpenCharge-macOS-arm64.zip"
  XCTAssertTrue(accepts(url:url,architecture:.appleSilicon)); XCTAssertFalse(accepts(url:url))
 }
 func testRepositoryIdentityAndCanonicalPathAreRequired() {
  let base = "https://github.com/shengjk/OpenCharge/releases/download/v1.2.3/OpenCharge-macOS-universal.zip"
  for url in [base.replacingOccurrences(of:"https:",with:"http:"),base.replacingOccurrences(of:"github.com/",with:"github.com.evil.invalid/"),base.replacingOccurrences(of:"shengjk",with:"other"),base.replacingOccurrences(of:"v1.2.3/",with:"v1.2.4/"),base.replacingOccurrences(of:"OpenCharge/releases",with:"OpenCharge/%72eleases"),base+"?download=1",base+"#file",base.replacingOccurrences(of:"github.com/",with:"user@github.com/"),base.replacingOccurrences(of:"github.com/",with:"github.com:443/"),base.replacingOccurrences(of:"universal.zip",with:"universal.pkg"),""] { XCTAssertFalse(accepts(url:url),url) }
 }
 func testVersionsAndBuildNumbersAreBoundedAndCanonical() {
  for version in ["v1.2.3","1.02.3","1.2","1.2.3\n",""] { XCTAssertFalse(accepts(version:version)) }
  for build in ["0","059","-1","1.0","1e2","",String(repeating:"9",count:19),"59\n"] { XCTAssertFalse(accepts(build:build)) }
  XCTAssertTrue(accepts(build:"999999999999999999"))
 }
 func testInstallerAndDeltaRoutesAreRejected() { for kind in ["package","guided-package","interactive-package",""] { XCTAssertFalse(accepts(kind:kind)) }; XCTAssertFalse(accepts(delta:true)) }
 func testArchiveSizeBoundsAreEnforced() { XCTAssertFalse(accepts(size:0)); XCTAssertTrue(accepts(size:UInt64(ReleaseCatalog.maximumArchiveBytes))); XCTAssertFalse(accepts(size:UInt64(ReleaseCatalog.maximumArchiveBytes)+1)); XCTAssertFalse(accepts(size:.max)) }
 func testPreviewChannelIsOptInAndUnknownChannelsFail() { XCTAssertTrue(accepts(channel:"preview")); XCTAssertFalse(accepts(channel:"preview",previews:false)); XCTAssertTrue(accepts(previews:false)); XCTAssertFalse(accepts(channel:"nightly")); XCTAssertFalse(accepts(channel:"")) }
 func testPrereleaseCannotEnterStableChannel() {
  let url = "https://github.com/shengjk/OpenCharge/releases/download/v1.2.3-beta.1/OpenCharge-macOS-universal.zip"
  XCTAssertTrue(accepts(version:"1.2.3-beta.1",url:url)); XCTAssertFalse(accepts(version:"1.2.3-beta.1",url:url,previews:false))
 }
}
