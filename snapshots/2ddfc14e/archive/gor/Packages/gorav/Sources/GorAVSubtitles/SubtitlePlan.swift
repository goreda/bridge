import Foundation

/// TIMED-PLAN IMPLEMENTATION (u8r2) - gorav lanes L5/L6 producer side.
///
/// Status: IMPLEMENTATION of the accepted interface. gdb's Q1-Q5 engineering
/// decision was relayed 2026-11-01 ~02:25 +03 in two parts via coordination -
/// peer-attributed content, NOT verified by us against an authenticated gdb
/// record; an ENGINEERING decision by gdb's side as relayed, NOT an
/// owner/architect ruling; no deploy/live/default change is implied.
/// Split unchanged: gdb owns the CoreText rasterizer and the host/presenter
/// binding; this lane owns the timed plan, plan revision and source cue/style
/// data. SHARED L5/L6 completion holds until real rendering is verified.
///
/// Decisions as relayed via coordination (peer-attributed throughout,
/// unverified by us against an authenticated gdb record) and where this
/// unit implements them:
/// Q1 The revision PAIR is authoritative: contentID (FNV-1a-64 over the
///    length-prefixed canonical serialization) + producer-owned monotonic
///    generation with typed exhaustion. Implemented by SubtitlePlanRevision,
///    SubtitlePlanContentID, SubtitlePlanProducer (carried from p5).
/// Q2 The presenter seam echoes GENERATION ONLY over the existing three
///    points - verified at landed main 261b58e09531cc8ca3505424c760b3af592b0247:
///    PresenterOverlay.subtitlePlanRevision: UInt64?
///    (SurfaceContract.swift:395), setSubtitlePlanAuthority((FrameIdentity)
///    -> UInt64?)? (MetalPresenter.swift:462),
///    OverlayCompositeReceipt.compositedPlanRevision: UInt64?
///    (MetalRenderer.swift:169). contentID stays plan-side; a same-contentID
///    new generation is a NEW revision and must re-admit. This unit exposes
///    plan.presenterEchoRevision for exactly that echo; the seam itself is
///    gdb's and is NOT widened.
/// Q3 OPTION A evictThenBareNotify: presenter-side mechanics (verified
///    present in landed MetalRenderer.swift: typed stale eviction, bare
///    re-render). Producer-side obligation is only what this file already
///    guarantees: generations never reused within a lineage, exhaustion
///    typed-refused, reissue = new pair.
/// Q4 Half-open [start,end); single active render = latest-starting cue; a
///    typed finding reports the SUPPRESSED cue indices - no silent stacking
///    or line merging. Implemented: OverlayAnswer.cue carries
///    suppressedCueIndices.
/// Q5 PlayRes reference metrics: absent PlayRes uses the DECLARED default
///    384x288 and the plan reports usedDefaultPlayRes (receipt edge is
///    presenter-side). Layout/drawable-pixel scaling, margins and frame
///    pull-in are renderer-side (gdb). Implemented: plan.effectivePlayResX/Y
///    + plan.usedDefaultPlayRes. NOTE: contentID still hashes the RAW PlayRes
///    presence/values (P5-1); the declared default is render-time data, not
///    identity. Written against the CANDIDATE SurfaceContract seam
/// (l3-metal-presenter-r7-landing @ 3dfe096a, PresenterOverlay L383-398) -
/// NOT adopted, NOT bound; that candidate is on HOLD at gdb (Mac compile
/// errors, respin 7069096 pending review, also not canonical). The canonical
/// pin and the overlay-staleness ruling are still open. Nothing here reduces
/// the real ASS delivery scope: the requirements below name exactly what the
/// renderer must honor and what stays explicitly UNSUPPORTED.
///
/// p5 revision (2026-11-01): gdb bounded review of p4 (peer-attributed via
/// coordination, NOT ratified, tests are not a ruling):
/// - P5-1 PlayRes is render-relevant but was outside the identity: a
///   PlayRes-only change left contentID unchanged. PlayRes PRESENCE and
///   VALUES are now hashed (per-axis: present flag + exact value).
/// - P5-2 styleName nil and "" collapsed to the same hash (public init can
///   reach both; the parser normalizes empty to nil). Presence is now hashed
///   explicitly: nil and "" are DIFFERENT identities, no silent collision.
///
/// p4 revision (2026-11-01): independent-review scrutiny on the proposed
/// canonical identity (peer-attributed via coordination, NOT ratified):
/// - S1 Length-prefixed text fields: the p3 NUL-terminator framing was not
///   prefix-free for text containing embedded NULs; fields are now hashed as
///   byte-count + bytes, unambiguous for arbitrary UTF-8.
/// - S2 fontSize was rounded to centipoints, collapsing real differences;
///   it is now hashed as its exact Double bitPattern. PRECISION BOUNDARY,
///   explicit: cue start/end are hashed at MILLISECOND resolution (lossless
///   for SRT millisecond and ASS centisecond sources); fontSize and colour
///   are exact. Sub-millisecond cue-time differences are outside the parsed
///   data model and intentionally not identity.
/// - S3 SubtitlePlanProducer confinement documented (single producer per
///   plan lineage, no thread-safety promise, restart seeding contract).
///
/// p3 revision (2026-11-01): incorporates PEER-ATTRIBUTED gdb engineering
/// notes relayed via coordination - engineering feedback, NOT ratified
/// design and NOT an owner ruling:
/// - F1 A pure content hash is only a content IDENTITY: an A->B->A edit
///   sequence returns to the same hash, so an already-invalidated revision
///   could be reused. p3 splits the revision into content identity plus a
///   producer-owned monotonic instance generation; the echoed pair is the
///   authoritative revision.
/// - F2 The canonical serialization previously omitted the
///   unsupportedOverrides and skippedStyles findings; they are now hashed,
///   so a findings change is a content change.
/// - F3 gdb noted the existing OverlayCompositeReceipt.compositedPlanRevision
///   MIGHT be reused as the echo field - noted, review pending at gdb, no
///   binding here. The staleness no-authority gate (render gate passes on
///   receipts alone when no authority is registered) is UNRESOLVED; this
///   proposal takes no position and assumes no candidate.
///
/// Boundary rules (from the candidate seam, verified):
/// - subtitlePlanRevision is PRODUCER-owned and opaque to the presenter; it is
///   echoed in receipts so this lane can verify WHICH plan was composited.
/// - subtitlePlanRevision is NEVER FrameIdentity.trackRevision (decoder/source
///   track semantics); the two fields stay distinct.
/// - The only overlay representation today is sdrRGBA8Premultiplied, valid
///   ONLY against an sdrRGBA8 surface contract. HDR playback has NO valid
///   subtitle overlay representation: it must be refused typed, never
///   misrendered. gdb describes the typed refusal as engineering harm
///   prevention on its side (peer-attributed via coordination, unverified
///   by us, pending canonical pin) - NOT an owner choice and NOT an M4
///   waiver.

