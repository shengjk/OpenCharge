import Foundation

final class EnergyPMSetFixture {
 var modes: [String: Int] = ["-b": 0, "-c": 2]
 var highSources = Set(["-b", "-c"])
 var highCapabilities: Set<String>?
 var writes: [[String]] = []
 var reject: (([String]) -> Bool)?
 var liveFails = false
 var failAfterWrite = false
 func run(_ args: [String], _ deadline: TimeInterval) throws -> String {
  precondition(deadline > ProcessInfo.processInfo.systemUptime)
  if args == ["-g", "custom"] {
   return [("-b", "Battery Power"), ("-c", "AC Power")].compactMap { flag, name in
    modes[flag].map { "\(name):\n \(highSources.contains(flag) ? "powermode" : "lowpowermode") \($0)\n" }
   }.joined()
  }
  if args == ["-g", "live"] {
   if liveFails { throw PowerModeError.unavailable("fixture live unavailable") }
   return "Currently in use:\n powermode \(modes["-c"] ?? 0)\n"
  }
  precondition(args.count == 3 && ["-b", "-c"].contains(args[0]))
  precondition(args[1] == ((highSources.contains(args[0]) || (highCapabilities ?? highSources).contains(args[0])) ? "powermode" : "lowpowermode"))
  let value = Int(args[2])!
  precondition((0...2).contains(value) && (value != 2 || (highCapabilities ?? highSources).contains(args[0])))
  writes.append(args)
  if reject?(args) == true {
   if failAfterWrite { modes[args[0]] = value }
   throw PowerModeError.unavailable("fixture write failure")
  }
  modes[args[0]] = value
  return ""
 }
 func controller() -> PowerModeController { PowerModeController(runner: run, authorizeWrites: { true }, highPowerAvailability: { (self.highCapabilities ?? self.highSources).contains($0 == .battery ? "-b" : "-c") }) }
}

