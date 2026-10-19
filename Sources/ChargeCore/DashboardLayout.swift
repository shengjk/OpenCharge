import Foundation

public enum DashboardWidget: String, Codable, CaseIterable, Identifiable {
 case battery, metrics, profiles, powerFlow, specifications, adapter, energyApps, trend
 public var id: Self { self }
 public var title: String { switch self {
 case .battery: return "当前电量"; case .metrics: return "温度、功率与循环"; case .profiles: return "快速配置"
 case .powerFlow: return "能量流向"; case .specifications: return "电池规格"; case .adapter: return "适配器与功耗"
 case .energyApps: return "高耗能应用"; case .trend: return "最近趋势"
 } }
}
public enum DashboardSpecification: String, Codable, CaseIterable, Identifiable {
 case hardwarePercent, health, condition, fullCapacity, designCapacity, timeToFull, timeToEmpty, voltage, current
 public var id: Self { self }
 public var title: String { switch self {
 case .hardwarePercent: return "硬件电量"; case .health: return "容量健康比例"; case .condition: return "电池状况"
 case .fullCapacity: return "满充容量"; case .designCapacity: return "设计容量"; case .timeToFull: return "系统预计充满"
 case .timeToEmpty: return "系统预计续航"; case .voltage: return "电池电压"; case .current: return "电池电流"
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
