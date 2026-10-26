#!/usr/bin/env python3
"""Merge per-shard stage-1 caches into one full-population cache, with a pin.

  merge : stage1_cache_merge.py merge --full-manifest FULL --full-manifest-sha256 HEX
              --frozen-population-sha256 HEX
              (--shard-manifest M --shard-cache C --shard-receipt R)... --out MERGED
              [--accept-diagnostic-fit]
  verify: stage1_cache_merge.py verify --full-manifest FULL --full-manifest-sha256 HEX
              --frozen-population-sha256 HEX --cache MERGED [--engine-exe-sha256 HEX]

TRUST MODEL (read this): --full-manifest-sha256 and --frozen-population-sha256 are
supplied EXTERNALLY (wrapper / frozen inventory attestation). A population pin a
manifest declares about itself is only a routing check; this tool does not claim
that it proves the 478-glyph identity, the externally frozen values do.
COMPLETION: a stage1-cache.txt is written before the engine's stage-1 hard gates, so a
cache file alone is NOT a completed run. Each shard needs the engine's receipt.txt
(written only after those gates) whose manifest_pin == sha256(shard manifest) and
run_mode stage1_only. A receipt carrying the diagnostic export intent (fallback ledger
> 0) is fit_status FIT_DIAGNOSTIC and is refused unless --accept-diagnostic-fit, and
the pin records it. CLEAN and FIT_DIAGNOSTIC are different outcomes, never merged.
COMMIT: cache is linked first, pin last; the pin is the commit marker. Failure after
the cache link rolls it back (or renames it .partial). Two files are not one atomic
write; an unpinned cache is uncommitted and verify refuses it.
"""
import argparse, hashlib, json, os, sys
from decimal import Decimal

SCHEMA = "stage1-cache-merge-pin/2"
PIN_KEYS = {"schema", "full_manifest_sha256", "population_sha256", "merged_cache_sha256", "header", "fit_status", "glyphs", "count"}
GLYPH_KEYS = {"codepoint", "name", "png_sha256", "block_sha256", "source_shard_cache_sha256", "source_shard_manifest_sha256"}
HEX = set("0123456789abcdef")

def sha(b): return hashlib.sha256(b).hexdigest()
def die(m): sys.exit("stage1_cache_merge: " + m)
def hex64(v, what):
    if not (isinstance(v, str) and len(v) == 64 and set(v) <= HEX): die(f"{what} must be 64 lowercase hex")
    return v

def no_dup_pairs(pairs):
    d = {}
    for k, v in pairs:
        if k in d: die(f"duplicate JSON key {k!r}")
        d[k] = v
    return d
def load_json(p): return json.load(open(p, encoding="utf-8"), object_pairs_hook=no_dup_pairs)

def manifest_rows(path):
    keys, glyphs = {}, []
    for ln in open(path, encoding="utf-8"):
        t = ln.strip()
        if not t or t.startswith("#"): continue
        k, _, rest = t.partition(" ")
        if k == "glyph":
            p = t.split()
            if len(p) != 4: die(f"{path}: bad glyph row {t!r}")
            glyphs.append((int(p[1], 16), p[2]))
        else:
            if k in keys: die(f"{path}: duplicate key {k}")
            keys[k] = rest.strip()
    cps = [c for c, _ in glyphs]
    if not glyphs or len(set(cps)) != len(cps) or len({n for _, n in glyphs}) != len(glyphs): die(f"{path}: empty or duplicate glyph cp/name")
    return keys, glyphs

def population_pin(glyphs):
    return sha("".join(sorted("%x:%s\n" % (c, n) for c, n in glyphs)).encode())

def rust_e(x):
    d = Decimal(repr(float(x))).normalize(); t = d.as_tuple()
    digits = "".join(map(str, t.digits)); exp = len(digits) - 1 + t.exponent
    if digits == "0": return "0e0"
    m = digits[0] + ("." + digits[1:] if len(digits) > 1 else "")
    return ("-" if t.sign else "") + f"{m}e{exp}"

