import Foundation

// B4-STEREO-META Swift feed v2 (lane: stereo/photon): maps the vendored C
// carrier's per-source observation SLOTS (kits/b4-stereometa/spmeta.h,
// spmeta_t: layout[5]/eye[5]/proj[5] - one observation per source slot
// per field; a later codec SEI replaces the slot, a cancel clears it)
// onto LabStereoResolver's input vocabulary WITHOUT layout loss:
//  - every KNOWN value maps to its pinned enum;
//  - every UNKNOWN wire code is preserved verbatim (raw + format);
//  - observations stay grouped BY TIER (layout and eye of one tier in
//    one observation - the resolver never combines them across tiers);
//  - the resolver's own pinned precedence (codecSEI > containerSideData
//    > trackMetadata, W-gdb-048) decides; the feed NEVER reduces to the
//    C side's resolved winner and never applies the C PROPOSED
//    OVERRIDE>CODEC>TRACK>CONTAINER tail (b4 README).
// The container parsing itself stays in the kit (b4 scope); the demux
// plumbing that fills the slots is integrator-side (spmeta.h ABI
// PROPOSED, integrator pin pending). This file is the normalized-enum
// consumer seam: pure, value-typed.
//
// INERT wiring note: nothing at head calls this feed yet. Session-start
// detection and any App registration are owned elsewhere (Ops).

/// One field observation in one source slot, mirroring spmeta_obs_t
/// (ordinals are the C enum values; do not renumber).
public struct SpmetaFieldObs: Equatable {
    /// spmeta_value_kind_t: 0 UNSET, 1 KNOWN, 2 UNKNOWN.
    public let kind: Int
    /// Normalized enum value when kind == KNOWN (spmeta_layout_t /
    /// spmeta_eye_order_t / spmeta_projection_t ordinal).
    public let norm: Int
    /// Wire code when kind == UNKNOWN.
    public let raw: UInt32
    /// spmeta_source_t: 1 CONTAINER, 2 TRACK, 3 CODEC, 4 OVERRIDE.
    public let source: Int
    /// spmeta_format_t: 1 MKV, 2 MP4, 3 H264.
    public let format: Int
    public init(kind: Int, norm: Int, raw: UInt32, source: Int, format: Int) {
        self.kind = kind; self.norm = norm; self.raw = raw
        self.source = source; self.format = format
    }
}

/// An OVERRIDE-source observation. The resolver has NO override tier
/// (pinned vocabulary is exactly codecSEI/containerSideData/
/// trackMetadata); override records are preserved verbatim here and
/// NEVER folded into the tier map. Folding or dropping them silently
/// would both lose information; whoever owns the resolver pin decides
/// their semantics.
public struct SpmetaOverrideRecord: Equatable {
    public let field: LabStereoUnknown.Field
    public let knownNorm: Int?
    public let raw: UInt32?
    public let format: Int
}

public struct LabStereoFeedResult: Equatable {
    /// Per-tier observations, grouped by the tier each slot's source
    /// maps to. Layout and eye stay within their own tier's observation.
    public var observations: [LabStereoTier: LabStereoObservation] = [:]
    /// OVERRIDE-source records, preserved verbatim (never folded).
    public var overrides: [SpmetaOverrideRecord] = []
    public init() {}
}

public enum LabStereoMetaFeed {
    /// Merge ALL per-source slot observations of all three fields
    /// (mirrors spmeta_t's per-field source-slot arrays; pass every
    /// occupied slot, UNSET slots may be omitted or passed with kind 0 -
    /// they contribute nothing). Slot uniqueness is the C handle's
    /// invariant (one observation per source slot per field); a
    /// duplicate KNOWN for the same tier+field is NOT overwritten - the
    /// first keeps the enum slot and the rest are preserved as unknown
    /// rows so no signal is ever silently replaced.
    public static func feed(layout: [SpmetaFieldObs],
                            eyeOrder: [SpmetaFieldObs],
                            projection: [SpmetaFieldObs]) -> LabStereoFeedResult {
        var result = LabStereoFeedResult()
        for obs in layout { apply(obs, field: .layout, into: &result) }
        for obs in eyeOrder { apply(obs, field: .eyeOrder, into: &result) }
        for obs in projection { apply(obs, field: .projection, into: &result) }
        return result
    }

    private static func apply(_ obs: SpmetaFieldObs,
                              field: LabStereoUnknown.Field,
                              into result: inout LabStereoFeedResult) {
        guard obs.kind != 0 else { return } // UNSET slot
        if obs.source == 4 { // OVERRIDE: preserved, never folded
            result.overrides.append(SpmetaOverrideRecord(
                field: field,
                knownNorm: obs.kind == 1 ? obs.norm : nil,
                raw: obs.kind == 2 ? obs.raw : nil,
                format: obs.format))
            return
        }
        guard let tier = tier(for: obs.source) else { return } // NONE/out-of-range source
        var observation = result.observations[tier] ?? LabStereoObservation()
        let format = formatWord(obs.format)
        let preserve: (UInt64) -> Void = { rawValue in
            observation.unknowns.append(LabStereoUnknown(tier: tier, field: field,
                                                         format: format, rawValue: rawValue))
        }
        switch obs.kind {
        case 2: // UNKNOWN wire code: preserve verbatim
            preserve(UInt64(obs.raw))
        case 1:
            switch field {
            case .layout:
                if let v = layoutEnum(obs.norm), observation.layout == nil {
                    observation.layout = v
                } else {
                    preserve(UInt64(bitPattern: Int64(obs.norm)))
                }
            case .eyeOrder:
                if let v = eyeEnum(obs.norm), observation.eyeOrder == nil {
                    observation.eyeOrder = v
                } else {
                    preserve(UInt64(bitPattern: Int64(obs.norm)))
                }
            case .projection:
                if let v = projectionEnum(obs.norm), observation.projection == nil {
                    observation.projection = v
                } else {
                    preserve(UInt64(bitPattern: Int64(obs.norm)))
                }
            }
        default:
            return
        }
        result.observations[tier] = observation
    }

    /// spmeta_source_t -> pinned resolver tier. OVERRIDE (4) is handled
    /// by the caller before this; NONE/out-of-range map to nil.
    private static func tier(for source: Int) -> LabStereoTier? {
        switch source {
        case 1: return .containerSideData
        case 2: return .trackMetadata
        case 3: return .codecSEI
        default: return nil
        }
    }

    private static func formatWord(_ format: Int) -> String {
        switch format {
        case 1: return "mkv"
        case 2: return "mp4"
        case 3: return "h264"
        default: return "unknown"
        }
    }

    /// spmeta_layout_t (ordinals fixed by spmeta.h; do not renumber).
    private static func layoutEnum(_ norm: Int) -> LabStereoLayout? {
        switch norm {
        case 1: return .mono
        case 2: return .sideBySide
        case 3: return .topBottom
        case 4: return .frameSequential
        case 5: return .rowInterleaved
        case 6: return .columnInterleaved
        case 7: return .checkerboard
        case 8: return .anaglyph
        default: return nil
        }
    }

    /// spmeta_eye_order_t.
    private static func eyeEnum(_ norm: Int) -> LabStereoEyeOrder? {
        switch norm {
        case 1: return .leftFirst
        case 2: return .rightFirst
        default: return nil
        }
    }

    /// spmeta_projection_t.
    private static func projectionEnum(_ norm: Int) -> LabStereoProjection? {
        switch norm {
        case 1: return .flat
        case 2: return .equirect
        case 3: return .cubemap
        case 4: return .mesh
        default: return nil
        }
    }
}
