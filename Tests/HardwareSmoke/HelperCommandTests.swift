import Foundation
@main struct HelperCommandTests {
 static func main() throws {
  let expected = ["magSafeSystem", "magSafeBlinkOrange", "magSafeSleepOn", "magSafeSleepOff", "magSafeStatus", "magSafeOff", "magSafeGreen", "magSafeOrange", "magSafeRestore"]
  precondition(expected.allSatisfy { HelperClient.supportedActions.contains($0) })
  precondition(FirmwareCommand.supportedActions.allSatisfy { HelperClient.supportedActions.contains($0) })
  for invalid in ["firmwareLimit:15", "firmwareLimit:020", "firmwareExit:101", "firmwareSleep:16", "firmwareLimit:20\nrestore", "ACLC", "magSafeBlue", "magSafeGreen\nrestore", "write /tmp/test", ""] {
   precondition(!HelperClient.supportedActions.contains(invalid))
   do { _ = try HelperClient.request(invalid); preconditionFailure("unbounded action accepted") }
   catch HelperError.rejected(let message) { precondition(message == "unknown helper action") }
  }
  for command in [FirmwareCommand.limit(19), .exit(15), .sleepTarget(16)] {
   do { _ = try HelperClient.request(command); preconditionFailure("invalid typed request accepted") }
   catch HelperError.rejected(let message) { precondition(message == "invalid firmware command") }
  }
  do { _ = try HelperClient.decodeReply(ChargeControlSuspension.reply); preconditionFailure("suspension accepted") }
  catch ChargeControlSuspension.systemSleep {}
  for reply in ["ERROR sleep-transition", "SUSPENDED sleep-transition ", "SUSPENDED other", "SUSPENDED sleep-transition\n"] {
   do { _ = try HelperClient.decodeReply(reply); preconditionFailure("malformed suspension") }
   catch HelperError.rejected(let message) { precondition(message == reply) }
  }
  let recovered = try HelperClient.decodeReply("OK recovered"); precondition(recovered == "recovered")
  print("PASS fixed firmware/LED commands accepted by client whitelist; raw keys/unknown/framed commands rejected without IPC")
 }
}
