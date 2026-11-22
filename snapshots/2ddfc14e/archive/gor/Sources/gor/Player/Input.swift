import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore

// MARK: - InputController.swift

// ================================================================
//  InputController - mouse and keyboard routing
// ================================================================
final class InputController {
    private var keyMonitor:           Any?
    private var gorHeldMotion:        [UInt16: (Int, Int, Int)] = [:]
    private var gorMotionReleaseMonitor: Any?
    private var gorFocusObservers:    [NSObjectProtocol] = []
    private var brightnessKeyMonitor: Any?
    private var lastMouseMoveTime           = Date()
    private var lastVariationUpdate         = Date()
    private weak var view: NSView?
    private let ipcCommand: (String) -> Void
    private let wakeUI: () -> Void
    private let musicModeActive: () -> Bool
    private let iptvModeActive: () -> Bool
    private let musicHitTest: (CGPoint) -> Bool
    private let iptvHitTest: (CGPoint) -> Bool
    private let isShowingInputPanel: () -> Bool
    private let spineAlpha: () -> CGFloat
    private let updateVariationBroadcaster: (NSPoint) -> Void
    private let notifyBrightnessKeyChanged: () -> Void
    private let volume: () -> Float
    private let setVolume: (Float) -> Void
    private let seekRelative: (Double) -> Void
    private let simulateVolumeHover: () -> Void
    private let toggleRandomSubtitlePosition: () -> Void
    private let moveSubtitleToDefaultPosition: (Int) -> Void
    private let hitTest: (NSPoint) -> NSView?
    private let dismissActiveDropdown: () -> Void
    private let toggleFullScreenIfNotInPanel: () -> Void
    private let inSpineOrSidebar: (NSPoint) -> Bool
    private let moveMpv: (CGFloat, CGFloat) -> Void
    private let resetMpvPositionCache: () -> Void

    init(
        view: NSView,
        ipcCommand: @escaping (String) -> Void,
        wakeUI: @escaping () -> Void,
        musicModeActive: @escaping () -> Bool,
        iptvModeActive: @escaping () -> Bool,
        musicHitTest: @escaping (CGPoint) -> Bool,
        iptvHitTest: @escaping (CGPoint) -> Bool,
        isShowingInputPanel: @escaping () -> Bool,
        spineAlpha: @escaping () -> CGFloat,
        updateVariationBroadcaster: @escaping (NSPoint) -> Void,
        notifyBrightnessKeyChanged: @escaping () -> Void,
        volume: @escaping () -> Float,
        setVolume: @escaping (Float) -> Void,
        seekRelative: @escaping (Double) -> Void,
        simulateVolumeHover: @escaping () -> Void,
        toggleRandomSubtitlePosition: @escaping () -> Void,
        moveSubtitleToDefaultPosition: @escaping (Int) -> Void,
        hitTest: @escaping (NSPoint) -> NSView?,
        dismissActiveDropdown: @escaping () -> Void,
        toggleFullScreenIfNotInPanel: @escaping () -> Void,
        inSpineOrSidebar: @escaping (NSPoint) -> Bool,
        moveMpv: @escaping (CGFloat, CGFloat) -> Void,
        resetMpvPositionCache: @escaping () -> Void
    ) {
        self.view = view
        self.ipcCommand = ipcCommand
        self.wakeUI = wakeUI
        self.musicModeActive = musicModeActive
        self.iptvModeActive = iptvModeActive
        self.musicHitTest = musicHitTest
        self.iptvHitTest = iptvHitTest
        self.isShowingInputPanel = isShowingInputPanel
        self.spineAlpha = spineAlpha
        self.updateVariationBroadcaster = updateVariationBroadcaster
        self.notifyBrightnessKeyChanged = notifyBrightnessKeyChanged
        self.volume = volume
        self.setVolume = setVolume
        self.seekRelative = seekRelative
        self.simulateVolumeHover = simulateVolumeHover
        self.toggleRandomSubtitlePosition = toggleRandomSubtitlePosition
        self.moveSubtitleToDefaultPosition = moveSubtitleToDefaultPosition
        self.hitTest = hitTest
        self.dismissActiveDropdown = dismissActiveDropdown
        self.toggleFullScreenIfNotInPanel = toggleFullScreenIfNotInPanel
        self.inSpineOrSidebar = inSpineOrSidebar
        self.moveMpv = moveMpv
        self.resetMpvPositionCache = resetMpvPositionCache
    }

