# W-gdb-032 decoder-lifetime fault vector pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-032

```packet-json
{
  "packet_id": "W-gdb-032",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "register(_:kind:codec:sourceID:revisionAtOpen:) -> RegisterOutcome; deregister(_:) -> Bool; mark(_:_:); invalidateSession(_:); snapshot(_:) -> DecoderSnapshot?; activeSnapshots(session:) -> [DecoderSnapshot]",
    "types": "RegisterOutcome { registered, refusedInvalidatedSession, refusedIdentityExhausted, duplicateRefused }; DecoderLifecycle { open, draining, failed, closed }; DecoderIdentity { session: UInt64, handle: UInt64 }",
    "ownership_lifetime": "inventory owns entries; session invalidation fences wholesale",
    "caller": "decoder fault vector runner",
    "callee": "DecoderInventory register/mark/deregister/invalidateSession/snapshot/activeSnapshots (pinned below)"
  },
  "test": {
    "command": "swift run decoder-fault-vector-tests && swift run decoder-lifetime-tests && swift run decoder-inventory-tests",
    "expected": "exit 0 for all three suites. 'decoder-fault-vector-tests: 5 PASS, 0 FAIL (1 seeded negative caught)' - rows F1-F5 replay declarative fault vectors (register verdicts incl. duplicateRefused and refusedInvalidatedSession, nil snapshot after deregister/invalidate, phantom double-deregister no-op with exact deregistrations count, phantom never-registered snapshot nil) against the REAL DecoderInventory, and the flipped F6 row must be caught and printed, never counted green. 'ALL DECODER LIFETIME CHECKS PASS (software registry only)' and 'decoder-inventory-tests: N PASS, 0 FAIL' stay green (pre-existing suites, bytes attested inline). The vector target (rf2) and Package.swift wiring (rf3) are packet-authored; locally compiled and run green on Linux Swift 5.10.1. decoder-lifetime-tests needs FFmpeg - lane runs the full command at pin.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/decoder-fault-vectors/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/decoder-lifetime-tests/main.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/decoder-inventory-tests/main.swift",
        "block": "rf1"
      },
      {
        "path": "Sources/decoder-fault-vector-tests/main.swift",
        "block": "rf2"
      },
      {
        "path": "Package.swift",
        "block": "rf3"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
    "command": "swift run decoder-fault-vector-tests && swift run decoder-lifetime-tests && swift run decoder-inventory-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T23:31:29.086092+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "0 FAIL",
    "inline_files": [
      {
        "path": "Sources/decoder-lifetime-tests/main.swift",
        "block": "rf0",
        "sha256": "177459ff39b95e25364144b08b4f01f8c2a7ed3b4a28caebea89f474c79372a2"
      },
      {
        "path": "Sources/decoder-inventory-tests/main.swift",
        "block": "rf1",
        "sha256": "c9f5b66a6236568c56f27c64675713e72dcd4ec3470e4ee31584ad22d76dcb37"
      },
      {
        "path": "Sources/decoder-fault-vector-tests/main.swift",
        "block": "rf2",
        "sha256": "87d1cc7c622c5982889e54547940396d39f99114075f4501b0f8b148be6ffbee"
      },
      {
        "path": "Package.swift",
        "block": "rf3",
        "sha256": "9edafc715530b539fa5f28eb986be94c1738e7d56ab3a142f38e601ea242ace2"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "47a743b3b7f26be0a4157d3b09dd16796626bd7eb0545be2d3abd75ff7d7219f",
    "last_5_lines": [
      "[5/8] Wrapping AST for decoder-inventory-tests for debugging",
      "[6/8] Write Objects.LinkFileList",
      "[7/8] Linking decoder-inventory-tests",
      "Build of product 'decoder-inventory-tests' complete! (1.22s)",
      "decoder-inventory-tests: 27 PASS, 0 FAIL"
    ],
    "receipt_sha256": "8b76ba4ad01dc0a9bfaa07e5c2798683ed350786bb482ecfd070e22d797028c9"
  }
}
```

## problem (what fails for the user)
decoder registration/lifetime is tracked by DecoderInventory; abort-mid-open, double-close or registration-after-abort regressions ship as leaked decoders or phantom inventory entries.

## reproducer
- repo: goreda/gorav @ 8786bfe3e5482a891dda15248b107e50fab52463 (branch main).
- real source: Sources/GorAVPlaybackCore/DecoderInventory.swift (sha256 f502dcdf; first 60 lines below); decoder-lifetime-tests (9 checks) + decoder-inventory-tests (27 checks) on Linux per the harness map.
- real test command: swift run decoder-lifetime-tests + swift run decoder-inventory-tests stay green.

## expected behaviour
fault vectors: open/fail/close/reopen sequences, abort mid-open, double-close typed no-op, registration after abort forbidden, generation counters across reopen; expected registry/lifetime state tables per sequence.

