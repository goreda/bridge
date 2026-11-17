# W-gdb-198y-in2tinct-40
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-40",
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
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py checks Sources/GorAVPlaybackCore/CoreSeekDriver.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: CoreSeekProvider, currentBinding, tryBegin, CoreSeekAdmissionRefusal, CoreSeekOutcome, CoreSeekDriver, requestCancellationOfActive, nextIDs, seek",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py",
    "callee": "Sources/GorAVPlaybackCore/CoreSeekDriver.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.552434+00:00",
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
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-40.py",
        "block": "fixtures1",
        "sha256": "ab2c589bbabe39b70b916e50aa38e6ddd46513f8639ade3eb6f48475dc86c1d8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7e6adab4b3ca5a3abad662c537e8c86248170596507618dba2851ccfc430a2cd",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "6a944afa9b31fdf6a56ad37209f6b02e31056b048c305d46dea4fdb0472fe146"
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
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
