import Foundation

// B5-STEREO-META transport (lane: stereo/photon), revision 2 (Z4C
// independent boundary evidence 096ac943: stale-context mutation,
// epoch regression, unvalidated rebind repaired): selected-stream
// codec/container observation transport with CONTEXT-BOUND admission,
// monotonic presentation-epoch invalidation and validated atomic
// rebind. Additive on the qualified v4 composition; no qualified byte
// changes - this file uses only the public surface of the qualified
// StereoStreamMetadataBridge / StereoStreamFieldMetadata /
// StereoStreamMetadata / LabStereoMetaFeed types.
//
// Contract (all pinned, none invented):
//  - BINDING CONTEXT: the host keys the transport with an explicit
//    StereoMetadataBindingContext. The field mapping to the presenter
//    route's identity currency is fixed at the type documentation and
//    nowhere else; the transport never mints, projects or infers an
//    identity.
//  - CONTEXTUAL ADMISSION: EVERY mutation carries the full context the
//    caller believes is current - INCLUDING the exact selected stream.
//    A mismatch (delayed callback from an older source, generation,
//    epoch or selection) refuses typed .staleContext BEFORE any payload
//    validation, and nothing mutates. Admission is full-context
//    equality, never a source-ID prefix or an epoch-only comparison.
//  - SELECTION: the selected-stream identity is part of the binding
//    context, so stored observations can never be relabelled onto a
//    different track. The selection is validated NON-EMPTY at rebind
//    (nil track + nil stream names no stream) and compared with FULL
//    exact equality at every mutation and at feed - nil and 0 are
//    different identifiers. No selection is ever inferred or defaulted;
//    a selection change is a rebind (validated, full replace).
//  - SOURCE REBIND: rebindSource is validated-then-committed ATOMICALLY:
//    an empty sourceID or any out-of-contract track observation (source
//    must be TRACK(2); kind 0...2; format 1...3) refuses typed and the
//    PREVIOUS binding and all its slots remain whole. On success ALL
//    slot state is replaced by the fresh container parse; track
//    observations (source 2) enter ONLY here - the transport never
//    parses wire bytes itself.
//  - EPOCH MONOTONICITY: advanceEpoch accepts only a strictly greater
//    presentation epoch; a regression refuses typed
//    .epochRegression and mutates nothing. Advancing to the CURRENT
//    epoch is a no-op (live SEI state kept). A successful advance
//    clears ONLY the codec (SEI) slots: H.264 SEI is temporal metadata
//    (spmeta.h header contract), so SEI observed under an older
//    presentation epoch must not survive a seek. Container defaults,
//    track observations and overrides are not temporal and persist.
//  - REPLACE/CANCEL: container defaults and explicit overrides mirror
//    spmeta_set_explicit (spmeta.h): source must be CONTAINER(1) or
//    OVERRIDE(4); a nil observation CLEARS that source's slot for the
//    field, a non-nil observation REPLACES it. Validation precedes every
//    mutation; a refusal leaves the slots whole (validate-then-mutate).
//  - Codec SEI events delegate to the qualified per-field applyCodecSEI:
//    a later SEI REPLACES the codec slot, a cancel CLEARS it, a
//    non-codec source or bad ordinal refuses typed without mutating.
//  - NO 180/360 INFERENCE: the transport carries observations only. The
//    session layout int stays with session authority; nothing here
//    derives a layout from dimensions, projection or any other field.
//  - No resolved winner is computed here (tier grouping is the qualified
//    feed's); OVERRIDE records are preserved verbatim and never folded
//    into tiers.
//  - The runtime-owner publication/activation gate is untouched: this
//    transport never publishes, acknowledges or activates anything.
//
// INERT until Ops composes the host wiring. Demux parsing, stream
// selection and App registration are owned elsewhere (Ops).

/// Explicit binding between the transport and the presenter route's
/// identity currency. Every field is host-supplied; the mapping is:
///   sourceID         <- VRRuntimeBinding.sourceID
///                       (== ProjectionSourceBinding.sourceID)
///   sourceGeneration <- VRRuntimeBinding.sourceGeneration
///                       (== ProjectionSourceBinding.nativeGeneration)
///   presentationEpoch <- NativeStereoMedia.presentationEpoch
/// ownerRevision is deliberately NOT carried: owner revisions belong to
/// the runtime owner, never to metadata transport state.
public struct StereoMetadataBindingContext: Equatable {
    public let sourceID: String
    public let sourceGeneration: UInt64
    public let presentationEpoch: UInt64
    /// The exact selected stream these observations belong to. Compared
    /// with full equality (nil and 0 are different identifiers); never
    /// inferred or defaulted.
    public let selection: StereoSelectedStream
    public init(sourceID: String, sourceGeneration: UInt64, presentationEpoch: UInt64,
                selection: StereoSelectedStream) {
        self.sourceID = sourceID; self.sourceGeneration = sourceGeneration
        self.presentationEpoch = presentationEpoch
        self.selection = selection
    }
}

