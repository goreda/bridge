//! Holdout gate for learned priors. The existing gate metric is unchanged:
//! |predicted - actual| in font units, reported as median and p90, paired on the
//! same set of cells for prior and baseline (as in the paired same-set evaluation).
//! Baseline errors are computed from the cells passed in, never read from a stored
//! constant. A learned prior opens the production gate only if it beats the
//! baseline on BOTH median and p90 over the held-out cells it covers.
use crate::prior::{Cell, Priors, Unseen, MIN_FOLD_FONTS};

/// CONVENTION, not derived: groups a leave-group-out gate needs before it can
/// open. With two groups each fold is judged against a single opposing group,
/// so the result would rest on one comparison. Three is the smallest count where
/// every fold has at least two other groups to learn from. This is a declared
/// choice; no measurement in the font data produces it. The font floor is
/// separate and derived (MIN_FOLD_FONTS, enforced per fold by Priors::build).
pub const MIN_FOLD_GROUPS: usize = 3;
use crate::store::Store;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq)]
pub struct Stats {
    pub median: f64,
    pub p90: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GateReport {
    /// The name of the held-out unit. `evaluate_font` stores the id it was given;
    /// inside a `GroupReport` that is the group id, not a font id. Per-font
    /// numbers are in `GroupReport::members`.
    pub font_id: String,
    pub cells: usize,
    pub scored: usize,
    pub unseen: usize,
    pub prior: Option<Stats>,
    pub baseline: Option<Stats>,
    pub open: bool,
    /// Set when a statistic could not be computed; the report is then closed.
    pub refusal: Option<StatsError>,
}

/// Why a statistic could not be computed. Returned instead of panicking.
#[derive(Debug, Clone, PartialEq)]
pub enum StatsError {
    /// No values.
    Empty,
    /// A value is NaN or infinite; `index` is its position in the input.
    NonFinite { index: usize },
    /// The quantile is outside 0..=1 or NaN.
    BadQuantile,
}

/// Nearest-rank quantile (p in 0..=1) on a copy of `v`. Refuses an empty
/// input, a non-finite value and a quantile outside 0..=1.
pub fn try_quantile(v: &[f64], p: f64) -> Result<f64, StatsError> {
    if v.is_empty() {
        return Err(StatsError::Empty);
    }
    if !(0.0..=1.0).contains(&p) {
        return Err(StatsError::BadQuantile);
    }
    if let Some(index) = v.iter().position(|x| !x.is_finite()) {
        return Err(StatsError::NonFinite { index });
    }
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.total_cmp(b));
    let rank = ((p * s.len() as f64).ceil() as usize).clamp(1, s.len());
    Ok(s[rank - 1])
}

fn try_median(v: &[f64]) -> Result<f64, StatsError> {
    try_quantile(v, 0.5)
}

pub fn try_stats(errs: &[f64]) -> Result<Stats, StatsError> {
    Ok(Stats { median: try_median(errs)?, p90: try_quantile(errs, 0.9)? })
}

/// Evaluates priors built WITHOUT `font_id` on that font's cells. Cells with no
/// prior (UNSEEN) are not scored and cannot count toward opening the gate. The
/// gate is closed when nothing is scored or when the prior fails either quantile.
pub fn evaluate_font(priors: &Priors, font_id: &str, cells: &[Cell]) -> GateReport {
    let (mut pe, mut be, mut un) = (vec![], vec![], 0usize);
    for c in cells {
        match priors.lookup(&c.key) {
            Ok(p) => {
                pe.push((p.mean - c.observed).abs());
                be.push((c.baseline_pred - c.observed).abs());
            }
            Err(Unseen) => un += 1,
        }
    }
    if pe.is_empty() {
        return GateReport { font_id: font_id.into(), cells: cells.len(), scored: 0, unseen: un, prior: None, baseline: None, open: false, refusal: None };
    }
    let (p, b) = match (try_stats(&pe), try_stats(&be)) {
        (Ok(p), Ok(b)) => (p, b),
        (Err(e), _) | (_, Err(e)) => {
            return GateReport { font_id: font_id.into(), cells: cells.len(), scored: pe.len(), unseen: un, prior: None, baseline: None, open: false, refusal: Some(e) };
        }
    };
    let open = p.median < b.median && p.p90 < b.p90;
    GateReport { font_id: font_id.into(), cells: cells.len(), scored: pe.len(), unseen: un, prior: Some(p), baseline: Some(b), open, refusal: None }
}

