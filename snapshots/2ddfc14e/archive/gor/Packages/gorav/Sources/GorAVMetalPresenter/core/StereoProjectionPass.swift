#if canImport(Metal)
import Foundation
import Metal
import GorAVPlaybackCore

// P31-STEREO-PROJECTION native geometry pass (lane: stereo/photon).
// Faithful MSL translation of the ORIGINAL frozen vr180-look.lua legacy
// variant (current producer pin c455d945, historical oracle a426265):
// the exact emitted legacy GLSL recovered by replaying the source's own
// deterministic generation (vr_default_source + blink strip + native TB
// rewrite) - translation input only, not product runtime evidence.
// Operation order, compile-time constants and clamps are the original's:
// fixed output eye ownership with the 194h optical-centre baseline,
// combined +/-0.8 shift clamp, normalize -> roll -> pitch -> yaw, 1.7m
// sphere translation, hemisphere edge rule, nine source-space blur taps,
// peripheral darken, strip fade. The retained-but-UNCALLED helpers
// stereo_pair_uv/stereo_partition (legacy keeps them dead via
// vr_frame_fit/vr_frame_spacing = 0 defines) are omitted; every live
// statement below carries its original. Explicit blink-Off is the source
// variant's own bypass (the blink code is stripped from this variant),
// not a new camera implementation.
//
// ABI: the stereo stage block is the FULL 127-lane wire block (508 LE
// 32-bit words, LookParameterABI, VPL1 header excluded - the header is
// never bound as lane 0). Lanes are read as raw words and reinterpreted
// (as_type) so the producer's already-quantized Float32 bit patterns are
// consumed exactly; nothing is recomputed from unquantized doubles.
// Constants/defaults outside the driven lanes stay pinned to the
// source/table values baked into the original legacy variant.
//
// Boundary: this pass IS the output-sized pass (original hook WIDTH
// OUTPUT.w HEIGHT OUTPUT.h) and samples the pre-reprojection source
// directly; it never projects an already-letterboxed/flat-resampled
// image. The Off path stays the ordinary flat route byte-for-byte. A
// DEDICATED sampler is created here; the renderer's global nearest
// sampler is untouched. Y orientation is adapted exactly once (below).
// No pixel claim: native compile/GPU behavior NOT_RUN.

/// Lane word offsets in the 508-byte block, from the actual
/// LookParameterTable (GorAVPlaybackCore/LookParameters.swift).
public enum StereoProjectionLane {
    public static let vrNativeTb = 0
    public static let vrCrossEye = 1
    // vr_calibration (2) is declared in the original variant but unused
    // by its hook body; the faithful port does not invent a use.
    public static let vrHeadRoll = 3
    public static let vrYaw = 27
    public static let vrPitch = 28
    public static let vrFov = 29
    public static let vrRoll = 30
    public static let vrBaseIpd = 53
    public static let vrIpdNudge = 54
    public static let vrHeadX = 55
    public static let vrHeadY = 56
    public static let vrHeadZ = 57
    public static let vrSwapEyes = 58
    public static let wordCount = 127 // LookParameterTable.count
    public static let byteCount = 508 // 127 * 4 (VPL1 header excluded)
    /// The consumed lanes by table name (vr_calibration / source_layout /
    /// plain stay declared-but-unused, exactly as the legacy variant).
    static let consumedNames: [(String, Int)] = [
        ("vr_native_tb", vrNativeTb), ("vr_cross_eye", vrCrossEye),
        ("vr_head_roll", vrHeadRoll), ("vr_yaw", vrYaw),
        ("vr_pitch", vrPitch), ("vr_fov", vrFov), ("vr_roll", vrRoll),
        ("vr_base_ipd", vrBaseIpd), ("vr_ipd_nudge", vrIpdNudge),
        ("vr_head_x", vrHeadX), ("vr_head_y", vrHeadY),
        ("vr_head_z", vrHeadZ), ("vr_swap_eyes", vrSwapEyes),
    ]
}

