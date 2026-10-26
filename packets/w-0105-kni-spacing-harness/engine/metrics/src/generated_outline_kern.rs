//! generated_outline_kern.rs — K3 code line: residual kern from solver pair positions.
//!
//! Path in crate: `engine/metrics/src/generated_outline_kern.rs` (sibling of
//! `outline_spacing.rs` [K1] and `self_anchored_spacing.rs` [K2]).
//! lib.rs / Cargo.toml registration: chief architect only (no parallel write).
//!
//! Pipeline: SpacingSolution.pair positions (origin frame) → residual kern
//! (`residual = origin_distance - left.advance`, same origin frame) → explicit
//! integer export rounding → ACTUAL GPOS writer path
//! (`engine/tooling/kern_writer/kern_gpos_writer.py`:
//!  write_kern(original: bytes, declared: list[dict], classes=None);
//!  CLI flags --original --declared --output --receipt [--classes]).
//!
//! Hard rules baked in:
//! - Captured/source-font GPOS is NEVER an input here. No captured-font
//!   extractor path exists in this module.
//! - No VERIFIED label on model-produced candidates: `Ready` means only
//!   "passed the finite/full-ink/overlap guards, ready for the writer".
//! - FRAME BINDING (chief architect frame rule, field/refusal enforced):
//!   native export places each glyph translated by
//!   `translate_x = lsb - ink_xmin` with `advance = solution.advance`, and the
//!   shipped pair distance is `export_distance = round(left.advance)
//!   + export_value` (explicit integer rounding). ALL guard geometry is
//!   measured in THAT frame: both glyphs translated, at the rounded export
//!   distance. A pair whose left OR right frame cannot be built (missing or
//!   non-finite lsb / advance / ink xmin) is REFUSED, never silently shipped.
//! - Per-pair no-surprise overlap guard: the wall gap is re-measured from the
//!   FULL outlines (every ink interval per row, counters kept — not just the
//!   two outer edges, no fixed band constant). Overlaps never land in the
//!   export list silently; they come out as a separate `OverlapHold` status
//!   for the policy/architect layer to confirm as intentional or send back.
//!   (mechanisms.rs is a contact initializer, not a finished kern engine;
//!   air.rs's outer-edges+band view is not used as geometric truth here.)
//! - The solver's wall_gap is cross-checked against the same translated
//!   geometry at the EXACT origin_distance; disagreement is held, not guessed.
//! - Zero-residual pairs: the Python writer preserves an explicit 0; dropping
//!   them is an explicit caller choice (`ExportGeometry::drop_zero_residual`).

use std::collections::{BTreeMap, BTreeSet};

use crate::outline_spacing::OutlineProfile;
use crate::signed_clearance::{evidence_at, safe_integer_distance};
#[cfg(test)]
use crate::signed_clearance::interval_overlap_depth;
use crate::self_anchored_spacing::SpacingSolution;

/// Evidence class stamped on every row this module produces (writer contract:
/// one of parsed|derived|declared; model-produced residuals are 'derived').
pub const EVIDENCE_CLASS_DERIVED: &str = "derived";
/// Tier-2 fallback rows: guard-verified, never solver-optimal (explicit
/// fallback class in the ledger; ships in GPOS like any ready row).
pub const EVIDENCE_CLASS_FALLBACK: &str = "fallback_guard_verified";

// ---------------------------------------------------------------------------
// Explicit integer export rounding
// ---------------------------------------------------------------------------

/// Explicit export rounding for GPOS integer values: half away from zero,
/// clamped to the int16 range the PairPos XAdvance value record carries
/// (the Python writer refuses non-int16 `written`; the clamp is reported in
/// the receipt and the pair is rejected instead of shipping a clamped value).
/// Returns (rounded, clamped?).
pub fn round_export_units(v: f64) -> (i16, bool) {
    let r = (v.abs() + 0.5).floor().copysign(v);
    if r > i16::MAX as f64 {
        (i16::MAX, true)
    } else if r < i16::MIN as f64 {
        (i16::MIN, true)
    } else {
        (r as i16, false)
    }
}

pub const ROUNDING_MODE_LABEL: &str = "half-away-from-zero, int16 range check";

/// Guard agreement tolerance shared by every kern-path site (eval_pair,
/// the negative-origin class evaluator, and the serial test oracle): the
/// floating error of the gap model scaled by the magnitudes involved. The
/// literal set is pinned by kern-scope-literals.tsv; new sites call this.
fn kern_agree_tol(wall_gap: f64, min_gap: f64, origin_distance: f64) -> f64 {
    let scale = 1.0 + wall_gap.abs() + min_gap.abs() + origin_distance.abs();
    1024.0 * f64::EPSILON * scale
}

// ---------------------------------------------------------------------------
// Export geometry (explicit inputs, no hidden stylistic constants)
// ---------------------------------------------------------------------------

/// Which frame the guard profiles live in. Caller-bound (chief architect
/// frame decision 12:17): the exported-spacing glyph-origin frame
/// (`origin_distance = left.advance + residual`, sidebearings applied) is the
/// semantic truth on the KNI path, so all guard profiles are `ExportedB`
/// there — each glyph's ink is translated by `x_translation = lsb - ink_xmin`
/// before measurement. `RawGenerated` exists for raw generated outlines
/// (no export translation); do NOT canonize it as solver truth.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProfileFrame {
    /// Raw generated outlines: measured untranslated.
    RawGenerated,
    /// Exported-spacing frame: measured with both glyphs translated by
    /// lsb - ink_xmin. The KNI path's frame.
    ExportedB,
}

/// Explicit geometric export options. These are guard tolerances, not
/// stylistic clamps; they are recorded verbatim in the receipt.
#[derive(Debug, Clone)]
pub struct ExportGeometry {
    /// Frame the guard profiles live in (caller-bound).
    pub profile_frame: ProfileFrame,
    /// Target UPM; profiles and spacing must already be in this unit frame
    /// (outline geometry frame is font units, common UPM per the K1/K2
    /// contract).
    pub upm: u16,
    /// Post-kern wall gap below `-overlap_tolerance_units` (or any true ink
    /// intersection) is held out of the export list as `OverlapHold`.
    pub overlap_tolerance_units: f64,
    /// Pairs whose residual rounds to 0 are dropped from the export list but
    /// counted in the receipt ledger. When false, an explicit 0 is emitted
    /// and the writer preserves it.
    pub drop_zero_residual: bool,
    /// LEGACY KNOB, RETAINED FOR API STABILITY — NO LONGER GATES MATCHING.
    /// Row alignment is delegated to K1 `align_pair_rows` (span-overlap
    /// segmentation; micro-segments below K1's MERGE_GUARD_UNITS are merged
    /// there). The old semantics — "rows sharing vertical span are compared,
    /// rows farther apart are not" — are preserved exactly and strengthened:
    /// span overlap is the exact version of the old ±tolerance window (on a
    /// common grid they coincide for any tolerance below the row pitch, and
    /// span overlap stays correct when each profile's grid anchors at its
    /// own min_y). The value is still recorded in the receipt.
    pub row_align_tolerance_units: f64,
}

// ---------------------------------------------------------------------------
// Frame binding (chief architect frame rule)
// ---------------------------------------------------------------------------

/// The glyph-origin frame a residual is expressed in. Native export places
/// the glyph with `x_translation = lsb - ink_xmin` and `advance = advance`;
/// guard geometry is measured only after BOTH glyphs' frames are applied.
#[derive(Debug, Clone, Copy)]
pub struct GlyphFrame {
    pub lsb: f64,
    pub ink_xmin: f64,      // OutlineProfile.bounds[0]
    pub advance: f64,
    pub x_translation: f64, // = lsb - ink_xmin
}

impl GlyphFrame {
    fn new(lsb: f64, ink_xmin: f64, advance: f64) -> Option<GlyphFrame> {
        if lsb.is_finite() && ink_xmin.is_finite() && advance.is_finite() {
            Some(GlyphFrame { lsb, ink_xmin, advance, x_translation: lsb - ink_xmin })
        } else {
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Exact glyph ID mapping (P3 static adaptation)
// ---------------------------------------------------------------------------

/// Exact glyph-name → glyph-ID binding for the emitted font. The wrapper
/// supplies the font's glyph order (glyph ID = index); K3 never invents,
/// guesses, or reorders IDs. A name absent from the order resolves to a
/// typed `None` at the row — never a silent skip or a wrong ID.
#[derive(Debug, Clone)]
pub struct GlyphIdMap {
    ids: BTreeMap<String, u16>,
    /// Names in glyph-ID order, kept for receipts/audits.
    order: Vec<String>,
}

/// Construction refusals for GlyphIdMap (typed, no silent fallback).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GlyphIdMapError {
    /// More glyphs than the u16 glyph-ID space can hold.
    TooManyGlyphs(usize),
    /// The same name appeared twice in the supplied order.
    DuplicateName(String),
}

impl GlyphIdMap {
    /// `glyph_order` = the emitted font's glyph names in glyph-ID order
    /// (index = glyph ID; .notdef sits wherever the font has it, usually 0).
    pub fn from_glyph_order(glyph_order: &[String]) -> Result<GlyphIdMap, GlyphIdMapError> {
        if glyph_order.len() > u16::MAX as usize + 1 {
            return Err(GlyphIdMapError::TooManyGlyphs(glyph_order.len()));
        }
        let mut ids = BTreeMap::new();
        for (i, name) in glyph_order.iter().enumerate() {
            if ids.insert(name.clone(), i as u16).is_some() {
                return Err(GlyphIdMapError::DuplicateName(name.clone()));
            }
        }
        Ok(GlyphIdMap { ids, order: glyph_order.to_vec() })
    }

    /// Convenience: derive the order from the same emitted profiles handed
    /// to `generate_residual_kern`. CALLER'S ASSERTION: `profiles` are in
    /// the emitted font's glyph order — K3 cannot verify font internals.
    pub fn from_profiles(profiles: &[OutlineProfile]) -> Result<GlyphIdMap, GlyphIdMapError> {
        let order: Vec<String> = profiles.iter().map(|p| p.glyph_id.clone()).collect();
        GlyphIdMap::from_glyph_order(&order)
    }

    /// Exact ID for a glyph name; `None` = not in the emitted font.
    pub fn id(&self, name: &str) -> Option<u16> {
        self.ids.get(name).copied()
    }

    pub fn len(&self) -> usize {
        self.order.len()
    }

    pub fn is_empty(&self) -> bool {
        self.order.is_empty()
    }
}

// ---------------------------------------------------------------------------
// Output ledger (explicit effective pair ledger)
// ---------------------------------------------------------------------------

/// Disposition of one candidate pair. `Ready` is NOT a verification claim —
/// it only means the guards passed and the pair may enter the GPOS writer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PairDisposition {
    /// Guards passed; exported to the GPOS writer path.
    Ready,
    /// Post-kern ink overlap beyond tolerance AT THE SHIPPED (translated,
    /// rounded) distance, or a solver/measured gap mismatch. Held OUT of the
    /// export; the policy/architect layer decides whether the overlap is
    /// intentional. This is the separate output status for intentional
    /// overlaps — nothing overlapping ships silently.
    /// Also the bucket for the typed `CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN`
    /// hold (registry: docs/conc/ledger-schema.md, code
    /// `containment_compensation`): a frame defect, not an intentional
    /// overlap; the reason string disambiguates.
    OverlapHold,
    /// Non-finite numbers, unknown glyph, missing ink geometry, or broken
    /// frame binding (either side).
    Rejected,
}

impl PairDisposition {
    /// `status` string for the writer's declared-row contract.
    pub fn status_str(self) -> &'static str {
        match self {
            PairDisposition::Ready => "ready",
            PairDisposition::OverlapHold => "overlap_hold",
            PairDisposition::Rejected => "rejected",
        }
    }
}

/// Typed hold reason (registry: docs/conc/ledger-schema.md, code
/// `containment_compensation`): the post-solve containment compensation
/// pushed this pair's origin below zero. The pair is held as `OverlapHold`,
/// never clamped, and ships kernless.
pub const CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN: &str = "containment_compensation_negative_origin";

