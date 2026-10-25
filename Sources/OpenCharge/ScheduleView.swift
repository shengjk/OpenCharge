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
  Card(editing ? String(localized:"编辑任务") : String(localized:"新增任务")) {
   Toggle(String(localized:"唤醒后补执行错过的任务"), isOn: Binding(get: { m.config.runMissedTasks ?? true }, set: { m.config.runMissedTasks = $0; m.save() }))
   DatePicker(String(localized:"运行时间"), selection: $draft.date)
   Picker(String(localized:"操作"), selection: $draft.action) { ForEach(ScheduleAction.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   if draft.action == .pause { Text(String(localized:"执行时按选定控制电量设置上限并暂停；电量低于 20%、读数不可用或当前状态不适用时跳过，并记录原因。已中断的校准仍需手动继续或取消。")).font(.caption).foregroundStyle(.secondary) }
   if draft.action == .limit || draft.action == .discharge { Stepper(String(localized:"目标 \(Int(draft.value))%"), value: $draft.value, in: 20...100) }
   Picker(String(localized:"重复"), selection: $draft.repeatRule) { ForEach(RepeatRule.allCases, id: \.self) { Text($0.displayName).tag($0) } }
   HStack {
    Button(editing ? String(localized:"保存修改") : String(localized:"添加任务")) { m.config.saveSchedule(draft); m.save(); draft = ChargeSchedule(); editing = false }.buttonStyle(.borderedProminent).tint(.mint)
    if editing { Button(String(localized:"取消编辑")) { draft = ChargeSchedule(); editing = false } }
   }
   if !editing { HStack {
    Text(String(localized:"快捷模板")).font(.caption).foregroundStyle(.secondary)
    Button(String(localized:"工作日 80%")) { draft = ChargeSchedule(); draft.action = .limit; draft.value = 80; draft.repeatRule = .weekdays }
    Button(String(localized:"周末充满")) { draft = ChargeSchedule(); draft.action = .topUp; draft.repeatRule = .weekly; draft.date = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 0, weekday: 7), matchingPolicy: .nextTime) ?? Date() }
   } }
  }
  Card(String(localized:"已安排")) {
   if m.config.schedules.isEmpty { Label(String(localized:"没有任务。为下次出行安排一次充满。"), systemImage: "calendar.badge.plus").foregroundStyle(.secondary).padding(.vertical) }
   ForEach($m.config.schedules) { $s in HStack { Toggle("", isOn: $s.enabled).labelsHidden().onChange(of: s.enabled) { _ in m.save() }; VStack(alignment: .leading) { Text(s.action.displayName).font(.headline); Text("\(s.date.formatted()) · \(s.repeatRule.displayName)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(String(localized:"编辑")) { draft = s; editing = true }; Button(role: .destructive) { if draft.id == s.id { draft = ChargeSchedule(); editing = false }; m.config.schedules.removeAll { $0.id == s.id }; m.save() } label: { Image(systemName: "trash") } } }
   Button(String(localized:"清空全部任务"), role: .destructive) { m.config.schedules = []; draft = ChargeSchedule(); editing = false; m.save() }
   Text(String(localized:"应用运行时每 10 秒检查。睡眠期间不执行；唤醒后每个逾期任务仅补执行一次。")).font(.caption).foregroundStyle(.secondary)
  }
  Card(String(localized:"执行历史")) {
   if (m.config.scheduleHistory ?? []).isEmpty { Text(String(localized:"任务执行后会记录结果。")).foregroundStyle(.secondary) }
   ForEach(Array((m.config.scheduleHistory ?? []).suffix(30).reversed())) { run in
    VStack(alignment: .leading, spacing: 4) { Text("\(run.action.displayName) · \(run.executedAt.formatted())").font(.caption); Text(run.result).font(.caption).foregroundStyle(.secondary) }
   }
  }
 }
}
