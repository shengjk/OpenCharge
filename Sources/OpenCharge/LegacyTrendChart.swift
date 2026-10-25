import SwiftUI
import ChargeCore

struct LegacyTrendChart: View {
 var samples: [TrendSample]
 var body: some View {
  GeometryReader { geometry in
   let width = max(0, geometry.size.width - 44)
   let height = max(0, geometry.size.height - 32)
   let plot = TrendPlot(samples: samples, size: CGSize(width: width, height: height))
   VStack(spacing: 6) {
    HStack(spacing: 6) {
     VStack { Text("100%"); Spacer(); Text("50%"); Spacer(); Text("0%") }
      .font(.caption).presentationSecondary().frame(width: 38, height: height).accessibilityHidden(true)
     ZStack(alignment: .topLeading) {
      grid(size: plot.size).stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1))
      area(plot.charge, height: height).fill(PresentationPalette.mint.opacity(0.12))
      curve(plot).stroke(PresentationPalette.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
      polyline(plot.limits).stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
      if plot.charge.count == 1, let point = plot.charge.first {
       Circle().fill(PresentationPalette.mint).frame(width: 5, height: 5).position(point)
      }
     }.frame(width: width, height: height).clipped().accessibilityHidden(true)
    }
    HStack(spacing: 0) {
     ForEach(Array(plot.tickDates.enumerated()), id: \.offset) { index, date in
      Text(timeLabel(date, domain: plot.domain)).lineLimit(1).minimumScaleFactor(0.7)
       .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == 2 ? .trailing : .center)
     }
    }.font(.caption).presentationSecondary().padding(.leading, 44).accessibilityHidden(true)
   }
   .accessibilityElement(children: .ignore)
   .accessibilityLabel(Text(NSLocalizedString("电量", comment: "")))
   .accessibilityValue(Text(summary(plot)))
  }
 }
 private func grid(size: CGSize) -> Path {
  var path = Path()
  for fraction in [CGFloat(0), 0.5, 1] {
   path.move(to: CGPoint(x: 0, y: size.height * fraction)); path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
  }
  return path
 }
 private func curve(_ plot: TrendPlot) -> Path {
  var path = Path()
  guard let first = plot.charge.first else { return path }
  path.move(to: first)
  for segment in plot.curves {
   path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
  }
  return path
 }
 private func polyline(_ points: [CGPoint]) -> Path {
  var path = Path(); guard let first = points.first else { return path }; path.move(to: first)
  for point in points.dropFirst() { path.addLine(to: point) }; return path
 }
 private func area(_ points: [CGPoint], height: CGFloat) -> Path {
  // Native AreaMark keeps its default linear interpolation independently of the SOC line.
  var path = polyline(points)
  if let first = points.first, let last = points.last {
   path.addLine(to: CGPoint(x: last.x, y: height)); path.addLine(to: CGPoint(x: first.x, y: height)); path.closeSubpath()
  }
  return path
 }
 private func timeLabel(_ date: Date, domain: ClosedRange<Date>) -> String {
  let formatter = DateFormatter()
  formatter.setLocalizedDateFormatFromTemplate(domain.upperBound.timeIntervalSince(domain.lowerBound) < 86_400 ? "jm" : "Mdjm")
  return formatter.string(from: date)
 }
 private func summary(_ plot: TrendPlot) -> String {
  let count = String.localizedStringWithFormat(NSLocalizedString("%lld 个本地采样", comment: ""), Int64(plot.samples.count))
  guard let first = plot.samples.first, let last = plot.samples.last else { return count }
  var parts = [count, DateDisplay.string(first.date), String(format: "%.1f%%", first.percent),
   DateDisplay.string(last.date), String(format: "%.1f%%", last.percent)]
  if let limit = plot.samples.reversed().compactMap({ $0.limit }).first(where: { $0.isFinite }) {
   parts.append(NSLocalizedString("上限", comment: "") + " " + String(format: "%.1f%%", limit))
  }
  return parts.joined(separator: " · ")
 }
}
