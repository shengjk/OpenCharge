import Foundation
import AppKit
import SwiftUI
import ChargeCore
import ChargeHardware

@MainActor func setupWizardChecks() throws {
 precondition(ProcessInfo.processInfo.environment["OPENCHARGE_DATA_DIR"] != nil)
 let original = try Configuration.load(), provider = PolicyStateRuntime.provider
 let suite = "org.opencharge.setup-fixture."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { try? original.save(); PolicyStateRuntime.provider = provider; defaults.removePersistentDomain(forName:suite) }
 precondition(!SetupWizardPresentation.shouldShow(configurationExists:true,defaults:defaults),"upgrade must not open wizard")
 precondition(SetupWizardPresentation.shouldShow(configurationExists:false,defaults:defaults))
 precondition(SetupWizardPresentation.shouldShow(configurationExists:true,defaults:defaults),"incomplete first run remains pending")
 for state in [SetupWizardPresentation.State.skipped,.completed] {
  SetupWizardPresentation.finish(state,defaults:defaults)
  precondition(!SetupWizardPresentation.shouldShow(configurationExists:false,defaults:defaults))
 }
 var c = Configuration(); c.historyEnabled = false; try c.save()
 let service = HelperService(bundle:.main,backend:nil,legacyCheck:{false},signatureCheck:{_ in preconditionFailure("wizard must not authorize service")})
 let m = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no lock")},readBattery:{BatteryReading(percent:50,connected:true,charging:false)},helperService:service)
 let now = Date(timeIntervalSince1970:1_800_000_000)
 let answers = SetupAnswers(usage:.rarely,temperature:40,unit:.celsius,regularSwitchOff:true,automaticCalibration:true)
 func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("invalid setup accepted") } catch {} }
 var refreshes = 0
 defaults.set(true,forKey:"settingsLock")
 rejects { try m.applySetupSurvey(answers,lidClosed:false,now:now,persist:{_ in preconditionFailure("locked save")},refresh:{preconditionFailure("locked refresh")}) }
 defaults.removeObject(forKey:"settingsLock")
 m.config.policy.mode = .calibration
 rejects { try m.applySetupSurvey(answers,lidClosed:false,now:now,persist:{_ in preconditionFailure("calibration save")}) }
 m.config.policy.mode = .automatic
 let before = try JSONEncoder().encode(m.config)
 SetupWizardPresentation.finish(.pending,defaults:defaults)
 precondition(m.setupDefaultCalibration)
 rejects { try m.applySetupSurvey(answers,lidClosed:false,now:now,persist:{_ in throw CocoaError(.fileWriteNoPermission)},refresh:{preconditionFailure("failed save refresh")}) }
 let after = try JSONEncoder().encode(m.config)
 // Compare decoded objects because JSON dictionary order is not a semantic property.
 let beforeObject = try JSONSerialization.jsonObject(with:before) as! NSDictionary
 let afterObject = try JSONSerialization.jsonObject(with:after) as! NSDictionary
 precondition(beforeObject == afterObject && defaults.string(forKey:SetupWizardPresentation.key) == "pending")
 for enabled in [false,true] {
  m.config.hardwareEnabled = enabled; m.config.systemActionsEnabled = enabled
  let count = m.config.schedules.count
  try m.applySetupSurvey(answers,lidClosed:false,now:now,persist:{value in
   precondition(value.hardwareEnabled == enabled && value.systemActionsEnabled == enabled)
   try value.save()
  },refresh:{refreshes += 1})
  precondition(m.config.hardwareEnabled == enabled && m.config.policy.limit == 70 && m.config.policy.maxTemperature == 50 && m.config.policy.automaticDischarge)
  precondition(m.config.schedules.count == max(1,count) && m.config.schedules[0].name != nil)
  precondition(defaults.string(forKey:SetupWizardPresentation.key) == "completed")
 }
 precondition(refreshes == 2 && m.setupDefaultCalibration)
 m.config.schedules[0].enabled = false; precondition(!m.setupDefaultCalibration,"finished first-run metadata must not re-check calibration after it is disabled")
 m.config.hardwareEnabled = false; m.config.systemActionsEnabled = false
 // A pure view mount must neither save policy nor attempt root registration or hardware control.
 let savedBytes = try Data(contentsOf:Configuration.url)
 for page in 0...5 {
  let host = NSHostingView(rootView:SetupWizardView(model:m,initialPage:page))
  host.frame = NSRect(x:0,y:0,width:720,height:650)
  host.layoutSubtreeIfNeeded()
  precondition(host.fittingSize.width.isFinite && host.fittingSize.height.isFinite)
  if let folder = ProcessInfo.processInfo.environment["OPENCHARGE_SETUP_PREVIEW_DIR"], folder.hasPrefix("/"),
     let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
   host.cacheDisplay(in:host.bounds,to:bitmap)
   let root = URL(fileURLWithPath:folder,isDirectory:true)
   try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
   if let png = bitmap.representation(using:.png,properties:[:]) { try png.write(to:root.appendingPathComponent("setup-\(page).png")) }
  }
 }
 let unchanged = try Data(contentsOf:Configuration.url); precondition(savedBytes == unchanged)
 precondition(!service.registrationAllowed && !service.busy)
 // Save a named occurrence through the real schedule engine, retaining its title in history.
 var due = ChargeSchedule(); due.name = "Named fixture 🔋"; due.action = .limit; due.value = 75; due.date = Date().addingTimeInterval(-1)
 m.config.schedules = [due]; m.refresh()
 precondition(m.config.scheduleHistory?.last?.scheduleName == due.name && m.config.policy.limit == 75 && !m.config.hardwareEnabled)
 print("PASS setup wizard: first-run/upgrade/skip state, lock/calibration/save guards, preserved opt-ins, named schedule history, idempotent calibration and six offscreen page mounts; injected actuators/isolated files only")
}
