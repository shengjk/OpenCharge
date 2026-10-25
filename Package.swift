// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OpenCharge", platforms: [.macOS(.v13)], products: [
 .executable(name: "OpenCharge", targets: ["OpenCharge"]),
 .executable(name: "chargectl", targets: ["chargectl"]),
 .executable(name: "charged", targets: ["charged"])
], targets: [
 .target(name: "ChargeCore"),
 .target(name: "ApplePowerConstants", publicHeadersPath: "include"),
 .target(name: "ChargeHardware", dependencies: ["ApplePowerConstants"], linkerSettings: [.linkedFramework("IOKit")]),
 .executableTarget(name: "OpenCharge", dependencies: ["ChargeCore", "ChargeHardware"],
  linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "AppIntents", "-Xlinker", "-weak_framework", "-Xlinker", "Charts"])]),
 .executableTarget(name: "chargectl", dependencies: ["ChargeCore", "ChargeHardware"]),
 .executableTarget(name: "charged", dependencies: ["ChargeCore", "ChargeHardware"]),
 .testTarget(name: "ChargeCoreTests", dependencies: ["ChargeCore"])
])
