// Picture/ExportColour.swift: merged with ExportExpectedLegsConsumer.swift (pure move)

import Foundation
import GorAVCore

// MARK: - ExportColour
// Picture/ExportColour.swift
// Uses: ExportSource, PhotonLookSnapshot, RendererHandoffBinding, ColorPlan, EncodeModel (TransferKind, MasterDisplay, PhotonLook, RenderIdentity)
// Engine: none
// Merged (199ee, pure concatenation, bodies unchanged) from: ExportColorWiring.swift, ExportColourEvidence.swift, ExportRenderReceiptEvidence.swift

// ===== BEGIN merged ExportColorWiring.swift =====
// Picture/ExportColorWiring.swift
// Consumer wiring for ColorPlan: derives the probed signal metadata from ExportSource and the render handoff from the validated PhotonLookSnapshot plus the render stage's runtime statement, binds them, and plans the colour policy.
// Uses: ExportSource, PhotonLookSnapshot, RendererHandoffBinding, ColorPlan, EncodeModel (TransferKind, MasterDisplay, PhotonLook, RenderIdentity)
// Engine: none

/// The render stage's runtime statement at export time. PhotonLookSnapshot carries the frozen
/// look; it does NOT carry how the frames were actually rendered, so the render stage states
/// these at the call site. The wiring never invents them.
public struct RenderStatement: Equatable {
    public var renderPath: RenderPath
    /// Explicit transfer intent of the render. Nil = the render stage makes no statement.
    public var transferIntent: TransferKind?
    public var framesBakedAsSeen: Bool
    public var colorPreservationValidated: Bool
    public var pixelsModifiedByLook: Bool
    public var gamutRemappedByLook: Bool

    public init(renderPath: RenderPath, transferIntent: TransferKind?, framesBakedAsSeen: Bool,
                colorPreservationValidated: Bool, pixelsModifiedByLook: Bool, gamutRemappedByLook: Bool = false) {
        self.renderPath = renderPath; self.transferIntent = transferIntent
        self.framesBakedAsSeen = framesBakedAsSeen
        self.colorPreservationValidated = colorPreservationValidated
        self.pixelsModifiedByLook = pixelsModifiedByLook
        self.gamutRemappedByLook = gamutRemappedByLook
    }
}

public enum ExportColorWiring {
    /// Vocabulary adapters between the Picture probe types and BUILD's EncodeModel types.
    /// Mechanical 1:1 mappings; nothing is inferred and nothing is defaulted here.
    public static func transfer(_ t: ExportTransfer) -> TransferKind {
        switch t { case .sdr: return .sdr; case .pq: return .pq; case .hlg: return .hlg }
    }
    public static func masterDisplay(_ md: ExportMasterDisplay) -> MasterDisplay {
        MasterDisplay(gx: md.gx, gy: md.gy, bx: md.bx, by: md.by, rx: md.rx, ry: md.ry,
                      wpx: md.wpx, wpy: md.wpy, lumaMax: md.lumaMax, lumaMin: md.lumaMin)
    }
    public static func look(_ s: PhotonLookSnapshot) throws -> PhotonLook {
        try PhotonLook(scripts: s.scripts, properties: s.properties,
                       renderIdentity: RenderIdentity(mpvBuild: s.renderIdentity.mpvBuild,
                                                      providerLockSHA256: s.renderIdentity.providerLockSHA256,
                                                      scriptHashes: s.renderIdentity.scriptHashes))
    }

    /// The probe metadata the current ExportSource vocabulary can actually state.
    /// KNOWN GAPS (refused downstream, never papered over):
    /// - ExportSource carries no primaries/matrix/range fields: they stay nil and the planner
    ///   refuses unknownSignalField unless a proven contract is supplied by the caller.
    /// - ExportSource.transfer is non-optional and defaults to SDR: an unreadable transfer is
    ///   indistinguishable from a real SDR probe. `transferIsProbed` is the caller's proof that
    ///   the value was actually read; false maps to nil (typed unknown), never to the default.
    /// - measuredMaxCLL/MaxFALL carry no measurement identity or coverage: they cannot become
    ///   MeasuredLightStatistics (that would fabricate an identity) and are not carried.
    /// Probe from the decoded read (mpv video-dec-params under the load-generation fence), never
    /// from ExportSource's bare fields: its transfer is a non-optional .sdr default and it has no
    /// primaries/matrix/range at all (G1/G2). An unread or unrecognised field is a typed unknown.
    public static func probe(from s: ExportSource, decoded: ExportDecodedSignal?,
                             contract: ProvenSignalContract? = nil) -> ProbedSignalMetadata {
        ProbedSignalMetadata(
            primaries: decoded?.primaries.flatMap(ExportColourEvidence.primaries),
            transfer: decoded?.sourceTag != nil ? { if case .kind(let k) = ExportColourEvidence.transferVerdict(sourceTag: decoded?.sourceTag, mpvTRC: decoded?.transfer) { return k }; return nil }() : decoded?.transfer.flatMap(ExportColourEvidence.transferKind),
            matrix: decoded?.matrix.flatMap(ExportColourEvidence.matrix),
            range: decoded?.range.flatMap(ExportColourEvidence.range),
            frameBitDepth: s.frameBitDepth,
            provenContract: contract,
            masteringDisplay: s.masterDisplay.map(masterDisplay),
            lightStatistics: nil,
            dynamicMetadata: DynamicMetadata(dolbyVision: nil, hdr10Plus: s.hasHDR10Plus))
    }

