#if canImport(AppKit)
import AppKit
import XCTest
import GorAVEmbeddedShell
import GorAVPlaybackCore
import GorAVNativeProbeKit

final class EmbeddedPreparedShotTests: XCTestCase {
    /// NOT_RUN on Linux. Requires two distinct local yuv420p videos; A must
    /// include at least 15 seconds of supported audio/video. Runs a real sink.
    @MainActor
    func testLiveVideoSwapKeepsRealAudioBindingAndClock() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["GORAV_PREPARED_A"], let b = env["GORAV_PREPARED_B"], a != b else {
            throw XCTSkip("set GORAV_PREPARED_A and GORAV_PREPARED_B to distinct local fixtures")
        }
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let session = GorAVEmbeddedSession(hostView: view, runID: "prepared-shot-live-witness")
        do {
            try await session.open(path: a)
            var now: Double?
            for _ in 0..<500 {
                now = await session.preparedShotFilmTime()
                if now != nil { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let filmNow = try XCTUnwrap(now)
            let epoch = try XCTUnwrap(session.preparedShotEpoch)
            let zero = try RationalTime(value: 0, timescale: 1)
            let video = SourceRef(id: a, kind: .local, startOffset: zero)
            let prepared = try await session.prepare(PreparedShot(shotID: UUID(), video: video,
                audio: video, filmClockEpoch: epoch))
            let adoptedWitness = try XCTUnwrap(session.preparedShotLiveWitness())
            do {
                _ = try await session.replaceVideo(at: zero,
                    with: SourceRef(id: "/missing-staged-source", kind: .local, startOffset: zero))
                XCTFail("missing first swap admitted")
            } catch { }
            let aborted = await session.abortUncommittedPreparation()
            XCTAssertEqual(aborted, .released)
            let releasedReceipt = await session.currentReceipt()
            XCTAssertNil(releasedReceipt)
            // No stop/reset/source swap was used to recover ordinary playback.
            let afterAbort = try XCTUnwrap(session.preparedShotLiveWitness())
            XCTAssertEqual(afterAbort.audioBinding, adoptedWitness.audioBinding)
            XCTAssertEqual(afterAbort.audioUnit, adoptedWitness.audioUnit)
            XCTAssertEqual(afterAbort.clock, adoptedWitness.clock)
            XCTAssertEqual(afterAbort.videoToken, adoptedWitness.videoToken)
            XCTAssertEqual(afterAbort.audioStopCalls, adoptedWitness.audioStopCalls)
            _ = try await session.prepare(PreparedShot(shotID: UUID(), video: video,
                audio: video, filmClockEpoch: epoch))
            let before = try XCTUnwrap(session.preparedShotLiveWitness())
            let target = try RationalTime(value: Int64((filmNow + 3) * 1000), timescale: 1000)
            let replacement = try await session.replaceVideo(at: target,
                with: SourceRef(id: b, kind: .local, startOffset: zero))
            let postCommitAbort = await session.abortUncommittedPreparation()
            XCTAssertEqual(postCommitAbort, .alreadyCommitted)
            let after = try XCTUnwrap(session.preparedShotLiveWitness())
            XCTAssertEqual(replacement.committedAt, target)
            XCTAssertEqual(replacement.epoch, prepared.epoch)
            XCTAssertEqual(replacement.audioBindingID, prepared.audioBindingID)
            XCTAssertTrue(replacement.audioBindingPreserved)
            XCTAssertEqual(after.audioBinding, before.audioBinding)
            XCTAssertEqual(after.audioUnit, before.audioUnit)
            XCTAssertEqual(after.clock, before.clock)
            XCTAssertEqual(after.sinkGeneration, before.sinkGeneration)
            XCTAssertEqual(after.audioStopCalls, before.audioStopCalls)
            XCTAssertNotEqual(after.videoToken, before.videoToken)
            XCTAssertGreaterThan(after.consumedBytes, before.consumedBytes)
            // A refused replacement leaves the receipt and native bindings intact.
            do {
                _ = try await session.replaceVideo(at: target,
                    with: SourceRef(id: "/nonexistent-prepared-video", kind: .local, startOffset: zero))
                XCTFail("missing video admitted")
            } catch { }
            let unchanged = await session.currentReceipt()
            XCTAssertEqual(unchanged?.priorVideo, replacement.priorVideo)
            XCTAssertEqual(unchanged?.committedAt, replacement.committedAt)
            let stable = try XCTUnwrap(session.preparedShotLiveWitness())
            XCTAssertEqual(stable.videoToken, after.videoToken)
            XCTAssertEqual(stable.audioBinding, after.audioBinding)
            await session.cancel()
        } catch {
            await session.cancel()
            throw error
        }
    }
}
#endif
