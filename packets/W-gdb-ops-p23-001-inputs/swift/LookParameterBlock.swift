import Foundation

// P22 (arch-195b; arch-196z item 3, M3-render lane): one live look parameter
// block. All 73 live vr180-look //!PARAMs plus the 18 dynamic photon-sharp
// floats ride one Swift value uploaded as a uniform buffer every frame.
// Changing a value never recompiles or reinstalls a shader: the block is
// revisioned on the wire (LookUniformABI) and the presenter uploads bytes.
// The 4 photon DEFINE params (algo, contentAdapt, mediumBandActive,
// coarseBandActive) are pipeline-variant selectors, NOT block lanes (P22:
// a parameter needing a variant gets a precompiled variant table, still no
// runtime compile).
//
// Source pins:
//   vr180-look.lua sha256 c455d945818a23ed7ddcb77a22002d12873430e53198b0ef253a673d7ccbeffc
//     (goreda/instinct lane tree archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua;
//      73 distinct live //!PARAMs: 68 base + 5 pack. PLAN's "77" is stale.)
//   photon-sharp.lua blob 25450b73: 18 DYNAMIC float of the pinned 22-site block.

/// One revisioned look block: 91 float lanes with stable wire IDs.
/// Never upload this struct's memory; LookUniformABI defines the wire format.
public struct LookParameterBlock: Equatable, Sendable {
    public enum Lane: Int, CaseIterable, Sendable {
        case vrNativeTb = 0   // vr_native_tb
        case vrCrossEye = 1   // vr_cross_eye
        case vrCalibration = 2   // vr_calibration
        case vrHeadRoll = 3   // vr_head_roll
        case vrSurfaceW = 4   // vr_surface_w
        case vrSurfaceH = 5   // vr_surface_h
        case vrSurfaceX = 6   // vr_surface_x
        case vrSurfaceY = 7   // vr_surface_y
        case vrSourceLayout = 8   // vr_source_layout
        case vrPlain = 9   // vr_plain
        case vrPlainAspect = 10   // vr_plain_aspect
        case vrFlatSbs = 11   // vr_flat_sbs
        case vrFlatMono = 12   // vr_flat_mono
        case vrD3Gain = 13   // vr_d3_gain
        case vrEyeAspect = 14   // vr_eye_aspect
        case vrFrameFit = 15   // vr_frame_fit
        case vrFrameSpacing = 16   // vr_frame_spacing
        case vrSourceX = 17   // vr_source_x
        case vrSourceY = 18   // vr_source_y
        case vrSourceW = 19   // vr_source_w
        case vrSourceH = 20   // vr_source_h
        case vrCropX = 21   // vr_crop_x
        case vrCropY = 22   // vr_crop_y
        case vrAspectOverride = 23   // vr_aspect_override
        case vrManualYaw = 24   // vr_manual_yaw
        case vrManualPitch = 25   // vr_manual_pitch
        case vrManualView = 26   // vr_manual_view
        case vrYaw = 27   // vr_yaw
        case vrPitch = 28   // vr_pitch
        case vrFov = 29   // vr_fov
        case vrRoll = 30   // vr_roll
        case blinkTopBottom = 31   // blink_top_bottom
        case blinkLidL = 32   // blink_lid_l
        case blinkLidR = 33   // blink_lid_r
        case blinkReopenL = 34   // blink_reopen_l
        case blinkReopenR = 35   // blink_reopen_r
        case blinkCloseMs = 36   // blink_close_ms
        case blinkOpenMs = 37   // blink_open_ms
        case blinkFailopenMs = 38   // blink_failopen_ms
        case blinkAdaptMs = 39   // blink_adapt_ms
        case blinkUpper = 40   // blink_upper
        case blinkLower = 41   // blink_lower
        case blinkArc = 42   // blink_arc
        case blinkFringe = 43   // blink_fringe
        case blinkGlow = 44   // blink_glow
        case blinkGlowRadius = 45   // blink_glow_radius
        case blinkSlitBlur = 46   // blink_slit_blur
        case blinkContrast = 47   // blink_contrast
        case blinkLift = 48   // blink_lift
        case blinkSbsStrength = 49   // blink_sbs_strength
        case blinkWarmR = 50   // blink_warm_r
        case blinkWarmG = 51   // blink_warm_g
        case blinkWarmB = 52   // blink_warm_b
        case vrBaseIpd = 53   // vr_base_ipd
        case vrIpdNudge = 54   // vr_ipd_nudge
        case vrHeadX = 55   // vr_head_x
        case vrHeadY = 56   // vr_head_y
        case vrHeadZ = 57   // vr_head_z
        case vrSwapEyes = 58   // vr_swap_eyes
        case vrZoomcompBaseline = 59   // vr_zoomcomp_baseline
        case vrGapFrac = 60   // vr_gap_frac
        case vrGapBlurFrac = 61   // vr_gap_blur_frac
        case vrVignetteRefFov = 62   // vr_vignette_ref_fov
        case vrParallaxStrength = 63   // vr_parallax_strength
        case vrParallaxDisparity = 64   // vr_parallax_disparity
        case vrVignetteStart = 65   // vr_vignette_start
        case vrVignetteDarken = 66   // vr_vignette_darken
        case vrVignetteBlur = 67   // vr_vignette_blur
        case vrPack = 68   // vr_pack
        case vrPkConv = 69   // vr_pk_conv
        case vrPkZoom = 70   // vr_pk_zoom
        case vrPkSoft = 71   // vr_pk_soft
        case vrPkSurroundInvert = 72   // vr_pk_surround_invert
        case phFramePeak = 73   // ph_frame_peak
        case phSceneContrast = 74   // ph_scene_contrast
        case phNoiseLevel = 75   // ph_noise_level
        case phMotionLevel = 76   // ph_motion_level
        case phAmount = 77   // ph_amount
        case phFineCoarse = 78   // ph_fine_coarse
        case phFactorRendered = 79   // ph_factor_rendered
        case phTemporalAlpha = 80   // ph_temporal_alpha
        case phHaloGuard = 81   // ph_halo_guard
        case phTextureBias = 82   // ph_texture_bias
        case phFineStrength = 83   // ph_fine_strength
        case phMediumStrength = 84   // ph_medium_strength
        case phCoarseStrength = 85   // ph_coarse_strength
        case phCoarseRadius = 86   // ph_coarse_radius
        case phCoringScale = 87   // ph_coring_scale
        case phHaloScale = 88   // ph_halo_scale
        case phBlockLevel = 89   // ph_block_level
        case phRingLevel = 90   // ph_ring_level
        public var shaderName: String {
            switch self {
            case .vrNativeTb: return "vr_native_tb"
            case .vrCrossEye: return "vr_cross_eye"
            case .vrCalibration: return "vr_calibration"
            case .vrHeadRoll: return "vr_head_roll"
            case .vrSurfaceW: return "vr_surface_w"
            case .vrSurfaceH: return "vr_surface_h"
            case .vrSurfaceX: return "vr_surface_x"
            case .vrSurfaceY: return "vr_surface_y"
            case .vrSourceLayout: return "vr_source_layout"
            case .vrPlain: return "vr_plain"
            case .vrPlainAspect: return "vr_plain_aspect"
            case .vrFlatSbs: return "vr_flat_sbs"
            case .vrFlatMono: return "vr_flat_mono"
            case .vrD3Gain: return "vr_d3_gain"
            case .vrEyeAspect: return "vr_eye_aspect"
            case .vrFrameFit: return "vr_frame_fit"
            case .vrFrameSpacing: return "vr_frame_spacing"
            case .vrSourceX: return "vr_source_x"
            case .vrSourceY: return "vr_source_y"
            case .vrSourceW: return "vr_source_w"
            case .vrSourceH: return "vr_source_h"
            case .vrCropX: return "vr_crop_x"
            case .vrCropY: return "vr_crop_y"
            case .vrAspectOverride: return "vr_aspect_override"
            case .vrManualYaw: return "vr_manual_yaw"
            case .vrManualPitch: return "vr_manual_pitch"
            case .vrManualView: return "vr_manual_view"
            case .vrYaw: return "vr_yaw"
            case .vrPitch: return "vr_pitch"
            case .vrFov: return "vr_fov"
            case .vrRoll: return "vr_roll"
            case .blinkTopBottom: return "blink_top_bottom"
            case .blinkLidL: return "blink_lid_l"
            case .blinkLidR: return "blink_lid_r"
            case .blinkReopenL: return "blink_reopen_l"
            case .blinkReopenR: return "blink_reopen_r"
            case .blinkCloseMs: return "blink_close_ms"
            case .blinkOpenMs: return "blink_open_ms"
            case .blinkFailopenMs: return "blink_failopen_ms"
            case .blinkAdaptMs: return "blink_adapt_ms"
            case .blinkUpper: return "blink_upper"
            case .blinkLower: return "blink_lower"
            case .blinkArc: return "blink_arc"
            case .blinkFringe: return "blink_fringe"
            case .blinkGlow: return "blink_glow"
            case .blinkGlowRadius: return "blink_glow_radius"
            case .blinkSlitBlur: return "blink_slit_blur"
            case .blinkContrast: return "blink_contrast"
            case .blinkLift: return "blink_lift"
            case .blinkSbsStrength: return "blink_sbs_strength"
            case .blinkWarmR: return "blink_warm_r"
            case .blinkWarmG: return "blink_warm_g"
            case .blinkWarmB: return "blink_warm_b"
            case .vrBaseIpd: return "vr_base_ipd"
            case .vrIpdNudge: return "vr_ipd_nudge"
            case .vrHeadX: return "vr_head_x"
            case .vrHeadY: return "vr_head_y"
            case .vrHeadZ: return "vr_head_z"
            case .vrSwapEyes: return "vr_swap_eyes"
            case .vrZoomcompBaseline: return "vr_zoomcomp_baseline"
            case .vrGapFrac: return "vr_gap_frac"
            case .vrGapBlurFrac: return "vr_gap_blur_frac"
            case .vrVignetteRefFov: return "vr_vignette_ref_fov"
            case .vrParallaxStrength: return "vr_parallax_strength"
            case .vrParallaxDisparity: return "vr_parallax_disparity"
            case .vrVignetteStart: return "vr_vignette_start"
            case .vrVignetteDarken: return "vr_vignette_darken"
            case .vrVignetteBlur: return "vr_vignette_blur"
            case .vrPack: return "vr_pack"
            case .vrPkConv: return "vr_pk_conv"
            case .vrPkZoom: return "vr_pk_zoom"
            case .vrPkSoft: return "vr_pk_soft"
            case .vrPkSurroundInvert: return "vr_pk_surround_invert"
            case .phFramePeak: return "ph_frame_peak"
            case .phSceneContrast: return "ph_scene_contrast"
            case .phNoiseLevel: return "ph_noise_level"
            case .phMotionLevel: return "ph_motion_level"
            case .phAmount: return "ph_amount"
            case .phFineCoarse: return "ph_fine_coarse"
            case .phFactorRendered: return "ph_factor_rendered"
            case .phTemporalAlpha: return "ph_temporal_alpha"
            case .phHaloGuard: return "ph_halo_guard"
            case .phTextureBias: return "ph_texture_bias"
            case .phFineStrength: return "ph_fine_strength"
            case .phMediumStrength: return "ph_medium_strength"
            case .phCoarseStrength: return "ph_coarse_strength"
            case .phCoarseRadius: return "ph_coarse_radius"
            case .phCoringScale: return "ph_coring_scale"
            case .phHaloScale: return "ph_halo_scale"
            case .phBlockLevel: return "ph_block_level"
            case .phRingLevel: return "ph_ring_level"
            }
        }
    }

