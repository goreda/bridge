// Native-entry-v1 successor to owner14. Default initialization still withholds
// tune exactly as v2 did. A host may explicitly select the source-grounded
// shippedLuaPair initialization, with separate policy labels until each real
// per-key tune command replaces it. Historical owner14 mechanics follow.
// StereoLookNativeInputOwner.swift - CANDIDATE v14: the REAL native owner
// of stereo-look host INPUT on the embedded host. App target, alongside
// GorAVPlayerHost. Lane: stereo/photon. v14 keeps v13's FULL block182
// distance/base-ipd contract and owner-local mm->NDC conversion
// (model/parser mechanics retained per Ops 8:11:41) and replaces the
// v13 viewport CUSTODY channel with PATH A: pull-time synchronous
// same-actor sampling of the actual attached view, carried in the
// package type StereoLookPullContext (StereoLookStageSource.swift,
// GorAVPlaybackCore; package patch pull-model v8). The bounded-admission
// mechanics of v12 are PRESERVED (Ops witness
// photon-v11-stage-withholding-witness.tar-9b07d8e3: omission is not
// withholding; the established complete 33-lane producer, the
// FramePayload contract, the qualified suite and the package types stay
// unchanged). Pair with: parser v3 (set-ipd-mm accepted),
// host patch v9 (real clock + context-forwarding provider),
// package patch pull-model v8 (context sampling + fences).
//
// v13 -> v14, per Ops consolidated review 8:11:41 (witness-executed):
// - REMOVED: acceptViewport, StereoLookViewportCustody,
//   drawableGeneration, displayID custody, display-change mmPerPx
//   clearing. Ops witnesses showed the callback-custody channel fail
//   three ways (stale display A overwrote B; contradictory width
//   accepted at the same generation; pre-adoption viewport entered
//   sourceB), and its displayID/generation fields had NO real
//   producer. This removal does NOT lower the correctness boundary:
//   the boundary moved INTO the pull contract - no valid context, no
//   vended input (missing-context nil admission).
// - Viewport + display scale now arrive per pull in the
//   StereoLookPullContext sampled by the PRESENTER (the owning
//   source) at the pull instant; see the package patch for the
//   sampling guarantees (attached-view backing geometry verified
//   EQUAL to the renderer's last admitted geometry, display identity
//   from the actual window screen). A nil context at pullInput means
//   detached/mismatch/unresolved and vends nil - an ABSENT or
//   unimplemented source NEVER falls back.
// - Bound-but-unavailable scale (display resolved, CGDisplay metrics
//   unavailable) MAY fall back to the MacBook panel constant
//   (25.4/227, Lua l.349/360), labeled "macbook-227ppi".
// - The orientation-command mmPerPx slot (arg 11, Sensing
//   main-display-only) is DIAGNOSTIC-ONLY on the native route (Ops
//   8:11:41): it is still stored in distanceCustody for parity with
//   the wire format and surfaced as orientationScaleSlot, but the
//   evaluation NEVER consumes it.
// - Ops arithmetic review caveat PRESERVED: at the 500 mm floating
//   equality boundary, the capped flag can differ from the LuaJIT
//   reference (18/1400 seed-fixed cases); infeasible/capMet/reason
//   match. No oracle, tolerance or rounding changed here; the
//   producer is preserved whole.
// - Ops extreme-input witness PRESERVED: width 1 with a
//   greatestFiniteMagnitude dial yields a nonfinite raw base; the
//   unchanged producer rejects nonfinite controls, so no wrong-pixel
//   claim is made (outside ordinary UI limits).
//
// Ops 7:53:35 hazard resolutions (each grounded in the cited source):
// (H1) The Sensing producer emits only the EXPLICIT reason
//     "fov-unavailable" (Sensing.swift l.1293-1301: cameraHFOVDegrees
//     is nil on macOS - prior intent evidence, NOT fresh native
//     verification); absence-of-integration never masquerades as a
//     producer reason: an empty custody evaluates as Lua's "no-input"
//     (l.352), and producer reasons pass through VERBATIM.
// (H2) Distance custody reason-clear parity (Lua l.1054-1057): a
//     supplied non-ok reason WITHOUT a positive dmm CLEARS the prior
//     distance sample (dist_in_d = nil); v12 retained the old mm,
//     which must NOT become algorithm. Implemented exactly.
// (H3) No-face hold expiry is evaluated on a FRESH monotonic clock at
//     every pull (buildInput(now:)), never cached in reassembly; and
//     an omitted distance slot NEVER refreshes the sample age (only a
//     positive dmm sets dist_in_at, Lua l.1054).
// (H4) NO DOUBLE FILTERING: the produced distance already passed the
//     Sensing one-euro channel fD (Sensing.swift l.221, l.1297-1299,
//     same tau as the fov channel, beta 0; block182 md.2 "filter d
//     through the same heavy one-euro channel"); this owner consumes
//     custody.mm VERBATIM and never re-filters - single filter
//     authority stays at the producer.
// (H5) Display/viewport matching - Path A (Ops 8:11:41): NO viewport
//     custody channel exists. The pull context supplies the
//     attached-view backing geometry AND the display identity AND the
//     display-bound scale, sampled atomically by the presenter at the
//     pull instant and verified against the renderer's last admitted
//     geometry. Main-display-only scale is never assumed; the
//     orientation-slot scale is diagnostic-only (see intro).
// (H6) Unknown/missing-route stays distinct from observed-unavailable:
//     admission blockers name MISSING LIVE ROUTES ("tune", "ipdDial",
//     "viewport"); producer-reported unavailability is a reason
//     string, never a blocker, and never fabricated by this owner.
// (H7) Native tune dispatch and ordinary embedded entry remain
//     real-source-custody gaps (199bm 4(3), PPController
//     refuseEmbedded gates) - unchanged, non-producing in harness.
//
// (0) BOUNDED PARTIAL CONTRACT (Ops 7:18:02, enforced per v9 review):
//     every lane is one of three classes, and the class is VISIBLE in
//     StereoLookHostInput.withheldLanes / .policyConstantLanes:
//     ACCEPT-REQUIRED (real native producer exists; must be accepted
//     under the CURRENT session+generation before any complete pull):
//     - enabled: setVRModeEnabled (VR180Controller l.474-478)
//     - projection: publishProjection (l.376-390)
//     - pack: store applier (l.324)
//     - toolsActive: refreshToolsActive (LookToolsRoute l.118-120)
//       from the REAL head/blink/loaded-file flags (l.42), fired on
//       every capture-consumer state change including each file load
//       (updateCaptureConsumers l.685, loadedVideoActive didSet l.63)
//     - swapEyes: sendSwapEyes on VR entry (l.481, l.511-513)
//     - viewingCross: store applier dispatch (l.328; the store's
//       effects carry crossEye by default, Control.swift l.139)
//     POLICY CONSTANT (reviewed/grounded native-policy constants -
//     no live source could contradict the value; applied as cited
//     constants and named in policyConstantLanes so they are never
//     mistaken for accepted authority):
//     - "pose": neutral 0/0/135/0, the app's OWN constant
//       (LookToolsRoute.neutralOrientationArgs l.56-60); leaves the
//       policy-constant list only once ALL FOUR pose fields (yaw, pitch,
//       fov, roll) have been supplied by accepted set-orientation
//       commands this session+generation - v9 cleared the label on an
//       all-nil command, which supplied no authority (Ops probe:
//       "all-nil orientation removed pose candidate true").
//     - "calibration": 0.0, retired-feature policy (shader
//       calibration mark retired, ThreeD/Control.swift l.2259); the
//       command is permanently refused at the parser.
//     - "crop": full eye (0,0,1,1), constant BY DESIGN at
//       publishProjection (VR180Controller l.381-385).
//     MISSING LIVE ROUTES - ADMISSION-BLOCKING (a live native source
//     exists or could exist, but no accepted value does; named in
//     admissionBlockers, and while any is unresolved the complete
//     input is STOPPED at the adapter boundary - the pull vends nil,
//     no payload is produced at all):
//     - "tune": user-adjustable live state (Ops 7:18:02 classes it
//       with live tune/tools); set-tune has NO Swift producer
//       (grep-verified). Lua pushes both parallax lanes together
//       (l.1217-1218), so BOTH set-tune lanes must be accepted. Ops
//       may separately review fixed tuning as a versioned candidate
//       policy; an explicit new constant policy is a separate review,
//       not a disguise for a missing live route. NUANCE FLAGGED TO
//       OPS (7:48:55): the excess formula uses the Lua defaults
//       0.4/-0.4 when tune is unset (Lua l.379-380 "or" branch) -
//       exact parity while no tune dispatch exists; not decided here.
//     - "ipdDial": the persisted mm dial (VR entry DOES dispatch
//       set-ipd-mm, sendPersistedBaseIPD l.507 -> publishBaseIPD
//       l.793-796). v13: accepted by parser v3 and converted HERE
//       (full contract below); blocks only until the dial actually
//       arrives this session+generation.
//     (v14: "viewport" is NO LONGER an admission blocker - it is
//     per-pull physical context (Path A); its absence makes the pull
//     vend nil for that frame, never a sticky blocker.)
//     The actual current host refuses vr180_look and has NO stereo-look
//     configuration holder (Ops native audit): nothing here is
//     recovered current applied state.
// (0b) NO PACKET DELTA: the established complete 33-lane producer, the
//     FramePayload contract, the qualified 33-lane suite and the
//     package types are PRESERVED (Ops witness: omission is not
//     withholding; no optional-output contract widening). The vended
//     input's baseIpd/appliedIpdBase lanes are filled ONLY at pull
//     time from the full contract evaluation below; while admission
//     is blocked no payload is produced at all.
// (0c) FULL block182 DISTANCE/BASE-IPD CONTRACT (Lua l.356-415,
//     Sensing.swift l.63-74, block182 md.2; every constant cited):
//     - half-width in mm: half_w = (viewportW/2) * mmpx / 2 where
//       mmpx = custody mmPerPx > 0 ? custody : 25.4/227 (Lua l.349,
//       l.359-360; block182: CGDisplayScreenSize=0 -> macbook value).
//     - parallax excess (Lua l.376-381, PARALLAX_CORRECTION_ENABLED
//       = true l.122): mag = tan(rad(90)/2) / tan(rad(clamp(fov +
//       manualFov, 22.5, layout<3 ? 179 : 157.5))/2) (ZOOM_REF 90
//       l.117, FOV_MIN l.51, fov_max l.55, FOV_MAX l.52);
//       excess = disparity_eff * (mag-1) * strength_eff with the
//       accepted tune lanes or the Lua defaults (l.125, l.129).
//     - today's separation (l.382-385): today_norm = excess +
//       ipdNudge + 0.0 (0.0 = today's base_ipd default l.345-347);
//       s_today = today_norm*half_w + VR_TODAY_BASE_IPD_MM(=0) +
//       offset_mm; ipd_eff = 63 + offset_mm (DEFAULT_IPD l.339).
//     - distance hold (l.386-394, HOLD 2.0 l.341): age = now -
//       sampleAt; age <= 0.5 reason "ok", age <= 2.0 "hold-last-d",
//       else d = nil and reason "no-face-hold-expired". Evaluated at
//       EVERY pull with the fresh monotonic clock (H3).
//     - vergence cap (l.395-398, REF 500 l.340): s_cap = (d/500) *
//       (ipd_eff + s_today) - ipd_eff; applied ONLY when it SHRINKS
//       the separation (s_cap < s_today). The clamp acts on the
//       COMBINED parallax+base+nudge separation - a base-only formula
//       is NOT parity for near input (Ops 7:46:08).
//     - shader feasibility clamp (l.399-402, LIMIT 0.8 l.350):
//       shift = s_requested/half_w clamped to +/-0.8, infeasible flag.
//     - applied base (l.404-405): vr_ipd_applied_base = shift -
//       excess - ipd_nudge; the pushed base is the applied one
//       (base_to_push l.641). Vended lanes: baseIpd = the raw dial
//       conversion offset_mm/half_w (Lua base_ipd, l.361),
//       appliedIpdBase = the post-clamp applied base (l.405).
//     - cap_met diagnostic (l.404): (no d) or ipd_eff + shift*half_w
//       <= (d/500)*(ipd_eff+s_today) + 1e-9.
//     - NO owner calibration step, ever (block182 md.2).
// (1) Whole-input availability = EVERY accept-required lane accepted
//     this session+generation AND enabled == true AND every missing
//     live route resolved (header 0) - i.e. admissionBlockers EMPTY.
//     Before that the pull vends nil: the typed route can land
//     partial, but there is NO complete input with unresolved live
//     state (Ops witness correction) and NO full stage admission with
//     unknown required inputs. The independent 2D tools path
//     (enabled=false with toolsActive=true) vends nil: it is OUTSIDE
//     this partial route, not covered.
// (2) set-ipd-mm is ACCEPTED (parser v3) and converted owner-locally
//     with the full contract (0c).
// (3) calibration is permanently refused at the parser.
// (4) ATOMIC VALIDATED ACCEPTANCE: accept() re-validates every
//     argument (finiteness, ranges, accumulation overflow) BEFORE any
//     mutation; a refusal leaves all lanes untouched. The owner
//     re-validates the projection kind against the wire whitelist
//     itself (typed-boundary defense in depth): an unknown kind is a
//     loud refusal, NEVER a silent layout 0.
// (5) LUA NUDGE PARITY (Ops probes, actual constants cited):
//     - a nudge while enabled != true is IGNORED SILENTLY, exactly
//       like vr180-look.lua l.1104 ("if not enabled then return end"):
//       no accumulation, no epoch bump, no refusal.
//     - manual_yaw clamps to +/-(pi / VR_YAW_CLAMP) with
//       VR_YAW_CLAMP = vr_f/4, vr_f = 45.0 (lua l.50, l.15) =
//       +/-(pi / 11.25).
//     - manual_pitch clamps to +/-deg2rad(85.0) (VR_PITCH_LIMIT_DEG =
//       VR_PITCH_DOWN_LIMIT_DEG = 85.0, lua l.48-49).
//     - manual_roll has NO clamp (lua l.1107 accumulates raw).
//     - manual_fov clamps to [VR_FOV_MIN - fov, vr_fov_max() - fov]
//       with VR_FOV_MIN = vr_f/2 = 22.5 (l.51) and vr_fov_max() =
//       source_layout < 3 ? 179.0 : VR_FOV_MAX (VR_FOV_MAX =
//       vr_f*3.5 = 157.5, l.52, l.55), evaluated against the CURRENT
//       fov lane and the CURRENT accepted layout; with no accepted
//       projection the flat bound 179.0 applies (lua source_layout
//       initial 0, l.24). The clamp bounds are pipeline constants of
//       the authority itself, cited per line - not invented.
//     - set-enabled(false) RESETS all four manual offsets to 0
//       (Ops v6 counterexample: the shipped Lua's disable path zeroes
//       manual_yaw/pitch/fov/roll - set-enabled route l.1004-1007 via
//       vr_file_off l.971 -> vr_full_fit l.976, and the route's own
//       reset at l.1015-16). toolsActive is deliberately NOT reset
//       here: the native tools overlay works with VR off
//       (LookToolsRoute refreshToolsActive l.118-120) and its lane is
//       recomputed from live flags by its own producer.
// (6) ORIGIN FENCE (Ops v5 finding: session token is NOT a source
//     fence): every command must carry a StereoLookCommandOrigin =
//     (session token, source path, source generation) captured by the
//     transport closure at install. The host owns a monotone
//     stereoLookSourceGeneration counter: beginSession increments it
//     and the adoption hook increments it again AND re-points the
//     embedded command closure, so a command queued before an adoption
//     carries the OLD (source, generation) and is refused after it -
//     no wire change, no new transport. QUALIFIED for the observed
//     synchronous transport only (Ops: store append/trim no
//     callback/await, PP embedded returns before queue, adoption
//     re-point plain state/no await) - not a universal queue-time
//     proof for arbitrary upstream queued strings. install() binds
//     all three; accept() refuses any mismatch or a missing origin,
//     loudly. A re-install drops EVERY lane (explicit loss), which is
//     how the session's onStereoSourceAdopted hook (pull-model patch
//     v5) resets this owner at same-session source adoption.
//     acceptanceEpoch is the owner's OWN monotone acceptance clock,
//     not a transported route revision (mpv revision machinery is
//     mpv-only, backlog-refused on this route).
// (7) Custody is never stripped: when admission passes, the pull
//     vends the PACKAGE type StereoLookHostInput (state + session +
//     source + acceptanceEpoch + withheldLanes + policyConstantLanes);
//     the presenter retains it for diagnostics
//     (pull-model patch v5).
// (8) EXECUTABLE-ROUTE HONESTY (Ops v9 review + live PPController
//     reread 07:25:43): the six-command entry sequence in the lane
//     tests is a SYNTHETIC MECHANICS FIXTURE, not ordinary native-UI
//     entry coverage. Ops traced the real PPController embedded entry
//     refusing BEFORE the VR controller and acceptEmbedded not running
//     recognition/applyThreeDState or the loaded-camera flags, so on
//     the ordinary native-UI path these typed commands may never reach
//     this owner - the pull then stays nil (visible partial state,
//     never wrong state). Production entry coverage is UNESTABLISHED
//     pending Ops' focused work; nothing here claims it.
//
// EXECUTOR: producer (handleChromeCommand) and consumer (presenter
// pull) are both @MainActor - same-actor, no lock, no async hop.
//
// UNRUN: no Mac/native compile here; Ops/Z4C qualify.

