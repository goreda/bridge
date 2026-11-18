/// Strict, bounded WebVTT parser. Same role as SRTParser: whole-document text
/// in, `SubtitleCue` values out, typed refusals on malformed input, no guessing
/// and no partial adoption of a broken block.
///
/// Scope (documented boundaries):
/// - Signature line: "WEBVTT" alone or followed by a space/tab and free text.
///   Keywords (WEBVTT, NOTE, STYLE, REGION, setting names) are case-sensitive and
///   matched on Unicode scalars, so no locale or case folding (Turkish dotted /
///   dotless i) can change what a keyword means.
/// - A blank line is an EMPTY line (WebVTT rule, unlike SRT): a whitespace-only
///   line is cue text. Tolerates a UTF-8 BOM and CR/LF/CRLF endings.
/// - Blocks: header block, then NOTE (skipped, typed; keyword + space/tab/EOL),
///   STYLE and REGION (keyword ALONE on the line; "STYLE foo" is a cue identifier),
///   cue blocks. STYLE/REGION after the first cue refuse.
/// - Cue: optional identifier line (must not contain "-->"), timing line
///   "start --> end [settings]" (separator: whitespace, "-->", whitespace),
///   one or more text lines (no "-->"), kept verbatim (inline tags untouched).
/// - Timestamps: [hh:]mm:ss.ttt, hours >= 2 digits, mm/ss two digits < 60,
///   milliseconds exactly three digits, "." only. end must be > start.
/// - Settings: vertical, line, position, size, align, region. Unknown names,
///   bad values, duplicates and unknown region ids refuse (stricter than the
///   spec, which ignores them; chosen to match SRTParser's no-guessing stance).
/// - Overlapping cues are accepted; file order is preserved. `SubtitleCue.index`
///   is the 1-based position of the cue in file order. Identifiers and settings
///   do not fit the pinned SubtitleCue type (unchanged), so they travel in the
///   parallel `VTTDocument.cueInfo` array.
/// - Malformed-input recovery: refuse the whole document with one typed error
///   (no partial adoption of earlier good cues), consistent with SRTParser.
/// - Bounds: input size, line count, cue count, line length (see `Limits`).
public enum VTTParser {

    public enum VTTError: Error, Equatable {
        case emptyDocument
        case inputTooLarge(limit: Int)
        case tooManyLines(limit: Int)
        case lineTooLong(line: Int, limit: Int)
        case tooManyCues(limit: Int)
        case missingSignature(line: Int)
        case badHeader(line: Int)
        case badTimingLine(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case missingText(line: Int)
        case textContainsArrow(line: Int)
        case badSetting(line: Int)
        case duplicateSetting(line: Int)
        case unknownRegion(line: Int)
        case badRegion(line: Int)
        case misplacedBlock(line: Int)
        case noteContainsArrow(line: Int)
    }

    public struct Limits: Equatable, Sendable {
        public var maxBytes: Int
        public var maxLines: Int
        public var maxLineScalars: Int
        public var maxCues: Int
        public init(maxBytes: Int = 16 * 1024 * 1024, maxLines: Int = 1_000_000,
                    maxLineScalars: Int = 65_536, maxCues: Int = 200_000) {
            self.maxBytes = maxBytes; self.maxLines = maxLines
            self.maxLineScalars = maxLineScalars; self.maxCues = maxCues
        }
        public static let `default` = Limits()
    }

    public enum Direction: String, Equatable, Sendable { case rl, lr }
    public enum Align: String, Equatable, Sendable { case start, center, end, left, right, lineLeft = "line-left", lineRight = "line-right" }
    public enum LinePosition: Equatable, Sendable {
        case number(Int)
        case percent(Double)
    }

    public struct CueSettings: Equatable, Sendable {
        public var vertical: Direction?
        public var line: LinePosition?
        public var lineAlign: Align?
        public var position: Double?
        public var positionAlign: Align?
        public var size: Double?
        public var align: Align?
        public var region: String?
        public init() {}
    }

    public struct Region: Equatable, Sendable {
        public var id: String
        public var width: Double?
        public var lines: Int?
        public var regionAnchor: (x: Double, y: Double)?
        public var viewportAnchor: (x: Double, y: Double)?
        public var scrollUp: Bool
        public static func == (a: Region, b: Region) -> Bool {
            a.id == b.id && a.width == b.width && a.lines == b.lines && a.scrollUp == b.scrollUp
                && a.regionAnchor?.x == b.regionAnchor?.x && a.regionAnchor?.y == b.regionAnchor?.y
                && a.viewportAnchor?.x == b.viewportAnchor?.x && a.viewportAnchor?.y == b.viewportAnchor?.y
        }
    }

