import Foundation
// MARK: - gor 514 portrait fit: video fit math, opening fit, real mpv crop (inlined, no new files)
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
//   - "both scaled and shrunk": scaled opening AND shrink-to-fit.
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

    /// The shrink-and-center rule (the "shrunk" half; literal 170c formula):
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

// gor 514 crop candidate: real mpv crop for a committed crop-detect rect (owner 04:49: "apply the
// crop-detect result as the video crop when its success rate is high"). Pure, no AppKit.
// - FULL-frame detection dimensions (videoDisplayW/H) are never replaced; the cropped aspect is a
//   separate value (effectiveAspect).
// - A LABELLED filter (@gorcrop) so unrelated filters (e.g. SBS / aspect menus) are untouched.
// - mpv acks `vf add` with "success" even when the filter did not take (measured, VF-LABEL-IPC.txt),
//   so success is only declared after reading the vf list back and matching the requested params.
// - The overlay is the identity ONLY in phase .active; in every other phase (idle, failure,
//   removed) the existing overlay crop path is untouched, which is the restore state.

struct GorCropFilter: Equatable {
    var w: Int, h: Int, x: Int, y: Int
    var arg: String { "crop=w=\(w):h=\(h):x=\(x):y=\(y)" }
}

enum GorCropPlan {
    static let label = "gorcrop"
    static let minSide = 16
    /// Smallest area fraction that is still worth a real crop; a rect covering ~everything is no crop.
    static let maxAreaFraction = 0.98

    /// rect: fractions of the FULL frame (x,y from the top-left, as CropDetector's normalized cropRect
    /// before applyVideoFrame flips it). Even-aligned integer pixels inside the frame.
    static func plan(fx: Double, fy: Double, fw: Double, fh: Double,
                     videoW: Double, videoH: Double) -> GorCropFilter? {
        guard videoW >= 2, videoH >= 2, fw > 0.1, fh > 0.1,
              fx >= -0.001, fy >= -0.001, fx + fw <= 1.001, fy + fh <= 1.001 else { return nil }
        func even(_ v: Double) -> Int { max(0, Int((v / 2).rounded()) * 2) }
        var x = even(fx * videoW), y = even(fy * videoH)
        var w = even(fw * videoW), h = even(fh * videoH)
        let vw = Int(videoW.rounded(.down)), vh = Int(videoH.rounded(.down))
        x = min(x, vw - minSide); y = min(y, vh - minSide)
        w = min(w, vw - x); h = min(h, vh - y)
        w -= w % 2; h -= h % 2
        guard w >= minSide, h >= minSide else { return nil }
        guard Double(w * h) / Double(vw * vh) < maxAreaFraction else { return nil }
        return GorCropFilter(w: w, h: h, x: x, y: y)
    }

    /// Real crop is only planned for square-pixel, unrotated video: the detector's rect is in DISPLAY
    /// fractions while `vf crop` works on coded pixels, so they only coincide when coded == display.
    /// Anything else keeps the existing overlay crop (no behavior change).
    static func eligible(codedW: Double, codedH: Double, dispW: Double, dispH: Double) -> Bool {
        codedW >= 2 && codedH >= 2 && abs(codedW - dispW) < 1 && abs(codedH - dispH) < 1
    }

    static func effectiveAspect(_ f: GorCropFilter) -> Double { Double(f.w) / Double(f.h) }

    static func addCommand(_ f: GorCropFilter, id: Int) -> String {
        "{\"command\":[\"vf\",\"add\",\"@\(label):\(f.arg)\"],\"request_id\":\(id)}"
    }
    static func removeCommand(id: Int) -> String {
        "{\"command\":[\"vf\",\"remove\",\"@\(label)\"],\"request_id\":\(id)}"
    }
    static func queryCommand(id: Int) -> String {
        "{\"command\":[\"get_property\",\"vf\"],\"request_id\":\(id)}"
    }

