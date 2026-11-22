import Foundation

/// Deterministic subtitle layout over a fixed character cell.
///
/// No font measurement is performed anywhere: every grapheme cluster occupies
/// one fixed cell (`cellWidth` x `cellHeight`, default 10 x 20, supplied by
/// the caller and documented in SPEC.md) and every text line occupies one
/// cell height. Coordinates: origin at the top-left of the viewport, y grows
/// downward. Boxes are anchored inside a safe area inset by
/// `safeAreaFraction` (default 5%) on every side.
///
/// PlayRes scaling: when the most recent parse was ASS with explicit
/// PlayResX/PlayResY, cell sizes and positions scale by viewport / PlayRes,
/// so boxes are defined in PlayRes space and mapped onto the viewport.
///
/// Stacking: cues sharing one anchor stack away from the anchor edge in
/// active order (bottom anchors upward, middle/top anchors downward).
///
/// Layout metadata comes from the most recent `parse` call on this instance;
/// cue arrays that did not come from that parse are laid out bottom-center
/// with no PlayRes scaling.
public final class FixedCellSubtitleLayout: SubtitleLayout {

    public let cellWidth: Double
    public let cellHeight: Double
    public let safeAreaFraction: Double

    private var parsedCues: [Cue] = []
    private var parsedMeta: [CueMeta] = []
    private var playResX: Double?
    private var playResY: Double?

    public init(cellWidth: Double = 10, cellHeight: Double = 20, safeAreaFraction: Double = 0.05) {
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.safeAreaFraction = safeAreaFraction
    }

    public func parse(text: String, format: String) throws -> [Cue] {
        switch format.lowercased() {
        case "srt":
            let cues = try SRTParser.parse(text)
            parsedCues = cues
            parsedMeta = cues.map { _ in CueMeta(anchor: .bottomCenter) }
            playResX = nil
            playResY = nil
            return cues
        case "ass", "ssa":
            let result = try ASSParser.parse(text)
            parsedCues = result.cues
            parsedMeta = result.meta
            playResX = result.playResX
            playResY = result.playResY
            return result.cues
        default:
            throw SubtitleParseError.unsupportedFormat(format)
        }
    }

    /// Half-open intervals: a cue is active when start <= t < end.
    /// Overlapping cues are all returned, in cue order.
    public func active(cues: [Cue], at seconds: Double) -> [Int] {
        cues.indices.filter { cues[$0].start <= seconds && seconds < cues[$0].end }
    }

    public func layout(cues: [Cue], active: [Int], viewportWidth: Double, viewportHeight: Double) throws -> [CueBox] {
        guard viewportWidth.isFinite, viewportHeight.isFinite, viewportWidth > 0, viewportHeight > 0 else {
            throw SubtitleLayoutError.invalidViewport(width: viewportWidth, height: viewportHeight)
        }
        guard cellWidth.isFinite, cellHeight.isFinite, cellWidth > 0, cellHeight > 0 else {
            throw SubtitleLayoutError.invalidCellSize(width: cellWidth, height: cellHeight)
        }

        let useMeta = (cues == parsedCues)
        let scaleX: Double
        let scaleY: Double
        if useMeta, let prx = playResX, let pry = playResY, prx > 0, pry > 0 {
            scaleX = viewportWidth / prx
            scaleY = viewportHeight / pry
        } else {
            scaleX = 1
            scaleY = 1
        }
        let cellW = cellWidth * scaleX
        let cellH = cellHeight * scaleY

        let safeL = safeAreaFraction * viewportWidth
        let safeT = safeAreaFraction * viewportHeight
        let safeW = Swift.max(0, viewportWidth * (1 - 2 * safeAreaFraction))
        let safeH = Swift.max(0, viewportHeight * (1 - 2 * safeAreaFraction))

        var boxes: [CueBox] = []
        var stackedDepth: [CueAnchor: Double] = [:]

        for index in active {
            guard cues.indices.contains(index) else { continue }
            let cue = cues[index]
            let anchor = (useMeta && parsedMeta.indices.contains(index))
                ? parsedMeta[index].anchor
                : .bottomCenter

            let lines = cue.text.split(separator: "\n", omittingEmptySubsequences: false)
            let maxLineChars = lines.map { $0.count }.max() ?? 0
            let width = Swift.min(Double(maxLineChars) * cellW, safeW)
            let height = Swift.min(Double(lines.count) * cellH, safeH)

            var x = safeL + anchor.horizontalFraction * (safeW - width)
            var y = safeT + anchor.verticalFraction * (safeH - height)

            let depth = stackedDepth[anchor] ?? 0
            if anchor.verticalFraction == 1 {
                y -= depth // bottom anchors stack upward
            } else {
                y += depth // middle/top anchors stack downward
            }
            stackedDepth[anchor] = depth + height

            // Keep the box inside the viewport even if a stack overflows.
            x = Swift.max(0, Swift.min(x, viewportWidth - width))
            y = Swift.max(0, Swift.min(y, viewportHeight - height))

            boxes.append(CueBox(cue: index, x: x, y: y, width: width, height: height))
        }
        return boxes
    }
}
