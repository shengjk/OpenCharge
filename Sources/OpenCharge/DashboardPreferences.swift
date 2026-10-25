import SwiftUI
import AppKit
import ChargeCore
import ChargeHardware

@MainActor final class DashboardPreferences: ObservableObject {
 private let defaults: UserDefaults
 var changed: (() -> Void)?
 @Published var showOnStartup: Bool { didSet { defaults.set(showOnStartup, forKey: "dashboardShowOnStartup"); changed?() } }
 @Published var backgroundUpdates: Bool { didSet { defaults.set(backgroundUpdates, forKey: "dashboardBackgroundUpdates"); changed?() } }
 @Published var layout: DashboardLayout { didSet {
  if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: "dashboardLayout") }; changed?()
 } }
 init(defaults: UserDefaults = .standard) {
  self.defaults = defaults
  showOnStartup = defaults.object(forKey: "dashboardShowOnStartup") as? Bool ?? true
  backgroundUpdates = defaults.object(forKey: "dashboardBackgroundUpdates") as? Bool ?? false
  if let data = defaults.data(forKey: "dashboardLayout"), data.count <= 16_384,
     let saved = try? JSONDecoder().decode(DashboardLayout.self, from: data) {
   layout = DashboardLayout(widgets: saved.widgets, specifications: saved.specifications)
  } else { layout = DashboardLayout() }
 }
}
@MainActor final class DashboardPresentation: ObservableObject {
 @Published private(set) var reading: BatteryReading?
 @Published private(set) var decision = Decision(.restore, NSLocalizedString("正在读取电池…", comment: ""), limit: 80)
 @Published private(set) var helperStatus = NSLocalizedString("监测模式", comment: "")
 @Published private(set) var limit: Double = 80
 @Published private(set) var history: [HistoryPoint] = []
 @Published var paused = true
 @Published var focused = false
 var title: String { reading.map { "\(Int($0.percent))%" } ?? "—" }
 var watts: Double? { guard let reading, let current = reading.currentMA, let voltage = reading.voltageMV else { return nil }; return current * voltage / 1_000_000 }
 var powerAverages: [Double: WeightedPowerAverage] {
  let points = history.map { PowerSample(date: $0.date, watts: $0.systemWatts) }
  var result: [Double: WeightedPowerAverage] = [:]
  for minutes in [5.0, 15, 30] { result[minutes] = TelemetryMath.weightedAverage(samples: points, endingAt: reading?.date ?? Date(), windowMinutes: minutes) }
  return result
 }
 func capture(_ model: ChargeModel) {
  reading = model.reading; decision = model.decision; helperStatus = model.helperStatus
  limit = model.config.policy.limit; history = Array(model.history.suffix(120))
 }
 func value(_ specification: DashboardSpecification) -> String { BatterySpecificationFormatter.value(specification, reading: reading) }
}
enum BatterySpecificationFormatter {
 static func value(_ specification: DashboardSpecification, reading: BatteryReading?) -> String {
  switch specification {
  case .hardwarePercent: return reading?.hardwarePercent.map { String(format: "%.1f%%", $0) } ?? "—"
  case .health: return reading?.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—"
  case .condition: return reading?.condition ?? "—"
  case .fullCapacity: return reading?.fullCapacityMAH.map { String(format: "%.0f mAh", $0) } ?? "—"
  case .designCapacity: return reading?.designCapacityMAH.map { String(format: "%.0f mAh", $0) } ?? "—"
  case .timeToFull: return reading?.timeToFullMinutes.map { String.localizedStringWithFormat(NSLocalizedString("%lld 分钟", comment: ""), Int64(Int($0))) } ?? "—"
  case .timeToEmpty: return reading?.timeToEmptyMinutes.map { String.localizedStringWithFormat(NSLocalizedString("%lld 分钟", comment: ""), Int64(Int($0))) } ?? "—"
  case .voltage: return reading?.voltageMV.map { String(format: "%.2f V", $0 / 1000) } ?? "—"
  case .current: return reading?.currentMA.map { String(format: "%+.0f mA", $0) } ?? "—"
  }
 }
}

// An actual NSWindow's key state, rather than app activity, distinguishes the
// dashboard from an active menu-bar popover or another application window.
struct DashboardWindowObserver: NSViewRepresentable {
 let model: ChargeModel
 func makeNSView(context: Context) -> DashboardWindowView { let view = DashboardWindowView(); view.model = model; return view }
 func updateNSView(_ view: DashboardWindowView, context: Context) { view.model = model }
}
@MainActor final class DashboardWindowView: NSView {
 weak var model: ChargeModel?
 var popover: PopoverConsumer?
 private var tokens: [NSObjectProtocol] = []
 override func viewDidMoveToWindow() {
  super.viewDidMoveToWindow()
  for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens.removeAll()
  guard let window else { return }
  if let popover { model?.setPopoverVisible(window.isKeyWindow && window.isVisible, consumer: popover) } else { model?.attachDashboardWindow(window) }
  for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
   tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] note in
    MainActor.assumeIsolated {
     let focused = note.name != NSWindow.willCloseNotification && window?.isKeyWindow == true && window?.isMiniaturized == false
     if let popover = self?.popover { self?.model?.setPopoverVisible(focused, consumer: popover) } else { self?.model?.setDashboardFocused(focused) }
    }
   })
  }
 }
 deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

struct PopoverWindowObserver: NSViewRepresentable {
 let model: ChargeModel
 var consumer: PopoverConsumer = .preview
 func makeNSView(context: Context) -> DashboardWindowView { let view = DashboardWindowView(); view.model = model; view.popover = consumer; return view }
 func updateNSView(_ view: DashboardWindowView, context: Context) { view.model = model; view.popover = consumer }
}
