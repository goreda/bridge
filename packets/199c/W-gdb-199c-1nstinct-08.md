# W-gdb-199c-1nstinct-08 - Nontrapping neutral integer observation
state: OPEN / unclaimed
lab: 1nstinct

## Product change
Replace unchecked Double-to-Int/NSNumber truncation with exact representability checks. Nonfinite, out-of-range and fractional frame-drop counters map to nil, never crash or truncate. Retain documented passthrough of Double properties including NaN and existing property names. Do not edit PPController or fake gorav snapshots.

## Grounded gap and boundary
U2 neutral observation snapshot safety; S2 GorPlaybackModel station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-08",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorPlaybackModel/EngineObservation.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "Replace unchecked Double-to-Int/NSNumber truncation with exact representability checks. Nonfinite, out-of-range and fractional frame-drop counters map to nil, never crash or truncate. Retain documented passthrough of Double properties including NaN and existing property names. Do not edit PPController or fake gorav snapshots.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 neutral observation snapshot safety; S2 GorPlaybackModel station",
    "callee": "archive/gor/Sources/gor/GorPlaybackModel/EngineObservation.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-08",
    "paths": [
      "archive/gor/Sources/gor/GorPlaybackModel/EngineObservation.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:52.998381+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "a108423f69f0a293210dc00ef791d118f84b461ef2c7436f296d63798f7d4932",
    "last_5_lines": [
      "0x00007fb9a8600000\u20130x00007fb9a8b95930 b9f29f81b467904a40bdaaa0b0f84468865569b7 libswiftCore.so /tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/lib/swift/linux/libswiftCore.so",
      "",
      "Backtrace took 0.01s",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorPlaybackModel/EngineObservation.swift",
        "block": "source1",
        "sha256": "c8ce37ab1ff7a734de70b76b8d1ba9cea64bd75031b98ac0fe2d4dc2bc83def6",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-08.json",
        "block": "fixtures2",
        "sha256": "9424651eac46a4bf1e38a9374ade400d7d37d1b102914510c7f5326f36b63b18"
      }
    ],
    "adaptation_note": "Coordinator moved test paths under archive/gor/Tests and runner ROOT parents3 to parents5. Original starter logs precede adaptation; adapted compiler rerun NOT_RUN."
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
//
//  EngineObservation.swift
//  gor - G4 observation surface (arch-195b, gor side)
//
//  Engine-neutral view of the player properties PPController observes today.
//  The mpv PollEngine keeps its exact tiers and cadence; this file owns:
//    - EngineProperty: the neutral keys and the single-source mpv<->neutral
//      name mapping (no mpv property name literal anywhere upstream),
//    - EngineObservedState: the typed snapshot consumers (G5 control bus,
//      G6 presentation receipt) read instead of raw [String: Any] stores,
//    - EngineObservationTranslator: pure store-snapshot -> state translation,
//    - EngineObservationCenter: the live sink PPController publishes every
//      poll flush into; consumers add observers or poll latest().
//  A future gorav backend publishes the same EngineObservedState and no
//  consumer changes.
//
//  Foundation-only on purpose: the file compiles and is checked on Linux
//  (no AppKit) via g4-observation-tests/main.swift.
//

import Foundation

// MARK: - EngineProperty (neutral keys, single-source mpv mapping)

/// The properties of the G4 observation surface. The Swift case name is the
/// engine-neutral key; the raw value is the mpv property name (the ONLY
/// place mpv names for this surface are written down).
public enum EngineProperty: String, CaseIterable {
    case timePos = "time-pos"
    case duration = "duration"
    case paused = "pause"
    case eofReached = "eof-reached"
    case idleActive = "idle-active"
    case metadata = "metadata"
    case mediaTitle = "media-title"
    case videoDisplayWidth = "video-params/dw"
    case videoDisplayHeight = "video-params/dh"
    case videoStereoMode = "video-params/stereo-in"
    case videoRotation = "video-params/rotate"
    case displayWidth = "dwidth"
    case displayHeight = "dheight"
    case containerFPS = "container-fps"
    case estimatedVideoFPS = "estimated-vf-fps"
    case displayFPS = "display-fps"
    case frameDropCount = "frame-drop-count"
    case decoderFrameDropCount = "decoder-frame-drop-count"
    case hwdecCurrent = "hwdec-current"

    /// mpv-side property name for IPC tables (PollEngine tiers).
    public var mpvName: String { rawValue }
    /// Engine-neutral key (the Swift case name).
    public var neutralName: String { String(describing: self) }
}

// MARK: - EngineObservedState (typed snapshot)