def expected_policy(keys):
    if "reference" in keys or "frame_map" in keys: die("reference/guided manifests are not supported by the merge policy binding")
    pol = {"fixed": "Fixed", "measured_experimental": "MeasuredExperimental"}.get(keys.get("fit_tolerance_policy"))
    if pol is None: die("full manifest fit_tolerance_policy missing/invalid")
    g = lambda k, d: keys.get(k, d)   # defaults mirror the engine parse_manifest defaults
    cw = g("corner_wiring", "off")
    if cw not in ("on", "off"): die("full manifest corner_wiring invalid (on|off)")
    return ("policy\tscale\t%s\trdp_epsilon\t%s\tfit_squared_error\t%s\tfit_max_refits\t%s\tfit_tolerance_policy\t%s\tframe_map\tNone\tguide\tNone\treferences\t[]\tcorner_wiring\t%s"
            % (rust_e(keys["scale"]), rust_e(g("rdp_epsilon", "0.25")), rust_e(g("fit_squared_error", "0.25")), int(g("fit_max_refits", "8")), pol, cw))

def parse_cache(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    if lines[-1] == "": lines.pop()
    if len(lines) < 3 or lines[0] != "kni-stage1-cache\tv1": die(f"{path}: bad header")
    header = lines[:3]
    if not header[1].startswith("policy\t") or not header[2].startswith("engine_exe_sha256\t"): die(f"{path}: bad policy/exe header")
    blocks, i = [], 3
    while i < len(lines):
        f = lines[i].split("\t")
        if f[0] == "excluded":
            if len(f) < 6 or f[2] != "cp" or f[4] != "png_sha256": die(f"{path}: bad excluded row")
            blocks.append({"name": f[1], "cp": int(f[3], 16), "png": f[5], "lines": [lines[i]]}); i += 1
        elif f[0] == "glyph":
            if len(f) != 6 or f[2] != "cp" or f[4] != "png_sha256": die(f"{path}: bad glyph row")
            j = i
            while j < len(lines) and lines[j] != "end": j += 1
            if j >= len(lines): die(f"{path}: block {f[1]} has no 'end'")
            blocks.append({"name": f[1], "cp": int(f[3], 16), "png": f[5], "lines": lines[i:j + 1]}); i = j + 1
        else: die(f"{path}: unexpected row {lines[i][:40]!r}")
    return header, blocks
def block_bytes(b): return ("\n".join(b["lines"]) + "\n").encode()

def receipt_rows(path, manifest_path, keys, glyphs):
    """Receipt JSON bound to the manifest file bytes and exact (cp,name) rows."""
    r = load_json(path)
    if sha(open(manifest_path, "rb").read()) != r.get("manifest_sha256"): die(f"{path}: manifest_sha256 != actual manifest bytes")
    if r.get("population_sha256") != keys.get("population_sha256"): die(f"{path}: population_sha256 differs from manifest")
    rows = r.get("glyphs")
    if not isinstance(rows, list) or len(rows) != len(glyphs): die(f"{path}: glyph row count != manifest")
    pins = {}
    for row, (cp, name) in zip(rows, glyphs):
        c = int(row["codepoint"][2:], 16)
        if c != cp or row["glyph"] != name: die(f"{path}: receipt row {row.get('codepoint')} {row.get('glyph')} != manifest row {cp:#x} {name}")
        if c in pins: die(f"{path}: duplicate codepoint {row['codepoint']}")
        pins[c] = hex64(row["tile_sha256"], "tile_sha256")
    return pins

def engine_receipt(path, manifest_path):
    """Completion marker from the engine: manifest_pin binds, run_mode stage1_only, fit status."""
    t = open(path, encoding="utf-8").read().split("\n")
    kv = [l.split("\t") for l in t if l]
    mp = [l for l in kv if l[0] == "manifest_pin"]
    if len(mp) != 1 or mp[0][1] != sha(open(manifest_path, "rb").read()): die(f"{path}: manifest_pin != sha256(shard manifest)")
    rm = [l for l in kv if l[0] == "run_mode"]
    if len(rm) != 1 or rm[0][1:4] != ["stage1_only", "solve_spacing", "NOT_RUN"]: die(f"{path}: not a stage1_only completion receipt")
    diag = any(l[0] in ("export_intent", "fallback_ledger_total") for l in kv)
    return "FIT_DIAGNOSTIC" if diag else "CLEAN"

def external_bindings(a):
    fm = open(a.full_manifest, "rb").read()
    if sha(fm) != hex64(a.full_manifest_sha256, "--full-manifest-sha256"): die("full manifest bytes != externally supplied --full-manifest-sha256")
    keys, glyphs = manifest_rows(a.full_manifest)
    if keys.get("run_mode") != "full": die("full manifest run_mode != full")
    pop = population_pin(glyphs)
    if not (pop == keys.get("population_sha256") == hex64(a.frozen_population_sha256, "--frozen-population-sha256")):
        die("population pin: recomputed / declared / externally frozen values do not all agree")
    return keys, glyphs, pop

def full_receipt_pins(a, keys, glyphs):
    rp = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(a.full_manifest))), "receipts", os.path.basename(a.full_manifest)[:-9] + ".receipt.json")
    if not os.path.isfile(rp): die(f"receipt next to full manifest not found: {rp}")
    return receipt_rows(rp, a.full_manifest, keys, glyphs)

