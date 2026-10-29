import Foundation

@MainActor func energyQuitChecks() {
 let target = EnergyQuitTarget(pid:12345,bundleIdentifier:"org.example.energy",startTimeMicroseconds:100_000_000)
 let valid = EnergyQuitSnapshot(target:target,isRegular:true,isTerminated:false)
 var calls = 0
 func request(_ snapshot: EnergyQuitSnapshot?, ownPID: Int32 = 9, accepted: Bool = true) -> EnergyQuitResult {
  EnergyApplicationQuit.request(target,ownPID:ownPID,current:snapshot,terminate:{calls += 1;return accepted})
 }
 precondition(request(nil) == .unavailable)
 precondition(request(valid,ownPID:target.pid) == .unavailable)
 precondition(request(EnergyQuitSnapshot(target:target,isRegular:false,isTerminated:false)) == .unavailable)
 precondition(request(EnergyQuitSnapshot(target:target,isRegular:true,isTerminated:true)) == .unavailable)
 for changed in [EnergyQuitTarget(pid:12346,bundleIdentifier:target.bundleIdentifier,startTimeMicroseconds:target.startTimeMicroseconds),EnergyQuitTarget(pid:target.pid,bundleIdentifier:"org.example.other",startTimeMicroseconds:target.startTimeMicroseconds),EnergyQuitTarget(pid:target.pid,bundleIdentifier:target.bundleIdentifier,startTimeMicroseconds:target.startTimeMicroseconds + 1)] {
  precondition(request(EnergyQuitSnapshot(target:changed,isRegular:true,isTerminated:false)) == .unavailable)
 }
 precondition(calls == 0)
 precondition(request(valid,accepted:false) == .notSent && calls == 1)
 precondition(request(valid) == .requested && calls == 2)
 let monitor = EnergyMonitor();var requests = 0
 monitor.requestQuit(target,perform:{_ in requests += 1;return .notSent})
 precondition(monitor.quitRequested.isEmpty)
 monitor.requestQuit(target,perform:{_ in requests += 1;return .requested})
 monitor.requestQuit(target,perform:{_ in preconditionFailure("duplicate pending quit")})
 precondition(requests == 2 && monitor.quitRequested == [target])
 print("PASS energy app quit: exact process/bundle/launch identity, self/background/terminated/stale rejection, normal-request/refusal outcomes and pending repeat suppression; injected actions only")
}
