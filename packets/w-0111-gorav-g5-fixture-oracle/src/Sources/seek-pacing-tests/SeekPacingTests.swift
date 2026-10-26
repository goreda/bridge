// M4 seek pacing re-anchor test (Linux): proves the post-seek pace preserves
// the measured late-start gap in ACTUAL pace - the first post-seek frame
// shows on arrival and later frames pace by pts deltas - instead of the
// raw-wall defects: forward seek = wait for the whole seek distance,
// backward seek = drop-storm to EOF. Pure Swift fakes; no FFmpeg.
import GorAVPlaybackCore
import Foundation

import Foundation
var failures = 0
func log(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
func expect(_ c: Bool, _ m: String) { if !c { failures += 1; log("FAIL \(m)") } }

final class FakeClock: PlaybackClock, @unchecked Sendable { var t: Double = 0; func nowSeconds() -> Double { t } }
final class Recorder: FrameSink, @unchecked Sendable {
    private let l = NSLock(); var shown: [Double] = []; var showWalls: [Double] = []
    let clock: FakeClock
    init(_ c: FakeClock) { clock = c }
    func show(_ f: SourceFrame) async -> Bool { l.lock(); shown.append(f.ptsSeconds); showWalls.append(clock.t); l.unlock(); return true }
    func show(_ f: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool { await show(f) }
    func snapshot() -> ([Double], [Double]) { l.lock(); defer { l.unlock() }; return (shown, showWalls) }
}
final class ScriptedSource: FrameSource, @unchecked Sendable {
    private let l = NSLock()
    private var script: [Double] = []; private var idx = 0; private var endWhenDrained = false
    func setScript(_ pts: [Double], end: Bool) { l.lock(); script = pts; idx = 0; endWhenDrained = end; l.unlock() }
    func nextEvent() async -> SourceEvent {
        l.lock()
        defer { l.unlock() }
        guard idx < script.count else { return endWhenDrained ? .ended(.endOfStream) : .temporarilyUnavailable }
        let pts = script[idx]; idx += 1
        return .frame(SourceFrame(ptsSeconds: pts, durationSeconds: 0.04, digest: "d\(pts)"))
    }
}

@main struct SeekPacingTests {
    static func scenario(_ name: String, pre: [Double], post: [Double], gap: Double,
                         expectShown: [Double]) async {
        let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource()
        src.setScript(pre, end: false)
        // Fake sleep must YIELD the executor (non-suspending async tight-loops
        // starve a small vCPU pool); the fake clock advances by the full wait.
        let pump = FramePump(source: src, sink: rec, clock: clock) { seconds in
            try? await Task.sleep(nanoseconds: 100_000); clock.t += seconds; return true
        }
        let run = Task { await pump.run() }
        while rec.snapshot().0.count < pre.count { try? await Task.sleep(nanoseconds: 2_000_000) }
        let ok = await pump.resetPresentation()
        expect(ok, "\(name): resetPresentation accepted (stateless source)")
        clock.t += gap                              // measured late-start gap: REAL wall time
        let wallAtLanding = clock.t
        src.setScript(post, end: true)
        let stats = await run.value
        let (shown, walls) = rec.snapshot()
        expect(shown == expectShown, "\(name): shown \(shown) == expected \(expectShown)")
        expect(stats.dropped == 0, "\(name): zero drops (got \(stats.dropped))")
        // First post-seek frame shows AT arrival wall (gap preserved, no
        // seek-distance wait): its show wall == landing wall exactly.
        if let i = shown.firstIndex(of: post[0]) {
            // On arrival = within ONE starve-backoff interval (0.05s) of
            // landing, NOT after the seek distance (forward old: +4.65s)
            // and not dropped (backward old: drop-storm to EOF).
            let lateness = walls[i] - wallAtLanding
            expect(lateness >= 0 && lateness <= 0.06, "\(name): first post-seek frame shown on arrival (lateness \(lateness)s, must be <= one backoff)")
        }
        log("\(name): shown=\(shown) drops=\(stats.dropped) waits=\(stats.waits)")
    }
    static func main() async {
        // MediaWallAnchor math: same anchor, canonical vs +100ms edit-list audio.
        let anchor = MediaWallAnchor(mediaSeconds: 5.0, wallSeconds: 2.0)
        expect(anchor.scheduledWall(forMediaSeconds: 5.0) == 2.0, "canonical: first pcm at target schedules at commit wall (0 wait)")
        expect(abs(anchor.scheduledWall(forMediaSeconds: 5.1) - 2.1) < 1e-9, "+100ms fixture: first pcm schedules 100ms after commit wall")
        expect(anchor.scheduledWall(forMediaSeconds: 5.3) == 2.3, "video keyframe at +0.3 schedules +0.3 (legitimate gap, not flattened)")

        await scenario("forward", pre: [0, 0.04, 0.08], post: [5.0, 5.04, 5.08], gap: 0.35,
                       expectShown: [0, 0.04, 0.08, 5.0, 5.04, 5.08])
        await scenario("backward", pre: [0, 0.04], post: [0.02, 0.06, 0.10], gap: 0.20,
                       expectShown: [0, 0.04, 0.02, 0.06, 0.10])
        // Explicit shared anchor: first post-seek frame pts = target+0.3 must
        // WAIT 0.3 (legitimate keyframe gap honored), not flatten to arrival.
        do {
            let clock = FakeClock(); let rec = Recorder(clock); let src = ScriptedSource()
            src.setScript([0, 0.04], end: false)
            let pump = FramePump(source: src, sink: rec, clock: clock) { seconds in
                try? await Task.sleep(nanoseconds: 100_000); clock.t += seconds; return true
            }
            let run = Task { await pump.run() }
            while rec.snapshot().0.count < 2 { try? await Task.sleep(nanoseconds: 2_000_000) }
            let ok = await pump.resetPresentation(seekAnchorSeconds: 5.0)
            expect(ok, "keyframeGap: resetPresentation with anchor accepted")
            clock.t += 0.15                       // wall gap before frames land
            let landing = clock.t
            src.setScript([5.3, 5.34], end: true)
            _ = await run.value
            let (shown, walls) = rec.snapshot()
            expect(shown == [0, 0.04, 5.3, 5.34], "keyframeGap: shown \(shown)")
            if let i = shown.firstIndex(of: 5.3) {
                // Frame lands at landing (anchor+0.15), scheduled at anchor+0.3:
                // honored = shows at ~anchor+0.3 (lateness ~0.15); flattened =
                // shows at arrival (lateness <= one backoff 0.06).
                let lateness = walls[i] - landing
                expect(lateness > 0.1 && lateness <= 0.25, "keyframeGap: +0.3 pts gap honored as real wait past arrival (lateness \(lateness)s; flattened would be <=0.06)")
            }
            print("keyframeGap: shown=\(shown)")
        }
        if failures == 0 { log("ALL_CHECKS_PASS") } else { log("FAILURES=\(failures)") }
    }
}