import Foundation
@_spi(NativeStereoAdmission) import GorAVPlaybackCore

/// Queue-time origin of one typed command (header 6): which host
/// session, which source, which source generation the command was
/// QUEUED under. Captured by the transport closure at install; never
/// derived at receipt time.
struct StereoLookCommandOrigin: Equatable {
    var session: UUID
    var source: String
    var generation: UInt64
}

/// DECLARED-CONSTANT initial values (header 0), DEFINED AND JUSTIFIED
/// AT THE HOST CALL SITE (file:line), validated here at install.
/// Accept-required IPD has no initial value. Tune is absent by default;
/// only the explicit shippedLuaPair policy opts into declared initialization.
enum StereoLookDeclaredTuneInitialization: Equatable {
    // vr180-look.lua: correction enabled, strength=0.4, disparity=-strength;
    // then copied independently into vr_tune at script initialization.
    case shippedLuaPair
}

struct StereoLookNativeInitial: Equatable {
    var poseYaw: Double
    var posePitch: Double
    var poseFov: Double
    var poseRoll: Double
    /// Retired-feature policy value, always 0.0 (ThreeD/Control.swift
    /// l.2259); no command can change it (parser refuses loud).
    var calibration: Double
    // Nil retains owner14/v2's withheld tune initialization exactly.
    var declaredTune: StereoLookDeclaredTuneInitialization? = nil

