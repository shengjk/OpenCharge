import Foundation
import ChargeCore

@MainActor func ledEncodingChecks(defaults: UserDefaults) throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = original; fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.policy = ChargePolicy(); fixture.calibrationCheckpoint = nil
 fixture.magSafeMode = .system; fixture.magSafeOffDuringSleep = false
 try fixture.save()
 for mode in [MagSafeMode.green, .orangeBlinking] {
  for capability in ["magSafe:legacy", "magSafeEncoding:aclcNativeV2", "magSafe:unavailable"] {
   let modern = capability == "magSafeEncoding:aclcNativeV2"
   let model = ChargeModel(dashboardDefaults: defaults, observeLid: false,
    screenLockRequest: { preconditionFailure("no locks in LED encoding fixture") })
   model.config.magSafeMode = mode
   var events: [String] = []
   model.updateMagSafe(request: { command in
    events.append(command)
    return command == "capabilities" ? capability : "fixture acknowledgement"
   })
   let expected = modern ? ["capabilities", "magSafeSleepOff", mode == .green ? "magSafeGreen" : "magSafeBlinkOrange"] : ["capabilities"]
   precondition(events == expected && !model.config.hardwareEnabled)
   if capability == "magSafe:unavailable" { precondition(model.magSafeStatus.contains("未检测到")) }
   if modern {
    model.config.magSafeMode = .system
    model.updateMagSafe(request: { events.append($0); return "fixture release" })
    precondition(events.last == "magSafeRestore")
   }
   precondition(!model.needsQuitPreparation)
  }
 }
 print("Correct green/native-blink capability precedes every LED setter; legacy service remains read-only; all IPC injected")
}
