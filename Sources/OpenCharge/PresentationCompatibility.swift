import SwiftUI
import AppKit

/// Shared presentation colors retain the system palette where it is available.
enum PresentationPalette {
 static var mint: Color {
  if #available(macOS 12, *) { return .mint }
  return Color(NSColor.systemTeal)
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
