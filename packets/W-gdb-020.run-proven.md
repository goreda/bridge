# W-gdb-020 clock/scheduler scenario extension pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-020

```packet-json
{
  "packet_id": "W-gdb-020",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "decide(ptsSeconds: Double, nowSeconds: Double, frameDuration: Double) -> FrameDecision",
    "types": "FrameDecision { drop, wait(Double), show }; SyncMaster { clock, audioNotImplemented /* never selected */ }; maxWaitSeconds default 1.0; master fixed at init",
    "ownership_lifetime": "value type; virtual clock injected; master never switches mid-run",
    "caller": "FramePump pacing loop",
    "callee": "AVSyncDecider.decide(ptsSeconds:nowSeconds:frameDuration:) -> FrameDecision; SyncMaster fixed at init"
  },
  "test": {
    "command": "swift run timing-ledger-tests && swift run seek-pacing-tests",
    "expected": "exit 0 for both; existing checks stay green; new scenario rows replay green; a perturbed drift constant fails its scenario with the row printed",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/clock-scenarios/",
      "Sources/timing-ledger-tests/",
      "Sources/seek-pacing-tests/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/timing-ledger-tests/SPSCTests.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/timing-ledger-tests/TimingLedgerTests.swift",
        "block": "rf2"
      },
      {
        "path": "Sources/seek-pacing-tests/SeekPacingTests.swift",
        "block": "rf3"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run timing-ledger-tests && swift run seek-pacing-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:17:56.500604+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL_CHECKS_PASS",
    "inline_files": [
      {
        "path": "Sources/timing-ledger-tests/SPSCTests.swift",
        "block": "rf1",
        "sha256": "ae9ffc44d415ca87e1fc52d08bf182344e589fed8839b7ed303307ae10345035"
      },
      {
        "path": "Sources/timing-ledger-tests/TimingLedgerTests.swift",
        "block": "rf2",
        "sha256": "df7a440efc069f3ab3aebf01c0862bd80fe33fee2686cc22f96cfd4b068f514e"
      },
      {
        "path": "Sources/seek-pacing-tests/SeekPacingTests.swift",
        "block": "rf3",
        "sha256": "da6f453c40c4770d2130e036076ad22df7e32a901f63b8d9c8dd9514330b4f9c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "ccca1666fc0044bac942dd873c10244347aa894f223a50c3ebfb2987b47de1cb",
    "last_5_lines": [
      "ALL_CHECKS_PASS",
      "DIGEST anchor canonical=2.0 plus100ms=2.0999999999999996 keyframe03=2.3",
      "DIGEST forward shown=[0.0, 0.04, 0.08, 5.0, 5.04, 5.08] drops=0",
      "DIGEST backward shown=[0.0, 0.04, 0.02, 0.06, 0.1] drops=0",
      "DIGEST keyframeGap shown=[0.0, 5.3] stalePulls=1"
    ],
    "receipt_sha256": "b4b86fbfee5cf73de1921ff576c381d26df914f23a6c3f500c14914164d2b5d5"
  }
}
```

## problem (what fails for the user)
the pacing loop's clock handling is covered for the 600s/25fps and five-seek scenarios; sustained drift, jitter bursts, host-clock jumps and paused-span removal are uncovered, and the audio-master seam is unasserted (no mid-run master switch exists in the product), so a scheduler regression there ships as A/V desync.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, 75946B) - FramePump, AVSyncDecider, SyncMaster; Sources/timing-ledger-tests/TimingLedgerTests.swift (sha256 df7a440e) and Sources/seek-pacing-tests/SeekPacingTests.swift (sha256 da6f453c) - the existing deterministic-clock suites.
- real test command: swift run timing-ledger-tests + swift run seek-pacing-tests (Linux, Swift 6.1.2).

## expected behaviour
new deterministic JSON scenarios (virtual-clock ticks only, no sleeps) for the four uncovered classes plus one master-seam honesty scenario, with expected wait/present/drop tables per scenario and a runner that replays them against the production decision path.

## exact call site and interface
the AVSyncDecider/SyncMaster decision interface in the pinned PlaybackCore; fixtures + runner extend the existing ledger/pacing suites.

## pinned ABI decisions (integrator, 2026-11-15; master-switch contradiction resolved)
- SyncMaster (PlaybackCore.swift, same pin): public enum SyncMaster { case clock; case audioNotImplemented /* NOT_IMPLEMENTED: do not select */ }; AVSyncDecider carries `public let master: SyncMaster` FIXED at init (default .clock). there is no mid-run master switch in the product; the earlier "master switch mid-run" scenario class is REPLACED by a master-seam honesty scenario: decide() is wall/display-clock only and never reads master; the shell must never select .audioNotImplemented.
- the decide table the scenarios assert: delta = ptsSeconds - nowSeconds; delta < -frameDuration/2 -> .drop; delta > +frameDuration/2 -> .wait(min(delta, maxWaitSeconds)); otherwise .show; maxWaitSeconds default 1.0 (mpv-flavored, K6 review r2 item 2 clamp).
- the four real scenario classes (sustained drift, jitter bursts, host-clock jumps, paused-span removal) assert exactly this table under virtual-clock ticks.

## behaviour that must not change
the existing ledger/pacing checks stay green; scheduler evidence stays virtual-clock - never physical-device claims.

## acceptance test (from the product repo)
the new scenarios replay green; a perturbed drift constant fails the affected scenario (negative control shown); fixtures byte-deterministic.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 17-75 of 1382)
```swift id=source1
public enum FrameDecision: Equatable, Sendable { case show, drop, wait(Double) }

/// Shared post-seek media/wall anchor (M4): ONE authority maps media pts to
/// wall time for BOTH video frame scheduling and the audio resume, so a
/// legitimate media offset (e.g. +100ms edit-list audio start) is preserved
/// as an actual A/V offset, never collapsed by independent arrival anchoring.
public struct MediaWallAnchor: Sendable, Equatable {
    public let mediaSeconds: Double
    public let wallSeconds: Double
    public init(mediaSeconds: Double, wallSeconds: Double) {
        self.mediaSeconds = mediaSeconds; self.wallSeconds = wallSeconds
    }
    public func scheduledWall(forMediaSeconds pts: Double) -> Double {
        wallSeconds + (pts - mediaSeconds)
    }
}

/// Sync master visibility (K6 review r2 item 5): audio-master sync is
/// NOT_IMPLEMENTED. mpv masters sync to audio when an audio track is live;
/// gorav's core currently decides against the wall/display clock only. The
/// seam is explicit so the shell cannot silently assume audio-mastered pts.
public enum SyncMaster: Sendable, Equatable {
    case clock
    case audioNotImplemented // NOT_IMPLEMENTED: do not select
}

public struct AVSyncDecider: Sendable {
    public let maxWaitSeconds: Double
    public let master: SyncMaster
    public init(maxWaitSeconds: Double = 1.0, master: SyncMaster = .clock) {
        self.maxWaitSeconds = maxWaitSeconds
        self.master = master
    }
    // mpv-flavored thresholds: a frame more than half a frame-duration late
    // is dropped; more than half early waits (clamped, K6 review r2 item 2);
    // inside the window it shows.
    public func decide(ptsSeconds: Double, nowSeconds: Double, frameDuration: Double) -> FrameDecision {
        let delta = ptsSeconds - nowSeconds
        if delta < -frameDuration / 2 { return .drop }
        if delta > frameDuration / 2 { return .wait(Swift.min(delta, maxWaitSeconds)) }
        return .show
    }
}

/// Optional pixel payload for display sinks. Pure value type; Linux tests
/// leave it nil, the macOS shell's FrameSource wrapper attaches RGBA bytes.
public struct PixelPayload: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8] // RGBA, width*4 stride
    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }
}

public struct SourceFrame: Sendable {
    public let ptsSeconds: Double
    public let durationSeconds: Double
    public let digest: String
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"scenario":"sustained-drift","ticks":[{"pts":1.000,"now":0.990,"frameDuration":0.04,"expect":"show"},{"pts":1.000,"now":0.980,"frameDuration":0.04,"expect":"wait(0.020000000000000018)"},{"pts":1.040,"now":1.071,"frameDuration":0.04,"expect":"drop"},{"pts":1.125,"now":1.000,"frameDuration":0.04,"expect":"wait(0.125)"}],"masterSeam":"clock-only; audioNotImplemented never selected","boundaryNote":"1.0-0.98 is 0.020000000000000018 in Double, strictly greater than frameDuration/2, so the pinned decide table waits; the exact half-frame tick is kept as a documented boundary row"}
```

