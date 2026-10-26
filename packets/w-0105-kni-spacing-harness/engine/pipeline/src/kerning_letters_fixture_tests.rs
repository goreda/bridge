//! Synthetic GPOS fixture + expected-set tests for the `kerning_letters` filter (test-only, no production code).
//!
//! Definition under test (stated, not inferred): a glyph is in the eligible set iff
//!  (a) its single mapped codepoint has General_Category L* = Lu, Ll, Lt, Lm or Lo (declared per codepoint in the fixture below,
//!      not computed by a heuristic), and
//!  (b) it participates (as left or right glyph) in at least one PairPos1 pair with a NONZERO x_advance.
//! Partner class does not matter (a letter kerned only against a digit still participates).
//! Nd/Mn/Zs/.notdef are never eligible even when kerned.
//! The expected set is written out explicitly below; the oracle is only a self-check of the fixture.
//!
//! `filter_under_test` is the single wiring point for B's filter. Until B's function exists in this tree the
//! wiring test is `#[ignore]` with that reason; the fixture and expected set are checked now.
use kni_metrics::gpos_pairpos1::{write_kern_pairpos1, PairKern};
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Gc { Lu, Ll, Lt, Lo, Lm, Nd, Mn, Zs, Notdef }

pub struct Glyph { pub id: &'static str, pub cp: Option<u32>, pub gc: Gc }

/// glyph order: index = glyph id.
pub fn glyphs() -> Vec<Glyph> {
    vec![
        Glyph { id: ".notdef", cp: None, gc: Gc::Notdef },
        Glyph { id: "A", cp: Some(0x41), gc: Gc::Lu },                  // 1 pair participant (A,a) and (alef,A)
        Glyph { id: "a", cp: Some(0x61), gc: Gc::Ll },                  // 2 pair participant
        Glyph { id: "alef", cp: Some(0x5D0), gc: Gc::Lo },              // 3 pair participant, Lo
        Glyph { id: "b", cp: Some(0x62), gc: Gc::Ll },                  // 4 letter, only a ZERO-valued pair
        Glyph { id: "c", cp: Some(0x63), gc: Gc::Ll },                  // 5 letter, absent from GPOS
        Glyph { id: "one", cp: Some(0x31), gc: Gc::Nd },                // 6 digit with nonzero kern
        Glyph { id: "acutecomb", cp: Some(0x301), gc: Gc::Mn },         // 7 combining accent with nonzero kern
        Glyph { id: "space", cp: Some(0x20), gc: Gc::Zs },              // 8 space with nonzero kern
        Glyph { id: "modifier_h", cp: Some(0x2B0), gc: Gc::Lm },        // 9 Lm with nonzero kern (eligible: L* = Lu/Ll/Lt/Lm/Lo)
        Glyph { id: "d", cp: Some(0x64), gc: Gc::Ll },                  // 10 letter kerned only against a digit
        Glyph { id: "dz_title", cp: Some(0x1C5), gc: Gc::Lt },          // 11 titlecase letter with nonzero kern
    ]
}

pub fn pairs() -> Vec<PairKern> {
    vec![
        PairKern { left: 1, right: 2, x_advance: -20 },  // A a
        PairKern { left: 3, right: 1, x_advance: -15 },  // alef A
        PairKern { left: 4, right: 4, x_advance: 0 },    // b b zero
        PairKern { left: 6, right: 6, x_advance: -10 },  // one one
        PairKern { left: 7, right: 6, x_advance: -5 },   // acutecomb one
        PairKern { left: 8, right: 6, x_advance: -30 },  // space one
        PairKern { left: 9, right: 6, x_advance: -7 },   // modifier_h one
            PairKern { left: 10, right: 6, x_advance: -12 }, // d one (digit partner)
        PairKern { left: 11, right: 2, x_advance: -9 },  // dz_title a
        PairKern { left: 0, right: 1, x_advance: -3 },   // .notdef A
    ]
}

/// cmap as (codepoint, glyph id), the shape bind_classes takes.
pub fn mapping() -> Vec<(u32, u16)> {
    glyphs().iter().enumerate().filter_map(|(i, g)| g.cp.map(|c| (c, i as u16))).collect()
}

/// Explicit expected eligible glyph ids (by glyph order name).
pub const EXPECTED_ELIGIBLE: [&str; 6] = ["A", "a", "alef", "modifier_h", "d", "dz_title"];

fn oracle() -> BTreeSet<&'static str> {
    let g = glyphs();
    let mut part: BTreeSet<u16> = BTreeSet::new();
    for p in pairs() {
        if p.x_advance != 0 {
            part.insert(p.left);
            part.insert(p.right);
        }
    }
    g.iter()
        .enumerate()
        .filter(|(i, x)| matches!(x.gc, Gc::Lu | Gc::Ll | Gc::Lt | Gc::Lm | Gc::Lo) && part.contains(&(*i as u16)))
        .map(|(_, x)| x.id)
        .collect()
}

