// Platform station: complete source units, with only unconditional imports lifted.
import AppKit
import CoreGraphics
import Foundation

// MARK: - OverlaySpaceGate.swift

/// Keeps the gor overlay on the same macOS Space as the mpv window it decorates.
///
/// Root cause of "the overlay stays behind when I move the player to another desktop": the overlay was an
/// ordinary floating window pinned to the Space it was created on (collectionBehavior had no Space flag), and
/// syncOverlay only follows mpv's frame, which is identical on every Space. Nothing ever moved or hid the overlay
/// when mpv left its Space, and it only came back after a click switched Spaces by hand.
///
/// Rule: the overlay lives on exactly ONE Space, mpv's, and is MOVED there when mpv's Space changes. It never joins
/// all Spaces: an earlier version did (`.canJoinAllSpaces`) and then hid itself with a delay, so switching back to the
/// old desktop showed the overlay for a few frames before it vanished (owner report 22:09).
/// mpv on screen on the active Space but the overlay is not -> order the overlay in with `.moveToActiveSpace` set only
/// for that one call (public API, no CGS), at most every `moveInterval` s. mpv off screen for `hideAfterMisses`
/// consecutive samples (~0.4 s at the 0.13 s sync rate, so fullscreen/Mission Control blips do not flicker it) ->
/// overlay ordered out. `.fullScreenAuxiliary` stays for mpv's native fullscreen Space.
/// Re-evaluated by every sync tick and by activeSpaceDidChange.
struct OverlaySpaceGate {
    enum Decision: Equatable { case show, hide, keep }
    static let hideAfterMisses = 3
    static let moveInterval: TimeInterval = 0.5
    private var lastMove: TimeInterval = -1
    private var mpvWindowID: CGWindowID?
    private var mpvIDCheckedAt: TimeInterval = -10
    private var lastSpaceSig = ""
    private(set) var misses = 0
    private(set) var hidden = false
    private var envLogged = false, noMpvLogged = false, stuckLogged = false
    private var divergeSince: TimeInterval?
    private(set) var seenOnScreen = false   // never hide before mpv has been seen on screen once (launch, misdetection)

    /// Pure decision, no AppKit: used by the window code and by Tests/Spaces/overlay_space_model_test.py.
    mutating func decide(onScreen: Bool) -> Decision {
        if onScreen {
            misses = 0; seenOnScreen = true
            if hidden { hidden = false; return .show }
            return .keep
        }
        misses += 1
        if !hidden && seenOnScreen && misses >= Self.hideAfterMisses { hidden = true; return .hide }
        return .keep
    }

    /// Pure: must the overlay be pulled onto the active Space now? (mpv is here, the overlay is not, rate limited)
    mutating func needsMove(onScreen: Bool, overlayOnActiveSpace: Bool, now: TimeInterval) -> Bool {
        guard onScreen, !overlayOnActiveSpace, now - lastMove >= Self.moveInterval else { return false }
        lastMove = now
        return true
    }

    /// Applies the decision to the overlay window. Returns whether the overlay may be shown now.
    mutating func apply(_ win: NSWindow, onScreen: Bool, pid: Int32? = nil) -> Bool {
        if !envLogged { envLogged = true; Self.log("env macOS=\(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: " ", with: "_")) \(Self.symbolReport()) pid=\(pid.map(String.init) ?? "none") overlayWin=\(win.windowNumber) behavior=\(win.collectionBehavior.rawValue) level=\(win.level.rawValue)") }
        followMpvSpace(win, pid: pid)
        let d = decide(onScreen: onScreen)
        if d != .keep { Self.log("gate \(d) onScreen=\(onScreen) active=\(Self.activeSpace().map(String.init) ?? "?") overlay=\(Self.spaces(of: CGWindowID(win.windowNumber))) mpv=\(mpvWindowID.map { Self.spaces(of: $0) } ?? [])") }
        if d == .hide { win.orderOut(nil) }
        else if d == .show || (win.alphaValue > 0 && needsMove(onScreen: onScreen, overlayOnActiveSpace: win.isOnActiveSpace, now: ProcessInfo.processInfo.systemUptime)) {
            win.collectionBehavior.insert(.moveToActiveSpace)   // only for this order-front: joins the Space mpv is on
            win.alphaValue = 1; win.orderFrontRegardless()
            win.collectionBehavior.remove(.moveToActiveSpace)
        }
        return !hidden
    }

