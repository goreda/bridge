// Exact photon-sharp spatial and photon-grain OUTPUT math, translated via
// glslang 11.8 -> validated SPIR-V -> SPIRV-Cross 2021.01 MSL 2.1.
// This is a GPU stage, not the Lua control/scene-feed owner. Callers supply
// the actual live parameters. No menu toggle is enabled by this file.
#if canImport(Metal)
import Foundation
import Metal

public enum PhotonMetalError: Error {
    case invalidParameter(String), unsupportedTemporalMode, textureSize, byteBudget
    case allocation, encoder, shader(String)
}

/// Slots retain the live Lua declaration order, not the push-list order.
/// Every slot is a float lane, including validated integer/define parameters.
public struct PhotonMetalParameters: Sendable {
    public enum Family: Sendable { case sharp, grain }
    public let family: Family
    public fileprivate(set) var lanes: [Float]
    public static let sharpNames: [String] = ["PHOTON_SHARP_FRAME_PEAK", "PHOTON_SHARP_SCENE_CONTRAST", "PHOTON_SHARP_NOISE_LEVEL", "PHOTON_SHARP_MOTION_LEVEL", "PHOTON_SHARP_AMOUNT", "PHOTON_SHARP_FINE_COARSE", "PHOTON_SHARP_FACTOR_RENDERED", "PHOTON_SHARP_TEMPORAL_ALPHA", "PHOTON_SHARP_HALO_GUARD", "PHOTON_SHARP_TEXTURE_BIAS", "PHOTON_SHARP_FINE_STRENGTH", "PHOTON_SHARP_MEDIUM_STRENGTH", "PHOTON_SHARP_COARSE_STRENGTH", "PHOTON_SHARP_ALGO", "PHOTON_SHARP_BLOCK_LEVEL", "PHOTON_SHARP_RING_LEVEL", "PHOTON_SHARP_CONTENT_ADAPT", "PHOTON_SHARP_MEDIUM_BAND_ACTIVE", "PHOTON_SHARP_COARSE_BAND_ACTIVE"]
    public static let grainNames: [String] = ["GR_FRAME_PEAK", "GR_SCENE_CONTRAST", "GR_NOISE_LEVEL", "GR_MOTION_LEVEL", "GR_AMOUNT", "GR_ANIM_BUCKET", "GR_IS_HDR", "GR_SCENE_HUE", "GR_HUE_MOD_STRENGTH", "GR_RENDER_DENSITY", "GR_SIZE_COEFFICIENT", "GRAIN_SIZE", "GRAIN_SOFTNESS", "CHROMA_SPLIT", "DEVELOPMENT", "FINE_WEIGHT", "CRYSTAL_WEIGHT", "CLOUD_WEIGHT", "BASE_STRENGTH", "FINE_SIZE_RATIO", "CLOUD_SIZE_RATIO", "SKEW_STRENGTH", "GR_SHADOW_SENSITIVITY", "GR_MIDTONE_SENSITIVITY", "GR_HIGHLIGHT_SENSITIVITY", "STOCK_PRESET", "RES_ADAPT", "GR_MONO_MODE", "GRAIN_DEBUG_VISUALIZE"]
    public init(_ family: Family) {
        self.family = family
        lanes = Array(repeating: 0, count: 128)
        let defaults: [Float] = family == .sharp ? [-1.0, 0.35, 0.10, 0.20, 1.05, 0.50, 1.00, 0.611, 0.50, 0.50, 1.00, 1.00, 1.00, 0, 0.0, 0.0, 1, 1, 1] : [0.5, 0.35, 0.10, 0.20, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 50.0, 1.0, 0.4, 0.25, 0.40, 0.45, 6.0, 0.5, 2.2, 0.0, 1.8, 1.5, 2.7, 5, 1, 0, 0]
        for (i,v) in defaults.enumerated() { lanes[i] = v }
    }
    public mutating func set(_ name: String, _ value: Float) throws {
        let names = family == .sharp ? Self.sharpNames : Self.grainNames
        guard let index = names.firstIndex(of: name), value.isFinite else {
            throw PhotonMetalError.invalidParameter(name)
        }
        let integers = ["PHOTON_SHARP_ALGO", "PHOTON_SHARP_CONTENT_ADAPT",
            "PHOTON_SHARP_MEDIUM_BAND_ACTIVE", "PHOTON_SHARP_COARSE_BAND_ACTIVE",
            "STOCK_PRESET", "RES_ADAPT", "GR_MONO_MODE", "GRAIN_DEBUG_VISUALIZE"]
        if integers.contains(name) {
            let maxValue: Float = name == "PHOTON_SHARP_ALGO" ? 4 : (name == "STOCK_PRESET" ? 5 : 1)
            guard value.rounded(.towardZero) == value, value >= 0, value <= maxValue else {
                throw PhotonMetalError.invalidParameter(name)
            }
        }
        lanes[index] = value
    }
    public func value(_ name: String) -> Float? {
        let names = family == .sharp ? Self.sharpNames : Self.grainNames
        return names.firstIndex(of: name).map { lanes[$0] }
    }
}

