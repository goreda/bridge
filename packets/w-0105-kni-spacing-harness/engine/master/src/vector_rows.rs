//! Vector-path acceptance rows A1 (guide fidelity), A2 (G1 join angle) and
//! A3 (curvature variation, single outline). Measurement only: nothing here
//! changes an outline, and no row has a built-in pass threshold other than
//! the ones the drawing standard defines in terms of the source itself.
//!
//! Frame: font units, y up, master and source in the same frame. Every row
//! carries the path label `vector`. A row that cannot be measured is
//! reported as "n/a (reason)", never as zero or as a pass.
//!
//! Numbers: tolerances derive from the drawing (`Params::grid`, `margin`) or
//! from the source outline. Every other number is a caller-supplied
//! parameter (see `GuideParams`, `A2Params`) or a named CONVENTION constant
//! below. There is no default for a parameter: the caller states it.

use crate::model::{joint_turn, MasterGlyph, SegKind};
use crate::validate::Params;
use crate::vector::PathLabel;

/// CONVENTION (drawing standard, section 7): scale factor that turns a
/// median absolute deviation into a spread estimate.
pub const MAD_TO_SIGMA: f64 = 1.4826;
/// CONVENTION: quantiles named by the drawing standard (p90 in A1, p95 in
/// A2), computed by the nearest-rank rule.
pub const Q90: f64 = 0.90;
pub const Q95: f64 = 0.95;
/// Resource guard (not a measurement): curve samples per segment.
pub const MAX_CURVE_SAMPLES: usize = 1 << 16;

fn median(v: &mut Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.total_cmp(b));
    let n = v.len();
    if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 }
}

fn nearest_rank(sorted: &[f64], q: f64) -> f64 {
    let n = sorted.len();
    let k = ((q * n as f64).ceil() as usize).max(1) - 1;
    sorted[k.min(n - 1)]
}

fn fmt_opt(v: Option<f64>) -> String {
    v.map_or("n/a".to_string(), |x| format!("{x:.6}"))
}

// ---------------------------------------------------------------- A1 ----

/// A policy value the caller declares instead of measuring. It is reported
/// in its own "declared, not measured" column with how it was derived.
#[derive(Debug, Clone, PartialEq)]
pub struct Declared {
    pub value: f64,
    pub derivation: String,
}