    /// Shader-exact defaults (source: vr180-look.lua @ c455d945, photon-sharp.lua blob 25450b73).
    public static let defaults: [Float] = [
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 0.02, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
        1.0, 1.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        0.0, 1.5707963, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0,
        80.0, 180.0, 200.0, 250.0,
        0.92, 0.08, 0.08, 0.03,
        0.05, 0.08, 0.004, 0.4,
        0.15, 1.0, 1.0, 1.0,
        1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.007500,
        0.0125, 0.5, 90.000000, 0.400000,
        -0.4, 0.250000, 1.0, 0.0015,
        0.0, 0.5, 1.0, 1.0,
        0.0, -1.0, 0.35, 0.10,
        0.20, 1.05, 0.50, 3.05,
        0.611, 0.65, 0.50, 1.00,
        1.00, 1.00, 0.0, 1.0,
        1.0, 0.0, 0.0,
    ]
    public static let laneCount = 91

    /// Lane values in Lane wire order. Always laneCount entries, all finite.
    public private(set) var values: [Float]

    public init() { values = Self.defaults }

    public init?(values: [Float]) {
        guard values.count == Self.laneCount, values.allSatisfy(\.isFinite) else { return nil }
        self.values = values
    }

    public func value(_ lane: Lane) -> Float { values[lane.rawValue] }