/// Dedicated texture-in/texture-out stages. Sharp is source-space before
/// geometry. Grain is drawable-space after geometry, before subtitles/output.
/// Buffers/textures are command-buffer owned until GPU completion, even when
/// the caller abandons a precommit render. No reusable mutable scratch races.
public final class PhotonMetalEffects: @unchecked Sendable {
    private let device: MTLDevice
    private let clampSampler: MTLSamplerState
    private let repeatSampler: MTLSamplerState
    private let blueNoise: MTLTexture
    private let sharp: MTLRenderPipelineState
    private let grain: [MTLRenderPipelineState]
    private let budgetLock = NSLock()
    private var inFlightBytes = 0
    public let byteLimit: Int
    public var scratchBytesInUse: Int {
        budgetLock.lock(); defer { budgetLock.unlock() }; return inFlightBytes
    }
    private static let vertexSource = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct PhotonVertex { float4 position [[position]]; float2 uv [[user(locn0)]]; };
    vertex PhotonVertex photonVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        PhotonVertex o; o.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
        o.uv = p; return o;
    }
    """#
    public init(device: MTLDevice, byteLimit: Int = 256 * 1024 * 1024) throws {
        guard byteLimit > 0 else { throw PhotonMetalError.byteBudget }
        self.device = device; self.byteLimit = byteLimit
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear; desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge; desc.tAddressMode = .clampToEdge
        guard let clamp = device.makeSamplerState(descriptor: desc) else { throw PhotonMetalError.allocation }
        clampSampler = clamp
        desc.sAddressMode = .repeat; desc.tAddressMode = .repeat
        guard let repeatS = device.makeSamplerState(descriptor: desc) else { throw PhotonMetalError.allocation }
        repeatSampler = repeatS
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 64, height: 64, mipmapped: false)
        td.storageMode = .shared; td.usage = .shaderRead
        guard let noise = device.makeTexture(descriptor: td),
              let bytes = Data(base64Encoded: Self.blueNoiseBase64), bytes.count == 4096 else { throw PhotonMetalError.allocation }
        bytes.withUnsafeBytes { noise.replace(region: MTLRegionMake2D(0,0,64,64), mipmapLevel: 0,
                                              withBytes: $0.baseAddress!, bytesPerRow: 64) }
        blueNoise = noise
        func pipeline(_ source: String) throws -> MTLRenderPipelineState {
            let options = MTLCompileOptions(); options.fastMathEnabled = false
            let library: MTLLibrary
            do { library = try device.makeLibrary(source: source + "\n" + Self.vertexSource, options: options) }
            catch { throw PhotonMetalError.shader(String(describing: error)) }
            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = library.makeFunction(name: "photonVertex")
            pd.fragmentFunction = library.makeFunction(name: "main0")
            pd.colorAttachments[0].pixelFormat = .rgba32Float
            do { return try device.makeRenderPipelineState(descriptor: pd) }
            catch { throw PhotonMetalError.shader(String(describing: error)) }
        }
        sharp = try pipeline(Self.sharpSource)
        grain = try Self.grainSources.map(pipeline)
    }
    private final class Scratch: @unchecked Sendable {
        let textures: [MTLTexture]
        let release: @Sendable () -> Void
        init(_ textures: [MTLTexture], release: @escaping @Sendable () -> Void) {
            self.textures = textures; self.release = release
        }
        deinit { release() }
    }
    private func allocate(_ sizes: [(Int, Int)], on cb: MTLCommandBuffer) throws -> [MTLTexture] {
        var bytes = 0
        for (w,h) in sizes {
            guard w > 0, h > 0, w <= 16384, h <= 16384 else { throw PhotonMetalError.textureSize }
            bytes += w * h * 16
        }
        budgetLock.lock()
        guard bytes <= 128 * 1024 * 1024, bytes <= byteLimit - inFlightBytes else { budgetLock.unlock(); throw PhotonMetalError.byteBudget }
        inFlightBytes += bytes; budgetLock.unlock()
        var textures: [MTLTexture] = []
        for (w,h) in sizes {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
            td.storageMode = .private; td.usage = [.shaderRead, .renderTarget]
            guard let t = device.makeTexture(descriptor: td) else {
                budgetLock.lock(); inFlightBytes -= bytes; budgetLock.unlock(); throw PhotonMetalError.allocation
            }
            textures.append(t)
        }
        let reservedBytes = bytes
        let lease = Scratch(textures) { [self] in
            budgetLock.lock(); inFlightBytes -= reservedBytes; budgetLock.unlock()
        }
        cb.addCompletedHandler { _ in withExtendedLifetime(lease) {} }
        return textures
    }
    private func pass(_ pipeline: MTLRenderPipelineState, on cb: MTLCommandBuffer,
                      output: MTLTexture, textures: [MTLTexture], samplers: [MTLSamplerState],
                      parameters: PhotonMetalParameters) throws {
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = output
        rp.colorAttachments[0].loadAction = .dontCare; rp.colorAttachments[0].storeAction = .store
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { throw PhotonMetalError.encoder }
        e.setRenderPipelineState(pipeline)
        for (i,t) in textures.enumerated() { e.setFragmentTexture(t, index: i) }
        for (i,s) in samplers.enumerated() { e.setFragmentSamplerState(s, index: i) }
        parameters.lanes.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
    }
    public func encodeSharp(commandBuffer cb: MTLCommandBuffer, source: MTLTexture,
                            parameters: PhotonMetalParameters, temporalMode: Int = 0) throws -> MTLTexture {
        guard parameters.family == .sharp else { throw PhotonMetalError.invalidParameter("family") }
        guard temporalMode == 0 else { throw PhotonMetalError.unsupportedTemporalMode }
        let output = try allocate([(source.width,source.height)], on: cb)[0]
        try pass(sharp, on: cb, output: output, textures: [source], samplers: [clampSampler], parameters: parameters)
        return output
    }
    public func encodeGrain(commandBuffer cb: MTLCommandBuffer, source: MTLTexture,
                            sourceWidth: Int, sourceHeight: Int,
                            parameters: PhotonMetalParameters) throws -> MTLTexture {
        guard parameters.family == .grain, sourceWidth > 0, sourceHeight > 0 else { throw PhotonMetalError.invalidParameter("family/source raster") }
        let w = source.width, h = source.height
        let t = try allocate([(1,h),(w,1),(1,h),(w,1),(w,h)], on: cb)
        var p = parameters
        p.lanes[124] = Float(sourceWidth); p.lanes[125] = Float(sourceHeight)
        try pass(grain[0], on: cb, output: t[0], textures: [source], samplers: [clampSampler], parameters: p)
        try pass(grain[1], on: cb, output: t[1], textures: [source], samplers: [clampSampler], parameters: p)
        try pass(grain[2], on: cb, output: t[2], textures: [source,t[0]], samplers: [clampSampler,clampSampler], parameters: p)
        try pass(grain[3], on: cb, output: t[3], textures: [source,t[1]], samplers: [clampSampler,clampSampler], parameters: p)
        try pass(grain[4], on: cb, output: t[4], textures: [blueNoise,source,t[2],t[3]],
                 samplers: [repeatSampler,clampSampler,clampSampler,clampSampler], parameters: p)
        return t[4]
    }
    private static let blueNoiseBase64 = "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"
    private static let sharpSource = #"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float peak;
    float contrast;
    float _noise;
    float motion;
    float amount;
    float fine_mix;
    float alpha;
    float block;
    float ring;
    bool has_feed;
};

struct Nbhd3
{
    float c;
    float n;
    float s;
    float e;
    float w;
    float nw;
    float ne;
    float sw;
    float se;
    float lo;
    float hi;
    float rcas_lo;
    float rcas_hi;
};

struct PhotonUniforms
{
    float4 values[32];
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float get_luma(thread const float3& c)
{
    return dot(c, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
}

static inline __attribute__((always_inline))
Params unpack_params(constant PhotonUniforms& ubo)
{
    Params p;
    p.amount = fast::clamp(ubo.values[1].x, 0.0, 128.0);
    p.fine_mix = fast::clamp(ubo.values[1].y + ubo.values[2].y, 0.0, 1.0);
    p.motion = fast::clamp(ubo.values[0].w, 0.0, 1.0);
    p.alpha = fast::clamp(ubo.values[1].w, 0.0, 1.0);
    float fed_peak = ubo.values[0].x;
    float fed_contrast = ubo.values[0].y;
    float fed_noise = ubo.values[0].z;
    p.has_feed = fed_peak > (-0.5);
    float _228;
    if (p.has_feed)
    {
        _228 = fast::clamp(fed_peak, 0.0, 1.0);
    }
    else
    {
        _228 = 0.5;
    }
    p.peak = _228;
    float _239;
    if (p.has_feed)
    {
        _239 = fast::clamp(fed_contrast, 0.0, 1.0);
    }
    else
    {
        _239 = 0.3499999940395355224609375;
    }
    p.contrast = _239;
    float _250;
    if (p.has_feed)
    {
        _250 = fast::clamp(fed_noise, 0.0, 1.0);
    }
    else
    {
        _250 = 0.100000001490116119384765625;
    }
    p._noise = _250;
    p.block = fast::clamp(ubo.values[3].z, 0.0, 1.0);
    p.ring = fast::clamp(ubo.values[3].w, 0.0, 1.0);
    return p;
}

static inline __attribute__((always_inline))
float read_luma(thread const int2& p, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    float3 param = HOOKED_raw.read(uint2(p), 0).xyz;
    return get_luma(param);
}

static inline __attribute__((always_inline))
Nbhd3 sample_nbhd3(thread const int2& sp, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    int2 param = sp;
    Nbhd3 v;
    v.c = read_luma(param, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_1 = sp + int2(0, -1);
    v.n = read_luma(param_1, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_2 = sp + int2(0, 1);
    v.s = read_luma(param_2, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_3 = sp + int2(1, 0);
    v.e = read_luma(param_3, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_4 = sp + int2(-1, 0);
    v.w = read_luma(param_4, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_5 = sp + int2(-1);
    v.nw = read_luma(param_5, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_6 = sp + int2(1, -1);
    v.ne = read_luma(param_6, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_7 = sp + int2(-1, 1);
    v.sw = read_luma(param_7, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_8 = sp + int2(1);
    v.se = read_luma(param_8, HOOKED_raw, HOOKED_rawSmplr);
    v.lo = fast::min(v.c, fast::min(fast::min(v.n, v.s), fast::min(v.e, v.w)));
    v.lo = fast::min(v.lo, fast::min(fast::min(v.nw, v.ne), fast::min(v.sw, v.se)));
    v.hi = fast::max(v.c, fast::max(fast::max(v.n, v.s), fast::max(v.e, v.w)));
    v.hi = fast::max(v.hi, fast::max(fast::max(v.nw, v.ne), fast::max(v.sw, v.se)));
    float cross_sum = ((v.n + v.e) + v.w) + v.s;
    v.rcas_lo = ((4.0 * v.lo) - cross_sum) + v.c;
    v.rcas_hi = ((4.0 * v.hi) - cross_sum) + v.c;
    return v;
}

static inline __attribute__((always_inline))
void estimate_fallback(thread const Nbhd3& v, thread float& peak_est, thread float& contrast_est, thread float& noise_est)
{
    peak_est = fast::clamp(v.c, 0.0, 1.0);
    float local_range = v.hi - v.lo;
    contrast_est = fast::clamp(local_range * 1.35000002384185791015625, 0.0, 1.0);
    float mean3 = ((((v.c + v.n) + v.s) + v.e) + v.w) * 0.20000000298023223876953125;
    float dev = ((((abs(v.c - mean3) + abs(v.n - mean3)) + abs(v.s - mean3)) + abs(v.e - mean3)) + abs(v.w - mean3)) * 0.20000000298023223876953125;
    float noisiness = fast::clamp(dev * 9.0, 0.0, 1.0);
    noise_est = noisiness * (1.0 - smoothstep(0.0, 0.25, local_range));
}

static inline __attribute__((always_inline))
int res_profile(thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    float h = float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y;
    if (h < 720.0)
    {
        return 0;
    }
    if (h <= 1088.0)
    {
        return 1;
    }
    return 2;
}

static inline __attribute__((always_inline))
float soft_lim(thread const float& v, thread const float& s)
{
    float vs = v / s;
    float vs2 = vs * vs;
    return (fast::clamp((abs(vs) * (27.0 + vs2)) / (27.0 + (9.0 * vs2)), 0.0, 1.0) * s) * sign(v);
}

static inline __attribute__((always_inline))
float algo_perceptual(thread const int2& sp, thread const float& orig_l, thread const Nbhd3& v, thread const Params& p, thread const float& strength)
{
    float blur = (((2.0 * (((v.n + v.e) + v.w) + v.s)) + (((v.nw + v.ne) + v.sw) + v.se)) + (4.0 * v.c)) / 16.0;
    float c_comp = fast::clamp(0.2666666805744171142578125 + (0.89999997615814208984375 * exp2((blur * blur) * (-7.400000095367431640625))), 0.0, 1.0);
    float b_diff_c = (blur - v.c) * (blur - v.c);
    float b_diff_n = (blur - v.n) * (blur - v.n);
    float b_diff_s = (blur - v.s) * (blur - v.s);
    float b_diff_e = (blur - v.e) * (blur - v.e);
    float b_diff_w = (blur - v.w) * (blur - v.w);
    float b_diff_nw = (blur - v.nw) * (blur - v.nw);
    float b_diff_ne = (blur - v.ne) * (blur - v.ne);
    float b_diff_sw = (blur - v.sw) * (blur - v.sw);
    float b_diff_se = (blur - v.se) * (blur - v.se);
    float edge_val = (((1.37999999523162841796875 * b_diff_c) + (1.14999997615814208984375 * (((b_diff_n + b_diff_s) + b_diff_e) + b_diff_w))) + (0.920000016689300537109375 * (((b_diff_nw + b_diff_ne) + b_diff_sw) + b_diff_se))) * c_comp;
    float pm_p = 1.0;
    float edge_sharp = pow(edge_val, 0.5 / (pm_p + 9.9999997473787516355514526367188e-06));
    edge_sharp = fast::clamp((edge_sharp * strength) * 0.5, 0.0, 1.0);
    float hp = orig_l - blur;
    float scale_lim = 0.0599999986588954925537109375 * (1.0 + strength);
    float boosted = hp * ((1.0 + edge_sharp) + (strength * 0.300000011920928955078125));
    float param = boosted;
    float param_1 = scale_lim + 9.9999997473787516355514526367188e-06;
    float limited = soft_lim(param, param_1);
    float sharp_luma = orig_l + limited;
    return sharp_luma;
}

static inline __attribute__((always_inline))
float2 edge_struct(thread const Nbhd3& v)
{
    float gx = ((v.ne - v.nw) + (2.0 * (v.e - v.w))) + (v.se - v.sw);
    float gy = ((v.sw - v.nw) + (2.0 * (v.s - v.n))) + (v.se - v.ne);
    float S = sqrt(((gx * gx) + (gy * gy)) + 9.9999997473787516355514526367188e-06);
    float _652;
    if ((abs(gx) + abs(gy)) > 9.9999997473787516355514526367188e-06)
    {
        _652 = abs(abs(gx) - abs(gy)) / (abs(gx) + abs(gy));
    }
    else
    {
        _652 = 0.0;
    }
    float C = _652;
    return float2(S, C);
}

static inline __attribute__((always_inline))
float learned_edge_confidence(thread const Nbhd3& v)
{
    float resp = ((v.c * 1.60000002384185791015625) + ((((v.n + v.s) + v.e) + v.w) * (-0.3499999940395355224609375))) + ((((v.nw + v.ne) + v.sw) + v.se) * (-0.2199999988079071044921875));
    return fast::clamp(abs(resp) * 2.2000000476837158203125, 0.0, 1.0);
}

static inline __attribute__((always_inline))
float blur_fine(thread const Nbhd3& v)
{
    return ((v.c * 0.4000000059604644775390625) + ((((v.n + v.s) + v.e) + v.w) * 0.100000001490116119384765625)) + ((((v.nw + v.ne) + v.sw) + v.se) * 0.02500000037252902984619140625);
}

static inline __attribute__((always_inline))
float clip_aware_push(thread const float& push, thread const float& orig_l, thread const Nbhd3& v, thread const float& strength)
{
    float overshoot_allow = 1.0 + (1.2000000476837158203125 * log2(1.0 + strength));
    float headroom_hi = fast::max(v.hi - orig_l, 9.9999997473787516355514526367188e-06) * overshoot_allow;
    float headroom_lo = fast::max(orig_l - v.lo, 9.9999997473787516355514526367188e-06) * overshoot_allow;
    float room = (push >= 0.0) ? headroom_hi : headroom_lo;
    return push * (room / ((room + (abs(push) * 0.1500000059604644775390625)) + 9.9999997473787516355514526367188e-06));
}

static inline __attribute__((always_inline))
float algo_structural(thread const int2& sp, thread const float& orig_l, thread const Nbhd3& v, thread const Params& p, thread const float& strength, constant PhotonUniforms& ubo)
{
    Nbhd3 param = v;
    float2 ec = edge_struct(param);
    float edge_strength = ec.x;
    float edge_coherence = ec.y;
    float directional_gain = smoothstep(0.0199999995529651641845703125, 0.1500000059604644775390625, edge_strength) * mix(0.300000011920928955078125, 1.0, edge_coherence);
    if (ubo.values[4].x == 1.0)
    {
        Nbhd3 param_1 = v;
        float learned_conf = learned_edge_confidence(param_1);
        directional_gain = mix(directional_gain, fast::max(directional_gain, learned_conf), 0.5);
    }
    Nbhd3 param_2 = v;
    float fine_b = blur_fine(param_2);
    float hp = orig_l - fine_b;
    float push = (strength * hp) * directional_gain;
    float param_3 = push;
    float param_4 = orig_l;
    Nbhd3 param_5 = v;
    float param_6 = strength;
    float sharp_luma = orig_l + clip_aware_push(param_3, param_4, param_5, param_6);
    return sharp_luma;
}

static inline __attribute__((always_inline))
float rcas_noise(thread const Nbhd3& v)
{
    float local_range = v.hi - v.lo;
    if (local_range < 9.9999997473787516355514526367188e-06)
    {
        return 1.0;
    }
    float hp = abs((((v.n + v.s) + v.e) + v.w) - (4.0 * v.c));
    float norm_hp = hp / (local_range + 9.9999997473787516355514526367188e-06);
    return smoothstep(0.1500000059604644775390625, 0.3499999940395355224609375, norm_hp);
}

static inline __attribute__((always_inline))
float algo_conservative(thread const int2& sp, thread const float& orig_l, thread const Nbhd3& v, thread const Params& p, thread const float& strength)
{
    Nbhd3 param = v;
    float fine_b = blur_fine(param);
    float hp = orig_l - fine_b;
    float local_range = v.hi - v.lo;
    float coring_w = smoothstep(0.02500000037252902984619140625, 0.07500000298023223876953125, local_range);
    hp *= coring_w;
    Nbhd3 param_1 = v;
    float noise_det = rcas_noise(param_1);
    hp *= (1.0 - noise_det);
    float push = (strength * 0.4000000059604644775390625) * hp;
    float headroom_hi = fast::max(v.hi - orig_l, 9.9999997473787516355514526367188e-06);
    float headroom_lo = fast::max(orig_l - v.lo, 9.9999997473787516355514526367188e-06);
    float room = (push >= 0.0) ? headroom_hi : headroom_lo;
    float w = room / ((room + abs(push)) + 9.9999997473787516355514526367188e-06);
    return orig_l + (push * w);
}

static inline __attribute__((always_inline))
float blur_coarse(thread const int2& sp, thread const float& center, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    int rp = res_profile(HOOKED_raw, HOOKED_rawSmplr);
    int _534;
    if (rp == 0)
    {
        _534 = 2;
    }
    else
    {
        _534 = (rp == 1) ? 3 : 4;
    }
    int off = _534;
    int2 param = sp + int2(-off, -off);
    float d1 = read_luma(param, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_1 = sp + int2(off, -off);
    float d2 = read_luma(param_1, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_2 = sp + int2(-off, off);
    float d3 = read_luma(param_2, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_3 = sp + int2(off, off);
    float d4 = read_luma(param_3, HOOKED_raw, HOOKED_rawSmplr);
    float sum = (center * 0.5) + ((((d1 + d2) + d3) + d4) * 0.100000001490116119384765625);
    return sum * 1.11111104488372802734375;
}

static inline __attribute__((always_inline))
float algo_aggressive(thread const int2& sp, thread const float& orig_l, thread const Nbhd3& v, thread const Params& p, thread const float& strength, thread const float& gf, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    Nbhd3 param = v;
    float fine_b = blur_fine(param);
    int2 param_1 = sp;
    float param_2 = v.c;
    float coarse_b = blur_coarse(param_1, param_2, HOOKED_raw, HOOKED_rawSmplr);
    float hp_fine = orig_l - fine_b;
    float hp_coarse = orig_l - coarse_b;
    float w_c = mix(0.60000002384185791015625, 0.89999997615814208984375, 1.0 - p.fine_mix);
    float w_f = 1.0 - (w_c * 0.5);
    float highpass = (hp_fine * w_f) + (hp_coarse * w_c);
    int rp = res_profile(HOOKED_raw, HOOKED_rawSmplr);
    float _1486;
    if (rp == 0)
    {
        _1486 = 0.0030000000260770320892333984375;
    }
    else
    {
        _1486 = (rp == 1) ? 0.00200000009499490261077880859375 : 0.001000000047497451305389404296875;
    }
    float coring_base = _1486;
    coring_base *= (1.0 + (1.5 * p.block));
    float local_range = v.hi - v.lo;
    float coring_w = smoothstep(coring_base, coring_base * 2.0, local_range);
    highpass *= coring_w;
    float push = (strength * 1.39999997615814208984375) * highpass;
    float param_3 = push;
    float param_4 = orig_l;
    Nbhd3 param_5 = v;
    float param_6 = strength;
    return orig_l + clip_aware_push(param_3, param_4, param_5, param_6);
}

static inline __attribute__((always_inline))
float blur_medium(thread const int2& sp, thread const Nbhd3& v, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    int2 param = sp + int2(0, -2);
    float h2 = read_luma(param, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_1 = sp + int2(0, 2);
    float v2 = read_luma(param_1, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_2 = sp + int2(-2, 0);
    float l2 = read_luma(param_2, HOOKED_raw, HOOKED_rawSmplr);
    int2 param_3 = sp + int2(2, 0);
    float r2 = read_luma(param_3, HOOKED_raw, HOOKED_rawSmplr);
    float sum = (((v.c * 0.180000007152557373046875) + ((((v.n + v.s) + v.w) + v.e) * 0.100000001490116119384765625)) + ((((h2 + v2) + l2) + r2) * 0.070000000298023223876953125)) + ((((v.nw + v.ne) + v.sw) + v.se) * 0.02999999932944774627685546875);
    return sum * 1.02040803432464599609375;
}

static inline __attribute__((always_inline))
float content_class(thread const Nbhd3& v, thread const float& noise_det, thread const float& edge_coherence)
{
    float local_range = v.hi - v.lo;
    float flatness = 1.0 - smoothstep(0.0, 0.119999997317790985107421875, local_range);
    float clean_noise = 1.0 - noise_det;
    float anim_score = ((flatness * 0.4000000059604644775390625) + (clean_noise * 0.3499999940395355224609375)) + (edge_coherence * 0.25);
    return fast::clamp(anim_score, 0.0, 1.0);
}

static inline __attribute__((always_inline))
float algo_hybrid(thread const int2& sp, thread const float& orig_l, thread const Nbhd3& v, thread const Params& p, thread const float& strength, thread const float& gf, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, constant PhotonUniforms& ubo)
{
    Nbhd3 param = v;
    float fine_b = blur_fine(param);
    float hp_fine = orig_l - fine_b;
    float hp_medium = 0.0;
    if ((isunordered(ubo.values[4].y, 0.0) || ubo.values[4].y != 0.0))
    {
        int2 param_1 = sp;
        Nbhd3 param_2 = v;
        float medium_b = blur_medium(param_1, param_2, HOOKED_raw, HOOKED_rawSmplr);
        hp_medium = orig_l - medium_b;
    }
    float hp_coarse = 0.0;
    if ((isunordered(ubo.values[4].z, 0.0) || ubo.values[4].z != 0.0))
    {
        int2 param_3 = sp;
        float param_4 = v.c;
        float coarse_b = blur_coarse(param_3, param_4, HOOKED_raw, HOOKED_rawSmplr);
        hp_coarse = orig_l - coarse_b;
    }
    float w_fine = (1.0 - p.fine_mix) * (1.0 - (0.5 * p.fine_mix));
    float w_coarse = p.fine_mix * (1.0 - (0.5 * (1.0 - p.fine_mix)));
    float w_medium = fast::max(0.0, (1.0 - w_fine) - w_coarse);
    float highpass = (((hp_fine * w_fine) * ubo.values[2].z) + ((hp_medium * w_medium) * ubo.values[2].w)) + ((hp_coarse * w_coarse) * ubo.values[3].x);
    int rp = res_profile(HOOKED_raw, HOOKED_rawSmplr);
    float _1007;
    if (rp == 0)
    {
        _1007 = 0.00999999977648258209228515625;
    }
    else
    {
        _1007 = (rp == 1) ? 0.007000000216066837310791015625 : 0.0040000001899898052215576171875;
    }
    float coring_base = _1007;
    float local_range = v.hi - v.lo;
    float coring_floor = mix(coring_base, coring_base * 2.5, p._noise);
    coring_floor *= (1.0 + (1.5 * p.block));
    Nbhd3 param_5 = v;
    float noise_det = rcas_noise(param_5);
    Nbhd3 param_6 = v;
    float2 ec_for_content = edge_struct(param_6);
    float anim_score = 0.5;
    if (ubo.values[4].x == 1.0)
    {
        Nbhd3 param_7 = v;
        float param_8 = noise_det;
        float param_9 = ec_for_content.y;
        anim_score = content_class(param_7, param_8, param_9);
        coring_floor *= mix(1.14999997615814208984375, 0.699999988079071044921875, anim_score);
    }
    float coring_w = smoothstep(coring_floor, coring_floor * 3.5, local_range);
    highpass *= coring_w;
    float rcas_noise_gate = 1.0 - noise_det;
    Nbhd3 param_10 = v;
    float learned_conf = learned_edge_confidence(param_10);
    rcas_noise_gate = mix(rcas_noise_gate, fast::max(rcas_noise_gate, learned_conf * 0.85000002384185791015625), ubo.values[4].x);
    float push = strength * highpass;
    float param_11 = push;
    float param_12 = orig_l;
    Nbhd3 param_13 = v;
    float param_14 = strength;
    float sharp_luma = orig_l + (clip_aware_push(param_11, param_12, param_13, param_14) * rcas_noise_gate);
    return sharp_luma;
}

static inline __attribute__((always_inline))
float4 hook(thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, constant PhotonUniforms& ubo, thread float2& uv)
{
    float4 orig = HOOKED_raw.sample(HOOKED_rawSmplr, uv);
    float3 param = orig.xyz;
    float orig_l = get_luma(param);
    int2 sp = int2((uv * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height()))) - float2(0.5));
    Params p = unpack_params(ubo);
    int2 param_1 = sp;
    Nbhd3 v = sample_nbhd3(param_1, HOOKED_raw, HOOKED_rawSmplr);
    if (!p.has_feed)
    {
        Nbhd3 param_2 = v;
        float param_3;
        float param_4;
        float param_5;
        estimate_fallback(param_2, param_3, param_4, param_5);
        float fb_peak = param_3;
        float fb_contrast = param_4;
        float fb_noise = param_5;
        p.peak = fb_peak;
        p.contrast = fb_contrast;
        p._noise = fb_noise;
    }
    float gf = fast::max(ubo.values[1].z, 0.00999999977648258209228515625);
    float hg = fast::clamp(ubo.values[2].x, 0.0, 1.0);
    int algo = int(ubo.values[3].y);
    int rp = res_profile(HOOKED_raw, HOOKED_rawSmplr);
    float strength = p.amount * gf;
    float _1610;
    if (rp == 0)
    {
        _1610 = 1.14999997615814208984375;
    }
    else
    {
        _1610 = (rp == 1) ? 1.10000002384185791015625 : 1.0499999523162841796875;
    }
    float res_headroom = _1610;
    strength *= res_headroom;
    float _1626;
    if (rp == 0)
    {
        _1626 = 0.5;
    }
    else
    {
        _1626 = (rp == 1) ? 0.449999988079071044921875 : 0.300000011920928955078125;
    }
    float contrast_scale = _1626;
    strength *= (0.64999997615814208984375 + (contrast_scale * p.contrast));
    float motion_damp = mix(0.449999988079071044921875, 0.25, hg);
    strength *= (1.0 - (motion_damp * p.motion));
    float _1656;
    if (rp == 0)
    {
        _1656 = 0.3499999940395355224609375;
    }
    else
    {
        _1656 = (rp == 1) ? 0.2800000011920928955078125 : 0.20000000298023223876953125;
    }
    float noise_ceil = _1656;
    float noise_gate = 1.0 - smoothstep(0.02999999932944774627685546875, noise_ceil, p._noise);
    strength *= mix(0.5, 1.0, noise_gate);
    strength *= mix(1.0, 0.449999988079071044921875, p.block);
    strength *= mix(1.0, 0.449999988079071044921875, p.ring);
    strength = fast::clamp(strength, 0.0, 128.0);
    float sharp_luma;
    if (algo == 1)
    {
        int2 param_6 = sp;
        float param_7 = orig_l;
        Nbhd3 param_8 = v;
        Params param_9 = p;
        float param_10 = strength;
        sharp_luma = algo_perceptual(param_6, param_7, param_8, param_9, param_10);
    }
    else
    {
        if (algo == 2)
        {
            int2 param_11 = sp;
            float param_12 = orig_l;
            Nbhd3 param_13 = v;
            Params param_14 = p;
            float param_15 = strength;
            sharp_luma = algo_structural(param_11, param_12, param_13, param_14, param_15, ubo);
        }
        else
        {
            if (algo == 3)
            {
                int2 param_16 = sp;
                float param_17 = orig_l;
                Nbhd3 param_18 = v;
                Params param_19 = p;
                float param_20 = strength;
                sharp_luma = algo_conservative(param_16, param_17, param_18, param_19, param_20);
            }
            else
            {
                if (algo == 4)
                {
                    int2 param_21 = sp;
                    float param_22 = orig_l;
                    Nbhd3 param_23 = v;
                    Params param_24 = p;
                    float param_25 = strength;
                    float param_26 = gf;
                    sharp_luma = algo_aggressive(param_21, param_22, param_23, param_24, param_25, param_26, HOOKED_raw, HOOKED_rawSmplr);
                }
                else
                {
                    int2 param_27 = sp;
                    float param_28 = orig_l;
                    Nbhd3 param_29 = v;
                    Params param_30 = p;
                    float param_31 = strength;
                    float param_32 = gf;
                    sharp_luma = algo_hybrid(param_27, param_28, param_29, param_30, param_31, param_32, HOOKED_raw, HOOKED_rawSmplr, ubo);
                }
            }
        }
    }
    float local_range = v.hi - v.lo;
    float flat_factor = 1.0 - smoothstep(0.0, 0.100000001490116119384765625, local_range);
    float temporal_base = p.alpha * (1.0 - (0.3499999940395355224609375 * p.motion));
    float temporal = mix(temporal_base, fast::min(1.0, (temporal_base * 1.14999997615814208984375) + 0.100000001490116119384765625), 1.0 - flat_factor);
    sharp_luma = mix(orig_l, sharp_luma, temporal);
    sharp_luma = fast::clamp(sharp_luma, 0.0, 1.0);
    float _1803;
    if (local_range > 9.9999997473787516355514526367188e-06)
    {
        _1803 = fast::clamp((abs(orig_l - mix(v.lo, v.hi, 0.5)) / ((local_range * 0.5) + 9.9999997473787516355514526367188e-06)) - 0.5, 0.0, 1.0);
    }
    else
    {
        _1803 = 0.0;
    }
    float edge_proximity = _1803;
    float halo_suppress = mix(1.0, 1.0 - (edge_proximity * 0.4000000059604644775390625), hg);
    float delta = sharp_luma - orig_l;
    sharp_luma = orig_l + (delta * halo_suppress);
    float _1840;
    if (rp == 0)
    {
        _1840 = 0.2800000011920928955078125;
    }
    else
    {
        _1840 = (rp == 1) ? 0.20000000298023223876953125 : 0.14000000059604644775390625;
    }
    float halo_base = _1840;
    float halo_clamp = mix(halo_base * 1.39999997615814208984375, halo_base * 0.60000002384185791015625, hg);
    float safe_luma = fast::max(orig_l, 0.001000000047497451305389404296875);
    float ratio = sharp_luma / safe_luma;
    ratio = fast::clamp(ratio, 1.0 - halo_clamp, 1.0 + halo_clamp);
    float3 color = fast::clamp(orig.xyz * ratio, float3(0.0), float3(1.0));
    return float4(color, orig.w);
}

fragment main0_out main0(main0_in in [[stage_in]], constant PhotonUniforms& ubo [[buffer(2)]], texture2d<float> HOOKED_raw [[texture(0)]], sampler HOOKED_rawSmplr [[sampler(0)]])
{
    main0_out out = {};
    out.result = hook(HOOKED_raw, HOOKED_rawSmplr, ubo, in.uv);
    return out;
}


"""#
    private static let grainSources: [String] = [
#"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct PhotonUniforms
{
    float4 values[32];
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float4 hook(thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread float2& uv)
{
    bool black = true;
    for (int i = 0; i < int(float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).x); i++)
    {
        float3 c = HOOKED_raw.read(uint2(int2(i, int(uv.y * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y))), 0).xyz;
        if (any((isunordered(c, float3(0.0)) || c != float3(0.0))))
        {
            black = false;
            break;
        }
    }
    return float4(float(black));
}

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> HOOKED_raw [[texture(0)]], sampler HOOKED_rawSmplr [[sampler(0)]])
{
    main0_out out = {};
    out.result = hook(HOOKED_raw, HOOKED_rawSmplr, in.uv);
    return out;
}


