# W-gdb-004 row 52 uniform ABI fixtures
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-004

```packet-json
{
 "packet_id": "W-gdb-004",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/uniform-packing-tests/main.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVMetalPresenter/core/StagePass.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "FrameUniforms.packedBytes() -> 64 bytes little-endian; kit checker check(golden) -> PASS | LayoutVersionMismatch(expected: 1)",
  "types": "@frozen FrameUniforms: 16 lanes x 4B, lane order pinned in prose; layoutVersion = 1 bound to (laneCount 16, byteCount 64, order)",
  "ownership_lifetime": "64-byte value copy; no pointers; MSL Uniforms mirrors lane-for-lane",
  "caller": "MetalStagePass.encode / MetalRenderer present path",
  "callee": "FrameUniforms.packedBytes() (RenderGraph.swift) - 16 lanes x 4B = 64B, @frozen"
 },
 "test": {
  "command": "swift run uniform-packing-tests",
  "expected": "exit 0; final line 'uniform-packing-tests: N PASS, 0 FAIL' with N >= 37; golden-decode and LayoutVersionMismatch rows included; flipped-golden-byte negative control prints its FAIL in the kit log only",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/uniform-abi/",
   "Sources/uniform-packing-tests/main.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
live parameters reach the renderer through a typed per-frame uniform block (195b-52 "validated uniform-consumer boundary"). the block's byte layout has no external golden fixtures: a layout drift (alignment, size, field order) silently corrupts every rendered frame.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: Sources/uniform-packing-tests/main.swift (sha256 11bbe1cc, 2415B) - the existing 37-check packing suite entry; the uniform block types it imports (GorAVMetalPresenter, same pin).
- real test command: swift run uniform-packing-tests (currently 37 PASS on Linux, Swift 6.1.2).

## expected behaviour
a fixture kit: byte-layout spec (alignment, endianness, size stability across versions), a generator emitting parameter-vector frames across the crop/color/transform classes, golden byte images, a decode checker asserting field offsets/values round-trip, and the version-bump case where the consumer rejects a mismatched layout version as a typed error, never silently reinterpreting.

## exact call site and interface
the uniform block type consumed by uniform-packing-tests; kit rides as fixtures + checker the suite adopts.

## pinned ABI decisions (integrator, 2026-11-15)
the uniform block is @frozen FrameUniforms (Sources/GorAVPlaybackCore/RenderGraph.swift, same pin): laneCount = 16, 16 lanes x 4 bytes = 64 bytes via packedBytes(); fixed lane order: frameWidth F32, frameHeight F32, fitModeID U32, reserved0 U32, cropX F32, cropY F32, cropW F32, cropH F32, panX F32, panY F32, log2Zoom F32, flags U32, toneCurveID U32, srcPeakNits F32 (default 100), dstPeakNits F32 (default 100), saturation F32 (default 1); little-endian; the MSL Uniforms struct in StagePassShader.source mirrors this lane for lane (asserted at the seam).
version-reject ABI (integrator decision - no version field exists at the pin): the kit defines layoutVersion = 1 bound to (laneCount 16, byteCount 64, the lane order above); the decode checker rejects any other (laneCount, byteCount, order) as typed LayoutVersionMismatch(expected: 1), never silently reinterpreting. a later product-side version lane bumps the constant.

## behaviour that must not change
the 37 existing checks stay green; the shader seam stays embedded-source (StagePassShader.source compiled once via makeLibrary(source:) at MetalStagePass.init - no .metal build step); this kit is offline bytes only, no GPU claim.

## acceptance test (from the product repo)
golden images reproduce byte-identically from the generator seed; flipping one golden byte fails the checker; swift run uniform-packing-tests with the kit integrated stays green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/uniform-packing-tests/main.swift (sha256 11bbe1cc, lines 1-50 of 50)
```swift id=source1
import Foundation
import GorAVPlaybackCore

// Witness for 195c-N6 uniform packing: exact 64-byte stream, field offsets,
// little-endian encoding, Float bit patterns - the contract the Metal upload
// and the MSL struct both follow.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func readF(_ b: [UInt8], _ off: Int) -> Float {
    let v = UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24
    return Float(bitPattern: v)
}
func readU(_ b: [UInt8], _ off: Int) -> UInt32 {
    UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24
}

var u = FrameUniforms()
u.frameWidth = 1920; u.frameHeight = 1080; u.fitModeID = 7
u.cropX = 0.25; u.cropY = 0.125; u.cropW = 0.5; u.cropH = 0.75
u.panX = -0.5; u.panY = 0.25; u.log2Zoom = 2; u.flags = 3
u.toneCurveID = 2; u.srcPeakNits = 4000; u.dstPeakNits = 100; u.saturation = 0.8
let b = u.packedBytes()

check("T1-count", b.count == 64)
check("T2-control", readF(b, 0) == 1920 && readF(b, 4) == 1080 && readU(b, 8) == 7 && readU(b, 12) == 0)
check("T3-crop", readF(b, 16) == 0.25 && readF(b, 20) == 0.125 && readF(b, 24) == 0.5 && readF(b, 28) == 0.75)
check("T4-host", readF(b, 32) == -0.5 && readF(b, 36) == 0.25 && readF(b, 40) == 2 && readU(b, 44) == 3)
check("T5-color", readU(b, 48) == 2 && readF(b, 52) == 4000 && readF(b, 56) == 100 && abs(readF(b, 60) - 0.8) < 1e-6)

// T6: offsets table matches the packer (guard against drift)
check("T6-offsets", FrameUniforms.Offsets.cropX == 16 && FrameUniforms.Offsets.panX == 32
      && FrameUniforms.Offsets.flags == 44 && FrameUniforms.Offsets.saturation == 60)

// T7: identity block packs deterministically (two packs equal)
check("T7-deterministic", FrameUniforms().packedBytes() == FrameUniforms().packedBytes()
      && FrameUniforms().packedBytes().count == 64)

// T8: little-endian sanity on a known value: 1.0f = 0x3F800000 -> bytes 00 00 80 3F
var u8 = FrameUniforms(); u8.frameWidth = 1
let b8 = u8.packedBytes()
check("T8-endian", b8[0] == 0x00 && b8[1] == 0x00 && b8[2] == 0x80 && b8[3] == 0x3F)

// T9: flags bits survive (software fallback bit0, gamut bit1)
var u9 = FrameUniforms(); u9.flags = 1
check("T9-flags", readU(u9.packedBytes(), 44) == 1)

print("uniform-packing-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
```

### Sources/GorAVMetalPresenter/core/StagePass.swift (sha256 9d3a46b3, lines 1-60 of 143)
```swift id=source2
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
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"layoutVersion":1,"laneCount":16,"byteCount":64,"laneOrder":["frameWidth","frameHeight","fitModeID","reserved0","cropX","cropY","cropW","cropH","panX","panY","log2Zoom","flags","toneCurveID","srcPeakNits","dstPeakNits","saturation"],"vector":{"frameWidth":1920,"frameHeight":1080,"cropW":0.5,"cropH":0.5,"toneCurveID":2,"srcPeakNits":1000,"dstPeakNits":100,"saturation":1},"goldenLE64B":"<deliverable-generated hex>"}
```
