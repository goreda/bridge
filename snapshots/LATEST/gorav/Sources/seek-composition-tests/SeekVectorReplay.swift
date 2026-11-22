// W-gdb-019: seek-vector replay harness + negative control.
//
// Replays the pack against a candidate seek planner and scores each vector's
// decision table. The built-in PinnedSeekCompositionModel encodes the
// orchestration semantics visible in the pinned SeekComposition.swift
// excerpt (lines 232-285, packet pin 3eb39d30...) plus the packet's pinned
// ABI decisions:
//
//   1. videoSeek() false (refused PRE-mutation): resume with ring intact ->
//      videoRefusedResumed; if resumeProducer also refuses -> closeAudio ->
//      resumeRefusedMuted.
//   2. Committed seek, not parked, firstFrameAnchor() nil (RULES.md:69 gate
//      timeout) -> closeAudio -> firstFrameTimeoutMuted.
//   3. parkedVideo == true: the gate is vacuous while the render path is
//      quiesced; anchor = nil, producer rearmed with nil shared anchor.
//   4. After a COMMITTED video seek there is NO rollback: refused ring
//      reset / refused audio seek / frame0 timeout CLOSE the audio leg
//      (typed mute):
//        ring reset refused       -> ringResetRefusedMuted
//        audio seek typed refusal -> refusedMuted
//        av_seek_frame error (can mutate even on failure) -> closeRequired,
//          never resume
//   5. Success -> nativeReady.
//
// PACK SCHEMA CONVENTION (not excerpt-derived): acceptedTargetTicks =
// clamp(target, 0, duration) + editListOffsetTicks; see pack 'conventions'.
//
// SV-011 RESOLVED by the integrator (arch-196s, 2026-11-15): parked + ring
// reset refused -> ringResetRefusedMuted. Confirmed against
// Sources/GorAVSeekComposition/SeekComposition.swift: parkedVideo skips the
// frame0 anchor gate only; resetRingForSeek still runs and its refusal goes
// to closeAudio + ringResetRefusedMuted. The pack author's truncated-excerpt
// assumption (ringResetRefusedResumed) was wrong.
//
// STATUS: NOT BUILT, NOT RUN (no Swift toolchain in the authoring
// environment). Integration: one line in the existing
// seek-composition-tests main, see README-SEEKVECTORS.md.

import Foundation

/// A candidate seek planner scores one vector into a decision table.
/// Wire the real SeekComposition orchestration in behind this protocol to
/// replay the pack against product code.
public protocol SeekVectorPlanner {
    func plan(_ vector: SeekVector) -> SeekVectorDecision
}

public enum SeekVectorReplay {
    /// Pinned SeekAudioOutcome case order (packet, 2026-11-15 integrator pin).
    public static let pinnedSeekAudioOutcomes = [
        "nativeReady", "resumeRefusedMuted", "closeRequired", "refusedMuted",
        "ringResetRefusedMuted", "firstFrameTimeoutMuted",
        "videoRefusedResumed", "ringResetRefusedResumed",
    ]

    /// Pinned AudioSeekRefusal cases at the same pin.
    public static let pinnedAudioSeekRefusals = [
        "closed", "staleBinding", "poisoned", "legacyMode", "invalidTarget",
        "unknownOrigin", "notSeekable",
    ]

    public struct ReplayRow {
        public var id: String
        public var vectorClass: String
        public var expected: String
        public var actual: String
        public var passed: Bool
        public var mismatches: [String]
    }

    @discardableResult
    public static func replay(
        pack: SeekVectorPack,
        planner: SeekVectorPlanner,
        flipOutcome vectorIdToFlip: String? = nil
    ) -> (rows: [ReplayRow], allPassed: Bool) {
        var rows: [ReplayRow] = []
        for vector in pack.vectors {
            var expected = vector.expected
            if vector.id == vectorIdToFlip,
               let index = pinnedSeekAudioOutcomes.firstIndex(of: expected.outcome) {
                // Negative control: flip to ANOTHER VALID vocabulary case, so
                // any failure is a real behavioural mismatch, not a schema
                // error.
                expected.outcome =
                    pinnedSeekAudioOutcomes[(index + 1) % pinnedSeekAudioOutcomes.count]
            }
            let actual = planner.plan(vector)
            var mismatches: [String] = []
            if actual.acceptedTargetTicks != expected.acceptedTargetTicks {
                mismatches.append(
                    "acceptedTargetTicks expected=\(expected.acceptedTargetTicks) actual=\(actual.acceptedTargetTicks)")
            }
            if actual.anchorExpectation != expected.anchorExpectation {
                mismatches.append(
                    "anchorExpectation expected=\(expected.anchorExpectation) actual=\(actual.anchorExpectation)")
            }
            if actual.ringResetRequired != expected.ringResetRequired {
                mismatches.append(
                    "ringResetRequired expected=\(expected.ringResetRequired) actual=\(actual.ringResetRequired)")
            }
            if actual.outcome != expected.outcome {
                mismatches.append(
                    "outcome expected=\(expected.outcome) actual=\(actual.outcome)")
            }
            if actual.audioSeekResult != expected.audioSeekResult {
                mismatches.append(
                    "audioSeekResult expected=\(String(describing: expected.audioSeekResult)) actual=\(String(describing: actual.audioSeekResult))")
            }
            rows.append(ReplayRow(
                id: vector.id,
                vectorClass: vector.vectorClass,
                expected: expected.outcome,
                actual: actual.outcome,
                passed: mismatches.isEmpty,
                mismatches: mismatches))
        }
        return (rows, rows.allSatisfy { $0.passed })
    }

