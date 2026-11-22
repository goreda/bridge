import Foundation

// P29-STEREO-LOOK v2 (lane: stereo/photon): the gorav-side value producer
// for the 33 stereoProjection lanes of LookParameterTable. This is a pure
// value-type port of the AUTHORITATIVE vr180-look.lua uniform push
// (vr_push_uniforms payload construction, pin c455d945 lines 631-680, plus
// the state/constants at lines 11-64) - the same re-expression pattern as
// LiveControlActuator (DR-0021). Foundation only, no mpv API: every
// host-side fact (media geometry, display metrics, face distance) is a
// typed input. No default is invented: every constant below carries its
// Lua line value, and every host-derived quantity (effective eye aspect,
// source crop, applied IPD base) is supplied by the caller.
//
// INERT until the gor lane's LuaJIT witness passes: the Lua stays
// authoritative. This file produces VALUES only; stage install, renderer
// wiring and App registration are owned elsewhere (Ops).
//
// Coverage: exactly the 33 lanes whose LookParameterTable stage is
// .stereoProjection (LookParameters.swift pin 466f5f0f33). Uniforms the
// Lua pushes that belong to OTHER stages (surface/output/crop/blink/tune
// vignette/...) are NOT written here.
//
// UPLOAD SEMANTICS (v2, Ops review): the authority does not upload model
// doubles - it SERIALIZES each lane with its own printf precision
// (%.6f / %.4f / %.1f, pin c455d945 ll.654-676) and the GPU receives the
// Float32 of the parsed decimal. Produced values below are therefore
// QUANTIZED through the same per-lane format before they are returned:
// f32(stored) == f32(parse(format_lua(d))) exactly. Comparison against
// the authority must happen on these quantized values, never on raw
// model doubles with a tolerance.
// VALIDATION: emitted values (yaw+manualYaw, the roll sum and final
// clamped pitch/fov results) are checked finite before quantization;
// every quantized value must parse finite AND fit Float32
// (Float(v).isFinite) or the whole push refuses typed
// (.notRepresentable). apply() writes a WORKING COPY of the block and
// commits only when all 33 sets succeed - a refused push leaves the
// caller's block bit-identical (values and revision).

/// Refusals of the producer (typed; no clamping into validity, no
/// invented fallback).
public enum StereoLookProducerError: Error, Equatable {
    /// A supplied or composed value was NaN or infinite (the field or
    /// lane name is carried).
    case nonFinite(field: String)
    /// A quantized lane value does not fit Float32 (the serialized
    /// upload domain). Carries the lane name.
    case notRepresentable(lane: String)
    /// source_layout outside the Lua's 0...6 encoding (pin c455d945 l.24).
    case invalidLayout(Int)
    /// flat_pack outside the Lua's 0...4 encoding (pin c455d945 l.26-30).
    case invalidPack(Int)
    /// The typed block refused a lane write (surfaced from
    /// LookParameterBlock.set; impossible for the pinned 33 lanes, kept
    /// typed rather than assumed).
    case laneRefused(name: String)
}

/// Session state the push consults (pin c455d945 ll.11-30, 424-425,
/// 898). `layout` uses the Lua's own integer encoding:
/// 0 mono (and flat-2d3d), 1 flat SBS, 2 flat TB, 3 VR180 SBS, 4 VR180 TB,
/// 5 VR360 mono, 6 VR360 TB. The 180/360 discrimination is NOT derivable
/// from the spmeta/resolver vocabulary (spmeta.h: the registry does not
/// carry it); the session authority supplies it.
public struct StereoLookSession: Equatable {
    public var enabled: Bool
    public var toolsActive: Bool
    public var layout: Int
    public var flatSbs: Bool
    public var flatMono: Bool
    public var flatPack: Int
    public var pkConv: Double
    public var pkZoom: Double
    public var pkSoft: Double
    /// The Lua's own constant (pin c455d945 l.44, D3_GAIN): max per-eye
    /// shift = gain/2 of frame width. Matches the table default (off=13).
    public var d3Gain: Double
    public init(enabled: Bool, toolsActive: Bool, layout: Int,
                flatSbs: Bool = false, flatMono: Bool = false, flatPack: Int = 0,
                pkConv: Double = 0.5, pkZoom: Double = 1.0, pkSoft: Double = 1.0,
                d3Gain: Double = 0.02) {
        self.enabled = enabled; self.toolsActive = toolsActive
        self.layout = layout; self.flatSbs = flatSbs; self.flatMono = flatMono
        self.flatPack = flatPack
        self.pkConv = pkConv; self.pkZoom = pkZoom; self.pkSoft = pkSoft
        self.d3Gain = d3Gain
    }
}

