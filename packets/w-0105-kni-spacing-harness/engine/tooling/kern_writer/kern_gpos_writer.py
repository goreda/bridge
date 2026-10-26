"""Kern GPOS PairPos writer (x-advance only), built directly with fontTools tables.

r2, bound to docs/design/gpos-binding-contract.md (commit 55b67918, PROPOSED contract).
Writes exactly one GPOS table (one kern feature under DFLT/dflt, one PairPos lookup,
x advance only, ValueFormat2 = 0) and copies every other table byte for byte. It does
not run the lossy feature-file class compiler.

Input: original font bytes and decided pair rows {left, right, requested, written (int|null),
status, reason, evidence_class (parsed|derived|declared)}. A row without a known evidence
class is rejected. A row with an integer `written` is stored (an explicit zero stays a zero
pair). written=null is not bound and needs a reason. Nothing is clamped, saturated or
wrapped: `written` is the final integer.
The font's existing kern pairs (kern-only GPOS, explicit zeros included) are read first and are
part of the effective table; a row that differs from an existing pair is a conflict, never an
override. A GPOS with anything other than one kern feature is refused (it would be lost).

Format 1 holds every pair that is not reproduced by a class. Format 2 comes only from an
explicit caller class table: for every glyph pair the class value must equal the effective
value; a listed pair that deviates (including an explicit zero) goes into a Format 1 subtable
placed before the class subtable (first match wins); an UNLISTED pair that a class would
change is a typed error. Offset16 overflow splits Format 1 into more subtables; if the lookup
still does not fit, fontTools writes an extension lookup. The written font is re-read and the
effective value of every glyph pair must equal the planned one.

Errors are WriterError with a stable code. Everything is deterministic.
Pins: fonttools 4.65.0 (see gposcheck requirements).
"""
import hashlib
import io
import json
import sys

from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables.DefaultTable import DefaultTable

# OpenType binary-format constants (layout facts of GPOS PairPos, not design thresholds).
INT16_MIN, INT16_MAX = -(1 << 15), (1 << 15) - 1
OFFSET16_MAX = (1 << 16) - 1                    # largest Offset16 / uint16 count
VALUE_FORMAT_X_ADVANCE = 0x0004                  # ValueFormat1: XAdvance only
VALUE_FORMAT_NONE = 0                            # ValueFormat2
REQ_FEATURE_NONE = 0xFFFF                        # LangSys.ReqFeatureIndex: none
PAIRPOS1_FIXED_HEADER = 10                       # format, coverageOff, vf1, vf2, pairSetCount (5 x uint16)
OFFSET16_BYTES = 2                               # one Offset16 per pair set in the header
PAIRSET_COUNT_BYTES = 2                          # PairSet.pairValueCount
PAIRVALUE_RECORD_BYTES = 4                       # secondGlyph uint16 + one int16 XAdvance
GPOS_VERSION_1_0 = 0x00010000
EXIT_OK, EXIT_WRITER_ERROR, EXIT_INPUT_ERROR = 0, 1, 2     # process exit codes
LOOKUP_TYPE_PAIR_ADJUSTMENT = 2                   # GPOS lookup type 2
LOOKUP_TYPE_EXTENSION = 9                         # GPOS lookup type 9 (extension)
PAIRPOS_FORMAT_GLYPHS = 1                         # PairPosFormat1: glyph pairs
PAIRPOS_FORMAT_CLASSES = 2                        # PairPosFormat2: class pairs


class WriterError(Exception):
    def __init__(self, code, detail=""):
        super().__init__("%s: %s" % (code, detail))
        self.code = code
        self.detail = detail


def _is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


EVIDENCE = ("parsed", "derived", "declared")