    /// The full consumer path: probe + render statement -> bound handoff -> colour plan.
    /// Refuses with the planner's typed refusals; nothing is caught or softened here.
    /// `measured` is the only accepted source of output light statistics (whole-output
    /// measurement with identity); ExportSource's fields never feed it (see probe gaps).
    public static func planColor(source: ExportSource, snapshot: PhotonLookSnapshot,
                                 render: RenderStatement, codec: Codec,
                                 decoded: ExportDecodedSignal?,
                                 contract: ProvenSignalContract? = nil,
                                 measured: MeasuredLightStatistics? = nil) throws -> ColorPlan {
        let p = probe(from: source, decoded: decoded, contract: contract)
        let state = RenderHandoffState(
            look: try look(snapshot), sourceEpoch: "\(source.path)@\(source.mtimeNs)",
            renderPath: render.renderPath, transferIntent: render.transferIntent,
            framesBakedAsSeen: render.framesBakedAsSeen,
            colorPreservationValidated: render.colorPreservationValidated,
            pixelsModifiedByLook: render.pixelsModifiedByLook,
            gamutRemappedByLook: render.gamutRemappedByLook)
        let bound = try RendererHandoffBinding.bind(probe: p, render: state)
        return try ColorPlan.plan(
            codec: codec, frames: bound.frames, evidence: bound.evidence,
            contract: RenderContract(framesAlreadyToneMapped: true,
                                     encoderToneMappingRequested: false,
                                     requestedOutputSignal: nil),
            measured: measured)
    }
}
// ===== END merged ExportColorWiring.swift =====

// ===== BEGIN merged ExportColourEvidence.swift =====
// Picture/ExportColourEvidence.swift
// Render + probe evidence the adapter supplies for the colour plan, captured under the same
// load-generation fence as the look snapshot. Every field the app cannot prove is nil, and nil
// maps to the strict branch, never to a claim: unknown gamut/px modification blocks source-metadata
// retention (ColorPlan.swift:620-628 retention requires gamutRemappedByLook == false; :655-658
// source-light retention requires pixelsModifiedByLook == false), unknown frames-baked or render
// path is a missing input, and validation is asserted only when explicitly true. A non-empty
// script list is processing presence, not pixel-modification proof; a producer colour statement is
// not a frames-baked proof until the renderer/look binding is verified; a displayReferredSDR route
// qualification is a route-class fact and never asserts a per-job render gate.
// Uses: ExportSnapshotAdapter
// Engine: none

public struct ExportDecodedSignal: Equatable {
    /// mpv video-dec-params colour fields as read for THIS load generation; nil = not read. Raw
    /// strings: mapping to the typed vocabulary happens in one place and an unrecognised value is
    /// a typed unknown, never a nearest match.
    public var primaries: String?
    public var transfer: String?
    public var matrix: String?
    public var range: String?
    /// ffprobe color_transfer of the source stream, verbatim. This tag decides the transfer; mpv's trc only has to agree.
    public var sourceTag: String?
    public init(primaries: String? = nil, transfer: String? = nil, matrix: String? = nil, range: String? = nil, sourceTag: String? = nil) {
        self.primaries = primaries; self.transfer = transfer; self.matrix = matrix; self.range = range; self.sourceTag = sourceTag
    }
}

extension ExportDecodedSignal {
    /// The four mpv property names of the decoded source colour probe, in a stable order so a
    /// batch query maps request_id -> key with no table drift.
    public static let videoDecParamsKeys = ["video-dec-params/primaries", "video-dec-params/trc",
                                            "video-dec-params/colormatrix", "video-dec-params/colorlevels"]

    /// Parses one mpv IPC batch reply (one JSON object per line, request_id = base + key index)
    /// into a keyed dict. Unsuccessful replies, unknown request ids, null and non-string or empty
    /// data are skipped: whatever is not positively read stays absent, never invented. A repeated
    /// reply for the same key with the SAME value is harmless; a repeated reply with a DIFFERENT
    /// value is a conflict: the key is dropped and stays dropped (never last-wins).
    public static func parseVideoDecParamsBatch(_ lines: [String], requestIDBase: Int) -> [String: String] {
        var values: [String: String] = [:]
        var conflicts: Set<String> = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["error"] as? String == "success",
                  let id = reply["request_id"] as? Int,
                  (requestIDBase..<(requestIDBase + videoDecParamsKeys.count)).contains(id),
                  let v = reply["data"] as? String, !v.isEmpty else { continue }
            let key = videoDecParamsKeys[id - requestIDBase]
            if let existing = values[key], existing != v {
                values.removeValue(forKey: key); conflicts.insert(key)
                continue
            }
            if !conflicts.contains(key) { values[key] = v }
        }
        return values
    }

    /// True when at least one field was positively read. An all-nil signal is no probe result at
    /// all and must be reported as unavailable, not carried as an empty tuple.
    public var hasAnyField: Bool { primaries != nil || transfer != nil || matrix != nil || range != nil }

    /// Builds the signal from a parsed batch reply keyed by mpv property name. Missing keys stay
    /// nil (typed unknown); the raw strings are kept verbatim and mapped in one place only.
    public init(videoDecParams values: [String: String]) {
        self.init(primaries: values["video-dec-params/primaries"],
                  transfer: values["video-dec-params/trc"],
                  matrix: values["video-dec-params/colormatrix"],
                  range: values["video-dec-params/colorlevels"])
    }
}

/// The accepted-load envelope epoch a probe was taken under: the player's session and opening
/// counters of the accepted identity. Two epochs compare by equality; an unknown epoch is never
/// a match. (Mirrors the accepted identity's session/opening; the path is guarded separately.)
public struct ExportLoadEpoch: Equatable {
    public var session: String
    public var opening: UInt64
    public init(session: String, opening: UInt64) { self.session = session; self.opening = opening }
}

