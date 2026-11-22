import Foundation
import GorAVNativeProbeKit

// R8 (arch-195b): crop stage. Turns the ControlBus NormalizedRect crop state
// into concrete pixel geometry on a decoded frame, and defines the crop
// DETECTION seam (stub detector now; N10 letterbox/pillarbox analysis fills
// it later). The render side (sampling the cropped region) is presenter work.

public struct CropGeometry: Equatable, Sendable {
    /// Pixel-space source rectangle inside the decoded frame.
    public let x: Int, y: Int, width: Int, height: Int
    /// Aspect of the cropped region (width/height), always > 0.
    public let aspect: Double
    public init(x: Int, y: Int, width: Int, height: Int, aspect: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.aspect = aspect
    }
}

public enum CropStageError: Error, Equatable, Sendable, CustomStringConvertible {
    case frameTooSmall
    /// Resolved pixel rectangle is empty.
    case belowMinimum
    public var description: String {
        switch self {
        case .frameTooSmall: return "frameTooSmall"
        case .belowMinimum: return "belowMinimum"
        }
    }
}

public enum CropStage {
    public static let minimumEdgePx = 1

    /// Resolve a validated NormalizedRect against a frame. Rounding is
    /// deterministic: origin floors, extents ceil, then clamp to the frame.
    /// The result always lies fully inside the frame.
    public static func resolve(_ rect: NormalizedRect,
                               frameWidth: Int, frameHeight: Int)
        -> Result<CropGeometry, CropStageError> {
        guard frameWidth >= minimumEdgePx, frameHeight >= minimumEdgePx else {
            return .failure(.frameTooSmall)
        }
        func pixel(_ value: Double, limit: Int, rounding: FloatingPointRoundingRule) -> Int {
            let rounded = value.rounded(rounding)
            // Clamp before conversion: Double(Int.max) rounds outside Int's range.
            if rounded >= Double(limit) { return limit }
            return Int(max(0, rounded))
        }
        let x = pixel(rect.x * Double(frameWidth), limit: frameWidth - 1, rounding: .down)
        let y = pixel(rect.y * Double(frameHeight), limit: frameHeight - 1, rounding: .down)
        let right = pixel((rect.x + rect.w) * Double(frameWidth), limit: frameWidth, rounding: .up)
        let bottom = pixel((rect.y + rect.h) * Double(frameHeight), limit: frameHeight, rounding: .up)
        let w = right - x, h = bottom - y
        guard w >= minimumEdgePx, h >= minimumEdgePx else { return .failure(.belowMinimum) }
        return .success(CropGeometry(x: x, y: y, width: w, height: h,
                                     aspect: Double(w) / Double(h)))
    }
}

/// A detector's suggestion for one frame. `confidence` in (0, 1].
public struct CropSuggestion: Equatable, Sendable {
    public let rect: NormalizedRect
    public let confidence: Double
    public init?(rect: NormalizedRect, confidence: Double) {
        guard confidence.isFinite, confidence > 0, confidence <= 1 else { return nil }
        self.rect = rect; self.confidence = confidence
    }
}

/// The N10 seam. Implementations must be cheap enough for the decode cadence
/// and must never retain pixel bytes.
public protocol CropDetecting: Sendable {
    func suggest(frame: NativeFrame) -> CropSuggestion?
}

/// Accepted stub: never suggests. Real letterbox/pillarbox analysis is N10.
public struct NullCropDetector: CropDetecting, Sendable {
    public init() {}
    public func suggest(frame: NativeFrame) -> CropSuggestion? { nil }
}

public struct CropController: Sendable {
    public enum AutoVerdict: Equatable, Sendable {
        case applied(CropGeometry)
        case noSuggestion
        case rejected(CropStageError)
        case refusedStaleSession
    }

    public private(set) var current: NormalizedRect = .full
    public let session: UInt64
    public let detector: any CropDetecting
    /// Auto-suggestions apply only at or above this confidence.
    public let autoThreshold: Double

    public init?(session: UInt64, detector: any CropDetecting = NullCropDetector(),
                autoThreshold: Double) {
        guard autoThreshold.isFinite, (0...1).contains(autoThreshold) else { return nil }
        self.session = session
        self.detector = detector
        self.autoThreshold = autoThreshold
    }

    public mutating func set(_ rect: NormalizedRect) { current = rect }
    public mutating func clear() { current = .full }

    /// Resolve the current crop against a frame of this session.
    public func geometry(frame: NativeFrame) -> Result<CropGeometry, CropStageError>? {
        guard frame.session == session else { return nil }
        return CropStage.resolve(current, frameWidth: frame.width, frameHeight: frame.height)
    }

    /// One detection pass. A suggestion at/above the threshold replaces the
    /// current crop and returns its resolved geometry; anything weaker leaves
    /// the crop untouched.
    public mutating func autoApply(frame: NativeFrame) -> AutoVerdict {
        guard frame.session == session else { return .refusedStaleSession }
        guard let s = detector.suggest(frame: frame), s.confidence >= autoThreshold else {
            return .noSuggestion
        }
        switch CropStage.resolve(s.rect, frameWidth: frame.width, frameHeight: frame.height) {
        case .success(let g):
            current = s.rect
            return .applied(g)
        case .failure(let e):
            return .rejected(e)
        }
    }
}
