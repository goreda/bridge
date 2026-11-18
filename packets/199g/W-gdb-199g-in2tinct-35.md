# W-gdb-199g-in2tinct-35 - Native lease requires an actual owner
state: OPEN / unclaimed

LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line265 owns LeaseTable. Whole LeaseTable source compiles. Owner.none ingress hardening only: no present adapter ownerless-allocation incident claimed.
lab: in2tinct

acquire must refuse owner.none; transfer to owner.none must also refuse without changing owner/accounting. Owner.none is absence, not release: release remains the only path removing bytes and handle. Preserve valid decoder-to-presenter ownership transfer and explicit release. FFmpegSoftwareDecoder owns LeaseTable at line265. Defensive ingress hardening: current adapter uses actual owners, so no present native allocation incident is claimed.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199g-in2tinct-35",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "acquire must refuse owner.none; transfer to owner.none must also refuse without changing owner/accounting. Owner.none is absence, not release: release remains the only path removing bytes and handle. Preserve valid decoder-to-presenter ownership transfer and explicit release. FFmpegSoftwareDecoder owns LeaseTable at line265. Defensive ingress hardening: current adapter uses actual owners, so no present native allocation incident is claimed.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line265 owns LeaseTable. Whole LeaseTable source compiles. Owner.none ingress hardening only: no present adapter ownerless-allocation incident claimed.",
    "callee": "Sources/GorAVNativeProbeKit/LeaseTable.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-35.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199g-in2tinct-35",
    "paths": [
      "Sources/GorAVNativeProbeKit/LeaseTable.swift",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-35.py",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-35.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-35.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
        "block": "source1",
        "sha256": "abdc3c430cc6dacbe24c22ac4bd87ad504c27b06736f6d6c913c005a69438925",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-35.py",
        "block": "fixtures1",
        "sha256": "ca73de002a7ea6df0372f590d1eead763fa38702b16e21455076dcf870d2dcae"
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-35.json",
        "block": "fixtures2",
        "sha256": "688695428809f83968db7f6f6444ba4d7a4680513357c2a19425f7311fc6bb1c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "cbcba6c489e711a5ce94802c0e1bf6972dd8a61709aa6596a4ed8e91b3b1c9db",
    "last_5_lines": [
      "FAIL refusal leaves accounting unchanged",
      "PASS real owner admitted",
      "FAIL ownerless transfer refused",
      "FAIL refused transfer retains ownership",
      ""
    ]
  },
  "classification": "LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line265 owns LeaseTable. Whole LeaseTable source compiles. Owner.none ingress hardening only: no present adapter ownerless-allocation incident claimed."
}
```

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

    /// Transfers ownership (decoder -> presenter). Unknown handle is a no-op returning false.
    @discardableResult public func transfer(handle: UInt64, to owner: Owner) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[handle] else { return false }
        e.owner = owner; entries[handle] = e
        return true
    }

    /// Releases the buffer. Returns false when the handle is unknown (double/unknown release).
    @discardableResult public func release(handle: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries.removeValue(forKey: handle) else { return false }
        outstandingBytes -= e.bytes
        return true
    }

    /// Immutable per-handle copy; caller still owns session serialization.
    public func entry(handle: UInt64) -> Entry? {
        lock.lock(); defer { lock.unlock() }; return entries[handle]
    }

    public var outstandingCount: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    public var currentOutstandingBytes: Int { lock.lock(); defer { lock.unlock() }; return outstandingBytes }

    /// r6: clears every entry; call after recording leaks so a later session
    /// never collides with stale handles.
    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries = [:]; outstandingBytes = 0
    }

    /// Handles still owned at teardown; every entry here is a leak to report.
    public func leakedHandles() -> [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return entries.keys.sorted()
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
  "source": "Sources/GorAVNativeProbeKit/LeaseTable.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet t=LeaseTable()\ncheck(!t.acquire(handle:1,bytes:8,owner:.none),\"ownerless allocation refused\")\ncheck(t.outstandingCount == 0 && t.currentOutstandingBytes == 0,\"refusal leaves accounting unchanged\")\ncheck(t.acquire(handle:2,bytes:8,owner:.decoder),\"real owner admitted\")\ncheck(!t.transfer(handle:2,to:.none),\"ownerless transfer refused\")\ncheck(t.entry(handle:2)?.owner == .decoder,\"refused transfer retains ownership\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL ownerless allocation refused
FAIL refusal leaves accounting unchanged
PASS real owner admitted
FAIL ownerless transfer refused
FAIL refused transfer retains ownership


```


Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Read-only caller bindings independently checked at cf3: ShellFrameSource ledger/bridge; MetalPresenter cue consumer; FFmpegSoftwareDecoder demux policy/lease table. B32 reduced wrapper/provider double and B31/B34 declaration extraction only, no full module claim. B33-35 malformed ingress hardening, not observed runtime incidents. Single production path plus own test, no adoption or runtime closure.
