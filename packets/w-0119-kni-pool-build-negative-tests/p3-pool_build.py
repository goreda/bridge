#!/usr/bin/env python3
"""AUTO-SB pool builder (repo tool; succeeds the ad hoc pool-build-r1.sh).

Builds an AUTO-SB observation pool (engine/pipeline/src/main.rs
AUTO_SB_POOL_HEADER contract: 4 TSV columns left_class/right_class/lsb/rsb,
"empty" = no class) from solved style spacing.tsv outputs.

Properties:
- Inputs are explicit and declared: one or more --root DIR trees are scanned
  for */*/spacing.tsv (two levels below the root, e.g. run19/Lyno/Jean). When
  the same style id "<family>/<style>" appears under several roots, the LAST
  root on the command line wins (rerun-preference dedup is a declared root
  order, never a hardcoded style list). --style FILE may instead point at
  individual spacing.tsv files (style id = the two parent directories).
- Exclusions are explicit: --exclude-style 'Family/Style' (repeatable). No
  style name is hardcoded. A file whose lsb values are all identical is
  flagged as a WARNING (unsolved constant-placeholder signal) but never
  auto-excluded.
- Rows: the spacing.tsv header maps lsb/rsb columns by NAME (refusal when
  absent); a row is kept when it has enough columns and both tokens parse as
  finite floats. Tokens are emitted VERBATIM (never reformatted), so a pool
  built from the same inputs is byte-reproducible.
- Output: header + rows in root order, then style discovery order, then file
  row order. Fully deterministic. Output sha256 and per-style row counts go
  to a stderr receipt; global medians (informational) use the engine's
  median_pure semantics (even n: mean of the two middle values).

usage: pool_build.py --root DIR [--root DIR ...] [--exclude-style ID ...]
                     --out POOL.tsv
       pool_build.py --style FILE [--style FILE ...] [--exclude-style ID ...]
                     --out POOL.tsv
Read-only on inputs. Writes only --out.
Exit 0 ok; exit 2 typed refusal on stderr.
"""
import argparse, hashlib, math, os, sys

HEADER = "left_class\tright_class\tlsb\trsb"
NO_CLASS = "empty"


def refuse(msg):
    sys.stderr.write("pool_build: refusal: %s\n" % msg)
    sys.exit(2)


def style_id_for(path, root):
    rel = os.path.relpath(path, root)
    parts = rel.split(os.sep)
    if len(parts) != 3 or parts[2] != "spacing.tsv":
        return None
    return "%s/%s" % (parts[0], parts[1])


def discover(roots):
    """Ordered (style_id, path) list; later roots override earlier ones."""
    chosen = {}
    order = []
    for root in roots:
        if not os.path.isdir(root):
            refuse("root missing: %s" % root)
        for fam in sorted(os.listdir(root)):
            fam_dir = os.path.join(root, fam)
            if not os.path.isdir(fam_dir):
                continue
            for sty in sorted(os.listdir(fam_dir)):
                cand = os.path.join(fam_dir, sty, "spacing.tsv")
                if not os.path.isfile(cand):
                    continue
                sid = "%s/%s" % (fam, sty)
                if sid not in chosen:
                    order.append(sid)
                chosen[sid] = cand
    return [(sid, chosen[sid]) for sid in order]


def load_rows(path):
    """(rows, n_lines) - rows as verbatim 'lsb\trsb' strings; typed refusal on
    a missing lsb/rsb header column."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as e:
        refuse("unreadable input %s: %s" % (path, e))
    if not lines:
        refuse("empty input: %s" % path)
    header = lines[0].split("\t")
    try:
        i_lsb = header.index("lsb")
        i_rsb = header.index("rsb")
    except ValueError:
        refuse("input %s: header lacks lsb/rsb columns (got: %s)" % (path, lines[0]))
    need = len(header)  # a kept row spans every declared column (reference: awk NF>=4)
    rows = []
    for raw in lines[1:]:
        if not raw:
            continue
        cols = raw.split("\t")
        if len(cols) < need:
            continue
        lsb, rsb = cols[i_lsb], cols[i_rsb]
        try:
            if not (math.isfinite(float(lsb)) and math.isfinite(float(rsb))):
                continue
        except ValueError:
            continue
        rows.append("%s\t%s" % (lsb, rsb))
    return rows


def median_pure(values):
    """Engine median_pure semantics; even n = mean of the two middles."""
    vals = sorted(values)
    n = len(vals)
    if n == 0:
        return None
    mid = n // 2
    if n % 2 == 1:
        return vals[mid]
    return (vals[mid - 1] + vals[mid]) / 2.0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="pool_build.py")
    ap.add_argument("--root", action="append", default=[])
    ap.add_argument("--style", action="append", default=[])
    ap.add_argument("--exclude-style", action="append", default=[])
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)

    if bool(a.root) == bool(a.style):
        refuse("declare exactly one input mode: --root tree(s) or --style file(s)")

    if a.root:
        selected = discover(a.root)
    else:
        selected = []
        for path in a.style:
            parent = os.path.dirname(os.path.abspath(path))
            parts = parent.split(os.sep)
            if len(parts) < 2:
                refuse("cannot derive style id from %s" % path)
            selected.append(("%s/%s" % (parts[-2], parts[-1]), path))

    excluded = set(a.exclude_style)
    kept = [(sid, p) for sid, p in selected if sid not in excluded]
    if not kept:
        refuse("no style inputs left after exclusions (%d excluded)" % len(excluded))

    out_lines = [HEADER]
    lsb_all, rsb_all = [], []
    receipt = []
    for sid, path in kept:
        rows = load_rows(path)
        if not rows:
            sys.stderr.write("pool_build: warning: %s (%s) contributed 0 usable rows\n" % (sid, path))
        lsb_vals = sorted(set(r.split("\t", 1)[0] for r in rows))
        if len(lsb_vals) == 1 and rows:
            sys.stderr.write(
                "pool_build: warning: %s (%s) lsb is a single constant %s on all %d rows"
                " (unsolved constant-placeholder signal; kept - exclusion is explicit only)\n"
                % (sid, path, lsb_vals[0], len(rows)))
        with open(path, "rb") as fh:
            src_sha = hashlib.sha256(fh.read()).hexdigest()
        receipt.append((sid, path, src_sha, len(rows)))
        for r in rows:
            out_lines.append("%s\t%s\t%s" % (NO_CLASS, NO_CLASS, r))
        for r in rows:
            l, s = r.split("\t")
            lsb_all.append(float(l))
            rsb_all.append(float(s))

    body = "\n".join(out_lines) + "\n"
    data = body.encode("utf-8")
    with open(a.out, "wb") as fh:
        fh.write(data)
    out_sha = hashlib.sha256(data).hexdigest()

    for sid, path, src_sha, n in receipt:
        sys.stderr.write("pool_build: style %s rows=%d src=%s sha256=%s\n" % (sid, n, path, src_sha))
    sys.stderr.write("pool_build: styles=%d rows=%d out=%s sha256=%s\n"
                     % (len(receipt), len(out_lines) - 1, a.out, out_sha))
    ml, mr = median_pure(lsb_all), median_pure(rsb_all)
    if ml is not None:
        sys.stderr.write("pool_build: global median lsb=%s rsb=%s (informational)\n" % (repr(ml), repr(mr)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
