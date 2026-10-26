//! LATTICE-1 prototype: style-level lattice detection and contour-level
//! dot/stroke classification for grid-style fonts (first target Mona
//! Alt/Regular). Prototype only - no production-path wiring. Included by the
//! example/test harness via #[path]; not a lib module.
//!
//! Design (chief architect brief 2026-10-18): grid dots cluster at one small
//! radius in the contour-size histogram; dot centers snap to a regular 2D
//! lattice shared across the style's glyphs. Conservative gate: every failed
//! check yields NoLattice naming the check; NoLattice must be bit-identical
//! to current behavior (this stage changes no behavior anywhere).
//!
//! Stage 3 (routing dots to the parametric circle fit) is a later writer.

use kni_core::capture::CapturedRing;
use kni_core::reference_slice::Point;

// ---------- per-ring features ----------

#[derive(Clone, Debug)]
pub struct RingFeatures {
    pub glyph: String,
    pub ring_index: usize,
    pub hole: bool,
    pub area: f64,
    pub perimeter: f64,
    pub circularity: f64,
    pub radius_equiv: f64,
    pub bbox_w: f64,
    pub bbox_h: f64,
    pub center: Point,
    pub n_points: usize,
    pub n_corners: usize,
}

pub fn ring_features(glyph: &str, ring_index: usize, r: &CapturedRing) -> RingFeatures {
    let pts = &r.points;
    let mut a2 = 0.0;
    let mut per = 0.0;
    let (mut mnx, mut mny, mut mxx, mut mxy) =
        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for i in 0..pts.len() {
        let u = pts[i];
        let v = pts[(i + 1) % pts.len()];
        a2 += u.x * v.y - v.x * u.y;
        per += (v.x - u.x).hypot(v.y - u.y);
        mnx = mnx.min(u.x);
        mxx = mxx.max(u.x);
        mny = mny.min(u.y);
        mxy = mxy.max(u.y);
    }
    let area = a2.abs() / 2.0;
    let circularity = if per > 0.0 {
        4.0 * std::f64::consts::PI * area / (per * per)
    } else {
        0.0
    };
    let radius_equiv = (area / std::f64::consts::PI).sqrt();
    RingFeatures {
        glyph: glyph.to_string(),
        ring_index,
        hole: r.hole,
        area,
        perimeter: per,
        circularity,
        radius_equiv,
        bbox_w: mxx - mnx,
        bbox_h: mxy - mny,
        center: Point {
            x: (mnx + mxx) / 2.0,
            y: (mny + mxy) / 2.0,
        },
        n_points: pts.len(),
        n_corners: r.corners.len(),
    }
}

// ---------- typed ledger rows ----------

#[derive(Clone, Debug)]
pub struct LatticeParams {
    pub dot_radius: f64,
    pub dot_radius_tol: f64,
    pub spacing: f64,
    pub basis_angle: f64,
    pub basis_angle2: f64,
    pub phase: (f64, f64),
    pub coverage: f64,
    pub per_glyph_phase_agreement: f64,
    pub dot_count: usize,
    pub glyph_count: usize,
    pub candidate_count: usize,
}

#[derive(Clone, Debug)]
pub enum LatticeStatus {
    Detected(LatticeParams),
    NoLattice { failed_check: &'static str },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContourClass {
    LatticeDot,
    Stroke,
    Ambiguous,
}

impl ContourClass {
    pub fn as_str(self) -> &'static str {
        match self {
            ContourClass::LatticeDot => "lattice_dot",
            ContourClass::Stroke => "stroke",
            ContourClass::Ambiguous => "ambiguous",
        }
    }
}

// ---------- tuning constants (measured-class thresholds, named) ----------

