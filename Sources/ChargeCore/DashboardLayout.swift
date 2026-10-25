import Foundation

public enum DashboardWidget: String, Codable, CaseIterable, Identifiable {
 case battery, metrics, profiles, powerFlow, specifications, adapter, energyApps, trend
 public var id: Self { self }
 public var title: String { switch self {
 case .battery: return NSLocalizedString("当前电量", comment: ""); case .metrics: return NSLocalizedString("温度、功率与循环", comment: ""); case .profiles: return NSLocalizedString("快速配置", comment: "")
 case .powerFlow: return NSLocalizedString("能量流向", comment: ""); case .specifications: return NSLocalizedString("电池规格", comment: ""); case .adapter: return NSLocalizedString("适配器与功耗", comment: "")
 case .energyApps: return NSLocalizedString("高耗能应用", comment: ""); case .trend: return NSLocalizedString("最近趋势", comment: "")
 } }
}
public enum DashboardSpecification: String, Codable, CaseIterable, Identifiable {
 case hardwarePercent, health, condition, fullCapacity, designCapacity, timeToFull, timeToEmpty, voltage, current
 public var id: Self { self }
 public var title: String { switch self {
 case .hardwarePercent: return NSLocalizedString("硬件电量", comment: ""); case .health: return NSLocalizedString("容量健康比例", comment: ""); case .condition: return NSLocalizedString("电池状况", comment: "")
 case .fullCapacity: return NSLocalizedString("满充容量", comment: ""); case .designCapacity: return NSLocalizedString("设计容量", comment: ""); case .timeToFull: return NSLocalizedString("系统预计充满", comment: "")
 case .timeToEmpty: return NSLocalizedString("系统预计续航", comment: ""); case .voltage: return NSLocalizedString("电池电压", comment: ""); case .current: return NSLocalizedString("电池电流", comment: "")
 } }
}
public struct DashboardLayout: Equatable, Codable {
 public var widgets: [DashboardWidget]
 public var specifications: [DashboardSpecification]
 public init(widgets: [DashboardWidget] = DashboardWidget.allCases, specifications: [DashboardSpecification] = DashboardSpecification.allCases) {
  self.widgets = Self.unique(widgets); self.specifications = Self.unique(specifications)
 }
 public init(widgetIDs: [String], specificationIDs: [String]) {
  self.init(widgets: widgetIDs.compactMap(DashboardWidget.init(rawValue:)), specifications: specificationIDs.compactMap(DashboardSpecification.init(rawValue:)))
 }
 private enum CodingKeys: String, CodingKey { case widgets, specifications }
 public init(from decoder: Decoder) throws {
  let values = try decoder.container(keyedBy: CodingKeys.self)
  let widgetIDs = try values.decodeIfPresent([String].self, forKey: .widgets) ?? DashboardWidget.allCases.map(\.rawValue)
  let specIDs = try values.decodeIfPresent([String].self, forKey: .specifications) ?? DashboardSpecification.allCases.map(\.rawValue)
  self.init(widgetIDs: widgetIDs, specificationIDs: specIDs)
 }
 public mutating func setVisible(_ widget: DashboardWidget, visible: Bool) {
  widgets.removeAll { $0 == widget }; if visible { widgets.append(widget) }
 }
 public mutating func setVisible(_ specification: DashboardSpecification, visible: Bool) {
  specifications.removeAll { $0 == specification }; if visible { specifications.append(specification) }
 }
 public mutating func move(_ widget: DashboardWidget, by offset: Int) {
  guard let index = widgets.firstIndex(of: widget), offset == -1 || offset == 1 else { return }
  let destination = index + offset
  guard widgets.indices.contains(destination) else { return }
  widgets.swapAt(index, destination)
 }
 private static func unique<T: Hashable>(_ values: [T]) -> [T] { var seen = Set<T>(); return values.filter { seen.insert($0).inserted } }
}
public enum DashboardRefreshPolicy {
 public static func shouldUpdate(windowFocused: Bool, backgroundUpdates: Bool) -> Bool { windowFocused || backgroundUpdates }
}