/// Producer-owned revision of one issued plan. PROPOSED shape (p3), pending
/// gdb acceptance:
/// - contentID: FNV-1a 64 over the canonical serialization (PlayRes presence
///   + values per axis; cue count, then per cue: index, start/end
///   MILLISECONDS, style name PRESENCE + value, lines; then the
///   style table in file order with EXACT fontSize bitPattern and colour;
///   then the override findings; then the skipped-style findings). Text
///   fields are length-prefixed (byte count + bytes), unambiguous for
///   arbitrary UTF-8 including embedded NULs. Deterministic, content-derived,
///   no timestamps. IDENTITY ONLY - A->B->A returns to the same contentID
///   (gdb note F1).
/// - generation: producer-owned monotonic instance counter, issued by
///   SubtitlePlanProducer, never reused within a producer. The PAIR is the
///   authoritative echoed revision: identical contentID with a newer
///   generation is a NEW revision, so an invalidated revision can never be
///   resurrected by editing back to old content.
public struct SubtitlePlanRevision: Equatable, Sendable {
    public let contentID: UInt64
    public let generation: UInt64
    public init(contentID: UInt64, generation: UInt64) {
        self.contentID = contentID
        self.generation = generation
    }
}

/// Canonical content identity behind SubtitlePlanRevision.contentID.
public enum SubtitlePlanContentID {
    public static func compute(cues: [SubtitleCue], styles: [ASSParser.Style],
                               playResX: Int?, playResY: Int?,
                               unsupportedOverrides: [ASSParser.OverrideReport],
                               skippedStyles: [ASSParser.SkippedStyle]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func feed(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        func feedText(_ s: String) { feed(UInt64(s.utf8.count)); for b in s.utf8 { feed(UInt64(b)) } }
        func feedOptText(_ s: String?) { feed(s == nil ? 0 : 1); if let s { feedText(s) } }
        func feedOptInt(_ v: Int?) { feed(v == nil ? 0 : 1); if let v { feed(UInt64(bitPattern: Int64(v))) } }
        // PlayRes is render-relevant identity (gdb review P5-1): presence AND
        // values, per axis.
        feedOptInt(playResX)
        feedOptInt(playResY)
        feed(UInt64(cues.count))
        for c in cues {
            feed(UInt64(bitPattern: Int64(c.index)))
            feed(UInt64(bitPattern: Int64((c.startSeconds * 1000).rounded())))
            feed(UInt64(bitPattern: Int64((c.endSeconds * 1000).rounded())))
            // nil and "" are DISTINCT identities (gdb review P5-2).
            feedOptText(c.styleName)
            for line in c.lines { feedText(line) }
        }
        for s in styles {
            feedText(s.name); feedText(s.fontName)
            feed(s.fontSize.bitPattern)
            feed(UInt64(s.primaryColourARGB))
        }
        // Findings are part of the identity (gdb note F2): a plan whose
        // overrides or skipped styles differ is different content.
        feed(UInt64(unsupportedOverrides.count))
        for o in unsupportedOverrides {
            feed(UInt64(bitPattern: Int64(o.cueIndex)))
            feed(UInt64(o.tags.count))
            for t in o.tags { feedText(t) }
        }
        feed(UInt64(skippedStyles.count))
        for s in skippedStyles {
            feed(UInt64(bitPattern: Int64(s.line)))
            feedText(s.reason)
        }
        return h
    }
}

/// One immutable timed plan: parsed track data plus its producer revision.
public struct SubtitlePlan: Equatable, Sendable {
    public let track: SubtitleTrack.Track
    public let schedule: SubtitleSchedule
    public let planRevision: SubtitlePlanRevision
    /// ASS PlayRes layout reference frame, RAW (nil for SRT / absent). These
    /// raw values are what the contentID hashes (P5-1).
    public var playResX: Int? { track.playResX }
    public var playResY: Int? { track.playResY }
    /// Q5 declared default reference frame when PlayRes is absent.
    public static let defaultPlayResX = 384
    public static let defaultPlayResY = 288
    /// Effective render-reference metrics: raw PlayRes, else the DECLARED
    /// default (Q5 - declared, not parsed; the presenter reports the
    /// usedDefaultPlayRes receipt edge).
    public var effectivePlayResX: Int { track.playResX ?? SubtitlePlan.defaultPlayResX }
    public var effectivePlayResY: Int { track.playResY ?? SubtitlePlan.defaultPlayResY }
    /// True when the effective metrics come from the declared default.
    /// PER-AXIS fallback: if exactly one axis is absent, that axis uses the
    /// declared default while the other keeps its raw value (mixed state),
    /// and this flag is still true.
    public var usedDefaultPlayRes: Bool { track.playResX == nil || track.playResY == nil }
    /// Q2: the generation-only value the presenter seam echoes
    /// (subtitlePlanRevision / compositedPlanRevision). contentID never
    /// crosses the seam.
    public var presenterEchoRevision: UInt64 { planRevision.generation }