/// A1 parameters. No defaults.
#[derive(Debug, Clone)]
pub struct GuideParams {
    /// CONVENTION: two flat source edges belong to one class when their y
    /// values are linked by steps no larger than this (single linkage).
    pub link: f64,
    /// CONVENTION: a class needs at least this many flat source edges.
    pub min_edges: usize,
    /// Declared spread limit. `None` means unavailable: the abstain test is
    /// then not evaluated (status `NotEvaluated`), never assumed.
    pub declared_spread_limit: Option<Declared>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassStatus {
    /// No declared limit: the abstain rule could not be evaluated.
    NotEvaluated,
    Active,
    /// Measured class spread exceeds the declared limit: nodes abstain.
    Abstained,
}

#[derive(Debug, Clone)]
pub struct GuideClass {
    /// Median y of the class's flat source edges (the source guide).
    pub value: f64,
    pub n_edges: usize,
    /// MAD_TO_SIGMA x MAD of the class's edge y values (measured).
    pub measured_spread: f64,
    /// Half-width within which a master node falls into the class: the
    /// largest edge deviation, at least `Params::grid`.
    pub window: f64,
    pub status: ClassStatus,
    /// Master nodes assigned to the class.
    pub nodes: usize,
    pub abstained_nodes: usize,
    /// Signed offsets node.y - value; None when no active node.
    pub median_offset: Option<f64>,
    /// Nearest-rank p90 and maximum of the absolute offsets.
    pub p90_abs_offset: Option<f64>,
    pub max_abs_offset: Option<f64>,
}

#[derive(Debug, Clone)]
pub struct GuideReport {
    pub label: PathLabel,
    pub classes: Vec<GuideClass>,
    /// Master nodes that fell into no class.
    pub unassigned_nodes: usize,
    pub declared_limit: Option<Declared>,
}

/// A1 guide fidelity. Classes come only from flat horizontal edges of the
/// source (line segments with |dy| <= grid and length > margin). Classes are
/// anonymous and ordered by y: this reader does not decide which one is a
/// baseline, x-height or overshoot. Nothing is snapped.
pub fn guide_fidelity(master: &MasterGlyph, source: &MasterGlyph, params: Params, gp: &GuideParams) -> GuideReport {
    let mut ys: Vec<f64> = Vec::new();
    for c in &source.contours {
        for s in c.segments() {
            if s.kind == SegKind::Line
                && (s.p1.1 - s.p0.1).abs() <= params.grid
                && (s.p1.0 - s.p0.0).abs() > params.margin
            {
                ys.push((s.p0.1 + s.p1.1) / 2.0);
            }
        }
    }
    ys.sort_by(|a, b| a.total_cmp(b));
    let mut groups: Vec<Vec<f64>> = Vec::new();
    for y in ys {
        let join = groups.last().map_or(false, |g| y - *g.last().unwrap() <= gp.link);
        if join {
            groups.last_mut().unwrap().push(y);
        } else {
            groups.push(vec![y]);
        }
    }
    let mut classes: Vec<GuideClass> = Vec::new();
    for g in groups.into_iter().filter(|g| g.len() >= gp.min_edges.max(1)) {
        let mut tmp = g.clone();
        let value = median(&mut tmp);
        let mut dev: Vec<f64> = g.iter().map(|y| (y - value).abs()).collect();
        let max_dev = dev.iter().cloned().fold(0.0, f64::max);
        let measured_spread = MAD_TO_SIGMA * median(&mut dev);
        classes.push(GuideClass {
            value,
            n_edges: g.len(),
            measured_spread,
            window: max_dev.max(params.grid),
            status: match &gp.declared_spread_limit {
                None => ClassStatus::NotEvaluated,
                Some(d) if measured_spread > d.value => ClassStatus::Abstained,
                Some(_) => ClassStatus::Active,
            },
            nodes: 0,
            abstained_nodes: 0,
            median_offset: None,
            p90_abs_offset: None,
            max_abs_offset: None,
        });
    }
    let mut offsets: Vec<Vec<f64>> = vec![Vec::new(); classes.len()];
    let mut unassigned = 0usize;
    for c in &master.contours {
        for n in c.nodes() {
            let mut best: Option<(usize, f64)> = None;
            for (i, k) in classes.iter().enumerate() {
                let d = (n.1 - k.value).abs();
                if d <= k.window && best.map_or(true, |(_, bd)| d < bd) {
                    best = Some((i, d));
                }
            }
            match best {
                None => unassigned += 1,
                Some((i, _)) => {
                    classes[i].nodes += 1;
                    if classes[i].status == ClassStatus::Abstained {
                        classes[i].abstained_nodes += 1;
                    } else {
                        offsets[i].push(n.1 - classes[i].value);
                    }
                }
            }
        }
    }
    for (k, off) in classes.iter_mut().zip(offsets.iter_mut()) {
        if off.is_empty() {
            continue;
        }
        let mut abs: Vec<f64> = off.iter().map(|v| v.abs()).collect();
        abs.sort_by(|a, b| a.total_cmp(b));
        k.median_offset = Some(median(off));
        k.p90_abs_offset = Some(nearest_rank(&abs, Q90));
        k.max_abs_offset = abs.last().copied();
    }
    GuideReport { label: PathLabel::Vector, classes, unassigned_nodes: unassigned, declared_limit: gp.declared_spread_limit.clone() }
}

impl GuideReport {
    /// Tab-separated rows: `label row class measured | declared | result`.
    pub fn rows(&self) -> Vec<String> {
        let l = self.label.as_str();
        if self.classes.is_empty() {
            return vec![format!("{l}\tA1\tn/a (no flat edges in the source)")];
        }
        let declared = match &self.declared_limit {
            Some(d) => format!("declared, not measured: {:.6} ({})", d.value, d.derivation),
            None => "declared, not measured: unavailable".to_string(),
        };
        self.classes
            .iter()
            .map(|k| {
                let st = match k.status {
                    ClassStatus::NotEvaluated => "abstain rule not evaluated (no declared limit)",
                    ClassStatus::Active => "active",
                    ClassStatus::Abstained => "abstained",
                };
                format!(
                    "{l}\tA1\tclass y={:.6}\tmeasured: edges={} spread={:.6}\t{declared}\t{st}\tnodes={} abstained={} median={} p90_abs={} max_abs={}",
                    k.value,
                    k.n_edges,
                    k.measured_spread,
                    k.nodes,
                    k.abstained_nodes,
                    fmt_opt(k.median_offset),
                    fmt_opt(k.p90_abs_offset),
                    fmt_opt(k.max_abs_offset),
                )
            })
            .collect()
    }
}

// ---------------------------------------------------------------- A2 ----

/// A2 parameters. No defaults.
#[derive(Debug, Clone, Copy)]
pub struct A2Params {
    /// CONVENTION (degrees): a joint with at least one curve segment is a
    /// smooth node when its turn angle is at most this.
    pub smooth_class_tol_deg: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AngleStats {
    pub nodes: usize,
    pub p95: f64,
    pub max: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum JoinVerdict {
    /// Master p95 is at most the source's own p95 (tolerance).
    Within,
    Exceeds,
    NotAvailable(&'static str),
}

#[derive(Debug, Clone)]
pub struct JoinReport {
    pub label: PathLabel,
    pub master: Option<AngleStats>,
    /// Source angle noise: the tolerance of the row.
    pub source: Option<AngleStats>,
    pub verdict: JoinVerdict,
}

fn smooth_turns(g: &MasterGlyph, tol: f64) -> Vec<f64> {
    let mut out = Vec::new();
    for c in &g.contours {
        let segs = c.segments();
        let m = segs.len();
        for i in 0..m {
            let j = (i + 1) % m;
            if segs[i].kind == SegKind::Line && segs[j].kind == SegKind::Line {
                continue;
            }
            let t = joint_turn(&segs[i], &segs[j]);
            if t <= tol {
                out.push(t);
            }
        }
    }
    out
}

fn stats(mut v: Vec<f64>) -> Option<AngleStats> {
    if v.is_empty() {
        return None;
    }
    v.sort_by(|a, b| a.total_cmp(b));
    Some(AngleStats { nodes: v.len(), p95: nearest_rank(&v, Q95), max: *v.last().unwrap() })
}

/// A2 G1 join angle: turn angle (degrees) at each smooth node.
pub fn join_angle(master: &MasterGlyph, source: &MasterGlyph, p: A2Params) -> JoinReport {
    let m = stats(smooth_turns(master, p.smooth_class_tol_deg));
    let s = stats(smooth_turns(source, p.smooth_class_tol_deg));
    let verdict = match (&m, &s) {
        (_, None) => JoinVerdict::NotAvailable("source has no smooth curve nodes"),
        (None, _) => JoinVerdict::NotAvailable("master has no smooth curve nodes"),
        (Some(a), Some(b)) if a.p95 <= b.p95 => JoinVerdict::Within,
        _ => JoinVerdict::Exceeds,
    };
    JoinReport { label: PathLabel::Vector, master: m, source: s, verdict }
}

impl JoinReport {
    pub fn rows(&self) -> Vec<String> {
        let l = self.label.as_str();
        let f = |s: &Option<AngleStats>| match s {
            Some(a) => format!("nodes={} p95={:.6} max={:.6}", a.nodes, a.p95, a.max),
            None => "n/a".to_string(),
        };
        let v = match &self.verdict {
            JoinVerdict::Within => "p95 within source angle noise".to_string(),
            JoinVerdict::Exceeds => "p95 exceeds source angle noise".to_string(),
            JoinVerdict::NotAvailable(r) => format!("n/a ({r})"),
        };
        vec![format!("{l}\tA2\tdegrees\tmaster: {}\ttolerance (source, measured): {}\t{v}", f(&self.master), f(&self.source))]
    }
}

// ---------------------------------------------------------------- A3 ----

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum A3Error {
    /// A source was given but the master is not segment-for-segment the same
    /// outline. Matching master spans to source spans is not defined; there
    /// is no fallback.
    MappingUndefined,
    /// More samples than the resource guard allows for one segment.
    Budget { contour: usize, seg: usize },
}

impl std::fmt::Display for A3Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            A3Error::MappingUndefined => write!(f, "mapping_undefined: master spans cannot be matched to source spans"),
            A3Error::Budget { contour, seg } => write!(f, "curve sample budget exceeded at contour {contour} segment {seg}"),
        }
    }
}

impl std::error::Error for A3Error {}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CurvatureValues {
    /// Maximum of |d kappa / d s| over the samples, 1/unit^2.
    pub max_dk_ds: f64,
    /// Arc-length-weighted RMS of d kappa / d s, 1/unit^2.
    pub rms_dk_ds: f64,
    /// Sign changes of kappa along the segment.
    pub sign_changes: usize,
    /// Interior extrema of kappa (sign changes of d kappa / d t).
    pub extrema: usize,
}

#[derive(Debug, Clone)]
pub struct CurvatureRow {
    pub contour: usize,
    pub seg: usize,
    /// None: the tangent vanishes at a sample (n/a, zero tangent).
    pub values: Option<CurvatureValues>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mapping {
    /// No source given: the master is measured alone.
    MasterOnly,
    /// Master is identical to the source outline: spans map one to one.
    Identity,
}

/// The "curvature extrema added relative to the source" row. It carries no
/// number: under an identity mapping the count is 0 by construction, so a
/// measured-looking `0` would say nothing; without a source it is undefined.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddedExtrema {
    /// Identity mapping: trivially 0, reported as n/a.
    IdentityTrivial,
    /// No source given.
    NoSourceMapping,
}

#[derive(Debug, Clone)]
pub struct CurvatureReport {
    pub label: PathLabel,
    pub mapping: Mapping,
    pub rows: Vec<CurvatureRow>,
    pub added_extrema: AddedExtrema,
}

fn same_outline(a: &MasterGlyph, b: &MasterGlyph) -> bool {
    a.contours.len() == b.contours.len()
        && a.contours.iter().zip(b.contours.iter()).all(|(x, y)| x.ops == y.ops)
}

fn sign_changes(v: &[f64]) -> usize {
    let mut last = 0.0f64;
    let mut n = 0;
    for &x in v {
        if x == 0.0 {
            continue;
        }
        if last != 0.0 && (x < 0.0) != (last < 0.0) {
            n += 1;
        }
        last = x;
    }
    n
}

/// Derivatives of a cubic at `t`: r', r'', r'''.
fn cubic_derivs(p: [(f64, f64); 4], t: f64) -> ((f64, f64), (f64, f64), (f64, f64)) {
    let u = 1.0 - t;
    let d1 = |k: usize| (p[k + 1].0 - p[k].0, p[k + 1].1 - p[k].1);
    let (a, b, c) = (d1(0), d1(1), d1(2));
    let r1 = (3.0 * (u * u * a.0 + 2.0 * u * t * b.0 + t * t * c.0), 3.0 * (u * u * a.1 + 2.0 * u * t * b.1 + t * t * c.1));
    let s0 = (b.0 - a.0, b.1 - a.1);
    let s1 = (c.0 - b.0, c.1 - b.1);
    let r2 = (6.0 * (u * s0.0 + t * s1.0), 6.0 * (u * s0.1 + t * s1.1));
    let r3 = (6.0 * (s1.0 - s0.0), 6.0 * (s1.1 - s0.1));
    (r1, r2, r3)
}

/// (kappa, d kappa / d t, speed) at `t`; None when the speed is zero.
fn kappa_at(p: [(f64, f64); 4], t: f64) -> Option<(f64, f64, f64)> {
    let (r1, r2, r3) = cubic_derivs(p, t);
    let sp = r1.0.hypot(r1.1);
    if sp == 0.0 {
        return None;
    }
    let n = r1.0 * r2.1 - r1.1 * r2.0;
    let dn = r1.0 * r3.1 - r1.1 * r3.0;
    let d = sp * sp * sp;
    let dd = 3.0 * sp * (r1.0 * r2.0 + r1.1 * r2.1);
    Some((n / d, (dn * d - n * dd) / (d * d), sp))
}

/// A3 curvature variation, one outline at a time. Curves are sampled with a
/// chord spacing no larger than `Params::grid` (control-polygon length divided
/// by the grid, rounded up), so maxima and extrema closer together than that
/// spacing can be missed: the values are sampled, not exact.
///
/// With `source = Some(_)` the master must be the same outline as the source
/// (identity mapping); anything else is `A3Error::MappingUndefined`.
pub fn curvature_variation(master: &MasterGlyph, source: Option<&MasterGlyph>, params: Params) -> Result<CurvatureReport, A3Error> {
    let mapping = match source {
        None => Mapping::MasterOnly,
        Some(s) if same_outline(master, s) => Mapping::Identity,
        Some(_) => return Err(A3Error::MappingUndefined),
    };
    let mut rows = Vec::new();
    for (ci, c) in master.contours.iter().enumerate() {
        for (si, s) in c.segments().iter().enumerate() {
            let (Some(c1), Some(c2)) = (s.c1, s.c2) else { continue };
            if s.kind != SegKind::Curve {
                continue;
            }
            let p = [s.p0, c1, c2, s.p1];
            let poly: f64 = (0..3).map(|k| (p[k + 1].0 - p[k].0).hypot(p[k + 1].1 - p[k].1)).sum();
            let n = ((poly / params.grid).ceil() as usize).max(2);
            if n > MAX_CURVE_SAMPLES {
                return Err(A3Error::Budget { contour: ci, seg: si });
            }
            let mut kap = Vec::with_capacity(n + 1);
            let mut dk = Vec::with_capacity(n + 1);
            let mut max_dk = 0.0f64;
            let mut ok = true;
            for k in 0..=n {
                match kappa_at(p, k as f64 / n as f64) {
                    Some((kp, dkt, sp)) => {
                        kap.push(kp);
                        dk.push(dkt);
                        max_dk = max_dk.max((dkt / sp).abs());
                    }
                    None => {
                        ok = false;
                        break;
                    }
                }
            }
            let mut num = 0.0;
            let mut len = 0.0;
            if ok {
                for k in 0..n {
                    match kappa_at(p, (k as f64 + 0.5) / n as f64) {
                        Some((_, dkt, sp)) => {
                            let f = dkt / sp;
                            num += f * f * sp;
                            len += sp;
                            max_dk = max_dk.max(f.abs());
                        }
                        None => {
                            ok = false;
                            break;
                        }
                    }
                }
            }
            let values = if ok {
                Some(CurvatureValues { max_dk_ds: max_dk, rms_dk_ds: (num / len).sqrt(), sign_changes: sign_changes(&kap), extrema: sign_changes(&dk) })
            } else {
                None
            };
            rows.push(CurvatureRow { contour: ci, seg: si, values });
        }
    }
    let added = if mapping == Mapping::Identity { AddedExtrema::IdentityTrivial } else { AddedExtrema::NoSourceMapping };
    Ok(CurvatureReport { label: PathLabel::Vector, mapping, rows, added_extrema: added })
}

impl CurvatureReport {
    pub fn rows_text(&self) -> Vec<String> {
        let l = self.label.as_str();
        let mut out: Vec<String> = self
            .rows
            .iter()
            .map(|r| match &r.values {
                Some(v) => format!(
                    "{l}\tA3\tcontour {} segment {}\tmax_dk_ds={:.6} rms_dk_ds={:.6} (1/unit^2)\tkappa_sign_changes={} kappa_extrema={}",
                    r.contour, r.seg, v.max_dk_ds, v.rms_dk_ds, v.sign_changes, v.extrema
                ),
                None => format!("{l}\tA3\tcontour {} segment {}\tn/a (zero tangent)", r.contour, r.seg),
            })
            .collect();
        out.push(match self.added_extrema {
            AddedExtrema::IdentityTrivial => format!("{l}\tA3\tadded extrema vs source\tn/a (identity mapping, trivially 0)"),
            AddedExtrema::NoSourceMapping => format!("{l}\tA3\tadded extrema vs source\tn/a (no source mapping)"),
        });
        out
    }
}
