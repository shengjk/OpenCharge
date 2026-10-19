import XCTest
@testable import ChargeCore
final class PowerFlowTests: XCTestCase {
 func testBatteryCanSupplySystemWhileAdapterIsConnectedButInhibited() {
  let snapshot = PowerFlowSnapshot(adapterWatts: 0, batteryWatts: -18, systemWatts: 18)
  XCTAssertEqual(snapshot.batteryFlow, .supplyingSystem); XCTAssertEqual(snapshot.adapterSupplying, false)
  XCTAssertEqual(snapshot.batteryWatts, -18)
 }
 func testChargingIdleAndMissingChannelsRemainDistinct() {
  XCTAssertEqual(PowerFlowSnapshot(adapterWatts: 40, batteryWatts: 15, systemWatts: 20).batteryFlow, .charging)
  XCTAssertEqual(PowerFlowSnapshot(adapterWatts: 12, batteryWatts: 0.01, systemWatts: 12).batteryFlow, .idle)
  let missing = PowerFlowSnapshot(adapterWatts: -.infinity, batteryWatts: .nan, systemWatts: -1)
  XCTAssertEqual(missing.batteryFlow, .unknown); XCTAssertNil(missing.adapterSupplying); XCTAssertNil(missing.systemWatts)
 }
}
