#!/usr/bin/env python3
"""191w: IconBarFit glyph-ink icon rows - the REAL Sources/gor/UI/IconBarFit.swift
compiled and run against fixture ink metrics, mirrored in Python, plus static
pins on the five consumer sites. AppKit glyph pixels remain native (Mac unrun).

Owner orders 13:35 (phonemsg-01M72GDKF9Y03BK321XR5NWPED) and 14:06-14:07
(phonemsg-01M72J7EM5T303Z171N6BY9XDD / -J7RTQ84TYE20JKAFX6CVE /
-J7YWE7GS7GFD6Z9D6V7J8), English paraphrase: back glyph starts exactly where
folder icons start; hover expands left to right with no shift; gaps equalised
by measured graphical width; same system elsewhere; gaps too tight - open
them; buttons overlap - no two buttons' ink may ever overlap; whatever value
was given, x2, one gap constant for all bars. Owner 14:29
(phonemsg-01M72KH1SNH8NJWAYKNW26SMFV), English paraphrase: x2 the current
button gap; every panel's distance to the spine must equal its distance
to the sidebar.

Run: python3 Tests/IconBarFit/run.py
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json, os, re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
S = ROOT / 'Sources' / 'gor'
bad = 0

def check(name, ok):
    global bad
    print(('PASS ' if ok else 'FAIL ') + name)
    bad += (not ok)

# ---- 1. run the real production layout code against fixture metrics ----
src = (S / 'UI/IconBarFit.swift').read_text()
# IconBarFit reads PhotonFont metrics (same module on the Mac); on Linux a
# fixture stub supplies them. pad=11.2 is the current Mac metric, so the
# stub also pins standardGap == 2x the pad/2 the IPTV bar used to show.
stub = 'import Foundation\nenum PhotonFont { static var pad: CGFloat { 11.2 }; static var twoDigitW: CGFloat { 17 }; static var charW: CGFloat { 8 }; static var gap: CGFloat { 0 } }'
main = r'''
import Foundation
struct Out: Codable { var gap: Double; var panelPadR50: Double; var trailing: [[Double]]; var trailingHover: [[Double]]; var trailingGrown: [[Double]]; var trailingWide: [[Double]]; var leading: [[Double]]; var hoverLead: [[Double]]; var hoverTrail: [[Double]] }
func rects(_ f: [CGRect]) -> [[Double]] { f.map { [$0.minX, $0.minY, $0.width, $0.height] } }
let g = IconBarFit.standardGap
let p50 = IconBarFit.panelPadR(padL: 50)
let t1 = IconBarFit.trailingFrames(right: 400, height: 24, gap: g, buttons: [
    IconBarFit.Slot(width: 32, ink: 10), IconBarFit.Slot(width: 32, ink: 18), IconBarFit.Slot(width: 32, ink: 12)])
// hover: the middle button's ink and frame grow (typewriter title); re-lay with live values
let grown = IconBarFit.hoverFrame(current: t1[1], ink: 44, minWidth: 32, textPad: 8, expandsLeftToRight: false)
let t2 = IconBarFit.trailingFrames(right: 400, height: 24, gap: g, buttons: [
    IconBarFit.Slot(width: 32, ink: 10), IconBarFit.Slot(width: grown.width, ink: 44), IconBarFit.Slot(width: 32, ink: 12)])
// driven-font re-face near the cursor: inks widen WITHOUT hover; a re-lay must keep ink disjoint
let t3 = IconBarFit.trailingFrames(right: 400, height: 24, gap: g, buttons: [
    IconBarFit.Slot(width: 32, ink: 14), IconBarFit.Slot(width: 32, ink: 24), IconBarFit.Slot(width: 32, ink: 16)])
// extreme: rendered ink wider than the 32pt slot itself
let t4 = IconBarFit.trailingFrames(right: 400, height: 24, gap: g, buttons: [
    IconBarFit.Slot(width: 32, ink: 40), IconBarFit.Slot(width: 32, ink: 48)])
let l1 = IconBarFit.leadingFrames(left: 0, height: 24, gap: g, buttons: [
    IconBarFit.Slot(width: 32, ink: 10), IconBarFit.Slot(width: 32, ink: 18)])
// hover growth must never move the pinned edge: leading keeps minX, trailing keeps maxX
var hl: [CGRect] = []
var cur = CGRect(x: 0, y: 0, width: 32, height: 24)
for ink in [10.0, 20.0, 40.0, 60.0, 10.0] {
    cur = IconBarFit.hoverFrame(current: cur, ink: ink, minWidth: 32, textPad: 8, expandsLeftToRight: true)
    hl.append(cur)
}
var ht: [CGRect] = []
var curT = CGRect(x: 368, y: 0, width: 32, height: 24)
for ink in [10.0, 40.0, 5.0] {
    curT = IconBarFit.hoverFrame(current: curT, ink: ink, minWidth: 32, textPad: 8, expandsLeftToRight: false)
    ht.append(curT)
}
let out = Out(gap: g, panelPadR50: p50, trailing: rects(t1), trailingHover: rects(t2), trailingGrown: rects(t3), trailingWide: rects(t4), leading: rects(l1), hoverLead: rects(hl), hoverTrail: rects(ht))
print(String(data: try! JSONEncoder().encode(out), encoding: .utf8)!)
'''
with tempfile.TemporaryDirectory() as d:
    p = Path(d)
    (p / 'iconbarfit.swift').write_text(src)
    (p / 'photonfont_stub.swift').write_text(stub)
    (p / 'main.swift').write_text(main)
    subprocess.run([os.environ.get('SWIFTC', '/tmp/swift6/usr/bin/swiftc'),
                    str(p / 'iconbarfit.swift'), str(p / 'photonfont_stub.swift'), str(p / 'main.swift'), '-o', str(p / 'check')], check=True)
    r = subprocess.run([str(p / 'check')], check=True, capture_output=True, text=True)
out = json.loads(r.stdout)
GAP = out['gap']

# ---- 2. Python mirror: the same layout, derived independently ----
def mirror_trailing(right, gap, slots):
    frames, prev_left, first = [], right + gap, True
    for w, ink in slots:
        gright = right if first else prev_left - gap
        frames.append((gright - w, w))
        prev_left, first = gright - ink, False
    return frames

def mirror_leading(left, gap, slots):
    frames, x = [], left
    for w, ink in slots:
        frames.append((x, w))
        x += ink + gap
    return frames

def ink_spans_trailing(frames, inks):
    # ink right edge of a right-aligned button = frame maxX
    return [(x + w - ink, x + w) for (x, w), ink in zip(frames, inks)]

def gaps_ok(frames, inks, gap):
    spans = ink_spans_trailing(frames, inks)
    return all(abs(spans[i][0] - spans[i + 1][1] - gap) < 1e-9 for i in range(len(spans) - 1))

def disjoint(frames, inks):
    spans = sorted(ink_spans_trailing(frames, inks))
    return all(spans[i][1] <= spans[i + 1][0] + 1e-9 for i in range(len(spans) - 1))

check('standardGap == pad == 2x the pad/2 the IPTV bar showed (and > 2x the 4pt file/music/archive bars), owner x2 orders', GAP == 11.2)
check('panelPadR(padL=50): sidebar-side clearance == spine-side clearance (fixture spine 30.4 / sidebar 39.4)',
      abs((50 - 30.4) - (out['panelPadR50'] - 39.4)) < 1e-9)

mt = mirror_trailing(400, GAP, [(32, 10), (32, 18), (32, 12)])
st = [(f[0], f[2]) for f in out['trailing']]
check('trailingFrames == Python mirror (frame minX/width)', [(round(a, 9), round(b, 9)) for a, b in st] == [(round(a, 9), round(b, 9)) for a, b in mt])
check('trailing: measured ink-to-ink gap == standardGap for heterogeneous glyphs (10/18/12)', gaps_ok(st, [10, 18, 12], GAP))
check('trailing: rightmost glyph right edge pinned at the bar right edge', abs(st[0][0] + st[0][1] - 400) < 1e-9)

mth = mirror_trailing(400, GAP, [(32, 10), (52, 44), (32, 12)])
sth = [(f[0], f[2]) for f in out['trailingHover']]
check('hover mid-growth: frames == Python mirror', [(round(a, 9), round(b, 9)) for a, b in sth] == [(round(a, 9), round(b, 9)) for a, b in mth])
check('hover mid-growth: ink gaps stay equal; only slots left of the hovered button move', gaps_ok(sth, [10, 44, 12], GAP) and sth[0] == st[0] and sth[2][0] < st[2][0])
check('hover mid-growth: no two inks overlap', disjoint(sth, [10, 44, 12]))

sg = [(f[0], f[2]) for f in out['trailingGrown']]
check('driven-font re-face (inks widen, no hover): gaps equal, no overlap', gaps_ok(sg, [14, 24, 16], GAP) and disjoint(sg, [14, 24, 16]))

sw = [(f[0], f[2]) for f in out['trailingWide']]
check('ink wider than the slot itself: gaps equal, no overlap', gaps_ok(sw, [40, 48], GAP) and disjoint(sw, [40, 48]))

ml = mirror_leading(0, GAP, [(32, 10), (32, 18)])
sl = [(f[0], f[2]) for f in out['leading']]
check('leadingFrames == Python mirror', [(round(a, 9), round(b, 9)) for a, b in sl] == [(round(a, 9), round(b, 9)) for a, b in ml])
check('leading: first button starts exactly at the row leading edge', sl[0][0] == 0)
check('leading: ink spans disjoint', all(sl[1][0] - (sl[0][0] + 10) >= GAP - 1e-9 for _ in [0]))

hl = out['hoverLead']
check('leading hover: minX pinned through growth AND shrink (no few-pixel shift)', all(f[0] == 0 for f in hl))
check('leading hover: width grows rightwards with ink + pad, floor 32', hl[2][2] == 48 and hl[4][2] == max(32, 10 + 8))
ht = out['hoverTrail']
check('trailing hover: maxX pinned through growth and shrink', all(abs(f[0] + f[2] - 400) < 1e-9 for f in ht))
check('trailing hover: shrink floors at the resting width 32', ht[2][2] == 32)

# ---- 3. static pins on the consumers ----
check('IconBarFit: one shared gap constant exists and follows the font metric', 'static var standardGap: CGFloat { max(8, PhotonFont.pad) }' in src)
# Panel-inset equality (owner 14:29): every panel's padR comes from the one helper.
check('IconBarFit: panelPadR encodes spine/sidebar equality', 'padL + PhotonFont.twoDigitW - PhotonFont.charW - PhotonFont.gap' in src)
ma = (S / 'UI/MenuActions.swift').read_text(); ppf = (_pp_split().dpath(S,'PPController_Features.swift')).read_text(); mp0 = (S / 'Modes/MusicPanel.swift').read_text()
check('all six panel sites derive padR from IconBarFit.panelPadR (openFile, openArchive x2, addLocalLibrary, music, IPTV)',
      ma.count('IconBarFit.panelPadR(padL:') == 3 and ppf.count('IconBarFit.panelPadR(padL:') == 2 and mp0.count('IconBarFit.panelPadR(padL:') == 1)
check('no literal padR survives at the panel sites', 'padR: CGFloat = 75' not in ma and 'padR: CGFloat = 54' not in ma and 'padR: CGFloat = 60' not in mp0 and 'PhotonFont.twoDigitW + PhotonFont.pad * 1.5' not in ppf)
sb = (S / 'UI/SidebarUI.swift').read_text(); sp = (S / 'UI/SpineUI.swift').read_text()
check('chrome-width formulas the helper encodes still hold: sidebarWidth and spineWidth',
      re.search(r'var sidebarWidth: CGFloat \{ PhotonFont\.twoDigitW \+ PhotonFont\.pad \* 2 \}', sb) is not None
      and re.search(r'var PAD:\s*CGFloat \{ PhotonFont\.pad \}', sp) is not None
      and re.search(r'var BTN_W:\s*CGFloat \{ PhotonFont\.charW \+ PhotonFont\.gap \}', sp) is not None and 'PAD + BTN_W + PAD' in sp)

mp = (S / 'Modes/MusicPanel.swift').read_text()
a = mp.index('final class MusicBtn: NSView'); b = mp.index('override func mouseUp', a)
btn = mp[a:b]
check('MusicBtn: leading-expansion mode exists and flips text alignment', 'expandsLeftToRight' in btn and 'alignmentMode' in btn)
check('MusicBtn: hover growth goes through IconBarFit.hoverFrame (both timers)', btn.count('IconBarFit.hoverFrame') >= 2)
check('MusicBtn: ink measured from the font the layer actually renders (CTLine on textLayer.font), not a parallel NSFont guess',
      'CTLineCreateWithAttributedString' in btn and '[.font: rawFont as! CTFont]' in btn and 'CGFloat(CTLineGetTypographicBounds' in btn and 'nsDriven' not in btn and 'wght: 700' not in btn)
# 191w-follow gate (owner Mac 14:20:44, build FAIL on 98e111466): the class that broke the Mac build -
# macOS-only Darwin-API misuse that no Linux stub typecheck can see. Swept repo-wide, not just MusicBtn.
sw_all = {p.name: p.read_text() for p in S.glob('*.swift')}
no_cf_downcast = [n for n, t in sw_all.items() if re.search(r'as\?\s+(?:CT|CG|CF|CV|MTL)[A-Z]', t)]
check('no conditional downcast to a CoreFoundation type anywhere (Mac hard error, was MusicPanel.swift:1661:53)', not no_cf_downcast)
no_bare_ctkey = [n for n, t in sw_all.items() if re.search(r'kCT\w+AttributeName(?!\s+as\s+String)', t)]
check('CT attribute-name constants reach attributed-string keys only via the as-String wrap (Mac hard error, was MusicPanel.swift:1662:96)', not no_bare_ctkey)
check('MusicBtn exposes measured inkWidth for the gap system', 'var inkWidth: CGFloat' in btn)
vb = btn[btn.index('VariationBroadcaster.shared.addListener'):btn.index('required init')]
check('MusicBtn: a driven-font width change re-lays the bar (overlap fix)', 'widthBefore' in vb and 'superview?.needsLayout = true' in vb)

fb = (S / 'Media/FileBrowser.swift').read_text()
check('FileBrowser: row leading inset is a named constant the top bar shares', 'static let rowLeading' in fb and 'padLeft: CGFloat = Self.rowLeading' in fb)
check('FileBrowser top bar: back glyph pinned at the row icon start, expands left to right', 'FileListRow.rowLeading' in fb and 'upBtn.expandsLeftToRight = true' in fb)
check('FileBrowser: both rows (top bar + accessories) use the one standardGap', fb.count('IconBarFit.trailingFrames') >= 2 and fb.count('IconBarFit.standardGap') >= 2)
check('FileBrowser: accessory reserve accounts for the widened gaps', 'standardGap' in fb.split('accessoryReserve')[1].split('}')[0])

a = mp.index('final class MusicTopBar'); mtb = mp[a:a + 9000]
check('MusicTopBar: back expands left to right, right row on standardGap', 'backBtn.expandsLeftToRight = true' in mtb and 'IconBarFit.standardGap' in mtb)

ip = (S / 'Media/IPTV.swift').read_text()
a = ip.index('final class IPTVTopBar'); itb = ip[a:a + 14000]
check('IPTVTopBar: both groups on standardGap', itb.count('IconBarFit.standardGap') >= 2)
check('IPTVTopBar: back/home expand left to right; old -5 glyph fudge gone', 'backBtn.expandsLeftToRight = true' in itb and 'homeBtn.expandsLeftToRight = true' in itb and 'lx - 5' not in itb)

ab = (S / 'Media/ArchiveBrowser.swift').read_text()
a = ab.index('final class ArchiveTopBar'); atb = ab[a:a + 12000]
check('ArchiveTopBar: back expands left to right, right row on standardGap', 'backBtn.expandsLeftToRight = true' in atb and 'IconBarFit.standardGap' in atb)

print('Mac pixels unrun: glyph ink widths are font-metric fixtures here; rendered-pixel alignment is Delivery\'s Mac capture')
sys.exit(1 if bad else 0)