/// The owner-queue accepted-load state the colour probe fences on, carried as plain values so the
/// probe decision stays in the tested pure layer without the Player types. Mirrors
/// ExportOwnerSnapshot (Player/ExportWireObserver.swift): session, opening, path, the accepted
/// receipt's run id, and the connection epoch the owner bumps on every file-loaded, purge and
/// reconnect.
public struct ExportProbeFence: Equatable {
    public var session: String, opening: UInt64, path: String, connectionEpoch: UInt64, receiptRunId: String?
    public init(session: String, opening: UInt64, path: String, connectionEpoch: UInt64, receiptRunId: String?) {
        self.session = session; self.opening = opening; self.path = path
        self.connectionEpoch = connectionEpoch; self.receiptRunId = receiptRunId
    }
}

public struct ExportColourEvidence: Equatable {
    /// The render path class the job's frames come from, when the route is known and qualified.
    /// The SDR BT.709 route (ExportRGBA64ColorTuple.effective) is the only qualified class today.
    public var renderPath: RenderPath?
    /// The producer's per-job statement that the frames carry the look exactly as seen. Absent or
    /// false = no proof: planning refuses (framesNotBakedAsSeen), the encode route stays closed.
    public var framesBakedAsSeen: Bool?
    /// True only with positive producer evidence that the look touched pixels. Nil = unknown and
    /// maps to true (strict): source light statistics are then never retained.
    public var pixelsModifiedByLook: Bool?
    /// True only with positive evidence that the look remapped primaries. Nil = unknown and maps
    /// to true (strict): the source mastering display is then never asserted as the output's master.
    public var gamutRemappedByLook: Bool?
    /// A validated color-preserving conversion contract for this job. False unless the colour gate
    /// qualified this route AND the job was validated: fail-closed by construction.
    public var colorPreservationValidated: Bool
    /// The decoded source signal read under the load-generation fence; nil = no probe this generation.
    public var decodedSignal: ExportDecodedSignal?
    /// The accepted-load epoch the evidence was captured under; nil = unknown, and unknown never matches.
    public var loadEpoch: ExportLoadEpoch?

    public init(renderPath: RenderPath? = nil, framesBakedAsSeen: Bool? = nil,
                pixelsModifiedByLook: Bool? = nil, gamutRemappedByLook: Bool? = nil,
                colorPreservationValidated: Bool = false, decodedSignal: ExportDecodedSignal? = nil,
                loadEpoch: ExportLoadEpoch? = nil) {
        self.renderPath = renderPath; self.framesBakedAsSeen = framesBakedAsSeen
        self.pixelsModifiedByLook = pixelsModifiedByLook; self.gamutRemappedByLook = gamutRemappedByLook
        self.colorPreservationValidated = colorPreservationValidated; self.decodedSignal = decodedSignal
        self.loadEpoch = loadEpoch
    }

    /// Epoch binding for the live-evidence fence: this evidence counts only when its epoch exists
    /// and equals the look capture's accepted identity. Unknown on either side refuses; a box
    /// epoch is never stamped and never matched by default.
    public func epochBound(toSession session: String?, opening: UInt64?) -> Bool {
        guard let loadEpoch, let session, let opening else { return false }
        return loadEpoch.session == session && loadEpoch.opening == opening
    }

    /// The strict RenderStatement for the binding: unknowns map to the branch that can never
    /// promote a retention claim. `baked` nil is returned as nil (missing input), not false,
    /// so the caller lists it as missing instead of planning against a fabricated statement.
    public func strictStatement(transferIntent: TransferKind?) -> RenderStatement? {
        guard let path = renderPath, let baked = framesBakedAsSeen else { return nil }
        return RenderStatement(renderPath: path, transferIntent: transferIntent,
                               framesBakedAsSeen: baked,
                               colorPreservationValidated: colorPreservationValidated,
                               pixelsModifiedByLook: pixelsModifiedByLook ?? true,
                               gamutRemappedByLook: gamutRemappedByLook ?? true)
    }

    /// mpv video-dec-params string -> typed transfer. Anything unrecognised is a typed unknown.
    public static func transferKind(_ s: String) -> TransferKind? {
        switch s {
        case "bt.709", "bt709": return .sdr
        case "smpte2084", "pq": return .pq
        case "arib-std-b67", "hlg": return .hlg
        default: return nil
        }
    }
    /// The transfer rule (one decision table, shared with BUILD2's qualify): the source tag (ffprobe color_transfer) decides.
    /// bt709 is accepted; mpv's trc (video-dec-params/trc) must be absent or bt.1886. mpv names its transfers in mp_csp_trc_names
    /// (video/csputils.c): there is bt.1886 and no bt.709, and avcol_trc_to_mp_csp_trc folds bt709, smpte170m, smpte240m and
    /// bt2020-10 into bt.1886, so bt.1886 alone proves nothing and never decides. Every other tag, HDR included, is refused with
    /// the tag shown; a missing, unknown or unspecified tag is refused.
    public enum TransferVerdict: Equatable { case kind(TransferKind), refused(String) }
    public static func transferVerdict(sourceTag: String?, mpvTRC: String?) -> TransferVerdict {
        let tag = sourceTag ?? ""
        guard tag == "bt709" else {
            return .refused("source transfer refused: ffprobe color_transfer is \(tag.isEmpty ? "absent" : "\"" + tag + "\""), only \"bt709\" is accepted")
        }
        guard let m = mpvTRC, !m.isEmpty else { return .kind(.sdr) }
        return m == "bt.1886" ? .kind(.sdr) : .refused("source transfer refused: ffprobe color_transfer is \"bt709\" but mpv reads gamma \"\(m)\", not bt.1886")
    }
    public static func primaries(_ s: String) -> ColorPrimaries? {
        switch s {
        case "bt.709", "bt709": return .bt709
        case "bt.2020", "bt2020": return .bt2020
        default: return nil
        }
    }
    public static func matrix(_ s: String) -> ColorMatrix? {
        switch s {
        case "bt.709", "bt709": return .bt709
        case "bt.2020nc", "bt.2020-ncl", "bt2020nc": return .bt2020nc
        default: return nil
        }
    }
    public static func range(_ s: String) -> VideoSignalRange? {
        switch s {
        case "limited", "tv", "mpeg": return .limited
        case "full", "pc", "jpeg": return .full
        default: return nil
        }
    }
}