/// Dot candidates: closed ink rings with near-circular shape.
const CAND_MIN_CIRCULARITY: f64 = 0.75;
/// Aspect-ratio band for candidates (bbox w/h within [1/b, b]).
const CAND_MAX_ASPECT: f64 = 1.25;
/// A lattice needs many dots: absolute floor and fraction of ink rings.
const MIN_DOT_COUNT: usize = 30;
const MIN_DOT_FRACTION: f64 = 0.20;
/// 1D radius histogram bin, relative to a first-moment estimate.
const RADIUS_BIN_FRAC: f64 = 0.10;
/// Nearest-neighbor histogram: spacing peak must hold this fraction of
/// dot-center nearest neighbors (designer grids are dense and regular).
const MIN_SPACING_PEAK_SHARE: f64 = 0.50;
/// Basis-vector acceptance band around the spacing estimate.
const BASIS_LEN_LO: f64 = 0.80;
const BASIS_LEN_HI: f64 = 1.25;
/// Two basis directions must be near-orthogonal (radians).
const ORTHO_TOL: f64 = 0.26; // ~15 deg
/// Coverage: fraction of dot centers within snap tolerance of the lattice.
const MIN_COVERAGE: f64 = 0.75;
/// Snap tolerance for lattice membership, relative to spacing.
const SNAP_TOL_FRAC: f64 = 0.20;

// ---------- histogram helpers ----------

struct Hist1D {
    bin: f64,
    origin: f64,
    counts: Vec<(f64, usize)>, // (bin center, count), sparse, sorted by center
}

impl Hist1D {
    fn new(bin: f64, origin: f64) -> Self {
        Hist1D {
            bin,
            origin,
            counts: Vec::new(),
        }
    }
    fn add(&mut self, v: f64, w: usize) {
        let idx = ((v - self.origin) / self.bin).floor() as i64;
        let center = self.origin + (idx as f64 + 0.5) * self.bin;
        match self
            .counts
            .binary_search_by(|a| a.0.partial_cmp(&center).unwrap())
        {
            Ok(i) => self.counts[i].1 += w,
            Err(i) => self.counts.insert(i, (center, w)),
        }
    }
    fn peak(&self) -> Option<(f64, usize)> {
        self.counts.iter().copied().max_by_key(|&(_, c)| c)
    }
}

fn weighted_mean_sd(pairs: &[(f64, usize)]) -> (f64, f64) {
    let n: usize = pairs.iter().map(|&(_, c)| c).sum();
    if n == 0 {
        return (0.0, 0.0);
    }
    let mean = pairs.iter().map(|&(v, c)| v * c as f64).sum::<f64>() / n as f64;
    let var = pairs
        .iter()
        .map(|&(v, c)| (v - mean) * (v - mean) * c as f64)
        .sum::<f64>()
        / n as f64;
    (mean, var.sqrt())
}

// ---------- stage 1: detection ----------

