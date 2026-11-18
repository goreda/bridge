# W-gdb-199i-in2tinct-37 - Subtitle issue list grows without bound on overlapping cues

state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: in2tinct

SubtitleSchedule must bound its collected structural issues while keeping the exact count, so a limits-valid but adversarial cue list cannot exhaust memory on the subtitle-load path. Preserve small-input results and activeCue(at:) semantics.

CALLER SCOPE: SubtitleSchedule is constructed on the shipping subtitle-load path at SubtitleController.swift:41 (selectPrimary) and :48 (selectSecondary), driven by SubtitleSidecarSession.swift:93, and at SubtitlePlan.swift:221. VTTParser.Limits.maxCues admits up to 200_000 cues per track (VTTParser.swift:59), so a limits-valid track of mutually overlapping cues yields on the order of n^2/2 Issue entries. Defensive bounded-witness hardening; not an observed live incident.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-path semantic proof, not the full FFmpeg module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Bound the collected structural issues to the first 64 witnesses in document order and add issueTotal with the exact count, the bounded-witness pattern used elsewhere in this codebase; small-input results and activeCue unchanged.

Native AppKit, Metal, camera capture, network, actual FFmpeg opens, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits 77 NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199i-in2tinct-37",
  "lab": "in2tinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "SubtitleSchedule keeps at most the first 64 structural witnesses in document order and exposes issueTotal as the exact count; small-input results and activeCue(at:) are unchanged. SubtitleSchedule is constructed on the shipping subtitle-load path at SubtitleController.swift:41 (selectPrimary) and :48 (selectSecondary), driven by SubtitleSidecarSession.swift:93, and at SubtitlePlan.swift:221. VTTParser.Limits.maxCues admits up to 200_000 cues per track (VTTParser.swift:59), so a limits-valid track of mutually overlapping cues yields on the order of n^2/2 Issue entries. Defensive bounded-witness hardening; not an observed live incident.",
    "ownership_lifetime": "Only the listed production source and its own tests.",
    "caller": "SubtitleSchedule is constructed on the shipping subtitle-load path at SubtitleController.swift:41 (selectPrimary) and :48 (selectSecondary), driven by SubtitleSidecarSession.swift:93, and at SubtitlePlan.swift:221. VTTParser.Limits.maxCues admits up to 200_000 cues per track (VTTParser.swift:59), so a limits-valid track of mutually overlapping cues yields on the order of n^2/2 Issue entries. Defensive bounded-witness hardening; not an observed live incident.",
    "callee": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199i-in2tinct-37",
    "paths": [
      "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift",
      "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py",
      "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift",
        "block": "source1",
        "sha256": "dd2afbc48525765a33777c758cb10df4b1629dfc85fd11e69fbbd896f12b2f22",
        "read_only_dependency": false,
        "role": "Pinned production source at the base pin."
      },
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift (fixed)",
        "block": "fixed_source",
        "sha256": "fb7b1a8f9b8f9a971c965bc21d005d09ff60fb4872ab089f0d3b11fb72f454c2",
        "role": "Same production file with only the minimal fix applied."
      },
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift (diff)",
        "block": "fix_diff",
        "sha256": "82159d9a19856a0482bb22d1c42bb34bf1a9004458d6a91825a6b07111f11f58",
        "role": "Unified diff pinned to fixed."
      },
      {
        "path": "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-37.json",
        "block": "fixtures2",
        "sha256": "97b7b014596bb0bee5e1c3008ac19839cdaa478af91f879cecaa3c066da093ab"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7ff88f13f8201ae279cf799f1f9639c2de8729b9e60565d0c4e16b1337ac9546",
    "last_5_lines": [
      "PASS first witness is the true first pair",
      "PASS small input exact",
      "PASS activeCue latest-start wins",
      "PASS out-of-order still reported",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "7ff88f13f8201ae279cf799f1f9639c2de8729b9e60565d0c4e16b1337ac9546",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "7ff88f13f8201ae279cf799f1f9639c2de8729b9e60565d0c4e16b1337ac9546",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "016a9ad773afecc4941aba452dc5ecaa79740f6c83682f0ded3cca7da6f4e9ee",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "016a9ad773afecc4941aba452dc5ecaa79740f6c83682f0ded3cca7da6f4e9ee",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "SubtitleSchedule is constructed on the shipping subtitle-load path at SubtitleController.swift:41 (selectPrimary) and :48 (selectSecondary), driven by SubtitleSidecarSession.swift:93, and at SubtitlePlan.swift:221. VTTParser.Limits.maxCues admits up to 200_000 cues per track (VTTParser.swift:59), so a limits-valid track of mutually overlapping cues yields on the order of n^2/2 Issue entries. Defensive bounded-witness hardening; not an observed live incident.",
  "fix": {
    "summary": "Bound the collected structural issues to the first 64 witnesses in document order and add issueTotal with the exact count, the bounded-witness pattern used elsewhere in this codebase; small-input results and activeCue unchanged.",
    "diff_block": "fix_diff",
    "diff_sha256": "82159d9a19856a0482bb22d1c42bb34bf1a9004458d6a91825a6b07111f11f58",
    "fixed_block": "fixed_source",
    "fixed_sha256": "fb7b1a8f9b8f9a971c965bc21d005d09ff60fb4872ab089f0d3b11fb72f454c2",
    "pinned_sha256": "dd2afbc48525765a33777c758cb10df4b1629dfc85fd11e69fbbd896f12b2f22"
  }
}
```

```swift id=source1
import Foundation

/// Time-ordered cue schedule with structural validation (lanes L5/L6, u2).
/// Pure model: the presenter hook (peer lane, interface pin pending) consumes
/// activeCue(at:). File order is preserved; structural issues are reported,
/// not silently repaired.
public struct SubtitleSchedule: Equatable, Sendable {

    public enum Issue: Equatable, Sendable {
        case outOfOrder(index: Int)          // start earlier than the previous cue's start
        case overlap(index: Int, previous: Int) // starts inside the previous cue's interval
    }

    public let cues: [SubtitleCue]
    public let issues: [Issue]

    public init(cues: [SubtitleCue]) {
        var found: [Issue] = []
        var maxStart = -Double.infinity
        for i in 0..<cues.count {
            // Out-of-order vs the running maximum start, not just the previous
            // cue: an early cue after several later ones is still flagged.
            if cues[i].startSeconds < maxStart {
                found.append(.outOfOrder(index: cues[i].index))
            }
            maxStart = max(maxStart, cues[i].startSeconds)
            // Overlap against EVERY earlier cue, not only the adjacent one:
            // out-of-order input can hide non-adjacent interval intersections.
            for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                    && cues[i].startSeconds < cues[j].endSeconds {
                found.append(.overlap(index: cues[i].index, previous: cues[j].index))
            }
        }
        self.cues = cues
        self.issues = found
    }

    /// The active cue with the LATEST start whose half-open interval holds t,
    /// or nil. File order is irrelevant to the result (overlapping cues resolve
    /// to the latest-starting one; stacked rendering is a presenter decision,
    /// not a model one).
    public func activeCue(at t: Double) -> SubtitleCue? {
        var best: SubtitleCue? = nil
        for cue in cues where cue.contains(seconds: t) {
            if best == nil || cue.startSeconds > best!.startSeconds { best = cue }
        }
        return best
    }
}

```

```swift id=fixed_source
import Foundation

/// Time-ordered cue schedule with structural validation (lanes L5/L6, u2).
/// Pure model: the presenter hook (peer lane, interface pin pending) consumes
/// activeCue(at:). File order is preserved; structural issues are reported,
/// not silently repaired.
public struct SubtitleSchedule: Equatable, Sendable {

    public enum Issue: Equatable, Sendable {
        case outOfOrder(index: Int)          // start earlier than the previous cue's start
        case overlap(index: Int, previous: Int) // starts inside the previous cue's interval
    }

    public let cues: [SubtitleCue]
    /// First 64 structural witnesses in document order; issueTotal is exact.
    public let issues: [Issue]
    public let issueTotal: Int

    public init(cues: [SubtitleCue]) {
        var found: [Issue] = []
        var total = 0
        var maxStart = -Double.infinity
        for i in 0..<cues.count {
            // Out-of-order vs the running maximum start, not just the previous
            // cue: an early cue after several later ones is still flagged.
            if cues[i].startSeconds < maxStart {
                total += 1
                if found.count < 64 { found.append(.outOfOrder(index: cues[i].index)) }
            }
            maxStart = max(maxStart, cues[i].startSeconds)
            // Overlap against EVERY earlier cue, not only the adjacent one:
            // out-of-order input can hide non-adjacent interval intersections.
            for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                    && cues[i].startSeconds < cues[j].endSeconds {
                total += 1
                if found.count < 64 { found.append(.overlap(index: cues[i].index, previous: cues[j].index)) }
            }
        }
        self.cues = cues
        self.issues = found
        self.issueTotal = total
    }

    /// The active cue with the LATEST start whose half-open interval holds t,
    /// or nil. File order is irrelevant to the result (overlapping cues resolve
    /// to the latest-starting one; stacked rendering is a presenter decision,
    /// not a model one).
    public func activeCue(at t: Double) -> SubtitleCue? {
        var best: SubtitleCue? = nil
        for cue in cues where cue.contains(seconds: t) {
            if best == nil || cue.startSeconds > best!.startSeconds { best = cue }
        }
        return best
    }
}

```

```diff id=fix_diff
--- a/archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift
+++ b/archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift
@@ -12,27 +12,33 @@
     }
 
     public let cues: [SubtitleCue]
