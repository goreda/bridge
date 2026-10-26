//! GPOS writer for the kern export path (direct GPOS,
//! no .fea intermediate - no compiler ambiguity). Minimal and real:
//! one 'DFLT' script, one 'kern' feature, one type-2 lookup with two
//! subtables in Adobe kernFeatureWriter order: PairPos Format 1 (exact
//! exceptions) FIRST, PairPos Format 2 (classes) second.
//!
//! Value records carry xAdvance only (valueFormat 0x0004). Class ids from
//! the compiler are shifted by 1 at write time: class 0 is the OpenType
//! reserved default class.
//!
//! Verification discipline: crate tests check layout invariants; the
//! acceptance evidence is an external fontTools round-trip (inject into a
//! real font, read back, compare pairs) - the writer is not its own judge.

use crate::export_gpos::KernPlan;
use std::collections::BTreeMap;

/// One exact pair exception (left/right are GLYPH IDS).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PairException {
    pub left: u16,
    pub right: u16,
    pub x_advance: i16,
}

fn u16be(v: u16) -> [u8; 2] { v.to_be_bytes() }
fn i16be(v: i16) -> [u8; 2] { v.to_be_bytes() }
fn u32be(v: u32) -> [u8; 4] { v.to_be_bytes() }

/// Coverage table, format 1.
fn coverage(glyphs: &[u16]) -> Vec<u8> {
    let mut g = glyphs.to_vec();
    g.sort_unstable();
    let mut out = u16be(1).to_vec();
    out.extend_from_slice(&u16be(g.len() as u16));
    for id in g {
        out.extend_from_slice(&u16be(id));
    }
    out
}

/// ClassDef, format 2, one range per glyph (v1 simplicity; range merging
/// is a size optimization for the storage-aware pass).
fn classdef(assignments: &BTreeMap<u16, usize>) -> Vec<u8> {
    let mut out = u16be(2).to_vec();
    out.extend_from_slice(&u16be(assignments.len() as u16));
    for (&g, &c) in assignments {
        out.extend_from_slice(&u16be(g));
        out.extend_from_slice(&u16be(g));
        out.extend_from_slice(&u16be((c + 1) as u16)); // shift: 0 reserved
    }
    out
}

/// PairPos Format 1 subtable: exact exceptions, grouped by left glyph.
fn pairpos_fmt1(exceptions: &[PairException]) -> Vec<u8> {
    let mut by_left: BTreeMap<u16, Vec<PairException>> = BTreeMap::new();
    for e in exceptions {
        by_left.entry(e.left).or_default().push(*e);
    }
    let lefts: Vec<u16> = by_left.keys().cloned().collect();
    let header_len = 10 + 2 * lefts.len();
    let mut pairsets: Vec<u8> = Vec::new();
    let mut offsets: Vec<u16> = Vec::new();
    for &l in &lefts {
        offsets.push((header_len + pairsets.len()) as u16);
        let recs = &by_left[&l];
        pairsets.extend_from_slice(&u16be(recs.len() as u16));
        for r in recs {
            pairsets.extend_from_slice(&u16be(r.right));
            pairsets.extend_from_slice(&i16be(r.x_advance));
            pairsets.extend_from_slice(&i16be(0));
        }
    }
    let cov = coverage(&lefts);
    let mut out = u16be(1).to_vec();
    out.extend_from_slice(&u16be((header_len + pairsets.len()) as u16)); // coverage offset
    out.extend_from_slice(&u16be(0x0004));
    out.extend_from_slice(&u16be(0x0004));
    out.extend_from_slice(&u16be(lefts.len() as u16));
    for o in offsets {
        out.extend_from_slice(&u16be(o));
    }
    out.extend_from_slice(&pairsets);
    out.extend_from_slice(&cov);
    out
}

