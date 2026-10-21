import Foundation
import Combine
import ChargeCore

@MainActor final class MenuBarActionPreferences: ObservableObject {
 private let defaults: UserDefaults
 @Published var rightClick: MenuBarRightClickAction {
  didSet { defaults.set(rightClick.rawValue, forKey: "menuRightClickAction") }
 }
 init(defaults: UserDefaults = .standard) {
  self.defaults = defaults
  rightClick = MenuBarRightClickAction.stored(defaults.string(forKey: "menuRightClickAction"))
 }
}
enum StatusItemClick { case primary, secondary, programmatic }
@MainActor enum StatusItemActionRouter {
 static func route(_ click: StatusItemClick, preference: MenuBarRightClickAction,
                   togglePopover: () -> Void, closePopover: () -> Void,
                   openSettings: () -> Void, toggleCharging: () -> Void, toggleLowPower: () -> Void) {
  guard click == .secondary else { togglePopover(); return }
  switch preference {
  case .popover: togglePopover()
  case .settings: closePopover(); openSettings()
  case .toggleCharging: toggleCharging()
  case .toggleLowPower: toggleLowPower()
  }
 }
}