"""#,
#"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct PhotonUniforms
{
    float4 values[32];
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float4 hook(thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread float2& uv)
{
    bool black = true;
    for (int i = 0; i < int(float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y); i++)
    {
        float3 c = HOOKED_raw.read(uint2(int2(int(uv.x * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).x), i)), 0).xyz;
        if (any((isunordered(c, float3(0.0)) || c != float3(0.0))))
        {
            black = false;
            break;
        }
    }
    return float4(float(black));
}

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> HOOKED_raw [[texture(0)]], sampler HOOKED_rawSmplr [[sampler(0)]])
{
    main0_out out = {};
    out.result = hook(HOOKED_raw, HOOKED_rawSmplr, in.uv);
    return out;
}


"""#,
#"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct PhotonUniforms
{
    float4 values[32];
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float4 hook(thread float2& uv, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread texture2d<float> ug1_row_black_raw, thread const sampler ug1_row_black_rawSmplr)
{
    int at = int(uv.y * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y);
    int n = int(float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y);
    bool lo = true;
    bool hi = true;
    for (int i = 0; i <= at; i++)
    {
        if (ug1_row_black_raw.read(uint2(int2(0, i)), 0).x < 0.5)
        {
            lo = false;
            break;
        }
    }
    for (int i_1 = at; i_1 < n; i_1++)
    {
        if (ug1_row_black_raw.read(uint2(int2(0, i_1)), 0).x < 0.5)
        {
            hi = false;
            break;
        }
    }
    return float4(float(lo || hi));
}

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> HOOKED_raw [[texture(0)]], texture2d<float> ug1_row_black_raw [[texture(1)]], sampler HOOKED_rawSmplr [[sampler(0)]], sampler ug1_row_black_rawSmplr [[sampler(1)]])
{
    main0_out out = {};
    out.result = hook(in.uv, HOOKED_raw, HOOKED_rawSmplr, ug1_row_black_raw, ug1_row_black_rawSmplr);
    return out;
}