def commit(out, body, pin_text):
    cand = [out, out + ".pin.json"]
    for p in cand:
        if os.path.lexists(p): die(f"refusing to overwrite {p}")
    tmps = []
    try:
        for p, data in ((cand[0], body), (cand[1], pin_text)):
            t = p + ".tmp-%d" % os.getpid()
            fd = os.open(t, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644); tmps.append(t)
            with os.fdopen(fd, "wb") as f: f.write(data.encode()); f.flush(); os.fsync(f.fileno())
        os.link(tmps[0], cand[0])                 # no-overwrite publish; cache first, pin = commit marker
        try: os.link(tmps[1], cand[1])
        except OSError as e:
            os.unlink(cand[0]); die(f"pin publish failed, cache rolled back: {e}")
    finally:
        for t in tmps:
            try: os.unlink(t)
            except OSError: pass
    dfd = os.open(os.path.dirname(os.path.abspath(out)), os.O_RDONLY)
    try: os.fsync(dfd)
    finally: os.close(dfd)

def merge(a):
    keys, full, pop = external_bindings(a)
    fpins = full_receipt_pins(a, keys, full)
    n = len(a.shard_manifest)
    if not (n == len(a.shard_cache) == len(a.shard_receipt)): die("--shard-manifest/--shard-cache/--shard-receipt counts differ")
    want_policy = expected_policy(keys)
    fullset = dict(full); header, got, src, status = None, {}, {}, set()
    for mp, cpath, rpath in zip(a.shard_manifest, a.shard_cache, a.shard_receipt):
        skeys, sg = manifest_rows(mp)
        if skeys.get("run_mode") != "stage1_only": die(f"{mp}: not stage1_only")
        if skeys.get("population_sha256") != pop: die(f"{mp}: population pin != full")
        for k in ("family", "subfamily", "postscript_name", "scale", "fit_tolerance_policy"):
            if skeys.get(k) != keys.get(k): die(f"{mp}: {k} differs from full manifest")
        for c, nm in sg:
            if fullset.get(c) != nm: die(f"{mp}: row {c:#x} {nm} != full manifest row")
        spins = receipt_rows(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(mp))), "receipts", os.path.basename(mp)[:-9] + ".receipt.json"), mp, skeys, sg)
        status.add(engine_receipt(rpath, mp))
        h, blocks = parse_cache(cpath)
        if h[1] != want_policy: die(f"{cpath}: policy line != full-manifest-derived policy\n cache : {h[1]}\n expect: {want_policy}")
        if header is None: header = h
        elif h != header: die(f"{cpath}: header differs from first shard cache")
        if [(b["cp"], b["name"]) for b in blocks] != sg: die(f"{cpath}: blocks (cp,name,order) != shard manifest rows")
        csha = sha(open(cpath, "rb").read()); msha = sha(open(mp, "rb").read())
        for b in blocks:
            if b["png"] != spins[b["cp"]] or b["png"] != fpins[b["cp"]]: die(f"{cpath}: png_sha256 of U+{b['cp']:04X} != receipts")
            if b["cp"] in got: die(f"duplicate U+{b['cp']:04X} across shards")
            got[b["cp"]] = b; src[b["cp"]] = (csha, msha)
    if [c for c, _ in full if c not in got] or set(got) - set(fullset): die("union of shard caches != full manifest glyph set")
    if "FIT_DIAGNOSTIC" in status:
        if not a.accept_diagnostic_fit: die("a shard receipt is FIT_DIAGNOSTIC (fallback ledger / diagnostic intent); pass --accept-diagnostic-fit to merge explicitly")
        fit = "FIT_DIAGNOSTIC"
    else: fit = "CLEAN"
    body = "\n".join(header) + "\n" + "".join(block_bytes(got[c]).decode() for c, _ in full)
    pin = {"schema": SCHEMA, "full_manifest_sha256": a.full_manifest_sha256, "population_sha256": pop, "merged_cache_sha256": sha(body.encode()),
           "header": header, "fit_status": fit, "count": len(full),
           "glyphs": [{"codepoint": "U+%04X" % c, "name": nm, "png_sha256": got[c]["png"], "block_sha256": sha(block_bytes(got[c])),
                       "source_shard_cache_sha256": src[c][0], "source_shard_manifest_sha256": src[c][1]} for c, nm in full]}
    commit(a.out, body, json.dumps(pin, indent=2) + "\n")
    print(f"merged {len(full)} glyphs from {n} shards fit_status={fit} -> {a.out}")

