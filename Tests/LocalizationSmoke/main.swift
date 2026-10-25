import Foundation
import ChargeCore
import ChargeHardware

@main struct LocalizationSmoke {
 @MainActor static func main() throws {
  let language = CommandLine.arguments.last!
  let bundle = Bundle.main
  precondition(bundle.preferredLocalizations.first == language,"unexpected selected language: \(bundle.preferredLocalizations)")
  func translated(_ key: String) -> String { bundle.localizedString(forKey:key,value:nil,table:nil) }
  let pairs = [("概览",Page.overview.title),
   ("动态状态",MenuIconStyle.status.title),
   ("高耗能应用",DashboardWidget.energyApps.title),
   ("电池电压",DashboardSpecification.voltage.title),
   ("固定绿色",MagSafeMode.green.displayName),
   ("系统电池传感器",BatteryTemperatureSource.registry.displayName)]
  for (key,value) in pairs {
   precondition(value == translated(key),"a domain label bypassed localization: \(key)")
   precondition(language == "zh-Hans" ? value == key : value != key)
  }
  func expected(_ english: String, _ simplified: String, _ traditional: String) -> String {
   switch language { case "en": return english; case "zh-Hans": return simplified; case "zh-Hant": return traditional; default: preconditionFailure("unsupported test expectation") }
  }
  precondition(Page.settings.title == expected("Settings and Diagnostics", "设置与诊断", "設定與診斷"))
  precondition(ScheduleAction.calibrate.displayName == expected("Calibrate Battery", "校准电池", "校正電池"))
  let target = String(localized:"目标 \(42)%")
  precondition(target == expected("Target 42%", "目标 42%", "目標 42%"),"interpolation mismatch: \(target)")
  let oneMinute = String(localized:"\(1) 分钟"), twoMinutes = String(localized:"\(2) 分钟")
  let oneSample = String(localized:"\(1) 个本地采样"), twoSamples = String(localized:"\(2) 个本地采样")
  precondition(oneMinute == expected("1 minute", "1 分钟", "1 分鐘"))
  precondition(twoMinutes == expected("2 minutes", "2 分钟", "2 分鐘"))
  precondition(oneSample == expected("1 local sample", "1 个本地采样", "1 個本地取樣"))
  precondition(twoSamples == expected("2 local samples", "2 个本地采样", "2 個本地取樣"))
  let range = String(localized:"充电上限必须在 20–100%")
  precondition(range == translated("充电上限必须在 20–100%"),"literal percent damaged")
  let phrase = bundle.localizedString(forKey:"读取 ${applicationName} 电量",value:nil,table:"AppShortcuts")
  precondition(phrase == expected("Get the battery level in ${applicationName}", "读取 ${applicationName} 电量", "讀取 ${applicationName} 電量"))
  let appStatePhrase = bundle.localizedString(forKey:"读取 ${applicationName} 应用状态",value:nil,table:"AppShortcuts")
  precondition(appStatePhrase == expected("Get the app state in ${applicationName}", "读取 ${applicationName} 应用状态", "讀取 ${applicationName} 應用程式狀態"))
  var engine = ChargeEngine(); var policy = ChargePolicy(); policy.heatProtection = false
  let decision = engine.decide(ChargeSample(percent:50,temperature:30),policy:policy)
  precondition(decision.action == .allowCharge && decision.phase == .charging)
  precondition(decision.reason == translated("低于目标，允许充电"))
  var dischargeEngine = ChargeEngine(); var dischargePolicy = policy
  dischargePolicy.mode = .discharge; dischargePolicy.reserve = 20
  let reserve = dischargeEngine.decide(ChargeSample(percent:15,temperature:30),policy:dischargePolicy)
  precondition(reserve.action == .allowCharge)
  precondition(reserve.reason == translated("低电量保底：停止放电并充电"))

  precondition(Page.overview.rawValue == "概览")
  precondition(ChargeMode.automatic.rawValue == "automatic" && PolicyPhase.discharging.rawValue == "Discharging")
  let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
  let encoded = try encoder.encode(policy)
  let decoded = try JSONDecoder().decode(ChargePolicy.self,from:encoded)
  precondition(decoded.mode == policy.mode && decoded.limit == policy.limit && decoded.stopInSleep == policy.stopInSleep)
  let error = ChargeControlSuspension.systemSleep
  precondition(error.localizedDescription == translated("系统睡眠或控制阶段已变化，稍后重新确认"))
  print("POLICY_BASE64 " + encoded.base64EncodedString())
  print("PASS native bundle language \(language): domain labels, policy reason, error, interpolation, literal percent and stable persisted identifiers; no hardware or app UI executed")
 }
}