    var allFinite: Bool {
        [poseYaw, posePitch, poseFov, poseRoll, calibration]
            .allSatisfy { $0.isFinite }
    }
}

// v14: the viewport/display context type StereoLookPullContext lives
// in the PACKAGE (StereoLookStageSource.swift, GorAVPlaybackCore,
// package patch pull-model v8) because the presenter - the owning
// source - builds it. This owner consumes it only via pullInput.

/// One full-contract base evaluation (header 0c), computed at pull
/// time with a FRESH clock. Diagnostic surface for qualification and
/// for the shell's geom-trace equivalent (block182 md.2 logging: d,
/// s, clamp flag, fallback reason); not a recovery channel.
struct StereoLookBaseEvaluation: Equatable {
    var baseIpdRaw: Double       // offset_mm / half_w (Lua base_ipd, l.361)
    var appliedIpdBase: Double   // shift - excess - ipdNudge (Lua l.405)
    var distanceMM: Double?
    var sTodayMM: Double
    var sCapMM: Double?
    /// full182 D3: remaining Lua trace fields (pin c455d945 l.406-413),
    /// computed where the values already exist - never re-derived downstream.
    var sRequestedMM: Double
    var sTotalMM: Double
    var offsetMM: Double
    var ipdEffMM: Double
    var capped: Bool
    var infeasible: Bool
    var capMet: Bool
    var reason: String
    var mmPerPx: Double
    var mmPerPxSource: String    // "host-display-<id>" (bound sample) or "macbook-227ppi" (Lua l.349 fallback)
    /// DIAGNOSTIC ONLY (Ops 8:11:41): the orientation-command mmPerPx
    /// slot as accepted on the wire. NEVER consumed by the evaluation.
    var orientationScaleSlot: Double?
    var eyeWidthMM: Double
    var halfWidthMM: Double
}

