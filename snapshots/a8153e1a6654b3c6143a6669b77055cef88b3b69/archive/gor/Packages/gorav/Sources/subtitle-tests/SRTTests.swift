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
