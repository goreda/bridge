"""Paired per-glyph delta, distinct shapes, family-level percentile bootstrap (protocol section 4)."""
import hashlib
import numpy as np


def shape_key(outline):
    """Translation-invariant shape hash of an outline given as rings of [x, y] points
    (cubic control points included, in order). Same shape moved elsewhere gives the same key."""
    pts = [p for ring in outline for p in ring]
    if not pts:
        return 'empty'
    mx = min(p[0] for p in pts); my = min(p[1] for p in pts)
    norm = [[(round(p[0] - mx, 9), round(p[1] - my, 9)) for p in ring] for ring in outline]
    return hashlib.sha256(repr(norm).encode()).hexdigest()


def improvement(base, lever, direction):
    """Positive = lever better than base, oriented by the preregistered direction."""
    return lever - base if direction == 'higher_better' else base - lever


def dedupe_shapes(rows):
    """One row per distinct shape (first seen, input order). Returns (rows, effective_count)."""
    seen = {}
    for r in rows:
        k = r.get('shape_key') or r['item_id']
        if k not in seen:
            seen[k] = r
    return list(seen.values()), len(seen)


def bootstrap_interval(values, level, resamples, seed, stat=np.median):
    """Percentile bootstrap over the unit values. Returns (lo, hi, point). Needs len>=2."""
    v = np.asarray(values, dtype=float)
    if v.size < 2:
        raise ValueError('bootstrap needs at least 2 units')
    rng = np.random.default_rng(seed)
    idx = rng.integers(0, v.size, size=(resamples, v.size))
    s = stat(v[idx], axis=1)
    a = (1 - level) / 2
    return float(np.quantile(s, a)), float(np.quantile(s, 1 - a)), float(stat(v))


def seed_stable(values, level, resamples, seeds, precision):
    """Interval endpoints must move less than `precision` between seeds (protocol section 4)."""
    ends = [bootstrap_interval(values, level, resamples, s)[:2] for s in seeds]
    lo = [e[0] for e in ends]; hi = [e[1] for e in ends]
    return (max(lo) - min(lo) < precision) and (max(hi) - min(hi) < precision), ends


def family_values(deltas_by_family):
    """Within-family dependence: one value per family = median of its paired differences."""
    return {f: float(np.median(d)) for f, d in deltas_by_family.items() if len(d)}
