import Foundation

/// 191k/17:33: placement measurements for the sidebar-V 3D corner controls. Compiles the PRODUCTION
/// layout (ThreeDCornerTuneLayout.swift) - no mirror. Any drift between what the view renders and
/// these corner/diagonal rules fails here. Owner 17:33 (phonemsg-01M72Y1GHHQT93RMMN87H3JZJZ),
/// English paraphrase: clickable cells, subs removed, word in the corner, value beside it, +/-
/// marching diagonally inward. Owner 22:28 (phonemsg-01M73EX09GEDHCQQ5V1YMJ5K8Y): single-letter
/// titles with a hover typewriter. Owner 2026-11-12 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q),
/// English paraphrase: title outer edge a fixed pad distance from the spine/sidebar; one shared
/// value column reserved from the longest
/// title ("depth"); depth/size pinned at the right edge, expanding left; the 3D dropdown row sits
/// directly under V. Owner 2026-11-12 13:47 (phonemsg-01M77NX7459XYMH8W2B3VR9N01): every pad x 2
/// gap drops to pad x 1 (the title-value air halved), and the scr cells are left/right arrows
/// (near "→" = screen farther, far "←" = screen nearer). This file pins that pad grid and
/// supersedes the 22:23-22:26 mockup pixel-token measurements.
var failures = 0
func eq(_ a: Double, _ b: Double) -> Bool { (a - b).magnitude < 1e-6 }
func eq(_ a: CornerTuneRect, _ b: CornerTuneRect) -> Bool { eq(a.x, b.x) && eq(a.y, b.y) && eq(a.w, b.w) && eq(a.h, b.h) }
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

let L = CornerTuneLayout(charW: 8, lineH: 16, pad: 12)
let content = CornerTuneRect(x: 0, y: 0, w: 2048, h: 1152)
let values: [String: String] = ["strength": "1", "ipd": "+0.0", "screenDepth": "1.5m", "screenSize": "80°"]

let controls = L.controls(in: content, subtitleBand: nil, values: values)
check("four-controls-subs-removed", controls.count == 4 && !controls.contains { $0.word == "subs" })
func ctl(_ word: String) -> CornerTuneControl { controls.first { $0.word == word }! }

// Owner 22:28: single-letter titles i/s/d/s with the full word kept for the hover typewriter.
check("letters-i-s-d-s", ctl("ipd").letter == "i" && ctl("scr").letter == "s" && ctl("depth").letter == "d" && ctl("size").letter == "s")
check("title-cells-one-char", controls.allSatisfy { $0.wordFrame.w == 8 })

// Corner anchoring (owner 2026-11-12 12:40, halved 13:47): title outer edge at the cleared
// content edge (clearContent's pad is the one pad to the spine/sidebar edge), pair row box
// rowPadLines from the edge. Fixture: charW 8, lineH 16, pad 12.
let m = CornerTuneLayout.titleMarginPads * 12, rowPad = CornerTuneLayout.rowPadLines * 16
let gap = CornerTuneLayout.gridGapPads * 12
let reserve = Double(CornerTuneLayout.titleReserveChars) * 8
check("ipd-top-left", ctl("ipd").corner == .topLeft && ctl("ipd").wordFrame.x == m && ctl("ipd").wordFrame.maxY == 1152 - rowPad)
check("depth-top-right", ctl("depth").corner == .topRight && ctl("depth").wordFrame.maxX == 2048 - m && ctl("depth").wordFrame.maxY == 1152 - rowPad)
check("scr-bottom-left", ctl("scr").corner == .bottomLeft && ctl("scr").wordFrame.x == m && ctl("scr").wordFrame.y == rowPad)
check("size-bottom-right", ctl("size").corner == .bottomRight && ctl("size").wordFrame.maxX == 2048 - m && ctl("size").wordFrame.y == rowPad)

