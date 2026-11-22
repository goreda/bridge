#!/usr/bin/env python3
"""s44: VR distort pin - the output-modes aspect/FOV chain end to end.

Owner distort anchors (repo history): the 03:19 "VR distortion" incident
was a CROP bug (bcbb320e: stale stream-scan crops removed most of the
frame before the eye-aspect feed; incident test Tests/CropAcceptPolicy),
and the s20 tear/streaks were disocclusion-fill/surround kernel bugs
(pinned by Tests/Stereo3DKernel kernel parity tests). This test pins the
remaining link: the output-mode geometry itself - canvas/eye sizes, SAR
metadata, spherical flag, and the 75 deg FOV convention - so a wrong
aspect or FOV anywhere in the chain fails loudly on Linux.

Run: python3 Tests/DepthAnalysis/test_vr180_aspect.py
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools", "depth_analysis"))
import output_modes as om  # noqa: E402

SIZES = [(1920, 1080), (1280, 720), (3840, 2160), (2560, 1080), (1080, 1920),
         (720, 720), (1440, 1440), (1000, 563), (719, 405), (4096, 4096)]

# --- flat modes: the packed canvas holds both eyes at the SOURCE size;
# with the declared SAR the displayed per-eye aspect equals the source
# aspect exactly (no stretch, no crop).
for w, h in SIZES:
    for mode, sar in (("full_sbs", 1.0), ("half_sbs", 2.0),
                      ("over_under", 1.0), ("anaglyph", 1.0)):
        cw, ch = om.canvas_size(mode, w, h)
        ew = cw / 2 if mode in ("full_sbs", "half_sbs") else cw
        eh = ch / 2 if mode == "over_under" else ch
        assert mode != "half_sbs" or ew * 2 == w  # even split
        disp = (ew * sar) / eh
        assert abs(disp - w / h) < 1e-9, (mode, w, h, disp)
print(f"PASS flat modes: displayed aspect == source aspect for "
      f"{len(SIZES)} sizes x 4 modes")

# --- vr180: the eye canvas is the square equirect180 eye (even, clamped
# 256..4096); the spherical V2 metadata rides ONLY vr180; no SAR stretch.
for w, h in SIZES:
    n = om.eye_n_for(h)
    assert n == max(256, min(4096, h - h % 2)), (h, n)
    cw, ch = om.canvas_size("vr180", w, h)
    assert (cw, ch) == (2 * n, n), (w, h, cw, ch)
md = om.MODE_METADATA
for mode in ("full_sbs", "half_sbs", "over_under", "anaglyph"):
    assert "spherical" not in md[mode]["stereo_mode"], mode
assert "spherical" in md["vr180"]["stereo_mode"]
assert "equirect" in md["vr180"]["container"]
print("PASS vr180: square equirect eye per source height; spherical "
      "metadata only on vr180")

# --- the 75 deg FOV convention is identical on every side of the chain:
# the Swift menu/geometry constant, the Python reference default, and the
# remap parity test's theta_h. A mismatch here IS a distort (wrong screen
# size / wrong equirect projection) that no kernel test would catch.
om_src = open(os.path.join(ROOT, "tools/depth_analysis/output_modes.py")).read()
sw = (lambda _b: _b[_b.index('// BEGIN relocated OutputModes.swift '):_b.index('// END relocated OutputModes.swift\n')])(_threed_split().path(ROOT).read_text())
assert "static let screenDeg = 75.0" in sw
assert re.search(r"screen_deg=75\.0|screen_deg: float = 75\.0", om_src), "python default"
remap = open(os.path.join(ROOT, "Tests/Stereo3DKernel",
                          "stereo_remap_kernel_test.py")).read()
assert re.search(r"radians\(75\.0\)", remap), \
    "the kernel parity test must exercise the SAME 75 deg convention"
print("PASS FOV: 75 deg screen convention identical in Swift, Python "
      "reference, and the kernel parity test")

# --- eye-N parity: the Swift eyeN and the Python mirror agree on every
# height (the distort class of the 03:19 incident: wrong eye geometry).
swift_eyen = re.search(r"static func eyeN\(sourceHeight h: Int\) -> Int \{ "
                       r"max\(256, min\(4096, h - h % 2\)\)", sw)
assert swift_eyen, "Swift eyeN formula drifted"
for h in range(180, 4400, 37):
    assert om.eye_n_for(h) == max(256, min(4096, h - h % 2)), h
print("PASS eyeN: Swift formula == Python mirror across 115 heights")

print("vr180 aspect: all pins hold")