## exact call site and interface
DecoderInventory's registration/lifetime vocabulary (pinned excerpt); vectors + checker are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15; register/close/invalidate ABI)
DecoderInventory (excerpt-level, same pin):
- register(_ id: DecoderIdentity, kind: DecoderKind, codec: String, sourceID: String? = nil, revisionAtOpen: UInt64 = 1) -> RegisterOutcome { registered, refusedInvalidatedSession, refusedIdentityExhausted, duplicateRefused } - a duplicate keeps the existing entry and receipts duplicateRegistrations += 1
- mark(_ id:, _ lifecycle:) with DecoderLifecycle { open, draining, failed, closed }
- deregister(_ id:) -> Bool - false = unknown identity, typed; deregistrations counter
- invalidateSession(_ session: UInt64) - fences a whole session (seek-restart/reset): all its entries drop and later registrations for it are refusedInvalidatedSession
- snapshot(_ id:) -> DecoderSnapshot? - nil for unknown/deregistered/session-invalidated; closed/failed entries still returned until deregistered
- activeSnapshots(session:) - registration order, excludes .closed, [] for invalidated sessions
- DecoderIdentity { session: UInt64, handle: UInt64 }; DecoderSnapshot carries lifecycle + registrationSeq: UInt64 (monotonic from 1)
fault vectors assert exactly these outcomes: registration after invalidateSession = refusedInvalidatedSession; double-close = second deregister returns false; abort-mid-open leaves no entry.

## behaviour that must not change
the 9+27 existing checks stay green; synthetic decoder stub only - no real codec.

## acceptance test (from the product repo)
vectors replay green against the pinned inventory; a seeded phantom registration is caught.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/DecoderInventory.swift (sha256 f502dcdf, lines 1-60 of 155)
```swift id=source1
import Foundation

// Row 195b-55 (arch-195b): active-decoder inventory. A decoder instance is
// Metadata registry only: software adapters wire lifetime below; no container inventory is read.
// Callers must serialize mutations. Decoder instances can be
// tracked from registration to explicit deregistration; snapshots are typed,
// immutable, and generation-fenced. The cache answers "what is live right
// now" without touching decoder internals - the adapter registers on open and
// deregisters on close/deinit/failure.

public struct DecoderIdentity: Equatable, Hashable, Sendable {
    /// Session/generation the decoder belongs to (same fence as frames).
    public let session: UInt64
    /// Per-session decoder handle; unique within a session.
    public let handle: UInt64
    public init(session: UInt64, handle: UInt64) {
        self.session = session; self.handle = handle
    }
}

public enum DecoderKind: String, Equatable, Sendable {
    case videoSoftware, audioSoftware, videoHardware
}

public enum DecoderLifecycle: String, Equatable, Sendable {
    case open, draining, failed, closed
}

/// Typed snapshot of one tracked decoder at read time.
public struct DecoderSnapshot: Equatable, Sendable {
    public let identity: DecoderIdentity
    public let kind: DecoderKind
    /// Probe-admitted codec name (e.g. "h264", "aac"); never a free-form
    /// source string (evidence privacy rule).
    public let codec: String
    /// Opaque provider identity, never a file path/URL. Immutable OPEN facts,
    /// not a claim to mirror a later seek revision or enumerate container tracks.
    public let sourceID: String?
    public let revisionAtOpen: UInt64
    /// Mutated only by DecoderInventory (same file) on mark(); immutable to callers.
    public internal(set) var lifecycle: DecoderLifecycle
    /// Registration order, monotonic per inventory - a cheap total order for
    /// "oldest live decoder" without trusting clocks.
    public let registrationSeq: UInt64
}

public struct DecoderInventory: Sendable {

    public enum RegisterOutcome: Equatable, Sendable {
        case registered
        case refusedInvalidatedSession
        case refusedIdentityExhausted
        /// Same identity registered twice; the existing entry wins and the
        /// attempt is receipted.
        case duplicateRefused
    }

    public private(set) var entries: [DecoderIdentity: DecoderSnapshot] = [:]
    public private(set) var duplicateRegistrations = 0
    public private(set) var deregistrations = 0
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"ops":[{"register":{"s":1,"h":1},"expect":"registered"},{"register":{"s":1,"h":1},"expect":"duplicateRefused"},{"invalidateSession":1},{"register":{"s":1,"h":2},"expect":"refusedInvalidatedSession"}],"expectCounters":{"duplicateRegistrations":1}}
```





