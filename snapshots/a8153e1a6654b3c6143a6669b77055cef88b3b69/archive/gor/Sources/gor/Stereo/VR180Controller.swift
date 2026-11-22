import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
final class VR180Controller {

    private(set) var vrModeEnabled = false { didSet { ThreadCpuDiag.vrMode = vrModeEnabled;if !vrModeEnabled {onSubtitleTilt?(0,0);onUITilt?(0)} } }

    var vrModeSetByAutoDetect = false
    private var flatStereoFile = false; var filmLooksStereo: Bool { detectedStereoKind != nil }; func showOSDLine(_ t: String) { showBlinkOSD(t) }
    private var flatAutoEyeAspect: Double = 0
    var flatUIEyeAspect: Double? {flatStereoFile && flatAutoEyeAspect > 0 ? flatAutoEyeAspect : nil}
    var isFlatStereo: Bool {flatStereoFile}
    var isFlat2D3D: Bool {projectionKind == "flat-2d3d"}
    func requestsFlatSBSGeometry(for path:String)->Bool {MainActor.assumeIsolated {
        let s=ThreeDStore.shared.snapshot;guard !path.isEmpty,s.currentFilm == ThreeDRecognitionBridge.filmID(path:path) else{return false}
        let p=ThreeDPresentationPlan.make(state:s);return p.luaKind=="flat-2d3d" && p.output == .sbs
    }}
    var expectsSBSFilmFrame:Bool {appliedPlan?.output == .sbs || appliedPlan?.output == .halfSBS}
    var presentsFlatSBSGeometry:Bool {appliedPlan?.luaKind=="flat-2d3d" && appliedPlan?.output == .sbs}
    var usesLegacyPreviewChrome:Bool {sourceIsFlatPreview && appliedPlan?.output == .vr180}
    private var sourceIsFlatPreview:Bool {projectionKind.hasPrefix("flat-")}
    var cropSourcePacking: (stereo: Bool, topBottom: Bool) {
        // The plan includes rendered-source replacements; output SBS alone is not source stereo.
        let kind=MainActor.assumeIsolated {ThreeDPresentationPlan.make(state:ThreeDStore.shared.snapshot).luaKind}
        return CropSourcePacking.flags(kind)
    }
    var isTopBottom: Bool { projectionKind == "flat-tb" }
    private var projectionKind = "mono"
    private var projectionKey = ""

    private(set) var headTrackingEnabled = false

