import AppKit
import ChargeHardware

enum MenuIconStyle: String, CaseIterable, Identifiable {
 case status, battery, coloredBattery, openCharge
 var id: String { rawValue }
 var title: String {
  switch self { case .status: return "动态状态"; case .battery: return "电池（单色）"; case .coloredBattery: return "电池（彩色）"; case .openCharge: return "OpenCharge 图标" }
 }
}
enum MenuBatteryState: String {
 case unknown, charging, discharging, holding, full, battery
 var title: String {
  switch self { case .unknown: return "状态未知"; case .charging: return "充电中"; case .discharging: return "接电放电"; case .holding: return "接电未充电"; case .full: return "已满电 · 系统补电管理"; case .battery: return "电池供电" }
 }
}
enum MenuBarTint: Equatable { case monochrome, charging, lowBattery, lowPower
 var color: NSColor? {
  switch self { case .monochrome: return nil; case .charging: return .systemGreen; case .lowBattery: return .systemRed; case .lowPower: return .systemYellow }
 }
}
struct MenuBarLabel: Equatable {
 let text: String
 let symbol: String?
 let accessibilityText: String
 let style: MenuIconStyle
 let state: MenuBatteryState
 let fraction: Double?
 let tint: MenuBarTint
 init(display: String, reading: BatteryReading?, style: String = "status", lowPower: Bool = false, tintLowPower: Bool = false, fullChargeHold: Bool = false) {
  self.style = MenuIconStyle(rawValue: style) ?? .status
  let validPercent = reading.flatMap { $0.percent.isFinite && (0...100).contains($0.percent) ? $0.percent : nil }
  fraction = validPercent.map { $0 / 100 }
  let percent = validPercent.map { "\(Int($0))%" } ?? "—"
  if let reading {
   if fullChargeHold && (reading.physicalAdapterConnected ?? reading.connected) { state = .full }
   else if reading.charging { state = .charging }
   else if reading.physicalAdapterConnected ?? reading.connected {
    state = reading.currentMA.map { $0.isFinite && $0 < 0 } == true ? .discharging : .holding
   } else { state = .battery }
  } else { state = .unknown }
  let batterySymbol: String
  if state == .charging { batterySymbol = "battery.100percent.bolt" }
  else if let validPercent {
   let step = min(4, max(0, Int((validPercent / 25).rounded()))) * 25
   batterySymbol = "battery.\(step)percent"
  } else { batterySymbol = "questionmark.circle" }
  let statusSymbol: String
  switch state {
  case .unknown: statusSymbol = "questionmark.circle"
  case .charging: statusSymbol = "battery.100percent.bolt"
  case .discharging: statusSymbol = "arrow.down.circle"
  case .holding, .full: statusSymbol = "pause.circle"
  case .battery: statusSymbol = batterySymbol
  }
  switch display {
  case "percentage": text = percent; symbol = nil
  case "hardware":
   text = reading?.hardwarePercent.flatMap { $0.isFinite && (0...100).contains($0) ? String(format: "%.0f%%", $0) : nil } ?? "—"
   symbol = nil
  default:
   text = display == "icon" ? "" : percent
   switch self.style {
   case .openCharge: symbol = "bolt.circle"
   case .battery, .coloredBattery: symbol = batterySymbol
   case .status: symbol = statusSymbol
   }
  }
  if lowPower && tintLowPower { tint = .lowPower }
  else if self.style == .coloredBattery && (state == .charging || state == .full) { tint = .charging }
  else if self.style == .coloredBattery && validPercent.map({ $0 <= 20 }) == true { tint = .lowBattery }
  else { tint = .monochrome }
  accessibilityText = "OpenCharge · \(text.isEmpty ? percent : text) · \(state.title)" + (lowPower ? " · 低电量模式" : "")
 }
}

/// Independent vector battery; fill uses the observed OS percentage, never a policy target.
enum MenuBarIconRenderer {
 static func image(for label: MenuBarLabel) -> NSImage? {
  guard let symbol = label.symbol else { return nil }
  if label.style == .battery || label.style == .coloredBattery { return battery(label) }
  guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
  if let color = label.tint.color {
   let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) ?? image
   configured.isTemplate = false; return configured
  }
  image.isTemplate = true; return image
 }
 private static func battery(_ label: MenuBarLabel) -> NSImage {
  let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { _ in
   let color = label.tint.color ?? NSColor.labelColor
   NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
   let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 3.75, width: 22.5, height: 10.5), xRadius: 2, yRadius: 2)
   outline.lineWidth = 1.25; outline.stroke()
   NSBezierPath(roundedRect: NSRect(x: 24, y: 7, width: 2.25, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
   if let fraction = label.fraction, fraction > 0 {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 2.5, y: 5.5, width: 19 * fraction, height: 7), xRadius: min(0.7, 9.5 * fraction), yRadius: 0.7).fill()
   }
   let badge: String?
   if label.fraction == nil { badge = "questionmark" }
   else { switch label.state { case .charging: badge = "bolt.fill"; case .holding, .full: badge = "pause.fill"; case .discharging: badge = "arrow.down"; default: badge = nil } }
   if let badge, let overlay = NSImage(systemSymbolName: badge, accessibilityDescription: nil) {
    // XOR keeps the state visible over both filled and empty regions of a template image.
    let glyph = overlay.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor])) ?? overlay
    glyph.draw(in: NSRect(x: 8, y: 5, width: 8, height: 8), from: .zero, operation: .xor, fraction: 1, respectFlipped: false, hints: nil)
   }
   return true
  }
  image.isTemplate = label.tint == .monochrome
  return image
 }
}

/// AppKit may invalidate effective appearance while snapshotting the status item itself.
/// Cache semantic values before assigning an image, so those callbacks cannot redraw forever.
struct MenuBarRenderCache {
 private struct Key: Equatable { let label: MenuBarLabel; let appearance: String }
 private var key: Key?
 mutating func needsRender(_ label: MenuBarLabel, appearance: String) -> Bool {
  let next = Key(label: label, appearance: appearance)
  guard next != key else { return false }
  key = next
  return true
 }
}
