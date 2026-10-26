#!/usr/bin/env python3
"""Spacing manifest-batch generator.

Inventory TSV (docs/collection/tiles-glyph-manifest.tsv layout) -> per-shard
engine manifests (main.rs parse_manifest line format) + receipts.

No literal counts are baked in: glyph count, shard count and every numeric
bound are derived from the selected style's own rows (tile heights, row count).
Required engine keys with no honest derivation (family, subfamily,
postscript_name, scale, fit_tolerance_policy) come from --meta; passthrough
engine keys come from --param. Missing required keys are a hard error.

SHARD SCOPE: shard manifests exist ONLY for stage-1 fit + cache. They must
never feed solve_spacing: W_target / stem / baseline / side classification
depend on the whole population. A full-population manifest (full.manifest,
all glyphs) is emitted for K2 and may point at the merged stage-1 cache via
--stage1-cache. Receipts carry purpose + solve_spacing_allowed.

Glyph image paths: manifest-relative by default (engine does base.join(path)
with base = manifest parent dir), or absolute with --absolute-paths. Every
tile must resolve inside --image-root.

usage: spacing_manifest_gen.py --inventory TSV --style 'Marq|Alternate'
         --image-root DIR --meta meta.txt --out OUT [--param params.txt]
         [--shards N | --shard-size N] [--verify-images] [--absolute-paths]
         [--stage1-cache PATH]
Read-only on inputs. Writes only under --out.
"""
import argparse, csv, hashlib, json, math, os, sys

REQUIRED_META = ["family", "subfamily", "postscript_name", "scale", "fit_tolerance_policy", "scan_row_step"]
PASSTHROUGH = {"vendor", "upm", "rdp_epsilon", "fit_squared_error", "fit_max_refits",
               "flatten_tolerance", "scan_row_step", "sample_resolution",
               "pair_min_shared_rows", "max_pairs", "max_pair_evaluations"}
DERIVED_ONLY = {"scan_max_rows"}  # derived from font-unit bbox height, never passed in
INV_COLS = ["style", "tile_index", "tile_file", "tile_sha256", "codepoint", "width_px", "height_px"]
SCHEMA = "spacing-manifest-receipt/2"
HEX = set("0123456789abcdef")

def sha256_bytes(b): return hashlib.sha256(b).hexdigest()

def read_kv(path):
    out = {}
    for ln, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.strip()
        if not line or line.startswith("#"): continue
        k, _, v = line.partition(" ")
        if not v.strip(): sys.exit(f"{path}:{ln}: key {k!r} has no value")
        if k in out: sys.exit(f"{path}:{ln}: duplicate key {k!r}")
        out[k] = v.strip()
    return out

def load_inventory(path, style):
    with open(path, encoding="utf-8", newline="") as f:
        rd = csv.DictReader(f, delimiter="\t")
        miss = [c for c in INV_COLS if c not in (rd.fieldnames or [])]
        if miss: sys.exit(f"inventory missing columns: {miss}")
        rows = [r for r in rd if r["style"] == style]
    if not rows:
        sys.exit(f"no inventory rows for style {style!r}")
    out, seen = [], {}
    for r in rows:
        t = r["tile_file"]
        cp = r["codepoint"]
        if not cp.startswith("U+") or not all(c in "0123456789ABCDEFabcdef" for c in cp[2:]) or not cp[2:]:
            sys.exit(f"bad codepoint {cp!r} (tile {t})")
        v = int(cp[2:], 16)
        if v > 0x10FFFF or 0xD800 <= v <= 0xDFFF:
            sys.exit(f"codepoint {cp} is not a Unicode scalar value (tile {t})")
        if v in seen: sys.exit(f"duplicate codepoint {cp} in style {style!r}: {seen[v]} / {t}")
        seen[v] = t
        sha = r["tile_sha256"]
        if len(sha) != 64 or not set(sha) <= HEX: sys.exit(f"tile_sha256 must be 64 lowercase hex: {t}")
        try: w, h = int(r["width_px"]), int(r["height_px"])
        except ValueError: sys.exit(f"non-integer width/height for {t}")
        if w <= 0 or h <= 0: sys.exit(f"width_px/height_px must be positive: {t} ({w}x{h})")
        if (not t or t != os.path.basename(t) or t in (".", "..") or "\\" in t or any(c.isspace() for c in t) or "\0" in t):
            sys.exit(f"tile_file must be a plain filename without separators/whitespace: {t!r}")
        out.append(dict(cp=v, name="uni%04X" % v, tile=t, sha=sha, w=w, h=h))
    out.sort(key=lambda g: g["cp"])
    return out

def split_shards(n, shards, shard_size):
    if shards and shard_size: sys.exit("use --shards or --shard-size, not both")
    if shard_size is None:
        shards = shards or math.ceil(math.sqrt(n))  # derived from the font's own glyph count
        shard_size = math.ceil(n / shards)
    shards = math.ceil(n / shard_size)
    return [(i * shard_size, min(n, (i + 1) * shard_size)) for i in range(shards)]

