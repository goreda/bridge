# W-gdb-198z-1nstinct-06 - Source-bound snapshot expansion
state: OPEN / unclaimed
lab: 1nstinct

Typed optional audio selection, volume, audio delay, subtitle slots/delay/style, effective crop/color with source-generation identity; no invented defaults. Define snapshot fields without depending on unreturned lab interfaces.

Required acceptance: Observation-surface executable test: open A, mutate, seek, replace B, no A state leakage.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-06",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ObservationSurface.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-bound snapshot expansion; Typed optional audio selection, volume, audio delay, subtitle slots/delay/style, effective crop/color with source-generation identity; no invented defaults. Define snapshot fields without depending on unreturned lab interfaces.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Observation-surface executable test: open A, mutate, seek, replace B, no A state leakage.",
    "callee": "Sources/GorAVPlaybackCore/ObservationSurface.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-06.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Observation-surface executable test: open A, mutate, seek, replace B, no A state leakage.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-06",
    "paths": [
      "Sources/GorAVPlaybackCore/ObservationSurface.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-06.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-06.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.427163+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ObservationSurface.swift",
        "block": "source1",
        "sha256": "206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-06.py",
        "block": "fixtures1",
        "sha256": "61bb6bad8faaea6bc761dd20f83333458a5263ef958d32847411d3582620dd09"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "e7f45a410403a539cc7a7b2a9a4b380d057c269a5be59c173bff1910185aa8af",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-06; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "6ea3f7405ba7684e2bbd14e52953d2950e91e1bfb428c8a181ec5f649a832acc"
  }
}
```

```swift id=source1
// G4 (arch-195l, dispatch L6): observation surface. PLAN.md line 43:
// lifecycle/observations - time-pos, duration, pause, eof, idle, metadata,
// media-title, video-params, dwidth/dheight, fps fields, frame-drop-count,
// hwdec-current -> R2, G4. This is the mpv-style observe_property surface on
// gorav: typed properties, change-only notification, explicit unsubscribe.
// Pure Swift, Linux-tested; session publication points live in
// GorAVEmbeddedSession (Darwin target, UNCOMPILED).
import Foundation

/// Value of an observed property. `.none` is mpv's "unavailable": the
/// property is known but has no value right now (e.g. duration before open).
public enum ObservationValue: Equatable, Sendable {
    case none
    case double(Double)
    case int(Int64)
    case bool(Bool)
    case string(String)
    case stringDict([String: String])
}

/// The PLAN line-43 property set, raw values equal to the mpv property names
/// gor's scripts already observe, so a script-side observer table ports
/// without renaming.
public enum ObservationProperty: String, CaseIterable, Sendable {
    case timePos = "time-pos"
    case duration = "duration"
    case pause = "pause"
    case eofReached = "eof-reached"
    case idleActive = "idle-active"
    case metadata = "metadata"
    case mediaTitle = "media-title"
    case videoParams = "video-params"
    case width = "width"
    case height = "height"
    case dwidth = "dwidth"
    case dheight = "dheight"
    case containerFps = "container-fps"
    case estimatedVfFps = "estimated-vf-fps"
    case frameDropCount = "frame-drop-count"
    case decoderFrameDropCount = "decoder-frame-drop-count"
    case hwdecCurrent = "hwdec-current"
}

public struct ObservationChange: Equatable, Sendable {
    public let property: ObservationProperty
    public let old: ObservationValue
    public let new: ObservationValue

    public init(property: ObservationProperty, old: ObservationValue, new: ObservationValue) {
        self.property = property
        self.old = old
        self.new = new
    }
}

/// Registration handle. Removing it (or letting it deinit) unsubscribes;
/// an observer that cannot be unsubscribed is a leak, so both paths exist.
public final class ObservationToken {
    public let id: UInt64
    public let property: ObservationProperty
    private let onDeinit: (UInt64) -> Void
    private var active = true
    private let lock = NSLock()

    fileprivate init(id: UInt64, property: ObservationProperty, onDeinit: @escaping (UInt64) -> Void) {
        self.id = id
        self.property = property
        self.onDeinit = onDeinit
    }

    /// Idempotent explicit unsubscribe.
    public func cancel() {
        lock.lock()
        let was = active
        active = false
        lock.unlock()
        if was { onDeinit(id) }
    }

    deinit { cancel() }
}

/// Thread-safe property store with change-only notification. Handlers are
/// invoked OUTSIDE the store lock, in publish order; a handler that
/// re-enters the store (reads or publishes) cannot deadlock it.
public final class ObservationStore: @unchecked Sendable {

    public struct Counters: Equatable, Sendable {
        public var publishes = 0          // publish() calls
        public var changed = 0            // publishes that changed the value
        public var dedupSkips = 0         // publishes skipped as unchanged
        public var notifications = 0      // handler invocations
        public init() {}
    }

    private let lock = NSLock()
    private var values: [ObservationProperty: ObservationValue] = [:]
    private var observers: [UInt64: (ObservationProperty, (ObservationChange) -> Void)] = [:]
    private var nextID: UInt64 = 0
    public private(set) var counters = Counters()

    public init() {}

    /// Current value; `.none` when the property was never published.
    public func read(_ property: ObservationProperty) -> ObservationValue {
        lock.lock()
        defer { lock.unlock() }
        return values[property] ?? .none
    }

    /// Publish a value. Change-only: a publish equal to the current value is
    /// counted as a dedup skip and notifies nobody. Returns whether the
    /// value changed.
    @discardableResult
    public func publish(_ property: ObservationProperty, _ value: ObservationValue) -> Bool {
        lock.lock()
        counters.publishes += 1
        let old = values[property] ?? .none
        guard old != value else {
            counters.dedupSkips += 1
            lock.unlock()
            return false
        }
        values[property] = value
        counters.changed += 1
        let change = ObservationChange(property: property, old: old, new: value)
        let targets = observers.values.filter { $0.0 == property }.map { $0.1 }
        counters.notifications += targets.count
        lock.unlock()
        for handler in targets { handler(change) }
        return true
    }

    /// Observe one property. The handler fires on every CHANGE after
    /// registration (no initial replay; read() for the current value).
    public func observe(_ property: ObservationProperty,
                        handler: @escaping (ObservationChange) -> Void) -> ObservationToken {
        lock.lock()
        nextID &+= 1
        let id = nextID
        observers[id] = (property, handler)
        lock.unlock()
        return ObservationToken(id: id, property: property) { [weak self] tokenID in
            self?.remove(tokenID)
        }
    }

    private func remove(_ id: UInt64) {
        lock.lock()
        observers[id] = nil
        lock.unlock()
    }

    /// Number of live observers; test and diagnostic hook.
    public var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVPlaybackCore/ObservationSurface.swift').read_bytes()).hexdigest()=='206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-06; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-06; baseline only, product change and semantic test still required
```

secret scan: clean
