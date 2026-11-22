#!/usr/bin/env python3
"""Tests for run_roll_capture.py (191c R4 Task 2). Hermetic: a FakeDriver
replaces mpv; no real mpv, display or network is needed. Live shader-discovery
against the historical vr180-look.lua runs only when VR180_HISTORICAL_LUA is set.
"""
import json, os, struct, sys, tempfile, unittest, zlib, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_roll_capture as r


FAKE_SHADER = r'''
mp.register_script_message("vr180-look-store-revision",function(revision,kind,sender,want_enabled,want_layout,want_pack,output,engine,generation,file,app_pid)
    if sender~="store-applier" then return end
end)
local route_arity={ ["vr180-look-set-projection"]=2,["vr180-look-set-output"]=1,["vr180-look-set-pack"]=5,["vr180-look-set-enabled"]=1,["vr180-look-plan-lock"]=2 }
mp.register_script_message("vr180-look-set-projection", function(kind, aspect)
    source_layout=({["flat-2d3d"]=0,["flat-sbs"]=1,["flat-tb"]=2,["vr180"]=3,["vr180-tb"]=4,["vr360-mono"]=5,["vr360-tb"]=6})[kind] or 0
end)
mp.register_script_message("vr180-look-set-pack", function(pack, gain_scale, conv, zoom, soft) end)
mp.register_script_message("vr180-look-set-enabled", function(val) end)
mp.register_script_message("vr180-look-route-complete",function(revision,sender) end)
mp.register_script_message("vr180-look-viewing-cross",function(val) end)
mp.register_script_message("vr180-look-set-swap-eyes", function(val) end)
mp.register_script_message("vr180-look-set-orientation", function(yaw_s, pitch_s, fov_s, roll_s, ipd_nudge_s, head_x_s, head_y_s, head_z_s, dist_mm_s, dist_reason_s, mm_per_px_s, fusion_roll_s, native_raw_roll_s)
    if roll then vr_roll=roll end
end)
-- slot naming: vr180-look-shader-a.glsl / vr180-look-shader-b.glsl
-- publishes user-data/vr180-look/installed-shader and user-data/vr180-look/applied-state
'''


def fake_png(path, w=2560, h=1600, rgb=(7, 9, 11)):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(rgb) * w
    raw = row * h
    idat = zlib.compress(raw, 1)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


MODES = [("sbs", "flat-sbs", 2560, 720), ("half_sbs", "flat-sbs", 1280, 720),
         ("top_bottom", "flat-tb", 1280, 1440), ("mono", "flat-2d3d", 1280, 720),
         ("native_vr180", "vr180", 2560, 720)]


