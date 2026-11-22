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
