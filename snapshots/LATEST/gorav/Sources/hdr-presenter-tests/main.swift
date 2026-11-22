import Foundation
import GorAVMetalPresenter

// Witness for HDR-PRESENTER (arch-198a 5(b)/5(c), DR-0016): the typed,
// revisioned HDR surface state and screen-metrics intake on the presenter
// side of the frozen gor<->gorav handoff seam (instinct
// lane/gdb-198a-hdr-handoff @ 3af4a273). Pure-state checks only; Metal,
// CAMetalLayer and live NSScreen headroom are NOT_RUN here (no Mac).

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

// T1: edr factory validates ruling 3 (finite, > 1.0)
check("T1a", PresenterHDRSurfaceState.edr(revision: 3, headroom: 2.0)
      == PresenterHDRSurfaceState(surfaceRevision: 3, kind: .edrActive(headroom: 2.0)))
check("T1b", PresenterHDRSurfaceState.edr(revision: 3, headroom: 1.0) == nil)
check("T1c", PresenterHDRSurfaceState.edr(revision: 3, headroom: 0.99) == nil)
check("T1d", PresenterHDRSurfaceState.edr(revision: 3, headroom: .nan) == nil)
check("T1e", PresenterHDRSurfaceState.edr(revision: 3, headroom: .infinity) == nil)
check("T1f", PresenterHDRSurfaceState.edr(revision: 3, headroom: -2.0) == nil)

// T2: ruling 2 revision identity - equal kind, different revision = different state
let e1 = PresenterHDRSurfaceState.edr(revision: 1, headroom: 2.0)!
let e2 = PresenterHDRSurfaceState.edr(revision: 2, headroom: 2.0)!
check("T2a", e1 != e2)
check("T2b", e1.kind == e2.kind)
let n1 = PresenterHDRSurfaceState.notNegotiated(revision: 0)
let n2 = PresenterHDRSurfaceState.notNegotiated(revision: 1)
check("T2c", n1 != n2)

// T3: ruling 4 - toneMapped is its own case, never equal to any sdrFallback
let tm = PresenterHDRSurfaceState.toneMapped(revision: 1, policy: .tonemappedHDRtoSDR)
check("T3a", tm.kind == .toneMapped(.tonemappedHDRtoSDR))
check("T3b", tm != PresenterHDRSurfaceState.sdr(revision: 1, reason: .decoderNotHDR))
check("T3c", tm != PresenterHDRSurfaceState.sdr(revision: 1, reason: .softwareFallbackFlagged))

// T4: make(revision:intent:measuredHeadroom:) negotiation-outcome mapping
let mHDR = PresenterHDRSurfaceState.make(revision: 5, intent: .nativeHDR, measuredHeadroom: 1.6)
check("T4a", mHDR.kind == .edrActive(headroom: 1.6) && mHDR.surfaceRevision == 5)
let mHDRnone = PresenterHDRSurfaceState.make(revision: 5, intent: .nativeHDR, measuredHeadroom: nil)
check("T4b", mHDRnone.kind == .sdrFallback(.noExtendedDynamicRangeHeadroom))
let mHDRflat = PresenterHDRSurfaceState.make(revision: 5, intent: .nativeHDR, measuredHeadroom: 1.0)
check("T4c", mHDRflat.kind == .sdrFallback(.noExtendedDynamicRangeHeadroom))
let mHDRnan = PresenterHDRSurfaceState.make(revision: 5, intent: .nativeHDR, measuredHeadroom: .nan)
check("T4d", mHDRnan.kind == .sdrFallback(.noExtendedDynamicRangeHeadroom))
let mTM = PresenterHDRSurfaceState.make(revision: 5, intent: .tonemappedHDRtoSDR, measuredHeadroom: 4.0)
check("T4e", mTM.kind == .toneMapped(.tonemappedHDRtoSDR))
let mTMnone = PresenterHDRSurfaceState.make(revision: 5, intent: .tonemappedHDRtoSDR, measuredHeadroom: nil)
check("T4f", mTMnone.kind == .toneMapped(.tonemappedHDRtoSDR))
let mSDR = PresenterHDRSurfaceState.make(revision: 5, intent: .nativeSDR, measuredHeadroom: 4.0)
check("T4g", mSDR.kind == .sdrFallback(.decoderNotHDR))

