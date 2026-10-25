import SwiftUI
import AppKit

/// Shared presentation colors retain the system palette where it is available.
enum PresentationPalette {
 static var mint: Color {
  if #available(macOS 12, *) { return .mint }
  return Color(NSColor.systemMint)
 }
}

extension View {
 /// Keep the hierarchical secondary style on modern systems.
 @ViewBuilder func presentationSecondary() -> some View {
  if #available(macOS 12, *) { foregroundStyle(.secondary) }
  else { foregroundColor(.secondary) }
 }

 @ViewBuilder func presentationMint() -> some View {
  if #available(macOS 12, *) { foregroundStyle(.mint) }
  else { foregroundColor(PresentationPalette.mint) }
 }

 @ViewBuilder func presentationOrange() -> some View {
  if #available(macOS 12, *) { foregroundStyle(.orange) }
  else { foregroundColor(.orange) }
 }
}

extension View {
 @ViewBuilder func presentationControlBackground(radius: CGFloat) -> some View {
  if #available(macOS 12, *) {
   background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
  } else {
   background(RoundedRectangle(cornerRadius: radius).fill(Color(NSColor.controlBackgroundColor)))
  }
 }

 @ViewBuilder func presentationPrimaryBackground(opacity: Double, radius: CGFloat) -> some View {
  if #available(macOS 12, *) {
   background(.primary.opacity(opacity), in: RoundedRectangle(cornerRadius: radius))
  } else {
   background(RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(opacity)))
  }
 }

 @ViewBuilder func presentationOrangeBackground(opacity: Double, radius: CGFloat) -> some View {
  if #available(macOS 12, *) {
   background(.orange.opacity(opacity), in: RoundedRectangle(cornerRadius: radius))
  } else {
   background(RoundedRectangle(cornerRadius: radius).fill(Color.orange.opacity(opacity)))
  }
 }

 func presentationBorder(radius: CGFloat, opacity: Double) -> some View {
  // Erase the newer stroke's concrete type inside its availability branch.
  if #available(macOS 12, *) {
   return AnyView(overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(opacity))))
  } else {
   return AnyView(overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(opacity))))
  }
 }

 @ViewBuilder func presentationTint(_ color: Color) -> some View {
  if #available(macOS 13, *) { tint(color) }
  else { accentColor(color) }
 }

 @ViewBuilder func presentationProminentButton() -> some View {
  if #available(macOS 12, *) { buttonStyle(.borderedProminent) }
  else { buttonStyle(LegacyProminentButtonStyle()) }
 }
}

private struct LegacyProminentButtonStyle: ButtonStyle {
 @Environment(\.isEnabled) private var enabled
 func makeBody(configuration: Configuration) -> some View {
  configuration.label
   .foregroundColor(enabled ? .white : .secondary)
   .padding(.horizontal, 8).padding(.vertical, 4)
   .background(RoundedRectangle(cornerRadius: 5).fill(
    enabled ? Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1) : Color.secondary.opacity(0.2)))
 }
}

/// Older systems retain an ordinary native button and its keyboard/accessibility behavior.
struct DestructiveButton<Label: View>: View {
 let action: () -> Void
 let label: Label
 init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
  self.action = action; self.label = label()
 }
 init(_ title: String, action: @escaping () -> Void) where Label == Text {
  self.action = action; self.label = Text(title)
 }
 @ViewBuilder var body: some View {
  if #available(macOS 12, *) { Button(role: .destructive, action: action) { label } }
  else { Button(action: action) { label }.foregroundColor(.red) }
 }
}

/// Submit only on Return; editing and focus changes do not apply a charge limit.
struct CommitTextField: View {
 let title: String
 @Binding var text: String
 let onCommit: () -> Void
 @ViewBuilder var body: some View {
  if #available(macOS 12, *) { TextField(title, text: $text).onSubmit(onCommit) }
  else { TextField(title, text: $text, onCommit: onCommit) }
 }
}

/// All dashboard pages share the same sidebar selection on both navigation hosts.
struct DashboardNavigation<Sidebar: View, Detail: View>: View {
 let sidebar: Sidebar
 let detail: Detail
 init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
  self.sidebar = sidebar(); self.detail = detail()
 }
 var body: some View {
  if #available(macOS 13, *) {
   return AnyView(NavigationSplitView {
    sidebar.navigationSplitViewColumnWidth(220)
   } detail: { detail })
  } else {
   return AnyView(HSplitView {
    sidebar.frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
   })
  }
 }
}
