import Foundation

enum GraphValueRange {
 /// Valid observations define the lower edge and twenty-percent upper headroom.
 /// A flat/empty series keeps an explicit nonzero display range.
 static func range(_ observations: [Double]) -> ClosedRange<Double> {
  let values = observations.filter(\.isFinite)
  guard let low = values.min(), let high = values.max() else { return 0...1 }
  let span = high - low
  let upper = span > 0 ? low + span * 1.2 : high + max(1, abs(high) * 0.2)
  if upper.isFinite && upper > low { return low...upper }
  return 0...max(1, high)
 }
}