@MainActor final class StereoLookNativeInputOwner {
    private(set) var installedSession: UUID?
    private(set) var installedSource: String?
    private(set) var installedGeneration: UInt64?
    private(set) var acceptanceEpoch: UInt64 = 0
    private var restrictedProjectionAdmission: StereoLookRestrictedProjectionAdmission?
    private var projectionSensorInputAccepted = false
    private var projectionEpochExhausted = false

    func invalidateRestrictedProjectionAdmission() {
        restrictedProjectionAdmission = nil
    }

    /// Called only by the native intent adapter after its accepted checked batch.
    /// Never turns generic owner completeness into an explicit-Off guarantee.
    func acceptRestrictedProjectionAdmission(_ admission: StereoLookRestrictedProjectionAdmission,
        origin: StereoLookCommandOrigin, expectedKind: String, expectedAspect: Double) -> String? {
        guard matchesOrigin(origin), !projectionSensorInputAccepted, !projectionEpochExhausted,
              admission.matches(session: origin.session, source: origin.source,
                  sourceGeneration: origin.generation, acceptanceEpoch: acceptanceEpoch),
              enabled == true, toolsActive == false, pack?.pack == 0,
              projection?.kind == expectedKind, projection?.aspect == expectedAspect,
              (admission.sourceFormat == .vr180SBS && expectedKind == "vr180") ||
              (admission.sourceFormat == .vr180TB && expectedKind == "vr180-tb") else {
            restrictedProjectionAdmission = nil
            return "native projection: accepted restricted-domain owner state unavailable"
        }
        restrictedProjectionAdmission = admission
        return nil
    }
    /// v14: there is NO context-free accepted input. The only vending
    /// path is pullInput(expectedSession:context:) with the live
    /// pull-time sample (Path A). NIL whenever admissionBlockers is
    /// non-empty (header 0/1) or the context is nil/invalid.
    /// Missing required live routes blocking admission right now
    /// (subset of ["tune", "ipdDial"], computed at every
    /// reassemble). Diagnostic only; not a recovery channel.
    private(set) var admissionBlockers: [String] = []
    /// Lane-status diagnostics (Ops taxonomy, differentiated):
    /// missing/unaccepted live routes vs reviewed policy constants.
    private(set) var withheldLanes: [String] = []
    private(set) var policyConstantLanes: [String] = []
    /// The derived session transform of the ACCEPTED lanes, exposed
    /// for qualification while the full input is admission-blocked
    /// (contains no missing-live-route field). Diagnostic only.
    private(set) var diagnosticSession: StereoLookSession?

    // -- ACCEPT-REQUIRED lanes (header 0 class A): UNKNOWN until
    //    accepted from a command this session+generation ------------
    private(set) var enabled: Bool?
    private(set) var projection: (kind: String, aspect: Double)?
    private(set) var pack: (pack: Int, gain: Double, conv: Double, zoom: Double, soft: Double)?
    private(set) var toolsActive: Bool?
    private(set) var swapEyes: Bool?
    private(set) var viewingCross: Bool?

    // -- POLICY-CONSTANT + accepted lanes ----------------------------
    private(set) var yaw = 0.0, pitch = 0.0, fov = 0.0, roll = 0.0
    private(set) var headX = 0.0, headY = 0.0, headZ = 0.0
    private(set) var ipdNudge = 0.0
    private(set) var nativeRawRoll: Double?
    private(set) var manualYaw = 0.0, manualPitch = 0.0, manualFov = 0.0, manualRoll = 0.0
    private(set) var calibration = 0.0
    /// Per-field pose acceptance (header 0, Ops v9 probe): an
    /// orientation command supplies authority ONLY for the fields it
    /// actually carries (Lua l.1036 nil = keep). The pose leaves the
    /// policy-constant list once ALL FOUR were supplied.
    private(set) var poseYawAccepted = false
    private(set) var posePitchAccepted = false
    private(set) var poseFovAccepted = false
    private(set) var poseRollAccepted = false

    // -- WITHHELD lanes (header 0): nil until accepted; never pushed
    //    while nil (packet delta (0b)) --------------------------------
    private(set) var tuneStrength: Double?
    private(set) var tuneDisparity: Double?
    private(set) var tuneStrengthAccepted = false
    private(set) var tuneDisparityAccepted = false
    /// The accepted session-scale IPD dial in anatomical mm (offset on
    /// the 63 mm default, block182 md.2; parser v3 set-ipd-mm, Lua
    /// l.1070-1075). nil until a dial command is accepted this
    /// session+generation; admission blocker "ipdDial" while nil.
    private(set) var ipdOffsetMM: Double?

    /// Distance-rule custody (H2/H3): the producer's one-euro-FILTERED
    /// distance (H4: consumed verbatim, never re-filtered), the
    /// monotonic accept-time of the last POSITIVE sample, the
    /// producer's verbatim reason, and the orientation-command mmPerPx
    /// slot - the slot is DIAGNOSTIC-ONLY (Ops 8:11:41): kept for wire
    /// parity, NEVER consumed by the evaluation (the display-bound
    /// scale arrives per pull in the context).
    private(set) var distanceCustody: (mm: Double?, at: Double?, reason: String?, mmPerPx: Double?)

    /// Fresh monotonic clock for hold evaluation at every pull (H3).
    /// Injected so qualification is deterministic; the shell supplies
    /// a real monotonic source. REQUIRED, never defaulted.
    private let clock: () -> Double

    /// Why the last install/accept refused, for diagnostics. Not a
    /// recovery channel: callers must not branch on the string.
    private(set) var lastRefusal: String?

    /// Lua nudge clamp constants (header 5; every value cited).
    private static let luaYawClampDivisor = 45.0 / 4.0   // vr_f / VR_YAW_CLAMP factor (lua l.15, l.50)
    private static let luaPitchLimitRad = 85.0 * .pi / 180.0  // VR_PITCH_LIMIT_DEG (lua l.48-49)
    private static let luaFovMin = 45.0 / 2.0             // VR_FOV_MIN = vr_f/2 (lua l.51)
    private static let luaFovMaxSpherical = 45.0 * 3.5    // VR_FOV_MAX = vr_f*3.5 (lua l.52)
    private static let luaFovMaxFlat = 179.0              // vr_fov_max() flat branch (lua l.55)

