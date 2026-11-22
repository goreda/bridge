import Foundation
// Sources/GorAVPlaybackCore/HostTransform.swift
// G3 host pan/zoom: pure math shared by the Metal renderer (per-frame quad) and by hosts that need the
// effective on-screen video rect. No Metal, no AppKit, no I/O. Linux only / Mac NOT_RUN for the GPU side.
//
// Units (fixed here, one definition):
//  - panX, panY: fractions of the drawable (1.0 = one full drawable width/height). +panX moves the image
//    right, +panY moves it up. Pan is applied AFTER zoom, in screen space.
//  - log2Zoom: zoom = 2^log2Zoom about the center of the aspect-fit rect (0 = fit, 1 = 2x). Zoom is a
//    magnification of the aspect-fit rect: it never changes the frame aspect.
//  - Subtitle/overlay composition rides the same quad in the fragment stage, so it moves with the video.

public struct HostTransform: Equatable, Sendable {
    public static let maxAbsPan = 16.0
    public static let maxAbsLog2Zoom = 8.0
    public let panX: Double
    public let panY: Double
    public let log2Zoom: Double
    /// nil when any value is non-finite or out of range (typed refusal at the call site, never clamped).
    public init?(panX: Double, panY: Double, log2Zoom: Double) {
        guard panX.isFinite, panY.isFinite, log2Zoom.isFinite,
              abs(panX) <= Self.maxAbsPan, abs(panY) <= Self.maxAbsPan,
              abs(log2Zoom) <= Self.maxAbsLog2Zoom else { return nil }
        self.panX = panX; self.panY = panY; self.log2Zoom = log2Zoom
    }
    public static let identity = HostTransform(panX: 0, panY: 0, log2Zoom: 0)!
    public var zoom: Double { exp2(log2Zoom) }
}

public enum HostTransformOutcome: Equatable, Sendable {
    case applied
    case refusedInvalid     // non-finite or out of range
    case refusedSealed      // renderer sealed or in a transition
    case refusedNotOpen     // no presenter yet
}

/// Quad vertices, same layout as MetalRenderer.quad: [x, y, u, v] for TL, BL, TR, BR in NDC, uv (0,0)=top-left.
/// `scaleX/scaleY` are the aspect-fit NDC half-extents (AspectFit.scaleX/scaleY).
public func hostTransformQuad(scaleX: Double, scaleY: Double, _ t: HostTransform) -> [Float] {
    let z = t.zoom
    let hx = scaleX * z, hy = scaleY * z
    let cx = 2.0 * t.panX, cy = 2.0 * t.panY      // NDC spans 2 per drawable
    let l = Float(cx - hx), r = Float(cx + hx), top = Float(cy + hy), bot = Float(cy - hy)
    return [l, top, 0, 0,
            l, bot, 0, 1,
            r, top, 1, 0,
            r, bot, 1, 1]
}

/// Rect in drawable pixels, origin top-left, y down.
public struct VideoRect: Equatable, Sendable {
    public let x: Double, y: Double, w: Double, h: Double
}

/// What G3 needs at open and after every transform: the frame as decoded and where it lands.
public struct EffectiveVideoGeometry: Equatable, Sendable {
    public let frameWidth: Int, frameHeight: Int          // presented frame pixels (display size as rendered)
    public let drawableWidth: Int, drawableHeight: Int    // drawable pixels
    public let rect: VideoRect                            // on-screen video rect incl. host transform (may extend past the drawable)
    public init(frameWidth: Int, frameHeight: Int, drawableWidth: Int, drawableHeight: Int, rect: VideoRect) {
        self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.drawableWidth = drawableWidth; self.drawableHeight = drawableHeight; self.rect = rect
    }
}

/// Aspect-fit rect of the frame in the drawable, then zoom about its center, then pan.
public func effectiveVideoRect(drawableW: Int, drawableH: Int, frameW: Int, frameH: Int, _ t: HostTransform) -> VideoRect? {
    guard drawableW > 0, drawableH > 0, frameW > 0, frameH > 0 else { return nil }
    let dw = Double(drawableW), dh = Double(drawableH)
    let s = min(dw / Double(frameW), dh / Double(frameH))
    let w = Double(frameW) * s * t.zoom, h = Double(frameH) * s * t.zoom
    let cx = dw / 2 + t.panX * dw
    let cy = dh / 2 - t.panY * dh
    return VideoRect(x: cx - w / 2, y: cy - h / 2, w: w, h: h)
}

public func effectiveVideoGeometry(drawableW: Int, drawableH: Int, frameW: Int, frameH: Int, _ t: HostTransform) -> EffectiveVideoGeometry? {
    guard let r = effectiveVideoRect(drawableW: drawableW, drawableH: drawableH, frameW: frameW, frameH: frameH, t) else { return nil }
    return EffectiveVideoGeometry(frameWidth: frameW, frameHeight: frameH, drawableWidth: drawableW, drawableHeight: drawableH, rect: r)
}
