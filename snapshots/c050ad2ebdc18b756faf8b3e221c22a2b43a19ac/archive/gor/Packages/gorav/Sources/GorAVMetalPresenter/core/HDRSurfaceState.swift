// L2 presenter, HDR-PRESENTER (arch-198a 5(b)/5(c), DR-198A-5C option 1):
// typed, revisioned HDR surface state and screen-metrics intake on the
// presenter side of the gor<->gorav handoff. Pure Foundation (same pattern
// as AspectFit.swift) so the file builds into the macOS target and the
// Linux witness unchanged. AUTHORED NEW 2026-11-16, lane c.
//
// Frozen seam (6 lane-c rulings, relayed via Main 2026-11-16):
// goreda/instinct lane/gdb-198a-hdr-handoff @
// 3af4a273e4c6cb1680436c58735f2153460a1b51,
// archive/gor/Sources/gor/GorAVHDRHandoff.swift.
// Module direction: gorav cannot import the gor target, so the presenter
// publishes these gorav-native types; the gor-side adapter conforms to the
// frozen HDRSurfaceStateSource/HDRScreenMetricsSink protocols and maps
// 1:1. Every mapping below names its frozen counterpart.
import Foundation

/// 1:1 mirror of SurfaceContract.OutputIntent (AppKit-gated, Linux-blind).
/// The mirror exists so this file never imports the gated contract; the
/// Darwin presenter switches on OutputIntent and passes the mirror case.
/// Mirror of the frozen seam's negotiation outcomes, NOT of its state
/// kinds - the frozen seam never sees this enum.
public enum HDRNegotiatedIntent: String, Sendable, Equatable, CaseIterable {
    case nativeSDR
    case nativeHDR
    case tonemappedHDRtoSDR
}

/// Mirror of the frozen HDRScreenMetrics (ruling 5): usable*/chrome* in
/// POINTS, backingScale a separate ratio. Drawable pixels are NEVER
/// computed on the gor side; the presenter derives
/// SurfaceContract.drawableWidth/Height from usableWidth * backingScale
/// (lane-c sentence pinned in the frozen file).
public struct PresenterHDRScreenMetrics: Equatable, Sendable {
    /// Usable screen area (NSScreen.visibleFrame), POINTS.
    public let usableWidth: Double
    public let usableHeight: Double
    /// NSScreen.backingScaleFactor (ratio, not points or pixels).
    public let backingScale: Double
    /// Window chrome delta (POINTS) for the window's own style mask.
    public let chromeWidth: Double
    public let chromeTop: Double

    /// Pure builder; nil on degenerate input. Same guard domain as the
    /// frozen HDRScreenMetrics.make (and GorOpeningFit.fitMetricsString):
    /// finite values, non-negative chrome, usable area at least 2pt on
    /// each axis, scale >= 1.
    public static func make(usableWidth: Double, usableHeight: Double,
                            backingScale: Double,
                            chromeWidth: Double, chromeTop: Double) -> PresenterHDRScreenMetrics? {
        let parts = [usableWidth, usableHeight, backingScale, chromeWidth, chromeTop]
        guard parts.allSatisfy({ $0.isFinite }), chromeWidth >= 0, chromeTop >= 0,
              usableWidth >= 2, usableHeight >= 2, backingScale >= 1 else { return nil }
        return PresenterHDRScreenMetrics(usableWidth: usableWidth, usableHeight: usableHeight,
                                         backingScale: backingScale,
                                         chromeWidth: chromeWidth, chromeTop: chromeTop)
    }

    /// Ruling 5 derivation: drawable PIXELS = points * backingScale,
    /// rounded to nearest (away from zero on .5), at least 1 px per axis,
    /// bounded by the SurfaceContract texture side cap (16384). Nil when
    /// the derivation cannot be represented (overflow or over the cap) -
    /// a typed refusal, never a clamped lie.
    public func derivedDrawableSize() -> (width: Int, height: Int)? {
        let w = (usableWidth * backingScale).rounded()
        let h = (usableHeight * backingScale).rounded()
        let cap = 16384.0  // SurfaceContract.maxTextureSide (gated); pinned copy.
        guard w >= 1, h >= 1, w <= cap, h <= cap,
              w <= Double(Int.max), h <= Double(Int.max) else { return nil }
        return (Int(w), Int(h))
    }
}

