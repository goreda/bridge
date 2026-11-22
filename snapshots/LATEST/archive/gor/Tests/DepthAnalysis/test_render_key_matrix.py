"""Render cache key state matrix (CONTRACT-190v s33).

Mirror of ThreeDRenderCoordinator.key (Sources/gor/
ThreeDRenderCoordinator.swift, v2) and the pixel-relevance semantics of
RenderPrefsValue + ShotComfort on the render path. Rule under test
(Main 11:04): every user-visible setting that changes pixels must
change the key; none that doesn't may.

Matrix verdict (this test pins the CURRENT v2 key behaviour, gaps
included, so an E-G key fix flips exactly the KNOWN_GAP rows):
- PASS rows: mode, strength (menu path), comfort toggle, explicit
  convergence, screenDeg (wide content), surround, osdLine, subtitles
  all behave correctly.
- KNOWN_GAP F1 (collision): comfort-capped regime (depth_scale > 1
  with over_budget = false - file-only, the menu ties over_budget to
  strength > 1): comfortIPD = ipdM * c.depthScale depends on ipdM
  beyond effectiveIPD = ipdM*depthScale; two states with equal
  effectiveIPD but different ipdM produce different pixels under the
  SAME key.
- KNOWN_GAP F2 (churn): in the same capped regime, moving strength
  (2 -> 3) changes effectiveIPD hence the key, but not the pixels
  (strengthFactor is clamped to 1).
- KNOWN_GAP F3 (collision via content): the menu 'quality' setting
  steers PREPARE (depth content); the render key has no depth-version
  component, so re-prepared depth under a new quality reuses a stale
  render.
- ACCEPTED: screenDeg values past the portrait vertical cap share one
  thetaH (key churn, portrait content only); mode sbs renders as vr180
  today (key churn while no sbs-specific output exists).
Recommended v3 key (contract s33): key on ipdM and
strengthFactor(depthScale, overBudget) when comfortActive (not
effectiveIPD + the ob flag), effectiveIPD when fixed, plus a depth
entry version.

Run: python3 Tests/DepthAnalysis/test_render_key_matrix.py
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m


def strength_factor(strength, over_budget):
    if not (strength > 0):
        return 0.0
    return strength if over_budget else min(strength, 1.0)


class Prefs:
    """RenderPrefsValue mirror (relevant fields only)."""

    def __init__(self, mode="vr180", depth_scale=1.0, ipd_m=0.063,
                 convergence_m=None, screen_deg=75.0, surround_soft=True,
                 comfort=True, over_budget=False):
        self.mode = mode
        self.depth_scale = depth_scale
        self.ipd_m = ipd_m
        self.convergence_m = convergence_m
        self.screen_deg = screen_deg
        self.surround_soft = surround_soft
        self.comfort = comfort
        self.over_budget = over_budget

    @property
    def comfort_active(self):
        return self.comfort and self.convergence_m is None

    @property
    def effective_ipd(self):
        return self.ipd_m * self.depth_scale

    def comfort_ipd(self, c_depth_scale):
        return (self.ipd_m * c_depth_scale
                * strength_factor(self.depth_scale, self.over_budget))


def key_v2(p, eye_n=720, codec="hevc", swap=True):
    """Verbatim mirror of ThreeDRenderCoordinator.key (v2)."""
    c = ("comfort+ob" if p.over_budget else "comfort") \
        if p.comfort_active else "fixed"
    conv = str(p.convergence_m) if p.convergence_m is not None else "nil"
    return (f"v2|{c}|{p.mode}|{p.effective_ipd}|{conv}|{eye_n}|{codec}"
            f"|{swap}|{p.screen_deg}|{p.surround_soft}")


def key_v3(p, eye_n=720, codec="hevc", swap=True, depth_stamp="d100-1"):
    """Verbatim mirror of ThreeDRenderCoordinator.key (v3, s33 fix) + depthStamp."""
    if p.comfort_active:
        ipd = f"comfort|ipd{p.ipd_m}|sf{strength_factor(p.depth_scale, p.over_budget)}"
    else:
        ipd = f"fixed|ipd{p.effective_ipd}"
    conv = str(p.convergence_m) if p.convergence_m is not None else "nil"
    return (f"v3|{ipd}|{p.mode}|{conv}|{eye_n}|{codec}|{swap}|{p.screen_deg}"
            f"|{p.surround_soft}|{depth_stamp}")


METHODS = ("mlbw_l2_inpaint_video", "mlbw_l2_inpaint", "row_flow_v3",
           "dibr_golden")  # 190w W3 tier order T1>T2>T3>fallback


def key_v4(p, method="mlbw_l2_inpaint_video", eye_n=720, codec="hevc",
           swap=True, depth_stamp="d100-1"):
    """Mirror of rehearsal.render_key_v4 / ThreeDRenderCoordinator.key v4
    (190w W3): v3 body plus the synthesis-method field after the version."""
    assert method in METHODS
    return "v4|" + method + "|" + key_v3(
        p, eye_n=eye_n, codec=codec, swap=swap, depth_stamp=depth_stamp)[3:]


def key_v5(p, **kw):
    """Mirror of rehearsal.render_key_v5 / Swift key v5 (E-G F3): span-p5p95 tag after the version."""
    return "v5|span-p5p95|" + key_v4(p, **kw)[3:]


def pixel_signature(p, c_depth_scale=0.5, aspect=16 / 9,
                    method="mlbw_l2_inpaint_video"):
    """What actually changes rendered pixels (render-path semantics).
    c_depth_scale: per-shot content value (ShotComfort), constant here
    because the key is compared within one entry."""
    if p.mode == "off":
        return ("off",)
    # sbs plays as vr180 for now (ThreeDRenderCoordinator.tick announce)
    mode = "vr180" if p.mode == "sbs" else p.mode
    import math
    # thetaH: screen_deg clamped [20,150], vertical cap at 150 deg
    h = min(max(p.screen_deg, 20.0), 150.0) * math.pi / 180.0 \
        if p.screen_deg > 0 else 0.0
    h_cap = 2.0 * math.atan(math.tan(math.radians(150.0) / 2.0) * aspect)
    theta_h = min(h, h_cap) if h > 0 else 0.0
    if p.comfort_active:
        ipd = p.comfort_ipd(c_depth_scale)
        conv = "shot-comfort"
    else:
        ipd = p.effective_ipd
        conv = p.convergence_m
    return (mode, ipd, conv, theta_h, p.surround_soft, method)


def check(name, a, b, expect_same_pixels, aspect=16 / 9):
    ka, kb = key_v4(a), key_v4(b)
    sa, sb = pixel_signature(a, aspect=aspect), pixel_signature(b, aspect=aspect)
    same_px = sa == sb
    assert same_px == expect_same_pixels, (name, "pixel model wrong")
    return ka == kb, same_px


def main():
    base = Prefs()
    rows = []

    def row(name, a, b, same_px, want_same_key, gap=None, aspect=16 / 9):
        same_key, same_pixels = check(name, a, b, same_px, aspect=aspect)
        ok = (same_key == want_same_key)
        rows.append((name, same_pixels, same_key, ok, gap))
        return ok

    # --- correct behaviour -------------------------------------------
    row("mode off->vr180", Prefs(mode="off"), Prefs(mode="vr180"),
        False, False)
    row("mode sbs->vr180 (renders identical today)", Prefs(mode="sbs"),
        Prefs(mode="vr180"), True, True, gap="ACCEPTED churn (placeholder)")
    row("strength 0.5->0.8 (under cap, comfort)", base,
        Prefs(depth_scale=0.8), False, False)
    row("strength 1.0->2.0 (menu path: ob follows)", base,
        Prefs(depth_scale=2.0, over_budget=True), False, False)
    row("comfort on->off", base, Prefs(comfort=False), False, False)
    row("convergence nil->2.0", base, Prefs(convergence_m=2.0), False,
        False)
    row("convergence 2.0->3.0", Prefs(convergence_m=2.0),
        Prefs(convergence_m=3.0), False, False)
    row("screenDeg 75->90 (wide)", base, Prefs(screen_deg=90.0), False,
        False)
    row("surround soft->off", base, Prefs(surround_soft=False), False,
        False)
    row("screenDeg 130->150 (portrait cap)", Prefs(screen_deg=130.0),
        Prefs(screen_deg=150.0), True, True,
        gap="ACCEPTED churn (portrait vertical cap)", aspect=9 / 16)
    # osdLine and subtitles never reach the key function (not args) and
    # never the render mp4 (OSD / mpv overlay) - nothing to test inside
    # key_v2; pinned here as documentation.

    # --- KNOWN_GAP F1: capped-comfort ipdM collision ------------------
    row("F1 capped comfort: (ipdM .063, ds 2, ob f) vs (ipdM .126, ds 1, ob f)",
        Prefs(depth_scale=2.0, over_budget=False),
        Prefs(depth_scale=1.0, ipd_m=0.126, over_budget=False),
        False, False, gap="F1 FIXED in v3")

    # --- KNOWN_GAP F2: capped-comfort strength churn ------------------
    row("F2 capped comfort: strength 2->3 (ob f)",
        Prefs(depth_scale=2.0, over_budget=False),
        Prefs(depth_scale=3.0, over_budget=False),
        True, True, gap="F2 FIXED in v3")
    # F3: same prefs, depth re-prepared (stamp changes) -> pixels may differ -> key must differ
    ka, kb = key_v3(Prefs(), depth_stamp="d100-1"), key_v3(Prefs(), depth_stamp="d100-2")
    assert ka != kb, "F3: a re-prepared depth container must change the key"
    assert key_v3(Prefs(), depth_stamp="d100-1") == key_v3(Prefs(), depth_stamp="d100-1")
    rows.append(("F3 depth re-prepared (stamp changes)", False, False, True, "F3 FIXED in v3"))

    fails = 0
    for name, same_px, same_key, ok, gap in rows:
        want = "same" if same_px else "diff"
        verdict = ("OK   " if ok else "GAP  ")
        print(f"  {verdict} pixels {want:4s} key {'same' if same_key else 'diff':4s}"
              f"  {name}" + (f"   [{gap}]" if gap else ""))
        if not ok and gap is None:
            fails += 1
        elif not ok and gap and gap.startswith("KNOWN_GAP"):
            fails += 0  # pinned gaps below
    # v3 fixes: F1 no longer collides, F2 no longer churns (both asserted by the rows above); v2 still collides/churns as reviewed
    assert key_v2(Prefs(depth_scale=2.0)) == key_v2(Prefs(depth_scale=1.0, ipd_m=0.126)), "v2 reference changed"
    assert key_v3(Prefs(depth_scale=2.0)) != key_v3(Prefs(depth_scale=1.0, ipd_m=0.126))
    assert key_v3(Prefs(depth_scale=2.0)) == key_v3(Prefs(depth_scale=3.0))
    # menu path unchanged: over-budget strength 1 -> 2 and 2 -> 3 still change the key AND the pixels
    assert key_v3(Prefs(depth_scale=2.0, over_budget=True)) != key_v3(Prefs(depth_scale=3.0, over_budget=True))
    assert key_v3(Prefs(depth_scale=1.0)) != key_v3(Prefs(depth_scale=2.0, over_budget=True))
    # v4 (190w W3): method field changes the key and the pixels; the bump
    # invalidates every v3-keyed cache
    assert key_v4(Prefs(), method="mlbw_l2_inpaint_video") != key_v4(Prefs(), method="mlbw_l2_inpaint")
    assert key_v4(Prefs(), method="row_flow_v3") != key_v4(Prefs(), method="dibr_golden")
    assert pixel_signature(Prefs(), method="mlbw_l2_inpaint_video") != pixel_signature(Prefs(), method="dibr_golden")
    assert key_v4(Prefs()) != key_v3(Prefs())
    assert key_v4(Prefs()).startswith("v4|mlbw_l2_inpaint_video|comfort|")
    assert pixel_signature(Prefs(), method="mlbw_l2_inpaint") == pixel_signature(Prefs(), method="mlbw_l2_inpaint")
    # swift mirror pin: the source carries the key shape and the stamp
    # (v4 spec handed to E-G 190w; E-G's Swift edit landed at 15b0e877/fcdb873e,
    # pin tightened to v4-only)
    import pathlib, re
    sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(pathlib.Path(__file__).resolve().parents[2])).read_text())
    # v5 (E-G F3 17:21): span-p5p95 tag; invalidates every v4 render
    assert key_v5(Prefs()).startswith("v5|span-p5p95|mlbw_l2_inpaint_video|comfort|")
    assert key_v5(Prefs()) != key_v4(Prefs())
    assert key_v5(Prefs(), method="row_flow_v3") != key_v5(Prefs(), method="dibr_golden")
    v5_landed = '"v5|span-p5p95|' in sw
    print("swift key shape:", "v5" if v5_landed else "v4 (v5 not on this checkout yet)")
    assert v5_landed or '"v4|' in sw, 'render key must be v4 or v5'
    for frag in (('"v5|span-p5p95|\\(method' if v5_landed else '"v4|\\(method'),
                 'comfort|ipd\\(p.ipdM)|sf\\(ShotComfort.strengthFactor(p.depthScale, overBudget: p.overBudget))', 'fixed|ipd\\(p.effectiveIPD)', 'static func depthStamp', 'baseKey + Self.depthStamp'):
        assert frag in sw, frag
    assert fails == 0, f"{fails} unreviewed matrix violations"
    print(f"matrix: {len(rows)} rows, v3 key: F1/F2/F3 fixed")
    print("ALL RENDER KEY MATRIX TESTS PASS")


if __name__ == "__main__":
    main()
