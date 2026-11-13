import Foundation
import Combine

enum PowerCalculationMode: Int, CaseIterable, Identifiable {
 case average = 0, instant = 1
 var id: Self { self }
 var interval: TimeInterval { self == .average ? 10 : 2 }
 var title: String {
  switch self {
  case .average: return NSLocalizedString("平均", comment: "")
  case .instant: return NSLocalizedString("即时", comment: "")
  }
 }
}

enum PowerGraphPeriod: Int, CaseIterable, Identifiable {
 case five = 5, fifteen = 15, thirty = 30
 var id: Self { self }
 var title: String { String.localizedStringWithFormat(NSLocalizedString("%lld 分钟", comment: ""), Int64(rawValue)) }
}

@MainActor final class PowerGraphPreferences: ObservableObject {
 static let modeKey = "dashboardPowerMode"
 static let periodKey = "dashboardPowerPeriod"
 private let defaults: UserDefaults?
 private var reloading = false
 @Published var mode: PowerCalculationMode = .average {
  didSet { if !reloading { defaults?.set(mode.rawValue, forKey: Self.modeKey) } }
 }
 @Published var period: PowerGraphPeriod = .fifteen {
  didSet { if !reloading { defaults?.set(period.rawValue, forKey: Self.periodKey) } }
 }
 // No defaults means a deterministic, nonpersistent preview or fixture.
 init(defaults: UserDefaults? = nil) { self.defaults = defaults; reloadAfterReset() }
 func reloadAfterReset() {
  reloading = true; defer { reloading = false }
  mode = (defaults?.object(forKey: Self.modeKey) as? Int).flatMap(PowerCalculationMode.init(rawValue:)) ?? .average
  period = (defaults?.object(forKey: Self.periodKey) as? Int).flatMap(PowerGraphPeriod.init(rawValue:)) ?? .fifteen
 }
}
