"""Verifier core. Every number in the receipt is computed here from the font bytes."""
import hashlib
import io
import struct
import platform
from dataclasses import dataclass
from typing import Optional

RECEIPT_VERSION = "gposcheck-receipt-v2"
VALUE_FIELDS = ("XPlacement", "YPlacement", "XAdvance", "YAdvance")
# CONVENTION (no theory behind the number): all-pairs enumeration costs n^2 pair lookups in pure
# Python; 600 glyphs is 360,000 lookups, a few seconds. Above the limit the check does not
# silently narrow its scope: it reports the typed finding "not_enumerated" and fails, unless the
# caller raises the limit explicitly. The limit in force is printed in every receipt.
ENUM_LIMIT_DEFAULT = 600
INT16_MIN, INT16_MAX = -32768, 32767
# Output contract: x advance only (ValueFormat1 exactly 0x0004), second value format 0. Bits 8-15 of a
# ValueFormat are reserved by the OpenType specification and are reported on their own.
OUTPUT_VALUE_FORMAT1 = 0x0004
OUTPUT_VALUE_FORMAT2 = 0x0000
RESERVED_VALUE_FORMAT_BITS = 0xFF00


def _fmt(x):
    """repr that cannot raise: integer to text conversion has a digit limit in newer Python versions."""
    try:
        return repr(x)
    except Exception:
        try:
            return "<integer with %d bits>" % x.bit_length()
        except Exception:
            return "<unprintable %s>" % type(x).__name__


def sha256(b):
    return hashlib.sha256(b).hexdigest()


@dataclass
class Declared:
    """One pair as the writer declares it. requested is the target in font units;
    written is the integer the writer says it stored (None = not written)."""
    left: str
    right: str
    requested: float
    written: Optional[int]
    status: str
    reason: str = ""

    @staticmethod
    def from_dict(d):
        return Declared(d["left"], d["right"], d["requested"], d.get("written"),
                        d["status"], d.get("reason", ""))


def computed_status(d):
    """written | rounded | rejected, or invalid when `written` is not a plain integer (or None).
    An invalid pair is reported as a finding and kept out of every comparison. An unusable
    `requested` does not make a pair invalid: it never equals `written`, so the pair is
    rounded and a declared status of written is a status mismatch."""
    w = d.written
    if w is None:
        return "rejected"
    if isinstance(w, bool) or not isinstance(w, int):
        return "invalid"
    try:
        fw = float(w)
    except OverflowError:
        return "invalid"
    try:
        return "written" if fw == float(d.requested) else "rounded"
    except (TypeError, ValueError, OverflowError):
        return "rounded"


def _unusable_number(x):
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return True
    if isinstance(x, float):
        return x != x or x in (float("inf"), float("-inf"))
    try:
        float(x)
    except OverflowError:
        return True
    return False


def _normalize_declared(declared, findings):
    """Declared pairs as a list of Declared. A malformed container or row is a typed finding and is left out."""
    out = []
    if isinstance(declared, (str, bytes, dict)) or not hasattr(declared, "__iter__"):
        findings.append(("declared_input_unusable", "declared must be a list of pair records, got %s" % type(declared).__name__))
        return out
    for i, d in enumerate(declared):
        if isinstance(d, Declared):
            row = d
        elif isinstance(d, dict):
            try:
                row = Declared.from_dict(d)
            except Exception as e:
                findings.append(("declared_row_unusable", "row %d: %s" % (i, _fmt(e))))
                continue
        else:
            findings.append(("declared_row_unusable", "row %d: expected an object, got %s" % (i, type(d).__name__)))
            continue
        if not isinstance(row.left, str) or not isinstance(row.right, str):
            findings.append(("declared_row_unusable", "row %d: left and right must be strings" % i))
            continue
        out.append(row)
    return out


def _raw_tables(data):
    from fontTools.ttLib import TTFont
    f = TTFont(io.BytesIO(data), lazy=True)
    return f, {t: f.reader[t] for t in f.reader.keys()}


def _mask_head(b):
    return b[:8] + b"\0\0\0\0" + b[12:] if len(b) >= 12 else b


def compare_non_gpos(orig_tables, out_tables, allowed):
    equal, diff = [], []
    for tag in sorted(set(orig_tables) | set(out_tables)):
        if tag == "GPOS":
            continue
        a, b = orig_tables.get(tag), out_tables.get(tag)
        if a is None:
            diff.append((tag, "added", None, sha256(b), 0, len(b)))
        elif b is None:
            diff.append((tag, "removed", sha256(a), None, len(a), 0))
        else:
            same = (_mask_head(a) == _mask_head(b)) if tag == "head" else (a == b)
            if same:
                equal.append((tag, sha256(b)))
            else:
                diff.append((tag, "changed", sha256(a), sha256(b), len(a), len(b)))
    return equal, diff


def _value(v):
    """(xadvance, other_nonzero_field_names) for a ValueRecord or None."""
    if v is None:
        return 0, []
    other = [n for n in VALUE_FIELDS if n != "XAdvance" and getattr(v, n, 0)]
    return getattr(v, "XAdvance", 0) or 0, other


