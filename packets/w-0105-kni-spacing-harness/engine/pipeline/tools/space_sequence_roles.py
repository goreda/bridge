#!/usr/bin/env python3
"""Space-sequence roles from the downloader's own request ledger (no file-name parsing).

For one style folder, joins ledger `send_intent` (the submitted text) with the matching `response`
(asset path + sha256) by event id, and keeps responses under <style>/sidebearing/** whose submitted
text is `H`, 1+ ASCII spaces, `H`. n_spaces = number of spaces in the submitted text. Tile bytes are
re-hashed and must equal the ledger asset sha256 (hard error otherwise). Same bytes under two ids
(sb/ and reference/) collapse to one tile with both ids recorded.

Read-only. Prints TSV: n_spaces tile_rel sha256 letter_spacing font_size controls_semantic_sha256 ids style_glyph_identity control_hash
A style with no ledger match yields no rows (caller reports MissingSpaceEvidence); nothing is guessed.

usage: space_sequence_roles.py --collection-root DIR --style-rel 'Karl Nawrot Typefaces/Fam/Style' --ledger GLOB [--ledger GLOB ...]
"""
import argparse, glob, hashlib, json, os, re, sys

TEXT = re.compile(r"^H( +)H$")

def die(m): sys.exit(f"space_sequence_roles: {m}")

def canonical_controls(value):
    """Canonical JSON object: unique control keys, sorted keys, compact UTF-8, finite JSON values."""
    if not isinstance(value, (dict, list)):
        die("ControlsConflict: controls_sanitized must be an object or key/value list")
    try:
        pairs = list(value.items()) if isinstance(value, dict) else value
        controls = {}
        for key, val in pairs:
            if not isinstance(key, str) or key in controls:
                die("ControlsConflict: control keys must be unique strings")
            controls[key] = val
        canonical = json.dumps(controls, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError):
        die("ControlsConflict: invalid controls_sanitized")
    return controls, canonical

def read_bounded(path, cap, what):
    """At most cap+1 bytes from a regular file; more than cap is a typed refusal (no unbounded read)."""
    if cap < 0: die(f"ResourceLimit: no byte budget left before reading {what}")
    with open(path, "rb") as f:
        b = f.read(cap + 1)
    if len(b) > cap: die(f"ResourceLimit: {what} is larger than the {cap} bytes allowed")
    return b

class Budget:
    """Shared read budget: every file read (ledgers and tiles) is charged; the cap of the NEXT read is decided before it."""
    def __init__(self, max_input_bytes, max_working_bytes):
        for n, v in (("max_input_bytes", max_input_bytes), ("max_working_bytes", max_working_bytes)):
            if not isinstance(v, int) or isinstance(v, bool) or v <= 0: die(f"{n} must be a positive integer (no default; pass it explicitly)")
        self.per, self.total, self.used = max_input_bytes, max_working_bytes, 0
    def read(self, path, what, per=True):
        """per=True: tile-like file, also capped by max_input_bytes. per=False (ledgers): capped only by the remaining working budget."""
        if self.used > self.total: die(f"ResourceLimit: {self.used} bytes already read exceed max_working_bytes {self.total}; {what} not opened")
        b = read_bounded(path, min(self.per, self.total - self.used) if per else self.total - self.used, what)
        self.used += len(b); return b

def load(paths, budget):
    rows = []
    for p in paths:
        for ln, l in enumerate(budget.read(p, f"ledger {os.path.basename(p)}", per=False).decode("utf-8").splitlines(), 1):
            if not l.strip(): continue
            try: row = json.loads(l)
            except ValueError: die(f"{p}:{ln}: not JSON")
            if not isinstance(row, dict): die(f"InvalidLedgerRow: {p}:{ln}: expected a JSON object")
            rows.append(row)
    return rows

