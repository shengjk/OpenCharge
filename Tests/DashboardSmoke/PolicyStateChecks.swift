import Foundation
import AppIntents
import ChargeCore

@MainActor func policyStateChecks(defaults: UserDefaults) async throws {
 let original = try Configuration.load()
 let originalProvider = PolicyStateRuntime.provider
 defer { try? original.save(); PolicyStateRuntime.provider = originalProvider }
 var fixture = Configuration()
 fixture.hardwareEnabled = false; fixture.systemActionsEnabled = false
 fixture.magSafeMode = .system; fixture.magSafeOffDuringSleep = false
 try fixture.save()
 var model: ChargeModel? = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  screenLockRequest: { preconditionFailure("policy getter must not lock the screen") })
 weak var releasedModel = model
 let before = try Data(contentsOf: Configuration.url)
 var policy = ChargePolicy(); var engine = ChargeEngine()
 for percent in [79.0, 75, 80] {
  var decision = engine.decide(ChargeSample(percent: percent, temperature: 30), policy: policy)
  decision.reason = "Presentation text cannot determine a typed state"
  model!.decision = decision
  let result = try await GetPolicyStateIntent().perform()
  precondition(result.value == decision.phase!.rawValue)
 }
 policy.mode = .discharge
 model!.decision = engine.decide(ChargeSample(percent: 90, temperature: 40), policy: policy)
 let discharging = try PolicyStateRuntime.read()
 precondition(discharging == .discharging)
 var requests: [String] = []
 try model!.prepareForQuit(request: { requests.append($0); return "fixture" })
 precondition(requests.isEmpty, "a disabled monitoring fixture must not send helper commands")
 let exiting = try await GetPolicyStateIntent().perform()
 precondition(exiting.value == PolicyPhase.exit.rawValue)
 let after = try Data(contentsOf: Configuration.url)
 precondition(after == before, "state reads must not persist changes")
 model = nil
 precondition(releasedModel == nil, "the state provider must not retain the model")
 do { _ = try PolicyStateRuntime.read(); preconditionFailure("ended model returned stale state") } catch {}
 fixture.policy.mode = .calibration
 fixture.calibrationCheckpoint = CalibrationCheckpoint(stage: .draining)
 try fixture.save()
 let interrupted = ChargeModel(dashboardDefaults: defaults, observeLid: false,
  screenLockRequest: { preconditionFailure("no locks in interrupted-state fixture") })
 precondition(interrupted.calibrationPending)
 let pending = try await GetPolicyStateIntent().perform()
 precondition(pending.value == PolicyPhase.calibration.rawValue)
 print("Live policy state follows typed engine decisions, pending calibration and quit; weak lifetime and read-only isolation passed without helper commands")
}
