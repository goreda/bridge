# W-gdb-199c-in2tinct-13 - Safe quad admission for host transforms
state: OPEN / unclaimed
lab: in2tinct

## Product change
Keep hostTransformQuad API and valid output unchanged. Return an empty array for nonpositive/nonfinite scale input or coordinates not representable as finite Float. Document empty as refusal; no invented identity quad. Host wiring is outside this packet.

## Grounded gap and boundary
U2 fit/pan/zoom and crop geometry prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-13.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-13",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/HostTransform.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "Keep hostTransformQuad API and valid output unchanged. Return an empty array for nonpositive/nonfinite scale input or coordinates not representable as finite Float. Document empty as refusal; no invented identity quad. Host wiring is outside this packet.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 fit/pan/zoom and crop geometry prerequisite",
    "callee": "Sources/GorAVPlaybackCore/HostTransform.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-13.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-13",
    "paths": [
      "Sources/GorAVPlaybackCore/HostTransform.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-13.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-13.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-13.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:46.907722+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "218ec66bab5fcc0ce16e3b06e3693e8cddb8ee8243a24694a8966e6b2caaa9c6",
    "last_5_lines": [
      "FAIL bad y refused",
      "PASS valid geometry unchanged",
      "semantic failures=10",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/HostTransform.swift",
        "block": "source1",
        "sha256": "7d9e3f3f355689d6f1e558f1a14c5d096c931ba02ca3d5dbfa712f19bddd2d49",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-13.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-13.json",
        "block": "fixtures2",
        "sha256": "20f584b5eb1f9c36d2af73b7238fe1806bbd1f1db36d9a7ce075e9c04d88f93a"
      }
    ],
    "receipt_sha256": "8d608f06c4822c8cf51a8b5fdab39435f1c3064b4c163b90bc23fdcdb7750327"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation
// Sources/GorAVPlaybackCore/HostTransform.swift
// G3 host pan/zoom: pure math shared by the Metal renderer (per-frame quad) and by hosts that need the
// effective on-screen video rect. No Metal, no AppKit, no I/O. Linux only / Mac NOT_RUN for the GPU side.
//
// Units (fixed here, one definition):
//  - panX, panY: fractions of the drawable (1.0 = one full drawable width/height). +panX moves the image
//    right, +panY moves it up. Pan is applied AFTER zoom, in screen space.
//  - log2Zoom: zoom = 2^log2Zoom about the center of the aspect-fit rect (0 = fit, 1 = 2x). Zoom is a
//    magnification of the aspect-fit rect: it never changes the frame aspect.
//  - Subtitle/overlay composition rides the same quad in the fragment stage, so it moves with the video.

public struct HostTransform: Equatable, Sendable {
    public static let maxAbsPan = 16.0
    public static let maxAbsLog2Zoom = 8.0
    public let panX: Double
    public let panY: Double
    public let log2Zoom: Double
    /// nil when any value is non-finite or out of range (typed refusal at the call site, never clamped).
    public init?(panX: Double, panY: Double, log2Zoom: Double) {
        guard panX.isFinite, panY.isFinite, log2Zoom.isFinite,
              abs(panX) <= Self.maxAbsPan, abs(panY) <= Self.maxAbsPan,
              abs(log2Zoom) <= Self.maxAbsLog2Zoom else { return nil }
        self.panX = panX; self.panY = panY; self.log2Zoom = log2Zoom
    }
    public static let identity = HostTransform(panX: 0, panY: 0, log2Zoom: 0)!
    public var zoom: Double { exp2(log2Zoom) }
}

public enum HostTransformOutcome: Equatable, Sendable {
    case applied
    case refusedInvalid     // non-finite or out of range
    case refusedSealed      // renderer sealed or in a transition
    case refusedNotOpen     // no presenter yet
}

/// Quad vertices, same layout as MetalRenderer.quad: [x, y, u, v] for TL, BL, TR, BR in NDC, uv (0,0)=top-left.
/// `scaleX/scaleY` are the aspect-fit NDC half-extents (AspectFit.scaleX/scaleY).
public func hostTransformQuad(scaleX: Double, scaleY: Double, _ t: HostTransform) -> [Float] {
    let z = t.zoom
    let hx = scaleX * z, hy = scaleY * z
    let cx = 2.0 * t.panX, cy = 2.0 * t.panY      // NDC spans 2 per drawable
    let l = Float(cx - hx), r = Float(cx + hx), top = Float(cy + hy), bot = Float(cy - hy)
    return [l, top, 0, 0,
            l, bot, 0, 1,
            r, top, 1, 0,
            r, bot, 1, 1]
}

/// Rect in drawable pixels, origin top-left, y down.
public struct VideoRect: Equatable, Sendable {
    public let x: Double, y: Double, w: Double, h: Double
}

/// What G3 needs at open and after every transform: the frame as decoded and where it lands.
public struct EffectiveVideoGeometry: Equatable, Sendable {
    public let frameWidth: Int, frameHeight: Int          // presented frame pixels (display size as rendered)
    public let drawableWidth: Int, drawableHeight: Int    // drawable pixels
    public let rect: VideoRect                            // on-screen video rect incl. host transform (may extend past the drawable)
    public init(frameWidth: Int, frameHeight: Int, drawableWidth: Int, drawableHeight: Int, rect: VideoRect) {
        self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.drawableWidth = drawableWidth; self.drawableHeight = drawableHeight; self.rect = rect
    }
}

/// Aspect-fit rect of the frame in the drawable, then zoom about its center, then pan.
public func effectiveVideoRect(drawableW: Int, drawableH: Int, frameW: Int, frameH: Int, _ t: HostTransform) -> VideoRect? {
    guard drawableW > 0, drawableH > 0, frameW > 0, frameH > 0 else { return nil }
    let dw = Double(drawableW), dh = Double(drawableH)
    let s = min(dw / Double(frameW), dh / Double(frameH))
    let w = Double(frameW) * s * t.zoom, h = Double(frameH) * s * t.zoom
    let cx = dw / 2 + t.panX * dw
    let cy = dh / 2 - t.panY * dh
    return VideoRect(x: cx - w / 2, y: cy - h / 2, w: w, h: h)
}

public func effectiveVideoGeometry(drawableW: Int, drawableH: Int, frameW: Int, frameH: Int, _ t: HostTransform) -> EffectiveVideoGeometry? {
    guard let r = effectiveVideoRect(drawableW: drawableW, drawableH: drawableH, frameW: frameW, frameH: frameH, t) else { return nil }
    return EffectiveVideoGeometry(frameWidth: frameW, frameHeight: frameH, drawableWidth: drawableW, drawableHeight: drawableH, rect: r)
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[3]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "Sources/GorAVPlaybackCore/HostTransform.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor x in [Double.nan, Double.infinity, -1, 0, Double.greatestFiniteMagnitude] {\n check(hostTransformQuad(scaleX: x, scaleY: 1, .identity).isEmpty,\"bad x refused\")\n check(hostTransformQuad(scaleX: 1, scaleY: x, .identity).isEmpty,\"bad y refused\")\n}\nlet q=hostTransformQuad(scaleX: 1, scaleY: 0.5, .identity)\ncheck(q == [-1,0.5,0,0,-1,-0.5,0,1,1,0.5,1,0,1,-0.5,1,1],\"valid geometry unchanged\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL bad x refused
FAIL bad y refused
FAIL bad x refused
FAIL bad y refused
FAIL bad x refused
FAIL bad y refused
FAIL bad x refused
FAIL bad y refused
FAIL bad x refused
FAIL bad y refused
PASS valid geometry unchanged
semantic failures=10



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
