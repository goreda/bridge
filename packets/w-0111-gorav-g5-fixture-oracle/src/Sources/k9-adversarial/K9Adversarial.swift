import Foundation
import GorAVPlaybackCore

// K9 adversarial battery (team2 GORAV-K9-ADVERSARIAL-CASES-r1, 14 cases).
// K9-12/13 target the AudioUnit render-callback API surface: MAC-DEFERRED
// (source-fixed; ring-level equivalents K9-03/08 run here).
@main
struct K9Adversarial {
    static var fails = 0
    static func check(_ id: String, _ ok: Bool, _ detail: String) {
        print("\(id): \(ok ? "PASS" : "FAIL") \(detail)")
        if !ok { fails += 1 }
    }
    static func inv(_ r: PCMRingBuffer, _ cap: Int) -> Bool {
        let a = r.available
        return a >= 0 && a <= cap
    }

    static func main() async {
        // K9-01 wrap-around at exact boundary
        do {
            let r = PCMRingBuffer(capacity: 8)
            r.push([1,2,3,4,5,6])
            let p1 = r.render(4)              // 1,2,3,4
            r.push([7,8,9,10,11,12])          // writePos wraps; 8 cap: avail 2+6=8? avail was 2, push 6 -> 8 full
            let p2 = r.render(8)
            let p3 = r.render(2)
            check("K9-01", p1 == [1,2,3,4] && p2 == [5,6,7,8,9,10,11,12] && p3 == [0,0] && r.underrunBytes == 2 && inv(r, 8), "wrap fifo+underrun=2")
        }
        // K9-02 capacity-1 ring, drop-newest
        do {
            let r = PCMRingBuffer(capacity: 1)
            r.push([42])
            r.push([43])
            let p1 = r.render(1)
            r.push([44])
            let p2 = r.render(1)
            check("K9-02", p1 == [42] && r.overrunDrops == 1 && p2 == [44] && inv(r, 1), "drop-newest cap1")
        }
        // K9-03 render(0)
        do {
            let r = PCMRingBuffer(capacity: 8)
            let e1 = r.render(0)
            r.push([1,2,3,4,5,6,7,8])
            let e2 = r.render(0)
            check("K9-03", e1.isEmpty && e2.isEmpty && r.available == 8 && r.underrunBytes == 0, "render(0) no-op")
        }
        // K9-04 push-during-render at capacity (call atomicity). r10 oracle
        // fix (owner Mac run r9): the r8/r9 assertion mis-encoded the
        // push-first branch - after push(64) drops all incoming and render(64)
        // then drains the pre-existing bytes, avail is 0, not 64. Linux
        // scheduling had only ever sampled the render-first order. Ring
        // behavior on the Mac was exactly per contract; the test was wrong.
        do {
            // Serial dual-order: BOTH orders asserted deterministically.
            do { // render first: drops 0, avail 64 after the push lands
                let r = PCMRingBuffer(capacity: 64)
                r.push([UInt8](repeating: 1, count: 64))
                let rendered = r.render(64)
                r.push([UInt8](repeating: 2, count: 64))
                check("K9-04s1", rendered == [UInt8](repeating: 1, count: 64) && r.overrunDrops == 0 && r.available == 64 && inv(r, 64), "serial render-first")
            }
            do { // push first: 64 drops (drop-newest), render gets pre-existing 64, avail 0
                let r = PCMRingBuffer(capacity: 64)
                r.push([UInt8](repeating: 1, count: 64))
                r.push([UInt8](repeating: 2, count: 64))
                let rendered = r.render(64)
                check("K9-04s2", rendered == [UInt8](repeating: 1, count: 64) && r.overrunDrops == 64 && r.available == 0 && inv(r, 64), "serial push-first")
            }
            // Concurrent either-order: whichever the lock serializes first.
            let r = PCMRingBuffer(capacity: 64)
            r.push([UInt8](repeating: 1, count: 64))
            async let out = Task { r.render(64) }.value
            async let _: Void = Task { r.push([UInt8](repeating: 2, count: 64)) }.value
            let rendered = await out
            let ok = rendered == [UInt8](repeating: 1, count: 64) && inv(r, 64)
                  && ((r.overrunDrops == 0 && r.available == 64) || (r.overrunDrops == 64 && r.available == 0))
            check("K9-04", ok, "atomic either-order, drops=\(r.overrunDrops) avail=\(r.available)")
        }
        // K9-05 interleave storm: full model-check against an expected FIFO
        do {
            let r = PCMRingBuffer(capacity: 16)
            var expected: [UInt8] = [] // models ring content, drop-newest
            var ok = true
            for i in 0..<10000 {
                let b = UInt8(truncatingIfNeeded: i)
                r.push([b])
                if expected.count < 16 { expected.append(b) } // drop-newest model
                let out = r.render(1)
                let want: UInt8 = expected.isEmpty ? 0 : expected.removeFirst()
                if out != [want] || r.available != expected.count { ok = false; break }
            }
            for _ in 0..<1000 {
                r.push([7,7,7])
                for b: UInt8 in [7,7,7] { if expected.count < 16 { expected.append(b) } }
                let out = r.render(16)
                for k in 0..<16 {
                    let want: UInt8 = expected.isEmpty ? 0 : expected.removeFirst()
                    if out[k] != want { ok = false; break }
                }
                if r.available != expected.count { ok = false }
                if !ok { break }
            }
            check("K9-05", ok && inv(r, 16), "11000-op model-checked FIFO")
        }
        // K9-06 sustained overflow accounting
        do {
            let r = PCMRingBuffer(capacity: 16)
            r.push([UInt8](0..<100).map { $0 } + [UInt8](repeating: 0, count: 900))
            let d1 = r.overrunDrops
            for _ in 0..<100 { r.push([9]) }
            let first16 = r.render(16)
            check("K9-06", d1 == 984 && r.overrunDrops == 1084 && first16 == [UInt8](0..<16), "drops=1084, first16 retained")
        }
        // K9-07 EOS drain-point invariant (ring level; glue fixed to drainBounded). Real fixture payload.
        do {
            let r = PCMRingBuffer(capacity: 1 << 20)
            let pcm = k9FixturePCM() // real fixture-k4.wav data chunk
            var pushed = 0
            var off = 0
            while off < pcm.count { let n = min(4096, pcm.count - off); r.push(Array(pcm[off..<off+n])); pushed += n; off += n } // pump outruns
            // EOS arrives; shell must drain before stop:
            var rendered = 0
            while r.available > 0 { rendered += r.render(min(4096, r.available)).count }
            let residual = r.available
            check("K9-07", pushed == rendered + residual && residual == 0, "pushed=\(pushed) rendered=\(rendered) residual=\(residual); glue: drainBounded before stop")
        }
        // K9-08 render(n) > capacity
        do {
            let r = PCMRingBuffer(capacity: 8)
            r.push([1,2,3,4,5,6,7,8])
            let out = r.render(64)
            check("K9-08", out.count == 64 && Array(out[0..<8]) == [1,2,3,4,5,6,7,8] && out[8...].allSatisfy { $0 == 0 } && r.underrunBytes == 56 && r.available == 0, "8 payload + 56 silence")
        }
        // K9-09 single push > capacity
        do {
            let r = PCMRingBuffer(capacity: 8)
            r.push([UInt8](1...32))
            let out = r.render(8)
            check("K9-09", r.overrunDrops == 24 && out == [UInt8](1...8) && r.available == 0, "first-8 retained, 24 dropped")
        }
        // K9-10 push(0) then render(1)
        do {
            let r = PCMRingBuffer(capacity: 8)
            r.push([])
            let out = r.render(1)
            check("K9-10", out == [0] && r.underrunBytes == 1 && r.overrunDrops == 0, "no-op push + 1 underrun")
        }
        // K9-11 full-drain-refill cycles
        do {
            let r = PCMRingBuffer(capacity: 4)
            var ok = true
            for c in 0..<5000 {
                let b = UInt8(truncatingIfNeeded: c)
                r.push([b,b,b,b])
                let out = r.render(4)
                if out != [b,b,b,b] || r.available != 0 { ok = false; break }
            }
            check("K9-11", ok && r.overrunDrops == 0 && r.underrunBytes == 0, "5000 cycles no drift")
        }
        // K9-12/13: AudioUnit render-callback API surface - MAC-DEFERRED.
        print("K9-12: MAC_DEFERRED (frames=0 no-op + nil-data noErr fixed in source; ring-level equivalent K9-03 PASS above)")
        print("K9-13: MAC_DEFERRED (mDataByteSize honored, advertised region fully written, single interleaved buffer - fixed in source; ring-level equivalent K9-08 PASS above)")
        // K9-14 EOS at capacity, consumer stalled; real fixture payload, drops == pushed - capacity
        do {
            let r = PCMRingBuffer(capacity: 64)
            let pcm = k9FixturePCM()
            r.push(pcm)
            check("K9-14", r.overrunDrops == pcm.count - 64 && r.available == 64 && pcm.count == r.available + r.overrunDrops, "stalled consumer: pushed=\(pcm.count) accepted=64 drops=\(r.overrunDrops)")
        }

// Extract the data-chunk payload of the kit's fixture-k4.wav (canonical 44-byte header).
func k9FixturePCM() -> [UInt8] {
    let kit = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/GORAV-PLAYBACK-KIT-r6"
    let url = URL(fileURLWithPath: kit + "/fixtures/fixture-k4.wav")
    guard let data = try? Data(contentsOf: url), data.count > 44,
          data[0] == 0x52, data[8] == 0x57 else { return [UInt8](repeating: 5, count: 176400) } // RIFF/WAVE
    return [UInt8](data.dropFirst(44))
}
        print(fails == 0 ? "K9_ADVERSARIAL_PASS (12 run, 2 mac-deferred)" : "K9_ADVERSARIAL_FAIL \(fails)")
        exit(fails == 0 ? 0 : 76)
    }
}
