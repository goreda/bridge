import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// SEEK-RESTART PROBE (189s / V4 diagnosis, RULES.md:69 step 2 timing):
// reproduces the V4 venue decoder state on Linux: consume ~0.5s of the
// e1-h264-aac-10s.mp4 fixture (V2 paused right after firstFrame), then
// seek(8.0) and measure, in MONOTONIC seconds:
//   - post-seek landing pts (BACKWARD seek -> keyframe <= 8.0; fixture has
//     ONE keyframe at 0, stss count=1, verified by ffprobe)
//   - frames decoded with pts < 8.0 (what the pump would DROP, anchor 8.0)
//   - elapsed until the first frame with pts >= 8.0 (first PRESENTABLE)
//   - elapsed until endOfStream (what V4 waits on, 8s deadline)
// If first-presentable and EOS land well under 8s, the video leg cannot
// explain run 42314208050's "no .ended within 8s" and the broken
// RULES.md:69 step is 3 (audio clock restart), not 2.
// Fixture video timescale = 12800 (ffprobe-verified on this file).
// Exit: 0 always (measurement probe); NOT_RUN=2 missing fixture.

let NOT_RUN: Int32 = 2
let TIMESCALE: Double = 12800

@main
struct SeekRestartProbe {
    static func elapsed(_ t0: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    }

    static func run(scenario: String, preConsumeSeconds: Double, seekTarget: Double) async {
        let fixture = FileManager.default.currentDirectoryPath + "/fixtures/e1-h264-aac-10s.mp4"
        guard FileManager.default.fileExists(atPath: fixture) else {
            print("SEEK-RESTART NOT_RUN: missing fixture \(fixture)"); fflush(stdout); Foundation.exit(NOT_RUN)
        }
        let decoder = FFmpegSoftwareDecoder()
        try! decoder.pinLocalRoots([FileManager.default.currentDirectoryPath])
        let session = SessionID(uncheckedEpoch: UInt64(7000 + Int(seekTarget * 10 + preConsumeSeconds)))
        do {
            try await decoder.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: session)
        } catch { print("SEEK-RESTART \(scenario): open threw \(error)"); return }
        _ = await decoder.nextEvent(session: session) // .opened

        // Pre-consume to the V4 seek-time decoder position (~0.5s content).
        var consumed = 0
        var lastPts = 0.0
        while lastPts < preConsumeSeconds {
            guard let ev = await decoder.nextEvent(session: session) else { break }
            if case .frameDecoded(let f) = ev {
                if let p = f.pts { lastPts = Double(p) / TIMESCALE }
                await decoder.releaseFrame(handle: f.handle, session: session)
                consumed += 1
            } else if case .endOfStream = ev { break }
        }

        let t0 = DispatchTime.now().uptimeNanoseconds
        do { try await decoder.seek(toSeconds: seekTarget, session: session) }
        catch { print("SEEK-RESTART \(scenario): seek(\(seekTarget)) threw \(error)"); return }
        let seekRc = elapsed(t0)

        var firstPts: Double? = nil; var firstIsKey = false
        var preTarget = 0; var postTarget = 0
        var tFirstPresentable: Double? = nil; var tEOS: Double? = nil
        pull: while let ev = await decoder.nextEvent(session: session) {
            switch ev {
            case .frameDecoded(let f):
                let pts = f.pts.map { Double($0) / TIMESCALE } ?? -1
                if firstPts == nil { firstPts = pts; firstIsKey = f.isKeyFrame }
                if pts < seekTarget - 1e-9 { preTarget += 1 } else {
                    postTarget += 1
                    if tFirstPresentable == nil { tFirstPresentable = elapsed(t0) }
                }
                await decoder.releaseFrame(handle: f.handle, session: session)
            case .endOfStream:
                tEOS = elapsed(t0); break pull
            case .failed(let c, let s):
                print("SEEK-RESTART \(scenario): decoder failed \(c) \(s)"); break pull
            case .feedSaturated: continue
            default: continue
            }
        }
        print(String(format: "SEEK-RESTART %@: preConsumed=%d (to %.2fs) seekCall=%.3fs landing=%.3fs key=%d preTargetDropped=%d firstPresentable=%@ EOS=%@",
                     scenario, consumed, lastPts, seekRc, firstPts ?? -1, firstIsKey ? 1 : 0, preTarget,
                     tFirstPresentable.map { String(format: "%.3fs", $0) } ?? "none",
                     tEOS.map { String(format: "%.3fs", $0) } ?? "none"))