    /// Typed plan-level findings: cue-data anomalies a consumer must see
    /// rather than have silently change an answer's meaning.
    public enum PlanFinding: Equatable, Sendable {
        /// Two or more cues share the same index. Parser-assigned indices
        /// are unique monotonic track order, so this is unreachable on
        /// parsed tracks; it guards PUBLIC construction where callers can
        /// supply arbitrary cues. While present, index-based suppression
        /// reporting (OverlayAnswer.cue suppressedCueIndices) is ambiguous
        /// for the listed indices: a non-winner cue sharing the winner's
        /// index is NOT listed as suppressed.
        case duplicateCueIndices([Int])
    }
    public let findings: [PlanFinding]

    public init(track: SubtitleTrack.Track, revision: SubtitlePlanRevision) {
        self.track = track
        self.schedule = SubtitleSchedule(cues: track.cues)
        self.planRevision = revision
        let indices = track.cues.map { $0.index }
        let dups = Dictionary(grouping: indices, by: { $0 })
            .filter { $0.value.count > 1 }.map { $0.key }.sorted()
        // Derived from cues, which the contentID already hashes: no contentID
        // input change (a findings change here IS a cues change upstream).
        self.findings = dups.isEmpty ? [] : [.duplicateCueIndices(dups)]
    }
}

/// Producer that owns the monotonic generation behind plan revisions.
/// Generations are issued strictly increasing and NEVER reused: exhaustion
/// is a typed refusal, not a silent wrap (gdb note F1; the
/// exhaustion/invalid-generation behavior is part of THIS proposal, still
/// open for gdb).
///
/// Restart continuity: a producer that restarts must be seeded with the last
/// generation it issued (startingGeneration:). Seeding with a LOWER value
/// than actually issued violates monotonicity - caller contract, stated
/// because the alternative (silent reuse) is exactly the failure F1 names.
///
/// CONFINEMENT (review note S3): one producer owns one plan lineage. This
/// class is NOT thread-safe: call makePlan/updateTrack from a single
/// serialized execution context. Do NOT run two producers over the same
/// lineage (two counters would issue overlapping generations, silently
/// breaking the pair's uniqueness); after a restart, seed exactly one new
/// producer with the last issued generation.
public final class SubtitlePlanProducer {
    public enum RevisionError: Error, Equatable {
        /// The generation space is exhausted; issuing another revision would
        /// wrap or reuse. Typed refusal - never wraps, never reuses.
        case generationExhausted
    }

