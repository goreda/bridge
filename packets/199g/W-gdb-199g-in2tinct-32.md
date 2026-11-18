# W-gdb-199g-in2tinct-32 - Failed seek attach clears previous fence
state: OPEN / unclaimed

LIVE-CALLER BOUND: GorAVEmbeddedSession.swift lines550/852/1598 and ShellFrameSource.swift line794 construct ShellSeekBridge. Exact attach/getter and binding DTOs compile with the complete seek contract and exact CoreSeekProvider protocol. A reduced ShellSeekBridge wrapper contains the original fenceLock/fence fields and init, not the rest of the class. Provider test double supplies currentBinding/tryBegin. This proves attach semantics only, not the seek transaction or native provider.
lab: in2tinct

attach(to:) must atomically clear any remembered fence when provider.currentBinding returns nil, so attach failure cannot leave a prior provider admitted by currentFence. Preserve successful attach behavior. Audit attach callers and keep all seek/ACK behavior unchanged. Live construction sites: GorAVEmbeddedSession lines550/852/1598 and ShellFrameSource line794. Regression extracts the exact attach/getter and fence DTOs, with the exact two stored fence fields. CoreSeekProvider is exact protocol; test provider is deliberately a test double. Other ShellSeekBridge operations and native provider are not run.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199g-in2tinct-32",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ShellSeekBridge.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "attach(to:) must atomically clear any remembered fence when provider.currentBinding returns nil, so attach failure cannot leave a prior provider admitted by currentFence. Preserve successful attach behavior. Audit attach callers and keep all seek/ACK behavior unchanged. Live construction sites: GorAVEmbeddedSession lines550/852/1598 and ShellFrameSource line794. Regression extracts the exact attach/getter and fence DTOs, with the exact two stored fence fields. CoreSeekProvider is exact protocol; test provider is deliberately a test double. Other ShellSeekBridge operations and native provider are not run.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "LIVE-CALLER BOUND: GorAVEmbeddedSession.swift lines550/852/1598 and ShellFrameSource.swift line794 construct ShellSeekBridge. Exact attach/getter and binding DTOs compile with the complete seek contract and exact CoreSeekProvider protocol. A reduced ShellSeekBridge wrapper contains the original fenceLock/fence fields and init, not the rest of the class. Provider test double supplies currentBinding/tryBegin. This proves attach semantics only, not the seek transaction or native provider.",
    "callee": "Sources/GorAVPlaybackCore/ShellSeekBridge.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-32.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199g-in2tinct-32",
    "paths": [
      "Sources/GorAVPlaybackCore/ShellSeekBridge.swift",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-32.py",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-32.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-32.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ShellSeekBridge.swift",
        "block": "source1",
        "sha256": "5689ac8756464a2fc412562749041ceb20384e2748ed60c49b41b5a715eb6dfe",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-32.py",
        "block": "fixtures1",
        "sha256": "ca73de002a7ea6df0372f590d1eead763fa38702b16e21455076dcf870d2dcae"
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-32.json",
        "block": "fixtures2",
        "sha256": "7adfa9a839e8d7a1175f11652f5168829adf1dd2651011f9865bd5db02e1a6fe"
      },
      {
        "path": "Sources/GorAVNativeProbeKit/GorAVSeekContract.swift",
        "block": "frozen_dependency_0",
        "sha256": "64b9ce00ed88d0fc03d9ede8870fd4f8f7e08e1ed45782a6a5daca002d5f405e",
        "read_only_dependency": true,
        "role": "Full original provenance for pinned declaration extraction; not an edit lease or an extra compile input."
      },
      {
        "path": "Sources/GorAVPlaybackCore/CoreSeekDriver.swift",
        "block": "frozen_dependency_1",
        "sha256": "3fdb2fa68692956b72389c964dfb6dfee41f0a95581dc8928afa86cf6349adf5",
        "read_only_dependency": true,
        "role": "Full original provenance for pinned declaration extraction; not an edit lease or an extra compile input."
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "a327f50837aa392e451f9f2e6891db387f9ef0cc964d5d671df9fe0b4ca0f58c",
    "last_5_lines": [
      "semantic_exit=1",
      "PASS initial attach",
      "PASS failed attach returned",
      "FAIL failed attach removes prior admission fence",
      ""
    ]
  },
  "classification": "LIVE-CALLER BOUND: GorAVEmbeddedSession.swift lines550/852/1598 and ShellFrameSource.swift line794 construct ShellSeekBridge. Exact attach/getter and binding DTOs compile with the complete seek contract and exact CoreSeekProvider protocol. A reduced ShellSeekBridge wrapper contains the original fenceLock/fence fields and init, not the rest of the class. Provider test double supplies currentBinding/tryBegin. This proves attach semantics only, not the seek transaction or native provider."
}
```

```swift id=source1
// ShellSeekBridge (S5 shell integration): the shell-facing seek entry point.
// Owns ONE CoreSeekDriver per provider open and maps the contract outcome to the
// shell's barrier/revision semantics. The bridge NEVER attests a flush the receipt
// does not evidence: a committed seek attests .flushed ONLY when the nativeReady
// facts are complete (flushObserved + packetFeedReset + decoderReset +
// packetAccountingReconciled). Anything mutated-but-not-ready, or any nativeReady
// with incomplete facts (provider attested ready but the barrier is not
// attestable from the receipt), fails closed as requiresClose.
import Foundation
import GorAVNativeProbeKit

public enum ShellSeekResult: Sendable {
    /// nativeReady with COMPLETE barrier facts. Attests the NATIVE cleanup (flush +
    /// packet-feed reset + decoder reset + accounting) and that every subsequently
    /// delivered frame carries its true EventOrigin (retained pre-seek handles keep
    /// their OLD origin, so stale frames are identifiable, never invisible).
    /// .flushed is truthful ONLY together with consumer-side fencing: the shell adopts
    /// adoptRevision EXACTLY ONCE (the provider-reserved revision, via the core ACK -
    /// no second shell-side bump) and drops any frame whose origin.providerRevision
    /// differs from the adopted revision. The bridge provides the fence input; the
    /// consumer-path enforcement is the shell's obligation (pump revision stamp).
    case committedFlushed(receipt: SeekReceipt, adoptRevision: SeekRevision)
    /// No mutation (refused/cancelled pre-entry): revision UNCHANGED; resume is
    /// core-gated - the shell continues the current presentation, no barrier needed.
    case noMutationCoreGated(receipt: SeekReceipt)
    /// Admission refused before any reservation: typed reason, no state change.
    case admissionRefused(reason: CoreSeekAdmissionRefusal)
    /// Mutated non-ready outcome (poison, closeRequired) OR a nativeReady whose facts
    /// do not evidence the full flush path. The shell MUST close; no barrier attestation.
    case requiresClose(receipt: SeekReceipt)
}

/// What anchored the current fence binding.
public enum SeekFenceAnchor: Sendable, Equatable {
    case initialOpen                 // actual provider currentBinding() read at attach (no seek yet)
    case committedSeek(SeekEventIdentity)  // an ACTUAL committed receipt, identity-bound
}
/// Explicit (provider identity, session, revision) fence binding. NEVER a numeric
/// coincidence with the pump's core revision: the two counters have independent
/// bases/epochs, so the mapping is recorded here from ACTUAL provider state, and
/// any mismatch fails closed (no binding -> nothing admits).
public struct SeekFenceBinding: Sendable, Equatable {
    public let source: SourceToken
    public let session: SeekSessionID
    public let providerRevision: SeekRevision
    public let anchor: SeekFenceAnchor
    /// A delivered event is playable ONLY under the exact binding: source identity,
    /// session, AND provider revision all match. Old-origin (pre-seek, retained or
    /// delayed) and cross-session events are rejected; the caller MUST releaseFrame
    /// every rejected handle exactly once.
    public func admits(_ origin: EventOrigin) -> Bool {
        origin.source == source && origin.session == session && origin.providerRevision == providerRevision
    }
}

/// M3 wiring outcome: the bridge result PLUS the pump-reset arbitration, with an explicit
/// recovery state. A committed provider seek whose pump reset is refused leaves the provider
/// advanced and the pump stale - resume is PROHIBITED (close or an explicit caller re-sync);
/// a ledger note alone would hide the inconsistency.
public enum ShellSeekWiringOutcome: Sendable {
    case committedAndReset(receipt: SeekReceipt)          // single pump bump published
    case committedButPumpRefused(receipt: SeekReceipt)    // resume PROHIBITED: close or re-sync
    case noChange                                         // noMutation / admissionRefused
    case requiresClose(receipt: SeekReceipt)              // poison / unattestable barrier
}

public final class ShellSeekBridge: @unchecked Sendable {
    private let driver = CoreSeekDriver()
    private let fenceLock = NSLock()
    private var fence: SeekFenceBinding?
    /// The current fence binding; nil fails closed (after poison/close or before attach).
    public var currentFence: SeekFenceBinding? { fenceLock.lock(); defer { fenceLock.unlock() }; return fence }
    public init() {}
    /// Attach to an OPEN provider: establishes the initial binding from the ACTUAL
    /// currentBinding() (initialOpen anchor). Returns false (fail closed) when the
    /// provider has no current binding.
    @discardableResult
    public func attach(to provider: any CoreSeekProvider) -> Bool {
        guard let b = provider.currentBinding() else { return false }
        fenceLock.lock()
        fence = SeekFenceBinding(source: b.token, session: b.session, providerRevision: b.revision, anchor: .initialOpen)
        fenceLock.unlock()
        return true
    }
    /// Validate a committed receipt against the provider's ACTUAL current binding:
    /// identity source, session, and nextRevision must all be current, else fail closed.
    private func bindCommitted(_ receipt: SeekReceipt, _ provider: any CoreSeekProvider) -> Bool {
        guard let b = provider.currentBinding(),
              b.token == receipt.identity.source,
              b.session == receipt.session,
              b.revision == receipt.nextRevision else { return false }
        fenceLock.lock()
        fence = SeekFenceBinding(source: b.token, session: b.session, providerRevision: b.revision,
                                 anchor: .committedSeek(receipt.identity))
        fenceLock.unlock()
        return true
    }
    private func clearFence() { fenceLock.lock(); fence = nil; fenceLock.unlock() }
    /// Call-time validation for the shell barrier: the current fence must exist, anchor a
    /// COMMITTED seek, AND still match the provider's ACTUAL current binding (source identity,
    /// session, revision). Anything less fails closed. Used by ShellFrameSource.coordinateSeek
    /// so a superseded or cross-session anchor can never attest a flush.
    public func fenceMatchesProvider(_ provider: any CoreSeekProvider) -> Bool {
        guard let f = currentFence, case .committedSeek = f.anchor,
              let b = provider.currentBinding(),
              b.token == f.source, b.session == f.session, b.revision == f.providerRevision
        else { return false }
        return true
    }
    /// True while a seek transaction is in flight (for shell UI gating).
    public var hasActiveSeek: Bool { driver.hasActiveTransaction }
    /// Core-initiated cancellation of the in-flight seek (user cancel during a held call).
    /// No-op when idle; provider arbitration decides cancel-vs-ready.
    public func cancelActiveSeek() { driver.requestCancellationOfActive() }

