//! Kern proposal table: one row per candidate glyph pair the font does not
//! already kern, each either `proposed` with a value or `unavailable` with a
//! reason. It wraps the additive generator in `gen`; it adds no predictor and
//! changes no value. It is not a GPOS export.
//!
//! Values are proposals, not validated results; no accuracy claim is made.
//! Existing pairs, explicit zeros included, are protected and never get a row.
//!
//! CONVENTION: rows are ordered by (left glyph name, right glyph name), byte
//! order. The tier of a source is mapped as: restore -> direct source, cell ->
//! class derived, prior -> class derived, geom -> engine derived.
//!
//! The solver path is not used. `Reason::NotConverged` is reserved and never
//! produced.

use crate::evidence::Tier;
use crate::gen::{self, GenError, GenerationInputs, KernPolicy};
use kni_learning::sha256::sha256_hex;
use kni_learning::Priors;
use std::collections::{BTreeMap, HashSet};

/// Fixed labels of the value source, stated on every predicted row.
pub const PREDICTOR_LABEL: &str = "predict_policy";
pub const FIT_SCOPE_LABEL: &str = "font-local existing pairs";
/// Header line and column order of the TSV.
pub const TSV_HEADER: &str = "#kern-proposal-table\tv1";
pub const TSV_COLUMNS: &str =
    "#columns\tleft\tright\tstatus\tvalue\traw_value\tsource\ttier\tcell_support\tclamped\treason\tpredictor\tfit_scope";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Proposed,
    Unavailable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    Cell,
    Geom,
    Prior,
    Restore,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Cell => "cell",
            Source::Geom => "geom",
            Source::Prior => "prior",
            Source::Restore => "restore",
        }
    }
    pub fn tier(self) -> Tier {
        match self {
            Source::Restore => Tier::DirectSource,
            Source::Cell | Source::Prior => Tier::ClassDerived,
            Source::Geom => Tier::EngineDerived,
        }
    }
}

