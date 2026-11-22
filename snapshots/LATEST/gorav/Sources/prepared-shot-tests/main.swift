import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVPlaybackCore

// arch-195b R4 witness: PreparedShotSessionBackend atomic multi-source op.
// Two fixtures (video A, video B) + separate source audio S; replace video at a
// film time mid-shot; receipts must prove no audio restart and no clock rebase.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

struct StubValidator: PreparedShotSourceValidator {
    let known: Set<String>
    let audioSurvives: Bool
    func canBind(_ s: SourceRef) -> Bool { known.contains(s.id) }
    func audioSurvivesVideoReplace(_ a: SourceRef) -> Bool { audioSurvives }
}

func t(_ v: Int64, _ ts: Int32 = 1_000_000) -> RationalTime { try! RationalTime(value: v, timescale: ts) }

// Fixtures
let videoA = SourceRef(id: "fixture-shotA.mp4", kind: .local, startOffset: t(0))
let videoB = SourceRef(id: "fixture-shotB.mp4", kind: .local, startOffset: t(0))
let audioS = SourceRef(id: "fixture-score.wav", kind: .local, startOffset: t(2_000_000)) // +2s offset on the film clock

// W1: mid-shot replace preserves audio binding and epoch
let coord1 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, videoB.id, audioS.id], audioSurvives: true))
let shotID = UUID()
let shot = PreparedShot(shotID: shotID, video: videoA, audio: audioS, filmClockEpoch: 7)
do {
    let r1 = try await coord1.prepare(shot)
    check("W1a prepare receipt epoch", r1.epoch == 7)
    check("W1b prepare receipt shotID", r1.shotID == shotID)
    check("W1c audio bound at prepare", r1.audioBindingID != nil && r1.audioBindingPreserved)
    check("W1d prepare commits at video startOffset", r1.committedAt == t(0))
    check("W1e no prior video at prepare", r1.priorVideo == nil)
    let mid: RationalTime = t(4_500_000) // film time 4.5s, mid-shot
    let r2 = try await coord1.replaceVideo(at: mid, with: videoB)
    check("W2a replace keeps epoch (no rebase)", r2.epoch == r1.epoch)
    check("W2b audio binding id identical (no restart)", r2.audioBindingID != nil && r2.audioBindingID == r1.audioBindingID)
    check("W2c audioBindingPreserved", r2.audioBindingPreserved)
    check("W2d committedAt equals requested film time", r2.committedAt == mid)
    check("W2e prior video is fixture A", r2.priorVideo == videoA)
    let cur = await coord1.currentReceipt()
    check("W2f currentReceipt is the replace receipt", cur?.audioBindingID == r1.audioBindingID && cur?.committedAt == mid)
} catch {
    check("W1/W2 unexpected throw \(error)", false)
}

// W3: atomic failure on audioBindingLost - state must be exactly as before
let coord2 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, videoB.id, audioS.id], audioSurvives: false))
do {
    let r1 = try await coord2.prepare(PreparedShot(shotID: UUID(), video: videoA, audio: audioS, filmClockEpoch: 3))
    do {
        _ = try await coord2.replaceVideo(at: t(1_000_000), with: videoB)
        check("W3a audioBindingLost thrown", false)
    } catch PreparedShotError.audioBindingLost {
        let cur = await coord2.currentReceipt()
        check("W3a audioBindingLost thrown", true)
        check("W3b atomic: receipt unchanged after failed replace", cur?.committedAt == r1.committedAt && cur?.priorVideo == nil && cur?.audioBindingID == r1.audioBindingID)
    } catch {
        check("W3a audioBindingLost thrown (got \(error))", false)
    }
} catch {
    check("W3 prepare threw \(error)", false)
}

// W4: replace without prepare -> sourceNotPrepared
let coord3 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id], audioSurvives: true))
do {
    _ = try await coord3.replaceVideo(at: t(0), with: videoA)
    check("W4 sourceNotPrepared thrown", false)
} catch PreparedShotError.sourceNotPrepared {
    check("W4 sourceNotPrepared thrown", true)
} catch {
    check("W4 sourceNotPrepared thrown (got \(error))", false)
}

// W5: double prepare -> staleEpoch
let coord4 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, audioS.id], audioSurvives: true))
do {
    _ = try await coord4.prepare(PreparedShot(shotID: UUID(), video: videoA, audio: audioS, filmClockEpoch: 1))
    do {
        _ = try await coord4.prepare(PreparedShot(shotID: UUID(), video: videoA, audio: audioS, filmClockEpoch: 2))
        check("W5 staleEpoch thrown", false)
    } catch PreparedShotError.staleEpoch {
        check("W5 staleEpoch thrown", true)
    }
} catch {
    check("W5 first prepare threw \(error)", false)
}

