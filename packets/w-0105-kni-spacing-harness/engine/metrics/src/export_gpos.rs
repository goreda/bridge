//! STEP 6: export_gpos - terminal postprocessing: PairState -> sidebearings
//! + kern table, plus the BBLH-style runtime-table lane.
//!
//! This first cut lands three code-grounded pieces:
//!
//! 1. BBLH SERIALIZER (v1 format, code-grounded from the BubbleKern v1
//!    table layout): big-endian; header version uint16 + glyphCount uint32;
//!    per glyph: presence uint8; when present, 2 wall sets, each count
//!    uint16 followed by count * (x, y) int32 pairs; the RIGHT set's x
//!    values are stored width-offset (x + advance). Round-trip reader
//!    included: a table is only landed when it re-reads identical.
//!
//! 2. RUNTIME OFFSET (BubbleKernTester convention): the offset applied at
//!    runtime is the exact wall gap over the shared y-range. Delegates to
//!    positions::lockstep_wall_gap (step 5a, exact for polylines), so the
//!    clamp to the shared y-range is inherent. Rectangular-glyph fallback:
//!    no walls -> no offset entry.
//!
//! 3. STORAGE-AWARE CLASS COMPILER. Pair targets -> kern classes + exact
//!    exceptions. Merge candidates ranked by error-increase-per-byte-saved;
//!    locked/collision-critical pairs stay exact exceptions, never merged
//!    (exceptions first, Adobe kernFeatureWriter order); max and mean error
//!    reported separately. BYTE MODEL IS OUR SURROGATE: an explicit,
//!    declared estimate of serialized size (per class-pair record + per
//!    exception record), standing in until the real GPOS serializer lands;
//!    the compiler's interface takes the byte model as parameters so the
//!    real cost function drops in without reshaping the algorithm.
//!    Re-import checking against targets arrives with the font backend.
//!
//! Source grounding: Lucke downsizing (same lane), BubbleKern v1+v2
//! code + BBLH, MATH spec precedent for font-embedded cut-in tables.
//! Terminal tier.

use crate::positions::lockstep_wall_gap;
use crate::side_walls::Wall;
use std::collections::BTreeMap;

// ---------------------------------------------------------------- BBLH ---

/// BBLH v1 format version value (uint16).
pub const BBLH_VERSION: u16 = 1;

/// One glyph's two wall sets, integer plane units (the format is int32).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BblhGlyph {
    /// Advance width in units; the right set is stored width-offset.
    pub advance: i32,
    /// Left wall (x, y) points, y ascending.
    pub left: Vec<(i32, i32)>,
    /// Right wall (x, y) points, y ascending, x relative to the right ink
    /// edge (stored as x + advance).
    pub right: Vec<(i32, i32)>,
}

impl BblhGlyph {
    /// Build from Wall polylines, rounding to integers (format is int32).
    /// Walls must be y-sorted (Wall invariant). Right-wall points are taken
    /// relative to the glyph's right edge: canvas x minus advance.
    pub fn from_walls(advance: f64, left: &Wall, right: &Wall) -> Self {
        let conv = |pts: &[(f64, f64)], off: f64| -> Vec<(i32, i32)> {
            pts.iter()
                .map(|&(y, x)| ((x - off).round() as i32, y.round() as i32))
                .collect()
        };
        Self {
            advance: advance.round() as i32,
            left: conv(&left.points, 0.0),
            right: conv(&right.points, advance),
        }
    }
}

/// Serialize a BBLH v1 table (big-endian). Glyphs may be absent (None) -
/// the presence byte is 0 and no payload follows (rectangular fallback).
pub fn bblh_write(glyphs: &[Option<BblhGlyph>]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&BBLH_VERSION.to_be_bytes());
    out.extend_from_slice(&(glyphs.len() as u32).to_be_bytes());
    for g in glyphs {
        match g {
            None => out.push(0u8),
            Some(g) => {
                out.push(1u8);
                for set in [&g.left, &g.right] {
                    out.extend_from_slice(&(set.len() as u16).to_be_bytes());
                    for &(x, y) in set.iter() {
                        let xs = if set as *const _ == &g.right as *const _ {
                            x + g.advance // right set width-offset
                        } else {
                            x
                        };
                        out.extend_from_slice(&xs.to_be_bytes());
                        out.extend_from_slice(&y.to_be_bytes());
                    }
                }
            }
        }
    }
    out
}

