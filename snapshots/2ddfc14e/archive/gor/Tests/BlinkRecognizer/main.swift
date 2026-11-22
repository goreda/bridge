// swiftc -O Extracted.swift main.swift -o rec && ./rec     (Extracted.swift = bottom of ScreenCaptureEngine.swift, tracker + recognizer, unmodified)
import Foundation
var fails = 0
func check(_ n: String, _ c: Bool) { print(c ? "ok  " : "FAIL", n); if !c { fails += 1 } }
typealias S = (t: Double, r: Double?)
func run(_ samples: [S]) -> [BlinkDetection?] {
    var tr = BlinkEpisodeTracker(); var out: [BlinkDetection?] = []
    for s in samples {
        let c: Bool? = s.r.map { $0 < 0.70 }
        let fed = tr.feed(t: s.t, ratio: s.r, closing: c)
        if let e = fed.event { out.append(BlinkRecognizer.classify(e)) }
    }
    return out
}
func warm(_ n: Int, gap: Double) -> [S] { (0..<n).map { (Double($0) * gap, 1.0) } }
func after(_ w: [S], _ gap: Double, _ rs: [Double?]) -> [S] {
    var t = w.last!.t; var o = w
    for r in rs { t += gap; o.append((t, r)) }
    return o
}
// A: 15 Hz, 3 closed samples, reopen -> confirmed
var d = run(after(warm(12, gap: 0.066), 0.066, [0.4, 0.4, 0.4, 1.0]))
check("A 15Hz blink confirmed", d.count == 1 && d[0]?.kind == .confirmed && d[0]!.nClosed == 3)
// B: 10 Hz, single closed sample -> possible (cannot be told from jitter)
d = run(after(warm(12, gap: 0.1), 0.1, [0.4, 1.0]))
check("B 10Hz single dip possible", d.count == 1 && d[0]?.kind == .possible)
// C: closed 0.5 s span then reopen -> too long for a blink, not abandoned: no detection
d = run(after(warm(12, gap: 0.1), 0.1, [0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 1.0]))
check("C 0.5 s closure not a blink", d.count == 1 && d[0] == nil)
// D: held closed past 0.6 s with many samples -> held, emitted once, reopen emits nothing more
d = run(after(warm(12, gap: 0.1), 0.1, [0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 1.0]))
check("D held closure once", d.count == 1 && d[0]?.kind == .held)
// E: unusable sample inside -> possible, never confirmed
var e = after(warm(12, gap: 0.04), 0.04, [0.4, nil, 0.4, 1.0])
d = run(e)
check("E unusable inside possible", d.count == 1 && d[0]?.kind == .possible)
// F: young baseline (3 open samples only) -> possible
d = run(after(warm(3, gap: 0.04), 0.04, [0.4, 0.4, 0.4, 0.4, 1.0]))
check("F young baseline possible", d.count == 1 && d[0]?.kind == .possible)
// G: 30 Hz single-sample dip (about 66 ms window) is shorter than any blink -> rejected
d = run(after(warm(12, gap: 0.033), 0.033, [0.4, 1.0]))
check("G 66 ms dip rejected", d.count == 1 && d[0] == nil)
// H: 30 Hz real blink (6 closed samples ~0.2 s) confirmed
d = run(after(warm(12, gap: 0.033), 0.033, [0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 1.0]))
check("H 30Hz 0.2 s blink confirmed", d.count == 1 && d[0]?.kind == .confirmed)
// I: no blink at all -> no events
d = run(warm(40, gap: 0.05))
check("I no dip no event", d.isEmpty)
// J: reset clears an open episode
var tr = BlinkEpisodeTracker(); _ = tr.feed(t: 0, ratio: 0.4, closing: true); tr.reset()
let after0 = tr.feed(t: 0.1, ratio: 1.0, closing: false)
check("J reset drops the open episode", after0.event == nil)
let sparseEvent = BlinkEpisodeTracker.Event(end:"reopened",t0:1,t1:2,durS:1,closedSpanS:0.2,nClosed:2,minRatio:0.4,maxGapS:0.8,unusableInside:0,tBefore:0.8,baselineYoung:false,inBlinkRange:false)
check("K unbounded gap never confirmed", BlinkRecognizer.classify(sparseEvent)?.kind == .possible)
check("L point samples never assert physical continuous duration", BlinkRecognizer.classify(sparseEvent)?.durMinS == 0)
print(fails == 0 ? "ALL PASS" : "FAILURES \(fails)"); exit(fails == 0 ? 0 : 1)
