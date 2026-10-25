import Foundation
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = app.appendingPathComponent("Contents/Resources/Metadata.appintents")
let data = try Data(contentsOf: directory.appendingPathComponent("extract.actionsdata"))
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let actions = root["actions"] as! [String: Any]
let expected = ["SetChargeLimitIntent", "SetChargeModeIntent", "GetBatteryPercentageIntent", "GetBatteryTemperatureIntent", "GetChargeLimitIntent", "GetChargeStateIntent", "GetPolicyStateIntent", "StartChargingIntent", "StopChargingIntent", "StartDischargeIntent", "StartCalibrationIntent", "SetMagSafeLEDIntent"]
for action in expected {
 guard let value = actions[action] as? [String: Any], value["isDiscoverable"] as? Bool == true else {
  fputs("Missing discoverable App Intent: \(action)\n", stderr); exit(1)
 }
}
guard let shortcuts = root["autoShortcuts"] as? [[String: Any]], shortcuts.count == 5,
      let provider = root["autoShortcutProviderMangledName"] as? String, !provider.isEmpty,
      let limit = actions["SetChargeLimitIntent"] as? [String: Any],
      let limitParameters = limit["parameters"] as? [[String: Any]], limitParameters.first?["name"] as? String == "percentage",
      let mode = actions["SetChargeModeIntent"] as? [String: Any],
      let modeParameters = mode["parameters"] as? [[String: Any]], modeParameters.first?["name"] as? String == "mode",
      let led = actions["SetMagSafeLEDIntent"] as? [String: Any],
      let ledParameters = led["parameters"] as? [[String: Any]], ledParameters.first?["name"] as? String == "color" else {
 fputs("App Shortcuts provider or parameter metadata is incomplete\n", stderr); exit(1)
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
let frameworkLoads = loads.components(separatedBy: "Load command ").filter { $0.contains("/AppIntents.framework/") }
guard !architectures.isEmpty, frameworkLoads.count == architectures.count,
      frameworkLoads.allSatisfy({ $0.contains("LC_LOAD_WEAK_DYLIB") }) else {
 fputs("App Intents framework must load weakly in every architecture\n", stderr); exit(1)
}
print("Verified \(expected.count) discoverable intent declarations, 5 App Shortcuts and setter parameters; metadata version \(version)")
print("Verified weak App Intents framework loading in \(frameworkLoads.count) architecture slice(s)")
print("Metadata validation does not establish runtime indexing by Shortcuts.")