    static func propertyCommand(_ name: String, id: Int) -> String {
        "{\"command\":[\"get_property\",\"\(name)\"],\"request_id\":\(id)}"
    }
    static func outParamsCommand(id: Int) -> String {
        "{\"command\":[\"get_property\",\"video-out-params\"],\"request_id\":\(id)}"
    }
    /// The filter really took effect: mpv's post-filter frame size equals the requested crop. mpv reports the cropped
    /// size in more than one field (w/h, the crop rectangle crop-w/crop-h, and the display size dw/dh); on a path where
    /// w/h keep the coded size but the crop is live, only the others change. The Mac log of 2026-11-02 02:25 shows
    /// that sequence: w/h never matched in 10 reads (about 2.4 s), then the display size was reported as the cropped
    /// 1480x1080 while our removal was in flight (inference, not measured on a Mac), and the false "never took effect" then removed a working crop and refit the window to the full frame while the overlay
    /// kept the crop. Any one of the three fields at the cropped size confirms it. Eligibility (square pixels, planner
    /// area < 98%) guarantees a cropped size differs from the full frame.
    static func confirms(outParams: Any?, expected f: GorCropFilter) -> Bool {
        guard let p = outParams as? [String: Any] else { return false }
        func n(_ k: String) -> Int? { (p[k] as? Int) ?? (p[k] as? Double).map { Int($0) } }
        func at(_ a: String, _ b: String) -> Bool { n(a) == f.w && n(b) == f.h }
        return at("w", "h") || at("crop-w", "crop-h") || at("dw", "dh")
    }

    /// Does the mpv `vf` property list contain our labelled crop with exactly the requested params?
    static func verify(vfList: Any?, expected f: GorCropFilter) -> Bool {
        guard let list = vfList as? [[String: Any]] else { return false }
        guard let e = list.first(where: { ($0["label"] as? String) == label }),
              (e["name"] as? String) == "crop",
              let p = e["params"] as? [String: Any] else { return false }
        func num(_ k: String) -> Int? {
            if let s = p[k] as? String { return Int(s) }
            if let n = p[k] as? Int { return n }
            if let d = p[k] as? Double { return Int(d) }
            return nil
        }
        return num("w") == f.w && num("h") == f.h && num("x") == f.x && num("y") == f.y
    }
    static func isPresent(vfList: Any?) -> Bool {
        guard let list = vfList as? [[String: Any]] else { return false }
        return list.contains { ($0["label"] as? String) == label }
    }
}

/// Crop rect as the detector produces it: fractions of the FULL frame, y from the top.
struct GorCropRequest: Equatable { var fx: Double, fy: Double, fw: Double, fh: Double }

extension GorCropPlan {
    static func probeCommand(id: Int) -> String {
        "{\"command\":[\"get_property\",\"video-params\"],\"request_id\":\(id)}"
    }
    /// From mpv `video-params`: coded size when the video is square-pixel and unrotated, else nil
    /// (the overlay crop path then stays in charge: no behavior change).
    static func codedSizeIfEligible(videoParams: Any?) -> (w: Double, h: Double)? {
        guard let p = videoParams as? [String: Any] else { return nil }
        func d(_ k: String) -> Double? { (p[k] as? Double) ?? (p[k] as? Int).map(Double.init) }
        guard let w = d("w"), let h = d("h"), let dw = d("dw"), let dh = d("dh") else { return nil }
        let rot = d("rotate") ?? 0
        guard rot == 0, w >= 2, h >= 2, abs(w - dw) < 1, abs(h - dh) < 1 else { return nil }
        return (w, h)
    }

    /// Window frame (AppKit points, y-up) for the cropped aspect: keep the user's width, anchor the top-left,
    /// shrink uniformly if it does not fit `avail` on BOTH axes, then shift inside `avail`.
    static func refitFrame(frame: GorFitRect, aspect: Double, chromeW: Double, chromeH: Double,
                           avail: GorFitRect) -> GorFitRect? {
        guard aspect > 0.01, aspect < 100, frame.w > chromeW + 1, avail.w > chromeW + 1, avail.h > chromeH + 1 else { return nil }
        var cw = frame.w - chromeW
        var ch = cw / aspect
        let maxCW = avail.w - chromeW, maxCH = avail.h - chromeH
        if cw > maxCW { cw = maxCW; ch = cw / aspect }
        if ch > maxCH { ch = maxCH; cw = ch * aspect }
        cw = cw.rounded(.down); ch = ch.rounded(.down)
        guard cw >= 1, ch >= 1 else { return nil }
        let w = cw + chromeW, h = ch + chromeH
        let top = frame.y + frame.h
        var x = frame.x, y = top - h
        x = min(max(x, avail.x), avail.x + avail.w - w)
        y = min(max(y, avail.y), avail.y + avail.h - h)
        return GorFitRect(x: x, y: y, w: w, h: h)
    }
}

