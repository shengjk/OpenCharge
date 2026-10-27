import XCTest
@testable import ChargeCore

final class SignedUpdateConfigurationTests: XCTestCase {
 private var valid: [String:Any] {
  var value: [String:Any] = ["CFBundleIdentifier":"org.opencharge.app", "SUPublicEDKey":Data(0..<32).base64EncodedString(), "SUFeedURL":SignedUpdateConfiguration.feedURL.absoluteString, "SUSignedFeedFailureExpirationInterval":0]
  for (key,flag) in SignedUpdateConfiguration.requiredBooleans { value[key] = flag }
  return value
 }
 func testMissingKeyKeepsExistingBuildUnconfigured() {
  XCTAssertEqual(SignedUpdateConfiguration.evaluate([:]),.unconfigured)
  var info = valid; info.removeValue(forKey:"SUPublicEDKey")
  XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.unconfigured)
 }
 func testCanonicalPublicKeyAndFixedFeedAreAccepted() {
  if case .ready(let config) = SignedUpdateConfiguration.evaluate(valid) {
   XCTAssertEqual(config.publicKey,Data(0..<32)); XCTAssertEqual(config.feed,SignedUpdateConfiguration.feedURL)
  } else { XCTFail("valid shape rejected") }
 }
 func testMalformedPublicKeysCannotStartSignedUpdater() {
  let invalid: [Any] = ["", " "+Data(0..<32).base64EncodedString(), Data(0..<32).base64EncodedString()+"\n", Data(0..<31).base64EncodedString(), Data(0..<33).base64EncodedString(), String(repeating:"!",count:44), Data(0..<32), NSNumber(value:1)]
  for key in invalid { var info = valid; info["SUPublicEDKey"] = key; XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.invalid) }
 }
 func testOnlyTheFixedRepositoryFeedIsAccepted() {
  for feed in ["http://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml", "https://raw.githubusercontent.com.evil.invalid/shengjk/OpenCharge/main/updates/appcast.xml", "https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml?test=1", "https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml#fragment", "https://raw.githubusercontent.com/shengjk/OpenCharge/other/updates/appcast.xml", "https://example.invalid/appcast.xml"] {
   var info = valid; info["SUFeedURL"] = feed; XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.invalid)
  }
  var info = valid; info["CFBundleIdentifier"] = "org.example.other"; XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.invalid)
 }
 func testUnsafeDefaultsAndNumericBooleanImpostorsAreRejected() {
  for (name,flag) in SignedUpdateConfiguration.requiredBooleans {
   for replacement: Any in [!flag, NSNumber(value:flag ? 1 : 0), flag ? "true" : "false"] {
    var info = valid; info[name] = replacement; XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.invalid)
   }
   var missing = valid; missing.removeValue(forKey:name); XCTAssertEqual(SignedUpdateConfiguration.evaluate(missing),.invalid)
  }
 }
 func testSignedFeedValidationCannotExpireOrUseBooleanZero() {
  for expiry: Any in [NSNumber(value:false), -1, 1, 1728000, Double.nan, Double.infinity, "0"] {
   var info = valid; info["SUSignedFeedFailureExpirationInterval"] = expiry; XCTAssertEqual(SignedUpdateConfiguration.evaluate(info),.invalid)
  }
  var missing = valid; missing.removeValue(forKey:"SUSignedFeedFailureExpirationInterval"); XCTAssertEqual(SignedUpdateConfiguration.evaluate(missing),.invalid)
 }
}
