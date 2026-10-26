import os, sys, tempfile, unittest, hashlib
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import space_evidence_gen as g

META = """cp 0x20
style_id unit-regular
frame_id f1
scale 1.71
scale_method declared-test
calibration_source_role hsh
hh_kern zero
hh_kern_ref kern-off
hsh_kern zero
hsh_kern_ref kern-off
shaping_settings_ref capture-1
ligatures_disabled true
letter_spacing_px 0
sidebearing_policy allow_negative
max_input_bytes 1000
max_pixels 100
max_working_bytes 1000
hh_mode hhh
"""
class T(unittest.TestCase):
    def mk(self, meta=META, roles=None):
        d = tempfile.mkdtemp()
        os.makedirs(d + "/img")
        open(d + "/img/a.png", "wb").write(b"A"); open(d + "/img/b.png", "wb").write(b"B")
        open(d + "/meta.txt", "w").write(meta)
        roles = roles if roles is not None else "role\ttile_file\tidentity_ref\tframe\nhsh\ta.png\tm:hsh\tunit-regular/f1\nhhh\tb.png\tm:hhh\tunit-regular/f1\n"
        open(d + "/roles.tsv", "w").write(roles)
        return d
    def run_(self, d): return g.build(d + "/roles.tsv", d + "/img", d + "/meta.txt", d + "/out")
    def test_ok_and_pins(self):
        d = self.mk(); r = self.run_(d)
        spec = open(d + "/out/space-evidence.spec", "rb").read()
        self.assertEqual(r["spec_sha256"], hashlib.sha256(spec).hexdigest())
        self.assertIn(hashlib.sha256(b"A").hexdigest().encode(), spec)
        self.assertIn(b"shaping f=unit-regular/f1 capture-1 true 0 " + hashlib.sha256(b"A").hexdigest().encode() + b",", spec)
        sc = open(d + "/out/scale-record.txt").read()
        self.assertIn("units_per_px 1.71", sc)
        self.assertIn("calibration_source_sha256 " + hashlib.sha256(b"A").hexdigest(), sc)
    def test_hard_errors(self):
        for meta, roles in [
            (META.replace("hh_mode hhh\n", ""), None),
            (META + "extra 1\n", None),
            (META.replace("cp 0x20", "cp 0xA0"), None),
            (META, "role\ttile_file\tidentity_ref\tframe\nhsh\ta.png\tm\tunit-regular/f1\n"),
            (META, "role\ttile_file\tidentity_ref\tframe\nhsh\ta.png\tm\tunit-regular/f1\nhsh\tb.png\tm\tunit-regular/f1\n"),
            (META, "role\ttile_file\tidentity_ref\tframe\nhsh\t../meta.txt\tm\tunit-regular/f1\nhhh\tb.png\tm\tunit-regular/f1\n"),
            (META, "role\ttile_file\tidentity_ref\tframe\nhsh\ta.png\tm\tother/f1\nhhh\tb.png\tm\tunit-regular/f1\n"),
            (META.replace("hh_kern zero", "hh_kern known"), None),
        ]:
            with self.assertRaises(SystemExit):
                self.run_(self.mk(meta, roles))
    SLOPE = """cp 0x20
style_id unit-regular
frame_id f1
scale 1.71
scale_method declared-test
calibration_source_role slope1
slope_kern_ref kern-off
slope_max_points 16
ink_delta 8
ink_ref notdef_audit.py:INK_DELTA:a88d1ad6
shaping_settings_ref capture-1
ligatures_disabled true
letter_spacing_px 0
max_input_bytes 1000
max_pixels 100
max_working_bytes 1000
hh_mode slope
"""
    SR = "role\ttile_file\tidentity_ref\tframe\nslope1\ta.png\tl:1\tunit-regular/f1\nslope2\tb.png\tl:2\tunit-regular/f1\nslope3\tc.png\tl:3\tunit-regular/f1\n"
    def mk3(self, meta, roles, same=False):
        d = self.mk(meta, roles)
        open(d + "/img/c.png", "wb").write(b"B" if same else b"C")
        return d
    def test_slope_rows_and_contract(self):
        d = self.mk3(self.SLOPE, self.SR); self.run_(d)
        spec = open(d + "/out/space-evidence.spec").read()
        self.assertEqual(spec.count("slope_tile "), 3)
        self.assertIn("slope_tile f=unit-regular/f1 2 ", spec)
        self.assertIn("slope_kern f=unit-regular/f1 zero kern-off", spec)
        self.assertNotIn("renderer_contract", spec)
        self.assertIn("ink_model border_median_delta 8 notdef_audit.py:INK_DELTA:a88d1ad6", spec)
        self.assertNotIn("hh_kern", spec)
        c = "renderer_model binary_pixel_center\nrenderer_transform_ref t\nrenderer_dpr_ref d\nrenderer_filter_ref f\nrenderer_threshold_ref th\nrenderer_compression_ref c\nrenderer_clipping_ref cl\n"
        d = self.mk3(self.SLOPE + c, self.SR); self.run_(d)
        self.assertIn("renderer_contract binary_pixel_center t d f th c cl", open(d + "/out/space-evidence.spec").read())
    def test_slope_hard_errors(self):
        for meta, roles, same in [
            (self.SLOPE, self.SR, True),  # aliased tiles
            (self.SLOPE + "renderer_model binary_pixel_center\n", self.SR, False),  # partial contract
            (self.SLOPE, self.SR.replace("slope3\tc.png", "hsh\tc.png"), False),
            (self.SLOPE.replace("slope_kern_ref kern-off\n", ""), self.SR, False),
            (self.SLOPE.replace("ink_delta 8\n", ""), self.SR, False),
            (self.SLOPE.replace("slope_max_points 16\n", ""), self.SR, False),
            (META + "renderer_model binary_pixel_center\n", None, False),
        ]:
            with self.assertRaises(SystemExit):
                self.run_(self.mk3(meta, roles, same))
    def test_bounded_reads_before_any_output(self):
        # a 2-byte tile with max_input_bytes 1 -> typed refusal, and NOTHING is written under out/
        d = self.mk(META.replace("max_input_bytes 1000", "max_input_bytes 1")); open(d + "/img/a.png", "wb").write(b"AA")
        with self.assertRaises(SystemExit) as c: self.run_(d)
        self.assertIn("ResourceLimit", str(c.exception)); self.assertFalse(os.path.exists(d + "/out"))
        # total over max_working_bytes: roles text alone is larger than 3 bytes
        d = self.mk(META.replace("max_working_bytes 1000", "max_working_bytes 3"))
        with self.assertRaises(SystemExit) as c: self.run_(d)
        self.assertIn("max_working_bytes", str(c.exception)); self.assertFalse(os.path.exists(d + "/out"))
    def test_tile_exactly_at_cap_passes_one_over_refuses(self):
        d = self.mk(META.replace("max_input_bytes 1000", "max_input_bytes 2")); open(d + "/img/a.png", "wb").write(b"AA"); self.run_(d)
        d = self.mk(META.replace("max_input_bytes 1000", "max_input_bytes 2")); open(d + "/img/a.png", "wb").write(b"AAA")
        with self.assertRaises(SystemExit): self.run_(d)
    def test_cap_is_min_of_input_cap_and_remaining_budget_and_no_open_when_over(self):
        calls = []; real = g.read_bounded
        def spy(path, cap, what): calls.append((os.path.basename(path), cap)); return real(path, cap, what)
        d = self.mk(META.replace("max_working_bytes 1000", "max_working_bytes 200"))
        rl = os.path.getsize(d + "/roles.tsv"); g.read_bounded = spy
        try: self.run_(d)
        finally: g.read_bounded = real
        self.assertIn(("a.png", 200 - rl), calls); self.assertIn(("b.png", 200 - rl - 1), calls)
        calls.clear(); d = self.mk(META.replace("max_working_bytes 1000", "max_working_bytes 3")); g.read_bounded = spy
        try:
            with self.assertRaises(SystemExit): self.run_(d)
        finally: g.read_bounded = real
        self.assertEqual([c for c in calls if c[0].endswith(".png")], [])  # no tile opened once roles already exceed the budget
    def test_read_is_cap_plus_one(self):
        calls = []; real = g.read_bounded
        def spy(path, cap, what): calls.append((os.path.basename(path), cap)); return real(path, cap, what)
        g.read_bounded = spy
        d = self.mk(); rl = os.path.getsize(d + "/roles.tsv")
        try: self.run_(d)
        finally: g.read_bounded = real
        self.assertIn(("a.png", 1000 - rl), calls)  # min(max_input_bytes 1000, budget 1000 - roles text)
    def test_oversized_meta_and_roles_refused(self):
        d = self.mk(); open(d + "/meta.txt", "w").write(META + "# " + "x" * (1 << 20) + "\n")
        with self.assertRaises(SystemExit) as c: self.run_(d)
        self.assertIn("ResourceLimit", str(c.exception))
        d = self.mk(); open(d + "/roles.tsv", "a").write("#" + "x" * (1 << 20))
        with self.assertRaises(SystemExit) as c: self.run_(d)
        self.assertIn("ResourceLimit", str(c.exception))
if __name__ == "__main__": unittest.main()
