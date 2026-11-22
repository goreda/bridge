import Foundation
import StereoLookNativeContract

// P30-STEREO-LOOK stage adapter (lane: stereo/photon): the stage OWNER's
// installation-epoch and stale-refusal boundary around the qualified
// StereoLookStageSource. Additive on the qualified v4 composition; no
// qualified byte changes.
//
// Contract (pinned by the Ops SurfaceContract grounding; none invented):
//  - FrameKey stays generic here. The presenter binds it to the real
//    core FrameIdentity with FULL equality in the concrete presenter
//    binding file (shared surface, Ops-composed). This adapter never
//    inspects, projects or re-keys a frame: no leaseKey, no PTS tuple,
//    no selected-field comparison anywhere.
//  - STAGE-INSTALLATION EPOCH: owned HERE as an explicit counter, minted
//    only by installStage(); never inferred from session, presentation
//    or surface generation. invalidate(_:) (rebind / retire / surface /
//    stream / source change) clears the installation AND the source's
//    accepted frame state, so the next frame after invalidation is
//    never deduped against pre-invalidation state and requires a fresh
//    installStage().
//  - FRAME: a frame answered before any installation refuses typed
//    (.uninstalled); an arriving frame is NEVER an implicit install.
//  - CONSUME: the consumer supplies the ADMITTED frame, the INSTALLED
//    stage epoch and the EXACT revision. Each is compared against the
//    payload BEFORE decode; any mismatch refuses typed
//    (frame/stageEpoch/revision) and nothing mutates. A matching triple
//    defers to the payload's own consume (ABI-validated shader words
//    only, never packet memory).
//  - The runtime-owner publication/ack gate is preserved whole: this
//    adapter never publishes, acknowledges or activates; the shadow
//    stays diagnostic-only; the title boundary (.noTitleSourceBound in
//    the source lane) is unchanged.
//
// INERT until Ops composes the presenter binding; App registration is
// owned elsewhere.

/// Why an installation was torn down. Detection of the underlying
/// surface/stream/source change is the caller's (the session observes
/// those); the adapter owns only the reset semantics.
public enum StereoLookStageInvalidation: Equatable {
    case rebind, retire, surfaceChange, streamChange, sourceChange
}

public enum StereoLookStageConsumeRefusal: Error, Equatable {
    /// No stage is installed (epoch never minted, or invalidated).
    case uninstalled
    /// The supplied admitted frame is not the payload's frame.
    case staleFrame
    /// The supplied epoch is not the installed stage epoch, or the
    /// payload was produced under a different stage epoch.
    case staleStageEpoch
    /// The supplied revision is not the payload's exact revision.
    case staleRevision
}

public final class StereoLookStageAdapter<FrameKey: Equatable> {
    private let source: StereoLookStageSource<FrameKey>
    /// The installed stage epoch; nil while uninstalled. Minted only by
    /// installStage(); cleared only by invalidate(_:).
    public private(set) var installedEpoch: UInt64?
    private var epochCounter: UInt64 = 0

    public init(source: StereoLookStageSource<FrameKey> = StereoLookStageSource<FrameKey>()) {
        self.source = source
    }

    /// Mint a new stage-installation epoch. Monotonic per adapter
    /// instance (wrapping only at UInt64.max, which no installation
    /// cadence reaches); never derived from any session or presentation
    /// generation.
    @discardableResult
    public func installStage() -> UInt64 {
        epochCounter &+= 1
        installedEpoch = epochCounter
        return epochCounter
    }

    /// One frame through the qualified source, tagged with the installed
    /// stage epoch. Requires an installed stage; a pre-install frame
    /// refuses typed and leaves the source's state untouched.
    public func frame(_ frame: FrameKey, host: StereoLookHostState) throws
        -> (StereoLookFramePayload<FrameKey>?, StereoLookFrameOutcome) {
        guard let epoch = installedEpoch else {
            throw StereoLookStageConsumeRefusal.uninstalled
        }
        return try source.framePayload(frame: frame, stageGeneration: epoch, host: host)
    }

    /// Admitted-frame consumption: full frame identity + installed stage
    /// epoch + exact revision, each compared and refused typed BEFORE
    /// decode; no state mutates on refusal. On a full match, defers to
    /// the payload's own validated consume.
    public func consume(_ payload: StereoLookFramePayload<FrameKey>,
                        admitted frame: FrameKey, installed epoch: UInt64,
                        revision: ParameterBlockRevision) throws -> LookParameterABI.Block? {
        guard let current = installedEpoch else {
            throw StereoLookStageConsumeRefusal.uninstalled
        }
        guard payload.frame == frame else {
            throw StereoLookStageConsumeRefusal.staleFrame
        }
        guard epoch == current, payload.stageGeneration == epoch else {
            throw StereoLookStageConsumeRefusal.staleStageEpoch
        }
        guard payload.revision == revision else {
            throw StereoLookStageConsumeRefusal.staleRevision
        }
        return payload.consume(frame: frame, stageGeneration: epoch, revision: revision)
    }

    /// Stage rebind/retire or surface/stream/source change: clears the
    /// installation and the source's accepted frame state. The block's
    /// values and revision stay the block owner's call, matching the
    /// source's own resetFrameState boundary.
    public func invalidate(_ cause: StereoLookStageInvalidation) {
        installedEpoch = nil
        source.resetFrameState()
    }
}