/// Mirror of the frozen HDRFallbackReason MINUS .presenterSeamUnavailable
/// (ruling 6: that reason is gor-side only - it reports the ABSENCE of an
/// attached presenter, a state the presenter itself can never publish).
/// NegotiationError map (ruling 6): .unsupportedPixelFormat corresponds to
/// SurfaceContract.NegotiationError.edrRequiresFloatFormat; the remaining
/// reasons have no NegotiationError counterpart until lane c names one
/// (they describe eligibility/measurement, not contract validation).
public enum PresenterHDRFallbackReason: String, Sendable, Equatable {
    /// The screen reports no EDR headroom to extend into, or no measured
    /// headroom exists (ruling 3).
    case noExtendedDynamicRangeHeadroom
    /// The surface pixel format cannot carry EDR content. Maps to
    /// NegotiationError.edrRequiresFloatFormat (ruling 6).
    case unsupportedPixelFormat
    /// The decoded stream is not HDR; nothing to extend.
    case decoderNotHDR
    /// DR-197F-HDR-PREP option 2: presenter software fallback bit0 set.
    case softwareFallbackFlagged
}

/// Policy tone-map is NOT a fallback (ruling 4): the presenter deliberately
/// tone-maps HDR into the SDR surface per its output intent.
public enum PresenterHDRToneMapPolicy: String, Sendable, Equatable {
    /// SurfaceContract.OutputIntent.tonemappedHDRtoSDR.
    case tonemappedHDRtoSDR
}

/// Mirror of the frozen HDRSurfaceKind (4 cases, same associated values).
public enum PresenterHDRSurfaceKind: Equatable, Sendable {
    /// No negotiation has completed yet this session/surface revision.
    case notNegotiated
    /// EDR surface active with the live measured headroom (finite, > 1.0;
    /// validated by PresenterHDRSurfaceState.edr).
    case edrActive(headroom: Double)
    /// SDR rendering after a failure/eligibility refusal (ruling 4).
    case sdrFallback(PresenterHDRFallbackReason)
    /// Deliberate policy tone-map into SDR (ruling 4; not a fallback).
    case toneMapped(PresenterHDRToneMapPolicy)
}

/// Mirror of the frozen HDRSurfaceState: the typed HDR-state receipt,
/// presenter -> chrome/diag. Every read is revisioned (ruling 2):
/// renegotiation bumps surfaceRevision (MetalRenderer.installRenderState
/// is the ONE revision counter; this type never mints its own), so two
/// reads with equal kind but different revision are different states.
public struct PresenterHDRSurfaceState: Equatable, Sendable {
    /// Fed from MetalRenderer.currentSurfaceRevision (the renderer owns
    /// the counter; initial negotiation is revision 0, +1 per
    /// renegotiation, overflow is a typed stop there).
    public let surfaceRevision: UInt64
    public let kind: PresenterHDRSurfaceKind

    public init(surfaceRevision: UInt64, kind: PresenterHDRSurfaceKind) {
        self.surfaceRevision = surfaceRevision
        self.kind = kind
    }

    public static func notNegotiated(revision: UInt64) -> PresenterHDRSurfaceState {
        PresenterHDRSurfaceState(surfaceRevision: revision, kind: .notNegotiated)
    }
    /// nil unless the headroom was measured finite and > 1.0 (ruling 3);
    /// callers without a measurement use notNegotiated or
    /// sdr(.noExtendedDynamicRangeHeadroom).
    public static func edr(revision: UInt64, headroom: Double) -> PresenterHDRSurfaceState? {
        guard headroom.isFinite, headroom > 1.0 else { return nil }
        return PresenterHDRSurfaceState(surfaceRevision: revision,
                                        kind: .edrActive(headroom: headroom))
    }
    public static func sdr(revision: UInt64, reason: PresenterHDRFallbackReason) -> PresenterHDRSurfaceState {
        PresenterHDRSurfaceState(surfaceRevision: revision, kind: .sdrFallback(reason))
    }
    public static func toneMapped(revision: UInt64, policy: PresenterHDRToneMapPolicy) -> PresenterHDRSurfaceState {
        PresenterHDRSurfaceState(surfaceRevision: revision, kind: .toneMapped(policy))
    }

