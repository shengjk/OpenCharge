import XCTest
@testable import ChargeCore

final class FirmwareHelperStateTests: XCTestCase {
 let fields = ["firmwareProtocol:fixedV1","firmwareRead:CH0B+BCLM","firmwareWrite:fixedV1","chargeRecovery:ready","internalBattery:present"]
 func testNumericAvailabilityRequiresEveryIndependentCapability() {
  let ordinary = "chargeControl:CHTE, profile:recognizedFormat, physicalEffects:unverified"
  XCTAssertFalse(FirmwareHelperCapabilities.supportsNumericControl(ordinary))
  XCTAssertTrue(FirmwareHelperCapabilities.supportsNumericControl((fields+[ordinary,"model:MacBookAir8,1"]).joined(separator:", ")))
  for index in fields.indices { var missing = fields; missing.remove(at:index); XCTAssertFalse(FirmwareHelperCapabilities.supportsNumericControl(missing.joined(separator:", "))) }
  XCTAssertTrue(FirmwareHelperCapabilities.supportsNumericControl(fields.reversed().joined(separator:",")))
 }
 func testUnavailablePendingUnknownAndDuplicateCapabilitiesAreRejected() {
  for (key,value) in [("firmwareProtocol","fixedV2"),("firmwareRead","BCLM"),("firmwareWrite","unavailable"),("chargeRecovery","pending"),("internalBattery","absent")] {
   var changed = fields; changed[changed.firstIndex(where:{$0.hasPrefix(key+":")})!] = key+":"+value
   XCTAssertFalse(FirmwareHelperCapabilities.supportsNumericControl(changed.joined(separator:", ")))
  }
  for duplicate in fields+fields.map({ $0.split(separator:":")[0]+":unavailable" }) { XCTAssertFalse(FirmwareHelperCapabilities.supportsNumericControl((fields+[duplicate]).joined(separator:", "))) }
  for extra in ["\n", "\r",String(repeating:"x",count:4097)] { XCTAssertFalse(FirmwareHelperCapabilities.supportsNumericControl(fields.joined(separator:", ")+extra)) }
 }
 func testStatusPreservesEveryRecognizedControlState() {
  for number in [15]+Array(20...100) {
   XCTAssertEqual(FirmwareHelperState(reply:"limit=\(number), charging=allowed")?.limit,UInt8(number))
   XCTAssertEqual(FirmwareHelperState(reply:"limit=\(number), charging=allowed")?.chargingAllowed,true)
   XCTAssertEqual(FirmwareHelperState(reply:"limit=\(number), charging=inhibited")?.chargingAllowed,false)
   let unknown = FirmwareHelperState(reply:"limit=\(number), charging=unknown")
   XCTAssertNotEqual(unknown,nil); XCTAssertNil(unknown?.chargingAllowed)
  }
  XCTAssertEqual(FirmwareHelperState(reply:"charging=allowed, limit=80")?.limit,80)
 }
 func testMalformedStatusCannotBecomeInhibitOrCharging() {
  for value in ["","limit=15","limit=80, charging=1","limit=80, charging=false","limit=19, charging=allowed","limit=101, charging=allowed","limit=256, charging=allowed","limit=-1, charging=allowed","limit=080, charging=allowed","limit=+80, charging=allowed","limit=80.0, charging=allowed","limit=８０, charging=allowed","limit=80, charging=allowed\nrestore","limit=80, charging=allowed\r","limit=80, charging=allowed, x=1","limit=80, limit=81","charging=allowed, charging=inhibited","limit=80, charging=","limit=, charging=allowed","limit=99999999999999999999999999999999, charging=allowed"] { XCTAssertNil(FirmwareHelperState(reply:value)) }
 }
 func testUnknownStateIsNotSubstitutedWhenProjectingSleep() {
  let status = FirmwareHelperState(reply:"limit=15, charging=unknown")
  var policy = ChargePolicy(); policy.limit = 80; policy.sailing = false
  XCTAssertNil(FirmwareLimitProjection.onSleep(policy:policy,phase:.charging,smcCharging:status?.chargingAllowed))
  XCTAssertEqual(FirmwareLimitProjection.onSleep(policy:policy,phase:.heatProtect,smcCharging:status?.chargingAllowed),80)
 }
}
