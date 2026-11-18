# W-gdb-199f-in2tinct-29 - Invalid chrome feed cannot mutate model
state: OPEN / unclaimed

CLASSIFICATION: SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.
lab: in2tinct

ingest must ignore a sample entirely when now, nonnil hue, saturation or contrast is nonfinite. Finite negative saturation sentinel remains supported. No state mutation, feed flag or smoothing change on invalid sample. Preserve valid feed/toggle behavior. Model is explicitly inert pending parity witness at this pin; no live shader binding claimed.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-29",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ChromeStateModel.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "ingest must ignore a sample entirely when now, nonnil hue, saturation or contrast is nonfinite. Finite negative saturation sentinel remains supported. No state mutation, feed flag or smoothing change on invalid sample. Preserve valid feed/toggle behavior. Model is explicitly inert pending parity witness at this pin; no live shader binding claimed.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.",
    "callee": "Sources/GorAVPlaybackCore/ChromeStateModel.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-29.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-29",
    "paths": [
      "Sources/GorAVPlaybackCore/ChromeStateModel.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-29.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-29.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-29.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ChromeStateModel.swift",
        "block": "source1",
        "sha256": "d84e80064f7536d1135227044348ceee2377c9da3883fcbceac0544dd2d627e7",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-29.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-29.json",
        "block": "fixtures2",
        "sha256": "282cfe4b85e806cbaa554b03f7e995d44394230664396348a39f609c90a03ffb"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "ee41df1abe9849dcb0c3a389f30b38f6f6843b3179aa04cb7ab069037a9af47f",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL nonfinite hue does not mutate model",
      "FAIL nonfinite clock does not mutate model",
      ""
    ]
  },
  "classification": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed."
}
```

```swift id=source1
import Foundation

/// P29-CHROME (DR-0019): pure Swift value-type state model re-expressing the
/// state/adaptive layer of photon-chrome.lua v1.1 (instinct main
/// archive/gor/Resources/vendor/mpv/scripts/photon-chrome.lua, 826 lines,
/// SHA256 d0ebe78af3dd3d2ed13bdd7d2f0960f7803cf31e709b96a40191c78285ee92ca)
/// under the chrome owner's pinned boundaries (relayed 00:28):
/// Foundation only, no AppKit/CoreGraphics, no mpv IPC, no glsl-shaders
/// property writes, no OSD, no file/shader path resolution. The Lua script
/// remains authoritative; this model is inert until the golden vectors pass
/// in the gor lane. All mpv-facing side effects, script messages, the scene
/// feed payload format, chrome view layout and the SubtitleView SDR pin stay
/// with the gor structure writer.
///
/// Seam names are the owner's frozen ones: ChromeStateModel (tracker),
/// ChromeSceneSample (input), ChromeResolvedState (output),
/// ChromeToggleEvent / ChromeToggleState (toggles). The sample carries
/// saturation/contrast in addition to the pinned hue/isCut labels because the
/// source's strength/contrast resolution consumes them; they default to the
/// source's neutral values so `ChromeSceneSample(hue:isCut:)` compiles as
/// pinned.

/// Scene sample input. hue is the normalized 0..1 wheel value (0=red), nil
/// when the frame has no usable hue (HDR path or uncomputable) - the source's
/// nil contract, never a fabricated 0. saturation uses the source's -1 HDR
/// sentinel for "no saturation data". contrast/motion/peak follow the feed;
/// only saturation/contrast drive resolution today.
public struct ChromeSceneSample: Equatable, Sendable {
    public let hue: Double?
    public let saturation: Double
    public let contrast: Double
    public let isCut: Bool
    public init(hue: Double?, saturation: Double = -1, contrast: Double = 0.25, isCut: Bool) {
        self.hue = hue; self.saturation = saturation; self.contrast = contrast; self.isCut = isCut
    }
}

/// The resolved, rendered state after a step - the model's only output.
/// shaderParameters carries the three live P22 photonChrome lanes by their
/// declared names (DR-0014/DR-0015): CH_FILTER_POS, CH_FILTER_STRENGTH,
/// CH_CONTRAST_AMOUNT.
public struct ChromeResolvedState: Equatable, Sendable {
    public let filterPositionRendered: Double
    public let filterStrengthRendered: Double
    public let contrastAmount: Double
    public let shaderParameters: [String: Double]
    public let hueArcClamped: Bool
    public let hasFeed: Bool
}

public enum ChromeToggleEvent: Equatable, Sendable {
    case toggle
    case filterToggle
    case pauseTransition
    case fileLoaded
    case setTargetEnabled(Bool)
}

