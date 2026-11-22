import Foundation

// P22 (arch-195b; queue item 198a-5b): the typed Swift representation of the full live
// look-parameter universe - one parameter block, one uniform-buffer upload per frame,
// value changes without shader recompile. Measured against the live declarations in
// goreda/instinct c54467887 archive/gor/Resources/vendor/mpv/scripts (68 vr180 base
// declarations + 5 pack-injected + photon chrome3/grain29/negativ3/sharp19 = 127).
// Nine vrBase defaults are Lua-computed in the source; their measured current values
// ride here with the source expression named in computedDefault. This file is a typed
// parameter model: no Metal upload, no pixel claim, Mac NOT_RUN.

public enum LookParameterFamily: String, CaseIterable, Sendable {
    case vrBase, vrPack, photonChrome, photonGrain, photonNegativ, photonSharp
    /// Measured live declaration counts (count_live.py convention: distinct names per file).
    public var expectedCount: Int {
        switch self {
        case .vrBase: return 68
        case .vrPack: return 5
        case .photonChrome: return 3
        case .photonGrain: return 29
        case .photonNegativ: return 3
        case .photonSharp: return 19
        }
    }
}

/// How a value may change. floatUniform/intUniform upload per frame; a compileTimeDefine
/// is baked into the shader source: changing it needs a precompiled variant (PLAN P22
/// fallback), never a silent recompile.
public enum LookParameterKind: Equatable, Sendable {
    case floatUniform(dynamic: Bool)
    case intUniform
    case compileTimeDefine
}

public struct LookParameter: Equatable, Sendable {
    public let name: String
    public let family: LookParameterFamily
    public let kind: LookParameterKind
    /// Exact declaration text from the source (digest material).
    public let defaultText: String
    /// Source expression for Lua-computed defaults; nil for literal declarations.
    public let computedDefault: String?
    /// Stable lane offset in the block, 0..126, canonical family then declaration order.
    public let offset: Int
    /// P21 stage that consumes this parameter (DR-0015 routing).
    public let stage: RenderGraphStage
    public var defaultValue: Double { Double(defaultText)! }
}