extension ExportColourEvidence {
    /// Owner-snapshot probe decision: the decoded read counts only when one and the same accepted
    /// load spans the whole batch - both snapshots present and equal on session, opening, path,
    /// connection epoch and a non-nil receipt run id - the probed path is the requested one, and
    /// the parsed tuple has at least one positively read field. A load, a reconnect or a same-path
    /// reopen during the query drops the read, as does a missing or mismatched receipt run id:
    /// (nil, nil), never a stale value. The epoch is the BEFORE snapshot's session/opening, bound
    /// only on equality. The App conformer calls exactly this; there is no second decision path.
    /// Scope: equality is a host identity fence - the owner state observed no change during the
    /// call. It is not a globally atomic mpv transaction, not proof that every mpv event was
    /// drained or that no transition is pending, and never producer-settlement or opened-file
    /// proof; the existing gates keep refusing Start.
    public static func ownerSnapshotProbeDecision(signal: ExportDecodedSignal, before: ExportProbeFence?, after: ExportProbeFence?, requestedPath: String) -> (signal: ExportDecodedSignal?, epoch: ExportLoadEpoch?) {
        guard let before, let after, before == after, before.path == requestedPath,
              before.receiptRunId != nil, signal.hasAnyField else { return (nil, nil) }
        return (signal, ExportLoadEpoch(session: before.session, opening: before.opening))
    }
}

/// The epoch legs of one same-job renderer receipt, carried as plain values so the binding
/// decision stays in the tested pure layer without the Player types. Every leg is required:
/// a receipt that cannot name its run, its accepted load, the look it applied, the raster it
/// rendered at and the renderer epoch it reports is not evidence input at all.
public struct ExportRendererEpochLegs: Equatable {
    /// The producer run the receipt belongs to (the job leg): the scripts' run id.
    public var runId: String
    /// The accepted load the render ran under (the load leg): session, opening and path.
    public var session: String
    public var opening: UInt64
    public var path: String
    /// The connection epoch the render stream lived on (the reconnect leg): a reconnect is a
    /// different renderer stream even when the path is unchanged.
    public var connectionEpoch: UInt64
    /// The look the renderer states it applied (the look pin leg).
    public var lookPinSha256: String
    /// The raster the frames were rendered at, [width, height] (the raster leg).
    public var raster: [Int]
    /// The renderer's per-run epoch the receipt reports (the renderer epoch leg).
    public var rendererEpoch: Int64
    public init(runId: String, session: String, opening: UInt64, path: String,
                connectionEpoch: UInt64, lookPinSha256: String, raster: [Int], rendererEpoch: Int64) {
        self.runId = runId; self.session = session; self.opening = opening; self.path = path
        self.connectionEpoch = connectionEpoch; self.lookPinSha256 = lookPinSha256
        self.raster = raster; self.rendererEpoch = rendererEpoch
    }
}

extension ExportColourEvidence {
    /// Accepted-load / renderer epoch binding for renderer-sourced evidence. The epoch the
    /// evidence may carry is the ACCEPTED LOAD's session/opening, and only when the receipt is
    /// one and the same job end to end: the receipt's run id equals the run context's and is
    /// well-formed, and the owner's accepted receipt names the same run (job leg); the
    /// receipt's session/opening/path equal the run context's accepted identity and the owner
    /// still reports that same load (load leg); the receipt's connection epoch is the owner's
    /// current one (reconnect leg); the receipt's look pin is well-formed and equals the run
    /// context's captured look pin (look pin leg); the receipt's raster is the raster the job
    /// committed to (raster leg); and the renderer epoch is a valid positive safe integer equal
    /// to the run context's export epoch, so any reset or advance invalidates the receipt by
    /// plain inequality (renderer epoch leg). Any nil or mismatch yields nil: typed unknown,
    /// never a stamped epoch, so the preflight keeps listing the evidence missing and refusing
    /// Start. This vouches ONLY the epoch: it stamps no render-path, frames-baked or validation
    /// field of the evidence, and it is a host identity fence, never producer-settlement or
    /// opened-file proof; the existing gates keep refusing Start.
    public static func rendererBoundEpoch(run: ExportProducerRunContext, owner: ExportProbeFence,
                                          receipt: ExportRendererEpochLegs,
                                          jobRaster: (w: Int, h: Int)) -> ExportLoadEpoch? {
        guard ExportRunValidation.validRunId(run.runId), receipt.runId == run.runId,
              let receiptRunId = owner.receiptRunId, receiptRunId == run.runId,
              receipt.session == run.identity.session, receipt.opening == run.identity.opening,
              receipt.path == run.identity.path,
              owner.session == run.identity.session, owner.opening == run.identity.opening,
              owner.path == run.identity.path,
              receipt.connectionEpoch == owner.connectionEpoch,
              ExportRunValidation.validPin(receipt.lookPinSha256),
              receipt.lookPinSha256 == run.lookPinSha256,
              receipt.raster == [jobRaster.w, jobRaster.h],
              jobRaster.w > 0, jobRaster.h > 0,
              ExportRunValidation.validEpoch(receipt.rendererEpoch),
              let exportEpoch = run.exportEpoch, exportEpoch == receipt.rendererEpoch
        else { return nil }
        return ExportLoadEpoch(session: run.identity.session, opening: run.identity.opening)
    }
}

