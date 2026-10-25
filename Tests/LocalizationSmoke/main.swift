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
  let target = String(localized:"目标 \(42)%")
  precondition(target == (language == "en" ? "Target 42%" : "目标 42%"),"interpolation mismatch: \(target)")
  let oneMinute = String(localized:"\(1) 分钟"), twoMinutes = String(localized:"\(2) 分钟")
  let oneSample = String(localized:"\(1) 个本地采样"), twoSamples = String(localized:"\(2) 个本地采样")
  precondition(oneMinute == (language == "en" ? "1 minute" : "1 分钟"))
  precondition(twoMinutes == (language == "en" ? "2 minutes" : "2 分钟"))
  precondition(oneSample == (language == "en" ? "1 local sample" : "1 个本地采样"))
  precondition(twoSamples == (language == "en" ? "2 local samples" : "2 个本地采样"))
  let range = String(localized:"充电上限必须在 20–100%")
  precondition(range == translated("充电上限必须在 20–100%"),"literal percent damaged")
  let phrase = bundle.localizedString(forKey:"读取 ${applicationName} 电量",value:nil,table:"AppShortcuts")
  precondition(phrase == (language == "en" ? "Get the battery level in ${applicationName}" : "读取 ${applicationName} 电量"))
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
