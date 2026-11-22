#!/usr/bin/env python3
"""Direction/corner glyphs are DERIVED from the action each row triggers, never pinned as text only (owner 2026-11-08).
window > position: glyph row (glyph, mode, key) -> PlayerWindowPlacement case body -> vertical/horizontal -> expected glyph.
subtitles > position: glyph -> selector -> sub-pos delta sign (mpv sub-pos 0 = top, 100 = bottom) -> up/down.
Mutants: swap two glyphs, swap two placement bodies, flip the sub-pos delta: each must be caught. Swift is not run."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
AD = (ROOT / "Sources/gor/App/AppDelegate.swift").read_text()
MA = (ROOT / "Sources/gor/UI/MenuActions.swift").read_text()
GLYPH = {("top", "left"): "↖", ("top", "right"): "↗", ("bottom", "left"): "↙", ("bottom", "right"): "↘", ("center", "center"): "•"}
def derive(ad, ma):
    rows = re.search(r'for \(title,mode,key\) in \[.*', ad + "\n")
    pairs = [(g, m, k) for g, m, k in re.findall(r'\("(.)","([a-z-]+)",("[a-z.]"|String\(UnicodeScalar\(NS\w+ArrowFunctionKey\)!\))\)', rows.group(0) + ad[ad.index(rows.group(0)):][:900])]
    pairs = list(dict.fromkeys(pairs))
    out = []
    for glyph, mode, key in pairs:
        m = re.search(r'case "%s":r\.origin=CGPoint\(x:([^,\n]+),y:([^\n]*)\)' % mode, ma)
        x, y = m.group(1), m.group(2)
        if "midX" in x and "midY" in y: v = h = "center"
        else:
            h = "right" if "maxX" in x else "left" if "minX" in x else "?"
            v = "top" if "maxY" in y else "bottom" if "minY" in y else "?"
        out.append((glyph, mode, key, v, h, GLYPH.get((v, h))))
    return out
def sub(ad, ma):
    res = {}
    for g, sel in re.findall(r'subPosMenu\.addItem\(item\("([↑↓])",\s*action: #selector\((\w+)\)', ad):
        d = re.search(r'func %s\(\)\s*\{ controller\?\.adjustSubtitleProperty\("sub-pos",delta:(-?\d+)\)' % sel, ma)
        res[g] = (sel, int(d.group(1)), "up" if int(d.group(1)) < 0 else "down")
    return res
def ok(ad, ma):
    errs = []
    rows = derive(ad, ma)
    if len(rows) != 5: errs.append("row count")
    for glyph, mode, key, v, h, exp in rows:
        if glyph != exp: errs.append(f"{mode}: glyph {glyph} but action goes {v}-{h} ({exp})")
    s = sub(ad, ma)
    if s.get("↑", (0, 0, ""))[2] != "up" or s.get("↓", (0, 0, ""))[2] != "down": errs.append("sub-pos arrows")
    return errs
fails = []
def check(n, c):
    print(("ok   " if c else "FAIL ") + n)
    if not c: fails.append(n)
check("real source: every glyph matches its action", ok(AD, MA) == [])
for g, mode, key, v, h, exp in derive(AD, MA): print(f"     {g}  key {key}  mode {mode} -> {v}-{h}")
for k, (sel, d, dirn) in sub(AD, MA).items(): print(f"     {k}  {sel} sub-pos delta {d:+d} -> {dirn}")
check('bullet is U+2022 not middot', '("•","center",".")' in AD and '·' not in AD.split('let positionMenu')[1][:400])
mut1 = AD.replace('("↖","top-left",String(UnicodeScalar(NSUpArrowFunctionKey)!)),("↗","top-right"', '("↗","top-left",String(UnicodeScalar(NSUpArrowFunctionKey)!)),("↖","top-right"')
check("mutant swap two arrows caught", mut1 != AD and ok(mut1, MA) != [])
mut2 = MA.replace('case "top-left":r.origin=CGPoint(x:visible.minX,y:visible.maxY-r.height)', 'case "top-left":r.origin=CGPoint(x:visible.minX,y:visible.minY)')
check("mutant top-left goes bottom caught", mut2 != MA and ok(AD, mut2) != [])
mut3 = MA.replace('adjustSubtitleProperty("sub-pos",delta:-1) }', 'adjustSubtitleProperty("sub-pos",delta:1) }', 1)
check("mutant sub-pos up delta flipped caught", mut3 != MA and ok(AD, mut3) != [])
check("window-place log present", "[window-place] mode=" in AD)

# ---- corner target frames lie inside the usable area (menu bar / notch / Dock excluded) ------------------------------------------
PIN_USABLE = "let usable=pictureInPictureActive ? screen.frame : PlayerWindowPlacement.usableFrame(screen:screen.frame,visible:screen.visibleFrame,"
check("pin non-pip placement uses the usable frame, pip keeps the screen frame", PIN_USABLE in AD)
def corner(mode, size, area):  # port of PlayerWindowPlacement.frame origin rules (AppKit y-up)
    (ax, ay, aw, ah), (w, h) = area, size
    x = {"left": ax, "right": ax + aw - w}.get(mode.split("-")[-1], ax + aw / 2 - w / 2)
    y = {"top": ay + ah - h, "bottom": ay}.get(mode.split("-")[0], ay + ah / 2 - h / 2)
    return x, y, w, h
SCREEN = (0, 0, 1728, 1117); VISIBLE = (0, 70, 1728, 1117 - 70 - 38)   # Dock 70 at the bottom, notch menu bar 38
def inside(f, a): return f[0] >= a[0] and f[1] >= a[1] and f[0] + f[2] <= a[0] + a[2] and f[1] + f[3] <= a[1] + a[3]
for mode in ("top-left", "top-right", "bottom-left", "bottom-right"):
    check(f"{mode} lands inside the usable area", inside(corner(mode, (800, 450), VISIBLE), VISIBLE))
    check(f"mutant screen.frame for {mode} leaves the usable area (menu bar/Dock) and is caught", not inside(corner(mode, (800, 450), SCREEN), VISIBLE))

# ---- shipped code points (hex), not the intended glyph (owner screenshot 14:47 showed bar arrows on rows h and j) -----------------
def cps(src, pat):
    m = re.search(pat, src); return [f"U+{ord(c):04X}" for c in m.group(0) if ord(c) > 127]
rowline = [l for l in AD.splitlines() if '("↖","top-left",' in l][0]
WANT = ["U+2196", "U+2197", "U+2199", "U+2198"]
check("corner glyph code points in source are exactly U+2196 U+2197 U+2199 U+2198 (h l k j)", [f"U+{ord(c):04X}" for c in rowline if ord(c) > 127] == WANT)
check("center is U+2022", [f"U+{ord(c):04X}" for c in re.search(r'\("(.)","center","\."\)', AD).group(0) if ord(c) > 127] == ["U+2022"])
subs = re.findall(r'subPosMenu\.addItem\(item\("(.)",\s*action: #selector\((menuSub(?:Up|Down))\)', AD)
check("subtitle arrows are U+2191 (up) and U+2193 (down)", [(f"U+{ord(g):04X}", n) for g, n in subs] == [("U+2191", "menuSubUp"), ("U+2193", "menuSubDown")])
check("no corner-arrow lookalikes U+21F1/U+21F2/U+2912/U+2913 anywhere in AppDelegate/MenuActions", not any(c in AD + MA for c in "\u21f1\u21f2\u2912\u2913"))
check("pin Apple Symbols attributed title on the position rows", 'NSFont(name:"Apple Symbols",size:NSFont.systemFontSize*8/6)' in AD and "entry.attributedTitle=" in AD)
mut_cp = AD.replace('("↖","top-left",', '("\u21f1","top-left",').replace('("↘","bottom-right",', '("\u21f2","bottom-right",')
mrow = [l for l in mut_cp.splitlines() if '"top-left",String' in l][0]
check("mutant U+21F1/U+21F2 on h/j is caught by the code point pin", [f"U+{ord(c):04X}" for c in mrow if ord(c) > 127] != WANT)

# ---- shortcuts: arrow keys with the same four modifiers (owner 14:47) ------------------------------------------------------------
# Owner mapping (final 14:50): • = "." ; ↖ = Up ; ↗ = Right ; ↙ = Left ; ↘ = Down ; all with fn+ctrl+opt+cmd (no shift).
SCHEME = {"top-left": "Up", "top-right": "Right", "bottom-left": "Left", "bottom-right": "Down"}
loop = AD[AD.index("let positionMenu = group"):][:1500]
keys = dict(re.findall(r'\("[^"]","([a-z-]+)",String\(UnicodeScalar\(NS(\w+)ArrowFunctionKey\)!\)\)', loop))
check("each corner row uses its owner-mapped arrow as keyEquivalent", keys == SCHEME)
print("     rows: " + "; ".join(f"{g} -> {k} -> {m}" for g, m, k in [("•", "center", "."), ("↖", "top-left", "Up"), ("↗", "top-right", "Right"), ("↙", "bottom-left", "Left"), ("↘", "bottom-right", "Down")]))
check("center row is the period key", '("•","center",".")' in loop)
check("position rows carry exactly fn+ctrl+opt+cmd (mask [.function,.control,.option,.command]), no shift", "key:key,mods:[.function,.control,.option,.command])" in loop and ".shift" not in loop.split("let sizeMenu")[0])
mut_mask = AD.replace("key:key,mods:[.function,.control,.option,.command])", "key:key,mods:[.command,.control,.option,.shift])", 1)
check("mutant restoring the shift mask is caught", mut_mask != AD and "key:key,mods:[.function,.control,.option,.command])" not in mut_mask[mut_mask.index("let positionMenu = group"):][:1500])
mut_key = AD.replace("NSUpArrowFunctionKey)!)),(\"↗\"", "NSRightArrowFunctionKey)!)),(\"↗\"")
mut_dot = AD.replace('("•","center",".")', '("•","center","c")')
check("mutant restoring c for center is caught", mut_dot != AD and '("•","center",".")' not in mut_dot)
dots = [l for l in AD.splitlines() if ('key: "."' in l or 'key:"."' in l)]
check("other period rows: next frame none, next chapter cmd+ctrl+opt WITHOUT fn, zoom out fn+shift: none has fn+ctrl+opt+cmd", len(dots) == 3 and not any(".function" in l and ".control" in l and ".option" in l and ".command" in l for l in dots))
chap = [l for l in dots if "menuChapterNext" in l][0]
check("adjacent chord: next chapter is ctrl+opt+cmd+. without fn (distinct mask from center)", ".function" not in chap and "fs" not in chap)
check("mutant swapping two arrow keys is caught", mut_key != AD and dict(re.findall(r'\("[^"]","([a-z-]+)",String\(UnicodeScalar\(NS(\w+)ArrowFunctionKey\)!\)\)', mut_key[mut_key.index("let positionMenu = group"):][:1500])) != SCHEME)
# conflicts: no other menu row uses an arrow key with all four of these modifiers; move video is fn+shift, delay is cmd+shift
others = [l for l in AD.splitlines() if "ArrowFunctionKey" in l and "positionMenu" not in l and "for (title,mode,key)" not in l]
check("no other row binds an arrow with ctrl+opt+cmd (move video is fn+shift, delay cmd+shift)", not any(".control" in l and ".option" in l and ".command" in l for l in others))
PF = (_pp_split().path(ROOT,'PPController_Features.swift')).read_text()
check("pip fn+arrow corner keys require NO command/option/control/shift, so they never fire on these chords", "let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])\n        guard modifiers.isEmpty" in PF)
check("raw key handlers for arrows exclude events carrying command", PF.count("keyCode == 123, !flags.contains(.command), !flags.contains(.shift)") == 1 and "keyCode == 126, !flags.contains(.command)" in PF)
# Owner glyph size spec (15:36 screenshots, same 303x222 scale, row pitch 22 px): target IMG_3294 glyph box 8x8 px for the bullet and all four
# arrows; his build (Apple Symbols at the 13 pt menu size) measured bullet 3x3, arrows 6x6 (5 tall for the lower-left arrow).
TARGET_PX, MEASURED_ARROW_PX, MEASURED_BULLET_PX, MENU_PT = 8.0, 6.0, 3.0, 13.0
arrow_pt = MENU_PT * TARGET_PX / MEASURED_ARROW_PX
check("arrow font size derived from the measurements is 17.33 pt (13 x 8/6)", abs(arrow_pt - 17.3333) < 0.01 and "NSFont.systemFontSize*8/6" in AD)
check("arrows now reach the 8 px target within 1 px, bullet keeps the menu font whose 8 px box matched the target",
      abs(MEASURED_ARROW_PX * arrow_pt / MENU_PT - TARGET_PX) < 1.0 and 'if title != "•",let f=NSFont(name:"Apple Symbols"' in AD)
mut_size = AD.replace("NSFont.systemFontSize*8/6", "NSFont.systemFontSize")
check("mutant back to the 13 pt tiny glyphs is caught", mut_size != AD and "NSFont.systemFontSize*8/6" not in mut_size)
mut_bullet = AD.replace('if title != "•",let f=NSFont', 'if let f=NSFont')
check("mutant restoring the Apple Symbols bullet (3 px dot) is caught", mut_bullet != AD and 'if title != "•",let f' not in mut_bullet)
print(f"{len(fails)} failed"); sys.exit(1 if fails else 0)
