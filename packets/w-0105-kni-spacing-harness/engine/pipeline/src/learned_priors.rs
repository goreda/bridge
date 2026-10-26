//! learned_priors.rs — PC-K2 production consumer of the K2 learning layer.
//!
//! Chain: certified receipts -> kni-learning store -> production gate ->
//! cross-font priors -> pair targets for the class pairs the frozen anchor
//! fallback covers. This is the engine-side consumer named by the learning
//! crate's contract (learning/src/lib.rs): `Store::load` maps an absent,
//! empty, invalid or pin-mismatched store to `Loaded::Cold`, and a Cold
//! store or a closed gate leaves the engine's current measurement path
//! unchanged.
//!
//! What is consumed: emitted pairs whose class-pair target came from the
//! anchor fallback (`ClassTargetSource::AnchorWTarget` — no measured source
//! and no derived lane carried a target) are re-solved against the learned
//! cross-font target for that facing class pair, using the SAME per-pair
//! oracle the production cascade uses (`solve_pair_t_l2`) with the SAME
//! domain formula and export-frame binding as the cascade's eval closure
//! (metrics/src/self_anchored_spacing.rs pair-eval: base_offset = l_rsb +
//! r_lsb, raw_base = l_xmax - r_xmin + base_offset, domain [t_lo, t_hi] =
//! [-min_base, dcap - min_base], advance/l_tr/r_tr export binding). A
//! measured or derived target always wins; an UNSEEN key stays on the
//! anchor; glyph sidebearings are never touched (they are solved from the
//! font's own outlines, not learned).
//!
//! DECLARED_CONVENTION (PC-K2-1, canonical key): the store key for one
//! ordered facing pair is `[("class", "<L>-><R>")]` where L is the left
//! glyph's right facing class and R the right glyph's left facing class,
//! with `SideClass` Display tokens. The training feed (receipt rows) and
//! this consumer's lookup share `pair_key`, so producer and consumer
//! cannot drift apart.
//!
//! DECLARED_CONVENTION (PC-K2-2, conservative keep): a re-solve that
//! refuses (NoFeasible / NoAcceptedCandidate / NotConverged /
//! Unmeasurable) or lands below the production noise epsilon
//! (sample_resolution / 2, the cascade's BelowEpsilon gate) keeps the
//! original pair row. The pass never silently drops an emitted pair and
//! never invents a target: every applied, kept and skipped pair is
//! receipted in `LearnedReport`.

use std::collections::BTreeMap;

use kni_learning::gate::{production_gate, GroupReport};
use kni_learning::prior::{Cell, Key, Priors};
use kni_learning::store::{Loaded, Store};
use kni_metrics::class_audit::ClassTargetSource;
use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::{
    font_median_pair_target, solve_pair_t_l2, solve_spacing_with_class_audit, FontContext,
    PairSolve, SideClass, SpacingError, SpacingPolicy, SpacingSolution,
};
use kni_metrics::signed_clearance::clearance_cells_constant_rows;
use kni_metrics::class_audit::ClassAudit;

/// PC-K2-1: canonical store key for one ordered facing pair. `left` is the
/// left glyph's RIGHT facing class, `right` the right glyph's LEFT facing
/// class (the same facing orientation the cascade and the class audit use).
pub fn pair_key(left: SideClass, right: SideClass) -> Key {
    vec![("class".to_string(), format!("{left}->{right}"))]
}

/// The learning layer, gated for production use.
#[derive(Debug)]
pub enum Learned {
    /// No usable learning: absent/empty/invalid store, no pooled priors,
    /// or a closed production gate. The engine keeps its current path.
    Cold(String),
    /// Gate-open priors with the group evidence that opened the gate.
    Active(ActivePriors),
}

#[derive(Debug)]
pub struct ActivePriors {
    priors: Priors,
    groups: Vec<GroupReport>,
}

impl ActivePriors {
    pub fn priors(&self) -> &Priors {
        &self.priors
    }
    /// The leave-group-out evidence that opened the gate (one report per
    /// held-out group; the gate opened only if every group is open).
    pub fn groups(&self) -> &[GroupReport] {
        &self.groups
    }
}

