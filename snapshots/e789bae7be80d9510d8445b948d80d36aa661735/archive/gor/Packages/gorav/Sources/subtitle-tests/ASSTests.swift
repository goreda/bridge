import Foundation
import GorAVSubtitles

// L6-u1 ASS parser contract tests (Linux model tests; no FFmpeg, no native
// display). 1 positive document (8 assertions) + 6 negative vectors, typed
// refusals only. Convention: ALL_CHECKS_PASS on success, exit 0/1.
@main
struct ASSTests {
    static var failures = 0
    static func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
    static func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

    static func expectThrows(_ m: String, _ want: ASSParser.ParseError, _ body: String) {
        do {
            _ = try ASSParser.parse(body)
            expect(false, "\(m): malformed input accepted")
        } catch let e as ASSParser.ParseError {
            expect(e == want, "\(m): got \(e), want \(want)")
        } catch {
            expect(false, "\(m): foreign error \(error)")
        }
    }

    static let sample = """
    [Script Info]
    Title: sample
    PlayResX: 384
    PlayResY: 288

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour
    Style: Default,Arial,20,&H00FFFFFF

    [Events]
    Format: Layer, Start, End, Style, Text
    Dialogue: 0,0:00:01.00,0:00:02.50,Default,Hello, world
    Comment: 0,0:00:00.00,0:00:00.10,Default,ignored
    Dialogue: 0,0:00:03.00,0:00:04.00,Default,{\\i1}Styled\\Nline2
    """

    static func main() {
        // p1: minimal document - style table, PlayRes, dialogue cues, comment skipped.
        do {
            let doc = try ASSParser.parse(sample)
            expect(doc.playResX == 384 && doc.playResY == 288, "p1: PlayRes")
            expect(doc.styles.count == 1, "p1: style count \(doc.styles.count)")
            if let s = doc.styles.first {
                expect(s.name == "Default" && s.fontName == "Arial" && s.fontSize == 20, "p1: style fields")
                expect(s.primaryColourARGB == 0x00FFFFFF, "p1: colour decode \(String(s.primaryColourARGB, radix: 16))")
            }
            expect(doc.cues.count == 2, "p1: cue count \(doc.cues.count) (comment must be skipped)")
            if doc.cues.count == 2 {
                let c0 = doc.cues[0]
                expect(c0.index == 1 && c0.startSeconds == 1.0 && c0.endSeconds == 2.5, "p1: cue0 timing")
                expect(c0.text == "Hello, world", "p1: cue0 text [\(c0.text)]")
                let c1 = doc.cues[1]
                expect(c1.index == 2 && c1.startSeconds == 3.0 && c1.endSeconds == 4.0, "p1: cue1 timing")
                expect(c0.styleName == "Default" && c1.styleName == "Default", "p1: style association preserved \(c0.styleName ?? "nil")")
                expect(c1.lines == ["Styled", "line2"], "p1: override strip + \\N split \(c1.lines)")
                expect(doc.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 2, tags: ["\\i"])],
                       "p1: override reported UNSUPPORTED \(doc.unsupportedOverrides)")
            }
        } catch { expect(false, "p1: threw \(error)") }

        // p1b: asymmetric colour vector - a BGR/RGB swap bug cannot pass.
        do {
            let d = try ASSParser.parse("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Asym,Arial,20,&H80112233\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n")
            expect(d.styles.first?.primaryColourARGB == 0x80332211, "p1b: &H80112233 -> 80332211 got \(String(d.styles.first?.primaryColourARGB ?? 0, radix: 16))")
        } catch { expect(false, "p1b: threw \(error)") }

        // p1c: invalid colour length (5 hex digits) refuses - style skipped, no positional misdecode.
        do {
            let d = try ASSParser.parse("[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Bad,Arial,20,&H12345\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n")
            expect(d.styles.isEmpty, "p1c: 5-hex colour refused (style skipped)")
            expect(d.skippedStyles == [ASSParser.SkippedStyle(line: 3, reason: "bad colour")],
                   "p1c: skip is caller-visible \(d.skippedStyles)")
        } catch { expect(false, "p1c: threw \(error)") }

        // p1d: stray "}" outside any block is preserved as text.
        do {
            let d = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,a}b\n")
            expect(d.cues.first?.text == "a}b", "p1d: stray } preserved got [\(d.cues.first?.text ?? "")]")
        } catch { expect(false, "p1d: threw \(error)") }

        // p2: a document with no override blocks reports none.
        do {
            let clean = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,plain\n")
            expect(clean.unsupportedOverrides.isEmpty, "p2: no overrides -> empty report")
            expect(clean.cues.count == 1, "p2: plain cue parsed")
        } catch { expect(false, "p2: threw \(error)") }

        // p3: unterminated override block still reported UNSUPPORTED.
        do {
            let d = try ASSParser.parse("[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,tail {\\pos(3,4)\n")
            expect(d.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\pos"])],
                   "p3: unterminated block reported \(d.unsupportedOverrides)")
        } catch { expect(false, "p3: threw \(error)") }

        // n1: Dialogue before any Format in [Events].
        expectThrows("n1", .dialogueBeforeFormat(line: 2), "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,x\n")
        // n2: no [Events] section at all.
        expectThrows("n2", .missingEventsSection, "[Script Info]\nTitle: x\n")
        // n3: seconds out of range.
        expectThrows("n3", .badTimestamp(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:61.00,0:00:02.00,x\n")
        // n4: end before start.
        expectThrows("n4", .endNotAfterStart(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:02.00,0:00:01.00,x\n")
        // n5: fewer fields than the Format declares.
        expectThrows("n5", .badDialogueFieldCount(line: 3), "[Events]\nFormat: Layer, Start, End, Style, Text\nDialogue: 0,0:00:01.00\n")
        // n7: pure override-only event -> explicit typed refusal (evidence kept).
        expectThrows("n7", .overrideOnlyText(line: 3), "[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,{\\pos(10,10)}\n")
        // n6: empty text field.
        expectThrows("n6", .missingText(line: 3), "[Events]\nFormat: Layer, Start, End, Style, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,\n")

        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}
