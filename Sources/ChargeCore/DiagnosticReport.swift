import Foundation

/// An explicit projection: never serialize the entire configuration, environment or IORegistry.
public struct DiagnosticReport: Codable {
 public struct Battery: Codable {
  public var percent: Double
  public var temperature: Double?
  public var connected: Bool
  public var charging: Bool
  public var cycles: Int?
  public init(percent: Double, temperature: Double?, connected: Bool, charging: Bool, cycles: Int?) {
   self.percent = percent; self.temperature = temperature; self.connected = connected; self.charging = charging; self.cycles = cycles
  }
 }
 public struct Policy: Codable {
  public var limit: Double
  public var mode: ChargeMode
  public var sailing: Bool
  public var sailingWidth: Double
  public var heatProtection: Bool
  public var maxTemperature: Double
  public var hardwareEnabled: Bool
  public var scheduleCount: Int
 }
 public let schemaVersion: Int
 public let generatedAt: Date
 public let appVersion: String
 public let systemVersion: String
 public let architecture: String
 public let model: String
 public let battery: Battery?
 public let policy: Policy
 public let registrationStatus: String
 public let helperCapabilities: String
 public let decision: ChargeAction
 public let errorPresent: Bool
 public init(appVersion: String, systemVersion: String, architecture: String, model: String,
             battery: Battery?, configuration: Configuration, registrationStatus: String,
             helperCapabilities: String, decision: ChargeAction, errorPresent: Bool, generatedAt: Date = Date()) {
  schemaVersion = 1; self.generatedAt = generatedAt; self.appVersion = appVersion; self.systemVersion = systemVersion
  self.architecture = architecture; self.model = model; self.battery = battery
  let p = configuration.policy
  policy = Policy(limit: p.limit, mode: p.mode, sailing: p.sailing, sailingWidth: p.sailingWidth, heatProtection: p.heatProtection, maxTemperature: p.maxTemperature, hardwareEnabled: configuration.hardwareEnabled, scheduleCount: configuration.schedules.count)
  self.registrationStatus = registrationStatus; self.helperCapabilities = Self.filteredCapabilities(helperCapabilities)
  self.decision = decision; self.errorPresent = errorPresent
 }
 private static func filteredCapabilities(_ text: String) -> String {
  let allowed: Set<String> = ["unavailable", "internalBattery:present", "internalBattery:absent", "batteryTelemetry", "chargeControl:CHTE", "chargeControl:CH0B+CH0C", "chargeControl:CH0C", "chargeControl:unavailable", "forceDischarge:CHIE", "forceDischarge:CH0J", "forceDischarge:CH0I", "profile:recognizedFormat", "physicalEffects:unverified", "writesRequirePrivilegedHelper", "magSafeKey:ACLC", "magSafe:unavailable", "lowPower:unavailable"]
  let tokens = text.prefix(4096).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { allowed.contains($0) }
  return tokens.isEmpty ? "unavailable" : tokens.joined(separator: ", ")
 }
 public func encoded() throws -> Data {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
  return try encoder.encode(self)
 }
}