public struct EngineVideoParams: Equatable {
    public var displayWidth: Double?
    public var displayHeight: Double?
    public var stereoMode: String?
    public var rotationDegrees: Double?
    public init(displayWidth: Double? = nil, displayHeight: Double? = nil,
                stereoMode: String? = nil, rotationDegrees: Double? = nil) {
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.stereoMode = stereoMode
        self.rotationDegrees = rotationDegrees
    }
}

public struct EngineObservedState: Equatable {
    public var timePos: Double?
    public var duration: Double?
    public var paused: Bool?
    public var eofReached: Bool?
    public var idleActive: Bool?
    public var metadata: [String: String]?
    public var mediaTitle: String?
    public var videoParams: EngineVideoParams
    public var displayWidth: Double?
    public var displayHeight: Double?
    public var containerFPS: Double?
    public var estimatedVideoFPS: Double?
    public var displayFPS: Double?
    public var frameDropCount: Int?
    public var decoderFrameDropCount: Int?
    public var hwdecCurrent: String?
    public init() {
        videoParams = EngineVideoParams()
    }
}

// MARK: - EngineObservationTranslator (pure)

public enum EngineObservationTranslator {
    /// Raw poll-store snapshot (mpv property names, JSON-decoded values) ->
    /// typed neutral state. A missing, NSNull, or mistyped entry maps to nil,
    /// never to a fabricated default. Values pass through as delivered,
    /// including NaN/inf (mirrors today's store semantics; consumers decide).
    public static func translate(_ results: [String: Any]) -> EngineObservedState {
        func double(_ p: EngineProperty) -> Double? {
            guard let v = results[p.mpvName] else { return nil }
            if let d = v as? Double { return d }
            if let n = v as? NSNumber { return n.doubleValue }
            if let i = v as? Int { return Double(i) }
            return nil
        }
        func bool(_ p: EngineProperty) -> Bool? {
            guard let v = results[p.mpvName] else { return nil }
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.boolValue }
            return nil
        }
        func int(_ p: EngineProperty) -> Int? {
            guard let v = results[p.mpvName] else { return nil }
            // Exact bridging first: integer NSNumbers land here; a fractional
            // NSNumber fails this cast instead of truncating.
            if let i = v as? Int { return i }
            // Fractional Doubles are rejected, never truncated.
            if let d = v as? Double { return d == d.rounded() ? Int(d) : nil }
            if let n = v as? NSNumber { return n.intValue }
            return nil
        }
        func string(_ p: EngineProperty) -> String? {
            guard let v = results[p.mpvName] else { return nil }
            return v as? String
        }
        var state = EngineObservedState()
        state.timePos = double(.timePos)
        state.duration = double(.duration)
        state.paused = bool(.paused)
        state.eofReached = bool(.eofReached)
        state.idleActive = bool(.idleActive)
        state.mediaTitle = string(.mediaTitle)
        if let m = results[EngineProperty.metadata.mpvName] as? [String: String] {
            state.metadata = m
        } else if let m = results[EngineProperty.metadata.mpvName] as? [String: Any] {
            // Mixed-value dictionaries keep only their string entries.
            var out = [String: String]()
            for (k, v) in m { if let s = v as? String { out[k] = s } }
            state.metadata = out
        }
        state.videoParams = EngineVideoParams(
            displayWidth: double(.videoDisplayWidth),
            displayHeight: double(.videoDisplayHeight),
            stereoMode: string(.videoStereoMode),
            rotationDegrees: double(.videoRotation))
        state.displayWidth = double(.displayWidth)
        state.displayHeight = double(.displayHeight)
        state.containerFPS = double(.containerFPS)
        state.estimatedVideoFPS = double(.estimatedVideoFPS)
        state.displayFPS = double(.displayFPS)
        state.frameDropCount = int(.frameDropCount)
        state.decoderFrameDropCount = int(.decoderFrameDropCount)
        state.hwdecCurrent = string(.hwdecCurrent)
        return state
    }
}

// MARK: - EngineObservationCenter (live sink)

/// The single publication point for the neutral surface. PPController's
/// PollEngine ingests one translated snapshot per flush; G5/G6 consumers
/// either poll latest() or register an observer. Thread-safe; observers are
/// called synchronously on the ingesting queue (the main queue in the
/// shipped wiring) in registration order, after `current` is updated.
public final class EngineObservationCenter {
    public static let shared = EngineObservationCenter()
    public typealias Observer = (EngineObservedState) -> Void

    private let lock = NSLock()
    private var current: EngineObservedState?
    private var observers: [Int: Observer] = [:]
    private var nextToken = 0
    /// Total ingests since process start; checks and future liveness use it.
    public private(set) var ingestedCount: UInt64 = 0

    public init() {}

