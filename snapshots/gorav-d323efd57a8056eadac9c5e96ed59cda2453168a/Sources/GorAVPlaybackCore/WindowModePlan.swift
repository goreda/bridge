// R8/G3 lane note: this file is the G3 (arch-195l, dispatch L6) pure-Swift
// core. "G3 fullscreen/pip on gorav": the gorav host window owns its own
// mode transitions (PLAN.md P28: gor owns the window and its motion; PLAN.md
// line 51: window fit spring, fullscreen, pip, ontop -> G3). This type is
// platform-free and Linux-tested; the AppKit application of a decision lives
// in GorAVMacShell.WindowModeController (Darwin-only).

/// Host window frame in screen points. Platform-free twin of CGRect so the
/// policy compiles and tests on Linux.
public struct WindowFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The three modes the gorav host window supports in the 195l scope.
/// ontop stays outside this item (listed under G3 window in PLAN line 51 but
/// not in the L6 dispatch text "fullscreen/pip").
public enum WindowMode: String, Equatable, Sendable, CaseIterable {
    case windowed
    case fullscreen
    case pictureInPicture
}

public enum WindowModeRefusal: Error, Equatable, Sendable {
    /// Already in the requested mode; the transition is a no-op, not an
    /// error of intent, but it is reported, never silently swallowed.
    case alreadyInMode(WindowMode)
    /// fullscreen <-> pictureInPicture is refused directly: exiting
    /// fullscreen animates and re-anchors the window, so a direct hop would
    /// move pixels the caller did not ask for. Exit to .windowed first.
    case requiresWindowedFirst(from: WindowMode, to: WindowMode)
    /// A restore was requested with no recorded windowed frame.
    case noRestoreFrame
    /// PiP sizing got a degenerate or non-finite content size or invalid
    /// bounds; no size is guessed.
    case degenerateContentSize
}

public enum WindowModeDecision: Equatable, Sendable {
    /// Enter fullscreen. The windowed frame must be captured by the caller
    /// before applying (AppKit re-anchors the window on enter).
    case enterFullscreen(saveRestore: WindowFrame)
    /// Leave fullscreen back to the recorded windowed frame.
    case exitFullscreen(restore: WindowFrame?)
    /// Enter PiP: the content view moves into a borderless floating
    /// always-on-top window of this size; the windowed frame is kept for
    /// exit. PiP windows are never resizable by the user in this item.
    case enterPiP(pipFrameSize: PipSize, saveRestore: WindowFrame)
    /// Leave PiP: the content view moves back into the main window, restored
    /// to the recorded frame.
    case exitPiP(restore: WindowFrame?)
}

/// Aspect-preserving PiP window size. The PiP window fits the video aspect
/// inside a bounded box; it never letterboxes inside the PiP window itself
/// (the presenter letterboxes inside the view as it already does).
public struct PipSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Default bounds for the PiP window: at most 480x270 (a quarter of a
    /// 1920x1080 frame). Portrait content gets a narrow window; there is no
    /// minimum-width bump, because any bump either overflows the box or is
    /// unreachable under max-bounds scaling - narrow is honest, guessed is
    /// not.
    public static let defaultMaxWidth = 480.0
    public static let defaultMaxHeight = 270.0

    /// Aspect-preserving fit of a content size inside the max box.
    /// Degenerate or non-finite content sizes or bounds are a typed refusal,
    /// never a guessed size. Extreme finite inputs that overflow the fit
    /// ratio or round a dimension to zero are degenerate too.
    public static func fit(contentWidth: Double, contentHeight: Double,
                           maxWidth: Double = defaultMaxWidth,
                           maxHeight: Double = defaultMaxHeight) -> Result<PipSize, WindowModeRefusal> {
        guard contentWidth.isFinite, contentHeight.isFinite,
              contentWidth > 0, contentHeight > 0,
              maxWidth.isFinite, maxHeight.isFinite,
              maxWidth > 0, maxHeight > 0 else {
            return .failure(.degenerateContentSize)
        }
        let scale = min(maxWidth / contentWidth, maxHeight / contentHeight)
        let w = contentWidth * scale
        let h = contentHeight * scale
        // Extreme finite inputs can overflow the ratio to infinity; a
        // non-finite fit is degenerate, never a size.
        guard w.isFinite, h.isFinite else { return .failure(.degenerateContentSize) }
        let rw = (w * 1000).rounded() / 1000
        let rh = (h * 1000).rounded() / 1000
        // A very narrow aspect can round a dimension to zero, and a huge
        // finite bound can overflow the rounding multiply to a non-finite
        // dimension; both are degenerate. No minimum-width bump (see above).
        guard rw.isFinite, rh.isFinite, rw > 0, rh > 0 else { return .failure(.degenerateContentSize) }
        return .success(PipSize(width: rw, height: rh))
    }
}

/// Window-mode state machine. Value type: the shell holds one per host
/// window and applies the returned decision to AppKit.
public struct WindowModeState: Equatable, Sendable {
    public private(set) var mode: WindowMode
    /// The windowed frame captured on the last exit from .windowed; restored
    /// when returning to .windowed. nil until the first transition away.
    public private(set) var windowedRestore: WindowFrame?

    public init(mode: WindowMode = .windowed, windowedRestore: WindowFrame? = nil) {
        self.mode = mode
        self.windowedRestore = windowedRestore
    }

    /// Request a transition. currentWindowedFrame is the window's frame NOW,
    /// required when leaving .windowed so it can be restored later; content
    /// size is required when entering PiP. The state only advances on
    /// success; a refusal leaves it untouched.
    public mutating func transition(to target: WindowMode,
                                    currentWindowedFrame: WindowFrame?,
                                    contentSize: (width: Double, height: Double)? = nil
    ) -> Result<WindowModeDecision, WindowModeRefusal> {
        if target == mode { return .failure(.alreadyInMode(mode)) }
        // Direct fullscreen <-> PiP hops are refused (documented choice).
        if (mode == .fullscreen && target == .pictureInPicture) ||
           (mode == .pictureInPicture && target == .fullscreen) {
            return .failure(.requiresWindowedFirst(from: mode, to: target))
        }
        switch target {
        case .fullscreen:
            guard mode == .windowed else {
                return .failure(.requiresWindowedFirst(from: mode, to: target))
            }
            guard let frame = currentWindowedFrame else { return .failure(.noRestoreFrame) }
            mode = .fullscreen
            windowedRestore = frame
            return .success(.enterFullscreen(saveRestore: frame))
        case .pictureInPicture:
            guard mode == .windowed else {
                return .failure(.requiresWindowedFirst(from: mode, to: target))
            }
            guard let frame = currentWindowedFrame else { return .failure(.noRestoreFrame) }
            guard let size = contentSize else { return .failure(.noRestoreFrame) }
            let fit = PipSize.fit(contentWidth: size.width, contentHeight: size.height)
            switch fit {
            case .failure(let r): return .failure(r)
            case .success(let pip):
                mode = .pictureInPicture
                windowedRestore = frame
                return .success(.enterPiP(pipFrameSize: pip, saveRestore: frame))
            }
        case .windowed:
            let previous = mode
            mode = .windowed
            let restore = windowedRestore
            switch previous {
            case .fullscreen: return .success(.exitFullscreen(restore: restore))
            case .pictureInPicture: return .success(.exitPiP(restore: restore))
            case .windowed: return .failure(.alreadyInMode(.windowed))  // unreachable
            }
        }
    }
}