    /// Returns a copy with one lane changed, nil when the value is not
    /// finite. No shader reinstall, no recompile: the next revisioned packet
    /// carries the new bytes.
    public func setting(_ lane: Lane, _ newValue: Float) -> LookParameterBlock? {
        guard newValue.isFinite else { return nil }
        var copy = values
        copy[lane.rawValue] = newValue
        return LookParameterBlock(values: copy)
    }
}

public enum LookParamViolation: Equatable, Sendable {
    case nonFinite(lane: LookParameterBlock.Lane)
    case outOfRange(lane: LookParameterBlock.Lane, value: Float, min: Float, max: Float)
    case negativeStrength(lane: LookParameterBlock.Lane, value: Float)
}

extension LookParameterBlock {
    /// Semantic domains the shader math relies on. Switch params (0/1 floats
    /// pushed by the host) are checked for finiteness only.
    public func violations() -> [LookParamViolation] {
        var out: [LookParamViolation] = []
        for lane in Lane.allCases where !value(lane).isFinite { out.append(.nonFinite(lane: lane)) }
        func range(_ lane: Lane, _ lo: Float, _ hi: Float) {
            let v = value(lane)
            if v.isFinite && (v < lo || v > hi) { out.append(.outOfRange(lane: lane, value: v, min: lo, max: hi)) }
        }
        range(.vrFov, .leastNonzeroMagnitude, Float.pi)
        range(.vrSourceW, .leastNonzeroMagnitude, 1)
        range(.vrSourceH, .leastNonzeroMagnitude, 1)
        range(.vrCropX, .leastNonzeroMagnitude, 1)
        range(.vrCropY, .leastNonzeroMagnitude, 1)
        for lane in [Lane.blinkUpper, .blinkLower, .blinkArc, .blinkFringe, .blinkGlow,
                     .blinkGlowRadius, .blinkContrast, .blinkLift, .blinkSbsStrength,
                     .blinkWarmR, .blinkWarmG, .blinkWarmB, .phFineCoarse, .phTemporalAlpha] {
            range(lane, 0, 1)
        }
        for lane in [Lane.blinkCloseMs, .blinkOpenMs, .blinkFailopenMs, .blinkAdaptMs] {
            range(lane, 0, .greatestFiniteMagnitude)
        }
        for lane in [Lane.phAmount, .phFineStrength, .phMediumStrength, .phCoarseStrength, .phFactorRendered] {
            let v = value(lane)
            if v.isFinite && v < 0 { out.append(.negativeStrength(lane: lane, value: v)) }
        }
        // framePeak: -1.0 is the no-feed sentinel, never a real peak.
        let peak = value(.phFramePeak)
        if peak.isFinite && peak < 0 && peak != -1.0 {
            out.append(.outOfRange(lane: .phFramePeak, value: peak, min: -1, max: .greatestFiniteMagnitude))
        }
        return out
    }
}