    public func seek(on provider: any CoreSeekProvider, position: RationalTime,
                     commitACK: @Sendable (SeekRevision, SeekReceipt) -> Void) async -> ShellSeekResult {
        switch await driver.seek(on: provider, position: position, commitACK: commitACK) {
        case .committed(let receipt):
            guard case .nativeReady(let facts) = receipt.outcome,
                  facts.flushObserved, facts.packetFeedReset,
                  facts.decoderReset, facts.packetAccountingReconciled else {
                clearFence(); return .requiresClose(receipt: receipt) // barrier not attestable: fail closed
            }
            guard bindCommitted(receipt, provider) else {
                clearFence(); return .requiresClose(receipt: receipt) // commit/binding mismatch: fail closed
            }
            return .committedFlushed(receipt: receipt, adoptRevision: receipt.nextRevision)
        case .noMutation(let receipt):
            return .noMutationCoreGated(receipt: receipt)   // revision unchanged: fence stays valid
        case .failedPoisoned(let receipt):
            clearFence(); return .requiresClose(receipt: receipt)
        case .admissionRefused(let reason):
            return .admissionRefused(reason: reason)
        }
    }
}

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+('private let fenceLock = NSLock()\nprivate var fence: SeekFenceBinding?\npublic init() {}\n' if cfg['source'].endswith('ShellSeekBridge.swift') else '')+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVPlaybackCore/ShellSeekBridge.swift",
  "markers": [
    "public var currentFence:",
    "public func attach("
  ],
  "wrapper": "public final class ShellSeekBridge",
  "support": "// GorAVSeekContract.swift v3 \u2014 shared seek contract, PROVIDER-ONLY scope (revise batch, v3 findings 1-8).\n// Placement: Sources/GorAVNativeProbeKit/GorAVSeekContract.swift (explicit-sources target; Package.swift\n// hunk by R2Y, sole Package.swift writer). Peer (goreda) sole-writes this file after Main's explicit start.\n// Scope: the provider (FFmpeg) boundary only. Global commit / display reanchor / first-out / core ACK are\n// NOT provider outcomes. NativeReady promises NATIVE REPOSITION + FLUSH ONLY - not target attainment,\n// not a decoded PTS, never a global commit.\n\nimport Foundation\n\n// MARK: - Errors\n\npublic enum SeekIssuanceError: Error, Sendable, Equatable {\n    case exhausted            // ID/revision/generation space exhausted; typed refusal, NEVER a wrap\n    case invalidIdentifier    // zero or otherwise invalid identity material\n}\n\npublic enum SeekTimeError: Error, Sendable, Equatable {\n    case invalidTimescale     // timescale <= 0: a TIME error, not an identity error\n    case overflow             // checked rational arithmetic overflow\n    case unknownOrigin        // conversion requested against an unknown stream origin\n    case targetBeforeOrigin   // negative-position target before the stream start origin\n}\n\n// MARK: - Identity (roles never conflated; identity is COMPOSITE source+transaction)\n\npublic struct SeekCorrelationID: Hashable, Sendable {\n    public let rawValue: UInt64   // nonzero\n    public let queueTurn: UInt64  // owned and minted solely by the core queue; provider stores/echoes only\n    public init(rawValue: UInt64, queueTurn: UInt64) throws {\n        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }\n        self.rawValue = rawValue\n        self.queueTurn = queueTurn\n    }\n}\n\npublic struct SeekTransactionID: Hashable, Sendable, Comparable {\n    public let rawValue: UInt64   // nonzero; meaningful only as part of SeekEventIdentity\n    public init(rawValue: UInt64) throws {\n        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }\n        self.rawValue = rawValue\n    }\n    public static func < (l: SeekTransactionID, r: SeekTransactionID) -> Bool { l.rawValue < r.rawValue }\n}\n\n/// Composite identity (finding 5): a transaction ID is unique only within its source. Every receipt,\n/// envelope and refusal that names a transaction names this composite.\npublic struct SeekEventIdentity: Hashable, Sendable {\n    public let source: SourceToken\n    public let transactionID: SeekTransactionID\n    public init(source: SourceToken, transactionID: SeekTransactionID) {\n        self.source = source\n        self.transactionID = transactionID\n    }\n}\n\n/// Provider-held, noncopyable, synchronized mint (finding 5). One instance per provider, held for the\n/// provider's lifetime; value-type copies cannot duplicate issuance. Saturates to an explicit exhausted\n/// state; never wraps.\npublic final class TransactionIDMint: @unchecked Sendable {  // NSLock-guarded mutable state\n    private let lock = NSLock()\n    private var next: UInt64 = 1\n    private var exhausted = false\n    public init() {}\n    public func issue() throws -> SeekTransactionID {\n        lock.lock(); defer { lock.unlock() }\n        guard !exhausted else { throw SeekIssuanceError.exhausted }\n        let id = try SeekTransactionID(rawValue: next)\n        if next == UInt64.max { exhausted = true } else { next += 1 }\n        return id\n    }\n}\n\npublic struct SeekSessionID: Hashable, Sendable {\n    public let rawValue: UInt64   // nonzero\n    public init(rawValue: UInt64) throws {\n        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }\n        self.rawValue = rawValue\n    }\n}\n\n/// Source identity: provider-minted instance + open generation starting at 1, incrementing per open,\n/// NEVER reset on reopen. Failed open consumes nothing and yields no token (typed error).\npublic struct SourceToken: Hashable, Sendable {\n    public let instanceID: UInt64      // nonzero; provider-minted, never caller-supplied\n    public let openGeneration: UInt64  // >= 1\n    public init(instanceID: UInt64, openGeneration: UInt64) throws {\n        guard instanceID != 0, openGeneration != 0 else { throw SeekIssuanceError.invalidIdentifier }\n        self.instanceID = instanceID\n        self.openGeneration = openGeneration\n    }\n}\n\n/// Sole construction path for genuine source tokens (finding 4): the provider mints BOTH the instance\n/// ID and the generation; caller-supplied instance IDs never establish identity. A failed open throws\n/// and consumes neither an instance ID nor a generation.\npublic protocol SourceTokenIssuing: Sendable {\n    func issueOpen() throws -> SourceToken\n}\n\npublic struct SeekRevision: Hashable, Sendable, Comparable {\n    public let rawValue: UInt64   // nonzero; 1 at open, first seek becomes 2\n    public static let atOpen = try! SeekRevision(rawValue: 1)\n    public init(rawValue: UInt64) throws {\n        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }\n        self.rawValue = rawValue\n    }\n    public func advanced() throws -> SeekRevision {\n        let (v, ov) = rawValue.addingReportingOverflow(1)\n        guard !ov, v != 0 else { throw SeekIssuanceError.exhausted }\n        return try SeekRevision(rawValue: v)\n    }\n    public static func < (l: SeekRevision, r: SeekRevision) -> Bool { l.rawValue < r.rawValue }\n}\n\n// MARK: - Time (integer rational; normalized equality+hash consistent with Comparable; checked math)\n\npublic struct RationalTime: Sendable {\n    public let value: Int64      // may be negative (negative stream origin)\n    public let timescale: Int32  // > 0\n    public init(value: Int64, timescale: Int32) throws {\n        guard timescale > 0 else { throw SeekTimeError.invalidTimescale }\n        self.value = value\n        self.timescale = timescale\n    }\n    /// Canonical form (reduced by gcd, positive timescale). Hash/equality are defined on this form.\n    public var normalized: RationalTime {\n        let mag = value.magnitude\n        let ts = UInt64(bitPattern: Int64(timescale))\n        var a = mag, b = ts\n        while b != 0 { let t = a % b; a = b; b = t }\n        let g = a == 0 ? 1 : a\n        let red = mag / g\n        let nv: Int64\n        if value < 0 { nv = red == (1 << 63) ? Int64.min : -Int64(red) } else { nv = Int64(red) }\n        let nts = Int32(ts / g)\n        return try! RationalTime(value: nv, timescale: nts)\n    }\n    /// Exact tick conversion for a REAL FFmpeg rational time_base (v4 delta 1): given a timebase\n    /// num/den (e.g. 1001/30000: num=1001, den=30000 ticks per second), returns\n    /// floor(value * den / (timescale * num)) - media-RELATIVE ticks from the stream start.\n    /// Two-limb wide intermediate arithmetic; mathematical floor exact for negatives; overflow-checked;\n    /// no Double, no dropped denominator. The caller then adds stream.start_time with a checked add\n    /// (unknown origin and negative relative targets are refused BEFORE mutation at tryBegin).\n    /// This is pure arithmetic - a successful av_seek_frame + flush does NOT prove exact or nearest\n    /// landing; only BACKWARD keyframe request is supported, exact/ceil/incompatible flags are\n    /// refused pre-mutation.\n    public func floorTicks(toTimebaseNumerator num: Int64, denominator den: Int64) throws -> Int64 {\n        guard num > 0, den > 0 else { throw SeekTimeError.invalidTimescale }\n        // Unsigned 128-bit long division using two standard-library UInt64 limbs. Both\n        // numerator (<2^127) and divisor (<2^95) fit without Int128 or OS-floor changes.\n        let product = value.magnitude.multipliedFullWidth(by: UInt64(den))\n        let divisor = UInt64(timescale).multipliedFullWidth(by: UInt64(num))\n        var remHigh: UInt64 = 0, remLow: UInt64 = 0\n        var qHigh: UInt64 = 0, qLow: UInt64 = 0\n        for bit in stride(from: 127, through: 0, by: -1) {\n            let incoming = bit >= 64 ? (product.high >> UInt64(bit - 64)) & 1 : (product.low >> UInt64(bit)) & 1\n            remHigh = (remHigh << 1) | (remLow >> 63)\n            remLow = (remLow << 1) | incoming\n            if remHigh > divisor.high || (remHigh == divisor.high && remLow >= divisor.low) {\n                let (low, borrow) = remLow.subtractingReportingOverflow(divisor.low)\n                remLow = low\n                remHigh = remHigh - divisor.high - (borrow ? 1 : 0)\n                if bit >= 64 { qHigh |= UInt64(1) << UInt64(bit - 64) }\n                else { qLow |= UInt64(1) << UInt64(bit) }\n            }\n        }\n        guard qHigh == 0 else { throw SeekTimeError.overflow }\n        if value >= 0 {\n            guard qLow <= UInt64(Int64.max) else { throw SeekTimeError.overflow }\n            return Int64(qLow)\n        }\n        let hasRemainder = remHigh != 0 || remLow != 0\n        let limit = UInt64(1) << 63\n        guard qLow <= limit, !(qLow == limit && hasRemainder) else { throw SeekTimeError.overflow }\n        if qLow == limit { return Int64.min }\n        return hasRemainder ? -Int64(qLow) - 1 : -Int64(qLow)\n    }\n    /// Absolute film PTS -> media-relative seek seconds, using the actual\n    /// stream origin. Exact checked rational subtraction, never Double-only\n    /// arithmetic or independently rounded operands. The real timebase is\n    /// validated and the eventual provider tick+origin conversion is preflighted\n    /// before a staged decoder can mutate. Negative origins are legal.\n    public func mediaRelativePosition(streamOrigin: RationalTime?,\n                                      streamTimebase: RationalTime) throws -> RationalTime {\n        guard let origin = streamOrigin else { throw SeekTimeError.unknownOrigin }\n        guard streamTimebase.value > 0 else { throw SeekTimeError.invalidTimescale }\n        guard self >= origin else { throw SeekTimeError.targetBeforeOrigin }\n        let lhs = self.normalized, rhs = origin.normalized\n        func gcd(_ x: UInt64, _ y: UInt64) -> UInt64 {\n            var a=x, b=y\n            while b != 0 { let r=a % b; a=b; b=r }\n            return a\n        }\n        let common = Int64(gcd(UInt64(lhs.timescale), UInt64(rhs.timescale)))\n        let leftFactor = Int64(rhs.timescale) / common\n        let rightFactor = Int64(lhs.timescale) / common\n        let (a, overflowA) = lhs.value.multipliedReportingOverflow(by:leftFactor)\n        let (b, overflowB) = rhs.value.multipliedReportingOverflow(by:rightFactor)\n        let (numerator, overflowN) = a.subtractingReportingOverflow(b)\n        let (denominator, overflowD) = Int64(lhs.timescale).multipliedReportingOverflow(by:leftFactor)\n        guard !overflowA, !overflowB, !overflowN, !overflowD, denominator > 0 else {\n            throw SeekTimeError.overflow\n        }\n        let divisor = gcd(numerator.magnitude, UInt64(denominator))\n        let reducedDen = denominator / Int64(divisor)\n        guard reducedDen <= Int64(Int32.max) else { throw SeekTimeError.overflow }\n        let relative = try RationalTime(value:numerator / Int64(divisor), timescale:Int32(reducedDen))\n        let delta = try relative.floorTicks(toTimebaseNumerator:streamTimebase.value,\n                                          denominator:Int64(streamTimebase.timescale))\n        let originTicks = try origin.floorTicks(toTimebaseNumerator:streamTimebase.value,\n                                               denominator:Int64(streamTimebase.timescale))\n        _ = try RationalTime.checkedOriginSum(deltaTicks:delta,startTimeTicks:originTicks)\n        return relative\n    }\n\n    /// Convenience for integral timescales (1 second = ts ticks), same checked semantics.\n    public func floorTicks(toTimescale ts: Int32) throws -> Int64 {\n        try floorTicks(toTimebaseNumerator: 1, denominator: Int64(ts))\n    }\n    /// Checked composition with the stream origin: deltaTicks + startTimeTicks, overflow-checked.\n    /// Unknown origin is refused by the caller pre-mutation; a negative ORIGIN is legal here.\n    public static func checkedOriginSum(deltaTicks: Int64, startTimeTicks: Int64) throws -> Int64 {\n        let (v, ov) = deltaTicks.addingReportingOverflow(startTimeTicks)\n        guard !ov else { throw SeekTimeError.overflow }\n        return v\n    }\n    /// Checked conversion to a target timescale (floor on inexact), negative-safe.\n    public func rescaled(to ts: Int32) throws -> RationalTime {\n        let ticks = try floorTicks(toTimescale: ts)\n        return try RationalTime(value: ticks, timescale: ts)\n    }\n}\n\nextension RationalTime: Equatable {\n    /// Cross-product equality on 128-bit products: a/b == c/d  <=>  a*d == c*b (b,d > 0).\n    /// Agrees with `normalized`-based hashing: equal rationals normalize identically.\n    public static func == (l: RationalTime, r: RationalTime) -> Bool {\n        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))\n        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))\n        return lp.high == rp.high && lp.low == rp.low\n    }\n}\n\nextension RationalTime: Hashable {\n    public func hash(into hasher: inout Hasher) {\n        let n = normalized\n        hasher.combine(n.value)\n        hasher.combine(n.timescale)\n    }\n}\n\nextension RationalTime: Comparable {\n    /// 128-bit cross-product comparison; exact for all inputs including negative origins.\n    /// Consistent with Equatable: neither-less implies ==. No Double anywhere.\n    public static func < (l: RationalTime, r: RationalTime) -> Bool {\n        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))\n        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))\n        if lp.high != rp.high { return lp.high < rp.high }\n        return lp.low < rp.low\n    }\n}\n\n// MARK: - Target coordinate (finding 1: ONE coordinate, explicit)\n\n/// The single target coordinate: MEDIA-RELATIVE rational seconds from the stream start (v4 delta 1).\n/// Conversion: deltaTicks = position.floorTicks(toTimebaseNumerator: tb.num, denominator: tb.den)\n/// for the stream's real rational time_base, then RationalTime.checkedOriginSum(deltaTicks:,\n/// startTimeTicks: origin). A NEGATIVE relative target (before stream start) is rejected\n/// (SeekTimeError.targetBeforeOrigin) BEFORE mutation; a negative ORIGIN is legal and exact; an\n/// UNKNOWN origin is refused BEFORE mutation. Only BACKWARD keyframe request is supported:\n/// exact/ceil/incompatible flags are refused PRE-MUTATION (tryBegin, .unsupported); av_seek_frame\n/// BACKWARD + flush does not prove exact or nearest landing. A post-mutation miss is NEVER noMutation.\npublic enum SeekRounding: String, Sendable {\n    case exact           // land on the exact tick or refuse PRE-MUTATION\n    case floorToKeyframe // BACKWARD request only; nearest/exact landing is not promised\n    case ceilToKeyframe  // nearest keyframe at or after the converted tick\n}\n\npublic struct SeekTarget: Sendable {\n    public let position: RationalTime      // media-timeline seconds (the ONE coordinate)\n    public let rounding: SeekRounding\n    public let requestedFlags: Int32       // whitelisted AVSEEK_FLAG_* bits; actual use recorded in facts\n    public init(position: RationalTime, rounding: SeekRounding, requestedFlags: Int32) {\n        self.position = position\n        self.rounding = rounding\n        self.requestedFlags = requestedFlags\n    }\n}\n\n// MARK: - Request\n\npublic struct SeekRequest: Sendable {\n    public let correlationID: SeekCorrelationID\n    public let session: SeekSessionID\n    public let source: SourceToken\n    public let target: SeekTarget\n    /// Core's expected current provider revision; provider validates expected == actual at queue-turn\n    /// (mismatch => .stale) and computes next = expected.advanced().\n    public let expectedRevision: SeekRevision\n    public init(correlationID: SeekCorrelationID, session: SeekSessionID, source: SourceToken,\n                target: SeekTarget, expectedRevision: SeekRevision) {\n        self.correlationID = correlationID\n        self.session = session\n        self.source = source\n        self.target = target\n        self.expectedRevision = expectedRevision\n    }\n}\n\n// MARK: - Descriptor + discovery (finding 4)\n\n/// Renamed (finding 4): GorAVCore and NativeProbeKit both declare SourceDescriptor; this contract's\n/// descriptor is SeekSourceDescriptor to keep decoder/open call sites unambiguous when a caller\n/// imports both modules.\npublic struct SeekSourceDescriptor: Sendable {\n    public let source: SourceToken\n    public let seekable: Bool\n    public let originKnown: Bool\n    public let startOrigin: RationalTime?    // nil == unknown origin; conversions then refuse\n    public let duration: RationalTime?\n    public let videoStreamIndex: Int32?\n    public let streamTimebase: RationalTime?\n    public init(source: SourceToken, seekable: Bool, originKnown: Bool, startOrigin: RationalTime?,\n                duration: RationalTime?, videoStreamIndex: Int32?, streamTimebase: RationalTime?) {\n        self.source = source\n        self.seekable = seekable\n        self.originKnown = originKnown\n        self.startOrigin = startOrigin\n        self.duration = duration\n        self.videoStreamIndex = videoStreamIndex\n        self.streamTimebase = streamTimebase\n    }\n}\n\npublic struct SeekCapabilities: Sendable {\n    public let seekable: Bool\n    public let supportedRoundings: Set<SeekRounding>\n    public let supportedFlags: Int32\n    public let originKnown: Bool\n    public init(seekable: Bool, supportedRoundings: Set<SeekRounding>, supportedFlags: Int32,\n                originKnown: Bool) {\n        self.seekable = seekable\n        self.supportedRoundings = supportedRoundings\n        self.supportedFlags = supportedFlags\n        self.originKnown = originKnown\n    }\n}\n\n/// Queue-owned, NON-BLOCKING open-binding discovery (finding 4): the genuine current source token,\n/// session and revision, plus capability advertisement. tryBegin never blocks on discovery.\npublic protocol SeekProviderDiscovery: Sendable {\n    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?\n    func capabilities() -> SeekCapabilities\n}\n\n// MARK: - Typed refusals (admission-time ONLY; after admission every outcome is a receipt)\n\npublic enum SeekRefusal: Error, Sendable, Equatable {\n    case busy(active: SeekEventIdentity)                     // active slot occupied; busy is observable\n    case exhausted                                           // ID/revision/generation exhaustion; no wrap\n    case stale(expected: SeekRevision, actual: SeekRevision) // revision mismatch at queue-turn\n    case unsupported(String)                                 // incl. exact/ceil/flags refused PRE-MUTATION\n    case closed                                              // session/source closed\n    case legacyRejected(reason: String)                      // unenveloped/legacy event or handle refused\n    case alreadyExecuted                                     // the ONLY post-admission throwing misuse\n}\n\n// MARK: - Provider stages, arbitration, mutation facts\n\npublic enum ProviderSeekStage: String, Sendable {\n    case reserved, preSeek, inNativeSeek, nativeReturned, cleanedUp, receipted, retired\n}\n\n/// Cancel-vs-NativeReady arbitration: the FIRST recorded event wins; recorded once, never rewritten.\n/// Kept SEPARATE from the actual reached cleanup stage (finding 8).\npublic enum SeekArbitration: String, Sendable {\n    case none, cancellationRequested, nativeReadyObserved\n}\n\npublic struct NativeSeekFacts: Sendable {\n    public let avSeekReturn: Int32?              // actual av_seek_frame return code; nil if never entered\n    public let flagsApplied: Int32\n    public let resolvedStreamIndex: Int32?\n    public let requestedTicks: Int64?            // target after origin+timebase conversion\n    public let resolvedStreamTimebase: RationalTime?\n    public let startOriginTicks: Int64?          // may be negative\n    public let flushObserved: Bool\n    public let packetFeedReset: Bool             // feed reset actually performed\n    public let decoderReset: Bool\n    public let packetsReleased: Int?             // explicit packet release count (nil if no mutation)\n    public let packetAccountingReconciled: Bool  // admission/release ledger reconciled\n    public init(avSeekReturn: Int32?, flagsApplied: Int32, resolvedStreamIndex: Int32?,\n                requestedTicks: Int64?, resolvedStreamTimebase: RationalTime?,\n                startOriginTicks: Int64?, flushObserved: Bool, packetFeedReset: Bool,\n                decoderReset: Bool, packetsReleased: Int?, packetAccountingReconciled: Bool) {\n        self.avSeekReturn = avSeekReturn\n        self.flagsApplied = flagsApplied\n        self.resolvedStreamIndex = resolvedStreamIndex\n        self.requestedTicks = requestedTicks\n        self.resolvedStreamTimebase = resolvedStreamTimebase\n        self.startOriginTicks = startOriginTicks\n        self.flushObserved = flushObserved\n        self.packetFeedReset = packetFeedReset\n        self.decoderReset = decoderReset\n        self.packetsReleased = packetsReleased\n        self.packetAccountingReconciled = packetAccountingReconciled\n    }\n}\n\npublic enum MutationState: String, Sendable {\n    case none, partial, completedClean\n}\n\n/// Recovery paths (finding 8): nativeReady is the ONLY notRequired outcome and the ONLY one that\n/// advances the revision and permits new output. Partial mutation, post-mutation cancellation and\n/// session-IO escalation ALL require closeRequired - no flushOnly/resume loophole, no new seek or\n/// reopen on the same session.\npublic enum RecoveryPath: String, Sendable {\n    case notRequired    // nativeReady only\n    case closeRequired  // mandatory for any mutated non-nativeReady outcome and session-IO escalation\n}\n\npublic struct PoisonReport: Sendable {\n    public let recoveryRequired: Bool   // true whenever mutation != .none and outcome != nativeReady\n    public let recoveryPath: RecoveryPath\n    public let detail: String\n    public init(recoveryRequired: Bool, recoveryPath: RecoveryPath, detail: String) {\n        self.recoveryRequired = recoveryRequired\n        self.recoveryPath = recoveryPath\n        self.detail = detail\n    }\n    /// Invariant helpers: the only two legal combinations for a mutated non-nativeReady outcome.\n    public static let cleanNativeReady = PoisonReport(recoveryRequired: false, recoveryPath: .notRequired, detail: \"\")\n    public static func closeRequired(_ detail: String) -> PoisonReport {\n        PoisonReport(recoveryRequired: true, recoveryPath: .closeRequired, detail: detail)\n    }\n}\n\npublic enum ResumePolicy: String, Sendable {\n    case resumeFromNativePosition // nativeReady only (provider success)\n    case unchangedCoreGated       // noMutation outcomes: position/revision unchanged; the CORE gates\n    case closedRequired           // every mutated non-nativeReady outcome\n}\n\npublic enum SeekFailureReason: Sendable, Equatable {\n    case avError(code: Int32)\n    case streamResolutionFailed\n    case interruptCancelled\n    case poisonedState\n    case sessionClosed\n    case descriptorUnsupported(String)\n}\n\n// MARK: - Receipt (exactly one immutable completion per ADMITTED reservation; never throws)\n\npublic struct SeekReceipt: Sendable {\n    /// Why an ADMITTED reservation was refused at queue-turn WITHOUT mutation (v4 delta 2).\n    /// Distinct from cancellation: the caller did not ask to cancel; the provider refused.\n    public enum NoMutationRefusal: Sendable, Equatable {\n        case stale(expected: SeekRevision, actual: SeekRevision)\n        case closed\n        case unsupported(String)\n    }\n    /// Why an admitted reservation was cancelled WITHOUT mutation.\n    public enum CancelReason: String, Sendable {\n        case requested   // explicit requestCancellation before execute\n        case abandoned   // handle released without execute/cancel: lease-release settlement, no orphan\n        case close       // close() settlement before execute\n    }\n    public enum Outcome: Sendable {\n        /// Provider completion evidence ONLY: native reposition + flush promised, revision advances,\n        /// new output permitted. NOT target attainment, NOT a decoded PTS, NOT a global commit/ACK.\n        /// The ONLY outcome that advances nextRevision.\n        case nativeReady(facts: NativeSeekFacts)\n        /// Admitted, then REFUSED at queue-turn before any mutation: position and revision UNCHANGED.\n        /// Resume is CORE-GATED (the core decides the next action) - NOT a provider success signal.\n        case refusedNoMutation(reason: NoMutationRefusal)\n        /// Caller-side settlement before any mutation (requested/abandoned/close). Position and\n        /// revision UNCHANGED; resume is CORE-GATED. Exactly-one reservation release.\n        case cancelledNoMutation(reason: CancelReason)\n        /// Post-mutation cancel: native call ran to its own return, cleanup completed with resources\n        /// alive. Poison is MANDATORY and is always closeRequired.\n        case cancelledAfterCleanup(facts: NativeSeekFacts, poison: PoisonReport)\n        /// Typed staged failure at the ACTUAL stage; poison MANDATORY, closeRequired when mutated.\n        case failed(stage: ProviderSeekStage, reason: SeekFailureReason,\n                    facts: NativeSeekFacts, poison: PoisonReport)\n    }\n    public let identity: SeekEventIdentity       // composite source+transaction\n    public let correlationID: SeekCorrelationID\n    public let session: SeekSessionID\n    public let request: SeekRequest              // original target preserved verbatim\n    public let previousRevision: SeekRevision\n    public let nextRevision: SeekRevision        // advanced ONLY on nativeReady\n    public let reachedStage: ProviderSeekStage   // actual cleanup stage reached\n    public let arbitration: SeekArbitration      // first-recorded winner; separate from reachedStage\n    public let mutation: MutationState\n    public let resumePolicy: ResumePolicy\n    public let outcome: Outcome\n    public init(identity: SeekEventIdentity, correlationID: SeekCorrelationID, session: SeekSessionID,\n                request: SeekRequest, previousRevision: SeekRevision, nextRevision: SeekRevision,\n                reachedStage: ProviderSeekStage, arbitration: SeekArbitration, mutation: MutationState,\n                resumePolicy: ResumePolicy, outcome: Outcome) {\n        self.identity = identity\n        self.correlationID = correlationID\n        self.session = session\n        self.request = request\n        self.previousRevision = previousRevision\n        self.nextRevision = nextRevision\n        self.reachedStage = reachedStage\n        self.arbitration = arbitration\n        self.mutation = mutation\n        self.resumePolicy = resumePolicy\n        self.outcome = outcome\n    }\n}\n\n// MARK: - Transaction handle (finding 7: after admission, NO throwing paths except duplicate execute)\n\n/// Ownership and completion invariants:\n/// - tryBegin admission is the only gate that refuses; every ADMITTED reservation produces exactly\n///   one immutable SeekReceipt - including queue-time stale/closed discovery after admission,\n///   cancel-before-execute, abandonment, and close settlement.\n/// - execute() moves reserved -> in-flight exactly once; the ONLY throwing misuse is a duplicate\n///   execute (.alreadyExecuted).\n/// - completion() NEVER throws; repeated calls return the SAME receipt value. Calling it before\n///   execute is legal: it suspends until execute, cancellation, abandonment or close settles the\n///   transaction (no wait-forever: requestCancellation() or close() always settles a pre-execute\n///   transaction as cancelledNoMutation). Abandonment is settlement by lease release: dropping an\n///   un-executed handle is collected and completed as cancelledNoMutation(.abandoned) - never an\n///   orphaned reservation.\n/// - requestCancellation() is a REQUEST: pre-mutation => cancelledNoMutation; post-entry => the\n///   native call is never abandoned/freed/reopened/superseded while active; after it returns,\n///   cleanup completes with resources alive; receipt is cancelledAfterCleanup or failed.\npublic protocol SeekTransaction: Sendable {\n    var identity: SeekEventIdentity { get }\n    var correlationID: SeekCorrelationID { get }\n    var session: SeekSessionID { get }\n    var request: SeekRequest { get }\n    /// Provider-issued reserved revision (= expectedRevision.advanced() as validated at queue-turn).\n    /// PINNED HANDSHAKE (finding 2): the provider validates expected and computes next; the core\n    /// ADOPTS this issued value before execute and does not hold a separately reserved revision.\n    var reservedRevision: SeekRevision { get }\n    func execute() throws\n    func completion() async -> SeekReceipt\n    func requestCancellation()\n}\n\n// MARK: - Provider surface\n\npublic protocol SeekProviding: Sendable {\n    func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor\n    /// Admits at most one active transaction. Checks expectedRevision at queue-turn (.stale),\n    /// capabilities (.unsupported PRE-MUTATION), slot (.busy). Throws SeekRefusal; after admission\n    /// the transaction ALWAYS completes via a receipt.\n    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction\n    var activeTransaction: SeekEventIdentity? { get }\n    /// Close ownership: provider-owned, exactly-once. Waits for any in-flight native call to return,\n    /// then for outstanding retained-handle copy/release turns; completes every admitted-but-unsettled\n    /// transaction exactly once (pre-mutation as cancelledNoMutation; in-flight after native return\n    /// and cleanup as cancelledAfterCleanup or failed). No late continuation runs after close; no\n    /// use-after-free. After close, all calls throw .closed and the event stream ends with .closed.\n    func close() async throws\n}\n\n// MARK: - Provider events (finding 6: envelope the CONCRETE DecodeEvent surface + bound sentinels)\n\npublic enum RequestOrigin: Sendable, Hashable {\n    case initialOpen\n    case transaction(SeekTransactionID)   // composite with EventOrigin.source\n}\n\npublic struct EventOrigin: Sendable, Hashable {\n    public let session: SeekSessionID\n    public let source: SourceToken\n    public let providerRevision: SeekRevision\n    public let requestOrigin: RequestOrigin\n    public init(session: SeekSessionID, source: SourceToken, providerRevision: SeekRevision,\n                requestOrigin: RequestOrigin) {\n        self.session = session\n        self.source = source\n        self.providerRevision = providerRevision\n        self.requestOrigin = requestOrigin\n    }\n}\n\n/// The provider event stream: every variant of the concrete DecodeEvent surface, origin-bound, plus\n/// explicit drained/closed sentinels. The read API never answers an untagged nil end: the stream\n/// terminates only AFTER a terminal sentinel (endOfStream or failed or interrupted), then .drained\n/// once all delivered handles are released or accounted, then .closed at close. Mixed legacy policy:\n/// any event or handle lacking a full EventOrigin is REFUSED with .legacyRejected - never retagged.\npublic enum SeekProviderEvent<Frame: Sendable>: Sendable {\n    case opened(EventOrigin, videoCodec: String, width: Int, height: Int)\n    case frameDecoded(EventOrigin, Frame)\n    case endOfStream(EventOrigin)\n    case interrupted(EventOrigin)\n    case failed(EventOrigin, code: Int32, summary: String)\n    case feedSaturated(EventOrigin, pendingPackets: Int)\n    case drained(EventOrigin)\n    case closed(EventOrigin)\n}\n\npublic protocol SeekEventReading: Sendable {\n    associatedtype Frame: Sendable\n    /// Suspends until the next event; the stream ends after .closed (subsequent calls return .closed).\n    func nextEvent() async -> SeekProviderEvent<Frame>\n}\n\n/// Retained old-handle rule (finding 6): a retained handle stays copyable, readable and releasable\n/// after a seek WHILE THE SAME OPEN GENERATION remains alive - this is generation-bound, NOT\n/// seek-revision-bound. Release is exactly-once per handle.\npublic struct RetainedHandleMetadata: Sendable {\n    public let origin: EventOrigin\n    public let validWhileOpenGeneration: UInt64   // == origin.source.openGeneration\n    public let releaseRequired: Bool\n    public init(origin: EventOrigin, validWhileOpenGeneration: UInt64, releaseRequired: Bool) {\n        self.origin = origin\n        self.validWhileOpenGeneration = validWhileOpenGeneration\n        self.releaseRequired = releaseRequired\n    }\n}\n\n// MARK: - Interrupts (two kinds, two lifetimes)\n\npublic enum InterruptKind: String, Sendable {\n    case requestCancel  // per-request; lifetime: until that request's receipt\n    case sessionIO      // sticky UNTIL close/recovery; never reset by a new operation; closeRequired\n}\n\npublic struct InterruptState: Sendable {\n    public let kind: InterruptKind\n    public let raisedBy: SeekEventIdentity?\n    public let activeIOObserving: Bool\n    public init(kind: InterruptKind, raisedBy: SeekEventIdentity?, activeIOObserving: Bool) {\n        self.kind = kind\n        self.raisedBy = raisedBy\n        self.activeIOObserving = activeIOObserving\n    }\n}\n\n// Cleanup ordering rule (contractual): post-mutation cleanup runs AFTER the native call returns,\n// with provider resources alive; never concurrently with an executing FFmpeg call.\n\n// MARK: - Provider transaction state machine\n// Synchronization is scoped to state snapshots. No native call, continuation resume,\n// user executor or await runs while this lock is held.\npublic final class ProviderSeekReservation: @unchecked Sendable {\n    public let identity: SeekEventIdentity\n    public let request: SeekRequest\n    public let reservedRevision: SeekRevision\n    fileprivate var executed = false\n    fileprivate var enteredNative = false\n    fileprivate var cancellation: SeekReceipt.CancelReason?\n    fileprivate var result: SeekReceipt?\n    fileprivate var waiters: [CheckedContinuation<SeekReceipt, Never>] = []\n    fileprivate init(identity: SeekEventIdentity, request: SeekRequest, revision: SeekRevision) {\n        self.identity = identity; self.request = request; self.reservedRevision = revision\n    }\n}\n\npublic final class ProviderSeekCoordinator: @unchecked Sendable {\n    private let lock = NSLock()\n    private let mint = TransactionIDMint()\n    private var active: ProviderSeekReservation?\n    private var closing = false\n    private var poisoned = false\n    private var coordinated = false\n    private var legacyUsed = false\n    private var binding: (SourceToken, SeekSessionID, SeekRevision)?\n    private var descriptorValue: SeekSourceDescriptor?\n    private var capabilityValue = SeekCapabilities(seekable: false, supportedRoundings: [], supportedFlags: 0, originKnown: false)\n    private var lastCorrelation: UInt64 = 0\n    public init() {}\n    private func locked<T>(_ body: () throws -> T) rethrows -> T {\n        lock.lock(); defer { lock.unlock() }; return try body()\n    }\n    // Called only after a successful native open. Token issuance is owned by the decoder.\n    public func opened(token: SourceToken, session: SeekSessionID, descriptor: SeekSourceDescriptor,\n                       capabilities: SeekCapabilities) {\n        locked {\n            precondition(active == nil)\n            binding = (token, session, .atOpen); descriptorValue = descriptor\n            capabilityValue = capabilities; closing = false; poisoned = false\n            coordinated = false; legacyUsed = false; lastCorrelation = 0\n        }\n    }\n    public func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)? {\n        locked { guard !closing, !poisoned, let b = binding else { return nil }; return (b.0,b.1,b.2) }\n    }\n    public func capabilities() -> SeekCapabilities { locked { capabilityValue } }\n    public func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor {\n        try locked {\n            guard !closing, !poisoned, let d = descriptorValue, d.source == source else { throw SeekRefusal.closed }\n            return d\n        }\n    }\n    public var activeTransaction: SeekEventIdentity? { locked { active?.identity } }\n    public var isCoordinated: Bool { locked { coordinated } }\n    /// A source open chooses legacy or enveloped mode once. No retagging of legacy work.\n    public func claimLegacy() -> Bool {\n        locked {\n            guard !coordinated, active == nil, !closing, !poisoned else { return false }\n            legacyUsed = true; return true\n        }\n    }\n    public func matches(session: UInt64) -> Bool { locked { binding?.1.rawValue == session } }\n    public var outputAllowed: Bool { locked { !closing && !poisoned && active == nil } }\n    public var isClosingOrPoisoned: Bool { locked { closing || poisoned } }\n    /// Activates coordinated event mode before the first pull. Cannot downgrade until a new open.\n    public func activateEvents() throws {\n        try locked {\n            guard !closing, !poisoned, binding != nil else { throw SeekRefusal.closed }\n            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: \"legacy mode already used for this open\") }\n            coordinated = true\n        }\n    }\n    public func tryBegin(_ request: SeekRequest,\n                         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) throws -> any SeekTransaction {\n        let r: ProviderSeekReservation = try locked {\n            guard !closing, !poisoned, let b = binding,\n                  b.0 == request.source, b.1 == request.session else { throw SeekRefusal.closed }\n            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: \"legacy mode already used for this open\") }\n            if let a = active { throw SeekRefusal.busy(active: a.identity) }\n            guard request.expectedRevision == b.2 else { throw SeekRefusal.stale(expected: request.expectedRevision, actual: b.2) }\n            guard request.correlationID.rawValue > lastCorrelation else { throw SeekRefusal.unsupported(\"replayed correlation\") }\n            guard capabilityValue.seekable, capabilityValue.originKnown,\n                  request.target.rounding == .floorToKeyframe,\n                  request.target.requestedFlags & ~Int32(1) == 0 else { throw SeekRefusal.unsupported(\"unsupported seek target or flags\") }\n            guard request.target.position.value >= 0 else { throw SeekTimeError.targetBeforeOrigin }\n            let next = try b.2.advanced()\n            let id = try mint.issue()\n            let value = ProviderSeekReservation(identity: SeekEventIdentity(source: b.0, transactionID: id), request: request, revision: next)\n            coordinated = true; lastCorrelation = request.correlationID.rawValue; active = value\n            return value\n        }\n        return ProviderSeekHandle(owner: self, record: r, executor: executor)\n    }\n    fileprivate func execute(_ r: ProviderSeekReservation,\n                             executor: @Sendable (ProviderSeekReservation) -> Void) throws {\n        try locked {\n            guard active === r, r.result == nil, !r.executed else { throw SeekRefusal.alreadyExecuted }\n            r.executed = true\n        }\n        executor(r)\n    }\n    /// Linearizes native entry against cancellation. A cancellation after this point is\n    /// conservatively post-entry even if the native function has not yet made its first mutation.\n    public func enterNative(_ r: ProviderSeekReservation) -> Bool {\n        locked {\n            guard active === r, r.result == nil, r.cancellation == nil, !closing, !poisoned else { return false }\n            r.enteredNative = true; return true\n        }\n    }\n    public func cancellationRequested(_ r: ProviderSeekReservation) -> Bool {\n        locked { r.cancellation != nil || closing }\n    }\n    public func queueRefusal(_ r: ProviderSeekReservation) -> SeekReceipt.NoMutationRefusal? {\n        locked {\n            guard !closing, !poisoned, let b = binding, b.0 == r.request.source,\n                  b.1 == r.request.session else { return .closed }\n            guard b.2 == r.request.expectedRevision else { return .stale(expected: r.request.expectedRevision, actual: b.2) }\n            return nil\n        }\n    }\n    public func cancel(_ r: ProviderSeekReservation, reason: SeekReceipt.CancelReason = .requested) {\n        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []\n        var completed: SeekReceipt?\n        locked {\n            guard r.result == nil else { return }\n            if r.cancellation == nil { r.cancellation = reason }\n            if !r.executed {\n                let receipt = noMutation(r, outcome: .cancelledNoMutation(reason: r.cancellation!), arbitration: .cancellationRequested)\n                r.result = receipt; completed = receipt\n                continuations = r.waiters; r.waiters = []\n                if active === r { active = nil }\n            }\n        }\n        if let completed { for c in continuations { c.resume(returning: completed) } }\n    }\n    private func noMutation(_ r: ProviderSeekReservation, outcome: SeekReceipt.Outcome,\n                            arbitration: SeekArbitration) -> SeekReceipt {\n        SeekReceipt(identity: r.identity, correlationID: r.request.correlationID, session: r.request.session,\n                    request: r.request, previousRevision: r.request.expectedRevision,\n                    nextRevision: r.request.expectedRevision, reachedStage: .preSeek,\n                    arbitration: arbitration, mutation: .none, resumePolicy: .unchangedCoreGated, outcome: outcome)\n    }\n    /// Single linearization point for cancellation versus nativeReady. The builder is a pure value\n    /// constructor; native work MUST already have returned and cleanup must already be complete.\n    public func finish(_ r: ProviderSeekReservation,\n                       build: (Bool) -> SeekReceipt) {\n        finishWithSnapshot(r) { build($0.recordedCancel != nil || $0.closing || $0.poisoned) }\n    }\n    /// Immutable settlement state, captured UNDER the coordinator lock inside the SAME critical\n    /// region that settles. The ONLY cross-module read path for pre-entry settlement\n    /// classification: no unsynchronized reservation getter, no Bool that cannot distinguish\n    /// closing from poisoned, no recursive lock acquisition inside the builder.\n    public struct SettlementSnapshot: Sendable, Equatable {\n        public let recordedCancel: SeekReceipt.CancelReason?   // first-recorded reason (existing rule: record once)\n        public let closing: Bool\n        public let poisoned: Bool\n    }\n    /// finish variant whose builder receives the atomic snapshot taken in the settlement's own\n    /// critical region - classification cannot observe a state the settlement did not. Distinct\n    /// name (not an overload): no trailing-closure ambiguity against finish(_:build:).\n    public func finishWithSnapshot(_ r: ProviderSeekReservation,\n                                   build: (SettlementSnapshot) -> SeekReceipt) {\n        var receipt: SeekReceipt?\n        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []\n        locked {\n            guard r.result == nil, active === r else { return }\n            let snap = SettlementSnapshot(recordedCancel: r.cancellation, closing: closing, poisoned: poisoned)\n            let value = build(snap)\n            precondition(value.identity == r.identity && value.session == r.request.session)\n            if case .nativeReady = value.outcome {\n                precondition(value.mutation == .completedClean && value.nextRevision == r.reservedRevision)\n                if let b = binding { binding = (b.0,b.1,r.reservedRevision) }\n            } else if value.mutation != .none { poisoned = true }\n            r.result = value; receipt = value\n            continuations = r.waiters; r.waiters = []; active = nil\n        }\n        if let receipt { for c in continuations { c.resume(returning: receipt) } }\n    }\n    public func waitUntilSettled() async {\n        let record = locked { active }\n        if let record { _ = await completion(record) }\n    }\n    fileprivate func completion(_ r: ProviderSeekReservation) async -> SeekReceipt {\n        await withCheckedContinuation { c in\n            let value: SeekReceipt? = locked {\n                if let v = r.result { return v }\n                r.waiters.append(c); return nil\n            }\n            if let value { c.resume(returning: value) }\n        }\n    }\n    /// Session I/O escalation invalidates output immediately. The decoder separately raises the\n    /// matching session interrupt while native state stays retained until native return/close.\n    public func poisonSession() { locked { poisoned = true } }\n    public func requestClose() {\n        // Atomic flag+record (peer NH6 2/2): the closing flag and the active record's .close reason\n        // are set under ONE lock, so a settlement can never observe closing=true with no recorded\n        // reason. First-recorded-wins preserved: a prior caller reason is never overwritten.\n        let r = locked { () -> ProviderSeekReservation? in\n            closing = true\n            if let a = active, a.result == nil, a.cancellation == nil { a.cancellation = .close }\n            return active\n        }\n        if let r { cancel(r, reason: .close) }\n    }\n}\n\nprivate final class ProviderSeekHandle: SeekTransaction, @unchecked Sendable {\n    private let owner: ProviderSeekCoordinator\n    private let record: ProviderSeekReservation\n    private let executor: @Sendable (ProviderSeekReservation) -> Void\n    init(owner: ProviderSeekCoordinator, record: ProviderSeekReservation,\n         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) {\n        self.owner = owner; self.record = record; self.executor = executor\n    }\n    var identity: SeekEventIdentity { record.identity }\n    var correlationID: SeekCorrelationID { record.request.correlationID }\n    var session: SeekSessionID { record.request.session }\n    var request: SeekRequest { record.request }\n    var reservedRevision: SeekRevision { record.reservedRevision }\n    func execute() throws { try owner.execute(record, executor: executor) }\n    func completion() async -> SeekReceipt { await owner.completion(record) }\n    func requestCancellation() { owner.cancel(record) }\n    deinit { owner.cancel(record, reason: .abandoned) }\n}\n\npublic protocol CoreSeekProvider: Sendable {\n    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?\n    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction\n}\npublic enum SeekFenceAnchor: Sendable, Equatable {\n    case initialOpen                 // actual provider currentBinding() read at attach (no seek yet)\n    case committedSeek(SeekEventIdentity)  // an ACTUAL committed receipt, identity-bound\n}\npublic struct SeekFenceBinding: Sendable, Equatable {\n    public let source: SourceToken\n    public let session: SeekSessionID\n    public let providerRevision: SeekRevision\n    public let anchor: SeekFenceAnchor\n    /// A delivered event is playable ONLY under the exact binding: source identity,\n    /// session, AND provider revision all match. Old-origin (pre-seek, retained or\n    /// delayed) and cross-session events are rejected; the caller MUST releaseFrame\n    /// every rejected handle exactly once.\n    public func admits(_ origin: EventOrigin) -> Bool {\n        origin.source == source && origin.session == session && origin.providerRevision == providerRevision\n    }\n}\nextension ShellSeekBridge { }",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nfinal class Provider: CoreSeekProvider,@unchecked Sendable {\n var valid=true\n func currentBinding()->(token:SourceToken,session:SeekSessionID,revision:SeekRevision)? {valid ? (try! SourceToken(instanceID:1,openGeneration:1),try! SeekSessionID(rawValue:1),.atOpen):nil}\n func tryBegin(_ request:SeekRequest)throws -> any SeekTransaction {throw SeekRefusal.closed}\n}\nlet p=Provider(),bridge=ShellSeekBridge()\ncheck(bridge.attach(to:p),\"initial attach\")\np.valid=false\ncheck(!bridge.attach(to:p),\"failed attach returned\")\ncheck(bridge.currentFence == nil,\"failed attach removes prior admission fence\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
PASS initial attach
PASS failed attach returned
FAIL failed attach removes prior admission fence


```

```swift id=frozen_dependency_0
// GorAVSeekContract.swift v3 — shared seek contract, PROVIDER-ONLY scope (revise batch, v3 findings 1-8).
// Placement: Sources/GorAVNativeProbeKit/GorAVSeekContract.swift (explicit-sources target; Package.swift
// hunk by R2Y, sole Package.swift writer). Peer (goreda) sole-writes this file after Main's explicit start.
// Scope: the provider (FFmpeg) boundary only. Global commit / display reanchor / first-out / core ACK are
// NOT provider outcomes. NativeReady promises NATIVE REPOSITION + FLUSH ONLY - not target attainment,
// not a decoded PTS, never a global commit.

import Foundation

// MARK: - Errors

public enum SeekIssuanceError: Error, Sendable, Equatable {
    case exhausted            // ID/revision/generation space exhausted; typed refusal, NEVER a wrap
    case invalidIdentifier    // zero or otherwise invalid identity material
}

public enum SeekTimeError: Error, Sendable, Equatable {
    case invalidTimescale     // timescale <= 0: a TIME error, not an identity error
    case overflow             // checked rational arithmetic overflow
    case unknownOrigin        // conversion requested against an unknown stream origin
    case targetBeforeOrigin   // negative-position target before the stream start origin
}

// MARK: - Identity (roles never conflated; identity is COMPOSITE source+transaction)

public struct SeekCorrelationID: Hashable, Sendable {
    public let rawValue: UInt64   // nonzero
    public let queueTurn: UInt64  // owned and minted solely by the core queue; provider stores/echoes only
    public init(rawValue: UInt64, queueTurn: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
        self.queueTurn = queueTurn
    }
}

public struct SeekTransactionID: Hashable, Sendable, Comparable {
    public let rawValue: UInt64   // nonzero; meaningful only as part of SeekEventIdentity
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
    public static func < (l: SeekTransactionID, r: SeekTransactionID) -> Bool { l.rawValue < r.rawValue }
}

/// Composite identity (finding 5): a transaction ID is unique only within its source. Every receipt,
/// envelope and refusal that names a transaction names this composite.
public struct SeekEventIdentity: Hashable, Sendable {
    public let source: SourceToken
    public let transactionID: SeekTransactionID
    public init(source: SourceToken, transactionID: SeekTransactionID) {
        self.source = source
        self.transactionID = transactionID
    }
}

/// Provider-held, noncopyable, synchronized mint (finding 5). One instance per provider, held for the
/// provider's lifetime; value-type copies cannot duplicate issuance. Saturates to an explicit exhausted
/// state; never wraps.
public final class TransactionIDMint: @unchecked Sendable {  // NSLock-guarded mutable state
    private let lock = NSLock()
    private var next: UInt64 = 1
    private var exhausted = false
    public init() {}
    public func issue() throws -> SeekTransactionID {
        lock.lock(); defer { lock.unlock() }
        guard !exhausted else { throw SeekIssuanceError.exhausted }
        let id = try SeekTransactionID(rawValue: next)
        if next == UInt64.max { exhausted = true } else { next += 1 }
        return id
    }
}

public struct SeekSessionID: Hashable, Sendable {
    public let rawValue: UInt64   // nonzero
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
}

/// Source identity: provider-minted instance + open generation starting at 1, incrementing per open,
/// NEVER reset on reopen. Failed open consumes nothing and yields no token (typed error).
public struct SourceToken: Hashable, Sendable {
    public let instanceID: UInt64      // nonzero; provider-minted, never caller-supplied
    public let openGeneration: UInt64  // >= 1
    public init(instanceID: UInt64, openGeneration: UInt64) throws {
        guard instanceID != 0, openGeneration != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.instanceID = instanceID
        self.openGeneration = openGeneration
    }
}

/// Sole construction path for genuine source tokens (finding 4): the provider mints BOTH the instance
/// ID and the generation; caller-supplied instance IDs never establish identity. A failed open throws
/// and consumes neither an instance ID nor a generation.
public protocol SourceTokenIssuing: Sendable {
    func issueOpen() throws -> SourceToken
}

public struct SeekRevision: Hashable, Sendable, Comparable {
    public let rawValue: UInt64   // nonzero; 1 at open, first seek becomes 2
    public static let atOpen = try! SeekRevision(rawValue: 1)
    public init(rawValue: UInt64) throws {
        guard rawValue != 0 else { throw SeekIssuanceError.invalidIdentifier }
        self.rawValue = rawValue
    }
    public func advanced() throws -> SeekRevision {
        let (v, ov) = rawValue.addingReportingOverflow(1)
        guard !ov, v != 0 else { throw SeekIssuanceError.exhausted }
        return try SeekRevision(rawValue: v)
    }
    public static func < (l: SeekRevision, r: SeekRevision) -> Bool { l.rawValue < r.rawValue }
}

// MARK: - Time (integer rational; normalized equality+hash consistent with Comparable; checked math)

public struct RationalTime: Sendable {
    public let value: Int64      // may be negative (negative stream origin)
    public let timescale: Int32  // > 0
    public init(value: Int64, timescale: Int32) throws {
        guard timescale > 0 else { throw SeekTimeError.invalidTimescale }
        self.value = value
        self.timescale = timescale
    }
    /// Canonical form (reduced by gcd, positive timescale). Hash/equality are defined on this form.
    public var normalized: RationalTime {
        let mag = value.magnitude
        let ts = UInt64(bitPattern: Int64(timescale))
        var a = mag, b = ts
        while b != 0 { let t = a % b; a = b; b = t }
        let g = a == 0 ? 1 : a
        let red = mag / g
        let nv: Int64
        if value < 0 { nv = red == (1 << 63) ? Int64.min : -Int64(red) } else { nv = Int64(red) }
        let nts = Int32(ts / g)
        return try! RationalTime(value: nv, timescale: nts)
    }
    /// Exact tick conversion for a REAL FFmpeg rational time_base (v4 delta 1): given a timebase
    /// num/den (e.g. 1001/30000: num=1001, den=30000 ticks per second), returns
    /// floor(value * den / (timescale * num)) - media-RELATIVE ticks from the stream start.
    /// Two-limb wide intermediate arithmetic; mathematical floor exact for negatives; overflow-checked;
    /// no Double, no dropped denominator. The caller then adds stream.start_time with a checked add
    /// (unknown origin and negative relative targets are refused BEFORE mutation at tryBegin).
    /// This is pure arithmetic - a successful av_seek_frame + flush does NOT prove exact or nearest
    /// landing; only BACKWARD keyframe request is supported, exact/ceil/incompatible flags are
    /// refused pre-mutation.
    public func floorTicks(toTimebaseNumerator num: Int64, denominator den: Int64) throws -> Int64 {
        guard num > 0, den > 0 else { throw SeekTimeError.invalidTimescale }
        // Unsigned 128-bit long division using two standard-library UInt64 limbs. Both
        // numerator (<2^127) and divisor (<2^95) fit without Int128 or OS-floor changes.
        let product = value.magnitude.multipliedFullWidth(by: UInt64(den))
        let divisor = UInt64(timescale).multipliedFullWidth(by: UInt64(num))
        var remHigh: UInt64 = 0, remLow: UInt64 = 0
        var qHigh: UInt64 = 0, qLow: UInt64 = 0
        for bit in stride(from: 127, through: 0, by: -1) {
            let incoming = bit >= 64 ? (product.high >> UInt64(bit - 64)) & 1 : (product.low >> UInt64(bit)) & 1
            remHigh = (remHigh << 1) | (remLow >> 63)
            remLow = (remLow << 1) | incoming
            if remHigh > divisor.high || (remHigh == divisor.high && remLow >= divisor.low) {
                let (low, borrow) = remLow.subtractingReportingOverflow(divisor.low)
                remLow = low
                remHigh = remHigh - divisor.high - (borrow ? 1 : 0)
                if bit >= 64 { qHigh |= UInt64(1) << UInt64(bit - 64) }
                else { qLow |= UInt64(1) << UInt64(bit) }
            }
        }
        guard qHigh == 0 else { throw SeekTimeError.overflow }
        if value >= 0 {
            guard qLow <= UInt64(Int64.max) else { throw SeekTimeError.overflow }
            return Int64(qLow)
        }
        let hasRemainder = remHigh != 0 || remLow != 0
        let limit = UInt64(1) << 63
        guard qLow <= limit, !(qLow == limit && hasRemainder) else { throw SeekTimeError.overflow }
        if qLow == limit { return Int64.min }
        return hasRemainder ? -Int64(qLow) - 1 : -Int64(qLow)
    }
    /// Absolute film PTS -> media-relative seek seconds, using the actual
    /// stream origin. Exact checked rational subtraction, never Double-only
    /// arithmetic or independently rounded operands. The real timebase is
    /// validated and the eventual provider tick+origin conversion is preflighted
    /// before a staged decoder can mutate. Negative origins are legal.
    public func mediaRelativePosition(streamOrigin: RationalTime?,
                                      streamTimebase: RationalTime) throws -> RationalTime {
        guard let origin = streamOrigin else { throw SeekTimeError.unknownOrigin }
        guard streamTimebase.value > 0 else { throw SeekTimeError.invalidTimescale }
        guard self >= origin else { throw SeekTimeError.targetBeforeOrigin }
        let lhs = self.normalized, rhs = origin.normalized
        func gcd(_ x: UInt64, _ y: UInt64) -> UInt64 {
            var a=x, b=y
            while b != 0 { let r=a % b; a=b; b=r }
            return a
        }
        let common = Int64(gcd(UInt64(lhs.timescale), UInt64(rhs.timescale)))
        let leftFactor = Int64(rhs.timescale) / common
        let rightFactor = Int64(lhs.timescale) / common
        let (a, overflowA) = lhs.value.multipliedReportingOverflow(by:leftFactor)
        let (b, overflowB) = rhs.value.multipliedReportingOverflow(by:rightFactor)
        let (numerator, overflowN) = a.subtractingReportingOverflow(b)
        let (denominator, overflowD) = Int64(lhs.timescale).multipliedReportingOverflow(by:leftFactor)
        guard !overflowA, !overflowB, !overflowN, !overflowD, denominator > 0 else {
            throw SeekTimeError.overflow
        }
        let divisor = gcd(numerator.magnitude, UInt64(denominator))
        let reducedDen = denominator / Int64(divisor)
        guard reducedDen <= Int64(Int32.max) else { throw SeekTimeError.overflow }
        let relative = try RationalTime(value:numerator / Int64(divisor), timescale:Int32(reducedDen))
        let delta = try relative.floorTicks(toTimebaseNumerator:streamTimebase.value,
                                          denominator:Int64(streamTimebase.timescale))
        let originTicks = try origin.floorTicks(toTimebaseNumerator:streamTimebase.value,
                                               denominator:Int64(streamTimebase.timescale))
        _ = try RationalTime.checkedOriginSum(deltaTicks:delta,startTimeTicks:originTicks)
        return relative
    }

    /// Convenience for integral timescales (1 second = ts ticks), same checked semantics.
    public func floorTicks(toTimescale ts: Int32) throws -> Int64 {
        try floorTicks(toTimebaseNumerator: 1, denominator: Int64(ts))
    }
    /// Checked composition with the stream origin: deltaTicks + startTimeTicks, overflow-checked.
    /// Unknown origin is refused by the caller pre-mutation; a negative ORIGIN is legal here.
    public static func checkedOriginSum(deltaTicks: Int64, startTimeTicks: Int64) throws -> Int64 {
        let (v, ov) = deltaTicks.addingReportingOverflow(startTimeTicks)
        guard !ov else { throw SeekTimeError.overflow }
        return v
    }
    /// Checked conversion to a target timescale (floor on inexact), negative-safe.
    public func rescaled(to ts: Int32) throws -> RationalTime {
        let ticks = try floorTicks(toTimescale: ts)
        return try RationalTime(value: ticks, timescale: ts)
    }
}

extension RationalTime: Equatable {
    /// Cross-product equality on 128-bit products: a/b == c/d  <=>  a*d == c*b (b,d > 0).
    /// Agrees with `normalized`-based hashing: equal rationals normalize identically.
    public static func == (l: RationalTime, r: RationalTime) -> Bool {
        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))
        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))
        return lp.high == rp.high && lp.low == rp.low
    }
}

