# W-gdb-199e-1nstinct-27 - Reject invalid subtitle sample clocks
state: OPEN / unclaimed
lab: 1nstinct

shouldSample must reject nonfinite now before reading signature or mutating cadence state in every paused/thermal/playing mode. Preserve pause/resume reset, valid signature changes and existing sampling intervals. HeatTelemetry below is explicit test environment input, not a replacement sampling algorithm.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. HeatTelemetry.thermalPressure is a test environment input fixed false; the complete actual governor class executes. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-27",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "shouldSample must reject nonfinite now before reading signature or mutating cadence state in every paused/thermal/playing mode. Preserve pause/resume reset, valid signature changes and existing sampling intervals. HeatTelemetry below is explicit test environment input, not a replacement sampling algorithm.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-27",
    "paths": [
      "archive/gor/Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift",
        "block": "source1",
        "sha256": "fe3793cff08a472617ba1ca2170cca700ca919c5e7760f0bddfd64b6ed2f98da",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-27.json",
        "block": "fixtures2",
        "sha256": "f4a4d8406069afd5f468c8b5a0a798074646dc942cdde01e2d7121f0f0716038"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "350a208c045595c98a95bea5cfe3344437019a1dd87f545c4a274fa695f383e3",
    "last_5_lines": [
      "FAIL infinite clock rejected",
      "FAIL invalid clock does not read signature",
      "FAIL valid initial sample remains available",
      "PASS valid cadence retained",
      ""
    ],
    "receipt_sha256": "e62d74689cceedb9e79c43daff36fa2f64c78aa6ff90cd53ea5b94e09a2dae47"
  }
}
```

```swift id=source1
import CoreGraphics

// Source commentary elided for privacy; historical proof hashes are not rebound.
final class SubtitleSampleGovernor {
    static let shared = SubtitleSampleGovernor()
    static let pausedInterval: Double = 1.0
    static let thermalPlayingInterval: Double = 0.4
    var paused = false { didSet {
        if paused != oldValue { lastSignature = nil; lastSampleAt = -.infinity }
        if paused != oldValue { lastThermalSampleAt = -.infinity }
    } }
    private var lastSignature: [CGRect?]?
    private var lastSampleAt: Double = -.infinity
    private var lastThermalSampleAt: Double = -.infinity

    func shouldSample(signature: () -> [CGRect?], now: Double) -> Bool {
        // Thermal spacing ahead of the playing fast path: the signature read is a cheap CGRect map, the capture
        // it gates is the expensive part. A changed signature samples immediately, exactly like the paused path.
        if !paused && HeatTelemetry.thermalPressure {
            let sig = signature()
            guard sig != lastSignature || now - lastThermalSampleAt >= Self.thermalPlayingInterval else { return false }
            lastSignature = sig; lastThermalSampleAt = now
            return true
        }
        guard paused else { return true }
        let sig = signature()
        guard sig != lastSignature || now - lastSampleAt >= Self.pausedInterval else { return false }
        lastSignature = sig; lastSampleAt = now
        return true
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
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift",
  "markers": [
    "final class SubtitleSampleGovernor {"
  ],
  "wrapper": "",
  "support": "enum HeatTelemetry { static var thermalPressure = false }",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet g=SubtitleSampleGovernor();g.paused=true\nvar calls=0\ncheck(!g.shouldSample(signature:{calls+=1;return []},now:.infinity),\"infinite clock rejected\")\ncheck(calls == 0,\"invalid clock does not read signature\")\ncheck(g.shouldSample(signature:{calls+=1;return []},now:1),\"valid initial sample remains available\")\ncheck(!g.shouldSample(signature:{calls+=1;return []},now:1.1),\"valid cadence retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL infinite clock rejected
FAIL invalid clock does not read signature
FAIL valid initial sample remains available
PASS valid cadence retained


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