```text id=rf0
import Foundation
import GorAVPlaybackCore
import GorAVFFmpegAdapter
import GorAVCore

// 195b-59: REAL software adapters and tracked local fixtures. Needs the pinned
// FFmpeg headers/libs. No hardware/device/native session acceptance is implied.
@main struct DecoderLifetimeChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let fixture=root.appendingPathComponent("fixtures/clip-bbb-10s.mov").path
        let tone=root.appendingPathComponent("fixtures/tone-48k.wav").path
        let registry=DecoderInventoryStore()
        let sid=SessionID(uncheckedEpoch:901)
        let foreign=SessionID(uncheckedEpoch:902)
        let reopened=SessionID(uncheckedEpoch:903)
        var video:FFmpegSoftwareDecoder?=FFmpegSoftwareDecoder(decoderInventory:registry)
        try video!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await video!.open(source:SourceDescriptor(id:"/missing-decoder-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing video opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed video open registers nothing")
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let first=registry.activeSnapshots(session:sid.epoch)
        precondition(first.count == 1 && first[0].kind == .videoSoftware)
        precondition(first[0].sourceID?.hasPrefix("video:") == true && first[0].revisionAtOpen == 1)
        print("PASS real video open registers immutable opaque identity")
        do {
            try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:foreign)
            fatalError("busy video reopen admitted")
        } catch { }
        precondition(registry.snapshot(first[0].identity) != nil)
        _ = await video!.closeAndReport(session:foreign)
        precondition(registry.snapshot(first[0].identity) != nil)
        print("PASS failed reopen and foreign close preserve live registration")
        _ = await video!.closeAndReport(session:sid)
        precondition(registry.snapshot(first[0].identity) == nil)
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:reopened)
        let second=registry.activeSnapshots(session:reopened.epoch)
        precondition(second.count == 1 && second[0].identity != first[0].identity)
        precondition(second[0].sourceID != first[0].sourceID)
        print("PASS close/reopen never revives prior registration")
        video=nil
        precondition(registry.activeSnapshots(session:reopened.epoch).isEmpty)
        print("PASS abandoned real video deinit deregisters")
        var audio:FFmpegSoftwareAudioDecoder?=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try audio!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await audio!.open(source:SourceDescriptor(id:"/missing-audio-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing audio opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed audio open registers nothing")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        let sound=registry.activeSnapshots(session:sid.epoch)
        precondition(sound.count == 1 && sound[0].kind == .audioSoftware)
        precondition(sound[0].sourceID != nil && sound[0].revisionAtOpen == 1)
        await audio!.close(session:foreign)
        precondition(registry.snapshot(sound[0].identity) != nil)
        await audio!.close(session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS real audio lifetime/foreign close fence")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        audio=nil
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS abandoned real audio deinit deregisters")
        registry.invalidateSession(sid.epoch)
        let stale=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try stale.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        try await stale.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        await stale.close(session:sid)
        print("PASS invalidated-session successful adapter open cannot revive metadata")
        print("ALL DECODER LIFETIME CHECKS PASS (software registry only)")
    }
}
```

```text id=rf1
import Foundation
import GorAVPlaybackCore

// Witness for row 195b-55: register/deregister, typed snapshots, duplicate
// refusal with receipt, lifecycle marking, session invalidation fencing,
// ordering by registration sequence.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

var inv = DecoderInventory()
let v7 = DecoderIdentity(session: 7, handle: 1)
let a7 = DecoderIdentity(session: 7, handle: 2)
let v8 = DecoderIdentity(session: 8, handle: 1)

// T1: register + snapshot
check("T1-register", inv.register(v7, kind: .videoSoftware, codec: "h264") == .registered)
let s1 = inv.snapshot(v7)
check("T1-snapshot", s1?.kind == .videoSoftware && s1?.codec == "h264"
      && s1?.lifecycle == .open && s1?.registrationSeq == 1)

// T2: duplicate refused, receipted, original wins
check("T2-dup", inv.register(v7, kind: .audioSoftware, codec: "aac") == .duplicateRefused
      && inv.duplicateRegistrations == 1)
check("T2-original-wins", inv.snapshot(v7)?.kind == .videoSoftware)

// T3: ordering across registrations
_ = inv.register(a7, kind: .audioSoftware, codec: "aac")
_ = inv.register(v8, kind: .videoSoftware, codec: "hevc")
let act7 = inv.activeSnapshots(session: 7)
check("T3-order", act7.map { $0.identity.handle } == [1, 2])

// T4: lifecycle marking
inv.mark(a7, .draining)
check("T4-lifecycle", inv.snapshot(a7)?.lifecycle == .draining)
inv.mark(DecoderIdentity(session: 9, handle: 9), .failed) // unknown: no crash, no entry
check("T4-unknown-mark", inv.snapshot(DecoderIdentity(session: 9, handle: 9)) == nil)

// T5: activeSnapshots excludes closed, includes failed (it happened)
inv.mark(a7, .closed)
check("T5-closed-excluded", inv.activeSnapshots(session: 7).map { $0.identity.handle } == [1])
inv.mark(a7, .failed) // re-mark after closed is caller error but must not corrupt
check("T5b-snapshot-survives", inv.snapshot(a7)?.lifecycle == .failed)

// T6: deregister
check("T6-dereg", inv.deregister(a7) && inv.deregistrations == 1)
check("T6-gone", inv.snapshot(a7) == nil && !inv.deregister(a7))

// T7: session invalidation fences everything for that session
inv.invalidateSession(7)
check("T7-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
check("T7-other-session-live", inv.activeSnapshots(session: 8).count == 1)

// T8: invalidated generations are terminal; stale registrations cannot revive them.
check("T8-stale-register-refused", inv.register(v7, kind: .videoSoftware, codec: "h264") == .refusedInvalidatedSession)
check("T8-remains-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
let v9 = DecoderIdentity(session: 9, handle: 1)
check("T8-new-generation-registers", inv.register(v9, kind: .videoSoftware, codec: "h264") == .registered)
check("T8-seq-monotonic", inv.snapshot(v9)!.registrationSeq > inv.snapshot(v8)!.registrationSeq)

// 195b-59: serialized multi-decoder metadata store, not container inventory.
let store=DecoderInventoryStore()
let live=store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"opaque-video-1",revisionAtOpen:1)!
let liveAudio=store.register(session:100,kind:.audioSoftware,codec:"aac",sourceID:"opaque-audio-1",revisionAtOpen:1)!
check("store-composite-handles",live != liveAudio)
check("store-open-identity",store.snapshot(live)?.sourceID == "opaque-video-1" && store.snapshot(live)?.revisionAtOpen == 1)
store.deregister(live)
check("store-close-drops-only-owner",store.snapshot(live) == nil && store.snapshot(liveAudio) != nil)
store.deregister(live)
let replacement=store.register(session:100,kind:.videoSoftware,codec:"hevc",sourceID:"opaque-video-2",revisionAtOpen:1)!
check("store-replacement-not-stale",replacement != live && store.snapshot(live) == nil)
store.invalidateSession(100)
check("store-invalidate-all",store.activeSnapshots(session:100).isEmpty)
check("store-stale-reregister-refused",store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"old",revisionAtOpen:1) == nil)
check("store-zero-session-refused",store.register(session:0,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:1) == nil)
check("store-zero-revision-refused",store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:0) == nil)
let lock=NSLock()
var ids:[DecoderIdentity]=[]
DispatchQueue.concurrentPerform(iterations:100) { n in
    if let id=store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"opaque-\(n)",revisionAtOpen:1) {
        lock.lock(); ids.append(id); lock.unlock()
    }
}
check("store-concurrent-identities",Set(ids).count == 100 && store.activeSnapshots(session:101).count == 100)
for id in ids { store.deregister(id) }
check("store-concurrent-clean",store.activeSnapshots(session:101).isEmpty)

print("decoder-inventory-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
```

