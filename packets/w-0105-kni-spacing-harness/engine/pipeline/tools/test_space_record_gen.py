import hashlib, json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import space_record_gen as g

STYLE = "Karl Nawrot Typefaces/F/S"   # real folder names contain spaces
REC = {"cp": "0x20", "style_id": "f-s", "frame_id": "f1", "scale": "1.71", "scale_method": "declared-test", "calibration_source_role": "slope1",
       "slope_kern_ref": "kern-off", "slope_max_points": "16", "ink_delta": "8", "ink_ref": "notdef_audit.py:INK_DELTA:a88d1ad6",
       "shaping_settings_ref": "capture-1", "ligatures_disabled": "true", "letter_spacing_px": "0",
       "max_input_bytes": "1000", "max_pixels": "100", "max_working_bytes": "40000", "hh_mode": "slope"}
def mk(items, sha_override=None):
    d = tempfile.mkdtemp(); rows = []
    for ident, text, rel, data in items:
        p = os.path.join(d, STYLE, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "wb").write(data)
        rows.append({"kind": "send_intent", "id": ident, "controls_sanitized": [["text", text], ["letter_spacing", "0"], ["font_size", "100"]], "controls_semantic_sha256": hashlib.sha256(("sem-" + str(len(text))).encode()).hexdigest(), "send_id": hashlib.sha256(ident.encode()).hexdigest()[:32]})
        rows.append({"kind": "response", "ok": True, "id": ident, "asset": {"path": f"{STYLE}/{rel}", "sha256": hashlib.sha256(data).hexdigest()}, "style_glyph_identity": "UNVERIFIED", "send_id": hashlib.sha256(ident.encode()).hexdigest()[:32]})
    lp = os.path.join(d, "ledger.jsonl"); open(lp, "w").write("\n".join(json.dumps(r) for r in rows) + "\n"); return d, lp
