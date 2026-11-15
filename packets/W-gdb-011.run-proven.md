# W-gdb-011 N7 mobius tone map (rewrites W-0277)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-011

```packet-json
{
  "packet_id": "W-gdb-011",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
  "touched_files": [
    {
      "path": "Sources/GorAVMetalPresenter/core/StagePass.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/color-stage-tests/main.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "ColorStage.plan(source: SourceSignal, target: DisplayTarget, hardwareToneMapper: Bool) -> ToneMapPlan; new mobius pass reads FrameUniforms color lanes",
    "types": "ToneMapCurve { none, clip, mobius, hable, reinhard }; SourceTRC 5 cases; GamutMode { perceptual, relativeColorimetric }; defaultPeak 100/1000 nits; DisplayTarget guards: peakNits > 0, saturation in [0, 2.0]",
    "ownership_lifetime": "parameters ride the FrameUniforms 64-byte value block; no runtime shader compilation added",
    "caller": "render graph color stage (ColorStage.plan consumer)",
    "callee": "new mobius tone-map pass + ColorStage/ToneMapPlan vocabulary (ColorStage.swift) + FrameUniforms color lanes"
  },
  "test": {
    "command": "swift run color-stage-tests",
    "expected": "exit 0; final line 'color-stage-tests: N PASS, 0 FAIL' with N >= 12; new scalar rows within 1e-4 relative; a row outside tolerance prints its band",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/GorAVPlaybackCore/ or Sources/GorAVMetalPresenter/core/",
      "Sources/color-stage-tests/main.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/color-stage-tests/main.swift",
        "block": "rf0"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "c82dc6b8d46f81fc521ff93231060ea7b57b330a",
    "command": "swift run color-stage-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:30:09.376638+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "color-stage-tests: 12 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/color-stage-tests/main.swift",
        "block": "rf0",
        "sha256": "76de7b5340bdc48b6ed935c14abe68da308e586d54ce3ceb977d003cd6dace0e"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "40ae925bbcbb50b40dabceede0e14cecde7275333e43dc3a899d96787cb7d32e",
    "last_5_lines": [
      "[69/72] Wrapping AST for color-stage-tests for debugging",
      "[70/72] Write Objects.LinkFileList",
      "[71/72] Linking color-stage-tests",
      "Build complete! (7.28s)",
      "color-stage-tests: 12 PASS, 0 FAIL"
    ],
    "receipt_sha256": "d57836cf2baefe4ad4e799e64254491ed882a39fb9abf3d29ff80a4bf7acbf98"
  }
}
```

## problem (what fails for the user)
HDR tone mapping is on the render graph's color stage, but the mobius->BT.1886/perceptual-gamut pass exists only as an open request with no generator-compatible implementation bound to the stage; wrong tone mapping shows as blown highlights or washed HDR for the user.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVMetalPresenter/core/StagePass.swift (sha256 9d3a46b3, 6249B) - the stage-pass seam; Sources/color-stage-tests/main.swift (sha256 76de7b53, 4131B) - the existing 12-check color-stage suite; Sources/render-graph-tests/main.swift (same pin) - graph routing.
- real test command: swift run color-stage-tests (12 PASS on Linux, Swift 6.1.2).

## expected behaviour
a generator-compatible mobius tone-map pass targeting BT.1886 with perceptual gamut compression: luminance units, transfer/range, gamut transform and parameter domains pinned below (integrator decision); portable reference implementation + scalar checks, dE-ITP where oracle terms apply. the new pass adds no runtime shader source compilation - parameters ride the typed per-frame uniform block.

## exact call site and interface
the StagePass color-stage seam and the color-stage-tests executable; the new pass integrates as a stage with its parameters in the typed uniform block.

