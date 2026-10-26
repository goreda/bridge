//! Core GPOS serializer: one 'kern' feature under script DFLT / default
//! LangSys, one type-2 lookup with one PairPos Format 1 subtable, x-advance
//! values only. Produces a byte buffer; it never touches a font file.
//!
//! Contract (every item is refused with a typed error, nothing is repaired):
//! - glyph ids must be below the caller's `num_glyphs` (the font owns it);
//! - a repeated pair is refused (`DuplicatePair` same value, `ConflictingPair`
//!   different value); no silent merge, no last-wins;
//! - values outside int16 are refused, explicit zero values are kept;
//! - every Offset16, Offset32 and count is checked; nothing is dropped or
//!   clamped to make a table fit;
//! - size-derived layout: pairs that do not fit one PairPos subtable are
//!   split, in sorted order, over several format 1 subtables of the one lookup
//!   (a left glyph may then appear in several subtables, with disjoint right
//!   glyphs); if the subtable offsets no longer fit Offset16 from the lookup,
//!   the lookup becomes an Extension lookup (type 9, Offset32). A table that
//!   fits one subtable is byte-identical to the single-subtable layout;
//! - an empty pair list is refused (`NoPairs`), not written as an empty table;
//! - output is independent of input order: pair sets by ascending left glyph,
//!   records by ascending right glyph, coverage ascending.
//!
//! The numeric values here are OpenType binary-format values, not artistic
//! thresholds. Lengths and offsets are computed from the tables written, not
//! typed in. Legacy `gpos.rs` is not used (see `gpos_verified.rs` header).

use std::collections::BTreeMap;
use std::fmt;
use std::mem::size_of;

/// One kern pair in integer font units. Glyph ids index the font's glyph order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PairKern {
    pub left: u16,
    pub right: u16,
    pub x_advance: i32,
}