    /// Cross-eye order (block 180 3a). false = default order, true = swapped halves.
    /// Persisted in UserDefaults; every VR disparity sign reads this flag.
    static let swapEyesDefaultsKey = "gor.vr.swapEyes"
    /// Head-tracking opt-in (block 180 3b). VR entry (auto-detect, menu, shift+v)
    /// enables the shader only; the camera starts ONLY from an explicit shift+h /
    /// menu head-tracking choice. The last explicit choice is remembered here
    /// (UserDefaults) but is never used to start the camera by itself.
    static let headTrackingDefaultsKey = "gor.vr.headTracking"
    /// VR entry restores prior auto tracking, except an explicit saved off or a test-owned camera opt-out.
    static var headTrackingAutoStartAllowed: Bool {
        guard ProcessInfo.processInfo.environment["GOR_VR_TEST_NO_CAMERA"] != "1" else { return false }
        return (UserDefaults.standard.object(forKey: headTrackingDefaultsKey) as? Bool) ?? true
    }
    private(set) var headTrackingPreferred=false
    private(set) var swapEyes=false
    private var headTrackingCameraActive = false
    private var blinkCameraActive = false
    /// Every VR entry defaults ON, but an explicit saved OFF survives re-entry and relaunch.
    private var blinkControlPreferred=false
    /// Set only when the head-motion leg actually called HeadTracker.start(); GOR_VR_SIM_POSE=1
    /// acquires no camera consumer, so the matching stop must never release the blink leg's.
    private var headOwnsRealCameraConsumer = false
    /// File-loaded signal fed by PPController from cameraLoadedVideoActive (UI lane owns every
    /// PPController write). Unlike playbackActive this does NOT drop on pause: blink needs
    /// frames while paused, or the bilateral-double pause toggle could never resume.
    var loadedVideoActive = false {
        didSet {
            guard loadedVideoActive != oldValue else { return }
            // A file boundary retires the recognizer epoch so a previous file's
            // first blink or held wink cannot act on the replacement file.
            if #available(macOS 12.0, *) {
                if loadedVideoActive { if blinkControlPreferred { _ = setBlinkControlEnabled(true, osd: false, remember: false) } }
                else {
                    HeadTracker.shared.blinkLogEnabled = false
                    HeadTracker.shared.flushBlinkSummary(osd: nil)
                    blinkControlDidStop(osd: nil)
                }
            }
            updateCaptureConsumers()
        }
    }
    var playbackActive = false {
        didSet {
            guard playbackActive != oldValue else { return }
            updateCaptureConsumers()
        }
    }

    static let vrYawPitchDegPerPoint: Double = 0.15
    static let vrFovDegPerMagnifyUnit: Double = -60.0

    static let vrAutoFullscreen: Bool = false
    // VR output fills the whole drawable (screen in fullscreen, window when windowed): vr180-look.lua
    // sets keepaspect=no on enable and restores the user's prior value on disable, and derives each
    // eye's horizontal fov from its viewport aspect (fixed vertical fov). No aspect override is sent.

    static let headRotationGain: Double = 1.0
    static let headTranslateMetersPerUnit: Double = 0.20
    static let headLeanNudgeFovDegPerUnit: Double = -150.0
    static let headIpdNudgePerUnit: Double = 0.06 * 2

    static let headTrackingRestFovDeg: Double = 135.0
    // Block184 restores the exact pre181 mapping (6f5e28345 parent): -150 degrees per box unit.
    // Noise belongs to the one-euro filter, never to a reduced control gain.
    static let headFovGain: Double = 1.0
    static let headDeadZoneRad: Double = 0.004
    static func softDeadZone(_ x: Double) -> Double {
        let m = max(0.0, abs(x) - headDeadZoneRad)
        return x < 0 ? -m : m
    }
    private static let headZTranslateSign: Double = -1.0

    /// The ipd dial (block 182 2): canonical state is the OFFSET IN MILLIMETRES on the 63 mm default,
    /// persisted in UserDefaults (gor.vr.ipdOffsetMM), so a display change never changes the physical
    /// offset. vr180-look converts it with the current viewport and CGDisplayScreenSize mm/px.
    /// The NDC statics below (step 0.02, limit 0.3) are today's dial units; they convert to mm once,
    /// at the M1 full-screen eye half-width (2560 px / 2 eyes / 2 at 25.4/227 mm per px, Apple 111883).
    static let ipdOffsetMMDefaultsKey = "gor.vr.ipdOffsetMM"
    static let ndcToMM: Double = (2560.0 / 2.0 / 2.0) * (25.4 / 227.0)
    private var currentIPDOffsetMM: Double = 0
    /// NDC-equivalent at the M1 scale, kept for the existing test surface and the vrIPD "v" field.
    private var currentBaseIPD: Double { currentIPDOffsetMM / Self.ndcToMM }
    static let baseIPDStep:  Double = 0.02
    static let baseIPDLimit: Double = 0.3

    /// Block184 dial is a dimensionless depth factor. Default1 gives crossed0.4% eye width for
    /// subtitles and0.8% for UI. A new key avoids reinterpreting old point offsets as this scale.
    static let subtitleDepthDefaultsKey = "gor.vr.subtitleDepthScale.v184"
    static let subtitleDepthDefault: Double = 1.0
    static let subtitleDepthStep:    Double = 0.25
    static let subtitleDepthLimit:   Double = 8.0
    private(set) var subtitleDepthPoints: Double = {
        let stored = UserDefaults.standard.object(forKey: VR180Controller.subtitleDepthDefaultsKey) as? Double
        return stored ?? VR180Controller.subtitleDepthDefault
    }()

    func setSubtitleDepth(_ points: Double) {
        subtitleDepthPoints = max(0, min(Self.subtitleDepthLimit, points))
        UserDefaults.standard.set(subtitleDepthPoints, forKey: Self.subtitleDepthDefaultsKey)
    }

    func adjustSubtitleDepth(by delta: Double) {
        setSubtitleDepth(subtitleDepthPoints + delta)
    }

    /// Whether the user has a stored pref at all (snapshot/restore needs the
    /// difference between "8 stored" and "no pref, default 8").
    var hasSubtitleDepthPref: Bool {
        UserDefaults.standard.object(forKey: Self.subtitleDepthDefaultsKey) != nil
    }

    func clearSubtitleDepth() {
        UserDefaults.standard.removeObject(forKey: Self.subtitleDepthDefaultsKey)
        subtitleDepthPoints = Self.subtitleDepthDefault
    }
    private let ipcCommand: (String) -> Void

    init(ipcCommand: @escaping (String) -> Void) {
        self.ipcCommand = ipcCommand
        resetTestVRProperty()
    }

    func invalidateOpenReceipt() { openReceipt.reset() }
    func invalidateAutoFitEntry() {autoFitEntry=""}
    private var openReceipt=ThreeDOpenReceipt()
    func resetForFileChange() {
        Diag.mediaRecord("3D-CLOSE file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) revision=\(routeRevision) output=\(appliedPlan?.output.rawValue ?? "none")")
        invalidateOpenReceipt()
        vrModeEnabled=false;ScreenCaptureEngine.shared.vrModeActive=false;autoFitEntry="";updateCaptureConsumers()
        resetTestVRProperty()
        appliedThreeD=nil;appliedPlan=nil;appliedEffects=nil;appliedInternal=nil
        vrModeSetByAutoDetect = false
        flatStereoFile = false
        projectionKey = ""
        manualProjection = nil; recognitionGeneration &+= 1; recognitionPath = ""; recognitionIdentity = ""
        probeStarted = false; probeFinished = false; probeProjection = nil; probeStereoSBS = false;probeEyeAspect=nil;probeEyeCrop=nil;sourceMeasuredEyeAspect=nil;probeStereoTB=false
        latestWidth = 0; latestHeight = 0; latestStereo = nil
        projectionKind="mono"
        openingProjection=nil
    }

    // State is owned by ThreeDStore. Recognition supplies evidence, never preferences.
    private var manualProjectionIsCurrentSession=false
    private var manualProjection: String?
    var recognitionPath = ""
    private var recognitionIdentity = ""
    private var recognitionGeneration: UInt64 = 0
    private var probeStarted = false
    var probeFinished = false
    private var probeProjection: String?
    private var openingProjection: String?
    private var probeStereoSBS = false
    private var probeEyeAspect:Double?
    private var probeEyeCrop:SBSEyeCrop.NormalizedCrop?
    private var sourceMeasuredEyeAspect:Double?
    func acceptSourceEyeAspect(_ aspect:Double?) {
        // Detector measurement is UI-only, including legacy/delayed callers.
        clearMeasuredEyeAspect()
    }
    func clearMeasuredEyeAspect() {
        latestSourceCrop=nil; projectionKey=""
        if isTopBottom { sourceMeasuredEyeAspect = latestHeight > 0 ? latestWidth*latestPixelAspect/latestHeight*2 : nil }
        else { sourceMeasuredEyeAspect = SBSGeometry.resolve(width:latestWidth,height:latestHeight,pixelAspect:latestPixelAspect,filename:recognitionPath,stereoProven:true)?.aspect }
    }
    private var probeStereoTB=false
    private var latestStereo: String?
    private var latestContainerMetadata:[String:String]=[:]
    private var recognitionLogKey=""
    private var latestProbeStatus="pending"
    var sourceSuggestion:String {if detectedStereoKind != nil {return detectedStereoKind!};return VRRecognition.suggestion(filename:recognitionPath,width:latestWidth,height:latestHeight)}
    var latestWidth: Double = 0
    var latestHeight: Double = 0
    private var latestPixelAspect:Double=1
    private var latestSourceCrop:(Double,Double)?

    func applyManualSource(_ value:String,enable:Bool) {
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setSource(SourceFormatChoice.source(value)))}
    }
    func applySourceOutput(_ output:String) {
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setOutput(ThreeDOutput(rawValue:output) ?? .off))}
    }
    func selectProjection(_ kind:String) {
        let map=["flat-2d3d":"flat","flat-sbs":"sbs","flat-tb":"ou","vr180":"vr180"]
        applyManualSource(map[kind] ?? "flat",enable:false)
    }
    func noteManualEnabled(_ enabled:Bool) {
        MainActor.assumeIsolated {let store=ThreeDStore.shared;store.dispatch(.setOutput(enabled ? ThreeDPresentationPlan.restoredOutput(for:store.snapshot):.off))}
    }
    private var appliedThreeD:FilmThreeD?
    private var appliedPlan:ThreeDPresentationPlan?
    private var appliedEffects:ThreeDGlobalEffects?
    private var applyingStore=false
    private var appliedInternal:Bool?
    private var routeRevision: UInt64 = 0
    private var pendingRouteRevision:UInt64?
    private var pendingRouteOutput:ThreeDOutput?
    private var droppedRouteKey=""
    private var autoFitEntry=""
    func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect],revision:UInt64?=nil) {
        applyingStore=true;defer {applyingStore=false}
        routeRevision=revision ?? MainActor.assumeIsolated {ThreeDStore.shared.revision}
        let revision=routeRevision
        let requestedPlan=ThreeDPresentationPlan.make(state:state)
        let expectedLayout=requestedPlan.vrEnabled ? (["flat-2d3d":0,"flat-sbs":1,"flat-tb":2,"vr180":3,"vr180-tb":4,"vr360-mono":5,"vr360-tb":6][requestedPlan.luaKind] ?? 0):0
        let filename=URL(fileURLWithPath:recognitionPath).lastPathComponent
        let routeCommand:[Any]=["script-message-to","vr180_look","vr180-look-store-revision",String(revision),requestedPlan.luaKind,"store-applier",String(requestedPlan.vrEnabled),String(expectedLayout),String(requestedPlan.pack),requestedPlan.output.rawValue,requestedPlan.engine.rawValue,String(recognitionGeneration),filename,String(ProcessInfo.processInfo.processIdentifier)]
        let routeEnvelope=(try? JSONSerialization.data(withJSONObject:["command":routeCommand])).flatMap {String(data:$0,encoding:.utf8)}
        Diag.mediaRecord("3D-TRANSITION file=\(filename) generation=\(recognitionGeneration) revision=\(revision) previous=\(appliedPlan?.output.rawValue ?? "none") output=\(requestedPlan.output.rawValue) engine=\(requestedPlan.engine.rawValue) phase=requested app_pid=\(ProcessInfo.processInfo.processIdentifier)")
        let recognitionFilm=recognitionPath.isEmpty ? nil:MainActor.assumeIsolated {ThreeDRecognitionBridge.filmID(path:recognitionPath)}
        let identityReady = !recognitionIdentity.isEmpty && state.currentFilm == recognitionFilm
        // Off is a safety exit even without binding. Bound effects keep their
        // existing independent-tools behavior; the normal path below owns Off.
        if requestedPlan.output == .off && !identityReady {
            if let routeEnvelope {sendRaw(routeEnvelope)}
            setVRModeEnabled(false)
        }
        guard identityReady else {
            pendingRouteRevision=revision
            if effects.contains(.reapply),state.currentFilm != nil {pendingRouteOutput=state.current.output}
            let reason=recognitionIdentity.isEmpty ? "identityEmpty":"filmMismatch"
            let key=reason+"|"+(state.currentFilm?.rawValue ?? "none")
            if key != droppedRouteKey {droppedRouteKey=key;Diag.mediaRecord("3D-DROPPED reason=\(reason) storeFilm=\(state.currentFilm?.rawValue ?? "none") recognitionFilm=\(recognitionFilm?.rawValue ?? "none") revision=\(revision)")}
            return
        }
        // Identity may bind before current-file geometry. Keep the requested output
        // pending rather than publishing a zero-aspect flat2D-to-SBS projection.
        if requestedPlan.output == .sbs,requestedPlan.luaKind=="flat-2d3d",requestedPlan.luaAspect<=0,
           knownEyeAspect(kind:"flat-2d3d",filename:recognitionPath,width:latestWidth,height:latestHeight)<=0 {
            pendingRouteRevision=revision
            Diag.mediaRecord("3D-GEOMETRY-PENDING path=\(recognitionPath) width=\(latestWidth) height=\(latestHeight) revision=\(revision)")
            return
        }
        pendingRouteRevision=nil;pendingRouteOutput=nil;droppedRouteKey=""
        let previousProjectionKey=projectionKey
        let forceReapply=effects.contains(.reapply)
        if forceReapply {projectionKey=""}
        if let routeEnvelope {sendRaw(routeEnvelope)}
        let plan=ThreeDPresentationPlan.make(state:state)
        var desired=state.current;desired.source=plan.filmSource;desired.output=plan.output
        let engine=plan.engine
        let internalMedia=state.renderedSource != nil && state.renderedOutput == plan.output
        if internalMedia && desired.output == .anaglyph {desired.output = .off}
        if internalMedia != appliedInternal {
            sendRaw("{\"command\":[\"set_property\",\"user-data/gor/3d-internal\",\(internalMedia)]}")
            if let bytes=try? JSONSerialization.data(withJSONObject:["command":["set_property","user-data/gor/3d-parent-film-id",state.currentFilm!.rawValue]]),let text=String(data:bytes,encoding:.utf8) {sendRaw(text)}
            appliedInternal=internalMedia
        }
        // Generated source changes are now presented by this writer too, even
        // when the parent film and output have not changed.
        let planChanged=plan != appliedPlan
        let routeChanged=desired != appliedThreeD || planChanged
        let presentationChanged=forceReapply || routeChanged
        let effectOnlyChange = !routeChanged && state.effects != appliedEffects
        if presentationChanged {
            releaseProjectionLock()
            // Republish stale state without passing through Off: Off resets the
            // tracked pose and causes each independent effect click to jump.
            if routeChanged || (desired.output == .off && !effectOnlyChange) {setVRModeEnabled(false)}
            projectionKey=""
            let kind=plan.luaKind
            Diag.mediaRecord("3D-DECISION path=store_applier film=\(state.currentFilm!.rawValue) source=\(desired.source.format.rawValue) engine=\(engine.rawValue) output=\(desired.output.rawValue) pack=\(plan.pack) userTouched=\(desired.userTouched)")
            if desired.output == .off {if !effectOnlyChange {setVRModeEnabled(false)}} else {
                setSwapEyes(desired.source.swap)
                if engine == .nativeVR180 {
                    let aspect = plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:kind,filename:recognitionPath,width:latestWidth,height:latestHeight)
                    publishProjection(kind,aspect:aspect,reason:"nativeVR180")
                    let entering = !vrModeEnabled
                    if entering { setVRModeEnabled(true) }
                    vrModeSetByAutoDetect = true
                    if entering && !flatStereoFile { simulatePoseIfRequested() }
                } else {
                    publishProjection(kind,aspect:plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:kind,filename:recognitionPath,width:latestWidth,height:latestHeight),reason:"storeApplier")
                }
                let luaOutput = engine == .twoDVR180 ? "full_sbs" : desired.output.rawValue
                sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-output\",\"\(luaOutput)\"]}")
                setVRModeEnabled(true)
            }
            appliedThreeD=desired
        }
        // Refresh late geometry without route/media/pose reset; projectionKey dedupes.
        if !presentationChanged, desired.output != .off {publishProjection(plan.luaKind,aspect:plan.luaAspect > 0 ? plan.luaAspect : knownEyeAspect(kind:plan.luaKind,filename:recognitionPath,width:latestWidth,height:latestHeight),reason:"sourceGeometry")}
        appliedPlan=plan
        if state.effects != appliedEffects || presentationChanged {
            func n(_ key:ThreeDEffectKey,_ fallback:Double)->Double {if case let .number(v)?=state.effects[key] {return v};return fallback}
            let p=ThreeDAutoRoute.previewParams(mode:desired.output.rawValue,strength:n(.strength,1),screenDepthM:n(.screenDepth,1.5),screenDeg:n(.screenSize,75),surround:state.effects[.surround] == .text("black") ? "black":"soft")
            if desired.output != .off {
            sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-pack\",\"\(plan.pack)\",\"\(p.gain)\",\"\(p.conv)\",\"\(p.zoom)\",\"\(p.soft)\"]}")
            }
            if case let .bool(v)?=state.effects[.head] {setHeadTrackingEnabled(v,remember:false)}
            if case let .bool(v)?=state.effects[.blink] {_=setBlinkControlEnabled(v,osd:false,remember:false)}
            if case let .bool(v)?=state.effects[.crossEye] {setSwapEyes(v != desired.source.swap);sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-viewing-cross\",\"\(v ? "1":"0")\"]}")}
            if case let .number(v)?=state.effects[.ipd] {publishBaseIPD(v/Self.ndcToMM,persist:false)}
            sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-surround-invert\",\"\(state.effects[.surroundInvert] == .bool(true) ? "1":"0")\"]}")
            appliedEffects=state.effects
        }
        // Actual Off wins over callbacks emitted while reapplying persisted effects.
        // Independent tool changes while already2D remain usable and keep their pose.
        if desired.output == .off && !effectOnlyChange {setVRModeEnabled(false)}
        if internalMedia && desired.output != .off {sendRaw(#"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","on","true"]}"#)}
        let fitEntry=(desired.output == .sbs || desired.output == .halfSBS) && plan.filmSource.format == .flat2D ? "\(recognitionGeneration)|\(recognitionIdentity)|\(desired.output.rawValue)":""
        if !fitEntry.isEmpty && fitEntry != autoFitEntry {resetFilmView(smooth:true)}
        autoFitEntry=fitEntry
        if effects.contains(.resetView) {resetFilmView();recenterHeadTracking()}
        if presentationChanged {Diag.mediaRecord("vrAppliedRoute file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) source=\(plan.filmSource.format.rawValue) output=\(plan.output.rawValue) engine=\(plan.engine.rawValue) probe=\(latestProbeStatus)")}
        publishThreeDAppliedState(plan: plan)
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-route-complete\",\"\(revision)\",\"store-applier\"]}")
        // Notify once after the complete route; intermediate false->true switches are not committed geometry.
        if presentationChanged || projectionKey != previousProjectionKey {onVRModeApplied?(vrModeEnabled)}
    }
    /// Read-only receipt of the applied 3D route, stamped so a driver can tell this build/process
    /// from a stale capture. This publishes state only; it must never change behavior.
    private func publishThreeDAppliedState(plan: ThreeDPresentationPlan) {
        let explicit=MainActor.assumeIsolated {ThreeDStore.shared.appliedOutput=plan.output;return ThreeDStore.shared.snapshot.current.explicitOutput?.rawValue ?? "none"}
        Diag.mediaRecord("3D-APPLIED phase=submitted file=\(URL(fileURLWithPath:recognitionPath).lastPathComponent) generation=\(recognitionGeneration) revision=\(routeRevision) engine=\(plan.engine.rawValue) output=\(plan.output.rawValue) source=\(SourceFormatChoice.raw(plan.filmSource)) pack=\(plan.pack) explicit=\(explicit)")
        let payload: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "revision": routeRevision,
            "build": BuildID.value(),
            "timestamp": Int64((Date().timeIntervalSince1970 * 1000).rounded()),
            "stereoSource": SourceFormatChoice.raw(plan.filmSource),
            "engine": plan.engine.rawValue,
            "output": plan.output.rawValue,
            "vr_mode": vrModeEnabled
        ]
        sendRaw(MPVCommand.make(["set_property", "user-data/gor/3d-applied-state", payload]))
    }
    func knownEyeAspect(kind: String, filename: String, width: Double, height: Double, fullByContract:Bool=false) -> Double {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        if kind == "flat-2d3d" {let a=width*latestPixelAspect/height;return a.isFinite && a>0 ? a:0}
        let source=SourceFormatChoice.get(recognitionPath).split(separator:":").first.map(String.init) ?? "auto"
        if source=="sbs" {return width*latestPixelAspect/height/2}
        if source=="half_sbs" {return width*latestPixelAspect/height}
        if source=="ou" {return width*latestPixelAspect/height*2}
        if source=="half_ou" {return width*latestPixelAspect/height}
        if kind == "flat-tb" {return width*latestPixelAspect/height*2}
        if kind != "flat-sbs" { return width / height / 2 }
        return SBSGeometry.resolve(width:width,height:height,pixelAspect:latestPixelAspect,filename:filename,stereoProven:kind=="flat-sbs",fullByContract:fullByContract,cropWidth:nil,cropHeight:nil)?.aspect ?? 0
    }
    func publishProjection(_ kind: String, aspect: Double, reason: String) {
        projectionKind = kind
        if #available(macOS 12.0, *) {HeadTracker.shared.nativeMotionResponsive=kind.hasPrefix("vr")}
        flatStereoFile = kind == "flat-sbs" || kind == "flat-tb" || kind == "flat-2d3d"
        flatAutoEyeAspect = flatStereoFile ? aspect : 0
        let x=0.0,y=0.0,w=1.0,h=1.0 // original full eye; recognition crop is UI-only
        let key = "\(kind):\(aspect):\(x):\(y):\(w):\(h)"
        guard projectionKey != key else { return }
        projectionKey = key
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-source-eye-crop\",\"\(x)\",\"\(y)\",\"\(w)\",\"\(h)\"]}")
        Diag.log("sbsEyeCrop x=\(x) y=\(y) w=\(w) h=\(h) eyeAspect=\(aspect) basis=sampledUnionWithGuard")
        if flatStereoFile && aspect == 0 {
            GeomTrace.logChanged("vrAspectUnknown", "{\"k\":\"vrAspectUnknown\",\"reason\":\"halfFullPackingUnspecified\",\"preview\":\"storedHalfFrame\",\"manualOverrideAvailable\":true}")
        }
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-projection\",\"\(kind)\",\"\(aspect)\"]}")
        GeomTrace.log("vrProjection", "{\"k\":\"vrProjection\",\"flat\":\(flatStereoFile),\"eyeAspect\":\(aspect),\"reason\":\"\(reason)\"}")
    }
    func autoDetectFromVideoParams(stereoMode: String?, width: Double, height: Double, filename: String, pixelAspect:Double=1,sourceCrop:String?=nil,containerMetadata:[String:String]=[:]) {
        guard width > 0, height > 0 else { return }
        // Prepared render shots belong to the source film's OUTPUT plan, not a new SOURCE decision.
        if ThreeDRecognitionBridge.internalMedia(filename) {return}
        let pendingChoice=pendingRouteOutput;pendingRouteOutput=nil
        let geometryChanged=latestWidth != width || latestHeight != height || latestPixelAspect != pixelAspect
        // Synchronous pending OUTPUT replay must see this film's geometry.
        latestWidth = width; latestHeight = height; latestStereo = stereoMode;latestPixelAspect=pixelAspect
        if recognitionPath != filename {
            recognitionPath = filename; recognitionGeneration &+= 1
            recognitionIdentity = VRRecognition.fileIdentity(filename)
            MainActor.assumeIsolated {ThreeDStore.shared.bindSource(path:filename,id:ThreeDRecognitionBridge.resolveAtOpen(path:filename))}
            if pendingRouteRevision != nil {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.reapply])}}
            // Old per-projection caches are historical UI data, never SOURCE evidence.
            manualProjection=nil;manualProjectionIsCurrentSession=false
            projectionKey = ""; recognitionLogKey="";latestProbeStatus="pending"; vrModeSetByAutoDetect = false; detectedStereoKind = nil; singleSwitchActive = false; singleSwitchPending = false
            probeStarted = false; probeFinished = false; probeProjection = nil; openingProjection = nil; probeStereoSBS = false;probeEyeAspect=nil;probeEyeCrop=nil;sourceMeasuredEyeAspect=nil;probeStereoTB=false
        }
        latestContainerMetadata=containerMetadata
        latestSourceCrop=SBSGeometry.parseCrop(sourceCrop)
        if !probeStarted, !filename.isEmpty {
            probeStarted = true
            Diag.mediaRecord("vrProbeStart file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(recognitionGeneration)")
            let generation = recognitionGeneration
            VRProjectionProbe.inspect(filename) { [weak self] result in
                guard let self, self.recognitionGeneration == generation, self.recognitionPath == filename else { return }
                self.probeFinished = true
                Diag.mediaRecord("vrProbeResult file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(generation) status=\(result.status) projection=\(result.projection ?? "none") sbs=\(result.stereoSBS) tb=\(result.stereoTopBottom)")
                self.latestProbeStatus=result.status
                self.probeProjection = result.projection
                self.probeStereoSBS = result.stereoSBS
                self.probeStereoTB=result.stereoTopBottom
                self.probeEyeAspect=result.eyeAspect
                self.probeEyeCrop=result.eyeCrop
                GeomTrace.log("vrRecognition", "{\"k\":\"vrRecognition\",\"status\":\"\(result.status)\",\"projection\":\"\(result.projection ?? "unknown")\",\"stereoSBS\":\(result.stereoSBS)}")
                self.autoDetectFromVideoParams(stereoMode:self.latestStereo,width:self.latestWidth,height:self.latestHeight,filename:filename,pixelAspect:self.latestPixelAspect,sourceCrop:self.latestSourceCrop.map {"\($0.0)x\($0.1)"},containerMetadata:self.latestContainerMetadata)
            }
        }
        let evidence=VRRecognition.mpvEvidence(stereoMode:stereoMode,metadata:containerMetadata)
        openingProjection = ThreeDProjectionMemory.resolve(current: openingProjection, evidence: evidence.projection, probe: probeProjection)
        let projection = openingProjection
        let vrChoice=VRRecognition.choose(remembered:nil, projection:projection, stereoSBS:evidence.stereoSBS || probeStereoSBS, filename:filename, width:width, height:height, stereoTB:evidence.stereoTB || probeStereoTB);let resolved=vrChoice.kind
        let metadata=ThreeDRecognitionBridge.source(projection:projection,sbs:evidence.stereoSBS || probeStereoSBS,tb:evidence.stereoTB || probeStereoTB,filename:filename)
        let tags=ThreeDRecognitionBridge.filename(filename)
        let detected=metadata ?? tags ?? ThreeDSource(.flat2D)
        detectedStereoKind=detected.format == .flat2D ? nil:detected.projection
        let input=ThreeDEvidence(metadata:metadata,filenameTag:tags,suggestion:VRRecognition.suggestion(filename:filename,width:width,height:height))
        guard openReceipt.accept(input) else {if geometryChanged {MainActor.assumeIsolated {applyThreeDState(ThreeDStore.shared.snapshot,[.present])}};return}
        // 196w: record the decision only when the receipt accepted a real change.
        // The 200 ms poll flush replays identical inputs (~7/s observed) and the
        // verdict itself is already deduped by accept; per-flush logging was pure
        // main-thread cost. Real route decisions still log here.
        Diag.mediaRecord("vrOpenDecision {\"k\":\"vrOpenDecision\",\"decision\":\"\(vrChoice.kind)\",\"reason\":\"\(vrChoice.reason)\"}")
        Diag.mediaRecord("vrOpenRoute film=\(MainActor.assumeIsolated {ThreeDRecognitionBridge.filmID(path:recognitionPath).rawValue}) file=\(URL(fileURLWithPath:filename).lastPathComponent) generation=\(recognitionGeneration) probe=\(latestProbeStatus) metadata=\(metadata?.format.rawValue ?? "none") tag=\(tags?.format.rawValue ?? "none") detected=\(detected.format.rawValue)")
        MainActor.assumeIsolated {
            let store=ThreeDStore.shared
            store.dispatch(.open(ThreeDRecognitionBridge.filmID(path:recognitionPath),input))
            // A click during the unbound gap belongs to the file now binding,
            // never to the previous film's source format.
            if let output=pendingChoice {pendingRouteOutput=nil;store.dispatch(.setOutput(output))}
        }
    }
    /// GOR_VR_SIM_POSE=1 only (self-test): switch head tracking on without the camera (updateHeadTrackingCamera
    /// then drives the synthetic pose). remember:false keeps the owner's saved preference untouched.
    private func simulatePoseIfRequested() {
        guard ProcessInfo.processInfo.environment["GOR_VR_SIM_POSE"] == "1" else { return }
        setHeadTrackingEnabled(true, remember: false)
    }
    func sendVRLookNudge(deltaX: CGFloat, deltaY: CGFloat, deltaRollDegrees:Double=0) {
        let dyawDeg   = Double(deltaX) * Self.vrYawPitchDegPerPoint
        let dpitchDeg = Double(deltaY) * Self.vrYawPitchDegPerPoint
        let dyawRad   = dyawDeg   * Double.pi / 180.0
        let dpitchRad = dpitchDeg * Double.pi / 180.0
        ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"\(dyawRad)\",\"\(dpitchRad)\",\"0\",\"\(deltaRollDegrees * Double.pi / 180)\"]}")
    }
    func sendVRFovNudge(deltaFovDegrees: Double) {
        ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-nudge\",\"0\",\"0\",\"\(deltaFovDegrees)\"]}")
    }

    // ── Core toggle ─────────────────────────────────────────────────────────

    func setVRModeEnabled(_ enabled: Bool) {
        guard applyingStore else {noteManualEnabled(enabled);return}
        vrModeEnabled = enabled
        ScreenCaptureEngine.shared.vrModeActive = enabled
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-enabled\",\"\(enabled ? "true" : "false")\"]}")
        if enabled {
            if Self.vrAutoFullscreen { sendRaw(#"{"command":["set","fullscreen","yes"]}"#) }
            sendSwapEyes(); sendPersistedBaseIPD()
            // Effects are explicit independent preferences; output changes never start head tracking.
            // Global effects are applied only from ThreeDStore, independent of output.
        } else {
            if Self.vrAutoFullscreen { sendRaw(#"{"command":["set","fullscreen","no"]}"#) }
        }
        traceCameraState("vrMode")
        updateCameraTraceHeartbeat()
    }

    /// GOR_TRACE_GEOM=1 only: 1 Hz settled-state samples while VR is on, so the
    /// self-test can observe the capture session over a window instead of relying on
    /// a single transition line.
    private var cameraTraceTimer: DispatchSourceTimer?
    private func updateCameraTraceHeartbeat() {
        guard GeomTrace.on else { return }
        cameraTraceTimer?.cancel(); cameraTraceTimer = nil
        guard vrModeEnabled else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in self?.traceCameraState("tick") }
        t.resume()
        cameraTraceTimer = t
    }

    /// Republish the canonical persisted dial when VR starts, including its zero default.
    func sendPersistedBaseIPD() {
        // Always republish the canonical mm, including 0: a re-entry must not keep a stale Lua mode/value.
        publishBaseIPD(currentBaseIPD, persist: false)
    }
    private func sendSwapEyes() {
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-swap-eyes\",\"\(swapEyes ? "1" : "0")\"]}")
    }

    func setSwapEyes(_ on: Bool) {
        guard applyingStore else {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.crossEye,.bool(on)))};return}
        swapEyes = on
        sendSwapEyes(); showBlinkOSD(on ? "cross-eye order on" : "cross-eye order off")
    }

    /// Blink log-only measurement (phase 2): needs head-tracking frames; starts nothing by itself.
    var blinkLogEnabled: Bool {
        if #available(macOS 12.0, *) { return HeadTracker.shared.blinkLogEnabled }
        return false
    }
    var onSoftVideoBlink: ((Double) -> Void)?
    private func showBlinkOSD(_ text: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", text, 3500]]),
              let json = String(data: data, encoding: .utf8) else { return }
        sendRaw(json)
    }
    func sendRaw(_ original: String) { // Route mutations have one owner and one store revision.
        var json=original
        if var object=(try? JSONSerialization.jsonObject(with:Data(json.utf8))) as? [String:Any],
           var command=object["command"] as? [Any],command.count>2,
           let name=command[2] as? String,ThreeDRouteEnvelope.messages.contains(name) {
            guard applyingStore else {Diag.log("3D-REJECTED sender=controller-outside-applier message=\(name) values=\(command) revision=none");return}
            let revision=routeRevision
            if name == "vr180-look-plan-lock" && command.count == 4 {command.append("false")}
            // arch-195c N3: no Swift-side admission gate on the mpv wire.
            // Stamped commands go out exactly as shipped; the restored
            // shipped Lua owns admission and the 3D-REJECTED record.
            command += [String(revision),"store-applier"];object["command"]=command
            if let data=try? JSONSerialization.data(withJSONObject:object),let encoded=String(data:data,encoding:.utf8) {json=encoded}
        }
        MainActor.assumeIsolated {ThreeDStore.shared.recordAppliedCommand(json)}
        ipcCommand(json)
    }
    var singleSwitchActive = false, singleSwitchPending = false; private(set) var detectedStereoKind: String?        // native detection of the open film (nil = not known to be stereo), read by singleSwitchPlan()
    /// Idempotent blink-control switch: the shift+e / menu toggle and the VR-entry default
    /// both land here. Blink owns a camera consumer (updateCaptureConsumers), so it works
    /// whether or not head tracking is on - the 7634 route started no camera at all unless
    /// head tracking was already running, which is why nothing responded.
    @discardableResult
    func setBlinkControlEnabled(_ on: Bool, osd: Bool = true, remember: Bool = true) -> Bool {
        if remember && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.blink,.bool(on)))};return on}
        guard #available(macOS 12.0, *) else {
            if osd { showBlinkOSD("blink control needs macOS 12 or later") }
            return false
        }
        blinkControlPreferred = on

        if on == HeadTracker.shared.blinkLogEnabled {
            updateCaptureConsumers()   // state unchanged; the camera may still need reconciling (file loaded, VR re-entry)
            if osd { showBlinkOSD(on ? "blink control on" : "blink control off") }
            return on
        }
        HeadTracker.shared.blinkLogEnabled = on   // turning off snapshots the session atomically inside the setter
        onExplorableSurface?()
        traceCameraState("blinkLog")
        if on {
            // gor.vr.blinkAnalog / gor.vr.blinkRobust: default ON; defaults write ... -bool NO restores the previous behaviour.
            IntentionalEyeClosure.analog = (UserDefaults.standard.object(forKey: "gor.vr.blinkAnalog") as? Bool) ?? true
            EyeGestureCommands.robust = (UserDefaults.standard.object(forKey: "gor.vr.blinkRobust") as? Bool) ?? true
            // gor.vr.blinkCadence / gor.vr.poseHoldLock (197i): default ON; -bool NO restores the shipped behaviour byte-identically.
            EyeGestureCommands.cadenceAdaptive = (UserDefaults.standard.object(forKey: "gor.vr.blinkCadence") as? Bool) ?? true
            HeadTracker.poseHoldLock = (UserDefaults.standard.object(forKey: "gor.vr.poseHoldLock") as? Bool) ?? true
            sendRaw(BlinkCommandRoute.analogIPC(IntentionalEyeClosure.analog))
            HeadTracker.shared.onBlinkIndicator = nil
            // Owner pilot: phonemsg-01M6RD9QYP8KCP2S8T2VTE2T8M double closure -> +60s (superseded by21:08 phonemsg-01M70QYE8XZCR62ETBTXN27PRE);
            // phonemsg-01M6RDAAK0XAV0GJ8ATDF39RPX / 01M6RDAG5R7R9YTQXC864HM8AQ single -> soft VIDEO blink.
            HeadTracker.shared.onEyeClosure = { [weak self] left, right, uncertain in
                self?.sendRaw(BlinkCommandRoute.lidsIPC(left, right, uncertain))
            }
            HeadTracker.shared.onBlinkControl = nil // command dispatch has one mutual-exclusion owner.
            HeadTracker.shared.onEyeCommand = { [weak self] command in
                guard let self, self.loadedVideoActive else { return }
                switch command {
                case let .seek(seconds): self.sendRaw(BlinkCommandRoute.seekIPC(seconds, commandHeld: NSEvent.modifierFlags.contains(.command)))
                case .playPause: if NSEvent.modifierFlags.contains(.control) { self.sendRaw(BlinkCommandRoute.playPauseIPC) }
                }
            }
            GeomTrace.beginBlinkLog(session: HeadTracker.shared.blinkSessionID) { [weak self] sid, reason in
                // Diagnostic storage failure: GeomTrace has already set blinkLogStopped for this session,
                // so no further disk writes happen and this callback never fires twice per session. Blink
                // CONTROL does not depend on the measurement log, but SCE's recognizer (logBlinkSample /
                // captureOutput) is gated on blinkLogEnabled - so the session, epoch, callbacks, preference
                // and camera consumer all stay exactly as they are: no stopBlinkLogIfCurrent, no flush, no
                // session close while live. Delivered on main; both reads below are main-serialized with
                // every session transition, so a stale failure from before an OFF->ON has zero effects.
                guard HeadTracker.shared.blinkLogEnabled, HeadTracker.shared.blinkSessionID == sid else { return }
                self?.showBlinkOSD("\(reason) - blink control stays on")
            }
        } else {
            HeadTracker.shared.flushBlinkSummary(osd: nil)
            blinkControlDidStop(osd: nil)
        }
        updateCaptureConsumers()
        if osd { showBlinkOSD(on ? "blink control on" : "blink control off") }
        return on
    }

    /// Single off-path for every stop cause (manual toggle, VR exit, diagnostic storage
    /// failure): clears the live callbacks, zeroes the shader lids through the production
    /// IPC route and releases the blink camera consumer. Safe when already stopped.
    private func blinkControlDidStop(osd: String?) {
        if #available(macOS 12.0, *) {
            HeadTracker.shared.onBlinkIndicator = nil
            HeadTracker.shared.onBlinkDetected = nil
            HeadTracker.shared.onEyeClosure = nil
            HeadTracker.shared.onEyeCommand = nil
            HeadTracker.shared.onBlinkControl = nil
        }
        sendRaw(BlinkCommandRoute.lidsClearedIPC)
        updateCaptureConsumers()
        if let osd { showBlinkOSD(osd) }
    }

    @discardableResult
    func toggleBlinkLog() -> Bool {
        setBlinkControlEnabled(!blinkControlPreferred)
    }

    @discardableResult
    func toggleSwapEyes() -> Bool {
        setSwapEyes(!swapEyes)
        return swapEyes
    }

    @discardableResult
    func toggleHeadTracking() -> Bool {
        setHeadTrackingEnabled(!headTrackingEnabled)
        showBlinkOSD(headTrackingEnabled ? "head tracking on" : "head tracking off")
        return headTrackingEnabled
    }


    /// Explicit choices are remembered; automatic VR stops preserve that preference.
    var onExplorableSurface: (() -> Void)?
    func setHeadTrackingEnabled(_ enabled: Bool, remember: Bool = true) {
        if remember && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.head,.bool(enabled)))};return}
        headTrackingPreferred=enabled
        guard enabled != headTrackingEnabled else { return }
        guard #available(macOS 12.0, *) else {
            print("[VR180Controller] Head-tracking needs macOS 12+ (VNDetectFaceRectanglesRequest revision 3).")
            return
        }
        headTrackingEnabled = enabled
        onExplorableSurface?()
        if !enabled { resetOrientation() }
        updateCaptureConsumers()
        traceCameraState("headTracking")
    }

    /// GOR_TRACE_GEOM=1 only: records whether the capture session is requested /
    /// running so the self-test can assert that opening a VR file does not start it.
    func traceCameraState(_ why: String) {
        guard GeomTrace.on else { return }
        var requested = false, running = false, consumers = 0, ambient = false
        if #available(macOS 12.0, *) {
            requested = HeadTracker.shared.isRequested
            running = HeadTracker.shared.isRunning
            (consumers, ambient) = HeadTracker.shared.traceConsumers
        }
        let vrOwned = consumers - (ambient ? 1 : 0)
        GeomTrace.log("vrCamera", "{\"k\":\"vrCamera\",\"why\":\"\(why)\",\"vr\":\(vrModeEnabled),\"head\":\(headTrackingEnabled),\"camActive\":\(headTrackingCameraActive),\"sessionRequested\":\(requested),\"sessionRunning\":\(running),\"consumers\":\(consumers),\"ambient\":\(ambient),\"vrOwned\":\(vrOwned)}")
    }

    /// Reconciles BOTH camera consumers on every state change - no shared early return,
    /// so an unchanged leg never skips the other (7634 returned early on the head edge and
    /// blink had no leg at all). Head-motion keeps its pause policy (playbackActive); the
    /// loadedVideoActive signal keeps paused head motion and blink live.
    private func updateCaptureConsumers() {
        guard #available(macOS 12.0, *) else { return }
        refreshToolsActive()
        let headShould = CaptureConsumerRules.headShouldRun(headTrackingEnabled: headTrackingEnabled, playbackActive: loadedVideoActive)
        if headShould != headTrackingCameraActive {
            headTrackingCameraActive = headShould
            if headShould {
                HeadTracker.shared.beginPoseSession(); HeadTracker.shared.onPoseUpdate = { [weak self] pose in
                    self?.applyHeadPose(pose)
                }
                if ProcessInfo.processInfo.environment["GOR_VR_SIM_POSE"] == "1" {
                    HeadTracker.shared.startSimulatedPose()   // self-test only: synthetic pose, camera never started
                } else {
                    HeadTracker.shared.start(owner: 1)
                    headOwnsRealCameraConsumer = true
                }
            } else {
                HeadTracker.shared.onPoseUpdate = nil;onSubtitleTilt?(0,0);onUITilt?(0)
                HeadTracker.shared.stopSimulatedPose()
                if headOwnsRealCameraConsumer {   // SIM_POSE acquired nothing: never release the blink leg's consumer
                    HeadTracker.shared.stop(owner: 1)
                    headOwnsRealCameraConsumer = false
                }
            }
        }
        let blinkShould = CaptureConsumerRules.blinkShouldRun(blinkOn: HeadTracker.shared.blinkLogEnabled,
                                                              vrEnabled: vrModeEnabled,
                                                              loadedVideoActive: loadedVideoActive,
                                                              cameraAllowed: Self.blinkCameraAllowed)
        if blinkShould != blinkCameraActive {
            blinkCameraActive = blinkShould
            // Blink needs frames only: never touches the onPoseUpdate slot (the head leg's
            // alone); logBlinkSample runs on every delivered camera frame in the engine.
            if blinkShould { HeadTracker.shared.start(owner: 2) } else { HeadTracker.shared.stop(owner: 2) }
        }
    }

    /// Automated tests never open the camera (same posture as headTrackingAutoStartAllowed).
    static var blinkCameraAllowed: Bool {
        ProcessInfo.processInfo.environment["GOR_VR_TEST_NO_CAMERA"] != "1"
    }

    private var recenterPosePublishing=false
    var onSubtitleTilt:((Double,Double)->Void)?
    var onVRModeApplied:((Bool)->Void)?
    var onUITilt:((Double)->Void)?
    private(set) var depthDistanceMM: Double?
    private func applyHeadPose(_ pose: HeadPose) {
        depthDistanceMM = pose.distanceMM
        guard headTrackingEnabled, loadedVideoActive else { return }
        //192d: all tracked pose filtering happens in Swift before this message.
        let direction=MainActor.assumeIsolated {ThreeDStore.shared.snapshot.effects[.headInvert] == .bool(true) ? -1.0:1.0}
        let yaw   = direction * Self.headRotationGain * pose.yaw
        let pitch = direction * Self.headRotationGain * pose.pitch
        let fov:Double
        if projectionKind.hasPrefix("vr") {
            fov=Self.headTrackingRestFovDeg + direction * Self.headFovGain * Self.headLeanNudgeFovDegPerUnit * pose.zOffset
        } else {
            // Display policy, not a camera-validity threshold: a flat film stays
            // at90...125% for head distance; manual zoom-out has its own wider rail.
            // Keep the measured pupil ratio in scale space, with the original sensitivity.
            let measured=1+direction*Self.headFovGain*pose.zOffset
            let scale=measured.isFinite ? min(1.25,max(0.90,measured)):1
            fov=2*atan(tan(Self.headTrackingRestFovDeg*Double.pi/360)/scale)*180/Double.pi
        }
        let roll  = direction * Self.headRotationGain * pose.roll
        let filmRoll=projectionKind.hasPrefix("vr") ? (direction * (pose.nativeRawRoll ?? pose.roll)):roll
        let pairRoll=projectionKind.hasPrefix("vr") ? (direction * (pose.fusionRoll ?? pose.roll)):roll
        let overlayRoll=projectionKind.hasPrefix("vr") ? 0:filmRoll
        onSubtitleTilt?(overlayRoll,projectionKind.hasPrefix("vr") ? 0:pairRoll*(swapEyes ? 1:-1))
        onUITilt?(overlayRoll)
        let headX = direction * Self.headTranslateMetersPerUnit * pose.xOffset
        let headY = direction * Self.headTranslateMetersPerUnit * pose.yOffset
        let headZ = 0.0 //192d D2: fov alone carries distance zoom, never a second multiplying headZ
        // Convergence is the same bounded display-distance request for a flat
        // film. Keeping the raw value here would bypass its viewport envelope.
        let flatDistance=pose.zOffset.isFinite ? min(0.25,max(-0.10,pose.zOffset)):0
        let ipdNudge = Self.headIpdNudgePerUnit * (projectionKind.hasPrefix("vr") ? pose.zOffset:flatDistance)
        // Block 182 2: the distance rule lives in vr180-look.lua; these three args ride on the same message.
        let distArg = pose.distanceMM.map { String(format: "%.2f", $0) } ?? "none"
        let distReason = pose.distanceFallback ?? "ok"
        let mmPerPx = VRDistance.mmPerPx()
        let ordered=recenterPosePublishing ? ",\"request_id\":194" : ""
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-orientation\",\"\(yaw)\",\"\(pitch)\",\"\(fov)\",\"\(roll)\",\"\(ipdNudge)\",\"\(headX)\",\"\(headY)\",\"\(headZ)\",\"\(distArg)\",\"\(distReason)\",\"\(mmPerPx)\",\"\(direction * (pose.fusionRoll ?? pose.roll))\",\"\(direction * (pose.nativeRawRoll ?? pose.roll))\"]\(ordered)}")
    }

    func recenterHeadTracking() {
        guard #available(macOS 12.0, *) else { return }
        resetFilmView()
        recenterPosePublishing=true;defer {recenterPosePublishing=false}
        HeadTracker.shared.recenter()
    }

    /// 180d test surface: the session IPD value for the selftest's
    /// snapshot/restore (the state itself stays private).
    var testCurrentBaseIPD: Double { currentBaseIPD }

    /// Absolute test cleanup through the same controller publication path.
    /// Inert without geometry tracing; restores the saved preference to its snapshot (below).
    /// Taken once when the selftest snapshots the dial: exact presence and value of the canonical key.
    private var testIPDSnapshot: (had: Bool, mm: Double, runtimeMM: Double)?
    func snapshotIPDForTest() { }
    func restoreBaseIPDForTest(_ value:Double) {
        guard GeomTrace.on else {return}
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.ipd,.number(value*Self.ndcToMM)))}
    }

    func adjustBaseIPD(by delta: Double) {
        MainActor.assumeIsolated {let store=ThreeDStore.shared;let current:Double;if case let .number(v)?=store.snapshot.effects[.ipd] {current=v} else {current=0};store.dispatch(.setEffect(.ipd,.number(current+delta*Self.ndcToMM)))}
    }
    private func publishBaseIPD(_ value: Double, persist: Bool = true) {
        currentIPDOffsetMM = value * Self.ndcToMM
        if persist && !applyingStore {MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.setEffect(.ipd,.number(currentIPDOffsetMM)))};return}
        sendRaw("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-ipd-mm\",\"\(currentIPDOffsetMM)\"]}")
        GeomTrace.log("vrIPD", String(format: #"{"k":"vrIPD","v":%.17g,"mm":%.17g}"#, currentBaseIPD, currentIPDOffsetMM))
    }
}