/// Crop-application protocol. All transitions are pure; the caller performs the returned actions.
struct GorCropMPV {
    enum Phase: Equatable {
        case idle
        case probing(id: Int, req: GorCropRequest, prior: GorCropFilter?)
        case adding(id: Int, filter: GorCropFilter, prior: GorCropFilter?)
        case verifying(id: Int, filter: GorCropFilter, prior: GorCropFilter?)
        case confirming(id: Int, filter: GorCropFilter, attempt: Int, prior: GorCropFilter?)
        /// Same attempt, reading mpv's real dwidth / dheight properties (the owner's Mac log shows the cropped size on this channel).
        case confirmingDW(id: Int, filter: GorCropFilter, attempt: Int, prior: GorCropFilter?)
        case confirmingDH(id: Int, filter: GorCropFilter, attempt: Int, prior: GorCropFilter?)
        case active(filter: GorCropFilter)
        case removing(id: Int, restoreAfterFailure: Bool)
    }
    enum Action: Equatable {
        case send(String)
        /// Same, but after a delay (mpv reconfigures its filter chain asynchronously).
        case sendAfter(String, ms: Int)
        /// Overlay becomes identity (mpv crop is live and verified) / back to the overlay crop path.
        case overlayIdentity(Bool)
        /// Window should refit to this effective (cropped) aspect.
        case refit(aspect: Double)
        /// Window should refit back to the FULL-frame aspect (crop removed).
        case refitFull
        case failed(String)
        /// A genuine failure finished its removal: the window is refit to the full frame, so the UI crop must go too.
        case cropAbandoned
    }
    private(set) var phase: Phase = .idle
    private var nextId = GorCropMPV.idRange.lowerBound
    private var pendingRequest: GorCropRequest? = nil
    private var pendingClear = false

    /// True while mpv shows (or is switching between) verified real crops, so the overlay draws NO crop of its own.
    /// A re-rect keeps it true until the outcome is known (no double-crop flash).
    var overlayIsIdentity: Bool {
        switch phase {
        case .active: return true
        case .probing(_, _, let p), .adding(_, _, let p), .verifying(_, _, let p), .confirming(_, _, _, let p), .confirmingDW(_, _, _, let p), .confirmingDH(_, _, _, let p): return p != nil
        default: return false
        }
    }
    /// Post-filter size mpv reports while our crop is (or is about to be) live. PPController maps it back to the FULL frame.
    var knownCroppedSizes: [GorCropFilter] {
        switch phase {
        case .active(let f): return [f]
        case .adding(_, let f, let p), .verifying(_, let f, let p), .confirming(_, let f, _, let p), .confirmingDW(_, let f, _, let p), .confirmingDH(_, let f, _, let p): return [f] + (p.map { [$0] } ?? [])
        case .probing(_, _, let p): return p.map { [$0] } ?? []
        case .removing: return []   // size reverts to full; either value is fine
        case .idle: return []
        }
    }
    /// The crop mpv is showing right now (active, or the previous one while a re-rect is in flight).
    var displayedFilter: GorCropFilter? {
        switch phase {
        case .active(let f): return f
        case .probing(_, _, let p), .adding(_, _, let p), .verifying(_, _, let p), .confirming(_, _, _, let p), .confirmingDW(_, _, _, let p), .confirmingDH(_, _, _, let p): return p
        default: return nil
        }
    }
    /// Id of the reply currently awaited (for the caller's watchdog), nil when nothing is in flight.
    var awaitedId: Int? {
        switch phase {
        case .probing(let i, _, _), .adding(let i, _, _), .verifying(let i, _, _), .confirming(let i, _, _, _), .confirmingDW(let i, _, _, _), .confirmingDH(let i, _, _, _), .removing(let i, _): return i
        default: return nil
        }
    }
    /// Watchdog: the awaited reply never came (socket down, mpv gone). Fall back to the overlay path and try to
    /// take our label out; a later request starts clean instead of being blocked forever.
    mutating func timedOut(id: Int) -> [Action] {
        guard awaitedId == id else { return [] }
        if case .removing = phase { phase = .idle; return [.overlayIdentity(false)] + settle() }
        return fail("no reply from mpv (watchdog)", removeLabel: true)
    }
    var activeFilter: GorCropFilter? { if case .active(let f) = phase { return f }; return nil }
    static let maxConfirmAttempts = 10
    /// Large range: a wrap would need a million mints, so a late reply cannot be mistaken for a newer request.
    static let idRange = 2_000_000..<3_000_000
    static func owns(id: Int) -> Bool { idRange.contains(id) }

