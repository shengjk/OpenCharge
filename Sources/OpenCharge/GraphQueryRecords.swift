import Foundation

/// Project ordered observations for display without editing their source history.
/// Comparisons use the original value; callers apply any display-unit conversion afterwards.
enum GraphQueryRecords {
 static func project<Element>(_ observations: [Element], endingAt end: Date,
                              spacing: TimeInterval, date: (Element) -> Date,
                              value: (Element) -> Double) -> [Element] {
  guard end.timeIntervalSinceReferenceDate.isFinite, spacing.isFinite, spacing >= 0 else { return [] }
  var previous: Element?
  var previousDate = end
  var previousValue = 0.0
  var result: [Element] = []
  for observation in observations {
   let timestamp = date(observation), raw = value(observation)
   guard timestamp.timeIntervalSinceReferenceDate.isFinite, timestamp <= end, raw.isFinite else { continue }
   if raw != previousValue {
    if let last = result.last, let previous,
       previousDate.timeIntervalSince(date(last)) > spacing {
     result.append(previous)
    } else if timestamp.timeIntervalSince(previousDate) > spacing {
     result.append(observation)
    }
   }
   previous = observation; previousDate = timestamp; previousValue = raw
  }
  // Keep the final observation, including an already-emitted endpoint. A query
  // with no valid observations stays unavailable rather than inventing a zero.
  if let previous { result.append(previous) }
  return result
 }
}
