import AppKit
import Combine
import SwiftUI
import ChargeHardware

/// Owns the real status item and its anchored popover, including dismissal.
@MainActor final class MenuBarController: NSObject, NSPopoverDelegate {
 private let model: ChargeModel
 private let item: NSStatusItem
 private let popover = NSPopover()
 private var subscriptions = Set<AnyCancellable>()
 private var preferencesObserver: NSObjectProtocol?
 private var powerObserver: NSObjectProtocol?
 private var appearanceObservation: NSKeyValueObservation?

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
  powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
   MainActor.assumeIsolated { self?.updateLabel() }
  }
  appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
   DispatchQueue.main.async { self?.updateLabel() }
  }
  model.openStatusPopoverEditor = { [weak self] in self?.openEditor() }
  updateLabel()
 }

 private func updateLabel() {
  guard let button = item.button else { return }
  let display = UserDefaults.standard.string(forKey: "menuDisplay") ?? "status"
  let defaults = UserDefaults.standard
  let label = MenuBarLabel(display: display, reading: model.reading,
   style: defaults.string(forKey: "menuIconStyle") ?? "status",
   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
   tintLowPower: defaults.bool(forKey: "menuTintLowPower"))
  button.effectiveAppearance.performAsCurrentDrawingAppearance {
   button.image = MenuBarIconRenderer.image(for: label)
  }
  button.imagePosition = .imageLeading
  button.title = label.text
  button.setAccessibilityLabel(label.accessibilityText)
  button.toolTip = "\(label.accessibilityText) · \(model.decision.reason)"
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
  if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
 }
}
