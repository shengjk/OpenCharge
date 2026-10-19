import Foundation

public enum ChargeMode: String, Codable, CaseIterable, Sendable { case automatic, paused, discharge, topUp, calibration }
public enum ChargeAction: String, Codable, Sendable { case allowCharge, inhibitCharge, forceDischarge, restore }
public enum CalibrationStage: String, Codable, Sendable { case idle, filling, holding, draining, refilling, returning, complete }
public enum ThermalBehavior: String, Codable, CaseIterable, Sendable { case fiveMinuteWindows, degreeHysteresis }
public struct ChargePolicy: Codable, Equatable, Sendable {
 public var limit = 80.0
 public var sailing = true
 public var sailingWidth = 5.0
 public var automaticDischarge = false
 public var heatProtection = true
 public var maxTemperature = 35.0
 public var thermalBehavior: ThermalBehavior? = nil
 public var protectDuringCalibration: Bool? = nil
 public var lowPowerMode: Bool? = nil
 public var useHardwarePercent: Bool? = nil
 public var mode: ChargeMode = .automatic
 public var reserve = 15.0
 public var keepAwakeUntilLimit: Bool? = nil
 public var stopInSleep = false
 public var stopOnQuit = false
 public var clamshellDischarge = false
 public var departure: Date? = nil
 public var departureTarget = 100.0
 public var estimatedPercentPerHour = 30.0
 public init() {}
 public mutating func normalize() {
  limit = min(100, max(20, limit.isFinite ? limit : 80))
  sailingWidth = min(20, max(1, sailingWidth.isFinite ? sailingWidth : 5))
  reserve = min(40, max(10, reserve.isFinite ? reserve : 15))
  maxTemperature = min(45, max(25, maxTemperature.isFinite ? maxTemperature : 35))
  departureTarget = min(100, max(20, departureTarget.isFinite ? departureTarget : 100))
  estimatedPercentPerHour = min(100, max(5, estimatedPercentPerHour.isFinite ? estimatedPercentPerHour : 30))
 }
}
public struct ChargeSample: Codable, Sendable {
 public var date: Date; public var percent: Double; public var temperature: Double?; public var connected: Bool; public var lidClosed: Bool
 public var physicalAdapterConnected: Bool?
 public var ownAdapterInhibited: Bool
 public init(date: Date = Date(), percent: Double, temperature: Double? = nil, connected: Bool = true, lidClosed: Bool = false, physicalAdapterConnected: Bool? = nil, ownAdapterInhibited: Bool = false) { self.physicalAdapterConnected = physicalAdapterConnected; self.ownAdapterInhibited = ownAdapterInhibited; self.date = date; self.percent = percent; self.temperature = temperature; self.connected = connected; self.lidClosed = lidClosed }
}
public struct Decision: Codable, Sendable {
 public var sailingHold: Bool? = nil
 public var action: ChargeAction; public var reason: String; public var effectiveLimit: Double
 public init(_ action: ChargeAction, _ reason: String, limit: Double) { self.action = action; self.reason = reason; effectiveLimit = limit }
}
public struct CalibrationCheckpoint: Codable, Equatable, Sendable {
 public var stage: CalibrationStage
 public var holdingSince: Date?
 public init(stage: CalibrationStage, holdingSince: Date? = nil) { self.stage = stage; self.holdingSince = holdingSince }
}
public struct ChargeEngine: Sendable {
 public private(set) var calibration: CalibrationStage = .idle
 public private(set) var holdingSince: Date?
 public private(set) var completedMode: ChargeMode?
 private var nextThermalCheck: Date?
 private var previousThermalBehavior: ThermalBehavior?
 private var heatPaused = false
 private var sailingPaused = true
 private var previousMode: ChargeMode = .automatic
 public init(checkpoint: CalibrationCheckpoint? = nil) { calibration = checkpoint?.stage ?? .idle; holdingSince = checkpoint?.holdingSince }
 public var checkpoint: CalibrationCheckpoint { CalibrationCheckpoint(stage: calibration, holdingSince: holdingSince) }
 public mutating func decide(_ sample: ChargeSample, policy raw: ChargePolicy) -> Decision {
  completedMode = nil
  var p = raw; p.normalize()
  let limit = p.limit
  func result(_ a: ChargeAction, _ r: String, _ l: Double? = nil, sailingHold: Bool = false) -> Decision { var value = Decision(a, r, limit: l ?? limit); value.sailingHold = sailingHold; return value }
  if p.mode != .calibration { calibration = .idle; holdingSince = nil }
  if p.mode != previousMode { sailingPaused = true; previousMode = p.mode }
  guard sample.percent.isFinite, (0...100).contains(sample.percent) else { return result(.restore, "无效电池读数，恢复系统控制") }
  // Cutting adapter input can make the OS report battery power. An acknowledged own cut
  // must not be mistaken for unplugging and immediately undone. Prefer raw presence when available.
  let adapterPresent = sample.physicalAdapterConnected ?? (sample.connected || sample.ownAdapterInhibited)
  guard adapterPresent else {
   if p.mode == .topUp { completedMode = .topUp }
   return result(.restore, "未连接电源，恢复系统控制")
  }
  let thermal = p.thermalBehavior ?? .fiveMinuteWindows
  if previousThermalBehavior != thermal { heatPaused = false; nextThermalCheck = nil; previousThermalBehavior = thermal }
  // 1.35 release behavior: heat protection cannot prevent charging below 20%.
  let thermalActive = p.heatProtection && sample.percent >= 20 && (p.mode != .calibration || p.protectDuringCalibration == true)
  if thermalActive {
   guard let t = sample.temperature, t.isFinite else { return result(.inhibitCharge, "温度不可用，等待可靠读数") }
   switch thermal {
   case .degreeHysteresis:
    if t >= p.maxTemperature { heatPaused = true }
    if t <= p.maxTemperature - 2 { heatPaused = false }
   case .fiveMinuteWindows:
    if let check = nextThermalCheck {
     if sample.date >= check { heatPaused = t >= p.maxTemperature; nextThermalCheck = sample.date.addingTimeInterval(300) }
    } else if t >= p.maxTemperature { heatPaused = true; nextThermalCheck = sample.date.addingTimeInterval(300) }
   }
   if heatPaused { return result(.inhibitCharge, thermal == .degreeHysteresis ? "热保护：等待降温至阈值以下 2°C" : "热保护：五分钟暂停窗口") }
  } else { heatPaused = false; nextThermalCheck = nil }
  if p.mode == .paused { return result(.inhibitCharge, "已手动暂停充电") }
  let dischargeFloor = p.mode == .calibration ? 10.0 : p.reserve
  if sample.percent <= dischargeFloor && ((p.mode == .calibration && calibration == .draining) || (p.mode != .calibration && (p.mode == .discharge || p.automaticDischarge))) {
   if p.mode == .calibration { calibration = .refilling }
   if p.mode == .discharge { completedMode = .discharge }
   return result(.allowCharge, "低电量保底：停止放电并充电")
  }
  if p.mode == .calibration {
   if calibration == .idle { calibration = .filling }
   switch calibration {
   case .filling:
    if sample.percent >= 100 { calibration = .draining }
    return result(.allowCharge, "校准：充至满电", 100)
   case .holding:
    if sample.date.timeIntervalSince(holdingSince ?? sample.date) >= 3600 { calibration = .returning }
    return result(.allowCharge, "校准：满电保持一小时", 100)
   case .draining:
    if sample.lidClosed && !p.clamshellDischarge { return result(.inhibitCharge, "校准等待开盖") }
    return result(.forceDischarge, "校准：放电至 10%", 10)
   case .refilling:
    if sample.percent >= 100 { calibration = .holding; holdingSince = sample.date }
    return result(.allowCharge, "校准：重新充满电", 100)
   case .returning:
    if sample.percent <= limit { calibration = .complete; return result(.inhibitCharge, "校准完成") }
    if sample.lidClosed && !p.clamshellDischarge { return result(.inhibitCharge, "校准等待开盖") }
    return result(.forceDischarge, "校准：恢复日常上限")
   case .complete:
    return result(sample.percent < limit ? .allowCharge : .inhibitCharge, "校准完成，日常上限控制")
   case .idle: break
   }
  }
  var target = p.mode == .topUp ? 100.0 : limit
  if let departure = p.departure, departure > sample.date {
   let hours = max(0, p.departureTarget - sample.percent) / p.estimatedPercentPerHour + 0.5
   if departure.timeIntervalSince(sample.date) <= hours * 3600 { target = p.departureTarget }
  }
  if p.mode == .discharge || (p.automaticDischarge && sample.percent > target) {
   if sample.percent <= target { if p.mode == .discharge { completedMode = .discharge }; return result(.inhibitCharge, "已放电至目标", target) }
   if sample.lidClosed && !p.clamshellDischarge { return result(.inhibitCharge, "合盖时暂停主动放电", target) }
   return result(.forceDischarge, "主动放电至目标", target)
  }
  if sample.percent >= target { sailingPaused = true; return result(.inhibitCharge, "达到充电上限", target) }
  if sample.percent >= 20 && sailingPaused && p.sailing && p.mode == .automatic && sample.percent > target - p.sailingWidth { return result(.inhibitCharge, "航行模式：电量处于保持区间", target, sailingHold: true) }
  sailingPaused = false
  return result(.allowCharge, target != limit ? "临时目标充电" : "低于目标，允许充电", target)
 }
}