    /// Full-contract base constants (header 0c; every value cited).
    private static let luaDefaultIpdMM = 63.0              // VR_DEFAULT_IPD_MM (lua l.339, block182 md.2)
    private static let luaReferenceDistanceMM = 500.0      // VR_REFERENCE_DISTANCE_MM (lua l.340)
    private static let luaDistanceHoldS = 2.0              // VR_DISTANCE_HOLD_S (lua l.341)
    private static let luaHoldOkThresholdS = 0.5           // "ok" vs "hold-last-d" boundary (lua l.390)
    private static let luaMacbookMMPerPx = 25.4 / 227.0    // VR_MACBOOK_MM_PER_PX (lua l.349)
    private static let luaShaderShiftLimit = 0.8           // VR_SHADER_SHIFT_LIMIT (lua l.350)
    private static let luaTodayBaseIpdMM = 0.0             // VR_TODAY_BASE_IPD_MM (lua l.346-347)
    private static let luaZoomReferenceFovDeg = 90.0       // VR_ZOOM_REFERENCE_FOV_DEG (lua l.117)
    private static let luaParallaxStrengthDefault = 0.4    // VR_PARALLAX_CORRECTION_STRENGTH (lua l.125)
    private static let luaParallaxDisparityDefault = -0.4  // = strength * -1 (lua l.129)

    init(clock: @escaping () -> Double) {
        self.clock = clock
        installedSession = nil
        installedSource = nil
        installedGeneration = nil
        ipdOffsetMM = nil
        distanceCustody = (nil, nil, nil, nil)
    }

    /// Bind to one host session+source+generation with the host's
    /// EXPLICIT validated declared-constant initial. Refuses (loud
    /// reason, no state change) on non-finite initial values. A
    /// re-install drops every lane from the previous install (explicit
    /// loss, never stale reuse) - this is also the source-adoption
    /// reset the session's onStereoSourceAdopted hook drives (header
    /// 6).
    @discardableResult
    func install(session: UUID, source: String, generation: UInt64,
                 initial: StereoLookNativeInitial) -> String? {
        guard initial.allFinite else {
            lastRefusal = "non-finite initial value"
            return lastRefusal
        }
        installedSession = session
        installedSource = source
        installedGeneration = generation
        acceptanceEpoch = 0
        restrictedProjectionAdmission = nil
        projectionSensorInputAccepted = false
        projectionEpochExhausted = false
        enabled = nil; projection = nil; pack = nil
        toolsActive = nil; swapEyes = nil; viewingCross = nil
        yaw = initial.poseYaw; pitch = initial.posePitch
        fov = initial.poseFov; roll = initial.poseRoll
        headX = 0; headY = 0; headZ = 0; ipdNudge = 0
        nativeRawRoll = nil
        manualYaw = 0; manualPitch = 0; manualFov = 0; manualRoll = 0
        calibration = initial.calibration
        poseYawAccepted = false; posePitchAccepted = false
        poseFovAccepted = false; poseRollAccepted = false
        tuneStrength = initial.declaredTune == .shippedLuaPair ? 0.4 : nil
        tuneDisparity = initial.declaredTune == .shippedLuaPair ? -0.4 : nil
        tuneStrengthAccepted = false; tuneDisparityAccepted = false
        ipdOffsetMM = nil
        admissionBlockers = []
        withheldLanes = []
        policyConstantLanes = []
        diagnosticSession = nil
        distanceCustody = (nil, nil, nil, nil)
        lastRefusal = nil
        reassemble()   // diagnostics/blockers exist from install, not first accept
        return nil
    }

    // Narrow origin check, not an applied-state snapshot or a new mutation.
    func matchesOrigin(_ origin: StereoLookCommandOrigin) -> Bool {
        installedSession == origin.session && installedSource == origin.source &&
            installedGeneration == origin.generation
    }

    func uninstall() {
        restrictedProjectionAdmission = nil
        projectionSensorInputAccepted = false
        projectionEpochExhausted = false
        installedSession = nil
        installedSource = nil
        installedGeneration = nil
        ipdOffsetMM = nil
        distanceCustody = (nil, nil, nil, nil)
        admissionBlockers = []
        withheldLanes = []
        policyConstantLanes = []
        diagnosticSession = nil
    }

    /// The wire projection-kind whitelist (VR180Controller
    /// publishProjection l.376-390 kinds). The owner re-validates the
    /// parser's enum at the typed boundary (header 4).
    private static let projectionKindWhitelist: Set<String> = [
        "flat-2d3d", "flat-sbs", "flat-tb",
        "vr180", "vr180-tb", "vr360-mono", "vr360-tb",
    ]

