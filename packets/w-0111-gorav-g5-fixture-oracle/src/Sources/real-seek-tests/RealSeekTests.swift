import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

// S5 integration milestone 3: CoreSeekDriver against the REAL FFmpeg adapter on the REAL k3.
// nativeReady end-to-end: open -> binding -> core seek turn -> receipt -> ACK -> post-seek
// backward-keyframe landing verified against the same adapter's sequential pass (self-consistent,
// NOT an independent oracle). NOT Mac native; locked Linux libs.

extension FFmpegSoftwareDecoder: CoreSeekProvider {}

var pass = 0, fail = 0
func chk(_ name: String, _ cond: Bool) {
    if cond { pass += 1; print("PASS \(name)") } else { fail += 1; print("FAIL \(name)") }
}

@main struct RealSeekTests {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"]!
        let src = "\(KIT)/fixtures/seekcheck-src.mp4"
        // sequential pass: digests + keyframes (self-consistency reference)
        struct Rec { let pts: Int64?; let digest: String; let key: Bool }
        var frames: [Rec] = []
        do {
            let d0 = FFmpegSoftwareDecoder()
            try d0.pinLocalRoots([KIT])
            try await d0.open(source: SourceDescriptor(id: src, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: 100))
            while let ev = await d0.nextEvent(session: SessionID(uncheckedEpoch: 100)) {
                if case .frameDecoded(let f) = ev {
                    frames.append(Rec(pts: f.pts, digest: await d0.frameDigest(handle: f.handle, session: SessionID(uncheckedEpoch: 100)) ?? "nil", key: f.isKeyFrame))
                    await d0.releaseFrame(handle: f.handle, session: SessionID(uncheckedEpoch: 100))
                }
                if case .endOfStream = ev { break }
                if case .failed(let c, let m) = ev { print("FAIL seq.decode \(c) \(m)"); exit(1) }
            }
            _ = await d0.closeAndReport(session: SessionID(uncheckedEpoch: 100))
        } catch { print("FAIL seq.open \(error)"); exit(1) }
        chk("seq.frames", frames.count > 12)
        // contract path through the driver
        do {
            let dec = FFmpegSoftwareDecoder()
            try dec.pinLocalRoots([KIT])
            let sid = SessionID(uncheckedEpoch: 200)
            try await dec.open(source: SourceDescriptor(id: src, kind: .local, seekable: true), session: sid)
            // coordinated (enveloped) channel ONLY - legacy pulls would claim legacy mode
            let ev0 = await dec.nextEvent()
            guard case .opened = ev0 else { chk("real.opened", false); exit(1) }
            chk("real.opened", true)
            chk("real.binding", dec.currentBinding() != nil)
            chk("real.caps", dec.capabilities().seekable && dec.capabilities().originKnown)
            let driver = CoreSeekDriver()
            let acks = AckBox()
            // target 1.2s on a 25fps fixture: frame 30 -> backward keyframe 24
            let out = await driver.seek(on: dec, position: try! RationalTime(value: 12, timescale: 10)) { rev, _ in acks.add(rev) }
            guard case .committed(let receipt) = out else { chk("real.committed", false); print("FAIL real.committed outcome=\(out)"); exit(1) }
            chk("real.committed", true)
            guard case .nativeReady(let facts) = receipt.outcome else { chk("real.nativeReady", false); exit(1) }
            chk("real.nativeReady", true)
            chk("real.ackOnce", acks.count == 1)
            chk("real.ackRev2", acks.first?.rawValue == 2)
            chk("real.factsReturn", facts.avSeekReturn != nil && facts.avSeekReturn! >= 0)
            chk("real.factsFlush", facts.flushObserved && facts.packetFeedReset && facts.decoderReset)
            chk("real.factsReconciled", facts.packetAccountingReconciled)
            chk("real.factsTicks", facts.requestedTicks != nil)
            chk("real.revAdvanced", receipt.nextRevision.rawValue == receipt.previousRevision.rawValue + 1)
            chk("real.bindingNowRev2", dec.currentBinding()?.revision.rawValue == 2)
            // post-seek landing: first decoded frame must be the backward keyframe (self-consistent)
            var got: String? = nil
            while got == nil {
                let ev = await dec.nextEvent()
                if case .frameDecoded(_, let f) = ev {
                    got = await dec.frameDigest(handle: f.handle, session: sid)
                    await dec.releaseFrame(handle: f.handle, session: sid)
                }
                if case .endOfStream = ev { break }
                if case .drained = ev { break }
                if case .failed(_, let c, let m) = ev { print("FAIL postseek.decode \(c) \(m)"); break }
            }
            let keys = frames.enumerated().filter { $0.element.key }.map { $0.offset }
            let wantIdx = keys.filter { $0 <= 30 }.last ?? keys[0]
            chk("real.landingBackwardKf", got == frames[wantIdx].digest)
            // second seek: correlation monotonicity + revision 3
            let out2 = await driver.seek(on: dec, position: try! RationalTime(value: 1, timescale: 10)) { rev, _ in acks.add(rev) }
            guard case .committed(let r2) = out2 else { chk("real.secondCommitted", false); exit(1) }
            chk("real.secondCommitted", true)
            chk("real.secondAckRev3", acks.last?.rawValue == 3)
            chk("real.corrMonotonic", r2.correlationID.rawValue > receipt.correlationID.rawValue)
            _ = await dec.closeAndReport(session: sid)
            // real multi-pull closed drain: repeated core seeks after close, all typed, no ACK
            let acksBefore = acks.count
            for _ in 0..<3 {
                let outC = await driver.seek(on: dec, position: try! RationalTime(value: 1, timescale: 10)) { rev, _ in acks.add(rev) }
                if case .admissionRefused = outC { chk("real.closedDrain.typed", true) } else { chk("real.closedDrain.typed", false) }
            }
            chk("real.closedDrain.noAck", acks.count == acksBefore)
        } catch { print("FAIL real.path \(error)"); exit(1) }
        print("FINAL pass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }
}
final class AckBox: @unchecked Sendable {
    private let l = NSLock(); private var v: [SeekRevision] = []
    var count: Int { l.lock(); defer { l.unlock() }; return v.count }
    var first: SeekRevision? { l.lock(); defer { l.unlock() }; return v.first }
    var last: SeekRevision? { l.lock(); defer { l.unlock() }; return v.last }
    func add(_ r: SeekRevision) { l.lock(); v.append(r); l.unlock() }
}
