import Foundation
import GorAVSubtitles

// Standalone test runner for the SubtitlePlan timed-plan API IMPLEMENTATION (u8r2,
// lanes L5/L6). Q1-Q5 engineering decisions LANDED per gdb's 2026-11-01
// decision as relayed via coordination (peer-attributed, unverified by us
// against an authenticated gdb record); tie rule peer-confirmed. These tests
// lock the decided behavior: content identity vs producer generation,
// findings in the identity, A->B->A regression, exhaustion refusal, typed
// answers, Q4 suppression/tie/boundary semantics, Q5 defaults, Q2 echo.
// ALL_CHECKS_PASS / FAILURES=n, exit 0/1. Run as a SEPARATE consumer module
// (SRTTests/ASSTests convention): build GorAVSubtitles with
// swiftc -emit-module -emit-library -module-name GorAVSubtitles, then compile
// this file against it with -I/-L.

@main
struct SubtitlePlanTests {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String) {
        if cond { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
    }

    static func main() {
        let cues = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Default"),
                    SubtitleCue(index: 2, startSeconds: 4, endSeconds: 6, lines: ["b"], styleName: "Default")]
        let styles = [ASSParser.Style(name: "Default", fontName: "Arial", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        let noFindings: ([ASSParser.OverrideReport], [ASSParser.SkippedStyle]) = ([], [])

        // 1: contentID deterministic
        let c1 = SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                               playResX: nil, playResY: nil, unsupportedOverrides: noFindings.0, skippedStyles: noFindings.1)
        let c2 = SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                               playResX: nil, playResY: nil, unsupportedOverrides: noFindings.0, skippedStyles: noFindings.1)
        check(c1 == c2, "contentID deterministic")