"""#,
#"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct PhotonUniforms
{
    float4 values[32];
};

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float4 hook(thread float2& uv, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread texture2d<float> ug1_col_black_raw, thread const sampler ug1_col_black_rawSmplr)
{
    int at = int(uv.x * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).x);
    int n = int(float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).x);
    bool lo = true;
    bool hi = true;
    for (int i = 0; i <= at; i++)
    {
        if (ug1_col_black_raw.read(uint2(int2(i, 0)), 0).x < 0.5)
        {
            lo = false;
            break;
        }
    }
    for (int i_1 = at; i_1 < n; i_1++)
    {
        if (ug1_col_black_raw.read(uint2(int2(i_1, 0)), 0).x < 0.5)
        {
            hi = false;
            break;
        }
    }
    return float4(float(lo || hi));
}

fragment main0_out main0(main0_in in [[stage_in]], texture2d<float> HOOKED_raw [[texture(0)]], texture2d<float> ug1_col_black_raw [[texture(1)]], sampler HOOKED_rawSmplr [[sampler(0)]], sampler ug1_col_black_rawSmplr [[sampler(1)]])
{
    main0_out out = {};
    out.result = hook(in.uv, HOOKED_raw, HOOKED_rawSmplr, ug1_col_black_raw, ug1_col_black_rawSmplr);
    return out;
}


"""#,
#"""
#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];

    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }

    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }

    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }

    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

