// ================================================================
//  PPController.swift - central overlay NSView
//  Owns: construction, mpv IPC polling and dispatch, frame layout, cross-feature decisions
//  Answers: I11 I14 I16 I27 I31 I34 I35 I36 I37 I41 I42 I44 · TRAP-04 TRAP-06 TRAP-07 TRAP-10
//  Contract: applyVideoFrame() is the only writer of spineUI/sidebarUI/subtitleView frames
//  Not here: self-contained features (PPController_Features.swift)
// ================================================================
//  Rules: New narrow feature state goes in PPController_Features.swift;
//  broad or cross-feature decisions stay here. Read mode flags through
//  forwarding properties. Keep unmigrated callers behind named shims.
// ================================================================
import AppKit
import CoreImage
import Foundation
import CoreFoundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
// ================================================================
//  PPController - overlay composition and dispatch
// ================================================================
// I14: construction sites are AppDelegate's launchMPV checkTimer, handleWakeUp (and its recovery timer), and attachOverlay.
final class PPController: NSView {

    // Typed backend composition only; wire format and decoding remain backend-owned.
    var playbackOperations:PlayerPlaybackOperations {
        PlayerPlaybackOperations(command:ipcCommand,persistent:persistentConnection.write,packet:ipcClient.sendCropPacket,reset:ipcClient.resetCropPackets)
    }
    func pausePlayback() {playbackOperations.pause()}
    func enableLivePhoton() {playbackOperations.photonLive()}

    // MARK: - State
    static let shadowRadius:  CGFloat = 2.2
    static let shadowOpacity: Float   = 0.5
    static var globalShadow: NSShadow {
        let s = NSShadow()
        s.shadowColor      = NSColor.black.withAlphaComponent(0.5)
        s.shadowBlurRadius = PPController.shadowRadius
        s.shadowOffset     = .zero
        return s
    }

    // ── UI state ────────────────────────────────────────────────────────
    let spineUI      = SpineUI(frame: .zero)
    let sidebarUI    = SidebarUI(frame: .zero)
    let subtitleView = SubtitleView(frame: .zero)

    // ── IPC state ───────────────────────────────────────────────────────
    let ipcPath: String
    let ipcClient: IPCClient
    private let persistentConnection: PersistentEventConnection

    private let pollEngine: PollEngine

    private let brightness:   BrightnessController
    private let cropDetector: CropDetector

    private var hideTimer:    Timer?
    private var eventMonitor: Any?
    private var trackListCache: [String: [(id: Int, title: String)]] = [:]

    private(set) var currentTime: Double = 0
    private(set) var duration:    Double = 0

    // Owner-log 260918 items 1+2: one mpv-poll-derived liveness signal feeds
    // the SCE dead-tap rebuild (item 1) and the dimming stall-hold (item 2).
    // Main-thread only; driven from handlePollResults.
    private var livenessLastTimePos: Double?
    private var livenessLastAdvanceAt: TimeInterval = 0
    private var livenessLastNoteAt: TimeInterval = 0
    private var playbackStalled = false
    private(set) var isPlaying:   Bool   = false
    
    static let defaultVolume: Float = 1.0

    /// Monotonic generation of confirmed file loads. Bumped on the persistent
    /// connection queue inside handleMPVEvent on "file-loaded" - mpv only
    /// emits it once the file opened, so failed loads never move it.
    private(set) var fileLoadedGeneration: Int = 0
    // Only touched by handleMPVEvent on the persistent connection queue.
    private var lastPlaybackDiagnosticGeneration = -1
    private var lastPlaybackFilenameGeneration: Int?
    private let playbackDiagnosticQueue = DispatchQueue(label: "gor.playback.diagnostic", qos: .utility)
    /// Callback fired right after each fileLoadedGeneration bump on the
    /// persistent connection queue.
    var onFileLoaded: ((Int) -> Void)?
    private(set) var volume: Float = PPController.defaultVolume

    var cursorHidden = false
    private var cursorTimer: Timer?

    // ── Feature state ───────────────────────────────────────────────────
    private var dragDropHandler: DragDropHandler?
    private var inputController: InputController?
    private var contentAdaptiveDimming: ContentAdaptiveDimming?

    var currentPath: String? { currentFilePath.isEmpty ? nil : currentFilePath }
    var isPaused: Bool { !isPlaying }

    struct PlayerState {
        var path:   String?
        var time:   Double
        var paused: Bool
    }

    private lazy var playerViewStub: PlayerViewStub = PlayerViewStub(controller: self)

    private var nativeVideoAspect: Double?
    private var videoLayoutAspect: Double?
    private var videoLayoutRotation: Double = 0

    static func rotatedAspect(width: Double, height: Double, rotation: Double) -> Double? {
        guard width > 0, height > 0 else { return nil }
        return abs(rotation.truncatingRemainder(dividingBy: 180)) == 90 ? height / width : width / height
    }

