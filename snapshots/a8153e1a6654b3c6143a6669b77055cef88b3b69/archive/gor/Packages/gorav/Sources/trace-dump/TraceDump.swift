import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// K13: snapshot route to EOS + close, then dump the bounded session trace
// as JSON for the receipt gate (team2 trace_receipt_gate_candidate r1a).
@main
struct TraceDump {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let fx = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: "\(KIT)/fixtures/first-ppm-rgb24-17x11.ppm")))
        guard let snapshot = ImmutableInputSnapshot(pinned: fx, expectedBytes: 574,
                sha256Hex: "009889e24805044e676ce86f9d26ed3b8cd60e9a014d623ef4e0ef48ed451fa9") else {
            print("K13 FAIL: pin"); exit(66)
        }
        let decoder = FFmpegSoftwareDecoder()
        let session = SessionID(uncheckedEpoch: 121)
        do { try await decoder.openSnapshot(snapshot, session: session) }
        catch { print("K13 FAIL: open \(error)"); exit(67) }
        var frames = 0, eos = false
        while let ev = await decoder.nextEvent(session: session) {
            switch ev {
            case .frameDecoded(let f): frames += 1; await decoder.releaseFrame(handle: f.handle, session: session)
            case .endOfStream: eos = true
            case .failed(let c, let sm): print("K13 FAIL: \(c) \(sm)"); exit(70)
            default: break
            }
        }
        _ = await decoder.closeAndReport(session: session)
        guard eos else { print("K13 FAIL: no EOS"); exit(71) }
        switch await decoder.observeSessionTrace(session: session) {
        case .failure(let r): print("K13 FAIL: trace \(r)"); exit(72)
        case .success(let snap):
            var recs: [String] = []
            for r in snap.records {
                let pr = r.providerResult.map { String($0) } ?? "null"
                recs.append("{\"sequence\":\(r.sequence),\"kind\":\"\(r.kind.rawValue)\",\"providerResult\":\(pr),\"selectedStreamIndex\":\(r.selectedStreamIndex)}")
            }
            let teardown: String
            switch snap.customIOLogicalTeardown {
            case .absent: teardown = "absent"
            case .called: teardown = "called"
            case .completed: teardown = "completed"
            }
            let json = "{\"sessionEpoch\":\(snap.sessionEpoch),\"capacity\":\(snap.capacity),\"overflowed\":\(snap.overflowed),\"customIOLogicalTeardown\":\"\(teardown)\",\"records\":[\(recs.joined(separator: ","))]}"
            let out = "\(KIT)/oracles/trace-snapshot-route.json"
            try! json.write(toFile: out, atomically: true, encoding: .utf8)
            print("frames=\(frames) eos=\(eos) records=\(snap.records.count) -> \(out)")
            print("kinds=\(snap.records.map { $0.kind.rawValue }.joined(separator: ","))")
        }
        // Second dump: PATH route over the mp4 (no custom IO -> customIOAbsent).
        do {
            let d2 = FFmpegSoftwareDecoder()
            try! d2.pinLocalRoots([KIT])
            let ses2 = SessionID(uncheckedEpoch: 122)
            try! await d2.open(source: SourceDescriptor(id: "\(KIT)/fixtures/fixture-k3.mp4", kind: .local, seekable: true), session: ses2)
            var n = 0
            while let ev = await d2.nextEvent(session: ses2) {
                if case .frameDecoded(let f) = ev { n += 1; await d2.releaseFrame(handle: f.handle, session: ses2) }
                if case .endOfStream = ev { break }
                if case .failed(let c, let sm) = ev { print("K13b FAIL: \(c) \(sm)"); exit(73) }
            }
            _ = await d2.closeAndReport(session: ses2)
            if case .success(let snap) = await d2.observeSessionTrace(session: ses2) {
                var recs: [String] = []
                for r in snap.records {
                    let pr = r.providerResult.map { String($0) } ?? "null"
                    recs.append("{\"sequence\":\(r.sequence),\"kind\":\"\(r.kind.rawValue)\",\"providerResult\":\(pr),\"selectedStreamIndex\":\(r.selectedStreamIndex)}")
                }
                let json = "{\"sessionEpoch\":\(snap.sessionEpoch),\"capacity\":\(snap.capacity),\"overflowed\":\(snap.overflowed),\"customIOLogicalTeardown\":\"\(snap.customIOLogicalTeardown == .completed ? "completed" : (snap.customIOLogicalTeardown == .called ? "called" : "absent"))\",\"records\":[\(recs.joined(separator: ","))]}"
                let out = "\(KIT)/oracles/trace-path-route.json"
                try! json.write(toFile: out, atomically: true, encoding: .utf8)
                print("path-route frames=\(n) records=\(snap.records.count) -> \(out)")
                print("kinds=\(snap.records.map { $0.kind.rawValue }.joined(separator: ","))")
            }
        }
        exit(0)
    }
}