```text id=rf1
// L1 rework SPSC tests (architect PART1 findings 1/2/4): frame alignment,
// event-time stamps, overflow latch, direct-buffer render, and a real
// two-thread conservation smoke (producer/consumer concurrently).
import Foundation
import GorAVPlaybackCore

enum SPSC {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String, _ detail: String = "") {
        if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
    }
    /// Unwrap for failable v4 ring construction: a nil (typed init refusal)
    /// is a test failure, never a crash.
    static func unwrap<T>(_ v: T?, _ name: String) -> T? {
        if v == nil { check(false, name, "typed init refusal") }
        return v
    }

    static func run() {
        // S1: frame quantization - a partial trailing frame is refused, never
        // admitted out of alignment (finding 2).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 8), "init S1") else { return }
            var bytes = [UInt8](repeating: 0xAB, count: 10) // 2 frames + 2-byte tail
            let r = bytes.withUnsafeBufferPointer { ring.push($0) }
            check(r.admittedFrames == 2 && r.droppedFrames == 0 && r.droppedTailBytes == 2, "S1 partial tail refused BYTE-exact, not as a frame", "\(r)")
            check(ring.availableFrames == 2, "S1 available is whole frames")
            check(ring.partialTailDrops.load() == 1 && ring.droppedBytes.load() == 2, "S1 tail counted as 2 BYTES not 4")
            check(ring.requestedBytes.load() == ring.admittedBytes.load() + ring.droppedBytes.load(), "S1 byte conservation requested==admitted+dropped")
        }
        // S2: full-ring drop-newest is frame-granular; retained content keeps
        // ordered identity (finding 2 + ordered-content mutant).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 4), "init S2") else { return }
            func frame(_ v: UInt8) -> [UInt8] { [v, v, v, v] }
            var pushed: [UInt8] = []
            for i: UInt8 in 0..<4 { pushed.append(contentsOf: frame(i &+ 1)) }
            let r1 = pushed.withUnsafeBufferPointer { ring.push($0) }
            check(r1.admittedFrames == 4 && r1.droppedFrames == 0, "S2 fill")
            var extra = frame(99) + frame(98)
            let r2 = extra.withUnsafeBufferPointer { ring.push($0) }
            check(r2.admittedFrames == 0 && r2.droppedFrames == 2, "S2 overflow drop frame-quantized")
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 16); defer { dst.deallocate() }
            let under = ring.render(into: dst, frames: 4)
            check(under == 0, "S2 no underrun on full ring")
            var out: [UInt8] = []; for i in 0..<16 { out.append(dst[i]) }
            check(out == pushed, "S2 retained identity oldest ordered frames")
        }
        // S3: underrun zero-fill is not consumption (finding 2).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 8), "init S4") else { return }
            var two = [UInt8](repeating: 7, count: 8)
            _ = two.withUnsafeBufferPointer { ring.push($0) }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 16); defer { dst.deallocate() }
            let under = ring.render(into: dst, frames: 4)
            check(under == 2 && ring.consumedFrames.load() == 2 && ring.underrunFrames.load() == 2, "S3 underrun frames counted")
            var tail: [UInt8] = []; for i in 8..<16 { tail.append(dst[i]) }
            check(tail == [0, 0, 0, 0, 0, 0, 0, 0], "S3 shortfall is silence")
        }
        // S4: event ring - post-time stamps + generation preserved, drain
        // order, sticky overflow latch (findings 1/4).
        do {
            final class TBox: @unchecked Sendable { var v = 100.0 }
            let tb = TBox()
            guard let ring = unwrap(SPSCEventRing(capacity: 2, clock: { tb.v }), "init S3") else { return }
            ring.post(.underrunStart, generation: 3, payload: .frames(512))
            tb.v = 101.5
            ring.post(.underrunEnd, generation: 3, payload: .frames(0))
            tb.v = 102.0
            ring.post(.staleFenced, generation: 3, payload: .bytes(4)) // overflows (cap 2)
            let evs = ring.drain()
            check(evs.count == 2 && evs[0].kind == .underrunStart && evs[1].kind == .underrunEnd, "S4 drain order")
            check(evs[0].tEvent == 100.0 && evs[1].tEvent == 101.5, "S4 post-time stamps preserved", "\(evs.map { $0.tEvent })")
            check(evs[0].generation == 3, "S4 generation at post time")
            check(ring.overflowed.load() == 1, "S4 overflow latch set")
            _ = ring.drain()
            check(ring.overflowed.load() == 1, "S4 latch sticky after drain")
        }
        // S5a: deterministic overflow witness, no scheduler assumption.
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 4), "init S5a") else { return }
            let fill = [UInt8](repeating: 7, count: 16)
            let extra = [UInt8](repeating: 9, count: 4)
            _ = fill.withUnsafeBufferPointer { ring.push($0) }
            let receipt = extra.withUnsafeBufferPointer { ring.push($0) }
            check(receipt.droppedFrames == 1 && ring.droppedFrames.load() == 1,
                  "S5a serial prefill overflow exercised exactly one dropped frame")
        }
        // S5: real two-thread conservation smoke. Producer pushes
        // seq-patterned frames; consumer renders; no torn frames, conservation
        // pushed == consumed + dropped + remaining (finding 1 adversarial).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 1024), "init S5") else { return }
            let totalFrames = 200_000
            let group = DispatchGroup()
            var maxSeqSeen = -1
            var monotonic = true
            let lock = NSLock()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                var chunk = [UInt8](repeating: 0, count: 64 * 4)
                var seq: UInt32 = 0
                var pushed = 0
                while pushed < totalFrames {
                    for f in 0..<64 {
                        chunk[f * 4 + 0] = UInt8(seq & 0xFF)
                        chunk[f * 4 + 1] = UInt8((seq >> 8) & 0xFF)
                        chunk[f * 4 + 2] = UInt8((seq >> 16) & 0xFF)
                        chunk[f * 4 + 3] = UInt8((seq >> 24) & 0xFF)
                        seq &+= 1
                    }
                    let r = chunk.withUnsafeBufferPointer { ring.push($0) }
                    pushed += Int(r.admittedFrames)
                    if r.admittedFrames == 0 { Thread.sleep(forTimeInterval: 0.0001) }
                }
            }
            // Consume until the producer's frames are ALL really consumed:
            // underrun zero-fill never increments consumedFrames, so this
            // cannot exit early on silence. (Fixes consumer-exits-first
            // deadlock of the naive slot-count loop.)
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 4)
            while ring.consumedFrames.load() < totalFrames {
                let before = ring.consumedFrames.load()
                _ = ring.render(into: dst, frames: 64)
                let got = Int(ring.consumedFrames.load() - before)
                for f in 0..<got {
                    let v = UInt32(dst[f * 4]) | UInt32(dst[f * 4 + 1]) << 8 | UInt32(dst[f * 4 + 2]) << 16 | UInt32(dst[f * 4 + 3]) << 24
                    lock.lock()
                    if Int(v) <= maxSeqSeen { monotonic = false }
                    maxSeqSeen = Int(v)
                    lock.unlock()
                }
                if got == 0 { Thread.sleep(forTimeInterval: 0.00005) }
            }
            group.wait()
            dst.deallocate()
            // Conservation: every ADMITTED frame is either consumed or still
            // in the ring. Dropped frames are refused-at-tail and were never
            // admitted, so they are not part of the ring's frame balance.
            let conservation = ring.consumedFrames.load() + ring.availableFrames == ring.pushedFrames.load()
            check(conservation, "S5 conservation admitted==consumed+remaining",
                  "p=\(ring.pushedFrames.load()) c=\(ring.consumedFrames.load()) d=\(ring.droppedFrames.load()) a=\(ring.availableFrames)")
            // Concurrent conservation/order permits zero drops. S5a proves overflow separately.
            check(ring.requestedBytes.load() == ring.admittedBytes.load() + ring.droppedBytes.load(), "S5 BYTE conservation requested==admitted+dropped",
                  "req=\(ring.requestedBytes.load()) adm=\(ring.admittedBytes.load()) drop=\(ring.droppedBytes.load())")
            // S6: receipt-before-reset regression (architect early blocker
            // #1): a post-stop summary built from the RECEIPT keeps the
            // retired session's evidence after the ring is reset.
            do {
                guard let ring2 = unwrap(SPSCPCMRing(capacityFrames: 64), "init S5b") else { return }
                var pcm = [UInt8](repeating: 5, count: 4 * 16)
                _ = pcm.withUnsafeBufferPointer { ring2.push($0) }
                let dst2 = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 4); defer { dst2.deallocate() }
                _ = ring2.render(into: dst2, frames: 8)
                let receipt = ring2.snapshotReceipt(generation: 1)
                ring2.resetForNewGeneration()
                check(ring2.pushedFrames.load() == 0 && ring2.maxAvailAfterPushFrames.load() == 0, "S6 live ring zeroed after reset")
                check(receipt.pushedFrames == 16 && receipt.consumedFrames == 8 && receipt.pushCount == 1 && receipt.maxPushFrames == 16,
                      "S6 retired receipt survives reset", "\(receipt)")
                let ev = QueueBoundEvidence(capacity: 64 * 4, watermark: 32,
                                            maxChunkBytes: Int(receipt.maxPushFrames) * 4,
                                            maxAvailAfterPush: Int(receipt.maxAvailAfterPushFrames) * 4,
                                            overrunDrops: Int(receipt.droppedFrames) * 4,
                                            pushCount: Int(receipt.pushCount))
                check(ev.admissionBoundHolds, "S6 post-stop evidence still proves the bound")
                // S7: invalid evidence inputs never trap and never claim (v3-4)
                let bad = QueueBoundEvidence(capacity: 64, watermark: -1, maxChunkBytes: 4, maxAvailAfterPush: 4, overrunDrops: 0, pushCount: 1)
                check(!bad.admissionBoundHolds, "S7 negative watermark refused")
                let over = QueueBoundEvidence(capacity: 64, watermark: 60, maxChunkBytes: 60, maxAvailAfterPush: 4, overrunDrops: 0, pushCount: 1)
                check(!over.admissionBoundHolds, "S7 watermark+chunk>capacity refused")
            }
            check(monotonic, "S5 no torn/reordered frames under concurrency")
        }
        print(failures == 0 ? "ALL SPSC TESTS PASS" : "SPSC FAILURES: \(failures)")
        // S8: v4 sticky PCM latch - tail refusal AND frame drop both latch;
        // reset clears.
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 4), "init S8") else { return }
            check(ring.droppedAnything.load() == 0, "S8 latch starts clear")
            var b3: [UInt8] = [1, 2, 3]
            _ = b3.withUnsafeBufferPointer { ring.push($0) } // tail refusal
            check(ring.droppedAnything.load() == 1, "S8 tail refusal latches sticky")
            ring.resetForNewGeneration()
            check(ring.droppedAnything.load() == 0, "S8 reset clears latch")
            var full: [UInt8] = [UInt8](repeating: 9, count: 20) // 5 frames > cap 4
            _ = full.withUnsafeBufferPointer { ring.push($0) }
            check(ring.droppedAnything.load() == 1 && ring.droppedFrames.load() == 1, "S8 frame drop latches sticky")
            let r = ring.snapshotReceipt(generation: 9)
            check(r.droppedAnything && r.generation == 9, "S8 receipt carries the latch + generation")
        }

        // T23 (lane-0 / architect 80b constraint A): admission-cell semantics.
        // A reader admitted BEFORE retire must drain; an enter AFTER retire fails;
        // retire is idempotent; readers drain to zero deterministically.
        do {
            print("T23 admission cell (architect 80b constraint A)")
            guard let a = AdmissionCell() else { print("FAIL T23 alloc"); exit(1) }
            check(a.enter(), "T23 first enter admitted")
            check(!a.enter(), "T23 ONE-CONSUMER: second enter while busy REFUSED (busy => silence, architect full verdict S2)")
            check(a.readers == 1, "T23 reader count stays 1 under contention")
            a.exit()
            check(a.readers == 0, "T23 reader drained")
            check(a.enter(), "T23 enter re-admitted after drain (not yet retired)")
            a.exit()
            let inFlightAtRetire = a.retire()
            check(inFlightAtRetire == 0, "T23 retire reports zero in-flight readers at retire")
            check(a.isRetired, "T23 retired flag set")
            check(!a.enter(), "T23 MUTANT-NEGATIVE: enter after retire REFUSED")
            check(a.retire() == 0, "T23 retire idempotent")
            check(!a.enter(), "T23 still refused after retire (retire is terminal)")
        }
    }
}


```

