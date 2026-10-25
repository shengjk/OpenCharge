import Foundation

public enum EnergySensitivity: String, CaseIterable, Identifiable {
 case high, balanced, low
 public var id: Self { self }
 public var threshold: Double { switch self { case .high: return 10_000; case .balanced: return 20_000; case .low: return 35_000 } }
 public var displayName: String { switch self { case .high: return String(localized:"高灵敏度"); case .balanced: return String(localized:"均衡"); case .low: return String(localized:"低灵敏度") } }
}
public struct EnergyImpact: Equatable, Sendable {
 public let bundleIdentifier: String
 public let impact: Double
 public init(bundleIdentifier: String, impact: Double) { self.bundleIdentifier = bundleIdentifier; self.impact = impact }
}
public enum EnergyImpactSelection {
 public enum InvalidData: Error { case malformed }
 // Select five system-energy candidates before thresholding or
 // resolving running applications. CPU percentage is not a ranking input.
 public static func select(bundleIdentifiers: [String], impacts: [Double], threshold: Double) throws -> [EnergyImpact] {
  guard bundleIdentifiers.count == impacts.count, impacts.count <= 10_000,
        threshold.isFinite, threshold >= 0,
        bundleIdentifiers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
        impacts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InvalidData.malformed }
  let indexed = bundleIdentifiers.indices.map { index in
   (index: index, value: EnergyImpact(bundleIdentifier: bundleIdentifiers[index], impact: impacts[index]))
  }
  let ranked = indexed.sorted { left, right in
   if left.value.impact == right.value.impact { return left.index < right.index }
   return left.value.impact > right.value.impact
  }
  return ranked.prefix(5).map { $0.value }.filter { $0.impact > threshold }
 }
}