/// The expected render state a probe must observe: a NEXT-MINT RESERVATION captured by the
/// renderer owner as ONE immutable value inside the freeze transaction (the same critical
/// section as the freeze) and bound to the probe request. It is the compare-and-consume
/// condition for the next mint, not a pre-minted snapshot being returned: the reserved
/// revision does not exist yet and is never presented as if it did. The expected minted
/// revision is exactly photonSnapshotRevision + 1 (checkedAdd; a counter overflow refuses,
/// never wraps). The consumer equates this expectation with the receipt's own actually-used
/// legs by exact equality - no >= anywhere; a mint between freeze and probe is observed as a
/// different value, never silently matched. The expected value is never copied from a receipt.
///
/// Two revision axes are carried separately and are never copied or converted into each other
/// (they may happen to hold equal integers; that is not semantic equality):
/// - the PHOTON SNAPSHOT MINT revision: the PhotonPresenterProducer snapshot counter at freeze
///   time, carried inside snapshotLegs (token + photon epoch + photon snapshot revision);
/// - the SURFACE revision: one leg of the source frame identity (session, generation,
///   sequence, surface revision), carried inside frameIdentity.
public struct ExportExpectedRenderLegs: Equatable {
    /// The renderer snapshot expectation: producer token, photon epoch and the photon snapshot
    /// mint revision observed at freeze time (the reservation base for the next mint).
    public var snapshotLegs: PhotonExportPhotonSnapshotLegs
    /// The source frame identity axis: session, generation, sequence and the surface revision
    /// the render used.
    public var frameIdentity: PhotonExportFrameIdentity
    /// The existing legs: run id, accepted load, connection epoch, look pin, raster and the
    /// renderer epoch at freeze time.
    public var legs: ExportRendererEpochLegs
    public init(snapshotLegs: PhotonExportPhotonSnapshotLegs,
                frameIdentity: PhotonExportFrameIdentity,
                legs: ExportRendererEpochLegs) {
        self.snapshotLegs = snapshotLegs; self.frameIdentity = frameIdentity; self.legs = legs
    }
    /// The photon snapshot mint revision axis, named explicitly so no consumer mistakes it for
    /// the surface revision.
    public var photonSnapshotRevision: UInt64 { snapshotLegs.revision }
    /// The surface revision axis, named explicitly so no consumer mistakes it for the photon
    /// snapshot mint revision.
    public var surfaceRevision: UInt64 { frameIdentity.surfaceRevision }
    /// The minted photon snapshot revision the consumer must observe from the next mint:
    /// exactly photonSnapshotRevision + 1. nil on counter overflow - a refusal, never a
    /// wrapped value.
    public var expectedMintedSnapshotRevision: UInt64? {
        let r = snapshotLegs.revision.addingReportingOverflow(1)
        return r.overflow ? nil : r.partialValue
    }
}

/// The fence verdict for carrying the frozen expectation into a probe observation. The
/// distinction is typed and never relabeled: a stale expectation stays stale.
public enum ExportExpectedLegsFence: Equatable {
    /// The owner still reports exactly the accepted load, connection and run the legs were
    /// frozen under: the expected value may ride the probe request, and the accepted-load
    /// epoch it vouches rides with it.
    case current(expected: ExportExpectedRenderLegs, epoch: ExportLoadEpoch)
    /// The owner moved between freeze and probe: a load, a reconnect or a run change. Typed
    /// stale, never relabeled as current; the probe must not run against the old expectation.
    case stale
    /// The fence itself cannot be read: typed unknown, fail-closed like today.
    case unknown
}

extension ExportColourEvidence {
    /// Carries the frozen expected legs into the probe observation under the same
    /// accepted-load/connection fence as the colour probe: .current only when the owner's
    /// snapshot names the same session, opening and path, the same connection epoch, and an
    /// accepted receipt of the same run; .stale when any of those moved between freeze and
    /// probe; .unknown when the fence cannot be read. The expected value is transported
    /// unchanged in both directions of the comparison: this function never edits, fills or
    /// re-derives a leg, and it performs no equality against any receipt - the consumer
    /// equates the freeze-captured expectation with the receipt's own reported legs. This is
    /// a host identity fence, never producer-settlement or opened-file proof.
    public static func carryExpectedLegs(_ expected: ExportExpectedRenderLegs,
                                         owner: ExportProbeFence?) -> ExportExpectedLegsFence {
        guard let owner else { return .unknown }
        let legs = expected.legs
        guard owner.session == legs.session, owner.opening == legs.opening,
              owner.path == legs.path, owner.connectionEpoch == legs.connectionEpoch,
              let receiptRunId = owner.receiptRunId, receiptRunId == legs.runId
        else { return .stale }
        return .current(expected: expected,
                        epoch: ExportLoadEpoch(session: legs.session, opening: legs.opening))
    }
}
// ===== END merged ExportColourEvidence.swift =====

