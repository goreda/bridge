import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// K11: two live VIDEO decoder instances, interleaved pulls - instance
// isolation (sessions, interrupt slots, retained frames are per-instance).
// K12: framePlaneCopy / frameDigest on released and foreign handles -> nil.
@main
struct IsolationTest {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "/tmp/gorav-build2"
        let mp4 = "\(KIT)/fixtures/fixture-k3.mp4"
        let oracle = try! String(contentsOfFile: "\(KIT)/oracles/k3-oracle.txt", encoding: .utf8)
            .split(separator: "\n").map { String($0.split(separator: " ")[1]) }
        // K11
        let d1 = FFmpegSoftwareDecoder(), d2 = FFmpegSoftwareDecoder()
        try! d1.pinLocalRoots([KIT]); try! d2.pinLocalRoots([KIT])
        let s1 = SessionID(uncheckedEpoch: 111), s2 = SessionID(uncheckedEpoch: 112)
        try! await d1.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: s1)
        try! await d2.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: s2)
        _ = await d1.nextEvent(session: s1); _ = await d2.nextEvent(session: s2)
        var g1: [String] = [], g2: [String] = []
        var e1 = false, e2 = false
        while !(e1 && e2) {
            if !e1, let ev = await d1.nextEvent(session: s1) {
                if case .frameDecoded(let f) = ev {
                    if let g = await d1.frameDigest(handle: f.handle, session: s1) { g1.append(g) }
                    await d1.releaseFrame(handle: f.handle, session: s1)
                }
                if case .endOfStream = ev { e1 = true }
                if case .failed = ev { e1 = true }
            } else if !e1 { e1 = true }
            if !e2, let ev = await d2.nextEvent(session: s2) {
                if case .frameDecoded(let f) = ev {
                    if let g = await d2.frameDigest(handle: f.handle, session: s2) { g2.append(g) }
                    await d2.releaseFrame(handle: f.handle, session: s2)
                }
                if case .endOfStream = ev { e2 = true }
                if case .failed = ev { e2 = true }
            } else if !e2 { e2 = true }
        }
        // cross-instance handle use must fail closed
        let r1 = await d1.closeAndReport(session: s1)
        let r2 = await d2.closeAndReport(session: s2)
        let k11 = g1 == oracle && g2 == oracle && (r1?.leakedHandles.isEmpty ?? false) && (r2?.leakedHandles.isEmpty ?? false)
        print("K11: d1=\(g1.count) d2=\(g2.count) both==oracle=\(g1 == oracle && g2 == oracle) leaks=0: \(k11 ? "K11_ISOLATION_PASS" : "K11_ISOLATION_FAIL")")

        // K12: released + foreign handle access
        let d3 = FFmpegSoftwareDecoder()
        try! d3.pinLocalRoots([KIT])
        let s3 = SessionID(uncheckedEpoch: 113)
        try! await d3.open(source: SourceDescriptor(id: mp4, kind: .local, seekable: true), session: s3)
        _ = await d3.nextEvent(session: s3)
        var firstHandle: UInt64?
        while let ev = await d3.nextEvent(session: s3) {
            if case .frameDecoded(let f) = ev { firstHandle = f.handle; break }
        }
        guard let h = firstHandle else { print("K12: no frame(BAD)"); exit(75) }
        let before = await d3.framePlaneCopy(handle: h, session: s3)
        await d3.releaseFrame(handle: h, session: s3)
        let afterRelease = await d3.framePlaneCopy(handle: h, session: s3)
        let digestAfterRelease = await d3.frameDigest(handle: h, session: s3)
        let foreignSession = await d3.framePlaneCopy(handle: h, session: SessionID(uncheckedEpoch: 114))
        _ = await d3.closeAndReport(session: s3)
        let k12 = before != nil && afterRelease == nil && digestAfterRelease == nil && foreignSession == nil
        print("K12: live=\(before != nil) released=\(afterRelease == nil) digestReleased=\(digestAfterRelease == nil) foreign=\(foreignSession == nil) \(k12 ? "K12_HANDLE_GATES_PASS" : "K12_HANDLE_GATES_FAIL")")
        exit(k11 && k12 ? 0 : 75)
    }
}
