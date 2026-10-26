
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Median,
    Class,
}

impl Mode {
    pub fn token(self) -> &'static str {
        match self {
            Mode::Median => "median",
            Mode::Class => "class",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TieBreak {
    A,
    B,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SideMedians {
    pub lsb: f64,
    pub rsb: f64,
        }
    }
}

/// Median of finite values. Even n: see the TAHMIN note in the module header.
/// None on empty input (never an invented 0.0). Non-finite values: None as well
/// (callers check finiteness first and return their own typed error).
pub fn median_with_tie_break(values: &[f64], tie_break: TieBreak) -> Option<f64> {
    if values.is_empty() || values.iter().any(|v| !v.is_finite()) {
        return None;
    }
    let mut v = values.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = v.len();
    if n % 2 == 1 {
        return Some(v[n / 2]);
    }
    let lo = v[n / 2 - 1];
    let hi = v[n / 2];
    Some(match tie_break {
        TieBreak::A => (lo + hi) / 2.0,
        TieBreak::B => lo,
    })
}

/// One pool observation: a glyph side pair, with its class on each side.
#[derive(Clone, Debug, PartialEq)]
pub struct PoolObservation {
    pub left_class: Option<String>,
    pub right_class: Option<String>,
    pub lsb: f64,
    pub rsb: f64,
}

/// Build pool medians from observations (pure; the caller loads the file).
/// global = median over all observations per side. per_class lsb median uses
/// observations whose left_class is that class; rsb median uses right_class.
/// A class seen on only one side gets a median on that side only; the other
/// side takes the global median value so the struct stays total, and the class
/// is still present in the map (basis stays `class:<id>`).
pub fn build_pool_medians(
    obs: &[PoolObservation],
    tie_break: TieBreak,
) -> Result<PoolMedians, AutoSbError> {
    if obs.is_empty() {
        return Err(AutoSbError::EmptyObservations);
    }
    for (i, o) in obs.iter().enumerate() {
        if !o.lsb.is_finite() || !o.rsb.is_finite() {
            return Err(AutoSbError::NonFiniteObservation { index: i });
        }
    }
    let lsbs: Vec<f64> = obs.iter().map(|o| o.lsb).collect();
    let rsbs: Vec<f64> = obs.iter().map(|o| o.rsb).collect();
    let global = SideMedians {
        lsb: median_with_tie_break(&lsbs, tie_break).ok_or(AutoSbError::EmptyObservations)?,
        rsb: median_with_tie_break(&rsbs, tie_break).ok_or(AutoSbError::EmptyObservations)?,
    };
    let mut classes: BTreeSet<&str> = BTreeSet::new();
    for o in obs {
        if let Some(c) = &o.left_class {
            classes.insert(c.as_str());
        }
        if let Some(c) = &o.right_class {
            classes.insert(c.as_str());
        }
) -> Result<(f64, Basis), RefusalReason> {
    let pick = |m: &SideMedians| match side {
        Side::Lsb => m.lsb,
        Side::Rsb => m.rsb,
    };
    match mode {
        Mode::Median => Ok((pick(&pool.global), Basis::Median)),
        Mode::Class => match class {
            None => Ok((pick(&pool.global), Basis::MedianFallback)),
            Some(c) if c.is_empty() => Err(RefusalReason::EmptyClassId { side }),
            Some(c) => match pool.per_class.get(c) {
                Some(m) => Ok((pick(m), Basis::Class(c.clone()))),
                None => Err(RefusalReason::ClassNotInPool { side, class: c.clone() }),
            },
        },
    }
}

/// Apply AUTO-SB targets to the solved glyphs. Output order = input order.
/// The class table is consulted only in Class mode; a glyph absent from the
/// table is class-less on both sides (global median fallback). Table rows for
/// glyphs not in `glyphs` are ignored.
pub fn apply(
    glyphs: &[SolvedGlyph],
    class_table: &BTreeMap<String, ClassAssignment>,
    pool: &PoolMedians,
    cfg: &AutoSbConfig,
) -> Result<Vec<GlyphOutcome>, AutoSbError> {
    if !cfg.offset_lsb.is_finite() {
        return Err(AutoSbError::NonFiniteOffset { field: "offset_lsb" });
    }
    if !cfg.offset_rsb.is_finite() {
        return Err(AutoSbError::NonFiniteOffset { field: "offset_rsb" });
    }
    if !pool.global.lsb.is_finite() {
        return Err(AutoSbError::NonFiniteGlobalMedian { field: "lsb" });
    }
    if !pool.global.rsb.is_finite() {
        return Err(AutoSbError::NonFiniteGlobalMedian { field: "rsb" });
    }
    for (c, m) in &pool.per_class {