class _Gpos:
    def __init__(self, font):
        self.gid = {n: i for i, n in enumerate(font.getGlyphOrder())}
        self.f1_subtables = self.f1_pairsets = self.f1_records = 0
        self.explicit_zero = set()
        self.findings = []
        self.lookup_types = {}
        self.extension_count = 0
        self.kern_lookup_indexes = []
        self.explicit_pairs = set()
        self.unexpected_fields = 0
        t = font["GPOS"].table
        reach, req_seen = set(), set()
        langsys = []
        for sr in (t.ScriptList.ScriptRecord if t.ScriptList else []):
            langs = [("%s/dflt" % sr.ScriptTag, sr.Script.DefaultLangSys)] if sr.Script.DefaultLangSys else []
            langs += [("%s/%s" % (sr.ScriptTag, lr.LangSysTag), lr.LangSys) for lr in sr.Script.LangSysRecord]
            for label, ls in langs:
                feats_of = set(ls.FeatureIndex)
                if ls.ReqFeatureIndex != 0xFFFF:
                    feats_of.add(ls.ReqFeatureIndex)
                langsys.append((label, feats_of))
                reach.update(ls.FeatureIndex)
                if ls.ReqFeatureIndex != 0xFFFF:
                    reach.add(ls.ReqFeatureIndex)
                    req_seen.add(ls.ReqFeatureIndex)
        feats = t.FeatureList.FeatureRecord if t.FeatureList else []
        lookups = t.LookupList.Lookup if t.LookupList else []
        for x in sorted(req_seen):
            self.findings.append(("req_feature_index_set", "ReqFeatureIndex=%d (a required feature is not the standard layout)" % x))
        for x in sorted(i for i in reach if not 0 <= i < len(feats)):
            self.findings.append(("feature_index_out_of_range", "%d >= FeatureCount %d" % (x, len(feats))))
        kern_idx, kern_feats = set(), 0
        for i, fr in enumerate(feats):
            if fr.FeatureTag == "kern":
                kern_feats += 1
                bad_lk = [x for x in fr.Feature.LookupListIndex if not 0 <= x < len(lookups)]
                for x in bad_lk:
                    self.findings.append(("lookup_index_out_of_range", "kern feature %d lookup %d >= LookupCount %d" % (i, x, len(lookups))))
                if i in reach:
                    kern_idx.update(x for x in fr.Feature.LookupListIndex if 0 <= x < len(lookups))
        if kern_feats and not kern_idx:
            self.findings.append(("kern_feature_unreachable", "kern feature exists but no script reaches it"))
        if not kern_feats:
            self.findings.append(("kern_feature_missing", "no kern feature in GPOS"))
        self.kern_lookup_indexes = sorted(kern_idx)
        self.feature_count = len(feats)
        self.kern_feature_count = kern_feats
        self.lookup_count = len(lookups)
        self.langsys = []
        for label, fset in langsys:
            lks = set()
            for i in fset:
                if 0 <= i < len(feats) and feats[i].FeatureTag == "kern":
                    lks.update(x for x in feats[i].Feature.LookupListIndex if 0 <= x < len(lookups))
            self.langsys.append((label, frozenset(lks)))
        self.lookups = []
        for i in self.kern_lookup_indexes:
            lk = lookups[i]
            if getattr(lk, "LookupFlag", 0) != 0:
                self.findings.append(("lookup_flag_nonstandard", "lookup %d LookupFlag=0x%04x" % (i, lk.LookupFlag)))
            subs = []
            for st in lk.SubTable:
                typ = lk.LookupType
                if typ == 9:
                    self.extension_count += 1
                    typ, st = st.ExtensionLookupType, st.ExtSubTable
                self.lookup_types[typ] = self.lookup_types.get(typ, 0) + 1
                if typ != 2:
                    self.findings.append(("unsupported_lookup_type_in_kern", "lookup %d type %d" % (i, typ)))
                    continue
                subs.append(self._index_subtable(st))
            self.lookups.append(subs)

    def _index_subtable(self, st):
        if st.Format not in (1, 2):
            self.findings.append(("unsupported_pairpos_format", str(st.Format)))
            return ("none", set(), None)
        cov = list(st.Coverage.glyphs)
        gid = self.gid
        covg = [gid.get(g, -1) for g in cov]
        if any(x < 0 for x in covg) or any(b <= a for a, b in zip(covg, covg[1:])):
            self.findings.append(("coverage_unsorted_or_unknown", "first glyph coverage must be unique and in glyph id order"))
        if st.Format == 1:
            self.f1_subtables += 1
            if len(cov) != len(st.PairSet) or getattr(st, "PairSetCount", len(st.PairSet)) != len(st.PairSet):
                self.findings.append(("pairset_count_mismatch", "coverage=%d pairsets=%d declared=%s" % (
                    len(cov), len(st.PairSet), getattr(st, "PairSetCount", "n/a"))))
            pairs = {}
            for g, ps in zip(cov, st.PairSet):
                self.f1_pairsets += 1
                recs = ps.PairValueRecord
                if getattr(ps, "PairValueCount", len(recs)) != len(recs):
                    self.findings.append(("pairvalue_count_mismatch", "%s declared=%s actual=%d" % (
                        g, ps.PairValueCount, len(recs))))
                seq = [gid.get(r.SecondGlyph, -1) for r in recs]
                if any(x < 0 for x in seq):
                    self.findings.append(("pairset_unknown_second_glyph", g))
                for a, b, r in zip(seq, seq[1:], recs[1:]):
                    if b == a:
                        self.findings.append(("pairset_duplicate_second_glyph", "%s,%s" % (g, r.SecondGlyph)))
                    elif b < a:
                        self.findings.append(("pairset_second_glyph_not_ascending", "%s,%s" % (g, r.SecondGlyph)))
                for r in recs:
                    self.f1_records += 1
                    self._range(g, r.SecondGlyph, r.Value1, r.Value2)
                    pairs.setdefault(g, {}).setdefault(r.SecondGlyph, (r.Value1, r.Value2))
                    self.explicit_pairs.add((g, r.SecondGlyph))
            return ("f1", set(cov), pairs)
        if st.Format == 2:
            if st.Class1Count != len(st.Class1Record) or any(
                    st.Class2Count != len(c.Class2Record) for c in st.Class1Record):
                self.findings.append(("class_count_mismatch", "class1=%s/%d class2=%s" % (
                    st.Class1Count, len(st.Class1Record), st.Class2Count)))
            for i, c1r in enumerate(st.Class1Record):
                for j, c2r in enumerate(c1r.Class2Record):
                    self._range("class%d" % i, "class%d" % j, c2r.Value1, c2r.Value2)
            c1, c2 = st.ClassDef1.classDefs if st.ClassDef1 else {}, st.ClassDef2.classDefs if st.ClassDef2 else {}
            for nm, cd, cnt in (("ClassDef1", c1, st.Class1Count), ("ClassDef2", c2, st.Class2Count)):
                top = max(cd.values(), default=0)
                if top >= cnt:
                    self.findings.append(("classdef_class_out_of_range", "%s uses class %d but the count is %d" % (nm, top, cnt)))
            return ("f2", set(cov), (c1, c2, st))
        raise AssertionError("unreachable")

    def _range(self, a, b, *values):
        for v in values:
            for n in VALUE_FIELDS:
                x = getattr(v, n, 0) if v is not None else 0
                if x is not None and not (INT16_MIN <= x <= INT16_MAX):
                    self.findings.append(("value_out_of_int16", "%s,%s %s=%d" % (a, b, n, x)))

    def class_out_of_range(self, left, right):
        """True when the first matching format 2 subtable maps the pair to a class index outside its class counts."""
        for subs in self.lookups:
            for kind, cov, data in subs:
                if left not in cov:
                    continue
                if kind == "f1":
                    if data.get(left, {}).get(right) is None:
                        continue
                    break
                c1, c2, st = data
                k1, k2 = c1.get(left, 0), c2.get(right, 0)
                if k1 >= len(st.Class1Record) or k2 >= len(st.Class1Record[k1].Class2Record):
                    return True
                break
        return False

    def explicit_zero_pair(self, left, right):
        """True when the first matching subtable of some kern lookup is a glyph pair record whose value is zero."""
        for subs in self.lookups:
            for kind, cov, data in subs:
                if left not in cov:
                    continue
                if kind == "f1":
                    rec = data.get(left, {}).get(right)
                    if rec is None:
                        continue
                    x, o = _value(rec[0])
                    return x == 0 and not o
                break
        return False

    def effective(self, left, right, only=None):
        """Sum over kern lookups of the first matching subtable's XAdvance, and field flags.
        only: restrict to these lookup indexes (one language system)."""
        total, flags = 0, []
        for li, subs in zip(self.kern_lookup_indexes, self.lookups):
            if only is not None and li not in only:
                continue
            for kind, cov, data in subs:
                if left not in cov:
                    continue
                if kind == "f1":
                    rec = data.get(left, {}).get(right)
                    if rec is None:
                        continue
                    v1, v2 = rec
                else:
                    c1, c2, st = data
                    k1, k2 = c1.get(left, 0), c2.get(right, 0)
                    if k1 >= len(st.Class1Record) or k2 >= len(st.Class1Record[k1].Class2Record):
                        continue
                    r = st.Class1Record[k1].Class2Record[k2]
                    v1, v2 = r.Value1, r.Value2
                x, o = _value(v1)
                x2, o2 = _value(v2)
                total += x
                flags += o + (["Value2"] if (x2 or o2) else [])
                break
        return total, flags


