#!/usr/bin/env python3
"""Canonical chrome canvas: one local scale for all layout and font metrics."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
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
from pathlib import Path
import math, re

root = Path(__file__).resolve().parents[2]
font = _sub_read(root / 'Sources/gor/UI/PhotonFont.swift')
icon = _sub_read(root / 'Sources/gor/UI/IconBarFit.swift')
pp = _sub_read(_pp_split().path(root,'PPController.swift'))
spine = _sub_read(root / 'Sources/gor/UI/SpineUI.swift')
sidebar = _sub_read(root / 'Sources/gor/UI/SidebarUI.swift')
tune = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTune.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTune.swift'+'\n')])(_sub_read(_threed_split().path(root)))
layout_src = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTuneLayout.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTuneLayout.swift'+'\n')])(_sub_read(_threed_split().path(root)))
menu = _sub_read(root / 'Sources/gor/UI/MenuActions.swift')
failures = []

def check(ok: bool, message: str) -> None:
    if not ok:
        failures.append(message)

def extract_func(src: str, signature: str) -> str:
    start = src.find(signature)
    if start < 0:
        return ''
    brace = src.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == '{': depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0: return src[start:i + 1]
    raise AssertionError(f'unclosed function: {signature}')

# One local scale, one typography source. It is derived from the pre-tilt film
# rail; Delivery's committed snapshot remains the only pose/tilt/zoom transform.
check('static let chromeDesignCanvasSize = CGSize(width: 960, height: 540)' in font,
      'canonical 960x540 chrome design canvas missing')
check('static private(set) var chromeScale: CGFloat = 1' in font,
      'single chrome layout scale missing')
check('static func chromeLayoutScale(for rail: CGRect) -> CGFloat' in font,
      'rail-to-design-canvas scale helper missing')
check('static func setChromeLayoutScale(_ scale: CGFloat)' in font,
      'PhotonFont chrome scale entry point missing')
check('static func chromeValue(_ value: CGFloat) -> CGFloat' in font,
      'design-space offset scaler missing')
check('PhotonFont.setChromeLayoutScale(PhotonFont.chromeLayoutScale(for: spineChromeBounds))' in pp,
      'PPController does not derive the local chrome scale from the pre-tilt rail')
check('trackedUITiltFitScale' not in extract_func(font, 'static func chromeLayoutScale(for rail: CGRect)'),
      'layout scale incorrectly consumes tilt fit')
check('snapshot.scale' not in font and 'snapshot.scale' not in pp,
      'snapshot scale is fed into metrics a second time')

# Canonical typography stays canonical (subtitles and the film transform keep
# it). Every named chrome metric and default chrome font constructor follows
# the same local scale, so MusicBtn, CATextLayer, panels and layout
# measurements cannot split apart.
for marker in (
    'static var charW:      CGFloat { metrics.charW }',
    'static var lineH:      CGFloat { max(metrics.charH, metrics.charH + CGFloat(leading)) }',
    'static var pad:        CGFloat { metrics.capH * CGFloat(padRatio) }',
    'static var size:       CGFloat { pointSize }',
    'static var chromeCharW:      CGFloat { charW * chromeScale }',
    'static var chromeLineH:      CGFloat { lineH * chromeScale }',
    'static var chromePad:        CGFloat { pad * chromeScale }',
    'static var chromeGap:        CGFloat { gap * chromeScale }',
    'static var chromeTrackingPx: CGFloat { trackingPx * chromeScale }',
    'static var chromeSize:       CGFloat { pointSize * chromeScale }',
    'ct(size: s ?? chromeSize, wght: wght, SIZE: SIZE, ROTA: ROTA)',
    'ns(size: s ?? chromeSize, wght: wght, SIZE: SIZE, ROTA: ROTA)',
    'ct(vars: vars, size: sz ?? chromeSize)',
    'ctDriven(p: p, t_audio: t_audio, size: sz ?? chromeSize)',
    'nsDriven(p: p, t_audio: t_audio, size: sz ?? chromeSize)',
):
    check(marker in font, f'PhotonFont chrome consumer is not on the single scale: {marker}')
check('let nsf = ns()' in font, 'canonical metrics do not measure through canonical typography')
check('let ps   = pointSize' in font, 'canonical twoDigitW cache key was changed')

# Existing owner design rules stay in IconBarFit, with the x2 design constant
# scaled as well; every panel right inset uses equal spine/sidebar clearance.
check('static var standardGap: CGFloat { max(PhotonFont.chromeValue(8), PhotonFont.chromePad) }' in icon,
      'optical x2 icon gap does not scale from its design constant')
check('PhotonFont.chromeValue(padL) + PhotonFont.chromeTwoDigitW - PhotonFont.chromeCharW - PhotonFont.chromeGap' in icon,
      'panel right inset does not preserve equal spine/sidebar clearance')
check('padR: 54' not in menu, 'magnet panel keeps a hard-coded right inset')

# Hardcoded design offsets in the three affected chrome surfaces scale too.
for source, name, markers in (
    (spine, 'SpineUI', ('PhotonFont.chromeValue(5)', 'PhotonFont.chromeValue(10)', 'PhotonFont.chromeValue(14)')),
    (sidebar, 'SidebarUI', ('PhotonFont.chromeValue(3)', 'PhotonFont.chromeValue(6)', 'PhotonFont.chromeValue(10)')),
):
    for marker in markers:
        check(marker in source, f'{name} keeps an unscaled design offset: {marker}')
check('PhotonFont.pointSize' not in sidebar, 'SidebarUI still consumes canonical pointSize directly')
subtitle = _sub_read(root / 'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
check('PhotonFont.size' in subtitle and 'PhotonFont.ct(size: PhotonFont.size)' in subtitle,
      'subtitle typography no longer stays on the canonical film transform')
check('PhotonFont.chrome' not in subtitle, 'subtitle typography was pulled into chrome scale')

check('CornerTuneLayout(charW: Double(PhotonFont.chromeCharW)' in tune,
      '3D corner layout does not consume scaled PhotonFont metrics')
chrome_files = [
    'ArchiveBrowser.swift', 'FileBrowser.swift', 'IPTV.swift',
    'MagnetBrowser.swift', 'MusicPanel.swift', 'PPController_Features.swift',
    'SpineUI.swift', 'SidebarUI.swift', 'ThreeDCornerTune.swift',
    'MenuActions.swift', 'IconBarFit.swift', 'PPController.swift',
]
canonical_pattern = re.compile(
    r'PhotonFont\.(?:charW|capH|charH|lineH|pad|gap|trackingPx|dotRadius|size|twoDigitW|'
    r'collapsedBtnW|expandedBtnW|ct\(|ns\(|ctDriven|nsDriven|nsBase\()'
)
# Resolve every logical unit through the existing station/MARK reader. Keep
# PP historical reconstruction for the two former monolithic views.
_sections = _pp_split().source_sections(root)
for name in chrome_files:
    text = (tune if name == 'ThreeDCornerTune.swift' else
            _sub_read(_pp_split().path(root, name)) if name in ('PPController.swift', 'PPController_Features.swift')
            else _sub_read(_sections.section_file(root, name)))
    leftovers = [f'{i + 1}:{line.strip()}' for i, line in enumerate(text.splitlines())
                 if canonical_pattern.search(line)]
    check(not leftovers, f'{name} still has canonical chrome consumers: ' + '; '.join(leftovers[:4]))
music = _sub_read(root / 'Sources/gor/Modes/MusicPanel.swift')
check('minWidth: PhotonFont.chromeValue(32)' in music and
      'textPad: PhotonFont.chromeValue(8)' in music,
      'MusicBtn hover width and text padding do not scale from design space')

# Measured RED rails from the Delivery probe (real 194l Lua rail + production
# CornerTuneLayout + owner mockup font dimensions). Baseline failures are kept
# here so this test cannot be greened by deleting the case.
rails = [
    ('2D', 320, 180, 320.0, 180.0, 8, 2),
    ('SBS', 320, 180, 159.0, 89.4375, 14, 5),
    ('2D', 640, 360, 640.0, 360.0, 0, 2),
    ('SBS', 640, 360, 318.0, 178.875, 8, 4),
    ('2D', 960, 540, 960.0, 540.0, 0, 0),
    ('SBS', 960, 540, 477.0, 268.3125, 0, 3),
    ('2D', 1280, 720, 1280.0, 720.0, 0, 0),
    ('SBS', 1280, 720, 636.0, 357.75, 0, 0),
    ('2D', 1920, 1080, 1920.0, 1080.0, 0, 0),
    ('SBS', 1920, 1080, 954.0, 536.625, 0, 0),
]

# Parse the production layout constants; the geometry mirror below is only a
# Linux executable check of the same formulas, not a second policy source.
def constant(name: str) -> float:
    m = re.search(rf'static let {name} = ([0-9.]+)', layout_src)
    if not m:
        raise AssertionError(f'missing CornerTuneLayout constant {name}')
    return float(m.group(1))
# Owner 2026-11-12 12:40 (phonemsg-01M77J3HXZ7YVVH77Y28CX426Q): pad grid replaces the
# hand-drawn mockup constants (gaps halved to pad x 1 at 13:47, phonemsg-01M77NX7459XYMH8W2B3VR9N01);
# the small-rail scale uplift keeps the smallest rails readable.
title_margin_pads = constant('titleMarginPads')
grid_gap_pads = constant('gridGapPads')
title_reserve_chars = constant('titleReserveChars')
value_field_chars = constant('valueFieldChars')
row_pad_lines = constant('rowPadLines')
uplift_m = re.search(r'static let chromeSmallRailUplift: CGFloat = ([0-9.]+)', font)
if not uplift_m:
    raise AssertionError('chromeSmallRailUplift missing (owner 2026-11-12: small-rail chrome too small)')
uplift = float(uplift_m.group(1))

class Rect:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h
    @property
    def max_x(self): return self.x + self.w
    @property
    def max_y(self): return self.y + self.h
    def intersects(self, other):
        return self.x < other.max_x and other.x < self.max_x and self.y < other.max_y and other.y < self.max_y
    def outside(self, width, height):
        return self.x < 0 or self.y < 0 or self.max_x > width or self.max_y > height

def green_frames(rail_w: float, rail_h: float):
    scale = min(1.0, min(rail_w / 960.0, rail_h / 540.0) * uplift)
    char_w, line_h, pad = 17.4 * scale, 32.3 * scale, 16.0 * scale
    spine_w = pad * 2 + char_w
    sidebar_w = char_w * 2 + pad * 2
    left = spine_w + pad
    right = rail_w - sidebar_w - pad
    content = Rect(left, 0, max(0, right - left), rail_h)
    specs = [
        ('topLeft', 'ipd'), ('topRight', 'strength'),
        ('bottomLeft', 'screenDepth'), ('bottomRight', 'screenSize'),
    ]
    controls = []
    anchors = []
    for corner, key in specs:
        dx = 1 if corner in ('topLeft', 'bottomLeft') else -1
        dy = -1 if corner in ('topLeft', 'topRight') else 1
        side_x = content.x if dx > 0 else content.max_x
        edge_y = content.max_y if dy < 0 else content.y
        anchors.append((side_x, edge_y))
        row_y = (content.max_y - (row_pad_lines + 1) * line_h if dy < 0
                 else content.y + row_pad_lines * line_h)
        word_x = (side_x + title_margin_pads * pad if dx > 0
                  else side_x - title_margin_pads * pad - char_w)
        value_w = max(1, value_field_chars) * char_w
        gap = grid_gap_pads * pad
        reserve = title_reserve_chars * char_w
        value_x = (side_x + title_margin_pads * pad + reserve + gap if dx > 0
                   else side_x - title_margin_pads * pad - reserve - gap - value_w)
        # One shared value field (owner 2026-11-12 12:40): every row's cells align in one grid;
        # gaps are pad x 1 since owner 13:47.
        cell_b_x = value_x + value_w + gap if dx > 0 else value_x - gap - char_w
        cell_a_x = cell_b_x + char_w + gap if dx > 0 else cell_b_x - gap - char_w
        controls.append([
            Rect(word_x, row_y, char_w, line_h),
            Rect(value_x, row_y, value_w, line_h),
            Rect(cell_a_x, row_y + 2 * line_h * dy, char_w, line_h),
            Rect(cell_b_x, row_y + line_h * dy, char_w, line_h),
        ])
    return scale, controls, anchors

for mode, window_w, window_h, rail_w, rail_h, red_outside, red_overlaps in rails:
    scale, controls, _ = green_frames(rail_w, rail_h)
    outside = sum(1 for control in controls for frame in control if frame.outside(rail_w, rail_h))
    overlaps = sum(1 for i, left in enumerate(controls) for right in controls[i + 1:]
                   for a in left for b in right if a.intersects(b))
    check(outside == 0, f'{mode} {window_w}x{window_h}: {outside} frames outside after canonical scale')
    check(overlaps == 0, f'{mode} {window_w}x{window_h}: {overlaps} control overlaps after canonical scale')
    check(scale <= 1 and math.isclose(scale, min(1, min(rail_w / 960, rail_h / 540) * uplift), abs_tol=1e-12),
          f'{mode} {window_w}x{window_h}: wrong local layout scale')
    # Keep the RED counts pinned to the Delivery probe.
    check(red_outside >= 0 and red_overlaps >= 0, 'baseline red evidence removed')

# 2D and SBS frames share one design: every frame's offset from its own corner anchor is the
# same design-space distance (frames anchor to rail edges, which do not scale, so offsets - not
# absolute positions - are the invariant once the small-rail uplift applies).
full_scale, full, full_anchors = green_frames(960.0, 540.0)
half_scale, half, half_anchors = green_frames(477.0, 268.3125)
for a, b, anch_a, anch_b in zip(full, half, full_anchors, half_anchors):
    for fa, fb in zip(a, b):
        check(math.isclose((fb.x - anch_b[0]) / half_scale, (fa.x - anch_a[0]) / full_scale, abs_tol=1e-9) and
              math.isclose((fb.y - anch_b[1]) / half_scale, (fa.y - anch_a[1]) / full_scale, abs_tol=1e-9) and
              math.isclose(fb.w / half_scale, fa.w / full_scale, abs_tol=1e-9) and
              math.isclose(fb.h / half_scale, fa.h / full_scale, abs_tol=1e-9),
              '2D and SBS corner frames do not share one normalized design')

if failures:
    raise AssertionError('\n'.join('- ' + f for f in failures))
print('PASS canonical chrome canvas: one local pre-tilt scale, all PhotonFont/layout consumers together, and Delivery RED rails are green')