    var timeSinceLastMouseMove: TimeInterval {
        Date().timeIntervalSince(lastMouseMoveTime)
    }

    // MARK: - Keyboard

    // Explicit owner for fn+shift hold. While the gorav host is the active engine it owns these events, so this
    // controller passes the whole event through untouched: no forward, no consume, no refusal path.
    // The predicate is the host's own, so the two sides cannot disagree.
    private func goravHostOwnsHold(_ e: NSEvent) -> Bool {
        guard (NSApp.delegate as? AppDelegate)?.activePlayerEngine == .gorav else { return false }
        return GorAVHostWindow.holdKeyAdmitted(
            keyCode: e.keyCode, flags: e.modifierFlags,
            physicalFnDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn))
    }

    func startKeyboardMonitor() {
        // Re-arming must not orphan an active local monitor. The newest
        // registration owns each key event; route/reset semantics stay unchanged.
        if let previous = keyMonitor {
            NSEvent.removeMonitor(previous)
            keyMonitor = nil
        }
        startGorMotionReleaseWatch()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, self.view != nil else { return e }
            if self.goravHostOwnsHold(e) { return e }
            if self.musicModeActive() { return e }
            if self.iptvModeActive() { return e }
            if self.isShowingInputPanel() || PanelKeyOwnership.shared.panelOwnsKey || e.window is GORInputPanel { return e }

            if e.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] {
                let clipKeys: [UInt16: String] = [8: "c", 5: "g", 6: "z", 7: "x", 31: "o", 3: "f"]
                if let key = clipKeys[e.keyCode] {
                    self.ipcCommand("{\"command\":[\"keypress\",\"Meta+Alt+\(key)\"]}")
                    return nil
                }
            }

            if let message = self.grainSizeTrimMessage(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.sendGrainSizeTrim(message)
                return nil
            }

            if self.isPhotonAdjustKey(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.forwardKeyToMPV(e)
                return nil
            }

            if self.gorMotionMatches(e) {
                guard self.hasPlayerKeyFocus(e) else { return e }
                self.gorMotionApply(e)
                return nil
            }

            if e.modifierFlags.contains(.command) { return e }

            if self.handleSpecialKeyCommands(event: e) { return nil }
            self.forwardKeyToMPV(e)
            return nil
        }
    }

    func startBrightnessKeyMonitor() {
        brightnessKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] e in
            guard e.subtype.rawValue == 8 else { return e }
            let keyCode = (e.data1 & 0xFFFF0000) >> 16
            if keyCode == 2 || keyCode == 3 {
                self?.notifyBrightnessKeyChanged()
            }
            return e
        }
    }
    private func handlePictureInPictureCornerKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty, hasPlayerKeyFocus(event),
              let direction = PlayerPictureInPicture.direction(
                keyCode: event.keyCode,
                fnHeld: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)),
              let app = NSApp.delegate as? AppDelegate else { return false }
        return app.movePictureInPicture(direction: direction)
    }
    /// Key ownership contract (pass-5 #8): Swift owns arrows
    /// (L/R volume, U/D seek), Shift+digit speeds, Shift+V/H/R/[/],
    /// and Cmd+Opt+C/G/Z/X/O/F (re-emitted to mpv as Meta+Alt+*). Everything
    /// else is forwarded to mpv via mpvKeyName. input.conf must mirror
    /// the Swift-owned set - keep them in sync when editing either side.
    private func handleSpecialKeyCommands(event: NSEvent) -> Bool {
        if handlePictureInPictureCornerKey(event) { return true }
        let flags   = event.modifierFlags
        let keyCode = event.keyCode

        if [123, 124, 125, 126].contains(keyCode) { wakeUI() }

        if keyCode == 123, !flags.contains(.command), !flags.contains(.shift) {
            let newVol = max(0, volume() - 0.05)
            setVolume(newVol)
            simulateVolumeHover()
            return true
        }

        if keyCode == 124, !flags.contains(.command), !flags.contains(.shift) {
            let newVol = min(1, volume() + 0.05)
            setVolume(newVol)
            simulateVolumeHover()
            return true
        }

        if keyCode == 126, !flags.contains(.command), !flags.contains(.shift) {
            seekRelative(60); return true
        }

        if keyCode == 125, !flags.contains(.command), !flags.contains(.shift) {
            seekRelative(-60); return true
        }

        if flags.contains(.shift) {
            if let keyChar = event.charactersIgnoringModifiers?.first,
               keyChar == "0" {
                toggleRandomSubtitlePosition()
                return true
            }
        }

        // 191b B5: the ONE keymap table (ThreeDKeymap.rows) drives both the 3d menu key equivalents and this keyboard path,
        // so they can never diverge. Exact modifier equality; keyCode pins the physical bracket keys (ANSI 30=']', 33='[')
        // because Shift/Option change the typed glyph. Anything not in the table falls through to mpv exactly as before.
        // Cross-eye stays Ctrl+Shift+X (Shift+X/Option+X are photon sharpen, non-3D); subtitle depth moved to Ctrl+Shift+[/]
        // because B4 claims Option+Shift+[/] for VR180 screen size. See ThreeDKeymap.moves for the full audit.
        if let act = ThreeDKeymap.match(charactersIgnoringModifiers: event.charactersIgnoringModifiers, keyCode: Int(keyCode),
                                        shift: flags.contains(.shift), option: flags.contains(.option),
                                        control: flags.contains(.control), command: flags.contains(.command)) {
            if !event.isARepeat { MainActor.assumeIsolated {ThreeDMenu.dispatch(act)} }
            return true
        }

        if flags.contains(.shift) {
            guard let keyChar = event.charactersIgnoringModifiers?.first,
                  let number  = Int(String(keyChar)),
                  (1...9).contains(number) else { return false }
            moveSubtitleToDefaultPosition(number)
            return true
        }

        return false
    }

    // Size trim is separate from amount/strength; plain b keeps its existing binding.
    private func grainSizeTrimMessage(_ event: NSEvent) -> String? {
        guard event.charactersIgnoringModifiers?.lowercased() == "b" else { return nil }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == [.shift] { return "photon-grain-size-trim-up" }
        if flags == [.command] { return "photon-grain-size-trim-down" }
        if flags == [.command, .shift] { return "photon-grain-size-trim-reset" }
        return nil
    }
    private func sendGrainSizeTrim(_ message: String) {
        ipcCommand("{\"command\":[\"script-message-to\",\"photon_grain\",\"\(message)\"]}")
    }

    // Grain "strength" shortcuts adjust amount offset; sharp adjusts its factor;
    // Cmd/Shift+B trims grain size; Cmd+Shift+B resets trim.
    // Accept only exact Shift or Command modifiers, ignoring Caps Lock.
    private func isPhotonAdjustKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.command] || flags == [.shift],
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return key == "g" || key == "x"
    }

    // gor motion keys. The easing lives in gor-fit.lua. A held key is sent as "hold dx dy dz" on every key-down and key
    // repeat; "hold 0 0 0" goes out on key-up, when shift/fn is let go, or when the app/window loses focus. The lua only
    // follows the held direction (speed eases in and out), so nothing is queued and nothing runs on after release.
    //   fn+shift+arrows  move the picture. Matched by the keyCodes a Mac keyboard reports for fn+arrow (Home 115, End 119,
    //                    Page Up 116, Page Down 121). Plain arrows (123-126) are NOT matched, so shift+arrow is untouched.
    //   fn+shift+, / .   zoom in / zoom out. Matched by PHYSICAL keyCode (43 = the ANSI comma key, 47 = the ANSI period key)
    //                    or by the typed character; both need fn+shift held.
    //   plain = and -    the zoom keys the menu already declares (single steps).
    // Platform facts used: NSEvent.ModifierFlags.function is set for any function key (F-keys, Home/End/Page Up/Down and the
    // arrows) and, per developer reports, while fn is held. Because it is set for the navigation keys themselves it cannot
    // tell fn+arrow from a real Home/End key; the keyCode is what narrows it. None of this has run on a Mac.
    // Plain arrows (123 left, 124 right, 125 down, 126 up) are accepted ONLY while the fn key is physically down according
    // to the session's modifier state (CGEventSource.flagsState / .maskSecondaryFn, the documented "Fn key is down" flag).
    // The event's own .function flag cannot tell them apart (arrows always carry it), so without a held fn plain shift+arrow
    // is untouched. This is an extra route for keyboards that deliver fn+arrow as an arrow instead of Home/End/Page keys.
    // Unverified on a Mac. Unmatched shift+fn keys are logged (first 25 only) so a real build shows the codes it receives.
    private var gorKeyLogCount = 0
    private func gorMotionVector(_ event: NSEvent) -> (Int, Int, Int)? {
        // Single owner: while the gorav host is the active engine its own key monitor owns fn+shift hold;
        // this mpv route must not also dispatch it.
        if (NSApp.delegate as? AppDelegate)?.activePlayerEngine == .gorav { return nil }
        let v = gorMotionVectorCore(event)
        if v == nil, gorKeyLogCount < 25, event.type == .keyDown,
           event.modifierFlags.contains(.shift), event.modifierFlags.contains(.function),
           !event.modifierFlags.contains(.command) {
            gorKeyLogCount += 1
            print("[gor-motion] unmatched shift+fn key: keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") flags=\(event.modifierFlags.rawValue)")
        }
        return v
    }
    private func gorMotionVectorCore(_ event: NSEvent) -> (Int, Int, Int)? {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        guard mods.contains(.shift), mods.contains(.function),
              !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return nil }
        switch event.keyCode {
        case 115: return (-1, 0, 0)
        case 119: return (1, 0, 0)
        case 116: return (0, -1, 0)
        case 121: return (0, 1, 0)
        case 43:  return (0, 0, 1)
        case 47:  return (0, 0, -1)
        case 123, 124, 125, 126:
            guard CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) else { return nil }
            switch event.keyCode {
            case 123: return (-1, 0, 0)
            case 124: return (1, 0, 0)
            case 126: return (0, -1, 0)
            default:  return (0, 1, 0)
            }
        default: break
        }
        switch event.charactersIgnoringModifiers ?? "" {
        case ",", "<": return (0, 0, 1)
        case ".", ">": return (0, 0, -1)
        default: return nil
        }
    }
    private func gorMotionStep(_ event: NSEvent) -> String? {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty else { return nil }
        switch event.charactersIgnoringModifiers ?? "" {
        case "=": return LookToolsRoute.motionJSON(kind:"step",z:1,projection:(view as? PPController)?.vrModeEnabled == true)
        case "-": return LookToolsRoute.motionJSON(kind:"step",z:-1,projection:(view as? PPController)?.vrModeEnabled == true)
        default: return nil
        }
    }
    private func gorMotionMatches(_ event: NSEvent) -> Bool {
        return gorMotionVector(event) != nil || gorMotionStep(event) != nil
    }
    private func gorMotionApply(_ event: NSEvent) {
        if let v = gorMotionVector(event) {
            gorHeldMotion[event.keyCode] = v
            gorSendHold()
        } else if let step = gorMotionStep(event) {
            ipcCommand(step)
        }
    }
    private func gorSendHold() {
        var x = 0, y = 0, z = 0
        for v in gorHeldMotion.values { x += v.0; y += v.1; z += v.2 }
        x = max(-1, min(1, x)); y = max(-1, min(1, y)); z = max(-1, min(1, z))
        ipcCommand(LookToolsRoute.motionJSON(kind:"hold",x:x,y:y,z:z,projection:(view as? PPController)?.vrModeEnabled == true))
    }
    private func gorReleaseAllMotion() {
        guard !gorHeldMotion.isEmpty else { return }
        gorHeldMotion.removeAll()
        gorSendHold()
    }

    // Key-up, shift/fn released, and focus loss all end a held move/zoom. (gor-fit.lua also stops by itself 0.6 s after the
    // last refresh if a key-up is ever lost.)
    private func startGorMotionReleaseWatch() {
        if let old = gorMotionReleaseMonitor { NSEvent.removeMonitor(old) }
        gorMotionReleaseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] e in
            guard let self = self, !self.gorHeldMotion.isEmpty else { return e }
            if e.type == .keyUp {
                if self.gorHeldMotion.removeValue(forKey: e.keyCode) != nil { self.gorSendHold() }
                else if !e.modifierFlags.contains(.shift) { self.gorReleaseAllMotion() }
            } else if !e.modifierFlags.contains(.shift) || !e.modifierFlags.contains(.function) {
                self.gorReleaseAllMotion()
            }
            return e
        }
        if gorFocusObservers.isEmpty {
            let c = NotificationCenter.default
            for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification] {
                gorFocusObservers.append(c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.gorReleaseAllMotion()
                })
            }
        }
    }
    private func hasPlayerKeyFocus(_ event: NSEvent) -> Bool {
        guard !musicModeActive(), !iptvModeActive(), !isShowingInputPanel(),
              let player = view as? PPController,
              let window = player.window,
              window.isKeyWindow, NSApp.keyWindow === window,
              event.window === window,
              let responder = window.firstResponder else { return false }
        // Positive identity guard rejects every text field, field editor and
        // editable control, including future/custom ones, without a panel list.
        guard !(responder is NSText), !(responder is NSTextView),
              !(responder is NSControl) else { return false }
        return responder === player
    }

    private func forwardKeyToMPV(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == " " &&
            flags.intersection([.command, .control, .option, .shift]).isEmpty {
            ipcCommand(#"{"command":["cycle","pause"]}"#)
            return
        }
        let mpvKey = mpvKeyName(event)
        guard !mpvKey.isEmpty else { return }
        let escaped = mpvKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        ipcCommand("{\"command\":[\"keypress\",\"\(escaped)\"]}")
    }

    private func mpvKeyName(_ event: NSEvent) -> String {
        let mods  = event.modifierFlags
        var parts = [String]()
        // Never turn arbitrary Command events into mpv keys.
        if mods.contains(.command) {
            guard isPhotonAdjustKey(event), hasPlayerKeyFocus(event) else { return "" }
            parts.append("Meta")
        }
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.option)  { parts.append("Alt")  }
        if mods.contains(.shift)   { parts.append("Shift") }

        let specialKeys: [UInt16: String] = [
            36: "ENTER",  48: "TAB",       51: "BS",          53: "ESC",
            63: "PLAYPAUSE",
            71: "KP0",    75: "KP_DEC",    76: "KP_ENTER",
            78: "KP_SUBTRACT",             81: "KP_EQUAL",    82: "KP0",
            96: "F5",     97: "F6",        98: "F7",          99: "F3",
           100: "F8",    101: "F9",       103: "F11",
           109: "F10",   111: "F12",      118: "F4",
           120: "F2",    122: "F1",       123: "LEFT",       124: "RIGHT",
           125: "DOWN",  126: "UP",
        ]

        if let special = specialKeys[event.keyCode] {
            parts.append(special)
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let c = chars.lowercased()
            switch c {
            case " ":           parts.append("SPACE")
            case "\t":          parts.append("TAB")
            case "\r", "\n":    parts.append("ENTER")
            case "\u{1b}":      parts.append("ESC")
            default:            parts.append(c)
            }
        } else {
            return ""
        }
        return parts.joined(separator: "+")
    }

    @discardableResult
    func handleViewKeyDown(_ event: NSEvent) -> Bool {
        if goravHostOwnsHold(event) { return false }
        if let message = grainSizeTrimMessage(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            sendGrainSizeTrim(message)
            return true
        }
        if isPhotonAdjustKey(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            forwardKeyToMPV(event)
            return true
        }
        if gorMotionMatches(event) {
            guard hasPlayerKeyFocus(event) else { return false }
            gorMotionApply(event)
            return true
        }
        // Command events not consumed by the local monitor belong to AppKit.
        if event.modifierFlags.contains(.command) { return false }
        if !handleSpecialKeyCommands(event: event) { forwardKeyToMPV(event) }
        return true
    }

    // MARK: - Mouse

    @discardableResult
    func handleMouseDown(with event: NSEvent) -> Bool {
        let loc     = event.locationInWindow
        let hit = hitTest(loc)

        var current: NSView? = hit
        while current != nil {
            if let dropRow  = current as? DropRow  {
                dropRow.mouseDown(with: event); return true
            }
            if let dropList = current as? DropdownList {
                dropList.dismiss(); return true
            }
            current = current?.superview
        }

        dismissActiveDropdown()

        if event.clickCount == 2 {
            guard let view = view else { return false }
            let convertedLoc = view.convert(loc, from: nil)
            let inMusic = musicHitTest(convertedLoc)
            let inIptv  = iptvHitTest(convertedLoc)
            if !inMusic, !inIptv { toggleFullScreenIfNotInPanel() }
        }
        return false
    }

    func handleMouseDragged(with event: NSEvent) {
        guard event.type == .leftMouseDragged, let view = view else { return }
        let loc       = view.convert(event.locationInWindow, from: nil)
        let inMusic   = musicHitTest(loc)
        let inIptv    = iptvHitTest(loc)
        if !inMusic, !inIptv, !inSpineOrSidebar(loc) {
            moveMpv(event.deltaX, event.deltaY)
        }
    }

    func handleMouseUp(with event: NSEvent) {
        resetMpvPositionCache()
    }

    func handleMouseEntered(with event: NSEvent) {
        lastMouseMoveTime = Date()
    }

    func handleMouseExited(with event: NSEvent) {
        lastMouseMoveTime = Date()
    }

    func handleMouseMoved(with event: NSEvent) {
        lastMouseMoveTime = Date()

        let throttle: TimeInterval = spineAlpha() > 0.5 ? 0.5 : 0.2

        let now = Date()
        if now.timeIntervalSince(lastVariationUpdate) > throttle {
            lastVariationUpdate = now
            updateVariationBroadcaster(event.locationInWindow)
        }
    }
}

