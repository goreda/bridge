//! Exact slab rows for stage-4 measurement (assignment relayed by Main, 8:19 PM).
//!
//! The stage-3 profile samples ink every `scan_row_step` font units. A contact narrower in y than that pitch can fall between two
//! sampled rows and read as clear. This module removes the sampling: it builds the ink intervals of a glyph's flattened rings at the
//! EXACT limits of every vertex-bounded slab, for the union of both glyphs' vertex y values. Inside a slab no ring vertex exists, so
//! every boundary is a straight segment and the nearest-wall gap is piecewise linear in y. Its extremes, and the presence or absence
//! of an overlap, are therefore decided at the slab ends. Nothing here is a row step or a tolerance.
//!
//! The rows feed the EXISTING measurement code (`signed_clearance::*_rows`), so the nearest-wall rule, the skip rule and the
//! strict-overlap predicate are the same ones the solver and the guard already use. The geometry is the production flatten
//! (0.5 font units from the original curves): exact for those polygons, approximate for the curves they stand for.
//!
//! Fill rule: non-zero winding, as in `outline_spacing`. Only intervals of width exactly 0 are dropped (no merge guard).

use crate::outline_spacing::{AlignedRow, InkInterval};

#[derive(Debug, Clone, PartialEq)]
pub enum ExactError {
    NonFinite,
    NoEdges,
}

#[derive(Debug, Clone, Copy)]
struct SlabEdge {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    dir: i32,
}

impl SlabEdge {
    fn x_at(&self, y: f64) -> f64 {
        self.x0 + (y - self.y0) / (self.y1 - self.y0) * (self.x1 - self.x0)
    }
}

/// One glyph's flattened rings cut into vertex-bounded slabs.
#[derive(Debug, Clone)]
pub struct ExactSlabs {
    ys: Vec<f64>,
    /// `slabs[i]` = edges spanning the window (ys[i], ys[i+1]), ordered by x at the window mid-height.
    slabs: Vec<Vec<SlabEdge>>,
    pub ring_count: usize,
    pub edge_count: usize,
}

impl ExactSlabs {
    pub fn from_rings(rings: &[Vec<[f64; 2]>]) -> Result<ExactSlabs, ExactError> {
        let mut edges: Vec<SlabEdge> = Vec::new();
        for ring in rings {
            let n = ring.len();
            for p in ring {
                if !p[0].is_finite() || !p[1].is_finite() {
                    return Err(ExactError::NonFinite);
                }
            }
            for k in 0..n {
                let (a, b) = (ring[k], ring[(k + 1) % n]);
                if a[1] != b[1] {
                    edges.push(SlabEdge { x0: a[0], y0: a[1], x1: b[0], y1: b[1], dir: if b[1] > a[1] { 1 } else { -1 } });
                }
            }
        }
        if edges.is_empty() {
            return Err(ExactError::NoEdges);
        }
        let mut ys: Vec<f64> = edges.iter().flat_map(|e| [e.y0, e.y1]).collect();
        ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
        ys.dedup();
        let mut slabs: Vec<Vec<SlabEdge>> = Vec::with_capacity(ys.len().saturating_sub(1));
        for w in ys.windows(2) {
            let (lo, hi) = (w[0], w[1]);
            let mid = 0.5 * (lo + hi);
            let mut v: Vec<SlabEdge> = edges
                .iter()
                .copied()
                .filter(|e| e.y0.min(e.y1) <= lo && e.y0.max(e.y1) >= hi)
                .collect();
            v.sort_by(|a, b| a.x_at(mid).partial_cmp(&b.x_at(mid)).unwrap());
            slabs.push(v);
        }
        Ok(ExactSlabs { ys, slabs, ring_count: rings.len(), edge_count: edges.len() })
    }