    /// Accept one typed command under its QUEUE-TIME origin (header
    /// 6). Full validation happens BEFORE any mutation; a refusal
    /// (missing/stale origin or invalid value) leaves all lanes
    /// untouched. Returns a loud refusal reason or nil on acceptance
    /// / silent Lua-parity ignore.
    @discardableResult
    func accept(_ command: StereoLookNativeCommand, origin: StereoLookCommandOrigin?) -> String? {
        guard let origin,
              installedSession == origin.session,
              installedSource == origin.source,
              installedGeneration == origin.generation else {
            lastRefusal = "missing or stale command origin"
            return lastRefusal
        }
        // Lua l.1104 parity: a nudge while disabled is ignored
        // SILENTLY (no accumulation, no epoch bump, no refusal).
        if case .nudge = command, enabled != true { return nil }
        // -- validation phase (no mutation below this line on failure)
        switch command {
        case .setOrientation(let oyaw, let opitch, let ofov, let oroll,
                             let oipd, let ohx, let ohy, let ohz,
                             let odmm, _, let ommpx, let ofuse, let oraw):
            for v in [oyaw, opitch, ofov, oroll, oipd, ohx, ohy, ohz, odmm, ommpx, ofuse, oraw] {
                if let v, !v.isFinite {
                    lastRefusal = "non-finite orientation slot"
                    return lastRefusal
                }
            }
        case .setPack(let p, let gain, let conv, let zoom, let soft):
            guard (0...3).contains(p), gain.isFinite, conv.isFinite, zoom.isFinite, soft.isFinite else {
                lastRefusal = "invalid pack value"
                return lastRefusal
            }
        case .setProjection(let kind, let aspect):
            guard Self.projectionKindWhitelist.contains(kind) else {
                lastRefusal = "unknown projection kind"
                return lastRefusal
            }
            guard aspect.isFinite, aspect > 0 else {
                lastRefusal = "invalid aspect"
                return lastRefusal
            }
        case .setTuneParallaxStrength(let v), .setTuneParallaxDisparity(let v):
            guard v.isFinite else {
                lastRefusal = "non-finite tune value"
                return lastRefusal
            }
        case .setIpdMM(let mm):
            guard mm.isFinite else {
                lastRefusal = "non-finite ipd mm value"
                return lastRefusal
            }
        case .nudge(let dyaw, let dpitch, let dfov, let droll):
            let ny = manualYaw + dyaw, np = manualPitch + dpitch
            let nf = manualFov + dfov, nr = manualRoll + droll
            guard ny.isFinite, np.isFinite, nf.isFinite, nr.isFinite else {
                lastRefusal = "nudge accumulation overflow"
                return lastRefusal
            }
        case .setEnabled, .viewingCross, .toolsActive, .setSwapEyes, .fullFit, .smoothFit:
            break
        }
        // Only manual operations that cannot start/change capture consumers or
        // the projection route may carry an existing admission forward. Generic
        // commands remain accepted as before; only this capability is invalidated.
        let preservesProjectionAdmission: Bool
        switch command {
        case .nudge, .fullFit, .smoothFit, .setSwapEyes, .viewingCross,
             .setIpdMM, .setTuneParallaxStrength, .setTuneParallaxDisparity:
            preservesProjectionAdmission = true
        case .toolsActive(let active):
            preservesProjectionAdmission = !active && toolsActive == false
        case .setEnabled(let on):
            preservesProjectionAdmission = on && enabled == true
        default:
            preservesProjectionAdmission = false
        }
        if !preservesProjectionAdmission { restrictedProjectionAdmission = nil }
        if case .setOrientation = command { projectionSensorInputAccepted = true }
        // -- mutation phase (validated)
        switch command {
        case .setEnabled(let on):
            enabled = on
            // Lua parity (header 5): disable zeroes the manual
            // offsets; enable does not touch them.
            if !on { manualYaw = 0; manualPitch = 0; manualFov = 0; manualRoll = 0 }
        case .setProjection(let kind, let aspect): projection = (kind, aspect)
        case .setPack(let p, let gain, let conv, let zoom, let soft):
            pack = (p, gain, conv, zoom, soft)
        case .toolsActive(let on): toolsActive = on
        case .setSwapEyes(let on): swapEyes = on
        case .viewingCross(let on): viewingCross = on
        case .setOrientation(let oyaw, let opitch, let ofov, let oroll,
                             let oipd, let ohx, let ohy, let ohz,
                             let odmm, let odrsn, let ommpx, _, let oraw):
            // Lua l.1036: nil slot keeps the current value. Acceptance
            // is PER ACTUAL SUPPLIED FIELD (Ops v9 probe): an all-nil
            // command supplies no pose authority and must not clear
            // the pose candidate label.
            if let oyaw { yaw = oyaw; poseYawAccepted = true }
            if let opitch { pitch = opitch; posePitchAccepted = true }
            if let ofov { fov = ofov; poseFovAccepted = true }
            if let oroll { roll = oroll; poseRollAccepted = true }
            if let oipd { ipdNudge = oipd }
            if let ohx { headX = ohx }
            if let ohy { headY = ohy }
            if let ohz { headZ = ohz }
            // Lua l.1054-1057 EXACT (Ops hazards H2/H3): only a
            // POSITIVE supplied distance refreshes the sample AND its
            // age; a supplied non-ok reason WITHOUT a positive
            // distance CLEARS the prior sample (a reason never
            // inherits an old mm); omitted slots leave everything
            // untouched and never refresh the age. mmpx is kept as
            // supplied (0 = scale unavailable -> the MacBook
            // constant, Lua l.1057).
            if let odmm, odmm > 0 {
                distanceCustody.mm = odmm
                distanceCustody.at = clock()
                distanceCustody.reason = "ok"
            } else if let odrsn, !odrsn.isEmpty, odrsn != "ok" {
                distanceCustody.mm = nil
                distanceCustody.at = nil
                distanceCustody.reason = odrsn
            }
            if let ommpx { distanceCustody.mmPerPx = ommpx }
            // Lua assigns the optional slot unconditionally (nil when
            // omitted) - Lua parity, Ops-confirmed.
            nativeRawRoll = oraw
        case .setIpdMM(let mm):
            ipdOffsetMM = mm
        case .setTuneParallaxStrength(let v):
            tuneStrength = v; tuneStrengthAccepted = true
        case .setTuneParallaxDisparity(let v):
            tuneDisparity = v; tuneDisparityAccepted = true
        case .nudge(let dyaw, let dpitch, let dfov, let droll):
            // Lua l.1103-1112 accumulation WITH the live clamps,
            // constants cited in header (5).
            let yawBound = Double.pi / Self.luaYawClampDivisor
            manualYaw = min(max(manualYaw + dyaw, -yawBound), yawBound)
            manualPitch = min(max(manualPitch + dpitch, -Self.luaPitchLimitRad), Self.luaPitchLimitRad)
            manualRoll += droll   // no clamp (lua l.1107)
            let layout = projection.map { Self.layout(for: $0.kind) } ?? 0
            let fovMax = layout < 3 ? Self.luaFovMaxFlat : Self.luaFovMaxSpherical
            manualFov = min(max(manualFov + dfov, Self.luaFovMin - fov), fovMax - fov)
        case .fullFit, .smoothFit:
            // Input semantic (Lua cinema_reset l.421-425 via l.1146;
            // smooth-fit l.1150 animates presentation): accumulated
            // manual offsets return to zero.
            manualYaw = 0; manualPitch = 0; manualFov = 0; manualRoll = 0
        }
        let priorAcceptanceEpoch = acceptanceEpoch
        acceptanceEpoch &+= 1
        if acceptanceEpoch <= priorAcceptanceEpoch {
            projectionEpochExhausted = true
            restrictedProjectionAdmission = nil
        } else if preservesProjectionAdmission, let admission = restrictedProjectionAdmission {
            restrictedProjectionAdmission = admission.advancing(to: acceptanceEpoch)
        }
        lastRefusal = nil
        reassemble()
        return nil
    }

    /// Lua set-projection layout mapping (l.899-902) over a kind the
    /// owner has ALREADY re-validated (header 4) - no silent layout 0
    /// for unknown kinds is possible here.
    private static func layout(for kind: String) -> Int {
        switch kind {
        case "flat-sbs": return 1
        case "flat-tb": return 2
        case "vr180": return 3
        case "vr180-tb": return 4
        case "vr360-mono": return 5
        case "vr360-tb": return 6
        default: return 0   // flat-2d3d (whitelist-guaranteed)
        }
    }