extension RationalTime: Hashable {
    public func hash(into hasher: inout Hasher) {
        let n = normalized
        hasher.combine(n.value)
        hasher.combine(n.timescale)
    }
}

extension RationalTime: Comparable {
    /// 128-bit cross-product comparison; exact for all inputs including negative origins.
    /// Consistent with Equatable: neither-less implies ==. No Double anywhere.
    public static func < (l: RationalTime, r: RationalTime) -> Bool {
        let lp = l.value.multipliedFullWidth(by: Int64(r.timescale))
        let rp = r.value.multipliedFullWidth(by: Int64(l.timescale))
        if lp.high != rp.high { return lp.high < rp.high }
        return lp.low < rp.low
    }
}

// MARK: - Target coordinate (finding 1: ONE coordinate, explicit)

/// The single target coordinate: MEDIA-RELATIVE rational seconds from the stream start (v4 delta 1).
/// Conversion: deltaTicks = position.floorTicks(toTimebaseNumerator: tb.num, denominator: tb.den)
/// for the stream's real rational time_base, then RationalTime.checkedOriginSum(deltaTicks:,
/// startTimeTicks: origin). A NEGATIVE relative target (before stream start) is rejected
/// (SeekTimeError.targetBeforeOrigin) BEFORE mutation; a negative ORIGIN is legal and exact; an
/// UNKNOWN origin is refused BEFORE mutation. Only BACKWARD keyframe request is supported:
/// exact/ceil/incompatible flags are refused PRE-MUTATION (tryBegin, .unsupported); av_seek_frame
/// BACKWARD + flush does not prove exact or nearest landing. A post-mutation miss is NEVER noMutation.
public enum SeekRounding: String, Sendable {
    case exact           // land on the exact tick or refuse PRE-MUTATION
    case floorToKeyframe // BACKWARD request only; nearest/exact landing is not promised
    case ceilToKeyframe  // nearest keyframe at or after the converted tick
}

