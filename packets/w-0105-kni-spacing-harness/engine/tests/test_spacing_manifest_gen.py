"""Tests run the ENGINE's real parse_manifest + check_run_mode: engine-run-mode.patch
is applied to a copy of kni-pipeline main.rs (KNI_PIPELINE_MAIN, the pre-patch file; an
already-patched file is used as is), the manifest section ('// ---- manifest' .. '// ---- bounded
flatten') is compiled into a harness binary, and every generated manifest is fed to it.
Missing cargo / main.rs / patch is a typed failure, never a skip."""
import csv, glob, hashlib, json, os, shutil, subprocess, sys, tempfile, unittest, math

GEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "spacing_manifest_gen.py")
HDR = ["style","tile_index","tile_file","tile_sha256","codepoint","unicode_name_derived","glyph_name_source","format","width_px","height_px","source_font_file_sha256"]
META = "family Fam\nsubfamily Sty\npostscript_name Fam-Sty\nscale 0.5\nfit_tolerance_policy measured_experimental\nscan_row_step 10\n"
HARNESS = {}

SHA_SHIM = r'''
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut m = data.to_vec(); let bl = (data.len() as u64) * 8;
    m.push(0x80); while m.len() % 64 != 56 { m.push(0); } m.extend_from_slice(&bl.to_be_bytes());
    for c in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([c[4*i],c[4*i+1],c[4*i+2],c[4*i+3]]); }
        for i in 16..64 { let s0 = w[i-15].rotate_right(7)^w[i-15].rotate_right(18)^(w[i-15]>>3); let s1 = w[i-2].rotate_right(17)^w[i-2].rotate_right(19)^(w[i-2]>>10); w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1); }
        let mut v = h;
        for i in 0..64 { let s1 = v[4].rotate_right(6)^v[4].rotate_right(11)^v[4].rotate_right(25); let ch = (v[4]&v[5])^(!v[4]&v[6]); let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]); let s0 = v[0].rotate_right(2)^v[0].rotate_right(13)^v[0].rotate_right(22); let mj = (v[0]&v[1])^(v[0]&v[2])^(v[1]&v[2]); let t2 = s0.wrapping_add(mj); v[7]=v[6]; v[6]=v[5]; v[5]=v[4]; v[4]=v[3].wrapping_add(t1); v[3]=v[2]; v[2]=v[1]; v[1]=v[0]; v[0]=t1.wrapping_add(t2); }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}
'''
PATCH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine", "engine-run-mode.patch")

def harness():
    if "bin" in HARNESS: return HARNESS["bin"]
    src = os.environ.get("KNI_PIPELINE_MAIN")
    cargo = shutil.which("cargo") or os.path.expanduser("~/.cargo/bin/cargo")
    if not src or not os.path.isfile(src): raise RuntimeError("KNI_PIPELINE_MAIN (kni-pipeline main.rs) is required")
    if not os.path.isfile(cargo): raise RuntimeError("cargo is required to run the engine parser")
    d = tempfile.mkdtemp(prefix="pmh-"); os.makedirs(d + "/src")
    shutil.copy(src, d + "/main.rs")
    if "run_mode" not in open(src).read():
        r = subprocess.run(["patch", "-s", d + "/main.rs", PATCH], capture_output=True, text=True)
        if r.returncode: raise RuntimeError("engine-run-mode.patch does not apply:\n" + r.stdout + r.stderr)
    text = open(d + "/main.rs").read()
    a = text.index("// ---------------- manifest"); b = text.index("// ---------------- bounded flatten")
    open(d + "/Cargo.toml", "w").write('[package]\nname="pmh"\nversion="0.0.0"\nedition="2021"\n')
    open(d + "/src/main.rs", "w").write("#![allow(dead_code)]\nuse std::fs;\nuse std::path::{Path, PathBuf};\n" + SHA_SHIM + text[a:b] + '''
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let text = fs::read_to_string(&a[1]).expect("read");
    let base = Path::new(&a[1]).parent().unwrap_or_else(|| Path::new(".")).to_path_buf();
    match parse_manifest(&text, &base).and_then(|m| check_run_mode(&m).map(|_| m)) {
        Ok(m) => { println!("OK {} {} {:?}", m.glyphs.len(), m.scan_max_rows, m.run_mode);
            for g in &m.glyphs { println!("G {:04X} {} {}", g.codepoint, g.name, g.image.is_file()); } }
        Err(e) => { println!("ERR {e}"); std::process::exit(3); }
    }
}
''')
    r = subprocess.run([cargo, "build", "--offline", "--manifest-path", d + "/Cargo.toml"], capture_output=True, text=True)
    if r.returncode: raise RuntimeError("harness build failed:\n" + r.stderr[-1500:])
    HARNESS["bin"] = d + "/target/debug/pmh"; return HARNESS["bin"]

def parse(manifest):
    b = harness()
    r = subprocess.run([b, manifest], capture_output=True, text=True)
    return r.returncode, r.stdout.strip().splitlines()

