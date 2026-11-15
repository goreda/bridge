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