    private mutating func mint() -> Int {
        let id = nextId; nextId += 1; if nextId >= Self.idRange.upperBound { nextId = Self.idRange.lowerBound }; return id
    }
    private var busy: Bool {
        switch phase { case .probing, .adding, .verifying, .confirming, .confirmingDW, .confirmingDH, .removing: return true; default: return false }
    }

    /// A committed crop (apply / reRect). Coalesces while a request is in flight.
    mutating func request(_ r: GorCropRequest) -> [Action] {
        pendingClear = false
        if busy { pendingRequest = r; return [] }
        let prior = activeFilter
        let id = mint(); phase = .probing(id: id, req: r, prior: prior)
        return [.send(GorCropPlan.probeCommand(id: id))]
    }

    /// Revert / reset / new file: remove our filter (idempotent at mpv: removing a missing label succeeds).
    mutating func clear() -> [Action] {
        pendingRequest = nil
        if busy { pendingClear = true; return [] }
        switch phase {
        case .idle: return []
        default:
            let id = mint(); phase = .removing(id: id, restoreAfterFailure: false)
            return [.overlayIdentity(false), .send(GorCropPlan.removeCommand(id: id))]
        }
    }

    /// Reply to one of our request ids. ok = mpv "error" == "success". data = reply data.
    mutating func reply(id: Int, ok: Bool, data: Any?) -> [Action] {
        switch phase {
        case .probing(let cur, let r, let prior) where cur == id:
            guard ok, let size = GorCropPlan.codedSizeIfEligible(videoParams: data) else {
                return fail("real crop not eligible (anamorphic/rotated/unreadable): overlay crop stays", removeLabel: prior != nil)
            }
            guard let f = GorCropPlan.plan(fx: r.fx, fy: r.fy, fw: r.fw, fh: r.fh, videoW: size.w, videoH: size.h) else {
                return fail("crop rect rejected by planner: overlay crop stays", removeLabel: prior != nil)
            }
            if let p = prior, p == f { phase = .active(filter: f); return settle() }
            let aid = mint(); phase = .adding(id: aid, filter: f, prior: prior)
            return [.send(GorCropPlan.addCommand(f, id: aid))]
        case .adding(let cur, let f, let prior) where cur == id:
            guard ok else { return fail("vf add refused", removeLabel: prior != nil) }
            let qid = mint(); phase = .verifying(id: qid, filter: f, prior: prior)
            return [.send(GorCropPlan.queryCommand(id: qid))]
        case .verifying(let cur, let f, let prior) where cur == id:
            if ok, GorCropPlan.verify(vfList: data, expected: f) {
                let qid = mint(); phase = .confirming(id: qid, filter: f, attempt: 1, prior: prior)
                return [.sendAfter(GorCropPlan.outParamsCommand(id: qid), ms: 150)]
            }
            // mpv acked but the filter is not what we asked: take our label out, overlay path stays.
            return fail("vf readback mismatch", removeLabel: GorCropPlan.isPresent(vfList: data))
        case .confirming(let cur, let f, let attempt, let prior) where cur == id:
            if ok, GorCropPlan.confirms(outParams: data, expected: f) {
                phase = .active(filter: f)
                var a: [Action] = [.overlayIdentity(true), .refit(aspect: GorCropPlan.effectiveAspect(f))]
                a += settle(); return a
            }
            // video-out-params did not show the cropped size: read the real dwidth property next.
            let did = mint(); phase = .confirmingDW(id: did, filter: f, attempt: attempt, prior: prior)
            return [.send(GorCropPlan.propertyCommand("dwidth", id: did))]
        case .confirmingDW(let cur, let f, let attempt, let prior) where cur == id:
            if ok, let v = (data as? Int) ?? (data as? Double).map({ Int($0) }), v == f.w {
                let did = mint(); phase = .confirmingDH(id: did, filter: f, attempt: attempt, prior: prior)
                return [.send(GorCropPlan.propertyCommand("dheight", id: did))]
            }
            return nextConfirmAttempt(f, attempt, prior)
        case .confirmingDH(let cur, let f, let attempt, let prior) where cur == id:
            if ok, let v = (data as? Int) ?? (data as? Double).map({ Int($0) }), v == f.h {
                phase = .active(filter: f)
                var a: [Action] = [.overlayIdentity(true), .refit(aspect: GorCropPlan.effectiveAspect(f))]
                a += settle(); return a
            }
            return nextConfirmAttempt(f, attempt, prior)
        case .removing(let cur, let afterFailure) where cur == id:
            phase = .idle
            var a: [Action] = [.overlayIdentity(false), .refitFull]
            if afterFailure { a.append(.cropAbandoned) }
            a += settle(); return a
        default:
            return []   // stale / unknown id
        }
    }