public struct SeekTarget: Sendable {
    public let position: RationalTime      // media-timeline seconds (the ONE coordinate)
    public let rounding: SeekRounding
    public let requestedFlags: Int32       // whitelisted AVSEEK_FLAG_* bits; actual use recorded in facts
    public init(position: RationalTime, rounding: SeekRounding, requestedFlags: Int32) {
        self.position = position
        self.rounding = rounding
        self.requestedFlags = requestedFlags
    }
}

// MARK: - Request

public struct SeekRequest: Sendable {
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let source: SourceToken
    public let target: SeekTarget
    /// Core's expected current provider revision; provider validates expected == actual at queue-turn
    /// (mismatch => .stale) and computes next = expected.advanced().
    public let expectedRevision: SeekRevision
    public init(correlationID: SeekCorrelationID, session: SeekSessionID, source: SourceToken,
                target: SeekTarget, expectedRevision: SeekRevision) {
        self.correlationID = correlationID
        self.session = session
        self.source = source
        self.target = target
        self.expectedRevision = expectedRevision
    }
}

// MARK: - Descriptor + discovery (finding 4)

/// Renamed (finding 4): GorAVCore and NativeProbeKit both declare SourceDescriptor; this contract's
/// descriptor is SeekSourceDescriptor to keep decoder/open call sites unambiguous when a caller
/// imports both modules.
public struct SeekSourceDescriptor: Sendable {
    public let source: SourceToken
    public let seekable: Bool
    public let originKnown: Bool
    public let startOrigin: RationalTime?    // nil == unknown origin; conversions then refuse
    public let duration: RationalTime?
    public let videoStreamIndex: Int32?
    public let streamTimebase: RationalTime?
    public init(source: SourceToken, seekable: Bool, originKnown: Bool, startOrigin: RationalTime?,
                duration: RationalTime?, videoStreamIndex: Int32?, streamTimebase: RationalTime?) {
        self.source = source
        self.seekable = seekable
        self.originKnown = originKnown
        self.startOrigin = startOrigin
        self.duration = duration
        self.videoStreamIndex = videoStreamIndex
        self.streamTimebase = streamTimebase
    }
}