    public struct CueInfo: Equatable, Sendable {
        public var identifier: String?
        public var settings: CueSettings
        /// 1-based line of the timing line.
        public var timingLine: Int
    }

    public enum SkippedKind: Equatable, Sendable { case note, style }
    public struct SkippedBlock: Equatable, Sendable {
        public var kind: SkippedKind
        public var line: Int
        public var lines: [String]
    }

    public struct Document: Equatable, Sendable {
        public var headerText: String
        public var cues: [SubtitleCue]
        /// Parallel to `cues`.
        public var cueInfo: [CueInfo]
        public var regions: [Region]
        public var skipped: [SkippedBlock]
    }

    /// Mirrors SRTParser.parse, with the Result form named by the packet.
    public static func parse(_ text: String) -> Result<[SubtitleCue], VTTError> {
        parse(text, limits: .default)
    }

    public static func parse(_ text: String, limits: Limits) -> Result<[SubtitleCue], VTTError> {
        do { return .success(try parseDocument(text, limits: limits).cues) }
        catch let e as VTTError { return .failure(e) }
        catch { preconditionFailure("unreachable: only VTTError is thrown") }
    }

    /// Throwing form, same shape as `SRTParser.parse`.
    public static func parseThrowing(_ text: String) throws -> [SubtitleCue] {
        try parseDocument(text, limits: .default).cues
    }

    public static func parseDocument(_ content: String, limits: Limits = .default) throws -> Document {
        guard content.utf8.count <= limits.maxBytes else { throw VTTError.inputTooLarge(limit: limits.maxBytes) }
        let lines = try splitLines(content, limits: limits)

        // Signature.
        guard let first = lines.first else { throw VTTError.emptyDocument }
        guard let header = headerText(first) else {
            if lines.allSatisfy({ $0.isEmpty }) { throw VTTError.emptyDocument }
            throw VTTError.missingSignature(line: 1)
        }
        var i = 1
        // Header block continues to the first empty line. It must not hold "-->".
        while i < lines.count && !lines[i].isEmpty {
            if lines[i].contains("-->") { throw VTTError.badHeader(line: i + 1) }
            i += 1
        }

        var doc = Document(headerText: header, cues: [], cueInfo: [], regions: [], skipped: [])
        var regionIDs = Set<String>()

        while i < lines.count {
            while i < lines.count && lines[i].isEmpty { i += 1 }
            guard i < lines.count else { break }
            let start = i
            var block: [String] = []
            while i < lines.count && !lines[i].isEmpty { block.append(lines[i]); i += 1 }
            let startLine = start + 1
            let head = block[0]

            if isKeyword(head, "NOTE") {
                for (k, l) in block.enumerated() where l.contains("-->") { throw VTTError.noteContainsArrow(line: startLine + k) }
                doc.skipped.append(SkippedBlock(kind: .note, line: startLine, lines: block))
                continue
            }
            if head == "STYLE" {
                if !doc.cues.isEmpty { throw VTTError.misplacedBlock(line: startLine) }
                doc.skipped.append(SkippedBlock(kind: .style, line: startLine, lines: block))
                continue
            }
            if head == "REGION" {
                if !doc.cues.isEmpty { throw VTTError.misplacedBlock(line: startLine) }
                let r = try parseRegion(block, startLine: startLine)
                guard !regionIDs.contains(r.id) else { throw VTTError.badRegion(line: startLine) }
                regionIDs.insert(r.id)
                doc.regions.append(r)
                continue
            }

            // Cue block.
            var k = 0
            var identifier: String? = nil
            if !head.contains("-->") {
                identifier = head
                k = 1
            }
            guard k < block.count, block[k].contains("-->") else { throw VTTError.badTimingLine(line: startLine + k) }
            let timingLine = startLine + k
            let (s, e, settings) = try parseTiming(block[k], line: timingLine, regions: regionIDs)
            let textLines = Array(block[(k + 1)...])
            guard !textLines.isEmpty else { throw VTTError.missingText(line: timingLine + 1) }
            for (t, l) in textLines.enumerated() where l.contains("-->") {
                throw VTTError.textContainsArrow(line: timingLine + 1 + t)
            }
            guard doc.cues.count < limits.maxCues else { throw VTTError.tooManyCues(limit: limits.maxCues) }
            doc.cues.append(SubtitleCue(index: doc.cues.count + 1, startSeconds: s, endSeconds: e, lines: textLines))
            doc.cueInfo.append(CueInfo(identifier: identifier, settings: settings, timingLine: timingLine))
        }
        return doc
    }