// ===== BEGIN merged ExportRenderReceiptEvidence.swift =====
// Picture/ExportRenderReceiptEvidence.swift
// Typed ExportColourEvidence render fields from a REAL renderer readback receipt, bound to the same job.
// The producer side (renderer receipt) states what the render did; this derives only what that receipt proves and
// refuses everything else. Nothing here is a constant: framesBakedAsSeen is true only when every leg below holds,
// colorPreservationValidated is never written (stays false), pixelsModifiedByLook / gamutRemappedByLook stay nil
// (the receipt makes no statement; nil maps to the strict branch). Probe-only evidence (decoded signal + load epoch)
// is carried through unchanged from the existing probe; this file never reads mpv.
// Two epochs, two evidences (architect design ruling relayed by main, not owner authority): this derivation is the PLAN-TIME (E0) evidence: a bounded real
// probe/readback taken under the capture's own epoch E0 shows the route/render capability. It is never the evidence of the E1 output frames (prepare mints E1 > E0;
// each output frame is validated against binding.run under E1 by ExportFrameRenderAdmission inside PhotonExportProducer.validate). E0 nil = typed unavailable.
// framesBakedAsSeen is NOT promoted from this derivation alone: it needs a typed seal/settlement proof bound to the receipt (ExportFrameSealProof); with no proof it stays nil
// and the plan keeps refusing. No production path supplies a seal proof yet.
// Scope: legs bound here are identity/run/epoch/look-pin/raster/photon-snapshot equality plus the qualified SDR BT.709
// contract. The run id and export epoch on a readback receipt are CALLER-CLAIMED labels (GorAVCore PhotonExportReadbackReceipt
// header): equality with the capture's own labels is a consistency fence, not renderer-verified epoch proof, and
// the photon snapshot legs are a renderer-state witness, not the Lua seal closure. No claim beyond that is made.
// Uses: GorAVCore (PhotonExportReadbackReceipt, PhotonExportPhotonSnapshotLegs), ExportColourEvidence, ExportLookCapture, ExportSnapshotExpectation
// Engine: none

/// One real readback receipt as the producer-side owner observed it, with the labels it was taken under.
/// `expectedSnapshot` is the renderer-state owner's own capture of the producer snapshot legs the job was frozen with
/// (never copied out of the receipt being judged).
public struct ExportRenderObservation: Equatable {
    public var receipt: PhotonExportReadbackReceipt
    public var identity: ExportAcceptedIdentity
    public var lookPinSha256: String
    public var expectedSnapshot: PhotonExportPhotonSnapshotLegs?
    /// The owner-queue accepted-load state read by the owner when the observation was handed over (the reconnect and job legs of the epoch binding).
    public var owner: ExportProbeFence
    /// The typed seal/settlement proof for exactly this frame request, when the renderer-owner chain supplies one. nil = none (the product has none yet): no promotion.
    public var sealProof: ExportFrameSealProof?
    /// The freeze-captured next-mint reservation (renderer owner, never copied from the receipt) the probe ran against. nil = the bridge did not carry one: the plain expectedSnapshot path only.
    public var expectedLegs: ExportExpectedRenderLegs?
    public init(receipt: PhotonExportReadbackReceipt, identity: ExportAcceptedIdentity, lookPinSha256: String,
                expectedSnapshot: PhotonExportPhotonSnapshotLegs?, owner: ExportProbeFence, sealProof: ExportFrameSealProof? = nil,
                expectedLegs: ExportExpectedRenderLegs? = nil) {
        self.receipt = receipt; self.identity = identity; self.lookPinSha256 = lookPinSha256; self.expectedSnapshot = expectedSnapshot; self.owner = owner
        self.sealProof = sealProof; self.expectedLegs = expectedLegs
    }
}

public enum ExportRenderEvidenceRefusal: Error, Equatable, CustomStringConvertible {
    /// The carried next-mint reservation does not bind to this capture/owner/look/raster, or disagrees with expectedSnapshot (reserved revision is not base + 1, or an overflowed base).
    case expectedLegsNotBound
    /// The exact-equality consumer refused the receipt against the reservation (typed reason kept).
    case expectedLegs(ExportExpectedLegsConsumer.Refusal)
    case noObservation
    case captureNotVerified
    case probeNotBound
    case identityMismatch
    case runMismatch
    case epochUnknownOrMismatch
    case lookPinMismatch
    case rasterUnknownOrMismatch
    case photonChainNotRun
    case stereoProjected
    case snapshotUnknown
    case snapshotMismatch
    case routeNotQualified
    case rendererEpochNotBound
    /// E0 unavailable: the capture has no export epoch to bind the probe to. Typed unavailable, no epoch is invented.
    case captureEpochUnavailable
    /// The receipt's overlay statement is refused by the readback contract's overlay policy, or the receipt contradicts itself.
    case overlayRefused
    case overlayInconsistent
    case alphaRefused
    case alphaInconsistent
    /// A seal proof was supplied but does not bind to this receipt's run, epoch, frame identity and owner.
    case sealNotBound
    public var description: String {
        switch self {
        case .expectedLegsNotBound: return "expected render legs do not bind to this capture, owner, look and raster"
        case .expectedLegs(let r): return "render receipt differs from the frozen next-mint reservation: \(r)"
        case .noObservation: return "no render receipt"
        case .captureNotVerified: return "look capture has no verified run identity"
        case .probeNotBound: return "colour probe is not bound to the look's accepted load"
        case .identityMismatch: return "render receipt is from another accepted load"
        case .runMismatch: return "render receipt is from another producer run"
        case .epochUnknownOrMismatch: return "render receipt export epoch is unknown or differs from the capture's"
        case .lookPinMismatch: return "render receipt is bound to another look"
        case .rasterUnknownOrMismatch: return "render receipt raster is unknown or differs from the planned raster"
        case .photonChainNotRun: return "render did not run the photon chain"
        case .stereoProjected: return "stereo projection is unsupported: outside the qualified SDR route"
        case .snapshotUnknown: return "renderer snapshot witness or expected snapshot is unknown"
        case .snapshotMismatch: return "renderer snapshot differs from the frozen one"
        case .routeNotQualified: return "render route is not the qualified SDR BT.709 route (unqualified route, unsupported)"
        case .captureEpochUnavailable: return "no capture export epoch (E0) to bind the probe to"
        case .overlayRefused: return "render receipt overlay is refused by the readback contract's overlay policy"
        case .overlayInconsistent: return "render receipt overlay statements contradict each other"
        case .alphaRefused: return "render receipt alpha evidence is refused by the readback contract"
        case .alphaInconsistent: return "render receipt alpha statements contradict each other"
        case .sealNotBound: return "seal proof does not bind to this render receipt"
        case .rendererEpochNotBound: return "render receipt legs do not bind to the owner's run, load, connection and epoch"
        }
    }
}

