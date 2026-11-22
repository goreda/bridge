import Foundation

/// Numpad-style ASS alignment anchor (1...9).
public enum CueAnchor: Int, Sendable, Equatable {
    case bottomLeft = 1, bottomCenter = 2, bottomRight = 3
    case middleLeft = 4, middleCenter = 5, middleRight = 6
    case topLeft = 7, topCenter = 8, topRight = 9

    /// 0 = left edge, 0.5 = centered, 1 = right edge of the safe area.
    var horizontalFraction: Double {
        switch self {
        case .bottomLeft, .middleLeft, .topLeft: return 0
        case .bottomCenter, .middleCenter, .topCenter: return 0.5
        case .bottomRight, .middleRight, .topRight: return 1
        }
    }

    /// 0 = top edge, 0.5 = centered, 1 = bottom edge of the safe area.
    var verticalFraction: Double {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: return 1
        case .middleLeft, .middleCenter, .middleRight: return 0.5
        case .topLeft, .topCenter, .topRight: return 0
        }
    }
}

/// Per-cue layout metadata recorded at parse time.
struct CueMeta: Equatable {
    var anchor: CueAnchor
}
