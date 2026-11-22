import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// Path-route refusal battery: typed refusals at open/session boundaries.
// (gdb chief MED r7-review) every battery line routes through here: any line
// containing "(BAD)" or ": FAIL" is counted, and the process exit code
// reflects it - a printed BAD can never again ride out on exit 0.
private var badCount = 0
private func out(_ s: String) { Swift.print(s); if s.contains("(BAD)") || s.contains(": FAIL") { badCount += 1 } }

@main

struct VideoRefusalTests {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let mp4 = "\(KIT)/fixtures/fixture-k3.mp4"
        func expectRefused(_ name: String, _ path: String, epoch: UInt64) async {
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: epoch))
                out("\(name): OPEN_ACCEPTED(BAD)")
            } catch { out("\(name): OPEN_REFUSED \(error)") }
        }
        // V1: nonexistent file inside pinned roots
        await expectRefused("V1_missing", "\(KIT)/fixtures/no-such.mp4", epoch: 91)
        // V2: a WAV against the video adapter (audio-only content: no video stream)
        await expectRefused("V2_wav", "\(KIT)/fixtures/fixture-k4.wav", epoch: 92)
        // V3: text masquerading as mp4
        let fakePath = "\(KIT)/fixtures/fake.mp4"
        try! "not an mp4 at all".write(toFile: fakePath, atomically: true, encoding: .utf8)
        await expectRefused("V3_fake_mp4", fakePath, epoch: 93)
        // V4: outside pinned roots
        await expectRefused("V4_outside_roots", "/etc/hostname", epoch: 94)
        // V5: URL-scheme source id
        do {
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: "https://example.com/x.mp4", kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 95))
                out("V5_scheme: OPEN_ACCEPTED(BAD)")
            } catch { out("V5_scheme: OPEN_REFUSED \(error)") }
        }
        // V6: relative path refused
        do {
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: "fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 96))
                out("V6_relative: OPEN_ACCEPTED(BAD)")
            } catch { out("V6_relative: OPEN_REFUSED \(error)") }
        }
        // V7: double-open on one instance -> sessionBusy; epoch reuse -> refused
        do {
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            let ses = SessionID(uncheckedEpoch: 97)
            try! await d.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: ses)
            do {
                try await d.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 98))
                out("V7_double_open: ACCEPTED(BAD)")
            } catch { out("V7_double_open: REFUSED \(error)") }
            _ = await d.closeAndReport(session: ses)
            do {
                try await d.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: ses)
                out("V8_epoch_reuse: ACCEPTED(BAD)")
            } catch { out("V8_epoch_reuse: REFUSED \(error)") }
        }
        // V9: seek refusals - before open, non-finite, negative, huge
        do {
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            do { try await d.seek(toSeconds: 1.0, session: SessionID(uncheckedEpoch: 99)); out("V9a_seek_unopened: ACCEPTED(BAD)") }
            catch { out("V9a_seek_unopened: REFUSED \(error)") }
            let ses = SessionID(uncheckedEpoch: 99)
            try! await d.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: ses)
            for (name, t) in [("V9b_nan", Double.nan), ("V9c_inf", Double.infinity), ("V9d_negative", -1.0), ("V9e_huge", 1e30)] {
                do { try await d.seek(toSeconds: t, session: ses); out("\(name): ACCEPTED(BAD)") }
                catch { out("\(name): REFUSED \(error)") }
            }
            // seek still works after the refused seeks
            try! await d.seek(toSeconds: 0.0, session: ses)
            out("V9f_valid_after_refusals: OK")
            _ = await d.closeAndReport(session: ses)
        }
        // V10: K13B vacuous-root pin battery - pin-time refusal of anything
        // that RESOLVES to '/', plus containment still intact afterwards.
        do {
            try? FileManager.default.removeItem(atPath: "/tmp/k13b-link-to-root")
            try! FileManager.default.createSymbolicLink(atPath: "/tmp/k13b-link-to-root", withDestinationPath: "/")
            for (name, root) in [("V10a_root", "/"), ("V10b_doubleslash", "//"), ("V10c_dotroot", "/."), ("V10d_symlink", "/tmp/k13b-link-to-root")] {
                let d = FFmpegSoftwareDecoder()
                do { try d.pinLocalRoots([root]); out("\(name): PIN_ACCEPTED(BAD)") }
                catch { out("\(name): PIN_REFUSED \(error)") }
            }
            // normal pin still works after the fix
            let d = FFmpegSoftwareDecoder()
            try! d.pinLocalRoots([KIT])
            do {
                try await d.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 90))
                out("V10e_normal_pin_still_opens: OK")
                _ = await d.closeAndReport(session: SessionID(uncheckedEpoch: 90))
            } catch { out("V10e_normal_pin_still_opens: REFUSED(BAD) \(error)") }
        }
        out("VIDEO_REFUSAL_SUMMARY bad=\(badCount)")
        exit(badCount == 0 ? 0 : 77)
    }
}
