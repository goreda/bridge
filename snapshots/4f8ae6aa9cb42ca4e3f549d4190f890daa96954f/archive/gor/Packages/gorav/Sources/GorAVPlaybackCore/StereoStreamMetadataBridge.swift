import Foundation

// B4-STEREO-META selected-stream bridge (lane: stereo/photon): the
// additive seam from the host's SELECTED video stream to
// LabStereoMetaFeed in the vendored isolated package (which has no
// spmeta parser). The host demux owns container parsing and stream
// selection; this bridge owns:
//  - an explicit, typed selection boundary (no stream is ever inferred;
//    both identifiers absent is a typed refusal, never a guess);
//  - the spmeta.h per-source slot model on the Swift side: one
//    observation per source slot per field, INCLUDING the codec slot's
//    temporal SEI semantics (a later SEI REPLACES the codec
//    observation; a cancel CLEARS it - spmeta.h header contract);
//  - wire-ordinal validation at the boundary (kind 0...2, source 1...4,
//    format 1...3), with every UNKNOWN wire code preserved verbatim.
// It NEVER derives the 180/360 discrimination or any session layout int
// (session authority supplies that), NEVER reduces observations to a
// resolved winner (the resolver's pinned precedence decides), and NEVER
// folds OVERRIDE-source records into tiers (preserved verbatim by the
// feed). INERT: nothing at head calls this bridge yet; session-start
// detection and App registration are owned elsewhere (Ops).

/// The host's explicit selected video stream. At least one identifier
/// must be present; the bridge refuses an empty selection typed rather
/// than guessing a stream.
public struct StereoSelectedStream: Equatable {
    /// Container track index as the host demux reports it (Matroska
    /// TrackEntry order / MP4 track), when the host has one.
    public let track: Int?
    /// Host-level stream identifier, when the host has one.
    public let stream: Int?
    public init(track: Int?, stream: Int?) {
        self.track = track; self.stream = stream
    }
}

public enum StereoStreamMetadataError: Error, Equatable {
    /// Both selection identifiers were absent: no stream can be named.
    case noSelection
    /// A wire ordinal outside the spmeta.h ranges reached the boundary
    /// (kind 0...2, source 1...4, format 1...3).
    case invalidOrdinal(field: String, value: Int)
    /// A codec-SEI event carried a non-codec source; the slot was NOT
    /// mutated.
    case codecSEISourceExpected(Int)
}

/// One field's per-source slot observations plus the temporal codec
/// (SEI) slot semantics. Mirrors spmeta.h: H.264 SEI is temporal
/// metadata - a later SEI REPLACES the codec-source observation and a
/// cancel flag CLEARS it; other sources' slots are unaffected.
public struct StereoStreamFieldMetadata: Equatable {
    public private(set) var observations: [SpmetaFieldObs]
    public init(observations: [SpmetaFieldObs]) {
        self.observations = observations
    }

    /// Applies one codec-SEI event for this field. A non-nil
    /// observation REPLACES the codec slot; nil CANCELS it (the slot
    /// returns to UNSET and contributes nothing further). The event is
    /// validated BEFORE the slot mutates: a non-codec source or an
    /// out-of-range kind/format ordinal refuses typed and the existing
    /// slot is preserved whole (atomic validate-then-mutate). Non-codec
    /// slots are never touched here.
    public mutating func applyCodecSEI(_ observation: SpmetaFieldObs?) throws {
        if let observation {
            guard observation.source == 3 else {
                throw StereoStreamMetadataError.codecSEISourceExpected(observation.source)
            }
            guard (0...2).contains(observation.kind) else {
                throw StereoStreamMetadataError.invalidOrdinal(field: "codecSEI.kind",
                                                               value: observation.kind)
            }
            guard (1...3).contains(observation.format) else {
                throw StereoStreamMetadataError.invalidOrdinal(field: "codecSEI.format",
                                                               value: observation.format)
            }
        }
        observations.removeAll { $0.source == 3 }
        if let observation { observations.append(observation) }
    }
}

/// The selected stream's stereo metadata observations, grouped per
/// field exactly as spmeta_t's per-field source-slot arrays. Container
/// defaults and overrides arrive as ordinary slot records (source 1 and
/// 4 respectively), matching spmeta_set_explicit.
public struct StereoStreamMetadata: Equatable {
    public var layout: StereoStreamFieldMetadata
    public var eyeOrder: StereoStreamFieldMetadata
    public var projection: StereoStreamFieldMetadata
    public init(layout: StereoStreamFieldMetadata = StereoStreamFieldMetadata(observations: []),
                eyeOrder: StereoStreamFieldMetadata = StereoStreamFieldMetadata(observations: []),
                projection: StereoStreamFieldMetadata = StereoStreamFieldMetadata(observations: [])) {
        self.layout = layout; self.eyeOrder = eyeOrder; self.projection = projection
    }
}

public enum StereoStreamMetadataBridge {
    private static func validate(_ obs: SpmetaFieldObs, field: String) throws {
        guard (0...2).contains(obs.kind) else {
            throw StereoStreamMetadataError.invalidOrdinal(field: field + ".kind", value: obs.kind)
        }
        guard (1...4).contains(obs.source) else {
            throw StereoStreamMetadataError.invalidOrdinal(field: field + ".source", value: obs.source)
        }
        guard (1...3).contains(obs.format) else {
            throw StereoStreamMetadataError.invalidOrdinal(field: field + ".format", value: obs.format)
        }
    }

    /// The one typed entry from selected-stream metadata to the
    /// resolver's input vocabulary. Requires an explicit selection;
    /// validates every wire ordinal; then defers ENTIRELY to
    /// LabStereoMetaFeed (tier grouping, duplicate-KNOWN preservation,
    /// OVERRIDE passthrough). The result carries no session layout int
    /// and no resolved winner.
    public static func feed(selection: StereoSelectedStream,
                            metadata: StereoStreamMetadata) throws -> LabStereoFeedResult {
        guard selection.track != nil || selection.stream != nil else {
            throw StereoStreamMetadataError.noSelection
        }
        for obs in metadata.layout.observations { try validate(obs, field: "layout") }
        for obs in metadata.eyeOrder.observations { try validate(obs, field: "eyeOrder") }
        for obs in metadata.projection.observations { try validate(obs, field: "projection") }
        return LabStereoMetaFeed.feed(layout: metadata.layout.observations,
                                      eyeOrder: metadata.eyeOrder.observations,
                                      projection: metadata.projection.observations)
    }
}
