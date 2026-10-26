//! gen: additive kern generation from learned knowledge.
//!
//! Task: add kern pairs to a font without overwriting the existing ones,
//! learning from them. The number of added pairs is an output.
//!
//! Design rule: no per-font
//! profile, config, or pluggable layer. One core + cumulative learned
//! knowledge. The knowledge artifacts consumed here (class assignments,
//! cell targets, stratum targets) are that persistent representation:
//! font-name-free learned structures the engine writes after studying a
//! font and re-applies by itself on the next one. The fit/clustering that
//! PRODUCES the artifacts is the learn phase; this module is the apply
//! phase, fully deterministic given the artifacts.
//!
//! Conventions (all derived from the font's own existing kern data; see
//! `KernPolicy`, no universal constants):
//! - value source priority: populated class cell median (support >= the
//!   font-derived minimum) else geometric min-gap solve toward stratum target;
//! - |kern| below the font's own cell leave-one-out median error is noise
//!   and is not written;
//! - values clamp to the font's observed existing kern range;
//! - the number of written pairs is an OUTPUT, not a target; candidates are
//!   visited in glyph-name order (deterministic, order has no effect on the
//!   set because nothing caps it);
//! - existing pairs are never regenerated: the additive guarantee is
//!   enforced through learn::AdditiveKernSet. An explicit source zero is an
//!   existing pair too: it is protected from regeneration exactly like a
//!   nonzero value. Zeros are left out of the statistics only (see
//!   `derive_policy_trim`), never out of the protected set;
//! - input is validated, not assumed: duplicates, non-finite numbers,
//!   saturated values and restore/existing conflicts are typed errors.
//!
//! Labels: CONVENTION marks a choice that is not measured from the font.
//! The leave-one-out error used for the noise floor is an internal
//! consistency measure over the same pairs that form the cell medians. It is
//! NOT an independent holdout and is not evidence of out-of-sample accuracy.

use crate::learn::{AdditiveKernSet, ExistingPair, PairInventory};
use kni_learning::Priors;
use std::collections::{BTreeMap, HashMap, HashSet};

/// Per-glyph learned knowledge row.
#[derive(Debug, Clone)]
pub struct GlyphKnowledge {
    /// 'U' uppercase, 'L' lowercase, 'd' digit, 'x' other.
    pub case: char,
    /// Legacy artifact column, parsed for format compatibility only. Not used
    /// by generation (external frequency prior removed: no hardcoded priors).
    pub freq_weight: i32,
    /// Class of this glyph's RIGHT wall (used when glyph is pair-left).
    pub right_class: u32,
    /// Class of this glyph's LEFT wall (used when glyph is pair-right).
    pub left_class: u32,
}

/// Learned class-pair and stratum targets.
#[derive(Debug, Clone)]
pub struct ClassTargets {
    /// (right_class of left glyph, left_class of right glyph, caseL, caseR)
    /// -> median observed kern of populated cells (>= 2 observations).
    pub cell_median: HashMap<(u32, u32, char, char), f64>,
    /// (caseL, caseR) -> median kerned-state min-gap of observed pairs.
    pub stratum_mingap: HashMap<(char, char), f64>,
    /// Global median kerned-state min-gap over all observed pairs.
    pub global_mingap: f64,
}

/// Glyph wall data: advance width and per-row (left_x, right_x).
#[derive(Debug, Clone)]
pub struct GlyphWall {
    pub advance: f64,
    /// y -> (left_x, right_x), ascending y.
    pub rows: BTreeMap<i32, (f64, f64)>,
}

/// One generated pair with provenance label.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedPair {
    pub left: String,
    pub right: String,
    pub kern: i32,
    /// "T0" restored-from-repo-table or "G-<cell|prior|geom>".
    pub tier: String,
}

/// Everything the apply phase needs.
#[derive(Debug, Clone)]
pub struct GenerationInputs {
    /// Universe glyphs. Any order is accepted (generation sorts a copy);
    /// duplicates are rejected by `validate_inputs`.
    pub glyphs: Vec<String>,
    pub knowledge: HashMap<String, GlyphKnowledge>,
    pub targets: ClassTargets,
    pub walls: HashMap<String, GlyphWall>,
    /// Existing effective kern (the protected set). Explicit zeros belong
    /// here: they are protected from regeneration. Build it from a pair list
    /// with `existing_from_pairs` to reject duplicate keys.
    pub existing: HashMap<(String, String), i32>,
    /// Repo-sanctioned pairs missing from the font, restored verbatim
    /// first, in file order.
    pub restore: Vec<ExistingPair>,
}

