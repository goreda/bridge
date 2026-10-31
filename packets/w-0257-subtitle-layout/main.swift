// Q5 coordinate-space venue tests (Linux, Swift 5.10.1): compile WITH
// SubtitleLayout.swift + AspectFit.swift; this file must be named main.swift.
// Recipe: swiftc SubtitleLayout.swift AspectFit.swift main.swift -o q5tests && ./q5tests
// Expected: 6 lines "PASS <name>", then "ALL PASS 6/6", exit 0.
import Foundation

var pass = 0, fail = 0
func expect(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { pass += 1; print("PASS \(name)") } else { fail += 1; print("FAIL \(name) \(detail)") }
}

// 1. font scaling from PlayRes reference: 40pt at PlayResY 288 on 1080-high drawable -> 150
let (s1, d1) = SubtitleLayout.scaleFontSize(40, playResY: 288, drawableHeight: 1080)
expect("font-scaled", s1 == 150.0 && d1 == false, "got \(s1) default=\(d1)")
// 2. missing PlayRes -> declared default 288, flagged
let (s2, d2) = SubtitleLayout.scaleFontSize(40, playResY: nil, drawableHeight: 1080)
expect("font-default-playres-flagged", s2 == 150.0 && d2 == true, "got \(s2) default=\(d2)")

// letterboxed fit: drawable 1920x1080, frame 1920x800 -> pixelRect (0,140,1920,800)
let fit = AspectFit.fit(drawableW: 1920, drawableH: 1080, frameW: 1920, frameH: 800)
expect("fit-letterbox", fit.pixelRect == PixelRect(x: 0, y: 140, w: 1920, h: 800), "got \(fit.pixelRect)")

// 4. rect fully inside frame: identity mapping, no pull
if let r = SubtitleLayout.drawableToFrameRectWithReceipt(OverlayRect(x: 100, y: 200, w: 300, h: 50), fit: fit, frameW: 1920, frameH: 800) {
    expect("inside-frame-no-pull", r.rect == PixelRect(x: 100, y: 60, w: 300, h: 50) && r.wasPulledIntoFrame == false, "got \(r)")
} else { expect("inside-frame-no-pull", false, "nil") }
// 5. rect in the letterbox border: PULLED INTO frame with receipt, never dropped/refused
if let r = SubtitleLayout.drawableToFrameRectWithReceipt(OverlayRect(x: 100, y: 40, w: 300, h: 50), fit: fit, frameW: 1920, frameH: 800) {
    expect("letterbox-pulled-in-with-receipt", r.rect.y == 0 && r.wasPulledIntoFrame == true && r.proposedY == -100.0, "got \(r)")
} else { expect("letterbox-pulled-in-with-receipt", false, "nil") }
// 6. degenerate zero-width rect: nil (caller typed-refuses .outsideFrame)
let deg = SubtitleLayout.drawableToFrameRectWithReceipt(OverlayRect(x: 100, y: 200, w: 0, h: 50), fit: fit, frameW: 1920, frameH: 800)
expect("degenerate-nil", deg == nil)

print(fail == 0 ? "ALL PASS \(pass)/6" : "FAILURES \(fail)/6")
exit(fail == 0 ? 0 : 1)