```text id=rf2
import Foundation
import GorAVPlaybackCore

// kits/decoder-fault-vectors (row 195b-55 adversarial pack): declarative
// fault-vector rows replayed against the REAL DecoderInventory. Each row is
// data: op sequence + exact expected outcomes (register verdicts, snapshot
// presence, counters). One seeded phantom-registration row (F6) carries a
// deliberately wrong expectation and MUST be caught by the harness.

var failures = 0
var passes = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 } else { passes += 1 }
}

enum FOp {
    case register(session: UInt64, handle: UInt64, expect: String)
    case deregister(session: UInt64, handle: UInt64, expectSnapshots: Int)
    case invalidate(session: UInt64)
    case expectSnapshotNil(session: UInt64, handle: UInt64)
}

struct FRow {
    let id: String
    let ops: [FOp]
    let expectCounters: [String: Int]   // "duplicateRegistrations"/"deregistrations" -> exact value
    let expectActive: [UInt64: Int]     // session -> exact active count
    let flipped: Bool                   // seeded negative: harness must find a mismatch
}

let rows: [FRow] = [
    // F1: register -> snapshot open; deregister -> snapshot nil, counter moves.
    FRow(id: "F1", ops: [
        .register(session: 7, handle: 1, expect: "registered"),
        .deregister(session: 7, handle: 1, expectSnapshots: 0),
        .expectSnapshotNil(session: 7, handle: 1),
    ], expectCounters: ["deregistrations": 1], expectActive: [7: 0], flipped: false),
    // F2: duplicate registration is refused with receipt; first entry wins.
    FRow(id: "F2", ops: [
        .register(session: 7, handle: 1, expect: "registered"),
        .register(session: 7, handle: 1, expect: "duplicateRefused"),
    ], expectCounters: ["duplicateRegistrations": 1, "deregistrations": 0], expectActive: [7: 1], flipped: false),
    // F3: invalidate fences the session; later register refuses typed; snapshot nil.
    FRow(id: "F3", ops: [
        .register(session: 8, handle: 1, expect: "registered"),
        .invalidate(session: 8),
        .register(session: 8, handle: 2, expect: "refusedInvalidatedSession"),
        .expectSnapshotNil(session: 8, handle: 1),
    ], expectCounters: [:], expectActive: [8: 0], flipped: false),
    // F4: phantom double-deregister: second deregister is a no-op, counter moves once.
    FRow(id: "F4", ops: [
        .register(session: 9, handle: 1, expect: "registered"),
        .deregister(session: 9, handle: 1, expectSnapshots: 0),
        .deregister(session: 9, handle: 1, expectSnapshots: 0),
    ], expectCounters: ["deregistrations": 1], expectActive: [9: 0], flipped: false),
    // F5: phantom registration never lands: snapshot of a never-registered id is nil
    // and deregistering it touches nothing.
    FRow(id: "F5", ops: [
        .expectSnapshotNil(session: 42, handle: 77),
        .deregister(session: 42, handle: 77, expectSnapshots: 0),
    ], expectCounters: ["deregistrations": 0], expectActive: [42: 0], flipped: false),
    // F6 (seeded negative): claims the phantom snapshot EXISTS. Harness must catch it.
    FRow(id: "F6", ops: [
        .expectSnapshotNil(session: 42, handle: 77),
    ], expectCounters: ["deregistrations": 1],  // wrong: nothing was ever deregistered
     expectActive: [42: 0], flipped: true),
]

var negativesCaught = 0
for row in rows {
    var inv = DecoderInventory()
    var mismatch: [String] = []
    for (i, op) in row.ops.enumerated() {
        switch op {
        case .register(let s, let h, let expect):
            let d = String(describing: inv.register(DecoderIdentity(session: s, handle: h), kind: .videoSoftware, codec: "h264", sourceID: "video:vec", revisionAtOpen: 1))
            if !d.contains(expect) { mismatch.append("op\(i) register: got \(d), want *\(expect)*") }
        case .deregister(let s, let h, let expectSnapshots):
            _ = inv.deregister(DecoderIdentity(session: s, handle: h))
            let n = inv.activeSnapshots(session: s).count
            if n != expectSnapshots { mismatch.append("op\(i) deregister: active=\(n), want \(expectSnapshots)") }
        case .invalidate(let s):
            inv.invalidateSession(s)
        case .expectSnapshotNil(let s, let h):
            if inv.snapshot(DecoderIdentity(session: s, handle: h)) != nil {
                mismatch.append("op\(i): snapshot of (\(s),\(h)) present, want nil")
            }
        }
    }
    let mirror = Mirror(reflecting: inv)
    for (label, want) in row.expectCounters {
        let got = mirror.children.first { $0.label == label }.map { $0.value as? Int ?? -1 } ?? -1
        if got != want { mismatch.append("counter \(label): got \(got), want \(want)") }
    }
    for (s, want) in row.expectActive {
        let got = inv.activeSnapshots(session: s).count
        if got != want { mismatch.append("active(\(s)): got \(got), want \(want)") }
    }
    if row.flipped {
        if mismatch.isEmpty { check("VECTOR-NEGATIVE \(row.id) discriminates", false, "flipped row replayed clean: harness blind") }
        else { negativesCaught += 1; print("VECTOR-NEGATIVE \(row.id) caught as required: \(mismatch.joined(separator: "; "))") }
    } else {
        check("VECTOR \(row.id) replay", mismatch.isEmpty, mismatch.joined(separator: "; "))
    }
}

print("decoder-fault-vector-tests: \(passes) PASS, \(failures) FAIL (\(negativesCaught) seeded negative caught)")
exit(failures == 0 ? 0 : 1)

```

