// SubtitleLayout.swift - M2 subtitle layout math (block 168). Pure Swift: type-checks
// AND runs on Linux. INDEPENDENT of the architect staleness ruling: placement and
// scaling do not depend on Option A/B, the authority lifecycle, or pull/push (Q3).
//
// Scope honesty: ASS margins/alignment are NOT parsed by the producer (R2) and are
// NEVER invented here. Placement is therefore a DECLARED DEFAULT (bottom-center,
// default margin), stated in receipts, not a parsed attribute. Coordinate space is
// interface question Q5 (open): the space is a PARAMETER with a labeled candidate
// default, not a silent choice.

/// Coordinate space for overlay destination rects (Q5 DECIDED 2026-11-01 02:25 +03,
/// M2-INTERFACE-DECISION-2026-11-01.md: layout output space = drawablePixels; producer
/// metrics interpreted in PlayRes reference frame; seam carries Int frame pixels via
/// AspectFit pull-IN with receipt).
public enum OverlayCoordinateSpace: String, Equatable, Sendable {
    case drawablePixels   // DECIDED layout output space (Q5, M2-INTERFACE-DECISION-2026-11-01)
    case playResScaled    // producer PlayRes reference frame units
}

/// Rect value type (tuples cannot conform to Equatable - caught by the standalone
/// Linux compile of this file).
public struct OverlayRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// Result carries what was defaulted so the receipt can SAY it (R3: "missing PlayRes:
/// renderer uses its default and says so").
public struct LayoutDecision: Equatable, Sendable {
    public let scaledFontSize: Double
    public let usedDefaultPlayRes: Bool
    public let destinationRect: OverlayRect
    public let coordinateSpace: OverlayCoordinateSpace
    public let placementWasDeclaredDefault: Bool
    public init(scaledFontSize: Double, usedDefaultPlayRes: Bool, destinationRect: OverlayRect,
                coordinateSpace: OverlayCoordinateSpace, placementWasDeclaredDefault: Bool) {
        self.scaledFontSize = scaledFontSize
        self.usedDefaultPlayRes = usedDefaultPlayRes
        self.destinationRect = destinationRect
        self.coordinateSpace = coordinateSpace
        self.placementWasDeclaredDefault = placementWasDeclaredDefault
    }
}

public enum SubtitleLayout {
    /// Producer default PlayRes when the track carries none (ASS reference 384x288 is
    /// the historical default; declared here, never silent).
    public static let defaultPlayResX = 384
    public static let defaultPlayResY = 288
    /// Declared default bottom margin as a fraction of drawable height (not a parsed
    /// ASS margin - those are not parsed, R2).
    public static let defaultBottomMarginFraction = 0.05

    /// R3: scale a style font size from the PlayRes reference frame to the drawable.
    /// Missing PlayRes -> default reference frame, flagged in the decision.
    public static func scaleFontSize(_ fontSize: Double,
                                     playResY: Int?,
                                     drawableHeight: Int) -> (size: Double, usedDefault: Bool) {
        let refY = Double(playResY ?? defaultPlayResY)
        let usedDefault = (playResY == nil)
        guard drawableHeight > 0, refY > 0 else { return (fontSize, usedDefault) }
        return (fontSize * Double(drawableHeight) / refY, usedDefault)
    }

