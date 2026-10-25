import Foundation
import CoreGraphics
import ImageIO

func trendPlotChecks() {
 let origin = Date(timeIntervalSinceReferenceDate: 1000)
 func sample(_ seconds: Double, _ percent: Double, _ limit: Double? = nil) -> TrendSample {
  TrendSample(date: origin.addingTimeInterval(seconds), percent: percent, limit: limit)
 }
 func plot(_ samples: [TrendSample], size: CGSize = CGSize(width: 600, height: 200)) -> TrendPlot {
  TrendPlot(samples: samples, size: size)
 }
 let empty = plot([])
 precondition(empty.charge.isEmpty && empty.limits.isEmpty && empty.curves.isEmpty)
 let singleton = plot([sample(0, 75, 80)])
 precondition(singleton.charge == [CGPoint(x: 300, y: 50)])
 precondition(singleton.limits.count == 1 && singleton.curves.isEmpty)
 precondition(singleton.domain.lowerBound == origin.addingTimeInterval(-30) && singleton.domain.upperBound == origin.addingTimeInterval(30))
 let mixed = plot([sample(120, 100, 90), sample(0, 0, 80), sample(60, 50)])
 precondition(mixed.samples.map(\.percent) == [0, 50, 100])
 precondition(mixed.charge == [CGPoint(x: 0, y: 200), CGPoint(x: 300, y: 100), CGPoint(x: 600, y: 0)])
 precondition(mixed.limits.count == 2 && mixed.limits[0].x == 0 && mixed.limits[1].x == 600)
 precondition(mixed.tickDates == [origin, origin.addingTimeInterval(60), origin.addingTimeInterval(120)])
 let duplicate = plot([sample(0, 20), sample(0, 80), sample(60, 40)])
 precondition(duplicate.samples.count == 3 && duplicate.charge[0].x == duplicate.charge[1].x)
 precondition(duplicate.curves[0].start.y == 160 && abs(duplicate.curves[0].end.y - 40) < 0.00001)
 let invalid = plot([sample(0, .nan), sample(1, 20, .infinity), sample(2, -5, -10), sample(3, 120, 150),
  TrendSample(date: Date(timeIntervalSinceReferenceDate: .infinity), percent: 10)])
 precondition(invalid.samples.count == 3 && invalid.charge.allSatisfy { (0...200).contains($0.y) })
 precondition(invalid.limits.count == 2 && invalid.limits[0].y == 200 && invalid.limits[1].y == 0)
 for size in [CGSize.zero, CGSize(width: -1, height: 20), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: CGFloat.nan)] {
  let invalidSize = plot([sample(0, 10), sample(1, 20)], size: size)
  precondition(invalidSize.charge.isEmpty && invalidSize.limits.isEmpty && invalidSize.curves.isEmpty)
 }
 let runs: [[Double]] = [[0, 10, 50, 100], [100, 80, 20, 0], [50, 50, 50, 50], [0, 100, 0, 100], [0, 0, 100, 100], [0, 99.99, 100, 100]]
 var evaluated = 0
 for values in runs {
  let graph = plot(zip([0.0, 0.001, 20, 100], values).map { sample($0.0, $0.1) })
  for segment in graph.curves {
   for step in 0...100 {
    let t = CGFloat(step) / 100, u = 1 - t
    let x = u*u*u*segment.start.x + 3*u*u*t*segment.control1.x + 3*u*t*t*segment.control2.x + t*t*t*segment.end.x
    let y = u*u*u*segment.start.y + 3*u*u*t*segment.control1.y + 3*u*t*t*segment.control2.y + t*t*t*segment.end.y
    precondition(x.isFinite && y.isFinite)
    precondition(x >= segment.start.x - 0.00001 && x <= segment.end.x + 0.00001)
    precondition(y >= min(segment.start.y, segment.end.y) - 0.00001 && y <= max(segment.start.y, segment.end.y) + 0.00001,
     "a trend must not invent a peak or dip between adjacent readings")
    evaluated += 1
   }
  }
 }
 let week = plot((0..<10080).map { sample(Double($0) * 60, Double($0 % 101), $0 % 2 == 0 ? 80 : nil) })
 precondition(week.charge.count == 10080 && week.curves.count == 10079 && week.limits.count == 5040,
  "the fallback must keep the full stored history rather than silently downsample")
 try! writeTrendGeometryPreview()
 print("PASS legacy trend projection: full history, time scale, duplicates, unknown limits, invalid data/layout and \(evaluated) bounded cubic samples; no UI or hardware")
}

// Optional private geometry artifact only. No app window or UI event is created.
func writeTrendGeometryPreview() throws {
 guard let folder = ProcessInfo.processInfo.environment["OPENCHARGE_TREND_PREVIEW_DIR"], !folder.isEmpty else { return }
 let context = CGContext(data: nil, width: 840, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
 context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 840, height: 300))
 context.translateBy(x: 40, y: 280); context.scaleBy(x: 1, y: -1)
 let date = Date(timeIntervalSinceReferenceDate: 0)
 let values: [Double] = [20, 20, 22, 75, 90, 90, 89, 70, 30, 15, 55]
 let plot = TrendPlot(samples: values.enumerated().map { i, value in
  TrendSample(date: date.addingTimeInterval(Double(i * i + i) * 60), percent: value, limit: i == 5 ? nil : i < 6 ? 80 : 65)
 }, size: CGSize(width: 760, height: 240))
 context.setStrokeColor(CGColor(gray: 0.8, alpha: 1)); context.setLineWidth(1)
 for y: CGFloat in [0, 120, 240] { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: 760, y: y)); context.strokePath() }
 let area = CGMutablePath(); area.move(to: plot.charge[0])
 for point in plot.charge.dropFirst() { area.addLine(to: point) }
 area.addLine(to: CGPoint(x: plot.charge.last!.x, y: 240)); area.addLine(to: CGPoint(x: plot.charge[0].x, y: 240)); area.closeSubpath()
 context.setFillColor(CGColor(red: 0, green: 0.65, blue: 0.6, alpha: 0.12)); context.addPath(area); context.fillPath()
 context.move(to: plot.charge[0])
 for curve in plot.curves { context.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2) }
 context.setLineWidth(2); context.setStrokeColor(CGColor(red: 0, green: 0.65, blue: 0.6, alpha: 1)); context.strokePath()
 context.setStrokeColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)); context.setLineWidth(1); context.setLineDash(phase: 0, lengths: [4, 4])
 context.move(to: plot.limits[0]); for point in plot.limits.dropFirst() { context.addLine(to: point) }; context.strokePath()
 let directory = URL(fileURLWithPath: folder, isDirectory: true)
 try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
 let target = directory.appendingPathComponent("trend-geometry-preview.png")
 let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
 CGImageDestinationAddImage(destination, context.makeImage()!, nil)
 precondition(CGImageDestinationFinalize(destination))
}