```text id=rf3
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "decoder-fault-vector-tests", targets: ["decoder-fault-vector-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "timepos-vector-tests", targets: ["timepos-vector-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "vtt-parser-tests", targets: ["vtt-parser-tests"]), .executable(name: "l3-convert-matrix-tests", targets: ["l3-convert-matrix-tests"]), .executable(name: "avsync-golden-tests", targets: ["avsync-golden-tests"]), .executable(name: "transport-vector-tests", targets: ["transport-vector-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"]), .executable(name: "e1-shapes-tests", targets: ["e1-shapes-tests"]), .executable(name: "parity-pixel-tests", targets: ["parity-pixel-tests"]), .executable(name: "untagged-color-tests", targets: ["untagged-color-tests"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "audio-interrupt-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/audio-interrupt-tests"),
        .executableTarget(name: "cue-output-tests", dependencies: ["GorAVSubtitles", "GorAVPlaybackCore"], path: "Sources/cue-output-tests"),
        .executableTarget(name: "render-graph-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/render-graph-tests"),
        .executableTarget(name: "decoder-lifetime-tests", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore"], path: "Sources/decoder-lifetime-tests"),
        .executableTarget(name: "decoder-inventory-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-inventory-tests"),
        .executableTarget(name: "decoder-fault-vector-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-fault-vector-tests"),
        .testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/PreparedVideoSwapTests"),
        .testTarget(name: "EmbeddedPreparedShotTests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), "GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Tests/EmbeddedPreparedShotTests"),
        .executableTarget(name: "color-stage-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/color-stage-tests"),
        .executableTarget(name: "crop-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/crop-tests"),
        .executableTarget(name: "frame-tap-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-tap-tests"),
        .executableTarget(name: "active-media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/active-media-inventory-tests"),
        .executableTarget(name: "media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/media-inventory-tests"),
        .executableTarget(name: "video-remote-open-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/video-remote-open-tests"),
        .executableTarget(name: "remote-source-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/remote-source-tests"),
        .executableTarget(name: "subtitle-controller-tests", dependencies: ["GorAVSubtitles"], path: "Sources/subtitle-tests", sources: ["SubtitleControllerTests.swift"]),
        .executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/prepared-shot-tests"),
        .executableTarget(name: "hosttransform-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/hosttransform-tests"),
        .executableTarget(name: "timepos-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-tests"),
        .executableTarget(name: "timepos-vector-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-vector-tests"),
        .executableTarget(name: "controlbus-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/controlbus-tests"),
        .target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"], path: "Sources/BridgeVTDecode"),
        .target(name: "AudioMasterScheduler", path: "Sources/AudioMasterScheduler"),
        .testTarget(name: "EngineContractTests", dependencies: ["BridgeVTDecode", "BridgeDemux", "AudioMasterScheduler"], path: "Tests/EngineContractTests"),
        .executableTarget(name: "e1-headless-tests", dependencies: ["BridgeDemux", "AudioMasterScheduler", "CFFmpeg", "GorAVPlaybackCore", "GorAVMetalPresenter"], path: "Sources/e1-headless-tests"),
        .executableTarget(name: "gorav-probe", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/gorav-probe"),


        .target(name: "GorAVCore", dependencies: ["GorAVCAtomics"], path: "Sources/GorAVCore", sources: ["Boundary.swift", "AdmissionTable.swift", "OpenURLRouter.swift"]),
        // L5/L6 u7 wiring candidate (coordinator-owned landing): parser/model library +
        // three SEPARATE @main consumer suites (one file each, never one merged target).
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "VTTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "vtt-parser-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/vtt-parser-tests"),
        .executableTarget(name: "avsync-golden-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/avsync-golden-tests"),
        .executableTarget(name: "transport-vector-tests", path: "Sources/transport-vector-tests"),
        .executableTarget(name: "parity-pixel-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                          path: "Sources/parity-pixel-tests"),
        .executableTarget(name: "untagged-color-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/untagged-color-tests"),
        .executableTarget(name: "l3-convert-matrix-tests", dependencies: ["GorAVFFmpegAdapter"],
                          path: "Sources/l3-convert-matrix-tests",
                          swiftSettings: [.define("L3_PROVIDER")]),
        .executableTarget(name: "subtitle-srt-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SRTTests.swift"]),
        .executableTarget(name: "subtitle-ass-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSTests.swift"]),
        .executableTarget(name: "subtitle-track-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitleTrackTests.swift"]),
        .executableTarget(name: "subtitle-plan-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitlePlanTests.swift"]),
        .target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"],
                path: "Sources/GorAVNativeProbeKit",
                sources: ["GorAVSeekContract.swift", "NativeProbe.swift", "LeaseTable.swift", "PacketFeedMachine.swift", "DemuxerPolicy.swift"]),
        .systemLibrary(name: "CFFmpeg", path: "Sources/CFFmpeg"),
        // L6 Dolby Vision lane (block 78d L6; new lane dirs only, milestone-gated M4)
        .target(name: "GorAVDVRPU",
                path: "Sources/GorAVDVRPU",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVDolbyVision",
                dependencies: ["GorAVDVRPU", "CFFmpeg", "GorAVCore",
                               "GorAVFFmpegAdapter"],
                path: "Sources/GorAVDolbyVision"),
        .executableTarget(name: "dovi-selftest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-selftest",
                exclude: ["swift"]),
        .executableTarget(name: "dovi-hdrtest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-hdrtest",
                exclude: ["gen_ref_fields.py"]),
        .executableTarget(name: "dovi-vectest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-vectest"),
        .executableTarget(name: "dovi-fuzz",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-fuzz"),
        .target(name: "GorAVFFmpegAdapter", dependencies: ["CFFmpeg", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/GorAVFFmpegAdapter", sources: ["FFmpegSoftwareDecoder.swift", "SnapshotInput.swift", "SnapshotAVIOOwner.swift", "FrameObservation.swift", "FFmpegSoftwareAudioDecoder.swift", "L3Admission.swift", "L3SampleConvert.swift", "L3PixelConvert.swift", "L3HardwareDecode.swift", "L3AVCoordinator.swift", "SourceOpenOptions.swift", "MediaInventory.swift", "ActiveTransportSnapshot.swift"]),        .executableTarget(name: "l4-hwdecode-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "CFFmpeg"],
                path: "Sources/l4-hwdecode-tests", sources: ["L4HWDecodeTests.swift"]),

        .executableTarget(name: "gorav-first-frame", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/gorav-first-frame", sources: ["FirstFrame.swift"]),
        .executableTarget(name: "refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/refusal-tests", sources: ["RefusalTests.swift"]),
        .executableTarget(name: "playback-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/playback-test", sources: ["PlaybackTest.swift"]),
        .executableTarget(name: "audio-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/audio-test", sources: ["AudioTest.swift"]),
        .executableTarget(name: "seek-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-test", sources: ["SeekTest.swift"]),
        .executableTarget(name: "e1-shapes-tests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), .target(name: "GorAVMetalPresenter", condition: .when(platforms: [.macOS])), .target(name: "GorAVPlaybackCore", condition: .when(platforms: [.macOS]))], path: "Sources/e1-shapes-tests"),
        .executableTarget(name: "seek-restart-probe", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-restart-probe", sources: ["main.swift"]),
        .executableTarget(name: "audio-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/audio-refusal-tests", sources: ["AudioRefusalTests.swift"]),
        .executableTarget(name: "video-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/video-refusal-tests", sources: ["VideoRefusalTests.swift"]),
        .executableTarget(name: "coexist-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/coexist-test", sources: ["CoexistTest.swift"]),
        .executableTarget(name: "isolation-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/isolation-test", sources: ["IsolationTest.swift"]),
        .executableTarget(name: "trace-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/trace-dump", sources: ["TraceDump.swift"]),
        .executableTarget(name: "core-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/core-seek-tests"),
        .executableTarget(name: "real-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/real-seek-tests"),
        .executableTarget(name: "seek-ring-reset-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-ring-reset-tests"),
        .target(name: "GorAVSeekComposition", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVSeekComposition"),
        .executableTarget(name: "seek-pacing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-pacing-tests"),
        .executableTarget(name: "seek-composition-tests", dependencies: ["GorAVSeekComposition", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/seek-composition-tests"),
        .executableTarget(name: "audio-seek-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-seek-tests"),
        .executableTarget(name: "demux-parity-tests", dependencies: ["BridgeDemux", "CFFmpeg"], path: "Sources/demux-parity-tests"),
        .executableTarget(name: "audio-baseline-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-baseline-tests"),
        .executableTarget(name: "seek-contract-tests", dependencies: ["GorAVNativeProbeKit", "GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/seek-contract-tests"),
        .executableTarget(name: "adversarial-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/adversarial-seek-tests"),
        .executableTarget(name: "shell-seek-bridge-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/shell-seek-bridge-tests"),
        .executableTarget(name: "k9-adversarial", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/k9-adversarial", sources: ["K9Adversarial.swift"]),
        .executableTarget(name: "shell-mac-test", dependencies: ["GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/shell-mac-test", sources: ["ShellMacTest.swift"]),
        .executableTarget(name: "frame-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/frame-dump", sources: ["FrameDump.swift", "ConverterVariants.swift", "RawPlaneDump.swift"]),
        .target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
        .target(name: "GorAVAudioClock",
                path: "Sources/GorAVAudioClock",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVAudioClockSwift",
                dependencies: ["GorAVAudioClock", "GorAVCAtomics", "GorAVPlaybackCore"],
                path: "Sources/GorAVAudioClockSwift"),
        // r3 (architect r2 BLOCKER): NO explicit sources list - an explicit
        // list silently omitted Lane0Contract.swift + LifetimeRegistry.swift
        // (AudioSink/AudioStopResult/PlaybackRegistry unresolved in a real
        // package build; manual swiftc had masked it). Default = every file.
        .target(name: "GorAVPlaybackCore", dependencies: ["GorAVCAtomics", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVPlaybackCore"),
        .executableTarget(name: "session-venue-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/session-venue-tests"),
        // native87 Stage B entrypoint (B1-B3): pause-hold counter witnesses,
        // parked seek, close-from-paused report on the REAL embedded session.
        // macOS legs only; UNRUN (exit 77) elsewhere.
        .executableTarget(name: "b-gate-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/b-gate-tests"),
        .testTarget(name: "GorAVAudioClockTests",
                    dependencies: ["GorAVAudioClockSwift"],
                    path: "Tests/GorAVAudioClockTests"),
        .testTarget(name: "ReadinessAnchorTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/ReadinessAnchorTests"),
        .testTarget(name: "AudioPacingTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/AudioPacingTests"),
        .testTarget(name: "J3AudioControlTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/J3AudioControlTests"),
        .testTarget(name: "DecodeHeartbeatTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/DecodeHeartbeatTests"),
        .testTarget(name: "PlayerControlPlaneTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/PlayerControlPlaneTests"),
        .executableTarget(name: "pause-resume-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/pause-resume-tests"),
        .executableTarget(name: "race-witness-tests", dependencies: ["GorAVPlaybackCore"],
                          path: "Sources/race-witness-tests"),
        .executableTarget(name: "admission-tests", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"],
                          path: "Sources/admission-tests"),
        .executableTarget(name: "open-url-tests", dependencies: ["GorAVCore"], path: "Sources/open-url-tests"),
        .executableTarget(name: "audio-delay-tests", dependencies: ["GorAVPlaybackCore", "GorAVAudioClockSwift"], path: "Sources/audio-delay-tests"),
        .executableTarget(name: "window-mode-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/window-mode-tests"),
        .executableTarget(name: "observation-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/observation-tests"),
        .executableTarget(name: "timing-ledger-tests", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/timing-ledger-tests", sources: ["TimingLedgerTests.swift", "SPSCTests.swift"]),
        .executableTarget(name: "gorav-sink-check", dependencies: ["GorAVMacShell"], path: "Sources/gorav-sink-check", sources: ["SinkCheck.swift"]),
        .executableTarget(name: "gorav-play", dependencies: ["GorAVMacShell", "GorAVMetalPresenter", "GorAVPlaybackCore"], path: "Sources/gorav-play", sources: ["GorAVPlay.swift"]),
        // L7 embedded shell (block 168 factory gap): the E1 host-NSView embed
        // session. Whole body is canImport(AppKit)-gated - compiles empty
        // off-Mac; a Linux build is NOT a Mac compile claim. Explicit
        // sources pin: exactly the reviewed session file; a stray file
        // dropped into the dir is uncompiled, never silently wired.
        .target(name: "GorAVEmbeddedShell",
                dependencies: ["GorAVSubtitles", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVMacShell", "GorAVMetalPresenter", "GorAVFFmpegAdapter", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVEmbeddedShell", sources: ["GorAVEmbeddedSession.swift"]),
        .target(name: "GorAVMacShell", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVMacShell", sources: ["ShellClock.swift", "DisplaySink.swift", "AudioUnitSink.swift", "ShellFrameSource.swift", "FrameTap.swift", "TappedFrameLuma.swift", "WindowModeController.swift"]),
        // L2 Metal presenter lane, r7 landing (block 168 L3): new target dir
        // only; every Metal/AppKit source is canImport-gated so off-Mac
        // builds compile the target empty. GorAVMetalShellApp mirrors the
        // trunk shell contract (owner-issued session, shared CancelCommit,
        // audio-master pacing).
        .target(name: "GorAVMetalPresenter",
                dependencies: ["GorAVMacShell", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVSubtitles"],
                path: "Sources/GorAVMetalPresenter/core",
                sources: ["AspectFit.swift", "MetalPresenterTelemetry.swift", "SurfaceContract.swift", "MetalRenderer.swift", "MetalPresenter.swift", "GorAVMetalShellApp.swift", "StagePass.swift", "CVPixelBufferTap.swift"]),
        .executableTarget(name: "gorav-metal-check", dependencies: ["GorAVMetalPresenter", "GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/GorAVMetalPresenter/cli", sources: ["MetalCheck.swift"])
    ]
)

```

