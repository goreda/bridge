# W-gdb-058 SRT parser contract witness (product suite)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-058

```packet-json
{
  "packet_id": "W-gdb-058",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/subtitle-tests/SRTTests.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "product test target subtitle-srt-tests",
    "types": "see excerpt",
    "ownership_lifetime": "product sources at the pinned sha",
    "caller": "lab run-proof gate",
    "callee": "subtitle-srt-tests (product target on main)"
  },
  "test": {
    "command": "swift run subtitle-srt-tests",
    "expected": "exit 0; final line 'ALL_CHECKS_PASS'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/subtitle-tests/SRTTests.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/subtitle-tests/SRTTests.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run subtitle-srt-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:58:43.174636+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL_CHECKS_PASS",
    "inline_files": [
      {
        "path": "Sources/subtitle-tests/SRTTests.swift",
        "block": "rf1",
        "sha256": "1ee9b6b646fdcf5f402fd289319a90b990af68bbb7919770ac0aabf311217de1"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "6285c56fcd6a8eafdf09095ebd24877794a0819da8ec4e85f1d684d3cb3d9376",
    "last_5_lines": [
      "[21/24] Wrapping AST for subtitle-srt-tests for debugging",
      "[22/24] Write Objects.LinkFileList",
      "[23/24] Linking subtitle-srt-tests",
      "Build complete! (2.84s)",
      "ALL_CHECKS_PASS"
    ],
    "receipt_sha256": "3695aac9e818803e5fbcf2a95c3e5b3999d53675cfd70fe49ce9629b997670a3"
  }
}
```

## problem (what fails for the user)
a malformed SRT cue that parses silently shows the owner broken subtitles; the product contract suite keeps typed refusals honest