def _glyph_char(font):
    rev = {}
    for cp, g in sorted(font.getBestCmap().items(), reverse=True):
        rev[g] = cp
    return rev


def _shape(hbfont, text, kern):
    import uharfbuzz as hb
    buf = hb.Buffer()
    buf.add_str(text)
    buf.direction, buf.script, buf.language = "ltr", "Latn", "en"
    hb.shape(hbfont, buf, {"kern": kern})
    return [(p.x_advance, p.x_offset, p.y_offset) for p in buf.glyph_positions], [i.codepoint for i in buf.glyph_infos]


def _raw_pairpos_checks(data, formats_out=None):
    """Structure checks on the raw GPOS bytes, independent of the fontTools object model (which
    recomputes or trusts counts): record arrays must fit in the table and must not run into the
    offsets that follow them. Returns a list of (code, detail)."""
    out = []
    u16 = lambda o: struct.unpack(">H", data[o:o + 2])[0]
    u32 = lambda o: struct.unpack(">I", data[o:o + 4])[0]
    vsize = lambda f: 2 * bin(f & 0xFF).count("1")
    try:
        ll = u16(8)
        for li in range(u16(ll)):
            lk = ll + u16(ll + 2 + 2 * li)
            typ = u16(lk)
            for si in range(u16(lk + 4)):
                sub = lk + u16(lk + 6 + 2 * si)
                if typ == 9:
                    if u16(sub) != 1:
                        out.append(("extension_format_unsupported", "lookup %d" % li))
                        continue
                    t, sub = u16(sub + 2), sub + u32(sub + 4)
                else:
                    t = typ
                if t != 2:
                    continue
                fmt = u16(sub)
                if fmt in (1, 2):
                    vf1, vf2 = u16(sub + 4), u16(sub + 6)
                    if formats_out is not None:
                        formats_out.append((li, fmt, vf1, vf2))
                    if (vf1 | vf2) & RESERVED_VALUE_FORMAT_BITS:
                        out.append(("value_format_reserved_bits", "lookup %d format %d ValueFormat1=0x%04x ValueFormat2=0x%04x" % (
                            li, fmt, vf1, vf2)))
                    if vf1 != OUTPUT_VALUE_FORMAT1:
                        out.append(("value_format1_not_x_advance_only", "lookup %d format %d ValueFormat1=0x%04x expected=0x%04x" % (
                            li, fmt, vf1, OUTPUT_VALUE_FORMAT1)))
                    if vf2 != OUTPUT_VALUE_FORMAT2:
                        out.append(("value_format2_not_zero", "lookup %d format %d ValueFormat2=0x%04x" % (li, fmt, vf2)))
                if fmt == 1:
                    f1, f2 = u16(sub + 4), u16(sub + 6)
                    rec = 2 + vsize(f1) + vsize(f2)
                    for i in range(u16(sub + 8)):
                        ps = sub + u16(sub + 10 + 2 * i)
                        end = ps + 2 + u16(ps) * rec
                        if end > len(data):
                            out.append(("pairset_count_mismatch", "lookup %d pairset %d runs past the table (%d > %d)" % (li, i, end, len(data))))
                elif fmt == 2:
                    f1, f2 = u16(sub + 4), u16(sub + 6)
                    c1, c2 = u16(sub + 12), u16(sub + 14)
                    end = sub + 16 + c1 * c2 * (vsize(f1) + vsize(f2))
                    offs = [sub + u16(sub + 2), sub + u16(sub + 8), sub + u16(sub + 10)]
                    nxt = min([o for o in offs if o >= sub + 16] or [len(data)])
                    if end > len(data) or end > nxt:
                        out.append(("class_count_mismatch", "lookup %d class records end at %d, next structure at %d, table ends at %d (class1=%d class2=%d)" % (
                            li, end, nxt, len(data), c1, c2)))
    except (struct.error, IndexError) as e:
        out.append(("gpos_raw_structure_unreadable", repr(e)))
    return out


