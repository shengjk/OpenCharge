import Foundation
import AppKit
import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func modeSelectionChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(); let provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider }
 var sample = BatteryReading(percent: 50, temperature: 30, connected: true, charging: false)
 var failReading = false
 func fixture(mode: ChargeMode = .automatic, currentPause: Bool = false, checkpoint: CalibrationCheckpoint? = nil) throws -> ChargeModel {
  var config = Configuration(); config.policy.limit = 50; config.policy.mode = mode
  config.policy.pauseAtCurrent = currentPause ? true : nil; config.calibrationCheckpoint = checkpoint
  config.hardwareEnabled = false; config.systemActionsEnabled = false; config.historyEnabled = false
  try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false, screenLockRequest: { preconditionFailure("mode fixture must not lock") }, readBattery: {
   if failReading { throw HardwareError.unavailable("fixture telemetry unavailable") }; return sample
  })
 }
 let pause = try fixture(mode: .paused, currentPause: true)
 pause.controlModeSelection.wrappedValue = .automatic
 pause.controlModeSelection.wrappedValue = .paused
 sample = BatteryReading(percent: 49, temperature: 30, connected: true, charging: false)
 pause.refresh()
 precondition(pause.config.policy.mode == .paused && pause.config.policy.pauseAtCurrent == nil && pause.decision.action == .inhibitCharge, "explicit picker Pause must stay paused below the old current-limit boundary")
 let saved = try Configuration.load(); precondition(saved.policy.mode == .paused && saved.policy.pauseAtCurrent == nil)

 // The picker uses the same connection guard as other explicit GUI requests.
 sample = BatteryReading(percent: 49, temperature: 30, connected: false, charging: false)
 for mode: ChargeMode in [.topUp, .calibration] {
  let unplugged = try fixture(); let before = unplugged.config.policy
  unplugged.controlModeSelection.wrappedValue = mode
  precondition(unplugged.config.policy == before && unplugged.error != nil)
  let persisted = try Configuration.load(); precondition(persisted.policy == before)
 }
 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 let pending = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .draining))
 pending.controlModeSelection.wrappedValue = .calibration
 precondition(pending.calibrationPending && pending.config.calibrationCheckpoint?.stage == .draining && pending.error != nil)
 pending.controlModeSelection.wrappedValue = .topUp
 precondition(pending.calibrationPending && pending.config.policy.mode == .calibration)
 pending.controlModeSelection.wrappedValue = .automatic
 precondition(!pending.calibrationPending && pending.calibration == .idle && pending.config.calibrationCheckpoint == nil)
 pending.controlModeSelection.wrappedValue = .calibration
 precondition(pending.calibration == .filling && !pending.calibrationPending)
 pending.controlModeSelection.wrappedValue = .paused
 precondition(pending.calibration == .idle && pending.config.calibrationCheckpoint == nil)

 // An accepted cancellation must reach the engine even if the refresh fails.
 let active = try fixture(mode: .calibration)
 sample = BatteryReading(percent: 100, temperature: 30, connected: true, charging: false)
 active.refresh(); precondition(active.calibration == .draining)
 failReading = true
 active.controlModeSelection.wrappedValue = .paused
 precondition(active.calibration == .idle && active.config.calibrationCheckpoint == nil)
 active.controlModeSelection.wrappedValue = .calibration
 failReading = false
 sample = BatteryReading(percent: 90, temperature: 30, connected: true, charging: false)
 active.refresh()
 precondition(active.calibration == .filling && active.config.calibrationCheckpoint?.stage == .filling, "cancelled calibration must not resume its old draining stage after unavailable telemetry")
 active.controlModeSelection.wrappedValue = .calibration
 precondition(active.calibration == .filling, "selecting an active mode is idempotent")

 // Resuming with a fractional reading in the target band completes the run.
 sample.percent = 50.9
 let returning = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .returning))
 returning.resumeCalibration()
 let finished = try Configuration.load()
 precondition(returning.decision.action == .inhibitCharge && returning.calibration == .complete)
 precondition(finished.policy.mode == .automatic && finished.calibrationCheckpoint == nil && finished.lastCalibration != nil)

 sample.percent = 100
 sample.hardwarePercent = 97
 let holding = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .holding))
 holding.config.policy.useHardwarePercent = true
 holding.resumeCalibration()
 let savedHold = try Configuration.load().calibrationCheckpoint
 precondition(holding.calibration == .holding && savedHold?.stage == .holding && savedHold?.holdingSince != nil)
 if let savedHold, let start = savedHold.holdingSince {
  precondition(savedHold.remainingHoldMinutes(at: start.addingTimeInterval(61)) == 59)
 }

 let profile = try fixture(mode: .calibration, checkpoint: CalibrationCheckpoint(stage: .holding, holdingSince: Date()))
 profile.profile(70, 5, 35)
 precondition(profile.config.policy.mode == .automatic && !profile.calibrationPending && profile.calibration == .idle && profile.config.calibrationCheckpoint == nil)
 precondition(profile.config.policy.limit == 70 && profile.config.policy.pauseAtCurrent == nil)
 let profileSaved = try Configuration.load()
 precondition(profileSaved.policy.mode == .automatic && profileSaved.calibrationCheckpoint == nil)
 for model in [pause, pending, active, returning, holding, profile] { precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true) }
 print("Explicit mode picker clears current-limit Pause state, enforces connection/interruption guards, cancels calibration across failed telemetry and shares profile cleanup; isolated telemetry, no hardware")
}