/// Typed refusal. No variant is recoverable by guessing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GposWriteError {
    NoPairs,
    GlyphOutOfRange { glyph: u16, num_glyphs: u16 },
    ValueOutOfRange { left: u16, right: u16, x_advance: i32 },
    DuplicatePair { left: u16, right: u16, x_advance: i16 },
    ConflictingPair { left: u16, right: u16, first: i16, second: i16 },
    CountOverflow { what: &'static str, count: usize },
    OffsetOverflow { what: &'static str, offset: usize },
}

impl fmt::Display for GposWriteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for GposWriteError {}

const U16_LEN: usize = size_of::<u16>();
const TAG_SCRIPT: &[u8] = b"DFLT";
const TAG_FEATURE: &[u8] = b"kern";
/// OpenType lookup type 2: pair adjustment.
const LOOKUP_PAIR_ADJUSTMENT: u16 = 2;
/// OpenType lookup type 9: extension positioning (Offset32 subtables).
const LOOKUP_EXTENSION: u16 = 9;
/// ValueFormat bit for xAdvance.
const VALUE_FORMAT_X_ADVANCE: u16 = 0x0004;

/// Big-endian uint16 words.
fn words(v: &[u16]) -> Vec<u8> {
    v.iter().flat_map(|w| w.to_be_bytes()).collect()
}

fn count16(what: &'static str, n: usize) -> Result<u16, GposWriteError> {
    u16::try_from(n).map_err(|_| GposWriteError::CountOverflow { what, count: n })
}

fn off16(what: &'static str, n: usize) -> Result<u16, GposWriteError> {
    u16::try_from(n).map_err(|_| GposWriteError::OffsetOverflow { what, offset: n })
}

/// Validate, sort and group. Input order never reaches the output.
fn group(
    num_glyphs: u16,
    pairs: &[PairKern],
) -> Result<BTreeMap<u16, BTreeMap<u16, i16>>, GposWriteError> {
    if pairs.is_empty() {
        return Err(GposWriteError::NoPairs);
    }
    let mut groups: BTreeMap<u16, BTreeMap<u16, i16>> = BTreeMap::new();
    for p in pairs {
        for g in [p.left, p.right] {
            if g >= num_glyphs {
                return Err(GposWriteError::GlyphOutOfRange { glyph: g, num_glyphs });
            }
        }
        let v = i16::try_from(p.x_advance).map_err(|_| GposWriteError::ValueOutOfRange {
            left: p.left,
            right: p.right,
            x_advance: p.x_advance,
        })?;
        if let Some(prev) = groups.entry(p.left).or_default().insert(p.right, v) {
            return Err(if prev == v {
                GposWriteError::DuplicatePair { left: p.left, right: p.right, x_advance: v }
            } else {
                GposWriteError::ConflictingPair { left: p.left, right: p.right, first: prev, second: v }
            });
        }
    }
    Ok(groups)
}

/// PairPos Format 1 subtable; every offset is relative to the subtable start.
fn pair_pos_subtable(groups: &BTreeMap<u16, BTreeMap<u16, i16>>) -> Result<Vec<u8>, GposWriteError> {
    let set_count = count16("pair set count", groups.len())?;
    // posFormat, coverageOffset, valueFormat1, valueFormat2, pairSetCount
    let fixed = |coverage_offset: u16| words(&[1, coverage_offset, VALUE_FORMAT_X_ADVANCE, 0, set_count]);
    let header_len = fixed(0).len() + U16_LEN * groups.len();
    let mut sets: Vec<u8> = Vec::new();
    let mut set_offsets: Vec<u16> = Vec::new();
    for recs in groups.values() {
        set_offsets.push(off16("pair set offset", header_len + sets.len())?);
        sets.extend_from_slice(&words(&[count16("pair value count", recs.len())?]));
        for (&right, &v) in recs {
            // PairValueRecord: secondGlyph, then the int16 xAdvance bits.
            sets.extend_from_slice(&words(&[right, v as u16]));
        }
    }
    let coverage_offset = off16("coverage offset", header_len + sets.len())?;
    let mut out = fixed(coverage_offset);
    out.extend_from_slice(&words(&set_offsets));
    out.extend_from_slice(&sets);
    // Coverage format 1: ascending left glyph ids.
    out.extend_from_slice(&words(&[1, set_count]));
    let lefts: Vec<u16> = groups.keys().copied().collect();
    out.extend_from_slice(&words(&lefts));
    Ok(out)
}

/// ScriptList with one DFLT record whose default LangSys lists feature 0.
fn script_list() -> Result<Vec<u8>, GposWriteError> {
    // LangSys: lookupOrder (null), requiredFeatureIndex (none), count, index
    let lang_sys = words(&[0, u16::MAX, 1, 0]);
    // Script: defaultLangSysOffset, langSysCount; the LangSys follows directly.
    let script_head = words(&[0, 0]).len();
    let mut script = words(&[off16("default langsys offset", script_head)?, 0]);
    script.extend_from_slice(&lang_sys);
    // ScriptList: count, record = tag + offset; the Script follows the record.
    let record_end = U16_LEN + TAG_SCRIPT.len() + U16_LEN;
    let mut out = words(&[1]);
    out.extend_from_slice(TAG_SCRIPT);
    out.extend_from_slice(&words(&[off16("script offset", record_end)?]));
    out.extend_from_slice(&script);
    Ok(out)
}

/// FeatureList with one 'kern' feature that lists lookup 0.
fn feature_list() -> Result<Vec<u8>, GposWriteError> {
    // Feature: featureParams (null), lookupIndexCount, lookupListIndex
    let feature = words(&[0, 1, 0]);
    let record_end = U16_LEN + TAG_FEATURE.len() + U16_LEN;
    let mut out = words(&[1]);
    out.extend_from_slice(TAG_FEATURE);
    out.extend_from_slice(&words(&[off16("feature offset", record_end)?]));
    out.extend_from_slice(&feature);
    Ok(out)
}

/// Split into pair groups that each fit one PairPos format 1 subtable: the
/// coverage offset (the largest offset in the subtable) must stay within
/// Offset16. Sorted order is kept; a left glyph with too many right glyphs is
/// continued in the next subtable. Sizes are derived from the layout itself.
fn partition(groups: &BTreeMap<u16, BTreeMap<u16, i16>>) -> Vec<BTreeMap<u16, BTreeMap<u16, i16>>> {
    let fixed_len = words(&[1, 0, 0, 0, 0]).len();
    let record_len = U16_LEN + U16_LEN;
    let limit = usize::from(u16::MAX);
    let mut parts = vec![];
    let mut cur: BTreeMap<u16, BTreeMap<u16, i16>> = BTreeMap::new();
    let mut sets_len = 0usize;
    for (&left, recs) in groups {
        for (&right, &v) in recs {
            let new_set = !cur.contains_key(&left);
            let grow = record_len + if new_set { U16_LEN + U16_LEN } else { 0 };
            let sets_after = sets_len + grow;
            let header_after = fixed_len + U16_LEN * (cur.len() + usize::from(new_set));
            if !cur.is_empty() && header_after + sets_after > limit {
                parts.push(std::mem::take(&mut cur));
                sets_len = 0;
            }
            let new_set = !cur.contains_key(&left);
            sets_len += record_len + if new_set { U16_LEN + U16_LEN } else { 0 };
            cur.entry(left).or_default().insert(right, v);
        }
    }
    if !cur.is_empty() {
        parts.push(cur);
    }
    parts
}

/// LookupList with one lookup owning all subtables. Plain type 2 while the
/// subtable offsets fit Offset16 from the lookup; otherwise a type 9 lookup
/// whose Extension records point at the subtables with Offset32.
fn lookup_list(subtables: &[Vec<u8>]) -> Result<Vec<u8>, GposWriteError> {
    let k = count16("subtable count", subtables.len())?;
    let list_head = words(&[0, 0]).len();
    let lookup_head = words(&[0, 0, 0]).len() + U16_LEN * subtables.len();
    // Plain layout: offsets are cumulative from the lookup start.
    let mut plain_offsets = Vec::new();
    let mut at = lookup_head;
    let mut plain_ok = true;
    for st in subtables {
        match u16::try_from(at) {
            Ok(o) => plain_offsets.push(o),
            Err(_) => {
                plain_ok = false;
                break;
            }
        }
        at += st.len();
    }
    let mut lookup;
    if plain_ok {
        lookup = words(&[LOOKUP_PAIR_ADJUSTMENT, 0, k]);
        lookup.extend_from_slice(&words(&plain_offsets));
        for st in subtables {
            lookup.extend_from_slice(st);
        }
    } else {
        // Extension: Lookup -> k ExtensionPosFormat1 records -> subtables.
        let ext_len = words(&[0, 0]).len() + size_of::<u32>();
        let mut ext_offsets = Vec::new();
        for i in 0..subtables.len() {
            ext_offsets.push(off16("extension record offset", lookup_head + i * ext_len)?);
        }
        lookup = words(&[LOOKUP_EXTENSION, 0, k]);
        lookup.extend_from_slice(&words(&ext_offsets));
        let data_at = lookup_head + ext_len * subtables.len();
        let mut data = Vec::new();
        for (i, st) in subtables.iter().enumerate() {
            // Offset32 is relative to the start of this extension record.
            let rel = data_at + data.len() - (lookup_head + i * ext_len);
            let rel32 = u32::try_from(rel)
                .map_err(|_| GposWriteError::OffsetOverflow { what: "extension offset", offset: rel })?;
            lookup.extend_from_slice(&words(&[1, LOOKUP_PAIR_ADJUSTMENT]));
            lookup.extend_from_slice(&rel32.to_be_bytes());
            data.extend_from_slice(st);
        }
        lookup.extend_from_slice(&data);
    }
    // LookupList: lookupCount, one offset; the Lookup follows directly.
    let mut out = words(&[1, off16("lookup offset", list_head)?]);
    out.extend_from_slice(&lookup);
    Ok(out)
}

/// Serialize a GPOS table (version 1.0) carrying exactly the given kern pairs.
/// `num_glyphs` is the font's glyph count; every glyph id must be below it.
/// An empty pair list is `Err(NoPairs)`; use `write_kern_pairpos1_or_omit`
/// when "no pairs" means "write no GPOS table".
pub fn write_kern_pairpos1(num_glyphs: u16, pairs: &[PairKern]) -> Result<Vec<u8>, GposWriteError> {
    let groups = group(num_glyphs, pairs)?;
    let subtables = partition(&groups)
        .iter()
        .map(pair_pos_subtable)
        .collect::<Result<Vec<_>, _>>()?;
    let scripts = script_list()?;
    let features = feature_list()?;
    let lookups = lookup_list(&subtables)?;
    // Header: major, minor, scriptListOffset, featureListOffset, lookupListOffset.
    let header = |s: u16, f: u16, l: u16| words(&[1, 0, s, f, l]);
    let scripts_at = header(0, 0, 0).len();
    let features_at = scripts_at + scripts.len();
    let lookups_at = features_at + features.len();
    let mut out = header(
        off16("script list offset", scripts_at)?,
        off16("feature list offset", features_at)?,
        off16("lookup list offset", lookups_at)?,
    );
    out.extend_from_slice(&scripts);
    out.extend_from_slice(&features);
    out.extend_from_slice(&lookups);
    Ok(out)
}

/// Same as `write_kern_pairpos1`, but an empty pair list yields `Ok(None)`
/// (the caller then writes no GPOS table). Every other refusal is unchanged.
pub fn write_kern_pairpos1_or_omit(num_glyphs: u16, pairs: &[PairKern]) -> Result<Option<Vec<u8>>, GposWriteError> {
    if pairs.is_empty() {
        return Ok(None);
    }
    write_kern_pairpos1(num_glyphs, pairs).map(Some)
}

/// Error policy for the GPOS kern writer. `OmitTable` (the default) is the
/// established behavior: any writer error omits the whole table.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum GposErrorPolicy {
    /// Any writer error omits the whole GPOS table (established behavior;
    /// bit-identical to `write_kern_pairpos1_or_omit` + the `kern_omitted`
    /// receipt line).
    #[default]
    OmitTable,
    /// Errors that name culprit pair(s) exclude only those pairs and retry
    /// with the remainder (the `solve_spacing_excluding_culprits` pattern):
    /// one bad pair no longer drops the whole table. Structural errors that
    /// name no pair (`NoPairs`, `CountOverflow`, `OffsetOverflow`) still omit
    /// the table. Terminates: every retry removes at least one pair.
    ExcludeCulpritPairs,
}