// T5: metrics make() guard domain (frozen HDRScreenMetrics.make parity)
check("T5a", PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: 900,
                                            backingScale: 2, chromeWidth: 0, chromeTop: 24) != nil)
check("T5b", PresenterHDRScreenMetrics.make(usableWidth: 1.9, usableHeight: 900,
                                            backingScale: 2, chromeWidth: 0, chromeTop: 24) == nil)
check("T5c", PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: 900,
                                            backingScale: 0.5, chromeWidth: 0, chromeTop: 24) == nil)
check("T5d", PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: 900,
                                            backingScale: 2, chromeWidth: -1, chromeTop: 24) == nil)
check("T5e", PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: 900,
                                            backingScale: 2, chromeWidth: 0, chromeTop: -0.5) == nil)
check("T5f", PresenterHDRScreenMetrics.make(usableWidth: .nan, usableHeight: 900,
                                            backingScale: 2, chromeWidth: 0, chromeTop: 24) == nil)
check("T5g", PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: .infinity,
                                            backingScale: 2, chromeWidth: 0, chromeTop: 24) == nil)

// T6: ruling 5 drawable derivation (points * backingScale, presenter-side only)
let met = PresenterHDRScreenMetrics.make(usableWidth: 1440, usableHeight: 900,
                                         backingScale: 2, chromeWidth: 0, chromeTop: 24)!
check("T6a", met.derivedDrawableSize()?.width == 2880 && met.derivedDrawableSize()?.height == 1800)
let metHalf = PresenterHDRScreenMetrics.make(usableWidth: 1440.25, usableHeight: 900,
                                             backingScale: 2, chromeWidth: 0, chromeTop: 24)!
check("T6b", metHalf.derivedDrawableSize()?.width == 2881)  // 2880.5 rounds away from zero
let metTiny = PresenterHDRScreenMetrics.make(usableWidth: 2, usableHeight: 2,
                                             backingScale: 1, chromeWidth: 0, chromeTop: 0)!
check("T6c", metTiny.derivedDrawableSize()?.width == 2 && metTiny.derivedDrawableSize()?.height == 2)
let metHuge = PresenterHDRScreenMetrics.make(usableWidth: 9000, usableHeight: 9000,
                                             backingScale: 2, chromeWidth: 0, chromeTop: 0)!
check("T6d", metHuge.derivedDrawableSize() == nil)  // 18000 > 16384 texture-side cap: typed refusal

// T7: provider publish semantics
let p = HDRSurfaceStateProvider()
check("T7a", p.currentHDRSurfaceState == .notNegotiated(revision: 0))
// first real negotiation lands at renderer revision 0
check("T7b", p.publish(.sdr(revision: 0, reason: .decoderNotHDR)) == nil)
check("T7c", p.currentHDRSurfaceState.kind == .sdrFallback(.decoderNotHDR))
// idempotent re-publish of the current (revision, kind)
check("T7d", p.publish(.sdr(revision: 0, reason: .decoderNotHDR)) == nil)
// kind change at the SAME revision is a typed refusal, state unchanged
check("T7e", p.publish(PresenterHDRSurfaceState.edr(revision: 0, headroom: 2.0)!)
      == .kindChangeAtSameRevision(revision: 0))
check("T7f", p.currentHDRSurfaceState.kind == .sdrFallback(.decoderNotHDR))
// renegotiation bumps the revision
check("T7g", p.publish(PresenterHDRSurfaceState.edr(revision: 1, headroom: 2.0)!) == nil)
check("T7h", p.currentHDRSurfaceState.kind == .edrActive(headroom: 2.0)
      && p.currentHDRSurfaceState.surfaceRevision == 1)
// regression is a typed refusal, state unchanged
check("T7i", p.publish(.sdr(revision: 0, reason: .decoderNotHDR))
      == .regressedRevision(published: 0, current: 1))
check("T7j", p.currentHDRSurfaceState.surfaceRevision == 1)

// T8: mirror enum is exactly the 3-case OutputIntent set (mirror drift guard)
check("T8", HDRNegotiatedIntent.allCases.count == 3)

print("hdr-presenter-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