def _language_system_mismatches(gp, pairs):
    """One finding per language system whose kern x-advance differs from the first language system on any
    pair of `pairs` (the enumerated pairs). Language systems that reach the same kern lookups cannot differ."""
    out = []
    if len({k for _, k in gp.langsys}) < 2:
        return out
    ref_label, ref = gp.langsys[0]
    for label, lks in gp.langsys[1:]:
        if lks == ref:
            continue
        diff = [(l, r) for (l, r) in sorted(pairs) if gp.effective(l, r, ref)[0] != gp.effective(l, r, lks)[0]]
        if diff:
            l, r = diff[0]
            out.append(("language_system_mismatch", "%s vs %s: %d pairs differ, first %s,%s %d vs %d" % (
                label, ref_label, len(diff), l, r, gp.effective(l, r, lks)[0], gp.effective(l, r, ref)[0])))
    return out


def _raw_feature_params_checks(data):
    """FeatureParams of a kern feature, read from the raw bytes (the object model drops it for this tag)."""
    out = []
    u16 = lambda o: struct.unpack(">H", data[o:o + 2])[0]
    try:
        fl = u16(6)
        if fl == 0:
            return out
        for i in range(u16(fl)):
            tag = data[fl + 2 + 6 * i:fl + 6 + 6 * i]
            ft = fl + u16(fl + 6 + 6 * i)
            if tag == b"kern" and u16(ft) != 0:
                out.append(("feature_params_present", "kern feature %d FeatureParams offset=%d" % (i, u16(ft))))
    except (struct.error, IndexError) as e:
        out.append(("gpos_raw_structure_unreadable", "feature list: " + repr(e)))
    return out