## reproducer
- repo: goreda/gorav @ 91a359f7b38cc0e6c4974661d85f389ef6041b1f (branch main).
- real source: Sources/subtitle-tests/SRTTests.swift (product suite inlined below).
- real test command: swift run subtitle-srt-tests (product's own target on main, Linux).

## expected behaviour
exit 0 with the product suite's summary line 'ALL_CHECKS_PASS'; any regression fails with its row id.

```text id=rf1
import Foundation
import GorAVSubtitles

// L5-u1 SRT parser contract tests (Linux model tests; no FFmpeg, no native
// display). 4 positive vectors + 7 negative vectors, typed refusals only.
// Convention: ALL_CHECKS_PASS on success, exit 0/1 like the trunk test targets.
@main
struct SRTTests {
    static var failures = 0
    static func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
    static func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

    static func expectThrows(_ m: String, _ want: SRTParser.ParseError, _ body: String) {
        do {
            _ = try SRTParser.parse(body)
            expect(false, "\(m): malformed input accepted")
        } catch let e as SRTParser.ParseError {
            expect(e == want, "\(m): got \(e), want \(want)")
        } catch {
            expect(false, "\(m): foreign error \(error)")
        }
    }

    static func main() {
        // p1: two LF cues, exact timing and text.
        do {
            let cues = try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,500\nHello world\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond line\n")
            expect(cues.count == 2, "p1: cue count \(cues.count)")
            if cues.count == 2 {
                expect(cues[0].index == 1 && cues[0].startSeconds == 1.0 && cues[0].endSeconds == 2.5, "p1: cue0 timing")
                expect(cues[0].lines == ["Hello world"] && cues[0].text == "Hello world", "p1: cue0 text")
                expect(cues[1].index == 2 && cues[1].startSeconds == 3.0 && cues[1].endSeconds == 4.0, "p1: cue1 timing")
            }
        } catch { expect(false, "p1: threw \(error)") }

        // p2: BOM + CRLF, hours > 0.
        do {
            let cues = try SRTParser.parse("\u{FEFF}1\r\n00:10:00,100 --> 01:00:00,000\r\nTitle\r\n")
            expect(cues.count == 1, "p2: cue count")
            if let c = cues.first {
                expect(c.startSeconds == 600.1 && c.endSeconds == 3600.0, "p2: timing \(c.startSeconds)-\(c.endSeconds)")
                expect(c.text == "Title", "p2: text")
            }
        } catch { expect(false, "p2: threw \(error)") }

        // p3: coordinate tail after the end timestamp is ignored.
        do {
            let cues = try SRTParser.parse("3\n00:00:05,000 --> 00:00:06,500 X1:100 X2:200 Y1:10 Y2:20\nPos\n")
            expect(cues.count == 1 && cues[0].endSeconds == 6.5, "p3: coordinate tail")
        } catch { expect(false, "p3: threw \(error)") }

        // p4: multiline cue; inline tags kept verbatim; half-open contains().
        do {
            let cues = try SRTParser.parse("7\n00:00:07,250 --> 00:00:09,000\n<i>one</i>\ntwo & three\n")
            expect(cues.count == 1, "p4: cue count")
            if let c = cues.first {
                expect(c.lines == ["<i>one</i>", "two & three"], "p4: lines \(c.lines)")
                expect(c.text == "<i>one</i>\ntwo & three", "p4: joined text")
                expect(c.startSeconds == 7.25, "p4: start")
                expect(c.contains(seconds: 7.25), "p4: contains start (closed)")
                expect(!c.contains(seconds: 9.0), "p4: excludes end (open)")
                expect(c.contains(seconds: 8.999), "p4: contains interior")
                expect(!c.contains(seconds: 7.249), "p4: excludes before")
            }
        } catch { expect(false, "p4: threw \(error)") }

        // n1: single-dash arrow.
        expectThrows("n1", .badTimingLine(line: 2), "1\n00:00:01,000 -> 00:00:02,000\ntext\n")
        // n2: zero-length cue (end == start).
        expectThrows("n2", .endNotAfterStart(line: 2), "1\n00:00:02,000 --> 00:00:02,000\ntext\n")
        // n3: dot millisecond separator (spec is comma).
        expectThrows("n3", .badTimestamp(line: 2), "1\n00:00:01.000 --> 00:00:02,000\ntext\n")
        // n4: non-numeric index.
        expectThrows("n4", .badIndex(line: 1), "x\n00:00:01,000 --> 00:00:02,000\ntext\n")
        // n5: cue without text.
        expectThrows("n5", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n")
        // n8: whitespace-only text line is blank everywhere (symmetric strictness).
        expectThrows("n8", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n   \n")
        // n6: empty document.
        expectThrows("n6", .emptyDocument, "  \n\n")
        // n7: text where the timing line must be.
        expectThrows("n7", .badTimingLine(line: 2), "1\ntext\n")

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=source1
import Foundation
import GorAVSubtitles

// L5-u1 SRT parser contract tests (Linux model tests; no FFmpeg, no native
// display). 4 positive vectors + 7 negative vectors, typed refusals only.
// Convention: ALL_CHECKS_PASS on success, exit 0/1 like the trunk test targets.
@main
struct SRTTests {
    static var failures = 0
    static func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
    static func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

    static func expectThrows(_ m: String, _ want: SRTParser.ParseError, _ body: String) {
        do {
            _ = try SRTParser.parse(body)
            expect(false, "\(m): malformed input accepted")
        } catch let e as SRTParser.ParseError {
            expect(e == want, "\(m): got \(e), want \(want)")
        } catch {
            expect(false, "\(m): foreign error \(error)")
        }
    }

    static func main() {
        // p1: two LF cues, exact timing and text.
        do {
            let cues = try SRTParser.parse("1\n00:00:01,000 --> 00:00:02,500\nHello world\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond line\n")
            expect(cues.count == 2, "p1: cue count \(cues.count)")
            if cues.count == 2 {
                expect(cues[0].index == 1 && cues[0].startSeconds == 1.0 && cues[0].endSeconds == 2.5, "p1: cue0 timing")
                expect(cues[0].lines == ["Hello world"] && cues[0].text == "Hello world", "p1: cue0 text")
                expect(cues[1].index == 2 && cues[1].startSeconds == 3.0 && cues[1].endSeconds == 4.0, "p1: cue1 timing")
            }
        } catch { expect(false, "p1: threw \(error)") }

        // p2: BOM + CRLF, hours > 0.
        do {
            let cues = try SRTParser.parse("\u{FEFF}1\r\n00:10:00,100 --> 01:00:00,000\r\nTitle\r\n")
            expect(cues.count == 1, "p2: cue count")
            if let c = cues.first {
                expect(c.startSeconds == 600.1 && c.endSeconds == 3600.0, "p2: timing \(c.startSeconds)-\(c.endSeconds)")
                expect(c.text == "Title", "p2: text")
            }
        } catch { expect(false, "p2: threw \(error)") }

        // p3: coordinate tail after the end timestamp is ignored.
        do {
            let cues = try SRTParser.parse("3\n00:00:05,000 --> 00:00:06,500 X1:100 X2:200 Y1:10 Y2:20\nPos\n")
            expect(cues.count == 1 && cues[0].endSeconds == 6.5, "p3: coordinate tail")
        } catch { expect(false, "p3: threw \(error)") }

        // p4: multiline cue; inline tags kept verbatim; half-open contains().
        do {
            let cues = try SRTParser.parse("7\n00:00:07,250 --> 00:00:09,000\n<i>one</i>\ntwo & three\n")
            expect(cues.count == 1, "p4: cue count")
            if let c = cues.first {
                expect(c.lines == ["<i>one</i>", "two & three"], "p4: lines \(c.lines)")
                expect(c.text == "<i>one</i>\ntwo & three", "p4: joined text")
                expect(c.startSeconds == 7.25, "p4: start")
                expect(c.contains(seconds: 7.25), "p4: contains start (closed)")
                expect(!c.contains(seconds: 9.0), "p4: excludes end (open)")
                expect(c.contains(seconds: 8.999), "p4: contains interior")
                expect(!c.contains(seconds: 7.249), "p4: excludes before")
            }
        } catch { expect(false, "p4: threw \(error)") }

        // n1: single-dash arrow.
        expectThrows("n1", .badTimingLine(line: 2), "1\n00:00:01,000 -> 00:00:02,000\ntext\n")
        // n2: zero-length cue (end == start).
        expectThrows("n2", .endNotAfterStart(line: 2), "1\n00:00:02,000 --> 00:00:02,000\ntext\n")
        // n3: dot millisecond separator (spec is comma).
        expectThrows("n3", .badTimestamp(line: 2), "1\n00:00:01.000 --> 00:00:02,000\ntext\n")
        // n4: non-numeric index.
        expectThrows("n4", .badIndex(line: 1), "x\n00:00:01,000 --> 00:00:02,000\ntext\n")
        // n5: cue without text.
        expectThrows("n5", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n")
        // n8: whitespace-only text line is blank everywhere (symmetric strictness).
        expectThrows("n8", .missingText(line: 3), "1\n00:00:01,000 --> 00:00:02,000\n   \n")
        // n6: empty document.
        expectThrows("n6", .emptyDocument, "  \n\n")
        // n7: text where the timing line must be.
        expectThrows("n7", .badTimingLine(line: 2), "1\ntext\n")

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}

```

```text id=fixtures1
fixtures are embedded in the product suite (inlined above).
```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-1_0f29nk/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-1_0f29nk/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/7] Write sources
[2/7] Write swift-version--9C6B84B6E025C5B.txt
[4/14] Emitting module GorAVSubtitles
[5/20] Compiling GorAVSubtitles SubtitleCueOutput.swift
[6/20] Compiling GorAVSubtitles SubtitlePlan.swift
[7/20] Compiling GorAVSubtitles SubtitleSchedule.swift
[8/20] Compiling GorAVSubtitles SubtitleSidecarSession.swift
[9/20] Compiling GorAVSubtitles SubtitleTrack.swift
[10/20] Compiling GorAVSubtitles VTTParser.swift
[11/20] Compiling GorAVSubtitles ASSParser.swift
[12/20] Compiling GorAVSubtitles SRTParser.swift
[13/20] Compiling GorAVSubtitles SubtitleAutoLoad.swift
[14/20] Compiling GorAVSubtitles SubtitleController.swift
[15/20] Compiling GorAVSubtitles SubtitleCue.swift
[16/20] Compiling GorAVSubtitles SubtitleCueDelivery.swift
[17/21] Wrapping AST for GorAVSubtitles for debugging
[19/23] Emitting module subtitle_srt_tests
[20/23] Compiling subtitle_srt_tests SRTTests.swift
[21/24] Wrapping AST for subtitle-srt-tests for debugging
[22/24] Write Objects.LinkFileList
[23/24] Linking subtitle-srt-tests
Build complete! (2.84s)
ALL_CHECKS_PASS
```
