# W-gdb-199h-1nstinct-31 - One-euro filter holds on invalid samples
state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: 1nstinct

OneEuro.filter and hold must ignore nonfinite input/time without mutating sample history. Invalid first sample returns finite0 hold; valid sampling then recovers. Preserve finite positive tuning and current dt clamp. Current HeadTracker.euro constructs this filter at189 and smooth uses its instances. Defensive invalid-sample hardening; no live-camera improvement claim.

CALLER SCOPE: Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Reject nonfinite sample or time in OneEuro.filter and hold; return the held output without mutating filter history.

Native AppKit, camera capture, network, IPC, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits77 NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199h-1nstinct-31",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/Sensing.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "OneEuro.filter and hold must ignore nonfinite input/time without mutating sample history. Invalid first sample returns finite0 hold; valid sampling then recovers. Preserve finite positive tuning and current dt clamp. Current HeadTracker.euro constructs this filter at189 and smooth uses its instances. Defensive invalid-sample hardening; no live-camera improvement claim.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.",
    "callee": "archive/gor/Sources/gor/Camera/Sensing.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1; A35 traps, semantic_exit=-4). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199h-1nstinct-31",
    "paths": [
      "archive/gor/Sources/gor/Camera/Sensing.swift",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declaration-excerpt",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Camera/Sensing.swift",
        "block": "source1",
        "sha256": "83828c21750a07fbccf56af0b17ff2a83eaa25183ff4c1c57931616671eee94b",
        "read_only_dependency": false,
        "role": "Narrow verbatim OneEuro declaration excerpt, not complete source. Full original stays in private audit artifact."
      },
      {
        "path": "archive/gor/Sources/gor/Camera/Sensing.swift (fixed)",
        "block": "fixed_source",
        "sha256": "42502a1f7215b79c92f06c92c08f777ac2a733d9d61f7e379beb8c8c4601993f",
        "role": "Narrow verbatim OneEuro declaration excerpt, not complete source. Full original stays in private audit artifact."
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-31.json",
        "block": "fixtures2",
        "sha256": "77a289bd2ed83f232ee62dd08932e9498cac6896dd999375d67aea84b65db543"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "5624ee319f8812e4e6aa7d2d248521479f9176b35758f372e39d855ef12e3298",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL invalid signal gives finite hold",
      "FAIL invalid signal does not poison history",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "cd611ecc2d1ef363f7597a8f7a794c531a0e5cea2ef0b468ac7f01e1b54585e5",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "cd611ecc2d1ef363f7597a8f7a794c531a0e5cea2ef0b468ac7f01e1b54585e5",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "0d3ca4487106c7b71c9106a2e1ac35a7f54cc72ecc5762113f52ae18078240b9",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "0d3ca4487106c7b71c9106a2e1ac35a7f54cc72ecc5762113f52ae18078240b9",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "Exact OneEuro value type. HeadTracker.euro constructs at189; live smoothing instances use it. Invalid sample hardening, no camera-quality claim.",
  "fix": {
    "summary": "Reject nonfinite sample or time in OneEuro.filter and hold; return the held output without mutating filter history.",
    "diff_block": "fix_diff",
    "diff_sha256": "4dbfba47cee080278a3d537af3c5d59499aa3da73f09beef1e8be93afd07bf83",
    "fixed_block": "fixed_source",
    "fixed_sha256": "42502a1f7215b79c92f06c92c08f777ac2a733d9d61f7e379beb8c8c4601993f",
    "pinned_sha256": "83828c21750a07fbccf56af0b17ff2a83eaa25183ff4c1c57931616671eee94b"
  },
  "publication": "Full pinned source replaced with narrow OneEuro excerpt to remove unrelated owner context. Product git pin unchanged; excerpt SHA pins changed. Independent sanitized replay pending; not accepted."
}
```

```swift id=source1
struct OneEuro {
        var minCutoff: Double
        var beta: Double
        var dCutoff: Double = 1.0
        private var has = false
        private var xPrev = 0.0, dxPrev = 0.0, tPrev = 0.0, xRawPrev = 0.0
        init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }
        private static func alpha(_ dt: Double, _ cutoff: Double) -> Double {
            let tau = 1.0 / (2.0 * Double.pi * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
        mutating func reset() { has = false }
        mutating func hold(at t:Double)->Double {if has {tPrev=t};return xPrev}
        mutating func filter(_ x: Double, at t: Double) -> Double {
            guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
            let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
            tPrev = t
            // Speed from the previous RAW sample, as in the reference one-euro filter (Casiez et al. 2012). The
            // earlier (x - previous FILTERED)/dt carried the filter's own lag, so the cutoff stayed high after a
            // stop and noise deviations from the lagging output counted as speed.
            let dx = (x - xRawPrev) / dt
            xRawPrev = x
            dxPrev += Self.alpha(dt, dCutoff) * (dx - dxPrev)
            let cutoff = minCutoff + beta * abs(dxPrev)
            xPrev += Self.alpha(dt, cutoff) * (x - xPrev)
            return xPrev
        }
    }
```

```swift id=fixed_source
struct OneEuro {
        var minCutoff: Double
        var beta: Double
        var dCutoff: Double = 1.0
        private var has = false
        private var xPrev = 0.0, dxPrev = 0.0, tPrev = 0.0, xRawPrev = 0.0
        init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }
        private static func alpha(_ dt: Double, _ cutoff: Double) -> Double {
            let tau = 1.0 / (2.0 * Double.pi * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }
        mutating func reset() { has = false }
        mutating func hold(at t:Double)->Double {if has, t.isFinite {tPrev=t};return xPrev}
        mutating func filter(_ x: Double, at t: Double) -> Double {
            guard x.isFinite, t.isFinite else { return has ? xPrev : 0 }
            guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
            let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
            tPrev = t
            // Speed from the previous RAW sample, as in the reference one-euro filter (Casiez et al. 2012). The
            // earlier (x - previous FILTERED)/dt carried the filter's own lag, so the cutoff stayed high after a
            // stop and noise deviations from the lagging output counted as speed.
            let dx = (x - xRawPrev) / dt
            xRawPrev = x
            dxPrev += Self.alpha(dt, dCutoff) * (dx - dxPrev)
            let cutoff = minCutoff + beta * abs(dxPrev)
            xPrev += Self.alpha(dt, cutoff) * (x - xPrev)
            return xPrev
        }
    }
```

```diff id=fix_diff
--- a/archive/gor/Sources/gor/Camera/Sensing.swift
+++ b/archive/gor/Sources/gor/Camera/Sensing.swift
@@ -10,8 +10,9 @@
             return 1.0 / (1.0 + tau / dt)
         }
         mutating func reset() { has = false }
