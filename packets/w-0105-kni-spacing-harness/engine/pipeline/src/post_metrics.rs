//! POST-METRICS LSB/RSB (engine/pipeline/src/post_metrics.rs). Source + unit tests; UNRUN on any real pipeline input.
//!
//! Owner contract: after spacing and kerning are finished, every in-scope glyph gets a uniform LSB addition and a
//! uniform RSB addition (separate values, DeclaredOutputUnits = 1000 UPM output units, independent of the scale K).
//! In-scope glyph: outline x += LSB (every point, control points included), advance += LSB + RSB, hmtx lsb := new xMin.
//! GPOS is never read or written here.
//!
//! Frame: the hook sits right before `prepare_generated`, which translates each outline so its integer ink xMin equals
//! the metrics-row `lsb` and rounds the advance. So the step edits ONLY the metrics rows (lsb+=L, rsb+=R, advance+=L+R).
//! `verify_final_frame` then proves on the prepared result, against a baseline prepare of the original rows: every point
//! (start, line ends, cubic controls) moved by exactly (+L, 0) for applied glyphs and not at all for excluded ones,
//! advance/hmtx deltas, and for EVERY ordered glyph pair the facing gap change (advance delta + origin shift delta) is >= 0
//! (no pair can lose clearance, so no new collision). The post-pass runs only from an approved-base token and carries no physical overlap guard;
//! this file does not re-solve anything.
//!
//! 0/0 => hook skips everything (byte-identical). Offsets: finite, integral, MIN_OFFSET <= v <= MAX_OFFSET, ANY sign
//! (owner directive 2026-10-17: negative offsets are legitimate; the nonnegative-only refusal was an engine limitation).
//! L < 0 translates the ink left (geometry translate), R < 0 shrinks the advance (advance adjustment); the ink shape
//! (translation aside) is byte/geometry identical. No clamp, no absolute value, no rounding of the declared value.
//! A pass with a negative component is allowed to shrink facing gaps BY DECLARATION: the gap check then MEASURES the
//! signed deltas (receipt gap_monotonicity=NOT_CLAIMED_SIGNED + gap_measurement=ANALYTIC_SIGNED) instead of proving
//! monotonicity (ANALYTIC_NONDECREASING, unchanged for nonnegative runs).
//! Types: SignedSideBearingOffset / GlyphClass / ScopePolicy are K2's kni_core::offset_scope (single type/domain, no copy here).
//! Class binding: explicit inventory + the pinned Unicode 17.0.0 General_Category M* table (unicode_marks.rs, source sha in file).
//! Mark coverage claim is limited to the Unicode Mark property; private-use/unassigned marks must be declared explicitly.
use kni_core::generated_native::prepare_generated;
use kni_core::offset_scope::{GlyphClass, OffsetError, ScopePolicy, SignedSideBearingOffset};
use kni_core::scale_context::{DimParam, Dimension};
use crate::unicode_marks;
use kni_core::ink_bounds::integer_outward_bounds;
use kni_core::native_font::NativeFontInput;
use kni_core::reference_slice::{DrawnGlyph, Point, Span};
use std::collections::{BTreeMap, BTreeSet};

/// Largest accepted single offset (i16 range of the output design space; a bigger one cannot be represented in glyf/hmtx).
pub const MAX_OFFSET: f64 = 32767.0;
/// Smallest accepted single offset (i16 minimum of the output design space; a more negative one cannot be represented).
pub const MIN_OFFSET: f64 = -32768.0;
/// prepare_generated rejects advances whose rounded value exceeds this.
pub const MAX_ADVANCE: i64 = 32767;

/// Row-level guard policy for `apply` / `bind_classes` (GUARD-SCAN P2: a single
/// bad row used to refuse the whole post_metrics stage; the ship path then
/// degraded to base bytes, main.rs emit_final_bundle_with). Default
/// `RefuseStage` keeps the incumbent whole-stage refusal: every existing call
/// is bit-identical. `ExcludeInvalidRows` lowers ONLY the per-row guards below
/// to typed exclusions: the row keeps its ORIGINAL metrics (never offset), a
/// typed exclusion row (`Decision::Excluded` with a stable reason code) goes
/// to the ledger, and the stage continues with the remaining rows.
///
/// NOT lowered (refusals in both modes, with the reason):
/// - EmptyGlyphId / DuplicateGlyphId: the ledger and `verify_final_frame` are
///   keyed by glyph identity (one ledger row per glyph, classes aligned by
///   index); a row without sound identity cannot be excluded without breaking
///   that invariant.
/// - UnknownScopeGlyph / ShapeMismatch / KerningLettersWithoutSelection:
///   scope/config defects, not row defects.
/// - bind_classes structural refusals (NotdefNotFirst, DuplicateNotdef,
///   SpaceNotInFont, mark inventory refusals, MappingGlyphOutOfRange): font
///   and cmap structure, not a metrics row.
/// Note: the noop-offset early return precedes exclusion in both modes (with
/// no offset there is nothing to exclude from; the ledger stays empty).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum RowPolicy { #[default] RefuseStage, ExcludeInvalidRows }

/// One glyph whose class could not be bound under `RowPolicy::ExcludeInvalidRows`.
/// `reason` is a stable ledger vocabulary string, reused as the apply-ledger
/// exclusion reason for that glyph.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BindExclusion { pub glyph_id: String, pub reason: &'static str }

