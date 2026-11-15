import Foundation
import ChargeCore
import ChargeHardware

@MainActor func hardwarePercentageSourceChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let historyURL = Configuration.directory.appendingPathComponent("history.json")
 let oldHistory = try? Data(contentsOf:historyURL)
 defer {
  if let oldHistory { try! oldHistory.write(to:historyURL) }
  else if FileManager.default.fileExists(atPath:historyURL.path) { try! FileManager.default.removeItem(at:historyURL) }
 }
 let archiveURL = Configuration.directory.appendingPathComponent("brsc-fixture.sqlite3")
 defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath:archiveURL.path + suffix) } }
 let saved = try Configuration.load()
 defer { try? saved.save() }
 let suite = "org.opencharge.hardware-source-fixture." + UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 var config = Configuration(); config.hardwareEnabled = false; config.notifications = false
 config.systemActionsEnabled = false; config.historyEnabled = true
 config.policy.limit = 80; config.policy.useHardwarePercent = true; try config.save()
 let properties: [String: Any] = ["CurrentCapacity":90, "MaxCapacity":100, "ExternalConnected":true,
  "IsCharging":true, "AppleRawMaxCapacity":5000, "AppleRawCurrentCapacity":3000, "Temperature":3000]
 let registry = try BatteryReader.decode(properties:properties,source:nil)
 let selected = try BatteryTelemetryReader.read(base:{ registry },smc:{ SMCTelemetryReading(hardwarePercent:70) })
 let model = ChargeModel(automaticRead:nil,dashboardDefaults:defaults,observeLid:false,readBattery:{ selected },statisticArchive:BatteryStatisticArchive(url:archiveURL),
  startupRecoveryRequest:{ _ in preconditionFailure("fixture must not request helper") })
 precondition(model.reading?.percent == 90 && model.reading?.hardwarePercent == 70 && model.reading?.rawCapacityPercent == 60)
 precondition(model.decision.action == .allowCharge, "hardware mode must use BRSC70 below80, independently of OS90")
 precondition(model.history.last?.hardwarePercent == 70 && model.history.last?.hardwarePercentageSource == .smc, "accepted model persists BRSC provenance")
 precondition(MenuBarLabel(display:"hardware",reading:selected).text == "70%")
 model.config.policy.useHardwarePercent = false; model.refresh()
 precondition(model.decision.action == .inhibitCharge, "OS mode must use90 above80")
 try model.prepareForQuit(request:{ _ in preconditionFailure("read-only fixture must not request helper") })
 print("production BRSC70/OS90/raw-ratio60 policy selection, menu label and recent-history source passed; injected readings, no actuators")
}
