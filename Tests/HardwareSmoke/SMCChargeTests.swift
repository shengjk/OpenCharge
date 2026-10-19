import Foundation

final class FakeSMC {
 var values: [String: [UInt8]]
 var writes: [(String, [UInt8])] = []
 var writeFailure: ((String, [UInt8]) -> Bool)?
 var readFailure: ((String) -> Bool)?
 init(_ values: [String: [UInt8]]) { self.values = values }
 func controller(battery: Bool = true, authorized: Bool = true) -> SMCChargeController {
  SMCChargeController(batteryPresent: battery, read: { key in
   if self.readFailure?(key) == true { throw HardwareError.unavailable("injected read failure") }
   return self.values[key]
  }, write: { key, bytes in
   if self.writeFailure?(key, bytes) == true { throw HardwareError.invalidData("injected write failure") }
   self.writes.append((key, bytes)); self.values[key] = bytes
  }, authorized: { authorized })
 }
}
@main struct SMCChargeTests {
 static func rejects(_ run: () throws -> Void) { do { try run(); preconditionFailure("unexpected success") } catch {} }
 static func main() throws {
  var scenarios = 0
  for chargeKeys in [["CHTE": [UInt8](arrayLiteral: 0, 0, 0, 0)], ["CH0B": [UInt8](arrayLiteral: 0), "CH0C": [UInt8](arrayLiteral: 0)]] {
   for (adapter, on) in [("CHIE", UInt8(8)), ("CH0J", UInt8(1)), ("CH0I", UInt8(1))] {
    var initial = chargeKeys; initial[adapter] = [0]
    let fake = FakeSMC(initial), client = fake.controller()
    _ = client.capabilities(); precondition(fake.writes.isEmpty)
    try client.apply(.forceDischarge); precondition(fake.values[adapter] == [on])
    for key in chargeKeys.keys { precondition(fake.values[key] == (key == "CHTE" ? [1, 0, 0, 0] : [2])) }
    let afterFirst = fake.writes.count
    try client.apply(.forceDischarge); precondition(fake.writes.count == afterFirst)
    try client.apply(.allowCharge); precondition(fake.values == initial)
    try client.apply(.inhibitCharge); precondition(fake.values[adapter] == [0])
    try client.apply(.restore); precondition(fake.values == initial)
    scenarios += 1
   }
  }
  // Modern key takes precedence; never combine two charge-control families.
  let preferred = FakeSMC(["CHTE": [0,0,0,0], "CH0B": [0], "CH0C": [0]])
  try preferred.controller().apply(.inhibitCharge); precondition(preferred.writes.map(\.0) == ["CHTE"]); scenarios += 1
  for invalid in [[:], ["CHTE": [UInt8](arrayLiteral: 0)], ["CHTE": [9,0,0,0], "CH0B": [0], "CH0C": [0]], ["CH0B": [0]], ["CH0B": [0], "CH0C": [1]], ["CHTE": [0,0,0,0], "CHIE": [1]]] {
   let fake = FakeSMC(invalid), client = fake.controller()
   rejects { try client.apply(.inhibitCharge) }; precondition(fake.writes.isEmpty); scenarios += 1
  }
  let noAdapter = FakeSMC(["CHTE": [0,0,0,0]]), noAdapterClient = noAdapter.controller()
  rejects { try noAdapterClient.apply(.forceDischarge) }; precondition(noAdapter.writes.isEmpty)
  try noAdapterClient.apply(.inhibitCharge); try noAdapterClient.apply(.restore); precondition(noAdapter.values["CHTE"] == [0,0,0,0]); scenarios += 1
  for (battery, allowed) in [(false, true), (true, false)] {
   let fake = FakeSMC(["CHTE": [0,0,0,0]])
   rejects { try fake.controller(battery: battery, authorized: allowed).apply(.inhibitCharge) }
   precondition(fake.writes.isEmpty); scenarios += 1
  }
  let unavailable = FakeSMC(["CHTE": [0,0,0,0], "CH0B": [0], "CH0C": [0]])
  unavailable.readFailure = { $0 == "CHTE" }
  rejects { try unavailable.controller().apply(.allowCharge) }; precondition(unavailable.writes.isEmpty); scenarios += 1
  let partial = FakeSMC(["CH0B": [0], "CH0C": [0]])
  var failOnce = true
  partial.writeFailure = { key, bytes in if key == "CH0C" && bytes == [2] && failOnce { failOnce = false; return true }; return false }
  rejects { try partial.controller().apply(.inhibitCharge) }
  precondition(partial.values == ["CH0B": [0], "CH0C": [0]]); scenarios += 1
  let retry = FakeSMC(["CHTE": [0,0,0,0]]), retryClient = retry.controller()
  try retryClient.apply(.inhibitCharge)
  retry.writeFailure = { _, bytes in bytes == [0,0,0,0] }
  rejects { try retryClient.apply(.restore) }; precondition(retry.values["CHTE"] == [1,0,0,0])
  retry.writeFailure = nil; try retryClient.apply(.restore); precondition(retry.values["CHTE"] == [0,0,0,0]); scenarios += 1
  let external = FakeSMC(["CHTE": [0,0,0,0]]), externalClient = external.controller()
  try externalClient.apply(.inhibitCharge); external.values["CHTE"] = [9,0,0,0]
  let beforeRestore = external.writes.count; try externalClient.apply(.restore)
  precondition(external.writes.count == beforeRestore && external.values["CHTE"] == [9,0,0,0]); scenarios += 1
  let unchanged = FakeSMC(["CHTE": [1,0,0,0]]), unchangedClient = unchanged.controller()
  try unchangedClient.apply(.inhibitCharge); try unchangedClient.apply(.restore); precondition(unchanged.writes.isEmpty); scenarios += 1
  var reads = 0, racingWrites = 0
  let racing = SMCChargeController(batteryPresent: true, read: { key in
   if key != "CHTE" { return nil }; reads += 1; return reads == 1 ? [0,0,0,0] : [9,0,0,0]
  }, write: { _, _ in racingWrites += 1 }, authorized: { true })
  rejects { try racing.apply(.inhibitCharge) }; precondition(racingWrites == 0); scenarios += 1
  var ignored = ["CH0B": [UInt8](arrayLiteral: 0), "CH0C": [UInt8](arrayLiteral: 0)]
  let badReadback = SMCChargeController(batteryPresent: true, read: { ignored[$0] }, write: { key, bytes in
   if key != "CH0C" { ignored[key] = bytes } // Firmware ignored the second mutation.
  }, authorized: { true })
  rejects { try badReadback.apply(.inhibitCharge) }; precondition(ignored == ["CH0B": [0], "CH0C": [0]]); scenarios += 1
  let cleanup = FakeSMC(["CH0B": [0], "CH0C": [0]]), cleanupClient = cleanup.controller()
  cleanup.writeFailure = { key, bytes in (key == "CH0C" && bytes == [2]) || (key == "CH0B" && bytes == [0]) }
  rejects { try cleanupClient.apply(.inhibitCharge) }; precondition(cleanup.values["CH0B"] == [2])
  cleanup.writeFailure = nil; try cleanupClient.apply(.restore); precondition(cleanup.values == ["CH0B": [0], "CH0C": [0]]); scenarios += 1
  print("PASS SMC charge profiles: \(scenarios) fixture scenarios; zero real hardware accesses")
 }
}