    /// Ink intervals of window `i` at height `y` (one of its two limits, taken from inside the window).
    fn intervals(&self, i: usize, y: f64) -> Vec<InkInterval> {
        let mut out = Vec::new();
        let mut winding = 0i32;
        let mut prev: Option<f64> = None;
        for e in &self.slabs[i] {
            let x = e.x_at(y);
            if winding != 0 {
                if let Some(px) = prev {
                    if x > px {
                        out.push(InkInterval { left: px, right: x });
                    }
                }
            }
            winding += e.dir;
            prev = Some(x);
        }
        out
    }

    fn window_of(&self, ya: f64, yb: f64) -> Option<usize> {
        let i = self.ys.partition_point(|&v| v <= ya);
        if i == 0 {
            return None;
        }
        let i = i - 1;
        if i + 1 < self.ys.len() && self.ys[i] <= ya && yb <= self.ys[i + 1] { Some(i) } else { None }
    }
}

/// Exact rows for a pair placed with the right glyph shifted by `shift` relative to the left (shift = origin_distance + r_tr - l_tr).
///
/// Cuts are every ring-vertex y of both glyphs PLUS every y where a left edge crosses a right edge (all edge pairs, not only
/// boundary pairs) inside a vertex slab. Inside a sub-slab no vertex exists and no left edge crosses a right edge, so the left-to-right
/// order of every boundary is fixed: facing-wall membership cannot flip and every overlap amount is linear in y. The extremes of the
/// nearest-wall gap and of the overlap are therefore at the sub-slab limits. A scissor (two straight edges crossing mid-slab) is
/// caught because its crossing y is a cut. Placement dependent: rebuild for each placement.
/// Contact contract: touching intervals (gap exactly 0) are not an overlap; `collides()` stays `min_gap < 0 || interval_hit` (strict).
pub fn exact_aligned_rows_at(left: &ExactSlabs, right: &ExactSlabs, shift: f64) -> Vec<AlignedRow> {
    let mut ys: Vec<f64> = left.ys.iter().chain(right.ys.iter()).copied().collect();
    ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
    ys.dedup();
    let mut rows = Vec::new();
    for w in ys.windows(2) {
        let (ya, yb) = (w[0], w[1]);
        if !(yb > ya) {
            continue;
        }
        let lw = left.window_of(ya, yb);
        let rw = right.window_of(ya, yb);
        if lw.is_none() && rw.is_none() {
            continue;
        }
        let mut cuts = vec![ya];
        if let (Some(i), Some(j)) = (lw, rw) {
            let mut crossings: Vec<f64> = Vec::new();
            for e in &left.slabs[i] {
                let (ea, eb) = (e.x_at(ya), e.x_at(yb));
                for f in &right.slabs[j] {
                    let ga = ea - (f.x_at(ya) + shift);
                    let gb = eb - (f.x_at(yb) + shift);
                    if (ga < 0.0 && gb > 0.0) || (ga > 0.0 && gb < 0.0) {
                        let y = ya + (yb - ya) * ga / (ga - gb);
                        if y > ya && y < yb {
                            crossings.push(y);
                        }
                    }
                }
            }
            crossings.sort_by(|a, b| a.partial_cmp(b).unwrap());
            crossings.dedup();
            cuts.extend(crossings);
        }
        cuts.push(yb);
        for c in cuts.windows(2) {
            let (c0, c1) = (c[0], c[1]);
            if !(c1 > c0) {
                continue;
            }
            for y in [c0, c1] {
                let l = lw.map(|i| left.intervals(i, y)).unwrap_or_default();
                let r = rw.map(|i| right.intervals(i, y)).unwrap_or_default();
                if l.is_empty() && r.is_empty() {
                    continue;
                }
                rows.push(AlignedRow { y, weight: 0.5 * (c1 - c0), left: l, right: r });
            }
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
    use crate::signed_clearance::{evidence_at, exact_evidence_rows};

    fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
        vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }
    fn slabs(r: Vec<Vec<[f64; 2]>>) -> ExactSlabs {
        ExactSlabs::from_rings(&r).unwrap()
    }
    fn prof(id: &str, rings: Vec<Vec<[f64; 2]>>, step: f64) -> crate::outline_spacing::OutlineProfile {
        profile_outline(
            &OutlineInput { glyph_id: id.into(), source_pin: "t".into(), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0, rings },
            ScanPolicy { row_step: step, max_rows: 100000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) },
        )
        .unwrap()
    }

    #[test]
    fn rectangles_have_the_analytic_gap_and_the_sampled_gap() {
        let (l, r) = (slabs(vec![rect(0.0, 0.0, 20.0, 40.0)]), slabs(vec![rect(0.0, 10.0, 15.0, 50.0)]));
        let rows = exact_aligned_rows_at(&l, &r, 30.0);
        let e = exact_evidence_rows(&rows, 0.0, 0.0, 30.0).unwrap();
        assert_eq!(e.clearance.min_gap, 10.0);
        assert!(!e.interval_hit);
        let s = evidence_at(&prof("l", vec![rect(0.0, 0.0, 20.0, 40.0)], 10.0), &prof("r", vec![rect(0.0, 10.0, 15.0, 50.0)], 10.0), 0.0, 0.0, 30.0).unwrap();
        assert_eq!(s.clearance.min_gap, e.clearance.min_gap);
        let hit = exact_evidence_rows(&exact_aligned_rows_at(&l, &r, 15.0), 0.0, 0.0, 15.0).unwrap();
        assert!(hit.interval_hit && hit.clearance.min_gap == -5.0, "{hit:?}");
    }

    /// A thin spike on a tall bar, lying wholly between two sampled row midpoints (5 and 15 at a 10 unit pitch).
    #[test]
    fn a_spike_between_sample_rows_is_a_collision_for_the_exact_rows_and_clear_for_the_sampled() {
        let block = vec![rect(0.0, 0.0, 20.0, 40.0)];
        let bar = vec![vec![[40.0, 0.0], [60.0, 0.0], [60.0, 40.0], [40.0, 40.0], [40.0, 13.5], [15.0, 12.5], [40.0, 11.5]]];
        let (l, r) = (slabs(block.clone()), slabs(bar.clone()));
        let ex = exact_evidence_rows(&exact_aligned_rows_at(&l, &r, 0.0), 0.0, 0.0, 0.0).unwrap();
        assert!(ex.interval_hit && ex.clearance.min_gap < 0.0, "{ex:?}");
        let sp = evidence_at(&prof("l", block, 10.0), &prof("r", bar, 10.0), 0.0, 0.0, 0.0).unwrap();
        assert!(!sp.interval_hit && sp.clearance.min_gap > 0.0, "sampled model misses the spike: {sp:?}");
    }

    #[test]
    fn non_finite_and_edge_free_input_is_refused_not_guessed() {
        assert_eq!(ExactSlabs::from_rings(&[vec![[0.0, f64::NAN], [1.0, 0.0], [1.0, 1.0]]]).unwrap_err(), ExactError::NonFinite);
        assert_eq!(ExactSlabs::from_rings(&[vec![[0.0, 1.0], [1.0, 1.0], [2.0, 1.0]]]).unwrap_err(), ExactError::NoEdges);
        assert_eq!(ExactSlabs::from_rings(&[]).unwrap_err(), ExactError::NoEdges);
    }

    #[test]
    fn interleaved_piece_behind_the_wall_is_skipped_not_a_collision() {
        // left ink [0,20]; right pieces [-10,-5] (behind, no overlap) and [30,50]: exact nearest-wall gap is +10 and there is no hit
        let l = slabs(vec![rect(0.0, 0.0, 20.0, 40.0)]);
        let r = slabs(vec![rect(-10.0, 0.0, -5.0, 40.0), rect(30.0, 0.0, 50.0, 40.0)]);
        let e = exact_evidence_rows(&exact_aligned_rows_at(&l, &r, 0.0), 0.0, 0.0, 0.0).unwrap();
        assert_eq!(e.clearance.min_gap, 10.0);
        assert!(!e.interval_hit && !e.collides());
    }

    #[test]
    fn counter_rings_follow_non_zero_winding() {
        // outer ring ccw, hole cw: the hole is not ink
        let outer = vec![[0.0, 0.0], [30.0, 0.0], [30.0, 30.0], [0.0, 30.0]];
        let hole = vec![[10.0, 10.0], [10.0, 20.0], [20.0, 20.0], [20.0, 10.0]];
        let g = slabs(vec![outer, hole]);
        let probe = slabs(vec![rect(0.0, 12.0, 4.0, 18.0)]); // sits inside the hole's x range when shifted by 13
        let e = exact_evidence_rows(&exact_aligned_rows_at(&g, &probe, 13.0), 0.0, 0.0, 13.0).unwrap();
        assert!(!e.interval_hit, "probe at x 13..17 lies in the counter: {e:?}");
    }

    /// SCISSOR (chief, amendment 24): A = [0,10] fixed; B runs [20,30] at the bottom to [-30,-20] at the top inside ONE vertex slab.
    /// At both vertex limits B is clear (ahead of A, then wholly behind A, so skipped), yet B passes through A in the middle.
    #[test]
    fn scissor_edges_crossing_inside_one_slab_are_a_collision() {
        let a = slabs(vec![rect(0.0, 0.0, 10.0, 10.0)]);
        let b = slabs(vec![vec![[20.0, 0.0], [30.0, 0.0], [-20.0, 10.0], [-30.0, 10.0]]]);
        // limits only (vertex cuts, no crossing cuts) would read clear: prove it by building those rows by hand
        let limits_only = vec![
            AlignedRow { y: 0.0, weight: 5.0, left: vec![InkInterval { left: 0.0, right: 10.0 }], right: vec![InkInterval { left: 20.0, right: 30.0 }] },
            AlignedRow { y: 10.0, weight: 5.0, left: vec![InkInterval { left: 0.0, right: 10.0 }], right: vec![InkInterval { left: -30.0, right: -20.0 }] },
        ];
        let blind = exact_evidence_rows(&limits_only, 0.0, 0.0, 0.0).unwrap();
        assert!(!blind.interval_hit && blind.clearance.min_gap >= 0.0, "vertex-limit rows are blind to the scissor: {blind:?}");
        let e = exact_evidence_rows(&exact_aligned_rows_at(&a, &b, 0.0), 0.0, 0.0, 0.0).unwrap();
        assert!(e.interval_hit && e.collides() && e.clearance.min_gap < 0.0, "crossing cuts expose it: {e:?}");
        assert_eq!(e.clearance.min_gap, -10.0, "full overlap of the 10 wide wall at the widest cut (B right edge meets A right edge)");
    }

    /// Contact contract: exact contact (gap 0) is NOT a collision; any real penetration is.
    #[test]
    fn exact_contact_is_not_a_collision_and_one_ulp_of_penetration_is() {
        let (l, r) = (slabs(vec![rect(0.0, 0.0, 20.0, 40.0)]), slabs(vec![rect(0.0, 10.0, 15.0, 50.0)]));
        let touch = exact_evidence_rows(&exact_aligned_rows_at(&l, &r, 20.0), 0.0, 0.0, 20.0).unwrap();
        assert_eq!(touch.clearance.min_gap, 0.0);
        assert!(!touch.interval_hit && !touch.collides(), "{touch:?}");
        let d = 20.0_f64 - 1e-9;
        let pen = exact_evidence_rows(&exact_aligned_rows_at(&l, &r, d), 0.0, 0.0, d).unwrap();
        assert!(pen.collides(), "{pen:?}");
        // horizontal-edge contact: stacked blocks that only share a horizontal edge never face each other
        let (u, v) = (slabs(vec![rect(0.0, 0.0, 20.0, 10.0)]), slabs(vec![rect(0.0, 10.0, 20.0, 20.0)]));
        assert!(exact_evidence_rows(&exact_aligned_rows_at(&u, &v, 0.0), 0.0, 0.0, 0.0).is_none(), "no slab holds ink of both: not measurable, typed upstream");
    }
}
