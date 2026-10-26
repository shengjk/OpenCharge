import Foundation
import ChargeCore
import ChargeHardware

@MainActor func firmwareInspectionChecks(defaults: UserDefaults) throws {
 var config = Configuration(); config.historyEnabled = false; try config.save()
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{preconditionFailure("no lock")},readBattery:{ BatteryReading(percent:50,connected:true,charging:false) })
 let baseline = try Data(contentsOf:Configuration.url)
 let capabilities = "firmwareProtocol:fixedV1, firmwareRead:CH0B+BCLM, firmwareWrite:fixedV1, chargeRecovery:ready, internalBattery:present"
 var calls: [String] = []
 for unavailable in ["chargeControl:CHTE",capabilities.replacingOccurrences(of:"fixedV1",with:"fixedV2"),capabilities.replacingOccurrences(of:"ready",with:"pending"),capabilities+", firmwareWrite:unavailable"] {
  calls = []; model.inspectServiceCapabilities { command in calls.append(command); precondition(command == "capabilities"); return unavailable }
  precondition(calls == ["capabilities"] && model.firmwareInspection == nil && model.firmwareStatus.contains("未提供"))
 }
 for advertised in [capabilities, capabilities.replacingOccurrences(of:"CH0B+BCLM",with:"BCLM")] {
 for (state,expected): (String,Bool?) in [("allowed",true),("inhibited",false),("unknown",nil)] {
  calls = []; model.inspectServiceCapabilities { command in
   calls.append(command)
   switch command { case "capabilities": return advertised
   case "firmwareStatus": return "limit=80, charging="+state
   default: preconditionFailure("inspection must be read-only") }
  }
  precondition(calls == ["capabilities","firmwareStatus"] && model.firmwareInspection?.limit == 80)
  precondition(model.firmwareInspection?.chargingAllowed == expected && model.firmwareStatus.contains("尚未启用"))
 }
 }
 calls = []; model.inspectServiceCapabilities { command in calls.append(command); return command == "capabilities" ? capabilities : "limit=15, charging=false" }
 precondition(calls == ["capabilities","firmwareStatus"] && model.firmwareInspection == nil && model.firmwareStatus.contains("失败"))
 model.inspectServiceCapabilities { _ in throw HelperError.unavailable }
 precondition(model.firmwareInspection == nil && model.firmwareStatus.contains("失败"))
 precondition(!model.config.hardwareEnabled && model.config.systemActionsEnabled != true && model.automationPhase != .intelMode)
 let saved = try Data(contentsOf:Configuration.url); precondition(saved == baseline,"diagnostic must not change configuration")
 print("Firmware inspection rejects old/pending/duplicate protocols before status, preserves unknown and validates replies; read-only injected IPC only")
}