// Value field starts pad x 1 after the reserved title column (13:47), same row as the title. The column
// is ONE shared column reserved from the longest title ("depth"), so every row's value starts at
// the same x and the grid never breaks (owner 2026-11-12 12:40).
let vx = m + reserve + gap   // value's title-side edge, measured from the corner side
check("ipd-value-column", eq(ctl("ipd").valueFrame.x, vx) && eq(ctl("ipd").valueFrame.y, ctl("ipd").wordFrame.y))
check("size-value-column", eq(ctl("size").valueFrame.maxX, 2048 - vx) && eq(ctl("size").valueFrame.y, ctl("size").wordFrame.y))
for c in controls {
    let leftSide = c.corner == .topLeft || c.corner == .bottomLeft
    check("\(c.word)-shared-value-column", leftSide ? eq(c.valueFrame.x, vx) : eq(c.valueFrame.maxX, 2048 - vx))
}
// Every gap in the chain title | value | near cell | far cell is pad x 1 edge-to-edge (13:47).
for c in controls {
    let leftSide = c.corner == .topLeft || c.corner == .bottomLeft
    if leftSide {
        check("\(c.word)-padx1-gaps", eq(c.valueFrame.x, c.wordFrame.x + reserve + gap)
            && eq(c.cellB.x, c.valueFrame.maxX + gap) && eq(c.cellA.x, c.cellB.maxX + gap))
    } else {
        check("\(c.word)-padx1-gaps", eq(c.valueFrame.maxX, c.wordFrame.maxX - reserve - gap)
            && eq(c.cellB.maxX, c.valueFrame.x - gap) && eq(c.cellA.maxX, c.cellB.x - gap))
    }
}

// Cells march diagonally inward after the value field; near = stronger (+), far = weaker, each
// step one line tall.
let ipd = ctl("ipd")
check("ipd-diagonal", eq(ipd.cellB.x, ipd.valueFrame.maxX + gap) && eq(ipd.cellB.y, ipd.wordFrame.y - 16)
    && eq(ipd.cellA.x, ipd.cellB.maxX + gap) && eq(ipd.cellA.y, ipd.wordFrame.y - 32)
    && ipd.glyphB == "+" && ipd.glyphA == "-")
let size = ctl("size")
check("size-diagonal-mirrored", eq(size.cellB.maxX, size.valueFrame.x - gap) && eq(size.cellB.y, size.wordFrame.y + 16)
    && eq(size.cellA.maxX, size.cellB.x - gap) && eq(size.cellA.y, size.wordFrame.y + 32))
// Bottom-right reads "- + 80° s" left to right (far cell, near cell, value, title).
check("size-reads-dash-plus-value-letter", size.cellA.maxX <= size.cellB.x && size.cellB.maxX <= size.valueFrame.x && size.valueFrame.maxX < size.wordFrame.x
    && size.glyphA == "-" && size.glyphB == "+" && size.value == "80°" && size.letter == "s")
let scr = ctl("scr")
check("scr-diagonal-up", eq(scr.cellB.x, scr.valueFrame.maxX + gap) && eq(scr.cellB.y, scr.wordFrame.y + 16)
    && eq(scr.cellA.x, scr.cellB.maxX + gap) && eq(scr.cellA.y, scr.wordFrame.y + 32)
    && scr.glyphB == "→" && scr.glyphA == "←")

// Every element inside the content rect; cells are single one-char frames, disjoint, hit-consistent.
for c in controls {
    for f in c.frames {
        check("\(c.word)-inside", f.x >= 0 && f.maxX <= 2048 && f.y >= 0 && f.maxY <= 1152)
    }
    check("\(c.word)-cells-one-char", c.cellA.w == 8 && c.cellB.w == 8 && c.cellA.h == 16 && c.cellB.h == 16)
    check("\(c.word)-cells-disjoint", !c.cellA.intersects(c.cellB))
    check("\(c.word)-cell-hit", c.cellA.contains(c.cellA.x + 4, c.cellA.y + 8) && !c.cellB.contains(c.cellA.x + 4, c.cellA.y + 8))
}
// The four corners are exact mirrors of each other (22:23: symmetry mathematically, not by eye).
func mirroredX(_ f: CornerTuneRect, _ w: Double) -> CornerTuneRect { CornerTuneRect(x: w - f.maxX, y: f.y, w: f.w, h: f.h) }
func mirroredY(_ f: CornerTuneRect, _ h: Double) -> CornerTuneRect { CornerTuneRect(x: f.x, y: h - f.maxY, w: f.w, h: f.h) }
// Frames mirror exactly except the value FIELD (fixed per-key width): the shared column pins its
// title-side edge, so unequal widths mirror by that edge, not by center.
for (a, b) in [(ctl("ipd"), ctl("depth")), (ctl("scr"), ctl("size"))] {
    for (fa, fb) in zip(a.frames, b.frames) {
        if fa.w != fb.w { check("\(a.word)-\(b.word)-mirror-x-value-edge", eq(fa.x, 2048 - fb.maxX) && eq(fa.y, fb.y)) }
        else { check("\(a.word)-\(b.word)-mirror-x", eq(mirroredX(fa, 2048), fb)) }
    }
}
for (a, b) in [(ctl("ipd"), ctl("scr")), (ctl("depth"), ctl("size"))] {
    let aLeft = a.corner == .topLeft || a.corner == .bottomLeft
    for (fa, fb) in zip(a.frames, b.frames) {
        if fa.w != fb.w { check("\(a.word)-\(b.word)-mirror-y-value-edge", (aLeft ? eq(fa.x, fb.x) : eq(fa.maxX, fb.maxX)) && eq(mirroredY(fa, 1152).y, fb.y)) }
        else { check("\(a.word)-\(b.word)-mirror-y", eq(mirroredY(fa, 1152), fb)) }
    }
}
// No two controls overlap in any element.
var overlap = false
for a in controls { for b in controls where a.word != b.word {
    for fa in a.frames { for fb in b.frames { if fa.intersects(fb) { overlap = true } } }
} }
check("no-control-overlap", !overlap)