def parse_declared(rows, glyph_order):
    """Validate rows; return {(left, right): written} for stored pairs, in a stable order."""
    if not isinstance(rows, list):
        raise WriterError("declared_not_a_list")
    known = set(glyph_order)
    stored, seen = {}, set()
    for r in rows:
        if not isinstance(r, dict):
            raise WriterError("declared_row_not_object")
        for k in ("left", "right", "requested", "written", "status", "reason"):
            if k not in r:
                raise WriterError("declared_key_missing", "%s in %r" % (k, r))
        if r.get("evidence_class") not in EVIDENCE:
            raise WriterError("evidence_class_missing_or_unknown", repr(r.get("evidence_class")))
        q = r["requested"]
        if isinstance(q, bool) or not isinstance(q, (int, float)) or q != q or q in (float("inf"), float("-inf")):
            raise WriterError("requested_not_finite", "%s,%s %r" % (r["left"], r["right"], q))
        l, rt, w = r["left"], r["right"], r["written"]
        if not isinstance(l, str) or not isinstance(rt, str):
            raise WriterError("glyph_name_not_string", repr(r))
        if l not in known or rt not in known:
            raise WriterError("glyph_not_in_font", "%s,%s" % (l, rt))
        if (l, rt) in seen:
            raise WriterError("duplicate_pair", "%s,%s" % (l, rt))
        seen.add((l, rt))
        if w is None:
            if not r["reason"]:
                raise WriterError("rejected_without_reason", "%s,%s" % (l, rt))
            continue
        if not _is_int(w):
            raise WriterError("written_not_integer", "%s,%s %r" % (l, rt, w))
        if not (INT16_MIN <= w <= INT16_MAX):
            raise WriterError("written_out_of_int16", "%s,%s %d" % (l, rt, w))
        stored[(l, rt)] = w
    return stored


def _value(v):
    vr = ot.ValueRecord()
    vr.XAdvance = v
    return vr


def _f1_subtable(lefts, by_left, gid):
    st = ot.PairPos()
    st.Format = PAIRPOS_FORMAT_GLYPHS
    st.ValueFormat1 = VALUE_FORMAT_X_ADVANCE
    st.ValueFormat2 = VALUE_FORMAT_NONE
    cov = ot.Coverage()
    cov.glyphs = list(lefts)
    st.Coverage = cov
    st.PairSet = []
    for l in lefts:
        ps = ot.PairSet()
        ps.PairValueRecord = []
        for _, r, v in sorted(by_left[l]):
            pv = ot.PairValueRecord()
            pv.SecondGlyph = r
            pv.Value1 = _value(v)
            pv.Value2 = None
            ps.PairValueRecord.append(pv)
        ps.PairValueCount = len(ps.PairValueRecord)
        st.PairSet.append(ps)
    st.PairSetCount = len(st.PairSet)
    return st


def _format1_subtables(pairs, gid):
    """Format 1 subtables in glyph id order; a new subtable starts before any Offset16 would
    exceed 65535. Size terms are the binary layout: header 10 + 2n, pair sets 2 + 4k, coverage 4 + 2n."""
    by_left = {}
    for (l, r), v in pairs.items():
        by_left.setdefault(l, []).append((gid[r], r, v))
    lefts = sorted(by_left, key=lambda n: gid[n])
    out, cur, used = [], [], 0
    for l in lefts:
        sz = PAIRSET_COUNT_BYTES + PAIRVALUE_RECORD_BYTES * len(by_left[l])
        n = len(cur) + 1
        if cur and (PAIRPOS1_FIXED_HEADER + OFFSET16_BYTES * n + used + sz > OFFSET16_MAX or n > OFFSET16_MAX):
            out.append(_f1_subtable(cur, by_left, gid))
            cur, used = [], 0
            n = 1
        if PAIRPOS1_FIXED_HEADER + OFFSET16_BYTES * n + sz > OFFSET16_MAX:
            raise WriterError("pairset_too_large", l)
        cur.append(l)
        used += sz
    if cur:
        out.append(_f1_subtable(cur, by_left, gid))
    return out