    /// Rebuild the immutable accepted input after any accepted command.
    /// Whole-input availability per header (1): EVERY accept-required
    /// lane accepted this session+generation AND enabled == true.
    /// While unavailable the pull vends nil - partial route, never
    /// full stage admission with unknown required inputs.
    private func reassemble() {
        // Lane-status diagnostics + admission blockers are maintained
        // even while the route is partial (visible unresolved state).
        var blockers: [String] = []
        if tuneStrength == nil || tuneDisparity == nil {
            blockers.append("tune")
        }
        if ipdOffsetMM == nil { blockers.append("ipdDial") }
        admissionBlockers = blockers
        withheldLanes = blockers
        var policies: [String] = []
        if !(poseYawAccepted && posePitchAccepted && poseFovAccepted && poseRollAccepted) {
            policies.append("pose")          // neutral-reset policy
        }
        policies.append("calibration")       // retired-policy constant
        policies.append("crop")              // constant-by-design
        if tuneStrength != nil && !tuneStrengthAccepted { policies.append("tuneStrength") }
        if tuneDisparity != nil && !tuneDisparityAccepted { policies.append("tuneDisparity") }
        policyConstantLanes = policies
        guard installedSession != nil, installedSource != nil,
              let enabled, enabled,
              let projection, let pack,
              let toolsActive, let swapEyes, let viewingCross else {
            diagnosticSession = nil
            return
        }
        let layout = Self.layout(for: projection.kind)
        let kind = projection.kind
        let flatSbs = kind == "flat-sbs" || kind == "flat-tb" || kind == "flat-2d3d"
        let flatMono = kind == "flat-2d3d"
        // flat_pack: Lua set-pack deterministic parts (l.889); the
        // Lua-internal vr_pack_blocked is not transported - the native
        // pipeline's own gate semantics apply.
        let flatPack = layout >= 3 ? 0 : max(0, min(3, pack.pack))
        // pk params: accepted values with the Lua's own clamps (l.890);
        // the producer serializes these lanes directly, so clamps are
        // applied ONCE here.
        let pkConv = max(0.1, min(0.9, pack.conv))
        let pkZoom = max(0.4, min(2.0, pack.zoom))
        let pkSoft = pack.soft >= 0.5 ? 1.0 : 0.0
        // d3Gain: the Lua pushes final D3_GAIN = 0.04*clamp(gain,0...2)
        // (l.889, which supersedes the older l.41 constant); the
        // producer serializes vr_d3_gain directly, so the cited
        // transform is applied here, once.
        let d3Gain = 0.04 * max(0, min(2, pack.gain))

        let sessionInput = StereoLookSession(
            enabled: enabled, toolsActive: toolsActive,
            layout: layout, flatSbs: flatSbs, flatMono: flatMono,
            flatPack: flatPack, pkConv: pkConv, pkZoom: pkZoom,
            pkSoft: pkSoft, d3Gain: d3Gain)
        diagnosticSession = sessionInput
        // The complete input itself is built at PULL time in
        // buildInput(now:) (H3): the hold expiry advances with the
        // fresh monotonic clock even when no command arrives.
    }

    // MARK: pull-side (MainActor, synchronous, no hops)

    /// The session provider's per-frame pull, fenced by the caller's
    /// EXPECTED session token: a provider closure that outlived its
    /// session gets nil, never another session's accepted input.
    /// Custody rides the return in the package type (header 7). The
    /// base evaluation runs HERE with a fresh clock (H3).
    /// PATH A (Ops 8:11:41): the pull carries the presenter's live
    /// sample of the actual attached view. NIL context (detached,
    /// geometry mismatch, display unresolved) vends NIL - an absent
    /// or unimplemented source never falls back. A bound context with
    /// a nil scale falls back to the panel constant inside the
    /// evaluation (labeled "macbook-227ppi").
    func pullInput(expectedSession: UUID, context: StereoLookPullContext?) -> StereoLookHostInput? {
        guard installedSession == expectedSession else { return nil }
        guard let context, context.widthPx > 0, context.heightPx > 0 else { return nil }
        return buildInput(now: clock(), context: context)
    }

    /// Build the admitted complete input at pull time (header 0/1/0c).
    /// NIL whenever any accept-required lane is missing, enabled is not
    /// true, or any missing live route is unresolved (admissionBlockers
    /// non-empty): the complete input is STOPPED at the adapter
    /// boundary - no payload, never a leaked default or prior-origin
    /// value.
    private func buildInput(now: Double, context: StereoLookPullContext) -> StereoLookHostInput? {
        guard let session = installedSession, let source = installedSource,
              let enabled, enabled,
              let projection, let pack,
              let toolsActive, let swapEyes, let viewingCross,
              admissionBlockers.isEmpty,
              let tuneStrength, let tuneDisparity,
              let ipdOffsetMM else {
            return nil
        }
        let layout = Self.layout(for: projection.kind)
        let kind = projection.kind
        let flatSbs = kind == "flat-sbs" || kind == "flat-tb" || kind == "flat-2d3d"
        let flatMono = kind == "flat-2d3d"
        // flat_pack: Lua set-pack deterministic parts (l.889); the
        // Lua-internal vr_pack_blocked is not transported - the native
        // pipeline's own gate semantics apply.
        let flatPack = layout >= 3 ? 0 : max(0, min(3, pack.pack))
        // pk params: accepted values with the Lua's own clamps (l.890);
        // the producer serializes these lanes directly, so clamps are
        // applied ONCE here.
        let pkConv = max(0.1, min(0.9, pack.conv))
        let pkZoom = max(0.4, min(2.0, pack.zoom))
        let pkSoft = pack.soft >= 0.5 ? 1.0 : 0.0
        // d3Gain: the Lua pushes final D3_GAIN = 0.04*clamp(gain,0...2)
        // (l.889, which supersedes the older l.41 constant); the
        // producer serializes vr_d3_gain directly, so the cited
        // transform is applied here, once.
        let d3Gain = 0.04 * max(0, min(2, pack.gain))
        // Full-contract base evaluation at THIS pull's fresh now (H3),
        // on THIS pull's sampled viewport/display context (Path A).
        let evaluation = evaluateAppliedBase(now: now, layout: layout,
                                             context: context,
                                             offsetMM: ipdOffsetMM)

        let sessionInput = StereoLookSession(
            enabled: enabled, toolsActive: toolsActive,
            layout: layout, flatSbs: flatSbs, flatMono: flatMono,
            flatPack: flatPack, pkConv: pkConv, pkZoom: pkZoom,
            pkSoft: pkSoft, d3Gain: d3Gain)
        let controls = StereoLookControls(
            yaw: yaw, pitch: pitch, fov: fov, roll: roll,
            manualYaw: manualYaw, manualPitch: manualPitch,
            manualFov: manualFov, manualRoll: manualRoll,
            headX: headX, headY: headY, headZ: headZ,
            baseIpd: evaluation.baseIpdRaw, ipdNudge: ipdNudge,
            appliedIpdBase: evaluation.appliedIpdBase,
            nativeRawRoll: nativeRawRoll,
            swapEyes: swapEyes ? 1.0 : 0.0,
            crossEye: viewingCross ? 1.0 : 0.0,
            calibration: calibration)
        // Source crop: full eye (0,0,1,1), constant BY DESIGN at
        // publishProjection (VR180Controller l.381-385; probeEyeCrop is
        // UI-only, never transported). [DECLARED constant-by-design]
        let geometry = StereoLookGeometry(
            eyeAspect: projection.aspect,
            sourceX: 0, sourceY: 0, sourceW: 1, sourceH: 1)
        // Both values exist from explicit declared initialization and/or
        // independently accepted current-origin per-key tune commands.
        let tune = StereoLookTune(parallaxStrength: tuneStrength,
                                  parallaxDisparity: tuneDisparity)
        return StereoLookHostInput(
            state: StereoLookHostState(
                session: sessionInput, controls: controls,
                geometry: geometry,
                tune: tune),
            session: session,
            source: source,
            acceptanceEpoch: acceptanceEpoch,
            withheldLanes: withheldLanes,
            policyConstantLanes: policyConstantLanes,
            sourceGeneration: installedGeneration,
            restrictedProjectionAdmission: restrictedProjectionAdmission,
            // full182 D2: the contract's geom-trace payload (owner order
            // item 2). This pull's own evaluation, verbatim; transport
            // only, admission-neutral.
            distanceTrace: StereoLookDistanceTrace(
                distanceMM: evaluation.distanceMM,
                sTodayMM: evaluation.sTodayMM,
                sRequestedMM: evaluation.sRequestedMM,
                sCapMM: evaluation.sCapMM,
                sTotalMM: evaluation.sTotalMM,
                offsetMM: evaluation.offsetMM,
                ipdEffMM: evaluation.ipdEffMM,
                capped: evaluation.capped,
                infeasible: evaluation.infeasible,
                capMet: evaluation.capMet,
                reason: evaluation.reason,
                mmPerPx: evaluation.mmPerPx,
                mmPerPxSource: evaluation.mmPerPxSource,
                eyeWidthMM: evaluation.eyeWidthMM,
                halfWidthMM: evaluation.halfWidthMM,
                baseIpdRaw: evaluation.baseIpdRaw,
                appliedIpdBase: evaluation.appliedIpdBase))
    }

