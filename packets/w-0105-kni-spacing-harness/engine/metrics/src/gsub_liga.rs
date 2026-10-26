//! Core GSUB 'liga' serializer: one 'liga' feature under scripts DFLT and
//! latn (same feature index in both; DFLT-only registration is a real
//! shaper-visibility risk) / default LangSys, one type-4 (LigatureSubst) lookup with one format 1
//! subtable. Produces a byte buffer; it never touches a font file.
//!
//! Ligature glyphs are deliberately NOT cmap-mapped (a cmap entry is one
//! scalar); the substitution sequence is the only route to the glyph, which
//! is what this table encodes.
//!
//! Contract (every item is refused with a typed error, nothing is repaired):
//! - glyph ids must be below the caller's `num_glyphs` (the font owns it);
//! - a sequence needs at least two glyphs total (`SequenceTooShort`);
//! - a repeated sequence is refused (`DuplicateSequence` same ligature,
//!   `ConflictingSequence` different ligature); no silent merge;
//! - every Offset16 and count is checked; nothing is dropped or clamped to
//!   make a table fit (DRAFT: no subtable splitting / Extension lookup yet,
//!   unlike the GPOS writer; an oversized table is refused);
//! - output is independent of input order: coverage ascending by first
//!   glyph; within a set, ligatures by descending component count (longest
//!   match first, so "f f i" wins over "f f"), ties by components then
//!   ligature glyph id.

use std::collections::BTreeMap;
use std::fmt;
use std::mem::size_of;

/// One ligature substitution in glyph ids. `components` are the glyphs
/// AFTER `first`; the full sequence is `first` + `components`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LigaSub {
    pub first: u16,
    pub components: Vec<u16>,
    pub ligature: u16,
}

