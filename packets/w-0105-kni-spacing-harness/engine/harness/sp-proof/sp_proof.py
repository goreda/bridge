#!/usr/bin/env python3
"""SP-PROOF: bit-identity proof harness for off-target styles/pairs.

Answers one question: did a candidate engine change ANY byte of any output
that belongs to a style (or pair) it was not supposed to touch?

Inputs
  base sha + candidate sha   labels of the two engine revisions under test
                             (recorded in the report; in `run` mode they are
                             the two git revisions that get built).
  kit manifest               TSV, one row per style:
                               style_id <TAB> family <TAB> subfamily <TAB>
                               manifest_relpath <TAB> out_relpath <TAB> scope
                             scope is exactly `on-target` or `off-target`.
                             Only off-target rows are compared; on-target rows
                             are reported as SKIPPED. manifest_relpath points
                             at the engine manifest for `run` mode; relative
                             paths resolve against $KNI_G_FIXTURES (never a
                             hardcoded path). Use `-` in compare-only kits.

Outputs
  --styles a,b,c               optional subset of kit style_ids; only those
                               are compared/run. Unknown ids refuse (typed).

  - stdout summary, machine-checkable exit code,
  - --report-json PATH: full style x glyph matrix (always complete),
  - --report-md PATH: human report; per-glyph tables only where DIFF.

Verdicts and exit codes (CONVENTION, declared here, never negotiated per run):
  PASS     exit 0  every off-target artifact byte-identical.
  FAIL     exit 4  at least one difference; the report names the first
                   differing glyph (glyph order) per differing style.
  REFUSED  exit 3  inputs unreadable/malformed; nothing was compared.

Artifact set compared per style out-dir (CONVENTION with rationale):
  font-<style_id>.otf   the shipped font; compared byte-for-byte first, and
                        on DIFF parsed per glyph (CFF CharStrings INDEX keyed
                        by the charset) so the report can name the first
                        differing glyph. The font MUST exist on both sides;
                        a missing font is a FAIL, never a skip.
  mapping.tsv, spacing.tsv, spacing-pair-ledger.tsv, kern-ledger.tsv,
  kern-diagnostic.tsv, iou.tsv, iou-population.tsv, profile-metadata.tsv
                        byte-for-byte. Identical absence on both sides counts
                        as identical (stage not reached in both runs equally).
  receipt-<style_id>.txt, run-provenance.tsv, stage1-cache.txt, floor.otf
                        are EXCLUDED: they can embed run-local absolute paths
                        and diagnostic prose, so byte equality is not defined
                        across two run roots. Documented exclusion, not a gap:
                        geometry, spacing and kern evidence all live in the
                        compared artifacts.

Glyph names come from the font itself: GID 0 is `.notdef` by spec, names
with SID >= 391 resolve through the CFF String INDEX (the engine's own
writer places every name there). A SID < 391 (foreign font) is labelled
`sid:<n>` and a typed warning is recorded; comparison still proceeds.

Stdlib only. Reads files, writes reports only where told. Repo text English.
"""
import argparse, hashlib, json, os, shutil, subprocess, sys

EXIT_PASS, EXIT_REFUSED, EXIT_FAIL = 0, 3, 4

LEDGER_ARTIFACTS = (
    "mapping.tsv", "spacing.tsv", "spacing-pair-ledger.tsv",
    "kern-ledger.tsv", "kern-diagnostic.tsv",
    "iou.tsv", "iou-population.tsv", "profile-metadata.tsv",
)
SCOPES = ("on-target", "off-target")


def refuse(msg):
    sys.stderr.write("sp_proof: REFUSED: " + msg + "\n")
    sys.exit(EXIT_REFUSED)


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


# ---------------------------------------------------------------- kit manifest

class KitRow:
    __slots__ = ("style_id", "family", "subfamily", "manifest", "out", "scope", "line")

    def __init__(self, fields, line):
        (self.style_id, self.family, self.subfamily,
         self.manifest, self.out, self.scope) = fields
        self.line = line


