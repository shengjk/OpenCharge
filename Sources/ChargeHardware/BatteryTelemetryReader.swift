import Foundation

/// One read-only source selection for the app, CLI and native automation.
/// SMC unavailability preserves the registry reading and its source label.
public enum BatteryTelemetryReader {
    public static func read(
        base: () throws -> BatteryReading = BatteryReader.read,
        smcTemperature: () throws -> Double? = {
            try SMCController().batteryTemperatureReading().celsius
        }
    ) throws -> BatteryReading {
        let reading = try base()
        return reading.applyingSMCTemperature(try? smcTemperature())
    }
}