/// Policy derived from the font's own existing kern data. Every field has a
/// derivation string so the receipt can show where each number came from.
#[derive(Debug, Clone)]
pub struct KernPolicy {
    /// |kern| below this is noise: median leave-one-out error of class-cell
    /// medians over the font's existing pairs (min 1: a 0 pair is no pair).
    pub noise_floor: i32,
    pub clamp_lo: i32,
    pub clamp_hi: i32,
    /// Minimum existing-pair support for a cell median to be trusted.
    pub min_cell_support: usize,
    /// Existing-pair count per cell (empty = permissive, trust artifact).
    pub cell_support: HashMap<(u32, u32, char, char), usize>,
    /// (field, derivation text) in fixed order, for the receipt.
    pub derivation: Vec<(String, String)>,
    /// Geometric-solve gate per (caseL, caseR) stratum, derived from the font's
    /// own existing pairs: open only when the solve's mean error on those pairs
    /// is strictly below the error of writing no kern (kern = 0). `None` =
    /// ungated (legacy permissive path). A stratum absent from the map is closed.
    pub geom_open: Option<BTreeMap<(char, char), bool>>,
}

impl KernPolicy {
    /// No derived limits: used only by the legacy single-pair `predict`.
    /// This is the no-clamp model: no range clamp, no noise floor, and an
    /// empty `cell_support`, which makes every cell median count as supported.
    /// It is a policy of "trust the artifact", NOT evidence that any cell has
    /// support in the font. The derived policy is a separate (clamped) model.
    pub fn permissive() -> Self {
        Self {
            noise_floor: 0,
            clamp_lo: i32::MIN,
            clamp_hi: i32::MAX,
            min_cell_support: 0,
            cell_support: HashMap::new(),
            derivation: Vec::new(),
            geom_open: None,
        }
    }
}

fn median_f64(v: &mut Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.total_cmp(b));
    let n = v.len();
    if n == 0 {
        return 0.0;
    }
    if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2.0
    }
}

/// Derive the policy from the protected (existing) set and class knowledge.
/// Deterministic: cells are visited in sorted key order.
pub fn derive_policy(inp: &GenerationInputs) -> Result<KernPolicy, GenError> {
    derive_policy_trim(inp, 0)
}