def _check_classes(classes, glyph_order):
    """classes = {"left": {glyph: class>=1}, "right": {glyph: class>=1}, "matrix": [[int]]}.
    matrix[i][j] is the value for left class i and right class j; row/column 0 is the
    'no class' class and must be all zero."""
    gset = set(glyph_order)
    try:
        lc, rc, mx = classes["left"], classes["right"], classes["matrix"]
    except (TypeError, KeyError):
        raise WriterError("classes_malformed")
    n1 = 1 + max(lc.values(), default=0)
    n2 = 1 + max(rc.values(), default=0)
    for d in (lc, rc):
        for g, c in d.items():
            if g not in gset:
                raise WriterError("class_glyph_not_in_font", g)
            if not _is_int(c) or c < 1:
                raise WriterError("class_index_invalid", "%s %r" % (g, c))
    if len(mx) != n1 or any(len(row) != n2 for row in mx):
        raise WriterError("class_matrix_shape", "need %dx%d" % (n1, n2))
    for i in range(n1):
        for j in range(n2):
            v = mx[i][j]
            if not _is_int(v) or not (INT16_MIN <= v <= INT16_MAX):
                raise WriterError("class_matrix_value", "%d,%d %r" % (i, j, v))
            if (i == 0 or j == 0) and v != 0:
                raise WriterError("class_zero_row_or_column_nonzero", "%d,%d" % (i, j))
    return lc, rc, mx, n1, n2


def _format2_subtable(lc, rc, mx, n1, n2, gid):
    st = ot.PairPos()
    st.Format = PAIRPOS_FORMAT_CLASSES
    st.ValueFormat1 = VALUE_FORMAT_X_ADVANCE
    st.ValueFormat2 = VALUE_FORMAT_NONE
    cov = ot.Coverage()
    cov.glyphs = sorted(lc, key=lambda n: gid[n])
    st.Coverage = cov
    for attr, d in (("ClassDef1", lc), ("ClassDef2", rc)):
        cd = ot.ClassDef()
        cd.classDefs = dict(d)
        setattr(st, attr, cd)
    st.Class1Count, st.Class2Count = n1, n2
    st.Class1Record = []
    for i in range(n1):
        c1 = ot.Class1Record()
        c1.Class2Record = []
        for j in range(n2):
            c2 = ot.Class2Record()
            c2.Value1 = _value(mx[i][j])
            c2.Value2 = None
            c1.Class2Record.append(c2)
        st.Class1Record.append(c1)
    return st


def plan_subtables(effective, listed, order, classes):
    """effective: {(l,r): int} every pair the table must give (existing + new, explicit zeros included).
    listed: set of pairs that are explicitly listed (exact). Returns the subtable list."""
    gid = {n: i for i, n in enumerate(order)}
    if classes is None:
        return _format1_subtables(effective, gid)
    lc, rc, mx, n1, n2 = _check_classes(classes, order)
    exceptions = {}
    for a in order:
        ca = lc.get(a, 0)
        for b in order:
            got = mx[ca][rc.get(b, 0)]
            want = effective.get((a, b), 0)
            if got == want:
                continue
            if (a, b) in listed:
                exceptions[(a, b)] = want
            else:
                raise WriterError("class_changes_unlisted_pair", "%s,%s class=%d effective=%d" % (a, b, got, want))
    subs = _format1_subtables(exceptions, gid) if exceptions else []
    return subs + [_format2_subtable(lc, rc, mx, n1, n2, gid)]


