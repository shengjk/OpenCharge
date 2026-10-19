import XCTest
@testable import ChargeCore
final class PopoverLayoutTests: XCTestCase {
 func testDragMovesBothDirectionsAndArrowEdgesStayBounded() {
  var layout = PopoverLayout(widgets: [.specifications, .powerFlow, .energyApps])
  layout.move(.specifications, to: .energyApps)
  XCTAssertEqual(layout.widgets, [.powerFlow, .energyApps, .specifications])
  layout.move(.specifications, to: .powerFlow)
  XCTAssertEqual(layout.widgets, [.specifications, .powerFlow, .energyApps])
  layout.move(.specifications, by: -1); layout.move(.energyApps, by: 1); layout.move(.powerFlow, by: Int.max)
  XCTAssertEqual(layout.widgets, [.specifications, .powerFlow, .energyApps])
  layout.move(.specifications, by: 1); XCTAssertEqual(layout.widgets, [.powerFlow, .specifications, .energyApps])
 }
 func testUnknownStoredWidgetsAndDuplicatesAreSanitized() {
  let data = Data(#"{"widgets":["energyApps","unknown","energyApps","specifications"],"specifications":["current","unknown","current"]}"#.utf8)
  let layout = try? JSONDecoder().decode(PopoverLayout.self, from: data)
  XCTAssertEqual(layout?.widgets, [.energyApps, .specifications]); XCTAssertEqual(layout?.specifications, [.current])
  var empty = PopoverLayout(widgets: [], specifications: [])
  empty.setVisible(.powerFlow, visible: true); empty.setVisible(.powerFlow, visible: true)
  XCTAssertEqual(empty.widgets, [.powerFlow]); empty.setVisible(.powerFlow, visible: false); XCTAssertEqual(empty.widgets, [])
  XCTAssertEqual((try? JSONEncoder().encode(empty)).flatMap { try? JSONDecoder().decode(PopoverLayout.self, from: $0) }, empty)
 }
 func testEnergyRefreshServesEitherVisibleConsumer() {
  for dashboard in [false, true] { for dashboardWidget in [false, true] { for popover in [false, true] { for popoverWidget in [false, true] {
   XCTAssertEqual(EnergyConsumerPolicy.shouldQuery(dashboardActive: dashboard, dashboardHasWidget: dashboardWidget, popoverVisible: popover, popoverHasWidget: popoverWidget), (dashboard && dashboardWidget) || (popover && popoverWidget))
  } } } }
 }
}
