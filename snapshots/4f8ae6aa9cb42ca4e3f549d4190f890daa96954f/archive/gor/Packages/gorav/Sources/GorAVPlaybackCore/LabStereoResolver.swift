// Lab stereo/projection resolver (G0743 / 195b-B4, lab: 1nstinct), additive
// consumer seam onto the PINNED e2 vocabulary (W-gdb-048 / Types.swift sha
// 15d90863): stereoView String? in {"mono","left","right"}, projection
// String? in {"flat","vr180","equirect"}, nil = not signaled (never invented).
// The format byte parsers (Matroska StereoMode/Projection, MP4 st3d/sv3d,
// H.264 frame-packing SEI) stay in the vendored C carrier kits/b4-stereometa
// (134-check suite); this file is the vocabulary mapping + precedence chain.
//
// PINNED PRECEDENCE (W-gdb-048 over W-gdb-014): codec SEI > container side
// data > track metadata > nil. This file implements the PIN order, which
// deliberately places container side data ABOVE track metadata; the vendored
// lab C's PROPOSED order (track > container) was pre-pin and is overridden
// here. Among known values only: an unknown code never overrides a known one
// and is preserved verbatim. Eye order is never guessed: a stereo layout
// without an explicit eye cannot become "left"/"right".
//
// Mapping to the pinned vocabulary: mono layout -> "mono"; stereo layout +
// explicit eye (left/right first) -> "left"/"right" (the eye the player
// shows first); stereo layout without explicit eye -> nil + preserved row;
// projection flat -> "flat", equirect -> "equirect"; cubemap/mesh/unknown
// have no pinned word -> nil + preserved row ("vr180" is unreachable from
// the parsed formats: no parsed signal discriminates 180 vs 360).

/// Normalized stereo layout, mirror of spmeta_layout_t (order fixed).
public enum LabStereoLayout: String, Equatable, Sendable {
    case mono, sideBySide, topBottom, frameSequential, rowInterleaved,
         columnInterleaved, checkerboard, anaglyph
}

/// Explicit eye order only; absent means the format did not encode one.
public enum LabStereoEyeOrder: String, Equatable, Sendable {
    case leftFirst, rightFirst
}

/// Normalized projection, mirror of spmeta_projection_t.
public enum LabStereoProjection: String, Equatable, Sendable {
    case flat, equirect, cubemap, mesh
}

/// One source tier in the pinned precedence chain (W-gdb-048).
public enum LabStereoTier: String, Equatable, Sendable, CaseIterable {
    case codecSEI, containerSideData, trackMetadata
}

/// A preserved non-mappable signal: raw wire value + which format carried it.
public struct LabStereoUnknown: Equatable, Sendable {
    public enum Field: String, Sendable { case layout, eyeOrder, projection }
    public var tier: LabStereoTier
    public var field: Field
    public var format: String   // "mkv" | "mp4" | "h264"
    public var rawValue: UInt64
    public init(tier: LabStereoTier, field: Field, format: String, rawValue: UInt64) {
        self.tier = tier; self.field = field; self.format = format; self.rawValue = rawValue
    }
}

/// A typed conflict: two tiers both carried KNOWN values that map to
/// different pinned words; the chain winner is kept, the loser recorded.
public struct LabStereoConflict: Equatable, Sendable {
    public var field: LabStereoUnknown.Field
    public var keptTier: LabStereoTier
    public var droppedTier: LabStereoTier
    public var kept: String
    public var dropped: String
    public init(field: LabStereoUnknown.Field, keptTier: LabStereoTier, droppedTier: LabStereoTier, kept: String, dropped: String) {
        self.field = field; self.keptTier = keptTier; self.droppedTier = droppedTier
        self.kept = kept; self.dropped = dropped
    }
}

