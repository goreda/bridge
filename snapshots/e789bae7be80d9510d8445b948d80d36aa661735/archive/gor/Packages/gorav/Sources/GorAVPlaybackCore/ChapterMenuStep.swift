import Foundation

/// MENU-CAPABILITY-PARITY slice 1: the chrome `add chapter <n>` command on the
/// gorav engine. mpv admits arbitrary integer skips; the delivered chapter
/// session API (GorAVEmbeddedSession.navigateChapter) navigates one chapter
/// per call, so only +/-1 routes today. Every other delta is refused with a
/// visible token - never silently clamped, floored or dropped (the parity
/// row's "no silent noops" rule).
public enum ChapterMenuStepRefusal: Error, Equatable, Sendable {
    case missingDelta
    case nonFinite
    case nonInteger
    case zero
    case skipBeyondOne
    /// OSD/log-safe token. Carries no command payload or path.
    public var token: String {
        switch self {
        case .missingDelta: return "chapter step requires a delta"
        case .nonFinite: return "chapter step delta must be finite"
        case .nonInteger: return "chapter step delta must be an integer"
        case .zero: return "chapter step of zero is not a navigation"
        case .skipBeyondOne: return "chapter skip beyond one chapter is not routed yet"
        }
    }
}

public enum ChapterMenuStep {
    /// Maps the mpv `add chapter <delta>` argument onto one navigation
    /// direction. Numeric strings arrive pre-parsed by the chrome router
    /// (GorAVPlayerHost number()), so the only accepted magnitudes are
    /// exactly 1 and -1.
    public static func direction(forDelta delta: Double?) -> Result<ChapterDirection, ChapterMenuStepRefusal> {
        guard let delta else { return .failure(.missingDelta) }
        guard delta.isFinite else { return .failure(.nonFinite) }
        guard delta.rounded() == delta else { return .failure(.nonInteger) }
        if delta == 0 { return .failure(.zero) }
        if delta == 1 { return .success(.next) }
        if delta == -1 { return .success(.previous) }
        return .failure(.skipBeyondOne)
    }
}