def _enumerate(gp, order, limit, extra=()):
    """Effective value of every glyph pair when the glyph count is within the limit, else only the
    explicit pairs and `extra`; the caller must report the second case as not_enumerated."""
    enum = len(order) <= limit
    names = set(order)
    pairs = {(l, r) for l in order for r in order} if enum else set(gp.explicit_pairs)
    pairs |= {k for k in extra if k[0] in names and k[1] in names}
    eff = {}
    for l, r in sorted(pairs):
        eff[(l, r)] = gp.effective(l, r)
    return enum, eff


def _compare_original(original, otabs, nfull, gp, out_eff, order, limit, drop_is_finding, findings):
    from fontTools.ttLib import TTFont
    L = []
    if "GPOS" not in otabs:
        L.append("original_effective compared=true original_gpos=absent original_nonzero=0")
        return L
    try:
        ofull = TTFont(io.BytesIO(original))
        og = _Gpos(ofull)
    except Exception as e:
        findings.append(("original_parse_failure", "GPOS: " + repr(e)))
        return ["original_effective compared=false original_gpos=unreadable"]
    info = []
    for code, detail in og.findings:
        if code in ("lookup_flag_nonstandard", "req_feature_index_set"):
            info.append("original_info code=%s detail=%s" % (code, detail))
            continue
        findings.append(("original_" + code, detail))
    info.append("original_gpos_structure lookups=%d features=%d kern_features=%d language_systems=%d distinct_kern_lookup_sets=%d" % (
        og.lookup_count, og.feature_count, og.kern_feature_count, len(og.langsys), len({k for _, k in og.langsys})))
    fmts = []
    _raw_pairpos_checks(otabs["GPOS"], fmts)
    for li, fmt, vf1, vf2 in fmts:
        if (vf1, vf2) != (OUTPUT_VALUE_FORMAT1, OUTPUT_VALUE_FORMAT2):
            info.append("original_value_format info=differs_from_output_contract lookup=%d format=%d ValueFormat1=0x%04x ValueFormat2=0x%04x compared_through=effective_x_advance" % (
                li, fmt, vf1, vf2))
    oorder = ofull.getGlyphOrder()
    enum_o, oeff = _enumerate(og, oorder, limit)
    if not enum_o:
        findings.append(("not_enumerated", "original glyphs=%d limit=%d" % (len(oorder), limit)))
    common = set(order) & set(oorder)
    only = sorted(set(oorder) ^ set(order))
    pres = chg = drop = add = 0
    lines = []
    keys = set(oeff) | set(out_eff)
    for k in sorted(keys):
        if k[0] not in common or k[1] not in common:
            continue
        ov = oeff.get(k, (0, []))[0]
        nv = out_eff.get(k)
        if nv is None:
            nv = gp.effective(*k)[0]
        if ov == 0 and nv == 0:
            continue
        if ov != 0 and nv == ov:
            pres += 1
            lines.append("original_pair status=preserved pair=%s,%s value=%d" % (k[0], k[1], ov))
        elif ov != 0 and nv == 0:
            drop += 1
            lines.append("original_pair status=dropped pair=%s,%s original=%d" % (k[0], k[1], ov))
            if drop_is_finding:
                findings.append(("original_pair_dropped", "%s,%s original=%d" % (k[0], k[1], ov)))
        elif ov != 0:
            chg += 1
            lines.append("original_pair status=changed pair=%s,%s original=%d output=%d" % (k[0], k[1], ov, nv))
        else:
            add += 1
            lines.append("original_pair status=added pair=%s,%s output=%d" % (k[0], k[1], nv))
    ez = sorted(k for k in gp.explicit_pairs if k[0] in common and k[1] in common and gp.explicit_zero_pair(*k))
    for k in ez:
        lines.append("original_pair status=explicit_zero_in_output pair=%s,%s original=%d" % (k[0], k[1], oeff.get(k, (0, []))[0]))
    onz = sum(1 for v in oeff.values() if v[0] != 0)
    L.append("original_effective compared=true original_gpos=present original_nonzero=%d preserved=%d changed=%d dropped=%d added=%d explicit_zero_in_output=%d glyphs_not_in_both=%d complete=%s mode=%s" % (
        onz, pres, chg, drop, add, len(ez), len(only), str(enum_o).lower(),
        "dropped_is_finding" if drop_is_finding else "report_only"))
    return L + info + lines