// MARK: - DragDropHandler.swift

// MARK: - DragDropHandler
// ================================================================
//  DragDropHandler - file drag routing
// ================================================================
// I11 / TRAP-04: match PPController.openMediaFile() routing for fonts, subtitles and media.
// Coupled: PPController.openMediaFile() (PPController.swift); edit both drag paths together.
final class DragDropHandler {
    private var lastDraggedURLs:      [URL]    = []
    private var dragInProgress                 = false
    private var dragStartLocation:    NSPoint  = .zero
    private var lastDragChangeCount:  Int      = 0
    private weak var window: NSWindow?
    private let stopTorrent: () -> Void
    private let streamTorrent: (String) -> Void
    private let openMediaFile: (String) -> Void
    private let photonEnabled: () -> Bool
    private let ipcCommand: (String) -> Void
    private let batchIPC: (String) -> Void
    init(
        window: NSWindow?,
        stopTorrent: @escaping () -> Void,
        streamTorrent: @escaping (String) -> Void,
        openMediaFile: @escaping (String) -> Void,
        photonEnabled: @escaping () -> Bool,
        ipcCommand: @escaping (String) -> Void,
        batchIPC: @escaping (String) -> Void
    ) {
        self.window = window
        self.stopTorrent = stopTorrent
        self.streamTorrent = streamTorrent
        self.openMediaFile = openMediaFile
        self.photonEnabled = photonEnabled
        self.ipcCommand = ipcCommand
        self.batchIPC = batchIPC
    }
    func start() {
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.dragStartLocation  = NSEvent.mouseLocation
            self?.dragInProgress     = false
            self?.lastDragChangeCount = NSPasteboard(name: .drag).changeCount
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }
            let cur = NSEvent.mouseLocation
            let dx  = cur.x - self.dragStartLocation.x
            let dy  = cur.y - self.dragStartLocation.y
            if sqrt(dx*dx + dy*dy) > 10 { self.dragInProgress = true }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            defer { self.dragInProgress = false }
            guard self.dragInProgress else { return }
            let currentChangeCount = NSPasteboard(name: .drag).changeCount
            guard currentChangeCount != self.lastDragChangeCount else { return }
            guard let win = self.window else { return }
            guard win.isVisible, win.isOnActiveSpace else { return }
            guard win.frame.contains(NSEvent.mouseLocation) else { return }
            let pb = NSPasteboard(name: .drag)
            guard let items = pb.pasteboardItems, !items.isEmpty else { return }
            let urls = items.compactMap { item -> URL? in
                guard let str = item.string(forType: .fileURL) else { return nil }
                return URL(string: str)
            }
            guard !urls.isEmpty else { return }
            guard urls != self.lastDraggedURLs else { return }
            self.lastDraggedURLs = urls
            var isFirst = true
            var hasNonFont = false
            for url in urls {
                let fontExts: Set<String> = ["ttf","otf","woff","woff2"]
                if !fontExts.contains(url.pathExtension.lowercased()) { hasNonFont = true; break }
            }
            if hasNonFont { self.stopTorrent() }
            for url in urls {
                let fontExts: Set<String> = ["ttf","otf","woff","woff2"]
                if fontExts.contains(url.pathExtension.lowercased()) {
                    _ = PhotonFont.loadFromURL(url)
                    if PhotonFont.needsAxisMapping {
                        PhotonFont.presentAxisMapping()
                    }
                    continue
                }
                let subExts: Set<String> = ["srt","ass","ssa","vtt","sub"]
                if subExts.contains(url.pathExtension.lowercased()) {
                    self.ipcCommand(MPVCommand.make(["sub-add", url.path]))
                    continue
                }
                if url.pathExtension.lowercased() == "torrent" {
                    self.streamTorrent(url.path)
                    continue
                }
                let imageExts: Set<String> = [
                    "jpg","jpeg","png","gif","bmp","webp",
                    "tiff","tif","ico","heic","heif","avif"
                ]
                if imageExts.contains(url.pathExtension.lowercased()) {
                    self.openMediaFile(url.path)
                    continue
                }
                let mode = isFirst ? "replace" : "append-play"
                if mode == "replace" {
                    self.openMediaFile(url.path)
                } else {
                    self.ipcCommand(MPVCommand.make(["loadfile", url.path, mode]))
                }
                isFirst = false
            }
        }
    }
}
