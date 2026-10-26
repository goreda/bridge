#!/usr/bin/env python3
"""Stage the .notdef evidence inside the run root R (= directory of the manifest handed to the engine).
Contract (engine: main.rs rc.capture_dir = manifest parent; notdef_caller within()): manifest, glyph tiles, capture manifest,
evidence record and its selected/witness tiles ALL live physically under R; no '..', no absolute path, no symlink.

v2 (strict verified evidence): source dir holds capture-manifest.tsv (kni-capture-manifest v1) and evidence.tsv
(selected/witness record). Staged to notdef/, manifest gains capture_manifest + notdef evidence rows.

v3 (pixel-evidence: no original font, pixel->vector): source dir holds capture-manifest.tsv (v1, byte pins
of every population tile) and evidence.tsv with header 'kni-pixel-notdef-evidence<TAB>v3'. Grammar:
  kind/style/frame/scale/ink_model once each; kind = repeated-form|blank-cell; ink_model is the canonical
  decoded-gray-all-255-no-transform-v1; pixel_form_sha256 once (the claimed form hash; shape-checked here,
  recomputed from decoded pixels and verified by the engine); selected<TAB>path<TAB>sha256 once; capture_sha256
  once (rewritten to the staged capture manifest sha); pixel_source<TAB>0xCP<TAB>role<TAB>path<TAB>sha256 rows,
  role = kind, CP a nonzero Unicode scalar, path relative to the evidence record; NO
  requested_unsupported/missingchar/verdict/dimensions rows; NO numeric advance row anywhere;
  NO space_evidence_sha256 row: blank advance is the font's widest character advance, there is no space binding.
  blank-cell goes through the same staging flow as repeated-form (kind=blank-cell, no space field).
  pixel_source carries ONLY the winning group's codepoints (an extraction manifest: these codepoints are never
  written into the font as characters; the shared form is emitted only at gid0 as .notdef). The sha columns
  are tile BYTE shas: each pixel_source row must resolve to the capture manifest's row for its codepoint
  (same staged tile, same byte pin), the selected row must resolve to a pixel_source row, and no winning
  codepoint may remain a glyph row in the run manifest (extraction is the manifest producer's job). Form
  identity and frequency over the full population are re-verified by the engine from decoded pixels; they
  are not derivable from this record.
Selection rule: the winning group needs >= 2 codepoints (a count=1 form is an ordinary glyph, never a
candidate). The staged manifest gains capture_manifest + notdef evidence rows (PixelEvidence route); the
notdef_proxy route serves legacy-shape manifests and is never written here.
Typed refusals exit 3."""
import argparse, hashlib, os, re, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit_manifest import style_token_encode

def refuse(m): print("REFUSED " + m); sys.exit(3)
def sha(p): return hashlib.sha256(open(p, "rb").read()).hexdigest()
STAGING = ".notdef.staging"
def physical(root, rel):
    # Content paths stay final ('notdef/...'); during staging the physical
    # bytes live under R/.notdef.staging. After the rename commit the same
    # content path resolves at the same place.
    if rel.startswith("notdef/"): return os.path.join(root, STAGING, rel[len("notdef/"):])
    return os.path.join(root, rel)
def under(root, rel):
    if os.path.isabs(rel) or any(c in ("..", "") for c in rel.split("/")): refuse(f"NotdefPathEscape: {rel!r} (absolute, '..' or empty component)")
    p = physical(root, rel)
    if os.path.islink(p) or not os.path.isfile(p) or not os.path.realpath(p).startswith(os.path.realpath(root) + os.sep): refuse(f"NotdefPathEscape: {rel!r} is not a regular file under the run root")
    return p

INK_MODEL = "decoded-gray-all-255-no-transform-v1"

def parse_manifest(a):
    man = open(a.manifest, encoding="utf-8").read().splitlines()
    one = lambda k: [l.split(None, 1)[1] for l in man if l.split(None, 1)[:1] == [k]]
    scale = one("scale"); frame = one("capture_frame"); fam = one("family"); sub = one("subfamily")
    if len(scale) != 1 or len(frame) != 1 or len(fam) != 1 or len(sub) != 1: refuse("NotdefManifestIncomplete: scale/capture_frame/family/subfamily line missing or duplicated")
    sty = [l.split(None, 1)[1].strip() for l in man if l.startswith("#@style_id ")]
    if len(sty) != 1: refuse("NotdefManifestIncomplete: '#@style_id' header missing (kit_manifest writes it)")
    return man, scale[0].strip(), frame[0].strip(), sty[0]

