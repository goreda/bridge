import Foundation
import GorAVSubtitles

// Standalone test runner for SubtitleTrack + SubtitleSchedule (lanes L5/L6 u2).
// Self-contained: fixtures are written to a temp directory, no external corpus
// needed. Prints ALL_CHECKS_PASS or FAILURES=<n>; exit 0/1 (CoexistTest
// convention). Run as a SEPARATE consumer module (SRTTests/ASSTests
// convention): build GorAVSubtitles with swiftc -emit-module -emit-library
// -module-name GorAVSubtitles, then compile this file against it with -I/-L.

@main
struct SubtitleTrackTests {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String) {
        if cond { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
    }
    static func main() {

        let tmp = NSTemporaryDirectory() + "tracktests-\(ProcessInfo.processInfo.globallyUniqueString)"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)

        let srtText = "1\n00:00:01,000 --> 00:00:03,000\nfirst\n\n2\n00:00:04,000 --> 00:00:06,000\nsecond\n"
        let assText = """
        [Script Info]
        Title: t
        ScriptType: v4.00+
        PlayResX: 640
        PlayResY: 360

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour
        Style: Default,Arial,28,&H00FFFFFF

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\b1}first\\Nsecond
        """

        let srtPath = tmp + "/a.srt"
        let assPath = tmp + "/b.ass"
        let badPath = tmp + "/c.txt"
        try? srtText.write(toFile: srtPath, atomically: true, encoding: .utf8)
        try? assText.write(toFile: assPath, atomically: true, encoding: .utf8)
        try? "x".write(toFile: badPath, atomically: true, encoding: .utf8)

        // 1: srt sidecar loads
        if let t = try? SubtitleTrack.load(path: srtPath) {
            check(t.format == "srt" && t.cues.count == 2, "load .srt -> 2 cues")
            check(t.playResX == nil && t.playResY == nil, "srt load carries no PlayRes")
            check(t.cues[0].startSeconds == 1 && t.cues[1].startSeconds == 4, "srt cue times")
        } else { check(false, "load .srt -> 2 cues"); check(false, "srt load carries no PlayRes"); check(false, "srt cue times") }

        // 2: ass sidecar loads with styles
        if let t = try? SubtitleTrack.load(path: assPath) {
            check(t.format == "ass" && t.cues.count == 1 && t.styles.count == 1, "load .ass -> 1 cue + 1 style")
            check(t.playResX == 640 && t.playResY == 360, "ass load carries PlayRes through loader")
            check(t.cues[0].lines == ["first", "second"], "ass \\N -> break")
            check(t.unsupportedOverrides == [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\b"])],
                  "ass override surfaced UNSUPPORTED")
        } else { check(false, "load .ass -> 1 cue + 1 style"); check(false, "ass load carries PlayRes through loader"); check(false, "ass \\N -> break") }

        // 3: unknown extension -> typed refusal
        do {
            _ = try SubtitleTrack.load(path: badPath)
            check(false, "unknown ext refused")
        } catch SubtitleTrack.LoadError.unknownFormat { check(true, "unknown ext refused") } catch { check(false, "unknown ext refused") }

        // 4: missing file -> typed refusal
        do {
            _ = try SubtitleTrack.load(path: tmp + "/missing.srt")
            check(false, "missing file refused")
        } catch SubtitleTrack.LoadError.unreadable { check(true, "missing file refused") } catch { check(false, "missing file refused") }

        // 5: clean schedule has no issues; activeCue edges
        let cues = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"]),
                    SubtitleCue(index: 2, startSeconds: 4, endSeconds: 6, lines: ["b"])]
        let sched = SubtitleSchedule(cues: cues)
        check(sched.issues.isEmpty, "clean schedule no issues")
        check(sched.activeCue(at: 0.5) == nil, "before first cue -> nil")
        check(sched.activeCue(at: 1) != nil && sched.activeCue(at: 2.999) != nil, "inside first cue")
        check(sched.activeCue(at: 3) == nil, "end is exclusive")
        check(sched.activeCue(at: 3.5) == nil, "gap between cues -> nil")
        check(sched.activeCue(at: 5)?.index == 2, "inside second cue")
        check(sched.activeCue(at: 6.1) == nil, "after last cue -> nil")

        // 6: overlap + out-of-order detected, not repaired
        let messy = [SubtitleCue(index: 1, startSeconds: 5, endSeconds: 7, lines: ["x"]),
                     SubtitleCue(index: 2, startSeconds: 2, endSeconds: 4, lines: ["y"]),
                     SubtitleCue(index: 3, startSeconds: 6, endSeconds: 8, lines: ["z"])]
        let messySched = SubtitleSchedule(cues: messy)
        check(messySched.issues.contains(.outOfOrder(index: 2)), "out-of-order flagged")
        check(messySched.issues.contains(.overlap(index: 3, previous: 1)), "overlap flagged (non-adjacent earlier cue)")

        // 7: overlapping lookup resolves to latest-starting cue
        let over = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 5, lines: ["a"]),
                    SubtitleCue(index: 2, startSeconds: 3, endSeconds: 6, lines: ["b"])]
        check(SubtitleSchedule(cues: over).activeCue(at: 4)?.index == 2, "overlap -> latest-starting cue wins")

        // 8: UNORDERED input - latest-starting policy holds regardless of file order
        let unordered = [SubtitleCue(index: 1, startSeconds: 3, endSeconds: 6, lines: ["late-start"]),
                         SubtitleCue(index: 2, startSeconds: 1, endSeconds: 5, lines: ["early-start"])]
        check(SubtitleSchedule(cues: unordered).activeCue(at: 4)?.index == 1, "unordered input: latest-starting wins")

        // 9: non-adjacent overlap detected (cue 3 overlaps cue 1 across cue 2)
        let nonAdj = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 8, lines: ["a"]),
                      SubtitleCue(index: 2, startSeconds: 2, endSeconds: 3, lines: ["b"]),
                      SubtitleCue(index: 3, startSeconds: 4, endSeconds: 5, lines: ["c"])]
        let nonAdjIssues = SubtitleSchedule(cues: nonAdj).issues
        check(nonAdjIssues.contains(.overlap(index: 3, previous: 1)), "non-adjacent overlap flagged")
        check(nonAdjIssues.contains(.overlap(index: 2, previous: 1)), "adjacent overlap still flagged")

        // 10: malformed style surfaces through the LOADER, not only the parser
        let badStyleAss = tmp + "/badstyle.ass"
        try? "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour\nStyle: Bad,Arial,20,&H12345\n[Events]\nFormat: Layer, Start, End, Text\nDialogue: 0,0:00:01.00,0:00:02.00,x\n".write(toFile: badStyleAss, atomically: true, encoding: .utf8)
        if let t = try? SubtitleTrack.load(path: badStyleAss) {
            check(t.skippedStyles == [ASSParser.SkippedStyle(line: 3, reason: "bad colour")],
                  "loader carries skippedStyles \(t.skippedStyles)")
            check(t.styles.isEmpty, "loader: bad style not adopted")
        } else { check(false, "loader carries skippedStyles"); check(false, "loader: bad style not adopted") }

        try? FileManager.default.removeItem(atPath: tmp)

        if failures == 0 { print("ALL_CHECKS_PASS") } else { print("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}
