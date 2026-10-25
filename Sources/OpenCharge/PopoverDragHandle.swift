import AppKit
import SwiftUI
import ChargeCore

private let popoverPasteboardType = NSPasteboard.PasteboardType("org.opencharge.popover-widget")

/// Native source and destination keep dragging independent of checkbox gestures.
struct PopoverDragHandle: NSViewRepresentable {
 let widget: PopoverWidget
 let preferences: PopoverPreferences
 func makeNSView(context: Context) -> PopoverDragSource { PopoverDragSource() }
 func updateNSView(_ view: PopoverDragSource, context: Context) {
  view.widget = widget; view.owner = preferences
  view.setAccessibilityLabel(String(localized:"拖动 \(widget.title)"))
  view.toolTip = String(localized:"拖动调整 \(widget.title) 的顺序")
 }
}

final class PopoverDragSource: NSImageView, NSDraggingSource {
 var widget: PopoverWidget?
 weak var owner: PopoverPreferences?
 override init(frame: NSRect) {
  super.init(frame: frame)
  image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
  contentTintColor = .secondaryLabelColor
  imageScaling = .scaleProportionallyDown
  setAccessibilityElement(true); setAccessibilityRole(.image)
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
 override func mouseDown(with event: NSEvent) {
  guard let image, let widget, owner != nil else { return }
  let payload = NSPasteboardItem()
  payload.setData(Data(widget.rawValue.utf8), forType: popoverPasteboardType)
  let item = NSDraggingItem(pasteboardWriter: payload)
  item.setDraggingFrame(bounds, contents: image)
  owner?.dragging = true
  beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
 }
 func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
  return context == .withinApplication ? .move : []
 }
 func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { owner?.dragging = false }
 static func widget(from sender: NSDraggingInfo, owner: PopoverPreferences) -> PopoverWidget? {
  guard let source = sender.draggingSource as? PopoverDragSource, source.owner === owner,
        let bytes = sender.draggingPasteboard.data(forType: popoverPasteboardType),
        let value = String(data: bytes, encoding: .utf8), let widget = PopoverWidget(rawValue: value),
        widget == source.widget, owner.layout.widgets.contains(widget) else { return nil }
  return widget
 }
}

struct PopoverDropRow<Content: View>: NSViewRepresentable {
 let widget: PopoverWidget
 let preferences: PopoverPreferences
 @ViewBuilder let content: () -> Content
 func makeNSView(context: Context) -> PopoverDropDestination {
  PopoverDropDestination(content: AnyView(content()))
 }
 func updateNSView(_ view: PopoverDropDestination, context: Context) {
  view.widget = widget; view.owner = preferences
  view.host.rootView = AnyView(content())
 }
}

final class PopoverDropDestination: NSView {
 let host: NSHostingView<AnyView>
 var widget: PopoverWidget?
 weak var owner: PopoverPreferences?
 init(content: AnyView) {
  host = NSHostingView(rootView: content)
  super.init(frame: .zero)
  host.translatesAutoresizingMaskIntoConstraints = false
  addSubview(host)
  NSLayoutConstraint.activate([
   host.leadingAnchor.constraint(equalTo: leadingAnchor), host.trailingAnchor.constraint(equalTo: trailingAnchor),
   host.topAnchor.constraint(equalTo: topAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor)
  ])
  registerForDraggedTypes([popoverPasteboardType])
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 private func source(_ sender: NSDraggingInfo) -> PopoverWidget? {
  guard let owner, let widget, owner.layout.widgets.contains(widget) else { return nil }
  return PopoverDragSource.widget(from: sender, owner: owner)
 }
 override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { let accepted = source(sender) != nil; return accepted ? .move : [] }
 override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { source(sender) == nil ? [] : .move }
 override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(sender) != nil }
 override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
  guard let source = source(sender), let widget, let owner else { return false }
  owner.layout.move(source, to: widget); return true
 }
}