        // AUDIO LEG (RULES.md:69 step 3): same fixture, same V4 state,
        // then the exact bound seek the session issues - which outcome?
        let adec = FFmpegSoftwareAudioDecoder()
        try! adec.pinLocalRoots([FileManager.default.currentDirectoryPath])
        let asession = SessionID(uncheckedEpoch: 7108)
        do {
            try await adec.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: asession)
        } catch { print("SEEK-RESTART audio: open threw \(error)"); return }
        guard let desc = await adec.seekDescriptor(session: asession) else {
            print("SEEK-RESTART audio: no seekDescriptor (session would refuse typed)"); return
        }
        print("SEEK-RESTART audio descriptor: seekable=\(desc.seekable) origin=\(desc.referenceOrigin.map { "\($0.value)/\($0.timescale)" } ?? "nil") timebase=\(desc.audioTimebase.value)/\(desc.audioTimebase.timescale)")
        var consumedSamples = 0
        while Double(consumedSamples) / 44100.0 < preConsumeSeconds {
            guard let env = await adec.nextBoundEvent(binding: desc.binding) else { break }
            if case .pcm(let f) = env.event { consumedSamples += f.samples }
        }
        let target = try! RationalTime(value: Int64(seekTarget * 1000), timescale: 1000)
        let tA = DispatchTime.now().uptimeNanoseconds
        let result = await adec.seek(binding: desc.binding, videoRelativeTarget: target, correlation: 1)
        let aSeek = Double(DispatchTime.now().uptimeNanoseconds - tA) / 1e9
        switch result {
        case .nativeReady(_, _, let common, let ticks):
            print(String(format: "SEEK-RESTART audio seek(\\(seekTarget)): nativeReady common=\\(common.value)/\\(common.timescale) ticks=\\(ticks) call=%.3fs", aSeek))
        case .refused(let why):
            print(String(format: "SEEK-RESTART audio seek(\\(seekTarget)): REFUSED \\(why) call=%.3fs -> session would emit .failed(audioSeek:refusedMuted) and CANCEL the commit", aSeek))
        case .closeRequired(_, _, let code):
            print(String(format: "SEEK-RESTART audio seek(\\(seekTarget)): CLOSE-REQUIRED nativeCode=\\(code) call=%.3fs -> session would emit .failed(audioSeek:closeRequired) and CANCEL the commit", aSeek))
        }
        // Post-seek audio: first pcm chunk landing vs target
        if case .nativeReady(let nb, _, _, _) = result {
            var firstReported = false
            for _ in 0..<2000 {
                guard let env = await adec.nextBoundEvent(binding: nb) else { break }
                if case .pcm = env.event, !firstReported {
                    firstReported = true
                    if let t = env.timing {
                        print("SEEK-RESTART audio post-seek first pcm: firstSample=\(t.firstSample.value)/\(t.firstSample.timescale) trimmed=\(t.trimmedSamples) gapFromTarget=\(t.gapFromTarget.map { "\($0.value)/\($0.timescale)" } ?? "nil")")
                    } else {
                        print("SEEK-RESTART audio post-seek first pcm: no timing")
                    }
                }
                if case .endOfStream = env.event { break }
            }
        }
        _ = await decoder.closeAndReport(session: session)
    }

    static func main() async {
        // V4 decoder state: ~0.5s consumed (V2 paused right after firstFrame),
        // then seek(8.0) near the end of the 10s fixture.
        await run(scenario: "v4-state", preConsumeSeconds: 0.5, seekTarget: 8.0)
        // Control: cold seek right after open.
        await run(scenario: "cold", preConsumeSeconds: 0.0, seekTarget: 8.0)
    }
}
