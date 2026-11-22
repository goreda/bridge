#if canImport(AppKit)
import AppKit
import CoreGraphics

// Owned only by the gorav integration backend. Never attach to or search for mpv.
// Retain for the session lifetime; supply the renderer as contentView and upload
// onTransform to the session's typed fit parameter block (zoom is log2 scale).
@MainActor
final class GorAVHostWindow: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onCropInterruption:(()->Void)?
    private var cropFrameOwned=false
    let window: NSWindow
    private var motion = GorAVHostMotion()
    private let onTransform: (GorAVHostTransform) -> Void
    private var timer: Timer?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var placedInitialFrame = false
    private var videoSize = NSSize(width: 16, height: 9)
    private var aspect = NSSize(width: 16, height: 9)
    private var transition = false
    private var applyingFrame = false
    private var keepAspect = true
    private var restorePiPFrame: NSRect?
    private var restorePiPLevel: NSWindow.Level?
    private var heldKeys = Set<UInt16>()

    init(contentView: NSView, playerWindow:NSWindow?=nil, onTransform: @escaping (GorAVHostTransform) -> Void) {
        self.onTransform = onTransform
        // An engine swap preserves the player's actual chrome object and frame.
        // A cold gorav launch uses the same borderless constructor as mpv.
        let frame=Self.initialPlayerFrame(screen:NSScreen.main?.visibleFrame)
        window = playerWindow ?? DraggableOverlayWindow.playerWindow(frame:frame)
        placedInitialFrame = playerWindow != nil
        super.init()
        window.styleMask = [.borderless]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = .normal
        contentView.frame=NSRect(origin:.zero,size:window.contentRect(forFrameRect:window.frame).size)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = contentView
        window.delegate = self
        window.contentAspectRatio = aspect
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains([.function, .shift]) { self?.releaseKeys() }
            return event
        }
    }

    static func initialPlayerFrame(screen:NSRect?)->NSRect {
        guard let area=screen,area.width.isFinite,area.height.isFinite,area.width>=160,area.height>=90 else {
            return NSRect(x:0,y:0,width:640,height:360)
        }
        let width=min(area.width,max(160,area.width*0.4))
        let height=min(area.height*0.9,max(90,width*9/16))
        return NSRect(x:area.midX-width/2,y:area.midY-height/2,width:width,height:height)
    }

    private var panelFadeStarted = false
    private var panelFadeFinished = false
    private var panelFadeCompletions: [() -> Void] = []
    private var programmaticCloseRequested = false
    private var closeFinalized = false
    private var closeNotified = false
    private var windowCloseObserved = false
    private var closeCompletions: [() -> Void] = []
    private func afterOwnedPanelFade(_ completion: @escaping () -> Void) {
        if panelFadeFinished { completion(); return }
        panelFadeCompletions.append(completion)
        guard !panelFadeStarted else { return }
        panelFadeStarted = true
        GORInputPanel.fadePanelsOwned(by: window, duration: 0.77) { [self] in
            panelFadeFinished = true
            let pending = panelFadeCompletions
            panelFadeCompletions.removeAll()
            for done in pending { done() }
        }
    }
    private func stopCloseInputs() {
        motion.releaseHold(immediate: true); heldKeys.removeAll(); stopTimer()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor); self.flagsMonitor = nil }
    }
    private func drainCloseCompletions() {
        let pending = closeCompletions
        closeCompletions.removeAll()
        for done in pending { done() }
    }
    private func finalizeClose(notify: Bool) {
        if !closeFinalized {
            closeFinalized = true
            stopCloseInputs()
        }
        if notify, !closeNotified {
            closeNotified = true
            onClose?()
        }
        // Every terminal path, including a raw-close callback that arrived
        // before a programmatic waiter, resolves all already-joined waiters.
        drainCloseCompletions()
    }
    // Backend teardown preserves the panel fade before unbinding the delegate.
    // Reentry and a concurrent user-close request share the same completion.
    func close(completion: @escaping () -> Void = {}) {
        if closeFinalized { completion(); return }
        closeCompletions.append(completion)
        guard !programmaticCloseRequested else { return }
        programmaticCloseRequested = true
        afterOwnedPanelFade { [self] in
            if !closeFinalized {
                closeFinalized = true
                stopCloseInputs()
                if !windowCloseObserved {
                    window.delegate = nil
                    window.close()
                }
            }
            finalizeClose(notify: false)
        }
    }
    func closeAndWait() async {
        await withCheckedContinuation { continuation in
            close { continuation.resume() }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return false }
        if panelFadeFinished { return !programmaticCloseRequested }
        if !panelFadeStarted {
            afterOwnedPanelFade { [self] in
                guard !programmaticCloseRequested, !closeFinalized else { return }
                window.performClose(nil)
            }
        }
        return false
    }

    // Call after effective display dimensions (pixel aspect and rotation applied) arrive.
    // A new file never repositions a window the user has already placed.
    func open(videoWidth: Double, height: Double) {
        guard videoWidth.isFinite, height.isFinite, videoWidth > 0, height > 0 else { return }
        motion.cancelFrame(); motion.newPlayback(); releaseKeys()
        videoSize = NSSize(width: videoWidth, height: height); aspect = videoSize
        restoreAspect()
        if !placedInitialFrame, !fullscreen, !motion.isPiP, let target = proposedFrame() {
            apply(target); placedInitialFrame = true
        }
        onTransform(motion.transform)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }
    var fullscreen: Bool { window.styleMask.contains(.fullScreen) }
    var pictureInPicture: Bool { motion.isPiP }

    // Explicit fit/rotate/crop actions may resize; delayed metadata must call open, not fit.
    func fit(videoWidth: Double? = nil, height: Double? = nil) {
        if let w = videoWidth, let h = height, w.isFinite, h.isFinite, w > 0, h > 0 {
            videoSize = NSSize(width: w, height: h); aspect = videoSize
        }
        guard !transition, !fullscreen, !motion.isPiP, let target = proposedFrame() else { return }
        motion.animateFrame(from: rect(window.frame), to: rect(target))
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        startTimer()
    }

    // Crop controller supplies each frame on its shared source/window phase.
    // Do not start a second host spring or let aspect locking jump to the endpoint.
    @discardableResult
    func applyCropFrame(_ frame:NSRect,aspect value:Double,finished:Bool)->Bool {
        guard value.isFinite,value>0,frame.width>0,frame.height>0,
              [frame.minX,frame.minY,frame.width,frame.height].allSatisfy({$0.isFinite}) else{return false}
        aspect=NSSize(width:value,height:1)
        guard !transition,!fullscreen,!motion.isPiP else{return true}
        motion.cancelFrame();cropFrameOwned = !finished
        window.contentResizeIncrements=NSSize(width:1,height:1)
        apply(frame)
        if finished {restoreAspect()}
        return true
    }

    func setKeepAspect(_ enabled: Bool) { keepAspect = enabled; restoreAspect() }
    func setFullscreen(_ enabled: Bool) {
        guard !transition, enabled != fullscreen else { return }
        if motion.isPiP { setPiP(false) }
        motion.cancelFrame(); releaseKeys(); restoreAspect()
        transition = true; window.toggleFullScreen(nil)
    }
    func setPiP(_ active: Bool) {
        guard !transition, !fullscreen, active != motion.isPiP else { return }
        motion.cancelFrame(); releaseKeys()
        motion.setPiP(active)
        if active {
            restorePiPFrame = window.frame; restorePiPLevel = window.level
            window.level = .floating
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            if let screen = window.screen ?? NSScreen.main {
                let area = screen.visibleFrame
                let ratio = videoSize.width / videoSize.height
                var w = min(area.width * 0.3, 480.0), h: CGFloat
                h = w / ratio
                if h > area.height * 0.4 { h = area.height * 0.4; w = h * ratio }
                apply(NSRect(x: area.maxX - w - 16, y: area.minY + 16, width: w, height: h))
            }
        } else {
            window.level = restorePiPLevel ?? .normal
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
            if let saved = restorePiPFrame { apply(saved) }
            restorePiPFrame = nil; restorePiPLevel = nil
        }
        restoreAspect(); onTransform(motion.transform)
    }
    func setOnTop(_ active: Bool) {
        if motion.isPiP { restorePiPLevel = active ? .floating : .normal }
        else { window.level = active ? .floating : .normal }
    }
    func move(dx: Double, dy: Double) { motion.nudge(dx: dx, dy: dy); startTimer() }
    func zoom(_ direction: Double) { motion.nudge(dz: direction); startTimer() }
    func resetPicture() { releaseKeys(); motion.reset(); startTimer() }
    // External crop/reset wins over in-flight picture motion.
    func adoptTransform(_ value: GorAVHostTransform) { motion.adopt(value); onTransform(motion.transform) }
    func hold(dx: Double, dy: Double, dz: Double) {
        motion.hold(dx: dx, dy: dy, dz: dz, now: ProcessInfo.processInfo.systemUptime); startTimer()
    }

    private func proposedFrame() -> NSRect? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        let c = window.contentRect(forFrameRect: window.frame)
        let area = rect(screen.visibleFrame)
        guard let result = GorAVHostFit.frame(videoWidth: videoSize.width, videoHeight: videoSize.height,
            usable: area, chromeWidth: window.frame.width - c.width, chromeTop: window.frame.height - c.height) else { return nil }
        return nsrect(result)
    }
    private func rect(_ r: NSRect) -> GorAVHostRect {
        GorAVHostRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
    private func nsrect(_ r: GorAVHostRect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }
    private func apply(_ frame: NSRect) {
        guard !transition, !fullscreen else { return }
        applyingFrame = true
        window.setFrame(frame, display: true, animate: false)
        applyingFrame = false
    }
    private func restoreAspect() {
        if cropFrameOwned {return}
        // Clear aspect locking while the frame spring owns the size. Restore the
        // latest requested lock once settled, cancelled or entering fullscreen.
        if keepAspect && !motion.frameMoving { window.contentAspectRatio = aspect }
        else { window.contentResizeIncrements = NSSize(width: 1, height: 1) }
    }
    private func startTimer() {
        guard timer == nil else { return }
        motion.tick(now: ProcessInfo.processInfo.systemUptime)
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            // Timer is installed only on the main run loop.
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t; RunLoop.main.add(t, forMode: .common)
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() {
        let old = motion.transform
        motion.tick(now: ProcessInfo.processInfo.systemUptime)
        if !transition, !fullscreen, let frame = motion.frame { apply(nsrect(frame)) }
        if motion.transform != old { onTransform(motion.transform) }
        if !motion.frameMoving { motion.cancelFrame(); restoreAspect() }
        if !motion.busy { stopTimer() }
    }
    // The one owner of fn+shift hold while the gorav host is the active engine. InputController calls this same
    // predicate to pass the WHOLE event through (monitor and view fallback), so the two can never disagree.
    // Admission matches the mpv route: shift and fn, no command/option/control; a plain arrow counts only while
    // fn is physically down (arrows always carry .function); Home/End/PageUp/PageDown (115/119/116/121) and the
    // physical comma/period keys (43/47) count by key code.
    nonisolated static func holdKeyAdmitted(keyCode: UInt16, flags: NSEvent.ModifierFlags, physicalFnDown: Bool) -> Bool {
        let mods = flags.intersection([.command, .shift, .option, .control, .function])
        guard mods.contains(.shift), mods.contains(.function),
              !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return false }
        switch keyCode {
        case 43, 47, 115, 119, 116, 121: return true
        case 123, 124, 125, 126: return physicalFnDown
        default: return false
        }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        let keys: Set<UInt16> = [123, 124, 125, 126, 43, 47, 115, 119, 116, 121]
        guard keys.contains(event.keyCode) else { return false }
        if event.type == .keyUp {
            guard heldKeys.remove(event.keyCode) != nil else { return false }
        } else {
            guard Self.holdKeyAdmitted(keyCode: event.keyCode, flags: event.modifierFlags,
                                       physicalFnDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn))
            else { return false }
            heldKeys.insert(event.keyCode)
        }
        // Existing host directions are kept: left/right x, up/down y, period/comma z. The navigation keys share
        // the arrow direction. The rendered direction of y and z is unverified against the mpv route.
        hold(dx: (!heldKeys.isDisjoint(with: [124, 119]) ? 1 : 0) - (!heldKeys.isDisjoint(with: [123, 115]) ? 1 : 0),
             dy: (!heldKeys.isDisjoint(with: [126, 116]) ? 1 : 0) - (!heldKeys.isDisjoint(with: [125, 121]) ? 1 : 0),
             dz: (heldKeys.contains(47) ? 1 : 0) - (heldKeys.contains(43) ? 1 : 0))
        return true
    }
    private func releaseKeys() {
        heldKeys.removeAll(); motion.releaseHold()
        if motion.busy { startTimer() }
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        cropFrameOwned=false;onCropInterruption?()
        placedInitialFrame = true; motion.cancelFrame(); restoreAspect()
    }
    func windowWillMove(_ notification: Notification) {
        if !applyingFrame { cropFrameOwned=false;onCropInterruption?();placedInitialFrame = true; motion.cancelFrame(); restoreAspect() }
    }
    func windowDidResignKey(_ notification: Notification) { releaseKeys() }
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        windowCloseObserved = true
        // Direct NSWindow.close can bypass windowShouldClose. Still finish
        // owned panels before notifying teardown, with one completion only.
        afterOwnedPanelFade { [self] in
            finalizeClose(notify: true)
        }
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        cropFrameOwned=false;onCropInterruption?()
        transition = true; motion.cancelFrame(); releaseKeys(); restoreAspect()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { transition = false }
    func windowWillExitFullScreen(_ notification: Notification) {
        transition = true; motion.cancelFrame(); releaseKeys()
    }
    func windowDidExitFullScreen(_ notification: Notification) { transition = false; restoreAspect() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { transition = false; restoreAspect() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { transition = false; restoreAspect() }
}
#endif
