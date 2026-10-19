import SwiftUI
import ChargeCore
@MainActor final class PopoverPreferences: ObservableObject {
 private let defaults: UserDefaults
 @Published private(set) var editingConsumers = Set<PopoverConsumer>()
 func isEditing(_ consumer: PopoverConsumer) -> Bool { editingConsumers.contains(consumer) }
 func setEditing(_ editing: Bool, consumer: PopoverConsumer) {
  if editing { editingConsumers.insert(consumer) } else { editingConsumers.remove(consumer) }
 }
 var dragging = false
 var changed: (() -> Void)?
 @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: "popoverAnimationsEnabled") } }
 @Published var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: "popoverShowPercentage") } }
 @Published var layout: PopoverLayout { didSet { if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: "popoverLayout") }; changed?() } }
 init(defaults: UserDefaults = .standard) {
  self.defaults = defaults; animationsEnabled = defaults.object(forKey: "popoverAnimationsEnabled") as? Bool ?? true; showPercentage = defaults.object(forKey: "popoverShowPercentage") as? Bool ?? true
  if let data = defaults.data(forKey: "popoverLayout"), data.count <= 16_384, let saved = try? JSONDecoder().decode(PopoverLayout.self, from: data) { layout = saved } else { layout = PopoverLayout() }
 }
}