/// Camera/control state (pin c455d945 ll.13-22, 100-156). Angles in
/// radians EXCEPT fov and manualFov, which are degrees (the push converts:
/// l.657). Manual offsets compose into camera angles only for native
/// (layout >= 3) layouts (l.647-651).
public struct StereoLookControls: Equatable {
    public var yaw: Double
    public var pitch: Double
    public var fov: Double
    public var roll: Double
    public var manualYaw: Double
    public var manualPitch: Double
    public var manualFov: Double
    public var manualRoll: Double
    public var headX: Double
    public var headY: Double
    public var headZ: Double
    public var baseIpd: Double
    public var ipdNudge: Double
    /// vr_ipd_applied_base (l.352, set by vr_update_distance from host
    /// display metrics + face distance). nil = dial value used as-is
    /// (l.641). The distance machinery itself is host-fed and stays
    /// caller-owned; only its RESULT enters here.
    public var appliedIpdBase: Double?
    /// vr_native_raw_roll (l.650-651): native-only raw roll path,
    /// composes with manualRoll when present and layout >= 3.
    public var nativeRawRoll: Double?
    /// Lua default 1.0 (l.155-157); matches the table default (off=58).
    public var swapEyes: Double
    public var crossEye: Double
    public var calibration: Double
    public init(yaw: Double = 0, pitch: Double = 0, fov: Double = 135, roll: Double = 0,
                manualYaw: Double = 0, manualPitch: Double = 0, manualFov: Double = 0,
                manualRoll: Double = 0,
                headX: Double = 0, headY: Double = 0, headZ: Double = 0,
                baseIpd: Double = 0, ipdNudge: Double = 0,
                appliedIpdBase: Double? = nil, nativeRawRoll: Double? = nil,
                swapEyes: Double = 1, crossEye: Double = 0, calibration: Double = 0) {
        self.yaw = yaw; self.pitch = pitch; self.fov = fov; self.roll = roll
        self.manualYaw = manualYaw; self.manualPitch = manualPitch
        self.manualFov = manualFov; self.manualRoll = manualRoll
        self.headX = headX; self.headY = headY; self.headZ = headZ
        self.baseIpd = baseIpd; self.ipdNudge = ipdNudge
        self.appliedIpdBase = appliedIpdBase; self.nativeRawRoll = nativeRawRoll
        self.swapEyes = swapEyes; self.crossEye = crossEye; self.calibration = calibration
    }
}

/// Host-resolved geometry (pin c455d945 ll.415, 496-516, 798-809). The
/// media-geometry fallback chains (effective_flat_eye_aspect,
/// plain_film_aspect) read mpv properties; here the RESOLVED values are
/// inputs. eyeAspect = effective_flat_eye_aspect(): the caller's
/// resolved flat-2d3d eye aspect (0 when unset, exactly like the Lua).
public struct StereoLookGeometry: Equatable {
    public var eyeAspect: Double
    /// source_eye_crop {x, y, w, h} (l.415); default {0,0,1,1}.
    public var sourceX: Double
    public var sourceY: Double
    public var sourceW: Double
    public var sourceH: Double
    public init(eyeAspect: Double = 0,
                sourceX: Double = 0, sourceY: Double = 0,
                sourceW: Double = 1, sourceH: Double = 1) {
        self.eyeAspect = eyeAspect
        self.sourceX = sourceX; self.sourceY = sourceY
        self.sourceW = sourceW; self.sourceH = sourceH
    }
}

/// The two stereoProjection-stage vr_tune entries (pin c455d945
/// ll.1217-1218; defaults ll.124-135: strength 0.4, disparity =
/// strength * -1). Other vr_tune entries belong to other stages.
public struct StereoLookTune: Equatable {
    public var parallaxStrength: Double
    public var parallaxDisparity: Double
    public init(parallaxStrength: Double = 0.4, parallaxDisparity: Double = -0.4) {
        self.parallaxStrength = parallaxStrength
        self.parallaxDisparity = parallaxDisparity
    }
}