    static func rotatedCropRect(_ rect: CGRect, rotation: Double) -> CGRect {
        let angle = (Int(rotation) % 360 + 360) % 360
        switch angle {
        case 90: return CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case 180: return CGRect(x: 1 - rect.maxX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        case 270: return CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
        default: return rect
        }
    }

    var videoDisplayW: Double = 0
    var videoDisplayH: Double = 0
    var appliedVideoFrame:           CGRect = .zero
    var appliedVideoFrameWindowSize: CGSize = .zero

    private var vr180Controller: VR180Controller?
    var vrModeEnabled: Bool { vr180Controller?.vrModeEnabled ?? false }
    var isFlatStereoMode: Bool { vr180Controller?.isFlatStereo ?? false }; var isFlat2D3DMode: Bool { vr180Controller?.isFlat2D3D ?? false }; var filmLooksStereo: Bool { vr180Controller?.filmLooksStereo ?? false }; func osdLine(_ t: String) { vr180Controller?.showOSDLine(t) }; func choose3DProjection() -> String { SingleSwitchRoute.projection(for: vr180Controller?.singleSwitchPlan() ?? .convert2D) }
    // 191b: the store subscription replaces the source-resolution callback.
    var sourceFilmPath:String {let p=vr180Controller?.recognitionPath ?? "";return p.isEmpty ? currentFilePath:p}; var detectedSourceLabel:String {vr180Controller?.detectedStereoKind ?? "2d"}; var sourceSuggestion:String {vr180Controller?.sourceSuggestion ?? "unknown"}
    func applySingleSwitch3D() -> (plan: SingleSwitchRoute.Plan, final: Bool) {if refuseEmbedded("single-switch 3D") {return (.convert2D,false)};return vr180Controller?.applySingleSwitch() ?? (.convert2D, true) }
    var headTrackingEnabled: Bool { vr180Controller?.headTrackingEnabled ?? false }
    private var surfaceToolsEnabled: Bool { headTrackingEnabled || blinkLogEnabled }
    func setVRModeEnabled(_ enabled: Bool) {
        if refuseEmbedded("VR output") {return}
        vr180Controller?.setVRModeEnabled(enabled)
        if !enabled {offReset();redetectCropAfter3DOff();return}
        (NSApp.delegate as? AppDelegate)?.currentAspectPreset = .defaultAR
        stereoManualAspect=nil;stereoGeometryKey="";stereoRestorePending=false;stereoProjectionBaseAspect=nil
        sourceCropPropertyActive=false;requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true);refreshStereoMenuGeometry(force:true);refreshEffectiveGap()
        appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)
    }
    private func offReset() {
        retireSBSFilmFrame()
        (NSApp.delegate as? AppDelegate)?.currentAspectPreset = .defaultAR
        stereoManualAspect=nil;stereoGeometryKey="";stereoRestorePending=false;stereoProjectionBaseAspect=nil
        ipcCommand(#"{"command":["set","video-aspect-override","no"]}"#)
        sourceCropPropertyActive=false;clearOwnedCropFromMenu()
        requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true);clearStereoMenuCrop(refit:false);restoreStereoMenuFrame();refreshStereoMenuGeometry(force:true)
        appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)
    }
    /// Leaving 3D back to plain 2D. offReset() clears the crop through the menu path, which
    /// marks the menu as owning the selection and blocks automatic detection until some
    /// unrelated event (dimension change, playback restart) fired. A mode change is not a
    /// user crop choice: release that ownership and measure again now, with the 2D packing.
    private func redetectCropAfter3DOff() {
        menuCropOwnsSelection=false;manualMenuCropAspect=nil;stereoRestorePending=false
        cropDetector.cancel();cropDetector.resetLastFile()
        startAutomaticCropDetection(needsRedetect:true)
    }
    private var cropPackingNeedsRedetect=false
    private func refreshCropSourcePacking() {
        let packing=vr180Controller?.cropSourcePacking ?? (stereo:false,topBottom:false)
        let viewportOnly=vrModeEnabled || headTrackingEnabled
        guard packing.stereo != cropDetector.stereoSBS || packing.topBottom != cropDetector.stereoTopBottom || viewportOnly != cropDetector.viewportOnly else {return}
        cropDetector.cancel();cropDetector.resetLastFile()
        cropPackingNeedsRedetect=true
        cropDetector.stereoSBS=packing.stereo;cropDetector.stereoTopBottom=packing.topBottom;cropDetector.viewportOnly=viewportOnly
        print("[cropdetect] source packing stereo=\(packing.stereo) tb=\(packing.topBottom) outputVR=\(vrModeEnabled)")
    }
    func setVRModeManually(_ enabled: Bool) {
        if refuseEmbedded("VR output") {return}
        vr180Controller?.noteManualEnabled(enabled)
        if !enabled {offReset();redetectCropAfter3DOff();return}
        stereoManualAspect=nil;stereoGeometryKey="";stereoRestorePending=false;stereoProjectionBaseAspect=nil
        refreshStereoMenuGeometry(force:true);refreshCropSourcePacking()
        refreshEffectiveGap();appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)
    }
    private var applyingThreeDWrapper=false
    func applyThreeDState(_ state:ThreeDState,_ effects:[ThreeDEffect]) {
        if embeddedBackend {
            guard let apply=embeddedThreeDState else {
                nativeStereoRefusal("native entry: opened-source adapter unavailable"); return
            }
            if let reason=apply(state, effects, ThreeDStore.shared.revision) { nativeStereoRefusal(reason) }
            return
        }
        let wasEnabled=vrModeEnabled
        let explicitPresentation=effects.contains(.reapply)
        let targetOff=ThreeDPresentationPlan.make(state:state).output == .off
        applyingThreeDWrapper=true;defer {applyingThreeDWrapper=false}
        // Entering/changing a 3D output resets before the controller flips; leaving 3D must reset AFTER the controller
        // has left VR, otherwise requestRealCrop() takes its vrModeEnabled early return and skips the window refit.
        if explicitPresentation && !targetOff {offReset()}
        vr180Controller?.applyThreeDState(state,effects)
        if targetOff {if wasEnabled || explicitPresentation {offReset();redetectCropAfter3DOff()};return}
        if vrModeEnabled, explicitPresentation || !wasEnabled {
            menuCropOwnsSelection=false;stereoRestorePending=false;cropDetector.resetLastFile()
            startAutomaticCropDetection(needsRedetect:true)
        }
        if wasEnabled != vrModeEnabled {stereoGeometryKey="";refreshStereoMenuGeometry(force:true);appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)}
    }
    func select3DOutput(_ mode:String) {if embeddedBackend {guard let output=ThreeDOutput(rawValue:mode) else {nativeStereoRefusal("native entry: unknown output");return};dispatchNativeStereoIntent(.setOutput(output));return};if refuseEmbedded("3D output "+mode) {return};vr180Controller?.applySourceOutput(mode);if mode=="off" {offReset();redetectCropAfter3DOff();return};clearStereoMenuCrop(refit:false);refreshStereoMenuGeometry(force:true);appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)}
    func selectManualSource(_ value:String) {if embeddedBackend {guard ["vr180","vr180:swap","vr180_tb","vr180_tb:swap"].contains(value) else {nativeStereoRefusal("native entry: source choice unavailable");return};dispatchNativeStereoIntent(.setSource(SourceFormatChoice.source(value)));return};if refuseEmbedded("3D source format") {return};vr180Controller?.applyManualSource(value,enable:false);refreshStereoMenuGeometry(force:true)}
    func selectVRProjection(_ kind: String) {
        if embeddedBackend {
            switch kind {
            case "vr180": dispatchNativeStereoIntent(.setSource(ThreeDSource(.vr180SBS)))
            case "vr180-tb": dispatchNativeStereoIntent(.setSource(ThreeDSource(.vr180TB)))
            case "mono": dispatchNativeStereoIntent(.setOutput(.off))
            default: nativeStereoRefusal("native entry: projection choice unavailable")
            }
            return
        }
        if refuseEmbedded("VR projection "+kind) {return}
        (NSApp.delegate as? AppDelegate)?.currentAspectPreset = .defaultAR
        stereoManualAspect = nil; stereoGeometryKey = ""; stereoRestorePending = false; stereoProjectionBaseAspect = nil
        ipcCommand(#"{"command":["set","video-aspect-override","no"]}"#)
        vr180Controller?.selectProjection(kind)
        refreshStereoMenuGeometry(force:true)
        refreshCropSourcePacking()
        cropDetector.cancel();cropDetector.resetLastFile()
        startAutomaticCropDetection(needsRedetect:true)
        refreshEffectiveGap()
        appliedVideoFrame = .zero; appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds:bounds)
    }
    func toggleHeadTracking()          {if refuseEmbedded("camera head tracking") {return}; _ = vr180Controller?.toggleHeadTracking() }
    var swapEyes: Bool { vr180Controller?.swapEyes ?? false }
    func uiDepthPlacement(eyeWidth:CGFloat,scale:CGFloat) -> (CGFloat,CGFloat) {
        let pixels=Double(eyeWidth*scale),factor=ThreeDSubtitleDepth.dial(vr180Controller?.subtitleDepthPoints ?? 1)
        let p=StereoDepth.placeDepth(disparityPX:-pixels*0.008*factor,
            distanceMM:vr180Controller?.depthDistanceMM,mmPerPX:VRDistance.mmPerPx(),swapEyes:swapEyes)
        return (CGFloat(p.left)/max(1,scale),CGFloat(p.right)/max(1,scale))
    }
    func toggleSwapEyes()              {if refuseEmbedded("stereo eye swap") {return}; _ = vr180Controller?.toggleSwapEyes(); applySubtitleDepthOffset() }
    var blinkLogEnabled: Bool { vr180Controller?.blinkLogEnabled ?? false }
    func toggleBlinkLog()              {if refuseEmbedded("camera blink control") {return};_ = vr180Controller?.toggleBlinkLog() }
    func recenterHeadTracking() {
        // Pose/view reset must not discard verified bars or the accepted film frame.
        vr180Controller?.recenterHeadTracking()
    }
    func adjustBaseIPD(by delta: Double) {if refuseEmbedded("stereo IPD") {return}; vr180Controller?.adjustBaseIPD(by: delta) }
    // MARK: - VR stereo chrome (block 180 3d / 181 2 / v2)
    /// Shared shipped value: parsed once from the same bundled vr180-look.lua
    /// the shader runs (via the app's own vendor resolver), so the Swift
    /// eye-band geometry cannot silently diverge from the shader. The traced
    /// value + source are asserted against the selftest's own parse of the
    /// shipped lua. Bands: left_end = 0.5 - gap*0.25, right_start = 0.5 +
    /// gap*0.25 (vr180-look.lua, PURE_LOOK disabled).
    static let vrPhysicalGap: (value: Double, source: String) = {
        if let text = try? String(contentsOfFile: GORResources.vendorPath("mpv/scripts/vr180-look.lua"), encoding: .utf8),
           let m = text.range(of: #"VR_PHYSICAL_GAP_FRAC\s*=\s*([0-9.]+)"#, options: .regularExpression),
           let eq = text[m].lastIndex(of: "="),
           let v = Double(text[m][text[m].index(after: eq)...].trimmingCharacters(in: .whitespaces)) {
            return (v, "lua")
        }
        return (0.0125, "fallback")
    }()
    /// Per-eye clip mask for the stereo chrome container (VR only).
    private let vrChromeMask = CALayer()
    /// Root overlay clip: both SBS eye bands, or the single 2D film frame.
    private let uiChromeMask = CAShapeLayer()
    // AppKit-owned button/sidebar backing layers cannot be moved into a CAReplicator without breaking
    // AppKit's view ownership. Mirror their actual rendered pixels instead, after their final layout.
    // The right eye is visual only. The original left-eye controls keep all actions and hit testing.
    private let vrControlMirrorRoot = CALayer()
    private let vrControlInput = VRStereoControlInput()
    private var vrControlMirrorLayers: [CALayer] = []
    private var vrControlMirrorShift: CGFloat = 0
    private var vrControlSourceOffset: CGFloat = 0
    private var vrShiftedFrames:[ObjectIdentifier:(CGRect,CGFloat)] = [:]
    private var vrControlMirrorClip: CGRect = .zero
    private var vrControlMirrorOn = false
    private var trackedUIRoll = 0.0; private var trackedUICenter = NSPoint.zero; private var trackedUILeftOffset: CGFloat = 0
    private var trackedUITiltFitScale: CGFloat = 1
    private func setTrackedUITilt(_ roll: Double) {
        guard Thread.isMainThread else {DispatchQueue.main.async { [weak self] in self?.setTrackedUITilt(roll) };return}
        trackedUIRoll=roll.isFinite ? roll:0; applyTrackedUITilt()
    }
    private func updateUIChromeClip(hostLayer: CALayer, rect: CGRect, eyeShift: CGFloat, replicating: Bool) {
        let path = CGMutablePath()
        path.addRect(rect)
        if replicating, eyeShift > 0 { path.addRect(rect.offsetBy(dx: eyeShift, dy: 0)) }
        uiChromeMask.path = path
        uiChromeMask.fillColor = NSColor.black.cgColor
        uiChromeMask.frame = hostLayer.bounds
        hostLayer.mask = uiChromeMask
    }
    // Non-affine/TB/anaglyph preview compatibility only. Normal2D/SBS never enters here.
    private func legacyPreviewRotatedFitScale(rect: CGRect, center: NSPoint, angle: Double, offset: NSPoint, target: CGRect) -> CGFloat {
        let c=CGFloat(cos(angle)),s=CGFloat(sin(angle))
        var scale:CGFloat=1
        for point in [NSPoint(x:rect.minX,y:rect.minY),NSPoint(x:rect.maxX,y:rect.minY),
                      NSPoint(x:rect.maxX,y:rect.maxY),NSPoint(x:rect.minX,y:rect.maxY)] {
            let rx=c*(point.x-center.x)-s*(point.y-center.y)
            let ry=s*(point.x-center.x)+c*(point.y-center.y)
            if abs(rx)>1e-10 {
                let bound=rx>0 ? (target.maxX-center.x-offset.x)/rx : (target.minX-center.x-offset.x)/rx
                scale=min(scale,bound)
            }
            if abs(ry)>1e-10 {
                let bound=ry>0 ? (target.maxY-center.y-offset.y)/ry : (target.minY-center.y-offset.y)/ry
                scale=min(scale,bound)
            }
        }
        return max(0.01,min(1,scale.isFinite ? scale:1))
    }
    private func applyLegacyPreviewUITilt() {
        let shared=subtitleView.trackedOverlayPlacement(in:self)
        let angle=shared?.placement.angle ?? -trackedUIRoll,c=CGFloat(cos(angle)),s=CGFloat(sin(angle))
        let pivot=shared?.center ?? trackedUICenter
        let correction=NSPoint(x:shared.map{CGFloat($0.placement.leftX)-trackedUILeftOffset} ?? 0,
                               y:shared.map{CGFloat($0.placement.leftY)} ?? 0)
        let replica=NSPoint(x:shared.map{CGFloat($0.placement.replicaX)} ?? vrControlMirrorShift,
                            y:shared.map{CGFloat($0.placement.replicaY)} ?? 0)
        let fitScale:CGFloat
        if abs(angle)>1e-10 {
            var scale=legacyPreviewRotatedFitScale(rect:controlChromeBounds,center:NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y),
                                      angle:angle,offset:correction,target:controlChromeBounds)
            for source in vrControlInput.sources {
                let rect=source.convert(source.bounds,to:self)
                scale=min(scale,legacyPreviewRotatedFitScale(rect:rect,center:NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y),
                                                angle:angle,offset:correction,target:controlChromeBounds))
            }
            let rightCenter=NSPoint(x:pivot.x+trackedUILeftOffset+replica.x,y:pivot.y+replica.y)
            let rightTarget=controlChromeBounds.offsetBy(dx:replica.x,dy:replica.y)
            for mirror in vrControlMirrorLayers where vrControlMirrorOn {
                let rect=mirror.frame.offsetBy(dx:vrControlMirrorClip.minX,dy:vrControlMirrorClip.minY)
                scale=min(scale,legacyPreviewRotatedFitScale(rect:rect,center:rightCenter,angle:angle,offset:correction,target:rightTarget))
            }
            fitScale=scale
        } else {
            fitScale=1
        }
        trackedUITiltFitScale=fitScale
        func transform(at point:NSPoint,center:NSPoint)->CGAffineTransform {
            let x=point.x-center.x,y=point.y-center.y
            return CGAffineTransform(a:c*fitScale,b:s*fitScale,c:-s*fitScale,d:c*fitScale,
                                     tx:fitScale*(c*x-s*y)-x+correction.x,ty:fitScale*(s*x+c*y)-y+correction.y)
        }
        CATransaction.begin();CATransaction.setDisableActions(true)
        for source in vrControlInput.sources {
            source.wantsLayer=true; guard let l=source.layer else {continue}
            let anchor=NSPoint(x:source.bounds.minX+l.anchorPoint.x*source.bounds.width,y:source.bounds.minY+l.anchorPoint.y*source.bounds.height)
            l.setAffineTransform(transform(at:source.convert(anchor,to:self),center:NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y)))
        }
        for mirror in vrControlMirrorLayers {
            let p=NSPoint(x:mirror.position.x+vrControlMirrorClip.minX,y:mirror.position.y+vrControlMirrorClip.minY)
            let center=NSPoint(x:pivot.x+trackedUILeftOffset+vrControlMirrorShift,y:pivot.y)
            var t=transform(at:p,center:center)
            t.tx += replica.x-vrControlMirrorShift;t.ty += replica.y
            mirror.setAffineTransform(t)
        }
        var chrome=CATransform3DMakeRotation(CGFloat(angle),0,0,1)
        chrome.m11*=fitScale;chrome.m12*=fitScale;chrome.m21*=fitScale;chrome.m22*=fitScale
        chrome.m41=pivot.x-fitScale*(c*pivot.x-s*pivot.y)+trackedUILeftOffset+correction.x
        chrome.m42=pivot.y-fitScale*(s*pivot.x+c*pivot.y)+correction.y
        vrChromeContainer.sublayerTransform=chrome
        vrChromeReplicator.instanceTransform=CATransform3DMakeTranslation(replica.x,replica.y,0)
        vrChromeContainer.mask=(abs(angle)>1e-10 || vrControlMirrorOn) ? vrChromeMask:nil
        vrControlMirrorRoot.masksToBounds=vrControlMirrorOn
        spineUI.setTrackedUITilt(angle,center:spineUI.convert(pivot,from:self),translation:correction,replica:replica,fitScale:fitScale)
        vrControlInput.eyeShift=replica.x;vrControlInput.eyeShiftY=replica.y;vrControlInput.tiltTranslation=correction
        vrControlInput.roll=angle;vrControlInput.tiltCenter=NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y);vrControlInput.tiltScale=fitScale
        vrControlInput.stereo=vrControlMirrorOn; vrControlInput.active=vrControlMirrorOn || abs(angle)>1e-10
        CATransaction.commit()
    }
    private var filmBandMasks:[ObjectIdentifier:(CALayer,CALayer?,CAShapeLayer)]=[:]
    private func restoreFilmBandMasks() {
        for (_,entry) in filmBandMasks {entry.0.mask=entry.1}
        filmBandMasks.removeAll()
    }
    private func clipFilmLayer(_ layer:CALayer,anchor:NSPoint,localAnchor:NSPoint,transform:CGAffineTransform,clip:CGRect) {
        let key=ObjectIdentifier(layer)
        let entry=filmBandMasks[key] ?? (layer,layer.mask,CAShapeLayer())
        let mask=entry.2,path=CGMutablePath(),t=transform
        let det=t.a*t.d-t.b*t.c
        guard abs(det)>1e-12 else{return}
        for (index,p) in [NSPoint(x:clip.minX,y:clip.minY),NSPoint(x:clip.maxX,y:clip.minY),NSPoint(x:clip.maxX,y:clip.maxY),NSPoint(x:clip.minX,y:clip.maxY)].enumerated() {
            let x=p.x-anchor.x-t.tx,y=p.y-anchor.y-t.ty
            let q=NSPoint(x:localAnchor.x+(t.d*x-t.c*y)/det,y:localAnchor.y+(-t.b*x+t.a*y)/det)
            if index==0 {path.move(to:q)} else {path.addLine(to:q)}
        }
        path.closeSubpath();mask.path=path;mask.fillColor=NSColor.black.cgColor
        mask.frame=layer.bounds;mask.mask=entry.1;layer.mask=mask;filmBandMasks[key]=entry
    }
    private var committedFilmFrame:[String:Double]?
    private var filmFrameSequenceFloor:[String:Double]=[:]
    private var filmFramePath="",pendingFilmFrame:[String:[String:Any]]=[:]
    private var filmIdentityQuery=9_194_000,filmIdentityPending=false
    private var filmIdentityAt=Date.distantPast,filmFirstReceiptAt=Date.distantPast
    private func beginFilmIdentity() {
        filmIdentityPending=true;clearCommittedFilmFrame();pendingFilmFrame.removeAll()
        filmFirstReceiptAt = .distantPast;applyTrackedUITilt()
        requestFilmIdentity()
    }
    private func requestFilmIdentity() {
        filmIdentityQuery+=1;if filmIdentityQuery>=9_195_000 {filmIdentityQuery=9_194_001}
        if let bytes=try? JSONSerialization.data(withJSONObject:["command":["get_property","path"],"request_id":filmIdentityQuery]),let text=String(data:bytes,encoding:.utf8) {persistentConnection.write(text)}
    }
    private func acceptFilmIdentityReply(_ id:Int,_ data:Any?) {
        guard id==filmIdentityQuery,let path=data as? String,!path.isEmpty else{return}
        setFilmFrameIdentity(path)
    }
    private func setFilmFrameIdentity(_ path:String) {
        guard !path.isEmpty else{return}
        let changed=filmFramePath != path || filmIdentityPending
        guard changed else{return}
        let pending=pendingFilmFrame[path]
        filmFramePath=path;filmIdentityPending=false;filmIdentityAt=Date()
        clearCommittedFilmFrame();pendingFilmFrame.removeAll()
        traceFilmUI("identity:current",receiptPath:path)
        if let pending {noteFilmFrame(pending)}
        // Read/replay the already accepted Lua receipt, never change its geometry.
        persistentConnection.write(#"{"command":["script-message-to","vr180_look","vr180-look-republish-film-frame"]}"#)
        // mpv can suppress an unchanged user-data observation; explicitly read the accepted value.
        persistentConnection.write(#"{"command":["get_property","user-data/vr180-look/film-frame"],"request_id":9195001}"#)
    }
    private func clearCommittedFilmFrame() {
        let hadFrame=committedFilmFrame != nil;committedFilmFrame=nil
        if hadFrame {appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)}
        applyTrackedUITilt()
    }
    private func retireSBSFilmFrame() {
        if committedFilmFrame?["layout"]==3 {clearCommittedFilmFrame()}
        pendingFilmFrame=pendingFilmFrame.filter {($0.value["layout"] as? NSNumber)?.doubleValue != 3}
        traceFilmUI("mode-exit:retired-sbs")
    }
    private func noteFilmFrame(_ data:Any?) {
        if filmFirstReceiptAt == .distantPast {filmFirstReceiptAt=Date()}
        guard let value=data as? [String:Any],let path=value["path"] as? String,!path.isEmpty else {
            clearCommittedFilmFrame();traceFilmUI("FILM-FRAME-REJECT missing=path");return
        }
        if path != filmFramePath || filmIdentityPending {
            let sequence=(value["sequence"] as? NSNumber)?.doubleValue ?? -1
            let previous=(pendingFilmFrame[path]?["sequence"] as? NSNumber)?.doubleValue ?? -2
            if sequence>=previous {pendingFilmFrame[path]=value}
            if pendingFilmFrame.count>4 {pendingFilmFrame=pendingFilmFrame.filter {$0.key==path}}
            traceFilmUI("pending:path",receiptPath:path);return
        }
        var fields:[String:Double]=[:]
        for key in ["sequence","scale","angle","leftX","leftY","replicaX","replicaY","width","height","frameW","frameH","baseX","baseY","layout","instances","clipX","clipY","clipW","clipH"] {
            guard let number=value[key] as? NSNumber,number.doubleValue.isFinite else {
                clearCommittedFilmFrame();traceFilmUI("FILM-FRAME-REJECT missing="+key,receiptPath:path);return
            }
            fields[key]=number.doubleValue
        }
        guard fields["scale"]!>0,fields["width"]!>0,fields["height"]!>0 else {
            clearCommittedFilmFrame();traceFilmUI("FILM-FRAME-REJECT missing=positive-geometry",receiptPath:path);return
        }
        if let previous=filmFrameSequenceFloor[path],fields["sequence"]!<previous {
            traceFilmUI("FILM-FRAME-REJECT stale-sequence",receiptPath:path);return
        }
        if fields["layout"]==3,(!vrModeEnabled || vr180Controller?.expectsSBSFilmFrame != true) {
            traceFilmUI("FILM-FRAME-REJECT retired-sbs-mode",receiptPath:path);return
        }
        let geometryChanged=committedFilmFrame?["frameW"] != fields["frameW"] || committedFilmFrame?["frameH"] != fields["frameH"] || committedFilmFrame?["baseX"] != fields["baseX"] || committedFilmFrame?["baseY"] != fields["baseY"] || committedFilmFrame?["layout"] != fields["layout"]
        filmFrameSequenceFloor[path]=fields["sequence"]!
        if filmFrameSequenceFloor.count>64 {filmFrameSequenceFloor=filmFrameSequenceFloor.filter {$0.key==path}}
        committedFilmFrame=fields
        if geometryChanged {appliedVideoFrame = .zero;applyVideoFrame(bounds:bounds)}
        applyTrackedUITilt();traceFilmUI("committed:receipt",receiptPath:path)
    }
    private func applyTrackedUITilt() {
        if vr180Controller?.usesLegacyPreviewChrome == true {subtitleView.setCommittedFilmFrame(committedFilmFrame,origin:subtitleView.frame.origin,output:bounds.size);restoreFilmBandMasks();vrControlInput.fixedEyeBand=nil;spineUI.setTrackedUIOutputClip(nil);applyLegacyPreviewUITilt();return}
        // The film publisher is the only flat pose/fit authority. No ink-safety pivot
        // or independent UI fitting may alter the film-relative control geometry.
        let frame=committedFilmFrame
        subtitleView.setCommittedFilmFrame(frame,origin:subtitleView.frame.origin,output:bounds.size)
        let angle=frame?["angle"] ?? 0,c=CGFloat(cos(angle)),s=CGFloat(sin(angle))
        let pivot=NSPoint(x:controlChromeBounds.midX-trackedUILeftOffset,y:controlChromeBounds.midY)
        let fitScale=CGFloat(frame?["scale"] ?? 1)
        let w=bounds.width,h=bounds.height
        let topBottom=frame?["layout"] == 1
        let band=frame.map {CGRect(x:CGFloat($0["clipX"]!)*w,y:(1-CGFloat($0["clipY"]!)-CGFloat($0["clipH"]!))*h,
                                  width:CGFloat($0["clipW"]!)*w,height:CGFloat($0["clipH"]!)*h)} ?? .zero
        if !topBottom {restoreFilmBandMasks()}
        let correction=frame.map {NSPoint(x:CGFloat($0["leftX"]!)*w-controlChromeBounds.midX,
                                           y:(1-CGFloat($0["leftY"]!))*h-controlChromeBounds.midY)} ?? .zero
        let replica=frame.map {NSPoint(x:CGFloat($0["replicaX"]!)*w,y:-CGFloat($0["replicaY"]!)*h)} ?? NSPoint(x:vrControlMirrorShift,y:0)
        trackedUITiltFitScale=fitScale
        func transform(at point:NSPoint,center:NSPoint)->CGAffineTransform {
            let x=point.x-center.x,y=point.y-center.y
            return CGAffineTransform(a:c*fitScale,b:s*fitScale,c:-s*fitScale,d:c*fitScale,
                                     tx:fitScale*(c*x-s*y)-x+correction.x,ty:fitScale*(s*x+c*y)-y+correction.y)
        }
        CATransaction.begin();CATransaction.setDisableActions(true)
        for source in vrControlInput.sources {
            source.wantsLayer=true; guard let l=source.layer else {continue}
            let anchor=NSPoint(x:source.bounds.minX+l.anchorPoint.x*source.bounds.width,y:source.bounds.minY+l.anchorPoint.y*source.bounds.height)
            let globalAnchor=source.convert(anchor,to:self)
            let t=transform(at:globalAnchor,center:NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y))
            l.setAffineTransform(t)
            if topBottom {clipFilmLayer(l,anchor:globalAnchor,localAnchor:anchor,transform:t,clip:band)}
        }
        for mirror in vrControlMirrorLayers {
            let p=NSPoint(x:mirror.position.x+vrControlMirrorClip.minX,y:mirror.position.y+vrControlMirrorClip.minY)
            let center=NSPoint(x:pivot.x+trackedUILeftOffset+vrControlMirrorShift,y:pivot.y)
            var t=transform(at:p,center:center)
            t.tx += replica.x-vrControlMirrorShift;t.ty += replica.y
            mirror.setAffineTransform(t)
            if topBottom {
                let local=NSPoint(x:mirror.bounds.midX,y:mirror.bounds.midY)
                clipFilmLayer(mirror,anchor:p,localAnchor:local,transform:t,clip:band.offsetBy(dx:replica.x,dy:replica.y))
            }
        }
        var chrome=CATransform3DMakeRotation(CGFloat(angle),0,0,1)
        chrome.m11*=fitScale;chrome.m12*=fitScale;chrome.m21*=fitScale;chrome.m22*=fitScale
        chrome.m41=pivot.x-fitScale*(c*pivot.x-s*pivot.y)+trackedUILeftOffset+correction.x
        chrome.m42=pivot.y-fitScale*(s*pivot.x+c*pivot.y)+correction.y
        vrChromeContainer.sublayerTransform=chrome
        vrChromeReplicator.instanceTransform=CATransform3DMakeTranslation(replica.x,replica.y,0)
        if topBottom {vrChromeMask.frame=band;vrChromeContainer.mask=vrChromeMask}
        else {vrChromeContainer.mask=frame == nil && vrControlMirrorOn ? vrChromeMask:nil}
        vrControlMirrorRoot.masksToBounds=frame == nil && vrControlMirrorOn
        if frame != nil {layer?.mask=nil}
        spineUI.setTrackedUITilt(angle,center:spineUI.convert(pivot,from:self),translation:correction,replica:replica,fitScale:fitScale,clipToBounds:frame == nil)
        spineUI.setTrackedUIOutputClip(topBottom ? spineUI.convert(band,from:self):nil)
        vrControlInput.fixedEyeBand=topBottom ? band:nil
        vrControlInput.eyeShift=replica.x;vrControlInput.eyeShiftY=replica.y;vrControlInput.tiltTranslation=correction
        vrControlInput.roll=angle;vrControlInput.tiltCenter=NSPoint(x:pivot.x+trackedUILeftOffset,y:pivot.y);vrControlInput.tiltScale=fitScale
        vrControlInput.stereo=vrControlMirrorOn; vrControlInput.active=vrControlMirrorOn || frame != nil
        CATransaction.commit()
        traceFilmUI(frame == nil ? (missingFlatFilmBounds(in:bounds) == nil ? "consumer:no-frame":"fallback:current-flat-film-rail-placement-only"):"consumer:applied")
    }
    private static func flatSourceGeometry(_ values:[String:Any])->(w:Double,h:Double,par:Double,basis:String) {
        func positive(_ v:Double)->Bool {v.isFinite && v>0}
        for (domain,coded) in [("video-dec-params/",true),("video-dec-params/d",false),("video-params/d",false)] {
            let w=values[domain+"w"] as? Double ?? 0,h=values[domain+"h"] as? Double ?? 0
            guard positive(w),positive(h) else{continue}
            let raw=values["video-dec-params/par"] as? Double ?? 1
            let par=coded && positive(raw) ? raw:1
            guard positive(w*par/h) else{continue}
            return (w,h,par,domain+(coded ? "coded-par":"display"))
        }
        return (0,0,1,"pending-current-paired-geometry")
    }
    private var filmGeometryBasis="unchanged"
    private func missingFlatFilmBounds(in bounds:CGRect)->CGRect? {
        guard committedFilmFrame == nil,vrModeEnabled,let vr=vr180Controller,
              vr.presentsFlatSBSGeometry,!vr.usesLegacyPreviewChrome,vr.recognitionPath==currentFilePath,
              cropRect==nil,manualMenuCropAspect==nil,stereoManualAspect==nil,stereoMenuCropAspect==nil,
              vr.latestWidth>0,vr.latestHeight>0,let gap=effectiveVrGap?.value else{return nil}
        let aspect=vr.knownEyeAspect(kind:"flat-2d3d",filename:currentFilePath,width:vr.latestWidth,height:vr.latestHeight)
        guard aspect.isFinite,aspect>0 else{return nil}
        let bw=bounds.width*CGFloat(0.5-gap*0.25),bh=bounds.height
        guard bw>0,bh>0 else{return nil}
        let w=min(bw,bh*CGFloat(aspect)),h=min(bh,bw/CGFloat(aspect))
        return CGRect(x:bounds.minX+(bw-w)/2,y:bounds.minY+(bh-h)/2,width:w,height:h)
    }
    private var filmUITraceAt=Date.distantPast,filmUITraceKey=""
    private func traceFilmUI(_ reason:String,receiptPath:String?=nil) {
        let key=currentFilePath+"|"+reason
        let now=Date();guard key != filmUITraceKey || now.timeIntervalSince(filmUITraceAt)>=1 else{return}
        filmUITraceKey=key;filmUITraceAt=now
        let t=vrChromeContainer.sublayerTransform,r=controlChromeBounds
        let value:[String:Any]=["reason":reason,"path":currentFilePath,"receiptPath":receiptPath ?? "",
            "identityPath":filmFramePath,"identityAt":filmIdentityAt.timeIntervalSince1970,"firstReceiptAt":filmFirstReceiptAt.timeIntervalSince1970,"geometryBasis":filmGeometryBasis,"frame":committedFilmFrame ?? [:],"eyeAspect":vr180Controller?.flatUIEyeAspect ?? 0,
            "vr":vrModeEnabled,"window":[bounds.width,bounds.height],"display":[videoDisplayW,videoDisplayH],
            "chrome":[r.minX,r.minY,r.width,r.height],"finalTransform":[t.m11,t.m12,t.m21,t.m22,t.m41,t.m42]]
        if let data=try? JSONSerialization.data(withJSONObject:value,options:.sortedKeys),let text=String(data:data,encoding:.utf8) {Diag.log("3D-FILM-UI "+text)}
    }
    private var vrControlPixelEvidenceSaved = false
    private var vrControlMirrorRefreshing = false
    private var vrMirrorThrottle = VRMirrorThrottle()
    private var presentationIsQuitting = false
    func suspendPresentationForQuit() {
        guard !presentationIsQuitting else { return }
        presentationIsQuitting = true
        ipcClient.closeLatestPose()
        cancelCropDetection() // terminal detection stop, including queued freshness followthrough
        cursorTimer?.invalidate(); cursorTimer = nil
        testScrollHarnessGeneration &+= 1
        vrControlInput.active = false
    }
    // Timer-only idempotence. Direct layout/pose/mode calls still use the original
    // refresh path without a gate. Stereo pixel mirroring and legacy chrome must
    // continue refreshing even when geometry is unchanged.
    private struct FlatControlTimerStamp: Equatable {
        var film: [String: Double]
        var geometry: [CGFloat]
        var objects: [ObjectIdentifier?]
        var flags: [Bool]
    }
    private var flatControlTimerGate = FlatControlRefreshGate<FlatControlTimerStamp>()
    private func flatControlTimerStamp() -> FlatControlTimerStamp {
        let panels = subviews.filter {
            $0 !== spineUI && $0 !== sidebarUI && $0 !== subtitleView && $0 !== vrControlInput && !$0.isHidden
        }
        let sources = spineUI.vrControlViews + [sidebarUI] + panels
        var stamp = FlatControlTimerStamp(film: committedFilmFrame ?? [:],
            geometry: [trackedUILeftOffset, vrControlMirrorShift, vrControlSourceOffset,
                       window?.backingScaleFactor ?? 1], objects: [],
            flags: [committedFilmFrame != nil, vrControlMirrorRoot.isHidden,
                    vrControlInput.superview === self, vrControlInput.active])
        func rect(_ r: CGRect) { stamp.geometry += [r.minX, r.minY, r.width, r.height] }
        func layerState(_ l: CALayer?) {
            stamp.objects += [l.map { ObjectIdentifier($0) }, l?.mask.map { ObjectIdentifier($0) }]
            guard let l else { return }
            rect(l.bounds)
            stamp.geometry += [l.position.x, l.position.y, l.anchorPoint.x, l.anchorPoint.y]
            let t = l.transform, u = l.sublayerTransform
            stamp.geometry += [t.m11,t.m12,t.m13,t.m14,t.m21,t.m22,t.m23,t.m24,
                               t.m31,t.m32,t.m33,t.m34,t.m41,t.m42,t.m43,t.m44,
                               u.m11,u.m12,u.m13,u.m14,u.m21,u.m22,u.m23,u.m24,
                               u.m31,u.m32,u.m33,u.m34,u.m41,u.m42,u.m43,u.m44]
        }
        rect(bounds); rect(controlChromeBounds); rect(vrControlMirrorClip)
        rect(subtitleView.frame); rect(subtitleView.bounds); rect(spineUI.frame)
        layerState(layer); layerState(vrChromeContainer); layerState(vrChromeReplicator)
        layerState(vrControlMirrorRoot); layerState(subtitleView.layer)
        stamp.objects += [ObjectIdentifier(spineUI), ObjectIdentifier(subtitleView)]
        for source in sources {
            stamp.objects.append(ObjectIdentifier(source))
            rect(source.frame); rect(source.bounds); rect(source.convert(source.bounds, to: self))
            stamp.flags.append(source.isHidden)
            layerState(source.layer)
            if let previous = vrShiftedFrames[ObjectIdentifier(source)] {
                rect(previous.0); stamp.geometry.append(previous.1)
            }
        }
        return stamp
    }
    private var vrMirrorThermalSkip: UInt = 0
    private func refreshVRControlMirrorsFromTimer() {
        guard Thread.isMainThread, !presentationIsQuitting, !vrControlMirrorRefreshing else { return }
        guard !vrControlMirrorOn, (committedFilmFrame?["layout"] ?? 0) == 0,
              vr180Controller?.usesLegacyPreviewChrome != true else {
            flatControlTimerGate.invalidate()
            // Owner 2026-11-15 (95 C report): under thermal pressure an idle mirror pass runs every 4th cursor
            // tick (2.5 Hz) - the per-tick stamp walk over every panel's layer tree is the sustained cost.
            // Interaction (hover/drag, held 1.5 s by VRMirrorThrottle.interactiveUntil) keeps the full 10 Hz,
            // and a cool machine never divides.
            if HeatTelemetry.thermalPressure, ProcessInfo.processInfo.systemUptime >= vrMirrorThrottle.interactiveUntil {
                vrMirrorThermalSkip &+= 1
                if vrMirrorThermalSkip % 4 != 0 { return }
            } else { vrMirrorThermalSkip = 0 }
            refreshVRControlMirrors()
            return
        }
        let before = flatControlTimerStamp()
        guard flatControlTimerGate.needsRefresh(before) else { return }
        refreshVRControlMirrors()
        // Capture after layout writes; recording the pre-write state would force
        // a redundant transaction on the next tick. A transition always runs once.
        flatControlTimerGate.recordApplied(flatControlTimerStamp())
    }
    private func refreshVRControlMirrors() {
        guard Thread.isMainThread, !presentationIsQuitting, !vrControlMirrorRefreshing else { return }
        vrControlMirrorRefreshing = true
        defer { vrControlMirrorRefreshing = false;applyTrackedUITilt() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Every in-player panel (browsers, menus, music/IPTV, transient overlays) shares the live
        // mirrored input route. Exclude the already-replicated subtitle canvas and core chrome owners.
        let panels = subviews.filter {
            $0 !== spineUI && $0 !== sidebarUI && $0 !== subtitleView && $0 !== vrControlInput && !$0.isHidden
        }
        let sources = spineUI.vrControlViews + [sidebarUI] + panels
        vrControlInput.host = self
        vrControlInput.onInteraction = { [weak self] in self?.vrMirrorThrottle.noteInteraction(now: ProcessInfo.processInfo.systemUptime); self?.claimFocusForClick(); self?.wakeUI() }
        for source in sources {
            let key=ObjectIdentifier(source), target=vrControlMirrorOn ? vrControlSourceOffset : 0
            let previous=vrShiftedFrames[key]
            let priorOffset=(previous?.0 == source.frame) ? (previous?.1 ?? 0) : 0
            if abs(target-priorOffset)>1e-10 {source.frame.origin.x += target-priorOffset}
            vrShiftedFrames[key]=(source.frame,target)
        }
        vrControlInput.sources = sources
        vrControlInput.eyeShift = vrControlMirrorShift; vrControlInput.eyeClip = vrControlMirrorClip
        vrControlInput.active = vrControlMirrorOn
        vrControlInput.frame = bounds
        if vrControlInput.superview !== self { addSubview(vrControlInput, positioned: .above, relativeTo: nil) }
        vrControlMirrorRoot.isHidden = !vrControlMirrorOn
        guard vrControlMirrorOn, let host = layer else {
            vrControlPixelEvidenceSaved = false
            CATransaction.commit()
            return
        }
        vrControlMirrorRoot.frame = vrControlMirrorClip
        vrControlMirrorRoot.masksToBounds = true
        while vrControlMirrorLayers.count < sources.count {
            let mirror = CALayer(); vrControlMirrorRoot.addSublayer(mirror); vrControlMirrorLayers.append(mirror)
        }
        for mirror in vrControlMirrorLayers {mirror.isHidden=true} // Never publish an untilted staging transform.
        var rendered = 0
        for (index, source) in sources.enumerated() {
            let mirror = vrControlMirrorLayers[index]
            var ancestor: NSView? = source
            var visible = true
            var alpha: CGFloat = 1
            while let view = ancestor, view !== self {
                visible = visible && !view.isHidden
                alpha *= view.alphaValue
                ancestor = view.superview
            }
            let sourceRect = source.convert(source.bounds, to: self)
            let placed = sourceRect.offsetBy(dx: vrControlMirrorShift - vrControlMirrorClip.minX, dy: -vrControlMirrorClip.minY)
            if visible, alpha > 0.01, sourceRect.width > 0, sourceRect.height > 0, mirror.contents != nil,
               !vrMirrorThrottle.shouldRender(slot: index, id: ObjectIdentifier(source), stamp: VRMirrorStamp.of(source),
                                              hasContents: true, now: ProcessInfo.processInfo.systemUptime) {
                mirror.bounds=CGRect(origin:.zero,size:placed.size);mirror.position=NSPoint(x:placed.midX,y:placed.midY); mirror.opacity = Float(alpha); mirror.isHidden = false; rendered += 1; continue // unchanged: keep pixels
            }
            guard visible, alpha > 0.01, sourceRect.width > 0, sourceRect.height > 0,
                  let rep = source.bitmapImageRepForCachingDisplay(in: source.bounds) else {
                mirror.isHidden = true
                continue
            }
            source.cacheDisplay(in: source.bounds, to: rep)
            guard let image = rep.cgImage else { mirror.isHidden = true; continue }
            mirror.contents = image
            mirror.contentsScale = window?.backingScaleFactor ?? 2; mirror.contentsGravity = .resize
            mirror.bounds=CGRect(origin:.zero,size:placed.size);mirror.position=NSPoint(x:placed.midX,y:placed.midY); mirror.opacity = Float(alpha); mirror.isHidden = false; rendered += 1
        }
        // Keep above the video and ordinary AppKit overlays, without stealing input.
        if vrControlMirrorRoot.superlayer !== host { host.addSublayer(vrControlMirrorRoot) }
        vrControlMirrorRoot.zPosition = 10_001
        applyTrackedUITilt() // Publish the final transform inside the same transaction as pixel/frame changes.
        CATransaction.commit()
        CATransaction.flush() // Diagnostic reads only the committed rigid placement.
        if GeomTrace.on, rendered > 0, !vrControlPixelEvidenceSaved,
           let evidence = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: evidence)
            if let png = evidence.representation(using: .png, properties: [:]) {
                let path = NSTemporaryDirectory() + "gor-vr-controls-\(ProcessInfo.processInfo.processIdentifier).png"
                if (try? png.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                    vrControlPixelEvidenceSaved = true
                    GeomTrace.log("vrControlImage", String(format: #"{"k":"vrControlImage","path":"%@","w":%d,"h":%d,"verified":false}"#,
                        path, evidence.pixelsWide, evidence.pixelsHigh))
                }
            }
        }
        GeomTrace.logChanged("vrControlPixels", String(format: #"{"k":"vrControlPixels","sources":%d,"rendered":%d,"right":[%.1f,%.1f,%.1f,%.1f]}"#,
            sources.count, rendered, vrControlMirrorClip.minX, vrControlMirrorClip.minY,
            vrControlMirrorClip.width, vrControlMirrorClip.height))
    }
    /// The shader's live published gap (user-data/vr180-look/physical-gap-frac,
    /// written by vr180-look.lua on init/enable/shader-write as a %.6f string;
    /// 0 means pure-look mode - no replicable band mapping).
    private var liveGapFrac: Double?
    /// The publication arrives as a decimal STRING (lua %.6f); accept a number
    /// too for the test drive path.
    static func parseGapPublication(_ data: Any?) -> Double? {
        if let d = data as? Double { return d }
        if let s = data as? String { return Double(s) }
        return nil
    }
    /// Effective gap: the shader's live value when published and positive;
    /// a live 0 (pure-look) or a missing value falls through to the bundled
    /// lua parse ONLY when no publication exists at all; no publication and
    /// no parse = nil (no replication without a sourced value).
    var effectiveVrGap: (value: Double, source: String)? {
        if let v = liveGapFrac { return v > 0 ? (v, "live") : nil }
        if Self.vrPhysicalGap.source == "lua" { return Self.vrPhysicalGap }
        return nil
    }
    /// Trace label for the gap source: live / pure (live 0) / lua / none.
    var vrGapSourceLabel: String {
        if let v = liveGapFrac { return v > 0 ? "live" : "pure" }
        if Self.vrPhysicalGap.source == "lua" { return "lua" }
        return "none"
    }
    /// Live gap publication from vr180-look.lua (init + every tune): the one
    /// effective value. Mid-session tuning refreshes the chrome through the
    /// same geometry path - no stale replicas.
    func noteVrGapPublication(_ data: Any?) {
        let v = Self.parseGapPublication(data)
        guard v != liveGapFrac else { return }
        liveGapFrac = v
        refreshStereoMenuGeometry(force:true)
        guard vrModeEnabled else { return }
        appliedVideoFrame = .zero
        appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds: bounds)
    }
    /// Re-read the shader's live gap publication on VR entry (the observed
    /// property feed keeps it live after that).
    func refreshEffectiveGap() {
        liveGapFrac = nil
        let lines = ipcClient.queryBatch(
            #"{"command":["get_property","user-data/vr180-look/physical-gap-frac"]}"#, timeout: 0.3)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["error"] as? String == "success" else { continue }
            if let v = Self.parseGapPublication(reply["data"]) { liveGapFrac = v }
        }
    }
    /// Replicator + container hosting chrome whose frames are in this view's
    /// coordinates (photon HUD rows, mpv OSD lines, HUD scroll indicator).
    /// In VR instance 1 is the right-eye copy (visual only; replicator
    /// replicas are never hit-testable, so hit-testing stays on instance 0).
    /// Outside VR instanceCount is 1 - no behavior change.
    private let vrChromeReplicator = CAReplicatorLayer()
    let vrChromeContainer = CALayer()
    func adjustSubtitleDepth(by delta: Double) {
        if refuseEmbedded("subtitle depth") {return}
        vr180Controller?.adjustSubtitleDepth(by: delta)
        applySubtitleDepthOffset()
    }
    /// Trace the depth factor and force a geometry pass. StereoDepth applies the physical-pixel
    /// default, eye order and comfort clamp at placement time.
    func applySubtitleDepthOffset() {
        let dial = ThreeDSubtitleDepth.dial(vr180Controller?.subtitleDepthPoints ?? 0)
        let signedOffset = dial * (swapEyes ? -1 : 1)
        let had = vr180Controller?.hasSubtitleDepthPref ?? false
        GeomTrace.logChanged("vrSubDepth", String(format: #"{"k":"vrSubDepth","dial":%.1f,"offset":%.1f,"swap":%d,"had":%d}"#,
            dial, signedOffset, swapEyes ? 1 : 0, had ? 1 : 0))
        appliedVideoFrame = .zero
        appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds: bounds)
    }
    var cropRect: CGRect? = nil
    private static let fullSourceCrop=CGRect(x:0,y:0,width:1,height:1)
    private var cropMotionTimer:Timer?
    private var cropMotionGeneration:UInt64=0
    private var cropMotionActive=false
    private var cropGeometryOwnedUntil:Double=0
    var cropGeometryTransitionActive:Bool {cropMotionActive || ProcessInfo.processInfo.systemUptime<cropGeometryOwnedUntil}
    private var cropMotionPlanning=false
    private var cropMotionWindowTarget:NSRect?
    private var cropMotionTargetRect:CGRect?
    private var cropPresentationRect=CGRect(x:0,y:0,width:1,height:1)
    private var visualCropRect:CGRect? {cropMotionActive ? cropPresentationRect:cropRect}
    private var cropLastCommandValue:String?
    private var cropLayoutReadback:(tag:String,intent:UInt64,command:String)?
    private var cropPropertyLayout:(session:String,path:String,opening:UInt64,tag:String?,crop:String,aspect:Double)?
    // Property geometry, not decoder-frame presentation or target success.
    private var currentOpeningPropertyAspect:Double? {
        guard let layout=cropPropertyLayout,layout.session==cropBoundLaunchSession,
              layout.path==currentFilePath,layout.opening==cropSourceOpening else{return nil}
        return layout.aspect
    }
    private static func canonicalSourceCrop(_ value:String)->[Int]? {
        let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
        if trimmed.isEmpty {return []}
        let pattern="^[0-9]+x[0-9]+[+][0-9]+[+][0-9]+$"
        guard trimmed.range(of:pattern,options:.regularExpression) != nil else{return nil}
        let parts=trimmed.split(whereSeparator:{$0=="x" || $0=="+"})
        let n=parts.compactMap{Int($0)}
        guard n.count==4,n[0]>0,n[1]>0,n[2]>=0,n[3]>=0 else{return nil}
        return n
    }
    private var cropPropertyMatchesCommand:Bool? {
        guard currentOpeningPropertyAspect != nil,let layout=cropPropertyLayout,
              let readback=cropLayoutReadback,readback.intent==cropPacketIntentGen,
              layout.tag==readback.tag,let actual=Self.canonicalSourceCrop(layout.crop),
              let expected=Self.canonicalSourceCrop(readback.command) else{return nil}
        return actual==expected
    }
    private func noteCropPropertyLayout(_ results:[String:Any],tag:String?)->Bool {
        guard usesCropCommandReceipts,!mediaTransitionPending,
              results["path"] as? String==currentFilePath,!currentFilePath.isEmpty,
              let crop=results["video-crop"] as? String,
              let w=results["dwidth"] as? Double,let h=results["dheight"] as? Double,
              w.isFinite,h.isFinite,w>0,h>0 else{return false}
        let previous=currentOpeningPropertyAspect
        cropPropertyLayout=(cropBoundLaunchSession,currentFilePath,cropSourceOpening,tag,crop,w/h)
        return previous != currentOpeningPropertyAspect
    }
    private var cropMenuOwnsPresentation:Bool {menuCropOwnsSelection && (!cropMotionActive || manualMenuCropAspect != nil || stereoMenuCropAspect != nil)}
    var nativePresentedCropAspect:Double? {
        if usesCropCommandReceipts {
            // Observed source layout follows current-opening property geometry even on target mismatch.
            // Never let an unconfirmed planned sample masquerade as the engine's settled aspect.
            return currentOpeningPropertyAspect ?? videoLayoutAspect ?? nativeVideoAspect
        }
        guard cropPresentationRect != Self.fullSourceCrop,videoDisplayH>0,
              embeddedBackend || (!vrModeEnabled && !surfaceToolsEnabled && sourceCropPropertyRequested) else{return nil}
        let base = nativeVideoAspect ?? videoDisplayW/videoDisplayH
        return base*Double(cropPresentationRect.width/cropPresentationRect.height)
    }
    private var menuCropOwnsSelection=false
    private var manualMenuCropAspect:Double?
    var selectedMenuCropAspect:Double? {manualMenuCropAspect ?? stereoMenuCropAspect}
    var lastSourceCropValue=""
    var sourceCropPropertyActive=false
    private var sourceCropPropertyRequested=false
    /// gor 514: real mpv crop for a committed crop-detect rect (labelled @gorcrop). While it is verified
    /// live the overlay is the identity; in every other state the existing overlay crop path is untouched.
    private var cropMPV = GorCropMPV()
    private var cropAutoRetries = 0
    private var lastMediaTitle:   String = ""
    var currentFilePath:          String = ""
    /// gor 514 opening-fit wiring (candidate 2026-11-01 v6, static review
    /// only). PER-OPEN identity: a path change, the dimension arrivals and
    /// the FIRST file-loaded of one logical opening all refer to the SAME
    /// open identity (openingFitOpenSeq), so at most one fit is emitted
    /// per opening and no later event of that opening (dims hop, the
    /// trailing file-loaded, a duplicate file-loaded) can re-apply over a
    /// user resize. A same-path reopen is detected structurally: mpv
    /// emits end-file before the new file-loaded of the same path, so a
    /// file-loaded arriving with an intervening end-file (and no path
    /// change) mints the next identity; a file-loaded with NO intervening
    /// end-file is a duplicate of the current opening and can never
    /// re-apply. v6: a music-exit (non-baseline, 0.38) arm or just-applied
    /// resume OWNS the load that follows its own stop end-file - the
    /// reopen re-mint must not clobber it to baseline, in EITHER event
    /// order (end-file -> file-loaded -> dims, end-file -> dims ->
    /// file-loaded). currentFilePath is never touched (playhead/stall
    /// identity). R-adjacent assumptions, both conservative: a same-path
    /// reload with no intervening end-file is indistinguishable from a
    /// duplicate file-loaded and is treated as the same opening; a
    /// reopen inside a music-exit epoch is taken for the resume's own
    /// load. Either way a refit is skipped, never an override of a user
    /// resize.
    private var openingFitOpenSeq: Int = 0
    private var openingFitArmedOpen: Int? = nil
    private var openingFitPendingFraction: Double = GorVideoFit.openBaselineFraction
    /// True after a path change until that opening's first file-loaded.
    private var openingFitAwaitingFirstLoad: Bool = false
    /// End-file seen since the last accepted file-loaded: the structural
    /// marker separating a same-path reopen (next identity) from a
    /// duplicate file-loaded (same identity).
    private var openingFitSawEndFile: Bool = false
    /// A non-baseline (music-exit) fit was emitted since the last accepted
    /// file-loaded: the next same-path file-loaded still belongs to that
    /// resume even though its arm is already consumed (order end-file ->
    /// dims -> file-loaded).
    private var openingFitNonBaselineApplied: Bool = false
    /// gor 514 trigger/clamp: arm visibility for AppDelegate's clamp
    /// guard (opening/clamp isolation). Read-only.
    var openingFitPending: Bool { openingFitArmedOpen != nil }
    /// Freshness for the file-loaded immediate attempt: display dims only
    /// count when measured for the path currently loaded.
    private var lastDisplayDimsValid: Bool = false
    private var lastDisplayDimsPath: String = ""
    /// gor 514: mint the NEXT open identity and arm it. Only three sites
    /// mint: a path change, a structural same-path reopen, a music exit.
    private func mintOpeningFitOpen(fraction: Double) {
        guard !currentFilePath.isEmpty else { return }
        openingFitOpenSeq &+= 1
        openingFitArmedOpen = openingFitOpenSeq
        openingFitPendingFraction = fraction
    }
    /// gor 514: one-shot opening fit - propose a resolution-sensitive size
    /// (GorVideoFit.proposedOpenSize), contain the chrome-inclusive frame
    /// inside the usable screen on BOTH axes (GorOpeningFit, pinned mpv
    /// v0.41.0 semantics), then hand mpv an absolute DEVICE-PIXEL geometry.
    /// At most one apply per open identity: the arm is consumed here, so
    /// nothing later in the same opening can re-apply over a user resize.
    /// Fullscreen windows are skipped while still consuming the arm (D7,
    /// unresolved choice).
    private func applyOpeningFitIfArmed(videoW: Double, videoH: Double) {
        guard openingFitArmedOpen != nil, !currentFilePath.isEmpty,
              videoW > 0, videoH > 0 else { return }
        openingFitArmedOpen = nil
        defer {
            if let aspect=deferredWindowRefitAspect {refitWindowForCrop(aspect:aspect)}
            reconcileCropPropertyWindow()
        }
        // gor-fit.lua already sized this window before the first frame (baseline opens only). A second geometry
        // here would be the visible resize after show. Music-exit restores (non-baseline fraction) keep the old path.
        if Self.gorFitScriptActive && openingFitPendingFraction == GorVideoFit.openBaselineFraction { return }
        // D7 (corrected in v6): mpv's OWN fullscreen state, IPC-observed on
        // AppDelegate. The overlay window is borderless
        // (DraggableOverlayWindow, .fullScreenAuxiliary) and can NEVER carry
        // .fullScreen - reading window?.styleMask here made the guard a
        // compile-time no-op in v3-v5.
        guard (NSApp.delegate as? AppDelegate)?.playerFullscreenState != true,
              let geom = GorOpeningFit.openingGeometry(
                  videoW: videoW, videoH: videoH,
                  screen: window?.screen ?? NSScreen.main,
                  floorFraction: openingFitPendingFraction) else { return }
        ipcCommand(MPVCommand.make(["set_property", "geometry", geom]))
        if openingFitPendingFraction != GorVideoFit.openBaselineFraction {
            openingFitNonBaselineApplied = true
        }
    }
    private var lastShownMPVOSD:  String = ""
    private(set) var visiblePictureBounds:CGRect = .zero
    // Overlay chrome uses the cropped film frame. Keeping the rect PPController-owned
    // lets SpineUI and the 3D tune overlay track one layout.
    private(set) var controlChromeBounds:CGRect = .zero
    var onVideoFrameApplied: ((CGRect, CGRect, CGRect) -> Void)?
    private struct VideoFramePanelEntry {
        weak var view: NSView?
        let padL: CGFloat
        let padR: CGFloat
        let padT: CGFloat
    }
    private var videoFramePanels: [VideoFramePanelEntry] = []
    func registerVideoFramePanel(_ view: NSView, padL: CGFloat, padR: CGFloat, padT: CGFloat) {
        videoFramePanels.append(VideoFramePanelEntry(view: view, padL: padL, padR: padR, padT: padT))
        reflowVideoFramePanel(view, padL: padL, padR: padR, padT: padT, base: stereoPanelBounds)
    }
    func unregisterVideoFramePanel(_ view: NSView) {
        videoFramePanels.removeAll { $0.view == nil || $0.view === view }
    }
    private var stereoManualAspect: Double?
    private var stereoMenuCropAspect: Double?
    private var stereoGeometryKey = ""
    private var stereoProjectionBaseAspect: Double?
    private var stereoWindowOwned = false
    private var stereoRestorePending = false
    private var stereoMenuOriginalFrame: NSRect?
    func applyMenuCrop(aspect: Double) -> Bool {
        if refuseEmbedded("video crop") {return false}
        if !vrModeEnabled {
            cropDetector.cancel();manualRedetectInFlight=false
            manualMenuCropAspect=aspect;menuCropOwnsSelection=true
            requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true)
            refitWindowForCrop(aspect:aspect)
            return true
        }
        cropDetector.cancel(); manualRedetectInFlight = false
        stereoRestorePending = false
        if stereoMenuOriginalFrame == nil { stereoMenuOriginalFrame = window?.frame }
        if stereoProjectionBaseAspect == nil { stereoProjectionBaseAspect = nativeVideoAspect.map { $0 * 0.5 } }
        menuCropOwnsSelection=true
        stereoMenuCropAspect = aspect
        refreshStereoMenuGeometry(force:true)
        return true
    }
    static var cropPacketSession=""
    private var cropBoundLaunchSession=PPController.cropPacketSession
    /// Called only by AppDelegate's actual new-receiver launch path, never by receiver content.
    func beginCropReceiverLaunch(_ session:String) {
        guard !session.isEmpty,session==Self.cropPacketSession,session != cropBoundLaunchSession else{return}
        cropDetectionStopped=false
        cropBoundLaunchSession=session
        cropFreshFollowup &+= 1;cropSourceOpening &+= 1;cropMeasurementEpoch &+= 1
        cropPacketIntentGen &+= 1;cropPacketIntent=nil;cropPacketPending=nil;cropPacketFinal=nil;cropPacketToken=nil
        cropReceiverCount=0;cropReceiverSeekGeneration=0;cropReceiverSeekToken=nil
        cropPacketTokenAttempts=0;cropPacketAcceptance="unresolved";cropConfirmedRect=nil;cropConfirmedIdentity=nil;cropSourceAcceptanceAnchor=nil
        cropSeekFenceActive=false;cropFreshMeasurementRequired=false;manualRedetectInFlight=false
        // Wire query ids and sample sequence stay launch-monotonic for this controller.
        cancelCropMotion()
        if !embeddedBackend,!vrModeEnabled,!surfaceToolsEnabled {cropDetector.invalidateMeasurementContext()}
    }
    private var cropPacketOpeningStamp:UInt64=0 // persistent connection queue only
    private var cropPacketLocalStamp:UInt64=0 // main queue
    private var cropPacketToken:String?
    private var cropPacketQueryId=9_196_000_000
    private var cropPacketPending:(id:Int,stamp:UInt64,path:String,rect:CGRect,gen:UInt64)?
    private var cropPacketIntent:(rect:CGRect,path:String,automatic:Bool,measured:Bool,epoch:UInt64,opening:UInt64)?   // unfulfilled crop request kept across token retry/refresh
    // One manual request may wait behind a running automatic scan. Its
    // detector token also fences every cancel/invalidation, including same-path reuse.
    private var queuedManualCrop:(path:String,opening:UInt64,epoch:UInt64,token:Int)?
    private func finishQueuedManualCrop(terminal:Bool,decisive:Bool,usable:Bool) {
        guard let queued=queuedManualCrop else{return}
        if usable {queuedManualCrop=nil;return}
        guard terminal else{return}
        queuedManualCrop=nil
        guard !decisive,!cropDetector.isPending,!presentationIsQuitting,!cropDetectionStopped,
              !mediaTransitionPending,!menuCropOwnsSelection,
              queued.path==currentFilePath,queued.opening==cropSourceOpening,
              queued.epoch==cropMeasurementEpoch,queued.token==cropDetector.retryToken else{return}
        // The completed automatic batch remains automatic. Only this new
        // invocation obtains the detector's fresh/manual sample semantics.
        reDetectCrop()
    }
    private var cropMeasurementEpoch:UInt64=0
    private var cropSourceOpening:UInt64=0
    private var cropReceiverSeekToken:String?
    private var cropSeekFenceActive=false
    private var cropFreshMeasurementRequired=false
    private func fenceCropMeasurementForSeek() {
        queuedManualCrop=nil
        guard !embeddedBackend,!vrModeEnabled,!surfaceToolsEnabled,Self.gorFitScriptActive else{return}
        guard !cropSeekFenceActive else{return}
        cropSeekFenceActive=true;cropMeasurementEpoch &+= 1
        // A manual measurement is stale after seek too; explicit reset is not a measurement.
        let staleMeasurement=manualRedetectInFlight || cropDetector.isPending
        manualRedetectInFlight=false
        cropDetector.invalidateMeasurementContext()
        if staleMeasurement {cropFreshMeasurementRequired=true}
        if cropPacketIntent?.measured==true {
            dropCropPacketIntent();cancelCropMotion()
            cropFreshMeasurementRequired=true
            wtCropRetry[currentFilePath]=nil
        }
    }
    private var cropDetectionStopped=false
    private func stopCropFreshFollowthrough() {
        queuedManualCrop=nil
        cropSearchWake &+= 1;cropSearchWakePending=false
        cropFreshFollowup &+= 1
        cropFreshMeasurementRequired=false
        cropDetectionStopped=true
    }
    private var cropFreshFollowup:UInt64=0
    private func scheduleCropFreshFollowthrough(_ attempt:Int=0) {
        guard !presentationIsQuitting,!cropDetectionStopped,cropFreshMeasurementRequired,!currentFilePath.isEmpty,!menuCropOwnsSelection else{return}
        cropFreshFollowup &+= 1
        let ticket=cropFreshFollowup,path=currentFilePath,opening=cropSourceOpening,measurement=cropMeasurementEpoch
        let delay=[0.05,0.5,2.0][min(attempt,2)]
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
            guard let self,self.cropFreshFollowup==ticket,self.currentFilePath==path,
                  self.cropSourceOpening==opening,self.cropMeasurementEpoch==measurement,
                  !self.presentationIsQuitting,!self.cropDetectionStopped,self.cropFreshMeasurementRequired,!self.mediaTransitionPending,!self.menuCropOwnsSelection else{return}
            if self.cropDetector.isPending {return} // an existing fresh scan owns completion/retry
            if self.isPlaying,!HeatTelemetry.thermalPressure,self.cropDetector.isMainPlaybackReady(),
               self.videoDisplayW>0,self.videoDisplayH>0 {
                self.startAutomaticCropDetection(needsRedetect:true)
                if self.cropDetector.isPending {return}
            }
            if attempt<2 {self.scheduleCropFreshFollowthrough(attempt+1)}
            else {self.showCropDetectOSD("crop waiting for a fresh measurement")}
            // Three bounded admission attempts only. Playback/dims/user events retain their existing triggers.
        }
    }
    private var cropPacketIntentGen:UInt64=0   // bumped on every set/drop so delayed retries and late replies die with the intent they served
    private var cropPacketSampleSequence:UInt64=0
    private var cropPacketFinal:(token:String,path:String,intent:UInt64,motion:UInt64,sequence:UInt64,crop:String,rect:CGRect)?
    private var cropConfirmedIdentity:(session:String,path:String,opening:UInt64,intent:UInt64,token:String)?
    // Last source-command acceptance in this opening, not a displayed frame and not current-target success.
    // Keep through failed newer intents/token rotations so automatic narrowing cannot erase its protection.
    private var cropSourceAcceptanceAnchor:(session:String,path:String,opening:UInt64,rect:CGRect)?
    private var cropNarrowingPolicyAnchor:CGRect? {
        guard usesCropCommandReceipts else{return cropRect}
        if let anchor=cropSourceAcceptanceAnchor,anchor.session==cropBoundLaunchSession,
           anchor.path==currentFilePath,anchor.opening==cropSourceOpening {
            return anchor.rect == Self.fullSourceCrop ? nil:anchor.rect
        }
        return cropCommandInFlight ? cropRect:nil
    }
    private func cropMayAutomaticallyReplaceTarget(_ rect:CGRect)->Bool {
        guard let anchor=cropNarrowingPolicyAnchor else{return true}
        return rect.minX <= anchor.minX && rect.minY <= anchor.minY && rect.maxX >= anchor.maxX && rect.maxY >= anchor.maxY
    }
    private var usesCropCommandReceipts:Bool {!embeddedBackend && !vrModeEnabled && !surfaceToolsEnabled && Self.gorFitScriptActive}
    /// Receiver command acceptance, never displayed-frame evidence. A new target invalidates the old identity.
    private var commandAcceptedCropRect:CGRect? {
        guard let identity=cropConfirmedIdentity,identity.session==cropBoundLaunchSession,
              identity.path==currentFilePath,identity.opening==cropSourceOpening,
              identity.intent==cropPacketIntentGen,identity.token==cropPacketToken else{return nil}
        return cropConfirmedRect
    }
    private var cropCommandInFlight:Bool {
        guard let intent=cropPacketIntent,intent.path==currentFilePath,intent.opening==cropSourceOpening,
              (!intent.measured || intent.epoch==cropMeasurementEpoch) else{return false}
        return cropMotionActive || cropPacketPending != nil || (cropPacketFinal != nil && cropPacketAcceptance=="awaiting")
    }
    /// Planning may coalesce active work; only accepted non-full crop may suppress a settled search.
    private var cropSearchOwnsSelection:Bool {
        if !usesCropCommandReceipts {return cropRect != nil}
        if cropCommandInFlight {return true}
        return commandAcceptedCropRect.map{$0 != Self.fullSourceCrop} ?? false
    }
    private var cropMayRedriveIdenticalTarget:Bool {
        usesCropCommandReceipts && !cropCommandInFlight && commandAcceptedCropRect != cropRect
    }
    private var cropReassertableRect:CGRect? {
        if !usesCropCommandReceipts {return cropRect}
        guard !cropCommandInFlight,let rect=commandAcceptedCropRect,rect != Self.fullSourceCrop else{return nil}
        return rect
    }
    private var cropConfirmedRect:CGRect? // receiver command/readback acceptance, NOT a displayed-frame receipt
    private(set) var cropPacketAcceptance="unresolved"
    // Launch-session high water is not reset by same-path reopen or socket reconnect.
    // A receiver restart needs the launch nonce contract, never a lower counter override.
    private var cropReceiverCount:Int64=0
    private var cropReceiverSeekGeneration:Int64=0
    private func validatedCropReceiverCount(_ data:Any?,_ arrivalStamp:UInt64)->Int64? {
        guard cropBoundLaunchSession==Self.cropPacketSession,arrivalStamp==cropPacketLocalStamp,!mediaTransitionPending,
              let state=PlayerCropEpoch.decode(data),state.session==Self.cropPacketSession,
              state.path==currentFilePath,
              state.count>=cropReceiverCount,
              state.seekGeneration>=cropReceiverSeekGeneration,state.seekGeneration<=state.count,
              (state.count>cropReceiverCount || state.seekGeneration==cropReceiverSeekGeneration) else{return nil}
        return state.count
    }
    private func noteReceiverCropSeek(_ data:Any?,_ count:Int64) {
        guard count>cropReceiverCount else{return}
        cropReceiverCount=count
        guard let state=PlayerCropEpoch.decode(data),state.seekGeneration>cropReceiverSeekGeneration else{return}
        let seek=state.seekGeneration
        cropReceiverSeekGeneration=seek
        cropReceiverSeekToken=Self.cropPacketSession+":"+String(count)
        // Only a validated forward receiver boundary may cancel a current measurement.
        cropSeekFenceActive=false
        fenceCropMeasurementForSeek()
        scheduleCropFreshFollowthrough()
    }
    private func noteCropPacketReceipt(_ data:Any?) {
        guard let expected=cropPacketFinal,let r=PlayerCropReceipt.decode(data),
              r.token==expected.token,r.path==expected.path,
              r.intent==String(expected.intent),r.motion==String(expected.motion),
              r.sequence==String(expected.sequence),r.crop==expected.crop,
              expected.path==currentFilePath,expected.token==cropPacketToken,
              expected.intent==cropPacketIntentGen,expected.motion==cropMotionGeneration else{return}
        let source:String?=r.source,geometry:String?=r.geometry
        let policySatisfied=r.policySatisfied
        if source=="accepted" {
            let tag="\(expected.token)|\(expected.intent)|\(expected.motion)|\(expected.sequence)"
            if cropLayoutReadback?.tag != tag {
                cropLayoutReadback=(tag,expected.intent,expected.crop)
                pollEngine.requestCropLayoutReadback(tag)
            }
            cropSourceAcceptanceAnchor=(cropBoundLaunchSession,currentFilePath,cropSourceOpening,expected.rect)
            // Source acceptance arrives only after Lua's source-layout event or
            //500ms fallback. Use the same explicit window-fit caller as stereo;
            // a missing tagged polling batch must not suppress the native fit.
            // Fullscreen keeps its existing deferred window ownership.
            if geometry == "accepted",let aspect=cropWindowAspect(expected.rect) {
                refitWindowForCrop(aspect:aspect)
            }
        }
        if source=="accepted" && policySatisfied {
            cropConfirmedRect=expected.rect
            cropConfirmedIdentity=(cropBoundLaunchSession,currentFilePath,cropSourceOpening,expected.intent,expected.token)
        }
        cropPacketAcceptance=source=="accepted" && policySatisfied ? "accepted":"partial-or-failed"
        if cropPacketAcceptance=="accepted" {
            cropPacketIntent=nil;cropPacketFinal=nil
            showCropDetectOSD("crop command accepted")
        } else {
            cropDetector.resetLastFile() // a later natural trigger may re-measure; no new scan loop
            scheduleCropCommandRecovery()
            showCropDetectOSD("crop not confirmed: source \(source ?? "missing"), window \(geometry ?? "missing")")
            print("[crop-receipt] unresolved source=\(source ?? "missing") geometry=\(geometry ?? "missing")")
        }
    }
    private var cropCommandRecoveryGen:UInt64=0
    private var cropCommandRecoveryAttempts=0
    private var cropCommandRecoveryPending:UInt64?
    private func scheduleCropCommandRecovery() {
        guard usesCropCommandReceipts,!presentationIsQuitting,!cropDetectionStopped,
              let intent=cropPacketIntent,intent.path==currentFilePath,intent.opening==cropSourceOpening,
              (!intent.measured || intent.epoch==cropMeasurementEpoch),!mediaTransitionPending,
              (!menuCropOwnsSelection || intent.rect==Self.fullSourceCrop) else{return}
        let gen=cropPacketIntentGen
        if cropCommandRecoveryGen != gen {cropCommandRecoveryGen=gen;cropCommandRecoveryAttempts=0;cropCommandRecoveryPending=nil}
        guard cropCommandRecoveryAttempts<3,cropCommandRecoveryPending==nil else{return}
        cropCommandRecoveryAttempts+=1;cropCommandRecoveryPending=gen
        let attempt=cropCommandRecoveryAttempts,path=currentFilePath,opening=cropSourceOpening
        let delay=[0.5,2.0,5.0][attempt-1]
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
            guard let self,self.cropCommandRecoveryPending==gen,self.cropCommandRecoveryGen==gen else{return}
            self.cropCommandRecoveryPending=nil
            guard !self.presentationIsQuitting,!self.cropDetectionStopped,self.cropPacketIntentGen==gen,
                  self.currentFilePath==path,self.cropSourceOpening==opening,
                  let current=self.cropPacketIntent,current.path==path,current.opening==opening,
                  (!current.measured || current.epoch==self.cropMeasurementEpoch),!self.mediaTransitionPending,
                  (!self.menuCropOwnsSelection || current.rect==Self.fullSourceCrop),
                  !self.cropCommandInFlight else{return}
            self.requestRealCrop(current.rect,resuming:gen)
        }
    }
    private var cropPacketTokenAttempts=0   // per opening; bounds timeout and epoch-refresh retries
    private static let cropPacketMaxTokenAttempts=8
    private func invalidateCropPacketToken(_ stamp:UInt64) {
        cropPacketLocalStamp=stamp
        fenceCropPacketTransport()
    }
    /// A transport fence (reconnect, start-file, epoch rotation) kills the
    /// token, the in-flight query and any running motion, but never the desire:
    /// an unchanged intent re-acquires a token so the crop still lands. A new
    /// opening/user action drops the intent separately (dropCropPacketIntent).
    private func fenceCropPacketTransport() {
        cropPacketToken=nil;cropPacketPending=nil;cropPacketFinal=nil;cropPacketAcceptance="unresolved"
        cancelCropMotion()
        if let intent=cropPacketIntent,intent.path==currentFilePath,intent.opening==cropSourceOpening,
              (!intent.measured || intent.epoch==cropMeasurementEpoch),!mediaTransitionPending,
           (!menuCropOwnsSelection || intent.rect==Self.fullSourceCrop) {
            requestCropPacketToken(intent.rect)
        }
    }
    private func requestCropPacketToken(_ rect:CGRect) {
        guard cropBoundLaunchSession==Self.cropPacketSession,cropPacketPending==nil,!currentFilePath.isEmpty else{return}
        guard cropPacketQueryId<9_196_999_999 else {print("[crop-receipt] token request identity exhausted; unresolved");return}
        cropPacketQueryId+=1 // launch-monotonic; never reuse a wire identity after wrap
        let id=cropPacketQueryId,stamp=cropPacketLocalStamp,path=currentFilePath,gen=cropPacketIntentGen
        cropPacketPending=(id,stamp,path,rect,cropPacketIntentGen)
        if let bytes=try? JSONSerialization.data(withJSONObject:["command":["get_property","user-data/gor/crop-epoch-state"],"request_id":id]),let text=String(data:bytes,encoding:.utf8) {persistentConnection.write(text)}
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
            guard let self,let pending=self.cropPacketPending,pending.id==id,pending.gen==gen,
                  pending.stamp==stamp,pending.path==path,self.cropPacketIntentGen==gen,
                  self.cropPacketLocalStamp==stamp,self.currentFilePath==path else{return}
            self.cropPacketPending=nil // Fail closed, no packet from an unbound token.
            self.retryCropPacketIntent() // The crop request survives a lost/slow token reply.
        }
    }
    private func acceptCropPacketToken(_ id:Int,_ ok:Bool,_ data:Any?,_ arrivalStamp:UInt64) {
        // Request authority comes BEFORE data can affect any scan, intent, or high water.
        guard let pending=cropPacketPending,pending.id==id,pending.gen==cropPacketIntentGen,
              pending.stamp==cropPacketLocalStamp,pending.stamp==arrivalStamp,
              pending.path==currentFilePath,!mediaTransitionPending else{return}
        guard ok,let count=validatedCropReceiverCount(data,arrivalStamp) else {
            cropPacketPending=nil;retryCropPacketIntent();return
        }
        noteReceiverCropSeek(data,count)
        // Processing a fresh seek may have invalidated this measured request.
        guard cropPacketPending?.id==id,cropPacketIntentGen==pending.gen else{return}
        cropPacketPending=nil
        cropPacketToken=Self.cropPacketSession+":"+String(count)
        requestRealCrop(pending.rect,resuming:pending.gen)
    }
    /// Bounded retry for an unfulfilled crop intent: token reply timeout,
    /// refused token validation, or an observed epoch rotation (script reload).
    private func retryCropPacketIntent() {
        // fullSource (reset/uncrop) comes from the user/menu itself; menu ownership suppresses only automatic crops
        guard let intent=cropPacketIntent,intent.path==currentFilePath,intent.opening==cropSourceOpening,
              (!intent.measured || intent.epoch==cropMeasurementEpoch),!mediaTransitionPending,
              (!menuCropOwnsSelection || intent.rect==Self.fullSourceCrop) else{cropPacketIntent=nil;return}
        guard cropPacketToken==nil,cropPacketPending==nil else{return}
        guard cropPacketTokenAttempts<Self.cropPacketMaxTokenAttempts else{
            print("[croptoken] token retries exhausted for this opening; crop intent kept for the next explicit request")
            return
        }
        cropPacketTokenAttempts+=1
        let gen=cropPacketIntentGen
        DispatchQueue.main.asyncAfter(deadline:.now()+Double(cropPacketTokenAttempts)) { [weak self] in
            guard let self,self.cropPacketToken==nil,self.cropPacketPending==nil,
                  self.cropPacketIntentGen==gen,
                  let current=self.cropPacketIntent,current.path==self.currentFilePath,current.opening==self.cropSourceOpening,
                  (!current.measured || current.epoch==self.cropMeasurementEpoch),!self.mediaTransitionPending else{return}
            self.requestCropPacketToken(current.rect)
        }
    }
    /// An epoch rotation observed over IPC (script reload/on_load) is a
    /// transport fence: the intent survives and re-acquires, so a reload during
    /// the first query or mid-motion cannot silently lose the crop (the
    /// transitionCrop sameCrop early-return would never re-drive it).
    private func noteCropEpochRotation(_ data:Any?,_ arrivalStamp:UInt64) {
        // Observation route shares the exact same stamp/session/path/count validation.
        guard let count=validatedCropReceiverCount(data,arrivalStamp) else{return}
        let forward=count>cropReceiverCount
        noteReceiverCropSeek(data,count)
        let identity=Self.cropPacketSession+":"+String(count)
        if !forward || cropPacketToken==identity {return}
        fenceCropPacketTransport()
    }
    private(set) var mediaTransitionPending=false
    private var mediaTransitionLoaded=false
    private var mediaTransitionNeedsFit=false
    func beginMediaTransition(suspendRender:Bool=true) {
        cropPacketToken=nil;dropCropPacketIntent()
        cancelCropMotion() // Fence pending samples before ordered load/stop/quit commands.
        mediaTransitionPending=true;mediaTransitionLoaded=false;mediaTransitionNeedsFit=false
        if suspendRender {
            vr180Controller?.invalidateAutoFitEntry()
            (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.setMediaTransitionPending(true)
            ThreeDPrepareRuntime.launcher?.cancelForMediaTransition()
        }
        ipcCommand(#"{"command":["set_property","user-data/gor/media-transition",true]}"#)
        ipcCommand(#"{"command":["script-message-to","gor_fit","cancel"]}"#)
        ipcCommand(#"{"command":["script-message-to","vr180_look","vr180-look-cancel-fit"]}"#)
        cropDetector.cancel();deferredWindowRefitAspect=nil
    }
    private func finishMediaTransition() {
        mediaTransitionPending=false;mediaTransitionNeedsFit=true
        (ThreeDRuntime.coordinator as? ThreeDRenderCoordinator)?.setMediaTransitionPending(false)
        ipcCommand(#"{"command":["set_property","user-data/gor/media-transition",false]}"#)
        // Both geometry writers park while the media transition is pending. Replay only the final mode's fit.
        if vrModeEnabled {
            stereoGeometryKey="";refreshStereoMenuGeometry(force:true)
            appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero;applyVideoFrame(bounds:bounds)
        } else if let a=deferredWindowRefitAspect {deferredWindowRefitAspect=nil;refitWindowForCrop(aspect:a)}
    }
    private func refreshStereoMenuGeometry(force: Bool = false) {
        guard !mediaTransitionPending else { return }
        guard vrModeEnabled else {
            if stereoWindowOwned { ipcCommand(#"{"command":["set_property","user-data/gor/stereo-window-owned",false]}"#) }
            stereoWindowOwned = false; stereoGeometryKey = ""
            return
        }
        // Never feed the output window's aspect back as SOURCE metadata.
        guard let source = vr180Controller?.flatUIEyeAspect ?? stereoProjectionBaseAspect ?? nativeVideoAspect.map({ $0 * 0.5 }),source>0 else { return }
        guard let p = StereoMenuGeometry.plan(sourceAspect:source,aspectOverride:stereoManualAspect,
            cropAspect:stereoMenuCropAspect,gap:effectiveVrGap?.value ?? 0) else { return }
        // Both flat and projected stereo use this target. Leaving projection to the generic
        // packed-video follower retains a stale aspect after SBS -> VR or reset.
        let owns = vrModeEnabled
        if owns != stereoWindowOwned { ipcCommand("{\"command\":[\"set_property\",\"user-data/gor/stereo-window-owned\",\(owns)]}") }
        stereoWindowOwned = owns
        let viewport=StereoMenuGeometry.viewport(p,detected:visualCropRect,menuOwns:cropMenuOwnsPresentation)
        let key = "\(viewport.key):\(p.eyeAspect):\(owns):\(openingFitPending):\(videoLayoutRotation)"
        guard force || key != stereoGeometryKey else { return }
        stereoGeometryKey = key
        guard publishSurfaceWindowCrop(x:viewport.scaleX,y:viewport.scaleY,cx:viewport.centerX,cy:viewport.centerY) else { return }
        if owns && !stereoRestorePending { refitWindowForCrop(aspect:Int(videoLayoutRotation) % 180 == 0 ? viewport.windowAspect : 1/viewport.windowAspect) }
        appliedVideoFrame = .zero; appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds:bounds)
    }
    func noteAspectMenuSelection(_ ratio: Double?) {
        if vrModeEnabled, stereoMenuOriginalFrame == nil { stereoMenuOriginalFrame = window?.frame }
        if vrModeEnabled, stereoProjectionBaseAspect == nil { stereoProjectionBaseAspect = nativeVideoAspect.map { $0 * 0.5 } }
        // Reset returns to the measured current film, never a saved window from an older ratio.
        // A previous restore must not block subsequent automatic or manual stereo geometry.
        stereoRestorePending = false
        stereoManualAspect = ratio
        stereoGeometryKey = ""
        refreshStereoMenuGeometry(force:true)
        if !vrModeEnabled { refitWindowForCrop(aspect:ratio ?? manualMenuCropAspect ?? nativeVideoAspect) }
        appliedVideoFrame = .zero; appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds:bounds)
    }
    @discardableResult
    private func publishSurfaceWindowCrop(x:Double,y:Double,cx:Double=0.5,cy:Double=0.5) -> Bool {
        guard let (w,h)=surfaceDrawableReceipt() else { surfaceCropAwaitingDrawable=true;print("[surface-anchor] drawable receipt unavailable; crop refit held");return false }
        let a=nativeVideoAspect ?? 1, crop=manualMenuCropAspect
        let sx=crop.map { min(1,$0/a) } ?? x, sy=crop.map { min(1,a/$0) } ?? y
        let p=(scaleX:"\(sx)|\(cx)|\(w)",scaleY:"\(sy)|\(cy)|\(h)")
        ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-menu-crop\",\"\(p.scaleX)\",\"\(p.scaleY)\"]}")
        if !cropMenuOwnsPresentation, let rect=visualCropRect { ipcCommand("{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-bar-crop\",\"\(rect.minX)\",\"\(rect.minY)\",\"\(rect.width)\",\"\(rect.height)\"]}") }
        return true
    }
    private func flatEyeContentBounds(_ band: CGRect) -> CGRect {
        guard vr180Controller?.isFlatStereo == true,
              let aspect = StereoMenuGeometry.plan(sourceAspect:vr180Controller?.flatUIEyeAspect ?? 1,aspectOverride:stereoManualAspect,cropAspect:stereoMenuCropAspect,gap:effectiveVrGap?.value ?? 0)?.eyeAspect, aspect > 0 else {return band}
        let domain = cropMenuOwnsPresentation ? nil:visualCropRect
        let ar=CGFloat(aspect)*(domain.map {$0.width/$0.height} ?? 1)
        if ar > band.width/band.height {
            let h=band.width/ar
            return CGRect(x:band.minX,y:band.midY-h/2,width:band.width,height:h)
        }
        let w=band.height*ar
        return CGRect(x:band.midX-w/2,y:band.minY,width:w,height:band.height)
    }
    var stereoPanelBounds: CGRect {
        visiblePictureBounds == .zero ? bounds:visiblePictureBounds
    }

    private func reflowVideoFramePanel(_ view: NSView, padL: CGFloat, padR: CGFloat, padT: CGFloat, base: CGRect) {
        // padL/padT are design-space inputs; padR is a legacy caller hint.
        // One source owns panel clearances: the left/right gaps to
        // spine/sidebar stay equal at every layout scale.
        _ = padR
        let leftPad = PhotonFont.chromeValue(padL)
        let rightPad = IconBarFit.panelPadR(padL: padL)
        let topPad = PhotonFont.chromeValue(padT)
        view.frame = CGRect(x: base.minX + leftPad, y: base.minY + topPad,
                            width: base.width - leftPad - rightPad, height: base.height - topPad * 2)
    }

    private var musicModeController: MusicModeController?
    var musicPanel: MusicPanel? { musicModeController?.musicPanel }
    var musicController: MusicController? { musicModeController?.musicController }
    var isMusicMode: Bool { musicModeController?.isMusicMode ?? false }
    func toggleMusicMode() { musicModeController?.toggleMusicMode() }

    private var iptvModeController: IPTVModeController?
    var iptvPanel: IPTVPanel? { iptvModeController?.iptvPanel }
    var isIptvMode: Bool { iptvModeController?.isIptvMode ?? false }
    var iptvChannelTitle: String {
        get { iptvModeController?.iptvChannelTitle ?? "" }
        set { iptvModeController?.iptvChannelTitle = newValue }
    }
    func toggleIptvMode() {
        iptvModeController?.toggleIptvMode()
        if isIptvMode { wakeUI() } // reopening a chrome-faded panel must reveal it immediately
    }
    typealias HLSVariant = IPTVModeController.HLSVariant

    private(set) var isLive = false

    var originalBrightness: Float { brightness.originalBrightness }

    private var autoPlayTried  = false
    private var wtCropRetry: [String: (n: Int, t: TimeInterval, scannedEnd: Double)] = [:]   // retries per remembered wt file; 64 most recent, oldest evicted
    // At most one vetoed final-result recovery per opening. A scan may finish
    // after its safety window; dropping it must not permanently lock the file.
    private var rejectedCropRetryAvailable = true
    private func recoverRejectedAutomaticCrop(early:Bool,manual:Bool) {
        guard !early,!manual,!cropSearchOwnsSelection,CropDetector.isWTPlayback(currentFilePath) else {return}
        wtCropRetry[currentFilePath]=nil
        guard rejectedCropRetryAvailable else {
            print("[cropdetect] safety-veto recovery exhausted; full picture kept until a new explicit search")
            return
        }
        rejectedCropRetryAvailable=false
        cropDetector.resetLastFile()
        let path=currentFilePath,token=cropDetector.retryToken
        wtCropRetry[path]=(1,ProcessInfo.processInfo.systemUptime,cropDetector.currentAutoDispatchFrontier() ?? lastSeekableEnd)
        let delay=Self.wtCropRetryDelay(attempt:1)
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
            guard let self,self.currentFilePath==path,self.cropDetector.retryToken==token else {return}
            self.fireWTCropRetry(path,token:token)
        }
    }
    private var lastSeekableEnd: Double = 0   // newest downloaded second the poll has published for the current wt file
    private var lastVideoTrackID = 0   // last observed current-tracks/video/id; 0 = none observed for this file yet
    /// 199az: a crop is searched until found - +2s, +5s, +10s, then every 30s while playing. No give-up count.
    static func wtCropRetryDelay(attempt n: Int) -> Double { n <= 1 ? 2 : n == 2 ? 5 : n == 3 ? 10 : 30 }

    weak var appDelegate: AppDelegate?
    private var subtitleModeScale=SubtitleModeScale(normal:SubtitleSizePreference.restored() ?? 1,pip:SubtitleSizePreference.restoredPiP())
    private var pendingSubtitleModeScale:Double?
    var pendingSubtitleModePosition:Double?
    func synchronizeSubtitlePresentation(pictureInPicture:Bool) {
        ipcCommand(MPVCommand.make(["script-message-to", "gor_fit", "pip-mode", pictureInPicture ? "yes" : "no"]))
        guard let scale=subtitleModeScale.transition(to:pictureInPicture) else{
            subtitleView.setPictureInPictureTypography(pictureInPicture);return
        }
        pendingSubtitleModeScale=scale
        ipcCommand(MPVCommand.make(["set_property","sub-scale",scale]))
        subtitleView.setSubtitleFontScale(scale)
        subtitleView.setPictureInPictureTypography(pictureInPicture)
        let position=subtitleView.subtitlePositionProperty
        pendingSubtitleModePosition=position
        ipcCommand(MPVCommand.make(["set_property","sub-pos",position]))
        Diag.log("[subtitle-mode] pip=\(pictureInPicture) normal=\(subtitleModeScale.normal) pipScale=\(subtitleModeScale.pip) actual=\(subtitleView.typographyProbe)")
    }
    private func acceptSubtitleScale(_ value:Double) {
        if let expected=pendingSubtitleModeScale {
            guard abs(expected-value)<0.000001 else{return} // late old-mode poll
            pendingSubtitleModeScale=nil
        }
        subtitleModeScale.accept(value)
        subtitleView.setSubtitleFontScale(value)
        SubtitleSizePreference.save(value,pictureInPicture:subtitleModeScale.pictureInPicture)
    }

    // MARK: - Init

    var usesEmbeddedThreeDIntent: Bool { embeddedBackend }
    var embeddedThreeDState: ((ThreeDState, [ThreeDEffect], UInt64) -> String?)?
    var embeddedThreeDAction: ((ThreeDAction) -> String?)?

    /// Renderer-time failures use the same native-entry OSD, after the
    /// host has checked current session/source/receipt/acceptance custody.
    func showNativeStereoProjectionRefusal(_ reason: String) {
        guard embeddedBackend else { return }
        nativeStereoRefusal(reason)
    }

    private func nativeStereoRefusal(_ reason: String) {
        spineUI.showMPVOSD(reason, force: true)
        print("[engine] backend=gorav native-entry-refusal=\(reason)")
    }

    private func dispatchNativeStereoIntent(_ action: ThreeDAction) {
        guard let apply=embeddedThreeDAction else {
            nativeStereoRefusal("native entry: opened-source adapter unavailable"); return
        }
        if let reason=apply(action) { nativeStereoRefusal(reason) }
    }

    private let embeddedBackend:Bool
    var embeddedCommand:((String)->Void)?
    /// Typed host setter for session delays. Returns nil only when the session accepted the value, else a refusal reason.
    var embeddedDelay:((_ property:String,_ seconds:Double)->String?)?
    var embeddedSubtitleScale:((_ scale:Double)->String?)?
    var embeddedSubtitlePosition:((_ percent:Double)->String?)?
    /// Installed only with a real native session adapter. nil is an unavailable operation.
    var embeddedSourceCrop:((_ source:String,_ crop:CGRect)->String?)?
    var embeddedCropWindow:((_ frame:NSRect,_ aspect:Double,_ finished:Bool)->Bool)?
    init(frame: NSRect, ipcPath: String, embeddedBackend:Bool=false) {
        self.embeddedBackend=embeddedBackend
        self.ipcPath      = ipcPath
        self.ipcClient    = IPCClient(path: ipcPath)
        self.persistentConnection = PersistentEventConnection(path: ipcPath)
        self.pollEngine   = PollEngine(connection: persistentConnection,receiverSession:{PPController.cropPacketSession})
        self.brightness   = BrightnessController()
        // vendorPath: resolved vendored path, or the conventional sibling
        // path on a miss (logged); launchHiddenMpv's do/catch degrades crop.
        self.cropDetector = CropDetector(mpvPath: GORResources.vendorPath("mpv/bin/mpv"))
        self.cropDetector.mainIPCPath = ipcPath

        super.init(frame: frame)

        let previousCropConnect=persistentConnection.onConnected
        persistentConnection.onConnected = { [weak self] in
            previousCropConnect?()
            guard let self else{return}
            self.cropPacketOpeningStamp &+= 1
            let stamp=self.cropPacketOpeningStamp
            DispatchQueue.main.async { [weak self] in self?.invalidateCropPacketToken(stamp) }
            // Reload/on_load rotations surface here; the registration dies with the socket.
            self.persistentConnection.write(#"{"command":["observe_property",9196900,"user-data/gor/crop-epoch-state"]}"#)
            self.persistentConnection.write(#"{"command":["observe_property",9196901,"user-data/gor/crop-packet-receipt"]}"#)
        }
        persistentConnection.onLine = { [weak self] obj in
            if obj["event"] as? String == "start-file" {
                self?.cropPacketOpeningStamp &+= 1
                let stamp=self?.cropPacketOpeningStamp ?? 0
                DispatchQueue.main.async { [weak self] in self?.invalidateCropPacketToken(stamp) }
            }
            if let id=obj["request_id"] as? Int,(9_196_000_001..<9_197_000_000).contains(id) {
                let ok=obj["error"] as? String == "success",data=obj["data"]
                let stamp=self?.cropPacketOpeningStamp ?? 0
                DispatchQueue.main.async { [weak self] in self?.acceptCropPacketToken(id,ok,data,stamp) }
                return
            }

            if obj["request_id"] as? Int == 9_195_001 {
                let frame=obj["data"]
                DispatchQueue.main.async { [weak self] in self?.noteFilmFrame(frame) }
            } else if let rid=obj["request_id"] as? Int,(9_194_001..<9_195_000).contains(rid) {
                let data=obj["data"]
                DispatchQueue.main.async { [weak self] in self?.acceptFilmIdentityReply(rid,data) }
            } else if let rid = obj["request_id"] as? Int, GorClampFence.ownsRequestId(rid) {
                let ok = (obj["error"] as? String) == "success"
                DispatchQueue.main.async {
                    (NSApp.delegate as? AppDelegate)?.noteClampGeometryReply(id: rid, ok: ok)
                }
            } else if let rid = obj["request_id"] as? Int, GorCropMPV.owns(id: rid) {
                let ok = (obj["error"] as? String) == "success"
                let data = obj["data"]
                let arrival = self?.pollEngine.noteArrival() ?? 0   // P4: connection-queue barrier stamp
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.noteGorCropReply(id: rid, ok: ok, data: data, arrival: arrival)
                }
            } else if let rid=obj["request_id"] as? Int,PollEngine.ownsQueryReply(rid) {
                self?.pollEngine.handleLine(obj)
            } else if let rid=obj["request_id"] as? Int,PollEngine.ownsObservationAck(rid) {
                return // subscription ACK, not a property snapshot
            } else if let rid = obj["request_id"] as? Int, rid >= 3_000_001 {
                // P4: reconnect chain readback reply (own launch-monotonic range)
                let ok = (obj["error"] as? String) == "success"
                let data = obj["data"]
                let arrival = self?.pollEngine.noteArrival() ?? 0
                DispatchQueue.main.async { [weak self] in
                    self?.noteOsdChainReply(id: rid, ok: ok, data: data, arrival: arrival)
                }
            } else if let rid = obj["request_id"] as? Int, rid == 1122 {
                // P4: osd-dimensions subscribe ack (122+1000); an error marks the
                // property unavailable on this mpv build - landed bound always.
                let ok = (obj["error"] as? String) == "success"
                DispatchQueue.main.async { [weak self] in
                    if !ok { self?.osdDimsAvailable = false }
                }
            } else if obj["request_id"] != nil {
                self?.pollEngine.handleLine(obj)
            } else if let event = obj["event"] as? String {
                if event == "property-change" {
                    if obj["name"] as? String == "fullscreen", let fullscreen = obj["data"] as? Bool {
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            (NSApp.delegate as? AppDelegate)?.noteMPVFullscreen(fullscreen, from: self)
                        }
                    }
                    if obj["name"] as? String == "seeking", obj["data"] as? Bool == true {
                        DispatchQueue.main.async { [weak self] in self?.fenceCropMeasurementForSeek();self?.cropDetector.setMainPlaybackReady(false) }
                    }
                    if obj["name"] as? String == "user-data/gor/crop-packet-receipt" {
                        let receipt=obj["data"]
                        DispatchQueue.main.async { [weak self] in self?.noteCropPacketReceipt(receipt) }
                    }
                    if obj["name"] as? String == "user-data/gor/crop-epoch-state" {
                        let epochData=obj["data"],stamp=self?.cropPacketOpeningStamp ?? 0
                        DispatchQueue.main.async { [weak self] in self?.noteCropEpochRotation(epochData,stamp) }
                    }
                    if obj["name"] as? String == "user-data/vr180-look/film-frame" {
                        let frameData=obj["data"]
                        DispatchQueue.main.async { [weak self] in self?.noteFilmFrame(frameData) }
                    }
                    if obj["name"] as? String == "user-data/vr180-look/physical-gap-frac" {
                        let gapData = obj["data"]
                        DispatchQueue.main.async { [weak self] in self?.noteVrGapPublication(gapData) }
                    }
                    self?.pollEngine.handlePropertyChange(obj)
                } else {
                    if event == "start-file" { self?.pollEngine.purgeFileStateOnQueue() }
                    if event == "file-loaded" {self?.pollEngine.noteFileLoadedOnQueue()}
                    self?.handleMPVEvent(event, obj)
                }
            }
        }
        if !embeddedBackend {persistentConnection.start()}

        setupAutoHide()
        registerForDraggedTypes([.fileURL, .string])
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
        VariationBroadcaster.shared.startUpdates()

        cropDetector.onResult = { [weak self] rect, decisive, confidence in
            guard let self = self, !self.menuCropOwnsSelection else {return}
            var usableQueuedResult=false
            defer {self.finishQueuedManualCrop(terminal:confidence>=0,decisive:decisive,usable:usableQueuedResult)}
            guard CropAcceptPolicy.accepts(rect: rect, stereo: self.cropDetector.stereoSBS || self.cropDetector.perEyeAspect != nil, startPlayhead: CropScanGuard.shared.startPlayhead, nowPlayhead: self.currentTime, stream: CropDetector.isWTPlayback(self.currentFilePath), manual: self.manualRedetectInFlight) else {
                self.recoverRejectedAutomaticCrop(early:confidence<0,manual:self.manualRedetectInFlight)
                if confidence>=0 {self.manualRedetectInFlight=false}
                return
            }
            usableQueuedResult=decisive
            // Detector aspect is UI-only; original per-eye picture aspect is unchanged.
            let early = confidence < 0; let manual = self.manualRedetectInFlight; if decisive && !early { self.wtCropRetry[self.currentFilePath] = nil }; print("[cropdetect] result decisive=\(decisive) early=\(early) manual=\(manual) rect=\(String(describing: rect))")
            if !early { self.manualRedetectInFlight = false }   // an early apply must not end the manual/retry state before the final result
            // Weak measurements never move the picture; the file stays
            // unlocked and a later trigger re-measures.
            guard decisive else {
                print("[cropdetect] indecisive result — crop state unchanged"); var willRetry = false; if CropDetector.isWTPlayback(self.currentFilePath), self.isPlaying, (!manual || !self.cropSearchOwnsSelection) { let n = self.wtCropRetry[self.currentFilePath]?.n ?? 0; if self.wtCropRetry.index(forKey: self.currentFilePath) == nil, self.wtCropRetry.count >= 64, let old = self.wtCropRetry.min(by: { $0.value.t < $1.value.t })?.key { self.wtCropRetry.removeValue(forKey: old) }; self.wtCropRetry[self.currentFilePath] = (n + 1, ProcessInfo.processInfo.systemUptime, self.cropDetector.currentAutoDispatchFrontier() ?? self.lastSeekableEnd); willRetry = true; let scheduled = self.currentFilePath; let token=self.cropDetector.retryToken; let delay = Self.wtCropRetryDelay(attempt: n + 1); print("[cropdetect] search continues in \(Int(delay))s (attempt \(n + 1), scanned to \(Int(self.lastSeekableEnd))s)"); DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in guard let self, self.currentFilePath == scheduled else { return }; self.fireWTCropRetry(scheduled,token:token) } }
                if manual { self.showCropDetectOSD(CropDetector.isWTPlayback(self.currentFilePath) ? (willRetry ? "crop detect: not enough of the stream downloaded yet, retrying by itself" : "crop detect: not enough of the stream downloaded yet, try again") : "crop detect: no decision yet, file left unlocked") }
                return
            }
            if let rect = rect {
                if manual { self.showCropDetectOSD("crop detect: bars found, applying crop") }
                if self.cropRect == nil {
                    self.transitionCrop(.apply(rect), confidence: abs(confidence), manual: manual)
                } else {
                    self.transitionCrop(.reRect(rect), confidence: abs(confidence), manual: manual)
                }
            } else {
                if manual { self.showCropDetectOSD("crop detect: no bars") }
                self.transitionCrop(.revert, confidence: confidence, manual: manual)
            }
        }

        cropDetector.onStatus = { [weak self] status in
            guard let self = self else { return }
            (NSApp.delegate as? AppDelegate)?.setCropDetectMenuStatus(status)
            // On-screen text only for a manual redetect: automatic detection
            // works silently, but a clicked button must never look dead.
            if let status = status, self.manualRedetectInFlight {
                self.showCropDetectOSD("crop detect: \(status)")
            }
        }

        DispatchQueue.main.async {
            self.brightness.captureLaunchBrightnessIfUnsaved()
            print("💡 App launched, original brightness: \(Int(self.brightness.getCurrentBrightness() * 100))%")
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Window attachment

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if musicModeController == nil {
            let mmc = MusicModeController(
                hostView: self,
                sidebarUI: sidebarUI,
                spineUI: spineUI,
                ipcPath: ipcPath,
                ipcCommand: { [weak self] cmd in self?.ipcCommand(cmd) },
                getAppliedVideoFrame: { [weak self] in self?.appliedVideoFrame ?? .zero },
                setAppliedVideoFrame: { [weak self] f in self?.appliedVideoFrame = f },
                setAppliedVideoFrameWindowSize: { [weak self] s in self?.appliedVideoFrameWindowSize = s },
                setVideoDisplaySize: { [weak self] w, h in
                    self?.videoDisplayW = w
                    self?.videoDisplayH = h
                },
                markOpeningFitPending: { [weak self] fraction in
                    self?.mintOpeningFitOpen(fraction: fraction)
                }
            )
            mmc.setup()
            musicModeController = mmc
        }
        if vr180Controller == nil {
            vr180Controller = VR180Controller(
                ipcCommand: { [weak self] cmd in self?.ipcCommand(cmd) }
            )
            vr180Controller?.applyThreeDState(MainActor.assumeIsolated {ThreeDStore.shared.snapshot},[.present])
            vr180Controller?.onUITilt = { [weak self] roll in
                guard self?.vr180Controller?.usesLegacyPreviewChrome == true else{return}
                self?.setTrackedUITilt(roll)
            } // Normal2D/SBS consumes only the committed film-frame receipt.
            vr180Controller?.onSubtitleTilt = { [weak self] roll,pair in self?.subtitleView.setTrackedTilt(roll:roll,pairRoll:pair) }
            // The controller replays pending 3D routes itself (identity/geometry arrives late) and flips vrModeEnabled
            // without this class knowing; relayout the frame/HUD here. Skipped inside applyThreeDState, which does it.
            vr180Controller?.onVRModeApplied = { [weak self] enabled in
                guard let self, !self.applyingThreeDWrapper else {return}
                if !enabled {self.offReset();self.redetectCropAfter3DOff();return}
                self.menuCropOwnsSelection=false;self.stereoRestorePending=false;self.cropDetector.resetLastFile()
                self.startAutomaticCropDetection(needsRedetect:true)
                self.stereoGeometryKey="";self.refreshStereoMenuGeometry(force:true)
                self.appliedVideoFrame = .zero;self.appliedVideoFrameWindowSize = .zero;self.applyVideoFrame(bounds:self.bounds)
            }
            vr180Controller?.onExplorableSurface = { [weak self] in
                guard let self else {return}
                self.requestRealCrop(self.cropRect ?? CGRect(x:0,y:0,width:1,height:1))
            }
            setCameraPlaybackActive(cameraLoadedVideoActive,
                                    vrActive: cameraLoadedVideoActive && isPlaying && !cameraPauseIntentPending)
        }
        if iptvModeController == nil {
            let imc = IPTVModeController(
                hostView: self,
                spineUI: spineUI,
                ipcCommand: { [weak self] cmd in self?.ipcCommand(cmd) },
                batchIPC: { [weak self] batch in self?.batchIPC(batch) },
                closeMusicModeIfActive: { [weak self] in
                    if self?.musicModeController?.isMusicMode == true {
                        self?.musicModeController?.toggleMusicMode()
                    }
                },
                getAppliedVideoFrame: { [weak self] in self?.appliedVideoFrame ?? .zero },
                applyVideoFrame: { [weak self] bounds in self?.applyVideoFrame(bounds: bounds) },
                photonEnabled: { (NSApp.delegate as? AppDelegate)?.photonEnabled ?? false },
                applyIPTVProfile: { (NSApp.delegate as? AppDelegate)?.applyIPTVProfile() }
            )
            imc.setup()
            iptvModeController = imc
        }

        // Block185a: video-only rendering is owned by vr180-look, no overlay layer.

        if inputController == nil {
            inputController = InputController(
                view: self,
                ipcCommand: { [weak self] cmd in self?.ipcCommand(cmd) },
                wakeUI: { [weak self] in self?.wakeUI() },
                musicModeActive: { [weak self] in self?.musicModeController?.isMusicMode == true },
                iptvModeActive: { [weak self] in self?.iptvModeController?.isIptvMode == true },
                musicHitTest: { [weak self] pt in self?.musicModeController?.hitTest(pt) ?? false },
                iptvHitTest: { [weak self] pt in self?.iptvModeController?.hitTest(pt) ?? false },
                isShowingInputPanel: { (NSApp.delegate as? AppDelegate)?.isShowingInputPanel == true },
                spineAlpha: { [weak self] in self?.spineUI.alphaValue ?? 0 },
                updateVariationBroadcaster: { [weak self] locationInWindow in
                    guard let self = self,
                          let winPt = self.window?.contentView?.convert(locationInWindow, from: nil)
                    else { return }
                    VariationBroadcaster.shared.update(windowPt: winPt)
                },
                notifyBrightnessKeyChanged: { [weak self] in self?.brightness.notifyExternalBrightnessChange() },
                volume: { [weak self] in self?.volume ?? PPController.defaultVolume },
                setVolume: { [weak self] v in self?.setVolume(v) },
                seekRelative: { [weak self] s in self?.seekRelative(s) },
                simulateVolumeHover: { [weak self] in self?.spineUI.btnV.simulateHoverForKeyboard() },
                toggleRandomSubtitlePosition: { [weak self] in self?.subtitleView.toggleRandomMode() },
                moveSubtitleToDefaultPosition: { [weak self] n in self?.subtitleView.moveToDefaultPosition(n) },
                hitTest: { [weak self] pt in
                    guard let self = self else { return nil }
                    return self.hitTest(self.convert(pt, from: nil))
                },
                dismissActiveDropdown: { [weak self] in self?.spineUI.activeDropdown?.removeFromSuperview() },
                toggleFullScreenIfNotInPanel: { [weak self] in self?.playerViewStub.toggleFullScreen() },
                inSpineOrSidebar: { [weak self] pt in
                    guard let self = self else { return false }
                    return self.spineUI.frame.contains(pt) || self.sidebarUI.frame.contains(pt)
                },
                moveMpv: { dx, dy in (NSApp.delegate as? AppDelegate)?.moveMpv(dx: dx, dy: dy) },
                resetMpvPositionCache: { (NSApp.delegate as? AppDelegate)?.resetMpvPositionCache() }
            )
        }

        if !embeddedBackend,ContentAdaptiveDimming.featureFlagEnabled, contentAdaptiveDimming == nil {
            let cad = ContentAdaptiveDimming(
                hostView: self,
                setSceneTargetOverride: { [weak self] newOverride in self?.brightness.sceneTargetOverride = newOverride },
                setBrightness: { [weak self] value in
                    guard let self, self.brightness.permitsSceneBrightnessWrites else { return }
                    self.brightness.setBrightness(value)
                },
                getCurrentBrightness: { [weak self] in self?.brightness.getCurrentBrightness() ?? 1.0 },
                isBrightnessFading: { [weak self] in !(self?.brightness.permitsSceneBrightnessWrites ?? false) },
                writeSceneStateToMPV: { [weak self] backlight, inertiaMode, isCut, ambientLevel, ambientSource, ambientRegions, ambientLux in
                    guard let self else { return }
                    let ambientJSON = ambientLevel.map { String($0) } ?? "null"
                    let ambientFaceJSON = ambientRegions.map { String($0.face) } ?? "null"
                    let ambientRoomJSON = ambientRegions.map { String($0.room) } ?? "null"
                    let ambientLuxJSON = ambientLux.map { String($0) } ?? "null"
                    self.batchIPC("""
                        {"command":["set_property","user-data/adaptive-brightness-backlight",\(backlight)]}
                        {"command":["set_property","user-data/adaptive-brightness-inertia-mode","\(inertiaMode)"]}
                        {"command":["set_property","user-data/adaptive-brightness-is-cut",\(isCut)]}
                        {"command":["set_property","user-data/adaptive-brightness-ambient-level",\(ambientJSON)]}
                        {"command":["set_property","user-data/adaptive-brightness-ambient-source","\(ambientSource)"]}
                        {"command":["set_property","user-data/adaptive-brightness-ambient-face",\(ambientFaceJSON)]}
                        {"command":["set_property","user-data/adaptive-brightness-ambient-room",\(ambientRoomJSON)]}
                        {"command":["set_property","user-data/adaptive-brightness-ambient-lux",\(ambientLuxJSON)]}
                        """)
                },
                setAmbientWindowOpen: { [weak self] isOpen in
                    self?.ipcCommand("""
                        {"command":["set_property","user-data/adaptive-brightness-ambient-window-open",\(isOpen)]}
                        """)
                }
            )
            cad.setup()
            contentAdaptiveDimming = cad
            setCameraPlaybackActive(cameraLoadedVideoActive,
                                    vrActive: cameraLoadedVideoActive && isPlaying && !cameraPauseIntentPending)
            if !ambientPlaybackFileEnded { synchronizeLoadedVideoCamera() }
            onVideoFrameApplied = { [weak cad] bounds, displayRect, target in
                cad?.handleVideoFrame(bounds, displayRect, target)
            }
        }

        FilmPrepareOSD.shared.start { [weak self] t in self?.showCropDetectOSD(t) }; cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkCursorHide()
            self?.refreshVRControlMirrorsFromTimer()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidExitFullScreen),
            name: NSWindow.didExitFullScreenNotification, object: window
        )

        dragDropHandler = DragDropHandler(
            window: window,
            stopTorrent: { (NSApp.delegate as? AppDelegate)?.stopTorrent() },
            streamTorrent: { (NSApp.delegate as? AppDelegate)?.streamTorrent($0) },
            openMediaFile: { [weak self] path in self?.openMediaFile(path) },
            photonEnabled: { (NSApp.delegate as? AppDelegate)?.photonEnabled ?? false },
            ipcCommand: { [weak self] cmd in self?.ipcCommand(cmd) },
            batchIPC: { [weak self] batch in self?.batchIPC(batch) }
        )
        dragDropHandler?.start()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        checkCursorHide()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        if cursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            cursorHidden = false
        }
    }

    @objc private func windowDidExitFullScreen(_ notification: Notification) {
        iptvModeController?.handleFullScreenExit()
    }

    // MARK: - Build

    private func build() {
        spineUI.playerView   = playerViewStub
        sidebarUI.playerView = playerViewStub

        spineUI.onIPC = { [weak self] json in
            self?.ipcCommand(json)
        }

        spineUI.getTrackList = { [weak self] type, completion in
            self?.fetchTrackList(type: type, completion: completion)
        }

        spineUI.onSubVisibilityChanged = { [weak self] visible in
            self?.subtitleView.isHidden = !visible
        }

        LiveCaptionController.shared.onCaption = { [weak self] text, duration, _ in
            guard let self = self else { return }
            self.subtitleView.show(text: text, duration: duration, at: self.currentTime)
            self.spineUI.pulseLiveCaptionBullet()
        }

        LiveCaptionController.shared.onFailure = { [weak self] message in
            print("[LiveCaption] ❌ \(message)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                SubtitleView.Config.liveCaptionActive = false
                self.spineUI.forceLiveCaptionOff()
                self.spineUI.showMPVOSD("live caption: " + message)
            }
        }

        spineUI.onSearchOpenSubtitles = { [weak self] langCode in
            guard let self = self, !self.currentFilePath.isEmpty else { return }
            // Invalidate an older src click before the FPS query so a slow
            // query cannot let its earlier search win a same-file race.
            self.subtitleView.invalidateSubtitleLookup()
            let path = self.currentFilePath
            let title = self.lastMediaTitle.isEmpty ? nil : self.lastMediaTitle
            let client = self.ipcClient
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let response = IPCClient.parseFirst(client.queryBatch(
                    #"{"command":["get_property","container-fps"]}"#))
                let rawFPS = (response["data"] as? NSNumber)?.doubleValue
                let fps = rawFPS.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentFilePath == path else { return }
                    self.subtitleView.loadSubtitleFromOpenSubtitles(
                        filePath: path, language: langCode, silent: false,
                        mediaTitle: title, videoFPS: fps)
                }
            }
        }

        spineUI.onFoldToggle = { [weak self] section in
            guard let self = self, !section.isEmpty else { return }

            let toggleTarget: [String: (script: String, msg: String)] = [
                "photon":  ("photon",         "photon-toggle"),
                "bright":  ("photon",         "photon-bright-toggle"),
                "sharp":   ("photon_sharp",   "photon-sharp-toggle"),
                "grain":   ("photon_grain",   "photon-grain-toggle"),
                "chrome":  ("photon_chrome",  "photon-chrome-toggle"),
                "negativ": ("photon_negativ", "photon-negativ-toggle")
            ]
            var batch = "{\"command\":[\"script-message-to\",\"photon_hud\",\"photon-hud-toggle-fold\",\"\(section)\"]}"
            if let t = toggleTarget[section] {
                batch += "\n{\"command\":[\"script-message-to\",\"\(t.script)\",\"\(t.msg)\"]}"
            }
            self.batchIPC(batch)
        }

        spineUI.onToggleLiveCaption = { [weak self] languageCode in
            self?.toggleLiveCaption(languageCode: languageCode) ?? false
        }

        spineUI.currentLiveCaptionModel = LiveCaptionController.shared.modelName
        spineUI.onSelectLiveCaptionModel = { modelName in
            LiveCaptionController.shared.modelName = modelName
        }

        subtitleView.onSubtitleSearchStatus = { [weak self] status in
            self?.spineUI.showSubtitleSearchStatus(status)
        }
        spineUI.currentSubtitleSearchStatus = { [weak self] in
            self?.subtitleView.subtitleSearchStatus
        }
        spineUI.canExportSrcSubtitle = { [weak self] in
            self?.subtitleView.canExportSrcSubtitle ?? false
        }
        spineUI.onExportSrcSubtitle = { [weak self] in
            self?.subtitleView.exportSrcSubtitle()
        }

        // 180d: stereo chrome replicator for superview-coordinate chrome
        // (photon HUD / mpv OSD / scroll indicator). zPosition keeps it above
        // the mpv video layer, which is added to this layer later.
        vrChromeContainer.anchorPoint = .zero // Origin-based shared subtitle transform.
        vrChromeReplicator.instanceCount = 1
        vrChromeReplicator.zPosition = 10_000
        vrChromeReplicator.addSublayer(vrChromeContainer)
        layer?.addSublayer(vrChromeReplicator)
        spineUI.vrParentChromeContainer = vrChromeContainer

        [subtitleView, spineUI, sidebarUI].forEach {
            $0.frame = bounds
            $0.autoresizingMask = [.width, .height]
            addSubview($0)
            $0.layer?.zPosition=2
        }

        LayoutEngine.shared.addObserver { [weak self] in
            guard let self = self else { return }
            self.appliedVideoFrame = .zero
            self.applyVideoFrame(bounds: self.bounds)
        }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        ))

        setupAdaptiveColor()
    }

    @discardableResult
    private func refuseEmbedded(_ control:String)->Bool {
        guard embeddedBackend else {return false}
        spineUI.showMPVOSD("gorav unavailable: "+control,force:true)
        print("[engine] backend=gorav refusal=unsupported-control control=\(control)")
        return true
    }
    /// Cross-file menu dispatch without exposing backend ownership. nil means
    /// native mpv owns the command; false is an embedded refusal, not fallback.
    func applyEmbeddedSubtitlePositionPreset(_ pos:Int)->Bool? {
        guard embeddedBackend else{return nil}
        return applyEmbeddedSubtitlePosition(Double(pos))
    }
    /// Actual embedded observations update the existing chrome. No mpv-shaped
    /// synthetic property dictionary or stale mpv poll can overwrite this state.
    func acceptEmbeddedVolume(_ accepted: Float) {
        guard embeddedBackend, accepted.isFinite, accepted >= 0, accepted <= 1 else { return }
        volume = accepted
        sidebarUI.update(currentTime:currentTime,duration:duration,progress:currentProgress(),volume:volume)
    }
    func acceptEmbedded(_ state:EngineObservedState,source:URL?) {
        guard embeddedBackend else {return}
        if let source,source.path != currentFilePath {
            dropCropPacketIntent();cropDetector.cancel();cropDetector.resetLastFile();cancelCropMotion()
            currentFilePath=source.path
            lastSeekableEnd=0;lastVideoTrackID=0
            cropRect=nil;cropPresentationRect=Self.fullSourceCrop;menuCropOwnsSelection=false
            manualMenuCropAspect=nil;manualRedetectInFlight=false;windowRefitAnchorFrame=nil
            sourceCropPropertyRequested=false;sourceCropPropertyActive=false
            videoDisplayW=0;videoDisplayH=0
            _=embeddedSourceCrop?(source.path,Self.fullSourceCrop)
            spineUI.setTitle(source.lastPathComponent)
            subtitleView.setFilePath(source.path)
        }
        if let time=state.timePos,time.isFinite {currentTime=time}
        if let seconds=state.duration,seconds.isFinite {duration=seconds}
        if let paused=state.paused {isPlaying = !paused;subtitleView.playbackPaused=paused;spineUI.updatePlayPauseState(isPlaying:!paused)}
        if let w=state.displayWidth,let h=state.displayHeight,w>0,h>0 {
            videoDisplayW=w;videoDisplayH=h;nativeVideoAspect=w/h;videoLayoutAspect=w/h
        }
        if videoDisplayW>0,videoDisplayH>0 {startAutomaticCropDetection()}
        sidebarUI.update(currentTime:currentTime,duration:duration,progress:currentProgress(),volume:volume)
    }
    func showEngineRoute(_ line:String) {spineUI.showMPVOSD(line,force:true)}

    // MARK: - IPC polling
    
    func startPolling() {
        inputController?.startKeyboardMonitor()
        inputController?.startBrightnessKeyMonitor()
        window?.makeFirstResponder(self)

        guard !embeddedBackend else {return}
        pollEngine.onLayoutInvalidated = { [weak self] in self?.invalidateOpeningLayout() }
        pollEngine.onResults = { [weak self] results, meta in
            self?.handlePollResults(results, meta: meta)
        }
        // G4: publish every flush to the engine-neutral observation surface
        // (G5 control bus / G6 presentation receipt consume it there).
        pollEngine.onObservation = { state, _ in
            EngineObservationCenter.shared.ingest(state)
        }
        pollEngine.start()
        startTestScrollHarness()
    }

    // MARK: - Geometry test harness (GOR_TRACE_GEOM=1 only)

    private var testScrollHarnessGeneration: UInt64 = 0

    /// Test-only geometry drives (GOR_TRACE_GEOM=1 only): while the trace is
    /// on, poll user-data properties and apply each new value through the
    /// real code paths. Lets the self-test exercise these without
    /// synthesizing AppKit events; inert in normal runs.
    ///   gor-test-hud-scroll: whole-row HUD scroll delta (the wheel path's
    ///     clamp/layout), each new nonzero value consumed once.
    ///   gor-test-vr-mode: 0/1 VR toggle through setVRModeEnabled (180d).
    ///   gor-test-vr-sub-dial: absolute subtitle depth in points through
    ///     VR180Controller.setSubtitleDepth (>=0) or pref removal (-1), for
    ///     magnitude and snapshot/restore (180d/181.2).
    ///   gor-test-vr-key: a key spec like "shift-alt-]" driven as a REAL
    ///     NSEvent through the app's own key monitor, so the ipd-vs-dial
    ///     isolation leg exercises the actual modifier-mask routing (181.2).
    private func startTestScrollHarness() {
        guard GeomTrace.on, ProcessInfo.processInfo.environment["GOR_TEST_VR_CONTROL"] == "1" else { return }
        testScrollHarnessGeneration &+= 1
        let generation = testScrollHarnessGeneration
        let client = ipcClient
        // Rest snapshot: the selftest restores the user's actual pref state
        // (including its absence) after exercising the dial.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let dial = ThreeDSubtitleDepth.dial(self.vr180Controller?.subtitleDepthPoints ?? VR180Controller.subtitleDepthDefault)
            let signed = dial * (self.swapEyes ? -1 : 1)
            let had = self.vr180Controller?.hasSubtitleDepthPref ?? false
            GeomTrace.log("vrSubDepth", String(format: #"{"k":"vrSubDepth","dial":%.1f,"offset":%.1f,"swap":%d,"had":%d}"#,
                dial, signed, self.swapEyes ? 1 : 0, had ? 1 : 0))
            self.vr180Controller?.snapshotIPDForTest()   // exact saved-preference snapshot (presence + value)
            GeomTrace.log("vrIPD", String(format: #"{"k":"vrIPD","v":%.17g}"#, (self.vr180Controller?.testCurrentBaseIPD ?? 0)))
            GeomTrace.log("vrMode", String(format: #"{"k":"vrMode","on":%d}"#, self.vrModeEnabled ? 1 : 0))
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Test-owned only: one bounded socket roundtrip for all requests, rather than seven
            // serial receive timeouts. Missing/error replies remain unknown, never a successful zero.
            let requests: [(String, Int)] = [("vr180-look/distance-trace",9310),("gor-test-hud-scroll",9301),
                ("gor-test-vr-mode",9302),("gor-test-vr-sub-dial",9303),("gor-test-vr-ipd-restore",9306),("gor-test-vr-key",9305)]
            var replies: [Int: [String:Any]] = [:]
            var lastPollStatus = ""
            func refreshTestReplies() {
                let payload = requests.map { prop, rid in
                    String(format: #"{"command":["get_property","user-data/%@"],"request_id":%d}"#, prop,rid)
                }.joined(separator:"\n") + "\n"
                replies = [:]
                for line in client.queryBatch(payload,timeout:0.6) {
                    guard let data=line.data(using:.utf8),
                          let reply=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                          let rid=reply["request_id"] as? Int, requests.contains(where:{$0.1==rid}) else {continue}
                    replies[rid]=reply
                }
                let states=requests.map { prop,rid in "\(rid):\(replies[rid]?["error"] as? String ?? "timeout/noReply")" }.joined(separator:",")
                if states != lastPollStatus {
                    lastPollStatus = states
                    GeomTrace.log("testPoll", "{\"k\":\"testPoll\",\"status\":\"\(states)\"}")
                }
            }
            func poll(_ prop: String, _ rid: Int) -> Double? {
                guard replies[rid]?["error"] as? String == "success" else {return nil}
                return replies[rid]?["data"] as? Double
            }
            func pollString(_ prop: String, _ rid: Int) -> String? {
                guard replies[rid]?["error"] as? String == "success" else {return nil}
                return replies[rid]?["data"] as? String
            }
            var lastRows: Double = 0
            var haveLast = false
            var lastVRMode: Double = 0
            var lastDial: Double = -2   // -1 is meaningful (clear pref)
            var lastKey: String = ""
            var lastRestoreIPD: Double?
            var lastDistanceTrace = ""
            while true {
                Thread.sleep(forTimeInterval: 0.4)
                guard let self, self.testScrollHarnessGeneration == generation else { return }
                refreshTestReplies()
                // Distance geometry (block 182 2): the values come from vr180-look.lua's own computation
                // (d, s_today/s_cap/s_total, offset, capped, infeasible, reason) read back as is; Swift does
                // not repeat the clamp math.
                if let tr = pollString("vr180-look/distance-trace", 9310), tr != lastDistanceTrace, tr.hasPrefix("{") {
                    lastDistanceTrace = tr
                    GeomTrace.log("vrDistance", tr)
                }
                // Keep this test-owned VR session's actual controls visible for pixel evidence. Normal runs
                // never enter this GeomTrace-gated harness; no camera or persistent UI preference is changed.
                if lastVRMode == 1 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        self.wakeUI()
                    }
                }
                if let neutral = poll("gor-test-hud-scroll", 9301), neutral == 0, haveLast {
                    haveLast = false
                    GeomTrace.log("hudScrollDrive", "{\"k\":\"hudScrollDrive\",\"v\":0}")
                }
                if let rows = poll("gor-test-hud-scroll", 9301),
                   rows != 0, rows == rows.rounded(), abs(rows) < 1000,
                   !(haveLast && rows == lastRows) {
                    haveLast = true; lastRows = rows
                    let rowDelta = Int(rows)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        GeomTrace.log("hudScrollDrive", "{\"k\":\"hudScrollDrive\",\"v\":\(rowDelta)}")
                        self.spineUI.drivePhotonHUDScrollForTest(rows: rowDelta)
                    }
                }
                if let mode = poll("gor-test-vr-mode", 9302), mode != lastVRMode {
                    lastVRMode = mode
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        ThreeDStore.shared.dispatch(.setOutput(mode == 1 ? .vr180 : .off))   // 191b-T: test hook folded into the store; the direct setVRModeEnabled bypass is deleted
                        if mode == 1 { self.wakeUI() }
                    }
                }
                if let dial = poll("gor-test-vr-sub-dial", 9303), dial >= -1, dial != lastDial {
                    lastDial = dial
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        if dial < 0 {
                            self.vr180Controller?.clearSubtitleDepth()
                        } else {
                            self.vr180Controller?.setSubtitleDepth(dial)
                        }
                        self.applySubtitleDepthOffset()
                    }
                }
                // Absolute cleanup only; key routing is tested independently.
                if let value = poll("gor-test-vr-ipd-restore", 9306), value.isFinite,
                   abs(value) <= VR180Controller.baseIPDLimit, value != lastRestoreIPD {
                    lastRestoreIPD = value
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        self.vr180Controller?.restoreBaseIPDForTest(value)
                    }
                }
                if let key = pollString("gor-test-vr-key", 9305), !key.isEmpty, key != lastKey {
                    lastKey = key
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.testScrollHarnessGeneration == generation else { return }
                        self.sendTestKey(key)
                    }
                }
            }
        }
    }

    /// 181.2 review: drive a REAL NSEvent through the app's own local key
    /// monitor (the actual modifier-mask routing), not the setter functions.
    /// Spec form: "shift-alt-]" - dash-separated modifiers then [ or ].
    /// Test-only (harness callers are GOR_TRACE_GEOM-gated).
    private func sendTestKey(_ spec: String) {
        guard GeomTrace.on else { return }
        var flags: NSEvent.ModifierFlags = []
        var rest = spec
        while true {
            if rest.hasPrefix("shift-") { flags.insert(.shift); rest.removeFirst(6) }
            else if rest.hasPrefix("alt-") { flags.insert(.option); rest.removeFirst(4) }
            else { break }
        }
        let keyCode: UInt16 = rest == "[" ? 33 : rest == "]" ? 30 : 0xFFFF
        // The real key window's number + a point inside this view, so window
        // routing and the monitor's focus checks behave natively; the event
        // then goes through NSApp.sendEvent into the app's own local monitor.
        let winNum = window?.windowNumber ?? 0
        let loc = window.map { $0.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)) } ?? .zero
        guard keyCode != 0xFFFF,
              let event = NSEvent.keyEvent(with: .keyDown, location: loc, modifierFlags: flags,
                                           timestamp: 0, windowNumber: winNum, context: nil,
                                           characters: rest, charactersIgnoringModifiers: rest,
                                           isARepeat: false, keyCode: keyCode) else { return }
        NSApp.sendEvent(event)
    }

    // MARK: - Poll result handling

    private var cameraPlaybackShutDown = false
    private var ambientPlaybackFileEnded = false
    private var cameraPauseIntentPending = false
    private var cameraLoadedVideoActive = false
    private var cameraFileGeneration: UInt64 = 0

    private func setCameraPlaybackActive(_ active: Bool, vrActive: Bool = false) {
        cameraLoadedVideoActive = active && !cameraPlaybackShutDown
        contentAdaptiveDimming?.playbackActive = cameraLoadedVideoActive
        vr180Controller?.playbackActive = vrActive && !cameraPlaybackShutDown
        vr180Controller?.loadedVideoActive = cameraLoadedVideoActive
    }

    func shutDownPlaybackCamera() {
        cameraFileGeneration &+= 1
        cameraPlaybackShutDown = true
        setCameraPlaybackActive(false)
    }

    func suspendPlaybackCamera() {
        // Sleep retires this controller; the fresh wake controller has no quit latch.
        cameraFileGeneration &+= 1
        ambientPlaybackFileEnded = true
        setCameraPlaybackActive(false)
    }

    private func updateAmbientPlaybackGate(_ results: [String: Any]) {
        let path = results["path"] as? String ?? ""
        if results["pause"] as? Bool == true { cameraPauseIntentPending = false }
        // A loaded audio-only file is not camera authority. Selected video identity
        // comes from mpv, not a cached display size or the pause flag.
        let selectedVideoID = results["current-tracks/video/id"] as? Int ?? 0
        let movingVideo = selectedVideoID > 0 &&
            results["current-tracks/video/albumart"] as? Bool == false &&
            results["current-tracks/video/image"] as? Bool == false
        let active = movingVideo && !path.isEmpty &&
            results["idle-active"] as? Bool == false && !ambientPlaybackFileEnded && !isTorrentStopped
        setCameraPlaybackActive(active, vrActive: active && results["pause"] as? Bool == false &&
                                !cameraPauseIntentPending)
    }

    private func synchronizeLoadedVideoCamera() {
        let generation = cameraFileGeneration
        let client = ipcClient
        let payload = ["path", "idle-active", "current-tracks/video/id", "pause",
                       "user-data/adaptive-brightness-enabled", "current-tracks/video/albumart",
                       "current-tracks/video/image"].enumerated().map { index, key in
            "{\"command\":[\"get_property\",\"\(key)\"],\"request_id\":\(7100 + index)}"
        }.joined(separator: "\n")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let lines = client.queryBatch(payload, timeout: 0.8)
            var snapshot: [String: Any] = [:]
            let keys = ["path", "idle-active", "current-tracks/video/id", "pause",
                        "user-data/adaptive-brightness-enabled", "current-tracks/video/albumart",
                        "current-tracks/video/image"]
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      reply["error"] as? String == "success",
                      let id = reply["request_id"] as? Int, (7100..<7107).contains(id),
                      let value = reply["data"], !(value is NSNull) else { continue }
                snapshot[keys[id - 7100]] = value
            }
            let result = snapshot
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.cameraFileGeneration,
                      !self.cameraPlaybackShutDown, !self.ambientPlaybackFileEnded else { return }
                self.updateAmbientPlaybackGate(result)
                if let enabled = result["user-data/adaptive-brightness-enabled"] as? Bool {
                    self.contentAdaptiveDimming?.runtimeEnabled = enabled
                }
            }
        }
    }

    private var lastEOF = false
    private var eofPath: String?

    /// Owner-log 260918: the process tap died and delivered digital zero for
    /// 330+s of confirmed advancing playback (subtitle/SpineUI fonts flat), and
    /// the post-seek rebuffer froze mpv on a black frame for 153s while the
    /// dimming read it as a dark scene and dragged brightness down. Both fixes
    /// key off one signal computed here from the 200ms poll: is the playhead
    /// actually advancing, and is playback audible.
    private func updatePlaybackLiveness(timePos t: Double, results: [String: Any]) {
        let now = ProcessInfo.processInfo.systemUptime
        if livenessLastTimePos.map({ abs(t - $0) > 0.05 }) ?? true {
            livenessLastAdvanceAt = now
        }
        livenessLastTimePos = t
        let paused = results["pause"] as? Bool ?? true
        let secondsSinceAdvance = now - livenessLastAdvanceAt

        // Item 2: hold the dimming off frozen seek/rebuffer frames.
        let seeking = results["seeking"] as? Bool ?? false
        let ended = wtPlaybackEnded || (results["eof-reached"] as? Bool ?? false)
        let stalled = Self.computePlaybackStalled(paused: paused, seeking: seeking,
                                                  ended: ended, duration: duration,
                                                  secondsSinceAdvance: secondsSinceAdvance)
        if stalled != playbackStalled {
            playbackStalled = stalled
            if #available(macOS 12.0, *) {
                contentAdaptiveDimming?.playbackStalled = stalled
            }
        }

        // Item 1: independent proof that mpv is audibly advancing. The tap's
        // zero-content diagnostic could never distinguish a dead tap from a
        // quiet passage on sample content alone; this signal is the missing
        // liveness proof. ~1Hz is ample against SCE's 3s freshness window.
        let muted = results["mute"] as? Bool ?? false
        let vol = results["volume"] as? Double ?? 100
        let audibleAdvancing = !paused && !muted && vol > 0 && secondsSinceAdvance < 0.5
        if audibleAdvancing, now - livenessLastNoteAt >= 1.0 {
            livenessLastNoteAt = now
            ScreenCaptureEngine.shared.notePlaybackLiveness()
        }
    }

    /// Dimensions can precede file-loaded/playback-restart. Never bind a WT
    /// capture to that absent/old playback lifetime. Decoded restart also calls
    /// this helper, even when the dimensions have not changed since the poll.
    /// Heat: a hot machine keeps the booked WT retry but does not run its heavy
    /// scan pass while thermal pressure is serious+ (owner 95C report 2026-11-15:
    /// two utility threads pegged decoding a streamed DVD title, retry every 45 s).
    /// The same 45 s timer re-arms without charging the per-file budget again (it
    /// was charged once at scheduling) until the box cools, then the auto path runs.
    /// 199az: a pending no-crop search restarts immediately on seek, resolution/aspect change, track
    /// switch and cache growth past the scanned range, with a fresh +2/+5/+10/30s cadence. The reset
    /// covers a search armed for retry AND a scan in flight (entry still nil on the first scan): the
    /// cancel bumps the retry generation, so the old scan's delayed completion dies on its token
    /// guard. A settled crop and a locked manual crop are untouched.
    /// Pure growth decision for the pending crop search, same coordinate on both sides: raw cache
    /// frontier end vs the dispatch-recorded raw frontier end. Extracted verbatim into the Swift
    /// qualification harness; the unchanged-cache negative control must return false.
    static func cropSearchGrowthRestarts(frontierEnd: Double, scannedEnd: Double) -> Bool {
        frontierEnd > scannedEnd + 2
    }

    private func restartPendingWTCropSearch(_ why: String) {
        guard !currentFilePath.isEmpty, CropDetector.isWTPlayback(currentFilePath),
              wtCropRetry[currentFilePath] != nil || cropDetector.isPending, !cropSearchOwnsSelection,
              !menuCropOwnsSelection else { return }
        // Owner 2m50s crop report: a buffer-growth restart must not cancel a running scan or reset its
        // retry count. The pending scan's own result re-fires the search with the grown range
        // (startAutomaticCropDetection computes positions from the current ranges at fire time),
        // so progress continues without the cancel/restart churn.
        if cropDetector.isPending { print("[cropdetect] buffer-growth restart skipped: scan already pending (\(why))"); return }
        print("[cropdetect] restarting the crop search (\(why))")
        // Owner 2m50s crop report: a buffer-growth restart must not reset the retry backoff to
        // attempt 1 (the 199az "restart at once on cache growth" intent is the immediate rescan,
        // not erasing the retry count). The entry is kept so the next indecisive result backs off
        // 2/5/10/30s as designed instead of rescanning every 2s.
        cropDetector.cancel(); cropDetector.resetLastFile()
        startAutomaticCropDetection(needsRedetect: true)
    }
    private func fireWTCropRetry(_ scheduled: String,token:Int) {
        guard currentFilePath==scheduled,cropDetector.retryToken==token,!menuCropOwnsSelection,!cropDetector.isPending else{return}
        if !isPlaying { print("[cropdetect] retry re-armed: playback paused, no scan"); DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in guard let self, self.currentFilePath == scheduled else { return }; self.fireWTCropRetry(scheduled,token:token) }; return }
        if HeatTelemetry.thermalPressure { print("[cropdetect] retry deferred: thermal pressure"); DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in guard let self, self.currentFilePath == scheduled else { return }; self.fireWTCropRetry(scheduled,token:token) }; return }
        self.startAutomaticCropDetection(needsRedetect:true)
    }
    private var cropSearchWake:UInt64=0
    private var cropSearchWakePending=false
    private func maintainAutomaticCropSearch(_ attempt:Int=0) {
        guard !presentationIsQuitting,!cropDetectionStopped,!currentFilePath.isEmpty,
              CropDetector.isWTPlayback(currentFilePath),!menuCropOwnsSelection else{return}
        guard !cropSearchWakePending else{return}
        cropSearchWakePending=true
        let ticket=cropSearchWake,path=currentFilePath,opening=cropSourceOpening
        DispatchQueue.main.asyncAfter(deadline:.now()+Self.wtCropRetryDelay(attempt:attempt+1)) { [weak self] in
            guard let self,self.cropSearchWake==ticket,self.currentFilePath==path,self.cropSourceOpening==opening else{return}
            self.cropSearchWakePending=false
            guard !self.presentationIsQuitting,!self.cropDetectionStopped,!self.menuCropOwnsSelection else{return}
            if let accepted=self.commandAcceptedCropRect,accepted != Self.fullSourceCrop {return}
            self.maintainAutomaticCropSearch(min(attempt+1,3))
            if self.isPlaying,!HeatTelemetry.thermalPressure,!self.cropDetector.isPending {
                self.cropDetector.resetLastFile()
                self.startAutomaticCropDetection(needsRedetect:true)
            }
        }
    }
    private func startAutomaticCropDetection(needsRedetect: Bool = false) {
        guard !presentationIsQuitting,!cropDetectionStopped else{return}
        maintainAutomaticCropSearch()
        if embeddedBackend && embeddedSourceCrop == nil {return}
        guard !mediaTransitionPending else {return}
        refreshCropSourcePacking()
        guard !menuCropOwnsSelection, !currentFilePath.isEmpty,
              (!currentFilePath.hasPrefix("http://localhost") || CropDetector.isWTPlayback(currentFilePath)),
              videoDisplayW > 0, videoDisplayH > 0,
              !cropDetector.isPending, !cropSearchOwnsSelection || needsRedetect || cropPackingNeedsRedetect else { return }
        if CropDetector.isWTPlayback(currentFilePath), !cropDetector.isMainPlaybackReady() { return }
        cropPackingNeedsRedetect=false
        print("[cropdetect] dimensions ready \(Int(videoDisplayW))x\(Int(videoDisplayH)) — triggering"); CropScanGuard.shared.begin(playhead: currentTime)
        cropDetector.detect(filePath: currentFilePath, videoW: videoDisplayW,
                            videoH: videoDisplayH, fallbackDuration: duration)
    }

    /// Pure stall decision, Linux-harness tested. Stall = not paused, not
    /// ended, finite-duration file (excludes live/IPTV, whose time-pos does
    /// not advance reliably), and mpv mid-seek or playhead frozen. Paused
    /// seeks and paused/EOF frames are deliberately NOT stalls: sampling the
    /// frame the user is looking at stays intentional there.
    static func computePlaybackStalled(paused: Bool, seeking: Bool, ended: Bool,
                                       duration: Double, secondsSinceAdvance: Double) -> Bool {
        guard !paused, !ended, duration.isFinite, duration > 0 else { return false }
        if seeking { return true }
        return secondsSinceAdvance >= 2.5
    }

    // TRAP-06: IPTV title comes from iptvChannelTitle, never media-title.
    private func handlePollResults(_ results: [String: Any], meta: PollEngine.Meta) {
        // P4: a (re)connect invalidates every retained margin (ipc.rst: a closed
        // connection unregisters observations; values re-anchor via fresh
        // initial deliveries) and re-reads the filter chain once, read-only.
        if meta.connGen != lastSeenConnGen {
            lastSeenConnGen = meta.connGen
            filmFrameSequenceFloor.removeAll()
            osdFilterUncertain = true
            osdMutationGen &+= 1
            latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
            sendOsdChainQuery()
        }
        // Gate before checkpoints/runtimeEnabled can schedule any camera work.
        updateAmbientPlaybackGate(results)
        let path = results["path"] as? String
        if path != eofPath {
            eofPath = path; lastEOF = false
            if let app = NSApp.delegate as? AppDelegate {
                app.magnetEpisodeTracker.noteMediaStarted(path: path, startedSource: app.lastMagnetURL)
            }
        }
        if let d = results["duration"] as? Double {
            duration = d; ThreeDFilmInfo.shared.set(path: path, fps: (results["container-fps"] as? NSNumber)?.doubleValue, frames: (results["estimated-frame-count"] as? NSNumber)?.intValue)
        }

        if let path = results["path"] as? String, let token = Self.wtPlaybackToken(path) {
            if token != wtObservedToken {
                wtObservedToken = token
                wtPlaybackEnded = false
                wtUserPauseIntent = false
                wtLastPosition = nil
                wtLastDuration = nil
                wtLastPositionAt = nil
                lastSentPlayheadAt = .distantPast
                lastSentPlayhead = -999
            }
            if let t = results["time-pos"] as? Double, t.isFinite {
                wtLastPosition = t
                wtLastPositionAt = ProcessInfo.processInfo.systemUptime
            }
            if let d = results["duration"] as? Double, d.isFinite, d > 0 { wtLastDuration = d }
        }
        if let t = results["time-pos"] as? Double {
            currentTime = t
            sendPlayheadToWTServer(t, duration: duration, mediaPath: results["path"] as? String)
            if #available(macOS 12.0, *) {
                contentAdaptiveDimming?.checkAmbientCheckpoints(currentTime: t, duration: duration)
            }
            updatePlaybackLiveness(timePos: t, results: results)
        }

        if results["eof-reached"] as? Bool == true, !lastEOF, !wtPlaybackEnded, wtObservedToken != nil {
            wtPlaybackEnded = true
            sendWTPlaybackEvent("eof")
        }
        if let p = results["pause"] as? Bool {
            // SubtitleView freezes fade/weight animation while paused. Set on
            // every observation (its didSet dedupes) so a missed edge or a
            // stale self-derived value can't wedge it.
            subtitleView.playbackPaused = p; SubtitleSampleGovernor.shared.paused = p
            let playing = !p
            if playing != isPlaying {
                isPlaying = playing
                brightness.updateForPlayback(isPlaying: playing)
                spineUI.updatePlayPauseState(isPlaying: playing)
                sendPauseStateToWTServer(isPlaying: playing)
                if !playing {
                    if #available(macOS 12.0, *) {
                        contentAdaptiveDimming?.handlePlaybackPaused()
                    }
                }
            }
        }
        
        let eof = results["eof-reached"] as? Bool ?? false
        if eof && !lastEOF {
            // A magnet pick that played to its end arms the next-episode prefill.
            if let app = NSApp.delegate as? AppDelegate {
                app.magnetEpisodeTracker.notePlaybackFinished(path: path)
            }
            if currentTime < 5.0 {
                iptvModeController?.handlePollEOF(currentTime: currentTime)
            }
        }
        lastEOF = eof

        if let vol = results["volume"] as? Double {
            let newVol = Float(vol / 100)
            if newVol != volume {
                volume = newVol
                spineUI.updateVolume(newVol)
            }
        }

        if let p = results["path"] as? String, !p.isEmpty, p != currentFilePath {
            currentFilePath   = p
            setFilmFrameIdentity(p)
            // gor 514: mint this path's open identity; its dims arrivals
            // and its first file-loaded share it (at most one apply).
            mintOpeningFitOpen(fraction: GorVideoFit.openBaselineFraction)
            pushFitMetrics()   // screen for the NEXT open (this one was sized from the previous push)
            openingFitAwaitingFirstLoad = true
            openingFitSawEndFile = false
            openingFitNonBaselineApplied = false
            // New file: playhead identity resets; a stale stall must not hold
            // the dimming against the new file's first frames.
            livenessLastTimePos = nil
            livenessLastAdvanceAt = 0
            playbackStalled = false
            if #available(macOS 12.0, *) {
                contentAdaptiveDimming?.playbackStalled = false
            }
            resetCropForOpening()
            cropDetector.cancel()
            cropDetector.resetLastFile()
            nativeVideoAspect = nil
            videoLayoutAspect = nil
            videoLayoutRotation = 0
            videoDisplayW     = 0
            videoDisplayH     = 0
            trackListCache.removeAll()
            subtitleView.clearAll()
            if !ThreeDRecognitionBridge.internalMedia(p) && p != vr180Controller?.recognitionPath {vr180Controller?.resetForFileChange()}
            contentAdaptiveDimming?.resetAmbientCheckpoints()
            subtitleView.setFilePath(p)
            stereoManualAspect = nil
            spineUI.isPGSCodec = false
            autoPlayTried = false
            ipcCommand(#"{"command":["set_property","sid","auto"]}"#)
            if musicModeController?.isMusicMode != true {
                appliedVideoFrame           = .zero
                appliedVideoFrameWindowSize = .zero
            }
            let isTorrentActive = !((NSApp.delegate as? AppDelegate)?.currentTorrentURL ?? "").isEmpty
            let isYtdlLive = results["ytdl_is_live"] as? Bool ?? false
            let isLive = self.isIptvMode || isTorrentActive || isYtdlLive
            if isLive != self.isLive {
                self.isLive = isLive
                let signal = isLive ? "true" : "false"
                ipcCommand("{\"command\":[\"script-message-to\",\"photon\",\"set-live\",\"\(signal)\"]}")
            }
            sidebarUI.isLiveStream = isLive
        }

        if mediaTransitionPending && mediaTransitionLoaded,
           let p=results["path"] as? String,p==currentFilePath,!p.isEmpty,
           let w=results["video-params/dw"] as? Double,let h=results["video-params/dh"] as? Double,w>0,h>0 {
            finishMediaTransition()
        }
        let cropPropertyAspectChanged=noteCropPropertyLayout(results,tag:meta.layoutReadbackTag)
        if !cropMotionActive,let crop = results["video-crop"] as? String {
            let changed = crop != lastSourceCropValue
            lastSourceCropValue=crop
            sourceCropPropertyActive = !crop.isEmpty
            if changed, crop.isEmpty, let kept = cropReassertableRect, sourceCropPropertyRequested {
                // mpv dropped our crop (vo reconfig etc.) while we still own an applied one: re-issue it.
                print(CropInvariant.keptLine("video-crop cleared externally"))
                requestRealCrop(kept)
                return
            }
            if changed, !vrModeEnabled, (!usesCropCommandReceipts || manualMenuCropAspect != nil) {
                if sourceCropPropertyActive, let c = SBSGeometry.parseCrop(crop) {
                    refitWindowForCrop(aspect:manualMenuCropAspect ?? (usesCropCommandReceipts ? currentOpeningPropertyAspect:nil) ?? c.0/c.1)
                } else if !sourceCropPropertyRequested { if surfaceToolsEnabled, !menuCropOwnsSelection, let rect=cropRect {requestRealCrop(rect)} else {refitWindowForCrop(aspect:stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect)} }
            }
        }
        // File-path handling above can reset this flag in the same poll.
        // Once playback has begun, cache readiness must never undo a pause.
        if results["pause"] as? Bool == false {
            autoPlayTried = true
        }

        if let t = results["media-title"] as? String, musicModeController?.isMusicMode != true, !isTorrentStopped {
            let isUrlLike = t.hasPrefix("http://") || t.hasPrefix("https://")
                         || t.hasPrefix("rtsp://")  || t.hasPrefix("rtmp://")
            if !iptvChannelTitle.isEmpty {
                spineUI.setTitle(iptvChannelTitle)
            } else if !isUrlLike && !t.isEmpty {
                spineUI.setTitle(t)
            }
            if t != lastMediaTitle, !t.isEmpty { lastMediaTitle = t }
        }

        if musicModeController?.isMusicMode != true && !mediaTransitionPending {
            let newW = results["video-params/dw"] as? Double ?? 0
            let newH = results["video-params/dh"] as? Double ?? 0
            videoLayoutRotation = results["video-params/rotate"] as? Double ?? 0
            if let w = results["video-dec-params/dw"] as? Double,
               let h = results["video-dec-params/dh"] as? Double {
                nativeVideoAspect = Self.rotatedAspect(width:w,height:h,rotation:videoLayoutRotation)
            }
            videoLayoutAspect = Self.rotatedAspect(width: newW, height: newH, rotation: videoLayoutRotation)
            let flatGeometry=vr180Controller?.requestsFlatSBSGeometry(for:currentFilePath) == true ? Self.flatSourceGeometry(results):nil
            filmGeometryBasis=flatGeometry?.basis ?? "unchanged"
            vr180Controller?.autoDetectFromVideoParams(
                stereoMode: results["video-params/stereo-in"] as? String,
                width: flatGeometry?.w ?? (results["video-dec-params/w"] as? Double ?? results["video-dec-params/dw"] as? Double ?? newW),
                height: flatGeometry?.h ?? (results["video-dec-params/h"] as? Double ?? results["video-dec-params/dh"] as? Double ?? newH), filename: currentFilePath,
                pixelAspect:flatGeometry?.par ?? (results["video-dec-params/par"] as? Double ?? 1),
                sourceCrop:results["video-crop"] as? String,
                containerMetadata:results["metadata"] as? [String:String] ?? [:]
            )
            refreshCropSourcePacking()
            refreshStereoMenuGeometry()
            let dw   = results["dwidth"]           as? Double ?? 0
            let dh   = results["dheight"]          as? Double ?? 0
            let osdW = results["osd-width"]        as? Double ?? 0
            let osdH = results["osd-height"]       as? Double ?? 0

            var finalW: Double
            var finalH: Double
            if currentFilePath.isEmpty {
                finalW = osdW > 0 ? osdW : 0
                finalH = osdH > 0 ? osdH : 0
            } else {
                finalW = dw > 0 ? dw : newW
                finalH = dh > 0 ? dh : newH
            }

            // video-crop changes post-crop dwidth/dheight, not the source identity. Keep the last
            // full display dimensions for scan ownership; videoLayoutAspect above remains post-crop.
            if sourceCropPropertyActive, videoDisplayW>0,videoDisplayH>0 {
                finalW=videoDisplayW;finalH=videoDisplayH
            }
            // gor 514 real crop: while our @gorcrop is live mpv's dwidth/dheight are the CROPPED size. The
            // detection / menu dimensions stay the FULL frame, so map it back (no false "dimensions changed").
            if videoDisplayW > 0, videoDisplayH > 0,
               cropMPV.knownCroppedSizes.contains(where: { abs(Double($0.w) - finalW) < 1 && abs(Double($0.h) - finalH) < 1 }) {
                finalW = videoDisplayW
                finalH = videoDisplayH
            }

            if finalW > 0, finalH > 0 {
                // gor 514: freshness tracking for the file-loaded
                // immediate attempt (dims can precede file-loaded).
                if dw > 0 && dh > 0 {
                    lastDisplayDimsValid = true
                    lastDisplayDimsPath = currentFilePath
                }
                let dimsChanged = (finalW != videoDisplayW || finalH != videoDisplayH)
                videoDisplayW = finalW
                videoDisplayH = finalH
                if dimsChanged {
                    if cropRect != nil { print(CropInvariant.transitionLine("dims changed", crop: cropRect, display: (finalW, finalH))) }
                    // I31 / TRAP-07: cancel only after fresh dimensions change, not on stale nonzero dimensions.
                    iptvModeController?.cancelBlackScreenWarning()
                    var needsRedetect = false
                    if !currentFilePath.isEmpty,
                       (!currentFilePath.hasPrefix("http://localhost") || CropDetector.isWTPlayback(currentFilePath)),
                       cropRect != nil || wtCropRetry[currentFilePath] != nil {
                        // Coded dims changed under an applied crop (rendition
                        // hop, broadcast AR switch): keep the rect displayed
                        // while re-measuring — anti-flap. The decisive result
                        // drives any transition through the crop state machine.
                        print("[cropdetect] dimensions changed with crop applied or search pending — re-measuring")
                        wtCropRetry[currentFilePath] = nil
                        cropDetector.cancel()
                        cropDetector.resetLastFile()
                        needsRedetect = true
                    }
                    appliedVideoFrame           = .zero
                    appliedVideoFrameWindowSize = .zero
                    // gor 514 (F-A): ONLY actual display dimensions
                    // (dwidth/dheight - post-rotation, SAR-corrected) may
                    // fire the fit; a coded-dims-only transient keeps the
                    // arm until display dims arrive.
                    if dw > 0 && dh > 0 {
                        applyOpeningFitIfArmed(videoW: finalW, videoH: finalH)
                    }
                    applyVideoFrame(bounds: bounds)
                    startAutomaticCropDetection(needsRedetect: needsRedetect)
                }
                if mediaTransitionNeedsFit, dw>0, dh>0,
                   let freshAspect=stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect ?? videoLayoutAspect {
                    mediaTransitionNeedsFit=false
                    applyOpeningFitIfArmed(videoW:finalW,videoH:finalH)
                    if vrModeEnabled {refreshStereoMenuGeometry(force:true)}
                    else {refitWindowForCrop(aspect:freshAspect)}
                    startAutomaticCropDetection()
                }
                if cropPackingNeedsRedetect {startAutomaticCropDetection(needsRedetect:true)}
            } else {
                // gor 514: nothing on screen - stored freshness is stale.
                lastDisplayDimsValid = false
                if videoDisplayW != 0 || videoDisplayH != 0 {
                    videoDisplayW               = 0
                    videoDisplayH               = 0
                    appliedVideoFrame           = .zero
                    appliedVideoFrameWindowSize = .zero
                }
            }
        }

        if cropPropertyAspectChanged,!cropMotionActive {
            appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero
            applyVideoFrame(bounds:bounds)
        }
        reconcileCropPropertyWindow()
        // P4 (card 713): observed osd-dimensions acceptance. Runs AFTER every
        // landed commit above, so accept-time tags match just-committed state.
        acceptOsdDims(results: results, meta: meta)

        // Stereo custom subtitles own the one visible source. Outside stereo preserve the
        // native renderer choice. Never show custom until both native visibility flags are OFF.
        AVSessionTrace.shared.sample(results,stereo:vrModeEnabled)
        if let value=results["sub-scale"] as? Double {
            acceptSubtitleScale(value)
        }
        if let value=results["sub-delay"] as? Double {subtitleView.setSubtitleDelay(value)}
        if let value=results["sub-pos"] as? Double {
            if pendingSubtitleModePosition == nil || abs(value-pendingSubtitleModePosition!)<0.000001 {
                pendingSubtitleModePosition=nil;subtitleView.setSubtitlePosition(value)
            }
        }
        let primaryNative=results["sub-visibility"] as? Bool ?? false
        let secondaryNative=results["secondary-sub-visibility"] as? Bool ?? false
        // Visibility OPTIONS do not prove a renderer has a track. mpv defaults
        // secondary-sub-visibility=true even with secondary-sid=false/no track.
        let nativeReported = SubtitleRendererOwnership.nativeVisible(primaryVisible: primaryNative,
            secondaryVisible: secondaryNative, primaryID: results["current-tracks/sub/id"], secondaryID: results["secondary-sid"])
        let stereoCustomOwnsSubtitles = vr180Controller?.vrModeEnabled == true || LiveCaptionController.shared.isActive
        if stereoCustomOwnsSubtitles && nativeReported {
            ipcCommand(#"{"command":["set_property","sub-visibility",false]}"#)
            ipcCommand(#"{"command":["set_property","secondary-sub-visibility",false]}"#)
        }
        let mpvNativeSubs = nativeReported && !stereoCustomOwnsSubtitles
        // Hide custom until the native OFF acknowledgement is observed, so no frame has two sources.
        subtitleView.setNativeSubtitleRendererActive(nativeReported)
        GeomTrace.logChanged("subtitleOwner", "{\"k\":\"subtitleOwner\",\"stereo\":\(stereoCustomOwnsSubtitles),\"nativeVisible\":\(nativeReported),\"customVisible\":\(!nativeReported),\"trackedTilt\":\(headTrackingEnabled)}")
        if !LiveCaptionController.shared.isActive && !mpvNativeSubs {
            let mpvSubText  = results["sub-text"] as? String
            let subStart    = results["sub-start"] as? Double ?? 0
            let subEnd      = results["sub-end"]   as? Double ?? 0
            let subDuration = subEnd - subStart

            if let subText = mpvSubText, !subText.isEmpty {
                let delay=results["sub-delay"] as? Double ?? 0
                let window=SubtitleMenuTiming.displayWindow(start:subStart,end:subEnd,delay:delay)
                subtitleView.show(text: subText,duration:subDuration,at:currentTime,
                    cueStart:window.start,cueEnd:window.end)
                if !SubtitleCueStore.shared.cues.isEmpty {
                    SubtitleCueStore.shared.cues = []
                }
            }
            subtitleView.checkExternalCue(at: currentTime)
        }

        recordSubtitleProbe(results: results, nativeReported: nativeReported)
        if let subCodec = results["current-tracks/sub/codec"] as? String {
            let isPGS = subCodec == "dvd_subtitle" || subCodec == "hdmv_pgs_subtitle"
            if isPGS {
                spineUI.isPGSCodec = true
                subtitleView.setPGSCodec(true, mediaTitle: lastMediaTitle.isEmpty ? nil : lastMediaTitle)
            }
        }

        if let msg = results["osd-msg1"] as? String {
            let clean = Self.cleanMPVOSD(msg)
            if !clean.isEmpty {
                if clean != lastShownMPVOSD {
                    spineUI.showMPVOSD(clean)
                    lastShownMPVOSD = clean
                }
            } else {
                lastShownMPVOSD = ""
            }
        } else {
            lastShownMPVOSD = ""
        }

        if spineUI.isOSDVisible() { spineUI.refreshOSD(string: osdString()) }
        TransferProbeAdmission.update(path: currentFilePath, seconds: results["demuxer-cache-duration"] as? Double, pausedForCache: (results["seeking"] as? Bool == true) ? true : results["paused-for-cache"] as? Bool, stamp: "\(meta.connGen):\(meta.keySeq["demuxer-cache-duration"] ?? 0):\(meta.keySeq["paused-for-cache"] ?? 0)")
        if let cacheState  = results["demuxer-cache-state"] as? [String: Any],
           let cacheRanges = cacheState["seekable-ranges"]  as? [[String: Any]],
           let lastRange   = cacheRanges.last,
           let end         = lastRange["end"]               as? Double,
           duration > 0 {
            let bufferProgress = end / duration
            sidebarUI.seekBar.bufferProgress = bufferProgress
            // Crop-search bookkeeping uses the furthest downloaded second, never the last listed
            // range: mpv does not promise seekable-ranges order, and a stale low end would hide
            // real cache growth from the restart rule (UI buffer progress keeps the old policy).
            let frontierEnd = cacheRanges.compactMap { $0["end"] as? Double }.max() ?? end
            if frontierEnd > lastSeekableEnd { lastSeekableEnd = frontierEnd }
            // 199az: cache growth past the range the pending search could see restarts it at once.
            // scannedEnd is the scan's own dispatch frontier identity (CropDetector records the raw
            // max range end at dispatch, same coordinate as frontierEnd here), so growth during a
            // pending scan is charged once at completion, not laundered into the monotonic latest
            // end - and an unchanged cache never trips the rule.
            if let pending = wtCropRetry[currentFilePath], !cropSearchOwnsSelection, Self.cropSearchGrowthRestarts(frontierEnd: frontierEnd, scannedEnd: pending.scannedEnd) {
                print("[cropdetect] buffer grew past the scanned range (\(Int(pending.scannedEnd))s -> \(Int(end))s)")
                restartPendingWTCropSearch("buffer-growth")
            }

            if end >= 5.0, duration > 0, !isPlaying, !autoPlayTried {
                autoPlayTried = true
                ipcCommand(#"{"command":["set_property","pause",false]}"#)
            }
        }

        // 199az: a video track switch (same file, new current-tracks/video/id) restarts a
        // pending crop search at once. The first observation of a file (0 -> id) is not a switch.
        if let vid = results["current-tracks/video/id"] as? Int, vid != lastVideoTrackID {
            let switched = lastVideoTrackID > 0 && vid > 0
            lastVideoTrackID = vid
            if switched { restartPendingWTCropSearch("track-switch") }
        }

        if let enabled = results["user-data/adaptive-brightness-enabled"] as? Bool {
            contentAdaptiveDimming?.runtimeEnabled = enabled
        }

        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }; applyVideoFrame(bounds: bounds)
        if isTorrentStopped {
            sidebarUI.update(currentTime: 0, duration: 0, progress: 0, volume: volume)
        } else {
            sidebarUI.update(
                currentTime: currentTime,
                duration:    duration,
                progress:    currentProgress(),
                volume:      volume
            )
        }
    }

    // MARK: - Crop

    // ── Crop state machine ────────────────────────────────────────────
    /// Anti-oscillation: every runtime change to the applied crop funnels
    /// through transitionCrop. Applying from a cold start is free; reverting
    /// to default or changing the rect needs stronger evidence than the
    /// detector's 2/3 gate, plus a cooldown since the last visible transition,
    /// so no vote sequence can flap the picture. Manual redetect overrides
    /// the cooldown (user intent) but never the evidence bar; the reset menu
    /// always transitions immediately. A reset disarms the cooldown, so a
    /// new file's first crop is never delayed by the last file's history.
    private enum CropTransition {
        case apply(CGRect)   // default -> applied
        case revert          // applied -> default (measured no-bars)
        case reRect(CGRect)  // applied -> applied with a different rect
        case reset           // reset menu: always allowed
    }

    private static let cropTransitionCooldown: TimeInterval = 15.0
    private static let cropRevertMinConfidence: Double = 0.75

    private var lastCropTransitionAt: Date = .distantPast
    /// Set by reDetectCrop, consumed by the next detector result: exactly one
    /// decisive transition per click, cooldown exempt.
    private var manualRedetectInFlight = false

    private func sameCrop(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.02 && abs(a.minY - b.minY) < 0.02 &&
        abs(a.width - b.width) < 0.02 && abs(a.height - b.height) < 0.02
    }

    // MARK: - gor 514 real crop (mpv vf crop, labelled @gorcrop)

    private var cropActionGeneration: UInt64 = 0

    // ── P4 (card 713), scope B: observed rendered-rect state ────────────────
    // Accepted osd-dimensions value plus the state it was tagged with at
    // accept time; both nil whenever validity is in doubt (landed bound then).
    var surfaceDrawableSnapshot:(Double,Double)?;var surfaceCropAwaitingDrawable=false
    private var latestOsdDims: [String: Double]? = nil
    private var latestOsdEpoch: (osdW: Double, osdH: Double, rotation: Double, path: String)? = nil
    /// True while a filter mutation may be un-acked or the physical filter
    /// state is otherwise unknown. Set at SEND time, never only at ack.
    private var osdFilterUncertain = false
    /// True once an add may physically exist; false only on proven absence.
    private var filterMayExist = false
    /// Socket-arrival barrier: accepted values must postdate it.
    private var osdLayoutSeq: UInt64 = 0
    private var osdAcceptFloor: UInt64 = 0
    private var lastAcceptedOsdSeq: UInt64 = 0
    private var lastSeenConnGen: UInt64 = 0
    /// P4/R1: mutation generation, bumped at EVERY uncertainty-setting event.
    /// A clearing event applies only while its captured generation still
    /// matches: a stale generation can never clear a newer uncertainty (the
    /// reset -> later add -> old ack and removing -> new crop -> old
    /// completion interleavings).
    private var osdMutationGen: UInt64 = 0
    private var activeFlowGen: UInt64 = 0     // generation the current .probing-rooted flow started under
    private var removingGen: UInt64 = 0       // generation at the latest entry into .removing
    private var resetRemovalGen: UInt64 = 0   // generation at the latest uncertainty-setting resetForNewFile
    private var chainQueryGen: UInt64 = 0     // generation at the latest chain readback send
    /// False once this mpv rejects the osd-dimensions observation.
    private var osdDimsAvailable = true
    /// Launch-monotonic ids for the reconnect chain readback: never reused, so
    /// a reply correlates to the connection the command was written to by
    /// construction (write() no-ops while disconnected).
    private var nextOsdQueryId = 3_000_001
    private var pendingOsdChainQueryId: Int? = nil

    private func invalidateOpeningLayout() {
        guard !embeddedBackend else{return}
        cropLastCommandValue=nil;cropLayoutReadback=nil;cropPropertyLayout=nil;cropWindowIssuedLayout=nil
        nativeVideoAspect=nil;videoLayoutAspect=nil;videoLayoutRotation=0
        videoDisplayW=0;videoDisplayH=0
        lastDisplayDimsValid=false;lastDisplayDimsPath=""
        lastSourceCropValue="";sourceCropPropertyActive=false
        appliedVideoFrame = .zero;appliedVideoFrameWindowSize = .zero
        latestOsdDims=nil;latestOsdEpoch=nil;surfaceDrawableSnapshot=nil
        deferredWindowRefitAspect=nil
    }
    private func resetCropForOpening() {
        queuedManualCrop=nil
        cropSearchWake &+= 1;cropSearchWakePending=false
        cropDetectionStopped=false
        cropFreshFollowup &+= 1;cropReceiverSeekToken=nil;cropSourceOpening &+= 1;cropMeasurementEpoch &+= 1;cropSeekFenceActive=false;cropFreshMeasurementRequired=false;cropConfirmedRect=nil;cropConfirmedIdentity=nil;cropSourceAcceptanceAnchor=nil
        cropPacketToken=nil;cropPacketTokenAttempts=0
        dropCropPacketIntent()
        rejectedCropRetryAvailable=true
        cancelCropMotion();cropGeometryOwnedUntil=0;cropPresentationRect=Self.fullSourceCrop
        lastDisplayDimsValid=false;lastDisplayDimsPath="";manualRedetectInFlight=false
        invalidateOpeningLayout()
        vr180Controller?.invalidateOpenReceipt()
        deferredWindowRefitAspect = nil; windowRefitAnchorFrame = nil
        stereoManualAspect = nil; stereoMenuCropAspect = nil; stereoMenuOriginalFrame = nil; stereoGeometryKey = ""; stereoProjectionBaseAspect = nil; stereoRestorePending = false
        (NSApp.delegate as? AppDelegate)?.currentAspectPreset = .defaultAR
        ipcCommand(#"{"command":["set","video-aspect-override","no"]}"#)
        ipcCommand(#"{"command":["script-message-to","vr180_look","vr180-look-menu-crop","1","1"]}"#)
        cropActionGeneration &+= 1
        cropRect = nil
        lastSeekableEnd = 0; lastVideoTrackID = 0   // file transition: the previous file's buffer end and track id never carry over
        cropAutoRetries = 0
        lastCropTransitionAt = .distantPast
        // P4: retained margins never survive a file transition. The reset
        // removal is fire-and-forget, so the physical filter state is
        // uncertain ONLY if a filter may exist (otherwise it is a no-op and
        // the missing-label semantics of mpv never matter).
        if filterMayExist {
            osdFilterUncertain = true
            osdMutationGen &+= 1
            resetRemovalGen = osdMutationGen
        }
        latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
        menuCropOwnsSelection=false
        manualMenuCropAspect=nil;lastSourceCropValue=""
        sourceCropPropertyActive=false;sourceCropPropertyRequested=false
        _=applyCropPresentation(Self.fullSourceCrop)
        if !embeddedBackend {runCropActions(cropMPV.resetForNewFile())}
    }

    /// All explicit crop reset controls share this path. Stop the detector first so an
    /// old completion cannot put the removed crop back, and refit even when vf was idle.
    func clearOwnedCropFromMenu() {
        if embeddedBackend && embeddedSourceCrop == nil {_=refuseEmbedded("source crop adapter");return}
        dropCropPacketIntent() // invalidate sender intent AND receiver token before the explicit reset
        cropDetector.cancel();manualRedetectInFlight=false;menuCropOwnsSelection=true
        clearStereoMenuCrop()
        transitionCrop(.reset, manual: true)
        refitWindowForCrop(aspect:stereoManualAspect ?? nativeVideoAspect)
        appliedVideoFrame = .zero
        appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds: bounds)
    }

    private func requestRealCrop(_ rect: CGRect, automatic:Bool=false, measured:Bool=false, newIntent:Bool=false, resuming:UInt64?=nil) {
        // Validity is the first gate: an invalid or non-finite rect must never
        // reach the token query, the retry path, or the recorded intent.
        guard rect.minX>=0,rect.minY>=0,rect.width>0,rect.height>0,rect.maxX<=1,rect.maxY<=1,
              [rect.minX,rect.minY,rect.width,rect.height].allSatisfy({$0.isFinite}) else{return}
        if !embeddedBackend,!vrModeEnabled,!surfaceToolsEnabled,Self.gorFitScriptActive,
           cropBoundLaunchSession != Self.cropPacketSession {return}
        // The transport guarantee covers every accepted request, cached-token
        // motions included: the desired rect is recorded BEFORE the token
        // branch so a rotation mid-motion can re-acquire and finish THIS crop,
        // and a newer desire always replaces an older intent, never merges.
        if !embeddedBackend && !vrModeEnabled && !surfaceToolsEnabled && Self.gorFitScriptActive,!currentFilePath.isEmpty {
            // Poll/reconfiguration re-drives are not fresh measurements or new explicit actions.
            if cropFreshMeasurementRequired,!newIntent,resuming==nil,rect != Self.fullSourceCrop {return}
            if let resuming {
                guard resuming==cropPacketIntentGen,let intent=cropPacketIntent,intent.path==currentFilePath,intent.rect==rect,
                      intent.opening==cropSourceOpening,(!intent.measured || intent.epoch==cropMeasurementEpoch) else{return}
            } else if newIntent || cropPacketIntent?.path != currentFilePath || cropPacketIntent?.rect != rect {
                cropPacketIntent=(rect,currentFilePath,automatic,measured,cropMeasurementEpoch,cropSourceOpening)
                cropPacketIntentGen &+= 1;cropPacketPending=nil;cropPacketFinal=nil
            }
        }
        if !embeddedBackend && !vrModeEnabled && !surfaceToolsEnabled && Self.gorFitScriptActive && cropPacketToken==nil {
            if let inFlight=cropPacketPending,inFlight.path==currentFilePath,inFlight.rect==rect {return} // identical query already in flight; let its ACK land
            cropPacketPending=nil // a genuinely newer crop request replaces any in-flight token query; its late reply no longer matches
            requestCropPacketToken(rect);return
        }

        if embeddedBackend && embeddedSourceCrop == nil {_=refuseEmbedded("source crop adapter");return}
        if !embeddedBackend,(surfaceToolsEnabled || vrModeEnabled),surfaceDrawableReceipt()==nil {surfaceCropAwaitingDrawable=true;return}
        // Reconfiguration/poll receipts must not restart an in-flight transition.
        if cropMotionActive,rect == cropMotionTargetRect {return}
        if !embeddedBackend,Self.gorFitScriptActive {ipcCommand(MPVCommand.make(["script-message-to","gor_fit","cancel"]))}
        cancelCropMotion()
        let generation=cropMotionGeneration,source=currentFilePath,openingToken=cropPacketToken
        let from=cropPresentationRect,windowFrom=window?.frame
        cropMotionActive=true;cropMotionTargetRect=rect;cropMotionPlanning=true;cropMotionWindowTarget=nil
        let aspect=cropWindowAspect(rect)
        refitWindowForCrop(aspect:aspect)
        cropMotionPlanning=false
        let windowTo=cropMotionWindowTarget
        let usesCropPacket = !embeddedBackend && !vrModeEnabled && !surfaceToolsEnabled
        // External mpv source crop is a single final command. Lua waits for
        // source reconfiguration (or500ms) before animating only the window.
        let clock=CropMotionClock(started:ProcessInfo.processInfo.systemUptime,duration:usesCropPacket ? 0:0.42)
        func step(_ host:PPController,_ now:Double) {
            guard host.cropMotionGeneration==generation,host.currentFilePath==source,host.cropPacketToken==openingToken else{return}
            let phase=clock.phase(now),sample=CropMotionClock.mix(from,rect,phase)
            let previous=host.cropPresentationRect
            host.cropPresentationRect=sample
            var packet:[PlayerCropSample]=[]
            let capture:((PlayerCropSample)->Void)?=usesCropPacket ? {packet.append($0)}:nil
            guard host.applyCropPresentation(sample,publish:capture) else {
                host.cropPresentationRect=previous
                host.cropRect=previous == Self.fullSourceCrop ? nil:previous
                host.cancelCropMotion();return
            }
            if let a=windowFrom,let b=windowTo {
                host.cropGeometryOwnedUntil=now+0.65
                let frame=CropMotionClock.mix(a,b,phase)
                if host.embeddedBackend {
                    guard host.embeddedCropWindow?(frame,aspect ?? 1,phase>=1)==true else {
                        host.spineUI.showMPVOSD("gorav crop window refused",force:true);host.interruptCropMotion();return
                    }
                } else if let screen=host.window?.screen ?? NSScreen.main,
                          let geom=GorOpeningFit.clampGeometry(frame:frame,screen:screen,chromeStyleMask:(NSApp.delegate as? AppDelegate)?.pictureInPictureActive == true ? .borderless:GorOpeningFit.mpvWindowMask) {
                    let sample=PlayerCropSample.window(geom,scripted:Self.gorFitScriptActive,final:phase>=1)
                    if usesCropPacket {packet.append(sample)} else {host.playbackOperations.publish(sample)}
                }
            }
            if usesCropPacket {
                // A script-message queue is not atomic with a preceding native property.
                // Run source + window updates inside one validated Lua callback, unlock first.
                if Self.gorFitScriptActive {
                    guard let prepared=PlayerFitProtocol.packet(packet,scripted:true,token:openingToken,source:source,intent:host.cropPacketIntentGen,motion:generation,sequence:&host.cropPacketSampleSequence,final:phase>=1),
                          let crop=prepared.crop,let openingToken else{host.cancelCropMotion();return}
                    let sequence=host.cropPacketSampleSequence,intent=host.cropPacketIntentGen
                    if phase>=1 {
                        host.cropPacketFinal=(openingToken,source,intent,generation,sequence,crop,rect)
                        host.cropPacketAcceptance="awaiting"
                        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak host] in
                            guard let host,host.cropPacketFinal?.sequence==sequence,host.cropPacketFinal?.motion==generation,host.cropPacketAcceptance=="awaiting" else{return}
                            host.cropPacketAcceptance="receipt-missing"
                            host.scheduleCropCommandRecovery()
                            host.cropDetector.resetLastFile() // remove only the settled-success latch, no immediate scan
                            host.showCropDetectOSD("crop not confirmed: receiver receipt missing")
                            print("[crop-receipt] final command acceptance unresolved; intent retained")
                        }
                    }
                    host.playbackOperations.deliver(prepared,generation:generation,final:phase>=1)
                } else if let prepared=PlayerFitProtocol.packet(packet,scripted:false,token:openingToken,source:source,intent:host.cropPacketIntentGen,motion:generation,sequence:&host.cropPacketSampleSequence,final:phase>=1) {
                    host.playbackOperations.deliver(prepared,generation:generation,final:phase>=1)
                }
            }
            if phase>=1 {
                host.cropMotionTimer?.invalidate();host.cropMotionTimer=nil;host.cropMotionActive=false
            }
            // Final layout must resolve the settled accessor even if the property
            // tuple arrived during interpolation and will not change on the next poll.
            host.appliedVideoFrame = .zero;host.appliedVideoFrameWindowSize = .zero
            host.applyVideoFrame(bounds:host.bounds)
            if phase>=1 {
                host.reconcileCropPropertyWindow()
                if !(usesCropPacket && Self.gorFitScriptActive),host.cropPacketIntent?.path==source,host.cropPacketIntent?.rect==rect {host.cropPacketIntent=nil}
                if !host.usesCropCommandReceipts,!host.embeddedBackend,let aspect,let delegate=NSApp.delegate as? AppDelegate,delegate.pictureInPictureActive {
                    delegate.refitPictureInPicture(aspect:aspect)
                }
            }
        }
        step(self,clock.started)
        guard cropMotionActive else{return}
        let timer=Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in
            guard let self else{return}
            guard self.cropMotionGeneration==generation else{return}
            guard self.currentFilePath==source else {self.cancelCropMotion();return}
            step(self,ProcessInfo.processInfo.systemUptime)
        }
        cropMotionTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    /// Real invalidation of the desired crop: user/lifecycle paths only.
    private func dropCropPacketIntent() {
        if !embeddedBackend,!vrModeEnabled,!surfaceToolsEnabled,Self.gorFitScriptActive {
            // Never let the next explicit reset reuse the token this fence is about to revoke.
            cropPacketToken=nil
            playbackOperations.fenceCropIntent()
        }
        cropPacketFinal=nil;cropPacketAcceptance="unresolved"
        cropPacketPending=nil;cropPacketIntent=nil;cropPacketIntentGen &+= 1
    }
    private func cancelCropMotion() {
        cropWindowRecoveryTicket &+= 1;cropWindowRecoveryKey=nil
        cropLayoutReadback=nil;cropWindowIssuedLayout=nil;deferredWindowRefitAspect=nil
        cropPacketFinal=nil
        if cropMotionActive,!embeddedBackend,Self.gorFitScriptActive {ipcCommand(MPVCommand.make(["script-message-to","gor_fit","cancel"]))}
        cropMotionGeneration &+= 1
        playbackOperations.resetCrop(cropMotionGeneration)
        cropMotionTimer?.invalidate();cropMotionTimer=nil
        cropMotionActive=false;cropMotionPlanning=false;cropMotionWindowTarget=nil;cropMotionTargetRect=nil
    }
    func stopEmbeddedCropWork() {stopCropFreshFollowthrough();dropCropPacketIntent();cancelCropMotion();cropDetector.cancel()}
    func interruptCropMotion() {
        cropGeometryOwnedUntil=0
        dropCropPacketIntent() // the user took over, even if we are still waiting for a token
        guard cropMotionActive else{return}
        cropRect=cropPresentationRect == Self.fullSourceCrop ? nil:cropPresentationRect
        cancelCropMotion()
    }
    private func cropWindowAspect(_ rect:CGRect)->Double? {
        if vrModeEnabled,let source=vr180Controller?.flatUIEyeAspect ?? stereoProjectionBaseAspect ?? nativeVideoAspect.map({$0*0.5}),
           let plan=StereoMenuGeometry.plan(sourceAspect:source,aspectOverride:stereoManualAspect,cropAspect:stereoMenuCropAspect,gap:effectiveVrGap?.value ?? 0) {
            let v=StereoMenuGeometry.viewport(plan,detected:rect,menuOwns:menuCropOwnsSelection)
            return Int(videoLayoutRotation)%180 == 0 ? v.windowAspect:1/v.windowAspect
        }
        return stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect.map {$0*Double(rect.width/rect.height)}
    }
    /// Each sample is applied through the real engine operation. No screenshot zoom substitute.
    private func applyCropPresentation(_ rect:CGRect,publish:((PlayerCropSample)->Void)?=nil)->Bool {
        let send=publish ?? { [weak self] in self?.playbackOperations.publish($0) }
        if embeddedBackend {
            if let why=embeddedSourceCrop?(currentFilePath,rect) {spineUI.showMPVOSD("gorav crop refused: "+why,force:true);return false}
            guard embeddedSourceCrop != nil else{return false}
            sourceCropPropertyRequested=true
            return true
        }
        if !vrModeEnabled && !surfaceToolsEnabled {
            let w=cropDetector.sourcePixelWidth,h=cropDetector.sourcePixelHeight
            let x=Int((Double(rect.minX)*Double(w)).rounded()),y=Int((Double(rect.minY)*Double(h)).rounded())
            let cw=Int((Double(rect.width)*Double(w)).rounded()),ch=Int((Double(rect.height)*Double(h)).rounded())
            if rect == Self.fullSourceCrop {
                sourceCropPropertyRequested=false
                cropLastCommandValue=""
                send(.source(""))
                return true
            }
            guard w>0,h>0,cw>0,ch>0,CropInvariant.fits(x:x,y:y,w:cw,h:ch,srcW:Int(w),srcH:Int(h)) else{return false}
            sourceCropPropertyRequested=true
            let value="\(cw)x\(ch)+\(x)+\(y)"
            cropLastCommandValue=value
            send(.source(value))
            return true
        }
        sourceCropPropertyRequested=false
        send(.source(""))
        if vrModeEnabled {
            vr180Controller?.clearMeasuredEyeAspect();refreshStereoMenuGeometry(force:true)
            return true
        }
        if surfaceToolsEnabled {return publishSurfaceWindowCrop(x:Double(rect.width),y:Double(rect.height),cx:Double(rect.midX),cy:Double(rect.midY))}
        return true
    }

    /// P4: one read-only vf-list query to resolve physical-filter uncertainty
    /// after a (re)connect. The launch-monotonic id correlates the reply to
    /// THIS connection by construction (never reused; written only while
    /// connected, so only an mpv on this connection can answer it).
    private func sendOsdChainQuery() {
        let id = nextOsdQueryId
        nextOsdQueryId += 1
        pendingOsdChainQueryId = id
        chainQueryGen = osdMutationGen
        persistentConnection.write(GorCropPlan.queryCommand(id: id))
    }

    /// P4: the chain readback proves the LOGICAL filter chain at processing
    /// time, not physical pixels. It clears uncertainty only on a verified
    /// match of the current phase; anything else stays uncertain (landed
    /// bound), and a reply to anything but the latest minted id is ignored.
    private func noteOsdChainReply(id: Int, ok: Bool, data: Any?, arrival: UInt64) {
        guard id == pendingOsdChainQueryId, chainQueryGen == osdMutationGen else { return }
        pendingOsdChainQueryId = nil
        guard ok else { return }
        switch cropMPV.phase {
        case .active(let f):
            guard GorCropPlan.verify(vfList: data, expected: f) else { return }
            filterMayExist = true
        case .idle:
            guard !GorCropPlan.isPresent(vfList: data) else { return }
            filterMayExist = false
        default:
            return
        }
        osdFilterUncertain = false
        osdAcceptFloor = max(osdAcceptFloor, arrival)
        latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
    }

    /// P4: GorCrop reply handling with physical-state bookkeeping. The ONLY
    /// clearing events for margins uncertainty:
    /// - entering .active (GorFit's own verify+confirm - its strongest signal);
    /// - the correlated ok reply to the latest resetForNewFile removal
    ///   (request_id match is the documented correlation mechanism);
    /// - a tracked removal completing ok (.removing -> .idle).
    /// Each also raises the acceptance floor to that reply's socket arrival.
    private func noteGorCropReply(id: Int, ok: Bool, data: Any?, arrival: UInt64) {
        var wasActive = false
        if case .active = cropMPV.phase { wasActive = true }
        var wasRemoving = false
        if case .removing = cropMPV.phase { wasRemoving = true }
        var wasProbing = false
        if case .probing = cropMPV.phase { wasProbing = true }
        runCropActions(cropMPV.reply(id: id, ok: ok, data: data))
        var nowActive = false
        if case .active = cropMPV.phase { nowActive = true }
        var nowRemoving = false
        if case .removing = cropMPV.phase { nowRemoving = true }
        var nowProbing = false
        if case .probing = cropMPV.phase { nowProbing = true }
        // A flow or removal that STARTS under the current generation inherits
        // it (covers flows started by settle() from a coalesced request).
        if nowProbing, !wasProbing { activeFlowGen = osdMutationGen }
        if nowRemoving, !wasRemoving { removingGen = osdMutationGen }
        // Every clearing additionally requires its captured generation to
        // still be current: a reply about an older mutation can never clear
        // uncertainty a LATER send created (R1).
        if nowActive, !wasActive, activeFlowGen == osdMutationGen {
            filterMayExist = true
            osdFilterUncertain = false
            osdAcceptFloor = max(osdAcceptFloor, arrival)
            latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
        }
        if ok, id == cropMPV.lastResetRemovalId, resetRemovalGen == osdMutationGen {
            filterMayExist = false
            osdFilterUncertain = false
            osdAcceptFloor = max(osdAcceptFloor, arrival)
            latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
        }
        if ok, wasRemoving, case .idle = cropMPV.phase, removingGen == osdMutationGen {
            filterMayExist = false
            osdFilterUncertain = false
            osdAcceptFloor = max(osdAcceptFloor, arrival)
            latestOsdDims = nil; latestOsdEpoch = nil;surfaceDrawableSnapshot=nil
        }
    }

    /// P4 (card 713), scope B: accept mpv's reported rendered-picture rect ONLY
    /// from the observed osd-dimensions stream, when its socket arrival order
    /// (PollEngine Meta - arrival order, not physical causality) postdates
    /// every geometry transition signal and the latest filter barrier, the
    /// filter state is certain, the socket is live, and the property is
    /// available. Any doubt keeps the landed bound.
    private func acceptOsdDims(results: [String: Any], meta: PollEngine.Meta) {
        // Block 180: env-gated rejection trace so the self-test capture shows
        // exactly which guard refuses acceptance (change-gated, main queue).
        func reject(_ why: String) {
            GeomTrace.logChanged("osdAcceptReject", String(format: #"{"k":"osdAcceptReject","why":"%@"}"#, why))
        }
        guard !osdFilterUncertain else { reject("filter-uncertain"); return }
        guard persistentConnection.isConnected else { reject("socket-down"); return }
        guard osdDimsAvailable else { reject("unavailable"); return }
        guard let raw = results["osd-dimensions"] as? [String: Any] else { reject("no-feed"); return }
        var d = [String: Double]()
        for k in ["w", "h", "ml", "mr", "mt", "mb"] {
            if let n = (raw[k] as? NSNumber)?.doubleValue, n.isFinite { d[k] = n }
        }
        // Structural garbage reject only; documented dummy values that look
        // sane (mpv: VO window not created/visible) are NOT detectable this way.
        // Block 180 (architect): negative margins are ACCEPTED - under zoom the
        // rendered picture can be larger than the window. applyVideoFrame
        // intersects the rendered rect with the visible window, so the bound
        // always tracks the current picture instead of holding a stale one.
        guard d.count == 6, let w = d["w"], let h = d["h"], w > 1, h > 1,
              let ml = d["ml"], let mr = d["mr"], let mt = d["mt"], let mb = d["mb"] else { reject("garbage"); return }
        guard let oSeq = meta.keySeq["osd-dimensions"], oSeq > osdAcceptFloor, oSeq > lastAcceptedOsdSeq else { reject("stale-seq"); return }
        var predates: String? = nil
        for k in ["path", "video-params/rotate", "video-params/dw", "video-params/dh"] {
            if let s = meta.keySeq[k], oSeq <= s { predates = k; break }
        }
        if let preKey = predates { reject("predates-" + preKey); return }
        lastAcceptedOsdSeq = oSeq
        let moved = latestOsdDims.map { o in d.contains { abs($0.value - (o[$0.key] ?? .infinity)) > 1 } } ?? true
        if moved { osdLayoutSeq = oSeq }
        if moved { GeomTrace.logChanged("osdAccept", String(format: #"{"k":"osdAccept","why":"accepted","w":%.1f,"h":%.1f,"ml":%.1f,"mr":%.1f,"mt":%.1f,"mb":%.1f,"seq":%llu}"#, w, h, ml, mr, mt, mb, oSeq)) }
        latestOsdDims = d;surfaceDrawableSnapshot=(w,h)
        if surfaceCropAwaitingDrawable {surfaceCropAwaitingDrawable=false;DispatchQueue.main.async { [weak self] in guard let self else {return};if self.vrModeEnabled {self.refreshStereoMenuGeometry(force:true)} else if self.surfaceToolsEnabled {self.requestRealCrop(self.cropRect ?? CGRect(x:0,y:0,width:1,height:1))} }}
        latestOsdEpoch = (osdW: w, osdH: h, rotation: videoLayoutRotation, path: currentFilePath)
        if moved, bounds.width > 1, bounds.height > 1 {
            appliedVideoFrame = .zero
            appliedVideoFrameWindowSize = .zero
            applyVideoFrame(bounds: bounds)
        }
    }

    /// (socket down, mpv gone), so the overlay path takes over and later requests are not blocked.
    private func runCropActions(_ actions: [GorCropMPV.Action]) {
        let generation = cropActionGeneration
        for action in actions {
            switch action {
            case .send(let json):
                persistentConnection.write(json)
            case .sendAfter(let json, let ms):
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                    guard let self, self.cropActionGeneration == generation else { return }
                    self.persistentConnection.write(json)
                }
            case .overlayIdentity:
                appliedVideoFrame           = .zero
                appliedVideoFrameWindowSize = .zero
                applyVideoFrame(bounds: bounds)
            case .refit(let aspect):
                if vrModeEnabled { refreshStereoMenuGeometry(force:true) }
                else if menuCropOwnsSelection {refitWindowForCrop(aspect:stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect)}
                else { refitWindowForCrop(aspect: aspect) }
            case .refitFull:
                if let aspect=stereoManualAspect ?? manualMenuCropAspect ?? nativeVideoAspect {refitWindowForCrop(aspect:aspect);break}
                if vrModeEnabled { refreshStereoMenuGeometry(force:true) }
                else { refitWindowForCrop(aspect: nil) }
            case .failed(let why):
                print("[cropdetect] real crop: \(why)")
            case .cropAbandoned:
                // Window and video are back at the full frame: drop the UI crop too (never window-full with an
                // overlay-cropped UI), and allow ONE automatic re-measure so a transient failure can recover.
                guard let keptRect = cropRect else { break }
                // Applied-crop invariant: an automatic failure never clears the crop. Re-issue the SAME rect once.
                print(CropInvariant.keptLine("real crop abandoned"))
                applyVideoFrame(bounds: bounds)
                if cropAutoRetries < 1 {
                    cropAutoRetries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self, self.cropActionGeneration == generation,
                              let r = self.cropRect, r == keptRect else { return }
                        self.requestRealCrop(r)
                    }
                }
            }
        }
        if let awaited = cropMPV.awaitedId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self, self.cropActionGeneration == generation else { return }
                // P4: a watchdog timeout leaves a removal un-acked (socket down
                // / mpv gone): the physical filter state is unknown from here
                // on. Absence of a feed is NOT proof retained margins are safe.
                self.osdFilterUncertain = true
                self.osdMutationGen &+= 1
                self.latestOsdDims = nil; self.latestOsdEpoch = nil
                self.runCropActions(self.cropMPV.timedOut(id: awaited))
            }
        }
    }

    /// Window follows the cropped aspect: user's width kept, centered after crop (uncrop stays anchored), shrunk
    /// to fit the usable screen on BOTH axes, written as an absolute mpv geometry like the opening fit.
    private var cropWindowRecoveryTicket:UInt64=0
    private var cropWindowRecoveryKey:(tag:String,aspect:Double,attempts:Int)?
    private var cropWindowIssuedLayout:(tag:String,aspect:Double)?
    @discardableResult
    private func reconcileCropPropertyWindow(settledFrame:NSRect?=nil)->Bool {
        guard usesCropCommandReceipts,!cropMotionActive,!mediaTransitionPending,
              !presentationIsQuitting,!cropDetectionStopped,manualMenuCropAspect==nil,
              let layout=cropPropertyLayout,let readback=cropLayoutReadback,
              readback.intent==cropPacketIntentGen,layout.tag==readback.tag,
              let aspect=currentOpeningPropertyAspect,aspect.isFinite,aspect>0 else{return false}
        guard cropWindowIssuedLayout?.tag != readback.tag || cropWindowIssuedLayout?.aspect != aspect else{return false}
        let delegate=NSApp.delegate as? AppDelegate
        guard delegate?.playerFullscreenState != true,delegate?.windowGeometryTransitionActive != true,
              !openingFitPending,window != nil else{return false}
        // Use the real refit caller. Property mismatch is actual geometry, not target acceptance.
        // No unscoped deferred aspect is created here: every later attempt revalidates identity.
        if cropWindowRecoveryKey?.tag != readback.tag || cropWindowRecoveryKey?.aspect != aspect {
            cropWindowRecoveryTicket &+= 1;cropWindowRecoveryKey=(readback.tag,aspect,0)
        }
        let ticket=cropWindowRecoveryTicket,tag=readback.tag,path=currentFilePath,opening=cropSourceOpening,intent=cropPacketIntentGen
        guard refitWindowForCrop(aspect:aspect,settledFrame:settledFrame,completion:{ [weak self] outcome in
            guard let self,self.cropWindowRecoveryTicket==ticket,self.currentFilePath==path,self.cropSourceOpening==opening,
                  self.cropPacketIntentGen==intent,self.cropLayoutReadback?.tag==tag else{return}
            switch outcome {
            case .landed,.alreadyEqual:break // Classified geometry receipt, never decoded-frame proof.
            case .userTakeover,.superseded:self.cropWindowRecoveryTicket &+= 1
            case .rejected,.unproven:
                guard let key=self.cropWindowRecoveryKey,key.tag==tag,key.aspect==aspect,key.attempts<3 else{return}
                self.cropWindowRecoveryKey=(tag,aspect,key.attempts+1)
                DispatchQueue.main.asyncAfter(deadline:.now()+[0.5,1.0,2.0][key.attempts]) { [weak self] in
                    guard let self,self.cropWindowRecoveryTicket==ticket,self.currentFilePath==path,
                          self.cropSourceOpening==opening,self.cropPacketIntentGen==intent,self.cropLayoutReadback?.tag==tag else{return}
                    self.cropWindowIssuedLayout=nil
                    self.reconcileCropPropertyWindow()
                }
            }
        }) else{return false}
        cropWindowIssuedLayout=(readback.tag,aspect)
        return true
    }
    private var windowRefitAnchorFrame: NSRect?
    func noteUserWindowGeometry(frame: NSRect) {
        guard !cropGeometryTransitionActive else{return}
        guard (NSApp.delegate as? AppDelegate)?.windowGeometryTransitionActive != true else { return }
        cropWindowRecoveryTicket &+= 1
        windowRefitAnchorFrame = frame
    }
    private var deferredWindowRefitAspect: Double?
    @discardableResult
    func finishFullscreenGeometryTransition(frame: NSRect) -> Bool {
        if reconcileCropPropertyWindow(settledFrame:frame) {return true}
        guard let aspect = deferredWindowRefitAspect else { return false }
        deferredWindowRefitAspect = nil
        refitWindowForCrop(aspect: aspect, settledFrame: frame)
        return true
    }
    @discardableResult
    private func refitWindowForCrop(aspect: Double?, settledFrame: NSRect? = nil,completion:((GorGeometryOutcome)->Void)?=nil) -> Bool {
        if cropMotionActive && !cropMotionPlanning {return false}
        if cropRect != nil { print(CropInvariant.transitionLine("window refit", crop: cropRect, display: (videoDisplayW, videoDisplayH))) }
        let a = aspect ?? appliedSourceCropAspect ?? (videoDisplayH > 0 ? videoDisplayW / videoDisplayH : 0)
        guard a > 0 else { return false }
        if mediaTransitionPending {deferredWindowRefitAspect=a;return false}
        if (NSApp.delegate as? AppDelegate)?.windowGeometryTransitionActive == true {
            deferredWindowRefitAspect = a
            return false
        }
        if let delegate=NSApp.delegate as? AppDelegate,delegate.pictureInPictureActive {
            if cropMotionPlanning,let win=window,let screen=win.screen ?? NSScreen.main {
                cropMotionWindowTarget=PlayerPictureInPicture.croppedFrame(current:win.frame,screen:screen.frame,aspect:a)
            } else {delegate.refitPictureInPicture(aspect:a,completion:completion)}
            return true
        }
        guard let win = window else { return false };if openingFitPending { deferredWindowRefitAspect = a; return false }
        deferredWindowRefitAspect = nil
        let f = settledFrame ?? win.frame
        let receiptScreen = settledFrame.flatMap { f in NSScreen.screens.max {
            let a = $0.frame.intersection(f), b = $1.frame.intersection(f)
            return (a.isNull ? 0 : a.width*a.height) < (b.isNull ? 0 : b.width*b.height)
        } }
        guard let screen = receiptScreen ?? win.screen ?? NSScreen.main else { return false }
        let vf = screen.visibleFrame
        let probe = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                       styleMask: GorOpeningFit.mpvWindowMask)
        // Keep the user's width across format round-trips. A portrait fit may shrink to screen height;
        // that derived narrow width must not become the next landscape proposal.
        if windowRefitAnchorFrame == nil { windowRefitAnchorFrame = f }
        let width = windowRefitAnchorFrame?.width ?? f.width
        guard let r = GorCropPlan.refitFrame(
                frame: GorFitRect(x: f.minX, y: f.minY, w: width, h: f.height),
                aspect: a, chromeW: probe.width - 100, chromeH: probe.height - 100,
                avail: GorFitRect(x: vf.minX, y: vf.minY, w: vf.width, h: vf.height)) else { return false }
        // A committed crop centers on the same screen; uncrop keeps its old anchor.
        let target = NSRect(x: aspect != nil ? vf.midX - r.w / 2 : r.x,
                            y: aspect != nil ? vf.midY - r.h / 2 : r.y,
                            width: r.w, height: r.h)
        if cropMotionPlanning {cropMotionWindowTarget=target;return true}
        if embeddedBackend {return embeddedCropWindow?(target,a,true)==true}
        if target.isAlmostEqual(to:f,epsilon:1.5) {completion?(.alreadyEqual);return true}
        guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen) else{return false}
        if let delegate = NSApp.delegate as? AppDelegate {
            // Same fence as the clamp: our own refit receipt is not mistaken for a user resize, and a user drag
            // during it is not swallowed (landing unproven -> re-evaluation).
            delegate.issueFencedGeometry(geom, before: f, target: target,completion:completion)
        } else {
            sendGeometryUntracked(geom)
            completion?(.unproven)
        }
        return true
    }

    private func transitionCrop(_ transition: CropTransition, confidence: Double = 1.0, manual: Bool = false) {
        let cooledDown = manual ||
            Date().timeIntervalSince(lastCropTransitionAt) >= Self.cropTransitionCooldown
        if cropRect != nil { print(CropInvariant.transitionLine("transition \(transition) manual=\(manual)", crop: cropRect, display: (videoDisplayW, videoDisplayH))) }
        func suppress(_ reason: String) {
            print("[cropdetect] \(reason) — crop state unchanged")
            // Never lock the file into a suppressed state: the next dims
            // change re-measures and the transition can land then.
            cropDetector.resetLastFile()
        }
        switch transition {
        case .reset:
            queuedManualCrop=nil
            vr180Controller?.clearMeasuredEyeAspect()
            // A reset forgets crop history: the next file's first crop
            // applies instantly, never blocked by the last file's cooldown.
            cropRect = nil
            manualMenuCropAspect=nil
            cropAutoRetries = 0
            lastCropTransitionAt = .distantPast
            if filterMayExist { osdFilterUncertain = true; osdMutationGen &+= 1 }   // P4: removal may be pending
            sourceCropPropertyRequested=false
            requestRealCrop(Self.fullSourceCrop,automatic:!manual,newIntent:true)
            if !embeddedBackend {runCropActions(cropMPV.clear())}
            if case .removing = cropMPV.phase { removingGen = osdMutationGen }   // P4/R1
        case .apply(let rect):
            // Identical crop already applied: re-applying it only flashes the re-rect, so return early (199al / 199ai.1).
            if cropRect == rect { if manual || ((cropFreshMeasurementRequired || cropMayRedriveIdenticalTarget) && cropMayAutomaticallyReplaceTarget(rect)) {requestRealCrop(rect,automatic:!manual,measured:true,newIntent:true);cropFreshMeasurementRequired=false};return }
            guard cropRect == nil else { return }
            guard manual || cropMayAutomaticallyReplaceTarget(rect) else {suppress(CropInvariant.keptLine("auto apply after unresolved reset"));return}
            guard cooledDown else { suppress("apply suppressed by anti-flap cooldown"); return }
            cropRect = rect
            lastCropTransitionAt = Date()
            print("[cropdetect] target planned: \(rect.debugDescription)")
            cropFreshMeasurementRequired=false
            requestRealCrop(rect,automatic:!manual,measured:true,newIntent:true)
        case .revert:
            guard cropRect != nil else { return }
            vr180Controller?.clearMeasuredEyeAspect()
            guard CropInvariant.mayChange(manual: manual) else { suppress(CropInvariant.keptLine("auto revert")); return }
            guard cooledDown else { suppress("revert suppressed by anti-flap cooldown"); return }
            cropRect = nil
            lastCropTransitionAt = Date()
            print("[cropdetect] crop reverted to default")
            if filterMayExist { osdFilterUncertain = true; osdMutationGen &+= 1 }   // P4: removal may be pending
            sourceCropPropertyRequested=false
            requestRealCrop(Self.fullSourceCrop,automatic:!manual,measured:true,newIntent:true)
            if !embeddedBackend {runCropActions(cropMPV.clear())}
            if case .removing = cropMPV.phase { removingGen = osdMutationGen }   // P4/R1
        case .reRect(let rect):
            guard let current = cropRect else { return }
            if sameCrop(current, rect) {
                if manual || ((cropFreshMeasurementRequired || cropMayRedriveIdenticalTarget) && cropMayAutomaticallyReplaceTarget(rect)) {
                    cropFreshMeasurementRequired=false
                    let previousFilter = cropMPV.displayedFilter
                    requestRealCrop(rect,automatic:!manual,measured:true,newIntent:true)  // explicit Redetect re-triggers the physical chain, not only UI crop
                    if let filter = previousFilter { refitWindowForCrop(aspect:GorCropPlan.effectiveAspect(filter)) }
                    appliedVideoFrame = .zero; appliedVideoFrameWindowSize = .zero
                    applyVideoFrame(bounds:bounds)
                }
                return
            }
            // A later measurement may always widen the applied crop (less crop); automatic narrowing stays
            // blocked and keeps the applied crop, and a manual reRect is unchanged.
            let widensAppliedCrop = cropMayAutomaticallyReplaceTarget(rect)
            guard CropInvariant.mayChange(manual: manual) || widensAppliedCrop else { suppress(CropInvariant.keptLine("auto re-rect")); return }
            guard cooledDown else { suppress("re-rect suppressed by anti-flap cooldown"); return }
            cropRect = rect
            lastCropTransitionAt = Date()
            print("[cropdetect] target updated: \(rect.debugDescription)")
            cropFreshMeasurementRequired=false
            requestRealCrop(rect,automatic:!manual,measured:true,newIntent:true)
        }
        appliedVideoFrame           = .zero
        appliedVideoFrameWindowSize = .zero
        applyVideoFrame(bounds: bounds)
    }

    private func clearStereoMenuCrop(refit: Bool = true) {
        guard stereoMenuCropAspect != nil else { return }
        stereoMenuCropAspect = nil
        if refit { refreshStereoMenuGeometry(force:true) }
    }
    private func restoreStereoMenuFrame() {
        stereoRestorePending = true
        stereoMenuOriginalFrame = nil
        // A historical size may have the previous mode's aspect. Use the same current-content
        // refit path as aspect/crop changes, including fullscreen transition deferral.
        refitWindowForCrop(aspect: nativeVideoAspect)
    }
    func resetCrop() {
        clearOwnedCropFromMenu()
    }

    func reDetectCrop() {
        guard !presentationIsQuitting else{return}
        cropDetectionStopped=false
        rejectedCropRetryAvailable=true;cropPacketTokenAttempts=0
        if embeddedBackend && embeddedSourceCrop == nil {_=refuseEmbedded("source crop adapter");return}
        refreshCropSourcePacking()
        menuCropOwnsSelection=false;manualMenuCropAspect=nil; stereoRestorePending = false
        if cropDetector.isPending, cropDetector.hasScanProgress {
            if !manualRedetectInFlight {
                queuedManualCrop=(currentFilePath,cropSourceOpening,cropMeasurementEpoch,cropDetector.retryToken)
            }
            showCropDetectOSD(manualRedetectInFlight ? "crop detect: manual measurement already running" : "crop detect: manual pass queued after current measurement")
            return
        }
        queuedManualCrop=nil
        guard !currentFilePath.hasPrefix("http://localhost") || CropDetector.isWTPlayback(currentFilePath) else {
            print("[cropdetect] unknown localhost source — skipping reDetect")
            return
        }
        // Keep the current crop displayed while re-measuring: one decisive
        // result per click, no uncrop bounce.
        manualRedetectInFlight = true
        cropDetector.cancel()
        cropDetector.resetLastFile()
        cropDetector.detect(
            filePath:         currentFilePath,
            videoW:           videoDisplayW,
            videoH:           videoDisplayH,
            fallbackDuration: duration,
            manualPriority:   true
        )
    }

    func cancelCropDetection() {
        queuedManualCrop=nil
        stopCropFreshFollowthrough()
        manualRedetectInFlight = false
        cropDetector.cancel()
    }

    /// Transient on-screen text through mpv's own OSD, so crop-detect
    /// feedback is visible over the video no matter where the spine UI is.
    func showCropDetectOSD(_ text: String) {
        if embeddedBackend {spineUI.showMPVOSD(text,force:true);return}
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        ipcCommand("{\"command\":[\"show-text\",\"\(escaped)\",2500]}")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        applyVideoFrame(bounds: bounds)
        musicModeController?.relayout()
        iptvModeController?.relayout()
    }

    // MARK: - Brightness
    func setBrightness(_ value: Float) { brightness.setUserBrightness(value) }

    func fadeToOriginalBrightnessForQuit(completion: @escaping () -> Void) {
        brightness.quitFade(completion: completion)
    }

    func restoreOriginalBrightnessForQuitDeadline() {
        brightness.restoreForQuitDeadline()
    }

    // MARK: - Auto-hide

    private func setupAutoHide() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .scrollWheel]
        ) { [weak self] e in
            self?.wakeUI()
            return e
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if spineUI.scrollTrackDropdownIfNeeded(with:event) {wakeUI();return}
        if vrModeEnabled {
            vr180Controller?.sendVRLookNudge(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            wakeUI()
            return
        }

        // Photon HUD scrolls only while the pointer hovers its rows and the
        // content overflows; otherwise the event keeps the old routing, so
        // the two-finger subtitle-position scroll stays untouched outside
        // the HUD.
        if spineUI.scrollPhotonHUDIfNeeded(with: event, in: self) {
            wakeUI()
            return
        }

        subtitleView.scrollWheel(with: event)

        wakeUI()

    }

    override func magnify(with event: NSEvent) {
        guard vrModeEnabled else {
            super.magnify(with: event)
            return
        }
        let dFov = event.magnification * VR180Controller.vrFovDegPerMagnifyUnit
        vr180Controller?.sendVRFovNudge(deltaFovDegrees: dFov)
        wakeUI()
    }

    override func rotate(with event:NSEvent) {
        guard vrModeEnabled else {super.rotate(with:event);return}
        vr180Controller?.sendVRLookNudge(deltaX:0,deltaY:0,deltaRollDegrees:Double(event.rotation))
        wakeUI()
    }

    private func setVRMirrorChromeOpacity(_ opacity: Float, duration: CFTimeInterval) {
        let key = "chromeOpacity"
        let fromOpacity = vrControlMirrorRoot.presentation()?.opacity ?? vrControlMirrorRoot.opacity
        vrControlMirrorRoot.removeAnimation(forKey: key)
        guard duration > 0 else { vrControlMirrorRoot.opacity = opacity; return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = fromOpacity
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        vrControlMirrorRoot.add(animation, forKey: key)
        vrControlMirrorRoot.opacity = opacity
    }

    func wakeUI() {
        if spineUI.alphaValue < 1 {
            setVRMirrorChromeOpacity(1.0, duration: 0.2)
            ThreeDCornerTuneView.shared.setChromeAlpha(1.0, duration: 0.2)
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.2
                self.spineUI.animator().alphaValue   = 1.0
                self.sidebarUI.animator().alphaValue = 1.0
                self.iptvPanel?.setChromeAlpha(1.0, animated: true)
                (NSApp.delegate as? AppDelegate)?.magnetBrowser?.panel.setChromeAlpha(1.0, animated: true)
            }
        }
        if spineUI.alphaValue >= 1 {
            ThreeDCornerTuneView.shared.setChromeAlpha(1.0, duration: 0)
            iptvPanel?.setChromeAlpha(1.0)
            (NSApp.delegate as? AppDelegate)?.magnetBrowser?.panel.setChromeAlpha(1.0)
        }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.setVRMirrorChromeOpacity(0.0, duration: 0.5)
            ThreeDCornerTuneView.shared.setChromeAlpha(0.0, duration: 0.5)
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.5
                self?.spineUI.animator().alphaValue   = 0.0
                self?.sidebarUI.animator().alphaValue = 0.0
                self?.iptvPanel?.setChromeAlpha(0.0, animated: true)
                (NSApp.delegate as? AppDelegate)?.magnetBrowser?.panel.setChromeAlpha(0.0, animated: true)
            }
            self?.spineUI.clearMPVOSD(animated: true)
        }
    }

    private func checkCursorHide() {
        var isDialogOpen = false
        if let keyWindow = NSApp.keyWindow {
            isDialogOpen = keyWindow.isKind(of: NSPanel.self)
        }
        // A window frame lives in global screen coordinates and keeps its
        // value when the window is carried onto another Space. Geometric
        // containment alone therefore also matched the same rectangle on
        // whatever desktop is active: the cursor vanished over the player's
        // old position with no player on that Space. Only a window that is
        // visible on the active Space may own cursor hiding (same gate as
        // the drag/drop path in Controller/Input.swift).
        let win = window
        let windowUsable = win != nil && win!.isVisible && win!.isOnActiveSpace
        let mouseInWindow = win != nil && win!.frame.contains(NSEvent.mouseLocation)

        switch Self.cursorHideDecision(dialogOpen: isDialogOpen,
                                       windowUsable: windowUsable,
                                       mouseInWindow: mouseInWindow,
                                       timeSinceLastMove: inputController?.timeSinceLastMouseMove ?? 0,
                                       hidden: cursorHidden) {
        case .hide:
            CGDisplayHideCursor(CGMainDisplayID()); cursorHidden = true
        case .show:
            CGDisplayShowCursor(CGMainDisplayID()); cursorHidden = false
        case .keep:
            break
        }
    }

    enum CursorHideDecision { case hide, show, keep }

    /// Pure hide/show decision, extracted for platform-independent testing.
    /// Hide only while the pointer rests over a usable (visible, active-Space)
    /// player window; every other state shows a hidden cursor exactly once.
    static func cursorHideDecision(dialogOpen: Bool,
                                   windowUsable: Bool,
                                   mouseInWindow: Bool,
                                   timeSinceLastMove: TimeInterval,
                                   hidden: Bool) -> CursorHideDecision {
        guard !dialogOpen, windowUsable, mouseInWindow else {
            return hidden ? .show : .keep
        }
        if timeSinceLastMove > 1.5, !hidden { return .hide }
        if timeSinceLastMove <= 1.5, hidden { return .show }
        return .keep
    }

    // MARK: - Mouse events

    // First click while another app's window had focus: the borderless overlay window is the one under the cursor, and an
    // NSView refuses the activating click by default (acceptsFirstMouse is false), so AppKit used the first click only to
    // activate and the click never reached gor; a second click was needed. Accept it, and make sure gor really is the
    // active app with this window key and the player (not a text field) as first responder. Nothing is forced when a
    // sheet or modal window is up, and an editing text control keeps its focus. Click, drag and double-click handling is
    // the same code as before and now also runs for the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func claimFocusForClick() {
        guard let w = window, w.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        // An open input panel owns the key window: a player click keeps its action but no
        // longer tears key (and the search field's first responder) away from the panel.
        guard PanelKeyOwnership.shared.mayKeyPlayerWindow() else { return }
        if !w.isKeyWindow { w.makeKeyAndOrderFront(nil) }
        if let r = w.firstResponder, r !== self, !(r is NSText), !(r is NSTextView), !(r is NSControl) {
            w.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        claimFocusForClick()
        let handled = inputController?.handleMouseDown(with: event) ?? false
        if !handled { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        inputController?.handleMouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        inputController?.handleMouseUp(with: event)
        super.mouseUp(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        inputController?.handleMouseEntered(with: event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        inputController?.handleMouseExited(with: event)
        spineUI.handleExternalMouseExited()
        super.mouseExited(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        inputController?.handleMouseMoved(with: event)
        spineUI.handleExternalMouseMoved(with: event)
        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if inputController?.handleViewKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }


    // MARK: - Video frame calculation
    // I27: sole writer of spineUI/sidebarUI/subtitleView frames.
    private func applyVideoFrame(bounds: CGRect) {
        // Native view frames and their free-standing HUD/OSD layers land in one
        // transaction. Otherwise CALayer geometry eases behind the moving UI.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let winW = bounds.width
        let winH = bounds.height
        guard winW > 1, winH > 1 else { return }
        GeomTrace.log("applyVideoFrame", "win=\(Int(winW))x\(Int(winH)) applied=\(Int(appliedVideoFrameWindowSize.width))x\(Int(appliedVideoFrameWindowSize.height)) fs=\(window?.styleMask.contains(.fullScreen) ?? false)")

        if appliedVideoFrame != .zero,
           abs(appliedVideoFrameWindowSize.width  - winW) > 2 ||
           abs(appliedVideoFrameWindowSize.height - winH) > 2 {
            appliedVideoFrame           = .zero
            appliedVideoFrameWindowSize = .zero
        }

        let displayRect: CGRect
        if vrModeEnabled || committedFilmFrame != nil {
            // MAIN projection fills the drawable, independent of the encoded SBS aspect.
            displayRect = CGRect(x: 0, y: 0, width: winW, height: winH)
        } else if videoDisplayW > 0, videoDisplayH > 0 {
            // gor 514 real crop: while mpv shows a verified crop, the displayed picture IS the cropped aspect.
            let videoAR = stereoManualAspect ?? manualMenuCropAspect ?? nativePresentedCropAspect ?? cropMPV.displayedFilter.map {
                let aspect = GorCropPlan.effectiveAspect($0)
                return Self.rotatedAspect(width: aspect, height: 1, rotation: videoLayoutRotation) ?? aspect
            } ?? videoLayoutAspect ?? (videoDisplayW / videoDisplayH)
            let winAR   = Double(winW) / Double(winH)

            if videoAR > winAR + 0.02 {
                let h = (winW / CGFloat(videoAR)).rounded()
                let y = ((winH - h) / 2).rounded()
                displayRect = CGRect(x: 0, y: y, width: winW, height: h)
            } else if winAR > videoAR + 0.02 {
                let w = (winH * CGFloat(videoAR)).rounded()
                let x = ((winW - w) / 2).rounded()
                displayRect = CGRect(x: x, y: 0, width: w, height: winH)
            } else {
                displayRect = CGRect(x: 0, y: 0, width: winW, height: winH)
            }
        } else {
            displayRect = CGRect(x: 0, y: 0, width: winW, height: winH)
        }


        let target: CGRect
        if !vrModeEnabled, !cropMPV.overlayIsIdentity, !sourceCropPropertyRequested, let sourceCrop = visualCropRect, sourceCrop.width > 0.1, sourceCrop.height > 0.1 {
            let cr = Self.rotatedCropRect(sourceCrop, rotation: videoLayoutRotation)
            let dX = displayRect.minX + cr.minX * displayRect.width
            let dW = cr.width * displayRect.width

            let bottomBandRatio = 1.0 - cr.minY - cr.height
            let dY = displayRect.minY + bottomBandRatio * displayRect.height
            let dH = cr.height * displayRect.height

            target = CGRect(x: dX.rounded(), y: dY.rounded(),
                            width: dW.rounded(), height: dH.rounded())
        } else {
            target = displayRect
        }

        let roundedTarget = CGRect(x: round(target.minX), y: round(target.minY),
                                   width: round(target.width), height: round(target.height))
        guard !roundedTarget.isAlmostEqual(to: appliedVideoFrame, epsilon: 2.0) else { return }
        appliedVideoFrame           = roundedTarget
        appliedVideoFrameWindowSize = CGSize(width: winW, height: winH)
        // The photon HUD bounds itself to this rect (horizontal crop edge and
        // vertical room); keep it in sync whenever the target is recomputed.
        // P4 (card 713) + block 180 (architect): the bound is mpv's
        // actually-rendered picture rect INTERSECTED with the visible window.
        // Negative margins are accepted, so the rendered rect tracks zoom and
        // pan; the intersection clamps it to what is actually visible. Bounds
        // are never kept stale: when accepted osd dims exist they win, and
        // only a missing/uncertain/degenerate feed falls back to the current
        // frame's target.
        // v8 overlay-crop mapped branch (cropRect set, overlay non-identity):
        // the crop fractions are mapped into the ACCEPTED rendered rect with
        // the same arithmetic as the target mapping (rotatedCropRect +
        // bottom-band flip), clamped to the view.
        var hudBounds = roundedTarget
        var hudBoundsSource = "target"
        // Block 180: change-gated skip-reason trace for the bound source.
        func osdBranchSkip() {
            let why: String
            if osdFilterUncertain { why = "filter-uncertain" }
            else if !persistentConnection.isConnected { why = "socket-down" }
            else if !osdDimsAvailable { why = "unavailable" }
            else if latestOsdDims == nil || latestOsdEpoch == nil { why = "no-accepted" }
            else if let ep = latestOsdEpoch {
                if abs(ep.osdW - Double(winW)) > 2 || abs(ep.osdH - Double(winH)) > 2 { why = "epoch-window" }
                else if ep.rotation != videoLayoutRotation { why = "epoch-rotation" }
                else if ep.path != currentFilePath { why = "epoch-path" }
                else { why = "dims-shape" }
            } else { why = "unknown" }
            GeomTrace.logChanged("osdBranch", String(format: #"{"k":"osdBranch","why":"%@"}"#, why))
        }
        if !vrModeEnabled, !osdFilterUncertain, persistentConnection.isConnected, osdDimsAvailable,
           let od = latestOsdDims, let ep = latestOsdEpoch,
           abs(ep.osdW - Double(winW)) <= 2, abs(ep.osdH - Double(winH)) <= 2,
           ep.rotation == videoLayoutRotation, ep.path == currentFilePath,
           let ow = od["w"], let oh = od["h"], ow > 1, oh > 1,
           let ml = od["ml"], let mr = od["mr"], let mt = od["mt"], let mb = od["mb"] {
            let sx = winW / CGFloat(ow)
            let sy = winH / CGFloat(oh)
            let x0 = max(0, CGFloat(ml) * sx)
            let x1 = min(winW, CGFloat(ow - mr) * sx)
            let y0 = max(0, CGFloat(mb) * sy)           // mpv top-left origin -> view bottom-left
            let y1 = min(winH, CGFloat(oh - mt) * sy)
            if x1 - x0 > 1, y1 - y0 > 1 {
                let rendered = CGRect(x: x0.rounded(), y: y0.rounded(),
                                      width: (x1 - x0).rounded(), height: (y1 - y0).rounded())
                if sourceCropPropertyRequested || cropMPV.overlayIsIdentity || cropRect == nil {
                    // rendered is already intersected with the visible window
                    // (max(0)/min(win) above): the block 180 bound.
                    hudBounds = rendered
                    hudBoundsSource = "osd-floor"
                } else if let sourceCrop = cropRect, sourceCrop.width > 0.1, sourceCrop.height > 0.1,
                          !rendered.isAlmostEqual(to: displayRect, epsilon: 1.0) {
                    // v8 mapped branch: map the crop fractions into the accepted
                    // rendered rect with the SAME arithmetic as the target mapping
                    // (rotatedCropRect + bottom-band flip), clamped to the view.
                    let cr = Self.rotatedCropRect(sourceCrop, rotation: videoLayoutRotation)
                    let mX = rendered.minX + cr.minX * rendered.width
                    let mW = cr.width * rendered.width
                    let bottomBandRatio = 1.0 - cr.minY - cr.height
                    let mY = rendered.minY + bottomBandRatio * rendered.height
                    let mH = cr.height * rendered.height
                    let mapped = CGRect(x: mX.rounded(), y: mY.rounded(),
                                        width: mW.rounded(), height: mH.rounded())
                        .intersection(CGRect(x: 0, y: 0, width: winW, height: winH))
                    if !mapped.isNull, mapped.width > 1, mapped.height > 1 {
                        hudBounds = mapped
                        hudBoundsSource = "osd-mapped"
                    }
                }
            } else {
                osdBranchSkip()
            }
        } else {
            osdBranchSkip()
        }
        // Block 180 3d / 181: in VR the chrome (HUD/OSD/spine/subtitles) is
        // drawn once inside the LEFT eye's band and mirrored into the right
        // eye by replicator layers. chromeBounds = hudBounds clipped to the
        // left-eye band; the band edges mirror vr180-look.lua
        // (half_gap = gap * 0.25 around 0.5). Outside VR chromeBounds ==
        // hudBounds and every replicator keeps instanceCount 1.
        var chromeBounds = hudBounds
        var vrEyeShift: CGFloat = 0
        let vrGap = vrModeEnabled ? effectiveVrGap : nil
        // No sourced gap value: do not replicate - single instance, loud
        // gsrc=none trace, the v2 leg FAILS instead of accepting a fallback.
        let vrReplicating = committedFilmFrame.map {($0["instances"] ?? 1)>1} ?? (vrModeEnabled && vrGap != nil && displayRect.width > 1)
        if vrReplicating, let gap = vrGap?.value {
            let halfGap = gap * 0.25
            let leftEndX   = displayRect.minX + (0.5 - halfGap) * displayRect.width
            let rightStart = (0.5 + halfGap) * displayRect.width
            let band = CGRect(x: displayRect.minX, y: hudBounds.minY,
                              width: leftEndX - displayRect.minX, height: hudBounds.height)
            let clipped = hudBounds.intersection(band)
            if !clipped.isNull, clipped.width > 1 { chromeBounds = flatEyeContentBounds(clipped) }
            vrEyeShift = rightStart
        }
        if committedFilmFrame?["layout"] == 1 || committedFilmFrame?["layout"] == 2 {vrEyeShift=0}
        if let frame=committedFilmFrame {
            let fw=CGFloat(frame["frameW"]!)*winW,fh=CGFloat(frame["frameH"]!)*winH
            chromeBounds=CGRect(x:CGFloat(frame["baseX"]!)*winW-fw/2,y:(1-CGFloat(frame["baseY"]!))*winH-fh/2,width:fw,height:fh)
        } else if let fallback=missingFlatFilmBounds(in:bounds) {
            chromeBounds=fallback
        }
        visiblePictureBounds=chromeBounds
        // Every chrome surface is confined to the cropped film frame. Spine,
        // sidebar and the 3D tune overlay share this rect in 2D, SBS and tilt.
        let spineChromeBounds = chromeBounds
        controlChromeBounds = spineChromeBounds
        // Local chrome layout only: derive from the pre-tilt film rail. The
        // Delivery film snapshot still owns pose/fit and applies tilt/zoom once.
        PhotonFont.setChromeLayoutScale(PhotonFont.chromeLayoutScale(for: spineChromeBounds))
        spineUI.hudCropBounds      = visiblePictureBounds
        GeomTrace.logChanged("hudCropBounds", String(format: #"{"k":"hudCropBounds","r":[%.0f,%.0f,%.0f,%.0f],"disp":[%.0f,%.0f,%.0f,%.0f],"rot":%.0f,"vw":%.0f,"vh":%.0f,"win":[%.0f,%.0f],"osdSeq":%llu,"src":"%@","chrome":[%.0f,%.0f,%.0f,%.0f]}"#,
            hudBounds.minX, hudBounds.minY, hudBounds.width, hudBounds.height,
            displayRect.minX, displayRect.minY, displayRect.width, displayRect.height,
            videoLayoutRotation, videoDisplayW, videoDisplayH, winW, winH, osdLayoutSeq, hudBoundsSource,
            chromeBounds.minX, chromeBounds.minY, chromeBounds.width, chromeBounds.height))
        // Per-eye clip: while replicating, the container is masked to the
        // left eye's band so overflow cannot bleed across the physical gap;
        // otherwise the mask is removed - identical to pre-180d parenting.
        if let hostLayer = layer {
            vrChromeReplicator.frame = hostLayer.bounds
            vrChromeContainer.frame  = hostLayer.bounds
            updateUIChromeClip(hostLayer: hostLayer, rect: spineChromeBounds, eyeShift: vrEyeShift, replicating: vrReplicating)
            if vrChromeMask.backgroundColor == nil { vrChromeMask.backgroundColor = NSColor.black.cgColor }
            vrChromeMask.frame = spineChromeBounds
            if vrReplicating {
                vrChromeContainer.mask = vrChromeMask
            } else {
                vrChromeContainer.mask = nil
            }
        }
        vrChromeReplicator.instanceCount = vrReplicating ? 2 : 1
        let pixelScale=window?.backingScaleFactor ?? 1
        let eyePixels=max(0,chromeBounds.width*pixelScale)
        let factor=ThreeDSubtitleDepth.dial(vr180Controller?.subtitleDepthPoints ?? 1)
        let legacyDepth=StereoDepth.placeDepth(disparityPX:-Double(eyePixels)*0.004*factor,
            distanceMM:vr180Controller?.depthDistanceMM,mmPerPX:VRDistance.mmPerPx(),swapEyes:swapEyes)
        let fraction=ThreeDSubtitleDepth.subtitleFraction(base:0.004*factor,width:Double(eyePixels),event:subtitleView.depthEvent,now:ProcessInfo.processInfo.systemUptime)
        let subDepth=ThreeDSubtitleDepth.experimentalOn ? StereoDepth.placeDepth(disparityPX:-Double(eyePixels)*fraction,distanceMM:vr180Controller?.depthDistanceMM,mmPerPX:VRDistance.mmPerPx(),swapEyes:swapEyes) : legacyDepth
        let uiDepth=legacyDepth // F never moves controls or the saved subtitle dial.
        let sharedPreview=(committedFilmFrame?["layout"] ?? 0)==1 || (committedFilmFrame?["layout"] ?? 0)==2
        let subLeft=vrReplicating ? CGFloat(subDepth.left)/pixelScale : 0
        let subRight=vrReplicating ? CGFloat(subDepth.right)/pixelScale : 0
        let uiLeft=vrReplicating && !sharedPreview ? CGFloat(uiDepth.left)/pixelScale : 0
        let uiRight=vrReplicating && !sharedPreview ? CGFloat(uiDepth.right)/pixelScale : 0
        trackedUICenter=NSPoint(x:controlChromeBounds.midX,y:controlChromeBounds.midY); trackedUILeftOffset=uiLeft
        if abs(trackedUIRoll)<1e-10 { // Layout must not expose an untilted intermediate frame.
            vrChromeContainer.sublayerTransform=CATransform3DMakeTranslation(uiLeft,0,0)
            vrChromeReplicator.instanceTransform=CATransform3DMakeTranslation(vrEyeShift+uiRight-uiLeft,0,0)
        }
        let vrDialSigned = subRight-subLeft
        vrControlMirrorOn = vrReplicating
        vrControlMirrorShift = vrEyeShift+uiRight-uiLeft
        vrControlSourceOffset=uiLeft
        vrControlMirrorClip = spineChromeBounds.offsetBy(dx: vrEyeShift, dy: 0)
        spineUI.setVRChrome(on: vrReplicating, shiftX: vrEyeShift, leftOffset:uiLeft, rightOffset:uiRight)
        // Subtitles stay inside the cropped film frame (chromeBounds is the committed film rect,
        // and subtitleView.frame is set to it), not the whole display rect. Local coordinates.
        let subtitleFilmCanvas = committedFilmFrame != nil ? CGRect(origin:.zero,size:chromeBounds.size) : displayRect.offsetBy(dx:-chromeBounds.minX,dy:-chromeBounds.minY)
        subtitleView.setVRReplica(on: vrReplicating, shiftX: vrEyeShift, offsetX: vrDialSigned, leftOffset:subLeft,screen:subtitleFilmCanvas,overlayScreen:displayRect.offsetBy(dx:-chromeBounds.minX,dy:-chromeBounds.minY))
        // Establish the VR canvas before layout/trace on the very first entry.
        // Keep the trailing pin too: the crop alignment below resets frames.
        if vrReplicating, chromeBounds.width > 1 {
            subtitleView.frame = chromeBounds
            sidebarUI.frame = CGRect(x: spineChromeBounds.maxX - sidebarUI.sidebarWidth, y: spineChromeBounds.minY,
                                     width: sidebarUI.sidebarWidth, height: spineChromeBounds.height)
        }
        onVideoFrameApplied?(bounds, displayRect, target)

        // One visible-picture authority for every chrome surface, including
        // normal zoom/pan. target/displayRect describe the unzoomed layout;
        // chromeBounds already carries accepted osd-dimensions and VR clipping.
        spineUI.frame = CGRect(x:spineChromeBounds.minX,y:spineChromeBounds.minY,
                               width:spineUI.spineWidth,height:spineChromeBounds.height)
        // Spine, sidebar and the 3D tune overlay share the same cropped film rail.
        sidebarUI.frame = CGRect(x:spineChromeBounds.maxX-sidebarUI.sidebarWidth,y:spineChromeBounds.minY,
                                 width:sidebarUI.sidebarWidth,height:spineChromeBounds.height)
        subtitleView.frame = chromeBounds
        subtitleView.setTrackedOverlayBounds(controlChromeBounds,in:self)

        // v2: force the final geometry/layout NOW, then trace the ACTUAL
        // committed state - real child-layer unions INTERSECTED with the
        // actual clip rects, the replicators' committed translations, and
        // child counts - never recomputed stand-ins or stale pre-layout
        // frames. Replica frames are a pure function of these.
        layoutSubtreeIfNeeded()
        spineUI.layoutSubtreeIfNeeded()
        subtitleView.layoutSubtreeIfNeeded()
        CATransaction.flush()
        func rectJSON(_ r: CGRect?) -> String {
            guard let r, !r.isNull else { return "null" }
            return String(format: "[%.1f,%.1f,%.1f,%.1f]", r.minX, r.minY, r.width, r.height)
        }
        func contentUnion(_ container: CALayer, clip: CGRect?) -> (CGRect?, Int) {
            var u: CGRect? = nil
            let kids = container.sublayers ?? []
            for k in kids { u = u.map { $0.union(k.frame) } ?? k.frame }
            if let c = clip, let r = u { let i = r.intersection(c); u = i.isNull ? nil : i }
            return (u, kids.count)
        }
        let hudClip: CGRect? = vrReplicating ? chromeBounds : nil
        let hud = contentUnion(vrChromeContainer, clip: hudClip)
        let hudTx = vrChromeReplicator.instanceTransform.m41
        let spineState = spineUI.vrChromeTraceState()
        let subState = subtitleView.vrReplicaTraceState()
        let spineContent = spineState.content?.offsetBy(dx: spineUI.frame.minX, dy: spineUI.frame.minY)
        let spineClip = spineState.clip?.offsetBy(dx: spineUI.frame.minX, dy: spineUI.frame.minY)
        let subContent = subState.content?.offsetBy(dx: subtitleView.frame.minX, dy: subtitleView.frame.minY)
        let subRaw = subState.raw?.offsetBy(dx: subtitleView.frame.minX, dy: subtitleView.frame.minY)
        let subClip = subState.clip?.offsetBy(dx: subtitleView.frame.minX, dy: subtitleView.frame.minY)
        let gapV = vrGap?.value ?? 0
        let gapS = vrModeEnabled ? vrGapSourceLabel : "off"
        let hg2 = gapV * 0.25
        let eyeLRect = CGRect(x: displayRect.minX, y: displayRect.minY,
                              width: (0.5 - hg2) * displayRect.width, height: displayRect.height)
        let eyeRRect = eyeLRect.offsetBy(dx: (0.5 + hg2) * displayRect.width, dy: 0)
        let allClipped = !vrReplicating || (hudClip != nil && spineClip != nil && subClip != nil)
        GeomTrace.logChanged("vrChrome", String(format: #"{"k":"vrChrome","on":%d,"rep":%d,"gap":%.5f,"gsrc":"%@","clip":%d,"hud":%@,"hudN":%ld,"hudClip":%@,"hudTx":%.1f,"spine":%@,"spineN":%ld,"spineClip":%@,"spineTx":%.1f,"sub":%@,"subRaw":%@,"subN":%ld,"subClip":%@,"subTx":%.1f,"eyeL":%@,"eyeR":%@,"disp":%@}"#,
            vrModeEnabled ? 1 : 0, vrReplicating ? 1 : 0,
            gapV, gapS, allClipped ? 1 : 0,
            rectJSON(hud.0), hud.1, rectJSON(hudClip), hudTx,
            rectJSON(spineContent), spineState.children, rectJSON(spineClip), spineState.tx,
            rectJSON(subContent), rectJSON(subRaw), subState.children, rectJSON(subClip), subState.tx,
            rectJSON(eyeLRect), rectJSON(eyeRRect), rectJSON(displayRect)))


        // Frames above are final now. Snapshot actual NSView controls, not title-layer counts.
        spineUI.layoutSubtreeIfNeeded()
        sidebarUI.layoutSubtreeIfNeeded()
        if !videoFramePanels.isEmpty {
            videoFramePanels.removeAll { $0.view == nil }
            for entry in videoFramePanels {
                guard let view = entry.view else { continue }
                reflowVideoFramePanel(view, padL: entry.padL, padR: entry.padR, padT: entry.padT, base: visiblePictureBounds)
            }
        }
        musicModeController?.relayout()
        iptvModeController?.relayout()
        refreshVRControlMirrors()
    }

    // MARK: - OSD

    private static func cleanMPVOSD(_ raw: String) -> String {
        var s = raw
        while let r = s.range(of: #"\{[^}]*\}"#, options: .regularExpression) { s.removeSubrange(r) }
        let strips = ["○", "●", "─", "━", "▶", "⏸", "⏹", "\u{25CF}", "\u{25CB}"]
        for p in strips { s = s.replacingOccurrences(of: p, with: "") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Native mpv and custom subtitles share the same canonical mpv properties.
    /// Read back before reflow/OSD: a successful menu click must not silently edit
    /// a renderer that is currently hidden, nor announce an unconfirmed value.
    @discardableResult
    func adjustSubtitleProperty(_ property:String,delta:Double=0,reset:Bool=false) -> Bool {
        guard ["sub-scale","sub-delay","sub-pos","audio-delay"].contains(property) else{return false}
        if embeddedBackend {return adjustEmbeddedSubtitleProperty(property,delta:delta,reset:reset)}
        if refuseEmbedded("subtitle/audio property "+property) {return false}
        let command=reset ? MPVCommand.make(["set_property",property,property == "sub-scale" ? 1 : property == "sub-pos" ? 100 : 0]) : MPVCommand.make(["add",property,delta])
        let payload=command+"\n"+MPVCommand.make(["get_property",property])
        let lines=ipcClient.queryBatch(payload,timeout:0.3)
        let replies=lines.compactMap{line->[String:Any]? in
            guard let data=line.data(using:.utf8) else{return nil}
            return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        }
        let reply=IPCClient.parseFirst(lines)
        guard replies.first?["error"] as? String == "success",let value=reply["data"] as? Double,value.isFinite else{
            spineUI.showMPVOSD("subtitle control unavailable",duration:1.5,force:true);return false
        }
        if property == "sub-scale" {
            pendingSubtitleModeScale=nil
            subtitleModeScale.accept(value)
            SubtitleSizePreference.save(value,pictureInPicture:subtitleModeScale.pictureInPicture)
            if reset {subtitleView.resetSubtitleFontSize()}
            else {subtitleView.setSubtitleFontScale(value)}
        }
        if property == "sub-delay" {subtitleView.setSubtitleDelay(value)}
        if property == "sub-pos" {pendingSubtitleModePosition=nil;subtitleView.setSubtitlePosition(value,force:true)}
        let label=property == "audio-delay" ? "audio delay" : property == "sub-scale" ? "subtitle font size" : property == "sub-delay" ? "subtitle delay" : "subtitle position"
        let amount=property.hasSuffix("delay") ? String(format:"%+.1fs",value) : property == "sub-scale" ? String(format:"%.0f%%",value*100) : String(format:"%.0f%%",value)
        spineUI.showMPVOSD(label+": "+amount,duration:1.5,force:true)
        return true
    }
    // gorav: the embedded session draws subtitles in its own presenter. sub-scale is accepted
    // through that real cue presenter; sub-pos uses measured bounded cue placement.
    // Delays, position and scale are committed and
    // announced only after the session accepted them. Values are session-only.
    private var embeddedSubDelay=0.0
    private var embeddedAudioDelay=0.0
    private var embeddedSubScale=1.0
    private var embeddedSubPosition=100.0
    func acceptEmbeddedSubtitlePosition(_ percent:Double) {
        guard percent.isFinite,(0...100).contains(percent) else{return}
        embeddedSubPosition=percent
    }
    @discardableResult
    func applyEmbeddedSubtitlePosition(_ percent:Double)->Bool {
        guard percent.isFinite,(0...100).contains(percent),let apply=embeddedSubtitlePosition else{return false}
        if let reason=apply(percent) {
            spineUI.showMPVOSD("gorav unavailable: "+reason,duration:1.5,force:true);return false
        }
        embeddedSubPosition=percent
        spineUI.showMPVOSD("subtitle position: "+String(format:"%.0f%%",percent),duration:1.5,force:true)
        return true
    }
    private func adjustEmbeddedSubtitleProperty(_ property:String,delta:Double,reset:Bool)->Bool {
        if property == "sub-pos" {return applyEmbeddedSubtitlePosition(reset ? 100:embeddedSubPosition+delta)}
        if property == "sub-scale" {
            let target=reset ? 1.0 : embeddedSubScale+delta
            guard target.isFinite, let apply=embeddedSubtitleScale else {
                _=refuseEmbedded("subtitle font size")
                return false
            }
            if let reason=apply(target) {
                spineUI.showMPVOSD("gorav unavailable: "+reason,duration:1.5,force:true)
                return false
            }
            embeddedSubScale=target
            spineUI.showMPVOSD("subtitle font size: "+String(format:"%.0f%%",target*100),duration:1.5,force:true)
            return true
        }
        guard property == "sub-delay" || property == "audio-delay" else {
            _=refuseEmbedded("subtitle position")
            return false
        }
        let current=property == "sub-delay" ? embeddedSubDelay : embeddedAudioDelay
        let target=reset ? 0 : current+delta
        guard let apply=embeddedDelay else {_=refuseEmbedded(property);return false}
        if let reason=apply(property,target) {
            spineUI.showMPVOSD("gorav unavailable: "+reason,duration:1.5,force:true)
            return false
        }
        if property == "sub-delay" {embeddedSubDelay=target} else {embeddedAudioDelay=target}
        spineUI.showMPVOSD((property == "sub-delay" ? "subtitle delay: " : "audio delay: ")+String(format:"%+.1fs",target),duration:1.5,force:true)
        return true
    }
    func resetSubtitles() {
        let scale=adjustSubtitleProperty("sub-scale",reset:true)
        let delay=adjustSubtitleProperty("sub-delay",reset:true)
        let position=adjustSubtitleProperty("sub-pos",reset:true)
        if scale && delay && position {spineUI.showMPVOSD("subtitles reset",duration:1.5,force:true)}
    }

    // MARK: - Track list

    /// Fresh on every native menu opening. Do not reuse the legacy dropdown cache.
    var windowMenuVideoSize:CGSize {
        let aspect:Double
        if vrModeEnabled,let p=StereoMenuGeometry.plan(sourceAspect:vr180Controller?.flatUIEyeAspect ?? stereoProjectionBaseAspect ?? 1,aspectOverride:stereoManualAspect,cropAspect:stereoMenuCropAspect,gap:effectiveVrGap?.value ?? 0) {aspect=p.windowAspect}
        else {aspect=stereoManualAspect ?? manualMenuCropAspect ?? appliedSourceCropAspect ?? cropMPV.displayedFilter.map { GorCropPlan.effectiveAspect($0) } ?? videoLayoutAspect ?? nativeVideoAspect ?? (videoDisplayH>0 ? videoDisplayW/videoDisplayH : 16.0/9.0)}
        let height=max(1,videoDisplayH)
        return CGSize(width:height*aspect,height:height)
    }

    func nativeOnTopState()->Bool? {
        if embeddedBackend {return window?.level == .floating}
        return IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","ontop"]}"#,timeout:0.15))["data"] as? Bool
    }

    func nativeTrackSnapshot() -> (path:String,tracks:[[String:Any]]) {
        if refuseEmbedded("audio/subtitle track snapshot") {return (currentFilePath,[])}
        let path=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","path"]}"#,timeout:0.15))["data"] as? String ?? ""
        let tracks=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","track-list"]}"#,timeout:0.15))["data"] as? [[String:Any]] ?? []
        let after=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","path"]}"#,timeout:0.15))["data"] as? String ?? ""
        return path == after ? (path,tracks) : ("",[])
    }

    func fetchTrackList(type: String, completion: @escaping ([(id: Int, title: String)]) -> Void) {
        if refuseEmbedded(type == "sub" ? "embedded subtitle track selection":"audio track selection") {completion([]);return}
        print("[fetchTrackList] type: \(type), ipcPath exists: \(FileManager.default.fileExists(atPath: ipcPath))")

        let requestedPath=currentFilePath
        guard FileManager.default.fileExists(atPath: ipcPath) else { completion([]); return }

        let json     = "{\"command\":[\"get_property\",\"track-list\"]}"
        let ipcLocal = ipcClient

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let lines = ipcLocal.queryBatch(json)
            let obj   = IPCClient.parseFirst(lines)
            guard let list = obj["data"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let targetType = type == "sub" ? "sub" : "audio"
            let tracks: [(id: Int, title: String)] = list.compactMap { track in
                guard let tid   = track["id"]   as? Int,
                      let ttype = track["type"] as? String,
                      ttype == targetType
                else { return nil }
                let title = (track["title"] as? String)
                          ?? (track["lang"]  as? String)
                          ?? "Track \(tid)"
                return (id: tid, title: title)
            }
            DispatchQueue.main.async {
                guard self.currentFilePath==requestedPath else {completion([]);return}
                completion(tracks)
            }
        }
    }

    // MARK: - Commands

    /// gor 514 v5: geometry write through the persistent connection so mpv's reply (request_id) reaches
    /// onLine. Returns false when the connection is down (caller falls back to the untracked write).
    var persistentConnectionUp: Bool { persistentConnection.isConnected }

    /// True only when gor-fit.lua is installed in the seeded scripts folder (set at mpv launch).
    static var gorFitScriptActive = false

    /// Every gor-initiated window frame goes through here. With gor-fit.lua it is an eased 140 ms move
    /// (script-message "animate"); without it, the old direct geometry write.
    private static func geometryCommandJSON(_ geom: String, requestId: Int?) -> String {
        let rid = requestId.map { ",\"request_id\":\($0)" } ?? ""
        if gorFitScriptActive {
            return "{\"command\":[\"script-message-to\",\"gor_fit\",\"animate\",\"\(geom)\"]\(rid)}"
        }
        return "{\"command\":[\"set_property\",\"geometry\",\"\(geom)\"]\(rid)}"
    }

    func cancelFitAnimation() {
        interruptCropMotion()
        guard !embeddedBackend,Self.gorFitScriptActive else { return }
        ipcCommand(MPVCommand.make(["script-message-to", "gor_fit", "cancel"]))
    }

    func sendGeometryUntracked(_ geom: String) {
        ipcCommand(Self.geometryCommandJSON(geom, requestId: nil))
    }

    /// Screen metrics for gor-fit.lua (usable size, backing scale, window chrome), pushed as mpv user-data so the
    /// next file is sized from the screen the window is on. Same inputs the old opening fit used.
    static var lastFitMetrics: String?
    static var lastFitAnchor: String?
    func pushFitMetrics() {
        guard Self.gorFitScriptActive, let value = GorOpeningFit.fitMetricsString(screen: window?.screen ?? NSScreen.main, separator: ",") else { return }
        Self.lastFitMetrics = value
        if let win=window,let screen=win.screen ?? NSScreen.main,
           let anchor=GorOpeningFit.clampGeometry(frame:win.frame,screen:screen) {
            Self.lastFitAnchor=anchor
            playbackOperations.fitAnchor(anchor)
        }
        ipcCommand(MPVCommand.make(["set_property", "user-data/gor/fit", value]))
    }

    func sendTrackedGeometry(_ geom: String, requestId: Int) -> Bool {
        guard persistentConnection.isConnected else { return false }
        persistentConnection.write(Self.geometryCommandJSON(geom, requestId: requestId))
        return true
    }

    /// r before playback (owner order 2026-11-15): jump to a random playlist
    /// entry so the selection starts playing; a no-op without a playlist.
    /// playlist-count is queried synchronously (0.3 s cap, same pattern as
    /// refreshEffectiveGap); the draw uses the shared crypto source.
    func randomPlaylistEntry() {
        let lines = ipcClient.queryBatch(#"{"command":["get_property","playlist-count"]}"#, timeout: 0.3)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["error"] as? String == "success",
                  let n = reply["data"] as? Int, n > 1,
                  let index = ArchiveRandom.shared.chooseIndex(count: n) else { continue }
            ipcCommand(#"{"command":["set_property","playlist-pos",\#(index)]}"#)
            return
        }
    }

    func ipcCommand(_ json: String) {
        if embeddedBackend {embeddedCommand?(json);return}
        var continuousPose=false,continuousLids=false
        if let data=json.data(using:.utf8),let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           let command=object["command"] as? [Any],let name=command.first as? String {
            if name == "stop" {beginMediaTransition()}
            if name == "loadfile",command.count>1,let path=command[1] as? String,
               Self.isReplacingLoadfile(command),
               !ThreeDRecognitionBridge.internalMedia(path),
               !(ThreeDRecognitionBridge.internalMedia(currentFilePath) && path==sourceFilmPath) {
                // An appended file must not fence the one playing now; only a replacing loadfile transitions.
                beginMediaTransition()
                pushLiveFitAnchor()
            }
            if ["stop","loadfile","quit","quit-watch-later"].contains(name) {
                // Only a replacing loadfile retires the file that is playing; an appended one leaves the
                // active file's camera/dimming/WT/pose state alone (start-file handles it when it begins).
                let retiresActive = name != "loadfile" || Self.isReplacingLoadfile(command)
                if retiresActive {
                    if name == "quit" || name == "quit-watch-later" {ipcClient.closeLatestPose()}
                    else {ipcClient.cancelLatestPose()}
                    sendWTPlaybackEvent(name)
                    cameraFileGeneration &+= 1
                    ambientPlaybackFileEnded = true
                    setCameraPlaybackActive(false)
                }
            }
            if name == "script-message-to",command.count>2,command[1] as? String == "vr180_look" {
                continuousPose = command[2] as? String == "vr180-look-set-orientation" && object["request_id"] == nil
                continuousLids = command[2] as? String == "vr180-look-set-lids"
                let poseBarrier = command[2] as? String == "vr180-look-full-fit" || (command[2] as? String == "vr180-look-set-orientation" && object["request_id"] != nil)
                if poseBarrier || (command[2] as? String == "vr180-look-set-enabled" && command.count>3 && command[3] as? String == "false") {ipcClient.cancelLatestPose()}
            }
        }
        // Pause intent wins even before the first playing poll is delivered.
        // Both the local key monitor and the view fallback use this path.
        if let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let command = object["command"] as? [Any], command.count >= 2,
           let name = command[0] as? String, let target = command[1] as? String {
            if (["cycle","set","set_property"].contains(name) && target=="pause") ||
               (name=="keypress" && ["SPACE","PLAYPAUSE"].contains(target)) {
                // Any explicit pause-state command wins over the automatic closed-eyes pause,
                // including a repeated manual pause=true that generates no property change.
                persistentConnection.write(#"{"command":["script-message-to","vr180_look","vr180-look-manual-playback"]}"#)
            }
            if (name == "cycle" && target == "pause" && !isPlaying) ||
               ((name == "set" || name == "set_property") && target == "pause" &&
                command.count > 2 && (command[2] as? Bool == false || command[2] as? String == "no")) {
                cameraPauseIntentPending = false
            }
            if (name == "cycle" && target == "pause" && isPlaying) ||
               ((name == "set" || name == "set_property") && target == "pause" &&
                command.count > 2 && (command[2] as? Bool == true || command[2] as? String == "yes")) {
                cameraPauseIntentPending = true
                vr180Controller?.playbackActive = false
            }
            if name == "seek" {
                if !embeddedBackend,!vrModeEnabled,!surfaceToolsEnabled,Self.gorFitScriptActive {
                    playbackOperations.fenceCropSeek()
                }
                fenceCropMeasurementForSeek()
                wtPlaybackEnded = false
                sendWTPlaybackEvent("seek-intent")
            }
            if (name == "cycle" && target == "pause") ||
               (name == "keypress" && (target == "SPACE" || target == "PLAYPAUSE")) {
                wtUserPauseIntent = isPlaying
                if wtUserPauseIntent { sendWTPlaybackEvent("user-pause") }
            } else if (name == "set" || name == "set_property") && target == "pause" && command.count > 2 {
                wtUserPauseIntent = command[2] as? Bool == true || command[2] as? String == "yes"
                if wtUserPauseIntent { sendWTPlaybackEvent("user-pause") }
            }
            if target == "fullscreen" {
                (NSApp.delegate as? AppDelegate)?.prepareMPVFullscreenTransition()
                (NSApp.delegate as? AppDelegate)?.cancelPendingMPVMinimize()
            }
            if (name == "cycle" && target == "pause") ||
               (name == "keypress" && (target == "SPACE" || target == "PLAYPAUSE")) ||
               ((name == "set" || name == "set_property") && target == "pause") {
                autoPlayTried = true
            }
        }
        if continuousLids {ipcClient.sendLatestLids(json)}
        else if continuousPose {ipcClient.sendLatestPose(json)}
        else {ipcClient.send(json)}
    }

    /// Only a replacing loadfile (mode absent or "replace") swaps the active file; append/append-play queue
    /// behind it, so they must neither start the media-transition fence nor push a live fit anchor. Structural
    /// parse of the command array, never a substring match: a filename containing "append" is not a mode.
    static func isReplacingLoadfile(_ command: [Any]) -> Bool {
        guard (command.first as? String) == "loadfile", command.count > 1 else { return false }
        if command.count > 2, let mode = command[2] as? String { return mode == "replace" }
        return true
    }

    /// Live anchor for a replacing loadfile sent on the single-command channel (music-mode video open, drag
    /// replace): the same numbers batchWithFitMetrics computes, pushed ahead of the loadfile so gor-fit.lua
    /// never has to fall back to a stale pushed anchor on this path either.
    func pushLiveFitAnchor() {
        guard Self.gorFitScriptActive else { return }
        if Thread.isMainThread, let win=window, let screen=win.screen ?? NSScreen.main,
           let anchor=GorOpeningFit.clampGeometry(frame:win.frame,screen:screen) {
            Self.lastFitAnchor=anchor
        }
        if let anchor=Self.lastFitAnchor {
            playbackOperations.fitAnchor(anchor)
        }
    }

    /// A replacing loadfile carries the screen metrics of the screen the window is on NOW, ahead of it in the same
    /// ordered batch, so gor-fit.lua sizes the first frame from fresh numbers (not the previous open's screen).
    /// Main thread: computed live. Other threads: the last value pushed (screen-change observers keep it current).
    /// Each batch line is parsed structurally; only a replacing loadfile arms metrics+anchor, so an appended
    /// file (or a filename containing "append") no longer decides the active file's fit inputs.
    func batchWithFitMetrics(_ payload: String) -> String {
        guard Self.gorFitScriptActive else { return payload }
        var replacing = false
        for line in payload.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = object["command"] as? [Any] else { continue }
            if Self.isReplacingLoadfile(command) { replacing = true; break }
        }
        guard replacing else { return payload }
        var value = Self.lastFitMetrics
        if Thread.isMainThread,
           let live = GorOpeningFit.fitMetricsString(screen: window?.screen ?? NSScreen.main, separator: ",") {
            value = live; Self.lastFitMetrics = live
            if let win=window,let screen=win.screen ?? NSScreen.main {
                Self.lastFitAnchor=GorOpeningFit.clampGeometry(frame:win.frame,screen:screen)
            }
        }
        guard let v = value else { return payload }
        return PlayerFitProtocol.fitBatch(payload,metrics:v,anchor:Self.lastFitAnchor)
    }

    func batchIPC(_ rawPayload: String, timeout: TimeInterval = 5.0) {
        if embeddedBackend {for line in rawPayload.split(separator:"\n") {embeddedCommand?(String(line))};return}
        let payload = batchWithFitMetrics(rawPayload)
        let client = ipcClient
        IPCClient.cmdQueue.async {
            let diagnosticOldThreadName = Thread.current.name
            Thread.current.name = "ipc.cmd"
            defer { Thread.current.name = diagnosticOldThreadName }
            _ = client.queryBatch(payload, timeout: timeout)
        }
    }

    // I11 / TRAP-04: drag file routing must agree with DragDropHandler (PPController_Features.swift).
    // Coupled: DragDropHandler.start() (PPController_Features.swift); edit both drag paths together.
    func openMediaFile(_ path: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.openMediaFile(path) }
            return
        }
        // Every local entrypoint goes through the selected engine, including
        // menu and drag opens on an already-created mpv controller.
        if let app=NSApp.delegate as? AppDelegate,app.routeLocalOpen(path:path) {return}
        openMediaFileOnMPV(path)
    }
    func openMediaFileOnMPV(_ path:String) {
        // Invalidate queued YouTube recovery before a local/archive load is sent.
        (NSApp.delegate as? AppDelegate)?.invalidateYoutubeRecovery()
        if musicModeController?.isMusicMode == true { musicModeController?.toggleMusicMode() }
        if iptvModeController?.isIptvMode == true { iptvModeController?.toggleIptvMode() }
        // A local file is not an IPTV channel: the poll prefers iptvChannelTitle whenever it is set.
        iptvChannelTitle = ""
        (NSApp.delegate as? AppDelegate)?.stopTorrent()
        TunnelForBlockedHosts.shared.willLoad(path)
        // Per-file baseline before the open (pass-5 #7).
        (NSApp.delegate as? AppDelegate)?.restoreDefaultProfile()
        let photonEnabled = (NSApp.delegate as? AppDelegate)?.photonEnabled ?? false
        let batch = [
            #"{"command":["script-message-to","photon","set-user-enabled","\#(photonEnabled ? "true" : "false")"]}"#,
            // force-media-title set by a stream/archive/magnet load stays set in mpv; clear it so a
            // local file shows its own title instead of the previous source's.
            MPVCommand.make(["set_property", "force-media-title", ""]),
            MPVCommand.make(["loadfile", path]),
        ].joined(separator: "\n")
        batchIPC(batch)
        isTorrentStopped = false
    }

    func togglePlay()              { ipcCommand(#"{"command":["cycle","pause"]}"#) }
    func seekRelative(_ s: Double) {
        ipcCommand("{\"command\":[\"seek\",\"\(String(format:"%.1f",s))\",\"relative\"]}")
        pollEngine.kick()
    }
    func seek(to p: Double) {
        ipcCommand("{\"command\":[\"seek\",\"\(String(format:"%.2f",p*duration))\",\"absolute\"]}")
        pollEngine.kick()
    }
    
    var isTorrentStopped = false
    var pendingStreamStartPos: Double?
    private var lastSentPlayhead: Double = -999
    private var lastSentPlayheadAt: Date = .distantPast

    /// One transport for every wt_server control POST; only path/body differ.
    private func postToWTServer(path: String, body: Data, contentType: String? = nil, token:String?=nil) {
        PlayerTorrentEndpoint.withControlURL(for:currentFilePath,token:token,path:path) { url in
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            req.httpBody = body
            URLSession.shared.dataTask(with: req).resume()
        }
    }

    private var wtUserPauseIntent = false
    private var wtPlaybackEnded = false
    private var wtObservedToken: String?
    private var wtLastPosition: Double?
    private var wtLastDuration: Double?
    private var wtLastPositionAt: TimeInterval?
    private var wtEventSequence = 0

    private static func wtPlaybackToken(_ path: String) -> String? {
        PlayerTorrentEndpoint.playbackToken(path)
    }

    private func sendWTPlaybackEvent(_ event: String) {
        guard let token = wtObservedToken,Self.wtPlaybackToken(currentFilePath)==token else { return }
        wtEventSequence += 1
        var payload: [String: Any] = ["event": event, "token": token, "sequence": wtEventSequence,
                                      "userPaused": wtUserPauseIntent]
        if let position = wtLastPosition { payload["playhead"] = position }
        if let sampledAt = wtLastPositionAt {
            payload["positionAge"] = max(0, ProcessInfo.processInfo.systemUptime - sampledAt)
        }
        if let duration = wtLastDuration { payload["duration"] = duration }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        postToWTServer(path: "/playback", body: data, contentType: "application/json",token:token)
    }

    func sendPlayheadToWTServer(_ time: Double, duration dur: Double = 0, mediaPath: String? = nil) {
        guard !wtPlaybackEnded, let mediaPath, let token = Self.wtPlaybackToken(mediaPath) else { return }
        let now      = Date()
        let timeDiff = abs(time - lastSentPlayhead)
        let ageSec   = now.timeIntervalSince(lastSentPlayheadAt)
        guard timeDiff > 1.0 || ageSec > 3.0 else { return }
        lastSentPlayhead   = time
        lastSentPlayheadAt = now

        wtEventSequence += 1
        let body: [String: Any] = ["playhead": time, "duration": dur, "token": token, "sequence": wtEventSequence]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        postToWTServer(path: "/pos", body: data, contentType: "application/json",token:token)
    }

    private var wtRecoveryInFlight = false
    private var wtLastRecoveryAt = Date.distantPast

    func recoverFrozenWTStream(token: String) {
        guard token == wtObservedToken, !wtUserPauseIntent, !cameraPlaybackShutDown,
              !wtRecoveryInFlight, Date().timeIntervalSince(wtLastRecoveryAt) >= 30 else { return }
        // A validated final EOF must keep its countdown, not restart the episode.
        if wtPlaybackEnded, let position = wtLastPosition, let duration = wtLastDuration,
           abs(duration - position) <= 2 { return }
        wtRecoveryInFlight = true
        wtLastRecoveryAt = Date()
        let client = ipcClient
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lines = client.queryBatch(#"{"command":["get_property","path"],"request_id":9101}"#)
            let path = IPCClient.parseFirst(lines)["data"] as? String
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.wtRecoveryInFlight = false
                guard !self.wtUserPauseIntent, !self.cameraPlaybackShutDown,
                      token == self.wtObservedToken, let path,
                      Self.wtPlaybackToken(path) == token,
                      (NSApp.delegate as? AppDelegate)?.currentTorrentURL == path else { return }
                let position = self.wtLastPosition ?? 0
                self.sendWTPlaybackEvent("recover")
                self.wtPlaybackEnded = false
                (NSApp.delegate as? AppDelegate)?.playMedia(
                    url: path, title: (NSApp.delegate as? AppDelegate)?.torrentTitle ?? "Torrent", startPos: position)
                print("[wt] same-file recovery token=\(token) position=\(position)")
            }
        }
    }

    func reloadStream() {
        postToWTServer(path: "/cmd", body: Data("SKIP\n".utf8))
    }

    // WT /cmd derivation, import-free and pure so the sender policy compiles
    // into the swiftc test harness without a server. A resume is never gated:
    // a pause-to-playing edge proves playback is running again, so a stale
    // keep-open EOF latch must clear on the resume edge or every later user
    // pause is swallowed as well (owner log via Main 2026-11-19: the pause
    // reached WT, the resume never did, and the position kept advancing).
    static func wtPauseCommand(isPlaying: Bool, playbackEnded: Bool) -> String? {
        if isPlaying { return "RESUME" }
        // keep-open's automatic EOF pause is not a user pause or a countdown cancel.
        return playbackEnded ? nil : "PAUSE"
    }

    func sendPauseStateToWTServer(isPlaying: Bool) {
        guard let command = Self.wtPauseCommand(isPlaying: isPlaying, playbackEnded: wtPlaybackEnded) else { return }
        if isPlaying {
            // Playback verifiably runs again; the EOF latch is stale.
            wtPlaybackEnded = false
        } else {
            sendWTPlaybackEvent("pause")
        }
        postToWTServer(path: "/cmd", body: Data((command + "\n").utf8))
    }

    func resumeStream() {
        postToWTServer(path: "/cmd", body: Data("REWINDOW\n".utf8))
    }

    func rewindowStream() {
        pendingStreamStartPos = nil
        isTorrentStopped = false
        resumeStream()
    }

    func stopStream() {
        isTorrentStopped = true
        ipcCommand(#"{"command":["stop"]}"#)
        TunnelForBlockedHosts.shared.stopOrQuit()
        (NSApp.delegate as? AppDelegate)?.stopTorrent()
        iptvChannelTitle = ""
        spineUI.setTitle("")
        sidebarUI.update(currentTime: 0, duration: 0, progress: 0, volume: volume)
        spineUI.clearMPVOSD(animated: true)
        spineUI.hideStreamControls()
    }
    
    func setVolume(_ v: Float) {
        volume = max(0, min(1, v))
        ipcCommand("{\"command\":[\"set_property\",\"volume\",\(Int(volume*100))]}")
    }
    func currentProgress() -> Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    func osdString() -> String {
        String(format: "pos %05.1f\ndur %05.1f\nvol %03d\n%03d%%",
               currentTime, duration, Int(volume*100), Int(currentProgress()*100))
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (NSApp.delegate as? AppDelegate)?.isDragging = true
        window?.ignoresMouseEvents = false
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        (NSApp.delegate as? AppDelegate)?.isDragging = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        (NSApp.delegate as? AppDelegate)?.isDragging = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (NSApp.delegate as? AppDelegate)?.isDragging = false
        return true
    }

    // MARK: - Subtitle menu

    func showSubtitleMenu(from v: NSView) {
        let menu = NSMenu()
        let c    = NSMenuItem(title: "Next Channel", action: #selector(cycleSubtitle), keyEquivalent: "")
        c.target = self; menu.addItem(c)
        let l    = NSMenuItem(title: "Load SRT…", action: #selector(loadSRT), keyEquivalent: "")
        l.target = self; menu.addItem(l)
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: v)
    }
    @objc func cycleSubtitle() { ipcCommand(#"{"command":["cycle","sub"]}"#) }
    @objc func loadSRT() {
        let panel = NSOpenPanel()
        panel.begin { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            self?.ipcCommand(MPVCommand.make(["sub-add", url.path]))
        }
    }

    private var lastSubtitleProbeAt: TimeInterval = 0
    private func recordSubtitleProbe(results: [String:Any], nativeReported: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastSubtitleProbeAt >= 1 else { return }
        lastSubtitleProbeAt = now
        let geometry = subtitleView.vrReplicaTraceState()
        func rect(_ r: CGRect?) -> Any {
            guard let r else { return NSNull() }
            return [Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)]
        }
        var row: [String:Any] = ["timestamp":Date().timeIntervalSince1970,"pid":ProcessInfo.processInfo.processIdentifier,
            "build":BuildID.value(),"liveCaptionActive":LiveCaptionController.shared.isActive,
            "subtitleOwner":nativeReported ? "native":"custom", "viewHidden":subtitleView.isHidden,
            "subRaw":rect(geometry.raw),"subClip":rect(geometry.clip),"subContent":rect(geometry.content)]
        row.merge(subtitleView.typographyProbe){_,new in new}
        for key in ["current-tracks/sub/id","secondary-sid","current-tracks/sub/codec","sub-text","sub-start","sub-end",
                    "sub-visibility","secondary-sub-visibility","sub-scale","sub-delay","sub-pos","audio-delay","path"] {
            if let value=results[key] { row[key]=value }
        }
        guard JSONSerialization.isValidJSONObject(row),let data=try? JSONSerialization.data(withJSONObject:row,options:.sortedKeys) else{return}
        // Latest state receipt, not a log. Bounded overwrite does not touch append-only logs.
        try? data.write(to:URL(fileURLWithPath:NSTemporaryDirectory()+"gor-subtitle-state.json"),options:.atomic)
    }

    // MARK: - Live caption
    func toggleLiveCaption(languageCode: String? = nil) -> Bool {
        if refuseEmbedded("live caption") {return false}
        let caption = LiveCaptionController.shared
        if caption.isActive {
            caption.stop()
            SubtitleView.Config.liveCaptionActive = false
            subtitleView.show(text: "", duration: 0.2, at: currentTime)
            return false
        }
        caption.preferredLanguage = languageCode
        caption.start()
        // start() can refuse missing assets/model or fail to launch synchronously.
        // Never report ON or suppress mpv cues unless a process actually started.
        let active = caption.isActive
        SubtitleView.Config.liveCaptionActive = active
        guard active else { return false }
        subtitleView.isHidden = false
        subtitleView.show(text: "", duration: 0.2, at: currentTime)
        subtitleView.moveToDefaultPosition(2)
        return true
    }

    // MARK: - mpv event dispatch

    private func handleMPVEvent(_ name: String, _ obj: [String: Any]) {
        switch name {
        case "audio-reconfig":
            ScreenCaptureEngine.shared.signalAudioReconfig()
        case "start-file":
            DispatchQueue.main.async { [weak self] in
                self?.beginMediaTransition(suspendRender:false)
                self?.beginFilmIdentity()
                self?.resetCropForOpening()
                self?.cameraFileGeneration &+= 1
                self?.sendWTPlaybackEvent("start-file")
                self?.wtObservedToken = nil
                self?.wtLastPosition = nil
                self?.wtLastDuration = nil
                self?.wtLastPositionAt = nil
                self?.ambientPlaybackFileEnded = true
                self?.setCameraPlaybackActive(false)
                self?.cropDetector.cancel()
                self?.cropDetector.resetLastFile()
                self?.cropDetector.resetMainPlayback(active: false)
            }
        case "file-loaded":
            // Bump before primeDims so observers of the generation always
            // see it ahead of any dimension-driven work for the new file.
            fileLoadedGeneration += 1
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.mediaTransitionLoaded=true
                self.requestFilmIdentity()
                self.ambientPlaybackFileEnded = false
                // gor 514 E1/v5: the FIRST file-loaded of the current
                // opening keeps the open identity minted at the path
                // change (dims may already have applied; the consumed arm
                // makes this a no-op, so a user resize is safe). A
                // file-loaded after an intervening end-file is a
                // structural same-path reopen and mints the next identity
                // (E1) without touching currentFilePath. A file-loaded
                // with NO intervening end-file is a duplicate of the
                // current opening: no re-mint, no possible re-apply.
                if self.openingFitAwaitingFirstLoad {
                    self.openingFitAwaitingFirstLoad = false
                } else if self.openingFitSawEndFile {
                    self.openingFitSawEndFile = false
                    // gor 514 v6: a live NON-baseline arm (music-exit
                    // resume, 0.38) OWNS the load that follows its own
                    // stop end-file - keep its identity and fraction
                    // instead of re-minting to baseline (order end-file
                    // -> file-loaded -> dims). The same hold applies when
                    // the resume fit already fired before this file-loaded
                    // (order end-file -> dims -> file-loaded): the load
                    // belongs to the same resume, and a fresh baseline arm
                    // here would allow a second refit overriding the
                    // resumed size (or a user resize after it).
                    let musicExitOwnsThisLoad =
                        (self.openingFitArmedOpen != nil
                         && self.openingFitPendingFraction != GorVideoFit.openBaselineFraction)
                        || self.openingFitNonBaselineApplied
                    self.openingFitNonBaselineApplied = false
                    if !musicExitOwnsThisLoad {
                        self.mintOpeningFitOpen(fraction: GorVideoFit.openBaselineFraction)
                    }
                }
                if self.lastDisplayDimsValid,
                   self.lastDisplayDimsPath == self.currentFilePath {
                    self.applyOpeningFitIfArmed(videoW: self.videoDisplayW,
                                                videoH: self.videoDisplayH)
                }
                self.cameraPauseIntentPending = false
                self.cropDetector.cancel()
                self.cropDetector.resetLastFile()
                self.cropDetector.resetMainPlayback(active: true)
                self.synchronizeLoadedVideoCamera()
            }
            TunnelForBlockedHosts.shared.fileLoaded()
            onFileLoaded?(fileLoadedGeneration)
            pollEngine.primeDims()
            pollEngine.kick()
        case "end-file":
            let reason = obj["reason"] as? String ?? "unknown"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let alreadyEnded = self.wtPlaybackEnded
                self.wtPlaybackEnded = true
                if reason != "eof" || !alreadyEnded {
                    self.sendWTPlaybackEvent(reason == "eof" ? "eof" : "end-\(reason)")
                }
                self.cameraFileGeneration &+= 1
                self.ambientPlaybackFileEnded = true
                self.setCameraPlaybackActive(false)
                self.cropDetector.resetMainPlayback(active: false)
                // gor 514 F3: consume a stale BASELINE arm at the terminal
                // (audio-only file, empty-path end) so it cannot fire on an
                // unrelated later dimension change. A music-exit arm (0.38)
                // is deliberately NOT consumed here: the exit's own stop
                // end-file always arrives after that arm is minted.
                // v5: the end-file is also the structural marker that makes
                // the NEXT file-loaded of the same path a reopen (E1).
                // Known gap (peer-noted, accepted, conservative): a LATE
                // end-file of the previous file arriving after the new
                // path's arm is minted consumes that fresh arm here - a
                // MISSED opening fit (mpv default size stands), never a
                // wrong resize. end-file carries no path, so the consume
                // cannot be path-matched without new state.
                self.beginMediaTransition(suspendRender:false)
                self.openingFitSawEndFile = true
                if self.openingFitPendingFraction == GorVideoFit.openBaselineFraction {
                    self.openingFitArmedOpen = nil
                }
            }
            TunnelForBlockedHosts.shared.fileEnded(reason: obj["reason"] as? String ?? "unknown")
        case "shutdown":
            DispatchQueue.main.async { [weak self] in
                self?.cameraFileGeneration &+= 1
                self?.ambientPlaybackFileEnded = true
                self?.setCameraPlaybackActive(false)
            }
        case "video-reconfig":
            pollEngine.primeDims()
            pollEngine.kick()
        case "seek":
            DispatchQueue.main.async { [weak self] in
                self?.fenceCropMeasurementForSeek()
                self?.rejectedCropRetryAvailable=true
                self?.sendWTPlaybackEvent("seek")
                self?.cropDetector.setMainPlaybackReady(false)
                // 199az: a seek restarts a pending search at once, and the reset is real: the retry
                // entry is dropped, any in-flight scan is cancelled (a delayed old-scan completion
                // dies on the retry-token guard, isPending clears, and the playback-restart trigger
                // scans afresh instead of bouncing off the old scan) and the last-file latch is cleared.
                if let self = self, !self.cropSearchOwnsSelection,
                   self.wtCropRetry[self.currentFilePath] != nil || self.cropDetector.isPending {
                    self.wtCropRetry[self.currentFilePath] = nil
                    self.cropDetector.cancel(); self.cropDetector.resetLastFile(); self.cropDetector.resetAutomaticWidenCursor()
                    print("[cropdetect] seek - crop search restarts with a fresh cadence")
                }
            }
            pollEngine.kick()
        case "playback-restart":
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cropSeekFenceActive=false
                self.wtPlaybackEnded = false
                self.sendWTPlaybackEvent("playback-restart")
                self.cropDetector.setMainPlaybackReady(true)
                self.startAutomaticCropDetection(needsRedetect:self.cropFreshMeasurementRequired)
                if Diag.mediaTelemetryEnabled, let playback = self.cropDetector.currentMainPlayback(),
                   playback != self.lastPlaybackFilenameGeneration {
                    self.lastPlaybackFilenameGeneration = playback
                    self.logPlaybackFilename(playback: playback)
                }
            }
            // Doubles as SCE's playback-start signal: re-runs a tap setup
            // whose retry budget expired before mpv had any audio to tap
            // (tapSetupArmedForPlayback). Cheap no-op when not armed.
            ScreenCaptureEngine.shared.signalPlaybackStart()
            pollEngine.kick()
            let generation = fileLoadedGeneration
            if generation > 0, generation != lastPlaybackDiagnosticGeneration {
                lastPlaybackDiagnosticGeneration = generation
                schedulePlaybackDiagnostic(generation: generation)
            }
        default:
            break
        }
    }

    // One bounded basename record at playback start. Shares the readiness identity.
    private func logPlaybackFilename(playback: Int) {
        guard Diag.mediaTelemetryEnabled else { return }
        let socket = ipcPath
        playbackDiagnosticQueue.async { [weak self] in
            guard let self, self.cropDetector.isMainPlaybackCurrent(playback) else { return }
            let lines = IPCClient(path: socket).queryBatch(
                #"{"command":["get_property","filename"]}"#, timeout: 0.6)
            guard let raw = IPCClient.parseFirst(lines)["data"] as? String else { return }
            let name: String
            if let url = URL(string: raw), url.scheme != nil {
                name = url.lastPathComponent
            } else {
                name = (raw.components(separatedBy: "?").first ?? "")
                    .components(separatedBy: "#").first ?? ""
            }
            let basename = (name as NSString).lastPathComponent
            let clean = basename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            let filename = String(String.UnicodeScalarView(clean).prefix(300))
            guard !filename.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: ["filename": filename], options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8),
                  self.cropDetector.isMainPlaybackCurrent(playback) else { return }
            Diag.mediaRecord("[playback-file] \(text)")
        }
    }

    // One bounded playback diagnostic per confirmed file generation.
    // IPCClient.queryBatch is synchronous: never run it on the event queue,
    // the 200ms poll, the UI thread, or IPCClient's shared command queue.
    private func schedulePlaybackDiagnostic(generation: Int) {
        let socket = ipcPath
        playbackDiagnosticQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            let stillCurrent = self.persistentConnection.workQueue.sync {
                self.fileLoadedGeneration == generation
            }
            guard stillCurrent else { return }
            let client = IPCClient(path: socket)
            func property(_ name: String) -> Any? {
                let request = ["command": ["get_property", name]]
                guard let bytes = try? JSONSerialization.data(withJSONObject: request),
                      let command = String(data: bytes, encoding: .utf8) else { return nil }
                let lines = client.queryBatch(command, timeout: 0.6)
                if lines.isEmpty { return "timeout-or-disconnected" }
                for line in lines {
                    guard let data = line.data(using: .utf8),
                          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          response["error"] as? String == "success" else { continue }
                    return response["data"]
                }
                return "unavailable"
            }
            func scalar(_ value: Any?) -> String {
                guard let value else { return "unavailable" }
                if let text = value as? String {
                    // Never log a path, stream URL, or token from an mpv field.
                    if text.contains("://") || text.contains("/") || text.contains("?") { return "redacted" }
                    let allowed = CharacterSet.alphanumerics
                        .union(CharacterSet(charactersIn: "-_.+"))
                    guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "redacted" }
                    return String(text.prefix(48))
                }
                if let number = value as? NSNumber { return String(describing: number) }
                return "unavailable"
            }
            // The mpv process is owned by AppDelegate. Read its PID on the
            // main queue; IPC's "pid" property is not guaranteed to exist.
            let pid = DispatchQueue.main.sync { () -> String in
                guard let process = (NSApp.delegate as? AppDelegate)?.mpvProcess,
                      process.isRunning else { return "unavailable" }
                return String(process.processIdentifier)
            }
            let hwdec = scalar(property("hwdec"))
            let current = scalar(property("hwdec-current"))
            let vfValue = property("vf")
            // A filter entry can contain a URL or user path in its arguments.
            let vf: String
            if let filters = vfValue as? [[String: Any]] {
                let knownNames: Set<String> = ["signalstats", "scale", "crop", "format", "lavfi"]
                let names = filters.prefix(5).map { entry -> String in
                    guard let name = entry["name"] as? String else { return "unnamed" }
                    return knownNames.contains(name) ? name : "other"
                }
                vf = names.isEmpty ? "none" : names.joined(separator: ",")
            } else {
                vf = scalar(vfValue)
            }
            func videoSummary(_ value: Any?) -> String {
                guard let dict = value as? [String: Any] else { return scalar(value) }
                let width = scalar(dict["w"] ?? dict["dw"])
                let height = scalar(dict["h"] ?? dict["dh"])
                return "\(width)x\(height)"
            }
            let video = videoSummary(property("video-params"))
            let decoder = videoSummary(property("video-dec-params"))
            let dropped = scalar(property("frame-drop-count"))
            let delayed = scalar(property("vo-delayed-frame-count"))
            let mistimed = scalar(property("mistimed-frame-count"))
            let avsync = scalar(property("avsync"))
            let currentBeforeLog = self.persistentConnection.workQueue.sync {
                self.fileLoadedGeneration == generation
            }
            guard currentBeforeLog else { return }
            let sameProcess = DispatchQueue.main.sync { () -> Bool in
                guard let process = (NSApp.delegate as? AppDelegate)?.mpvProcess,
                      process.isRunning else { return false }
                return String(process.processIdentifier) == pid
            }
            guard sameProcess else { return }
            // No file path or full property JSON appears.
            ThreadCpuDiag.recordPlaybackDecode("[thermal-diag] mpvPID=\(pid) generation=\(generation) hwdec=\(hwdec) hwdec-current=\(current) vf=\(vf) video=\(video) decode=\(decoder) drop=\(dropped) delayed=\(delayed) mistimed=\(mistimed) avsync=\(avsync)")
        }
    }

    // MARK: - Teardown

    deinit {
        stopCropFreshFollowthrough()
        pollEngine.stop()
        persistentConnection.stop()
        brightness.teardown()
        brightness.restore()
        cropMotionTimer?.invalidate()
        cropDetector.cancel()

        // cropDetector.cancel() closes only this detector's retained lifelines
        // and removes its own socket paths. Never name-kill another player's mpv.

    }
}