def make(d, n, style="Fam|Sty", images=True, hmax=None):
    os.makedirs(d + "/img", exist_ok=True)
    with open(d + "/inv.tsv", "w", newline="") as f:
        w = csv.writer(f, delimiter="\t"); w.writerow(HDR)
        for i in range(n):
            cp = 0x41 + i; b = b"png%d" % i
            fn = "%05d__%04X__x.png" % (i, cp)
            if images:
                with open(d + "/img/" + fn, "wb") as g: g.write(b)
            w.writerow([style, "%05d" % i, fn, hashlib.sha256(b).hexdigest(), "U+%04X" % cp, "X", "MISSING", "PNG", 100 + i % 7, (hmax or 200) - i % 5, "MISSING"])
    with open(d + "/meta.txt", "w") as f: f.write(META)

def run(d, *extra, meta="meta.txt", out="out"):
    return subprocess.run([sys.executable, GEN, "--inventory", d + "/inv.tsv", "--style", "Fam|Sty", "--image-root", d + "/img",
                           "--meta", d + "/" + meta, "--out", d + "/" + out, *extra], capture_output=True, text=True)

def edit_inv(d, old, new):
    t = open(d + "/inv.tsv").read().replace(old, new, 1)
    with open(d + "/inv.tsv", "w") as f: f.write(t)

