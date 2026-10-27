import SwiftUI
import AppKit
import ChargeCore

/// Explicit migration: existing configurations do not unexpectedly open a new wizard.
enum SetupWizardPresentation {
 enum State: String { case pending, completed, skipped }
 static let key = "setupWizardState"
 static func shouldShow(configurationExists: Bool, defaults: UserDefaults) -> Bool {
  if let stored = defaults.string(forKey:key), let state = State(rawValue:stored) { return state == .pending }
  guard !configurationExists else { return false }
  defaults.set(State.pending.rawValue,forKey:key); return true
 }
 static func finish(_ state: State, defaults: UserDefaults) { defaults.set(state.rawValue,forKey:key) }
}
@MainActor final class SetupWizardWindowDelegate: NSObject, NSWindowDelegate {
 let closed: () -> Void
 init(closed: @escaping () -> Void) { self.closed = closed }
 func windowWillClose(_ notification: Notification) { closed() }
}

struct SetupWizardView: View {
 @ObservedObject var model: ChargeModel
 @AppStorage("appearance") private var appearance = "system"
 @State private var answers: SetupAnswers
 @State private var page = 0
 @State private var previewDate = Date()
 @State private var previewLidClosed = false
 @State private var message: String?
 init(model: ChargeModel, initialPage: Int = 0) {
  self.model = model
  _page = State(initialValue:min(5,max(0,initialPage)))
  let c = model.config, metric = SetupTemperatureUnit.preferred(for:.current) == .celsius
  let ambient = min(40,max(15,c.policy.maxTemperature-10))
  _answers = State(initialValue:SetupAnswers(usage:c.policy.limit <= 75 ? .rarely : c.policy.limit <= 85 ? .sometimes : .mostly,
   temperature:metric ? ambient : ambient*9/5+32,unit:metric ? .celsius : .fahrenheit,
   regularSwitchOff:c.policy.stopInSleep,automaticCalibration:model.setupDefaultCalibration))
 }
 private var plan: SetupRecommendation? { try? SetupRecommendation(answers:answers,lidClosed:previewLidClosed,now:previewDate) }
 var body: some View {
  VStack(alignment:.leading,spacing:18) {
   HStack { Image(systemName:"bolt.shield").font(.title).presentationMint(); Text(NSLocalizedString("OpenCharge · 设置向导",comment:"")).font(.title2.bold()); Spacer(); Text(String.localizedStringWithFormat(NSLocalizedString("第 %lld / 6 步",comment:""),Int64(page+1))).presentationSecondary() }
   ProgressView(value:Double(page+1),total:6)
   ScrollView { VStack(alignment:.leading,spacing:18) {
    content
    if let message { Text(message).presentationOrange() }
   }.frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:.infinity)
   Divider()
   HStack {
    Button(NSLocalizedString("暂不设置",comment:"")) { model.finishSetupWizard(applied:false) }
    Spacer()
    if page > 0 { Button(NSLocalizedString("上一步",comment:"")) { message = nil; page -= 1 } }
    if page < 5 { Button(NSLocalizedString("下一步",comment:"")) { message = nil; if page == 4 { snapshot() }; page += 1 }.presentationProminentButton() }
    else { Button(NSLocalizedString("应用预设并完成",comment:"")) { apply() }.presentationProminentButton().disabled(plan == nil || model.settingsLocked || model.settingsResetPending || model.config.policy.mode == .calibration) }
   }
  }.padding(24).frame(minWidth:660,minHeight:570)
   .background(Color(NSColor.windowBackgroundColor))
   .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
   .environmentObject(model)
 }
 @ViewBuilder private var content: some View {
  switch page {
  case 0:
   Card(NSLocalizedString("先了解你的充电管理方式",comment:"")) {
    Text(NSLocalizedString("回答四个问题，查看建议的充电策略和可选校准计划。最后确认前不会应用这些答案。",comment:""))
    Text(NSLocalizedString("硬件控制需要单独启用。安装与注册服务可在设置中管理；向导保留你已有的控制许可。",comment:"")).presentationSecondary()
    HelperServiceView(service:model.helperService)
   }
   Card(NSLocalizedString("检查系统充电设置",comment:"")) {
    Text(NSLocalizedString("系统优化充电、系统充电上限和其他电池工具可能同时影响充电。请检查当前设置，再选择你希望使用的管理方式。",comment:""))
    HStack { Button(NSLocalizedString("打开电池设置",comment:"")) { if let url = URL(string:"x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) } }; Link(NSLocalizedString("Apple 充电设置说明",comment:""),destination:URL(string:"https://support.apple.com/102338")!) }
   }
  case 1:
   Card(NSLocalizedString("你多久会外出使用电脑？",comment:"")) {
    Picker(NSLocalizedString("外出使用频率",comment:""),selection:$answers.usage) {
     Text(NSLocalizedString("很少 · 建议上限 70%",comment:"")).tag(SetupUsage.rarely)
     Text(NSLocalizedString("有时 · 建议上限 80%",comment:"")).tag(SetupUsage.sometimes)
     Text(NSLocalizedString("经常 · 建议上限 90%",comment:"")).tag(SetupUsage.mostly)
    }.pickerStyle(.radioGroup)
   }
  case 2:
   Card(NSLocalizedString("工作环境的平均温度是多少？",comment:"")) {
    Picker(NSLocalizedString("温度单位",comment:""),selection:Binding(get:{answers.unit},set:{unit in
     guard unit != answers.unit else { return }
     answers.temperature = unit == .fahrenheit ? answers.temperature*9/5+32 : (answers.temperature-32)*5/9
     answers.unit = unit
    })) { Text("°C").tag(SetupTemperatureUnit.celsius); Text("°F").tag(SetupTemperatureUnit.fahrenheit) }.pickerStyle(.segmented)
    Slider(value:$answers.temperature,in:answers.unit == .celsius ? 15...40 : 59...104,step:1)
    Text(String(format:"%.1f %@",answers.temperature,answers.unit == .celsius ? "°C" : "°F")).font(.title2)
    Text(NSLocalizedString("温控暂停阈值按环境温度加 10°C 生成，可在充电控制页继续调整。",comment:"")).presentationSecondary()
   }
  case 3:
   Card(NSLocalizedString("你会经常关机或切换用户吗？",comment:"")) {
    Toggle(NSLocalizedString("经常关机或切换用户",comment:""),isOn:$answers.regularSwitchOff)
    Text(NSLocalizedString("此答案用于建议睡眠停充和自动放电；自动放电还会结合完成向导时的合盖状态。",comment:"")).presentationSecondary()
   }
  case 4:
   Card(NSLocalizedString("是否创建自动校准计划？",comment:"")) {
    Toggle(NSLocalizedString("创建自动校准计划",comment:""),isOn:$answers.automaticCalibration)
    Text(NSLocalizedString("很少外出时建议每两周一次，有时外出时建议每月一次；首次计划在两周后。经常外出时不新增计划。已有自动校准任务会保留。",comment:"")).presentationSecondary()
    Text(NSLocalizedString("校准需要保持供电并经历充放电过程。任务实际执行仍遵守硬件控制许可和校准条件。",comment:"")).font(.caption).presentationSecondary()
   }
  default:
   Card(NSLocalizedString("确认建议设置",comment:"")) {
    if let plan {
     let merged = plan.applying(to:model.config,calibrationName:NSLocalizedString("自动校准",comment:""))
     Text(String.localizedStringWithFormat(NSLocalizedString("充电上限 %lld%% · 航行宽度 %lld%%",comment:""),Int64(plan.limit),Int64(plan.sailingWidth)))
     HStack { Text(NSLocalizedString("航行模式",comment:"")); Spacer(); Text(merged.policy.sailing ? NSLocalizedString("开启",comment:"") : NSLocalizedString("关闭",comment:"")) }
     Text(String.localizedStringWithFormat(NSLocalizedString("热保护开启 · 暂停阈值 %@°C",comment:""),String(format:"%.1f",plan.maxTemperature)))
     Text(merged.policy.stopInSleep ? NSLocalizedString("睡眠停充：开启",comment:"") : NSLocalizedString("睡眠停充：关闭",comment:""))
     Text(plan.automaticDischarge ? NSLocalizedString("自动放电：开启",comment:"") : NSLocalizedString("自动放电：关闭",comment:""))
     Text(NSLocalizedString("控制基准：macOS 电量",comment:""))
     Text(model.config.hardwareEnabled ? NSLocalizedString("硬件控制已启用",comment:"") : NSLocalizedString("只读监测",comment:""))
     if merged.schedules.count > model.config.schedules.count, let task = merged.schedules.last {
      Text(String.localizedStringWithFormat(NSLocalizedString("新增自动校准：%@ · %@",comment:""),DateDisplay.string(task.date),task.repeatRule.displayName))
     } else if let existing = merged.schedules.first(where:{$0.id == merged.setupCalibrationScheduleID && $0.action == .calibrate}) {
      Text(String.localizedStringWithFormat(NSLocalizedString("已有自动校准：%@ · %@ · %@",comment:""),DateDisplay.string(existing.date),existing.repeatRule.displayName,existing.enabled ? NSLocalizedString("开启",comment:"") : NSLocalizedString("关闭",comment:"")))
     } else { Text(NSLocalizedString("保留已有任务，不新增校准任务",comment:"")) }
    }
    Text(NSLocalizedString("未列出的策略保持原设置。已启用的充电控制会使用新策略；未启用时继续监测。",comment:"")).font(.caption).presentationSecondary()
    if model.config.policy.mode == .calibration { Text(NSLocalizedString("请先结束校准，再应用设置向导",comment:"")).presentationOrange() }
    ChargeSettingsLockNotice(model:model)
   }
  }
 }
 private func snapshot() { previewDate = Date(); previewLidClosed = model.setupLidClosed() }
 private func apply() {
  if let first = plan?.firstCalibration, first <= Date() {
   snapshot(); message = NSLocalizedString("预览已过期，请确认更新后的预设",comment:""); return
  }
  let latest = model.setupLidClosed()
  guard latest == previewLidClosed else { snapshot(); message = NSLocalizedString("合盖状态已改变，请确认更新后的预设",comment:""); return }
  do { try model.applySetupSurvey(answers,lidClosed:latest,now:previewDate); model.finishSetupWizard(applied:true) }
  catch { message = error.localizedDescription }
 }
}