    // MARK: - Lines

    /// Splits on CRLF / CR / LF over unicode scalars (Swift treats "\r\n" as one
    /// Character, so Character-based splitting is avoided on purpose).
    static func splitLines(_ content: String, limits: Limits) throws -> [String] {
        var scalars = Array(content.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        var curCount = 0
        var j = 0
        func flush() throws {
            out.append(String(cur))
            cur = String.UnicodeScalarView(); curCount = 0
            if out.count > limits.maxLines { throw VTTError.tooManyLines(limit: limits.maxLines) }
        }
        while j < scalars.count {
            let c = scalars[j]
            if c == "\r" {
                try flush()
                if j + 1 < scalars.count && scalars[j + 1] == "\n" { j += 1 }
            } else if c == "\n" {
                try flush()
            } else {
                cur.append(c); curCount += 1
                if curCount > limits.maxLineScalars { throw VTTError.lineTooLong(line: out.count + 1, limit: limits.maxLineScalars) }
            }
            j += 1
        }
        if !cur.isEmpty { try flush() }
        return out
    }

    static func headerText(_ line: String) -> String? {
        let u = Array(line.unicodeScalars)
        let sig = Array("WEBVTT".unicodeScalars)
        guard u.count >= sig.count, Array(u[0..<sig.count]) == sig else { return nil }
        if u.count == sig.count { return "" }
        guard u[sig.count] == " " || u[sig.count] == "\t" else { return nil }
        return String(String.UnicodeScalarView(u[(sig.count + 1)...]))
    }

    /// Keyword followed by end of line, space or tab (scalar comparison).
    static func isKeyword(_ line: String, _ kw: String) -> Bool {
        let u = Array(line.unicodeScalars), k = Array(kw.unicodeScalars)
        guard u.count >= k.count, Array(u[0..<k.count]) == k else { return false }
        return u.count == k.count || u[k.count] == " " || u[k.count] == "\t"
    }

    // MARK: - Timing

    static func isSep(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if isSep(c) { if !cur.isEmpty { out.append(String(cur)); cur = String.UnicodeScalarView() } }
            else { cur.append(c) }
        }
        if !cur.isEmpty { out.append(String(cur)) }
        return out
    }

    static func parseTiming(_ line: String, line number: Int, regions: Set<String>) throws -> (Double, Double, CueSettings) {
        let t = tokens(line)
        guard t.count >= 3, t[1] == "-->" else { throw VTTError.badTimingLine(line: number) }
        // "-->" must be set off by whitespace on both sides.
        guard let start = parseTimestamp(t[0]) else { throw VTTError.badTimestamp(line: number) }
        guard let end = parseTimestamp(t[2]) else { throw VTTError.badTimestamp(line: number) }
        guard end > start else { throw VTTError.endNotAfterStart(line: number) }
        let settings = try parseSettings(Array(t[3...]), line: number, regions: regions)
        return (start, end, settings)
    }

