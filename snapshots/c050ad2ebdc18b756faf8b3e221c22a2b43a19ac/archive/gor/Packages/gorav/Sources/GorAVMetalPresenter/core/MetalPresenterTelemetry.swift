// L2 presenter: telemetry counters mirroring KitDisplayTelemetry semantics
// 1:1 (GorAVMacShell/DisplaySink.swift) so the v1.4 comparison is
// field-for-field, plus presenter-specific counters. r3 (r2 finding 1):
// counters are SESSION-SCOPED - a recreated presenter starts a fresh
// session via beginSession() so no recreate inherits a dead session's
// numbers; lifetimeTotals() accumulates across sessions for the matrix.
// Pure Swift, no AppKit. AUTHORED NEW 2026-10-25, L2 lane.
import Foundation

@MainActor public enum MetalPresenterTelemetry {
    /// Same semantics as KitDisplayTelemetry.uploads: frames handed to the GPU.
    public static var uploads = 0
    /// Same semantics as KitDisplayTelemetry.visibleUploads.
    public static var visibleUploads = 0
    /// Same semantics as KitDisplayTelemetry.noPixels.
    public static var noPixels = 0
    /// Same contract as KitDisplayTelemetry.closedByUser: windowShouldClose
    /// records intent (and, r3, synchronously seals the presenter).
    public static var closedByUser = false
    // Presenter-specific receipts:
    public static var resizeEvents = 0
    public static var fullscreenEntries = 0
    public static var fullscreenExits = 0
    /// nextDrawable() returned nil (occluded/minimized); frame counted as
    /// uploaded (GPU work done) but no present happened. Reported, never hidden.
    public static var drawableNilPresents = 0
    /// P31: renderer registration refusals surfaced at the presenter
    /// (sealed/identity/length/domain) - the flat fallback after a
    /// refusal is counted, never silent.
    public static var stereoBindingRefusals = 0
    public static var readbacks = 0
    /// Typed rejections at the presenter boundary (invalid/stale/closed).
    public static var uploadRejections = 0
    /// Queued show/resize work observed AFTER close (seal witness).
    public static var staleWorkAfterClose = 0
    /// Typed seal barrier residuals (r6 finding 1): seal() returned with
    /// admitted frames still uncommitted - surfaced, never hidden.
    public static var sealResidualEvents = 0
    public static var sealResidualPending = 0
    /// Typed geometry-change rejections (r6 finding 2).
    public static var geometryRejections = 0
    /// Window-mode-only controls invoked in embed mode (typed no-ops).
    public static var windowModeNoOps = 0
    /// Sequence-space exhaustion stops (r6 finding 6: never a wrap alias).
    public static var sequenceExhausted = 0
    /// r8 trunk-contract port: ticketed shows consumed through the shared
    /// CancelCommit authority (commitFrame accepted = admission + contents
    /// assignment in ONE critical section).
    public static var ticketedCommits = 0
    /// r8: ticketed shows REFUSED typed - no commit authority bound, the
    /// close fence, or a stale/foreign ticket. Never a default-accept.
    public static var ticketRefusals = 0

    private static var lifetime = [String: Int]()

    /// Session start (presenter init / recreate): session counters reset,
    /// so a recreate can never contaminate or be contaminated (r2 finding 1).
    public static func beginSession() {
        accumulate()
        uploads = 0; visibleUploads = 0; noPixels = 0; closedByUser = false
        resizeEvents = 0; fullscreenEntries = 0; fullscreenExits = 0
        drawableNilPresents = 0; readbacks = 0
        uploadRejections = 0; staleWorkAfterClose = 0
        sealResidualEvents = 0; sealResidualPending = 0
        geometryRejections = 0; sequenceExhausted = 0
        windowModeNoOps = 0
        ticketedCommits = 0; ticketRefusals = 0
    }

    /// Matrix-section reset without a new session (kept for the check CLI).
    public static func reset() {
        uploads = 0; visibleUploads = 0; noPixels = 0; closedByUser = false
        resizeEvents = 0; fullscreenEntries = 0; fullscreenExits = 0
        drawableNilPresents = 0; readbacks = 0
        uploadRejections = 0; staleWorkAfterClose = 0
        sealResidualEvents = 0; sealResidualPending = 0
        geometryRejections = 0; sequenceExhausted = 0
        windowModeNoOps = 0
        ticketedCommits = 0; ticketRefusals = 0
    }

    private static func accumulate() {
        lifetime["uploads", default: 0] += uploads
        lifetime["visibleUploads", default: 0] += visibleUploads
        lifetime["noPixels", default: 0] += noPixels
        lifetime["staleWorkAfterClose", default: 0] += staleWorkAfterClose
    }
    public static func lifetimeTotals() -> [String: Int] {
        var t = lifetime
        t["uploads", default: 0] += uploads
        t["visibleUploads", default: 0] += visibleUploads
        t["noPixels", default: 0] += noPixels
        t["staleWorkAfterClose", default: 0] += staleWorkAfterClose
        return t
    }
}
