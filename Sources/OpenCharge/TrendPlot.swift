import Foundation
import SwiftUI

struct TrendSample: Equatable {
 var date: Date
 var percent: Double
 var limit: Double? = nil
}

/// Display-only data. Invalid readings never change the stored history.
struct TrendPlot {
 let samples: [TrendSample]
 let domain: ClosedRange<Date>
 let charge: [CGPoint]
 let limits: [CGPoint]
 let size: CGSize

 init(samples: [TrendSample], size: CGSize) {
  self.size = size
  self.samples = samples.enumerated().filter {
   $0.element.date.timeIntervalSinceReferenceDate.isFinite && $0.element.percent.isFinite
  }.sorted {
   $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date
  }.map(\.element)
  let first = self.samples.first?.date ?? Date(timeIntervalSinceReferenceDate: 0)
  let last = self.samples.last?.date ?? first
  domain = first == last ? first.addingTimeInterval(-30)...last.addingTimeInterval(30) : first...last
  guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
        domain.upperBound.timeIntervalSince(domain.lowerBound).isFinite,
        domain.upperBound.timeIntervalSince(domain.lowerBound) > 0 else {
   charge = []; limits = []; return
  }
  let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
  let origin = domain.lowerBound
  func point(_ sample: TrendSample, value: Double) -> CGPoint {
   CGPoint(x: sample.date.timeIntervalSince(origin) / span * size.width,
    y: (1 - min(100, max(0, value)) / 100) * size.height)
  }
  charge = self.samples.map { point($0, value: $0.percent) }
  limits = self.samples.compactMap { sample in
   guard let limit = sample.limit, limit.isFinite else { return nil }
   return point(sample, value: limit)
  }
 }

 var linePath: Path {
  var path = Path()
  guard let first = charge.first else { return path }
  path.move(to: first)
  for point in charge.dropFirst() { path.addLine(to: point) }
  return path
 }

 var limitPath: Path {
  var path = Path()
  guard let first = limits.first else { return path }
  path.move(to: first)
  var previous = first
  for point in limits.dropFirst() {
   path.addLine(to: CGPoint(x: point.x, y: previous.y))
   path.addLine(to: point)
   previous = point
  }
  return path
 }

 func tickLabel(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.setLocalizedDateFormatFromTemplate(domain.upperBound.timeIntervalSince(domain.lowerBound) < 86_400 ? "jm" : "Mdjm")
  return formatter.string(from: date)
 }

 var tickDates: [Date] {
  let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
  guard span.isFinite else { return [domain.lowerBound, domain.upperBound] }
  return [domain.lowerBound, domain.lowerBound.addingTimeInterval(span / 2), domain.upperBound]
 }
}
