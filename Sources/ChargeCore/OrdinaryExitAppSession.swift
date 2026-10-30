import Foundation

/// Unlike numeric final exit, ordinary commit retains the original-value
/// journal. An explicit acknowledged restore can therefore still cancel it,
/// including after an ambiguous commit reply.
public final class OrdinaryExitAppSession {
 public private(set) var id: UUID?
 private var prepared = false
 private var committed = false
 public init() {}
 public func restored() { id = nil; prepared = false; committed = false }
 public func prepare(request: (String) throws -> String) throws {
  if id == nil { id = UUID() }
  guard !committed, let id else { throw OrdinaryExitError.rejected("Ordinary exit already committed") }
  guard try request(OrdinaryExitCommand.prepare(id).wireValue) == "ordinary exit prepared" else { throw OrdinaryExitError.rejected("Invalid ordinary exit preparation reply") }
  prepared = true
 }
 public func renew(request: (String) throws -> String) throws {
  if prepared && !committed { try prepare(request:request) }
 }
 public func commit(request: (String) throws -> String) throws {
  guard let id else { return }
  guard prepared else { throw OrdinaryExitError.rejected("Ordinary exit preparation not acknowledged") }
  guard try request(OrdinaryExitCommand.commit(id).wireValue) == "ordinary exit committed" else { throw OrdinaryExitError.rejected("Invalid ordinary exit commit reply") }
  committed = true
 }
}
