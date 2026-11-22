import Foundation
import StereoLookNativeContract

// P31-STEREO-LOOK stage submission (lane: stereo/photon), part of the
// shared caller implementation on the QUALIFIED v7 transport: the
// presenter's remembered stage state around the QUALIFIED
// StereoLookStageAdapter. The adapter already owns installation epochs
// and typed stale-refusal; this wrapper owns the CALLER-side facts the
// render seam needs between frames:
//  - the CURRENT submission (latest produced payload + its exact block
//    revision), held across frames so an admitted-frame render can bind
//    the stage block without re-producing;
//  - the OUTCOME lifecycle on the submission: a .produced frame REPLACES
//    the submission, an .unchanged frame KEEPS it (same accepted state),
//    a .gated frame CLEARS it AND rebinds the installation. The pinned
//    contract (c455d945 l.632) is about BINDABILITY: while the
//    publication gate is closed the BINDING keeps the stage uninstalled
//    - no payload exists to bind and no earlier payload may be bound
//    either. The stage-installation EPOCH is intentionally NON-nil
//    during the gate: v10 (Z4C v9 T44.reproduced) the QUALIFIED source
//    RETAINS its accepted frame/host across gated frames, so clearing
//    only the wrapper's submission left the states diverged - a later
//    identical reopen answered .unchanged with no payload and the
//    wrapper stayed nil forever. The wrapper therefore pairs the clear
//    with a stage REBIND: invalidate clears the source's accepted state
//    and the fresh install mints a new epoch EAGERLY on the gated frame
//    itself (an arriving frame is never an implicit install), so the
//    next open-gate frame RE-PRODUCES under the fresh epoch and every
//    pre-gate payload stays epoch-refused forever - refused typed under
//    its own dead epoch AND under the live rebound one.
//  - the INSTALL/INVALIDATE pairing the Ops grounding pins: invalidate
//    clears the installation AND the submission (rebind / retire /
//    surface / stream / source change), and install mints a FRESH
//    stage epoch with no submission - a payload produced under an older
//    epoch can never be bound after any invalidation (the adapter's
//    typed .staleStageEpoch / .uninstalled refusals enforce it).
//  - BLOCK QUERY: block(admitted:) consumes the current submission
//    against the ADMITTED frame + installed epoch + exact revision via
//    the adapter's typed consume. Every typed refusal answers nil and
//    mutates nothing (the submission stays whole for the matching
//    frame). There is no substitution key anywhere: the full FrameKey
//    equality of the concrete presenter binding is the only identity.
//  - AUTHORITY: the host's setter calls authorityChanged() on every
//    actual host-state change or loss; the submission is cleared and
//    the stage rebound (fresh epoch), so a block can never outlive the
//    authority it was produced under.
//
// The runtime-owner publication/ack gate and the title boundary are
// untouched: nothing here publishes, acknowledges, activates, or binds
// a title source; the shadow stays diagnostic-only.
//
// INERT until Ops composes the presenter wiring; the encode-side
// consume of the returned block is Ops's separate renderer composition.

public final class StereoLookStageSubmission<FrameKey: Equatable> {
    private let adapter: StereoLookStageAdapter<FrameKey>
    /// The latest produced payload and its exact block revision; nil
    /// while nothing produced, after a .gated frame, or after any
    /// invalidation or fresh install.
    public private(set) var current: (payload: StereoLookFramePayload<FrameKey>,
                                      revision: ParameterBlockRevision)?

    /// The installed stage epoch, mirrored from the adapter (nil while
    /// uninstalled).
    public var installedEpoch: UInt64? { adapter.installedEpoch }

    public init(adapter: StereoLookStageAdapter<FrameKey> = StereoLookStageAdapter<FrameKey>()) {
        self.adapter = adapter
    }

    /// Mint a fresh stage-installation epoch and drop any submission
    /// from a previous installation (none could match the new epoch).
    @discardableResult
    public func install() -> UInt64 {
        current = nil
        return adapter.installStage()
    }

    /// Stage rebind/retire or surface/stream/source change: clears the
    /// installation, the adapter's accepted frame state, AND the
    /// submission. A re-install is a separate explicit call.
    public func invalidate(_ cause: StereoLookStageInvalidation) {
        adapter.invalidate(cause)
        current = nil
    }

    /// Host AUTHORITY changed or was lost (Z4C v11 authority-loss RED):
    /// the caller (the presenter's setter) guarantees an actual value
    /// change and owns the value itself; this owns the consequences -
    /// the submission is cleared AND the stage rebound (accepted state
    /// cleared, fresh epoch minted eagerly), so no payload produced
    /// under a PREVIOUS authority can ever bind against the new one and
    /// an identical-authority return RE-PRODUCES instead of aliasing
    /// the retained accepted state. No-op while uninstalled; the drive
    /// itself still requires a non-nil host from the caller.
    public func authorityChanged() {
        guard adapter.installedEpoch != nil else { return }
        current = nil
        adapter.invalidate(.rebind)
        _ = adapter.installStage()
    }

    /// One frame through the adapter, maintaining the submission per the
    /// outcome lifecycle in the file header. A typed refusal from the
    /// adapter (uninstalled, producer refusal) propagates and leaves the
    /// submission untouched.
    @discardableResult
    public func frame(_ frame: FrameKey, host: StereoLookHostState) throws
        -> StereoLookFrameOutcome {
        let (payload, outcome) = try adapter.frame(frame, host: host)
        switch outcome {
        case .produced(let revision):
            guard let payload else { break }
            current = (payload, revision)
        case .unchanged:
            break
        case .gated:
            // Gate closed: clear the submission AND rebind the stage
            // (accepted state cleared, fresh epoch minted) so a later
            // identical reopen re-produces instead of answering
            // .unchanged into a permanently nil wrapper (Z4C v9
            // T44.reproduced). No earlier payload can ever bind again.
            current = nil
            adapter.invalidate(.rebind)
            _ = adapter.installStage()
        }
        return outcome
    }

    /// The current stage block for the render seam, consumed against the
    /// ADMITTED frame + installed epoch + exact revision through the
    /// adapter's typed consume. Any typed refusal (uninstalled, stale
    /// frame, stale epoch, stale revision) answers nil and mutates
    /// nothing; nil also answers when no submission exists.
    public func block(admitted frame: FrameKey)
        -> (block: LookParameterABI.Block, revision: ParameterBlockRevision)? {
        guard let current, let epoch = adapter.installedEpoch else { return nil }
        // try? FLATTENS (SE-0230): one binding covers both the typed
        // refusals and the payload's own nil answer (no ABI-validated
        // block). v9: Z4C evidence 09629212 - a second conditional
        // binding here was illegal and broke the portable build.
        guard let block = try? adapter.consume(current.payload, admitted: frame,
                                               installed: epoch,
                                               revision: current.revision) else {
            return nil
        }
        return (block, current.revision)
    }
}
