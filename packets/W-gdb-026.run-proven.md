# W-gdb-026 tone-map scalar golden vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-026

```packet-json
{
  "packet_id": "W-gdb-026",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "Sources/color-stage-tests/main.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVMetalPresenter/core/StagePass.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "scalar f(input: Double, params) -> Double per transfer function; per-group vector checker",
    "types": "ToneMapCurve + GamutMode vocabulary; compute float64, store float32; tol 1e-4 relative, dE-ITP <= 1.0",
    "ownership_lifetime": "pure scalars; no runtime shader compilation",
    "caller": "tone-map vector checker",
    "callee": "scalar transfer functions at the ColorStage surface (BT.1886 EOTF/inverse, perceptual gamut compression)"
  },
  "test": {
    "command": "python3 kits/tone-map-vectors/check.py",
    "expected": "exit 0; stdout 'tone-map-vectors: all groups within tolerance PASS'; a perturbed constant fails the affected vector group with the band named",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/tone-map-vectors/"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/tone-map-vectors/check.py",
        "block": "rf1"
      },
      {
        "path": "kits/tone-map-vectors/generate.py",
        "block": "rf2"
      },
      {
        "path": "kits/tone-map-vectors/vectors.json",
        "block": "rf3"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/tone-map-vectors/check.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:06:20.832007+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "tone-map-vectors: all groups within tolerance PASS",
    "inline_files": [
      {
        "path": "kits/tone-map-vectors/check.py",
        "block": "rf1",
        "sha256": "da7d8149c7bb699e29d91f36eeaa19b6e98c2edd6fa2f0aa412cd42c65837c2e"
      },
      {
        "path": "kits/tone-map-vectors/generate.py",
        "block": "rf2",
        "sha256": "e9adb39154fbff1a081e9c0abfcee7d6fb5f8ecf2459d0b56a1d7c240bb6b37a"
      },
      {
        "path": "kits/tone-map-vectors/vectors.json",
        "block": "rf3",
        "sha256": "93bca6c88a80679283f475f2b7e01c487cddaa1f46eb7186bb87ec135aa656ae"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7ffdcbb5e0e0e66f5e8b4e31ca92913b1fc374f6ef134ddeac9b9845fd965d4b",
    "last_5_lines": [
      "PASS bt1886-eotf (5 vectors within band)",
      "PASS bt1886-inverse (4 vectors within band)",
      "PASS bt1886-roundtrip-de-itp (3 vectors within band)",
      "PASS gamut-compress-bt2020-to-bt709 (4 vectors within band)",
      "tone-map-vectors: all groups within tolerance PASS"
    ],
    "receipt_sha256": "4b0703ec7237054b27501527c4bffe4feb04f52a52feb1f24788aebb1f1bd8db"
  }
}
```

## problem (what fails for the user)
the color stage's tone-map behavior has no offline-computed scalar golden vectors, so a math change in a transfer function ships as visibly wrong HDR with no test failing.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/color-stage-tests/main.swift (sha256 76de7b53, whole below) and Sources/GorAVMetalPresenter/core/StagePass.swift (sha256 9d3a46b3; color-pass section below).
- real test command: swift run color-stage-tests (12 PASS on Linux).

## expected behaviour
scalar golden vectors for BT.1886 EOTF and inverse plus perceptual gamut compression at stated primaries: published formulas, fixed precision, stated tolerance bands, edge inputs (0, near-0, 1, HDR max); generator script + vector tables. supports W-gdb-011 - vectors only, no shader code.

## exact call site and interface
the stage's color-pass parameter surface (pinned excerpt); vectors assert scalar in/out at that surface.