def verify(a):
    keys, full, pop = external_bindings(a)
    pinp = a.cache + ".pin.json"
    if not os.path.isfile(pinp): die("pin file missing: uncommitted cache, refuse reuse")
    pin = load_json(pinp)
    if set(pin) != PIN_KEYS or pin["schema"] != SCHEMA: die("pin schema/keys mismatch")
    for k, v in (("full_manifest_sha256", a.full_manifest_sha256), ("population_sha256", pop)):
        if pin[k] != v: die(f"pin {k} != expected")
    if pin["fit_status"] not in ("CLEAN", "FIT_DIAGNOSTIC"): die("pin fit_status invalid")
    if sha(open(a.cache, "rb").read()) != pin["merged_cache_sha256"]: die("cache bytes changed since merge")
    header, blocks = parse_cache(a.cache)
    if header != pin["header"] or header[1] != expected_policy(keys): die("header/policy changed or != full manifest policy")
    if not (len(full) == len(blocks) == len(pin["glyphs"]) == pin["count"]) or len(full) == 0: die("glyph count mismatch (manifest/cache/pin)")
    fpins = full_receipt_pins(a, keys, full)
    for (c, nm), b, g in zip(full, blocks, pin["glyphs"]):
        if set(g) != GLYPH_KEYS: die("pin glyph record keys mismatch")
        want = ("U+%04X" % c, nm, fpins[c], sha(block_bytes(b)))
        if (g["codepoint"], g["name"], g["png_sha256"], g["block_sha256"]) != want or (b["cp"], b["name"], b["png"]) != (c, nm, fpins[c]):
            die(f"record U+{c:04X}: cp/name/png/block hash mismatch")
    exe = header[2].split("\t")[1]
    if a.engine_exe_sha256 and exe != a.engine_exe_sha256: die(f"engine executable changed (cache {exe[:12]}, current {a.engine_exe_sha256[:12]}): invalidated")
    print(f"ok: cache matches pin and full manifest (fit_status={pin['fit_status']})")

def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("merge", "verify"):
        p = sub.add_parser(name); p.add_argument("--full-manifest", required=True)
        p.add_argument("--full-manifest-sha256", required=True); p.add_argument("--frozen-population-sha256", required=True)
    m = sub.choices["merge"]
    for f in ("--shard-manifest", "--shard-cache", "--shard-receipt"): m.add_argument(f, action="append", required=True)
    m.add_argument("--out", required=True); m.add_argument("--accept-diagnostic-fit", action="store_true")
    v = sub.choices["verify"]; v.add_argument("--cache", required=True); v.add_argument("--engine-exe-sha256")
    a = ap.parse_args(); merge(a) if a.cmd == "merge" else verify(a)

if __name__ == "__main__": main()