public enum StereoProjectionError: Error, Equatable {
    /// Metal library compilation failed. The payload carries the NSError
    /// domain, code and localizedDescription from makeLibrary(source:) so
    /// the real compiler message is never discarded (52577f0d failure:
    /// the bare case left shader defect vs virtual venue undecided).
    case shaderCompileFailed(String)
    /// A consumed lane name/offset disagrees with LookParameterTable.
    /// Distinct from shaderCompileFailed: the two used to share one bare
    /// case, so a lane-layout drift surfaced as "shader compile failed".
    case laneLayoutMismatch(String)
    case pipelineFailed(String)
    case samplerFailed
    case encoderUnavailable
    case incompatibleResources
    case malformedBlock
}

/// MSL for the projection pass. Embedded as source (makeLibrary(source:))
/// so the SwiftPM target keeps its pure-Swift sources pin and no .metal
/// build step appears (the StagePassShader precedent).
public enum StereoProjectionShader {
    public static let source = """
#include <metal_stdlib>
using namespace metal;

// Original compile-time constants, pinned to the frozen legacy variant
// (VR_PURE_LOOK_ENABLED=false branch values).
#define PI 3.14159265359
#define PHYSICAL_GAP_FRAC 0.012500
#define EYE_GAP_BLUR_FRAC 0.500000
#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG 90.000000
#define ZOOM_COMPENSATION_STRENGTH 0.007500
#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC 0.007500
#define ZOOM_REFERENCE_FOV_DEG 90.000000
#define PARALLAX_CORRECTION_STRENGTH 0.400000
#define PARALLAX_CORRECTION_DISPARITY -0.400000
#define PERIPHERAL_VIGNETTE_START_FRAC 0.250000
#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH 1.000000
#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH 0.001500
#define PERIPHERAL_VIGNETTE_BLUR_SAMPLES 9
#define SPHERE_RADIUS_METERS 1.700000

struct ProjGeom {
    float2 targetSize; // drawable/output pixels (target_size)
    float2 sourceSize; // pre-reprojection source pixels (diagnostic/assert)
};

struct ProjOut {
    float4 pos [[position]];
};

// Full-output coverage; the original hook is OUTPUT-sized.
vertex ProjOut projVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? -1.0 : 1.0);
    ProjOut o;
    o.pos = float4(p, 0.0, 1.0);
    return o;
}

static inline float lane(constant uint* lanes, int i) {
    return as_type<float>(lanes[i]); // exact quantized Float32 word, never recomputed
}

// Original: native TB source sampling uses its own eye domain, never SBS
// reinterpretation (post-generation rewrite applied to the variant).
static inline float2 native_source_uv(float packed_x, float y, float vr_native_tb) {
    float eye = step(0.5, packed_x);
    return vr_native_tb > 0.5
        ? float2((packed_x - eye * 0.5) * 2.0, (y + eye) * 0.5)
        : float2(packed_x, y);
}

fragment float4 projFragment(ProjOut in [[stage_in]],
                             texture2d<float> src [[texture(0)]],
                             sampler projSampler [[sampler(0)]],
                             constant uint* lanes [[buffer(0)]],
                             constant ProjGeom& g [[buffer(1)]]) {
    const float vr_native_tb = lane(lanes, 0);
    const float vr_cross_eye = lane(lanes, 1);
    const float vr_head_roll = lane(lanes, 3);
    const float vr_yaw = lane(lanes, 27);
    const float vr_pitch = lane(lanes, 28);
    const float vr_fov = lane(lanes, 29);
    const float vr_roll = lane(lanes, 30);
    const float vr_base_ipd = lane(lanes, 53);
    const float vr_ipd_nudge = lane(lanes, 54);
    const float3 head_offset = float3(lane(lanes, 55), lane(lanes, 56), lane(lanes, 57));
    const float vr_swap_eyes = lane(lanes, 58);

    // Y ORIENTATION, ADAPTED ONCE: mpv HOOKED_pos and Metal [[position]]
    // share the top-left origin with y growing downward, so the original
    // eye_pos semantics carry over directly; the shader's own internal
    // ndc_y flip (image v down -> ray y up) is the original's, unchanged.
    float2 out_size = g.targetSize;
    float2 eye_pos = in.pos.xy / out_size;

    float half_gap    = PHYSICAL_GAP_FRAC * 0.25;
    float half_blur   = EYE_GAP_BLUR_FRAC * 0.25;
    float left_end    = 0.5 - half_gap;
    float right_start = 0.5 + half_gap;

    float tan_half_fov = tan(vr_fov * 0.5);

    // Zoom compensation Mechanism A (ZOOM_COMPENSATION_ENABLED == 1 in
    // the pinned variant).
    float vertical_height_scale = 1.0;
    float zoom_ref_tan_half_fov = tan((ZOOM_REFERENCE_FOV_DEG * (PI / 180.0)) * 0.5);
    float zoom_magnification = zoom_ref_tan_half_fov / tan_half_fov;
    float height_scale_full = clamp(
        ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC * zoom_magnification,
        ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC, 1.0
    );
    vertical_height_scale = mix(1.0, height_scale_full, ZOOM_COMPENSATION_STRENGTH);

    float top_margin    = (1.0 - vertical_height_scale) * 0.5;
    float bottom_margin = top_margin;
    float y_draw_start = top_margin;
    float y_draw_end   = 1.0 - bottom_margin;

    bool in_gap = (eye_pos.x >= left_end && eye_pos.x < right_start);
    if (in_gap) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float dist_from_edge = (eye_pos.x < 0.5) ? (left_end - eye_pos.x) : (eye_pos.x - right_start);
    float strip_blend = smoothstep(0.0, half_blur, dist_from_edge);
    strip_blend = pow(strip_blend, 0.25);

    float eye_aspect = (out_size.x * 0.5) / out_size.y;

    float is_right_eye = step(right_start, eye_pos.x);
    float2 eye_uv = float2(
        is_right_eye > 0.5
            ? (eye_pos.x - right_start) / (1.0 - right_start)
            : (eye_pos.x / left_end),
        eye_pos.y
    );

    // 194h fixed full-height viewports, rotating native optical-centre
    // baseline; cross/parallel reverse the viewer eye axis.
    float native_angle = vr_head_roll * (vr_cross_eye > 0.5 ? 1.0 : -1.0);
    float native_spacing = (0.5 + PHYSICAL_GAP_FRAC * 0.25) * out_size.x / out_size.y;
    float native_side = is_right_eye - 0.5;
    eye_uv.x -= native_side * native_spacing * (cos(native_angle) - 1.0) / (out_size.x * left_end / out_size.y);
    eye_uv.y -= native_side * native_spacing * sin(native_angle);
    eye_uv.y = clamp((eye_uv.y - y_draw_start) / (y_draw_end - y_draw_start), 0.0, 1.0);
    float ndc_x = (eye_uv.x * 2.0 - 1.0);
    float ndc_y = (1.0 - eye_uv.y * 2.0);  // flip: image v grows downward, ray y should grow upward

    // Peripheral vignette factor (PERIPHERAL_VIGNETTE_MODE == 1 branch).
    float dx = ndc_x * eye_aspect;
    float dy = ndc_y;
    float corner_mag = length(float2(eye_aspect, 1.0));
    float peripheral_radial = length(float2(dx, dy)) / corner_mag;
    float peripheral_factor = smoothstep(PERIPHERAL_VIGNETTE_START_FRAC, 1.0, peripheral_radial);

    float eye_sign = is_right_eye > 0.5 ? 1.0 : -1.0;

    // Parallax correction Mechanism B (PARALLAX_CORRECTION_ENABLED == 1).
    float parallax_ref_tan_half_fov = tan((ZOOM_REFERENCE_FOV_DEG * (PI / 180.0)) * 0.5);
    float magnification = parallax_ref_tan_half_fov / tan_half_fov;
    float excess_disparity = PARALLAX_CORRECTION_DISPARITY * (magnification - 1.0) * PARALLAX_CORRECTION_STRENGTH;

    float ipd_shift = vr_base_ipd + vr_ipd_nudge;
    // ONE shift, ONE clamp, ONE ndc_x write (original combined rule).
    float combined_horizontal_shift = clamp(excess_disparity + ipd_shift, -0.8, 0.8);
    ndc_x -= eye_sign * combined_horizontal_shift * 0.5;

    float3 ray = normalize(float3(
        ndc_x * tan_half_fov,
        ndc_y * tan_half_fov / eye_aspect,
        1.0
    ));

    // Roll AFTER the eye_aspect divide, BEFORE pitch/yaw, nowhere else.
    float cr = cos(vr_roll), sr = sin(vr_roll);
    float3 ray_rolled = float3(
        ray.x * cr - ray.y * sr,
        ray.x * sr + ray.y * cr,
        ray.z
    );

    float cp = cos(vr_pitch), sp = sin(vr_pitch);
    float3 ray_pitched = float3(
        ray_rolled.x,
        ray_rolled.y * cp - ray_rolled.z * sp,
        ray_rolled.y * sp + ray_rolled.z * cp
    );
    float cy = cos(vr_yaw), sy = sin(vr_yaw);
    float3 ray_world = float3(
        ray_pitched.x * cy + ray_pitched.z * sy,
        ray_pitched.y,
        -ray_pitched.x * sy + ray_pitched.z * cy
    );

    // Motion parallax from head position (1.7m sphere).
    float3 sphere_hit = ray_world * SPHERE_RADIUS_METERS;
    ray_world = normalize(sphere_hit - head_offset);

    // Spherical coordinates; original hemisphere edge rule.
    float u;
    if (ray_world.z <= 0.0) {
        u = (ray_world.x >= 0.0) ? 1.0 : 0.0;
    } else {
        float theta = atan2(ray_world.x, ray_world.z);
        u = (theta / PI) + 0.5;
        u = clamp(u, 0.0, 1.0);
    }

    float phi = asin(clamp(ray_world.y, -1.0, 1.0));
    float v = 0.5 - (phi / PI);
    v = clamp(v, 0.0, 1.0);

    // Original-eye half of the actual SBS/TB source.
    bool src_right_half = (is_right_eye > 0.5) != (vr_swap_eyes > 0.5);
    float src_u = src_right_half ? (u * 0.5 + 0.5) : (u * 0.5);

    // Peripheral blur: 1 center tap + (SAMPLES-1) ring taps, uniformly
    // weighted, applied in SOURCE UV space (original rule).
    float blur_radius = PERIPHERAL_VIGNETTE_BLUR_STRENGTH * peripheral_factor;
    float4 blurred_color = float4(0.0);
    if (blur_radius > 0.0) {
        float4 acc = float4(0.0);
        acc += src.sample(projSampler, native_source_uv(src_u, v, vr_native_tb));
        for (int i = 0; i < PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1; i++) {
            float angle = 6.28318530718 * float(i) / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1);
            float2 ring_offset = float2(cos(angle), sin(angle)) * blur_radius;
            acc += src.sample(projSampler, native_source_uv(src_u, v, vr_native_tb) + ring_offset);
        }
        blurred_color = acc / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES);
    } else {
        blurred_color = src.sample(projSampler, native_source_uv(src_u, v, vr_native_tb));
    }

    // Peripheral darken, then strip fade LAST (original order).
    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;
    float4 peripheral_color = mix(blurred_color, float4(0.0, 0.0, 0.0, 1.0), darken_amount);
    return mix(float4(0.0, 0.0, 0.0, 1.0), peripheral_color, strip_blend);
}
"""
}