/// `derive_policy` with the `trim` most extreme existing values dropped from
/// each end of the clamp range (outlier sensitivity probe; trim 0 = real policy).
pub fn derive_policy_trim(inp: &GenerationInputs, trim: usize) -> Result<KernPolicy, GenError> {
    validate_inputs(inp)?;
    let mut cells: BTreeMap<(u32, u32, char, char), Vec<f64>> = BTreeMap::new();
    let mut ex_lo = i32::MAX;
    let mut ex_hi = i32::MIN;
    let mut all_vals: Vec<i32> = Vec::new();
    let mut ex: Vec<(&(String, String), &i32)> = inp.existing.iter().collect();
    ex.sort();
    for ((l, r), v) in ex {
        // CONVENTION: explicit zeros are excluded from the statistics (cell
        // medians, LOO error, clamp range) so a zero does not pull the medians
        // toward 0. They stay in the protected set (see `run`).
        if *v == 0 {
            continue;
        }
        ex_lo = ex_lo.min(*v);
        ex_hi = ex_hi.max(*v);
        all_vals.push(*v);
        if let (Some(kl), Some(kr)) = (inp.knowledge.get(l), inp.knowledge.get(r)) {
            cells
                .entry((kl.right_class, kr.left_class, kl.case, kr.case))
                .or_default()
                .push(*v as f64);
        }
    }
    // No silent empty output.
    if all_vals.is_empty() {
        return Err(GenError::NoExistingKern);
    }
    if cells.values().all(|v| v.len() < MIN_LOO_OBSERVATIONS) {
        return Err(GenError::NoCellWithTwoObservations);
    }
    if trim > 0 && all_vals.len() > 2 * trim {
        all_vals.sort();
        ex_lo = all_vals[trim];
        ex_hi = all_vals[all_vals.len() - 1 - trim];
    }
    // Support threshold. CONVENTION: the median occupancy of occupied cells
    // is the support requirement (a choice, not a measured optimum). The
    // floor 2 is structural: a leave-one-out median needs two observations.
    let mut occ: Vec<f64> = cells.values().map(|v| v.len() as f64).collect();
    let min_support = (median_f64(&mut occ).round_ties_even() as usize).max(MIN_LOO_OBSERVATIONS);
    // Noise floor: leave-one-out median error across all cells with >= 2 obs.
    let mut errs: Vec<f64> = Vec::new();
    for vals in cells.values() {
        if vals.len() < MIN_LOO_OBSERVATIONS {
            continue;
        }
        for i in 0..vals.len() {
            let mut rest: Vec<f64> = vals
                .iter()
                .enumerate()
                .filter(|(j, _)| *j != i)
                .map(|(_, x)| *x)
                .collect();
            errs.push((vals[i] - median_f64(&mut rest)).abs());
        }
    }
    // CONVENTION: the floor of 1 (a generated 0 is not a pair). The median
    // itself is an internal-consistency LOO error, not a holdout error.
    let noise = round_to_i32(median_f64(&mut errs), "noise floor")?.max(1);
    // The range always contains 0, so a clamp can never flip a sign.
    let (clamp_lo, clamp_hi) = (ex_lo.min(0), ex_hi.max(0));
    let support: HashMap<_, _> = cells.iter().map(|(k, v)| (*k, v.len())).collect();
    // Geometric-solve gate. The solve (stratum target minus kern-0 min-gap) is
    // scored on every existing pair with geometry, explicit zeros included (a
    // zero is evidence that no kern was right), against writing kern = 0. A
    // stratum opens only when the solve is strictly better on those pairs.
    let mut gate_err: BTreeMap<(char, char), (f64, f64, usize)> = BTreeMap::new();
    {
        let mut exs: Vec<(&(String, String), &i32)> = inp.existing.iter().collect();
        exs.sort();
        for ((l, r), v) in exs {
            let (Some(kl), Some(kr)) = (inp.knowledge.get(l), inp.knowledge.get(r)) else { continue };
            let (Some(wl), Some(wr)) = (inp.walls.get(l), inp.walls.get(r)) else { continue };
            let Some(g0) = min_gap0(wl, wr) else { continue };
            let target = inp
                .targets
                .stratum_mingap
                .get(&(kl.case, kr.case))
                .copied()
                .unwrap_or(inp.targets.global_mingap);
            let e = gate_err.entry((kl.case, kr.case)).or_insert((0.0, 0.0, 0));
            e.0 += ((target - g0).round_ties_even() - f64::from(*v)).abs();
            e.1 += f64::from(*v).abs();
            e.2 += 1;
        }
    }
    let geom_open: BTreeMap<(char, char), bool> =
        gate_err.iter().map(|(k, (g, z, _))| (*k, g < z)).collect();
    let geom_text = gate_err
        .iter()
        .map(|((a, b), (g, z, n))| format!("{a}{b}:n={n},geom_abs={g},zero_abs={z},open={}", g < z))
        .collect::<Vec<_>>()
        .join(";");
    let mut derivation = vec![
        (
            "noise_floor".to_string(),
            format!(
                "median LOO error of cell medians over {} errors (internal consistency, not an independent holdout), CONVENTION floor 1 = {noise}",
                errs.len()
            ),
        ),
        (
            "clamp".to_string(),
            format!("observed existing kern range extended to contain 0: [{clamp_lo},{clamp_hi}]"),
        ),
        (
            "min_cell_support".to_string(),
            format!(
                "CONVENTION: median occupancy of {} occupied cells, structural floor 2 = {min_support}",
                cells.len()
            ),
        ),
    ];
    derivation.push((
        "geom_gate".to_string(),
        format!("geometric solve opens per stratum only if summed |solve - kern| < summed |kern| over existing pairs (in-sample, zeros included); {geom_text}"),
    ));
    Ok(KernPolicy {
        noise_floor: noise,
        clamp_lo,
        clamp_hi,
        min_cell_support: min_support,
        cell_support: support,
        derivation,
        geom_open: Some(geom_open),
    })
}

