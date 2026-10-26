#!/usr/bin/env python3
"""space_evidence producer: role TSV + declared meta -> spec file, scale_record file, manifest row.

No names are guessed: which file is the HsH tile and which is the HHH tile comes only from the
role TSV. Every sha256 is computed from the file bytes here. Nothing has a default: a missing
meta key, an unknown key, a duplicate role, a tile outside --image-root, whitespace in a path,
or a frame that disagrees with --meta style_id/frame_id is a hard error.

usage: space_evidence_gen.py --roles roles.tsv --image-root DIR --meta meta.txt --out OUT
Read-only on inputs. Writes only under --out:
  space-evidence.spec, scale-record.txt, manifest-row.txt, receipt.tsv

roles.tsv columns (header required): role  tile_file  identity_ref  frame
  role in {hsh, hhh}; tile_file is relative to --image-root; frame is <style_id>/<frame_id>.
meta.txt rows (`key value`, no spaces inside a value), all required unless noted:
  cp style_id frame_id scale scale_method calibration_source_role(hsh|hhh)
  hh_kern(zero|known) hh_kern_ref [hh_kern_px when known]
  hsh_kern(zero|known) hsh_kern_ref [hsh_kern_px when known]
  shaping_settings_ref ligatures_disabled(true|false) letter_spacing_px sidebearing_policy
  max_input_bytes max_pixels max_working_bytes
  hh_mode(hhh|explicit); with explicit: explicit_lsb_px explicit_rsb_px explicit_ref (no hhh role then)
`scale` is written verbatim to scale-record units_per_px and must be the manifest `scale` token.
"""
import argparse, csv, hashlib, math, os, sys

REQ = ["cp", "style_id", "frame_id", "scale", "scale_method", "calibration_source_role",
       "shaping_settings_ref", "ligatures_disabled", "letter_spacing_px",
       "max_input_bytes", "max_pixels", "max_working_bytes", "hh_mode"]
PAIR_REQ = ["hh_kern", "hh_kern_ref", "hsh_kern", "hsh_kern_ref", "sidebearing_policy"]
SLOPE_REQ = ["slope_kern_ref", "ink_delta", "ink_ref", "slope_max_points"]
CONTRACT = ["renderer_model", "renderer_transform_ref", "renderer_dpr_ref", "renderer_filter_ref",
            "renderer_threshold_ref", "renderer_compression_ref", "renderer_clipping_ref"]
OPT = {"hh_kern_px", "hsh_kern_px", "explicit_lsb_px", "explicit_rsb_px", "explicit_ref"} | set(CONTRACT)
SLOPE_ROLES = ("slope1", "slope2", "slope3")
ROLES = ("hsh", "hhh") + SLOPE_ROLES

def die(m): sys.exit(f"space_evidence_gen: {m}")

def sha(b): return hashlib.sha256(b).hexdigest()

SMALL_FILE_CAP = 1 << 20  # meta/roles text files: a declared tool cap (1 MiB), not an engine budget

def read_bounded(path, cap, what):
    """Read at most cap+1 bytes from a regular file; more than cap is a typed refusal (no unbounded read)."""
    with open(path, "rb") as f:
        b = f.read(cap + 1)
    if len(b) > cap: die(f"ResourceLimit: {what} is larger than {cap} bytes")
    return b

def read_kv(path):
    out = {}
    for ln, raw in enumerate(read_bounded(path, SMALL_FILE_CAP, "meta file").decode("utf-8").splitlines(), 1):
        s = raw.strip()
        if not s or s.startswith("#"): continue
        k, _, v = s.partition(" ")
        v = v.strip()
        if not v or any(c.isspace() for c in v): die(f"{path}:{ln}: key {k!r} needs exactly one whitespace-free value")
        if k in out: die(f"{path}:{ln}: duplicate key {k!r}")
        out[k] = v
    return out

def num(meta, k):
    try: x = float(meta[k])
    except (KeyError, ValueError): die(f"meta {k} must be a number")
    if not math.isfinite(x): die(f"meta {k} must be finite")
    return meta[k]

def nonneg_int(meta, k):
    v = meta.get(k, "")
    if not v.isdigit() or int(v) == 0: die(f"meta {k} must be a positive integer")
    return v

