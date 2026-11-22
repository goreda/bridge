import Foundation

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

/// One frame's complete explicit host state. Memberwise only: every
/// field is supplied by the host at this boundary. A host with
/// unresolved live state (missing tune/baseIpd authority) does NOT
/// vend this state at all (bounded admission correction, Ops
/// producer/payload + stage witnesses): the complete input is stopped
/// at the adapter boundary instead of widening this contract with
/// optional lanes - omission is not withholding, since the payload
/// serializes the whole block.
public struct StereoLookHostState: Equatable {
    public var session: StereoLookSession
    public var controls: StereoLookControls
    public var geometry: StereoLookGeometry
    public var tune: StereoLookTune
    public init(session: StereoLookSession, controls: StereoLookControls,
                geometry: StereoLookGeometry, tune: StereoLookTune) {
        self.session = session; self.controls = controls
        self.geometry = geometry; self.tune = tune
    }
}

/// A restricted native projection capability, not lane diagnostics.
/// Only the native-admission SPI can construct or restamp this value. The app
/// adapter supplies it after checking current original-source evidence,
/// explicit SBS/TB -> VR180 intent, explicit head-Off/blink-Off, and its
/// successful synchronous owner batch. Generic HostInput construction has none.
/// This API boundary is not authentication against deliberately hostile code
/// that opts into an implementation SPI.
public struct StereoLookRestrictedProjectionAdmission: Equatable, Sendable {
    public enum SourceFormat: String, Equatable, Sendable { case vr180SBS, vr180TB }
    public let admissionID: UUID
    public let session: UUID
    public let source: String
    public let sourceGeneration: UInt64
    public let acceptanceEpoch: UInt64
    public let acceptedStoreRevision: UInt64
    public let sourceFormat: SourceFormat
    public let sourceID: String
    public let sourceInventorySession: UInt64
    public let sourceInventoryRevision: UInt64
    public let sourcePresentationEpoch: UInt64
    public let selectedVideoIndex: Int
    public let uncroppedWidth: Int
    public let uncroppedHeight: Int

    @_spi(NativeStereoAdmission)
    public init(session: UUID, source: String, sourceGeneration: UInt64,
                acceptanceEpoch: UInt64, acceptedStoreRevision: UInt64,
                sourceFormat: SourceFormat, sourceID: String, sourceInventorySession: UInt64,
                sourceInventoryRevision: UInt64, sourcePresentationEpoch: UInt64,
                selectedVideoIndex: Int, uncroppedWidth: Int, uncroppedHeight: Int,
                admissionID: UUID = UUID()) {
        self.admissionID = admissionID; self.session = session; self.source = source
        self.sourceGeneration = sourceGeneration; self.acceptanceEpoch = acceptanceEpoch
        self.acceptedStoreRevision = acceptedStoreRevision; self.sourceFormat = sourceFormat
        self.sourceID = sourceID; self.sourceInventorySession = sourceInventorySession
        self.sourceInventoryRevision = sourceInventoryRevision
        self.sourcePresentationEpoch = sourcePresentationEpoch
        self.selectedVideoIndex = selectedVideoIndex
        self.uncroppedWidth = uncroppedWidth; self.uncroppedHeight = uncroppedHeight
    }

    public func matches(session: UUID, source: String, sourceGeneration: UInt64?,
                        acceptanceEpoch: UInt64) -> Bool {
        self.session == session && self.source == source &&
        self.sourceGeneration == sourceGeneration && self.acceptanceEpoch == acceptanceEpoch &&
        selectedVideoIndex >= 0 && uncroppedWidth > 0 && uncroppedHeight > 0
    }

    /// Only an already accepted capability can follow a safe manual command.
    @_spi(NativeStereoAdmission)
    public func advancing(to epoch: UInt64) -> Self? {
        guard epoch > acceptanceEpoch else { return nil }
        return Self(session: session, source: source, sourceGeneration: sourceGeneration,
            acceptanceEpoch: epoch, acceptedStoreRevision: acceptedStoreRevision,
            sourceFormat: sourceFormat, sourceID: sourceID,
            sourceInventorySession: sourceInventorySession,
            sourceInventoryRevision: sourceInventoryRevision,
            sourcePresentationEpoch: sourcePresentationEpoch,
            selectedVideoIndex: selectedVideoIndex, uncroppedWidth: uncroppedWidth,
            uncroppedHeight: uncroppedHeight, admissionID: admissionID)
    }
}