/// Typed refusal. No variant is recoverable by guessing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GsubWriteError {
    NoLigatures,
    SequenceTooShort { first: u16 },
    GlyphOutOfRange { glyph: u16, num_glyphs: u16 },
    DuplicateSequence { first: u16, components: Vec<u16>, ligature: u16 },
    ConflictingSequence { first: u16, components: Vec<u16>, first_lig: u16, second_lig: u16 },
    CountOverflow { what: &'static str, count: usize },
    OffsetOverflow { what: &'static str, offset: usize },
}

impl fmt::Display for GsubWriteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for GsubWriteError {}

const U16_LEN: usize = size_of::<u16>();

fn words(v: &[u16]) -> Vec<u8> {
    v.iter().flat_map(|w| w.to_be_bytes()).collect()
}

fn off16(what: &'static str, at: usize) -> Result<u16, GsubWriteError> {
    u16::try_from(at).map_err(|_| GsubWriteError::OffsetOverflow { what, offset: at })
}

fn cnt16(what: &'static str, n: usize) -> Result<u16, GsubWriteError> {
    u16::try_from(n).map_err(|_| GsubWriteError::CountOverflow { what, count: n })
}

/// Group by first glyph, refuse duplicates/conflicts, sort for
/// determinism. Returns first glyphs ascending with their sets.
fn group(num_glyphs: u16, subs: &[LigaSub]) -> Result<Vec<(u16, Vec<LigaSub>)>, GsubWriteError> {
    let mut seen: BTreeMap<(u16, Vec<u16>), u16> = BTreeMap::new();
    for s in subs {
        if s.components.is_empty() {
            return Err(GsubWriteError::SequenceTooShort { first: s.first });
        }
        for &g in std::iter::once(&s.first).chain(s.components.iter()).chain(std::iter::once(&s.ligature)) {
            if g >= num_glyphs {
                return Err(GsubWriteError::GlyphOutOfRange { glyph: g, num_glyphs });
            }
        }
        match seen.insert((s.first, s.components.clone()), s.ligature) {
            None => {}
            Some(prev) if prev == s.ligature => {
                return Err(GsubWriteError::DuplicateSequence { first: s.first, components: s.components.clone(), ligature: s.ligature });
            }
            Some(prev) => {
                return Err(GsubWriteError::ConflictingSequence { first: s.first, components: s.components.clone(), first_lig: prev, second_lig: s.ligature });
            }
        }
    }
    let mut by_first: BTreeMap<u16, Vec<LigaSub>> = BTreeMap::new();
    for ((first, components), ligature) in seen {
        by_first.entry(first).or_default().push(LigaSub { first, components, ligature });
    }
    // Longest match first; ties broken for determinism only.
    for set in by_first.values_mut() {
        set.sort_by(|a, b| b.components.len().cmp(&a.components.len())
            .then_with(|| a.components.cmp(&b.components))
            .then_with(|| a.ligature.cmp(&b.ligature)));
    }
    Ok(by_first.into_iter().collect())
}

/// Coverage format 1 over the first glyphs (already ascending).
fn coverage(groups: &[(u16, Vec<LigaSub>)]) -> Result<Vec<u8>, GsubWriteError> {
    let mut out = words(&[1, cnt16("coverage glyphs", groups.len())?]);
    for (first, _) in groups {
        out.extend_from_slice(&first.to_be_bytes());
    }
    Ok(out)
}

/// One Ligature table: ligGlyph, compCount (total incl. first), components.
fn ligature(s: &LigaSub) -> Result<Vec<u8>, GsubWriteError> {
    let comp_count = cnt16("component count", s.components.len() + 1)?;
    let mut out = words(&[s.ligature, comp_count]);
    for c in &s.components {
        out.extend_from_slice(&c.to_be_bytes());
    }
    Ok(out)
}

/// LigatureSet: count, offsets, then the Ligature tables.
fn ligature_set(set: &[LigaSub]) -> Result<Vec<u8>, GsubWriteError> {
    let head = U16_LEN * (1 + set.len());
    let mut out = words(&[cnt16("ligature count", set.len())?]);
    let mut at = head;
    let mut tables = Vec::new();
    for s in set {
        let t = ligature(s)?;
        out.extend_from_slice(&off16("ligature offset", at)?.to_be_bytes());
        at += t.len();
        tables.extend_from_slice(&t);
    }
    out.extend_from_slice(&tables);
    Ok(out)
}

/// LigatureSubst format 1 subtable: format, coverage offset, set count and
/// offsets, then coverage and the sets.
fn ligature_subtable(groups: &[(u16, Vec<LigaSub>)]) -> Result<Vec<u8>, GsubWriteError> {
    let cov = coverage(groups)?;
    let head = U16_LEN * (3 + groups.len());
    let cov_at = head;
    let sets_at = cov_at + cov.len();
    let mut out = words(&[1, off16("coverage offset", cov_at)?, cnt16("ligature sets", groups.len())?]);
    let mut at = sets_at;
    let mut sets = Vec::new();
    for (_, set) in groups {
        let s = ligature_set(set)?;
        out.extend_from_slice(&off16("ligature set offset", at)?.to_be_bytes());
        at += s.len();
        sets.extend_from_slice(&s);
    }
    out.extend_from_slice(&cov);
    out.extend_from_slice(&sets);
    Ok(out)
}

/// Script table: default LangSys only, one feature (index 0).
fn script_table() -> Vec<u8> {
    let mut out = words(&[4, 0]); // defaultLangSysOffset, langSysCount
    out.extend_from_slice(&words(&[0, 0xffff, 1, 0])); // lookupOrder, reqFeature, count, feature[0]
    out
}

/// ScriptList: DFLT and latn (records sorted by tag), each with its own
/// Script table pointing at the same feature index 0.
fn script_list() -> Vec<u8> {
    let table = script_table();
    let head = U16_LEN * (1 + 2 * 3); // count + two 6-byte records
    let dflt_at = head;
    let latn_at = dflt_at + table.len();
    let mut out = words(&[2]); // scriptCount
    out.extend_from_slice(b"DFLT");
    out.extend_from_slice(&(dflt_at as u16).to_be_bytes());
    out.extend_from_slice(b"latn");
    out.extend_from_slice(&(latn_at as u16).to_be_bytes());
    out.extend_from_slice(&table);
    out.extend_from_slice(&table);
    out
}

/// FeatureList: one 'liga' feature pointing at lookup 0.
fn feature_list() -> Vec<u8> {
    let mut out = words(&[1]); // featureCount
    out.extend_from_slice(b"liga");
    out.extend_from_slice(&words(&[8])); // offset to Feature table
    out.extend_from_slice(&words(&[0, 1, 0])); // params, lookupIndexCount, index[0]
    out
}

/// LookupList: one type-4 lookup, flag 0, one subtable.
fn lookup_list(subtable: &[u8]) -> Result<Vec<u8>, GsubWriteError> {
    let mut lookup = words(&[4, 0, 1, 8]); // type, flag, subTableCount, subtable offset
    lookup.extend_from_slice(subtable);
    let mut out = words(&[1, off16("lookup offset", U16_LEN * 2)?]);
    out.extend_from_slice(&lookup);
    Ok(out)
}

/// Serialize a GSUB table (version 1.0) carrying exactly the given ligature
/// substitutions. `num_glyphs` is the font's glyph count; every glyph id
/// must be below it. An empty list is `Err(NoLigatures)`; use
/// `write_liga_or_omit` when "no ligatures" means "write no GSUB table".
pub fn write_liga(num_glyphs: u16, subs: &[LigaSub]) -> Result<Vec<u8>, GsubWriteError> {
    if subs.is_empty() {
        return Err(GsubWriteError::NoLigatures);
    }
    let groups = group(num_glyphs, subs)?;
    let subtable = ligature_subtable(&groups)?;
    let scripts = script_list();
    let features = feature_list();
    let lookups = lookup_list(&subtable)?;
    // Header: major, minor, scriptListOffset, featureListOffset, lookupListOffset.
    let scripts_at = U16_LEN * 5;
    let features_at = scripts_at + scripts.len();
    let lookups_at = features_at + features.len();
    let mut out = words(&[1, 0,
        off16("script list offset", scripts_at)?,
        off16("feature list offset", features_at)?,
        off16("lookup list offset", lookups_at)?]);
    out.extend_from_slice(&scripts);
    out.extend_from_slice(&features);
    out.extend_from_slice(&lookups);
    Ok(out)
}

/// Same as `write_liga`, but an empty list yields `Ok(None)` (the caller
/// then writes no GSUB table). Every other refusal is unchanged.
pub fn write_liga_or_omit(num_glyphs: u16, subs: &[LigaSub]) -> Result<Option<Vec<u8>>, GsubWriteError> {
    if subs.is_empty() {
        return Ok(None);
    }
    write_liga(num_glyphs, subs).map(Some)
}

#[cfg(test)]
mod tests {
    use super::*;

    const N: u16 = 40;
    // glyph order sketch: 1=f 2=i 3=l 4=f_i 5=f_l 6=f_f 7=f_f_i 8=f_f_l
    fn subs() -> Vec<LigaSub> {
        vec![
            LigaSub { first: 1, components: vec![2], ligature: 4 },
            LigaSub { first: 1, components: vec![3], ligature: 5 },
            LigaSub { first: 1, components: vec![1], ligature: 6 },
            LigaSub { first: 1, components: vec![1, 2], ligature: 7 },
            LigaSub { first: 1, components: vec![1, 3], ligature: 8 },
        ]
    }

    fn rd(b: &[u8], at: usize) -> u16 {
        u16::from_be_bytes([b[at], b[at + 1]])
    }

    // Independent reader: walks the table by its offsets and returns
    // (first, components, ligature) rows in coverage/set order, checking
    // bounds and tags.
    fn parse(b: &[u8]) -> Vec<(u16, Vec<u16>, u16)> {
        assert_eq!((rd(b, 0), rd(b, 2)), (1, 0), "GSUB version 1.0");
        let (sl, fl, ll) = (rd(b, 4) as usize, rd(b, 6) as usize, rd(b, 8) as usize);
        assert_eq!(rd(b, sl), 2, "scripts DFLT + latn");
        for i in 0..2 {
            let rec = sl + 2 + i * 6;
            let tag = &b[rec..rec + 4];
            assert!(tag == b"DFLT" || tag == b"latn", "unexpected script tag {tag:?}");
            let script = sl + rd(b, rec + 4) as usize;
            let langsys = script + rd(b, script) as usize;
            assert_eq!(rd(b, langsys + 6), 0, "both scripts reference feature index 0");
        }
        assert_eq!(rd(b, fl), 1);
        assert_eq!(&b[fl + 2..fl + 6], b"liga");
        assert_eq!(rd(b, ll), 1);
        let lookup = ll + rd(b, ll + 2) as usize;
        assert_eq!((rd(b, lookup), rd(b, lookup + 2), rd(b, lookup + 4)), (4, 0, 1), "one type-4 lookup, flag 0");
        let st = lookup + rd(b, lookup + 6) as usize;
        assert_eq!(rd(b, st), 1, "LigatureSubst format 1");
        let cov = st + rd(b, st + 2) as usize;
        let set_count = rd(b, st + 4) as usize;
        assert_eq!(rd(b, cov), 1, "coverage format 1");
        let cov_count = rd(b, cov + 2) as usize;
        assert_eq!(cov_count, set_count, "one coverage glyph per set");
        let mut out = Vec::new();
        for i in 0..set_count {
            let first = rd(b, cov + 4 + i * 2);
            let set = st + rd(b, st + 6 + i * 2) as usize;
            let lig_count = rd(b, set) as usize;
            for j in 0..lig_count {
                let lig = set + rd(b, set + 2 + j * 2) as usize;
                let (glyph, comp_count) = (rd(b, lig), rd(b, lig + 2) as usize);
                let comps = (0..comp_count - 1).map(|k| rd(b, lig + 4 + k * 2)).collect::<Vec<_>>();
                out.push((first, comps, glyph));
            }
        }
        out
    }

    #[test]
    fn builds_and_reads_back_sorted_longest_first() {
        let bytes = write_liga(N, &subs()).unwrap();
        assert_eq!(parse(&bytes), vec![
            (1, vec![1, 2], 7), // f f i -> f_f_i (3-long first)
            (1, vec![1, 3], 8), // f f l -> f_f_l
            (1, vec![1], 6),    // f f -> f_f
            (1, vec![2], 4),    // f i -> f_i
            (1, vec![3], 5),    // f l -> f_l
        ]);
    }

    #[test]
    fn script_list_carries_dflt_and_latn_on_the_same_feature() {
        let bytes = write_liga(N, &subs()).unwrap();
        let sl = rd(&bytes, 4) as usize;
        assert_eq!(rd(&bytes, sl), 2);
        let mut seen = Vec::new();
        for i in 0..2 {
            let rec = sl + 2 + i * 6;
            seen.push(String::from_utf8_lossy(&bytes[rec..rec + 4]).into_owned());
            let script = sl + rd(&bytes, rec + 4) as usize;
            assert_eq!(rd(&bytes, script), 4, "default LangSys present");
            let langsys = script + rd(&bytes, script) as usize;
            assert_eq!(rd(&bytes, langsys + 2), 0xffff, "no required feature");
            assert_eq!(rd(&bytes, langsys + 4), 1, "one feature");
            assert_eq!(rd(&bytes, langsys + 6), 0, "feature index 0 (the liga feature)");
        }
        assert_eq!(seen, vec!["DFLT", "latn"], "records sorted by tag");
    }

    #[test]
    fn output_is_independent_of_input_order() {
        let mut shuffled = subs();
        shuffled.reverse();
        assert_eq!(write_liga(N, &subs()).unwrap(), write_liga(N, &shuffled).unwrap());
    }

    #[test]
    fn empty_list_refused_or_omitted() {
        assert_eq!(write_liga(N, &[]).unwrap_err(), GsubWriteError::NoLigatures);
        assert_eq!(write_liga_or_omit(N, &[]).unwrap(), None);
        assert!(write_liga_or_omit(N, &subs()).unwrap().is_some());
    }

    #[test]
    fn out_of_range_and_short_sequence_refused() {
        let bad = LigaSub { first: N, components: vec![2], ligature: 4 };
        assert_eq!(write_liga(N, &[bad]).unwrap_err(), GsubWriteError::GlyphOutOfRange { glyph: N, num_glyphs: N });
        let short = LigaSub { first: 1, components: vec![], ligature: 4 };
        assert_eq!(write_liga(N, &[short]).unwrap_err(), GsubWriteError::SequenceTooShort { first: 1 });
    }

    #[test]
    fn duplicate_and_conflicting_sequences_refused() {
        let mut dup = subs();
        dup.push(dup[0].clone());
        assert!(matches!(write_liga(N, &dup).unwrap_err(), GsubWriteError::DuplicateSequence { .. }));
        let mut con = subs();
        con.push(LigaSub { first: 1, components: vec![2], ligature: 9 });
        assert!(matches!(write_liga(N, &con).unwrap_err(), GsubWriteError::ConflictingSequence { second_lig: 9, .. }));
    }

    #[test]
    fn multiple_first_glyphs_get_separate_sets() {
        let s = vec![
            LigaSub { first: 3, components: vec![2], ligature: 9 },
            LigaSub { first: 1, components: vec![2], ligature: 4 },
        ];
        let bytes = write_liga(N, &s).unwrap();
        let rows = parse(&bytes);
        assert_eq!(rows, vec![(1, vec![2], 4), (3, vec![2], 9)], "coverage ascending by first glyph");
    }
}