def build_gpos(font, subtables):
    lk = ot.Lookup()
    lk.LookupType = LOOKUP_TYPE_PAIR_ADJUSTMENT
    lk.LookupFlag = 0
    lk.SubTable = subtables
    lk.SubTableCount = len(subtables)
    ll = ot.LookupList()
    ll.Lookup = [lk]
    ll.LookupCount = 1
    fr = ot.FeatureRecord()
    fr.FeatureTag = "kern"
    fr.Feature = ot.Feature()
    fr.Feature.FeatureParams = None
    fr.Feature.LookupListIndex = [0]
    fr.Feature.LookupCount = 1
    fl = ot.FeatureList()
    fl.FeatureRecord = [fr]
    fl.FeatureCount = 1
    ls = ot.LangSys()
    ls.LookupOrder = None
    ls.ReqFeatureIndex = REQ_FEATURE_NONE
    ls.FeatureIndex = [0]
    ls.FeatureCount = 1
    sc = ot.Script()
    sc.DefaultLangSys = ls
    sc.LangSysRecord = []
    sc.LangSysCount = 0
    sr = ot.ScriptRecord()
    sr.ScriptTag = "DFLT"
    sr.Script = sc
    sl = ot.ScriptList()
    sl.ScriptRecord = [sr]
    sl.ScriptCount = 1
    g = ot.GPOS()
    g.Version = GPOS_VERSION_1_0
    g.ScriptList, g.FeatureList, g.LookupList = sl, fl, ll
    tbl = newTable("GPOS")
    tbl.table = g
    return tbl.compile(font)


def _kern_subtables(gpos_table):
    """Subtables of the kern lookups, in lookup then subtable order. Refuses a GPOS that holds
    anything besides one kern feature (replacing it would drop data)."""
    t = gpos_table.table
    feats = t.FeatureList.FeatureRecord if t.FeatureList else []
    if len(feats) != 1 or feats[0].FeatureTag != "kern":
        raise WriterError("original_gpos_not_kern_only", "features=%s" % [f.FeatureTag for f in feats])
    idx = feats[0].Feature.LookupListIndex
    lks = t.LookupList.Lookup if t.LookupList else []
    if len(lks) != len(idx):
        raise WriterError("original_gpos_has_other_lookups")
    out = []
    for i in idx:
        lk = lks[i]
        for st in lk.SubTable:
            if lk.LookupType == LOOKUP_TYPE_EXTENSION:
                st = st.ExtSubTable
            if lk.LookupType not in (LOOKUP_TYPE_PAIR_ADJUSTMENT, LOOKUP_TYPE_EXTENSION):
                raise WriterError("original_gpos_other_lookup_type", str(lk.LookupType))
            out.append(st)
    return out


def _lookup_value(subtables, a, b):
    """Effective x advance of pair (a,b): first subtable whose coverage holds `a` and that has a record wins."""
    for st in subtables:
        if a not in st.Coverage.glyphs:
            continue
        if st.Format == PAIRPOS_FORMAT_GLYPHS:
            ps = st.PairSet[st.Coverage.glyphs.index(a)]
            for pv in ps.PairValueRecord:
                if pv.SecondGlyph == b:
                    return getattr(pv.Value1, "XAdvance", 0) if pv.Value1 else 0
        elif st.Format == PAIRPOS_FORMAT_CLASSES:
            c1 = st.ClassDef1.classDefs.get(a, 0)
            c2 = st.ClassDef2.classDefs.get(b, 0)
            v = st.Class1Record[c1].Class2Record[c2].Value1
            return getattr(v, "XAdvance", 0) if v else 0
        else:
            raise WriterError("unsupported_pairpos_format", str(st.Format))
    return 0


def existing_pairs(font, order):
    """Listed pairs of an existing kern-only GPOS: Format 1 records (explicit zeros kept) and
    nonzero Format 2 cells, as effective values (first matching subtable wins)."""
    if "GPOS" not in font:
        return {}
    subs = _kern_subtables(font["GPOS"])
    seen = {}
    for st in subs:
        if st.Format == PAIRPOS_FORMAT_GLYPHS:
            for l, ps in zip(st.Coverage.glyphs, st.PairSet):
                for pv in ps.PairValueRecord:
                    seen.setdefault((l, pv.SecondGlyph), None)
        elif st.Format == PAIRPOS_FORMAT_CLASSES:
            for a in st.Coverage.glyphs:
                for b in order:
                    if _lookup_value([st], a, b) != 0:
                        seen.setdefault((a, b), None)
    return {k: _lookup_value(subs, *k) for k in seen}