public struct SeekCapabilities: Sendable {
    public let seekable: Bool
    public let supportedRoundings: Set<SeekRounding>
    public let supportedFlags: Int32
    public let originKnown: Bool
    public init(seekable: Bool, supportedRoundings: Set<SeekRounding>, supportedFlags: Int32,
                originKnown: Bool) {
        self.seekable = seekable
        self.supportedRoundings = supportedRoundings
        self.supportedFlags = supportedFlags
        self.originKnown = originKnown
    }
}

/// Queue-owned, NON-BLOCKING open-binding discovery (finding 4): the genuine current source token,
/// session and revision, plus capability advertisement. tryBegin never blocks on discovery.
public protocol SeekProviderDiscovery: Sendable {
    func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)?
    func capabilities() -> SeekCapabilities
}

// MARK: - Typed refusals (admission-time ONLY; after admission every outcome is a receipt)

public enum SeekRefusal: Error, Sendable, Equatable {
    case busy(active: SeekEventIdentity)                     // active slot occupied; busy is observable
    case exhausted                                           // ID/revision/generation exhaustion; no wrap
    case stale(expected: SeekRevision, actual: SeekRevision) // revision mismatch at queue-turn
    case unsupported(String)                                 // incl. exact/ceil/flags refused PRE-MUTATION
    case closed                                              // session/source closed
    case legacyRejected(reason: String)                      // unenveloped/legacy event or handle refused
    case alreadyExecuted                                     // the ONLY post-admission throwing misuse
}