/// spmeta field selector (ordinals are spmeta_field_id_t; do not
/// renumber).
public enum StereoMetadataField: Int, Equatable, Hashable, CaseIterable {
    case layout = 0, eyeOrder = 1, projection = 2
}

public enum StereoMetadataTransportError: Error, Equatable {
    /// No source is bound: observations and feed require rebindSource.
    case unbound
    /// The caller's expected context is not the bound context: a delayed
    /// event from an older source, generation or epoch. Nothing mutated.
    case staleContext
    /// A presentation-epoch advance must be strictly greater.
    case epochRegression(current: UInt64, requested: UInt64)
    /// A rebind carried an empty sourceID: no source can be named.
    case emptySourceID
    /// A rebind carried a selection with both identifiers absent: no
    /// stream can be named.
    case emptySelection
    /// A feed named a different selection than the bound context.
    case selectionMismatch
    /// A rebind track parse carried a non-track source slot.
    case trackSourceExpected(Int)
    /// spmeta_set_explicit accepts CONTAINER(1) and OVERRIDE(4) only.
    case explicitSourceExpected(Int)
    /// The observation's own source does not match the addressed slot.
    case sourceMismatch(slot: Int, observation: Int)
    /// A wire ordinal outside the spmeta.h ranges reached the boundary.
    case invalidOrdinal(field: String, value: Int)
}

public final class StereoStreamMetadataTransport {
    /// The bound source/epoch context; nil until rebindSource.
    public private(set) var context: StereoMetadataBindingContext?
    private var fields: [StereoMetadataField: StereoStreamFieldMetadata] = [
        .layout: StereoStreamFieldMetadata(observations: []),
        .eyeOrder: StereoStreamFieldMetadata(observations: []),
        .projection: StereoStreamFieldMetadata(observations: []),
    ]

    public init() {}

    /// Contextual admission shared by every mutation: full-context
    /// equality, checked BEFORE any payload validation.
    private func requireContext(_ expected: StereoMetadataBindingContext) throws {
        guard let current = context else { throw StereoMetadataTransportError.unbound }
        guard current == expected else { throw StereoMetadataTransportError.staleContext }
    }

    /// Validates a rebind's context and track parse WITHOUT touching
    /// state. Track slots must be exactly source TRACK(2) with in-range
    /// ordinals; the sourceID must name a source.
    private static func validateRebind(context: StereoMetadataBindingContext,
                                       track: StereoStreamMetadata) throws {
        guard !context.sourceID.isEmpty else {
            throw StereoMetadataTransportError.emptySourceID
        }
        guard context.selection.track != nil || context.selection.stream != nil else {
            throw StereoMetadataTransportError.emptySelection
        }
        let grouped: [(StereoMetadataField, StereoStreamFieldMetadata)] = [
            (.layout, track.layout), (.eyeOrder, track.eyeOrder), (.projection, track.projection),
        ]
        for (field, fm) in grouped {
            for obs in fm.observations {
                guard obs.source == 2 else {
                    throw StereoMetadataTransportError.trackSourceExpected(obs.source)
                }
                guard (0...2).contains(obs.kind) else {
                    throw StereoMetadataTransportError.invalidOrdinal(field: "\(field).kind",
                                                                      value: obs.kind)
                }
                guard (1...3).contains(obs.format) else {
                    throw StereoMetadataTransportError.invalidOrdinal(field: "\(field).format",
                                                                      value: obs.format)
                }
            }
        }
    }

    /// Source/stream change or first bind: validated, then ALL slot
    /// state is replaced by the fresh container parse in ONE commit.
    /// A refusal leaves the previous binding and every slot whole.
    /// The same context re-bound also fully replaces: a rebind is never
    /// merged with prior state.
    public func rebindSource(to context: StereoMetadataBindingContext,
                             track: StereoStreamMetadata = StereoStreamMetadata()) throws {
        try Self.validateRebind(context: context, track: track)
        self.context = context
        fields[.layout] = track.layout
        fields[.eyeOrder] = track.eyeOrder
        fields[.projection] = track.projection
    }