class T(unittest.TestCase):
    def test_engine_parses_every_manifest_and_images_resolve(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 258)
            r = run(d, "--verify-images"); self.assertEqual(r.returncode, 0, r.stderr)
            idx = json.load(open(d + "/out/receipts/index.receipt.json"))
            total = 0
            for m in sorted(glob.glob(d + "/out/manifests/shard-*.manifest")):
                res = parse(m)
                if res is None: continue
                rc, lines = res; self.assertEqual(rc, 0, lines)
                gl = [l for l in lines if l.startswith("G ")]
                self.assertTrue(all(l.endswith("true") for l in gl), "image path did not resolve: " + str([l for l in gl if not l.endswith("true")][:2]))
                total += len(gl)
            if harness(): self.assertEqual(total, 258)
            self.assertEqual(sum(s["glyph_count"] for s in idx["shards"]), 258)
            self.assertEqual(idx["shard_count"], 17)
    def test_absolute_paths_also_resolve(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 6); self.assertEqual(run(d, "--absolute-paths").returncode, 0)
            res = parse(d + "/out/manifests/full.manifest")
            if res: self.assertTrue(all(l.endswith("true") for l in res[1] if l.startswith("G ")))
    def test_full_manifest_is_whole_population_and_shards_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 25); run(d, "--shard-size", "10", "--stage1-cache", "../cache/stage1.txt")
            idx = json.load(open(d + "/out/receipts/index.receipt.json"))
            self.assertEqual(idx["full"]["glyph_count"], 25); self.assertTrue(idx["full"]["solve_spacing_allowed"])
            self.assertTrue(all(not s["solve_spacing_allowed"] and s["purpose"] == "stage1_fit_cache_only" for s in idx["shards"]))
            full = open(d + "/out/manifests/full.manifest").read()
            self.assertIn("stage1_cache ../cache/stage1.txt", full)
            self.assertNotIn("stage1_cache", open(d + "/out/manifests/shard-1-of-3.manifest").read())
            if harness(): self.assertEqual(parse(d + "/out/manifests/full.manifest")[1][0].split()[1], "25")
    def test_scan_max_rows_from_font_unit_height_not_pixels(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 12, hmax=204); run(d)
            b = json.load(open(d + "/out/receipts/index.receipt.json"))["derived_bounds"]
            self.assertEqual(b["scan_max_rows"], math.ceil(204 * 0.5 / 10) + 1)   # 12 = anchored-phase bound, not 204
            self.assertEqual(b["max_pairs"], 12 * 11); self.assertEqual(b["max_pair_evaluations"], 12 * 11 * b["scan_max_rows"])
            res = parse(d + "/out/manifests/full.manifest")
            if res: self.assertEqual(res[1][0].split()[2], str(b["scan_max_rows"]))
    def test_scan_row_step_required_and_param_cannot_set_derived(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 3); open(d + "/m2.txt", "w").write(META.replace("scan_row_step 10\n", ""))
            r = run(d, meta="m2.txt"); self.assertNotEqual(r.returncode, 0); self.assertIn("scan_row_step", r.stderr)
            open(d + "/p.txt", "w").write("scan_max_rows 5\n")
            r = run(d, "--param", d + "/p.txt"); self.assertNotEqual(r.returncode, 0); self.assertIn("derived", r.stderr)
    def test_receipt_hash_matches_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 10); self.assertEqual(run(d).returncode, 0)
            for rp in glob.glob(d + "/out/receipts/*-of-*.json") + [d + "/out/receipts/full.receipt.json"]:
                r = json.load(open(rp)); t = open(d + "/out/manifests/" + r["manifest_file"], "rb").read()
                self.assertEqual(hashlib.sha256(t).hexdigest(), r["manifest_sha256"])
    def test_validation_failures(self):
        cases = [("U+0042", "U+D800", "Unicode scalar"), ("U+0042", "U+110000", "Unicode scalar"), ("U+0042", "0042", "bad codepoint"),
                 ("U+0042", "U+0041", "duplicate codepoint"), ("\t101\t", "\t0\t", "positive"), ("\t101\t", "\t-3\t", "positive")]
        for old, new, msg in cases:
            with tempfile.TemporaryDirectory() as d:
                make(d, 3); edit_inv(d, old, new)
                r = run(d); self.assertNotEqual(r.returncode, 0, (old, new)); self.assertIn(msg, r.stderr, (old, new, r.stderr))
        with tempfile.TemporaryDirectory() as d:
            make(d, 3); t = open(d + "/inv.tsv").read(); h = hashlib.sha256(b"png0").hexdigest()
            edit_inv(d, h, h.upper()); self.assertIn("lowercase hex", run(d).stderr)
    def test_path_containment(self):
        for bad in ["../evil.png", "sub/x.png", "/abs.png", "a b.png"]:
            with tempfile.TemporaryDirectory() as d:
                make(d, 3); edit_inv(d, "00000__0041__x.png", bad)
                r = run(d); self.assertNotEqual(r.returncode, 0, bad); self.assertIn("tile_file", r.stderr)
    def test_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as outside:
            make(d, 3); p = d + "/img/00000__0041__x.png"; os.remove(p)
            open(outside + "/t.png", "wb").write(b"png0"); os.symlink(outside + "/t.png", p)
            r = run(d, "--verify-images"); self.assertNotEqual(r.returncode, 0); self.assertIn("outside image root", r.stderr)
    def test_out_exclusive_create_no_reuse_no_symlink_no_force(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 8); self.assertEqual(run(d).returncode, 0)
            before = sorted(os.listdir(d + "/out/manifests"))
            r = run(d); self.assertNotEqual(r.returncode, 0); self.assertIn("already exists", r.stderr)
            self.assertEqual(before, sorted(os.listdir(d + "/out/manifests")))
            r = run(d, "--force", out="o3"); self.assertNotEqual(r.returncode, 0)   # flag removed
            os.symlink(d + "/out", d + "/link"); r = run(d, out="link"); self.assertNotEqual(r.returncode, 0)
            r = run(d, out="img/inside"); self.assertNotEqual(r.returncode, 0); self.assertIn("inside the image root", r.stderr)
    def test_run_mode_gate_enforced_by_engine_parser(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 25); run(d, "--shard-size", "10")
            sh = d + "/out/manifests/shard-1-of-3.manifest"
            rc, l = parse(sh); self.assertEqual(rc, 0, l); self.assertIn("Stage1Only", l[0])
            rc, l = parse(d + "/out/manifests/full.manifest"); self.assertEqual(rc, 0, l); self.assertIn("Full", l[0])
            t = open(sh).read()
            for bad, why in [(t.replace("run_mode stage1_only", "run_mode full"), "declared population"),
                             (t + "stage1_cache x.txt\n", "contradictory"),
                             (t.replace("run_mode stage1_only\n", ""), "run_mode is required"),
                             (t.replace("run_mode stage1_only", "run_mode bogus"), "bad run_mode")]:
                open(d + "/bad.manifest", "w").write(bad)
                rc, l = parse(d + "/bad.manifest"); self.assertEqual(rc, 3, bad[:0]); self.assertIn(why, l[0])
            f = open(d + "/out/manifests/full.manifest").read().splitlines()
            dropped = [x for x in f if not x.startswith("glyph 0x0041")]
            open(d + "/bad.manifest", "w").write("\n".join(dropped) + "\n")
            rc, l = parse(d + "/bad.manifest"); self.assertEqual(rc, 3); self.assertIn("declared population", l[0])
    def test_scan_rows_bound_formula_covers_every_phase(self):
        sys.path.insert(0, os.path.dirname(GEN)); import importlib; g = importlib.import_module("spacing_manifest_gen")
        step = 10.0
        for H in (1.0, 9.9, 10.0, 10.1, 99.5, 100.0, 105.0):
            bound = g.scan_rows_upper_bound(H, step)
            for k in range(0, 200):
                miny = k * 0.37 - 20.0; maxy = miny + H
                cells = math.ceil(maxy / step) - math.floor(miny / step)   # engine anchored-grid row count
                self.assertLessEqual(cells, bound, (H, miny))
        # the old formula was provably short for some phase
        self.assertTrue(any(math.ceil((m + 10.1) / 10) - math.floor(m / 10) > math.ceil(10.1 / 10) for m in [9.95]))
    def test_missing_meta_key_and_sha_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 3); open(d + "/m2.txt", "w").write("family Fam\n")
            self.assertIn("missing required", run(d, meta="m2.txt").stderr)
            with open(d + "/img/00001__0042__x.png", "wb") as f: f.write(b"tampered")
            self.assertIn("sha mismatch", run(d, "--verify-images", out="o2").stderr)
    def test_engine_rejects_nothing_we_emit_unknown_keys(self):
        with tempfile.TemporaryDirectory() as d:
            make(d, 5); run(d)
            res = parse(d + "/out/manifests/full.manifest")
            if res: self.assertEqual(res[0], 0, res[1])
if __name__ == "__main__": unittest.main()