public enum ScheduleAction: String, Codable, CaseIterable { case limit, topUp, pause, discharge, calibrate, automatic, lowPowerOn, lowPowerOff }
public enum RepeatRule: String, Codable, CaseIterable { case once, daily, weekdays, weekly, biweekly, monthly, yearly }
public struct ChargeSchedule: Codable, Identifiable {
 public var anchorDay: Int? = nil
 public var anchorMonth: Int? = nil
 public var anchorHour: Int? = nil
 public var anchorMinute: Int? = nil
 public var anchorSecond: Int? = nil
 public var id = UUID(); public var enabled = true; public var date = Date(); public var action: ScheduleAction = .topUp; public var value = 80.0; public var repeatRule: RepeatRule = .once
 public init() {}
 public mutating func consume(now: Date, policy: inout ChargePolicy, calendar: Calendar = .current, runMissedTasks: Bool = true) -> Bool {
  guard enabled else { return false }
  if anchorDay == nil || !(1...31).contains(anchorDay!) { anchorDay = calendar.component(.day, from: date) }
  if anchorMonth == nil || !(1...12).contains(anchorMonth!) { anchorMonth = calendar.component(.month, from: date) }
  if anchorHour == nil || !(0...23).contains(anchorHour!) { anchorHour = calendar.component(.hour, from: date) }
  if anchorMinute == nil || !(0...59).contains(anchorMinute!) { anchorMinute = calendar.component(.minute, from: date) }
  if anchorSecond == nil || !(0...59).contains(anchorSecond!) { anchorSecond = calendar.component(.second, from: date) }
  func clock(on day: Date) -> Date? {
   let start = calendar.startOfDay(for: day)
   let components = DateComponents(hour: anchorHour, minute: anchorMinute, second: anchorSecond)
   guard let next = calendar.nextDate(after: start.addingTimeInterval(-1), matching: components, matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first), calendar.isDate(next, inSameDayAs: day) else { return nil }
   return next
  }
  func advancing(_ days: Int, from value: Date) -> Date? {
   guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: value)) else { return nil }
   return clock(on: day)
  }
  if repeatRule == .weekdays {
   while calendar.isDateInWeekend(date) { guard let next = advancing(1, from: date) else { enabled = false; return false }; date = next }
  }
  guard date <= now else { return false }
  let shouldExecute = runMissedTasks || now.timeIntervalSince(date) <= 15
  if shouldExecute {
  switch action { case .limit: policy.limit = value; policy.mode = .automatic
   case .topUp: policy.mode = .topUp; case .pause: policy.mode = .paused
   case .discharge: policy.limit = value; policy.mode = .discharge
   case .calibrate: policy.mode = .calibration; case .automatic: policy.mode = .automatic
   case .lowPowerOn: policy.lowPowerMode = true; case .lowPowerOff: policy.lowPowerMode = false }
  policy.normalize()
  }
  if repeatRule == .once { enabled = false; return shouldExecute }
  // Jump near now for long daily/weekly backlogs, retaining the original interval phase.
  // Execute at most once; the loop then resolves the current date and weekend boundary.
  let step: Int? = repeatRule == .daily || repeatRule == .weekdays ? 1 : repeatRule == .weekly ? 7 : repeatRule == .biweekly ? 14 : nil
  if let step, let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day, days >= step {
   if let jump = advancing((days / step) * step, from: date) { date = jump }
  }
  if repeatRule == .weekdays {
   while calendar.isDateInWeekend(date) { guard let next = advancing(1, from: date) else { enabled = false; return shouldExecute }; date = next }
  }
  // Advance from calendar dates rather than elapsed seconds. Only one action on catch-up.
  while date <= now {
   let next: Date?
   switch repeatRule { case .daily, .weekdays: next = advancing(1, from: date)
    case .weekly: next = advancing(7, from: date)
    case .biweekly: next = advancing(14, from: date)
    case .monthly:
     var components = calendar.dateComponents([.year, .month], from: date)
     let day = anchorDay ?? calendar.component(.day, from: date)
     components.day = 1
     var month = calendar.date(from: components)!
     var candidate: Date? = nil
     repeat {
      guard let later = calendar.date(byAdding: .month, value: 1, to: month) else { break }; month = later
      if let days = calendar.range(of: .day, in: .month, for: month), days.contains(day) {
       var c = calendar.dateComponents([.year, .month], from: month); c.day = day; c.hour = 12; candidate = calendar.date(from: c).flatMap { clock(on: $0) }
      }
     } while candidate == nil
     next = candidate
    case .yearly:
     var c = calendar.dateComponents([.year], from: date)
     let day = anchorDay ?? calendar.component(.day, from: date)
     let month = anchorMonth ?? calendar.component(.month, from: date)
     var candidate: Date? = nil
     var year = (c.year ?? calendar.component(.year, from: date)) + 1
     // Match the selected date exactly; leap-day schedules skip non-leap years.
     for _ in 0..<8 {
      c.year = year; c.month = month; c.day = day; c.hour = 12
      if let proposed = calendar.date(from: c), calendar.component(.month, from: proposed) == month, calendar.component(.day, from: proposed) == day { candidate = clock(on: proposed); break }
      year += 1
     }
     next = candidate
    case .once: next = nil }
   guard let n = next, n > date else { enabled = false; break }; date = n
   if repeatRule == .weekdays { while calendar.isDateInWeekend(date) { guard let next = advancing(1, from: date) else { enabled = false; return shouldExecute }; date = next } }
  }
  return shouldExecute
 }
}
public struct ScheduleExecution: Codable, Identifiable {
 public var id = UUID()
 public var scheduleID: UUID
 public var action: ScheduleAction
 public var scheduledAt: Date
 public var executedAt: Date
 public var result: String
 public init(scheduleID: UUID, action: ScheduleAction, scheduledAt: Date, executedAt: Date = Date(), result: String) { self.scheduleID = scheduleID; self.action = action; self.scheduledAt = scheduledAt; self.executedAt = executedAt; self.result = result }
}
public struct Configuration: Codable {
 public var policy = ChargePolicy(); public var schedules: [ChargeSchedule] = []; public var notifications = false; public var hardwareEnabled = false; public var historyEnabled = true
 public var calibrationCheckpoint: CalibrationCheckpoint? = nil
 public var lastCalibration: Date? = nil
 public var scheduleHistory: [ScheduleExecution]? = nil
 public var runMissedTasks: Bool? = nil
 public var systemActionsEnabled: Bool? = nil
 public var magSafeMode: MagSafeMode? = nil
 public var magSafeBlinkDischarge: Bool? = nil
 public var magSafeOffDuringSleep: Bool? = nil
 public init() {}
 public static var directory: URL {
  if let path = ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"], path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
  return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenCharge") }
 public static var url: URL { directory.appendingPathComponent("configuration.json") }
 public static func load() throws -> Self { guard FileManager.default.fileExists(atPath: url.path) else { return Self() }; var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)); value.policy.normalize(); return value }
 public func save() throws { try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true); let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(self).write(to: Self.url, options: .atomic); if ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] == nil { DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.opencharge.configurationChanged"), object: nil) } }
}

public extension ScheduleAction {
 var displayName: String { switch self { case .limit: return "设置充电上限"; case .topUp: return "充至满电"; case .pause: return "暂停充电"; case .discharge: return "放电至目标"; case .calibrate: return "校准电池"; case .automatic: return "恢复自动模式"; case .lowPowerOn: return "开启低电量模式"; case .lowPowerOff: return "关闭低电量模式" } }
}
public extension RepeatRule {
 var displayName: String { switch self { case .once: return "不重复"; case .daily: return "每天"; case .weekdays: return "工作日"; case .weekly: return "每周"; case .biweekly: return "每两周"; case .monthly: return "每月"; case .yearly: return "每年" } }
}
public extension CalibrationStage {
 var displayName: String { switch self { case .idle: return "未启动"; case .filling: return "首次充满"; case .draining: return "放电至10%"; case .refilling: return "再次充满"; case .holding: return "保持满电一小时"; case .returning: return "恢复日常电量"; case .complete: return "已完成" } }
}
public extension ChargeAction {
 var displayName: String { switch self { case .allowCharge: return "允许充电"; case .inhibitCharge: return "暂停充电"; case .forceDischarge: return "主动放电"; case .restore: return "恢复系统控制" } }
}