    private mutating func nextConfirmAttempt(_ f: GorCropFilter, _ attempt: Int, _ prior: GorCropFilter?) -> [Action] {
        if attempt < Self.maxConfirmAttempts {
            let qid = mint(); phase = .confirming(id: qid, filter: f, attempt: attempt + 1, prior: prior)
            return [.sendAfter(GorCropPlan.outParamsCommand(id: qid), ms: 150)]
        }
        return fail("crop never took effect (post-filter size, out-params and dwidth/dheight all mismatch)", removeLabel: true)
    }

    private mutating func fail(_ why: String, removeLabel: Bool) -> [Action] {
        var a: [Action] = [.overlayIdentity(false), .failed(why)]
        if removeLabel {
            let id = mint(); phase = .removing(id: id, restoreAfterFailure: true)
            a.append(.send(GorCropPlan.removeCommand(id: id)))
        } else {
            phase = .idle; a += settle()
        }
        return a
    }

    private mutating func settle() -> [Action] {
        if pendingClear { pendingClear = false; return clear() }
        if let r = pendingRequest { pendingRequest = nil; return request(r) }
        return []
    }
}

// MARK: - gor 514 portrait fit: window clamp + ack/landing fence (inlined, no new files)
// ================================================================
//  GorWindowClamp - gor 514 trigger/clamp unit (candidate v4)
//  Owns: the PURE clamp math that re-fits the EXISTING mpv window into
//  a changed usable screen area, the reference-screen pick, the guard
//  predicate for the evaluation's reentrancy discipline, and the pure
//  trigger helpers (usable-area snapshot diff, user-resize receipt
//  classification).
//  AppKit glue lives in AppDelegate (trigger, state) and GorOpeningFit
//  (geometry emission).
//
//  STATUS: NEW wiring candidate (2026-11-01 v3), static review only.
//  v2: user-resize trigger (AX receipt classification) + usable-area
//  snapshot poll (didChangeScreenParametersNotification is documented
//  for display reconfig; Dock POSITION reportedly fires it, Dock SIZE
//  has documented non-firing evidence - poll is the catch-all).
//  v3 (reviewer F-1): a guard-blocked evaluation is no longer DROPPED.
//  Terminal blocks (fullscreen, minimized, no frame) recover through
//  their own later triggers; TRANSIENT blocks (drag, restore/entry/
//  position writes, own clamp fence, live opening arm) hold the
//  request pending and retry, coalesced and deadline-bounded.
//  New file, new identity; kernel GorVideoFit 213cc504 UNCHANGED (its
//  value types are reused, its code is not touched).
//
//  Contract:
//   - clampedFrame works in the NATIVE AppKit space (origin = the
//     minimum-x/minimum-y corner); only min/max comparisons, so the
//     math is display-orientation agnostic. avail is the reference
//     screen's visibleFrame in the same space.
//   - A clamp SHRINKS (preserving the frame's aspect) only when the
//     frame exceeds the usable area on an axis, and TRANSLATES only
//     when the frame pokes out. It never grows, never recenters, and
//     returns nil when the frame is already inside: a clamp never
//     overrides a user action beyond the intended clamp.
//   - referenceScreenIndex picks the screen with the LARGEST
//     intersection with the window frame (F2: never NSScreen.main);
//     a fully offscreen window is pulled back to the first screen.
//   - shouldEvaluateClamp is the single guard predicate for the
//     feedback/reentrancy discipline: fullscreen, drag, restore/entry/
//     position writes in flight, our own clamp write in flight, and
//     opening-fit isolation all block the evaluation.
// ================================================================

