# W-gdb-199c-in2tinct-19 - Finite positive ASS font sizes
state: OPEN / unclaimed
lab: in2tinct

## Product change
parseStyle must report a skipped style for nonfinite or nonpositive Fontsize instead of admitting a NaN/infinity/negative rasterizer input. Keep the existing skippedStyles diagnostic path and valid source style values; do not clamp or silently substitute a size.

## Grounded gap and boundary
U2 subtitle font/style prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-19.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-19",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/ASSParser.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "parseStyle must report a skipped style for nonfinite or nonpositive Fontsize instead of admitting a NaN/infinity/negative rasterizer input. Keep the existing skippedStyles diagnostic path and valid source style values; do not clamp or silently substitute a size.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 subtitle font/style prerequisite",
    "callee": "Sources/GorAVSubtitles/ASSParser.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-19.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-19",
    "paths": [
      "Sources/GorAVSubtitles/ASSParser.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-19.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-19.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-19.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:51.933270+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "100d8b7b47c795354cb6fa5ca1b811205f0d4d4320dbc4dcdd5a05c6cfee4ea0",
    "last_5_lines": [
      "FAIL invalid font size diagnosed",
      "PASS valid style preserved",
      "semantic failures=4",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/ASSParser.swift",
        "block": "source1",
        "sha256": "4c16b99f1e1e78c7bd84346b35b0be6d670dff2df193bc9f69ac2a0ddc7d18f6",
        "read_only_dependency": false
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source2",
        "sha256": "2311ed3052c4a66f2d7942d23624b693faa52dc509354e22fbff148aa3abaa40",
        "read_only_dependency": true
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-19.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-19.json",
        "block": "fixtures2",
        "sha256": "bb6563d41735e0960053c7488193347a79d690390ba055cc0efbe09abe06ce47"
      }
    ],
    "receipt_sha256": "0fee6eff198888f79503afc7f344e968936abb280fce83be367a0286961c88f2"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

/// Minimal strict ASS/SSA parser (lane L6, unit u1): text subtitles with a
/// style table. Parses [Script Info] (PlayRes only), [V4+ Styles] (Style rows
/// via their own Format), [Events] (Format + Dialogue; Comment rows skipped).
/// Cue text: override blocks "{...}" are detected, reported as UNSUPPORTED
/// (Document.unsupportedOverrides, per-cue tag list) and removed from the
/// plain-text cue lines only. "\N"/"\n" are converted to line breaks, "\h"
/// to a non-breaking space. Karaoke timing, vector drawing and every other
/// rendering semantic inside override blocks are NOT interpreted or rendered:
/// unsupported means unsupported, never silently dropped without record.
/// Typed refusals on malformed structure; a malformed Style row is skipped
/// (cosmetic) while a malformed Dialogue row refuses (content).
public enum ASSParser {

    public enum ParseError: Error, Equatable {
        case missingEventsSection
        case missingEventsFormat(line: Int)
        case dialogueBeforeFormat(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case badDialogueFieldCount(line: Int)
        case missingText(line: Int)
        /// The event's text is ONLY override blocks: after (reported) removal
        /// nothing renderable remains. Typed refusal so the event is an
        /// explicit not-rendered record, never silently erased.
        case overrideOnlyText(line: Int)
    }

    public struct Style: Equatable, Sendable {
        public let name: String
        public let fontName: String
        public let fontSize: Double
        /// ASS stores &HAABBGGRR; this is the decoded AARRGGBB value.
        public let primaryColourARGB: UInt32

        public init(name: String, fontName: String, fontSize: Double, primaryColourARGB: UInt32) {
            self.name = name
            self.fontName = fontName
            self.fontSize = fontSize
            self.primaryColourARGB = primaryColourARGB
        }
    }

    /// One cue's unsupported rendering instructions: the override tag names
    /// (e.g. "\\pos", "\\fad") found in its "{...}" blocks. tags is empty when
    /// the block carried no backslash tag (e.g. a drawing-only block).
    public struct OverrideReport: Equatable, Sendable {
        public let cueIndex: Int
        public let tags: [String]

