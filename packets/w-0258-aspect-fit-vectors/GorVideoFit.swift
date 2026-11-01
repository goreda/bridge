// gor 514 / owner 170c: single video-window sizing rule, all orientations.
// Pure value math with zero imports so the SAME file compiles into the
// macOS app target and into the Linux test harness unchanged.
//
// Fit domain (2026-11-01 ruling, gdb correction record + architect exact-
// INTEGER requirement): the contain rule below is EXACT Int64 rational
// floor under an explicit integer domain (see the contract on containFit);
// typed refusal outside it, never a silent min-1 floor. The sqrt opening
// chooser stays an independent float policy layer.
//
// Owner constraints (170c, peer-relayed):
//   - "hem ölçekli hem küçültülmüş": scaled opening AND shrink-to-fit.
//   - scale = resolution-sensitive: 4K opens larger than 720p but never at
//     full screen width.
//   - hard bound: no resolution ever exceeds the usable screen (visibleFrame)
//     in width or height; aspect always preserved.
//   - landscape/current opening behavior for the <=720p class is unchanged.
//
// Curve (TECHNICAL DESIGN, not owner-quoted numbers):
//   longTarget = max(screenW * floorFraction,
//                    screenW * floorFraction * sqrt(longSide / 1280))
//   - floor = today's behavior: <=720p class (long side <= 1280) opens exactly
//     like the historical --geometry=40% (or 38% at music-mode exit).
//   - above 720p the opening grows with the square root of the long side:
//     bigger videos open bigger, with diminishing returns, never jumping to
//     full screen width (4K = x1.732 of the floor).
//   The proposed opening is then passed through fit() which only shrinks
//   (scale = min(1, avail.w/v.w, avail.h/v.h)), rounds down and centers.

struct GorFitSize: Equatable {
    var w: Double
    var h: Double
}

struct GorFitRect: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

enum GorVideoFit {
    /// Today's launch baseline (--geometry=40% at AppDelegate launchMPV).
    static let openBaselineFraction = 0.40
    /// Today's music-mode exit restore (38% at PPController_Features).
    static let musicExitBaselineFraction = 0.38
    /// Resolution class anchor: long side 1280 (720p class) = the floor.
    static let baselineLongSide = 1280.0

    /// Resolution-sensitive proposed opening size (the "scale" half).
    static func proposedOpenSize(videoW: Double, videoH: Double,
                                 screenW: Double,
                                 floorFraction: Double = openBaselineFraction) -> GorFitSize {
        guard videoW > 0, videoH > 0, screenW > 0, floorFraction > 0 else {
            return GorFitSize(w: 0, h: 0)
        }
        let longSide = max(videoW, videoH)
        let floorTarget = screenW * floorFraction
        let scaledTarget = floorTarget * (longSide / baselineLongSide).squareRoot()
        let longTarget = max(floorTarget, scaledTarget).rounded(.down)
        // F2 (review): extreme aspect ratios must never propose a zero side;
        // clamp both derived sides to >= 1 (a zero proposal silently degraded
        // to no geometry at all).
        if videoW >= videoH {
            return GorFitSize(w: max(1, longTarget), h: max(1, (longTarget * videoH / videoW).rounded(.down)))
        } else {
            return GorFitSize(w: max(1, (longTarget * videoW / videoH).rounded(.down)), h: max(1, longTarget))
        }
    }