struct PhotonUniforms
{
    float4 values[32];
};

constant spvUnsafeArray<float3, 6> _1133 = spvUnsafeArray<float3, 6>({ float3(1.0, 0.87999999523162841796875, 1.10000002384185791015625), float3(0.89999997615814208984375, 0.89999997615814208984375, 0.949999988079071044921875), float3(1.0499999523162841796875, 0.85000002384185791015625, 1.14999997615814208984375), float3(1.10000002384185791015625, 0.800000011920928955078125, 1.2000000476837158203125), float3(1.0, 0.949999988079071044921875, 1.0), float3(0.949999988079071044921875, 0.920000016689300537109375, 1.0499999523162841796875) });

struct main0_out
{
    float4 result [[color(0)]];
};

struct main0_in
{
    float2 uv [[user(locn0)]];
};

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

static inline __attribute__((always_inline))
float mod289(thread const float& x)
{
    return x - (floor(x / 289.0) * 289.0);
}

static inline __attribute__((always_inline))
float permute(thread const float& x)
{
    float param = x;
    float xr = mod289(param);
    float param_1 = ((34.0 * xr) + 1.0) * xr;
    return mod289(param_1);
}

static inline __attribute__((always_inline))
float rand01(thread const float& x)
{
    return fract(x / 41.0);
}

