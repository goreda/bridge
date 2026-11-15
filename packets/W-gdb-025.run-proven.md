# W-gdb-025 audio ring-buffer seek-reset model + property tests
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-025

```packet-json
{
  "packet_id": "W-gdb-025",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/SPSC.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVMacShell/AudioUnitSink.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64); resetForNewGeneration()",
    "types": "RTEvent { kind: underrunStart | underrunEnd | staleFenced, generation: UInt64, tEvent: Double, payload }; AdmissionCell { enter/exit/retire/readers/isRetired }; AtomicU64",
    "ownership_lifetime": "RT plane; AdmissionCell is a LOCAL payload lifetime fence, no provider-quiescence claim",
    "caller": "ring model tests (Linux)",
    "callee": "SPSCPCMRing.push/resetForNewGeneration + AdmissionCell + RTEvent vocabulary (pinned below)"
  },
  "test": {
    "command": "swift run --package-path kits/ring-model ring-model-tests",
    "expected": "exit 0; final line matches '^ring-model-tests: [1-9][0-9]* PASS, 0 FAIL$'; deterministic seeds printed; a seeded stale-generation write is caught (negative control shown)",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/ring-model/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/ring-model/Package.swift",
        "block": "rf1"
      },
      {
        "path": "kits/ring-model/Sources/RingModel/RingModel.swift",
        "block": "rf3"
      },
      {
        "path": "kits/ring-model/Sources/ring-model-tests/main.swift",
        "block": "rf4"
      },
      {
        "path": "kits/ring-model/ring_model.py",
        "block": "rf7"
      },
      {
        "path": "kits/ring-model/ring_model_tests.py",
        "block": "rf8"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "swift run --package-path kits/ring-model ring-model-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:22:13.969580+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ring-model-tests: 36 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "kits/ring-model/Package.swift",
        "block": "rf1",
        "sha256": "e4676e7afe3b49adc709157ea36ee4144807e55381f5787d96ef14062781ad31"
      },
      {
        "path": "kits/ring-model/Sources/RingModel/RingModel.swift",
        "block": "rf3",
        "sha256": "4276a7c4a62f4c463e960f78a2b762b96803a074a4db6c54f25d85dbc007346f"
      },
      {
        "path": "kits/ring-model/Sources/ring-model-tests/main.swift",
        "block": "rf4",
        "sha256": "04cafb759bec1181bf87e8f8533b850b892903e996576f21bd801806a7de7db7"
      },
      {
        "path": "kits/ring-model/ring_model.py",
        "block": "rf7",
        "sha256": "f5a11ebbc18b68845c11cd0ab5b947aaf07363f70fd2a1132a6904d7ec30370a"
      },
      {
        "path": "kits/ring-model/ring_model_tests.py",
        "block": "rf8",
        "sha256": "9097f3eed80f1e20e2c22f279a7f5e8fea3df59492205e834a96584180e54c53"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "15d97eaf9212717214e30c9140224e75a6369b8f8717dfb4850d924ddcc395cf",
    "last_5_lines": [
      "seeds: 42 1 7 2026 31337 99991 123456 8675309",
      "negative control BuggyStaleAcceptRing: caught on 8/8 seeds; first violation: stale write admitted",
      "negative control BuggyPauseUnderrunRing: caught on 8/8 seeds; first violation: underrun frames counter (pause silence leaked?)",
      "negative control BuggyNoRearmRing: caught on 8/8 seeds; first violation: underrun events 19/14 vs 19/19",
      "ring-model-tests: 36 PASS, 0 FAIL"
    ],
    "receipt_sha256": "72d8e8794ba9ee07c0d3ce2f284279aa21a977e0cc799c22e71856da910e10c0"
  }
}
```

## problem (what fails for the user)
the audio ring (SPSC) and the sink's pause-silence contract carry seek generations and counters; without a portable model + property tests over randomized op sequences, a fencing regression (stale-generation write accepted) ships as a post-seek audio pop or bleed.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/SPSC.swift (sha256 fcba3646; ring excerpt below) and Sources/GorAVMacShell/AudioUnitSink.swift (sha256 22cb8c69; pause-contract excerpt below).
- real test command: the returned model runs on Linux; existing seek-ring-reset/audio suites stay green.

## expected behaviour
a portable ring model with seek generations (reset fencing, underrun accounting, pause-silence counters, resume re-arm) plus property tests over randomized push/reset/pause/resume/read sequences asserting counter invariants and fence honesty; deterministic seeds.

## exact call site and interface
the ring's push/reset/read semantics and the sink's silence-counter contract (pinned excerpts) define the model's vocabulary.

## pinned ABI decisions (integrator, 2026-11-15; push/reset fence ABI)
- public func SPSCPCMRing.push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64) (SPSC.swift, same pin); PCMRingReceipt carries the same accounting fields
- reset fencing: resetForNewGeneration() clears per-generation state; a write tagged with an old generation after the bump is fenced - RTEvent.Kind.staleFenced (= 3) is the typed witness; RTEvent { kind, generation: UInt64 (session generation AT POST TIME), tEvent: Double, payload: .frames(UInt64) | .bytes(UInt64) }
- AdmissionCell (LOCAL payload lifetime fence, no provider-quiescence claim): enter() -> Bool, exit(), retire() -> UInt64, readers: UInt64, isRetired: Bool; payload zeroed BEFORE any reset/reuse/dispose
- AtomicU64: load/store/fetchAdd/compareExchange - the counter primitives the model mirrors
property invariants the model asserts: admitted + dropped == offered per push; a stale-generation push is fenced (staleFenced, never admitted); underrun accounting matches underrunStart/underrunEnd events.