    static func allDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    /// [hh:]mm:ss.ttt
    static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var hh = 0
        var idx = 0
        if parts.count == 3 {
            guard parts[0].unicodeScalars.count >= 2, allDigits(parts[0]), let h = Int(parts[0]) else { return nil }
            hh = h; idx = 1
        }
        guard parts[idx].unicodeScalars.count == 2, allDigits(parts[idx]), let mm = Int(parts[idx]), mm < 60 else { return nil }
        let sm = parts[idx + 1].split(separator: ".", omittingEmptySubsequences: false)
        guard sm.count == 2 else { return nil }
        guard sm[0].unicodeScalars.count == 2, allDigits(sm[0]), let ss = Int(sm[0]), ss < 60 else { return nil }
        guard sm[1].unicodeScalars.count == 3, allDigits(sm[1]), let ms = Int(sm[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(ms) / 1000
    }

    // MARK: - Settings

    static func parsePercent(_ s: Substring) -> Double? {
        guard s.hasSuffix("%") else { return nil }
        let body = s.dropLast()
        guard let v = parseDecimal(body), v >= 0, v <= 100 else { return nil }
        return v
    }

    /// digits[.digits] only (no sign, exponent, inf, nan).
    static func parseDecimal(_ s: Substring) -> Double? {
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        guard p.count <= 2, allDigits(p[0]) else { return nil }
        if p.count == 2 { guard allDigits(p[1]) else { return nil } }
        return Double(String(s))
    }

    static func parseSettings(_ toks: [String], line: Int, regions: Set<String>) throws -> CueSettings {
        var st = CueSettings()
        var seen = Set<String>()
        for tok in toks {
            let kv = tok.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, !kv[1].isEmpty else { throw VTTError.badSetting(line: line) }
            let key = String(kv[0]), val = kv[1]
            guard ["vertical", "line", "position", "size", "align", "region"].contains(key) else { throw VTTError.badSetting(line: line) }
            guard seen.insert(key).inserted else { throw VTTError.duplicateSetting(line: line) }
            let comma = val.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            switch key {
            case "vertical":
                guard let d = Direction(rawValue: String(val)) else { throw VTTError.badSetting(line: line) }
                st.vertical = d
            case "line":
                let v = comma[0]
                if let p = parsePercent(v) { st.line = .percent(p) }
                else {
                    var digits = v
                    if digits.hasPrefix("-") { digits = digits.dropFirst() }
                    guard allDigits(digits), let n = Int(String(v)) else { throw VTTError.badSetting(line: line) }
                    st.line = .number(n)
                }
                if comma.count == 2 {
                    guard let a = Align(rawValue: String(comma[1])), [.start, .center, .end].contains(a) else { throw VTTError.badSetting(line: line) }
                    st.lineAlign = a
                }
            case "position":
                guard let p = parsePercent(comma[0]) else { throw VTTError.badSetting(line: line) }
                st.position = p
                if comma.count == 2 {
                    guard let a = Align(rawValue: String(comma[1])), [.lineLeft, .center, .lineRight].contains(a) else { throw VTTError.badSetting(line: line) }
                    st.positionAlign = a
                }
            case "size":
                guard let p = parsePercent(val) else { throw VTTError.badSetting(line: line) }
                st.size = p
            case "align":
                guard let a = Align(rawValue: String(val)), [.start, .center, .end, .left, .right].contains(a) else { throw VTTError.badSetting(line: line) }
                st.align = a
            default: // region
                let id = String(val)
                guard regions.contains(id) else { throw VTTError.unknownRegion(line: line) }
                st.region = id
            }
        }
        return st
    }

    // MARK: - Region

    static func parseAnchor(_ s: Substring) -> (x: Double, y: Double)? {
        let p = s.split(separator: ",", omittingEmptySubsequences: false)
        guard p.count == 2, let x = parsePercent(p[0]), let y = parsePercent(p[1]) else { return nil }
        return (x, y)
    }

    static func parseRegion(_ block: [String], startLine: Int) throws -> Region {
        var r = Region(id: "", width: nil, lines: nil, regionAnchor: nil, viewportAnchor: nil, scrollUp: false)
        var seen = Set<String>()
        var haveID = false
        for (k, l) in block.dropFirst().enumerated() {
            let ln = startLine + 1 + k
            for tok in tokens(l) {
                let kv = tok.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard kv.count == 2, !kv[1].isEmpty else { throw VTTError.badRegion(line: ln) }
                let key = String(kv[0]), val = kv[1]
                guard seen.insert(key).inserted else { throw VTTError.badRegion(line: ln) }
                switch key {
                case "id": r.id = String(val); haveID = true
                case "width":
                    guard let p = parsePercent(val) else { throw VTTError.badRegion(line: ln) }
                    r.width = p
                case "lines":
                    guard allDigits(val), let n = Int(String(val)), n > 0 else { throw VTTError.badRegion(line: ln) }
                    r.lines = n
                case "regionanchor":
                    guard let a = parseAnchor(val) else { throw VTTError.badRegion(line: ln) }
                    r.regionAnchor = a
                case "viewportanchor":
                    guard let a = parseAnchor(val) else { throw VTTError.badRegion(line: ln) }
                    r.viewportAnchor = a
                case "scroll":
                    guard val == "up" else { throw VTTError.badRegion(line: ln) }
                    r.scrollUp = true
                default: throw VTTError.badRegion(line: ln)
                }
            }
        }
        guard haveID, !r.id.isEmpty, !r.id.contains("-->") else { throw VTTError.badRegion(line: startLine) }
        return r
    }
}