def build(roles_path, image_root, meta_path, out):
    meta = read_kv(meta_path)
    slope = meta.get("hh_mode") == "slope"
    need_keys = REQ + (SLOPE_REQ if slope else PAIR_REQ)
    miss = [k for k in need_keys if k not in meta]
    if miss: die(f"meta missing keys: {miss}")
    unk = [k for k in meta if k not in need_keys and k not in OPT]
    if not slope and any(k in meta for k in CONTRACT): die("renderer_* keys only with hh_mode slope")
    have_c = [k for k in CONTRACT if k in meta]
    if have_c and len(have_c) != len(CONTRACT): die(f"renderer contract is all-or-none, missing {[k for k in CONTRACT if k not in meta]}")
    if have_c and meta["renderer_model"] != "binary_pixel_center": die("renderer_model must be binary_pixel_center")
    if unk: die(f"meta unknown keys: {unk}")
    frame = f"{meta['style_id']}/{meta['frame_id']}"
    if "/" in meta["style_id"] or "/" in meta["frame_id"]: die("style_id/frame_id must not contain '/'")
    cp = meta["cp"]
    if int(cp[2:] if cp.startswith("0x") else cp, 16) != 0x20: die("cp must be U+0020")
    num(meta, "scale"); num(meta, "letter_spacing_px")
    if meta["ligatures_disabled"] not in ("true", "false"): die("ligatures_disabled must be true|false")
    if not slope and meta["sidebearing_policy"] not in ("allow_negative", "require_nonnegative"): die("sidebearing_policy invalid")
    for k in ("max_input_bytes", "max_pixels", "max_working_bytes"): nonneg_int(meta, k)
    if slope and not meta["slope_max_points"].isdigit(): die("slope_max_points must be an unsigned integer")
    if slope and not (meta["ink_delta"].isdigit() and int(meta["ink_delta"]) <= 255): die("ink_delta must be 0..255")
    if meta["hh_mode"] not in ("hhh", "explicit", "slope"): die("hh_mode must be hhh|explicit|slope")
    if meta["calibration_source_role"] not in ROLES: die("calibration_source_role must be one of the roles")
    for p in (() if slope else ("hh_kern", "hsh_kern")):
        if meta[p] not in ("zero", "known"): die(f"{p} must be zero|known")
        if (meta[p] == "known") != (f"{p}_px" in meta): die(f"{p}_px required iff {p} is known")
        if meta[p] == "known": num(meta, f"{p}_px")
    if meta["hh_mode"] == "explicit":
        for k in ("explicit_lsb_px", "explicit_rsb_px", "explicit_ref"):
            if k not in meta: die(f"hh_mode explicit needs {k}")
        num(meta, "explicit_lsb_px"); num(meta, "explicit_rsb_px")
    elif any(k in meta for k in ("explicit_lsb_px", "explicit_rsb_px", "explicit_ref")): die("explicit_* keys only with hh_mode explicit")

    root = os.path.realpath(image_root)
    rows = {}
    import io
    budget = int(meta["max_working_bytes"]); used = 0
    roles_text = read_bounded(roles_path, SMALL_FILE_CAP, "roles file").decode("utf-8")
    used += len(roles_text.encode("utf-8"))
    with io.StringIO(roles_text, newline="") as f:
        rd = csv.DictReader(f, delimiter="\t")
        need = ["role", "tile_file", "identity_ref", "frame"]
        if [c for c in need if c not in (rd.fieldnames or [])]: die(f"roles TSV needs columns {need}")
        for r in rd:
            role = r["role"]
            if role not in ROLES: die(f"unknown role {role!r}")
            if role in rows: die(f"duplicate role {role}")
            if r["frame"] != frame: die(f"role {role} frame {r['frame']!r} != meta {frame!r}")
            for k in ("tile_file", "identity_ref"):
                if not r[k] or any(c.isspace() for c in r[k]): die(f"role {role} {k} empty or has whitespace")
            p = os.path.realpath(os.path.join(root, r["tile_file"]))
            if os.path.commonpath([root, p]) != root: die(f"role {role} tile outside --image-root")
            if not os.path.isfile(p): die(f"role {role} tile not a file: {r['tile_file']}")
            if used > budget: die(f"ResourceLimit: input bytes already read ({used}) exceed max_working_bytes {budget}; no tile opened")
            tb = read_bounded(p, min(int(meta["max_input_bytes"]), budget - used), f"role {role} tile")  # cap+1 read; cap = min(max_input_bytes, remaining budget), decided BEFORE the read
            used += len(tb)
            rows[role] = (p, r["identity_ref"], sha(tb))
    if slope:
        if any(r in rows for r in ("hsh", "hhh")): die("hh_mode slope excludes hsh/hhh roles")
        if not all(r in rows for r in SLOPE_ROLES): die(f"hh_mode slope needs roles {SLOPE_ROLES}")
        shas = [rows[r][2] for r in SLOPE_ROLES]
        if len(set(shas)) != len(shas): die("ALIASED_TILES: slope tiles with different space counts have identical bytes; slope unmeasurable")
    elif any(r in rows for r in SLOPE_ROLES): die("slope roles need hh_mode slope")
    if not slope and "hsh" not in rows: die("role hsh missing")
    if meta["hh_mode"] == "hhh" and "hhh" not in rows: die("hh_mode hhh needs role hhh")
    if meta["hh_mode"] == "explicit" and "hhh" in rows: die("hh_mode explicit excludes role hhh")
    if meta["calibration_source_role"] not in rows: die("calibration_source_role has no tile")

    os.makedirs(out, exist_ok=True)
    out = os.path.realpath(out)
    rel = lambda p: os.path.relpath(p, out)
    for p, _, _ in rows.values():
        if any(c.isspace() for c in rel(p)): die("relative tile path has whitespace")
    sc_text = (f"style_id {meta['style_id']}\nframe_id {meta['frame_id']}\nunits_per_px {meta['scale']}\n"
               f"calibration_source_sha256 {rows[meta['calibration_source_role']][2]}\nmethod {meta['scale_method']}\n")
    sc_bytes = sc_text.encode()
    lines = [f"cp {cp}", f"style_id {meta['style_id']}", f"frame_id {meta['frame_id']}"]
    for role in ROLES:
        if role in rows and role in SLOPE_ROLES:
            p, ident, h = rows[role]
            lines.append(f"slope_tile f={frame} {role[len('slope'):]} {rel(p)} {ident} {h}")
        elif role in rows:
            p, ident, h = rows[role]
            lines.append(f"{role}_tile f={frame} {rel(p)} {ident} {h}")
    def kern(p):
        return f"{p} f={frame} " + ("zero " if meta[p] == "zero" else f"known {meta[p + '_px']} ") + meta[p + "_ref"]
    if slope:
        lines.append(f"slope_kern f={frame} zero {meta['slope_kern_ref']}")
        lines.append(f"slope_max_points {meta['slope_max_points']}")
        lines.append(f"ink_model border_median_delta {meta['ink_delta']} {meta['ink_ref']}")
        if have_c: lines.append("renderer_contract " + " ".join(meta[k] for k in CONTRACT))
    else:
        if meta["hh_mode"] == "hhh": lines.append(kern("hh_kern"))
        else: lines.append(f"hh_explicit f={frame} {meta['explicit_lsb_px']} {meta['explicit_rsb_px']} {meta['explicit_ref']}")
        lines.append(kern("hsh_kern"))
    lines.append(f"shaping f={frame} {meta['shaping_settings_ref']} {meta['ligatures_disabled']} {meta['letter_spacing_px']} "
                 + ",".join(rows[r][2] for r in ROLES if r in rows))
    lines.append(f"scale_record f={frame} scale-record.txt {sha(sc_bytes)}")
    if not slope: lines.append(f"sidebearing_policy {meta['sidebearing_policy']}")
    spec_bytes = ("\n".join(lines) + "\n").encode()
    open(os.path.join(out, "scale-record.txt"), "wb").write(sc_bytes)
    open(os.path.join(out, "space-evidence.spec"), "wb").write(spec_bytes)
    row = f"space_evidence space-evidence.spec {sha(spec_bytes)} {meta['max_input_bytes']} {meta['max_pixels']} {meta['max_working_bytes']}\n"
    open(os.path.join(out, "manifest-row.txt"), "w").write(row)
    rc = "".join(f"{k}\t{rows[k][0]}\t{rows[k][2]}\t{rows[k][1]}\n" for k in ROLES if k in rows)
    open(os.path.join(out, "receipt.tsv"), "w").write(
        "role\ttile_abs_path\ttile_sha256\tidentity_ref\n" + rc + f"spec_sha256\t{sha(spec_bytes)}\nscale_record_sha256\t{sha(sc_bytes)}\n"
        "note\tmanifest `scale` must be the token " + meta["scale"] + "; scale record is a pinned-consistency claim, not independent calibration\n")
    return {"spec_sha256": sha(spec_bytes), "scale_record_sha256": sha(sc_bytes), "manifest_row": row.strip()}

def main():
    ap = argparse.ArgumentParser()
    for a in ("--roles", "--image-root", "--meta", "--out"): ap.add_argument(a, required=True)
    a = ap.parse_args()
    r = build(a.roles, a.image_root, a.meta, a.out)
    print(r["manifest_row"])

if __name__ == "__main__":
    main()
