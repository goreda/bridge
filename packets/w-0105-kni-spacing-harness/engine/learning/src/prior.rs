use crate::store::{Obs, Store};
use std::collections::{BTreeMap, BTreeSet};

pub type Key = Vec<(String, String)>;

/// Pooled prior for one feature bucket. Every font contributes one mean with equal
/// weight, so a font with many observations cannot dominate.
#[derive(Debug, Clone, PartialEq)]
pub struct Prior {
    pub mean: f64,
    pub fonts: usize,
    /// Variance of the per-font means (between-font spread), from sample moments.
    pub between_var: f64,
}

impl Prior {
    /// Updates the prior with a new font's own measurements (n, sum, sumsq).
    /// Weight on the font's own mean = tau2 / (tau2 + s2/n), where tau2 is the
    /// between-font variance and s2/n the variance of the font's own mean, both from
    /// data (sumsq). More own data or a tighter own spread moves the result toward
    /// the font's own mean; no tuned constant is involved.
    pub fn shrink(&self, n: u64, sum: f64, sumsq: f64) -> f64 {
        // A variance needs at least two observations; with fewer, the font's own
        // spread is unknown and a single value must not be trusted fully.
        if n < 2 {
            return self.mean;
        }
        let nf = n as f64;
        let own = sum / nf;
        let s2 = ((sumsq - nf * own * own) / (nf - 1.0)).max(0.0); // unbiased sample variance
        let sem2 = s2 / nf;
        let denom = self.between_var + sem2;
        if denom <= 0.0 {
            return own;
        }
        let w = self.between_var / denom;
        self.mean + w * (own - self.mean)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Priors {
    map: BTreeMap<Key, Prior>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Unseen;

impl Priors {
    /// Builds priors from certified fonts only. A bucket gets a prior only when at
    /// least two distinct fonts support it (leave-one-out needs another font);
    /// fewer fonts overall yields no priors at all (cold start).
    pub fn build(records: &[Obs], exclude_font: Option<&str>) -> Priors {
        Priors::build_excluding(records, &|f| Some(f) == exclude_font)
    }

    /// Same as `build`, but excludes every font for which `excluded` is true
    /// (a held-out group of fonts). Weighting is unchanged: one mean per font.
    pub fn build_excluding(records: &[Obs], excluded: &dyn Fn(&str) -> bool) -> Priors {
        let mut per: BTreeMap<&Key, BTreeMap<&str, (u64, f64)>> = BTreeMap::new();
        for o in records.iter().filter(|o| o.prov.certified && !excluded(o.prov.font_id.as_str())) {
            let e = per.entry(&o.key).or_default().entry(o.prov.font_id.as_str()).or_insert((0, 0.0));
            e.0 += o.n;
            e.1 += o.sum;
        }
        let all: BTreeSet<&str> = per.values().flat_map(|m| m.keys().copied()).collect();
        let mut map = BTreeMap::new();
        if all.len() >= MIN_FONTS {
            for (k, fonts) in per {
                if fonts.len() >= MIN_FONTS {
                    let means: Vec<f64> = fonts.values().filter(|(n, _)| *n > 0).map(|(n, s)| s / *n as f64).collect();
                    if means.len() >= MIN_FONTS {
                        let m = means.iter().sum::<f64>() / means.len() as f64;
                        let bv = means.iter().map(|x| (x - m) * (x - m)).sum::<f64>() / (means.len() - 1) as f64;
                        map.insert(k.clone(), Prior { mean: m, fonts: means.len(), between_var: bv });
                    }
                }
            }
        }
        Priors { map }
    }

    pub fn lookup(&self, key: &Key) -> Result<&Prior, Unseen> {
        self.map.get(key).ok_or(Unseen)
    }
    pub fn len(&self) -> usize {
        self.map.len()
    }
    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }
    pub fn from_store(s: &Store) -> Priors {
        Priors::build(&s.records, None)
    }
}

/// Structural minimum: a prior needs one font to learn from besides the font it is
/// used on. This is the definition of leave-one-out, not a tuned value.
const MIN_FONTS: usize = 2;

/// Fonts a leave-one-out fold needs in total. `Priors::build` forms a prior
/// only when at least MIN_FONTS fonts remain after the held-out font is
/// excluded, so a fold needs MIN_FONTS other fonts plus the held-out one.
/// Derived from MIN_FONTS, not a separate choice.
pub const MIN_FOLD_FONTS: usize = MIN_FONTS + 1;

/// A held-out cell: the font's own observed mean and what the baseline predicted.
#[derive(Debug, Clone)]
pub struct Cell {
    pub key: Key,
    pub observed: f64,
    pub baseline_pred: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FontReport {
    pub font_id: String,
    pub cells: usize,
    pub unseen: usize,
    pub prior_abs_err: f64,    // summed over seen cells
    pub baseline_abs_err: f64, // same cells
    pub beats_baseline: bool,  // strictly lower error on seen cells, and at least one seen cell
}

/// Leave-font-out: for each certified font, build priors from the others and score
/// them on the held-out font's cells. Cells whose bucket has no prior are UNSEEN and
/// are never scored as wins (they cannot open the gate).
pub fn leave_font_out(s: &Store, cells_of: &dyn Fn(&str) -> Vec<Cell>) -> Vec<FontReport> {
    let fonts: BTreeSet<&str> = s.records.iter().filter(|o| o.prov.certified).map(|o| o.prov.font_id.as_str()).collect();
    fonts
        .iter()
        .map(|f| {
            let pri = Priors::build(&s.records, Some(f));
            let cells = cells_of(f);
            let (mut un, mut pe, mut be) = (0usize, 0.0, 0.0);
            let mut seen = 0usize;
            for c in &cells {
                match pri.lookup(&c.key) {
                    Ok(p) => {
                        seen += 1;
                        pe += (p.mean - c.observed).abs();
                        be += (c.baseline_pred - c.observed).abs();
                    }
                    Err(Unseen) => un += 1,
                }
            }
            FontReport { font_id: f.to_string(), cells: cells.len(), unseen: un, prior_abs_err: pe, baseline_abs_err: be, beats_baseline: seen > 0 && pe < be }
        })
        .collect()
}