## pinned ABI decisions (integrator, 2026-11-15; primaries/precision/tolerances now pinned)
- vocabulary at the pin (ColorStage.swift): ToneMapCurve { none, clip, mobius, hable, reinhard }; SourceTRC { bt709, bt2020PQ, hlg, dolbyVision, unknown }; GamutMode { perceptual, relativeColorimetric }; defaultPeak: 100 nits SDR / 1000 nits PQ,HLG,DV
- primaries: BT.709 and BT.2020 xy triples per the public standards; MasteringPrimaries validity = allFiniteInUnitRange (SurfaceContract.swift, same pin)
- precision: vectors computed in Float64, stored at Float32 precision (the uniform lanes are F32); integer/digest fields byte-exact
- tolerances (integrator decision): transfer-function scalars within 1e-4 relative; dE-ITP <= 1.0 where a public oracle formula is cited; a failing vector names its band, never a silently widened pass
- edge inputs: 0, near-0 (1e-6), 1, HDR max at the row's peak (1000 default, 4000 signalled).

## behaviour that must not change
the 12 existing checks stay green; no runtime shader compilation is introduced.

## acceptance test (from the product repo)
vectors reproduce byte-identically from the generator; one perturbed constant fails the affected vector group.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/color-stage-tests/main.swift (sha256 76de7b53, lines 1-68 of 68)
```swift id=source1
import Foundation
import GorAVPlaybackCore

// Witness for the R9 color stage policy: curve selection, peak defaults,
// overrides, software fallback, receipts, input guards.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

// T1: sdr to sdr = no tone map, no fallback
let p1 = ColorStage.plan(source: SourceSignal(trc: .bt709), target: .sdr100, hardwareToneMapper: false)
check("T1", p1.curve == .none && !p1.softwareFallback && p1.receipts.contains("sdr-to-sdr:no-tone-map"))

// T2: hdr10 to sdr, no hw = mobius + software fallback, default peak 1000
let p2 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ), target: .sdr100, hardwareToneMapper: false)
check("T2", p2.curve == .mobius && p2.softwareFallback && p2.sourcePeakNits == 1000
      && p2.receipts.contains("hdr-to-sdr:mobius-default")
      && p2.receipts.contains("no-hw-tone-mapper:software-fallback"))

// T3: same with hw tone mapper = no fallback
let p3 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ), target: .sdr100, hardwareToneMapper: true)
check("T3", p3.curve == .mobius && !p3.softwareFallback)

// T4: signalled mastering peak wins over default; invalid signalled peak ignored
let p4 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 4000), target: .sdr100, hardwareToneMapper: true)
check("T4", p4.sourcePeakNits == 4000 && !p4.receipts.contains { $0.hasPrefix("src-peak-default") })
check("T4b", SourceSignal(trc: .bt2020PQ, sourcePeakNits: -5).sourcePeakNits == nil
      && SourceSignal(trc: .bt2020PQ, sourcePeakNits: .nan).sourcePeakNits == nil)

// T5: hlg to sdr
let p5 = ColorStage.plan(source: SourceSignal(trc: .hlg), target: .sdr100, hardwareToneMapper: false)
check("T5", p5.curve == .mobius && p5.sourcePeakNits == 1000)

// T6: dv without hw forces software even when curve is none (sdr-to-hdr path cannot occur for dv, use hdr target)
let dvTarget = DisplayTarget(targetTRC: .bt2020PQ, peakNits: 1000)!
let p6 = ColorStage.plan(source: SourceSignal(trc: .dolbyVision), target: dvTarget, hardwareToneMapper: false)
check("T6", p6.softwareFallback && p6.receipts.contains("dv-without-hw:software-fallback"))

// T7: sdr to hdr = passthrough, no inverse tone map
let p7 = ColorStage.plan(source: SourceSignal(trc: .bt709), target: dvTarget, hardwareToneMapper: false)
check("T7", p7.curve == .none && p7.receipts.contains("sdr-to-hdr:passthrough-no-inverse-tone-map"))

// T8: hdr to hdr, peak fits = none; exceeds = mobius
let p8a = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 600), target: dvTarget, hardwareToneMapper: true)
let p8b = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 4000), target: dvTarget, hardwareToneMapper: true)
check("T8", p8a.curve == .none && p8a.receipts.contains("hdr-to-hdr:peak-fits")
      && p8b.curve == .mobius && p8b.receipts.contains("hdr-to-hdr:mobius-down-map"))

// T9: curve override wins, receipt names it
let p9 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ),
                         target: DisplayTarget(targetTRC: .bt709, peakNits: 100, curveOverride: .hable)!,
                         hardwareToneMapper: true)
check("T9", p9.curve == .hable && p9.receipts.contains("curve-override:hable"))

// T10: target guards - bad peak/saturation refused
check("T10", DisplayTarget(targetTRC: .bt709, peakNits: 0) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 2.5) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: -1) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 2.0) != nil)

// T11: saturation and gamut carried into the plan
let p11 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ),
                          target: DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 0.8, gamut: .relativeColorimetric)!,
                          hardwareToneMapper: true)
check("T11", p11.saturation == 0.8 && p11.gamut == .relativeColorimetric)

print("color-stage-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
```