```text id=rf2
// L1 timing/lifecycle deterministic model tests (architect delta 2026-10-25
// conditions 1,2,4,5,6 + negative mutants). Pure Swift over GorAVPlaybackCore
// with injected deterministic clocks: runs off-Mac (Linux swift 6.1.2) and on
// any Mac/CI runner. Every scenario asserts; any failure prints FAIL and the
// process exits non-zero. No wall-clock, no randomness, no I/O.
import Foundation
import GorAVPlaybackCore

final class FakeClock: PlaybackClock, @unchecked Sendable {
    var t = 0.0
    func nowSeconds() -> Double { t }
}
final class FakeSource: FrameSource, @unchecked Sendable {
    var frames: [SourceFrame]
    var i = 0
    init(_ frames: [SourceFrame]) { self.frames = frames }
    func nextEvent() async -> SourceEvent {
        guard i < frames.count else { return .ended(.sourceEnded) }
        defer { i += 1 }
        return .frame(frames[i])
    }
}
final class FakeSink: FrameSink, @unchecked Sendable {
    var shown: [String] = []
    var acceptShows = true
    func show(_ frame: SourceFrame) async -> Bool {
        if acceptShows { shown.append(frame.digest) }
        return acceptShows
    }
    // Explicit TEST-FAKE ticketed conformance (no protocol bypass
    // default - verdict S5 rev3).
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await show(frame)
    }
}

var failures = 0
func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
}

@main
struct TimingLedgerTests {
    static func main() async {
        // T1: full lifecycle ordering on one origin (cond. 2).
        do {
            let fc = FakeClock()
            let ledger = TimingLedger(capacity: 64, clock: { fc.t })
            ledger.append(session: 1, generation: 1, segment: .open, subsystem: .core, kind: .ledgerOrigin)
            fc.t += 0.1; ledger.append(session: 2, generation: 1, segment: .open, subsystem: .audio, kind: .audioStartAccepted)
            fc.t += 0.1; ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            fc.t += 1.0; ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .frameShown, pts: 0.0)
            fc.t += 9.0; ledger.append(session: 2, generation: 1, segment: .pump, subsystem: .audio, kind: .terminal, note: "endOfStream")
            fc.t += 0.5; ledger.append(session: 2, generation: 1, segment: .drain, subsystem: .audio, kind: .drainEnd, bytes: 0)
            fc.t += 0.1; ledger.append(session: 2, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownComplete)
            let evs = ledger.snapshot()
            check(evs.map { $0.kind } == [.ledgerOrigin, .audioStartAccepted, .videoPumpStart, .frameShown, .terminal, .drainEnd, .teardownComplete], "T1 lifecycle order")
            check(evs.map { $0.seq } == Array(1...7), "T1 seq monotonic")
            var mono = true; for i in 1..<evs.count { if evs[i].tRel < evs[i-1].tRel { mono = false } }
            check(mono, "T1 tRel non-decreasing")
            check(ledger.allowsSuccess, "T1 allowsSuccess")
        }
        // T2: start-starve - silence is never consumed content (cond. 6 start-starve).
        do {
            let ring = PCMRingBuffer(capacity: 16)
            let r1 = ring.renderCounted(8)
            check(r1.underrun == 8 && ring.kitConsumedBytes == 0, "T2 start-starve silence not consumed")
            ring.push([1, 2, 3, 4])
            let r2 = ring.renderCounted(8)
            check(r2.underrun == 4 && ring.kitConsumedBytes == 4 && Array(r2.out[0..<4]) == [1, 2, 3, 4] && Array(r2.out[4..<8]) == [0, 0, 0, 0], "T2 real bytes before silence")
        }
        // T3: mid-starve counters.
        do {
            let ring = PCMRingBuffer(capacity: 16)
            ring.push([9, 9, 9, 9, 9, 9, 9, 9])
            let a = ring.renderCounted(8)
            let b = ring.renderCounted(4)
            check(a.underrun == 0 && b.underrun == 4 && ring.kitConsumedBytes == 8 && ring.underrunBytes == 4, "T3 mid-starve counters")
        }
        // T4: overrun drop-newest keeps ORDERED CONTENT IDENTITY, not just
        // byte balance (architect cond: byte-conserving mutant must fail).
        do {
            let ring = PCMRingBuffer(capacity: 16)
            let o1 = ring.pushCounted(Array(0..<16))
            check(o1.admitted == 16 && o1.dropped == 0, "T4 fill admitted")
            let o2 = ring.pushCounted([100, 101, 102, 103])
            check(o2.admitted == 0 && o2.dropped == 4 && ring.overrunDrops == 4, "T4 overflow dropped")
            let out = ring.renderCounted(16)
            check(Array(out.out) == Array(0..<16), "T4 retained content identity is the oldest ordered bytes")
        }
        // T5: watermark bound is derived from RECORDED maxima (cond. 1).
        do {
            let ring = PCMRingBuffer(capacity: 1024)
            let watermark = 256, chunk = 100
            for _ in 0..<30 {
                if ring.available <= watermark { _ = ring.pushCounted([UInt8](repeating: 7, count: chunk)) }
                else { _ = ring.renderCounted(88) }
            }
            let ev = QueueBoundEvidence(capacity: 1024, watermark: watermark,
                                        maxChunkBytes: ring.maxPushBytes,
                                        maxAvailAfterPush: ring.maxAvailAfterPush,
                                        overrunDrops: ring.overrunDrops,
                                        pushCount: ring.pushCount)
            check(ring.maxAvailAfterPush <= watermark + chunk, "T5 recorded maxAvail within watermark+chunk", "got \(ring.maxAvailAfterPush)")
            check(ev.admissionBoundHolds && ring.overrunDrops == 0, "T5 admission bound verified from records")
            let unrecorded = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 0, maxAvailAfterPush: 0, overrunDrops: 0, pushCount: 0)
            check(!unrecorded.admissionBoundHolds, "T5 no bound claim without recorded maxima")
            // finding 5 mutants: overrun>0 or maxAvail beyond watermark+chunk
            // must REFUSE the bound even when records exist.
            let overran = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 100, maxAvailAfterPush: 300, overrunDrops: 4, pushCount: 10)
            check(!overran.admissionBoundHolds, "T5 MUTANT overrun refuses bound")
            let overshot = QueueBoundEvidence(capacity: 1024, watermark: 256, maxChunkBytes: 100, maxAvailAfterPush: 400, overrunDrops: 0, pushCount: 10)
            check(!overshot.admissionBoundHolds, "T5 MUTANT maxAvail>watermark+chunk refuses bound")
        }
        // T6: same-actor upload fence decision + close-intent ordering (cond. 3).
        do {
            check(UploadFence.mayUpload(closeIntent: false) && !UploadFence.mayUpload(closeIntent: true), "T6 fence decision")
            let ledger = TimingLedger(capacity: 8, clock: { 0.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .closeIntent)
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .closeFenceSkip, pts: 5.0)
            let kinds = ledger.snapshot().map { $0.kind }
            check(kinds == [.closeIntent, .closeFenceSkip], "T6 close intent precedes fence skip")
        }
        // T7: cancel / decode error / EOS are DISTINCT end reasons (cond. 6).
        do {
            check(EndReason.from(audioTerminal: .endOfStream, closeIntent: false) == .endOfStream, "T7 eos")
            check(EndReason.from(audioTerminal: .failed, closeIntent: false) == .decodeFailed, "T7 decodeFailed")
            check(EndReason.from(audioTerminal: .sourceEnded, closeIntent: false) == .sourceEnded, "T7 sourceEnded")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeIntent: true) == .userClose, "T7 userClose distinct")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeIntent: false) == .stoppedEarly, "T7 bare stoppedEarly")
            let all: Set<EndReason> = [.endOfStream, .decodeFailed, .sourceEnded, .userClose, .stoppedEarly, .cancelled]
            check(all.count == 6, "T7 six distinct end reasons")
        }
        // T8: per-generation lifecycle v3 - DOUBLE_DISPOSE,
        // STOP_BEFORE_START, START_STOP_START, TEARDOWN_BLOCKS_START and
        // FAILED_SESSION_TERMINAL mutants (v2-review finding 2).
        do {
            let lc = SessionLifecycle()
            check(lc.beginStop() == .none && lc.noOpStopCount == 1, "T8 MUTANT stop-before-start is a no-op (guard not consumed)")
            let g1 = lc.beginStart()
            check(g1 == 1, "T8 first start reserves generation 1")
            check(lc.beginStart() == nil && lc.refusedStartCount == 1, "T8 MUTANT double start refused")
            check(lc.commitStart(1), "T8 commit")
            check(lc.beginStop() == .teardownOwned(1), "T8 stop owns teardown")
            // v3: the generation stays OCCUPIED while teardown runs - a new
            // start during teardown is refused (v2 admitted it).
            check(lc.beginStart() == nil && lc.refusedStartCount == 2, "T8 MUTANT start-during-teardown refused")
            check(lc.beginStop() == .none, "T8 MUTANT double dispose refused")
            lc.finishStop(1)
            check(lc.stopCount == 1, "T8 stop counted at quiescence, not at begin")
            let g2 = lc.beginStart()
            check(g2 == 2, "T8 start-stop-start RE-ARMS with generation 2")
            lc.abortStart(2)
            check(lc.abortedStartCount == 1 && lc.beginStart() == 3, "T8 aborted start rolls back and re-arms")
            // stop racing a start: startWillTearDown, commitStart false,
            // abortStart completes the raced stop.
            check(lc.beginStop() == .startWillTearDown(3), "T8 stop-races-start is typed, touches nothing")
            check(!lc.commitStart(3), "T8 raced start commit fails")
            lc.abortStart(3)
            check(lc.stopCount == 2 && lc.current == .idle, "T8 raced stop completed by start side")
            // FAILED session is TERMINAL: never overwritten.
            _ = lc.beginStart(); _ = lc.commitStart(4)
            _ = lc.beginStop()
            lc.failStop(4)
            check(lc.beginStart() == nil && lc.refusedStartFailedCount == 1, "T8 MUTANT start on FAILED session refused")
            check(lc.beginStop() == .none, "T8 stop on FAILED is a no-op")
        }
        // T9: stale-generation fence - EARLY_FREE_CALLBACK mutant must not
        // touch session resources (cond. 4/6).
        do {
            let fence = GenerationFence()
            check(fence.checkRT(1), "T9 current generation admitted")
            fence.advance() // stop() boundary
            check(!fence.checkRT(1), "T9 MUTANT stale-generation callback fenced")
            check(fence.fencedCount == 1, "T9 stale attempt recorded")
            check(fence.checkRT(2), "T9 new generation admitted")
        }
        // T10: bounded ledger overflow refuses success (cond. 5).
        do {
            let ledger = TimingLedger(capacity: 4, clock: { 0.0 })
            for _ in 0..<10 { ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush) }
            check(ledger.count == 4 && ledger.overflowed && ledger.droppedEventCount == 6 && !ledger.allowsSuccess, "T10 overflow refuses success")
        }
        // T11: SPSC event ring fold keeps EVENT-TIME stamps (finding 4) and
        // the overflow latch refuses success (cond. 5).
        do {
            let ledger = TimingLedger(capacity: 16, clock: { 0.0 })
            var t = 50.0
            final class TB: @unchecked Sendable { var v = 50.0 }
            let tb = TB(); tb.v = t
            guard let rt = SPSCEventRing(capacity: 2, clock: { tb.v }) else { check(false, "T11 init"); return }
            rt.post(.underrunStart, generation: 7, payload: .frames(512))
            tb.v = 55.0
            rt.post(.underrunEnd, generation: 7, payload: .frames(0))
            let drained = rt.drain()
            ledger.fold(rt: drained, session: 2, segment: .pump)
            let evs = ledger.snapshot()
            check(evs.map { $0.kind } == [.underrunStart, .underrunEnd], "T11 transitions folded")
            check(evs[0].tAbs == 50.0 && evs[1].tAbs == 55.0, "T11 EVENT-TIME stamps preserved, not drain time", "\(evs.map { $0.tAbs })")
            check(evs[0].generation == 7, "T11 post-time generation preserved")
            check(ledger.allowsSuccess, "T11 clean fold keeps success")
            guard let rt2 = SPSCEventRing(capacity: 1, clock: { 0.0 }) else { check(false, "T11 init2"); return }
            rt2.post(.staleFenced, generation: 1, payload: .bytes(0))
            rt2.post(.staleFenced, generation: 1, payload: .bytes(0)) // overflow latch
            check(rt2.overflowed.load() == 1, "T11 overflow latch set")
            ledger.fold(rt: rt2.drain(), session: 2, segment: .pump)
            if rt2.overflowed.load() == 1 { ledger.foldRTOverflow() }
            check(!ledger.allowsSuccess, "T11 RT overflow folds into ledger and refuses success")
            _ = t
        }
        // T12: pump PTS classification - forward gap recorded as observation,
        // backward and non-finite as typed drops; order of shown digests
        // preserved (cond. 2 + ordered content identity).
        do {
            let ledger = TimingLedger(capacity: 256, clock: { 0.0 })
            let clock = FakeClock()
            func fr(_ pts: Double, _ d: String) -> SourceFrame { SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: d) }
            let source = FakeSource([fr(0.00, "a"), fr(0.04, "b"), fr(0.20, "c"), fr(0.05, "X"), fr(0.24, "d")])
            let sink = FakeSink()
            let pump = FramePump(source: source, sink: sink, clock: clock,
                                 ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                                 onWait: { d in clock.t += d; return true })
            let stats = await pump.run()
            check(stats.shown == 4 && stats.dropped == 0, "T12 shown count", "\(stats.shown)/\(stats.dropped)")
            check(sink.shown == ["a", "b", "c", "d"], "T12 shown order identity", "\(sink.shown)")
            // backward: feed one out-of-order frame in a second run segment
            let ledger2 = TimingLedger(capacity: 64, clock: { 0.0 })
            let clock2 = FakeClock()
            let source2 = FakeSource([fr(0.00, "a"), fr(0.04, "b"), fr(0.02, "BACK"), fr(0.08, "c")])
            let sink2 = FakeSink()
            let pump2 = FramePump(source: source2, sink: sink2, clock: clock2,
                                  ledger: ledger2, ledgerSession: 1, ledgerGeneration: 1,
                                  onWait: { d in clock2.t += d; return true })
            let stats2 = await pump2.run()
            check(stats2.outOfOrderDrops == 1 && sink2.shown == ["a", "b", "c"], "T12 backward typed drop", "\(stats2.outOfOrderDrops)")
            let kinds = ledger.snapshot().map { $0.kind }
            check(kinds.filter { $0 == .ptsGapForward }.count == 1, "T12 forward gap classified once", "\(kinds)")
            check(kinds.filter { $0 == .frameShown }.count == 4, "T12 frameShown events")
            let kinds2 = ledger2.snapshot().map { $0.kind }
            check(kinds2.contains(.ptsBackwardDrop), "T12 backward event recorded")
            // non-finite
            let ledger3 = TimingLedger(capacity: 64, clock: { 0.0 })
            let clock3 = FakeClock()
            let source3 = FakeSource([fr(Double.nan, "NAN"), fr(0.0, "ok")])
            let sink3 = FakeSink()
            let pump3 = FramePump(source: source3, sink: sink3, clock: clock3,
                                  ledger: ledger3, ledgerSession: 1, ledgerGeneration: 1,
                                  onWait: { d in clock3.t += d; return true })
            let stats3 = await pump3.run()
            check(stats3.nonFiniteDrops == 1 && sink3.shown == ["ok"], "T12 non-finite typed drop")
            check(ledger3.snapshot().map { $0.kind }.contains(.ptsNonFiniteDrop), "T12 non-finite event")
        }
        // T20: v4 missingSequence - ORDERED, PER-SESSION/GENERATION
        // completeness: foreign sessions and out-of-order kinds never count.
        do {
            let ledger = TimingLedger(capacity: 64, clock: { 0.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpEnd) // WRONG order (end before start), s1
            ledger.append(session: 2, generation: 9, segment: .open, subsystem: .audio, kind: .audioStartAccepted) // foreign session
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            check(ledger.missingSequence(session: 1, generation: 1, required: [.videoPumpStart, .videoPumpEnd]).isEmpty == false,
                  "T20 out-of-order sequence is INCOMPLETE")
            check(ledger.missingSequence(session: 2, generation: 9, required: [.audioStartAccepted]).isEmpty,
                  "T20 own session ordered single kind complete")
            check(!ledger.missingSequence(session: 1, generation: 1, required: [.audioStartAccepted]).isEmpty,
                  "T20 foreign-session kind never counts")
        }
        // T21: v4 export order - PUBLICATION (seq), late RT fold with an
        // OLDER event-time stamp does NOT regress the emission order.
        do {
            let ledger = TimingLedger(capacity: 64, clock: { 100.0 })
            ledger.append(session: 1, generation: 1, segment: .pump, subsystem: .video, kind: .videoPumpStart)
            let ev = RTEvent(kind: .underrunStart, generation: 3, tEvent: 1.0, payload: .frames(7)) // older stamp
            ledger.fold(rt: [ev], session: 2, segment: .pump)
            let lines = ledger.jsonLines().split(separator: "\n").map(String.init)
            let k1 = ((try? JSONSerialization.jsonObject(with: Data(lines[1].utf8))) as? [String: Any])?["kind"] as? String
            let k2 = ((try? JSONSerialization.jsonObject(with: Data(lines[2].utf8))) as? [String: Any])?["kind"] as? String
            check(k1 == "videoPumpStart" && k2 == "underrunStart",
                  "T21 publication order kept despite older folded stamp", "\(k1 ?? "?")/\(k2 ?? "?")")
            let e2 = (try? JSONSerialization.jsonObject(with: Data(lines[2].utf8))) as? [String: Any]
            check((e2?["tAbs"] as? Double) == 1.0 && (e2?["bytes"] as? Int) == 28 && (e2?["note"] as? String) == "rtPost unit=frames4",
                  "T21 folded event keeps event-time + EXACT frame->byte conversion", "\(String(describing: e2))")
        }
        // T22: v4 sticky latch - drops at count 1 AND >=2 both latched;
        // reset clears it.
        do {
            let ledger2 = TimingLedger(capacity: 64, clock: { 0.0 })
            guard let rt3 = SPSCEventRing(capacity: 1, clock: { 0.0 }) else { check(false, "T22 init"); return }
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1))
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1))
            rt3.post(.staleFenced, generation: 1, payload: .bytes(1)) // TWO overflows
            check(rt3.droppedAnything.load() == 1 && rt3.overflowed.load() == 2, "T22 sticky latch set with counter 2")
            rt3.resetForNewGeneration()
            check(rt3.droppedAnything.load() == 0 && rt3.overflowed.load() == 0, "T22 reset clears latch+counter")
            _ = ledger2
        }
        // T13: JSONL export v2 (finding 8) - versioned header, REAL JSON
        // parse of every line (no manual interpolation), byte bound with a
        // truncation marker, bounded notes, non-finite stamp refusal.
        do {
            let ledger = TimingLedger(capacity: 8, clock: { 1.5 }, runID: "t13", cwd: "/x")
            ledger.append(session: 1, generation: 2, segment: .pump, subsystem: .video, kind: .frameShown, pts: 0.04, bytes: 3, note: "quote\"and\\backslash")
            let lines = ledger.jsonLines().split(separator: "\n").map(String.init)
            check(lines.count == 2, "T13 header + one event")
            let h = (try? JSONSerialization.jsonObject(with: Data(lines[0].utf8))) as? [String: Any]
            check(h?["schema"] as? String == "gorav.timing-ledger/4" && h?["order"] as? String == "publication" && h?["runID"] as? String == "t13" && h?["cwd"] as? String == "/x", "T13 header", lines[0])
            let e = (try? JSONSerialization.jsonObject(with: Data(lines[1].utf8))) as? [String: Any]
            check(e?["kind"] as? String == "frameShown" && (e?["pts"] as? Double) == 0.04 && (e?["tAbs"] as? Double) == 1.5, "T13 event parses as real JSON", lines[1])
            check(e?["note"] as? String == "quote\"and\\backslash", "T13 escaping round-trips through JSONEncoder")
            // byte bound: tiny budget truncates with a marker last line.
            let l2 = TimingLedger(capacity: 64, clock: { 0.0 })
            for i in 0..<30 { l2.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush, bytes: i) }
            let out = l2.jsonLines(maxBytes: 400)
            let ls = out.split(separator: "\n").map(String.init)
            let last = (try? JSONSerialization.jsonObject(with: Data(ls.last!.utf8))) as? [String: Any]
            check(last?["type"] as? String == "truncated" && (last?["omittedEvents"] as? Int) ?? 0 > 0 && (last?["writtenEvents"] as? Int) != nil, "T13 truncation marker receipt is last line", ls.last ?? "")
            // L9 W2 (architect-reviewed): an export-formatting budget
            // truncates PRESENTATION only - it marks lastExportTruncated
            // but NEVER poisons the ingestion verdict.
            check(l2.lastExportTruncated && l2.allowsSuccess, "T13 truncated export marks truncation, verdict unpoisoned")
            // Ingestion-side capacity loss still refuses success (distinct path).
            let l2b = TimingLedger(capacity: 3, clock: { 0.0 })
            for i in 0..<6 { l2b.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush, bytes: i) }
            check(!l2b.allowsSuccess && l2b.overflowed, "T13 ingestion capacity overflow still refuses success")
            // note bound
            let l3 = TimingLedger(capacity: 4, clock: { 0.0 })
            l3.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .terminal, note: String(repeating: "z", count: 1000))
            check(l3.snapshot()[0].note.utf8.count == TimingLedger.maxNoteUTF8 + 1 && l3.truncatedNoteCount == 1, "T13 note byte-bound")
            // non-finite stamp refuses success
            let l4 = TimingLedger(capacity: 4, clock: { Double.nan })
            l4.append(session: 1, generation: 1, segment: .pump, subsystem: .core, kind: .audioPush)
            check(!l4.allowsSuccess && l4.invalidStampCount == 1, "T13 non-finite stamp refuses success")
        }
        // T14: a fenced (refused) show is NOT logged frameShown and NOT
        // counted as shown (finding 4: "frameShown even when closed" mutant).
        do {
            let ledger = TimingLedger(capacity: 32, clock: { 0.0 })
            let src = FakeSource([SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "x")])
            let sink = FakeSink(); sink.acceptShows = false // window closed / fenced
            let pump = FramePump(source: src, sink: sink, clock: FakeClock(),
                                 ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                                 onWait: { _ in true })
            let stats = await pump.run()
            check(stats.shown == 0 && stats.fencedShows == 1, "T14 refused show not counted shown")
            check(!ledger.snapshot().map { $0.kind }.contains(.frameShown), "T14 MUTANT frameShown on refused show absent")
        }
        // T24: timed-close ACTOR attribution (r9 root fix) - the probe close
        // is a typed CANCELLED teardown, a real user close stays userClose,
        // and the legacy closeIntent mapping delegates identically (r8 Mac
        // evidence: probe close stamped endReason=userClose).
        do {
            check(EndReason.from(audioTerminal: .stoppedEarly, closeActor: .probe) == .cancelled, "T24 probe close is cancelled, not userClose")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeActor: .user) == .userClose, "T24 user close stays userClose")
            check(EndReason.from(audioTerminal: .stoppedEarly, closeActor: .none) == .stoppedEarly, "T24 no close actor stays stoppedEarly")
            check(EndReason.from(audioTerminal: .endOfStream, closeActor: .probe) == .endOfStream, "T24 probe never rewrites EOS")
            check(EndReason.from(audioTerminal: .failed, closeActor: .probe) == .decodeFailed, "T24 probe never rewrites failure")
            check(EndReason.from(audioTerminal: .sourceEnded, closeActor: .probe) == .sourceEnded, "T24 probe never rewrites sourceEnded")
            check(EndReason.from(audioTerminal: .cancelled, closeActor: .probe) == .cancelled, "T24 cancelled stable under probe")
            for t in [AudioTerminalKind.endOfStream, .failed, .sourceEnded, .stoppedEarly, .cancelled] {
                check(EndReason.from(audioTerminal: t, closeIntent: true) == EndReason.from(audioTerminal: t, closeActor: .user), "T24 closeIntent=true delegates to user actor", "\(t.rawValue)")
                check(EndReason.from(audioTerminal: t, closeIntent: false) == EndReason.from(audioTerminal: t, closeActor: .none), "T24 closeIntent=false delegates to no actor", "\(t.rawValue)")
            }
            check(EndReason.videoTerminal(windowClosed: true, closeActor: .probe, pumpEnd: .cancelled, sourceEnd: .stopped) == .cancelled, "T24 timed-close video leg is cancelled")
            check(EndReason.videoTerminal(windowClosed: true, closeActor: .user, pumpEnd: .cancelled, sourceEnd: .stopped) == .userClose, "T24 real user close video leg is userClose")
            check(EndReason.videoTerminal(windowClosed: true, closeActor: .user, pumpEnd: .failed(-1), sourceEnd: .decodeFailed) == .userClose, "T24 close intent outranks pump failure (r8 priority)")
            check(EndReason.videoTerminal(windowClosed: false, closeActor: .none, pumpEnd: .endOfStream, sourceEnd: .endOfStream) == .endOfStream, "T24 clean EOS preserved")
            check(EndReason.videoTerminal(windowClosed: false, closeActor: .none, pumpEnd: .failed(-1), sourceEnd: .decodeFailed) == .decodeFailed, "T24 pump failure preserved")
            check(EndReason.videoTerminal(windowClosed: false, closeActor: .none, pumpEnd: .cancelled, sourceEnd: .stopped) == .cancelled, "T24 bare cancel preserved")
            check(EndReason.videoTerminal(windowClosed: false, closeActor: .none, pumpEnd: .endOfStream, sourceEnd: .interrupted) == .stoppedEarly, "T24 interrupted source is stoppedEarly")
            check(EndReason.combined(audio: .cancelled, video: .cancelled) == .cancelled, "T24 timed-close combined summary is cancelled")
            check(EndReason.combined(audio: .userClose, video: .userClose) == .userClose, "T24 user-close combined summary is userClose")
        }
        // T25: close-actor stamp precedence matrix (r9; drives the Mac
        // DisplaySink probe/user stamping). First actor wins; the probe
        // stamps only a close that actually lands; a veto leaves no stamp.
        do {
            var s0 = CloseActorStamp()
            check(s0.actor == .none && !s0.closeIntent, "T25 initial: no actor, no intent")
            // probe first, close lands -> probe actor, intent recorded
            var s1 = CloseActorStamp()
            check(s1.probeFire(), "T25 probe fires when no intent")
            s1.recordCloseIntent()
            check(s1.actor == .probe && s1.closeIntent, "T25 probe close lands: probe actor")
            // user first -> probe is refused, user keeps the actor
            var s2 = CloseActorStamp()
            s2.recordCloseIntent()
            check(!s2.probeFire(), "T25 probe refused after user close")
            check(s2.actor == .user, "T25 actual user close never re-attributed to probe")
            // veto / no-fire: probe bracket returns with no intent, no stamp
            var s3 = CloseActorStamp()
            check(s3.probeFire(), "T25 veto case: probe fires")
            s3.probeCloseReturned() // performClose returned, delegate never ran
            check(s3.actor == .none && !s3.closeIntent, "T25 vetoed probe leaves no stamp")
            s3.recordCloseIntent() // a later REAL user close
            check(s3.actor == .user, "T25 user close after vetoed probe is user")
            // veto then EOS teardown: nothing recorded, EOS stays EOS (no misattribution)
            var s4 = CloseActorStamp()
            _ = s4.probeFire(); s4.probeCloseReturned()
            check(s4.actor == .none && !s4.closeIntent, "T25 EOS after vetoed probe keeps no actor")
            // reentrancy: a second delegate intent never restamps
            var s5 = CloseActorStamp()
            _ = s5.probeFire(); s5.recordCloseIntent(); s5.recordCloseIntent()
            check(s5.actor == .probe, "T25 reentrant close intent never restamps")
            check(!s5.probeFire(), "T25 second probe refused after landed close")
            // user-only run (no probe): actor is user, intent true
            var s6 = CloseActorStamp()
            s6.recordCloseIntent()
            check(s6.actor == .user && s6.closeIntent, "T25 user-only close stamps user")
        }
        print(failures == 0 ? "ALL MODEL TESTS PASS" : "MODEL TEST FAILURES: \(failures)")
        SPSC.run()
        Foundation.exit((failures == 0 && SPSC.failures == 0) ? 0 : 1)
    }
}

```

