import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - gor 514 portrait fit: video fit math, opening fit, real mpv crop
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

#if canImport(AppKit)
// ================================================================
//  GorOpeningFit - AppKit bridge for the gor 514 opening-fit rule
//  Owns: NSScreen.visibleFrame -> GorVideoFit kernel space (points) ->
//  an absolute mpv geometry string (DEVICE PIXELS, content-relative).
//
//  STATUS: NEW wiring candidate (2026-11-01 v5), static review only.
//  New file, new identity; NOT the lost GorFitCapability (dd891a23).
//
//  v5 semantics, verified against PINNED mpv v0.41.0 backend source
//  (peer v3-blockers, resolved by source, not assumption):
//   - window.swift:76 creates the mpv window with styleMask
//     [.titled, .closable, .miniaturizable, .resizable]; the border
//     option only hides the title-bar overlay (window.swift:55-57),
//     the titled mask is dropped only in fullscreen (window.swift:240-
//     243, and our apply path skips fullscreen windows). So the actual
//     chrome is the TITLED-mask delta, MEASURED via
//     NSWindow.frameRect(forContentRect:styleMask:) - not a constant.
//   - common.swift:412-441 (getWindowGeometry): the geometry is computed
//     in BACKING (device-pixel) coordinates against the targetFrame,
//     which defaults to visibleFrame (app_bridge.m:65-66,
//     app_bridge.h:26-29 FRAME_VISIBLE=0), y origin flipped to top-left.
//   - window.swift:343-353 (updateFrame): the resulting rect is applied
//     via frameRect(forContentRect:) - geometry X/Y reference the
//     CONTENT rect; the title bar extends chromeTop ABOVE it.
//   - win_state.c:100-108: dpi_scale applies only to the DEFAULT size
//     (and only when hidpi-window-scale); win_state.c:129-130 applies
//     EXPLICIT --geometry W/H/X/Y as absolute values in the same
//     (device-pixel) space. So gor must emit all four numbers in device
//     pixels: points x screen.backingScaleFactor, FLOORED to the device
//     pixel (floor can never push a size or an edge past the both-axis
//     bound; nearest-rounding could, by a fraction of a point).
//   - Installed mpv version/backend drift remains a kit-time unknown.
//
//  Kernel space: avail origin (0,0), y DOWN from the top of the usable
//  area; the pure point math stays in GorVideoFit (unchanged 213cc504).
// ================================================================