/// CONVENTION (structural floor): a leave-one-out median needs two
/// observations in a cell, so a cell with fewer than this many values takes no
/// part in the noise floor. It is also the lower bound of the minimum cell
/// support. The occupancy median that sets the support still counts every
/// occupied cell, singletons included.
const MIN_LOO_OBSERVATIONS: usize = 2;

/// Typed refusal: generation does not silently return nothing or guess.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GenError {
    /// No nonzero existing kern: nothing to derive thresholds from.
    NoExistingKern,
    /// Existing kern present but no class cell has two observations.
    NoCellWithTwoObservations,
    /// A glyph name appears more than once in `glyphs`.
    DuplicateGlyph(String),
    /// The same (left, right) key appears more than once in an existing list.
    DuplicateExistingPair { left: String, right: String },
    /// The same (left, right) key appears more than once in `restore`.
    DuplicateRestorePair { left: String, right: String },
    /// A restore pair is also in the existing (protected) set.
    RestoreExistingConflict { left: String, right: String },
    /// A number is NaN or infinite; the field is named.
    NonFinite(String),
    /// A value is at or beyond the i32 limits (i32::MIN and i32::MAX are
    /// rejected as sentinels; i32::MIN also has no positive absolute value).
    Saturated(String),
}

impl GenError {
    pub fn reason(&self) -> &'static str {
        match self {
            GenError::NoExistingKern => "no nonzero existing kern pairs: policy cannot be derived from this font",
            GenError::NoCellWithTwoObservations => "no class cell has two existing observations: noise floor cannot be derived",
            GenError::DuplicateGlyph(_) => "duplicate glyph name in the glyph list",
            GenError::DuplicateExistingPair { .. } => "duplicate pair in the existing list",
            GenError::DuplicateRestorePair { .. } => "duplicate pair in the restore list",
            GenError::RestoreExistingConflict { .. } => "a restore pair is also an existing pair",
            GenError::NonFinite(_) => "a number is not finite",
            GenError::Saturated(_) => "a value is saturated or outside the i32 range",
        }
    }
}

impl std::fmt::Display for GenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GenError::DuplicateGlyph(g) => write!(f, "{}: {g}", self.reason()),
            GenError::DuplicateExistingPair { left, right }
            | GenError::DuplicateRestorePair { left, right }
            | GenError::RestoreExistingConflict { left, right } => {
                write!(f, "{}: {left} {right}", self.reason())
            }
            GenError::NonFinite(w) | GenError::Saturated(w) => write!(f, "{}: {w}", self.reason()),
            _ => write!(f, "{}", self.reason()),
        }
    }
}

impl std::error::Error for GenError {}

fn saturated(v: i32) -> bool {
    v == i32::MIN || v == i32::MAX
}

/// Round ties-to-even into i32, refusing NaN, infinity and any value outside
/// the symmetric range (-i32::MAX..=i32::MAX). Never saturates silently.
fn round_to_i32(x: f64, what: &str) -> Result<i32, GenError> {
    if !x.is_finite() {
        return Err(GenError::NonFinite(what.to_string()));
    }
    let r = x.round_ties_even();
    if r < -(i32::MAX as f64) || r > i32::MAX as f64 {
        return Err(GenError::Saturated(what.to_string()));
    }
    Ok(r as i32)
}

/// |v| < floor without overflow at i32::MIN.
fn below_noise(v: i32, floor: i32) -> bool {
    v.unsigned_abs() < floor.max(0) as u32
}

/// Build the protected set from a pair list, rejecting duplicate keys instead
/// of letting the last one win.
pub fn existing_from_pairs(
    pairs: Vec<ExistingPair>,
) -> Result<HashMap<(String, String), i32>, GenError> {
    let mut m = HashMap::new();
    for p in pairs {
        let key = (p.left, p.right);
        if m.contains_key(&key) {
            return Err(GenError::DuplicateExistingPair { left: key.0, right: key.1 });
        }
        m.insert(key, p.kern);
    }
    Ok(m)
}

