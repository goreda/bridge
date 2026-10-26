#!/usr/bin/env python3
"""outline_metrics.py - C1 metric harness (fake-line hunt side product).

Computes per-glyph and per-style outline metrics from a stage1-cache.txt
(the artifact BOTH base and patched code write byte-identically, so this
harness measures any build's output without engine changes):

  cubic%   cubic spans / total spans (shipped rings)
  node     node (span) count
  corner   joints whose tangent-angle delta lands in the upper Otsu class
  g1brk    joints above the grid-derived measurability floor but below the
           corner split (tangent discontinuity the eye can resolve)

No invented thresholds:
  * measurability floor per joint = atan(EXPORT_RESOLUTION/2 / L_in) +
    atan(EXPORT_RESOLUTION/2 / L_out), EXPORT_RESOLUTION = 1 unit (the
    engine's own fixed export grid, generated_native::EXPORT_RESOLUTION);
    the smallest tangent angle the integer grid can resolve given the two
    adjacent span lengths.
  * corner split = Otsu threshold over all joint deltas of the run
    (data-derived per style, no constant). Degenerate single-value runs
    (e.g. Paul New's uniform 90-degree joints) fall back to: all
    above-floor joints are corners, zero G1 breaks.

Usage:
  outline_metrics.py CACHE [--audit LINE_AUDIT_TSV] [--glyphs] [--json]
Exit 2 on malformed input. Never fabricates: missing data prints 'na'.
"""
import math, struct, sys, json

EXPORT_RESOLUTION = 1.0  # engine constant: generated_native.rs EXPORT_RESOLUTION


def bits(h):
    return struct.unpack('>d', struct.pack('>Q', int(h, 16)))[0]


def parse_cache(path):
    """stage1-cache.txt -> [(glyph, cp, rings)], rings = [(start, spans)]."""
    glyphs = []
    cur = None
    ring = None
    skip = 0  # receipt_lines N -> the next N lines are receipt text, not cache rows
    with open(path, 'r', errors='replace') as fh:
        for line in fh:
            if skip > 0:
                skip -= 1
                continue
            f = line.rstrip('\n').split('\t')
            if f[0] == 'receipt_lines':
                skip = int(f[1])
            elif f[0] == 'glyph':
                cur = {'name': f[1], 'cp': f[3], 'rings': []}
                glyphs.append(cur)
            elif f[0] == 'ring' and cur is not None:
                ring = {'start': (bits(f[1]), bits(f[2])), 'spans': []}
                cur['rings'].append(ring)
            elif f[0] == 'L' and ring is not None:
                ring['spans'].append(('L', (bits(f[1]), bits(f[2]))))
            elif f[0] == 'C' and ring is not None:
                ring['spans'].append(('C', tuple(bits(x) for x in f[1:7])))
            elif f[0] == 'end':
                cur = None
                ring = None
    return glyphs


def span_end(sp):
    return sp[1] if sp[0] == 'L' else sp[1][4:6]


def joint_deltas(rings):
    """tangent-angle delta (degrees) at every joint of every ring."""
    deltas = []
    for ring in rings:
        pts = [ring['start']] + [span_end(sp) for sp in ring['spans']]
        for i, sp in enumerate(ring['spans']):
            a = pts[i]
            b = span_end(sp)
            # incoming tangent of span i at its end
            tin = (b[0] - (sp[1][2] if sp[0] == 'C' else a[0]),
                   b[1] - (sp[1][3] if sp[0] == 'C' else a[1]))
            nxt = ring['spans'][(i + 1) % len(ring['spans'])]
            # outgoing tangent of next span at its start (= b)
            if nxt[0] == 'C':
                tout = (nxt[1][0] - b[0], nxt[1][1] - b[1])
            else:
                e = span_end(nxt)
                tout = (e[0] - b[0], e[1] - b[1])
            lin = math.hypot(*tin)
            lout = math.hypot(*tout)
            if lin == 0.0 or lout == 0.0:
                continue
            cos = max(-1.0, min(1.0, (tin[0] * tout[0] + tin[1] * tout[1]) / (lin * lout)))
            delta = math.degrees(math.acos(cos))
            floor = math.degrees(math.atan((EXPORT_RESOLUTION / 2.0) / lin) +
                                 math.atan((EXPORT_RESOLUTION / 2.0) / lout))
            deltas.append((delta, floor))
    return deltas


def otsu_split(values):
    """Otsu threshold over 1-degree bins; None when a single distinct value."""
    if not values:
        return None
    lo, hi = min(values), max(values)
    if hi - lo < 1e-9:
        return None
    nb = max(2, min(180, int(hi - lo) + 1))
    hist = [0] * nb
    for v in values:
        hist[min(nb - 1, int((v - lo)))] += 1
    total = len(values)
    sum_all = sum(i * h for i, h in enumerate(hist))
    w0 = 0
    sum0 = 0
    best = -1.0
    best_t = None
    for t in range(nb):
        w0 += hist[t]
        sum0 += t * hist[t]
        if w0 == 0 or w0 == total:
            continue
        m0 = sum0 / w0
        m1 = (sum_all - sum0) / (total - w0)
        var = w0 * (total - w0) * (m0 - m1) ** 2
        if var > best:
            best = var
            best_t = t
    return None if best_t is None else lo + best_t + 0.5