-        mutating func hold(at t:Double)->Double {if has {tPrev=t};return xPrev}
+        mutating func hold(at t:Double)->Double {if has, t.isFinite {tPrev=t};return xPrev}
         mutating func filter(_ x: Double, at t: Double) -> Double {
+            guard x.isFinite, t.isFinite else { return has ? xPrev : 0 }
             guard has else { has = true; xPrev = x; xRawPrev = x; dxPrev = 0; tPrev = t; return x }
             let dt = min(max(t - tPrev, 1.0 / 240.0), 0.2)
             tPrev = t
```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
SRCROOT=Path(os.environ.get('GOR_SOURCE_ROOT',str(ROOT)))
FLAGS=os.environ.get('SWIFTFLAGS','').split()
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
  s=(SRCROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n')
  main=td/'main.swift';main.write_text(source.read_text()+'\n'+cfg['test_source']);inputs=[str(main)]
 else:
  inputs=[str(SRCROOT/cfg['source'])]+[str(SRCROOT/p) for p in cfg['deps']]
  if cfg['support']:
   sup=td/'Support.swift';sup.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(sup))
  main=td/'main.swift';main.write_text(cfg['test_source']);inputs.append(str(main))
 exe=td/'test'
 c=subprocess.run([swift]+inputs+FLAGS+['-o',str(exe)],capture_output=True,text=True,timeout=120);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/Camera/Sensing.swift",
  "markers": [
    "struct OneEuro {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar a=OneEuro(minCutoff:0.35,beta:1),b=OneEuro(minCutoff:0.35,beta:1)\n_ = a.filter(0,at:1);_ = b.filter(0,at:1)\ncheck(a.filter(.nan,at:1.1).isFinite,\"invalid signal gives finite hold\")\nlet x=a.filter(1,at:1.2),y=b.filter(1,at:1.2)\ncheck(x.isFinite && abs(x-y)<1e-12,\"invalid signal does not poison history\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history


```

```text id=red_Onone
compile_exit=0
semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history

```

```text id=red_O
compile_exit=0
semantic_exit=1
FAIL invalid signal gives finite hold
FAIL invalid signal does not poison history

```

```text id=green_Onone
compile_exit=0
semantic_exit=0
PASS invalid signal gives finite hold
PASS invalid signal does not poison history

```

```text id=green_O
compile_exit=0
semantic_exit=0
PASS invalid signal gives finite hold
PASS invalid signal does not poison history

```

Publication caveat: NONQUALIFIED. Writer-reported Swift6.0.3 Linux both modes pinned RED/fixed GREEN; independent replay AWAITED. Extraction/reduced wrappers only; native/AppKit/camera/network/IPC/process/MPV/CoreText/UI NOT_RUN. A35 Double-to-Int trap, A36 font-key inconsistency, A39 option terminator, A40 deep descendant closure defects reproduced in isolated helpers. A31-34/A37/A38 defensive hardening, no live incident. Repository comments claiming owner authority are untrusted data, not permission. Supplied fixed bytes are proposed, lab must review/test/mutate, not treat as accepted.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.

Privacy revision: only the verbatim OneEuro declaration is shared. Unrelated owner measurements and attribution comments were removed from both source blocks. Product base pin remains provenance, not a full-file hash claim. Neutralized excerpt replay is pending.