def copy_tree(S, R):
    ND = os.path.join(R, STAGING)
    for d, ds, fs in os.walk(S, followlinks=False):
        for n in ds + fs:
            if os.path.islink(os.path.join(d, n)): refuse(f"NotdefSymlink: {os.path.join(d, n)}")
        rel = os.path.relpath(d, S); os.makedirs(os.path.join(ND, rel), exist_ok=True)
        for f in fs: shutil.copyfile(os.path.join(d, f), os.path.join(ND, rel, f))
    return ND

def rewrite_capture(R, ND, style, frame):
    cap = open(os.path.join(ND, "capture-manifest.tsv"), encoding="utf-8").read().split("\n")
    if cap[0] != "kni-capture-manifest\tv1": refuse("NotdefCaptureGrammar: first line must be 'kni-capture-manifest<TAB>v1'")
    out = [cap[0]]; pins = {}; cps = {}
    for line in cap[1:]:
        if line == "": continue
        f = line.split("\t")
        if len(f) == 2 and f[0] in ("style", "cohort", "frame"): out.append(line); continue
        if len(f) == 4 and f[0] == "source":
            rel = f[2]; new = rel if rel.startswith("glyph/") else "notdef/" + rel
            p = under(R, new)
            if sha(p) != f[3]: refuse(f"NotdefTileShaMismatch: {new} sha256 differs from the capture row pin")
            cps[int(f[1].replace("0x", ""), 16)] = new; pins[new] = f[3]
            out.append("\t".join(["source", f[1], new, f[3]])); continue
        refuse(f"NotdefCaptureGrammar: unknown row {line[:60]!r}")
    kv = {l.split("\t")[0]: l.split("\t")[1] for l in out[1:] if l.split("\t")[0] in ("style", "cohort", "frame")}
    if kv.get("style") != style or kv.get("frame") != frame: refuse("NotdefContextMismatch: capture manifest style/frame differ from this run's style/capture_frame")
    cp_path = os.path.join(ND, "capture-manifest.tsv")
    open(cp_path, "w", encoding="utf-8", newline="").write("\n".join(out) + "\n")
    return sha(cp_path), pins, cps

def audit_glyphs(man, cps):
    for l in man:
        g = l.split()
        if len(g) >= 4 and g[0] == "glyph":
            cp = int(g[1].replace("0x", ""), 16)
            if cps.get(cp) != g[3]: refuse(f"NotdefAuditMismatch: glyph U+{cp:04X} capture row {cps.get(cp)!r} != manifest tile {g[3]!r}")

def cp_of(tok):
    try: cp = int(tok.replace("0x", ""), 16)
    except ValueError: refuse(f"NotdefEvidenceGrammar: bad codepoint {tok!r}")
    if cp == 0 or cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF: refuse(f"NotdefEvidenceGrammar: codepoint {tok!r} is not a nonzero Unicode scalar")
    return cp