def scan_rows_upper_bound(height_units, row_step):
    return math.ceil(height_units / row_step) + 1

def derived_bounds(glyphs, scale, row_step):
    """scan_max_rows is a ROW count, an upper bound for the engine's anchored
    grid floor(miny/step)..ceil(maxy/step)-1 over any phase of miny:
    that count <= ceil((maxy-miny)/step) + 1. Font-unit height = pixel
    height * scale. Tested against the real profile_outline (cargo test
    scan_rows_bound). It is a bound, not a measurement. The grid bound does
    not cover thin-ring supplementary rows: those are one per grid-missed
    ring, bounded by the glyph's own ring count (an input property this
    generator never sees), so the engine accounts them separately."""
    n = len(glyphs)
    height_units = max(g["h"] for g in glyphs) * scale
    rows = scan_rows_upper_bound(height_units, row_step)
    pairs = n * (n - 1)
    return {"scan_max_rows": rows, "max_pairs": pairs, "max_pair_evaluations": pairs * rows}

def contained(root, p):
    root = os.path.realpath(root); p = os.path.realpath(p)
    return p == root or p.startswith(root + os.sep)

def fresh_out(out, image_root):
    """Exclusive create: --out must not exist (no reuse, no overwrite, no
    symlink hops). Canonical containment: it may not sit inside the image root
    or the inventory tree's image directory."""
    if os.path.lexists(out):
        sys.exit(f"refusing: output path already exists (fresh --out required, no overwrite): {out}")
    parent = os.path.dirname(os.path.abspath(out)) or "."
    if not os.path.isdir(parent): sys.exit(f"output parent is not a directory: {parent}")
    if contained(image_root, os.path.join(os.path.realpath(parent), os.path.basename(out))):
        sys.exit("refusing: --out resolves inside the image root")
    os.makedirs(out, exist_ok=False)

def population_pin(glyphs):
    """sha256 over sorted 'codepoint-hex:glyph-name\n' lines. The engine
    recomputes the same pin from the manifest's glyph rows (run_mode gate)."""
    lines = sorted("%x:%s\n" % (g["cp"], g["name"]) for g in glyphs)
    return sha256_bytes("".join(lines).encode())

