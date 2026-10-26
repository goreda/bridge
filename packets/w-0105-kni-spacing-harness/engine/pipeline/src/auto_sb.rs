//! AUTO-SB: pure side-bearing target module (no I/O, no globals, no clocks).
//!
//! Input: solved glyphs (glyph_id, lsb, rsb, advance), a class table already
//! loaded by the caller (glyph_id -> left_class / right_class), pool medians
//! (global + per class), explicit user offsets and an explicit tie-break.
//! The table load, the pool load, the CLI flags and the receipt writing all
//! live outside this module.
//!
//! Modes:
//!   Median: target side-bearing = pooled global median + user offset.
//!   Class:  target = per-class median of the glyph side's class + user offset;
//!           a side without a class falls back to the global median (basis
//!           `median_fallback`). A side whose class is named but absent from
//!           the pool is a typed refusal, never a silent fallback.
//!
//! lsb uses the left class and the lsb medians; rsb uses the right class and
//! the rsb medians. User offsets are two separate fields (DECISION-user-offset);
//! they are added to the target and never alias lsb_add / rsb_add.
//!
//! INVARIANT (frame geometry): for every applied glyph
//! `d_advance == d_lsb + d_rsb` bit-exactly in f64. `d_advance` is DEFINED as
//! the f64 sum `d_lsb + d_rsb`, `new_advance = advance + d_advance`, and
//! `check_invariant` re-verifies both relations bitwise.
//!
//! No `Default` exists for the config or for `TieBreak`: the tie-break must be
//! chosen explicitly by the caller (no hidden default).
//!
//! TAHMIN (unruled assumption, one place, trivially swappable): the held spec
//! says "--tie-break <A|B>" for "ties in median of even n" but the held files
//! do not define A and B. Here A = mean of the two middle values (identical to
//! the engine's existing `median_pure`), B = the lower of the two middle
//! values. Odd n has no tie and both give the middle value.

use std::collections::{BTreeMap, BTreeSet};

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

#[derive(Clone, Debug, PartialEq)]
pub struct PoolMedians {
    pub global: SideMedians,
    pub per_class: BTreeMap<String, SideMedians>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SolvedGlyph {
    pub glyph_id: String,
    pub lsb: f64,
    pub rsb: f64,
    pub advance: f64,
}

/// One class-table row. `None` = class-less side.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClassAssignment {
    pub left_class: Option<String>,
    pub right_class: Option<String>,
}

/// Explicit configuration. No Default impl on purpose.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AutoSbConfig {
    pub mode: Mode,
    pub offset_lsb: f64,
    pub offset_rsb: f64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Basis {
    /// Median mode: pooled global median.
    Median,
    /// Class mode: per-class median of this class.
    Class(String),
    /// Class mode, side has no class: global median.
    MedianFallback,
}