def glyph_metrics(glyphs):
    """per-glyph rows + run-level joint deltas for the style split."""
    rows = []
    all_deltas = []
    for g in glyphs:
        spans = sum(len(r['spans']) for r in g['rings'])
        cubics = sum(1 for r in g['rings'] for sp in r['spans'] if sp[0] == 'C')
        deltas = joint_deltas(g['rings'])
        all_deltas.extend(deltas)
        rows.append({'glyph': g['name'], 'cp': g['cp'], 'spans': spans,
                     'cubics': cubics, 'nodes': spans, 'deltas': deltas})
    return rows, all_deltas


def split_corners(deltas, corner_split):
    corners = g1 = 0
    for d, fl in deltas:
        if d <= fl:
            continue
        if corner_split is None or d >= corner_split:
            corners += 1
        else:
            g1 += 1
    return corners, g1


def parse_audit(path):
    """line-audit.tsv -> (total_line_spans, suspicious, per_glyph_counts)."""
    total = susp = 0
    per_glyph = {}
    with open(path, 'r', errors='replace') as fh:
        for line in fh:
            if not line or line[0] == '#' or line.startswith('glyph\t'):
                continue
            f = line.rstrip('\n').split('\t')
            if len(f) < 14:
                continue
            total += 1
            s = f[12] == '1'
            susp += s
            t, c = per_glyph.get(f[0], (0, 0))
            per_glyph[f[0]] = (t + 1, c + s)
    return total, susp, per_glyph


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cache = argv[1]
    audit = None
    show_glyphs = '--glyphs' in argv
    as_json = '--json' in argv
    if '--audit' in argv:
        audit = argv[argv.index('--audit') + 1]
    glyphs = parse_cache(cache)
    if not glyphs:
        print('no glyphs parsed from', cache, file=sys.stderr)
        return 2
    rows, deltas = glyph_metrics(glyphs)
    split = otsu_split([d for d, _ in deltas])
    audit_tot = audit_susp = None
    per_glyph_audit = {}
    if audit:
        audit_tot, audit_susp, per_glyph_audit = parse_audit(audit)
    out_rows = []
    tot = {'spans': 0, 'cubics': 0, 'corners': 0, 'g1': 0, 'lines': 0, 'susp': 0}
    for r in rows:
        corners, g1 = split_corners(r['deltas'], split)
        la, ls = per_glyph_audit.get(r['glyph'], (0, 0))
        row = {'glyph': r['glyph'], 'spans': r['spans'], 'cubics': r['cubics'],
               'cubic_pct': (100.0 * r['cubics'] / r['spans']) if r['spans'] else None,
               'nodes': r['nodes'], 'corners': corners, 'g1_breaks': g1,
               'line_spans': la if audit else None, 'suspicious_lines': ls if audit else None}
        out_rows.append(row)
        tot['spans'] += r['spans']
        tot['cubics'] += r['cubics']
        tot['corners'] += corners
        tot['g1'] += g1
        tot['lines'] += la
        tot['susp'] += ls
    style = {'glyphs': len(rows), 'spans': tot['spans'], 'cubics': tot['cubics'],
             'cubic_pct': (100.0 * tot['cubics'] / tot['spans']) if tot['spans'] else None,
             'nodes': tot['spans'], 'corners': tot['corners'], 'g1_breaks': tot['g1'],
             'corner_split_deg': split,
             'line_spans': audit_tot, 'suspicious_lines': audit_susp}
    if as_json:
        print(json.dumps({'style': style, 'glyphs': out_rows if show_glyphs else None}, indent=1))
        return 0
    pct = lambda v: 'na' if v is None else f'{v:.2f}'
    num = lambda v: 'na' if v is None else str(v)
    print(f"style: glyphs={style['glyphs']} spans={style['spans']} cubic%={pct(style['cubic_pct'])} "
          f"nodes={style['nodes']} corners={style['corners']} g1_breaks={style['g1_breaks']} "
          f"corner_split_deg={pct(style['corner_split_deg'])} "
          f"line_spans={num(style['line_spans'])} suspicious_lines={num(style['suspicious_lines'])}")
    if show_glyphs:
        print('glyph\tspans\tcubics\tcubic_pct\tnodes\tcorners\tg1_breaks\tline_spans\tsuspicious_lines')
        for r in out_rows:
            print(f"{r['glyph']}\t{r['spans']}\t{r['cubics']}\t{pct(r['cubic_pct'])}\t{r['nodes']}"
                  f"\t{r['corners']}\t{r['g1_breaks']}\t{num(r['line_spans'])}\t{num(r['suspicious_lines'])}")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
