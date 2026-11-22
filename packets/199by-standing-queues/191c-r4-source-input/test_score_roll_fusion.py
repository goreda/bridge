#!/usr/bin/env python3
"""Regression tests for score_roll_fusion.py (191c R4 Task 3).

All captures here are SYNTHETIC TEST FIXTURES rendered by a Python reference
renderer (PIL), labelled synthetic: they are not mpv output, not Mac/GPU
evidence, and prove nothing about production rendering. They exercise the
scorer's matching, conventions, gating and refusals. Real-mpv scoring is
NOT_RUN end to end here (pinned shader repo is private to the runner lane).
"""
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_roll_fusion as S

HERE = os.path.dirname(os.path.abspath(__file__))
PART1_DIR = os.environ.get(
    "ROLL_MARKERS_DIR",
    os.path.join(HERE, "fixtures", "packets", "191c-roll-fusion"))
PART1_MANIFEST = os.path.join(PART1_DIR, "fixtures", "manifest.json")
BG = (12, 12, 12)
OUT_W, OUT_H = 2560, 1600
SYN_SHADER_SHA = hashlib.sha256(
    b"synthetic test binding; not real shader bytes").hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ------------------------- synthetic reference renderer ----------------------

def _eye_crops(fx, src):
    """Per-eye logical crops, honoring SAR; mono synthesizes a shifted right
    eye (production d3 modelled as a constant horizontal shift)."""
    sar = fx["sample_aspect_ratio"]
    out = {}
    if "mono" in fx["eyes"]:
        x, y, w, h = fx["eyes"]["mono"]
        d3 = 30
        out["left"] = src.crop((x, y, x + w, y + h))
        out["right"] = src.crop((x + d3, y, x + d3 + w, y + h))
    else:
        for eye in ("left", "right"):
            x, y, w, h = fx["eyes"][eye]
            out[eye] = src.crop((x, y, x + w, y + h))
    if sar[0] != sar[1]:
        for eye, c in out.items():
            out[eye] = c.resize((c.width * sar[0] // sar[1], c.height),
                                Image.BICUBIC)
    return out


def render_capture(fx, roll_deg, crossed=False, mutant=None):
    """Render a synthetic 2560x1600 window capture.

    Correct model: each eye half is rotated about the half centre by
    -theta_eff (theta_eff = -roll_deg when crossed else roll_deg), so the
    inter-eye separation lands exactly on a(theta_eff). Mutants:
      'horizontal': never rotate (screen-horizontal separation, wrong
                    under roll)
      'image_y':    rotate by +theta_eff instead of -theta_eff (image-y
                    convention flip)
    """
    src = Image.open(os.path.join(PART1_DIR, "fixtures", fx["path"])).convert("RGB")
    canvas = Image.new("RGB", (OUT_W, OUT_H), BG)
    teff = (-roll_deg if crossed else roll_deg)
    ang = -teff if mutant != "image_y" else teff
    if mutant == "horizontal":
        ang = 0.0
    # eyes occupy the central 70% of each half (fov letterbox), so that
    # corner markers survive a rigid 30-degree roll of the composed pair
    sw, sh = int(OUT_W / 2 * 0.7), int(OUT_H * 0.7)
    for eye, crop in _eye_crops(fx, src).items():
        half = crop.resize((sw, sh), Image.BICUBIC)
        ox = (0 if eye == "left" else OUT_W // 2) + (OUT_W // 2 - sw) // 2
        canvas.paste(half, (ox, (OUT_H - sh) // 2))
    if ang:
        # correct roll model: the composed pair rotates rigidly about the
        # output centre, so the inter-eye separation lands on a(theta_eff)
        canvas = canvas.rotate(ang, resample=Image.BILINEAR,
                               center=(OUT_W / 2, OUT_H / 2), fillcolor=BG)
    return canvas


def cap_id(fx_id, mode, roll_deg, crossed=False, baseline=False):
    s = f"{fx_id}__{mode}__roll{'m' if roll_deg < 0 else 'p'}{abs(roll_deg):g}"
    if crossed:
        s += "__crossed"
    if baseline:
        s += "__baseline"
    return s


def make_world(tmp, manifest_path, fixture_ids, angles=S.REQUIRED_ANGLES_DEG,
               crossed_angles=S.CROSSED_ANGLES_DEG, mutant=None,
               mutant_angles=None, skip_captures=(), tamper_zero_roll=None,
               erase_marker=None, duplicate_marker=None):
    """Render a complete (unless asked otherwise) synthetic run + index.

    Returns (index_path, manifest_path). skip_captures: set of capture ids to
    omit. tamper_zero_roll: fixture id whose roll-0 run capture gets one
    pixel flipped vs baseline. erase_marker / duplicate_marker: (fixture_id,
    marker_id) applied to that fixture's +15 deg capture.
    """
    manifest = json.load(open(manifest_path))
    manifest["fixtures"] = [f for f in manifest["fixtures"]
                            if f["id"] in fixture_ids]
    sub_path = os.path.join(tmp, "manifest.json")
    with open(sub_path, "w") as f:
        json.dump(manifest, f)
    tsrc = os.path.join(os.path.dirname(manifest_path), "templates")
    if os.path.isdir(tsrc):
        os.symlink(tsrc, os.path.join(tmp, "templates"))
    caps_dir = os.path.join(tmp, "captures")
    os.makedirs(caps_dir)
    records = []
    env = {"evidence_class": "synthetic-linux", "clean_checkout": False,
           "toolchain": {"python": sys.version.split()[0], "renderer": "PIL"},
           "renderer_class": "software",
           "renderer_string": "synthetic-python-test-renderer (not mpv)",
           "mpv_binary_sha256": None}
    for fx in manifest["fixtures"]:
        mode = S.MODE_MAP[fx["mode"]]
        jobs = [(a, False, False) for a in angles]
        if fx.get("signed_disparity_fraction") == 0.0:
            jobs += [(a, True, False) for a in crossed_angles]
        jobs.append((0.0, False, True))
        for ang, crossed, baseline in jobs:
            cid = cap_id(fx["id"], mode, ang, crossed, baseline)
            if cid in skip_captures:
                records.append({"capture_id": cid, "fixture_id": fx["id"],
                                "fixture_sha256": fx["sha256"], "mode": mode,
                                "roll_deg": ang, "roll_rad": math.radians(ang),
                                "crossed": crossed, "zero_roll_baseline": baseline,
                                "pose_message": None, "effective_options": {},
                                "shader_sha256": SYN_SHADER_SHA,
                                "renderer_class": "software",
                                "status": "not_run",
                                "error": "omitted by test",
                                "image": None,
                                "acceptance_class": "smoke_not_evidence",
                                "golden_comparison": None,
                                "command": ["synthetic"]})
                continue
            m = mutant if (mutant_angles is None or ang in mutant_angles) else None
            img = render_capture(fx, ang, crossed, mutant=m)
            if erase_marker and erase_marker[0] == fx["id"] and ang == 15.0 \
                    and not crossed and not baseline:
                _erase_marker(img, fx, erase_marker[1])
            if duplicate_marker and duplicate_marker[0] == fx["id"] \
                    and ang == 15.0 and not crossed and not baseline:
                _duplicate_marker(img, fx, duplicate_marker[1])
            p = os.path.join(caps_dir, cid + ".png")
            img.save(p)
            records.append({"capture_id": cid, "fixture_id": fx["id"],
                            "fixture_sha256": fx["sha256"], "mode": mode,
                            "roll_deg": ang,
                            "roll_rad": round(math.radians(ang), 6),
                            "crossed": crossed, "zero_roll_baseline": baseline,
                            "pose_message": {"name": "synthetic-pose",
                                             "args": [ang]},
                            "effective_options": {"vr_roll": math.radians(ang)},
                            "shader_sha256": SYN_SHADER_SHA,
                            "renderer_class": "software",
                            "status": "captured", "error": None,
                            "image": {"path": os.path.relpath(p, tmp),
                                      "sha256": sha256_file(p),
                                      "width": OUT_W, "height": OUT_H},
                            "acceptance_class": "evidence",
                            "golden": None, "golden_comparison": None,
                            "command": ["synthetic"]})
    # golden carrier: an independently rendered zero-roll image bound on
    # the __baseline record (never the baseline capture image itself)
    gold_dir = os.path.join(tmp, "goldens")
    os.makedirs(gold_dir, exist_ok=True)
    for r in records:
        if r["zero_roll_baseline"] and r["status"] == "captured":
            fx = next(f for f in manifest["fixtures"]
                      if f["id"] == r["fixture_id"])
            gp = os.path.join(gold_dir, r["fixture_id"] + "__golden.png")
            render_capture(fx, 0.0).save(gp)
            r["golden"] = {"bound": True,
                           "golden_sha256": sha256_file(gp),
                           "golden_path": os.path.relpath(gp, tmp),
                           "shipping_shader_sha256": SYN_SHADER_SHA}
    if tamper_zero_roll:
        cid = cap_id(tamper_zero_roll, S.MODE_MAP[
            next(f["mode"] for f in manifest["fixtures"]
                 if f["id"] == tamper_zero_roll)], 0.0)
        p = os.path.join(caps_dir, cid + ".png")
        img = Image.open(p).convert("RGB")
        px = img.load()
        px[7, 7] = (255, 255, 255)
        img.save(p)
        for r in records:
            if r["capture_id"] == cid:
                r["image"]["sha256"] = sha256_file(p)
    index = {"schema": "roll-capture/v1", "created_utc": "synthetic-test",
             "runner": {"name": "synthetic-test-runner", "version": "0",
                        "sha256": "0" * 64},
             "environment": env,
             "source": {"repo": "zuellue/gorav-native-ci",
                        "commit": S.SOURCE_COMMIT, "path": S.SOURCE_PATH,
                        "expected_sha256": SYN_SHADER_SHA,
                        "actual_sha256": SYN_SHADER_SHA,
                        "git_blob_sha1": None,
                        "binding_status": "verified",
                        "provenance": "synthetic test binding; not real shader bytes"},
             "fixtures_manifest": {"schema": "roll-markers/v1",
                                   "path": "manifest.json",
                                   "sha256": sha256_file(sub_path)},
             "golden_comparison": {"status": "RUN"},
             "captures": records}
    idx_path = os.path.join(tmp, "index.json")
    with open(idx_path, "w") as f:
        json.dump(index, f)
    return idx_path, sub_path


def _marker_screen_pos(fx, marker_id, eye, roll_deg, crossed=False):
    """Predict the rendered screen position of a marker for tampering."""
    m = next(mk for mk in fx["markers"] if mk["id"] == marker_id)
    src_pos = m["positions"].get(eye) or m["positions"].get("mono")
    u, v = src_pos["eye_uv"]
    x = ((0.0 if eye == "left" else OUT_W / 2) + 0.15 * OUT_W / 2
         + u * 0.7 * OUT_W / 2)
    if eye == "right" and "mono" in fx["eyes"]:
        x += 30.0 * 0.7  # modelled d3 shift (source px, half scale 0.7)
    y = 0.15 * OUT_H + v * 0.7 * OUT_H
    th = math.radians((-roll_deg) if crossed else roll_deg)
    dx, dy = x - OUT_W / 2, y - OUT_H / 2
    rx = dx * math.cos(th) - dy * math.sin(th)
    ry = dx * math.sin(th) + dy * math.cos(th)
    return OUT_W / 2 + rx, OUT_H / 2 + ry


def _erase_marker(img, fx, marker_id):
    for eye in ("left", "right"):
        x, y = _marker_screen_pos(fx, marker_id, eye, 15.0)
        for ix in range(int(x) - 30, int(x) + 30):
            for iy in range(int(y) - 50, int(y) + 50):
                if 0 <= ix < img.width and 0 <= iy < img.height:
                    img.putpixel((ix, iy), BG)


def _duplicate_marker(img, fx, marker_id):
    x, y = _marker_screen_pos(fx, marker_id, "right", 15.0)
    m = next(mk for mk in fx["markers"] if mk["id"] == marker_id)
    col = tuple(m["identity_rgb"])
    for ix in range(int(x) - 80, int(x) - 60):
        for iy in range(int(y) - 8, int(y) + 8):
            img.putpixel((ix, iy), col)
    for ix in range(int(x) - 74, int(x) - 66):
        for iy in range(int(y) - 4, int(y) + 4):
            img.putpixel((ix, iy), (255, 255, 255))  # impostor needs a core


# ------------------------------ pure math tests -----------------------------

class TestMath(unittest.TestCase):
    def test_pairs_along_eye_axis_every_angle(self):
        for th in S.REQUIRED_ANGLES_DEG + S.CROSSED_ANGLES_DEG:
            a, _ = S.axis_vectors(th)
            p_l = (513.25, 301.75)
            p_r = (p_l[0] + 640.0 * a[0], p_l[1] + 640.0 * a[1])
            self.assertAlmostEqual(S.vertical_error(p_r, p_l, th), 0.0,
                                   places=9, msg=f"angle {th}")
            self.assertAlmostEqual(S.axial_separation(p_r, p_l, th), 640.0,
                                   places=9)

    def test_screen_horizontal_mutant_fails_under_roll(self):
        for th in (-30.0, -15.0, -5.0, 5.0, 15.0, 30.0):
            p_l, p_r = (100.0, 500.0), (740.0, 500.0)  # purely horizontal
            ev = S.vertical_error(p_r, p_l, th)
            self.assertGreater(abs(ev), S.TOLERANCE_PX,
                               f"horizontal separation must fail at {th} deg")
        self.assertAlmostEqual(S.vertical_error((740.0, 500.0),
                                                (100.0, 500.0), 0.0), 0.0)

    def test_crossed_sign_convention(self):
        th = 15.0
        a, _ = S.axis_vectors(-th)  # crossed: theta_eff = -roll_deg
        p_l = (200.0, 800.0)
        p_r = (p_l[0] + 640.0 * a[0], p_l[1] + 640.0 * a[1])
        self.assertAlmostEqual(S.vertical_error(p_r, p_l, -th), 0.0, places=9)
        self.assertGreater(abs(S.vertical_error(p_r, p_l, +th)),
                           S.TOLERANCE_PX,
                           "wrong rollSign must be detectable")
        rec = {"crossed": True, "roll_deg": th}
        self.assertEqual(S.theta_eff_deg(rec), -th)
        rec = {"crossed": False, "roll_deg": th}
        self.assertEqual(S.theta_eff_deg(rec), th)

    def test_image_y_mutant_fails(self):
        for th in (-30.0, -15.0, -5.0, 5.0, 15.0, 30.0):
            a, _ = S.axis_vectors(th)
            p_l = (200.0, 800.0)
            # separation along the y-flipped axis (screen-y-up confusion)
            p_r = (p_l[0] + 640.0 * a[0], p_l[1] - 640.0 * a[1])
            self.assertGreater(abs(S.vertical_error(p_r, p_l, th)),
                               S.TOLERANCE_PX, f"y-flip must fail at {th}")

    def test_over_one_px_vertical_error_detected(self):
        th = 15.0
        a, ap = S.axis_vectors(th)
        p_l = (200.0, 800.0)
        for off in (1.01, 1.5, -2.0):
            p_r = (p_l[0] + 640.0 * a[0] + off * ap[0],
                   p_l[1] + 640.0 * a[1] + off * ap[1])
            self.assertAlmostEqual(S.vertical_error(p_r, p_l, th), off,
                                   places=9)
            self.assertGreater(abs(off), S.TOLERANCE_PX)


class TestMatcher(unittest.TestCase):
    def _region(self, w=400, h=300):
        return np.full((h, w, 3), BG, dtype=np.float64)

    def test_colour_centroid_subpixel(self):
        reg = self._region()
        reg[100:120, 150:170] = (255, 96, 96)
        m = S.match_marker(reg, np.zeros((5, 5, 3)), (255, 96, 96))
        self.assertEqual(m["method"], "colour")
        self.assertAlmostEqual(m["x"], 159.5, places=6)
        self.assertAlmostEqual(m["y"], 109.5, places=6)

    def test_colour_duplicate_detected(self):
        reg = self._region()
        reg[100:120, 50:70] = (255, 96, 96)
        reg[100:120, 250:270] = (255, 96, 96)
        m = S.match_marker(reg, np.zeros((5, 5, 3)), (255, 96, 96))
        self.assertTrue(m["duplicate"])

    def test_unmatched_when_absent(self):
        reg = self._region()
        m = S.match_marker(reg, np.zeros((5, 5, 3)), (255, 96, 96))
        self.assertIsNone(m)

    def test_template_fallback(self):
        rng = np.random.default_rng(7)
        tmpl = rng.normal(128, 60, (17, 17, 3))
        reg = self._region() + rng.normal(0, 3, (300, 400, 3))
        reg[200:217, 250:267] = tmpl
        m = S.match_marker(reg, tmpl, (255, 96, 96))
        self.assertIsNotNone(m)
        self.assertEqual(m["method"], "template")
        self.assertAlmostEqual(m["x"], 258.0, delta=0.6)
        self.assertAlmostEqual(m["y"], 208.0, delta=0.6)


# --------------------------- end-to-end CLI tests ---------------------------

def run_cli(manifest, index, output=None, extra_args=("--allow-subset-manifest",)):
    cmd = [sys.executable, os.path.join(HERE, "score_roll_fusion.py"),
           "--manifest", manifest, "--capture-index", index]
    if output:
        cmd += ["--output", output]
    cmd += list(extra_args)
    return subprocess.run(cmd, capture_output=True, text=True)


@unittest.skipUnless(os.path.isfile(PART1_MANIFEST),
                     "part 1 fixture pack not unpacked next to the tests")
class TestEndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="rollfusion-test-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_pass_correct_renderer_two_fixtures(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST,
                              ["sbs_neg02", "sbs_zero",
                               "top_bottom_pos02", "top_bottom_zero"])
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_PASS, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertEqual(rep["verdict"], "PASS")
        for fx in rep["preview"].values():
            for a in fx["angles"].values():
                self.assertEqual(a["n_pairs_matched"], 9)
                self.assertLessEqual(a["max_abs_e_v"], S.TOLERANCE_PX)
        self.assertTrue(all(z["identical"] for z in rep["zero_roll"].values()))
        self.assertIn("software", rep.get("rendering_note", ""))

    def test_pass_crossed_zero_disparity_fixture(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_zero"])
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_PASS, r.stdout + r.stderr)

    def test_pass_remaining_modes(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST,
                              ["half_sbs_pos02", "sbs_zero", "mono_zero",
                               "native_vr180_pos02",
                               "native_vr180_zero"])
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_PASS, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertIn("native_vr180_pos02", rep["native_regression"])
        self.assertNotIn("native_vr180_pos02", rep["preview"])

    def test_fail_horizontal_mutant(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02", "sbs_zero"],
                              mutant="horizontal",
                              mutant_angles={-30.0, -15.0, -5.0, 5.0, 15.0, 30.0})
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_ACCEPTANCE_FAIL,
                         r.stdout + r.stderr)

    def test_fail_image_y_mutant(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02", "sbs_zero"],
                              mutant="image_y")
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_ACCEPTANCE_FAIL,
                         r.stdout + r.stderr)

    def test_missing_marker_cannot_pass(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              erase_marker=("sbs_neg02", "r1c1"))
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        self.assertIn("r1c1", r.stdout)

    def test_duplicate_marker_cannot_pass(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              duplicate_marker=("sbs_neg02", "r0c0"))
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)

    def test_incomplete_angle_set_cannot_pass(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              skip_captures={cap_id("sbs_neg02", "flat-sbs",
                                                    15.0)})
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)

    def test_changed_zero_roll_pixel_fails(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              tamper_zero_roll="sbs_neg02")
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_ACCEPTANCE_FAIL,
                         r.stdout + r.stderr)
        self.assertIn("zero-roll", r.stdout)

    def test_not_run_records_incomplete(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        # flip every record to not_run: nothing may be scored
        idx_doc = json.load(open(idx))
        for rec in idx_doc["captures"]:
            rec["status"] = "not_run"
            rec["acceptance_class"] = "not_run"
            rec["image"] = None
            rec["golden"] = None
            rec["error"] = "binding_status=missing: shader bytes unavailable"
        idx_doc["source"]["binding_status"] = "missing"
        idx_doc["source"]["actual_sha256"] = None
        idx_doc["source"]["expected_sha256"] = None
        with open(idx, "w") as f:
            json.dump(idx_doc, f)
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertTrue(rep.get("not_run"))
        self.assertFalse(rep["preview"])

    def test_hash_tampering_refused(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        idx_doc = json.load(open(idx))
        for rec in idx_doc["captures"]:
            if rec["status"] == "captured":
                rec["image"]["sha256"] = "0" * 64  # break binding
                break
        with open(idx, "w") as f:
            json.dump(idx_doc, f)
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_malformed_record_refused(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        idx_doc = json.load(open(idx))
        del idx_doc["captures"][0]["roll_deg"]
        with open(idx, "w") as f:
            json.dump(idx_doc, f)
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_wrong_manifest_schema_refused(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(man))
        doc["schema"] = "roll-markers/v0"
        with open(man, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)



REAL_SMOKE_INDEX = os.path.join(HERE, "test_data_real_smoke.index.json")


class TestContractAndIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="rollfusion-test-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_plan_validation_full_manifest_ok(self):
        man = S.load_manifest(PART1_MANIFEST)
        S.validate_plan(man)  # must not raise on the real 13-fixture plan

    def test_subset_manifest_rejected_by_default(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        r = run_cli(man, idx, extra_args=())
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_tolerance_nan_and_bounds(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              angles=(0.0,))
        for bad in ("nan", "inf", "1.5", "-0.1"):
            r = run_cli(man, idx, extra_args=("--allow-subset-manifest",
                                              "--tolerance-px", bad))
            self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR,
                             f"tolerance {bad}: " + r.stdout + r.stderr)

    def test_nonfinite_roll_deg_rejected(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        doc["captures"][0]["roll_deg"] = float("nan")
        with open(idx, "w") as f:
            f.write(json.dumps(doc))
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_no_golden_carrier_is_not_run(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        doc["captures"] = [c for c in doc["captures"]
                           if not c["zero_roll_baseline"]]
        for c in doc["captures"]:
            c["golden"] = None
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertTrue(rep["zero_roll"]["sbs_neg02"].get("not_run"))

    def test_unidentified_core_cannot_pass(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"],
                              duplicate_marker=("sbs_neg02", "r0c0"))
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)

    def test_golden_comparison_not_run(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        doc["golden_comparison"] = {"status": "NOT_RUN",
                                    "reason": "no golden baseline carrier"}
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertEqual(rep["zero_roll"]["sbs_neg02"].get("reason"),
                         "golden_comparison NOT_RUN")
        self.assertEqual(rep["failures"], [])

    def test_verified_binding_rejects_null_expected(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        doc["source"]["expected_sha256"] = None
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_source_repo_checked(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        doc["source"]["repo"] = "example.com/evil-fork"
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx)
        self.assertEqual(r.returncode, S.EXIT_INPUT_ERROR, r.stdout + r.stderr)

    def test_captured_shader_error_not_scorable(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        victim = next(c for c in doc["captures"]
                      if c["roll_deg"] == 5.0 and not c["crossed"]
                      and not c["zero_roll_baseline"])
        victim["status"] = "captured_shader_error"
        victim["error"] = "shader failed to load in slot"
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        fx = rep["preview"]["sbs_neg02"]
        self.assertNotIn("+5", fx["angles"])
        self.assertTrue(any("shader error" in i for i in rep["incomplete"]))

    def test_shipping_shader_sha256_preserved(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertEqual(rep.get("shipping_shader_sha256"), SYN_SHADER_SHA)

    def test_real_smoke_index_refused(self):
        if not os.path.isfile(REAL_SMOKE_INDEX):
            self.skipTest("real smoke index copy not present")
        r = run_cli(PART1_MANIFEST, REAL_SMOKE_INDEX,
                    os.path.join(self.tmp, "report.json"), extra_args=())
        self.assertEqual(r.returncode, S.EXIT_INCOMPLETE, r.stdout + r.stderr)
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        self.assertEqual(rep["verdict"], "INCOMPLETE")
        self.assertTrue(rep.get("not_run"))
        self.assertFalse(rep["preview"])
        self.assertFalse(rep["crossed"])
        self.assertTrue(rep.get("n_refused_records", 0) >= 112)
        self.assertIsNone(rep.get("shipping_shader_sha256"))


class TestFallback(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="rollfusion-test-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_colour_fallback_pairs_counted(self):
        idx, man = make_world(self.tmp, PART1_MANIFEST, ["sbs_neg02"])
        doc = json.load(open(idx))
        for rec in doc["captures"]:
            if rec["status"] != "captured":
                continue
            p = os.path.join(self.tmp, rec["image"]["path"])
            a = np.array(Image.open(p).convert("RGB"))
            a[np.all(a >= S.WHITE_CORE_MIN, axis=2)] = (200, 200, 200)
            Image.fromarray(a).save(p)
            rec["image"]["sha256"] = sha256_file(p)
            if rec.get("golden"):
                rec["golden"] = None
        doc["captures"] = [c for c in doc["captures"]
                           if not c["zero_roll_baseline"]]
        with open(idx, "w") as f:
            json.dump(doc, f)
        r = run_cli(man, idx, os.path.join(self.tmp, "report.json"))
        rep = json.load(open(os.path.join(self.tmp, "report.json")))
        fx = rep["preview"]["sbs_neg02"]
        for ang, a_rep in fx["angles"].items():
            n = a_rep["n_pairs_matched"]
            n_clip = len(a_rep.get("clipped_marker_ids", []))
            self.assertEqual(n + n_clip, 9,
                             f"angle {ang}: markers lost, not clipped")
            self.assertGreaterEqual(n, 8,
                                    f"angle {ang}: fallback pairs not counted")
            for pair in a_rep["pairs"]:
                self.assertEqual(pair["left"]["method"], "colour")
                self.assertEqual(pair["right"]["method"], "colour")


if __name__ == "__main__":
    unittest.main()