/// Per-frame projection pass replacing the flat geometry operation on the
/// enabled native branch. Does not claim pixel parity: NOT_RUN.
public final class StereoProjectionPass {
    private let device: MTLDevice
    private let library: MTLLibrary
    private let pipelineState: MTLRenderPipelineState
    /// Dedicated projection sampler (linear/clamp, matching the original
    /// hook texture's filtering); the renderer's global nearest sampler
    /// is never touched, so unrelated 2D pixels cannot change.
    private let sampler: MTLSamplerState

    public init(device: MTLDevice) throws {
        self.device = device
        do {
            // Explicit compile options (PhotonMetalEffects precedent):
            // fast math DISABLED so the GPU arithmetic keeps the IEEE
            // semantics the source port assumes - a deliberate,
            // reviewable arithmetic choice for later controlled-input
            // visual comparison, never a silent nil-options default.
            let options = MTLCompileOptions(); options.fastMathEnabled = false
            self.library = try device.makeLibrary(source: StereoProjectionShader.source, options: options)
        } catch {
            let ns = error as NSError
            throw StereoProjectionError.shaderCompileFailed(
                "domain=\(ns.domain) code=\(ns.code): \(ns.localizedDescription)")
        }
        // Lane offsets are asserted equal to the host's LookParameterTable
        // (the same canonical 127-lane layout the stage block packs) at
        // construction - a layout drift fails typed, never mis-reads.
        for (name, offset) in StereoProjectionLane.consumedNames {
            guard let p = LookParameterTable.all.first(where: { $0.name == name }),
                  p.offset == offset else {
                let actual = LookParameterTable.all.first(where: { $0.name == name })?.offset
                throw StereoProjectionError.laneLayoutMismatch(
                    "\(name): expected offset \(offset), found \(actual.map(String.init) ?? "absent")")
            }
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "projVertex")
        desc.fragmentFunction = library.makeFunction(name: "projFragment")
        desc.colorAttachments[0].pixelFormat = .rgba32Float
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            let ns = error as NSError
            throw StereoProjectionError.pipelineFailed(
                "domain=\(ns.domain) code=\(ns.code): \(ns.localizedDescription)")
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        guard let s = device.makeSamplerState(descriptor: sd) else {
            throw StereoProjectionError.samplerFailed
        }
        self.sampler = s
    }

