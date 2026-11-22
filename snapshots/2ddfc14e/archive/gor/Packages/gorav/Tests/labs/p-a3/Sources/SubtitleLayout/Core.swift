// P-A3 clean-room subtitle parsing and deterministic fixed-cell layout.
// Public contract from bridge packet P-A3 (goreda/bridge GROUP-INBOX.md).
// No renderer, no Metal/UI, no font measurement.

import Foundation

/// One parsed subtitle cue. Times are seconds from media start.
public struct Cue: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let track: Int

    public init(start: Double, end: Double, text: String, track: Int) {
        self.start = start
        self.end = end
        self.text = text
        self.track = track
    }
}

/// Deterministic layout rectangle for one active cue.
/// Origin is the top-left corner of the viewport; y grows downward.
public struct CueBox: Equatable, Sendable {
    public let cue: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(cue: Int, x: Double, y: Double, width: Double, height: Double) {
        self.cue = cue
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Errors thrown while parsing subtitle text.
public enum SubtitleParseError: Error, Equatable, Sendable {
    /// The `format` argument is neither "srt" nor "ass" (case-insensitive).
    case unsupportedFormat(String)
    /// A cue time range is malformed or has end <= start. Carries the offending line.
    case malformedTimeRange(String)
    /// A cue block is structurally malformed (missing index, timing line, or text).
    case malformedCue(String)
    /// The input contains no parseable cue content.
    case emptyInput
}

/// Errors thrown while laying out cues.
public enum SubtitleLayoutError: Error, Equatable, Sendable {
    /// Viewport dimensions must be finite and positive.
    case invalidViewport(width: Double, height: Double)
    /// Cell dimensions must be finite and positive.
    case invalidCellSize(width: Double, height: Double)
}

/// Public contract from packet P-A3.
public protocol SubtitleLayout {
    func parse(text: String, format: String) throws -> [Cue]
    func active(cues: [Cue], at seconds: Double) -> [Int]
    func layout(cues: [Cue], active: [Int], viewportWidth: Double, viewportHeight: Double) throws -> [CueBox]
}
