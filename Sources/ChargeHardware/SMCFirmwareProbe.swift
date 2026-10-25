import Foundation

/// A bounded numeric firmware selection, not a claim that all Intel models share this protocol.
/// Exact model selection and typed runtime values are both required.
public enum SMCFirmwareProbe {
 public static func eligible(model: String, architecture: String, internalBattery: Bool) -> Bool {
  architecture == "x86_64" && internalBattery &&
   ["MacBookAir8,1", "MacBookAir8,2", "MacBookAir9,1",
    "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
    "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
    "MacBookPro13,1", "MacBookPro13,2", "MacBookPro13,3",
    "MacBookPro14,1", "MacBookPro14,2", "MacBookPro14,3"].contains(model)
 }
 static func inspect(model: String, architecture: String, internalBattery: Bool,
                     read: @escaping (String) throws -> SMCByteReading?) throws -> FirmwareChargeStatus {
  let supported = eligible(model: model, architecture: architecture, internalBattery: internalBattery)
  let controller = SMCFirmwareChargeController(eligibleHost: supported, batteryPresent: internalBattery,
   read: read, write: { _, _ in throw HardwareError.permissionRequired }, authorized: { false })
  return try controller.inspect()
 }
}
