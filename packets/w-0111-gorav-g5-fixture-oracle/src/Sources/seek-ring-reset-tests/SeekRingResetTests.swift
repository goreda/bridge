// M4 seek ring-reset PROTOCOL test (Linux): exercises the exact quiescence +
// in-place reset protocol the Mac sink performs (design C) against the REAL
// PlaybackCore primitives (GenerationFence + SPSCPCMRing + reader thread
// standing in for the RT render callback). No AudioUnit on Linux: the reader
// thread + join is the quiescence witness here; on Mac it is
// AudioOutputUnitStop's no-callback-after-return guarantee. Invariants:
//   1. No pre-reset bytes are readable post-reset (residual drained by reset).
//   2. Stale generation is fenced (checkRT false, fenced count advances).
//   3. New generation resumes immediately with correct bytes.
//   4. resetForNewGeneration is safe repeatedly (no slot/state exhaustion).
//   5. Ring counters reflect the retired generation via snapshotReceipt.
import GorAVPlaybackCore
import Foundation

var failures = 0
func expect(_ c: Bool, _ m: String) { if !c { failures += 1; print("FAIL \(m)") } }

let capacity = 4096, sr = 44100, ch = 2, bps = 2
let ring = SPSCPCMRing(capacityFrames: 1 << 12)!
let fence = GenerationFence()
fence.setActive(1)

final class Box: @unchecked Sendable { var readBytes: [UInt8] = []; var preResetSeen = false; var lock = NSLock() }
let box = Box()
final class Flag: @unchecked Sendable {
    private let l = NSLock(); private var v = false
    func load() -> Bool { l.lock(); defer { l.unlock() }; return v }
    func store(_ n: Bool) { l.lock(); v = n; l.unlock() }
}
let stopFlag = Flag()

// RT-stand-in reader: drains whatever the ring has, paced like a callback.
func spawnReader(_ gen: UInt64) -> Thread {
    let t = Thread { [ring, fence, box, stopFlag] in
        var tmp = [UInt8](repeating: 0, count: 512)
        while !stopFlag.load() {
            guard fence.checkRT(gen) else { Thread.sleep(forTimeInterval: 0.001); continue }  // stale fence -> silence
            // render returns the UNDERRUN frame count and zero-fills the rest
            // (bounded-silence design); real bytes = (128 - under) * 4.
            let under = tmp.withUnsafeMutableBufferPointer { ring.render(into: $0.baseAddress!, frames: 128) }
            let realB = (128 - Int(under)) * 4
            if realB > 0 { box.lock.lock(); box.readBytes.append(contentsOf: tmp[0..<realB]); box.lock.unlock() }
            else { Thread.sleep(forTimeInterval: 0.001) }
        }
    }
    t.start()
    return t
}

// Generation 1: push pre-reset PCM (pattern A), run reader briefly.
let patternA = [UInt8](repeating: 0xA5, count: 2048)
patternA.withUnsafeBufferPointer { _ = ring.push($0) }
let reader1 = spawnReader(1)
Thread.sleep(forTimeInterval: 0.02)
stopFlag.store(true); while !reader1.isFinished { Thread.sleep(forTimeInterval: 0.001) }  // quiescence witness (AudioOutputUnitStop on Mac)
stopFlag.store(false)
// Force a deterministic residual: push more gen-1 bytes AFTER the reader is
// quiesced (producer may push; consumer stopped) so the reset provably
// discards unread pre-reset bytes.
patternA.withUnsafeBufferPointer { _ = ring.push($0) }
expect(ring.availableFrames > 0, "residual present pre-reset")

let receiptPre = ring.snapshotReceipt(generation: 1)
expect(receiptPre.pushCount >= 1, "pre-reset push visible")

// RESET (design C): fence advance -> in-place reset -> resume.
fence.setActive(2)
let fencedStale = fence.checkRT(1)   // a late gen-1 record must fence
expect(!fencedStale, "stale generation fenced post-advance")
expect(fence.fencedCount >= 1, "fenced counter advanced")
ring.resetForNewGeneration()
expect(ring.availableFrames == 0, "no residual bytes post-reset")

// Generation 2: reader resumes; push post-reset PCM (pattern B).
let patternB = [UInt8](repeating: 0x5A, count: 1024)
let boxStart = box.readBytes.count
let reader2 = spawnReader(2)
patternB.withUnsafeBufferPointer { _ = ring.push($0) }
Thread.sleep(forTimeInterval: 0.05)
stopFlag.store(true); while !reader2.isFinished { Thread.sleep(forTimeInterval: 0.001) }
let post = Array(box.readBytes.dropFirst(boxStart))
expect(post.count >= 512, "post-reset bytes read (got \(post.count))")
expect(!post.contains(0xA5), "no pre-reset pattern A leaked post-reset")
expect(post.allSatisfy { $0 == 0x5A }, "post-reset bytes are pattern B")
expect(fence.checkRT(2), "active generation admitted")

// Repeated reset safety (seek-after-seek): two more generations, no exhaustion.
fence.setActive(3); ring.resetForNewGeneration()
expect(ring.availableFrames == 0, "second reset leaves no residual")
fence.setActive(4); ring.resetForNewGeneration()
expect(fence.checkRT(4), "fourth generation admitted")

if failures == 0 { print("ALL_CHECKS_PASS") } else { print("FAILURES=\(failures)") }
