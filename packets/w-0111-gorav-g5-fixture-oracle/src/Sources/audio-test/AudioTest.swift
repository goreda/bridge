import Foundation
import GorAVCore
import GorAVFFmpegAdapter
import GorAVPlaybackCore

@main
struct AudioTest {
    static func main() async {
        let expected = "793d0b08641cf595"
        func mark(_ m: String) { FileHandle.standardError.write((m + "\n").data(using: .utf8)!) }
        mark("A: start")
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let decoder = FFmpegSoftwareAudioDecoder()
        mark("B: pin"); do { try decoder.pinLocalRoots([KIT]) } catch { print("K4 FAIL: pin \(error)"); exit(66) }
        let session = SessionID(uncheckedEpoch: 31)
        mark("C: open"); do { try await decoder.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4.wav", kind: .local, seekable: true), session: session) }
        catch { print("K4 FAIL: open \(error)"); exit(67) }
        var hash: UInt64 = 14695981039346656037
        var frames = 0, totalBytes = 0, sawEOS = false
        mark("D: pull loop"); loop: while let event = await decoder.nextEvent(session: session) {
            switch event {
            case .opened(let codec, let rate, let ch): print("opened: codec=\(codec) \(rate)Hz \(ch)ch")
            case .pcm(let f):
                frames += 1; totalBytes += f.bytes.count
                for b in f.bytes { hash = (hash ^ UInt64(b)) &* 1099511628211 }
            case .endOfStream: sawEOS = true; break loop
            case .failed(let code, let summary): print("K4 FAIL: failed \(code) \(summary)"); exit(70)
            }
        }
        await decoder.close(session: session)
        let digest = String(format: "%016llx", hash)
        print("frames=\(frames) bytes=\(totalBytes) eos=\(sawEOS)")
        print("pcm_digest_fnv1a64=\(digest)")
        print("expected          =\(expected)")
        if digest == expected && sawEOS { print("K4_AUDIO_PASS") } else { print("K4_AUDIO_MISMATCH"); exit(71) }

        // K8: shell audio buffer (PCMRingBuffer) oracle - push the full
        // decoded payload, render in 4,096-byte pulls, chain-FNV must equal
        // the K4 oracle; underrun past payload renders silence, counted.
        do {
            let ring = PCMRingBuffer(capacity: 1 << 20)
            let dec2 = FFmpegSoftwareAudioDecoder()
            try! dec2.pinLocalRoots([KIT])
            let ses2 = SessionID(uncheckedEpoch: 32)
            try! await dec2.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4.wav", kind: .local, seekable: true), session: ses2)
            var total = 0
            loop2: while let ev = await dec2.nextEvent(session: ses2) {
                switch ev {
                case .pcm(let f): ring.push(f.bytes); total += f.bytes.count
                case .endOfStream: break loop2
                case .failed(let c, let sm): print("K8 FAIL: \(c) \(sm)"); exit(70)
                default: break
                }
            }
            await dec2.close(session: ses2)
            var h: UInt64 = 14695981039346656037
            var rendered = 0
            while rendered < total {
                let n = min(4096, total - rendered)
                for b in ring.render(n) { h = (h ^ UInt64(b)) &* 1099511628211 }
                rendered += n
            }
            let got = String(format: "%016llx", h)
            let silence = ring.render(8192)
            let silenceOK = silence.allSatisfy { $0 == 0 }
            print("k8_render_digest=\(got) bytes=\(rendered) underrunBytes=\(ring.underrunBytes)")
            // Overrun check: tiny ring, push 3x capacity, drops counted.
            let tiny = PCMRingBuffer(capacity: 1024)
            tiny.push([UInt8](repeating: 7, count: 3072))
            let overrunOK = tiny.overrunDrops == 2048 && tiny.available == 1024
            if got == expected && rendered == 176400 && silenceOK && ring.underrunBytes == 8192 && overrunOK {
                print("K8_AUDIO_RING_PASS")
            } else { print("K8_AUDIO_RING_FAIL"); exit(72) }

            // K9: concurrent producer/consumer over the ring - FIFO order,
            // zero loss, zero corruption under real Task interleaving.
            do {
                let ring2 = PCMRingBuffer(capacity: 1 << 20)
                let payload: [UInt8] = (0..<176400).map { UInt8(truncatingIfNeeded: $0 &* 2654435761 &>> 8) }
                async let pushDone: Void = Task {
                    var off = 0
                    while off < payload.count {
                        let n = min(4096, payload.count - off)
                        ring2.push(Array(payload[off..<off+n])); off += n
                        await Task.yield()
                    }
                }.value
                var out: [UInt8] = []
                out.reserveCapacity(payload.count)
                while out.count < payload.count {
                    let a = ring2.available
                    if a == 0 { await Task.yield(); continue }
                    out.append(contentsOf: ring2.render(min(a, 4096)))
                }
                await pushDone
                let fifoOK = out == payload
                let lossOK = ring2.overrunDrops == 0
                print("k9 concurrent: bytes=\(out.count) fifo=\(fifoOK) drops=\(ring2.overrunDrops)")
                print(fifoOK && lossOK ? "K9_RING_CONCURRENCY_PASS" : "K9_RING_CONCURRENCY_FAIL")
                if !(fifoOK && lossOK) { exit(73) }
            }
            exit(0)
        }
    }
}