def load_kit(path):
    try:
        text = open(path, "r", encoding="utf-8").read()
    except OSError as e:
        refuse("KitManifestUnreadable: %s" % e)
    rows = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in raw.rstrip("\n").split("\t")]
        if len(fields) != 6:
            refuse("KitManifestMalformed: line %d: want 6 tab-separated fields, got %d" % (lineno, len(fields)))
        if fields[5] not in SCOPES:
            refuse("KitManifestMalformed: line %d: scope must be one of %s, got %r" % (lineno, "/".join(SCOPES), fields[5]))
        if not fields[0] or any(c in fields[0] for c in "/\\ \t"):
            refuse("KitManifestMalformed: line %d: bad style_id %r" % (lineno, fields[0]))
        rows.append(KitRow(fields, lineno))
    if not rows:
        refuse("KitManifestEmpty: %s has no style rows" % path)
    if not any(r.scope == "off-target" for r in rows):
        refuse("KitManifestNoOffTarget: nothing to prove: no off-target rows")
    seen = set()
    for r in rows:
        if r.style_id in seen:
            refuse("KitManifestMalformed: duplicate style_id %r (line %d)" % (r.style_id, r.line))
        seen.add(r.style_id)
    return rows


# ---------------------------------------------------------------- style subset

def filter_styles(rows, subset):
    """--styles a,b,c: compare/run only those kit rows. Unknown ids are a
    typed refusal, never a silent skip."""
    if not subset:
        return rows
    wanted = [w.strip() for w in subset.split(",") if w.strip()]
    if not wanted:
        refuse("StyleSubsetEmpty: --styles named no style")
    known = {r.style_id for r in rows}
    for w in wanted:
        if w not in known:
            refuse("StyleSubsetUnknown: %r is not a style_id in the kit manifest (known: %s)"
                   % (w, ", ".join(sorted(known))))
    return [r for r in rows if r.style_id in set(wanted)]


# ---------------------------------------------------------------- CFF reading

class CffError(Exception):
    pass


def _u16(b, o):
    return (b[o] << 8) | b[o + 1]


