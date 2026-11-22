#if canImport(AppKit) && canImport(Metal)
import Foundation
import GorAVPlaybackCore

// P30/P31-STEREO-LOOK presenter binding (lane: stereo/photon; SHARED
// SURFACE, Ops-composed): the ONE explicit currency binding from the
// isolated stage adapter to the live core identity, plus the P31 seam
// counters. CONSUMED by MetalPresenter.swift (P31 shared-caller seam):
// this file is not an alias-only "integration" - the presenter's
// admission/render seam drives these bindings per admitted frame.
//
// FrameKey IS FrameIdentity (SurfaceContract.swift): slots, leases and
// records match on FULL FrameIdentity equality, so this binding never
// substitutes leaseKey, a PTS tuple or any field subset - the generic
// adapter compares whole values and FrameIdentity's Equatable is the
// complete immutable identity (sessionID + sessionGeneration + sequence
// + surfaceRevision + producerSource + ptsSeconds + trackRevision +
// score + streamIndex + streamHandle + ptsTimebase + presentationEpoch).
//
// Stage-installation epochs are owned by the adapter (the stage owner),
// minted by installStage() and reset by invalidate(_:) on
// rebind/retire/surface/stream/source change; they are never inferred
// from session or presentation generation. Consumption requires the
// admitted actual frame + installed epoch + exact revision and refuses
// stale typed. The runtime-owner ack gate is preserved whole: nothing
// here publishes, acknowledges or activates.
public typealias StereoLookPresenterAdapter = StereoLookStageAdapter<FrameIdentity>
public typealias StereoLookPresenterPayload = StereoLookFramePayload<FrameIdentity>
public typealias StereoLookPresenterSubmission = StereoLookStageSubmission<FrameIdentity>

/// P31 seam counters for the presenter wiring (installs, invalidations,
/// per-frame drive outcomes, stale render-seam queries). Kept here so
/// the shared MetalPresenterTelemetry file stays untouched by this lane.
public struct StereoLookPresenterCounters: Equatable {
    public private(set) var installs = 0
    public private(set) var invalidations = 0
    public private(set) var produced = 0
    public private(set) var unchanged = 0
    public private(set) var gated = 0
    public private(set) var hostStateMissing = 0
    public private(set) var driveRefusals = 0
    public private(set) var staleQueries = 0
    public init() {}
    public mutating func recordInstall() { installs += 1 }
    public mutating func recordInvalidation(_ cause: StereoLookStageInvalidation) { invalidations += 1 }
    public mutating func recordProduced() { produced += 1 }
    public mutating func recordUnchanged() { unchanged += 1 }
    public mutating func recordGated() { gated += 1 }
    public mutating func recordHostStateMissing() { hostStateMissing += 1 }
    public mutating func recordDriveRefusal() { driveRefusals += 1 }
    public mutating func recordStaleQuery() { staleQueries += 1 }
}
#endif