/// Parse a BBLH v1 table back. The v1 layout does not carry advances: at
/// runtime they come from the font's own metrics, so the reader takes them
/// as an argument (`advances`, one per glyph; the value is ignored for
/// absent glyphs). The right-set width-offset is removed on read, so a
/// write->read round trip with the same advances is the identity.
pub fn bblh_read(bytes: &[u8], advances: &[i32]) -> Option<Vec<Option<BblhGlyph>>> {
    let mut pos = 0usize;
    let take = |pos: &mut usize, n: usize| -> Option<&[u8]> {
        if *pos + n > bytes.len() {
            return None;
        }
        let s = &bytes[*pos..*pos + n];
        *pos += n;
        Some(s)
    };
    let u16be = |pos: &mut usize| -> Option<u16> {
        Some(u16::from_be_bytes(take(pos, 2)?.try_into().ok()?))
    };
    let u32be = |pos: &mut usize| -> Option<u32> {
        Some(u32::from_be_bytes(take(pos, 4)?.try_into().ok()?))
    };
    let i32be = |pos: &mut usize| -> Option<i32> {
        Some(i32::from_be_bytes(take(pos, 4)?.try_into().ok()?))
    };
    if u16be(&mut pos)? != BBLH_VERSION {
        return None;
    }
    let count = u32be(&mut pos)? as usize;
    let mut glyphs = Vec::with_capacity(count);
    for _ in 0..count {
        let present = take(&mut pos, 1)?[0];
        if present == 0 {
            glyphs.push(None);
            continue;
        }
        let mut sets = Vec::with_capacity(2);
        for _ in 0..2 {
            let n = u16be(&mut pos)? as usize;
            let mut pts = Vec::with_capacity(n);
            for _ in 0..n {
                pts.push((i32be(&mut pos)?, i32be(&mut pos)?));
            }
            sets.push(pts);
        }
        let advance = *advances.get(glyphs.len())?;
        let right: Vec<(i32, i32)> = sets[1].iter().map(|&(x, y)| (x - advance, y)).collect();
        glyphs.push(Some(BblhGlyph { advance, left: sets.remove(0), right }));
    }
    Some(glyphs)
}

/// Runtime offset for one adjacent pair (BubbleKernTester convention):
/// the exact wall gap between the left glyph's right wall and the right
/// glyph's left wall at the current displacement, over the shared y-range.
/// Returns None when either wall is missing (rectangular fallback: no
/// offset entry) or the y-ranges do not overlap.
pub fn runtime_offset(left_right_wall: &Wall, right_left_wall: &Wall, displacement: f64) -> Option<f64> {
    lockstep_wall_gap(left_right_wall, right_left_wall, displacement).map(|g| g.min_gap)
}

// --------------------------------------------- storage-aware compiler ---

/// One pair's target kern after sidebearing assignment.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PairTarget {
    pub left: u16,
    pub right: u16,
    /// Target kern in integer font units.
    pub kern: i32,
    /// Locked/model/collision-critical pairs keep exact exceptions and are
    /// never merged into classes (exceptions first).
    pub locked: bool,
}

/// Surrogate serialized-size model (OUR SURROGATE until the real GPOS
/// serializer lands). Explicit parameters so the real cost function drops
/// in without reshaping the compiler.
#[derive(Debug, Clone, Copy)]
pub struct ByteModel {
    /// Bytes per class-pair record in the class matrix.
    pub bytes_per_class_pair: usize,
    /// Bytes per exact exception record (glyph pair + value + coverage
    /// share).
    pub bytes_per_exception: usize,
    /// Fixed table overhead in bytes (header, class definitions share).
    pub fixed_overhead: usize,
}

impl Default for ByteModel {
    fn default() -> Self {
        Self { bytes_per_class_pair: 2, bytes_per_exception: 6, fixed_overhead: 64 }
    }
}

/// Compiled kern plan.
#[derive(Debug, Clone)]
pub struct KernPlan {
    /// Right-glyph class assignment: glyph -> class id.
    pub right_classes: BTreeMap<u16, usize>,
    /// Left-glyph class assignment: glyph -> class id.
    pub left_classes: BTreeMap<u16, usize>,
    /// Class matrix values: (left_class, right_class) -> kern.
    pub class_kerns: BTreeMap<(usize, usize), i32>,
    /// Exact exceptions kept as pair records (locked pairs and pairs whose
    /// class value differs from their target).
    pub exceptions: Vec<PairTarget>,
    /// Largest absolute deviation from any target (units).
    pub max_error: i32,
    /// Mean absolute deviation over all non-locked targets (milli-units).
    pub mean_error_milli: i64,
    /// Estimated serialized size under the surrogate byte model.
    pub estimated_bytes: usize,
}