### Sources/GorAVMetalPresenter/core/StagePass.swift (sha256 9d3a46b3, lines 60-143 of 143)
```swift id=source2
public struct StagePassPipeline {
    fileprivate let state: MTLRenderPipelineState
    fileprivate let format: MTLPixelFormat
}

/// Per-frame stage. Does not claim P12 color parity. Identity is never clamped.
public final class MetalStagePass {
    private let device: MTLDevice
    private let library: MTLLibrary

    public init(device: MTLDevice) throws {
        self.device = device
        do {
            self.library = try device.makeLibrary(source: StagePassShader.source, options: nil)
        } catch {
            throw StagePassError.shaderCompileFailed
        }
    }

    public func makePipeline(colorPixelFormat: MTLPixelFormat) throws -> StagePassPipeline {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "stageVertex")
        desc.fragmentFunction = library.makeFunction(name: "stageFragment")
        desc.colorAttachments[0].pixelFormat = colorPixelFormat
        do {
            return StagePassPipeline(state: try device.makeRenderPipelineState(descriptor: desc), format: colorPixelFormat)
        } catch {
            throw StagePassError.pipelineFailed
        }
    }

    /// Encode one frame. `uniforms` is the RenderGraph.encode output for this
    /// frame's session; the pack is 64 bytes, asserted at the seam.
    public func encode(commandBuffer: MTLCommandBuffer,
                       pipeline: StagePassPipeline,
                       source: MTLTexture,
                       destination: MTLRenderPassDescriptor,
                       uniforms: FrameUniforms) throws {
        if case .failure(let reason) = StageColorAdmission.identity(uniforms) {
            throw StagePassError.color(reason)
        }
        guard let target = destination.colorAttachments[0].texture,
              commandBuffer.commandQueue.device.registryID == device.registryID,
              pipeline.state.device.registryID == device.registryID,
              pipeline.format == target.pixelFormat,
              source.device.registryID == device.registryID,
              target.device.registryID == device.registryID,
              source !== target, source.pixelFormat == target.pixelFormat,
              [.bgra8Unorm, .rgba8Unorm, .rgba16Float, .rgba32Float].contains(source.pixelFormat),
              source.sampleCount == 1, target.sampleCount == 1,
              source.textureType == .type2D, target.textureType == .type2D,
              Float(source.width) == uniforms.frameWidth, Float(source.height) == uniforms.frameHeight else {
            throw StagePassError.incompatibleResources
        }
        // Output fit bars must be defined, not stale contents from a prior frame.
        destination.colorAttachments[0].loadAction = .clear
        destination.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: destination) else { throw StagePassError.encoderUnavailable }
        defer { enc.endEncoding() }
        enc.setRenderPipelineState(pipeline.state)
        enc.setFragmentTexture(source, index: 0)
        try Self.bindGeometry(encoder: enc, uniforms: uniforms,
                              drawableWidth: target.width, drawableHeight: target.height)
        let bytes = uniforms.packedBytes()
        bytes.withUnsafeBytes { raw in
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    /// Shared vertex binding used by MetalRenderer's real present/readback path.
    /// Existing fragment output transform and subtitle composition stay intact.
    public static func bindGeometry(encoder: MTLRenderCommandEncoder, uniforms: FrameUniforms,
                                    drawableWidth: Int, drawableHeight: Int) throws {
        guard let q = StageGeometry.quad(uniforms: uniforms, drawableWidth: drawableWidth,
                                        drawableHeight: drawableHeight) else {
            throw StagePassError.unsupportedParameters
        }
        q.withUnsafeBytes { raw in
            encoder.setVertexBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
    }

}
#endif
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"group":"bt1886-eotf","precision":"float32","tol_rel":1e-4,"vectors":[{"in":0.0,"out":0.0},{"in":1e-6,"out":"<ref>"},{"in":0.18,"out":"<ref>"},{"in":1.0,"out":"<ref>"}],"dE_ITP_max":1.0}
```

