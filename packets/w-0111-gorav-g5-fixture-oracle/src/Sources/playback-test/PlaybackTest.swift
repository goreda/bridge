import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

// K3 playback-loop proof: path route (mp4/mpeg4 admission), pull-to-EOS,
// per-frame adapter frameDigest vs the shipped C-oracle, clean teardown.
@main
struct PlaybackTest {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let fixture = "\(KIT)/fixtures/fixture-k3.mp4"
        let oraclePath = "\(KIT)/oracles/k3-oracle.txt"
        guard let oracleRaw = try? String(contentsOfFile: oraclePath, encoding: .utf8) else {
            print("K3 FAIL: oracle unreadable"); exit(65)
        }
        let oracle = oracleRaw.split(separator: "\n").compactMap { line -> (Int, String)? in
            let p = line.split(separator: " "); guard p.count == 2, let i = Int(p[0]) else { return nil }
            return (i, String(p[1]))
        }

        let decoder = FFmpegSoftwareDecoder()
        do { try decoder.pinLocalRoots([KIT]) }
        catch { print("K3 FAIL: pinLocalRoots \(error)"); exit(66) }
        let session = SessionID(uncheckedEpoch: 21)
        do {
            try await decoder.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: session)
        } catch { print("K3 FAIL: open \(error)"); exit(67) }

        var digests: [String] = []
        var sawEOS = false
        while let event = await decoder.nextEvent(session: session) {
            switch event {
            case .opened(let codec, let w, let h):
                print("opened: codec=\(codec) \(w)x\(h)")
            case .frameDecoded(let frame):
                let d = await decoder.frameDigest(handle: frame.handle, session: session) ?? "nil"
                digests.append(d)
                await decoder.releaseFrame(handle: frame.handle, session: session)
            case .endOfStream:
                sawEOS = true
            case .failed(let code, let summary):
                print("K3 FAIL: failed \(code) \(summary)"); exit(70)
            default: break
            }
        }
        let report = await decoder.closeAndReport(session: session)
        print("frames=\(digests.count) eos=\(sawEOS) leaks=\(report?.leakedHandles.count ?? -1)")

        var mismatches = 0
        for (i, o) in oracle {
            if i < digests.count, digests[i] != o { mismatches += 1; print("MISMATCH frame \(i): got \(digests[i]) want \(o)") }
        }
        if digests.count == oracle.count && mismatches == 0 && sawEOS && (report?.leakedHandles.isEmpty ?? false) {
            print("K3_PLAYBACK_LOOP_PASS frames=\(digests.count)")
        } else {
            print("K3_PLAYBACK_LOOP_MISMATCH frames=\(digests.count)/\(oracle.count) mismatches=\(mismatches)")
            exit(71)
        }

        // K6 core scenarios, same binary (known-good runtime path).
        final class FakeClock: PlaybackClock, @unchecked Sendable {
            var t: Double = 0; let step: Double
            init(step: Double) { self.step = step }
            func nowSeconds() -> Double { defer { t += step }; return t }
        }
        struct NullSink: FrameSink { func show(_ frame: SourceFrame) async -> Bool { true } }
        struct AdapterSource: FrameSource {
            let decoder: FFmpegSoftwareDecoder; let session: SessionID
            func nextEvent() async -> SourceEvent {
                while let ev = await decoder.nextEvent(session: session) {
                    switch ev {
                    case .frameDecoded(let f):
                        // S5: release the handle on EVERY path BEFORE any
                        // skip - a missing-PTS skip without release leaks it.
                        guard let pts = f.pts else {
                            await decoder.releaseFrame(handle: f.handle, session: session)
                            continue
                        }
                        let d = await decoder.frameDigest(handle: f.handle, session: session) ?? "nil"
                        await decoder.releaseFrame(handle: f.handle, session: session)
                        return .frame(SourceFrame(ptsSeconds: Double(pts) / 12800.0, durationSeconds: 0.04, digest: d))
                    case .endOfStream: return .ended(.endOfStream)
                    case .failed(let code, _): return .failed(code)
                    default: continue
                    }
                }
                return nil
            }
        }
        func scenario(_ name: String, _ epoch: UInt64, _ step: Double, _ oracleD: [String]) async -> (PumpStats, Int) {
            let dec = FFmpegSoftwareDecoder()
            try! dec.pinLocalRoots([ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"])
            let ses = SessionID(uncheckedEpoch: epoch)
            try! await dec.open(source: SourceDescriptor(id: "\(ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2")/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: ses)
            _ = await dec.nextEvent(session: ses)
            let clock = FakeClock(step: step)
            let pump = FramePump(source: AdapterSource(decoder: dec, session: ses), sink: NullSink(), clock: clock) { _ in }
            let stats = await pump.run()
            _ = await dec.closeAndReport(session: ses)
            let mm = zip(stats.digestsShown, oracleD).filter { $0 != $1 }.count
            print("\(name): shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits) digestMismatches=\(mm)")
            return (stats, mm)
        }
        let oracleDigests = oracle.map { $0.1 }
        var k6fails = 0
        let (s1, m1) = await scenario("S1_realtime", 61, 0.04, oracleDigests)
        if !(s1.shown == 47 && s1.dropped == 0 && m1 == 0 && s1.digestsShown == oracleDigests) { k6fails += 1 }
        let (s2, _) = await scenario("S2_slow", 62, 0.08, oracleDigests)
        if !(s2.dropped > 0 && s2.shown + s2.dropped == 47) { k6fails += 1 }
        let (s3, m3) = await scenario("S3_fast", 63, 0.02, oracleDigests)
        if !(s3.waits > 0 && s3.shown == 47 && m3 == 0) { k6fails += 1 }

        // S4-S6: synthetic-fault boundary scenarios (team2 13:48 addendum).
        final class SyntheticSource: FrameSource, @unchecked Sendable {
            var frames: [SourceFrame]
            init(frames: [SourceFrame]) { self.frames = frames }
            func nextEvent() async -> SourceEvent { frames.isEmpty ? .ended(.sourceEnded) : .frame(frames.removeFirst()) }
        }
        func synthetic(_ name: String, _ frames: [SourceFrame], _ step: Double) async -> PumpStats {
            let clock = FakeClock(step: step)
            let pump = FramePump(source: SyntheticSource(frames: frames), sink: NullSink(), clock: clock,
                                 decider: AVSyncDecider(maxWaitSeconds: 0.05)) { _ in }
            let stats = await pump.run()
            print("\(name): shown=\(stats.shown) dropped=\(stats.dropped) waits=\(stats.waits) outOfOrder=\(stats.outOfOrderDrops) nonFinite=\(stats.nonFiniteDrops)")
            return stats
        }
        // S4: one out-of-order pts -> typed drop, no trap, others shown.
        let s4 = await synthetic("S4_out_of_order", [
            SourceFrame(ptsSeconds: 0.04, durationSeconds: 0.04, digest: "a"),
            SourceFrame(ptsSeconds: 0.02, durationSeconds: 0.04, digest: "b"), // violation
            SourceFrame(ptsSeconds: 0.08, durationSeconds: 0.04, digest: "c"),
        ], 0.04)
        if !(s4.outOfOrderDrops == 1 && s4.digestsShown == ["a", "c"]) { k6fails += 1 }
        // S5: far-future pts with clamped max-wait -> bounded waits, eventual drop.
        let s5 = await synthetic("S5_far_future", [
            SourceFrame(ptsSeconds: 3600, durationSeconds: 0.04, digest: "x"),
        ], 0.04)
        if !(s5.shown + s5.dropped == 1 && s5.waits <= 100) { k6fails += 1 }
        // S6: NaN pts and infinite duration -> boundary refusal, no trap.
        let s6 = await synthetic("S6_non_finite", [
            SourceFrame(ptsSeconds: .nan, durationSeconds: 0.04, digest: "n1"),
            SourceFrame(ptsSeconds: 0.0, durationSeconds: .infinity, digest: "n2"),
        ], 0.04)
        if !(s6.nonFiniteDrops == 2 && s6.shown == 0) { k6fails += 1 }

        // S7: mid-stream backward seek + resetPresentation - post-seek
        // frames must be SHOWN (not mass out-of-order drops); without the
        // reset this is the proven failure mode.
        do {
            let dec = FFmpegSoftwareDecoder()
            try! dec.pinLocalRoots([ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"])
            let ses = SessionID(uncheckedEpoch: 64)
            try! await dec.open(source: SourceDescriptor(id: "\(ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2")/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: ses)
            _ = await dec.nextEvent(session: ses)
            let clock = FakeClock(step: 0.04)
            let pump = FramePump(source: AdapterSource(decoder: dec, session: ses), sink: NullSink(), clock: clock) { _ in }
            // Decode 20 frames, then seek back to 0.8s (landing keyframe 12),
            // reset presentation, drain the rest; compare digests.
            // FramePump.run() drains to EOS, so drive it in two legs via a
            // pausable source wrapper: decode leg 1 directly here.
            var leg1: [String] = []
            let src = AdapterSource(decoder: dec, session: ses)
            for _ in 0..<20 { if case .frame(let f) = await src.nextEvent() { leg1.append(f.digest) } }
            try! await dec.seek(toSeconds: 0.8, session: ses)
            // Verdict S5 rev6: the reset is a SEEK-COMPLETION ACK with a
            // typed refusal - the Bool is load-bearing, never ignored.
            let resetOK = await pump.resetPresentation()
            if !resetOK {
                print("S7_seek_reset_refused: typed refusal, no seek ACK")
                k6fails += 1
                _ = await dec.closeAndReport(session: ses)
            } else {
            let stats2 = await pump.run()
            let want = Array(oracleDigests[0..<20]) + Array(oracleDigests[12...])
            let gotAll = leg1 + stats2.digestsShown
            let ok = gotAll == want && stats2.outOfOrderDrops == 0
            print("S7_seek_resume: leg1=\(leg1.count) leg2=\(stats2.shown) outOfOrder=\(stats2.outOfOrderDrops) \(ok ? "OK" : "MISMATCH")")
            if !ok { k6fails += 1 }
            _ = await dec.closeAndReport(session: ses)
            }
        }
        print(k6fails == 0 ? "K6_CORE_PASS" : "K6_CORE_FAIL")

        // K7: shell display conversion (yuv420p->RGBA BT.601) vs independent
        // C oracle over the real decoder's frames (framePlaneCopy seam).
        // All 47 frames compared; frame 0 pins 4f38bbd35303d485.
        var k7ok = false
        do {
            let k7oracle = try! String(contentsOfFile: "\(ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2")/oracles/k7b-rgba-oracle.txt", encoding: .utf8)
                .split(separator: "\n").map { String($0.split(separator: " ")[1]) }
            let dec = FFmpegSoftwareDecoder()
            try! dec.pinLocalRoots([ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"])
            let ses = SessionID(uncheckedEpoch: 71)
            try! await dec.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: ses)
            _ = await dec.nextEvent(session: ses)
            var idx = 0, k7mis = 0
            while let ev = await dec.nextEvent(session: ses) {
                if case .frameDecoded(let f) = ev {
                    if let copy = await dec.framePlaneCopy(handle: f.handle, session: ses), copy.planes.count == 3 {
                        let rgba = copy.planes[0].withUnsafeBufferPointer { yb in
                            copy.planes[1].withUnsafeBufferPointer { ub in
                                copy.planes[2].withUnsafeBufferPointer { vb in
                                    YUV420Converter.rgbaFromYUV420p(
                                        y: yb.baseAddress!, yStride: copy.width,
                                        u: ub.baseAddress!, uStride: copy.width / 2,
                                        v: vb.baseAddress!, vStride: copy.width / 2,
                                        width: copy.width, height: copy.height)
                                }
                            }
                        }
                        var h: UInt64 = 14695981039346656037
                        for b in rgba { h = (h ^ UInt64(b)) &* 1099511628211 }
                        let got = String(format: "%016llx", h)
                        if idx < k7oracle.count && got != k7oracle[idx] { k7mis += 1; print("K7 MISMATCH frame \(idx): \(got) want \(k7oracle[idx])") }
                        idx += 1
                    }
                    await dec.releaseFrame(handle: f.handle, session: ses)
                }
                if case .endOfStream = ev { break }
                if case .failed(let c, let sm) = ev { print("K7 FAIL: \(c) \(sm)"); k7mis += 1; break }
            }
            _ = await dec.closeAndReport(session: ses)
            print("k7 frames=\(idx) mismatches=\(k7mis) oracle=\(k7oracle.count)")
            k7ok = (idx == 47 && idx == k7oracle.count && k7mis == 0)
        }
        print(k7ok ? "K7_YUV_RGB_PASS" : "K7_YUV_RGB_FAIL")
        exit(k6fails == 0 && k7ok ? 0 : 71)
    }
}
