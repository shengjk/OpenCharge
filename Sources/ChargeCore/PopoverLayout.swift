import Foundation
public enum PopoverWidget: String, Codable, CaseIterable, Identifiable {
 case specifications, powerFlow, energyApps
 public var id: Self { self }
 public var title: String { switch self { case .specifications: return String(localized:"电池规格"); case .powerFlow: return String(localized:"能量流向"); case .energyApps: return String(localized:"高耗能应用") } }
}
public struct PopoverLayout: Codable, Equatable {
 public var widgets: [PopoverWidget]
 public var specifications: [DashboardSpecification]
 public init(widgets: [PopoverWidget] = [.powerFlow, .energyApps], specifications: [DashboardSpecification] = [.hardwarePercent, .health, .condition]) {
  var seen = Set<PopoverWidget>(); self.widgets = widgets.filter { seen.insert($0).inserted }
  var specs = Set<DashboardSpecification>(); self.specifications = specifications.filter { specs.insert($0).inserted }
 }
 private enum CodingKeys: String, CodingKey { case widgets, specifications }
 public init(from decoder: Decoder) throws {
  let c = try decoder.container(keyedBy: CodingKeys.self)
  let ids = try c.decodeIfPresent([String].self, forKey: .widgets) ?? ["powerFlow", "energyApps"]
  let specs = try c.decodeIfPresent([String].self, forKey: .specifications) ?? ["hardwarePercent", "health", "condition"]
  self.init(widgets: ids.compactMap(PopoverWidget.init(rawValue:)), specifications: specs.compactMap(DashboardSpecification.init(rawValue:)))
 }
 public mutating func setVisible(_ widget: PopoverWidget, visible: Bool) { widgets.removeAll { $0 == widget }; if visible { widgets.append(widget) } }
 public mutating func move(_ widget: PopoverWidget, by offset: Int) {
  guard let i = widgets.firstIndex(of: widget), offset == -1 || offset == 1 else { return }
  let j = i + offset; guard widgets.indices.contains(j) else { return }; widgets.swapAt(i, j)
 }
 public mutating func move(_ widget: PopoverWidget, to target: PopoverWidget) {
  guard widget != target, let from = widgets.firstIndex(of: widget), let destination = widgets.firstIndex(of: target) else { return }
  widgets.remove(at: from); widgets.insert(widget, at: destination)
 }
}
public enum EnergyConsumerPolicy {
 public static func shouldQuery(dashboardActive: Bool, dashboardHasWidget: Bool, popoverVisible: Bool, popoverHasWidget: Bool) -> Bool {
  (dashboardActive && dashboardHasWidget) || (popoverVisible && popoverHasWidget)
 }
}
