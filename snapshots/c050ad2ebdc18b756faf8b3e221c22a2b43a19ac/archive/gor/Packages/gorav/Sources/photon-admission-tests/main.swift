import Foundation
import GorAVPlaybackCore

// photon-admission-tests (P29-ADMISSION, DR-0018, lane c): acceptance receipt for
// the Swift re-expression of photon-admission.lua. Positive paths plus a negative
// control for EVERY refusal reason in the source protocol. Receipts assert host
// parameter acceptance only; the witness binds no media and no GPU.

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}
typealias A = PhotonAdmission

let doc = A.Document(gen: 1, name: "clip")
var now = 0.0
var applied: [Double] = []
var applyOK = true
func makeReceiver() -> A.Receiver {
    A.Receiver(base: 10, cacheCapacity: 2,
               apply: { v in if applyOK { applied.append(v) }; return applyOK },
               clock: { now })
}
func cmd(_ r: A.Receiver, id: Int, mult: Double = 2, rev: Int? = nil, serialFloor: Int = 0,
         expected: Double? = nil, d: A.Document? = nil) -> A.Command {
    A.Command(doc: d ?? doc, id: id, revision: rev ?? r.revision, serialFloor: serialFloor,
              mult: mult, expectedStrength: expected ?? 10 * mult)
}

// -- A. Ring ----------------------------------------------------------------------
do {
    let ring = A.Ring(capacity: 3)
    for i in 1...5 { ring.record(["n": "\(i)"]) }
    let (events, dropped) = ring.snapshot()
    check("A1.ringOrder", events.map { $0["n"] } == ["3", "4", "5"])
    check("A2.ringDropped", dropped == 2)
}

// -- B. Receiver positive paths ----------------------------------------------------
do {
    let r = makeReceiver()
    check("B1.bindFirst", r.bind(doc, enabled: true))
    check("B2.rebindSameDocRefused", !r.bind(doc, enabled: true))
    let v = r.auto(cmd(r, id: 1))
    check("B3.applied", v.status == .applied && v.origin == "AUTO_COMMAND" && v.acceptedStrength == 20 && r.revision == 1)
    let dup = r.auto(cmd(r, id: 1, rev: 0))
    check("B4.duplicateReemit", dup.status == .applied && dup.revision == 1 && dup.commandId == 1)
    let noop = r.auto(cmd(r, id: 2))
    check("B5.noop", noop.status == .noop && noop.revision == 1)
    let (action, err) = r.manualStrength(25)
    check("B6.manual", action != nil && err == nil && r.suppressed && action?.strength == 25 && action?.origin == "MANUAL_STRENGTH")
    let (okResume, _) = r.resume(doc: doc, actionId: action!.actionId, revision: action!.revision)
    check("B7.resume", okResume && !r.suppressed)
    let (dupResume, dupErr) = r.resume(doc: doc, actionId: action!.actionId, revision: action!.revision)
    check("B8.resumeDuplicate", dupResume && dupErr == "duplicate")
    let highBefore = r.commandHigh
    r.invalidate(reason: "test")
    check("B9.invalidateKeepsHighWater", r.revision == 3 && r.commandHigh == highBefore && r.manual == nil && !r.suppressed)
    check("B10.publishSerial", r.publish() == 1 && r.publish() == 2)
}

// -- C. Receiver negative controls (every source reason) ---------------------------
do {
    let r = makeReceiver(); _ = r.bind(doc, enabled: true)
    check("C1.malformedNil", r.auto(nil).reason == "malformed")
    check("C2.malformedIdZero", r.auto(cmd(r, id: 0)).reason == "malformed")
    check("C3.malformedMultLow", r.auto(cmd(r, id: 1, mult: 0.4, expected: 4)).reason == "malformed")
    check("C4.malformedMultNaN", r.auto(cmd(r, id: 1, mult: .nan, expected: .nan)).reason == "malformed")
    check("C5.malformedDocEmpty", r.auto(cmd(r, id: 1, d: A.Document(gen: 1, name: ""))).reason == "malformed")
    check("C6.document", r.auto(cmd(r, id: 1, d: A.Document(gen: 2, name: "clip"))).reason == "document")
    _ = r.auto(cmd(r, id: 1))
    check("C7.duplicateConflict", r.auto(cmd(r, id: 1, mult: 3, rev: 0, expected: 30)).reason == "duplicate-conflict")
    _ = r.auto(cmd(r, id: 2)); _ = r.auto(cmd(r, id: 3)) // cache cap 2: id 1 evicted
    check("C8.staleEvicted", r.auto(cmd(r, id: 1, rev: 0)).reason == "stale-evicted")
    check("C9.revision", r.auto(cmd(r, id: 4, rev: 99)).reason == "revision")
    check("C10.serial", r.auto(cmd(r, id: 5, serialFloor: 99)).reason == "serial")
    _ = r.bind(A.Document(gen: 9, name: "other"), enabled: false)
    check("C11.disabled", r.auto(A.Command(doc: A.Document(gen: 9, name: "other"), id: 1, revision: 0, serialFloor: 0, mult: 2, expectedStrength: 20)).reason == "disabled")
    _ = r.bind(doc, enabled: true)
    _ = r.manualStrength(5)
    check("C12.manualOverride", r.auto(cmd(r, id: 1, mult: 0.5, rev: r.revision, expected: 5)).reason == "manual-override")
    let r2 = makeReceiver(); _ = r2.bind(doc, enabled: true)
    check("C13.baseMismatch", r2.auto(cmd(r2, id: 1, expected: 19.999)).reason == "base-mismatch")
    check("C14.hostRange", r2.auto(cmd(r2, id: 2, mult: 8, expected: 80)).reason == "host-range")
    applyOK = false
    check("C15.applyFailed", r2.auto(cmd(r2, id: 3)).reason == "apply-failed" && r2.revision == 0)
    applyOK = true
    let (noAction, noErr) = r2.manualStrength(.nan)
    check("C16.invalidManualNaN", noAction == nil && noErr == "invalid-manual")
    let r3 = makeReceiver() // never bound/enabled
    let (noAction2, noErr2) = r3.manualStrength(5)
    check("C17.invalidManualDisabled", noAction2 == nil && noErr2 == "invalid-manual")
    let (badResume, badResumeErr) = r2.resume(doc: doc, actionId: 99, revision: 0)
    check("C18.staleResume", !badResume && badResumeErr == "stale-resume")
}

