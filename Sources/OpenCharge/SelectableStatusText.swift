import SwiftUI
import AppKit

struct SelectableStatusText: View {
 var text: String
 var body: some View {
  if #available(macOS 12, *) {
   return AnyView(Text(text).font(.callout).textSelection(.enabled))
  }
  return AnyView(LegacySelectableStatusText(text: text).frame(maxWidth: .infinity, alignment: .leading))
 }
}

private struct LegacySelectableStatusText: NSViewRepresentable {
 var text: String
 func makeNSView(context: Context) -> SelectableStatusField {
  let field = SelectableStatusField(frame: .zero); field.update(text); return field
 }
 func updateNSView(_ field: SelectableStatusField, context: Context) { field.update(text) }
}

/// A wrapping, read-only native control retains AppKit selection and Copy behavior.
final class SelectableStatusField: NSTextField {
 override init(frame: NSRect) {
  super.init(frame: frame)
  isEditable = false; isSelectable = true
  isBezeled = false; isBordered = false; drawsBackground = false
  font = NSFont.preferredFont(forTextStyle: .callout)
  textColor = .labelColor; alignment = .natural
  focusRingType = .none; maximumNumberOfLines = 0
  lineBreakMode = .byWordWrapping
  cell?.wraps = true; cell?.isScrollable = false
  allowsEditingTextAttributes = false
  setContentHuggingPriority(.defaultLow, for: .horizontal)
  setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

 func update(_ text: String) {
  guard stringValue != text else { return }
  stringValue = text
  invalidateIntrinsicContentSize()
 }
 override func setFrameSize(_ newSize: NSSize) {
  let changed = bounds.width != newSize.width
  super.setFrameSize(newSize)
  if changed {
   preferredMaxLayoutWidth = max(1, newSize.width)
   invalidateIntrinsicContentSize()
  }
 }
 override var intrinsicContentSize: NSSize {
  let width = max(1, bounds.width)
  let measured = cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0
  let line = font.map { $0.ascender - $0.descender + $0.leading } ?? 17
  return NSSize(width: NSView.noIntrinsicMetric, height: ceil(max(measured, line)))
 }
}
