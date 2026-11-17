# W-gdb-198y-in2tinct-03
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/ObservationSurface.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-03",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ObservationSurface.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/ObservationSurface.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: ObservationValue, ObservationProperty, ObservationChange, ObservationToken, cancel, ObservationStore, Counters, read, publish, observe, remove",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py",
    "callee": "Sources/GorAVPlaybackCore/ObservationSurface.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.658315+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ObservationSurface.swift",
        "block": "source1",
        "sha256": "206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-03.py",
        "block": "fixtures1",
        "sha256": "bd1ca4cacb553831268b274963e4a458bf73d97262e69f3cd6839478158cd149"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "f6fac8e690d156838cbbf3ece62288b717ffa71cb9282a3a77f73c0634a0ba1d",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-03: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "2c67fdc56b71687eedcbe6c18c0e8329b8b981e0ef2e56a20a12dee42985ea2b"
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
p=ROOT/'Sources/GorAVPlaybackCore/ObservationSurface.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd', 'pinned source changed: rebase and review, never bless silently'
for token in ['ObservationValue', 'ObservationProperty', 'ObservationChange', 'ObservationToken', 'cancel', 'ObservationStore', 'Counters', 'read', 'publish', 'observe', 'remove']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-03: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-03: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
