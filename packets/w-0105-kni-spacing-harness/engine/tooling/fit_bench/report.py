#!/usr/bin/env python3
"""fit_bench before/after report (parallel-fitting program, piece 18; W13).

Reads raw fit_bench_v1 TSVs from two result dirs (before/ after), pairs them
by label, and renders the comparison table the program is judged on:
fitting s/glyph, pairs wall, total wall - before, after, speedup - per style.
Phase names are looked up in the recorded rows, never assumed: a phase that
is absent from a TSV reports MISSING, not zero.

Quality domain (W13): when a TSV carries `quality` rows, the table also
compares the shipped-domain fit quality - total node count and the
exact-coverage area deviation per ink pixel (font units^2 / ink px). A TSV
without quality rows (pre-W13 recorder) reports MISSING, never zero.

Usage: report.py <before-dir> <after-dir> [--tsv]
Stdlib only; reads files, writes stdout only.
"""
import os, sys

REQUIRED_PHASES = ("fitting", "pairs")


def parse_tsv(path):
    phases, glyphs, quality, meta = {}, [], [], {}
    with open(path, encoding="utf-8") as f:
        header = f.readline().strip()
        if header != "fit_bench_v1":
            raise ValueError(f"{path}: bad header {header!r}")
        for line in f:
            cells = line.rstrip("\n").split("\t")
            if not cells or cells[0] == "":
                continue
            kind = cells[0]
            if kind == "phase" and len(cells) == 3:
                phases[cells[1]] = float(cells[2])
            elif kind == "glyph" and len(cells) == 3:
                glyphs.append((cells[1], float(cells[2])))
            elif kind == "quality" and len(cells) == 9:
                quality.append({
                    "name": cells[1], "domain": cells[2],
                    "rings": int(cells[3]), "nodes": int(cells[4]),
                    "fallback_line_spans": int(cells[5]),
                    "final_missing_extrema": int(cells[6]),
                    "ink_px": int(cells[7]), "area_err_units2": float(cells[8]),
                })
            elif len(cells) == 2:
                meta[kind] = cells[1]
    return {"phases": phases, "glyphs": glyphs, "quality": quality, "meta": meta}


def parse_meta(path):
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            cells = line.rstrip("\n").split("\t")
            if len(cells) == 2:
                out[cells[0]] = cells[1]
    return out


def load_dir(d):
    runs = {}
    for name in sorted(os.listdir(d)):
        if name.endswith(".tsv"):
            label = name[:-4]
            runs[label] = {
                "tsv": parse_tsv(os.path.join(d, name)),
                "meta": parse_meta(os.path.join(d, label + ".meta")),
            }
    return runs


def shipped_quality(tsv):
    """Quality rows of the shipped domain only; the measurement domain is
    engine-internal context, not the delivered outline."""
    return [q for q in tsv["quality"] if q["domain"] == "shipped"]


def metric(run, what):
    """(value, unit) for a required metric, or None -> MISSING."""
    tsv = run["tsv"]
    n = len(tsv["glyphs"])
    if what == "fitting_s_per_glyph":
        if "fitting" not in tsv["phases"] or n == 0:
            return None
        return tsv["phases"]["fitting"] / n
    if what == "pairs_s":
        return tsv["phases"].get("pairs")
    if what == "total_s":
        v = tsv["meta"].get("total_s")
        return float(v) if v is not None else None
    if what == "quality_nodes":
        q = shipped_quality(tsv)
        return sum(r["nodes"] for r in q) if q else None
    if what == "quality_err_per_inkpx":
        q = shipped_quality(tsv)
        if not q:
            return None
        ink = sum(r["ink_px"] for r in q)
        if ink == 0:
            return None
        return sum(r["area_err_units2"] for r in q) / ink
    raise ValueError(what)


def fmt(v, digits=3):
    return "MISSING" if v is None else f"{v:.{digits}f}"


def speedup(before, after):
    if before is None or after is None or after == 0:
        return "n/a"
    return f"{before / after:.2f}x"


def build_rows(before_runs, after_runs):
    labels = sorted(set(before_runs) | set(after_runs))
    rows = []
    for label in labels:
        b, a = before_runs.get(label), after_runs.get(label)
        row = {"label": label}
        row["style"] = (b or a)["meta"].get("style_id", label)
        row["glyphs"] = str(len((b or a)["tsv"]["glyphs"]))
        row["sha_before"] = (b or {}).get("meta", {}).get("engine_git_sha", "-")[:8]
        row["sha_after"] = (a or {}).get("meta", {}).get("engine_git_sha", "-")[:8]
        for what, key in (("fitting_s_per_glyph", "fit"), ("pairs_s", "pairs"), ("total_s", "total"),
                          ("quality_nodes", "nodes"), ("quality_err_per_inkpx", "err")):
            vb = metric(b, what) if b else None
            va = metric(a, what) if a else None
            row[f"{key}_before"], row[f"{key}_after"], row[f"{key}_x"] = vb, va, speedup(vb, va)
        rows.append(row)
    return rows


def render_markdown(rows):
    out = ["| style | glyphs | fitting s/glyph before | after | speedup | pairs s before | after | speedup | total s before | after | speedup | nodes before | after | reduction | area err/inkpx before | after | reduction |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        out.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            r["style"], r["glyphs"],
            fmt(r["fit_before"], 4), fmt(r["fit_after"], 4), r["fit_x"],
            fmt(r["pairs_before"]), fmt(r["pairs_after"]), r["pairs_x"],
            fmt(r["total_before"]), fmt(r["total_after"]), r["total_x"],
            fmt(r["nodes_before"], 0), fmt(r["nodes_after"], 0), r["nodes_x"],
            fmt(r["err_before"], 6), fmt(r["err_after"], 6), r["err_x"]))
    return "\n".join(out) + "\n"


def render_tsv(rows):
    cols = ["label", "style", "glyphs", "sha_before", "sha_after",
            "fit_before", "fit_after", "fit_x",
            "pairs_before", "pairs_after", "pairs_x",
            "total_before", "total_after", "total_x",
            "nodes_before", "nodes_after", "nodes_x",
            "err_before", "err_after", "err_x"]
    out = ["\t".join(cols)]
    for r in rows:
        line = []
        for c in cols:
            v = r.get(c)
            line.append("MISSING" if v is None else (f"{v:.6f}" if isinstance(v, float) else str(v)))
        out.append("\t".join(line))
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    before, after = load_dir(argv[1]), load_dir(argv[2])
    if not before:
        sys.stderr.write(f"report: no TSVs in before dir {argv[1]}\n")
        return 2
    rows = build_rows(before, after)
    sys.stdout.write(render_tsv(rows) if "--tsv" in argv[3:] else render_markdown(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
