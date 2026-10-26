#!/usr/bin/env python3
"""space_record_gen: ledger + collection tree + declared records -> roles.tsv + meta.txt -> bounded space_evidence_gen -> manifest-row.txt.

build_space_inputs(coll_root, style_rel, ledger_path, out_dir, records) -> dict

  coll_root   collection root; style_rel 'Karl Nawrot Typefaces/<Family>/<Style>' (tiles live under <style_rel>/sidebearing/**).
  ledger_path a ledger.jsonl path or glob (downloader request ledger).
  records     dict of DECLARED meta values (cp style_id frame_id scale scale_method calibration_source_role hh_mode shaping_settings_ref
              ligatures_disabled letter_spacing_px max_input_bytes max_pixels max_working_bytes + the slope/pair keys that space_evidence_gen
              requires). Nothing here has a default and nothing is read from file names. Missing or whitespace-containing values are refused.

Roles come ONLY from the ledger (space_sequence_roles: submitted text `H`+n spaces+`H`, response asset sha re-hashed against the ledger):
  hh_mode slope    : n=1,2,3 -> slope1,slope2,slope3 (all three required).
  hh_mode explicit : n=1 -> hsh (no hhh role).
  hh_mode hhh      : refused here (the ledger text pattern has no H H H role; supply it through the hand-written roles route).
Aliases: the same tile BYTES for two different space counts is a hard error (the slope would be unmeasurable). Same bytes under two ledger ids for the
SAME count are collapsed by space_sequence_roles with both ids kept in identity_ref.
Missing record (a needed space count has no ledger tile) -> NO file is written; the error says which counts are absent.
Tiles are byte-copied into <out_dir>/tiles/ (names derive from role+sha, no whitespace) because space_evidence_gen refuses whitespace in the
relative tile path and collection folder names contain spaces. The copy is re-hashed against the ledger sha.
Raises SpaceRecordError (descriptive). Does not touch the collection or the engine.
"""
import hashlib, os, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import space_sequence_roles as ssr
import space_evidence_gen as seg

class SpaceRecordError(Exception): pass

def noclobber_rename(src, dst):
    """Atomic rename that FAILS if dst exists (even an empty directory). Linux renameat2(RENAME_NOREPLACE), macOS renamex_np(RENAME_EXCL).
    No fallback: where neither exists the publish is refused with an explicit error (a plain os.rename could overwrite an empty dir)."""
    import ctypes, errno
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        r = libc.renameat2(-100, os.fsencode(src), -100, os.fsencode(dst), 1)  # AT_FDCWD, RENAME_NOREPLACE
    elif sys.platform == "darwin" and hasattr(libc, "renamex_np"):
        r = libc.renamex_np(os.fsencode(src), os.fsencode(dst), 4)  # RENAME_EXCL
    else:
        raise SpaceRecordError("NoClobberRenameUnavailable: this platform has no renameat2/renamex_np; refusing to publish without a no-overwrite rename")
    if r != 0:
        e = ctypes.get_errno()
        raise SpaceRecordError(f"could not publish {dst}: {os.strerror(e)}" + (" (target appeared; no overwrite)" if e in (errno.EEXIST, errno.ENOTEMPTY) else ""))

def _call(fn, *a):
    try: return fn(*a)
    except SystemExit as e: raise SpaceRecordError(str(e.code))

def _contained(root, rel_or_abs, what, must_exist=True):
    """Real path must lie under root (no .., no absolute escape, no symlink escape)."""
    rr = os.path.realpath(root)
    p = os.path.realpath(os.path.join(rr, rel_or_abs))
    if os.path.commonpath([rr, p]) != rr or p == rr: raise SpaceRecordError(f"{what} {rel_or_abs!r} is outside the collection root")
    if must_exist and not os.path.exists(p): raise SpaceRecordError(f"{what} {rel_or_abs!r} does not exist")
    return p

