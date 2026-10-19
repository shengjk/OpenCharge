import Foundation

public enum HardwareIdentity {
 public static func model() throws -> String {
  let properties = try registryProperties("IOPlatformExpertDevice")
  if let data = properties["model"] as? Data { return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self) }
  return properties["model"] as? String ?? "unknown"
 }
}