/// Loads the store and runs the production gate. `cells_of` supplies each
/// certified font's held-out cells (its own observed key means against the
/// engine's current-path baseline predictions — see `observed_cells`);
/// `group_of` maps a font id to its family/group id so a sibling can never
/// support its own prior. Any refusal closes to `Learned::Cold` with the
/// reason; the gate decision itself lives in kni-learning.
pub fn load_and_gate(
    path: &str,
    pin: Option<&str>,
    cells_of: &dyn Fn(&str) -> Vec<Cell>,
    group_of: &dyn Fn(&str) -> Option<String>,
) -> Learned {
    let store = match Store::load(path, pin) {
        Loaded::Warm(s) => s,
        Loaded::Cold(reason) => return Learned::Cold(reason),
    };
    if !store.allowed_fields.iter().any(|f| f == "class") {
        return Learned::Cold(
            "store declares no 'class' key field; no pair-target query this consumer can answer"
                .into(),
        );
    }
    let priors = Priors::from_store(&store);
    if priors.is_empty() {
        return Learned::Cold(
            "no pooled priors (cold start: fewer than two certified fonts per bucket)".into(),
        );
    }
    match production_gate(&store, cells_of, group_of) {
        Err(e) => Learned::Cold(format!("gate refused to run: {e:?}")),
        Ok((false, _)) => Learned::Cold(
            "production gate closed: priors do not beat the engine's current path on every held-out group"
                .into(),
        ),
        Ok((true, groups)) => Learned::Active(ActivePriors { priors, groups }),
    }
}

/// The held-out font's own observed cells, read from the store's records:
/// `observed` = sum/n per key (the font's own certified mean) and
/// `baseline_pred` from the caller's current-path predictor (for the
/// spacing consumer: the anchor-fallback target the engine would use for
/// that class pair on that font). Keys without a baseline prediction are
/// skipped, never scored against a zero.
pub fn observed_cells(
    store: &Store,
    font_id: &str,
    baseline: &dyn Fn(&Key) -> Option<f64>,
) -> Vec<Cell> {
    let mut acc: BTreeMap<&Key, (u64, f64)> = BTreeMap::new();
    for o in store.records.iter().filter(|o| o.prov.certified && o.prov.font_id == font_id) {
        let e = acc.entry(&o.key).or_insert((0, 0.0));
        e.0 += o.n;
        e.1 += o.sum;
    }
    acc.into_iter()
        .filter_map(|(k, (n, s))| {
            if n == 0 {
                return None;
            }
            Some(Cell { key: k.clone(), observed: s / n as f64, baseline_pred: baseline(k)? })
        })
        .collect()
}

/// One re-targeted pair: identity, the anchor target the frozen cascade
/// used, the learned target that replaced it, and the measured before/after
/// origin distances (glyph-origin frame, the solver's output frame).
#[derive(Debug, Clone, PartialEq)]
pub struct AppliedPair {
    pub left: String,
    pub right: String,
    pub key: String,
    pub anchor_target: f64,
    pub learned_target: f64,
    pub before_origin: f64,
    pub after_origin: f64,
}

/// Receipt of the learned pass over one solution. Counts partition the
/// emitted pair population: applied + skipped_* + kept_* == pairs.len().
#[derive(Debug, Clone, Default, PartialEq)]
pub struct LearnedReport {
    pub applied: Vec<AppliedPair>,
    /// Pairs whose target came from a measured source or a derived lane:
    /// learned targets never override them.
    pub skipped_measured_or_derived: usize,
    /// Pairs whose facing class pair has no gate-open prior (UNSEEN stays
    /// on the anchor, by the learning crate's contract).
    pub skipped_unseen: usize,
    /// Pairs kept on their original row because the re-solve refused or
    /// the learned target was not a usable (finite, >= 0) value.
    pub kept_after_refusal: usize,
    /// Pairs kept because the re-solve landed below the production noise
    /// epsilon (the cascade's BelowEpsilon gate); never silently dropped.
    pub kept_below_epsilon: usize,
}

/// The solution (re-targeted where the report says) plus the class audit
/// of the SAME underlying solve and the learned-pass receipt.
#[derive(Debug)]
pub struct LearnedSolve {
    pub solution: SpacingSolution,
    pub audit: ClassAudit,
    pub report: LearnedReport,
}