/// Why the grouped gate refused to run.
#[derive(Debug, Clone, PartialEq)]
pub enum GateError {
    /// `group_of` returned no group for this certified font. A font without a
    /// group is never treated as its own group.
    UngroupedFont(String),
}

/// One member font of a held-out group, scored against the prior of its group
/// fold (the same held-out prior as the group report) on its own cells only.
/// It is a report: a failing or empty member does not close the gate.
#[derive(Debug, Clone, PartialEq)]
pub struct MemberReport {
    pub font_id: String,
    pub cells: usize,
    pub scored: usize,
    pub unseen: usize,
    pub prior: Option<Stats>,
    pub baseline: Option<Stats>,
    pub refusal: Option<StatsError>,
    pub open: bool,
    /// (this member's scored cells, scored cells of the whole group), as
    /// integers; no ratio is computed. (0, 0) when the group scored nothing.
    pub scored_share: (usize, usize),
    /// (this member's cells, all pooled cells of the group), as integers; no
    /// ratio is computed. (0, 0) when the group has no cells.
    pub total_cell_share: (usize, usize),
}

/// Scores one member's cells with the group's held-out priors. Uses the same
/// logic as `evaluate_font`; an empty member gives a closed report with
/// scored 0 and no refusal. The pooled counts come from the group report, so
/// the shares cannot be set from outside.
fn evaluate_member(priors: &Priors, font_id: &str, cells: &[Cell], pooled_cells: usize, pooled_scored: usize) -> MemberReport {
    let r = evaluate_font(priors, font_id, cells);
    MemberReport {
        font_id: font_id.into(),
        cells: r.cells,
        scored: r.scored,
        unseen: r.unseen,
        prior: r.prior,
        baseline: r.baseline,
        refusal: r.refusal,
        open: r.open,
        scored_share: (r.scored, pooled_scored),
        total_cell_share: (r.cells, pooled_cells),
    }
}

/// Report of one held-out group of fonts (family or component).
#[derive(Debug, Clone, PartialEq)]
pub struct GroupReport {
    pub group_id: String,
    pub fonts: Vec<String>,
    pub report: GateReport,
    /// One entry per font of the group, in the order of `fonts` (sorted by font
    /// id). Members never change `report` or the gate decision.
    pub members: Vec<MemberReport>,
}

/// Production gate: leave-group-out over every certified font. `group_of` maps a
/// font id to an opaque group id (for example a family); a fold excludes every
/// font of the held-out group, so a sibling cannot support its own prior. The
/// gate opens only if there are at least MIN_FOLD_FONTS fonts (derived) and at
/// least MIN_FOLD_GROUPS groups (declared convention), and every group's report
/// is open (no group may be sacrificed to a pooled average).
pub fn production_gate(
    s: &Store,
    cells_of: &dyn Fn(&str) -> Vec<Cell>,
    group_of: &dyn Fn(&str) -> Option<String>,
) -> Result<(bool, Vec<GroupReport>), GateError> {
    let fonts: BTreeSet<&str> = s.records.iter().filter(|o| o.prov.certified).map(|o| o.prov.font_id.as_str()).collect();
    let mut groups: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for f in &fonts {
        match group_of(f) {
            Some(g) => groups.entry(g).or_default().push(f.to_string()),
            None => return Err(GateError::UngroupedFont(f.to_string())),
        }
    }
    let reports: Vec<GroupReport> = groups
        .iter()
        .map(|(g, members)| {
            let held: BTreeSet<&str> = members.iter().map(|m| m.as_str()).collect();
            let priors = Priors::build_excluding(&s.records, &|f| held.contains(f));
            let per_member: Vec<Vec<Cell>> = members.iter().map(|m| cells_of(m)).collect();
            let pooled: Vec<Cell> = per_member.iter().flatten().cloned().collect();
            let group_report = evaluate_font(&priors, g, &pooled);
            let member_reports: Vec<MemberReport> = members
                .iter()
                .zip(&per_member)
                .map(|(m, cells)| evaluate_member(&priors, m, cells, group_report.cells, group_report.scored))
                .collect();
            GroupReport { group_id: g.clone(), fonts: members.clone(), report: group_report, members: member_reports }
        })
        .collect();
    let open = fonts.len() >= MIN_FOLD_FONTS && groups.len() >= MIN_FOLD_GROUPS && !reports.is_empty() && reports.iter().all(|r| r.report.open);
    Ok((open, reports))
}
