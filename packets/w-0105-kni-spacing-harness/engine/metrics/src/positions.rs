//! STEP 5: positions - PairOriginDistance per pair + convergence receipts.
//!
//! This first cut implements the EXACT wall-gap computation (code-grounded,
//! BubbleKern v2): a lockstep walk over the shared y-range of the left
//! glyph's right wall and the right glyph's left wall, sampling at the
//! range endpoints plus every interior vertex y of BOTH walls. Linear
//! interpolation is exact for polylines, so vertex sampling gives the true
//! minimum horizontal gap with no grid error.
//!
//! Raster-plane equivalent (code-grounded, BubbleKern v1): 10-unit grid
//! scan, kern = -min_y(RB_left[y] + LB_right[y]).
//!
//! Reference thresholds from the v1 code (>=10 apply as-is, 8-10 round up
//! to ten, <8 skip; fail-safe maxKern = min(w_left, w_right)/2 in v2; v1
//! had -1) are REFERENCE DEFAULTS, tunable, not doctrine. Known limitation
//! from v1 code: "Adhere to SB" trimming blocks positive kerns in practice;
//! KNI needs both signs, so trimming is a per-font option, not a default.
//!
//! BOUNDARY: the wall-contact offset is a CONSTRAINT + solver
//! initializer (near-contact mechanism), NOT the perceptual target.
//! Collision geometry alone is not letterfitting. The mechanisms solver
//! (step 5, not yet implemented) owns the perceptual target.

use crate::side_walls::Wall;

/// CONVENTION: tolerance for treating two wall-breakpoint y values as the same
/// row, in the same plane units as the wall y coordinates. These y values are
/// floats computed from polyline vertices, so two values that should be equal
/// can differ by rounding noise; 1e-12 is an arbitrary-scale choice far below
/// the plane resolution, not a measured error bound. It is a
/// separate constant from the distance tie tolerance in stress.rs: that one
/// compares chamfer distances, this one compares y coordinates.
const Y_TIE_TOLERANCE: f64 = 1e-12;

/// Result of the exact wall-gap walk for one wall pair.
#[derive(Debug, Clone, Copy)]
pub struct WallGap {
    /// Minimum horizontal gap over the shared y-range (plane units).
    /// Negative means the walls overlap at the current displacement.
    pub min_gap: f64,
    /// The y at which the minimum occurs (first such y).
    pub at_y: f64,
    /// Displacement change that brings the walls into contact:
    /// contact_delta = -min_gap (negative pulls the right wall left).
    pub contact_delta: f64,
    /// Number of sample points used (range endpoints + interior knots).
    pub sampled: usize,
}

/// Exact minimum horizontal gap between two polylines over their shared
/// y-range. `displacement` shifts the right wall's x relative to the left
/// wall's frame: gap(y) = displacement + right.x_at(y) - left.x_at(y).
/// Returns None when the y-ranges do not overlap.
pub fn lockstep_wall_gap(left: &Wall, right: &Wall, displacement: f64) -> Option<WallGap> {
    let ly0 = left.points.first()?.0;
    let ly1 = left.points.last()?.0;
    let ry0 = right.points.first()?.0;
    let ry1 = right.points.last()?.0;
    let y0 = ly0.max(ry0);
    let y1 = ly1.min(ry1);
    if y0 > y1 {
        return None;
    }
    // Sample set: shared-range endpoints + every vertex y of both walls
    // inside the range. The gap is piecewise linear with breaks only at
    // these y's, so the minimum over the samples is the true minimum.
    let mut ys: Vec<f64> = vec![y0, y1];
    for &(y, _) in left.points.iter().chain(right.points.iter()) {
        if y > y0 && y < y1 {
            ys.push(y);
        }
    }
    ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
    ys.dedup_by(|a, b| (*a - *b).abs() < Y_TIE_TOLERANCE);
    let mut best: Option<WallGap> = None;
    for &y in &ys {
        let lx = left.x_at(y)?;
        let rx = right.x_at(y)?;
        let gap = displacement + rx - lx;
        let better = match &best {
            None => true,
            Some(b) => gap < b.min_gap,
        };
        if better {
            best = Some(WallGap { min_gap: gap, at_y: y, contact_delta: -gap, sampled: ys.len() });
        }
    }
    best.map(|mut b| {
        b.sampled = ys.len();
        b
    })
}

/// Reference thresholds distilled from the BubbleKern v1 code. REFERENCE
/// DEFAULTS: tunable parameters, not doctrine.
#[derive(Debug, Clone, Copy)]
pub struct ReferenceThresholds {
    /// |kern| at or above this applies as-is (v1: 10).
    pub apply_at_or_above: f64,
    /// |kern| at or above this (but below apply_at_or_above) rounds up to
    /// apply_at_or_above (v1: 8).
    pub round_up_from: f64,
    /// Fail-safe cap: maxKern = min(w_left, w_right) * this fraction
    /// (v2: 1/2; v1 had -1 as an absolute cap).
    pub max_kern_width_fraction: f64,
    /// "Adhere to SB" trimming: when true, positive kerns are trimmed to
    /// zero (v1 behavior). KNI default is FALSE - both signs are needed;
    /// trimming is a per-font option, not a default.
    pub trim_positive: bool,
}