enum GorOpeningFit {
    /// "usableW,usableH,backingScale,chromeW,chromeTop" for gor-fit.lua (points; visibleFrame of the screen).
    static func fitMetricsString(screen: NSScreen?, separator: String) -> String? {
        guard let screen else { return nil }
        let vf = screen.visibleFrame
        let probe = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                       styleMask: mpvWindowMask)
        let parts = [vf.width, vf.height, screen.backingScaleFactor, probe.width - 100, probe.height - 100]
        guard parts.allSatisfy({ $0.isFinite && $0 >= 0 }), vf.width >= 2, vf.height >= 2 else { return nil }
        return parts.map { String(format: "%.3f", $0) }.joined(separator: separator)
    }
    /// Launch-time metrics as a script-opt suffix (";" separated: "," separates script-opts). Empty when the
    /// script is not installed or no screen is known.
    static func fitScriptOptSuffix() -> String {
        guard PPController.gorFitScriptActive,
              let v = fitMetricsString(screen: NSScreen.main, separator: ";") else { return "" }
        return ",gor_fit-metrics=" + v
    }
    /// The actual mpv window style mask per pinned v0.41.0 window.swift:76.
    static let mpvWindowMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    /// Absolute mpv geometry for the one-shot opening fit, or nil when
    /// there is nothing safe to apply (no screen, degenerate inputs, or
    /// a kernel refusal - refusals are never silently floored).
    static func openingGeometry(videoW: Double, videoH: Double,
                                screen: NSScreen?,
                                floorFraction: Double,
                                chromeStyleMask: NSWindow.StyleMask = mpvWindowMask) -> String? {
        guard let screen, videoW > 0, videoH > 0, floorFraction > 0 else { return nil }
        let vf = screen.visibleFrame
        guard vf.width >= 2, vf.height >= 2 else { return nil }
        let scale = screen.backingScaleFactor
        guard scale >= 1 else { return nil }

        // Actual chrome delta for the mask, measured through the owning
        // API. Titled adds its bar above the content (top edge, top-down);
        // side/bottom chrome is zero on macOS.
        let probeContent = NSRect(x: 0, y: 0, width: 100, height: 100)
        let probeFrame = NSWindow.frameRect(forContentRect: probeContent,
                                            styleMask: chromeStyleMask)
        let chromeW = probeFrame.width - probeContent.width
        let chromeTop = probeFrame.height - probeContent.height
        guard chromeW >= 0, chromeTop >= 0 else { return nil }

        // The "scaled" half: resolution-sensitive CONTENT proposal (points).
        let proposal = GorVideoFit.proposedOpenSize(videoW: videoW, videoH: videoH,
                                                    screenW: vf.width,
                                                    floorFraction: floorFraction)
        guard proposal.w >= 1, proposal.h >= 1 else { return nil }

        // The "shrunk" half: fit the FRAME (content + chrome) inside the
        // usable frame on BOTH axes (shrink-only, centered, points), then
        // derive the content size from the fitted frame. A shrunk frame
        // distorts content aspect by at most chromeTop points.
        let frameProposal = GorFitSize(w: proposal.w + chromeW,
                                       h: proposal.h + chromeTop)
        let fitted = GorVideoFit.fit(video: frameProposal,
                                     avail: GorFitRect(x: 0, y: 0,
                                                       w: vf.width, h: vf.height))
        let contentW = fitted.w - chromeW
        let contentH = fitted.h - chromeTop
        guard fitted.w >= 1, fitted.h >= 1, contentW >= 1, contentH >= 1 else { return nil }

        // mpv X/Y reference the CONTENT top-left, relative to the
        // visibleFrame top-left, in DEVICE pixels (source refs above):
        // the frame sits at fitted.(x,y), the content chromeTop lower.
        // Emission FLOORS (peer evidence 2026-11-01): a floored size can
        // never exceed the both-axis bound, and floored origins keep the
        // whole frame inside it; nearest-rounding could push an edge out
        // by a fraction of a point.
        let xC = fitted.x
        let yC = fitted.y + chromeTop
        let W = Int((contentW * scale).rounded(.down))
        let H = Int((contentH * scale).rounded(.down))
        let X = Int((xC * scale).rounded(.down))
        let Y = Int((yC * scale).rounded(.down))
        // mpv silently REJECTS a setFrame whose FRAME is below minSize
        // 160x90 (window.swift:91 sets NSWindow.minSize; window.swift:361-
        // 365 compares the FRAME rect passed to setFrame). Our geometry
        // references the CONTENT rect; mpv adds the chrome to form the
        // frame it checks, so the aligned refusal threshold is the
        // FITTED FRAME: refuse below 160x90 in either axis instead of
        // firing a geometry command that would be dropped silently.
        guard W >= 1, H >= 1 else { return nil }
        guard fitted.w >= 160, fitted.h >= 90 else { return nil }
        return String(format: "%dx%d+%d+%d", W, H, X, Y)
    }

    /// gor 514 trigger/clamp unit (candidate v1): convert an ALREADY
    /// CLAMPED window frame (points, AppKit space; the pure clamp math
    /// lives in GorWindowClamp) into an absolute mpv geometry with the
    /// same pinned v0.41.0 conventions as the opening fit above:
    /// chrome measured via frameRect(forContentRect:styleMask:), X/Y
    /// relative to the visibleFrame top-left referencing the CONTENT
    /// rect, all four values floored device pixels, FRAME-threshold
    /// minSize refusal (window.swift:91/:361-365).
    static func clampGeometry(frame: NSRect,
                              screen: NSScreen?,
                              chromeStyleMask: NSWindow.StyleMask = mpvWindowMask) -> String? {
        guard let screen, frame.width > 0, frame.height > 0 else { return nil }
        let vf = screen.visibleFrame
        guard vf.width >= 2, vf.height >= 2 else { return nil }
        let scale = screen.backingScaleFactor
        guard scale >= 1 else { return nil }

        // Same measured chrome delta as the opening fit.
        let probeContent = NSRect(x: 0, y: 0, width: 100, height: 100)
        let probeFrame = NSWindow.frameRect(forContentRect: probeContent,
                                            styleMask: chromeStyleMask)
        let chromeW = probeFrame.width - probeContent.width
        let chromeTop = probeFrame.height - probeContent.height
        guard chromeW >= 0, chromeTop >= 0 else { return nil }

        let contentW = frame.width - chromeW
        let contentH = frame.height - chromeTop
        guard contentW >= 1, contentH >= 1 else { return nil }
        // Geometry X/Y reference the CONTENT top-left relative to the
        // visibleFrame top-left. AppKit y-up: the content's top edge is
        // chromeTop BELOW the frame's top edge, so its distance from the
        // visibleFrame top is vf.maxY - frame.maxY + chromeTop.
        let xC = frame.minX - vf.minX
        let yC = vf.maxY - frame.maxY + chromeTop
        let W = Int((contentW * scale).rounded(.down))
        let H = Int((contentH * scale).rounded(.down))
        let X = Int((xC * scale).rounded(.down))
        let Y = Int((yC * scale).rounded(.down))
        guard W >= 1, H >= 1 else { return nil }
        guard frame.width >= 160, frame.height >= 90 else { return nil }
        // The extra '+' is intentional: mpv parses '+-24' as absolute -24 from the top/left.
        // Bare '-24' is a DIFFERENT instruction: anchor 24px from the bottom/right.
        // This matters when the auto-hidden menu permits a frame above visibleFrame.maxY.
        return String(format: "%dx%d+%d+%d", W, H, X, Y)
    }
}