```text id=rf3
// M4 seek pacing re-anchor test (Linux): proves the post-seek pace preserves
// the measured late-start gap in ACTUAL pace - the first post-seek frame
// shows on arrival and later frames pace by pts deltas - instead of the
// raw-wall defects: forward seek = wait for the whole seek distance,
// backward seek = drop-storm to EOF. Pure Swift fakes; no FFmpeg.
import GorAVPlaybackCore
import Foundation

import Foundation
var failures = 0
func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

final class FakeClock: PlaybackClock, @unchecked Sendable { var t: Double = 0; func nowSeconds() -> Double { t } }
final class Recorder: FrameSink, @unchecked Sendable {
    private let l = NSLock(); var shown: [Double] = []; var showWalls: [Double] = []
    let clock: FakeClock
    init(_ c: FakeClock) { clock = c }
    func show(_ f: SourceFrame) async -> Bool { l.lock(); shown.append(f.ptsSeconds); showWalls.append(clock.t); l.unlock(); return true }
    func show(_ f: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool { await show(f) }
    func snapshot() -> ([Double], [Double]) { l.lock(); defer { l.unlock() }; return (shown, showWalls) }
}
final class ScriptedSource: FrameSource, @unchecked Sendable {
    private let l = NSLock()
    private var script: [Double] = []; private var idx = 0; private var endWhenDrained = false
    func setScript(_ pts: [Double], end: Bool) { l.lock(); script = pts; idx = 0; endWhenDrained = end; l.unlock() }
    func nextEvent() async -> SourceEvent {
        l.lock()
        defer { l.unlock() }
        guard idx < script.count else { return endWhenDrained ? .ended(.endOfStream) : .temporarilyUnavailable }
        let pts = script[idx]; idx += 1
        return .frame(SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: "d\(pts)"))
    }
}

@main struct SeekPacingTests {
    static func scenario(_ name: String, pre: [Double], post: [Double], gap: Double,
                         expectShown: [Double]) async {
        let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource()
        src.setScript(pre, end: false)
        // Fake sleep must YIELD the executor (non-suspending async tight-loops
        // starve a small vCPU pool); the fake clock advances by the full wait.
        let pump = FramePump(source: src, sink: rec, clock: clock) { seconds in
            try? await Task.sleep(nanoseconds: 100_000); clock.t += seconds; return true
        }
        let run = Task { await pump.run() }
        while rec.snapshot().0.count < pre.count { try? await Task.sleep(nanoseconds: 2_000_000) }
        let ok = await pump.resetPresentation()
        expect(ok, "\(name): resetPresentation accepted (stateless source)")
        clock.t += gap                              // measured late-start gap: REAL wall time
        let wallAtLanding = clock.t
        src.setScript(post, end: true)
        let stats = await run.value
        let (shown, walls) = rec.snapshot()
        expect(shown == expectShown, "\(name): shown \(shown) == expected \(expectShown)")
        expect(stats.dropped == 0, "\(name): zero drops (got \(stats.dropped))")
        // First post-seek frame shows AT arrival wall (gap preserved, no
        // seek-distance wait): its show wall == landing wall exactly.
        if let i = shown.firstIndex(of: post[0]) {
            // On arrival = within ONE starve-backoff interval (0.05s) of
            // landing, NOT after the seek distance (forward old: +4.65s)
            // and not dropped (backward old: drop-storm to EOF).
            let lateness = walls[i] - wallAtLanding
            expect(lateness >= 0 && lateness <= 0.06, "\(name): first post-seek frame shown on arrival (lateness \(lateness)s, must be <= one backoff)")
        }
        log("\(name): shown=\(shown) drops=\(stats.dropped) waits=\(stats.waits)")
        // Deterministic witness log (queue item 19): shown/drops are asserted
        // exact above, so they are byte-stable across runs. waits is excluded:
        // starve-backoff iteration counts depend on real scheduling.
        print("DIGEST \(name) shown=\(shown) drops=\(stats.dropped)")
    }
    static func main() async {
        // MediaWallAnchor math: same anchor, canonical vs +100ms edit-list audio.
        let anchor = MediaWallAnchor(mediaSeconds: 5.0, wallSeconds: 2.0)
        expect(anchor.scheduledWall(forMediaSeconds: 5.0) == 2.0, "canonical: first pcm at target schedules at commit wall (0 wait)")
        expect(abs(anchor.scheduledWall(forMediaSeconds: 5.1) - 2.1) < 1e-9, "+100ms fixture: first pcm schedules 100ms after commit wall")
        expect(anchor.scheduledWall(forMediaSeconds: 5.3) == 2.3, "video keyframe at +0.3 schedules +0.3 (legitimate gap, not flattened)")
        print("DIGEST anchor canonical=\(anchor.scheduledWall(forMediaSeconds: 5.0)) plus100ms=\(anchor.scheduledWall(forMediaSeconds: 5.1)) keyframe03=\(anchor.scheduledWall(forMediaSeconds: 5.3))")

        await scenario("forward", pre: [0, 0.04, 0.08], post: [5.0, 5.04, 5.08], gap: 0.35,
                       expectShown: [0, 0.04, 0.08, 5.0, 5.04, 5.08])
        await scenario("backward", pre: [0, 0.04], post: [0.02, 0.06, 0.10], gap: 0.20,
                       expectShown: [0, 0.04, 0.02, 0.06, 0.10])
        // RULES.md:69 landing: first post-seek frame pts = target+0.3
        // PRESENTS ON ARRIVAL and owns the anchor (pts + arrival wall); the
        // audio clock restarts on that anchor, so the keyframe gap never
        // becomes an audio-ahead dead window. (Supersedes the M4 shared
        // anchor's "gap honored as a video wait" - that design restarted
        // audio at the commit wall and let audio run ahead of video.)
        do {
            // No concurrent fake-clock advance during setup. The source's
            // first delivery switches the wait phase, so pending starvation
            // waits cannot move the anchor/arrival relationship.
            final class Phase: @unchecked Sendable {
                let lock = NSLock(); var delivered = false
                func set() { lock.lock(); delivered = true; lock.unlock() }
                func value() -> Bool { lock.lock(); defer { lock.unlock() }; return delivered }
            }
            final class ControlledSource: FrameSource, @unchecked Sendable {
                var pump: FramePump?
                let clock: FakeClock, phase: Phase
                var index = 0
                init(_ clock: FakeClock, _ phase: Phase) { self.clock = clock; self.phase = phase }
                func nextEvent() async -> SourceEvent {
                    index += 1
                    if index == 1 { return .frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "pre")) }
                    if index == 2 {
                        let ok = await pump!.resetPresentation(seekLandingTarget: 5)
                        expect(ok, "keyframeGap: reset accepted")
                        clock.t += 0.18
                        // This event is intentionally stale due to reset. Pump
                        // must fence it; the next delivery owns the fresh stamp.
                        return .temporarilyUnavailable
                    }
                    if index == 3 {
                        phase.set()
                        return .frame(SourceFrame(ptsSeconds: 5.3, durationSeconds: 0.04, digest: "post"))
                    }
                    return .ended(.endOfStream)
                }
            }
            let clock = FakeClock(), phase = Phase()
            let rec = Recorder(clock), src = ControlledSource(clock, phase)
            let pump = FramePump(source: src, sink: rec, clock: clock) { seconds in
                if phase.value() { clock.t += seconds }
                return true
            }
            src.pump = pump
            let stats = await pump.run()
            let (shown, walls) = rec.snapshot()
            expect(shown == [0, 5.3], "keyframeGap: shown \(shown)")
            expect(stats.seekStalePulls == 1, "keyframeGap: setup event fenced")
            if walls.count == 2 {
                let lateness = walls[1] - 0.18
                expect(lateness >= 0 && lateness <= 0.001,
                       "keyframeGap: landing frame presents ON ARRIVAL (no dead window), got \(lateness)")
            }
            print("DIGEST keyframeGap shown=\(shown) stalePulls=\(stats.seekStalePulls)")
        }
        // RULES.md:69 catch-up drop: frames BELOW the landing target are
        // discarded instantly (no pacing, no anchor); the first frame
        // at/past the target presents on arrival and owns the anchor.
        do {
            let clock = FakeClock(), rec = Recorder(clock), src = ScriptedSource()
            src.setScript([0], end: false)
            let pump = FramePump(source: src, sink: rec, clock: clock) { seconds in
                try? await Task.sleep(nanoseconds: 100_000); clock.t += seconds; return true
            }
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 1 { try? await Task.sleep(nanoseconds: 2_000_000) }
            let ok = await pump.resetPresentation(seekLandingTarget: 5.0)
            expect(ok, "landingDrop: reset accepted")
            clock.t += 0.20
            let wallAtLanding = clock.t
            src.setScript([4.92, 4.96, 5.0, 5.04], end: true)
            let stats = await run.value
            let (shown, walls) = rec.snapshot()
            expect(shown == [0, 5.0, 5.04], "landingDrop: shown \(shown) (pre-target 4.92/4.96 dropped)")
            expect(stats.dropped == 2, "landingDrop: exactly the two pre-target frames dropped (got \(stats.dropped))")
            if let i = shown.firstIndex(of: 5.0) {
                let lateness = walls[i] - wallAtLanding
                expect(lateness >= 0 && lateness <= 0.06,
                       "landingDrop: landing frame 5.0 shown on arrival, owns anchor (lateness \(lateness))")
            }
            if let i = shown.firstIndex(of: 5.04) {
                let lateness = walls[i] - wallAtLanding
                expect(lateness >= 0.03 && lateness <= 0.10,
                       "landingDrop: 5.04 paced 0.04 off the landing anchor (lateness \(lateness))")
            }
            log("landingDrop: shown=\(shown) drops=\(stats.dropped) waits=\(stats.waits)")
        }
        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}


```

