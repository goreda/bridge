import Foundation
import GorAVCore
import GorAVFFmpegAdapter
import GorAVNativeProbeKit
import GorAVPlaybackCore

@main
struct AudioTest {
    static func main() async {
        let expected = "793d0b08641cf595"
        func mark(_ m: String) { FileHandle.standardError.write((m + "\n").data(using: .utf8)!) }
        mark("A: start")
        // d13 R-block (queue 8): runs first so it is reachable on runners without the kit's fixture-k4.wav.
        await rBlock()
        if ProcessInfo.processInfo.environment["GORAV_RBLOCK_ONLY"] == "1" { exit(0) }
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
            case .opened(let codec, let rate, let ch, _, _): print("opened: codec=\(codec) \(rate)Hz \(ch)ch")
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

// ---- R-block (queue 8, d13): audio format as an explicit open-time input.
struct RCapture {
    var opened: [(codec: String, rate: Int, ch: Int, cRate: Int, cCh: Int)] = []
    var frameFormats: Set<String> = []
    var frames = 0, samples = 0, bytes = 0
    var bytesMatchSamples = true
    var digest: UInt64 = 14695981039346656037
    var failed: String?
}

extension AudioTest {
    static func rCapture(root: String, file: String, epoch: UInt64, format: AudioOutFormat? = nil) async -> (RCapture, String?) {
        var cap = RCapture()
        let d = FFmpegSoftwareAudioDecoder()
        do { try d.pinLocalRoots([root]) } catch { return (cap, "pin \(error)") }
        let ses = SessionID(uncheckedEpoch: epoch)
        let src = SourceDescriptor(id: "\(root)/\(file)", kind: .local, seekable: true)
        do {
            if let f = format { try await d.open(source: src, session: ses, format: f) }
            else { try await d.open(source: src, session: ses) }
        } catch { return (cap, "open \(error)") }
        loop: while let ev = await d.nextEvent(session: ses) {
            switch ev {
            // R3-BEGIN
            case .opened(let c, let r, let ch, let cr, let cc): cap.opened.append((c, r, ch, cr, cc))
            // R3-END
            case .pcm(let f):
                cap.frames += 1; cap.samples += f.samples; cap.bytes += f.bytes.count
                cap.frameFormats.insert("\(f.sampleRate)Hz/\(f.channels)ch")
                if f.bytes.count != f.samples * f.channels * 2 { cap.bytesMatchSamples = false }
                for b in f.bytes { cap.digest = (cap.digest ^ UInt64(b)) &* 1099511628211 }
            case .endOfStream: break loop
            case .failed(let code, let sm): cap.failed = "\(code) \(sm)"; break loop
            default: break
            }
        }
        await d.close(session: ses)
        return (cap, nil)
    }

    static func rBlock() async {
        var fails = 0
        func chk(_ ok: Bool, _ name: String, _ info: String = "") {
            if ok { print("PASS \(name)") } else { print("FAIL \(name) \(info)"); fails += 1 }
        }
        let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
        let c = AudioOutFormat.sinkContract
        chk(c.rate == 44100 && c.channels == 2, "R0 sink contract pinned to 44100 Hz x2")
        // R1: contract-native source, contract pinned (default and explicit).
        let (a, ea) = await rCapture(root: root, file: "fixtures/clip-bbb-10s.mov", epoch: 81)
        chk(ea == nil && a.failed == nil, "R1 open+decode clip-bbb-10s.mov", "\(ea ?? a.failed ?? "")")
        chk(a.frameFormats == ["44100Hz/2ch"] && a.frames > 0 && a.bytesMatchSamples, "R1 contract-native source frames carry the contract format", "\(a.frameFormats)")
        print("INFO R1 clip-bbb-10s.mov frames=\(a.frames) samples=\(a.samples) bytes=\(a.bytes) fnv1a64=\(String(format: "%016llx", a.digest))")
        let (a2, ea2) = await rCapture(root: root, file: "fixtures/clip-bbb-10s.mov", epoch: 82, format: AudioOutFormat(rate: 44100, channels: 2))
        chk(ea2 == nil && a2.digest == a.digest && a2.bytes == a.bytes, "R1 explicit contract format is byte-identical to the default", "\(ea2 ?? "")")
        // R2: non-contract source (48 kHz stereo pcm_s16le wav) -> contract frames via the sink-side converter.
        let (b, eb) = await rCapture(root: root, file: "fixtures/tone-48k.wav", epoch: 83)
        chk(eb == nil && b.failed == nil, "R2 open+decode tone-48k.wav", "\(eb ?? b.failed ?? "")")
        chk(b.frameFormats == ["44100Hz/2ch"] && b.frames > 0 && b.bytesMatchSamples, "R2 non-contract source frames carry the CONTRACT format", "\(b.frameFormats)")
        print("INFO R2 tone-48k.wav frames=\(b.frames) samples=\(b.samples) bytes=\(b.bytes) (48000 in -> ~44100 expected)")
        chk(abs(b.samples - 44100) <= 64, "R2 duration conserved through the sink-side converter (44100 +/- 64 samples)", "samples=\(b.samples)")
        // R3: .opened reports source-native vs contract.
        // R3-BEGIN
        chk(a.opened.count == 1 && a.opened[0].codec == "pcm_s16le" && a.opened[0].rate == 44100 && a.opened[0].ch == 2 && a.opened[0].cRate == 44100 && a.opened[0].cCh == 2,
            "R3 .opened native == contract for clip-bbb-10s.mov", "\(a.opened)")
        chk(b.opened.count == 1 && b.opened[0].codec == "pcm_s16le" && b.opened[0].rate == 48000 && b.opened[0].ch == 2 && b.opened[0].cRate == 44100 && b.opened[0].cCh == 2,
            "R3 .opened native 48000x2 vs contract 44100x2 for tone-48k.wav", "\(b.opened)")
        // R3-END
        // R5: any other requested device format is refused at open, not coerced.
        let (_, e5) = await rCapture(root: root, file: "fixtures/tone-48k.wav", epoch: 84, format: AudioOutFormat(rate: 48000, channels: 2))
        chk(e5?.contains("not supported") == true, "R5 non-contract device format refused at open", "\(e5 ?? "opened")")
        // R6 (queue 37): converted-audio seek refusal is typed; contract-native control is not refused for the converter reason.
        func seekProbe(_ file: String, epoch: UInt64) async -> AudioSeekResult? {
            let d = FFmpegSoftwareAudioDecoder()
            do { try d.pinLocalRoots([root]) } catch { return nil }
            let ses = SessionID(uncheckedEpoch: epoch)
            do { try await d.open(source: SourceDescriptor(id: "\(root)/\(file)", kind: .local, seekable: true), session: ses) } catch { return nil }
            var result: AudioSeekResult?
            if let desc = await d.seekDescriptor(session: ses), let target = try? RationalTime(value: 1, timescale: 2) {
                result = await d.seek(binding: desc.binding, videoRelativeTarget: target, correlation: 1)
            }
            await d.close(session: ses)
            return result
        }
        let r6a = await seekProbe("fixtures/tone-48k.wav", epoch: 85)
        // arch-195b R6: converted-audio seek must WORK. A bare PCM wav has an exact zero
        // origin (first byte is the first sample), so the decoder falls back to t=0 and the
        // seek to 0.5s commits natively.
        if case .nativeReady(_, let r6aCorr, let r6aCommon, _) = r6a {
            chk(r6aCorr == 1 && r6aCommon == (try? RationalTime(value: 1, timescale: 2)), "R6 converted (48 kHz PCM wav) seek commits natively at the 0.5s target", "\(String(describing: r6a))")
        } else {
            chk(false, "R6 converted (48 kHz PCM wav) seek commits natively at the 0.5s target", "\(String(describing: r6a))")
        }
        // R6b-continuity: after the seek, the first converted PCM frame lands ON the target
        // and the remaining duration plays out on one clock.
        do {
            let d = FFmpegSoftwareAudioDecoder()
            try d.pinLocalRoots([root])
            let ses = SessionID(uncheckedEpoch: 88)
            try await d.open(source: SourceDescriptor(id: "\(root)/fixtures/tone-48k.wav", kind: .local, seekable: true), session: ses)
            var gap: Double? = nil
            var postSamples = 0
            if let desc = await d.seekDescriptor(session: ses), let target = try? RationalTime(value: 1, timescale: 2) {
                let res = await d.seek(binding: desc.binding, videoRelativeTarget: target, correlation: 2)
                if case .nativeReady(let nb, _, _, _) = res {
                    loop: while let env = await d.nextBoundEvent(binding: nb) {
                        switch env.event {
                        case .pcm(let f):
                            postSamples += f.samples
                            if gap == nil, let tm = env.timing, let g = tm.gapFromTarget {
                                gap = abs(Double(g.value) / Double(g.timescale))
                            }
                        case .endOfStream, .failed: break loop
                        default: break
                        }
                    }
                }
            }
            await d.close(session: ses)
            chk(gap != nil && gap! <= 2.0/44100.0, "R6 post-seek first converted frame lands within 2 output samples of the target", "gap=\(gap.map{String($0)} ?? "nil")")
            chk(abs(postSamples - 22050) <= 64, "R6 post-seek remaining duration conserved (22050 +/- 64 samples)", "samples=\(postSamples)")
        } catch {
            chk(false, "R6 post-seek continuity probe threw", "\(error)")
        }
        let r6c = await seekProbe("fixtures/m1/synthetic-h264-aac.mp4", epoch: 87)
        print("INFO R6 converted muxed aac (48 kHz) seek result: \(String(describing: r6c))")
        chk(r6c != nil && r6c != .refused(.decoderResetUnavailable), "R6 converted muxed aac (48 kHz) seek not refused for the converter reason", "\(String(describing: r6c))")
        let r6b = await seekProbe("fixtures/clip-bbb-10s.mov", epoch: 86)
        print("INFO R6 contract-native control seek result: \(String(describing: r6b))")
        chk(r6b != nil && r6b != .refused(.decoderResetUnavailable), "R6 contract-native control seek not refused for the converter reason", "\(String(describing: r6b))")
        print(fails == 0 ? "R_BLOCK_PASS" : "R_BLOCK_FAIL: \(fails)")
        if fails != 0 { exit(74) }
    }
}
