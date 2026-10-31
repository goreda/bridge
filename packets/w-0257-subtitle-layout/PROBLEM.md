# W-0257 - gorav subtitle layout coordinate space (Q5) adversarial venue

state: candidate (awaiting solver acceptance + reviewer blind failure-cases)
solver lab: 1nstinct
reviewer lab: in2tinct
source grant: owner 2026-10-27 (block 123a) - real product source excerpts may be posted when a W- needs them.
secret scan: clean (grepped for key-like strings and known key variable names; no credentials, no user data, no fonts, no licensed bytes).

## problem (what fails, for the user)
Subtitle overlay rects computed in drawable space are WRONG for the overlay seam, which is FRAME pixels: on any non-1:1 drawable/frame ratio (4K content in a window, letterboxed 2.4:1), subtitles would land offset or vanish. The decided M2 rule (block 168, Q5): layout output space = drawablePixels; producer metrics interpreted in the PlayRes reference frame; the seam carries Int frame pixels via AspectFit pull-IN with a receipt. A subtitle rect landing in the letterbox border is repositioned INTO the frame and REPORTED (never dropped, never silently moved); only a degenerate zero-size rect is nil (typed .outsideFrame at the caller). This unit needs adversarial edge-check and, if a defect is found, a fix inside this unit.

## reproducer (real source at named pins)
- SubtitleLayout.swift  sha256 1b8cc11047c38d3c4faee047b471991ea1524e18784080eaa015655390fda42f  (unit under review)
- AspectFit.swift      sha256 f677d4fa45f25af0ea127613524025507c62a5b02e9df7720305b6c4b3a17266  (dependency, L2 lane, stable)
- main.swift           sha256 4479c28a9b4508d6150ccec0f74e05da3866f7f4c38bad4c9359b9c1e4637a6d  (venue; rename from q5-main)
All attached to this packet. M2 candidate source state 4bb068cc; interface decision ref M2-INTERFACE-DECISION-2026-11-01 (coordinator, via Ops).
Run (Linux, Swift 5.10.1):  swiftc SubtitleLayout.swift AspectFit.swift main.swift -o q5tests && ./q5tests

## expected behaviour
6 lines "PASS <name>" then "ALL PASS 6/6", exit 0. Covered cases: PlayRes font scaling / missing-PlayRes declared default flagged / letterbox fit / inside-frame identity no-pull / letterbox pull-in with receipt (proposedY -100) / degenerate zero-size nil.

## exact call site and interface
Renderer overlay seam: SubtitleLayout.drawableToFrameRectWithReceipt(_:fit:frameW:frameH:) -> (rect: PixelRect, wasPulledIntoFrame, proposedX/Y/W/H)? consumed by the Metal presenter's overlay validation (frameW/H bounds check) and shader (uv*frameW/H sampling). AspectFit.fit supplies the letterbox mapping. Placement is a DECLARED DEFAULT (bottom-center, 5% margin) stated in receipts: ASS margins/alignment are not parsed (R2) and never invented.

## behaviour that must not change
- Pull-IN, never drop: any non-degenerate rect is composited inside the frame AND reported with its pre-clamp proposal.
- Int frame pixels at the seam; rounding: x/y floor, w/h toNearestOrAwayFromZero with min 1.
- Pure Swift; Linux-runnable; no Metal/AppKit imports; Sendable value types.
- AspectFit.fit semantics (letterbox, symmetric borders) unchanged.
- Any semantic change forced by an adversarial finding returns to Ops with evidence first; no silent rule edit.

## known edges to attack (from independent review)
- SubtitleLayout.scaleFontSize with drawableHeight <= 0 returns the UNSCALED size silently (no typed signal); confirm intended or propose typed refusal.
- SubtitleLayout.declaredDefaultRect fills scaledFontSize = 0 and usedDefaultPlayRes = false as placeholders; a consumer reading those from a placement decision gets wrong values. Confirm consumers cannot, or propose Optionals.
- Rect wider/taller than the frame; rect fully beyond the right/bottom border; negative-destination rects; extreme aspect ratios (e.g. 32:9 drawable, 1:1 frame).
- Enum case comment "candidate default, pending Q5 answer" is stale against the decided header - doc-only, confirm no behavioural meaning.

## acceptance test
The venue above must pass unmodified, PLUS the reviewer lab's blind failure cases (written before reading any fix): border-straddling rects on all four sides, sub-pixel rects, extreme ratios, degenerate fit (zero frame), receipt exactness (proposed values bit-exact). Neither lab approval is product acceptance; Ops lands after readback.
