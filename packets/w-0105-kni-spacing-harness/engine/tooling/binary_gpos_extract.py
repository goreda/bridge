#!/usr/bin/env python3
"""binary-gpos-u extractor (contract: first matching subtable WITHIN a
lookup; SUM across lookups). Observation: first-glyph XAdvance (Value1)
resolved from pinned binary GPOS kern lookups; font units. No Value2, no RTL,
charset-covered pairs only. Ledger rows = NONZERO resolved pairs; resolved
zeros are counted.
Value2 definition: if the FIRST matching subtable in
ANY lookup carries Value2 XAdvance, the pair is EXCLUDED entirely (counted as
value2_excluded, never summed with other lookups' contributions).
Extension: LookupType 9 subtables with ExtensionLookupType==2 are unwrapped;
other extension types counted and skipped. Script convention (extractor-level,
for manifest): 'kern' feature lookups collected from DFLT and latn scripts
(all langsys), feature index deduped, applied in lookup index order.
Variable fonts are instantiated at wght=400 BEFORE observation (contract step;
GPOS device/VariationIndex values pinned by instancer).
Pre-registered scope: fonts with NO GPOS kern lookups resolve to zero pairs and
surface as WARNING_ZERO_PAIRS (excluded from ledger, counted); a legacy 'kern'
table is never read into the ledger (binary-gpos-u observes GPOS only), its
presence is counted. fontTools version is pinned in the manifest.
Per-font report: pairs, zeros_resolved, value2_excluded, lookup type counts
(fmt2-direct / extension-unwrapped / other-type), instantiated flag; a font
with 0 resolved nonzero pairs is a WARNING, not silence.
"""
import csv, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

def kern_lookups(font):
    gpos = font['GPOS'].table if 'GPOS' in font else None
    if gpos is None: return [], {'fmt2_direct': 0, 'ext_unwrapped': 0, 'other': 0}
    feats = gpos.FeatureList
    scripts = gpos.ScriptList
    idxs = []
    for srec in scripts.ScriptRecord:
        if srec.ScriptTag not in {'DFLT', 'latn'}: continue
        langs = []
        if srec.Script.DefaultLangSys: langs.append(srec.Script.DefaultLangSys)
        langs += [l.LangSys for l in srec.Script.LangSysRecord]
        for ls in langs:
            for fi in ls.FeatureIndex:
                fr = feats.FeatureRecord[fi]
                if fr.FeatureTag == 'kern':
                    idxs.extend(fr.Feature.LookupListIndex)
    counts = {'fmt2_direct': 0, 'ext_unwrapped': 0, 'other': 0}
    subs = []
    for i in sorted(set(idxs)):
        lk = gpos.LookupList.Lookup[i]
        if lk.LookupType == 2:
            counts['fmt2_direct'] += 1
            subs.append(lk.SubTable)
        elif lk.LookupType == 9:
            unwrapped = []
            ok = True
            for st in lk.SubTable:
                if st.ExtensionLookupType == 2:
                    unwrapped.append(st.ExtSubTable)
                else:
                    ok = False
            if unwrapped:
                counts['ext_unwrapped'] += 1
                subs.append(unwrapped)
            if not ok:
                counts['other'] += 1
        else:
            counts['other'] += 1
    return subs, counts

def match_subtable(st, lg, rg):
    """None = no match; ('ok', v) = Value1 XAdvance; ('value2',) = contaminated."""
    if lg not in st.Coverage.glyphs: return None
    if st.Format == 1:
        i = st.Coverage.glyphs.index(lg)
        if i >= len(st.PairSet): return None
        for pvr in st.PairSet[i].PairValueRecord:
            if pvr.SecondGlyph == rg:
                if getattr(pvr.Value2, 'XAdvance', None): return ('value2',)
                return ('ok', getattr(pvr.Value1, 'XAdvance', None) or 0)
        return None
    else:
        c1 = st.ClassDef1.classDefs.get(lg, 0)
        c2 = st.ClassDef2.classDefs.get(rg, 0)
        try:
            rec = st.Class1Record[c1].Class2Record[c2]
        except IndexError:
            return None
        if getattr(rec.Value2, 'XAdvance', None): return ('value2',)
        return ('ok', getattr(rec.Value1, 'XAdvance', None) or 0)

def lookup_pairs(subtables, charset):
    """pair -> resolution for ONE lookup (first matching subtable wins)."""
    out = {}
    def consider(lg, rg):
        if (lg, rg) in out: return
        for st in subtables:
            m = match_subtable(st, lg, rg)
            if m is not None:
                out[(lg, rg)] = m
                return
    for st in subtables:
        if st.Format == 1:
            for i, lg in enumerate(st.Coverage.glyphs):
                if lg not in charset or i >= len(st.PairSet): continue
                for pvr in st.PairSet[i].PairValueRecord:
                    if pvr.SecondGlyph in charset:
                        consider(lg, pvr.SecondGlyph)
        else:
            for lg in st.Coverage.glyphs:
                if lg not in charset: continue
                for rg in charset:
                    consider(lg, rg)
    return out

def extract(path):
    font = TTFont(path, lazy=True)
    legacy_kern = 'kern' in font  # pre-registered: legacy 'kern' table is OUT
    # of binary-gpos-u scope (never read into ledger), counted only.
    instantiated = 'fvar' in font
    if instantiated:
        font = instantiateVariableFont(font, {'wght': 400})
    charset = set(font.getBestCmap().values())
    gid = {g: i for i, g in enumerate(font.getGlyphOrder())}
    lookups, counts = kern_lookups(font)
    total = {}
    excluded = set()
    zeros = 0
    for subtables in lookups:
        for (lg, rg), m in lookup_pairs(subtables, charset).items():
            if (lg, rg) in excluded: continue
            if m[0] == 'value2':
                total.pop((lg, rg), None)
                excluded.add((lg, rg))
                continue
            total[(lg, rg)] = total.get((lg, rg), 0) + m[1]
    rows = []
    for (lg, rg), v in total.items():
        if v == 0:
            zeros += 1
        else:
            rows.append((gid[lg], gid[rg], lg, rg, v))
    rows.sort()
    return rows, zeros, len(excluded), counts, instantiated, legacy_kern

def main():
    path, out = sys.argv[1], sys.argv[2]
    rows, zeros, n_v2, counts, inst, legacy = extract(path)
    with open(out, 'w', newline='') as f:
        w = csv.writer(f, delimiter='\t')
        w.writerow(['left_gid', 'right_gid', 'left', 'right', 'kern_u'])
        w.writerows(rows)
    warn = ' WARNING_ZERO_PAIRS' if not rows else ''
    lk = ' legacy_kern_present(out-of-scope)' if legacy else ''
    print(f"pairs={len(rows)} zeros_resolved={zeros} value2_excluded={n_v2} "
          f"lookups(fmt2_direct={counts['fmt2_direct']} ext_unwrapped={counts['ext_unwrapped']} other={counts['other']}) "
          f"instantiated={'wght400' if inst else 'static'}{warn}{lk}")

if __name__ == '__main__':
    main()
