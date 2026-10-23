import Foundation
import IOKit.pwr_mgt

private enum Injected: Error { case denied, create, inspect, release }
private final class Fixture {
 var allowed = true
 var events: [String] = []
 var next: UInt32 = 7
 var createFails = false
 var inspectFails = false
 var matches = true
 var releaseFails = false
 func controller() -> FirmwareInflowAssertion {
  FirmwareInflowAssertion(authorize: {
   self.events.append("authorize"); if !self.allowed { throw Injected.denied }
  }, create: {
   self.events.append("create"); if self.createFails { throw Injected.create }; return self.next
  }, inspect: { id in
   self.events.append("inspect:\(id)"); if self.inspectFails { throw Injected.inspect }; return self.matches
  }, release: { id in
   self.events.append("release:\(id)"); if self.releaseFails { throw Injected.release }
  })
 }
}
@main struct FirmwareInflowAssertionTests {
 static var checks = 0
 static func check(_ value: Bool) { precondition(value); checks += 1 }
 static func rejects(_ action: () throws -> Void) { do { try action(); preconditionFailure("unexpected success") } catch { checks += 1 } }
 static func main() throws {
  // Every OS operation is injected; this executable never creates an assertion.
  let typeKey = kIOPMAssertionTypeKey as String, levelKey = kIOPMAssertionLevelKey as String
  check(!FirmwareInflowAssertion.matches([:]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow"]))
  check(!FirmwareInflowAssertion.matches([typeKey:"PreventSystemSleep",levelKey:255]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:true]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:"255"]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:255.5]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:Double.nan]))
  check(!FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:0]))
  check(FirmwareInflowAssertion.matches([typeKey:"DisableInflow",levelKey:255]))
  let f = Fixture(), c = f.controller()
  check(c.ownedID == nil && !c.recoveryRequired)
  try c.restore(); check(f.events == ["authorize"])
  f.events = []; f.allowed = false
  rejects { try c.acquire() }; check(f.events == ["authorize"] && c.ownedID == nil)
  f.allowed = true; f.createFails = true; f.events = []
  rejects { try c.acquire() }; check(f.events == ["authorize","create"] && c.ownedID == nil && !c.recoveryRequired)
  f.createFails = false; f.next = 0; f.events = []
  rejects { try c.acquire() }; check(f.events == ["authorize","create"] && c.ownedID == nil)
  f.next = 7; f.events = []; try c.acquire()
  check(f.events == ["authorize","create","inspect:7"] && c.ownedID == 7 && !c.recoveryRequired)
  f.events = []; try c.acquire(); check(f.events == ["authorize","inspect:7"])
  f.allowed = false; f.events = []
  rejects { try c.restore() }; check(f.events == ["authorize"] && c.ownedID == 7)
  f.allowed = true; f.matches = false
  rejects { try c.acquire() }; check(c.ownedID == 7 && c.recoveryRequired)
  f.events = []; rejects { try c.acquire() }; check(f.events == ["authorize"])
  f.releaseFails = true; f.events = []
  rejects { try c.restore() }; check(f.events == ["authorize","release:7"] && c.ownedID == 7 && c.recoveryRequired)
  f.releaseFails = false; f.events = []; try c.restore()
  check(f.events == ["authorize","release:7"] && c.ownedID == nil && !c.recoveryRequired)
  f.next = 19; f.matches = true; f.inspectFails = true; f.events = []
  rejects { try c.acquire() }; check(c.ownedID == 19 && c.recoveryRequired)
  f.inspectFails = false; f.events = []; rejects { try c.acquire() }; check(f.events == ["authorize"])
  try c.restore(); check(c.ownedID == nil && !c.recoveryRequired)
  f.events = []; try c.acquire(); check(f.events == ["authorize","create","inspect:19"])
  try c.restore(); check(c.ownedID == nil)
  print("Firmware inflow assertion: \(checks) injected ownership/failure checks passed; no OS assertions created")
 }
}