impl Basis {
    pub fn token(&self) -> String {
        match self {
            Basis::Median => "median".to_string(),
            Basis::Class(c) => format!("class:{c}"),
            Basis::MedianFallback => "median_fallback".to_string(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Lsb,
    Rsb,
}

impl Side {
    fn token(self) -> &'static str {
        match self {
            Side::Lsb => "lsb",
            Side::Rsb => "rsb",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct AppliedRow {
    pub glyph_id: String,
    pub mode: Mode,
    pub old_lsb: f64,
    pub old_rsb: f64,
    pub old_advance: f64,
    pub new_lsb: f64,
    pub new_rsb: f64,
    pub new_advance: f64,
    pub d_lsb: f64,
    pub d_rsb: f64,
    pub d_advance: f64,
    pub lsb_basis: Basis,
    pub rsb_basis: Basis,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RefusalReason {
    NonFiniteInput,
    NonFiniteResult,
    EmptyClassId { side: Side },
    ClassNotInPool { side: Side, class: String },
}

impl RefusalReason {
    pub fn token(&self) -> String {
        match self {
            RefusalReason::NonFiniteInput => "NonFiniteInput".to_string(),
            RefusalReason::NonFiniteResult => "NonFiniteResult".to_string(),
            RefusalReason::EmptyClassId { side } => format!("EmptyClassId:{}", side.token()),
            RefusalReason::ClassNotInPool { side, class } => {
                format!("ClassNotInPool:{}:{}", side.token(), class)
            }
        }
    }
}

/// Per-glyph result. A refused glyph is untouched by the caller (no delta);
/// the refusal is a typed row, never a silent skip.
#[derive(Clone, Debug, PartialEq)]
pub enum GlyphOutcome {
    Applied(AppliedRow),
    Refused { glyph_id: String, reason: RefusalReason },
}

/// Whole-run errors: nothing is applied.
#[derive(Clone, Debug, PartialEq)]
pub enum AutoSbError {
    NonFiniteOffset { field: &'static str },
    NonFiniteGlobalMedian { field: &'static str },
    NonFinitePoolClassMedian { class: String, field: &'static str },
    DuplicateGlyphId(String),
    EmptyObservations,
    NonFiniteObservation { index: usize },
}

impl AutoSbError {
    pub fn token(&self) -> String {
        match self {
            AutoSbError::NonFiniteOffset { field } => format!("NonFiniteOffset:{field}"),
            AutoSbError::NonFiniteGlobalMedian { field } => format!("NonFiniteGlobalMedian:{field}"),
            AutoSbError::NonFinitePoolClassMedian { class, field } => {
                format!("NonFinitePoolClassMedian:{class}:{field}")
            }
            AutoSbError::DuplicateGlyphId(g) => format!("DuplicateGlyphId:{g}"),
            AutoSbError::EmptyObservations => "EmptyObservations".to_string(),
            AutoSbError::NonFiniteObservation { index } => format!("NonFiniteObservation:{index}"),
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
    }
    let mut per_class = BTreeMap::new();
    for c in classes {
        let l: Vec<f64> = obs
            .iter()
            .filter(|o| o.left_class.as_deref() == Some(c))
            .map(|o| o.lsb)
            .collect();
        let r: Vec<f64> = obs
            .iter()
            .filter(|o| o.right_class.as_deref() == Some(c))
            .map(|o| o.rsb)
            .collect();
        per_class.insert(
            c.to_string(),
            SideMedians {
                lsb: median_with_tie_break(&l, tie_break).unwrap_or(global.lsb),
                rsb: median_with_tie_break(&r, tie_break).unwrap_or(global.rsb),
            },
        );
    }
    Ok(PoolMedians { global, per_class })
}

fn resolve_side(
    mode: Mode,
    side: Side,
    class: Option<&String>,
    pool: &PoolMedians,
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
        if !m.lsb.is_finite() {
            return Err(AutoSbError::NonFinitePoolClassMedian { class: c.clone(), field: "lsb" });
        }
        if !m.rsb.is_finite() {
            return Err(AutoSbError::NonFinitePoolClassMedian { class: c.clone(), field: "rsb" });
        }
    }
    let mut seen: BTreeSet<&str> = BTreeSet::new();
    for g in glyphs {
        if !seen.insert(g.glyph_id.as_str()) {
            return Err(AutoSbError::DuplicateGlyphId(g.glyph_id.clone()));
        }
    }
    let mut out = Vec::with_capacity(glyphs.len());
    for g in glyphs {
        let refuse = |reason: RefusalReason| GlyphOutcome::Refused {
            glyph_id: g.glyph_id.clone(),
            reason,
        };
        if !g.lsb.is_finite() || !g.rsb.is_finite() || !g.advance.is_finite() {
            out.push(refuse(RefusalReason::NonFiniteInput));
            continue;
        }
        let (lc, rc) = match class_table.get(&g.glyph_id) {
            Some(a) => (a.left_class.as_ref(), a.right_class.as_ref()),
            None => (None, None),
        };
        let (base_l, lb) = match resolve_side(cfg.mode, Side::Lsb, lc, pool) {
            Ok(v) => v,
            Err(r) => {
                out.push(refuse(r));
                continue;
            }
        };
        let (base_r, rb) = match resolve_side(cfg.mode, Side::Rsb, rc, pool) {
            Ok(v) => v,
            Err(r) => {
                out.push(refuse(r));
                continue;
            }
        };
        let new_lsb = base_l + cfg.offset_lsb;
        let new_rsb = base_r + cfg.offset_rsb;
        let d_lsb = new_lsb - g.lsb;
        let d_rsb = new_rsb - g.rsb;
        let d_advance = d_lsb + d_rsb;
        let new_advance = g.advance + d_advance;
        if ![new_lsb, new_rsb, d_lsb, d_rsb, d_advance, new_advance]
            .iter()
            .all(|v| v.is_finite())
        {
            out.push(refuse(RefusalReason::NonFiniteResult));
            continue;
        }
        out.push(GlyphOutcome::Applied(AppliedRow {
            glyph_id: g.glyph_id.clone(),
            mode: cfg.mode,
            old_lsb: g.lsb,
            old_rsb: g.rsb,
            old_advance: g.advance,
            new_lsb,
            new_rsb,
            new_advance,
            d_lsb,
            d_rsb,
            d_advance,
            lsb_basis: lb,
            rsb_basis: rb,
        }));
    }
    Ok(out)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InvariantReport {
    pub checked: usize,
    pub refused: usize,
    /// glyph ids whose rows violate either relation (bitwise).
    pub violations: Vec<String>,
}

impl InvariantReport {
    pub fn holds(&self) -> bool {
        self.violations.is_empty()
    }
}

/// Re-verify, bitwise, over all applied rows:
///   d_advance == d_lsb + d_rsb
///   new_advance == old_advance + d_advance
///   d_lsb == new_lsb - old_lsb, d_rsb == new_rsb - old_rsb
pub fn check_invariant(outcomes: &[GlyphOutcome]) -> InvariantReport {
    let mut checked = 0;
    let mut refused = 0;
    let mut violations = Vec::new();
    for o in outcomes {
        match o {
            GlyphOutcome::Refused { .. } => refused += 1,
            GlyphOutcome::Applied(r) => {
                checked += 1;
                let ok = r.d_advance.to_bits() == (r.d_lsb + r.d_rsb).to_bits()
                    && r.new_advance.to_bits() == (r.old_advance + r.d_advance).to_bits()
                    && r.d_lsb.to_bits() == (r.new_lsb - r.old_lsb).to_bits()
                    && r.d_rsb.to_bits() == (r.new_rsb - r.old_rsb).to_bits();
                if !ok {
                    violations.push(r.glyph_id.clone());
                }
            }
        }
    }
    InvariantReport { checked, refused, violations }
}

/// Receipt TSV `auto_sb_applied`: glyph, dLSB, dRSB, dAdvance, basis.
/// Floats use Rust shortest round-trip formatting. Basis cell: `lsb=<b>;rsb=<b>`.
pub fn applied_tsv(outcomes: &[GlyphOutcome]) -> String {
    let mut s = String::from("glyph\tdLSB\tdRSB\tdAdvance\tbasis\n");
    for o in outcomes {
        if let GlyphOutcome::Applied(r) = o {
            s.push_str(&format!(
                "{}\t{}\t{}\t{}\tlsb={};rsb={}\n",
                r.glyph_id,
                r.d_lsb,
                r.d_rsb,
                r.d_advance,
                r.lsb_basis.token(),
                r.rsb_basis.token()
            ));
        }
    }
    s
}

/// Typed refusal rows: glyph, reason. Header always present.
pub fn refused_tsv(outcomes: &[GlyphOutcome]) -> String {
    let mut s = String::from("glyph\treason\n");
    for o in outcomes {
        if let GlyphOutcome::Refused { glyph_id, reason } = o {
            s.push_str(&format!("{}\t{}\n", glyph_id, reason.token()));
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn g(id: &str, lsb: f64, rsb: f64, adv: f64) -> SolvedGlyph {
        SolvedGlyph { glyph_id: id.to_string(), lsb, rsb, advance: adv }
    }
    fn ca(l: Option<&str>, r: Option<&str>) -> ClassAssignment {
        ClassAssignment { left_class: l.map(String::from), right_class: r.map(String::from) }
    }
    fn pool() -> PoolMedians {
        let mut per_class = BTreeMap::new();
        per_class.insert("round".to_string(), SideMedians { lsb: 20.0, rsb: 22.0 });
        per_class.insert("flat".to_string(), SideMedians { lsb: 40.0, rsb: 44.0 });
        PoolMedians { global: SideMedians { lsb: 30.0, rsb: 33.0 }, per_class }
    }
    fn cfg(mode: Mode, ol: f64, or: f64) -> AutoSbConfig {
        AutoSbConfig { mode, offset_lsb: ol, offset_rsb: or }
    }
    fn applied(o: &GlyphOutcome) -> &AppliedRow {
        match o {
            GlyphOutcome::Applied(r) => r,
            other => panic!("expected Applied, got {other:?}"),
        }
    }

    #[test]
    fn median_odd_and_even_with_both_tie_breaks() {
        assert_eq!(median_with_tie_break(&[3.0, 1.0, 2.0], TieBreak::A), Some(2.0));
        assert_eq!(median_with_tie_break(&[3.0, 1.0, 2.0], TieBreak::B), Some(2.0));
        assert_eq!(median_with_tie_break(&[4.0, 1.0, 3.0, 2.0], TieBreak::A), Some(2.5));
        assert_eq!(median_with_tie_break(&[4.0, 1.0, 3.0, 2.0], TieBreak::B), Some(2.0));
        assert_eq!(median_with_tie_break(&[-4.0, -1.0], TieBreak::A), Some(-2.5));
        assert_eq!(median_with_tie_break(&[-4.0, -1.0], TieBreak::B), Some(-4.0));
    }

    #[test]
    fn median_empty_or_nonfinite_is_none_never_zero() {
        assert_eq!(median_with_tie_break(&[], TieBreak::A), None);
        assert_eq!(median_with_tie_break(&[1.0, f64::NAN], TieBreak::B), None);
        assert_eq!(median_with_tie_break(&[f64::INFINITY], TieBreak::A), None);
    }

    #[test]
    fn median_mode_sets_global_target_for_every_glyph_and_ignores_classes() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0), g("b", 50.0, 60.0, 600.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), Some("flat")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Median, 0.0, 0.0)).unwrap();
        let a = applied(&out[0]);
        assert_eq!((a.new_lsb, a.new_rsb), (30.0, 33.0));
        assert_eq!((a.d_lsb, a.d_rsb, a.d_advance), (20.0, 21.0, 41.0));
        assert_eq!(a.new_advance, 541.0);
        assert_eq!((a.lsb_basis.clone(), a.rsb_basis.clone()), (Basis::Median, Basis::Median));
        let b = applied(&out[1]);
        assert_eq!((b.d_lsb, b.d_rsb, b.d_advance), (-20.0, -27.0, -47.0));
        assert_eq!(b.new_advance, 553.0);
    }

    #[test]
    fn class_mode_uses_side_specific_class_and_side_specific_medians() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), Some("flat")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 0.0, 0.0)).unwrap();
        let a = applied(&out[0]);
        assert_eq!((a.new_lsb, a.new_rsb), (20.0, 44.0)); // round.lsb, flat.rsb
        assert_eq!(a.lsb_basis, Basis::Class("round".to_string()));
        assert_eq!(a.rsb_basis, Basis::Class("flat".to_string()));
        assert_eq!(a.d_advance, (20.0 - 10.0) + (44.0 - 12.0));
    }

    #[test]
    fn class_less_side_falls_back_to_global_median_per_side() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0), g("nt", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), None)); // right class-less
        // "nt" has no table row at all: class-less on both sides
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 0.0, 0.0)).unwrap();
        let a = applied(&out[0]);
        assert_eq!((a.new_lsb, a.new_rsb), (20.0, 33.0));
        assert_eq!(a.lsb_basis, Basis::Class("round".to_string()));
        assert_eq!(a.rsb_basis, Basis::MedianFallback);
        let n = applied(&out[1]);
        assert_eq!((n.new_lsb, n.new_rsb), (30.0, 33.0));
        assert_eq!((n.lsb_basis.clone(), n.rsb_basis.clone()), (Basis::MedianFallback, Basis::MedianFallback));
    }

    #[test]
    fn named_class_missing_from_pool_is_typed_refusal_not_silent_fallback() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0), g("b", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("novel"), None));
        table.insert("b".to_string(), ca(None, Some("")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 0.0, 0.0)).unwrap();
        assert_eq!(
            out[0],
            GlyphOutcome::Refused {
                glyph_id: "a".to_string(),
                reason: RefusalReason::ClassNotInPool { side: Side::Lsb, class: "novel".to_string() }
            }
        );
        assert_eq!(
            out[1],
            GlyphOutcome::Refused {
                glyph_id: "b".to_string(),
                reason: RefusalReason::EmptyClassId { side: Side::Rsb }
            }
        );
        let t = refused_tsv(&out);
        assert_eq!(t, "glyph\treason\na\tClassNotInPool:lsb:novel\nb\tEmptyClassId:rsb\n");
        let rep = check_invariant(&out);
        assert_eq!((rep.checked, rep.refused), (0, 2));
    }

    #[test]
    fn median_mode_does_not_refuse_unknown_classes() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("novel"), Some("")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Median, 0.0, 0.0)).unwrap();
        assert!(matches!(out[0], GlyphOutcome::Applied(_)));
    }

    #[test]
    fn user_offsets_are_separate_fields_added_to_the_target() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), Some("flat")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 5.0, -3.0)).unwrap();
        let a = applied(&out[0]);
        assert_eq!((a.new_lsb, a.new_rsb), (25.0, 41.0));
        let out2 = apply(&glyphs, &table, &pool(), &cfg(Mode::Median, 1.5, 0.0)).unwrap();
        let b = applied(&out2[0]);
        assert_eq!((b.new_lsb, b.new_rsb), (31.5, 33.0));
        // zero offset on one side leaves that side at the plain target
        let out3 = apply(&glyphs, &table, &pool(), &cfg(Mode::Median, 0.0, 7.0)).unwrap();
        assert_eq!(applied(&out3[0]).new_lsb, 30.0);
        assert_eq!(applied(&out3[0]).new_rsb, 40.0);
    }

    #[test]
    fn invariant_is_bit_exact_for_awkward_floats() {
        let glyphs = vec![
            g("x", 0.1, 0.2, 333.333),
            g("y", -17.3, 1e-9, 1e6 + 0.7),
            g("z", 123456.789, -0.000123, 0.3),
        ];
        let pool = PoolMedians {
            global: SideMedians { lsb: 0.1 + 0.2, rsb: 1.0 / 3.0 },
            per_class: BTreeMap::new(),
        };
        let table = BTreeMap::new();
        let out = apply(&glyphs, &table, &pool, &cfg(Mode::Median, 0.7, -0.1)).unwrap();
        let rep = check_invariant(&out);
        assert_eq!(rep.checked, 3);
        assert!(rep.holds(), "{rep:?}");
        for o in &out {
            let r = applied(o);
            assert_eq!(r.d_advance.to_bits(), (r.d_lsb + r.d_rsb).to_bits());
        }
    }

    #[test]
    fn invariant_holds_over_a_deterministic_pseudo_random_population() {
        let mut s: u64 = 0x9E3779B97F4A7C15;
        let mut next = || {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            ((s >> 11) as f64) / ((1u64 << 53) as f64)
        };
        let mut glyphs = Vec::new();
        for i in 0..2000 {
            glyphs.push(g(&format!("g{i}"), next() * 400.0 - 100.0, next() * 400.0 - 100.0, next() * 1500.0));
        }
        let pool = PoolMedians {
            global: SideMedians { lsb: next() * 80.0, rsb: next() * 80.0 },
            per_class: BTreeMap::new(),
        };
        let out = apply(&glyphs, &BTreeMap::new(), &pool, &cfg(Mode::Median, next() * 10.0, next() * -10.0)).unwrap();
        let rep = check_invariant(&out);
        assert_eq!((rep.checked, rep.refused), (2000, 0));
        assert!(rep.holds());
    }

    #[test]
    fn check_invariant_detects_a_tampered_row() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0)];
        let mut out = apply(&glyphs, &BTreeMap::new(), &pool(), &cfg(Mode::Median, 0.0, 0.0)).unwrap();
        if let GlyphOutcome::Applied(r) = &mut out[0] {
            r.d_advance += 1e-9;
        }
        let rep = check_invariant(&out);
        assert_eq!(rep.violations, vec!["a".to_string()]);
        assert!(!rep.holds());
    }

    #[test]
    fn output_order_matches_input_and_unlisted_table_rows_are_ignored() {
        let glyphs = vec![g("z", 1.0, 1.0, 100.0), g("a", 2.0, 2.0, 100.0), g("m", 3.0, 3.0, 100.0)];
        let mut table = BTreeMap::new();
        table.insert("not_in_glyphs".to_string(), ca(Some("novel"), Some("novel")));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 0.0, 0.0)).unwrap();
        let ids: Vec<&str> = out.iter().map(|o| applied(o).glyph_id.as_str()).collect();
        assert_eq!(ids, vec!["z", "a", "m"]);
    }

    #[test]
    fn whole_run_errors_are_typed_and_apply_nothing() {
        let glyphs = vec![g("a", 1.0, 1.0, 100.0)];
        let t = BTreeMap::new();
        assert_eq!(
            apply(&glyphs, &t, &pool(), &cfg(Mode::Median, f64::NAN, 0.0)).unwrap_err(),
            AutoSbError::NonFiniteOffset { field: "offset_lsb" }
        );
        assert_eq!(
            apply(&glyphs, &t, &pool(), &cfg(Mode::Median, 0.0, f64::INFINITY)).unwrap_err(),
            AutoSbError::NonFiniteOffset { field: "offset_rsb" }
        );
        let mut bad = pool();
        bad.global.rsb = f64::NAN;
        assert_eq!(
            apply(&glyphs, &t, &bad, &cfg(Mode::Median, 0.0, 0.0)).unwrap_err(),
            AutoSbError::NonFiniteGlobalMedian { field: "rsb" }
        );
        let mut bad2 = pool();
        bad2.per_class.insert("x".to_string(), SideMedians { lsb: f64::NAN, rsb: 1.0 });
        assert_eq!(
            apply(&glyphs, &t, &bad2, &cfg(Mode::Median, 0.0, 0.0)).unwrap_err(),
            AutoSbError::NonFinitePoolClassMedian { class: "x".to_string(), field: "lsb" }
        );
        let dup = vec![g("a", 1.0, 1.0, 100.0), g("a", 2.0, 2.0, 100.0)];
        assert_eq!(
            apply(&dup, &t, &pool(), &cfg(Mode::Median, 0.0, 0.0)).unwrap_err(),
            AutoSbError::DuplicateGlyphId("a".to_string())
        );
    }

    #[test]
    fn nonfinite_glyph_input_is_a_typed_refusal_and_others_still_apply() {
        let glyphs = vec![g("bad", f64::NAN, 1.0, 100.0), g("ok", 1.0, 1.0, 100.0)];
        let out = apply(&glyphs, &BTreeMap::new(), &pool(), &cfg(Mode::Median, 0.0, 0.0)).unwrap();
        assert_eq!(
            out[0],
            GlyphOutcome::Refused { glyph_id: "bad".to_string(), reason: RefusalReason::NonFiniteInput }
        );
        assert!(matches!(out[1], GlyphOutcome::Applied(_)));
    }

    #[test]
    fn overflowing_result_is_a_typed_refusal() {
        let glyphs = vec![g("big", 0.0, 0.0, f64::MAX)];
        let p = PoolMedians { global: SideMedians { lsb: f64::MAX, rsb: f64::MAX }, per_class: BTreeMap::new() };
        let out = apply(&glyphs, &BTreeMap::new(), &p, &cfg(Mode::Median, 0.0, 0.0)).unwrap();
        assert_eq!(
            out[0],
            GlyphOutcome::Refused { glyph_id: "big".to_string(), reason: RefusalReason::NonFiniteResult }
        );
    }

    #[test]
    fn build_pool_medians_global_and_per_class_with_tie_break() {
        let obs = vec![
            PoolObservation { left_class: Some("r".into()), right_class: Some("f".into()), lsb: 10.0, rsb: 100.0 },
            PoolObservation { left_class: Some("r".into()), right_class: None, lsb: 20.0, rsb: 200.0 },
            PoolObservation { left_class: Some("f".into()), right_class: Some("f".into()), lsb: 50.0, rsb: 300.0 },
            PoolObservation { left_class: None, right_class: None, lsb: 40.0, rsb: 400.0 },
        ];
        let a = build_pool_medians(&obs, TieBreak::A).unwrap();
        assert_eq!(a.global, SideMedians { lsb: 30.0, rsb: 250.0 });
        assert_eq!(a.per_class["r"].lsb, 15.0); // lsb: 10,20 -> mean
        assert_eq!(a.per_class["f"].rsb, 200.0); // rsb f: 100,300 -> mean
        assert_eq!(a.per_class["f"].lsb, 50.0);
        // class r has no right-side observations: takes the global rsb value
        assert_eq!(a.per_class["r"].rsb, 250.0);
        let b = build_pool_medians(&obs, TieBreak::B).unwrap();
        assert_eq!(b.global, SideMedians { lsb: 20.0, rsb: 200.0 });
        assert_eq!(b.per_class["r"].lsb, 10.0);
        assert_eq!(b.per_class["f"].rsb, 100.0);
    }

    #[test]
    fn build_pool_medians_errors_are_typed() {
        assert_eq!(build_pool_medians(&[], TieBreak::A).unwrap_err(), AutoSbError::EmptyObservations);
        let obs = vec![
            PoolObservation { left_class: None, right_class: None, lsb: 1.0, rsb: 1.0 },
            PoolObservation { left_class: None, right_class: None, lsb: f64::NAN, rsb: 1.0 },
        ];
        assert_eq!(
            build_pool_medians(&obs, TieBreak::A).unwrap_err(),
            AutoSbError::NonFiniteObservation { index: 1 }
        );
    }

    #[test]
    fn applied_tsv_has_spec_columns_and_basis_tokens() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0), g("b", 10.0, 12.0, 500.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), None));
        let out = apply(&glyphs, &table, &pool(), &cfg(Mode::Class, 0.0, 0.0)).unwrap();
        let t = applied_tsv(&out);
        assert_eq!(
            t,
            "glyph\tdLSB\tdRSB\tdAdvance\tbasis\n\
             a\t10\t21\t31\tlsb=class:round;rsb=median_fallback\n\
             b\t20\t21\t41\tlsb=median_fallback;rsb=median_fallback\n"
        );
    }

    #[test]
    fn same_inputs_give_identical_outputs() {
        let glyphs = vec![g("a", 10.0, 12.0, 500.0), g("b", -3.0, 4.0, 700.0)];
        let mut table = BTreeMap::new();
        table.insert("a".to_string(), ca(Some("round"), Some("flat")));
        let c = cfg(Mode::Class, 1.25, -0.5);
        assert_eq!(apply(&glyphs, &table, &pool(), &c), apply(&glyphs, &table, &pool(), &c));
    }
}
