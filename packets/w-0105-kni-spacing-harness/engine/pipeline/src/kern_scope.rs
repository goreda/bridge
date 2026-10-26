//! Owner scope "kerning_letters": +LSB/RSB applies only to glyphs that are (a) Unicode 17.0.0 General_Category L* (every mapped
//! codepoint, pinned table in unicode_marks.rs) AND (b) actual participants (left OR right) of a NONZERO pair-kern value in the
//! emitted baseline GPOS bytes, read back here. Implicit/zero pairs, dropped/held/rejected pairs (not in the GPOS), space, .notdef,
//! marks, digits, punctuation and symbols are never eligible, even when they appear in GPOS. Eligibility is computed once from the
//! approved baseline (before +LSB/RSB); there is no iteration. The result feeds `post_metrics::post_pass` as an explicit allow-list.
use crate::unicode_marks;
use std::collections::BTreeSet;

pub const POLICY_ID: &str = "kerning_letters";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KernScopeError { Gpos(String), Gsub(String), Shape(&'static str), EmptySelection }

fn u16at(b: &[u8], o: usize) -> Result<u16, KernScopeError> {
    b.get(o..o.checked_add(2).ok_or(KernScopeError::Gpos("offset overflow".into()))?).map(|x| u16::from_be_bytes([x[0], x[1]])).ok_or(KernScopeError::Gpos(format!("truncated at {o}")))
}
fn u32at(b: &[u8], o: usize) -> Result<u32, KernScopeError> {
    b.get(o..o.checked_add(4).ok_or(KernScopeError::Gpos("offset overflow".into()))?).map(|x| u32::from_be_bytes([x[0], x[1], x[2], x[3]])).ok_or(KernScopeError::Gpos(format!("truncated at {o}")))
}
/// Coverage format 1 only (format 2 is an honest refusal). Every count is bounded BEFORE any allocation or loop.
fn coverage(b: &[u8], o: usize, num_glyphs: usize) -> Result<Vec<u16>, KernScopeError> {
    if u16at(b, o)? != 1 { return Err(KernScopeError::Gpos("coverage format other than 1 is not supported".into())); }
    let n = u16at(b, o + 2)? as usize;
    if n == 0 || n > num_glyphs || o + 4 + 2 * n > b.len() { return Err(KernScopeError::Gpos("coverage count outside the font / table".into())); }
    let mut v = Vec::with_capacity(n);
    for i in 0..n {
        let g = u16at(b, o + 4 + 2 * i)?;
        if usize::from(g) >= num_glyphs || v.last().map_or(false, |p| *p >= g) { return Err(KernScopeError::Gpos("coverage not strictly increasing / outside the font".into())); }
        v.push(g);
    }
    Ok(v)
}
/// All (left, right, xAdvance) triples of one PairPos format 1 subtable whose valueFormat1 is exactly xAdvance and valueFormat2 is 0.
fn pair_pos(b: &[u8], st: usize, num_glyphs: usize, out: &mut Vec<(u16, u16, i16)>) -> Result<(), KernScopeError> {
    if u16at(b, st)? != 1 { return Err(KernScopeError::Gpos("PairPos format other than 1 is not supported (no silent skip)".into())); }
    let cov = coverage(b, st + usize::from(u16at(b, st + 2)?), num_glyphs)?;
    let (f1, f2, n) = (u16at(b, st + 4)?, u16at(b, st + 6)?, u16at(b, st + 8)? as usize);
    if f1 != 4 || f2 != 0 { return Err(KernScopeError::Gpos("valueFormat1/2 are not the canonical xAdvance-only 0x0004/0".into())); }
    if n != cov.len() { return Err(KernScopeError::Gpos("pairSetCount != coverage count".into())); }
    for (i, left) in cov.iter().enumerate() {
        let ps = st + usize::from(u16at(b, st + 10 + 2 * i)?);
        let cnt = u16at(b, ps)? as usize;
        if cnt == 0 || cnt > num_glyphs || ps + 2 + 4 * cnt > b.len() || out.len() + cnt > b.len() / 4 { return Err(KernScopeError::Gpos("pair count outside the font / table".into())); }
        let mut prev: Option<u16> = None;
        for k in 0..cnt {
            let r = ps + 2 + k * 4;
            let right = u16at(b, r)?;
            if usize::from(right) >= num_glyphs || prev.map_or(false, |p| p >= right) { return Err(KernScopeError::Gpos("second glyphs not strictly increasing / outside the font".into())); }
            prev = Some(right);
            out.push((*left, right, u16at(b, r + 2)? as i16));
        }
    }
    Ok(())
}
/// NARROW reader for the pipeline's OWN canonical table (`write_kern_pairpos1`), not a general GPOS reader. It parses every pair, then
/// PROVES canonicality: re-serializing the parsed pairs with the writer must reproduce the input bytes exactly. That proves the
/// writer's single fixed script/feature/lookup structure (all lookups active, kern only) and that nothing else is in the table.
/// Any other table (extra/inactive/non-kern lookups, class-based PairPos 2, other value formats) is a typed refusal.
/// Returns glyph indexes taking part (left OR right) in a NONZERO xAdvance pair-kern value.
pub fn kern_participants(gpos: &[u8], num_glyphs: usize) -> Result<BTreeSet<u16>, KernScopeError> {
    if num_glyphs == 0 || num_glyphs > 65535 || gpos.len() > (1 << 24) { return Err(KernScopeError::Gpos("glyph count / table size outside the budget".into())); }
    if u16at(gpos, 0)? != 1 || u16at(gpos, 2)? != 0 { return Err(KernScopeError::Gpos("GPOS version != 1.0".into())); }
    let ll = usize::from(u16at(gpos, 8)?);
    let n = u16at(gpos, ll)? as usize;
    if n == 0 || n > 8 || ll + 2 + 2 * n > gpos.len() { return Err(KernScopeError::Gpos("lookup count outside the budget".into())); }
    let mut pairs: Vec<(u16, u16, i16)> = Vec::new();
    for i in 0..n {
        let lk = ll + usize::from(u16at(gpos, ll + 2 + 2 * i)?);
        let (ty, nst) = (u16at(gpos, lk)?, u16at(gpos, lk + 4)? as usize);
        if ty != 2 && ty != 9 { return Err(KernScopeError::Gpos(format!("lookup type {ty} is not pair adjustment"))); }
        if nst == 0 || nst > 4096 || lk + 6 + 2 * nst > gpos.len() { return Err(KernScopeError::Gpos("subtable count outside the budget".into())); }
        for j in 0..nst {
            let mut st = lk + usize::from(u16at(gpos, lk + 6 + 2 * j)?);
            if ty == 9 {
                if u16at(gpos, st)? != 1 || u16at(gpos, st + 2)? != 2 { return Err(KernScopeError::Gpos("extension subtable is not PairPos".into())); }
                st = st.checked_add(u32at(gpos, st + 4)? as usize).ok_or(KernScopeError::Gpos("offset overflow".into()))?;
            }
            pair_pos(gpos, st, num_glyphs, &mut pairs)?;
        }
    }
    let canon = kni_metrics::gpos_pairpos1::write_kern_pairpos1(num_glyphs as u16,
        &pairs.iter().map(|p| kni_metrics::gpos_pairpos1::PairKern { left: p.0, right: p.1, x_advance: i32::from(p.2) }).collect::<Vec<_>>())
        .map_err(|e| KernScopeError::Gpos(format!("canonical re-serialization refused: {e:?}")))?;
    if canon != gpos { return Err(KernScopeError::Gpos("table is not byte-identical to the canonical write_kern_pairpos1 serialization of its own pairs".into())); }
    Ok(pairs.iter().filter(|p| p.2 != 0).flat_map(|p| [p.0, p.1]).collect())
}

/// NARROW reader for the pipeline's OWN canonical GSUB (`write_liga`), not a general GSUB reader: collects the ligature TARGET
/// glyphs of every type-4 LigatureSubst subtable, then PROVES canonicality - re-serializing the parsed substitutions with the
/// writer must reproduce the input bytes exactly. Ligature glyphs ship unmapped by design; this readback is the only
/// font-internal source that names them. Any other table shape is a typed refusal.
pub fn ligature_targets(gsub: &[u8], num_glyphs: usize) -> Result<BTreeSet<u16>, KernScopeError> {
    (|| {
        if num_glyphs == 0 || num_glyphs > 65535 || gsub.len() > (1 << 24) { return Err(KernScopeError::Gpos("glyph count / table size outside the budget".into())); }
        if u16at(gsub, 0)? != 1 || u16at(gsub, 2)? != 0 { return Err(KernScopeError::Gpos("GSUB version != 1.0".into())); }
        let ll = usize::from(u16at(gsub, 8)?);
        let n = u16at(gsub, ll)? as usize;
        if n == 0 || n > 8 || ll + 2 + 2 * n > gsub.len() { return Err(KernScopeError::Gpos("lookup count outside the budget".into())); }
        let mut subs: Vec<kni_metrics::gsub_liga::LigaSub> = Vec::new();
        for i in 0..n {
            let lk = ll + usize::from(u16at(gsub, ll + 2 + 2 * i)?);
            let (ty, nst) = (u16at(gsub, lk)?, u16at(gsub, lk + 4)? as usize);
            if ty != 4 { return Err(KernScopeError::Gpos(format!("lookup type {ty} is not ligature substitution"))); }
            if nst == 0 || nst > 4096 || lk + 6 + 2 * nst > gsub.len() { return Err(KernScopeError::Gpos("subtable count outside the budget".into())); }
            for j in 0..nst {
                let st = lk + usize::from(u16at(gsub, lk + 6 + 2 * j)?);
                if u16at(gsub, st)? != 1 { return Err(KernScopeError::Gpos("LigatureSubst format other than 1 is not supported (no silent skip)".into())); }
                let cov = coverage(gsub, st + usize::from(u16at(gsub, st + 2)?), num_glyphs)?;
                let sc = u16at(gsub, st + 4)? as usize;
                if sc != cov.len() { return Err(KernScopeError::Gpos("ligSetCount != coverage count".into())); }
                for (k, &first) in cov.iter().enumerate() {
                    let set = st + usize::from(u16at(gsub, st + 6 + 2 * k)?);
                    let cnt = u16at(gsub, set)? as usize;
                    if cnt == 0 || cnt > num_glyphs || set + 2 + 2 * cnt > gsub.len() || subs.len() + cnt > gsub.len() / 6 { return Err(KernScopeError::Gpos("ligature count outside the font / table".into())); }
                    for m in 0..cnt {
                        let lig = set + usize::from(u16at(gsub, set + 2 + 2 * m)?);
                        let (glyph, cc) = (u16at(gsub, lig)?, u16at(gsub, lig + 2)? as usize);
                        if cc < 2 || cc > 8 || lig + 4 + 2 * (cc - 1) > gsub.len() { return Err(KernScopeError::Gpos("component count outside the budget".into())); }
                        let components = (0..cc - 1).map(|x| u16at(gsub, lig + 4 + 2 * x)).collect::<Result<Vec<_>, _>>()?;
                        if usize::from(glyph) >= num_glyphs || components.iter().any(|&c| usize::from(c) >= num_glyphs) { return Err(KernScopeError::Gpos("ligature / component glyph outside the font".into())); }
                        subs.push(kni_metrics::gsub_liga::LigaSub { first, components, ligature: glyph });
                    }
                }
            }
        }
        let canon = kni_metrics::gsub_liga::write_liga(num_glyphs as u16, &subs)
            .map_err(|e| KernScopeError::Gpos(format!("canonical re-serialization refused: {e:?}")))?;
        if canon != gsub { return Err(KernScopeError::Gpos("table is not byte-identical to the canonical write_liga serialization of its own substitutions".into())); }
        Ok(subs.iter().map(|s| s.ligature).collect())
    })().map_err(|e| match e { KernScopeError::Gpos(m) => KernScopeError::Gsub(m), other => other })
}

/// Allow-set bound to ONE approved baseline: private fields, constructed only by `select_for_token` from the token's own bytes, font
/// glyph order and cmap. `post_pass` refuses it for any other token (baseline sha mismatch); callers cannot supply an arbitrary set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TokenBoundAllow { allow: BTreeSet<String>, base_sha256: String }
impl TokenBoundAllow {
    pub fn allow(&self) -> &BTreeSet<String> { &self.allow }
    pub fn base_sha256(&self) -> &str { &self.base_sha256 }
}
/// Read the token's own baseline GPOS bytes, select Unicode L* ∩ nonzero kern participants, bind the result to the token's sha256.
pub fn select_for_token(token: &crate::post_metrics::ApprovedBase, classes: &[(String, kni_core::offset_scope::GlyphClass)]) -> Result<(TokenBoundAllow, KerningLetters), KernScopeError> {
    let font = token.font();
    let order: Vec<String> = font.glyphs.iter().map(|g| g.name.clone()).collect();
    let gpos = crate::post_metrics::sfnt_table(token.bytes(), b"GPOS").ok_or(KernScopeError::Gpos("approved baseline has no GPOS table".into()))?;
    let participants = kern_participants(gpos, order.len())?;
    let ligatures = match crate::post_metrics::sfnt_table(token.bytes(), b"GSUB") {
        Some(g) => ligature_targets(g, order.len())?,
        None => BTreeSet::new(),
    };
    let is_base = |n: &str| classes.iter().find(|c| c.0 == n).map(|c| c.1 == kni_core::offset_scope::GlyphClass::Base);
    let sel = select_kerning_letters(&order, &font.mapping, &is_base, &participants, &ligatures)?;
    Ok((TokenBoundAllow { allow: sel.allow.clone(), base_sha256: token.sha256().to_string() }, sel))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KerningLetters {
    pub allow: BTreeSet<String>,
    pub participants_sha256: String, pub allow_sha256: String, pub eligible_unicode_letters: usize, pub actual_kern_participants: usize, pub ineligible_kern_participants: usize, pub letters_without_nonzero_kern: usize,
}
impl KerningLetters {
    pub fn receipt_line(&self) -> String {
        format!("scope_selection\tpolicy\t{POLICY_ID}\tunicode\t17.0.0 General_Category L*\tEligibleUnicodeLetters\t{}\tActualKernParticipants\t{}\tintersection\t{}\tineligible_kern_participants\t{}\tletters_without_nonzero_kern\t{}\tkern_participants_sha256\t{}\tallow_set_sha256\t{}\n",
            self.eligible_unicode_letters, self.actual_kern_participants, self.allow.len(), self.ineligible_kern_participants, self.letters_without_nonzero_kern, self.participants_sha256, self.allow_sha256)
    }
}
/// `is_base[gid]` = the glyph is class Base (not space/.notdef/mark). Eligible = Base && (every mapped codepoint is L* (at
/// least one) || the glyph is a ligature target in `ligatures`). Ligature glyphs ship unmapped by design: without the
/// ligature branch the kerning_letters post-pass adjusts the letter side of a ligature kern pair but never the ligature
/// side. `ligatures` comes from the approved baseline's own GSUB readback (`ligature_targets`); an empty set is exactly
/// the old letters-only behavior.
pub fn select_kerning_letters(order: &[String], mapping: &[(u32, u16)], is_base: &dyn Fn(&str) -> Option<bool>, participants: &BTreeSet<u16>, ligatures: &BTreeSet<u16>) -> Result<KerningLetters, KernScopeError> {
    if participants.iter().any(|g| usize::from(*g) >= order.len()) { return Err(KernScopeError::Shape("kern participant outside the glyph order")); }
    if ligatures.iter().any(|g| usize::from(*g) >= order.len()) { return Err(KernScopeError::Shape("ligature target outside the glyph order")); }
    let mut eligible: BTreeSet<u16> = BTreeSet::new();
    for (gid, name) in order.iter().enumerate() {
        if is_base(name).ok_or(KernScopeError::Shape("glyph has no class"))? != true { continue; }
        let cps: Vec<u32> = mapping.iter().filter(|m| usize::from(m.1) == gid).map(|m| m.0).collect();
        if ligatures.contains(&(gid as u16)) || (!cps.is_empty() && cps.iter().all(|c| unicode_marks::is_letter(*c))) { eligible.insert(gid as u16); }
    }
    let inter: BTreeSet<u16> = eligible.intersection(participants).copied().collect();
    if inter.is_empty() { return Err(KernScopeError::EmptySelection); }
    let dig = |items: Vec<String>| kni_core::cff_reader::sha256_hex(items.join("\n").as_bytes());
    Ok(KerningLetters {
        participants_sha256: dig(participants.iter().map(|g| g.to_string()).collect()), allow_sha256: dig(inter.iter().map(|g| order[usize::from(*g)].clone()).collect()),
        allow: inter.iter().map(|g| order[usize::from(*g)].clone()).collect(),
        eligible_unicode_letters: eligible.len(), actual_kern_participants: participants.len(),
        ineligible_kern_participants: participants.difference(&eligible).count(), letters_without_nonzero_kern: eligible.difference(participants).count(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_metrics::gpos_pairpos1::{write_kern_pairpos1, PairKern};
    // glyph order: 0 .notdef, 1 A, 2 o, 3 space, 4 one(digit), 5 acute(mark), 6 b (letter, only zero pair), 7 z (letter, not in GPOS)
    fn order() -> Vec<String> { [".notdef", "A", "o", "space", "one", "acute", "b", "z"].iter().map(|s| s.to_string()).collect() }
    fn map() -> Vec<(u32, u16)> { vec![(65, 1), (111, 2), (32, 3), (0x31, 4), (0x301, 5), (98, 6), (122, 7)] }
    fn base(n: &str) -> Option<bool> { Some(!matches!(n, ".notdef" | "space" | "acute")) }
    fn gpos(pairs: &[(u16, u16, i32)]) -> Vec<u8> {
        write_kern_pairpos1(8, &pairs.iter().map(|p| PairKern { left: p.0, right: p.1, x_advance: p.2 }).collect::<Vec<_>>()).unwrap()
    }
    fn lig_order() -> Vec<String> { [".notdef", "A", "o", "f_i"].iter().map(|s| s.to_string()).collect() }
    fn lig_map() -> Vec<(u32, u16)> { vec![(65, 1), (111, 2)] } // f_i unmapped by design
    fn lig_base(n: &str) -> Option<bool> { Some(n != ".notdef") }

    #[test]
    fn ligature_targets_reads_back_canonical_gsub() {
        let gsub = kni_metrics::gsub_liga::write_liga(4, &[kni_metrics::gsub_liga::LigaSub { first: 1, components: vec![2], ligature: 3 }]).unwrap();
        assert_eq!(ligature_targets(&gsub, 4).unwrap(), BTreeSet::from([3]));
        assert!(matches!(ligature_targets(&[0u8; 12], 4), Err(KernScopeError::Gsub(_))), "junk table is a typed refusal");
        assert!(matches!(ligature_targets(&gpos(&[(1, 3, -7)]), 4), Err(KernScopeError::Gsub(_))), "a GPOS is not a GSUB");
    }

    #[test]
    fn ligature_kern_pair_selects_both_sides_symmetrically() {
        // pairs A->f_i and f_i->o, both nonzero: letter AND ligature are eligible and selected
        let p = kern_participants(&gpos(&[(1, 3, -20), (3, 2, -15)]), 4).unwrap();
        let lig = BTreeSet::from([3u16]);
        let s = select_kerning_letters(&lig_order(), &lig_map(), &lig_base, &p, &lig).unwrap();
        assert_eq!(s.allow, BTreeSet::from(["A".to_string(), "o".to_string(), "f_i".to_string()]),
            "ligature pair participant selected together with its letter neighbors");
        // same setup without the GSUB-derived set: the unmapped ligature stays out (old behavior)
        let s = select_kerning_letters(&lig_order(), &lig_map(), &lig_base, &p, &BTreeSet::new()).unwrap();
        assert_eq!(s.allow, BTreeSet::from(["A".to_string(), "o".to_string()]));
    }

    #[test]
    fn ligature_target_outside_glyph_order_refused() {
        let p = kern_participants(&gpos(&[(1, 2, -20)]), 4).unwrap();
        assert!(matches!(select_kerning_letters(&lig_order(), &lig_map(), &lig_base, &p, &BTreeSet::from([9u16])),
            Err(KernScopeError::Shape(_))));
    }

    #[test]
    fn participants_are_nonzero_pair_members_read_back_from_gpos_bytes() {
        let g = gpos(&[(1, 2, -12), (2, 1, 7), (3, 1, -5), (4, 2, 3), (5, 1, 2), (0, 1, 4)]);
        let p = kern_participants(&g, 8).unwrap();
        assert_eq!(p, [0u16, 1, 2, 3, 4, 5].into());
        // a zero-valued pair is NOT a participant (6 and 7 absent)
        assert!(!p.contains(&6) && !p.contains(&7));
        assert!(kern_participants(&g[..g.len() - 3], 8).is_err());
        assert!(kern_participants(&g, 3).is_err());
    }
    #[test]
    fn selection_is_letters_intersect_actual_participants_only() {
        let g = gpos(&[(1, 2, -12), (2, 1, 7), (3, 1, -5), (4, 2, 3), (5, 1, 2), (0, 1, 4)]);
        let p = kern_participants(&g, 8).unwrap();
        let s = select_kerning_letters(&order(), &map(), &base, &p, &BTreeSet::new()).unwrap();
        // applied: letters in a nonzero pair (A, o). Excluded: space, .notdef, mark acute, digit one (all in GPOS), letters b/z (no nonzero kern)
        assert_eq!(s.allow, ["A".to_string(), "o".to_string()].into());
        assert_eq!((s.eligible_unicode_letters, s.actual_kern_participants, s.ineligible_kern_participants, s.letters_without_nonzero_kern), (4, 6, 4, 2));
        let l = s.receipt_line();
        assert!(l.contains("policy\tkerning_letters") && l.contains("EligibleUnicodeLetters\t4") && l.contains("ActualKernParticipants\t6") && l.contains("intersection\t2") && l.contains("kern_participants_sha256\t") && l.contains("allow_set_sha256\t"));
    }
    #[test]
    fn letter_with_zero_pair_or_absent_from_gpos_is_excluded_and_empty_is_refused() {
        // only b has a pair, and its value is zero => the writer carries it, but the reader sees no nonzero participant
        let g = gpos(&[(6, 1, 0), (1, 2, 5)]);
        let p = kern_participants(&g, 8).unwrap();
        assert!(!p.contains(&6) && p.contains(&1) && p.contains(&2));
        let s = select_kerning_letters(&order(), &map(), &base, &p, &BTreeSet::new()).unwrap();
        assert!(!s.allow.contains("b") && !s.allow.contains("z"));
        // only non-letters kern => EmptySelection (typed refusal, never a silent no-op)
        let g2 = gpos(&[(3, 4, 5), (5, 0, 5)]);
        assert_eq!(select_kerning_letters(&order(), &map(), &base, &kern_participants(&g2, 8).unwrap(), &BTreeSet::new()).unwrap_err(), KernScopeError::EmptySelection);
        // a "letter" whose class is not Base (declared mark/space) is not eligible
        let not_base = |n: &str| Some(n != "A");
        let g3 = gpos(&[(1, 2, 5)]);
        let s3 = select_kerning_letters(&order(), &map(), &not_base, &kern_participants(&g3, 8).unwrap(), &BTreeSet::new()).unwrap();
        assert_eq!(s3.allow, ["o".to_string()].into());
    }
    #[test]
    fn non_canonical_or_hostile_tables_are_typed_refusals_without_allocation_blowup() {
        let g = gpos(&[(1, 2, -12), (2, 1, 7)]);
        assert!(kern_participants(&g, 8).is_ok());
        // any single flipped byte in the script/feature/lookup structure or values => not byte-identical to the canonical serialization (or a typed parse refusal)
        // structural bytes (everything before the PairPos subtable data) refuse on any flip; data-byte flips (glyph ids / values) may yield another canonical table
        let ps = { let ll = u16at(&g, 8).unwrap() as usize; let lk = ll + u16at(&g, ll + 2).unwrap() as usize; lk + u16at(&g, lk + 6).unwrap() as usize };
        for i in 0..ps { let mut t = g.clone(); t[i] ^= 0x01; assert!(kern_participants(&t, 8).is_err(), "structural byte {i} flip accepted"); }
        // coverage format 2 and an overlapping/huge range count are refused before any expansion
        let ll = u16at(&g, 8).unwrap() as usize; let lk = ll + u16at(&g, ll + 2).unwrap() as usize;
        let st = lk + u16at(&g, lk + 6).unwrap() as usize; let cov = st + u16at(&g, st + 2).unwrap() as usize;
        let mut f2 = g.clone(); f2[cov + 1] = 2; assert!(kern_participants(&f2, 8).is_err());
        let mut big = g.clone(); big[cov + 2] = 0xFF; big[cov + 3] = 0xFF; assert!(kern_participants(&big, 8).is_err());
        // truncation, zero glyph budget, oversize budget
        assert!(kern_participants(&g[..10], 8).is_err() && kern_participants(&g, 0).is_err() && kern_participants(&g, 70000).is_err());
    }
}