/// Check the inputs generation relies on. Errors are reported in a fixed
/// order, so the same bad input always gives the same error.
pub fn validate_inputs(inp: &GenerationInputs) -> Result<(), GenError> {
    let mut seen: HashSet<&str> = HashSet::new();
    for g in &inp.glyphs {
        if !seen.insert(g.as_str()) {
            return Err(GenError::DuplicateGlyph(g.clone()));
        }
    }
    let mut ex: Vec<(&(String, String), &i32)> = inp.existing.iter().collect();
    ex.sort();
    for ((l, r), v) in ex {
        if saturated(*v) {
            return Err(GenError::Saturated(format!("existing value for {l} {r}")));
        }
    }
    let mut rs: HashSet<(&str, &str)> = HashSet::new();
    for p in &inp.restore {
        if !rs.insert((p.left.as_str(), p.right.as_str())) {
            return Err(GenError::DuplicateRestorePair { left: p.left.clone(), right: p.right.clone() });
        }
        if inp.existing.contains_key(&(p.left.clone(), p.right.clone())) {
            return Err(GenError::RestoreExistingConflict { left: p.left.clone(), right: p.right.clone() });
        }
        if saturated(p.kern) {
            return Err(GenError::Saturated(format!("restore value for {} {}", p.left, p.right)));
        }
    }
    let finite = |x: f64, what: &str| -> Result<(), GenError> {
        if x.is_finite() { Ok(()) } else { Err(GenError::NonFinite(what.to_string())) }
    };
    let mut cm: Vec<_> = inp.targets.cell_median.iter().collect();
    cm.sort_by(|a, b| a.0.cmp(b.0));
    for (_, v) in cm {
        finite(*v, "cell median target")?;
    }
    let mut sm: Vec<_> = inp.targets.stratum_mingap.iter().collect();
    sm.sort_by(|a, b| a.0.cmp(b.0));
    for (_, v) in sm {
        finite(*v, "stratum min-gap target")?;
    }
    finite(inp.targets.global_mingap, "global min-gap target")?;
    let mut wl: Vec<_> = inp.walls.iter().collect();
    wl.sort_by(|a, b| a.0.cmp(b.0));
    for (name, w) in wl {
        finite(w.advance, &format!("advance of {name}"))?;
        for (lx, rx) in w.rows.values() {
            finite(*lx, &format!("wall x of {name}"))?;
            finite(*rx, &format!("wall x of {name}"))?;
        }
    }
    Ok(())
}

/// Counters for the receipt (sign guard and outlier sensitivity).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct GenReport {
    pub written: usize,
    pub clamped_lo: usize,
    pub clamped_hi: usize,
    pub rejected_sign_flip: usize,
    pub below_noise: usize,
    /// Existing pairs whose source value is an explicit zero. They are
    /// protected from regeneration and excluded from the statistics.
    pub protected_zero: usize,
    /// Pairs (pair,value) that differ when the single most extreme existing
    /// value is dropped from each end of the clamp range (outlier sensitivity).
    pub trim1_symmetric_diff: usize,
}

/// Min-gap between the two walls at kern 0 over shared y rows, or None
/// when the glyphs share no inked row. Linear in kern by construction:
/// min_gap(k) = min_gap(0) + k, so the solve below is closed form.
pub fn min_gap0(left: &GlyphWall, right: &GlyphWall) -> Option<f64> {
    let mut best: Option<f64> = None;
    for (y, (lx_r, _)) in right.rows.iter() {
        if let Some((_, rx_l)) = left.rows.get(y) {
            let g = left.advance + lx_r - rx_l;
            if best.map_or(true, |b| g < b) {
                best = Some(g);
            }
        }
    }
    best
}

/// Predict one pair's kern: populated-cell median first, else the
/// geometric min-gap solve toward the stratum target with global
/// fallback. Returns the value source tag with the rounded value.
pub fn predict(
    inp: &GenerationInputs,
    left: &str,
    right: &str,
) -> Option<(i32, &'static str)> {
    predict_with(inp, left, right, None)
}

/// Provisional store key for a pair's feature cell. The field set is fixed by the
/// class design decision; until then it mirrors the cell tuple used above. Glyph
/// identity never enters the key.
fn provisional_key(
    kl: &GlyphKnowledge,
    kr: &GlyphKnowledge,
) -> Vec<(String, String)> {
    vec![
        ("right_class".into(), kl.right_class.to_string()),
        ("left_class".into(), kr.left_class.to_string()),
        ("case_left".into(), kl.case.to_string()),
        ("case_right".into(), kr.case.to_string()),
    ]
}

