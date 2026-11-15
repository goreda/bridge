# W-gdb-028 frame-lease adversarial vector pack
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-028

```packet-json
{
 "packet_id": "W-gdb-028",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
   "excerpt_block": "source1_1"
  },
  {
   "path": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
   "excerpt_block": "source1_2"
  }
 ],
 "interface": {
  "signatures": "acquire(handle: UInt64, bytes: Int, owner: Owner) -> Bool; transfer(handle:to:) -> Bool; release(handle:) -> Bool; entry(handle:) -> Entry?; leakedHandles() -> [UInt64]",
  "types": "Entry { handle: UInt64, bytes: Int, owner: Owner }; fence-after-release witness = release returning false; cross-plane stale writes: RTEvent.Kind.staleFenced",
  "ownership_lifetime": "the table itself; budget counts outstanding bytes; double-release returns false and mutates nothing",
  "caller": "lease vector runner",
  "callee": "LeaseTable acquire/transfer/release + Entry/Owner + RTEvent.staleFenced (pinned below)"
 },
 "test": {
  "command": "swift run frame-lease-tests && swift run frame-tap-tests",
  "expected": "exit 0 for both; existing checks stay green; vector replay rows green; a seeded fence-after-release is caught and printed",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/lease-vectors/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
decoded-frame leases/fences (LeaseTable and the tap bridge) guard pixel lifetime; eviction-while-pinned or fence-after-release regressions ship as corrupt frames or use-after-release crashes, and current coverage is linear happy-path heavy.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVNativeProbeKit/LeaseTable.swift (sha256 abdc3c43; first 60 lines below); frame-lease-tests + frame-tap-tests suites (Linux PASS at the pin per STATUS.md).
- real test command: swift run frame-lease-tests + swift run frame-tap-tests stay green.

## expected behaviour
a portable model plus adversarial vectors: retain/release ordering, eviction while pinned, readback during eviction release, fence-after-release detection, owner-hook re-entry; vectors assert exact lease counts and typed fence violations.

## exact call site and interface
LeaseTable's lease/fence vocabulary (pinned excerpt); model + vectors are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15; the fence API)
LeaseTable (excerpt above) is the lease half of the fence ledger; the fence vocabulary at the pin:
- acquire(handle: UInt64, bytes: Int, owner: Owner) -> Bool - false = budget/duplicate refusal, typed
- transfer(handle: UInt64, to: Owner) -> Bool
- release(handle: UInt64) -> Bool - release of an unknown/already-released handle returns false: THAT is the typed fence-after-release witness
- entry(handle:) -> Entry?, outstandingCount, currentOutstandingBytes, maxOutstandingBytes (budget), removeAll(), leakedHandles() -> [UInt64]
- Entry { handle: UInt64, bytes: Int, owner: Owner }; Owner enum per the excerpt
- cross-plane stale writes ride RTEvent.Kind.staleFenced (SPSC.swift, same pin)
vectors assert: exact outstanding counts/bytes per op sequence; double-release returns false and mutates nothing; eviction-while-pinned is impossible (budget counts outstanding bytes); leakedHandles() names every survivor of a teardown without removeAll().

## behaviour that must not change
existing lease/tap checks stay green; deterministic; no GPU, no pixels.

## acceptance test (from the product repo)
vectors replay green against the pinned lease logic; a seeded fence-after-release is caught (negative control shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVNativeProbeKit/LeaseTable.swift (sha256 abdc3c43, lines 1-46 of 83)
```swift id=source1
// AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 2912B/0f5fb9eb...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: ownership accounting.
import Foundation

/// Ownership accounting for native frame buffers, separate from the contract-level
/// FrameLeaseLedger (which tracks protocol stage transitions). LeaseTable answers
/// one question: who currently owns buffer slot N, and is every acquire matched
/// by exactly one release before teardown. A leak here is a retained native buffer;
/// it is recorded, never silently dropped.
public final class LeaseTable: @unchecked Sendable {
    public enum Owner: Equatable, Sendable {
        case decoder
        case presenter
        case none
    }
    public struct Entry: Equatable, Sendable {
        public let handle: UInt64
        public let bytes: Int
        public internal(set) var owner: Owner
        public init(handle: UInt64, bytes: Int, owner: Owner) {
            self.handle = handle; self.bytes = bytes; self.owner = owner
        }
    }
    private let lock = NSLock()
    private var entries: [UInt64: Entry] = [:]
    private var outstandingBytes: Int = 0
    private var maxOutstandingBytesStore: Int = 0
    /// r5 D16: lock-guarded getter; backing store only touched under lock.
    public var maxOutstandingBytes: Int { lock.lock(); defer { lock.unlock() }; return maxOutstandingBytesStore }
    public init() {}

    /// Records a freshly allocated native buffer. Returns false on duplicate handle.
    @discardableResult public func acquire(handle: UInt64, bytes: Int, owner: Owner) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // r4 D16: negative byte counts are a caller contract violation.
        guard bytes >= 0 else { return false }
        guard entries[handle] == nil else { return false }
        entries[handle] = Entry(handle: handle, bytes: bytes, owner: owner)
        let (sum, overflow) = outstandingBytes.addingReportingOverflow(bytes)
        if overflow { entries.removeValue(forKey: handle); return false }
        outstandingBytes = sum
        maxOutstandingBytesStore = max(maxOutstandingBytesStore, outstandingBytes)
        return true
    }

```

### Sources/GorAVNativeProbeKit/LeaseTable.swift (sha256 abdc3c43, lines 48-54 of 83)
```swift id=source1_1
    @discardableResult public func transfer(handle: UInt64, to owner: Owner) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[handle] else { return false }
        e.owner = owner; entries[handle] = e
        return true
    }

```

### Sources/GorAVNativeProbeKit/LeaseTable.swift (sha256 abdc3c43, lines 56-60 of 83)
```swift id=source1_2
    @discardableResult public func release(handle: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries.removeValue(forKey: handle) else { return false }
        outstandingBytes -= e.bytes
        return true
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"ops":[{"acquire":{"h":1,"bytes":4096,"owner":"display"}},{"release":{"h":1}},{"release":{"h":1},"expect":false},{"teardown":{}}],"expect":{"outstandingCount":0,"leakedHandles":[]}}
```
