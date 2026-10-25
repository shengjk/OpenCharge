import Foundation
import ChargeCore
import ChargeHardware

@MainActor func unavailableHelperChecks() async throws {
 let original = try Configuration.load()
 defer { try? original.save() }
 var fixture = Configuration(); fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 try fixture.save()
 let suite = "org.opencharge.helper-availability."+UUID().uuidString
 let defaults = UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 let service = HelperService(bundle:.main,backend:nil,legacyCheck:{ false },signatureCheck:{ _ in preconditionFailure("unavailable backend cannot verify or register") })
 let model = ChargeModel(dashboardDefaults:defaults,observeLid:false,screenLockRequest:{ preconditionFailure("no locks") },readBattery:{ BatteryReading(percent:50,connected:true,charging:false) },helperService:service)
 model.config.hardwareEnabled = true
 let bytes = try Data(contentsOf:Configuration.url)
 await model.removeHelperService()
 precondition(model.config.hardwareEnabled && model.error != nil)
 let after = try Data(contentsOf:Configuration.url)
 precondition(after == bytes,"Unavailable removal rewrote configuration before rejecting")
 model.config.hardwareEnabled = false
 print("Unavailable service removal preserves opt-in and disk state before cleanup; injected backend, no helper or system setter")
}
