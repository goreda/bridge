import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// K10: audio + video adapters live simultaneously, interleaved pulls on one
// task - the macOS shell's real pattern. Both must decode to their oracles
// with clean EOS and no cross-interference.
@main
struct CoexistTest {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let videoOracle = try! String(contentsOfFile: "\(KIT)/oracles/k3-oracle.txt", encoding: .utf8)
            .split(separator: "\n").map { String($0.split(separator: " ")[1]) }
        let v = FFmpegSoftwareDecoder()
        try! v.pinLocalRoots([KIT])
        let a = FFmpegSoftwareAudioDecoder()
        try! a.pinLocalRoots([KIT])
        let vs = SessionID(uncheckedEpoch: 101), ases = SessionID(uncheckedEpoch: 102)
        try! await v.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: vs)
        try! await a.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k4.wav", kind: .local, seekable: true), session: ases)
        _ = await v.nextEvent(session: vs) // video .opened

        var vDigests: [String] = []
        var aHash: UInt64 = 14695981039346656037
        var vEOS = false, aEOS = false
        var vFail: String?, aFail: String?
        // Round-robin interleave until both reach EOS.
        while !(vEOS && aEOS) {
            if !vEOS {
                if let ev = await v.nextEvent(session: vs) {
                    switch ev {
                    case .frameDecoded(let f):
                        if let d = await v.frameDigest(handle: f.handle, session: vs) { vDigests.append(d) }
                        await v.releaseFrame(handle: f.handle, session: vs)
                    case .endOfStream: vEOS = true
                    case .failed(let c, let sm): vFail = "v \(c) \(sm)"; vEOS = true
                    default: break
                    }
                } else { vEOS = true }
            }
            if !aEOS {
                if let ev = await a.nextEvent(session: ases) {
                    switch ev {
                    case .pcm(let f): for b in f.bytes { aHash = (aHash ^ UInt64(b)) &* 1099511628211 }
                    case .endOfStream: aEOS = true
                    case .failed(let c, let sm): aFail = "a \(c) \(sm)"; aEOS = true
                    default: break
                    }
                } else { aEOS = true }
            }
        }
        _ = await v.closeAndReport(session: vs)
        await a.close(session: ases)
        let vOK = vDigests == videoOracle
        let aOK = String(format: "%016llx", aHash) == "793d0b08641cf595"
        print("video: \(vDigests.count) frames ==oracle=\(vOK) fail=\(vFail ?? "none")")
        print("audio: digest \(String(format: "%016llx", aHash)) ==oracle=\(aOK) fail=\(aFail ?? "none")")
        print(vOK && aOK && vFail == nil && aFail == nil ? "K10_COEXIST_PASS" : "K10_COEXIST_FAIL")
        exit(vOK && aOK && vFail == nil && aFail == nil ? 0 : 74)
    }
}
