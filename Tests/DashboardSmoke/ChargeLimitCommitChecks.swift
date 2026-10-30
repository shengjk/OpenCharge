import Foundation
import ChargeCore
import ChargeHardware

@MainActor func chargeLimitCommitChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original=try Configuration.load(),provider=PolicyStateRuntime.provider
 let suite="org.opencharge.limit-commit."+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!
 defer { try? original.save();PolicyStateRuntime.provider=provider;defaults.removePersistentDomain(forName:suite) }
 var config=Configuration();config.historyEnabled=false;config.notifications=false;config.systemActionsEnabled=false
 config.policy.mode = .calibration;config.calibrationCheckpoint=CalibrationCheckpoint(stage:.draining);try config.save()
 let model=ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{BatteryReading(percent:50,connected:true,charging:false)})
 func reject() throws {
  let data=try Data(contentsOf:Configuration.url),limit=model.config.policy.limit,id=model.config.chargeLimitChangeID
  precondition(!model.setChargeLimitFromGUI(65))
  let after=try Data(contentsOf:Configuration.url)
  precondition(after==data && model.config.policy.limit==limit && model.config.chargeLimitChangeID==id)
 }
 precondition(model.calibrationPending);try reject()
 model.resumeCalibration();precondition(!model.calibrationPending && model.config.policy.mode == .calibration);try reject()
 model.changeMode(.automatic)
 defaults.set(true,forKey:"settingsLock");try reject();defaults.removeObject(forKey:"settingsLock")
 precondition(model.setChargeLimitFromGUI(65))
 model.applyChargeSettingsFromGUI(presentLowLimitNotice:{})
 let saved=try Configuration.load();precondition(saved.policy.limit==65 && !saved.hardwareEnabled)
 enum Failure:Error {case storage}
 do { try model.resetSettings(request:{_ in preconditionFailure("no IPC")},releaseIdle:{},persist:{_ in throw Failure.storage},applyDock:{_ in});preconditionFailure("storage failure required") } catch {}
 precondition(model.settingsResetPending);try reject()
 print("PASS GUI charge-limit commit: active/interrupted calibration, administrator lock and pending reset reject stale edits without disk/identity changes; ordinary commit persists; fake battery/no control")
}
