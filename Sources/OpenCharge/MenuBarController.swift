import AppKit
import Combine
import SwiftUI
import ChargeHardware

struct MenuBarLabel {
 let text: String
 let symbol: String?
 let accessibilityText: String
 init(display: String, reading: BatteryReading?) {
  let percent = reading.flatMap { $0.percent.isFinite && (0...100).contains($0.percent) ? "\(Int($0.percent))%" : nil } ?? "—"
  let batterySymbol = reading?.charging == true ? "battery.100percent.bolt" : reading?.connected == true ? "battery.75percent" : "battery.50percent"
  switch display {
  case "percentage": text = percent; symbol = nil
  case "hardware":
   text = reading?.hardwarePercent.flatMap { $0.isFinite && (0...100).contains($0) ? String(format: "%.0f%%", $0) : nil } ?? "—"
   symbol = nil
  case "icon": text = ""; symbol = batterySymbol
  default:
   text = percent
   symbol = reading?.charging == true ? batterySymbol : reading?.connected == true ? "pause.circle" : batterySymbol
  }
  accessibilityText = "OpenCharge · \(text.isEmpty ? percent : text)"
 }
}

/// Owns the real status item and its anchored popover, including dismissal.
@MainActor final class MenuBarController: NSObject, NSPopoverDelegate {
 private let model: ChargeModel
 private let item: NSStatusItem
 private let popover = NSPopover()
 private var subscriptions = Set<AnyCancellable>()
 private var preferencesObserver: NSObjectProtocol?

 init(model: ChargeModel) {
  self.model = model
  item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  super.init()
  popover.behavior = .transient
  popover.delegate = self
  popover.contentViewController = NSHostingController(rootView: MenuView(consumer: .statusItem, dismiss: { [weak self] in self?.close() }).environmentObject(model))
  item.button?.target = self
  item.button?.action = #selector(togglePopover(_:))
  model.$reading.receive(on: RunLoop.main).sink { [weak self] _ in
   MainActor.assumeIsolated { self?.updateLabel() }
  }.store(in: &subscriptions)
  preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
   MainActor.assumeIsolated { self?.updateLabel() }
  }
  model.openStatusPopoverEditor = { [weak self] in self?.openEditor() }
  updateLabel()
 }

 private func updateLabel() {
  guard let button = item.button else { return }
  let display = UserDefaults.standard.string(forKey: "menuDisplay") ?? "status"
  let label = MenuBarLabel(display: display, reading: model.reading)
  let image = label.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
  image?.isTemplate = true
  button.image = image
  button.imagePosition = .imageLeading
  button.title = label.text
  button.setAccessibilityLabel(label.accessibilityText)
  button.toolTip = "OpenCharge · \(model.decision.reason)"
 }

 @objc func togglePopover(_ sender: Any? = nil) {
  if popover.isShown { popover.performClose(sender); return }
  showPopover()
 }
 func openEditor() {
  model.popoverPreferences.setEditing(true, consumer: .statusItem)
  if popover.isShown { popover.contentViewController?.view.window?.makeKey(); return }
  showPopover()
 }
 private func showPopover() {
  guard let button = item.button else { return }
  NSApp.activate(ignoringOtherApps: true)
  popover.animates = model.popoverPreferences.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  popover.contentViewController?.view.window?.makeKey()
 }
 func clickStatusItem() { item.button?.performClick(nil) }

 func popoverDidShow(_ notification: Notification) {
  if let window = popover.contentViewController?.view.window {
   window.identifier = NSUserInterfaceItemIdentifier("OpenChargeStatusPopover")
   window.title = "OpenCharge · 菜单栏弹窗"
  }
  model.setPopoverVisible(true, consumer: .statusItem)
 }
 func popoverDidClose(_ notification: Notification) {
  model.setPopoverVisible(false, consumer: .statusItem)
  model.popoverPreferences.setEditing(false, consumer: .statusItem)
 }
 func popoverShouldClose(_ popover: NSPopover) -> Bool { return !model.popoverPreferences.dragging }
 func close() {
  popover.close(); model.setPopoverVisible(false, consumer: .statusItem)
  model.popoverPreferences.setEditing(false, consumer: .statusItem)
 }
 deinit {
  if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
 }
}
