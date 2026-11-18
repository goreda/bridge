# W-gdb-199c-in2tinct-20 - Bound SRT input before allocation
state: OPEN / unclaimed
lab: in2tinct

## Product change
Add SRTParser.Limits(maxBytes:maxLines:maxLineScalars:maxCues:) with VTT-equivalent defaults and a defaulted limits argument to parse. Enforce bytes before normalization/splitting; enforce other bounds while scanning, with ParseError.inputTooLarge(limit:), tooManyLines(limit:), lineTooLong(line:limit:), and tooManyCues(limit:) cases. Keep existing parse call compatibility, strict timing grammar and whole-document refusal. Supplied test initially fails compilation until this additive API exists; writer must additionally test each limit and exact boundary.

## Grounded gap and boundary
U2 external subtitle import bounded-input prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-20.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_API_MISSING, exit 2; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-20",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SRTParser.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "Add SRTParser.Limits(maxBytes:maxLines:maxLineScalars:maxCues:) with VTT-equivalent defaults and a defaulted limits argument to parse. Enforce bytes before normalization/splitting; enforce other bounds while scanning, with ParseError.inputTooLarge(limit:), tooManyLines(limit:), lineTooLong(line:limit:), and tooManyCues(limit:) cases. Keep existing parse call compatibility, strict timing grammar and whole-document refusal. Supplied test initially fails compilation until this additive API exists; writer must additionally test each limit and exact boundary.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 external subtitle import bounded-input prerequisite",
    "callee": "Sources/GorAVSubtitles/SRTParser.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-20.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-20",
    "paths": [
      "Sources/GorAVSubtitles/SRTParser.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-20.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-20.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-20.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 2,
    "exit_code": 2,
    "ran_at": "2026-11-18T00:13:52.394829+00:00",
    "expected_log_contains": "compile_exit=1",
    "log_block": "actual_run_log",
    "log_sha256": "3677a2bbf5a8370ea75cf1e1eda267be07b203e34ab4c06d57db07f915d4ef3e",
    "last_5_lines": [
      " 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,\"cue budget refused\") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,\"typed cue refusal\") } catch { check(false,\"wrong cue error\") }",
      "   |                                                                                                                                                                                          `- error: type 'SRTParser.ParseError' has no member 'tooManyCues'",
      "10 | print(\"semantic failures=\\(failures)\")",
      "11 | exit(failures == 0 ? 0 : 1)",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SRTParser.swift",
        "block": "source1",
        "sha256": "49ab4d1258dc63529700a6e560ff1cefb6e287f65e267fc3f9befcafb0f5a653",
        "read_only_dependency": false
      },
      {
        "path": "Sources/GorAVSubtitles/SubtitleCue.swift",
        "block": "source2",
        "sha256": "2311ed3052c4a66f2d7942d23624b693faa52dc509354e22fbff148aa3abaa40",
        "read_only_dependency": true
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-20.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-20.json",
        "block": "fixtures2",
        "sha256": "d78f684fd4da292a743e65d3467782f9b47ca8deb6c9a385640a9742d457f0cf"
      }
    ],
    "receipt_sha256": "b202019b851e684ac2dd9ade3e05357109d290d75ecd3cd244d670962fe8cf48"
  },
  "starter_status": "BASELINE_API_MISSING"
}
```

```swift id=source1
import Foundation

/// Strict SubRip (SRT) parser (lane L5, unit u1). Typed refusals on malformed
/// input; no guessing, no partial adoption of a broken block. Spec scope:
/// positive integer index line, "HH:MM:SS,mmm --> HH:MM:SS,mmm" timing line
/// (optional coordinate tail ignored), one or more text lines, blocks split on
/// blank lines (a whitespace-only line counts as blank EVERYWHERE, including
/// inside cue text). Tolerates a UTF-8 BOM and CR/LF/CRLF endings. Inline tags
/// in cue text are kept verbatim; presentation stripping belongs to the
/// renderer.
/// Explicit boundaries (strict by design, documented per independent review):
/// the timing separator must be exactly " --> " (tabs or other spacing refuse);
/// cue indices must be positive integers but monotonic sequence is NOT required
/// (accepted deviation: file order is preserved; playback does not depend on
/// index order).
public enum SRTParser {

    public enum ParseError: Error, Equatable {
        case emptyDocument
        case badIndex(line: Int)
        case badTimingLine(line: Int)
        case badTimestamp(line: Int)
        case endNotAfterStart(line: Int)
        case missingText(line: Int)
    }

