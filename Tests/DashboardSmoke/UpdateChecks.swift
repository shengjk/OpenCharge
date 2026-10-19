import Foundation
import ChargeCore

@MainActor func updateChecks() throws {
 let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCharge-update-hash-" + UUID().uuidString)
 try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
 defer { try? FileManager.default.removeItem(at: folder) }
 let file = folder.appendingPathComponent("fixture.zip")
 try Data("abc".utf8).write(to: file)
 let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
 try ReleaseHTTP.verify(file, size: 3, expected: hash)
 func rejects(_ run: () throws -> Void) { do { try run(); preconditionFailure("unsafe download accepted") } catch {} }
 rejects { try ReleaseHTTP.verify(file, size: 4, expected: hash) }
 rejects { try ReleaseHTTP.verify(file, size: 2, expected: hash) }
 try Data("abd".utf8).write(to: file)
 rejects { try ReleaseHTTP.verify(file, size: 3, expected: hash) }
 for address in ["http://github.com/a", "https://github.com.evil.test/a", "https://token@github.com/a", "file:///tmp/a", "https://github.com:444/a"] {
  precondition(!ReleaseRedirects.allowed(URL(string: address)!))
 }
 for address in ["https://api.github.com/repos/shengjk/OpenCharge/releases", "https://release-assets.githubusercontent.com/a", "https://github.com/shengjk/OpenCharge/releases"] { precondition(ReleaseRedirects.allowed(URL(string: address)!)) }
 let suite = "org.opencharge.update-fixture." + UUID().uuidString
 let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
 let updates = AppUpdates(defaults: defaults, currentVersion: "0.3.10")
 precondition(!updates.automaticChecks && updates.includePreviews && updates.candidate == nil && !updates.busy)
 print("Update download/hash/redirect/default checks passed; no network, install or hardware action")
}
