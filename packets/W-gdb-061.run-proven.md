# W-gdb-061 control bus witness (product suite, P24)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-061

```packet-json
{
  "packet_id": "W-gdb-061",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/controlbus-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "product test target controlbus-tests",
    "types": "see excerpt",
    "ownership_lifetime": "product sources at the pinned sha",
    "caller": "lab run-proof gate",
    "callee": "controlbus-tests (product target on main)"
  },
  "test": {
    "command": "swift run controlbus-tests",
    "expected": "exit 0; final line 'controlbus-tests: all pass'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/controlbus-tests/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/controlbus-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run controlbus-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:59:04.248153+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "controlbus-tests: all pass",
    "inline_files": [
      {
        "path": "Sources/controlbus-tests/main.swift",
        "block": "rf1",
        "sha256": "2f92e561c99bfeaf42c1bbd7c99d62213b965af19049212a74b0be3af65722d9"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "77337bc9e8d5ddec8a64983cee5301c3077391a84795958e829a34aef893d2b1",
    "last_5_lines": [
      "PASS L12 stale-generation receipt dropped",
      "PASS L13 new generation may carry a lower revision and sequence",
      "PASS L14 a receipt from a newer generation starts it implicitly",
      "PASS L15 frames counted only when recorded or counted as regression",
      "controlbus-tests: all pass"
    ],
    "receipt_sha256": "e7a679b910970bc3aea4b63ef2c5b0ea02b9edfbf9900cf9d7148e6d897baea8"
  }
}
```

## problem (what fails for the user)
the control bus is the only gor<->gorav channel (P24); a dropped or misrouted call desyncs look state for the owner

## reproducer
- repo: goreda/gorav @ 91a359f7b38cc0e6c4974661d85f389ef6041b1f (branch main).
- real source: Sources/controlbus-tests/main.swift (product target sources inlined below).
- real test command: swift run controlbus-tests (product's own target on main, Linux).

## expected behaviour
exit 0 with the product suite's summary line 'controlbus-tests: all pass'; any regression fails with its row id.

```text id=rf1
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

```

```text id=source1
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

```

```text id=fixtures1
fixtures are embedded in the product target sources (inlined above).
```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-6okk1yj_/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-6okk1yj_/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Compiling GorAVCore AdmissionTable.swift
[8/15] Compiling GorAVCore Boundary.swift
[9/15] Emitting module GorAVCore
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-6okk1yj_/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module controlbus_tests
[68/71] Compiling controlbus_tests main.swift
[69/72] Wrapping AST for controlbus-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking controlbus-tests
Build complete! (7.22s)
PASS V1 rect rejects NaN
PASS V2 rect rejects zero size
PASS V3 rect rejects outside unit square
PASS V4 token rejects empty, space, non-ascii, long
PASS V5 token accepts real gor names
PASS V6 plan rejects bad pack and aspect
PASS V7 film geometry rejects the cases gor rejects today
PASS B1 refuses when not open
PASS B2 first look accepted
PASS B3 lower revision refused stale
PASS B4 same revision, different plan refused
PASS B5 same revision, same plan is an idempotent accept
PASS B6 next revision replaces the plan
PASS B7 orientation merges only the given fields
PASS B8 orientation NaN refused, state unchanged
PASS B9 tune stored by name, NaN refused
PASS B10 effects merge, bad number refuses the whole call
PASS B11 crop and fit recorded as requested state
PASS B12 refuses after close
PASS B13 accepted is not applied: empty ledger says not applied
PASS L1 empty ledger has no film or revision
PASS L2 first receipt accepted
PASS L3 not applied until the revision is reached
PASS L4 receipt at revision 2 makes it applied
PASS L5 film geometry comes from the receipt
PASS L6 revision regression counted, last kept
PASS L7 backwards film sequence refused (gor stale-sequence rule)
PASS L8 non-finite pts refused
PASS L9 nil pts accepted, no fabricated zero
PASS L10 receipt without film clears film but keeps revision
PASS L11 seek clears applied state
PASS L12 stale-generation receipt dropped
PASS L13 new generation may carry a lower revision and sequence
PASS L14 a receipt from a newer generation starts it implicitly
PASS L15 frames counted only when recorded or counted as regression
controlbus-tests: all pass
```
