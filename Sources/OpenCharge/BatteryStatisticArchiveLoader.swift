import SwiftUI

enum BatteryStatisticSeries: String, CaseIterable, Identifiable {
 case channels, observations
 var id: Self { self }
 var title: String { self == .channels ? NSLocalizedString("周期记录",comment:"") : NSLocalizedString("原始观察",comment:"") }
}

struct BatteryStatisticArchiveRequest: Equatable {
 let url: URL?
 let hours: Int
 let revision: Int
 let active: Bool
 let metric: BatteryStatistic
 let endingAt: Date
 let series: BatteryStatisticSeries
 let designCapacity: Double?
}

@MainActor final class BatteryStatisticArchiveLoader: ObservableObject {
 @Published private(set) var records: [BatteryStatisticRecord] = []
 @Published private(set) var loading = false
 @Published private(set) var error: String?
 typealias Read = @Sendable (BatteryStatisticArchive, Int, Date, BatteryStatistic?) throws -> [BatteryStatisticRecord]
 private let read: Read
 private struct Selection: Equatable {
  let url: URL; let metric: BatteryStatistic?; let series: BatteryStatisticSeries; let designCapacity: Double?
 }
 private var selection: Selection?
 private var generation = 0
 init(read: @escaping Read = { try $0.load(hours: $1, endingAt: $2, compactFor: $3) }) { self.read = read }

 func load(archive: BatteryStatisticArchive?, hours: Int, endingAt end: Date, active: Bool, metric: BatteryStatistic? = nil, series: BatteryStatisticSeries = .observations, designCapacity: Double? = nil) {
  generation &+= 1
  let token = generation
  guard let archive else { records = []; error = nil; loading = false; selection = nil; return }
  let next = Selection(url:archive.url,metric:metric,series:series,designCapacity:designCapacity)
  if selection != next { records = []; error = nil; selection = next }
  guard active else { loading = false; return }
  loading = true; error = nil
  let read = self.read
  DispatchQueue.global(qos: .utility).async {
   let result = Result {
    if series == .channels, let metric { return try archive.loadChannels(hours:hours,endingAt:end,metric:metric,designCapacity:designCapacity) }
    return try read(archive, hours, end, metric)
   }
   DispatchQueue.main.async { [weak self] in
    guard let self, self.generation == token else { return }
    self.loading = false
    switch result {
    case .success(let records): self.records = records
    case .failure(let failure): self.records = []; self.error = failure.localizedDescription
    }
   }
  }
 }
 func cancel() { generation &+= 1; loading = false }
}
