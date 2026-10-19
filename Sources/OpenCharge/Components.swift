import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct Card<Content: View>: View {
 let title: String; let content: Content
 init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
 var body: some View { VStack(alignment: .leading, spacing: 16) { Text(title).font(.headline); content }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06))) }
}
struct Metric: View {
 var label: String; var value: String; var icon: String
 var body: some View {
  GeometryReader { geometry in
   VStack(alignment: .leading, spacing: 12) {
    Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    Text(value).font(.system(size: 24, weight: .semibold, design: .rounded))
     .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
     .frame(width: max(0, geometry.size.width - 36), alignment: .leading).clipped()
   }.padding(18)
  }.frame(height: 110).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
 }
}