#[derive(Debug, Clone)]
pub struct GeneratedKernPair {
    pub left: String,
    pub right: String,
    /// Exact residual in units: `origin_distance - left.advance`.
    pub residual_units: f64,
    /// Integer value handed to the GPOS writer (explicit rounding).
    pub export_value: i16,
    /// Shipped pair distance: `round(left.advance) + export_value`.
    pub export_distance: i32,
    /// Frame bindings; `None` only on early rejection. BOTH must exist for a
    /// pair to reach Ready.
    pub left_frame: Option<GlyphFrame>,
    pub right_frame: Option<GlyphFrame>,
    /// Solver-reported wall gap (from PairPosition, kept for cross-check).
    pub solver_wall_gap_units: f64,
    /// Caller-bound frame (ExportGeometry::profile_frame) measurement at
    /// the EXACT origin_distance — like-for-like cross-check input vs the
    /// solver's wall_gap; never the guard.
    pub measured_gap_at_origin: Option<f64>,
    /// Same caller-bound frame at the ROUNDED export distance — the
    /// geometry the font actually ships; the overlap guard's basis.
    pub measured_gap_at_export: Option<f64>,
    /// Row-height-weighted mean gap at the exact origin / at the shipped
    /// distance (optical-integral view; K1 weight contract).
    pub weighted_mean_gap_at_origin: Option<f64>,
    pub weighted_mean_gap_at_export: Option<f64>,
    /// True ink intersection at the shipped (translated, rounded) distance.
    pub ink_intersects: bool,
    /// True interval intersection at the EXACT solver origin (caller-bound
    /// frame) and at the shipped integer distance, kept as SEPARATE receipts
    /// (chief 23:39): the export-frame integer hit never erases an
    /// exact-origin hit. None when rejected before measurement.
    pub origin_interval_hit: Option<bool>,
    pub export_interval_hit: Option<bool>,
    pub optical_cost: f64,
    pub disposition: PairDisposition,
    /// Why the pair was held or rejected; empty for Ready.
    pub note: String,
}

/// One declared row for the actual GPOS writer
/// (`kern_gpos_writer.py --declared`): keys left, right, requested, written,
/// status, reason, evidence_class — plus the frame binding the wrapper needs
/// (not forwarded into the writer JSON unless the wrapper chooses to).
/// `written = None` pairs carry a reason and are ledger-only; the writer
/// refuses to store them, so the wrapper should pass only `written = Some`
/// rows as store candidates and keep the rest for the receipt.
#[derive(Debug, Clone)]
pub struct WriterDeclaredRow {
    pub left: String,
    pub right: String,
    /// Exact requested residual (finite f64; writer accepts int or float).
    pub requested: f64,
    /// Final integer for the writer; None => reason explains why unbound.
    pub written: Option<i16>,
    pub status: &'static str,
    pub reason: String,
    pub evidence_class: &'static str, // always EVIDENCE_CLASS_DERIVED here
    // Frame binding (wrapper-side, architect frame rule):
    pub left_x_translation: Option<f64>,
    pub left_advance: Option<f64>,
    pub right_x_translation: Option<f64>,
    pub right_advance: Option<f64>,
    /// Shipped pair distance the guard measured at; None when unbound.
    pub export_distance: Option<i32>,
}

/// P3: one Ready residual row with the exact glyph-ID binding of the
/// emitted font attached. Name fields stay authoritative for the Python
/// writer path; the `*_gid` fields serve the native GPOS path. `None` IDs
/// are a typed refusal (glyph not in the emitted font) visible to the
/// wrapper — never a silent drop or remap.
#[derive(Debug, Clone)]
pub struct ReadyResidualRow {
    pub left: String,
    pub right: String,
    pub left_gid: Option<u16>,
    pub right_gid: Option<u16>,
    /// Exact residual (same value the Python writer sees as `requested`).
    pub requested: f64,
    /// Final integer value (same value the Python writer sees as `written`).
    pub written: i16,
    /// Shipped pair distance the guard measured at.
    pub export_distance: i32,
}

impl ReadyResidualRow {
    /// True when both glyph IDs are exactly bound.
    pub fn fully_bound(&self) -> bool {
        self.left_gid.is_some() && self.right_gid.is_some()
    }
}

/// Support-only provenance: pins + policy receipt. Never an input.
#[derive(Debug, Clone)]
pub struct KernReceipt {
    pub upm: u16,
    pub source_pins: Vec<String>,
    pub policy_derivation: String,
    pub rounding: String,
    pub overlap_tolerance_units: f64,
    pub ready: usize,
    pub fallback_ready: usize,
    pub overlap_held: usize,
    pub rejected: usize,
    pub dropped_zero: usize,
    pub clamps_refused: usize,
    /// From K2: false exactly when the solver truncated pairs via max_pairs
    /// (excluded_pairs non-empty) — the ledger then covers a subset.
    pub solution_complete: bool,
    /// K2 ledger counts, passed through (self pairs skipped by construction;
    /// below-epsilon pairs dropped at the noise floor).
    pub excluded_self_pairs: usize,
    pub excluded_below_epsilon: usize,
    pub excluded_pairs_count: usize,
    /// K2 closing-patch ledger count (pairs whose geometry could not be
    /// measured), passed through.
    pub excluded_unmeasurable: usize,
    /// Pairs whose rounded integer distance collided and was replaced by a verified safe integer.
    pub export_adjusted: usize,
    /// Frame the guard measurements were made in.
    pub profile_frame: ProfileFrame,
    /// Row alignment backend in use (K1 delegation receipt).
    pub alignment: String,
}

/// The explicit effective pair ledger: exactly which pairs ship, which are
/// held, which are rejected, and why.
#[derive(Debug, Clone)]
pub struct GeneratedKern {
    pub ready: Vec<GeneratedKernPair>,
    /// Tier-2 fallback pairs that passed the same guard: an explicit
    /// fallback_guard_verified class, never mixed into solver-ready rows.
    pub fallback_ready: Vec<GeneratedKernPair>,
    pub overlap_holds: Vec<GeneratedKernPair>,
    pub rejected: Vec<GeneratedKernPair>,
    pub dropped_zero: Vec<GeneratedKernPair>,
    /// Pairs whose exact solver origin collided and that shipped at the first exact-clear lattice integer of the existing walk (ordinary and
    /// below-epsilon). Their entries are in the ready/fallback_ready/dropped_zero buckets; this is the typed, disjoint class K_all.
    pub lattice_resolved: Vec<LatticeClear>,
    pub receipt: KernReceipt,
}