    /// Direct follow: when mpv's window and the overlay are on different Spaces (even if mpv's Space is not the active
    /// one), move the overlay to mpv's Space with CGSMoveWindowsToManagedSpace. The overlay is our own window, so this
    /// needs no SIP change. Loaded with dlsym: if a symbol is missing on some macOS the public path above still runs.
    private mutating func followMpvSpace(_ win: NSWindow, pid: Int32?) {
        guard let pid, win.windowNumber > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if mpvWindowID == nil || now - mpvIDCheckedAt > 2 { mpvIDCheckedAt = now; mpvWindowID = Self.largestWindowID(pid: pid) }
        guard let mpvID = mpvWindowID else { if !noMpvLogged { noMpvLogged = true; Self.log("spaces mpvWin=none pid=\(pid)") }; return }
        noMpvLogged = false
        let mine = CGWindowID(win.windowNumber)
        let theirs = Self.spaces(of: mpvID), here = Self.spaces(of: mine)
        let sig = "\(theirs)|\(here)|\(Self.activeSpace() ?? 0)"
        if sig != lastSpaceSig { lastSpaceSig = sig; Self.log("spaces mpvWin=\(mpvID) mpv=\(theirs) overlay=\(here) active=\(Self.activeSpace().map(String.init) ?? "?")") }
        let sameSpace = theirs.contains(where: { here.contains($0) })
        let activeNow: UInt64 = Self.activeSpace() ?? 0
        if !theirs.isEmpty, theirs.contains(activeNow), !sameSpace {   // mpv is on the Space the user is looking at, the overlay is not
            if divergeSince == nil { divergeSince = now }
            if let t0 = divergeSince, now - t0 > 1.5, !stuckLogged { stuckLogged = true; Self.log("STUCK mpv=\(theirs) overlay=\(here) active=\(activeNow) alpha=\(win.alphaValue) visible=\(win.isVisible) onActive=\(win.isOnActiveSpace) for=\(String(format: "%.1f", now - t0))s") }
        } else if let t0 = divergeSince { divergeSince = nil; stuckLogged = false; let dt = String(format: "%.2f", now - t0)
            if sameSpace { Self.log("converged after \(dt)s mpv=\(theirs) overlay=\(here)") }   // overlay really shares mpv's Space
            else { Self.log("diverge ended NOT converged after \(dt)s mpv=\(theirs) overlay=\(here) active=\(activeNow)") } }   // mpv left the active Space or has no Space: nothing proves a follow
        guard let target = theirs.first, !theirs.isEmpty, !here.isEmpty, !sameSpace else { return }
        if Self.moveWindow(mine, to: target) { let after = Self.spaces(of: mine); Self.log("moved overlay \(mine) from \(here) to mpv space \(target) now=\(after) ok=\(after.contains(target))") }
        else { Self.log("move overlay \(mine) to space \(target) NOT done: CGSMoveWindowsToManagedSpace or CGSMainConnectionID unavailable") }
    }

