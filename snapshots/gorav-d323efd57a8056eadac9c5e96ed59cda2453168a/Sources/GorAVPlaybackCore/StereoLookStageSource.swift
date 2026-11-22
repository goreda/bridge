import Foundation
@_exported import StereoLookNativeContract

// P29-STEREO-LOOK stage-binding source (lane: stereo/photon): the
// per-frame SOURCE half of the stereo stage-binding adoption gap on the
// isolated composition. It drives StereoLookFramePayload.produce (Ops
// frame-payload v2 packet) from EXPLICIT host state and answers the
// binding's per-frame question: a fresh payload, an unchanged frame, or
// a closed gate.
//
// Boundaries (all pinned, none invented):
//  - Host geometry/controls/session/tune are EXPLICIT inputs per frame,
//    carried as one StereoLookHostState. This source holds no host
//    state of its own, invents no default pose, geometry or aspect, and
//    never derives the 180/360 layout discrimination (session
//    authority).
//  - Supported outcome contract (Z4C adversarial evidence, explicit):
//    .unchanged is reported ONLY for an exact replay of the last
//    accepted (frame, stageGeneration, host) triple - frame/stage
//    identity always receives its own admissible explicit binding, so
//    host-state equality alone NEVER suppresses a new frame or stage
//    generation. .gated is per-frame consistent: EVERY frame arriving
//    while the publication gate is closed reports .gated (gate state
//    is not deduped), the block stays bit-identical, and accepted
//    state is not displaced. A refusal leaves accepted state untouched,
//    so a corrected or repeated host state retries faithfully.
//  - A producer refusal propagates typed and leaves the source's last
//    accepted state untouched, so a corrected host state can retry.
//  - TITLE: this source binds NO title path. title_r stays unbound
//    (.noTitleSourceBound) until a real carrier proof exists (an
//    upload-path caller plus an equivalence witness); the host-approx
//    helper is diagnostic only and is deliberately not reachable here.
//  - The runtime owner (VRRuntimeOwner/StereoProjectionMetal) is
//    preserved whole: this source never publishes, acknowledges, or
//    mutates it; the shadow stays diagnostic-only.
//
// Depends on the Ops frame-payload v2 packet (StereoLookFramePayload,
// same module). INERT until Ops composes the binding; App registration
// is owned elsewhere.

// The seam's public value-type contract (StereoLookSession/Controls/
// Geometry/Tune, StereoLookHostState, StereoLookHostInput,
// StereoLookPullContext, StereoLookRestrictedProjectionAdmission and
// StereoLookDistanceTrace) now lives in the StereoLookNativeContract
// module (architecture facade r1) and is re-exported here so every
// existing GorAVPlaybackCore consumer compiles unchanged. The
// NativeStereoAdmission SPI is NOT re-exported: capability
// construction/restamp still requires an explicit
// @_spi(NativeStereoAdmission) import of StereoLookNativeContract.

public enum StereoLookFrameOutcome: Equatable {
    /// A fresh payload was produced at this block revision.
    case produced(ParameterBlockRevision)
    /// Host state identical to the last accepted state: no production,
    /// matching the authority's payload dedupe.
    case unchanged
    /// The publication gate is closed (pin c455d945 l.632): nothing
    /// produced, block untouched; the binding should keep the stage
    /// uninstalled.
    case gated
}

public final class StereoLookStageSource<FrameKey: Equatable> {
    /// The stage's live block. Mutated only through the payload
    /// adapter's atomic produce.
    public private(set) var block: LookParameterBlock
    /// The revision of the last produced payload, for the binding's
    /// admission dedupe.
    public private(set) var lastProducedRevision: ParameterBlockRevision?
    private var lastFrame: FrameKey?
    private var lastStageGeneration: UInt64?
    private var lastHost: StereoLookHostState?

    public init(block: LookParameterBlock = LookParameterBlock()) {
        self.block = block
    }

    /// Answers one frame. See the file header for the exact outcome
    /// semantics; no outcome mutates anything it must not.
    @discardableResult
    public func framePayload(frame: FrameKey, stageGeneration: UInt64,
                             host: StereoLookHostState) throws
        -> (StereoLookFramePayload<FrameKey>?, StereoLookFrameOutcome) {
        if let lastFrame, let lastStageGeneration, let lastHost,
           lastFrame == frame, lastStageGeneration == stageGeneration, lastHost == host,
           lastProducedRevision == block.revision {
            return (nil, .unchanged)
        }
        guard let payload = try StereoLookFramePayload<FrameKey>.produce(
            block: &block, frame: frame, stageGeneration: stageGeneration,
            session: host.session, controls: host.controls,
            geometry: host.geometry, tune: host.tune) else {
            return (nil, .gated)
        }
        self.lastFrame = frame
        self.lastStageGeneration = stageGeneration
        lastHost = host
        lastProducedRevision = block.revision
        return (payload, .produced(block.revision))
    }

    /// Stage teardown/rebind: forgets the last accepted frame identity
    /// and host state so the next frame reports faithfully. The block's
    /// values and revision are the block owner's call, not this
    /// source's.
    public func resetFrameState() {
        lastFrame = nil
        lastStageGeneration = nil
        lastHost = nil
    }
}
