import Foundation

func energyModeCommandChecks() throws {
 var requests: [String] = []; var reads = 0
 let status = EnergyModeStatus(battery:.automatic,ac:.high,highBattery:false,highAC:true,current:.low)
 func read() -> EnergyModeStatus { reads += 1; return status }
 func unexpected(_ command: String) -> String { requests.append(command); preconditionFailure("unexpected helper request") }
 let observed = try EnergyModeCommand.run(arguments:["status"],readStatus:read,request:unexpected)
 precondition(observed == status.description && reads == 1 && requests.isEmpty)
 for args in [[],["high"],["high","battery"],["high","ups","--confirm"],
              ["high","battery","--confirm","extra"],["restore","--confirm"],
              ["status","--confirm"],["--confirm"],["high","--confirm","battery"],
              ["low","--confirm","--confirm"],["HIGH","ac","--confirm"]] {
  do { _ = try EnergyModeCommand.run(arguments:args,readStatus:read,request:unexpected); preconditionFailure("invalid arguments accepted") }
  catch EnergyModeCommand.Failure.invalidArguments { }
 }
 precondition(reads == 1 && requests.isEmpty)
 for (name,mode) in [("automatic",EnergyMode.automatic),("low",.low),("high",.high)] {
  for source: PowerSource? in [nil,.battery,.ac] {
   let args = [name] + (source.map { [$0.rawValue] } ?? []) + ["--confirm"]
   var command: String?
   let receipt = EnergyModeStatus(battery:mode,ac:mode,highBattery:true,highAC:true,current:.automatic)
   let result = try EnergyModeCommand.run(arguments:args,readStatus:{preconditionFailure("mutations must use helper readback")},request:{ command = $0;return receipt.description })
   precondition(command == EnergyModeRequest(mode:mode,source:source).command && result == receipt.description)
  }
 }
 let acOnly = EnergyModeStatus(battery:nil,ac:.high,highBattery:nil,highAC:true,current:nil)
 let scoped = try EnergyModeCommand.run(arguments:["high","ac","--confirm"],readStatus:read,request:{_ in acOnly.description})
 precondition(scoped == acOnly.description)
 for receipt in [status.description,acOnly.description,"battery=unknown ac=unknown highBattery=unknown highAC=unknown current=unknown"] {
  do { _ = try EnergyModeCommand.run(arguments:["low","battery","--confirm"],readStatus:read,request:{_ in receipt});preconditionFailure("unconfirmed source accepted") }
  catch EnergyModeCommand.Failure.unexpectedReadback { }
 }
 do { _ = try EnergyModeCommand.run(arguments:["high","--confirm"],readStatus:read,request:{_ in status.description});preconditionFailure("mixed source readback accepted") }
 catch EnergyModeCommand.Failure.unexpectedReadback { }
 do { _ = try EnergyModeCommand.run(arguments:["low","--confirm"],readStatus:read,request:{_ in "battery=1 ac=1"});preconditionFailure("legacy reply accepted") }
 catch PowerModeError.invalidOutput { }
 enum Injected: Error { case helper }
 do { _ = try EnergyModeCommand.run(arguments:["high","ac","--confirm"],readStatus:read,request:{_ in throw Injected.helper});preconditionFailure("helper failure ignored") }
 catch Injected.helper { }
 precondition(reads == 1 && requests.isEmpty)
 print("Tri-state CLI: read-only status, strict admission, nine fixed commands, scoped/mixed/unknown/malformed readbacks and helper failure propagation passed; injected callbacks only")
}