/// PairPos Format 2 subtable: class kerning matrix.
fn pairpos_fmt2(plan: &KernPlan, glyph_has_kerns: &[u16]) -> Vec<u8> {
    let cd1 = classdef(&plan.left_classes);
    let cd2 = classdef(&plan.right_classes);
    let n_c1 = plan.left_classes.values().max().map(|m| m + 2).unwrap_or(1) as u16; // +class 0
    let n_c2 = plan.right_classes.values().max().map(|m| m + 2).unwrap_or(1) as u16;
    let matrix_len = (n_c1 as usize) * (n_c2 as usize) * 4;
    let header_len = 16;
    let cd1_off = header_len + matrix_len;
    let cd2_off = cd1_off + cd1.len();
    let cov_off = cd2_off + cd2.len();
    let mut out = u16be(2).to_vec();
    out.extend_from_slice(&u16be(cov_off as u16));
    out.extend_from_slice(&u16be(0x0004));
    out.extend_from_slice(&u16be(0x0004));
    out.extend_from_slice(&u16be(cd1_off as u16));
    out.extend_from_slice(&u16be(cd2_off as u16));
    out.extend_from_slice(&u16be(n_c1));
    out.extend_from_slice(&u16be(n_c2));
    for c1 in 0..n_c1 {
        for c2 in 0..n_c2 {
            let v = if c1 == 0 || c2 == 0 {
                0
            } else {
                *plan.class_kerns.get(&((c1 - 1) as usize, (c2 - 1) as usize)).unwrap_or(&0)
            };
            out.extend_from_slice(&i16be(v as i16));
            out.extend_from_slice(&i16be(0));
        }
    }
    out.extend_from_slice(&cd1);
    out.extend_from_slice(&cd2);
    out.extend_from_slice(&coverage(glyph_has_kerns));
    out
}