        public init(cueIndex: Int, tags: [String]) {
            self.cueIndex = cueIndex
            self.tags = tags
        }
    }

    /// A Style row that failed to parse: caller-visible, never a silent drop.
    /// reason: "field count", "missing required field", "bad fontsize",
    /// "bad colour".
    public struct SkippedStyle: Equatable, Sendable {
        public let line: Int
        public let reason: String

        public init(line: Int, reason: String) {
            self.line = line
            self.reason = reason
        }
    }

    public struct Document: Equatable, Sendable {
        public let styles: [Style]
        public let cues: [SubtitleCue]
        public let playResX: Int?
        public let playResY: Int?
        /// Every cue that carried override blocks; unsupported, reported.
        public let unsupportedOverrides: [OverrideReport]
        /// Style rows that failed parsing (cosmetic, but on record).
        public let skippedStyles: [SkippedStyle]
    }

    public static func parse(_ content: String) throws -> Document {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var section = ""
        var sawEvents = false
        var styleFields: [String] = []
        var eventFields: [String] = []
        var haveEventFormat = false
        var styles: [Style] = []
        var cues: [SubtitleCue] = []
        var overrideReports: [OverrideReport] = []
        var skippedStyles: [SkippedStyle] = []
        var playResX: Int? = nil
        var playResY: Int? = nil

        for (idx, raw) in lines.enumerated() {
            let lineNo = idx + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                if section == "events" { sawEvents = true }
                continue
            }
            let lowered = line.lowercased()
            switch section {
            case "script info":
                if let v = infoValue(line, key: "PlayResX") { playResX = Int(v) }
                if let v = infoValue(line, key: "PlayResY") { playResY = Int(v) }
            case "v4+ styles", "v4 styles":
                if lowered.hasPrefix("format:") {
                    styleFields = splitFields(String(line.dropFirst(7)))
                } else if lowered.hasPrefix("style:") {
                    switch parseStyle(String(line.dropFirst(6)), fields: styleFields) {
                    case .ok(let s): styles.append(s)
                    case .skipped(let reason): skippedStyles.append(SkippedStyle(line: lineNo, reason: reason))
                    }
                }
            case "events":
                if lowered.hasPrefix("format:") {
                    eventFields = splitFields(String(line.dropFirst(7)))
                    guard eventFields.contains("start"), eventFields.contains("end"), eventFields.contains("text") else {
                        throw ParseError.missingEventsFormat(line: lineNo)
                    }
                    haveEventFormat = true
                } else if lowered.hasPrefix("dialogue:") {
                    guard haveEventFormat else { throw ParseError.dialogueBeforeFormat(line: lineNo) }
                    let (cue, report) = try parseDialogue(String(line.dropFirst(9)), fields: eventFields, line: lineNo, index: cues.count + 1)
                    cues.append(cue)
                    if let report { overrideReports.append(report) }
                } else if lowered.hasPrefix("comment:") {
                    continue
                }
            default:
                continue
            }
        }
        guard sawEvents else { throw ParseError.missingEventsSection }
        return Document(styles: styles, cues: cues, playResX: playResX, playResY: playResY,
                        unsupportedOverrides: overrideReports, skippedStyles: skippedStyles)
    }