    /// Presentation-epoch advance inside the bound source: strictly
    /// greater epochs only. Codec (SEI) slots clear on a successful
    /// advance (temporal metadata); container, track and override slots
    /// persist. Advancing to the current epoch is a no-op; a regression
    /// refuses typed and mutates nothing.
    public func advanceEpoch(context expected: StereoMetadataBindingContext,
                             to presentationEpoch: UInt64) throws {
        try requireContext(expected)
        guard presentationEpoch != expected.presentationEpoch else { return }
        guard presentationEpoch > expected.presentationEpoch else {
            throw StereoMetadataTransportError.epochRegression(
                current: expected.presentationEpoch, requested: presentationEpoch)
        }
        context = StereoMetadataBindingContext(
            sourceID: expected.sourceID,
            sourceGeneration: expected.sourceGeneration,
            presentationEpoch: presentationEpoch,
            selection: expected.selection)
        for field in StereoMetadataField.allCases {
            guard let current = fields[field] else { continue }
            fields[field] = StereoStreamFieldMetadata(
                observations: current.observations.filter { $0.source != 3 })
        }
    }

    /// Retire/teardown: unbind and clear all slot state.
    public func reset() {
        context = nil
        for field in StereoMetadataField.allCases {
            fields[field] = StereoStreamFieldMetadata(observations: [])
        }
    }

    /// One codec-SEI event for one field, admitted under full-context
    /// equality, then delegated to the qualified per-field contract
    /// (later SEI replaces, cancel clears, typed refusal leaves the slot
    /// whole). Requires a bound, matching source context.
    public func applyCodecSEI(context expected: StereoMetadataBindingContext,
                              field: StereoMetadataField,
                              observation: SpmetaFieldObs?) throws {
        try requireContext(expected)
        guard var current = fields[field] else { return }
        try current.applyCodecSEI(observation)
        fields[field] = current
    }

    /// Container default or explicit override, mirroring
    /// spmeta_set_explicit: `source` must be CONTAINER(1) or OVERRIDE(4);
    /// a nil observation CLEARS that source's slot for the field, a
    /// non-nil observation REPLACES it (and must carry the same source).
    /// Context admission precedes validation; validation precedes any
    /// mutation; a refusal leaves the slot whole.
    public func applyExplicit(context expected: StereoMetadataBindingContext,
                              source: Int, field: StereoMetadataField,
                              observation: SpmetaFieldObs?) throws {
        try requireContext(expected)
        guard source == 1 || source == 4 else {
            throw StereoMetadataTransportError.explicitSourceExpected(source)
        }
        if let observation {
            guard observation.source == source else {
                throw StereoMetadataTransportError.sourceMismatch(slot: source,
                                                                  observation: observation.source)
            }
            guard (0...2).contains(observation.kind) else {
                throw StereoMetadataTransportError.invalidOrdinal(field: "\(field).kind",
                                                                  value: observation.kind)
            }
            guard (1...3).contains(observation.format) else {
                throw StereoMetadataTransportError.invalidOrdinal(field: "\(field).format",
                                                                  value: observation.format)
            }
        }
        guard let current = fields[field] else { return }
        var observations = current.observations.filter { $0.source != source }
        if let observation { observations.append(observation) }
        fields[field] = StereoStreamFieldMetadata(observations: observations)
    }

    /// Current slot observations for one field (read-only snapshot).
    public func observations(_ field: StereoMetadataField) -> [SpmetaFieldObs] {
        fields[field]?.observations ?? []
    }

    /// Typed entry to the resolver's input vocabulary through the
    /// qualified selected-stream bridge. Requires a bound source AND an
    /// explicit selection; carries no session layout int and no resolved
    /// winner.
    public func feed(selection: StereoSelectedStream) throws -> LabStereoFeedResult {
        guard let context = self.context else { throw StereoMetadataTransportError.unbound }
        guard selection == context.selection else {
            throw StereoMetadataTransportError.selectionMismatch
        }
        let metadata = StereoStreamMetadata(
            layout: fields[.layout] ?? StereoStreamFieldMetadata(observations: []),
            eyeOrder: fields[.eyeOrder] ?? StereoStreamFieldMetadata(observations: []),
            projection: fields[.projection] ?? StereoStreamFieldMetadata(observations: []))
        return try StereoStreamMetadataBridge.feed(selection: selection, metadata: metadata)
    }
}