/// One produced lane assignment, ALREADY QUANTIZED to the lane's
/// serialized-upload precision (see the file header). Equatable so the
/// caller can dedupe (the Lua dedupes by payload-string equality, pin
/// c455d945 l.685-686; apply() itself writes unconditionally).
public struct StereoLaneValue: Equatable {
    public let name: String
    public let value: Double
}

public enum StereoLookProducer {
    /// The Lua's global vr factor (pin c455d945 l.13).
    public static let vrFactor = 45.0
    /// VR_FOV_MIN = vr_f / 2 (l.52).
    public static let fovMinDeg = vrFactor / 2
    /// VR_FOV_MAX = vr_f * 3.5 (l.53); flat layouts use 179 (l.55).
    public static let fovMaxSphericalDeg = vrFactor * 3.5
    public static let fovMaxFlatDeg = 179.0

    private static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }

    private static func finite(_ v: Double) -> Bool { v == v && v.magnitude < Double.infinity }

    /// The authority's per-lane serialization precision (pin c455d945
    /// ll.654-676). Lanes not listed serialize as %.6f.
    private static let format1: Set<String> = [
        "vr_swap_eyes", "vr_cross_eye", "vr_calibration", "vr_native_tb",
        "vr_flat_sbs", "vr_flat_mono", "vr_plain", "vr_source_layout",
        "vr_pack", "vr_pk_soft",
    ]
    private static let format4: Set<String> = ["vr_pk_conv", "vr_pk_zoom"]

    /// Serializes exactly like the authority (C printf via both sides)
    /// and re-parses, yielding the Double whose Float32 is bit-identical
    /// to the authority's GPU upload. Throws typed on non-finite or
    /// Float32-unrepresentable results (overflowing compositions,
    /// huge-but-finite controls).
    private static func quantize(_ v: Double, lane: String) throws -> Double {
        guard finite(v) else { throw StereoLookProducerError.nonFinite(field: lane) }
        let fmt = format1.contains(lane) ? "%.1f" : (format4.contains(lane) ? "%.4f" : "%.6f")
        let s = String(format: fmt, v)
        guard let q = Double(s), finite(q) else {
            throw StereoLookProducerError.nonFinite(field: lane)
        }
        guard Float(q).isFinite else {
            throw StereoLookProducerError.notRepresentable(lane: lane)
        }
        return q
    }

    /// The full 33-lane push, in LookParameterTable stereoProjection
    /// order, quantized to serialized-upload precision. Returns nil when
    /// the Lua's publication gate is closed (pin c455d945 l.632: not
    /// enabled and not tools_active publish nothing); a nil result must
    /// NOT mutate any block.
    public static func laneValues(session: StereoLookSession,
                                  controls: StereoLookControls,
                                  geometry: StereoLookGeometry,
                                  tune: StereoLookTune = StereoLookTune()) throws -> [StereoLaneValue]? {
        guard session.enabled || session.toolsActive else { return nil }
        guard (0...6).contains(session.layout) else {
            throw StereoLookProducerError.invalidLayout(session.layout)
        }
        guard (0...4).contains(session.flatPack) else {
            throw StereoLookProducerError.invalidPack(session.flatPack)
        }
        let inputs: [(String, Double)] = [
            ("yaw", controls.yaw), ("pitch", controls.pitch), ("fov", controls.fov),
            ("roll", controls.roll), ("manualYaw", controls.manualYaw),
            ("manualPitch", controls.manualPitch), ("manualFov", controls.manualFov),
            ("manualRoll", controls.manualRoll),
            ("headX", controls.headX), ("headY", controls.headY), ("headZ", controls.headZ),
            ("baseIpd", controls.baseIpd), ("ipdNudge", controls.ipdNudge),
            ("swapEyes", controls.swapEyes), ("crossEye", controls.crossEye),
            ("calibration", controls.calibration),
            ("eyeAspect", geometry.eyeAspect),
            ("sourceX", geometry.sourceX), ("sourceY", geometry.sourceY),
            ("sourceW", geometry.sourceW), ("sourceH", geometry.sourceH),
            ("parallaxStrength", tune.parallaxStrength),
            ("parallaxDisparity", tune.parallaxDisparity),
            ("d3Gain", session.d3Gain),
            ("pkConv", session.pkConv), ("pkZoom", session.pkZoom), ("pkSoft", session.pkSoft),
        ]
        for (name, v) in inputs where !finite(v) {
            throw StereoLookProducerError.nonFinite(field: name)
        }
        if let a = controls.appliedIpdBase, !finite(a) {
            throw StereoLookProducerError.nonFinite(field: "appliedIpdBase")
        }
        if let r = controls.nativeRawRoll, !finite(r) {
            throw StereoLookProducerError.nonFinite(field: "nativeRawRoll")
        }

        // pin c455d945 ll.646-651: spherical cameras compose head+manual;
        // flat shaders keep manual offsets in their own uniforms.
        let native = session.layout >= 3
        let pYaw = controls.yaw + (native ? controls.manualYaw : 0)
        let pitchLimit = deg2rad(89)
        let pPitch = min(pitchLimit, max(-pitchLimit,
                                         controls.pitch + (native ? controls.manualPitch : 0)))
        let fovMax = session.layout < 3 ? fovMaxFlatDeg : fovMaxSphericalDeg
        let pFov = deg2rad(min(fovMax, max(fovMinDeg,
                                           controls.fov + (native ? controls.manualFov : 0))))
        let pRoll: Double
        if native, let raw = controls.nativeRawRoll {
            pRoll = raw + controls.manualRoll
        } else {
            pRoll = controls.roll + controls.manualRoll
        }
        let baseToPush = controls.appliedIpdBase ?? controls.baseIpd
        // pin c455d945 l.672: vr_plain.
        let plain = (session.toolsActive && !session.enabled)
            || (session.layout < 3 && session.flatPack <= 0 && !session.flatSbs)
        // pin c455d945 l.660: vr_native_tb.
        let nativeTb = (session.layout == 4 || session.layout == 6) ? 1.0 : 0.0

        let raw: [(String, Double)] = [
            ("vr_native_tb", nativeTb),
            ("vr_cross_eye", controls.crossEye),
            ("vr_calibration", controls.calibration),
            ("vr_head_roll", pRoll),
            ("vr_source_layout", Double(session.layout)),
            ("vr_plain", plain ? 1 : 0),
            ("vr_flat_sbs", session.flatSbs ? 1 : 0),
            ("vr_flat_mono", session.flatMono ? 1 : 0),
            ("vr_d3_gain", session.d3Gain),
            ("vr_eye_aspect", geometry.eyeAspect),
            ("vr_source_x", geometry.sourceX),
            ("vr_source_y", geometry.sourceY),
            ("vr_source_w", geometry.sourceW),
            ("vr_source_h", geometry.sourceH),
            ("vr_manual_yaw", controls.manualYaw),
            ("vr_manual_pitch", controls.manualPitch),
            ("vr_manual_view", controls.manualFov),
            ("vr_yaw", pYaw),
            ("vr_pitch", pPitch),
            ("vr_fov", pFov),
            ("vr_roll", pRoll),
            ("vr_base_ipd", baseToPush),
            ("vr_ipd_nudge", controls.ipdNudge),
            ("vr_head_x", controls.headX),
            ("vr_head_y", controls.headY),
            ("vr_head_z", controls.headZ),
            ("vr_swap_eyes", controls.swapEyes),
            ("vr_parallax_strength", tune.parallaxStrength),
            ("vr_parallax_disparity", tune.parallaxDisparity),
            ("vr_pack", Double(session.flatPack)),
            ("vr_pk_conv", session.pkConv),
            ("vr_pk_zoom", session.pkZoom),
            ("vr_pk_soft", session.pkSoft),
        ]
        // Validate and quantize ALL lanes before any is returned; a
        // single overflowing composition or Float32-unrepresentable
        // value refuses the whole push typed.
        var out: [StereoLaneValue] = []
        out.reserveCapacity(raw.count)
        for (name, v) in raw {
            out.append(StereoLaneValue(name: name, value: try quantize(v, lane: name)))
        }
        return out
    }

    /// Writes the 33 lanes ATOMICALLY: a working copy of the block takes
    /// all sets and is committed only when every set succeeded - a
    /// refused or unrepresentable push leaves the caller's block
    /// bit-identical (values and revision). Returns false without ANY
    /// write when the publication gate is closed. NOTE: each accepted
    /// effective set bumps the block revision, so the final revision after one
    /// apply is the only meaningful one; same-value sets are no-ops in
    /// LookParameterBlock. Call this when produced values changed (compare laneValues output),
    /// matching the Lua's payload dedupe.
    @discardableResult
    public static func apply(to block: inout LookParameterBlock,
                             session: StereoLookSession,
                             controls: StereoLookControls,
                             geometry: StereoLookGeometry,
                             tune: StereoLookTune = StereoLookTune()) throws -> Bool {
        guard let values = try laneValues(session: session, controls: controls,
                                          geometry: geometry, tune: tune) else { return false }
        var working = block
        for lane in values {
            if case .failure = working.set(lane.name, lane.value) {
                throw StereoLookProducerError.laneRefused(name: lane.name)
            }
        }
        block = working
        return true
    }
}

