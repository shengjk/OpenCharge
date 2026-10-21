import AppIntents
import Foundation
import ChargeCore
import ChargeHardware

// Scripts/build-app.sh extracts these declarations into Metadata.appintents.
struct SetChargeLimitIntent: AppIntent {
 static var title: LocalizedStringResource = "设置 OpenCharge 充电上限"
 static var openAppWhenRun = true
 @Parameter(title: "充电上限", default: 80) var percentage: Int
 func perform() async throws -> some IntentResult {
  guard (20...100).contains(percentage) else { throw HelperError.rejected("充电上限必须在 20–100%") }
  var config = try Configuration.load(); guard config.policy.mode != .calibration else { throw HelperError.rejected("校准期间不能修改上限") }; config.setChargeLimit(Double(percentage)); config.policy.mode = .automatic; try config.save(); return .result()
 }
}
enum AutomationMode: String, AppEnum {
 case automatic, paused, discharge, topUp, calibration
 static var typeDisplayRepresentation: TypeDisplayRepresentation = "充电模式"
 static var caseDisplayRepresentations: [AutomationMode: DisplayRepresentation] = [.automatic: "自动", .paused: "暂停", .discharge: "放电", .topUp: "充满", .calibration: "校准"]
}
struct SetChargeModeIntent: AppIntent {
 static var title: LocalizedStringResource = "设置 OpenCharge 模式"
 static var openAppWhenRun = true
 @Parameter(title: "模式") var mode: AutomationMode
 func perform() async throws -> some IntentResult {
  var config = try Configuration.load(); config.policy.mode = ChargeMode(rawValue: mode.rawValue)!; config.policy.pauseAtCurrent = nil; if mode == .calibration { config.calibrationCheckpoint = nil }; try config.save(); return .result()
 }
}
struct GetBatteryPercentageIntent: AppIntent {
 static var title: LocalizedStringResource = "读取 OpenCharge 电量"
 func perform() async throws -> some IntentResult & ReturnsValue<Double> { let c = try Configuration.load(); return .result(value: try BatteryTelemetryReader.read().controlPercentage(useHardware: c.policy.useHardwarePercent ?? false)) }
}
struct GetBatteryTemperatureIntent: AppIntent {
 static var title: LocalizedStringResource = "读取 OpenCharge 电池温度"
 func perform() async throws -> some IntentResult & ReturnsValue<Double> { guard let temperature = try BatteryTelemetryReader.read().temperature else { throw HelperError.rejected("温度不可用") }; return .result(value: temperature) }
}
struct GetChargeLimitIntent: AppIntent {
 static var title: LocalizedStringResource = "读取 OpenCharge 充电上限"
 func perform() async throws -> some IntentResult & ReturnsValue<Double> { .result(value: try Configuration.load().policy.limit) }
}
struct GetChargeStateIntent: AppIntent {
 static var title: LocalizedStringResource = "读取 OpenCharge 充电状态"
 func perform() async throws -> some IntentResult & ReturnsValue<String> {
  let reading = try BatteryTelemetryReader.read()
  return .result(value: reading.charging ? "charging" : (reading.connected ? "holding" : "discharging"))
 }
}

@MainActor enum PolicyStateRuntime {
 static var provider: (() throws -> PolicyPhase)?
 static func read() throws -> PolicyPhase {
  guard let provider else { throw HelperError.rejected("应用策略状态尚不可读，请先打开 OpenCharge") }
  return try provider()
 }
}
struct GetPolicyStateIntent: AppIntent {
 static var title: LocalizedStringResource = "读取 OpenCharge 应用状态"
 static var description = IntentDescription("读取运行中策略的当前状态；与电源流向不同，不执行控制操作。")
 func perform() async throws -> some IntentResult & ReturnsValue<String> {
  let phase = try await MainActor.run { try PolicyStateRuntime.read() }
  return .result(value: phase.rawValue)
 }
}

struct OpenChargeShortcuts: AppShortcutsProvider {
 static var appShortcuts: [AppShortcut] {
  AppShortcut(intent: SetChargeLimitIntent(), phrases: ["设置 \(.applicationName) 充电上限"], shortTitle: "设置充电上限", systemImageName: "battery.80percent")
  AppShortcut(intent: SetChargeModeIntent(), phrases: ["设置 \(.applicationName) 充电模式"], shortTitle: "设置充电模式", systemImageName: "bolt.circle")
  AppShortcut(intent: GetBatteryPercentageIntent(), phrases: ["读取 \(.applicationName) 电量"], shortTitle: "读取电量", systemImageName: "battery.100percent")
  AppShortcut(intent: GetChargeStateIntent(), phrases: ["读取 \(.applicationName) 充电状态"], shortTitle: "读取充电状态", systemImageName: "info.circle")
  AppShortcut(intent: GetPolicyStateIntent(), phrases: ["读取 \(.applicationName) 应用状态"], shortTitle: "读取应用状态", systemImageName: "app.badge")
 }
}

struct StartChargingIntent: AppIntent {
 static var title: LocalizedStringResource = "OpenCharge 充至满电"
 static var openAppWhenRun = true
 func perform() async throws -> some IntentResult { var c = try Configuration.load(); c.policy.mode = .topUp; try c.save(); return .result() }
}
@MainActor enum PauseIntentTelemetry {
 static var read: () throws -> BatteryReading = { try BatteryTelemetryReader.read() }
}
struct StopChargingIntent: AppIntent {
 static var title: LocalizedStringResource = "OpenCharge 暂停充电"
 static var openAppWhenRun = true
 func perform() async throws -> some IntentResult {
  try await MainActor.run {
   var config = try Configuration.load()
   let percent = try PauseIntentTelemetry.read().controlPercentage(useHardware: config.policy.useHardwarePercent == true)
   try PauseChargeRequest.apply(percent: percent, policy: &config.policy)
   config.calibrationCheckpoint = nil
   try config.save()
  }
  return .result()
 }
}
struct StartDischargeIntent: AppIntent {
 static var title: LocalizedStringResource = "OpenCharge 开始放电"
 static var openAppWhenRun = true
 func perform() async throws -> some IntentResult { var c = try Configuration.load(); c.policy.mode = .discharge; try c.save(); return .result() }
}
struct StartCalibrationIntent: AppIntent {
 static var title: LocalizedStringResource = "OpenCharge 开始校准"
 static var openAppWhenRun = true
 func perform() async throws -> some IntentResult { var c = try Configuration.load(); c.policy.mode = .calibration; c.calibrationCheckpoint = nil; try c.save(); return .result() }
}


enum AutomationLEDColor: String, AppEnum {
 case system, off, green, orange, orangeBlinking
 static var typeDisplayRepresentation: TypeDisplayRepresentation = "MagSafe 灯光"
 static var caseDisplayRepresentations: [AutomationLEDColor: DisplayRepresentation] = [.system: "系统灯光", .off: "熄灭", .green: "绿色", .orange: "橙色", .orangeBlinking: "橙色闪烁"]
}
struct SetMagSafeLEDIntent: AppIntent {
 static var title: LocalizedStringResource = "设置 OpenCharge MagSafe 灯光"
 static var openAppWhenRun = true
 @Parameter(title: "灯光", default: .system) var color: AutomationLEDColor
 func perform() async throws -> some IntentResult {
  var config = try Configuration.load()
  guard let mode = MagSafeMode(rawValue: color.rawValue) else { throw HelperError.rejected("无效灯光颜色") }
  config.magSafeMode = mode; try config.save(); return .result(dialog: "已保存灯光设置，请在 OpenCharge 查看应用结果。")
 }
}