public enum ExportRenderReceiptEvidence {
    /// The receipt-only legs (no probe needed): the same checks the producer-side consumer gate can reuse per frame.
    /// nil = every leg held. Order is fixed; the first failing leg is returned.
    public static func refusal(observation: ExportRenderObservation, capture: ExportLookCapture) -> ExportRenderEvidenceRefusal? {
        guard capture.producerRunVerified, let accepted = capture.acceptedIdentity else { return .captureNotVerified }
        let r = observation.receipt
        guard observation.identity == accepted else { return .identityMismatch }
        guard r.runID == capture.loadReceipt.runId else { return .runMismatch }
        // Unknown never matches: a receipt without an export epoch was not rendered under the barrier, and a capture without one has no epoch to equal.
        guard let c = capture.exportEpoch else { return .captureEpochUnavailable }
        guard let e = r.exportEpoch, e == c else { return .epochUnknownOrMismatch }
        guard !observation.lookPinSha256.isEmpty, observation.lookPinSha256 == capture.look.pinSha256 else { return .lookPinMismatch }
        guard let planned = capture.raster.expectedEncode, r.width == planned.width, r.height == planned.height else { return .rasterUnknownOrMismatch }
        guard r.render.photonChain else { return .photonChainNotRun }
        guard !r.render.stereoProjected else { return .stereoProjected }
        // Overlay and alpha: the contract's own admission plus self-consistency of the two statements on the receipt (a contradicting receipt is refused, never reconciled).
        guard r.contract.admits(compositedOverlay: r.compositedOverlay) == nil else { return .overlayRefused }
        guard r.compositedOverlay == r.render.compositedOverlay else { return .overlayInconsistent }
        guard r.contract.admits(alpha: r.alphaEvidence) == nil else { return .alphaRefused }
        guard r.alphaEvidence == r.render.alphaEvidence else { return .alphaInconsistent }
        guard let expected = observation.expectedSnapshot else { return .snapshotUnknown }
        switch ExportSnapshotExpectation(legs: expected, rule: .exact).verdict(r.render) {
        case .unknown: return .snapshotUnknown
        case .mismatch: return .snapshotMismatch
        case .match: break
        }
        guard r.contract.exportColorTuple == .sdr709 else { return .routeNotQualified }
        // The carried next-mint reservation must be the renderer owner's own capture for THIS capture/owner/look/raster and agree with expectedSnapshot (reserved = base + 1, checked).
        if let x = observation.expectedLegs {
            guard let minted = x.expectedMintedSnapshotRevision, x.legs.runId == capture.loadReceipt.runId, x.legs.rendererEpoch == c,
                  x.legs.session == accepted.session, x.legs.opening == accepted.opening, x.legs.path == accepted.path,
                  x.legs.connectionEpoch == observation.owner.connectionEpoch, x.legs.lookPinSha256 == capture.look.pinSha256,
                  x.legs.raster == [planned.width, planned.height],
                  expected == PhotonExportPhotonSnapshotLegs(epoch: x.snapshotLegs.epoch, token: x.snapshotLegs.token, revision: minted)
            else { return .expectedLegsNotBound }
        }
        // Final fence: PLAYBACK's pure epoch binding (ExportColourEvidence.rendererBoundEpoch) over the same receipt legs: run, accepted load, connection epoch,
        // look pin, raster and renderer epoch against the capture's run context and the owner's state. It must vouch the accepted load's epoch.
        guard let run = ExportProducerRunContext(capture: capture) else { return .captureNotVerified }
        let legs = ExportRendererEpochLegs(runId: r.runID, session: observation.identity.session, opening: observation.identity.opening,
                                           path: observation.identity.path, connectionEpoch: observation.owner.connectionEpoch,
                                           lookPinSha256: observation.lookPinSha256, raster: [r.width, r.height], rendererEpoch: e)
        guard ExportColourEvidence.rendererBoundEpoch(run: run, owner: observation.owner, receipt: legs, jobRaster: (w: planned.width, h: planned.height))
                == ExportLoadEpoch(session: accepted.session, opening: accepted.opening) else { return .rendererEpochNotBound }
        return nil
    }

    /// Merges the render fields a verified same-job receipt proves into the probe evidence. A refusal returns no evidence.
    /// `consumer` carries the consume-once state for next-mint reservations across calls (a replayed reservation is refused); nil = a fresh consumer for this call only.
    public static func derive(observation: ExportRenderObservation?, capture: ExportLookCapture,
                              probe: ExportColourEvidence, consumer: ExportExpectedLegsConsumer? = nil) -> Result<ExportColourEvidence, ExportRenderEvidenceRefusal> {
        guard let observation else { return .failure(.noObservation) }
        guard probe.epochBound(toSession: capture.acceptedIdentity?.session, opening: capture.acceptedIdentity?.opening) else { return .failure(.probeNotBound) }
        if let why = refusal(observation: observation, capture: capture) { return .failure(why) }
        if let x = observation.expectedLegs, let why = (consumer ?? ExportExpectedLegsConsumer()).consume(x, receipt: observation.receipt) { return .failure(.expectedLegs(why)) }
        var baked: Bool? = nil
        if let proof = observation.sealProof {
            let r = observation.receipt
            let id = PhotonExportFrameIdentity(sessionID: r.sessionID, sessionGeneration: r.sessionGeneration, sequence: r.sequence, surfaceRevision: r.surfaceRevision)
            guard proof.sealed, proof.runId == r.runID, proof.epoch == r.exportEpoch, proof.identity == id,
                  proof.owner.session == observation.owner.session, proof.owner.opening == observation.owner.opening,
                  proof.owner.connectionEpoch == observation.owner.connectionEpoch else { return .failure(.sealNotBound) }
            baked = true
        }
        return .success(ExportColourEvidence(renderPath: .displayReferredSDR, framesBakedAsSeen: baked,
                                             pixelsModifiedByLook: nil, gamutRemappedByLook: nil,
                                             colorPreservationValidated: false,
                                             decodedSignal: probe.decodedSignal, loadEpoch: probe.loadEpoch))
    }
}