enum GorWindowClamp {
    /// mpv's window minSize in FRAME units (pinned mpv v0.41.0
    /// window.swift:91 sets NSWindow.minSize; :361-365 rejects the
    /// FRAME below it) - a clamp never emits a frame below this.
    static let minFrameW: Double = 160
    static let minFrameH: Double = 90

    /// The clamped frame, or nil when the frame already fits (no-op) or
    /// cannot be represented safely (degenerate input, or the usable
    /// area is below the min frame - skip, never a silently dropped
    /// command).
    static func clampedFrame(_ frame: GorFitRect, in avail: GorFitRect,
                             minW: Double = minFrameW,
                             minH: Double = minFrameH) -> GorFitRect? {
        guard frame.w > 0, frame.h > 0, avail.w > 0, avail.h > 0 else { return nil }
        guard avail.w >= minW, avail.h >= minH else { return nil }
        var w = frame.w, h = frame.h
        if w > avail.w || h > avail.h {
            // Shrink-only, aspect preserved, one multiply per axis,
            // floored: a floored edge can never exceed the bound.
            let s = min(avail.w / w, avail.h / h)
            w = (w * s).rounded(.down)
            h = (h * s).rounded(.down)
            guard w >= minW, h >= minH else { return nil }
            guard w <= avail.w, h <= avail.h else { return nil }
        }
        var x = frame.x, y = frame.y
        if x < avail.x { x = avail.x }
        if y < avail.y { y = avail.y }
        if x + w > avail.x + avail.w { x = avail.x + avail.w - w }
        if y + h > avail.y + avail.h { y = avail.y + avail.h - h }
        if x == frame.x, y == frame.y, w == frame.w, h == frame.h { return nil }
        return GorFitRect(x: x, y: y, w: w, h: h)
    }

    /// The reference screen for a frame: the LARGEST intersection area
    /// with the window frame wins (F2: never NSScreen.main). Fully
    /// offscreen windows fall back to the first screen so the window is
    /// pulled back onto a visible area.
    static func referenceScreenIndex(for frame: GorFitRect,
                                     screens: [(frame: GorFitRect, avail: GorFitRect)]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var bestIdx: Int? = nil
        var bestArea = 0.0
        for (i, s) in screens.enumerated() {
            let iw = min(frame.x + frame.w, s.frame.x + s.frame.w) - max(frame.x, s.frame.x)
            let ih = min(frame.y + frame.h, s.frame.y + s.frame.h) - max(frame.y, s.frame.y)
            let area = max(0, iw) * max(0, ih)
            if area > bestArea { bestArea = area; bestIdx = i }
        }
        return bestIdx ?? 0
    }

