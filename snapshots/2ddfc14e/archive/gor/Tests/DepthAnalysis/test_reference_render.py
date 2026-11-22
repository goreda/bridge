"""Reference render: stereo math + fill invariants, golden SBS hashes, and a
full entry-dir round trip (depth/source mp4 -> SBS). The pinned hashes make
the Python reference deterministic; the Mac Swift renderer must match the
manifest this same code emits on real footage (golden_manifest)."""
import json
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))
from prepare_film import (D_SCALE, V_INV_MAX, write_depth_hevc,  # noqa: E402
                          write_source_hevc)
from reference_render import (eye_n_for, golden_manifest,  # noqa: E402
                              render_frame_sbs, render_shot_sbs, theta_h_for)

H, W = 36, 64


def _craft():
    rng = np.random.default_rng(190)
    z = np.zeros((H, W))
    z[:, :] = 1.0 + (np.add.outer(np.arange(H), np.arange(W)) % 17) * 0.25
    z[4:8, 4:12] = 0.0           # masked block
    z[20:, 40:] = 0.4            # near foreground corner
    rgb = rng.integers(0, 256, (H, W, 3), dtype=np.uint8)
    return z, rgb


def test_math_invariants():
    z, rgb = _craft()
    th = math.radians(90.0)
    sbs = render_frame_sbs(rgb, z, th, ipd=0.063, convergence_m=2.0)
    assert sbs.shape == (H, 2 * W, 3) and sbs.dtype == np.uint8
    left, right = sbs[:, :W], sbs[:, W:]
    # both eyes paint something; masked sources never write on their own
    assert left.sum() > 0 and right.sum() > 0
    # swapEyes exchanges the halves (conv flips sign -> not identical pairs)
    sbs_sw = render_frame_sbs(rgb, z, th, ipd=0.063, convergence_m=2.0,
                              swap_eyes=True)
    assert not np.array_equal(sbs_sw[:, :W], left)
    # ipd=0, no convergence: both eyes identical (self-occlusion independent)
    sbs0 = render_frame_sbs(rgb, z, th, ipd=0.0, convergence_m=None)
    assert np.array_equal(sbs0[:, :W], sbs0[:, W:])
    print("PASS invariants: shapes, swapEyes diverges, ipd=0 eyes identical")


def test_zbuffer_near_wins():
    z, rgb = _craft()
    # force one source pixel on top of another: constant z plane with a
    # near square; render at low out res so warps collide
    z2 = np.full((H, W), 2.0)
    z2[8:16, 8:16] = 0.5
    sbs = render_frame_sbs(rgb, z2, math.radians(120.0), out_w=16, out_h=16)
    left = sbs[:, :16]
    # a near-square source colour must survive (z-buffer nearest wins;
    # equal-depth ties inside the square are stable-order, so check the set)
    near_colours = rgb[8:16, 8:16].reshape(-1, 3)
    hits = sum(((left == c).all(axis=-1)).any() for c in near_colours)
    assert hits > 0, "no near-square colour survived the warp"
    print("PASS z-buffer: nearest sample wins collisions")