/// The E1 per-frame render admission, run by PhotonExportProducer.validate for EVERY output frame against binding.run (the epoch prepare minted, E1 > E0).
/// It never consults the plan-time observation: a first frame or an E0 probe is no pass for the next frame. The frozen snapshot is the renderer-state owner's own capture;
/// the receipt is judged against it by exact equality (a renderer-state witness, not the Lua seal closure and not an "exact seal").
public struct ExportFrameRenderAdmission: Equatable {
    public enum Refusal: Equatable {
        case runMismatch, epochMismatch, lookPinMismatch, photonChainNotRun, stereoProjected, snapshotUnknown, snapshotMismatch
        case overlayInconsistent, alphaInconsistent, routeNotQualified
    }
    public var frozenSnapshot: PhotonExportPhotonSnapshotLegs
    public var lookPinSha256: String
    public init(frozenSnapshot: PhotonExportPhotonSnapshotLegs, lookPinSha256: String) { self.frozenSnapshot = frozenSnapshot; self.lookPinSha256 = lookPinSha256 }

    public func refusal(receipt r: PhotonExportReadbackReceipt, run: ExportProducerRunContext) -> Refusal? {
        guard r.runID == run.runId else { return .runMismatch }
        guard let e = r.exportEpoch, let b = run.exportEpoch, e == b else { return .epochMismatch }
        guard !lookPinSha256.isEmpty, run.lookPinSha256 == lookPinSha256 else { return .lookPinMismatch }
        guard r.render.photonChain else { return .photonChainNotRun }
        guard !r.render.stereoProjected else { return .stereoProjected }
        switch ExportSnapshotExpectation(legs: frozenSnapshot, rule: .exact).verdict(r.render) {
        case .unknown: return .snapshotUnknown
        case .mismatch: return .snapshotMismatch
        case .match: break
        }
        guard r.compositedOverlay == r.render.compositedOverlay else { return .overlayInconsistent }
        guard r.alphaEvidence == r.render.alphaEvidence else { return .alphaInconsistent }
        guard r.contract.exportColorTuple == .sdr709 else { return .routeNotQualified }
        return nil
    }
}
// ===== END merged ExportRenderReceiptEvidence.swift =====

// MARK: - ExportExpectedLegsConsumer
/// Consumer side of the next-mint reservation (ExportExpectedRenderLegs): the freeze-captured expectation is equated with the receipt's OWN reported legs by exact equality,
/// never >=, never copied from the receipt. Two revision axes are checked separately and never converted into each other: the Photon snapshot MINT revision
/// (expected = photonSnapshotRevision + 1, overflow refuses) and the SURFACE revision inside the source frame identity (and its provenance witness).
/// One expectation is consumable once: any second check of the same reservation is .replay. This is a renderer-state equality witness only: it is no seal/settlement proof,
/// does not make the epoch label anything but caller-claimed, and promotes nothing.
public final class ExportExpectedLegsConsumer {
    public enum Refusal: Equatable {
        case replay, overflow, snapshotUnknown
        case snapshotTokenOrEpochMismatch, photonSnapshotRevisionMismatch
        case frameIdentityMismatch, surfaceRevisionWitnessMismatch
        case runMismatch, rendererEpochMismatch
    }
    private struct Key: Hashable { let token: UUID; let epoch: UInt64; let revision: UInt64; let seq: UInt64; let run: String }
    private var consumed = Set<Key>()
    private let lock = NSLock()
    public init() {}

    public func consume(_ expected: ExportExpectedRenderLegs, receipt r: PhotonExportReadbackReceipt) -> Refusal? {
        let s = expected.snapshotLegs
        let k = Key(token: s.token, epoch: s.epoch, revision: s.revision, seq: expected.frameIdentity.sequence, run: expected.legs.runId)
        lock.lock(); let fresh = consumed.insert(k).inserted; lock.unlock()
        guard fresh else { return .replay }
        guard let minted = expected.expectedMintedSnapshotRevision else { return .overflow }
        guard let used = r.render.photonSnapshotLegs else { return .snapshotUnknown }
        guard used.token == s.token, used.epoch == s.epoch else { return .snapshotTokenOrEpochMismatch }
        guard used.revision == minted else { return .photonSnapshotRevisionMismatch }
        let id = expected.frameIdentity
        guard r.sessionID == id.sessionID, r.sessionGeneration == id.sessionGeneration, r.sequence == id.sequence, r.surfaceRevision == id.surfaceRevision
        else { return .frameIdentityMismatch }
        guard r.provenance.surfaceRevisionWitness == id.surfaceRevision else { return .surfaceRevisionWitnessMismatch }
        guard r.runID == expected.legs.runId else { return .runMismatch }
        guard let e = r.exportEpoch, e == expected.legs.rendererEpoch else { return .rendererEpochMismatch }
        return nil
    }
}
