// ================================================================
//  MenuActions.swift - main menu action handlers (AppDelegate extension)
//  Owns: all @objc menu* handlers, about panel, URL input panel,
//  aspect/VR mode state (currentAspectPreset, currentVRMode), playMedia
//  Contract: aspect actions always send `set` on video-aspect-override,
//  never add/cycle-values (mpv-player/mpv#13362)
// ================================================================
import AppKit
import Foundation
import CoreText
import ObjectiveC

// One native key panel owns both eye copies, so editing, IME, Escape and Return keep their
// existing responder/action lifecycle. The right eye maps back to those same live controls.
private var stereoPanelAssociation: UInt8 = 0
final class VRStereoPanelSession {
    weak var panel: NSPanel?
    weak var original: NSView?
    weak var parent: NSWindow?
    var lastParentFrame: CGRect = .zero
    private var sourceDepthOffset:CGFloat=0
    private var depthCommittedFrame:CGRect?
    private var savedPanelFrame: CGRect = .zero
    private var savedSourceFrame: CGRect = .zero
    private var savedBackground = NSColor.clear
    private var savedOpaque = false
    private var savedMovable = false
    let mirror = CALayer()
    let editorMirror = CALayer()
    var timer: Timer?
    init(panel: NSPanel, parent: NSWindow) {
        self.panel = panel
        self.parent = parent
        lastParentFrame = parent.contentRect(forFrameRect: parent.frame)
        guard let source = panel.contentView else { return }
        original = source
        savedPanelFrame = panel.frame; savedSourceFrame = source.frame
        savedBackground = panel.backgroundColor; savedOpaque = panel.isOpaque
        savedMovable = panel.isMovableByWindowBackground
        let oldFrame = panel.frame
        let parentContent = parent.contentRect(forFrameRect: parent.frame)
        let gap = CGFloat(PPController.vrPhysicalGap.value)
        let eyeWidth = parentContent.width * (0.5 - gap * 0.25)
        let width = min(source.bounds.width, max(100, eyeWidth - 16))
        let height = source.bounds.height
        let y = min(max(0, oldFrame.minY - parentContent.minY), max(0,parentContent.height-height))
        panel.setFrame(parentContent, display: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = false
        let host = NSView(frame: CGRect(origin: .zero, size: parentContent.size))
        host.wantsLayer = true
        panel.contentView = host
        source.frame = CGRect(x: (eyeWidth-width)*0.5, y:y, width:width, height:height)
        host.addSubview(source)
        let shift = parentContent.width * (0.5 + gap * 0.25)
        mirror.frame = source.frame.offsetBy(dx: shift, dy:0)
        mirror.contentsGravity = .resize
        host.layer?.addSublayer(mirror)
        host.layer?.addSublayer(editorMirror)
        let input = VRStereoControlInput(frame: host.bounds)
        input.host = host; input.sources = [source]; input.eyeShift = shift
        input.eyeClip = CGRect(x:shift,y:0,width:eyeWidth,height:parentContent.height)
        input.active = true
        host.addSubview(input)
        if let field = source.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
            field.frame.size.width = max(0,width-40)
        }
        // Keep the original/native field editor visible in both eyes while typing.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    var maximumContentWidth: CGFloat {
        guard let host=panel?.contentView else {return original?.bounds.width ?? 100}
        return max(100,host.bounds.width*(0.5-CGFloat(PPController.vrPhysicalGap.value)*0.25)-16)
    }
    func fit(width: CGFloat, height: CGFloat) {
        guard let source = original, let host = panel?.contentView else { return }
        let gap = CGFloat(PPController.vrPhysicalGap.value)
        let eyeWidth = host.bounds.width * (0.5-gap*0.25)
        let w = min(width,max(100,eyeWidth-16))
        source.frame = CGRect(x:(eyeWidth-w)*0.5+sourceDepthOffset,y:(host.bounds.height-height)*0.5,width:w,height:height)
        depthCommittedFrame=source.frame
        mirror.frame = source.frame.offsetBy(dx:host.bounds.width*(0.5+gap*0.25),dy:0)
    }
    private func refresh() {
        guard let panel, let original else { return }
        if let root = parent?.contentView {
            func player(_ view: NSView) -> PPController? {
                if let p = view as? PPController { return p }
                for child in view.subviews { if let p = player(child) {return p} }
                return nil
            }
            if player(root)?.vrModeEnabled != true {
                // The same native panel can outlive VR. Restore its original ownership and geometry,
                // not a stale full-player transparent input window when it is next shown in mono.
                timer?.invalidate(); timer=nil
                original.removeFromSuperview(); panel.contentView=original
                original.frame=savedSourceFrame
                panel.backgroundColor=savedBackground; panel.isOpaque=savedOpaque
                panel.isMovableByWindowBackground=savedMovable
                panel.setFrame(savedPanelFrame,display:panel.isVisible)
                objc_setAssociatedObject(panel,&stereoPanelAssociation,nil,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return
            }
        }
        guard panel.isVisible else {return}
        if let parent {
            let frame = parent.contentRect(forFrameRect: parent.frame)
            if frame != lastParentFrame {
                lastParentFrame = frame
                panel.setFrame(frame,display:true)
                panel.contentView?.frame.size = frame.size
                if let input = panel.contentView?.subviews.compactMap({ $0 as? VRStereoControlInput }).first {
                    let gap = CGFloat(PPController.vrPhysicalGap.value)
                    input.frame = CGRect(origin:.zero,size:frame.size)
                    input.eyeShift = frame.width*(0.5+gap*0.25)
                    input.eyeClip = CGRect(x:input.eyeShift,y:0,width:frame.width*(0.5-gap*0.25),height:frame.height)
                }
                fit(width: original.bounds.width,height:original.bounds.height)
            }
        }
        if let root=parent?.contentView,let host=panel.contentView {
            func player(_ v:NSView) -> PPController? {
                if let p=v as? PPController { return p }
                for c in v.subviews { if let p=player(c) {return p} };return nil
            }
            if let p=player(root) {
                let gap=CGFloat(PPController.vrPhysicalGap.value),eye=host.bounds.width*(0.5-gap*0.25)
                let (left,right)=p.uiDepthPlacement(eyeWidth:eye,scale:panel.backingScaleFactor)
                // Move the actual source view so AppKit hit-testing follows its displayed position.
                let prior = depthCommittedFrame == original.frame ? sourceDepthOffset : 0
                original.frame.origin.x += left-prior;sourceDepthOffset=left
                depthCommittedFrame=original.frame
                let shift=host.bounds.width*(0.5+gap*0.25)+right-left
                mirror.frame=original.frame.offsetBy(dx:shift,dy:0)
                if let input=host.subviews.compactMap({$0 as? VRStereoControlInput}).first { input.eyeShift=shift }
            }
        }
        guard let bitmap = original.bitmapImageRepForCachingDisplay(in: original.bounds) else { return }
        original.cacheDisplay(in: original.bounds, to: bitmap)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mirror.contents = bitmap.cgImage
        editorMirror.isHidden = true
        if let field = original.subviews.first(where: { $0 is NSTextField }) as? NSTextField,
           let editor = field.currentEditor() as? NSView, !editor.isDescendant(of: original), let host = panel.contentView,
           let rep = editor.bitmapImageRepForCachingDisplay(in:editor.bounds) {
            // AppKit may host the shared field editor outside the source view. Capture it explicitly.
            editor.cacheDisplay(in:editor.bounds,to:rep)
            editorMirror.frame = editor.convert(editor.bounds,to:host).offsetBy(dx:mirror.frame.minX-original.frame.minX,dy:0)
            editorMirror.contents = rep.cgImage
            editorMirror.isHidden = false
        }
        CATransaction.commit()
    }
    deinit { timer?.invalidate() }
}

extension NSPanel {
    var stereoSession: VRStereoPanelSession? {
        objc_getAssociatedObject(self, &stereoPanelAssociation) as? VRStereoPanelSession
    }
    func installStereoIfNeeded(parent: NSWindow?) {
        guard objc_getAssociatedObject(self, &stereoPanelAssociation) == nil, let parent,
              let root = parent.contentView else { return }
        func find(_ view: NSView) -> PPController? {
            if let player = view as? PPController { return player }
            for child in view.subviews { if let player = find(child) { return player } }
            return nil
        }
        guard let player = find(root), player.vrModeEnabled else { return }
        let session = VRStereoPanelSession(panel:self,parent:parent)
        objc_setAssociatedObject(self,&stereoPanelAssociation,session,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Borderless panels need an explicit key-window policy for Escape and click
/// dismissal. Without this, makeKeyAndOrderFront can leave the player key.
private final class GORAboutPanel: GORInputPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Draw at an explicit CoreText baseline so title ink and logo attachment
// use the same glyph bounds, including the g descender.
private final class GORAboutTextLayer: CALayer {
    var text = ""
    var textColor = NSColor.white
    private var textLine: CTLine?
    private var baseline: CGFloat = 0
    private var lineWidth: CGFloat = 0
    var leftInset: CGFloat?
    func setFont(_ font: CTFont) -> CGRect {
        let value = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: textColor])
        let line = CTLineCreateWithAttributedString(value)
        textLine = line
        let pathBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        baseline = max(abs(CTFontGetDescent(font)), -pathBounds.minY)
        lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        setNeedsDisplay()
        return pathBounds.offsetBy(dx: 0, dy: baseline)
    }
    override func draw(in context: CGContext) {
        guard let textLine else { return }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: leftInset ?? (bounds.width - lineWidth) / 2, y: baseline)
        CTLineDraw(textLine, context)
    }
}

extension AppDelegate {

    // MARK: - IPC Shortcut
    
    func cmd(_ json: String) { controller?.ipcCommand(json) }
    
    // MARK: - File Menu
    
