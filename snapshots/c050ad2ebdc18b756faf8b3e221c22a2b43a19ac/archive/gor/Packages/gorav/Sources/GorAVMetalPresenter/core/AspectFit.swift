// L2 presenter (block 78d): aspect-fit viewport math. Pure Swift, no AppKit
// or Metal, so it is verifiable off-Mac against an independent oracle.
// AUTHORED NEW 2026-10-25, L2 lane.
import Foundation

/// Letterbox fit of a frame into a drawable, preserving aspect.
/// The v1.4 CGImage sink used CALayer default contentsGravity (.resize),
/// which DISTORTS aspect on any non-matching window size (the v1.4 window
/// is 640x480 while the fixture is 640x360). The Metal presenter letterboxes
/// instead; the change is deliberate and measured by the check executable.
/// Typed pixel rect (review point 6: a tuple member cannot synthesize
/// Equatable; this type can).
public struct PixelRect: Equatable, Sendable {
    public let x: Int, y: Int, w: Int, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public struct AspectFit: Equatable, Sendable {
    /// NDC half-extents of the fitted quad (1.0 = full drawable).
    public let scaleX: Double
    public let scaleY: Double
    /// Pixel rect of the fitted image inside the drawable, in readback row
    /// space (row 0 = first row returned by MetalRenderer.readbackNative);
    /// everything outside is letterbox black. Letterbox checks are symmetric,
    /// so the choice of vertical origin does not affect the verdict.
    public let pixelRect: PixelRect

    public static func fit(drawableW: Int, drawableH: Int, frameW: Int, frameH: Int) -> AspectFit {
        precondition(drawableW > 0 && drawableH > 0 && frameW > 0 && frameH > 0)
        let s = min(Double(drawableW) / Double(frameW), Double(drawableH) / Double(frameH))
        let fitW = Double(frameW) * s
        let fitH = Double(frameH) * s
        let x = (Double(drawableW) - fitW) / 2
        let y = (Double(drawableH) - fitH) / 2
        return AspectFit(scaleX: fitW / Double(drawableW),
                         scaleY: fitH / Double(drawableH),
                         pixelRect: PixelRect(x: Int(x.rounded()), y: Int(y.rounded()),
                                              w: Int(fitW.rounded()), h: Int(fitH.rounded())))
    }

    /// True when the drawable pixel belongs to the letterbox border.
    public static func isLetterbox(px: Int, py: Int, fit: AspectFit) -> Bool {
        px < fit.pixelRect.x || py < fit.pixelRect.y ||
        px >= fit.pixelRect.x + fit.pixelRect.w || py >= fit.pixelRect.y + fit.pixelRect.h
    }
}
