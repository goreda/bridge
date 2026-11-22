import Foundation

// Run alongside the product source in the SAME product commit:
// swiftc -parse-as-library archive/gor/Sources/gor/ThreeD.swift (PreparedShotPlayback.swift section) \
//   archive/gor/Tests/PreparedShotPlaybackChecks.swift -o /tmp/prepared-shot-checks
// /tmp/prepared-shot-checks
@MainActor
private final class FakeMultiSourceSession: PreparedShotSessionBackend {
    var requests: [PreparedShotPlayback.Request] = []
    var rebaseReceipt = false
    var restartAudio = false
    var fail = false
    var suspend = false
    var pending: CheckedContinuation<Void, Never>?
    enum Witness: Error { case refused }
    func applyPreparedShot(_ r: PreparedShotPlayback.Request) async throws
        -> PreparedShotPlayback.Receipt {
        requests.append(r)
        if suspend {
            await withCheckedContinuation { pending = $0 }
        }
        if fail { throw Witness.refused }
        return PreparedShotPlayback.Receipt(sessionID: r.sessionID,
            operationID: r.operationID, videoURL: r.videoURL,
            sourceAudioURL: r.sourceAudioURL, requestedFilmTime: r.filmTime,
            committedFilmTime: r.filmTime,
            rebased: rebaseReceipt,
            preservedRunningAudio: restartAudio ? false : r.preserveRunningAudio)
    }
}

@main
struct PreparedShotPlaybackChecks {
    @MainActor
    static func main() async throws {
        let audio = URL(fileURLWithPath: "/films/source, with spaces.mov")
        let video = URL(fileURLWithPath: "/prepared/first render.mov")
        let second = URL(fileURLWithPath: "/prepared/second render.mov")
        let backend = FakeMultiSourceSession()
        let player = PreparedShotPlayback(backend: backend)
        let first = try await player.loadPreparedShot(render: video, source: audio, start: 8.125)
        precondition(backend.requests[0].operation == .adoptRunningSource)
        precondition(!backend.requests[0].rebaseStartTime)
        precondition(backend.requests[0].preserveRunningAudio)
        precondition(first.committedFilmTime == 8.125)
        print("PASS adopt running source audio, absolute film time, no rebase")
        let next = try await player.loadPreparedShot(render: second, source: audio, start: 22.5)
        precondition(backend.requests[1].operation == .replaceVideo)
        precondition(backend.requests[1].preserveRunningAudio)
        precondition(first.sessionID == next.sessionID)
        precondition(first.operationID != next.operationID)
        print("PASS replace video preserves one source audio session")
        let restored = try await player.loadSource2D(file: audio, start: 24.0)
        precondition(backend.requests[2].operation == .returnToSource)
        precondition(restored.videoURL == audio && restored.sourceAudioURL == audio)
        precondition(restored.sessionID == first.sessionID && restored.preservedRunningAudio)
        print("PASS return source video without restarting audio")
        do {
            _ = try await player.loadPreparedShot(render: video, source: second, start: 1)
            preconditionFailure("source changed silently")
        } catch PreparedShotPlayback.Failure.sourceAudioChanged {}
        precondition(backend.requests.count == 3)
        print("PASS different source requires new media lifecycle")
        for bad in [Double.nan, Double.infinity, -1] {
            do {
                _ = try await player.loadPreparedShot(render: video, source: audio, start: bad)
                preconditionFailure("invalid start admitted")
            } catch PreparedShotPlayback.Failure.invalidFilmTime {}
        }
        precondition(backend.requests.count == 3)
        print("PASS bad film times rejected before backend")
        do {
            _ = try await player.loadPreparedShot(render: URL(string:"https://example.invalid/render")!, source: audio, start: 1)
            preconditionFailure("network admitted to local prepared path")
        } catch PreparedShotPlayback.Failure.notLocalFile {}
        print("PASS local prepared source boundary")
        let unopened = PreparedShotPlayback(backend: FakeMultiSourceSession())
        do {
            _ = try await unopened.loadSource2D(file: audio, start: 0)
            preconditionFailure("unopened restore")
        } catch PreparedShotPlayback.Failure.noSourceSession {}
        print("PASS unopened source restore rejected")
        backend.rebaseReceipt = true
        do {
            _ = try await player.loadPreparedShot(render: video, source: audio, start: 26)
            preconditionFailure("rebase accepted")
        } catch PreparedShotPlayback.Failure.receiptMismatch {}
        precondition(player.current == nil && player.invalidated)
        print("PASS rebased backend receipt invalidates coordinator")
        do {
            _ = try await player.loadPreparedShot(render: video, source: audio, start: 27)
            preconditionFailure("invalidated session reused")
        } catch PreparedShotPlayback.Failure.sessionInvalidated {}
        print("PASS no silent reopen after partial failure")
        let restartedBackend = FakeMultiSourceSession()
        let restartedPlayer = PreparedShotPlayback(backend: restartedBackend)
        _ = try await restartedPlayer.loadPreparedShot(render: video, source: audio, start: 1)
        restartedBackend.restartAudio = true
        do {
            _ = try await restartedPlayer.loadPreparedShot(render: second, source: audio, start: 2)
            preconditionFailure("audio restarted")
        } catch PreparedShotPlayback.Failure.receiptMismatch {}
        print("PASS restarted audio receipt rejected")
        let refusedBackend = FakeMultiSourceSession()
        refusedBackend.fail = true
        let refusedPlayer = PreparedShotPlayback(backend: refusedBackend)
        do {
            _ = try await refusedPlayer.loadPreparedShot(render: video, source: audio, start: 0)
            preconditionFailure("failure concealed")
        } catch FakeMultiSourceSession.Witness.refused {}
        precondition(refusedPlayer.invalidated && refusedPlayer.current == nil)
        print("PASS typed backend refusal is not playback success")
        let heldBackend = FakeMultiSourceSession()
        heldBackend.suspend = true
        let heldPlayer = PreparedShotPlayback(backend: heldBackend)
        let task = Task { @MainActor in
            try await heldPlayer.loadPreparedShot(render: video, source: audio, start: 0)
        }
        while heldBackend.pending == nil { await Task.yield() }
        do {
            _ = try await heldPlayer.loadPreparedShot(render: second, source: audio, start: 1)
            preconditionFailure("concurrent mutation admitted")
        } catch PreparedShotPlayback.Failure.operationInFlight {}
        heldBackend.pending?.resume()
        _ = try await task.value
        precondition(heldBackend.requests.count == 1)
        print("PASS concurrent operation rejected during await")
        print("ALL PREPARED-SHOT CHECKS PASS (fake backend only, not native playback)")
    }
}