    static func infoValue(_ line: String, key: String) -> String? {
        guard line.lowercased().hasPrefix(key.lowercased() + ":") else { return nil }
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    static func splitFields(_ s: String) -> [String] {
        s.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    enum StyleResult {
        case ok(Style)
        case skipped(reason: String)
    }

    static func parseStyle(_ body: String, fields: [String]) -> StyleResult {
        guard !fields.isEmpty else { return .skipped(reason: "no style Format") }
        let values = body.split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.count == fields.count else { return .skipped(reason: "field count") }
        guard let ni = fields.firstIndex(of: "name"),
              let fi = fields.firstIndex(of: "fontname"),
              let si = fields.firstIndex(of: "fontsize"),
              let ci = fields.firstIndex(of: "primarycolour") else { return .skipped(reason: "missing required field") }
        guard let size = Double(values[si]) else { return .skipped(reason: "bad fontsize") }
        guard let argb = parseColour(values[ci]) else { return .skipped(reason: "bad colour") }
        return .ok(Style(name: values[ni], fontName: values[fi], fontSize: size, primaryColourARGB: argb))
    }

    /// "&HAABBGGRR" (8 hex digits) or "&HBBGGRR" (6) -> AARRGGBB.
    static func parseColour(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("&h") else { return nil }
        t = String(t.dropFirst(2))
        // Exactly 6 (&HBBGGRR) or 8 (&HAABBGGRR) hex digits; any other length
        // refuses instead of misdecoding positionally.
        guard t.count == 6 || t.count == 8, t.allSatisfy({ $0.isHexDigit }), let v = UInt32(t, radix: 16) else { return nil }
        let aa: UInt32 = t.count <= 6 ? 0 : (v >> 24) & 0xff
        let bb = (v >> 16) & 0xff
        let gg = (v >> 8) & 0xff
        let rr = v & 0xff
        return (aa << 24) | (rr << 16) | (gg << 8) | bb
    }

    static func parseDialogue(_ body: String, fields: [String], line: Int, index: Int) throws -> (SubtitleCue, OverrideReport?) {
        let parts = body.split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == fields.count else { throw ParseError.badDialogueFieldCount(line: line) }
        func field(_ name: String) -> String { parts[fields.firstIndex(of: name)!] }
        guard let start = parseTimestamp(field("start").trimmingCharacters(in: .whitespaces)) else { throw ParseError.badTimestamp(line: line) }
        guard let end = parseTimestamp(field("end").trimmingCharacters(in: .whitespaces)) else { throw ParseError.badTimestamp(line: line) }
        guard end > start else { throw ParseError.endNotAfterStart(line: line) }
        let rawText = field("text")
        let (cleaned, tags) = cleanText(rawText)
        if cleaned.isEmpty {
            // Distinguish an empty text field from a pure override-only event:
            // the override-only case keeps its tags in the refusal's line
            // context instead of vanishing into a generic missingText.
            if rawText.contains("{") { throw ParseError.overrideOnlyText(line: line) }
            throw ParseError.missingText(line: line)
        }
        // Per-cue style association is preserved, never discarded: it is the
        // link a future renderer needs between cue text and the style table.
        let styleName = fields.contains("style") ? field("style").trimmingCharacters(in: .whitespaces) : nil
        let cue = SubtitleCue(index: index, startSeconds: start, endSeconds: end,
                              lines: cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                              styleName: styleName?.isEmpty == true ? nil : styleName)
        return (cue, tags.isEmpty ? nil : OverrideReport(cueIndex: index, tags: tags))
    }

    /// "H:MM:SS.cc" - hours any non-negative integer, mm/ss two digits < 60,
    /// centiseconds exactly two digits.
    static func parseTimestamp(_ s: String) -> Double? {
        let hms = s.split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 3 else { return nil }
        guard !hms[0].isEmpty, hms[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let hh = Int(hms[0]) else { return nil }
        guard hms[1].count == 2, hms[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let mm = Int(hms[1]), mm >= 0, mm < 60 else { return nil }
        let sc = hms[2].split(separator: ".", omittingEmptySubsequences: false)
        guard sc.count == 2 else { return nil }
        guard sc[0].count == 2, sc[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ss = Int(sc[0]), ss >= 0, ss < 60 else { return nil }
        guard sc[1].count == 2, sc[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let cs = Int(sc[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(cs) / 100
    }

    /// Removes "{...}" override blocks (non-nested, unterminated block drops to
    /// end of text), converts "\N"/"\n" to line breaks and "\h" to NBSP.
    /// Returns the cleaned text plus the sorted unique override tag names found
    /// inside the blocks (reported UNSUPPORTED by the caller; a block with no
    /// backslash tag contributes "block").
    static func cleanText(_ s: String) -> (String, [String]) {
        var out = ""
        var tags = Set<String>()
        var depth = 0
        var blockStart = String.Index?.none
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { if depth == 0 { blockStart = i }; depth += 1; i = s.index(after: i); continue }
            if c == "}", depth > 0 {
                depth -= 1
                if depth == 0, let b = blockStart {
                    let content = s[s.index(after: b)..<i]
                    let found = extractTags(String(content))
                    tags.formUnion(found.isEmpty ? ["block"] : found)
                    blockStart = nil
                }
                i = s.index(after: i); continue
            }
            // A "}" at depth 0 has no matching block: it is ordinary text and
            // is preserved, not silently dropped.
            if depth == 0 {
                if c == "\\" {
                    let n = s.index(after: i)
                    if n < s.endIndex {
                        let d = s[n]
                        if d == "N" || d == "n" { out.append("\n"); i = s.index(after: n); continue }
                        if d == "h" { out.append("\u{00A0}"); i = s.index(after: n); continue }
                    }
                }
                out.append(c)
            }
            i = s.index(after: i)
        }
        if depth > 0, let b = blockStart {
            // Unterminated block: content to end of text is still reported.
            let content = s[s.index(after: b)..<s.endIndex]
            let found = extractTags(String(content))
            tags.formUnion(found.isEmpty ? ["block"] : found)
        }
        return (out.trimmingCharacters(in: .whitespaces), tags.sorted())
    }

    /// Backslash tag names inside one override block, e.g. "\\pos(1,2)\\fad(0,0)"
    /// -> ["\\fad", "\\pos"]. Stops each tag at the first non-letter character.
    static func extractTags(_ block: String) -> [String] {
        var found = Set<String>()
        var i = block.startIndex
        while i < block.endIndex {
            if block[i] == "\\" {
                var j = block.index(after: i)
                var name = "\\"
                while j < block.endIndex, block[j].isLetter {
                    name.append(block[j])
                    j = block.index(after: j)
                }
                if name.count > 1 { found.insert(name) }
                i = j
            } else {
                i = block.index(after: i)
            }
        }
        return found.sorted()
    }
}

```

```swift id=source2
import Foundation

/// One timed subtitle cue over the half-open interval [startSeconds, endSeconds).
/// Format-neutral: produced by the SRT (L5) and ASS (L6) parsers and consumed
/// by the future presenter hook (trunk-owned wiring, block-78 L8 allocation:
/// Sources/GorAVSubtitles is a new path; no trunk files touched here).
public struct SubtitleCue: Equatable, Sendable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let lines: [String]
    /// ASS Dialogue Style association, preserved for the future renderer.
    /// nil for SRT and for ASS events whose Format carries no Style field.
    /// This is an association record, not styling support.
    public let styleName: String?

    public init(index: Int, startSeconds: Double, endSeconds: Double, lines: [String], styleName: String? = nil) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.lines = lines
        self.styleName = styleName
    }

    /// Cue text with original line breaks.
    public var text: String { lines.joined(separator: "\n") }

    /// Membership test on the half-open interval; inverted cues hold nothing.
    public func contains(seconds t: Double) -> Bool {
        t >= startSeconds && t < endSeconds
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[3]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "Sources/GorAVSubtitles/ASSParser.swift",
    "Sources/GorAVSubtitles/SubtitleCue.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor size in [\"nan\",\"inf\",\"-1\",\"0\"] {\n let text=\"[V4+ Styles]\\nFormat: Name, Fontname, Fontsize, PrimaryColour\\nStyle: Default,Arial,\\(size),&H00FFFFFF\\n[Events]\\nFormat: Start, End, Style, Text\\nDialogue: 0:00:00.00,0:00:01.00,Default,x\"\n let d=try ASSParser.parse(text)\n check(d.styles.isEmpty && !d.skippedStyles.isEmpty,\"invalid font size diagnosed\")\n}\nlet good=try ASSParser.parse(\"[V4+ Styles]\\nFormat: Name, Fontname, Fontsize, PrimaryColour\\nStyle: Default,Arial,24,&H00FFFFFF\\n[Events]\\nFormat: Start, End, Style, Text\\nDialogue: 0:00:00.00,0:00:01.00,Default,x\")\ncheck(good.styles.first?.fontSize == 24,\"valid style preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL invalid font size diagnosed
FAIL invalid font size diagnosed
FAIL invalid font size diagnosed
FAIL invalid font size diagnosed
PASS valid style preserved
semantic failures=4



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
