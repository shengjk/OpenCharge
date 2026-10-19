import Foundation
import Darwin
import ChargeCore
import ChargeHardware

// Narrow local IPC: only the active console user may request fixed charge/power-mode actions.
// The helper accepts no key names, file paths, shell commands or arbitrary bytes.
func consoleUID() -> uid_t? { var s = stat(); guard stat("/dev/console", &s) == 0, s.st_uid > 0 else { return nil }; return s.st_uid }
func log(_ text: String) { fputs("charged: \(text)\n", stderr) }
guard geteuid() == 0 else { log("must run as root via launchd"); exit(1) }
// Hold the exclusive recovery-directory lock for the daemon lifetime, even if SMC is unavailable.
// A second helper must not replace the living helper's socket after failing to acquire this lock.
let recoveryStore: ChargeRecoveryFileStore
let recoveryBootSession: String
do {
 recoveryStore = try ChargeRecoveryFileStore()
 recoveryBootSession = try ChargeRecoveryFileStore.bootSession()
} catch { log("recovery storage unavailable; refusing service startup: \(error.localizedDescription)"); exit(1) }
let controller: SMCController?
let smcFailure: String?
do {
 controller = try SMCController(recoveryStore: recoveryStore, bootSession: recoveryBootSession); smcFailure = nil
}
catch { controller = nil; smcFailure = error.localizedDescription; log("SMC unavailable; power-mode service remains available") }
let powerModes = PowerModeController()
let magSafe = controller?.magSafeController()
let ledSession = magSafe.map { MagSafeSession(controller: $0) }
var ledLease = ControlLease()
var ledNeedsRestore = false
func restoreLED() throws { try ledSession?.restore(); ledNeedsRestore = false; ledLease.clear() }
func restoreSMC() throws {
 var failure: Error?
 do { try controller?.apply(.restore) } catch { failure = error }
 do { try restoreLED() } catch { failure = failure ?? error }
 if let failure { throw failure }
}
func capabilities() -> String {
 var values = controller?.capabilities() ?? ["chargeControl:unavailable", "SMC:\(smcFailure ?? "unknown")"]
 do { values.append("lowPower:\(try powerModes.status().description)") }
 catch { values.append("lowPower:unavailable") }
 if let status = try? magSafe?.status() { values.append("magSafe:" + status) }
 else { values.append("magSafe:unavailable") }
 return values.joined(separator: ", ")
}
let path = HelperClient.socketPath
var old = stat()
if lstat(path, &old) == 0 {
 guard (old.st_uid == 0 || old.st_uid == consoleUID()), (old.st_mode & S_IFMT) == S_IFSOCK else { log("refusing unexpected socket path"); exit(1) }
 unlink(path)
}
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(1) }
let descriptorFlags = fcntl(fd, F_GETFL)
guard descriptorFlags >= 0, fcntl(fd, F_SETFL, descriptorFlags | O_NONBLOCK) == 0 else { exit(1) }
var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8CString).map { UInt8(bitPattern: $0) }) }
let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { log("socket setup failed"); exit(1) }
var lease = ControlLease()
var needsRestore = false
var owner: uid_t = 0
var restoreBeforeCommands = false
// Recover a prior helper's fixed charge writes before accepting new charge commands.
// This path exists only in a newly installed helper; read-only clients never open the journal.
if let controller {
 do { try controller.apply(.restore) }
 catch {
  needsRestore = true; restoreBeforeCommands = true
  log("interrupted charge recovery pending: \(error.localizedDescription)")
 }
}
var pauseOnSleep = false
var currentAction: HardwareAction? = nil
// Every caller runs on the main queue, serializing console changes and SMC actions.
func synchronizeConsoleOwner() {
 let active = consoleUID() ?? 0
 if active != owner {
  if ledNeedsRestore { do { try restoreLED() } catch { log("LED console restoration failed: \(error.localizedDescription)"); return } }
  restoreBeforeCommands = restoreBeforeCommands || (needsRestore && !lease.retained)
  // Keep the old owner on error so the next timer retries the ownership transition.
  if chown(path, active, 0) == 0 { owner = active }
  else { log("socket ownership update failed") }
 }
 if restoreBeforeCommands {
  do { try restoreSMC(); needsRestore = false; restoreBeforeCommands = false; currentAction = nil; pauseOnSleep = false; lease.clear(); log("pending session restored") }
  catch { log("restoration retry failed: \(error.localizedDescription)") }
 }
}
signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
let shutdownSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
shutdownSource.setEventHandler { do { try restoreSMC() } catch { log("shutdown restoration failed: \(error.localizedDescription)") }; unlink(path); exit(0) }; shutdownSource.resume()
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler { do { try restoreSMC() } catch { log("shutdown restoration failed: \(error.localizedDescription)") }; unlink(path); exit(0) }; interruptSource.resume()
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: 1)
timer.setEventHandler {
 synchronizeConsoleOwner()
 if ledNeedsRestore && ledLease.expired(at: ProcessInfo.processInfo.systemUptime) {
  do { try restoreLED() } catch { log("LED watchdog restoration failed: \(error.localizedDescription)") }
 }
 if ledNeedsRestore && !ledLease.expired(at: ProcessInfo.processInfo.systemUptime) {
  do { try ledSession?.tick(now: ProcessInfo.processInfo.systemUptime) }
  catch { log("LED update failed: \(error.localizedDescription)") }
 }
 if needsRestore && !restoreBeforeCommands && lease.expired(at: ProcessInfo.processInfo.systemUptime) {
  restoreBeforeCommands = true
  synchronizeConsoleOwner()
 }
}
timer.resume()
let powerObserver: SystemPowerObserver?
do {
 powerObserver = try SystemPowerObserver(onSleep: {
  lease.beginSleep(); ledLease.beginSleep()
  if ledNeedsRestore { do { try ledSession?.sleep(now: ProcessInfo.processInfo.systemUptime) } catch { log("LED sleep update failed: \(error.localizedDescription)") } }
  if pauseOnSleep || currentAction == .forceDischarge {
   do { guard let controller else { return }; needsRestore = true; try controller.apply(.inhibitCharge); currentAction = .inhibitCharge }
   catch { log("pause on sleep failed: \(error.localizedDescription)") }
  }
 }, onWake: { lease.wake(at: ProcessInfo.processInfo.systemUptime); ledLease.wake(at: ProcessInfo.processInfo.systemUptime); if ledNeedsRestore { do { try ledSession?.wake(now: ProcessInfo.processInfo.systemUptime) } catch { log("LED wake update failed: \(error.localizedDescription)") } } })
} catch { powerObserver = nil; log("system sleep observation unavailable: \(error.localizedDescription)") }
let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
source.setEventHandler {
 let client = accept(fd, nil, nil); guard client >= 0 else { return }; defer { close(client) }
 var uid: uid_t = 0; var gid: gid_t = 0
 guard getpeereid(client, &uid, &gid) == 0, uid > 0, uid == consoleUID() else { return }
 var noSig: Int32 = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
 let deadline = ProcessInfo.processInfo.systemUptime + 2
 let command: String
 do { command = try HelperSocketIO.readLine(client, limit: 128, deadline: deadline) }
 catch { return }
 // A console switch can happen while reading; a connection is not a persistent authorization.
 synchronizeConsoleOwner()
 guard uid == consoleUID(), uid == owner else { return }
 let response: String
 var attemptedAction = false
 do {
  if command == "capabilities" { response = "OK " + capabilities() }
  else if command == "sleepPolicyOn" || command == "sleepPolicyOff" {
   guard command == "sleepPolicyOff" || (controller != nil && powerObserver != nil) else { throw HelperError.rejected("sleep policy unavailable") }
   pauseOnSleep = command == "sleepPolicyOn"; response = "OK sleepPolicy=\(pauseOnSleep ? "on" : "off")"
  }
  else if command == "retainChargeInhibit" {
   guard !restoreBeforeCommands, let controller else { throw HelperError.rejected("SMC or cleanup unavailable") }
   attemptedAction = true; needsRestore = true; lease.request(at: ProcessInfo.processInfo.systemUptime)
   try controller.apply(.inhibitCharge); currentAction = .inhibitCharge; lease.request(at: ProcessInfo.processInfo.systemUptime, retained: true)
   response = "OK retainedChargeInhibit"
  }
  else if command == "magSafeStatus" { guard let magSafe else { throw HelperError.rejected("MagSafe unavailable") }; response = "OK " + (try magSafe.status()) }
  else if command == "magSafeRestore" { try restoreLED(); response = "OK MagSafe restored" }
  else if command == "magSafeSleepOn" || command == "magSafeSleepOff" {
   guard let ledSession, let magSafe, command == "magSafeSleepOff" || powerObserver != nil else { throw HelperError.rejected("MagSafe sleep observation unavailable") }
   _ = try magSafe.status()
   ledNeedsRestore = true; ledLease.request(at: ProcessInfo.processInfo.systemUptime)
   try ledSession.setOffDuringSleep(command == "magSafeSleepOn", now: ProcessInfo.processInfo.systemUptime)
   response = "OK MagSafe sleep policy updated"
  }
  else if ["magSafeSystem", "magSafeOff", "magSafeGreen", "magSafeOrange", "magSafeBlinkOrange"].contains(command) {
   guard let magSafe, let ledSession else { throw HelperError.rejected("MagSafe unavailable") }
   _ = try magSafe.status()
   let patterns: [String: MagSafePattern] = ["magSafeSystem": .system, "magSafeOff": .off, "magSafeGreen": .green, "magSafeOrange": .orange, "magSafeBlinkOrange": .blinkOrange]
   ledNeedsRestore = true; ledLease.request(at: ProcessInfo.processInfo.systemUptime)
   try ledSession.select(patterns[command]!, now: ProcessInfo.processInfo.systemUptime); response = "OK " + (try magSafe.status())
  }
  else if command == "lowPowerStatus" { response = "OK " + (try powerModes.status()).description }
  else if command == "lowPowerOn" || command == "lowPowerOff" {
   // Deliberate persistent preferences never arm the SMC watchdog or shutdown restoration.
   response = "OK " + (try powerModes.setEnabled(command == "lowPowerOn")).description
  }
  else if command == "lowPowerBatteryOn" || command == "lowPowerBatteryOff" {
   response = "OK " + (try powerModes.setEnabled(command == "lowPowerBatteryOn", source: .battery)).description
  }
  else if command == "lowPowerACOn" || command == "lowPowerACOff" {
   response = "OK " + (try powerModes.setEnabled(command == "lowPowerACOn", source: .ac)).description
  }
  else if command == "lowPowerRestore" { response = "OK " + (try powerModes.restore()).description }
  else {
   guard let action = HardwareAction(rawValue: command) else { throw HelperError.rejected("unknown action") }
   guard !restoreBeforeCommands || action == .restore else { throw HelperError.rejected("previous session cleanup pending") }
   guard let controller else { throw HelperError.rejected("SMC unavailable: \(smcFailure ?? "unknown")") }
   attemptedAction = true
   lease.request(at: ProcessInfo.processInfo.systemUptime); needsRestore = true
   try controller.apply(action); needsRestore = action != .restore; currentAction = action
   if action == .restore { pauseOnSleep = false; lease.clear() }
   response = "OK \(action.rawValue)"
  }
 } catch {
  if attemptedAction && needsRestore { restoreBeforeCommands = true }
  response = "ERROR " + error.localizedDescription
 }
 do { try HelperSocketIO.writeLine(response, to: client, deadline: ProcessInfo.processInfo.systemUptime + 1) }
 catch { log("IPC response delivery failed") }
}
source.resume(); dispatchMain()