// Subtitle band: bottom stacks shift above it with one pad of air, diagonals preserved.
let band = CornerTuneRect(x: 0, y: 0, w: 2048, h: 120)
let shifted = L.controls(in: content, subtitleBand: band, values: values)
func sctl(_ word: String) -> CornerTuneControl { shifted.first { $0.word == word }! }
check("size-above-subtitle-band", sctl("size").wordFrame.y == 120 + 12 && sctl("size").wordFrame.maxX == 2048 - m)
check("size-diagonal-preserved-under-shift", eq(sctl("size").cellA.y, sctl("size").valueFrame.y + 32) && eq(sctl("size").cellA.maxX, sctl("size").cellB.x - gap))
check("top-rows-untouched-by-band", sctl("ipd").wordFrame.maxY == 1152 - rowPad && sctl("depth").wordFrame.maxY == 1152 - rowPad)

// Chrome clearance: side chrome pushes the content edge, corner margins still exact.
let chrome = [CornerTuneRect(x: 0, y: 0, w: 40, h: 1152), CornerTuneRect(x: 2008, y: 0, w: 40, h: 1152)]
let cleared = CornerTuneLayout.clearContent(content, chrome: chrome, pad: 12)
let ccontrols = L.controls(in: cleared, subtitleBand: nil, values: values)
func cctl(_ word: String) -> CornerTuneControl { ccontrols.first { $0.word == word }! }
check("chrome-pushes-left-corner", cctl("ipd").wordFrame.x == 52 + m)
check("chrome-pushes-right-corner", cctl("size").wordFrame.maxX == 1996 - m)
// Owner 13:47 (halved from 12:40's pad x 2): with clearContent's pad, every title's outer edge
// sits pad x 1 (12 px in this fixture) from the spine/sidebar edge.
check("titles-pad-from-spine", eq(cctl("ipd").wordFrame.x - 40, 12) && eq(2008 - cctl("depth").wordFrame.maxX, 12))
check("titles-pad-from-sidebar", eq(cctl("scr").wordFrame.x - 40, 12) && eq(2008 - cctl("size").wordFrame.maxX, 12))


// Value formatting shared with the view.
check("format-size", CornerTuneLayout.format(key: "screenSize", raw: 80) == "80°")
check("format-ipd", CornerTuneLayout.format(key: "ipd", raw: 0.5) == "+0.5")
check("format-screen", CornerTuneLayout.format(key: "screenDepth", raw: 1.5) == "1.5m")

// Owner 21:28 (phonemsg-01M73BG6BQ7DP7BGPR2FWA3TXP): crosshair exactly at center, one UI-font cell.
func crosshairChecks(_ w: Double, _ h: Double, _ tag: String) {
    let full = CornerTuneRect(x: 0, y: 0, w: w, h: h)
    let c = CornerTuneLayout.crosshairFrame(in: full, charW: 8, lineH: 16)
    check("\(tag)-crosshair-one-cell", c.w == 8 && c.h == 16)
    check("\(tag)-crosshair-centered", (c.x + c.w / 2 - w / 2).magnitude < 1e-9 && (c.y + c.h / 2 - h / 2).magnitude < 1e-9)
    check("\(tag)-crosshair-inside", c.x >= 0 && c.maxX <= w && c.y >= 0 && c.maxY <= h)
}
crosshairChecks(2048, 1152, "even")
crosshairChecks(801, 603, "odd")

