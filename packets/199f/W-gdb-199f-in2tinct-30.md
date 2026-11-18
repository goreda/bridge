# W-gdb-199f-in2tinct-30 - Repeated readiness begin cannot reuse generation
state: OPEN / unclaimed

CLASSIFICATION: Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.
lab: in2tinct

begin must not reset a live lineage generation to0 after seek or erase its readiness barrier. Keep initial begin idempotent. Add explicit new-lineage construction/reset naming if needed rather than silently recycling epoch. Existing seek readiness and clock-start ordering stay unchanged. This is generation-lifecycle hardening for a production ordering model; begin currently explicitly resets to0. The writer must define construction/new-lineage reset separately and audit callers before changing that behavior. Full shell integration not exercised.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-30",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "begin must not reset a live lineage generation to0 after seek or erase its readiness barrier. Keep initial begin idempotent. Add explicit new-lineage construction/reset naming if needed rather than silently recycling epoch. Existing seek readiness and clock-start ordering stay unchanged. This is generation-lifecycle hardening for a production ordering model; begin currently explicitly resets to0. The writer must define construction/new-lineage reset separately and audit callers before changing that behavior. Full shell integration not exercised.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident.",
    "callee": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-30.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-30",
    "paths": [
      "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-30.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-30.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-30.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
        "block": "source1",
        "sha256": "84ab7c80c17d441405756e2fe7d4ed61d54a7c9219c496c3fcf61a9b249e2db3",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-30.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-30.json",
        "block": "fixtures2",
        "sha256": "f4c5dff85183c0f2d8e6358be62dc3752d46ecfb6c626c973983a8be27f14086"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "160d7f941080fda2308bb862f9380a407899cacf13198de4f41931024574e192",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL begin cannot reuse generation zero",
      "PASS seek anchor remains required",
      ""
    ]
  },
  "classification": "Production lifecycle/ordering helper; callers not run by this isolated test. Contract hardening, not an observed live incident."
}
```

```swift id=source1
import Foundation

/// 189k PERMANENT ENGINE RULE (owner block 189k, 2026-11-07 01:50 +03):
/// the audio clock starts only after frame 0 is decoded AND presented;
/// after every seek: flush the queue, present the first frame, then
/// restart the clock. Frame 0 of each generation is the readiness anchor
/// and never receives a scheduler decision. maxLate and all downstream
/// asserts are unchanged by this type; it owns ONLY the ordering state so
/// no harness or shell can reimplement (or skip) the rule.
///
/// The session is deliberately small and platform-neutral (Linux-testable):
/// callers perform the real decode/present/clock work and move the session
/// through its typed gates. A clock start requested before the anchor is
/// presented is REFUSED (typed), never silently permitted.
public struct ReadinessAnchorSession: Sendable, Equatable {
    /// Seek fence: bumped on every seek; frames from older generations are stale.
    public private(set) var generation: UInt64 = 0
    /// True while the current generation's first frame has not been both
    /// decoded and presented. An anchor-pending frame takes NO scheduler
    /// decision: it IS the timeline zero.
    public private(set) var anchorPending = true
    /// True after requestClockStart() succeeded for the current generation.
    public private(set) var clockRunning = false
    public init() {}

    /// Start of playback (generation 0).
    public mutating func begin() {
        generation = 0; anchorPending = true; clockRunning = false
    }

    /// The readiness anchor frame for the current generation was decoded
    /// AND presented. Idempotent within a generation.
    public mutating func anchorPresentedNow() { anchorPending = false }

    /// Typed clock-start gate: succeeds only after the anchor is presented.
    /// Returns false (refusal) when the anchor is still pending.
    public mutating func requestClockStart() -> Bool {
        guard !anchorPending else { return false }
        clockRunning = true
        return true
    }

    /// Seek: the queue is flushed by the caller; the clock stops; the first
    /// frame of the new generation is again a readiness anchor that must be
    /// presented before the clock restarts. Returns the new generation.
    @discardableResult
    public mutating func seek() -> UInt64 {
        generation &+= 1
        anchorPending = true
        clockRunning = false
        return generation
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
  "source": "Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar p=ReadinessAnchorSession();p.begin();p.anchorPresentedNow();_ = p.requestClockStart();_ = p.seek()\nlet g=p.generation;p.begin()\ncheck(p.generation == g,\"begin cannot reuse generation zero\")\ncheck(!p.requestClockStart(),\"seek anchor remains required\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL begin cannot reuse generation zero
PASS seek anchor remains required


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. Single production path plus own test, no adoption or runtime closure. Proposed begin reset semantic change requires full caller audit before adoption; retained comment is data, not authority.