    /// Parses whole-document SRT text into cues in file order.
    public static func parse(_ content: String) throws -> [SubtitleCue] {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var cues: [SubtitleCue] = []
        var i = 0
        var sawAnyBlock = false
        while i < lines.count {
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
            guard i < lines.count else { break }
            sawAnyBlock = true
            let indexLine = i + 1 // 1-based for diagnostics
            guard isPositiveInt(lines[i]) else { throw ParseError.badIndex(line: indexLine) }
            let index = Int(lines[i])!
            i += 1
            guard i < lines.count, !lines[i].isEmpty else { throw ParseError.badTimingLine(line: i + 1) }
            let timingLine = i + 1
            let (start, end) = try parseTiming(lines[i], line: timingLine)
            i += 1
            var textLines: [String] = []
            while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[i])
                i += 1
            }
            // missingText points at the line where text was expected (first
            // line after the timing line), not at the timing line itself.
            guard !textLines.isEmpty else { throw ParseError.missingText(line: timingLine + 1) }
            cues.append(SubtitleCue(index: index, startSeconds: start, endSeconds: end, lines: textLines))
        }
        guard sawAnyBlock else { throw ParseError.emptyDocument }
        return cues
    }

    static func isPositiveInt(_ s: String) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0 >= "0" && $0 <= "9" }), let v = Int(s), v > 0 else { return false }
        return true
    }

    static func parseTiming(_ line: String, line number: Int) throws -> (Double, Double) {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { throw ParseError.badTimingLine(line: number) }
        guard let start = parseTimestamp(parts[0]) else { throw ParseError.badTimestamp(line: number) }
        // Optional coordinate tail after the end timestamp (" X1:a X2:b Y1:c Y2:d").
        let endToken = parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let end = parseTimestamp(endToken) else { throw ParseError.badTimestamp(line: number) }
        guard end > start else { throw ParseError.endNotAfterStart(line: number) }
        return (start, end)
    }

    /// "HH:MM:SS,mmm" - hours any non-negative integer, mm/ss two digits < 60,
    /// milliseconds exactly three digits. Comma is the only accepted separator.
    static func parseTimestamp(_ s: String) -> Double? {
        let hms = s.split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 3 else { return nil }
        guard !hms[0].isEmpty, hms[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let hh = Int(hms[0]) else { return nil }
        guard hms[1].count == 2, hms[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let mm = Int(hms[1]), mm >= 0, mm < 60 else { return nil }
        let sm = hms[2].split(separator: ",", omittingEmptySubsequences: false)
        guard sm.count == 2 else { return nil }
        guard sm[0].count == 2, sm[0].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ss = Int(sm[0]), ss >= 0, ss < 60 else { return nil }
        guard sm[1].count == 3, sm[1].allSatisfy({ $0 >= "0" && $0 <= "9" }), let ms = Int(sm[1]) else { return nil }
        return Double(hh) * 3600 + Double(mm) * 60 + Double(ss) + Double(ms) / 1000
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
    "Sources/GorAVSubtitles/SRTParser.swift",
    "Sources/GorAVSubtitles/SubtitleCue.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet text=\"1\\n00:00:00,000 --> 00:00:01,000\\nx\"\nlet parsed = try SRTParser.parse(text)\ncheck(parsed.count == 1,\"existing API retained\")\ndo { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,\"byte budget refused\") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,\"typed byte refusal\") } catch { check(false,\"wrong byte error\") }\ndo { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,\"cue budget refused\") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,\"typed cue refusal\") } catch { check(false,\"wrong cue error\") }\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=1

/tmp/tmpg6jkbs1y/main.swift:8:53: error: extra argument 'limits' in call
 6 | let parsed = try SRTParser.parse(text)
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
   |                                                     `- error: extra argument 'limits' in call
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
10 | print("semantic failures=\(failures)")

/tmp/tmpg6jkbs1y/main.swift:8:53: error: type 'SRTParser' has no member 'Limits'
 6 | let parsed = try SRTParser.parse(text)
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
   |                                                     `- error: type 'SRTParser' has no member 'Limits'
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
10 | print("semantic failures=\(failures)")

/tmp/tmpg6jkbs1y/main.swift:8:185: error: type 'SRTParser.ParseError' has no member 'inputTooLarge'
 6 | let parsed = try SRTParser.parse(text)
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
   |                                                                                                                                                                                         `- error: type 'SRTParser.ParseError' has no member 'inputTooLarge'
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
10 | print("semantic failures=\(failures)")

/tmp/tmpg6jkbs1y/main.swift:9:53: error: extra argument 'limits' in call
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
   |                                                     `- error: extra argument 'limits' in call
10 | print("semantic failures=\(failures)")
11 | exit(failures == 0 ? 0 : 1)

/tmp/tmpg6jkbs1y/main.swift:9:53: error: type 'SRTParser' has no member 'Limits'
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
   |                                                     `- error: type 'SRTParser' has no member 'Limits'
10 | print("semantic failures=\(failures)")
11 | exit(failures == 0 ? 0 : 1)

/tmp/tmpg6jkbs1y/main.swift:9:186: error: type 'SRTParser.ParseError' has no member 'tooManyCues'
 7 | check(parsed.count == 1,"existing API retained")
 8 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1,maxLines: 100,maxLineScalars: 100,maxCues: 10)); check(false,"byte budget refused") } catch SRTParser.ParseError.inputTooLarge(let limit) { check(limit == 1,"typed byte refusal") } catch { check(false,"wrong byte error") }
 9 | do { _ = try SRTParser.parse(text,limits: SRTParser.Limits(maxBytes: 1024,maxLines: 100,maxLineScalars: 100,maxCues: 0)); check(false,"cue budget refused") } catch SRTParser.ParseError.tooManyCues(let limit) { check(limit == 0,"typed cue refusal") } catch { check(false,"wrong cue error") }
   |                                                                                                                                                                                          `- error: type 'SRTParser.ParseError' has no member 'tooManyCues'
10 | print("semantic failures=\(failures)")
11 | exit(failures == 0 ? 0 : 1)


```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