    /// Usable-area snapshot diff for the poll trigger. Exact compare:
    /// visibleFrame origins/sizes are integral in practice, and a false
    /// positive only costs one in-bounds no-op evaluation.
    static func visibleFramesChanged(old: [GorFitRect], new: [GorFitRect]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) where a != b { return true }
        return false
    }

    /// AX-receipt classification: a frame change that reaches the
    /// receipt site with no gor geometry write in flight is EXTERNAL
    /// (user resize/move of the mpv window, or mpv-native movement).
    /// Our own clamp's receipt (fence up) and an in-flight opening fit
    /// are not user resizes.
    static func shouldTreatAsUserResize(clampWritePending: Bool,
                                        openingFitPending: Bool) -> Bool {
        !clampWritePending && !openingFitPending
    }

    /// Terminal blocks (v3): the evaluation is dropped, but every one of
    /// these states re-triggers through its own path when it clears
    /// (fullscreen exit / unminimize / first frame all land at the AX
    /// receipt or a later usable-area trigger). No retry needed.
    static func hasTerminalBlock(fullscreen: Bool?,
                                 minimized: Bool,
                                 frameValid: Bool) -> Bool {
        guard frameValid, !minimized else { return true }
        return fullscreen == true
    }

    /// Transient blocks (v3): gor geometry writes in flight, an active
    /// drag, the own-write fence, a live opening arm. These clear on
    /// their own within a short window, so a blocked evaluation stays
    /// PENDING and retries (deadline-bounded, coalesced - never a busy
    /// loop).
    static func hasTransientBlock(dragActive: Bool,
                                  restoreWritePending: Bool,
                                  entryWritePending: Bool,
                                  positionWriteInFlight: Bool,
                                  clampWritePending: Bool,
                                  openingFitPending: Bool) -> Bool {
        dragActive || restoreWritePending || entryWritePending
            || positionWriteInFlight || clampWritePending || openingFitPending
    }

    /// What a triggered evaluation should do (v3, reviewer F-1):
    /// evaluate now, stay pending and retry once more after the retry
    /// interval, or drop (terminal block, or the retry deadline passed).
    enum ClampAction {
        case evaluate, retry, drop
    }
    static func decideClampAction(terminal: Bool,
                                  transient: Bool,
                                  now: Double,
                                  retryUntil: Double) -> ClampAction {
        if terminal { return .drop }
        if transient { return now < retryUntil ? .retry : .drop }
        return .evaluate
    }

    /// The single guard predicate for a clamp evaluation. Everything
    /// that could fight the user, the opening fit, or an in-flight
    /// geometry write blocks the evaluation; an unknown fullscreen
    /// state (nil) does not (windowed is the steady state).
    static func shouldEvaluateClamp(fullscreen: Bool?,
                                    minimized: Bool,
                                    dragActive: Bool,
                                    restoreWritePending: Bool,
                                    entryWritePending: Bool,
                                    positionWriteInFlight: Bool,
                                    clampWritePending: Bool,
                                    openingFitPending: Bool,
                                    frameValid: Bool) -> Bool {
        if hasTerminalBlock(fullscreen: fullscreen, minimized: minimized,
                            frameValid: frameValid) { return false }
        if hasTransientBlock(dragActive: dragActive,
                             restoreWritePending: restoreWritePending,
                             entryWritePending: entryWritePending,
                             positionWriteInFlight: positionWriteInFlight,
                             clampWritePending: clampWritePending,
                             openingFitPending: openingFitPending) { return false }
        return true
    }
}

// gor 514 v5 candidate: completion-based own-write fence (pure, no AppKit).
// Fence lifetime follows the write's STATE, not a fixed 0.60 s: awaitingAck (IPC set_property
// issued, mpv reply with our request_id not yet seen) -> landing (mpv applied it, waiting for the
// receipt of the final frame) -> idle (landing receipt consumed). Time is only a safety timeout.
struct GorClampFence {
    enum Phase: Equatable { case idle, awaitingAck(seq: Int), landing }
    enum Verdict: Equatable { case own, user }
    private(set) var phase: Phase = .idle
    private(set) var seq = 0
    private var deadline = 0.0
    private var before = GorFitRect(x: 0, y: 0, w: 0, h: 0)
    private var expected = GorFitRect(x: 0, y: 0, w: 0, h: 0)
    private var chasedTarget = GorFitRect(x: 0, y: 0, w: 0, h: 0)
    private var chasedCount = 0
    static let maxIdenticalWrites = 3
    static let ackTimeout = 1.5, landingTimeout = 0.6, eps = 2.0

    var isUp: Bool { phase != .idle }

    /// mpv request_id for the geometry write of `seq` (own range, away from crop 9300..<9400 and the polls).
    /// Monotonic, never wraps in practice (a wrapped id could match a late reply to a NEWER write).
    static func requestId(_ seq: Int) -> Int { 1_000_000 + seq }
    static func ownsRequestId(_ id: Int) -> Bool { id >= 1_000_000 && id < 2_000_000 }

