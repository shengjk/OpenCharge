import SwiftUI
import AppKit
import Accessibility
import ChargeCore

extension TrendPlot {
 static func accessiblePercent(_ value: Double) -> String {
  guard value.isFinite else { return NSLocalizedString("未知", comment: "") }
  return String(format: "%.1f%%", locale: Locale.current, min(100, max(0, value)))
 }
 var accessibilitySummary: String {
  let count = String.localizedStringWithFormat(NSLocalizedString("%lld 个本地采样", comment: ""), Int64(samples.count))
  guard let first = samples.first, let last = samples.last else { return count }
  var parts = [count, DateDisplay.string(first.date), Self.accessiblePercent(first.percent),
   DateDisplay.string(last.date), Self.accessiblePercent(last.percent)]
  if let limit = samples.reversed().compactMap({ $0.limit }).first(where: { $0.isFinite }) {
   parts.append(NSLocalizedString("上限", comment: "") + " " + Self.accessiblePercent(limit))
  }
  return parts.joined(separator: " · ")
 }
}

/// Invisible native accessibility surface; drawing and mouse handling stay in SwiftUI.
struct LegacyTrendAccessibility: NSViewRepresentable {
 var plot: TrendPlot
 func makeNSView(context: Context) -> LegacyTrendAccessibilityView {
  if #available(macOS 12, *) { return AudioTrendAccessibilityView() }
  return LegacyTrendAccessibilityView()
 }
 func updateNSView(_ view: LegacyTrendAccessibilityView, context: Context) { view.update(plot) }
}

class LegacyTrendAccessibilityView: NSView {
 fileprivate(set) var plot = TrendPlot(samples: [], size: .zero)
 private var elements: [TrendReadingElement]?
 override var isFlipped: Bool { true }
 override func hitTest(_ point: NSPoint) -> NSView? { nil }
 override init(frame frameRect: NSRect) {
  super.init(frame: frameRect)
  setAccessibilityElement(true); setAccessibilityRole(.group)
  setAccessibilityLabel(NSLocalizedString("电量", comment: ""))
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 func update(_ value: TrendPlot) {
  let changed = value.samples != plot.samples
  plot = value
  if changed {
   if let elements { self.elements = readingElements(reusing: elements) }
   invalidateDescriptor()
   if window?.isVisible == true { NSAccessibility.post(element: self, notification: .layoutChanged) }
  }
 }
 func invalidateDescriptor() { }
 override func accessibilityValue() -> Any? { plot.accessibilitySummary }
 override func accessibilityChildren() -> [Any]? {
  if elements == nil { elements = readingElements(reusing: []) }
  return elements
 }
 override func accessibilityHitTest(_ point: NSPoint) -> Any? {
  let children = accessibilityChildren() as? [TrendReadingElement] ?? []
  return children.first(where: { $0.accessibilityFrame().contains(point) }) ?? self
 }
 private func readingElements(reusing previous: [TrendReadingElement]) -> [TrendReadingElement] {
  var reusable = Dictionary(uniqueKeysWithValues: previous.map { ($0.key, $0) })
  var occurrences: [Date: Int] = [:]
  let next = plot.samples.enumerated().map { index, sample in
   let occurrence = occurrences[sample.date, default: 0]
   occurrences[sample.date] = occurrence + 1
   let key = TrendReadingElement.Key(date: sample.date, occurrence: occurrence)
   let element = reusable.removeValue(forKey: key) ?? TrendReadingElement(key: key, owner: self)
   element.sample = sample; element.index = index
   return element
  }
  for removed in reusable.values { removed.detach() }
  return next
 }
 fileprivate func readingFrame(_ index: Int) -> NSRect {
  guard plot.charge.indices.contains(index) else { return .zero }
  let point = plot.charge[index]
  // The rendered plot starts after the 38-point Y axis and 6-point gap.
  let local = NSRect(x: 44 + point.x - 3, y: point.y - 3, width: 6, height: 6)
  guard let window else { return .zero }
  return window.convertToScreen(convert(local, to: nil))
 }
}

private final class TrendReadingElement: NSAccessibilityElement {
 struct Key: Hashable { let date: Date; let occurrence: Int }
 let key: Key
 private weak var owner: LegacyTrendAccessibilityView?
 var sample = TrendSample(date: Date(timeIntervalSinceReferenceDate: 0), percent: 0)
 var index = 0
 init(key: Key, owner: LegacyTrendAccessibilityView) {
  self.key = key; self.owner = owner
  super.init(); setAccessibilityElement(true); setAccessibilityRole(.staticText)
 }
 func detach() { owner = nil }
 override func accessibilityParent() -> Any? { owner }
 override func accessibilityLabel() -> String? { DateDisplay.string(sample.date) }
 override func accessibilityValue() -> Any? {
  let limit = sample.limit.flatMap { $0.isFinite ? TrendPlot.accessiblePercent($0) : nil } ?? NSLocalizedString("未知", comment: "")
  return NSLocalizedString("电量", comment: "") + " " + TrendPlot.accessiblePercent(sample.percent) + " · " + NSLocalizedString("上限", comment: "") + " " + limit
 }
 override func accessibilityFrame() -> NSRect { owner?.readingFrame(index) ?? .zero }
}

@available(macOS 12, *)
final class AudioTrendAccessibilityView: LegacyTrendAccessibilityView, AXChart {
 private var descriptor: AXChartDescriptor?
 override func invalidateDescriptor() { descriptor = nil }
 var accessibilityChartDescriptor: AXChartDescriptor? {
  get {
   if descriptor == nil { descriptor = makeDescriptor() }
   // AXChart's content frame is in superview coordinates, as specified by the SDK.
   descriptor?.contentFrame = convert(NSRect(x: 44, y: 0, width: plot.size.width, height: plot.size.height), to: superview)
   return descriptor
  }
  set { descriptor = newValue }
 }
 private func makeDescriptor() -> AXChartDescriptor? {
  let origin = plot.domain.lowerBound
  let span = plot.domain.upperBound.timeIntervalSince(origin)
  guard !plot.samples.isEmpty, span.isFinite, span > 0 else { return nil }
  let xAxis = AXNumericDataAxisDescriptor(title: NSLocalizedString("时间", comment: ""), range: 0...span, gridlinePositions: []) { seconds in
   guard seconds.isFinite else { return NSLocalizedString("未知", comment: "") }
   return DateDisplay.string(origin.addingTimeInterval(seconds))
  }
  let yAxis = AXNumericDataAxisDescriptor(title: NSLocalizedString("电量", comment: ""), range: 0...100, gridlinePositions: [0, 50, 100]) { TrendPlot.accessiblePercent($0) }
  let charge = plot.samples.map { AXDataPoint(x: $0.date.timeIntervalSince(origin), y: min(100, max(0, $0.percent))) }
  let limits = plot.samples.compactMap { sample -> AXDataPoint? in
   guard let limit = sample.limit, limit.isFinite else { return nil }
   return AXDataPoint(x: sample.date.timeIntervalSince(origin), y: min(100, max(0, limit)))
  }
  var series = [AXDataSeriesDescriptor(name: NSLocalizedString("电量", comment: ""), isContinuous: true, dataPoints: charge)]
  if !limits.isEmpty { series.append(AXDataSeriesDescriptor(name: NSLocalizedString("上限", comment: ""), isContinuous: true, dataPoints: limits)) }
  let result = AXChartDescriptor(title: NSLocalizedString("电量", comment: ""), summary: plot.accessibilitySummary, xAxis: xAxis, yAxis: yAxis, series: series)
  result.contentDirection = .leftToRight
  return result
 }
}