/// Detect the style-level lattice from pre-fit captured rings of every glyph
/// of the style. All geometry in capture pixel space; the lattice basis is
/// estimated from within-glyph pairwise differences (origin-invariant), the
/// phase from cross-glyph residues (the designer grid is one shared frame).
pub fn detect_lattice(rings: &[RingFeatures]) -> LatticeStatus {
    let glyph_count = {
        let mut g: Vec<&str> = rings.iter().map(|r| r.glyph.as_str()).collect();
        g.sort_unstable();
        g.dedup();
        g.len()
    };
    // Check 1: dot candidate cluster in the contour-size histogram.
    let ink: Vec<&RingFeatures> = rings.iter().filter(|r| !r.hole).collect();
    let candidates: Vec<&RingFeatures> = ink
        .iter()
        .copied()
        .filter(|r| {
            r.circularity >= CAND_MIN_CIRCULARITY
                && r.bbox_w > 0.0
                && r.bbox_h > 0.0
                && {
                    let aspect = r.bbox_w.max(r.bbox_h) / r.bbox_w.min(r.bbox_h);
                    aspect <= CAND_MAX_ASPECT
                }
                && r.radius_equiv > 0.0
        })
        .collect();
    if candidates.len() < MIN_DOT_COUNT
        || (candidates.len() as f64) < MIN_DOT_FRACTION * ink.len().max(1) as f64
    {
        return LatticeStatus::NoLattice {
            failed_check: "dot_cluster_size",
        };
    }
    let r_mean = candidates.iter().map(|r| r.radius_equiv).sum::<f64>()
        / candidates.len() as f64;
    let mut rh = Hist1D::new((r_mean * RADIUS_BIN_FRAC).max(0.25), 0.0);
    for c in &candidates {
        rh.add(c.radius_equiv, 1);
    }
    let (peak_c, peak_n) = match rh.peak() {
        Some(p) => p,
        None => {
            return LatticeStatus::NoLattice {
                failed_check: "dot_cluster_size",
            }
        }
    };
    // Expand around the peak while bins hold >= 1/4 of the peak count.
    let mut cluster: Vec<(f64, usize)> = Vec::new();
    for &(bc, bn) in &rh.counts {
        if (bc - peak_c).abs() <= 3.0 * rh.bin && bn * 4 >= peak_n {
            cluster.push((bc, bn));
        }
    }
    let (dot_radius, dot_sd) = weighted_mean_sd(&cluster);
    let dot_radius_tol = (1.5 * dot_sd).max(0.15 * dot_radius).max(0.75);
    let dots: Vec<&RingFeatures> = candidates
        .iter()
        .copied()
        .filter(|r| (r.radius_equiv - dot_radius).abs() <= dot_radius_tol)
        .collect();
    if dots.len() < MIN_DOT_COUNT
        || (dots.len() as f64) < MIN_DOT_FRACTION * ink.len().max(1) as f64
    {
        return LatticeStatus::NoLattice {
            failed_check: "dot_cluster_size",
        };
    }

    // Check 2: spacing from the dot-center nearest-neighbor histogram.
    let mut nn: Vec<f64> = Vec::new();
    {
        // group dot centers by glyph
        let mut by_glyph: std::collections::BTreeMap<&str, Vec<Point>> =
            std::collections::BTreeMap::new();
        for d in &dots {
            by_glyph
                .entry(d.glyph.as_str())
                .or_default()
                .push(d.center);
        }
        for (_, pts) in &by_glyph {
            for i in 0..pts.len() {
                let mut best = f64::INFINITY;
                for j in 0..pts.len() {
                    if i == j {
                        continue;
                    }
                    let d = (pts[i].x - pts[j].x).hypot(pts[i].y - pts[j].y);
                    if d < best {
                        best = d;
                    }
                }
                if best.is_finite() && best > 0.0 {
                    nn.push(best);
                }
            }
        }
    }
    if nn.len() < MIN_DOT_COUNT {
        return LatticeStatus::NoLattice {
            failed_check: "spacing_peak",
        };
    }
    let nn_mean = nn.iter().sum::<f64>() / nn.len() as f64;
    let mut nh = Hist1D::new((nn_mean * 0.05).max(0.25), 0.0);
    for &d in &nn {
        nh.add(d, 1);
    }
    // smallest-distance bin with a strong count: the grid step; later
    // peaks are its multiples (sqrt2, 2, ...), weaker on a filled grid.
    let total_nn: usize = nh.counts.iter().map(|&(_, c)| c).sum();
    let mut spacing: Option<f64> = None;
    for &(bc, bn) in &nh.counts {
        if bn as f64 >= MIN_SPACING_PEAK_SHARE * total_nn as f64 {
            spacing = Some(bc);
            break;
        }
        // also accept the dominant peak if it is the first local max
        if let Some((pc, pn)) = nh.peak() {
            if (bc - pc).abs() < 1e-9 && bn == pn {
                spacing = Some(bc);
                break;
            }
        }
    }
    let spacing = match spacing {
        Some(s) if s > 2.0 * dot_radius * 0.5 => s,
        _ => {
            return LatticeStatus::NoLattice {
                failed_check: "spacing_peak",
            }
        }
    };

    // Check 3: 2D basis from pairwise-difference angles at the spacing band.
    let mut angles: Vec<f64> = Vec::new();
    {
        let mut by_glyph: std::collections::BTreeMap<&str, Vec<Point>> =
            std::collections::BTreeMap::new();
        for d in &dots {
            by_glyph
                .entry(d.glyph.as_str())
                .or_default()
                .push(d.center);
        }
        for (_, pts) in &by_glyph {
            for i in 0..pts.len() {
                for j in i + 1..pts.len() {
                    let dx = pts[j].x - pts[i].x;
                    let dy = pts[j].y - pts[i].y;
                    let l = dx.hypot(dy);
                    if l >= BASIS_LEN_LO * spacing && l <= BASIS_LEN_HI * spacing {
                        // undirected direction, folded into [0, pi)
                        let mut a = dy.atan2(dx);
                        if a < 0.0 {
                            a += std::f64::consts::PI;
                        }
                        if a >= std::f64::consts::PI {
                            a -= std::f64::consts::PI;
                        }
                        angles.push(a);
                    }
                }
            }
        }
    }
    if angles.len() < MIN_DOT_COUNT {
        return LatticeStatus::NoLattice {
            failed_check: "basis_directions",
        };
    }
    let mut ah = Hist1D::new(std::f64::consts::PI / 72.0, 0.0); // 2.5 deg bins
    for &a in &angles {
        ah.add(a, 1);
    }
    let (a1c, a1n) = match ah.peak() {
        Some(p) => p,
        None => {
            return LatticeStatus::NoLattice {
                failed_check: "basis_directions",
            }
        }
    };
    // second direction: peak outside +/-30 deg of the first
    let mut second: Option<(f64, usize)> = None;
    for &(bc, bn) in &ah.counts {
        let mut d = (bc - a1c).abs();
        if d > std::f64::consts::FRAC_PI_2 {
            d = std::f64::consts::PI - d;
        }
        if d > std::f64::consts::PI / 6.0 {
            if second.map(|s| bn > s.1).unwrap_or(true) {
                second = Some((bc, bn));
            }
        }
    }
    let (a2c, a2n) = match second {
        Some(s) => s,
        None => {
            return LatticeStatus::NoLattice {
                failed_check: "basis_directions",
            }
        }
    };
    if (a2n as f64) < 0.25 * a1n as f64 {
        return LatticeStatus::NoLattice {
            failed_check: "basis_directions",
        };
    }
    let mut ortho = (a2c - a1c).abs();
    if ortho > std::f64::consts::FRAC_PI_2 {
        ortho = std::f64::consts::PI - ortho;
    }
    if (ortho - std::f64::consts::FRAC_PI_2).abs() > ORTHO_TOL {
        return LatticeStatus::NoLattice {
            failed_check: "basis_orthogonality",
        };
    }
    // weighted circular refinement of the two directions (mod pi each)
    let refine = |target: f64| -> f64 {
        let (mut sx, mut sy) = (0.0, 0.0);
        for &(bc, bn) in &ah.counts {
            let mut d = (bc - target).abs();
            if d > std::f64::consts::FRAC_PI_2 {
                d = std::f64::consts::PI - d;
            }
            if d <= std::f64::consts::PI / 12.0 {
                // 2*angle trick for undirected directions
                sx += (2.0 * bc).cos() * bn as f64;
                sy += (2.0 * bc).sin() * bn as f64;
            }
        }
        let mut a = sy.atan2(sx) / 2.0;
        if a < 0.0 {
            a += std::f64::consts::PI;
        }
        a
    };
    let basis_angle = refine(a1c);
    let basis_angle2 = refine(a2c);

    // Check 4: phase + coverage. Lattice coordinates (u,v) in the basis
    // frame; phase = modal residue; coverage = snapped fraction.
    let e1 = (basis_angle.cos(), basis_angle.sin());
    let e2 = (basis_angle2.cos(), basis_angle2.sin());
    let mut uh = Hist1D::new(spacing / 16.0, 0.0);
    let mut vh = Hist1D::new(spacing / 16.0, 0.0);
    let mut per_glyph: std::collections::BTreeMap<&str, (f64, f64, usize)> =
        std::collections::BTreeMap::new();
    for d in &dots {
        let u = (d.center.x * e1.0 + d.center.y * e1.1).rem_euclid(spacing);
        let v = (d.center.x * e2.0 + d.center.y * e2.1).rem_euclid(spacing);
        uh.add(u, 1);
        vh.add(v, 1);
    }
    let phase_u = match uh.peak() {
        Some((p, _)) => p,
        None => {
            return LatticeStatus::NoLattice {
                failed_check: "phase_coverage",
            }
        }
    };
    let phase_v = match vh.peak() {
        Some((p, _)) => p,
        None => {
            return LatticeStatus::NoLattice {
                failed_check: "phase_coverage",
            }
        }
    };
    let snap_tol = SNAP_TOL_FRAC * spacing;
    let mut snapped = 0usize;
    for d in &dots {
        let u = (d.center.x * e1.0 + d.center.y * e1.1).rem_euclid(spacing);
        let v = (d.center.x * e2.0 + d.center.y * e2.1).rem_euclid(spacing);
        let du = (u - phase_u).abs().min(spacing - (u - phase_u).abs());
        let dv = (v - phase_v).abs().min(spacing - (v - phase_v).abs());
        let ok = du <= snap_tol && dv <= snap_tol;
        if ok {
            snapped += 1;
        }
        let e = per_glyph.entry(d.glyph.as_str()).or_default();
        e.2 += 1;
        if ok {
            e.0 += 1.0;
        }
        e.1 += 0.0;
    }
    let coverage = snapped as f64 / dots.len().max(1) as f64;
    // per-glyph agreement: fraction of glyphs whose own coverage >= MIN_COVERAGE
    let mut agree = 0usize;
    let mut g_with_dots = 0usize;
    for (_, (s, _, n)) in &per_glyph {
        if *n >= 4 {
            g_with_dots += 1;
            if *s / *n as f64 >= MIN_COVERAGE {
                agree += 1;
            }
        }
    }
    let per_glyph_phase_agreement = if g_with_dots > 0 {
        agree as f64 / g_with_dots as f64
    } else {
        0.0
    };
    if coverage < MIN_COVERAGE {
        return LatticeStatus::NoLattice {
            failed_check: "phase_coverage",
        };
    }
    LatticeStatus::Detected(LatticeParams {
        dot_radius,
        dot_radius_tol,
        spacing,
        basis_angle,
        basis_angle2,
        phase: (phase_u, phase_v),
        coverage,
        per_glyph_phase_agreement,
        dot_count: dots.len(),
        glyph_count,
        candidate_count: candidates.len(),
    })
}

