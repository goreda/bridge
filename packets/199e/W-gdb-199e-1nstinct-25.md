# W-gdb-199e-1nstinct-25 - Reject invalid icon row geometry
state: OPEN / unclaimed
lab: 1nstinct

leadingFrames and trailingFrames must reject nonfinite anchors/height/gap/slot widths/ink, negative widths/ink/gap or nonpositive height, returning [] for the whole row. Guard nonfinite intermediate frame origins as well. Preserve valid measured ink spacing and hoverFrame behavior. PhotonFont is not edited; its unrelated static sizing references are excluded from this isolated starter.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-25",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorFit/IconBarFit.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "leadingFrames and trailingFrames must reject nonfinite anchors/height/gap/slot widths/ink, negative widths/ink/gap or nonpositive height, returning [] for the whole row. Guard nonfinite intermediate frame origins as well. Preserve valid measured ink spacing and hoverFrame behavior. PhotonFont is not edited; its unrelated static sizing references are excluded from this isolated starter.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorFit/IconBarFit.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-25",
    "paths": [
      "archive/gor/Sources/gor/GorFit/IconBarFit.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorFit/IconBarFit.swift",
        "block": "source1",
        "sha256": "be45ac1c02481bda9e17b4a7d36702d0ecaafcb6654ecdb685d141c0ac6a3eb5",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-25.json",
        "block": "fixtures2",
        "sha256": "a4ec32f737f317cff5ca87b68da2f0735bb0cd95602545bb8fe234251a5c6331"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "bd0b480859755af0214d87df3f9528ff955abf4c0218caf523557313effc7f79",
    "last_5_lines": [
      "FAIL invalid ink refused",
      "FAIL invalid slot refused",
      "FAIL invalid ink refused",
      "PASS normal frame unchanged",
      ""
    ],
    "receipt_sha256": "ed646b28a29ef31bb5dcf638fbaf83bb33996cfca43d4fd02a624e31baed4690"
  }
}
```

```swift id=source1
import Foundation

// ================================================================
//  IconBarFit - glyph-ink based icon row layout
//
//  WHY: the top bars used to place MusicBtn slots with a fixed
//  inter-FRAME pad, but every button renders a different glyph and the
//  variable font gives each character a different width, so the visual
//  gap between glyphs came out unequal (owner 13:35: the random button
//  sat too close to search). These helpers lay buttons out so the gap
//  between glyph INK edges is constant, computed from each button's
//  measured ink width - no stretched type, no global rescale.
//
//  WHY hover: MusicBtn grows its frame for the typewriter hover title.
//  Trailing buttons keep their right edge pinned so the resting glyph
//  never moves; leading (back-style) buttons expand left to right with
//  their origin pinned, so the glyph does not shift either.
//
//  Contract for callers: pass each button's LIVE frame width and its
//  ink measured from the string it currently renders (MusicBtn.inkWidth),
//  so a typewriter hover title re-lays the row with equal gaps at every
//  step and only the slots on the growing side move. Frames come back
//  with y = 0; offset them when the row is vertically centred.
// ================================================================
enum IconBarFit {
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    static var standardGap: CGFloat { max(PhotonFont.chromeValue(8), PhotonFont.chromePad) }

    /// Panel chrome insets (owner 14:29, same message: a panel's distance
    /// to the spine must equal its distance to the sidebar). The spine is
    /// spineWidth = pad*2 + charW + gap wide at the left chrome edge, the
    /// sidebar sidebarWidth = twoDigitW + pad*2 at the right, so a panel
    /// placed padL from the base edge sits padL - spineWidth clear of the
    /// spine; padR below puts it the same distance clear of the sidebar.
    static func panelPadR(padL: CGFloat) -> CGFloat {
        PhotonFont.chromeValue(padL) + PhotonFont.chromeTwoDigitW - PhotonFont.chromeCharW - PhotonFont.chromeGap
    }

    /// One button's contribution: its live frame width and the measured
    /// width of the string it currently renders (its ink).
    struct Slot {
        var width: CGFloat
        var ink: CGFloat
    }

    /// Right-to-left icon row with equal gaps between glyph ink edges.
    /// Text is right-aligned in every button frame, so a button's glyph
    /// right edge is its frame maxX. Each button's maxX is placed `gap`
    /// plus the previous (right) button's ink left of that button's
    /// previous glyph; frames are returned in the order given (first =
    /// rightmost). Live ink values keep the gaps equal while a hover
    /// title grows: only slots left of the hovered button move.
    static func trailingFrames(right: CGFloat, height: CGFloat, gap: CGFloat, buttons: [Slot]) -> [CGRect] {
        var frames: [CGRect] = []
        frames.reserveCapacity(buttons.count)
        var prevInkLeft = right + gap
        var first = true
        for b in buttons {
            let glyphRight = first ? right : prevInkLeft - gap
            frames.append(CGRect(x: glyphRight - b.width, y: 0, width: b.width, height: height))
            prevInkLeft = glyphRight - b.ink
            first = false
        }
        return frames
    }

    /// Left-to-right icon row with equal gaps between glyph ink edges.
    /// Text is left-aligned in every button frame, so a button's glyph
    /// left edge is its frame minX. The first button starts exactly at
    /// `left` - the file browser uses this to start the back glyph
    /// exactly where the rows' folder icons start.
    static func leadingFrames(left: CGFloat, height: CGFloat, gap: CGFloat, buttons: [Slot]) -> [CGRect] {
        var frames: [CGRect] = []
        frames.reserveCapacity(buttons.count)
        var x = left
        for b in buttons {
            frames.append(CGRect(x: x, y: 0, width: b.width, height: height))
            x += b.ink + gap
        }
        return frames
    }

    /// Frame growth for the typewriter hover title. Leading buttons
    /// keep minX pinned (the title expands left to right and the glyph
    /// never shifts); trailing buttons keep maxX pinned. The width
    /// floor is minWidth and textPad is the breathing room around the
    /// measured ink. Pass ink 0 with textPad 0 for the resting reset.
    static func hoverFrame(current: CGRect, ink: CGFloat, minWidth: CGFloat, textPad: CGFloat, expandsLeftToRight: Bool) -> CGRect {
        let w = max(minWidth, ink + textPad)
        if expandsLeftToRight {
            return CGRect(x: current.minX, y: current.minY, width: w, height: current.height)
        }
        return CGRect(x: current.maxX - w, y: current.minY, width: w, height: current.height)
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
  "source": "archive/gor/Sources/gor/GorFit/IconBarFit.swift",
  "markers": [
    "struct Slot {",
    "static func trailingFrames(",
    "static func leadingFrames("
  ],
  "wrapper": "enum IconBarFit",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nfor x in [CGFloat.nan,CGFloat.infinity,-1] {\n check(IconBarFit.leadingFrames(left:0,height:20,gap:2,buttons:[.init(width:x,ink:10)]).isEmpty,\"invalid slot refused\")\n check(IconBarFit.trailingFrames(right:100,height:20,gap:2,buttons:[.init(width:10,ink:x)]).isEmpty,\"invalid ink refused\")\n}\ncheck(IconBarFit.leadingFrames(left:0,height:20,gap:2,buttons:[.init(width:10,ink:8)]).first == CGRect(x:0,y:0,width:10,height:20),\"normal frame unchanged\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL invalid slot refused
FAIL invalid ink refused
FAIL invalid slot refused
FAIL invalid ink refused
FAIL invalid slot refused
FAIL invalid ink refused
PASS normal frame unchanged


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