static inline __attribute__((always_inline))
float2 dihedral_transform(thread float2& p, thread int& sel)
{
    if (sel >= 4)
    {
        p.x = mod(64.0 - p.x, 64.0);
        sel -= 4;
    }
    if (sel == 1)
    {
        return float2(p.y, mod(64.0 - p.x, 64.0));
    }
    if (sel == 2)
    {
        return float2(mod(64.0 - p.x, 64.0), mod(64.0 - p.y, 64.0));
    }
    if (sel == 3)
    {
        return float2(mod(64.0 - p.y, 64.0), p.x);
    }
    return p;
}

static inline __attribute__((always_inline))
float sample_bluenoise(thread const float2& pos_px, thread const float& cell_size, thread const float& salt, thread const float& frame_bucket, thread const float& time_seed, thread texture2d<float> TEX_BLUENOISE_raw, thread const sampler TEX_BLUENOISE_rawSmplr)
{
    float2 cell_pos = pos_px / float2(fast::max(cell_size, 0.00999999977648258209228515625));
    float2 tile_id = floor(cell_pos / float2(64.0));
    float2 local_p = mod(cell_pos, float2(64.0));
    float param = (((tile_id.x * 41.0) + (tile_id.y * 113.0)) + (salt * 7.0)) + (frame_bucket * time_seed);
    float h = permute(param);
    float param_1 = h;
    int sel = int(floor(rand01(param_1) * 8.0));
    float param_2 = h + 5.0;
    float oh = permute(param_2);
    float param_3 = oh;
    float ox = floor(rand01(param_3) * 64.0);
    float param_4 = oh + 1.0;
    float param_5 = permute(param_4);
    float oy = floor(rand01(param_5) * 64.0);
    float2 lp = mod(local_p + float2(ox, oy), float2(64.0));
    float2 param_6 = lp;
    int param_7 = sel;
    float2 _322 = dihedral_transform(param_6, param_7);
    float2 tp = _322;
    float2 d = float2(0.0078125, 0.0);
    float raw = ((TEX_BLUENOISE_raw.sample(TEX_BLUENOISE_rawSmplr, (((tp + float2(0.5)) / float2(64.0)) + d.xx)).x + TEX_BLUENOISE_raw.sample(TEX_BLUENOISE_rawSmplr, (((tp + float2(0.5)) / float2(64.0)) - d.xx)).x) * 0.25) + (TEX_BLUENOISE_raw.sample(TEX_BLUENOISE_rawSmplr, ((tp + float2(0.5)) / float2(64.0))).x * 0.5);
    float dither = (raw * 2.0) - 1.0;
    float2 cell_xy = floor(cell_pos);
    float param_8 = (((cell_xy.x * 53.0) + (cell_xy.y * 97.0)) + (salt * 13.0)) + (frame_bucket * time_seed);
    float amp_h = permute(param_8);
    float param_9 = amp_h;
    float amp = rand01(param_9);
    return dither * amp;
}

