import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

// Witness for the R5 decoded frame tap: rate limiting, bounded queue with
// evict-oldest overflow, FIFO consumption, latest readback, stale-session
// fencing, counter exactness.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func frame(_ session: UInt64, _ pts: Int64) -> NativeFrame {
    NativeFrame(session: session, handle: UInt64(pts + 1), pts: pts, duration: 33_333,
                width: 320, height: 240, pixelFormatName: "yuv420p", isKeyFrame: pts == 0)
}

// T1: rate limiting at 10 fps (100ms): frames at 0, 50, 100, 210ms
var tap = DecodedFrameTap(session: 7, capacity: 4, maxPerSecond: 10)
check("T1-first-accepted", tap.offer(frame(7, 0), clockNow: 0) == .accepted)
check("T1-too-soon-dropped", tap.offer(frame(7, 50), clockNow: 0.05) == .droppedRateLimit)
check("T1-at-limit-accepted", tap.offer(frame(7, 100), clockNow: 0.10) == .accepted)
check("T1-drop-count", tap.counters.droppedRateLimit == 1 && tap.counters.accepted == 2)

// T2: overflow evicts oldest, keeps tap live
var t2 = DecodedFrameTap(session: 7, capacity: 2, maxPerSecond: 0)
check("T2-fill1", t2.offer(frame(7, 1), clockNow: 0) == .accepted)
check("T2-fill2", t2.offer(frame(7, 2), clockNow: 0) == .accepted)
check("T2-overflow-evicts", t2.offer(frame(7, 3), clockNow: 0) == .acceptedEvictingOldest)
check("T2-depth-bounded", t2.depth == 2)
check("T2-oldest-evicted", t2.next()?.pts == 2)   // pts 1 was evicted
check("T2-counters", t2.counters.evictedOldest == 1 && t2.counters.accepted == 3)
check("T2-drain-fifo", t2.next()?.pts == 3 && t2.next() == nil)

// T3: stale session fenced
var t3 = DecodedFrameTap(session: 7, capacity: 2, maxPerSecond: 0)
check("T3-stale-refused", t3.offer(frame(8, 1), clockNow: 0) == .refusedStaleSession)
check("T3-stale-not-queued", t3.depth == 0 && t3.counters.refusedStaleSession == 1)

// T4: latest readback is the newest ACCEPTED frame and counts reads
var t4 = DecodedFrameTap(session: 7, capacity: 4, maxPerSecond: 10)
_ = t4.offer(frame(7, 10), clockNow: 0)
_ = t4.offer(frame(7, 20), clockNow: 0.05) // rate-dropped
check("T4-readback-newest-accepted", t4.latestForReadback()?.pts == 10)
_ = t4.offer(frame(7, 30), clockNow: 0.10)
check("T4-readback-updates", t4.latestForReadback()?.pts == 30)
check("T4-readback-count", t4.counters.readbacks == 2)

// T5: non-finite clock never blocks (one-clock rule parity with the timePos gate)
var t5 = DecodedFrameTap(session: 7, capacity: 4, maxPerSecond: 1)
check("T5-nan-accepted-1", t5.offer(frame(7, 1), clockNow: .nan) == .accepted)
check("T5-nan-accepted-2", t5.offer(frame(7, 2), clockNow: .nan) == .accepted)
// ...but a finite sample after NaNs starts the interval fresh
check("T5-finite-anchors", t5.offer(frame(7, 3), clockNow: 10.0) == .accepted)
check("T5-finite-then-dropped", t5.offer(frame(7, 4), clockNow: 10.5) == .droppedRateLimit)

print("frame-tap-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