impl GeneratedKern {
    /// Declared rows for the actual writer path, in solver order. Ready
    /// pairs have `written = Some(export_value)` (explicit 0 preserved unless
    /// the caller set `drop_zero_residual`); held/rejected pairs have
    /// `written = None` + reason so nothing binds silently.
    pub fn writer_declared_rows(&self) -> Vec<WriterDeclaredRow> {
        let mut rows = Vec::new();
        let mut push = |p: &GeneratedKernPair, written: Option<i16>, evidence_class: &'static str| {
            rows.push(WriterDeclaredRow {
                left: p.left.clone(),
                right: p.right.clone(),
                requested: p.residual_units,
                written,
                status: p.disposition.status_str(),
                reason: p.note.clone(),
                evidence_class,
                left_x_translation: p.left_frame.map(|f| f.x_translation),
                left_advance: p.left_frame.map(|f| f.advance),
                right_x_translation: p.right_frame.map(|f| f.x_translation),
                right_advance: p.right_frame.map(|f| f.advance),
                export_distance: written.map(|_| p.export_distance),
            });
        };
        for p in &self.ready {
            push(p, Some(p.export_value), EVIDENCE_CLASS_DERIVED);
        }
        for p in &self.fallback_ready {
            push(p, Some(p.export_value), EVIDENCE_CLASS_FALLBACK);
        }
        for p in self.overlap_holds.iter().chain(self.rejected.iter()) {
            push(p, None, EVIDENCE_CLASS_DERIVED);
        }
        rows
    }

    /// P3: Ready pairs only — the residual rows that ship — each bound to
    /// the exact glyph IDs of the emitted font via `map`. Rows with an
    /// unbound glyph keep their names and carry `None` IDs (typed refusal);
    /// nothing is dropped or remapped silently.
    pub fn ready_residual_rows(&self, map: &GlyphIdMap) -> Vec<ReadyResidualRow> {
        self.ready
            .iter()
            .chain(self.fallback_ready.iter())
            .map(|p| ReadyResidualRow {
                left: p.left.clone(),
                right: p.right.clone(),
                left_gid: map.id(&p.left),
                right_gid: map.id(&p.right),
                requested: p.residual_units,
                written: p.export_value,
                export_distance: p.export_distance,
            })
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Full-outline wall gap measurement (the full-outline shaping connection)
// ---------------------------------------------------------------------------

/// Nearest-wall horizontal gap between two full outlines in the EXPORT frame:
/// each glyph's ink is translated by its `x_translation = lsb - ink_xmin`,
/// and the right glyph's origin sits at `pair_origin_distance` in the left
/// glyph's frame. For the shipped-geometry guard, call this with
/// `pair_origin_distance = round(left.advance) + export_value`.
///
/// ALIGNMENT: delegated to K1 `align_pair_rows` — the exact piecewise-
/// constant segmentation over the union of both row grids (span overlap,
/// never exact f64 y equality; no resampling, no new approximation). Rows
/// where either side carries no ink are skipped (no wall to measure there;
/// a gap row cannot collide).
///
/// TOLERANCE SEMANTICS (preservation): the retired internal matcher compared
/// row pairs within ±`_row_align_tolerance` of each other's y. Span-overlap
/// segmentation preserves that intent exactly — rows sharing vertical span
/// are compared, rows not sharing span are not — and strengthens it: it is
/// the exact limit of the window as tolerance approaches the row pitch, and
/// it stays correct when each profile's grid anchors at its own min_y
/// (per-glyph anchoring, where a fixed f64-y window can silently miss every
/// row). The parameter is retained for API stability only; the value is
/// recorded in the receipt via ExportGeometry.
///
/// Uses EVERY ink interval of every aligned segment (counters included), not
/// just the two outer edges and no fixed band constant: for each right-ink
/// interval, the gap is measured to the nearest left wall to its left; a
/// true interval intersection at any segment sets `ink_intersects`.
///
/// Gap measurement over K1-aligned rows (`align_pair_rows` span-overlap
/// segmentation). Per K1: row/segment height is weight-bearing, so beside
/// the min gap (the guard's basis) the weighted mean gap is carried as the
/// optical-integral view, weighted by the aligned segment heights.
#[derive(Debug, Clone, Copy)]
pub struct GapMeasure {
    /// Nearest-wall minimum gap across all compared segments (guard basis).
    pub min_gap: f64,
    /// True ink intersection at any compared segment.
    pub intersects: bool,
    /// Segment-height-weighted mean of per-interval nearest-wall gaps.
    pub weighted_mean_gap: f64,
}

/// Returns None if no segment carries ink on both sides (no shared coverage).
///
/// Delegates to the shared signed collision primitive (`signed_clearance`),
/// the same model the K2 solver uses: piecewise-linear outer walls on the
/// union grid for the signed min gap, plus true interval intersection
/// (counters included) as separate collision evidence. A positive min gap
/// never masks an intersection and is never read as penetration depth.
pub fn measure_full_outline_gap(
    left: &OutlineProfile,
    right: &OutlineProfile,
    left_translation: f64,
    right_translation: f64,
    pair_origin_distance: f64,
    _row_align_tolerance: f64, // retained; matching delegated (see above)
) -> Option<GapMeasure> {
    let e = evidence_at(left, right, left_translation, right_translation, pair_origin_distance)?;
    Some(GapMeasure {
        min_gap: e.clearance.min_gap,
        // TRUE ink intersection only: a negative signed clearance without an
        // interval hit (reversed pair, no overlap) is still caught by the
        // signed-gap hold path; intersects must not conflate the two
        // (reversed-order regression).
        intersects: e.interval_hit,
        weighted_mean_gap: e.clearance.weighted_mean_gap,
    })
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

/// Build the effective pair ledger from a SpacingSolution.
///
/// `profiles` must carry the full-outline geometry for every glyph named in
/// the solution's pairs; pairs without usable full ink geometry are Rejected
/// (no-surprise guard: nothing ships on outer-wall-only or missing
/// geometry).
pub fn generate_residual_kern(
    solution: &SpacingSolution,
    profiles: &[OutlineProfile],
    geo: &ExportGeometry,
) -> GeneratedKern {
    generate_residual_kern_jobs(solution, profiles, geo, 1)
}

/// Per-worker stack RESERVE for the pair pool (virtual; pages are committed
/// on use), matching the stage-1/stage-2 convention.
const KERN_WORKER_STACK_BYTES: usize = 16 << 20;

/// Jobs-aware residual-kern production (P1-PAR, the W14 PROFILES-PAR
/// pattern): one job per solved pair, folded into the kern ledger in pair
/// order. Every per-pair input is immutable (the spacing/profile lookup
/// maps, the export geometry); every shared output (the ready /
/// fallback_ready / overlap_holds / dropped_zero / rejected buckets, the
/// receipt counters, the source-pin set, the PROBE-BITS diagnostics) is
/// written exactly once, in pair order, by the reduce. Bit-identity
/// contract: for any job count the emitted GeneratedKern equals the former
/// serial loop value for value (proved by the oracle tests in this file,
/// which keep the old loop verbatim); even the PROBE-BITS stderr lines are
/// buffered per pair and emitted in pair order. jobs == 1 runs inline on
/// the calling thread. A pool that cannot be built is a panic, never a
/// silent serial fallback.
pub fn generate_residual_kern_jobs(
    solution: &SpacingSolution,
    profiles: &[OutlineProfile],
    geo: &ExportGeometry,
    jobs: usize,
) -> GeneratedKern {
    generate_residual_kern_jobs_exact(solution, profiles, None, geo, jobs)
}

/// Stage-4 residual kern with an optional EXACT measurement authority (assignment relayed by Main, 8:19 PM): when `exact` is supplied every
/// stage-4 decision point (collision evidence, measured gap, the agree check's reference wall gap, the export-lattice search)
/// reads the exact slab rows of the glyphs' flattened rings instead of the sampled profile rows. A pair whose glyphs lack exact
/// geometry is refused with a typed reason, never measured on the sampled model (no mixed frames). `None` is the sampled path,
/// bit-identical to before.
pub fn generate_residual_kern_jobs_exact(
    solution: &SpacingSolution,
    profiles: &[OutlineProfile],
    exact: Option<&ExactMap>,
    geo: &ExportGeometry,
    jobs: usize,
) -> GeneratedKern {
    generate_residual_kern_jobs_below_eps(solution, profiles, exact, &BTreeSet::new(), geo, jobs).0
}

/// Typed record of a pair whose exact solver origin collided and that shipped at the first exact-clear integer of the existing walk (am. 47; ordinary and below-epsilon, provenance in the below_epsilon field). The solver residual and the shipped lattice
/// integer are carried separately; nothing here is a margin or a tolerance.
#[derive(Debug, Clone)]
pub struct LatticeClear {
    pub left: String,
    pub right: String,
    /// Solver placement (origin_distance) and its exact penetration depth there (> agree_tol, which is why the early hold would fire).
    pub solver_origin: f64,
    pub depth_at_origin: f64,
    /// Lattice start d0 = lattice_start(origin, min_gap) and its signed shift from the solver origin.
    pub d0: i32,
    /// SHIPPED integer distance (first exact-clear lattice integer of the existing walk from d0) and the walk steps taken (d_shipped - d0; 0 = d0 itself).
    pub d_shipped: i32,
    pub walk_steps: i32,
    /// Signed shift of the shipped distance from the solver origin (d_shipped - solver_origin).
    pub shift: f64,
    pub gap_at_origin: f64,
    pub gap_at_d0: f64,
    pub gap_at_shipped: f64,
    /// `true` when the pair was a below-epsilon candidate (provenance); `false` for an ordinary exact-origin-collision pair.
    pub below_epsilon: bool,
    /// Solver residual (origin - advance) and the SHIPPED integer export value (d_shipped - round(advance)); they differ by construction.
    pub solver_residual: f64,
    pub export_value: i16,
    /// The pair's own solver target gap (None when absent); `gap_at_shipped >= target` is NOT assumed, see `target_met`.
    pub pair_target: Option<f64>,
}

impl LatticeClear {
    /// Contact class at the SHIPPED distance, reported as measured: exactly 0.0 is TOUCH (neither labelled clean nor a collision), > 0 is POSITIVE_GAP.
    pub fn contact_class(&self) -> &'static str { if self.gap_at_shipped == 0.0 { "TOUCH_GAP_0" } else { "POSITIVE_GAP" } }
    /// `Some(met)` against the pair's own target, None when the pair carries no target.
    pub fn target_met(&self) -> Option<bool> { self.pair_target.map(|t| self.gap_at_shipped >= t) }
}

/// What the below-epsilon candidate set did in stage 4. The classes are MUTUALLY EXCLUSIVE and sum to `candidates`:
/// candidates = dropped_no_exact_collision + resolved_on_lattice + ready + fallback_ready + held + rejected + dropped_zero.
/// `ready`, `fallback_ready` and `dropped_zero` here are candidates that did NOT resolve on the lattice (a resolution is counted once, in K).
#[derive(Debug, Clone, Default)]
pub struct BelowEpsilonStage4 {
    /// Candidates in `below_eps` that were evaluated.
    pub candidates: usize,
    /// (left, right, natural min_gap) dropped: natural placement exact-clear, the stage-3 epsilon drop stands (typed, no row).
    pub dropped_no_exact_collision: Vec<(String, String, f64)>,
    /// K: resolved on the lattice (walk step 0 included) (their entries are in the ordinary ready/fallback_ready/dropped_zero buckets).
    pub resolved_on_lattice: Vec<LatticeClear>,
    pub ready: usize,
    pub fallback_ready: usize,
    pub held: usize,
    pub rejected: usize,
    pub dropped_zero: usize,
}

impl BelowEpsilonStage4 {
    /// Machine check of the partition (no class counted twice, none missing).
    pub fn partition_closed(&self) -> bool {
        self.candidates == self.dropped_no_exact_collision.len() + self.resolved_on_lattice.len()
            + self.ready + self.fallback_ready + self.held + self.rejected + self.dropped_zero
    }
}

/// Note token of an ORDINARY pair whose exact origin collided and that shipped at the first exact-clear lattice integer (am. 47).
pub const EXACT_ORIGIN_COLLISION_RESOLVED_ON_LATTICE: &str = "reason=EXACT_ORIGIN_COLLISION_RESOLVED_ON_LATTICE";

/// Note token of a below-epsilon candidate resolved on the lattice (am. 47 unified walk; walk_steps above 0 included).
pub const BELOW_EPSILON_RESIDUAL_RESOLVED_ON_LATTICE: &str = "reason=BELOW_EPSILON_RESIDUAL_RESOLVED_ON_LATTICE";

/// Note token carried by every below-epsilon candidate pair whose natural placement collides exactly (it then follows the ordinary
/// stage-4 rules: cleaned exact residual or typed hold).
pub const BELOW_EPSILON_RESIDUAL_COLLIDING: &str = "reason=BELOW_EPSILON_RESIDUAL_COLLIDING";

/// Stage-4 residual kern with the below-epsilon candidate set (slice 5). Pairs whose (left,right) is in `below_eps` are the
/// stage-3 below-epsilon drops returned by `solve_below_epsilon_candidates`: each is eligible only if the natural placement
/// (origin = left advance) collides under the same measurement authority; otherwise it is dropped with no row and reported in
/// `BelowEpsilonStage4`. Every other pair follows the unchanged path (empty set == `generate_residual_kern_jobs_exact`, bit-identical).
pub fn generate_residual_kern_jobs_below_eps(
    solution: &SpacingSolution,
    profiles: &[OutlineProfile],
    exact: Option<&ExactMap>,
    below_eps: &BTreeSet<(String, String)>,
    geo: &ExportGeometry,
    jobs: usize,
) -> (GeneratedKern, BelowEpsilonStage4) {
    let spacing: BTreeMap<&str, (f64, f64)> = solution
        .glyphs
        .iter()
        .map(|g| (g.glyph_id.as_str(), (g.lsb, g.advance)))
        .collect();
    let profs: BTreeMap<&str, &OutlineProfile> = profiles
        .iter()
        .map(|p| (p.glyph_id.as_str(), p))
        .collect();

    let mut out = GeneratedKern {
        ready: Vec::new(),
        fallback_ready: Vec::new(),
        overlap_holds: Vec::new(),
        rejected: Vec::new(),
        dropped_zero: Vec::new(),
        lattice_resolved: Vec::new(),
        receipt: KernReceipt {
            upm: geo.upm,
            source_pins: Vec::new(),
            policy_derivation: solution.policy_derivation.clone(),
            rounding: ROUNDING_MODE_LABEL.to_string(),
            overlap_tolerance_units: geo.overlap_tolerance_units,
            ready: 0,
            fallback_ready: 0,
            overlap_held: 0,
            rejected: 0,
            dropped_zero: 0,
            clamps_refused: 0,
            solution_complete: solution.complete,
            excluded_self_pairs: solution.excluded_self_pairs,
            excluded_below_epsilon: solution.excluded_below_epsilon,
            excluded_pairs_count: solution.excluded_pairs.len(),
            excluded_unmeasurable: solution.excluded_unmeasurable,
            export_adjusted: 0,
            profile_frame: geo.profile_frame,
            alignment: "K1 align_pair_rows span-overlap (row matching delegated; legacy tolerance knob recorded, not gating)".to_string(),
        },
    };

    let pair_list: Vec<(&crate::self_anchored_spacing::PairPosition, bool)> = solution
        .pairs
        .iter()
        .map(|p| (p, false))
        .chain(solution.fallback_pairs.iter().map(|p| (p, true)))
        .collect();

    let eval = |(idx, &(pair, is_fallback)): (usize, &(&crate::self_anchored_spacing::PairPosition, bool))| {
        eval_pair(idx, pair, is_fallback, below_eps.contains(&(pair.left.clone(), pair.right.clone())), &spacing, &profs, exact, geo)
    };
    let outcomes: Vec<PairOutcome> = if jobs <= 1 {
        pair_list.iter().enumerate().map(eval).collect()
    } else {
        use rayon::prelude::*;
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(jobs)
            .stack_size(KERN_WORKER_STACK_BYTES)
            .build()
            .expect("residual-kern worker pool could not be built");
        pool.install(|| pair_list.par_iter().enumerate().map(eval).collect())
    };

    // kern-reduce-seq: fold outcomes in pair order into the buckets, the
    // receipt counters and the source-pin set. The only place shared state
    // is written; the value layout is exactly what the former in-loop code
    // wrote. The driver returns outcomes already in pair order (indexed
    // collect); this VERIFIES that: outcome k must carry idx == k and every
    // index 0..n must be covered exactly once.
    let mut pins = std::collections::BTreeSet::new();
    let mut be = BelowEpsilonStage4::default();
    let mut next = 0usize;
    for o in outcomes {
        assert!(o.idx == next, "residual-kern reduce: outcome index {} where {} was expected (duplicate, gap or out-of-order)", o.idx, next);
        next += 1;
        for p in o.pins { pins.insert(p); }
        out.receipt.clamps_refused += o.clamps_refused;
        out.receipt.export_adjusted += o.export_adjusted;
        if let Some(line) = o.probe { eprintln!("{line}"); }
        let is_cand = below_eps.contains(&(pair_list[o.idx].0.left.clone(), pair_list[o.idx].0.right.clone()));
        let cleared = o.lattice.is_some();
        if let Some(l) = o.lattice { if is_cand { be.resolved_on_lattice.push(l.clone()); } out.lattice_resolved.push(l); }
        match o.kind {
            PairKind::Ready(e) => { out.receipt.ready += 1; out.ready.push(e); if is_cand && !cleared { be.ready += 1; } }
            PairKind::FallbackReady(e) => { out.receipt.fallback_ready += 1; out.fallback_ready.push(e); if is_cand && !cleared { be.fallback_ready += 1; } }
            PairKind::OverlapHold(e) => { out.receipt.overlap_held += 1; out.overlap_holds.push(e); if is_cand { be.held += 1; } }
            PairKind::DroppedZero(e) => { out.receipt.dropped_zero += 1; out.dropped_zero.push(e); if is_cand && !cleared { be.dropped_zero += 1; } }
            PairKind::Rejected(e) => { out.receipt.rejected += 1; out.rejected.push(e); if is_cand { be.rejected += 1; } }
            PairKind::BelowEpsDrop(l, r, g) => { be.dropped_no_exact_collision.push((l, r, g)); }
        }
    }
    be.candidates = pair_list.iter().filter(|(p, _)| below_eps.contains(&(p.left.clone(), p.right.clone()))).count();
    assert!(next == pair_list.len(), "residual-kern reduce: {} outcomes for {} pairs (incomplete coverage)", next, pair_list.len());
    out.receipt.source_pins = pins.into_iter().collect();
    (out, be)
}

/// Exact stage-4 glyph geometry: flattened rings cut into slabs, per glyph name.
pub type ExactMap = BTreeMap<String, crate::exact_rows::ExactSlabs>;

/// One pair's measurement authority: the sampled aligned rows (unchanged path) or the exact slab rows (rebuilt per placement,
/// because crossing cuts depend on where the right glyph sits).
struct Meas<'a> {
    sampled_rows: Vec<crate::outline_spacing::AlignedRow>,
    slabs: Option<(&'a crate::exact_rows::ExactSlabs, &'a crate::exact_rows::ExactSlabs)>,
    span: f64,
    /// Set when any exact evidence came from the no-facing-wall fallback (typed evidence-source marker).
    fallback_used: std::cell::Cell<bool>,
}

/// Typed evidence-source marker appended to a pair note when stage-4 evidence used the no-facing-wall fallback.
const EVIDENCE_SOURCE_NO_FACING_WALL_FALLBACK: &str = "evidence_source=NO_FACING_WALL_FALLBACK_PAIR_CLEARANCE_ROWS";

impl<'a> Meas<'a> {
    fn new(lp: &OutlineProfile, rp: &OutlineProfile, exact: Option<&'a ExactMap>, left: &str, right: &str) -> Result<Meas<'a>, String> {
        let span = (lp.bounds[2] - lp.bounds[0]) + (rp.bounds[2] - rp.bounds[0]);
        match exact {
            None => Ok(Meas { sampled_rows: crate::outline_spacing::align_pair_rows(lp, rp), slabs: None, span, fallback_used: Default::default() }),
            Some(m) => match (m.get(left), m.get(right)) {
                (Some(a), Some(b)) => Ok(Meas { sampled_rows: Vec::new(), slabs: Some((a, b)), span, fallback_used: Default::default() }),
                _ => Err("exact ring geometry unavailable for a pair glyph (degenerate or non-finite rings); stage-4 authority fails closed".to_string()),
            },
        }
    }
    fn with_rows<T>(&self, l_tr: f64, r_tr: f64, d: f64, f: impl FnOnce(&[crate::outline_spacing::AlignedRow]) -> T) -> T {
        match self.slabs {
            Some((a, b)) => f(&crate::exact_rows::exact_aligned_rows_at(a, b, d + r_tr - l_tr)),
            None => f(&self.sampled_rows),
        }
    }
    fn ev(&self, l_tr: f64, r_tr: f64, d: f64) -> Option<crate::signed_clearance::Evidence> {
        self.with_rows(l_tr, r_tr, d, |rows| {
            if self.slabs.is_some() {
                crate::signed_clearance::exact_evidence_rows_marked(rows, l_tr, r_tr, d).map(|(e, fb)| {
                    if fb { self.fallback_used.set(true); }
                    e
                })
            } else {
                crate::signed_clearance::evidence_at_rows(rows, l_tr, r_tr, d)
            }
        })
    }
    fn depth(&self, l_tr: f64, r_tr: f64, d: f64) -> f64 {
        self.with_rows(l_tr, r_tr, d, |rows| crate::signed_clearance::interval_overlap_depth_rows(rows, l_tr, r_tr, d))
    }
    fn safe(&self, lp: &OutlineProfile, rp: &OutlineProfile, l_tr: f64, r_tr: f64, exact_d: f64, exact_clearance: f64) -> Option<i32> {
        if self.slabs.is_some() {
            crate::signed_clearance::safe_integer_distance_by(|d| self.ev(l_tr, r_tr, d), self.span, exact_d, exact_clearance)
        } else {
            safe_integer_distance(lp, rp, l_tr, r_tr, exact_d, exact_clearance)
        }
    }
    /// Reference wall gap for the agree check. Sampled path: the solver's own wall_gap. Exact path: the solver-model (facing-cell)
    /// gap recomputed on the exact rows at the origin placement, so the check never mixes a sampled reference with an exact reading.
    fn reference_wall_gap(&self, solver_wall_gap: f64, l_tr: f64, r_tr: f64, d: f64) -> Option<f64> {
        if self.slabs.is_none() {
            return Some(solver_wall_gap);
        }
        self.with_rows(l_tr, r_tr, d, |rows| {
            let cells = crate::signed_clearance::clearance_cells_constant_rows(rows, d + r_tr - l_tr);
            crate::signed_clearance::clearance_of(&cells).map(|c| c.min_gap)
        })
    }
    /// Note with the typed evidence-source marker when the fallback fed any stage-4 evidence of this pair.
    fn mark(&self, note: String) -> String {
        if self.fallback_used.get() {
            if note.is_empty() { EVIDENCE_SOURCE_NO_FACING_WALL_FALLBACK.to_string() } else { format!("{note}; {EVIDENCE_SOURCE_NO_FACING_WALL_FALLBACK}") }
        } else {
            note
        }
    }
}

/// One pair's ledger destination.
enum PairKind {
    Ready(GeneratedKernPair),
    FallbackReady(GeneratedKernPair),
    OverlapHold(GeneratedKernPair),
    DroppedZero(GeneratedKernPair),
    Rejected(GeneratedKernPair),
    /// Below-epsilon candidate whose natural placement does not collide: typed drop, no row (left, right, natural min_gap).
    BelowEpsDrop(String, String, f64),
}

/// What one pair contributed to the run ledgers, tagged with its pair index
/// so the reduce can verify exact 0..n coverage.
struct PairOutcome {
    idx: usize,
    pins: Vec<String>,
    clamps_refused: usize,
    export_adjusted: usize,
    probe: Option<String>,
    kind: PairKind,
    /// Set only when a pair resolved on the lattice (am. 47).
    lattice: Option<LatticeClear>,
}

/// Rejection record, the exact value the former `push_rejected` appended
/// (counter fold happens in the reduce).
#[allow(clippy::too_many_arguments)]
fn rejected(
    idx: usize,
    pins: Vec<String>,
    clamps_refused: usize,
    probe: Option<String>,
    pair: &crate::self_anchored_spacing::PairPosition,
    residual: f64,
    export_value: i16,
    export_distance: i32,
    left_frame: Option<GlyphFrame>,
    right_frame: Option<GlyphFrame>,
    gap_origin: Option<f64>,
    gap_export: Option<f64>,
    wmean_origin: Option<f64>,
    wmean_export: Option<f64>,
    intersects: bool,
    note: String,
) -> PairOutcome {
    PairOutcome {
        idx,
        pins,
        clamps_refused,
        export_adjusted: 0,
        probe,
        lattice: None,
        kind: PairKind::Rejected(GeneratedKernPair {
            left: pair.left.clone(),
            right: pair.right.clone(),
            residual_units: residual,
            export_value,
            export_distance,
            left_frame,
            right_frame,
            solver_wall_gap_units: pair.wall_gap,
            measured_gap_at_origin: gap_origin,
            measured_gap_at_export: gap_export,
            weighted_mean_gap_at_origin: wmean_origin,
            weighted_mean_gap_at_export: wmean_export,
            ink_intersects: intersects,
            origin_interval_hit: None,
            export_interval_hit: None,
            optical_cost: pair.optical_cost,
            disposition: PairDisposition::Rejected,
            note,
        }),
    }
}

/// Typed-hold record for a negative post-compensation origin that cannot
/// ship: the same `OverlapHold` bucket the export gate already counts as
/// unresolved, with the registry-typed reason in `note` plus the concrete
/// cause. Frames are unbound, so the gap evidence fields stay `None`.
/// Under the negative-origin class rule (see
/// `eval_negative_origin_compensated`) this hold is the residual outcome
/// for the unmeasurable or unverifiable cases only - never a silent drop.
fn held_negative_origin(
    idx: usize,
    pair: &crate::self_anchored_spacing::PairPosition,
    residual: f64,
    cause: &str,
) -> PairOutcome {
    PairOutcome {
        idx,
        pins: Vec::new(),
        clamps_refused: 0,
        export_adjusted: 0,
        probe: None,
        lattice: None,
        kind: PairKind::OverlapHold(GeneratedKernPair {
            left: pair.left.clone(),
            right: pair.right.clone(),
            residual_units: residual,
            export_value: 0,
            export_distance: 0,
            left_frame: None,
            right_frame: None,
            solver_wall_gap_units: pair.wall_gap,
            measured_gap_at_origin: None,
            measured_gap_at_export: None,
            weighted_mean_gap_at_origin: None,
            weighted_mean_gap_at_export: None,
            ink_intersects: false,
            origin_interval_hit: None,
            export_interval_hit: None,
            optical_cost: pair.optical_cost,
            disposition: PairDisposition::OverlapHold,
            note: format!(
                "{CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN}: origin_distance {:.6} below zero after containment compensation (held, never clamped; pair ships kernless); {cause}",
                pair.origin_distance
            ),
        }),
    }
}

/// Compensated negative-origin class (architect decision): a post-
/// compensation origin below zero is not per-se a frame defect - GPOS
/// carries a negative XAdvance legally. The class is decided on the
/// MEASURED geometry at the negative origin, never on the sign alone:
///
///   * tangent or clean (strict-collision depth at or below the guard's
///     own agree_tol): the pair ships as a legal negative XAdvance, with
///     the usual integer-rounding guard on the shipped distance;
///   * real collision (depth beyond agree_tol): the placement is cut at
///     the tangent (gap = 0 on the integer grid, the deterministic
///     ceil of the exact tangent distance), counted as `export_adjusted`
///     and ledgered with the typed `export_adjusted` reason - an adjusted
///     shipment, never a silent drop;
///   * anything unmeasurable or unverifiable keeps the typed
///     `containment_compensation_negative_origin` hold and ships kernless.
///
/// No new literals: the tolerance is the guard's agree_tol formula and the
/// ledger mechanism is the existing `export_adjusted` counter + reason.
/// Pure: no shared mutable state, safe on a pool worker.
fn eval_negative_origin_compensated(
    idx: usize,
    pair: &crate::self_anchored_spacing::PairPosition,
    is_fallback: bool,
    l_spacing: (f64, f64),
    r_spacing: (f64, f64),
    profs: &BTreeMap<&str, &OutlineProfile>,
    exact: Option<&ExactMap>,
    geo: &ExportGeometry,
) -> PairOutcome {
    let (l_lsb, l_adv) = l_spacing;
    let (r_lsb, r_adv) = r_spacing;
    let residual = pair.origin_distance - l_adv;
    let mut pins: Vec<String> = Vec::new();

    // Full ink geometry: without it the class cannot be measured, and an
    // unmeasurable class pair is held, never guessed.
    let (lp, rp) = match (profs.get(pair.left.as_str()), profs.get(pair.right.as_str())) {
        (Some(l), Some(r)) => (*l, *r),
        _ => return held_negative_origin(idx, pair, residual, "full-outline profile missing; legality not measurable"),
    };
    if lp.upm != geo.upm || rp.upm != geo.upm {
        return held_negative_origin(idx, pair, residual, "upm mismatch; legality not measurable");
    }
    if !(lp.ink_area > 0.0 && rp.ink_area > 0.0)
        || !lp.bounds.iter().chain(rp.bounds.iter()).all(|b| b.is_finite())
    {
        return held_negative_origin(idx, pair, residual, "empty ink or non-finite bounds; legality not measurable");
    }
    let (l_frame, r_frame) = match (
        GlyphFrame::new(l_lsb, lp.bounds[0], l_adv),
        GlyphFrame::new(r_lsb, rp.bounds[0], r_adv),
    ) {
        (Some(l), Some(r)) => (l, r),
        _ => return held_negative_origin(idx, pair, residual, "frame binding broken; legality not measurable"),
    };
    pins.push(lp.source_pin.clone());
    pins.push(rp.source_pin.clone());
    let meas = match Meas::new(lp, rp, exact, pair.left.as_str(), pair.right.as_str()) {
        Ok(m) => m,
        Err(why) => return held_negative_origin(idx, pair, residual, &why),
    };

    let (export_value, clamped_v) = round_export_units(residual);
    let (advance_rnd, clamped_a) = round_export_units(l_adv);
    if clamped_v || clamped_a {
        return held_negative_origin(idx, pair, residual, "residual or advance out of int16 range; GPOS cannot carry it");
    }
    let export_distance = advance_rnd as i32 + export_value as i32;
    let (t_l, t_r) = match geo.profile_frame {
        ProfileFrame::ExportedB => (l_frame.x_translation, r_frame.x_translation),
        ProfileFrame::RawGenerated => (0.0, 0.0),
    };
    let ev_origin = match meas.ev(t_l, t_r, pair.origin_distance) {
        Some(e) => e,
        None => return held_negative_origin(idx, pair, residual, "no shared scan-row coverage at the origin; legality not measurable"),
    };

    let ref_wall = match meas.reference_wall_gap(pair.wall_gap, t_l, t_r, pair.origin_distance) {
        Some(v) => v,
        None => return held_negative_origin(idx, pair, residual, "exact reference wall_gap not measurable (no facing wall); stage-4 authority fails closed"),
    };
    let agree_tol = kern_agree_tol(ref_wall, ev_origin.clearance.min_gap, pair.origin_distance);
    let origin_depth = if ev_origin.collides() {
        (-ev_origin.clearance.min_gap)
            .max(meas.depth(t_l, t_r, pair.origin_distance))
    } else {
        0.0
    };

    let mut adjusted = 0usize;
    let (export_value, export_distance, ev_export, note) = if origin_depth > agree_tol {
        // Real collision: cut at the tangent. The measured depth is the
        // exact rigid shift that brings the deepest contact to gap = 0;
        // the deterministic integer on the grid is its ceil (gap is
        // monotone non-decreasing in distance, so ceil never collides in
        // exact math; the re-measurement below verifies the shipped bits).
        let d_ship = (pair.origin_distance + origin_depth).ceil() as i64;
        let ev_val = d_ship - advance_rnd as i64;
        match meas.ev(t_l, t_r, d_ship as f64) {
            Some(e2) if !e2.collides() && ev_val >= i16::MIN as i64 && ev_val <= i16::MAX as i64 => {
                adjusted += 1;
                (ev_val as i16, d_ship as i32, e2, format!(
                    "export_adjusted: {CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN} collision at origin {:.6} (min_gap {:.6}, depth {:.6}) cut at tangent distance {} (gap at export {:.6})",
                    pair.origin_distance, ev_origin.clearance.min_gap, origin_depth,
                    d_ship, e2.clearance.min_gap))
            }
            _ => return held_negative_origin(idx, pair, residual, "tangent cut not verifiable on the integer grid"),
        }
    } else {
        // Tangent or clean at the negative origin: legal negative
        // XAdvance. The integer-rounding guard on the shipped distance is
        // the same arm as the generic path.
        let ev_export0 = match meas.ev(t_l, t_r, export_distance as f64) {
            Some(e) => e,
            None => return held_negative_origin(idx, pair, residual, "no shared scan-row coverage at the export distance"),
        };
        if ev_export0.collides() {
            match meas.safe(lp, rp, t_l, t_r, pair.origin_distance,
                                        ev_origin.clearance.min_gap) {
                Some(d) => {
                    let ev2 = meas.ev(t_l, t_r, d as f64);
                    let ev_val = d as i64 - advance_rnd as i64;
                    match ev2 {
                        Some(e2) if !e2.collides() && ev_val >= i16::MIN as i64 && ev_val <= i16::MAX as i64 => {
                            adjusted += 1;
                            (ev_val as i16, d, e2, format!(
                                "export_adjusted: rounded distance {} collided (min_gap {:.6}, interval_hit={}); safe integer {} (shift {:+.6} from exact)",
                                export_distance, ev_export0.clearance.min_gap, ev_export0.interval_hit,
                                d, d as f64 - pair.origin_distance))
                        }
                        _ => return held_negative_origin(idx, pair, residual, "no verified safe integer distance near the negative origin"),
                    }
                }
                None => return held_negative_origin(idx, pair, residual, "no verified safe integer distance near the negative origin"),
            }
        } else {
            (export_value, export_distance, ev_export0, String::new())
        }
    };

    let entry = GeneratedKernPair {
        left: pair.left.clone(),
        right: pair.right.clone(),
        residual_units: residual,
        export_value,
        export_distance,
        left_frame: Some(l_frame),
        right_frame: Some(r_frame),
        solver_wall_gap_units: pair.wall_gap,
        measured_gap_at_origin: Some(ev_origin.clearance.min_gap),
        measured_gap_at_export: Some(ev_export.clearance.min_gap),
        weighted_mean_gap_at_origin: Some(ev_origin.clearance.weighted_mean_gap),
        weighted_mean_gap_at_export: Some(ev_export.clearance.weighted_mean_gap),
        ink_intersects: ev_export.collides(),
        origin_interval_hit: Some(ev_origin.interval_hit),
        export_interval_hit: Some(ev_export.interval_hit),
        optical_cost: pair.optical_cost,
        disposition: PairDisposition::Ready,
        note: meas.mark(note),
    };
    let kind = if geo.drop_zero_residual && export_value == 0 {
        PairKind::DroppedZero(entry)
    } else if is_fallback {
        PairKind::FallbackReady(entry)
    } else {
        PairKind::Ready(entry)
    };
    PairOutcome { idx, pins, clamps_refused: 0, export_adjusted: adjusted, probe: None, kind, lattice: None }
}

/// One pair's job, verbatim semantics of the former serial loop body. Pure:
/// no shared mutable state, safe on a pool worker.
fn eval_pair(
    idx: usize,
    pair: &crate::self_anchored_spacing::PairPosition,
    is_fallback: bool,
    below_eps: bool,
    spacing: &BTreeMap<&str, (f64, f64)>,
    profs: &BTreeMap<&str, &OutlineProfile>,
    exact: Option<&ExactMap>,
    geo: &ExportGeometry,
) -> PairOutcome {
    let mut pins: Vec<String> = Vec::new();
    let mut probe: Option<String> = None;
    // 1. Both glyphs' spacing present; every input finite.
    let (l_lsb, l_adv) = match spacing.get(pair.left.as_str()) {
        Some(&(l, a)) => (l, a),
        None => {
            return rejected(idx, pins, 0, probe, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
                "left glyph missing from SpacingSolution.glyphs".to_string());
        }
    };
    let (r_lsb, r_adv) = match spacing.get(pair.right.as_str()) {
        Some(&(l, a)) => (l, a),
        None => {
            return rejected(idx, pins, 0, probe, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
                "right glyph missing from SpacingSolution.glyphs".to_string());
        }
    };
    if !(pair.origin_distance.is_finite()
        && pair.wall_gap.is_finite()
        && pair.optical_cost.is_finite()
        && l_lsb.is_finite() && l_adv.is_finite()
        && r_lsb.is_finite() && r_adv.is_finite())
    {
        return rejected(idx, pins, 0, probe, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
            "non-finite input (origin_distance / wall_gap / optical_cost / lsb / advance)"
                .to_string());
    }
    let residual = pair.origin_distance - l_adv;

    // 1b. Compensated negative-origin class (architect decision): legal
    //     GPOS negative XAdvance when measured tangent/clean, tangent cut
    //     with a typed export_adjusted row on a real collision, typed hold
    //     only when unmeasurable or unverifiable. A negative origin on a
    //     pair the compensation never touched is not attributed to
    //     containment and follows the normal geometry path below.
    if pair.origin_distance < 0.0 && pair.compensated {
        return eval_negative_origin_compensated(idx, pair, is_fallback, (l_lsb, l_adv), (r_lsb, r_adv), profs, exact, geo);
    }

    // 2. Full ink geometry present, nonzero, finite bounds, UPM match.
    let (lp, rp) = match (profs.get(pair.left.as_str()), profs.get(pair.right.as_str())) {
        (Some(l), Some(r)) => (*l, *r),
        _ => {
            return rejected(idx, pins, 0, probe, pair, residual, 0, 0, None, None, None, None, None, None, false,
                "missing full-outline profile for pair glyph".to_string());
        }
    };
    if lp.upm != geo.upm || rp.upm != geo.upm {
        return rejected(idx, pins, 0, probe, pair, residual, 0, 0, None, None, None, None, None, None, false,
            format!("upm mismatch: left={} right={} export={}", lp.upm, rp.upm, geo.upm));
    }
    if !(lp.ink_area > 0.0 && rp.ink_area > 0.0)
        || !lp.bounds.iter().chain(rp.bounds.iter()).all(|b| b.is_finite())
    {
        return rejected(idx, pins, 0, probe, pair, residual, 0, 0, None, None, None, None, None, None, false,
            "empty ink or non-finite bounds in profile".to_string());
    }

    // 3. Frame binding (architect rule): BOTH frames or no Ready.
    let (l_frame, r_frame) = match (
        GlyphFrame::new(l_lsb, lp.bounds[0], l_adv),
        GlyphFrame::new(r_lsb, rp.bounds[0], r_adv),
    ) {
        (Some(l), Some(r)) => (l, r),
        _ => {
            return rejected(idx, pins, 0, probe, pair, residual, 0, 0, None, None, None, None, None, None, false,
                "frame binding broken: lsb / ink xmin / advance non-finite".to_string());
        }
    };

    pins.push(lp.source_pin.clone());
    pins.push(rp.source_pin.clone());
    let meas = match Meas::new(lp, rp, exact, pair.left.as_str(), pair.right.as_str()) {
        Ok(m) => m,
        Err(why) => {
            return rejected(idx, pins, 0, probe, pair, residual, 0, 0, Some(l_frame), Some(r_frame), None, None, None, None, false, why);
        }
    };

    // 4. Explicit integer export rounding + shipped distance
    //    (export_distance = round(left.advance) + export_value).
    //    A clamped value is refused, never shipped (the writer's int16
    //    check is the backstop, not the plan).
    let (export_value, clamped_v) = round_export_units(residual);
    let (advance_rnd, clamped_a) = round_export_units(l_adv);
    if clamped_v || clamped_a {
        return rejected(idx, pins, 1, probe, pair, residual, export_value, 0, Some(l_frame), Some(r_frame),
            None, None, None, None, false,
            format!("residual {:.3} or advance {:.3} out of int16 range; refused",
                residual, l_adv));
    }
    let export_distance = advance_rnd as i32 + export_value as i32;

    // 5. Full-outline shaping connection, caller-bound frame
    //    (geo.profile_frame; the KNI path is ExportedB — the exported-
    //    spacing origin frame is the semantic truth, translations move
    //    ink, not origins, so residual = origin_distance - left.advance
    //    is frame-invariant):
    //    a) at the EXACT origin_distance — like-for-like cross-check vs
    //       the solver's wall_gap;
    //    b) at the ROUNDED export_distance — the no-surprise overlap
    //       guard on the geometry the font actually ships.
    let (t_l, t_r) = match geo.profile_frame {
        ProfileFrame::ExportedB => (l_frame.x_translation, r_frame.x_translation),
        ProfileFrame::RawGenerated => (0.0, 0.0),
    };
    let ev_origin = meas.ev(t_l, t_r, pair.origin_distance);
    let ev_export0 = meas.ev(t_l, t_r, export_distance as f64);
    // PROBE (SOURCE-GATE-BYPASSED PROBE, GORAV): exact f64 bits, addition
    // order origin_distance = advance + residual; frame translations as passed.
    if let (Some(a), Some(b)) = (ev_origin, ev_export0) {
        probe = Some(format!("PROBE-BITS\t{}\t{}\torigin_bits={:016x}\tresidual_bits={:016x}\tadvance_bits={:016x}\ttl_bits={:016x}\ttr_bits={:016x}\tevO_mingap_bits={:016x}\tevO_hit={}\texport_dist={}\tevX_mingap_bits={:016x}\tevX_hit={}",
            pair.left, pair.right, pair.origin_distance.to_bits(), residual.to_bits(),
            l_adv.to_bits(), t_l.to_bits(), t_r.to_bits(),
            a.clearance.min_gap.to_bits(), a.interval_hit,
            export_distance, b.clearance.min_gap.to_bits(), b.interval_hit));
    }
    let (ev_origin, ev_export0) = match (ev_origin, ev_export0) {
        (Some(a), Some(b)) => (a, b),
        (None, _) => {
            return rejected(idx, pins, 0, probe, pair, residual, export_value, export_distance,
                Some(l_frame), Some(r_frame), None, None, None, None, false,
                "no shared scan-row coverage between pair profiles".to_string());
        }
        (Some(a), None) => {
            return rejected(idx, pins, 0, probe, pair, residual, export_value, export_distance,
                Some(l_frame), Some(r_frame), Some(a.clearance.min_gap), None, None, None, false,
                "no shared scan-row coverage at export distance".to_string());
        }
    };

    // Slice 5: a stage-3 below-epsilon drop is eligible only when its NATURAL placement (origin = left advance) collides under the
    // same measurement authority (collides(): gap 0 contact is not a collision). Otherwise the epsilon drop stands, typed, no row.
    let mut s5_prefix = String::new();
    if below_eps {
        match meas.ev(t_l, t_r, l_adv) {
            Some(n) if n.collides() => {
                s5_prefix = format!("{BELOW_EPSILON_RESIDUAL_COLLIDING}: natural placement collides exactly (min_gap {:.6}, interval_hit={}); stage-3 epsilon drop not applied", n.clearance.min_gap, n.interval_hit);
            }
            Some(n) => {
                return PairOutcome { idx, pins, clamps_refused: 0, export_adjusted: 0, probe, lattice: None,
                    kind: PairKind::BelowEpsDrop(pair.left.clone(), pair.right.clone(), n.clearance.min_gap) };
            }
            None => {
                return rejected(idx, pins, 0, probe, pair, residual, export_value, export_distance, Some(l_frame), Some(r_frame),
                    Some(ev_origin.clearance.min_gap), Some(ev_export0.clearance.min_gap), None, None, false,
                    "BELOW_EPSILON_RESIDUAL candidate: natural placement not measurable (no shared scan-row coverage); fails closed".to_string());
            }
        }
    }
    let mut disposition = PairDisposition::Ready;
    let mut note = String::new();
    let mut export_value = export_value;
    let mut export_distance = export_distance;
    let mut ev_export = ev_export0;
    let mut adjusted = 0usize;

    // 6. No-surprise overlap guard on the shipped geometry.
    //    a) Collision at the EXACT solver placement is a genuine hold:
    //       rounding cannot repair it. The collision reading holds only
    //       beyond agree_tol: the solver constrains gap >= 0 on this same
    //       interval model, so it can legally place a pair at exact contact
    //       (depth 0), and post-solve frame repairs (containment
    //       compensation) plus f64 translation rebinding shift the
    //       re-measured placement by ulps. A strict-inequality reading of
    //       that sub-tolerance penetration would hold a legally placed
    //       contact pair; depth at or below agree_tol is indistinguishable
    //       from contact. Real penetration (deeper than agree_tol) always
    //       holds.
    //    b) Collision only after integer rounding is a lattice problem:
    //       choose the deterministic safe integer (never closer than the
    //       solver placement can absorb), verified on actual geometry.
    //    c) Solver wall_gap vs measured at origin must agree within
    //       floating error scaled by the magnitudes involved (same
    //       model, same frame: a larger disagreement is a real defect).
    let ref_wall = match meas.reference_wall_gap(pair.wall_gap, t_l, t_r, pair.origin_distance) {
        Some(v) => v,
        None => {
            return rejected(idx, pins, 0, probe, pair, residual, export_value, export_distance, Some(l_frame), Some(r_frame),
                Some(ev_origin.clearance.min_gap), Some(ev_export0.clearance.min_gap), None, None, false,
                "exact reference wall_gap not measurable (no facing wall); stage-4 authority fails closed".to_string());
        }
    };
    let agree_tol = kern_agree_tol(ref_wall, ev_origin.clearance.min_gap, pair.origin_distance);
    let origin_depth = if ev_origin.collides() {
        (-ev_origin.clearance.min_gap)
            .max(meas.depth(t_l, t_r, pair.origin_distance))
    } else {
        0.0
    };
    // Unified lattice repair (chief am. 47, supersedes the am. 44 d0-only rule): a pair whose EXACT solver origin collides beyond agree_tol
    // (below-epsilon candidates and ordinary pairs alike) ships at the first exact-clear integer of the EXISTING walk
    // (safe_integer_distance_by: start d0 = lattice_start, +1 steps, existing span bound, existing exact predicate !collides()).
    // No new constant or tolerance. The shipped integer is re-measured; only a verified !collides() shipment is accepted. Anything else
    // (walk exhausted, no coverage, i16 overflow) keeps the unchanged typed hold below. Exact (slab) measurement only.
    let mut lattice: Option<LatticeClear> = None;
    let mut resolved: Option<(i32, i16, crate::signed_clearance::Evidence, f64)> = None;
    if origin_depth > agree_tol && meas.slabs.is_some() {
        let d0 = crate::signed_clearance::lattice_start(pair.origin_distance, ev_origin.clearance.min_gap);
        if d0.is_finite() && d0.abs() <= i32::MAX as f64 {
            if let (Some(e0), Some(d)) = (meas.ev(t_l, t_r, d0), meas.safe(lp, rp, t_l, t_r, pair.origin_distance, ev_origin.clearance.min_gap)) {
                let ev_val = d as i64 - advance_rnd as i64;
                if ev_val >= i16::MIN as i64 && ev_val <= i16::MAX as i64 {
                    if let Some(e2) = meas.ev(t_l, t_r, d as f64) {
                        if !e2.collides() { resolved = Some((d, ev_val as i16, e2, e0.clearance.min_gap)); }
                    }
                }
            }
        }
    }
    if let Some((d, ev_val, e2, gap_d0)) = resolved {
        let d0 = crate::signed_clearance::lattice_start(pair.origin_distance, ev_origin.clearance.min_gap) as i32;
        lattice = Some(LatticeClear {
            left: pair.left.clone(), right: pair.right.clone(),
            solver_origin: pair.origin_distance, depth_at_origin: origin_depth,
            d0, d_shipped: d, walk_steps: d - d0, shift: d as f64 - pair.origin_distance,
            gap_at_origin: ev_origin.clearance.min_gap, gap_at_d0: gap_d0, gap_at_shipped: e2.clearance.min_gap,
            below_epsilon: below_eps,
            solver_residual: residual, export_value: ev_val, pair_target: pair.pair_target,
        });
        let tag = if below_eps { BELOW_EPSILON_RESIDUAL_RESOLVED_ON_LATTICE } else { EXACT_ORIGIN_COLLISION_RESOLVED_ON_LATTICE };
        let msg = format!("{tag}: solver origin {:.6} penetrates by {:.6}; shipped lattice integer {} (d0 {}, walk_steps {}, gap at shipped {:.6}, interval_hit={})",
            pair.origin_distance, origin_depth, d, d0, d - d0, e2.clearance.min_gap, e2.interval_hit);
        s5_prefix = if s5_prefix.is_empty() { msg } else { format!("{s5_prefix}; {msg}") };
        export_distance = d;
        export_value = ev_val;
        ev_export = e2;
    } else if origin_depth > agree_tol {
        disposition = PairDisposition::OverlapHold;
        note = format!(
            "collision at exact solver placement (origin {:.6}): min_gap {:.6}, depth {:.6}, interval_hit={}",
            pair.origin_distance, ev_origin.clearance.min_gap,
            ev_origin.clearance.penetration_depth, ev_origin.interval_hit);
    } else if (ev_origin.clearance.min_gap - ref_wall).abs() > agree_tol {
        disposition = PairDisposition::OverlapHold;
        note = format!(
            "solver wall_gap {:.6} vs measured {:.6} disagree beyond fp tolerance {:.3e}",
            ref_wall, ev_origin.clearance.min_gap, agree_tol);
    } else if ev_export.collides() {
        match meas.safe(lp, rp, t_l, t_r, pair.origin_distance,
                                    ev_origin.clearance.min_gap) {
            Some(d) => {
                let ev2 = meas.ev(t_l, t_r, d as f64);
                let ev_val = d as i64 - advance_rnd as i64;
                match ev2 {
                    Some(e2) if !e2.collides() && ev_val >= i16::MIN as i64 && ev_val <= i16::MAX as i64 => {
                        note = format!(
                            "export_adjusted: rounded distance {} collided (min_gap {:.6}, interval_hit={}); safe integer {} (shift {:+.6} from exact)",
                            export_distance, ev_export.clearance.min_gap, ev_export.interval_hit,
                            d, d as f64 - pair.origin_distance);
                        export_distance = d;
                        export_value = ev_val as i16;
                        ev_export = e2;
                        adjusted += 1;
                    }
                    _ => {
                        disposition = PairDisposition::OverlapHold;
                        note = format!("no verified safe integer distance near {:.6}", pair.origin_distance);
                    }
                }
            }
            None => {
                disposition = PairDisposition::OverlapHold;
                note = format!("no verified safe integer distance near {:.6}", pair.origin_distance);
            }
        }
    }
    let gap_origin = Some(ev_origin.clearance.min_gap);
    let wmean_origin = Some(ev_origin.clearance.weighted_mean_gap);
    let gap_export = Some(ev_export.clearance.min_gap);
    let wmean_export = Some(ev_export.clearance.weighted_mean_gap);
    let ix_export = ev_export.collides();

    let entry = GeneratedKernPair {
        left: pair.left.clone(),
        right: pair.right.clone(),
        residual_units: residual,
        export_value,
        export_distance,
        left_frame: Some(l_frame),
        right_frame: Some(r_frame),
        solver_wall_gap_units: pair.wall_gap,
        measured_gap_at_origin: gap_origin,
        measured_gap_at_export: gap_export,
        weighted_mean_gap_at_origin: wmean_origin,
        weighted_mean_gap_at_export: wmean_export,
        ink_intersects: ix_export,
        origin_interval_hit: Some(ev_origin.interval_hit),
        export_interval_hit: Some(ev_export.interval_hit),
        optical_cost: pair.optical_cost,
        disposition,
        note: meas.mark(if s5_prefix.is_empty() { note } else if note.is_empty() { s5_prefix } else { format!("{s5_prefix}; {note}") }),
    };

    let kind = match disposition {
        PairDisposition::Ready => {
            if geo.drop_zero_residual && export_value == 0 {
                PairKind::DroppedZero(entry)
            } else if is_fallback {
                PairKind::FallbackReady(entry)
            } else {
                PairKind::Ready(entry)
            }
        }
        PairDisposition::OverlapHold => PairKind::OverlapHold(entry),
        PairDisposition::Rejected => unreachable!("rejections push early"),
    };
    PairOutcome { idx, pins, clamps_refused: 0, export_adjusted: adjusted, probe, kind, lattice }
}

#[cfg(test)]
mod par_tests {
    use super::*;
    use crate::outline_spacing::{InkInterval, ScanRow};
    use crate::self_anchored_spacing::{GlyphSpacing, PairPosition, SpaceStatus, SpacingSolution};

    // ---- OLD serial loop, kept verbatim (pre-P1-PAR) as the oracle --------
    fn old_serial_generate_residual_kern(
        solution: &SpacingSolution,
        profiles: &[OutlineProfile],
        geo: &ExportGeometry,
    ) -> GeneratedKern {
        let spacing: BTreeMap<&str, (f64, f64)> = solution
            .glyphs
            .iter()
            .map(|g| (g.glyph_id.as_str(), (g.lsb, g.advance)))
            .collect();
        let profs: BTreeMap<&str, &OutlineProfile> = profiles
            .iter()
            .map(|p| (p.glyph_id.as_str(), p))
            .collect();

        let mut out = GeneratedKern {
            ready: Vec::new(),
            fallback_ready: Vec::new(),
            overlap_holds: Vec::new(),
            rejected: Vec::new(),
            dropped_zero: Vec::new(),
        lattice_resolved: Vec::new(),
            receipt: KernReceipt {
                upm: geo.upm,
                source_pins: Vec::new(),
                policy_derivation: solution.policy_derivation.clone(),
                rounding: ROUNDING_MODE_LABEL.to_string(),
                overlap_tolerance_units: geo.overlap_tolerance_units,
                ready: 0,
                fallback_ready: 0,
                overlap_held: 0,
                rejected: 0,
                dropped_zero: 0,
                clamps_refused: 0,
                solution_complete: solution.complete,
                excluded_self_pairs: solution.excluded_self_pairs,
                excluded_below_epsilon: solution.excluded_below_epsilon,
                excluded_pairs_count: solution.excluded_pairs.len(),
                excluded_unmeasurable: solution.excluded_unmeasurable,
                export_adjusted: 0,
                profile_frame: geo.profile_frame,
                alignment: "K1 align_pair_rows span-overlap (row matching delegated; legacy tolerance knob recorded, not gating)".to_string(),
            },
        };

        let mut pins = std::collections::BTreeSet::new();

        for (idx, (pair, is_fallback)) in solution
            .pairs
            .iter()
            .map(|p| (p, false))
            .chain(solution.fallback_pairs.iter().map(|p| (p, true)))
            .enumerate()
        {
            // 1. Both glyphs' spacing present; every input finite.
            let (l_lsb, l_adv) = match spacing.get(pair.left.as_str()) {
                Some(&(l, a)) => (l, a),
                None => {
                    push_rejected(&mut out, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
                        "left glyph missing from SpacingSolution.glyphs".to_string());
                    continue;
                }
            };
            let (r_lsb, r_adv) = match spacing.get(pair.right.as_str()) {
                Some(&(l, a)) => (l, a),
                None => {
                    push_rejected(&mut out, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
                        "right glyph missing from SpacingSolution.glyphs".to_string());
                    continue;
                }
            };
            if !(pair.origin_distance.is_finite()
                && pair.wall_gap.is_finite()
                && pair.optical_cost.is_finite()
                && l_lsb.is_finite() && l_adv.is_finite()
                && r_lsb.is_finite() && r_adv.is_finite())
            {
                push_rejected(&mut out, pair, f64::NAN, 0, 0, None, None, None, None, None, None, false,
                    "non-finite input (origin_distance / wall_gap / optical_cost / lsb / advance)"
                        .to_string());
                continue;
            }
            let residual = pair.origin_distance - l_adv;

            // 1b. Compensated negative-origin class: identical semantics to
            //     eval_pair via the shared evaluator; the fold below mirrors
            //     the parallel reduce exactly.
            if pair.origin_distance < 0.0 && pair.compensated {
                let o = eval_negative_origin_compensated(idx, pair, is_fallback, (l_lsb, l_adv), (r_lsb, r_adv), &profs, None, geo);
                for pin in o.pins { pins.insert(pin); }
                out.receipt.clamps_refused += o.clamps_refused;
                out.receipt.export_adjusted += o.export_adjusted;
                match o.kind {
                    PairKind::Ready(e) => { out.receipt.ready += 1; out.ready.push(e); }
                    PairKind::FallbackReady(e) => { out.receipt.fallback_ready += 1; out.fallback_ready.push(e); }
                    PairKind::OverlapHold(e) => { out.receipt.overlap_held += 1; out.overlap_holds.push(e); }
                    PairKind::DroppedZero(e) => { out.receipt.dropped_zero += 1; out.dropped_zero.push(e); }
                    PairKind::Rejected(e) => { out.receipt.rejected += 1; out.rejected.push(e); }
                    PairKind::BelowEpsDrop(..) => unreachable!("only eval_pair produces below-epsilon drops"),
                }
                continue;
            }

            // 2. Full ink geometry present, nonzero, finite bounds, UPM match.
            let (lp, rp) = match (profs.get(pair.left.as_str()), profs.get(pair.right.as_str())) {
                (Some(l), Some(r)) => (*l, *r),
                _ => {
                    push_rejected(&mut out, pair, residual, 0, 0, None, None, None, None, None, None, false,
                        "missing full-outline profile for pair glyph".to_string());
                    continue;
                }
            };
            if lp.upm != geo.upm || rp.upm != geo.upm {
                push_rejected(&mut out, pair, residual, 0, 0, None, None, None, None, None, None, false,
                    format!("upm mismatch: left={} right={} export={}", lp.upm, rp.upm, geo.upm));
                continue;
            }
            if !(lp.ink_area > 0.0 && rp.ink_area > 0.0)
                || !lp.bounds.iter().chain(rp.bounds.iter()).all(|b| b.is_finite())
            {
                push_rejected(&mut out, pair, residual, 0, 0, None, None, None, None, None, None, false,
                    "empty ink or non-finite bounds in profile".to_string());
                continue;
            }

            // 3. Frame binding (architect rule): BOTH frames or no Ready.
            let (l_frame, r_frame) = match (
                GlyphFrame::new(l_lsb, lp.bounds[0], l_adv),
                GlyphFrame::new(r_lsb, rp.bounds[0], r_adv),
            ) {
                (Some(l), Some(r)) => (l, r),
                _ => {
                    push_rejected(&mut out, pair, residual, 0, 0, None, None, None, None, None, None, false,
                        "frame binding broken: lsb / ink xmin / advance non-finite".to_string());
                    continue;
                }
            };

            pins.insert(lp.source_pin.clone());
            pins.insert(rp.source_pin.clone());

            // 4. Explicit integer export rounding + shipped distance
            let (export_value, clamped_v) = round_export_units(residual);
            let (advance_rnd, clamped_a) = round_export_units(l_adv);
            if clamped_v || clamped_a {
                out.receipt.clamps_refused += 1;
                push_rejected(&mut out, pair, residual, export_value, 0, Some(l_frame), Some(r_frame),
                    None, None, None, None, false,
                    format!("residual {:.3} or advance {:.3} out of int16 range; refused",
                        residual, l_adv));
                continue;
            }
            let export_distance = advance_rnd as i32 + export_value as i32;

            // 5. Full-outline shaping connection, caller-bound frame
            let (t_l, t_r) = match geo.profile_frame {
                ProfileFrame::ExportedB => (l_frame.x_translation, r_frame.x_translation),
                ProfileFrame::RawGenerated => (0.0, 0.0),
            };
            let ev_origin = evidence_at(lp, rp, t_l, t_r, pair.origin_distance);
            let ev_export0 = evidence_at(lp, rp, t_l, t_r, export_distance as f64);
            let (ev_origin, ev_export0) = match (ev_origin, ev_export0) {
                (Some(a), Some(b)) => (a, b),
                (None, _) => {
                    push_rejected(&mut out, pair, residual, export_value, export_distance,
                        Some(l_frame), Some(r_frame), None, None, None, None, false,
                        "no shared scan-row coverage between pair profiles".to_string());
                    continue;
                }
                (Some(a), None) => {
                    push_rejected(&mut out, pair, residual, export_value, export_distance,
                        Some(l_frame), Some(r_frame), Some(a.clearance.min_gap), None, None, None, false,
                        "no shared scan-row coverage at export distance".to_string());
                    continue;
                }
            };

            let mut disposition = PairDisposition::Ready;
            let mut note = String::new();
            let mut export_value = export_value;
            let mut export_distance = export_distance;
            let mut ev_export = ev_export0;

            // 6. No-surprise overlap guard on the shipped geometry (same
            //    origin-depth rule as eval_pair: sub-agree_tol penetration is
            //    frame noise at a legal contact placement, never a hold).
            let agree_tol = kern_agree_tol(pair.wall_gap, ev_origin.clearance.min_gap, pair.origin_distance);
            let origin_depth = if ev_origin.collides() {
                (-ev_origin.clearance.min_gap)
                    .max(interval_overlap_depth(lp, rp, t_l, t_r, pair.origin_distance))
            } else {
                0.0
            };
            if origin_depth > agree_tol {
                disposition = PairDisposition::OverlapHold;
                note = format!(
                    "collision at exact solver placement (origin {:.6}): min_gap {:.6}, depth {:.6}, interval_hit={}",
                    pair.origin_distance, ev_origin.clearance.min_gap,
                    ev_origin.clearance.penetration_depth, ev_origin.interval_hit);
            } else if (ev_origin.clearance.min_gap - pair.wall_gap).abs() > agree_tol {
                disposition = PairDisposition::OverlapHold;
                note = format!(
                    "solver wall_gap {:.6} vs measured {:.6} disagree beyond fp tolerance {:.3e}",
                    pair.wall_gap, ev_origin.clearance.min_gap, agree_tol);
            } else if ev_export.collides() {
                match safe_integer_distance(lp, rp, t_l, t_r, pair.origin_distance,
                                            ev_origin.clearance.min_gap) {
                    Some(d) => {
                        let ev2 = evidence_at(lp, rp, t_l, t_r, d as f64);
                        let ev_val = d as i64 - advance_rnd as i64;
                        match ev2 {
                            Some(e2) if !e2.collides() && ev_val >= i16::MIN as i64 && ev_val <= i16::MAX as i64 => {
                                note = format!(
                                    "export_adjusted: rounded distance {} collided (min_gap {:.6}, interval_hit={}); safe integer {} (shift {:+.6} from exact)",
                                    export_distance, ev_export.clearance.min_gap, ev_export.interval_hit,
                                    d, d as f64 - pair.origin_distance);
                                export_distance = d;
                                export_value = ev_val as i16;
                                ev_export = e2;
                                out.receipt.export_adjusted += 1;
                            }
                            _ => {
                                disposition = PairDisposition::OverlapHold;
                                note = format!("no verified safe integer distance near {:.6}", pair.origin_distance);
                            }
                        }
                    }
                    None => {
                        disposition = PairDisposition::OverlapHold;
                        note = format!("no verified safe integer distance near {:.6}", pair.origin_distance);
                    }
                }
            }
            let gap_origin = Some(ev_origin.clearance.min_gap);
            let wmean_origin = Some(ev_origin.clearance.weighted_mean_gap);
            let gap_export = Some(ev_export.clearance.min_gap);
            let wmean_export = Some(ev_export.clearance.weighted_mean_gap);
            let ix_export = ev_export.collides();

            let entry = GeneratedKernPair {
                left: pair.left.clone(),
                right: pair.right.clone(),
                residual_units: residual,
                export_value,
                export_distance,
                left_frame: Some(l_frame),
                right_frame: Some(r_frame),
                solver_wall_gap_units: pair.wall_gap,
                measured_gap_at_origin: gap_origin,
                measured_gap_at_export: gap_export,
                weighted_mean_gap_at_origin: wmean_origin,
                weighted_mean_gap_at_export: wmean_export,
                ink_intersects: ix_export,
                origin_interval_hit: Some(ev_origin.interval_hit),
                export_interval_hit: Some(ev_export.interval_hit),
                optical_cost: pair.optical_cost,
                disposition,
                note,
            };

            match disposition {
                PairDisposition::Ready => {
                    if geo.drop_zero_residual && export_value == 0 {
                        out.receipt.dropped_zero += 1;
                        out.dropped_zero.push(entry);
                    } else if is_fallback {
                        out.receipt.fallback_ready += 1;
                        out.fallback_ready.push(entry);
                    } else {
                        out.receipt.ready += 1;
                        out.ready.push(entry);
                    }
                }
                PairDisposition::OverlapHold => {
                    out.receipt.overlap_held += 1;
                    out.overlap_holds.push(entry);
                }
                PairDisposition::Rejected => unreachable!("rejections push early"),
            }
        }

        out.receipt.source_pins = pins.into_iter().collect();
        out
    }

    #[allow(clippy::too_many_arguments)]
    fn push_rejected(
        out: &mut GeneratedKern,
        pair: &crate::self_anchored_spacing::PairPosition,
        residual: f64,
        export_value: i16,
        export_distance: i32,
        left_frame: Option<GlyphFrame>,
        right_frame: Option<GlyphFrame>,
        gap_origin: Option<f64>,
        gap_export: Option<f64>,
        wmean_origin: Option<f64>,
        wmean_export: Option<f64>,
        intersects: bool,
        note: String,
    ) {
        out.receipt.rejected += 1;
        out.rejected.push(GeneratedKernPair {
            left: pair.left.clone(),
            right: pair.right.clone(),
            residual_units: residual,
            export_value,
            export_distance,
            left_frame,
            right_frame,
            solver_wall_gap_units: pair.wall_gap,
            measured_gap_at_origin: gap_origin,
            measured_gap_at_export: gap_export,
            weighted_mean_gap_at_origin: wmean_origin,
            weighted_mean_gap_at_export: wmean_export,
            ink_intersects: intersects,
            origin_interval_hit: None,
            export_interval_hit: None,
            optical_cost: pair.optical_cost,
            disposition: PairDisposition::Rejected,
            note,
        });
    }

    // ---- fixture -----------------------------------------------------------

    fn prof(id: &str, upm: u16, ink: (f64, f64), yspan: (f64, f64)) -> OutlineProfile {
        let step = 10.0;
        let mut rows = Vec::new();
        let mut y = yspan.0;
        while y < yspan.1 {
            rows.push(ScanRow {
                y,
                weight: f64::min(step, yspan.1 - y),
                span_lo: ink.0,
                span_hi: ink.1,
                ink: vec![InkInterval { left: ink.0, right: ink.1 }],
            });
            y += step;
        }
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: format!("sha256:test:{id}"),
            upm,
            origin: [0.0, 0.0],
            rows,
            bounds: [ink.0, yspan.0, ink.1, yspan.1],
            ink_area: (ink.1 - ink.0) * (yspan.1 - yspan.0),
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: "bounded_curve_flatten+scanline".to_string(),
            row_step: step,
            flatten_tolerance: 0.1,
        }
    }

    fn gs(id: &str) -> GlyphSpacing {
        GlyphSpacing { glyph_id: id.into(), lsb: 50.0, rsb: 50.0, advance: 600.0 }
    }

    fn pair(l: &str, r: &str, od: f64, wall_gap: f64) -> PairPosition {
        PairPosition { left: l.into(), right: r.into(), origin_distance: od, wall_gap, optical_cost: 1.0, pair_target: None, compensated: false }
    }

    fn solution(glyphs: Vec<GlyphSpacing>, pairs: Vec<PairPosition>, fallback_pairs: Vec<PairPosition>) -> SpacingSolution {
        SpacingSolution {
            baseline: 0.0, x_height: 500.0, x_height_source: crate::self_anchored_spacing::XHeightSource::Ctx, cap_height: 700.0,
            glyphs, pairs, font_median_pair_target: None, space_status: SpaceStatus::Absent,
            excluded_pairs: vec![], complete: true, excluded_self_pairs: 0, excluded_below_epsilon: 0,
            excluded_unmeasurable: 0, numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0,
            hold_reasons: vec![], pair_ledger: vec![], fallback_pairs, fallback_natural_clear_pairs: 0,
            fallback_verified_pairs: 0, numeric_failed_nonfinite: 0, numeric_failed_malformed: 0,
            numeric_failed_natural_unverifiable: 0, numeric_failed_natural_frame_conflict: 0,
            accounting_residual: 0, accounting_closed: true,
            policy_derivation: "test fixture".into(),
            unobserved_policy: vec![],
            anchor_audit: crate::anchor_audit::AnchorAuditReport::not_run(),
            contrast_floor_adjustments: vec![], contrast_floor_failures: vec![],
        }
    }

    fn geo() -> ExportGeometry {
        ExportGeometry {
            profile_frame: ProfileFrame::ExportedB,
            upm: 1000,
            overlap_tolerance_units: 0.0,
            drop_zero_residual: false,
            row_align_tolerance_units: 10.0,
        }
    }

    /// Pairs exercising every bucket: ready, fallback-ready, rejected (missing
    /// profile / upm mismatch / clamp), overlap-hold (collision), no shared
    /// scan-row coverage.
    fn fixture() -> (SpacingSolution, Vec<OutlineProfile>) {
        let pa = prof("A", 1000, (0.0, 100.0), (0.0, 700.0));
        let pb = prof("B", 1000, (0.0, 100.0), (0.0, 700.0));
        let pc = prof("C", 1000, (0.0, 100.0), (0.0, 100.0));
        let pd = prof("D", 1000, (0.0, 100.0), (500.0, 600.0));
        let pe = prof("E", 2000, (0.0, 100.0), (0.0, 700.0));
        // wall_gap values the guard will measure, so the agree check passes bit-exactly.
        let (fl, fr) = (GlyphFrame::new(50.0, 0.0, 600.0).unwrap(), GlyphFrame::new(50.0, 0.0, 600.0).unwrap());
        let ev_ready = evidence_at(&pa, &pb, fl.x_translation, fr.x_translation, 650.0).expect("shared rows");
        let ev_coll = evidence_at(&pa, &pb, fl.x_translation, fr.x_translation, 10.0).expect("shared rows");
        assert!(ev_coll.collides(), "fixture pair must collide at origin");
        // Compensated negative-origin class: a collision cut at the tangent
        // (A->B at -5, depth 105, cut to distance 100) and a clean legal
        // negative XAdvance (A->F at -25: F's ink sits 50 right of B's, so
        // the measured gap there is 25 > 0).
        let pf = {
            let mut p = prof("F", 1000, (150.0, 250.0), (0.0, 700.0));
            // Row alignment keys on the span; keep it overlapping A's (0-100).
            for row in &mut p.rows { row.span_lo = 0.0; row.span_hi = 250.0; }
            p
        };
        let ff = GlyphFrame::new(200.0, 150.0, 600.0).unwrap();
        let ev_cut = evidence_at(&pa, &pb, fl.x_translation, fr.x_translation, -5.0).expect("shared rows");
        let ev_clean = evidence_at(&pa, &pf, fl.x_translation, ff.x_translation, -25.0).expect("shared rows");
        assert!(ev_cut.collides(), "class fixture must collide at the negative origin");
        assert!(!ev_clean.collides(), "class fixture must be clean at the negative origin");
        let mut p_cut = pair("A", "B", -5.0, ev_cut.clearance.min_gap);
        p_cut.compensated = true;
        let mut p_clean = pair("A", "F", -25.0, ev_clean.clearance.min_gap);
        p_clean.compensated = true;
        let pairs = vec![
            pair("A", "B", 650.0, ev_ready.clearance.min_gap),
            pair("A", "ZZ", 650.0, 5.0),
            pair("A", "E", 650.0, 5.0),
            pair("A", "B", 50_600.0, 5.0),
            pair("A", "B", 10.0, ev_coll.clearance.min_gap),
            pair("C", "D", 650.0, 5.0),
            p_cut,
            p_clean,
        ];
        let fallback = vec![pair("A", "B", 650.0, ev_ready.clearance.min_gap)];
        let mut glyphs = vec![gs("A"), gs("B"), gs("C"), gs("D"), gs("E"), gs("ZZ")];
        glyphs.push(GlyphSpacing { glyph_id: "F".into(), lsb: 200.0, rsb: 0.0, advance: 600.0 });
        (solution(glyphs, pairs, fallback), vec![pa, pb, pc, pd, pe, pf])
    }

    // ---- tests ---------------------------------------------------------------

    #[test]
    fn negative_origin_after_containment_compensation_is_a_typed_hold() {
        let mut p = pair("A", "B", -1.0, 0.0);
        p.compensated = true;
        let sol = solution(vec![gs("A"), gs("B")], vec![p], vec![]);
        let kern = generate_residual_kern_jobs(&sol, &[], &geo(), 1);
        assert_eq!(kern.receipt.overlap_held, 1);
        assert_eq!(kern.receipt.ready, 0);
        assert!(kern.overlap_holds[0].note.starts_with(CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN));
        assert_eq!(kern.overlap_holds[0].residual_units, -1.0 - 600.0);
        assert!(kern.overlap_holds[0].left_frame.is_none());

        // Fallback pairs take the same path.
        let mut p = pair("A", "B", -2.0, 0.0);
        p.compensated = true;
        let sol = solution(vec![gs("A"), gs("B")], vec![], vec![p]);
        let kern = generate_residual_kern_jobs(&sol, &[], &geo(), 1);
        assert_eq!(kern.receipt.overlap_held, 1);
        assert!(kern.overlap_holds[0].note.starts_with(CONTAINMENT_COMPENSATION_NEGATIVE_ORIGIN));
    }


    /// The parallel driver equals the old serial loop value for value at every
    /// job count (full Debug equality of the whole GeneratedKern), with every
    /// bucket exercised.
    #[test]
    fn parallel_residual_kern_matches_the_old_serial_loop_at_jobs_1_2_4_8() {
        let (sol, profs) = fixture();
        let g = geo();
        let oracle = old_serial_generate_residual_kern(&sol, &profs, &g);
        assert_eq!(oracle.receipt.ready, 3, "plain ready + tangent cut + clean negative XAdvance");
        assert_eq!(oracle.receipt.fallback_ready, 1);
        assert_eq!(oracle.receipt.rejected, 3, "missing profile + upm + clamp");
        assert_eq!(oracle.receipt.overlap_held, 2, "collision pair + vertically-disjoint pair both hold");
        assert_eq!(oracle.receipt.export_adjusted, 1, "the compensated-origin collision ships cut at the tangent");
        let total = oracle.receipt.ready + oracle.receipt.fallback_ready + oracle.receipt.rejected + oracle.receipt.overlap_held + oracle.receipt.dropped_zero;
        assert_eq!(total, 9, "every pair job accounted for exactly once");
        assert_eq!(oracle.receipt.clamps_refused, 1);
        assert!(!oracle.receipt.source_pins.is_empty());
        let want = format!("{oracle:?}");
        for jobs in [1usize, 2, 4, 8] {
            let got = generate_residual_kern_jobs(&sol, &profs, &g, jobs);
            assert_eq!(format!("{got:?}"), want, "GeneratedKern, jobs={jobs}");
        }
        // The compatibility wrapper stays the serial entry point.
        let got = generate_residual_kern(&sol, &profs, &g);
        assert_eq!(format!("{got:?}"), want, "wrapper == oracle");
    }

    /// drop_zero_residual routes zero-residual ready pairs into the dropped
    /// bucket identically at every job count.
    #[test]
    fn drop_zero_residual_bucket_matches_at_jobs_1_4() {
        let pa = prof("A", 1000, (0.0, 100.0), (0.0, 700.0));
        let pb = prof("B", 1000, (0.0, 100.0), (0.0, 700.0));
        let (fl, fr) = (GlyphFrame::new(50.0, 0.0, 600.0).unwrap(), GlyphFrame::new(50.0, 0.0, 600.0).unwrap());
        let ev = evidence_at(&pa, &pb, fl.x_translation, fr.x_translation, 600.0).expect("shared rows");
        let sol = solution(vec![gs("A"), gs("B")], vec![pair("A", "B", 600.0, ev.clearance.min_gap)], vec![]);
        let mut g = geo();
        g.drop_zero_residual = true;
        let oracle = old_serial_generate_residual_kern(&sol, &[pa.clone(), pb.clone()], &g);
        assert_eq!(oracle.receipt.dropped_zero, 1, "residual 0 must drop");
        assert_eq!(oracle.receipt.ready, 0);
        let want = format!("{oracle:?}");
        for jobs in [1usize, 4] {
            let got = generate_residual_kern_jobs(&sol, &[pa.clone(), pb.clone()], &g, jobs);
            assert_eq!(format!("{got:?}"), want, "jobs={jobs}");
        }
    }

    /// Empty pair population: identical empty ledger at any job count.
    #[test]
    fn empty_pair_list_is_identical() {
        let sol = solution(vec![gs("A")], vec![], vec![]);
        let g = geo();
        let want = format!("{:?}", old_serial_generate_residual_kern(&sol, &[], &g));
        for jobs in [1usize, 4] {
            assert_eq!(format!("{:?}", generate_residual_kern_jobs(&sol, &[], &g, jobs)), want, "jobs={jobs}");
        }
    }
}
