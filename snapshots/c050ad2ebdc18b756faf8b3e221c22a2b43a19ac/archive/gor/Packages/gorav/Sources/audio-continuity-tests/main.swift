// audio-continuity-tests: the converted-audio PTS gate tolerance unit.
// Exact values measured 2026-11-16 on the live mux HLS segment leg
// (plan/evidence/2026-11-16-hls-candidate/, run-segment.log): a 90 kHz
// mpegts audio timebase whose PTS ladder is not sample-aligned; per-frame
// offsets from a sample-exact cursor oscillate within +/-0.61 samples
// (probe: 63 frames, max |61|/4410000 s) and never accumulate. The gate
// must treat sub-sample differences as continuous: they cannot be
// gap-filled (gap fill works in whole samples) and signal no missing audio.
import Foundation
import GorAVCore
import GorAVFFmpegAdapter
import GorAVNativeProbeKit

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

do {
    // The exact measured leg-2 failure values.
    let actual = try RationalTime(value: 33583, timescale: 3000)
    let expected = try RationalTime(value: 49366951, timescale: 4410000)
    let containerTick = try RationalTime(value: 1, timescale: 90000)  // mpegts audio time_base
    let rate: Int32 = 44100

    let diff = try AudioMediaTime.subtract(actual, expected)
    check("measured difference is exactly 59/4410000 s",
          diff == (try RationalTime(value: 59, timescale: 4410000)))
    check("measured difference exceeds one container tick (why the gate fired)",
          diff > containerTick)

    let oneSample = try RationalTime(value: 1, timescale: rate)
    check("measured difference is sub-sample (0.59 samples)",
          diff < oneSample)

    // The gate tolerance must absorb sub-sample differences on a 90 kHz
    // container clock.
    let tick = try AudioMediaTime.continuityTick(containerTimebase: containerTick, audioRate: rate)
    check("90kHz container: tolerance is one audio sample",
          tick == oneSample)
    let negTick = try RationalTime(value: -tick.value, timescale: tick.timescale)
    check("measured sub-sample difference passes the gate",
          diff < tick && diff > negTick)

    // Probe maximum over 63 frames of the same segment: 61/4410000 s.
    let probeMax = try RationalTime(value: 61, timescale: 4410000)
    check("probe maximum sub-sample drift passes the gate",
          probeMax < tick)

    // Matroska case from the original comment: a 1 ms container tick is
    // coarser than one sample and stays the tolerance.
    let mkvTick = try RationalTime(value: 1, timescale: 1000)
    check("1ms container: tolerance stays one container tick",
          (try AudioMediaTime.continuityTick(containerTimebase: mkvTick, audioRate: rate)) == mkvTick)

    // A real one-frame discontinuity (1024 samples) still trips the gate.
    let frameGap = try RationalTime(value: 1024, timescale: rate)
    check("one-frame discontinuity still trips the gate",
          frameGap > tick)

    // Negative side symmetric.
    let neg = try RationalTime(value: -59, timescale: 4410000)
    check("negative sub-sample difference passes the gate", neg > negTick)
} catch {
    print("FAIL setup threw: \(error)")
    failures += 1
}
print(failures == 0 ? "audio-continuity-tests: all pass" : "audio-continuity-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