@main struct EnergyModeTests {
 static func main() throws {
  let fixture = EnergyPMSetFixture(); let controller = fixture.controller()
  let initial = try controller.energyStatus()
  precondition(initial.ac == .high && initial.current == .high && initial.highBattery == true && initial.lowPower.ac == false)
  _ = try controller.setEnabled(false)
  precondition(fixture.writes.isEmpty && fixture.modes["-c"] == 2)
  _ = try controller.setEnabled(true, source: .ac)
  precondition(fixture.writes == [["-c", "powermode", "1"]])
  _ = try controller.restore()
  precondition(fixture.modes["-c"] == 2)
  _ = try controller.setMode(.high, source: .battery)
  precondition(fixture.modes["-b"] == 2)
  _ = try controller.restore()
  precondition(fixture.modes == ["-b": 0, "-c": 2])
  fixture.highSources.remove("-b")
  let count = fixture.writes.count
  do { _ = try controller.setMode(.high); preconditionFailure("mixed high-power capability accepted") } catch {}
  precondition(fixture.writes.count == count)
  _ = try controller.setMode(.low)
  precondition(Array(fixture.writes.suffix(2)) == [["-b", "lowpowermode", "1"], ["-c", "powermode", "1"]])
  _ = try controller.restore()
  precondition(fixture.modes == ["-b": 0, "-c": 2])
  fixture.highSources.insert("-b")
  fixture.reject = { $0 == ["-c", "powermode", "1"] }
  do { _ = try controller.setMode(.low); preconditionFailure("partial write failure ignored") } catch {}
  precondition(fixture.modes == ["-b": 0, "-c": 2])
  fixture.reject = nil
  _ = try controller.setMode(.low, source: .ac)
  fixture.reject = { $0 == ["-c", "powermode", "0"] }
  do { _ = try controller.setMode(.automatic, source: .ac); preconditionFailure("repeat operation failure ignored") } catch {}
  precondition(fixture.modes["-c"] == 1, "failed new request must preserve the preceding accepted mode")
  fixture.reject = nil
  _ = try controller.restore()
  precondition(fixture.modes["-c"] == 2, "explicit restore still recovers the original session mode")
  _ = try controller.setMode(.automatic, source: .ac)
  fixture.modes["-c"] = 1
  let priorRestore = fixture.writes.count
  _ = try controller.restore()
  precondition(fixture.modes["-c"] == 1 && fixture.writes.count == priorRestore)
  let sourceDependent = EnergyPMSetFixture()
  sourceDependent.highSources = []
  sourceDependent.highCapabilities = ["-c"]
  let sourceDependentController = sourceDependent.controller()
  let contextual = try sourceDependentController.energyStatus()
  precondition(contextual.ac == .high && contextual.highAC == true && contextual.highBattery == false)
  _ = try sourceDependentController.setMode(.automatic, source: .ac)
  precondition(sourceDependent.writes.last == ["-c", "powermode", "0"])
  _ = try sourceDependentController.restore()
  precondition(sourceDependent.modes["-c"] == 2)
  let unknownCapability = PowerModeController(runner: sourceDependent.run, authorizeWrites: { true }, highPowerAvailability: { _ in nil })
  sourceDependent.highSources = ["-b", "-c"]
  let unknownStatus = try unknownCapability.energyStatus()
  precondition(unknownStatus.ac == .high && unknownStatus.highAC == nil)
  let unknownWrites = sourceDependent.writes.count
  do { _ = try unknownCapability.setMode(.high, source: .battery); preconditionFailure("unknown capability accepted") } catch {}
  precondition(sourceDependent.writes.count == unknownWrites)
  let switchingOff = EnergyPMSetFixture()
  switchingOff.modes = ["-b": 1, "-c": 2]
  let offController = switchingOff.controller()
  _ = try offController.setHighPowerEnabled(false)
  precondition(switchingOff.modes == ["-b": 1, "-c": 0])
  precondition(switchingOff.writes == [["-c", "powermode", "0"]])
  _ = try offController.restore()
  precondition(switchingOff.modes == ["-b": 1, "-c": 2])
  _ = try offController.setHighPowerEnabled(true)
  precondition(switchingOff.modes == ["-b": 2, "-c": 2])
  let ambiguous = EnergyPMSetFixture()
  ambiguous.failAfterWrite = true
  ambiguous.reject = { $0 == ["-c", "powermode", "1"] }
  let ambiguousController = ambiguous.controller()
  do { _ = try ambiguousController.setMode(.low); preconditionFailure("ambiguous response ignored") } catch {}
  precondition(ambiguous.modes == ["-b": 0, "-c": 2])
  let cleanup = EnergyPMSetFixture()
  cleanup.reject = { $0 == ["-c", "powermode", "1"] || $0 == ["-b", "powermode", "0"] }
  let cleanupController = cleanup.controller()
  do { _ = try cleanupController.setMode(.low); preconditionFailure("cleanup failure ignored") } catch {}
  precondition(cleanup.modes["-b"] == 1)
  cleanup.reject = nil
  _ = try cleanupController.restore()
  precondition(cleanup.modes == ["-b": 0, "-c": 2])
  fixture.liveFails = true
  let unavailableLive = try controller.energyStatus()
  precondition(unavailableLive.current == nil && unavailableLive.ac == .low)
  for output in ["AC Power:\n powermode 3\n", "AC Power:\n powermode 0\n lowpowermode 0\n"] {
   do { _ = try PowerModeController.parseEnergyCustom(output); preconditionFailure("malformed mode accepted") } catch {}
  }
  for mode in EnergyMode.allCases {
   for source: PowerSource? in [nil, .battery, .ac] {
    let request = EnergyModeRequest(mode: mode, source: source)
    precondition(EnergyModeRequest(command: request.command)?.mode == mode)
    precondition(EnergyModeRequest(command: request.command)?.source == source)
   }
  }
  precondition(EnergyModeRequest(command: "energyModeACHigh trailing") == nil)
  let wire = try EnergyModeStatus(helperResponse: initial.description)
  precondition(wire.ac == .high && wire.current == .high && wire.highAC == true)
  let denied = PowerModeController(runner: fixture.run, authorizeWrites: { false })
  let priorDenied = fixture.writes.count
  do { _ = try denied.setMode(.high); preconditionFailure("unauthorized write accepted") } catch {}
  precondition(fixture.writes.count == priorDenied)
  print("PASS tri-state mode parsing, legacy compatibility, complete original-mode recovery, mixed capability preflight, partial rollback, peer changes, live unknown and fixed command routing; no pmset executed")
 }
}
