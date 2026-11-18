# W-gdb-199f-in2tinct-26 - Closed decoder metadata cannot reopen
state: OPEN / unclaimed

CLASSIFICATION: Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.
lab: in2tinct

mark must keep closed lifecycle terminal until explicit deregistration. Ignore attempted closed-to-open/draining/failed changes, preserving the closed snapshot and exclusion from activeSnapshots. Do not widen failed semantics or change identity registration. Production metadata registry has adapter callers; these callers are not executed by this isolated regression. This is terminal-lifecycle hardening, not a claim that an observed live adapter currently reopens decoders.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-26",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "mark must keep closed lifecycle terminal until explicit deregistration. Ignore attempted closed-to-open/draining/failed changes, preserving the closed snapshot and exclusion from activeSnapshots. Do not widen failed semantics or change identity registration. Production metadata registry has adapter callers; these callers are not executed by this isolated regression. This is terminal-lifecycle hardening, not a claim that an observed live adapter currently reopens decoders.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.",
    "callee": "Sources/GorAVPlaybackCore/DecoderInventory.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-26.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-26",
    "paths": [
      "Sources/GorAVPlaybackCore/DecoderInventory.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-26.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-26.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-26.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
        "block": "source1",
        "sha256": "f502dcdf89727f73c3836d5cdee5d609c53c6b853a731cf6b90424b42ba51d80",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-26.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-26.json",
        "block": "fixtures2",
        "sha256": "8cc4527f0f64e785add10537d5616505344976dfdbce8b57295f4eebd968c8d4"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "66846812f0425466ffb2ad1708e652450a07f42e94932216fff06760108cd49d",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL closed remains terminal",
      "FAIL closed decoder never reappears active",
      ""
    ]
  },
  "classification": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident."
}
```

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
    /// Sessions invalidated wholesale (reset/seek-restart); snapshots for
    /// them are never served again even if a stale decoder forgets to
    /// deregister.
    public private(set) var invalidatedSessions: Set<UInt64> = []
    private var nextSeq: UInt64 = 1

    public init() {}

    @discardableResult
    public mutating func register(_ id: DecoderIdentity, kind: DecoderKind,
                                  codec: String, sourceID: String? = nil,
                                  revisionAtOpen: UInt64 = 1) -> RegisterOutcome {
        guard !invalidatedSessions.contains(id.session) else { return .refusedInvalidatedSession }
        guard nextSeq < UInt64.max else { return .refusedIdentityExhausted }
        guard entries[id] == nil else {
            duplicateRegistrations += 1
            return .duplicateRefused
        }
        entries[id] = DecoderSnapshot(identity: id, kind: kind, codec: codec, sourceID: sourceID,
                                      revisionAtOpen: revisionAtOpen, lifecycle: .open, registrationSeq: nextSeq)
        nextSeq += 1
        return .registered
    }

    public mutating func mark(_ id: DecoderIdentity, _ lifecycle: DecoderLifecycle) {
        if entries[id] != nil { entries[id]!.lifecycle = lifecycle }
    }

    @discardableResult
    public mutating func deregister(_ id: DecoderIdentity) -> Bool {
        guard entries.removeValue(forKey: id) != nil else { return false }
        deregistrations += 1
        return true
    }

    /// Fence a whole session (seek-restart / reset): all its entries drop.
    public mutating func invalidateSession(_ session: UInt64) {
        invalidatedSessions.insert(session)
        entries = entries.filter { $0.key.session != session }
    }

    /// Live snapshot for one identity; nil for unknown, deregistered, or
    /// session-invalidated decoders. `lifecycle` filter: closed/failed
    /// entries are still returned (they happened) until deregistered.
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        guard !invalidatedSessions.contains(id.session) else { return nil }
        return entries[id]
    }

    /// All currently tracked decoders for a session, registration order.
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        guard !invalidatedSessions.contains(session) else { return [] }
        return entries.values
            .filter { $0.identity.session == session && $0.lifecycle != .closed }
            .sorted { $0.registrationSeq < $1.registrationSeq }
    }
}

/// Shared metadata store. The lock serializes cross-decoder registry access;
/// native open/failure/teardown calls still originate on each adapter's queue.
/// No callbacks run under this lock, and no second source open occurs here.
public final class DecoderInventoryStore: @unchecked Sendable {
    public static let shared = DecoderInventoryStore()
    private let lock = NSLock()
    private var inventory = DecoderInventory()
    private var nextHandle: UInt64 = 1
    public init() {}
    public func register(session: UInt64, kind: DecoderKind, codec: String,
                         sourceID: String, revisionAtOpen: UInt64) -> DecoderIdentity? {
        lock.lock(); defer { lock.unlock() }
        guard session != 0, revisionAtOpen != 0, !sourceID.isEmpty,
              nextHandle < UInt64.max else { return nil }
        let id=DecoderIdentity(session:session,handle:nextHandle)
        nextHandle += 1 // A refused attempt never allows handle reuse.
        guard inventory.register(id,kind:kind,codec:codec,sourceID:sourceID,
                                 revisionAtOpen:revisionAtOpen) == .registered else { return nil }
        return id
    }
    public func deregister(_ id: DecoderIdentity) {
        lock.lock(); defer { lock.unlock() }
        _ = inventory.deregister(id)
    }
    public func invalidateSession(_ session: UInt64) {
        lock.lock(); defer { lock.unlock() }
        inventory.invalidateSession(session)
    }
    public func snapshot(_ id: DecoderIdentity) -> DecoderSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return inventory.snapshot(id)
    }
    public func activeSnapshots(session: UInt64) -> [DecoderSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return inventory.activeSnapshots(session:session)
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
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')) else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVPlaybackCore/DecoderInventory.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar inv=DecoderInventory();let id=DecoderIdentity(session:1,handle:1)\n_ = inv.register(id,kind:.videoSoftware,codec:\"h264\")\ninv.mark(id,.closed);inv.mark(id,.open)\ncheck(inv.snapshot(id)?.lifecycle == .closed,\"closed remains terminal\")\ncheck(inv.activeSnapshots(session:1).isEmpty,\"closed decoder never reappears active\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL closed remains terminal
FAIL closed decoder never reappears active


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. Single production path plus own test, no adoption or runtime closure.