    /// Drawable-pixel rect -> FRAME-pixel rect via the renderer's AspectFit mapping
    /// (review P1b: the overlay seam is FRAME pixels - MetalRenderer validates
    /// ox/oy/ow/oh against lease.frameW/H (:843-854) and the shader samples
    /// uv*frameW/H, so drawable-space rects are WRONG for any non-1:1 4K/window
    /// ratio). Clamps INTO the displayed frame (pull-IN, never dropped); nil iff
    /// the fit/frame guard fails or the scaled/clamped width or height fails > 0 (zero incl. -0.0, negative, NaN).
    public static func drawableToFrameRect(_ r: OverlayRect, fit: AspectFit,
                                           frameW: Int, frameH: Int) -> PixelRect? {
        guard fit.pixelRect.w > 0, fit.pixelRect.h > 0, frameW > 0, frameH > 0 else { return nil }
        let sx = Double(frameW) / Double(fit.pixelRect.w)
        let sy = Double(frameH) / Double(fit.pixelRect.h)
        let fx = (r.x - Double(fit.pixelRect.x)) * sx
        let fy = (r.y - Double(fit.pixelRect.y)) * sy
        // Pull INTO the frame: a subtitle rect that lands (fully or partly) in the
        // letterbox border is repositioned to the frame edge, never dropped (adversarial
        // run A5: declared-default bottom placement on 2.4:1 content sits below the
        // frame bottom - refusing it would silently lose every subtitle). Only a
        // degenerate zero-size rect is nil (typed .outsideFrame at the caller).
        let fw = min(r.w * sx, Double(frameW)), fh = min(r.h * sy, Double(frameH))
        guard fw > 0, fh > 0 else { return nil }
        let cx = min(max(0.0, fx), Double(frameW) - fw)
        let cy = min(max(0.0, fy), Double(frameH) - fh)
        return PixelRect(x: Int(cx.rounded(.down)), y: Int(cy.rounded(.down)),
                         w: max(1, Int(fw.rounded(.toNearestOrAwayFromZero))),
                         h: max(1, Int(fh.rounded(.toNearestOrAwayFromZero))))
    }

    /// M2 r2 receipt variant: same conversion, PLUS the typed placement receipt
    /// the pull-IN policy requires - whether the rect was repositioned/clamped
    /// into the frame and the exact pre-clamp proposal. The policy is no longer
    /// silent: a pulled-in overlay is composited AND reported; nothing is
    /// dropped or moved without a receipt the host can audit.
    public static func drawableToFrameRectWithReceipt(_ r: OverlayRect, fit: AspectFit,
                                                      frameW: Int, frameH: Int)
        -> (rect: PixelRect, wasPulledIntoFrame: Bool,
            proposedX: Double, proposedY: Double, proposedW: Double, proposedH: Double)? {
        guard fit.pixelRect.w > 0, fit.pixelRect.h > 0, frameW > 0, frameH > 0 else { return nil }
        let sx = Double(frameW) / Double(fit.pixelRect.w)
        let sy = Double(frameH) / Double(fit.pixelRect.h)
        let fx = (r.x - Double(fit.pixelRect.x)) * sx
        let fy = (r.y - Double(fit.pixelRect.y)) * sy
        let fw = min(r.w * sx, Double(frameW)), fh = min(r.h * sy, Double(frameH))
        guard fw > 0, fh > 0 else { return nil }
        let cx = min(max(0.0, fx), Double(frameW) - fw)
        let cy = min(max(0.0, fy), Double(frameH) - fh)
        let pulled = (cx != fx) || (cy != fy) || (fw != r.w * sx) || (fh != r.h * sy)
        return (PixelRect(x: Int(cx.rounded(.down)), y: Int(cy.rounded(.down)),
                          w: max(1, Int(fw.rounded(.toNearestOrAwayFromZero))),
                          h: max(1, Int(fh.rounded(.toNearestOrAwayFromZero)))),
                pulled, fx, fy, r.w * sx, r.h * sy)
    }

    /// Declared-default placement: bottom-center of the drawable.
    /// textW/textH in the SAME units as drawableW/drawableH when space == .drawablePixels.
    public static func declaredDefaultRect(textW: Double, textH: Double,
                                           drawableW: Double, drawableH: Double,
                                           space: OverlayCoordinateSpace) -> LayoutDecision {
        let x = (drawableW - textW) / 2.0
        let y = drawableH * (1.0 - defaultBottomMarginFraction) - textH
        return LayoutDecision(scaledFontSize: 0, usedDefaultPlayRes: false,
                              destinationRect: OverlayRect(x: x, y: y, w: textW, h: textH),
                              coordinateSpace: space,
                              placementWasDeclaredDefault: true)
    }
}