    // playlist-play-index takes exactly one argument in mpv 0.41; the old
    // trailing "yes" made mpv reject the whole command, so reload did nothing.
    @objc func menuReload() { cmd(#"{"command":["playlist-play-index","current"]}"#) }
    @objc func menuStop()         { cmd(#"{"command":["stop"]}"#); TunnelForBlockedHosts.shared.stopOrQuit() }
    @objc func menuQuitSave()     { cmd(#"{"command":["quit-watch-later"]}"#) }

    /// Shift+Q - full quit-and-restart. Sets pendingRestart so
    /// applicationWillTerminate (AppDelegate.swift) relaunches this bundle
    /// after its cleanup, then drives the exact Cmd+Q termination path.
    @objc func menuRestartQuit() {
        pendingRestart = true
        NSApp.terminate(nil)
    }

    // MARK: - Playback Menu
    
    @objc func menuPlayPause()    { cmd(#"{"command":["cycle","pause"]}"#) }
    @objc func menuSeekF5()       { cmd(#"{"command":["seek","5","relative"]}"#) }
    @objc func menuSeekB5()       { cmd(#"{"command":["seek","-5","relative"]}"#) }
    @objc func menuSeekF60()      { cmd(#"{"command":["seek","60","relative"]}"#) }
    @objc func menuSeekB60()      { cmd(#"{"command":["seek","-60","relative"]}"#) }
    @objc func menuSeekStart()    { cmd(#"{"command":["seek","0","absolute"]}"#) }
    @objc func menuChapterNext()  { cmd(#"{"command":["add","chapter","1"]}"#) }
    @objc func menuChapterPrev()  { cmd(#"{"command":["add","chapter","-1"]}"#) }
    @objc func menuFrameNext()    { cmd(#"{"command":["frame-step"]}"#) }
    @objc func menuFramePrev()    { cmd(#"{"command":["frame-back-step"]}"#) }
    @objc func menuSpeedUp()      { cmd(#"{"command":["multiply","speed",1.1]}"#) }
    @objc func menuSpeedDown()    { cmd(#"{"command":["multiply","speed",0.9]}"#) }
    @objc func menuSpeedDouble()  { cmd(#"{"command":["multiply","speed",2.0]}"#) }
    @objc func menuSpeedHalf()    { cmd(#"{"command":["multiply","speed",0.5]}"#) }
    @objc func menuSpeedReset()   { cmd(#"{"command":["set","speed",1.0]}"#) }
    @objc func menuLoopFile()     { cmd(#"{"command":["cycle-values","loop-file","inf","no"]}"#) }
    @objc func menuABLoop()       { cmd(#"{"command":["ab-loop"]}"#) }
    @objc func menuPlaylistNext() { cmd(#"{"command":["playlist-next"]}"#) }
    @objc func menuPlaylistPrev() { cmd(#"{"command":["playlist-prev"]}"#) }

    // MARK: - Video Menu
    
    @objc func menuFullscreen()       { cmd(#"{"command":["cycle","fullscreen"]}"#) }
    @objc func menuOntop()            { cmd(#"{"command":["cycle","ontop"]}"#) }
    // gor motion: zoom and pan steps go to gor-fit.lua, which eases toward the target (no tick-tick-tick).
    @objc func menuZoomIn()           { cmd(#"{"command":["script-message-to","gor_fit","zoom","1"]}"#) }
    @objc func menuZoomOut()          { cmd(#"{"command":["script-message-to","gor_fit","zoom","-1"]}"#) }
    // gor 514: "reset zoom & pan" never worked. Root cause (mpv 0.41 JSON IPC, reproduced):
    // the `set` command rejects a JSON NUMBER value with "invalid parameter" (it accepts only
    // a string), so ["set","video-zoom",0] was a silent no-op. `set_property` takes the
    // number. It now resets the zoom AND every pan the video menu can create: the new
    // in-window content pan (video-pan-x/y) and panscan (the e/w items).
    @objc func menuZoomReset() {
        if PPController.gorFitScriptActive {
            cmd(#"{"command":["script-message-to","gor_fit","reset"]}"#)
        } else {
            cmd(#"{"command":["set_property","video-zoom",0]}"#)
            cmd(#"{"command":["set_property","video-pan-x",0]}"#)
            cmd(#"{"command":["set_property","video-pan-y",0]}"#)
            cmd(#"{"command":["set_property","panscan",0]}"#)
        }
    }
    // gor 514: move the video INSIDE the window after zooming (content pan, not a window
    // move). mpv video-pan-x/y are fractions of the video size; +x moves the picture right,
    // +y moves it down. One step = 5% of the video size. `add` takes a number (verified).
    @objc func menuPanVideoLeft()     { cmd(#"{"command":["script-message-to","gor_fit","move","-1","0"]}"#) }
    @objc func menuPanVideoRight()    { cmd(#"{"command":["script-message-to","gor_fit","move","1","0"]}"#) }
    @objc func menuPanVideoUp()       { cmd(#"{"command":["script-message-to","gor_fit","move","0","-1"]}"#) }
    @objc func menuPanVideoDown()     { cmd(#"{"command":["script-message-to","gor_fit","move","0","1"]}"#) }
    @objc func menuPanscanIn()        { cmd(#"{"command":["add","panscan",0.1]}"#) }
    @objc func menuPanscanOut()       { cmd(#"{"command":["add","panscan",-0.1]}"#) }
    // gor rotate menu (owner 5xx): mpv 0.41's `add` on video-rotate does not wrap.
    // Verified against the vendor mpv 0.41 over IPC: +90 from 270 clamps to 359 (a
    // non-90-degree step hardware decode cannot show, so the picture looks stuck and
    // every later add stays 359) and -90 from 0 selects the "no" choice (rotation
    // off entirely, shown as a boolean false on readback). cycle-values walks the
    // four right angles in order, wraps both directions, and self-heals from both
    // poisoned states; set_property 0 resets. The r1-rotate-menu selftest leg
    // replays these exact strings and checks video-rotate AND video-params/rotate.
    @objc func menuRotateCW()         { cmd(#"{"command":["cycle-values","video-rotate","90","180","270","0"]}"#) }
    @objc func menuRotateCCW()        { cmd(#"{"command":["cycle-values","video-rotate","270","180","90","0"]}"#) }
    @objc func menuRotateReset()      { cmd(#"{"command":["set_property","video-rotate",0]}"#) }

    // MARK: - Aspect Ratio Submenu
    //
    // WHY: mpv's add/multiply don't reliably operate on
    // video-aspect-override (mpv-player/mpv#13362), so every action
    // resolves a concrete ratio in Swift and always sends `set`.
    // currentAspectPreset tracks the last menu action, not mpv's live
    // state (no synchronous getter); mpv resets the property per file,
    // so the two can drift until the next menu action.
    enum AspectPreset: Equatable {
        case ratio(Double)   // active numeric override, e.g. 1.85
        case defaultAR       // "no" — no override, container aspect

        var mpvValue: String {
            switch self {
            case .ratio(let r): return String(format: "%.6f", r)
            case .defaultAR:    return "no"
            }
        }
    }

    private static var _currentAspectPreset = AspectPreset.defaultAR
    var currentAspectPreset: AspectPreset {
        get { Self._currentAspectPreset }
        set { Self._currentAspectPreset = newValue }
    }

    func setAspect(_ preset: AspectPreset) {
        if activePlayerEngine == .gorav {controller?.showEngineRoute("gorav unavailable: aspect override");return}
        currentAspectPreset = preset
        let ratio: Double?
        if case .ratio(let value) = preset { ratio=value } else { ratio=nil }
        // Publish the player override before reflowing stereo geometry.
        cmd("{\"command\":[\"set\",\"video-aspect-override\",\"\(preset.mpvValue)\"]}")
        controller?.noteAspectMenuSelection(ratio)
    }

    @objc func menuAspect133() { setAspect(.ratio(4.0/3)) }   // 4:3 Academy
    @objc func menuAspect137() { setAspect(.ratio(1.37)) }   // Academy sound
    @objc func menuAspect143() { setAspect(.ratio(1.43)) }   // IMAX
    @objc func menuAspect166() { setAspect(.ratio(1.66)) }   // European widescreen
    @objc func menuAspect178() { setAspect(.ratio(16.0/9)) }   // 16:9 HDTV
    @objc func menuAspect185() { setAspect(.ratio(1.85)) }   // American widescreen
    @objc func menuAspect200() { setAspect(.ratio(2.00)) }   // Univisium
    @objc func menuAspect220() { setAspect(.ratio(2.20)) }   // 70mm
    @objc func menuAspect235() { setAspect(.ratio(2.35)) }   // CinemaScope
    @objc func menuAspect239() { setAspect(.ratio(2.39)) }   // Anamorphic widescreen
    @objc func menuAspect255() { setAspect(.ratio(2.55)) }   // CinemaScope 55
    @objc func menuAspect259() { setAspect(.ratio(2.59)) }   // Cinerama
    @objc func menuAspect276() { setAspect(.ratio(2.76)) }   // Ultra Panavision 70
    @objc func menuAspect300() { setAspect(.ratio(3.00)) }   // Polyvision
    @objc func menuAspect400() { setAspect(.ratio(4.00)) }   // Napoléon triptych
    @objc func menuAspect500() { setAspect(.ratio(5.00)) }   // Apoléon riptych
    @objc func menuAspect600() { setAspect(.ratio(6.00)) }   // Poléon iptych
    @objc func menuAspect700() { setAspect(.ratio(7.00)) }   // Oléon ptych
    // WHY: integer ratios reuse the decimal handler within 0.005 (16:9
    // -> menuAspect178, 4:3 -> menuAspect133) - an exact-value handler
    // would split the checkmark across two items meaning the same ratio.
    @objc func menuAspect1610() { setAspect(.ratio(1.60)) }   // 16:10
    @objc func menuAspect32()   { setAspect(.ratio(1.50)) }   // 3:2
    @objc func menuAspect11()   { setAspect(.ratio(1.00)) }   // 1:1 square
    @objc func menuAspect54()   { setAspect(.ratio(1.25)) }   // 5:4
    @objc func menuAspect916()  { setAspect(.ratio(9.0/16)) }   // 9:16 vertical/mobile
    @objc func menuAspect34()   { setAspect(.ratio(0.75)) }   // 3:4 portrait
    @objc func menuAspectDefault() { setAspect(.defaultAR) }

    // Fine adjustment: expand-horizontal raises W/H, expand-vertical
    // lowers it. Starts from currentAspectPreset; .defaultAR falls back
    // to the live container aspect via videoDisplayW/H.
    private static let fineStep = 0.1
    private static let minAspect = 0.5
    private static let maxAspect = 8.0

    private func baseAspectForNudge() -> Double {
        if case .ratio(let r) = currentAspectPreset { return r }
        guard let ctrl = controller, ctrl.videoDisplayW > 0, ctrl.videoDisplayH > 0 else {
            return 1.78 // no video loaded yet and no prior preset — reasonable HDTV default
        }
        return ctrl.videoDisplayW / ctrl.videoDisplayH
    }

    private func nudgeAspect(by delta: Double) {
        let clamped = min(Self.maxAspect, max(Self.minAspect, baseAspectForNudge() + delta))
        setAspect(.ratio(clamped))
    }

    @objc func menuAspectExpandH() { nudgeAspect(by:  Self.fineStep) }
    @objc func menuAspectShrinkH() { nudgeAspect(by: -Self.fineStep) }
    @objc func menuAspectExpandV() { nudgeAspect(by: -Self.fineStep) }
    @objc func menuAspectShrinkV() { nudgeAspect(by:  Self.fineStep) }

    // MARK: - VR Modes
    //
    // Three mutually-exclusive output modes, tracked in currentVRMode
    // separately from the aspect checkmark: mono (no shader, no crop),
    // side-by-side (both eyes on a flat stereo plane),
    // VR180 (vr180-look.lua shader + look-around gestures).
    // side-by-side always crops exactly the left 50% of videoDisplayW,
    // independent of applyCrop()'s target-aspect fit.
    enum VRMode: Equatable { case mono, sideBySide, vr180 }
    private static var _currentVRMode = VRMode.mono
    var currentVRMode: VRMode {
        get { Self._currentVRMode }
        set { Self._currentVRMode = newValue }
    }

    private func clearVRCrop() {
        controller?.clearOwnedCropFromMenu()
    }

    // 191b B4: the mono/sbs/2d3d/vr180 menu entries are gone; the one "3d" menu's View/Film rows (ThreeDMenu) replace them.
    @objc func menuCropNone() {
        controller?.clearOwnedCropFromMenu()
    }
    @objc func menuCrop239()  { applyCrop(aspectW: 2.39, aspectH: 1) }
    @objc func menuCrop235()  { applyCrop(aspectW: 2.35, aspectH: 1) }
    @objc func menuCrop220()  { applyCrop(aspectW: 2.20, aspectH: 1) }
    @objc func menuCrop200()  { applyCrop(aspectW: 2.00, aspectH: 1) }
    @objc func menuCrop185()  { applyCrop(aspectW: 1.85, aspectH: 1) }
    @objc func menuCrop166()  { applyCrop(aspectW: 1.66, aspectH: 1) }
    @objc func menuCrop143()  { applyCrop(aspectW: 1.43, aspectH: 1) }
    @objc func menuCrop137()  { applyCrop(aspectW: 1.37, aspectH: 1) }
    @objc func menuCrop255()  { applyCrop(aspectW: 2.55, aspectH: 1) }
    @objc func menuCrop259()  { applyCrop(aspectW: 2.59, aspectH: 1) }
    @objc func menuCrop276()  { applyCrop(aspectW: 2.76, aspectH: 1) }
    @objc func menuCrop300()  { applyCrop(aspectW: 3.00, aspectH: 1) }
    @objc func menuCrop400()  { applyCrop(aspectW: 4.00, aspectH: 1) }
    @objc func menuCrop500()  { applyCrop(aspectW: 5.00, aspectH: 1) }
    @objc func menuCrop600()  { applyCrop(aspectW: 6.00, aspectH: 1) }
    @objc func menuCrop700()  { applyCrop(aspectW: 7.00, aspectH: 1) }
    @objc func menuCrop169()  { applyCrop(aspectW: 16,   aspectH: 9) }
    @objc func menuCrop1610() { applyCrop(aspectW: 16,   aspectH: 10) }
    @objc func menuCrop43()   { applyCrop(aspectW: 4,    aspectH: 3) }
    @objc func menuCrop32()   { applyCrop(aspectW: 3,    aspectH: 2) }
    @objc func menuCrop11()   { applyCrop(aspectW: 1,    aspectH: 1) }
    @objc func menuCrop54()   { applyCrop(aspectW: 5,    aspectH: 4) }
    @objc func menuCrop916()  { applyCrop(aspectW: 9,    aspectH: 16) }
    @objc func menuCrop45()   { applyCrop(aspectW: 4,    aspectH: 5) }
    @objc func menuCrop34()   { applyCrop(aspectW: 3,    aspectH: 4) }
    @objc func menuScreenshot()       { cmd(#"{"command":["screenshot","subtitles"]}"#) }
    @objc func menuScreenshotClean()  { cmd(#"{"command":["screenshot","video"]}"#) }
    @objc func menuScreenshotWin()    { cmd(#"{"command":["screenshot","window"]}"#) }
    @objc func menuDeband()           { cmd(#"{"command":["cycle","deband"]}"#) }
    @objc func menuDeinterlace()      { cmd(#"{"command":["cycle","deinterlace"]}"#) }
    @objc func menuHwdec()            { cmd("{\"command\":[\"cycle-values\",\"hwdec\",\"no\",\"auto\"]}") }
    @objc func menuContrastUp()       { cmd(#"{"command":["add","contrast",1]}"#) }
    @objc func menuContrastDown()     { cmd(#"{"command":["add","contrast",-1]}"#) }
    @objc func menuBrightUp()         { cmd(#"{"command":["add","brightness",1]}"#) }
    @objc func menuBrightDown()       { cmd(#"{"command":["add","brightness",-1]}"#) }
    @objc func menuGammaUp()          { cmd(#"{"command":["add","gamma",1]}"#) }
    @objc func menuGammaDown()        { cmd(#"{"command":["add","gamma",-1]}"#) }
    @objc func menuSatUp()            { cmd(#"{"command":["add","saturation",1]}"#) }
    @objc func menuSatDown()          { cmd(#"{"command":["add","saturation",-1]}"#) }
    @objc func menuColorReset() {
        // One batch so the four channels return to 0 together; hand-nudged
        // contrast/brightness/gamma/saturation have no other way back.
        controller?.batchIPC([#"{"command":["set_property","contrast",0]}"#,
                              #"{"command":["set_property","brightness",0]}"#,
                              #"{"command":["set_property","gamma",0]}"#,
                              #"{"command":["set_property","saturation",0]}"#].joined(separator: "\n"),
                             timeout: 5.0)
    }
    @objc func menuCropReset()  { controller?.resetCrop() }
    @objc func menuCropDetect() { controller?.reDetectCrop() }

    private func applyCrop(aspectW: Double, aspectH: Double) {
        guard let ctrl = controller else { return }
        _ = ctrl.applyMenuCrop(aspect:aspectW/aspectH)
    }

    // MARK: - Audio Menu
    
    @objc func menuVolUp()        { cmd(#"{"command":["add","volume",5]}"#) }
    @objc func menuVolDown()      { cmd(#"{"command":["add","volume",-5]}"#) }
    @objc func menuMute()         { cmd(#"{"command":["cycle","mute"]}"#) }
    @objc func menuAudioNext()    { cmd(#"{"command":["cycle","audio"]}"#) }
    @objc func menuAudioPrev()    { cmd(#"{"command":["cycle","audio","down"]}"#) }
    @objc func menuAudioDelayP()  { controller?.adjustSubtitleProperty("audio-delay",delta:0.1) }
    @objc func menuAudioDelayM()  { controller?.adjustSubtitleProperty("audio-delay",delta:-0.1) }
    @objc func menuAudioDelayReset() { controller?.adjustSubtitleProperty("audio-delay",reset:true) }

    // MARK: - Subtitles Menu
    
    @objc func menuSubToggle()    { cmd(#"{"command":["cycle","sub-visibility"]}"#) }
    @objc func menuSubNext()      { cmd(#"{"command":["cycle","sub"]}"#) }
    @objc func menuSubPrev()      { cmd(#"{"command":["cycle","sub","down"]}"#) }
    @objc func menuSubDelayP()    { controller?.adjustSubtitleProperty("sub-delay",delta:0.1) }
    @objc func menuSubDelayM()    { controller?.adjustSubtitleProperty("sub-delay",delta:-0.1) }
    @objc func menuSubDelayReset() { controller?.adjustSubtitleProperty("sub-delay",reset:true) }
    @objc func menuSubSizeUp()    { controller?.adjustSubtitleProperty("sub-scale",delta:0.1) }
    @objc func menuSubSizeDown()  { controller?.adjustSubtitleProperty("sub-scale",delta:-0.1) }
    @objc func menuSubSizeReset() { controller?.adjustSubtitleProperty("sub-scale",reset:true) }
    @objc func menuSubtitlesReset() {controller?.resetSubtitles()}
    @objc func menuSubUp()        { controller?.adjustSubtitleProperty("sub-pos",delta:-1) }
    @objc func menuSubDown()      { controller?.adjustSubtitleProperty("sub-pos",delta:1) }
    @objc func menuSubPosPreset(_ sender: NSMenuItem) {
        guard let pos = sender.representedObject as? Int else { return }
        controller?.setSubtitlePositionPreset(pos)
    }

    // MARK: - Photon Menu (messages proven by PPController.engineToggleMessages + input.conf)

    @objc func menuPhotonToggle() { cmd(#"{"command":["script-message-to","photon","photon-toggle"]}"#) }
    @objc func menuPhotonHUD()    { cmd(#"{"command":["keypress","F8"]}"#) }   // keypress = same path as the physical F8 binding in photon-hud.lua
    @objc func menuPhotonBright() { cmd(#"{"command":["script-message-to","photon","photon-bright-toggle"]}"#) }
    @objc func menuPhotonSharp()  { cmd(#"{"command":["script-message-to","photon_sharp","photon-sharp-toggle"]}"#) }
    @objc func menuPhotonGrain()  { cmd(#"{"command":["script-message-to","photon_grain","photon-grain-toggle"]}"#) }
    @objc func menuPhotonChrome() { cmd(#"{"command":["script-message-to","photon_chrome","photon-chrome-toggle"]}"#) }
    @objc func menuPhotonChromeFilter() { cmd(#"{"command":["script-message-to","photon_chrome","photon-chrome-filter-toggle"]}"#) }
    @objc func menuPhotonNegativ() { cmd(#"{"command":["script-message-to","photon_negativ","photon-negativ-toggle"]}"#) }
    @objc func menuStatsToggle()  { cmd(#"{"command":["script-binding","gor_stats/display-stats-toggle"]}"#) }

    @objc func menuSubRandomPos() { controller?.subtitleView.toggleRandomMode() }

    // MARK: - Captions

    @objc func menuLiveCaption() { _ = controller?.toggleLiveCaption(languageCode: nil) }

    @objc func menuCaptionModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        LiveCaptionController.shared.modelName = model
    }

    @objc func menuSaveSrcSubtitle() { controller?.subtitleView.exportSrcSubtitle() }

    // MARK: - Modes

    @objc func menuMusicMode() { controller?.toggleMusicMode() }

    // 191b B5: the old vr-tools menu entry points (head tracking, cross-eye, blink, recenter, IPD) are gone; the same chords
    // live once in ThreeDKeymap.rows and dispatch through ThreeDMenu.dispatch -> ThreeDStore.

    // MARK: - Clip (clip.lua bindings; InputController re-emits the Cmd+Opt keys)

    @objc func menuClipVideo() { cmd(#"{"command":["script-binding","clip/clip_video"]}"#) }
    @objc func menuClipGif()   { cmd(#"{"command":["script-binding","clip/clip_gif"]}"#) }
    @objc func menuClipUndo()  { cmd(#"{"command":["script-binding","clip/clip_undo"]}"#) }
    @objc func menuClipAbort() { cmd(#"{"command":["script-binding","clip/clip_abort"]}"#) }
    @objc func menuClipOpen()  { cmd(#"{"command":["script-binding","clip/clip_open"]}"#) }
    @objc func menuClipFade()  { cmd(#"{"command":["script-binding","clip/toggle_fade"]}"#) }
    
    @objc func menuVolMax() {
        controller?.setVolume(PPController.defaultVolume)
    }

    @objc func menuSeekF20() {
        controller?.seekRelative(20)
    }

    @objc func menuSeekB20() {
        controller?.seekRelative(-20)
    }

    // MARK: - Panels

    @objc func menuIptvMode() { controller?.toggleIptvMode() }

    @objc func showAbout() {
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        guard let parentWin = overlayWin else { return }

        let size: CGFloat = 120

        let parentFrame = parentWin.frame
        let px = parentFrame.midX - size / 2
        let py = parentFrame.midY - size / 2

        let panel = GORAboutPanel(
            contentRect: CGRect(x: px, y: py, width: size, height: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.title = ""
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.black
        panel.isOpaque = true
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let bg = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.clear.cgColor

        let logoBox = NSView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        logoBox.wantsLayer = true
        logoBox.layer?.backgroundColor = NSColor.black.cgColor
        logoBox.layer?.cornerRadius = 6
        bg.addSubview(logoBox)

        let logoView = NSImageView(frame: logoBox.bounds)
        if let logoPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let logo = NSImage(contentsOfFile: logoPath) {
            logoView.image = logo
            logoView.imageScaling = .scaleProportionallyUpOrDown
        }
        let click = NSClickGestureRecognizer(target: self, action: #selector(dismissAboutPanel))
        logoView.addGestureRecognizer(click)
        logoBox.addSubview(logoView)
        panel.contentView = bg

        // Keep the original transparent text window and 120pt logo tile.
        // Measure full-size font rows instead of fitting them in fixed 26pt cells.
        let textPanel = NSPanel(
            contentRect: CGRect(x: px, y: py, width: size, height: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        textPanel.isFloatingPanel = true
        textPanel.becomesKeyOnlyIfNeeded = false
        textPanel.hidesOnDeactivate = false
        textPanel.title = ""
        textPanel.level = .modalPanel
        textPanel.isMovableByWindowBackground = true
        textPanel.backgroundColor = .clear
        textPanel.isOpaque = false
        textPanel.hasShadow = false
        textPanel.titlebarAppearsTransparent = true
        textPanel.appearance = NSAppearance(named: .darkAqua)
        textPanel.standardWindowButton(.closeButton)?.isHidden = true
        textPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        textPanel.standardWindowButton(.zoomButton)?.isHidden = true
        textPanel.ignoresMouseEvents = true

        let textBg = NSView(frame: .zero)
        textBg.wantsLayer = true
        textBg.layer?.backgroundColor = NSColor.clear.cgColor
        // Keep global UI charH/lineH. Explicit CTLine baselines allow the
        // logo to attach exactly below the title's actual g descender.
        func makeRow(_ text: String, color: NSColor) -> GORAboutTextLayer {
            let row = GORAboutTextLayer()
            row.text = text
            row.textColor = color
            row.contentsScale = parentWin.backingScaleFactor
            textBg.layer?.addSublayer(row)
            return row
        }
        let topLabel = makeRow("gor", color: .white)
        let versionLabel = makeRow("v.2.2 spm", color: NSColor.white.withAlphaComponent(0.5))
        let idLabel = makeRow("build-id", color: NSColor.white.withAlphaComponent(0.5))
        let idValueLabel = makeRow(BuildID.shortValue(BuildID.value()), color: NSColor.white.withAlphaComponent(0.5))
        let layoutRows: (CTFont) -> Void = { [weak parentWin, weak panel, weak textPanel, weak textBg, weak topLabel, weak versionLabel, weak idLabel, weak idValueLabel] font in
            guard let parentWin, let panel, let textPanel, let textBg, let topLabel, let versionLabel, let idLabel, let idValueLabel else { return }
            // Owner's image: logo on the left; four left-aligned lines on
            // the right. Typography/row step/gap use the global UI policy.
            let rows = [topLabel, versionLabel, idLabel, idValueLabel]
            let inks = rows.map { $0.setFont(font) }
            let rowHeight = PhotonFont.chromeCharH
            var lineStep = PhotonFont.chromeLineH
            for i in 0..<(inks.count - 1) {
                lineStep = max(lineStep, inks[i + 1].maxY - inks[i].minY)
            }
            let widths = rows.map { row -> CGFloat in
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: row.text, attributes: [.font: font]))
                return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            }
            let textLeft = max(0, -(inks.map { $0.minX }.min() ?? 0))
            let textWidth = ceil(max(widths.max() ?? 0, inks.map { $0.maxX }.max() ?? 0) + textLeft)
            let textBottom = inks[3].minY
            let textTop = lineStep * 3 + inks[0].maxY
            let textHeight = textTop - textBottom
            let blockHeight = max(size, textHeight)
            let gap = PhotonFont.chromePad
            let totalWidth = size + gap + textWidth
            let center = NSPoint(x: parentWin.frame.midX, y: parentWin.frame.midY)
            let logoX = center.x - totalWidth / 2
            let logoY = center.y - size / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            if let stereo = panel.stereoSession {
                stereo.fit(width: totalWidth, height: blockHeight)
                textBg.frame = CGRect(x:size+gap,y:0,width:textWidth,height:blockHeight)
            } else {
                panel.setFrameOrigin(NSPoint(x: logoX, y: logoY))
                let originY = center.y - blockHeight / 2
                textPanel.setFrame(CGRect(x: logoX + size + gap, y: originY,
                                          width: textWidth, height: blockHeight), display: true)
                textBg.frame = CGRect(x: 0, y: 0, width: textWidth, height: blockHeight)
            }
            let baseY = (blockHeight - textHeight) / 2 - textBottom
            for (i, row) in rows.enumerated() {
                row.leftInset = textLeft
                row.frame = CGRect(x: 0, y: baseY + CGFloat(3 - i) * lineStep,
                                   width: textWidth, height: max(rowHeight, inks[i].maxY))
            }
        }
        textPanel.contentView = textBg

        isShowingInputPanel = true
        setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true

        // Both tokens must be removed when the panel closes: a
        // discarded local-monitor token leaks one permanent app-wide
        // keyDown listener per About open (and its strong panel capture
        // keeps the panel alive); a discarded observer token keeps the
        // closure (and textPanel) registered forever. The box is a class
        // so the @Sendable observer closure captures a let, not mutable
        // vars ("mutated after capture" warning otherwise).
        final class MonitorBox {
            var escMonitor: Any?
            var closeObserver: NSObjectProtocol?
        }
        let box = MonitorBox()
        box.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main
        ) { [weak self, weak parentWin, weak textPanel] _ in
            self?.isShowingInputPanel = false
            self?.setEventTapEnabled(true)
            parentWin?.ignoresMouseEvents = false
            textPanel?.orderOut(nil)
            if let m = box.escMonitor { NSEvent.removeMonitor(m) }
            if let o = box.closeObserver { NotificationCenter.default.removeObserver(o) }
        }

        box.escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            if event.keyCode == 53, let panel = panel, panel.isVisible, event.window === panel {
                // close() posts willCloseNotification - the observer
                // above runs the cleanup and removes this monitor.
                panel.close()
                return nil
            }
            return event
        }

        panel.makeKeyAndOrderFront(nil)
        
        layoutRows(PhotonFont.chromeCt())
        // In VR put the logo and text into one native content group before duplicating both eyes.
        if let root = parentWin.contentView {
            func player(_ view: NSView) -> PPController? {
                if let p = view as? PPController { return p }
                for child in view.subviews { if let p = player(child) { return p } }
                return nil
            }
            if player(root)?.vrModeEnabled == true {
                let textWidth = textBg.bounds.width, blockHeight = textBg.bounds.height
                let gap = PhotonFont.chromePad
                bg.setFrameSize(CGSize(width:size+gap+textWidth,height:blockHeight))
                logoBox.frame.origin.y = (blockHeight-size)*0.5
                textBg.removeFromSuperview()
                textBg.frame.origin = CGPoint(x:size+gap,y:0)
                bg.addSubview(textBg)
                panel.setContentSize(bg.bounds.size)
                panel.installStereoIfNeeded(parent: parentWin)
                layoutRows(PhotonFont.chromeCt())
            }
        }
        VariationBroadcaster.shared.addListener(weakLifetime: topLabel) { [weak panel, weak logoBox] in
            guard let panel, panel.isVisible, let logoBox else { return }
            layoutRows(PhotonFont.chromeCtDriven(view: logoBox, profile: .logo))
        }
        if panel.stereoSession == nil { textPanel.orderFront(nil) }
    }

    @objc func dismissAboutPanel() {
        // Never close the playback overlay if the About panel lost key status.
        if let panel = NSApp.windows.first(where: { $0 is GORAboutPanel && $0.isVisible }) {
            panel.close()
        }
        isShowingInputPanel = false
        overlayWin?.ignoresMouseEvents = false
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
    @objc func menuOpenURL() {
        VariationBroadcaster.shared.noteOpenPath("CmdU-panel")
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        // The event tap sets isShowingInputPanel before dispatching here
        // (see setupEventTap), so a failing guard must reset the flag.
        guard let parentWin = overlayWin else { isShowingInputPanel = false; return }
        let appDelegate = self

        let ph: CGFloat = 54
        let startFrame = SearchBarFit.initialFrame(host: parentWin, height: ph)
        let pw = startFrame.width
        let px = startFrame.minX
        let py = startFrame.minY

        let panel = GORInputPanel(
            contentRect: CGRect(x: px, y: py, width: pw, height: ph),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.title = ""
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.black
        panel.isOpaque = true
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let bg = NSView(frame: CGRect(x: 0, y: 0, width: pw, height: ph))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor

        let tf = NSTextField(frame: CGRect(x: 20, y: 14, width: pw - 40, height: 28))
        tf.font = PhotonFont.chromeNs()
        tf.textColor = .white
        tf.backgroundColor = .clear; tf.drawsBackground = false
        tf.isBordered = false; tf.focusRingType = .none
        tf.isEditable = true
        tf.isSelectable = true
        tf.refusesFirstResponder = false
        tf.placeholderString = "open url…"
        tf.target = self
        tf.action = #selector(commitURL)

        bg.addSubview(tf)
        panel.contentView = bg
        SearchBarFit.install(panel: panel, field: tf, anchor: .center, host: parentWin)

        appDelegate.isShowingInputPanel = true
        appDelegate.setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main
        ) { [weak parentWin] _ in
            appDelegate.isShowingInputPanel = false
            appDelegate.setEventTapEnabled(true)
            parentWin?.ignoresMouseEvents = false
        }

        panel.installStereoIfNeeded(parent: parentWin)
        panel.makeKeyAndOrderFront(nil)
        panel.assertKeyAndFocus(tf)
    }
    @objc func commitURL(_ sender: NSTextField) {
        // sender is the field itself (target-action). Never re-scan
        // NSApp.windows for the panel - ArchiveTopBar's search panel is
        // an identical NSPanel+NSTextField and can resolve wrong.
        guard let panel = sender.window else { return }
        let urlStr = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.orderOut(nil)
        isShowingInputPanel = false
        overlayWin?.ignoresMouseEvents = false
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        guard !urlStr.isEmpty else { return }
        
        if urlStr.contains("transfer.it") || urlStr.contains("mega.nz") || urlStr.contains("gofile.io") || urlStr.contains("drive.google.com") {
            openArchiveWithURL(urlStr)
            return
        }
        
        if urlStr.hasPrefix("magnet:") || urlStr.hasSuffix(".torrent") || urlStr.contains(".torrent?") {
            VariationBroadcaster.shared.noteOpenPath("CmdU-torrent")
            streamTorrent(urlStr)
            return
        }
        
        if urlStr.contains("youtube.com") || urlStr.contains("youtu.be") {
            controller?.ipcCommand("{\"command\":[\"script-message-to\",\"photon\",\"set-live\",\"true\"]}")
        }
        
        // WHY: everything else (yt-dlp/YouTube included) goes through
        // playMedia so its cache/demuxer pre-tuning applies (see
        // playMedia's generic else branch).
        playMedia(url: urlStr, title: urlStr)
    }
   
    @objc func openFile() { openFilePanel(atPath: nil) }

    /// startPath seeds the browser's folder (Cmd+P: the playing media's
    /// folder); nil keeps the panel's own default.
    func openFilePanel(atPath startPath: String?) {
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        // The event tap sets isShowingInputPanel synchronously before
        // dispatching here (see setupEventTap), so a failing guard must
        // reset the flag itself or it strands true forever.
        guard let parentWin = overlayWin, let contentView = parentWin.contentView,
              let ctrl = controller else { isShowingInputPanel = false; return }
        
        contentView.subviews.filter { $0 is FileBrowserPanel }.forEach { $0.removeFromSuperview() }
        
        let padL: CGFloat = 50
        let padR: CGFloat = IconBarFit.panelPadR(padL: padL)
        let padT: CGFloat = 9
        // No frame computed here: registerVideoFramePanel (PPController)
        // re-derives it from the same padding formula on every
        // appliedVideoFrame recalc - autoresizingMask only scales
        // proportionally and drifts against letterbox/pillarbox math.
        let browser = FileBrowserPanel(frame: .zero)
        // Arka plan transparan — UI ile uyumlu
        browser.wantsLayer = true
        browser.layer?.backgroundColor = NSColor.clear.cgColor
        // Core Animation orders sibling layers by zPosition, not add
        // order; SpineUI's dropdowns/HUD panels set 5000-5001, so this
        // panel must sit above them.
        browser.layer?.zPosition = 6000
        ctrl.registerVideoFramePanel(browser, padL: padL, padR: padR, padT: padT)
        
        browser.onSelect = { [weak self, weak browser] (path: String) in
            browser?.onClose?()

            if path.lowercased().hasSuffix(".torrent") {
                self?.streamTorrent(path)
                return
            }

            let dir = (path as NSString).deletingLastPathComponent
            let videoExts = Set(["mkv","mp4","avi","mov","m4v","webm","vob","ts","flv","mp3","flac","wav","aac","ogg","m4a","crdownload","part"])
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                let playable = files
                    .filter { videoExts.contains($0.components(separatedBy: ".").last?.lowercased() ?? "") }
                    .sorted()
                // Always start at the chosen file. Append the rest in folder order.
                if self?.controller?.isMusicMode == true { self?.controller?.toggleMusicMode() }
                if self?.controller?.isIptvMode == true { self?.controller?.toggleIptvMode() }
                self?.controller?.openMediaFile(path)
                for file in playable where dir + "/" + file != path {
                    let fullPath = dir + "/" + file
                    if let data = try? JSONSerialization.data(withJSONObject: ["command": ["loadfile", fullPath, "append"]]),
                       let command = String(data: data, encoding: .utf8) {
                        self?.controller?.ipcCommand(command)
                    }
                }
            } else {
                if self?.controller?.isMusicMode == true { self?.controller?.toggleMusicMode() }
                if self?.controller?.isIptvMode == true { self?.controller?.toggleIptvMode() }
                self?.controller?.openMediaFile(path)
            }
        }
        browser.onClose = { [weak self, weak browser] in
            guard let browser else { return }
            browser.removeFromSuperview()
            self?.controller?.unregisterVideoFramePanel(browser)
            self?.isShowingInputPanel = false
            self?.overlayWin?.ignoresMouseEvents = false
            if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }

        contentView.addSubview(browser)
        if let startPath { browser.loadPath(startPath) }

        isShowingInputPanel = true
        setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = false

        // Same leaked-monitor fix as openArchive(): capture the token
        // and remove it on close.
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak browser] event in
            guard event.keyCode == 53, let browser else{return event}
            if let input=event.window as? GORInputPanel {
                guard input.isKeyWindow,!input.hasMarkedText else{return event}
                input.cancelOperation(nil);return nil
            }
            guard event.window === browser.window else{return event}
            // Esc closes the search field first; the browser responds
            // only to a second Esc once search is gone.
            if browser.isSearchPanelOpen == true {
                _ = browser.closeSearchPanelIfOpen()
                return nil
            }
            if browser.superview != nil {
                browser.onClose?()
                return nil
            }
            return event
        }
        let previousOnClose = browser.onClose
        browser.onClose = {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            previousOnClose?()
        }
        // r (owner order 2026-11-15): with this folder panel open, a plain r
        // presses its random button. The event tap is disabled for the
        // panel's lifetime, so the panel needs its own monitor. Typing in a
        // search field is untouched: those events target the field's panel
        // window, not the browser's window. Same remove-on-close rule as the
        // Esc monitor.
        var rMonitor: Any?
        rMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak browser] event in
            guard event.keyCode == 15,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let browser, browser.superview != nil, event.window === browser.window else { return event }
            browser.pressRandomFromKey()
            return nil
        }
        let prevCloseForR = browser.onClose
        browser.onClose = {
            if let rMonitor { NSEvent.removeMonitor(rMonitor) }
            prevCloseForR?()
        }
    }
    
    /// Cmd+P (owner 2026-11-15): open the file browser at the playing
    /// media's folder. That folder IS the playlist (selecting a file there
    /// appends its playable siblings), so the browser lists the playlist.
    /// No-ops without a playing file; internal overlay media has no folder.
    @objc func menuOpenPlaylistFolder() {
        guard let ctrl = controller else { return }
        let path = ctrl.currentFilePath
        guard !path.isEmpty, !ThreeDRecognitionBridge.internalMedia(path) else { return }
        openFilePanel(atPath: (path as NSString).deletingLastPathComponent)
    }

    /// Cmd+F (owner 2026-11-15): toggle the frontmost browser panel's search.
    /// Routed through the menu's key equivalent so it fires while a panel owns
    /// keys and the event tap is off; a silent no-op when no searchable panel
    /// is open.
    @objc func menuFindInPanel() {
        switch frontmostSearchablePanel() {
        case let p as FileBrowserPanel: p.toggleSearchPanelFromKey()
        case let p as ArchiveBrowserPanel: p.toggleSearchFromKey()
        case let p as MagnetResultsPanel: p.toggleSearchFromKey()
        default: break
        }
    }

    @objc func menuSubLoad() {
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: 100)
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["srt","ass","ssa","sub","vtt","sup"].compactMap { .init(filenameExtension: $0) }
        let resp = showingPanel { panel.runModal() }
        guard resp == .OK, let url = panel.url else { return }
        if let command = Self.jsonCommand(["sub-add", url.path]) { cmd(command) }
    }
    
    @objc func openArchive() {
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        // A failing guard means no panel is showing, so reset the flag
        // the tap set (see openFile()). The "already open" check below is
        // different: a panel IS up, so the flag must stay true.
        guard let parentWin = overlayWin, let contentView = parentWin.contentView,
              let ctrl = controller else { isShowingInputPanel = false; return }
        if contentView.subviews.contains(where: { $0 is ArchiveBrowserPanel }) { return }
        let padL: CGFloat = 40; let padR = IconBarFit.panelPadR(padL: padL); let padT: CGFloat = 9
        // Same as openFile(): registerVideoFramePanel re-derives the
        // frame; nothing computed here up front.
        let panel = ArchiveBrowserPanel(frame: .zero)
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.clear.cgColor
        // Same zPosition issue as openFile(): must sit above SpineUI's
        // 5000-5001 dropdown/HUD layers.
        panel.layer?.zPosition = 6000
        ctrl.registerVideoFramePanel(panel, padL: padL, padR: padR, padT: padT)
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            panel.removeFromSuperview()
            TunnelForBlockedHosts.shared.browserClosed()
            self?.controller?.unregisterVideoFramePanel(panel)
            self?.isShowingInputPanel = false
            self?.overlayWin?.ignoresMouseEvents = false
            if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        panel.onPlay = { [weak self] (url, title, nodeKey, folderKeyFragment, subtitleURLs) in
            self?.stopTorrent()
            self?.stopMegaRelay()
            // Mega links route through the megajs relay (see
            // MegaStreamManager.swift), which resolves share, keys and CDN
            // URL from the link itself. nodeKey carries the file handle for
            // folder taps ("<handle>:<b64>"); single-file links need neither
            // it nor folderKeyFragment - the handle is in the URL.
            if url.contains("mega.nz/") || url.hasPrefix("mega-folder::") {
                self?.streamMega(shareLink: url, nodeKeyField: nodeKey ?? "", folderKeyFragment: folderKeyFragment ?? "", title: title)
            } else {
                self?.playMedia(url: url, title: title, subtitleURLs: subtitleURLs)
            }
        }
        contentView.addSubview(panel)
        isShowingInputPanel = true
        setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = false
        // The monitor token must be captured and removed in onClose - a
        // discarded token leaks one permanent app-wide keyDown listener
        // per panel open.
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.keyCode == 53, let panel, panel.superview != nil else { return event }
            if let input = event.window as? GORInputPanel {
                guard input.isKeyWindow,!input.hasMarkedText else{return event}
                input.cancelOperation(nil);return nil
            }
            guard event.window === panel.window else{return event}
            // Esc closes the search panel first; the browser closes on
            // the next press, matching Esc nesting elsewhere in the app.
            if panel.closeActiveSearchPanel() == true { return nil }
            panel.onClose?(); return nil
        }
        let previousOnClose = panel.onClose
        panel.onClose = {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            previousOnClose?()
        }
        // r (owner order 2026-11-15): same rule as the file browser - a
        // plain r presses this panel's random button while the tap is off;
        // keystrokes into a search field window pass through.
        var rMonitor: Any?
        rMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.keyCode == 15,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let panel, panel.superview != nil, event.window === panel.window else { return event }
            panel.pressRandomFromKey()
            return nil
        }
        let prevCloseForR = panel.onClose
        panel.onClose = {
            if let rMonitor { NSEvent.removeMonitor(rMonitor) }
            prevCloseForR?()
        }
    }

    private func openArchiveWithURL(_ urlStr: String) {
        guard let parentWin = overlayWin, let contentView = parentWin.contentView,
              let ctrl = controller else { return }
        // Same guard as openArchive(): if a panel is already up, leave
        // it alone rather than stacking a second one (and a second
        // ArchiveLibrary.shared.load()) on top.
        if contentView.subviews.contains(where: { $0 is ArchiveBrowserPanel }) { return }
        let padL: CGFloat = 40; let padR = IconBarFit.panelPadR(padL: padL); let padT: CGFloat = 9
        // Same as openArchive(): register instead of a one-shot frame.
        let panel = ArchiveBrowserPanel(frame: .zero)
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.clear.cgColor
        // Same zPosition issue as openFile().
        panel.layer?.zPosition = 6000
        ctrl.registerVideoFramePanel(panel, padL: padL, padR: padR, padT: padT)
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            panel.removeFromSuperview()
            TunnelForBlockedHosts.shared.browserClosed()
            self?.controller?.unregisterVideoFramePanel(panel)
            self?.isShowingInputPanel = false
            self?.overlayWin?.ignoresMouseEvents = false
            if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        panel.onPlay = { [weak self] (url, title, nodeKey, folderKeyFragment, subtitleURLs) in
            self?.stopTorrent()
            self?.stopMegaRelay()
            // Mega links route through the megajs relay (see
            // MegaStreamManager.swift), which resolves share, keys and CDN
            // URL from the link itself. nodeKey carries the file handle for
            // folder taps ("<handle>:<b64>"); single-file links need neither
            // it nor folderKeyFragment - the handle is in the URL.
            if url.contains("mega.nz/") || url.hasPrefix("mega-folder::") {
                self?.streamMega(shareLink: url, nodeKeyField: nodeKey ?? "", folderKeyFragment: folderKeyFragment ?? "", title: title)
            } else {
                self?.playMedia(url: url, title: title, subtitleURLs: subtitleURLs)
            }
        }
        contentView.addSubview(panel)
        isShowingInputPanel = true
        setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = false
        // Same leaked-monitor issue as openArchive(): capture and remove
        // on close.
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.keyCode == 53, let panel, panel.superview != nil else { return event }
            if let input = event.window as? GORInputPanel {
                guard input.isKeyWindow,!input.hasMarkedText else{return event}
                input.cancelOperation(nil);return nil
            }
            guard event.window === panel.window else{return event}
            // Same as openArchive()'s monitor: search first, browser on
            // a second press.
            if panel.closeActiveSearchPanel() == true { return nil }
            panel.onClose?(); return nil
        }
        let previousOnClose = panel.onClose
        panel.onClose = {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            previousOnClose?()
        }
        // r (owner order 2026-11-15): same rule as openArchive().
        var rMonitor: Any?
        rMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.keyCode == 15,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let panel, panel.superview != nil, event.window === panel.window else { return event }
            panel.pressRandomFromKey()
            return nil
        }
        let prevCloseForR = panel.onClose
        panel.onClose = {
            if let rMonitor { NSEvent.removeMonitor(rMonitor) }
            prevCloseForR?()
        }
        
        panel.selectTitle(urlStr, links: [urlStr])
    }
    
    private static func jsonCommand(_ command: [Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": command]),
              let line = String(data: data, encoding: .utf8) else { return nil }
        return line
    }

    func playMedia(url: String, title: String, startPos: Double? = nil, subtitleURLs: [String] = [],skipGORAV:Bool=false) {
        // All playback identity and UI state lives on main, regardless of caller.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.playMedia(url: url, title: title, startPos: startPos, subtitleURLs: subtitleURLs,skipGORAV:skipGORAV)
            }
            return
        }
        // transfer.it signed CDN URL: parallel relay instead of mpv's single connection (see
        // AppDelegate.isTransferItCDN). The relay's own 127.0.0.1 URL comes back through here and
        // falls through to normal playback.
        if AppDelegate.isTransferItCDN(url) {
            streamMega(shareLink: url, nodeKeyField: "", folderKeyFragment: "", title: title,
                       startPos: startPos, subtitleURLs: subtitleURLs)
            return
        }
        VariationBroadcaster.shared.noteOpenPath(URLComponents(string: url)?.port == 2222 ? "torrent-play" : "other-play")
        print("[PLAYMEDIA] startPos=\(startPos ?? -1)")
        youtubePlaybackGeneration &+= 1
        lastPlayedSubtitleURLs = subtitleURLs
        lastPlayedURL = url
        lastPlayedTitle = title
        lastPlayedStartPos = startPos
        youtubeRetryAttempted = false
        var finalURL = url
        var cookieHeader = ""
        var gofileToken = ""

        if url.contains("|") {
            var parts = url.components(separatedBy: "|")
            finalURL = parts.removeFirst()
            for part in parts {
                if part.hasPrefix("cookie=") { cookieHeader = String(part.dropFirst("cookie=".count)) }
                else if part.hasPrefix("gofile-token=") { gofileToken = String(part.dropFirst("gofile-token=".count)) }
            }
        }

        // Keep tunnel ownership across a second blocked-host load; a plain
        // URL replaces playback and releases only after its load completes.
        TunnelForBlockedHosts.shared.willLoad(finalURL)

        var extraHeaders: [String] = []
        if !gofileToken.isEmpty { extraHeaders.append("Authorization: Bearer \(gofileToken)") }
        if !cookieHeader.isEmpty  { extraHeaders.append("Cookie: \(cookieHeader)") }

        // T4 M1 gap 1: gorav stream route (magnet/IPTV/archive reach here as
        // resolved http(s) URLs from the owner's torrent app, the mega relay
        // and the IPTV/archive pickers). Pre-open admission only; a refusal
        // falls through to the mpv load below untouched.
        let admissionStart = startPos.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if !skipGORAV,routeMPVStreamIfNeeded(completion:{ [weak self] in
            self?.playMedia(url:url,title:title,startPos:startPos,subtitleURLs:subtitleURLs,skipGORAV:true)
        }) {return}
        if !skipGORAV,goravAdmitAndOpen(url: finalURL, headerCount: extraHeaders.count,
                             subtitleCount: subtitleURLs.count, startPos: admissionStart,fallback:{ [weak self] in
            self?.playMedia(url:url,title:title,startPos:startPos,subtitleURLs:subtitleURLs,skipGORAV:true)
        }) { return }

        var cmds: [String] = []
        cmds.append(#"{"command":["set_property","user-agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"]}"#)
        // Every load clears previous signed-host cookies/auth before another origin.
        if extraHeaders.isEmpty { cmds.append(MPVCommand.make(["set_property", "http-header-fields", ""])) }
        if !extraHeaders.isEmpty {
            // Real JSON escaping: header values carry CRLF, which quote-only
            // escaping left raw inside the JSON string (pass-5 #5).
            cmds.append(MPVCommand.make(["set_property", "http-header-fields",
                                         extraHeaders.joined(separator: "\r\n")]))
        }

        // Keyed by port, not prefix: localhost:2222 is wt_server, 2223 is the
        // mega relay (generic profile), anything else is a plain remote.
        let archiveParts = URLComponents(string: finalURL)
        let archiveHost = archiveParts?.host?.lowercased() ?? ""
        let isArchive = (archiveParts?.scheme == "https" && (archiveHost == "archive.org" || archiveHost.hasSuffix(".us.archive.org"))
            && archiveParts?.user == nil && archiveParts?.password == nil && archiveParts?.port == nil)
        let isTorrent = (URLComponents(string: finalURL)?.port == 2222)
        if isTorrent {
            // network-timeout only: wt_server's dl-gate waits up to ~205s on
            // thin swarms; mpv's default 60s kills the stream first (production
            // log 260925). cache/demuxer/decode are owned by TorrentManager's
            // PARAMS application, which landed just before this call - writing
            // them here landed last and silently won (pass-5 #4).
            cmds.append(#"{"command":["set_property","network-timeout","240"]}"#)
        } else {
            // Per-file baseline first (pass-5 #7), then branch overrides.
            restoreDefaultProfile()
            if finalURL.contains("pixeldrain.com") {
                cmds.append(#"{"command":["set_property","cache","yes"]}"#)
                cmds.append(#"{"command":["set_property","cache-secs","3600"]}"#)
                cmds.append(#"{"command":["set_property","cache-pause-initial","yes"]}"#)
                cmds.append(#"{"command":["set_property","cache-pause-wait","600"]}"#)
                cmds.append(#"{"command":["set_property","cache-on-disk","yes"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-max-bytes","4096M"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-max-back-bytes","1024M"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-readahead-secs","3600"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-seekable-cache","yes"]}"#)
                cmds.append(#"{"command":["set_property","prefetch-playlist","no"]}"#)
                cmds.append(#"{"command":["set_property","network-timeout","30"]}"#)
            } else {
                cmds.append(#"{"command":["set_property","cache-secs","30"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-max-bytes","500M"]}"#)
                cmds.append(#"{"command":["set_property","demuxer-readahead-secs","120"]}"#)
            }
        }

        // The title is a per-file option on this loadfile (below), not a global property: a global
        // force-media-title stays set in mpv and kept showing this title for every later local file.
        // A stream load is also not an IPTV channel; drop the IPTV title so the spine follows mpv.
        controller?.iptvChannelTitle = ""

        // 260930.1: file-local companions are installed during this exact load.
        // Named arguments avoid the loadfile index change in mpv 0.38.
        var fileOptions: [String: String] = [:]
        let explicitStart = startPos.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if let pos = explicitStart { fileOptions["start"] = String(pos) }
        fileOptions["force-media-title"] = title
        if isArchive {
            // File-local stream profile: start promptly, fetch ahead without waiting
            // for minutes of prebuffer, retain bounded cached backwards seeking.
            fileOptions["pause"] = "no"
            fileOptions["resume-playback"] = "no"
            if explicitStart == nil { fileOptions["start"] = "0" }
            fileOptions["cache"] = "yes"
            fileOptions["cache-on-disk"] = "no"
            fileOptions["cache-pause-initial"] = "no"
            fileOptions["cache-pause-wait"] = "1"
            fileOptions["cache-secs"] = "120"
            fileOptions["demuxer-readahead-secs"] = "120"
            fileOptions["demuxer-max-bytes"] = "256MiB"
            fileOptions["demuxer-max-back-bytes"] = "128MiB"
            fileOptions["demuxer-seekable-cache"] = "yes"
            fileOptions["demuxer-cache-wait"] = "no"
            // Root fix (r37): lavf mov, after reading a front moov, skips mdat by seeking to its end to scan
            // trailing atoms. A libarchive deflate entry cannot seek, so mpv re-inflates the entry from the
            // start up to that offset (whole member, ~138MB compressed for the 12032_400.mp4 case) and no frame
            // is shown. ignidx makes mov stop right after moov+mdat. Per-file, archive loads only.
            fileOptions["demuxer-lavf-o"] = "fflags=+ignidx"

        }
        let companionPaths = subtitleURLs.compactMap { signed -> String? in
            let parts = signed.components(separatedBy: "|")
            guard let path = parts.first, let parsed = URL(string: path), parsed.scheme == "https",
                  let host = parsed.host?.lowercased(), host.hasSuffix(".gofile.io"),
                  parsed.user == nil, parsed.password == nil, parsed.path.hasPrefix("/download/") else { return nil }
            // All companions came from this folder/account. Do not silently use
            // a different account's URL with the video's headers.
            for part in parts.dropFirst() {
                if part.hasPrefix("gofile-token="), String(part.dropFirst("gofile-token=".count)) != gofileToken { return nil }
                if part.hasPrefix("cookie="), String(part.dropFirst("cookie=".count)) != cookieHeader { return nil }
            }
            return path
        }
        if !companionPaths.isEmpty {
            // mpv Unix path-list separators need escaping even
            // inside a structured options map. JSONSerialization handles JSON.
            fileOptions["sub-files"] = companionPaths.map {
                $0.replacingOccurrences(of: ":", with: "\\:")
            }.joined(separator: ":")
        }
        // 260930.2: every load takes the named envelope, not only companion
        // loads. Positional loadfile grew an insertion-index third argument
        // (OPT_INT) in mpv 0.38; a "start=..." string landing there fails
        // type-checking and mpv rejects the whole loadfile, so a resume with
        // saved position never started playback.
        // Archive container members (https://archive.org/download/<id>/<name>.zip|.rar/<member>) go to mpv's
        // own libarchive entry URL instead of the view_archive.php redirect (HTTP 200, Range ignored, no length).
        // mpv reads the container over ordinary Range requests (archive.org container: 206) and plays from 0.
        let loadURL = isArchive ? Self.nativeArchiveEntryURL(finalURL) ?? finalURL : finalURL
        var load: [String: Any] = ["name": "loadfile", "url": loadURL, "flags": "replace"]
        if !fileOptions.isEmpty { load["options"] = fileOptions }
        if let data = try? JSONSerialization.data(withJSONObject: ["command": load]),
           let command = String(data: data, encoding: .utf8) { cmds.append(command) }
        if !subtitleURLs.isEmpty {
            print("[gofile-subtitles 260930.1] attaching \(companionPaths.count)/\(subtitleURLs.count) companions to this load")
        }
        if isTorrent || isArchive { cmds.append(#"{"command":["set_property","pause","no"]}"#) }

        controller?.batchIPC(cmds.joined(separator: "\n"), timeout: 5.0)
        controller?.isTorrentStopped = false
    }
    
    /// Observed mpv 0.41 form: archive://<container URL, %-escaped once more>|/<member path, unescaped>.
    /// Returns nil (caller keeps the original URL) unless the URL is exactly archive.org/download/<id>/<x>.zip|rar/<member>.
    static func nativeArchiveEntryURL(_ value: String) -> String? {
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == "archive.org", parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        let segments = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 5, segments[0].isEmpty, segments[1] == "download", !segments[2].isEmpty else { return nil }
        var containerIndex: Int?
        for i in 3..<segments.count {
            let name = segments[i].removingPercentEncoding?.lowercased() ?? ""
            if name.hasSuffix(".zip") || name.hasSuffix(".rar") { containerIndex = i; break }
        }
        guard let idx = containerIndex, idx + 1 < segments.count else { return nil }
        let memberParts = segments[(idx + 1)...].map { $0.removingPercentEncoding ?? "" }
        guard memberParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("|") && !$0.contains("\\")
                  && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) else { return nil }
        // %2F inside one segment decodes to "/": re-check every resulting component.
        guard memberParts.joined(separator: "/").split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        let containerParts = segments[1...idx].compactMap { $0.removingPercentEncoding }
        guard containerParts.count == idx,
              containerParts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("|") && !$0.contains("\\")
                  && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }) else { return nil }
        // Encode each component independently: a decoded slash in a filename
        // must stay %2F, not become a hierarchy delimiter.
        let keep = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedParts = containerParts.compactMap { $0.addingPercentEncoding(withAllowedCharacters: keep) }
        guard encodedParts.count == containerParts.count else { return nil }
        let escaped = "https://archive.org/" + encodedParts.joined(separator: "/")
        return "archive://" + escaped + "|/" + memberParts.joined(separator: "/")
    }

    private func showingPanel<T>(_ block: () -> T) -> T {
        overlayWin?.ignoresMouseEvents = true
        let result = block()
        overlayWin?.ignoresMouseEvents = false
        return result
    }
        
    // MARK: - NSApplication Delegate
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if PanelKeyOwnership.shared.mayKeyPlayerWindow(), let pid = mpvProcess?.processIdentifier {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, true as CFTypeRef)
        }
        overlayWin?.orderFrontRegardless()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    
    func applicationWillUpdate(_ notification: Notification) {
        // keep the Edit menu enabled while an input panel is up
        if isShowingInputPanel {
            NSApp.mainMenu?.items.forEach { menuItem in
                if menuItem.title == "edit" {
                    menuItem.isEnabled = true
                }
            }
        }
    }
    
}

// MARK: - Explicit panel focus

extension NSPanel {
    // Explicit panel opening/refocusing owns this one activation. Later focus returns are handled
    // by GORInputPanel's native key/click transitions, not delayed activation attempts.
    func assertKeyAndFocus(_ view: NSView) {
        guard view.window === self, !NoActivate.active else{return}
        (self as? GORInputPanel)?.rememberFocus(view)
        if !NoActivate.active {NSApp.activate(ignoringOtherApps:true)}
        makeKeyAndOrderFront(nil)
        _=makeFirstResponder(view)
        DispatchQueue.main.async { [weak self,weak view] in
            guard let panel=self,let view,panel.isVisible,panel.isKeyWindow,view.window === panel else{return}
            (panel as? GORInputPanel)?.restorePanelFocus()
        }
    }
}

extension AppDelegate {
    @objc func openMagnetSearch() {
        VariationBroadcaster.shared.noteOpenPath("CmdM-panel")
        if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
        if let browser = magnetBrowser {
            if browser.panel.superview != nil {
                controller?.wakeUI()
                browser.openSearch(); return
            }
            // Stale controller whose panel is detached: tear it down so exactly one instance exists.
            browser.panel.onClose?()
            magnetBrowser = nil
        }
        guard let parent = overlayWin, let content = parent.contentView,
              let ctrl = controller else { return }
        let panel = MagnetResultsPanel(frame: .zero)
        panel.layer?.zPosition = 6100
        ctrl.registerVideoFramePanel(panel, padL: 40, padR: IconBarFit.panelPadR(padL: 40), padT: 9)
        let browser = MagnetBrowserController(app:self, panel:panel)
        magnetBrowser = browser
        panel.onClose = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.magnetBrowser?.stop()
            panel.removeFromSuperview()
            self.controller?.unregisterVideoFramePanel(panel)
            self.magnetBrowser = nil
            self.isShowingInputPanel = false
            self.overlayWin?.ignoresMouseEvents = false
            self.setEventTapEnabled(true)
        }
        content.addSubview(panel)
        panel.isHidden = true // first Cmd+M shows only the floating search bar
        isShowingInputPanel = true
        setEventTapEnabled(false)
        parent.ignoresMouseEvents = false
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak panel] event in
            guard event.keyCode == 53, let panel, panel.superview != nil else { return event }
            if let input = event.window as? GORInputPanel {
                guard input.isKeyWindow,!input.hasMarkedText else{return event}
                input.cancelOperation(nil);return nil
            }
            guard event.window === panel.window else{return event}
            if panel.isSearchOpen == true {
                panel.dismissSearch()
                return nil
            }
            panel.onClose?(); return nil
        }
        let previous = panel.onClose
        panel.onClose = {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            previous?()
        }
        ctrl.wakeUI()
        browser.openSearch()
    }
}



/// Menu rows are pure data so the same real builder is exercised without AppKit.
struct NativeTrackRow {
    let id:Int
    let title:String
    let selected:Bool
}
enum NativeTrackMenu {
    static func rows(_ tracks:[[String:Any]],type:String)->[NativeTrackRow] {
        let matching=tracks.filter { $0["type"] as? String == type }
        var rows:[NativeTrackRow]=[]
        if type == "sub" {
            rows.append(NativeTrackRow(id:-1,title:"off",selected: !matching.contains { $0["selected"] as? Bool == true }))
        }
        for track in matching {
            guard let id=track["id"] as? Int else {continue}
            var parts=["track \(id)"]
            for key in ["title","lang","codec"] {
                if let text=track[key] as? String,!text.isEmpty {parts.append(text)}
            }
            for key in ["default","external"] where track[key] as? Bool == true {parts.append(key)}
            rows.append(NativeTrackRow(id:id,title:parts.joined(separator:" · "),selected:track["selected"] as? Bool == true))
        }
        return rows
    }
    static func property(_ type:String)->String { type == "audio" ? "aid" : type == "video" ? "vid" : "sid" }
}
extension AppDelegate {
    func menuNeedsUpdate(_ menu:NSMenu) {
        if menu.title == "output device" {rebuildAudioDeviceMenu(menu);return}
        guard let type=["video tracks":"video","audio tracks":"audio","subtitle tracks":"sub"][menu.title] else{return}
        for item in menu.items where item.tag == 7401 {menu.removeItem(item)}
        let snapshot=controller?.nativeTrackSnapshot()
        let rows=NativeTrackMenu.rows(snapshot?.tracks ?? [],type:type)
        let divider=NSMenuItem.separator();divider.tag=7401;menu.insertItem(divider,at:0)
        if rows.isEmpty {
            let empty=NSMenuItem(title:"no \(type) tracks",action:nil,keyEquivalent:"");empty.tag=7401;empty.isEnabled=false
            menu.insertItem(empty,at:0)
        }
        for row in rows.reversed() {
            let item=NSMenuItem(title:row.title,action:#selector(menuSelectTrack(_:)),keyEquivalent:"")
            item.target=self;item.tag=7401;item.state=row.selected ? .on : .off
            item.representedObject=["type":type,"id":String(row.id),"path":snapshot?.path ?? ""]
            menu.insertItem(item,at:0)
        }
    }
    /// audio > output device: the list mpv itself reports, rebuilt on every
    /// open; checkmarks read mpv's current audio-device, never a local guess.
    func rebuildAudioDeviceMenu(_ menu:NSMenu) {
        for item in menu.items where item.tag == 7402 {menu.removeItem(item)}
        let snapshot=controller?.nativeAudioDeviceSnapshot()
        let current=snapshot?.current ?? "auto"
        let devices=snapshot?.devices ?? []
        let auto=NSMenuItem(title:"auto (system default)",action:#selector(menuSelectAudioDevice(_:)),keyEquivalent:"")
        auto.target=self;auto.tag=7402;auto.representedObject="auto"
        auto.state=current == "auto" ? .on : .off
        menu.insertItem(auto,at:0)
        if devices.isEmpty {
            let empty=NSMenuItem(title:"no output devices",action:nil,keyEquivalent:"");empty.tag=7402;empty.isEnabled=false
            menu.insertItem(empty,at:1)
            return
        }
        for device in devices.reversed() {
            let item=NSMenuItem(title:device.label,action:#selector(menuSelectAudioDevice(_:)),keyEquivalent:"")
            item.target=self;item.tag=7402;item.state=device.name == current ? .on : .off
            item.representedObject=device.name
            menu.insertItem(item,at:1)
        }
    }
    @objc func menuSelectTrack(_ item:NSMenuItem) {
        guard let selection=item.representedObject as? [String:String],let type=selection["type"],let raw=selection["id"],let id=Int(raw),let ctrl=controller else{return}
        let live=ctrl.nativeTrackSnapshot()
        guard !live.path.isEmpty,live.path==selection["path"],
              NativeTrackMenu.rows(live.tracks,type:type).contains(where:{$0.id==id}) else{return}
        let value:Any=id == -1 ? "no" : id
        let command:[String:Any]=["command":["set_property",NativeTrackMenu.property(type),value]]
        if let data=try? JSONSerialization.data(withJSONObject:command),let json=String(data:data,encoding:.utf8) {ctrl.ipcCommand(json)}
        if type == "sub",id != -1 {
            ctrl.ipcCommand(#"{"command":["set_property","sub-visibility",false]}"#)
            ctrl.ipcCommand(#"{"command":["set_property","secondary-sub-visibility",false]}"#)
            ctrl.subtitleView.isHidden=false
        }
    }
}

/// Window frame plans preserve the original UI and leave native window fencing to AppDelegate.
enum PlayerWindowPlacement {
    static func usableFrame(screen:CGRect,visible:CGRect,menuAutoHides:Bool)->CGRect {
        // NSScreen.visibleFrame includes Dock exclusion. With auto-hide enabled,
        // a temporarily revealed menu bar must not reserve permanent top space.
        guard menuAutoHides else{return visible}
        return CGRect(x:visible.minX,y:visible.minY,width:visible.width,height:max(0,screen.maxY-visible.minY))
    }
    static func frame(mode:String,current:CGRect,visible:CGRect)->CGRect {
        var r=current
        switch mode {
        case "zoom","fill":
            let factor=min(visible.width/max(1,r.width),visible.height/max(1,r.height))
            r=CGRect(x:visible.midX-r.width*factor/2,y:visible.midY-r.height*factor/2,width:r.width*factor,height:r.height*factor)
        case "smaller","larger":
            let factor:CGFloat=mode == "smaller" ? 0.8 : 1.25
            r=CGRect(x:r.midX-r.width*factor/2,y:r.midY-r.height*factor/2,width:r.width*factor,height:r.height*factor)
        default:break
        }
        // Position commands do not resize unless the current window cannot fit.
        // Oversize windows shrink uniformly, preserving their existing aspect.
        let fit=min(1,visible.width/max(1,r.width),visible.height/max(1,r.height))
        r.size=CGSize(width:r.width*fit,height:r.height*fit)
        switch mode {
        case "top-left":r.origin=CGPoint(x:visible.minX,y:visible.maxY-r.height)
        case "top-right":r.origin=CGPoint(x:visible.maxX-r.width,y:visible.maxY-r.height)
        case "bottom-left":r.origin=CGPoint(x:visible.minX,y:visible.minY)
        case "bottom-right":r.origin=CGPoint(x:visible.maxX-r.width,y:visible.minY)
        case "center":r.origin=CGPoint(x:visible.midX-r.width/2,y:visible.midY-r.height/2)
        default:break
        }
        r.origin.x=min(max(r.minX,visible.minX),visible.maxX-r.width)
        r.origin.y=min(max(r.minY,visible.minY),visible.maxY-r.height)
        return r
    }
}

extension AppDelegate {
    func installAudioDeviceSubmenu(in parent:NSMenu) {
        let row=NSMenuItem(title:"output device",action:nil,keyEquivalent:"")
        let menu=NSMenu(title:"output device");menu.delegate=self;row.submenu=menu
        parent.addItem(row)
    }
    func installTrackSubmenu(in parent:NSMenu,type:String) {
        let row=NSMenuItem(title:"tracks",action:nil,keyEquivalent:"")
        let title=type == "video" ? "video tracks" : type == "audio" ? "audio tracks" : "subtitle tracks"
        let menu=NSMenu(title:title);menu.delegate=self;row.submenu=menu
        parent.addItem(row);parent.addItem(.separator())
    }
    @objc func menuWindowMinimize(){
        if activePlayerEngine == .gorav,let window=embeddedWindow {
            if window.isMiniaturized {window.deminiaturize(nil)} else {window.miniaturize(nil)};return
        }
        togglePlayerMinimize()
    }
    @objc func menuWindowPlacement(_ sender:NSMenuItem){if let mode=sender.representedObject as? String {placePlayerWindow(mode)}}
    @objc func menuWindowFront(){if activePlayerEngine == .gorav {embeddedWindow?.makeKeyAndOrderFront(nil);return};if !NoActivate.active {NSApp.activate(ignoringOtherApps:true)};if !NoActivate.active {NSApp.arrangeInFront(nil);overlayWin?.makeKeyAndOrderFront(nil)}}
    private func shortcutLines(_ menu:NSMenu,prefix:String="")->[String] {
        var lines:[String]=[]
        for item in menu.items where !item.isSeparatorItem {
            let label=prefix.isEmpty ? item.title : prefix+" > "+item.title
            if let child=item.submenu {lines+=shortcutLines(child,prefix:label)}
            else if !item.keyEquivalent.isEmpty {
                let f=item.keyEquivalentModifierMask
                let mods=(f.contains(.control) ? "\u{2303}" : "")+(f.contains(.option) ? "\u{2325}" : "")+(f.contains(.shift) ? "\u{21E7}" : "")+(f.contains(.command) ? "\u{2318}" : "")
                lines.append(label+"    "+mods+(item.keyEquivalent == " " ? "Space" : item.keyEquivalent.uppercased()))
            }
        }
        return lines
    }
    @objc func menuHelpShortcuts(){
        let alert=NSAlert();alert.messageText="Keyboard Shortcuts"
        alert.informativeText="Current menu shortcuts. Player-only keys follow the active player; text fields keep editing keys."
        let scroll=NSScrollView(frame:CGRect(x:0,y:0,width:620,height:420));scroll.hasVerticalScroller=true
        let text=NSTextView(frame:scroll.bounds);text.isEditable=false;text.isSelectable=true
        text.string=NSApp.mainMenu.map{shortcutLines($0).joined(separator:"\n")} ?? ""
        scroll.documentView=text;alert.accessoryView=scroll;alert.addButton(withTitle:"Close");alert.runModal()
    }
    @objc func menuHelpIssueReport(){
        let version=Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let report="gor issue report\nVersion: "+version+"\nmacOS: "+ProcessInfo.processInfo.operatingSystemVersionString+"\n\nWhat happened:\n\nSteps to reproduce:\n\nExpected result:\n"
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(report,forType:.string)
        let alert=NSAlert();alert.messageText="Issue report copied"
        alert.informativeText="Paste this template into your existing support conversation. Add the steps and expected result. No media paths, titles or private logs were copied."
        alert.addButton(withTitle:"OK");alert.runModal()
    }
}

enum PlayerPictureInPicture {
    enum Direction {
        case left, right, down, up
    }

    static func direction(keyCode: UInt16, fnHeld: Bool) -> Direction? {
        guard fnHeld else { return nil }
        switch keyCode {
        case 115: return .left   // fn-left is Home on Apple keyboards.
        case 119: return .right  // fn-right is End.
        case 121: return .down   // fn-down is Page Down.
        case 116: return .up     // fn-up is Page Up.
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }

    static func directionalFrame(current: CGRect, screen: CGRect, direction: Direction) -> CGRect {
        var horizontal = current.midX < screen.midX ? "left" : "right"
        var vertical = current.midY < screen.midY ? "bottom" : "top"
        switch direction {
        case .left: horizontal = "left"
        case .right: horizontal = "right"
        case .down: vertical = "bottom"
        case .up: vertical = "top"
        }
        return PlayerWindowPlacement.frame(mode: vertical + "-" + horizontal,
                                           current: current, visible: screen)
    }

    static func croppedFrame(current:CGRect,screen:CGRect,aspect:Double)->CGRect {
        guard aspect.isFinite,aspect>0 else{return current}
        let a=CGFloat(aspect)
        // Keep the PiP's long-side budget, not an old16:9 window ratio.
        let budget=max(current.width,current.height)
        let size=a>=1 ? CGSize(width:budget,height:budget/a) : CGSize(width:budget*a,height:budget)
        let proposed=CGRect(x:current.midX-size.width/2,y:current.midY-size.height/2,width:size.width,height:size.height)
        return nearestCorner(candidate:proposed,screen:screen)
    }
    static func nearestCorner(candidate:CGRect,screen:CGRect)->CGRect {
        let horizontal=candidate.midX < screen.midX ? "left" : "right"
        let vertical=candidate.midY < screen.midY ? "bottom" : "top"
        return PlayerWindowPlacement.frame(mode:vertical+"-"+horizontal,current:candidate,visible:screen)
    }
    static func frame(current:CGRect,visible:CGRect,preferred:CGRect?=nil)->CGRect {
        if let saved=preferred,saved.width>0,saved.height>0,
           saved.minX>=visible.minX,saved.maxX<=visible.maxX,saved.minY>=visible.minY,saved.maxY<=visible.maxY {
            return croppedFrame(current:saved,screen:visible,aspect:Double(current.width/max(1,current.height)))
        }
        // At most a third of either display dimension, never enlarge a small window.
        let scale=min(1,visible.width*0.32/max(1,current.width),visible.height*0.32/max(1,current.height))
        let small=CGRect(x:current.minX,y:current.minY,width:current.width*scale,height:current.height*scale)
        return PlayerWindowPlacement.frame(mode:"bottom-left",current:small,visible:visible)
    }
}
extension AppDelegate {
    @discardableResult
    func movePictureInPicture(direction: PlayerPictureInPicture.Direction) -> Bool {
        guard pictureInPictureActive, !windowGeometryTransitionActive,
              let window = overlayWin, let screen = window.screen ?? NSScreen.main else { return false }
        // Snap stores the committed target before easing starts. Use it for rapid
        // orthogonal key presses, not an intermediate physical animation frame.
        let saved = UserDefaults.standard.string(forKey: "gor.pip.preferredFrame").map { NSRectFromString($0) }
        let current = saved.flatMap { frame -> CGRect? in
            guard frame.width > 0, frame.height > 0,
                  screen.frame.contains(frame) else { return nil }
            return frame
        } ?? window.frame
        let target = PlayerPictureInPicture.directionalFrame(current: current, screen: screen.frame,
                                                            direction: direction)
        if target != current { snapPictureInPicture(target) }
        return true
    }

    @objc func menuPictureInPicture(){
        if activePlayerEngine == .gorav {toggleEmbeddedPiP();return}
        togglePlayerPictureInPicture()
    }
}

/// Stable content-based sizing: never derive a new aspect from rounded window receipts.
enum PlayerWindowSizing {
    static func nextScale(_ current:Double,mode:String)->Double {
        min(4,max(0.1,current*(mode == "smaller" ? 0.8 : 1.25)))
    }
    static func frame(mode:String,current:CGRect,screen:CGRect,video:CGSize,resetDefault:Bool,userScale:Double=1)->CGRect {
        guard video.width>0,video.height>0 else{return current}
        let aspect=video.width/video.height
        var size=current.size
        if resetDefault {
            let proposed=GorVideoFit.proposedOpenSize(videoW:Double(video.width),videoH:Double(video.height),screenW:Double(screen.width))
            size=CGSize(width:proposed.w*userScale,height:proposed.w*userScale/Double(aspect))
        } else if mode == "fill" || mode == "zoom" {
            size=CGSize(width:screen.width,height:screen.width/aspect)
        }
        let fit=min(1,screen.width/max(1,size.width),screen.height/max(1,size.height))
        size=CGSize(width:size.width*fit,height:size.height*fit)
        return CGRect(x:screen.midX-size.width/2,y:screen.midY-size.height/2,width:size.width,height:size.height)
    }
}

struct VideoFormat {
    let title:String
    let ratio:Double
}
enum VideoFormatCatalog {
    static let formats:[VideoFormat]=[
        VideoFormat(title:"9:16",ratio:9.0/16),VideoFormat(title:"2:3",ratio:2.0/3),
        VideoFormat(title:"3:4",ratio:3.0/4),VideoFormat(title:"4:5",ratio:4.0/5),
        VideoFormat(title:"1:1",ratio:1),VideoFormat(title:"5:4",ratio:5.0/4),
        VideoFormat(title:"4:3",ratio:4.0/3),VideoFormat(title:"1.37:1",ratio:1.37),
        VideoFormat(title:"1.43:1",ratio:1.43),VideoFormat(title:"3:2",ratio:1.5),
        VideoFormat(title:"16:10",ratio:1.6),VideoFormat(title:"1.66:1",ratio:1.66),
        VideoFormat(title:"16:9",ratio:16.0/9),VideoFormat(title:"1.85:1",ratio:1.85),
        VideoFormat(title:"2:1",ratio:2),VideoFormat(title:"2.20:1",ratio:2.2),
        VideoFormat(title:"2.35:1",ratio:2.35),VideoFormat(title:"2.39:1",ratio:2.39),
        VideoFormat(title:"2.55:1",ratio:2.55),VideoFormat(title:"2.59:1",ratio:2.59),
        VideoFormat(title:"2.76:1",ratio:2.76),VideoFormat(title:"3:1",ratio:3),
        VideoFormat(title:"4:1",ratio:4),VideoFormat(title:"5:1",ratio:5),
        VideoFormat(title:"6:1",ratio:6),VideoFormat(title:"7:1",ratio:7),VideoFormat(title:"8:1",ratio:8)]
    static func parse(_ text:String)->Double? {
        let parts=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"/",with:":").split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==1 || parts.count==2,let w=Double(parts[0]),w.isFinite,w>0 else{return nil}
        let h=parts.count==2 ? Double(parts[1]) : 1
        guard let h,h.isFinite,h>0 else{return nil}
        let r=w/h
        return r>=0.1 && r<=20 ? r : nil
    }
    struct SourceCrop {let commandValue:String;let width:Int;let height:Int}
    static func sourceCrop(aspect:Double,params:[String:Any])->SourceCrop? {
        func n(_ key:String)->Double { (params[key] as? Double) ?? (params[key] as? Int).map(Double.init) ?? 0 }
        let w=n("w"),h=n("h"),par=n("par")>0 ? n("par") : 1
        guard w>=16,h>=16,aspect.isFinite,aspect>0 else{return nil}
        let rotation=Int(n("rotate")) % 180
        let pixelAspect=(rotation == 0 ? aspect : 1/aspect)/par
        let cw=min(w,h*pixelAspect),ch=min(h,w/pixelAspect)
        let width=max(2,Int(cw/2)*2),height=max(2,Int(ch/2)*2)
        let x=max(0,Int((w-Double(width))/4)*2),y=max(0,Int((h-Double(height))/4)*2)
        let value=width==Int(w) && height==Int(h) ? "" : "\(width)x\(height)+\(x)+\(y)"
        return SourceCrop(commandValue:value,width:width,height:height)
    }
}
extension AppDelegate {
    func populateVideoFormats(_ menu:NSMenu,crop:Bool) {
        menu.addItem(item("cycle",action:crop ? #selector(menuCycleCrop) : #selector(menuCycleAspect),key:"a",mods:crop ? [.command, .control, .option, .shift] : [.command, .control, .option]))   // walks this list, wraps to no override; the rows stay click-only - 27 chords would exhaust the keyboard
        menu.addItem(item("reset",action:crop ? #selector(menuCropReset) : #selector(menuAspectDefault),key:crop ? "c" : "",mods:crop ? [.command,.control,.option] : .command))
        menu.addItem(.separator())
        for format in VideoFormatCatalog.formats {
            let row=item(format.title,action:#selector(menuVideoFormat(_:)),key:"")
            row.representedObject=["kind":crop ? "crop" : "aspect","ratio":String(format.ratio)]
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let manual=item("manual...",action:#selector(menuManualVideoFormat(_:)),key:"")
        manual.representedObject=crop ? "crop" : "aspect";menu.addItem(manual)
        if !crop {
            menu.addItem(.separator())
            menu.addItem(item("expand horizontal (+0.1)",action:#selector(menuAspectExpandH),key:String(UnicodeScalar(NSRightArrowFunctionKey)!),mods:[.function, .command, .control, .option, .shift]))
            menu.addItem(item("shrink horizontal (-0.1)",action:#selector(menuAspectShrinkH),key:String(UnicodeScalar(NSLeftArrowFunctionKey)!),mods:[.function, .command, .control, .option, .shift]))
            menu.addItem(item("expand vertical (+0.1)",action:#selector(menuAspectExpandV),key:String(UnicodeScalar(NSUpArrowFunctionKey)!),mods:[.function, .command, .control, .option, .shift]))
            menu.addItem(item("shrink vertical (-0.1)",action:#selector(menuAspectShrinkV),key:String(UnicodeScalar(NSDownArrowFunctionKey)!),mods:[.function, .command, .control, .option, .shift]))
        }
    }
    private func selectVideoFormat(_ ratio:Double,crop:Bool) {
        if crop {
            // A crop target is a source-picture shape, not a stale display override.
            setAspect(.defaultAR)
            if controller?.applyMenuCrop(aspect:ratio) != true {
                let alert=NSAlert();alert.messageText="crop unavailable";alert.informativeText="The current decoder dimensions could not be read. No crop was applied.";alert.runModal()
            }
        } else {setAspect(.ratio(ratio))}
    }
    @objc func menuVideoFormat(_ sender:NSMenuItem) {
        guard let choice=sender.representedObject as? [String:String],let ratio=Double(choice["ratio"] ?? "") else{return}
        selectVideoFormat(ratio,crop:choice["kind"] == "crop")
    }
    @objc func menuManualVideoFormat(_ sender:NSMenuItem) {
        let crop=sender.representedObject as? String == "crop"
        let alert=NSAlert();alert.messageText=crop ? "manual crop" : "manual aspect ratio"
        alert.informativeText="Enter width:height (4:3), width/height, or a decimal ratio (1.85). Range: 0.1 to 20."
        let field=NSTextField(frame:CGRect(x:0,y:0,width:260,height:24));field.placeholderString="4:3"
        alert.accessoryView=field;alert.addButton(withTitle:"apply");alert.addButton(withTitle:"cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        guard let ratio=VideoFormatCatalog.parse(field.stringValue) else {
            let error=NSAlert();error.messageText="invalid ratio";error.informativeText="Use a positive ratio such as 4:3 or 1.85, between 0.1 and 20.";error.runModal();return
        }
        selectVideoFormat(ratio,crop:crop)
    }
}

// BEGIN station-move AudioMenuControls.swift
import AppKit

// Audio menu expansion (owner, 2026-11-08: "there are too few audio menu items.
// are those the only settings video players have?"). The video-player audio
// set mpv already supports, wired as menu rows: volume boost above 100%,
// output device, channel layout/downmix, dynamics (night mode, loudness
// normalize) and equalizer presets. Delay keeps its existing group.
//
// One-of lists and toggles are tracked in AudioMenuState: these paths have
// no input.conf binding and no other UI, so the tracked value cannot drift
// from what mpv was sent; checkmarks mirror it. The device list is re-read
// from mpv itself on every menu open (MenuActions.rebuildAudioDeviceMenu).
extension AppDelegate {

    enum AudioMenuState {
        static var channelLayout = "auto-safe"   // mpv's own default
        static var nightMode = false
        static var normalize = false
        static var equalizer = "off"
    }

    /// Equalizer preset name -> single-band ffmpeg equalizer curve. The
    /// labeled filter (@goreq) is replaced as a unit, so presets never stack.
    static let audioEqualizerPresets: [String: String] = [
        "bass boost": "equalizer=f=100:t=h:w=100:g=6",
        "voice": "equalizer=f=3000:t=h:w=1500:g=5",
        "treble": "equalizer=f=8000:t=h:w=3000:g=5",
    ]

    // MARK: boost (volume above 100%)

    @objc func menuVolBoostUp() {
        controller?.batchIPC([#"{"command":["set_property","volume-max",200]}"#,
                              #"{"command":["add","volume",10]}"#].joined(separator: "\n"),
                             timeout: 5.0)
    }

    @objc func menuVolBoostDown() {
        controller?.batchIPC([#"{"command":["add","volume",-10]}"#].joined(separator: "\n"),
                             timeout: 5.0)
    }

    @objc func menuVolBoostOff() {
        controller?.batchIPC([#"{"command":["set_property","volume",100]}"#,
                              #"{"command":["set_property","volume-max",130]}"#].joined(separator: "\n"),
                             timeout: 5.0)
    }

    // MARK: output device (list comes from mpv on every open)

    @objc func menuSelectAudioDevice(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let command: [String: Any] = ["command": ["set_property", "audio-device", name]]
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let json = String(data: data, encoding: .utf8) else { return }
        controller?.ipcCommand(json)
    }

    // MARK: channel layout / downmix

    @objc func menuAudioChannels(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        AudioMenuState.channelLayout = value
        cmd("{\"command\":[\"set_property\",\"audio-channels\",\"\(value)\"]}")
    }

    // MARK: dynamics

    @objc func menuNightMode() {
        AudioMenuState.nightMode.toggle()
        cmd(#"{"command":["af","toggle","@gornight:dynaudnorm"]}"#)
    }

    @objc func menuNormalize() {
        AudioMenuState.normalize.toggle()
        cmd(#"{"command":["af","toggle","@gornorm:lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]"]}"#)
    }

    // MARK: equalizer presets

    @objc func menuAudioEqualizer(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        AudioMenuState.equalizer = name
        var lines = [#"{"command":["af","remove","@goreq"]}"#]
        if let curve = AppDelegate.audioEqualizerPresets[name] {
            lines.append("{\"command\":[\"af\",\"add\",\"@goreq:lavfi=[\(curve)]\"]}")
        }
        controller?.batchIPC(lines.joined(separator: "\n"), timeout: 5.0)
    }
}
// END station-move AudioMenuControls.swift

// BEGIN station-move UpdateChecks.swift
import AppKit

// General update button (owner, 2026-11-08: "rename check chromium in the gor menu;
// make that item the general update button"). The old
// chromium-only item becomes "update": one press checks every component gor
// can update by itself - the vendored chromium headless shell and the staged
// yt-dlp - and is wired to include the app/repo update the moment the
// auto-update engine is activated. The engine stays OFF: this file only reads
// its config; nothing here enables a flag, swaps a binary or schedules a poll.
extension AppDelegate {

    enum UpdateChecks {
        /// Pinned vendor components (VENDOR.md freeze) have no self-update
        /// path by design: they ride the app/repo update. Keep in sync with
        /// VENDOR.md; reported so a press never looks like it forgot them.
        static let repoManaged = "mpv/ffmpeg, node/webtorrent, whisper, mus2"

        /// The folder the running gor.app sits in: the auto-update engine's
        /// <project> (its config is <project>/.gor-autoupdate/config.json).
        static func projectDirectory() -> URL {
            URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        }

        /// Engine state, read-only, from the exact file the Python engine
        /// (tools/autoupdate.py Updater.config) writes. Missing or malformed
        /// means off; only the owner turns it on.
        static func appUpdateEnabled(project: URL) -> Bool {
            let config = project.appendingPathComponent(".gor-autoupdate/config.json")
            guard let data = try? Data(contentsOf: config),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let enabled = object["enabled"] as? Bool else { return false }
            return enabled
        }

        /// Where the engine script can live once it ships: inside the bundle
        /// resources first, then the source project layout (dev builds).
        static func engineScript(project: URL) -> String? {
            let candidates: [String?] = [
                Bundle.main.resourceURL?.appendingPathComponent("autoupdate.py").path,
                project.appendingPathComponent("tools/autoupdate.py").path,
            ]
            return candidates.compactMap { $0 }.first { FileManager.default.isReadableFile(atPath: $0) }
        }
    }

    @objc func menuUpdate() {
        print("[update] general update check started")
        menuCheckChromiumUpdate()   // keeps its own [chromium-update] log tag
        checkYtDlpOnDemand()
        print("[update] pinned components (\(UpdateChecks.repoManaged)) update with the app")
        checkAppUpdateOnDemand()
    }

    private func checkYtDlpOnDemand() {
        guard !ytdlpUpdateInProgress else {
            print("[update] yt-dlp: check already running")
            return
        }
        let path = AppDelegate.stagedYtDlpPath()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            print("[update] yt-dlp: binary missing")
            return
        }
        ytdlpUpdateInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["-U"]
            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            do {
                try task.run()
                task.waitUntilExit()
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: bytes, encoding: .utf8) ?? ""
                print("[update] yt-dlp: status=\(task.terminationStatus) \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            } catch {
                print("[update] yt-dlp: failed to launch: \(error)")
            }
            DispatchQueue.main.async { self?.ytdlpUpdateInProgress = false }
        }
    }

    private func checkAppUpdateOnDemand() {
        let project = UpdateChecks.projectDirectory()
        guard UpdateChecks.appUpdateEnabled(project: project) else {
            print("[update] app: auto-update engine off; app/repo check joins this button once the owner activates it")
            return
        }
        guard let script = UpdateChecks.engineScript(project: project) else {
            print("[update] app: engine enabled but autoupdate.py not shipped in this layout; skipped")
            return
        }
        // The engine's sidecar is the repo-sync checkout (milat layout).
        let sidecar = StagedRunPaths.home(FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("Downloads/gor-repo-sync").path
        guard FileManager.default.fileExists(atPath: sidecar) else {
            print("[update] app: repo-sync checkout missing at \(sidecar); skipped")
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [script, "--project", project.path, "--sidecar", sidecar, "fetch-release"]
            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            do {
                try task.run()
                task.waitUntilExit()
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: bytes, encoding: .utf8) ?? ""
                print("[update] app: status=\(task.terminationStatus) \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            } catch {
                print("[update] app: engine failed to launch: \(error)")
            }
        }
    }
}
// END station-move UpdateChecks.swift

// BEGIN station-move VideoFormatCycle.swift
import AppKit

// Aspect / crop format cycling (owner, 2026-11-08).
//
// Control-Option-Command-A steps the aspect override, Shift joins for the
// crop. The walk runs through the shared VideoFormatCatalog list the two
// menus show, in menu order, and wraps to "no override" (aspect default /
// crop off) after the widest format. State is read where the menu checkmarks
// read it - currentAspectPreset for the aspect override and the controller's
// selectedMenuCropAspect for the crop - so clicking a format row resumes the
// walk at that format. A manual entry or a fine-nudged value resumes at the
// first wider format; past the widest, the walk wraps. Every step answers on
// mpv's own OSD, like the other toggles: a repeat chord never raises a modal.
extension AppDelegate {
    enum VideoFormatCycle {
        // -1 = no override. Same 0.005 reuse tolerance as the aspect handlers.
        static func nextIndex(current: Double?, formats: [VideoFormat]) -> Int {
            guard !formats.isEmpty else { return -1 }
            guard let current else { return 0 }
            for (i, format) in formats.enumerated() where abs(format.ratio - current) < 0.005 {
                return i + 1 < formats.count ? i + 1 : -1
            }
            for (i, format) in formats.enumerated() where format.ratio > current { return i }
            return -1
        }
    }

    // Transient on-screen text through mpv's OSD, matching showCropDetectOSD.
    private func osdFormat(_ text: String) {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        cmd("{\"command\":[\"show-text\",\"\(escaped)\",2500]}")
    }

    @objc func menuCycleAspect() {
        let formats = VideoFormatCatalog.formats
        let current: Double?
        if case .ratio(let value) = currentAspectPreset { current = value } else { current = nil }
        let next = VideoFormatCycle.nextIndex(current: current, formats: formats)
        if next < 0 {
            setAspect(.defaultAR)
            osdFormat("aspect: default")
        } else {
            setAspect(.ratio(formats[next].ratio))
            osdFormat("aspect: \(formats[next].title)")
        }
    }

    @objc func menuCycleCrop() {
        guard let ctrl = controller else { return }
        let formats = VideoFormatCatalog.formats
        let next = VideoFormatCycle.nextIndex(current: ctrl.selectedMenuCropAspect, formats: formats)
        if next < 0 {
            ctrl.resetCrop()
            osdFormat("crop: off")
            return
        }
        if ctrl.applyMenuCrop(aspect: formats[next].ratio) {
            // A crop target is a source-picture shape, not a stale display override.
            setAspect(.defaultAR)
            osdFormat("crop: \(formats[next].title)")
        } else {
            osdFormat("crop unavailable: decoder dimensions unreadable")
        }
    }
}
// END station-move VideoFormatCycle.swift