/// Same as `predict`, with optional learned priors. `None` is the current path,
/// unchanged. A prior is an additional candidate only for a cell with no
/// cell_median (UNSEEN by the existing evidence); it never replaces cell_median
/// and is consulted before the geometric solve only when the caller passed
/// `Some`, which it does only when the leave-font-out gate is open.
pub fn predict_with(
    inp: &GenerationInputs,
    left: &str,
    right: &str,
    priors: Option<&Priors>,
) -> Option<(i32, &'static str)> {
    predict_policy(inp, left, right, priors, &KernPolicy::permissive())
}

/// `predict_with` under a derived policy: a cell median is used only when
/// its existing-pair support reaches `min_cell_support`. A value that cannot
/// be represented (non-finite or outside the i32 range) yields `None` here;
/// `generate` reports it as a typed error instead.
pub fn predict_policy(
    inp: &GenerationInputs,
    left: &str,
    right: &str,
    priors: Option<&Priors>,
    pol: &KernPolicy,
) -> Option<(i32, &'static str)> {
    predict_checked(inp, left, right, priors, pol).ok().flatten()
}

/// Prediction with typed errors for unrepresentable values.
pub fn predict_checked(
    inp: &GenerationInputs,
    left: &str,
    right: &str,
    priors: Option<&Priors>,
    pol: &KernPolicy,
) -> Result<Option<(i32, &'static str)>, GenError> {
    let (Some(kl), Some(kr)) = (inp.knowledge.get(left), inp.knowledge.get(right)) else {
        return Ok(None);
    };
    let cell = (kl.right_class, kr.left_class, kl.case, kr.case);
    let supported = pol.cell_support.is_empty()
        || pol.cell_support.get(&cell).copied().unwrap_or(0) >= pol.min_cell_support;
    if let (true, Some(med)) = (supported, inp.targets.cell_median.get(&cell)) {
        return Ok(Some((round_to_i32(*med, "cell median")?, "cell")));
    }
    if let Some(p) = priors {
        if let Ok(pr) = p.lookup(&provisional_key(kl, kr)) {
            return Ok(Some((round_to_i32(pr.mean, "prior mean")?, "prior")));
        }
    }
    if let Some(open) = &pol.geom_open {
        if !open.get(&(kl.case, kr.case)).copied().unwrap_or(false) {
            return Ok(None);
        }
    }
    let target = inp
        .targets
        .stratum_mingap
        .get(&(kl.case, kr.case))
        .copied()
        .unwrap_or(inp.targets.global_mingap);
    let (Some(wl), Some(wr)) = (inp.walls.get(left), inp.walls.get(right)) else {
        return Ok(None);
    };
    let Some(g0) = min_gap0(wl, wr) else {
        return Ok(None);
    };
    Ok(Some((round_to_i32(target - g0, "geometric solve")?, "geom")))
}

/// Run the additive generation. Restorations lead verbatim; candidates
/// are visited in glyph-name order; existing nonzero pairs are never
/// candidates. There is no pair-count target: the set is the output.
/// Refuses with a typed error instead of returning silent emptiness.
pub fn generate(inp: &GenerationInputs) -> Result<Vec<GeneratedPair>, GenError> {
    generate_with(inp, None)
}

/// `generate` with optional learned priors; `None` is the no-prior path.
pub fn generate_with(
    inp: &GenerationInputs,
    priors: Option<&Priors>,
) -> Result<Vec<GeneratedPair>, GenError> {
    generate_with_policy(inp, priors).map(|r| r.0)
}

/// Same, also returning the derived policy and the counters for the receipt.
pub fn generate_with_policy(
    inp: &GenerationInputs,
    priors: Option<&Priors>,
) -> Result<(Vec<GeneratedPair>, KernPolicy, GenReport), GenError> {
    let pol = derive_policy(inp)?;
    let (out, mut rep) = run(inp, priors, &pol)?;
    // Outlier sensitivity: same inputs, clamp range with extremes trimmed.
    if let Ok(pol1) = derive_policy_trim(inp, 1) {
        let (out1, _) = run(inp, priors, &pol1)?;
        let a: std::collections::HashSet<_> = out.iter().map(|p| (&p.left, &p.right, p.kern)).collect();
        let b: std::collections::HashSet<_> = out1.iter().map(|p| (&p.left, &p.right, p.kern)).collect();
        rep.trim1_symmetric_diff = a.symmetric_difference(&b).count();
    }
    Ok((out, pol, rep))
}

