// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OpenCharge", platforms: [.macOS(.v13)], products: [
 .executable(name: "OpenCharge", targets: ["OpenCharge"]),
 .executable(name: "chargectl", targets: ["chargectl"]),
 .executable(name: "charged", targets: ["charged"])
], targets: [
 .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip", checksum: "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"),
 .target(name: "ChargeCore"),
 .target(name: "ApplePowerConstants", publicHeadersPath: "include"),
 .target(name: "ChargeHardware", dependencies: ["ApplePowerConstants"], linkerSettings: [.linkedFramework("IOKit")]),
 .executableTarget(name: "OpenCharge", dependencies: ["ChargeCore", "ChargeHardware", "ApplePowerConstants", "Sparkle"],
  linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "AppIntents", "-Xlinker", "-weak_framework", "-Xlinker", "Charts", "-Xlinker", "-weak_framework", "-Xlinker", "Accessibility"])]),
 .executableTarget(name: "chargectl", dependencies: ["ChargeCore", "ChargeHardware"]),
 .executableTarget(name: "charged", dependencies: ["ChargeCore", "ChargeHardware"]),
 .testTarget(name: "ChargeCoreTests", dependencies: ["ChargeCore"])
])
