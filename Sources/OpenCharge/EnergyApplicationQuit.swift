import AppKit
import Foundation
import Darwin

struct EnergyQuitTarget: Hashable {
 let pid: Int32
 let bundleIdentifier: String
 let startTimeMicroseconds: UInt64
}

struct EnergyQuitSnapshot {
 let target: EnergyQuitTarget
 let isRegular: Bool
 let isTerminated: Bool
}

enum EnergyQuitResult: String { case requested, notSent, unavailable }

@MainActor enum EnergyApplicationQuit {
 static func snapshot(_ app: NSRunningApplication) -> EnergyQuitSnapshot? {
  guard let bundle = app.bundleIdentifier, !bundle.isEmpty, app.processIdentifier > 1 else { return nil }
  var info = proc_bsdinfo()
  let size = Int32(MemoryLayout<proc_bsdinfo>.size)
  guard proc_pidinfo(app.processIdentifier,PROC_PIDTBSDINFO,0,&info,size) == size,
        info.pbi_pid == UInt32(app.processIdentifier), info.pbi_uid == geteuid(),
        info.pbi_start_tvsec > 0, info.pbi_start_tvsec < UInt64.max / 1_000_000,
        info.pbi_start_tvusec < 1_000_000 else { return nil }
  let started = info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
  return EnergyQuitSnapshot(target:EnergyQuitTarget(pid:app.processIdentifier,bundleIdentifier:bundle,startTimeMicroseconds:started),isRegular:app.activationPolicy == .regular,isTerminated:app.isTerminated)
 }
 static func request(_ target: EnergyQuitTarget) -> EnergyQuitResult {
  guard let app = NSRunningApplication(processIdentifier:target.pid) else { return .unavailable }
  return request(target,ownPID:ProcessInfo.processInfo.processIdentifier,current:snapshot(app),terminate:{app.terminate()})
 }
 static func request(_ target: EnergyQuitTarget, ownPID: Int32, current: EnergyQuitSnapshot?, terminate: () -> Bool) -> EnergyQuitResult {
  guard target.pid > 1, target.pid != ownPID, let current,
        current.target == target, current.isRegular, !current.isTerminated else { return .unavailable }
  // A successful return acknowledges a normal quit request, not process exit.
  return terminate() ? .requested : .notSent
 }
}
