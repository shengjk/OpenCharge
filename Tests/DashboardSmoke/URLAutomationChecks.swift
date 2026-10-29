import Foundation
import ChargeCore
import ChargeHardware

@MainActor func urlAutomationChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.url-check."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); defaults.removePersistentDomain(forName:suite); PolicyStateRuntime.provider = provider }
 enum Failure: Error { case storage }
 func model() -> ChargeModel {
  ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{BatteryReading(percent:50,connected:true,charging:false)})
 }
 func reject(_ value: String, in model: ChargeModel) throws {
  let before = try Data(contentsOf:Configuration.url)
  let limit = model.config.policy.limit, mode = model.config.policy.mode, id = model.config.chargeLimitChangeID
  var refreshed = false
  model.handleURL(URL(string:value)!,refresh:{refreshed=true})
  let after = try Data(contentsOf:Configuration.url)
  precondition(!refreshed && before == after && model.config.policy.limit == limit && model.config.policy.mode == mode && model.config.chargeLimitChangeID == id)
 }
 var config = Configuration(); config.historyEnabled = false; config.policy.mode = .calibration; config.calibrationCheckpoint = CalibrationCheckpoint(stage:.draining); try config.save()
 let calibrating = model()
 precondition(calibrating.calibrationPending)
 try reject("opencharge://limit?value=75",in:calibrating)
 precondition(calibrating.error != nil)
 calibrating.resumeCalibration()
 precondition(!calibrating.calibrationPending && calibrating.config.policy.mode == .calibration)
 try reject("opencharge://limit?value=75",in:calibrating)
 config.policy.mode = .automatic; config.calibrationCheckpoint = nil; try config.save()
 defaults.set(true,forKey:"settingsLock")
 let ordinary = model(); precondition(ordinary.settingsLocked)
 for text in ["nan","inf","19","101","bad"] { try reject("opencharge://limit?value="+text,in:ordinary) }
 for value in [20,100,75] {
  var refreshed = false
  ordinary.handleURL(URL(string:"opencharge://limit?value=\(value)")!,refresh:{refreshed=true})
  let saved = try Configuration.load()
  precondition(refreshed && saved.policy.limit == Double(value) && ordinary.config.policy.limit == Double(value) && ordinary.settingsLocked)
 }
 try ordinary.prepareForQuit(request:{_ in preconditionFailure("monitoring quit must not send IPC")})
 try reject("opencharge://limit?value=90",in:ordinary)
 try reject("opencharge://mode?value=paused",in:ordinary)
 defaults.removeObject(forKey:"settingsLock")
 let resetting = model()
 do { try resetting.resetSettings(request:{_ in preconditionFailure("no reset IPC")},releaseIdle:{},persist:{_ in throw Failure.storage},applyDock:{_ in});preconditionFailure("injected save failure") } catch {}
 precondition(resetting.settingsResetPending)
 try reject("opencharge://limit?value=90",in:resetting)
 try reject("opencharge://mode?value=paused",in:resetting)
 print("PASS URL automation: active/interrupted calibration, quit/reset admission and invalid limits preserve memory/file/identity without refresh; valid boundary/locked-GUI automation persists; isolated config and injected telemetry only")
}
