import SwiftUI
import AppKit
import ChargeCore

/// Select stored records in display space. Equal distances keep the earlier record.
enum GraphInspection {
 static func nearestIndex(dates: [Date], domain: ClosedRange<Date>, width: CGFloat, x: CGFloat) -> Int? {
  let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
  guard dates.count > 1, width.isFinite, width > 0, x.isFinite, span.isFinite, span > 0 else { return nil }
  var best: Int?
  var distance = CGFloat.infinity
  for (index, date) in dates.enumerated() {
   let position = CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * width
   let candidate = abs(position - x)
   if candidate.isFinite && candidate < distance { best = index; distance = candidate }
  }
  return best
 }
}

/// Tracking areas receive movement without taking clicks away from the chart.
struct GraphPointerSurface: NSViewRepresentable {
 var moved: (CGFloat?) -> Void
 func makeNSView(context: Context) -> GraphPointerView { GraphPointerView() }
 func updateNSView(_ view: GraphPointerView, context: Context) { view.moved = moved }
 static func dismantleNSView(_ view: GraphPointerView, coordinator: ()) { view.moved = nil }
}

final class GraphPointerView: NSView {
 var moved: ((CGFloat?) -> Void)?
 private var area: NSTrackingArea?
 override var isFlipped: Bool { true }
 override func hitTest(_ point: NSPoint) -> NSView? { nil }
 override func updateTrackingAreas() {
  super.updateTrackingAreas()
  if let area { removeTrackingArea(area) }
  let next = NSTrackingArea(rect: .zero,
   options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
   owner: self, userInfo: nil)
  addTrackingArea(next); area = next
 }
 override func mouseEntered(with event: NSEvent) { update(event) }
 override func mouseMoved(with event: NSEvent) { update(event) }
 override func mouseExited(with event: NSEvent) { moved?(nil) }
 private func update(_ event: NSEvent) {
  let point = convert(event.locationInWindow, from: nil)
  moved?(bounds.contains(point) ? point.x : nil)
 }
}

struct GraphInspectionCallout: View {
 let date: Date
 let value: String
 let secondary: String?
 var body: some View {
  VStack(alignment: .leading, spacing: 2) {
   Text(value).fontWeight(.bold).fixedSize()
   if let secondary { Text(secondary).fixedSize() }
   Text(DateDisplay.string(date, style: .time)).fixedSize()
  }.font(.caption2.monospacedDigit())
   .padding(5).background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.windowBackgroundColor)))
   .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.4)))
   .fixedSize().allowsHitTesting(false)
 }
}