    /// The full block182 base evaluation (header 0c), pure over the
    /// accepted lanes + custody + a supplied monotonic now. H4: the
    /// custody distance is consumed VERBATIM (the producer's one-euro
    /// fD is the single filter authority, Sensing.swift l.221/1299).
    private func evaluateAppliedBase(now: Double, layout: Int, context: StereoLookPullContext, offsetMM: Double) -> StereoLookBaseEvaluation {
        // mm/px scale (Path A): the pull context's DISPLAY-BOUND sample
        // when positive; a bound-but-unavailable scale falls back to
        // the MacBook panel constant (Lua l.359-360, l.349). The
        // orientation-command slot is NEVER consulted (Ops 8:11:41:
        // diagnostic-only). Source named verbatim for the trace.
        let boundScale = context.mmPerPx
        let haveScale = boundScale != nil && boundScale! > 0
        let mmpx = haveScale ? boundScale! : Self.luaMacbookMMPerPx
        let src = haveScale ? "host-display-\(context.displayID)" : "macbook-227ppi"
        let eyeWMM = (Double(context.widthPx) / 2.0) * mmpx
        let halfW = eyeWMM / 2.0
        // Parallax excess (Lua l.376-381; PARALLAX_CORRECTION_ENABLED =
        // true l.122). Tune unset -> the Lua defaults 0.4 / -0.4
        // (l.125, l.129): exact parity while no tune dispatch exists;
        // the admission gate still blocks an unset tune (header 0), so
        // the default branch is reachable only in diagnostics.
        let strength = tuneStrength ?? Self.luaParallaxStrengthDefault
        let disparity = tuneDisparity ?? Self.luaParallaxDisparityDefault
        let fovMax = layout < 3 ? Self.luaFovMaxFlat : Self.luaFovMaxSpherical
        let fovEff = min(max(fov + manualFov, Self.luaFovMin), fovMax)
        let mag = tan(Self.luaZoomReferenceFovDeg * .pi / 180.0 * 0.5) / tan(fovEff * .pi / 180.0 * 0.5)
        let excess = disparity * (mag - 1.0) * strength
        // Today's separation (Lua l.382-385; VR_TODAY_BASE_IPD_MM = 0).
        let todayNorm = excess + ipdNudge + 0.0
        let sToday = todayNorm * halfW + Self.luaTodayBaseIpdMM + offsetMM
        let ipdEff = Self.luaDefaultIpdMM + offsetMM
        // Distance hold, evaluated with the FRESH now (Lua l.386-394;
        // H3). Only a positive accepted sample has an age (H2/H3).
        var d: Double? = nil
        var reason = distanceCustody.reason ?? "no-input"   // Lua init l.352
        if let mm = distanceCustody.mm, let at = distanceCustody.at {
            let age = now - at
            if age <= Self.luaDistanceHoldS {
                d = mm
                reason = age <= Self.luaHoldOkThresholdS ? "ok" : "hold-last-d"
            } else {
                reason = "no-face-hold-expired"
            }
        }
        // Vergence cap on the COMBINED separation (Lua l.395-398); it
        // only ever SHRINKS the separation at close distance.
        var sRequested = sToday
        var capped = false
        var sCap: Double? = nil
        if let d {
            let cap = (d / Self.luaReferenceDistanceMM) * (ipdEff + sToday) - ipdEff
            sCap = cap
            if cap < sToday { sRequested = cap; capped = true }
        }
        // Shader feasibility clamp (Lua l.399-402).
        var shift = sRequested / halfW
        let infeasible = abs(shift) > Self.luaShaderShiftLimit
        if infeasible {
            shift = min(max(shift, -Self.luaShaderShiftLimit), Self.luaShaderShiftLimit)
        }
        let sTotal = shift * halfW
        // cap_met diagnostic (Lua l.404).
        let capMet = (d == nil) || (ipdEff + sTotal <= (d! / Self.luaReferenceDistanceMM) * (ipdEff + sToday) + 1e-9)
        // Applied base (Lua l.405) and raw dial conversion (l.361).
        let applied = shift - excess - ipdNudge
        return StereoLookBaseEvaluation(
            baseIpdRaw: offsetMM / halfW, appliedIpdBase: applied,
            distanceMM: d, sTodayMM: sToday, sCapMM: sCap,
            sRequestedMM: sRequested, sTotalMM: sTotal,
            offsetMM: offsetMM, ipdEffMM: ipdEff,
            capped: capped, infeasible: infeasible, capMet: capMet,
            reason: reason, mmPerPx: mmpx, mmPerPxSource: src,
            orientationScaleSlot: distanceCustody.mmPerPx,
            eyeWidthMM: eyeWMM, halfWidthMM: halfW)
    }

    /// Same-module qualification surface: the full-contract evaluation
    /// at an explicit now on an explicit pull context. NIL while the
    /// dial custody is missing. Diagnostic only, never a recovery
    /// channel.
    func diagnosticEvaluateBase(now: Double, context: StereoLookPullContext) -> StereoLookBaseEvaluation? {
        guard let ipdOffsetMM else { return nil }
        let layout = projection.map { Self.layout(for: $0.kind) } ?? 0
        return evaluateAppliedBase(now: now, layout: layout,
                                   context: context, offsetMM: ipdOffsetMM)
    }
}
