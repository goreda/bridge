import Foundation

/// Row GORAV-SUBTITLE-TYPOGRAPHY (native80): the ONE user-facing subtitle
/// scale semantic for the embedded cue presenter, mirroring mpv sub-scale
/// (1.0 = 100%). Foundation-only so the decision source compiles and runs
/// off-Mac. Position uses the separate measured bounds helper below; tilt
/// and animation remain outside this surface. Nothing invents ASS override geometry (unsupported override
/// tags keep their typed-refusal route).
public enum SubtitleTypography {
    /// mpv parity: 1.0 is the default scale.
    public static let defaultScale = 1.0
    /// Accepted range. Anything outside (or non-finite) is a typed refusal,
    /// never a silent clamp.
    public static let minScale = 0.1
    public static let maxScale = 10.0

    /// The accepted target for an add/reset adjustment, or nil to refuse.
    /// reset always returns the default; add accumulates on the caller's
    /// session-only current value (same rule as embedded delay state).
    public static func adjustedScale(current: Double, delta: Double, reset: Bool) -> Double? {
        guard current.isFinite, delta.isFinite else { return nil }
        let target = reset ? defaultScale : current + delta
        guard target.isFinite, target >= minScale, target <= maxScale else { return nil }
        return target
    }

    /// Base point size the cue presenter renders at scale 1.0.
    public static let baseCueFontSize = 22.0
    /// Rendered point size for an accepted scale.
    public static func renderedFontSize(scale: Double) -> Double {
        baseCueFontSize * scale
    }
}

// SubtitlePositionBounds (199w row 103 GORAV-SUBTITLE-TYPOGRAPHY, bounded
// vertical placement math) - additive pure translation helper.
//
// SCOPE: given an ALREADY measured subtitle block rectangle, a caller-supplied
// safe rectangle and a requested normalized vertical position, propose a
// translated rectangle or refuse typed. This is never applied-state success:
// the caller's renderer decides what actually lands. No font measurement,
// wrapping, line merging, scale, rotation, tilt, animation, glyph
// rasterization or pixels are generated here; no playhead, cue selection or
// timing changes. This helper introduces NO product default position or
// margin, and adopts none of the historical peer-attributed layout defaults
// recorded as unverified in SubtitlePlan.swift.
//
// COORDINATE CONTRACT (owned by this helper): all rectangles are finite
// Doubles in ONE caller-declared common space, origin at the upper left,
// positive Y downward. The adapter, not this helper, converts AppKit/Metal
// coordinate systems, backing scale, letterbox regions and safe insets; none
// of those are inferred from a viewport size or a source comment.
import Foundation

/// Caller-supplied safe rectangle: nonnegative finite origins, strictly
/// positive finite dimensions, endpoint sums finite and STRICTLY ADVANCING
/// after floating-point addition (a huge origin with sub-ULP dimensions
/// cannot form a misleading empty interval). Reversed rectangles are never
/// silently standardized.
public struct SafeRectangle: Sendable, Equatable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public init?(minX: Double, minY: Double, width: Double, height: Double) {
        guard minX.isFinite, minY.isFinite, width.isFinite, height.isFinite,
              minX >= 0, minY >= 0, width > 0, height > 0 else { return nil }
        let maxX = minX + width
        let maxY = minY + height
        guard maxX.isFinite, maxY.isFinite, maxX > minX, maxY > minY else { return nil }
        self.minX = minX; self.minY = minY; self.width = width; self.height = height
    }
    /// Independently computed endpoints, used by every containment check.
    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
}

/// An already measured subtitle block: finite origin (any sign; a block may
/// currently sit outside the safe rectangle vertically), strictly positive
/// finite dimensions, endpoint sums finite and advancing, exactly like
/// SafeRectangle (a finite origin plus a finite dimension must not overflow
/// to an infinite endpoint).
public struct SubtitleBlockRect: Sendable, Equatable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public init?(minX: Double, minY: Double, width: Double, height: Double) {
        guard minX.isFinite, minY.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        let maxX = minX + width
        let maxY = minY + height
        guard maxX.isFinite, maxY.isFinite, maxX > minX, maxY > minY else { return nil }
        self.minX = minX; self.minY = minY; self.width = width; self.height = height
    }
}