// Owner 21:29 (phonemsg-01M73BH406Z70HP50CPE0AM8QN): no control is ever clipped, any window size.
// Sweep worst case: content == the full picture bounds (chrome only shrinks content further).
let sizes: [(Double, Double)] = [(200, 200), (320, 200), (640, 480), (800, 600), (1024, 576), (1280, 720), (1600, 900), (1920, 1080), (2560, 1080), (3440, 1440), (3840, 2160), (801, 603), (2048, 1152)]
for (w, h) in sizes {
    let full = CornerTuneRect(x: 0, y: 0, w: w, h: h)
    let cs = L.controls(in: full, subtitleBand: nil, values: values)
    for c in cs {
        for f in c.frames {
            check("sweep-\(c.word)-\(Int(w))x\(Int(h))-never-clipped", f.x >= 0 && f.maxX <= w && f.y >= 0 && f.maxY <= h)
        }
    }
    let cross = CornerTuneLayout.crosshairFrame(in: full, charW: 8, lineH: 16)
    check("sweep-crosshair-\(Int(w))x\(Int(h))-inside", cross.x >= 0 && cross.maxX <= w && cross.y >= 0 && cross.maxY <= h)
}
// Owner 21:31 (phonemsg-01M73BN8SNRMNC3TGGTK18NJEV): fixed positions - when a value changes width
// (0.5 -> 0.75) NO frame of that control may move. Measured across each key's reachable values.
let valueSets: [String: [String]] = [
    "ipd": ["+0.0", "+0.1", "-0.1", "+0.2", "-0.2"],
    "strength": ["0", "0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2"],
    "screenDepth": ["0.25m", "0.667m", "1m", "1.5m", "2.25m", "3.38m", "5.06m", "7.59m", "8m"],
    "screenSize": ["20\u{00B0}", "75\u{00B0}", "105\u{00B0}", "150\u{00B0}"],
]
let specByKey = ["ipd": "ipd", "strength": "depth", "screenDepth": "scr", "screenSize": "size"]
for (key, set) in valueSets {
    var reference: CornerTuneControl?
    for v in set {
        var varied = values
        varied[key] = v
        let c = L.controls(in: content, subtitleBand: nil, values: varied).first { $0.word == specByKey[key]! }!
        check("\(c.word)-value-fits-field-\(v)", Double(v.count) * 8 <= c.valueFrame.w)
        if let r = reference {
            check("\(c.word)-fixed-positions-\(v)", c.wordFrame == r.wordFrame && c.valueFrame == r.valueFrame && c.cellA == r.cellA && c.cellB == r.cellB)
        } else { reference = c }
    }
}
// Every value `format` can emit for each key's reachable set must fit the fixed field width.
var s = 0.0
while s <= 2.0 { check("format-strength-fits-\(s)", CornerTuneLayout.format(key: "strength", raw: s).count <= 4); s += 0.25 }
var d = 1.5
while d < 8.0 { check("format-depth-fits-\(d)", CornerTuneLayout.format(key: "screenDepth", raw: d).count <= 6); d = min(d * 1.5, 8.0) }
d = 1.5
while d > 0.25 { check("format-depth-low-fits-\(d)", CornerTuneLayout.format(key: "screenDepth", raw: d).count <= 6); d = max(d / 1.5, 0.25) }
var z = 20.0
while z <= 150.0 { check("format-size-fits-\(z)", CornerTuneLayout.format(key: "screenSize", raw: z).count <= 4); z += 5 }
var i = -0.2
while i <= 0.2001 { check("format-ipd-fits-\(i)", CornerTuneLayout.format(key: "ipd", raw: i).count <= 4); i += 0.02 }
// Owner 2026-11-12 12:40: the diagonal steps are one line tall each on every corner; the pad x 1
// edge gaps themselves are pinned per control above.
for c in controls {
    check("\(c.word)-diagonal-line-steps", eq((c.cellB.y - c.valueFrame.y).magnitude, 16) && eq((c.cellA.y - c.cellB.y).magnitude, 16))
}