    /// Entry point for the existing seek-composition-tests main.
    ///
    ///   --seek-vectors <path>    replay this pack (exit 0 iff all rows pass)
    ///   --flip-outcome <id>      negative control: flip one expected outcome
    ///   --negative-control       flip pack.vectors[0] (SV-001 in the
    ///                            generated pack) and REQUIRE exactly that row to
    ///                            fail with its vector id (exit 0 iff it does)
    public static func run(arguments: [String]) -> Int32 {
        var packPath: String?
        var flip: String?
        var negativeControl = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--seek-vectors" where index + 1 < arguments.count:
                packPath = arguments[index + 1]; index += 2
            case "--flip-outcome" where index + 1 < arguments.count:
                flip = arguments[index + 1]; index += 2
            case "--negative-control":
                negativeControl = true; index += 1
            default:
                index += 1
            }
        }
        guard let path = packPath else {
            FileHandle.standardError.write(
                Data("seek-vector replay: no --seek-vectors path; skipping\n".utf8))
            return 0  // existing suite stays green when the flag is absent
        }
        do {
            let pack = try SeekVectorPack.load(from: path)
            try pack.validateVocabulary()
            if negativeControl {
                let first = pack.vectors[0].id
                let (rows, _) = replay(pack: pack,
                                       planner: PinnedSeekCompositionModel(),
                                       flipOutcome: first)
                let failed = rows.filter { !$0.passed }
                let ok = failed.count == 1 && failed[0].id == first
                for row in failed {
                    print("FAIL \(row.id): \(row.mismatches.joined(separator: "; "))")
                }
                print("negative-control: flipped \(first) -> " +
                      (ok ? "correctly FAILED with vector id" : "UNEXPECTED RESULT"))
                return ok ? 0 : 1
            }
            let (rows, allPassed) = replay(pack: pack,
                                           planner: PinnedSeekCompositionModel(),
                                           flipOutcome: flip)
            print("vector_id\tclass\texpected\tactual\tresult")
            for row in rows {
                print("\(row.id)\t\(row.vectorClass)\t\(row.expected)\t\(row.actual)\t\(row.passed ? "PASS" : "FAIL")")
                for mismatch in row.mismatches {
                    print("  FAIL \(row.id): \(mismatch)")
                }
            }
            let failedCount = rows.filter { !$0.passed }.count
            print("summary: \(rows.count) vectors, \(rows.count - failedCount) pass, \(failedCount) fail")
            return allPassed ? 0 : 1
        } catch {
            FileHandle.standardError.write(
                Data("seek-vector replay: \(error)\n".utf8))
            return 2
        }
    }
}

/// Reference planner: the pinned-orchestration model. A green replay of the
/// pack against THIS model validates the pack itself; replaying against the
/// real SeekComposition wiring is the product-side check.
public struct PinnedSeekCompositionModel: SeekVectorPlanner {
    public init() {}

    public func plan(_ vector: SeekVector) -> SeekVectorDecision {
        let request = vector.request
        let scenario = vector.scenario
        let stream = vector.stream

        let clamped = min(max(request.targetTicks, 0), stream.durationTicks)
        let accepted = clamped + stream.editListOffsetTicks
        let parked = request.parkedVideo

        func decision(_ anchor: String, _ reset: Bool,
                      _ outcome: String, _ result: SeekVectorAudioResult?)
            -> SeekVectorDecision {
            SeekVectorDecision(
                acceptedTargetTicks: accepted,
                anchorExpectation: anchor,
                ringResetRequired: reset,
                outcome: outcome,
                audioSeekResult: result)
        }

        // (1) video refused pre-mutation: nothing mutated, ring intact.
        guard scenario.videoSeekCommitted else {
            if scenario.resumeProducer == "ok" {
                return decision("not-reached", false, "videoRefusedResumed", nil)
            }
            return decision("not-reached", false, "resumeRefusedMuted", nil)
        }

        // (2)/(3) frame0 gate (vacuous while parked).
        let anchor: String
        if parked {
            anchor = "skipped-parked"
        } else if scenario.firstFrameAnchor == "timeout" {
            return decision("timeout-closes", false, "firstFrameTimeoutMuted", nil)
        } else {
            anchor = "required-and-presented"
        }

        // (4) ring reset after commit: no rollback.
        guard scenario.ringReset == "ok" else {
            // INTEGRATOR CONFIRMED (arch-196s, 2026-11-15) against
            // Sources/GorAVSeekComposition/SeekComposition.swift: parked skips
            // ONLY the frame0 gate; the ring reset still runs and a refusal
            // after a committed video seek closes the audio leg.
            return decision(anchor, true, "ringResetRefusedMuted", nil)
        }

        // (4)/(5) audio seek.
        switch scenario.audioSeek.kind {
        case "refused":
            return decision(anchor, true, "refusedMuted",
                            SeekVectorAudioResult(
                                kind: "refused", seekTicks: nil,
                                reason: scenario.audioSeek.reason,
                                nativeCode: nil))
        default:
            let code = scenario.audioSeek.nativeCode ?? 0
            if code == 0 {
                return decision(anchor, true, "nativeReady",
                                SeekVectorAudioResult(
                                    kind: "nativeReady",
                                    seekTicks: scenario.audioSeek.seekTicks,
                                    reason: nil, nativeCode: nil))
            }
            return decision(anchor, true, "closeRequired",
                            SeekVectorAudioResult(
                                kind: "closeRequired", seekTicks: nil,
                                reason: nil, nativeCode: code))
        }
    }
}
