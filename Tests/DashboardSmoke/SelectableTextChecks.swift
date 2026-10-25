import AppKit

@MainActor func selectableTextChecks() {
 _ = NSApplication.shared
 let field = SelectableStatusField(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
 precondition(field.isSelectable && !field.isEditable && !field.isBezeled && !field.isBordered && !field.drawsBackground)
 precondition(field.maximumNumberOfLines == 0 && field.cell?.wraps == true && field.cell?.isScrollable == false)
 let text = "Read-only status · 只读状态 · 🪫\n" + String(repeating: "A long diagnostic remains selectable and wraps at the available width. ", count: 12)
 field.update(text)
 precondition(field.stringValue == text)
 precondition(field.accessibilityValue() == text)
 let wide = field.intrinsicContentSize
 field.setFrameSize(NSSize(width: 120, height: wide.height))
 let narrow = field.intrinsicContentSize
 precondition(wide.width == NSView.noIntrinsicMetric && narrow.height > wide.height,
  "wrapping status text must grow vertically when the host narrows")
 field.setFrameSize(NSSize(width: 700, height: narrow.height))
 precondition(field.intrinsicContentSize.height < narrow.height)
 // Native selection is exercised only in this never-shown private window. No copy/pasteboard write.
 let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
 window.isReleasedWhenClosed = false; window.contentView = field
 field.selectText(nil)
 guard let editor = field.currentEditor() as? NSTextView else { preconditionFailure("read-only text must acquire a native selection editor") }
 precondition(editor.string == text && editor.isSelectable && !editor.isEditable)
 let selection = NSRange(location: 3, length: 9)
 editor.setSelectedRange(selection)
 field.update(text)
 precondition(editor.selectedRange() == selection, "an unchanged polling status must preserve the user's selection")
 precondition(editor.responds(to: #selector(NSText.copy(_:))))
 field.update("New 🪫")
 precondition(editor.string == "New 🪫", "a status update must replace the visible selection editor's text")
 let range = editor.selectedRange()
 precondition(range.location == NSNotFound || NSMaxRange(range) <= (editor.string as NSString).length)
 window.makeFirstResponder(nil)
 field.update("Updated status 🪫")
 precondition(field.stringValue == "Updated status 🪫" && field.accessibilityValue() == "Updated status 🪫")
 field.update("")
 precondition(field.intrinsicContentSize.height.isFinite && field.intrinsicContentSize.height > 0)
 window.contentView = nil
 print("PASS legacy selectable status: native read-only editor, Unicode/newlines, width-dependent wrapping, unchanged-selection retention and AX value; no clipboard write or visible window")
}