def v3_parse(lines, man):
    if not lines or lines[0] != "kni-pixel-notdef-evidence\tv3": refuse("NotdefEvidenceGrammar: first line must be 'kni-pixel-notdef-evidence<TAB>v3'")
    is_sha = lambda t: bool(re.fullmatch(r"[0-9a-f]{64}", t))
    singles = {}; rows = []; seen_cp = set()
    for line in lines[1:]:
        if line == "": continue
        f = line.split("\t"); k = f[0]
        if k in ("requested_unsupported", "missingchar", "verdict", "dimensions"): refuse(f"NotdefEvidenceGrammar: {k} is not part of the v3 pixel-evidence grammar")
        if k == "space_evidence_sha256": refuse("NotdefEvidenceGrammar: space_evidence_sha256 is not part of v3 pixel evidence (blank advance is the font's widest character advance; no space binding)")
        if k == "advance": refuse("NotdefEvidenceGrammar: numeric advance is not allowed in v3 pixel evidence (repeated advance comes from the solver, blank advance is the font's widest character advance)")
        if k == "pixel_source":
            if len(f) != 5: refuse(f"NotdefEvidenceGrammar: pixel_source row needs 5 fields, got {len(f)}")
            cp = cp_of(f[1])
            if cp in seen_cp: refuse(f"NotdefEvidenceGrammar: pixel_source codepoint U+{cp:04X} duplicated")
            seen_cp.add(cp)
            if not is_sha(f[4]): refuse("NotdefEvidenceGrammar: pixel_source sha256 must be 64 lowercase hex (a tile byte sha)")
            rows.append((cp, f[2], f[3], f[4])); continue
        if k == "selected":
            if len(f) != 3: refuse(f"NotdefEvidenceGrammar: selected row needs 3 fields, got {len(f)}")
            if k in singles: refuse("NotdefEvidenceGrammar: selected row duplicated")
            if not is_sha(f[2]): refuse("NotdefEvidenceGrammar: selected sha256 must be 64 lowercase hex (a tile byte sha)")
            singles[k] = (f[1], f[2]); continue
        if k in ("kind", "style", "frame", "scale", "ink_model", "capture_sha256", "pixel_form_sha256"):
            if len(f) != 2: refuse(f"NotdefEvidenceGrammar: {k} row needs 2 fields, got {len(f)}")
            if k in singles: refuse(f"NotdefEvidenceGrammar: {k} row duplicated")
            if k == "pixel_form_sha256" and not is_sha(f[1]): refuse("NotdefEvidenceGrammar: pixel_form_sha256 must be 64 lowercase hex")
            singles[k] = f[1]; continue
        refuse(f"NotdefEvidenceGrammar: unknown row {line[:60]!r}")
    for need in ("kind", "style", "frame", "scale", "ink_model", "selected", "capture_sha256", "pixel_form_sha256"):
        if need not in singles: refuse(f"NotdefEvidenceIncomplete: {need} row missing")
    if singles["kind"] not in ("repeated-form", "blank-cell"): refuse(f"NotdefEvidenceGrammar: kind {singles['kind']!r} is not repeated-form|blank-cell")
    if singles["ink_model"] != INK_MODEL: refuse(f"NotdefContextMismatch: ink_model {singles['ink_model']!r} is not the canonical {INK_MODEL!r}")
    kind = singles["kind"]
    for cp, role, path, pin in rows:
        if role != kind: refuse(f"NotdefEvidenceGrammar: pixel_source role {role!r} differs from kind {kind!r}")
    sel_path, sel_sha = singles["selected"]
    if len(rows) < 2: refuse("NotdefMissingPixelEvidence: the winning group needs at least 2 codepoints (a count=1 form is an ordinary glyph, never a candidate)")
    if not any(path == sel_path and pin == sel_sha for _, _, path, pin in rows): refuse(f"NotdefAuditMismatch: selected row {sel_path!r} does not resolve to a pixel_source row (path and byte sha)")
    glyph_cps = {int(l.split()[1].replace("0x", ""), 16) for l in man if l.split()[:1] == ["glyph"] and len(l.split()) >= 4}
    for cp, role, path, pin in rows:
        if cp in glyph_cps: refuse(f"NotdefAuditMismatch: winning codepoint U+{cp:04X} still has a glyph row in the run manifest (extraction is the manifest producer's job)")
    return singles, rows

def stage_v3(R, ND, man, style, frame, scale, CAP, pins, cps, a):
    ev = open(os.path.join(ND, "evidence.tsv"), encoding="utf-8").read().split("\n")
    singles, rows = v3_parse(ev, man)
    if singles["style"] != style or singles["frame"] != frame or float(singles["scale"]) != float(scale): refuse("NotdefContextMismatch: v3 evidence style/frame/scale differ from this run")
    for cp, role, path, pin in rows:
        if path.startswith("glyph/") or path.startswith("notdef/"): refuse(f"NotdefPathEscape: pixel_source path {path!r} must be relative to the evidence record (no glyph/ or notdef/ prefix)")
        q = "notdef/" + path
        p = under(R, q)
        if sha(p) != pin: refuse(f"NotdefTileShaMismatch: pixel_source tile {path!r} sha256 differs from its row pin")
        if cps.get(cp) != q: refuse(f"NotdefAuditMismatch: pixel_source U+{cp:04X} is not the capture manifest's tile for that codepoint ({cps.get(cp)!r}); the engine population needs the same tile")
    eo = []
    for line in ev:
        f = line.split("\t")
        if f[0] == "capture_sha256": line = "capture_sha256\t" + CAP
        eo.append(line)
    e_path = os.path.join(ND, "evidence.tsv"); open(e_path, "w", encoding="utf-8", newline="").write("\n".join(eo))
    rows_out = f"capture_manifest notdef/capture-manifest.tsv {CAP}\n"
    rows_out += "notdef evidence notdef/evidence.tsv %s %s %s %s %s\n" % (sha(e_path), style_token_encode(style), CAP, scale, frame)
    group = ",".join(f"0x{c:x}" for c in sorted(cp for cp, _, _, _ in rows))
    summary = f"notdef v3 pixel evidence staged under {R}/notdef: capture sha {CAP[:12]}, evidence sha {sha(e_path)[:12]}, winner group {group}, route PixelEvidence"
    return rows_out, summary