    private typealias MainConn = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias MoveWins = @convention(c) (Int32, CFArray, UInt64) -> Void
    private typealias ActiveSp = @convention(c) (Int32) -> UInt64
    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(p, to: type)
    }
    /// One-time environment line for the log reader: which private symbols resolved on this macOS.
    static func symbolReport() -> String {
        func b(_ ok: Bool) -> Int { ok ? 1 : 0 }
        return "sym_main=\(b(sym("CGSMainConnectionID", MainConn.self) != nil)) sym_copy=\(b(sym("CGSCopySpacesForWindows", CopySpaces.self) != nil)) sym_active=\(b(sym("CGSGetActiveSpace", ActiveSp.self) != nil)) sym_move=\(b(sym("CGSMoveWindowsToManagedSpace", MoveWins.self) != nil))"
    }
    static func spaces(of wid: CGWindowID) -> [UInt64] {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let copy = sym("CGSCopySpacesForWindows", CopySpaces.self),
              let arr = copy(conn(), 7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return arr.map { $0.uint64Value }
    }
    static func activeSpace() -> UInt64? {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let f = sym("CGSGetActiveSpace", ActiveSp.self) else { return nil }
        return f(conn())
    }
    static func moveWindow(_ wid: CGWindowID, to space: UInt64) -> Bool {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let mv = sym("CGSMoveWindowsToManagedSpace", MoveWins.self) else { return false }
        mv(conn(), [NSNumber(value: wid)] as CFArray, space); return true
    }
    /// Largest window of the mpv process, on any Space (optionAll lists off-screen Spaces too).
    static func largestWindowID(pid: Int32) -> CGWindowID? {
        var best: (CGWindowID, Double)?
        for d in CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [] {
            guard let owner = d[kCGWindowOwnerPID as String] as? Int32, owner == pid, let n = d[kCGWindowNumber as String] as? Int,
                  let b = d[kCGWindowBounds as String] as? [String: Any], let w = b["Width"] as? Double, let h = b["Height"] as? Double,
                  w > 50, h > 50, w * h > (best?.1 ?? 0) else { continue }
            best = (CGWindowID(n), w * h)
        }
        return best?.0
    }
    /// State-change lines only (never per tick), 5 MB cap, same shared file as the other numeric diagnostics.
    static func log(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        let data = Data("\(f.string(from: Date())) [spaces] \(text)\n".utf8)
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }

    /// True while a window of the mpv process (any level: mpv.conf has ontop=yes, so it sits at the floating level)
    /// is on screen (so on a visible Space). Unknown pid
    /// counts as on screen, so a missing process never hides the overlay. Safe off the main thread.
    static func mpvOnScreen(pid: Int32?) -> Bool {
        guard let pid else { return true }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in list {
            guard let owner = d[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let b = d[kCGWindowBounds as String] as? [String: Any],
                  let w = b["Width"] as? Double, let h = b["Height"] as? Double, w > 50, h > 50 else { continue }
            return true
        }
        return false
    }

    static func observeSpaceChange(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        // Space switch: re-check at once and again while the window server settles (the on-screen list can lag the
        // notification by a few frames), so the overlay arrives or leaves without waiting for the 0.13 s tick.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            Self.log("activeSpaceDidChange active=\(Self.activeSpace().map(String.init) ?? "?")")
            handler()
            for d in [0.1, 0.25, 0.5] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { handler() } }
        }
    }
}

// Audit notes (macOS Spaces / displays), kept next to the rule they justify:
// - Native fullscreen: mpv gets its own Space; `.fullScreenAuxiliary` lets the overlay sit on it once moved there, and the gate sees mpv
//   on screen there, so the overlay is shown. Leaving fullscreen is the same transition in reverse.
// - Mission Control / Exposé: windows may report off screen for a moment; 3 misses (about 0.4 s) are required before
//   hiding, and a single on-screen sample shows the overlay again.
// - Display change / sleep: the existing screen-parameter observers still own frame math; the gate only decides
//   visibility, so a moved or removed display cannot leave the overlay hidden: the next on-screen sample shows it.
// - Several displays with separate Spaces: CGWindowList on-screen covers every display's active Space, so mpv on a
//   second display keeps the overlay visible there (the overlay is moved onto mpv's Space, on whichever display that is).
// - mpv hidden with Cmd+H or on an inactive Space: the overlay stays ordered out, so no UI floats over other desktops.
// - Panels (GORInputPanel) are not covered by this gate; they open on the active Space when ordered front.
// MARK: - PanelFocus.swift