fn run(
    inp: &GenerationInputs,
    priors: Option<&Priors>,
    pol: &KernPolicy,
) -> Result<(Vec<GeneratedPair>, GenReport), GenError> {
    validate_inputs(inp)?;
    let mut rep = GenReport::default();
    rep.protected_zero = inp.existing.values().filter(|v| **v == 0).count();
    let mut out: Vec<GeneratedPair> = Vec::new();
    for p in &inp.restore {
        out.push(GeneratedPair {
            left: p.left.clone(),
            right: p.right.clone(),
            kern: p.kern,
            tier: "T0".to_string(),
        });
    }
    let restored: std::collections::HashSet<(&str, &str)> = inp
        .restore
        .iter()
        .map(|p| (p.left.as_str(), p.right.as_str()))
        .collect();
    // Sort a copy: the order never depends on how the caller built the list.
    let mut glyphs: Vec<&String> = inp.glyphs.iter().collect();
    glyphs.sort();
    for l in glyphs.iter().copied() {
        for r in glyphs.iter().copied() {
            // Protects every existing pair, including explicit zeros.
            if inp.existing.contains_key(&((*l).clone(), (*r).clone())) {
                continue;
            }
            if restored.contains(&(l.as_str(), r.as_str())) {
                continue;
            }
            let (wl, wr) = match (inp.walls.get(l), inp.walls.get(r)) {
                (Some(a), Some(b)) => (a, b),
                _ => continue,
            };
            if min_gap0(wl, wr).is_none() {
                continue;
            }
            let Some((raw, src)) = predict_checked(inp, l, r, priors, pol)? else {
                continue;
            };
            let mut v = raw;
            if v < pol.clamp_lo {
                v = pol.clamp_lo;
                rep.clamped_lo += 1;
            } else if v > pol.clamp_hi {
                v = pol.clamp_hi;
                rep.clamped_hi += 1;
            }
            // Sign guard (unreachable while the range contains 0; kept explicit).
            if v != 0 && raw != 0 && (v < 0) != (raw < 0) {
                rep.rejected_sign_flip += 1;
                continue;
            }
            if below_noise(v, pol.noise_floor) {
                rep.below_noise += 1;
                continue;
            }
            out.push(GeneratedPair {
                left: l.to_string(),
                right: r.to_string(),
                kern: v,
                tier: format!("G-{src}"),
            });
        }
    }
    rep.written = out.len();
    Ok((out, rep))
}

/// Build the AdditiveKernSet over the existing inventory plus the
/// generated pairs and verify the multiset-exact additive guarantee
/// against the source inventory.
pub fn build_additive_set(
    inp: &GenerationInputs,
    generated: &[GeneratedPair],
) -> Result<AdditiveKernSet, String> {
    let inventory = PairInventory::new(
        inp.existing
            .iter()
            .map(|((l, r), v)| ExistingPair {
                left: l.clone(),
                right: r.clone(),
                kern: *v,
            })
            .collect(),
    );
    let mut set = AdditiveKernSet::new(&inventory);
    for p in generated {
        if !set.add_generated(
            ExistingPair {
                left: p.left.clone(),
                right: p.right.clone(),
                kern: p.kern,
            },
            &p.tier,
        ) {
            return Err(format!(
                "generated pair collides with existing or duplicate: {} {}",
                p.left, p.right
            ));
        }
    }
    set.verify_additive(&inventory)?;
    Ok(set)
}

// ---------- artifact parsing (line-based TSV, no external deps) ----------

fn fields(line: &str) -> Vec<&str> {
    line.split('\t').collect()
}

/// Parse classes.tsv: glyph, case, freq_weight, right_class, left_class.
pub fn parse_classes(text: &str) -> Result<(Vec<String>, HashMap<String, GlyphKnowledge>), String> {
    let mut glyphs = Vec::new();
    let mut map = HashMap::new();
    for line in text.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let f = fields(line);
        if f.len() < 5 {
            return Err(format!("classes row too short: {line}"));
        }
        let g = f[0].to_string();
        map.insert(
            g.clone(),
            GlyphKnowledge {
                case: f[1].chars().next().ok_or("empty case")?,
                freq_weight: f[2].parse().map_err(|_| "bad freq")?,
                right_class: f[3].parse().map_err(|_| "bad right_class")?,
                left_class: f[4].parse().map_err(|_| "bad left_class")?,
            },
        );
        glyphs.push(g);
    }
    glyphs.sort();
    Ok((glyphs, map))
}

