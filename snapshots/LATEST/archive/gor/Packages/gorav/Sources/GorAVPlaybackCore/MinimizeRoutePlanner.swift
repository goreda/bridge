/// PARITY-INPUT slice 1: which minimize chain a minimize request must take.
/// The shared borderless player window (DraggableOverlayWindow) routes every
/// standard minimize action (Window menu, remapped key) to
/// AppDelegate.requestMPVMinimize, whose guard required the mpv AX window.
/// On the gorav engine mpv is retired and no AX window exists, so the request
/// silently did nothing - a silent no-op, which parity forbids (route or
/// loud-refuse). gorav's minimize is the player window itself.
public enum MinimizeRoute {
    /// Legacy chain: exit fullscreen, wait for geometry, AX-minimize the mpv window.
    case mpvWindowChain
    /// gorav engine: miniaturize the player window itself, no mpv chain involved.
    case goravHostWindow
}
public enum MinimizeRoutePlanner {
    /// nil means nothing exists to minimize; only then is the request a genuine no-op.
    public static func route(engineIsGorav:Bool,hasMpvAXWindow:Bool,hasPlayerWindow:Bool)->MinimizeRoute? {
        if engineIsGorav {return hasPlayerWindow ? .goravHostWindow : nil}
        return (hasMpvAXWindow && hasPlayerWindow) ? .mpvWindowChain : nil
    }
}
