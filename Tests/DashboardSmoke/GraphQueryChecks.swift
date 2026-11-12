import Foundation

func graphQueryChecks() {
 struct Reading: Equatable { let second: Double; let value: Double }
 let end = Date(timeIntervalSince1970: 1000)
 func query(_ pairs: [(Double, Double)], spacing: Double = 10) -> [Reading] {
  GraphQueryRecords.project(pairs.map { Reading(second: $0.0, value: $0.1) }, endingAt: end,
   spacing: spacing, date: { end.addingTimeInterval($0.second) }, value: { $0.value })
 }
 func seconds(_ pairs: [(Double, Double)], spacing: Double = 10) -> [Double] { query(pairs, spacing: spacing).map(\.second) }
 precondition(seconds([]).isEmpty)
 precondition(seconds([(-100,30)]) == [-100])
 precondition(seconds([(-100,30),(-90,31),(-80,32)]) == [-80], "spacing equality cannot emit a change")
 precondition(seconds([(-100,30),(-89,31),(-78,32)]) == [-89,-78,-78], "first-record seed and final duplicate are intentional")
 precondition(seconds([(-100,30),(-89,31),(-70,31),(-60,32)]) == [-89,-70,-60], "a previous plateau end wins over the changed observation")
 precondition(seconds([(-100,30),(-89,31),(-79,31),(-69,32)]) == [-89,-69], "a plateau endpoint exactly at the spacing boundary is not emitted")
 precondition(seconds([(-100,30),(-89,31),(-79,32),(-68,33)]) == [-89,-68,-68])
 precondition(seconds([(-200,0),(-180,0),(-100,0)]) == [-100], "constant zero uses its real last timestamp")
 precondition(seconds([(-100,30),(-89,31),(-89,32),(-78,33)]) == [-89,-78,-78], "duplicate timestamps do not invent elapsed time")
 precondition(seconds([(-100,30),(-89,31),(-70,.nan),(-60,32),(1,99)]) == [-89,-60,-60])
 precondition(seconds([(-100,.infinity),(-90,.nan)]).isEmpty)
 precondition(seconds([(-400,50),(-220,51),(-40,52)], spacing: 180) == [-40])
 precondition(seconds([(-500,50),(-319,51),(-138,52)], spacing: 180) == [-319,-138,-138])
 let original = [Reading(second: -100,value: 3000),Reading(second: -89,value: 3001)]
 let projected = GraphQueryRecords.project(original, endingAt: end, spacing: 10,
  date: { end.addingTimeInterval($0.second) }, value: { $0.value })
 precondition(original.count == 2 && projected.map(\.value) == [3001,3001])
 precondition(projected.map { $0.value * 0.01 } == [30.01,30.01], "unit conversion follows raw-value selection")
 for invalid in [-1.0, .nan, .infinity] {
  precondition(GraphQueryRecords.project(original, endingAt: end, spacing: invalid,
   date: { end.addingTimeInterval($0.second) }, value: { $0.value }).isEmpty)
 }
 print("PASS shared graph query: query-time seed, strict 0/10/180-second boundaries, previous plateau endpoint preference, final duplicate, duplicate dates, raw-unit comparison, invalid/empty inputs and immutable observations")
}