/// A proposed placement: X, width and height preserved BIT-FOR-BIT from the
/// measured block; only Y is computed. The requested position is echoed
/// exactly (including signed zero) so the adapter can separate requested
/// intent from measured/applied geometry.
public struct SubtitlePlacement: Sendable, Equatable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double
    public let requestedPosition: Double
    public var maxY: Double { minY + height }
}

public enum PlacementRefusal: Error, Sendable, Equatable {
    /// p not finite or outside [0,1]. Never clamped.
    case invalidPosition
    case blockTooWide
    case blockTooTall
    /// The block's current horizontal interval is not already inside the
    /// safe interval. Never resized or fixed here.
    case horizontalOutsideSafe
    /// No representable Y contains the unchanged block inside the safe
    /// vertical interval. Containment is never relaxed by an epsilon.
    case unrepresentablePlacement
}

public enum SubtitlePositionBounds {

    /// Bound on the representable-step search when rounding pushes a
    /// candidate outside the safe interval. Exceeding it means no
    /// representable placement was found: typed refusal, never a tolerance
    /// pass.
    static let maxAdjustmentSteps = 1024

    /// Propose the vertical placement of `block` inside `safe` at normalized
    /// position `p` (0 = block top at safe top, 1 = block bottom at safe
    /// bottom, 0.5 = centered in the available travel). Pure and stateless:
    /// refusals change nothing and identical inputs always return identical
    /// results (A -> B -> A equals fresh).
    public static func propose(safe: SafeRectangle, block: SubtitleBlockRect,
                               position p: Double) -> Result<SubtitlePlacement, PlacementRefusal> {
        // -0.0 compares equal to 0.0 and is accepted; it is echoed as-is.
        guard p.isFinite, p >= 0, p <= 1 else { return .failure(.invalidPosition) }
        guard block.width <= safe.width else { return .failure(.blockTooWide) }
        guard block.height <= safe.height else { return .failure(.blockTooTall) }
        // Exact horizontal edges are valid; the block is never resized.
        guard block.minX >= safe.minX, block.minX + block.width <= safe.maxX else {
            return .failure(.horizontalOutsideSafe)
        }

        let travel = safe.height - block.height      // >= 0, finite
        let safeBottom = safe.maxY                    // independently computed
        // Endpoint-specific formulas BEFORE any general expression, so p=0/1
        // anchor exactly at the safe edges rather than at a rounded midpoint
        // of a weighted-endpoint interpolation.
        var y: Double
        if p == 0 {
            y = safe.minY
        } else if p == 1 {
            y = safeBottom - block.height
        } else {
            y = safe.minY + p * travel
        }

        // Final containment with independently computed bottoms. Adjust
        // inward by representable steps only; the block never shrinks.
        var steps = 0
        if y < safe.minY {
            y = safe.minY
        }
        while y + block.height > safeBottom {
            let inward = safeBottom - block.height
            if inward >= safe.minY, inward < y {
                y = inward
            } else if y > safe.minY {
                y = y.nextDown
            } else {
                return .failure(.unrepresentablePlacement)
            }
            steps += 1
            if steps > maxAdjustmentSteps { return .failure(.unrepresentablePlacement) }
        }
        // Re-check BOTH bounds after adjustment; no tolerance comparison.
        guard y >= safe.minY, y + block.height <= safeBottom else {
            return .failure(.unrepresentablePlacement)
        }
        return .success(SubtitlePlacement(minX: block.minX, minY: y,
                                          width: block.width, height: block.height,
                                          requestedPosition: p))
    }
}
