import Foundation
import AppKit
import ChargeCore
import ChargeHardware

@MainActor func lowChargeLimitNoticeChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.low-limit-check."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); defaults.removePersistentDomain(forName:suite); PolicyStateRuntime.provider = provider }
 let alert = LowChargeLimitNotice.makeAlert()
 precondition(alert.alertStyle == .informational && alert.buttons.count == 1 && !alert.messageText.isEmpty && !alert.informativeText.isEmpty)
 var shown = 0
 for limit in [Double.nan,.infinity,19,75.01,100] {
  LowChargeLimitNotice.showIfNeeded(limit:limit,defaults:defaults,present:{shown += 1})
 }
 precondition(shown == 0 && defaults.object(forKey:LowChargeLimitNotice.key) == nil)
 LowChargeLimitNotice.showIfNeeded(limit:75,defaults:defaults) {
  shown += 1
  LowChargeLimitNotice.showIfNeeded(limit:20,defaults:defaults,present:{preconditionFailure("reentrant alert")})
 }
 precondition(shown == 1)
 let reopened = UserDefaults(suiteName:suite)!
 LowChargeLimitNotice.showIfNeeded(limit:20,defaults:reopened,present:{preconditionFailure("repeat after reopening")})
 AppPreferenceReset.removeOverrides(from:defaults)
 precondition(defaults.object(forKey:LowChargeLimitNotice.key) == nil)
 var config = Configuration(); config.historyEnabled = false; config.notifications = false; config.systemActionsEnabled = false; try config.save()
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,readBattery:{BatteryReading(percent:50,connected:true,charging:false)})
 defaults.set(true,forKey:"settingsLock")
 model.applyChargeSettingsFromGUI(presentLowLimitNotice:{preconditionFailure("locked GUI")})
 precondition(defaults.object(forKey:LowChargeLimitNotice.key) == nil)
 defaults.removeObject(forKey:"settingsLock")
 model.setChargeLimitFromGUI(75)
 model.applyChargeSettingsFromGUI(presentLowLimitNotice:{shown += 1})
 precondition(shown == 2 && !model.config.hardwareEnabled && model.config.policy.limit == 75)
 let saved = try Data(contentsOf:Configuration.url)
 model.showLowChargeLimitNotice(present:{preconditionFailure("repeated model notice")})
 let unchanged = try Data(contentsOf:Configuration.url); precondition(unchanged == saved)
 AppPreferenceReset.removeOverrides(from:defaults)
 model.config.policy.mode = .calibration
 model.showLowChargeLimitNotice(present:{preconditionFailure("calibration")})
 precondition(defaults.object(forKey:LowChargeLimitNotice.key) == nil)
 model.config.policy.mode = .automatic
 try model.prepareForQuit(request:{_ in preconditionFailure("no IPC")})
 model.showLowChargeLimitNotice(present:{preconditionFailure("quit preparation")})
 precondition(defaults.object(forKey:LowChargeLimitNotice.key) == nil)
 print("PASS one-time low-limit notice: inclusive 75 boundary, invalid limits, reentrancy, persisted acknowledgement/reset, locked GUI and calibration/quit gates; simulated battery and presenter only")
}