public struct ChromeToggleState: Equatable, Sendable {
    public let enabled: Bool
    public let targetEnabled: Bool
    public let manualFilterActive: Bool
    public let manualFilterPosition: Int
}

/// The stateful tracker. Value type; the host owns when to call and what to
/// do with the output (apply to the chrome pass, publish HUD, persist).
public struct ChromeStateModel: Equatable, Sendable {
    // Source control-panel constants (exact values, not re-tuned).
    public static let chromeFilter = 1.0               // orange default
    public static let filterStrength = 0.75
    public static let hueDriven = true
    public static let hueFilterArcMax = 120.0 / 360.0
    public static let hueEmaAlpha = 0.08               // photon-common HUE_EMA_ALPHA
    public static let contrastBase = 0.11 / 2
    public static let contrastSceneGain = 0.22 / 2
    public static let contrastClampMax = 0.44 / 2
    public static let satFloor = 0.15
    public static let satCeil = 0.55
    public static let satStrengthMin = 0.35
    public static let tier1TauAttack = 0.35
    public static let tier1CutTau = 0.6
    public static let charTau = 9.0
    public static let charDeadZone = 0.36
    public static let charDwellMin = 2.5
    public static let charEaseTau = 3.0
    public static let charCutEaseTau = 0.8
    public static let filterNames = ["red", "orange", "yellow", "green"]

    // Toggle state.
    public private(set) var enabled = false
    public private(set) var targetEnabled = false
    public private(set) var manualFilterActive = false
    public private(set) var manualFilterPos = ChromeStateModel.chromeFilter

    // Carryover rendezvous (file-loaded x latest absolute target declaration).
    private var carryoverSawFileLoaded = false
    private var carryoverSawTargetMessage = false

    // Scene state (source defaults).
    public private(set) var sceneSat = 0.0             // -1 = HDR sentinel, no sat data
    public private(set) var sceneContrast = 0.25
    public private(set) var sceneHue: Double? = nil
    public private(set) var sceneHueSmoothed: Double? = nil
    public private(set) var isCut = false
    public private(set) var hasFeed = false

    // Resolved targets and rendered values (TIER 1 / TIER 2 split).
    public private(set) var filterStrengthResolved = ChromeStateModel.filterStrength
    public private(set) var contrastResolved = ChromeStateModel.contrastBase
    public private(set) var filterPosResolved = ChromeStateModel.chromeFilter
    public private(set) var filterStrengthRendered = ChromeStateModel.filterStrength
    public private(set) var contrastRendered = ChromeStateModel.contrastBase
    public private(set) var filterPosRendered = ChromeStateModel.chromeFilter
    public private(set) var hueArcClamped = false

    // TIER-2 character tracker fields (photon-common char_track).
    public private(set) var charSignal = ChromeStateModel.chromeFilter
    public private(set) var charCommitted = ChromeStateModel.chromeFilter
    private var charRendered = ChromeStateModel.chromeFilter
    private var charDwellStart: Double? = nil
    private var tier1LastT = 0.0
    private var charLastT = 0.0

    public init() {}

    public var toggleState: ChromeToggleState {
        ChromeToggleState(enabled: enabled, targetEnabled: targetEnabled,
                          manualFilterActive: manualFilterActive, manualFilterPosition: Int(manualFilterPos))
    }