static inline __attribute__((always_inline))
float soft_grain_layer(thread const float2& pos_px, thread const float& cell_size, thread const float& softness, thread const float& salt, thread const float& frame_bucket, thread const float& time_seed, thread texture2d<float> TEX_BLUENOISE_raw, thread const sampler TEX_BLUENOISE_rawSmplr)
{
    float2 param = pos_px;
    float param_1 = cell_size;
    float param_2 = salt;
    float param_3 = frame_bucket;
    float param_4 = time_seed;
    float hard = sample_bluenoise(param, param_1, param_2, param_3, param_4, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float2 soft_offset = float2(cell_size, cell_size * 0.5) * 0.75;
    float2 param_5 = pos_px + soft_offset;
    float param_6 = cell_size;
    float param_7 = salt;
    float param_8 = frame_bucket;
    float param_9 = time_seed;
    float soft = sample_bluenoise(param_5, param_6, param_7, param_8, param_9, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    return mix(hard, soft, fast::clamp(softness, 0.0, 1.0));
}

static inline __attribute__((always_inline))
int res_profile_grain(constant PhotonUniforms& ubo)
{
    float h = ubo.values[31].y;
    if (h < 700.0)
    {
        return 0;
    }
    if (h < 1100.0)
    {
        return 1;
    }
    return 2;
}

static inline __attribute__((always_inline))
void res_scale_grain(thread float& scale_mult, thread float& density_mult, constant PhotonUniforms& ubo)
{
    if (int(ubo.values[6].z) == 0)
    {
        scale_mult = 1.0;
        density_mult = 1.0;
        return;
    }
    int rp = res_profile_grain(ubo);
    if (rp == 0)
    {
        scale_mult = 2.0;
        density_mult = 0.699999988079071044921875;
    }
    else
    {
        if (rp == 1)
        {
            scale_mult = 1.0;
            density_mult = 1.0;
        }
        else
        {
            scale_mult = 0.5;
            density_mult = 0.85000002384185791015625;
        }
    }
}

static inline __attribute__((always_inline))
float window_compensation(thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr)
{
    float h = fast::max(float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).y, 1.0);
    return fast::clamp(sqrt(1600.0 / h), 0.4000000059604644775390625, 0.800000011920928955078125);
}

static inline __attribute__((always_inline))
float luma_adapt(thread const float& luma)
{
    float deviation = (luma - 0.4000000059604644775390625) / 0.449999988079071044921875;
    float midtone = exp((-deviation) * deviation);
    float shadow_floor = 0.119999997317790985107421875 * (1.0 - smoothstep(0.0, 0.300000011920928955078125, luma));
    float highlight_floor = 0.20000000298023223876953125 * smoothstep(0.5, 0.85000002384185791015625, luma);
    return fast::clamp((midtone + shadow_floor) + highlight_floor, 0.0, 1.0499999523162841796875);
}

static inline __attribute__((always_inline))
float zone_sensitivity(thread const float& luma, constant PhotonUniforms& ubo)
{
    float shadow_w = 1.0 - smoothstep(0.0, 0.1500000059604644775390625, luma);
    float highlight_w = smoothstep(0.949999988079071044921875, 1.0, luma);
    float midtone_w = fast::clamp((1.0 - shadow_w) - highlight_w, 0.0, 1.0);
    return ((shadow_w * ubo.values[5].z) + (midtone_w * ubo.values[5].w)) + (highlight_w * ubo.values[6].x);
}

static inline __attribute__((always_inline))
float hdr_black_gate(thread const float& luma, thread const float& is_hdr)
{
    float gate = smoothstep(0.0, 0.0599999986588954925537109375, luma);
    gate = pow(gate, 2.2000000476837158203125);
    return mix(1.0, gate, is_hdr);
}

static inline __attribute__((always_inline))
float local_texture_variance(thread const float& center_luma, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread float2& uv)
{
    float2 d = float2(1.0) / float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height()));
    float3 lw = float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625);
    float s = 0.0;
    float s2 = 0.0;
    float l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(-d.x, -d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(0.0, -d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(d.x, -d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(-d.x, 0.0))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = center_luma;
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(d.x, 0.0))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(-d.x, d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(0.0, d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    l = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(d.x, d.y))).xyz, lw);
    s += l;
    s2 += (l * l);
    s /= 9.0;
    s2 /= 9.0;
    return fast::max(0.0, s2 - (s * s));
}

static inline __attribute__((always_inline))
float3 scene_hue_modulation(thread const float& hue_deg, constant PhotonUniforms& ubo)
{
    float d_r = fast::min(abs(hue_deg - 0.0), 360.0 - abs(hue_deg - 0.0));
    float d_g = fast::min(abs(hue_deg - 120.0), 360.0 - abs(hue_deg - 120.0));
    float d_b = fast::min(abs(hue_deg - 240.0), 360.0 - abs(hue_deg - 240.0));
    float w_r = 1.0 - smoothstep(0.0, 60.0, d_r);
    float w_g = 1.0 - smoothstep(0.0, 60.0, d_g);
    float w_b = 1.0 - smoothstep(0.0, 60.0, d_b);
    return float3(1.0 + (ubo.values[2].x * w_r), 1.0 + (ubo.values[2].x * w_g), 1.0 + (ubo.values[2].x * w_b));
}

