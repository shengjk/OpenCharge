import AppIntents
import ChargeCore
import ChargeHardware
import Foundation

@MainActor func powerModeIntentChecks() async throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 let originalPerform = PowerModeIntentRuntime.perform
 let suite = "org.opencharge.power-intent."+UUID().uuidString
 let defaults = UserDefaults(suiteName: suite)!
 defer {
  try? original.save(); PolicyStateRuntime.provider = originalProvider
  PowerModeIntentRuntime.perform = originalPerform; defaults.removePersistentDomain(forName: suite)
 }
 var configuration = Configuration()
 configuration.hardwareEnabled = false; configuration.historyEnabled = false; configuration.systemActionsEnabled = true
 try configuration.save()
 let model = ChargeModel(automaticRead: nil, dashboardDefaults: defaults, observeLid: false,
  readBattery: { BatteryReading(percent: 60, connected: true, charging: false) })
 var battery = 0, ac = 0, highSupported = true
 var writes: [[String]] = [], requests: [String] = []
 let controller = PowerModeController(runner: { args, _ in
  if args == ["-g", "custom"] { return "Battery Power:\n powermode \(battery)\nAC Power:\n powermode \(ac)\n" }
  if args == ["-g", "live"] { return "Currently in use:\n powermode \(ac)\n" }
  precondition(args.count == 3 && args[1] == "powermode")
  writes.append(args)
  if args[0] == "-b" { battery = Int(args[2])! } else { ac = Int(args[2])! }
  return ""
 }, authorizeWrites: { true }, highPowerAvailability: { _ in highSupported })
 var revokeAfterRead = false
 var changeChargeLimitAfterRead = false
 var corruptReply = false
 func request(_ command: String) throws -> String {
  precondition(HelperClient.supportedActions.contains(command))
  requests.append(command)
  let response: String
  switch command {
  case "lowPowerStatus": response = try controller.status().description
  case "energyModeStatus": response = try controller.energyStatus().description
  case "lowPowerOn", "lowPowerOff": response = try controller.setEnabled(command == "lowPowerOn").description
  case "highPowerOn", "highPowerOff": response = try controller.setHighPowerEnabled(command == "highPowerOn").description
  default: preconditionFailure("unexpected route")
  }
  if command.hasSuffix("Status") {
   if revokeAfterRead {
    var latest = try Configuration.load(); latest.systemActionsEnabled = false; try latest.save()
   }
   if changeChargeLimitAfterRead {
    var latest = try Configuration.load(); latest.setChargeLimit(63); try latest.save()
   }
  }
  return corruptReply && command == "lowPowerOn" ? "battery=0 ac=0" : response
 }
 PowerModeIntentRuntime.perform = { try model.performPowerModeShortcut($0, request: request) }
 func run(_ action: PowerModeShortcutAction) async throws {
  switch action {
  case .enableLow: _ = try await EnableLowPowerModeIntent().perform()
  case .disableLow: _ = try await DisableLowPowerModeIntent().perform()
  case .enableHigh: _ = try await EnableHighPowerModeIntent().perform()
  case .disableHigh: _ = try await DisableHighPowerModeIntent().perform()
  }
 }
 let configurationBytes = try Data(contentsOf: Configuration.url)
 for (action, expected) in [(PowerModeShortcutAction.enableLow, 1), (.disableLow, 0), (.enableHigh, 2), (.disableHigh, 0)] {
  requests = []
  try await run(action)
  precondition(battery == expected && ac == expected)
  precondition(requests == [action.usesLowPowerInterface ? "lowPowerStatus" : "energyModeStatus", action.rawValue])
  let savedBytes = try Data(contentsOf: Configuration.url)
  precondition(savedBytes == configurationBytes)
 }
 battery = 2; ac = 0; writes = []
 try await run(.disableLow)
 precondition(battery == 2 && ac == 0 && writes.isEmpty)
 battery = 1; ac = 2; writes = []
 try await run(.disableHigh)
 precondition(battery == 1 && ac == 0 && writes == [["-c", "powermode", "0"]])
 highSupported = false; battery = 0; ac = 0; writes = []; requests = []
 do { try await run(.enableHigh); preconditionFailure("unsupported High Power mode succeeded") } catch {}
 precondition(writes.isEmpty && requests == ["energyModeStatus"])
 highSupported = true
 model.config.systemActionsEnabled = false; requests = []
 do { try await run(.enableLow); preconditionFailure("in-memory opt-out ignored") } catch {}
 precondition(requests.isEmpty)
 model.config.systemActionsEnabled = true
 configuration.systemActionsEnabled = false; try configuration.save(); requests = []
 do { try await run(.enableLow); preconditionFailure("persisted opt-out ignored") } catch {}
 precondition(requests.isEmpty)
 configuration.systemActionsEnabled = true; try configuration.save()
 revokeAfterRead = true; writes = []; requests = []
 do { try await run(.enableLow); preconditionFailure("revoked permission ignored") } catch {}
 precondition(writes.isEmpty && requests == ["lowPowerStatus"])
 revokeAfterRead = false; try configuration.save()
 corruptReply = true
 do { try await run(.enableLow); preconditionFailure("mismatched readback returned success") } catch {}
 corruptReply = false
 changeChargeLimitAfterRead = true
 try await run(.enableLow)
 let latestConfiguration = try Configuration.load()
 precondition(latestConfiguration.policy.limit == 63)
 changeChargeLimitAfterRead = false
 try model.prepareForQuit(request: { _ in preconditionFailure("no charge/helper cleanup required") })
 requests = []
 do { try await run(.disableLow); preconditionFailure("quit lifecycle ignored") } catch {}
 precondition(requests.isEmpty)
 print("PASS four actual power-mode Intent performers, shared backend commands, reciprocal-mode preservation, fresh permission/revocation, readback, charge-config isolation and quit gating; injected IPC only")
}
