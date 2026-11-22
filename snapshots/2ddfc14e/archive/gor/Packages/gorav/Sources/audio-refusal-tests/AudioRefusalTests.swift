import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// Audio admission/fault battery (mirrors the video battery posture):
// every non-pinned-family input must be a TYPED refusal, never a decode.
// (gdb chief MED r7-review) every battery line routes through here: any line
// containing "(BAD)" or ": FAIL" is counted, and the process exit code
// reflects it - a printed BAD can never again ride out on exit 0.
private var badCount = 0
private func out(_ s: String) { Swift.print(s); if s.contains("(BAD)") || s.contains(": FAIL") { badCount += 1 } }

@main

struct AudioRefusalTests {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        func expectOpenRefused(_ name: String, _ path: String, epoch: UInt64) async {
            let d = FFmpegSoftwareAudioDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: epoch))
                out("\(name): OPEN_ACCEPTED(BAD)")
            } catch { out("\(name): OPEN_REFUSED \(error)") }
        }
        // A1: mp4 video file against the audio adapter (container != wav)
        await expectOpenRefused("A1_mp4", "\(KIT)/fixtures/fixture-k3.mp4", epoch: 81)
        // A2: ppm image against the audio adapter
        await expectOpenRefused("A2_ppm", "\(KIT)/fixtures/first-ppm-rgb24-17x11.ppm", epoch: 82)
        // A3: float32 WAV (codec != pcm_s16le)
        await expectOpenRefused("A3_float_wav", "\(KIT)/fixtures/fixture-k4-float.wav", epoch: 83)
        // A4: source outside pinned roots
        do {
            let d = FFmpegSoftwareAudioDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: "/etc/hostname", kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 84))
                out("A4_outside_roots: OPEN_ACCEPTED(BAD)")
            } catch { out("A4_outside_roots: OPEN_REFUSED \(error)") }
        }
        // A5: vacuous root refused at pin time
        do {
            let d = FFmpegSoftwareAudioDecoder()
            try d.pinLocalRoots(["/"])
            out("A5_vacuous_root: PIN_ACCEPTED(BAD)")
        } catch { out("A5_vacuous_root: PIN_REFUSED \(error)") }
        // A6: truncated WAV - open may succeed (header intact) but decode must
        // end in a TYPED event (EOS or .failed), never a hang or silent loss.
        do {
            let d = FFmpegSoftwareAudioDecoder()
            try! d.pinLocalRoots([KIT])
            let ses = SessionID(uncheckedEpoch: 86)
            try await d.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4-truncated.wav", kind: .local, seekable: true), session: ses)
            var frames = 0, bytes = 0, term = "none"
            loop: while let ev = await d.nextEvent(session: ses) {
                switch ev {
                case .pcm(let f): frames += 1; bytes += f.bytes.count
                case .endOfStream: term = "eos"; break loop
                case .failed(let c, _): term = "failed(\(c))"; break loop
                default: break
                }
            }
            await d.close(session: ses)
            let ok = term != "none" && bytes < 176400
            out("A6_truncated: frames=\(frames) bytes=\(bytes) terminal=\(term) \(ok ? "TYPED_OK" : "BAD")")
        } catch { out("A6_truncated: OPEN_REFUSED \(error) TYPED_OK") }
        // A7: stale session observes nothing after close
        do {
            let d = FFmpegSoftwareAudioDecoder()
            try! d.pinLocalRoots([KIT])
            let ses = SessionID(uncheckedEpoch: 87)
            try await d.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4.wav", kind: .local, seekable: true), session: ses)
            await d.close(session: ses)
            let ev = await d.nextEvent(session: ses)
            out(ev == nil ? "A7_stale_session: NIL_OK" : "A7_stale_session: EVENT_AFTER_CLOSE(BAD)")
        } catch { out("A7_stale_session: OPEN_REFUSED \(error)") }
        // A8: K13B vacuous-root aliases (post-resolution guard, F2)
        do {
            try? FileManager.default.removeItem(atPath: "/tmp/k13b-link-to-root")
            try! FileManager.default.createSymbolicLink(atPath: "/tmp/k13b-link-to-root", withDestinationPath: "/")
            for (name, root) in [("A8a_root", "/"), ("A8b_doubleslash", "//"), ("A8c_dotroot", "/."), ("A8d_symlink", "/tmp/k13b-link-to-root")] {
                let d = FFmpegSoftwareAudioDecoder()
                do { try d.pinLocalRoots([root]); out("\(name): PIN_ACCEPTED(BAD)") }
                catch { out("\(name): PIN_REFUSED \(error)") }
            }
            let d = FFmpegSoftwareAudioDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4.wav", kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 89))
                out("A8e_normal_pin_still_opens: OK")
                await d.close(session: SessionID(uncheckedEpoch: 89))
            } catch { out("A8e_normal_pin_still_opens: REFUSED(BAD) \(error)") }
        }
        out("AUDIO_REFUSAL_SUMMARY bad=\(badCount)")
        exit(badCount == 0 ? 0 : 77)
    }
}