/// Parse targets.tsv: CELL/STRATUM/GLOBAL sections.
pub fn parse_targets(text: &str) -> Result<ClassTargets, String> {
    let mut cell_median = HashMap::new();
    let mut stratum_mingap = HashMap::new();
    let mut global_mingap = None;
    for line in text.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let f = fields(line);
        match f[0] {
            "CELL" => {
                let cp: Vec<char> = f[3].chars().collect();
                if cp.len() != 2 {
                    return Err(format!("bad CELL case pair: {line}"));
                }
                cell_median.insert(
                    (
                        f[1].parse().map_err(|_| "bad cell k1")?,
                        f[2].parse().map_err(|_| "bad cell k2")?,
                        cp[0],
                        cp[1],
                    ),
                    f[5].parse().map_err(|_| "bad cell value")?,
                );
            }
            "STRATUM" => {
                let cp: Vec<char> = f[3].chars().collect();
                if cp.len() != 2 {
                    return Err(format!("bad STRATUM case pair: {line}"));
                }
                stratum_mingap.insert((cp[0], cp[1]), f[5].parse().map_err(|_| "bad stratum value")?);
            }
            "GLOBAL" => {
                global_mingap = Some(f[5].parse().map_err(|_| "bad global value")?);
            }
            other => return Err(format!("unknown targets section: {other}")),
        }
    }
    Ok(ClassTargets {
        cell_median,
        stratum_mingap,
        global_mingap: global_mingap.ok_or("missing GLOBAL row")?,
    })
}

/// Parse walls.tsv: glyph, advance, y, left_x, right_x.
pub fn parse_walls(text: &str) -> Result<HashMap<String, GlyphWall>, String> {
    let mut out: HashMap<String, GlyphWall> = HashMap::new();
    for line in text.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let f = fields(line);
        if f.len() < 5 {
            return Err(format!("walls row too short: {line}"));
        }
        let e = out.entry(f[0].to_string()).or_insert(GlyphWall {
            advance: f[1].parse().map_err(|_| "bad advance")?,
            rows: BTreeMap::new(),
        });
        e.rows.insert(
            f[2].parse().map_err(|_| "bad y")?,
            (f[3].parse().map_err(|_| "bad left_x")?, f[4].parse().map_err(|_| "bad right_x")?),
        );
    }
    Ok(out)
}

/// Parse existing.tsv / restore.tsv: left, right, kern_u.
pub fn parse_pairs(text: &str) -> Result<Vec<ExistingPair>, String> {
    let mut out = Vec::new();
    for line in text.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let f = fields(line);
        if f.len() < 3 {
            return Err(format!("pairs row too short: {line}"));
        }
        out.push(ExistingPair {
            left: f[0].to_string(),
            right: f[1].to_string(),
            kern: f[2].parse().map_err(|_| "bad kern")?,
        });
    }
    Ok(out)
}

#[cfg(test)]
mod unit {
    use super::*;

    #[test]
    fn round_to_i32_refuses_non_finite_and_saturation() {
        assert_eq!(round_to_i32(2.5, "x"), Ok(2));
        assert_eq!(round_to_i32(-22.5, "x"), Ok(-22));
        assert!(matches!(round_to_i32(f64::NAN, "x"), Err(GenError::NonFinite(_))));
        assert!(matches!(round_to_i32(f64::INFINITY, "x"), Err(GenError::NonFinite(_))));
        assert!(matches!(round_to_i32(-3.0e9, "x"), Err(GenError::Saturated(_))));
        assert!(matches!(round_to_i32(i32::MIN as f64, "x"), Err(GenError::Saturated(_))));
        assert_eq!(round_to_i32(i32::MAX as f64 - 1.0, "x"), Ok(i32::MAX - 1));
    }

    #[test]
    fn below_noise_does_not_overflow_at_i32_min() {
        assert!(!below_noise(i32::MIN, 1));
        assert!(!below_noise(i32::MIN, i32::MAX));
        assert!(below_noise(0, 1));
        assert!(!below_noise(-1, 1));
        assert!(!below_noise(5, 0));
    }
}