// Owner 21:43: window -> fullscreen -> back must never break placement. Same values throughout;
// every frame inside, crosshair centered, corner anchoring exact at every step of the transition.
let transition: [(Double, Double)] = [(1280, 720), (1920, 1080), (3440, 1440), (3840, 2160), (1280, 720)]
for (w, h) in transition {
    let full = CornerTuneRect(x: 0, y: 0, w: w, h: h)
    let cs = L.controls(in: full, subtitleBand: nil, values: values)
    func tctl(_ word: String) -> CornerTuneControl { cs.first { $0.word == word }! }
    for c in cs {
        for f in c.frames {
            check("fs-\(c.word)-\(Int(w))x\(Int(h))-inside", f.x >= 0 && f.maxX <= w && f.y >= 0 && f.maxY <= h)
        }
    }
    check("fs-anchors-\(Int(w))x\(Int(h))", tctl("ipd").wordFrame.x == m && tctl("ipd").wordFrame.maxY == h - rowPad
        && tctl("depth").wordFrame.maxX == w - m && tctl("depth").wordFrame.maxY == h - rowPad
        && tctl("scr").wordFrame.x == m && tctl("scr").wordFrame.y == rowPad
        && tctl("size").wordFrame.maxX == w - m && tctl("size").wordFrame.y == rowPad)
    let cr = CornerTuneLayout.crosshairFrame(in: full, charW: 8, lineH: 16)
    check("fs-crosshair-\(Int(w))x\(Int(h))-center", (cr.x + 4 - w / 2).magnitude < 1e-9 && (cr.y + 8 - h / 2).magnitude < 1e-9)
    // Fixed positions across the transition: same value => same columns, on every step.
    for c in cs {
        let leftSide = c.corner == .topLeft || c.corner == .bottomLeft
        let vEdge = leftSide ? c.valueFrame.x : w - c.valueFrame.maxX
        check("fs-\(c.word)-\(Int(w))x\(Int(h))-columns", eq(vEdge, vx))
    }
}
// Owner 2026-11-12 12:40 supersedes the 22:13 per-key field widths: the grid must not break, so
// every row carries the SAME value field - the widest value (screenDepth, 6 chars) - and the +/-
// cells align in one column on every corner. Values still center in the field.
for c in controls {
    check("\(c.word)-field-width", c.valueFrame.w == Double(CornerTuneLayout.valueFieldChars) * 8)
}

// The 22:23-22:26 hand-drawn mockup pixel-token measurements were superseded by the owner's
// 2026-11-12 12:40 pad grid (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q, gaps halved to pad x 1 at 13:47,
// phonemsg-01M77NX7459XYMH8W2B3VR9N01); the grid is pinned by the padx1 checks above. At the
// canonical mockup metrics (17.4 x 32.3 px, pad 16) the pad grid keeps the same corner-anchored
// diagonal reading order.
let ML = CornerTuneLayout(charW: 17.4, lineH: 32.3, pad: 16)
let panel = CornerTuneRect(x: 0, y: 0, w: 817, h: 461)
let mvalues: [String: String] = ["strength": "2", "ipd": "-1.4", "screenDepth": "8m", "screenSize": "65°"]
let mc = ML.controls(in: panel, subtitleBand: nil, values: mvalues)
func mctl(_ word: String) -> CornerTuneControl { mc.first { $0.word == word }! }
for word in ["ipd", "scr", "depth", "size"] {
    let c = mctl(word)
    let leftSide = c.corner == .topLeft || c.corner == .bottomLeft
    let mg = CornerTuneLayout.gridGapPads * 16
    let mr = Double(CornerTuneLayout.titleReserveChars) * 17.4
    let mt = CornerTuneLayout.titleMarginPads * 16
    let vEdge = leftSide ? c.valueFrame.x : 817 - c.valueFrame.maxX
    check("canonical-\(word)-padx1-grid", eq(vEdge, mt + mr + mg)
        && eq((leftSide ? c.cellB.x - c.valueFrame.maxX : c.valueFrame.x - c.cellB.maxX), mg)
        && eq((leftSide ? c.cellA.x - c.cellB.maxX : c.cellB.x - c.cellA.maxX), mg))
    // Rows: pair line box starts half a line from the corner edge; each element one line further in.
    let topCorner = c.corner == .topLeft || c.corner == .topRight
    let pairBoxTop = topCorner ? 461 - c.wordFrame.maxY : c.wordFrame.y
    let nearBoxTop = topCorner ? 461 - c.cellB.maxY : c.cellB.y
    check("canonical-\(word)-pair-row", abs(pairBoxTop - 16.15) <= 6)
    check("canonical-\(word)-near-row", abs(nearBoxTop - 48.45) <= 6)
}
if failures > 0 { print("FAILURES: \(failures)"); } else { print("ALL PASS") }

// Owner 2026-11-12 12:40: the 3D dropdown row sits on the row directly below V - top edge at V's
// minY, bottom edge one full typography row lower, at every font scale.
for row in [12.0,24.0,36.0,48.0] {
    let top=CornerTuneLayout.dropdownTop(videoMinY:200,lineH:row)
    precondition(top==200)
    precondition(top-row==200-row)
    precondition(CornerTuneLayout.dropdownTop(videoMinY:0,lineH:row)>=row)
}
// Owner update: the open surface remains attached but always fades with chrome.
for chrome in [1.0,0.5,0.0,1.0,0.0] {
    precondition(CornerTuneLayout.overlayAlpha(calibrationOnly:false,chromeAlpha:chrome)==chrome)
    precondition(CornerTuneLayout.overlayAlpha(calibrationOnly:true,chromeAlpha:chrome)==chrome)
}
print("PASS row offset and repeated idle/click visibility: full panel and marker fade with chrome")

precondition(failures == 0)