    /// The one mapping from a validated negotiation outcome to a receipt
    /// kind. measuredHeadroom is the LIVE screen measurement (Darwin:
    /// NSScreen maximumExtendedDynamicRangeColorComponentValue, read at
    /// negotiation/renegotiation; Linux witness: injected). Mapping
    /// decisions:
    /// - nativeHDR: edrActive ONLY with a valid measurement; without one
    ///   the honest receipt is sdrFallback(.noExtendedDynamicRangeHeadroom)
    ///   (ruling 3: no measurement, no EDR claim).
    /// - tonemappedHDRtoSDR: .toneMapped(.tonemappedHDRtoSDR) - a policy
    ///   tone-map is never a fallback (ruling 4).
    /// - nativeSDR: sdrFallback(.decoderNotHDR). A deliberate SDR intent
    ///   means the source carries no HDR signal; under ruling 4's
    ///   "failure/eligibility refusal" wording this is the ELIGIBILITY
    ///   case (nothing to extend), not a failure. Flagged for the gor
    ///   writer in DR-0016: if the seam wants deliberate-SDR distinct
    ///   from decoderNotHDR, that case is named gor-side and mapped here.
    public static func make(revision: UInt64, intent: HDRNegotiatedIntent,
                            measuredHeadroom: Double?) -> PresenterHDRSurfaceState {
        switch intent {
        case .nativeHDR:
            if let h = measuredHeadroom, let s = edr(revision: revision, headroom: h) {
                return s
            }
            return sdr(revision: revision, reason: .noExtendedDynamicRangeHeadroom)
        case .tonemappedHDRtoSDR:
            return toneMapped(revision: revision, policy: .tonemappedHDRtoSDR)
        case .nativeSDR:
            return sdr(revision: revision, reason: .decoderNotHDR)
        }
    }
}

/// Typed publish refusals for HDRSurfaceStateProvider.
public enum HDRSurfacePublishError: Error, Equatable {
    /// A publish at a revision BELOW the current one: revisions are
    /// monotonic with renegotiation (MetalRenderer bumps +1); going back
    /// would relabel a newer surface as an older one.
    case regressedRevision(published: UInt64, current: UInt64)
    /// A kind change at the SAME revision violates ruling 2 (identity is
    /// revision + kind; renegotiation must bump the revision).
    case kindChangeAtSameRevision(revision: UInt64)
}

/// The presenter's HDR state source: what the gor-side
/// HDRSurfaceStateSource adapter reads (ruling 1: a PROPERTY,
/// currentHDRSurfaceState, never a method; the type reads state and never
/// negotiates - SurfaceNegotiator.apply stays the one negotiation point).
/// Thread-safe: negotiation and reads run on different threads in the
/// renderer, so publish/read serialize on one lock.
public final class HDRSurfaceStateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var state: PresenterHDRSurfaceState

    public init() {
        state = .notNegotiated(revision: 0)
    }

    /// Frozen-seam property shape (ruling 1).
    public var currentHDRSurfaceState: PresenterHDRSurfaceState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Publish the state of a completed negotiation. Returns a typed
    /// refusal and leaves the state unchanged on a monotonicity or
    /// identity violation; re-publishing the CURRENT (revision, kind) is
    /// an idempotent no-op (nil). The unpublished sentinel
    /// (.notNegotiated) accepts any revision >= its own: the renderer's
    /// FIRST negotiation is revision 0 and must be publishable.
    @discardableResult
    public func publish(_ next: PresenterHDRSurfaceState) -> HDRSurfacePublishError? {
        lock.lock()
        defer { lock.unlock() }
        if case .notNegotiated = state.kind {
            guard next.surfaceRevision >= state.surfaceRevision else {
                return .regressedRevision(published: next.surfaceRevision,
                                          current: state.surfaceRevision)
            }
            state = next
            return nil
        }
        if next.surfaceRevision < state.surfaceRevision {
            return .regressedRevision(published: next.surfaceRevision,
                                      current: state.surfaceRevision)
        }
        if next.surfaceRevision == state.surfaceRevision {
            return next.kind == state.kind
                ? nil
                : .kindChangeAtSameRevision(revision: next.surfaceRevision)
        }
        state = next
        return nil
    }
}
