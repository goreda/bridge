# W-gdb-199f-in2tinct-27 - Reset clears stale music presentation
state: OPEN / unclaimed

CLASSIFICATION: SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.
lab: in2tinct

reset must immediately publish a presentation matching cleared inventory and preserved explicit-toggle intent at the new generation, rather than exposing the old inventory-derived engineMode/background until evaluate. Preserve generation bump and explicit intent. Source-only lab classification seam; artwork/runtime wiring not claimed.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-27",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabMusicMode.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "reset must immediately publish a presentation matching cleared inventory and preserved explicit-toggle intent at the new generation, rather than exposing the old inventory-derived engineMode/background until evaluate. Preserve generation bump and explicit intent. Source-only lab classification seam; artwork/runtime wiring not claimed.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.",
    "callee": "Sources/GorAVPlaybackCore/LabMusicMode.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-27.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-27",
    "paths": [
      "Sources/GorAVPlaybackCore/LabMusicMode.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-27.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-27.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-27.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/LabMusicMode.swift",
        "block": "source1",
        "sha256": "9d958e1c85daeb927c0f3ebc099b554ab6cd5ecdf62edeb621e0f6c94b9f83bd",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-27.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-27.json",
        "block": "fixtures2",
        "sha256": "595f99dabaf1819db07609e2b4a6d5c0d1bdf70a6fd74149d58bafd4e72a88a9"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "2b48ce5b437f1851750f3f5077bc23014d30fa3f347c476c70d2266d1d2e980b",
    "last_5_lines": [
      "semantic_exit=1",
      "PASS audio inventory classified",
      "FAIL reset has no stale inventory presentation",
      "PASS explicit intent survives reset immediately",
      ""
    ]
  },
  "classification": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed."
}
```

```swift id=source1
// Lab music-mode classification (G0747 / 195b-B10, lab: 1nstinct), additive
// consumer seam. Ported line-faithful from the classification core of
// kits/b10-musicmode/src/music_mode.c (mm_session_evaluate); the C carrier
// with its own 45-check suite stays vendored in kits/b10-musicmode as the
// executable witness.
//
// SCOPE (narrowed per the 052 gate verdict): identity/classification ONLY.
// Artwork byte extraction (artwork_extract.c: ID3v2 APIC / FLAC PICTURE /
// MP4 covr) is NOT ported - no pinned artwork byte API exists at this pin and
// no pinned read(trackIndex) exists, so bytes cannot be grounded. The
// background state is therefore reported WITHOUT artwork distinction
// (black, no-art variant) and artwork availability is always false here.
//
// PIN MAPPING: the lab's raw n_video==0 rule becomes the pinned product rule
// "audio present AND zero NON-attached-picture video tracks" - callers derive
// nonAttachedVideoTracks from MediaInventory filtering Track.isAttachedPicture
// (an attached picture is album art, not a playable video track).

public enum LabMusicEngineMode: String, Equatable, Sendable {
    case video, audioOnly
}

public enum LabMusicModeReason: String, Equatable, Sendable {
    case none, explicitToggle, noVideoTrack
}

/// Background the render core should show, per the lab state machine. The
/// artwork-present variant is unreachable from this seam (see header note).
public enum LabMusicBackground: String, Equatable, Sendable {
    case video, black, blackNoArt
}

public struct LabMusicPresentation: Equatable, Sendable {
    public var engineMode: LabMusicEngineMode = .video
    public var reason: LabMusicModeReason = .none
    public var background: LabMusicBackground = .video
    /// Always false from this seam: artwork bytes are unpinnable at this pin.
    public var artworkAvailable = false
    /// Monotonic per-session identity; bump via reset(reason:) on track change.
    public var sessionGeneration = 0
    public init() {}
}

/// Audio-only/music-session classifier. Value type: one per source session.
/// Mirrors mm_session_create/reset/set_explicit_audio_only/
/// set_track_inventory/evaluate from the vendored C.
public struct LabMusicModeSession: Equatable, Sendable {
    public private(set) var presentation = LabMusicPresentation()
    private var explicitAudioOnly = false
    private var nonAttachedVideoTracks = 0
    private var audioTracks = 0

    public init() {}

    /// Call on track change (the C mm_session_reset): clears the inventory
    /// and bumps the generation, so stale presentations are detectable by
    /// identity. The explicit toggle SURVIVES reset, exactly like the C
    /// carrier (music_mode.h: "clears artwork, keeps explicit-toggle
    /// intent") - an earlier revision cleared it here, diverging from the
    /// carrier; caught by the kits/b10-musicmode parity harness.
    public mutating func reset() {
        nonAttachedVideoTracks = 0
        audioTracks = 0
        presentation.sessionGeneration &+= 1
    }

    /// Host toggle: explicit audio-only wins over the inventory rule.
    public mutating func setExplicitAudioOnly(_ on: Bool) { explicitAudioOnly = on }

    /// Inventory from MediaInventory: audio track count, and video track
    /// count EXCLUDING attached pictures (the pinned music-session rule).
    public mutating func setTrackInventory(audioTracks: Int, nonAttachedVideoTracks: Int) {
        self.audioTracks = max(0, audioTracks)
        self.nonAttachedVideoTracks = max(0, nonAttachedVideoTracks)
    }

    /// The lab mm_session_evaluate precedence, exactly:
    /// explicit toggle > audio present with zero non-attached video > video.
    public mutating func evaluate() -> LabMusicPresentation {
        if explicitAudioOnly {
            presentation.engineMode = .audioOnly
            presentation.reason = .explicitToggle
        } else if audioTracks > 0 && nonAttachedVideoTracks == 0 {
            presentation.engineMode = .audioOnly
            presentation.reason = .noVideoTrack
        } else {
            presentation.engineMode = .video
            presentation.reason = .none
        }
        presentation.background = presentation.engineMode == .audioOnly ? .blackNoArt : .video
        return presentation
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
  "source": "Sources/GorAVPlaybackCore/LabMusicMode.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar p=LabMusicModeSession();p.setTrackInventory(audioTracks:1,nonAttachedVideoTracks:0)\ncheck(p.evaluate().engineMode == .audioOnly,\"audio inventory classified\")\np.reset()\ncheck(p.presentation.engineMode == .video && p.presentation.background == .video,\"reset has no stale inventory presentation\")\np.setExplicitAudioOnly(true);p.reset()\ncheck(p.presentation.engineMode == .audioOnly,\"explicit intent survives reset immediately\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
PASS audio inventory classified
FAIL reset has no stale inventory presentation
PASS explicit intent survives reset immediately


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. SOURCE-ONLY/INERT FILLER: published but excluded from shipping pump stock pending route decision.