/// Version 1 wire format for the look block. Header layout matches
/// FrameUniformABI: magic at 0, version at 4, session at 8, parameter
/// revision at 16; payload starts at 24. All words little endian.
public enum LookUniformABI {
    public static let magic: UInt32 = 0x314B4C47 // bytes GLK1
    public static let version: UInt32 = 1
    public static let headerBytes = 24
    public static let payloadBytes = LookParameterBlock.laneCount * 4
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

    public static func packet(session: UInt64, revision: ParameterBlockRevision,
                              block: LookParameterBlock) -> Data? {
        guard block.violations().isEmpty else { return nil }
        var bytes = Data()
        append(Self.magic, to: &bytes)
        append(Self.version, to: &bytes)
        append(session, to: &bytes)
        append(revision.value, to: &bytes)
        for v in block.values { append(v.bitPattern, to: &bytes) }
        return bytes
    }
}

public enum LookUniformConsumerError: Error, Equatable, Sendable {
    case malformed, unsupportedVersion, sessionMismatch, revisionMismatch, invalidPayload
}

/// Presenter-facing boundary: consumes serialized bytes, validates identity
/// and lanes, and exposes the exact payload bytes for the Metal binding.
public enum LookUniformConsumer {
    public struct Block: Equatable, Sendable {
        public let session: UInt64
        public let revision: ParameterBlockRevision
        public let parameters: LookParameterBlock
        public let shaderBytes: Data
    }
    public static func consume(_ packet: Data, session: UInt64, revision: ParameterBlockRevision)
        -> Result<Block, LookUniformConsumerError> {
        let b = [UInt8](packet)
        guard b.count == LookUniformABI.packetBytes,
              LookUniformABI.word(b, 0) == LookUniformABI.magic else { return .failure(.malformed) }
        guard LookUniformABI.word(b, 4) == LookUniformABI.version else { return .failure(.unsupportedVersion) }
        guard LookUniformABI.wide(b, 8) == session else { return .failure(.sessionMismatch) }
        guard LookUniformABI.wide(b, 16) == revision.value else { return .failure(.revisionMismatch) }
        var values = [Float]()
        values.reserveCapacity(LookParameterBlock.laneCount)
        for i in 0..<LookParameterBlock.laneCount {
            values.append(Float(bitPattern: LookUniformABI.word(b, LookUniformABI.headerBytes + i * 4)))
        }
        guard let block = LookParameterBlock(values: values), block.violations().isEmpty else {
            return .failure(.invalidPayload)
        }
        return .success(Block(session: session, revision: revision, parameters: block,
                              shaderBytes: Data(b[LookUniformABI.headerBytes...])))
    }
}
