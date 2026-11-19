import Foundation

// R6 (arch-195l, dispatch L6): audio track selection policy + audio delay
// value semantics. Pure Swift, Linux-verifiable; the Mac wiring
// (FFmpegSoftwareAudioDecoder preferred stream, session commands) consumes
// these types. Selection is typed and loud: an explicit request that the
// container cannot honor is a typed refusal, never a silent fallback.

/// One audio track as the control layer needs it (mirrors the audio rows of
/// MediaInventory.Track without importing the FFmpeg adapter).
public struct AudioTrackInfo: Equatable, Sendable {
    /// Container stream index (avformat stream index, not an ordinal).
    public let index: Int
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public init?(index: Int, language: String?, title: String?, isDefault: Bool) {
        guard index >= 0 else { return nil }
        self.index = index; self.language = language
        self.title = title; self.isDefault = isDefault
    }
}

public enum AudioTrackSelector: Equatable, Sendable {
    /// Container default flag first, else the lowest stream index.
    case auto
    /// Exact container stream index.
    case index(Int)
    /// Exact language tag, case-insensitive (e.g. "eng", "tur").
    case language(String)
}

public enum AudioTrackRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case noAudioTracks
    case requestedIndexAbsent(Int)
    case requestedLanguageAbsent(String)
    /// 199r-01 MULTIAUDIO: two tracks carry the same container stream index, so
    /// any pick among them would be arbitrary. Typed refusal, never a silent pick.
    case duplicateIndex(Int)
    public var description: String {
        switch self {
        case .noAudioTracks: return "noAudioTracks"
        case .requestedIndexAbsent(let i): return "requestedIndexAbsent(\(i))"
        case .requestedLanguageAbsent(let l): return "requestedLanguageAbsent(\(l))"
        case .duplicateIndex(let i): return "duplicateIndex(\(i))"
        }
    }
}

public enum AudioTrackPlan {
    public static func select(_ selector: AudioTrackSelector, from tracks: [AudioTrackInfo])
        -> Result<AudioTrackInfo, AudioTrackRefusal> {
        guard !tracks.isEmpty else { return .failure(.noAudioTracks) }
        // 199r-01: an ambiguous inventory is refused before any selector runs.
        if let d = duplicateIndex(in: tracks) { return .failure(.duplicateIndex(d)) }
        switch selector {
        case .auto:
            if let d = tracks.first(where: { $0.isDefault }) { return .success(d) }
            return .success(tracks.min(by: { $0.index < $1.index })!)
        case .index(let i):
            guard i >= 0, let t = tracks.first(where: { $0.index == i }) else {
                return .failure(.requestedIndexAbsent(i))
            }
            return .success(t)
        case .language(let lang):
            let wanted = lang.lowercased()
            guard let t = tracks.first(where: { $0.language?.lowercased() == wanted }) else {
                return .failure(.requestedLanguageAbsent(lang))
            }
            return .success(t)
        }
    }

    /// 199r-01 MULTIAUDIO: ordered language preferences followed by the current
    /// auto policy. Deterministic: the first preference that matches any track
    /// wins, and within one preference the first matching track in inventory
    /// order. A preference that matches nothing advances to the next one;
    /// exhausted preferences resolve exactly like `.auto`. Matching is
    /// case-insensitive, same as `.language`. An ambiguous inventory is refused
    /// before any preference runs; an empty preference list is pure auto.
    public static func selectPreferred(_ preferences: [String], from tracks: [AudioTrackInfo])
        -> Result<AudioTrackInfo, AudioTrackRefusal> {
        guard !tracks.isEmpty else { return .failure(.noAudioTracks) }
        if let d = duplicateIndex(in: tracks) { return .failure(.duplicateIndex(d)) }
        for preference in preferences {
            let wanted = preference.lowercased()
            if let t = tracks.first(where: { $0.language?.lowercased() == wanted }) {
                return .success(t)
            }
        }
        return select(.auto, from: tracks)
    }

    /// The first container stream index carried by more than one track, if any.
    private static func duplicateIndex(in tracks: [AudioTrackInfo]) -> Int? {
        var seen = Set<Int>()
        for t in tracks where !seen.insert(t.index).inserted { return t.index }
        return nil
    }
}

/// User audio delay, mpv audio-delay convention: POSITIVE delays the audio
/// relative to the video. Setting REPLACES the value; it never accumulates.
public struct AudioDelay: Equatable, Sendable {
    public static let limitSeconds = 600.0
    public let seconds: Double
    public init?(_ seconds: Double) {
        guard seconds.isFinite, abs(seconds) <= AudioDelay.limitSeconds else { return nil }
        self.seconds = seconds
    }
}