@MainActor func calibrationRecoveryChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider }
 let checkpoint = CalibrationCheckpoint(stage: .draining)
 var connected = true
 func fixture(_ choice: CalibrationRecoveryChoice?, hardware: Bool = false) throws -> ChargeModel {
  var config = Configuration()
  config.historyEnabled = false; config.hardwareEnabled = hardware
  config.policy.mode = .calibration
  config.calibrationCheckpoint = checkpoint; config.calibrationRecoveryChoice = choice
  try config.save()
  return ChargeModel(dashboardDefaults: defaults, observeLid: false, readBattery: {
   BatteryReading(percent: 80, connected: connected, charging: false)
  })
 }
 let alert = CalibrationRecoveryAlert.makeAlert()
 precondition(alert.buttons.count == 2 && (alert.accessoryView as? NSButton)?.state == .off)
 precondition((CalibrationRecoveryAlert.makeAlert(allowRemember: false).accessoryView as? NSButton)?.isEnabled == false)
 let asking = try fixture(nil)
 var prompts = 0, refreshes = 0
 asking.handleInterruptedCalibrationOnLaunch(present: { prompts += 1; return nil },
  request: { _ in preconditionFailure("no helper request") }, refresh: { refreshes += 1 })
 precondition(prompts == 1 && refreshes == 0 && asking.calibrationPending)
 asking.handleInterruptedCalibrationOnLaunch(present: { (resume: false, remember: true) },
  request: { _ in preconditionFailure("no helper request") }, refresh: { refreshes += 1 })
 let remembered = try Configuration.load()
 precondition(remembered.calibrationRecoveryChoice == .cancel && remembered.calibrationCheckpoint == nil)
 precondition(remembered.policy.mode == .automatic && refreshes == 1)

 let cancelling = try fixture(.cancel)
 cancelling.handleInterruptedCalibrationOnLaunch(present: { preconditionFailure("remembered choice must not prompt") },
  request: { _ in preconditionFailure("no helper request") }, refresh: { refreshes += 1 })
 precondition(cancelling.config.policy.mode == .automatic && !cancelling.calibrationPending && refreshes == 2)

 let monitor = try fixture(.resume)
 monitor.handleInterruptedCalibrationOnLaunch(present: { preconditionFailure("remembered choice must not prompt") },
  request: { _ in preconditionFailure("monitoring must not opt in") }, refresh: { refreshes += 1 })
 precondition(monitor.calibrationPending && !monitor.config.hardwareEnabled && refreshes == 2)

 let resuming = try fixture(.resume, hardware: true)
 var commands: [String] = []
 let supported: (String) throws -> String = { command in
  commands.append(command); return "chargeControl:fixture, sleepOverride:interfacesDetected, sleepRecovery:phasesV1"
 }
 connected = false
 resuming.handleInterruptedCalibrationOnLaunch(request: supported, refresh: { refreshes += 1 })
 precondition(resuming.calibrationPending && commands.isEmpty)
 connected = true
 resuming.handleInterruptedCalibrationOnLaunch(request: { _ in "chargeControl:fixture" }, refresh: { refreshes += 1 })
 precondition(resuming.calibrationPending && !resuming.config.hardwareEnabled && refreshes == 2)
 resuming.resolveInterruptedCalibration(resume: true, request: supported,
  persist: { _ in throw CocoaError(.fileWriteNoPermission) }, refresh: { refreshes += 1 })
 precondition(resuming.calibrationPending && !resuming.config.hardwareEnabled && refreshes == 2)
 resuming.handleInterruptedCalibrationOnLaunch(request: supported, refresh: { refreshes += 1 })
 precondition(!resuming.calibrationPending && resuming.config.hardwareEnabled && refreshes == 3)
 precondition(resuming.calibration == .draining && commands == ["capabilities", "capabilities"])
 resuming.config.hardwareEnabled = false

 let daily = try fixture(.cancel, hardware: true)
 daily.handleInterruptedCalibrationOnLaunch(request: { _ in "chargeControl:fixture" }, refresh: { refreshes += 1 })
 precondition(daily.config.policy.mode == .automatic && daily.config.hardwareEnabled && refreshes == 4)
 daily.config.hardwareEnabled = false
 let offline = try fixture(.cancel, hardware: true)
 offline.handleInterruptedCalibrationOnLaunch(request: { _ in throw HelperError.unavailable }, refresh: { refreshes += 1 })
 precondition(offline.config.policy.mode == .automatic && !offline.config.hardwareEnabled && !offline.calibrationPending && refreshes == 5)
 let revoked = try fixture(.resume, hardware: true)
 revoked.enableHardware(false, request: { command in precondition(command == "restore"); return "fixture" }, refresh: {})
 revoked.handleInterruptedCalibrationOnLaunch(request: { _ in preconditionFailure("revoked opt-in must not be reused") },
  refresh: { preconditionFailure("revoked opt-in must remain pending") })
 precondition(revoked.calibrationPending && !revoked.config.hardwareEnabled)
 print("Calibration recovery prompt, remembered choices, charger and helper preflight, and save failure passed; all inputs and requests injected")
}