// MARK: - Provider stages, arbitration, mutation facts

public enum ProviderSeekStage: String, Sendable {
    case reserved, preSeek, inNativeSeek, nativeReturned, cleanedUp, receipted, retired
}

/// Cancel-vs-NativeReady arbitration: the FIRST recorded event wins; recorded once, never rewritten.
/// Kept SEPARATE from the actual reached cleanup stage (finding 8).
public enum SeekArbitration: String, Sendable {
    case none, cancellationRequested, nativeReadyObserved
}

public struct NativeSeekFacts: Sendable {
    public let avSeekReturn: Int32?              // actual av_seek_frame return code; nil if never entered
    public let flagsApplied: Int32
    public let resolvedStreamIndex: Int32?
    public let requestedTicks: Int64?            // target after origin+timebase conversion
    public let resolvedStreamTimebase: RationalTime?
    public let startOriginTicks: Int64?          // may be negative
    public let flushObserved: Bool
    public let packetFeedReset: Bool             // feed reset actually performed
    public let decoderReset: Bool
    public let packetsReleased: Int?             // explicit packet release count (nil if no mutation)
    public let packetAccountingReconciled: Bool  // admission/release ledger reconciled
    public init(avSeekReturn: Int32?, flagsApplied: Int32, resolvedStreamIndex: Int32?,
                requestedTicks: Int64?, resolvedStreamTimebase: RationalTime?,
                startOriginTicks: Int64?, flushObserved: Bool, packetFeedReset: Bool,
                decoderReset: Bool, packetsReleased: Int?, packetAccountingReconciled: Bool) {
        self.avSeekReturn = avSeekReturn
        self.flagsApplied = flagsApplied
        self.resolvedStreamIndex = resolvedStreamIndex
        self.requestedTicks = requestedTicks
        self.resolvedStreamTimebase = resolvedStreamTimebase
        self.startOriginTicks = startOriginTicks
        self.flushObserved = flushObserved
        self.packetFeedReset = packetFeedReset
        self.decoderReset = decoderReset
        self.packetsReleased = packetsReleased
        self.packetAccountingReconciled = packetAccountingReconciled
    }
}

