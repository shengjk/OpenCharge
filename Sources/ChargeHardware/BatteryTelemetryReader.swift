import Foundation

/// One read-only source selection for the app, CLI and native automation.
/// SMC unavailability preserves the registry reading and its source label.
public enum BatteryTelemetryReader {
    public static func read() throws -> BatteryReading {
        try read(base: BatteryReader.read, smc: { try SMCController().telemetryReading() })
    }

    /// Inject the complete acquisition boundary; fixtures never open an SMC connection.
    public static func read(base: () throws -> BatteryReading,
                            smc: () throws -> SMCTelemetryReading) throws -> BatteryReading {
        let reading = try base()
        guard let sensors = try? smc() else { return reading }
        return reading.applyingSMCTemperature(sensors.temperature)
            .applyingSMCPower(system: sensors.systemPowerW, input: sensors.adapterPowerW)
    }

    public static func read(base: () throws -> BatteryReading,
                            smcTemperature: () throws -> Double?) throws -> BatteryReading {
        let reading = try base()
        return reading.applyingSMCTemperature(try? smcTemperature())
    }
}