@MainActor func calibrationSummaryChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = provider }
 var config = Configuration()
 config.historyEnabled = false; config.policy.mode = .calibration
 config.calibrationCheckpoint = CalibrationCheckpoint(stage: .holding, holdingSince: Date().addingTimeInterval(-600))
 config.lastCalibration = Date(timeIntervalSince1970: 1000)
 try config.save()
 var sample = BatteryReading(percent: 100, connected: false, charging: false)
 let model = ChargeModel(dashboardDefaults: defaults, observeLid: false, readBattery: { sample })
 precondition(model.calibrationSummary().interrupted && model.calibrationSummary().showsInPopover)
 precondition(model.calibrationSummary().remainingHoldMinutes == nil)
 model.resumeCalibration()
 precondition(model.calibrationSummary().status == NSLocalizedString("校准：等待接电", comment: ""))
 sample.connected = true
 model.setDashboardFocused(true)
 model.refresh()
 let active = model.dashboard.calibration
 precondition(active.active && !active.interrupted && active.stage == .holding && active.remainingHoldMinutes != nil)
 precondition(active.lastCompleted == config.lastCalibration)
 for compact in [false, true] {
  let view = NSHostingView(rootView: CalibrationSummaryView(model: model, summary: active, compact: compact))
  precondition(view.fittingSize.height > 0)
 }
 model.setDashboardFocused(false)
 sample.connected = false
 model.refresh()
 precondition(model.calibrationSummary().remainingHoldMinutes == nil)
 precondition(model.dashboard.calibration == active, "the dashboard card must respect snapshot freezing")
 model.changeMode(.automatic)
 precondition(!model.calibrationSummary().showsInPopover && !model.config.hardwareEnabled)
 print("Calibration summary waiting/recovery/hold states and both native layouts passed; isolated telemetry")
}
