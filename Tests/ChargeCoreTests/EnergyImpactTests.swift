import XCTest
@testable import ChargeCore

final class EnergyImpactTests: XCTestCase {
 func testRanksByEnergyAndKeepsFiveBeforeStrictThreshold() {
  let values = try? EnergyImpactSelection.select(bundleIdentifiers: ["a", "b", "c", "d", "e", "f", "g"], impacts: [10_000, 50_000, 30_000, 20_000, 40_000, 60_000, 70_000], threshold: 30_000)
  XCTAssertEqual(values?.map(\.bundleIdentifier), ["g", "f", "b", "e"])
  XCTAssertEqual(values?.map(\.impact), [70_000, 60_000, 50_000, 40_000])
  XCTAssertEqual((try? EnergyImpactSelection.select(bundleIdentifiers: ["a", "b", "c", "d", "e", "f"], impacts: [6, 5, 4, 3, 2, 1], threshold: 0))?.count, 5)
 }
 func testRejectsMalformedDataAndPreservesTieOrder() {
  XCTAssertNil(try? EnergyImpactSelection.select(bundleIdentifiers: ["a"], impacts: [], threshold: 0))
  for invalid in [Double.nan, .infinity, -1] { XCTAssertNil(try? EnergyImpactSelection.select(bundleIdentifiers: ["a"], impacts: [invalid], threshold: 0)) }
  XCTAssertNil(try? EnergyImpactSelection.select(bundleIdentifiers: [""], impacts: [1], threshold: 0))
  XCTAssertNil(try? EnergyImpactSelection.select(bundleIdentifiers: ["a"], impacts: [1], threshold: .nan))
  XCTAssertEqual((try? EnergyImpactSelection.select(bundleIdentifiers: ["b", "a"], impacts: [2, 2], threshold: 1))?.map(\.bundleIdentifier), ["b", "a"])
  XCTAssertEqual(EnergySensitivity.allCases.map(\.threshold), [10_000, 20_000, 35_000])
 }
}
