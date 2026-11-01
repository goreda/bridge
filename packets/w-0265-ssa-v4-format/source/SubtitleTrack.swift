import Foundation

/// Sidecar subtitle track loader (lanes L5/L6, unit u2): picks the parser by
/// file extension (.srt, .ass, .ssa) and returns cues plus the optional ASS
/// style table. Unknown extensions and unreadable files are typed refusals,
/// never silent fallbacks. Pure loader; no playback or rendering here.
public enum SubtitleTrack {

    public enum LoadError: Error, Equatable {
        case unknownFormat(path: String)
        case unreadable(path: String)
    }

    public struct Track: Equatable, Sendable {
        public let format: String // "srt" or "ass" (.ssa normalizes to "ass")
        public let cues: [SubtitleCue]
        public let styles: [ASSParser.Style]
        /// ASS override blocks detected during load: UNSUPPORTED rendering
        /// instructions, reported, never silently stripped. Empty for SRT.
        public let unsupportedOverrides: [ASSParser.OverrideReport]
        /// ASS Style rows that failed parsing during load: caller-visible at
        /// the loader entry point too, never dropped between parser and
        /// consumer. Empty for SRT.
        public let skippedStyles: [ASSParser.SkippedStyle]
        /// ASS PlayRes layout reference frame; nil for SRT or when absent.
        public let playResX: Int?
        public let playResY: Int?

        public init(format: String, cues: [SubtitleCue], styles: [ASSParser.Style],
                    unsupportedOverrides: [ASSParser.OverrideReport],
                    skippedStyles: [ASSParser.SkippedStyle], playResX: Int?, playResY: Int?) {
            self.format = format
            self.cues = cues
            self.styles = styles
            self.unsupportedOverrides = unsupportedOverrides
            self.skippedStyles = skippedStyles
            self.playResX = playResX
            self.playResY = playResY
        }
    }

    public static func load(path: String) throws -> Track {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "srt" || ext == "ass" || ext == "ssa" else { throw LoadError.unknownFormat(path: path) }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable(path: path)
        }
        if ext == "srt" {
            return Track(format: "srt", cues: try SRTParser.parse(text), styles: [],
                         unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        }
        let doc = try ASSParser.parse(text)
        return Track(format: "ass", cues: doc.cues, styles: doc.styles,
                     unsupportedOverrides: doc.unsupportedOverrides, skippedStyles: doc.skippedStyles,
                     playResX: doc.playResX, playResY: doc.playResY)
    }
}