    public func ingest(_ state: EngineObservedState) {
        lock.lock()
        current = state
        ingestedCount &+= 1
        let snapshot = observers.sorted { $0.key < $1.key }.map { $0.value }
        lock.unlock()
        for observer in snapshot { observer(state) }
    }

    public func latest() -> EngineObservedState? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Returns a token for removeObserver(_:).
    @discardableResult
    public func addObserver(_ observer: @escaping Observer) -> Int {
        lock.lock()
        let token = nextToken
        nextToken += 1
        observers[token] = observer
        lock.unlock()
        return token
    }

    public func removeObserver(_ token: Int) {
        lock.lock()
        observers[token] = nil
        lock.unlock()
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "archive/gor/Sources/gor/GorPlaybackModel/EngineObservation.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor value: Any in [Double.infinity, -Double.infinity, Double.nan, Double.greatestFiniteMagnitude, Double(Int.max), NSNumber(value: 1.5)] {\n let s=EngineObservationTranslator.translate([\"frame-drop-count\": value])\n check(s.frameDropCount == nil,\"invalid counter refused\")\n}\ncheck(EngineObservationTranslator.translate([\"frame-drop-count\": 42]).frameDropCount == 42,\"integer retained\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=-4

Swift/IntegerTypes.swift:14133: Fatal error: Double value cannot be converted to Int because it is either infinite or NaN

*** Signal 4: Backtracing from 0x7fb9a875fd14... done ***

*** Program crashed: Illegal instruction at 0x00007fb9a875fd14 ***

Thread 0 "test" crashed:

0      0x00007fb9a875fd14 closure #1 in closure #1 in closure #1 in _assertionFailure(_:_:file:line:flags:) + 308 in libswiftCore.so
1 [ra] 0x00007fb9a875fac2 closure #1 in closure #1 in _assertionFailure(_:_:file:line:flags:) + 257 in libswiftCore.so
2 [ra] 0x00007fb9a875f97d closure #1 in _assertionFailure(_:_:file:line:flags:) + 380 in libswiftCore.so
3 [ra] 0x00007fb9a88e2e76 _assertionFailure(_:_:file:line:flags:) + 229 in libswiftCore.so
4 [ra] 0x000055652462e8f0 int #1 (_:) in static EngineObservationTranslator.translate(_:) + 1311 in test
5 [ra] 0x0000556524634fe7 static EngineObservationTranslator.translate(_:) + 2374 in test
6 [ra] 0x000055652463693e main + 941 in test


Registers:

rax 0x0000000000000000  0
rdx 0x0000000000000001  1
rcx 0x0000000000000005  5
rbx 0x0000000556551fe0  22923255776
rsi 0x0000000000000007  7
rdi 0x0000556551fce010  03 00 02 00 01 00 02 00 02 00 01 00 00 00 01 00  ················
rbp 0x00007ffedecc0260  a0 02 cc de fe 7f 00 00 c2 fa 75 a8 b9 7f 00 00   ·ÌÞþ···Âúu¨¹···
rsp 0x00007ffedecc0250  4c 00 00 00 00 00 00 00 35 37 00 00 00 00 00 00  L·······57······
 r8 0x0000556551fe0c30  e0 1f 55 56 05 00 00 00 74 0c 99 e7 3f ba 4a 9f  à·UV····t··ç?ºJ·
 r9 0x00007ffedecc0040  46 61 74 61 6c 20 65 72 72 6f 72 3a 20 44 6f 75  Fatal error: Dou
r10 0x0000000000000000  0
r11 0x9f4aba3fe7990c74  11478191383938403444
r12 0x00007ffedecc1201  00 00 00 00 00 00 00 40 9e 22 a7 b9 7f 00 00 88  ·······@·"§¹····
r13 0x0000000000000000  0
r14 0x0000000000000001  1
r15 0x0000000000000001  1
rip 0x00007fb9a875fd14  0f 0b 48 83 ec 08 48 8d 05 3f e0 46 00 48 8d 3d  ··H·ì·H··?àF·H·=

rflags 0x0000000000010206  PF

cs 0x0033  fs 0x0000  gs 0x0000


Images (18 omitted):

0x000055652462a000–0x0000556524638e40 <no build ID>                            test            /tmp/tmpi82gya57/test
0x00007fb9a8600000–0x00007fb9a8b95930 b9f29f81b467904a40bdaaa0b0f84468865569b7 libswiftCore.so /tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/lib/swift/linux/libswiftCore.so

Backtrace took 0.01s



```

Coordinator adaptation: test paths moved under archive/gor/Tests; ROOT adjusted to repository root. No semantic test changes. Original starter evidence not rerun here.

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
