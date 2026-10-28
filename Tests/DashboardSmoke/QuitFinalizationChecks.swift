import Foundation
import ChargeCore

@MainActor func quitFinalizationChecks() {
 enum Failure: Error { case fixture }
 var events: [String] = []
 let success = QuitFlow(waitForPower:false,prepare:{events.append("prepare")},cancelControl:{events.append("cancel")},finalize:{events.append("commit")},reply:{events.append("reply:\($0)")})
 precondition(success.beginPreparation()); success.poll()
 precondition(events == ["prepare","commit","reply:true"])
 success.cancel(); precondition(events.count == 3)
 // Waiting renews only preparation, including while a decision is displayed.
 events = []; var renewalFails = false
 let leased = QuitFlow(waitForPower:true,timeout:2,prepare:{events.append("prepare")},readPower:{.unknown},cancelControl:{events.append("restore")},renewPreparation:{events.append("renew");if renewalFails { throw Failure.fixture }},finalize:{events.append("unexpected commit")},reply:{events.append("reply:\($0)")},clock:{0})
 precondition(leased.beginPreparation()); leased.poll(); leased.renewLease()
 renewalFails = true; leased.renewLease(); precondition(leased.phase == .needsDecision)
 leased.renewLease(); precondition(events == ["prepare","renew","renew"])
 leased.cancel(); leased.renewLease(); precondition(events == ["prepare","renew","renew","restore","reply:false"])
 var now = 0.0
 events = []
 let waiting = QuitFlow(waitForPower:true,timeout:2,prepare:{events.append("prepare")},readPower:{.unknown},cancelControl:{events.append("restore")},finalize:{events.append("unexpected commit")},reply:{events.append("reply:\($0)")},clock:{now})
 precondition(waiting.beginPreparation()); waiting.poll(); now = 3; waiting.poll()
 precondition(waiting.phase == .needsDecision); waiting.cancel()
 precondition(events == ["prepare","restore","reply:false"])
 for exitAnyway in [false,true] {
  events = []; var attempted = false; var loseReply = true
  let flow = QuitFlow(waitForPower:false,prepare:{events.append("prepare")},cancelControl:{events.append("unexpected restore")},finalize:{
   attempted = true; events.append("commit"); if loseReply { throw Failure.fixture }
  },commitStarted:{attempted},reply:{events.append("reply:\($0)")})
  precondition(flow.beginPreparation()); flow.poll()
  precondition(flow.finalizationFailed && flow.irreversible && !flow.canCancel && flow.phase == .needsDecision)
  flow.cancel(); precondition(events == ["prepare","commit"])
  if exitAnyway { flow.force(); precondition(events == ["prepare","commit","reply:true"]) }
  else { loseReply = false; flow.retry(); precondition(events == ["prepare","commit","commit","reply:true"]) }
 }
 // A local failure before commit delivery remains cancellable and retryable.
 events = []; var localFailure = true
 let local = QuitFlow(waitForPower:false,prepare:{events.append("prepare")},cancelControl:{events.append("restore")},finalize:{events.append("confirm"); if localFailure { throw Failure.fixture }},reply:{events.append("reply:\($0)")})
 precondition(local.beginPreparation()); local.poll(); precondition(local.finalizationFailed && local.canCancel)
 localFailure = false; local.retry(); local.poll()
 precondition(events == ["prepare","confirm","prepare","confirm","reply:true"])
 print("PASS quit finalization: commit before termination reply, cancellable preparation, no rollback claim after ambiguous commit, same-commit retry and explicit unconfirmed exit; no windows, helper or hardware")
}