/// One focus lifecycle for native gor panels. No activation polling or app-wide focus stealing.
/// A panel only claims activation on a click addressed to itself or an explicit open/refocus call.
class GORInputPanel: NSPanel {
    private weak var savedControl:NSView?
    private var savedSelection:NSRange?
    override var canBecomeKey:Bool {!NoActivate.active}
    override var canBecomeMain:Bool {false}
    var hasMarkedText:Bool {(firstResponder as? NSTextView)?.hasMarkedText() == true}
    // Key-window ownership: while this panel is open it owns the key window; automatic
    // player re-keys (activation recovery, overlay click, un-minimize) stand down.
    private func registerKeyOwnership() {PanelKeyOwnership.shared.register(ObjectIdentifier(self))}
    private func releaseKeyOwnership() {PanelKeyOwnership.shared.unregister(ObjectIdentifier(self))}
    override func makeKeyAndOrderFront(_ sender:Any?) {
        registerKeyOwnership()
        super.makeKeyAndOrderFront(sender)
        GORInputPanel.logFocus("open-assert",panel:self)
    }
    override func orderFront(_ sender:Any?) {registerKeyOwnership();super.orderFront(sender)}
    override func close() {releaseKeyOwnership();super.close()}
    override func orderOut(_ sender:Any?) {releaseKeyOwnership();super.orderOut(sender)}
    deinit {PanelKeyOwnership.shared.unregister(ObjectIdentifier(self))}
    /// Focus diagnostic: one line at open/key-gain/key-loss naming the key window and its
    /// first responder, so an owner capture shows who holds key and who took it.
    static func logFocus(_ phase:String,panel:NSWindow?) {
        let key=NSApp.keyWindow
        let keyDesc=key.map {"\(type(of:$0))"} ?? "none"
        let firstDesc=key?.firstResponder.map {"\(type(of:$0))"} ?? "none"
        let panelDesc=panel.map {"\(type(of:$0))"} ?? "none"
        print("[panel-focus] \(phase) panel=\(panelDesc) keyWindow=\(keyDesc) firstResponder=\(firstDesc)")
    }
    func rememberFocus(_ view:NSView) {if view.window === self {savedControl=view;savedSelection=nil}}
    private func firstEditable(in view:NSView)->NSTextField? {
        PanelFocusTraversal.first(in:view,children:{$0.subviews},visible:{!$0.isHidden && $0.alphaValue>0.01},accept:{
            guard let field=$0 as? NSTextField,field.isEditable,field.isEnabled else{return nil};return field
        })
    }
    func restorePanelFocus() {
        guard isVisible,isKeyWindow else{return}
        // Preserve the active field editor/IME and selection. A non-text control keeps focus too.
        if let responder=firstResponder as? NSView,responder !== contentView,
           responder.window === self {
            if responder is NSTextView {return}
            if responder is NSControl && !(responder is NSTextField) {return}
        }
        let target=(savedControl?.window === self ? savedControl:nil) ?? contentView.flatMap {firstEditable(in:$0)}
        guard let target else{return}
        if let field=target as? NSTextField,let editor=field.currentEditor(),firstResponder === editor{return}
        _=makeFirstResponder(target)
        if let field=target as? NSTextField,let editor=field.currentEditor() as? NSTextView,let range=savedSelection {
            let length=(field.stringValue as NSString).length
            editor.setSelectedRange(NSRange(location:min(range.location,length),length:min(range.length,max(0,length-min(range.location,length)))))
        }
    }
    override func resignKey() {
        if let editor=firstResponder as? NSTextView,let field=editor.delegate as? NSTextField {
            savedControl=field;savedSelection=editor.selectedRange()
        }
        else if let view=firstResponder as? NSView,view.window === self,view is NSControl {savedControl=view}
        super.resignKey()
        GORInputPanel.logFocus("resigned-key",panel:self)
        // The new key window is only settled a beat later; log it then to name any stealer.
        DispatchQueue.main.async {GORInputPanel.logFocus("post-loss",panel:nil)}
    }
    override func becomeKey() {registerKeyOwnership();super.becomeKey();restorePanelFocus();GORInputPanel.logFocus("became-key",panel:self)}
    override func sendEvent(_ event:NSEvent) {
        if event.type == .leftMouseDown,attachedSheet == nil,NSApp.modalWindow == nil {
            if !NSApp.isActive && !NoActivate.active {NSApp.activate(ignoringOtherApps:true)}
            if !isKeyWindow {makeKeyAndOrderFront(nil)}
            restorePanelFocus()
        }
        super.sendEvent(event)
    }
    @MainActor private final class PanelFade {
        let panel: NSWindow
        let alpha: CGFloat
        let ignores: Bool
        var completions: [() -> Void] = []
        init(_ panel: NSWindow) {
            self.panel = panel; alpha = panel.alphaValue; ignores = panel.ignoresMouseEvents
        }
    }
    // Main-thread owned. Global quit and session close join the same actual
    // animation rather than capturing an already-faded state a second time.
    private static var panelFades: [ObjectIdentifier: PanelFade] = [:]
    private static func fadePanels(_ panels: [NSWindow], duration: TimeInterval,
                                   completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        var seen = Set<ObjectIdentifier>()
        let unique = panels.filter { seen.insert(ObjectIdentifier($0)).inserted }
        guard !unique.isEmpty else { completion(); return }
        let group = DispatchGroup()
        var fresh: [PanelFade] = []
        for panel in unique {
            let key = ObjectIdentifier(panel)
            group.enter()
            if let fade = panelFades[key] {
                fade.completions.append { group.leave() }
            } else {
                let fade = PanelFade(panel)
                fade.completions.append { group.leave() }
                panelFades[key] = fade; fresh.append(fade)
                panel.ignoresMouseEvents = true
            }
        }
        if !fresh.isEmpty {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                for fade in fresh { fade.panel.animator().alphaValue = 0 }
            }, completionHandler: {
                for fade in fresh.reversed() {
                    fade.panel.orderOut(nil)
                    fade.panel.close()
                    fade.panel.alphaValue = fade.alpha
                    fade.panel.ignoresMouseEvents = fade.ignores
                    panelFades.removeValue(forKey: ObjectIdentifier(fade.panel))
                    for done in fade.completions { done() }
                }
            })
        }
        group.notify(queue: .main, execute: completion)
    }
    /// Preserve the existing global quit collection: visible panels and
    /// their visible child windows, recursively, excluding the overlay.
    static func fadeAllForQuit(excluding overlay: NSWindow?, duration: TimeInterval,
                               completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        var seen = Set<ObjectIdentifier>()
        var windows: [NSWindow] = []
        func collect(_ window: NSWindow) {
            guard window !== overlay, seen.insert(ObjectIdentifier(window)).inserted else { return }
            if window.isVisible { windows.append(window) }
            for child in window.childWindows ?? [] { collect(child) }
        }
        for panel in NSApp.windows.compactMap({ $0 as? NSPanel }) { collect(panel) }
        fadePanels(windows, duration: duration, completion: completion)
    }
    /// A normal player close only owns panels transitively parented to it,
    /// including hidden intermediate panels. NSWindow.parent is the AppKit API.
    static func fadePanelsOwned(by owner: NSWindow, duration: TimeInterval,
                                completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        var owned: [NSPanel] = []
        var frontier = [owner]
        while let parent = frontier.popLast() {
            for panel in NSApp.windows.compactMap({ $0 as? NSPanel })
            where panel.parent === parent && !owned.contains(where: { $0 === panel }) {
                owned.append(panel); frontier.append(panel)
            }
        }
        fadePanels(owned, duration: duration, completion: completion)
    }
    override func cancelOperation(_ sender:Any?) {performClose(sender)}
    override func keyDown(with event:NSEvent) {
        // Existing text delegates and panel monitors retain first refusal. This fallback is for
        // a panel with no editor/control owning Escape, and closes through its ordinary lifecycle.
        if event.keyCode==53 {cancelOperation(nil);return}
        super.keyDown(with:event)
    }
}
// MARK: - PanelFocusTraversal.swift
// Test/background launches may create real windows but must not claim the user's focus.
enum NoActivate {
    static func requested(arguments:[String],environment:[String:String])->Bool {
        arguments.contains("--gor-no-activate") || environment["GOR_NO_ACTIVATE"] == "1"
    }
    static var active:Bool {requested(arguments:ProcessInfo.processInfo.arguments,environment:ProcessInfo.processInfo.environment)}
    private static var startupPending = ProcessInfo.processInfo.arguments.contains("--gor-background-start")
    static var suppressAutomatic:Bool {active || startupPending}
    static func userInteraction() {startupPending=false}
}
// Exact traversal used by native panel focus, independently executable without AppKit.
enum PanelFocusTraversal {
    static func first<Node,Result>(in node:Node,children:(Node)->[Node],visible:(Node)->Bool,accept:(Node)->Result?)->Result? {
        guard visible(node) else{return nil}
        if let found=accept(node){return found}
        for child in children(node) {
            if let found:Result=first(in:child,children:children,visible:visible,accept:accept){return found}
        }
        return nil
    }
}

