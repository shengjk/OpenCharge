import Foundation

/// Serialized by SMCController. Only one charge backend may own a session.
/// The two journals overlap on CH0B, so conflicting startup records require
/// explicit recovery rather than guessing an order that could destroy ownership.
final class ChargeBackendSession {
 enum Backend { case ordinary, firmware }
 private(set) var active: Backend?
 private(set) var recoveryRequired = false
 private var initialized = false
 private let ordinaryPending: () throws -> Bool
 private let firmwarePending: () throws -> Bool
 private let ordinary: (HardwareAction) throws -> Void
 private let firmwareInspect: () throws -> Void
 private let firmwareLimit: (Int) throws -> Void
 private let firmwareInhibit: () throws -> Void
 private let firmwareExit: (Int) throws -> Void
 private let firmwareRestore: () throws -> Void
 private let firmwareEligible: Bool
 init(ordinaryPending: @escaping () throws -> Bool, firmwarePending: @escaping () throws -> Bool,
      ordinary: @escaping (HardwareAction) throws -> Void, firmwareEligible: Bool,
      firmwareInspect: @escaping () throws -> Void, firmwareLimit: @escaping (Int) throws -> Void,
      firmwareInhibit: @escaping () throws -> Void, firmwareExit: @escaping (Int) throws -> Void,
      firmwareRestore: @escaping () throws -> Void) {
  self.ordinaryPending = ordinaryPending; self.firmwarePending = firmwarePending; self.ordinary = ordinary
  self.firmwareEligible = firmwareEligible; self.firmwareInspect = firmwareInspect; self.firmwareLimit = firmwareLimit
  self.firmwareInhibit = firmwareInhibit; self.firmwareExit = firmwareExit; self.firmwareRestore = firmwareRestore
 }
 func restore() throws {
  do {
   if !initialized {
    let oldOrdinary = try ordinaryPending(), oldFirmware = try firmwarePending()
    guard !(oldOrdinary && oldFirmware) else { throw HardwareError.unavailable("Conflicting charge recovery records; refusing automatic writes") }
    active = oldOrdinary ? .ordinary : (oldFirmware ? .firmware : nil)
   }
   if active == .ordinary { try ordinary(.restore) }
   if active == .firmware { try firmwareRestore() }
   active = nil; initialized = true; recoveryRequired = false
  } catch { recoveryRequired = true; throw error }
 }
 private func prepare(_ backend: Backend) throws {
  guard !recoveryRequired else { throw HardwareError.unavailable("Charge recovery pending") }
  if !initialized { try restore() }
  if let active, active != backend { try restore() }
  active = backend
 }
 func apply(_ action: HardwareAction) throws {
  if action == .restore { try restore(); return }
  try prepare(.ordinary)
  do { try ordinary(action) } catch { recoveryRequired = true; throw error }
 }
 private func prepareFirmware() throws {
  guard firmwareEligible else { throw HardwareError.unsupported("Numeric firmware profile unavailable") }
  guard !recoveryRequired else { throw HardwareError.unavailable("Charge recovery pending") }
  // Reject unreadable numeric metadata before restoring an ordinary session.
  try firmwareInspect()
  try prepare(.firmware)
 }
 func setFirmwareLimit(_ value: Int) throws {
  guard (20...100).contains(value) else { throw HardwareError.invalidData("Firmware limit must be 20...100") }
  try prepareFirmware()
  do { try firmwareLimit(value) } catch { recoveryRequired = true; throw error }
 }
 func inhibitFirmware() throws {
  try prepareFirmware()
  do { try firmwareInhibit() } catch { recoveryRequired = true; throw error }
 }
 func finishFirmwareExit(_ value: Int) throws {
  guard (20...100).contains(value) else { throw HardwareError.invalidData("Firmware exit limit must be 20...100") }
  try prepareFirmware()
  do { try firmwareExit(value); active = nil }
  catch { recoveryRequired = true; throw error }
 }
}