def _u32(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


def sfnt_table(font, tag):
    if len(font) < 12:
        raise CffError("Truncated: sfnt header")
    num = _u16(font, 4)
    for i in range(num):
        rec = 12 + 16 * i
        if rec + 16 > len(font):
            raise CffError("Truncated: table directory")
        if font[rec:rec + 4] == tag:
            off, length = _u32(font, rec + 8), _u32(font, rec + 12)
            if off + length > len(font):
                raise CffError("TableOutOfBounds: %r" % tag)
            return font[off:off + length]
    raise CffError("MissingTable: %r" % tag)


def read_index(b, o, what):
    if o + 2 > len(b):
        raise CffError("Truncated: %s INDEX count" % what)
    count = _u16(b, o)
    o += 2
    if count == 0:
        return [], o
    if o >= len(b):
        raise CffError("Truncated: %s INDEX offSize" % what)
    offsize = b[o]
    o += 1
    if not 1 <= offsize <= 4:
        raise CffError("BadIndex: %s offSize %d" % (what, offsize))
    offs = []
    for _ in range(count + 1):
        if o + offsize > len(b):
            raise CffError("Truncated: %s INDEX offsets" % what)
        v = 0
        for k in range(offsize):
            v = (v << 8) | b[o + k]
        offs.append(v)
        o += offsize
    data_start = o
    objects = []
    for i in range(count):
        lo, hi = offs[i] - 1, offs[i + 1] - 1
        if lo < 0 or hi < lo or data_start + hi > len(b):
            raise CffError("BadIndex: %s object %d out of bounds" % (what, i))
        objects.append(b[data_start + lo:data_start + hi])
    end = data_start + (offs[-1] - 1 if offs[-1] else 0)
    return objects, end


def read_dict(b, wanted):
    """Parse one DICT; return {op: last_operand} for the wanted operators."""
    out = {}
    stack = []
    i = 0
    while i < len(b):
        b0 = b[i]
        i += 1
        if b0 == 28:
            if i + 2 > len(b):
                raise CffError("Truncated: dict int16")
            stack.append((b[i] << 8 | b[i + 1]) - (0x10000 if b[i] & 0x80 else 0))
            i += 2
        elif b0 == 29:
            if i + 4 > len(b):
                raise CffError("Truncated: dict int32")
            v = _u32(b, i)
            stack.append(v - (1 << 32) if v & 0x80000000 else v)
            i += 4
        elif b0 == 30:  # real number, BCD nibbles; parse-and-drop
            while i < len(b):
                byte = b[i]
                i += 1
                if (byte & 0xF) == 0xF or (byte >> 4) == 0xF:
                    break
            stack.append(None)
        elif 32 <= b0 <= 246:
            stack.append(b0 - 139)
        elif 247 <= b0 <= 254:
            if i >= len(b):
                raise CffError("Truncated: dict operand")
            b1 = b[i]
            i += 1
            stack.append((b0 - 247) * 256 + b1 + 108 if b0 <= 250 else -(b0 - 251) * 256 - b1 - 108)
        else:
            op = (12, b[i]) if b0 == 12 else b0
            if b0 == 12:
                i += 1
                if i > len(b):
                    raise CffError("Truncated: dict escape op")
            if op in wanted and stack:
                out[op] = stack[-1]
            stack = []
    return out


def glyph_charstrings(font):
    """Return (names, charstrings, warnings): ordered per-GID glyph names and
    raw Type 2 charstring bytes. names[0] is always '.notdef'."""
    cff = sfnt_table(font, b"CFF ")
    if len(cff) < 4:
        raise CffError("Truncated: CFF header")
    hdr_size = cff[2]
    _, o = read_index(cff, hdr_size, "Name")
    top_dicts, o = read_index(cff, o, "Top DICT")
    if len(top_dicts) != 1:
        raise CffError("BadDict: want exactly 1 Top DICT, got %d" % len(top_dicts))
    strings, _ = read_index(cff, o, "String")
    top = read_dict(top_dicts[0], wanted={15, 17})
    if 17 not in top or top[17] is None:
        raise CffError("MissingTopDictEntry: CharStrings")
    if 15 not in top or top[15] is None:
        raise CffError("MissingTopDictEntry: charset")
    charsets_off, chars_off = top[15], top[17]
    charstrings, _ = read_index(cff, chars_off, "CharStrings")
    n = len(charstrings)
    # charset
    if charsets_off >= len(cff):
        raise CffError("BadDict: charset offset out of bounds")
    fmt = cff[charsets_off]
    p = charsets_off + 1
    sids = []
    if fmt == 0:
        for _ in range(n - 1):
            if p + 2 > len(cff):
                raise CffError("Truncated: charset format 0")
            sids.append(_u16(cff, p))
            p += 2
    elif fmt in (1, 2):
        while len(sids) < n - 1:
            if p + (3 if fmt == 1 else 4) > len(cff):
                raise CffError("Truncated: charset format %d" % fmt)
            first = _u16(cff, p)
            p += 2
            if fmt == 1:
                left = cff[p]
                p += 1
            else:
                left = _u16(cff, p)
                p += 2
            sids.extend(range(first, first + left + 1))
        sids = sids[:n - 1]
    else:
        raise CffError("BadDict: charset format %d" % fmt)
    if len(sids) != n - 1:
        raise CffError("BadDict: charset covers %d glyphs, CharStrings has %d" % (len(sids) + 1, n))
    warnings = []
    names = [".notdef"]
    for sid in sids:
        if sid >= 391:
            idx = sid - 391
            if idx >= len(strings):
                raise CffError("BadDict: SID %d has no String INDEX entry" % sid)
            try:
                names.append(strings[idx].decode("ascii"))
            except UnicodeDecodeError:
                raise CffError("BadDict: non-ASCII glyph name at SID %d" % sid)
        else:
            names.append("sid:%d" % sid)
            warnings.append("standard_string_sid\t%d\tlabelled sid:%d (no standard table embedded)" % (sid, sid))
    return names, charstrings, warnings


# ---------------------------------------------------------------- comparison

ARTIFACT_SAME, ARTIFACT_DIFF = "SAME", "DIFF"


def read_bytes(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError as e:
        refuse("ArtifactUnreadable: %s: %s" % (path, e))


def compare_font(base_bytes, cand_bytes):
    """Whole-file first; on DIFF, per-glyph resolution. Returns a dict with
    the style x glyph matrix and the first differing glyph (glyph order)."""
    result = {"font_sha256_base": sha256_hex(base_bytes),
              "font_sha256_cand": sha256_hex(cand_bytes)}
    if base_bytes == cand_bytes:
        result["font"] = ARTIFACT_SAME
        try:
            names, _, _ = glyph_charstrings(base_bytes)
            result["glyph_count"] = len(names)
        except CffError:
            result["glyph_count"] = None
        return result
    result["font"] = ARTIFACT_DIFF
    try:
        b_names, b_chars, b_warn = glyph_charstrings(base_bytes)
        c_names, c_chars, c_warn = glyph_charstrings(cand_bytes)
    except CffError as e:
        result["glyph_error"] = str(e)
        result["first_diff_glyph"] = None
        return result
    result["glyph_warnings"] = b_warn + c_warn
    matrix = []
    first_diff = None
    n = max(len(b_names), len(c_names))
    for gid in range(n):
        b = sha256_hex(b_chars[gid]) if gid < len(b_chars) else None
        c = sha256_hex(c_chars[gid]) if gid < len(c_chars) else None
        name = b_names[gid] if gid < len(b_names) else c_names[gid]
        if b is None:
            status = "CAND-ONLY"
        elif c is None:
            status = "BASE-ONLY"
        elif b == c:
            status = "SAME"
        else:
            status = "DIFF"
        matrix.append({"gid": gid, "name": name, "status": status,
                       "base_sha256": b, "cand_sha256": c})
        if first_diff is None and status != "SAME":
            first_diff = {"gid": gid, "name": name, "status": status}
    result["glyph_count"] = n
    result["glyph_diff_count"] = sum(1 for m in matrix if m["status"] != "SAME")
    result["matrix"] = matrix
    result["first_diff_glyph"] = first_diff
    return result


def compare_style(row, base_root, cand_root):
    base_dir, cand_dir = os.path.join(base_root, row.out), os.path.join(cand_root, row.out)
    style = {"style_id": row.style_id, "family": row.family, "subfamily": row.subfamily,
             "scope": row.scope, "out": row.out, "artifacts": [], "verdict": "PASS"}
    font_name = "font-%s.otf" % row.style_id
    wanted = [font_name] + list(LEDGER_ARTIFACTS)
    for fname in wanted:
        b_path, c_path = os.path.join(base_dir, fname), os.path.join(cand_dir, fname)
        b_has, c_has = os.path.isfile(b_path), os.path.isfile(c_path)
        if not b_has and not c_has:
            if fname == font_name:
                style["artifacts"].append({"name": fname, "status": "MISSING-BOTH"})
                style["verdict"] = "FAIL"
            else:
                style["artifacts"].append({"name": fname, "status": "NOT-EMITTED"})
            continue
        if not b_has or not c_has:
            style["artifacts"].append({"name": fname, "status": "MISSING-BASE" if not b_has else "MISSING-CAND"})
            style["verdict"] = "FAIL"
            continue
        b_bytes, c_bytes = read_bytes(b_path), read_bytes(c_path)
        if fname == font_name:
            detail = compare_font(b_bytes, c_bytes)
            entry = {"name": fname, "status": detail["font"]}
            if detail["font"] == ARTIFACT_DIFF:
                style["verdict"] = "FAIL"
                for k in ("font_sha256_base", "font_sha256_cand", "glyph_count",
                          "glyph_diff_count", "matrix", "first_diff_glyph",
                          "glyph_error", "glyph_warnings"):
                    if k in detail:
                        entry[k] = detail[k]
            else:
                entry["sha256"] = detail["font_sha256_base"]
                entry["glyph_count"] = detail.get("glyph_count")
            style["artifacts"].append(entry)
        else:
            if b_bytes == c_bytes:
                style["artifacts"].append({"name": fname, "status": ARTIFACT_SAME, "sha256": sha256_hex(b_bytes)})
            else:
                style["artifacts"].append({"name": fname, "status": ARTIFACT_DIFF,
                                           "base_sha256": sha256_hex(b_bytes),
                                           "cand_sha256": sha256_hex(c_bytes)})
                style["verdict"] = "FAIL"
    return style


# ---------------------------------------------------------------- reports

def render_md(report):
    L = []
    L.append("# SP-PROOF bit-identity report")
    L.append("")
    L.append("- base: `%s`" % report["base_label"])
    L.append("- candidate: `%s`" % report["cand_label"])
    L.append("- kit manifest: `%s`" % report["kit"])
    L.append("- verdict: **%s**" % report["verdict"])
    L.append("")
    L.append("| style | scope | verdict | artifacts DIFF | first differing glyph |")
    L.append("|---|---|---|---|---|")
    for s in report["styles"]:
        if s["scope"] == "on-target":
            L.append("| %s | on-target | SKIPPED | - | - |" % s["style_id"])
            continue
        diffs = [a["name"] for a in s["artifacts"] if a["status"] in (ARTIFACT_DIFF, "MISSING-BASE", "MISSING-CAND", "MISSING-BOTH")]
        first = "-"
        for a in s["artifacts"]:
            fd = a.get("first_diff_glyph")
            if fd:
                first = "%s (GID %d, %s)" % (fd["name"], fd["gid"], fd["status"])
                break
        L.append("| %s | off-target | %s | %s | %s |" % (s["style_id"], s["verdict"], ", ".join(diffs) or "-", first))
    for s in report["styles"]:
        if s["scope"] == "on-target":
            continue
        for a in s["artifacts"]:
            if "matrix" in a:
                L.append("")
                L.append("## %s: glyph matrix (DIFF only)" % s["style_id"])
                L.append("")
                L.append("| GID | glyph | status | base sha256 | cand sha256 |")
                L.append("|---|---|---|---|---|")
                for m in a["matrix"]:
                    if m["status"] == "SAME":
                        continue
                    L.append("| %d | %s | %s | %s | %s |" % (
                        m["gid"], m["name"], m["status"],
                        (m["base_sha256"] or "-")[:16], (m["cand_sha256"] or "-")[:16]))
            for w in a.get("glyph_warnings", []):
                L.append("")
                L.append("warning: %s/%s: %s" % (s["style_id"], a["name"], w))
    L.append("")
    return "\n".join(L)


def run_compare(args):
    rows = filter_styles(load_kit(args.kit), getattr(args, "styles", None))
    if not os.path.isdir(args.base_root):
        refuse("RunRootMissing: base root %s" % args.base_root)
    if not os.path.isdir(args.cand_root):
        refuse("RunRootMissing: candidate root %s" % args.cand_root)
    styles = []
    for r in rows:
        if r.scope == "on-target":
            styles.append({"style_id": r.style_id, "scope": r.scope, "verdict": "SKIPPED", "artifacts": []})
        else:
            styles.append(compare_style(r, args.base_root, args.cand_root))
    verdict = "PASS" if all(s["verdict"] != "FAIL" for s in styles) else "FAIL"
    report = {"tool": "sp_proof", "base_label": args.base_label, "cand_label": args.cand_label,
              "kit": args.kit, "styles_subset": getattr(args, "styles", None),
              "verdict": verdict, "styles": styles}
    if args.report_json:
        with open(args.report_json, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, sort_keys=True)
            f.write("\n")
    if args.report_md:
        with open(args.report_md, "w", encoding="utf-8") as f:
            f.write(render_md(report))
    off = [s for s in styles if s["scope"] == "off-target"]
    failed = [s for s in off if s["verdict"] == "FAIL"]
    print("sp_proof: %s — %d off-target style(s), %d identical, %d FAILED (base=%s cand=%s)"
          % (verdict, len(off), len(off) - len(failed), len(failed), args.base_label, args.cand_label))
    for s in failed:
        first = next((a.get("first_diff_glyph") for a in s["artifacts"] if a.get("first_diff_glyph")), None)
        print("  FAIL %s%s" % (s["style_id"],
              (" first differing glyph: %s (GID %d)" % (first["name"], first["gid"])) if first else ""))
    return EXIT_PASS if verdict == "PASS" else EXIT_FAIL


# ---------------------------------------------------------------- run driver

def run_driver(args):
    fixtures = os.environ.get("KNI_G_FIXTURES")
    rows = filter_styles(load_kit(args.kit), getattr(args, "styles", None))
    resolved = {}
    for r in rows:
        if r.scope != "off-target":
            continue
        if r.manifest == "-":
            refuse("KitManifestMalformed: style %s has no engine manifest (`-`); run mode needs one" % r.style_id)
        # relative manifest paths resolve against $KNI_G_FIXTURES when set,
        # else against the kit file's own directory (self-contained kits).
        if os.path.isabs(r.manifest):
            path = r.manifest
        elif fixtures:
            path = os.path.join(fixtures, r.manifest)
        else:
            path = os.path.join(os.path.dirname(os.path.abspath(args.kit)), r.manifest)
        if not os.path.isfile(path):
            refuse("EngineManifestMissing: %s (style %s)" % (path, r.style_id))
        resolved[r.style_id] = path
    if not os.path.isdir(args.repo):
        refuse("RepoMissing: %s" % args.repo)
    if os.path.exists(args.work):
        refuse("WorkDirExists: %s (no overwrite)" % args.work)
    os.makedirs(args.work)
    engine_rel = os.path.join("kni-kit", "out8-runkit-v2", "engine")
    outs = {}
    for label, sha in (("base", args.base_sha), ("cand", args.cand_sha)):
        wt = os.path.join(args.work, label + "-src")
        subprocess.run(["git", "-C", args.repo, "worktree", "add", "--detach", wt, sha], check=True)
        cargo = shutil.which("cargo")
        if not cargo:
            refuse("ToolMissing: cargo not on PATH")
        subprocess.run([cargo, "build", "--release", "--manifest-path",
                        os.path.join(wt, engine_rel, "pipeline", "Cargo.toml")], check=True)
        binary = os.path.join(wt, engine_rel, "pipeline", "target", "release", "kni-pipeline")
        root = os.path.join(args.work, label + "-out")
        os.makedirs(root)
        for r in rows:
            if r.scope != "off-target":
                continue
            manifest = resolved[r.style_id]
            out_dir = os.path.join(root, r.out)
            cmd = [binary, manifest, out_dir, "--style-id", r.style_id] + list(args.run_extra_args or ())
            proc = subprocess.run(cmd, cwd=os.path.dirname(manifest))
            if proc.returncode != 0:
                sys.stderr.write("sp_proof: warning: %s run for style %s exited %d; comparison continues\n"
                                 % (label, r.style_id, proc.returncode))
        outs[label] = root
    ns = argparse.Namespace(kit=args.kit, base_root=outs["base"], cand_root=outs["cand"],
                            base_label=args.base_sha, cand_label=args.cand_sha,
                            styles=args.styles,
                            report_json=args.report_json, report_md=args.report_md)
    return run_compare(ns)


def main(argv):
    p = argparse.ArgumentParser(prog="sp_proof", description="SP-PROOF bit-identity proof harness (off-target styles/pairs).")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare", help="compare two already-produced run roots")
    c.add_argument("--kit", required=True, help="kit manifest TSV")
    c.add_argument("--base-root", required=True)
    c.add_argument("--cand-root", required=True)
    c.add_argument("--base-label", default="base")
    c.add_argument("--cand-label", default="candidate")
    c.add_argument("--styles", help="comma-separated style_id subset from the kit manifest; only these are compared")
    c.add_argument("--report-json")
    c.add_argument("--report-md")
    r = sub.add_parser("run", help="build both shas from a repo, run off-target styles, then compare")
    r.add_argument("--kit", required=True)
    r.add_argument("--repo", required=True)
    r.add_argument("--base-sha", required=True)
    r.add_argument("--cand-sha", required=True)
    r.add_argument("--work", required=True, help="fresh work dir (refuses if it exists)")
    r.add_argument("--styles", help="comma-separated style_id subset; only these are run and compared")
    r.add_argument("--run-extra-args", action="append", default=[],
                   help="one extra pipeline token per flag, passed to BOTH builds equally; use = for dashed values: --run-extra-args=--jobs --run-extra-args=2")
    r.add_argument("--report-json")
    r.add_argument("--report-md")
    args = p.parse_args(argv)
    if args.cmd == "compare":
        return run_compare(args)
    return run_driver(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