/// Key-window ownership between gor's single player window and its floating input panels.
/// Invariant: while at least one input panel is open, the panel owns the key window and no
/// automatic gor path (app-activation recovery, mpv-activation recovery, overlay click focus
/// claim, un-minimize) may re-key the player window. The panel re-claims key only through its
/// own open/click path (GORInputPanel). AppKit-free so the rule runs in the Linux harness
/// (Tests/Harness/PanelFocus); the AppKit binding lives in PanelFocus.swift.
/// Main-thread only, like the windows it describes.
final class PanelKeyOwnership {
    static let shared = PanelKeyOwnership()
    /// Tokens of the currently open input panels, in registration order.
    private(set) var openPanels:[ObjectIdentifier] = []
    /// Idempotent: a panel registers on every ordering-in/key claim.
    func register(_ token:ObjectIdentifier) {
        if !openPanels.contains(token) { openPanels.append(token) }
    }
    /// Idempotent: close, order-out and deinit all unregister.
    func unregister(_ token:ObjectIdentifier) {
        openPanels.removeAll { $0 == token }
    }
    var panelOwnsKey:Bool { !openPanels.isEmpty }
    /// The single decision point every automatic player-window re-key must consult.
    func mayKeyPlayerWindow() -> Bool { !NoActivate.suppressAutomatic && !panelOwnsKey }
}
