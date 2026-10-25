import SwiftUI
import AppKit
import Charts
import ServiceManagement
import UserNotifications
import IOKit
import UniformTypeIdentifiers
import ChargeCore
import ChargeHardware

struct ScheduleView: View {
 @EnvironmentObject var m: ChargeModel
 @State private var draft = ChargeSchedule()
 @State private var editing = false
 var body: some View {
  Card(editing ? NSLocalizedString("编辑任务", comment: "") : NSLocalizedString("新增任务", comment: "")) {
   Toggle(NSLocalizedString("唤醒后补执行错过的任务", comment: ""), isOn: Binding(get: { m.config.runMissedTasks ?? true }, set: { m.config.runMissedTasks = $0; m.save() }))
   DatePicker(NSLocalizedString("运行时间", comment: ""), selection: $draft.date)
   Picker(NSLocalizedString("操作", comment: ""), selection: $draft.action) { ForEach(ScheduleAction.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   if draft.action == .pause { Text(NSLocalizedString("执行时按选定控制电量设置上限并暂停；电量低于 20%、读数不可用或当前状态不适用时跳过，并记录原因。已中断的校准仍需手动继续或取消。", comment: "")).font(.caption).presentationSecondary() }
   if draft.action == .limit || draft.action == .discharge { Stepper(String.localizedStringWithFormat(NSLocalizedString("目标 %lld%%", comment: ""), Int64(Int(draft.value))), value: $draft.value, in: 20...100) }
   Picker(NSLocalizedString("重复", comment: ""), selection: $draft.repeatRule) { ForEach(RepeatRule.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   HStack {
    Button(editing ? NSLocalizedString("保存修改", comment: "") : NSLocalizedString("添加任务", comment: "")) { m.config.saveSchedule(draft); m.save(); draft = ChargeSchedule(); editing = false }.presentationProminentButton().presentationTint(PresentationPalette.mint)
    if editing { Button(NSLocalizedString("取消编辑", comment: "")) { draft = ChargeSchedule(); editing = false } }
   }
   if !editing { HStack {
    Text(NSLocalizedString("快捷模板", comment: "")).font(.caption).presentationSecondary()
    Button(NSLocalizedString("工作日 80%", comment: "")) { draft = ChargeSchedule(); draft.action = .limit; draft.value = 80; draft.repeatRule = .weekdays }
    Button(NSLocalizedString("周末充满", comment: "")) { draft = ChargeSchedule(); draft.action = .topUp; draft.repeatRule = .weekly; draft.date = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 0, weekday: 7), matchingPolicy: .nextTime) ?? Date() }
   } }
  }
  Card(NSLocalizedString("已安排", comment: "")) {
   if m.config.schedules.isEmpty { Label(NSLocalizedString("没有任务。为下次出行安排一次充满。", comment: ""), systemImage: "calendar.badge.plus").presentationSecondary().padding(.vertical) }
   ForEach($m.config.schedules) { $s in HStack { Toggle("", isOn: $s.enabled).labelsHidden().onChange(of: s.enabled) { _ in m.save() }; VStack(alignment: .leading) { Text(s.action.displayName).font(.headline); Text("\(DateDisplay.string(s.date)) · \(s.repeatRule.displayName)").font(.caption).presentationSecondary() }; Spacer(); Button(NSLocalizedString("编辑", comment: "")) { draft = s; editing = true }; DestructiveButton { if draft.id == s.id { draft = ChargeSchedule(); editing = false }; m.config.schedules.removeAll { $0.id == s.id }; m.save() } label: { Image(systemName: "trash") } } }
   DestructiveButton(NSLocalizedString("清空全部任务", comment: "")) { m.config.schedules = []; draft = ChargeSchedule(); editing = false; m.save() }
   Text(NSLocalizedString("应用运行时每 10 秒检查。睡眠期间不执行；唤醒后每个逾期任务仅补执行一次。", comment: "")).font(.caption).presentationSecondary()
  }
  Card(NSLocalizedString("执行历史", comment: "")) {
   if (m.config.scheduleHistory ?? []).isEmpty { Text(NSLocalizedString("任务执行后会记录结果。", comment: "")).presentationSecondary() }
   ForEach(Array((m.config.scheduleHistory ?? []).suffix(30).reversed())) { run in
    VStack(alignment: .leading, spacing: 4) { Text("\(run.action.displayName) · \(DateDisplay.string(run.executedAt))").font(.caption); Text(run.result).font(.caption).presentationSecondary() }
   }
  }
 }
}
