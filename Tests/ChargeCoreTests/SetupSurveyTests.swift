import XCTest
@testable import ChargeCore

final class SetupSurveyTests: XCTestCase {
 let now = Date(timeIntervalSince1970:1_800_000_000)
 func answers(_ usage: SetupUsage = .rarely, temperature: Double = 25, unit: SetupTemperatureUnit = .celsius, regular: Bool = false, automatic: Bool = true) -> SetupAnswers {
  SetupAnswers(usage:usage,temperature:temperature,unit:unit,regularSwitchOff:regular,automaticCalibration:automatic)
 }
 func testRegionalTemperatureUnitsDoNotChangeInterfaceLanguage() {
  XCTAssertEqual(SetupTemperatureUnit.preferred(for:Locale(identifier:"en_US")),.fahrenheit)
  XCTAssertEqual(SetupTemperatureUnit.preferred(for:Locale(identifier:"en_GB")),.celsius)
  XCTAssertEqual(SetupTemperatureUnit.preferred(for:Locale(identifier:"zh_CN")),.celsius)
 }
 func testUsageTemperatureLidAndRecurringRules() {
  for (usage,limit,width,rule) in [(SetupUsage.rarely,70.0,5.0,RepeatRule.biweekly),(.sometimes,80,5,.monthly),(.mostly,90,10,.once)] {
   for regular in [false,true] { for closed in [false,true] {
    let plan = try! SetupRecommendation(answers:answers(usage,regular:regular),lidClosed:closed,now:now)
    XCTAssertEqual(plan.limit,limit); XCTAssertEqual(plan.sailingWidth,width); XCTAssertEqual(plan.maxTemperature,35)
    XCTAssertEqual(plan.stopInSleep,regular); XCTAssertEqual(plan.automaticDischarge,regular && !closed)
    XCTAssertEqual(plan.calibrationRepeat,usage == .mostly ? nil : rule)
    XCTAssertEqual(plan.firstCalibration,usage == .mostly ? nil : now.addingTimeInterval(1209600))
   } }
  }
  XCTAssertNil(try! SetupRecommendation(answers:answers(automatic:false),lidClosed:false,now:now).calibrationRepeat)
 }
 func testUnitConversionEntirePickerRangeAndInvalidValues() {
  for value in 15...40 {
   let c = try! SetupRecommendation(answers:answers(temperature:Double(value)),lidClosed:false,now:now)
   let f = try! SetupRecommendation(answers:answers(temperature:Double(value)*9/5+32,unit:.fahrenheit),lidClosed:false,now:now)
   XCTAssertEqual(c.maxTemperature,Double(value+10)); XCTAssertEqual(c.maxTemperature,f.maxTemperature)
   var policy = ChargePolicy(); policy.maxTemperature = c.maxTemperature; policy.normalize(); XCTAssertEqual(policy.maxTemperature,c.maxTemperature)
  }
  let fraction = try! SetupRecommendation(answers:answers(temperature:73,unit:.fahrenheit),lidClosed:false,now:now)
  XCTAssertEqual(fraction.maxTemperature,Double(Float((73.0-32)*5/9+10)))
  for unit in SetupTemperatureUnit.allCases {
   for value in [-Double.infinity,Double.infinity,Double.nan,0,200] {
    do { _ = try SetupRecommendation(answers:answers(temperature:value,unit:unit),lidClosed:false,now:now); XCTFail("invalid temperature accepted") } catch {}
   }
  }
  for time in [Double.nan,Double.infinity,1e300] {
   do { _ = try SetupRecommendation(answers:answers(),lidClosed:false,now:Date(timeIntervalSince1970:time)); XCTFail("invalid date") } catch {}
  }
 }
 func testApplicationPreservesUnrelatedPolicyPermissionsHistoryAndExistingTasks() {
  var original = Configuration(); original.hardwareEnabled = false; original.systemActionsEnabled = false
  original.policy.sailing = false; original.policy.stopOnQuit = true; original.policy.mode = .paused
  original.lastCalibration = now; original.schedules = [ChargeSchedule()]
  let plan = try! SetupRecommendation(answers:answers(temperature:40,regular:true),lidClosed:false,now:now)
  let next = plan.applying(to:original,calibrationName:"Automatic Calibration")
  XCTAssertFalse(next.hardwareEnabled); XCTAssertEqual(next.systemActionsEnabled,false)
  XCTAssertFalse(next.policy.sailing); XCTAssertTrue(next.policy.stopOnQuit); XCTAssertEqual(next.policy.mode,.paused)
  XCTAssertEqual(next.policy.maxTemperature,50); XCTAssertEqual(next.lastCalibration,now)
  XCTAssertEqual(next.schedules.count,2); XCTAssertEqual(next.schedules[0].id,original.schedules[0].id)
  XCTAssertEqual(next.schedules[1].name,"Automatic Calibration"); XCTAssertEqual(next.schedules[1].action,.calibrate)
  XCTAssertEqual(next.schedules[1].repeatRule,.biweekly); XCTAssertEqual(next.schedules[1].date,now.addingTimeInterval(1209600))
  XCTAssertEqual(next.setupCalibrationScheduleID,next.schedules[1].id)
 }
 func testStableIdentityAndLocalizedNamesDeduplicateWithoutReenablingOrDeleting() {
  let plan = try! SetupRecommendation(answers:answers(),lidClosed:false,now:now)
  var c = plan.applying(to:Configuration(),calibrationName:"Automatic Calibration")
  let id = c.schedules[0].id, date = c.schedules[0].date
  c.schedules[0].name = "User renamed"; c.schedules[0].enabled = false; c.schedules[0].repeatRule = .monthly
  let next = plan.applying(to:c,calibrationName:"自动校准")
  XCTAssertEqual(next.schedules.count,1); XCTAssertEqual(next.schedules[0].id,id); XCTAssertFalse(next.schedules[0].enabled)
  XCTAssertEqual(next.schedules[0].name,"User renamed"); XCTAssertEqual(next.schedules[0].repeatRule,.monthly); XCTAssertEqual(next.schedules[0].date,date)
  c.setupCalibrationScheduleID = nil; c.schedules[0].name = " AUTOMATIC CALIBRATION "
  XCTAssertEqual(plan.applying(to:c,calibrationName:"自动校准").schedules.count,1)
  let off = try! SetupRecommendation(answers:answers(.mostly,automatic:false),lidClosed:false,now:now)
  XCTAssertEqual(off.applying(to:next,calibrationName:"自动校准").schedules.count,1)
 }
 func testNamedSchedulesAndExecutionHistoryRemainBackwardCompatibleAndPortable() {
  var task = ChargeSchedule(); task.name = "  Unicode 任务 🔋  "
  XCTAssertEqual(task.displayTitle,"Unicode 任务 🔋")
  let copy = try! JSONDecoder().decode(ChargeSchedule.self,from:JSONEncoder().encode(task)); XCTAssertEqual(copy.name,task.name)
  var object = try! JSONSerialization.jsonObject(with:JSONEncoder().encode(task)) as! [String:Any]; object.removeValue(forKey:"name")
  let old = try! JSONDecoder().decode(ChargeSchedule.self,from:JSONSerialization.data(withJSONObject:object)); XCTAssertNil(old.name); XCTAssertEqual(old.displayTitle,old.action.displayName)
  let run = ScheduleExecution(scheduleID:task.id,action:task.action,scheduledAt:now,result:"fixture",scheduleName:task.name)
  let history = try! JSONDecoder().decode(ScheduleExecution.self,from:JSONEncoder().encode(run)); XCTAssertEqual(history.displayTitle,"Unicode 任务 🔋")
  var c = Configuration(); c.schedules = [task]
  let restored = try! ConfigurationBackup.restored(from:ConfigurationBackup(configuration:c).encoded()); XCTAssertEqual(restored.schedules[0].name,task.name); XCTAssertFalse(restored.schedules[0].enabled)
 }
}