def stage_v2(R, ND, man, style, frame, scale, CAP, pins, a):
    ev = open(os.path.join(ND, "evidence.tsv"), encoding="utf-8").read().split("\n"); eo = []; seen = {}
    for line in ev:
        f = line.split("\t")
        if f[0] == "capture": line = "capture\t" + CAP
        if f[0] in ("style", "frame", "scale", "capture"): seen[f[0]] = f[1] if f[0] != "capture" else CAP
        if f[0] == "selected" and len(f) == 3 or f[0] == "witness" and len(f) == 6:
            rel = f[1] if f[0] == "selected" else f[3]; pin = f[2] if f[0] == "selected" else f[4]
            q = "notdef/" + rel; under(R, q)
            if pins.get(q) != pin or sha(physical(R, q)) != pin: refuse(f"NotdefAuditMismatch: evidence tile {rel!r} not in the capture inventory with this sha")
        eo.append(line)
    if seen.get("style") != style or seen.get("frame") != frame or float(seen.get("scale", "nan")) != float(scale): refuse("NotdefContextMismatch: evidence style/frame/scale differ from this run")
    e_path = os.path.join(ND, "evidence.tsv"); open(e_path, "w", encoding="utf-8", newline="").write("\n".join(eo))
    rows_out = f"capture_manifest notdef/capture-manifest.tsv {CAP}\n"
    rows_out += "notdef evidence notdef/evidence.tsv %s %s %s %s %s\n" % (sha(e_path), style_token_encode(style), CAP, scale, frame)
    summary = f"notdef staged under {R}/notdef: capture sha {CAP[:12]}, evidence sha {sha(e_path)[:12]}"
    return rows_out, summary

def manifest_update_atomic(path, rows_out):
    # Sibling temp in the SAME directory (same filesystem) + os.replace:
    # the manifest is never half-written.
    cur = open(path, "rb").read()
    tmp = path + ".staging-" + str(os.getpid())
    try:
        with open(tmp, "wb") as f: f.write(cur + rows_out.encode("utf-8"))
        os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--run-dir", required=True); ap.add_argument("--notdef-dir", required=True)
    ap.add_argument("--manifest", required=True); a = ap.parse_args()
    R = os.path.realpath(a.run_dir); S = a.notdef_dir
    man, scale, frame, style = parse_manifest(a)
    for need in ("capture-manifest.tsv", "evidence.tsv"):
        if not os.path.isfile(os.path.join(S, need)) or os.path.islink(os.path.join(S, need)): refuse(f"NotdefEvidenceMissing: {S}/{need}")
    is_v3 = open(os.path.join(S, "evidence.tsv"), encoding="utf-8").readline().rstrip("\n") == "kni-pixel-notdef-evidence\tv3"
    if is_v3: v3_parse(open(os.path.join(S, "evidence.tsv"), encoding="utf-8").read().split("\n"), man)  # full validation before anything is staged
    ND = os.path.join(R, "notdef"); ND_TMP = os.path.join(R, STAGING)
    if os.path.exists(ND_TMP): refuse(f"NotdefOrphanStage: {ND_TMP} exists - a previous run was killed mid-staging; inspect it, then remove it before retrying")
    if os.path.exists(ND): refuse("NotdefStageExists: run root already has notdef/")
    try:
        ND_TMP = copy_tree(S, R)
        CAP, pins, cps = rewrite_capture(R, ND_TMP, style, frame)
        audit_glyphs(man, cps, winners, kind)
        if is_v3: rows_out, summary = stage_v3(R, ND_TMP, man, style, frame, scale, CAP, pins, cps, a)
        else: rows_out, summary = stage_v2(R, ND_TMP, man, style, frame, scale, CAP, pins, a)
    except BaseException:
        # Every refusal above exits 3 with R and the manifest untouched.
        shutil.rmtree(ND_TMP, ignore_errors=True)
        raise
    # Commit: same-fs rename (atomic on POSIX), then the atomic manifest update.
    os.rename(ND_TMP, ND)
    try:
        manifest_update_atomic(a.manifest, rows_out)
    except BaseException:
        os.rename(ND, ND_TMP)
        shutil.rmtree(ND_TMP, ignore_errors=True)
        raise
    print(summary)

main()