```text id=actual_run_log
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Emitting module GorAVCore
[8/15] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/41] Emitting module GorAVPlaybackCore
[22/57] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[23/57] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[24/57] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[25/57] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[26/57] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[27/57] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[28/57] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[29/57] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[30/57] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[31/57] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[32/57] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[33/57] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[34/57] Compiling GorAVPlaybackCore Lane0Contract.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[35/57] Compiling GorAVPlaybackCore LifetimeRegistry.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[36/57] Compiling GorAVPlaybackCore ObservationSurface.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[37/57] Compiling GorAVPlaybackCore PlayArguments.swift
/tmp/packet-proof-thv5soje/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[38/57] Compiling GorAVPlaybackCore PlaybackCore.swift
[39/57] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[40/57] Compiling GorAVPlaybackCore PlayheadObservers.swift
[41/57] Compiling GorAVPlaybackCore PlayheadPosition.swift
[42/57] Compiling GorAVPlaybackCore PreparedAdoption.swift
[43/57] Compiling GorAVPlaybackCore PreparedShotSession.swift
[44/57] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[45/57] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[46/57] Compiling GorAVPlaybackCore RenderGraph.swift
[47/57] Compiling GorAVPlaybackCore SPSC.swift
[48/57] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[49/57] Compiling GorAVPlaybackCore StageGeometry.swift
[50/57] Compiling GorAVPlaybackCore TapCropDetector.swift
[51/57] Compiling GorAVPlaybackCore TimingLedger.swift
[52/57] Compiling GorAVPlaybackCore UniformPacking.swift
[53/57] Compiling GorAVPlaybackCore WindowModePlan.swift
[54/58] Wrapping AST for GorAVPlaybackCore for debugging
[56/60] Compiling timing_ledger_tests SPSCTests.swift
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:24:17: warning: variable 'bytes' was never mutated; consider changing to 'let' constant
            var bytes = [UInt8](repeating: 0xAB, count: 10) // 2 frames + 2-byte tail
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:40:17: warning: variable 'extra' was never mutated; consider changing to 'let' constant
            var extra = frame(99) + frame(98)
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:52:17: warning: variable 'two' was never mutated; consider changing to 'let' constant
            var two = [UInt8](repeating: 7, count: 8)
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:152:21: warning: variable 'pcm' was never mutated; consider changing to 'let' constant
                var pcm = [UInt8](repeating: 5, count: 4 * 16)
                ~~~ ^
                let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:181:17: warning: variable 'b3' was never mutated; consider changing to 'let' constant
            var b3: [UInt8] = [1, 2, 3]
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:186:17: warning: variable 'full' was never mutated; consider changing to 'let' constant
            var full: [UInt8] = [UInt8](repeating: 9, count: 20) // 5 frames > cap 4
            ~~~ ^
            let
[57/60] Emitting module timing_ledger_tests
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:24:17: warning: variable 'bytes' was never mutated; consider changing to 'let' constant
            var bytes = [UInt8](repeating: 0xAB, count: 10) // 2 frames + 2-byte tail
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:40:17: warning: variable 'extra' was never mutated; consider changing to 'let' constant
            var extra = frame(99) + frame(98)
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:52:17: warning: variable 'two' was never mutated; consider changing to 'let' constant
            var two = [UInt8](repeating: 7, count: 8)
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:152:21: warning: variable 'pcm' was never mutated; consider changing to 'let' constant
                var pcm = [UInt8](repeating: 5, count: 4 * 16)
                ~~~ ^
                let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:181:17: warning: variable 'b3' was never mutated; consider changing to 'let' constant
            var b3: [UInt8] = [1, 2, 3]
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/SPSCTests.swift:186:17: warning: variable 'full' was never mutated; consider changing to 'let' constant
            var full: [UInt8] = [UInt8](repeating: 9, count: 20) // 5 frames > cap 4
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/TimingLedgerTests.swift:188:17: warning: variable 't' was never mutated; consider changing to 'let' constant
            var t = 50.0
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/TimingLedgerTests.swift:376:17: warning: variable 's0' was never mutated; consider changing to 'let' constant
            var s0 = CloseActorStamp()
            ~~~ ^
            let
[58/61] Compiling timing_ledger_tests TimingLedgerTests.swift
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/TimingLedgerTests.swift:188:17: warning: variable 't' was never mutated; consider changing to 'let' constant
            var t = 50.0
            ~~~ ^
            let
/tmp/packet-proof-thv5soje/tree/Sources/timing-ledger-tests/TimingLedgerTests.swift:376:17: warning: variable 's0' was never mutated; consider changing to 'let' constant
            var s0 = CloseActorStamp()
            ~~~ ^
            let
[59/62] Wrapping AST for timing-ledger-tests for debugging
[60/62] Write Objects.LinkFileList
[61/62] Linking timing-ledger-tests
Build complete! (7.77s)
PASS T1 lifecycle order
PASS T1 seq monotonic
PASS T1 tRel non-decreasing
PASS T1 allowsSuccess
PASS T2 start-starve silence not consumed
PASS T2 real bytes before silence
PASS T3 mid-starve counters
PASS T4 fill admitted
PASS T4 overflow dropped
PASS T4 retained content identity is the oldest ordered bytes
PASS T5 recorded maxAvail within watermark+chunk
PASS T5 admission bound verified from records
PASS T5 no bound claim without recorded maxima
PASS T5 MUTANT overrun refuses bound
PASS T5 MUTANT maxAvail>watermark+chunk refuses bound
PASS T6 fence decision
PASS T6 close intent precedes fence skip
PASS T7 eos
PASS T7 decodeFailed
PASS T7 sourceEnded
PASS T7 userClose distinct
PASS T7 bare stoppedEarly
PASS T7 six distinct end reasons
PASS T8 MUTANT stop-before-start is a no-op (guard not consumed)
PASS T8 first start reserves generation 1
PASS T8 MUTANT double start refused
PASS T8 commit
PASS T8 stop owns teardown
PASS T8 MUTANT start-during-teardown refused
PASS T8 MUTANT double dispose refused
PASS T8 stop counted at quiescence, not at begin
PASS T8 start-stop-start RE-ARMS with generation 2
PASS T8 aborted start rolls back and re-arms
PASS T8 stop-races-start is typed, touches nothing
PASS T8 raced start commit fails
PASS T8 raced stop completed by start side
PASS T8 MUTANT start on FAILED session refused
PASS T8 stop on FAILED is a no-op
PASS T9 current generation admitted
PASS T9 MUTANT stale-generation callback fenced
PASS T9 stale attempt recorded
PASS T9 new generation admitted
PASS T10 overflow refuses success
PASS T11 transitions folded
PASS T11 EVENT-TIME stamps preserved, not drain time
PASS T11 post-time generation preserved
PASS T11 clean fold keeps success
PASS T11 overflow latch set
PASS T11 RT overflow folds into ledger and refuses success
PASS T12 shown count
PASS T12 shown order identity
PASS T12 backward typed drop
PASS T12 forward gap classified once
PASS T12 frameShown events
PASS T12 backward event recorded
PASS T12 non-finite typed drop
PASS T12 non-finite event
PASS T20 out-of-order sequence is INCOMPLETE
PASS T20 own session ordered single kind complete
PASS T20 foreign-session kind never counts
PASS T21 publication order kept despite older folded stamp
PASS T21 folded event keeps event-time + EXACT frame->byte conversion
PASS T22 sticky latch set with counter 2
PASS T22 reset clears latch+counter
PASS T13 header + one event
PASS T13 header
PASS T13 event parses as real JSON
PASS T13 escaping round-trips through JSONEncoder
PASS T13 truncation marker receipt is last line
PASS T13 truncated export marks truncation, verdict unpoisoned
PASS T13 ingestion capacity overflow still refuses success
PASS T13 note byte-bound
PASS T13 non-finite stamp refuses success
PASS T14 refused show not counted shown
PASS T14 MUTANT frameShown on refused show absent
PASS T24 probe close is cancelled, not userClose
PASS T24 user close stays userClose
PASS T24 no close actor stays stoppedEarly
PASS T24 probe never rewrites EOS
PASS T24 probe never rewrites failure
PASS T24 probe never rewrites sourceEnded
PASS T24 cancelled stable under probe
PASS T24 closeIntent=true delegates to user actor
PASS T24 closeIntent=false delegates to no actor
PASS T24 closeIntent=true delegates to user actor
PASS T24 closeIntent=false delegates to no actor
PASS T24 closeIntent=true delegates to user actor
PASS T24 closeIntent=false delegates to no actor
PASS T24 closeIntent=true delegates to user actor
PASS T24 closeIntent=false delegates to no actor
PASS T24 closeIntent=true delegates to user actor
PASS T24 closeIntent=false delegates to no actor
PASS T24 timed-close video leg is cancelled
PASS T24 real user close video leg is userClose
PASS T24 close intent outranks pump failure (r8 priority)
PASS T24 clean EOS preserved
PASS T24 pump failure preserved
PASS T24 bare cancel preserved
PASS T24 interrupted source is stoppedEarly
PASS T24 timed-close combined summary is cancelled
PASS T24 user-close combined summary is userClose
PASS T25 initial: no actor, no intent
PASS T25 probe fires when no intent
PASS T25 probe close lands: probe actor
PASS T25 probe refused after user close
PASS T25 actual user close never re-attributed to probe
PASS T25 veto case: probe fires
PASS T25 vetoed probe leaves no stamp
PASS T25 user close after vetoed probe is user
PASS T25 EOS after vetoed probe keeps no actor
PASS T25 reentrant close intent never restamps
PASS T25 second probe refused after landed close
PASS T25 user-only close stamps user
ALL MODEL TESTS PASS
PASS S1 partial tail refused BYTE-exact, not as a frame
PASS S1 available is whole frames
PASS S1 tail counted as 2 BYTES not 4
PASS S1 byte conservation requested==admitted+dropped
PASS S2 fill
PASS S2 overflow drop frame-quantized
PASS S2 no underrun on full ring
PASS S2 retained identity oldest ordered frames
PASS S3 underrun frames counted
PASS S3 shortfall is silence
PASS S4 drain order
PASS S4 post-time stamps preserved
PASS S4 generation at post time
PASS S4 overflow latch set
PASS S4 latch sticky after drain
PASS S5a serial prefill overflow exercised exactly one dropped frame
PASS S5 conservation admitted==consumed+remaining
PASS S5 BYTE conservation requested==admitted+dropped
PASS S6 live ring zeroed after reset
PASS S6 retired receipt survives reset
PASS S6 post-stop evidence still proves the bound
PASS S7 negative watermark refused
PASS S7 watermark+chunk>capacity refused
PASS S5 no torn/reordered frames under concurrency
ALL SPSC TESTS PASS
PASS S8 latch starts clear
PASS S8 tail refusal latches sticky
PASS S8 reset clears latch
PASS S8 frame drop latches sticky
PASS S8 receipt carries the latch + generation
T23 admission cell (architect 80b constraint A)
PASS T23 first enter admitted
PASS T23 ONE-CONSUMER: second enter while busy REFUSED (busy => silence, architect full verdict S2)
PASS T23 reader count stays 1 under contention
PASS T23 reader drained
PASS T23 enter re-admitted after drain (not yet retired)
PASS T23 retire reports zero in-flight readers at retire
PASS T23 retired flag set
PASS T23 MUTANT-NEGATIVE: enter after retire REFUSED
PASS T23 retire idempotent
PASS T23 still refused after retire (retire is terminal)
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-thv5soje/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[1/8] Write swift-version--9C6B84B6E025C5B.txt
[3/7] Emitting module seek_pacing_tests
[4/7] Compiling seek_pacing_tests SeekPacingTests.swift
[5/8] Wrapping AST for seek-pacing-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking seek-pacing-tests
Build complete! (0.86s)
forward: shown=[0.0, 0.04, 0.08, 5.0, 5.04, 5.08] drops=0 waits=4
backward: shown=[0.0, 0.04, 0.02, 0.06, 0.1] drops=0 waits=3
landingDrop: shown=[0.0, 5.0, 5.04] drops=2 waits=1
ALL_CHECKS_PASS
DIGEST anchor canonical=2.0 plus100ms=2.0999999999999996 keyframe03=2.3
DIGEST forward shown=[0.0, 0.04, 0.08, 5.0, 5.04, 5.08] drops=0
DIGEST backward shown=[0.0, 0.04, 0.02, 0.06, 0.1] drops=0
DIGEST keyframeGap shown=[0.0, 5.3] stalePulls=1
```
