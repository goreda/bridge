//! STEP 3: side_classes - SideDescriptor: CONTINUOUS membership degrees per
//! glyph side.
//!
//! - Membership degrees are CONTINUOUS with NONLINEAR gating; the softmin
//!   gate implemented here is OUR CANDIDATE (sigmoid/softmin
//!   experiments are OUR candidates, not published data), labeled as such, never presented
//!   as published.
//! - REGRESSION BASELINE: existing hard classes. The published HTLS method
//!   resolves a HARD category per glyph via sidecar font rules
//!   (`rules.find_rule`: glyph match -> category -> area factor + reference
//!   glyph; GPL-3.0 upstream consulted for semantics only, no code copied).
//!   `hard_class` below reproduces that hard assignment (nearest prototype),
//!   so any font already carrying hard classes round-trips unchanged.
//! - Category -> area factor resolution (published semantics): a hard rule
//!   scales paramArea by the category factor. Here the factor becomes the
//!   membership-weighted combination over classes (OUR CANDIDATE; the hard
//!   baseline is recovered exactly when one membership is 1).
//! - Latent special-spacing groups (Ahrens 2022) remain tier (d) discovery:
//!   NOT implemented here; `winner_distance` exposes the raw evidence a
//!   discovery pass would need (a side far from every prototype is a
//!   candidate seed for a latent group).
//!
//! Tier (b). Source grounding: Ahrens 2022, HTLS rule semantics.

use crate::side_walls::Wall;

/// Vertical samples per fingerprint (OUR CANDIDATE resolution parameter).
pub const FINGERPRINT_SAMPLES: usize = 9;

/// Default softmin temperature in normalized-distance units (OUR CANDIDATE).
pub const DEFAULT_TEMPERATURE: f64 = 0.03;

/// Scale- and translation-invariant shape fingerprint of one wall.
///
/// The wall is sampled at FINGERPRINT_SAMPLES heights evenly spaced over its
/// own y band (linear interpolation along the polyline is exact, per the
/// positions module doctrine). Each sample is the horizontal position
/// relative to the band mean, normalized by the y extent, so the vector is
/// invariant to horizontal translation and to uniform scaling of the plane
/// (unit/scale invariance gate). A final scalar feature, aspect =
/// (x_max - x_min) / y_extent, captures how much the wall deviates from a
/// straight stem relative to its height.
#[derive(Debug, Clone, PartialEq)]
pub struct WallFingerprint {
    /// Normalized shape samples, top to bottom of the wall band.
    pub shape: Vec<f64>,
    /// (x_max - x_min) / y_extent.
    pub aspect: f64,
}

impl WallFingerprint {
    /// Fingerprint a wall; None if the wall has no positive y extent.
    pub fn from_wall(wall: &Wall) -> Option<Self> {
        let pts = &wall.points;
        if pts.len() < 2 {
            return None;
        }
        let y0 = pts.first().unwrap().0;
        let y1 = pts.last().unwrap().0;
        let h = y1 - y0;
        if h <= 0.0 {
            return None;
        }
        let n = FINGERPRINT_SAMPLES;
        let mut xs = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / (n - 1) as f64;
            xs.push(sample_x(pts, y0 + t * h)?);
        }
        let mean = xs.iter().sum::<f64>() / n as f64;
        let x_min = xs.iter().cloned().fold(f64::INFINITY, f64::min);
        let x_max = xs.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        Some(Self {
            shape: xs.iter().map(|&x| (x - mean) / h).collect(),
            aspect: (x_max - x_min) / h,
        })
    }

    /// Euclidean distance over shape samples plus the aspect feature with
    /// equal weight (OUR CANDIDATE metric; no published metric exists).
    pub fn distance(&self, other: &WallFingerprint) -> f64 {
        let mut acc = (self.aspect - other.aspect).powi(2);
        for (a, b) in self.shape.iter().zip(other.shape.iter()) {
            acc += (a - b).powi(2);
        }
        acc.sqrt()
    }
}

