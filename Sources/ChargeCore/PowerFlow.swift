import Foundation

public enum BatteryFlow: String, Sendable { case charging, supplyingSystem, idle, unknown }
public struct PowerFlowSnapshot: Sendable {
 public let adapterWatts: Double?
 public let batteryWatts: Double?
 public let systemWatts: Double?
 public var batteryFlow: BatteryFlow {
  guard let watts = batteryWatts else { return .unknown }
  if watts >= 0.1 { return .charging }; if watts <= -0.1 { return .supplyingSystem }; return .idle
 }
 public var adapterSupplying: Bool? { adapterWatts.map { $0 >= 0.1 } }
 public init(adapterWatts: Double?, batteryWatts: Double?, systemWatts: Double?) {
  self.adapterWatts = adapterWatts.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
  self.batteryWatts = batteryWatts.flatMap { $0.isFinite ? $0 : nil }
  self.systemWatts = systemWatts.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
 }
}
