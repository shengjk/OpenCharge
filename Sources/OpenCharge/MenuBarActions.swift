import Foundation
import Combine
import ChargeCore

@MainActor final class MenuBarActionPreferences: ObservableObject {
 private var reloading = false
 private let defaults: UserDefaults
 @Published var rightClick: MenuBarRightClickAction {
  didSet { guard !reloading else { return }; defaults.set(rightClick.rawValue, forKey: "menuRightClickAction") }
 }
 func reloadAfterReset() {
  reloading = true
  rightClick = MenuBarRightClickAction.stored(defaults.string(forKey:"menuRightClickAction"))
  reloading = false
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