/// Horizontal position of the wall polyline at height y (exact linear
/// interpolation between the bracketing vertices; None outside the band).
fn sample_x(pts: &[(f64, f64)], y: f64) -> Option<f64> {
    if y < pts.first()?.0 || y > pts.last()?.0 {
        return None;
    }
    for w in pts.windows(2) {
        let (ya, xa) = w[0];
        let (yb, xb) = w[1];
        if y >= ya && y <= yb {
            if (yb - ya).abs() < f64::EPSILON {
                return Some(xa);
            }
            let t = (y - ya) / (yb - ya);
            return Some(xa + t * (xb - xa));
        }
    }
    None
}

/// A named side class: one prototype fingerprint plus the category factor
/// that scales the spacing area target (published HTLS rule semantics:
/// effectiveArea = paramArea * factor; 1.0 = no category adjustment).
#[derive(Debug, Clone)]
pub struct SideClass {
    pub id: String,
    pub prototype: WallFingerprint,
    pub area_factor: f64,
}

impl SideClass {
    /// Build a class from an exemplar wall (the class carrier). Returns None
    /// on a degenerate wall.
    pub fn from_exemplar(id: &str, wall: &Wall, area_factor: f64) -> Option<Self> {
        Some(Self {
            id: id.to_string(),
            prototype: WallFingerprint::from_wall(wall)?,
            area_factor,
        })
    }
}

/// Continuous membership readout for one glyph side (tier b artifact).
#[derive(Debug, Clone)]
pub struct SideDescriptor {
    /// (class id, membership degree in (0,1], softmin-normalized, sums to 1).
    pub memberships: Vec<(String, f64)>,
    /// Regression baseline: the hard class a published-style rule lookup
    /// would return (nearest prototype).
    pub hard_class: String,
    /// Raw fingerprint distance to the winning prototype. Large values flag
    /// sides no class explains: evidence for latent-group discovery (tier d),
    /// never silently forced into the nearest class.
    pub winner_distance: f64,
    /// 1 - winning membership. Kept explicit so downstream solvers can
    /// propagate class uncertainty instead of averaging it away (Ahrens).
    pub uncertainty: f64,
}

impl SideDescriptor {
    /// Membership-weighted area factor (OUR CANDIDATE continuous replacement
    /// for the published hard category factor; recovers the hard factor
    /// exactly when one membership is 1).
    pub fn area_factor(&self, classes: &[SideClass]) -> f64 {
        self.memberships
            .iter()
            .map(|(id, w)| {
                let f = classes
                    .iter()
                    .find(|c| &c.id == id)
                    .map(|c| c.area_factor)
                    .unwrap_or(1.0);
                w * f
            })
            .sum()
    }
}

/// Softmin classifier over side classes (gate: OUR CANDIDATE, not published data).
#[derive(Debug, Clone)]
pub struct Classifier {
    pub classes: Vec<SideClass>,
    /// Softmin temperature in normalized-distance units.
    pub temperature: f64,
}

impl Classifier {
    pub fn new(classes: Vec<SideClass>, temperature: f64) -> Self {
        Self { classes, temperature }
    }

    /// Describe one wall side. None on degenerate walls or empty class set.
    pub fn describe(&self, wall: &Wall) -> Option<SideDescriptor> {
        let fp = WallFingerprint::from_wall(wall)?;
        if self.classes.is_empty() || self.temperature <= 0.0 {
            return None;
        }
        let dists: Vec<f64> = self
            .classes
            .iter()
            .map(|c| fp.distance(&c.prototype))
            .collect();
        // softmin gate (OUR CANDIDATE): w_i ~ exp(-d_i / T), normalized.
        // Numerically stable: subtract the min exponent argument first.
        let d_min = dists.iter().cloned().fold(f64::INFINITY, f64::min);
        let exps: Vec<f64> = dists
            .iter()
            .map(|&d| (-(d - d_min) / self.temperature).exp())
            .collect();
        let z: f64 = exps.iter().sum();
        let mut best = 0usize;
        for (i, &d) in dists.iter().enumerate() {
            if d < dists[best] {
                best = i;
            }
        }
        let memberships: Vec<(String, f64)> = self
            .classes
            .iter()
            .zip(exps.iter())
            .map(|(c, e)| (c.id.clone(), e / z))
            .collect();
        Some(SideDescriptor {
            memberships,
            hard_class: self.classes[best].id.clone(),
            winner_distance: dists[best],
            uncertainty: 1.0 - exps[best] / z,
        })
    }
}


