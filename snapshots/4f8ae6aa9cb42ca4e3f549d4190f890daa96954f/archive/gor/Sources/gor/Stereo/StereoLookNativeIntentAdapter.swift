import Foundation
@_spi(NativeStereoAdmission) import GorAVPlaybackCore
#if canImport(GorAVEmbeddedShell)
import GorAVEmbeddedShell
#endif

/// Ordinary Store intent to the native input owner. No mpv receipts or applied
/// snapshots enter this seam. Revision suffixes on the old string route are not
/// its fence: the actual current Store snapshot and revision are checked here.
@MainActor final class StereoLookNativeIntentAdapter {
    private var boundOrigin: StereoLookCommandOrigin?
    private var lastRevision: UInt64?
    private struct Intent: Equatable {
        let plan: ThreeDPresentationPlan
        let sourceIsExplicit: Bool
        let effects: ThreeDGlobalEffects
        init(_ state: ThreeDState) {
            plan=ThreeDPresentationPlan.make(state: state)
            sourceIsExplicit=state.current.userSource == true
            effects=state.effects
        }
    }
    private var lastIntent: Intent? // Intent dedupe only, never applied truth.
    private var lastEvidence: NativeStereoEntryReceipt?

    /// full182 tune dispatch: the pinned Lua DEFAULT tune lanes, dispatched
    /// explicitly at entry so the owner's admission can complete (its gate
    /// blocks an unset tune). Values are exactly today's #define defaults -
    /// VR_PARALLAX_CORRECTION_STRENGTH 0.4 (pin c455d945 l.125), DISPARITY
    /// = strength * -1 (l.129) - identical to the shader's own constants
    /// (StereoProjectionPass PARALLAX_CORRECTION_*), so the owner's excess
    /// recomputation matches the shader's and a default tune changes no
    /// output. This is the FIXED-TUNING native-policy candidate the owner
    /// header names; it is declared here so Ops review sees it as a
    /// versioned policy, not a hidden default. A future live tune control
    /// replaces these two commands with per-key current-origin dispatch.
    private static let tuneParallaxStrengthPolicy = 0.4
    private static let tuneParallaxDisparityPolicy = -0.4

    func reset(origin: StereoLookCommandOrigin?) {
        boundOrigin=origin; lastRevision=nil; lastIntent=nil; lastEvidence=nil
    }

    func hasAcceptedSourceEvidence(_ receipt: NativeStereoEntryReceipt) -> Bool {
        lastEvidence == receipt
    }

    /// Current Store/source checks for the projection capability at EVERY pull,
    /// including revisions whose unsupported intent was not accepted by apply.
    func hasCurrentRestrictedProjectionIntent(_ receipt: NativeStereoEntryReceipt,
        state: ThreeDState, revision: UInt64, origin: StereoLookCommandOrigin) -> Bool {
        guard boundOrigin == origin, lastEvidence == receipt, lastRevision == revision,
              let accepted = lastIntent, accepted == Intent(state),
              accepted.sourceIsExplicit, accepted.plan.output == .vr180,
              accepted.plan.engine == .nativeVR180, accepted.plan.pack == 0,
              [.vr180SBS, .vr180TB].contains(accepted.plan.filmSource.format),
              accepted.effects[.head] == .bool(false), accepted.effects[.blink] == .bool(false)
        else { return false }
        return true
    }

