import Foundation
import ChargeCore
import ChargeHardware

// Shared read providers do not require the App Intents framework.
@MainActor enum PolicyStateRuntime {
 static var provider: (() throws -> PolicyPhase)?
 static func read() throws -> PolicyPhase {
  guard let provider else { throw HelperError.rejected(NSLocalizedString("应用策略状态尚不可读，请先打开 OpenCharge", comment: "")) }
  return try provider()
 }
}

@MainActor enum PauseIntentTelemetry {
 static var read: () throws -> BatteryReading = { try BatteryTelemetryReader.read() }
}

enum PowerModeShortcutAction: String, CaseIterable {
 case enableLow = "lowPowerOn", disableLow = "lowPowerOff"
 case enableHigh = "highPowerOn", disableHigh = "highPowerOff"
 var usesLowPowerInterface: Bool { self == .enableLow || self == .disableLow }
 var enablesMode: Bool { self == .enableLow || self == .enableHigh }
}

@MainActor enum PowerModeIntentRuntime {
 static var perform: (PowerModeShortcutAction) throws -> Void = { _ in
  throw HelperError.rejected(NSLocalizedString("应用策略状态尚不可读，请先打开 OpenCharge", comment: ""))
 }
}