    public var resolvedState: ChromeResolvedState {
        ChromeResolvedState(
            filterPositionRendered: filterPosRendered,
            filterStrengthRendered: filterStrengthRendered,
            contrastAmount: contrastRendered,
            shaderParameters: ["CH_FILTER_POS": filterPosRendered,
                               "CH_FILTER_STRENGTH": filterStrengthRendered,
                               "CH_CONTRAST_AMOUNT": contrastRendered],
            hueArcClamped: hueArcClamped,
            hasFeed: hasFeed)
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

    /// photon-common lerp_hue: shortest way around the wraparound wheel.
    static func lerpHue(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var d = b - a
        if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
        var h = a + d * t
        if h < 0 { h += 1 } else if h >= 1 { h -= 1 }
        return h
    }

    /// photon-common hue_circular_dist (0..0.5).
    static func hueCircularDist(_ a: Double, _ b: Double) -> Double {
        let d = max(a, b) - min(a, b)
        return d > 0.5 ? 1 - d : d
    }

    /// photon-common smooth_hue (scale 1): snap on cut or first sample, else EMA.
    static func smoothHue(_ current: Double?, _ raw: Double, alpha: Double, snap: Bool) -> Double {
        if snap || current == nil { return raw }
        return lerpHue(current!, raw, alpha)
    }

    /// photon-common asym_smooth (the source's feed path uses one tau both ways).
    static func asymSmooth(_ current: Double, _ target: Double, _ tauAttack: Double, _ tauRelease: Double, _ dt: Double) -> Double {
        let tau = target > current ? tauAttack : tauRelease
        return current + (1 - exp(-dt / tau)) * (target - current)
    }

    /// Scene feed ingestion (the mpv-facing decode stays with the gor owner;
    /// the payload format is frozen on their side). Hue smoothing updates even
    /// while disabled; resolution and rendering run only when enabled, per the
    /// source's "armed but not on" early-return.
    public mutating func ingest(_ sample: ChromeSceneSample, now: Double) {
        let isFirstFeed = !hasFeed
        sceneSat = sample.saturation
        sceneContrast = sample.contrast
        isCut = sample.isCut
        hasFeed = true
        sceneHue = sample.hue
        if let hue = sample.hue {
            sceneHueSmoothed = ChromeStateModel.smoothHue(sceneHueSmoothed, hue,
                                                          alpha: ChromeStateModel.hueEmaAlpha,
                                                          snap: sample.isCut || sceneHueSmoothed == nil)
        }
        // nil hue: hold the previous smoothed value, never collapse to nil/0.
        guard enabled else { return }
        resolveAdaptiveParams(now: now)
        if isFirstFeed {
            // First real feed: snap rendered to the first real resolved values.
            filterStrengthRendered = filterStrengthResolved
            contrastRendered = contrastResolved
        }
    }

    /// TIER-1/TIER-2 resolution. Called on every enabled feed tick and from
    /// toggle paths, exactly like the source's ch_resolve_adaptive_params.
    public mutating func resolveAdaptiveParams(now: Double) {
        let S = ChromeStateModel.self
        if sceneSat < 0 {
            // HDR sentinel: no saturation signal; flat user preference.
            filterStrengthResolved = S.filterStrength
        } else {
            let satTRaw = S.clamp((sceneSat - S.satFloor) / (S.satCeil - S.satFloor), 0, 1)
            let satT = S.satStrengthMin + satTRaw * (1 - S.satStrengthMin)
            filterStrengthResolved = S.filterStrength * satT
        }
        contrastResolved = S.clamp(S.contrastBase + sceneContrast * S.contrastSceneGain, 0, S.contrastClampMax)

        if manualFilterActive {
            filterPosResolved = manualFilterPos
            hueArcClamped = false
        } else if !S.hueDriven || sceneHueSmoothed == nil {
            filterPosResolved = S.chromeFilter
            hueArcClamped = false
        } else {
            let h = sceneHueSmoothed!
            let inArc = h >= 0 && h <= S.hueFilterArcMax
            let hueInArc: Double
            if inArc {
                hueInArc = h
            } else {
                // Outside the red->green arc: pin to the nearer endpoint.
                hueInArc = S.hueCircularDist(h, 0) <= S.hueCircularDist(h, S.hueFilterArcMax) ? 0 : S.hueFilterArcMax
            }
            hueArcClamped = !inArc
            filterPosResolved = hueInArc / S.hueFilterArcMax * 3
        }

        // TIER 1: exponential ease toward resolved; faster settle on a cut.
        let tier1Dt = min(now - (tier1LastT > 0 ? tier1LastT : now - 0.1), 1.0)
        tier1LastT = now
        let tier1Tau = isCut ? S.tier1CutTau : S.tier1TauAttack
        filterStrengthRendered = S.asymSmooth(filterStrengthRendered, filterStrengthResolved, tier1Tau, tier1Tau, tier1Dt)
        contrastRendered = S.asymSmooth(contrastRendered, contrastResolved, tier1Tau, tier1Tau, tier1Dt)

        // TIER 2: long-EMA + dead-zone + dwell-confirmation + ease (char_track).
        let charDt = min(now - (charLastT > 0 ? charLastT : now - 0.1), 1.0)
        charLastT = now
        filterPosRendered = charTrack(raw: filterPosResolved, now: now, dt: charDt, isCut: isCut)
    }

    /// photon-common char_track with chrome's tier-2 constants.
    private mutating func charTrack(raw: Double, now: Double, dt: Double, isCut: Bool) -> Double {
        let S = ChromeStateModel.self
        charSignal += (1 - exp(-dt / S.charTau)) * (raw - charSignal)
        let drift = max(charSignal, charCommitted) - min(charSignal, charCommitted)
        if drift <= S.charDeadZone && !isCut {
            charDwellStart = nil
        } else {
            if charDwellStart == nil { charDwellStart = now }
            if isCut || now - charDwellStart! >= S.charDwellMin {
                charCommitted = charSignal
                charDwellStart = nil
            }
        }
        let easeTau = isCut ? S.charCutEaseTau : S.charEaseTau
        charRendered += (1 - exp(-dt / easeTau)) * (charCommitted - charRendered)
        return charRendered
    }

    /// The ONLY operation that flips enabled (source: the toggle handler is
    /// deliberately not wired into photon.lua's F9).
    public mutating func toggle(now: Double) {
        enabled.toggle()
        targetEnabled = enabled
        if enabled { resolveAdaptiveParams(now: now) }
    }

    /// Manual filter cycle: red -> orange -> yellow -> green -> off (back to
    /// scene-adaptive). Instant snap, not an eased chase. No-op when disabled.
    public mutating func filterToggle(now: Double) {
        guard enabled else { return }
        if !manualFilterActive {
            manualFilterActive = true; manualFilterPos = 0 // red
        } else if manualFilterPos < 3 {
            manualFilterPos += 1
        } else {
            manualFilterActive = false
        }
        let snapTarget = manualFilterActive ? manualFilterPos : ChromeStateModel.chromeFilter
        charSignal = snapTarget; charCommitted = snapTarget; charRendered = snapTarget; charDwellStart = nil
        filterPosRendered = snapTarget
        resolveAdaptiveParams(now: now)
    }

    /// The PAUSE transition (not unpause, not a round trip) clears the manual
    /// override. Returns true when an override was cleared.
    @discardableResult
    public mutating func pauseTransition(now: Double) -> Bool {
        guard manualFilterActive else { return false }
        manualFilterActive = false
        if enabled { resolveAdaptiveParams(now: now) }
        return true
    }

    /// New file: neutral scene defaults, character state reset, manual
    /// override does NOT survive, then carryover rendezvous.
    public mutating func fileLoaded(now: Double) {
        carryoverSawFileLoaded = true
        hasFeed = false
        sceneSat = 0.10
        sceneContrast = 0.35
        sceneHue = nil; sceneHueSmoothed = nil
        charSignal = ChromeStateModel.chromeFilter; charCommitted = ChromeStateModel.chromeFilter
        charRendered = ChromeStateModel.chromeFilter; charDwellStart = nil
        manualFilterActive = false
        charLastT = 0; tier1LastT = 0
        resolveAdaptiveParams(now: now)
        filterPosRendered = filterPosResolved
        filterStrengthRendered = filterStrengthResolved
        contrastRendered = contrastResolved
        maybeApplyCarryover(now: now)
    }

    /// Latest absolute target declaration; latched even before file-loaded.
    public mutating func setTargetEnabled(_ value: Bool, now: Double) {
        targetEnabled = value
        carryoverSawTargetMessage = true
        maybeApplyCarryover(now: now)
    }

    /// The carryover decision runs only at the rendezvous (both saw-flags).
    private mutating func maybeApplyCarryover(now: Double) {
        guard carryoverSawFileLoaded && carryoverSawTargetMessage else { return }
        if targetEnabled && !enabled {
            enabled = true
        } else if !targetEnabled && enabled {
            enabled = false
        }
        // Same target + already on: the source re-applies; the value model has
        // nothing to re-apply - resolved state is recomputed on next ingest.
    }

    public mutating func apply(_ event: ChromeToggleEvent, now: Double) {
        switch event {
        case .toggle: toggle(now: now)
        case .filterToggle: filterToggle(now: now)
        case .pauseTransition: pauseTransition(now: now)
        case .fileLoaded: fileLoaded(now: now)
        case .setTargetEnabled(let v): setTargetEnabled(v, now: now)
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
  "source": "Sources/GorAVPlaybackCore/ChromeStateModel.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar c=ChromeStateModel();let before=c\nc.ingest(ChromeSceneSample(hue:.nan,saturation:0.5,contrast:0.2,isCut:false),now:1)\ncheck(c == before,\"nonfinite hue does not mutate model\")\nc.ingest(ChromeSceneSample(hue:0.2,saturation:0.5,contrast:0.2,isCut:false),now:.infinity)\ncheck(c == before,\"nonfinite clock does not mutate model\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL nonfinite hue does not mutate model
FAIL nonfinite clock does not mutate model


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. SOURCE-ONLY/INERT FILLER: published but excluded from shipping pump stock pending route decision.
