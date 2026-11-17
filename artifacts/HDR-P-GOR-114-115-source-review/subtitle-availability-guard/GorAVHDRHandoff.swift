import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - DR-198A-5C (arch-198a 5c, HDR-P-GOR, option 1): typed handoff at the
// Viewport/presenter seam.
//
// Topology (from DR-198A-5C-GOR-PREP r1, selected option 1):
//   - gor keeps owning window/chrome; the presenter (gorav MetalPresenter,
//     lane c) owns the ONE surface negotiation. gor never configures an EDR
//     surface itself (DR option 3 rejected: second writer to surface state).
//   - gor supplies screen metrics from the SAME source gor-fit already uses
//     (NSScreen.visibleFrame + backingScaleFactor + chrome measured through
//     NSWindow.frameRect(forContentRect:styleMask:), the GorOpeningFit
//     pattern), an SDR-white subtitle layer above the video surface
//     (SubtitleView remains the subtitle presentation owner; the pin lives in
//     SubtitleView.setupLayer), and routes the typed HDR-state receipt from
//     presenter to chrome/diag surfaces.
//   - Writer topology unchanged: this file READS window/screen state and
//     writes none of it. Viewport/window writers are untouched.
//
// Lane c freeze (2026-11-16, relayed via Main, 6 rulings applied):
//   1. State source protocol is HDRSurfaceStateSource (property, not method);
//      the metrics sink is a separate protocol. Negotiation itself happens at
//      exactly one point: gorav SurfaceNegotiator.apply.
//   2. Every state read carries surfaceRevision (fed from the presenter's
//      SurfaceContract.surfaceRevision); SDR<->EDR renegotiation can happen
//      on windowDidChangeScreen, so identity-less state reads do not exist.
//   3. edrActive headroom is non-optional and valid only when measured
//      finite and > 1.0; without a measurement the state is notNegotiated or
//      sdrFallback(.noExtendedDynamicRangeHeadroom).
//   4. sdrFallback covers failure/eligibility refusal only; a policy
//      HDR->SDR tone-map is its own case .toneMapped(policy).
//   5. HDRScreenMetrics units: usable*/chrome* are points, backingScale is a
//      separate ratio. Drawable pixels are NEVER computed on the gor side;
//      the presenter derives SurfaceContract.drawableWidth/Height from
//      usableWidth * backingScale (lane c sentence, pinned here).
//   6. HDRFallbackReason <-> NegotiationError map: .unsupportedPixelFormat
//      corresponds to gorav edrRequiresFloatFormat; .presenterSeamUnavailable
//      stays gor-side (no NegotiationError counterpart). The remaining
//      reasons are gor-side unless lane c names their counterparts.
//
// The value types above the AppKit guard are pure Foundation so the same file
// compiles into the macOS app target and into the Linux test harness
// unchanged (Tests/Harness/HDRHandoff).

struct HDRScreenMetrics: Equatable, Sendable {
    /// Usable screen area (NSScreen.visibleFrame), POINTS.
    var usableWidth: Double
    var usableHeight: Double
    /// NSScreen.backingScaleFactor (ratio, not points or pixels).
    var backingScale: Double
    /// Window chrome delta (POINTS) for the window's own style mask, measured
    /// through NSWindow.frameRect(forContentRect:styleMask:).
    var chromeWidth: Double
    var chromeTop: Double

    /// Pure builder; nil on degenerate input. Same guard domain as
    /// GorOpeningFit.fitMetricsString: finite values, non-negative chrome,
    /// usable area at least 2pt on each axis, scale >= 1. Never computes
    /// drawable pixels (presenter-side per ruling 5).
    static func make(usableWidth: Double, usableHeight: Double,
                     backingScale: Double,
                     chromeWidth: Double, chromeTop: Double) -> HDRScreenMetrics? {
        let parts = [usableWidth, usableHeight, backingScale, chromeWidth, chromeTop]
        guard parts.allSatisfy({ $0.isFinite }), chromeWidth >= 0, chromeTop >= 0,
              usableWidth >= 2, usableHeight >= 2, backingScale >= 1 else { return nil }
        return HDRScreenMetrics(usableWidth: usableWidth, usableHeight: usableHeight,
                                backingScale: backingScale,
                                chromeWidth: chromeWidth, chromeTop: chromeTop)
    }
}

enum HDRFallbackReason: String, Sendable, Equatable {
    /// The vendored presenter exposes no surface-negotiation seam yet
    /// (lane c presenter not attached); playback continues in SDR.
    /// gor-side only: no NegotiationError counterpart (ruling 6).
    case presenterSeamUnavailable
    /// The screen reports no EDR headroom to extend into, or no measured
    /// headroom exists (ruling 3).
    case noExtendedDynamicRangeHeadroom
    /// The surface pixel format cannot carry EDR content. Maps to gorav
    /// NegotiationError edrRequiresFloatFormat (ruling 6).
    case unsupportedPixelFormat
    /// The decoded stream is not HDR; nothing to extend.
    case decoderNotHDR
    /// DR-197F-HDR-PREP option 2: presenter software fallback bit0 set.
    case softwareFallbackFlagged
}

/// Policy tone-map is NOT a fallback (ruling 4): the presenter deliberately
/// tone-maps HDR into the SDR surface per its output intent.
enum HDRToneMapPolicy: String, Sendable, Equatable {
    /// gorav OutputIntent.tonemappedHDRtoSDR.
    case tonemappedHDRtoSDR
}