    /// Encode the projection into an output-sized rgba32Float working
    /// texture. `blockBytes` is the exact 508-byte shader payload (VPL1
    /// header excluded); anything else is a typed refusal, never a
    /// padded/truncated stand-in.
    public func encode(commandBuffer: MTLCommandBuffer,
                       source: MTLTexture,
                       destination: MTLTexture,
                       blockBytes: Data) throws {
        guard blockBytes.count == StereoProjectionLane.byteCount else {
            throw StereoProjectionError.malformedBlock
        }
        guard commandBuffer.commandQueue.device.registryID == device.registryID,
              source.device.registryID == device.registryID,
              destination.device.registryID == device.registryID,
              source !== destination,
              // The pre-reprojection source arrives in the surface's own
              // format (SDR rgba8/bgra8, EDR rgba16F) or, with sharp
              // enabled, the rgba32Float effects output; the GPU's
              // standard unpack is the original semantics. Destination is
              // always the rgba32Float working texture.
              [.rgba8Unorm, .bgra8Unorm, .rgba16Float, .rgba32Float].contains(source.pixelFormat),
              destination.pixelFormat == .rgba32Float,
              source.sampleCount == 1, destination.sampleCount == 1,
              source.textureType == .type2D, destination.textureType == .type2D else {
            throw StereoProjectionError.incompatibleResources
        }
        var geom = (targetSize: SIMD2<Float>(Float(destination.width), Float(destination.height)),
                    sourceSize: SIMD2<Float>(Float(source.width), Float(source.height)))
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = destination
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rp.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rp) else {
            throw StereoProjectionError.encoderUnavailable
        }
        defer { enc.endEncoding() }
        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        blockBytes.withUnsafeBytes { raw in
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        enc.setFragmentBytes(&geom, length: MemoryLayout.stride(ofValue: geom), index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
#endif