def write_kern(original, declared, classes=None):
    """Return (output_font_bytes, receipt dict). Only the GPOS table is replaced or added."""
    try:
        font = TTFont(io.BytesIO(original), recalcTimestamp=False, recalcBBoxes=False)
        tags = set(font.keys())
    except Exception as e:  # fontTools raises many types on damaged input
        raise WriterError("original_parse_failure", repr(e))
    if "kern" in tags:
        raise WriterError("original_has_legacy_kern")
    order = font.getGlyphOrder()
    if len(set(order)) != len(order):
        raise WriterError("glyph_order_not_unique")
    existing = existing_pairs(font, order)
    stored = parse_declared(declared, order)
    effective, counts = dict(existing), {"existing": len(existing), "new": 0, "same_as_existing": 0}
    for k, v in stored.items():
        if k in existing:
            if existing[k] != v:
                raise WriterError("conflicting_pair", "%s,%s existing=%d row=%d" % (k[0], k[1], existing[k], v))
            counts["same_as_existing"] += 1
        else:
            counts["new"] += 1
        effective[k] = v
    if not effective:
        raise WriterError("no_pairs_to_store")
    listed = set(effective)
    subs = plan_subtables(effective, listed, order, classes)
    data = build_gpos(font, subs)
    raw = TTFont(io.BytesIO(original), lazy=True, recalcTimestamp=False, recalcBBoxes=False)
    t = DefaultTable("GPOS")
    t.data = data
    raw["GPOS"] = t
    buf = io.BytesIO()
    raw.save(buf)
    out = buf.getvalue()
    # re-read: every glyph pair must give the planned effective value
    back = TTFont(io.BytesIO(out))
    back_subs = _kern_subtables(back["GPOS"])
    bad = []
    for a in order:
        for b in order:
            if _lookup_value(back_subs, a, b) != effective.get((a, b), 0):
                bad.append("%s,%s" % (a, b))
    if bad:
        raise WriterError("readback_mismatch", "%d pairs, first %s" % (len(bad), bad[0]))
    rejected = [(d["left"], d["right"], d["reason"]) for d in declared if d["written"] is None]
    rounded = [(d["left"], d["right"]) for d in declared
               if d["written"] is not None and float(d["written"]) != float(d["requested"])]
    receipt = {
        "writer": "kern_gpos_writer.r2", "contract": "docs/design/gpos-binding-contract.md@55b67918",
        "original_sha256": hashlib.sha256(original).hexdigest(), "output_sha256": hashlib.sha256(out).hexdigest(),
        "gpos_sha256": hashlib.sha256(data).hexdigest(), "gpos_bytes": len(data),
        "pairs_written": counts["new"], "pairs_existing": counts["existing"],
        "pairs_same_as_existing": counts["same_as_existing"],
        "rounded": len(rounded), "rejected": len(rejected),
        "rejections": [{"left": l, "right": r, "reason": why} for l, r, why in rejected],
        "subtables": len(subs), "formats": sorted({s.Format for s in subs}),
        "classes": classes is not None, "tables_other_than_gpos": "byte-equal by construction, verify with gposcheck",
    }
    return out, receipt


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True)
    ap.add_argument("--declared", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--receipt", required=True)
    ap.add_argument("--classes", help="JSON {left:{g:c},right:{g:c},matrix:[[..]]} for Format 2")
    a = ap.parse_args(argv)
    try:
        orig = open(a.original, "rb").read()
        decl = json.load(open(a.declared))
        cls = json.load(open(a.classes)) if a.classes else None
        out, rec = write_kern(orig, decl, cls)
    except WriterError as e:
        sys.stderr.write("error %s\n" % e)
        return EXIT_WRITER_ERROR
    except (OSError, ValueError) as e:
        sys.stderr.write("error input_unusable: %s\n" % e)
        return EXIT_INPUT_ERROR
    try:
        with open(a.output, "xb") as f:
            f.write(out)
        with open(a.receipt, "x") as f:
            json.dump(rec, f, indent=1, sort_keys=True)
    except OSError as e:
        sys.stderr.write("error output_not_written: %s\n" % e)
        return EXIT_INPUT_ERROR
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
