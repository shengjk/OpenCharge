import Foundation

public enum ConfigurationBackupError: LocalizedError {
 case tooLarge, unsupportedVersion, invalidSchedules
 public var errorDescription: String? {
  switch self {
  case .tooLarge: return String(localized:"备份超过 1 MB，无法导入")
  case .unsupportedVersion: return String(localized:"此备份版本尚不受支持")
  case .invalidSchedules: return String(localized:"备份中的任务数量、标识或数值无效")
  }
 }
}

/// Portable settings only. Battery history and machine identifiers are not included.
public struct ConfigurationBackup: Codable {
 public var schemaVersion: Int
 public var createdAt: Date
 public var configuration: Configuration
 public init(configuration: Configuration, createdAt: Date = Date()) {
  schemaVersion = 1; self.createdAt = createdAt; self.configuration = configuration
 }
 public func encoded() throws -> Data {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  return try encoder.encode(self)
 }
 public static func restored(from data: Data) throws -> Configuration {
  guard data.count <= 1_048_576 else { throw ConfigurationBackupError.tooLarge }
  let backup = try JSONDecoder().decode(Self.self, from: data)
  guard backup.schemaVersion == 1 else { throw ConfigurationBackupError.unsupportedVersion }
  var config = backup.configuration
  guard config.schedules.count <= 1000,
        Set(config.schedules.map(\.id)).count == config.schedules.count,
        config.schedules.allSatisfy({ $0.value.isFinite && $0.date.timeIntervalSince1970.isFinite })
  else { throw ConfigurationBackupError.invalidSchedules }
  config.policy.keepAwakeWithLidClosed = false; config.policy.allowDisplaySleep = true; config.policy.lockScreenWhenClosed = false
  config.policy.normalize()
  // An imported file must never resume a hardware operation or an overdue task.
  config.hardwareEnabled = false; config.systemActionsEnabled = false
  config.magSafeMode = .system; config.magSafeOffDuringSleep = false
  config.policy.mode = .automatic; config.policy.departure = nil
  config.calibrationCheckpoint = nil; config.sailingCheckpoint = nil; config.chargeLimitChangeID = nil; config.scheduleHistory = nil
  for index in config.schedules.indices {
   config.schedules[index].enabled = false
   config.schedules[index].value = min(100, max(20, config.schedules[index].value))
  }
  return config
 }
}

public extension ChargeSchedule {
 mutating func resetCalendarAnchor() { anchorDay = nil; anchorMonth = nil; anchorHour = nil; anchorMinute = nil; anchorSecond = nil }
}
public extension Configuration {
 /// Replace editable fields, retaining identity so execution history remains attributable.
 mutating func saveSchedule(_ draft: ChargeSchedule) {
  var value = draft
  value.value = value.value.isFinite ? min(100, max(20, value.value)) : 80
  if let index = schedules.firstIndex(where: { $0.id == draft.id }) {
   let old = schedules[index]
   if old.date == value.date && old.repeatRule == value.repeatRule {
    value.anchorDay = old.anchorDay; value.anchorMonth = old.anchorMonth
    value.anchorHour = old.anchorHour; value.anchorMinute = old.anchorMinute; value.anchorSecond = old.anchorSecond
   } else { value.resetCalendarAnchor() }
   schedules[index] = value
  } else { value.resetCalendarAnchor(); schedules.append(value) }
 }
}