    /// The shrink-and-center rule (the "küçültülmüş" half; literal 170c formula):
    ///   scale   = min(1, avail.w / v.w, avail.h / v.h)   (shrink only)
    ///   content = v * scale, rounded down
    ///   window  = content centered inside avail
    /// v7 (fit-domain ruling 2026-11-01 + architect exact-INTEGER
    /// requirement 05:11; architect-qualified 05:15:02): the contain rule is
    /// EXACT INTEGER arithmetic, not a float approximation argued exact.
    ///
    /// CONTRACT (explicit; a cell PASS list alone does not state it):
    ///  - Integer domain: video and avail sizes are whole points/pixels with
    ///    0 < size <= Int32.max (covers a 2-billion-px video; products then
    ///    stay <= 2^62, inside Int64 - no overflow inside the domain).
    ///    Origins may be negative (multi-monitor) within the same magnitude.
    ///  - Conversion policy: Double call sites FLOOR each input at the
    ///    boundary before the integer rule runs. Sub-point precision is
    ///    outside this contract; no gor caller needs it (video dims are
    ///    whole pixels, screen frames whole points in practice; floor-at-
    ///    the-boundary matches the previous float pipeline to <1pt).
    ///  - Exact rule: constrained axis assigned from avail directly; free
    ///    axis = exact rational floor(freeVideo * availDim / videoDim) in
    ///    Int64 - NO epsilon, no tolerance, no materialized scale factor.
    ///    Axis choice by Int64 cross-multiplied compare.
    ///  - Result: .ok(rect) when both sides floor to >= 1; otherwise TYPED
    ///    .unrepresentable(axis, scaled) - never a silent min-1 floor.
    ///    Inputs violating the integer domain return .outOfIntegerDomain.
    ///  - The sqrt opening chooser (proposedOpenSize) is an independent
    ///    float POLICY layer and is deliberately untouched.
    enum GorFitContain: Equatable {
        case ok(GorFitRect)
        case unrepresentable(axis: String, scaled: Double)
        case outOfIntegerDomain
    }
    private static let intDomainLimit: Int64 = Int64(Int32.max)

    /// Exact-integer contain core. All arithmetic Int64; every product is
    /// bounded by intDomainLimit^2 < Int64.max inside the domain, so no
    /// checked-arithmetic trap can fire for in-domain inputs.
    static func containFitInt(videoW vw: Int64, videoH vh: Int64,
                              availX ax: Int64, availY ay: Int64,
                              availW aw: Int64, availH ah: Int64) -> GorFitContain {
        guard vw > 0, vh > 0, aw > 0, ah > 0 else {
            return .ok(GorFitRect(x: Double(ax), y: Double(ay), w: 0, h: 0))
        }
        guard vw <= intDomainLimit, vh <= intDomainLimit,
              aw <= intDomainLimit, ah <= intDomainLimit,
              abs(ax) <= intDomainLimit, abs(ay) <= intDomainLimit else {
            return .outOfIntegerDomain
        }
        let cw: Int64, ch: Int64
        if vw <= aw && vh <= ah {
            cw = vw; ch = vh
        } else if aw * vh <= ah * vw {
            cw = aw
            ch = vh * aw / vw              // exact rational floor (Int64)
        } else {
            ch = ah
            cw = vw * ah / vh              // exact rational floor (Int64)
        }
        if cw < 1 {
            return .unrepresentable(axis: "width",
                                    scaled: Double(vw) * min(1.0, Double(ah) / Double(vh)))
        }
        if ch < 1 {
            return .unrepresentable(axis: "height",
                                    scaled: Double(vh) * min(1.0, Double(aw) / Double(vw)))
        }
        // Integer centering: (aw - cw) >= 0 and Int64 division truncates
        // toward zero = floor for non-negative values; adding the (possibly
        // negative) origin is exact.
        let cx = ax + (aw - cw) / 2
        let cy = ay + (ah - ch) / 2
        return .ok(GorFitRect(x: Double(cx), y: Double(cy), w: Double(cw), h: Double(ch)))
    }

    static func containFit(video: GorFitSize, avail: GorFitRect) -> GorFitContain {
        // Named conversion policy: floor at the boundary. Degenerate sizes
        // (zero, negative, or NaN - NaN fails every > 0 check) take the
        // pre-existing EMPTY-rect convention (.ok(w == 0)), NOT
        // .outOfIntegerDomain; only POSITIVE sizes beyond Int32.max (or
        // out-of-range origins) are .outOfIntegerDomain. The magnitude
        // guard must run BEFORE conversion: Double -> Int64 conversion of
        // an out-of-range value would trap.
        let sizes = [video.w, video.h, avail.w, avail.h]
        guard sizes.allSatisfy({ $0 > 0 }) else {
            return .ok(GorFitRect(x: avail.x, y: avail.y, w: 0, h: 0))
        }
        guard sizes.allSatisfy({ $0 <= Double(Int32.max) }),
              abs(avail.x) <= Double(Int32.max), abs(avail.y) <= Double(Int32.max) else {
            return .outOfIntegerDomain
        }
        return containFitInt(videoW: Int64(video.w.rounded(.down)), videoH: Int64(video.h.rounded(.down)),
                             availX: Int64(avail.x.rounded(.down)), availY: Int64(avail.y.rounded(.down)),
                             availW: Int64(avail.w.rounded(.down)), availH: Int64(avail.h.rounded(.down)))
    }
    static func fit(video: GorFitSize, avail: GorFitRect) -> GorFitRect {
        switch containFit(video: video, avail: avail) {
        case .ok(let r): return r
        case .unrepresentable, .outOfIntegerDomain:
            // Typed refusal -> the standing no-legal-set convention: zero
            // rect, skipped by sendFitGeometry, propagated by opening().
            return GorFitRect(x: avail.x, y: avail.y, w: 0, h: 0)
        }
    }

