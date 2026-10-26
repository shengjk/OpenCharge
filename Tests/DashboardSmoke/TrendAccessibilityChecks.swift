import AppKit
import SwiftUI
import Accessibility
import ChargeCore

@MainActor func trendAccessibilityChecks() {
 _ = NSApplication.shared
 let origin = Date(timeIntervalSinceReferenceDate: 1000)
 func sample(_ seconds: Double, _ percent: Double, _ limit: Double? = nil) -> TrendSample {
  TrendSample(date: origin.addingTimeInterval(seconds), percent: percent, limit: limit)
 }
 func plot(_ samples: [TrendSample], width: CGFloat = 600) -> TrendPlot {
  TrendPlot(samples: samples, size: CGSize(width: width, height: 200))
 }
 func children(_ view: LegacyTrendAccessibilityView) -> [NSAccessibilityElement] {
  view.accessibilityChildren() as! [NSAccessibilityElement]
 }
 let view = LegacyTrendAccessibilityView(frame: NSRect(x: 0, y: 0, width: 644, height: 232))
 precondition(view.isAccessibilityElement() && view.accessibilityRole() == .group)
 precondition(children(view).isEmpty && view.hitTest(.zero) == nil)
 let samples = [sample(120, 100, 90), sample(0, 20, 80), sample(60, 50), sample(60, 65, .nan), sample(121, .nan)]
 view.update(plot(samples))
 let readings = children(view)
 precondition(readings.count == 4)
 precondition(readings[0].accessibilityLabel() == DateDisplay.string(origin))
 precondition(readings[0].accessibilityValue() as? String == NSLocalizedString("电量", comment: "") + " " + TrendPlot.accessiblePercent(20) + " · " + NSLocalizedString("上限", comment: "") + " " + TrendPlot.accessiblePercent(80))
 for index in [1, 2] {
  precondition((readings[index].accessibilityValue() as? String)?.contains(NSLocalizedString("未知", comment: "")) == true,
   "unknown limits cannot inherit a previous known value")
 }
 precondition(readings.allSatisfy { $0.accessibilityRole() == .staticText && $0.accessibilityParent() as? NSView === view })
 precondition(readings[1] !== readings[2], "duplicate timestamps remain separate readings")
 let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 644, height: 232), styleMask: .borderless, backing: .buffered, defer: false)
 window.isReleasedWhenClosed = false; window.contentView = view
 let firstFrame = readings[0].accessibilityFrame(), lastFrame = readings[3].accessibilityFrame()
 precondition(firstFrame.width == 6 && lastFrame.midX > firstFrame.midX && firstFrame.midY < lastFrame.midY,
  "screen frames must follow time left-to-right and charge bottom-to-top")
 precondition(view.accessibilityHitTest(NSPoint(x:firstFrame.midX,y:firstFrame.midY)) as? NSAccessibilityElement === readings[0])
 view.update(plot(samples, width: 300))
 precondition(children(view)[0] === readings[0] && children(view)[3] === readings[3])
 precondition(readings[3].accessibilityFrame().midX < lastFrame.midX)
 let beforeMove = readings[0].accessibilityFrame()
 window.setFrameOrigin(NSPoint(x:200,y:300))
 precondition(readings[0].accessibilityFrame().origin == NSPoint(x:beforeMove.origin.x+100,y:beforeMove.origin.y+100))
 view.update(plot([sample(60, 55), sample(60, 65, .nan), sample(120, 100, 90),sample(180, 75, 80)]))
 precondition(children(view)[0] === readings[1] && children(view)[1] === readings[2])
 precondition(readings[0].accessibilityParent() == nil && readings[0].accessibilityFrame() == .zero, "removed readings cannot retain a live frame")
 precondition((readings[1].accessibilityValue() as? String)?.contains(TrendPlot.accessiblePercent(55)) == true)
 let week: [TrendSample] = (0..<10080).map { index in
  let limit: Double? = index % 2 == 0 ? 80 : nil
  return sample(Double(index) * 60, Double(index % 101), limit)
 }
 view.update(plot(week)); precondition(children(view).count == 10080)
 if #available(macOS 12, *) {
  let audio = AudioTrendAccessibilityView(frame: view.frame)
  audio.update(plot(samples)); window.contentView = audio
  guard let descriptor = audio.accessibilityChartDescriptor, let x = descriptor.xAxis as? AXNumericDataAxisDescriptor else { preconditionFailure("audio graph descriptor is missing") }
  precondition(x.range == 0...120 && descriptor.yAxis?.range == 0...100)
  precondition(descriptor.series.count == 2 && descriptor.series[0].dataPoints.count == 4 && descriptor.series[1].dataPoints.count == 2)
  precondition(descriptor.series[0].dataPoints.map { $0.xValue.__number } == [0,60,60,120])
  precondition(descriptor.series[0].dataPoints.map { $0.yValue!.__number } == [20,50,65,100])
  precondition(descriptor.series[1].dataPoints.map { $0.xValue.__number } == [0,120])
  precondition(x.valueDescriptionProvider(0) == DateDisplay.string(origin))
  precondition(descriptor.contentDirection == .leftToRight && descriptor.contentFrame.size == CGSize(width:600,height:200))
  precondition(audio.accessibilityChartDescriptor === descriptor)
  audio.update(plot([sample(0,-5,-10),sample(60,120,150)]))
  let clipped = audio.accessibilityChartDescriptor!
  precondition(clipped !== descriptor && clipped.series[0].dataPoints.map { $0.yValue!.__number } == [0,100])
  audio.update(plot([sample(0,75)]))
  precondition((audio.accessibilityChartDescriptor?.xAxis as? AXNumericDataAxisDescriptor)?.range == 0...60)
  precondition(audio.accessibilityChartDescriptor?.series.count == 1)
  audio.update(plot(week)); precondition(audio.accessibilityChartDescriptor?.series[0].dataPoints.count == 10080)
  audio.update(plot([])); precondition(audio.accessibilityChartDescriptor == nil && children(audio).isEmpty)
 }
 // Mount the actual SwiftUI fallback in a never-shown window to check the bridge is present.
 let host = NSHostingView(rootView: LegacyTrendChart(samples:samples))
 window.contentView = host; host.frame = NSRect(x:0,y:0,width:644,height:232)
 host.layoutSubtreeIfNeeded()
 func nativeSurface(_ root: NSView) -> LegacyTrendAccessibilityView? {
  if let found = root as? LegacyTrendAccessibilityView { return found }
  return root.subviews.lazy.compactMap { nativeSurface($0) }.first
 }
 guard let mounted = nativeSurface(host) else { preconditionFailure("SwiftUI chart did not mount its native accessibility bridge") }
 precondition(mounted.isAccessibilityElement() && children(mounted).count == 4)
 // A never-shown NSHostingView returns no hosted AX children on this host.
 // Mounting is verified here; assistive-technology reachability remains a manual gate.
 window.contentView = nil
 print("PASS legacy trend accessibility: chronological native children, duplicate/unknown values, stable identity, resize/window geometry, full week, mounted SwiftUI bridge and available audio descriptors; no visible window, sound or hardware")
}
