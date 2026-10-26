import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// K5 seek proof: oracle-indexed landings. Fixture GOP=12 (keyframes 0,12,24,36),
// 25fps. BACKWARD seek lands on the keyframe <= target.
@main
struct SeekTest {
    static func main() async {
        let oracleRaw = try! String(contentsOfFile: "\(ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2")/oracles/k3-oracle.txt", encoding: .utf8)
        let oracle = oracleRaw.split(separator: "\n").map { String($0.split(separator: " ")[1]) }
        let decoder = FFmpegSoftwareDecoder()
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        try! decoder.pinLocalRoots([KIT])
        let session = SessionID(uncheckedEpoch: 41)
        do { try await decoder.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: session) }
        catch { print("K5 FAIL: open \(error)"); exit(67) }
        _ = await decoder.nextEvent(session: session) // consume .opened

        // (seekSeconds, expectedOracleIndex)
        let cases: [(Double, Int)] = [(0.8, 12), (0.0, 0), (1.8, 36)]
        var fails = 0
        for (t, want) in cases {
            do { try await decoder.seek(toSeconds: t, session: session) }
            catch { print("K5 FAIL: seek(\(t)) threw \(error)"); fails += 1; continue }
            var got: String?
            while got == nil, let ev = await decoder.nextEvent(session: session) {
                if case .frameDecoded(let f) = ev {
                    got = await decoder.frameDigest(handle: f.handle, session: session)
                    await decoder.releaseFrame(handle: f.handle, session: session)
                }
                if case .endOfStream = ev { break }
                if case .failed(let c, let s) = ev { print("K5 FAIL: failed \(c) \(s)"); break }
            }
            let ok = got == oracle[want]
            if !ok { fails += 1 }
            print("seek \(t)s -> landing frame digest \(got ?? "nil") want oracle[\(want)] \(oracle[want]) \(ok ? "OK" : "MISMATCH")")
        }
        _ = await decoder.closeAndReport(session: session)

        // K5b: seek then DRAIN TO EOS - the full decoded suffix after a seek
        // must equal the oracle suffix from the landing keyframe on. Proves
        // the pipeline/feed reset is complete, not just the first frame.
        var suffixFails = 0
        for (t, want) in [(0.8, 12), (0.0, 0), (1.8, 36)] {
            let dec2 = FFmpegSoftwareDecoder()
            try! dec2.pinLocalRoots([ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"])
            let ses2 = SessionID(uncheckedEpoch: 42 + UInt64(want))
            try! await dec2.open(source: SourceDescriptor(id: "\(ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2")/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: ses2)
            _ = await dec2.nextEvent(session: ses2) // .opened
            try! await dec2.seek(toSeconds: t, session: ses2)
            var digests: [String] = []
            while let ev = await dec2.nextEvent(session: ses2) {
                if case .frameDecoded(let f) = ev {
                    if let d = await dec2.frameDigest(handle: f.handle, session: ses2) { digests.append(d) }
                    await dec2.releaseFrame(handle: f.handle, session: ses2)
                }
                if case .endOfStream = ev { break }
                if case .failed(let c, let sm) = ev { print("K5b FAIL: \(c) \(sm)"); suffixFails += 1; break }
            }
            _ = await dec2.closeAndReport(session: ses2)
            let wantSuffix = Array(oracle[want...])
            let ok = digests == wantSuffix
            if !ok { suffixFails += 1 }
            print("seek \(t)s drain-to-EOS: \(digests.count) frames, suffix \(ok ? "== oracle[\(want)...]" : "MISMATCH want \(wantSuffix.count)")")
        }
        fails += suffixFails
        if fails == 0 { print("K5_SEEK_PASS"); exit(0) }
        print("K5_SEEK_MISMATCH"); exit(71)
    }
}
