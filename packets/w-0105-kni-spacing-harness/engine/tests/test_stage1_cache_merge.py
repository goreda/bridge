"""Real engine-written stage1 cache sample (6 glyphs) split into shards. Receipts are synthesized
in the engine's receipt.txt line format (manifest_pin / run_mode rows)."""
import csv, glob, hashlib, importlib.util, json, os, subprocess, sys, tempfile, unittest
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GEN = ROOT + "/tools/spacing_manifest_gen.py"; MRG = ROOT + "/tools/stage1_cache_merge.py"
SAMPLE = os.environ.get("KNI_STAGE1_CACHE_SAMPLE", "/downloads/stage1-cache-843c0cb5.txt")
HDR = ["style","tile_index","tile_file","tile_sha256","codepoint","unicode_name_derived","glyph_name_source","format","width_px","height_px","source_font_file_sha256"]
def sh(*a): return subprocess.run([sys.executable, *a], capture_output=True, text=True)
def fsha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
spec = importlib.util.spec_from_file_location("mrg", MRG); mrg = importlib.util.module_from_spec(spec); spec.loader.exec_module(mrg)

class T(unittest.TestCase):
    def setUp(self):
        self.d = d = tempfile.mkdtemp()
        text = open(SAMPLE).read(); L = text.split("\n")
        self.header = L[:3]
        self.blocks, self.order, i = {}, [], 3
        while i < len(L) and L[i]:
            f = L[i].split("\t"); cp = int(f[3], 16); uni = "uni%04X" % cp
            first = "\t".join([f[0], uni] + f[2:])
            if f[0] == "excluded": blk = [first]; i += 1
            else:
                j = i
                while L[j] != "end": j += 1
                blk = [first] + L[i + 1:j + 1]; i = j + 1
            self.blocks[cp] = (blk, f[5]); self.order.append(cp)
        os.makedirs(d + "/img")
        with open(d + "/inv.tsv", "w", newline="") as f:
            w = csv.writer(f, delimiter="\t"); w.writerow(HDR)
            for k, cp in enumerate(self.order):
                fn = "%05d__%04X__x.png" % (k, cp); open(d + "/img/" + fn, "wb").write(b"x")
                w.writerow(["F|S", "%05d" % k, fn, self.blocks[cp][1], "U+%04X" % cp, "X", "M", "PNG", 100, 100, "M"])
        pol = self.header[1].split("\t"); scale = pol[2]
        open(d + "/meta.txt", "w").write("family F\nsubfamily S\npostscript_name F-S\nscale %s\nfit_tolerance_policy fixed\nfit_squared_error 0.25\nscan_row_step 10\n" % repr(float(scale)))
        r = sh(GEN, "--inventory", d + "/inv.tsv", "--style", "F|S", "--image-root", d + "/img", "--meta", d + "/meta.txt", "--out", d + "/out", "--shards", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.fm = d + "/out/manifests/full.manifest"; self.fsha = fsha(self.fm)
        self.pop = json.load(open(d + "/out/receipts/index.receipt.json"))["population_sha256"]
        self.sm = sorted(glob.glob(d + "/out/manifests/shard-*.manifest")); self.sc, self.sr = [], []
        for k, m in enumerate(self.sm):
            cps = [int(l.split()[1], 16) for l in open(m) if l.startswith("glyph ")]
            open(f"{d}/cache{k}.txt", "w").write("\n".join(self.header) + "\n" + "".join("\n".join(self.blocks[c][0]) + "\n" for c in cps))
            self.write_receipt(k, m); self.sc.append(f"{d}/cache{k}.txt"); self.sr.append(f"{d}/receipt{k}.txt")
    def write_receipt(self, k, m, extra=""):
        open(f"{self.d}/receipt{k}.txt", "w").write(f"manifest_pin\t{fsha(m)}\nrun_mode\tstage1_only\tsolve_spacing\tNOT_RUN\tpopulation_sha256\t{self.pop}\tglyphs\t2\n" + extra)
    def args(self, cmd, **kw):
        a = [MRG, cmd, "--full-manifest", self.d + "/out/manifests/full.manifest", "--full-manifest-sha256", kw.get("fsha", self.fsha),
             "--frozen-population-sha256", kw.get("pop", self.pop)]
        return a
    def merge(self, out="merged.txt", sc=None, sm=None, sr=None, extra=(), **kw):
        a = self.args("merge", **kw) + ["--out", self.d + "/" + out, *extra]
        for m, c, r in zip(sm or self.sm, sc or self.sc, sr or self.sr): a += ["--shard-manifest", m, "--shard-cache", c, "--shard-receipt", r]
        return sh(*a)
    def verify(self, *extra, **kw): return sh(*self.args("verify", **kw), "--cache", self.d + "/merged.txt", *extra)
    def ok(self):
        r = self.merge(); self.assertEqual(r.returncode, 0, r.stderr); return r
    def pinfile(self): return self.d + "/merged.txt.pin.json"

    def test_merge_verify_blocks_byte_exact(self):
        self.ok(); merged = open(self.d + "/merged.txt").read()
        for blk, _ in self.blocks.values(): self.assertIn("\n".join(blk) + "\n", merged)
        v = self.verify(); self.assertEqual(v.returncode, 0, v.stderr); self.assertIn("CLEAN", v.stdout)
    def test_verify_rejects_empty_or_short_pin_and_bad_schema(self):
        self.ok(); p = json.load(open(self.pinfile()))
        for mut, msg in [(lambda x: x.update(glyphs=[], count=0), "count"), (lambda x: x["glyphs"].pop(), "count"),
                         (lambda x: x.update(extra=1), "schema"), (lambda x: x["glyphs"][0].update(name="evil"), "mismatch"),
                         (lambda x: x["glyphs"][1].update(block_sha256="0" * 64), "mismatch"), (lambda x: x.update(schema="old"), "schema")]:
            q = json.loads(json.dumps(p)); mut(q); open(self.pinfile(), "w").write(json.dumps(q))
            r = self.verify(); self.assertNotEqual(r.returncode, 0, msg); self.assertIn(msg, r.stderr)
    def test_verify_invalidation(self):
        self.ok(); exe = self.header[2].split("\t")[1]
        self.assertEqual(self.verify("--engine-exe-sha256", exe).returncode, 0)
        self.assertIn("engine executable changed", self.verify("--engine-exe-sha256", "0" * 64).stderr)
        open(self.d + "/merged.txt", "a").write("x"); self.assertIn("changed since merge", self.verify().stderr)
    def test_external_pins_required_and_checked(self):
        self.assertIn("externally supplied", self.merge(fsha="0" * 64).stderr)
        self.assertIn("externally frozen", self.merge(pop="1" * 64).stderr)
        self.ok(); self.assertNotEqual(self.verify(pop="1" * 64).returncode, 0)
    def test_name_binding_block_name_vs_full_manifest(self):
        t = open(self.sc[0]).read().replace("glyph\tuni", "glyph\tX", 1); open(self.sc[0], "w").write(t)
        r = self.merge(); self.assertNotEqual(r.returncode, 0); self.assertIn("(cp,name,order)", r.stderr)
    def test_policy_bound_to_full_manifest(self):
        for k in (0, 1):
            t = open(self.sc[k]).read().replace("fit_max_refits\t8", "fit_max_refits\t9"); open(self.sc[k], "w").write(t)
        r = self.merge(); self.assertNotEqual(r.returncode, 0); self.assertIn("policy line", r.stderr)
    def test_receipt_json_duplicate_key_dup_cp_and_manifest_hash(self):
        rp = self.d + "/out/receipts/full.receipt.json"; t = open(rp).read(); orig = t
        open(rp, "w").write(t.replace('"style"', '"style": "x", "style"', 1)); self.assertIn("duplicate JSON key", self.merge().stderr)
        j = json.loads(orig); j["glyphs"][1]["codepoint"] = j["glyphs"][0]["codepoint"]; open(rp, "w").write(json.dumps(j))
        self.assertNotEqual(self.merge().returncode, 0)
        j = json.loads(orig); j["manifest_sha256"] = "0" * 64; open(rp, "w").write(json.dumps(j)); self.assertIn("manifest_sha256", self.merge().stderr)
        j = json.loads(orig); j["glyphs"][0]["glyph"] = "evil"; open(rp, "w").write(json.dumps(j)); self.assertIn("receipt row", self.merge().stderr)
    def test_cache_alone_is_not_completion(self):
        open(self.sr[0], "w").write("manifest_pin\t" + "0" * 64 + "\n")
        r = self.merge(); self.assertNotEqual(r.returncode, 0); self.assertIn("manifest_pin", r.stderr)
        open(self.sr[0], "w").write(""); self.assertNotEqual(self.merge().returncode, 0)
    def test_diagnostic_fit_is_explicit_and_recorded(self):
        self.write_receipt(0, self.sm[0], "export_intent\tdiagnostic_test_export\tTEST/UNVALIDATED\nfallback_ledger_total\t101\tx\n")
        r = self.merge(); self.assertNotEqual(r.returncode, 0); self.assertIn("FIT_DIAGNOSTIC", r.stderr)
        r = self.merge(extra=["--accept-diagnostic-fit"]); self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.load(open(self.pinfile()))["fit_status"], "FIT_DIAGNOSTIC"); self.assertIn("FIT_DIAGNOSTIC", self.verify().stdout)
    def test_missing_shard_duplicate_header_png_overwrite(self):
        r = self.merge(sc=self.sc[:1], sm=self.sm[:1], sr=self.sr[:1]); self.assertNotEqual(r.returncode, 0); self.assertIn("union", r.stderr)
        r = self.merge(sc=[self.sc[0], self.sc[0]], sr=self.sr); self.assertNotEqual(r.returncode, 0)
        t = open(self.sc[0]).read(); h = self.blocks[self.order[0]][1]
        open(self.sc[0], "w").write(t.replace(h, "0" * 64)); self.assertIn("png_sha256", self.merge().stderr)
        open(self.sc[0], "w").write(t); self.ok(); self.assertIn("refusing to overwrite", self.merge().stderr)
    def test_commit_rollback_when_pin_publish_fails(self):
        out = self.d + "/c.txt"; real = os.link; n = {"c": 0}
        def flaky(a, b, *x, **k):
            n["c"] += 1
            if n["c"] == 2: raise OSError("simulated")
            return real(a, b, *x, **k)
        mrg.os.link = flaky
        try:
            with self.assertRaises(SystemExit): mrg.commit(out, "body\n", "{}\n")
        finally: mrg.os.link = real
        self.assertFalse(os.path.lexists(out)); self.assertFalse(os.path.lexists(out + ".pin.json"))
        self.assertEqual([f for f in os.listdir(self.d) if ".tmp-" in f], [])
    def test_unpinned_cache_refused(self):
        self.ok(); os.remove(self.pinfile()); self.assertIn("uncommitted", self.verify().stderr)
if __name__ == "__main__": unittest.main()
