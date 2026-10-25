import AppKit
import ChargeHardware

@MainActor func menuBarAppearanceChecks() throws {
 var checks = 0
 func expect(_ value: Bool, _ reason: String) { precondition(value, reason); checks += 1 }
 let trickle = BatteryReading(percent: 100, connected: true, charging: true)
 let full = MenuBarLabel(display: "status", reading: trickle, fullChargeHold: true)
 expect(full.state == .full && full.symbol == "pause.circle", "full top-off has a separate pause presentation")
 expect(full.accessibilityText.contains("系统补电管理"), "full presentation does not claim physical charging has stopped")
 expect(MenuBarLabel(display: "status", reading: trickle).state == .charging, "monitoring continues to show observed charging")
 expect(MenuBarLabel(display: "status", reading: nil, fullChargeHold: true).state == .unknown, "full flag cannot invent telemetry")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 100, connected: false, charging: false), fullChargeHold: true).state == .battery, "unplugged telemetry takes priority over old full flag")
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
 let unavailable = MenuBarLabel(display:"status",reading:charging,lowPower:nil,tintLowPower:true)
 expect(unavailable.tint == .monochrome, "unknown low-power state cannot request yellow tint")
 expect(!unavailable.accessibilityText.contains(NSLocalizedString(" · 低电量模式", comment:"")), "unknown state must not announce active Low Power Mode")
 if let symbol = NSImage(systemSymbolName:"bolt.circle",accessibilityDescription:nil) {
  let legacy = MenuBarIconRenderer.legacyColoredSymbol(symbol,color:.red)
  expect(!legacy.isTemplate, "legacy explicit tint must retain its color")
  let bitmap = NSBitmapImageRep(cgImage:legacy.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
  let expectedColor = NSColor.red.usingColorSpace(.sRGB)!
  var coloredPixels = 0
  for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
   // colorAt returns the stored components under a legacy calibrated-space tag.
   // Re-converting that tag would change already-sRGB bitmap values.
   if let pixel = bitmap.colorAt(x:x,y:y), pixel.alphaComponent > 0.25 {
    coloredPixels += 1
    expect(abs(pixel.redComponent - expectedColor.redComponent) < 0.04 && abs(pixel.greenComponent - expectedColor.greenComponent) < 0.04 && abs(pixel.blueComponent - expectedColor.blueComponent) < 0.04, "legacy alpha mask preserves requested RGB: \(pixel) expected \(expectedColor)")
   }
  } }
  expect(coloredPixels > 0, "legacy symbol mask must contain visible pixels")
 }
 expect(MenuBarLabel(display: "status", reading: charging, style: "coloredBattery").tint == .charging, "colored charging indication")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 20, connected: false, charging: false), style: "coloredBattery").tint == .lowBattery, "low battery color at twenty percent")
 expect(MenuBarLabel(display: "status", reading: BatteryReading(percent: 21, connected: false, charging: false), style: "coloredBattery").tint == .monochrome, "no low battery color above boundary")
 expect(MenuBarLabel(display: "percentage", reading: held, lowPower: true, tintLowPower: true).symbol == nil, "low-power tint cannot add an unwanted icon")
 expect(MenuBarLabel(display: "status", reading: held, style: "invalid").style == .status, "unknown stored style has stable fallback")
 expect(MenuBarLabel(display: "status", reading: nil, style: "coloredBattery").tint == .monochrome, "unknown charge level cannot trigger a low battery warning")
 var cache = MenuBarRenderCache()
 let stable = MenuBarLabel(display: "status", reading: held)
 expect(cache.needsRender(stable, appearance: "aqua"), "first presentation must render")
 var duplicateRenders = 0
 for _ in 0..<1000 { if cache.needsRender(stable, appearance: "aqua") { duplicateRenders += 1 } }
 expect(duplicateRenders == 0, "repeated AppKit callbacks must not recreate an unchanged status image")
 expect(cache.needsRender(stable, appearance: "darkAqua"), "real appearance changes must render")
 expect(!cache.needsRender(stable, appearance: "darkAqua"), "the new appearance must settle")
 expect(cache.needsRender(MenuBarLabel(display: "icon", reading: held), appearance: "darkAqua"), "display preference changes must render")
 expect(cache.needsRender(MenuBarLabel(display: "icon", reading: charging), appearance: "darkAqua"), "new observed states must render")
 expect(cache.needsRender(MenuBarLabel(display: "icon", reading: charging, lowPower: true, tintLowPower: true), appearance: "darkAqua"), "power state changes must render")
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
