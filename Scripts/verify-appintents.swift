import Foundation
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = app.appendingPathComponent("Contents/Resources/Metadata.appintents")
let data = try Data(contentsOf: directory.appendingPathComponent("extract.actionsdata"))
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let actions = root["actions"] as! [String: Any]
let expected = ["SetChargeLimitIntent", "SetChargeModeIntent", "GetBatteryPercentageIntent", "GetBatteryTemperatureIntent", "GetChargeLimitIntent", "GetChargeStateIntent", "GetPolicyStateIntent", "StartChargingIntent", "StopChargingIntent", "StartDischargeIntent", "StartCalibrationIntent", "SetMagSafeLEDIntent", "EnableLowPowerModeIntent", "DisableLowPowerModeIntent", "EnableHighPowerModeIntent", "DisableHighPowerModeIntent"]
for action in expected {
 guard let value = actions[action] as? [String: Any], value["isDiscoverable"] as? Bool == true else {
  fputs("Missing discoverable App Intent: \(action)\n", stderr); exit(1)
 }
}
guard let shortcuts = root["autoShortcuts"] as? [[String: Any]], shortcuts.count == 9,
      let provider = root["autoShortcutProviderMangledName"] as? String, !provider.isEmpty,
      let limit = actions["SetChargeLimitIntent"] as? [String: Any],
      let limitParameters = limit["parameters"] as? [[String: Any]], limitParameters.first?["name"] as? String == "percentage",
      let mode = actions["SetChargeModeIntent"] as? [String: Any],
      let modeParameters = mode["parameters"] as? [[String: Any]], modeParameters.first?["name"] as? String == "mode",
      let led = actions["SetMagSafeLEDIntent"] as? [String: Any],
      let ledParameters = led["parameters"] as? [[String: Any]], ledParameters.first?["name"] as? String == "color" else {
 fputs("App Shortcuts provider or parameter metadata is incomplete\n", stderr); exit(1)
}
for name in ["EnableLowPowerModeIntent", "DisableLowPowerModeIntent", "EnableHighPowerModeIntent", "DisableHighPowerModeIntent"] {
 guard let action = actions[name] as? [String:Any],
       let parameters = action["parameters"] as? [[String:Any]], parameters.isEmpty else {
  fputs("Power-mode Shortcut parameters differ from the fixed action contract\n", stderr); exit(1)
 }
}
let expectedShortcuts: Set<String> = ["SetChargeLimitIntent", "SetChargeModeIntent", "GetBatteryPercentageIntent", "GetChargeStateIntent", "GetPolicyStateIntent", "EnableLowPowerModeIntent", "DisableLowPowerModeIntent", "EnableHighPowerModeIntent", "DisableHighPowerModeIntent"]
guard Set(shortcuts.compactMap { $0["actionIdentifier"] as? String }) == expectedShortcuts else {
 fputs("App Shortcuts action identities differ from the declared catalog\n", stderr); exit(1)
}
let version = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("version.json")))
func commandOutput(_ path: String, _ arguments: [String]) throws -> String {
 let process = Process(), pipe = Pipe()
 process.executableURL = URL(fileURLWithPath:path); process.arguments = arguments; process.standardOutput = pipe
 try process.run()
 let output = String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
 process.waitUntilExit()
 guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
 return output
}
let binary = app.appendingPathComponent("Contents/MacOS/OpenCharge").path
let architectures = try commandOutput("/usr/bin/lipo", ["-archs",binary]).split(whereSeparator: \.isWhitespace)
let loads = try commandOutput("/usr/bin/otool", ["-arch","all","-l",binary])
for name in ["AppIntents", "Charts", "Accessibility"] {
 let frameworkLoads = loads.components(separatedBy: "Load command ").filter { $0.contains("/" + name + ".framework/") }
 guard !architectures.isEmpty, frameworkLoads.count == architectures.count,
       frameworkLoads.allSatisfy({ $0.contains("LC_LOAD_WEAK_DYLIB") }) else {
  fputs("\(name) framework must load weakly in every architecture\n", stderr); exit(1)
 }
 print("Verified weak \(name) framework loading in \(frameworkLoads.count) architecture slice(s)")
}
print("Verified \(expected.count) discoverable intent declarations, 9 App Shortcuts and setter parameters; metadata version \(version)")
print("Metadata validation does not establish runtime indexing by Shortcuts.")