ITEMS = [("a", "H H", "sidebearing/sb/zzz.png", b"one"), ("b", "H  H", "sidebearing/sb/yyy.png", b"two!"), ("c", "H   H", "sidebearing/sb/xxx.png", b"three")]
class T(unittest.TestCase):
    def out(self): return os.path.join(tempfile.mkdtemp(), "o")
    def test_roles_from_ledger_not_filename_and_row_emitted(self):
        d, lp = mk(ITEMS); r = g.build_space_inputs(d, STYLE, lp, self.out(), REC)
        roles = open(r["roles_tsv"]).read().splitlines()
        self.assertEqual([x.split("\t")[0] for x in roles[1:]], ["slope1", "slope2", "slope3"])
        self.assertTrue(r["manifest_row"].startswith("space_evidence space-evidence.spec "))
        self.assertIn(hashlib.sha256(b"two!").hexdigest()[:12], roles[2])   # n=2 tile is the file named yyy, picked by submitted text
        self.assertTrue(os.path.isfile(os.path.join(r["out"], "manifest-row.txt")))
    def test_alias_across_counts_hard_error(self):
        d, lp = mk([ITEMS[0], ("b", "H  H", "sidebearing/sb/yyy.png", b"one"), ITEMS[2]])
        with self.assertRaises(g.SpaceRecordError) as c: g.build_space_inputs(d, STYLE, lp, self.out(), REC)
        self.assertIn("ALIASED_TILES", str(c.exception))
    def test_missing_record_writes_nothing(self):
        d, lp = mk(ITEMS[:2]); o = self.out()
        with self.assertRaises(g.SpaceRecordError) as c: g.build_space_inputs(d, STYLE, lp, o, REC)
        self.assertIn("[3]", str(c.exception)); self.assertFalse(os.path.exists(o))
    def test_same_bytes_two_ids_same_count_collapse_ok(self):
        d, lp = mk(ITEMS + [("a2", "H H", "sidebearing/reference/a.png", b"one")]); r = g.build_space_inputs(d, STYLE, lp, self.out(), REC)
        self.assertIn("a,a2", open(r["roles_tsv"]).read())
    def test_missing_or_bad_record_refused(self):
        d, lp = mk(ITEMS)
        for rec in ({k: v for k, v in REC.items() if k != "scale"}, dict(REC, scale="1 71"), dict(REC, hh_mode="hhh"), {}):
            with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, lp, self.out(), rec)
    def test_tampered_asset_refused_and_no_ledger_match_refused(self):
        d, lp = mk(ITEMS); open(os.path.join(d, STYLE, "sidebearing/sb/yyy.png"), "wb").write(b"X")
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, lp, self.out(), REC)
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, "/nonexistent/*.jsonl", self.out(), REC)
    def test_bounded_gen_enforced_through_builder(self):
        d, lp = mk(ITEMS)
        with self.assertRaises(g.SpaceRecordError) as c: g.build_space_inputs(d, STYLE, lp, self.out(), dict(REC, max_input_bytes="4"))
        self.assertIn("ResourceLimit", str(c.exception))
    def test_explicit_mode_needs_only_n1(self):
        d, lp = mk(ITEMS[:1]); rec = {k: v for k, v in REC.items() if not k.startswith(("slope", "ink"))}
        rec.update(hh_mode="explicit", calibration_source_role="hsh", hh_kern="zero", hh_kern_ref="k", hsh_kern="zero", hsh_kern_ref="k", sidebearing_policy="allow_negative", explicit_lsb_px="1", explicit_rsb_px="1", explicit_ref="r")
        r = g.build_space_inputs(d, STYLE, lp, self.out(), rec); self.assertIn("hsh_tile", open(os.path.join(r["out"], "space-evidence.spec")).read())
    def test_existing_out_dir_refused_and_no_leftovers(self):
        d, lp = mk(ITEMS); par = tempfile.mkdtemp(); o = os.path.join(par, "o"); os.mkdir(o)
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, lp, o, REC)
        o2 = os.path.join(par, "o2")
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, lp, o2, dict(REC, scale="x"))   # bad record found late (inside gen)
        self.assertFalse(os.path.exists(o2)); self.assertEqual(sorted(os.listdir(par)), ["o"])                   # temp dir removed too
    def test_path_containment(self):
        d, lp = mk(ITEMS); par = tempfile.mkdtemp()
        for st in ("../x", "/etc", STYLE + "/../../.."):
            with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, st, lp, os.path.join(par, "a"), REC)
        outside = os.path.join(par, "ledger.jsonl"); open(outside, "w").write(open(lp).read())
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, outside, os.path.join(par, "b"), REC)
        os.symlink(outside, os.path.join(d, "link.jsonl"))
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, os.path.join(d, "link.jsonl"), os.path.join(par, "c"), REC)
        self.assertEqual(os.listdir(par), ["ledger.jsonl"])
    def test_receipt_paths_point_at_published_dir(self):
        d, lp = mk(ITEMS); par = tempfile.mkdtemp(); o = os.path.join(par, "o"); r = g.build_space_inputs(d, STYLE, lp, o, REC)
        rc = open(os.path.join(r["out"], "receipt.tsv")).read(); self.assertIn(os.path.realpath(o), rc); self.assertNotIn(".space-record-", rc)
        for ln in rc.splitlines()[1:4]: self.assertTrue(os.path.isfile(ln.split("\t")[1]))
    def test_budget_charged_for_copy_reads_too(self):
        d, lp = mk(ITEMS); sz = os.path.getsize(lp); tiles = 3 + 4 + 5
        with self.assertRaises(g.SpaceRecordError) as c: g.build_space_inputs(d, STYLE, lp, os.path.join(tempfile.mkdtemp(), "o"), dict(REC, max_working_bytes=str(sz + tiles + 2)))
        self.assertIn("ResourceLimit", str(c.exception))
        r = g.build_space_inputs(d, STYLE, lp, os.path.join(tempfile.mkdtemp(), "o"), dict(REC, max_working_bytes=str(sz + 2 * tiles + 400)))
        self.assertIn("manifest_row", r)
    def test_noclobber_rename_refuses_existing_empty_dir_and_simulated_race(self):
        par = tempfile.mkdtemp(); a = os.path.join(par, "a"); b = os.path.join(par, "b"); os.mkdir(a); os.mkdir(b)
        with self.assertRaises(g.SpaceRecordError): g.noclobber_rename(a, b)      # os.rename would have replaced the empty dir
        self.assertTrue(os.path.isdir(a)); self.assertTrue(os.path.isdir(b))
        d, lp = mk(ITEMS); o = os.path.join(par, "o"); real = os.path.lexists; calls = []
        def late(p):   # the precheck sees "absent"; the dir appears right after (race)
            r = real(p)
            if p == o and not calls: calls.append(1); os.mkdir(o); return False
            return real(p)
        os.path.lexists = late
        try:
            with self.assertRaises(g.SpaceRecordError) as c: g.build_space_inputs(d, STYLE, lp, o, REC)
        finally: os.path.lexists = real
        self.assertIn("no overwrite", str(c.exception)); self.assertEqual(os.listdir(o), []); self.assertEqual(sorted(os.listdir(par)), ["a", "b", "o"])
    def test_tile_copy_path_contained(self):
        d, lp = mk(ITEMS); outside = os.path.join(tempfile.mkdtemp(), "x.png"); open(outside, "wb").write(b"two!")
        os.remove(os.path.join(d, STYLE, "sidebearing/sb/yyy.png")); os.symlink(outside, os.path.join(d, STYLE, "sidebearing/sb/yyy.png"))
        with self.assertRaises(g.SpaceRecordError): g.build_space_inputs(d, STYLE, lp, self.out(), REC)
