import AppKit

@MainActor func graphInspectionChecks() {
 let first = Date(timeIntervalSince1970: 1000)
 let last = first.addingTimeInterval(100)
 let dates = [first, first.addingTimeInterval(30), first.addingTimeInterval(30), last]
 let domain = first...last
 // Irregular dates use displayed distance, not a rounded array offset.
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: 90) == 1)
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: 30) == 0)
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: 130) == 1)
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: 199) == 3)
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: -10) == 0)
 precondition(GraphInspection.nearestIndex(dates: [first], domain: domain, width: 200, x: 0) == nil)
 for width: CGFloat in [0, -1, .nan, .infinity] {
  precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: width, x: 0) == nil)
 }
 precondition(GraphInspection.nearestIndex(dates: dates, domain: domain, width: 200, x: .nan) == nil)
 precondition(GraphInspection.nearestIndex(dates: dates, domain: first...first, width: 200, x: 0) == nil)
 let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
 let pointer = GraphPointerView(frame: NSRect(x: 40, y: 20, width: 200, height: 100))
 root.addSubview(pointer)
 let window = NSWindow(contentRect: root.bounds, styleMask: .borderless, backing: .buffered, defer: true)
 window.contentView = root
 defer { window.contentView = nil }
 var events: [CGFloat?] = []
 pointer.moved = { events.append($0) }
 pointer.updateTrackingAreas()
 precondition(pointer.trackingAreas.count == 1)
 precondition(pointer.trackingAreas[0].options.contains([.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]))
 precondition(pointer.hitTest(NSPoint(x: 10, y: 10)) == nil)
 func event(_ point: NSPoint) -> NSEvent {
  NSEvent.mouseEvent(with: .mouseMoved, location: pointer.convert(point, to: nil),
   modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
   eventNumber: 0, clickCount: 0, pressure: 0)!
 }
 pointer.mouseEntered(with: event(NSPoint(x: 20, y: 30)))
 pointer.mouseMoved(with: event(NSPoint(x: 170, y: 30)))
 pointer.mouseExited(with: event(NSPoint(x: 210, y: 30)))
 precondition(events.count == 3 && events[0] == 20 && events[1] == 170 && events[2] == nil)
 pointer.updateTrackingAreas(); precondition(pointer.trackingAreas.count == 1)
 print("PASS graph inspection irregular-date nearest record, earlier ties/duplicate dates, endpoint and degenerate geometry; injected AppKit enter/move/exit coordinates, tracking refresh and click passthrough; no physical pointer or controller actions")
}