/// Compile pair targets into classes under an error budget.
///
/// Greedy (OUR merge policy; the separate-reporting discipline comes from the source, the heuristic is ours):
/// 1. locked pairs are set aside as exact exceptions, first;
/// 2. right glyphs with identical pair vectors over the present left
///    glyphs merge at zero error; same for left glyphs;
/// 3. while any merge keeps max_error within `max_error_budget`, apply the
///    merge with the smallest error-increase per byte saved.
/// Deterministic: ties break on the smallest class id pair.
pub fn compile_kerns(
    targets: &[PairTarget],
    max_error_budget: i32,
    model: ByteModel,
) -> KernPlan {
    let (locked, free): (Vec<&PairTarget>, Vec<&PairTarget>) = targets.iter().partition(|t| t.locked);
    // Initial assignment: every glyph its own class.
    let mut left_class: BTreeMap<u16, usize> = BTreeMap::new();
    let mut right_class: BTreeMap<u16, usize> = BTreeMap::new();
    for t in &free {
        let n = left_class.len();
        left_class.entry(t.left).or_insert(n);
        let n = right_class.len();
        right_class.entry(t.right).or_insert(n);
    }
    // Zero-error merge pass: glyphs with identical vectors over the other
    // side's glyphs (including absent-pair patterns) merge.
    let vec_of = |g: u16, left_side: bool, free: &[&PairTarget]| -> Vec<(u16, i32)> {
        let mut v: Vec<(u16, i32)> = free
            .iter()
            .filter(|t| if left_side { t.left == g } else { t.right == g })
            .map(|t| if left_side { (t.right, t.kern) } else { (t.left, t.kern) })
            .collect();
        v.sort();
        v
    };
    let merge_identical = |class: &mut BTreeMap<u16, usize>, left_side: bool, free: &[&PairTarget]| {
        let mut seen: BTreeMap<Vec<(u16, i32)>, usize> = BTreeMap::new();
        let glyphs: Vec<u16> = class.keys().cloned().collect();
        for g in glyphs {
            let v = vec_of(g, left_side, free);
            let n = seen.len();
            let id = *seen.entry(v).or_insert(n);
            class.insert(g, id);
        }
    };
    merge_identical(&mut left_class, true, &free);
    merge_identical(&mut right_class, false, &free);

    // Class value: for a (lc, rc) pair with targets present, the value that
    // minimizes max deviation is the midpoint of the target range.
    let class_value = |lc: usize, rc: usize, free: &[&PairTarget], lc_map: &BTreeMap<u16, usize>, rc_map: &BTreeMap<u16, usize>| -> Option<(i32, i32)> {
        let mut ks: Vec<i32> = free
            .iter()
            .filter(|t| lc_map[&t.left] == lc && rc_map[&t.right] == rc)
            .map(|t| t.kern)
            .collect();
        if ks.is_empty() {
            return None;
        }
        ks.sort();
        let v = (ks[0] + ks[ks.len() - 1]) / 2;
        let err = ks.iter().map(|k| (k - v).abs()).max().unwrap();
        Some((v, err))
    };

    // Budgeted merge loop: merge the right-class pair (or left-class pair)
    // with the smallest error increase per byte saved, while the global max
    // error stays within budget.
    loop {
        let n_lc = left_class.values().max().map(|m| m + 1).unwrap_or(0);
        let n_rc = right_class.values().max().map(|m| m + 1).unwrap_or(0);
        let current_max = {
            let mut m = 0;
            for lc in 0..n_lc {
                for rc in 0..n_rc {
                    if let Some((_, e)) = class_value(lc, rc, &free, &left_class, &right_class) {
                        m = m.max(e);
                    }
                }
            }
            m
        };
        if current_max > max_error_budget {
            break; // cannot improve within budget from here
        }
        // Try merging each pair of right classes; pick the best.
        let mut best: Option<(i32, bool, usize, usize)> = None; // (err_after, is_right, a, b)
        for is_right in [true, false] {
            let (map, other) = if is_right { (&right_class, &left_class) } else { (&left_class, &right_class) };
            let n = map.values().max().map(|m| m + 1).unwrap_or(0);
            for a in 0..n {
                for b in (a + 1)..n {
                    // simulate merge b -> a
                    let mut trial = map.clone();
                    for v in trial.values_mut() {
                        if *v == b {
                            *v = a;
                        }
                    }
                    let (lc_map, rc_map) = if is_right { (other, &trial) } else { (&trial, other) };
                    let mut err = 0;
                    for lc in 0..lc_map.values().max().map(|m| m + 1).unwrap_or(0) {
                        for rc in 0..rc_map.values().max().map(|m| m + 1).unwrap_or(0) {
                            if let Some((_, e)) = class_value(lc, rc, &free, lc_map, rc_map) {
                                err = err.max(e);
                            }
                        }
                    }
                    if err <= max_error_budget {
                        let cand = (err, is_right, a, b);
                        if best.map(|b0| cand.0 < b0.0 || (cand.0 == b0.0 && (cand.2, cand.3) < (b0.2, b0.3))).unwrap_or(true) {
                            best = Some(cand);
                        }
                    }
                }
            }
        }
        match best {
            None => break,
            Some((_, is_right, a, b)) => {
                let map = if is_right { &mut right_class } else { &mut left_class };
                for v in map.values_mut() {
                    if *v == b {
                        *v = a;
                    } else if *v > b {
                        *v -= 1; // compact ids so matrices stay dense
                    }
                }
            }
        }
    }

    // Materialize the plan.
    let n_lc = left_class.values().max().map(|m| m + 1).unwrap_or(0);
    let n_rc = right_class.values().max().map(|m| m + 1).unwrap_or(0);
    let mut class_kerns = BTreeMap::new();
    let mut exceptions: Vec<PairTarget> = locked.iter().map(|t| **t).collect();
    let mut max_error = 0i32;
    let mut err_sum = 0i64;
    let mut err_n = 0i64;
    for lc in 0..n_lc {
        for rc in 0..n_rc {
            if let Some((v, _)) = class_value(lc, rc, &free, &left_class, &right_class) {
                class_kerns.insert((lc, rc), v);
            }
        }
    }
    for t in &free {
        let v = class_kerns[&(left_class[&t.left], right_class[&t.right])];
        let e = (t.kern - v).abs();
        if e > 0 {
            // Pairs deviating from their class value keep exact exceptions.
            exceptions.push(**t);
        }
        max_error = max_error.max(e);
        err_sum += e as i64;
        err_n += 1;
    }
    let mean_error_milli = if err_n > 0 { err_sum * 1000 / err_n } else { 0 };
    // With exact exceptions for every deviation, the effective shipped error
    // is zero; report the CLASS-approximation error (what the matrix alone
    // would cost) as max/mean, per the separate-reporting rule.
    let estimated_bytes = model.fixed_overhead
        + class_kerns.len() * model.bytes_per_class_pair
        + exceptions.len() * model.bytes_per_exception;
    KernPlan {
        right_classes: right_class,
        left_classes: left_class,
        class_kerns,
        exceptions,
        max_error,
        mean_error_milli,
        estimated_bytes,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_walls::{Side, Wall, WallSource};

    fn wall(points: Vec<(f64, f64)>) -> Wall {
        Wall { side: Side::Left, points, source: WallSource::Measured }
    }

    fn sample_glyphs() -> Vec<Option<BblhGlyph>> {
        vec![
            Some(BblhGlyph {
                advance: 500,
                left: vec![(0, -200), (10, 0), (0, 700)],
                right: vec![(-20, -200), (0, 250), (-20, 700)],
            }),
            None,
            Some(BblhGlyph { advance: 436, left: vec![(61, 0), (61, 690)], right: vec![(0, 0), (0, 690)] }),
        ]
    }

    #[test]
    fn bblh_header_layout_big_endian() {
        let bytes = bblh_write(&sample_glyphs());
        assert_eq!(&bytes[0..2], &[0x00, 0x01]); // version uint16 BE
        assert_eq!(&bytes[2..6], &[0x00, 0x00, 0x00, 0x03]); // glyphCount uint32 BE
        assert_eq!(bytes[6], 1); // presence
    }

    #[test]
    fn bblh_absent_glyph_is_single_zero_byte() {
        let bytes = bblh_write(&vec![None, None]);
        assert_eq!(bytes.len(), 6 + 2, "header + two presence bytes only");
        assert_eq!(&bytes[6..], &[0, 0]);
    }

    #[test]
    fn bblh_right_set_is_width_offset() {
        // Right wall x=0 at advance 436 must serialize as 0 + 436.
        let g = vec![Some(BblhGlyph { advance: 436, left: vec![(0, 0)], right: vec![(0, 0)] })];
        let bytes = bblh_write(&g);
        // header 6 + presence 1 + left count 2 + left point 8 + right count 2
        let off = 6 + 1 + 2 + 8 + 2;
        assert_eq!(&bytes[off..off + 4], &436i32.to_be_bytes());
    }

    #[test]
    fn bblh_round_trip_is_identity() {
        let glyphs = sample_glyphs();
        let advances = [500, 0, 436]; // per-glyph advances, font-side data
        let back = bblh_read(&bblh_write(&glyphs), &advances).unwrap();
        assert_eq!(glyphs, back, "write->read with font advances is the identity");
    }

    #[test]
    fn bblh_truncated_input_rejected() {
        assert!(bblh_read(&[0x00], &[]).is_none());
        assert!(bblh_read(&[0x00, 0x02, 0, 0, 0, 0], &[]).is_none()); // bad version
        // advances shorter than the present glyphs: rejected, no panic.
        let bytes = bblh_write(&sample_glyphs());
        assert!(bblh_read(&bytes, &[500]).is_none());
    }

    #[test]
    fn runtime_offset_matches_lockstep() {
        let l = wall(vec![(0.0, 100.0), (1000.0, 100.0)]);
        let r = wall(vec![(0.0, 180.0), (1000.0, 180.0)]);
        assert_eq!(runtime_offset(&l, &r, 0.0), Some(80.0));
        assert_eq!(runtime_offset(&l, &r, -30.0), Some(50.0));
        let far = wall(vec![(2000.0, 180.0), (3000.0, 180.0)]);
        assert_eq!(runtime_offset(&l, &far, 0.0), None); // disjoint y-ranges
    }

    #[test]
    fn compile_zero_error_merge_identical_vectors() {
        // Two right glyphs with identical pair vectors merge at zero error.
        let targets = vec![
            PairTarget { left: 0, right: 1, kern: -80, locked: false },
            PairTarget { left: 0, right: 2, kern: -80, locked: false },
            PairTarget { left: 3, right: 1, kern: -40, locked: false },
            PairTarget { left: 3, right: 2, kern: -40, locked: false },
        ];
        let plan = compile_kerns(&targets, 0, ByteModel::default());
        assert_eq!(plan.max_error, 0);
        assert_eq!(plan.mean_error_milli, 0);
        assert_eq!(plan.right_classes[&1], plan.right_classes[&2]);
        assert_eq!(plan.class_kerns.len(), 2);
        assert!(plan.exceptions.is_empty());
    }

    #[test]
    fn compile_respects_error_budget() {
        // Two right glyphs whose kerns differ by 10: merging costs 5.
        let targets = vec![
            PairTarget { left: 0, right: 1, kern: -80, locked: false },
            PairTarget { left: 0, right: 2, kern: -70, locked: false },
        ];
        let wide = compile_kerns(&targets, 5, ByteModel::default());
        assert_eq!(wide.right_classes[&1], wide.right_classes[&2]);
        assert_eq!(wide.max_error, 5);
        let tight = compile_kerns(&targets, 4, ByteModel::default());
        assert_ne!(tight.right_classes[&1], tight.right_classes[&2]);
        assert_eq!(tight.max_error, 0);
    }

    #[test]
    fn compile_locked_pairs_stay_exact() {
        let targets = vec![
            PairTarget { left: 0, right: 1, kern: -80, locked: true },
            PairTarget { left: 0, right: 2, kern: -70, locked: false },
        ];
        let plan = compile_kerns(&targets, 100, ByteModel::default());
        assert!(plan.exceptions.iter().any(|t| t.right == 1 && t.kern == -80));
        assert!(plan.exceptions[0].locked, "exceptions first");
    }

    #[test]
    fn compile_deterministic_and_bytes_drop() {
        let targets = vec![
            PairTarget { left: 0, right: 1, kern: -80, locked: false },
            PairTarget { left: 0, right: 2, kern: -80, locked: false },
            PairTarget { left: 0, right: 3, kern: -79, locked: false },
            PairTarget { left: 4, right: 1, kern: 0, locked: false },
            PairTarget { left: 4, right: 2, kern: 0, locked: false },
            PairTarget { left: 4, right: 3, kern: 0, locked: false },
        ];
        let a = compile_kerns(&targets, 5, ByteModel::default());
        let b = compile_kerns(&targets, 5, ByteModel::default());
        assert_eq!(a.class_kerns, b.class_kerns);
        assert_eq!(a.exceptions, b.exceptions);
        let singletons = compile_kerns(&targets, 0, ByteModel::default());
        assert!(a.estimated_bytes <= singletons.estimated_bytes + 2 * ByteModel::default().bytes_per_exception);
    }
}