+    /// First 64 structural witnesses in document order; issueTotal is exact.
     public let issues: [Issue]
+    public let issueTotal: Int
 
     public init(cues: [SubtitleCue]) {
         var found: [Issue] = []
+        var total = 0
         var maxStart = -Double.infinity
         for i in 0..<cues.count {
             // Out-of-order vs the running maximum start, not just the previous
             // cue: an early cue after several later ones is still flagged.
             if cues[i].startSeconds < maxStart {
-                found.append(.outOfOrder(index: cues[i].index))
+                total += 1
+                if found.count < 64 { found.append(.outOfOrder(index: cues[i].index)) }
             }
             maxStart = max(maxStart, cues[i].startSeconds)
             // Overlap against EVERY earlier cue, not only the adjacent one:
             // out-of-order input can hide non-adjacent interval intersections.
             for j in 0..<i where cues[j].startSeconds < cues[i].endSeconds
                     && cues[i].startSeconds < cues[j].endSeconds {
-                found.append(.overlap(index: cues[i].index, previous: cues[j].index))
+                total += 1
+                if found.count < 64 { found.append(.overlap(index: cues[i].index, previous: cues[j].index)) }
             }
         }
         self.cues = cues
         self.issues = found
+        self.issueTotal = total
     }
 
     /// The active cue with the LATEST start whose half-open interval holds t,

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
  "source": "archive/gor/Packages/gorav/Sources/GorAVSubtitles/SubtitleSchedule.swift",
  "markers": [
    "public struct SubtitleSchedule"
  ],
  "wrapper": "",
  "support": "public struct SubtitleCue: Equatable, Sendable {\n    public let index: Int\n    public let startSeconds: Double\n    public let endSeconds: Double\n    public let lines: [String]\n    public let styleName: String?\n    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {\n        self.index = index; self.startSeconds = startSeconds; self.endSeconds = endSeconds; self.lines = lines; self.styleName = styleName\n    }\n    public var text: String { lines.joined(separator: \"\\n\") }\n    public func contains(seconds t: Double) -> Bool { t >= startSeconds && t < endSeconds }\n}\n",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nfunc cue(_ i:Int,_ s:Double,_ e:Double)->SubtitleCue { SubtitleCue(index:i,startSeconds:s,endSeconds:e,lines:[\"x\"]) }\nlet many=(0..<100).map { cue($0+1,1,2) }\nlet sched=SubtitleSchedule(cues:many)\ncheck(sched.issues.count <= 64,\"witness list bounded\")\ncheck(sched.issues.first == .overlap(index:2,previous:1),\"first witness is the true first pair\")\nlet small=SubtitleSchedule(cues:[cue(1,0,2),cue(2,1,3),cue(3,4,5)])\ncheck(small.issues == [.overlap(index:2,previous:1)],\"small input exact\")\ncheck(small.activeCue(at:1.5)?.index == 2,\"activeCue latest-start wins\")\nlet unordered=SubtitleSchedule(cues:[cue(1,5,6),cue(2,1,2)])\ncheck(unordered.issues == [.outOfOrder(index:2)],\"out-of-order still reported\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL witness list bounded
PASS first witness is the true first pair
PASS small input exact
PASS activeCue latest-start wins
PASS out-of-order still reported


```

```text id=red_Onone
compile_exit=0

semantic_exit=1
FAIL witness list bounded
PASS first witness is the true first pair
PASS small input exact
PASS activeCue latest-start wins
PASS out-of-order still reported


```

```text id=red_O
compile_exit=0

semantic_exit=1
FAIL witness list bounded
PASS first witness is the true first pair
PASS small input exact
PASS activeCue latest-start wins
PASS out-of-order still reported


```

```text id=green_Onone
compile_exit=0

semantic_exit=0
PASS witness list bounded
PASS first witness is the true first pair
PASS small input exact
PASS activeCue latest-start wins
PASS out-of-order still reported


```

```text id=green_O
compile_exit=0

semantic_exit=0
PASS witness list bounded
PASS first witness is the true first pair
PASS small input exact
PASS activeCue latest-start wins
PASS out-of-order still reported


```

Publication caveat: NONQUALIFIED. Host-vendored gorav snapshot pinned b603, NOT current gorav main cf3. Writer-reported Swift6.0.3 both-mode baseline RED/fixed GREEN; independent replay awaited. Defensive hardening, not observed live incidents. B36 cookie header boundary call sites FFmpegSoftwareDecoder759/814, AudioDecoder310/341, MediaInventory101/121; B37 subtitle schedule consumer41/48 and plan221. No native/network/fullpackage acceptance. Proposed fixes require independent mutants/boundary replay.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
