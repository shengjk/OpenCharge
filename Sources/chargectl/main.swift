import Foundation
import ChargeCore
import ChargeHardware
import Darwin
func output<T: Encodable>(_ value: T) throws { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; print(String(decoding: try e.encode(value), as: UTF8.self)) }
func recoverOrdinaryQuit(_ configuration: inout Configuration) throws -> String? {
 try OrdinaryQuitRecovery.restoreIfNeeded(configuration:&configuration,request:HelperClient.request,persist:{try $0.save()})
}
func usage() { print("""
OpenCharge CLI
  status [--json]            Read real battery telemetry
  explain                   Preview policy decision; never writes SMC
  limit 20...100             Save a charge limit
  mode automatic|paused|discharge|topUp|calibration
  profile desk|balanced|travel
  departure ISO8601 [target] Set a departure charging plan
  schedule ISO8601 action repeat [value]
  schedules                 List tasks
  low-power status|on|off|restore [battery|ac] [--confirm]
  schedule-remove UUID      Remove a stored schedule
  schedule-history          Show execution results
  diagnose-smc              Probe model/key capabilities; read-only, no helper
  magsafe status|off|green|orange|orange-blinking|restore [--confirm]
                            LED changes expire after 45 awake seconds without renewal
  capabilities              Query the installed root helper
  hardware ACTION --confirm Direct bounded helper action (45s heartbeat lease)
                            allowCharge|inhibitCharge|forceDischarge|restore
                            Numeric firmware models use app-owned control; restore remains available
  restore                   Restore system charging using helper
  export                    Print local history as JSON
  help
Configuration commands do not write hardware. The GUI owns continuous control.
""") }
do {
 let args = Array(CommandLine.arguments.dropFirst()); let command = args.first ?? "help"
 var config = try Configuration.load()
 switch command {
 case "status": let r = try BatteryTelemetryReader.read(); if args.contains("--json") { try output(r) } else { print("Battery \(r.percent)% · \(r.connected ? "AC" : "battery") · charging=\(r.charging) · \(r.temperature.map { String(format: "%.1f°C", $0) } ?? "temperature unavailable")") }
 case "explain": let r = try BatteryTelemetryReader.read(); var e = ChargeEngine(checkpoint: config.calibrationCheckpoint, sailingCheckpoint: config.sailingCheckpoint); try output(e.decide(ChargeSample(percent: try r.controlPercentage(useHardware: config.policy.useHardwarePercent ?? false), temperature: r.temperature, connected: r.connected), policy: config.policy))
 case "limit": guard args.count == 2, let n = Double(args[1]), n.isFinite, (20...100).contains(n) else { throw HelperError.rejected("limit must be 20...100") }; config.setChargeLimit(n); try config.save(); print("Saved \(n)%")
 case "mode": guard args.count == 2, let mode = ChargeMode(rawValue: args[1]) else { throw HelperError.rejected("invalid mode") }; config.policy.mode = mode; config.policy.pauseAtCurrent = nil; try config.save(); print("Saved \(mode.rawValue)")
 case "profile": guard args.count == 2 else { throw HelperError.rejected("profile requires desk|balanced|travel") }; switch args[1] { case "desk": config.setChargeLimit(70); config.policy.sailingWidth = 10; case "balanced": config.setChargeLimit(80); config.policy.sailingWidth = 5; case "travel": config.setChargeLimit(100); default: throw HelperError.rejected("unknown profile") }; config.policy.mode = .automatic; try config.save(); print("Saved profile")
 case "departure": guard args.count >= 2, let date = ISO8601DateFormatter().date(from: args[1]), date > Date() else { throw HelperError.rejected("use a future ISO8601 date with timezone") }; config.policy.departure = date; if args.count > 2 { guard let n = Double(args[2]), n.isFinite, (20...100).contains(n) else { throw HelperError.rejected("target must be 20...100") }; config.policy.departureTarget = n }; try config.save(); print("Saved departure")
 case "schedule": guard args.count >= 4, let date = ISO8601DateFormatter().date(from: args[1]), let action = ScheduleAction(rawValue: args[2]), let rule = RepeatRule(rawValue: args[3]) else { throw HelperError.rejected("schedule ISO8601 action repeat [value]") }; var schedule = ChargeSchedule(); schedule.date = date; schedule.action = action; schedule.repeatRule = rule; if args.count > 4 { guard let n = Double(args[4]), n.isFinite, (20...100).contains(n) else { throw HelperError.rejected("value must be 20...100") }; schedule.value = n }; config.schedules.append(schedule); try config.save(); try output(schedule)
 case "schedules": try output(config.schedules)
 case "schedule-remove": guard args.count == 2, let id = UUID(uuidString: args[1]), config.schedules.contains(where: { $0.id == id }) else { throw HelperError.rejected("unknown schedule UUID") }; config.schedules.removeAll { $0.id == id }; try config.save(); print("Removed schedule")
 case "schedule-history": try output(config.scheduleHistory ?? [])
 case "low-power":
  guard args.count >= 2 else { throw HelperError.rejected("low-power status|on|off|restore [battery|ac] --confirm") }
  if args[1] == "status" { try output(PowerModeController().status()) }
  else {
   guard args.contains("--confirm"), ["on", "off", "restore"].contains(args[1]) else { throw HelperError.rejected("a setting change requires on|off|restore and --confirm") }
   let source = args.dropFirst(2).filter { $0 != "--confirm" }
   guard source.count <= 1, source.isEmpty || ["battery", "ac"].contains(source[0]), args[1] != "restore" || source.isEmpty else { throw HelperError.rejected("invalid source") }
   let prefix = source.first == "battery" ? "lowPowerBattery" : source.first == "ac" ? "lowPowerAC" : "lowPower"
   print(try HelperClient.request(args[1] == "restore" ? "lowPowerRestore" : prefix + (args[1] == "on" ? "On" : "Off")))
  }
 case "magsafe":
  guard args.count >= 2 else { throw HelperError.rejected("magsafe status|off|green|orange|orange-blinking|restore --confirm") }
  if args[1] == "status", args.count == 2 { print(try HelperClient.request("magSafeStatus")) }
  else {
   guard args.count == 3, args[2] == "--confirm", ["off", "green", "orange", "orange-blinking", "restore"].contains(args[1]) else { throw HelperError.rejected("LED change requires a fixed color or restore and --confirm") }
   let commands = ["off": "magSafeOff", "green": "magSafeGreen", "orange": "magSafeOrange", "orange-blinking": "magSafeBlinkOrange", "restore": "magSafeRestore"]
   let command = commands[args[1]]!
   try MagSafePolicy.validateNativeEncoding(command: command, capabilities: { try HelperClient.request("capabilities") })
   _ = try recoverOrdinaryQuit(&config)
   print(try HelperClient.request(command))
  }
 case "diagnose-smc": try output(SMCController().capabilities())
 case "capabilities": print(try HelperClient.request("capabilities"))
 case "hardware":
  print(try DirectChargeCommand.run(arguments: Array(args.dropFirst()), numericRequired: {
   #if arch(x86_64)
   return SMCFirmwareProbe.eligible(model:try HardwareIdentity.model(),architecture:"x86_64",internalBattery:true)
   #else
   return false
   #endif
  }, request: { command in
   let recovered = try recoverOrdinaryQuit(&config)
   if command == "restore", let recovered { return recovered }
   return try HelperClient.request(command)
  }))
 case "restore":
  if let recovered = try recoverOrdinaryQuit(&config) { print(recovered) }
  else { print(try HelperClient.request("restore")) }
 case "export": let url = Configuration.directory.appendingPathComponent("history.json"); print(String(decoding: try Data(contentsOf: url), as: UTF8.self))
 case "help", "--help", "-h": usage()
 default: usage(); exit(2)
 }
} catch { fputs("chargectl: \(error.localizedDescription)\n", stderr); exit(1) }
