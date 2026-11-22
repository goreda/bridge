// PlayerControlPlaneTests - runnable XCTest suite for the pure-core control
// plane (Linux venue: swift test --filter PlayerControlPlaneTests).
import XCTest
@testable import GorAVPlaybackCore

final class PlayerControlPlaneTests: XCTestCase {

    private func drivenToPlaying() -> PlayerControlPlane {
        var p = PlayerControlPlane()
        _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.play)
        return p
    }

    func testHappyPathToClosed() {
        var p = PlayerControlPlane()
        XCTAssertEqual(p.state, .idle)
        XCTAssertEqual(p.apply(.beginLoad), .success(.loading))
        XCTAssertEqual(p.apply(.loadReady), .success(.ready))
        XCTAssertEqual(p.apply(.play), .success(.playing))
        XCTAssertEqual(p.apply(.pause), .success(.paused))
        XCTAssertEqual(p.apply(.resume), .success(.playing))
        XCTAssertEqual(p.apply(.close), .success(.closing))
        XCTAssertEqual(p.apply(.closed), .success(.closed))
        // Count contract (PlayerControlPlane.swift: generation starts at 0,
        // advances on EVERY accepted transition): exactly the 7 accepted
        // transitions above => 7. Venue r1/r2 run proved 8 wrong (actual 7).
        XCTAssertEqual(p.generation, 7)
    }

    func testSeekFromPlayingCommittedReturnsPlaying() {
        var p = drivenToPlaying()
        XCTAssertEqual(p.apply(.beginSeek), .success(.seeking))
        XCTAssertEqual(p.seekOrigin, .playing)
        XCTAssertEqual(p.apply(.seekCommitted), .success(.playing))
        XCTAssertNil(p.seekOrigin)
    }

    func testSeekFromPausedCommittedReturnsPaused_originPreserved() {
        var p = drivenToPlaying()
        _ = p.apply(.pause)
        let g0 = p.generation
        XCTAssertEqual(p.apply(.beginSeek), .success(.seeking))
        XCTAssertEqual(p.seekOrigin, .paused)
        XCTAssertEqual(p.apply(.seekCommitted), .success(.paused))   // r3: never silently resumes
        XCTAssertNil(p.seekOrigin)
        XCTAssertEqual(p.generation, g0 + 2)
    }

    func testSeekFromPausedRefusedReturnsPaused() {
        var p = drivenToPlaying()
        _ = p.apply(.pause)
        _ = p.apply(.beginSeek)
        XCTAssertEqual(p.apply(.seekRefused), .success(.paused))
        XCTAssertNil(p.seekOrigin)
    }

    func testReentrantBeginSeekRefused_stateAndGenerationUntouched() {
        var p = drivenToPlaying()
        _ = p.apply(.beginSeek)
        let g = p.generation
        if case .failure(.illegalTransition(from: .seeking, control: .beginSeek)) = p.apply(.beginSeek) {} else {
            XCTFail("re-entrant beginSeek must refuse typed")
        }
        XCTAssertEqual(p.state, .seeking)
        XCTAssertEqual(p.generation, g)
        XCTAssertEqual(p.seekOrigin, .playing)
    }

    func testRefusedControlDoesNotAdvanceGeneration_staleFence() {
        var p = drivenToPlaying()
        let g = p.generation
        XCTAssertEqual(p.apply(.resume), .failure(.illegalTransition(from: .playing, control: .resume)))
        XCTAssertEqual(p.generation, g)   // a consumer fencing on g sees NO phantom transition
        XCTAssertEqual(p.apply(.pause), .success(.paused))
        XCTAssertEqual(p.generation, g + 1)
    }

    func testSeekRequiresCloseGoesClosing() {
        var p = drivenToPlaying()
        _ = p.apply(.beginSeek)
        XCTAssertEqual(p.apply(.seekRequiresClose), .success(.closing))
        XCTAssertNil(p.seekOrigin)
    }

    func testTerminalStatesRefuseEverything() {
        var p = drivenToPlaying()
        _ = p.apply(.close); _ = p.apply(.closed)
        XCTAssertEqual(p.apply(.play), .failure(.terminal(.closed)))
        XCTAssertEqual(p.apply(.close), .failure(.terminal(.closed)))
        XCTAssertEqual(p.apply(.fail), .failure(.terminal(.closed)))
        var q = drivenToPlaying()
        _ = q.apply(.fail)
        XCTAssertEqual(q.state, .failed)
        XCTAssertEqual(q.apply(.play), .failure(.terminal(.failed)))
    }

    func testLoadFailureFromLoading() {
        var p = PlayerControlPlane()
        _ = p.apply(.beginLoad)
        XCTAssertEqual(p.apply(.loadFailed), .success(.failed))
    }

    func testFailFromAnyNonTerminalState() {
        for (setup, expectFrom): (String, PlayerLifecycleState) in
            [("idle", .idle), ("loading", .loading), ("ready", .ready),
             ("playing", .playing), ("paused", .paused), ("seeking", .seeking), ("closing", .closing)] {
            var p = PlayerControlPlane()
            switch setup {
            case "loading": _ = p.apply(.beginLoad)
            case "ready": _ = p.apply(.beginLoad); _ = p.apply(.loadReady)
            case "playing": _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.play)
            case "paused": _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.play); _ = p.apply(.pause)
            case "seeking": _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.play); _ = p.apply(.beginSeek)
            case "closing": _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.close)
            default: break
            }
            XCTAssertEqual(p.state, expectFrom, "setup \(setup)")
            XCTAssertEqual(p.apply(.fail), .success(.failed), "fail from \(setup)")
            XCTAssertNil(p.seekOrigin)
        }
    }

    func testIllegalEarlyControls() {
        var p = PlayerControlPlane()
        XCTAssertEqual(p.apply(.play), .failure(.illegalTransition(from: .idle, control: .play)))
        XCTAssertEqual(p.apply(.close), .failure(.illegalTransition(from: .idle, control: .close)))
        XCTAssertEqual(p.apply(.beginSeek), .failure(.illegalTransition(from: .idle, control: .beginSeek)))
        _ = p.apply(.beginLoad); _ = p.apply(.loadReady)
        XCTAssertEqual(p.apply(.pause), .failure(.illegalTransition(from: .ready, control: .pause)))
        XCTAssertEqual(p.apply(.resume), .failure(.illegalTransition(from: .ready, control: .resume)))
    }

    func testDerivedFlags() {
        var p = PlayerControlPlane()
        XCTAssertFalse(p.seekAllowed); XCTAssertFalse(p.audioSilenced)
        _ = p.apply(.beginLoad); _ = p.apply(.loadReady); _ = p.apply(.play)
        XCTAssertTrue(p.seekAllowed); XCTAssertFalse(p.audioSilenced)
        _ = p.apply(.pause)
        XCTAssertTrue(p.seekAllowed); XCTAssertTrue(p.audioSilenced)
        _ = p.apply(.beginSeek)
        XCTAssertFalse(p.seekAllowed); XCTAssertTrue(p.audioSilenced)
    }
}
