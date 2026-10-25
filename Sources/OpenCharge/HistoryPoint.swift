import Foundation
import ChargeHardware

struct HistoryPoint: Codable, Identifiable {
 var id: Date { date }; var date: Date; var percent: Double; var temperature: Double?; var watts: Double?; var reason: String
 var temperatureSource: BatteryTemperatureSource? = nil; var systemWatts: Double? = nil; var adapterWatts: Double? = nil; var limit: Double? = nil; var hardwarePercent: Double? = nil; var health: Double? = nil; var cycles: Int? = nil
}