## pinned ABI decisions (integrator, 2026-11-15; domains now pinned)
parameter domains from ColorStage.swift + RenderGraph.swift at the pin:
- public enum ToneMapCurve: String, CaseIterable { none, clip, mobius, hable, reinhard } - the new pass is .mobius
- public enum SourceTRC: String { bt709, bt2020PQ, hlg, dolbyVision, unknown }
- defaultPeak(trc): bt709/unknown = 100 nits; hlg/bt2020PQ/dolbyVision = 1000 nits; a valid signalled mastering peak wins; negative/NaN signalled peaks ignored (color-stage-tests T4/T4b)
- DisplayTarget guards: peakNits > 0; saturation in [0, 2.0] inclusive (2.5 and -1 refused, T10); public enum GamutMode { perceptual, relativeColorimetric }
- uniform lanes (FrameUniforms): toneCurveID U32 via FrameUniforms.curveID(_:), srcPeakNits/dstPeakNits/saturation F32; gamutID: perceptual = 0, relativeColorimetric = 1
- luminance units: nits (cd/m2); PQ/HLG source normalized to its peak; BT.1886 target at targetPeakNits; dE-ITP oracle terms only where a public reference formula is cited.
the pinned StagePass compiles its embedded MSL once at MetalStagePass.init; the new pass adds no runtime shader compilation - parameters ride the uniform lanes above.

## behaviour that must not change
the 12 existing color-stage checks and 14 render-graph checks stay green; no unrelated delta-E variant; no GPU correctness claim from CPU execution.

## acceptance test (from the product repo)
the pass's scalar reference checks PASS on Linux; golden vectors (open request COL1 vectors may ride) reproduce within tolerance; existing suites stay green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVMetalPresenter/core/StagePass.swift (sha256 9d3a46b3, lines 1-143 of 143)
```swift id=source1
#if canImport(Metal) && canImport(CoreVideo)
import Foundation
import Metal
import CoreVideo
import GorAVPlaybackCore

// N6: screen-space geometry is shared with the actual presenter. Color is
// identity-only with typed refusals for unimplemented P12/gamut/software paths.
// Native compile and GPU behavior remain NOT_RUN on Linux.

/// MSL for the stage pass. Embedded as source (makeLibrary(source:)) so the
/// SwiftPM target keeps its pure-Swift sources pin and no .metal build step
/// appears. The Uniforms struct mirrors FrameUniforms.Offsets lane for lane.
public enum StagePassShader {
    public static let source = """
#include <metal_stdlib>
using namespace metal;

// 16 lanes x 4 bytes, mirrors FrameUniforms declaration order.
struct Uniforms {
    float frameWidth; float frameHeight; uint fitModeID; uint reserved0;
    float cropX; float cropY; float cropW; float cropH;
    float panX; float panY; float log2Zoom; uint flags;
    uint toneCurveID; float srcPeakNits; float dstPeakNits; float saturation;
};

struct VOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VOut stageVertex(uint vid [[vertex_id]], constant float4* quad [[buffer(0)]]) {
    VOut o;
    o.pos = float4(quad[vid].xy, 0.0, 1.0);
    o.uv = quad[vid].zw;
    return o;
}

fragment float4 stageFragment(VOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant Uniforms& u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.uv);
    return c; // Only validated identity-color copy is admitted below.
}
"""
}

public enum StagePassError: Error, Equatable {
    case shaderCompileFailed
    case pipelineFailed
    case unsupportedParameters
    case encoderUnavailable
    case incompatibleResources
    case color(StageColorRefusal)
}

/// Carries the format of the pipeline created by this stage, not an
/// arbitrary caller pipeline whose attachments cannot be inspected later.
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

### Sources/color-stage-tests/main.swift (sha256 76de7b53, lines 1-68 of 68)
```swift id=source2
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

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"curve":"mobius","srcPeakNits":1000,"dstPeakNits":100,"input":0.18,"expected":"<reference implementation value>","tol_rel":1e-4}
```


```text id=rf0
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

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-ajkbwdhf/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-ajkbwdhf/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Compiling GorAVCore AdmissionTable.swift
[8/15] Compiling GorAVCore Boundary.swift
[9/15] Emitting module GorAVCore
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-ajkbwdhf/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module color_stage_tests
[68/71] Compiling color_stage_tests main.swift
[69/72] Wrapping AST for color-stage-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking color-stage-tests
Build complete! (7.28s)
color-stage-tests: 12 PASS, 0 FAIL
```
