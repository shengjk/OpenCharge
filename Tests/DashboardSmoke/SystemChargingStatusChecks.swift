import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func systemChargingStatusChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"]?.contains("/.build/dashboard-validation/fixture.") == true)
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = Configuration(); fixture.hardwareEnabled = false; fixture.historyEnabled = false
 try fixture.save()
 let before = try Data(contentsOf: Configuration.url)
 precondition(OptimizedChargingEngagement(true) == .engaged)
 precondition(OptimizedChargingEngagement(false) == .notEngaged)
 precondition(OptimizedChargingEngagement(nil) == .unavailable)
 let sampledAt = Date(timeIntervalSince1970: 1000)
 let dated = BatteryReading(date: sampledAt, percent: 80, connected: true, charging: false, optimizedChargingEngaged: true)
 precondition(OptimizedChargingEngagement(reading: dated, at: sampledAt.addingTimeInterval(30)) == .engaged)
 for date in [sampledAt.addingTimeInterval(31), sampledAt.addingTimeInterval(-1), Date(timeIntervalSince1970: .nan)] {
  precondition(OptimizedChargingEngagement(reading: dated, at: date) == .waitingForFreshReading)
 }
 precondition(OptimizedChargingEngagement(reading: nil, at: sampledAt) == .unavailable)
 for reported: Bool? in [true, false, nil] {
  let reading = BatteryReading(percent: 80, connected: true, charging: false, optimizedChargingEngaged: reported)
  let host = NSHostingView(rootView: SystemChargingStatusView(reading: reading))
  host.frame = NSRect(x: 0, y: 0, width: 640, height: 230); host.layoutSubtreeIfNeeded()
  precondition(host.fittingSize.width > 0 && host.fittingSize.height > 0)
 }
 let absent = NSHostingView(rootView: SystemChargingStatusView(reading: nil))
 absent.frame = NSRect(x: 0, y: 0, width: 640, height: 230); absent.layoutSubtreeIfNeeded()
 let after = try Data(contentsOf: Configuration.url)
 precondition(before == after)
 print("PASS system optimized-charging engaged/not-engaged/unknown/freshness projection and actual readonly view mounts; isolated configuration unchanged, no settings or helper actions")
}