## behaviour that must not change
the pause contract (callbacks continue rendering intentional silence) is preserved exactly; no audio-device claim.

## acceptance test (from the product repo)
property tests PASS on Linux across seeds; a seeded stale-generation write is caught (negative control shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/SPSC.swift (sha256 fcba3646, lines 260-290 of 333)
```swift id=source1
            pushCount.fetchAdd(1)
            admittedBytes.fetchAdd(admit &* UInt64(SPSCPCMRing.bytesPerFrame))
        }
        if drop > 0 {
            droppedFrames.fetchAdd(drop)
            droppedBytes.fetchAdd(drop &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
        }
        return (admit, drop, tail)
    }
    private var bufCount: Int { Int(capacityFrames) &* SPSCPCMRing.bytesPerFrame }
    /// Consumer side (RT). Renders `frames` frames DIRECTLY into `dst`:
    /// real frames copied, shortfall zero-filled and counted as underrun.
    /// No allocation, no lock, no Array subscript. Returns underrun frames.
    /// v4-5: frames is UInt32 (the AudioUnit unit); byte arithmetic is
    /// range-checked, no UInt64->Int narrowing.
    @discardableResult
    public func render(into dst: UnsafeMutablePointer<UInt8>, frames: UInt32) -> UInt32 {
        let want = UInt64(frames)
        let ri = r.load()                    // own: exact
        let wi = w.load()                    // producer's: acquire; may equal/exceed ri
        let avail = wi >= ri ? wi - ri : 0   // saturating: never underflows
        let real = Swift.min(avail, want)
        if real > 0 {
            var idx = Int(ri % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var i = 0
            let n = Int(real) &* SPSCPCMRing.bytesPerFrame // real <= UInt32.max frames
            while i < n {
                dst[i] = buf[idx]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                i &+= 1
```

### Sources/GorAVMacShell/AudioUnitSink.swift (sha256 22cb8c69, lines 634-678 of 1284)
```swift id=source2
        guard let p = AudioPacingPolicy(hostClock: hostClock,
                                        sampleRate: AudioUnitSink.pcmSampleRate,
                                        consistencyTolerance: consistencyTolerance) else { return false }
        pacingHostClock = hostClock
        pacingPolicy = p
        pacingClock = AudioMasterPacingClock(policy: p, hostClock: hostClock)
        return true
    }

    /// M1 typed pause (condition (a)): quiesce the render path. The ring
    /// residual is HELD (no consumption), intentional silence is NOT
    /// underrun/overrun (its own counter), and no clock-drift decisions
    /// run while quiesced. Typed false when not active, unattached, or
    /// already paused. The J3 pause path calls this.
    /// The WHOLE pause is one stateLock section (20:40 lifecycle race):
    /// lifecycle check + policy pause + RT flag store are atomic against
    /// stop()/start(), so a teardown can never orphan a quiesce into the
    /// next session. Boundary contract (architect 20:12) unchanged:
    /// pushIfUnpaused holds the same lock across admission + pause check
    /// + ring write, so once pauseAudio() returns true no admitted push
    /// can enter the ring; J3's async pre-push audioPaused check is an
    /// optimization, correctness does not depend on it.
    @discardableResult
    public func pauseAudio() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard case .active = lifecycle.current, let p = pacingPolicy, pausedFlag?.load() == 0 else {
            return false
        }
        guard p.pause(atHost: hostSeconds()) else { return false }
        pausedFlag?.store(1)
        return true
    }

    /// M1 typed resume: a NEW clock generation (8.5) anchored on the
    /// device-consumed counter frozen over the pause BEFORE consumption
    /// resumes - the anchor is exact and the value continues from the
    /// frozen point (no jump).
    /// One stateLock section, symmetric with pauseAudio (20:40): the
    /// policy resume (new generation on the frozen device-consumed
    /// counter), the receipt fold, and the RT flag clear are atomic
    /// against stop()/start(). The RT thread is lock-free by design, so
    /// the silence fold carries a one-callback slack at this edge;
    /// receipts reconcile at transition granularity (condition (d)).
    @discardableResult
    public func resumeAudio() -> Bool {
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"seed":42,"ops":[{"push":{"frames":480}},{"resetForNewGeneration":{}},{"push":{"frames":480,"generation":"stale"},"expect":"staleFenced"},{"read":{"frames":480}}],"expectReceipts":[{"admitted":480,"dropped":0},{"admitted":0,"fenced":true}]}
```

## repair note (arch-196x item 4)
test.command corrected to `swift run --package-path kits/ring-model ring-model-tests` (the vendored kit is a nested Swift package; decision via main). inline files: kits/ring-model text sources + its Package.swift from gorav main (arch-196s disposition 10/15); README.md and the checked-in binary not inlined.

```text id=rf1
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "ring-model",
    targets: [
        .target(name: "RingModel", path: "Sources/RingModel"),
        .executableTarget(name: "ring-model-tests", dependencies: ["RingModel"], path: "Sources/ring-model-tests"),
    ]
)

```

```text id=rf3
// Portable SPSC PCM ring model with seek generations. Sequential model of
// accounting and fencing only: no threads, no audio device, no provider-quiescence claim.
// AdmissionCell is a LOCAL payload lifetime fence.

public final class AtomicU64 {
    private var v: UInt64
    public init(_ initial: UInt64 = 0) { v = initial }
    public func load() -> UInt64 { v }
    public func store(_ x: UInt64) { v = x }
    @discardableResult public func fetchAdd(_ d: UInt64) -> UInt64 { let o = v; v = o &+ d; return o }
    public func compareExchange(expected: UInt64, desired: UInt64) -> (exchanged: Bool, original: UInt64) {
        if v == expected { v = desired; return (true, expected) }
        return (false, v)
    }
}

public final class AdmissionCell {
    private let readerCount = AtomicU64()
    private var retired = false
    public var payload: [UInt8]? = nil
    public init() {}
    public func enter() -> Bool { if retired { return false }; readerCount.fetchAdd(1); return true }
    public func exit() { precondition(readerCount.load() > 0, "exit without enter"); readerCount.store(readerCount.load() - 1) }
    /// Zeroes payload BEFORE any reuse/dispose; returns readers still inside.
    public func retire() -> UInt64 { retired = true; payload = nil; return readerCount.load() }
    public var readers: UInt64 { readerCount.load() }
    public var isRetired: Bool { retired }
}

public enum RTPayload: Equatable { case frames(UInt64), bytes(UInt64) }

public struct RTEvent: Equatable {
    public enum Kind: Int { case underrunStart = 1, underrunEnd = 2, staleFenced = 3 }
    public var kind: Kind
    public var generation: UInt64   // session generation AT POST TIME
    public var tEvent: Double
    public var payload: RTPayload
}

public struct Receipt: Equatable {
    public var admittedFrames: UInt64 = 0
    public var droppedFrames: UInt64 = 0
    public var droppedTailBytes: UInt64 = 0
    public var fenced = false
    public var pausedReject = false
}

public class SPSCRingModel {
    public static let bytesPerFrame = 4
    public let cap: UInt64
    var buf: [UInt32]
    let w = AtomicU64(), r = AtomicU64()
    public private(set) var generation: UInt64 = 0
    public private(set) var paused = false
    public private(set) var events: [RTEvent] = []
    var clock = 0.0
    var inUnderrun = false
    public let admittedFrames = AtomicU64(), droppedFrames = AtomicU64(), droppedTailBytes = AtomicU64()
    public let fencedPushes = AtomicU64(), underrunFrames = AtomicU64(), underrunEvents = AtomicU64()
    public let silenceFrames = AtomicU64()          // intentional pause silence, NOT underrun
    public let genAdmitted = AtomicU64(), genUnderrun = AtomicU64()  // cleared by reset

    public required init(capacityFrames: Int) {
        precondition(capacityFrames > 0)
        cap = UInt64(capacityFrames); buf = [UInt32](repeating: 0, count: capacityFrames)
    }
    func post(_ k: RTEvent.Kind, _ n: UInt64) {
        clock += 1; events.append(RTEvent(kind: k, generation: generation, tEvent: clock, payload: .frames(n)))
    }
    public var occupancy: UInt64 { w.load() - r.load() }

    /// `generation: nil` = current generation tag.
    public func push(_ ids: [UInt32], tailBytes: UInt64 = 0, generation tagIn: UInt64? = nil) -> Receipt {
        precondition(tailBytes < UInt64(SPSCRingModel.bytesPerFrame))
        let tag = tagIn ?? generation
        if tag != generation {
            fencedPushes.fetchAdd(1); post(.staleFenced, UInt64(ids.count))
            var rc = Receipt(); rc.fenced = true; return rc
        }
        if paused { var rc = Receipt(); rc.pausedReject = true; return rc }
        let offered = UInt64(ids.count)
        let admit = min(offered, cap - occupancy), drop = offered - admit
        let wi = w.load()
        var i: UInt64 = 0
        while i < admit { buf[Int((wi &+ i) % cap)] = ids[Int(i)]; i += 1 }
        w.store(wi &+ admit)
        if admit > 0 { admittedFrames.fetchAdd(admit); genAdmitted.fetchAdd(admit) }
        if drop > 0 { droppedFrames.fetchAdd(drop) }
        if tailBytes > 0 { droppedTailBytes.fetchAdd(tailBytes) }
        return Receipt(admittedFrames: admit, droppedFrames: drop, droppedTailBytes: tailBytes)
    }

    public func resetForNewGeneration() {
        if inUnderrun { post(.underrunEnd, 0); inUnderrun = false }  // close under OLD generation
        generation &+= 1
        r.store(w.load())
        genAdmitted.store(0); genUnderrun.store(0)
    }

    public func read(frames: Int) -> (out: [UInt32], underrun: UInt64) {
        if paused { silenceFrames.fetchAdd(UInt64(frames)); return ([UInt32](repeating: 0, count: frames), 0) }
        let ri = r.load(), wi = w.load()
        let real = min(wi - ri, UInt64(frames))
        var out = [UInt32](); out.reserveCapacity(frames)
        var i: UInt64 = 0
        while i < real { out.append(buf[Int((ri &+ i) % cap)]); i += 1 }
        let short = UInt64(frames) - real
        out.append(contentsOf: [UInt32](repeating: 0, count: Int(short)))
        r.store(ri &+ real)
        if short > 0 {
            underrunFrames.fetchAdd(short); genUnderrun.fetchAdd(short)
            if !inUnderrun { inUnderrun = true; underrunEvents.fetchAdd(1); post(.underrunStart, short) }
        } else if inUnderrun && frames > 0 { inUnderrun = false; post(.underrunEnd, 0) }
        return (out, short)
    }

    @discardableResult public func pauseAudio() -> Bool {
        if paused { return false }
        if inUnderrun { post(.underrunEnd, 0); inUnderrun = false }
        paused = true   // residual HELD
        return true
    }
    /// Re-arms the underrun edge detector so the next shortfall posts a fresh underrunStart.
    @discardableResult public func resumeAudio() -> Bool {
        if !paused { return false }
        paused = false; inUnderrun = false; return true
    }
    // hooks for negative-control subclasses
    func setPausedRaw(_ p: Bool) { paused = p }
    var underrunOpen: Bool { get { inUnderrun } set { inUnderrun = newValue } }
}

/// NEGATIVE CONTROL: fence removed, stale-generation writes admitted.
public final class BuggyStaleAcceptRing: SPSCRingModel {
    public override func push(_ ids: [UInt32], tailBytes: UInt64 = 0, generation tagIn: UInt64? = nil) -> Receipt {
        super.push(ids, tailBytes: tailBytes, generation: nil)
    }
}
/// NEGATIVE CONTROL: pause silence counted as underrun.
public final class BuggyPauseUnderrunRing: SPSCRingModel {
    public override func read(frames: Int) -> (out: [UInt32], underrun: UInt64) {
        if paused { underrunFrames.fetchAdd(UInt64(frames)) }
        return super.read(frames: frames)
    }
}
/// NEGATIVE CONTROL: pause leaves underrun open (no close, so resume cannot re-arm cleanly).
public final class BuggyNoRearmRing: SPSCRingModel {
    @discardableResult public override func pauseAudio() -> Bool {
        if paused { return false }
        setPausedRaw(true); return true
    }
}

```

```text id=rf4
import RingModel
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct SplitMix64 {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
}

final class Tally { var pass = 0; var fail = 0
    func check(_ name: String, _ c: Bool, _ d: String = "") {
        if c { pass += 1 } else { fail += 1; print("FAIL \(name) \(d)") } } }

func runSequence<R: SPSCRingModel>(_ type: R.Type, seed: UInt64, nops: Int = 400, cap: Int = 64) -> [String] {
    var rng = SplitMix64(s: seed)
    let ring = R(capacityFrames: cap)
    var oracle: [UInt32] = []
    var gen: UInt64 = 0, paused = false, nextId: UInt32 = 1
    var v: [String] = []
    var offeredT: UInt64 = 0, admT: UInt64 = 0, dropT: UInt64 = 0, fenced: UInt64 = 0, sil: UInt64 = 0, under: UInt64 = 0
    var inUnder = false, expStarts = 0, expEnds = 0
    let ops = ["push", "push", "push", "read", "read", "reset", "pause", "resume", "stale"]
    for _ in 0..<nops {
        let op = ops[rng.range(0, ops.count - 1)]
        if op == "push" || op == "stale" {
            let n = rng.range(0, 40), tail = UInt64(rng.range(0, 3))
            let ids = (0..<n).map { nextId &+ UInt32($0) }; nextId &+= UInt32(n)
            var tag: UInt64? = nil
            if op == "stale" { if gen == 0 { continue }; tag = gen - UInt64(rng.range(1, Int(gen))) }
            let before = ring.events.count
            let rc = ring.push(ids, tailBytes: tail, generation: tag)
            if op == "stale" {
                if !rc.fenced || rc.admittedFrames != 0 { v.append("stale write admitted") }
                if !ring.events[before...].contains(where: { $0.kind == .staleFenced }) { v.append("no staleFenced event") }
                fenced += 1; continue
            }
            if paused { if rc.admittedFrames != 0 || !rc.pausedReject { v.append("push admitted while paused") }; continue }
            let adm = min(n, ring.cap > UInt64(oracle.count) ? Int(ring.cap) - oracle.count : 0)
            if rc.admittedFrames != UInt64(adm) || rc.droppedFrames != UInt64(n - adm) || rc.droppedTailBytes != tail { v.append("receipt mismatch") }
            if rc.admittedFrames + rc.droppedFrames != UInt64(n) { v.append("admitted+dropped != offered") }
            oracle.append(contentsOf: ids[0..<adm]); offeredT += UInt64(n); admT += UInt64(adm); dropT += UInt64(n - adm)
        } else if op == "read" {
            let n = rng.range(0, 48)
            let (out, short) = ring.read(frames: n)
            if paused {
                if out != [UInt32](repeating: 0, count: n) || short != 0 { v.append("pause not silent") }
                sil += UInt64(n)
            } else {
                let real = min(n, oracle.count)
                let exp = Array(oracle[0..<real]) + [UInt32](repeating: 0, count: n - real)
                oracle.removeFirst(real)
                if out != exp { v.append("read data mismatch (bleed/pop)") }
                if short != UInt64(n - real) { v.append("underrun count mismatch") }
                under += UInt64(n - real)
                if n - real > 0 && !inUnder { inUnder = true; expStarts += 1 }
                else if n - real == 0 && inUnder && n > 0 { inUnder = false; expEnds += 1 }
            }
        } else if op == "reset" {
            if inUnder { expEnds += 1; inUnder = false }
            ring.resetForNewGeneration(); gen += 1; oracle.removeAll()
            if ring.generation != gen { v.append("generation not bumped") }
            if ring.occupancy != 0 { v.append("ring not cleared on reset") }
        } else if op == "pause" {
            let r = ring.pauseAudio()
            if r == paused { v.append("pause typed result wrong") }
            if !paused { if inUnder { expEnds += 1; inUnder = false }; paused = true }
        } else if op == "resume" {
            let r = ring.resumeAudio()
            if r != paused { v.append("resume typed result wrong") }
            if paused { paused = false; inUnder = false }
        }
        if ring.occupancy != UInt64(oracle.count) { v.append("occupancy diverged") }
    }
    if ring.admittedFrames.load() != admT || ring.droppedFrames.load() != dropT { v.append("counter totals") }
    if ring.admittedFrames.load() + ring.droppedFrames.load() != offeredT { v.append("admitted+dropped != offered (total)") }
    if ring.silenceFrames.load() != sil { v.append("silence counter") }
    if ring.underrunFrames.load() != under { v.append("underrun frames counter (pause silence leaked?)") }
    if ring.fencedPushes.load() != fenced { v.append("fenced counter") }
    let starts = ring.events.filter { $0.kind == .underrunStart }.count
    let ends = ring.events.filter { $0.kind == .underrunEnd }.count
    if starts != expStarts || ends != expEnds { v.append("underrun events \(starts)/\(ends) vs \(expStarts)/\(expEnds)") }
    if starts - ends != (inUnder ? 1 : 0) { v.append("underrun start/end unpaired") }
    if ring.underrunEvents.load() != UInt64(starts) { v.append("underrunEvents != starts") }
    if ring.events.contains(where: { $0.generation > ring.generation }) { v.append("event generation from future") }
    let ts = ring.events.map { $0.tEvent }
    if ts != ts.sorted() { v.append("tEvent not monotonic") }
    return v
}

let t = Tally()
let seeds: [UInt64] = [42, 1, 7, 2026, 31337, 99991, 123456, 8675309]
print("ring-model-tests (swift model)")
print("seeds: " + seeds.map { String($0) }.joined(separator: " "))

do { // fixture1
    let r = SPSCRingModel(capacityFrames: 1024)
    let a = r.push((1...480).map { UInt32($0) }); r.resetForNewGeneration()
    let b = r.push((1...480).map { UInt32($0) }, generation: 0)
    let lastKind = r.events.last?.kind
    let (out, sh) = r.read(frames: 480)
    t.check("fixture1 push admitted 480", a.admittedFrames == 480 && a.droppedFrames == 0)
    t.check("fixture1 stale fenced", b.fenced && b.admittedFrames == 0 && lastKind == .staleFenced && RTEvent.Kind.staleFenced.rawValue == 3)
    t.check("fixture1 read silent after reset", out == [UInt32](repeating: 0, count: 480) && sh == 480)
}
do {
    let c = AdmissionCell(); c.payload = [1]
    t.check("cell enter", c.enter() && c.readers == 1); c.exit()
    t.check("cell retire zeroes payload", c.retire() == 0 && c.payload == nil && c.isRetired && !c.enter())
    let x = AtomicU64(5)
    t.check("atomic fetchAdd", x.fetchAdd(3) == 5 && x.load() == 8)
    t.check("atomic cas", x.compareExchange(expected: 8, desired: 1).exchanged && !x.compareExchange(expected: 8, desired: 2).exchanged && x.load() == 1)
    t.check("atomic wrap", AtomicU64(UInt64.max).fetchAdd(1) == UInt64.max)
}
for seed in seeds { for cap in [1, 7, 64] {
    let v = runSequence(SPSCRingModel.self, seed: seed &* 1000 &+ UInt64(cap), cap: cap)
    t.check("property seed=\(seed) cap=\(cap)", v.isEmpty, "\(v.prefix(3))")
} }
t.check("deterministic replay", runSequence(SPSCRingModel.self, seed: 42) == runSequence(SPSCRingModel.self, seed: 42))

func control<R: SPSCRingModel>(_ type: R.Type, _ name: String) {
    let caught = seeds.filter { !runSequence(type, seed: $0).isEmpty }
    let first = caught.first.flatMap { runSequence(type, seed: $0).first } ?? ""
    print("negative control \(name): caught on \(caught.count)/\(seeds.count) seeds; first violation: \(first)")
    t.check("negative control \(name) caught", !caught.isEmpty)
}
control(BuggyStaleAcceptRing.self, "BuggyStaleAcceptRing")
control(BuggyPauseUnderrunRing.self, "BuggyPauseUnderrunRing")
control(BuggyNoRearmRing.self, "BuggyNoRearmRing")
print("ring-model-tests: \(t.pass) PASS, \(t.fail) FAIL")
exit(t.fail == 0 ? 0 : 1)

```

```text id=rf7
"""Portable SPSC PCM ring model with seek generations (python3 stdlib only).
Single-threaded sequential model of push/reset/pause/resume/read semantics.
It models accounting and fencing only; no audio device, no threads, no
provider-quiescence claim. AdmissionCell is a LOCAL payload lifetime fence."""
from dataclasses import dataclass, field
from typing import Optional, List, Tuple

U64 = (1 << 64) - 1
BYTES_PER_FRAME = 4

UNDERRUN_START, UNDERRUN_END, STALE_FENCED = 1, 2, 3  # staleFenced == 3


class AtomicU64:
    def __init__(self, v=0): self._v = v & U64
    def load(self): return self._v
    def store(self, v): self._v = v & U64
    def fetchAdd(self, d):
        old = self._v; self._v = (old + d) & U64; return old
    def compareExchange(self, expected, desired):
        if self._v == expected:
            self._v = desired & U64; return True, expected
        return False, self._v


class AdmissionCell:
    """enter/exit/retire/readers/isRetired. enter() fails once retired."""
    def __init__(self): self._readers = AtomicU64(); self._retired = False; self.payload = None
    def enter(self):
        if self._retired: return False
        self._readers.fetchAdd(1); return True
    def exit(self):
        assert self._readers.load() > 0, "exit without enter"
        self._readers.fetchAdd(U64)  # -1 mod 2^64
    def retire(self):
        self._retired = True; self.payload = None  # payload zeroed BEFORE reuse/dispose
        return self._readers.load()
    @property
    def readers(self): return self._readers.load()
    @property
    def isRetired(self): return self._retired


@dataclass
class RTEvent:
    kind: int
    generation: int      # session generation AT POST TIME
    tEvent: float
    payload: Tuple[str, int]  # ("frames"|"bytes", n)


@dataclass
class Receipt:
    admittedFrames: int = 0
    droppedFrames: int = 0
    droppedTailBytes: int = 0
    fenced: bool = False
    pausedReject: bool = False


class SPSCRingModel:
    def __init__(self, capacity_frames: int):
        assert capacity_frames > 0
        self.cap = capacity_frames
        self.buf = [0] * capacity_frames  # one int per frame (frame id)
        self.w = AtomicU64(); self.r = AtomicU64()
        self.generation = 0
        self.paused = False
        self.events: List[RTEvent] = []
        self.clock = 0.0
        self.inUnderrun = False
        # cumulative counters (survive reset)
        self.admittedFrames = AtomicU64(); self.droppedFrames = AtomicU64()
        self.droppedTailBytes = AtomicU64(); self.fencedPushes = AtomicU64()
        self.underrunFrames = AtomicU64(); self.underrunEvents = AtomicU64()
        self.silenceFrames = AtomicU64()  # intentional pause silence, NOT underrun
        # per-generation counters (cleared by reset)
        self.genAdmitted = AtomicU64(); self.genUnderrun = AtomicU64()

    # --- helpers
    def _tick(self): self.clock += 1.0; return self.clock
    def _post(self, kind, n, tag="frames"):
        self.events.append(RTEvent(kind, self.generation, self._tick(), (tag, n)))
    def occupancy(self): return self.w.load() - self.r.load()

    # --- producer
    def push(self, frame_ids: List[int], tail_bytes: int = 0, generation: Optional[int] = None) -> Receipt:
        """frame_ids: whole frames offered; tail_bytes: trailing partial-frame bytes (dropped)."""
        assert 0 <= tail_bytes < BYTES_PER_FRAME
        tag = self.generation if generation is None else generation
        if tag != self.generation:  # fence: stale write never admitted
            self.fencedPushes.fetchAdd(1)
            self._post(STALE_FENCED, len(frame_ids))
            return Receipt(fenced=True)
        if self.paused:  # pushIfUnpaused: no admitted push once paused
            return Receipt(pausedReject=True)
        offered = len(frame_ids)
        free = self.cap - self.occupancy()
        admit = min(offered, free); drop = offered - admit
        wi = self.w.load()
        for i in range(admit): self.buf[(wi + i) % self.cap] = frame_ids[i]
        self.w.store(wi + admit)
        if admit: self.admittedFrames.fetchAdd(admit); self.genAdmitted.fetchAdd(admit)
        if drop: self.droppedFrames.fetchAdd(drop)
        if tail_bytes: self.droppedTailBytes.fetchAdd(tail_bytes)
        return Receipt(admit, drop, tail_bytes)

    def resetForNewGeneration(self):
        """Bump generation, clear ring and per-generation state. An open underrun
        is closed under the OLD generation so start/end stay paired."""
        if self.inUnderrun:
            self._post(UNDERRUN_END, 0); self.inUnderrun = False
        self.generation += 1
        self.r.store(self.w.load())  # discard residual
        self.genAdmitted.store(0); self.genUnderrun.store(0)

    # --- consumer
    def read(self, frames: int) -> Tuple[List[int], int]:
        """Returns (frames out, underrun frames). Paused: intentional silence."""
        if self.paused:
            self.silenceFrames.fetchAdd(frames)
            return [0] * frames, 0
        ri, wi = self.r.load(), self.w.load()
        real = min(wi - ri, frames)
        out = [self.buf[(ri + i) % self.cap] for i in range(real)] + [0] * (frames - real)
        self.r.store(ri + real)
        short = frames - real
        if short > 0:
            self.underrunFrames.fetchAdd(short); self.genUnderrun.fetchAdd(short)
            if not self.inUnderrun:
                self.inUnderrun = True; self.underrunEvents.fetchAdd(1)
                self._post(UNDERRUN_START, short)
        elif self.inUnderrun and frames > 0:
            self.inUnderrun = False; self._post(UNDERRUN_END, 0)
        return out, short

    # --- pause contract
    def pauseAudio(self) -> bool:
        if self.paused: return False
        if self.inUnderrun:  # close open underrun at the edge
            self._post(UNDERRUN_END, 0); self.inUnderrun = False
        self.paused = True  # residual HELD, not consumed
        return True

    def resumeAudio(self) -> bool:
        if not self.paused: return False
        self.paused = False
        self.inUnderrun = False  # re-arm: next shortfall emits a fresh underrunStart
        return True


class BuggyStaleAcceptRing(SPSCRingModel):
    """NEGATIVE CONTROL: accepts stale-generation writes (fence removed)."""
    def push(self, frame_ids, tail_bytes=0, generation=None):
        return super().push(frame_ids, tail_bytes, None)


class BuggyPauseUnderrunRing(SPSCRingModel):
    """NEGATIVE CONTROL: pause silence counted as underrun."""
    def read(self, frames):
        if self.paused:
            self.underrunFrames.fetchAdd(frames)
        return super().read(frames)


class BuggyNoRearmRing(SPSCRingModel):
    """NEGATIVE CONTROL: resume does not re-arm underrun edge detector."""
    def pauseAudio(self):
        if self.paused: return False
        self.paused = True; return True  # leaves inUnderrun open

```

```text id=rf8
"""Property tests + negative controls. python3 stdlib only."""
import random, sys
from collections import deque
from ring_model import *

SEEDS = [42, 1, 7, 2026, 31337, 99991, 123456, 8675309]
passed = failed = 0

def check(name, cond, detail=""):
    global passed, failed
    if cond: passed += 1
    else:
        failed += 1; print(f"FAIL {name} {detail}")

def run_sequence(ring_cls, seed, nops=400, cap=64, fail_fast=False):
    """Random ops against an independent oracle. Returns list of violation strings."""
    rng = random.Random(seed); ring = ring_cls(cap)
    oracle = deque(); gen = 0; paused = False
    next_id = 1; v = []
    offered_total = adm_total = drop_total = fenced = sil = under = 0
    in_under = False; exp_starts = exp_ends = 0
    old_gens = [] ; stale_seen = 0
    for _ in range(nops):
        op = rng.choice(["push", "push", "push", "read", "read", "reset", "pause", "resume", "stale"])
        if op in ("push", "stale"):
            n = rng.randint(0, 40); tail = rng.randint(0, 3)
            ids = list(range(next_id, next_id + n)); next_id += n
            tag = None
            if op == "stale":
                if gen == 0: continue
                tag = gen - rng.randint(1, gen)
            before = len(ring.events)
            rc = ring.push(ids, tail, tag)
            if op == "stale":
                if not rc.fenced or rc.admittedFrames != 0: v.append("stale write admitted")
                if not any(e.kind == STALE_FENCED for e in ring.events[before:]): v.append("no staleFenced event")
                stale_seen += 1; fenced += 1
                # stale data must never show up: oracle untouched
                continue
            if paused:
                if rc.admittedFrames or not rc.pausedReject: v.append("push admitted while paused")
                continue
            free = cap - len(oracle); adm = min(n, free)
            if (rc.admittedFrames, rc.droppedFrames, rc.droppedTailBytes) != (adm, n - adm, tail):
                v.append(f"receipt {rc} vs adm={adm}")
            if rc.admittedFrames + rc.droppedFrames != n: v.append("admitted+dropped != offered")
            oracle.extend(ids[:adm]); offered_total += n; adm_total += adm; drop_total += n - adm
        elif op == "read":
            n = rng.randint(0, 48)
            out, short = ring.read(n)
            if paused:
                if out != [0] * n or short != 0: v.append("pause not silent")
                sil += n
            else:
                real = min(n, len(oracle))
                exp = [oracle.popleft() for _ in range(real)] + [0] * (n - real)
                if out != exp: v.append("read data mismatch (bleed/pop)")
                if short != n - real: v.append("underrun count mismatch")
                under += n - real
                if n - real > 0 and not in_under: in_under = True; exp_starts += 1
                elif n - real == 0 and in_under and n > 0: in_under = False; exp_ends += 1
        elif op == "reset":
            if in_under: exp_ends += 1; in_under = False
            ring.resetForNewGeneration(); gen += 1; oracle.clear()
            if ring.generation != gen: v.append("generation not bumped")
            if ring.occupancy() != 0: v.append("ring not cleared on reset")
        elif op == "pause":
            r = ring.pauseAudio()
            if r == paused: v.append("pause typed result wrong")
            if not paused:
                if in_under: exp_ends += 1; in_under = False
                paused = True
        elif op == "resume":
            r = ring.resumeAudio()
            if r != paused: v.append("resume typed result wrong")
            if paused: paused = False; in_under = False
        if ring.occupancy() != len(oracle): v.append("occupancy diverged")
        if ring.occupancy() > cap: v.append("overfull")
    # global invariants
    if ring.admittedFrames.load() != adm_total or ring.droppedFrames.load() != drop_total: v.append("counter totals")
    if ring.admittedFrames.load() + ring.droppedFrames.load() != offered_total: v.append("admitted+dropped != offered (total)")
    if ring.silenceFrames.load() != sil: v.append("silence counter")
    if ring.underrunFrames.load() != under: v.append("underrun frames counter (pause silence leaked?)")
    if ring.fencedPushes.load() != fenced: v.append("fenced counter")
    starts = [e for e in ring.events if e.kind == UNDERRUN_START]
    ends = [e for e in ring.events if e.kind == UNDERRUN_END]
    if len(starts) != exp_starts or len(ends) != exp_ends: v.append(f"underrun events {len(starts)}/{len(ends)} vs {exp_starts}/{exp_ends}")
    if len(starts) - len(ends) != (1 if in_under else 0): v.append("underrun start/end unpaired")
    if ring.underrunEvents.load() != len(starts): v.append("underrunEvents != starts")
    if any(e.generation > ring.generation for e in ring.events): v.append("event generation from future")
    ts = [e.tEvent for e in ring.events]
    if ts != sorted(ts): v.append("tEvent not monotonic")
    return v

def main():
    print("ring-model-tests (python3 model, Linux)")
    print("seeds:", " ".join(map(str, SEEDS)))
    # fixture1
    r = SPSCRingModel(1024)
    a = r.push(list(range(1, 481))); r.resetForNewGeneration()
    b = r.push(list(range(1, 481)), 0, 0); last_kind = r.events[-1].kind; out, sh = r.read(480)
    check("fixture1 push admitted 480", (a.admittedFrames, a.droppedFrames) == (480, 0))
    check("fixture1 stale fenced", b.fenced and b.admittedFrames == 0 and last_kind == STALE_FENCED == 3)
    check("fixture1 read silent after reset", out == [0] * 480 and sh == 480)
    # AdmissionCell
    c = AdmissionCell(); c.payload = b"x"
    check("cell enter", c.enter() and c.readers == 1); c.exit()
    check("cell retire zeroes payload", c.retire() == 0 and c.payload is None and c.isRetired and not c.enter())
    # AtomicU64
    x = AtomicU64(5)
    check("atomic fetchAdd", x.fetchAdd(3) == 5 and x.load() == 8)
    check("atomic cas", x.compareExchange(8, 1)[0] and not x.compareExchange(8, 2)[0] and x.load() == 1)
    check("atomic wrap", AtomicU64(U64).fetchAdd(1) == U64)
    # properties
    for seed in SEEDS:
        for cap in (1, 7, 64):
            v = run_sequence(SPSCRingModel, seed * 1000 + cap, 400, cap)
            check(f"property seed={seed} cap={cap}", not v, str(v[:3]))
    # determinism
    check("deterministic replay", run_sequence(SPSCRingModel, 42) == run_sequence(SPSCRingModel, 42) == [])
    # negative controls: each buggy ring must be caught on at least one seed
    for cls, needle in ((BuggyStaleAcceptRing, "stale"), (BuggyPauseUnderrunRing, "underrun frames counter"), (BuggyNoRearmRing, "underrun")):
        caught = [s for s in SEEDS if run_sequence(cls, s, 400, 64)]
        sample = run_sequence(cls, caught[0], 400, 64)[0] if caught else ""
        print(f"negative control {cls.__name__}: caught on {len(caught)}/{len(SEEDS)} seeds; first violation: {sample}")
        check(f"negative control {cls.__name__} caught", len(caught) > 0)
    print(f"ring-model-tests: {passed} PASS, {failed} FAIL")
    return 1 if failed else 0

if __name__ == "__main__": sys.exit(main())

```

```text id=actual_run_log
Building for debugging...
[0/7] Write sources
[2/7] Write swift-version--9C6B84B6E025C5B.txt
[4/9] Emitting module RingModel
[5/9] Compiling RingModel RingModel.swift
[6/10] Wrapping AST for RingModel for debugging
[8/12] Emitting module ring_model_tests
[9/12] Compiling ring_model_tests main.swift
[10/13] Wrapping AST for ring-model-tests for debugging
[11/13] Write Objects.LinkFileList
[12/13] Linking ring-model-tests
Build complete! (1.93s)
ring-model-tests (swift model)
seeds: 42 1 7 2026 31337 99991 123456 8675309
negative control BuggyStaleAcceptRing: caught on 8/8 seeds; first violation: stale write admitted
negative control BuggyPauseUnderrunRing: caught on 8/8 seeds; first violation: underrun frames counter (pause silence leaked?)
negative control BuggyNoRearmRing: caught on 8/8 seeds; first violation: underrun events 19/14 vs 19/19
ring-model-tests: 36 PASS, 0 FAIL
```