static inline __attribute__((always_inline))
float grain_layers(thread const float2& pos_px, thread const float& eff_grain_size, thread const float& channel_seed, thread const float& frame_bucket, constant PhotonUniforms& ubo, thread texture2d<float> TEX_BLUENOISE_raw, thread const sampler TEX_BLUENOISE_rawSmplr)
{
    float cell_fine = eff_grain_size * ubo.values[4].w;
    float cell_crystal = eff_grain_size;
    float cell_cloud = eff_grain_size * ubo.values[5].x;
    float salt_fine = 3.0 + channel_seed;
    float salt_crystal = 11.0 + channel_seed;
    float salt_cloud = 29.0 + channel_seed;
    float tseed_fine = 3.3027756214141845703125 + channel_seed;
    float tseed_crystal = 19.61803436279296875 + channel_seed;
    float tseed_cloud = 7.414213657379150390625 + channel_seed;
    float2 param = pos_px;
    float param_1 = cell_fine;
    float param_2 = ubo.values[3].x;
    float param_3 = salt_fine;
    float param_4 = frame_bucket;
    float param_5 = tseed_fine;
    float fine = soft_grain_layer(param, param_1, param_2, param_3, param_4, param_5, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float2 param_6 = pos_px;
    float param_7 = cell_crystal;
    float param_8 = ubo.values[3].x;
    float param_9 = salt_crystal;
    float param_10 = frame_bucket;
    float param_11 = tseed_crystal;
    float crystal = soft_grain_layer(param_6, param_7, param_8, param_9, param_10, param_11, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float2 param_12 = pos_px;
    float param_13 = cell_cloud;
    float param_14 = ubo.values[3].x;
    float param_15 = salt_cloud;
    float param_16 = frame_bucket;
    float param_17 = tseed_cloud;
    float cloud = soft_grain_layer(param_12, param_13, param_14, param_15, param_16, param_17, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float w_fn = fast::max(ubo.values[3].w, 0.0);
    float w_cr = fast::max(ubo.values[4].x, 0.0);
    float w_cl = fast::max(ubo.values[4].y, 0.0);
    float wsum = fast::max((w_fn + w_cr) + w_cl, 0.001000000047497451305389404296875);
    float raw = (((fine * w_fn) + (crystal * w_cr)) + (cloud * w_cl)) / wsum;
    return raw * ubo.values[3].z;
}

static inline __attribute__((always_inline))
float4 hook(constant PhotonUniforms& ubo, thread texture2d<float> TEX_BLUENOISE_raw, thread const sampler TEX_BLUENOISE_rawSmplr, thread texture2d<float> HOOKED_raw, thread const sampler HOOKED_rawSmplr, thread float2& uv, thread texture2d<float> ug1_row_edge_raw, thread const sampler ug1_row_edge_rawSmplr, thread texture2d<float> ug1_col_edge_raw, thread const sampler ug1_col_edge_rawSmplr)
{
    float4 color = HOOKED_raw.sample(HOOKED_rawSmplr, uv);
    float frame_bucket = ubo.values[1].y;
    if (ubo.values[7].x == 1.0)
    {
        float2 dbg_pos_px = uv * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height()));
        float2 param = dbg_pos_px;
        float param_1 = ubo.values[2].w;
        float param_2 = ubo.values[3].x;
        float param_3 = 11.0;
        float param_4 = frame_bucket;
        float param_5 = 19.61803436279296875;
        float dbg_raw = soft_grain_layer(param, param_1, param_2, param_3, param_4, param_5, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr) * 50.0;
        return float4(color.xyz + float3(dbg_raw), color.w);
    }
    float peak = fast::clamp(ubo.values[0].x, 0.0, 1.0);
    float _noise = fast::clamp(ubo.values[0].z, 0.0, 1.0);
    float motion = fast::clamp(ubo.values[0].w, 0.0, 1.0);
    float amount = fast::clamp(ubo.values[1].x, 0.0, 10.0);
    float hdr_flag = ubo.values[1].z;
    float param_6;
    float param_7;
    res_scale_grain(param_6, param_7, ubo);
    float scale_mult = param_6;
    float density_mult = param_7;
    float eff_size = ((ubo.values[2].w * scale_mult) * window_compensation(HOOKED_raw, HOOKED_rawSmplr)) * mix(1.0, 0.75, hdr_flag);
    if (ubo.values[2].z > 0.0)
    {
        eff_size = (ubo.values[2].w * ubo.values[2].z) * mix(1.0, 0.75, hdr_flag);
    }
    float2 pos_px = uv * float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height()));
    float luma = dot(color.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float param_8 = luma;
    float param_9 = luma;
    float luma_gain = luma_adapt(param_8) * zone_sensitivity(param_9, ubo);
    bool _1022 = all(color.xyz == float3(0.0));
    bool _1046;
    if (_1022)
    {
        float4 _1031 = ug1_row_edge_raw.sample(ug1_row_edge_rawSmplr, float2(0.5, uv.y));
        bool _1033 = _1031.x > 0.5;
        bool _1045;
        if (!_1033)
        {
            _1045 = ug1_col_edge_raw.sample(ug1_col_edge_rawSmplr, float2(uv.x, 0.5)).x > 0.5;
        }
        else
        {
            _1045 = _1033;
        }
        _1046 = _1045;
    }
    else
    {
        _1046 = _1022;
    }
    if (_1046)
    {
        luma_gain = 0.0;
    }
    float adapt = amount;
    adapt *= (1.0 + (0.800000011920928955078125 * (1.0 - peak)));
    adapt *= mix(0.800000011920928955078125, 1.2000000476837158203125, motion);
    float is_hdr = step(1.0, fast::max(fast::max(color.x, color.y), color.z));
    adapt *= mix(1.0, 0.550000011920928955078125, is_hdr);
    float param_10 = luma;
    float param_11 = is_hdr;
    luma_gain *= hdr_black_gate(param_10, param_11);
    float param_12 = luma;
    float tex_var = local_texture_variance(param_12, HOOKED_raw, HOOKED_rawSmplr, uv);
    float tex_density = 1.0 - (smoothstep(0.0, 0.008000000379979610443115234375, tex_var) * 0.3499999940395355224609375);
    float luma_n = dot(HOOKED_raw.sample(HOOKED_rawSmplr, (uv + float2(2.0 / float2(int2(HOOKED_raw.get_width(), HOOKED_raw.get_height())).x, 0.0))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float px_motion = smoothstep(0.0199999995529651641845703125, 0.100000001490116119384765625, abs(luma - luma_n)) * motion;
    float param_13 = ubo.values[1].w;
    float3 sp = _1133[int(ubo.values[6].y)] * scene_hue_modulation(param_13, ubo);
    float _1150;
    if (ubo.values[2].y > 0.0)
    {
        _1150 = ubo.values[2].y;
    }
    else
    {
        _1150 = density_mult;
    }
    float render_density = _1150;
    float amp = ((luma_gain * (ubo.values[4].z / 10.0)) * adapt) * render_density;
    amp *= tex_density;
    amp *= (1.0 + (0.119999997317790985107421875 * px_motion));
    float2 param_14 = pos_px;
    float param_15 = eff_size;
    float param_16 = 0.0;
    float param_17 = frame_bucket;
    float g_r_raw = grain_layers(param_14, param_15, param_16, param_17, ubo, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float2 param_18 = pos_px;
    float param_19 = eff_size;
    float param_20 = 17.0;
    float param_21 = frame_bucket;
    float g_g_raw = grain_layers(param_18, param_19, param_20, param_21, ubo, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float2 param_22 = pos_px;
    float param_23 = eff_size;
    float param_24 = 37.0;
    float param_25 = frame_bucket;
    float g_b_raw = grain_layers(param_22, param_23, param_24, param_25, ubo, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr);
    float g_luma = ((g_r_raw * 0.2989999949932098388671875) + (g_g_raw * 0.58700001239776611328125)) + (g_b_raw * 0.114000000059604644775390625);
    float skew = (-ubo.values[5].y) * (luma - 0.5);
    float g_r;
    float g_g;
    float g_b;
    if ((isunordered(ubo.values[6].w, 0.0) || ubo.values[6].w != 0.0))
    {
        float g_mono_raw = g_luma + skew;
        float g_mono = sign(g_mono_raw) * pow(abs(g_mono_raw), 0.85000002384185791015625);
        g_r = g_mono;
        g_g = g_mono;
        g_b = g_mono;
    }
    else
    {
        g_r = mix(g_r_raw, g_luma, ubo.values[3].y) + skew;
        g_g = mix(g_g_raw, g_luma, ubo.values[3].y) + skew;
        g_b = mix(g_b_raw, g_luma, ubo.values[3].y) + skew;
        float chroma_blend = fast::clamp(ubo.values[3].y * 4.0, 0.0, 1.0);
        g_r *= mix(1.0, sp.x, chroma_blend);
        g_g *= mix(1.0, sp.y, chroma_blend);
        g_b *= mix(1.0, sp.z, chroma_blend);
    }
    float3 cg = float3(g_r, g_g, g_b) * amp;
    return float4(color.xyz + cg, color.w);
}

fragment main0_out main0(main0_in in [[stage_in]], constant PhotonUniforms& ubo [[buffer(2)]], texture2d<float> TEX_BLUENOISE_raw [[texture(0)]], texture2d<float> HOOKED_raw [[texture(1)]], texture2d<float> ug1_row_edge_raw [[texture(2)]], texture2d<float> ug1_col_edge_raw [[texture(3)]], sampler TEX_BLUENOISE_rawSmplr [[sampler(0)]], sampler HOOKED_rawSmplr [[sampler(1)]], sampler ug1_row_edge_rawSmplr [[sampler(2)]], sampler ug1_col_edge_rawSmplr [[sampler(3)]])
{
    main0_out out = {};
    out.result = hook(ubo, TEX_BLUENOISE_raw, TEX_BLUENOISE_rawSmplr, HOOKED_raw, HOOKED_rawSmplr, in.uv, ug1_row_edge_raw, ug1_row_edge_rawSmplr, ug1_col_edge_raw, ug1_col_edge_rawSmplr);
    return out;
}


"""#,
]
}
#endif