/// One pulled host input: the accepted state plus the custody the pull
/// must preserve (Ops v4 review: custody must not be stripped at the
/// provider boundary). session/source identify the accepting native
/// input owner; acceptanceEpoch is its monotonic acceptance counter.
/// The presenter retains the last custody it drove for stage-accept
/// diagnostics; it never derives authority from it.
public struct StereoLookHostInput: Equatable {
    public var state: StereoLookHostState
    public var session: UUID
    public var source: String
    public var acceptanceEpoch: UInt64
    /// Generic input has no restricted-projection capability by default.
    public var sourceGeneration: UInt64?
    public var restrictedProjectionAdmission: StereoLookRestrictedProjectionAdmission?
    /// Lane-status visibility, DIFFERENTIATED (Ops clarification:
    /// valid categories are accepted current-origin values, explicitly
    /// reviewed native-policy constants, and missing live routes -
    /// never one undifferentiated list):
    /// WITHHELD lanes: missing or unaccepted live routes. While ANY
    /// exists the host must not vend a complete input at all (bounded
    /// admission correction, Ops witnesses) - so on a vended input
    /// this list is empty by construction; it names the class, and
    /// the owner's own admissionBlockers diagnostic carries the live
    /// blockers. (baseIpd: unsupported live state, the persisted mm
    /// dial is loud-refused and cannot become an accepted zero, 199bm
    /// 4.2; tune: no Swift set-tune producer, listed until both
    /// set-tune lanes are accepted OR Ops reviews fixed tuning as a
    /// versioned candidate policy.)
    public var withheldLanes: [String]
    /// POLICY-CONSTANT lanes: grounded native-policy constants that
    /// ARE applied while listed (calibration 0: retired-feature
    /// policy, Control.swift l.2259; crop full-eye: constant by
    /// design, VR180Controller l.381-385; pose: neutral-reset policy,
    /// LookToolsRoute l.56-60, listed only until all four pose fields
    /// were actually supplied - per-field provenance, an empty
    /// orientation supplies no authority). Pose/tune may additionally
    /// be reviewed as versioned candidate policies separately.
    public var policyConstantLanes: [String]
    /// full182 geom-trace transport (block182 owner order item 2: log d, s,
    /// the clamp flag and each fallback reason): the owner's per-pull
    /// distance evaluation VERBATIM, or nil when the vend did not evaluate
    /// a distance (admission-neutral; never an admission input, never
    /// consulted for authority - a trace is visibility, never validated).
    public var distanceTrace: StereoLookDistanceTrace?
    public init(state: StereoLookHostState, session: UUID, source: String,
                acceptanceEpoch: UInt64, withheldLanes: [String] = [],
                policyConstantLanes: [String] = [], sourceGeneration: UInt64? = nil,
                restrictedProjectionAdmission: StereoLookRestrictedProjectionAdmission? = nil,
                distanceTrace: StereoLookDistanceTrace? = nil) {
        self.state = state; self.session = session
        self.source = source; self.acceptanceEpoch = acceptanceEpoch
        self.sourceGeneration = sourceGeneration
        self.restrictedProjectionAdmission = restrictedProjectionAdmission
        self.withheldLanes = withheldLanes
        self.policyConstantLanes = policyConstantLanes
        self.distanceTrace = distanceTrace
    }
}

/// One pull's PHYSICAL viewport/display context (Path A, Ops 8:11:41
/// consolidated review): sampled synchronously by the PRESENTER - the
/// owning source - on its own actor at the instant of the per-frame
/// pull, never from a queued callback's cached claim. A non-nil value
/// is constructed ONLY when ALL hold: the attached view is in a
/// window; its CURRENT backing geometry EQUALS the geometry the
/// renderer last ADMITTED (the noteGeometryChange .applied response,
/// MetalRenderer l.1195-1246) - a layer assignment queued ahead of
/// renderer admission is a mismatch, never a sample; and the actual
/// attached display identity resolved. A nil context at the provider
/// means detached/mismatch/unresolved: the pull vends nil
/// (missing-context nil admission; an ABSENT or unimplemented source
/// never falls back).
public struct StereoLookPullContext: Equatable {
    /// Attached-view backing pixel size (convertToBacking of the
    /// current bounds), verified equal to the renderer's admitted
    /// geometry at the sample instant.
    public var widthPx: Int
    public var heightPx: Int
    /// The actual attached display (NSScreenNumber). Non-optional: a
    /// context without display identity is never vended.
    public var displayID: UInt32
    /// DISPLAY-BOUND mm/px (CGDisplayScreenSize/pixelWidth of
    /// displayID, the Sensing VRDistance.mmPerPx formula l.71-74
    /// parameterized by the SAMPLED display). NIL = bound but
    /// unavailable: the consumer's documented panel fallback applies
    /// (Lua l.349/360, labeled "macbook-227ppi").
    public var mmPerPx: Double?
    public init(widthPx: Int, heightPx: Int, displayID: UInt32, mmPerPx: Double?) {
        self.widthPx = widthPx; self.heightPx = heightPx
        self.displayID = displayID; self.mmPerPx = mmPerPx
    }
}

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
