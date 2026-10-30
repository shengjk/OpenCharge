import Foundation
import AppKit
import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func targetDischargeChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.target-discharge."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); PolicyStateRuntime.provider = provider; defaults.removePersistentDomain(forName:suite) }
 var base = Configuration(); base.historyEnabled = false; base.notifications = false; base.systemActionsEnabled = false; try base.save()
 var sample = BatteryReading(percent:80,connected:true,charging:false,physicalAdapterConnected:true)
 var telemetryFails = false, refreshes = 0
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no locks")},readBattery:{if telemetryFails {throw HelperError.unavailable};return sample})
 func bytes() throws -> Data { try JSONSerialization.data(withJSONObject:JSONSerialization.jsonObject(with:JSONEncoder().encode(model.config)),options:.sortedKeys) }
 func reject(_ target: Double = 40) throws {
  let before = try bytes(), disk = try Data(contentsOf:Configuration.url)
  precondition(!model.startTargetDischargeFromGUI(target,persist:{_ in preconditionFailure("rejected request saved")},refresh:{preconditionFailure("rejected request refreshed")}))
  let after = try bytes();precondition(before == after)
  let diskAfter = try Data(contentsOf:Configuration.url); precondition(disk == diskAfter)
 }
 try reject() // The action cannot silently enable hardware control.
 model.config.hardwareEnabled = true
 for target in [Double.nan,.infinity,19,101,40.5,80,100] { try reject(target) }
 defaults.set(true,forKey:"settingsLock");try reject();defaults.removeObject(forKey:"settingsLock")
 model.config.policy.mode = .calibration;try reject();model.config.policy.mode = .automatic
 model.config.policy.automaticDischarge = true;try reject();model.config.policy.automaticDischarge = false
 model.config.policy.reserve = 40;try reject(30);model.config.policy.reserve = 15
 sample.physicalAdapterConnected = false;try reject();sample.physicalAdapterConnected = true
 telemetryFails = true;try reject();telemetryFails = false
 for invalid in [Double.nan,-1,101] { sample.percent = invalid; try reject() };sample.percent = 80
 model.config.policy.useHardwarePercent = true;try reject()
 sample.hardwarePercent = 39;try reject()
 sample.hardwarePercent = 70
 model.config.policy.pauseAtCurrent = true;model.config.calibrationCheckpoint = CalibrationCheckpoint(stage:.draining)
 model.config.policy.departure = Date().addingTimeInterval(100)
 let beforeSaveFailure = try bytes()
 precondition(!model.startTargetDischargeFromGUI(40,persist:{_ in throw HelperError.unavailable},refresh:{preconditionFailure("failed save refreshed")}))
 let afterSaveFailure = try bytes();precondition(beforeSaveFailure == afterSaveFailure)
 precondition(model.startTargetDischargeFromGUI(40,refresh:{refreshes += 1}))
 let saved = try Configuration.load()
 precondition(saved.hardwareEnabled && saved.policy.limit == 40 && saved.policy.mode == .discharge && saved.policy.pauseAtCurrent == nil && saved.calibrationCheckpoint == nil && saved.policy.departure == nil && !saved.policy.automaticDischarge && refreshes == 1)
 model.evaluatePolicy(ChargeSample(percent:70,temperature:30,connected:true));precondition(model.decision.action == .forceDischarge && model.decision.effectiveLimit == 40)
 model.evaluatePolicy(ChargeSample(percent:40,temperature:30,connected:true));precondition(model.decision.action == .inhibitCharge && model.config.policy.mode == .automatic)
 model.config.policy.useHardwarePercent = false
 precondition(model.startTargetDischargeFromGUI(35,refresh:{refreshes += 1}))
 let beforeStopFailure = try bytes()
 precondition(!model.stopTargetDischargeFromGUI(persist:{_ in throw HelperError.unavailable},refresh:{preconditionFailure("failed stop save refreshed")}))
 let afterStopFailure = try bytes();precondition(beforeStopFailure == afterStopFailure)
 precondition(model.stopTargetDischargeFromGUI(refresh:{refreshes += 1}))
 precondition(model.config.policy.mode == .paused && model.config.policy.limit == 35 && refreshes == 3)
 model.evaluatePolicy(ChargeSample(percent:70,temperature:30,connected:true));precondition(model.decision.action == .inhibitCharge)
 // Mounting the card only stages its draft and must leave disk and policy unchanged.
 let disk = try Data(contentsOf:Configuration.url)
 let host = NSHostingView(rootView:TargetDischargeCard(model:model));host.frame = NSRect(x:0,y:0,width:680,height:480);host.layoutSubtreeIfNeeded()
 let afterMount = try Data(contentsOf:Configuration.url);precondition(disk == afterMount && host.fittingSize.height.isFinite)
 if let folder = ProcessInfo.processInfo.environment["OPENCHARGE_DISCHARGE_PREVIEW_DIR"], folder.hasPrefix("/"),let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
  host.cacheDisplay(in:host.bounds,to:bitmap)
  let url=URL(fileURLWithPath:folder,isDirectory:true);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
  if let data=bitmap.representation(using:.png,properties:[:]) { try data.write(to:url.appendingPathComponent("target-discharge.png")) }
 }
 model.config.hardwareEnabled = false
 print("PASS target discharge card: fresh adapter/percentage, range/reserve/lock/calibration/automatic mode guards, save failure, shared target, stale-state cleanup, target completion, stop-to-pause and nonmutating mount; isolated configuration and injected refresh, no real helper actions")
}