/// One excluded kern pair: (left, right, typed reason token). Reason tokens
/// are variant identities, never stringified payloads (receipt contract).
pub type GposPairExclusion = (u16, u16, &'static str);

/// Typed outcome of a policy-gated GPOS write.
#[derive(Debug)]
pub struct GposDegrade {
    /// The written table (None = no GPOS table emitted).
    pub table: Option<Vec<u8>>,
    /// Pairs excluded under `ExcludeCulpritPairs`, in removal order.
    pub excluded: Vec<GposPairExclusion>,
    /// Set when the table was omitted on a writer error (always the case for
    /// `OmitTable`; for `ExcludeCulpritPairs` only when the error names no
    /// excludable pair). None when the write succeeded, or when every
    /// remaining pair was excluded (an empty pair set emits no table and is
    /// not an error).
    pub omitted: Option<GposWriteError>,
}

impl GposDegrade {
    /// Receipt rows for the audit trail (same role as the existing
    /// `warning	kern_row_unbound` and `kern_omitted` lines). None when the
    /// write was clean. The `kern_omitted` row is byte-identical to the one
    /// the established degrade path emits.
    pub fn receipt(&self) -> Option<String> {
        if self.excluded.is_empty() && self.omitted.is_none() {
            return None;
        }
        let mut s = String::new();
        for (left, right, reason) in &self.excluded {
            s.push_str(&format!("warning	kern_pair_excluded	pair	{left}->{right}	reason	{reason}
"));
        }
        if let Some(e) = &self.omitted {
            s.push_str(&format!("kern_omitted	true	reason	gpos_writer_error	{e:?}	(GPOS writer failed; font exported without GPOS kerning)
"));
        } else if !self.excluded.is_empty() {
            s.push_str(&format!("kern_gpos	pairs_excluded	{}	policy	exclude_culprit_pairs
", self.excluded.len()));
        }
        Some(s)
    }
}

/// Indices of the pairs an error blames, plus the typed reason token.
/// `DuplicatePair`/`ConflictingPair` keep the FIRST input occurrence and drop
/// the rest (deterministic for a deterministic input order). Returns None for
/// structural errors that name no pair.
fn culprit_removals(e: &GposWriteError, pairs: &[PairKern]) -> Option<(Vec<usize>, &'static str)> {
    match e {
        GposWriteError::ValueOutOfRange { left, right, .. } => Some((
            pairs.iter().enumerate().filter(|(_, p)| p.left == *left && p.right == *right).map(|(i, _)| i).collect(),
            "value_out_of_range",
        )),
        GposWriteError::DuplicatePair { left, right, .. } | GposWriteError::ConflictingPair { left, right, .. } => {
            let reason = if matches!(e, GposWriteError::DuplicatePair { .. }) { "duplicate_pair" } else { "conflicting_pair" };
            let mut kept = false;
            let mut idx = Vec::new();
            for (i, p) in pairs.iter().enumerate() {
                if p.left == *left && p.right == *right {
                    if kept { idx.push(i); } else { kept = true; }
                }
            }
            Some((idx, reason))
        }
        GposWriteError::GlyphOutOfRange { glyph, .. } => Some((
            pairs.iter().enumerate().filter(|(_, p)| p.left == *glyph || p.right == *glyph).map(|(i, _)| i).collect(),
            "glyph_out_of_range",
        )),
        GposWriteError::NoPairs | GposWriteError::CountOverflow { .. } | GposWriteError::OffsetOverflow { .. } => None,
    }
}

/// Policy-gated GPOS write. With `OmitTable` this reproduces
/// `write_kern_pairpos1_or_omit` exactly. With `ExcludeCulpritPairs`,
/// pair-naming errors exclude the culprit pairs and retry; errors naming no
/// pair fall back to whole-table omission.
pub fn write_kern_pairpos1_with_policy(num_glyphs: u16, pairs: &[PairKern], policy: GposErrorPolicy) -> GposDegrade {
    match policy {
        GposErrorPolicy::OmitTable => match write_kern_pairpos1_or_omit(num_glyphs, pairs) {
            Ok(table) => GposDegrade { table, excluded: Vec::new(), omitted: None },
            Err(e) => GposDegrade { table: None, excluded: Vec::new(), omitted: Some(e) },
        },
        GposErrorPolicy::ExcludeCulpritPairs => {
            let mut live: Vec<PairKern> = pairs.to_vec();
            let mut excluded: Vec<GposPairExclusion> = Vec::new();
            loop {
                match write_kern_pairpos1_or_omit(num_glyphs, &live) {
                    Ok(table) => return GposDegrade { table, excluded, omitted: None },
                    Err(e) => {
                        let Some((idx, reason)) = culprit_removals(&e, &live) else {
                            return GposDegrade { table: None, excluded, omitted: Some(e) };
                        };
                        if idx.is_empty() {
                            // no removal possible -> cannot make progress; omit the table
                            return GposDegrade { table: None, excluded, omitted: Some(e) };
                        }
                        let mut drop = vec![false; live.len()];
                        for &i in &idx {
                            drop[i] = true;
                            excluded.push((live[i].left, live[i].right, reason));
                        }
                        live = live.into_iter().enumerate().filter(|(i, _)| !drop[*i]).map(|(_, p)| p).collect();
                    }
                }
            }
        }
    }
}

/// Drop-in for the established composition
/// `gpos_or_omit_on_error(write_kern_pairpos1_or_omit(num_glyphs, pairs))` in
/// main.rs: same `(table, receipt_line)` shape. With `OmitTable` the result
/// is bit-identical; with `ExcludeCulpritPairs` culprit pairs are excluded
/// and the table still ships.
pub fn write_kern_with_policy(num_glyphs: u16, pairs: &[PairKern], policy: GposErrorPolicy) -> (Option<Vec<u8>>, Option<String>) {
    let d = write_kern_pairpos1_with_policy(num_glyphs, pairs, policy);
    let receipt = d.receipt();
    (d.table, receipt)
}
#[cfg(test)]
mod tests {
    use super::*;

    const TEST_NUM_GLYPHS: u16 = 40;
    const TEST_LEFT_A: u16 = 3;
    const TEST_LEFT_B: u16 = 17;
    const TEST_RIGHT_A: u16 = 5;
    const TEST_RIGHT_B: u16 = 9;
    const TEST_KERN_NEG: i32 = -10;
    const TEST_KERN_POS: i32 = 25;
    const TEST_MANY_RIGHTS: u16 = 20000;
    const TEST_WIDE: u16 = 300;
    const TEST_PLAIN_LEFTS: u16 = 20;
    const TEST_PLAIN_RIGHTS: u16 = 2000;

    fn pk(left: u16, right: u16, x: i32) -> PairKern {
        PairKern { left, right, x_advance: x }
    }

    // Independent reader: walks the tables by their offsets and returns the
    // pairs, checking bounds, ordering and the single-lookup layout.
    fn rd(b: &[u8], at: usize) -> u16 {
        u16::from_be_bytes([b[at], b[at + 1]])
    }

    fn parse(b: &[u8]) -> Vec<(u16, u16, i16)> {
        assert_eq!((rd(b, 0), rd(b, 2)), (1, 0), "GPOS version 1.0");
        let (sl, fl, ll) = (rd(b, 4) as usize, rd(b, 6) as usize, rd(b, 8) as usize);
        assert_eq!(rd(b, sl), 1, "one script");
        assert_eq!(&b[sl + 2..sl + 6], b"DFLT");
        let script = sl + rd(b, sl + 6) as usize;
        let lang = script + rd(b, script) as usize;
        assert_eq!(rd(b, script + 2), 0, "no non-default LangSys");
        assert_eq!((rd(b, lang), rd(b, lang + 2), rd(b, lang + 4), rd(b, lang + 6)), (0, u16::MAX, 1, 0));
        assert_eq!(rd(b, fl), 1, "one feature");
        assert_eq!(&b[fl + 2..fl + 6], b"kern");
        let feat = fl + rd(b, fl + 6) as usize;
        assert_eq!((rd(b, feat), rd(b, feat + 2), rd(b, feat + 4)), (0, 1, 0));
        assert_eq!(rd(b, ll), 1, "one lookup");
        let look = ll + rd(b, ll + 2) as usize;
        let (ltype, k) = (rd(b, look), rd(b, look + 4) as usize);
        assert_eq!(rd(b, look + 2), 0, "no lookup flags");
        assert!(ltype == 2 || ltype == 9, "plain or extension");
        let mut out = vec![];
        for s in 0..k {
            let mut sub = look + rd(b, look + 6 + 2 * s) as usize;
            if ltype == 9 {
                assert_eq!((rd(b, sub), rd(b, sub + 2)), (1, 2), "ExtensionPosFormat1 wrapping type 2");
                let off = u32::from_be_bytes([b[sub + 4], b[sub + 5], b[sub + 6], b[sub + 7]]) as usize;
                sub += off;
            }
            out.extend(parse_subtable(b, sub));
        }
        let mut sorted = out.clone();
        sorted.sort();
        sorted.dedup_by_key(|t| (t.0, t.1));
        assert_eq!(sorted.len(), out.len(), "a pair appears in exactly one subtable");
        out
    }

    fn parse_subtable(b: &[u8], sub: usize) -> Vec<(u16, u16, i16)> {
        assert_eq!(rd(b, sub), 1, "PairPos format 1");
        assert_eq!((rd(b, sub + 4), rd(b, sub + 6)), (4, 0), "xAdvance only");
        let n = rd(b, sub + 8) as usize;
        let cov = sub + rd(b, sub + 2) as usize;
        assert_eq!((rd(b, cov), rd(b, cov + 2) as usize), (1, n));
        let mut out = vec![];
        let mut prev_left = None;
        for i in 0..n {
            let left = rd(b, cov + 4 + 2 * i);
            assert!(prev_left.map_or(true, |p| p < left), "coverage ascending");
            prev_left = Some(left);
            let set = sub + rd(b, sub + 10 + 2 * i) as usize;
            let m = rd(b, set) as usize;
            let mut prev_right = None;
            for j in 0..m {
                let right = rd(b, set + 2 + 4 * j);
                assert!(prev_right.map_or(true, |p| p < right), "records ascending");
                prev_right = Some(right);
                out.push((left, right, rd(b, set + 4 + 4 * j) as i16));
            }
        }
        out
    }

    fn lookup_type(b: &[u8]) -> u16 {
        let ll = rd(b, 8) as usize;
        rd(b, ll + rd(b, ll + 2) as usize)
    }

    fn subtable_count(b: &[u8]) -> u16 {
        let ll = rd(b, 8) as usize;
        rd(b, ll + rd(b, ll + 2) as usize + 4)
    }

    #[test]
    fn golden_single_pair_is_hand_assembled() {
        let got = write_kern_pairpos1(3, &[pk(1, 2, TEST_KERN_NEG)]).unwrap();
        // Hand-assembled from the OpenType GPOS layout: header, ScriptList,
        // FeatureList, LookupList with one PairPos format 1 subtable.
        let mut want: Vec<u8> = vec![];
        want.extend_from_slice(&[0, 1, 0, 0, 0, 10, 0, 30, 0, 44]);
        want.extend_from_slice(&[0, 1]);
        want.extend_from_slice(b"DFLT");
        want.extend_from_slice(&[0, 8, 0, 4, 0, 0, 0, 0, 0xFF, 0xFF, 0, 1, 0, 0]);
        want.extend_from_slice(&[0, 1]);
        want.extend_from_slice(b"kern");
        want.extend_from_slice(&[0, 8, 0, 0, 0, 1, 0, 0]);
        want.extend_from_slice(&[0, 1, 0, 4, 0, 2, 0, 0, 0, 1, 0, 8]);
        want.extend_from_slice(&[0, 1, 0, 18, 0, 4, 0, 0, 0, 1, 0, 12]);
        want.extend_from_slice(&[0, 1, 0, 2, 0xFF, 0xF6]);
        want.extend_from_slice(&[0, 1, 0, 1, 0, 1]);
        assert_eq!(got, want);
    }

    #[test]
    fn output_is_independent_of_input_order_and_keeps_zero() {
        let a = [pk(TEST_LEFT_B, TEST_RIGHT_B, TEST_KERN_POS), pk(TEST_LEFT_A, TEST_RIGHT_B, 0), pk(TEST_LEFT_A, TEST_RIGHT_A, TEST_KERN_NEG)];
        let mut b = a;
        b.reverse();
        let (x, y) = (write_kern_pairpos1(TEST_NUM_GLYPHS, &a).unwrap(), write_kern_pairpos1(TEST_NUM_GLYPHS, &b).unwrap());
        assert_eq!(x, y);
        assert_eq!(
            parse(&x),
            vec![
                (TEST_LEFT_A, TEST_RIGHT_A, TEST_KERN_NEG as i16),
                (TEST_LEFT_A, TEST_RIGHT_B, 0),
                (TEST_LEFT_B, TEST_RIGHT_B, TEST_KERN_POS as i16),
            ]
        );
    }

    #[test]
    fn glyph_range_is_checked_at_the_boundary() {
        let last = TEST_NUM_GLYPHS - 1;
        assert!(write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(last, last, 0)]).is_ok());
        assert_eq!(
            write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(TEST_NUM_GLYPHS, 0, 0)]),
            Err(GposWriteError::GlyphOutOfRange { glyph: TEST_NUM_GLYPHS, num_glyphs: TEST_NUM_GLYPHS })
        );
        assert_eq!(
            write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(0, TEST_NUM_GLYPHS, 0)]),
            Err(GposWriteError::GlyphOutOfRange { glyph: TEST_NUM_GLYPHS, num_glyphs: TEST_NUM_GLYPHS })
        );
    }

    #[test]
    fn value_range_is_int16() {
        assert!(write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(0, 1, i32::from(i16::MAX)), pk(0, 2, i32::from(i16::MIN))]).is_ok());
        let over = i32::from(i16::MAX) + 1;
        assert_eq!(
            write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(0, 1, over)]),
            Err(GposWriteError::ValueOutOfRange { left: 0, right: 1, x_advance: over })
        );
        assert!(write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(0, 1, i32::from(i16::MIN) - 1)]).is_err());
    }

    #[test]
    fn duplicate_and_conflict_are_distinct_refusals() {
        assert_eq!(
            write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(1, 2, TEST_KERN_NEG), pk(1, 2, TEST_KERN_NEG)]),
            Err(GposWriteError::DuplicatePair { left: 1, right: 2, x_advance: TEST_KERN_NEG as i16 })
        );
        assert_eq!(
            write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(1, 2, TEST_KERN_NEG), pk(1, 2, TEST_KERN_POS)]),
            Err(GposWriteError::ConflictingPair { left: 1, right: 2, first: TEST_KERN_NEG as i16, second: TEST_KERN_POS as i16 })
        );
        // (1,2) and (2,1) are different pairs.
        assert!(write_kern_pairpos1(TEST_NUM_GLYPHS, &[pk(1, 2, TEST_KERN_NEG), pk(2, 1, TEST_KERN_POS)]).is_ok());
    }

    #[test]
    fn empty_input_is_refused() {
        assert_eq!(write_kern_pairpos1(TEST_NUM_GLYPHS, &[]), Err(GposWriteError::NoPairs));
    }

    #[test]
    fn one_left_with_too_many_rights_splits_into_extension_subtables() {
        let many: Vec<PairKern> = (0..TEST_MANY_RIGHTS).map(|r| pk(1, r, TEST_KERN_NEG)).collect();
        let bytes = write_kern_pairpos1(u16::MAX, &many).unwrap();
        assert!(subtable_count(&bytes) >= 2, "split by size");
        assert_eq!(lookup_type(&bytes), 9, "offsets no longer fit Offset16, so Extension");
        let got = parse(&bytes);
        assert_eq!(got.len(), many.len());
        assert!(got.iter().all(|&(l, _, v)| l == 1 && i32::from(v) == TEST_KERN_NEG));
    }

    #[test]
    fn many_lefts_split_and_nothing_is_dropped() {
        let mut input = vec![];
        for l in 0..TEST_WIDE {
            for r in 0..TEST_WIDE {
                input.push(pk(l, r, (i32::from(l) + i32::from(r)) % TEST_KERN_POS - TEST_KERN_POS / 2));
            }
        }
        let bytes = write_kern_pairpos1(TEST_WIDE, &input).unwrap();
        assert!(subtable_count(&bytes) >= 2);
        let mut want: Vec<(u16, u16, i16)> = input.iter().map(|p| (p.left, p.right, p.x_advance as i16)).collect();
        want.sort();
        let mut got = parse(&bytes);
        got.sort();
        assert_eq!(got, want);
    }

    #[test]
    fn small_tables_stay_one_plain_subtable() {
        let fit: Vec<PairKern> = (0..TEST_NUM_GLYPHS).map(|r| pk(1, r, TEST_KERN_POS)).collect();
        let bytes = write_kern_pairpos1(TEST_NUM_GLYPHS, &fit).unwrap();
        assert_eq!((lookup_type(&bytes), subtable_count(&bytes)), (2, 1));
        assert_eq!(parse(&bytes).len(), fit.len());
    }

    #[test]
    fn more_than_one_subtable_always_means_extension() {
        // A subtable is filled to the Offset16 limit before the next one starts,
        // so the second subtable cannot be reached by a plain Offset16.
        let mut input = vec![];
        for l in 0..TEST_PLAIN_LEFTS {
            for r in 0..TEST_PLAIN_RIGHTS {
                input.push(pk(l, r, TEST_KERN_NEG));
            }
        }
        let bytes = write_kern_pairpos1(u16::MAX, &input).unwrap();
        assert!(subtable_count(&bytes) >= 2);
        assert_eq!(lookup_type(&bytes), 9);
        assert_eq!(parse(&bytes).len(), input.len());
    }

    #[test]
    fn omit_helper_maps_only_empty_to_none() {
        assert_eq!(write_kern_pairpos1_or_omit(TEST_NUM_GLYPHS, &[]), Ok(None));
        assert!(write_kern_pairpos1_or_omit(TEST_NUM_GLYPHS, &[pk(0, 1, 0)]).unwrap().is_some());
        assert_eq!(
            write_kern_pairpos1_or_omit(TEST_NUM_GLYPHS, &[pk(TEST_NUM_GLYPHS, 0, 0)]),
            Err(GposWriteError::GlyphOutOfRange { glyph: TEST_NUM_GLYPHS, num_glyphs: TEST_NUM_GLYPHS })
        );
    }

    #[test]
    fn round_trip_dense_table() {
        let mut input = vec![];
        for l in 0..TEST_NUM_GLYPHS {
            for r in (0..TEST_NUM_GLYPHS).step_by(3) {
                input.push(pk(l, r, (i32::from(l) - i32::from(r)) * TEST_KERN_NEG));
            }
        }
        let bytes = write_kern_pairpos1(TEST_NUM_GLYPHS, &input).unwrap();
        let mut want: Vec<(u16, u16, i16)> = input.iter().map(|p| (p.left, p.right, p.x_advance as i16)).collect();
        want.sort();
        assert_eq!(parse(&bytes), want);
    }
    #[test]
    fn policy_omit_table_is_bit_identical_to_or_omit() {
        let pairs = [pk(TEST_LEFT_A, TEST_RIGHT_A, TEST_KERN_NEG), pk(TEST_LEFT_B, TEST_RIGHT_B, TEST_KERN_POS)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &pairs, GposErrorPolicy::OmitTable);
        assert!(d.excluded.is_empty() && d.omitted.is_none());
        assert_eq!(d.table.unwrap(), write_kern_pairpos1(TEST_NUM_GLYPHS, &pairs).unwrap());
        // error path: same omission and byte-identical kern_omitted line
        let over = i32::from(i16::MAX) + 1;
        let bad = [pk(TEST_LEFT_A, TEST_RIGHT_A, over)];
        let (t, line) = write_kern_with_policy(TEST_NUM_GLYPHS, &bad, GposErrorPolicy::OmitTable);
        assert!(t.is_none());
        assert_eq!(
            line.unwrap(),
            format!("kern_omitted	true	reason	gpos_writer_error	{:?}	(GPOS writer failed; font exported without GPOS kerning)
",
                GposWriteError::ValueOutOfRange { left: TEST_LEFT_A, right: TEST_RIGHT_A, x_advance: over })
        );
        // empty input: no table, no line
        let (t, line) = write_kern_with_policy(TEST_NUM_GLYPHS, &[], GposErrorPolicy::OmitTable);
        assert!(t.is_none() && line.is_none());
    }

    #[test]
    fn exclude_culprit_pairs_keeps_good_pairs() {
        let over = i32::from(i16::MAX) + 1;
        let pairs = [pk(TEST_LEFT_A, TEST_RIGHT_A, TEST_KERN_NEG), pk(TEST_LEFT_B, TEST_RIGHT_B, over)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &pairs, GposErrorPolicy::ExcludeCulpritPairs);
        assert!(d.omitted.is_none());
        assert_eq!(d.excluded, vec![(TEST_LEFT_B, TEST_RIGHT_B, "value_out_of_range")]);
        assert_eq!(parse(&d.table.unwrap()), vec![(TEST_LEFT_A, TEST_RIGHT_A, TEST_KERN_NEG as i16)]);
    }

    #[test]
    fn exclude_duplicate_and_conflicting_keep_first_occurrence() {
        let dup = [pk(1, 2, TEST_KERN_NEG), pk(1, 2, TEST_KERN_NEG), pk(3, 4, TEST_KERN_POS)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &dup, GposErrorPolicy::ExcludeCulpritPairs);
        assert_eq!(d.excluded, vec![(1, 2, "duplicate_pair")]);
        let mut got = parse(&d.table.unwrap());
        got.sort();
        assert_eq!(got, vec![(1, 2, TEST_KERN_NEG as i16), (3, 4, TEST_KERN_POS as i16)]);
        let confl = [pk(1, 2, TEST_KERN_NEG), pk(1, 2, TEST_KERN_POS), pk(3, 4, 7)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &confl, GposErrorPolicy::ExcludeCulpritPairs);
        assert_eq!(d.excluded, vec![(1, 2, "conflicting_pair")]);
        let mut got = parse(&d.table.unwrap());
        got.sort();
        assert_eq!(got, vec![(1, 2, TEST_KERN_NEG as i16), (3, 4, 7)]);
    }

    #[test]
    fn exclude_glyph_out_of_range_drops_pairs_referencing_it() {
        let pairs = [pk(1, 2, TEST_KERN_NEG), pk(TEST_NUM_GLYPHS, 0, 5), pk(0, TEST_NUM_GLYPHS, 5)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &pairs, GposErrorPolicy::ExcludeCulpritPairs);
        assert!(d.omitted.is_none());
        assert_eq!(d.excluded.len(), 2);
        assert!(d.excluded.iter().all(|e| e.2 == "glyph_out_of_range"));
        assert_eq!(parse(&d.table.unwrap()), vec![(1, 2, TEST_KERN_NEG as i16)]);
    }

    #[test]
    fn all_pairs_excluded_yields_no_table_not_an_error() {
        let over = i32::from(i16::MAX) + 1;
        let pairs = [pk(1, 2, over), pk(1, 3, over)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &pairs, GposErrorPolicy::ExcludeCulpritPairs);
        assert!(d.table.is_none() && d.omitted.is_none());
        assert_eq!(d.excluded.len(), 2);
        let rc = d.receipt().unwrap();
        assert!(rc.contains("kern_pair_excluded	pair	1->2	reason	value_out_of_range"));
        assert!(rc.contains("kern_gpos	pairs_excluded	2	policy	exclude_culprit_pairs"));
        assert!(!rc.contains("kern_omitted"));
    }

    #[test]
    fn receipt_lines_for_partial_exclusion_and_clean_run() {
        let over = i32::from(i16::MAX) + 1;
        let pairs = [pk(1, 2, TEST_KERN_NEG), pk(3, 4, over)];
        let d = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &pairs, GposErrorPolicy::ExcludeCulpritPairs);
        let rc = d.receipt().unwrap();
        assert!(rc.contains("warning	kern_pair_excluded	pair	3->4	reason	value_out_of_range
"));
        assert!(rc.contains("kern_gpos	pairs_excluded	1	policy	exclude_culprit_pairs
"));
        let ok = write_kern_pairpos1_with_policy(TEST_NUM_GLYPHS, &[pk(1, 2, TEST_KERN_NEG)], GposErrorPolicy::ExcludeCulpritPairs);
        assert!(ok.receipt().is_none());
    }
}