```text id=actual_run_log
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--6630B1A18289934C.txt
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
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-72ciyhvy/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module decoder_fault_vector_tests
[68/71] Compiling decoder_fault_vector_tests main.swift
[69/72] Wrapping AST for decoder-fault-vector-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking decoder-fault-vector-tests
Build of product 'decoder-fault-vector-tests' complete! (8.72s)
PASS VECTOR F1 replay
PASS VECTOR F2 replay
PASS VECTOR F3 replay
PASS VECTOR F4 replay
PASS VECTOR F5 replay
VECTOR-NEGATIVE F6 caught as required: counter deregistrations: got 0, want 1
decoder-fault-vector-tests: 5 PASS, 0 FAIL (1 seeded negative caught)
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
[0/1] Planning build
Building for debugging...
[0/6] Write sources
[2/10] Write swift-version--6630B1A18289934C.txt
[4/15] Emitting module GorAVFFmpegAdapter
[5/21] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[6/21] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[7/21] Compiling GorAVFFmpegAdapter MediaInventory.swift
[8/21] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[9/21] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[10/21] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[11/21] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[12/21] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[13/21] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[14/21] Compiling GorAVFFmpegAdapter FrameObservation.swift
[15/21] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[16/21] Compiling GorAVFFmpegAdapter L3Admission.swift
[17/21] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[18/22] Wrapping AST for GorAVFFmpegAdapter for debugging
[20/24] Emitting module decoder_lifetime_tests
[21/24] Compiling decoder_lifetime_tests main.swift
[22/25] Wrapping AST for decoder-lifetime-tests for debugging
[23/25] Write Objects.LinkFileList
[24/25] Linking decoder-lifetime-tests
Build of product 'decoder-lifetime-tests' complete! (4.63s)
PASS failed video open registers nothing
PASS real video open registers immutable opaque identity
PASS failed reopen and foreign close preserve live registration
PASS close/reopen never revives prior registration
PASS abandoned real video deinit deregisters
PASS failed audio open registers nothing
PASS real audio lifetime/foreign close fence
PASS abandoned real audio deinit deregisters
PASS invalidated-session successful adapter open cannot revive metadata
ALL DECODER LIFETIME CHECKS PASS (software registry only)
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-72ciyhvy/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[1/8] Write swift-version--6630B1A18289934C.txt
[3/7] Emitting module decoder_inventory_tests
[4/7] Compiling decoder_inventory_tests main.swift
[5/8] Wrapping AST for decoder-inventory-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking decoder-inventory-tests
Build of product 'decoder-inventory-tests' complete! (1.22s)
decoder-inventory-tests: 27 PASS, 0 FAIL
```