```text id=rf1
#!/usr/bin/env python3
"""tone-map golden vector checker. Recomputes every vector from the cited
formula, compares within the group tolerance, and verifies the roundtrip
dE-ITP band. --perturb replaces gamma 2.4 with 2.2 and MUST fail the
bt1886-eotf group with the band named. Stdlib only, deterministic."""
import json,sys,struct,pathlib

def f32(x): return struct.unpack('f', struct.pack('f', x))[0]
LW = 100.0
def itp(r, g, b):
    return (0.5*r+0.5*g, 1.61375*r-3.32344*g+1.70968*b, 4.37806*r-4.24553*g-0.13253*b)
def de_itp(a, b):
    return 720.0 * ((a[0]-b[0])**2 + 0.25*(a[1]-b[1])**2 + (a[2]-b[2])**2) ** 0.5
def pq_encode(l):
    y = max(l, 0.0) / 10000.0
    return ((0.8359375 + 18.8515625 * y ** 0.1593017578125) / (1 + 18.6875 * y ** 0.1593017578125)) ** 78.84375
def pq_neutral_itp(v, gamma):
    e = pq_encode(LW * max(v, 0.0) ** gamma)
    return itp(e, e, e)
D65 = (0.3127, 0.3290)

def main():
    gamma = 2.2 if "--perturb" in sys.argv else 2.4
    spec = json.loads(pathlib.Path(__file__).with_name("vectors.json").read_text())
    bad = []
    for g in spec["groups"]:
        name = g["group"]
        fails = []
        for v in g["vectors"]:
            if name == "bt1886-eotf":
                got = f32(LW * max(v["in"], 0.0) ** gamma)
                ok = got == 0.0 and v["out"] == 0.0 or (v["out"] != 0.0 and abs(got - v["out"]) <= g["tol_rel"] * abs(v["out"]))
                if not ok: fails.append(("in=%g out=%g got=%g tol_rel=%g" % (v["in"], v["out"], got, g["tol_rel"])))
            elif name == "bt1886-inverse":
                got = f32((max(v["in"], 0.0) / LW) ** (1.0 / gamma))
                ok = got == 0.0 and v["out"] == 0.0 or (v["out"] != 0.0 and abs(got - v["out"]) <= g["tol_rel"] * abs(v["out"]))
                if not ok: fails.append(("in=%g out=%g got=%g tol_rel=%g" % (v["in"], v["out"], got, g["tol_rel"])))
            elif name == "bt1886-roundtrip-de-itp":
                got = f32((max(LW * max(v["in"], 0.0) ** gamma, 0.0) / LW) ** (1.0 / gamma))
                de = de_itp(pq_neutral_itp(v["in"], gamma), pq_neutral_itp(got, gamma))
                ok = de <= g["dE_ITP_max"]
                if not ok: fails.append(("in=%g dE_ITP=%g band<=%g" % (v["in"], de, g["dE_ITP_max"])))
            elif name == "gamut-compress-bt2020-to-bt709":
                got = [f32(D65[0] + 0.85 * (v["in"][0] - D65[0])), f32(D65[1] + 0.85 * (v["in"][1] - D65[1]))]
                ok = all(abs(got[i] - v["out"][i]) <= g["tol_rel"] * max(abs(v["out"][i]), 1e-6) for i in (0, 1))
                if not ok: fails.append(("in=%s out=%s got=%s" % (v["in"], v["out"], got)))
        if fails:
            print("FAIL %s: %d vector(s) out of band (%s)" % (name, len(fails), "; ".join(fails[:3])))
            bad.append(name)
        else:
            print("PASS %s (%d vectors within band)" % (name, len(g["vectors"])))
    if bad:
        print("tone-map-vectors: FAIL groups out of tolerance: %s" % ", ".join(bad))
        return 1
    print("tone-map-vectors: all groups within tolerance PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())

```

