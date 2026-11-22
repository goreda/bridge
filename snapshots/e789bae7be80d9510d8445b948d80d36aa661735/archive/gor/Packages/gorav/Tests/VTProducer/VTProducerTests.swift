import Foundation
#if SWIFT_PACKAGE
import GorAVPlaybackCore
#endif

private final class Probe {
    let drop: () -> Void
    init(drop: @escaping () -> Void) { self.drop = drop }
    deinit { drop() }
}

@main struct VTProducerTests {
    static func main() async throws {
        let source = SourceSession(session: 42, revision: 3)
        let origin = NativeFrameProvenance(source: source, ptsSeconds: 12.5, durationSeconds: 0.04)
        var assertions = 0
        func expect(_ ok: @autoclosure () -> Bool) { precondition(ok()); assertions += 1 }
        expect(origin.admits(source: source, ptsSeconds: 12.5, durationSeconds: 0.04))
        expect(!origin.admits(source: SourceSession(session: 43, revision: 3), ptsSeconds: 12.5, durationSeconds: 0.04))
        expect(!origin.admits(source: SourceSession(session: 42, revision: 4), ptsSeconds: 12.5, durationSeconds: 0.04))
        expect(!origin.admits(source: source, ptsSeconds: 12.6, durationSeconds: 0.04))
        expect(!origin.admits(source: source, ptsSeconds: .nan, durationSeconds: 0.04))
        expect(!origin.admits(source: source, ptsSeconds: 12.5, durationSeconds: .infinity))
        expect(!origin.admits(source: source, ptsSeconds: 12.5, durationSeconds: 0))
        expect(!NativeFrameProvenance(source: SourceSession(session: 0, revision: 0), ptsSeconds: 0, durationSeconds: 1)
            .admits(source: SourceSession(session: 0, revision: 0), ptsSeconds: 0, durationSeconds: 1))

        // Exercise the exact NativeFrameSlot stored by MetalRenderer, with
        // a simulated GPU strong reader independent of the recycled slot.
        var drops = 0
        var slot = NativeFrameSlot()
        for _ in 0..<1000 {
            weak var weakProbe: Probe?
            weak var weakOwner: NativeFrameOwnership?
            var gpuReader: NativeFrameOwnership?
            do {
                let probe = Probe { drops += 1 }
                weakProbe = probe
                let owner = NativeFrameOwnership(retaining: probe, provenance: origin)
                weakOwner = owner
                slot.replace(with: owner)
                gpuReader = owner
            }
            expect(weakProbe != nil && weakOwner != nil)
            slot.recycle()
            expect(weakProbe != nil && weakOwner != nil) // GPU owns it, no early release
            expect(gpuReader?.provenance == origin)
            gpuReader = nil
            expect(weakProbe == nil && weakOwner == nil)
        }
        expect(drops == 1000)
        // Replacement recycles the old slot owner, not only explicit clear.
        weak var replaced: Probe?
        do {
            let probe = Probe { drops += 1 }; replaced = probe
            slot.replace(with: NativeFrameOwnership(retaining: probe, provenance: origin))
        }
        slot.replace(with: nil)
        expect(replaced == nil && drops == 1001)

        // Actual production ticket cell: provenance refusal does not burn a
        // valid ticket; same origin/PTS later commits once, replay refuses.
        let commit = CancelCommit(sessionEpoch: 42)
        let p0 = NativeFrameProvenance(source: SourceSession(session: 42, revision: 0), ptsSeconds: 1, durationSeconds: 0.04)
        let ticket = commit.tryAdmit(revision: 0, framePTS: 1, frameDigest: "vt-zerocopy")!
        var assignments = 0
        func nativeCommit(_ p: NativeFrameProvenance) -> Bool {
            commit.commitFrame(ticket, framePTS: 1, frameDigest: "vt-zerocopy", permit: {
                p.admits(source: SourceSession(session: commit.sessionEpoch, revision: ticket.revision), ptsSeconds: 1, durationSeconds: 0.04)
            }, assign: { assignments += 1 })
        }
        expect(!nativeCommit(origin))
        expect(nativeCommit(p0))
        expect(!nativeCommit(p0))
        expect(assignments == 1)
        let oldTicket = commit.tryAdmit(revision: 0, framePTS: 2, frameDigest: "vt-zerocopy")!
        _ = try commit.bumpRevision()
        expect(!commit.commitFrame(oldTicket, framePTS: 2, frameDigest: "vt-zerocopy", assign: { assignments += 1 }))
        expect(assignments == 1)

        // Normalized eight/ten-bit samples: both white points must be near
        // one, not the old ten-bit quarter-scale result. Neutral black=0.
        for depth in [8, 10] {
            let c = VTYUVToRGBCoefficients.resolve(matrix: .bt709, bitDepth: depth)
            let maximum: Float = depth == 8 ? 255 : 1023
            let shift: Float = depth == 8 ? 1 : 4
            let y = 235 * shift / maximum
            let black = 16 * shift / maximum
            expect(abs(c.yGain * (y - c.yCenter) - 1) < 0.002)
            expect(abs(c.yGain * (black - c.yCenter)) < 0.00001)
        }
        #if canImport(AppKit) && canImport(Metal) && SWIFT_PACKAGE
        try await nativeProducerSlotTests()
        #else
        print("UNRUN Darwin CVPixelBuffer/Metal slot execution; portable ownership uses a deinit probe")
        #endif
        print("PASS VT-PRODUCER portable assertions=\(assertions), recycle=1001, generation/PTS/ticket refusal, 8/10-bit coefficient witnesses")
    }
}
