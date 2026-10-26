// L1 rework SPSC tests (architect PART1 findings 1/2/4): frame alignment,
// event-time stamps, overflow latch, direct-buffer render, and a real
// two-thread conservation smoke (producer/consumer concurrently).
import Foundation
import GorAVPlaybackCore

enum SPSC {
    static var failures = 0
    static func check(_ cond: Bool, _ name: String, _ detail: String = "") {
        if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
    }
    /// Unwrap for failable v4 ring construction: a nil (typed init refusal)
    /// is a test failure, never a crash.
    static func unwrap<T>(_ v: T?, _ name: String) -> T? {
        if v == nil { check(false, name, "typed init refusal") }
        return v
    }

    static func run() {
        // S1: frame quantization - a partial trailing frame is refused, never
        // admitted out of alignment (finding 2).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 8), "init S1") else { return }
            var bytes = [UInt8](repeating: 0xAB, count: 10) // 2 frames + 2-byte tail
            let r = bytes.withUnsafeBufferPointer { ring.push($0) }
            check(r.admittedFrames == 2 && r.droppedFrames == 0 && r.droppedTailBytes == 2, "S1 partial tail refused BYTE-exact, not as a frame", "\(r)")
            check(ring.availableFrames == 2, "S1 available is whole frames")
            check(ring.partialTailDrops.load() == 1 && ring.droppedBytes.load() == 2, "S1 tail counted as 2 BYTES not 4")
            check(ring.requestedBytes.load() == ring.admittedBytes.load() + ring.droppedBytes.load(), "S1 byte conservation requested==admitted+dropped")
        }
        // S2: full-ring drop-newest is frame-granular; retained content keeps
        // ordered identity (finding 2 + ordered-content mutant).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 4), "init S2") else { return }
            func frame(_ v: UInt8) -> [UInt8] { [v, v, v, v] }
            var pushed: [UInt8] = []
            for i: UInt8 in 0..<4 { pushed.append(contentsOf: frame(i &+ 1)) }
            let r1 = pushed.withUnsafeBufferPointer { ring.push($0) }
            check(r1.admittedFrames == 4 && r1.droppedFrames == 0, "S2 fill")
            var extra = frame(99) + frame(98)
            let r2 = extra.withUnsafeBufferPointer { ring.push($0) }
            check(r2.admittedFrames == 0 && r2.droppedFrames == 2, "S2 overflow drop frame-quantized")
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 16); defer { dst.deallocate() }
            let under = ring.render(into: dst, frames: 4)
            check(under == 0, "S2 no underrun on full ring")
            var out: [UInt8] = []; for i in 0..<16 { out.append(dst[i]) }
            check(out == pushed, "S2 retained identity oldest ordered frames")
        }
        // S3: underrun zero-fill is not consumption (finding 2).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 8), "init S4") else { return }
            var two = [UInt8](repeating: 7, count: 8)
            _ = two.withUnsafeBufferPointer { ring.push($0) }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 16); defer { dst.deallocate() }
            let under = ring.render(into: dst, frames: 4)
            check(under == 2 && ring.consumedFrames.load() == 2 && ring.underrunFrames.load() == 2, "S3 underrun frames counted")
            var tail: [UInt8] = []; for i in 8..<16 { tail.append(dst[i]) }
            check(tail == [0, 0, 0, 0, 0, 0, 0, 0], "S3 shortfall is silence")
        }
        // S4: event ring - post-time stamps + generation preserved, drain
        // order, sticky overflow latch (findings 1/4).
        do {
            final class TBox: @unchecked Sendable { var v = 100.0 }
            let tb = TBox()
            guard let ring = unwrap(SPSCEventRing(capacity: 2, clock: { tb.v }), "init S3") else { return }
            ring.post(.underrunStart, generation: 3, payload: .frames(512))
            tb.v = 101.5
            ring.post(.underrunEnd, generation: 3, payload: .frames(0))
            tb.v = 102.0
            ring.post(.staleFenced, generation: 3, payload: .bytes(4)) // overflows (cap 2)
            let evs = ring.drain()
            check(evs.count == 2 && evs[0].kind == .underrunStart && evs[1].kind == .underrunEnd, "S4 drain order")
            check(evs[0].tEvent == 100.0 && evs[1].tEvent == 101.5, "S4 post-time stamps preserved", "\(evs.map { $0.tEvent })")
            check(evs[0].generation == 3, "S4 generation at post time")
            check(ring.overflowed.load() == 1, "S4 overflow latch set")
            _ = ring.drain()
            check(ring.overflowed.load() == 1, "S4 latch sticky after drain")
        }
        // S5: real two-thread conservation smoke. Producer pushes
        // seq-patterned frames; consumer renders; no torn frames, conservation
        // pushed == consumed + dropped + remaining (finding 1 adversarial).
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 1024), "init S5") else { return }
            let totalFrames = 200_000
            let group = DispatchGroup()
            var maxSeqSeen = -1
            var monotonic = true
            let lock = NSLock()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                var chunk = [UInt8](repeating: 0, count: 64 * 4)
                var seq: UInt32 = 0
                var pushed = 0
                while pushed < totalFrames {
                    for f in 0..<64 {
                        chunk[f * 4 + 0] = UInt8(seq & 0xFF)
                        chunk[f * 4 + 1] = UInt8((seq >> 8) & 0xFF)
                        chunk[f * 4 + 2] = UInt8((seq >> 16) & 0xFF)
                        chunk[f * 4 + 3] = UInt8((seq >> 24) & 0xFF)
                        seq &+= 1
                    }
                    let r = chunk.withUnsafeBufferPointer { ring.push($0) }
                    pushed += Int(r.admittedFrames)
                    if r.admittedFrames == 0 { Thread.sleep(forTimeInterval: 0.0001) }
                }
            }
            // Consume until the producer's frames are ALL really consumed:
            // underrun zero-fill never increments consumedFrames, so this
            // cannot exit early on silence. (Fixes consumer-exits-first
            // deadlock of the naive slot-count loop.)
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 4)
            while ring.consumedFrames.load() < totalFrames {
                let before = ring.consumedFrames.load()
                _ = ring.render(into: dst, frames: 64)
                let got = Int(ring.consumedFrames.load() - before)
                for f in 0..<got {
                    let v = UInt32(dst[f * 4]) | UInt32(dst[f * 4 + 1]) << 8 | UInt32(dst[f * 4 + 2]) << 16 | UInt32(dst[f * 4 + 3]) << 24
                    lock.lock()
                    if Int(v) <= maxSeqSeen { monotonic = false }
                    maxSeqSeen = Int(v)
                    lock.unlock()
                }
                if got == 0 { Thread.sleep(forTimeInterval: 0.00005) }
            }
            group.wait()
            dst.deallocate()
            // Conservation: every ADMITTED frame is either consumed or still
            // in the ring. Dropped frames are refused-at-tail and were never
            // admitted, so they are not part of the ring's frame balance.
            let conservation = ring.consumedFrames.load() + ring.availableFrames == ring.pushedFrames.load()
            check(conservation, "S5 conservation admitted==consumed+remaining",
                  "p=\(ring.pushedFrames.load()) c=\(ring.consumedFrames.load()) d=\(ring.droppedFrames.load()) a=\(ring.availableFrames)")
            check(ring.droppedFrames.load() > 0, "S5 overflow path actually exercised (dropped>0)")
            check(ring.requestedBytes.load() == ring.admittedBytes.load() + ring.droppedBytes.load(), "S5 BYTE conservation requested==admitted+dropped",
                  "req=\(ring.requestedBytes.load()) adm=\(ring.admittedBytes.load()) drop=\(ring.droppedBytes.load())")
            // S6: receipt-before-reset regression (architect early blocker
            // #1): a post-stop summary built from the RECEIPT keeps the
            // retired session's evidence after the ring is reset.
            do {
                guard let ring2 = unwrap(SPSCPCMRing(capacityFrames: 64), "init S5b") else { return }
                var pcm = [UInt8](repeating: 5, count: 4 * 16)
                _ = pcm.withUnsafeBufferPointer { ring2.push($0) }
                let dst2 = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 4); defer { dst2.deallocate() }
                _ = ring2.render(into: dst2, frames: 8)
                let receipt = ring2.snapshotReceipt(generation: 1)
                ring2.resetForNewGeneration()
                check(ring2.pushedFrames.load() == 0 && ring2.maxAvailAfterPushFrames.load() == 0, "S6 live ring zeroed after reset")
                check(receipt.pushedFrames == 16 && receipt.consumedFrames == 8 && receipt.pushCount == 1 && receipt.maxPushFrames == 16,
                      "S6 retired receipt survives reset", "\(receipt)")
                let ev = QueueBoundEvidence(capacity: 64 * 4, watermark: 32,
                                            maxChunkBytes: Int(receipt.maxPushFrames) * 4,
                                            maxAvailAfterPush: Int(receipt.maxAvailAfterPushFrames) * 4,
                                            overrunDrops: Int(receipt.droppedFrames) * 4,
                                            pushCount: Int(receipt.pushCount))
                check(ev.admissionBoundHolds, "S6 post-stop evidence still proves the bound")
                // S7: invalid evidence inputs never trap and never claim (v3-4)
                let bad = QueueBoundEvidence(capacity: 64, watermark: -1, maxChunkBytes: 4, maxAvailAfterPush: 4, overrunDrops: 0, pushCount: 1)
                check(!bad.admissionBoundHolds, "S7 negative watermark refused")
                let over = QueueBoundEvidence(capacity: 64, watermark: 60, maxChunkBytes: 60, maxAvailAfterPush: 4, overrunDrops: 0, pushCount: 1)
                check(!over.admissionBoundHolds, "S7 watermark+chunk>capacity refused")
            }
            check(monotonic, "S5 no torn/reordered frames under concurrency")
        }
        print(failures == 0 ? "ALL SPSC TESTS PASS" : "SPSC FAILURES: \(failures)")
        // S8: v4 sticky PCM latch - tail refusal AND frame drop both latch;
        // reset clears.
        do {
            guard let ring = unwrap(SPSCPCMRing(capacityFrames: 4), "init S8") else { return }
            check(ring.droppedAnything.load() == 0, "S8 latch starts clear")
            var b3: [UInt8] = [1, 2, 3]
            _ = b3.withUnsafeBufferPointer { ring.push($0) } // tail refusal
            check(ring.droppedAnything.load() == 1, "S8 tail refusal latches sticky")
            ring.resetForNewGeneration()
            check(ring.droppedAnything.load() == 0, "S8 reset clears latch")
            var full: [UInt8] = [UInt8](repeating: 9, count: 20) // 5 frames > cap 4
            _ = full.withUnsafeBufferPointer { ring.push($0) }
            check(ring.droppedAnything.load() == 1 && ring.droppedFrames.load() == 1, "S8 frame drop latches sticky")
            let r = ring.snapshotReceipt(generation: 9)
            check(r.droppedAnything && r.generation == 9, "S8 receipt carries the latch + generation")
        }

        // T23 (lane-0 / architect 80b constraint A): admission-cell semantics.
        // A reader admitted BEFORE retire must drain; an enter AFTER retire fails;
        // retire is idempotent; readers drain to zero deterministically.
        do {
            print("T23 admission cell (architect 80b constraint A)")
            guard let a = AdmissionCell() else { print("FAIL T23 alloc"); exit(1) }
            check(a.enter(), "T23 first enter admitted")
            check(!a.enter(), "T23 ONE-CONSUMER: second enter while busy REFUSED (busy => silence, architect full verdict S2)")
            check(a.readers == 1, "T23 reader count stays 1 under contention")
            a.exit()
            check(a.readers == 0, "T23 reader drained")
            check(a.enter(), "T23 enter re-admitted after drain (not yet retired)")
            a.exit()
            let inFlightAtRetire = a.retire()
            check(inFlightAtRetire == 0, "T23 retire reports zero in-flight readers at retire")
            check(a.isRetired, "T23 retired flag set")
            check(!a.enter(), "T23 MUTANT-NEGATIVE: enter after retire REFUSED")
            check(a.retire() == 0, "T23 retire idempotent")
            check(!a.enter(), "T23 still refused after retire (retire is terminal)")
        }
    }
}