def test_plane_known_disparity():
    """Mathematically known case: fronto-parallel plane at z0, no
    convergence. A point at world (0,0,z0) (source centre pixel) projects
    to lon = atan2(+-ipd/2, z0) per eye; expected SBS column offset between
    the halves is du = 2*atan(ipd/(2*z0))/pi * OW, left eye's copy landing
    du/2 RIGHT of its half-centre, right eye's du/2 LEFT of its centre
    (normal order; swapEyes inverts). Pins eye direction AND magnitude."""
    ipd, z0, ow, oh = 0.063, 2.0, 160, 90
    rgb = np.zeros((H, W, 3), np.uint8)
    rgb[:, W // 2] = [255, 0, 0]          # centre column, one pixel wide
    z = np.full((H, W), z0)
    th = math.radians(90.0)
    sbs = render_frame_sbs(rgb, z, th, ipd=ipd, convergence_m=None,
                           out_w=ow, out_h=oh)
    expect = 2.0 * math.atan(ipd / (2.0 * z0)) / math.pi * ow
    for half, side in ((sbs[:, :ow], +1), (sbs[:, ow:], -1)):
        cols = np.flatnonzero((half[:, :, 0] == 255).any(axis=0))
        assert len(cols) > 0, "red column missing from eye"
        c = cols.mean()
        pred = ow / 2 + side * expect / 2
        assert abs(c - pred) <= 1.5, (side, c, pred, expect)
    sbs_sw = render_frame_sbs(rgb, z, th, ipd=ipd, convergence_m=None,
                              out_w=ow, out_h=oh, swap_eyes=True)
    for half, side in ((sbs_sw[:, :ow], -1), (sbs_sw[:, ow:], +1)):
        cols = np.flatnonzero((half[:, :, 0] == 255).any(axis=0))
        assert abs(cols.mean() - (ow / 2 + side * expect / 2)) <= 1.5
    print(f"PASS known plane: z={z0}m ipd={ipd} -> disparity "
          f"{expect:.2f}px, direction pinned, swapEyes inverts")


def test_plane_angular_extent():
    """A far plane fills exactly the shot's angular window of the 180 deg
    equirect: coverage fraction ~= (theta_h/pi) * (theta_v/pi) with theta_v
    from the same f. Proves the 'thin strip' on real footage is geometry
    (shot fov << 180 deg), not a warp/fill bug."""
    th = math.radians(90.0)
    f = (W / 2.0) / math.tan(th / 2.0)
    th_v = 2.0 * math.atan((H / 2.0) / f)
    z = np.full((H, W), 100.0)  # far: depth barely changes the angles
    rgb = np.full((H, W, 3), 200, np.uint8)
    # surround=off: coverage is a MAP-GEOMETRY metric (soft surround would
    # fill the whole canvas with the uniform colour and saturate it)
    sbs = render_frame_sbs(rgb, z, th, ipd=0.063, out_w=320, out_h=180,
                           surround="off")
    cov = (sbs[:, :320] > 0).mean()
    expect = (th / math.pi) * (th_v / math.pi)
    assert abs(cov - expect) < 0.03, (cov, expect)
    print(f"PASS angular extent: coverage {cov:.3f} == expected "
          f"{expect:.3f} for 90x{math.degrees(th_v):.0f} deg window")


def test_theta_h_mapping():
    """Pins against RenderPrefsValue.thetaH (RenderPrefsReader.swift):
    default 75, 0 = legacy shot fov, clamp 20..150, vertical cap 150 deg
    keeps the screen inside the canvas for tall aspects."""
    shot = math.radians(51.19)
    assert abs(theta_h_for(75.0, shot, 16 / 9) - math.radians(75.0)) < 1e-12
    assert theta_h_for(0.0, shot, 16 / 9) == shot          # legacy shot fov
    assert theta_h_for(-1.0, shot, 16 / 9) == shot
    assert theta_h_for(75.0, shot, 0.0) == shot            # invalid aspect
    assert abs(theta_h_for(5.0, shot, 16 / 9) - math.radians(20.0)) < 1e-12
    assert abs(theta_h_for(200.0, shot, 16 / 9) - math.radians(150.0)) < 1e-12
    # tall aspect: vertical cap bites below the 150 deg horizontal clamp
    cap = 2.0 * math.atan(math.tan(math.radians(75.0)) * 0.5)
    assert abs(theta_h_for(150.0, shot, 0.5) - cap) < 1e-12
    assert theta_h_for(150.0, shot, 0.5) < math.radians(150.0)
    print("PASS thetaH mapping == RenderPrefsValue.thetaH pins")


def test_eye_n_rule():
    """Pins ThreeDRenderCoordinator.eyeN: max(256, min(4096, even floor))."""
    assert eye_n_for(360) == 360 and eye_n_for(361) == 360
    assert eye_n_for(100) == 256 and eye_n_for(5000) == 4096
    assert eye_n_for(1080) == 1080
    print("PASS eyeN rule == ThreeDRenderCoordinator.eyeN")


def test_surround_soft():
    # E-G ef1581d2 (s3d_surround): canvas pixels OUTSIDE the film footprint
    # (direction with conv removed, eye offset ignored, not landing in the
    # source frustum) get the edge-clamped 5x5 source mean, tap step
    # max(1, max(W,H)/64). Pin the vectorised port in reference_render
    # against E-G's loop reference (tools/vr180_render_ref.surround_soft).
    sys.path.insert(0, os.path.abspath(os.path.join(
        os.path.dirname(__file__), "..", "..", "tools")))
    from vr180_render_ref import surround_soft
    rng = np.random.default_rng(7)
    h, w = 72, 128
    rgb = rng.integers(0, 256, (h, w, 3), dtype=np.uint8)
    z = np.full((h, w), 2.0)
    th = math.radians(75.0)
    ow = oh = 90
    ipd, conv_m = 0.063, 2.0
    kw = dict(ipd=ipd, convergence_m=conv_m, swap_eyes=True,
              out_w=ow, out_h=oh)
    base = render_frame_sbs(rgb, z, th, surround="off", **kw)
    mine = render_frame_sbs(rgb, z, th, surround="soft", **kw)
    ref = base.copy()
    for e, sign in enumerate([1.0, -1.0]):  # swapEyes order
        conv = math.atan2(sign * ipd / 2.0, conv_m)
        eye_img = ref[:, e * ow:(e + 1) * ow].copy()
        surround_soft(rgb, th, conv, ow, oh, eye_img)
        ref[:, e * ow:(e + 1) * ow] = eye_img
    # s11 tolerance: inside footprint byte-identical, outside +-1 LSB
    # (float summation order differs between the two mirrors)
    diff = np.abs(mine.astype(int) - ref.astype(int))
    assert diff.max() <= 1, f"surround mismatch vs E-G loop ref: {diff.max()} LSB"
    print(f"PASS surround: vectorised == E-G loop ref within 1 LSB "
          f"(max {int(diff.max())}, {int((diff > 0).sum())} px)")

    dflt = render_frame_sbs(rgb, z, th, **kw)
    assert np.array_equal(dflt, mine), "default surround must be soft"
    print("PASS surround: default is soft")

    # inside-footprint pixels identical between off and soft; all changed
    # pixels lie outside the footprint (formula from E-G's spec)
    oy, ox = np.mgrid[0:oh, 0:ow].astype(np.float64)
    f = (w / 2.0) / math.tan(th / 2.0)
    changed = (base != mine).any(axis=2)
    assert changed.any(), "surround had no effect"
    for e, sign in enumerate([1.0, -1.0]):  # per-eye footprint (own conv)
        conv = math.atan2(sign * ipd / 2.0, conv_m)
        lon = ((ox + 0.5) / ow - 0.5) * math.pi - conv
        lat = (0.5 - (oy + 0.5) / oh) * math.pi
        dx, dy = np.sin(lon) * np.cos(lat), np.sin(lat)
        dz = np.cos(lon) * np.cos(lat)
        dzc = np.maximum(dz, 1e-4)
        sx, sy = f * dx / dzc + w * 0.5, h * 0.5 - f * dy / dzc
        eye_in = (dz > 0) & (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
        b_e, m_e = base[:, e * ow:(e + 1) * ow], mine[:, e * ow:(e + 1) * ow]
        assert np.array_equal(b_e[eye_in], m_e[eye_in]), \
            "inside-footprint pixels must be byte-identical to surround off"
        assert not changed[:, e * ow:(e + 1) * ow][eye_in].any()
    print("PASS surround: inside footprint byte-identical, "
          f"changed px all outside ({int(changed.sum())} px)")


def test_entry_mini_fixture():
    """The committed parity fixture (golden/entry_mini) must reproduce its
    manifest exactly through the decode path - this is the hash the Mac
    lane's Swift renderer is checked against."""
    import json as _json
    ed = os.path.normpath(os.path.join(
        os.path.dirname(__file__), "..", "..", "tools", "depth_analysis",
        "golden", "entry_mini"))
    man = _json.load(open(os.path.join(ed, "manifest.json")))
    frames, info = render_shot_sbs(ed, 0, ipd=0.063, convergence_m=2.0,
                                   swap_eyes=True)
    chk = golden_manifest(frames, info)
    assert chk["sequence_sha256"] == man["sequence_sha256"]
    assert chk["frame_sha256"] == man["frame_sha256"]
    assert info["out_w"] == info["out_h"] == 256  # eyeN floor for 36px src
    print("PASS entry_mini fixture roundtrip:",
          man["sequence_sha256"][:12])


def test_golden_hash():
    z, rgb = _craft()
    th = math.radians(90.0)
    sbs = render_frame_sbs(rgb, z, th, ipd=0.063, convergence_m=2.0)
    import hashlib
    h = hashlib.sha256(sbs.tobytes()).hexdigest()
    assert h == "e86723ada4bd4c6699800e2046665bbe91553a2e1ae4b97bc22ffb40ac84f71a", h
    print(f"PASS golden hash: {h[:12]}...")


def test_entry_roundtrip():
    z, rgb = _craft()
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "src.mp4")
        raw = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-f", "rawvideo", "-s", f"{W}x{H}",
             "-pix_fmt", "rgb24", "-framerate", "24", "-i", "-",
             "-frames:v", "2", "-vf", "format=yuv420p", "-c:v", "libx265",
             "-preset", "fast", "-crf", "18", "-y", src],
            stdin=subprocess.PIPE)
        raw.communicate(np.stack([rgb, rgb]).tobytes())
        assert raw.returncode == 0
        entry = os.path.join(td, "entry"); os.makedirs(entry)
        inv = np.where(z > 0, D_SCALE / np.maximum(z, 1e-9), 0.0)
        inv = np.clip(inv, 0, V_INV_MAX).astype(np.float32)
        write_depth_hevc(os.path.join(entry, "depth_shot_00000.mp4"),
                         np.stack([inv, inv]), fps=24.0, start_frame=0)
        json.dump({"depth_width": W, "depth_height": H, "frames": 2,
                   "start_frame": 0, "fps": 24.0, "start_pts": 0.0,
                   "source_width": W, "source_height": H},
                  open(os.path.join(entry, "depth_shot_00000.json"), "w"))
        write_source_hevc(os.path.join(entry, "source_shot_00000.mp4"),
                          src, 0, 2, 24.0)
        json.dump({"shots": [{"shot": 0, "start": 0, "end": 2, "frames": 2,
                              "median_hfov_deg": 90.0, "median_vfov_deg": 55.0,
                              "hfov_deg": 90.0, "vfov_deg": 55.0,
                              "confidence": 1.0}]},
                  open(os.path.join(entry, "fov_track.json"), "w"))
        frames, info = render_shot_sbs(entry, 0, ipd=0.063, convergence_m=2.0)
        # default output = square eyeN x eyeN eyes from the source height
        assert frames.shape == (2, 256, 512, 3)
        assert info["shot_hfov_deg"] == 90.0 and info["start_pts"] == 0.0
        # default screen_deg 75 -> theta_h 75 deg (aspect 64/36 under cap)
        assert abs(info["theta_h_deg"] - 75.0) < 1e-9
        man = golden_manifest(frames, info)
        assert len(man["frame_sha256"]) == 2 and len(man["sequence_sha256"]) == 64
        assert frames.sum() > 0
        print("PASS entry roundtrip: 2 frames -> SBS, manifest emitted")


if __name__ == "__main__":
    test_math_invariants()
    test_plane_known_disparity()
    test_theta_h_mapping()
    test_eye_n_rule()
    test_surround_soft()
    test_entry_mini_fixture()
    test_plane_angular_extent()
    test_zbuffer_near_wins()
    test_golden_hash()
    test_entry_roundtrip()