    @discardableResult
    func apply(state: ThreeDState, effects: [ThreeDEffect], revision: UInt64,
               currentState: ThreeDState, currentRevision: UInt64,
               receipt: NativeStereoEntryReceipt, receiptIsCurrent: Bool,
               origin: StereoLookCommandOrigin, filmID: FilmID,
               owner: StereoLookNativeInputOwner) -> String? {
        guard boundOrigin == origin, owner.matchesOrigin(origin) else { return "native entry: stale source origin" }
        guard receiptIsCurrent, origin.source == receipt.playbackMediaID else { return "native entry: stale opened-source evidence" }
        guard state.currentFilm == filmID else { return "native entry: original film binding mismatch" }
        guard revision == currentRevision, state == currentState,
              lastRevision == nil || revision >= lastRevision! else { return "native entry: stale Store revision or snapshot" }
        let intent=Intent(state)
        if lastRevision == revision, let prior=lastIntent, prior != intent {
            return "native entry: conflicting same-revision intent"
        }
        guard !effects.contains(.resetView) else { return "native entry: reset-view intent unavailable" }
        // Current but unsupported intent must not retain the old projection
        // capability. Stale origin/revision refusals above remain non-mutating.
        owner.invalidateRestrictedProjectionAdmission()
        let plan=ThreeDPresentationPlan.make(state: state)
        // Off is a bound safety exit, not an assertion of a supported output.
        if plan.output == .off {
            if let why=owner.accept(.setEnabled(false), origin: origin) { return why }
            commit(state, revision, receipt)
            return nil
        }
        guard !receipt.prepared, receipt.originalMediaID == receipt.playbackMediaID else {
            return "native entry: prepared-source enabled plan unavailable"
        }
        guard plan.output == .vr180, plan.engine == .nativeVR180,
              state.current.userSource == true,
              [.vr180SBS, .vr180TB].contains(plan.filmSource.format),
              plan.pack == 0, state.renderedSource == nil, state.renderedOutput == nil,
              state.renderedAspect == nil else {
            return "native entry: only explicit original native VR180 SBS/TB to VR180 is supported"
        }
        let fx=state.effects
        guard fx[.head] == .bool(false), fx[.blink] == .bool(false) else {
            return "native entry: camera tools unavailable; native viewer-camera consumer path is not integrated"
        }
        guard fx[.surroundInvert] == .bool(false) else { return "native entry: surround inversion unavailable" }
        guard fx[.quality] == .text("auto"), fx[.osdLine] == .bool(true),
              fx[.headInvert] == nil || fx[.headInvert] == .bool(false) else {
            return "native entry: requested ancillary effect unavailable"
        }
        guard case let .bool(cross)?=fx[.crossEye],
              case let .number(ipdMM)?=fx[.ipd], ipdMM.isFinite,
              case let .number(strength)?=fx[.strength], strength.isFinite,
              case let .number(depth)?=fx[.screenDepth], depth.isFinite, depth > 0,
              case let .number(size)?=fx[.screenSize], size.isFinite, size > 0,
              case let .text(surround)?=fx[.surround], ["soft", "black"].contains(surround)
        else { return "native entry: required effect intent absent or invalid" }
        let facts=receipt.evidence
        guard facts.selectedVideoIndex >= 0, !facts.attachedPicture,
              facts.uncroppedWidth > 0, facts.uncroppedHeight > 0 else {
            return "native entry: selected source geometry unavailable or attached picture"
        }
        // Preserve the current VR180Controller.knownEyeAspect spherical basis.
        // PAR is carried as optional source evidence, not defaulted to 1. That
        // legacy spherical basis uses uncropped width/height/2 for both kinds.
        let aspect=Double(facts.uncroppedWidth)/Double(facts.uncroppedHeight)/2
        guard aspect.isFinite, aspect > 0 else { return "native entry: invalid uncropped aspect" }
        let p=ThreeDAutoRoute.previewParams(mode: plan.output.rawValue,
            strength: strength, screenDepthM: depth, screenDeg: size, surround: surround)
        guard [p.gain, p.conv, p.zoom, p.soft].allSatisfy({ $0.isFinite }) else {
            return "native entry: invalid derived pack intent"
        }
        if lastRevision == revision, lastEvidence == receipt, !effects.contains(.reapply) {
            return sealRestrictedProjectionAdmission(receipt: receipt, revision: revision,
                origin: origin, plan: plan, aspect: aspect, owner: owner)
        }
        // Every value and fence is checked before the first mutation. This
        // synchronous batch cannot interleave an adoption or Store revision.
        var commands: [StereoLookNativeCommand] = []
        let routeChanged=lastIntent.map { $0.plan != plan } ?? true
        if routeChanged { commands.append(.setEnabled(false)) }
        commands += [
            .setProjection(kind: plan.luaKind, aspect: aspect),
            .setPack(pack: plan.pack, gain: p.gain, conv: p.conv, zoom: p.zoom, soft: p.soft),
            .toolsActive(false), // Both requested consumers are explicitly off.
            .setSwapEyes(cross != plan.filmSource.swap), .viewingCross(cross),
            .setTuneParallaxStrength(Self.tuneParallaxStrengthPolicy),
            .setTuneParallaxDisparity(Self.tuneParallaxDisparityPolicy),
            .setIpdMM(ipdMM), .setEnabled(true)
        ]
        for command in commands {
            if let why=owner.accept(command, origin: origin) {
                _ = owner.accept(.setEnabled(false), origin: origin)
                return "native entry: validated batch refused: " + why
            }
        }
        commit(state, revision, receipt)
        return sealRestrictedProjectionAdmission(receipt: receipt, revision: revision,
            origin: origin, plan: plan, aspect: aspect, owner: owner)
    }

    /// Reached only AFTER all real current-source/explicit-Off guards above.
    private func sealRestrictedProjectionAdmission(receipt: NativeStereoEntryReceipt,
        revision: UInt64, origin: StereoLookCommandOrigin, plan: ThreeDPresentationPlan,
        aspect: Double, owner: StereoLookNativeInputOwner) -> String? {
        let facts = receipt.evidence
        let format: StereoLookRestrictedProjectionAdmission.SourceFormat =
            plan.filmSource.format == .vr180TB ? .vr180TB : .vr180SBS
        let admission = StereoLookRestrictedProjectionAdmission(
            session: origin.session, source: origin.source, sourceGeneration: origin.generation,
            acceptanceEpoch: owner.acceptanceEpoch, acceptedStoreRevision: revision,
            sourceFormat: format, sourceID: facts.identity.sourceID,
            sourceInventorySession: facts.identity.session,
            sourceInventoryRevision: facts.identity.revision,
            sourcePresentationEpoch: facts.identity.presentationEpoch,
            selectedVideoIndex: facts.selectedVideoIndex,
            uncroppedWidth: facts.uncroppedWidth, uncroppedHeight: facts.uncroppedHeight)
        return owner.acceptRestrictedProjectionAdmission(admission, origin: origin,
            expectedKind: plan.luaKind, expectedAspect: aspect)
    }

    private func commit(_ state: ThreeDState, _ revision: UInt64, _ evidence: NativeStereoEntryReceipt) {
        lastIntent=Intent(state); lastRevision=revision; lastEvidence=evidence
    }
}
