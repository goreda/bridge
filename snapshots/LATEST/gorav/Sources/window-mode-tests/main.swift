// G3 (arch-195l, dispatch L6) window-mode policy tests. Pure Swift, runs on
// Linux. One check() counter style like crop-tests / audio-delay-tests.
import Foundation
import GorAVPlaybackCore

var pass = 0, fail = 0
func check(_ cond: Bool, _ name: String) {
    if cond { pass += 1; print("PASS \(name)") }
    else { fail += 1; print("FAIL \(name)") }
}

let frame = WindowFrame(x: 200, y: 200, width: 640, height: 480)

// W1-W3: windowed -> fullscreen saves the restore frame and enters.
var s = WindowModeState()
let w1 = s.transition(to: .fullscreen, currentWindowedFrame: frame)
check({ if case .success(.enterFullscreen(let f)) = w1 { return f == frame } else { return false } }(),
      "W1 windowed->fullscreen returns enterFullscreen with the saved frame")
check(s.mode == .fullscreen, "W2 state advances to fullscreen")
check(s.windowedRestore == frame, "W3 restore frame recorded")

// W4-W5: fullscreen -> windowed restores.
let w4 = s.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .success(.exitFullscreen(let r)) = w4 { return r == frame } else { return false } }(),
      "W4 fullscreen->windowed returns exitFullscreen with the recorded frame")
check(s.mode == .windowed, "W5 state back to windowed")

// W6: same-mode request is a typed no-op refusal, state untouched.
var s6 = WindowModeState()
let w6 = s6.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .failure(.alreadyInMode(.windowed)) = w6 { return true } else { return false } }(),
      "W6 windowed->windowed refused as alreadyInMode")

// W7-W8: fullscreen <-> PiP direct hops are refused, state untouched.
var s7 = WindowModeState()
_ = s7.transition(to: .fullscreen, currentWindowedFrame: frame)
let w7 = s7.transition(to: .pictureInPicture, currentWindowedFrame: nil,
                       contentSize: (1920, 1080))
check({ if case .failure(.requiresWindowedFirst(.fullscreen, .pictureInPicture)) = w7 { return true } else { return false } }(),
      "W7 fullscreen->pip refused requiresWindowedFirst")
check(s7.mode == .fullscreen, "W8 state stays fullscreen after refusal")

// W9: PiP -> fullscreen refused the other way.
var s9 = WindowModeState()
_ = s9.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: (1920, 1080))
let w9 = s9.transition(to: .fullscreen, currentWindowedFrame: nil)
check({ if case .failure(.requiresWindowedFirst(.pictureInPicture, .fullscreen)) = w9 { return true } else { return false } }(),
      "W9 pip->fullscreen refused requiresWindowedFirst")

// W10-W12: windowed -> PiP fits 16:9 into the 480x270 box exactly.
var s10 = WindowModeState()
let w10 = s10.transition(to: .pictureInPicture, currentWindowedFrame: frame,
                         contentSize: (1920, 1080))
check({ if case .success(.enterPiP(let p, let f)) = w10 {
            return p.width == 480 && p.height == 270 && f == frame }
        else { return false } }(),
      "W10 16:9 content fits the 480x270 PiP box")
check(s10.mode == .pictureInPicture, "W11 state advances to pictureInPicture")
check(s10.windowedRestore == frame, "W12 restore frame recorded at PiP entry")

// W13: PiP -> windowed restores.
let w13 = s10.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .success(.exitPiP(let r)) = w13 { return r == frame } else { return false } }(),
      "W13 pip->windowed returns exitPiP with the recorded frame")

// W14: leaving windowed without a current frame is a typed refusal.
var s14 = WindowModeState()
let w14 = s14.transition(to: .fullscreen, currentWindowedFrame: nil)
check({ if case .failure(.noRestoreFrame) = w14 { return true } else { return false } }(),
      "W14 fullscreen without a current frame refused noRestoreFrame")

// W15: PiP entry without content size is a typed refusal.
var s15 = WindowModeState()
let w15 = s15.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: nil)
check({ if case .failure(.noRestoreFrame) = w15 { return true } else { return false } }(),
      "W15 pip without content size refused")

// W16: degenerate content size is a typed refusal, never a guessed size.
var s16 = WindowModeState()
let w16 = s16.transition(to: .pictureInPicture, currentWindowedFrame: frame,
                         contentSize: (0, 1080))
check({ if case .failure(.degenerateContentSize) = w16 { return true } else { return false } }(),
      "W16 zero-width content refused degenerateContentSize")

// W17: 4:3 content fits by height, width follows aspect.
if case .success(let p) = PipSize.fit(contentWidth: 1440, contentHeight: 1080) {
    check(p.height == 270 && abs(p.width - 360) < 0.01, "W17 4:3 content fits to 360x270")
} else { check(false, "W17 4:3 content fits to 360x270") }