```text id=rf2
#!/usr/bin/env python3
"""Deterministic generator for tone-map scalar golden vectors.
Formulas: BT.1886 EOTF L = Lw * V^2.4 (ideal black Lb=0, Lw=100 nits SDR);
inverse V = (L/Lw)^(1/2.4); dE-ITP per ITU-R BT.2124 (PQ-encoded R'G'B').
Gamut compression: PROPOSED scalar xy compression toward D65, k=0.85 (labelled
proposed, not a published standard). Compute float64, store float32 precision.
Usage: python3 kits/tone-map-vectors/generate.py  (writes vectors.json byte-identically)"""
import json,struct,pathlib

def f32(x): return struct.unpack('f', struct.pack('f', x))[0]
LW, GAMMA = 100.0, 2.4
def eotf(v): return LW * max(v, 0.0) ** GAMMA
def eotf_inv(l): return (max(l, 0.0) / LW) ** (1.0 / GAMMA)
# BT.2124 ITP from PQ-encoded R'G'B' (normalized 0..1)
def itp(r, g, b):
    i = 0.5 * r + 0.5 * g
    t = 1.61375 * r - 3.32344 * g + 1.70968 * b
    p = 4.37806 * r - 4.24553 * g - 0.13253 * b
    return (i, t, p)
def de_itp(a, b):
    return 720.0 * ((a[0]-b[0])**2 + 0.25 * (a[1]-b[1])**2 + (a[2]-b[2])**2) ** 0.5
def pq_encode(l_nits):
    m1, m2, c1, c2, c3 = 0.1593017578125, 78.84375, 0.8359375, 18.8515625, 18.6875
    y = max(l_nits, 0.0) / 10000.0
    return ((c1 + c2 * y ** m1) / (1 + c3 * y ** m1)) ** m2
# scalar luminance-only PQ roundtrip via neutral (r=g=b) pairs
def pq_neutral_itp(v):
    l = eotf(v)
    e = pq_encode(l)
    return itp(e, e, e)
D65 = (0.3127, 0.3290)
K_COMPRESS = 0.85  # PROPOSED constant, not a published standard
def compress_xy(x, y):
    return (D65[0] + K_COMPRESS * (x - D65[0]), D65[1] + K_COMPRESS * (y - D65[1]))

groups = []
g1 = {"group": "bt1886-eotf", "formula": "L = 100 * V^2.4", "precision": "float32", "tol_rel": 1e-4,
      "vectors": [{"in": v, "out": f32(eotf(v))} for v in (0.0, 1e-6, 0.18, 0.5, 1.0)]}
g2 = {"group": "bt1886-inverse", "formula": "V = (L/100)^(1/2.4)", "precision": "float32", "tol_rel": 1e-4,
      "vectors": [{"in": l, "out": f32(eotf_inv(l))} for l in (0.0, f32(eotf(1e-6)), f32(eotf(0.18)), 100.0)]}
g3 = {"group": "bt1886-roundtrip-de-itp", "formula": "dE_ITP(BT.2124) of V vs inverse(EOTF(V)) in neutral PQ", "dE_ITP_max": 1.0,
      "vectors": [{"in": v, "out": f32(eotf_inv(eotf(v))), "dE_ITP": f32(de_itp(pq_neutral_itp(v), pq_neutral_itp(f32(eotf_inv(eotf(v))))))} for v in (1e-6, 0.18, 1.0)]}
g4 = {"group": "gamut-compress-bt2020-to-bt709", "formula": "PROPOSED xy' = D65 + 0.85*(xy - D65)", "precision": "float32", "tol_rel": 1e-4,
      "vectors": [{"in": [x, y], "out": [f32(a), f32(b)]} for (x, y), (a, b) in
                  [(p, compress_xy(*p)) for p in [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046), (0.4, 0.4)]]]}
spec = {"comment": "tone-map scalar golden vectors; formulas per group; gamut compression constant is PROPOSED, not a published standard; dE-ITP per BT.2124", "groups": [g1, g2, g3, g4]}
pathlib.Path(__file__).with_name("vectors.json").write_text(json.dumps(spec, indent=1, sort_keys=True) + "\n")
print("vectors.json regenerated (4 groups, %d vectors)" % sum(len(g["vectors"]) for g in [g1, g2, g3, g4]))

```