// -- D. Sender positive path + fences ----------------------------------------------
do {
    now = 0
    var saved: [Double] = []
    var resumedCalls = 0
    let s = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true,
                     save: { v, _ in saved.append(v); return true },
                     resume: { _, _, _ in resumedCalls += 1; return true })
    check("D1.bindSender", s.bind(doc, revision: 0, serial: 0, base: 10))
    check("D2.rebindSameDocRefused", !s.bind(doc, revision: 0, serial: 0, base: 10))
    let (c, e) = s.send(2)
    check("D3.send", c != nil && e == nil && s.state == .autoPending && c?.expectedStrength == 20)
    let ackReceipt = A.Receipt(docGen: 1, docName: "clip", commandId: c!.id, revision: 1, serial: 0,
                               status: .applied, reason: nil, origin: "AUTO_COMMAND",
                               acceptedStrength: 20, base: 10)
    now = 1
    check("D4.ack", s.ack(ackReceipt) && s.state == .ready && s.revision == 1)
    // manual + learning
    let action = A.Receiver.ManualAction(doc: doc, actionId: 1, revision: 2, strength: 12,
                                         kind: "strength", origin: "MANUAL_STRENGTH", resumed: false)
    check("D5.manualReceipt", s.manual(action) && s.state == .manual)
    check("D6.sampleNotEnough", !s.sample(11, scene: 0, revisionAfter: 2) && s.state == .manual)
    check("D7.sampleMedian", s.sample(13, scene: 0, revisionAfter: 2) == false)
    check("D8.learn", s.sample(12, scene: 0, revisionAfter: 2) && s.lookR == 12 && saved == [12] && resumedCalls == 1 && s.state == .ready && !s.receiverSuppressionUnresolved)
    // timeout
    _ = s.send(2)
    now = 100
    s.timeoutTick()
    check("D9.timeout", s.state == .holdUnresolved && s.reason == "timeout")
}