enum HDRSurfaceKind: Equatable, Sendable {
    /// No negotiation has completed yet this session/surface revision.
    case notNegotiated
    /// EDR surface active with the live measured headroom (finite, > 1.0;
    /// validated by HDRSurfaceState.edr).
    case edrActive(headroom: Double)
    /// SDR rendering after a failure/eligibility refusal (ruling 4).
    case sdrFallback(HDRFallbackReason)
    /// Deliberate policy tone-map into SDR (ruling 4; not a fallback).
    case toneMapped(HDRToneMapPolicy)
}

/// Typed HDR-state receipt, presenter -> chrome/diag (HDR-P-GOR). Every read
/// is revisioned (ruling 2): renegotiation bumps surfaceRevision, so two
/// reads with equal kind but different revision are different states.
struct HDRSurfaceState: Equatable, Sendable {
    /// Fed from the presenter's SurfaceContract.surfaceRevision.
    var surfaceRevision: UInt64
    var kind: HDRSurfaceKind

    static func notNegotiated(revision: UInt64) -> HDRSurfaceState {
        HDRSurfaceState(surfaceRevision: revision, kind: .notNegotiated)
    }
    /// nil unless the headroom was measured finite and > 1.0 (ruling 3);
    /// callers without a measurement use notNegotiated or
    /// sdr(.noExtendedDynamicRangeHeadroom).
    static func edr(revision: UInt64, headroom: Double) -> HDRSurfaceState? {
        guard headroom.isFinite, headroom > 1.0 else { return nil }
        return HDRSurfaceState(surfaceRevision: revision, kind: .edrActive(headroom: headroom))
    }
    static func sdr(revision: UInt64, reason: HDRFallbackReason) -> HDRSurfaceState {
        HDRSurfaceState(surfaceRevision: revision, kind: .sdrFallback(reason))
    }
    static func toneMapped(revision: UInt64, policy: HDRToneMapPolicy) -> HDRSurfaceState {
        HDRSurfaceState(surfaceRevision: revision, kind: .toneMapped(policy))
    }
}

#if canImport(AppKit)

/// Presenter-side state source (lane c). Property, not method (ruling 1);
/// reads are always revisioned through HDRSurfaceState.surfaceRevision.
/// Surface negotiation itself happens at exactly one point: gorav
/// SurfaceNegotiator.apply. This protocol reads state; it never negotiates.
protocol HDRSurfaceStateSource: AnyObject, Sendable {
    var currentHDRSurfaceState: HDRSurfaceState { get }
}

/// Metrics sink (ruling 1: separate from the state source). gor pushes the
/// same metrics gor-fit uses; the presenter derives drawable pixels from
/// usableWidth * backingScale - gor never computes them (ruling 5).
protocol HDRScreenMetricsSink: AnyObject {
    func hdrUpdateScreenMetrics(_ metrics: HDRScreenMetrics)
}

enum HDRHandoffRefusal: Error, Equatable {
    /// A presenter attachment is already live; the
    /// single-surface-negotiation contract admits exactly one.
    case secondNegotiator
}

/// gor-side coordinator for the HDR presenter handoff. Reads window/screen
/// metrics and pushes them to the attached presenter sink; routes the typed,
/// revisioned state receipt to its one chrome/diag sink. Owns no window or
/// surface state and configures no EDR surface.
@MainActor
final class HDRSurfaceHandoff {
    private weak var stateSource: (any HDRSurfaceStateSource)?
    private weak var metricsSink: (any HDRScreenMetricsSink)?
    private(set) var state: HDRSurfaceState = .notNegotiated(revision: 0) {
        didSet { if state != oldValue { onState?(state) } }
    }
    /// Chrome/diag receipt sink (HUD/diag surfaces). Exactly one.
    var onState: ((HDRSurfaceState) -> Void)?
    private(set) var lastMetrics: HDRScreenMetrics?

    /// Attach the presenter's state source and metrics sink (usually one
    /// object conforming to both). Typed refusal while an attachment is
    /// live; re-attaching the live source is a no-op.
    func attach(stateSource source: any HDRSurfaceStateSource,
                metricsSink sink: any HDRScreenMetricsSink) -> HDRHandoffRefusal? {
        if let live = stateSource {
            return live === source ? nil : .secondNegotiator
        }
        stateSource = source
        metricsSink = sink
        if let lastMetrics { sink.hdrUpdateScreenMetrics(lastMetrics) }
        refreshState()
        return nil
    }

    func detach(stateSource source: any HDRSurfaceStateSource) {
        guard stateSource === source else { return }
        stateSource = nil
        metricsSink = nil
        refreshState()
    }

    /// Read-only metrics source: the window's screen (falling back to main),
    /// chrome measured for the window's own style mask. Never writes window
    /// or screen state.
    static func metrics(for window: NSWindow) -> HDRScreenMetrics? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        let probe = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                       styleMask: window.styleMask)
        return HDRScreenMetrics.make(usableWidth: screen.visibleFrame.width,
                                     usableHeight: screen.visibleFrame.height,
                                     backingScale: screen.backingScaleFactor,
                                     chromeWidth: probe.width - 100,
                                     chromeTop: probe.height - 100)
    }

    /// Push current metrics to the sink (when attached) and refresh the
    /// revisioned state receipt. Call at open/show and on screen/backing
    /// changes - renegotiation on screen change is expected (ruling 2).
    func pushMetrics(window: NSWindow) {
        guard let metrics = HDRSurfaceHandoff.metrics(for: window) else { return }
        lastMetrics = metrics
        metricsSink?.hdrUpdateScreenMetrics(metrics)
        refreshState()
    }

    /// Repoll the revisioned state. Without an attached source the honest
    /// receipt is SDR with presenterSeamUnavailable (revision 0: no
    /// presenter SurfaceContract exists).
    func refreshState() {
        state = stateSource?.currentHDRSurfaceState
            ?? .sdr(revision: 0, reason: .presenterSeamUnavailable)
    }
}
#endif