fn tier_str(t: Tier) -> &'static str {
    match t {
        Tier::DirectSource => "direct_source",
        Tier::ClassDerived => "class_derived",
        Tier::EngineDerived => "engine_derived",
        Tier::DesignerOverride => "designer_override",
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Clamped {
    No,
    Lo,
    Hi,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Reason {
    /// One of the glyphs has no wall data.
    NoWallData,
    /// The two glyphs share no inked row at kern 0.
    NoSharedRows,
    /// No class knowledge for a glyph, so no value could be predicted.
    NoValue,
    /// The clamped value is below the font's noise floor.
    BelowNoise,
    /// Clamping flipped the sign (unreachable while the range contains 0).
    ClampSignFlip,
    /// A prior produced a non-finite value.
    NonFinite,
    /// A predicted value is outside the i32 range.
    Saturated,
    /// Reserved for a solver path that is not used.
    NotConverged,
}

impl Reason {
    pub fn as_str(self) -> &'static str {
        match self {
            Reason::NoWallData => "no_wall_data",
            Reason::NoSharedRows => "no_shared_rows",
            Reason::NoValue => "no_value",
            Reason::BelowNoise => "below_noise",
            Reason::ClampSignFlip => "clamp_sign_flip",
            Reason::NonFinite => "non_finite",
            Reason::Saturated => "saturated",
            Reason::NotConverged => "not_converged",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProposalRow {
    pub left: String,
    pub right: String,
    pub status: Status,
    /// Present only when `status` is `Proposed`.
    pub value: Option<i32>,
    /// Value before clamp and noise test, when one was computed.
    pub raw_value: Option<i32>,
    pub source: Option<Source>,
    /// Existing pairs in the cell behind a cell median.
    pub cell_support: Option<usize>,
    pub clamped: Clamped,
    /// Present only when `status` is `Unavailable`.
    pub reason: Option<Reason>,
}

#[derive(Debug, Clone)]
pub struct Proposal {
    pub rows: Vec<ProposalRow>,
    /// (field, derivation text) of the policy.
    pub policy: Vec<(String, String)>,
    /// Existing pairs protected from proposals, explicit zeros included.
    pub protected_existing: usize,
    pub protected_zero: usize,
    pub inputs_sha256: String,
}

fn unavailable(l: &str, r: &str, reason: Reason) -> ProposalRow {
    ProposalRow {
        left: l.to_string(),
        right: r.to_string(),
        status: Status::Unavailable,
        value: None,
        raw_value: None,
        source: None,
        cell_support: None,
        clamped: Clamped::No,
        reason: Some(reason),
    }
}

fn candidate(
    inp: &GenerationInputs,
    priors: Option<&Priors>,
    pol: &KernPolicy,
    l: &str,
    r: &str,
) -> Result<ProposalRow, GenError> {
    let (Some(wl), Some(wr)) = (inp.walls.get(l), inp.walls.get(r)) else {
        return Ok(unavailable(l, r, Reason::NoWallData));
    };
    if gen::min_gap0(wl, wr).is_none() {
        return Ok(unavailable(l, r, Reason::NoSharedRows));
    }
    let (raw, src) = match gen::predict_checked(inp, l, r, priors, pol) {
        Ok(Some(x)) => x,
        Ok(None) => return Ok(unavailable(l, r, Reason::NoValue)),
        Err(GenError::NonFinite(_)) => return Ok(unavailable(l, r, Reason::NonFinite)),
        Err(GenError::Saturated(_)) => return Ok(unavailable(l, r, Reason::Saturated)),
        Err(e) => return Err(e),
    };
    let source = match src {
        "cell" => Source::Cell,
        "prior" => Source::Prior,
        _ => Source::Geom,
    };
    let cell_support = if source == Source::Cell {
        match (inp.knowledge.get(l), inp.knowledge.get(r)) {
            (Some(kl), Some(kr)) => pol.cell_support.get(&(kl.right_class, kr.left_class, kl.case, kr.case)).copied(),
            _ => None,
        }
    } else {
        None
    };
    let mut v = raw;
    let mut clamped = Clamped::No;
    if v < pol.clamp_lo {
        v = pol.clamp_lo;
        clamped = Clamped::Lo;
    } else if v > pol.clamp_hi {
        v = pol.clamp_hi;
        clamped = Clamped::Hi;
    }
    let mut row = ProposalRow {
        left: l.to_string(),
        right: r.to_string(),
        status: Status::Unavailable,
        value: None,
        raw_value: Some(raw),
        source: Some(source),
        cell_support,
        clamped,
        reason: None,
    };
    if v != 0 && raw != 0 && (v < 0) != (raw < 0) {
        row.reason = Some(Reason::ClampSignFlip);
    } else if v.unsigned_abs() < pol.noise_floor.max(0) as u32 {
        row.reason = Some(Reason::BelowNoise);
    } else {
        row.status = Status::Proposed;
        row.value = Some(v);
    }
    Ok(row)
}

/// Build the proposal table. Input errors are the typed errors of `gen`.
pub fn build_proposal(inp: &GenerationInputs, priors: Option<&Priors>) -> Result<Proposal, GenError> {
    gen::validate_inputs(inp)?;
    let pol = gen::derive_policy(inp)?;
    let mut rows: Vec<ProposalRow> = Vec::new();
    for p in &inp.restore {
        rows.push(ProposalRow {
            left: p.left.clone(),
            right: p.right.clone(),
            status: Status::Proposed,
            value: Some(p.kern),
            raw_value: Some(p.kern),
            source: Some(Source::Restore),
            cell_support: None,
            clamped: Clamped::No,
            reason: None,
        });
    }
    let restored: HashSet<(&str, &str)> = inp.restore.iter().map(|p| (p.left.as_str(), p.right.as_str())).collect();
    let mut glyphs: Vec<&String> = inp.glyphs.iter().collect();
    glyphs.sort();
    for l in glyphs.iter().copied() {
        for r in glyphs.iter().copied() {
            if inp.existing.contains_key(&(l.clone(), r.clone())) || restored.contains(&(l.as_str(), r.as_str())) {
                continue;
            }
            rows.push(candidate(inp, priors, &pol, l, r)?);
        }
    }
    rows.sort_by(|a, b| (a.left.as_str(), a.right.as_str()).cmp(&(b.left.as_str(), b.right.as_str())));
    Ok(Proposal {
        rows,
        policy: pol.derivation.clone(),
        protected_existing: inp.existing.len(),
        protected_zero: inp.existing.values().filter(|v| **v == 0).count(),
        inputs_sha256: sha256_hex(canonical_inputs(inp).as_bytes()),
    })
}

/// Canonical text of the inputs: sorted, exact float representation.
fn canonical_inputs(inp: &GenerationInputs) -> String {
    let mut s = String::new();
    let mut glyphs: Vec<&String> = inp.glyphs.iter().collect();
    glyphs.sort();
    for g in glyphs {
        s.push_str(&format!("G\t{g}\n"));
    }
    let mut ex: Vec<_> = inp.existing.iter().collect();
    ex.sort();
    for ((l, r), v) in ex {
        s.push_str(&format!("E\t{l}\t{r}\t{v}\n"));
    }
    for p in &inp.restore {
        s.push_str(&format!("R\t{}\t{}\t{}\n", p.left, p.right, p.kern));
    }
    let mut kn: Vec<_> = inp.knowledge.iter().collect();
    kn.sort_by(|a, b| a.0.cmp(b.0));
    for (g, k) in kn {
        s.push_str(&format!("K\t{g}\t{}\t{}\t{}\t{}\n", k.case, k.freq_weight, k.right_class, k.left_class));
    }
    let mut cm: Vec<_> = inp.targets.cell_median.iter().collect();
    cm.sort_by(|a, b| a.0.cmp(b.0));
    for (k, v) in cm {
        s.push_str(&format!("C\t{k:?}\t{v:?}\n"));
    }
    let mut sm: Vec<_> = inp.targets.stratum_mingap.iter().collect();
    sm.sort_by(|a, b| a.0.cmp(b.0));
    for (k, v) in sm {
        s.push_str(&format!("S\t{k:?}\t{v:?}\n"));
    }
    s.push_str(&format!("T\t{:?}\n", inp.targets.global_mingap));
    let mut wl: Vec<_> = inp.walls.iter().collect();
    wl.sort_by(|a, b| a.0.cmp(b.0));
    for (g, w) in wl {
        s.push_str(&format!("W\t{g}\t{:?}\n", w.advance));
        for (y, (lx, rx)) in &w.rows {
            s.push_str(&format!("w\t{y}\t{lx:?}\t{rx:?}\n"));
        }
    }
    s
}

fn clean(t: &str) -> String {
    t.replace(['\t', '\n', '\r'], " ")
}

fn na<T: ToString>(v: Option<T>) -> String {
    v.map_or("n/a".to_string(), |x| x.to_string())
}

impl Proposal {
    /// Fixed-column TSV. Header lines start with `#`. Absent fields read `n/a`.
    pub fn tsv(&self) -> String {
        let mut o = String::new();
        o.push_str(TSV_HEADER);
        o.push('\n');
        o.push_str(TSV_COLUMNS);
        o.push('\n');
        for (f, t) in &self.policy {
            o.push_str(&format!("#policy\t{}\t{}\n", clean(f), clean(t)));
        }
        let mut counts: BTreeMap<String, usize> = BTreeMap::new();
        for r in &self.rows {
            let key = match r.status {
                Status::Proposed => format!("proposed:{}", r.source.map_or("n/a", |s| s.as_str())),
                Status::Unavailable => format!("unavailable:{}", r.reason.map_or("n/a", |x| x.as_str())),
            };
            *counts.entry(key).or_insert(0) += 1;
        }
        for (k, n) in &counts {
            o.push_str(&format!("#count\t{k}\t{n}\n"));
        }
        o.push_str(&format!("#protected_existing\t{}\n", self.protected_existing));
        o.push_str(&format!("#protected_zero\t{}\n", self.protected_zero));
        o.push_str(&format!("#inputs_sha256\t{}\n", self.inputs_sha256));
        for r in &self.rows {
            let (predictor, scope) = match r.source {
                Some(Source::Restore) | None => ("n/a", "n/a"),
                Some(_) => (PREDICTOR_LABEL, FIT_SCOPE_LABEL),
            };
            let clamped = match r.clamped {
                Clamped::No => "none",
                Clamped::Lo => "lo",
                Clamped::Hi => "hi",
            };
            o.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                r.left,
                r.right,
                match r.status {
                    Status::Proposed => "proposed",
                    Status::Unavailable => "unavailable",
                },
                na(r.value),
                na(r.raw_value),
                r.source.map_or("n/a", |s| s.as_str()),
                r.source.map_or("n/a", |s| tier_str(s.tier())),
                na(r.cell_support),
                clamped,
                r.reason.map_or("n/a", |x| x.as_str()),
                predictor,
                scope,
            ));
        }
        o
    }

    /// SHA-256 of the TSV bytes: the pin of the table.
    pub fn tsv_sha256(&self) -> String {
        sha256_hex(self.tsv().as_bytes())
    }
}