/// Solves spacing and applies gate-open learned priors to the pairs the
/// anchor fallback covered. `learned == None` (Cold store or closed gate)
/// returns the frozen solution untouched with an empty report: the engine's
/// current measurement path is unchanged, per the learning crate contract.
pub fn solve_with_priors(
    profiles: &[OutlineProfile],
    ctx: Option<&FontContext>,
    policy: &SpacingPolicy,
    learned: Option<&Priors>,
) -> Result<LearnedSolve, SpacingError> {
    let (mut sol, audit) = solve_spacing_with_class_audit(profiles, ctx, policy)?;
    let mut report = LearnedReport::default();
    let priors = match learned {
        Some(p) if !p.is_empty() => p,
        _ => return Ok(LearnedSolve { solution: sol, audit, report }),
    };

    // Snapshot the solved sidebearings the re-solve binds against (the
    // cascade's metrics map: (lsb, rsb, advance) per glyph id).
    let glyph_metrics: BTreeMap<&str, (f64, f64, f64)> = sol
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.as_str(), (g.lsb, g.rsb, g.advance)))
        .collect();
    let prof_by_id: BTreeMap<&str, &OutlineProfile> =
        profiles.iter().map(|p| (p.glyph_id.as_str(), p)).collect();
    // Facing classes from the SAME solve's audit (never re-classified).
    let class_of: BTreeMap<&str, (SideClass, SideClass)> = audit
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.as_str(), (g.left_class, g.right_class)))
        .collect();

    let eps = policy.sample_resolution / 2.0;
    for i in 0..sol.pairs.len() {
        let (left, right) = (sol.pairs[i].left.clone(), sol.pairs[i].right.clone());
        let row = match audit.pair_target_for(&left, &right) {
            Some(r) => r,
            None => {
                report.kept_after_refusal += 1;
                continue;
            }
        };
        if row.source != ClassTargetSource::AnchorWTarget {
            report.skipped_measured_or_derived += 1;
            continue;
        }
        // Face the pair as the solver does: left glyph's right side into
        // right glyph's left side.
        let (lclass, rclass) = match (class_of.get(left.as_str()), class_of.get(right.as_str())) {
            (Some(&(_, lc)), Some(&(rc, _))) => (lc, rc),
            _ => {
                report.kept_after_refusal += 1;
                continue;
            }
        };
        let key = pair_key(lclass, rclass);
        let learned_target = match priors.lookup(&key) {
            Ok(p) => p.mean,
            Err(_) => {
                report.skipped_unseen += 1;
                continue;
            }
        };
        if !(learned_target.is_finite() && learned_target >= 0.0) {
            report.kept_after_refusal += 1;
            continue;
        }
        let (Some(&(l_lsb, l_rsb, advance_l)), Some(&(r_lsb, _, _))) =
            (glyph_metrics.get(left.as_str()), glyph_metrics.get(right.as_str()))
        else {
            report.kept_after_refusal += 1;
            continue;
        };
        let (Some(&lp), Some(&rp)) =
            (prof_by_id.get(left.as_str()), prof_by_id.get(right.as_str()))
        else {
            report.kept_after_refusal += 1;
            continue;
        };
        // The cascade's eval recipe, verbatim (see module doc): same domain
        // formula, same export-frame binding, same oracle.
        let base_offset = l_rsb + r_lsb;
        let raw_base = lp.bounds[2] - rp.bounds[0] + base_offset;
        let cells = clearance_cells_constant_rows(
            &kni_metrics::outline_spacing::align_pair_rows(lp, rp),
            raw_base,
        );
        if cells.len() < policy.pair_min_shared_rows {
            report.kept_after_refusal += 1;
            continue;
        }
        let min_base = cells.iter().fold(f64::INFINITY, |m, c| m.min(c.1).min(c.2));
        if !min_base.is_finite() {
            report.kept_after_refusal += 1;
            continue;
        }
        let t_lo = -min_base;
        let t_hi = (audit.dcap - min_base).max(t_lo);
        let l_tr = l_lsb - lp.bounds[0];
        let r_tr = r_lsb - rp.bounds[0];
        match solve_pair_t_l2(
            lp, rp, raw_base, audit.dcap, learned_target, audit.lambda, t_lo, t_hi, advance_l,
            l_tr, r_tr,
        ) {
            PairSolve::Solved { residual, origin, wall_gap, .. } => {
                if residual.abs() < eps {
                    report.kept_below_epsilon += 1;
                    continue;
                }
                let before = sol.pairs[i].origin_distance;
                sol.pairs[i].origin_distance = origin;
                sol.pairs[i].wall_gap = wall_gap;
                sol.pairs[i].pair_target = Some(learned_target);
                sol.pairs[i].optical_cost =
                    distribution_variance_at(lp, rp, raw_base + residual, audit.dcap)
                        .unwrap_or(sol.pairs[i].optical_cost);
                report.applied.push(AppliedPair {
                    key: format!("{lclass}->{rclass}"),
                    left,
                    right,
                    anchor_target: row.target,
                    learned_target,
                    before_origin: before,
                    after_origin: origin,
                });
            }
            _ => {
                report.kept_after_refusal += 1;
            }
        }
    }
    if !report.applied.is_empty() {
        sol.font_median_pair_target = font_median_pair_target(&sol.pairs);
        sol.policy_derivation = format!(
            "{} + learned_priors(PC-K2: {} anchor-target pairs re-targeted from gate-open store priors; measured/derived targets untouched)",
            sol.policy_derivation,
            report.applied.len()
        );
    }
    Ok(LearnedSolve { solution: sol, audit, report })
}

