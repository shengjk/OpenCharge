import SwiftUI

struct BatteryStatisticArchiveRequest: Equatable {
 let url: URL?
 let hours: Int
 let revision: Int
 let active: Bool
 let metric: BatteryStatistic
 let endingAt: Date
}

@MainActor final class BatteryStatisticArchiveLoader: ObservableObject {
 @Published private(set) var records: [BatteryStatisticRecord] = []
 @Published private(set) var loading = false
 @Published private(set) var error: String?
 typealias Read = @Sendable (BatteryStatisticArchive, Int, Date, BatteryStatistic?) throws -> [BatteryStatisticRecord]
 private let read: Read
 private var generation = 0
 init(read: @escaping Read = { try $0.load(hours: $1, endingAt: $2, compactFor: $3) }) { self.read = read }

 func load(archive: BatteryStatisticArchive?, hours: Int, endingAt end: Date, active: Bool, metric: BatteryStatistic? = nil) {
  generation &+= 1
  let token = generation
  guard let archive else { records = []; error = nil; loading = false; return }
  guard active else { loading = false; return }
  loading = true; error = nil
  let read = self.read
  DispatchQueue.global(qos: .utility).async {
   let result = Result { try read(archive, hours, end, metric) }
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