```text id=rf3
{
 "comment": "tone-map scalar golden vectors; formulas per group; gamut compression constant is PROPOSED, not a published standard; dE-ITP per BT.2124",
 "groups": [
  {
   "formula": "L = 100 * V^2.4",
   "group": "bt1886-eotf",
   "precision": "float32",
   "tol_rel": 0.0001,
   "vectors": [
    {
     "in": 0.0,
     "out": 0.0
    },
    {
     "in": 1e-06,
     "out": 3.981071657228885e-13
    },
    {
     "in": 0.18,
     "out": 1.6317514181137085
    },
    {
     "in": 0.5,
     "out": 18.946456909179688
    },
    {
     "in": 1.0,
     "out": 100.0
    }
   ]
  },
  {
   "formula": "V = (L/100)^(1/2.4)",
   "group": "bt1886-inverse",
   "precision": "float32",
   "tol_rel": 0.0001,
   "vectors": [
    {
     "in": 0.0,
     "out": 0.0
    },
    {
     "in": 3.981071657228885e-13,
     "out": 9.999999974752427e-07
    },
    {
     "in": 1.6317514181137085,
     "out": 0.17999999225139618
    },
    {
     "in": 100.0,
     "out": 1.0
    }
   ]
  },
  {
   "dE_ITP_max": 1.0,
   "formula": "dE_ITP(BT.2124) of V vs inverse(EOTF(V)) in neutral PQ",
   "group": "bt1886-roundtrip-de-itp",
   "vectors": [
    {
     "dE_ITP": 6.948261410677503e-13,
     "in": 1e-06,
     "out": 9.999999974752427e-07
    },
    {
     "dE_ITP": 3.910183750122087e-06,
     "in": 0.18,
     "out": 0.18000000715255737
    },
    {
     "dE_ITP": 0.0,
     "in": 1.0,
     "out": 1.0
    }
   ]
  },
  {
   "formula": "PROPOSED xy' = D65 + 0.85*(xy - D65)",
   "group": "gamut-compress-bt2020-to-bt709",
   "precision": "float32",
   "tol_rel": 0.0001,
   "vectors": [
    {
     "in": [
      0.708,
      0.292
     ],
     "out": [
      0.648705005645752,
      0.2975499927997589
     ]
    },
    {
     "in": [
      0.17,
      0.797
     ],
     "out": [
      0.19140499830245972,
      0.7268000245094299
     ]
    },
    {
     "in": [
      0.131,
      0.046
     ],
     "out": [
      0.15825499594211578,
      0.08844999969005585
     ]
    },
    {
     "in": [
      0.4,
      0.4
     ],
     "out": [
      0.3869050145149231,
      0.3893499970436096
     ]
    }
   ]
  }
 ]
}

```

```text id=actual_run_log
PASS bt1886-eotf (5 vectors within band)
PASS bt1886-inverse (4 vectors within band)
PASS bt1886-roundtrip-de-itp (3 vectors within band)
PASS gamut-compress-bt2020-to-bt709 (4 vectors within band)
tone-map-vectors: all groups within tolerance PASS
```