// ---------- stage 2: classification ----------

/// Classify one contour against a detected lattice. Ambiguous evidence is
/// typed Ambiguous and stays in the stroke path - no silent reclass.
pub fn classify_contour(f: &RingFeatures, p: &LatticeParams) -> ContourClass {
    if f.hole {
        return ContourClass::Stroke;
    }
    let size_dev = (f.radius_equiv - p.dot_radius).abs();
    let size_ok = size_dev <= p.dot_radius_tol;
    let size_far = size_dev > 2.0 * p.dot_radius_tol;
    let circ_ok = f.circularity >= CAND_MIN_CIRCULARITY;
    let circ_bad = f.circularity < 0.5;
    let e1 = (p.basis_angle.cos(), p.basis_angle.sin());
    let e2 = (p.basis_angle2.cos(), p.basis_angle2.sin());
    let u = (f.center.x * e1.0 + f.center.y * e1.1).rem_euclid(p.spacing);
    let v = (f.center.x * e2.0 + f.center.y * e2.1).rem_euclid(p.spacing);
    let du = (u - p.phase.0).abs().min(p.spacing - (u - p.phase.0).abs());
    let dv = (v - p.phase.1).abs().min(p.spacing - (v - p.phase.1).abs());
    let snap_tol = SNAP_TOL_FRAC * p.spacing;
    let lattice_ok = du <= snap_tol && dv <= snap_tol;
    let lattice_far = du > 2.0 * snap_tol || dv > 2.0 * snap_tol;

    if size_ok && circ_ok && lattice_ok {
        ContourClass::LatticeDot
    } else if size_far || circ_bad || lattice_far && !size_ok {
        ContourClass::Stroke
    } else {
        ContourClass::Ambiguous
    }
}
