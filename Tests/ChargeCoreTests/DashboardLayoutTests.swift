import XCTest
@testable import ChargeCore

final class DashboardLayoutTests: XCTestCase {
 func testRestoresKnownUniqueWidgetsAndAllowsEmptyLayout() {
  let layout = DashboardLayout(widgetIDs: ["trend", "unknown", "battery", "trend"], specificationIDs: ["current", "unknown", "current", "voltage"])
  XCTAssertEqual(layout.widgets, [.trend, .battery]); XCTAssertEqual(layout.specifications, [.current, .voltage])
  XCTAssertEqual(DashboardLayout(widgetIDs: [], specificationIDs: []).widgets, [])
  let restored = (try? JSONEncoder().encode(layout)).flatMap { try? JSONDecoder().decode(DashboardLayout.self, from: $0) }
  XCTAssertEqual(restored, layout)
 }
 func testMovesAndVisibilityKeepOrderWithoutDuplicates() {
  var layout = DashboardLayout(widgets: [.battery, .powerFlow, .trend], specifications: [.current])
  layout.move(.battery, by: -1); XCTAssertEqual(layout.widgets, [.battery, .powerFlow, .trend])
  layout.move(.trend, by: -1); XCTAssertEqual(layout.widgets, [.battery, .trend, .powerFlow])
  layout.move(.battery, by: Int.max); XCTAssertEqual(layout.widgets, [.battery, .trend, .powerFlow])
  layout.setVisible(.trend, visible: false); layout.setVisible(.trend, visible: true); layout.setVisible(.trend, visible: true)
  XCTAssertEqual(layout.widgets, [.battery, .powerFlow, .trend])
  layout.setVisible(.current, visible: false); XCTAssertEqual(layout.specifications, [])
  layout.setVisible(.voltage, visible: true); layout.setVisible(.voltage, visible: true); XCTAssertEqual(layout.specifications, [.voltage])
 }
 func testOnlyDisplayRefreshFollowsFocusOrBackgroundPreference() {
  XCTAssertFalse(DashboardRefreshPolicy.shouldUpdate(windowFocused: false, backgroundUpdates: false))
  XCTAssertTrue(DashboardRefreshPolicy.shouldUpdate(windowFocused: true, backgroundUpdates: false))
  XCTAssertTrue(DashboardRefreshPolicy.shouldUpdate(windowFocused: false, backgroundUpdates: true))
  XCTAssertTrue(DashboardRefreshPolicy.shouldUpdate(windowFocused: true, backgroundUpdates: true))
 }
}