public enum MutationState: String, Sendable {
    case none, partial, completedClean
}

/// Recovery paths (finding 8): nativeReady is the ONLY notRequired outcome and the ONLY one that
/// advances the revision and permits new output. Partial mutation, post-mutation cancellation and
/// session-IO escalation ALL require closeRequired - no flushOnly/resume loophole, no new seek or
/// reopen on the same session.
public enum RecoveryPath: String, Sendable {
    case notRequired    // nativeReady only
    case closeRequired  // mandatory for any mutated non-nativeReady outcome and session-IO escalation
}

public struct PoisonReport: Sendable {
    public let recoveryRequired: Bool   // true whenever mutation != .none and outcome != nativeReady
    public let recoveryPath: RecoveryPath
    public let detail: String
    public init(recoveryRequired: Bool, recoveryPath: RecoveryPath, detail: String) {
        self.recoveryRequired = recoveryRequired
        self.recoveryPath = recoveryPath
        self.detail = detail
    }
    /// Invariant helpers: the only two legal combinations for a mutated non-nativeReady outcome.
    public static let cleanNativeReady = PoisonReport(recoveryRequired: false, recoveryPath: .notRequired, detail: "")
    public static func closeRequired(_ detail: String) -> PoisonReport {
        PoisonReport(recoveryRequired: true, recoveryPath: .closeRequired, detail: detail)
    }
}

public enum ResumePolicy: String, Sendable {
    case resumeFromNativePosition // nativeReady only (provider success)
    case unchangedCoreGated       // noMutation outcomes: position/revision unchanged; the CORE gates
    case closedRequired           // every mutated non-nativeReady outcome
}

public enum SeekFailureReason: Sendable, Equatable {
    case avError(code: Int32)
    case streamResolutionFailed
    case interruptCancelled
    case poisonedState
    case sessionClosed
    case descriptorUnsupported(String)
}

// MARK: - Receipt (exactly one immutable completion per ADMITTED reservation; never throws)

public struct SeekReceipt: Sendable {
    /// Why an ADMITTED reservation was refused at queue-turn WITHOUT mutation (v4 delta 2).
    /// Distinct from cancellation: the caller did not ask to cancel; the provider refused.
    public enum NoMutationRefusal: Sendable, Equatable {
        case stale(expected: SeekRevision, actual: SeekRevision)
        case closed
        case unsupported(String)
    }
    /// Why an admitted reservation was cancelled WITHOUT mutation.
    public enum CancelReason: String, Sendable {
        case requested   // explicit requestCancellation before execute
        case abandoned   // handle released without execute/cancel: lease-release settlement, no orphan
        case close       // close() settlement before execute
    }
    public enum Outcome: Sendable {
        /// Provider completion evidence ONLY: native reposition + flush promised, revision advances,
        /// new output permitted. NOT target attainment, NOT a decoded PTS, NOT a global commit/ACK.
        /// The ONLY outcome that advances nextRevision.
        case nativeReady(facts: NativeSeekFacts)
        /// Admitted, then REFUSED at queue-turn before any mutation: position and revision UNCHANGED.
        /// Resume is CORE-GATED (the core decides the next action) - NOT a provider success signal.
        case refusedNoMutation(reason: NoMutationRefusal)
        /// Caller-side settlement before any mutation (requested/abandoned/close). Position and
        /// revision UNCHANGED; resume is CORE-GATED. Exactly-one reservation release.
        case cancelledNoMutation(reason: CancelReason)
        /// Post-mutation cancel: native call ran to its own return, cleanup completed with resources
        /// alive. Poison is MANDATORY and is always closeRequired.
        case cancelledAfterCleanup(facts: NativeSeekFacts, poison: PoisonReport)
        /// Typed staged failure at the ACTUAL stage; poison MANDATORY, closeRequired when mutated.
        case failed(stage: ProviderSeekStage, reason: SeekFailureReason,
                    facts: NativeSeekFacts, poison: PoisonReport)
    }
    public let identity: SeekEventIdentity       // composite source+transaction
    public let correlationID: SeekCorrelationID
    public let session: SeekSessionID
    public let request: SeekRequest              // original target preserved verbatim
    public let previousRevision: SeekRevision
    public let nextRevision: SeekRevision        // advanced ONLY on nativeReady
    public let reachedStage: ProviderSeekStage   // actual cleanup stage reached
    public let arbitration: SeekArbitration      // first-recorded winner; separate from reachedStage
    public let mutation: MutationState
    public let resumePolicy: ResumePolicy
    public let outcome: Outcome
    public init(identity: SeekEventIdentity, correlationID: SeekCorrelationID, session: SeekSessionID,
                request: SeekRequest, previousRevision: SeekRevision, nextRevision: SeekRevision,
                reachedStage: ProviderSeekStage, arbitration: SeekArbitration, mutation: MutationState,
                resumePolicy: ResumePolicy, outcome: Outcome) {
        self.identity = identity
        self.correlationID = correlationID
        self.session = session
        self.request = request
        self.previousRevision = previousRevision
        self.nextRevision = nextRevision
        self.reachedStage = reachedStage
        self.arbitration = arbitration
        self.mutation = mutation
        self.resumePolicy = resumePolicy
        self.outcome = outcome
    }
}

// MARK: - Transaction handle (finding 7: after admission, NO throwing paths except duplicate execute)

/// Ownership and completion invariants:
/// - tryBegin admission is the only gate that refuses; every ADMITTED reservation produces exactly
///   one immutable SeekReceipt - including queue-time stale/closed discovery after admission,
///   cancel-before-execute, abandonment, and close settlement.
/// - execute() moves reserved -> in-flight exactly once; the ONLY throwing misuse is a duplicate
///   execute (.alreadyExecuted).
/// - completion() NEVER throws; repeated calls return the SAME receipt value. Calling it before
///   execute is legal: it suspends until execute, cancellation, abandonment or close settles the
///   transaction (no wait-forever: requestCancellation() or close() always settles a pre-execute
///   transaction as cancelledNoMutation). Abandonment is settlement by lease release: dropping an
///   un-executed handle is collected and completed as cancelledNoMutation(.abandoned) - never an
///   orphaned reservation.
/// - requestCancellation() is a REQUEST: pre-mutation => cancelledNoMutation; post-entry => the
///   native call is never abandoned/freed/reopened/superseded while active; after it returns,
///   cleanup completes with resources alive; receipt is cancelledAfterCleanup or failed.
public protocol SeekTransaction: Sendable {
    var identity: SeekEventIdentity { get }
    var correlationID: SeekCorrelationID { get }
    var session: SeekSessionID { get }
    var request: SeekRequest { get }
    /// Provider-issued reserved revision (= expectedRevision.advanced() as validated at queue-turn).
    /// PINNED HANDSHAKE (finding 2): the provider validates expected and computes next; the core
    /// ADOPTS this issued value before execute and does not hold a separately reserved revision.
    var reservedRevision: SeekRevision { get }
    func execute() throws
    func completion() async -> SeekReceipt
    func requestCancellation()
}

// MARK: - Provider surface

public protocol SeekProviding: Sendable {
    func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor
    /// Admits at most one active transaction. Checks expectedRevision at queue-turn (.stale),
    /// capabilities (.unsupported PRE-MUTATION), slot (.busy). Throws SeekRefusal; after admission
    /// the transaction ALWAYS completes via a receipt.
    func tryBegin(_ request: SeekRequest) throws -> any SeekTransaction
    var activeTransaction: SeekEventIdentity? { get }
    /// Close ownership: provider-owned, exactly-once. Waits for any in-flight native call to return,
    /// then for outstanding retained-handle copy/release turns; completes every admitted-but-unsettled
    /// transaction exactly once (pre-mutation as cancelledNoMutation; in-flight after native return
    /// and cleanup as cancelledAfterCleanup or failed). No late continuation runs after close; no
    /// use-after-free. After close, all calls throw .closed and the event stream ends with .closed.
    func close() async throws
}

// MARK: - Provider events (finding 6: envelope the CONCRETE DecodeEvent surface + bound sentinels)

public enum RequestOrigin: Sendable, Hashable {
    case initialOpen
    case transaction(SeekTransactionID)   // composite with EventOrigin.source
}

public struct EventOrigin: Sendable, Hashable {
    public let session: SeekSessionID
    public let source: SourceToken
    public let providerRevision: SeekRevision
    public let requestOrigin: RequestOrigin
    public init(session: SeekSessionID, source: SourceToken, providerRevision: SeekRevision,
                requestOrigin: RequestOrigin) {
        self.session = session
        self.source = source
        self.providerRevision = providerRevision
        self.requestOrigin = requestOrigin
    }
}

/// The provider event stream: every variant of the concrete DecodeEvent surface, origin-bound, plus
/// explicit drained/closed sentinels. The read API never answers an untagged nil end: the stream
/// terminates only AFTER a terminal sentinel (endOfStream or failed or interrupted), then .drained
/// once all delivered handles are released or accounted, then .closed at close. Mixed legacy policy:
/// any event or handle lacking a full EventOrigin is REFUSED with .legacyRejected - never retagged.
public enum SeekProviderEvent<Frame: Sendable>: Sendable {
    case opened(EventOrigin, videoCodec: String, width: Int, height: Int)
    case frameDecoded(EventOrigin, Frame)
    case endOfStream(EventOrigin)
    case interrupted(EventOrigin)
    case failed(EventOrigin, code: Int32, summary: String)
    case feedSaturated(EventOrigin, pendingPackets: Int)
    case drained(EventOrigin)
    case closed(EventOrigin)
}

public protocol SeekEventReading: Sendable {
    associatedtype Frame: Sendable
    /// Suspends until the next event; the stream ends after .closed (subsequent calls return .closed).
    func nextEvent() async -> SeekProviderEvent<Frame>
}

/// Retained old-handle rule (finding 6): a retained handle stays copyable, readable and releasable
/// after a seek WHILE THE SAME OPEN GENERATION remains alive - this is generation-bound, NOT
/// seek-revision-bound. Release is exactly-once per handle.
public struct RetainedHandleMetadata: Sendable {
    public let origin: EventOrigin
    public let validWhileOpenGeneration: UInt64   // == origin.source.openGeneration
    public let releaseRequired: Bool
    public init(origin: EventOrigin, validWhileOpenGeneration: UInt64, releaseRequired: Bool) {
        self.origin = origin
        self.validWhileOpenGeneration = validWhileOpenGeneration
        self.releaseRequired = releaseRequired
    }
}

