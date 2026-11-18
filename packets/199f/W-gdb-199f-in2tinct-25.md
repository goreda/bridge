# W-gdb-199f-in2tinct-25 - Repeated adoption cannot discard an active barrier
state: OPEN / unclaimed

CLASSIFICATION: Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.
lab: in2tinct

Make adopt idempotent while already adopted, without resetting operation or committed state. A repeated adopt cannot allow abort during operation or release a committed swap. clear is the explicit new-lineage reset. Preserve initial adoption/release semantics. Shared production ownership state, actual caller binding not executed here. This is defensive repeated-call hardening, not a demonstrated live double-adoption incident.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-25",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/PreparedAdoption.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Make adopt idempotent while already adopted, without resetting operation or committed state. A repeated adopt cannot allow abort during operation or release a committed swap. clear is the explicit new-lineage reset. Preserve initial adoption/release semantics. Shared production ownership state, actual caller binding not executed here. This is defensive repeated-call hardening, not a demonstrated live double-adoption incident.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.",
    "callee": "Sources/GorAVPlaybackCore/PreparedAdoption.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-25.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-25",
    "paths": [
      "Sources/GorAVPlaybackCore/PreparedAdoption.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-25.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-25.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-25.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/PreparedAdoption.swift",
        "block": "source1",
        "sha256": "111949fc7b840f823e2bba5a6108f7cae70ad879bcea770142d4dbc43650708b",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-25.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-25.json",
        "block": "fixtures2",
        "sha256": "28f6a0b49a1e99d5abfb7646c0974f155c9d8318a505dbf063846d16f0ca3473"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "d3bf691251b08e5a9da8321e495568597d13556322a04faa8de80ccd9cb82039",
    "last_5_lines": [
      "semantic_exit=1",
      "PASS operation begins",
      "FAIL duplicate adoption preserves in-flight barrier",
      "FAIL duplicate adoption preserves commit fence",
      ""
    ]
  },
  "classification": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident."
}
```

```swift id=source1
import Foundation

public enum PreparedAdoptionRelease: Equatable, Sendable {
    case released
    case noAdoption
    /// Retry after the suspended staging/boundary operation returns. No live state changed.
    case operationInFlight
    /// A swap changed the video source. Use explicit session cancellation to stop playback.
    case alreadyCommitted
}

/// Shared by the live session and portable coordinator. This is ownership only:
/// release never closes a decoder, touches audio, changes the pump or resets a clock.
public struct PreparedAdoption: Sendable {
    private var adopted = false
    private var committed = false
    private var operation = false
    public init() {}
    public mutating func adopt() { adopted = true; committed = false; operation = false }
    public mutating func beginOperation() -> Bool {
        guard adopted, !operation else { return false }
        operation = true; return true
    }
    public mutating func finishOperation(didCommit: Bool) {
        committed = committed || didCommit; operation = false
    }
    public mutating func abortUncommitted() -> PreparedAdoptionRelease {
        guard adopted else { return .noAdoption }
        guard !operation else { return .operationInFlight }
        guard !committed else { return .alreadyCommitted }
        adopted = false
        return .released
    }
    public mutating func clear() { self = PreparedAdoption() }
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
  "source": "Sources/GorAVPlaybackCore/PreparedAdoption.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar p=PreparedAdoption();p.adopt();check(p.beginOperation(),\"operation begins\")\np.adopt()\ncheck(p.abortUncommitted() == .operationInFlight,\"duplicate adoption preserves in-flight barrier\")\np.finishOperation(didCommit:true);p.adopt()\ncheck(p.abortUncommitted() == .alreadyCommitted,\"duplicate adoption preserves commit fence\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
PASS operation begins
FAIL duplicate adoption preserves in-flight barrier
FAIL duplicate adoption preserves commit fence


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. Single production path plus own test, no adoption or runtime closure.
