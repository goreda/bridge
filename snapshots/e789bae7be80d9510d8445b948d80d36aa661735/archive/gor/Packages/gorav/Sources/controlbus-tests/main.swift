// Sources/controlbus-tests/main.swift  (exit 0 = all pass)
import GorAVPlaybackCore
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var failures = 0
func check(_ n: String, _ ok: Bool) { print(ok ? "PASS \(n)" : "FAIL \(n)"); if !ok { failures += 1 } }
let rev = { (v: UInt64) in ParameterBlockRevision(v) }
let tok = { (s: String) in ModeToken(s)! }
func plan(_ out: String = "full_sbs", enabled: Bool = true, pack: Int = 3) -> RoutePlan {
    RoutePlan(projection: tok("flat-sbs"), engine: tok("flat_\(out)"), output: tok(out), enabled: enabled, pack: pack, aspect: 0)!
}
func film(_ seq: Double, scale: Double = 1, w: Double = 0.8) -> FilmFrameGeometry {
    FilmFrameGeometry(sequence: seq, scale: scale, angle: 0, leftX: 0.5, leftY: 0.5, replicaX: 0, replicaY: 0,
                      width: w, height: 0.8, frameW: 0.8, frameH: 0.8, baseX: 0.5, baseY: 0.5,
                      layout: 3, instances: 2, clipX: 0, clipY: 0, clipW: 0, clipH: 0)!
}
func rcpt(_ r: UInt64, g: UInt64 = 0, seq: Double = 1, pts: Double? = 1.0, hasFilm: Bool = true) -> PresentationReceipt {
    PresentationReceipt(ptsSeconds: pts, film: hasFilm ? film(seq) : nil, crop: .full,
                        projection: tok("flat-sbs"), output: tok("full_sbs"), revision: rev(r), generation: g)
}

// Values
check("V1 rect rejects NaN", NormalizedRect(x: .nan, y: 0, w: 1, h: 1) == nil)
check("V2 rect rejects zero size", NormalizedRect(x: 0, y: 0, w: 0, h: 1) == nil)
check("V3 rect rejects outside unit square", NormalizedRect(x: 0.5, y: 0, w: 0.6, h: 1) == nil)
check("V4 token rejects empty, space, non-ascii, long", ModeToken("") == nil && ModeToken("a b") == nil && ModeToken("caf\u{e9}") == nil && ModeToken(String(repeating: "a", count: 33)) == nil)
check("V5 token accepts real gor names", ModeToken("flat-sbs") != nil && ModeToken("vr180-tb") != nil && ModeToken("nativeVR180") != nil && ModeToken("vr_gap_frac") != nil)
check("V6 plan rejects bad pack and aspect", RoutePlan(projection: tok("vr180"), engine: tok("nativeVR180"), output: tok("vr180"), enabled: true, pack: -1, aspect: 0) == nil
      && RoutePlan(projection: tok("vr180"), engine: tok("nativeVR180"), output: tok("vr180"), enabled: true, pack: 0, aspect: .nan) == nil
      && RoutePlan(projection: tok("vr180"), engine: tok("nativeVR180"), output: tok("vr180"), enabled: true, pack: 256, aspect: 0) == nil)
check("V7 film geometry rejects the cases gor rejects today",
      FilmFrameGeometry(sequence: 1, scale: 0, angle: 0, leftX: 0, leftY: 0, replicaX: 0, replicaY: 0, width: 1, height: 1, frameW: 1, frameH: 1, baseX: 0, baseY: 0, layout: 0, instances: 1, clipX: 0, clipY: 0, clipW: 0, clipH: 0) == nil
      && FilmFrameGeometry(sequence: 1, scale: 1, angle: .infinity, leftX: 0, leftY: 0, replicaX: 0, replicaY: 0, width: 1, height: 1, frameW: 1, frameH: 1, baseX: 0, baseY: 0, layout: 0, instances: 1, clipX: 0, clipY: 0, clipW: 0, clipH: 0) == nil
      && FilmFrameGeometry(sequence: 1, scale: 1, angle: 0, leftX: 0, leftY: 0, replicaX: 0, replicaY: 0, width: 0, height: 1, frameW: 1, frameH: 1, baseX: 0, baseY: 0, layout: 0, instances: 1, clipX: 0, clipY: 0, clipW: 0, clipH: 0) == nil)