    public private(set) var lastGeneration: UInt64
    private var track: SubtitleTrack.Track

    public init(track: SubtitleTrack.Track, startingGeneration: UInt64 = 0) {
        self.track = track
        self.lastGeneration = startingGeneration
    }

    /// Issue a plan for the current track with the next generation.
    public func makePlan() throws -> SubtitlePlan {
        guard lastGeneration < UInt64.max else { throw RevisionError.generationExhausted }
        lastGeneration += 1
        return SubtitlePlan(track: track, revision: SubtitlePlanRevision(
            contentID: SubtitlePlanContentID.compute(
                cues: track.cues, styles: track.styles,
                playResX: track.playResX, playResY: track.playResY,
                unsupportedOverrides: track.unsupportedOverrides,
                skippedStyles: track.skippedStyles),
            generation: lastGeneration))
    }

    /// Replace the track and issue a plan with the next generation.
    public func updateTrack(_ newTrack: SubtitleTrack.Track) throws -> SubtitlePlan {
        track = newTrack
        return try makePlan()
    }
}

/// What the producer answers when the presenter asks what to render for a
/// frame. Typed; the HDR case is a REFUSAL, not a degraded render.
public enum OverlayAnswer: Equatable, Sendable {
    /// No cue active at this pts; presenter composites nothing.
    case empty(planRevision: SubtitlePlanRevision)
    /// The active cue (latest-starting per the Q4 decision) with its plan
    /// revision and the indices of any OTHER cues covering the same pts
    /// (suppressed, never stacked or merged), sorted ascending. Equal-start
    /// ties resolve to first in track order - ALIGNED with
    /// SubtitleSchedule.activeCue (both keep the first maximal); consumers
    /// must not re-derive a winner with a last-wins rule. Style
    /// association, lines and the style table travel on the plan;
    /// override/skipped-style findings travel on the track.
    case cue(SubtitleCue, suppressedCueIndices: [Int], planRevision: SubtitlePlanRevision)
    /// HDR surface contract: no supported overlay representation exists.
    /// Typed refusal - compositing SDR-gamma text into an HDR surface is a
    /// misrender, not a fallback.
    case hdrUnsupported(planRevision: SubtitlePlanRevision)
}

public extension SubtitlePlan {
    /// surfaceIsHDR: the presenter names the surface contract class it is
    /// compositing against (true for nativeHDR / edrRGBA16F; the candidate
    /// contract rejects SDR overlays there typed). Producer-side this is a
    /// boolean proposal input until the canonical pin lands.
    ///
    /// PRECONDITION: cue indices are unique (parser-assigned indices are
    /// monotonic track order, so parsed tracks always satisfy this).
    /// suppressedCueIndices is index-based: a non-winner cue SHARING the
    /// winner's index would not be reported. Public construction with
    /// duplicate indices is not refused but is surfaced as the typed plan
    /// finding SubtitlePlan.PlanFinding.duplicateCueIndices (gdb u8r1
    /// review note 1).
    func overlay(at ptsSeconds: Double, surfaceIsHDR: Bool) -> OverlayAnswer {
        if surfaceIsHDR { return .hdrUnsupported(planRevision: planRevision) }
        // Q4: all cues covering pts (half-open); latest-starting wins, the
        // rest are reported as suppressed - never stacked or merged.
        // TIE RULE (peer-confirmed 2026-11-01 via coordination): among cues
        // with the SAME latest start, the one FIRST IN TRACK ORDER wins; the
        // rest are suppressed. Swift's max(by:) keeps the first maximal
        // element, so the rule is deterministic and track-order-stable.
        // Aligned with SubtitleSchedule.activeCue, which also keeps the FIRST
        // maximal (strictly-greater replacement) - no drift between the two
        // winner paths (gdb u8r1 review note 4, noted not changed).
        let covering = track.cues.filter { $0.startSeconds <= ptsSeconds && ptsSeconds < $0.endSeconds }
        guard let winner = covering.max(by: { $0.startSeconds < $1.startSeconds }) else {
            return .empty(planRevision: planRevision)
        }
        let suppressed = covering.filter { $0.index != winner.index }.map { $0.index }.sorted()
        return .cue(winner, suppressedCueIndices: suppressed, planRevision: planRevision)
    }
}

/// STYLE/RENDER REQUIREMENTS R1-R6 for gdb's rasterizer. Scope label per
/// gdb's own request (peer-attributed via coordination): accepted as gdb
/// MAIN-SIDE ENGINEERING scope, NOT an owner or architect ruling. The parser
/// data behind each is ALREADY shipped and execution-verified:
///
/// R1 Honor the line structure: SubtitleCue.lines are explicit line breaks
///    (SRT newlines; ASS \N and \n both became breaks at parse time; \h is a
///    non-breaking space U+00A0 already materialized in the text).
/// R2 Honor the per-cue style ASSOCIATION (SubtitleCue.styleName) against the
///    plan's style table: name, fontName, fontSize, primaryColourARGB
///    (decoded AARRGGBB from ASS &HAABBGGRR). That is the full parsed style
///    scope - bold/italic/outline/shadow/margins/alignment are NOT parsed and
///    MUST NOT be invented by the renderer.
/// R3 PlayRes (plan.playResX/playResY, carried through the loader) is the
///    layout reference frame; scaling to the drawable is renderer-side.
///    Missing PlayRes: renderer uses its default and says so.
/// R4 UNSUPPORTED, never silently rendered: every cue listed in
///    track.unsupportedOverrides carries ASS override tags (\pos, \move, \fad,
///    \clip, karaoke, drawing, ...) that were reported, not interpreted. The
///    renderer must show the cue's PLAIN TEXT and MUST NOT apply those
///    effects; the not-rendered record stays queryable on the plan.
/// R5 override-only events never reach the plan (typed refusal at parse);
///    malformed styles are visible in track.skippedStyles and are not
///    available to the renderer.
/// R6 Timing is the half-open interval [startSeconds, endSeconds) in media
///    seconds; one active cue per pts (latest-starting wins on overlaps).
///    Multi-cue stacking is OUT of v1 scope (interface question Q4 below).
///
/// INTERFACE QUESTIONS - RESOLVED per gdb's 2026-11-01 engineering decision
/// as relayed via coordination (peer-attributed, unverified by us against an
/// authenticated gdb record; recorded here for traceability):
/// Q1 per the relayed decision: the two-part revision (contentID + producer monotonic
///    generation, typed exhaustion, single-producer restart seeding). A->B->A
///    yields a new generation. Reissue semantics decided: same contentID with
///    a new generation IS a new revision and must re-admit (Q2 text).
/// Q2 per the relayed decision: the existing three-point seam stays UNWIDENED and echoes the
///    GENERATION only; authority registration is session-scoped (sessionID +
///    sessionGeneration); equality is sufficient; contentID stays plan-side;
///    the render cache MAY key on contentID. Verified seam pins cited above.
/// Q3 per the relayed decision: OPTION A evictThenBareNotify (P1 typed whole-present refusal;
///    P2 commit checks the registered authority; P3/P4 typed eviction +
///    counted bare re-render; staleOverlayEvicted receipt edge). Presenter
///    side; producer guarantees noted above. A later override must be an
///    explicit policy; undecided production refuses.
/// Q4 per the relayed decision: half-open [start,end); single active render = latest-starting
///    cue; suppressed cue indices reported as a typed finding; no stacking
///    or line merging (margins/alignment unparsed - stacking would invent
///    geometry; revisit when parsing lands).
/// Q5 per the relayed decision: three spaces - ASS PlayRes reference metrics (declared
///    default 384x288 with usedDefaultPlayRes receipt when absent); layout
///    in drawable pixels (font scales by drawableHeight/playResY; declared
///    default bottom-center, margin fraction 0.05); presenter Int frame
///    pixels via rendererAspectFit with reported placement. Only the
///    PlayRes metrics + default declaration are this lane's; the rest is
///    renderer-side (gdb).