        // 2: contentID changes with content (text, timing, style association, style table)
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a2"], styleName: "Default"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on text change")
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3.5, lines: ["a"], styleName: "Default"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on timing change")
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Other"), cues[1]], styles: styles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on style association change")
        check(SubtitlePlanContentID.compute(cues: cues, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []) != c1,
              "contentID changes on style table change")

        // 3: findings are part of the identity (gdb note F2)
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                            playResX: nil, playResY: nil, unsupportedOverrides: [ASSParser.OverrideReport(cueIndex: 1, tags: ["\\b"])],
                                            skippedStyles: []) != c1,
              "contentID changes on override findings")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles,
                                            playResX: nil, playResY: nil, unsupportedOverrides: [],
                                            skippedStyles: [ASSParser.SkippedStyle(line: 3, reason: "bad colour")]) != c1,
              "contentID changes on skipped-style findings")

        // 3b: review note S1 - serialization is unambiguous (length-prefixed):
        // field-boundary ambiguity and embedded NULs must change the identity
        let cueSplit1 = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["ab"], styleName: "D")]
        let cueSplit2 = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a", "b"], styleName: "D")]
        check(SubtitlePlanContentID.compute(cues: cueSplit1, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueSplit2, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "line-count boundary unambiguous (ab vs a|b)")
        let cueNul = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a\u{0}b"], styleName: "D")]
        check(SubtitlePlanContentID.compute(cues: cueNul, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueSplit1, styles: [], playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "embedded NUL changes identity")
        let styleShift1 = [ASSParser.Style(name: "ab", fontName: "c", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        let styleShift2 = [ASSParser.Style(name: "a", fontName: "bc", fontSize: 20, primaryColourARGB: 0x00FFFFFF)]
        check(SubtitlePlanContentID.compute(cues: [], styles: styleShift1, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: [], styles: styleShift2, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "style field boundary unambiguous (ab+c vs a+bc)")

        // 3c: review note S2 - fontSize precision is exact, not rounded
        let styleTiny1 = [ASSParser.Style(name: "D", fontName: "A", fontSize: 20.0, primaryColourARGB: 0x00FFFFFF)]
        let styleTiny2 = [ASSParser.Style(name: "D", fontName: "A", fontSize: 20.0 + 1e-9, primaryColourARGB: 0x00FFFFFF)]
        check(SubtitlePlanContentID.compute(cues: [], styles: styleTiny1, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: [], styles: styleTiny2, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "fontSize 1e-9 difference changes identity (no rounding collapse)")

        // 3d: gdb review P5-1 - PlayRes presence and values are identity
        let base = SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 640, playResY: 360,
                                                 unsupportedOverrides: [], skippedStyles: [])
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: nil, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes presence changes identity")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 641, playResY: 360,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes value change changes identity")
        check(SubtitlePlanContentID.compute(cues: cues, styles: styles, playResX: 640, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: []) != base,
              "PlayRes per-axis presence changes identity")

        // 3e: gdb review P5-2 - nil vs empty styleName are distinct identities
        let cueNilStyle = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: nil)]
        let cueEmptyStyle = [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "")]
        check(SubtitlePlanContentID.compute(cues: cueNilStyle, styles: [], playResX: nil, playResY: nil,
                                            unsupportedOverrides: [], skippedStyles: [])
              != SubtitlePlanContentID.compute(cues: cueEmptyStyle, styles: [], playResX: nil, playResY: nil,
                                               unsupportedOverrides: [], skippedStyles: []),
              "nil vs empty styleName are distinct identities")

        // 4: A->B->A (gdb note F1): contentID repeats, generation does not
        let trackA = SubtitleTrack.Track(format: "ass", cues: cues, styles: styles,
                                         unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let trackB = SubtitleTrack.Track(format: "ass", cues: [SubtitleCue(index: 1, startSeconds: 1, endSeconds: 3, lines: ["a2"], styleName: "Default"), cues[1]],
                                         styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let producer = SubtitlePlanProducer(track: trackA)
        guard let planA1 = try? producer.makePlan(),
              let _ = try? producer.updateTrack(trackB),
              let planA2 = try? producer.updateTrack(trackA) else {
            check(false, "A->B->A plans issued"); return
        }
        check(planA1.planRevision.contentID == planA2.planRevision.contentID,
              "A->B->A: contentID returns (identity, not freshness)")
        check(planA1.planRevision.generation < planA2.planRevision.generation,
              "A->B->A: generation advanced")
        check(planA1.planRevision != planA2.planRevision,
              "A->B->A: full revision pair never reused")

        // 5: generation strictly monotonic across issues
        check(planA2.planRevision.generation == planA1.planRevision.generation + 2,
              "generation strictly monotonic")

        // 6: exhaustion is a typed refusal, never a wrap or reuse
        let trackSrt = SubtitleTrack.Track(format: "srt", cues: cues, styles: [],
                                           unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let hot = SubtitlePlanProducer(track: trackSrt, startingGeneration: UInt64.max - 1)
        guard let lastOK = try? hot.makePlan() else { check(false, "last generation issuable"); return }
        check(lastOK.planRevision.generation == UInt64.max, "generation reaches max")
        do {
            _ = try hot.makePlan()
            check(false, "exhaustion throws typed refusal")
        } catch SubtitlePlanProducer.RevisionError.generationExhausted {
            check(true, "exhaustion throws typed refusal")
        } catch { check(false, "exhaustion throws typed refusal") }
        check(hot.lastGeneration == UInt64.max, "no wrap: counter stays at max after refusal")

        // 7: plan carries PlayRes through the track; srt plan has none
        check(planA1.playResX == 640 && planA1.playResY == 360, "plan carries PlayRes")
        let srtProducer = SubtitlePlanProducer(track: trackSrt)
        guard let srtPlan = try? srtProducer.makePlan() else { check(false, "srt plan issued"); return }
        check(srtPlan.playResX == nil, "srt plan has no PlayRes")

        // 8: plan revision contentID matches compute for its content
        // (trackA carries PlayRes 640/360, so the identity includes it)
        check(planA1.planRevision.contentID == SubtitlePlanContentID.compute(
            cues: cues, styles: styles, playResX: 640, playResY: 360,
            unsupportedOverrides: [], skippedStyles: []), "plan contentID matches compute")

        // 9: typed overlay answers on SDR surface carry the full revision pair
        if case .empty(let rev) = planA1.overlay(at: 0.5, surfaceIsHDR: false) {
            check(rev == planA1.planRevision, "gap -> empty with plan revision")
        } else { check(false, "gap -> empty") }
        if case .cue(let c, let sup, let rev) = planA1.overlay(at: 2, surfaceIsHDR: false) {
            check(c.index == 1 && rev == planA1.planRevision && sup.isEmpty, "active cue with plan revision, no suppression")
        } else { check(false, "active cue answer") }
        if case .empty = planA1.overlay(at: 3, surfaceIsHDR: false) {
            check(true, "end is exclusive at plan level")
        } else { check(false, "end exclusivity") }

        // 10: HDR surface -> typed refusal, never a degraded cue answer
        if case .hdrUnsupported(let rev) = planA1.overlay(at: 2, surfaceIsHDR: true) {
            check(rev == planA1.planRevision, "HDR -> typed refusal with plan revision")
        } else { check(false, "HDR typed refusal") }
        if case .hdrUnsupported = planA1.overlay(at: 0.5, surfaceIsHDR: true) {
            check(true, "HDR refusal even in gaps (no misrender)")
        } else { check(false, "HDR refusal in gap") }

        // 11: Q4 - latest-starting wins; suppressed indices typed, sorted, never stacked
        let overA = SubtitleCue(index: 1, startSeconds: 1, endSeconds: 5, lines: ["a"], styleName: "Default")
        let overB = SubtitleCue(index: 2, startSeconds: 3, endSeconds: 6, lines: ["b"], styleName: "Default")
        let overC = SubtitleCue(index: 3, startSeconds: 4, endSeconds: 8, lines: ["c"], styleName: "Default")
        let overTrack = SubtitleTrack.Track(format: "ass", cues: [overA, overB, overC], styles: styles,
                                            unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let overProducer = SubtitlePlanProducer(track: overTrack)
        guard let overPlan = try? overProducer.makePlan() else { check(false, "overlap plan issued"); return }
        if case .cue(let w, let sup, _) = overPlan.overlay(at: 4.5, surfaceIsHDR: false) {
            check(w.index == 3 && sup == [1, 2], "three-way overlap: latest-starting wins, suppressed [1,2] sorted")
        } else { check(false, "three-way overlap answer") }
        if case .cue(let w2, let sup2, _) = overPlan.overlay(at: 3.5, surfaceIsHDR: false) {
            check(w2.index == 2 && sup2 == [1], "two-way overlap: suppressed [1]")
        } else { check(false, "two-way overlap answer") }
        if case .cue(_, let sup3, _) = overPlan.overlay(at: 1.5, surfaceIsHDR: false) {
            check(sup3.isEmpty, "single coverage: no suppressed indices")
        } else { check(false, "single coverage answer") }

        // 11b: Q4 tie rule (named behavior; decision silent on ties): equal
        // startSeconds -> FIRST IN TRACK ORDER wins, other suppressed
        let tieA = SubtitleCue(index: 1, startSeconds: 2, endSeconds: 5, lines: ["first"], styleName: "Default")
        let tieB = SubtitleCue(index: 2, startSeconds: 2, endSeconds: 6, lines: ["second"], styleName: "Default")
        let tieTrack = SubtitleTrack.Track(format: "ass", cues: [tieA, tieB], styles: styles,
                                           unsupportedOverrides: [], skippedStyles: [], playResX: 640, playResY: 360)
        let tieProducer = SubtitlePlanProducer(track: tieTrack)
        guard let tiePlan = try? tieProducer.makePlan() else { check(false, "tie plan issued"); return }
        if case .cue(let tw, let tsup, _) = tiePlan.overlay(at: 3, surfaceIsHDR: false) {
            check(tw.index == 1 && tsup == [2], "equal-start tie: first in track order wins")
        } else { check(false, "tie answer") }

        // 11c: half-open boundary - pts == start is INCLUSIVE (gdb u8r1 review note 2)
        let edgeTrack = SubtitleTrack.Track(format: "srt", cues: [SubtitleCue(index: 1, startSeconds: 2, endSeconds: 5, lines: ["edge"], styleName: "Default")],
                                            styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let edgeProducer = SubtitlePlanProducer(track: edgeTrack)
        guard let edgePlan = try? edgeProducer.makePlan() else { check(false, "edge plan issued"); return }
        if case .cue(let ew, let esup, _) = edgePlan.overlay(at: 2, surfaceIsHDR: false) {
            check(ew.index == 1 && esup.isEmpty, "pts == start inclusive (half-open [start,end))")
        } else { check(false, "start-inclusive answer") }

        // 11d: duplicate cue indices -> typed plan finding; index-based
        // suppression reporting is then ambiguous for the shared index
        // (gdb u8r1 review note 1)
        let dupTrack = SubtitleTrack.Track(format: "srt", cues: [SubtitleCue(index: 7, startSeconds: 1, endSeconds: 3, lines: ["a"], styleName: "Default"),
                                                               SubtitleCue(index: 7, startSeconds: 2, endSeconds: 4, lines: ["b"], styleName: "Default")],
                                           styles: styles, unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        let dupProducer = SubtitlePlanProducer(track: dupTrack)
        guard let dupPlan = try? dupProducer.makePlan() else { check(false, "dup plan issued"); return }
        if case .cue(let dw, let dsup, _) = dupPlan.overlay(at: 2.5, surfaceIsHDR: false) {
            check(dw.startSeconds == 2 && dsup.isEmpty && dupPlan.findings == [.duplicateCueIndices([7])],
                  "duplicate cue indices -> typed finding; shared-index suppression visibly ambiguous")
        } else { check(false, "duplicate-index answer") }

        // 12: Q5 - declared default PlayRes 384x288 + usedDefaultPlayRes flag
        check(srtPlan.effectivePlayResX == 384 && srtPlan.effectivePlayResY == 288,
              "absent PlayRes -> declared default 384x288")
        check(srtPlan.usedDefaultPlayRes, "usedDefaultPlayRes true when absent")
        check(planA1.effectivePlayResX == 640 && planA1.effectivePlayResY == 360 && !planA1.usedDefaultPlayRes,
              "raw PlayRes used when present, flag false")

        // 13: Q2 - presenter echo is the generation only
        check(planA1.presenterEchoRevision == planA1.planRevision.generation,
              "presenter echo carries generation only")
        check(planA1.presenterEchoRevision != planA2.presenterEchoRevision,
              "echo changes across reissue (same content, new generation)")

        // SP-TRAP regression (observed exit132 on extreme SRT input): non-finite
        // and Int64-unrepresentable cue times hash without a trap; extension
        // classes stay distinct; ordinary millisecond identity is untouched
        // (existing checks above already pin the representable encoding).
        let trapStyles = styles
        let hugeID = SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: .greatestFiniteMagnitude, endSeconds: .infinity, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
        let nanID = SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: .nan, endSeconds: 2, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
        let negInfID = SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: -.infinity, endSeconds: 2, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
        let negHugeID = SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: -.greatestFiniteMagnitude, endSeconds: 2, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
        check(hugeID != nanID && hugeID != negInfID && hugeID != negHugeID && nanID != negInfID && nanID != negHugeID && negInfID != negHugeID,
              "SP-TRAP: non-finite/unrepresentable cue times hash distinctly, no trap")
        let hugeHalfID = SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: .greatestFiniteMagnitude / 2, endSeconds: .infinity, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
        check(hugeID != hugeHalfID, "SP-TRAP: distinct huge magnitudes keep distinct identities")
        check(SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: -0.0, endSeconds: 0.0, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: [])
              == SubtitlePlanContentID.compute(cues: [SubtitleCue(index: 1, startSeconds: 0.0, endSeconds: 0.0, lines: ["a"], styleName: "Default")], styles: trapStyles, playResX: nil, playResY: nil, unsupportedOverrides: [], skippedStyles: []),
              "SP-TRAP: -0.0 and +0.0 keep the same millisecond identity")

        if failures == 0 { print("ALL_CHECKS_PASS") } else { print("FAILURES=\(failures)") }
        exit(failures == 0 ? 0 : 1)
    }
}