/// The production `optical_cost` reconstruction: production fills
/// `PairPosition.optical_cost` with the VARIANCE term only
/// (`let (_, var) = channel_stats(&cells_at, 0.0, dcap)` at the solved
/// placement; metrics/src/self_anchored_spacing.rs pair assembly), so this
/// returns the same variance of the capped gap over the pair's clearance
/// cells at the solved placement (raw_base + residual). The fold copies
/// cell_integrals + channel_stats with the same per-cell math and
/// accumulation order; bit-identity against the cascade's own optical_cost
/// is pinned in this crate's tests (re-solve at the original target
/// reproduces the original optical_cost exactly).
fn distribution_variance_at(
    lp: &OutlineProfile,
    rp: &OutlineProfile,
    offset: f64,
    cap: f64,
) -> Option<f64> {
    let cells = clearance_cells_constant_rows(
        &kni_metrics::outline_spacing::align_pair_rows(lp, rp),
        offset,
    );
    if cells.is_empty() {
        return None;
    }
    let (mut len, mut s1, mut s2) = (0.0, 0.0, 0.0);
    for &(l, c0, c1) in &cells {
        let (a, b) = cell_integrals(l, c0, c1, cap);
        len += l;
        s1 += a;
        s2 += b;
    }
    if !(len > 0.0) {
        return Some(0.0);
    }
    let w = s1 / len;
    Some((s2 / len - w * w).max(0.0))
}

/// Integrals over one linear gap segment of min(c, cap) and min(c, cap)^2.
/// Verbatim copy of the cascade's cell_integrals (source-cited above); the
/// tests pin bit-identity against the cascade's own optical_cost.
fn cell_integrals(len: f64, c0: f64, c1: f64, cap: f64) -> (f64, f64) {
    let lin =
        |len: f64, a: f64, b: f64| (len * (a + b) / 2.0, len * (a * a + a * b + b * b) / 3.0);
    if c0 <= cap && c1 <= cap {
        return lin(len, c0, c1);
    }
    if c0 >= cap && c1 >= cap {
        return (len * cap, len * cap * cap);
    }
    let f = (cap - c0) / (c1 - c0);
    let (lo_len, hi_len) = (len * f, len * (1.0 - f));
    if c0 < cap {
        let (a, b) = lin(lo_len, c0, cap);
        (a + hi_len * cap, b + hi_len * cap * cap)
    } else {
        let (a, b) = lin(hi_len, cap, c1);
        (a + lo_len * cap, b + lo_len * cap * cap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pair_key_uses_display_tokens_and_facing_order() {
        assert_eq!(
            pair_key(SideClass::Straight, SideClass::Round),
            vec![("class".to_string(), "straight->round".to_string())]
        );
        assert_eq!(
            pair_key(SideClass::Round, SideClass::Straight),
            vec![("class".to_string(), "round->straight".to_string())]
        );
    }
}