def _sequences(sequences, hbfont, rev, nfull, gp, findings):
    cmap = nfull.getBestCmap()
    L = []
    total = bad = 0
    if isinstance(sequences, (str, bytes, dict)) or not hasattr(sequences, "__iter__"):
        findings.append(("sequence_input_unusable", "sequences must be a list, got %s" % type(sequences).__name__))
        return []
    for item in sequences:
        total += 1
        if isinstance(item, str):
            text, exp = item, None
        elif isinstance(item, dict) and isinstance(item.get("text"), str) and (
                item.get("expected_kern") is None or isinstance(item.get("expected_kern"), (list, tuple))):
            text, exp = item["text"], item.get("expected_kern")
        else:
            bad += 1
            findings.append(("sequence_input_unusable", "item %d: expected a string or {text, expected_kern}" % (total - 1)))
            continue
        miss = [c for c in text if ord(c) not in cmap]
        if miss or len(text) < 2:
            bad += 1
            findings.append(("sequence_not_shapable", "%r missing_cmap=%s" % (text, "".join(miss) or "none")))
            L.append("sequence text=%s result=not_shapable" % text)
            continue
        names = [cmap[ord(c)] for c in text]
        on, gids = _shape(hbfont, text, True)
        off, _ = _shape(hbfont, text, False)
        delta = [a[0] - b[0] for a, b in zip(on, off)]
        table = [gp.effective(a, b)[0] for a, b in zip(names, names[1:])] + [0]
        ok = (delta == table and [a[1:] for a in on] == [b[1:] for b in off]
              and gids == [nfull.getGlyphID(n) for n in names])
        if exp is not None:
            ok = ok and list(exp) == delta
        if not ok:
            bad += 1
            findings.append(("sequence_mismatch", "%s shaped=%s table=%s expected=%s" % (text, delta, table, exp)))
        L.append("sequence text=%s glyphs=%s advances_off=%s advances_on=%s delta=%s table_delta=%s expected=%s ok=%s" % (
            text, ",".join(names), [a[0] for a in off], [a[0] for a in on], delta, table,
            "none" if exp is None else list(exp), str(ok).lower()))
    return ["sequences total=%d mismatches=%d" % (total, bad)] + L


def check(original, output, declared, allow_diff_tags=(), **kw):
    """Same contract as _check. Any exception that escapes the checks is a typed finding in the receipt, not a crash."""
    try:
        return _check(original, output, declared, allow_diff_tags, **kw)
    except Exception as e:
        lines = [RECEIPT_VERSION]
        if isinstance(original, (bytes, bytearray)) and isinstance(output, (bytes, bytearray)):
            lines.append("input original_sha256=%s original_bytes=%d output_sha256=%s output_bytes=%d" % (
                sha256(original), len(original), sha256(output), len(output)))
        lines.append("finding code=check_aborted detail=%s" % _fmt(repr(e)))
        lines.append("verdict=FAIL findings=1")
        return "\n".join(lines) + "\n", [("check_aborted", repr(e))], {}


