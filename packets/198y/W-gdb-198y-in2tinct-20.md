# W-gdb-198y-in2tinct-20
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/CoreSeekDriver.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-20",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CoreSeekDriver.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/CoreSeekDriver.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: CoreSeekProvider, currentBinding, tryBegin, CoreSeekAdmissionRefusal, CoreSeekOutcome, CoreSeekDriver, requestCancellationOfActive, nextIDs, seek",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py",
    "callee": "Sources/GorAVPlaybackCore/CoreSeekDriver.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:21.220418+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CoreSeekDriver.swift",
        "block": "source1",
        "sha256": "3fdb2fa68692956b72389c964dfb6dfee41f0a95581dc8928afa86cf6349adf5"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-20.py",
        "block": "fixtures1",
        "sha256": "cbb5f7591f047bf07480af2ec590bb3bcf754a2ec08d5488c9c9bcd8fa6eead6"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "485d721ed85137f3654011e584d3d15c90f0df5cd7a44d4b5a244747a59c4cd8",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-20: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "1bd6fffa0a916f706e5a125f22d5b044198b12245676d28d81a8e5c9d958ae63"
  }
}
```

```swift id=source1
import Foundation
import GorAVCore
import GorAVNativeProbeKit

/// S5 integration (R2Y core lane): the CORE-side seek driver. The core owns correlation/queue-turn
/// minting and the commit ACK; the provider (peer) owns the native boundary. Contract invariants
/// enforced here:
///  - revision advances ONLY on nativeReady (the commit ACK); refused/cancelled no-mutation
///    outcomes leave the revision untouched and resume core-gated (never provider-success-gated);
///  - PINNED HANDSHAKE: the core ADOPTS the provider-issued reservedRevision; it never holds a
///    separately reserved revision;
///  - BACKWARD keyframe request only (flags bit 0); exact/ceil targets are not expressible here;
///  - provider receipts never carry a global commit - the ACK callback is the core's only commit.
public protocol CoreSeekProvider: Sendable {
    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?
    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction
}

public enum CoreSeekAdmissionRefusal: Sendable, Equatable {
    case noSource            // no current binding (nothing open / poisoned / closing)
    case busy                // an active transaction occupies the provider slot
    case stale               // core's expected revision != provider's current at queue-turn
    case closed
    case unsupported(String)
    case legacyRejected
    case correlationExhausted
}

public enum CoreSeekOutcome: Sendable {
    case committed(receipt: SeekReceipt)      // nativeReady: ACK fired with the adopted revision
    case noMutation(receipt: SeekReceipt)     // refused/cancelled: revision UNCHANGED, core-gated resume
    case failedPoisoned(receipt: SeekReceipt) // failed/cancelledAfterCleanup: poison, closeRequired
    case admissionRefused(reason: CoreSeekAdmissionRefusal)
}

public final class CoreSeekDriver: @unchecked Sendable {
    private let lock = NSLock()
    private var lastCorrelation: UInt64 = 0
    private var lastQueueTurn: UInt64 = 0
    private var active: (any SeekTransaction)?   // for core-initiated cancellation; never executed twice
    /// Lock-guarded activity read for the shell bridge: true while a transaction is in flight.
    public var hasActiveTransaction: Bool { lock.lock(); defer { lock.unlock() }; return active != nil }
    public init() {}
    /// TEST SEAM (harness only): seed the mint so exhaustion is a runnable witness. Production uses init().
    public init(testSeed correlation: UInt64, queueTurn: UInt64) {
        lastCorrelation = correlation; lastQueueTurn = queueTurn
    }
    /// Core-initiated cancellation of the in-flight transaction (e.g. user cancel during a held
    /// native call). Idempotent-safe: the provider arbitrates first-recorded winner; if no
    /// transaction is active this is a no-op, never an error.
    public func requestCancellationOfActive() {
        lock.lock(); let txn = active; lock.unlock()
        txn?.requestCancellation()
    }
    private func nextIDs() -> (UInt64, UInt64)? {
        lock.lock(); defer { lock.unlock() }
        let (c, oc) = lastCorrelation.addingReportingOverflow(1)
        let (t, ot) = lastQueueTurn.addingReportingOverflow(1)
        guard !oc, !ot else { return nil }   // saturating exhaustion, NEVER a wrap
        lastCorrelation = c; lastQueueTurn = t; return (c, t)
    }
    /// One core seek turn. `commitACK` fires EXACTLY once, only on nativeReady, with the adopted
    /// (provider-issued) revision - wire it to the PresentationRevision bump; no other outcome
    /// may advance any core-visible revision.
    public func seek(on provider: any CoreSeekProvider, position: RationalTime,
                     commitACK: @Sendable (SeekRevision, SeekReceipt) -> Void) async -> CoreSeekOutcome {
        guard let binding = provider.currentBinding() else { return .admissionRefused(reason: .noSource) }
        guard let ids = nextIDs(),
              let cid = try? SeekCorrelationID(rawValue: ids.0, queueTurn: ids.1) else {
            return .admissionRefused(reason: .correlationExhausted)
        }
        let target = SeekTarget(position: position, rounding: .floorToKeyframe, requestedFlags: 1)
        let request = SeekRequest(correlationID: cid, session: binding.session, source: binding.token,
                                  target: target, expectedRevision: binding.revision)
        let txn: any SeekTransaction
        do { txn = try provider.tryBegin(request) }
        catch SeekRefusal.busy { return .admissionRefused(reason: .busy) }
        catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
        catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
        catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
        catch { return .admissionRefused(reason: .unsupported("\(error)")) }
        let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
        lock.lock(); active = txn; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock() }
        do { try txn.execute() }
        catch {
            txn.requestCancellation()
            _ = await txn.completion()
            return .admissionRefused(reason: .unsupported("execute misuse: \(error)"))
        }
        let receipt = await txn.completion()
        switch receipt.outcome {
        case .nativeReady:
            commitACK(adopted, receipt)          // the ONLY advance path in the whole flow
            return .committed(receipt: receipt)
        case .refusedNoMutation, .cancelledNoMutation:
            return .noMutation(receipt: receipt) // revision untouched; resume is core-gated
        default:
            return .failedPoisoned(receipt: receipt)
        }
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/CoreSeekDriver.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='3fdb2fa68692956b72389c964dfb6dfee41f0a95581dc8928afa86cf6349adf5', 'pinned source changed: rebase and review, never bless silently'
for token in ['CoreSeekProvider', 'currentBinding', 'tryBegin', 'CoreSeekAdmissionRefusal', 'CoreSeekOutcome', 'CoreSeekDriver', 'requestCancellationOfActive', 'nextIDs', 'seek']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='3fdb2fa68692956b72389c964dfb6dfee41f0a95581dc8928afa86cf6349adf5'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-20: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-20: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