def build_manifest(meta, extra, glyphs, header, base_dir, image_root, absolute, run_mode, pop, stage1_cache=None):
    lines = [header, f"family {meta['family']}", f"subfamily {meta['subfamily']}",
             f"postscript_name {meta['postscript_name']}", f"scale {meta['scale']}",
             f"fit_tolerance_policy {meta['fit_tolerance_policy']}"]
    for k in sorted(extra): lines.append(f"{k} {extra[k]}")
    lines += [f"run_mode {run_mode}", f"population_sha256 {pop}"]
    if stage1_cache: lines.append(f"stage1_cache {stage1_cache}")
    for g in glyphs:
        full = os.path.join(image_root, g["tile"])
        if not contained(image_root, full):
            sys.exit(f"tile escapes image root: {g['tile']}")
        path = os.path.abspath(full) if absolute else os.path.relpath(os.path.abspath(full), os.path.abspath(base_dir))
        if any(c.isspace() for c in path):
            sys.exit(f"path contains whitespace (engine splits on whitespace): {path!r}")
        lines.append(f"glyph 0x{g['cp']:04X} {g['name']} {path}")
    return "\n".join(lines) + "\n"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", required=True); ap.add_argument("--style", required=True)
    ap.add_argument("--image-root", required=True); ap.add_argument("--meta", required=True)
    ap.add_argument("--param"); ap.add_argument("--out", required=True)
    ap.add_argument("--shards", type=int); ap.add_argument("--shard-size", type=int)
    ap.add_argument("--verify-images", action="store_true")
    ap.add_argument("--absolute-paths", action="store_true")
    ap.add_argument("--stage1-cache")
    a = ap.parse_args()
    for v in (a.shards, a.shard_size):
        if v is not None and v < 1: sys.exit("--shards/--shard-size must be >= 1")

    meta = read_kv(a.meta)
    miss = [k for k in REQUIRED_META if k not in meta]
    if miss: sys.exit(f"meta missing required keys: {miss}")
    if meta["fit_tolerance_policy"] not in ("measured_experimental", "fixed"):
        sys.exit("fit_tolerance_policy must be measured_experimental|fixed")
    extra = {k: v for k, v in meta.items() if k in PASSTHROUGH}
    if a.param:
        for k, v in read_kv(a.param).items():
            if k in DERIVED_ONLY: sys.exit(f"{k} is derived, not a parameter")
            if k not in PASSTHROUGH: sys.exit(f"--param key {k!r} not an engine passthrough key")
            extra[k] = v
    if meta["fit_tolerance_policy"] == "fixed" and "fit_squared_error" not in extra:
        sys.exit("fixed policy requires explicit fit_squared_error")
    if "scan_row_step" in meta: extra["scan_row_step"] = meta["scan_row_step"]
    try:
        scale = float(meta["scale"]); step = float(extra["scan_row_step"])
        if not (math.isfinite(scale) and scale > 0 and math.isfinite(step) and step > 0): raise ValueError
    except ValueError: sys.exit("scale and scan_row_step must be finite and > 0")
    if not os.path.isdir(a.image_root): sys.exit(f"image root is not a directory: {a.image_root}")

    glyphs = load_inventory(a.inventory, a.style)
    n = len(glyphs)
    bounds = derived_bounds(glyphs, scale, step)
    for k, v in bounds.items(): extra.setdefault(k, str(v))
    inv_sha = sha256_bytes(open(a.inventory, "rb").read())

    if a.verify_images:
        bad = []
        for g in glyphs:
            p = os.path.join(a.image_root, g["tile"])
            if not contained(a.image_root, p): bad.append((g["tile"], "outside image root")); continue
            if not os.path.isfile(p): bad.append((g["tile"], "missing")); continue
            if sha256_bytes(open(p, "rb").read()) != g["sha"]: bad.append((g["tile"], "sha mismatch"))
        if bad: sys.exit(f"image verification failed ({len(bad)}): {bad[:5]}")

    dup = {}
    for g in glyphs: dup.setdefault(g["sha"], []).append(g["cp"])
    repeated = [{"tile_sha256": s_, "codepoints": ["U+%04X" % c for c in cps]} for s_, cps in dup.items() if len(cps) > 1]

    fresh_out(a.out, a.image_root)
    mdir = os.path.join(a.out, "manifests"); rdir = os.path.join(a.out, "receipts")
    os.makedirs(mdir); os.makedirs(rdir)
    pop = population_pin(glyphs)
    spans = split_shards(n, a.shards, a.shard_size)
    width = len(str(len(spans)))
    entries = []

    def emit(tag, part, purpose, solve_ok, cache, run_mode):
        header = f"# generated by spacing_manifest_gen.py; style={a.style}; {tag}; purpose={purpose}; inventory_sha256={inv_sha}"
        text = build_manifest(meta, extra, part, header, mdir, a.image_root, a.absolute_paths, run_mode, pop, cache)
        mpath = os.path.join(mdir, f"{tag}.manifest")
        open(mpath, "w", encoding="utf-8").write(text)
        rec = {"schema": SCHEMA, "style": a.style, "tag": tag, "purpose": purpose,
               "solve_spacing_allowed": solve_ok, "run_mode": run_mode, "population_sha256": pop, "manifest_file": os.path.basename(mpath),
               "manifest_sha256": sha256_bytes(text.encode()), "inventory_sha256": inv_sha,
               "image_root": os.path.abspath(a.image_root), "path_mode": "absolute" if a.absolute_paths else "manifest-relative",
               "images_verified": bool(a.verify_images), "glyph_count": len(part),
               "population_glyph_count": n,
               "glyphs": [{"codepoint": "U+%04X" % g["cp"], "glyph": g["name"], "tile": g["tile"],
                           "tile_sha256": g["sha"]} for g in part]}
        open(os.path.join(rdir, f"{tag}.receipt.json"), "w").write(json.dumps(rec, indent=2, ensure_ascii=False) + "\n")
        return {"tag": tag, "manifest": os.path.basename(mpath), "manifest_sha256": rec["manifest_sha256"],
                "glyph_count": len(part), "purpose": purpose, "solve_spacing_allowed": solve_ok}

    for i, (lo, hi) in enumerate(spans):
        tag = f"shard-{str(i + 1).zfill(width)}-of-{len(spans)}"
        entries.append(emit(tag, glyphs[lo:hi], "stage1_fit_cache_only", False, None, "stage1_only"))
    full = emit("full", glyphs, "full_population_solve", True, a.stage1_cache, "full")
    index = {"schema": SCHEMA + "/index", "style": a.style, "inventory": os.path.basename(a.inventory),
             "inventory_sha256": inv_sha, "glyph_count": n, "shard_count": len(spans),
             "derived_bounds": bounds, "repeated_tile_groups": repeated, "shards": entries, "full": full,
             "population_sha256": pop,
             "note": "shard manifests carry run_mode stage1_only: the engine stops before profiles/solve_spacing (typed gate, see engine patch). K2 runs once on full.manifest after stage1_cache_merge.py"}
    open(os.path.join(rdir, "index.receipt.json"), "w").write(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    print(f"style={a.style} glyphs={n} shards={len(spans)} out={a.out}")

if __name__ == "__main__":
    main()