def _check(original, output, declared, allow_diff_tags=(), *, enumeration_limit=ENUM_LIMIT_DEFAULT,
           allow_legacy_kern=None, compare_original=False, original_drop_is_finding=False, sequences=()):
    """Returns (receipt_text, findings, stats). original/output are font file bytes.

    sequences: strings or {"text": str, "expected_kern": [int, ...]} shaped in context.
    allow_legacy_kern: None (a legacy kern table is a finding) or a non-empty reason string.
    compare_original: also report the original GPOS effective pairs against the output.
    """
    import fontTools
    import uharfbuzz as hb
    from fontTools.ttLib import TTFont
    findings = []
    L = []
    declared = _normalize_declared(declared, findings)
    L.append(RECEIPT_VERSION)
    L.append("env python=%s fonttools=%s uharfbuzz=%s harfbuzz=%s" % (
        platform.python_version(), fontTools.version, hb.__version__, hb.version_string()))
    pf = []
    for name, blob, code in (("original", original, "original_parse_failure"), ("output", output, "parse_failure")):
        if not isinstance(blob, (bytes, bytearray)):
            pf.append((code, "%s is not a byte string (%s)" % (name, type(blob).__name__)))
    if pf:
        L.append("input original_sha256=%s output_sha256=%s" % (
            sha256(original) if isinstance(original, (bytes, bytearray)) else "none",
            sha256(output) if isinstance(output, (bytes, bytearray)) else "none"))
    else:
        L.append("input original_sha256=%s original_bytes=%d output_sha256=%s output_bytes=%d" % (
            sha256(original), len(original), sha256(output), len(output)))
        try:
            ofont, otabs = _raw_tables(original)
        except Exception as e:  # a damaged original is a typed finding, never a crash
            pf.append(("original_parse_failure", repr(e)))
        try:
            nfont, ntabs = _raw_tables(output)
            nfull = TTFont(io.BytesIO(output))
            if "GPOS" in ntabs:
                nfull["GPOS"]  # decompile now so a damaged table is a typed finding
                gp = _Gpos(nfull)
            else:
                gp = None
        except Exception as e:  # parse failure is a finding, never a crash
            pf.append(("parse_failure", repr(e)))
    if pf:
        findings += pf
        for code, detail in findings:
            L.append("finding code=%s detail=%s" % (code, _fmt(detail)))
        L.append("verdict=FAIL findings=%d" % len(findings))
        return "\n".join(L) + "\n", findings, {}
    # declared counters
    seen = set()
    counts = {"written": 0, "rounded": 0, "rejected": 0, "invalid": 0}
    max_err = 0.0
    for d in declared:
        key = (d.left, d.right)
        if key in seen:
            findings.append(("duplicate_declared_pair", "%s,%s" % key))
        seen.add(key)
        if d.written is not None:
            if isinstance(d.written, bool) or not isinstance(d.written, int):
                findings.append(("written_not_integer", "%s,%s %s" % (d.left, d.right, _fmt(d.written))))
            elif not (INT16_MIN <= d.written <= INT16_MAX):
                findings.append(("written_out_of_int16", "%s,%s %s" % (d.left, d.right, _fmt(d.written))))
        cs = computed_status(d)
        counts[cs] += 1
        if cs == "invalid":
            findings.append(("declared_value_unusable", "%s,%s requested=%s written=%s" % (d.left, d.right, _fmt(d.requested), _fmt(d.written))))
            continue
        if _unusable_number(d.requested):
            findings.append(("declared_value_unusable", "%s,%s requested=%s written=%s" % (d.left, d.right, _fmt(d.requested), _fmt(d.written))))
        if d.status != cs:
            findings.append(("status_mismatch", "%s,%s declared=%s computed=%s" % (d.left, d.right, d.status, cs)))
        if cs == "rejected" and not d.reason:
            findings.append(("rejected_without_reason", "%s,%s" % key))
        if cs == "rounded" and not _unusable_number(d.requested):
            max_err = max(max_err, abs(float(d.requested) - float(d.written)))
    L.append("declared total=%d written=%d rounded=%d rejected=%d invalid=%d" % (
        len(declared), counts["written"], counts["rounded"], counts["rejected"], counts["invalid"]))
    L.append("rounding count=%d max_abs_error=%r" % (counts["rounded"], max_err))
    for d in declared:
        if computed_status(d) == "invalid":
            L.append("declared_invalid pair=%s,%s requested=%s written=%s" % (d.left, d.right, _fmt(d.requested), _fmt(d.written)))
        if computed_status(d) == "rejected":
            L.append("declared_rejected pair=%s,%s requested=%s reason=%s" % (d.left, d.right, _fmt(d.requested), d.reason or "MISSING"))
    # GPOS table
    if "GPOS" not in ntabs:
        findings.append(("gpos_missing", "output has no GPOS table"))
        L.append("table GPOS present=false original_present=%s" % str("GPOS" in otabs).lower())
        gp = None
    else:
        findings += gp.findings
        findings += _raw_pairpos_checks(ntabs["GPOS"])
        findings += _raw_feature_params_checks(ntabs["GPOS"])
        if gp.lookup_count > 1:
            findings.append(("output_lookup_count_not_one", "output GPOS has %d lookups, the contract has one" % gp.lookup_count))
        L.append("gpos_structure lookups=%d features=%d kern_features=%d language_systems=%d distinct_kern_lookup_sets=%d" % (
            gp.lookup_count, gp.feature_count, gp.kern_feature_count, len(gp.langsys),
            len({k for _, k in gp.langsys})))
        L.append("table GPOS present=true output_sha256=%s bytes=%d original_sha256=%s kern_lookups=%d lookup_types=%s extension_subtables=%d" % (
            sha256(ntabs["GPOS"]), len(ntabs["GPOS"]),
            sha256(otabs["GPOS"]) if "GPOS" in otabs else "none",
            len(gp.kern_lookup_indexes),
            ",".join("%d:%d" % kv for kv in sorted(gp.lookup_types.items())) or "none",
            gp.extension_count))
    # non-GPOS bytes
    equal, diff = compare_non_gpos(otabs, ntabs, allow_diff_tags)
    bad = [x for x in diff if x[0] not in allow_diff_tags]
    L.append("non_gpos_tables equal=%d diff=%d diff_not_allowed=%d head_checksum_adjustment_masked=true" % (len(equal), len(diff), len(bad)))
    for tag, h in equal:
        L.append("non_gpos_equal tag=%s sha256=%s" % (tag, h))
    for tag, kind, a, b, la, lb in diff:
        L.append("non_gpos_diff tag=%s kind=%s original_sha256=%s output_sha256=%s original_bytes=%d output_bytes=%d allowed=%s" % (
            tag, kind, a, b, la, lb, str(tag in allow_diff_tags).lower()))
    for x in bad:
        findings.append(("non_gpos_table_differs", "%s %s" % (x[0], x[1])))
    # legacy kern table
    legacy = "kern" in ntabs
    if legacy and not allow_legacy_kern:
        findings.append(("legacy_kern_table_present", "output has a legacy kern table (original had one: %s)" % str("kern" in otabs).lower()))
    L.append("legacy_kern present=%s original_present=%s allowed=%s" % (
        str(legacy).lower(), str("kern" in otabs).lower(), ("reason=" + allow_legacy_kern) if allow_legacy_kern else "false"))
    # round trip
    order = nfull.getGlyphOrder()
    names = set(order)
    mism = rej_present = 0
    checked = 0
    undeclared = 0
    flags_total = 0
    eff = {}
    if gp is not None:
        for d in declared:
            for g in (d.left, d.right):
                if g not in names:
                    findings.append(("unknown_glyph", g))
        dmap = {(d.left, d.right): d for d in declared}
        enum, raw_eff = _enumerate(gp, order, enumeration_limit, dmap)
        if not enum:
            findings.append(("not_enumerated", "glyphs=%d limit=%d: undeclared nonzero pairs not ruled out" % (len(order), enumeration_limit)))
        L.append("format1 subtables=%d pairsets=%d pair_records=%d" % (gp.f1_subtables, gp.f1_pairsets, gp.f1_records))
        findings += _language_system_mismatches(gp, raw_eff)
        for (l, r), (v, fl) in raw_eff.items():
            eff[(l, r)] = v
            if fl:
                flags_total += 1
                findings.append(("unexpected_value_fields", "%s,%s %s" % (l, r, ",".join(sorted(set(fl))))))
            d = dmap.get((l, r))
            if d is None:
                if v != 0:
                    undeclared += 1
                    findings.append(("undeclared_nonzero_pair", "%s,%s value=%d" % (l, r, v)))
                continue
            if computed_status(d) == "invalid":
                continue
            checked += 1
            if computed_status(d) == "rejected":
                if v != 0:
                    rej_present += 1
                    findings.append(("rejected_pair_present", "%s,%s value=%d" % (l, r, v)))
            elif v != d.written:
                mism += 1
                findings.append(("roundtrip_value_mismatch", "%s,%s declared=%d read=%d" % (l, r, d.written, v)))
        L.append("roundtrip declared_pairs_checked=%d mismatches=%d rejected_present=%d undeclared_nonzero=%d unexpected_value_fields=%d enumerated_glyph_pairs=%s" % (
            checked, mism, rej_present, undeclared, flags_total,
            len(order) ** 2 if enum else "not_enumerated"))
        L.append("enumeration glyphs=%d limit=%d limit_class=CONVENTION complete=%s" % (len(order), enumeration_limit, str(enum).lower()))
        # HarfBuzz
        rev = _glyph_char(nfull)
        try:
            hbfont = hb.Font(hb.Face(bytes(output)))
        except Exception as e:
            hbfont = None
            findings.append(("harfbuzz_unusable", _fmt(repr(e))))
        exc = sorted(k for k, d in dmap.items() if computed_status(d) in ("written", "rounded"))
        rej = sorted(k for k, d in dmap.items() if computed_status(d) == "rejected")
        extra = sorted(p for p in gp.explicit_pairs if p not in dmap)
        hb_mism = hb_unshaped = 0
        lines = []
        for group, items in (("declared_written", exc), ("rejected", rej), ("explicit_undeclared", extra)):
            for l, r in items:
                if hbfont is None:
                    break
                if gp.class_out_of_range(l, r):
                    lines.append("harfbuzz_pair group=%s pair=%s,%s result=skipped_class_index_out_of_range table_value=%d" % (
                        group, l, r, eff.get((l, r), 0)))
                    continue
                if l not in rev or r not in rev:
                    hb_unshaped += 1
                    findings.append(("hb_not_shapable_no_cmap", "%s,%s" % (l, r)))
                    lines.append("harfbuzz_pair group=%s pair=%s,%s result=not_shapable_no_cmap" % (group, l, r))
                    continue
                text = chr(rev[l]) + chr(rev[r])
                on, gids = _shape(hbfont, text, True)
                off, _ = _shape(hbfont, text, False)
                want = eff.get((l, r), 0)
                got = on[0][0] - off[0][0]
                ok = (got == want and on[1][0] == off[1][0] and on[0][1:] == off[0][1:] and on[1][1:] == off[1][1:]
                      and gids == [nfull.getGlyphID(l), nfull.getGlyphID(r)])
                if group == "declared_written" and (l, r) in dmap:
                    want_d = dmap[(l, r)].written
                    ok = ok and got == want_d
                    want = want_d
                if not ok:
                    hb_mism += 1
                    findings.append(("hb_value_mismatch", "%s,%s expected=%d got=%d" % (l, r, want, got)))
                lines.append("harfbuzz_pair group=%s pair=%s,%s expected=%d got=%d ok=%s" % (group, l, r, want, got, str(ok).lower()))
        L.append("harfbuzz declared_written_pairs=%d rejected_pairs=%d explicit_undeclared_pairs=%d mismatches=%d not_shapable=%d" % (
            len(exc), len(rej), len(extra), hb_mism, hb_unshaped))
        L += lines
        # B8: original effective pairs against the output (optional)
        if compare_original:
            L += _compare_original(original, otabs, nfull, gp, eff, order, enumeration_limit, original_drop_is_finding, findings)
        # context sequences shaped as a whole
        if sequences and hbfont is not None:
            L += _sequences(sequences, hbfont, rev, nfull, gp, findings)
    for code, detail in findings:
        L.append("finding code=%s detail=%s" % (code, detail))
    L.append("verdict=%s findings=%d" % ("PASS" if not findings else "FAIL", len(findings)))
    return "\n".join(L) + "\n", findings, {"counts": counts}
