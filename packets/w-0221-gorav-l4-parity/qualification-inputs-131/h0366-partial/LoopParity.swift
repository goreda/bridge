import Foundation

// Drives the REAL FramePump (pinned PlaybackCore.swift) on a virtual monotonic clock.
final class VClock: PlaybackClock, @unchecked Sendable {
    private let l = NSLock(); private var t: Double
    init(_ t: Double) { self.t = t }
    func nowSeconds() -> Double { l.withLock { t } }
    func advance(_ d: Double) { l.withLock { t += d } }
}
enum Step { case frame(SourceFrame, Double), starve(Double), end }
final class ScriptSource: FrameSource, @unchecked Sendable {
    private let l = NSLock(); private var steps: [Step]; let clock: VClock
    init(_ s: [Step], _ c: VClock) { steps = s; clock = c }
    func nextEvent() async -> SourceEvent {
        let s: Step = l.withLock { steps.isEmpty ? Step.end : steps.removeFirst() }
        switch s {
        case .frame(let f, let adv): clock.advance(adv); return .frame(f)
        case .starve(let adv): clock.advance(adv); return .temporarilyUnavailable
        case .end: return .ended(.sourceEnded)
        }
    }
}
final class RecSink: FrameSink, @unchecked Sendable {
    private let l = NSLock(); let clock: VClock; let commit: CancelCommit?; let refusePts: Double?
    var shown: [(Double, Double)] = []
    init(_ c: VClock, _ commit: CancelCommit?, refusePts: Double? = nil) { clock = c; self.commit = commit; self.refusePts = refusePts }
    func show(_ f: SourceFrame) async -> Bool {
        if f.ptsSeconds == refusePts { return false }
        let w = clock.nowSeconds(); l.withLock { shown.append((f.ptsSeconds, w)) }; return true
    }
    func show(_ f: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        guard commit!._testMayFinishConsume(ticket: admission) else { return false }
        return await show(f)
    }
}

struct Frame: Decodable { let pts: Dbl; let dur: Double; let adv: Double? }
struct Dbl: Decodable { let v: Double
    init(from d: Decoder) throws { let c = try d.singleValueContainer()
        if let s = try? c.decode(String.self) { v = s == "nan" ? .nan : (s == "inf" ? .infinity : -.infinity) } else { v = try c.decode(Double.self) } } }
struct Phase: Decodable { let reset: String?; let seekAnchor: Double?; let frames: [Frame] }
struct Expect: Decodable {
    let shown: [[Double]]; let dropped: Int; let waits: Int
    let outOfOrderDrops: Int?; let nonFiniteDrops: Int?; let fencedShows: Int?; let starveWaits: Int?
}
struct Scenario: Decodable { let name: String; let startWall: Double; let maxWait: Double; let refusePts: Double?
    let phases: [Phase]; let expect: Expect }
struct Corpus: Decodable { let schema: Int; let scenarios: [Scenario] }

var failures = 0
func fail(_ s: String) { failures += 1; print("FAIL " + s) }
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

