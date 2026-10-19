import Foundation
@main struct HelperCommandTests {
 static func main() throws {
  let expected = ["magSafeSystem", "magSafeBlinkOrange", "magSafeSleepOn", "magSafeSleepOff", "magSafeStatus", "magSafeOff", "magSafeGreen", "magSafeOrange", "magSafeRestore"]
  precondition(expected.allSatisfy { HelperClient.supportedActions.contains($0) })
  for invalid in ["ACLC", "magSafeBlue", "magSafeGreen\nrestore", "write /tmp/test", ""] {
   precondition(!HelperClient.supportedActions.contains(invalid))
   do { _ = try HelperClient.request(invalid); preconditionFailure("unbounded action accepted") }
   catch HelperError.rejected(let message) { precondition(message == "unknown helper action") }
  }
  print("PASS fixed LED commands accepted by client whitelist; raw keys/unknown/framed commands rejected without IPC")
 }
}
