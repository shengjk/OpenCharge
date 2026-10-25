import Foundation

struct TrendSample {
 var date: Date
 var percent: Double
 var limit: Double? = nil
}

/// Display-only data. Invalid readings never change the stored history.
struct TrendPlot {
 struct CurveSegment {
  let start: CGPoint
  let control1: CGPoint
  let control2: CGPoint
  let end: CGPoint
 }
 let samples: [TrendSample]
 let domain: ClosedRange<Date>
 let charge: [CGPoint]
 let limits: [CGPoint]
 let curves: [CurveSegment]
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
   charge = []; limits = []; curves = []; return
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
  curves = Self.monotone(charge)
 }

 /// Cubic Hermite interpolation with a slope limiter prevents overshooting adjacent readings.
 static func monotone(_ points: [CGPoint]) -> [CurveSegment] {
  guard points.count > 1 else { return [] }
  var slopes = [CGFloat]()
  for i in 0..<(points.count - 1) {
   let dx = points[i + 1].x - points[i].x
   let slope = dx > 0 ? (points[i + 1].y - points[i].y) / dx : 0
   slopes.append(slope.isFinite ? slope : 0)
  }
  var tangents = Array(repeating: CGFloat.zero, count: points.count)
  tangents[0] = slopes[0]; tangents[points.count - 1] = slopes[slopes.count - 1]
  if points.count > 2 {
   for i in 1..<(points.count - 1) {
    let a = slopes[i - 1], b = slopes[i]
    tangents[i] = (a > 0 && b > 0) || (a < 0 && b < 0) ? a / 2 + b / 2 : 0
   }
  }
  for i in slopes.indices {
   let slope = slopes[i]
   if slope == 0 { tangents[i] = 0; tangents[i + 1] = 0; continue }
   let a = min(3, max(0, tangents[i] / slope)), b = min(3, max(0, tangents[i + 1] / slope))
   let magnitude = hypot(a, b)
   let scale: CGFloat = magnitude > 3 ? 3 / magnitude : 1
   tangents[i] = scale * a * slope
   tangents[i + 1] = scale * b * slope
  }
  return slopes.indices.map { i in
   let start = points[i], end = points[i + 1], dx = (end.x - start.x) / 3
   return CurveSegment(start: start, control1: CGPoint(x: start.x + dx, y: start.y + tangents[i] * dx),
    control2: CGPoint(x: end.x - dx, y: end.y - tangents[i + 1] * dx), end: end)
  }
 }

 var tickDates: [Date] {
  let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
  guard span.isFinite else { return [domain.lowerBound, domain.upperBound] }
  return [domain.lowerBound, domain.lowerBound.addingTimeInterval(span / 2), domain.upperBound]
 }
}
