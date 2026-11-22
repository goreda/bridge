// P-A3-R1: strict configuration validation layered on the unchanged P-A3
// FixedCellSubtitleLayout. Fails explicitly with named errors instead of
// producing layout boxes from unchecked configuration.
//
// Original P-A3 package is vendored byte-identical under Vendor/; this file
// is new in R1 and changes nothing in the original.

import Foundation
import SubtitleLayout

/// Named errors for unchecked configuration, raised before any box is made.
public enum SubtitleConfigError: Error, Equatable, Sendable {
    /// Cell width/height is NaN or infinite.
    case nonFiniteCellSize(width: Double, height: Double)
    /// Cell width/height is zero or negative.
    case nonPositiveCellSize(width: Double, height: Double)
    /// Safe-area fraction is NaN or infinite.
    case nonFiniteSafeAreaFraction(Double)
    /// Safe-area fraction outside [0, 0.5); at 0.5 the safe area is empty.
    case outOfRangeSafeAreaFraction(Double)
    /// A PlayResX/PlayResY header line exists but does not parse to a finite
    /// number (covers "nan", "inf", and non-numeric text). Carries raw text.
    case nonFinitePlayRes(rawX: String?, rawY: String?)
    /// A PlayRes value parses but is zero or negative. Carries raw text.
    case nonPositivePlayRes(rawX: String?, rawY: String?)
}

/// SubtitleLayout wrapper that validates all layout-shaping configuration
/// up front and delegates parsing/geometry to the unchanged P-A3 engine.
///
/// Checked configuration:
/// - cell size and safe-area fraction at init (throwing init);
/// - ASS PlayResX/PlayResY header values at parse time.
///
/// Metadata isolation is inherited from the P-A3 engine and pinned by the
/// R1 regression tests: anchor/PlayRes metadata only applies to the exact
/// cue array returned by the instance's most recent parse. Cue arrays from
/// another parse, another instance, or hand-built arrays lay out with the
/// documented defaults (bottom-center, no PlayRes scaling).
public final class StrictSubtitleLayout: SubtitleLayout {

    public let cellWidth: Double
    public let cellHeight: Double
    public let safeAreaFraction: Double

    private let inner: FixedCellSubtitleLayout

    public init(cellWidth: Double = 10, cellHeight: Double = 20, safeAreaFraction: Double = 0.05) throws {
        guard cellWidth.isFinite, cellHeight.isFinite else {
            throw SubtitleConfigError.nonFiniteCellSize(width: cellWidth, height: cellHeight)
        }
        guard cellWidth > 0, cellHeight > 0 else {
            throw SubtitleConfigError.nonPositiveCellSize(width: cellWidth, height: cellHeight)
        }
        guard safeAreaFraction.isFinite else {
            throw SubtitleConfigError.nonFiniteSafeAreaFraction(safeAreaFraction)
        }
        guard safeAreaFraction >= 0, safeAreaFraction < 0.5 else {
            throw SubtitleConfigError.outOfRangeSafeAreaFraction(safeAreaFraction)
        }
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.safeAreaFraction = safeAreaFraction
        self.inner = FixedCellSubtitleLayout(
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            safeAreaFraction: safeAreaFraction
        )
    }

    public func parse(text: String, format: String) throws -> [Cue] {
        let lowered = format.lowercased()
        if lowered == "ass" || lowered == "ssa" {
            try Self.validatePlayResHeader(text)
        }
        return try inner.parse(text: text, format: format)
    }

    public func active(cues: [Cue], at seconds: Double) -> [Int] {
        inner.active(cues: cues, at: seconds)
    }

    public func layout(cues: [Cue], active: [Int], viewportWidth: Double, viewportHeight: Double) throws -> [CueBox] {
        try inner.layout(cues: cues, active: active, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
    }

    /// Scans the [Script Info] PlayRes header lines only. An absent header is
    /// valid (no PlayRes scaling). A present header must hold a finite,
    /// positive number; anything else throws a named error with the raw text.
    static func validatePlayResHeader(_ text: String) throws {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var inScriptInfo = false
        var rawX: String?
        var rawY: String?
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inScriptInfo = trimmed.lowercased() == "[script info]"
                continue
            }
            guard inScriptInfo else { continue }
            let kv = trimmed.components(separatedBy: ":")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            if key == "playresx" { rawX = value }
            if key == "playresy" { rawY = value }
        }
        for raw in [rawX, rawY] {
            guard let raw else { continue }
            guard let value = Double(raw), value.isFinite else {
                throw SubtitleConfigError.nonFinitePlayRes(rawX: rawX, rawY: rawY)
            }
            guard value > 0 else {
                throw SubtitleConfigError.nonPositivePlayRes(rawX: rawX, rawY: rawY)
            }
        }
    }
}