// Bus
var b = ControlBus()
check("B1 refuses when not open", b.send(.setCrop(.full)) == .refused(.notOpen))
b.open()
check("B2 first look accepted", b.send(.setLook(revision: rev(1), plan: plan())) == .accepted(commandSeq: 1))
check("B3 lower revision refused stale", b.send(.setLook(revision: rev(0), plan: plan())) == .refused(.staleRevision(current: rev(1))))
check("B4 same revision, different plan refused", b.send(.setLook(revision: rev(1), plan: plan("off", enabled: false, pack: 0))) == .refused(.revisionReused(current: rev(1))) && b.state.plan == plan())
check("B5 same revision, same plan is an idempotent accept", b.send(.setLook(revision: rev(1), plan: plan())) == .accepted(commandSeq: 2))
check("B6 next revision replaces the plan", b.send(.setLook(revision: rev(2), plan: plan("off", enabled: false, pack: 0))) == .accepted(commandSeq: 3) && b.state.look == rev(2) && b.state.plan?.enabled == false)
check("B7 orientation merges only the given fields", {
    _ = b.send(.setOrientation(ViewOrientation(yaw: 0.5, pitch: -0.1)))
    _ = b.send(.setOrientation(ViewOrientation(roll: 7.0)))   // beyond 2 pi: tilt is unwrapped by the renderer, never clamped here
    return b.state.orientation.yaw == 0.5 && b.state.orientation.pitch == -0.1 && b.state.orientation.roll == 7.0 && b.state.orientation.fov == nil
}())
check("B8 orientation NaN refused, state unchanged", b.send(.setOrientation(ViewOrientation(yaw: .nan))) == .refused(.nonFinite) && b.state.orientation.yaw == 0.5)
check("B9 tune stored by name, NaN refused", b.send(.setTune(name: tok("vr_gap_frac"), value: 0.02)) != .refused(.nonFinite) && b.state.tune[tok("vr_gap_frac")] == 0.02
      && b.send(.setTune(name: tok("vr_gap_frac"), value: .nan)) == .refused(.nonFinite) && b.state.tune[tok("vr_gap_frac")] == 0.02)
check("B10 effects merge, bad number refuses the whole call", {
    _ = b.send(.setEffects([tok("strength"): .number(1.2), tok("blink"): .bool(true)]))
    let r = b.send(.setEffects([tok("screenDepth"): .number(.infinity), tok("quality"): .text(tok("auto"))]))
    return r == .refused(.nonFinite) && b.state.effects[tok("strength")] == .number(1.2) && b.state.effects[tok("quality")] == nil
}())
let half = NormalizedRect(x: 0, y: 0, w: 0.5, h: 1)!
_ = b.send(.setCrop(half)); _ = b.send(.setFit(tok("fill")))
check("B11 crop and fit recorded as requested state", b.state.crop == half && b.state.fit == tok("fill"))
b.close()
check("B12 refuses after close", b.send(.setFit(tok("fit"))) == .refused(.notOpen))
check("B13 accepted is not applied: empty ledger says not applied", ReceiptLedger().isApplied(look: rev(2)) == false)

// Ledger (P25 consumer)
var l = ReceiptLedger()
check("L1 empty ledger has no film or revision", l.film == nil && l.appliedRevision == nil)
check("L2 first receipt accepted", l.consume(rcpt(1, seq: 1)) == .accepted)
check("L3 not applied until the revision is reached", l.isApplied(look: rev(1)) && !l.isApplied(look: rev(2)))
check("L4 receipt at revision 2 makes it applied", l.consume(rcpt(2, seq: 2)) == .accepted && l.isApplied(look: rev(2)))
check("L5 film geometry comes from the receipt", l.film?.width == 0.8 && l.film?.sequence == 2)
check("L6 revision regression counted, last kept", l.consume(rcpt(1, seq: 3)) == .regressedRevision(last: rev(2)) && l.regressions == 1 && l.appliedRevision == rev(2) && l.film?.sequence == 2)
check("L7 backwards film sequence refused (gor stale-sequence rule)", l.consume(rcpt(2, seq: 1)) == .staleSequence(floor: 2) && l.film?.sequence == 2)
check("L8 non-finite pts refused", l.consume(rcpt(3, seq: 4, pts: .infinity)) == .nonFinitePts && l.appliedRevision == rev(2))
check("L9 nil pts accepted, no fabricated zero", l.consume(rcpt(3, seq: 4, pts: nil)) == .accepted && l.last?.ptsSeconds == nil)
check("L10 receipt without film clears film but keeps revision", l.consume(rcpt(4, seq: 5, hasFilm: false)) == .accepted && l.film == nil && l.appliedRevision == rev(4))
l.beginGeneration(1)
check("L11 seek clears applied state", l.last == nil && !l.isApplied(look: rev(1)))
check("L12 stale-generation receipt dropped", l.consume(rcpt(9, g: 0, seq: 9)) == .staleGeneration(current: 1) && l.last == nil)
check("L13 new generation may carry a lower revision and sequence", l.consume(rcpt(1, g: 1, seq: 1)) == .accepted && l.film?.sequence == 1)
check("L14 a receipt from a newer generation starts it implicitly", l.consume(rcpt(1, g: 2, seq: 1)) == .accepted && l.currentGeneration == 2)
check("L15 frames counted only when recorded or counted as regression", l.framesSeen == 7)

print(failures == 0 ? "controlbus-tests: all pass" : "controlbus-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
