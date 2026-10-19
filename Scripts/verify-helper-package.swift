import Foundation
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let plist = app.appendingPathComponent("Contents/Library/LaunchDaemons/org.opencharge.charged.plist")
let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
guard object["Label"] as? String == "org.opencharge.charged",
      object["BundleProgram"] as? String == "Contents/MacOS/charged",
      object["Program"] == nil, object["ProgramArguments"] == nil,
      object["RunAtLoad"] as? Bool == true, object["KeepAlive"] as? Bool == true,
      object["ThrottleInterval"] as? Int == 30,
      FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/charged").path),
      FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/HELPER-SETUP.md").path)
else { fatalError("Incomplete or unbounded embedded helper package") }
print("Verified embedded LaunchDaemon label, relative BundleProgram, executable and setup guide; no service registered")