#[derive(Clone, Debug, PartialEq)]
pub enum PostMetricsError {
    /// K2 offset_scope constructor refusal (wrong dimension, fractional/non-finite, NonFiniteSum), pass-through.
    Offset(OffsetError),
    /// single representable-range refusal of the config constructor (MIN_OFFSET <= value <= MAX_OFFSET).
    OffsetOutOfRange { name: &'static str },
    EmptyGlyphId,
    DuplicateGlyphId(String),
    InvalidMetric(String),
    UnknownScopeGlyph(String),
    NumericRange(String),
    /// glyph (other than .notdef) has no codepoint in the mapping: its class cannot be bound.
    MissingCodepoint(String),
    /// glyph is mapped from several codepoints whose declared classes disagree.
    AmbiguousClass(String),
    /// a font codepoint with Unicode General_Category M* (pinned table) is not in the declared mark inventory.
    UndeclaredMark { codepoint: u32 },
    /// a declared mark codepoint is absent from the font mapping.
    MarkNotInFont { codepoint: u32 },
    /// a declared mark codepoint has no Unicode M* property (declare private-use marks only through `private_marks`).
    DeclaredNonMark { codepoint: u32 },
    SpaceNotInFont { codepoint: u32 },
    NotdefNotFirst,
    DuplicateNotdef,
    MappingGlyphOutOfRange(u32),
    /// before/after/classes/ledger inputs disagree in shape (typed, no index panic).
    ShapeMismatch(&'static str),
    /// the pre-pass (base) guard did not approve the base font: no ApprovedBase token exists, nothing is applied.
    BaseGuardFailed(String),
    /// post_pass called with 0/0: there is no pass to run and no fallback output (callers keep the base route).
    ZeroOffsetPass,
    /// structural verification of the final bytes/font failed (typed; no OTF is published, offset is never silently reduced).
    Structural(String),
    Publish(String),
    /// the approved font could not be reproduced by re-preparing its own rows (the pass would not start from the approved bytes).
    RoundTripMismatch(String),
    /// token minted under a different RunConfig/scale context than the one the pass is run with.
    ContextMismatch(String),
    /// owner scope "kerning-applied letters" selected no glyph (never a silent no-op).
    EmptyKernedLetterSelection,
    /// ScopePolicy::KerningLetters without the explicit letters-and-kern allow-list: fail closed, nothing shifts.
    KerningLettersWithoutSelection,
    Verify { glyph: String, reason: String },
    Prepare(String),
}

pub type Offsets = SignedSideBearingOffset;
/// The ONE config constructor: values come from the run config (post_metrics.lsb_add / rsb_add, DeclaredOutputUnits, UPM 1000);
/// K2's signed constructor decides kind/finite/sum refusals, then the representable-range refusal
/// (MIN_OFFSET <= v <= MAX_OFFSET, any sign) is applied here once.
#[allow(dead_code)] // kept: the ONE config constructor for run-config offsets (per item doc); no call site in this binary
pub fn offsets_from_config(lsb_add: f64, rsb_add: f64) -> Result<Offsets, PostMetricsError> {
    let mk = |n: &str, v: f64| DimParam::new(n, v, Dimension::DeclaredOutputUnits, "run_config.post_metrics").map_err(|_| PostMetricsError::Offset(OffsetError::InvalidOffset { name: n.to_string() }));
    let o = SignedSideBearingOffset::from_params(&mk("lsb_add", lsb_add)?, &mk("rsb_add", rsb_add)?).map_err(PostMetricsError::Offset)?;
    if o.lsb() < MIN_OFFSET || o.lsb() > MAX_OFFSET { return Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" }); }
    if o.rsb() < MIN_OFFSET || o.rsb() > MAX_OFFSET { return Err(PostMetricsError::OffsetOutOfRange { name: "rsb_add" }); }
    Ok(o)
}
/// Representable-range recheck for ANY SignedSideBearingOffset (it can be built directly through K2's constructor,
/// bypassing offsets_from_config): finite, integral, MIN_OFFSET <= v <= MAX_OFFSET (any sign). Called at the entry of
/// apply and verify_final_frame.
pub fn check_range(o: &Offsets) -> Result<(), PostMetricsError> {
    for (v, name) in [(o.lsb(), "lsb_add"), (o.rsb(), "rsb_add")] {
        if !(v.is_finite() && v.fract() == 0.0) { return Err(PostMetricsError::Offset(OffsetError::InvalidOffset { name: name.to_string() })); }
        if v < MIN_OFFSET || v > MAX_OFFSET { return Err(PostMetricsError::OffsetOutOfRange { name }); }
    }
    Ok(())
}
/// Exact integer value of an already range-checked offset (typed error instead of a saturating cast).
fn lsb_i(o: &Offsets) -> Result<i64, PostMetricsError> { check_range(o)?; Ok(o.lsb() as i64) }
fn rsb_i(o: &Offsets) -> Result<i64, PostMetricsError> { check_range(o)?; Ok(o.rsb() as i64) }

/// Explicit scope (no Default): K2 class flags + optional allowlist + explicit exclusions + a recorded origin (printed in the
/// ledger so nothing is reported as config-bound when it is not).
#[derive(Clone, Debug)]
pub struct Scope { pub policy: ScopePolicy, pub allow: Option<BTreeSet<String>>, pub exclude: BTreeSet<String>, pub origin: String }
impl Scope {
    pub fn new(policy: ScopePolicy, origin: &str) -> Self { Scope { policy, allow: None, exclude: BTreeSet::new(), origin: origin.to_string() } }
    #[allow(dead_code)] // kept: base-glyphs-only scope constructor; no call site in this binary
    pub fn base_only(origin: &str) -> Self { Scope::new(ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false }, origin) }
}

/// What the hook consumes: validated offsets + scope (+ where they came from). Built from the immutable RunConfig snapshot
/// (`from_run_config`) or, while main.rs has no RunConfig wiring, `legacy_default` = 0/0 (a no-op; the scope is then irrelevant).
#[derive(Clone, Debug)]
pub struct PostStep { pub offset: Offsets, pub scope: Scope }
impl PostStep {
    pub fn from_run_config(rc: &crate::run_config::RunConfig) -> Result<Self, PostMetricsError> {
        let offset = rc.offset();
        check_range(&offset)?; // RunConfig accepts any finite offset; representability is refused here
        Ok(PostStep { offset, scope: Scope::new(rc.post_scope(), &format!("run_config.post_scope label={}", rc.post_scope_label())) })
    }
    pub fn legacy_default() -> Self {
        PostStep { offset: Offsets::none(), scope: Scope::new(ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false }, "legacy-default: main.rs has no RunConfig wiring; 0/0 no-op") }
    }
}

/// Explicit class inventory: mark codepoints + the space codepoint. `private_marks` = private-use/unassigned codepoints the
/// caller declares as marks (the Unicode table cannot know them).
#[derive(Clone, Debug, Default)]
pub struct DeclaredInventory { pub mark_codepoints: BTreeSet<u32>, pub private_marks: BTreeSet<u32>, pub space_codepoint: Option<u32> }
impl DeclaredInventory {
    /// Marks := every mapped codepoint with Unicode 17.0.0 General_Category Mn/Mc/Me (pinned table) + `private_marks`.
    pub fn from_pinned_unicode(mapping: &[(u32, u16)], private_marks: BTreeSet<u32>, space_codepoint: Option<u32>) -> Self {
        let mut m: BTreeSet<u32> = mapping.iter().map(|x| x.0).filter(|c| unicode_marks::is_mark(*c)).collect();
        m.extend(private_marks.iter().copied());
        DeclaredInventory { mark_codepoints: m, private_marks, space_codepoint }
    }
}

pub type Classes = Vec<(String, GlyphClass)>;

/// Bind a class to EVERY glyph from the declared inventory and the real cmap mapping.
/// - `.notdef` must be glyph 0 and unique (NotdefNotFirst / DuplicateNotdef); class Notdef, no codepoint needed.
/// - every other glyph needs >= 1 mapped codepoint (MissingCodepoint); glyph id out of range => typed.
/// - class per codepoint: declared space cp => Space, declared mark cp => Mark, else Base; conflicting classes on one glyph
///   => AmbiguousClass. Declared space cp must be mapped (SpaceNotInFont).
/// - mark checks (claim limited to the Unicode Mark property, pinned 17.0.0 table): a mapped M* codepoint not declared =>
///   UndeclaredMark; a declared mark that is not M* and not in `private_marks` => DeclaredNonMark; declared but unmapped =>
///   MarkNotInFont. Private-use/unassigned marks are covered only if declared.
pub fn bind_classes(order: &[String], mapping: &[(u32, u16)], inv: &DeclaredInventory, ligature_gids: &BTreeSet<u16>) -> Result<Classes, PostMetricsError> {
    bind_classes_with_policy(order, mapping, inv, RowPolicy::RefuseStage, ligature_gids).map(|(c, _)| c)
}
/// `bind_classes` under an explicit row policy. Under `ExcludeInvalidRows` a glyph
/// whose class cannot be bound (no codepoint, or conflicting classes across its
/// codepoints) is bound to a placeholder class (Base) so `classes` stays aligned
/// 1:1 with `order`, and is reported in the exclusion list; the caller passes that
/// list to `apply_with_row_policy`, which excludes the glyph from the offset.
/// Structural refusals (see RowPolicy docs) fire in both modes. Under
/// `RefuseStage` the returned exclusion list is always empty (strict delegate =
/// the incumbent function, bit-identical).
pub fn bind_classes_with_policy(order: &[String], mapping: &[(u32, u16)], inv: &DeclaredInventory, row_policy: RowPolicy, ligature_gids: &BTreeSet<u16>) -> Result<(Classes, Vec<BindExclusion>), PostMetricsError> {
    if order.first().map(|s| s.as_str()) != Some(".notdef") { return Err(PostMetricsError::NotdefNotFirst); }
    if order.iter().skip(1).any(|s| s == ".notdef") { return Err(PostMetricsError::DuplicateNotdef); }
    let mut ids = BTreeSet::new();
    for id in order { if id.is_empty() { return Err(PostMetricsError::EmptyGlyphId); } if !ids.insert(id.as_str()) { return Err(PostMetricsError::DuplicateGlyphId(id.clone())); } }
    let mapped: BTreeSet<u32> = mapping.iter().map(|m| m.0).collect();
    if let Some(c) = inv.space_codepoint { if !mapped.contains(&c) { return Err(PostMetricsError::SpaceNotInFont { codepoint: c }); } }
    for c in &inv.mark_codepoints {
        if !mapped.contains(c) { return Err(PostMetricsError::MarkNotInFont { codepoint: *c }); }
        if !unicode_marks::is_mark(*c) && !inv.private_marks.contains(c) { return Err(PostMetricsError::DeclaredNonMark { codepoint: *c }); }
    }
    for c in &mapped { if unicode_marks::is_mark(*c) && !inv.mark_codepoints.contains(c) { return Err(PostMetricsError::UndeclaredMark { codepoint: *c }); } }
    let mut per: BTreeMap<usize, BTreeSet<u8>> = BTreeMap::new();
    for (cp, gid) in mapping {
        let i = *gid as usize;
        if i >= order.len() { return Err(PostMetricsError::MappingGlyphOutOfRange(*cp)); }
        let k = if inv.space_codepoint == Some(*cp) { 1u8 } else if inv.mark_codepoints.contains(cp) { 2 } else { 0 };
        per.entry(i).or_default().insert(k);
    }
    let mut out = Vec::with_capacity(order.len());
    let mut excl: Vec<BindExclusion> = Vec::new();
    for (i, id) in order.iter().enumerate() {
        if i == 0 { out.push((id.clone(), GlyphClass::Notdef)); continue; }
        // Unmapped by design: a GSUB ligature target binds as Base (it shapes
        // text like a letter); any other unmapped glyph keeps the refusal.
        if per.get(&i).is_none() && ligature_gids.contains(&(i as u16)) { out.push((id.clone(), GlyphClass::Base)); continue; }
        let reason = match per.get(&i) {
            None => Some("class unbound: no codepoint"),
            Some(ks) if ks.len() != 1 => Some("class unbound: ambiguous class"),
            Some(ks) => { out.push((id.clone(), match *ks.iter().next().unwrap() { 1 => GlyphClass::Space, 2 => GlyphClass::Mark, _ => GlyphClass::Base })); None }
        };
        if let Some(r) = reason {
            if row_policy == RowPolicy::RefuseStage {
                return Err(if r == "class unbound: no codepoint" { PostMetricsError::MissingCodepoint(id.clone()) } else { PostMetricsError::AmbiguousClass(id.clone()) });
            }
            // placeholder binding keeps classes aligned; apply excludes the glyph
            out.push((id.clone(), GlyphClass::Base));
            excl.push(BindExclusion { glyph_id: id.clone(), reason: r });
        }
    }
    Ok((out, excl))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Decision { Applied, Excluded(&'static str) }
#[derive(Clone, Debug)]
pub struct LedgerRow { pub glyph_id: String, pub class: GlyphClass, pub decision: Decision }
#[derive(Clone, Debug, Default)]
pub struct Ledger { pub rows: Vec<LedgerRow>, pub scope_note: String }

/// TSV cell escape: backslash, tab, LF, CR and every other control char are escaped; the row structure cannot be forged.
pub fn tsv_escape(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => o.push_str("\\\\"), '\t' => o.push_str("\\t"), '\n' => o.push_str("\\n"), '\r' => o.push_str("\\r"),
            c if c.is_control() => o.push_str(&format!("\\u{{{:x}}}", c as u32)),
            c => o.push(c),
        }
    }
    o
}

impl Ledger {
    pub fn applied(&self) -> Vec<&str> { self.rows.iter().filter(|r| r.decision == Decision::Applied).map(|r| r.glyph_id.as_str()).collect() }
    pub fn tsv(&self, o: Offsets) -> String {
        let mut s = format!("# post_metrics\tlsb_add\t{}\trsb_add\t{}\tunits\tDeclaredOutputUnits(UPM1000)\n# scope\t{}\nglyph_id\tclass\tdecision\treason\n", o.lsb(), o.rsb(), tsv_escape(&self.scope_note));
        for r in &self.rows {
            let (d, why) = match &r.decision { Decision::Applied => ("applied", ""), Decision::Excluded(w) => ("excluded", *w) };
            s.push_str(&format!("{}\t{:?}\t{}\t{}\n", tsv_escape(&r.glyph_id), r.class, d, why));
        }
        s
    }
}

pub type Row = (String, f64, f64, f64); // glyph_id, lsb, rsb, advance (same tuple as prepare_generated)

/// Pure: returns NEW rows + ledger. 0/0 => identical rows, empty ledger. All arithmetic is on finite f64 integers bounded
/// by MAX_OFFSET; the result advance must stay <= MAX_ADVANCE (prepare_generated's range) or the step refuses (typed).
#[allow(dead_code)] // kept: strict RefuseStage entry, bit-identical delegate of apply_with_row_policy (per item doc); no call site in this binary
pub fn apply(rows: &[Row], classes: &[(String, GlyphClass)], off: Offsets, scope: &Scope) -> Result<(Vec<Row>, Ledger), PostMetricsError> {
    apply_with_row_policy(rows, classes, off, scope, RowPolicy::RefuseStage, &[])
}
/// `apply` under an explicit row policy (see RowPolicy). `bind_exclusions` carries
/// the output of `bind_classes_with_policy` under the same policy; a listed glyph
/// is excluded with its bind reason. Under `RefuseStage` this is the incumbent
/// `apply`, bit-identical (the strict delegate above calls exactly this).
pub fn apply_with_row_policy(rows: &[Row], classes: &[(String, GlyphClass)], off: Offsets, scope: &Scope, row_policy: RowPolicy, bind_exclusions: &[BindExclusion]) -> Result<(Vec<Row>, Ledger), PostMetricsError> {
    check_range(&off)?;
    let lenient = row_policy == RowPolicy::ExcludeInvalidRows;
    let mut seen = BTreeSet::new();
    for (id, l, r, a) in rows {
        if id.is_empty() { return Err(PostMetricsError::EmptyGlyphId); }
        if !seen.insert(id.as_str()) { return Err(PostMetricsError::DuplicateGlyphId(id.clone())); }
        if !lenient && !(l.is_finite() && r.is_finite() && a.is_finite() && *a >= 0.0) { return Err(PostMetricsError::InvalidMetric(id.clone())); }
    }
    for n in scope.allow.iter().flatten().chain(scope.exclude.iter()) {
        if !seen.contains(n.as_str()) { return Err(PostMetricsError::UnknownScopeGlyph(n.clone())); }
    }
    if off.is_noop() { return Ok((rows.to_vec(), Ledger::default())); }
    if scope.policy.selects_kerning_letters() && scope.allow.is_none() { return Err(PostMetricsError::KerningLettersWithoutSelection); }
    if classes.len() != rows.len() { return Err(PostMetricsError::ShapeMismatch("classes length != rows length")); }
    let mut out = Vec::with_capacity(rows.len());
    let mut ledger = Ledger { rows: Vec::new(), scope_note: format!("policy={:?} allow={:?} exclude={:?} origin={}", scope.policy, scope.allow, scope.exclude, scope.origin) };
    for row in rows {
        // bind-excluded glyphs (lenient bind_classes) are excluded with the bind reason
        if let Some(b) = bind_exclusions.iter().find(|b| b.glyph_id == row.0) {
            let class = classes.iter().find(|c| c.0 == row.0).map(|c| c.1).ok_or_else(|| PostMetricsError::MissingCodepoint(row.0.clone()))?;
            ledger.rows.push(LedgerRow { glyph_id: row.0.clone(), class, decision: Decision::Excluded(b.reason) });
            out.push(row.clone());
            continue;
        }
        if lenient && !(row.1.is_finite() && row.2.is_finite() && row.3.is_finite() && row.3 >= 0.0) {
            let class = classes.iter().find(|c| c.0 == row.0).map(|c| c.1).ok_or_else(|| PostMetricsError::MissingCodepoint(row.0.clone()))?;
            ledger.rows.push(LedgerRow { glyph_id: row.0.clone(), class, decision: Decision::Excluded("invalid metric") });
            out.push(row.clone());
            continue;
        }
        let class = classes.iter().find(|c| c.0 == row.0).map(|c| c.1).ok_or_else(|| PostMetricsError::MissingCodepoint(row.0.clone()))?;
        let why: Option<&'static str> = if scope.exclude.contains(&row.0) { Some("explicit exclusion") }
            else if scope.allow.as_ref().map_or(false, |a| !a.contains(&row.0)) { Some("not in allowlist") }
            else if !(scope.policy.includes(class) || (class == GlyphClass::Base && scope.policy.selects_kerning_letters())) {
                Some(match class { GlyphClass::Base => "base not in scope", GlyphClass::Space => "space is not propagated automatically",
                    GlyphClass::Notdef => ".notdef is not propagated automatically", GlyphClass::Mark => "mark is not propagated automatically" }) }
            else { None };
        match why {
            Some(w) => { ledger.rows.push(LedgerRow { glyph_id: row.0.clone(), class, decision: Decision::Excluded(w) }); out.push(row.clone()); }
            None => {
                let add = off.facing_gap_delta(); // |each| <= 32768 (constructor refusal): exact in f64
                // zero-advance marks stay zero-advance even under a negative add (a combining mark must not gain width)
                let adv = if class == GlyphClass::Mark && row.3 == 0.0 { row.3 } else { row.3 + add };
                let n = (row.0.clone(), row.1 + off.lsb(), row.2 + off.rsb(), adv);
                // Final-row bounds, CHECKED (never clamped, never absolute-valued): advance within 0..=MAX_ADVANCE
                // (the prepare range; a signed offset can underflow it below 0), lsb within the i16 design space
                // [MIN_OFFSET, MAX_OFFSET] (a negative lsb is representable), rsb not below i16::MIN (hhea min_rsb
                // is i16; the upper side is derived from geometry and caught by the final aggregate gate as before).
                if !(n.1.is_finite() && n.2.is_finite() && n.3.is_finite()) || n.3.round() > MAX_ADVANCE as f64 || n.3 < 0.0
                    || n.1 < MIN_OFFSET || n.1 > MAX_OFFSET || n.2 < MIN_OFFSET {
                    if lenient {
                        ledger.rows.push(LedgerRow { glyph_id: row.0.clone(), class, decision: Decision::Excluded("numeric range overflow") });
                        out.push(row.clone());
                        continue;
                    }
                    return Err(PostMetricsError::NumericRange(row.0.clone()));
                }
                ledger.rows.push(LedgerRow { glyph_id: row.0.clone(), class, decision: Decision::Applied });
                out.push(n);
            }
        }
    }
    Ok((out, ledger))
}

fn pts(g: &DrawnGlyph) -> Vec<Point> {
    let mut v = Vec::new();
    for r in &g.rings { v.push(r.start); for s in &r.spans { match s {
        Span::Line { end } => v.push(*end),
        Span::Cubic { control_one, control_two, end } => { v.push(*control_one); v.push(*control_two); v.push(*end); } } } }
    v
}

/// FINAL-FRAME verification on prepared fonts (`before` = prepare with original rows, `after` = with applied rows).
/// Every point incl. cubic controls: x' == x + dx, y' == y, ring/span structure identical (dx = LSB for applied, else 0).
/// advance/hmtx/bounds deltas, i16/advance ranges via checked arithmetic, cmap and order unchanged, and for every ordered
/// pair (a,b) the facing-gap delta (adv'_a - adv_a) + (dx_b - dx_a) >= 0. Any mismatch => Err.
pub fn verify_final_frame(before: &NativeFontInput, after: &NativeFontInput, off: Offsets, ledger: &Ledger,
                          classes: &[(String, GlyphClass)]) -> Result<(), PostMetricsError> {
    let bad = |g: &str, r: String| PostMetricsError::Verify { glyph: g.to_string(), reason: r };
    check_range(&off)?;
    let (l_i, r_i) = (lsb_i(&off)?, rsb_i(&off)?);
    // shape validation first: no index below can panic
    let n = before.glyphs.len();
    if after.glyphs.len() != n { return Err(PostMetricsError::ShapeMismatch("before/after glyph count differs")); }
    if before.left_side_bearings.len() != n || after.left_side_bearings.len() != n { return Err(PostMetricsError::ShapeMismatch("hmtx lsb count != glyph count")); }
    if classes.len() != n { return Err(PostMetricsError::ShapeMismatch("classes length != glyph count")); }
    let mut seen_names = BTreeSet::new();
    for (i, g) in before.glyphs.iter().enumerate() {
        if !seen_names.insert(g.name.as_str()) { return Err(PostMetricsError::DuplicateGlyphId(g.name.clone())); }
        if classes[i].0 != g.name { return Err(PostMetricsError::ShapeMismatch("classes order != glyph order")); }
    }
    let mut seen_led = BTreeSet::new();
    for r in &ledger.rows {
        if !seen_led.insert(r.glyph_id.as_str()) { return Err(PostMetricsError::DuplicateGlyphId(r.glyph_id.clone())); }
        match classes.iter().find(|c| c.0 == r.glyph_id) {
            None => return Err(PostMetricsError::UnknownScopeGlyph(r.glyph_id.clone())),
            Some(c) if c.1 != r.class => return Err(PostMetricsError::ShapeMismatch("ledger class != class binding")),
            _ => {}
        }
    }
    if !off.is_noop() && ledger.rows.len() != n { return Err(PostMetricsError::ShapeMismatch("ledger must cover every glyph")); }
    let applied: BTreeSet<&str> = ledger.applied().into_iter().collect();
    let mut dxs: Vec<(i64, i64)> = Vec::new(); // per glyph (dx, advance delta)
    for (i, (b, a)) in before.glyphs.iter().zip(after.glyphs.iter()).enumerate() {
        if b.name != a.name { return Err(bad(&b.name, "glyph order changed".into())); }
        let is_applied = !off.is_noop() && applied.contains(b.name.as_str());
        let mark0 = classes.iter().any(|c| c.0 == b.name && c.1 == GlyphClass::Mark) && b.advance == 0;
        let add = l_i.checked_add(r_i).ok_or_else(|| bad(&b.name, "offset sum overflow".into()))?;
        let d_adv = if is_applied && !mark0 { add } else { 0 };
        let want_adv = (b.advance as i64).checked_add(d_adv).ok_or_else(|| bad(&b.name, "advance overflow".into()))?;
        if want_adv > MAX_ADVANCE { return Err(bad(&b.name, format!("advance {want_adv} exceeds {MAX_ADVANCE}"))); }
        if want_adv < 0 { return Err(bad(&b.name, format!("advance {want_adv} below 0"))); }
        if a.advance as i64 != want_adv { return Err(bad(&b.name, format!("advance {} != expected {}", a.advance, want_adv))); }
        let dx = if is_applied { l_i } else { 0 };
        // every point, controls included
        if b.outline.rings.len() != a.outline.rings.len() { return Err(bad(&b.name, "ring count changed".into())); }
        for (rb, ra) in b.outline.rings.iter().zip(a.outline.rings.iter()) {
            if rb.spans.len() != ra.spans.len() { return Err(bad(&b.name, "span count changed".into())); }
            for (sb, sa) in rb.spans.iter().zip(ra.spans.iter()) {
                if std::mem::discriminant(sb) != std::mem::discriminant(sa) { return Err(bad(&b.name, "span kind changed".into())); }
            }
        }
        let (pb, pa) = (pts(&b.outline), pts(&a.outline));
        if pb.len() != pa.len() { return Err(bad(&b.name, "point count changed".into())); }
        for (k, (x, y)) in pb.iter().zip(pa.iter()).enumerate() {
            if y.x != x.x + dx as f64 || y.y != x.y { return Err(bad(&b.name, format!("point {k} ({},{}) -> ({},{}) != shift {dx}", x.x, x.y, y.x, y.y))); }
        }
        let bb = integer_outward_bounds(&b.outline).map_err(|e| bad(&b.name, format!("bounds before: {e:?}")))?;
        let ab = integer_outward_bounds(&a.outline).map_err(|e| bad(&a.name, format!("bounds after: {e:?}")))?;
        match (bb, ab) {
            (None, None) => {}
            (Some(x), Some(y)) => {
                for (k, (p, q)) in x.iter().zip(y.iter()).enumerate() {
                    let sh = if k % 2 == 0 { dx } else { 0 };
                    let exp = (*p as i64).checked_add(sh).ok_or_else(|| bad(&b.name, "bounds overflow".into()))?;
                    if exp < i16::MIN as i64 || exp > i16::MAX as i64 { return Err(bad(&b.name, "bounds exceed i16".into())); }
                    if *q as i64 != exp { return Err(bad(&b.name, format!("bounds[{k}] {q} != expected {exp}"))); }
                }
                if after.left_side_bearings[i] as i64 != y[0] as i64 { return Err(bad(&b.name, "hmtx lsb != xMin".into())); }
                if after.left_side_bearings[i] as i64 != before.left_side_bearings[i] as i64 + dx { return Err(bad(&b.name, "hmtx lsb delta != LSB".into())); }
            }
            _ => return Err(bad(&b.name, "outline emptiness changed".into())),
        }
        dxs.push((dx, a.advance as i64 - b.advance as i64));
    }
    // gap monotonicity proof: right glyph origin moves by (adv delta of left + dx_right); its ink by the same plus its
    // own dx. This is a proof only in the nonnegative domain (no declared offset can shrink a gap). A signed pass with a
    // negative component shrinks gaps BY DECLARATION (owner directive 2026-10-17): the per-glyph exactness checks above
    // stay the guard and the shipped-byte gap deltas are MEASURED by gap_certificate (receipt), never assumed here.
    let monotone_domain = l_i >= 0 && r_i >= 0;
    for (a_i, (dx_a, dadv_a)) in dxs.iter().enumerate() {
        for (b_i, (dx_b, _)) in dxs.iter().enumerate() {
            let delta = dadv_a + dx_b - dx_a;
            if monotone_domain && delta < 0 { return Err(bad(&before.glyphs[a_i].name, format!("facing gap to {} would shrink by {}", before.glyphs[b_i].name, -delta))); }
        }
    }
    if before.mapping != after.mapping { return Err(bad("*", "cmap mapping changed".into())); }
    Ok(())
}

/// Prepare baseline + applied, run `finalize` (the shipped-frame step, i.e. clip_metadata) on BOTH and run the STRUCTURAL
/// verification (`verify_final_frame`). This is NOT a physical overlap guard.
pub fn prepare_and_structural_verify(glyphs: &[DrawnGlyph], mapping: &[(u32, u16)], rows: &[Row], applied_rows: &[Row],
                          metadata: &NativeFontInput, off: Offsets, ledger: &Ledger, classes: &[(String, GlyphClass)],
                          finalize: &dyn Fn(NativeFontInput) -> NativeFontInput)
                          -> Result<NativeFontInput, PostMetricsError> {
    let before = finalize(prepare_generated(glyphs, mapping, rows, metadata).map_err(|e| PostMetricsError::Prepare(format!("{e:?}")))?);
    let after = finalize(prepare_generated(glyphs, mapping, applied_rows, metadata).map_err(|e| PostMetricsError::Prepare(format!("{e:?}")))?);
    verify_final_frame(&before, &after, off, ledger, classes)?;
    Ok(after)
}

/// Typed policy of the post-pass route. The pass runs only AFTER the base guard approved the base font and does NOT re-measure
/// physical overlap (receipt: final_overlap_status=NOT_MEASURED_POST_PASS).
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PostPassPolicy { AfterApprovedBase_NoOverlapRecheck }

/// Typed token: the finalized base font + the EXACT encoded base bytes (with GPOS), bound to the offset/scope of the run
/// config snapshot. Constructed only through `mint*` (private fields). `mint` with `approved == false` yields BaseGuardFailed
/// and no token; `mint_unapproved_warned` mints from an unapproved base for the always-output export path (the caller emits the
/// typed POST_PASS_APPLIED_UNAPPROVED_BASE warning; the token records `base_approved` for provenance). The round-trip binding
/// (font + GPOS must re-encode to the exact base bytes) is enforced by every constructor.
#[derive(Clone, Debug)]
pub struct ApprovedBase { font: NativeFontInput, gpos: Option<Vec<u8>>, bytes: Vec<u8>, sha256: String, step: PostStep, context_binding: String, run_config_sha256: String, #[allow(dead_code)] /* kept: the token records base_approved for provenance (per struct doc) */ base_approved: bool }
impl ApprovedBase {
    /// W3 signature: (approved base font, exact encoded base bytes incl. GPOS, run config snapshot, optional GPOS bytes, approved flag).
    /// The token carries the RunConfig context (scale binding record + canonical RunConfig digest) computed here from `rc`.
    pub fn mint(base_font: &NativeFontInput, exact_encoded_base: &[u8], rc: &crate::run_config::RunConfig, gpos: Option<&[u8]>, approved: bool) -> Result<Self, PostMetricsError> {
        let (cb, sha) = Self::context_of(rc);
        Self::mint_inner(base_font, exact_encoded_base, PostStep::from_run_config(rc)?, cb, sha, gpos, approved, false)
    }
    /// Always-output export path: mint from a base the pre-LSB/RSB gates did NOT approve (partial fit, exclusions, held kern).
    /// The guard condition is the caller's typed receipt warning; the declared post step still applies to the glyphs its scope
    /// selects. Same round-trip binding as `mint`; only the approval refusal is waived.
    pub fn mint_unapproved_warned(base_font: &NativeFontInput, exact_encoded_base: &[u8], rc: &crate::run_config::RunConfig, gpos: Option<&[u8]>) -> Result<Self, PostMetricsError> {
        let (cb, sha) = Self::context_of(rc);
        Self::mint_inner(base_font, exact_encoded_base, PostStep::from_run_config(rc)?, cb, sha, gpos, false, true)
    }
    /// (context_binding, run_config_sha256) of a RunConfig: scale binding record and sha256 of the canonical record.
    pub fn context_of(rc: &crate::run_config::RunConfig) -> (String, String) {
        (rc.scale().binding_record().to_string(), kni_core::cff_reader::sha256_hex(rc.canonical_record().as_bytes()))
    }
    #[cfg(test)]
    pub(crate) fn mint_with_step(base_font: &NativeFontInput, exact_encoded_base: &[u8], step: PostStep, gpos: Option<&[u8]>, approved: bool) -> Result<Self, PostMetricsError> {
        Self::mint_inner(base_font, exact_encoded_base, step, "test-context-binding".into(), "test-run-config-sha".into(), gpos, approved, false)
    }
    fn mint_inner(base_font: &NativeFontInput, exact_encoded_base: &[u8], step: PostStep, context_binding: String, run_config_sha256: String, gpos: Option<&[u8]>, approved: bool, allow_unapproved: bool) -> Result<Self, PostMetricsError> {
        if !approved && !allow_unapproved { return Err(PostMetricsError::BaseGuardFailed("base guard did not approve the base font".into())); }
        let re = kni_core::native_font::encode_with_layout(base_font, gpos).map_err(|e| PostMetricsError::Prepare(format!("encode base: {e:?}")))?;
        if re != exact_encoded_base { return Err(PostMetricsError::RoundTripMismatch("base font + gpos do not encode to the supplied exact base bytes".into())); }
        Ok(ApprovedBase { font: base_font.clone(), gpos: gpos.map(|g| g.to_vec()), bytes: exact_encoded_base.to_vec(), sha256: kni_core::cff_reader::sha256_hex(exact_encoded_base), step, context_binding, run_config_sha256, base_approved: approved })
    }
    pub fn font(&self) -> &NativeFontInput { &self.font }
    #[allow(dead_code)] // kept: token provenance accessor (scale binding record); unused in this binary
    pub fn context_binding(&self) -> &str { &self.context_binding }
    #[allow(dead_code)] // kept: token provenance accessor (canonical RunConfig digest); unused in this binary
    pub fn run_config_sha256(&self) -> &str { &self.run_config_sha256 }
    pub fn sha256(&self) -> &str { &self.sha256 }
    pub fn bytes(&self) -> &[u8] { &self.bytes }
    #[allow(dead_code)] // kept: token provenance accessor (declared post step); unused in this binary
    pub fn step(&self) -> &PostStep { &self.step }
    /// Whether the pre-LSB/RSB gates approved the base this token was minted from (provenance only; the pass runs either way).
    #[allow(dead_code)] // kept: approval provenance accessor (per item doc); unused in this binary
    pub fn base_approved(&self) -> bool { self.base_approved }
}

#[derive(Clone, Debug)]
pub struct PostPassOutput { pub bytes: Vec<u8>, pub font: NativeFontInput, pub ledger: Ledger, #[allow(dead_code)] /* kept: typed post-pass policy carried on the output (per policy doc) */ pub policy: PostPassPolicy, pub receipt: String }

/// Minimal sfnt table lookup on shipped bytes (None if absent or malformed).
pub fn sfnt_table<'a>(b: &'a [u8], tag: &[u8; 4]) -> Option<&'a [u8]> {
    let n = u16::from_be_bytes([*b.get(4)?, *b.get(5)?]) as usize;
    for i in 0..n {
        let r = 12usize.checked_add(16usize.checked_mul(i)?)?;
        let rec = b.get(r..r.checked_add(16)?)?;
        if &rec[0..4] == tag {
            let off = u32::from_be_bytes(rec[8..12].try_into().ok()?) as usize;
            let len = u32::from_be_bytes(rec[12..16].try_into().ok()?) as usize;
            return b.get(off..off.checked_add(len)?);
        }
    }
    None
}

/// Analytic gap-delta certificate (NOT a physical overlap measurement). From the two shipped byte streams only: integer
/// hmtx advances and the CFF-readback glyph translation (uniform x shift, y unchanged, same point structure). For an ordered pair
/// (a,b) with unchanged outline shapes, unchanged GPOS and unchanged baseline, gap delta = d_adv(a) + dx(b) - dx(a)
/// = dRSB(a) + dLSB(b); over ALL ordered pairs (incl. a==b, every class, .notdef/space included) its minimum is
/// min_a(d_adv(a) - dx(a)) + min_b(dx(b)), so the computation is O(n). All integer arithmetic, no epsilon. The certificate
/// MEASURES the signed deltas: a negative minimum pair delta is a legitimate outcome of a declared negative offset
/// (owner directive 2026-10-17) and is reported via min_pair_delta, not refused. Structural mismatches (a shape changes,
/// a non-uniform translation, non-integral/changed y, a read failure) stay typed Structural "NOT_PROVEN" refusals.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GapCertificate { pub glyphs: usize, pub min_rsb_delta: i64, pub min_lsb_delta: i64, pub min_pair_delta: i64, pub translations: Vec<i64>, pub advance_deltas: Vec<i64> }
fn hmtx_advances(b: &[u8]) -> Result<Vec<i64>, PostMetricsError> {
    let hhea = sfnt_table(b, b"hhea").ok_or_else(|| st("NOT_PROVEN: hhea missing"))?;
    let n = u16::from_be_bytes([*hhea.get(34).ok_or_else(|| st("NOT_PROVEN: hhea short"))?, *hhea.get(35).ok_or_else(|| st("NOT_PROVEN: hhea short"))?]) as usize;
    let hm = sfnt_table(b, b"hmtx").ok_or_else(|| st("NOT_PROVEN: hmtx missing"))?;
    let mut v = Vec::with_capacity(n);
    for i in 0..n { let o = 4 * i; v.push(u16::from_be_bytes([*hm.get(o).ok_or_else(|| st("NOT_PROVEN: hmtx short or compressed (numberOfHMetrics < glyph count not proven)"))?, *hm.get(o + 1).ok_or_else(|| st("NOT_PROVEN: hmtx short or compressed (numberOfHMetrics < glyph count not proven)"))?]) as i64); }
    Ok(v)
}
pub fn gap_certificate(base_bytes: &[u8], final_bytes: &[u8]) -> Result<GapCertificate, PostMetricsError> {
    let (ab, af) = (hmtx_advances(base_bytes)?, hmtx_advances(final_bytes)?);
    if ab.len() != af.len() || ab.is_empty() { return Err(st("NOT_PROVEN: hmtx glyph count differs or empty")); }
    let rb = kni_core::cff_reader::CffReader::from_bytes(base_bytes, &kni_core::cff_reader::sha256_hex(base_bytes)).map_err(|e| st(format!("NOT_PROVEN: readback base: {e:?}")))?;
    let rf = kni_core::cff_reader::CffReader::from_bytes(final_bytes, &kni_core::cff_reader::sha256_hex(final_bytes)).map_err(|e| st(format!("NOT_PROVEN: readback final: {e:?}")))?;
    if rb.glyph_count() != ab.len() || rf.glyph_count() != ab.len() { return Err(st("NOT_PROVEN: readback glyph count != hmtx count")); }
    let n = ab.len();
    let (mut dxs, mut dadv) = (Vec::with_capacity(n), Vec::with_capacity(n));
    for i in 0..n {
        let gb = rb.read_glyph(i as u16).map_err(|e| st(format!("NOT_PROVEN: read base {i}: {e:?}")))?.drawn(String::new());
        let gf = rf.read_glyph(i as u16).map_err(|e| st(format!("NOT_PROVEN: read final {i}: {e:?}")))?.drawn(String::new());
        let (pb, pf) = (pts(&gb), pts(&gf));
        if pb.len() != pf.len() { return Err(st(format!("NOT_PROVEN: glyph {i} point count differs"))); }
        let mut dx: Option<i64> = None;
        for (p, q) in pb.iter().zip(pf.iter()) {
            if p.x.fract() != 0.0 || q.x.fract() != 0.0 || p.y != q.y { return Err(st(format!("NOT_PROVEN: glyph {i} non-integral x or y changed"))); }
            let d = q.x as i64 - p.x as i64;
            match dx { None => dx = Some(d), Some(e) if e != d => return Err(st(format!("NOT_PROVEN: glyph {i} not a uniform translation (outline warp)"))), _ => {} }
        }
        dxs.push(dx.unwrap_or(0));
        dadv.push(af[i] - ab[i]);
    }
    let min_rsb = (0..n).map(|i| dadv[i] - dxs[i]).min().ok_or_else(|| st("empty"))?;
    let min_lsb = dxs.iter().copied().min().ok_or_else(|| st("empty"))?;
    let min_pair = min_rsb.checked_add(min_lsb).ok_or_else(|| st("NOT_PROVEN: delta overflow"))?;
    // min_pair may be negative: that is the measured effect of a declared negative offset, reported as data.
    Ok(GapCertificate { glyphs: n, min_rsb_delta: min_rsb, min_lsb_delta: min_lsb, min_pair_delta: min_pair, translations: dxs, advance_deltas: dadv })
}

fn st(m: impl Into<String>) -> PostMetricsError { PostMetricsError::Structural(m.into()) }

/// Aggregates (head/hhea/OS2/name) of the post-pass font versus the approved font and the recomputed glyph data.
/// Declared provenance of OS/2 xAvgCharWidth. The caller (main) chooses; nothing is auto-detected from the base value.
/// LegacyConstant: the base value is a legacy default (not owner design) and is left untouched.
/// DerivedMean: xAvgCharWidth = mean of the hmtx advances of the declared population with the named rounding (integer arithmetic,
/// checked sum, no epsilon), re-derived from the FINAL advances and required to be i16-representable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AvgWidthPolicy { #[allow(dead_code)] /* kept: legacy-default policy, base value left untouched (per item doc) */ LegacyConstant, DerivedMean { population: AvgPopulation, rounding: AvgRounding } }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AvgPopulation { #[allow(dead_code)] /* kept: full-population option of DerivedMean */ AllGlyphs, NonzeroAdvance }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AvgRounding { Floor, #[allow(dead_code)] /* kept: ceil rounding option of DerivedMean */ Ceil, #[allow(dead_code)] /* kept: half-up rounding option of DerivedMean */ HalfUp }
impl AvgWidthPolicy {
    pub fn label(&self) -> String {
        match self { Self::LegacyConstant => "LegacyConstant".into(), Self::DerivedMean { population, rounding } => format!("DerivedMean({population:?},{rounding:?})") }
    }
}
fn avg_width_for(policy: AvgWidthPolicy, base: &NativeFontInput, after: &NativeFontInput) -> Result<(i16, &'static str), PostMetricsError> {
    let AvgWidthPolicy::DerivedMean { population, rounding } = policy else { return Ok((base.os2.average_width, "UNCHANGED_LEGACY_CONSTANT")); };
    let mut sum: u64 = 0; let mut cnt: u64 = 0;
    for g in &after.glyphs {
        if population == AvgPopulation::NonzeroAdvance && g.advance == 0 { continue; }
        sum = sum.checked_add(u64::from(g.advance)).ok_or_else(|| st("xAvgCharWidth sum overflow"))?;
        cnt += 1;
    }
    if cnt == 0 { return Ok((0, "derived_after_hmtx_empty_population")); }
    let v = match rounding {
        AvgRounding::Floor => sum / cnt,
        AvgRounding::Ceil => sum.checked_add(cnt - 1).ok_or_else(|| st("xAvgCharWidth sum overflow"))? / cnt,
        AvgRounding::HalfUp => sum.checked_mul(2).and_then(|x| x.checked_add(cnt)).ok_or_else(|| st("xAvgCharWidth sum overflow"))? / (2 * cnt),
    };
    Ok((i16::try_from(v).map_err(|_| st("xAvgCharWidth exceeds i16"))?, "derived_after_hmtx"))
}

fn verify_aggregates(policy: AvgWidthPolicy, base: &NativeFontInput, after: &NativeFontInput, finalize: &dyn Fn(NativeFontInput) -> NativeFontInput) -> Result<(), PostMetricsError> {
    let n = after.glyphs.len();
    if usize::from(after.hhea.metric_count) != n { return Err(st("hhea.metric_count != glyph count")); }
    let mut all: Option<[i16; 4]> = None;
    let (mut min_l, mut min_r, mut max_e, mut max_adv) = (None::<i16>, None::<i16>, None::<i16>, 0u16);
    for (g, l) in after.glyphs.iter().zip(after.left_side_bearings.iter()) {
        max_adv = max_adv.max(g.advance);
        if let Some(b) = integer_outward_bounds(&g.outline).map_err(|e| st(format!("bounds: {e:?}")))? {
            all = Some(match all { None => b, Some(v) => [v[0].min(b[0]), v[1].min(b[1]), v[2].max(b[2]), v[3].max(b[3])] });
            let extent = i16::try_from(*l as i32 + b[2] as i32 - b[0] as i32).map_err(|_| st("extent exceeds i16"))?;
            let rsb = i16::try_from(g.advance as i32 - extent as i32).map_err(|_| st("rsb exceeds i16"))?;
            min_l = Some(min_l.map_or(*l, |v| v.min(*l))); min_r = Some(min_r.map_or(rsb, |v| v.min(rsb))); max_e = Some(max_e.map_or(extent, |v| v.max(extent)));
        }
    }
    if after.head.bounds != all.unwrap_or([0; 4]) { return Err(st("head.bounds != union of glyph bounds")); }
    if after.hhea.advance_max != max_adv { return Err(st("hhea.advance_max != max advance")); }
    if after.hhea.min_lsb != min_l.unwrap_or(0) || after.hhea.min_rsb != min_r.unwrap_or(0) || after.hhea.max_extent != max_e.unwrap_or(0) { return Err(st("hhea min_lsb/min_rsb/max_extent mismatch")); }
    // finalize is idempotent on the result (vertical/OS2 derived fields already follow the new head bounds and cmap)
    let again = finalize(after.clone());
    if again.hhea.ascender != after.hhea.ascender || again.hhea.descender != after.hhea.descender || again.os2.typo != after.os2.typo
        || again.os2.win_ascent != after.os2.win_ascent || again.os2.win_descent != after.os2.win_descent
        || again.os2.first_char != after.os2.first_char || again.os2.last_char != after.os2.last_char { return Err(st("finalize not idempotent on post-pass font")); }
    // xAvgCharWidth must follow the new hmtx advances (see avg_width_for); everything else non-derived must be untouched
    if avg_width_for(policy, base, after)?.0 != after.os2.average_width { return Err(st("OS/2 xAvgCharWidth stale vs hmtx advances")); }
    let (mut a, mut b) = (after.os2.clone(), base.os2.clone());
    for o in [&mut a, &mut b] { o.average_width = 0; o.typo = [0; 3]; o.win_ascent = 0; o.win_descent = 0; o.first_char = 0; o.last_char = 0; }
    if format!("{a:?}") != format!("{b:?}") { return Err(st("OS/2 non-derived fields changed")); }
    if format!("{:?}", after.names) != format!("{:?}", base.names) || after.postscript_name != base.postscript_name { return Err(st("name records changed")); }
    if after.mapping != base.mapping { return Err(st("cmap changed")); }
    Ok(())
}

/// POST-PASS (separate pass; input = guard-approved base token; output = ONE final font + bytes). Steps: range check; rebuild
/// rows from the approved font and PROVE the round trip (unmodified rows re-prepare to the same bytes); apply LSB/RSB;
/// prepare+finalize; structural verify (exact every-point translation, advance/hmtx/bounds, cmap/order, facing-gap
/// monotonicity); aggregates (head/hhea/OS2/names); encode with the SAME gpos bytes (+determinism); GPOS table byte identity;
/// independent CffReader readback translation check. This is NOT a physical overlap guard. Any failure => typed Err, nothing
/// is returned or published; the offset is never reduced silently. 0/0 => Err(ZeroOffsetPass) (no fallback output).
pub fn post_pass(base: &ApprovedBase, rc: &crate::run_config::RunConfig, classes: &[(String, GlyphClass)], allow: Option<&crate::kern_scope::TokenBoundAllow>, avg_policy: AvgWidthPolicy,
                 finalize: &dyn Fn(NativeFontInput) -> NativeFontInput) -> Result<PostPassOutput, PostMetricsError> {
    let (cb, sha) = ApprovedBase::context_of(rc);
    post_pass_in(base, &cb, &sha, classes, allow, avg_policy, finalize)
}
/// Same pass with an explicit run context; a token minted under a different context is refused (no cross-context reuse).
pub fn post_pass_in(base: &ApprovedBase, context_binding: &str, run_config_sha256: &str, classes: &[(String, GlyphClass)], allow: Option<&crate::kern_scope::TokenBoundAllow>, avg_policy: AvgWidthPolicy,
                 finalize: &dyn Fn(NativeFontInput) -> NativeFontInput) -> Result<PostPassOutput, PostMetricsError> {
    post_pass_in_with_row_policy(base, context_binding, run_config_sha256, classes, allow, avg_policy, finalize, RowPolicy::RefuseStage, &[])
}
/// `post_pass_in` under an explicit row policy; threads RowPolicy and the
/// `bind_classes_with_policy` exclusions into `apply_with_row_policy`. The
/// strict delegate above is the incumbent path, bit-identical.
pub fn post_pass_in_with_row_policy(base: &ApprovedBase, context_binding: &str, run_config_sha256: &str, classes: &[(String, GlyphClass)], allow: Option<&crate::kern_scope::TokenBoundAllow>, avg_policy: AvgWidthPolicy,
                 finalize: &dyn Fn(NativeFontInput) -> NativeFontInput, row_policy: RowPolicy, bind_exclusions: &[BindExclusion]) -> Result<PostPassOutput, PostMetricsError> {
    if base.context_binding != context_binding || base.run_config_sha256 != run_config_sha256 {
        return Err(PostMetricsError::ContextMismatch("approved-base token was minted under a different run context".into()));
    }
    let off = base.step.offset;
    // explicit allow-list (owner scope: kerning-applied letters) narrows the configured class policy; it never widens it
    let mut scope_owned = base.step.scope.clone();
    if let Some(tb) = allow {
        if tb.base_sha256() != base.sha256 { return Err(PostMetricsError::ContextMismatch("allow-set is bound to a different approved baseline".into())); }
        let a = tb.allow();
        scope_owned.allow = Some(match &scope_owned.allow { Some(x) => x.intersection(a).cloned().collect(), None => a.clone() });
        if scope_owned.allow.as_ref().map_or(true, |x| x.is_empty()) { return Err(PostMetricsError::EmptyKernedLetterSelection); }
    }
    let scope = &scope_owned;
    check_range(&off)?;
    if off.is_noop() { return Err(PostMetricsError::ZeroOffsetPass); }
    let approved = &base.font;
    let n = approved.glyphs.len();
    if approved.left_side_bearings.len() != n { return Err(PostMetricsError::ShapeMismatch("hmtx lsb count != glyph count")); }
    let mut glyphs: Vec<DrawnGlyph> = Vec::with_capacity(n);
    let mut rows: Vec<Row> = Vec::with_capacity(n);
    for (i, g) in approved.glyphs.iter().enumerate() {
        let mut d = g.outline.clone();
        d.glyph_id = g.name.clone();
        let rsb = match integer_outward_bounds(&g.outline).map_err(|e| PostMetricsError::Prepare(format!("{e:?}")))? {
            Some(b) => g.advance as f64 - b[2] as f64,
            None => 0.0,
        };
        let lsb_row = match kni_core::generated_native::ink_min_x(&g.outline).map_err(|e| PostMetricsError::Prepare(format!("{e:?}")))? {
            Some(xmin) => xmin,
            None => approved.left_side_bearings[i] as f64,
        };
        rows.push((g.name.clone(), lsb_row, rsb, g.advance as f64));
        glyphs.push(d);
    }
    let re = finalize(prepare_generated(&glyphs, &approved.mapping, &rows, approved).map_err(|e| PostMetricsError::Prepare(format!("{e:?}")))?);
    let reb = kni_core::native_font::encode_with_layout(&re, base.gpos.as_deref()).map_err(|e| PostMetricsError::RoundTripMismatch(format!("encode: {e:?}")))?;
    if reb != base.bytes { return Err(PostMetricsError::RoundTripMismatch("re-prepared rows do not reproduce the approved base bytes".into())); }
    let (applied, ledger) = apply_with_row_policy(&rows, classes, off, scope, row_policy, bind_exclusions)?;
    let after = prepare_and_structural_verify(&glyphs, &approved.mapping, &rows, &applied, approved, off, &ledger, classes, finalize)?;
    let mut after = after;
    let (avg, avg_note) = avg_width_for(avg_policy, approved, &after)?;
    after.os2.average_width = avg;
    verify_aggregates(avg_policy, approved, &after, finalize)?;
    let bytes = kni_core::native_font::encode_with_layout(&after, base.gpos.as_deref()).map_err(|e| st(format!("encode final: {e:?}")))?;
    let bytes2 = kni_core::native_font::encode_with_layout(&after, base.gpos.as_deref()).map_err(|e| st(format!("encode final(2): {e:?}")))?;
    if bytes != bytes2 { return Err(st("final encode not deterministic")); }
    if sfnt_table(&base.bytes, b"GPOS") != sfnt_table(&bytes, b"GPOS") { return Err(st("GPOS table bytes differ from the approved base")); }
    // independent readback of both byte streams: every point (controls included) moved by exactly (+dx, 0)
    let applied_ids: BTreeSet<&str> = ledger.applied().into_iter().collect();
    let rb = kni_core::cff_reader::CffReader::from_bytes(&base.bytes, &base.sha256).map_err(|e| st(format!("readback base: {e:?}")))?;
    let fsha = kni_core::cff_reader::sha256_hex(&bytes);
    let rf = kni_core::cff_reader::CffReader::from_bytes(&bytes, &fsha).map_err(|e| st(format!("readback final: {e:?}")))?;
    if rb.glyph_count() != n || rf.glyph_count() != n { return Err(st("readback glyph count mismatch")); }
    for (i, g) in approved.glyphs.iter().enumerate() {
        let gb = rb.read_glyph(i as u16).map_err(|e| st(format!("readback base glyph {i}: {e:?}")))?.drawn(g.name.clone());
        let gf = rf.read_glyph(i as u16).map_err(|e| st(format!("readback final glyph {i}: {e:?}")))?.drawn(g.name.clone());
        let dx = if applied_ids.contains(g.name.as_str()) { off.lsb() } else { 0.0 };
        let (pb, pf) = (pts(&gb), pts(&gf));
        if pb.len() != pf.len() { return Err(st(format!("readback point count differs for {}", g.name))); }
        for (p, q) in pb.iter().zip(pf.iter()) { if q.x != p.x + dx || q.y != p.y { return Err(st(format!("readback point mismatch in {}", g.name))); } }
    }
    let cert = gap_certificate(&base.bytes, &bytes)?;
    // Nonnegative runs keep the monotonicity claim (receipt byte-identical to before); a signed run with a negative
    // measured minimum claims NO monotonicity and reports the signed measurement instead.
    let gap_lines = if cert.min_pair_delta >= 0 { "gap_monotonicity\tANALYTIC_NONDECREASING\n".to_string() }
        else { format!("gap_monotonicity\tNOT_CLAIMED_SIGNED\ngap_measurement\tANALYTIC_SIGNED\n") };
    let receipt = format!(
        "guard_stage\tpre_lsb_rsb\nguard_result\tapproved\napproved_base_sha256\t{}\ncontext_binding\t{}\nrun_config_sha256\t{}\npostpass\tlsb_rsb\nrequested_lsb\t{}\nrequested_rsb\t{}\neffective_lsb\t{}\neffective_rsb\t{}\nscope\t{}\nfinal_font_sha256\t{}\nfinal_overlap_rechecked\tfalse\nfinal_overlap_status\tNOT_MEASURED_POST_PASS\nguard_policy\tPRE_POSTMETRICS_ONLY\npost_pass_policy\tAfterApprovedBase_NoOverlapRecheck\nxavgcharwidth\t{}\t{}\t{}\n{}gap_min_pair_delta\t{}\nphysical_overlap_postpass\tNOT_MEASURED\nbaseline_overlap_note\texisting baseline overlap, if any, is not removed or measured by this pass\n",
        base.sha256, tsv_escape(&base.context_binding), base.run_config_sha256, off.lsb(), off.rsb(), off.lsb(), off.rsb(), tsv_escape(&ledger.scope_note), fsha, avg, avg_note, avg_policy.label(), gap_lines, cert.min_pair_delta);
    Ok(PostPassOutput { bytes, font: after, ledger, policy: PostPassPolicy::AfterApprovedBase_NoOverlapRecheck, receipt })
}

/// Atomic exclusive publish: write to a unique temp file in `dir`, then hard-link it to `name` (fails if `name` exists), then
/// remove the temp. Never overwrites; no partial file is ever visible under `name`.
#[allow(dead_code)] // kept: atomic exclusive publish API (per item doc); no call site in this binary
pub fn publish_exclusive(dir: &std::path::Path, name: &str, bytes: &[u8]) -> Result<std::path::PathBuf, PostMetricsError> {
    publish_set_exclusive(dir, &[(name, bytes)]).map(|mut v| v.remove(0))
}

/// Transaction-with-rollback publish of several files (e.g. font.otf + ledger). NOT an atomic set: claims happen one by one, so a
/// concurrent reader may briefly see an earlier file (e.g. the ledger) before a later one (the font); on failure the rollback is
/// best effort and any failure of it is reported. Each single claim is atomic and never overwrites. All files are STAGED first (create_new temps,
/// written and synced); then each is CLAIMED with hard_link (atomic, fails if the name exists, so a concurrent creator is never
/// overwritten and no exists() precheck is relied on). If any claim fails, only the entries THIS attempt claimed are removed
/// (rollback), and all temps are removed. Every cleanup failure is reported in the returned error, never swallowed.
pub fn publish_set_exclusive(dir: &std::path::Path, files: &[(&str, &[u8])]) -> Result<Vec<std::path::PathBuf>, PostMetricsError> {
    use std::io::Write;
    let pe = |op: &str, e: std::io::Error| format!("{op}: {:?}", e.kind());
    let names: BTreeSet<&str> = files.iter().map(|f| f.0).collect();
    if files.is_empty() || names.len() != files.len() || files.iter().any(|f| f.0.is_empty() || f.0.contains('/') || f.0.contains('\\') || f.0.starts_with('.')) {
        return Err(PostMetricsError::Publish("invalid or duplicate publish names".into()));
    }
    let pid = std::process::id();
    let tmps: Vec<std::path::PathBuf> = files.iter().enumerate().map(|(i, f)| dir.join(format!(".{}.tmp-{pid}-{i}", f.0))).collect();
    let mut staged: Vec<&std::path::PathBuf> = Vec::new();
    let mut claimed: Vec<std::path::PathBuf> = Vec::new();
    let mut failure: Option<String> = None;
    for (i, f) in files.iter().enumerate() {
        let r = std::fs::OpenOptions::new().write(true).create_new(true).open(&tmps[i]).map_err(|e| pe(&format!("create tmp for {}", f.0), e))
            .and_then(|mut h| { staged.push(&tmps[i]); h.write_all(f.1).map_err(|e| pe(&format!("write {}", f.0), e)).and_then(|_| h.sync_all().map_err(|e| pe(&format!("sync {}", f.0), e))) });
        if let Err(e) = r { failure = Some(e); break; }
    }
    if failure.is_none() {
        for (i, f) in files.iter().enumerate() {
            let target = dir.join(f.0);
            match std::fs::hard_link(&tmps[i], &target) {
                Ok(()) => claimed.push(target),
                Err(e) => { failure = Some(pe(&format!("claim {} (exists?)", f.0), e)); break; }
            }
        }
    }
    let mut cleanup: Vec<String> = Vec::new();
    if failure.is_some() { for c in &claimed { if let Err(e) = std::fs::remove_file(c) { cleanup.push(format!("rollback {}: {}", c.display(), pe("remove", e))); } } }
    for t in &staged { if let Err(e) = std::fs::remove_file(t) { cleanup.push(format!("temp {}: {}", t.display(), pe("remove", e))); } }
    match (failure, cleanup.is_empty()) {
        (None, true) => Ok(claimed),
        (None, false) => { // temps linger: do not report success; roll the claims back and report every failure
            let mut all = cleanup;
            for c in &claimed { if let Err(e) = std::fs::remove_file(c) { all.push(format!("rollback {}: {}", c.display(), pe("remove", e))); } }
            Err(PostMetricsError::Publish(format!("temp cleanup failed after claim; rollback attempted; CLEANUP FAILED: {}", all.join("; "))))
        }
        (Some(f), true) => Err(PostMetricsError::Publish(f)),
        (Some(f), false) => Err(PostMetricsError::Publish(format!("{f}; CLEANUP FAILED: {}", cleanup.join("; ")))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_core::cff_reader::{sha256_hex, CffReader};
    use kni_core::native_font::encode_with_layout;
    use kni_core::reference_slice::{ReferenceRing, Span};
    use kni_metrics::gpos_pairpos1::{write_kern_pairpos1_or_omit, PairKern};

    fn sq(id: &str, x0: f64, x1: f64) -> DrawnGlyph {
        DrawnGlyph { glyph_id: id.into(), rings: vec![ReferenceRing { start: Point { x: x0, y: 0.0 },
            spans: vec![Span::Line { end: Point { x: x1, y: 0.0 } }, Span::Line { end: Point { x: x1, y: 100.0 } },
                        Span::Line { end: Point { x: x0, y: 100.0 } }, Span::Line { end: Point { x: x0, y: 0.0 } }] }] }
    }
    /// curve glyph: INNER cubic control points deliberately away from the bbox extrema.
    fn curve(id: &str) -> DrawnGlyph {
        DrawnGlyph { glyph_id: id.into(), rings: vec![ReferenceRing { start: Point { x: 20.0, y: 0.0 },
            spans: vec![Span::Cubic { control_one: Point { x: 40.0, y: 30.0 }, control_two: Point { x: 60.0, y: 30.0 }, end: Point { x: 80.0, y: 0.0 } },
                        Span::Line { end: Point { x: 20.0, y: 0.0 } }] }] }
    }
    fn fixture() -> (Vec<DrawnGlyph>, Vec<Row>, Classes, Vec<(u32, u16)>, Vec<String>) {
        let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, sq("A", 10.0, 90.0), sq("acute", 0.0, 30.0),
            DrawnGlyph { glyph_id: "space".into(), rings: vec![] }, curve("o")];
        let rows: Vec<Row> = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), 10.0, 20.0, 110.0), ("acute".into(), 0.0, 0.0, 0.0),
            ("space".into(), 0.0, 0.0, 250.0), ("o".into(), 20.0, 20.0, 100.0)];
        let order: Vec<String> = glyphs.iter().map(|g| g.glyph_id.clone()).collect();
        let map = vec![(65, 1), (0x301, 2), (32, 3), (111, 4)];
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        let classes = bind_classes(&order, &map, &inv, &BTreeSet::new()).unwrap();
        (glyphs, rows, classes, map, order)
    }
    fn meta() -> NativeFontInput {
        use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, Os2Metadata, PostMetadata};
        NativeFontInput {
            postscript_name: "Test-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
            head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0, -12, 800, 740], mac_style: 0, lowest_ppem: 1 },
            hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
                panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
            names: crate::names("Test", "Regular", "Test-Regular"),
        }
    }
    fn u16at(b: &[u8], o: usize) -> u16 { u16::from_be_bytes([b[o], b[o + 1]]) }
    fn table<'a>(b: &'a [u8], tag: &[u8; 4]) -> Option<&'a [u8]> {
        for i in 0..u16at(b, 4) as usize {
            let r = 12 + 16 * i;
            if &b[r..r + 4] == tag {
                let off = u32::from_be_bytes(b[r + 8..r + 12].try_into().unwrap()) as usize;
                let len = u32::from_be_bytes(b[r + 12..r + 16].try_into().unwrap()) as usize;
                return Some(&b[off..off + len]);
            }
        }
        None
    }
    fn gpos() -> Option<Vec<u8>> {
        write_kern_pairpos1_or_omit(5, &[PairKern { left: 1, right: 4, x_advance: -12 }, PairKern { left: 4, right: 1, x_advance: 7 }]).unwrap()
    }
    fn encode(g: &[DrawnGlyph], map: &[(u32, u16)], rows: &[Row]) -> Vec<u8> {
        let p = crate::clip_metadata(prepare_generated(g, map, rows, &meta()).unwrap());
        encode_with_layout(&p, gpos().as_deref()).unwrap()
    }

    #[test]
    fn offsets_reject_bad_and_huge() {
        for (l, r) in [(f64::NAN, 0.0), (0.0, f64::INFINITY), (0.0, f64::NEG_INFINITY), (0.5, 0.0), (0.0, 25.5), (-0.5, 0.0), (0.0, -25.5)] {
            assert!(matches!(offsets_from_config(l, r), Err(PostMetricsError::Offset(OffsetError::InvalidOffset { .. }))), "{l} {r}");
        }
        for v in [32768.0, 1e300, f64::MAX, 1e19] { assert!(matches!(offsets_from_config(v, 0.0), Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" })), "{v}"); assert!(offsets_from_config(0.0, v).is_err()); }
        for v in [-32769.0, -1e300, f64::MIN, -1e19] { assert!(matches!(offsets_from_config(v, 0.0), Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" })), "{v}"); assert!(offsets_from_config(0.0, v).is_err()); }
        assert!(matches!(offsets_from_config(1e308, 1e308), Err(PostMetricsError::Offset(OffsetError::NonFiniteSum)))); assert!(offsets_from_config(25.0, 25.0).is_ok() && offsets_from_config(32767.0, 32767.0).is_ok());
    }
    #[test]
    fn post_step_from_real_run_config() {
        use crate::run_config::{FitErrorPolicy, RunConfig};
        use kni_core::scale_context::ScaleContext;
        let ctx = ScaleContext::from_convention("r", "c", 2.0, 1000.0, "cohort", "frame").unwrap();
        let mut i = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), std::path::PathBuf::from("cap"), std::path::PathBuf::from("out"), "s1");
        i.lsb_add = 25.0; i.rsb_add = 25.0; i.post_scope = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false }; i.post_scope_label = "base".into();
        let rc = RunConfig::new(i.clone(), ctx.clone()).unwrap();
        let ps = PostStep::from_run_config(&rc).unwrap();
        assert_eq!((ps.offset.lsb(), ps.offset.rsb(), ps.scope.policy.base, ps.scope.policy.mark), (25.0, 25.0, true, false));
        assert_eq!(ps.scope.origin, "run_config.post_scope label=base");
        // RunConfig accepts a huge finite offset; the post step refuses it
        i.lsb_add = 1e300; i.rsb_add = 0.0;
        let rc = RunConfig::new(i, ctx).unwrap();
        assert!(matches!(PostStep::from_run_config(&rc), Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" })));
        assert!(PostStep::legacy_default().offset.is_noop());
    }
    #[test]
    fn directly_constructed_huge_offset_refused_at_entry() {
        use kni_core::scale_context::{DimParam, Dimension};
        let p = |n: &str, v: f64| DimParam::new(n, v, Dimension::DeclaredOutputUnits, "t").unwrap();
        let huge = SignedSideBearingOffset::from_params(&p("lsb", 1e300), &p("rsb", 0.0)).unwrap(); // K2's signed constructor accepts it
        let (g, rows, classes, map, _o) = fixture();
        assert!(matches!(apply(&rows, &classes, huge, &Scope::base_only("t")), Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" })));
        assert!(matches!(check_range(&SignedSideBearingOffset::from_params(&p("l", 0.0), &p("r", 32768.0)).unwrap()), Err(PostMetricsError::OffsetOutOfRange { name: "rsb_add" })));
        assert!(matches!(check_range(&SignedSideBearingOffset::from_params(&p("l", -32769.0), &p("r", 0.0)).unwrap()), Err(PostMetricsError::OffsetOutOfRange { name: "lsb_add" })));
        let ok = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, ok, &Scope::base_only("t")).unwrap();
        let before = prepare_generated(&g, &map, &rows, &meta()).unwrap();
        let after = prepare_generated(&g, &map, &applied, &meta()).unwrap();
        assert!(matches!(verify_final_frame(&before, &after, huge, &led, &classes), Err(PostMetricsError::OffsetOutOfRange { .. })));
        assert!(matches!(verify_final_frame(&before, &after, SignedSideBearingOffset::from_params(&p("l", 1e19), &p("r", 0.0)).unwrap(), &led, &classes), Err(PostMetricsError::OffsetOutOfRange { .. })));
    }
    #[test]
    fn huge_but_representable_offset_refused_without_panic() {
        let (g, rows, classes, map, _o) = fixture();
        let off = offsets_from_config(32767.0, 32767.0).unwrap();
        assert!(matches!(apply(&rows, &classes, off, &Scope::base_only("test")), Err(PostMetricsError::NumericRange(_))));
        let _ = (g, map);
    }
    #[test]
    fn zero_zero_noop_rows_bitwise() {
        let (_g, rows, classes, _m, _o) = fixture();
        let (out, led) = apply(&rows, &classes, Offsets::none(), &Scope::base_only("test")).unwrap();
        for (a, b) in rows.iter().zip(out.iter()) { assert_eq!((&a.0, a.1.to_bits(), a.2.to_bits(), a.3.to_bits()), (&b.0, b.1.to_bits(), b.2.to_bits(), b.3.to_bits())); }
        assert!(led.rows.is_empty());
    }
    #[test]
    fn marq_25_25_rows_ledger_and_independence() {
        let (_g, rows, classes, _m, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (out, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        assert_eq!(out[1], ("A".into(), 35.0, 45.0, 160.0));
        assert_eq!((&out[0], &out[2], &out[3]), (&rows[0], &rows[2], &rows[3]));
        assert_eq!(led.applied(), vec!["A", "o"]);
        let t = led.tsv(off);
        assert!(t.contains("acute\tMark\texcluded\tmark is not propagated") && t.contains("space\tSpace\texcluded") && t.contains(".notdef\tNotdef\texcluded"), "{t}");
        let (a, _) = apply(&rows, &classes, offsets_from_config(7.0, 0.0).unwrap(), &Scope::base_only("test")).unwrap();
        assert_eq!(a[1], ("A".into(), 17.0, 20.0, 117.0));
        let (b, _) = apply(&rows, &classes, offsets_from_config(0.0, 9.0).unwrap(), &Scope::base_only("test")).unwrap();
        assert_eq!(b[1], ("A".into(), 10.0, 29.0, 119.0));
    }
    #[test]
    fn signed_offsets_accept_negative_values() {
        // owner directive 2026-10-17: negative offsets are legitimate (the old refusal was an engine limitation)
        let o = offsets_from_config(-1.0, 0.0).unwrap(); assert_eq!((o.lsb(), o.rsb()), (-1.0, 0.0));
        let o = offsets_from_config(0.0, -1.0).unwrap(); assert_eq!((o.lsb(), o.rsb()), (0.0, -1.0));
        let o = offsets_from_config(-25.0, -30.0).unwrap(); assert_eq!((o.lsb(), o.rsb(), o.facing_gap_delta()), (-25.0, -30.0, -55.0));
        let o = offsets_from_config(MIN_OFFSET, MAX_OFFSET).unwrap(); assert_eq!((o.lsb(), o.rsb()), (-32768.0, 32767.0));
        assert!(matches!(offsets_from_config(-1e308, -1e308), Err(PostMetricsError::Offset(OffsetError::NonFiniteSum))));
    }
    #[test]
    fn negative_l_r_both_rows_ledger() {
        let (_g, rows, classes, _m, _o) = fixture();
        // negative L only: geometry translate (lsb moves left), advance shrinks by L
        let (out, led) = apply(&rows, &classes, offsets_from_config(-25.0, 0.0).unwrap(), &Scope::base_only("t")).unwrap();
        assert_eq!(out[1], ("A".into(), -15.0, 20.0, 85.0));
        assert_eq!(led.applied(), vec!["A", "o"]);
        // negative R only: advance adjustment, no geometry shift
        let (out, _) = apply(&rows, &classes, offsets_from_config(0.0, -15.0).unwrap(), &Scope::base_only("t")).unwrap();
        assert_eq!(out[1], ("A".into(), 10.0, 5.0, 95.0));
        // both negative
        let (out, _) = apply(&rows, &classes, offsets_from_config(-10.0, -15.0).unwrap(), &Scope::base_only("t")).unwrap();
        assert_eq!(out[1], ("A".into(), 0.0, 5.0, 85.0));
        // lsb may cross zero left (a negative lsb is representable in hmtx/i16)
        let (out, _) = apply(&rows, &classes, offsets_from_config(-40.0, 0.0).unwrap(), &Scope::base_only("t")).unwrap();
        assert_eq!(out[1].1, -30.0);
        assert_eq!(out[4].1, -20.0);
        // zero-advance mark keeps advance 0 even under a negative add; its lsb still shifts
        let mut sc = Scope::base_only("t"); sc.policy.mark = true;
        let (out, _) = apply(&rows, &classes, offsets_from_config(-25.0, -25.0).unwrap(), &sc).unwrap();
        assert_eq!(out[2].3, 0.0, "zero-advance mark must not gain or lose width");
        assert_eq!(out[2].1, -25.0);
    }
    #[test]
    fn negative_offset_advance_underflow_typed_refusal() {
        let (_g, rows, classes, _m, _o) = fixture();
        // add -105: "A" 110 -> 5 survives, "o" 100 -> -5 underflows (typed, never clamped to 0)
        assert!(matches!(apply(&rows, &classes, offsets_from_config(-105.0, 0.0).unwrap(), &Scope::base_only("t")), Err(PostMetricsError::NumericRange(id)) if id == "o"));
        // lenient: the underflow row is excluded with the stable reason, the surviving row is applied
        let (out, led) = apply_with_row_policy(&rows, &classes, offsets_from_config(-105.0, 0.0).unwrap(), &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &[]).unwrap();
        assert_eq!(out[4], rows[4], "underflow row keeps original metrics");
        assert!(matches!(led.rows.iter().find(|r| r.glyph_id == "o").unwrap().decision, Decision::Excluded("numeric range overflow")));
        assert_eq!(out[1], ("A".into(), -95.0, 20.0, 5.0));
        // overflow side still refused (positive add past MAX_ADVANCE)
        let (_g, mut rows2, classes, _m, _o) = fixture();
        rows2[1].3 = 32760.0;
        assert!(matches!(apply(&rows2, &classes, offsets_from_config(25.0, 25.0).unwrap(), &Scope::base_only("t")), Err(PostMetricsError::NumericRange(_))));
    }
    #[test]
    fn signed_i16_bounds_checked_never_clamped() {
        // lsb result below i16::MIN is a typed refusal, not a clamp
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows[1].1 = -100.0; // an already-negative lsb is legal in a font
        rows[1].3 = 33000.0; rows[4].3 = 33000.0; // keep advances in range so only the lsb bound fires
        assert!(matches!(apply(&rows, &classes, offsets_from_config(MIN_OFFSET, 0.0).unwrap(), &Scope::base_only("t")), Err(PostMetricsError::NumericRange(id)) if id == "A"));
        // exactly at i16::MIN is accepted
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows[1].1 = -1.0; rows[1].3 = 33000.0; rows[4].3 = 33000.0;
        let (out, _) = apply(&rows, &classes, offsets_from_config(MIN_OFFSET + 1.0, 0.0).unwrap(), &Scope::base_only("t")).unwrap();
        assert_eq!(out[1].1, -32768.0);
        // rsb below i16::MIN is a typed refusal (hhea min_rsb is i16)
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows[1].2 = -100.0; rows[1].3 = 33000.0; rows[4].3 = 33000.0;
        assert!(matches!(apply(&rows, &classes, offsets_from_config(0.0, MIN_OFFSET).unwrap(), &Scope::base_only("t")), Err(PostMetricsError::NumericRange(id)) if id == "A"));
    }
    #[test]
    fn signed_offsets_multi_class_scope() {
        let (_g, rows, classes, _m, _o) = fixture();
        let all = ScopePolicy { base: true, space: true, notdef: true, mark: true, kerning_letters: false };
        let (out, led) = apply(&rows, &classes, offsets_from_config(-10.0, -20.0).unwrap(), &Scope::new(all, "t")).unwrap();
        assert_eq!(led.applied(), vec![".notdef", "A", "acute", "space", "o"]);
        assert_eq!(out[0], (".notdef".into(), -10.0, -20.0, 470.0));
        assert_eq!(out[3], ("space".into(), -10.0, -20.0, 220.0));
        assert_eq!(out[2], ("acute".into(), -10.0, -20.0, 0.0));
        // class subset: base+space only
        let bs = ScopePolicy { base: true, space: true, notdef: false, mark: false, kerning_letters: false };
        let (_out, led) = apply(&rows, &classes, offsets_from_config(-10.0, -20.0).unwrap(), &Scope::new(bs, "t")).unwrap();
        assert_eq!(led.applied(), vec!["A", "space", "o"]);
        // negative offset with the token-bound kerning_letters scope still fails closed without an allow-list
        let kl = ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: true };
        assert!(matches!(apply(&rows, &classes, offsets_from_config(-1.0, 0.0).unwrap(), &Scope::new(kl, "t")), Err(PostMetricsError::KerningLettersWithoutSelection)));
    }
    #[test]
    fn scope_allow_exclude_unknown_mark() {
        let (_g, rows, classes, _m, _o) = fixture();
        let off = offsets_from_config(1.0, 1.0).unwrap();
        let mut s = Scope::base_only("test"); s.exclude.insert("A".into()); s.exclude.insert("o".into());
        let (out, led) = apply(&rows, &classes, off, &s).unwrap();
        assert_eq!(out, rows); assert!(led.applied().is_empty());
        let mut s = Scope::base_only("test"); s.allow = Some(["nope".to_string()].into());
        assert_eq!(apply(&rows, &classes, off, &s).unwrap_err(), PostMetricsError::UnknownScopeGlyph("nope".into()));
        let mut s = Scope::base_only("test"); s.policy.mark = true;
        let (out, _) = apply(&rows, &classes, off, &s).unwrap();
        assert_eq!(out[2].3, 0.0, "mark advance stays 0"); assert_eq!(out[2].1, 1.0);
    }
    #[test]
    fn inventory_binding_typed_errors() {
        let order: Vec<String> = [".notdef", "A", "acute", "space"].iter().map(|s| s.to_string()).collect();
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        let good = vec![(65, 1), (0x301, 2), (32, 3)];
        let c = bind_classes(&order, &good, &inv, &BTreeSet::new()).unwrap();
        assert_eq!(c.iter().map(|x| x.1).collect::<Vec<_>>(), vec![GlyphClass::Notdef, GlyphClass::Base, GlyphClass::Mark, GlyphClass::Space]);
        assert_eq!(bind_classes(&order, &[(65, 1), (0x301, 2)], &inv, &BTreeSet::new()).unwrap_err(), PostMetricsError::SpaceNotInFont { codepoint: 32 });
        let inv_ns = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: None };
        assert_eq!(bind_classes(&order, &[(65, 1), (0x301, 2)], &inv_ns, &BTreeSet::new()).unwrap_err(), PostMetricsError::MissingCodepoint("space".into()));
        assert_eq!(bind_classes(&order, &[(65, 1), (0x301, 2), (32, 3), (0xA0, 2)], &inv, &BTreeSet::new()).unwrap_err(), PostMetricsError::AmbiguousClass("acute".into()));
        assert!(bind_classes(&order, &[(65, 1), (0x301, 2), (0x302, 2), (32, 3)], &DeclaredInventory { mark_codepoints: [0x301, 0x302].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) }, &BTreeSet::new()).is_ok());
        // real Unicode Mark property: undeclared M* codepoint (Latin 0300) fail closed
        assert_eq!(bind_classes(&order, &[(65, 1), (0x301, 2), (32, 3), (0x300, 2)], &inv, &BTreeSet::new()).unwrap_err(), PostMetricsError::UndeclaredMark { codepoint: 0x300 });
        assert_eq!(bind_classes(&order, &good, &DeclaredInventory { mark_codepoints: [0x301, 0x308].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) }, &BTreeSet::new()).unwrap_err(), PostMetricsError::MarkNotInFont { codepoint: 0x308 });
        assert!(matches!(bind_classes(&order, &[(65, 9)], &inv, &BTreeSet::new()), Err(_)));
        // notdef rules
        let bad_order: Vec<String> = ["A", ".notdef"].iter().map(|s| s.to_string()).collect();
        assert_eq!(bind_classes(&bad_order, &[(65, 0)], &inv_ns, &BTreeSet::new()).unwrap_err(), PostMetricsError::NotdefNotFirst);
        let dup: Vec<String> = [".notdef", "A", ".notdef"].iter().map(|s| s.to_string()).collect();
        assert_eq!(bind_classes(&dup, &[(65, 1)], &inv_ns, &BTreeSet::new()).unwrap_err(), PostMetricsError::DuplicateNotdef);
    }
    #[test]
    fn unicode_property_not_block_tripwire() {
        // Devanagari vowel sign AA (Mc), outside the old combining blocks
        assert!(unicode_marks::is_mark(0x093E) && unicode_marks::is_mark(0x0301) && !unicode_marks::is_mark(0x0041) && !unicode_marks::is_mark(0x0020));
        let order: Vec<String> = [".notdef", "A", "devaa"].iter().map(|s| s.to_string()).collect();
        let map = vec![(65, 1), (0x93E, 2)];
        let none = DeclaredInventory { mark_codepoints: BTreeSet::new(), private_marks: BTreeSet::new(), space_codepoint: None };
        assert_eq!(bind_classes(&order, &map, &none, &BTreeSet::new()).unwrap_err(), PostMetricsError::UndeclaredMark { codepoint: 0x93E });
        let inv = DeclaredInventory::from_pinned_unicode(&map, BTreeSet::new(), None);
        assert_eq!(bind_classes(&order, &map, &inv, &BTreeSet::new()).unwrap()[2].1, GlyphClass::Mark);        // ligature readback: unmapped GSUB ligature target binds as Base; any other unmapped glyph still refuses
        let lig_order: Vec<String> = [".notdef", "A", "o", "f_i"].iter().map(|s| s.to_string()).collect();
        let lig_map: Vec<(u32, u16)> = vec![(65, 1), (111, 2)];
        let inv_plain = DeclaredInventory { mark_codepoints: BTreeSet::new(), private_marks: BTreeSet::new(), space_codepoint: None };
        let c = bind_classes(&lig_order, &lig_map, &inv_plain, &BTreeSet::from([3u16])).unwrap();
        assert_eq!(c[3].1, GlyphClass::Base, "GSUB ligature target binds as Base without a codepoint");
        assert_eq!(bind_classes(&lig_order, &lig_map, &inv_plain, &BTreeSet::new()).unwrap_err(), PostMetricsError::MissingCodepoint("f_i".into()));

        // declared non-mark rejected unless explicitly private
        let wrong = DeclaredInventory { mark_codepoints: [65].into(), private_marks: BTreeSet::new(), space_codepoint: None };
        assert_eq!(bind_classes(&order, &map, &wrong, &BTreeSet::new()).unwrap_err(), PostMetricsError::DeclaredNonMark { codepoint: 65 });
        let order2: Vec<String> = [".notdef", "pua"].iter().map(|s| s.to_string()).collect();
        let pm = DeclaredInventory::from_pinned_unicode(&[(0xE000, 1)], [0xE000].into(), None);
        assert_eq!(bind_classes(&order2, &[(0xE000, 1)], &pm, &BTreeSet::new()).unwrap()[1].1, GlyphClass::Mark);
    }
    #[test]
    fn malformed_inputs_typed_no_panic() {
        let (g, rows, classes, map, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        let before = prepare_generated(&g, &map, &rows, &meta()).unwrap();
        let after = prepare_generated(&g, &map, &applied, &meta()).unwrap();
        // truncated lsb vector
        let mut a2 = after.clone(); a2.left_side_bearings.pop();
        assert!(matches!(verify_final_frame(&before, &a2, off, &led, &classes), Err(PostMetricsError::ShapeMismatch(_))));
        let mut a3 = after.clone(); a3.glyphs.pop();
        assert!(matches!(verify_final_frame(&before, &a3, off, &led, &classes), Err(PostMetricsError::ShapeMismatch(_))));
        // classes length / order
        assert!(matches!(verify_final_frame(&before, &after, off, &led, &classes[..2]), Err(PostMetricsError::ShapeMismatch(_))));
        let mut swapped = classes.clone(); swapped.swap(1, 2);
        assert!(matches!(verify_final_frame(&before, &after, off, &led, &swapped), Err(PostMetricsError::ShapeMismatch(_))));
        // duplicate ledger row, unknown ledger glyph, short ledger
        let mut dup = led.clone(); dup.rows.push(dup.rows[0].clone());
        assert!(matches!(verify_final_frame(&before, &after, off, &dup, &classes), Err(PostMetricsError::DuplicateGlyphId(_))));
        let mut unk = led.clone(); unk.rows[0].glyph_id = "zzz".into();
        assert!(matches!(verify_final_frame(&before, &after, off, &unk, &classes), Err(PostMetricsError::UnknownScopeGlyph(_))));
        let mut short = led.clone(); short.rows.pop();
        assert!(matches!(verify_final_frame(&before, &after, off, &short, &classes), Err(PostMetricsError::ShapeMismatch(_))));
        // duplicate glyph names
        let mut dn = before.clone(); dn.glyphs[2].name = dn.glyphs[1].name.clone();
        assert!(matches!(verify_final_frame(&dn, &dn, off, &led, &classes), Err(PostMetricsError::DuplicateGlyphId(_))));
        // apply: classes shorter than rows
        assert!(matches!(apply(&rows, &classes[..2], off, &Scope::base_only("t")), Err(PostMetricsError::ShapeMismatch(_))));
    }
    #[test]
    fn clip_metadata_changes_only_vertical_and_char_range_and_verified_is_shipped() {
        let (g, rows, classes, map, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        let raw = prepare_generated(&g, &map, &applied, &meta()).unwrap();
        let clipped = crate::clip_metadata(raw.clone());
        assert_eq!(raw.left_side_bearings, clipped.left_side_bearings);
        assert_eq!(raw.mapping, clipped.mapping);
        for (a, b) in raw.glyphs.iter().zip(clipped.glyphs.iter()) { assert_eq!((&a.name, a.advance), (&b.name, b.advance)); assert_eq!(pts(&a.outline).iter().map(|p| (p.x, p.y)).collect::<Vec<_>>(), pts(&b.outline).iter().map(|p| (p.x, p.y)).collect::<Vec<_>>()); }
        assert_ne!((raw.hhea.ascender, raw.os2.first_char), (clipped.hhea.ascender, clipped.os2.first_char), "clip does change hhea/os2");
        // the verified return value IS the shipped frame: encoding it equals encoding clip(prepare(applied))
        let verified = prepare_and_structural_verify(&g, &map, &rows, &applied, &meta(), off, &led, &classes, &crate::clip_metadata).unwrap();
        assert_eq!(encode_with_layout(&verified, gpos().as_deref()).unwrap(), encode_with_layout(&clipped, gpos().as_deref()).unwrap());
    }
    #[test]
    fn tsv_escape_blocks_row_forgery() {
        assert_eq!(tsv_escape("a\tb\nc\r\\d\u{1}"), "a\\tb\\nc\\r\\\\d\\u{1}");
        let l = Ledger { rows: vec![LedgerRow { glyph_id: "x\ty\nforged\tapplied".into(), class: GlyphClass::Base, decision: Decision::Applied }], scope_note: "s\nforged".into() };
        let t = l.tsv(offsets_from_config(1.0, 1.0).unwrap());
        assert_eq!(t.lines().count(), 4, "{t}");
    }
    #[test]
    fn final_frame_prepared_every_point_including_inner_controls() {
        let (g, rows, classes, map, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        let after = prepare_and_structural_verify(&g, &map, &rows, &applied, &meta(), off, &led, &classes, &crate::clip_metadata).unwrap();
        let before = prepare_generated(&g, &map, &rows, &meta()).unwrap();
        let (b, a) = (pts(&before.glyphs[4].outline), pts(&after.glyphs[4].outline));
        assert!(b.len() >= 4);
        for (p, q) in b.iter().zip(a.iter()) { assert_eq!((q.x, q.y), (p.x + 25.0, p.y)); }
        assert_eq!(after.glyphs[1].advance, before.glyphs[1].advance + 50);
    }
    #[test]
    fn tamper_inner_control_point_is_caught_bbox_alone_would_miss() {
        let (g, rows, classes, map, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        let before = prepare_generated(&g, &map, &rows, &meta()).unwrap();
        let mut after = prepare_generated(&g, &map, &applied, &meta()).unwrap();
        if let Span::Cubic { control_one, .. } = &mut after.glyphs[4].outline.rings[0].spans[0] { control_one.x += 1.0; } else { panic!() }
        // bounds are unchanged (analytic extrema may move by <1 unit but integer-outward bounds stay equal here)
        let e = verify_final_frame(&before, &after, off, &led, &classes).unwrap_err();
        assert!(matches!(&e, PostMetricsError::Verify { reason, .. } if reason.contains("point")), "{e:?}");
        let mut applied2 = applied.clone(); applied2[1].3 += 1.0;
        assert!(matches!(prepare_and_structural_verify(&g, &map, &rows, &applied2, &meta(), off, &led, &classes, &crate::clip_metadata), Err(PostMetricsError::Verify { .. })));
    }
    #[test]
    fn real_otf_zero_zero_byte_identical_and_gpos_identical_at_25_25() {
        let (g, rows, classes, map, order) = fixture();
        let base = encode(&g, &map, &rows);
        // 0/0 path: hook skips, rows are moved through untouched => same bytes
        let (rows00, _) = apply(&rows, &classes, Offsets::none(), &Scope::base_only("test")).unwrap();
        assert_eq!(base, encode(&g, &map, &rows00));
        assert_eq!(sha256_hex(&base), sha256_hex(&encode(&g, &map, &rows)));
        // 25/25
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply(&rows, &classes, off, &Scope::base_only("test")).unwrap();
        prepare_and_structural_verify(&g, &map, &rows, &applied, &meta(), off, &led, &classes, &crate::clip_metadata).unwrap();
        let out = encode(&g, &map, &applied);
        assert_ne!(base, out);
        // GPOS table bytes identical
        let (gb, go) = (table(&base, b"GPOS").expect("GPOS base"), table(&out, b"GPOS").expect("GPOS out"));
        assert_eq!(gb, go);
        // hmtx: advance/lsb for each glyph
        let (hb, ho) = (table(&base, b"hmtx").unwrap(), table(&out, b"hmtx").unwrap());
        for (i, id) in order.iter().enumerate() {
            let (ab, lb) = (u16at(hb, 4 * i) as i64, u16at(hb, 4 * i + 2) as i16 as i64);
            let (ao, lo) = (u16at(ho, 4 * i) as i64, u16at(ho, 4 * i + 2) as i16 as i64);
            let applied_g = led.applied().contains(&id.as_str());
            assert_eq!(ao - ab, if applied_g { 50 } else { 0 }, "{id} advance");
            if g[i].rings.is_empty() { assert_eq!(lo, lb, "{id}"); } else { assert_eq!(lo - lb, if applied_g { 25 } else { 0 }, "{id} lsb"); }
        }
        // CFF readback: every point (controls included) from the encoded OTFs
        let rb = CffReader::from_bytes(&base, &sha256_hex(&base)).unwrap();
        let ro = CffReader::from_bytes(&out, &sha256_hex(&out)).unwrap();
        for (i, id) in order.iter().enumerate() {
            let (gb_, go_) = (rb.read_glyph(i as u16).unwrap().drawn(id.clone()), ro.read_glyph(i as u16).unwrap().drawn(id.clone()));
            let dx = if led.applied().contains(&id.as_str()) { 25.0 } else { 0.0 };
            let (pb, po) = (pts(&gb_), pts(&go_));
            assert_eq!(pb.len(), po.len(), "{id}");
            for (p, q) in pb.iter().zip(po.iter()) { assert_eq!((q.x, q.y), (p.x + dx, p.y), "{id}"); }
        }
    }

    const TEST_AVG: AvgWidthPolicy = AvgWidthPolicy::LegacyConstant;
    fn token(off: Offsets, approved: bool) -> Result<(ApprovedBase, Classes), PostMetricsError> {
        let (f, classes, _rows, _g, _map) = approved_font();
        let gp = gpos();
        let bytes = encode_with_layout(&f, gp.as_deref()).unwrap();
        let step = PostStep { offset: off, scope: Scope::base_only("test") };
        ApprovedBase::mint_with_step(&f, &bytes, step, gp.as_deref(), approved).map(|t| (t, classes))
    }
    fn run_pass(l: f64, r: f64) -> Result<PostPassOutput, PostMetricsError> {
        let (t, classes) = token(offsets_from_config(l, r).unwrap(), true)?;
        post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, None, TEST_AVG, &crate::clip_metadata)
    }

    #[test]
    fn base_guard_fail_mints_no_token_so_no_post_apply() {
        assert!(matches!(token(offsets_from_config(25.0, 25.0).unwrap(), false), Err(PostMetricsError::BaseGuardFailed(_))));
    }
    #[test]
    fn token_bound_to_exact_base_bytes() {
        let (f, _c, _r, _g, _m) = approved_font();
        let gp = gpos();
        let mut bytes = encode_with_layout(&f, gp.as_deref()).unwrap();
        *bytes.last_mut().unwrap() ^= 1;
        let step = PostStep { offset: offsets_from_config(25.0, 25.0).unwrap(), scope: Scope::base_only("test") };
        assert!(matches!(ApprovedBase::mint_with_step(&f, &bytes, step.clone(), gp.as_deref(), true), Err(PostMetricsError::RoundTripMismatch(_))));
        // GPOS dropped from the claimed base => different bytes => refusal
        let with = encode_with_layout(&f, gp.as_deref()).unwrap();
        assert!(ApprovedBase::mint_with_step(&f, &with, step, None, true).is_err());
    }
    #[test]
    fn token_refused_under_a_different_run_context() {
        let (t, classes) = token(offsets_from_config(25.0, 25.0).unwrap(), true).unwrap();
        assert!(matches!(post_pass_in(&t, "other-binding", t.run_config_sha256(), &classes, None, TEST_AVG, &crate::clip_metadata), Err(PostMetricsError::ContextMismatch(_))));
        assert!(matches!(post_pass_in(&t, t.context_binding(), "other-sha", &classes, None, TEST_AVG, &crate::clip_metadata), Err(PostMetricsError::ContextMismatch(_))));
        let o = post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, None, TEST_AVG, &crate::clip_metadata).unwrap();
        assert!(o.receipt.contains("context_binding\ttest-context-binding") && o.receipt.contains("run_config_sha256\ttest-run-config-sha"));
    }
    #[test]
    fn zero_zero_pass_is_typed_refusal() {
        assert!(matches!(run_pass(0.0, 0.0), Err(PostMetricsError::ZeroOffsetPass)));
    }
    #[test]
    fn four_scope_combinations_with_certificate_and_receipt() {
        for (l, r) in [(0.0, 25.0), (25.0, 0.0), (25.0, 25.0)] {
            let out = run_pass(l, r).unwrap();
            let (t, _) = token(offsets_from_config(l, r).unwrap(), true).unwrap();
            // GPOS table byte-identical, non-empty
            let (gb, go) = (sfnt_table(t.bytes(), b"GPOS").expect("GPOS base"), sfnt_table(&out.bytes, b"GPOS").expect("GPOS out"));
            assert!(!gb.is_empty()); assert_eq!(gb, go);
            let c = gap_certificate(t.bytes(), &out.bytes).unwrap();
            assert!(c.min_pair_delta >= 0);
            for k in ["guard_stage\tpre_lsb_rsb", "guard_result\tapproved", "approved_base_sha256\t", "postpass\tlsb_rsb", "final_overlap_rechecked\tfalse",
                      "final_overlap_status\tNOT_MEASURED_POST_PASS", "guard_policy\tPRE_POSTMETRICS_ONLY", "gap_monotonicity\tANALYTIC_NONDECREASING", "physical_overlap_postpass\tNOT_MEASURED"] {
                assert!(out.receipt.contains(k), "{l}/{r} missing {k}");
            }
            assert!(out.receipt.contains(t.sha256()));
        }
    }
    #[test]
    fn signed_post_pass_negative_offsets_gpos_readback_and_receipt() {
        for (l, r) in [(-25.0, 0.0), (0.0, -25.0), (-10.0, -15.0)] {
            let out = run_pass(l, r).unwrap();
            let (t, _) = token(offsets_from_config(l, r).unwrap(), true).unwrap();
            // GPOS table byte-identical (pair coordinates untouched by an ink translation/advance adjustment)
            let (gb, go) = (sfnt_table(t.bytes(), b"GPOS").expect("GPOS base"), sfnt_table(&out.bytes, b"GPOS").expect("GPOS out"));
            assert!(!gb.is_empty()); assert_eq!(gb, go, "{l}/{r} GPOS changed");
            // analytic certificate MEASURES the signed deltas (negative minimum pair delta is data, not a refusal)
            let c = gap_certificate(t.bytes(), &out.bytes).unwrap();
            assert_eq!(c.min_pair_delta, (l.min(0.0) + r.min(0.0)) as i64, "{l}/{r}");
            assert!(c.min_pair_delta < 0);
            // receipt: no monotonicity claim under signed offsets; the signed measurement is reported
            assert!(out.receipt.contains("gap_monotonicity\tNOT_CLAIMED_SIGNED"), "{l}/{r}\n{}", out.receipt);
            assert!(out.receipt.contains("gap_measurement\tANALYTIC_SIGNED"), "{l}/{r}\n{}", out.receipt);
            assert!(out.receipt.contains(&format!("gap_min_pair_delta\t{}", c.min_pair_delta)), "{l}/{r}\n{}", out.receipt);
            // hmtx advances of applied glyphs decreased by exactly l+r
            let (hb, ho) = (sfnt_table(t.bytes(), b"hmtx").unwrap(), sfnt_table(&out.bytes, b"hmtx").unwrap());
            for (i, id) in [".notdef", "A", "acute", "space", "o"].iter().enumerate() {
                let (ab, ao) = (u16at(hb, 4 * i) as i64, u16at(ho, 4 * i) as i64);
                let applied = *id == "A" || *id == "o";
                assert_eq!(ao - ab, if applied { (l + r) as i64 } else { 0 }, "{id} advance");
            }
            // independent CFF readback: every point (controls included) moved by exactly (l, 0), ink shape otherwise identical
            let rb = CffReader::from_bytes(t.bytes(), &sha256_hex(t.bytes())).unwrap();
            let ro = CffReader::from_bytes(&out.bytes, &sha256_hex(&out.bytes)).unwrap();
            for (i, id) in [".notdef", "A", "acute", "space", "o"].iter().enumerate() {
                let (gb_, go_) = (rb.read_glyph(i as u16).unwrap().drawn(id.to_string()), ro.read_glyph(i as u16).unwrap().drawn(id.to_string()));
                let dx = if *id == "A" || *id == "o" { l } else { 0.0 };
                let (pb, po) = (pts(&gb_), pts(&go_));
                assert_eq!(pb.len(), po.len(), "{id}");
                for (p, q) in pb.iter().zip(po.iter()) { assert_eq!((q.x, q.y), (p.x + dx, p.y), "{id}"); }
            }
        }
        // nonnegative run: the monotonicity claim and receipt text are unchanged
        let out = run_pass(25.0, 25.0).unwrap();
        assert!(out.receipt.contains("gap_monotonicity\tANALYTIC_NONDECREASING"), "{}", out.receipt);
        assert!(!out.receipt.contains("NOT_CLAIMED_SIGNED"));
        // mixed signs (negative L, positive R) also take the measured path when the pair delta goes negative
        let out = run_pass(-25.0, 5.0).unwrap();
        assert!(out.receipt.contains("gap_measurement\tANALYTIC_SIGNED"), "{}", out.receipt);
    }
    #[test]
    fn certificate_rejects_forged_advance_and_outline_warp_and_unrelated_font() {
        let (g, rows, _c, map, _o) = fixture();
        let base = encode(&g, &map, &rows);
        assert!(gap_certificate(&base, &base).is_ok()); // identity: delta 0
        // smaller advance, same outline: exactly what a declared negative RSB offset produces; measured, not refused
        let mut r2 = rows.clone(); r2[1].3 -= 10.0;
        let c2 = gap_certificate(&base, &encode(&g, &map, &r2)).unwrap();
        assert_eq!(c2.advance_deltas[1], -10);
        assert_eq!(c2.min_pair_delta, -10);
        // outline warp: same point count, non-uniform x change => structural refusal stands
        let mut g2 = g.clone(); g2[1] = sq("A", 10.0, 100.0);
        assert!(matches!(gap_certificate(&base, &encode(&g2, &map, &rows)), Err(PostMetricsError::Structural(m)) if m.contains("NOT_PROVEN")));
        // negative offset direction (shift left, same advance): measured signed translation, reported as data
        let mut r3 = rows.clone(); r3[1].1 -= 5.0;
        let c3 = gap_certificate(&base, &encode(&g, &map, &r3)).unwrap();
        assert_eq!(c3.translations[1], -5);
        assert_eq!(c3.min_lsb_delta, -5);
        assert_eq!(c3.min_pair_delta, -5);
    }
    #[test]
    fn exactly_one_otf_atomic_exclusive_publish() {
        let out = run_pass(25.0, 25.0).unwrap();
        let dir = std::env::temp_dir().join(format!("kni_pub_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir); std::fs::create_dir_all(&dir).unwrap();
        publish_exclusive(&dir, "font.otf", &out.bytes).unwrap();
        assert!(matches!(publish_exclusive(&dir, "font.otf", &out.bytes), Err(PostMetricsError::Publish(_))));
        let names: Vec<String> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert_eq!(names, vec!["font.otf".to_string()]);
        assert_eq!(std::fs::read(dir.join("font.otf")).unwrap(), out.bytes);
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn set_u16(b: &mut [u8], tag: &[u8; 4], rel: usize, v: u16) {
        let n = u16at(b, 4) as usize;
        for i in 0..n { let r = 12 + 16 * i; if &b[r..r + 4] == tag { let off = u32::from_be_bytes(b[r + 8..r + 12].try_into().unwrap()) as usize; b[off + rel..off + rel + 2].copy_from_slice(&v.to_be_bytes()); return; } }
        panic!("no table");
    }
    #[test]
    fn short_or_compressed_hmtx_is_not_proven() {
        let (g, rows, _c, map, _o) = fixture();
        let base = encode(&g, &map, &rows);
        let n = g.len() as u16;
        // compressed: numberOfHMetrics < glyph count (trailing glyphs would share the last advance)
        let mut c = base.clone(); set_u16(&mut c, b"hhea", 34, n - 1);
        assert!(matches!(gap_certificate(&base, &c), Err(PostMetricsError::Structural(m)) if m.contains("NOT_PROVEN")));
        assert!(matches!(gap_certificate(&c, &base), Err(PostMetricsError::Structural(m)) if m.contains("NOT_PROVEN")));
        // short: numberOfHMetrics claims more records than the hmtx table holds
        let mut sh = base.clone(); set_u16(&mut sh, b"hhea", 34, n + 3);
        assert!(matches!(gap_certificate(&base, &sh), Err(PostMetricsError::Structural(m)) if m.contains("NOT_PROVEN")));
        // truncated table length in the directory
        let mut tr = base.clone();
        let cnt = u16at(&tr, 4) as usize;
        for i in 0..cnt { let r = 12 + 16 * i; if &tr[r..r + 4] == b"hmtx" { tr[r + 12..r + 16].copy_from_slice(&6u32.to_be_bytes()); } }
        assert!(matches!(gap_certificate(&base, &tr), Err(PostMetricsError::Structural(m)) if m.contains("NOT_PROVEN")));
    }
    #[test]
    fn xavgcharwidth_policy_derived_mean_and_legacy_constant() {
        let (f, classes, _rows, _g, _map) = approved_font();
        let gp = gpos();
        let bytes = encode_with_layout(&f, gp.as_deref()).unwrap();
        let step = PostStep { offset: offsets_from_config(25.0, 25.0).unwrap(), scope: Scope::base_only("test") };
        let t = ApprovedBase::mint_with_step(&f, &bytes, step, gp.as_deref(), true).unwrap();
        // LegacyConstant: untouched (500), labelled
        let o0 = post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, None, AvgWidthPolicy::LegacyConstant, &crate::clip_metadata).unwrap();
        assert_eq!(o0.font.os2.average_width, 500);
        assert!(o0.receipt.contains("xavgcharwidth\t500\tUNCHANGED_LEGACY_CONSTANT\tLegacyConstant"));
        // DerivedMean over every population/rounding: exact integer mean of the FINAL hmtx advances, read back from the bytes
        for (pop, rnd) in [(AvgPopulation::AllGlyphs, AvgRounding::Floor), (AvgPopulation::AllGlyphs, AvgRounding::Ceil), (AvgPopulation::AllGlyphs, AvgRounding::HalfUp), (AvgPopulation::NonzeroAdvance, AvgRounding::Floor)] {
            let pol = AvgWidthPolicy::DerivedMean { population: pop, rounding: rnd };
            let o = post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, None, pol, &crate::clip_metadata).unwrap();
            let adv: Vec<u64> = hmtx_advances(&o.bytes).unwrap().into_iter().map(|a| a as u64).filter(|a| pop == AvgPopulation::AllGlyphs || *a != 0).collect();
            let (sum, cnt) = (adv.iter().sum::<u64>(), adv.len() as u64);
            let want = match rnd { AvgRounding::Floor => sum / cnt, AvgRounding::Ceil => (sum + cnt - 1) / cnt, AvgRounding::HalfUp => (2 * sum + cnt) / (2 * cnt) } as i16;
            assert_eq!(o.font.os2.average_width, want);
            assert_eq!(u16at(sfnt_table(&o.bytes, b"OS/2").unwrap(), 2) as i16, want);
            assert!(o.receipt.contains(&format!("xavgcharwidth\t{want}\tderived_after_hmtx\t{}", pol.label())));
            assert_ne!(want, 500);
            // stale value (the legacy constant) is refused by the aggregate check
            let mut stale = o.font.clone(); stale.os2.average_width = 500;
            assert!(verify_aggregates(pol, &f, &stale, &crate::clip_metadata).is_err());
        }
    }
    #[test]
    fn avg_nonzero_floor_excludes_zero_advance_marks_and_empty_population_is_zero() {
        let (mut f, _c, _r, _g, _m) = approved_font();
        let pol = AvgWidthPolicy::DerivedMean { population: AvgPopulation::NonzeroAdvance, rounding: AvgRounding::Floor };
        let all = AvgWidthPolicy::DerivedMean { population: AvgPopulation::AllGlyphs, rounding: AvgRounding::Floor };
        // fixture: .notdef 500, A 110, acute(mark) 0, space 250, o 100 => nonzero mean floor(960/4)=240, all-glyph floor(960/5)=192
        let adv: Vec<u16> = f.glyphs.iter().map(|g| g.advance).collect();
        assert!(adv.contains(&0) && adv.len() == 5);
        let base = f.clone();
        assert_eq!(avg_width_for(pol, &base, &f).unwrap().0, 240);
        assert_eq!(avg_width_for(all, &base, &f).unwrap().0, 192);
        // empty nonzero population => 0 (matches os2_consistency: all-zero advances require average 0)
        for g in f.glyphs.iter_mut() { g.advance = 0; }
        assert_eq!(avg_width_for(pol, &base, &f).unwrap().0, 0);
        // i16 overflow refused (checked): mean above i16::MAX
        for g in f.glyphs.iter_mut() { g.advance = u16::MAX; }
        assert!(avg_width_for(pol, &base, &f).is_err());
        // legacy: untouched
        assert_eq!(avg_width_for(AvgWidthPolicy::LegacyConstant, &base, &f).unwrap().0, base.os2.average_width);
    }
    #[test]
    fn allow_list_is_token_bound_narrows_configured_scope_and_never_widens() {
        let (f, classes, _r, _g, _m) = approved_font();
        let order: Vec<String> = f.glyphs.iter().map(|x| x.name.clone()).collect();
        let gp = gpos(); let bytes = encode_with_layout(&f, gp.as_deref()).unwrap();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let base_pol = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        let t = ApprovedBase::mint_with_step(&f, &bytes, PostStep { offset: off, scope: Scope::new(base_pol, "t") }, gp.as_deref(), true).unwrap();
        // fixture GPOS: nonzero pairs A<->o only; selection is derived from the token's own bytes
        let (tb, sel) = crate::kern_scope::select_for_token(&t, &classes).unwrap();
        assert_eq!(sel.allow, ["A".to_string(), "o".to_string()].into());
        let out = post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, Some(&tb), TEST_AVG, &crate::clip_metadata).unwrap();
        assert_eq!(out.ledger.applied(), vec!["A", "o"]);
        for (i, n) in order.iter().enumerate() {
            let (ab, ao) = (u16at(sfnt_table(t.bytes(), b"hmtx").unwrap(), 4 * i), u16at(sfnt_table(&out.bytes, b"hmtx").unwrap(), 4 * i));
            assert_eq!(ao as i32 - ab as i32, if n == "A" || n == "o" { 50 } else { 0 }, "{n}"); // space, notdef, mark untouched
        }
        // an allow-set minted for ANOTHER baseline is refused (no arbitrary / foreign allow)
        let mut f2 = f.clone(); f2.glyphs[1].advance += 1;
        let b2 = encode_with_layout(&f2, gp.as_deref()).unwrap();
        let t2 = ApprovedBase::mint_with_step(&f2, &b2, PostStep { offset: off, scope: Scope::new(base_pol, "t") }, gp.as_deref(), true).unwrap();
        assert!(matches!(post_pass_in(&t2, t2.context_binding(), t2.run_config_sha256(), &classes, Some(&tb), TEST_AVG, &crate::clip_metadata), Err(PostMetricsError::ContextMismatch(_))));
        // never widens: space-only class policy + allow {A,o} => only the allowed glyphs that the class scope admits (none of A/o) => EmptyKernedLetterSelection? no: allow is intersected with nothing; class scope excludes Base
        let sp = ScopePolicy { base: false, space: true, notdef: false, mark: false, kerning_letters: false };
        let t3 = ApprovedBase::mint_with_step(&f, &bytes, PostStep { offset: off, scope: Scope::new(sp, "t") }, gp.as_deref(), true).unwrap();
        let (tb3, _) = crate::kern_scope::select_for_token(&t3, &classes).unwrap();
        let o3 = post_pass_in(&t3, t3.context_binding(), t3.run_config_sha256(), &classes, Some(&tb3), TEST_AVG, &crate::clip_metadata).unwrap();
        assert!(o3.ledger.applied().is_empty());
    }
    #[test]
    fn kerning_letters_policy_applies_only_to_allowed_base_glyphs_and_fails_closed() {
        let (f, classes, rows, g, map) = approved_font();
        let _ = (g, map);
        let kl = ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: true };
        assert!(!kl.is_empty() && !kl.includes(GlyphClass::Base));
        let off = offsets_from_config(25.0, 25.0).unwrap();
        // no allow-list => typed refusal, nothing moves
        assert!(matches!(apply(&rows, &classes, off, &Scope::new(kl, "t")), Err(PostMetricsError::KerningLettersWithoutSelection)));
        // allow-list: only the allowed Base glyph moves; space/.notdef/mark never even if listed? (listed non-Base stays excluded by class)
        let mut sc = Scope::new(kl, "t"); sc.allow = Some(["A".to_string(), "space".to_string(), "acute".to_string(), ".notdef".to_string()].into());
        let (_o, led) = apply(&rows, &classes, off, &sc).unwrap();
        assert_eq!(led.applied(), vec!["A"]);
        // through the real pass: policy kerning_letters + allow {A}
        let gp = gpos(); let bytes = encode_with_layout(&f, gp.as_deref()).unwrap();
        let t = ApprovedBase::mint_with_step(&f, &bytes, PostStep { offset: off, scope: Scope::new(kl, "t") }, gp.as_deref(), true).unwrap();
        assert!(post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, None, TEST_AVG, &crate::clip_metadata).is_err());
        let (tb, _) = crate::kern_scope::select_for_token(&t, &classes).unwrap();
        let out = post_pass_in(&t, t.context_binding(), t.run_config_sha256(), &classes, Some(&tb), TEST_AVG, &crate::clip_metadata).unwrap();
        assert_eq!(out.ledger.applied(), vec!["A", "o"]);
    }
    #[test]
    fn publish_set_is_transactional_and_never_overwrites() {
        let dir = std::env::temp_dir().join(format!("kni_set_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir); std::fs::create_dir_all(&dir).unwrap();
        let count = |d: &std::path::Path| std::fs::read_dir(d).unwrap().count();
        // second name already exists => first claim rolled back, existing untouched, no temps
        std::fs::write(dir.join("ledger.tsv"), b"old").unwrap();
        let e = publish_set_exclusive(&dir, &[("font.otf", b"F"), ("ledger.tsv", b"L")]).unwrap_err();
        assert!(matches!(&e, PostMetricsError::Publish(m) if m.contains("claim ledger.tsv") && !m.contains("CLEANUP FAILED")));
        assert!(!dir.join("font.otf").exists()); assert_eq!(std::fs::read(dir.join("ledger.tsv")).unwrap(), b"old"); assert_eq!(count(&dir), 1);
        // first name already exists => nothing else created
        std::fs::remove_file(dir.join("ledger.tsv")).unwrap(); std::fs::write(dir.join("font.otf"), b"oldfont").unwrap();
        assert!(publish_set_exclusive(&dir, &[("font.otf", b"F"), ("ledger.tsv", b"L")]).is_err());
        assert_eq!(std::fs::read(dir.join("font.otf")).unwrap(), b"oldfont"); assert_eq!(count(&dir), 1);
        // success: both claimed, no temps
        std::fs::remove_file(dir.join("font.otf")).unwrap();
        let ok = publish_set_exclusive(&dir, &[("font.otf", b"F"), ("ledger.tsv", b"L")]).unwrap();
        assert_eq!(ok.len(), 2); assert_eq!(count(&dir), 2);
        // invalid / duplicate / dot names refused
        for bad in [vec![("a", &b"x"[..]), ("a", &b"y"[..])], vec![("../x", &b"x"[..])], vec![(".h", &b"x"[..])], vec![]] { assert!(publish_set_exclusive(&dir, &bad).is_err()); }
        assert_eq!(count(&dir), 2);
        // a stale temp name collision => create_new fails, nothing claimed, the stale temp is not ours and is left alone
        std::fs::remove_file(dir.join("font.otf")).unwrap(); std::fs::remove_file(dir.join("ledger.tsv")).unwrap();
        let stale = dir.join(format!(".font.otf.tmp-{}-0", std::process::id())); std::fs::write(&stale, b"stale").unwrap();
        assert!(publish_set_exclusive(&dir, &[("font.otf", b"F")]).is_err());
        assert_eq!(std::fs::read(&stale).unwrap(), b"stale"); assert!(!dir.join("font.otf").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
    #[test]
    fn publish_failure_leaves_no_temp_and_no_target() {
        let dir = std::env::temp_dir().join(format!("kni_pubf_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        // missing directory: typed error, nothing created
        assert!(matches!(publish_exclusive(&dir, "font.otf", b"x"), Err(PostMetricsError::Publish(_))));
        assert!(!dir.exists());
        // existing target: Err, target untouched, no temp left
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("font.otf"), b"keep").unwrap();
        assert!(publish_exclusive(&dir, "font.otf", b"new").is_err());
        assert_eq!(std::fs::read(dir.join("font.otf")).unwrap(), b"keep");
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn approved_font() -> (NativeFontInput, Classes, Vec<Row>, Vec<DrawnGlyph>, Vec<(u32, u16)>) {
        let (g, rows, classes, map, _o) = fixture();
        let f = crate::clip_metadata(prepare_generated(&g, &map, &rows, &meta()).unwrap());
        (f, classes, rows, g, map)
    }
    // ---- GUARD-SCAN P2: row-level exclusion (RowPolicy::ExcludeInvalidRows) ----
    fn fixture_bad_metric() -> (Vec<Row>, Classes) {
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows[1].1 = f64::NAN; // glyph "A": invalid lsb
        (rows, classes)
    }
    #[test]
    fn strict_apply_still_refuses_bad_rows() {
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (rows, classes) = fixture_bad_metric();
        assert!(matches!(apply(&rows, &classes, off, &Scope::base_only("t")), Err(PostMetricsError::InvalidMetric(id)) if id == "A"));
    }
    #[test]
    fn strict_delegates_bit_identical_to_row_policy_default() {
        let (_g, rows, classes, _m, _o) = fixture();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (a, la) = apply(&rows, &classes, off, &Scope::base_only("t")).unwrap();
        let (b, lb) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::RefuseStage, &[]).unwrap();
        assert_eq!(a, b); assert_eq!(la.tsv(off), lb.tsv(off));
        assert_eq!(RowPolicy::default(), RowPolicy::RefuseStage);
    }
    #[test]
    fn lenient_invalid_metric_row_excluded_others_applied() {
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (rows, classes) = fixture_bad_metric();
        let (out, led) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &[]).unwrap();
        // excluded row passes through with ORIGINAL metrics (NaN-aware compare)
        assert!(out[1].0 == rows[1].0 && out[1].1.is_nan() && out[1].2 == rows[1].2 && out[1].3 == rows[1].3);
        // every other in-scope row applied
        assert_eq!(out[4], ("o".into(), 45.0, 45.0, 150.0));
        // typed ledger: one row per glyph, exclusion reason stable
        assert_eq!(led.rows.len(), rows.len());
        let a = led.rows.iter().find(|r| r.glyph_id == "A").unwrap();
        assert!(matches!(a.decision, Decision::Excluded("invalid metric")));
        // scope base_only: "o" applied, "A" excluded; .notdef/space/acute out of scope
        assert_eq!(led.rows.iter().filter(|r| r.decision == Decision::Applied).count(), 1);
        assert!(matches!(led.rows.iter().find(|r| r.glyph_id == "o").unwrap().decision, Decision::Applied));
        assert!(led.tsv(off).contains("excluded	invalid metric"));
    }
    #[test]
    fn lenient_numeric_range_row_excluded() {
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows[1].3 = 32760.0; // advance + offsets would exceed MAX_ADVANCE
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (out, led) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &[]).unwrap();
        assert_eq!(out[1], rows[1]);
        assert!(matches!(led.rows.iter().find(|r| r.glyph_id == "A").unwrap().decision, Decision::Excluded("numeric range overflow")));
        assert!(matches!(apply(&rows, &classes, off, &Scope::base_only("t")), Err(PostMetricsError::NumericRange(_))));
    }
    #[test]
    fn lenient_bind_classes_unbound_glyph_excluded() {
        let (_g, rows, _classes, _m, order) = fixture();
        // mapping without glyph "o": strict bind refuses, lenient binds placeholder + exclusion
        let map = vec![(65, 1), (0x301, 2), (32, 3)];
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        assert!(matches!(bind_classes(&order, &map, &inv, &BTreeSet::new()), Err(PostMetricsError::MissingCodepoint(id)) if id == "o"));
        let (classes, excl) = bind_classes_with_policy(&order, &map, &inv, RowPolicy::ExcludeInvalidRows, &BTreeSet::new()).unwrap();
        assert_eq!(classes.len(), order.len());
        assert_eq!(excl, vec![BindExclusion { glyph_id: "o".into(), reason: "class unbound: no codepoint" }]);
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (out, led) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &excl).unwrap();
        assert_eq!(out[4], rows[4], "unbound glyph keeps original metrics");
        assert!(matches!(led.rows.iter().find(|r| r.glyph_id == "o").unwrap().decision, Decision::Excluded("class unbound: no codepoint")));
        assert!(matches!(apply(&rows, &classes, off, &Scope::base_only("t")), Ok(_)), "strict apply does not know the bind exclusion; class placeholder binds as Base");
    }
    #[test]
    fn lenient_ambiguous_class_unbound() {
        let (_g, rows, _c, _m, order) = fixture();
        // glyph "o" mapped from two codepoints with conflicting classes (one space, one base)
        let map = vec![(65, 1), (0x301, 2), (32, 3), (111, 4), (0x20AC, 4)];
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        let inv2 = DeclaredInventory { space_codepoint: Some(0x20AC), ..inv };
        assert!(matches!(bind_classes(&order, &map, &inv2, &BTreeSet::new()), Err(PostMetricsError::AmbiguousClass(id)) if id == "o"));
        let (classes, excl) = bind_classes_with_policy(&order, &map, &inv2, RowPolicy::ExcludeInvalidRows, &BTreeSet::new()).unwrap();
        assert_eq!(excl, vec![BindExclusion { glyph_id: "o".into(), reason: "class unbound: ambiguous class" }]);
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (out, led) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &excl).unwrap();
        assert_eq!(out[4], rows[4]);
        assert!(matches!(led.rows.iter().find(|r| r.glyph_id == "o").unwrap().decision, Decision::Excluded("class unbound: ambiguous class")));
    }
    #[test]
    fn lenient_structural_refusals_stay_refusals() {
        // duplicate glyph id and unknown scope glyph are NOT lowered in lenient mode
        let (_g, mut rows, classes, _m, _o) = fixture();
        rows.push(rows[1].clone());
        let off = offsets_from_config(25.0, 25.0).unwrap();
        assert!(matches!(apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &[]), Err(PostMetricsError::DuplicateGlyphId(_))));
        let (_g, rows, classes, _m, _o) = fixture();
        let mut sc = Scope::base_only("t"); sc.exclude = ["nosuch".into()].into_iter().collect();
        assert!(matches!(apply_with_row_policy(&rows, &classes, off, &sc, RowPolicy::ExcludeInvalidRows, &[]), Err(PostMetricsError::UnknownScopeGlyph(_))));
    }
    #[test]
    fn lenient_excluded_row_verifies_unmoved() {
        // full prepare+verify path: a bind-excluded glyph is verified as unmoved
        let (g, rows, _c, map, order) = fixture();
        let map_short: Vec<(u32, u16)> = map.iter().filter(|(cp, _)| *cp != 111).cloned().collect();
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        let (classes, excl) = bind_classes_with_policy(&order, &map_short, &inv, RowPolicy::ExcludeInvalidRows, &BTreeSet::new()).unwrap();
        let off = offsets_from_config(25.0, 25.0).unwrap();
        let (applied, led) = apply_with_row_policy(&rows, &classes, off, &Scope::base_only("t"), RowPolicy::ExcludeInvalidRows, &excl).unwrap();
        let after = prepare_and_structural_verify(&g, &map, &rows, &applied, &meta(), off, &led, &classes, &crate::clip_metadata).unwrap();
        let before = prepare_generated(&g, &map, &rows, &meta()).unwrap();
        // "o" (index 4) unmoved, "A" (index 1) moved by +25
        assert_eq!(after.glyphs[4].advance, before.glyphs[4].advance);
        assert_eq!(after.glyphs[1].advance, before.glyphs[1].advance + 50);
    }

    // ---- NV-5 acceptance evidence (next-version work list item 5; design doc 2026-10-16-static-lsb-rsb-overlay-design.md).
    // Descriptive before/after of the overlay over the FULL ordered-pair space, measured from the shipped byte
    // streams only (hmtx advances + CFF-readback translations, the gap_certificate source of truth). The
    // certificate reports minima only; the descriptive layer quantifies every ordered pair: the facing-gap delta
    // of (a, b) is d_adv(a) + dx(b) - dx(a) = dRSB(a) + dLSB(b), so under a base-only scope the pair space
    // partitions into applied x applied (uniform L + R), applied x excluded (R), excluded x applied (L) and
    // excluded x excluded (0). A single uniform shift per partition IS the preservation of relative gap
    // differences between pairs; the GPOS kern layer is pair-relative and unchanged. All integer arithmetic.
    /// 7-glyph pair-space fixture: 4 Base glyphs (one an unmapped GSUB ligature target), 1 Mark, Space, .notdef.
    fn pairspace_fixture() -> (NativeFontInput, Classes, Vec<String>, Option<Vec<u8>>) {
        let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, sq("A", 10.0, 90.0), sq("V", 5.0, 115.0),
            curve("o"), sq("acute", 0.0, 30.0), DrawnGlyph { glyph_id: "space".into(), rings: vec![] }, sq("f_i", 20.0, 120.0)];
        let rows: Vec<Row> = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), 10.0, 20.0, 110.0), ("V".into(), 5.0, 15.0, 130.0),
            ("o".into(), 20.0, 20.0, 100.0), ("acute".into(), 0.0, 0.0, 0.0), ("space".into(), 0.0, 0.0, 250.0), ("f_i".into(), 20.0, 50.0, 170.0)];
        let order: Vec<String> = glyphs.iter().map(|g| g.glyph_id.clone()).collect();
        let map = vec![(65, 1), (86, 2), (111, 3), (0x301, 4), (32, 5)];
        let lig = BTreeSet::from([6u16]);
        let inv = DeclaredInventory { mark_codepoints: [0x301].into(), private_marks: BTreeSet::new(), space_codepoint: Some(32) };
        let classes = bind_classes(&order, &map, &inv, &lig).unwrap();
        let gp = write_kern_pairpos1_or_omit(7, &[PairKern { left: 1, right: 2, x_advance: -30 }, PairKern { left: 2, right: 1, x_advance: -10 },
            PairKern { left: 3, right: 6, x_advance: 15 }]).unwrap();
        let font = crate::clip_metadata(prepare_generated(&glyphs, &map, &rows, &meta()).unwrap());
        (font, classes, order, gp)
    }
    /// Facing-gap deltas over the full ordered-pair space, bucketed by (left applied, right applied).
    fn pair_space_buckets(cert: &GapCertificate, applied: &BTreeSet<&str>, order: &[String]) -> BTreeMap<(bool, bool), Vec<i64>> {
        let mut m: BTreeMap<(bool, bool), Vec<i64>> = BTreeMap::new();
        for (a, ga) in order.iter().enumerate() {
            for (b, gb) in order.iter().enumerate() {
                m.entry((applied.contains(ga.as_str()), applied.contains(gb.as_str()))).or_default()
                    .push(cert.advance_deltas[a] + cert.translations[b] - cert.translations[a]);
            }
        }
        m
    }
    #[test]
    fn overlay_on_pair_space_descriptive_before_after() {
        let (font, classes, order, gp) = pairspace_fixture();
        let base_bytes = encode_with_layout(&font, gp.as_deref()).unwrap();
        // owner-declared trial convention (+25/+25) and a declared negative pass; both measured, never assumed
        for (l, r) in [(25.0, 25.0), (-10.0, -15.0)] {
            let off = offsets_from_config(l, r).unwrap();
            let step = PostStep { offset: off, scope: Scope::base_only("pairspace") };
            let token = ApprovedBase::mint_with_step(&font, &base_bytes, step, gp.as_deref(), true).unwrap();
            let out = post_pass_in(&token, token.context_binding(), token.run_config_sha256(), &classes, None, TEST_AVG, &crate::clip_metadata).unwrap();
            // typed ledger: one row per glyph, class + decision typed; the applied set is the four Base glyphs
            let applied: BTreeSet<&str> = out.ledger.applied().into_iter().collect();
            assert_eq!(out.ledger.rows.len(), 7, "{l}/{r}");
            assert_eq!(applied, BTreeSet::from(["A", "V", "o", "f_i"]), "{l}/{r}");
            let tsv = out.ledger.tsv(off);
            for row in ["A\tBase\tapplied\t", "V\tBase\tapplied\t", "o\tBase\tapplied\t", "f_i\tBase\tapplied\t",
                        "space\tSpace\texcluded\tspace is not propagated automatically",
                        ".notdef\tNotdef\texcluded\t.notdef is not propagated automatically",
                        "acute\tMark\texcluded\tmark is not propagated automatically"] {
                assert!(tsv.contains(row), "{l}/{r} ledger missing {row}");
            }
            // GPOS pair layer byte-identical
            assert_eq!(sfnt_table(&base_bytes, b"GPOS"), sfnt_table(&out.bytes, b"GPOS"), "{l}/{r}");
            // descriptive pair space, measured on the shipped bytes
            let cert = gap_certificate(&base_bytes, &out.bytes).unwrap();
            assert_eq!(cert.glyphs, 7, "{l}/{r}");
            let b = pair_space_buckets(&cert, &applied, &order);
            let (li, ri) = (l as i64, r as i64);
            let (tt, te, et, ee) = (&b[&(true, true)], &b[&(true, false)], &b[&(false, true)], &b[&(false, false)]);
            assert_eq!((tt.len(), te.len(), et.len(), ee.len()), (16, 12, 12, 9), "{l}/{r} partition sizes");
            assert!(tt.iter().all(|&d| d == li + ri), "{l}/{r} applied x applied must shift by exactly L+R");
            assert!(te.iter().all(|&d| d == ri), "{l}/{r} applied x excluded must shift by exactly R");
            assert!(et.iter().all(|&d| d == li), "{l}/{r} excluded x applied must shift by exactly L");
            assert!(ee.iter().all(|&d| d == 0), "{l}/{r} excluded x excluded must not move");
            // totals over all 49 ordered pairs: exact sum, min, max
            let all: Vec<i64> = [tt, te, et, ee].into_iter().flat_map(|v| v.iter().copied()).collect();
            assert_eq!(all.len(), 49, "{l}/{r}");
            assert_eq!(all.iter().sum::<i64>(), 16 * (li + ri) + 12 * ri + 12 * li, "{l}/{r} pair-delta sum");
            let (mn, mx) = (*all.iter().min().unwrap(), *all.iter().max().unwrap());
            assert_eq!(mn, cert.min_pair_delta, "{l}/{r} certificate minimum equals the pair-space minimum");
            assert_eq!((mn, mx), if li + ri >= 0 { (0, li + ri) } else { (li + ri, 0) }, "{l}/{r} pair-space extremes");
            // per-glyph measured deltas: advance += L+R and translation += L exactly on the applied set, 0 elsewhere
            for (i, g) in order.iter().enumerate() {
                let on = applied.contains(g.as_str());
                assert_eq!(cert.advance_deltas[i], if on { li + ri } else { 0 }, "{l}/{r} advance delta {g}");
                assert_eq!(cert.translations[i], if on { li } else { 0 }, "{l}/{r} translation {g}");
            }
        }
    }

}