    /// User-resize lock (owner ruling 2026-11-01 via gdb relay, "of course it
    /// should lock"): a manual resize must LOCK the window to the VIDEO aspect
    /// (post-rotation display dims) and stay hard-bounded inside the usable
    /// area on BOTH axes. The window does NOT stay free-form with black bars,
    /// and is NOT recentered - the user's origin survives whenever it fits.
    ///
    /// Gesture driver: the axis that changed MOST relative to the pre-gesture
    /// size (`previous`) is treated as the one the user dragged; the OTHER
    /// axis is projected onto the video aspect from it. Ties drive from the
    /// width. (A snapshot-only "minimal deviation" rule is unstable under
    /// floor rounding and can snap the window AWAY from the drag direction.)
    ///
    /// Then: hard bound both axes into avail with a single shrink factor
    /// (never grows back above the user's size); floor to whole points.
    /// If the result falls below minWin on either axis there is NO legal
    /// set (production minWin = mpv Cocoa minSize 160x90, v0.41.0
    /// video/out/mac/window.swift:91 - smaller frames are silently rejected
    /// by its setFrame guard, :362-366), so the window is left untouched
    /// instead of sending a doomed set or breaking the bound by growing.
    /// Position: preserve the user's origin while it fits; clamp into avail
    /// only as far as the bound requires.
    ///
    /// The gesture-driving axis is a DIRECTION choice, not a pixel promise:
    /// after aspect projection and floor rounding its final value can land
    /// up to ~2pt off the raw drag position (reviewer probe, v3 review).
    ///
    /// Stability: an aspect-true, in-bounds rect with previous == itself maps
    /// to itself (tie -> keep width -> projection returns the same size), so
    /// our own geometry set never re-triggers a visible change; the AppKit
    /// call site additionally no-ops inside a 1pt tolerance.
    static func lockedResize(window: GorFitRect, videoW: Double, videoH: Double,
                             avail: GorFitRect, previous: GorFitSize,
                             minWin: GorFitSize) -> GorFitRect {
        guard window.w > 0, window.h > 0, videoW > 0, videoH > 0,
              avail.w > 0, avail.h > 0, previous.w > 0, previous.h > 0 else { return window }
        // Which axis did the gesture drive? Larger relative change wins.
        let relW = abs(window.w - previous.w) / previous.w
        let relH = abs(window.h - previous.h) / previous.h
        let keepWidth = relW >= relH
        // v7 exact-INTEGER projection + bound (architect 05:11). DERIVATION
        // ORDER unchanged: gesture axis bounded first, height re-derived
        // from the final floored width (v5 settled-size parity); the
        // gesture-axis CHOICE above stays a float policy decision. Because
        // the projected pair always lies on the video ray, the drag
        // dimension CANCELS in every composed ratio: each result below is a
        // SINGLE Int64 division of products <= 2^62 inside the integer
        // domain (dims whole points/pixels, 1...Int32.max after the named
        // floor-at-the-boundary conversion). No materialized scale factor,
        // no floored-then-shrunk composition (the 159-vs-160 loss), no
        // epsilon.
        guard window.w < 2_147_483_648, window.h < 2_147_483_648,
              videoW < 2_147_483_648, videoH < 2_147_483_648,
              avail.w < 2_147_483_648, avail.h < 2_147_483_648 else { return window }
        let ivw = Int64(videoW.rounded(.down)), ivh = Int64(videoH.rounded(.down))
        let iaw = Int64(avail.w.rounded(.down)), iah = Int64(avail.h.rounded(.down))
        guard ivw >= 1, ivh >= 1, iaw >= 1, iah >= 1 else { return window }
        var iW: Int64, iH: Int64
        if keepWidth {
            iW = Int64(window.w.rounded(.down))
            iH = iW > 0 ? iW * ivh / ivw : 0
        } else {
            iH = Int64(window.h.rounded(.down))
            iW = iH > 0 ? iH * ivw / ivh : 0
        }
        // Sub-1pt converted inputs have no legal integer set (v5 parity:
        // they fell into the minWin refusal below after flooring to 0).
        guard iW >= 1, iH >= 1 else { return window }
        if iW > iaw || iH > iah {
            if iaw * iH <= iah * iW {
                // Width is the tighter bound: assign it exactly (the float
                // form floor(fw * avail.w / fw) can land at avail.w - 1).
                iW = iaw
            } else {
                // Height is the tighter bound. The drag dimension cancels
                // on the video ray: this is floor(iah * ivw / ivh), exact.
                iW = iah * ivw / ivh
            }
            // Defensive (kept): if the derived height still exceeds, bind
            // height and re-derive width from it (same ray formula).
            if iW * ivh / ivw > iah {
                iH = iah
                iW = iH * ivw / ivh
            }
        }
        let fw = Double(iW)
        let fh = Double(iW * ivh / ivw)
        // Backend minimum window size (production: mpv Cocoa minSize 160x90,
        // v0.41.0 video/out/mac/window.swift:94 - its setFrame override
        // silently REJECTS anything smaller, lines 365-370). A set below
        // minWin is therefore not a legal set, and growing up to minWin would
        // break the hard avail bound - so there is no legal set at all and we
        // leave the user's window untouched (honest no-op, never a doomed
        // set that silently does nothing on the real backend).
        if fw < minWin.w || fh < minWin.h { return window }
        // Position: preserve the user's origin while it fits; clamp into avail
        // only as far as the bound requires. No recentering.
        let fx = min(max(window.x, avail.x), avail.x + max(0, avail.w - fw))
        let fy = min(max(window.y, avail.y), avail.y + max(0, avail.h - fh))
        return GorFitRect(x: fx, y: fy, w: fw, h: fh)
    }

