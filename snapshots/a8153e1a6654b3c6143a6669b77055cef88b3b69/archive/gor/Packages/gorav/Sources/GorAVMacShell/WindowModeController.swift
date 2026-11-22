// G3 (arch-195l, dispatch L6): fullscreen / picture-in-picture on the gorav
// host window. Applies the Linux-tested WindowModeState decisions to AppKit.
// UNCOMPILED on Linux (no AppKit): reviewed source, not measured behavior.
// The policy, transitions and PiP sizing ARE Linux-tested
// (window-mode-tests W1-W21). PiP is a borderless floating always-on-top
// window that takes over the SAME layer-backed content view (one
// CAMetalLayer can live in exactly one window, so the view is reparented,
// never duplicated); PLAN.md P28: gor owns the window and its motion.
#if canImport(AppKit)
import AppKit
import Foundation
import GorAVPlaybackCore

@MainActor
public final class WindowModeController: NSObject {

    public enum ApplyError: Error, Equatable {
        case refused(WindowModeRefusal)
        case noContentView
    }

    private let window: NSWindow
    private let contentView: NSView
    private var state = WindowModeState()
    private var pipWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    /// contentSizeProvider returns the current video frame size in pixels;
    /// asked only when entering PiP.
    private let contentSizeProvider: () -> (width: Double, height: Double)?

    public init(window: NSWindow, contentView: NSView,
                contentSizeProvider: @escaping () -> (width: Double, height: Double)?) {
        self.window = window
        self.contentView = contentView
        self.contentSizeProvider = contentSizeProvider
        super.init()
        let center = NotificationCenter.default
        // Fullscreen can also be entered/exited by the user through the
        // window's own green-button chrome; the notifications keep the
        // state machine honest no matter who initiated the transition.
        observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                            object: window, queue: .main) { [weak self] _ in
            self?.noteExternalFullscreen(entered: true)
        })
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                            object: window, queue: .main) { [weak self] _ in
            self?.noteExternalFullscreen(entered: false)
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    public var currentMode: WindowMode { state.mode }

    /// User-initiated fullscreen through the window chrome bypasses
    /// transition(); reconcile the state machine with what AppKit reports.
    private func noteExternalFullscreen(entered: Bool) {
        if entered, state.mode == .windowed {
            state = WindowModeState(mode: .fullscreen,
                                    windowedRestore: state.windowedRestore ?? Self.frame(of: window))
        } else if !entered, state.mode == .fullscreen {
            let restore = state.windowedRestore
            state = WindowModeState(mode: .windowed, windowedRestore: restore)
            if let restore { applyRestore(restore) }
        }
    }

    private static func frame(of w: NSWindow) -> WindowFrame {
        let f = w.frame
        return WindowFrame(x: Double(f.origin.x), y: Double(f.origin.y),
                           width: Double(f.size.width), height: Double(f.size.height))
    }

    private func applyRestore(_ f: WindowFrame) {
        window.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height),
                        display: true, animate: false)
    }

    @discardableResult
    public func toggleFullscreen() -> Result<WindowMode, ApplyError> {
        let target: WindowMode = state.mode == .fullscreen ? .windowed : .fullscreen
        return enter(target)
    }

    @discardableResult
    public func togglePiP() -> Result<WindowMode, ApplyError> {
        let target: WindowMode = state.mode == .pictureInPicture ? .windowed : .pictureInPicture
        return enter(target)
    }

    @discardableResult
    public func enter(_ target: WindowMode) -> Result<WindowMode, ApplyError> {
        let content = target == .pictureInPicture ? contentSizeProvider() : nil
        let decision = state.transition(to: target,
                                        currentWindowedFrame: Self.frame(of: window),
                                        contentSize: content)
        switch decision {
        case .failure(let r): return .failure(.refused(r))
        case .success(let d):
            switch d {
            case .enterFullscreen:
                window.toggleFullScreen(nil)
            case .exitFullscreen(let restore):
                window.toggleFullScreen(nil)
                if let restore { applyRestore(restore) }
            case .enterPiP(let pip, _):
                enterPiPWindow(size: pip)
            case .exitPiP(let restore):
                exitPiPWindow(restore: restore)
            }
            return .success(state.mode)
        }
    }

    private func enterPiPWindow(size: PipSize) {
        guard contentView.superview != nil else { return }
        let pip = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        pip.isOpaque = false
        pip.backgroundColor = .clear
        pip.level = .floating
        pip.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pip.isReleasedWhenClosed = false
        pip.hasShadow = true
        // Reparent the SAME layer-backed view: one CAMetalLayer, one window.
        contentView.removeFromSuperview()
        contentView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        pip.contentView = contentView
        window.orderOut(nil)
        // Bottom-right of the visible screen with a small margin.
        if let screen = window.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            pip.setFrameOrigin(NSPoint(x: vf.maxX - CGFloat(size.width) - 24,
                                       y: vf.minY + 24))
        }
        pip.makeKeyAndOrderFront(nil)
        pipWindow = pip
    }

    private func exitPiPWindow(restore: WindowFrame?) {
        guard let pip = pipWindow else { return }
        contentView.removeFromSuperview()
        contentView.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        pip.orderOut(nil)
        pipWindow = nil
        if let restore { applyRestore(restore) }
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