// ---------------------------------------------------------------------------
// Anatomy-matched edge classification
// (work list docs/kni/2026-10-16-kern-spacing-next-version-work-list.md,
// next-version item 1: straight-drawn stems classify straight wherever the
// font draws them straight; geometry-first and font-relative by construction)
// ---------------------------------------------------------------------------

/// Anatomy vocabulary for one glyph side. Tokens are 1:1 with the production
/// solver's side-class Display strings (self_anchored_spacing::SideClass) so
/// the integrator wiring is a mechanical mapping with no renaming.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AnatomyClass {
    Straight,
    Round,
    Diagonal,
    Arm,
    Open,
    Empty,
}

impl AnatomyClass {
    /// Stable token, identical to the solver's SideClass Display strings.
    pub fn token(self) -> &'static str {
        match self {
            AnatomyClass::Straight => "straight",
            AnatomyClass::Round => "round",
            AnatomyClass::Diagonal => "diagonal",
            AnatomyClass::Arm => "arm",
            AnatomyClass::Open => "open",
            AnatomyClass::Empty => "empty",
        }
    }
}

impl std::fmt::Display for AnatomyClass {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.token())
    }
}

/// Classify one side of a glyph from its band wall series with anatomy
/// matching. Same input contract as the production `classify_side`
/// (self_anchored_spacing.rs): `wall` = per-band-row distance from the box
/// edge to first ink (>= 0), `s` = the font's own measured stem width; the
/// caller guarantees finite values. The rule order and every threshold of
/// the existing rev2 section-4 rule chain are preserved verbatim; the only
/// addition is the majority-plateau straight test below, inserted after the
/// existing tight-range straight test and before the diagonal test.
///
/// Verdict stability (bit-identity clause): any side the existing chain
/// already reads as Arm, Straight, Diagonal, Round or Open keeps its verdict
/// unless the new majority test fires; the test can only fire where the
/// existing chain would have answered Diagonal, Round or Open, and it is a
/// strict generalisation of the existing straight test (the tightest
/// majority window never spans more than the full range), so every side the
/// existing chain reads as Straight is still Straight.
///
/// Font-relativity (design invariant, work-list item 5): the only length
/// threshold is the font's own stem width s with the same 0.5 factor the
/// existing straight test already applies to the full range (rev2 section 4,
/// reused, not a new constant). The coverage requirement is a bare majority
/// of the side's own rows (m = n/2 + 1, derived from the row count n; no
/// fixed fraction constant). A font that draws its stems round produces no
/// tight majority and keeps its round reading. Provenance:
/// docs/kni/2026-10-18-nv1-anatomy-edge-classification.md.
pub fn classify_side_anatomy(wall: &[f64], s: f64) -> AnatomyClass {
    let n = wall.len();
    if n == 0 {
        return AnatomyClass::Empty;
    }
    let mut min = f64::INFINITY;
    let mut max = f64::NEG_INFINITY;
    let mut max_jump = 0.0f64;
    let mut same_sign = 0usize;
    let mut sign = 0i32;
    let mut sign_changes = 0usize;
    for w in wall.windows(2) {
        let d = w[1] - w[0];
        if d.abs() > max_jump {
            max_jump = d.abs();
        }
        let ds = if d > 0.0 { 1 } else if d < 0.0 { -1 } else { 0 };
        if ds != 0 {
            if sign != 0 && ds != sign {
                sign_changes += 1;
            }
            if ds == sign {
                same_sign += 1;
            }
            sign = ds;
        }
    }
    for &x in wall {
        if x < min {
            min = x;
        }
        if x > max {
            max = x;
        }
    }
    let range = max - min;
    // Arm (existing rev2 section-4 rule, unchanged).
    if s > 0.0 && max_jump > s {
        return AnatomyClass::Arm;
    }
    // Straight, tight range (existing rev2 section-4 rule, unchanged).
    if range <= 0.5 * s {
        return AnatomyClass::Straight;
    }
    // Straight, anatomy-matched (NEW, work-list next-version item 1): a
    // straight-drawn stem holds one edge position along the band; serifs and
    // terminal flares are excursions at the band ends, so the tightest
    // majority of rows spans far less than the full range. The straight
    // verdict uses the same half-stem band the existing tight-range rule
    // uses, applied to the tightest majority window instead of the full
    // range, and keeps the existing round rule's own smoothness bound
    // (max_jump <= 0.5 * s): a side with sharper row-to-row steps keeps its
    // legacy arm/open verdict. A round or diagonal side has no tight
    // majority and falls through to the existing chain unchanged.
    if s > 0.0 && max_jump <= 0.5 * s && straight_by_majority(wall, s) {
        return AnatomyClass::Straight;
    }
    // Diagonal (existing rev2 section-4 rule, unchanged).
    if sign_changes == 0 && same_sign + 1 >= n / 2 {
        return AnatomyClass::Diagonal;
    }
    // Round (existing rev2 section-4 rule, unchanged).
    if s > 0.0 && max_jump <= 0.5 * s {
        return AnatomyClass::Round;
    }
    AnatomyClass::Open
}