    /// Full opening pipeline: proposed opening size, shrunk to fit, centered,
    /// then checked against the backend minimum window size.
    ///
    /// G1 (v4 review): a fitted opening below minWin is a DOOMED set on the
    /// real backend (mpv Cocoa minSize 160x90, v0.41.0 window.swift:91;
    /// setFrame rejects smaller, :362-366). When that happens, grow
    /// UNIFORMLY up to the minimum (aspect preserved, up to ~1pt of rounding)
    /// - but only while the grown size still fits the usable area. If the
    /// minimum itself does not fit, there is no legal opening set: return
    /// the zero rect (w == 0), which sendFitGeometry already skips.
    static func opening(videoW: Double, videoH: Double,
                        screenW: Double, avail: GorFitRect,
                        floorFraction: Double = openBaselineFraction,
                        minWin: GorFitSize) -> GorFitRect {
        let proposed = proposedOpenSize(videoW: videoW, videoH: videoH,
                                        screenW: screenW, floorFraction: floorFraction)
        let fitted = fit(video: proposed, avail: avail)
        guard fitted.w > 0, fitted.h > 0 else { return fitted }
        if fitted.w >= minWin.w, fitted.h >= minWin.h { return fitted }
        let g = max(minWin.w / fitted.w, minWin.h / fitted.h)
        // Round UP both axes: rounding down could stay below the minimum.
        let gw = (fitted.w * g).rounded(.up)
        let gh = (fitted.h * g).rounded(.up)
        guard gw <= avail.w, gh <= avail.h else {
            return GorFitRect(x: avail.x, y: avail.y, w: 0, h: 0)
        }
        let cx = (avail.x + (avail.w - gw) / 2).rounded(.down)
        let cy = (avail.y + (avail.h - gh) / 2).rounded(.down)
        return GorFitRect(x: cx, y: cy, w: gw, h: gh)
    }
}