/// Write a complete GPOS table. `glyph_order_len` is unused today; the
/// caller supplies glyph ids directly (the font backend owns names).
pub fn write_gpos(exceptions: &[PairException], plan: &KernPlan) -> Vec<u8> {
    let fmt1 = pairpos_fmt1(exceptions);
    let class_lefts: Vec<u16> = plan.left_classes.keys().cloned().collect();
    let fmt2 = pairpos_fmt2(plan, &class_lefts);

    // ScriptList: 1 record, Script: defaultLangSys, LangSys: 1 feature.
    let script_list = {
        let mut langsys = u16be(0).to_vec(); // lookupOrder = NULL
        langsys.extend_from_slice(&u16be(0xFFFF)); // reqFeatureIndex
        langsys.extend_from_slice(&u16be(1)); // featureIndexCount
        langsys.extend_from_slice(&u16be(0)); // feature 0
        let mut script = u16be(4).to_vec(); // defaultLangSysOffset
        script.extend_from_slice(&u16be(0)); // langSysCount
        script.extend_from_slice(&langsys);
        let mut sl = u16be(1).to_vec();
        sl.extend_from_slice(b"DFLT");
        sl.extend_from_slice(&u16be(8)); // script offset (after count+record)
        sl.extend_from_slice(&script);
        sl
    };
    let feature_list = {
        let mut feat = u16be(0).to_vec(); // featureParams = NULL
        feat.extend_from_slice(&u16be(1)); // lookupIndexCount
        feat.extend_from_slice(&u16be(0)); // lookup 0
        let mut fl = u16be(1).to_vec();
        fl.extend_from_slice(b"kern");
        fl.extend_from_slice(&u16be(8));
        fl.extend_from_slice(&feat);
        fl
    };
    let lookup = {
        let n_sub = 2u16;
        let header = 6 + 2 * n_sub as usize;
        let mut lk = u16be(2).to_vec(); // type 2 PairPos
        lk.extend_from_slice(&u16be(0)); // flags
        lk.extend_from_slice(&u16be(n_sub));
        lk.extend_from_slice(&u16be(header as u16)); // fmt1 first (exceptions)
        lk.extend_from_slice(&u16be((header + fmt1.len()) as u16));
        lk.extend_from_slice(&fmt1);
        lk.extend_from_slice(&fmt2);
        lk
    };
    let lookup_list = {
        let mut ll = u16be(1).to_vec();
        ll.extend_from_slice(&u16be(4));
        ll.extend_from_slice(&lookup);
        ll
    };
    let mut out = u32be(0x00010000).to_vec();
    out.extend_from_slice(&u16be(10));
    out.extend_from_slice(&u16be((10 + script_list.len()) as u16));
    out.extend_from_slice(&u16be((10 + script_list.len() + feature_list.len()) as u16));
    out.extend_from_slice(&script_list);
    out.extend_from_slice(&feature_list);
    out.extend_from_slice(&lookup_list);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::export_gpos::{ByteModel, PairTarget, compile_kerns};

    fn sample_plan() -> (Vec<PairException>, KernPlan) {
        let targets = vec![
            PairTarget { left: 10, right: 20, kern: -80, locked: false },
            PairTarget { left: 10, right: 21, kern: -80, locked: false },
            PairTarget { left: 11, right: 20, kern: -40, locked: false },
            PairTarget { left: 11, right: 21, kern: -40, locked: false },
        ];
        let plan = compile_kerns(&targets, 0, ByteModel::default());
        let ex = vec![PairException { left: 30, right: 40, x_advance: -120 }];
        (ex, plan)
    }

    fn be_u16(b: &[u8], off: usize) -> u16 {
        u16::from_be_bytes([b[off], b[off + 1]])
    }

    #[test]
    fn gpos_header_and_lists() {
        let (ex, plan) = sample_plan();
        let g = write_gpos(&ex, &plan);
        assert_eq!(&g[0..4], &[0, 1, 0, 0], "version 1.0");
        let sl = be_u16(&g, 4) as usize;
        let fl = be_u16(&g, 6) as usize;
        let ll = be_u16(&g, 8) as usize;
        assert!(sl < fl && fl < ll && ll < g.len(), "ordered offsets");
        assert_eq!(&g[sl + 2..sl + 6], b"DFLT");
        assert_eq!(&g[fl + 2..fl + 6], b"kern");
        // lookup type 2, flags 0, 2 subtables (fmt1 first)
        let lookup = ll + 4;
        assert_eq!(be_u16(&g, lookup), 2);
        assert_eq!(be_u16(&g, lookup + 2), 0);
        assert_eq!(be_u16(&g, lookup + 4), 2);
        let sub1 = lookup + be_u16(&g, lookup + 6) as usize;
        let sub2 = lookup + be_u16(&g, lookup + 8) as usize;
        assert_eq!(be_u16(&g, sub1), 1, "PairPos fmt1 (exceptions) first");
        assert_eq!(be_u16(&g, sub2), 2, "PairPos fmt2 (classes) second");
        assert!(sub1 < sub2);
    }

    #[test]
    fn exception_record_bytes() {
        let (ex, plan) = sample_plan();
        let g = write_gpos(&ex, &plan);
        // find the fmt1 subtable via offsets
        let ll = be_u16(&g, 8) as usize;
        let lookup = ll + 4;
        let sub1 = lookup + be_u16(&g, lookup + 6) as usize;
        // fmt1: posFormat(2) cov(2) vf1(2) vf2(2) pairSetCount(2) offsets(2*n)
        let psc = be_u16(&g, sub1 + 8) as usize;
        assert_eq!(psc, 1);
        let ps = sub1 + be_u16(&g, sub1 + 10) as usize;
        assert_eq!(be_u16(&g, ps), 1, "one pair record");
        assert_eq!(be_u16(&g, ps + 2), 40, "right glyph");
        assert_eq!(be_u16(&g, ps + 4) as i16, -120, "xAdvance");
    }

    #[test]
    fn class_matrix_has_reserved_zero_classes() {
        let (ex, plan) = sample_plan();
        let g = write_gpos(&ex, &plan);
        let ll = be_u16(&g, 8) as usize;
        let lookup = ll + 4;
        let sub2 = lookup + be_u16(&g, lookup + 8) as usize;
        let n1 = be_u16(&g, sub2 + 12) as usize;
        let n2 = be_u16(&g, sub2 + 14) as usize;
        assert_eq!(n1, 3, "2 left classes + reserved 0");
        assert_eq!(n2, 2, "1 right class + reserved 0");
        // first row (class 0) must be all zeros
        for i in 0..n2 {
            assert_eq!(be_u16(&g, sub2 + 16 + i * 4), 0);
        }
        // class (1,1) value = -80 (shifted ids)
        let v = be_u16(&g, sub2 + 16 + (1 * n2 + 1) * 4) as i16;
        assert_eq!(v, -80);
    }

    #[test]
    fn empty_exceptions_still_valid() {
        let targets = vec![PairTarget { left: 1, right: 2, kern: -10, locked: false }];
        let plan = compile_kerns(&targets, 0, ByteModel::default());
        let g = write_gpos(&[], &plan);
        assert_eq!(&g[0..4], &[0, 1, 0, 0]);
    }
}
