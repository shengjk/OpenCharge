import Foundation

/// A bounded numeric firmware selection, not a claim that all Intel models share this protocol.
/// Exact model selection and typed runtime values are both required.
public enum SMCFirmwareProbe {
 public static func selectedProfile(model: String, architecture: String, internalBattery: Bool) -> SMCFirmwareKeyProfile? {
  guard architecture == "x86_64", internalBattery else { return nil }
  let paired = ["MacBookAir8,1", "MacBookAir8,2", "MacBookAir9,1",
    "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
    "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
    "MacBookPro13,1", "MacBookPro13,2", "MacBookPro13,3",
    "MacBookPro14,1", "MacBookPro14,2", "MacBookPro14,3"]
  if paired.contains(model) { return .chargeAndLimit }
  let legacy = [
   "MacBook1,1", "MacBook2,1", "MacBook3,1", "MacBook4,1", "MacBook5,1",
   "MacBook5,2", "MacBook6,1", "MacBook7,1", "MacBook8,1", "MacBook9,1",
   "MacBook10,1", "MacBookAir1,1", "MacBookAir2,1", "MacBookAir3,1", "MacBookAir3,2",
   "MacBookAir4,1", "MacBookAir4,2", "MacBookAir5,1", "MacBookAir5,2", "MacBookAir6,1",
   "MacBookAir6,2", "MacBookAir7,1", "MacBookAir7,2", "MacBookPro1,1", "MacBookPro1,2",
   "MacBookPro2,1", "MacBookPro2,2", "MacBookPro3,1", "MacBookPro4,1", "MacBookPro5,1",
   "MacBookPro5,2", "MacBookPro5,3", "MacBookPro5,4", "MacBookPro5,5", "MacBookPro6,1",
   "MacBookPro6,2", "MacBookPro7,1", "MacBookPro8,1", "MacBookPro8,2", "MacBookPro8,3",
   "MacBookPro9,1", "MacBookPro9,2", "MacBookPro10,1", "MacBookPro10,2", "MacBookPro11,1",
   "MacBookPro11,2", "MacBookPro11,3", "MacBookPro11,4", "MacBookPro11,5", "MacBookPro12,1"
  ]
  return legacy.contains(model) ? .limitOnly : nil
 }
 public static func eligible(model: String, architecture: String, internalBattery: Bool) -> Bool {
  selectedProfile(model:model,architecture:architecture,internalBattery:internalBattery) != nil
 }
 static func inspect(model: String, architecture: String, internalBattery: Bool,
                     read: @escaping (String) throws -> SMCByteReading?) throws -> FirmwareChargeStatus {
  let selected = selectedProfile(model:model,architecture:architecture,internalBattery:internalBattery)
  let controller = SMCFirmwareChargeController(eligibleHost: selected != nil, batteryPresent: internalBattery, keyProfile: selected ?? .chargeAndLimit,
   read: read, write: { _, _ in throw HardwareError.permissionRequired }, authorized: { false })
  return try controller.inspect()
 }
}
