import Foundation

@main struct MagSafeTests {
 static func main() throws {
  var state: [UInt8]? = [2]; var writes: [[UInt8]] = []
  var failWrite = false; var wrongReadback = false
  let controller = MagSafeController(read: { state }, write: { bytes in
   if failWrite { throw HardwareError.invalidData("injected write failure") }
   writes.append(bytes); state = wrongReadback && bytes == [4] ? [1] : bytes
  })
  try controller.restore(); precondition(writes.isEmpty)
  try controller.set(.green); precondition(state == [3])
  try controller.set(.orange); precondition(state == [4])
  try controller.restore(); precondition(state == [2]) // Never guessed reset=0.
  writes = []; try controller.set(.orange); state = [1]
  try controller.restore(); precondition(state == [1] && writes == [[4]]) // External ownership.
  state = [3]; writes = []; try controller.set(.green); try controller.restore(); precondition(writes.isEmpty)
  state = [2]; failWrite = true
  do { try controller.set(.off); preconditionFailure("write failure accepted") } catch {}
  precondition(state == [2]); failWrite = false
  try controller.restore()
  state = [2]; wrongReadback = true
  do { try controller.set(.orange); preconditionFailure("readback mismatch accepted") } catch {}
  precondition(state == [1]) // An unowned unexpected value must not be overwritten.
  wrongReadback = false
  for invalid: [UInt8]? in [nil, [], [9], [0, 0]] {
   state = invalid
   do { _ = try controller.status(); preconditionFailure("invalid key accepted") } catch {}
  }
  state = [2]; try controller.set(.green); failWrite = true
  do { try controller.restore(); preconditionFailure("failed restoration accepted") } catch {}
  precondition(state == [3]); failWrite = false; try controller.restore(); precondition(state == [2])
  state = [0]; try controller.set(.off); try controller.restore(); precondition(state == [0])
  state = [2]; writes = []
  let session = MagSafeSession(controller: controller)
  try session.select(.blinkOrange, now: 100); precondition(state == [4])
  try session.tick(now: 100.9); precondition(state == [4])
  try session.select(.blinkOrange, now: 101); precondition(state == [1]) // Heartbeat must not restart blink phase.
  try session.tick(now: 102); precondition(state == [4])
  try session.setOffDuringSleep(true, now: 102)
  try session.sleep(now: 102); precondition(state == [1])
  let sleepingWrites = writes.count
  try session.tick(now: 500); precondition(state == [1] && writes.count == sleepingWrites)
  try session.wake(now: 500); precondition(state == [4])
  try session.select(.green, now: 501); precondition(state == [3])
  try session.sleep(now: 502); precondition(state == [1])
  try session.wake(now: 503); precondition(state == [3])
  try session.select(.system, now: 504); precondition(state == [2])
  try session.sleep(now: 505); precondition(state == [1])
  try session.wake(now: 506); precondition(state == [2])
  try session.restore(); precondition(state == [2])
  print("PASS MagSafe session: monotonic blinking, heartbeat phase, sleep precedence, wake and system restoration")
  print("PASS MagSafe: original-state restore, external writer, no-op, write failure, readback mismatch, key bounds, captured zero")
 }
}
