import Foundation

// StereoLookNativeContract (lane: stereo/photon; architecture facade r1):
// the PUBLIC value-type contract of the native stereo-look host-input seam,
// published as a library product so the app target consumes these types
// through a declared product dependency instead of importing GorAVPlaybackCore
// internals (owner RTF 2dd findings: edge:GorAVPlaybackCore and
// gorav-internal:GorAVPlaybackCore on StereoLookNativeInputOwner.swift and
// StereoLookNativeIntentAdapter.swift). Pure value types and Foundation only;
// this module depends on NO gorav-internal module. The NativeStereoAdmission
// SPI (restricted-admission construction and epoch restamp) is preserved on
// the same declarations, unchanged: the facade publishes the contract; it
// does not widen who may construct or restamp a capability, and no algorithm,
// tune or trace value changes. Declarations below are byte-verbatim moves
// from GorAVPlaybackCore/StereoLookProducer.swift (4 structs) and
// GorAVPlaybackCore/StereoLookStageSource.swift (4 types); the distance trace
// lives in StereoLookDistanceTrace.swift in this same module, moved whole.

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
