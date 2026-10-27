import Foundation

public enum SetupUsage: Int, CaseIterable, Codable { case rarely, sometimes, mostly }
public enum SetupTemperatureUnit: String, CaseIterable {
 case celsius, fahrenheit
 public static func preferred(for locale: Locale) -> Self {
  ((locale as NSLocale).object(forKey:.usesMetricSystem) as? Bool ?? true) ? .celsius : .fahrenheit
 }
}
public enum SetupSurveyError: LocalizedError {
 case invalidTemperature, invalidDate
 public var errorDescription: String? {
  switch self {
  case .invalidTemperature: return NSLocalizedString("环境温度须为 15–40°C 或 59–104°F", comment: "")
  case .invalidDate: return NSLocalizedString("无法为设置向导生成有效的任务日期", comment: "")
  }
 }
}
public struct SetupAnswers {
 public var usage: SetupUsage
 public var temperature: Double
 public var unit: SetupTemperatureUnit
 public var regularSwitchOff: Bool
 public var automaticCalibration: Bool
 public init(usage: SetupUsage, temperature: Double, unit: SetupTemperatureUnit, regularSwitchOff: Bool, automaticCalibration: Bool) {
  self.usage = usage; self.temperature = temperature; self.unit = unit
  self.regularSwitchOff = regularSwitchOff; self.automaticCalibration = automaticCalibration
 }
}
/// A data-only plan. Creating or saving this value never enables hardware or system actions.
public struct SetupRecommendation {
 public let limit: Double
 public let sailingWidth: Double
 public let maxTemperature: Double
 public let stopInSleep: Bool
 public let automaticDischarge: Bool
 public let calibrationRepeat: RepeatRule?
 public let firstCalibration: Date?
 public init(answers: SetupAnswers, lidClosed: Bool, now: Date) throws {
  let bounds: ClosedRange<Double> = answers.unit == .celsius ? 15...40 : 59...104
  guard answers.temperature.isFinite, bounds.contains(answers.temperature) else { throw SetupSurveyError.invalidTemperature }
  guard now.timeIntervalSince1970.isFinite else { throw SetupSurveyError.invalidDate }
  limit = [70.0,80.0,90.0][answers.usage.rawValue]
  sailingWidth = answers.usage == .mostly ? 10 : 5
  let celsius = answers.unit == .celsius ? answers.temperature : (answers.temperature - 32) * 5 / 9
  maxTemperature = Double(Float(celsius + 10))
  stopInSleep = answers.regularSwitchOff
  automaticDischarge = answers.regularSwitchOff && !lidClosed
  calibrationRepeat = answers.automaticCalibration && answers.usage != .mostly ? (answers.usage == .rarely ? .biweekly : .monthly) : nil
  let first = now.addingTimeInterval(14 * 86400)
  guard first.timeIntervalSince1970.isFinite, first > now else { throw SetupSurveyError.invalidDate }
  firstCalibration = calibrationRepeat == nil ? nil : first
 }
 public func applying(to original: Configuration, calibrationName: String) -> Configuration {
  var config = original
  config.setChargeLimit(limit)
  config.policy.sailingWidth = sailingWidth
  config.policy.useHardwarePercent = false
  config.policy.heatProtection = true
  config.policy.maxTemperature = maxTemperature
  config.policy.stopInSleep = stopInSleep
  config.policy.automaticDischarge = automaticDischarge
  config.policy.normalize()
  if let rule = calibrationRepeat, let date = firstCalibration {
   let aliases = [calibrationName,"自动校准","Automatic Calibration"].map { $0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() }
   let existing = config.schedules.first { task in
    task.action == .calibrate && (task.id == config.setupCalibrationScheduleID || task.name.map { aliases.contains($0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()) } == true)
   }
   if let existing { config.setupCalibrationScheduleID = existing.id }
   else {
    var task = ChargeSchedule(); task.name = calibrationName; task.action = .calibrate; task.date = date; task.repeatRule = rule
    config.setupCalibrationScheduleID = task.id; config.schedules.append(task)
   }
  }
  return config
 }
}
public extension ChargeSchedule {
 var displayTitle: String {
  if let value = name?.trimmingCharacters(in:.whitespacesAndNewlines), !value.isEmpty { return value }
  return action.displayName
 }
}
public extension ScheduleExecution {
 var displayTitle: String {
  if let value = scheduleName?.trimmingCharacters(in:.whitespacesAndNewlines), !value.isEmpty { return value }
  return action.displayName
 }
}
