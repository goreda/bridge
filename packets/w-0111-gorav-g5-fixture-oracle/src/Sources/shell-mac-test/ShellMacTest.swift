import Foundation
#if canImport(AppKit) && canImport(CoreAudio)
import AudioToolbox
import GorAVMacShell

// r11 Mac-only checks for the AudioUnit render callback (team2 K9-12 and K9-13)
// and an AudioUnit start/stop smoke. No sound is played: the ring is empty or
// zero-filled, so the unit renders silence.
@main
struct ShellMacTest {
    static var fails = 0
    static func check(_ id: String, _ ok: Bool, _ detail: String) {
        print("\(id): \(ok ? "PASS" : "FAIL") \(detail)")
        if !ok { fails += 1 }
    }

    // Builds a one-buffer AudioBufferList of `size` bytes inside an allocation of
    // `alloc` bytes, all filled with 0xAB (canary), then runs `body`.
    static func withList(size: Int, alloc: Int, _ body: (UnsafeMutablePointer<AudioBufferList>, UnsafeMutablePointer<UInt8>) -> Void) {
        let mem = UnsafeMutablePointer<UInt8>.allocate(capacity: alloc)
        mem.initialize(repeating: 0xAB, count: alloc)
        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee = AudioBufferList(mNumberBuffers: 1,
                                      mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(size), mData: UnsafeMutableRawPointer(mem)))
        body(abl, mem)
        abl.deallocate()
        mem.deallocate()
    }

    static func main() {
        // K9-12: frames == 0 is a no-op (buffer untouched); nil buffer list is noErr.
        // v5: no fake-running seam exists; the test drives a REAL session
        // (hardware required) and declares the no-producer witness.
        do {
            guard let sink = AudioUnitSink() else { check("SINK_ALLOC", false, "bring-up refused"); exit(78) }
            try sink.start()
            sink.push([UInt8](repeating: 7, count: 16))
            var st: OSStatus = -1
            var untouched = false
            withList(size: 16, alloc: 16) { abl, mem in
                st = sink.testRender(frames: 0, data: abl)
                untouched = (0..<16).allSatisfy { mem[$0] == 0xAB }
            }
            let stNil = sink.testRender(frames: 4, data: nil)
            sink.producerNotExpected(generation: sink.currentGeneration)
            sink.stop()
            check("K9-12", st == noErr && untouched && stNil == noErr && sink.stoppedReceipt != nil,
                  "frames=0 no-op untouched=\(untouched) nilList=\(stNil)")
        }
        // K9-13a: advertised region (mDataByteSize 64) is written in full:
        // 32 pushed bytes, then silence for the rest, no 0xAB left.
        do {
            guard let sink = AudioUnitSink() else { check("SINK_ALLOC", false, "bring-up refused"); exit(78) }
            try sink.start()
            sink.push((1...32).map { UInt8($0) })
            var st: OSStatus = -1
            var head = false, tail = false
            withList(size: 64, alloc: 64) { abl, mem in
                st = sink.testRender(frames: 16, data: abl)
                head = (0..<32).allSatisfy { mem[$0] == UInt8($0 + 1) }
                tail = (32..<64).allSatisfy { mem[$0] == 0 }
            }
            sink.producerNotExpected(generation: sink.currentGeneration)
            sink.stop()
            check("K9-13a", st == noErr && head && tail, "head=\(head) silenceTail=\(tail)")
        }
        // K9-13b: frames*4 larger than mDataByteSize: only mDataByteSize bytes are
        // written; the canary bytes after the advertised region stay 0xAB.
        do {
            guard let sink = AudioUnitSink() else { check("SINK_ALLOC", false, "bring-up refused"); exit(78) }
            try sink.start()
            sink.push([UInt8](repeating: 9, count: 64))
            var st: OSStatus = -1
            var written = false, canary = false
            withList(size: 16, alloc: 32) { abl, mem in
                st = sink.testRender(frames: 100, data: abl)
                written = (0..<16).allSatisfy { mem[$0] == 9 }
                canary = (16..<32).allSatisfy { mem[$0] == 0xAB }
            }
            sink.producerNotExpected(generation: sink.currentGeneration)
            sink.stop()
            check("K9-13b", st == noErr && written && canary, "written=\(written) canaryIntact=\(canary)")
        }
        // AU_SMOKE: the default output unit sets up, starts, takes zero PCM, and stops.
        do {
            guard let sink = AudioUnitSink() else { check("SINK_ALLOC", false, "bring-up refused"); exit(78) }
            var ok = true
            var detail = "start/stop ok"
            do {
                try sink.start()
                sink.push([UInt8](repeating: 0, count: 17640))
                Thread.sleep(forTimeInterval: 0.3)
                sink.producerNotExpected(generation: sink.currentGeneration)
                sink.stop()
            } catch {
                ok = false
                detail = "start failed: \(error)"
            }
            check("AU_SMOKE", ok, detail)
        }
        print(fails == 0 ? "SHELL_MAC_TEST_PASS" : "SHELL_MAC_TEST_FAIL \(fails)")
        exit(fails == 0 ? 0 : 78)
    }
}
#else
@main
struct ShellMacTest {
    static func main() {
        print("SHELL_MAC_TEST_SKIPPED not macOS")
    }
}
#endif
