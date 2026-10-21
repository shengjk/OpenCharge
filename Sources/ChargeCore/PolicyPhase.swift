import Foundation

/// Policy state and observed power flow are separate interfaces.
public enum PolicyPhase: String, Codable, CaseIterable, Sendable {
 case charging = "Charging", pause = "Pause", sailing = "Sailing", discharging = "Discharging"
 case topUp = "Topup", heatProtect = "HeatProtect", calibration = "Calibration", exit = "Exit"
 // Reserved for a backend that actually implements that operating state.
 case intelMode = "IntelMode"
}