// W6: admission refusal on unknown source
let coord5 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id], audioSurvives: true))
do {
    _ = try await coord5.prepare(PreparedShot(shotID: UUID(), video: videoB, audio: nil, filmClockEpoch: 1))
    check("W6 admissionRefused thrown", false)
} catch PreparedShotError.admissionRefused {
    check("W6 admissionRefused thrown", true)
} catch {
    check("W6 admissionRefused thrown (got \(error))", false)
}

// W7: video-only shot replace works, no binding claimed
let coord6 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, videoB.id], audioSurvives: true))
do {
    let r1 = try await coord6.prepare(PreparedShot(shotID: UUID(), video: videoA, audio: nil, filmClockEpoch: 9))
    let r2 = try await coord6.replaceVideo(at: t(500_000), with: videoB)
    check("W7a video-only has no binding", r1.audioBindingID == nil && r2.audioBindingID == nil)
    check("W7b epoch preserved", r2.epoch == 9 && r1.epoch == 9)
    check("W7c prior video recorded", r2.priorVideo == videoA)
} catch {
    check("W7 threw \(error)", false)
}

// W8: cancel clears state; replace after cancel refuses
let coord7 = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, videoB.id], audioSurvives: true))
do {
    _ = try await coord7.prepare(PreparedShot(shotID: UUID(), video: videoA, audio: nil, filmClockEpoch: 1))
    await coord7.cancel()
    let cur = await coord7.currentReceipt()
    check("W8a receipt cleared after cancel", cur == nil)
    do {
        _ = try await coord7.replaceVideo(at: t(0), with: videoB)
        check("W8b replace after cancel refuses", false)
    } catch PreparedShotError.sourceNotPrepared {
        check("W8b replace after cancel refuses", true)
    }
} catch {
    check("W8 threw \(error)", false)
}

// Adoption release is nonterminal, unlike cancel. Check the actual coordinator.
let releaseCoordinator = PreparedShotCoordinator(validator: StubValidator(known: [videoA.id, videoB.id, audioS.id], audioSurvives: true))
let adoptedShot = PreparedShot(shotID: UUID(), video: videoA, audio: audioS, filmClockEpoch: 12)
_ = try await releaseCoordinator.prepare(adoptedShot)
let released = await releaseCoordinator.abortUncommittedPreparation()
check("A1 uncommitted adoption releases", released == .released)
check("A2 receipt cleared", await releaseCoordinator.currentReceipt() == nil)
check("A3 repeated abort idempotent", await releaseCoordinator.abortUncommittedPreparation() == .noAdoption)
_ = try await releaseCoordinator.prepare(adoptedShot)
do {
    _ = try await releaseCoordinator.replaceVideo(at: t(0), with: SourceRef(id: "missing", kind: .local, startOffset: t(0)))
    check("A4 staging refusal", false)
} catch { check("A4 staging refusal", true) }
check("A5 failed first swap releases", await releaseCoordinator.abortUncommittedPreparation() == .released)
_ = try await releaseCoordinator.prepare(adoptedShot)
let committedReceipt = try await releaseCoordinator.replaceVideo(at: t(1), with: videoB)
check("A6 committed abort refuses", await releaseCoordinator.abortUncommittedPreparation() == .alreadyCommitted)
check("A7 committed binding retained", await releaseCoordinator.currentReceipt()?.audioBindingID == committedReceipt.audioBindingID)
await releaseCoordinator.cancel()
check("A8 explicit cancel terminal", await releaseCoordinator.currentReceipt() == nil)

// This same value gate guards real live-session staging across suspension.
var gate = PreparedAdoption(); gate.adopt()
check("A9 operation admitted", gate.beginOperation())
check("A10 busy abort never releases", gate.abortUncommitted() == .operationInFlight)
check("A11 overlap refused", !gate.beginOperation())
gate.finishOperation(didCommit: false) // cancelled task, late boundary or preroll failure
check("A12 cancelled/late staging releases", gate.abortUncommitted() == .released)
gate.adopt(); _ = gate.beginOperation(); gate.finishOperation(didCommit: true)
check("A13 commit ownership cannot be aborted", gate.abortUncommitted() == .alreadyCommitted)
gate.clear()
check("A14 teardown clears gate", gate.abortUncommitted() == .noAdoption)

print(failures == 0 ? "prepared-shot-tests: all pass" : "prepared-shot-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
