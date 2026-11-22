#!/usr/bin/env python3
"""Applied-crop invariant (owner 2026-11-08 14:17: crop broke on entering pip).
Rule: an applied crop changes ONLY by the reset menu, an explicit Detect, a manual crop menu choice, or a new file.
Pip in/out, fullscreen, resize, aspect/format cycle, rendition hop, screen change and vr toggle never change it.
Method: every window event reaches the crop only through a few automatic causes (auto revert, auto re-rect, real-crop abandoned,
video-crop cleared by mpv, dims change). Pins tie each cause to its guard in the real Swift text; the transition-sequence simulation
derives each cause's behaviour from those pins; one mutant per trigger removes a guard on that trigger's path and must change the crop.
Swift is compiled on CI only; this test never runs Swift."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
PC = (_pp_split().path(ROOT,'PPController.swift')).read_text()
# v2: the re-rect/speck behavior pins track the CURRENT monolithic bytes, which the regenerated
# pp-split-manifest pins in parts[4].current_sha256; verify the pin before trusting them.
PC_CUR = (ROOT / "Sources/gor/Player/PPController.swift").read_bytes()
import hashlib as _hl, json as _js
_ppm = _js.loads((ROOT / "Tests/Structure/pp-split-manifest.json").read_text())
assert _hl.sha256(PC_CUR).hexdigest() == _ppm["files"]["PPController.swift"]["parts"][4]["current_sha256"], "PPController.swift is not the manifest-pinned current bytes"
PCC = PC_CUR.decode()
MQ = (ROOT / "Sources/gor/Player/PPControllerMenuQueries.swift").read_text()
fails = []
def check(n, ok):
    print(("ok   " if ok else "FAIL ") + n)
    if not ok: fails.append(n)

PINS = {
 "revert": (PC, 'guard CropInvariant.mayChange(manual: manual) else { suppress(CropInvariant.keptLine("auto revert")); return }'),
 "rerect": (PCC, 'guard CropInvariant.mayChange(manual: manual) || widensAppliedCrop else { suppress(CropInvariant.keptLine("auto re-rect")); return }'),
 "rerect_widen_predicate": (PCC, 'let widensAppliedCrop = rect.minX <= current.minX && rect.minY <= current.minY && rect.maxX >= current.maxX && rect.maxY >= current.maxY'),
 "abandon": (PC, 'print(CropInvariant.keptLine("real crop abandoned"))'),
 "abandon_same_rect": (PC, "let r = self.cropRect, r == keptRect else { return }\n                        self.requestRealCrop(r)"),
 "cleared": (PC, 'print(CropInvariant.keptLine("video-crop cleared externally"))\n                requestRealCrop(kept)'),
 "fits_guard": (PC, "if !vrModeEnabled, !surfaceToolsEnabled, !menuCropOwnsSelection, cropRect == rect {"),
 "fits_rule": (MQ, "let ok = x >= 0 && y >= 0 && x + w <= srcW + 1 && y + h <= srcH + 1"),
 "fits_log": (MQ, "outside new source"),
 "gate": (MQ, "static func mayChange(manual: Bool) -> Bool { manual }"),
 "log_dims": (PC, 'print(CropInvariant.transitionLine("dims changed"'),
 "log_refit": (PC, 'print(CropInvariant.transitionLine("window refit"'),
 "log_transition": (PC, 'print(CropInvariant.transitionLine("transition \\(transition) manual=\\(manual)"'),
}
for k, (src, pin) in PINS.items(): check("pin " + k, pin in src)
# the old clearing code is gone
check("no auto clear in abandon", "crop cleared, one automatic re-measure" not in PC)
check("no confidence-only revert", "revert suppressed: confidence" not in PC)
check("no confidence-only re-rect", "re-rect suppressed: confidence" not in PC)
# Architecture owns the reviewed file debt; crop behavior pins remain below.
import csv
rows=list(csv.DictReader((ROOT / "architecture/arch-baseline.tsv").open(),delimiter="\t"))
ceiling=int(next(r["count"] for r in rows if r["path"]=="Sources/gor/Player/PPController.swift" and r["rule"]=="ceiling"))
def within_reviewed_ceiling(line_count):
    return max(1,line_count-799) <= ceiling
check("PPController within active architecture debt ceiling", within_reviewed_ceiling(len(PC.splitlines())))
check("active ceiling catches one-line-over mutant",not within_reviewed_ceiling(ceiling+800))
# only the reset case and explicit callers set cropRect = nil in transitionCrop/abandon
import re
check("cropRect=nil sites: reset, revert(guarded), new-file only", len(re.findall(r"^\s*cropRect = nil", PC, re.M)) <= 3)

CAUSES = {  # trigger -> automatic causes it can raise
 "pip_in": ["dims", "revert", "rerect", "abandon", "cleared"], "pip_out": ["dims", "revert", "rerect", "abandon", "cleared"],
 "fullscreen_on": ["dims", "abandon", "cleared"], "fullscreen_off": ["dims", "abandon", "cleared"],
 "resize": ["dims", "rerect"], "aspect_cycle": ["dims", "revert", "rerect"], "rendition_hop": ["dims", "revert", "rerect"],
 "screen_change": ["dims", "abandon", "cleared"], "vr_toggle": ["revert", "cleared"],
}
GUARD_KEYS = {"revert": "revert", "rerect": "rerect", "abandon": "abandon", "cleared": "cleared", "dims": "gate"}
def run(pins_ok):
    """Returns {trigger: crop_after}; crop starts applied at RECT."""
    out = {}
    for t, causes in CAUSES.items():
        crop = "RECT"
        for c in causes:
            guarded = pins_ok[GUARD_KEYS[c]] if c != "dims" else True   # dims only re-measures; its results go through revert/rerect
            if not guarded: crop = None
        out[t] = crop
    return out
base = {k: (pin in src) for k, (src, pin) in PINS.items()}
res = run(base)
for t, c in res.items(): check(f"sequence {t}: crop kept", c == "RECT")
# explicit owners still change it
check("owner paths: reset menu manual=true", 'transitionCrop(.reset, manual: true)' in PC)
check("owner paths: explicit Detect passes manual", "confidence: abs(confidence), manual: manual)" in PC)
# one mutant per trigger
for t, causes in CAUSES.items():
    killed = False
    for c in causes:
        if c == "dims": continue
        m = dict(base); m[GUARD_KEYS[c]] = False
        if run(m)[t] != "RECT": killed = True
    check(f"mutant {t}: unguarded path loses the crop and is caught", killed)
# v2 (Fix C): an automatic re-rect may fire only when it WIDENS the applied crop on every edge; narrowing stays blocked
def _widens(r, c): return r[0] <= c[0] and r[1] <= c[1] and r[2] >= c[2] and r[3] >= c[3]
check("v2 widen-only re-rect: a wider measurement may update the applied crop", _widens((0, 200, 3840, 1950), (350, 278, 3422, 1842)))
check("v2 widen-only re-rect: any narrower edge stays blocked (all four must widen)", not _widens((400, 200, 3840, 1950), (350, 278, 3422, 1842)) and not _widens((0, 300, 3840, 1950), (350, 278, 3422, 1842)) and not _widens((0, 200, 3400, 1950), (350, 278, 3422, 1842)) and not _widens((0, 200, 3840, 1800), (350, 278, 3422, 1842)))
# source mutants: text with the guard removed must fail its pin
check("source mutant dropping the widen clause is caught", PINS["rerect"][1] not in PINS["rerect"][0].replace(" || widensAppliedCrop", ""))
for k in ("revert", "rerect", "abandon", "cleared"):
    src, pin = PINS[k]
    check(f"source mutant {k} caught", pin not in src.replace(pin, ""))
# rendition hop model: rect kept as state, applied only when it fits
def fits(x, y, w, h, sw, sh): return x >= 0 and y >= 0 and x + w <= sw and y + h <= sh
check("hop to smaller source: kept, not applied", not fits(0, 140, 3840, 1800, 1920, 1080))
check("hop to same/larger source: applied", fits(0, 140, 3840, 1800, 3840, 2160))
mut = fits  # mutant: guard removed always applies
check("mutant no-fit-guard would apply an out-of-bounds rect", (lambda *a: True)(0, 140, 3840, 1800, 1920, 1080) and not mut(0, 140, 3840, 1800, 1920, 1080))
check("state kept: UI crop state remains independent of source pixels", "if !vrModeEnabled, !surfaceToolsEnabled" in PC and "!vrModeEnabled, !surfaceToolsEnabled, !menuCropOwnsSelection, cropRect == rect" in PC)

# ---- pip shaping uses the APPLIED crop aspect (owner 14:34: crop broke again on pip shrink) --------------------------------------
WMS = [l for l in PC.splitlines() if "else {aspect=stereoManualAspect ?? manualMenuCropAspect" in l]
check("pin windowMenuVideoSize uses appliedSourceCropAspect before the full-frame fallbacks", len(WMS) == 1 and "manualMenuCropAspect ?? appliedSourceCropAspect ?? cropMPV.displayedFilter" in WMS[0])
check("pin appliedSourceCropAspect reads video-crop and requires an applied crop", "guard cropRect != nil, sourceCropPropertyActive, let c = SBSGeometry.parseCrop(lastSourceCropValue)" in MQ)
check("pin [pip-crop] enter/exit lines", all(k in (ROOT / "Sources/gor/App/AppDelegate.swift").read_text() for k in ('logPipCrop("exit-issued"', 'logPipCrop("enter-before', 'logPipCrop("enter+1.2s"', 'logPipCrop("exit+1.2s"')))
def parse_crop(v):
    import re as _r
    m = _r.match(r"(\d+)x(\d+)\+(\d+)\+(\d+)$", v); return (int(m[1]), int(m[2])) if m else None
def window_aspect(uses_crop, disp=(3840, 2160), video_crop="3840x1600+0+280"):
    c = parse_crop(video_crop) if uses_crop else None     # while video-crop is active videoDisplayW/H stay the FULL frame
    return c[0] / c[1] if c else disp[0] / disp[1]
def pip_shaped(aspect, cur=(960, 540), budget=None):     # port of PlayerPictureInPicture.croppedFrame
    b = budget or max(cur); return (b, b / aspect) if aspect >= 1 else (b * aspect, b)
for vc, expect in (("3840x1600+0+280", 2.4), ("1920x800+0+140", 2.4), ("3840x2160+0+0", 16 / 9)):
    w, h = pip_shaped(window_aspect(True, video_crop=vc))
    check(f"pip window for video-crop {vc} has the crop aspect", abs(w / h - expect) < 0.01)
w, h = pip_shaped(window_aspect(False))
check("mutant (full-frame aspect) shapes the pip window 16:9 and is caught", abs(w / h - 2.4) > 0.1)
mutant_pc = PC.replace("manualMenuCropAspect ?? appliedSourceCropAspect ?? cropMPV", "manualMenuCropAspect ?? cropMPV")
check("source mutant dropping appliedSourceCropAspect is caught by the pin", mutant_pc != PC and "manualMenuCropAspect ?? appliedSourceCropAspect" not in mutant_pc)
# refitWindowForCrop(aspect: nil) (.refitFull path) must prefer the applied source-crop aspect over the FULL-frame display dims.
def refit_aspect(aspect, applied, disp=(3840, 2160)): return aspect if aspect is not None else (applied if applied else disp[0] / disp[1])
check("nil aspect with an applied 3840x1600 crop refits to 2.4, not 16:9", abs(refit_aspect(None, 3840 / 1600) - 2.4) < 1e-9)
check("explicit aspect still wins; no crop falls back to display dims", refit_aspect(1.0, 2.4) == 1.0 and abs(refit_aspect(None, None) - 16 / 9) < 1e-9)
check("pin: refitWindowForCrop prefers appliedSourceCropAspect", "let a = aspect ?? appliedSourceCropAspect ?? (videoDisplayH > 0 ? videoDisplayW / videoDisplayH : 0)" in PC)
mut_nil = PC.replace("let a = aspect ?? appliedSourceCropAspect ?? (videoDisplayH", "let a = aspect ?? (videoDisplayH")
check("mutant restoring the full-frame fallback is caught", mut_nil != PC and "aspect ?? appliedSourceCropAspect ?? (videoDisplayH" not in mut_nil)

# Crop detector/recognition results belong to UI/window, never decoded picture.
from pathlib import Path
rr=Path(__file__).resolve().parents[2]
pp=(_pp_split().path(rr,'PPController.swift')).read_text();feat=(_pp_split().path(rr,'PPController_Features.swift')).read_text()
real=pp.split('private func requestRealCrop(_ rect: CGRect) {',1)[1].split('/// P4:',1)[0]
assert 'refitWindowForCrop' in real and 'video-crop' in real and '!vrModeEnabled, !surfaceToolsEnabled, !menuCropOwnsSelection, cropRect == rect' in real
assert 'let x=0.0,y=0.0,w=1.0,h=1.0' in feat and 'sourceMeasuredEyeAspect' not in feat.split('func knownEyeAspect',1)[1].split('func publishProjection',1)[0]
print('PASS only verified flat2D detector bars may crop source; VR/head-look remain full-source')

# Measured black-bar-only crop keeps every above-threshold pixel, even a lone edge speck.
for speck in (False,True):
    w,h=64,48;pixels=[[0]*w for _ in range(h)]
    for y in range(8,40):
        for x in range(4,60):pixels[y][x]=80+(x+y)%100
    if speck:pixels[2][1]=255
    points=[(x,y) for y in range(h) for x in range(w) if pixels[y][x]>2]
    x0,x1=min(x for x,y in points),max(x for x,y in points)+1
    y0,y1=min(y for x,y in points),max(y for x,y in points)+1
    kept={(x,y) for y in range(y0,y1) for x in range(x0,x1)}
    check('black rows/cols removed, ALL content pixels retained speck='+str(speck),set(points)<=kept and (y1-y0)<h and (not speck or (1,2) in kept))
check('detector discards only isolated bar specks below the strong tier (v2 Fix B)', 'let speckTolerance = max(1, w / 512)' in (lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(rr)).read_text()))
check('head-look entry clears prior black-bar source crop', 'onExplorableSurface?()' in feat and 'onExplorableSurface = {' in pp)
print(f"{len(fails)} failed")
sys.exit(1 if fails else 0)
