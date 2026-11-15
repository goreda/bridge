# W-gdb-027 transport snapshot truthfulness vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-027

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
transport snapshots (bytes read, buffered, EOF) must be truthful - an inferred percentage or guessed EOF shows the user a lying progress/buffer display. the snapshot type exists; there is no independent truthfulness vector set.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift (sha256 5f0ea2a1, 42 lines, whole below); the active-transport-tests suite (16 PASS on Linux per STATUS.md at the pin).
- real test command: swift run active-transport-tests stays green.

## expected behaviour
scripted sources (local file + loopback HTTP) with known byte behavior and expected snapshot tables - including honest-unknown cases that must remain unknown, never inferred; a checker asserts a candidate surface reports exactly the table.

## exact call site and interface
ActiveTransportSnapshot's fields (pinned excerpt) are the asserted vocabulary.

## behaviour that must not change
the 16 existing checks stay green; unknown stays unknown (typed), never a guess.

## acceptance test (from the product repo)
the vector set replays green against the pinned snapshot producer; a seeded inferred value fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift (sha256 5f0ea2a1, lines 1-42 of 42)
```swift
import Foundation
import GorAVNativeProbeKit
import CFFmpeg

/// A queue-time observation of the active AVIOContext, not a cache model.
/// nil means unavailable/not observed, never zero. No paths, URLs or headers.
public struct ActiveTransportSnapshot: Equatable, Sendable {
    public let source: SourceToken
    public let session: SeekSessionID
    public let revision: SeekRevision
    /// FFmpeg AVIO bytes_read counter, cumulative for this open. Includes probe
    /// reads and rereads; not network-only unique bytes or file position.
    public let bytesRead: Int64?
    /// Bytes remaining in AVIO's current user-space input buffer only.
    public let bufferAvailableBytes: Int?
    /// true when AVIO has observed EOF; nil before that or without an AVIOContext.
    /// A seek can clear this observation. No prediction that the remote is finished.
    public let eofObserved: Bool?
    /// Negative FFmpeg AVIO error when present; nil means no error observed,
    /// not an assertion that transport is healthy or unable to stall.
    public let errorCode: Int32?

    // Called only inside the format owner's native queue, never retains pb.
    static func capture(_ pb: UnsafePointer<AVIOContext>?, source: SourceToken,
                        session: SeekSessionID, revision: SeekRevision) -> Self {
        guard let pb else {
            return Self(source: source, session: session, revision: revision,
                        bytesRead: nil, bufferAvailableBytes: nil, eofObserved: nil, errorCode: nil)
        }
        let count = pb.pointee.bytes_read
        let available = gorav_avio_buffer_available(pb)
        return Self(source: source, session: session, revision: revision,
                    bytesRead: count >= 0 ? count : nil,
                    bufferAvailableBytes: available >= 0 ? Int(available) : nil,
                    eofObserved: pb.pointee.eof_reached != 0 ? true : nil,
                    errorCode: pb.pointee.error < 0 ? pb.pointee.error : nil)
    }
}

public enum ActiveTransportRefusal: Error, Equatable, Sendable {
    case notOpen, staleBinding
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