/// Majority-plateau straight test: let m = n / 2 + 1 be the bare majority of
/// the side's own row count n (derived from the data, not a fixed fraction),
/// and let w* be the smallest span of m consecutive values in the sorted
/// series (the tightest majority window). The side reads straight iff
/// w* <= 0.5 * s, the same half-stem band the existing rev2 section-4
/// straight rule applies to the full range. The caller additionally applies
/// the existing round rule's smoothness bound (max_jump <= 0.5 * s) before
/// calling this test. No new numeric constant: the coverage count m derives
/// from n and both length thresholds are the existing rules' own, measured
/// in the font's stem width.
fn straight_by_majority(wall: &[f64], s: f64) -> bool {
    let n = wall.len();
    let m = n / 2 + 1;
    let mut v = wall.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mut w_min = f64::INFINITY;
    for i in 0..=(n - m) {
        let w = v[i + m - 1] - v[i];
        if w < w_min {
            w_min = w;
        }
    }
    w_min <= 0.5 * s
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_walls::{Side, Wall, WallSource};

    fn wall(points: Vec<(f64, f64)>) -> Wall {
        Wall { side: Side::Left, points, source: WallSource::Measured }
    }

    /// Straight stem wall: vertical line, y 0..1000.
    fn straight() -> Wall {
        wall(vec![(0.0, 100.0), (1000.0, 100.0)])
    }

    /// Round wall: bowed outward at mid-height (O-like side), y 0..1000.
    fn round_wall() -> Wall {
        wall(vec![
            (0.0, 150.0),
            (250.0, 60.0),
            (500.0, 20.0),
            (750.0, 60.0),
            (1000.0, 150.0),
        ])
    }

    fn two_classes() -> Classifier {
        let straight = SideClass::from_exemplar("straight", &straight(), 1.0).unwrap();
        let round = SideClass::from_exemplar("round", &round_wall(), 0.9).unwrap();
        Classifier::new(vec![straight, round], DEFAULT_TEMPERATURE)
    }

    #[test]
    fn fingerprint_translation_invariant() {
        // Same shape shifted in x: identical fingerprint.
        let shifted = wall(vec![(0.0, 500.0), (1000.0, 500.0)]);
        assert_eq!(
            WallFingerprint::from_wall(&straight()).unwrap(),
            WallFingerprint::from_wall(&shifted).unwrap()
        );
    }

    #[test]
    fn fingerprint_scale_invariant() {
        // Uniformly scaled plane (both axes): identical fingerprint. This is
        // the unit/scale-invariance gate at the class layer.
        let scaled = wall(vec![
            (0.0, 75.0),
            (125.0, 30.0),
            (250.0, 10.0),
            (375.0, 30.0),
            (500.0, 75.0),
        ]);
        let a = WallFingerprint::from_wall(&round_wall()).unwrap();
        let b = WallFingerprint::from_wall(&scaled).unwrap();
        assert!(a.distance(&b) < 1e-9, "scaled fingerprint distance {}", a.distance(&b));
    }

    #[test]
    fn exemplars_recover_hard_classes() {
        // Regression baseline: each exemplar is classified into its own
        // class with near-total membership (hard HTLS rule lookup recovered).
        let clf = two_classes();
        let d_straight = clf.describe(&straight()).unwrap();
        assert_eq!(d_straight.hard_class, "straight");
        assert!(d_straight.uncertainty < 0.01);
        let d_round = clf.describe(&round_wall()).unwrap();
        assert_eq!(d_round.hard_class, "round");
        assert!(d_round.uncertainty < 0.01);
    }

    #[test]
    fn memberships_sum_to_one() {
        let clf = two_classes();
        let d = clf.describe(&round_wall()).unwrap();
        let s: f64 = d.memberships.iter().map(|(_, w)| w).sum();
        assert!((s - 1.0).abs() < 1e-12);
    }

    #[test]
    fn intermediate_wall_gets_mixed_membership() {
        // A wall halfway between the prototypes must not be forced to
        // one-hot: both memberships carry mass, argmax stays nearest.
        let mid = wall(vec![
            (0.0, 125.0),
            (250.0, 80.0),
            (500.0, 60.0),
            (750.0, 80.0),
            (1000.0, 125.0),
        ]);
        let clf = two_classes();
        let d = clf.describe(&mid).unwrap();
        // Both classes must carry real mass (no forced one-hot); the argmax
        // stays the nearest prototype, whichever it is.
        assert!(
            d.memberships.iter().all(|(_, w)| *w > 0.1),
            "mixed membership: {:?}",
            d.memberships
        );
        assert!(d.uncertainty > 0.01, "uncertainty preserved");
    }

    #[test]
    fn far_wall_flags_large_winner_distance() {
        // Diagonal wall (V-like side): no prototype explains it. The
        // membership gate still normalizes, but winner_distance carries the
        // evidence (latent-group seed, tier d).
        let diag = wall(vec![(0.0, 20.0), (1000.0, 300.0)]);
        let clf = two_classes();
        let d = clf.describe(&diag).unwrap();
        let d_round = clf.describe(&round_wall()).unwrap();
        assert!(
            d.winner_distance > 10.0 * d_round.winner_distance.max(1e-9),
            "far wall flagged: {} vs {}",
            d.winner_distance,
            d_round.winner_distance
        );
    }

    #[test]
    fn area_factor_hard_baseline_and_mix() {
        // Published baseline: an exemplar recovers its class factor exactly.
        // Continuous: mixed membership gives the weighted combination.
        let clf = two_classes();
        let d_round = clf.describe(&round_wall()).unwrap();
        let f = d_round.area_factor(&clf.classes);
        assert!((f - 0.9).abs() < 0.01, "hard factor recovered: {f}");
        let mid = wall(vec![
            (0.0, 125.0),
            (250.0, 80.0),
            (500.0, 60.0),
            (750.0, 80.0),
            (1000.0, 125.0),
        ]);
        let d_mid = clf.describe(&mid).unwrap();
        let f_mid = d_mid.area_factor(&clf.classes);
        assert!(f_mid > 0.9 && f_mid < 1.0, "weighted factor {f_mid}");
    }

    #[test]
    fn deterministic() {
        let clf = two_classes();
        let a = clf.describe(&round_wall()).unwrap();
        let b = clf.describe(&round_wall()).unwrap();
        assert_eq!(a.memberships, b.memberships);
        assert_eq!(a.hard_class, b.hard_class);
    }

    #[test]
    fn degenerate_walls_rejected() {
        assert!(WallFingerprint::from_wall(&wall(vec![(10.0, 5.0)])).is_none());
        assert!(WallFingerprint::from_wall(&wall(vec![(10.0, 5.0), (10.0, 9.0)])).is_none());
        let clf = Classifier::new(vec![], DEFAULT_TEMPERATURE);
        assert!(clf.describe(&straight()).is_none());
    }

    // -- anatomy-matched edge classification (work-list next-version item 1) --

    /// Legacy rev2 section-4 rule chain (self_anchored_spacing::classify_side
    /// semantics), replicated in the test module as the regression baseline
    /// for the anatomy-matched change set.
    fn legacy_class(wall: &[f64], s: f64) -> &'static str {
        let n = wall.len();
        if n == 0 {
            return "empty";
        }
        let mut min = f64::INFINITY;
        let mut max = f64::NEG_INFINITY;
        let mut max_jump = 0.0f64;
        let mut same_sign = 0usize;
        let mut sign = 0i32;
        let mut sign_changes = 0usize;
        for w in wall.windows(2) {
            let d = w[1] - w[0];
            if d.abs() > max_jump {
                max_jump = d.abs();
            }
            let ds = if d > 0.0 { 1 } else if d < 0.0 { -1 } else { 0 };
            if ds != 0 {
                if sign != 0 && ds != sign {
                    sign_changes += 1;
                }
                if ds == sign {
                    same_sign += 1;
                }
                sign = ds;
            }
        }
        for &x in wall {
            if x < min {
                min = x;
            }
            if x > max {
                max = x;
            }
        }
        if s > 0.0 && max_jump > s {
            return "arm";
        }
        if max - min <= 0.5 * s {
            return "straight";
        }
        if sign_changes == 0 && same_sign + 1 >= n / 2 {
            return "diagonal";
        }
        if s > 0.0 && max_jump <= 0.5 * s {
            return "round";
        }
        "open"
    }

    /// Straight stem with serif flares, modeled on the documented Marq
    /// Alternate failure measurement (work-list item 3): stem width s = 65,
    /// flat stem edge over most of the cap band, smooth terminal flare of
    /// about 0.84 * s at the band end. The legacy chain reads this round;
    /// the font draws it straight.
    fn serif_stem_series() -> Vec<f64> {
        let mut v: Vec<f64> = (0..58).map(|i| (i % 3) as f64 * 0.2).collect();
        for k in 1..=10 {
            v.push(0.4 + k as f64 * 5.49);
        }
        v
    }

    #[test]
    fn serifed_straight_stem_classifies_straight() {
        let s = 65.0;
        let ser = serif_stem_series();
        assert_eq!(legacy_class(&ser, s), "round", "baseline reproduces the documented miss");
        assert_eq!(classify_side_anatomy(&ser, s), AnatomyClass::Straight);
        // Mirror image (flare at the top of the band) behaves identically.
        let mut flipped = ser.clone();
        flipped.reverse();
        assert_eq!(classify_side_anatomy(&flipped, s), AnatomyClass::Straight);
    }

    #[test]
    fn flat_and_tight_range_stems_stay_straight() {
        let s = 65.0;
        let flat = vec![0.0; 68];
        assert_eq!(classify_side_anatomy(&flat, s), AnatomyClass::Straight);
        let shallow: Vec<f64> = (0..68).map(|i| (i % 5) as f64).collect();
        assert_eq!(legacy_class(&shallow, s), "straight");
        assert_eq!(classify_side_anatomy(&shallow, s), AnatomyClass::Straight);
    }

    #[test]
    fn round_side_keeps_round_reading() {
        // Design invariant: a font that draws the side round reads round.
        let s = 65.0;
        let n = 69;
        // Smooth bowl side (parabola, amplitude 3 stem widths): the legacy
        // chain reads it round; no tight majority exists, so it stays round.
        let bowed: Vec<f64> = (0..n)
            .map(|i| {
                let t = (i as f64 - (n - 1) as f64 / 2.0) / ((n - 1) as f64 / 2.0);
                3.0 * s * (1.0 - t * t)
            })
            .collect();
        assert_eq!(legacy_class(&bowed, s), "round");
        assert_eq!(classify_side_anatomy(&bowed, s), AnatomyClass::Round);
        // Same model at 4.4 stem widths (the fixture O's proportions): no
        // tight majority either; the round reading is preserved.
        let wide: Vec<f64> = (0..n)
            .map(|i| {
                let t = (i as f64 - (n - 1) as f64 / 2.0) / ((n - 1) as f64 / 2.0);
                4.4 * s * (1.0 - t * t)
            })
            .collect();
        assert_eq!(legacy_class(&wide, s), "round");
        assert_eq!(classify_side_anatomy(&wide, s), AnatomyClass::Round);
    }

    #[test]
    fn diagonal_side_keeps_diagonal_reading() {
        let s = 65.0;
        let diag: Vec<f64> = (0..69).map(|i| i as f64 * (3.0 * s / 68.0)).collect();
        assert_eq!(legacy_class(&diag, s), "diagonal");
        assert_eq!(classify_side_anatomy(&diag, s), AnatomyClass::Diagonal);
    }

    #[test]
    fn arm_and_open_verdicts_unchanged() {
        let s = 65.0;
        // Arm: one jump larger than the stem width.
        let mut arm = vec![0.0; 40];
        arm.extend(vec![1.2 * s; 29]);
        assert_eq!(legacy_class(&arm, s), "arm");
        assert_eq!(classify_side_anatomy(&arm, s), AnatomyClass::Arm);
        // Open: alternating rows, jump between 0.5*s and s, no drift dominance.
        let zigzag: Vec<f64> = (0..69).map(|i| if i % 2 == 0 { 0.0 } else { 0.8 * s }).collect();
        assert_eq!(legacy_class(&zigzag, s), "open");
        assert_eq!(classify_side_anatomy(&zigzag, s), AnatomyClass::Open);
    }

    #[test]
    fn majority_plateau_boundary_cases() {
        let s = 100.0;
        // Bare majority plateau (6 of 10 rows) plus a gentle terminal ramp:
        // the tightest majority window spans zero, the ramp rows are the
        // terminal excursion; legacy reads the ramp dominance as round.
        let majority: Vec<f64> = vec![0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 30.0, 60.0, 90.0, 120.0];
        assert_eq!(legacy_class(&majority, s), "round");
        assert_eq!(classify_side_anatomy(&majority, s), AnatomyClass::Straight);
        // A one-step ledge of a full stem width is not a smooth flare: the
        // existing smoothness bound keeps the legacy open verdict even with
        // a majority plateau present.
        let ledge: Vec<f64> = [0.0; 6].iter().chain([100.0; 4].iter()).cloned().collect();
        assert_eq!(legacy_class(&ledge, s), "open");
        assert_eq!(classify_side_anatomy(&ledge, s), AnatomyClass::Open);
    }

    #[test]
    fn anatomy_classification_is_deterministic() {
        let s = 65.0;
        let ser = serif_stem_series();
        assert_eq!(classify_side_anatomy(&ser, s), classify_side_anatomy(&ser, s));
    }

    #[test]
    fn anatomy_tokens_match_solver_vocabulary() {
        assert_eq!(AnatomyClass::Straight.token(), "straight");
        assert_eq!(AnatomyClass::Round.token(), "round");
        assert_eq!(AnatomyClass::Diagonal.token(), "diagonal");
        assert_eq!(AnatomyClass::Arm.token(), "arm");
        assert_eq!(AnatomyClass::Open.token(), "open");
        assert_eq!(AnatomyClass::Empty.token(), "empty");
        assert_eq!(classify_side_anatomy(&[], 65.0), AnatomyClass::Empty);
    }

    /// Fixture acceptance evidence: the in-repo kern wall fixture
    /// (tests/fixtures/walls.tsv) reproduces the documented failure - the
    /// legacy chain reads the straight-drawn stems H/N/I/L round - and the
    /// anatomy-matched rule flips exactly those straight-drawn stem sides to
    /// straight while every round/diagonal control keeps its legacy verdict.
    /// Run with --nocapture to print the full before/after table.
    #[test]
    fn fixture_stems_flip_to_straight_rounds_unchanged() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/walls.tsv");
        let text = std::fs::read_to_string(path).expect("fixture walls.tsv");
        let mut walls: Vec<(String, Vec<(f64, f64, f64)>)> = Vec::new();
        for line in text.lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let f: Vec<&str> = line.split('\t').collect();
            assert!(f.len() == 5, "fixture row width: {line}");
            let y: f64 = f[2].parse().unwrap();
            let lx: f64 = f[3].parse().unwrap();
            let rx: f64 = f[4].parse().unwrap();
            if walls.last().map(|(g, _)| g != f[0]).unwrap_or(true) {
                walls.push((f[0].to_string(), Vec::new()));
            }
            walls.last_mut().unwrap().1.push((y, lx, rx));
        }
        let band_of = |g: &str| -> (f64, f64) {
            let rows = &walls.iter().find(|(id, _)| id == g).unwrap().1;
            let y0 = rows.iter().map(|r| r.0).fold(f64::INFINITY, f64::min);
            let y1 = rows.iter().map(|r| r.0).fold(f64::NEG_INFINITY, f64::max);
            (y0, y1)
        };
        // Baseline and heights measured from the fixture font's own glyphs:
        // baseline and x-height from x, cap height from H (same anchors the
        // solver derives from the font).
        let (by0, _) = band_of("x");
        let (_, bx1) = band_of("x");
        let (_, bh1) = band_of("H");
        let baseline = by0;
        let x_height = bx1 - baseline;
        let cap = bh1 - baseline;
        // Stem width estimate: median ink width of l rows inside the band
        // (the fixture carries outer walls only, no interval list; the
        // production s is the median stem-interval width over n,h,m,H,I,l).
        let mut lw: Vec<f64> = walls
            .iter()
            .find(|(id, _)| id == "l")
            .unwrap()
            .1
            .iter()
            .filter(|r| r.0 >= baseline && r.0 <= baseline + x_height)
            .map(|r| r.2 - r.1)
            .collect();
        lw.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let s = lw[lw.len() / 2];

        let series = |glyph: &str, left: bool| -> Vec<f64> {
            let rows = &walls.iter().find(|(id, _)| id == glyph).unwrap().1;
            let is_cap = glyph.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false);
            let top = baseline + if is_cap { cap } else { x_height };
            let band: Vec<(f64, f64)> = rows
                .iter()
                .filter(|r| r.0 >= baseline && r.0 <= top)
                .map(|r| (r.1, r.2))
                .collect();
            if left {
                let m = band.iter().map(|r| r.0).fold(f64::INFINITY, f64::min);
                band.iter().map(|r| r.0 - m).collect()
            } else {
                let m = band.iter().map(|r| r.1).fold(f64::NEG_INFINITY, f64::max);
                band.iter().map(|r| m - r.1).collect()
            }
        };

        let glyphs: Vec<String> = walls.iter().map(|(g, _)| g.clone()).collect();
        println!("# anatomy acceptance table (s={s:.3}, baseline={baseline}, x_height={x_height}, cap={cap})");
        println!("# glyph\tside\tlegacy\tanatomy");
        for g in &glyphs {
            for left in [true, false] {
                let ser = series(g, left);
                if ser.is_empty() {
                    continue;
                }
                let old = legacy_class(&ser, s);
                let new = classify_side_anatomy(&ser, s).token();
                if old != new {
                    println!("{g}\t{}\t{old}\t{new}", if left { "L" } else { "R" });
                }
                // Generalisation property on the fixture: every side the
                // legacy chain reads straight stays straight.
                if old == "straight" {
                    assert_eq!(new, "straight", "{g} {} lost its straight reading", if left { "L" } else { "R" });
                }
            }
        }
        // The documented miss: the straight-drawn stem sides of H, N, I, L
        // read round under the legacy chain and now classify straight. L's
        // right side carries the foot arm in this fixture font: the font
        // does not draw it straight, and the arm verdict is preserved.
        for (g, left) in [("H", true), ("H", false), ("N", true), ("N", false), ("I", true), ("I", false), ("L", true)] {
            let ser = series(g, left);
            assert_eq!(legacy_class(&ser, s), "round", "{g} baseline");
            assert_eq!(
                classify_side_anatomy(&ser, s),
                AnatomyClass::Straight,
                "{g} {} must classify straight",
                if left { "L" } else { "R" }
            );
        }
        let l_right = series("L", false);
        assert_eq!(legacy_class(&l_right, s), "arm");
        assert_eq!(classify_side_anatomy(&l_right, s), AnatomyClass::Arm, "L R foot arm preserved");
        // Font-relative invariant: the fixture's round and diagonal sides
        // keep their legacy verdicts.
        for (g, left) in [("O", true), ("O", false), ("o", true), ("o", false), ("C", true), ("c", true)] {
            let ser = series(g, left);
            assert_eq!(
                classify_side_anatomy(&ser, s).token(),
                legacy_class(&ser, s),
                "{g} {} changed off the straight miss set",
                if left { "L" } else { "R" }
            );
        }
        for (g, left) in [("V", false), ("W", false), ("v", false), ("w", false)] {
            let ser = series(g, left);
            assert_eq!(classify_side_anatomy(&ser, s), AnatomyClass::Diagonal, "{g} diagonal preserved");
        }
    }
}
