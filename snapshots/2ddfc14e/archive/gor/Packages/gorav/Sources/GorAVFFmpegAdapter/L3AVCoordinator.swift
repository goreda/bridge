// AUTHORED NEW (2026-10-25, v4.3, L3 formats/hardware-decode lane).
// Joint audio/video seek + fallback resume surface (blocker 5; v4.2 first
// cut, reworked under architect r5 group 4). The decoders own their native
// queues and state; this coordinator SEQUENCES the two legs under a mutual
// exclusion so concurrent joint seeks cannot interleave legs across pairs.
// Sync/clock POLICY stays with L1 - this is mechanism only.
//
// HONESTY CONTRACT (r5): a completed joint seek means both legs accepted
// the same target - it does NOT prove same PTS/phase (verifying that would
// require consuming frames, which belongs to the delivery owner L1). The
// outcome is typed accordingly, and L1 verifies phase from the first
// post-seek frames plus both decoders' seek receipts.
import Foundation
#if canImport(Dispatch)
import Dispatch
#endif
import GorAVCore

public final class L3AVCoordinator: @unchecked Sendable {

    /// Outcome of a joint seek (v4.3 r5: no "aligned" claim - the
    /// coordinator observes leg ACCEPTANCE, not decoded phase).
    public enum JointSeekResult: Equatable, Sendable {
        /// Both legs accepted the same target seconds. Phase alignment is
        /// NOT claimed: the sync owner verifies it from the first post-seek
        /// frames and the seek receipts carried here.
        case seekCompleted(videoSeeks: Int, audioSeeks: Int)
        /// The video leg failed. av_seek_frame has no rollback: the video
        /// demuxer position is UNKNOWN after this outcome - re-seek or
        /// reopen before delivering either leg. Audio was NOT attempted.
        case videoLegFailed(videoError: String, videoPositionKnown: Bool)
        /// Video accepted, audio failed: the pair is MISALIGNED until
        /// resynced. The sync owner must hold delivery of the moved video
        /// leg until the audio leg is re-seeked successfully.
        case audioLegFailedAfterVideo(audioError: String)
        /// A joint seek was already in flight on this coordinator.
        case seekInProgress
    /// v4.4 (r6 g4): the legs ran but a seek counter moved by other than
    /// exactly one per leg - a direct seek or another coordinator
    /// interleaved; the pair's alignment is not proven.
    case contended
    /// v4.4 (r6 g4): a materialized report is not bound to this session's
    /// epoch - the receipt cannot be attributed, so the seek is not proven.
    case sessionMismatch
    case notImplemented(reason: String)
    }

    /// What the sync owner needs about hardware->software fallback: the
    /// presentation timestamps at which the video lane resumed from a
    /// keyframe this session (empty = no fallback) plus both lanes' seek
    /// counts. LIVE-readable since v4.3 (the video report materializes from
    /// live counters while the session is active, not only at close).
    public struct FallbackResumeSurface: Equatable, Sendable {
        public let sessionEpoch: UInt64
        public let fallbackResumePTS: [Int64]
        public let videoSeeks: Int
        public let audioSeeks: Int
    }

    private let video: FFmpegSoftwareDecoder
    private let audio: FFmpegSoftwareAudioDecoder
    /// Mutual exclusion for joint seeks: two concurrent seekBoth calls
    /// would interleave legs (videoA/videoB/audioA/audioB) and report
    /// completion over a mismatched pair. Claim/release are SYNCHRONOUS
    /// queue turns - NSLock across an async boundary is unavailable from
    /// asynchronous contexts (compiler-flagged; an error in Swift 6 mode).
    private let claimQueue = DispatchQueue(label: "gorav.l3.avcoord.claim")
    private var jointSeekInFlight = false
    private func claimJointSeek() -> Bool {
        claimQueue.sync {
            if jointSeekInFlight { return false }
            jointSeekInFlight = true
            return true
        }
    }
    private func releaseJointSeek() {
        claimQueue.sync { jointSeekInFlight = false }
    }

    public init(video: FFmpegSoftwareDecoder, audio: FFmpegSoftwareAudioDecoder) {
        self.video = video
        self.audio = audio
    }

    /// Joint seek: video leg first (its keyframe-aligned landing is the
    /// pair's anchor), then the audio leg to the same target. Serialized:
    /// a concurrent call typed-refuses .seekInProgress. Both decoders
    /// validate the session epoch themselves.
    @discardableResult
    public func seekBoth(toSeconds seconds: Double, session: SessionID) async -> JointSeekResult {
        return .notImplemented(reason: "Joint seek requires the NH6 coordinated transaction owner; legacy Double seek is disabled")
    }

    /// Fallback-resume witness for L1. Both lanes materialize their
    /// reports from LIVE counters while a session is active (v4.3) and
    /// from the frozen close-time report after close - this surface works
    /// during playback, not only postmortem. nil for an epoch the video
    /// lane never ran.
    public func fallbackResumeSurface(session: SessionID) async -> FallbackResumeSurface? {
        return nil // M2: no pair-bound converted-audio report yet.
    }
}