def sample_manifest(tmp):
    fdir = os.path.join(tmp, "fixtures")
    os.makedirs(fdir)
    fixtures = []
    for mode, kind, w, h in MODES:
        disps = [0.0] if mode == "mono" else [-0.02, 0.0, 0.02]
        for d in disps:
            tag = "zero" if d == 0 else ("neg02" if d < 0 else "pos02")
            fid = "%s_%s" % (mode, tag)
            fake_png(os.path.join(fdir, fid + ".png"), w, h)
            fixtures.append({
                "id": fid, "mode": mode, "path": fid + ".png", "width": w, "height": h,
                "sha256": r.sha256_file(os.path.join(fdir, fid + ".png")),
                "eyes": {"left": [0, 0, w // (2 if mode in ("sbs", "native_vr180") else 1), h if mode != "top_bottom" else h // 2]},
                "sample_aspect_ratio": [2, 1] if mode == "half_sbs" else [1, 1],
                "logical_eye_dimensions": [1280, 720],
                "signed_disparity_fraction": d,
                "markers": [],
            })
    doc = {"schema": "roll-markers/v1", "fixtures": fixtures}
    mpath = os.path.join(tmp, "manifest.json")
    with open(mpath, "w") as f:
        json.dump(doc, f)
    return mpath, fdir, fixtures


class FakeDriver(object):
    """Stands in for MpvProcess; behavioural knobs simulate mpv failures."""

    def __init__(self, home, fail_start=False, skip_screenshot=False,
                 stale_roll=False, wrong_size=False, wrong_layout=False,
                 wrong_cross=False, stale_events=False, no_fresh_event=False,
                 wrong_fov=False, slot="b", stale_other_slot=False,
                 active_slot_wrong=False, missing_entry=False):
        self.home = home
        self.argv = ["fake-mpv"]
        self.ipc = FakeIpc(stale_roll=stale_roll, wrong_layout=wrong_layout,
                           wrong_cross=wrong_cross, stale_events=stale_events,
                           no_fresh_event=no_fresh_event, wrong_fov=wrong_fov,
                           slot=slot, stale_other_slot=stale_other_slot,
                           active_slot_wrong=active_slot_wrong,
                           missing_entry=missing_entry)
        self.fail_start = fail_start
        self.stopped = False
        if skip_screenshot:
            self.ipc.on_screenshot = lambda p: None
        elif wrong_size:
            self.ipc.on_screenshot = lambda p: fake_png(p, 1280, 800)
        else:
            self.ipc.on_screenshot = fake_png

    def start(self, fixture_path, allow_sw=True):
        if self.fail_start:
            raise r.CellError("mpv failed to start (rc=1): boom")

    def stop(self):
        self.stopped = True


class FakeIpc(object):
    """Realistic stand-in: full shader option map, event queue that honours
    drain_events, and a completed applied-state."""

    LAYOUTS = {"flat-2d3d": 0, "flat-sbs": 1, "flat-tb": 2, "vr180": 3}

    def __init__(self, stale_roll=False, wrong_layout=False, wrong_cross=False,
                 stale_events=False, no_fresh_event=False, wrong_fov=False,
                 slot="b", stale_other_slot=False, active_slot_wrong=False,
                 missing_entry=False):
        self.slot = slot
        self.stale_other_slot = stale_other_slot
        self.active_slot_wrong = active_slot_wrong
        self.missing_entry = missing_entry
        self.messages = []
        self.on_screenshot = None
        self.stale_roll = stale_roll
        self.wrong_layout = wrong_layout
        self.wrong_cross = wrong_cross
        self.no_fresh_event = no_fresh_event
        self.wrong_fov = wrong_fov
        self.roll = 0.0
        self.enabled = False
        self.kind = None
        self.crossed = False
        self.events = []
        if stale_events:
            # queued startup events that a lazy sync could wrongly consume
            self.events.append({"event": "playback-restart"})
            self.events.append({"event": "video-reconfig"})

    # -- client surface used by capture_cell --
    def command(self, *args, timeout=15.0):
        if args[0] == "script-message":
            self.messages.append(list(args[1:]))
            name = args[1]
            if name.endswith("set-enabled"):
                self.enabled = args[2] == "true"
            elif name.endswith("set-projection"):
                self.kind = args[2]
            elif name.endswith("viewing-cross"):
                self.crossed = args[2] == "true"
            elif name.endswith("set-orientation"):
                if not self.stale_roll:
                    self.roll = float(args[5])
            return None
        if args[0] == "get_property":
            prop = args[1]
            if prop == "user-data/vr180-look/installed-shader":
                return {"verdict": "PASS", "variant": "extended", "expected": "extended",
                        "sha256": "ab" * 32,
                        "entry": ("none" if self.missing_entry else
                                  "/fake/dir/vr180-look-shader-%s.glsl" % self.slot)}
            if prop == "user-data/vr180-look/applied-state":
                return json.dumps({"source_layout": self.LAYOUTS.get(self.kind, 0),
                                   "enabled": self.enabled, "completed_revision": 1,
                                   "flat_pack": 0, "plan_lock": None})
            if prop == "glsl-shader-opts":
                layout = self.LAYOUTS.get(self.kind, 0)
                if self.wrong_layout:
                    layout += 1
                cross = 1.0 if self.crossed else 0.0
                if self.wrong_cross:
                    cross = 1.0 - cross
                flat = self.kind in ("flat-sbs", "flat-tb", "flat-2d3d")
                vals = {
                    "vr_roll": "%.6f" % self.roll,
                    "vr_head_roll": "%.6f" % self.roll,
                    "vr_cross_eye": "%.1f" % cross,
                    "vr_source_layout": "%.1f" % float(layout),
                    "vr_flat_sbs": "%.1f" % (1.0 if flat else 0.0),
                    "vr_flat_mono": "%.1f" % (1.0 if self.kind == "flat-2d3d" else 0.0),
                    "vr_fov": "9.000000" if self.wrong_fov else "2.356194",
                    "vr_eye_aspect": "1.777778",
                }
                def other():
                    return "a" if self.slot == "b" else "b"
                out = {}
                if self.active_slot_wrong:
                    # active slot stale/wrong, INACTIVE slot holds correct values:
                    # only slot-coherent matching may refuse this
                    bad = dict(vals)
                    bad["vr_roll"] = "0.000000"
                    bad["vr_head_roll"] = "0.000000"
                    out.update({"vr180-look-shader-%s/%s" % (self.slot, k): v
                                for k, v in bad.items()})
                    out.update({"vr180-look-shader-%s/%s" % (other(), k): v
                                for k, v in vals.items()})
                else:
                    out.update({"vr180-look-shader-%s/%s" % (self.slot, k): v
                                for k, v in vals.items()})
                    if self.stale_other_slot:
                        stale = dict(vals)
                        stale["vr_roll"] = "9.000000"
                        stale["vr_head_roll"] = "9.000000"
                        out.update({"vr180-look-shader-%s/%s" % (other(), k): v
                                    for k, v in stale.items()})
                return out
        if args[0] == "seek":
            if not self.no_fresh_event:
                self.events.append({"event": "playback-restart"})
            return None
        if args[0] == "screenshot-to-file":
            if self.on_screenshot is not None:
                self.on_screenshot(args[1])
            return None
        return None

    def wait_property(self, name, predicate, timeout, poll=0.05, native=True):
        val = self.command("get_property", name)
        if predicate(val):
            return val
        raise r.IpcError("stale option: property %r never satisfied (last=%r, waited %.1fs)"
                         % (name, val, timeout))

    def drain_events(self):
        self.events = []

    def wait_event(self, names, timeout):
        for i, ev in enumerate(self.events):
            if ev.get("event") in names:
                self.events.pop(i)
                return ev
        raise r.IpcError("timed out (%.1fs) waiting for mpv event %s"
                         % (timeout, "/".join(names)))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="rollcap-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.mpath, self.fdir, self.fixtures = sample_manifest(self.tmp)
        self.shader = os.path.join(self.tmp, "vr180-look.lua")
        with open(self.shader, "w") as f:
            f.write(FAKE_SHADER)
        self.contract = r.ShaderContract(FAKE_SHADER)

    def _args(self, **over):
        import argparse
        a = argparse.Namespace(manifest=self.mpath, fixtures_dir=self.fdir,
                               shader=self.shader, binding=None,
                               allow_unbound_smoke=True,
                               provenance="unit-test fake shader", golden=None,
                               mpv="fake", out=os.path.join(self.tmp, "out"),
                               timeout=5.0, only=None)
        for k, v in over.items():
            setattr(a, k, v)
        return a

    def _factory(self, home, log_path):
        return FakeDriver(home)


class TestDiscovery(Base):
    def test_pose_message_and_roll_arg(self):
        self.assertEqual(self.contract.pose_message, "vr180-look-set-orientation")
        self.assertEqual(self.contract.pose_args["roll_index"], 3)
        self.assertEqual(len(self.contract.pose_args["args"]), 13)

    def test_route_messages_found(self):
        for k in ("set-projection", "set-pack", "set-enabled", "route-complete",
                  "viewing-cross", "set-swap-eyes"):
            self.assertTrue(self.contract.route[k].endswith(k))
        self.assertEqual(self.contract.store_revision_message, "vr180-look-store-revision")
        r.check_route_arity(self.contract)

    def test_missing_pose_registration_refused(self):
        with self.assertRaises(r.RunnerError):
            r.ShaderContract(FAKE_SHADER.replace("vr_roll=roll", "unrelated=roll"))

    def test_missing_route_registration_refused(self):
        broken = FAKE_SHADER.replace('mp.register_script_message("vr180-look-set-enabled", function(val) end)', "")
        with self.assertRaises(r.RunnerError):
            r.ShaderContract(broken)

    def test_store_revision_arg_divergence_refused(self):
        broken = FAKE_SHADER.replace("function(revision,kind,sender,", "function(revision,sender,kind,")
        with self.assertRaises(r.RunnerError):
            r.ShaderContract(broken)


class TestSerialization(Base):
    def test_pose_argv(self):
        argv = self.contract.pose_argv(0.261799)
        self.assertEqual(len(argv), 13)
        self.assertEqual(argv[3], "0.261799")
        self.assertEqual(argv.count(""), 12)
        argv = self.contract.pose_argv(-0.523599)
        self.assertEqual(argv[3], "-0.523599")

    def test_route_sequence(self):
        fx = self.fixtures[0]
        cell = r.Cell(fx, "flat-sbs", 5)
        msgs = r.route_messages(self.contract, cell, 16 / 9)
        self.assertEqual(msgs[0][0], "vr180-look-store-revision")
        self.assertEqual(msgs[0][2], "flat-sbs")
        self.assertEqual(msgs[0][3], "store-applier")
        self.assertEqual([m[0] for m in msgs],
                         ["vr180-look-store-revision", "vr180-look-set-projection",
                          "vr180-look-set-enabled", "vr180-look-route-complete"])
        self.assertEqual(msgs[1][1:3], ["flat-sbs", "1.777778"])

    def test_route_sequence_flat_2d3d_has_set_pack(self):
        fx = next(f for f in self.fixtures if f["mode"] == "mono")
        cell = r.Cell(fx, "flat-2d3d", 0)
        msgs = r.route_messages(self.contract, cell, 16 / 9)
        names = [m[0] for m in msgs]
        self.assertIn("vr180-look-set-pack", names)
        pack = msgs[names.index("vr180-look-set-pack")]
        self.assertEqual(pack[1:6], ["0", "1", "0.5", "1", "1"])

    def test_half_sbs_sar_honored(self):
        fx = next(f for f in self.fixtures if f["mode"] == "half_sbs")
        self.assertAlmostEqual(r.logical_eye_aspect(fx), 16 / 9, places=6)

    def test_capture_id_format(self):
        self.assertEqual(r.capture_id("sbs_zero", "flat-sbs", -30), "sbs_zero__flat-sbs__rollm30")
        self.assertEqual(r.capture_id("mono_zero", "flat-2d3d", 15, crossed=True),
                         "mono_zero__flat-2d3d__rollp15__crossed")
        self.assertEqual(r.capture_id("sbs_zero", "flat-sbs", 0, baseline=True),
                         "sbs_zero__flat-sbs__rollp0__baseline")


class TestPlan(Base):
    def test_angle_mode_completeness(self):
        cells = r.build_plan(self.fixtures)
        ids = [c.capture_id for c in cells]
        self.assertEqual(len(ids), len(set(ids)), "duplicate capture ids")
        self.assertEqual(len(cells), 13 * 8 + 8)  # 7 angles + 1 baseline per fixture, 8 crossed
        for fx in self.fixtures:
            kind = r.MODE_TO_KIND[fx["mode"]]
            for deg in (-30, -15, -5, 0, 5, 15, 30):
                self.assertIn(r.capture_id(fx["id"], kind, deg), ids)
            self.assertIn(r.capture_id(fx["id"], kind, 0, baseline=True), ids)
        for mode, kind in (("sbs", "flat-sbs"), ("top_bottom", "flat-tb"),
                           ("mono", "flat-2d3d"), ("native_vr180", "vr180")):
            for deg in (-15, 15):
                self.assertIn(r.capture_id("%s_zero" % mode, kind, deg, crossed=True), ids)
        self.assertEqual(sum(1 for c in cells if c.crossed), 8)
        self.assertEqual(sum(1 for c in cells if c.baseline), 13)


class TestCaptureCell(Base):
    def _cell(self, fid="sbs_zero", kind="flat-sbs", deg=15, crossed=False, baseline=False):
        fx = next(f for f in self.fixtures if f["id"] == fid)
        fx["_abs_path"] = os.path.join(self.fdir, fx["path"])
        return r.Cell(fx, kind, deg, crossed=crossed, baseline=baseline)

    def _run_cell(self, cell, **kw):
        knobs = ("fail_start", "skip_screenshot", "stale_roll", "wrong_size",
                 "wrong_layout", "wrong_cross", "stale_events", "no_fresh_event", "wrong_fov")
        drv = kw.pop("drv", None) or FakeDriver(self.tmp, **{k: v for k, v in kw.items()
                                                if k in knobs})
        rec = r.capture_cell(cell, self.contract, drv, self.tmp,
                             kw.get("binding_status", "verified"), (None, "software"),
                             kw.get("timeout_s", 5.0),
                             pose_injected=kw.get("pose_injected", True))
        return rec, drv

    def test_happy_path(self):
        rec, drv = self._run_cell(self._cell())
        self.assertEqual(rec["status"], "captured", rec["error"])
        self.assertEqual(rec["acceptance_class"], "evidence")
        img = rec["image"]
        self.assertEqual((img["width"], img["height"]), (2560, 1600))
        self.assertEqual(img["sha256"], r.sha256_file(os.path.join(self.tmp, img["path"])))
        self.assertEqual(rec["pose_message"]["name"], "vr180-look-set-orientation")
        self.assertEqual(rec["pose_message"]["args"][3], "0.261799")
        self.assertIn("vr_roll", rec["effective_options"])
        self.assertTrue(drv.stopped)
        names = [m[0] for m in drv.ipc.messages]
        self.assertEqual(names[0], "vr180-look-store-revision")
        self.assertIn("vr180-look-set-orientation", names)

    def test_zero_roll_baseline_no_pose(self):
        rec, drv = self._run_cell(self._cell(deg=0, baseline=True), pose_injected=False)
        self.assertEqual(rec["status"], "captured", rec["error"])
        self.assertTrue(rec["zero_roll_baseline"])
        self.assertIsNone(rec["pose_message"]["args"])
        self.assertNotIn("vr180-look-set-orientation", [m[0] for m in drv.ipc.messages])

    def test_crossed_sends_viewing_cross_before_pose(self):
        rec, drv = self._run_cell(self._cell(deg=15, crossed=True))
        self.assertEqual(rec["status"], "captured", rec["error"])
        names = [m[0] for m in drv.ipc.messages]
        self.assertLess(names.index("vr180-look-viewing-cross"),
                        names.index("vr180-look-set-orientation"))
        self.assertEqual(rec["effective_options"]["vr_cross_eye"], "1.0")

    def test_smoke_acceptance_class(self):
        rec, _ = self._run_cell(self._cell(), binding_status="unbound-smoke")
        self.assertEqual(rec["acceptance_class"], "smoke_not_evidence")

    def test_nonzero_mpv_start_refusal(self):
        rec, _ = self._run_cell(self._cell(), fail_start=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("mpv failed to start", rec["error"])
        self.assertIsNone(rec["image"])

    def test_missing_capture_refusal(self):
        rec, _ = self._run_cell(self._cell(), skip_screenshot=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("capture file missing", rec["error"])

    def test_wrong_capture_size_refusal(self):
        rec, _ = self._run_cell(self._cell(), wrong_size=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("expected 2560x1600", rec["error"])

    def test_stale_option_refusal(self):
        rec, _ = self._run_cell(self._cell(), stale_roll=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("stale option", rec["error"])


class TestFullStateValidation(Base):
    def _cell(self, fid="sbs_zero", kind="flat-sbs", deg=15, crossed=False):
        fx = next(f for f in self.fixtures if f["id"] == fid)
        fx["_abs_path"] = os.path.join(self.fdir, fx["path"])
        return r.Cell(fx, kind, deg, crossed=crossed)

    def _run(self, cell, **knobs):
        drv = FakeDriver(self.tmp, **knobs)
        return r.capture_cell(cell, self.contract, drv, self.tmp, "verified",
                              (None, "software"), 5.0, pose_injected=True)

    def test_wrong_layout_refused(self):
        rec = self._run(self._cell(), wrong_layout=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("vr_source_layout", rec["error"])

    def test_wrong_cross_refused(self):
        rec = self._run(self._cell(crossed=True), wrong_cross=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("vr_cross_eye", rec["error"])

    def test_wrong_fov_refused(self):
        rec = self._run(self._cell(), wrong_fov=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("vr_fov", rec["error"])

    def test_stale_roll_refused(self):
        rec = self._run(self._cell(), stale_roll=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("vr_roll", rec["error"])

    def test_non_finite_uniform_refused(self):
        cell = self._cell()
        exp = r.expected_option_state(cell, r.logical_eye_aspect(cell.fixture), True)
        opts = {"vr180-look-shader-a/" + k: repr(v) for k, v in exp.items()}
        pred = r._opts_full_match(exp, "a")
        self.assertEqual(pred(opts), [])  # sanity: finite exact match passes
        for bad_val in ("nan", "inf", "-inf"):
            o2 = dict(opts)
            o2["vr180-look-shader-a/vr_head_roll"] = bad_val
            res = pred(o2)
            self.assertIsInstance(res, list, bad_val)
            self.assertTrue(any("non-finite" in b for b in res), res)

    def test_mixed_stale_slot_ignored(self):
        # correct active slot plus a stale other slot: capture must succeed on
        # the active namespace alone
        rec = self._run(self._cell(), stale_other_slot=True)
        self.assertEqual(rec["status"], "captured", rec["error"])
        self.assertEqual(rec["shader_slot"], "vr180-look-shader-b")
        self.assertEqual(rec["option_receipt"]["slot"], "vr180-look-shader-b")
        self.assertAlmostEqual(rec["option_receipt"]["values"]["vr_head_roll"],
                               rec["roll_rad"], places=5)
        self.assertEqual(rec["option_receipt"]["installed_shader"]["entry"],
                         "/fake/dir/vr180-look-shader-b.glsl")

    def test_active_slot_stale_other_slot_correct_refused(self):
        # the flattened matcher could assemble a pass from the inactive slot's
        # correct values; coherent slot selection must refuse
        rec = self._run(self._cell(), active_slot_wrong=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("vr_head_roll", rec["error"])

    def test_installed_shader_entry_without_slot_refused(self):
        rec = self._run(self._cell(), missing_entry=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("entry", rec["error"])

    def test_stale_queued_events_do_not_satisfy_frame_sync(self):
        rec = self._run(self._cell(), stale_events=True, no_fresh_event=True)
        self.assertEqual(rec["status"], "error")
        self.assertIn("waiting for mpv event", rec["error"])

    def test_drain_then_fresh_event_captures(self):
        rec = self._run(self._cell(), stale_events=True, no_fresh_event=False)
        self.assertEqual(rec["status"], "captured", rec["error"])


class TestGoldenAndRuns(Base):
    def test_full_fake_run(self):
        rc = r.run(self._args(), driver_factory=self._factory)
        self.assertEqual(rc, 0)
        idx = json.load(open(os.path.join(self.tmp, "out", "run_roll_capture.index.json")))
        self.assertEqual(idx["planned_cells"], 112)
        self.assertEqual(idx["captured"], 112)
        self.assertFalse(idx["acceptance_evidence"])  # smoke binding
        self.assertTrue(idx["complete"])
        self.assertEqual(idx["golden_comparison"]["status"], "NOT_RUN")
        classes = {c["acceptance_class"] for c in idx["captures"]}
        self.assertEqual(classes, {"smoke_not_evidence"})
        base = [c for c in idx["captures"] if c["zero_roll_baseline"]]
        self.assertEqual(len(base), 13)
        self.assertTrue(all(c["golden"]["bound"] is False for c in base))
        self.assertTrue(all(c["golden"]["golden_hash_verified"] is False for c in base))
        self.assertTrue(all(c["option_receipt"] and c["option_receipt"]["matched_expectation"]
                            and c["option_receipt"]["applied_state"]["enabled"] is True
                            for c in idx["captures"]))
        self.assertIn("render_proof_note", idx)
        self.assertIn("NOT render proof", idx["render_proof_note"])

    def test_subset_never_acceptance_or_complete(self):
        rc = r.run(self._args(only=["rollp15"]), driver_factory=self._factory)
        self.assertEqual(rc, 0)
        idx = json.load(open(os.path.join(self.tmp, "out", "run_roll_capture.index.json")))
        self.assertEqual(idx["captured"], 17)  # 13 fixtures + 4 crossed
        self.assertFalse(idx["complete"])
        self.assertFalse(idx["acceptance_evidence"])

    def test_binding_missing_writes_not_run_index(self):
        rc = r.main(["--manifest", self.mpath, "--fixtures-dir", self.fdir,
                     "--shader", self.shader, "--mpv", "fake",
                     "--out", os.path.join(self.tmp, "out2")])
        self.assertEqual(rc, 2)
        idx = json.load(open(os.path.join(self.tmp, "out2", "run_roll_capture.index.json")))
        self.assertEqual(idx["planned_cells"], 112)
        self.assertEqual(idx["captured"], 0)
        self.assertEqual(idx["captures"][0]["status"], "not_run")
        self.assertIn("binding missing", idx["fatal_error"])
        self.assertFalse(idx["acceptance_evidence"])

    def _write_golden(self, ship_sha, img_bytes=b"\x89PNG\r\n\x1a\n" + b"g" * 64,
                      img_sha=None):
        gimg = os.path.join(self.tmp, "g.png")
        with open(gimg, "wb") as f:
            f.write(img_bytes)
        gpath = os.path.join(self.tmp, "golden.json")
        with open(gpath, "w") as f:
            json.dump({"schema": "roll-golden-baseline/v1",
                       "shader_sha256": ship_sha,
                       "captures": {"sbs_zero": {"path": "g.png",
                                                 "sha256": img_sha or r.sha256_file(gimg)}}}, f)
        return gpath

    def test_golden_shipping_shader_hash_may_differ(self):
        # the golden carrier binds the SHIPPING build's captures; its shader
        # hash is recorded, never required to equal the run shader
        gpath = self._write_golden("f" * 64)
        g = r.load_golden(gpath)
        self.assertEqual(g["shipping_shader_sha256"], "f" * 64)
        self.assertEqual(g["captures"]["sbs_zero"]["sha256"], r.sha256_file(
            os.path.join(self.tmp, "g.png")))

    def test_golden_image_missing_refused(self):
        gpath = self._write_golden("f" * 64)
        os.remove(os.path.join(self.tmp, "g.png"))
        with self.assertRaises(r.RunnerError):
            r.load_golden(gpath)

    def test_golden_image_hash_mismatch_refused(self):
        gpath = self._write_golden("f" * 64, img_sha="0" * 64)
        with self.assertRaises(r.RunnerError):
            r.load_golden(gpath)

    def test_golden_bound(self):
        gpath = self._write_golden("f" * 64)  # shipping shader differs from run shader
        gsha = r.sha256_file(os.path.join(self.tmp, "g.png"))
        rc = r.run(self._args(golden=gpath, only=["sbs_zero__flat-sbs__rollp0__baseline"]),
                   driver_factory=self._factory)
        self.assertEqual(rc, 0)
        idx = json.load(open(os.path.join(self.tmp, "out", "run_roll_capture.index.json")))
        gc = idx["golden_comparison"]
        self.assertEqual(gc["status"], "recorded")
        self.assertEqual(gc["shipping_shader_sha256"], "f" * 64)
        self.assertFalse(gc["same_shader_as_run"])
        self.assertEqual(gc["bound_baselines"], 1)
        rec = idx["captures"][0]
        self.assertTrue(rec["golden"]["bound"])
        self.assertTrue(rec["golden"]["golden_hash_verified"])
        self.assertEqual(rec["golden"]["golden_sha256"], gsha)


class TestShaderErrorScan(Base):
    def test_scan_shader_log_patterns(self):
        p = os.path.join(self.tmp, "x.log")
        with open(p, "w") as f:
            f.write("[   1.184][e][vo/gpu] Unrecognized command 'PARAM vr_native_tb'!\n")
            f.write("[   1.184][w][vo/gpu] Unrecognized command 'PARAM warn_only'!\n")
            f.write("[   1.184][e][cplayer] Unrecognized command 'PARAM not_gpu'!\n")
            f.write("[   1.184][e][vo/gpu/opengl] Error while parsing OFFSET!\n")
        hits = r.scan_shader_log(p)
        self.assertEqual(len(hits), 2)
        self.assertIn("vr_native_tb", hits[0])
        self.assertIn("OFFSET", hits[1])
        self.assertEqual(r.scan_shader_log(os.path.join(self.tmp, "missing.log")), [])

    def _factory_bad_log(self, home, log_path):
        with open(log_path, "w") as f:
            f.write("[   1.184][e][vo/gpu] Unrecognized command 'PARAM vr_native_tb'!\n")
        return FakeDriver(home)

    def test_shader_error_flags_cells(self):
        rc = r.run(self._args(only=["sbs_zero__flat-sbs__rollp30"]),
                   driver_factory=self._factory_bad_log)
        self.assertEqual(rc, 2)  # nothing cleanly captured
        idx = json.load(open(os.path.join(self.tmp, "out", "run_roll_capture.index.json")))
        # substring match also selects half_sbs_zero__flat-sbs__rollp30
        self.assertEqual(len(idx["captures"]), 2)
        self.assertEqual(idx["captured"], 0)
        self.assertEqual(idx["shader_errored"], 2)
        self.assertFalse(idx["complete"])
        self.assertFalse(idx["acceptance_evidence"])
        rec = idx["captures"][0]
        self.assertEqual(rec["status"], "captured_shader_error")
        self.assertTrue(rec["shader_errors"])
        self.assertIn("PARAM vr_native_tb", rec["shader_errors"][0])
        self.assertIsNotNone(rec["image"])  # image kept but flagged untransformed
        self.assertIn("untransformed", rec["error"])

    def test_mixed_shader_error_partial_run(self):
        state = {"n": 0}
        def factory(home, log_path):
            state["n"] += 1
            if state["n"] == 1:
                with open(log_path, "w") as f:
                    f.write("[   0.5][e][vo/gpu] Unrecognized command 'PARAM vr_native_tb'!\n")
            return FakeDriver(home)
        rc = r.run(self._args(only=["rollp0__baseline"]), driver_factory=factory)
        self.assertEqual(rc, 3)
        idx = json.load(open(os.path.join(self.tmp, "out", "run_roll_capture.index.json")))
        self.assertEqual(idx["shader_errored"], 1)
        self.assertEqual(idx["captured"], 12)
        self.assertFalse(idx["complete"])
        self.assertFalse(idx["acceptance_evidence"])


class TestBindingAndManifest(Base):
    def test_manifest_schema_refusal(self):
        bad = os.path.join(self.tmp, "bad.json")
        with open(bad, "w") as f:
            json.dump({"schema": "other/v9", "fixtures": [1]}, f)
        with self.assertRaises(r.RunnerError):
            r.load_manifest(bad)

    def test_fixture_hash_mismatch_refusal(self):
        fx = dict(self.fixtures[0], sha256="0" * 64)
        with self.assertRaises(r.RunnerError):
            r.verify_fixture_bytes(fx, self.fdir)

    def test_binding_missing_requires_smoke_flag(self):
        with self.assertRaises(r.RunnerError) as cm:
            r.resolve_binding(self.shader, None, False, None)
        self.assertIn("pinned shader binding missing", str(cm.exception))

    def test_binding_mismatch_refusal(self):
        with self.assertRaises(r.RunnerError) as cm:
            r.resolve_binding(self.shader, {"repo": r.PIN_REPO, "commit": r.PIN_COMMIT,
                                            "path": r.PIN_PATH, "sha256": "0" * 64},
                              False, None)
        self.assertIn("mismatch", str(cm.exception))

    def test_binding_wrong_commit_refusal(self):
        binding_path = os.path.join(self.tmp, "binding.json")
        with open(binding_path, "w") as f:
            json.dump({"schema": r.BINDING_SCHEMA, "repo": r.PIN_REPO,
                       "commit": "0" * 40, "path": r.PIN_PATH, "sha256": "a" * 64}, f)
        with self.assertRaises(r.RunnerError):
            r.load_binding(binding_path)

    def test_binding_verified(self):
        binding_path = os.path.join(self.tmp, "binding.json")
        with open(binding_path, "w") as f:
            json.dump({"schema": r.BINDING_SCHEMA, "repo": r.PIN_REPO, "commit": r.PIN_COMMIT,
                       "path": r.PIN_PATH, "sha256": r.sha256_file(self.shader)}, f)
        status, expected, actual, blob = r.resolve_binding(self.shader, r.load_binding(binding_path),
                                                           False, None)
        self.assertEqual(status, "verified")
        self.assertEqual(expected, actual)
        self.assertEqual(len(blob), 40)


class TestLiveHistoricalShader(unittest.TestCase):
    def test_discovery_against_historical_copy(self):
        path = os.environ.get("VR180_HISTORICAL_LUA") or \
            "/tmp/bridge/packets/W-gdb-ops-p23-001-inputs/lua/vr180-look.lua"
        if not os.path.isfile(path):
            self.skipTest("historical vr180-look.lua not available")
        text = open(path, errors="replace").read()
        c = r.ShaderContract(text)
        self.assertEqual(c.pose_message, "vr180-look-set-orientation")
        self.assertEqual(c.pose_args["roll_index"], 3)
        r.check_route_arity(c)
        self.assertIn("flat-sbs", c.kinds)


if __name__ == "__main__":
    unittest.main(verbosity=2)