/// WIRING POINT: the production reader + selector over the fixture's EMITTED GPOS bytes (canonical writer table, zero pair included).
fn filter_under_test(glyph_order: &[&str], mapping: &[(u32, u16)], pairs: &[PairKern]) -> BTreeSet<String> {
    let gpos = write_kern_pairpos1(glyph_order.len() as u16, pairs).expect("fixture GPOS");
    let part = crate::kern_scope::kern_participants(&gpos, glyph_order.len()).expect("canonical readback");
    let order: Vec<String> = glyph_order.iter().map(|s| s.to_string()).collect();
    let is_base = |n: &str| Some(!matches!(n, ".notdef" | "space" | "acutecomb"));
    crate::kern_scope::select_kerning_letters(&order, mapping, &is_base, &part, &std::collections::BTreeSet::new()).expect("selection").allow
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_is_a_valid_pairpos1_and_covers_each_case() {
        let g = glyphs();
        // GPOS bytes build (writer accepts the fixture, incl. the zero-valued pair or refuses it typed)
        let nonzero: Vec<PairKern> = pairs().into_iter().filter(|p| p.x_advance != 0).collect();
        assert!(write_kern_pairpos1(g.len() as u16, &nonzero).is_ok());
        // each required case exists
        let has = |gc: Gc| g.iter().any(|x| x.gc == gc);
        assert!(has(Gc::Lu) && has(Gc::Ll) && has(Gc::Lo) && has(Gc::Nd) && has(Gc::Mn) && has(Gc::Zs) && has(Gc::Notdef) && has(Gc::Lm) && has(Gc::Lt));
        // mapping: one codepoint per glyph, unique cps, notdef unmapped
        let m = mapping();
        let cps: BTreeSet<u32> = m.iter().map(|x| x.0).collect();
        assert_eq!(cps.len(), m.len());
        assert!(m.iter().all(|(_, gid)| *gid != 0));
        // letter with zero pair, letter absent from GPOS, letter with digit partner
        let in_any = |id: u16| pairs().iter().any(|p| p.left == id || p.right == id);
        assert!(in_any(4) && pairs().iter().filter(|p| p.left == 4 || p.right == 4).all(|p| p.x_advance == 0));
        assert!(!in_any(5));
        assert!(pairs().iter().any(|p| p.left == 10 && p.right == 6));
    }

    #[test]
    fn expected_set_is_explicit_and_matches_stated_definition() {
        let want: BTreeSet<&str> = EXPECTED_ELIGIBLE.iter().copied().collect();
        assert_eq!(oracle(), want);
        // negative cases named one by one
        for (id, why) in [
            ("b", "letter, only zero-valued pair"),
            ("c", "letter, absent from GPOS"),
            ("one", "digit with kern"),
            ("acutecomb", "combining accent with kern"),
            ("space", "space with kern"),
            (".notdef", ".notdef with kern"),
        ] {
            assert!(!want.contains(id), "{id}: {why}");
        }
    }

    #[test]
    fn b_filter_matches_expected_set() {
        let g = glyphs();
        let order: Vec<&str> = g.iter().map(|x| x.id).collect();
        let got = filter_under_test(&order, &mapping(), &pairs());
        let want: BTreeSet<String> = EXPECTED_ELIGIBLE.iter().map(|s| s.to_string()).collect();
        assert_eq!(got, want);
    }
}