/// HOST APPROXIMATION of the shader's D3_TITLE statistic (pin c455d945
/// ll.2087-2104), retained as a DIAGNOSTIC/CALIBRATION helper only.
/// Equivalence to the authority is NOT established: the GLSL hook reads
/// pipeline float color via HOOKED_tex (normalized UV, GPU filtering)
/// over MAIN, while this helper nearest-samples UInt8 upload bytes;
/// color-domain and filtering differences are unquantified. Do NOT wire
/// this as the title_r carrier: the StereoTitlePolicy
/// .noTitleSourceBound declaration stands until a real carrier proof
/// (an upload-path caller plus an equivalence witness) exists.
///
/// What the shader computes (for reference): a 1x1 SAVE texture whose
/// texel is the count, over a 5x5 grid, of cells whose Rec.709 luma
/// (0.2126/0.7152/0.0722 on 0...1 channels) is < 0.08 AND whose chroma
/// (max rgb - min rgb) is < 0.06, divided by 25; the stage then applies
/// clamp((tap-0.60)/0.20, 0, 1) itself (l.1631).
public enum StereoTitleStat {
    public enum ComponentOrder {
        case rgba
        case bgra
    }

    /// Bounds-checked nearest-byte sampling over an in-memory buffer.
    /// Returns the dark fraction in 0...1, or nil for degenerate input
    /// (nonpositive size, stride smaller than one row, buffer shorter
    /// than the strided frame). All arithmetic is overflow-checked via
    /// Int64 before any indexing.
    public static func darkFraction(_ pixels: [UInt8],
                                    width: Int, height: Int,
                                    bytesPerRow: Int,
                                    order: ComponentOrder) -> Float? {
        let w = Int64(width), h = Int64(height), stride = Int64(bytesPerRow)
        guard w > 0, h > 0, stride > 0 else { return nil }
        let (rowBytes, rowOverflow) = w.multipliedReportingOverflow(by: 4)
        guard !rowOverflow, stride >= rowBytes else { return nil }
        let (rowOffset, offsetOverflow) = (h - 1).multipliedReportingOverflow(by: stride)
        guard !offsetOverflow else { return nil }
        let (required, sizeOverflow) = rowOffset.addingReportingOverflow(rowBytes)
        guard !sizeOverflow, required <= Int64(pixels.count) else { return nil }
        let rOff: Int64, gOff: Int64, bOff: Int64
        switch order {
        case .rgba: rOff = 0; gOff = 1; bOff = 2
        case .bgra: rOff = 2; gOff = 1; bOff = 0
        }
        var dark = 0.0
        for gy in 0..<5 {
            let y = min(h - 1, Int64((Double(gy) + 0.5) / 5.0 * Double(h)))
            for gx in 0..<5 {
                let x = min(w - 1, Int64((Double(gx) + 0.5) / 5.0 * Double(w)))
                let base = Int(y * stride + x * 4)
                let r = Double(pixels[base + Int(rOff)]) / 255.0
                let g = Double(pixels[base + Int(gOff)]) / 255.0
                let b = Double(pixels[base + Int(bOff)]) / 255.0
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let chroma = max(r, max(g, b)) - min(r, min(g, b))
                if luma < 0.08 && chroma < 0.06 { dark += 1.0 / 25.0 }
            }
        }
        return Float(dark)
    }
}