def roles(coll_root, style_rel, ledger_globs, max_input_bytes=None, max_working_bytes=None, budget=None):
    budget = budget or Budget(max_input_bytes, max_working_bytes)  # explicit limits are required; None refuses
    # Entry guard (the CLI is public): style_rel and the real style/sidebearing roots must lie under the real collection root BEFORE any ledger or asset is read.
    if not isinstance(style_rel, str) or not style_rel or os.path.isabs(style_rel) or ".." in style_rel.split("/"): die(f"style_rel {style_rel!r} must be a non-empty relative path without '..'")
    cr = os.path.realpath(coll_root)
    for what, q in (("style folder", os.path.realpath(os.path.join(cr, style_rel))), ("sidebearing folder", os.path.realpath(os.path.join(cr, style_rel, "sidebearing")))):
        if os.path.commonpath([cr, q]) != cr or q == cr: die(f"{what} of {style_rel!r} resolves outside the collection root (path or symlink escape); nothing read")
    paths = sorted({p for g in ledger_globs for p in glob.glob(g)})
    if not paths: die("no ledger file matches --ledger")
    rows = load(paths, budget)
    HEX32 = re.compile(r"^[0-9a-f]{32}$")
    intents = {}      # (id, send_id) -> the one intent row; duplicates must be identical, else hard error
    for r in rows:
        if r.get("kind") == "send_intent":
            sid = r.get("send_id")
            if not isinstance(sid, str) or not HEX32.match(sid): die(f"send_intent {r.get('id')}: send_id missing or not 32 hex")
            sem = r.get("controls_semantic_sha256")
            if not isinstance(sem, str) or not re.fullmatch(r"[0-9a-f]{64}", sem):
                die(f"InvalidSemanticSha256: send_intent {r.get('id')}: controls_semantic_sha256 must be 64 lowercase hex")
            key = (r["id"], sid)
            if key in intents and (intents[key].get("controls_sanitized"), intents[key].get("controls_semantic_sha256")) != (r.get("controls_sanitized"), r.get("controls_semantic_sha256")):
                die(f"send_intent {key[0]}/{sid[:8]}: two intents with the same id+send_id but different controls/semantic sha")
            intents.setdefault(key, r)
    sems = {}
    for (i_, s_), r in intents.items():
        sems.setdefault(i_, set()).add(r.get("controls_semantic_sha256"))
    for i_, ss in sems.items():
        if len(ss) > 1: die(f"{i_}: send_intents of one id carry different controls_semantic_sha256 {sorted(map(str, ss))}")
    prefix = style_rel.rstrip("/") + "/sidebearing/"
    sb_root = os.path.realpath(os.path.join(coll_root, style_rel, "sidebearing"))
    by_sha = {}; tile_sha = {}; count_by_sha = {}; controls_by_count = {}; slope_controls = None
    for r in rows:
        if r.get("kind") != "response" or not r.get("ok"): continue
        a = r.get("asset") or {}
        pth = a.get("path", "")
        if not pth.startswith(prefix): continue
        sid = r.get("send_id")
        if not isinstance(sid, str) or not HEX32.match(sid): die(f"response {r['id']}: send_id missing or not 32 hex")
        it = intents.get((r["id"], sid))
        if it is None: die(f"response {r['id']}/{sid[:8]} has no send_intent with the same id AND send_id")
        its = [it]
        controls, canonical = canonical_controls(it.get("controls_sanitized"))
        text = controls.get("text")
        if not isinstance(text, str): die("ControlsConflict: text must be a string")
        m = TEXT.match(text)
        if not m: continue
        c = controls
        if os.path.isabs(pth) or ".." in pth.split("/"): die(f"ledger asset path {pth!r} is absolute or contains '..'")
        fp = os.path.realpath(os.path.join(coll_root, pth))
        if os.path.commonpath([sb_root, fp]) != sb_root or fp == sb_root: die(f"ledger asset {pth!r} resolves outside {style_rel}/sidebearing (symlink or path escape); not read")
        if not os.path.isfile(fp): die(f"ledger asset missing on disk: {pth}")
        if fp not in tile_sha: tile_sha[fp] = hashlib.sha256(budget.read(fp, f"tile {pth}")).hexdigest()  # each file is read (and charged) once
        h = tile_sha[fp]
        if h != a["sha256"]: die(f"{pth}: bytes sha {h} != ledger asset sha {a['sha256']}")
        n = len(m.group(1))
        if h in count_by_sha and count_by_sha[h] != n:
            die(f"ALIASED_TILES: same bytes {h} claim different space counts {count_by_sha[h]} and {n}")
        count_by_sha[h] = n
        role_controls = (c.get("letter_spacing"), c.get("font_size"), it["controls_semantic_sha256"], r.get("style_glyph_identity"), canonical)
        if n in controls_by_count and controls_by_count[n] != role_controls:
            # Preserve the specific glyph-identity refusal before the general controls refusal.
            if controls_by_count[n][3] != role_controls[3]:
                die(f"AmbiguousGlyphIdentity: space count {n} carries different style_glyph_identity")
            die(f"ControlsConflict: space count {n} carries different capture controls")
        controls_by_count[n] = role_controls
        # Slope comparison ignores only submitted text; semantic hashes include text.
        if n in (1, 2, 3):
            capture_controls = ({k: v for k, v in controls.items() if k != "text"}, r.get("style_glyph_identity"))
            if slope_controls is not None and slope_controls != capture_controls:
                die("ControlsConflict: slope counts have different text-excluded controls or glyph identity")
            slope_controls = capture_controls
        key = (n, h)
        control_hash = hashlib.sha256(canonical.encode("utf-8") + h.encode("ascii")).hexdigest()
        e = by_sha.setdefault(key, {"tile": pth, "ids": [], "ls": c.get("letter_spacing"), "fs": c.get("font_size"),
                                    "sem": its[-1]["controls_semantic_sha256"], "gid": r.get("style_glyph_identity"),
                                    "control_hash": control_hash, "controls": controls})
        # Duplicate byte/count evidence must agree on glyph identity; order never chooses it.
        if e["gid"] != r.get("style_glyph_identity"):
            die(f"AmbiguousGlyphIdentity: same bytes/count {h}/{n} carry different style_glyph_identity")
        e["ids"].append(r["id"])
        if (e["ls"], e["fs"]) != (c.get("letter_spacing"), c.get("font_size")) or e["control_hash"] != control_hash:
            die(f"ControlsConflict: {pth}: same role has different capture controls")
        if e["sem"] != its[-1]["controls_semantic_sha256"]: die(f"ControlsConflict: {pth}: same role has different controls_semantic_sha256 ({e['sem']} vs {its[-1]['controls_semantic_sha256']})")
        if pth < e["tile"]: e["tile"] = pth
    out = []
    for (n, h), e in sorted(by_sha.items()):
        out.append((n, os.path.relpath(e["tile"], style_rel), h, e["ls"], e["fs"], e["sem"], ",".join(sorted(e["ids"])), e["gid"], e["control_hash"]))
    ns = [o[0] for o in out]
    if len(ns) != len(set(ns)): die("two different tiles for the same space count: ambiguous, refusing")
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--collection-root", required=True); ap.add_argument("--style-rel", required=True)
    ap.add_argument("--ledger", action="append", required=True); ap.add_argument("--max-input-bytes", type=int, required=True); ap.add_argument("--max-working-bytes", type=int, required=True)
    a = ap.parse_args()
    for o in roles(a.collection_root, a.style_rel, a.ledger, a.max_input_bytes, a.max_working_bytes):
        print("\t".join(str(x) for x in o))

if __name__ == "__main__":
    main()
