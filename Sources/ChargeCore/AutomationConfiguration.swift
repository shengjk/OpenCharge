import Foundation

public extension Configuration {
 /// An explicit automation request starts a fresh mode, rather than resuming
 /// a saved calibration. Continuation remains a separate application action.
 mutating func setAutomationMode(_ mode: ChargeMode) {
  policy.mode = mode
  policy.pauseAtCurrent = nil
  calibrationCheckpoint = nil
 }
}
