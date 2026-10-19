import Foundation

final class FakePMSet {
 var state: [String: Int]
 var writes: [[String]] = []
 var fail: (([String]) -> Bool)?
 init(battery: Int?, ac: Int?) {
  state = [:]; state["-b"] = battery; state["-c"] = ac
 }
 func run(_ arguments: [String], _ deadline: TimeInterval) throws -> String {
  precondition(deadline > ProcessInfo.processInfo.systemUptime)
  if arguments == ["-g", "custom"] {
   var text = ""
   for (flag, name) in [("-b", "Battery Power"), ("-c", "AC Power")] {
    if let value = state[flag] { text += "\(name):\n lowpowermode \(value)\n sleep 10\n" }
   }
   return text
  }
  precondition(arguments.count == 3 && ["-b", "-c"].contains(arguments[0]))
  precondition(arguments[1] == "lowpowermode" && ["0", "1"].contains(arguments[2]))
  writes.append(arguments)
  if fail?(arguments) == true { throw PowerModeError.unavailable("injected failure") }
  state[arguments[0]] = Int(arguments[2])!
  return ""
 }
 func controller() -> PowerModeController { PowerModeController(runner: run, authorizeWrites: { true }) }
}
@main struct Tests {
 static func main() throws {
  let text = "Battery Power:\n lowpowermode 1\nAC Power:\n lowpowermode 0\nUPS Power:\n lowpowermode 1\n"
  let parsed = try PowerModeController.parseCustom(text)
  precondition(parsed.battery == true && parsed.ac == false)
  for invalid in ["AC Power:\n lowpowermode 2\n", "AC Power:\n lowpowermode 0\n lowpowermode 1\n", "AC Power:\n lowpowermode 0\nAC Power:\n"] {
   do { _ = try PowerModeController.parseCustom(invalid); fatalError("invalid parse accepted") } catch { }
  }
  let separate = FakePMSet(battery: 0, ac: 0); let separateController = separate.controller()
  _ = try separateController.setEnabled(true, source: .battery)
  precondition(separate.state == ["-b": 1, "-c": 0])
  precondition(separate.writes == [["-b", "lowpowermode", "1"]])
  _ = try separateController.setEnabled(true, source: .ac)
  precondition(separate.state == ["-b": 1, "-c": 1])
  _ = try separateController.setEnabled(false, source: .battery)
  precondition(separate.state == ["-b": 0, "-c": 1])
  _ = try separateController.setEnabled(false, source: .ac)
  precondition(separate.state == ["-b": 0, "-c": 0])

  let targetedFailure = FakePMSet(battery: 0, ac: 0)
  let targetedController = targetedFailure.controller()
  _ = try targetedController.setEnabled(true, source: .battery)
  targetedFailure.fail = { $0 == ["-c", "lowpowermode", "1"] }
  do { _ = try targetedController.setEnabled(true, source: .ac); fatalError("targeted failure ignored") } catch { }
  precondition(targetedFailure.state == ["-b": 1, "-c": 0])
  precondition(targetedFailure.writes.filter { $0[0] == "-b" }.count == 1)

  let missingTarget = FakePMSet(battery: nil, ac: 0)
  do { _ = try missingTarget.controller().setEnabled(true, source: .battery); fatalError("missing target accepted") } catch { }
  precondition(missingTarget.writes.isEmpty && missingTarget.state == ["-c": 0])

  let mixed = FakePMSet(battery: 1, ac: 0); let mixedController = mixed.controller()
  _ = try mixedController.setEnabled(true)
  precondition(mixed.writes == [["-c", "lowpowermode", "1"]])
  _ = try mixedController.restore()
  precondition(mixed.state == ["-b": 1, "-c": 0])

  let absent = FakePMSet(battery: nil, ac: 0); let absentController = absent.controller()
  _ = try absentController.restore(); precondition(absent.writes.isEmpty)
  let absentStatus = try absentController.setEnabled(true)
  precondition(absentStatus.battery == nil && absent.state["-c"] == 1)
  precondition(absent.writes.allSatisfy { $0[0] == "-c" })

  let empty = FakePMSet(battery: nil, ac: nil)
  do { _ = try empty.controller().setEnabled(true); fatalError("missing settings accepted") } catch { }
  precondition(empty.writes.isEmpty)

  let partial = FakePMSet(battery: 0, ac: 0); let partialController = partial.controller()
  partial.fail = { $0 == ["-c", "lowpowermode", "1"] }
  do { _ = try partialController.setEnabled(true); fatalError("injected failure ignored") } catch { }
  precondition(partial.state == ["-b": 0, "-c": 0])

  let retry = FakePMSet(battery: 0, ac: 0); let retryController = retry.controller()
  retry.fail = { $0 == ["-c", "lowpowermode", "1"] || $0 == ["-b", "lowpowermode", "0"] }
  do { _ = try retryController.setEnabled(true); fatalError("cleanup failure ignored") } catch { }
  precondition(retry.state["-b"] == 1)
  retry.fail = nil
  _ = try retryController.restore()
  precondition(retry.state == ["-b": 0, "-c": 0])

  let existing = FakePMSet(battery: 0, ac: 0); let existingController = existing.controller()
  _ = try existingController.setEnabled(true)
  var failOnce = true
  existing.fail = { arguments in
   if arguments == ["-b", "lowpowermode", "0"] && failOnce { failOnce = false; return true }
   return false
  }
  do { _ = try existingController.setEnabled(false); fatalError("existing-write failure ignored") } catch { }
  precondition(existing.state == ["-b": 0, "-c": 0])

  let external = FakePMSet(battery: 0, ac: 0); let externalController = external.controller()
  _ = try externalController.setEnabled(true)
  external.state["-b"] = 0 // Independent System Settings change.
  let before = external.writes.count
  _ = try externalController.restore()
  precondition(external.state == ["-b": 0, "-c": 0])
  precondition(external.writes.count == before + 1 && external.writes.last![0] == "-c")

  let denied = FakePMSet(battery: 0, ac: 0)
  let deniedController = PowerModeController(runner: denied.run, authorizeWrites: { false })
  do { _ = try deniedController.setEnabled(true); fatalError("authorization ignored") } catch { }
  precondition(denied.writes.isEmpty)
  print("Low Power Mode fake-runner checks: parser, separate battery/AC on/off, targeted failure isolation, mixed sources, absent source, no-op restore, partial failure rollback, cleanup retry, external changes, authorization passed")
 }
}
