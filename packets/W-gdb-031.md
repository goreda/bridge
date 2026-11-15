# W-gdb-031 pause/resume atomic receipt vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-031

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
FramePump.resume returns an atomic receipt (state-changed, old-anchor-cleared) replacing a racy two-step read; without vectors over the full op matrix (repeated resume, cancel-while-paused, seek-while-paused), a receipt regression reintroduces the race invisibly.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; ResumeReceipt excerpt below); pause-resume-tests suite (5 checks, Linux per the harness map).
- real test command: swift run pause-resume-tests stays green.

## expected behaviour
vectors for the full operation matrix with expected receipt fields per sequence and the exact anchor re-establishment point; deterministic model clock; checker scores a candidate implementation's receipts.

## exact call site and interface
ResumeReceipt's fields (pinned excerpt) are the asserted vocabulary.

## behaviour that must not change
the 5 existing checks stay green; idempotence and the real clock are preserved.

## acceptance test (from the product repo)
the matrix replays green; a dropped anchor-cleared flag fails the affected vector.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 641-660 of 1382)
```swift
    public struct ResumeReceipt: Sendable, Equatable {
        public let changedState: Bool
        public let paceAnchorCleared: Bool
    }
    @discardableResult
    public func resume() -> ResumeReceipt {
        guard paused, let began = pauseBeganWall else {
            return ResumeReceipt(changedState: false, paceAnchorCleared: false)
        }
        let pausedWall = Swift.max(0, ProcessInfo.processInfo.systemUptime - began)
        paused = false
        pauseBeganWall = nil
        pausedWallTotal += pausedWall
        paceAnchorPts = nil
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .pauseResumed,
                       note: "pausedWall_s=\(pausedWall)")
        return ResumeReceipt(changedState: true, paceAnchorCleared: paceAnchorPts == nil)
    }
    /// The park loop: while paused, wait in bounded cancellable slices and
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