// W18: content already at the box aspect fills the box exactly.
if case .success(let p) = PipSize.fit(contentWidth: 160, contentHeight: 90) {
    check(p.width == 480 && p.height == 270, "W18 box-aspect content fills the PiP box")
} else { check(false, "W18 box-aspect content fills the PiP box") }

// W19: very tall content is capped by height, narrow width, aspect kept
// (no minimum-width bump - it would either overflow the box or be
// unreachable under max-bounds scaling).
if case .success(let p) = PipSize.fit(contentWidth: 90, contentHeight: 1600) {
    let aspect = p.width / p.height
    check(p.height == 270 && abs(aspect - (90.0 / 1600.0)) < 0.01,
          "W19 tall content capped by height, aspect kept")
} else { check(false, "W19 tall content capped by height, aspect kept") }

// W20: non-finite content refused.
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: .nan, contentHeight: 100) {
    check(true, "W20 NaN content refused")
} else { check(false, "W20 NaN content refused") }

// W21: rounding is stable to 3 decimals (480.0 not 479.9999...).
if case .success(let p) = PipSize.fit(contentWidth: 1920, contentHeight: 1080) {
    check(p.width * 1000 == (p.width * 1000).rounded(), "W21 pip size rounded to 3 decimals")
} else { check(false, "W21 pip size rounded to 3 decimals") }

// ---- B-WINDOW group (P28): bounds/arithmetic hardening + state proofs ----

// W22-W25 (B001 nonfinite-max-width): non-finite max bounds refuse. NaN was
// already refused (control); infinite bounds previously slipped the >0
// guard, and both-infinite bounds returned an infinite size as success.
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1920, contentHeight: 1080, maxWidth: .infinity, maxHeight: .infinity) {
    check(true, "W22 infinite max bounds refused")
} else { check(false, "W22 infinite max bounds refused") }
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1920, contentHeight: 1080, maxWidth: .nan) {
    check(true, "W23 NaN max width refused (control)")
} else { check(false, "W23 NaN max width refused (control)") }
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1920, contentHeight: 1080, maxWidth: .infinity, maxHeight: 270) {
    check(true, "W24 single infinite bound refused")
} else { check(false, "W24 single infinite bound refused") }
if case .success(let p) = PipSize.fit(contentWidth: 1920, contentHeight: 1080, maxWidth: 320, maxHeight: 180) {
    check(p.width == 320 && p.height == 180, "W25 finite custom bounds size exactly (valid sizing unchanged)")
} else { check(false, "W25 finite custom bounds size exactly (valid sizing unchanged)") }

// W26-W28 (B002 extreme-content-arithmetic): finite greatest/subnormal
// content must not succeed with NaN/infinite (or rounded-to-zero) sizes.
// Both-subnormal content overflowed the fit ratio to infinity -> (inf, inf).
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: .leastNonzeroMagnitude, contentHeight: .leastNonzeroMagnitude) {
    check(true, "W26 subnormal content ratio overflow refused")
} else { check(false, "W26 subnormal content ratio overflow refused") }
if case .success(let p) = PipSize.fit(contentWidth: .greatestFiniteMagnitude, contentHeight: .greatestFiniteMagnitude) {
    check(p.width.isFinite && p.height.isFinite && p.width > 0 && p.height > 0 && p.width <= 480 && p.height <= 270,
          "W27 greatest-finite content still fits finite inside the box")
} else { check(false, "W27 greatest-finite content still fits finite inside the box") }
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: .greatestFiniteMagnitude, contentHeight: 1) {
    check(true, "W28 greatest-width extreme refused (height rounded to zero)")
} else { check(false, "W28 greatest-width extreme refused (height rounded to zero)") }

// W29-W30 (B003 subpixel-rounded-zero): a dimension rounding to zero is a
// typed refusal, not a zero-size window; a narrow but representable aspect
// still succeeds positive (no invented minimum-width bump).
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1, contentHeight: 1_000_000) {
    check(true, "W29 subpixel-rounded-zero width refused")
} else { check(false, "W29 subpixel-rounded-zero width refused") }
if case .success(let p) = PipSize.fit(contentWidth: 1, contentHeight: 1000) {
    check(p.width > 0 && p.height == 270, "W30 narrow representable aspect stays positive")
} else { check(false, "W30 narrow representable aspect stays positive") }

// W34 (QUAL_HUGE regression): huge finite custom bounds overflow the 3-decimal
// rounding multiply; a non-finite rounded dimension is degenerate, never a size.
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1920, contentHeight: 1080, maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude) {
    check(true, "W34 huge finite bounds rounding overflow refused")
} else { check(false, "W34 huge finite bounds rounding overflow refused") }

print("window-mode-tests: \(pass) PASS, \(fail) FAIL")
exit(fail == 0 ? 0 : 1)
