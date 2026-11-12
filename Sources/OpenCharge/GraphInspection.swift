import SwiftUI
import AppKit
import ChargeCore

/// Select stored records in display space. Equal distances keep the earlier record.
enum GraphInspection {
 static func nearestIndex(dates: [Date], domain: ClosedRange<Date>, width: CGFloat, x: CGFloat) -> Int? {
  let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
  guard dates.count > 1, width.isFinite, width > 0, x.isFinite, span.isFinite, span > 0 else { return nil }
  let positions = dates.map { date in
   CGPoint(x: CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * width, y: 0)
  }
  return nearestIndex(positions: positions, x: x)
 }

 static func nearestIndex(positions: [CGPoint], x: CGFloat) -> Int? {
  guard positions.count > 1, x.isFinite else { return nil }
  var best: Int?
  var distance = CGFloat.infinity
  for (index, position) in positions.enumerated() {
   let candidate = abs(position.x - x)
   if position.x.isFinite && position.y.isFinite && candidate.isFinite && candidate < distance {
    best = index; distance = candidate
   }
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
   Text(date, style: .date).fixedSize()
   Text(DateDisplay.string(date, style: .time)).fixedSize()
  }.font(.caption2.monospacedDigit())
   .padding(5).background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.windowBackgroundColor)))
   .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.4)))
   .fixedSize().allowsHitTesting(false)
 }
}

struct GraphInspectionSample {
 let date: Date
 let position: CGPoint
 let value: String
 let secondary: String?
}

/// A shared interaction layer; the owning plot supplies its actual drawing coordinates.
struct GraphInspectionOverlay: View {
 let samples: [GraphInspectionSample]
 let size: CGSize
 @State private var pointerFraction: CGFloat?
 var body: some View {
  ZStack(alignment: .topLeading) {
   GraphPointerSurface { x in
    pointerFraction = x.flatMap { size.width > 0 ? min(1, max(0, $0 / size.width)) : nil }
   }
   if let fraction = pointerFraction,
      let index = GraphInspection.nearestIndex(positions: samples.map(\.position), x: fraction * size.width) {
    let sample = samples[index]
    Path { path in
     path.move(to: CGPoint(x: sample.position.x, y: 0))
     path.addLine(to: CGPoint(x: sample.position.x, y: size.height))
    }.stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).allowsHitTesting(false)
    Circle().fill(PresentationPalette.mint).frame(width: 7, height: 7)
     .position(sample.position).allowsHitTesting(false)
    GraphInspectionCallout(date: sample.date, value: sample.value, secondary: sample.secondary)
     .frame(width: max(0, size.width - 12), height: size.height,
      alignment: sample.position.x > size.width / 2 ? .topTrailing : .topLeading)
     .padding(.horizontal, 6)
   }
  }.frame(width: size.width, height: size.height)
   .accessibilityHidden(true).onDisappear { pointerFraction = nil }
 }
}

extension TrendPlot {
 var inspectionSamples: [GraphInspectionSample] {
  guard charge.count == chargeSamples.count else { return [] }
  return chargeSamples.indices.map { index in
   let sample = chargeSamples[index]
   return GraphInspectionSample(date: sample.date, position: charge[index],
    value: Self.accessiblePercent(sample.percent),
    secondary: sample.limit.flatMap { value in
     value.isFinite ? NSLocalizedString("上限", comment: "") + " " + Self.accessiblePercent(value) : nil
    })
  }
 }
}