    /// Time-only safety net, independent of any receipt: with a static desktop no receipt may ever arrive, and the
    /// fence must not outlive its timeout (the TCv3-F1 class of defect). Called before every evaluation.
    /// Returns true when a write ended WITHOUT its requested frame ever landing (timeout in awaitingAck/landing): the
    /// final frame is then unproven (it may be a user resize that looked like our own on-path frame), so the caller
    /// re-evaluates the current frame instead of trusting the fence.
    @discardableResult
    mutating func expire(now: Double) -> Bool {
        guard phase != .idle, now >= deadline else { return false }
        phase = .idle
        return true
    }

    /// mpv refused the geometry write (error reply): nothing will land, release the fence.
    mutating func abort() { phase = .idle }

    /// State-based loop bound (not a time or iteration cap on distinct work): the SAME target written
    /// `maxIdenticalWrites` times without it ever landing means mpv/the OS keep refusing it. Stop chasing that
    /// exact target; a different target (the user moved the window again) or one landing resets it.
    func canWrite(expected e: GorFitRect) -> Bool {
        func same(_ a: GorFitRect, _ b: GorFitRect) -> Bool {
            abs(a.x-b.x) < Self.eps && abs(a.y-b.y) < Self.eps && abs(a.w-b.w) < Self.eps && abs(a.h-b.h) < Self.eps }
        return !(same(e, chasedTarget) && chasedCount >= Self.maxIdenticalWrites)
    }

    /// tracked == false: no request_id reply will ever come (connection down, untracked fallback), so the fence goes
    /// straight to `landing` with the SHORT timeout instead of waiting 1.5 s for an ack that cannot arrive.
    mutating func write(now: Double, before: GorFitRect, expected: GorFitRect, tracked: Bool = true) -> Int {
        func same(_ a: GorFitRect, _ b: GorFitRect) -> Bool {
            abs(a.x-b.x) < Self.eps && abs(a.y-b.y) < Self.eps && abs(a.w-b.w) < Self.eps && abs(a.h-b.h) < Self.eps }
        if same(expected, chasedTarget) { chasedCount += 1 } else { chasedTarget = expected; chasedCount = 1 }
        seq += 1
        if tracked { phase = .awaitingAck(seq: seq); deadline = now + Self.ackTimeout }
        else { phase = .landing; deadline = now + Self.landingTimeout }
        self.before = before; self.expected = expected
        return seq
    }
    /// mpv replied to our request_id (command executed). Stale acks (older seq) are ignored.
    mutating func ack(seq s: Int, now: Double) {
        guard case .awaitingAck(let cur) = phase, cur == s else { return }
        phase = .landing; deadline = now + Self.landingTimeout
    }
    /// `pointerDown`: the primary mouse button is held. gor's own geometry write is programmatic (no button held), so a
    /// receipt that is not exactly the requested frame while the button is down is the user dragging/resizing, even
    /// when it lies on the before->requested path (the case geometry alone cannot tell apart).
    mutating func classify(receipt r: GorFitRect, now: Double, pointerDown: Bool = false) -> Verdict {
        guard phase != .idle else { return .user }
        if now >= deadline { phase = .idle; return .user }
        func same(_ a: GorFitRect, _ b: GorFitRect) -> Bool {
            abs(a.x-b.x) < Self.eps && abs(a.y-b.y) < Self.eps && abs(a.w-b.w) < Self.eps && abs(a.h-b.h) < Self.eps }
        func btw(_ v: Double,_ a: Double,_ b: Double) -> Bool { v >= min(a,b)-Self.eps && v <= max(a,b)+Self.eps }
        let onPath = btw(r.x,before.x,expected.x) && btw(r.y,before.y,expected.y) && btw(r.w,before.w,expected.w) && btw(r.h,before.h,expected.h)
        if same(r, expected) {
            if phase == .landing { phase = .idle; chasedCount = 0 }   // landed: later receipts are user's
            return .own
        }
        if pointerDown { phase = .idle; return .user }
        if same(r, before) || onPath { return .own }
        phase = .idle; return .user
    }
}