def build_space_inputs(coll_root, style_rel, ledger_path, out_dir, records):
    if not isinstance(records, dict) or not records: raise SpaceRecordError("records must be a non-empty dict of declared meta values")
    for k, v in records.items():
        if not isinstance(v, str) or not v or any(c.isspace() for c in v): raise SpaceRecordError(f"record {k!r} must be a non-empty string without whitespace (got {v!r})")
    mode = records.get("hh_mode")
    if mode not in ("slope", "explicit"): raise SpaceRecordError(f"hh_mode must be slope or explicit for ledger-derived roles (got {mode!r}; hhh is not derivable from the H<spaces>H ledger texts)")
    for k in ("style_id", "frame_id"):
        if k not in records: raise SpaceRecordError(f"records missing {k}")
    try: lim = (int(records["max_input_bytes"]), int(records["max_working_bytes"]))
    except (KeyError, ValueError): raise SpaceRecordError("records need integer max_input_bytes and max_working_bytes (applied to the ledger and tile reads)")
    if os.path.isabs(style_rel) or ".." in style_rel.split("/"): raise SpaceRecordError(f"style_rel {style_rel!r} must be relative without '..'")
    style_dir = _contained(coll_root, style_rel, "style_rel")
    import glob
    cands = sorted(glob.glob(ledger_path)) or ([ledger_path] if os.path.isfile(ledger_path) else [])
    if not cands: raise SpaceRecordError(f"no ledger file matches {ledger_path!r}")
    paths = [_contained(coll_root, c, "ledger") for c in cands]
    for q in paths:
        if not os.path.isfile(q): raise SpaceRecordError(f"ledger {q!r} is not a regular file")
    out_dir = os.path.realpath(out_dir)
    # Installed at <repo>/engine/pipeline/tools/space_record_gen.py; protect <repo>/engine.
    engine_root = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", ".."))
    for label, protected in (("collection", os.path.realpath(coll_root)), ("engine", engine_root)):
        if os.path.commonpath([protected, out_dir]) == protected:
            raise SpaceRecordError(f"OutputTreeConflict: out_dir is inside the {label} tree; nothing written")
    if os.path.lexists(out_dir): raise SpaceRecordError(f"out_dir {out_dir} exists (no overwrite)")
    parent = os.path.dirname(out_dir)
    if not os.path.isdir(parent): raise SpaceRecordError(f"parent of out_dir {parent} does not exist")
    budget = ssr.Budget(*lim)
    need = (1, 2, 3) if mode == "slope" else (1,)
    rows = _call(ssr.roles, coll_root, style_rel, paths, None, None, budget)
    by_n = {r[0]: r for r in rows}
    missing = [n for n in need if n not in by_n]
    if missing: raise SpaceRecordError(f"missing ledger records for space count(s) {missing} under {style_rel}: found counts {sorted(by_n)}; nothing written")
    shas = {}
    for n in need:
        sh = by_n[n][2]
        if sh in shas: raise SpaceRecordError(f"ALIASED_TILES: space counts {shas[sh]} and {n} have identical tile bytes ({sh[:12]}); refusing")
        shas[sh] = n
    from decimal import Decimal, InvalidOperation
    for n in need:
        try:
            declared_ls = Decimal(records["letter_spacing_px"])
            evidence_ls = Decimal(str(by_n[n][3]))
            matches = declared_ls.is_finite() and evidence_ls.is_finite() and declared_ls == evidence_ls
        except (KeyError, InvalidOperation, ValueError):
            matches = False
        if not matches:
            raise SpaceRecordError(f"ControlsConflict: count {n} letter_spacing differs from declared letter_spacing_px")
    frame = f"{records['style_id']}/{records['frame_id']}"
    role_of = (lambda n: f"slope{n}") if mode == "slope" else (lambda n: "hsh")
    # Everything is built in a private temp dir next to out_dir and published with one rename; any error removes the temp dir (nothing is left behind).
    tmp = tempfile.mkdtemp(prefix=".space-record-", dir=parent)
    try:
        plan = []
        for n in need:
            _, rel, sha, ls, fs, sem, ids, gid, control_hash = by_n[n]
            src = _contained(style_dir, rel, f"tile {rel}")   # realpath under the style dir before any read
            b = _call(budget.read, src, f"tile {rel} (copy)")
            if hashlib.sha256(b).hexdigest() != sha: raise SpaceRecordError(f"{rel}: bytes changed since the ledger check")
            plan.append((role_of(n), f"{role_of(n)}-{sha[:12]}.png", "ledger:" + ids.replace(" ", "") + ":control_hash:" + control_hash, b))
        os.makedirs(os.path.join(tmp, "tiles"))
        for _, rel, _, b in plan:
            with open(os.path.join(tmp, "tiles", rel), "xb") as f: f.write(b)
        with open(os.path.join(tmp, "roles.tsv"), "x", encoding="utf-8") as f:
            f.write("role\ttile_file\tidentity_ref\tframe\n" + "".join(f"{r}\t{rel}\t{ident}\t{frame}\n" for r, rel, ident, _ in plan))
        with open(os.path.join(tmp, "meta.txt"), "x", encoding="utf-8") as f: f.write("".join(f"{k} {v}\n" for k, v in records.items()))
        res = _call(seg.build, os.path.join(tmp, "roles.tsv"), os.path.join(tmp, "tiles"), os.path.join(tmp, "meta.txt"), os.path.join(tmp, "space-evidence"))
        rp = os.path.join(tmp, "space-evidence", "receipt.tsv")   # receipt carries absolute tile paths: rewrite the temp prefix to the final one
        txt = open(rp, encoding="utf-8").read().replace(os.path.realpath(tmp), out_dir)
        # identity_ref embeds each control hash in the pinned spec and therefore the manifest hash.
        txt += "".join(f"control_hash\t{role_of(n)}\t{by_n[n][8]}\tletter_spacing-compared\n" for n in need)
        open(rp, "w", encoding="utf-8").write(txt)
        noclobber_rename(tmp, out_dir)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True); raise
    return {"roles_tsv": os.path.join(out_dir, "roles.tsv"), "meta_txt": os.path.join(out_dir, "meta.txt"), "out": os.path.join(out_dir, "space-evidence"),
            "manifest_row": res["manifest_row"], "spec_sha256": res["spec_sha256"], "scale_record_sha256": res["scale_record_sha256"],
            "counts": {n: by_n[n][2] for n in need}}