class BindingAndOutputTests(unittest.TestCase):
    def test_records_ls_mutation_refuses_without_output(self):
        d, lp = mk(ITEMS); o = os.path.join(tempfile.mkdtemp(), 'out')
        with self.assertRaisesRegex(g.SpaceRecordError, 'ControlsConflict'):
            g.build_space_inputs(d, STYLE, lp, o, dict(REC, letter_spacing_px='1'))
        self.assertFalse(os.path.lexists(o))

    def test_collection_output_refuses_without_any_write(self):
        d, lp = mk(ITEMS)
        before = sorted(os.path.relpath(os.path.join(p, f), d) for p, _, fs in os.walk(d) for f in fs)
        with self.assertRaisesRegex(g.SpaceRecordError, 'OutputTreeConflict'):
            g.build_space_inputs(d, STYLE, lp, os.path.join(d, 'output'), REC)
        after = sorted(os.path.relpath(os.path.join(p, f), d) for p, _, fs in os.walk(d) for f in fs)
        self.assertEqual(before, after)
        self.assertFalse(os.path.exists(os.path.join(d, 'output')))

    def test_engine_output_and_symlink_refuse_before_temp_build(self):
        import unittest.mock as mock
        d, lp = mk(ITEMS)
        # Assert the installed layout independently of the generator's guard formula.
        from pathlib import Path
        module = Path(g.__file__).resolve()
        self.assertEqual(module.parent.name, 'tools')
        self.assertEqual(module.parent.parent.name, 'pipeline')
        engine = module.parents[2]
        self.assertEqual(engine.name, 'engine')
        par = tempfile.TemporaryDirectory()
        self.addCleanup(par.cleanup)
        with mock.patch.object(g.tempfile, 'mkdtemp', side_effect=AssertionError('temp build reached')):
            with self.assertRaisesRegex(g.SpaceRecordError, 'OutputTreeConflict'):
                g.build_space_inputs(d, STYLE, lp, os.path.join(engine, 'out'), REC)
            for subtree in ('metrics', 'pipeline'):
                with self.subTest(subtree=subtree), self.assertRaisesRegex(g.SpaceRecordError, 'OutputTreeConflict'):
                    g.build_space_inputs(d, STYLE, lp, os.path.join(engine, subtree, 'correction-probe-out'), REC)
            try:
                os.symlink(d, os.path.join(par.name, 'collection-link'))
                with self.assertRaisesRegex(g.SpaceRecordError, 'OutputTreeConflict'):
                    g.build_space_inputs(d, STYLE, lp, os.path.join(par.name, 'collection-link', 'out'), REC)
            finally:
                par.cleanup()

    def test_control_hash_chains_through_receipt_spec_and_manifest(self):
        d, lp = mk(ITEMS); o = os.path.join(tempfile.mkdtemp(), 'out')
        result = g.build_space_inputs(d, STYLE, lp, o, REC)
        spec = open(os.path.join(result['out'], 'space-evidence.spec'), 'rb').read()
        receipt = open(os.path.join(result['out'], 'receipt.tsv')).read()
        self.assertIn(hashlib.sha256(spec).hexdigest(), result['manifest_row'])
        for row in g.ssr.roles(d, STYLE, [lp], 1000, 40000):
            self.assertIn(':control_hash:'+row[8], spec.decode())
            self.assertIn(row[8], receipt)
        self.assertIn('letter_spacing-compared', receipt)

if __name__ == "__main__": unittest.main()
