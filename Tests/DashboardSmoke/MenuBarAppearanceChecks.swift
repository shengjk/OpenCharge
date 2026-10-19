import AppKit
import ChargeHardware

@MainActor func menuBarAppearanceChecks() throws {
 var checks = 0
 func expect(_ value: Bool, _ reason: String) { precondition(value, reason); checks += 1 }
 let held = BatteryReading(percent: 80, connected: true, charging: false)
 let charging = BatteryReading(percent: 7, connected: true, charging: true)
 let discharge = BatteryReading(percent: 76, currentMA: -600, connected: false, charging: false, physicalAdapterConnected: true)
 expect(MenuBarLabel(display: "status", reading: held).state == .holding, "connected idle state")
 expect(MenuBarLabel(display: "status", reading: charging).state == .charging, "charging telemetry")
 expect(MenuBarLabel(display: "status", reading: discharge).state == .discharging, "physical connection survives adapter inhibition")
 expect(MenuBarLabel(display: "status", reading: discharge).symbol == "arrow.down.circle", "plugged discharge has its own state icon")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 20, currentMA: -600, connected: false, charging: false)).state == .battery, "ordinary battery use is not plugged discharge")
 expect(MenuBarLabel(display: "status", reading: nil).state == .unknown, "missing reading has no invented state")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 80, currentMA: .nan, connected: true, charging: false)).state == .holding, "invalid current cannot infer discharge")
 for style in MenuIconStyle.allCases {
  for display in ["status", "icon", "percentage", "hardware"] {
   let label = MenuBarLabel(display: display, reading: held, style: style.rawValue)
   let image = MenuBarIconRenderer.image(for: label)
   if display == "icon" { expect(label.symbol == MenuBarLabel(display: "status", reading: held, style: style.rawValue).symbol, "icon-only hides text without changing icon style") }
   expect((image != nil) == (display == "status" || display == "icon"), "text-only modes must stay text-only")
   expect(label.accessibilityText.contains("接电未充电"), "state remains accessible for every style and display")
   if let image { expect(image.isTemplate, "idle monochrome images adapt to menu-bar appearance") }
  }
 }
 let lowPower = MenuBarLabel(display: "status", reading: charging, style: "coloredBattery", lowPower: true, tintLowPower: true)
 expect(lowPower.tint == .lowPower, "explicit low-power tint precedes charging color")
 expect(MenuBarIconRenderer.image(for: lowPower)?.isTemplate == false, "low-power color must not be discarded by template rendering")
 expect(MenuBarLabel(display: "status", reading: charging, lowPower: true).tint == .monochrome, "existing defaults stay monochrome")
 expect(MenuBarLabel(display: "status", reading: charging, style: "coloredBattery").tint == .charging, "colored charging indication")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 20, connected: false, charging: false), style: "coloredBattery").tint == .lowBattery, "low battery color at twenty percent")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 21, connected: false, charging: false), style: "coloredBattery").tint == .monochrome, "no low battery color above boundary")
 expect(MenuBarLabel(display: "percentage", reading: held, lowPower: true, tintLowPower: true).symbol == nil, "low-power tint cannot add an unwanted icon")
 expect(MenuBarLabel(display: "status", reading: held, style: "invalid").style == .status, "unknown stored style has stable fallback")
 expect(MenuBarLabel(display: "status", reading: nil, style: "coloredBattery").tint == .monochrome, "unknown charge level cannot trigger a low battery warning")
 let aqua = NSAppearance(named: .aqua)!
 var areas: [Int] = []
 for percent in [0.0, 25, 50, 75, 100] {
  let reading = BatteryReading(percent: percent, connected: false, charging: false)
  let label = MenuBarLabel(display: "icon", reading: reading, style: "battery")
  expect(label.fraction == percent / 100, "battery fill uses observed OS percentage")
  var data: Data?
  aqua.performAsCurrentDrawingAppearance { data = MenuBarIconRenderer.image(for: label)?.tiffRepresentation }
  let bitmap = NSBitmapImageRep(data: data!)!
  var area = 0
  for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh {
   if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { area += 1 }
  } }
  areas.append(area)
 }
 expect(zip(areas, areas.dropFirst()).allSatisfy { $0 < $1 }, "rendered battery fill grows strictly with observed charge")
 for invalid in [-1.0, 101, .nan, .infinity] {
  let label = MenuBarLabel(display: "status", reading: BatteryReading(percent: invalid, connected: false, charging: false), style: "battery")
  expect(label.text == "—" && label.fraction == nil, "invalid percentage is unknown, not a fabricated fill")
 }
 if let directory = ProcessInfo.processInfo.environment["OPENCHARGE_ICON_PREVIEW_DIR"], directory.hasPrefix("/") {
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  let image = menuBarContactSheet()
  let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menu-bar-styles.png"))
 }
 print("Menu-bar appearance: \(checks) projection/rendering checks passed; no power settings changed")
}

@MainActor private func menuBarContactSheet() -> NSImage {
 let samples: [(String, BatteryReading?, Bool)] = [
  ("电池供电 40%", BatteryReading(percent: 40, connected: false, charging: false), false),
  ("充电中 80%", BatteryReading(percent: 80, connected: true, charging: true), false),
  ("接电未充电 80%", BatteryReading(percent: 80, connected: true, charging: false), false),
  ("接电放电 76%", BatteryReading(percent: 76, currentMA: -600, connected: false, charging: false, physicalAdapterConnected: true), false),
  ("读数不可用", nil, false),
  ("低电量模式 52%", BatteryReading(percent: 52, connected: false, charging: false), true)
 ]
 return NSImage(size: NSSize(width: 760, height: 520), flipped: false) { _ in
  for dark in [false, true] {
   let base: CGFloat = dark ? 0 : 260
   let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
   appearance.performAsCurrentDrawingAppearance {
    (dark ? NSColor(calibratedWhite: 0.08, alpha: 1) : .white).setFill()
    NSRect(x: 0, y: base, width: 760, height: 260).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
    ((dark ? "深色" : "浅色") as NSString).draw(at: NSPoint(x: 12, y: base + 232), withAttributes: attributes)
    for (column, style) in MenuIconStyle.allCases.enumerated() {
     (style.title as NSString).draw(at: NSPoint(x: 160 + column * 140, y: Int(base) + 232), withAttributes: attributes)
    }
    for (row, sample) in samples.enumerated() {
     let y = base + 198 - CGFloat(row * 31)
     (sample.0 as NSString).draw(at: NSPoint(x: 12, y: y), withAttributes: attributes)
     for (column, style) in MenuIconStyle.allCases.enumerated() {
      let label = MenuBarLabel(display: "status", reading: sample.1, style: style.rawValue, lowPower: sample.2, tintLowPower: true)
      if let image = MenuBarIconRenderer.image(for: label) {
       let point = NSPoint(x: 160 + column * 140, y: Int(y))
       if image.isTemplate {
        let mask = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { rect in
         image.draw(in: rect); NSColor.labelColor.setFill(); rect.fill(using: .sourceIn); return true
        }
        mask.draw(in: NSRect(origin: point, size: NSSize(width: 27, height: 18)))
       } else { image.draw(in: NSRect(origin: point, size: NSSize(width: 27, height: 18))) }
      }
      (label.text as NSString).draw(at: NSPoint(x: 193 + column * 140, y: Int(y)), withAttributes: attributes)
     }
    }
   }
  }
  return true
 }
}