impl Default for ReferenceThresholds {
    fn default() -> Self {
        Self {
            apply_at_or_above: 10.0,
            round_up_from: 8.0,
            max_kern_width_fraction: 0.5,
            trim_positive: false,
        }
    }
}

impl ReferenceThresholds {
    /// Apply the reference threshold policy to a wall-contact kern value.
    /// Below round_up_from: skipped (returns 0). Between round_up_from and
    /// apply_at_or_above: rounded up to apply_at_or_above (sign preserved).
    /// Capped at min(w_left, w_right) * max_kern_width_fraction.
    pub fn apply(&self, kern: f64, w_left: f64, w_right: f64) -> f64 {
        let cap = w_left.min(w_right) * self.max_kern_width_fraction;
        let mut k = kern;
        if self.trim_positive && k > 0.0 {
            k = 0.0;
        }
        let a = k.abs();
        let signed = if a < self.round_up_from {
            0.0
        } else if a < self.apply_at_or_above {
            self.apply_at_or_above.copysign(k)
        } else {
            k
        };
        signed.clamp(-cap, cap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_walls::{Side, Wall, WallSource};

    fn wall(side: Side, pts: Vec<(f64, f64)>) -> Wall {
        Wall { side, points: pts, source: WallSource::DesignerOverride }
    }

    #[test]
    fn straight_walls_constant_gap() {
        let l = wall(Side::Right, vec![(0.0, 50.0), (100.0, 50.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let g = lockstep_wall_gap(&l, &r, 0.0).unwrap();
        assert_eq!(g.min_gap, 50.0);
        assert_eq!(g.contact_delta, -50.0);
    }

    #[test]
    fn min_at_vertex_inside_range() {
        // Left wall slants right toward the bottom: gap tightens with y.
        let l = wall(Side::Right, vec![(0.0, 45.0), (100.0, 55.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let g = lockstep_wall_gap(&l, &r, 0.0).unwrap();
        assert_eq!(g.min_gap, 45.0);
        assert_eq!(g.at_y, 100.0);
    }

    #[test]
    fn interior_knot_of_either_wall_is_sampled() {
        // Left wall has an outward bulge with a knot at y=30: the minimum
        // sits exactly at that knot (not at range endpoints).
        let l = wall(Side::Right, vec![(0.0, 40.0), (30.0, 60.0), (100.0, 40.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let g = lockstep_wall_gap(&l, &r, 0.0).unwrap();
        assert_eq!(g.min_gap, 40.0);
        assert_eq!(g.at_y, 30.0);
        assert!(g.sampled >= 3);
    }

    #[test]
    fn partial_overlap_scans_shared_range_only() {
        let l = wall(Side::Right, vec![(0.0, 50.0), (40.0, 50.0)]);
        let r = wall(Side::Left, vec![(20.0, 100.0), (100.0, 100.0)]);
        let g = lockstep_wall_gap(&l, &r, 0.0).unwrap();
        assert_eq!(g.min_gap, 50.0);
        assert!(g.at_y >= 20.0 && g.at_y <= 40.0);
    }

    #[test]
    fn disjoint_ranges_return_none() {
        let l = wall(Side::Right, vec![(0.0, 50.0), (40.0, 50.0)]);
        let r = wall(Side::Left, vec![(60.0, 100.0), (100.0, 100.0)]);
        assert!(lockstep_wall_gap(&l, &r, 0.0).is_none());
    }

    #[test]
    fn overlapping_walls_give_positive_contact_delta() {
        let l = wall(Side::Right, vec![(0.0, 90.0), (100.0, 90.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let g = lockstep_wall_gap(&l, &r, -20.0).unwrap();
        assert_eq!(g.min_gap, -10.0); // walls interpenetrate by 10
        assert_eq!(g.contact_delta, 10.0); // must move apart
    }

    #[test]
    fn reference_thresholds_policy() {
        let t = ReferenceThresholds::default();
        assert_eq!(t.apply(5.0, 100.0, 100.0), 0.0); // below 8: skipped
        assert_eq!(t.apply(9.0, 100.0, 100.0), 10.0); // 8..10 rounds up
        assert_eq!(t.apply(12.0, 100.0, 100.0), 12.0); // as-is
        assert_eq!(t.apply(90.0, 100.0, 100.0), 50.0); // capped at min/2
        assert_eq!(t.apply(-9.0, 100.0, 100.0), -10.0); // sign preserved
        let trim = ReferenceThresholds { trim_positive: true, ..Default::default() };
        assert_eq!(trim.apply(20.0, 100.0, 100.0), 0.0); // positive trimmed
        assert_eq!(trim.apply(-20.0, 100.0, 100.0), -20.0); // negative kept
    }
}