func runScenario(_ sc: Scenario, commitMode: Bool) async {
    let clock = VClock(sc.startWall)
    let commit: CancelCommit? = commitMode ? CancelCommit() : nil
    let sink = RecSink(clock, commit, refusePts: sc.refusePts)
    final class Box: @unchecked Sendable { var src: ScriptSource? }
    let box = Box()
    final class Fwd: FrameSource, @unchecked Sendable { let b: Box; init(_ b: Box) { self.b = b }
        func nextEvent() async -> SourceEvent { await b.src!.nextEvent() } }
    let pump = FramePump(source: Fwd(box), sink: sink, clock: clock, decider: AVSyncDecider(maxWaitSeconds: sc.maxWait),
                         ledger: TimingLedger(), commit: commit, onWait: { d in clock.advance(d); return true })
    var tot = (dropped: 0, waits: 0, ooo: 0, nf: 0, fenced: 0, starve: 0)
    for ph in sc.phases {
        if let r = ph.reset { _ = await pump.resetPresentation(seekAnchorSeconds: r == "seek" ? ph.seekAnchor : nil) }
        var st: [Step] = []
        for f in ph.frames { st.append(.frame(SourceFrame(ptsSeconds: f.pts.v, durationSeconds: f.dur, digest: "d\(f.pts.v)"), f.adv ?? 0)) }
        box.src = ScriptSource(st, clock)
        let s = await pump.run()
        tot.dropped += s.dropped; tot.waits += s.waits; tot.ooo += s.outOfOrderDrops; tot.nf += s.nonFiniteDrops
        tot.fenced += s.fencedShows; tot.starve += s.starveWaits
    }
    let tag = "\(sc.name)[\(commitMode ? "commit" : "plain")]"
    let e = sc.expect
    if sink.shown.count != e.shown.count { fail("\(tag) shown count \(sink.shown.count) != \(e.shown.count): \(sink.shown)") }
    else { for (i, x) in e.shown.enumerated() where !(close(sink.shown[i].0, x[0]) && close(sink.shown[i].1, x[1])) {
        fail("\(tag) shown[\(i)] (pts,wall) \(sink.shown[i]) != \(x)") } }
    if tot.dropped != e.dropped { fail("\(tag) dropped \(tot.dropped) != \(e.dropped)") }
    if tot.waits != e.waits { fail("\(tag) waits \(tot.waits) != \(e.waits)") }
    if let x = e.outOfOrderDrops, tot.ooo != x { fail("\(tag) outOfOrderDrops \(tot.ooo) != \(x)") }
    if let x = e.nonFiniteDrops, tot.nf != x { fail("\(tag) nonFiniteDrops \(tot.nf) != \(x)") }
    if let x = e.fencedShows, tot.fenced != x { fail("\(tag) fencedShows \(tot.fenced) != \(x)") }
}

// Code-driven scenarios (need callbacks inside the pump's wait).
func runCancelInWait() async {
    let clock = VClock(100); let sink = RecSink(clock, nil)
    let src = ScriptSource([.frame(SourceFrame(ptsSeconds: 0, durationSeconds: 0.25, digest: "a"), 0),
                            .frame(SourceFrame(ptsSeconds: 0.25, durationSeconds: 0.25, digest: "b"), 0)], clock)
    let pump = FramePump(source: src, sink: sink, clock: clock, decider: AVSyncDecider(), onWait: { _ in false })
    let s = await pump.run()
    if !(s.cancelled && s.endReason == .cancelled && s.shown == 1 && s.waits == 1) { fail("cancelInWait \(s)") }
}
func runSeekDuringWait(commitMode: Bool) async {
    let clock = VClock(100); let commit: CancelCommit? = commitMode ? CancelCommit() : nil
    let sink = RecSink(clock, commit)
    func f(_ p: Double) -> Step { .frame(SourceFrame(ptsSeconds: p, durationSeconds: 0.25, digest: "p\(p)"), 0) }
    let src = ScriptSource([f(0), f(0.25), f(50.25), f(50.5)], clock)
    final class PBox: @unchecked Sendable { var p: FramePump?; var n = 0 }
    let pb = PBox()
    let pump = FramePump(source: src, sink: sink, clock: clock, commit: commit, onWait: { d in
        pb.n += 1
        if pb.n == 1 { _ = await pb.p!.resetPresentation(seekAnchorSeconds: 50) }  // seek lands DURING the pacing wait
        clock.advance(d); return true })
    pb.p = pump
    let s = await pump.run()
    let want: [(Double, Double)] = [(0, 100), (50.25, 100.25), (50.5, 100.5)]
    let tag = "seekDuringWait[\(commitMode ? "commit" : "plain")]"
    if sink.shown.count != 3 || zip(sink.shown, want).contains(where: { !(close($0.0, $1.0) && close($0.1, $1.1)) }) { fail("\(tag) shown \(sink.shown)") }
    if s.seekStalePulls != 1 { fail("\(tag) seekStalePulls \(s.seekStalePulls) != 1") }
}

@main struct LoopParity {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("one corpus path required") }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard corpus.schema == 1, corpus.scenarios.count == 17 else { fatalError("unexpected loop corpus schema or scenario count") }
        for sc in corpus.scenarios { await runScenario(sc, commitMode: false); await runScenario(sc, commitMode: true) }
        await runCancelInWait()
        await runSeekDuringWait(commitMode: false); await runSeekDuringWait(commitMode: true)
        let n = corpus.scenarios.count * 2 + 3
        if failures > 0 { print("loop parity: \(failures) failure(s)"); exit(1) }
        print("loop parity: \(corpus.scenarios.count) corpus scenarios x {plain,commit} + 3 code-driven = \(n) runs, 0 fail")
    }
}
