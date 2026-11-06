import Darwin
import SwiftUI
import ChargeHardware

/// Owns only the user-requested idle assertion. Charge-policy assertions have
/// their own owner and are never renewed or released here.
@MainActor final class ManualAwakeSession: ObservableObject {
 @Published private(set) var active = false
 @Published private(set) var remainingMinutes: Int?
 @Published private(set) var error: String?
 private let makeController: (Bool) -> SleepController
 private let clock: () -> TimeInterval
 private var controller: SleepController?
 private var deadline: TimeInterval?
 private var timer: Timer?
 private var stopRequested = false

 init(makeController: @escaping (Bool) -> SleepController = {
  SleepController(keepDisplayAwake: $0, name: "OpenCharge manual keep-awake")
 }, clock: @escaping () -> TimeInterval = { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000 }) {
  self.makeController = makeController; self.clock = clock
 }

 func start(minutes: Int?, percent: Double, connected: Bool, floor: Int, endsOnBattery: Bool, keepDisplayAwake: Bool) {
  if let minutes, !(1...1440).contains(minutes) {
   error = NSLocalizedString("保活时长须为 1 至 1440 分钟", comment: ""); return
  }
  guard (0...100).contains(percent), percent > Double(floor), connected || !endsOnBattery else {
   error = NSLocalizedString("电量或电源条件不满足，无法开始保活", comment: ""); return
  }
  guard !stopRequested else { return }
  do {
   if controller == nil {
    let next = makeController(keepDisplayAwake)
    try next.setPreventIdleSleep(true)
    controller = next
   }
   active = true; error = nil; timer?.invalidate()
   remainingMinutes = minutes
   deadline = minutes.map { clock() + Double($0) * 60 }
   timer = nil
   if let minutes {
    let nextTimer = Timer(timeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
     MainActor.assumeIsolated { self?.updateTime() }
    }
    timer = nextTimer
    RunLoop.main.add(nextTimer, forMode: .common)
   }
  } catch { self.error = error.localizedDescription }
 }

 func reportReadFailure(_ error: Error) {
  do {
   if active { try release() }
   self.error = error.localizedDescription
  } catch { self.error = error.localizedDescription }
 }

 func observe(percent: Double, connected: Bool, floor: Int, endsOnBattery: Bool) {
  guard active else { return }
  if stopRequested || !(0...100).contains(percent) || percent <= Double(floor) || (!connected && endsOnBattery) {
   stop()
  } else {
   updateTime()
  }
 }

 private func updateTime() {
  guard let deadline else { return }
  let remaining = deadline - clock()
  if remaining <= 0 { stop() }
  else { remainingMinutes = Int(ceil(remaining / 60)) }
 }

 func stop() {
  do { try release() } catch { self.error = error.localizedDescription }
 }

 func release() throws {
  stopRequested = true
  try controller?.setPreventIdleSleep(false)
  timer?.invalidate(); timer = nil
  controller = nil; deadline = nil; remainingMinutes = nil; active = false
  stopRequested = false; error = nil
 }
}

struct ManualAwakeView: View {
 let model: ChargeModel
 @ObservedObject var session: ManualAwakeSession
 @State private var custom = false
 @State private var customMinutes = "60"

 var body: some View {
  VStack(alignment: .leading, spacing: 6) {
   if let minutes = session.remainingMinutes {
    Text(String.localizedStringWithFormat(NSLocalizedString("保活剩余 %lld 分钟", comment: ""), Int64(minutes)))
     .font(.caption.monospacedDigit())
   } else if session.active {
    Text(NSLocalizedString("不限时保活已开启", comment: "")).font(.caption)
   } else {
    Text(NSLocalizedString("临时阻止空闲睡眠", comment: "")).font(.caption).presentationSecondary()
   }
   HStack {
    Menu(NSLocalizedString("保活时长", comment: "")) {
     Button(NSLocalizedString("30 分钟", comment: "")) { model.startManualAwake(minutes: 30) }
     Button(NSLocalizedString("1 小时", comment: "")) { model.startManualAwake(minutes: 60) }
     Button(NSLocalizedString("3 小时", comment: "")) { model.startManualAwake(minutes: 180) }
     Button(NSLocalizedString("不限时", comment: "")) { model.startManualAwake(minutes: nil) }
     Button(NSLocalizedString("自定义保活时长", comment: "")) { custom = true }
    }
    if session.active {
     Button(NSLocalizedString("结束保活", comment: "")) { session.stop() }
    }
   }
   if custom {
    TextField(NSLocalizedString("保活时长（分钟）", comment: ""), text: $customMinutes)
    HStack {
     Button(NSLocalizedString("开始保活", comment: "")) {
      guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespaces)), (1...1440).contains(minutes) else { return }
      model.startManualAwake(minutes: minutes)
      custom = false
     }.disabled(Int(customMinutes.trimmingCharacters(in: .whitespaces)).map { !(1...1440).contains($0) } ?? true)
     Button(NSLocalizedString("取消", comment: "")) { custom = false }
    }
   }
   if let error = session.error {
    Text(error).font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
   }
  }
 }
}