#endif

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
        // Keep every pixel touched by the detected content rect. Origins round OUT,
        // far edges round OUT; nearest/even width rounding can cut one real picture column.
        guard [fx,fy,fw,fh,videoW,videoH].allSatisfy({$0.isFinite}) else {return nil}
        func evenDown(_ v: Double) -> Int {max(0,Int((v / 2).rounded(.down))*2)}
        func evenUp(_ v: Double) -> Int {max(0,Int((v / 2).rounded(.up))*2)}
        let vw = Int(videoW.rounded(.down)), vh = Int(videoH.rounded(.down))
        let x = evenDown(fx*videoW), y = evenDown(fy*videoH)
        let right = evenUp((fx+fw)*videoW), bottom = evenUp((fy+fh)*videoH)
        // Odd coded bounds cannot be kept AND even-aligned without clipping. Refuse rather than cut.
        guard right <= vw, bottom <= vh else {return nil}
        let w = right-x, h = bottom-y
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

    /// Manual intent geometry only. Eligibility is checked again from live video-params
    /// by the transaction owner; no UI masking is applied from this proposal.
    static func centeredManualRequest(aspectW: Double, aspectH: Double,
                                      displayW: Double, displayH: Double) -> GorCropRequest? {
        guard [aspectW, aspectH, displayW, displayH].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let target = aspectW / aspectH, source = displayW / displayH
        guard target.isFinite, source.isFinite, target > 0, source > 0 else { return nil }
        let w = min(1, target / source), h = min(1, source / target)
        return GorCropRequest(fx: (1-w)/2, fy: (1-h)/2, fw: w, fh: h)
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
    /// P4 (card 713): the id minted by the latest resetForNewFile removal.
    /// That removal stays fire-and-forget for this state machine by design;
    /// the id is exposed read-only so the controller can correlate its reply.
    private(set) var lastResetRemovalId: Int? = nil
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

    /// A new file owns its own opening geometry. Retire every old crop transaction;
    /// the idempotent removal reply must never refit the new film to an old window.
    mutating func resetForNewFile() -> [Action] {
        pendingRequest = nil
        pendingClear = false
        phase = .idle
        let id = mint()
        lastResetRemovalId = id
        return [.overlayIdentity(false), .send(GorCropPlan.removeCommand(id: id))]
    }

    /// Revert / reset: remove our filter (idempotent at mpv: removing a missing label succeeds).
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

// MARK: - gor 514 portrait fit: window clamp + ack/landing fence
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
enum GorGeometryOutcome {case landed,alreadyEqual,rejected,unproven,userTakeover,superseded}
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

#if canImport(AppKit)
extension AppDelegate {
    // MARK: - gor 514 trigger/clamp (candidate v4, static review only)

    /// Usable-area triggers, grounded coverage (v2):
    /// - didChangeScreenParametersNotification: documented for display
    ///   (dis)connect/mode changes (Apple doc); Dock POSITION changes
    ///   reportedly fire it too, Dock SIZE changes have documented
    ///   NON-firing evidence (OpenJDK 8072069 review, 2015), so the
    ///   notification is NOT trusted as complete.
    /// - Snapshot poll (2s, cheap NSScreen reads, no AX): the catch-all
    ///   for Dock size/menu-bar/any visibleFrame drift; Apple
    ///   explicitly says visibleFrame must not be cached because it can
    ///   change between calls.
    /// Both feed the same debounced evaluation.
    func installWindowClampTrigger() {
        lastKnownVisibleFrames = NSScreen.screens.map {
            GorFitRect(x: $0.visibleFrame.origin.x, y: $0.visibleFrame.origin.y,
                       w: $0.visibleFrame.width, h: $0.visibleFrame.height)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.controller?.pushFitMetrics()
            self?.scheduleWindowClampEvaluation()
        }
        // The mpv window moved to another display: refresh the metrics the next open will be sized from.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.controller?.pushFitMetrics()
        }
        let poll = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = NSScreen.screens.map {
                GorFitRect(x: $0.visibleFrame.origin.x, y: $0.visibleFrame.origin.y,
                           w: $0.visibleFrame.width, h: $0.visibleFrame.height)
            }
            if GorWindowClamp.visibleFramesChanged(old: self.lastKnownVisibleFrames,
                                                   new: current) {
                self.lastKnownVisibleFrames = current
                self.scheduleWindowClampEvaluation()
            }
        }
        poll.tolerance = 0.5
        RunLoop.main.add(poll, forMode: .common)
        windowClampPollTimer = poll
    }

    /// gor 514 v2/v3 user-resize trigger: called from the syncOverlay AX
    /// receipt site (which already excludes every gor geometry write via
    /// the drag/position/restore/entry fences) and from the
    /// write-completion receipt (overlay-drag position, fullscreen
    /// restore - the FINAL frame after gor's own write clears). A frame
    /// change arriving with no clamp/opening write in flight is treated
    /// as a user resize/move of the mpv window. Sharing the 0.40s
    /// debounce gives resize-END semantics: a live drag keeps deferring,
    /// the clamp evaluates only the final frame (no mid-drag fighting).
    func noteExternalWindowFrameChange() {
        if cropGeometryCompletion != nil,
           classifyCropGeometryOutcome(frame:lastFrame,now:ProcessInfo.processInfo.systemUptime,pointerDown:(NSEvent.pressedMouseButtons & 1) != 0) {return}
        if controller?.cropGeometryTransitionActive == true {
            if (NSEvent.pressedMouseButtons & 1) != 0 {controller?.cancelFitAnimation()}
            else {return}
        }
        // v4 (peer TCv3-F1): the own-write fence must release HERE, not
        // only inside evaluateWindowClamp. Our own clamp's AX receipt is
        // suppressed and schedules nothing, so on a static desktop an
        // expired fence would otherwise suppress every LATER user resize
        // until an unrelated screen/Dock trigger. Releasing the expired
        // fence before classification keeps the 0.60s own-receipt
        // suppression intact while never outliving the settle window.
        if clampFence.isUp {
            let r = lastFrame
            let verdict = clampFence.classify(
                receipt: GorFitRect(x: r.origin.x, y: r.origin.y, w: r.width, h: r.height),
                now: ProcessInfo.processInfo.systemUptime,
                pointerDown: (NSEvent.pressedMouseButtons & 1) != 0)
            // Our own write's receipt (requested frame, pre-write frame, or a frame on the path between)
            // schedules nothing: the feedback bound is unchanged. Anything else released the fence and
            // is classified as the user's resize below.
            if verdict == .own { return }
        }
        guard GorWindowClamp.shouldTreatAsUserResize(
            clampWritePending: windowClampWritePending,
            openingFitPending: controller?.openingFitPending ?? false
        ) else { return }
        controller?.noteUserWindowGeometry(frame: lastFrame)
        scheduleWindowClampEvaluation()
    }

    /// Every trigger (usable-area change, user-resize receipt) re-arms
    /// the pending request and its retry deadline, then coalesces
    /// through the single debounced work item.
    func scheduleWindowClampEvaluation(delay: TimeInterval = 0.40,
                                               rearmDeadline: Bool = true) {
        if rearmDeadline {
            windowClampRetryUntil = ProcessInfo.processInfo.systemUptime
                + Self.windowClampRetryBudget
        }
        windowClampWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.evaluateWindowClamp() }
        windowClampWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Re-evaluate the EXISTING window against the current usable area
    /// and clamp it back inside on BOTH axes (shrink preserves aspect,
    /// translate only when poking out; never grows, never recenters, and
    /// an in-bounds window is untouched). Runs on usable-area changes
    /// AND on user resize/move end (resize-end debounce). Opening-fit
    /// state is never touched, and a live opening arm skips the clamp
    /// entirely (the opening fit already bounds both axes). Reentrancy:
    /// our own geometry write cannot retrigger the notification, its AX
    /// receipt is fenced out of the user-resize classification, and the
    /// write fence + settle window suppress overlapping evaluations.
    /// Aspect during a USER resize is mpv's own keepAspect
    /// (window.swift:368); the clamp never breaks aspect when it
    /// shrinks. Consequence of the accepted scope: a window
    /// deliberately parked partially offscreen is pulled in-bounds at
    /// resize end.
    func evaluateWindowClamp() {
        let now = ProcessInfo.processInfo.systemUptime
        if clampFence.expire(now: now) {
            finishCropGeometryOutcome(seq:clampFence.seq,outcome:.unproven)
        }
        let screenList = NSScreen.screens
        let gscreens = screenList.map {
            (frame: GorFitRect(x: $0.frame.origin.x, y: $0.frame.origin.y,
                               w: $0.frame.width, h: $0.frame.height),
             avail: GorFitRect(x: (pictureInPictureActive ? $0.frame : $0.visibleFrame).origin.x, y: (pictureInPictureActive ? $0.frame : $0.visibleFrame).origin.y,
                               w: (pictureInPictureActive ? $0.frame : $0.visibleFrame).width, h: (pictureInPictureActive ? $0.frame : $0.visibleFrame).height))
        }
        let frame = lastFrame
        let terminal = GorWindowClamp.hasTerminalBlock(
            fullscreen: playerFullscreenState, minimized: false,
            frameValid: !frame.isEmpty)
        let transient = GorWindowClamp.hasTransientBlock(
            dragActive: overlayDragActive,
            restoreWritePending: mpvRestoreWritePending || windowGeometryTransitionActive || (controller?.cropGeometryTransitionActive ?? false),
            entryWritePending: mpvEntryWritePending,
            positionWriteInFlight: overlayPositionWriteInFlight,
            clampWritePending: windowClampWritePending,
            openingFitPending: controller?.openingFitPending ?? false)
        // v3 (reviewer F-1): no lost events. A transiently blocked
        // evaluation RETRIES (coalesced, deadline-bounded - about ten
        // 0.5s retries inside a 5s budget, never a busy loop); a
        // terminal block drops because its clearing re-triggers on its
        // own (fullscreen exit / first frame land at the AX receipt).
        switch GorWindowClamp.decideClampAction(terminal: terminal,
                                                transient: transient,
                                                now: now,
                                                retryUntil: windowClampRetryUntil) {
        case .drop:
            return
        case .retry:
            scheduleWindowClampEvaluation(delay: Self.windowClampRetryInterval,
                                          rearmDeadline: false)
            return
        case .evaluate:
            break
        }
        let gframe = GorFitRect(x: frame.origin.x, y: frame.origin.y,
                                w: frame.width, h: frame.height)
        guard let refIdx = GorWindowClamp.referenceScreenIndex(for: gframe, screens: gscreens),
              let clamped = GorWindowClamp.clampedFrame(gframe, in: gscreens[refIdx].avail) else {
            return  // in-bounds: no-op, user action untouched
        }
        let target = NSRect(x: clamped.x, y: clamped.y, width: clamped.w, height: clamped.h)
        guard let geom = GorOpeningFit.clampGeometry(frame: target,
                                                     screen: screenList[refIdx], chromeStyleMask: pictureInPictureActive ? .borderless : GorOpeningFit.mpvWindowMask) else { return }
        let gtarget = GorFitRect(x: target.origin.x, y: target.origin.y, w: target.width, h: target.height)
        guard clampFence.canWrite(expected: gtarget) else {
            print("[clamp] same target refused \(GorClampFence.maxIdenticalWrites)x - not chasing it")
            return
        }
        issueFencedGeometry(geom, before: frame, target: target, now: now)
    }

    /// The ONE place a gor-initiated window geometry write is issued (clamp and crop refit): arms the fence with
    /// the pre-write and requested frames, sends through the tracked path when the connection is up, otherwise
    /// the untracked fallback (fence then goes straight to landing with the short timeout, no ack is awaited).
    /// A deadline check re-evaluates the frame if the requested frame never provably landed.
    func finishCropGeometryOutcome(seq:Int,outcome:GorGeometryOutcome) {
        guard let pending=cropGeometryCompletion,pending.seq==seq else{return}
        cropGeometryCompletion=nil
        pending.callback(outcome)
    }
    @discardableResult
    func classifyCropGeometryOutcome(frame:NSRect,now:Double,pointerDown:Bool)->Bool {
        guard let pending=cropGeometryCompletion else{return false}
        if clampFence.expire(now:now) {
            finishCropGeometryOutcome(seq:pending.seq,outcome:.unproven)
            return false
        }
        let verdict=clampFence.classify(receipt:GorFitRect(x:frame.minX,y:frame.minY,w:frame.width,h:frame.height),now:now,pointerDown:pointerDown)
        if verdict == .user {finishCropGeometryOutcome(seq:pending.seq,outcome:.userTakeover);return false}
        if !clampFence.isUp {finishCropGeometryOutcome(seq:pending.seq,outcome:.landed)}
        return true
    }
    func issueFencedGeometry(_ geom: String, before: NSRect, target: NSRect,
                             now: TimeInterval = ProcessInfo.processInfo.systemUptime,
                             completion:((GorGeometryOutcome)->Void)?=nil) {
        // All callers (including clamp/Window menu) share the native transition fence.
        guard !windowGeometryTransitionActive else {completion?(.superseded);return}
        if let old=cropGeometryCompletion {finishCropGeometryOutcome(seq:old.seq,outcome:.superseded)}
        let gb = GorFitRect(x: before.origin.x, y: before.origin.y, w: before.width, h: before.height)
        let gt = GorFitRect(x: target.origin.x, y: target.origin.y, w: target.width, h: target.height)
        // Connection state is read first so the fence phase matches what was actually sent.
        let tracked = controller?.persistentConnectionUp ?? false
        let seq = clampFence.write(now: now, before: gb, expected: gt, tracked: tracked)
        if let completion {cropGeometryCompletion=(seq,completion)}
        if !(tracked && controller?.sendTrackedGeometry(geom, requestId: GorClampFence.requestId(seq)) == true) {
            controller?.sendGeometryUntracked(geom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + GorClampFence.ackTimeout + GorClampFence.landingTimeout + 0.1) { [weak self] in
            guard let self else { return }
            guard self.clampFence.seq==seq else{return}
            if self.clampFence.expire(now: ProcessInfo.processInfo.systemUptime) {
                self.finishCropGeometryOutcome(seq:seq,outcome:.unproven)
                self.scheduleWindowClampEvaluation()   // landing unproven (e.g. on-path user resize): re-check
            }
        }
    }

    /// mpv's reply to our tracked geometry write (routed from PPController). A stale id is ignored.
    func noteClampGeometryReply(id: Int, ok: Bool) {
        guard GorClampFence.requestId(clampFence.seq) == id else { return }
        if ok {
            clampFence.ack(seq: clampFence.seq, now: ProcessInfo.processInfo.systemUptime)
        } else {
            clampFence.abort()
            finishCropGeometryOutcome(seq:clampFence.seq,outcome:.rejected)
            scheduleWindowClampEvaluation()   // the write did not happen: re-evaluate instead of losing it
        }
    }

}
#endif