/// One tier's observation of the stereo/projection signal. Layout and eye
/// come from the SAME tier (never combined across tiers). Values already
/// normalized by the (vendored C) parsers; rawUnknown covers preserved codes.
public struct LabStereoObservation: Equatable, Sendable {
    public var layout: LabStereoLayout?
    public var eyeOrder: LabStereoEyeOrder?
    public var projection: LabStereoProjection?
    public var unknowns: [LabStereoUnknown] = []
    public init(layout: LabStereoLayout? = nil, eyeOrder: LabStereoEyeOrder? = nil,
                projection: LabStereoProjection? = nil, unknowns: [LabStereoUnknown] = []) {
        self.layout = layout; self.eyeOrder = eyeOrder
        self.projection = projection; self.unknowns = unknowns
    }
}

/// Resolved pinned fields plus the typed audit trail.
public struct LabStereoResolution: Equatable, Sendable {
    public var stereoView: String?      // pinned: "mono" | "left" | "right" | nil
    public var projection: String?      // pinned: "flat" | "vr180" | "equirect" | nil
    public var conflicts: [LabStereoConflict] = []
    public var unknowns: [LabStereoUnknown] = []
    public init() {}
}

public enum LabStereoResolver {
    /// Pinned precedence: codecSEI > containerSideData > trackMetadata.
    private static let order: [LabStereoTier] = [.codecSEI, .containerSideData, .trackMetadata]

    /// Map one tier's known layout+eye to the pinned stereoView word.
    /// nil when unmappable (stereo without explicit eye is never guessed).
    static func stereoViewWord(layout: LabStereoLayout, eye: LabStereoEyeOrder?) -> String? {
        switch layout {
        case .mono: return "mono"
        default:
            switch eye {
            case .leftFirst: return "left"
            case .rightFirst: return "right"
            case nil: return nil
            }
        }
    }

    static func projectionWord(_ p: LabStereoProjection) -> String? {
        switch p {
        case .flat: return "flat"
        case .equirect: return "equirect"
        case .cubemap, .mesh: return nil
        }
    }

    /// Resolve observations per tier into the pinned fields. The first tier
    /// (in pinned order) with a MAPPABLE known value wins the field; other
    /// tiers' known values that map differently become typed conflict rows;
    /// unmappable knowns and unknowns are preserved, never dropped.
    public static func resolve(_ obs: [LabStereoTier: LabStereoObservation]) -> LabStereoResolution {
        var res = LabStereoResolution()

        // stereoView field (layout+eye, same tier only)
        var svWinner: (tier: LabStereoTier, word: String)?
        for tier in order {
            guard let o = obs[tier], let lay = o.layout else { continue }
            guard let word = stereoViewWord(layout: lay, eye: o.eyeOrder) else {
                res.unknowns.append(LabStereoUnknown(tier: tier, field: .eyeOrder,
                                                     format: "normalized", rawValue: 0))
                continue
            }
            if let w = svWinner {
                if w.word != word {
                    res.conflicts.append(LabStereoConflict(field: .layout, keptTier: w.tier,
                                                           droppedTier: tier, kept: w.word, dropped: word))
                }
            } else {
                svWinner = (tier, word)
            }
        }
        res.stereoView = svWinner?.word

        // projection field
        var pjWinner: (tier: LabStereoTier, word: String)?
        for tier in order {
            guard let o = obs[tier], let p = o.projection else { continue }
            guard let word = projectionWord(p) else {
                res.unknowns.append(LabStereoUnknown(tier: tier, field: .projection,
                                                     format: "normalized", rawValue: 0))
                continue
            }
            if let w = pjWinner {
                if w.word != word {
                    res.conflicts.append(LabStereoConflict(field: .projection, keptTier: w.tier,
                                                           droppedTier: tier, kept: w.word, dropped: word))
                }
            } else {
                pjWinner = (tier, word)
            }
        }
        res.projection = pjWinner?.word

        for tier in order { res.unknowns.append(contentsOf: obs[tier]?.unknowns ?? []) }
        return res
    }
}