// -- E. Sender negative controls -----------------------------------------------------
do {
    now = 0
    let s = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true)
    _ = s.bind(doc, revision: 0, serial: 0, base: 10)
    check("E1.ackIgnoredNoPending", !s.ack(A.Receipt(docGen: 1, docName: "clip", commandId: 1, revision: 1, serial: 0, status: .applied, reason: nil, origin: "AUTO_COMMAND", acceptedStrength: 20, base: 10)))
    let c = s.send(2).command!
    func ackR(status: A.Status, rev: Int, accepted: Double = 20, origin: String? = "AUTO_COMMAND", serial: Int = 0, base: Double = 10, reason: String? = nil) -> A.Receipt {
        A.Receipt(docGen: 1, docName: "clip", commandId: c.id, revision: rev, serial: serial,
                  status: status, reason: reason, origin: origin, acceptedStrength: accepted, base: base)
    }
    check("E2.rejectedHolds", !s.ack(ackR(status: .rejected, rev: 0, reason: "disabled")) && s.state == .holdUnresolved && s.reason == "rejected:disabled")
    check("E3.holdNotBypassedByRebind", !s.bind(doc, revision: 0, serial: 0, base: 10) && s.state == .holdUnresolved)
    let s2 = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true)
    _ = s2.bind(doc, revision: 0, serial: 0, base: 10)
    let c2 = s2.send(2).command!
    func ack2(status: A.Status, rev: Int, accepted: Double = 20, origin: String? = "AUTO_COMMAND", serial: Int = 0, base: Double = 10) -> A.Receipt {
        A.Receipt(docGen: 1, docName: "clip", commandId: c2.id, revision: rev, serial: serial,
                  status: status, reason: nil, origin: origin, acceptedStrength: accepted, base: base)
    }
    check("E4.invalidAckRevision", !s2.ack(ack2(status: .applied, rev: 5)) && s2.reason == "invalid-ack")
    let s3 = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true)
    _ = s3.bind(doc, revision: 0, serial: 0, base: 10)
    let c3 = s3.send(2).command!
    let wrongStrength = A.Receipt(docGen: 1, docName: "clip", commandId: c3.id, revision: 1, serial: 0, status: .applied, reason: nil, origin: "AUTO_COMMAND", acceptedStrength: 21, base: 10)
    check("E5.invalidAckStrength", !s3.ack(wrongStrength) && s3.reason == "invalid-ack")
    let s4 = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true)
    _ = s4.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s4.send(2)
    let wrongOrigin = A.Receipt(docGen: 1, docName: "clip", commandId: 1, revision: 1, serial: 0, status: .applied, reason: nil, origin: "OPERATOR", acceptedStrength: 20, base: 10)
    check("E6.invalidAckOrigin", !s4.ack(wrongOrigin))
    let s5 = A.Sender(clock: { now }, timeout: 5, manualIdentityBound: true)
    _ = s5.bind(doc, revision: 0, serial: 0, base: 10)
    check("E7.hostRangeSendSkipped", s5.send(8).command == nil && s5.send(8).error == "host-range" && s5.state == .ready)
    check("E8.multOutOfRangeNil", s5.send(0.1).command == nil)
    // manual fences
    let unbound = A.Sender(clock: { now }, manualIdentityBound: false)
    _ = unbound.bind(doc, revision: 0, serial: 0, base: 10)
    let act = A.Receiver.ManualAction(doc: doc, actionId: 1, revision: 1, strength: 12, kind: "strength", origin: "MANUAL_STRENGTH", resumed: false)
    check("E9.manualIdentityUnbound", !unbound.manual(act) && unbound.reason == "manual-identity-unbound")
    let s6 = A.Sender(clock: { now }, manualIdentityBound: true)
    _ = s6.bind(doc, revision: 5, serial: 0, base: 10)
    check("E10.invalidManualStaleRevision", !s6.manual(act) && s6.reason == "invalid-manual")
    let s7 = A.Sender(clock: { now }, manualIdentityBound: true, save: { _, _ in true }, resume: { _, _, _ in true })
    _ = s7.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s7.manual(act)
    check("E11.learningFenceValue", !s7.sample(0, scene: 0, revisionAfter: 1) && s7.reason == "learning-fence")
    let s8 = A.Sender(clock: { now }, manualIdentityBound: true, save: { _, _ in true }, resume: { _, _, _ in true })
    _ = s8.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s8.manual(act)
    _ = s8.sample(10, scene: 0, revisionAfter: 1)
    check("E12.sceneChange", !s8.sample(11, scene: 1, revisionAfter: 1) && s8.reason == "scene-change")
    let s9 = A.Sender(clock: { now }, manualIdentityBound: true, save: { _, _ in false }, resume: { _, _, _ in true })
    _ = s9.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s9.manual(act)
    _ = s9.sample(10, scene: 0, revisionAfter: 1); _ = s9.sample(11, scene: 0, revisionAfter: 1)
    check("E13.saveFailed", !s9.sample(12, scene: 0, revisionAfter: 1) && s9.reason == "save-failed")
    let s10 = A.Sender(clock: { now }, manualIdentityBound: true, save: { _, _ in true }, resume: { _, _, _ in false })
    _ = s10.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s10.manual(act)
    _ = s10.sample(10, scene: 0, revisionAfter: 1); _ = s10.sample(11, scene: 0, revisionAfter: 1)
    check("E14.resumeFailed", !s10.sample(12, scene: 0, revisionAfter: 1) && s10.reason == "resume-failed")
    // unqualified timeout stays pending
    let s11 = A.Sender(clock: { now })
    _ = s11.bind(doc, revision: 0, serial: 0, base: 10)
    _ = s11.send(2)
    now = 1000
    s11.timeoutTick()
    check("E15.unqualifiedTimeoutPending", s11.state == .autoPending)
}

// -- F. Persistence codec -------------------------------------------------------------
do {
    check("F1.roundtrip", A.decodeLook(A.encodeLook(12.5)!) == 12.5)
    check("F2.formatPinned", A.encodeLook(12.5) == "manual-action-v2\n12.5\n")
    check("F3.decodeGarbageNil", A.decodeLook("manual-action-v2\nabc\n") == nil)
    check("F4.decodeNoTrailingNlNil", A.decodeLook("manual-action-v2\n12.5") == nil)
    check("F5.decodeExtraLineNil", A.decodeLook("manual-action-v2\n12.5\n13\n") == nil)
    check("F6.decodeRangeNil", A.decodeLook("manual-action-v2\n0\n") == nil && A.decodeLook("manual-action-v2\n100\n") == nil)
    check("F7.encodeRangeNil", A.encodeLook(0) == nil && A.encodeLook(100) == nil && A.encodeLook(.nan) == nil)
    check("F8.namespace", A.namespace == "~~state/gor_look_manual_v2.txt" && A.schema == "manual-action-v2")
}

print("FINAL pass=\(pass) fail=\(fail)")
exit(fail == 0 ? 0 : 1)