public enum LookParameterTable {
    public static let count = 127
    public static let all: [LookParameter] = [
        LookParameter(name: "vr_native_tb", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 0, stage: .stereoProjection),
        LookParameter(name: "vr_cross_eye", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 1, stage: .stereoProjection),
        LookParameter(name: "vr_calibration", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 2, stage: .stereoProjection),
        LookParameter(name: "vr_head_roll", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 3, stage: .stereoProjection),
        LookParameter(name: "vr_surface_w", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 4, stage: .output),
        LookParameter(name: "vr_surface_h", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 5, stage: .output),
        LookParameter(name: "vr_surface_x", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 6, stage: .output),
        LookParameter(name: "vr_surface_y", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 7, stage: .output),
        LookParameter(name: "vr_source_layout", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 8, stage: .stereoProjection),
        LookParameter(name: "vr_plain", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 9, stage: .stereoProjection),
        LookParameter(name: "vr_plain_aspect", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 10, stage: .output),
        LookParameter(name: "vr_flat_sbs", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 11, stage: .stereoProjection),
        LookParameter(name: "vr_flat_mono", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 12, stage: .stereoProjection),
        LookParameter(name: "vr_d3_gain", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.02", computedDefault: nil, offset: 13, stage: .stereoProjection),
        LookParameter(name: "vr_eye_aspect", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 14, stage: .stereoProjection),
        LookParameter(name: "vr_frame_fit", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 15, stage: .output),
        LookParameter(name: "vr_frame_spacing", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 16, stage: .output),
        LookParameter(name: "vr_source_x", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 17, stage: .stereoProjection),
        LookParameter(name: "vr_source_y", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 18, stage: .stereoProjection),
        LookParameter(name: "vr_source_w", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1", computedDefault: nil, offset: 19, stage: .stereoProjection),
        LookParameter(name: "vr_source_h", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1", computedDefault: nil, offset: 20, stage: .stereoProjection),
        LookParameter(name: "vr_crop_x", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 21, stage: .crop),
        LookParameter(name: "vr_crop_y", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 22, stage: .crop),
        LookParameter(name: "vr_aspect_override", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 23, stage: .output),
        LookParameter(name: "vr_manual_yaw", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 24, stage: .stereoProjection),
        LookParameter(name: "vr_manual_pitch", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 25, stage: .stereoProjection),
        LookParameter(name: "vr_manual_view", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 26, stage: .stereoProjection),
        LookParameter(name: "vr_yaw", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 27, stage: .stereoProjection),
        LookParameter(name: "vr_pitch", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 28, stage: .stereoProjection),
        LookParameter(name: "vr_fov", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.5707963", computedDefault: nil, offset: 29, stage: .stereoProjection),
        LookParameter(name: "vr_roll", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 30, stage: .stereoProjection),
        LookParameter(name: "blink_top_bottom", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 31, stage: .surround),
        LookParameter(name: "blink_lid_l", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 32, stage: .surround),
        LookParameter(name: "blink_lid_r", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 33, stage: .surround),
        LookParameter(name: "blink_reopen_l", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 34, stage: .surround),
        LookParameter(name: "blink_reopen_r", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0", computedDefault: nil, offset: 35, stage: .surround),
        LookParameter(name: "blink_close_ms", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "80", computedDefault: nil, offset: 36, stage: .surround),
        LookParameter(name: "blink_open_ms", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "180", computedDefault: nil, offset: 37, stage: .surround),
        LookParameter(name: "blink_failopen_ms", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "200", computedDefault: nil, offset: 38, stage: .surround),
        LookParameter(name: "blink_adapt_ms", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "250", computedDefault: nil, offset: 39, stage: .surround),
        LookParameter(name: "blink_upper", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.92", computedDefault: nil, offset: 40, stage: .surround),
        LookParameter(name: "blink_lower", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.08", computedDefault: nil, offset: 41, stage: .surround),
        LookParameter(name: "blink_arc", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.08", computedDefault: nil, offset: 42, stage: .surround),
        LookParameter(name: "blink_fringe", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.03", computedDefault: nil, offset: 43, stage: .surround),
        LookParameter(name: "blink_glow", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.05", computedDefault: nil, offset: 44, stage: .surround),
        LookParameter(name: "blink_glow_radius", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.08", computedDefault: nil, offset: 45, stage: .surround),
        LookParameter(name: "blink_slit_blur", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.004", computedDefault: nil, offset: 46, stage: .surround),
        LookParameter(name: "blink_contrast", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.4", computedDefault: nil, offset: 47, stage: .surround),
        LookParameter(name: "blink_lift", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.15", computedDefault: nil, offset: 48, stage: .surround),
        LookParameter(name: "blink_sbs_strength", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 49, stage: .surround),
        LookParameter(name: "blink_warm_r", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 50, stage: .surround),
        LookParameter(name: "blink_warm_g", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 51, stage: .surround),
        LookParameter(name: "blink_warm_b", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 52, stage: .surround),
        LookParameter(name: "vr_base_ipd", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 53, stage: .stereoProjection),
        LookParameter(name: "vr_ipd_nudge", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 54, stage: .stereoProjection),
        LookParameter(name: "vr_head_x", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 55, stage: .stereoProjection),
        LookParameter(name: "vr_head_y", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 56, stage: .stereoProjection),
        LookParameter(name: "vr_head_z", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 57, stage: .stereoProjection),
        LookParameter(name: "vr_swap_eyes", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: nil, offset: 58, stage: .stereoProjection),
        LookParameter(name: "vr_zoomcomp_baseline", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0075", computedDefault: "VR_ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC", offset: 59, stage: .output),
        LookParameter(name: "vr_gap_frac", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0125", computedDefault: "VR_PHYSICAL_GAP_FRAC (pure-look off)", offset: 60, stage: .surround),
        LookParameter(name: "vr_gap_blur_frac", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.5", computedDefault: "VR_EYE_GAP_BLUR_FRAC (pure-look off)", offset: 61, stage: .surround),
        LookParameter(name: "vr_vignette_ref_fov", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "90.0", computedDefault: "VR_PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG", offset: 62, stage: .surround),
        LookParameter(name: "vr_parallax_strength", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.4", computedDefault: "VR_PARALLAX_CORRECTION_STRENGTH", offset: 63, stage: .stereoProjection),
        LookParameter(name: "vr_parallax_disparity", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "-0.4", computedDefault: "VR_PARALLAX_CORRECTION_DISPARITY = strength * -1", offset: 64, stage: .stereoProjection),
        LookParameter(name: "vr_vignette_start", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.25", computedDefault: "VR_PERIPHERAL_VIGNETTE_START_FRAC", offset: 65, stage: .surround),
        LookParameter(name: "vr_vignette_darken", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: "VR_PERIPHERAL_VIGNETTE_DARKEN_STRENGTH (pure-look off)", offset: 66, stage: .surround),
        LookParameter(name: "vr_vignette_blur", family: .vrBase, kind: .floatUniform(dynamic: false), defaultText: "0.0015", computedDefault: "VR_PERIPHERAL_VIGNETTE_BLUR_STRENGTH = 0.006/4 (pure-look off)", offset: 67, stage: .surround),
        LookParameter(name: "vr_pack", family: .vrPack, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: "pack injection, VR180_LOOK_PACK_SOURCE", offset: 68, stage: .stereoProjection),
        LookParameter(name: "vr_pk_conv", family: .vrPack, kind: .floatUniform(dynamic: false), defaultText: "0.5", computedDefault: "pack injection, VR180_LOOK_PACK_SOURCE", offset: 69, stage: .stereoProjection),
        LookParameter(name: "vr_pk_zoom", family: .vrPack, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: "pack injection, VR180_LOOK_PACK_SOURCE", offset: 70, stage: .stereoProjection),
        LookParameter(name: "vr_pk_soft", family: .vrPack, kind: .floatUniform(dynamic: false), defaultText: "1.0", computedDefault: "pack injection, VR180_LOOK_PACK_SOURCE", offset: 71, stage: .stereoProjection),
        LookParameter(name: "vr_pk_surround_invert", family: .vrPack, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: "pack injection, VR180_LOOK_PACK_SOURCE", offset: 72, stage: .surround),
        LookParameter(name: "CH_FILTER_POS", family: .photonChrome, kind: .floatUniform(dynamic: true), defaultText: "1.0", computedDefault: nil, offset: 73, stage: .photon),
        LookParameter(name: "CH_FILTER_STRENGTH", family: .photonChrome, kind: .floatUniform(dynamic: true), defaultText: "0.75", computedDefault: nil, offset: 74, stage: .photon),
        LookParameter(name: "CH_CONTRAST_AMOUNT", family: .photonChrome, kind: .floatUniform(dynamic: true), defaultText: "0.055", computedDefault: nil, offset: 75, stage: .photon),
        LookParameter(name: "GR_FRAME_PEAK", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.5", computedDefault: nil, offset: 76, stage: .photon),
        LookParameter(name: "GR_SCENE_CONTRAST", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.35", computedDefault: nil, offset: 77, stage: .photon),
        LookParameter(name: "GR_NOISE_LEVEL", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.10", computedDefault: nil, offset: 78, stage: .photon),
        LookParameter(name: "GR_MOTION_LEVEL", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.20", computedDefault: nil, offset: 79, stage: .photon),
        LookParameter(name: "GR_AMOUNT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "1.0", computedDefault: nil, offset: 80, stage: .photon),
        LookParameter(name: "GR_ANIM_BUCKET", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 81, stage: .photon),
        LookParameter(name: "GR_IS_HDR", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 82, stage: .photon),
        LookParameter(name: "GR_SCENE_HUE", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 83, stage: .photon),
        LookParameter(name: "GR_HUE_MOD_STRENGTH", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 84, stage: .photon),
        LookParameter(name: "GR_RENDER_DENSITY", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 85, stage: .photon),
        LookParameter(name: "GR_SIZE_COEFFICIENT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 86, stage: .photon),
        LookParameter(name: "GRAIN_SIZE", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "1.2", computedDefault: nil, offset: 87, stage: .photon),
        LookParameter(name: "GRAIN_SOFTNESS", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "1.0", computedDefault: nil, offset: 88, stage: .photon),
        LookParameter(name: "CHROMA_SPLIT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.5", computedDefault: nil, offset: 89, stage: .photon),
        LookParameter(name: "DEVELOPMENT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.4", computedDefault: nil, offset: 90, stage: .photon),
        LookParameter(name: "FINE_WEIGHT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.25", computedDefault: nil, offset: 91, stage: .photon),
        LookParameter(name: "CRYSTAL_WEIGHT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.40", computedDefault: nil, offset: 92, stage: .photon),
        LookParameter(name: "CLOUD_WEIGHT", family: .photonGrain, kind: .floatUniform(dynamic: true), defaultText: "0.45", computedDefault: nil, offset: 93, stage: .photon),
        LookParameter(name: "BASE_STRENGTH", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "5.0", computedDefault: nil, offset: 94, stage: .photon),
        LookParameter(name: "FINE_SIZE_RATIO", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "0.5", computedDefault: nil, offset: 95, stage: .photon),
        LookParameter(name: "CLOUD_SIZE_RATIO", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "2.2", computedDefault: nil, offset: 96, stage: .photon),
        LookParameter(name: "SKEW_STRENGTH", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "0.0", computedDefault: nil, offset: 97, stage: .photon),
        LookParameter(name: "GR_SHADOW_SENSITIVITY", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "1.8", computedDefault: nil, offset: 98, stage: .photon),
        LookParameter(name: "GR_MIDTONE_SENSITIVITY", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "1.5", computedDefault: nil, offset: 99, stage: .photon),
        LookParameter(name: "GR_HIGHLIGHT_SENSITIVITY", family: .photonGrain, kind: .floatUniform(dynamic: false), defaultText: "2.7", computedDefault: nil, offset: 100, stage: .photon),
        LookParameter(name: "STOCK_PRESET", family: .photonGrain, kind: .intUniform, defaultText: "5", computedDefault: nil, offset: 101, stage: .photon),
        LookParameter(name: "RES_ADAPT", family: .photonGrain, kind: .intUniform, defaultText: "1", computedDefault: nil, offset: 102, stage: .photon),
        LookParameter(name: "GR_MONO_MODE", family: .photonGrain, kind: .compileTimeDefine, defaultText: "0", computedDefault: nil, offset: 103, stage: .photon),
        LookParameter(name: "GRAIN_DEBUG_VISUALIZE", family: .photonGrain, kind: .compileTimeDefine, defaultText: "0", computedDefault: nil, offset: 104, stage: .photon),
        LookParameter(name: "NG_GAMMA", family: .photonNegativ, kind: .floatUniform(dynamic: true), defaultText: "0.6", computedDefault: nil, offset: 105, stage: .photon),
        LookParameter(name: "NG_MASK_GAIN", family: .photonNegativ, kind: .floatUniform(dynamic: true), defaultText: "1.0", computedDefault: nil, offset: 106, stage: .photon),
        LookParameter(name: "NG_STOCK_POS", family: .photonNegativ, kind: .floatUniform(dynamic: true), defaultText: "1.0", computedDefault: nil, offset: 107, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_FRAME_PEAK", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "-1.0", computedDefault: nil, offset: 108, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_SCENE_CONTRAST", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.35", computedDefault: nil, offset: 109, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_NOISE_LEVEL", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.10", computedDefault: nil, offset: 110, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_MOTION_LEVEL", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.20", computedDefault: nil, offset: 111, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_AMOUNT", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "1.05", computedDefault: nil, offset: 112, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_FINE_COARSE", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.50", computedDefault: nil, offset: 113, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_FACTOR_RENDERED", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "3.05", computedDefault: nil, offset: 114, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_TEMPORAL_ALPHA", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.611", computedDefault: nil, offset: 115, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_HALO_GUARD", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.50", computedDefault: nil, offset: 116, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_TEXTURE_BIAS", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.50", computedDefault: nil, offset: 117, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_FINE_STRENGTH", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "1.00", computedDefault: nil, offset: 118, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_MEDIUM_STRENGTH", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "1.00", computedDefault: nil, offset: 119, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_COARSE_STRENGTH", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "1.00", computedDefault: nil, offset: 120, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_ALGO", family: .photonSharp, kind: .compileTimeDefine, defaultText: "0", computedDefault: nil, offset: 121, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_BLOCK_LEVEL", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 122, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_RING_LEVEL", family: .photonSharp, kind: .floatUniform(dynamic: true), defaultText: "0.0", computedDefault: nil, offset: 123, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_CONTENT_ADAPT", family: .photonSharp, kind: .compileTimeDefine, defaultText: "1", computedDefault: nil, offset: 124, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_MEDIUM_BAND_ACTIVE", family: .photonSharp, kind: .compileTimeDefine, defaultText: "1", computedDefault: nil, offset: 125, stage: .photon),
        LookParameter(name: "PHOTON_SHARP_COARSE_BAND_ACTIVE", family: .photonSharp, kind: .compileTimeDefine, defaultText: "1", computedDefault: nil, offset: 126, stage: .photon),
    ]
}

public enum LookParamError: Error, Equatable, Sendable {
    case unknownName
    case nonFinite
    /// intUniform lanes take integral values only.
    case notIntegral
    /// compileTimeDefine lanes are baked into the shader; a change needs a
    /// precompiled variant table, never a runtime recompile.
    case requiresVariant
}

/// The one live block: current values for every declared look parameter,
/// one revision per effective change, one serialized upload per frame.
public struct LookParameterBlock: Equatable, Sendable {
    public private(set) var revision: ParameterBlockRevision
    /// Lane values in canonical table order; mutate only through set().
    public private(set) var values: [Double]

    public init() {
        values = LookParameterTable.all.map(\.defaultValue)
        revision = ParameterBlockRevision(0)
    }

    public func value(_ name: String) -> Double? {
        guard let i = LookParameterTable.index(of: name) else { return nil }
        return values[i]
    }

    /// Typed and loud: unknown names, nonfinite values and compile-time defines
    /// are refused with no change. A same-value set is accepted without a
    /// revision bump; only an effective change advances the revision.
    @discardableResult
    public mutating func set(_ name: String, _ v: Double) -> Result<ParameterBlockRevision, LookParamError> {
        guard let i = LookParameterTable.index(of: name) else { return .failure(.unknownName) }
        guard v.isFinite else { return .failure(.nonFinite) }
        if case .compileTimeDefine = LookParameterTable.all[i].kind { return .failure(.requiresVariant) }
        if case .intUniform = LookParameterTable.all[i].kind, v != v.rounded() { return .failure(.notIntegral) }
        guard values[i] != v else { return .success(revision) }
        values[i] = v
        revision = ParameterBlockRevision(revision.value &+ 1)
        return .success(revision)
    }
}

/// Version 1 wire format for the per-frame upload. Header 24 B: magic VPL1 at 0,
/// version at 4, revision at 8, lane count at 16, reserved zero at 20. Payload:
/// 127 little-endian 32-bit words; float lanes carry the Float32 bit pattern,
/// int/define lanes carry the UInt32 bit pattern of Int32.
public enum LookParameterABI {
    public static let magic: UInt32 = 0x314C5056 // bytes VPL1
    public static let version: UInt32 = 1
    public static let headerBytes = 24
    public static let payloadBytes = LookParameterTable.count * 4
    public static let packetBytes = headerBytes + payloadBytes

    static func append(_ value: UInt32, to bytes: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    static func append(_ value: UInt64, to bytes: inout Data) {
        append(UInt32(truncatingIfNeeded: value), to: &bytes)
        append(UInt32(truncatingIfNeeded: value >> 32), to: &bytes)
    }
    static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
    static func wide(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        UInt64(word(bytes, offset)) | UInt64(word(bytes, offset + 4)) << 32
    }
    static func laneWord(_ p: LookParameter, _ v: Double) -> UInt32 {
        switch p.kind {
        case .floatUniform: return Float(v).bitPattern
        case .intUniform, .compileTimeDefine: return UInt32(bitPattern: Int32(v))
        }
    }

    public static func serialize(_ block: LookParameterBlock) -> Data {
        var bytes = Data(); bytes.reserveCapacity(packetBytes)
        append(magic, to: &bytes); append(version, to: &bytes)
        append(block.revision.value, to: &bytes)
        append(UInt32(LookParameterTable.count), to: &bytes); append(UInt32(0), to: &bytes)
        for (i, p) in LookParameterTable.all.enumerated() {
            append(laneWord(p, block.values[i]), to: &bytes)
        }
        return bytes
    }

    public enum ConsumeError: Error, Equatable, Sendable {
        case malformed, unsupportedVersion, laneCountMismatch, revisionMismatch, invalidPayload
    }

    public struct Block: Equatable, Sendable {
        public let revision: ParameterBlockRevision
        public let values: [Double]
        public let shaderBytes: Data
    }

    /// Presenter-facing boundary: validates identity and lanes, exposes the
    /// exact payload words for a future Metal binding. No pixel claim.
    public static func consume(_ packet: Data, revision: ParameterBlockRevision)
        -> Result<Block, ConsumeError> {
        let b = [UInt8](packet)
        guard b.count == packetBytes, word(b, 0) == magic else { return .failure(.malformed) }
        guard word(b, 4) == version else { return .failure(.unsupportedVersion) }
        guard word(b, 16) == UInt32(LookParameterTable.count), word(b, 20) == 0 else { return .failure(.laneCountMismatch) }
        let rev = ParameterBlockRevision(wide(b, 8))
        guard rev == revision else { return .failure(.revisionMismatch) }
        var values = [Double](); values.reserveCapacity(LookParameterTable.count)
        for (i, p) in LookParameterTable.all.enumerated() {
            let w = word(b, headerBytes + i * 4)
            switch p.kind {
            case .floatUniform:
                let f = Float(bitPattern: w)
                guard f.isFinite else { return .failure(.invalidPayload) }
                values.append(Double(f))
            case .intUniform, .compileTimeDefine:
                values.append(Double(Int32(bitPattern: w)))
            }
        }
        return .success(Block(revision: rev, values: values, shaderBytes: Data(b[headerBytes...])))
    }
}

/// P21 stage routing (DR-0015): every look parameter has exactly one primary
/// consuming stage. Stage-less passes (decode, colorToneMap, bitmapSubtitles,
/// present) consume no look parameters today.
public enum LookParameterRouting {
    public static func parameters(for stage: RenderGraphStage) -> [LookParameter] {
        LookParameterTable.all.filter { $0.stage == stage }
    }
    public static func count(for stage: RenderGraphStage) -> Int {
        LookParameterTable.all.reduce(0) { $0 + ($1.stage == stage ? 1 : 0) }
    }
    /// FNV-1a 64 over "name:stage" lines in canonical table order - pins the
    /// routing to the measured classification: 0xc6684e869ace3449 (DR-0015).
    public static func routingDigest() -> UInt64 {
        var text = ""
        for p in LookParameterTable.all { text += "\(p.name):\(p.stage.rawValue)\n" }
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return h
    }
}

extension LookParameterTable {
    private static let byName: [String: Int] = {
        var m = [String: Int]()
        for (i, p) in all.enumerated() { m[p.name] = i }
        return m
    }()
    public static func index(of name: String) -> Int? { byName[name] }
    public static func parameter(_ name: String) -> LookParameter? { index(of: name).map { all[$0] } }

    /// FNV-1a 64 over the canonical manifest lines
    /// "family:name:[DYNAMIC ]type=default" joined by \n with a trailing \n -
    /// the same text the source measurement produced. Pins the table to the
    /// measured live universe: 0x6c88c1b6baf184b4 at c54467887.
    public static func manifestDigest() -> UInt64 {
        var text = ""
        for p in all {
            let dyn: String
            let type: String
            switch p.kind {
            case .floatUniform(let d): dyn = d ? "DYNAMIC " : ""; type = "float"
            case .intUniform: dyn = ""; type = "int"
            case .compileTimeDefine: dyn = ""; type = "DEFINE"
            }
            text += "\(p.family.rawValue):\(p.name):\(dyn)\(type)=\(p.defaultText)\n"
        }
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return h
    }
}