// MARK: - Interrupts (two kinds, two lifetimes)

public enum InterruptKind: String, Sendable {
    case requestCancel  // per-request; lifetime: until that request's receipt
    case sessionIO      // sticky UNTIL close/recovery; never reset by a new operation; closeRequired
}

public struct InterruptState: Sendable {
    public let kind: InterruptKind
    public let raisedBy: SeekEventIdentity?
    public let activeIOObserving: Bool
    public init(kind: InterruptKind, raisedBy: SeekEventIdentity?, activeIOObserving: Bool) {
        self.kind = kind
        self.raisedBy = raisedBy
        self.activeIOObserving = activeIOObserving
    }
}

// Cleanup ordering rule (contractual): post-mutation cleanup runs AFTER the native call returns,
// with provider resources alive; never concurrently with an executing FFmpeg call.

// MARK: - Provider transaction state machine
// Synchronization is scoped to state snapshots. No native call, continuation resume,
// user executor or await runs while this lock is held.
public final class ProviderSeekReservation: @unchecked Sendable {
    public let identity: SeekEventIdentity
    public let request: SeekRequest
    public let reservedRevision: SeekRevision
    fileprivate var executed = false
    fileprivate var enteredNative = false
    fileprivate var cancellation: SeekReceipt.CancelReason?
    fileprivate var result: SeekReceipt?
    fileprivate var waiters: [CheckedContinuation<SeekReceipt, Never>] = []
    fileprivate init(identity: SeekEventIdentity, request: SeekRequest, revision: SeekRevision) {
        self.identity = identity; self.request = request; self.reservedRevision = revision
    }
}

public final class ProviderSeekCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let mint = TransactionIDMint()
    private var active: ProviderSeekReservation?
    private var closing = false
    private var poisoned = false
    private var coordinated = false
    private var legacyUsed = false
    private var binding: (SourceToken, SeekSessionID, SeekRevision)?
    private var descriptorValue: SeekSourceDescriptor?
    private var capabilityValue = SeekCapabilities(seekable: false, supportedRoundings: [], supportedFlags: 0, originKnown: false)
    private var lastCorrelation: UInt64 = 0
    public init() {}
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    // Called only after a successful native open. Token issuance is owned by the decoder.
    public func opened(token: SourceToken, session: SeekSessionID, descriptor: SeekSourceDescriptor,
                       capabilities: SeekCapabilities) {
        locked {
            precondition(active == nil)
            binding = (token, session, .atOpen); descriptorValue = descriptor
            capabilityValue = capabilities; closing = false; poisoned = false
            coordinated = false; legacyUsed = false; lastCorrelation = 0
        }
    }
    public func currentBinding() -> (token: SourceToken, session: SeekSessionID, revision: SeekRevision)? {
        locked { guard !closing, !poisoned, let b = binding else { return nil }; return (b.0,b.1,b.2) }
    }
    public func capabilities() -> SeekCapabilities { locked { capabilityValue } }
    public func descriptor(for source: SourceToken) throws -> SeekSourceDescriptor {
        try locked {
            guard !closing, !poisoned, let d = descriptorValue, d.source == source else { throw SeekRefusal.closed }
            return d
        }
    }
    public var activeTransaction: SeekEventIdentity? { locked { active?.identity } }
    public var isCoordinated: Bool { locked { coordinated } }
    /// A source open chooses legacy or enveloped mode once. No retagging of legacy work.
    public func claimLegacy() -> Bool {
        locked {
            guard !coordinated, active == nil, !closing, !poisoned else { return false }
            legacyUsed = true; return true
        }
    }
    public func matches(session: UInt64) -> Bool { locked { binding?.1.rawValue == session } }
    public var outputAllowed: Bool { locked { !closing && !poisoned && active == nil } }
    public var isClosingOrPoisoned: Bool { locked { closing || poisoned } }
    /// Activates coordinated event mode before the first pull. Cannot downgrade until a new open.
    public func activateEvents() throws {
        try locked {
            guard !closing, !poisoned, binding != nil else { throw SeekRefusal.closed }
            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: "legacy mode already used for this open") }
            coordinated = true
        }
    }
    public func tryBegin(_ request: SeekRequest,
                         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) throws -> any SeekTransaction {
        let r: ProviderSeekReservation = try locked {
            guard !closing, !poisoned, let b = binding,
                  b.0 == request.source, b.1 == request.session else { throw SeekRefusal.closed }
            guard !legacyUsed else { throw SeekRefusal.legacyRejected(reason: "legacy mode already used for this open") }
            if let a = active { throw SeekRefusal.busy(active: a.identity) }
            guard request.expectedRevision == b.2 else { throw SeekRefusal.stale(expected: request.expectedRevision, actual: b.2) }
            guard request.correlationID.rawValue > lastCorrelation else { throw SeekRefusal.unsupported("replayed correlation") }
            guard capabilityValue.seekable, capabilityValue.originKnown,
                  request.target.rounding == .floorToKeyframe,
                  request.target.requestedFlags & ~Int32(1) == 0 else { throw SeekRefusal.unsupported("unsupported seek target or flags") }
            guard request.target.position.value >= 0 else { throw SeekTimeError.targetBeforeOrigin }
            let next = try b.2.advanced()
            let id = try mint.issue()
            let value = ProviderSeekReservation(identity: SeekEventIdentity(source: b.0, transactionID: id), request: request, revision: next)
            coordinated = true; lastCorrelation = request.correlationID.rawValue; active = value
            return value
        }
        return ProviderSeekHandle(owner: self, record: r, executor: executor)
    }
    fileprivate func execute(_ r: ProviderSeekReservation,
                             executor: @Sendable (ProviderSeekReservation) -> Void) throws {
        try locked {
            guard active === r, r.result == nil, !r.executed else { throw SeekRefusal.alreadyExecuted }
            r.executed = true
        }
        executor(r)
    }
    /// Linearizes native entry against cancellation. A cancellation after this point is
    /// conservatively post-entry even if the native function has not yet made its first mutation.
    public func enterNative(_ r: ProviderSeekReservation) -> Bool {
        locked {
            guard active === r, r.result == nil, r.cancellation == nil, !closing, !poisoned else { return false }
            r.enteredNative = true; return true
        }
    }
    public func cancellationRequested(_ r: ProviderSeekReservation) -> Bool {
        locked { r.cancellation != nil || closing }
    }
    public func queueRefusal(_ r: ProviderSeekReservation) -> SeekReceipt.NoMutationRefusal? {
        locked {
            guard !closing, !poisoned, let b = binding, b.0 == r.request.source,
                  b.1 == r.request.session else { return .closed }
            guard b.2 == r.request.expectedRevision else { return .stale(expected: r.request.expectedRevision, actual: b.2) }
            return nil
        }
    }
    public func cancel(_ r: ProviderSeekReservation, reason: SeekReceipt.CancelReason = .requested) {
        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []
        var completed: SeekReceipt?
        locked {
            guard r.result == nil else { return }
            if r.cancellation == nil { r.cancellation = reason }
            if !r.executed {
                let receipt = noMutation(r, outcome: .cancelledNoMutation(reason: r.cancellation!), arbitration: .cancellationRequested)
                r.result = receipt; completed = receipt
                continuations = r.waiters; r.waiters = []
                if active === r { active = nil }
            }
        }
        if let completed { for c in continuations { c.resume(returning: completed) } }
    }
    private func noMutation(_ r: ProviderSeekReservation, outcome: SeekReceipt.Outcome,
                            arbitration: SeekArbitration) -> SeekReceipt {
        SeekReceipt(identity: r.identity, correlationID: r.request.correlationID, session: r.request.session,
                    request: r.request, previousRevision: r.request.expectedRevision,
                    nextRevision: r.request.expectedRevision, reachedStage: .preSeek,
                    arbitration: arbitration, mutation: .none, resumePolicy: .unchangedCoreGated, outcome: outcome)
    }
    /// Single linearization point for cancellation versus nativeReady. The builder is a pure value
    /// constructor; native work MUST already have returned and cleanup must already be complete.
    public func finish(_ r: ProviderSeekReservation,
                       build: (Bool) -> SeekReceipt) {
        finishWithSnapshot(r) { build($0.recordedCancel != nil || $0.closing || $0.poisoned) }
    }
    /// Immutable settlement state, captured UNDER the coordinator lock inside the SAME critical
    /// region that settles. The ONLY cross-module read path for pre-entry settlement
    /// classification: no unsynchronized reservation getter, no Bool that cannot distinguish
    /// closing from poisoned, no recursive lock acquisition inside the builder.
    public struct SettlementSnapshot: Sendable, Equatable {
        public let recordedCancel: SeekReceipt.CancelReason?   // first-recorded reason (existing rule: record once)
        public let closing: Bool
        public let poisoned: Bool
    }
    /// finish variant whose builder receives the atomic snapshot taken in the settlement's own
    /// critical region - classification cannot observe a state the settlement did not. Distinct
    /// name (not an overload): no trailing-closure ambiguity against finish(_:build:).
    public func finishWithSnapshot(_ r: ProviderSeekReservation,
                                   build: (SettlementSnapshot) -> SeekReceipt) {
        var receipt: SeekReceipt?
        var continuations: [CheckedContinuation<SeekReceipt, Never>] = []
        locked {
            guard r.result == nil, active === r else { return }
            let snap = SettlementSnapshot(recordedCancel: r.cancellation, closing: closing, poisoned: poisoned)
            let value = build(snap)
            precondition(value.identity == r.identity && value.session == r.request.session)
            if case .nativeReady = value.outcome {
                precondition(value.mutation == .completedClean && value.nextRevision == r.reservedRevision)
                if let b = binding { binding = (b.0,b.1,r.reservedRevision) }
            } else if value.mutation != .none { poisoned = true }
            r.result = value; receipt = value
            continuations = r.waiters; r.waiters = []; active = nil
        }
        if let receipt { for c in continuations { c.resume(returning: receipt) } }
    }
    public func waitUntilSettled() async {
        let record = locked { active }
        if let record { _ = await completion(record) }
    }
    fileprivate func completion(_ r: ProviderSeekReservation) async -> SeekReceipt {
        await withCheckedContinuation { c in
            let value: SeekReceipt? = locked {
                if let v = r.result { return v }
                r.waiters.append(c); return nil
            }
            if let value { c.resume(returning: value) }
        }
    }
    /// Session I/O escalation invalidates output immediately. The decoder separately raises the
    /// matching session interrupt while native state stays retained until native return/close.
    public func poisonSession() { locked { poisoned = true } }
    public func requestClose() {
        // Atomic flag+record (peer NH6 2/2): the closing flag and the active record's .close reason
        // are set under ONE lock, so a settlement can never observe closing=true with no recorded
        // reason. First-recorded-wins preserved: a prior caller reason is never overwritten.
        let r = locked { () -> ProviderSeekReservation? in
            closing = true
            if let a = active, a.result == nil, a.cancellation == nil { a.cancellation = .close }
            return active
        }
        if let r { cancel(r, reason: .close) }
    }
}

private final class ProviderSeekHandle: SeekTransaction, @unchecked Sendable {
    private let owner: ProviderSeekCoordinator
    private let record: ProviderSeekReservation
    private let executor: @Sendable (ProviderSeekReservation) -> Void
    init(owner: ProviderSeekCoordinator, record: ProviderSeekReservation,
         executor: @escaping @Sendable (ProviderSeekReservation) -> Void) {
        self.owner = owner; self.record = record; self.executor = executor
    }
    var identity: SeekEventIdentity { record.identity }
    var correlationID: SeekCorrelationID { record.request.correlationID }
    var session: SeekSessionID { record.request.session }
    var request: SeekRequest { record.request }
    var reservedRevision: SeekRevision { record.reservedRevision }
    func execute() throws { try owner.execute(record, executor: executor) }
    func completion() async -> SeekReceipt { await owner.completion(record) }
    func requestCancellation() { owner.cancel(record) }
    deinit { owner.cancel(record, reason: .abandoned) }
}

```

```swift id=frozen_dependency_1
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

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Read-only caller bindings independently checked at cf3: ShellFrameSource ledger/bridge; MetalPresenter cue consumer; FFmpegSoftwareDecoder demux policy/lease table. B32 reduced wrapper/provider double and B31/B34 declaration extraction only, no full module claim. B33-35 malformed ingress hardening, not observed runtime incidents. Single production path plus own test, no adoption or runtime closure.
