import Foundation

/// A bounded initial selection, not a claim that all other Intel models lack support.
/// Exact model selection and typed runtime values are both required.
enum SMCFirmwareProbe {
 static func eligible(model: String, architecture: String, internalBattery: Bool) -> Bool {
  architecture == "x86_64" && internalBattery &&
   ["MacBookAir8,1", "MacBookAir8,2", "MacBookAir9,1"].contains(model)
 }
 static func inspect(model: String, architecture: String, internalBattery: Bool,
                     read: @escaping (String) throws -> SMCByteReading?) throws -> FirmwareChargeStatus {
  let supported = eligible(model: model, architecture: architecture, internalBattery: internalBattery)
  let controller = SMCFirmwareChargeController(eligibleHost: supported, batteryPresent: internalBattery,
   read: read, write: { _, _ in throw HardwareError.permissionRequired }, authorized: { false })
  return try controller.inspect()
 }
}
