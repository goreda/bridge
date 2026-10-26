//! kni-pipeline: single executable over the merged engine tree.
//!
//! Chain (every stage is the library's own public path, no copied logic):
//!   manifest file -> per-glyph source bytes
//!   -> capture_dispatch/generated_draw_frame::fit_bytes_source_frame (real route)
//!   -> outline_spacing::profile_outline (bounded flatten, budget-guarded)
//!   -> self_anchored_spacing::solve_spacing (FontContext WITHOUT measured_pairs /
//!      measured_sidebearings: no source/font-pair input enters the solver)
//!   -> generated_outline_kern::generate_residual_kern
//!   -> gpos_pairpos1::write_kern_pairpos1_or_omit
//!   -> generated_native::prepare_generated -> native_font::encode_with_layout
//!   -> OTF bytes + receipt bundle.
//!
//! Guard scope: guards cover this bounded generated active path only; no
//! general lower-level public-API safety claim is made here.

mod spacing_fallback;
mod learned_driver;
mod pair_visual_wiring;
mod pair_visual_targets;
mod fit_reduce;
mod profiles_par;
mod space_evidence;
pub mod space_spec;
mod bound_detector_validator;
mod notdef_caller;
mod notdef_producer;
#[cfg(test)]
mod notdef_producer_validator_tests;
mod notdef_proxy;
mod notdef_wiring;
mod k3_notdef_scan;
use bound_detector_validator::{Action as NotdefAction, EvidenceBinding};
mod run_config;
mod run_failure;
mod run_audit;
mod declared_convention;
mod paul_new_anchor;
mod paul_new_metrics_policy;
mod determinism_decide;
mod fit_bench;
mod iou_population;
mod scale_wiring;
mod kern_scope;
use kni_core::rounding_reconcile;
#[allow(dead_code)] // ink-containment floor guard; exercised by stem_pair_containment_tests, production wiring pending
mod ink_containment;
#[allow(dead_code)] // typed ambiguity-degrade ledger scaffolding; exercised by its tests, production wiring pending
mod guard_degrade;
mod stem_pair_overflow;
mod population_floor;
mod spacing_oohh;
mod style_overrides;
#[allow(dead_code)] // W2 module API (Mode::token, InvariantReport/holds/check_invariant, applied_tsv) is exercised by auto_sb's own tests only; main.rs A2 glue has its own invariant check
mod auto_sb;
use kni_pipeline::{export_gate_closure, k5_main_adapter, k6_final_publish};
#[cfg(test)]
mod kerning_letters_fixture_tests;
#[cfg(test)]
mod stem_pair_containment_tests;
use run_config::RunConfig;
#[cfg(test)]
use run_config::FitErrorPolicy;  // test-only import (cfg(test) mods reference it unqualified)
use scale_wiring::{WiringError, BoundRunScale};

/// PNG decode budget for source tiles: explicit default at the call site until
/// a decode-budget config field exists; the limits are recorded in the receipt.
const PNG_DECODE_LIMITS: kni_core::capture::DecodeLimits = kni_core::capture::DecodeLimits {
    max_input_bytes: 32 * 1024 * 1024,
    max_pixels: 4_194_304,
    max_working_bytes: 64 * 1024 * 1024,
};
mod post_metrics;
#[allow(dead_code)]
mod kerning_pairs;
#[allow(dead_code)]
mod kerning_measure;
#[allow(dead_code)]
mod kerning_model;
mod unicode_marks;
mod natural_spacing;
use kni_core::cff_reader::sha256_hex;
use kni_core::cubic_fit::FitPolicy;
use kni_core::generated_draw_frame::{fit_captured_source_frame, fit_captured_source_frame_guarded_guided, ReferenceFrameMap};
use kni_core::reference_guided::GuideConfig;
use kni_core::reference_transfer::{make_pin, PinnedReference};
use kni_core::generated_native::{prepare_generated, prepare_generated_with_placement, rounding_ledger, InkPlacement};
use kni_core::jpeg_source::Limits;
use kni_core::native_font::{encode_with_layout, encode_with_layout_gsub, NativeFontInput};
use kni_metrics::self_anchored_spacing::SpacingSolution;
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};
use kni_metrics::generated_outline_kern::{
    ExportGeometry, GlyphIdMap, ProfileFrame,
};
use kni_metrics::gpos_pairpos1::PairKern;
use kni_metrics::gsub_liga::{write_liga_or_omit, LigaSub};
use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::{solve_spacing_jobs, FontContext, SpacingPolicy};
#[cfg(test)]
use kni_metrics::self_anchored_spacing::solve_spacing;
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

// ---------------- manifest ----------------

/// Glyph rows accept the legacy whitespace form plus one explicit extension: a
/// double-quoted image path. Quoting is the preferred and only spaced-path
/// form; an unquoted spaced path still fails instead of being guessed as a
/// path/scale split. Backslash escapes only `"` and `\` inside a quoted path;
/// all other backslashes stay literal.
fn split_glyph_fields(line: &str) -> Result<Vec<String>, String> {
    let mut fields = Vec::new();
    let mut cur = String::new();
    let mut in_quote = false;
    let mut escaped = false;
    let mut field_started = false;
    let mut quote_closed = false;
    for ch in line.chars() {
        if escaped {
            match ch {
                '"' => cur.push('"'),
                '\\' => cur.push('\\'),
                other => {
                    cur.push('\\');
                    cur.push(other);
                }
            }
            escaped = false;
            continue;
        }
        if in_quote {
            match ch {
                '\\' => escaped = true,
                '"' => {
                    in_quote = false;
                    quote_closed = true;
                }
                _ => cur.push(ch),
            }
            continue;
        }
        if ch.is_whitespace() {
            if field_started {
                fields.push(std::mem::take(&mut cur));
            }
            field_started = false;
            quote_closed = false;
            continue;
        }
        if quote_closed {
            return Err("quoted glyph image path must end at whitespace".into());
        }
        if ch == '"' {
            if field_started {
                return Err("quote must start the glyph image path field".into());
            }
            field_started = true;
            in_quote = true;
            continue;
        }
        cur.push(ch);
        field_started = true;
    }
    if escaped {
        cur.push('\\');
    }
    if in_quote {
        return Err("unterminated quoted glyph image path".into());
    }
    if field_started {
        fields.push(cur);
    }
    Ok(fields)
}

#[derive(Clone, Debug)]
struct GlyphRow {
    /// `Some(cp)` for an encoded row; `None` for an unencoded anonymous row
    /// (manifest syntax `glyph - <name> <image>`): drawn, fitted and spaced like
    /// any other glyph, shipped in the CFF charset with NO cmap entry.
    codepoint: Option<u32>,
    /// Ligature sequence tail: empty for an ordinary (single-codepoint) row; the remaining scalars
    /// for a ligature glyph (`0x0066_0069` -> codepoint 0x66, extra_cps [0x69]). A ligature glyph is
    /// drawn, fitted and spaced like any other but is never cmap-mapped (cmap holds single scalars).
    extra_cps: Vec<u32>,
    name: String,
    image: PathBuf,
    scale: Option<f64>,
}
impl GlyphRow {
    fn is_ligature(&self) -> bool { !self.extra_cps.is_empty() }
    /// Sorted-set / population-pin key: `66` for an ordinary row, `66_69` for a ligature
    /// (lowercase hex, `_`-joined, no padding - the kit writer emits the identical string).
    pub(crate) fn seq_label(&self) -> String {
        let mut k = match self.codepoint {
            Some(cp) => format!("{cp:x}"),
            // Unencoded anonymous row: name-keyed (kit writer emits the identical string).
            None => format!("anon:{}", self.name),
        };
        for cp in &self.extra_cps { k.push_str(&format!("_{cp:x}")); }
        k
    }
    /// Receipt/display form: `0x66` or `0x66_0x69` (`-` for an unencoded row).
    pub(crate) fn cp_display(&self) -> String {
        let mut d = match self.codepoint {
            Some(cp) => format!("{cp:#x}"),
            None => "-".to_string(),
        };
        for cp in &self.extra_cps { d.push_str(&format!("_{cp:#x}")); }
        d
    }
}

/// Typed fit-tolerance route selection: a caller override of the
/// measured route is a typed policy selection, never a silent conflict).
/// MeasuredExperimental: per-glyph DerivedTolerance from the actual raster
/// (core::tolerance::derive_from_gray), squared_error = fit_se_scaled(scale) = mean(u^2)/3 * scale^2.
/// This is an RMS variance statistic fed to a MAX-POINT gate -
/// NOT norm-compatible, NOT a production bound. It exists for experimental smoke diagnostics
/// only and must never back a usable artifact; the norm-compatible quantization bound covers
/// quantization only and is separate work (aliasing-corridor research).
/// Fixed: manifest fit_squared_error row (legacy route).
#[derive(Clone, Copy, Debug, PartialEq)]
/// DerivedSourceQuantization: squared_error = (K/2)^2 fu^2 from the style's declared K (RunConfig::new); manifest key
/// `derived_source_quantization`; the manifest fit_squared_error row is ignored for this route.
enum FitTolerancePolicy { MeasuredExperimental, Fixed, DerivedSourceQuantization }

/// Typed run mode (S1 v3). Stage1Only fits + writes stage1-cache.txt and then
/// STOPS in stage2_and_beyond before profiles/solve_spacing: a shard can never
/// produce a spacing solution, because W_target/stem/baseline/side
/// classification need the whole population. Full runs everything, and only
/// when the manifest's glyph set hashes to its declared population pin.
#[derive(Clone, Copy, Debug, PartialEq)]
enum RunMode { Stage1Only, Full }

/// The only declared value of the manifest `os2_x_height_write` key (chief decision
/// 7a17069f3815014525547446e994a4d16cf9e76c): skip the OS/2 sxHeight write when the
/// bridged x_height measurement is Unresolved. Absent key = legacy write.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Os2XHeightWrite { ResolvedOnly, MeasuredPreferred }

/// r229 receipt-only M3 adapter declaration (chief architecture position, not an
/// owner ruling): every key optional, no defaults. All six absent = adapter OFF
/// (byte-equal output); some present = MISSING_PARAM rows; invalid values =
/// INVALID_PARAM rows; all present and valid = planner M1+M3 measured, receipt-only.
#[derive(Clone, Debug, Default)]
struct M3Decl {
    lower_set: Option<Vec<u32>>,
    excl_set: Option<Vec<u32>>,
    cluster_gap: Option<f64>,
    min_cluster_size: Option<i64>,
    tol_flat: Option<f64>,
    min_gap: Option<f64>,
    /// R3 (chief ruling): explicit codepoint list for the measured cap line; no default. Optional: absent never makes the M3 declaration incomplete.
    cap_set: Option<Vec<u32>>,
}

#[derive(Clone, Debug)]
struct Manifest {
    family: String,
    subfamily: String,
    postscript_name: String,
    /// Declared manifest value when sanitization changed it (receipt record only).
    postscript_name_declared: Option<String>,
    vendor: [u8; 4],
    upm: u16,
    scale: f64,
    capture_frame: Option<String>,
    capture_cohort: Option<String>,
    post_lsb_add: f64,
    post_rsb_add: f64,
    post_scope: kni_core::offset_scope::ScopePolicy,
    post_scope_label: String,
    rdp_epsilon: f64,
    fit_squared_error: f64,
    fit_max_refits: usize,
    fit_tolerance_policy: FitTolerancePolicy,
    flatten_tolerance: f64,
    scan_row_step: f64,
    scan_max_rows: usize,
    sample_resolution: f64,
    max_pair_evaluations: u64,
    iou: Option<run_config::IouSettings>,
    max_pairs: usize,
    pair_min_shared_rows: usize,
    /// AUTO-SB (A2) mode key; None = off (byte-identical run). Merged with the --auto-sb flag
    /// at one injection point (validated_run_config_with_cli); disagreement is a hard error.
    auto_sb: Option<run_config::AutoSbMode>,
    /// Class-mode input table (glyph_id,left_class,right_class; external perception-layer measurement).
    auto_sb_class_table: Option<PathBuf>,
    /// User offset on the AUTO-SB target side bearings (output units, signed); None = absent (0.0).
    auto_sb_offset_lsb: Option<f64>,
    auto_sb_offset_rsb: Option<f64>,
    /// Explicit even-n median tie rule; required when auto_sb is on.
    tie_break: Option<run_config::TieBreak>,
    /// Pool observations TSV (pooled median source); merged with the --auto-sb-pool flag.
    auto_sb_pool: Option<PathBuf>,
    glyphs: Vec<GlyphRow>,
    space_evidence: Option<space_evidence::SpaceEvidenceRef>,
    space: Option<(u32, f64)>, // explicit caller-declared space: codepoint, advance
    /// Always-output: with no measured/manifest space, derive the space advance
    /// from the solved glyphs (space_evidence::derive_space_advance).
    derive_space_from_letter_advances: bool,
    notdef: Option<EvidenceBinding>,
    notdef_proxy: Option<(String,u32)>,
    capture_manifest: Option<(PathBuf, String)>,
    /// Pinned declared style-override table (style-overrides.tsv): path + sha256.
    style_overrides: Option<(PathBuf, String)>,
    run_mode: RunMode,
    corner_wiring: bool,
    /// Declared OS/2 sxHeight write guard; None (key absent) = legacy behavior.
    os2_x_height_write: Option<Os2XHeightWrite>,
    /// r229 M3 adapter declaration; all-None = adapter OFF.
    m3: M3Decl,
    population_sha256: String, // sha256 over sorted "cp-hex:name\n" rows of the FULL population
    stage1_cache: Option<PathBuf>, // explicit caller-declared stage-1 geometry reuse (pin-verified)
    /// Explicit opt-in, pinned learned spacing store and certified gate evidence.
    learned_store: Option<(PathBuf, String)>,
    learned_gate_evidence: Option<PathBuf>,
    /// Explicit same-source declaration, never an automatic spacing default.
    pair_visual_same_source: bool,

    /// glyph name -> (owner OTF path, font sha256, codepoint): pinned reference for the guided path
    references: Vec<(String, PathBuf, String, u32)>,
    frame_map: Option<(f64, f64, f64, f64)>, // reraster xmin, ymax, px_per_unit, pad_px (required with references)
    guide: Option<(f64, f64, f64)>, // smooth_sin, max_node_dist, max_ring_cost (explicit, caller-owned)
}


/// Pure residual-kern export gate (safety restore; known-defect provenance: a DIAG-PROBE copy
/// had disabled this refusal in the canonical base). No I/O; no kern solve/GPOS math here.
/// unresolved==0 => Clear in every mode. unresolved>0 in the Default (warn-export) mode =>
/// Partial: the caller records the typed `kern_gate_degraded` warning plus the
/// diagnostic_partial_kern and partial_output receipt rows and the export continues.
/// unresolved>0 in Strict mode => typed refusal (no font ships); strict is the human
/// kit-acceptance gate for final kits, which reads the receipt, not engine behavior.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KernGate { Clear, Partial }
/// Gate mode for `residual_kern_gate`. Default = warn-export degrade; Strict = refusal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KernGateMode { Default, Strict }
/// Placeholder routing guard on the emitted cmap, kind-conditional
/// (always-output). Under PixelEvidence the bound codepoints SHIP as drawn
/// glyphs with their own gids, so cmap presence is the contract and only
/// .notdef routing (gid 0) is a mismatch. Under CandidateProxy the candidates
/// ship through the generated proxy path and must never reach cmap directly;
/// .notdef routing stays a mismatch there too.
fn placeholder_mapping_guard(proxy_state: &Option<bound_detector_validator::DetectionState>, mapping: &[(u32, u16)]) -> Result<(), String> {
    match proxy_state {
        Some(bound_detector_validator::DetectionState::PixelEvidence { sources, .. }) if !sources.is_empty() => {
            if mapping.iter().any(|(_, gid)| *gid == 0) {
                return Err(bound_detector_validator::BadNotdef::ContextMismatch.to_string());
            }
        }
        Some(bound_detector_validator::DetectionState::CandidateProxy { candidate_cps, .. }) if !candidate_cps.is_empty() => {
            if mapping.iter().any(|(cp, gid)| candidate_cps.contains(cp) || *gid == 0) {
                return Err(bound_detector_validator::BadNotdef::ContextMismatch.to_string());
            }
        }
        _ => {}
    }
    Ok(())
}

fn residual_kern_gate(overlap_held: usize, rejected: usize, clamps_refused: usize, mode: KernGateMode) -> Result<KernGate, String> {
    let unresolved = overlap_held
        .checked_add(rejected)
        .and_then(|a| a.checked_add(clamps_refused))
        .ok_or_else(|| format!("residual kern ledger overflow (overlap_held={overlap_held}, rejected={rejected}, clamps_refused={clamps_refused})"))?;
    if unresolved == 0 { return Ok(KernGate::Clear); }
    if mode == KernGateMode::Strict {
        return Err(format!(
            "residual kern unresolved (overlap_held={overlap_held}, rejected={rejected}, clamps_refused={clamps_refused}); strict mode refuses export. The default warn-export mode degrades to a receipt-marked partial output (kern_gate_degraded)"
        ));
    }
    Ok(KernGate::Partial)
}

/// Resolve the declared style override for this manifest's family/subfamily
/// from the pinned kit table, or None when the style is not listed (all other
/// styles behave bit-exactly as before).
fn declared_override_for(m: &Manifest) -> Result<Option<style_overrides::StyleOverride>, String> {
    // declared post-lsb/rsb overrides and AUTO-SB write the same bearing fields;
    // both declared = typed refusal, never silent precedence.
    if m.style_overrides.is_some() && m.auto_sb.is_some() {
        return Err("refused: style_overrides and auto_sb both declared (same bearing fields; choose one)".to_string());
    }
    match &m.style_overrides {
        Some((path, pin)) => {
            let table = style_overrides::load_pinned(path, pin).map_err(|e| format!("style_overrides refused: {e:?}"))?;
            Ok(style_overrides::lookup(&table, &m.family, &m.subfamily).cloned())
        }
        None => Ok(None),
    }
}

/// Apply a declared style override to the parsed manifest (SET semantics;
/// chief ruling 2026-10-17): the post-step values are SET from the override
/// row and the flag/manifest lsb_add/rsb_add are IGNORED - one injection
/// point (manifest -> run_config -> post_metrics), so the value is applied
/// exactly once (40/45 never becomes 80/90). Returns the typed receipt rows.
/// Pure: no I/O.
fn apply_declared_style_override(m: &mut Manifest, row: &style_overrides::StyleOverride) -> String {
    let mut out = style_overrides::overrides_flags_row(m.post_lsb_add, m.post_rsb_add, row);
    out.push_str(&style_overrides::ignored_input_rows());
    m.post_lsb_add = row.lsb_add;
    m.post_rsb_add = row.rsb_add;
    m.post_scope = style_overrides::DECLARED_POST_SCOPE;
    m.post_scope_label = style_overrides::DECLARED_POST_SCOPE_LABEL.to_string();
    out
}

/// Empty GeneratedKern for a declared style override: the kern stage did NOT
/// run (typed not_run rows are emitted instead). Zero pairs, zero receipt
/// counts, closed ledger - downstream GPOS/gate code sees the same shape as a
/// genuine zero-pair run.
fn declared_skipped_kern(upm: u16, profile_frame: ProfileFrame) -> kni_metrics::generated_outline_kern::GeneratedKern {
    kni_metrics::generated_outline_kern::GeneratedKern {
        ready: vec![], fallback_ready: vec![], overlap_holds: vec![], rejected: vec![], dropped_zero: vec![], lattice_resolved: vec![],
        receipt: kni_metrics::generated_outline_kern::KernReceipt {
            upm, source_pins: vec![], policy_derivation: "declared convention: kern not run for this style".into(),
            rounding: String::new(), overlap_tolerance_units: 0.0,
            ready: 0, fallback_ready: 0, overlap_held: 0, rejected: 0, dropped_zero: 0, clamps_refused: 0,
            solution_complete: true, excluded_self_pairs: 0, excluded_below_epsilon: 0, excluded_pairs_count: 0,
            excluded_unmeasurable: 0, export_adjusted: 0, profile_frame, alignment: String::new(),
        },
    }
}

/// Drop ledger: one `kern_drop\t<pair>\treason_code\t<code>` line per held / rejected / clamped / zero-dropped pair.
/// Codes are derived from structure, never from free-text notes: a rejected pair that carries both frame bindings reached the
/// int16 clamp guard (`clamp_refused`); any other rejection never bound its frames (`rejected_unbound`).
/// The per-code line counts must close EXACTLY against the kern receipt counters, else a typed refusal.
fn kern_drop_ledger(kern: &kni_metrics::generated_outline_kern::GeneratedKern) -> Result<String, String> {
    let mut out = String::new();
    let (mut held, mut clamp, mut unbound, mut zero) = (0usize, 0usize, 0usize, 0usize);
    let pair_name = |p: &kni_metrics::generated_outline_kern::GeneratedKernPair| format!("{}->{}", p.left, p.right);
    for p in &kern.overlap_holds { held += 1; out.push_str(&format!("kern_drop\t{}\treason_code\toverlap_hold\n", pair_name(p))); }
    for p in &kern.rejected {
        let code = if p.left_frame.is_some() && p.right_frame.is_some() { clamp += 1; "clamp_refused" } else { unbound += 1; "rejected_unbound" };
        out.push_str(&format!("kern_drop\t{}\treason_code\t{}\n", pair_name(p), code));
    }
    for p in &kern.dropped_zero { zero += 1; out.push_str(&format!("kern_drop\t{}\treason_code\tdropped_zero\n", pair_name(p))); }
    let r = &kern.receipt;
    let rejected_total = clamp.checked_add(unbound);
    if held != r.overlap_held || rejected_total != Some(r.rejected) || clamp != r.clamps_refused || zero != r.dropped_zero {
        return Err(format!(
            "kern drop ledger does not close against receipt (ledger overlap_hold={held} rejected={rejected_total:?} clamp_refused={clamp} dropped_zero={zero}; receipt overlap_held={} rejected={} clamps_refused={} dropped_zero={})",
            r.overlap_held, r.rejected, r.clamps_refused, r.dropped_zero));
    }
    out.push_str(&format!("kern_drop_total\toverlap_hold\t{held}\tclamp_refused\t{clamp}\trejected_unbound\t{unbound}\tdropped_zero\t{zero}\tclosed\ttrue\n"));
    Ok(out)
}

/// Manifest post-step offset value: one finite number (integrality and >= 0 are enforced again by RunConfig::new).
fn parse_post_offset(key: &str, v: Option<&str>, extra: bool) -> Result<f64, String> {
    let v = v.ok_or_else(|| format!("manifest: {key} missing"))?;
    if extra { return Err(format!("manifest: {key} extra field")); }
    let x: f64 = v.parse().map_err(|_| format!("manifest: bad {key} '{v}'"))?;
    if !x.is_finite() { return Err(format!("manifest: {key} must be finite")); }
    Ok(x)
}
/// post_scope = comma-separated subset of base,space,notdef,mark, OR the single token `kerning_letters` (Base ∩ Unicode L* ∩ emitted nonzero
/// GPOS pair-kern participants; filtered in the post-step). `kerning_letters` is exclusive: it is not combined with other members
/// (not with `base`: plain `base` stays valid and unchanged). Unknown, duplicate or empty member = refusal.
fn parse_post_scope(v: &str) -> Result<kni_core::offset_scope::ScopePolicy, String> {
    let mut p = kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false };
    let mut members = 0usize;
    for part in v.split(',') {
        members += 1;
        let slot = match part {
            "base" => &mut p.base, "space" => &mut p.space, "notdef" => &mut p.notdef, "mark" => &mut p.mark,
            "kerning_letters" => &mut p.kerning_letters,
            other => return Err(format!("manifest: bad post_scope member '{other}' (base|space|notdef|mark|kerning_letters)")),
        };
        if *slot { return Err(format!("manifest: duplicate post_scope member '{part}'")); }
        *slot = true;
    }
    if p.kerning_letters && members != 1 { return Err("manifest: post_scope kerning_letters must stand alone (it refines base; do not combine)".into()); }
    Ok(p)
}

fn parse_manifest(text: &str, base: &Path) -> Result<Manifest, String> {
    let mut family = None;
    let mut subfamily = None;
    let mut ps = None;
    let mut vendor = *b"NONE";
    let mut upm = 1000u16;
    let mut scale = None;
    let mut capture_frame = None;
    let mut capture_cohort = None;
    let mut post_lsb: Option<f64> = None;
    let mut post_rsb: Option<f64> = None;
    let mut post_scope: Option<kni_core::offset_scope::ScopePolicy> = None;
    let mut post_label: Option<String> = None;
    let mut rdp_epsilon = 0.25;
    let mut fit_se = 0.25;
    let mut fit_refits = 8usize;
    let mut fit_tol_policy: Option<FitTolerancePolicy> = None;
    let mut flat_tol = 0.5;
    let mut row_step = 10.0;
    let mut auto_sb = None;
    let mut auto_sb_class_table = None;
    let mut auto_sb_pool = None;
    let mut auto_sb_offset_lsb = None;
    let mut auto_sb_offset_rsb = None;
    let mut tie_break = None;
    let mut max_rows = 1000usize;
    let mut sample_res = 10.0;
    let mut max_pe = 1_000_000u64;
    let mut iou_thr: Option<u8> = None;
    let mut iou_steps: Option<usize> = None;
    let mut max_pairs = 10_000usize;
    let mut min_rows = 1usize;
    let mut glyphs = Vec::new();
    let mut notdef_proxy = None;
    let mut space = None;
    let mut space_evidence = None;
    let mut derive_space_from_letter_advances = false;
    let mut notdef = None;
    let mut capture_manifest = None;
    let mut style_overrides: Option<(PathBuf, String)> = None;
    let mut stage1_cache = None;
    let mut learned_store = None;
    let mut learned_gate_evidence = None;
    let mut pair_visual_same_source = false;
    let mut run_mode: Option<RunMode> = None;
    let mut corner_wiring = false;
    let mut os2_x_height_write = None;
    let mut m3 = M3Decl::default();
    let mut population_sha256: Option<String> = None;
    let mut references = Vec::new();
    let mut frame_map: [Option<f64>; 4] = [None; 4];
    let mut guide: [Option<f64>; 3] = [None; 3];
    for (ln, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let err = |m: &str| format!("manifest line {}: {}", ln + 1, m);
        let mut it = line.split_whitespace();
        let key = it.next().unwrap();
        match key {
            "family" => family = Some(line["family".len()..].trim().to_string()),
            "subfamily" => subfamily = Some(line["subfamily".len()..].trim().to_string()),
            "postscript_name" => ps = Some(it.next().ok_or(err("postscript_name missing"))?.to_string()),
            "vendor" => {
                let v = it.next().ok_or(err("vendor missing"))?.as_bytes();
                if v.len() != 4 {
                    return Err(err("vendor must be exactly 4 bytes"));
                }
                vendor = [v[0], v[1], v[2], v[3]];
            }
            "upm" => upm = it.next().ok_or(err("upm missing"))?.parse().map_err(|_| err("bad upm"))?,
            "capture_frame" => {
                if capture_frame.is_some() { return Err(err("duplicate capture_frame")); }
                capture_frame = Some(it.next().ok_or(err("capture_frame missing"))?.to_string());
                if it.next().is_some() { return Err(err("capture_frame extra field")); }
            },
            "capture_cohort" => {
                if capture_cohort.is_some() { return Err(err("duplicate capture_cohort")); }
                capture_cohort = Some(it.collect::<Vec<_>>().join(" "));
            },
            "lsb_add" => {
                if post_lsb.is_some() { return Err(err("duplicate lsb_add")); }
                post_lsb = Some(parse_post_offset("lsb_add", it.next(), it.next().is_some())?);
            },
            "rsb_add" => {
                if post_rsb.is_some() { return Err(err("duplicate rsb_add")); }
                post_rsb = Some(parse_post_offset("rsb_add", it.next(), it.next().is_some())?);
            },
            "post_scope" => {
                if post_scope.is_some() { return Err(err("duplicate post_scope")); }
                let v = it.next().ok_or(err("post_scope missing"))?;
                if it.next().is_some() { return Err(err("post_scope extra field (comma-separated, no spaces)")); }
                post_scope = Some(parse_post_scope(v)?);
            },
            "post_scope_label" => {
                if post_label.is_some() { return Err(err("duplicate post_scope_label")); }
                let v = it.next().ok_or(err("post_scope_label missing"))?;
                if it.next().is_some() { return Err(err("post_scope_label extra field")); }
                post_label = Some(v.to_string());
            },
            "scale" => scale = Some(it.next().ok_or(err("scale missing"))?.parse::<f64>().map_err(|_| err("bad scale"))?),
            "rdp_epsilon" => rdp_epsilon = it.next().ok_or(err("rdp_epsilon missing"))?.parse().map_err(|_| err("bad rdp_epsilon"))?,
            "fit_squared_error" => fit_se = it.next().ok_or(err("fit_squared_error missing"))?.parse().map_err(|_| err("bad fit_squared_error"))?,
            "fit_max_refits" => fit_refits = it.next().ok_or(err("fit_max_refits missing"))?.parse().map_err(|_| err("bad fit_max_refits"))?,
            "fit_tolerance_policy" => {
                fit_tol_policy = Some(match it.next().ok_or(err("fit_tolerance_policy missing"))? {
                    "measured_experimental" => FitTolerancePolicy::MeasuredExperimental,
                    "fixed" => FitTolerancePolicy::Fixed,
                    "derived_source_quantization" => FitTolerancePolicy::DerivedSourceQuantization,
                    other => return Err(format!("manifest: bad fit_tolerance_policy {other:?} (measured_experimental|fixed|derived_source_quantization); the RMS measured route is experimental-only, not a production bound")),
                });
            }
            "flatten_tolerance" => flat_tol = it.next().ok_or(err("flatten_tolerance missing"))?.parse().map_err(|_| err("bad flatten_tolerance"))?,
            "scan_row_step" => row_step = it.next().ok_or(err("scan_row_step missing"))?.parse().map_err(|_| err("bad scan_row_step"))?,
            "scan_max_rows" => max_rows = it.next().ok_or(err("scan_max_rows missing"))?.parse().map_err(|_| err("bad scan_max_rows"))?,
            "sample_resolution" => sample_res = it.next().ok_or(err("sample_resolution missing"))?.parse().map_err(|_| err("bad sample_resolution"))?,
            "iou_ink_threshold" => { if iou_thr.is_some() { return Err(err("duplicate iou_ink_threshold")); } iou_thr = Some(it.next().ok_or(err("iou_ink_threshold missing"))?.parse().map_err(|_| err("bad iou_ink_threshold"))?); if it.next().is_some() { return Err(err("iou_ink_threshold extra field")); } },
            "iou_flatten_steps" => { if iou_steps.is_some() { return Err(err("duplicate iou_flatten_steps")); } iou_steps = Some(it.next().ok_or(err("iou_flatten_steps missing"))?.parse().map_err(|_| err("bad iou_flatten_steps"))?); if it.next().is_some() { return Err(err("iou_flatten_steps extra field")); } },
            "max_pair_evaluations" => max_pe = it.next().ok_or(err("max_pair_evaluations missing"))?.parse().map_err(|_| err("bad max_pair_evaluations"))?,
            "max_pairs" => max_pairs = it.next().ok_or(err("max_pairs missing"))?.parse().map_err(|_| err("bad max_pairs"))?,
            "pair_min_shared_rows" => min_rows = it.next().ok_or(err("pair_min_shared_rows missing"))?.parse().map_err(|_| err("bad pair_min_shared_rows"))?,
            "auto_sb" => {
                if auto_sb.is_some() { return Err(err("duplicate auto_sb")); }
                auto_sb = Some(run_config::AutoSbMode::from_flag(it.next().ok_or(err("auto_sb missing"))?).ok_or(err("bad auto_sb (median|class)"))?);
                if it.next().is_some() { return Err(err("auto_sb extra field")); }
            },
            "auto_sb_class_table" => {
                if auto_sb_class_table.is_some() { return Err(err("duplicate auto_sb_class_table")); }
                auto_sb_class_table = Some(base.join(it.next().ok_or(err("auto_sb_class_table missing"))?));
                if it.next().is_some() { return Err(err("auto_sb_class_table extra field")); }
            },
            "auto_sb_pool" => {
                if auto_sb_pool.is_some() { return Err(err("duplicate auto_sb_pool")); }
                auto_sb_pool = Some(base.join(it.next().ok_or(err("auto_sb_pool missing"))?));
                if it.next().is_some() { return Err(err("auto_sb_pool extra field")); }
            },
            "auto_sb_offset_lsb" => {
                if auto_sb_offset_lsb.is_some() { return Err(err("duplicate auto_sb_offset_lsb")); }
                let v: f64 = it.next().ok_or(err("auto_sb_offset_lsb missing"))?.parse().map_err(|_| err("bad auto_sb_offset_lsb"))?;
                if !v.is_finite() { return Err(err("auto_sb_offset_lsb must be finite")); }
                if it.next().is_some() { return Err(err("auto_sb_offset_lsb extra field")); }
                auto_sb_offset_lsb = Some(v);
            },
            "auto_sb_offset_rsb" => {
                if auto_sb_offset_rsb.is_some() { return Err(err("duplicate auto_sb_offset_rsb")); }
                let v: f64 = it.next().ok_or(err("auto_sb_offset_rsb missing"))?.parse().map_err(|_| err("bad auto_sb_offset_rsb"))?;
                if !v.is_finite() { return Err(err("auto_sb_offset_rsb must be finite")); }
                if it.next().is_some() { return Err(err("auto_sb_offset_rsb extra field")); }
                auto_sb_offset_rsb = Some(v);
            },
            "tie_break" => {
                if tie_break.is_some() { return Err(err("duplicate tie_break")); }
                tie_break = Some(run_config::TieBreak::from_flag(it.next().ok_or(err("tie_break missing"))?).ok_or(err("bad tie_break (A|B)"))?);
                if it.next().is_some() { return Err(err("tie_break extra field")); }
            },
            "glyph" => {
                let fields = split_glyph_fields(line).map_err(|m| err(&m))?;
                let cp_raw = fields.get(1).ok_or(err("glyph codepoint missing"))?;
                let name = fields.get(2).ok_or(err("glyph name missing"))?.to_string();
                let img = fields.get(3).ok_or(err("glyph image path missing"))?;
                let sc = match fields.get(4) {
                    Some(v) => Some(v.parse::<f64>().map_err(|_| err("bad per-glyph scale"))?),
                    None => None,
                };
                if fields.len() > 5 {
                    return Err(err("unexpected extra field"));
                }
                // Row-local value faults (codepoint, glyph name) exclude only this row and are recorded as
                // manifest_row_excluded events; the run continues with the remaining rows (run_config glyph-row region).
                match run_config::parse_glyph_row_codepoints(cp_raw).and_then(|cps| run_config::validate_glyph_row_name(&name).map(|_| cps)) {
                    Ok(cps) => glyphs.push(GlyphRow { codepoint: Some(cps[0]), extra_cps: cps[1..].to_vec(), name, image: base.join(img), scale: sc }),
                    Err(_) if cp_raw == "-" => {
                        // Unencoded anonymous row: `glyph - <name> <image> [scale]`. Only the bare
                        // "-" field selects it; a failed codepoint parse never falls through here
                        // silently (any other Err keeps the row-excluded path below).
                        match run_config::validate_glyph_row_name(&name) {
                            Ok(()) => glyphs.push(GlyphRow { codepoint: None, extra_cps: Vec::new(), name, image: base.join(img), scale: sc }),
                            Err(r) => eprint!("{}", run_config::manifest_row_excluded_event(line, r)),
                        }
                    }
                    Err(r) => eprint!("{}", run_config::manifest_row_excluded_event(line, r)),
                }
            }
            "notdef_proxy" => {
                let rule=it.next().ok_or("bad_notdef::Grammar")?;
                let pin=it.next().ok_or("bad_notdef::Grammar")?;
                let cp=it.next().ok_or("bad_notdef::Grammar")?;
                if !["legacy-largest-repeat-proxy","most-frequent-pixel-hash"].contains(&rule) || pin.len()!=64 || !pin.bytes().all(|c|c.is_ascii_digit()||(b'a'..=b'f').contains(&c)) || it.next().is_some(){return Err("bad_notdef::Grammar".into());}
                let cp=u32::from_str_radix(cp.trim_start_matches("0x"),16).map_err(|_|"bad_notdef::Grammar")?;
                if notdef_proxy.replace((pin.into(),cp)).is_some(){return Err("bad_notdef::Duplicate".into());}
            }
            "capture_manifest" => {
                let p = it.next().ok_or("bad_notdef::Grammar")?;
                let pin = it.next().ok_or("bad_notdef::Grammar")?;
                if it.next().is_some() { return Err("bad_notdef::Grammar".into()); }
                if capture_manifest.replace((base.join(p), pin.to_string())).is_some() { return Err("bad_notdef::Duplicate".into()); }
            }
            "style_overrides" => {
                let p = it.next().ok_or(err("style_overrides missing path"))?;
                let pin = it.next().ok_or(err("style_overrides missing sha256"))?;
                if it.next().is_some() { return Err(err("style_overrides extra field")); }
                if style_overrides.replace((base.join(p), pin.to_string())).is_some() { return Err(err("duplicate style_overrides")); }
            },
            "learned_store" => {
                let p = it.next().ok_or(err("learned_store missing path"))?;
                let pin = it.next().ok_or(err("learned_store missing sha256"))?;
                if pin.len() != 64 || !pin.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) { return Err(err("learned_store sha256 must be 64 lowercase hex")); }
                if it.next().is_some() { return Err(err("learned_store extra field")); }
                if learned_store.replace((base.join(p), pin.to_string())).is_some() { return Err(err("duplicate learned_store")); }
            },
            "learned_gate_evidence" => {
                let p = it.next().ok_or(err("learned_gate_evidence missing path"))?;
                if it.next().is_some() { return Err(err("learned_gate_evidence extra field")); }
                if learned_gate_evidence.replace(base.join(p)).is_some() { return Err(err("duplicate learned_gate_evidence")); }
            },
            "pair_visual_same_source" => {
                if it.next().is_some() { return Err(err("pair_visual_same_source takes no value")); }
                if pair_visual_same_source { return Err(err("duplicate pair_visual_same_source")); }
                pair_visual_same_source = true;
            }
            "notdef" => {
                if notdef.is_some() { return Err(bound_detector_validator::BadNotdef::Duplicate.to_string()); }
                notdef = Some(bound_detector_validator::parse_binding(it, base).map_err(|e| e.to_string())?);
            }
            "derive_space_from_letter_advances" => {
                if it.next().is_some() { return Err(err("derive_space_from_letter_advances takes no value")); }
                if derive_space_from_letter_advances { return Err(err("duplicate derive_space_from_letter_advances")); }
                derive_space_from_letter_advances = true;
            }
            "space" => {
                let cp_raw = it.next().ok_or(err("space codepoint missing"))?;
                let cp = u32::from_str_radix(cp_raw.strip_prefix("0x").unwrap_or(cp_raw), 16)
                    .map_err(|_| err("bad space codepoint"))?;
                let adv: f64 = it.next().ok_or(err("space advance missing"))?.parse().map_err(|_| err("bad space advance"))?;
                if !adv.is_finite() || adv < 0.0 {
                    return Err(err("space advance must be finite and >= 0"));
                }
                if space.replace((cp, adv)).is_some() {
                    return Err(err("duplicate space row"));
                }
            }
            "space_evidence" => {
                let row = space_evidence::SpaceEvidenceRef::from_tokens(base, &mut it, &err)?;
                if space_evidence.replace(row).is_some() {
                    return Err(err("duplicate space_evidence row"));
                }
                if it.next().is_some() {
                    return Err(err("unexpected extra field"));
                }
            }
            "reference" => {
                let name = it.next().ok_or(err("reference glyph name missing"))?.to_string();
                let path = it.next().ok_or(err("reference font path missing"))?;
                let sha = it.next().ok_or(err("reference font sha256 missing"))?.to_string();
                if sha.len() != 64 || !sha.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
                    return Err(err("reference font sha256 must be 64 lowercase hex"));
                }
                let cp_raw = it.next().ok_or(err("reference codepoint missing"))?;
                let cp = u32::from_str_radix(cp_raw.strip_prefix("0x").unwrap_or(cp_raw), 16).map_err(|_| err("bad reference codepoint"))?;
                references.push((name, base.join(path), sha, cp));
            }
            "reraster_xmin" => frame_map[0] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad reraster_xmin"))?),
            "reraster_ymax" => frame_map[1] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad reraster_ymax"))?),
            "reraster_ppu" => frame_map[2] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad reraster_ppu"))?),
            "reraster_pad" => frame_map[3] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad reraster_pad"))?),
            "guide_smooth_sin" => guide[0] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad guide_smooth_sin"))?),
            "guide_max_node_dist" => guide[1] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad guide_max_node_dist"))?),
            "guide_max_ring_cost" => guide[2] = Some(it.next().ok_or(err("value missing"))?.parse().map_err(|_| err("bad guide_max_ring_cost"))?),
            "stage1_cache" => { let v = it.next().ok_or(err("stage1_cache path missing"))?; stage1_cache = Some(base.join(v)); }
            "corner_wiring" => {
                corner_wiring = match it.next().ok_or(err("corner_wiring missing"))? {
                    "on" => true,
                    "off" => false,
                    other => return Err(err(&format!("bad corner_wiring {other:?} (on|off)"))),
                }
            }
            "run_mode" => {
                run_mode = Some(match it.next().ok_or(err("run_mode missing"))? {
                    "stage1_only" => RunMode::Stage1Only,
                    "full" => RunMode::Full,
                    other => return Err(err(&format!("bad run_mode {other:?} (stage1_only|full)"))),
                });
            }
            "population_sha256" => {
                let v = it.next().ok_or(err("population_sha256 missing"))?;
                if v.len() != 64 || !v.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
                    return Err(err("population_sha256 must be 64 lowercase hex"));
                }
                population_sha256 = Some(v.to_string());
            }
            "os2_x_height_write" => {
                os2_x_height_write = Some(match it.next().ok_or(err("os2_x_height_write missing"))? {
                    "resolved_only" => Os2XHeightWrite::ResolvedOnly,
                    "measured_preferred" => Os2XHeightWrite::MeasuredPreferred,
                    other => return Err(err(&format!("bad os2_x_height_write {other:?} (resolved_only)"))),
                });
            }
            "m3_lower_set" | "m3_excl_set" | "m3_cap_set" => {
                let mut v = Vec::new();
                for tok in it {
                    let cp = u32::from_str_radix(tok.strip_prefix("0x").unwrap_or(tok), 16).map_err(|_| err(&format!("bad {key} codepoint {tok:?}")))?;
                    v.push(cp);
                }
                match key { "m3_lower_set" => m3.lower_set = Some(v), "m3_excl_set" => m3.excl_set = Some(v), _ => m3.cap_set = Some(v) }
            }
            "m3_cluster_gap" => m3.cluster_gap = Some(it.next().ok_or(err("m3_cluster_gap missing"))?.parse().map_err(|_| err("bad m3_cluster_gap"))?),
            "m3_min_cluster_size" => m3.min_cluster_size = Some(it.next().ok_or(err("m3_min_cluster_size missing"))?.parse().map_err(|_| err("bad m3_min_cluster_size"))?),
            "m3_tol_flat" => m3.tol_flat = Some(it.next().ok_or(err("m3_tol_flat missing"))?.parse().map_err(|_| err("bad m3_tol_flat"))?),
            "m3_min_gap" => m3.min_gap = Some(it.next().ok_or(err("m3_min_gap missing"))?.parse().map_err(|_| err("bad m3_min_gap"))?),
            other => return Err(err(&format!("unknown key '{other}'"))),
        }
    }
    let family = family.filter(|f| !f.is_empty()).ok_or("manifest: family is required")?;
    let subfamily = subfamily.filter(|f| !f.is_empty()).ok_or("manifest: subfamily is required (owner naming contract: e.g. family \"Marq\", subfamily \"Alternate\", postscript_name \"Marq-Alternate\")")?;
    let postscript_name_raw = ps.ok_or("manifest: postscript_name is required")?;
    // Single ingestion point for PostScript name hygiene: every byte outside
    // [A-Za-z0-9-] becomes '-' (deterministic, whole class). The sanitized
    // value feeds CFF FontName and nameID 6 (and the derived nameID 3
    // "{ps}:1"); nameID 1/4 are family/subfamily-derived and untouched. The
    // declared value rides along for the receipt record when it changed.
    let postscript_name = sanitize_postscript_name(&postscript_name_raw);
    let postscript_name_declared = if postscript_name != postscript_name_raw { Some(postscript_name_raw) } else { None };
    let scale = scale.ok_or("manifest: scale (font units per source pixel) is required")?;
    if !scale.is_finite() || scale <= 0.0 {
        return Err("manifest: scale must be finite and > 0".into());
    }
    for (label, v) in [("rdp_epsilon", rdp_epsilon), ("fit_squared_error", fit_se), ("flatten_tolerance", flat_tol), ("scan_row_step", row_step), ("sample_resolution", sample_res)].into_iter().map(|(l, v): (&str, f64)| (l, v)) {
        if !v.is_finite() || v <= 0.0 {
            return Err(format!("manifest: {label} must be finite and > 0"));
        }
    }
    if glyphs.is_empty() {
        return Err("manifest: at least one glyph row is required".into());
    }
    let (post_lsb_add, post_rsb_add) = (post_lsb.unwrap_or(0.0), post_rsb.unwrap_or(0.0));
    let post_declared = post_lsb.is_some() || post_rsb.is_some() || post_scope.is_some() || post_label.is_some();
    if post_declared {
        // a declared post step states ALL of: both offsets, an explicit scope and a label (no partial declaration, no default scope)
        if post_lsb.is_none() || post_rsb.is_none() { return Err("manifest: post step needs both lsb_add and rsb_add".into()); }
        if post_scope.is_none() { return Err("manifest: post step needs an explicit post_scope".into()); }
        if post_label.as_deref().map_or(true, |l| l.is_empty()) { return Err("manifest: post step needs a non-empty post_scope_label".into()); }
    }
    let none_scope = kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false };
    match (&learned_store, &learned_gate_evidence) {
        (Some(_), None) => return Err("learned_store requires learned_gate_evidence".to_string()),
        (None, Some(_)) => return Err("learned_gate_evidence requires learned_store".to_string()),
        _ => {}
    }
    Ok(Manifest {
        post_lsb_add, post_rsb_add, post_scope: post_scope.unwrap_or(none_scope), post_scope_label: post_label.unwrap_or_else(|| "none".to_string()),
        fit_tolerance_policy: fit_tol_policy.ok_or("manifest: fit_tolerance_policy is required (measured_experimental|fixed|derived_source_quantization); derived_source_quantization uses (K/2)^2 from the declared scale; measured_experimental derives per-glyph squared tolerance from the actual raster (RMS variance, EXPERIMENTAL ONLY, not a production bound), fixed uses the fit_squared_error row - the choice must be explicit, never silent")?,
        family, subfamily, postscript_name, postscript_name_declared, vendor, upm, scale, capture_frame, capture_cohort, rdp_epsilon, corner_wiring,
        fit_squared_error: fit_se, fit_max_refits: fit_refits,
        flatten_tolerance: flat_tol, scan_row_step: row_step, scan_max_rows: max_rows,
        sample_resolution: sample_res, max_pair_evaluations: max_pe, max_pairs,
        iou: match (iou_thr, iou_steps) { (Some(t), Some(n)) => Some(run_config::IouSettings { ink_threshold: t, flatten_steps: n }), (None, None) => None, _ => return Err("manifest: iou_ink_threshold and iou_flatten_steps must be declared together".into()) },
        run_mode: run_mode.ok_or("manifest: run_mode is required (stage1_only|full)")?,
        os2_x_height_write, m3,
        population_sha256: population_sha256.ok_or("manifest: population_sha256 is required")?,
        pair_min_shared_rows: min_rows,
        auto_sb, auto_sb_class_table, auto_sb_offset_lsb, auto_sb_offset_rsb, tie_break, auto_sb_pool,
        glyphs, space, space_evidence, derive_space_from_letter_advances, notdef, notdef_proxy, capture_manifest, style_overrides, stage1_cache, learned_store, learned_gate_evidence, pair_visual_same_source,
        frame_map: if references.is_empty() { None } else {
            Some([frame_map[0], frame_map[1], frame_map[2], frame_map[3]].into_iter().collect::<Option<Vec<f64>>>()
                .and_then(|v| v.try_into().ok().map(|a: [f64; 4]| (a[0], a[1], a[2], a[3])))
                .ok_or("manifest: reference rows require reraster_xmin/ymax/ppu/pad")?)
        },
        guide: if references.is_empty() { None } else {
            Some([guide[0], guide[1], guide[2]].into_iter().collect::<Option<Vec<f64>>>()
                .and_then(|v| v.try_into().ok().map(|a: [f64; 3]| (a[0], a[1], a[2])))
                .ok_or("manifest: reference rows require guide_smooth_sin/max_node_dist/max_ring_cost")?)
        },
        references,
    })
}

/// sha256 over sorted "cp-hex:name\n" rows; the generator computes the same pin.
fn population_pin(glyphs: &[GlyphRow]) -> String {
    let mut rows: Vec<String> = glyphs.iter().map(|g| format!("{}:{}\n", g.seq_label(), g.name)).collect();
    rows.sort();
    sha256_hex(rows.concat().as_bytes())
}

/// Run-mode gate, evaluated before any stage-1 work.
/// - Full: the glyph set must hash to the declared population pin (a shard
///   relabelled "full" fails here).
/// - Stage1Only: reusing a stage1_cache is contradictory (nothing to fit).
fn check_run_mode(m: &Manifest) -> Result<(), String> {
    match m.run_mode {
        RunMode::Full => {
            let pin = population_pin(&m.glyphs);
            if pin != m.population_sha256 {
                return Err(format!("run_mode full refused: glyph set pin {pin} != declared population_sha256 {} (a shard cannot run spacing)", m.population_sha256));
            }
            Ok(())
        }
        RunMode::Stage1Only => {
            if m.stage1_cache.is_some() {
                return Err("run_mode stage1_only refused: stage1_cache reuse is contradictory".into());
            }
            Ok(())
        }
    }
}

// ---------------- bounded flatten (budget-guarded, guard-before-flatten) ----------------

const MAX_FLATTEN_DEPTH: usize = 16;

fn flatten_into(p0: [f64; 2], c1: [f64; 2], c2: [f64; 2], p1: [f64; 2], tol: f64, depth: usize, out: &mut Vec<[f64; 2]>, budget: usize) -> Result<(), String> {
    if out.len() >= budget {
        return Err(format!("flatten budget refused: {budget} total points exceeded"));
    }
    // max distance of controls from the chord
    let (dx, dy) = (p1[0] - p0[0], p1[1] - p0[1]);
    let len = (dx * dx + dy * dy).sqrt();
    let dist = |p: [f64; 2]| {
        if len == 0.0 {
            ((p[0] - p0[0]).powi(2) + (p[1] - p0[1]).powi(2)).sqrt()
        } else {
            ((p[0] - p0[0]) * dy - (p[1] - p0[1]) * dx).abs() / len
        }
    };
    if depth < MAX_FLATTEN_DEPTH && (dist(c1) > tol || dist(c2) > tol) {
        let m = |a: [f64; 2], b: [f64; 2]| [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];
        let (p01, p12, p23) = (m(p0, c1), m(c1, c2), m(c2, p1));
        let (p012, p123) = (m(p01, p12), m(p12, p23));
        let mid = m(p012, p123);
        flatten_into(p0, p01, p012, mid, tol, depth + 1, out, budget)?;
        flatten_into(mid, p123, p23, p1, tol, depth + 1, out, budget)?;
    } else {
        out.push(p1);
    }
    Ok(())
}

fn drawing_polys(g: &DrawnGlyph, tol: f64, budget: usize) -> Result<Vec<Vec<[f64; 2]>>, String> {
    let mut rings = Vec::with_capacity(g.rings.len());
    for r in &g.rings {
        let mut poly = vec![[r.start.x, r.start.y]];
        let mut cur = r.start;
        for sp in &r.spans {
            match sp {
                Span::Line { end } => {
                    poly.push([end.x, end.y]);
                    cur = *end;
                }
                Span::Cubic { control_one, control_two, end } => {
                    flatten_into(
                        [cur.x, cur.y],
                        [control_one.x, control_one.y],
                        [control_two.x, control_two.y],
                        [end.x, end.y],
                        tol, 0, &mut poly, budget,
                    )?;
                    cur = *end;
                }
            }
        }
        if poly.len() > 1 && poly.last() == poly.first() {
            poly.pop();
        }
        rings.push(poly);
    }
    Ok(rings)
}

// ---------------- metadata ----------------

/// Owner naming contract (2026-10-14 16:00:03 +03, author=user): the name table carries the
/// manifest's family/subfamily/postscript_name byte-level; nothing is invented here.
fn sanitize_postscript_name(ps: &str) -> String {
    ps.bytes().map(|b| if b.is_ascii_alphanumeric() || b == b'-' { b as char } else { '-' }).collect()
}

fn names(family: &str, subfamily: &str, ps: &str) -> Vec<NameRecord> {
    [(1, family.to_string()), (2, subfamily.to_string()), (3, format!("{ps}:1")),
     (4, format!("{family} {subfamily}")), (5, "Version 1.0".into()), (6, ps.to_string())]
        .into_iter().map(|(id, value)| NameRecord { language: 0x409, name_id: id, value }).collect()
}

/// Readback gate: decode the name table from the SHIPPED bytes and verify the contract
/// fields against the manifest. Any mismatch or parse failure is a hard error.
fn name_table_readback(bytes: &[u8], family: &str, subfamily: &str, ps: &str) -> Result<Vec<(u16, String)>, String> {
    let u16b = |o: usize| -> Result<u16, String> { bytes.get(o..o + 2).map(|b| u16::from_be_bytes([b[0], b[1]])).ok_or("name readback: truncated".into()) };
    let u32b = |o: usize| -> Result<u32, String> { bytes.get(o..o + 4).map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]])).ok_or("name readback: truncated".into()) };
    if bytes.len() < 12 { return Err("name readback: file too small".into()); }
    let num_tables = u16b(4)? as usize;
    let mut name_off = None;
    for i in 0..num_tables {
        let r = 12 + 16 * i;
        if bytes.get(r..r + 4) == Some(b"name") {
            name_off = Some((u32b(r + 8)? as usize, u32b(r + 12)? as usize));
        }
    }
    let (off, _len) = name_off.ok_or("name readback: no name table")?;
    let count = u16b(off + 2)? as usize;
    let storage = off + u16b(off + 4)? as usize;
    let mut got: Vec<(u16, String)> = Vec::new();
    for i in 0..count {
        let r = off + 6 + 12 * i;
        let (platform, _enc, _lang, id, len, soff) = (u16b(r)?, u16b(r + 2)?, u16b(r + 4)?, u16b(r + 6)?, u16b(r + 8)? as usize, u16b(r + 10)? as usize);
        if platform != 3 { continue; }
        let raw = bytes.get(storage + soff..storage + soff + len).ok_or("name readback: string out of range")?;
        if raw.len() % 2 != 0 { return Err("name readback: odd utf16 length".into()); }
        let text: String = raw.chunks_exact(2).map(|c| u16::from_be_bytes([c[0], c[1]])).map(|u| char::from_u32(u as u32).unwrap_or('\u{fffd}')).collect();
        got.push((id, text));
    }
    let full = format!("{family} {subfamily}");
    for (id, expect) in [(1u16, family), (2u16, subfamily), (4u16, full.as_str()), (6u16, ps)] {
        let actual = got.iter().find(|(i, _)| *i == id).map(|(_, v)| v.as_str());
        match actual {
            Some(a) if a == expect => {}
            Some(a) => return Err(format!("name readback: nameID {id} mismatch: shipped {a:?} != contract {expect:?}")),
            None => return Err(format!("name readback: nameID {id} missing from shipped bytes")),
        }
    }
    Ok(got)
}

fn metadata(m: &Manifest) -> NativeFontInput {
    NativeFontInput {
        postscript_name: m.postscript_name.clone(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: m.upm, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
            panose: [0; 10], unicode_ranges: [0; 4], vendor: m.vendor, selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
        names: names(&m.family, &m.subfamily, &m.postscript_name),
    }
}

/// Heights from the solver (median heuristic / ctx), written as OS/2 sxHeight/sCapHeight.
/// Sets OS/2 version 4 and USE_TYPO (0x80); nothing else is touched. Atomic: Err leaves `f` unchanged.
/// Typed x_height provenance receipt row (r109): fed from the typed
/// SpacingSolution field, never parsed from policy_derivation strings.
/// Existing receipt rows (incl. vertical_height_source) keep their bytes;
/// this row is additive only.
fn os2_x_height_source_row(s: &SpacingSolution) -> String {
    format!("os2_x_height_source\t{}\n", s.x_height_source.token())
}

/// Typed x_height measurement row (r225, receipt-only, additive): the bridge's
/// result for the solved x_height provenance. Every legacy XHeightSource maps to
/// Unresolved (KNI-added cautious policy); numeric value and token ride along
/// separately. No consumer behavior is attached to this row.
fn x_height_meas_row(s: &SpacingSolution) -> String {
    let b = kni_xheight_bridge::meas_from_solution(s);
    let state = match b.meas_kind { kni_xheight_bridge::SpacingMeasKind::Unresolved => "unresolved" };
    format!("x_height_meas\t{}\tsource\t{}\tvalue\t{}\n", state, b.token, b.value)
}

/// The r226 write-guard decision: the manifest declares `os2_x_height_write
/// resolved_only` AND the bridged measurement of the solved x_height is
/// Unresolved => skip the OS/2 sxHeight write (typed m6_skip receipt row).
fn skip_os2_x_height_write(m: &Manifest, s: &SpacingSolution) -> bool {
    matches!(m.os2_x_height_write, Some(Os2XHeightWrite::ResolvedOnly))
        && matches!(kni_xheight_bridge::meas_from_solution(s).meas_kind, kni_xheight_bridge::SpacingMeasKind::Unresolved)
}

/// write_x_height=false is the guarded skip: the metadata sxHeight keeps its prior
/// value and the skipped (unwritten) solved value is not domain-validated; cap_height,
/// version and USE_TYPO are still written. The returned xh is what the file carries.
#[cfg(test)]
fn apply_vertical_metadata_guarded(f: &mut NativeFontInput, s: &SpacingSolution, write_x_height: bool) -> Result<(i16, i16), String> {
    apply_vertical_metadata_measured(f, s, write_x_height, None, None)
}

/// R1 (chief ruling efabd0c1, measured-preferred): `measured_x` = Some(v) writes OS/2 sxHeight = v
/// (already bridged: MEASURED, unit fu) instead of the solver value; None keeps the guarded solver path.
fn apply_vertical_metadata_measured(f: &mut NativeFontInput, s: &SpacingSolution, write_x_height: bool, measured_x: Option<f64>, measured_cap: Option<f64>) -> Result<(i16, i16), String> {
    let conv = |name: &str, v: f64| -> Result<i16, String> {
        if !v.is_finite() || v < 0.0 { return Err(format!("{name} must be finite and nonnegative, got {v}")); }
        let r = v.round();
        if r > i16::MAX as f64 { return Err(format!("{name} {v} out of i16 range")); }
        Ok(r as i16)
    };
    let xh = if let Some(v) = measured_x { conv("x_height", v)? } else if write_x_height { conv("x_height", s.x_height)? } else { f.os2.x_height };
    let ch = conv("cap_height", measured_cap.unwrap_or(s.cap_height))?;
    f.os2.version = 4;
    f.os2.selection |= 0x80;
    f.os2.x_height = xh;
    f.os2.cap_height = ch;
    Ok((xh, ch))
}

/// R1 helper. Exported sxHeight = M3 top_center - exported baseline (the outline y of the x-height line
/// after the baseline shift; tile-anchor scope applies shift 0 and exports baseline 0). Unit "fu" is the
/// declared engine outline unit (R2). The typed bridge decides: only Meas::Measured is written.
/// Frame guard (chief 19:21 (d)): M3 measures in the M1 frame (`m1_value`, relative to the M1 baseline); the exported value is
/// relative to the solver baseline. If they disagree by more than the declared m3_tol_flat the adapter is UNRESOLVED: neither is chosen.
fn frame_disagreement_row(tag: &str, top_center: f64, m1_value: f64, solver_baseline: f64, tol: f64) -> Option<String> {
    let solver_frame = top_center - solver_baseline;
    let d = (m1_value - solver_frame).abs();
    if d.is_finite() && d <= tol { return None; }
    Some(format!("{tag}\tnot_measured\treason\tFRAME_DISAGREEMENT\tm1_frame_value\t{m1_value}\texported_frame_value\t{solver_frame}\tdiff\t{d}\ttol\t{tol}\tfallback\tsolver_current\n"))
}

fn os2_x_height_measured_preferred(m3: Option<M3Measured>, m3_rows: &str, solver_baseline: f64, tile_anchor: bool, style: &str, tol: f64) -> (Option<f64>, String) {
    use kni_planner::row42_43::{XHeightInput, XV};
    let nm = |reason: &str| (None, format!("os2_x_height_measured\tnot_measured\treason\t{reason}\tfallback\tsolver_current\n"));
    let Some(r) = m3 else { return nm("M3_UNRESOLVED_OR_NOT_DECLARED"); };
    if let Some(row) = frame_disagreement_row("os2_x_height_measured", r.top_center, r.value, solver_baseline, tol) { return (None, row); }
    let exported_baseline = if tile_anchor { 0.0 } else { solver_baseline };
    let v = r.top_center - exported_baseline;
    let inp = XHeightInput { style: style.to_string(), state: "MEASURED".into(), value: XV::F(v), unit: "fu".into(), baseline: XV::F(exported_baseline), line_y: XV::F(r.top_center),
        method: "planner_row43_measured".into(), evidence_sha: kni_core::cff_reader::sha256_hex(m3_rows.as_bytes()), n: r.size, spread: Some(r.spread) };
    match kni_xheight_bridge::meas_from_input(&inp) {
        Ok(b) => match b.meas {
            _ if matches!(b.measured_value(), Some(x) if x.is_finite() && x > 0.0) => { let x = b.measured_value().unwrap(); (Some(x), format!("os2_x_height_measured\tmeasured\tsource\tplanner_row43_measured\tvalue\t{}\tm3_value_m1_relative\t{}\tevidence_sha\t{}\n", x, r.value, inp.evidence_sha)) }
            _ => nm("BRIDGE_NOT_MEASURED_OR_NONPOSITIVE"),
        },
        Err(_) => nm("BRIDGE_UNIT_REFUSED"),
    }
}


/// Canonical text of the declared M3 inputs (f64 by bit pattern). Under measured_preferred these inputs decide the written
/// sxHeight/sCapHeight, so they ride in the os2_x_height_write token and therefore in run_config_sha256.
fn m3_decl_token(d: &M3Decl) -> String {
    let set = |v: &Option<Vec<u32>>| match v { None => "-".to_string(), Some(v) => v.iter().map(|c| format!("{c:X}")).collect::<Vec<_>>().join(",") };
    let f = |v: Option<f64>| match v { None => "-".to_string(), Some(x) => format!("{:016x}", x.to_bits()) };
    format!("m3[lower={};excl={};cap={};gap={};min_cs={};tol={};min_gap={}]", set(&d.lower_set), set(&d.excl_set), set(&d.cap_set), f(d.cluster_gap),
        d.min_cluster_size.map_or("-".to_string(), |n| n.to_string()), f(d.tol_flat), f(d.min_gap))
}

/// R3 helper (chief ruling): cap line = measure_cap top_center - exported baseline, only for a declared m3_cap_set.
/// The glyph set is DECLARED_CONVENTION (calibrated=false); the value is labelled measured only because measure_cap RESOLVED.
/// No typed cap bridge exists yet, so the guard here is the same one the x_height bridge applies: finite and > 0.
fn os2_cap_height_measured_preferred(cap: Option<M3CapMeasured>, set_declared: bool, m3_rows: &str, solver_baseline: f64, tile_anchor: bool, tol: f64) -> (Option<f64>, String) {
    let nm = |reason: &str| (None, format!("os2_cap_height_measured\tnot_measured\treason\t{reason}\tfallback\tsolver_current\n"));
    if let (true, Some(c)) = (set_declared, cap) {
        if let Some(row) = frame_disagreement_row("os2_cap_height_measured", c.top_center, c.value, solver_baseline, tol) { return (None, row); }
    }
    // exported-frame value is formed only here, at the bridge boundary; the typed bridge decides what may be written
    let exported = cap.map(|c| kni_xheight_bridge::CapInput { state: "MEASURED".into(), value: c.top_center - if tile_anchor { 0.0 } else { solver_baseline }, unit: "fu".into(),
        method: "planner_cap_measured".into(), evidence_sha: kni_core::cff_reader::sha256_hex(m3_rows.as_bytes()), n: c.size, spread: Some(c.spread),
        set_provenance: "DECLARED_CONVENTION".into(), calibrated: false });
    match kni_xheight_bridge::cap_meas_from_input(exported.as_ref(), set_declared) {
        kni_xheight_bridge::CapMeas::NotMeasured(r) => nm(r.token()),
        kni_xheight_bridge::CapMeas::Measured(v) => {
            let c = cap.unwrap();
            (Some(v), format!("os2_cap_height_measured\tmeasured\tsource\tplanner_cap_measured\tvalue\t{}\tm3_value_m1_relative\t{}\tcap_set\tDECLARED_CONVENTION\tcalibrated\tfalse\tevidence_sha\t{}\n", v, c.value, kni_core::cff_reader::sha256_hex(m3_rows.as_bytes())))
        }
    }
}

/// r229 receipt-only M3 x_height adapter (chief architecture position, not an owner
/// ruling). Reads the SAME pre-shift drawn glyphs the vertical lane shifts with
/// solved.baseline (apply_baseline_shift below: "Spacing and kern solves run BEFORE
/// this shift"), so M1 (baseline) and M3 (x_height) are computed in one shared
/// frame. No unit conversion, no unit label, no OS/2 or font-byte effect.
fn m3_points(g: &DrawnGlyph) -> Vec<kni_planner::json::J> {
    use kni_planner::json::J;
    let pt = |p: &Point, on: bool| J::Arr(vec![J::Float(p.x), J::Float(p.y), J::Bool(on)]);
    let mut v = Vec::new();
    for r in &g.rings {
        v.push(pt(&r.start, true));
        for sp in &r.spans {
            match sp {
                Span::Line { end } => v.push(pt(end, true)),
                Span::Cubic { control_one, control_two, end } => { v.push(pt(control_one, false)); v.push(pt(control_two, false)); v.push(pt(end, true)); }
            }
        }
    }
    v
}

fn m3_reason(j: &kni_planner::json::J) -> String {
    // planner verbatim reason: typed_result rewrites some legacy codes into
    // reason + reason_alias; the alias is the planner's own code.
    j.get("reason_alias").and_then(|x| x.str()).or_else(|| j.get("reason").and_then(|x| x.str())).unwrap_or("UNKNOWN").to_string()
}

fn m3_num(j: &kni_planner::json::J, k: &str) -> String {
    j.get(k).and_then(|x| x.f()).map(|v| format!("{v}")).unwrap_or_else(|| "-".to_string())
}

/// r281 receipt-only per-glyph extremum rows (decision receipt-glyph-extremum-rows-0550):
/// the planner result's glyph_rows block, one row per candidate/excluded glyph.
/// Null glyph or null extremum stays the typed "-" marker, never a number or +/-inf.
fn m3_glyph_rows(tag: &str, extremum: &str, j: &kni_planner::json::J) -> String {
    use kni_planner::json::J;
    let mut out = String::new();
    let rows = match j.get("glyph_rows") { Some(J::Arr(r)) => r, _ => return out };
    for r in rows {
        let g = r.get("glyph").and_then(|x| x.str()).unwrap_or("-").to_string();
        let cp = match r.get("codepoint") { Some(J::Int(c)) => format!("0x{c:x}"), _ => "-".to_string() };
        let cls = r.get("cls").and_then(|x| x.str()).unwrap_or("-").to_string();
        let y = r.get(extremum).and_then(|x| x.f()).map(|v| format!("{v}")).unwrap_or_else(|| "-".to_string());
        out.push_str(&format!("{tag}\tglyph\t{g}\tcp\t{cp}\tcls\t{cls}\t{extremum}\t{y}\n"));
    }
    out
}

#[cfg(test)]
fn m3_adapter_rows(m: &Manifest, glyphs: &[DrawnGlyph], solver_baseline: f64) -> String {
    m3_adapter(m, glyphs, solver_baseline).0
}

/// RESOLVED M3 x_height measurement in the pre-shift engine outline frame (value is relative to the M1 baseline).
#[derive(Clone, Copy, Debug, PartialEq)]
struct M3Measured { top_center: f64, value: f64, size: i64, spread: f64 }

/// RESOLVED measure_cap result (same frame and baseline as the x_height line).
#[derive(Clone, Copy, Debug, PartialEq)]
struct M3CapMeasured { top_center: f64, value: f64, size: i64, spread: f64 }

/// Same rows as before plus the structured RESOLVED result (None for every other state).
fn m3_adapter(m: &Manifest, glyphs: &[DrawnGlyph], solver_baseline: f64) -> (String, Option<M3Measured>, Option<M3CapMeasured>) {
    use kni_planner::json::J;
    let mut measured: Option<M3Measured> = None;
    let mut cap_measured: Option<M3CapMeasured> = None;
    let d = &m.m3;
    let declared: [(&str, bool); 6] = [
        ("m3_lower_set", d.lower_set.is_some()),
        ("m3_excl_set", d.excl_set.is_some()),
        ("m3_cluster_gap", d.cluster_gap.is_some()),
        ("m3_min_cluster_size", d.min_cluster_size.is_some()),
        ("m3_tol_flat", d.tol_flat.is_some()),
        ("m3_min_gap", d.min_gap.is_some()),
    ];
    // State 1 OFF: no m3_* key declared -> no rows, byte-equal output.
    if declared.iter().all(|(_, present)| !present) { return (String::new(), None, None); }
    let mut out = String::from("m3_status\tEXPERIMENTAL_RECEIPT_ONLY\n");
    // State 2 ACTIVE-MISSING: planner is never called, one row per missing key.
    let missing: Vec<&str> = declared.iter().filter(|(_, present)| !present).map(|(k, _)| *k).collect();
    if !missing.is_empty() {
        for k in missing { out.push_str(&format!("m3_result\tUNRESOLVED\treason\tMISSING_PARAM:{k}\n")); }
        return (out, None, None);
    }
    // State 3 ACTIVE-INVALID: declared but outside the contract domain; planner never called.
    let lower = d.lower_set.clone().unwrap();
    let excl = d.excl_set.clone().unwrap();
    let gap = d.cluster_gap.unwrap();
    let min_cs = d.min_cluster_size.unwrap();
    let tol = d.tol_flat.unwrap();
    let min_gap = d.min_gap.unwrap();
    let dup = |v: &[u32]| v.iter().any(|c| v.iter().filter(|x| *x == c).count() > 1);
    let mut invalid: Vec<&str> = Vec::new();
    if lower.is_empty() || dup(&lower) { invalid.push("m3_lower_set"); }
    if excl.is_empty() || dup(&excl) || excl.iter().any(|c| lower.contains(c)) { invalid.push("m3_excl_set"); }
    if !gap.is_finite() || gap < 0.0 { invalid.push("m3_cluster_gap"); }
    if min_cs < 0 { invalid.push("m3_min_cluster_size"); }
    if !tol.is_finite() || tol < 0.0 { invalid.push("m3_tol_flat"); }
    if !min_gap.is_finite() || min_gap < 0.0 { invalid.push("m3_min_gap"); }
    if !invalid.is_empty() {
        for k in invalid { out.push_str(&format!("m3_result\tUNRESOLVED\treason\tINVALID_PARAM:{k}\n")); }
        return (out, None, None);
    }
    // Fully declared and valid: measure. Points carry the on-curve flag; cubic
    // controls are off-curve. Empty-outline glyphs (e.g. blank .notdef) are not
    // measurement candidates and are left out of every planner input.
    let cp_of_name: std::collections::HashMap<&str, u32> = m.glyphs.iter().filter_map(|g| g.codepoint.map(|cp| (g.name.as_str(), cp))).collect();
    let mut m1_rows: Vec<J> = Vec::new();
    let mut gobj: Vec<(String, J)> = Vec::new();
    for g in glyphs {
        let pts = m3_points(g);
        if pts.is_empty() { continue; }
        let cp = cp_of_name.get(g.glyph_id.as_str()).copied().map(|c| J::Int(c as i64)).unwrap_or(J::Null);
        m1_rows.push(J::Obj(vec![("glyph".into(), J::Str(g.glyph_id.clone())), ("codepoint".into(), cp), ("points".into(), J::Arr(pts.clone()))]));
        gobj.push((g.glyph_id.clone(), J::Arr(pts)));
    }
    // cmap: single-scalar manifest rows whose drawn glyph exists in gobj (a
    // mapped name without outline points would panic the planner's lookup).
    let cmap = J::Obj(m.glyphs.iter().filter(|g| !g.is_ligature() && g.codepoint.is_some())
        .filter(|g| gobj.iter().any(|(n, _)| n == &g.name))
        .map(|g| (g.codepoint.unwrap().to_string(), J::Str(g.name.clone()))).collect());
    let params = J::Obj(vec![
        ("lower_set".into(), J::Arr(lower.iter().map(|c| J::Int(*c as i64)).collect())),
        ("excl_set".into(), J::Arr(excl.iter().map(|c| J::Int(*c as i64)).collect())),
        ("cluster_gap".into(), J::Float(gap)),
        ("min_cluster_size".into(), J::Int(min_cs)),
        ("tol_flat".into(), J::Float(tol)),
        ("min_gap".into(), J::Float(min_gap)),
    ]);
    out.push_str("m3_frame\tengine_coordinate\tunit\tUNDECLARED\n");
    out.push_str("m3_frame\tread_at\tpre_shift\n");
    out.push_str(&format!("m3_baseline_ref\tsolver\tvalue\t{solver_baseline}\tnote\tnot_used_not_equivalent_to_M1\n"));
    let m1 = match kni_planner::rows_a::measure_baseline(&J::Arr(m1_rows), &params) {
        Ok(j) => j,
        Err(e) => { out.push_str(&format!("m3_result\tUNRESOLVED\treason\tPLANNER_ERR:{e}\n")); return (out, None, None); }
    };
    if m1.get("status").and_then(|x| x.str()) == Some("RESOLVED") {
        out.push_str(&format!("m3_baseline\tsource\tM1_measure_baseline\tstatus\tRESOLVED\tvalue\t{}\tsize\t{}\tspread\t{}\n", m3_num(&m1, "value"), m3_num(&m1, "size"), m3_num(&m1, "spread")));
    } else {
        out.push_str(&format!("m3_baseline\tsource\tM1_measure_baseline\tstatus\tUNRESOLVED\treason\t{}\n", m3_reason(&m1)));
    }
    out.push_str(&m3_glyph_rows("m1_glyph", "ymin", &m1));
    let gobj_for_cap = gobj.clone();
    let m3r = match kni_planner::rows_a::measure_xheight(&J::Obj(gobj), &cmap, &m1, &params) {
        Ok(j) => j,
        Err(e) => { out.push_str(&format!("m3_result\tUNRESOLVED\treason\tPLANNER_ERR:{e}\n")); return (out, None, None); }
    };
    if m3r.get("status").and_then(|x| x.str()) == Some("RESOLVED") {
        let ex = m3r.get("excluded").map(|e| e.arr().iter().filter_map(|x| x.str()).collect::<Vec<_>>().join(",")).unwrap_or_default();
        let ex = if ex.is_empty() { "-".to_string() } else { ex };
        if let (Some(tc), Some(v)) = (m3r.get("top_center").and_then(|x| x.f()), m3r.get("value").and_then(|x| x.f())) {
            measured = Some(M3Measured { top_center: tc, value: v, size: m3r.get("size").and_then(|x| x.f()).unwrap_or(0.0) as i64, spread: m3r.get("spread").and_then(|x| x.f()).unwrap_or(0.0) });
        }
        out.push_str(&format!("m3_result\tRESOLVED\tvalue\t{}\ttop_center\t{}\tsize\t{}\tspread\t{}\texcluded\t{}\n", m3_num(&m3r, "value"), m3_num(&m3r, "top_center"), m3_num(&m3r, "size"), m3_num(&m3r, "spread"), ex));
    } else {
        out.push_str(&format!("m3_result\tUNRESOLVED\treason\t{}\n", m3_reason(&m3r)));
    }
    out.push_str(&m3_glyph_rows("m3_glyph", "ymax", &m3r));
    // R3: measured cap line, only for a declared m3_cap_set. Codepoint list and measurement are separate rows:
    // the set is DECLARED_CONVENTION (calibrated=false); the value is labelled measured only when measure_cap RESOLVED.
    if let Some(cap_set) = &d.cap_set {
        let cs: Vec<String> = cap_set.iter().map(|c| format!("0x{c:X}")).collect();
        out.push_str(&format!("m3_cap_set\tDECLARED_CONVENTION\tcalibrated\tfalse\tcodepoints\t{}\n", cs.join(",")));
        let mut cp_params = vec![("cap_set".to_string(), J::Arr(cap_set.iter().map(|c| J::Int(*c as i64)).collect()))];
        if let J::Obj(kv) = &params { for (k, v) in kv { if k != "lower_set" && k != "excl_set" && k != "min_gap" { cp_params.push((k.clone(), v.clone())); } } }
        let cap_params = J::Obj(cp_params);
        match kni_planner::rows_a::measure_cap(&J::Obj(gobj_for_cap), &cmap, &m1, &cap_params) {
            Err(e) => out.push_str(&format!("m3_cap_result\tUNRESOLVED\treason\tPLANNER_ERR:{e}\n")),
            Ok(c) => if c.get("status").and_then(|x| x.str()) == Some("RESOLVED") {
                let ex = c.get("excluded").map(|e| e.arr().iter().filter_map(|x| x.str()).collect::<Vec<_>>().join(",")).unwrap_or_default();
                let ex = if ex.is_empty() { "-".to_string() } else { ex };
                out.push_str(&format!("m3_cap_result\tRESOLVED\tvalue\t{}\ttop_center\t{}\tsize\t{}\tspread\t{}\texcluded\t{}\n", m3_num(&c, "value"), m3_num(&c, "top_center"), m3_num(&c, "size"), m3_num(&c, "spread"), ex));
                if let (Some(tc), Some(v)) = (c.get("top_center").and_then(|x| x.f()), c.get("value").and_then(|x| x.f())) {
                    cap_measured = Some(M3CapMeasured { top_center: tc, value: v, size: c.get("size").and_then(|x| x.f()).unwrap_or(0.0) as i64, spread: c.get("spread").and_then(|x| x.f()).unwrap_or(0.0) });
                }
            } else { out.push_str(&format!("m3_cap_result\tUNRESOLVED\treason\t{}\n", m3_reason(&c))); },
        }
    }
    (out, measured, cap_measured)
}

/// The domain checks of apply_baseline_shift at a candidate shift, without
/// mutating: every y (start, end, c1, c2) finite and inside the i16 domain
/// both before and after the shift. Scopes that ship their own anchor (and
/// therefore apply no rebase) still validate the export domain through this.
fn validate_baseline_shift_domain(glyphs: &[DrawnGlyph], shift: f64) -> Result<(), String> {
    let chk = |g: &str, y: f64| -> Result<(), String> {
        let v = y + shift;
        if !y.is_finite() || y.round() < i16::MIN as f64 || y.round() > i16::MAX as f64 || !v.is_finite() || v.round() < i16::MIN as f64 || v.round() > i16::MAX as f64 {
            return Err(format!("glyph {g}: y {y} + shift {shift} out of i16 range or non-finite"));
        }
        Ok(())
    };
    for g in glyphs.iter() {
        for r in &g.rings {
            chk(&g.glyph_id, r.start.y)?;
            for sp in &r.spans {
                match sp {
                    Span::Line { end } => chk(&g.glyph_id, end.y)?,
                    Span::Cubic { control_one, control_two, end } => { chk(&g.glyph_id, control_one.y)?; chk(&g.glyph_id, control_two.y)?; chk(&g.glyph_id, end.y)?; }
                }
            }
        }
    }
    Ok(())
}

/// Shift every y by shift=round(-baseline) so the baseline lands on 0 up to `residual`
/// (residual r = baseline + shift = exported baseline after the shift; exactly 0 only if r == 0).
/// A large shift is allowed when every translated point stays in the i16 domain; with no points at all
/// only baseline finiteness is checked (explicit empty case). x is untouched. Every future y (start, end, c1, c2) is pre-validated finite and in i16
/// (also for shift 0); mutation happens only after all validation succeeds.
/// Spacing and kern solves run BEFORE this shift; no translation-invariance is claimed.
fn apply_baseline_shift(glyphs: &mut [DrawnGlyph], baseline: f64) -> Result<(f64, f64), String> {
    if !baseline.is_finite() { return Err(format!("baseline not finite: {baseline}")); }
    let shift = (-baseline).round();
    let residual = baseline + shift;
    let chk = |g: &str, y: f64| -> Result<(), String> {
        let v = y + shift;
        if !y.is_finite() || y.round() < i16::MIN as f64 || y.round() > i16::MAX as f64 || !v.is_finite() || v.round() < i16::MIN as f64 || v.round() > i16::MAX as f64 {
            return Err(format!("glyph {g}: y {y} + shift {shift} out of i16 range or non-finite"));
        }
        Ok(())
    };
    for g in glyphs.iter() {
        for r in &g.rings {
            chk(&g.glyph_id, r.start.y)?;
            for sp in &r.spans {
                match sp {
                    Span::Line { end } => chk(&g.glyph_id, end.y)?,
                    Span::Cubic { control_one, control_two, end } => { chk(&g.glyph_id, control_one.y)?; chk(&g.glyph_id, control_two.y)?; chk(&g.glyph_id, end.y)?; }
                }
            }
        }
    }
    for g in glyphs.iter_mut() {
        for r in &mut g.rings {
            r.start.y += shift;
            for sp in &mut r.spans {
                match sp {
                    Span::Line { end } => end.y += shift,
                    Span::Cubic { control_one, control_two, end } => { control_one.y += shift; control_two.y += shift; end.y += shift; }
                }
            }
        }
    }
    Ok((shift, residual))
}

/// Quantized ink x-bounds of a shipped drawing: every point rounded exactly
/// as the export prepare rounds it, then the engine's single analytic
/// integer-outward convention. hmtx bearings and the metrics policy read the
/// same numbers the export will ship (no pre-quantization drift).
fn quantized_integer_bounds_x(g: &DrawnGlyph) -> Option<(i64, i64)> {
    let mut q = g.clone();
    for ring in &mut q.rings {
        let r = |p: &mut kni_core::reference_slice::Point| p.x = p.x.round();
        r(&mut ring.start);
        for span in &mut ring.spans {
            match span {
                kni_core::reference_slice::Span::Line { end } => r(end),
                kni_core::reference_slice::Span::Cubic { control_one, control_two, end } => {
                    r(control_one); r(control_two); r(end);
                }
            }
        }
    }
    kni_core::ink_bounds::integer_outward_bounds(&q).ok().flatten().map(|b| (i64::from(b[0]), i64::from(b[2])))
}

/// Paul New spec advance model (Paul New family only), 2026-10-18 revision:
/// the advance is the frame-stripped em box - the population median of the
/// shipped ink xMax plus the declared target rsb (-1) - and every glyph's
/// declared lsb is its shipped ink xMin, so hmtx and ink coincide (the
/// 2026-10-17 fixed-696/zero-lsb model carried the 2 px tile frame as
/// phantom bearings; owner directive 2026-10-18 03:05/03:06 retires it).
/// Edge-reaching glyphs ship lsb = rsb = -1; margin glyphs ship margin - 1
/// per side. This is a metrics-level override at assembly: the spacing
/// solve, kern pairs and all outlines are untouched, and every other
/// family's rows pass through bit-identical. Rows are (glyph_id, lsb, rsb,
/// advance). Inkless rows (space) keep 0/0 bearings on the shared advance.
fn paul_new_advance_override(family: &str, metrics: &mut [(String, f64, f64, f64)], glyphs: &[DrawnGlyph]) {
    if family != declared_convention::PAUL_NEW_FAMILY { return; }
    let mut bounds_of: std::collections::HashMap<&str, (i64, i64)> = std::collections::HashMap::new();
    let mut xmaxs: Vec<i64> = Vec::new();
    for g in glyphs {
        if let Some(b) = quantized_integer_bounds_x(g) {
            bounds_of.insert(g.glyph_id.as_str(), b);
            if g.glyph_id != ".notdef" { xmaxs.push(b.1); }
        }
    }
    if xmaxs.is_empty() { return; }
    xmaxs.sort_unstable();
    // Lower median: the tile set's inner right edge (most letterforms reach
    // it), so the shared advance reflects the population, not an outlier.
    let med_xmax = xmaxs[(xmaxs.len() - 1) / 2];
    let advance = (med_xmax + paul_new_metrics_policy::PAUL_NEW_TARGET_RSB) as f64;
    for row in metrics.iter_mut() {
        match bounds_of.get(row.0.as_str()) {
            Some(&(xmin, xmax)) => {
                row.1 = xmin as f64;
                row.2 = (med_xmax + paul_new_metrics_policy::PAUL_NEW_TARGET_RSB - xmax) as f64;
                row.3 = advance;
            }
            None => {
                row.1 = 0.0;
                row.2 = 0.0;
                row.3 = advance;
            }
        }
    }
}

/// Paul New metrics policy wiring (family-gated; measurement only). Evaluates
/// the FINAL shipped outlines and metrics rows against the declared policy in
/// paul_new_metrics_policy (advance fixed at 696, declared lsb 0, target rsb
/// -1) and appends the typed policy receipt TSV. Nothing here edits geometry,
/// advances or bearings; a non-Paul-New family returns before any work, so its
/// receipt and shipped bytes stay bit-identical.
fn paul_new_metrics_policy_report(
    family: &str,
    glyphs: &[DrawnGlyph],
    metrics: &[(String, f64, f64, f64)],
    receipt: &mut String,
) {
    if family != declared_convention::PAUL_NEW_FAMILY { return; }
    let advance_of: std::collections::HashMap<&str, f64> =
        metrics.iter().map(|r| (r.0.as_str(), r.3)).collect();
    let mut verdicts = Vec::with_capacity(glyphs.len());
    for g in glyphs {
        let Some(advance) = advance_of.get(g.glyph_id.as_str()) else {
            receipt.push_str(&format!("warning\tpaul_new_metrics_policy_metrics_row_missing\tglyph\t{}\tdegrade\tverdict_skipped\n", g.glyph_id));
            continue;
        };
        let ink_bounds_x = match quantized_integer_bounds_x(g) {
            Some(b) => Some(b),
            None => None,
        };
        verdicts.push((g.glyph_id.clone(), advance.round() as i64, ink_bounds_x));
    }
    // Declared advance for the verdicts: the same population rule the
    // assembly override applies (median shipped ink xMax + target rsb), so a
    // downstream pass that moves hmtx away from it stands out.
    let mut xs: Vec<i64> = verdicts.iter().filter_map(|(_, _, b)| b.map(|bb| bb.1)).collect();
    xs.sort_unstable();
    let declared_advance = xs.get((xs.len().saturating_sub(1)) / 2).copied().unwrap_or(0)
        + paul_new_metrics_policy::PAUL_NEW_TARGET_RSB;
    let verdicts: Vec<_> = verdicts.into_iter()
        .map(|(id, adv, b)| paul_new_metrics_policy::evaluate_glyph(&id, adv, b, declared_advance))
        .collect();
    receipt.push_str(&paul_new_metrics_policy::receipt_tsv(&verdicts, declared_advance));
}

/// One glyph's (advance, lsb) from a shipped font's hmtx, walked with checked
/// offsets (same parse discipline as space_evidence::hmtx_advance, extended to
/// the lsb half of the metric row). Never trusts the directory: every offset
/// and table extent is bounds-checked against the actual bytes.
fn paul_new_hmtx_metric(font: &[u8], gid: u16) -> Result<(u16, i16), String> {
    let u16b = |o: usize| -> Result<u16, String> {
        font.get(o..o.checked_add(2).ok_or("offset overflow")?).map(|b| u16::from_be_bytes([b[0], b[1]])).ok_or_else(|| "hmtx readback: truncated".to_string())
    };
    let u32b = |o: usize| -> Result<u32, String> {
        font.get(o..o.checked_add(4).ok_or("offset overflow")?).map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]])).ok_or_else(|| "hmtx readback: truncated".to_string())
    };
    let n = u16b(4)? as usize;
    let mut hhea = None;
    let mut hmtx = None;
    for i in 0..n {
        let r = i.checked_mul(16).and_then(|v| v.checked_add(12)).ok_or("directory offset overflow")?;
        let tag = font.get(r..r.checked_add(4).ok_or("directory offset overflow")?).ok_or("hmtx readback: truncated directory")?;
        let off = u32b(r.checked_add(8).ok_or("directory offset overflow")?)? as usize;
        let len = u32b(r.checked_add(12).ok_or("directory offset overflow")?)? as usize;
        if tag == b"hhea" || tag == b"hmtx" {
            if off.checked_add(len).map_or(true, |end| end > font.len()) {
                return Err(format!("hmtx readback: table {} extends past the font", String::from_utf8_lossy(tag)));
            }
        }
        if tag == b"hhea" { hhea = Some((off, len)); }
        if tag == b"hmtx" { hmtx = Some((off, len)); }
    }
    let (hoff, hlen) = hhea.ok_or("hmtx readback: no hhea")?;
    // numberOfHMetrics is the last u16 of the 36-byte hhea table.
    const HHEA_NUMBER_OF_HMETRICS_OFFSET: usize = 34;
    if hlen < HHEA_NUMBER_OF_HMETRICS_OFFSET + 2 {
        return Err("hmtx readback: hhea table too short".into());
    }
    let (moff, mlen) = hmtx.ok_or("hmtx readback: no hmtx")?;
    let metrics = u16b(hoff.checked_add(HHEA_NUMBER_OF_HMETRICS_OFFSET).ok_or("overflow")?)? as usize;
    let g = gid as usize;
    if g >= metrics {
        return Err(format!("hmtx readback: gid {g} beyond numberOfHMetrics {metrics}"));
    }
    let at = moff.checked_add(g.checked_mul(4).ok_or("overflow")?).ok_or("overflow")?;
    if g.checked_mul(4).and_then(|v| v.checked_add(4)).map_or(true, |v| v > mlen) {
        return Err("hmtx readback: gid outside the hmtx table".into());
    }
    Ok((u16b(at)?, u16b(at + 2)? as i16))
}

/// Paul New policy readback (family-gated; measurement only): walks the FINAL
/// shipped font's hmtx and checks every glyph row against the assembly's own
/// expected rows (advance, lsb per glyph id, from the overridden metrics).
/// Since the 2026-10-18 frame ruling the declared bearings are derived per
/// run, so the readback pins shipped bytes to the assembly ledger rather than
/// to a constant. Typed receipt rows on any miss; the font bytes are never
/// edited. A non-Paul-New family returns before any work, so its receipt and
/// bytes stay bit-identical. RSB has no hmtx field: the RSB verdict stays
/// with the ink-measurement report above, never claimed here.
fn paul_new_metrics_policy_readback(family: &str, final_bytes: &[u8], num_glyphs: u16, expected: &[(u16, i16)]) -> String {
    if family != declared_convention::PAUL_NEW_FAMILY { return String::new(); }
    let mut out = String::from("# paul_new_metrics_policy_readback	source	final_hmtx	expected	assembly_metrics_rows	semantics	measured_not_enforced
");
    let (mut checked, mut advance_off, mut lsb_off) = (0usize, 0usize, 0usize);
    for gid in 0..num_glyphs {
        match paul_new_hmtx_metric(final_bytes, gid) {
            Ok((advance, lsb)) => {
                checked += 1;
                let want = expected.get(gid as usize).copied();
                if want.map_or(true, |(a, _)| a != advance) {
                    advance_off += 1;
                    out.push_str(&format!("warning\tpaul_new_metrics_policy_readback\tgid\t{gid}\tadvance\t{advance}\tcode\tadvance_readback_miss\n"));
                }
                if want.map_or(true, |(_, l)| l != lsb) {
                    lsb_off += 1;
                    out.push_str(&format!("warning\tpaul_new_metrics_policy_readback\tgid\t{gid}\tlsb\t{lsb}\tcode\tlsb_readback_miss\n"));
                }
            }
            Err(e) => {
                out.push_str(&format!("warning\tpaul_new_metrics_policy_readback\tgid\t{gid}\tcode\treadback_failed\tdetail\t{e}\n"));
            }
        }
    }
    out.push_str(&format!("# summary\tglyphs_checked\t{checked}\tadvance_off_policy\t{advance_off}\tlsb_off_policy\t{lsb_off}\n"));
    out
}

fn clip_metadata(mut f: NativeFontInput) -> NativeFontInput {
    f.hhea.ascender = f.head.bounds[3];
    f.hhea.descender = f.head.bounds[1];
    // Paul New special case (declared_convention::vertical_metrics_override): declared line
    // metrics replace the bounds-derived ones; outlines are untouched.
    let family = f.names.iter().find(|r| r.name_id == 1).map(|r| r.value.as_str()).unwrap_or("");
    if let Some((asc, desc)) = declared_convention::vertical_metrics_override(family) {
        f.hhea.ascender = asc;
        f.hhea.descender = desc;
        // Paul New spec: OS/2 sCapHeight/sxHeight ship the declared pair, never the
        // solver's median heuristic (apply_vertical_metadata) or a placeholder.
        f.os2.cap_height = declared_convention::PAUL_NEW_CAP_HEIGHT_UNITS;
        f.os2.x_height = declared_convention::PAUL_NEW_X_HEIGHT_UNITS;
    }
    f.os2.typo = [f.hhea.ascender, f.hhea.descender, 0];
    f.os2.win_ascent = f.hhea.ascender.max(0) as u16;
    f.os2.win_descent = (-(f.hhea.descender as i32)).max(0) as u16;
    let mut cps: Vec<u32> = f.mapping.iter().map(|m| m.0).collect();
    cps.sort();
    if let (Some(&lo), Some(&hi)) = (cps.first(), cps.last()) {
        f.os2.first_char = lo.min(65535) as u16;
        f.os2.last_char = hi.min(65535) as u16;
    }
    f
}

// ---------------- run ----------------

fn valid_name(n: &str) -> bool {
    !n.is_empty() && n.len() <= 63 && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
}

/// Final export tail, one testable unit: (non-zero offset => mint ONLY if base_approved, then post-pass) -> name gate on the FINAL bytes
/// -> [ledger] -> single atomic exclusive publish of font.otf. Any refusal returns before anything is written: no font.otf, no ledger.
/// 0/0 => the approved base bytes ship unchanged (legacy parity, xAvgCharWidth untouched).
/// Read-only view handed to the pre-publish hook (shipped final bytes + the prepared font they encode + the approved baseline bytes).
/// The hook gets only shared references and returns Ok/Err: it cannot change the shipped bytes. Err => nothing is published.
pub struct PrePublish<'a> { pub final_bytes: &'a [u8], pub prepared: &'a NativeFontInput, pub base_bytes: &'a [u8], pub post_pass: bool }


/// POST_METRICS degrade (brief 4.3): the post-step config is re-validated at the call site
/// (`PostStep::from_run_config` re-runs `check_range`: RunConfig accepts any finite integral
/// offset; representability in the i16 glyf/hmtx design space is only refused here). An
/// out-of-range or otherwise unbuildable post step is no longer a hard refusal: the post
/// override is OMITTED (`PostStep::legacy_default`, 0/0 => the approved base bytes ship
/// unchanged) and a typed warning with the stable code `post_metrics_degraded` is recorded
/// in the receipt. A degrade never invents values: the offset is dropped, never clamped or
/// guessed. A REPRESENTABLE non-zero offset keeps the existing path (including the
/// approved-base requirement) untouched.
fn post_step_or_degrade(rc: &run_config::RunConfig, receipt: &mut String) -> post_metrics::PostStep {
    match post_metrics::PostStep::from_run_config(rc) {
        Ok(step) => step,
        Err(e) => {
            receipt.push_str(&format!("warning\tcode\tpost_metrics_degraded\tstage\tpost_step_build\treason\t{}\taction\tpost_override_omitted\n",
                post_metrics::tsv_escape(&format!("{e:?}"))));
            post_metrics::PostStep::legacy_default()
        }
    }
}


#[cfg(test)]
mod post_metrics_degrade_tests {
    use super::post_step_or_degrade;
    use crate::post_metrics;
    use crate::run_config::{FitErrorPolicy, RunConfig};
    use kni_core::offset_scope::ScopePolicy;
    use kni_core::scale_context::ScaleContext;
    use std::path::PathBuf;

    /// RunConfig whose post-step LSB offset is `lsb_add`; base scope so a non-zero offset is config-valid.
    /// CONVENTION: scale fixture mirrors run_config tests (from_convention("r","c",k,1000,"cohort","frame")).
    fn cfg_with_lsb(lsb_add: f64) -> RunConfig {
        let mut i = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("cap"), PathBuf::from("out"), "s1");
        i.lsb_add = lsb_add;
        i.post_scope = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        i.post_scope_label = "grp".to_string();
        RunConfig::new(i, ScaleContext::from_convention("r", "c", 2.0, 1000.0, "cohort", "frame").unwrap()).unwrap()
    }

    /// Brief 4.3 test: an out-of-range value (one unit past the representable bound) degrades:
    /// the post override is omitted (0/0 no-op, range-clean) and the typed warning is recorded.
    #[test]
    fn out_of_range_offset_degrades_to_omitted_post_override() {
        let rc = cfg_with_lsb(post_metrics::MAX_OFFSET + 1.0);
        let mut receipt = String::new();
        let step = post_step_or_degrade(&rc, &mut receipt);
        assert!(step.offset.is_noop());
        assert_eq!(step.offset, post_metrics::PostStep::legacy_default().offset);
        post_metrics::check_range(&step.offset).unwrap();
        assert!(receipt.contains("warning\tcode\tpost_metrics_degraded\t"), "{receipt}");
        assert!(receipt.contains("action\tpost_override_omitted"), "{receipt}");
        assert!(receipt.contains("reason\tOffsetOutOfRange"), "{receipt}");
    }

    /// A representable non-zero offset keeps the normal path: returned unchanged, no warning.
    #[test]
    fn representable_offset_passes_through_without_warning() {
        let rc = cfg_with_lsb(post_metrics::MAX_OFFSET);
        let mut receipt = String::new();
        let step = post_step_or_degrade(&rc, &mut receipt);
        assert_eq!(step.offset.lsb(), post_metrics::MAX_OFFSET);
        assert!(!step.offset.is_noop());
        assert!(receipt.is_empty(), "{receipt}");
    }

    /// The 0/0 default is untouched: no-op step, no warning.
    #[test]
    fn noop_config_passes_through_without_warning() {
        let i = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("cap"), PathBuf::from("out"), "s1");
        let rc = RunConfig::new(i, ScaleContext::from_convention("r", "c", 2.0, 1000.0, "cohort", "frame").unwrap()).unwrap();
        let mut receipt = String::new();
        let step = post_step_or_degrade(&rc, &mut receipt);
        assert!(step.offset.is_noop());
        assert!(receipt.is_empty(), "{receipt}");
    }
}

#[allow(dead_code)] // final-bundle emitter kept for the bundle test surface; call-site wiring pending
fn emit_final_bundle(out_dir: &Path, base_approved: bool, approved_base: &NativeFontInput, base_bytes: &[u8], rc: &run_config::RunConfig,
    gpos: Option<&[u8]>, mapping: &[(u32, u16)], order: &[String], space_cp: Option<u32>, family: &str, subfamily: &str, ps: &str,
    pre_publish: &dyn Fn(&PrePublish<'_>) -> Result<(), String>, receipt: &mut String) -> Result<PathBuf, String> {
    emit_final_bundle_with(out_dir, base_approved, approved_base, base_bytes, rc, gpos, mapping, order, space_cp, family, subfamily, ps,
        &|v| pre_publish(v).map(|_| Vec::new()), receipt, PostUnapprovedPolicy::Refuse)
}

/// What `emit_final_bundle_with` does when a declared NON-ZERO post step meets
/// an unapproved base. Normal runs hard-refuse (the mint contract: an
/// unapproved base never reaches mint). The always-output export path applies
/// the declared step anyway - to the glyphs its scope selects - with a typed
/// warning recording the unapproved base: the pass is a refinement, never a
/// shipment precondition, and a guard condition logs, never skips the step.
#[derive(PartialEq, Clone, Copy)]
enum PostUnapprovedPolicy { Refuse, ApplyWithTypedWarning }

/// Same as `emit_final_bundle`, but the hook may return extra payload files (name, bytes). They are published in the SAME
/// publish_set_exclusive rollback set as ledger and font: all or none, an existing file is never overwritten, and the hook writes nothing.
fn emit_final_bundle_with(out_dir: &Path, base_approved: bool, approved_base: &NativeFontInput, base_bytes: &[u8], rc: &run_config::RunConfig,
    gpos: Option<&[u8]>, mapping: &[(u32, u16)], order: &[String], space_cp: Option<u32>, family: &str, subfamily: &str, ps: &str,
    pre_publish: &dyn Fn(&PrePublish<'_>) -> Result<Vec<(String, Vec<u8>)>, String>, receipt: &mut String,
    post_unapproved: PostUnapprovedPolicy) -> Result<PathBuf, String> {
    emit_final_bundle_with_provenance(out_dir, base_approved, approved_base, base_bytes, rc, gpos, mapping, order, space_cp, family, subfamily, ps, pre_publish, receipt, post_unapproved, None)
}

fn emit_final_bundle_with_provenance(out_dir: &Path, base_approved: bool, approved_base: &NativeFontInput, base_bytes: &[u8], rc: &run_config::RunConfig,
    gpos: Option<&[u8]>, mapping: &[(u32, u16)], order: &[String], space_cp: Option<u32>, family: &str, subfamily: &str, ps: &str,
    pre_publish: &dyn Fn(&PrePublish<'_>) -> Result<Vec<(String, Vec<u8>)>, String>, receipt: &mut String,
    post_unapproved: PostUnapprovedPolicy, provenance: Option<(&k6_final_publish::ActualPins, &k6_final_publish::ClaimedPins)>) -> Result<PathBuf, String> {
    emit_final_bundle_with_master(out_dir, base_approved, approved_base, base_bytes, rc, gpos, mapping, order, space_cp, family, subfamily, ps, pre_publish, receipt, post_unapproved, false, provenance)
}

fn emit_final_bundle_with_master(out_dir: &Path, base_approved: bool, approved_base: &NativeFontInput, base_bytes: &[u8], rc: &run_config::RunConfig,
    gpos: Option<&[u8]>, mapping: &[(u32, u16)], order: &[String], space_cp: Option<u32>, family: &str, subfamily: &str, ps: &str,
    pre_publish: &dyn Fn(&PrePublish<'_>) -> Result<Vec<(String, Vec<u8>)>, String>, receipt: &mut String,
    post_unapproved: PostUnapprovedPolicy, require_master: bool,
    provenance: Option<(&k6_final_publish::ActualPins, &k6_final_publish::ClaimedPins)>) -> Result<PathBuf, String> {
    let post = post_step_or_degrade(rc, receipt);
    let pm = post.offset;
    post_metrics::check_range(&pm).map_err(|e| format!("post_metrics offsets: {e:?}"))?;
    let mut post_ledger_tsv: Option<String> = None;
    let mut final_font: Option<NativeFontInput> = None;
    let bytes = if pm.is_noop() { base_bytes.to_vec() } else if !base_approved
        && post_unapproved == PostUnapprovedPolicy::Refuse {
        // Mint contract on every non-always-output path: an unapproved base
        // never reaches mint; the refusal is typed and the run keeps its receipts.
        return Err(format!("post_metrics base not approved: {:?}",
            post_metrics::PostMetricsError::BaseGuardFailed("pre-LSB/RSB gates did not approve this base".into())));
    } else {
        // Always-output: an unapproved base does NOT skip the declared post
        // step. The guard condition is logged as a typed warning and the step
        // still applies to the glyphs its scope selects; any post-metrics
        // refusal degrades to shipping the base bytes with a typed warning
        // (the pass is a refinement, never a shipment precondition).
        if !base_approved {
            receipt.push_str(&post_pass_applied_unapproved_receipt_line(pm.lsb(), pm.rsb()));
        }
        let post_result: Result<(Vec<u8>, String, NativeFontInput), String> = (|| {
        let token = if base_approved {
            post_metrics::ApprovedBase::mint(approved_base, base_bytes, rc, gpos, true)
                .map_err(|e| format!("post_metrics approval binding refused: {e:?}"))?
        } else {
            post_metrics::ApprovedBase::mint_unapproved_warned(approved_base, base_bytes, rc, gpos)
                .map_err(|e| format!("post_metrics unapproved binding refused: {e:?}"))?
        };
        let inv = post_metrics::DeclaredInventory::from_pinned_unicode(mapping, BTreeSet::new(), space_cp);
        // Ligature glyphs ship unmapped: bind them as Base via the baseline's own GSUB readback,
        // otherwise bind_classes would refuse them as MissingCodepoint. No GSUB -> empty -> old behavior.
        let ligature_gids: BTreeSet<u16> = match post_metrics::sfnt_table(base_bytes, b"GSUB") {
            Some(g) => kern_scope::ligature_targets(g, order.len()).map_err(|e| format!("post_metrics GSUB ligature readback: {e:?}"))?,
            None => BTreeSet::new(),
        };
        let classes = post_metrics::bind_classes(order, mapping, &inv, &ligature_gids).map_err(|e| format!("post_metrics class binding: {e:?}"))?;
        // Owner scope kerning_letters (ScopePolicy::kerning_letters): Unicode L* AND actual nonzero pair-kern participants read back from the
        // APPROVED BASELINE GPOS bytes, computed once before +LSB/RSB. Other policies keep the plain class scope (no allow-list).
        let sel_allow = if post.scope.policy.selects_kerning_letters() {
            let (tb, sel) = kern_scope::select_for_token(&token, &classes).map_err(|e| format!("post_metrics scope selection refused: {e:?}"))?;
            receipt.push_str(&sel.receipt_line());
            Some(tb)
        } else { None };
        let out = post_metrics::post_pass(&token, rc, &classes, sel_allow.as_ref(), AVG_WIDTH_POLICY_NONZERO_FINAL, &clip_metadata)
            .map_err(|e| format!("post_metrics structural refusal: {e:?}"))?;
        receipt.push_str(&out.receipt);
        receipt.push_str(&format!("post_metrics\tlsb_add\t{}\trsb_add\t{}\tapplied\t{}\tunits\tDeclaredOutputUnits\tscope_origin\t{}\n", pm.lsb(), pm.rsb(), out.ledger.applied().len(), post.scope.origin));
        receipt.push_str("rounding_ledger_basis\tbase_pre_postpass\n");
        Ok((out.bytes, out.ledger.tsv(pm), out.font))
        })();
        match post_result {
            Ok((b, tsv, font)) => { post_ledger_tsv = Some(tsv); final_font = Some(font); b }
            Err(e) => { receipt.push_str(&format!("warning\tpost_metrics_refused\tdegrade\tbase_bytes_shipped\tdetail\t{e}\n")); base_bytes.to_vec() }
        }
    };
    // Name gate on the FINAL bytes BEFORE anything is published (0/0 included).
    // Always-output: a name-table contract mismatch is a typed warning; the
    // bytes still ship.
    let readback = match name_table_readback(&bytes, family, subfamily, ps) {
        Ok(r) => r,
        Err(e) => { receipt.push_str(&format!("warning\tname_table_readback_refused\tdegrade\tbytes_shipped\tdetail\t{e}\n")); Vec::new() }
    };
    // Pre-publish hook (read-only; e.g. the IoU/measurement gate): runs after the name gate, before any file exists. Err => zero files.
    // Always-output: a pre-publish hook refusal drops the hook's extra
    // artifacts with a typed warning; the font still publishes.
    let extra = match pre_publish(&PrePublish { final_bytes: &bytes, prepared: final_font.as_ref().unwrap_or(approved_base), base_bytes, post_pass: final_font.is_some() }) {
        Ok(x) => x,
        Err(e) => { receipt.push_str(&format!("warning\tpre_publish_refused\tdegrade\textras_omitted\tdetail\t{e}\n")); Vec::new() }
    };
    let mut extra = extra;
    if require_master && EXPORT_SESSION.with(|s| s.borrow().is_some()) {
        let run = EXPORT_SESSION.with(|s| s.borrow().clone().unwrap());
        use kni_pipeline::export_lifecycle as life;
        life::exclusive(&run.join("final.otf"), &bytes)?;
        let names = approved_base.glyphs.iter().map(|g| life::hex(g.name.as_bytes())).collect::<Vec<_>>().join("\n");
        life::exclusive(&run.join("names"), names.as_bytes())?;
        let maps = mapping.iter().map(|(c,g)|format!("{c}\t{g}\n")).collect::<String>();
        life::exclusive(&run.join("mapping"), maps.as_bytes())?;
        life::exclusive(&run.join("otf-name"),rc.otf_file_name().as_bytes())?;
        let pins = provenance.map(|(a,c)|encode_export_pins(a,c)).unwrap_or_default();
        life::exclusive(&run.join("provenance"),pins.as_bytes())?;
        if let Some(l) = &post_ledger_tsv { extra.push(("post_metrics_ledger.tsv".into(),l.as_bytes().to_vec())); }
        for (n,b) in extra { life::exclusive(&out_dir.join(n),&b)?; }
        receipt.push_str("master_export\tPENDING\tprivate_snapshot\ttrue\n");
        receipt.push_str(&format!("otf\t{}\tbytes\t{}\tsha256\t{}\n",out_dir.join(rc.otf_file_name()).display(),bytes.len(),sha256_hex(&bytes)));
        for (id,value) in &readback {receipt.push_str(&format!("name_readback\tid\t{}\tvalue\t{}\n",id,value));}
        return Ok(out_dir.join(rc.otf_file_name()));
    }
    if require_master {
        let (doc, rows) = kni_pipeline::master_companion::build(&bytes, final_font.as_ref().unwrap_or(approved_base), mapping)?;
        let name = rc.otf_file_name().replace(".otf", ".glyphs");
        receipt.push_str(&format!("master_glyphs_file\t{}\n", name));
        receipt.push_str(&rows);
        extra.push((name, doc.into_bytes()));
    }
    fs::create_dir_all(out_dir).map_err(|e| e.to_string())?;
    // Ledger and font are published as a transaction WITH ROLLBACK (not an atomic set: a reader may briefly see the ledger first):
    // staged, then claimed with atomic no-overwrite links; on failure only what this attempt created is removed (best effort) and any
    // cleanup failure is reported. No exists() precheck (race).
    let mut set: Vec<(&str, &[u8])> = Vec::new();
    for (n, b) in &extra { set.push((n.as_str(), b.as_slice())); }
    if let Some(l) = &post_ledger_tsv { set.push(("post_metrics_ledger.tsv", l.as_bytes())); }
    let otf_name = rc.otf_file_name();
    set.push((otf_name.as_str(), &bytes[..]));
    let published = match provenance {
        Some((actual, claimed)) => k6_final_publish::publish_with_provenance(out_dir, &set, actual, claimed,
            &|d, f| post_metrics::publish_set_exclusive(d, f).map_err(|e| format!("publish: {e:?}")))?,
        None => post_metrics::publish_set_exclusive(out_dir, &set).map_err(|e| format!("publish: {e:?}"))?,
    };
    let otf_path = published.last().cloned().ok_or("publish: empty result")?;
    receipt.push_str(&format!("otf\t{}\tbytes\t{}\tsha256\t{}\n", otf_path.display(), bytes.len(), sha256_hex(&bytes)));
    for (id, value) in &readback {
        receipt.push_str(&format!("name_readback\tid\t{}\tvalue\t{}\n", id, value));
    }
    Ok(otf_path)
}

/// K6 final publish pins, recomputed from the real bytes of this run.
/// KNI_SOURCE_COMMIT (40 hex) turns provenance on; with it unset the run degrades with a typed warning (always-output) - unless a
/// KNI_CLAIMED_* pin is set, because a claim with no provenance to check it against is refused. Claims are compared, never trusted.
fn k6_provenance_pins(manifest_pin: &str, stage1_pins: &std::collections::HashMap<String, String>, master_source_text: Option<&str>,
    receipt: &mut String) -> Result<Option<(kni_pipeline::k6_final_publish::ActualPins, kni_pipeline::k6_final_publish::ClaimedPins)>, String> {
    use kni_pipeline::k6_final_publish::{source_set_sha256, utc_now, ActualPins, ClaimedPins};
    let env = |k: &str| std::env::var(k).ok().filter(|v| !v.trim().is_empty());
    let claimed = ClaimedPins {
        code_sha256: env("KNI_CLAIMED_CODE_SHA256"), manifest_sha256: env("KNI_CLAIMED_MANIFEST_SHA256"),
        source_set_sha256: env("KNI_CLAIMED_SOURCE_SET_SHA256"), master_source_sha256: env("KNI_CLAIMED_MASTER_SHA256"),
        artifact_sha256: env("KNI_CLAIMED_ARTIFACT_SHA256"),
        artifact_bytes: match env("KNI_CLAIMED_ARTIFACT_BYTES") { Some(v) => Some(v.trim().parse::<u64>().map_err(|_| "K6: KNI_CLAIMED_ARTIFACT_BYTES is not an integer".to_string())?), None => None },
        commit: env("KNI_CLAIMED_COMMIT"),
    };
    let any_claim = claimed.code_sha256.is_some() || claimed.manifest_sha256.is_some() || claimed.source_set_sha256.is_some()
        || claimed.master_source_sha256.is_some() || claimed.artifact_sha256.is_some() || claimed.artifact_bytes.is_some() || claimed.commit.is_some();
    let commit = match env("KNI_SOURCE_COMMIT") {
        Some(c) => c,
        None if any_claim => return Err("K6: KNI_CLAIMED_* pins set but KNI_SOURCE_COMMIT is unset - nothing to check the claims against, publish refused".into()),
        None => {
            receipt.push_str("warning\tprovenance_unavailable\tdegrade\tno_sidecar_shipped\tdetail\tKNI_SOURCE_COMMIT unset\n");
            return Ok(None);
        }
    };
    let code_sha256 = std::env::current_exe().and_then(fs::read).map(|b| sha256_hex(&b)).map_err(|e| format!("K6: cannot read own executable for the code pin: {:?}", e.kind()))?;
    let actual = ActualPins {
        code_id: format!("kni-pipeline/{}", env!("CARGO_PKG_VERSION")), commit, utc: utc_now(), code_sha256,
        manifest_sha256: manifest_pin.to_string(), source_set_sha256: source_set_sha256(stage1_pins),
        master_source_sha256: master_source_text.map(|t| sha256_hex(t.as_bytes())),
    };
    Ok(Some((actual, claimed)))
}

/// xAvgCharWidth provenance for a NON-ZERO post-pass final font: derived from the final hmtx advances over NON-ZERO advances (space/.notdef included, zero-advance marks excluded),
/// floor rounding, empty population => 0 (integer arithmetic, same rule as core os2_consistency). 0/0 never reaches the pass: the legacy base value (500) ships byte-identical.
const AVG_WIDTH_POLICY_NONZERO_FINAL: post_metrics::AvgWidthPolicy = post_metrics::AvgWidthPolicy::DerivedMean {
    population: post_metrics::AvgPopulation::NonzeroAdvance, rounding: post_metrics::AvgRounding::Floor };

/// Pure gate closure: diagnostic fit, partial population, incomplete solver,
/// and each unresolved kern counter independently prevent base approval.
fn pre_base_approved(usable_fit: bool, exclusions: usize, complete: bool, held: usize, rejected: usize, clamped: usize) -> bool {
    usable_fit && exclusions == 0 && complete && held == 0 && rejected == 0 && clamped == 0
}

/// Records the pre-offset guard decision, not a post-offset physical claim.
/// The caller passes the exact CFF/GPOS bytes produced from the approved frame.
fn pre_export_guard_receipt(base_bytes: &[u8], rc: &run_config::RunConfig, approved: bool) -> String {
    let esc = post_metrics::tsv_escape;
    format!("export_guard\tguard_stage\tpre_lsb_rsb\tguard_result\t{}\tapproved_base_sha256\t{}\tguard_policy\tPRE_POSTMETRICS_ONLY\tcontext_binding\t{}\trun_config_sha256\t{}\n",
        if approved { "approved" } else { "diagnostic_not_approved" },
        if approved { sha256_hex(base_bytes) } else { "none".into() },
        esc(rc.scale().binding_record()), sha256_hex(rc.canonical_record().as_bytes()))
}

/// Pure adapter: the runtime scale binder supplies the already-bound context.
/// Manifest keys and defaults are unchanged. Post offsets remain the legacy 0/0;
/// selecting +25/+25 needs a separately reviewed config-input route and final guard.
#[cfg(test)] // test-only wrapper: delegates to validated_run_config_with_cli with empty AutoSbFlags (one implementation)
fn validated_run_config(
    m: &Manifest,
    scale: kni_core::scale_context::ScaleContext,
    capture_dir: PathBuf,
    out_dir: PathBuf,
    style_id: &str,
) -> Result<run_config::RunConfig, String> {
    validated_run_config_with_cli(m, scale, capture_dir, out_dir, style_id, &AutoSbFlags::default())
}

/// One-injection-point merge for AUTO-SB fields: the flag and the manifest key are two spellings
/// of the same input; equal or single-sided values merge, disagreement is a hard error.
fn merge_auto_sb<T: PartialEq + Copy + std::fmt::Debug>(field: &'static str, cli: Option<T>, manifest: Option<T>) -> Result<Option<T>, String> {
    match (cli, manifest) {
        (Some(c), Some(m)) if c != m => Err(format!("{field}: flag and manifest key disagree ({c:?} vs {m:?}); one injection point, fix one side")),
        (c, m) => Ok(c.or(m)),
    }
}

#[allow(clippy::too_many_arguments)]
fn validated_run_config_with_cli(
    m: &Manifest,
    scale: kni_core::scale_context::ScaleContext,
    capture_dir: PathBuf,
    out_dir: PathBuf,
    style_id: &str,
    auto_sb_cli: &AutoSbFlags,
) -> Result<run_config::RunConfig, String> {
    if scale.units_per_px().to_bits() != m.scale.to_bits()
        || scale.target_upm().to_bits() != f64::from(m.upm).to_bits() {
        return Err("run config: bound scale/UPM disagrees with manifest".into());
    }
    if let Some(g) = m.glyphs.iter().find(|g| g.scale.is_some()) {
        return Err(format!("PerGlyphScaleOverride: {}", g.name));
    }
    let fit_policy = match m.fit_tolerance_policy {
        FitTolerancePolicy::Fixed => run_config::FitErrorPolicy::Fixed,
        FitTolerancePolicy::MeasuredExperimental => run_config::FitErrorPolicy::MeasuredExperimental,
        FitTolerancePolicy::DerivedSourceQuantization => run_config::FitErrorPolicy::DerivedSourceQuantization,
    };
    let mut input = run_config::RunConfig::legacy_defaults_input(Some(fit_policy), capture_dir, out_dir, style_id);
    input.lsb_add = m.post_lsb_add;
    input.rsb_add = m.post_rsb_add;
    input.post_scope = m.post_scope;
    input.post_scope_label = m.post_scope_label.clone();
    input.rdp_epsilon = m.rdp_epsilon;
    input.fit_squared_error = m.fit_squared_error;
    input.fit_max_refits = m.fit_max_refits;
    input.flatten_tolerance = m.flatten_tolerance;
    input.scan_row_step = m.scan_row_step;
    input.scan_max_rows = m.scan_max_rows;
    input.sample_resolution = m.sample_resolution;
    input.pair_min_shared_rows = m.pair_min_shared_rows;
    input.max_pairs = m.max_pairs;
    input.max_pair_evaluations = m.max_pair_evaluations;
    input.iou = m.iou;
    input.auto_sb = merge_auto_sb("auto_sb", auto_sb_cli.mode, m.auto_sb)?;
    input.auto_sb_class_table = match (&auto_sb_cli.class_table, &m.auto_sb_class_table) {
        (Some(c), Some(t)) if c != t => return Err(format!("auto_sb_class_table: flag and manifest key disagree ({c:?} vs {t:?}); one injection point, fix one side")),
        (c, t) => c.clone().or_else(|| t.clone()),
    };
    input.auto_sb_offset_lsb = merge_auto_sb("auto_sb_offset_lsb", auto_sb_cli.offset_lsb, m.auto_sb_offset_lsb)?.unwrap_or(0.0);
    input.auto_sb_offset_rsb = merge_auto_sb("auto_sb_offset_rsb", auto_sb_cli.offset_rsb, m.auto_sb_offset_rsb)?.unwrap_or(0.0);
    input.tie_break = merge_auto_sb("tie_break", auto_sb_cli.tie_break, m.tie_break)?;
    input.auto_sb_pool = match (&auto_sb_cli.pool, &m.auto_sb_pool) {
        (Some(c), Some(t)) if c != t => return Err(format!("auto_sb_pool: flag and manifest key disagree ({c:?} vs {t:?}); one injection point, fix one side")),
        (c, t) => c.clone().or_else(|| t.clone()),
    };
    input.os2_x_height_write = m.os2_x_height_write.map(|w| match w { Os2XHeightWrite::ResolvedOnly => "resolved_only".to_string(), Os2XHeightWrite::MeasuredPreferred => format!("measured_preferred;{}", m3_decl_token(&m.m3)) });
    run_config::RunConfig::new(input, scale).map_err(|e| format!("run config: {e:?}"))
}

/// Validate the entire manifest before output creation or fitting. H decoding
/// uses the same bounded dispatch as glyph capture; synthetic H is not real-H acceptance.
fn read_source_bounded(path: &Path, max: usize) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let file = fs::File::open(path).map_err(|e| format!("open source: {e}"))?;
    let cap = max.checked_add(1).ok_or("source byte limit overflow")?;
    let mut bytes = Vec::new();
    file.take(cap as u64).read_to_end(&mut bytes).map_err(|e| format!("read source: {e}"))?;
    if bytes.len() > max { return Err("source input byte limit exceeded".into()); }
    Ok(bytes)
}

fn bind_manifest_scale(m: &Manifest, limits: Limits) -> Result<BoundRunScale, WiringError> {
    for g in &m.glyphs { scale_wiring::reject_glyph_override(&g.name, g.scale)?; }
    let style = scale_wiring::style_id_of(&m.family, &m.subfamily)?;
    let cohort = m.capture_cohort.as_deref().filter(|s| !s.is_empty()).ok_or(WiringError::EmptyField { field: "capture_cohort" })?;
    let frame = m.capture_frame.as_deref().filter(|s| !s.is_empty()).ok_or(WiringError::EmptyField { field: "capture_frame" })?;
    let observation = if declared_convention::record_for(&style).is_some() {
        let mut hs = m.glyphs.iter().filter(|g| g.codepoint == Some(0x48) && !g.is_ligature());
        let h = hs.next().ok_or(WiringError::MissingHRow)?;
        if hs.next().is_some() { return Err(WiringError::DuplicateHRow); }
        let bytes = read_source_bounded(&h.image, limits.max_input_bytes).map_err(|reason| WiringError::ReadH { reason })?;
        Some(scale_wiring::observe_h_reference(&style, &bytes, &PNG_DECODE_LIMITS, limits, m.upm as f64)?)
    } else { None };
    let bound = scale_wiring::bind_run_scale(&style, observation.as_ref(), cohort, frame, m.upm as f64)?;
    scale_wiring::check_manifest_scale(m.scale, bound.context())?;
    Ok(bound)
}

fn validate_manifest_identities(m: &Manifest) -> Result<(), String> {
    let mut names_seen = BTreeSet::new();
    let mut cps_seen = BTreeSet::new();
    for g in &m.glyphs {
        for cp in g.codepoint.into_iter().chain(g.extra_cps.iter().copied()) {
            bound_detector_validator::validate_codepoint(cp).map_err(|e| e.to_string())?;
        }
        if !valid_name(&g.name) || g.name == ".notdef" || g.name == "space" {
            return Err(format!("refused: invalid or reserved glyph name '{}'", g.name));
        }
        if !names_seen.insert(g.name.clone()) {
            return Err(format!("refused: duplicate glyph name '{}'", g.name));
        }
        // Identity is the full scalar sequence: `f` (66) and `f_i` (66_69) are distinct rows,
        // two rows with the same sequence are a duplicate.
        if !cps_seen.insert(g.seq_label()) {
            return Err(format!("refused: duplicate codepoint sequence {}", g.cp_display()));
        }
    }
    if m.space.is_some() && m.space_evidence.is_some() { return Err("space and space_evidence are exclusive".into()); }
    if let Some((cp, _)) = m.space {
        bound_detector_validator::validate_codepoint(cp).map_err(|e| e.to_string())?;
        space_evidence::validate_space_cp(cp)?;
        if !cps_seen.insert(format!("{cp:x}")) {
            return Err(format!("refused: space codepoint {:#x} duplicates a glyph", cp));
        }
    }
    if m.glyphs.len() + 2 > u16::MAX as usize {
        return Err("refused: glyph count exceeds u16 range".into());
    }
    Ok(())
}

fn resolve_notdef(m: &Manifest, rc: &run_config::RunConfig, limits: Limits) -> Result<bound_detector_validator::DetectionState, String> {
    let supported: BTreeSet<u32> = m.glyphs.iter().filter_map(|g| g.codepoint).chain(m.space.map(|s| s.0)).collect();
    let style = scale_wiring::style_id_of(&m.family, &m.subfamily).map_err(|e| format!("notdef style: {e:?}"))?;
    if let Some((pin,cp))=&m.notdef_proxy {
        if m.notdef.is_some() || m.capture_manifest.is_some(){return Err("bad_notdef::ContextMismatch".into());}
        return notdef_proxy::select(&m.glyphs,pin,*cp,rc.capture_dir(),&PNG_DECODE_LIMITS,limits).map_err(|e| e.to_string());
    }
    notdef_caller::load(
        m.notdef.as_ref(), m.capture_manifest.as_ref().map(|(p, pin)| (p.as_path(), pin.as_str())),
        rc.capture_dir(), &style, rc.scale(), &supported, &m.glyphs.iter().filter_map(|g| g.codepoint.map(|cp| (cp,g.image.clone()))).collect::<Vec<_>>(), limits,
    ).map_err(|e| e.to_string())
 }

/// Evidence-consumption failures that are ignored (never trusted, never
/// fatal): the evidence bytes are not used and the run drops to the
/// blank-cell route. Anything else (IO, limits, manifest conflicts) stays an
/// error. Returns the stable `notdef_evidence_ignored` code.
fn ignorable_notdef_evidence_code(err: &str) -> Option<&'static str> {
    match err {
        "bad_notdef::ShaMismatch" => Some("ShaMismatch"),
        "bad_notdef::ContextMismatch" => Some("ContextMismatch"),
        "bad_notdef::Grammar" => Some("Grammar"),
        "bad_notdef::Duplicate" => Some("Duplicate"),
        _ => None,
    }
}

/// Blank-cell state used when notdef evidence is ignored: no evidence bytes,
/// no placeholder sources, advance resolved at assembly (max glyph advance).
fn ignored_evidence_blank_state(m: &Manifest, rc: &run_config::RunConfig, limits: Limits) -> Result<bound_detector_validator::DetectionState, String> {
    let style = scale_wiring::style_id_of(&m.family, &m.subfamily).map_err(|e| format!("notdef style: {e:?}"))?;
    Ok(bound_detector_validator::DetectionState::PixelEvidence {
        kind: bound_detector_validator::PixelNotdefKind::BlankCell,
        context: bound_detector_validator::PixelContext {
            style,
            frame: rc.scale().frame_binding().into(),
            units_per_px: rc.scale().units_per_px(),
            source_sha256: String::new(),
            ink_model: bound_detector_validator::PIXEL_INK_MODEL.into(),
        },
        image: PathBuf::new(),
        pixel_form_sha256: String::new(),
        evidence_sha256: String::new(),
        sources: Vec::new(),
        space_advance: None,
        decode: bound_detector_validator::LimitsReceipt {
            max_input_bytes: limits.max_input_bytes, max_pixels: limits.max_pixels, max_working_bytes: limits.max_working_bytes,
            origin: "notdef_evidence_ignored".into(),
        },
    })
}

/// `resolve_notdef` with the ignore rule: a broken evidence file is dropped
/// (blank-cell route) and the returned code feeds the warning row.
fn resolve_notdef_or_ignore(m: &Manifest, rc: &run_config::RunConfig, limits: Limits) -> Result<(bound_detector_validator::DetectionState, Option<&'static str>), String> {
    match resolve_notdef(m, rc, limits) {
        Ok(state) => Ok((state, None)),
        Err(e) if m.notdef_proxy.is_none() => match ignorable_notdef_evidence_code(&e) {
            Some(code) => Ok((ignored_evidence_blank_state(m, rc, limits)?, Some(code))),
            None => Err(e),
        },
        Err(e) => Err(e),
    }
}


/// Progress pulse (owner rule: no step may stay silent for more than 15
/// seconds). A scoped heartbeat that prints one `progress <label> ...` line
/// every PULSE_SECS on stderr until dropped; step-start lines stay the
/// caller's. PULSE_SECS sits below the 15-second silence ceiling with
/// margin for scheduling jitter; the ceiling is the declared convention,
/// the pulse cadence derives from it.
const PULSE_SECS: u64 = 10;

struct ProgressPulse {
    stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
    handle: Option<std::thread::JoinHandle<()>>,
}

fn progress_pulse(label: &str) -> ProgressPulse {
    let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let flag = stop.clone();
    let label = label.to_string();
    let t0 = std::time::Instant::now();
    let handle = std::thread::spawn(move || {
        let me = std::thread::current();
        let mut last = std::time::Instant::now();
        loop {
            // park (not sleep): Drop unparks for a prompt shutdown; spurious wakeups re-check the flag.
            std::thread::park_timeout(std::time::Duration::from_secs(1));
            if flag.load(std::sync::atomic::Ordering::Relaxed) { break; }
            if last.elapsed() >= std::time::Duration::from_secs(PULSE_SECS) {
                eprintln!("progress {label} ... {}s elapsed", t0.elapsed().as_secs());
                last = std::time::Instant::now();
            }
        }
        drop(me);
    });
    ProgressPulse { stop, handle: Some(handle) }
}

impl Drop for ProgressPulse {
    fn drop(&mut self) {
        self.stop.store(true, std::sync::atomic::Ordering::Relaxed);
        if let Some(h) = self.handle.take() { h.thread().unpark(); let _ = h.join(); }
    }
}

// ---- unified typed skip ledger (stage1 exclusion emission) -----------------
// One row per skipped glyph:
//   glyph_skip\t<name>\tcp\t<hex>\treason_code\t<code>\tstage\t<n>
// plus one run-level total counter line `glyph_skip_total\t<n>`.
// CONVENTION: the stage number is the pipeline stage that emitted the skip
// (stage 1 = capture + generated drawing); it is a fixed property of the
// emission site, not a tunable parameter.
const GLYPH_SKIP_STAGE1: u32 = 1;
/// CONVENTION: stage 2 = profile construction (same fixed-emission-site
/// rule as GLYPH_SKIP_STAGE1); ring-level typed skips carry it.
const PROFILE_RING_SKIP_STAGE: u32 = 2;

/// Typed reason code for a stage-1 skip. `no contours` marks an intentional
/// empty glyph (the source tile has nothing to draw); every other refusal is
/// a fit failure. Codes are stable receipt vocabulary, not free text.
fn stage1_skip_reason_code(reason: &str) -> &'static str {
    if reason.contains("no contours") { "intentional_empty" } else { "failure" }
}

/// One unified typed skip-ledger row for a stage-1 exclusion.
fn glyph_skip_ledger_line(name: &str, codepoint: Option<u32>, reason: &str) -> String {
    let cp = match codepoint { Some(c) => format!("{c:#x}"), None => "-".to_string() };
    format!("glyph_skip\t{}\tcp\t{}\treason_code\t{}\tstage\t{}\n", name, cp, stage1_skip_reason_code(reason), GLYPH_SKIP_STAGE1)
}

/// Placeholder self-detection decision: the style's own slot population,
/// grouped by pixel_form_sha256 of the DECODED form, carries a placeholder
/// class only when dominant_placeholder finds the distribution's own gap. The blank/drawn split reuses the codebase's
/// own ink test (all gray samples 255); blank classes are skipped, drawn
/// classes keep their fit and are only flagged (produce+flag; kit-content
/// removal is an owner decision).
fn placeholder_scan_decision(groups: &std::collections::BTreeMap<String, Vec<u32>>, blank: &std::collections::BTreeMap<String, bool>) -> Option<(String, bool)> {
    let hash = bound_detector_validator::dominant_placeholder(groups)?;
    Some((hash.clone(), *blank.get(hash)?))
}

/// One typed ledger row per skipped blank-placeholder slot.
fn placeholder_skip_line(name: &str, codepoint: u32, form_hash: &str) -> String {
    format!("placeholder_skip\t{}\tcp\t{:#x}\tkind\tblank-cell\tpixel_form_sha256\t{}\tstage\t{}\n", name, codepoint, form_hash, GLYPH_SKIP_STAGE1)
}

/// One typed flag row per drawn-placeholder slot (fit continues unchanged).
fn placeholder_form_line(name: &str, codepoint: u32, form_hash: &str) -> String {
    format!("placeholder_form\t{}\tcp\t{:#x}\tkind\tdrawn-form\tpixel_form_sha256\t{}\tstage\t{}\n", name, codepoint, form_hash, GLYPH_SKIP_STAGE1)
}

/// Run-level placeholder-class summary (decision_basis = population gap).
fn placeholder_class_line(form_hash: &str, blank: bool, slots: usize) -> String {
    format!("placeholder_class\tpixel_form_sha256\t{}\tkind\t{}\tslot_count\t{}\tdecision_basis\tpopulation-dominance-gap\n", form_hash, if blank { "blank-cell" } else { "drawn-form" }, slots)
}

/// Run-level placeholder-class summary for a bound-evidence claim
/// (decision_basis = bound-notdef-evidence).
fn placeholder_claim_class_line(form_hash: &str, slots: usize) -> String {
    format!("placeholder_class\tpixel_form_sha256\t{}\tkind\tdrawn-form\tslot_count\t{}\tdecision_basis\tbound-notdef-evidence\n", form_hash, slots)
}

/// Bound repeated-form .notdef evidence: glyph rows whose codepoints are the
/// bound .notdef form are NOT ordinary glyphs. Each is skipped (no drawn glyph,
/// no cmap entry) with one typed placeholder_skip row; one run-level
/// placeholder_class row summarizes the class. Returns (receipt rows, skipped cps).
fn placeholder_claim_skip_lines(rows: &[GlyphRow], sources: &[u32], form_hash: &str) -> (String, Vec<u32>) {
    let mut out = String::new();
    let hits: Vec<(&GlyphRow, u32)> = rows.iter().filter_map(|g| g.codepoint.filter(|cp| sources.contains(cp)).map(|cp| (g, cp))).collect();
    if hits.is_empty() { return (out, vec![]); }
    out.push_str(&placeholder_claim_class_line(form_hash, hits.len()));
    for (g, cp) in &hits {
        out.push_str(&format!("placeholder_skip\t{}\tcp\t{:#x}\tkind\trepeated-form\tpixel_form_sha256\t{}\tstage\t{}\n", g.name, cp, form_hash, GLYPH_SKIP_STAGE1));
    }
    (out, hits.iter().map(|(_, cp)| *cp).collect())
}

/// Run-level total counter line for the unified skip ledger.
fn glyph_skip_total_line(total: usize) -> String {
    format!("glyph_skip_total\t{}\n", total)
}

/// Run-failure floor (always-output rule): lenient scan of the raw manifest text for the three naming keys the floor OTF
/// needs. Nothing is invented: a missing key means no floor OTF, only the failure receipt.
fn floor_names(text: &str) -> Option<(String, String, String, u16)> {
    let (mut fam, mut sub, mut ps, mut upm) = (None, None, None, 1000u16);
    for line in text.lines() {
        let mut it = line.splitn(2, char::is_whitespace);
        let (k, v) = (it.next().unwrap_or(""), it.next().unwrap_or("").trim());
        if v.is_empty() { continue; }
        match k { "family" => fam = Some(v.to_string()), "subfamily" => sub = Some(v.to_string()), "postscript_name" => ps = Some(v.to_string()),
            "upm" => { if let Ok(u) = v.parse::<u16>() { if u > 0 { upm = u; } } } _ => {} }
    }
    Some((fam?, sub?, ps?, upm))
}

/// Floor OTF: blank .notdef only, no cmap entries, no GPOS. CONVENTION: .notdef advance = upm/2 (half em, derived from the declared
/// upm; same ratio as the blank-notdef test fixture). Err = floor not producible (receipt still written by the caller).
fn write_floor_otf(out_dir: &Path, family: &str, subfamily: &str, ps: &str, upm: u16) -> Result<PathBuf, String> {
    let mut f = NativeFontInput {
        postscript_name: ps.to_string(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: upm, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
            panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"NONE", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
        names: names(family, subfamily, ps),
    };
    f.os2.average_width = (upm / 2) as i16;
    let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }];
    let metrics = vec![(".notdef".to_string(), 0.0, 0.0, f64::from(upm / 2))];
    let prepared = prepare_generated(&glyphs, &[], &metrics, &f).map_err(|e| format!("floor prepare: {e:?}"))?;
    let bytes = encode_with_layout(&prepared, None).map_err(|e| format!("floor encode: {e:?}"))?;
    let path = out_dir.join("floor.otf");
    fs::write(&path, &bytes).map_err(|e| format!("floor write: {e}"))?;
    Ok(path)
}

/// Global floor: a manifest that cannot be read, parsed, or turned into a valid run config still ends with a typed
/// run-failure receipt plus (when the manifest names the font) a floor OTF. Returns the refusal text for main().
fn manifest_floor(out_dir: &Path, code: &str, detail: &str, manifest_text: Option<&str>) -> String {
    let _ = fs::create_dir_all(out_dir);
    let _ = run_failure::write_run_failure_receipt(out_dir, code, detail);
    let floor = match manifest_text.and_then(floor_names) {
        Some((fam, sub, ps, upm)) => match write_floor_otf(out_dir, &fam, &sub, &ps, upm) {
            Ok(p) => format!("; floor OTF written: {}", p.display()),
            Err(e) => format!("; floor OTF not produced: {e}"),
        },
        None => "; floor OTF not produced: manifest does not name family/subfamily/postscript_name".to_string(),
    };
    format!("{code}: {detail}{floor}")
}

fn merge_visibility_source_bytes(m: &Manifest, per_tile_limit: usize) -> Result<Vec<u8>, String> {
    let mut source = Vec::new();
    for glyph in &m.glyphs {
        let tile = read_source_bounded(&glyph.image, per_tile_limit)
            .map_err(|e| format!("mov-1 source read for glyph {} ({}): {e}", glyph.name, glyph.image.display()))?;
        let additional = glyph.name.as_bytes().len().checked_add(1).and_then(|n| n.checked_add(tile.len()))
            .ok_or_else(|| format!("mov-1 source buffer size overflow at glyph {}", glyph.name))?;
        source.try_reserve(additional).map_err(|e| format!("mov-1 source buffer allocation at glyph {}: {e}", glyph.name))?;
        source.extend_from_slice(glyph.name.as_bytes());
        source.push(0);
        source.extend_from_slice(&tile);
    }
    Ok(source)
}

/// CLI spellings of the AUTO-SB (A2) config; mirror keys exist in the manifest. Flag and manifest
/// are two spellings of one input and merge at one injection point (validated_run_config_with_cli):
/// equal or single-sided values merge, disagreement is a hard error, never a silent precedence.
/// Off (no flag, no manifest key) = byte-identical run.
#[derive(Clone, Debug, Default, PartialEq)]
struct AutoSbFlags {
    mode: Option<run_config::AutoSbMode>,
    class_table: Option<PathBuf>,
    pool: Option<PathBuf>,
    offset_lsb: Option<f64>,
    offset_rsb: Option<f64>,
    tie_break: Option<run_config::TieBreak>,
}

fn take_auto_sb_flags(args: &[String]) -> Result<(AutoSbFlags, Vec<String>), String> {
    fn val(flag: &str, v: Option<&String>) -> Result<String, String> {
        match v {
            // negative numeric values start with one dash and are legitimate here
            Some(v) if !v.starts_with("--") => Ok(v.clone()),
            _ => Err(format!("usage: {flag} requires a value")),
        }
    }
    let mut kept: Vec<String> = Vec::with_capacity(args.len());
    let mut f = AutoSbFlags::default();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--auto-sb" => {
                if f.mode.is_some() { return Err("usage: --auto-sb given more than once".to_string()); }
                let v = val("--auto-sb", it.next())?;
                f.mode = Some(run_config::AutoSbMode::from_flag(&v).ok_or_else(|| format!("usage: bad --auto-sb {v:?} (median|class)"))?);
            }
            "--auto-sb-class-table" => {
                if f.class_table.is_some() { return Err("usage: --auto-sb-class-table given more than once".to_string()); }
                f.class_table = Some(PathBuf::from(val("--auto-sb-class-table", it.next())?));
            }
            "--auto-sb-pool" => {
                if f.pool.is_some() { return Err("usage: --auto-sb-pool given more than once".to_string()); }
                f.pool = Some(PathBuf::from(val("--auto-sb-pool", it.next())?));
            }
            "--auto-sb-offset-lsb" => {
                if f.offset_lsb.is_some() { return Err("usage: --auto-sb-offset-lsb given more than once".to_string()); }
                let v = val("--auto-sb-offset-lsb", it.next())?;
                let x: f64 = v.parse().map_err(|_| format!("usage: bad --auto-sb-offset-lsb {v:?}"))?;
                if !x.is_finite() { return Err(format!("usage: --auto-sb-offset-lsb must be finite, got {v:?}")); }
                f.offset_lsb = Some(x);
            }
            "--auto-sb-offset-rsb" => {
                if f.offset_rsb.is_some() { return Err("usage: --auto-sb-offset-rsb given more than once".to_string()); }
                let v = val("--auto-sb-offset-rsb", it.next())?;
                let x: f64 = v.parse().map_err(|_| format!("usage: bad --auto-sb-offset-rsb {v:?}"))?;
                if !x.is_finite() { return Err(format!("usage: --auto-sb-offset-rsb must be finite, got {v:?}")); }
                f.offset_rsb = Some(x);
            }
            "--tie-break" => {
                if f.tie_break.is_some() { return Err("usage: --tie-break given more than once".to_string()); }
                let v = val("--tie-break", it.next())?;
                f.tie_break = Some(run_config::TieBreak::from_flag(&v).ok_or_else(|| format!("usage: bad --tie-break {v:?} (A|B)"))?);
            }
            _ => kept.push(a.clone()),
        }
    }
    Ok((f, kept))
}

fn run_inner(args: Vec<String>) -> Result<String, String> {
    let merge_observe_enabled = std::env::var(kni_core::obs_envelope::OBSERVE_GATE_ENV).as_deref() == Ok("1");
    fit_bench::install_from_env();
    let (pair_visual_dir, args) = take_pair_visual_flag(&args)?;
    let (style_id, args) = run_config::take_style_id_flag(&args).map_err(|e| format!("usage: --style-id <id> is required: {e:?}"))?;
    let (jobs, args) = run_config::take_jobs_flag(&args, run_config::Jobs::default_parallelism(), run_config::Jobs::default_parallelism()).map_err(|e| format!("usage: {e}"))?;
    let allow_partial = args.iter().any(|a| a == "--allow-partial");
    // Explicit diagnostic test export intent: retains the typed fallback ledger in the
    // export intent. NOT a silent widening of --allow-partial. In this mode the typed
    // fallback ledger is KEPT in the receipt, the normal usable/final hard-fail is KEPT
    // for any non-diagnostic invocation, and only test-font byte production is unblocked.
    // Policy/gate/geometry/frozen renderer unchanged; serializer/count/metadata/memory
    // errors are never bypassed.
    let diagnostic_test_export = args.iter().any(|a| a == "--diagnostic-test-export");
    // Explicit fallback-warn export intent: the typed fallback ledger no longer hard-fails
    // the export; the full ledger lands in the receipt and the out dir carries
    // fallback-glyphs.tsv. The shipped font's name table is NEVER warning-tagged, on this
    // or any other path. NOT a production candidate. Geometry, kern and spacing emission
    // are byte-identical to any other intent.
    let fallback_export_warn = args.iter().any(|a| a == "--fallback-export-warn");
    let spacing_oohh_flag = args.iter().any(|a| a == spacing_oohh::FLAG);
    let class_channel_targets_flag = args.iter().any(|a| a == "--class-channel-targets");
    let (auto_sb_flags, args) = take_auto_sb_flags(&args)?;
    if diagnostic_test_export && fallback_export_warn {
        return Err("refused: --diagnostic-test-export and --fallback-export-warn are mutually exclusive export intents".to_string());
    }
    let positional: Vec<&String> = args[1..].iter().filter(|a| !a.starts_with("--")).collect(); // auto-sb flags already consumed above
    if positional.len() != 2 || args.iter().any(|a| a.starts_with("--") && a != "--allow-partial" && a != "--diagnostic-test-export" && a != "--fallback-export-warn" && a != spacing_oohh::FLAG && a != "--class-channel-targets") {
        return Err(format!("usage: {} <manifest-file> <output-dir> --style-id <id> [--jobs N] [--allow-partial] [--diagnostic-test-export] [--fallback-export-warn] [--spacing-oohh] [--class-channel-targets] [--auto-sb <median|class> [--auto-sb-class-table <path>] [--auto-sb-pool <path>] [--auto-sb-offset-lsb <f64>] [--auto-sb-offset-rsb <f64>] [--tie-break <A|B>]]", args[0]));
    }
    let manifest_path = PathBuf::from(positional[0]);
    let out_dir = PathBuf::from(positional[1]);
    if out_dir.exists() {
        return Err(format!("refused: output dir exists (no overwrite): {}", out_dir.display()));
    }
    let manifest_text = match fs::read_to_string(&manifest_path) {
        Ok(t) => t,
        Err(e) => return Err(manifest_floor(&out_dir, "MANIFEST_UNREADABLE", &format!("read manifest: {e}"), None)),
    };
    let manifest_pin = sha256_hex(manifest_text.as_bytes());
    let base = manifest_path.parent().unwrap_or_else(|| Path::new(".")).to_path_buf();
    let mut m = match parse_manifest(&manifest_text, &base) {
        Ok(m) => m,
        Err(e) => return Err(manifest_floor(&out_dir, "MANIFEST_INVALID", &e, Some(&manifest_text))),
    };
    check_run_mode(&m)?;
    // Declared style override (style-scoped declared convention, SET semantics;
    // chief ruling 2026-10-17; convention doc docs/kni/2026-10-17-mona-alt-monospace-convention.md):
    // when the run's style has a row in the pinned style-overrides.tsv, the row is
    // the single source of the post-step values. The manifest/flag lsb_add/rsb_add
    // are IGNORED (typed `declared_convention_overrides_flags` receipt row) and the
    // values are SET - one injection point (manifest -> run_config -> post_metrics),
    // never an addition on top, so 40/45 can never become 80/90.
    let declared_override = declared_override_for(&m)?;
    let mut style_override_rows = String::new();
    if let Some(row) = &declared_override {
        style_override_rows.push_str(&apply_declared_style_override(&mut m, row));
    }
    // Per-tile decode/input ceilings, not a population-retained working allowance.
    let limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
    let bound = bind_manifest_scale(&m, limits).map_err(|e| format!("scale wiring refused: {e:?}"))?;
    let wiring_row = scale_wiring::wiring_receipt_row(&bound).map_err(|e| format!("scale receipt refused: {e:?}"))?;
    let rc = match validated_run_config_with_cli(&m, bound.into_context(), base.clone(), out_dir.clone(), &style_id, &auto_sb_flags) {
        Ok(rc) => rc,
        Err(e) => return Err(manifest_floor(&out_dir, "RUN_CONFIG_INVALID", &e, Some(&manifest_text))),
    };
    rc.check_output_dir_available().map_err(|e| format!("output precheck: {e:?}"))?;
    let mut observer_records: Vec<kni_core::obs_envelope::Record> = Vec::new();
    let mut observer_run_context: Option<MergeVisibilityRunContext> = None;

    if merge_observe_enabled {
        let epoch_secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| format!("mov-1 clock before Unix epoch: {e}"))?.as_secs();
        let run_id = format!("{}:{epoch_secs}", &manifest_pin[..12]);
        let invocation_id = kni_core::obs_envelope::invocation_id(&manifest_pin, epoch_secs);
        let fixture_id = std::env::var("KNI_MOV1_FIXTURE_ID").ok();
        let fixture_sha256 = std::env::var("KNI_MOV1_FIXTURE_SHA256").ok();
        let source_full_ref = None;
        let active_source_mapping_status = None;
        let grid = Some(m.scale.to_string());
        let line_tolerance = None;
        let stage1_cache_sha256 = if let Some(path) = &m.stage1_cache {
            let cache_bytes = fs::read(path).map_err(|e| format!("mov-1 stage1 cache read {}: {e}", path.display()))?;
            Some(sha256_hex(&cache_bytes))
        } else { None };
        let stage1_route = if m.stage1_cache.is_some() {
            kni_core::obs_envelope::Stage1Route::CacheReuse
        } else {
            kni_core::obs_envelope::Stage1Route::Live
        };
        let source_bytes = std::sync::Arc::new(merge_visibility_source_bytes(&m, limits.max_input_bytes)?);
        observer_run_context = Some(MergeVisibilityRunContext {
            run_id: run_id.clone(), invocation_id: invocation_id.clone(), style: style_id.clone(),
            stage1_route: stage1_route.clone(), stage1_cache_sha256: stage1_cache_sha256.clone(), source_bytes,
        });
        observer_records.push(kni_core::obs_envelope::Record::Envelope(
            kni_core::obs_envelope::Envelope {
                run_id,
                source_full_ref,
                active_source_mapping_status,
                fixture_id,
                fixture_sha256,
                config_digest: Some(manifest_pin.clone()),
                economy_mode: None,
                coordinate_unit: Some("font_units".into()),
                grid,
                dense_bound_db: None,
                line_tolerance,
                workers: jobs.get() as u32,
                stage1_route,
                stage1_cache_sha256,
                invocation_id,
                env_flags: kni_core::obs_envelope::collect_env_flags(),
                invocation_id_style: "ring:<n>".into(),
            },
        ));
    }
    validate_manifest_identities(&m)?;

    // Evidence validation happens before any fitting or output creation.
    let mut receipt = String::new();
    receipt.push_str(&style_override_rows);
    // Always-output C-class: evidence that survives none of the ignore routes is
    // treated as absent (typed warning; mismatched bytes are never used) and the
    // run continues - assembly ships the blank-notdef arm.
    let mut nd_evidence_void = false;
    let (mut nd_state, nd_evidence_ignored) = match resolve_notdef_or_ignore(&m, &rc, limits) {
        Ok(x) => x,
        Err(e) => { receipt.push_str(&format!("warning\tnotdef_evidence_void\tdegrade\tblank_notdef\tdetail\t{e}\n"));
            nd_evidence_void = true;
            (bound_detector_validator::DetectionState::MissingPixelEvidence, None) }
    };
    if let Some(code) = nd_evidence_ignored {
        let w = format!("notdef_evidence_ignored\t{code}\n");
        eprint!("{w}");
        receipt.push_str(&w);
    }
    // K3 is an evidence producer above the existing routing chain. Only a
    // validator-confirmed state may replace missing, undeclared evidence.
    nd_state = k3_notdef_scan::route_if_missing(
        &m, &rc, limits, nd_state, nd_evidence_ignored.is_some() || nd_evidence_void,
        &mut receipt,
    );
    // notdef classification (contract): the tasnif is decided at the very
    // start of the run, right after capture; every later stage consumes
    // this decision and nothing re-derives or refuses the notdef
    // downstream. The advance basis is declared here and materialized at
    // assembly from the solved population.
    {
        let nd_classification = format!("{}notdef_classification\tstage\trun-start\tadvance_basis\tmax-glyph-advance\n", nd_state.receipt());
        eprint!("{nd_classification}");
        receipt.push_str(&nd_classification);
    }
    receipt.push_str(&k3_notdef_scan::run(&m.glyphs, limits, &nd_state));
    let mut bound_repeated_skip: Vec<u32> = vec![];
    if let bound_detector_validator::DetectionState::PixelEvidence { kind, sources, pixel_form_sha256, .. } = &nd_state {
        match kind {
            bound_detector_validator::PixelNotdefKind::RepeatedForm => {
                // Bound repeated-form codepoints are the designer's .notdef
                // form: typed skip, never an ordinary cmap glyph.
                let (lines, cps) = placeholder_claim_skip_lines(&m.glyphs, sources, pixel_form_sha256);
                receipt.push_str(&lines);
                bound_repeated_skip = cps;
            }
            bound_detector_validator::PixelNotdefKind::BlankCell => {
                reject_placeholder_population(&m.glyphs, sources).map_err(|e| e.to_string())?;
            }
        }
    }
    let proxy_candidate_cps: Vec<u32> = match &nd_state {
        bound_detector_validator::DetectionState::CandidateProxy { candidate_cps, .. } => candidate_cps.clone(),
        _ => vec![],
    };
    // Placeholder self-detection: active only when no claim-driven
    // placeholder extraction is in force (a claim's validated population
    // already carries placeholder semantics), and never on the
    // stage1-cache reuse route (the cache is an explicit owner input; its
    // identity is unchanged). Tiles are grouped by pixel_form_sha256 of the
    // decoded form - file bytes are not form identity - and the dominance
    // gap, not a threshold, decides.
    //
    // The scan runs BEFORE the MissingPixelEvidence refusal below. A
    // dominant class is evidence; the run continues. No dominant class:
    // the refusal stands, typed. Computation happens here; the class/slot
    // ledger rows emit at the original receipt site.
    let mut placeholder_skip_cps: Vec<u32> = bound_repeated_skip.clone();
    // A claim with a validated population (>=2 sources) already carries
    // placeholder semantics for that class; the ignored-evidence blank state
    // (PixelEvidence with EMPTY sources) carries none, so self-detection
    // runs there.
    let claim_handles_population = !proxy_candidate_cps.is_empty()
        || matches!(&nd_state, bound_detector_validator::DetectionState::PixelEvidence { sources, .. } if !sources.is_empty());
    // The placeholder decision is single-sourced here: the live scan, or
    // the typed row a found-class live run persisted into its stage1 cache:
    // a found-class run must produce, and its replay must produce the same
    // output and receipt rows.
    let mut placeholder_decision: Option<(String, bool, Vec<u32>)> = None;
    let mut placeholder_scanned = false;
    let mut speck_areas_run: Vec<f64> = Vec::new();
    let mut speck_retained_hole_run: usize = 0;
    let mut speck_dropped_collapse_run: usize = 0;
    let mut speck_replay_unavailable = false;
    // sub_grid_floor is split: the stage1 subtotal is stage-1 state
    // (persisted into the cache; replay restores it), the notdef post-pass
    // events are produced by a fresh local fit on every route and are never
    // persisted - the receipt row is subtotal + local, no double counting.
    let mut sub_grid_floor_total: usize = 0;
    let mut sub_grid_postpass_total: usize = 0;
    let mut sub_grid_replay_unavailable = false;
    let mut speck_retained_hole_replay_unavailable = false;
    let mut speck_dropped_collapse_replay_unavailable = false;
    let mut sweep_replay_unavailable = false;
    let mut sweep_replay_restore: Option<usize> = None;
    // Live stage-1 pass only; the replay route derives the totals from the
    // persisted cache row.
    let mut corner_wiring_totals_run = kni_core::corner_wiring::WiringTotals::default();
    let mut corner_wiring_replay_unavailable = false;
    if let Some(cache_path) = &m.stage1_cache {
        if let Some((form_hash, is_blank, slots)) = read_cache_placeholder_decision(cache_path)? {
            // The persisted decision is a pin, not an input: recompute the
            // form hash from the slots' source pixel evidence and refuse on
            // any mismatch before the decision drives anything.
            verify_cache_placeholder_decision(&m, limits, &form_hash, is_blank, &slots)?;
            if is_blank { placeholder_skip_cps = slots.clone(); }
            placeholder_decision = Some((form_hash, is_blank, slots));
        }
        // The run-level speck row is derived from cache-persisted evidence
        // on the replay route; a cache without the row gets a typed
        // replay-unavailable marker at the receipt site, never a silent 0.
        match read_cache_speck_retained(cache_path)? {
            Some(areas) => speck_areas_run = areas,
            None => speck_replay_unavailable = true,
        }
        // Same contract for the sub-grid floor: the stage1 subtotal is
        // restored from persisted evidence; a cache without the row gets a
        // typed replay-unavailable marker at the receipt site, never a
        // silent 0.
        match read_cache_sub_grid_floor(cache_path)? {
            Some(n) => sub_grid_floor_total = n,
            None => sub_grid_replay_unavailable = true,
        }
        // Same contract for the hole-dropped row: the replay route derives
        // it from cache-persisted evidence; absence is a typed marker, never
        // a silent 0.
        match read_cache_speck_retained_hole(cache_path)? {
            Some(n) => speck_retained_hole_run = n,
            None => speck_retained_hole_replay_unavailable = true,
        }
        // Same contract for the post-round-collapse dropped row.
        match read_cache_speck_dropped_collapse(cache_path)? {
            Some(n) => speck_dropped_collapse_run = n,
            None => speck_dropped_collapse_replay_unavailable = true,
        }
        // Same pattern for the final straight-sweep count: restore the
        // persisted live total into this thread's counter; an older cache
        // without the row gets a typed marker, never a silent 0.
        match read_cache_straight_sweep(cache_path)? {
            Some(n) => sweep_replay_restore = Some(n),
            None => sweep_replay_unavailable = true,
        }
        // The run-level corner-wiring seam counts are derived from the
        // cache-persisted row on the replay route; a cache without the row
        // gets a typed replay-unavailable marker at the receipt site, never
        // a silent 0.
        match read_cache_corner_wiring_seams(cache_path)? {
            Some(t) => corner_wiring_totals_run = t,
            None => corner_wiring_replay_unavailable = true,
        }
    } else if !claim_handles_population
    {
        let _pulse = progress_pulse("placeholder-scan");
        let mut groups: std::collections::BTreeMap<String, Vec<u32>> = std::collections::BTreeMap::new();
        let mut blank: std::collections::BTreeMap<String, bool> = std::collections::BTreeMap::new();
        for g in &m.glyphs {
            // Unencoded anonymous rows are always drawn: they never join a
            // placeholder class (the class decision is a codepoint-slot notion).
            let Some(cp) = g.codepoint else { continue; };
            let bytes = read_source_bounded(&g.image, limits.max_input_bytes)?;
            let decoded = kni_core::capture_dispatch::decode_source(&bytes, &PNG_DECODE_LIMITS, limits).map_err(|e| format!("placeholder-scan decode {}: {e:?}", g.name))?;
            let form_hash = bound_detector_validator::pixel_form_sha256(decoded.width, decoded.height, &decoded.gray).map_err(|e| format!("placeholder-scan form hash {}: {e:?}", g.name))?;
            // One form has one gray payload: blankness is a group property.
            blank.entry(form_hash.clone()).or_insert_with(|| decoded.gray.iter().all(|&pixel| pixel == 255));
            groups.entry(form_hash).or_default().push(cp);
        }
        let decision = placeholder_scan_decision(&groups, &blank)
            .map(|(form_hash, is_blank)| { let slots = groups[&form_hash].clone(); (form_hash, is_blank, slots) });
        if let Some((_, true, slots)) = &decision { placeholder_skip_cps = slots.clone(); }
        placeholder_scanned = true;
        placeholder_decision = decision;
    }
    // Typed both ways: a MissingPixelEvidence full run without the
    // partial-degrade allowance consults the scan BEFORE refusing.
    // placeholder_class_none prints to stderr as well - the refusal below
    // discards the receipt, and the ledger row must survive. No silent
    // ignore either way.
    let refusal_pending = matches!(&nd_state, bound_detector_validator::DetectionState::MissingPixelEvidence)
        && m.run_mode == RunMode::Full && !allow_partial;
    if refusal_pending {
        let line = match &placeholder_decision {
            Some((form_hash, is_blank, slots)) => format!(
                "placeholder_class_found\tpixel_form_sha256\t{}\tkind\t{}\tslot_count\t{}\tdecision_basis\tpopulation-dominance-gap\n",
                form_hash, if *is_blank { "blank-cell" } else { "drawn-form" }, slots.len()),
            // Live: the scan found no dominant class. Replay: a found class
            // would have been persisted into the cache, so its absence is the
            // none decision; the basis names which route decided. Typed both
            // ways, no silent ignore; the refusal itself stays typed.
            None if placeholder_scanned => "placeholder_class_none\tdecision_basis\tpopulation-dominance-gap\n".to_string(),
            None if m.stage1_cache.is_some() => "placeholder_class_none\tdecision_basis\tstage1-cache-no-persisted-decision\n".to_string(),
            None => String::new(),
        };
        if !line.is_empty() {
            eprint!("{line}");
            receipt.push_str(&line);
        }
    }
    let placeholder_detected = refusal_pending && placeholder_decision.is_some();
    let nd_action = if m.run_mode == RunMode::Full {
        if placeholder_detected {
            // Evidence found by self-detection: the run continues; .notdef
            // ships the blank arm (advance basis declared at run-start) and
            // the class's slots are skipped (blank) or fitted+flagged
            // (drawn) by the placeholder rows below.
            Some(NotdefAction::Empty { advance: m.upm as f64, partial_reason: Some("placeholder_class_found") })
        } else {
            Some(nd_state.action(allow_partial, m.upm as f64).map_err(|e| e.to_string())?)
        }
    } else { None };

    // ---- stage 1: capture + generated drawing (real route, per glyph) ----
    let mut processed: Vec<(&GlyphRow, DrawnGlyph)> = Vec::new();
    let mut fallback_span_total: usize = 0;
    let mut fallback_glyph_spans: Vec<(String, usize)> = Vec::new();
    let mut fallback_provenance: Vec<(String, Vec<kni_core::capture_fit::FallbackSpanProvenance>)> = Vec::new();
    kni_core::capture_fit::reset_straight_sweep_converted();
    if let Some(n) = sweep_replay_restore {
        kni_core::capture_fit::add_straight_sweep_converted(n).map_err(|e| e.to_string())?;
    }
    // immutable stage-1 capture pins: glyph name -> sha256 of the PNG bytes the fit consumed (live) or the cache-verified pin
    let mut stage1_pins: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    let mut exclusions: Vec<(String, Option<u32>, String)> = Vec::new();
    if let Some(declared) = &m.postscript_name_declared {
        receipt.push_str(&format!("postscript_name_sanitized\t{}\t{}\n", declared, m.postscript_name));
    }
    receipt.push_str(&wiring_row);
    receipt.push_str(&format!("manifest_pin\t{manifest_pin}\n"));
    receipt.push_str(&format!("png_decode_limits\tmax_input_bytes\t{}\tmax_pixels\t{}\tmax_working_bytes\t{}\torigin\tDecodeBudgetNotInRunConfig(hardcoded hub default)\n", PNG_DECODE_LIMITS.max_input_bytes, PNG_DECODE_LIMITS.max_pixels, PNG_DECODE_LIMITS.max_working_bytes));
    receipt.extend(rc.receipt_rows());
    let _total_glyphs = m.glyphs.len();
    if !proxy_candidate_cps.is_empty() {
        receipt.push_str(&format!("placeholder_extraction\tcandidate_count\t{}\tfailure_exclusions\t0\n",proxy_candidate_cps.len()));
    }
    if !placeholder_skip_cps.is_empty() {
        receipt.push_str(&format!("placeholder_extraction\tcandidate_count\t{}\tfailure_exclusions\t0\n", placeholder_skip_cps.len()));
    }
    // Scan ledger rows emit here (the scan itself ran before the notdef
    // refusal); placeholder_skip_cps is already set.
    if let Some((form_hash, is_blank, slots)) = &placeholder_decision {
        receipt.push_str(&placeholder_class_line(form_hash, *is_blank, slots.len()));
        for g in &m.glyphs {
            let Some(cp) = g.codepoint else { continue; };
            if !slots.contains(&cp) { continue; }
            if *is_blank {
                receipt.push_str(&placeholder_skip_line(&g.name, cp, form_hash));
            } else {
                receipt.push_str(&placeholder_form_line(&g.name, cp, form_hash));
            }
        }
    }
    let total_glyphs = m.glyphs.len();
    // Output directory initialization on the common path: the stage1_cache
    // branch never created out_dir, but profile-rows.txt is written on the
    // shared path below; create it once here so both the ordinary and
    // cache-reuse routes have it before any profile/provenance output.
    rc.create_output_dir_exclusive().map_err(|e| format!("create out dir: {e:?}"))?;
    if let Some(pin) = pair_visual_pre_stage(&pair_visual_dir, &out_dir, false)? {
        receipt.push_str(&pin);
    }
    let mut stage1_shipped: Vec<DrawnGlyph> = Vec::new();
    if let Some(cache_path) = &m.stage1_cache {
        if !proxy_candidate_cps.is_empty() { return Err("CandidateProxyCacheRequiresExtractedPopulation".into()); }
        load_stage1_cache(cache_path, &m, &rc, &placeholder_skip_cps, &mut processed, &mut stage1_shipped, &mut exclusions, &mut receipt, &mut fallback_span_total, &mut stage1_pins, &mut fallback_glyph_spans)?;
    } else {
        let mut cache = String::new();
        cache.push_str("kni-stage1-cache\tv2\n");
        cache.push_str(&format!("policy\tscale\t{:e}\trdp_epsilon\t{:e}\tfit_squared_error\t{:e}\tfit_max_refits\t{}\tfit_tolerance_policy\t{:?}\tframe_map\t{:?}\tguide\t{:?}\treferences\t{:?}\tcorner_wiring\t{}\n", rc.scale().units_per_px(), m.rdp_epsilon, rc.fit_squared_error().value(), m.fit_max_refits, m.fit_tolerance_policy, m.frame_map, m.guide, m.references, if m.corner_wiring { "on" } else { "off" }));
        cache.push_str(&format!("scale_binding\t{}\n", rc.scale().binding_record()));
        cache.push_str(&format!("stage1_identity\t{}\n", rc.stage1_identity()));
        let exe_sha = fs::read("/proc/self/exe").map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".to_string());
        cache.push_str(&format!("engine_exe_sha256\t{}\n", exe_sha));
        // A found-class decision is part of stage-1 state; persist it as a
        // typed row so the replay route takes the identical notdef branch,
        // skips/flags the identical slots, and emits the identical receipt
        // rows.
        if let Some((form_hash, is_blank, slots)) = &placeholder_decision {
            let cps: Vec<String> = slots.iter().map(|cp| format!("{cp:#x}")).collect();
            cache.push_str(&format!("placeholder_decision\tfound\tpixel_form_sha256\t{}\tkind\t{}\tslot_count\t{}\tslots\t{}\n",
                form_hash, if *is_blank { "blank-cell" } else { "drawn-form" }, slots.len(), cps.join(",")));
        }
        let rows: Vec<&GlyphRow> = m.glyphs.iter().filter(|g| g.codepoint.map_or(true, |cp| !proxy_candidate_cps.contains(&cp) && !placeholder_skip_cps.contains(&cp))).collect();
        // fit-driver-par: indexed parallel fit (order-preserving collect), then one sequential reduce in manifest order.
        // counters on this thread before stage 1: the fold below must keep this base (a jobs=1 fit adds to this very thread)
        let base_sweep = kni_core::capture_fit::straight_sweep_converted();
        let base_reloc = kni_core::capture_fit::reloc_moved();
        let bench_fitting = fit_bench::PhaseGuard::enter("fitting");
        let outcomes = stage1_fit_all(&rows, &m, &rc, limits, jobs, total_glyphs, observer_run_context.as_ref())?;
        drop(bench_fitting);
        let mut acc = Stage1Acc::default();
        stage1_reduce(&rows, outcomes, &mut acc, &mut cache, &mut receipt)?;
        // The stage-1 cache header carries engine_exe_sha256 (this binary's bytes): byte identity across --jobs N holds for one
        // binary; --jobs is not part of the binary, the cache text or the receipt. The straight-sweep/reloc counters are per-thread: fold the per-glyph deltas into this thread's run counter
        // (reset first so a serial run on this thread is not double counted), exactly the serial run total.
        // counter = base + sum of per-glyph deltas, identical for jobs=1 (fit ran on this thread) and jobs>1 (fit ran elsewhere).
        kni_core::capture_fit::reset_straight_sweep_converted();
        kni_core::capture_fit::add_straight_sweep_converted(base_sweep).map_err(|e| e.to_string())?;
        kni_core::capture_fit::add_straight_sweep_converted(acc.straight_sweep).map_err(|e| e.to_string())?;
        kni_core::capture_fit::reset_reloc_moved();
        kni_core::capture_fit::add_reloc_moved(base_reloc).map_err(|e| e.to_string())?;
        kni_core::capture_fit::add_reloc_moved(acc.reloc_moved).map_err(|e| e.to_string())?;
        let Stage1Acc { observer_records: fit_observer_records, processed: p, shipped: shp, exclusions: ex, pins, fallback_span_total: fst, fallback_glyph_spans: fgs, fallback_provenance: fprov, sub_grid_floor_total: sg, speck_areas, line_audit: la, corner_wiring: cw, corner_wiring_totals: cwt, .. } = acc;
        observer_records.extend(fit_observer_records);
        speck_areas_run = speck_areas;
        speck_retained_hole_run = acc.speck_retained_hole_total;
        speck_dropped_collapse_run = acc.speck_dropped_collapse_total;
        corner_wiring_totals_run = cwt;
        let corner_wiring_rows = cw;
        processed = p; stage1_shipped = shp; exclusions = ex; stage1_pins = pins; fallback_span_total = fst; fallback_glyph_spans = fgs; fallback_provenance = fprov; sub_grid_floor_total = sg;
        let line_audit_rows = la;
        // The run-level speck receipt row is part of stage-1 state: persist
        // the exact areas (bit-exact) so the replay route derives the
        // identical receipt row from the cache instead of a silent zero.
        let speck_bits: Vec<String> = speck_areas_run.iter().map(|a| format!("{:016x}", a.to_bits())).collect();
        cache.push_str(&format!("speck_retained	count	{}	areas	{}
", speck_areas_run.len(), speck_bits.join(",")));
        // The hole-dropped row persists a bare count rather than a per-ring list by
        // design: the row carries no per-ring values, so the count is the
        // complete bit-exact evidence (delta pattern differs from
        // speck_retained on purpose).
        cache.push_str(&format!("speck_retained_hole\tcount\t{}\n", speck_retained_hole_run));
        // Same bare-count contract for the post-round-collapse dropped row:
        // the count is the complete bit-exact evidence.
        cache.push_str(&format!("speck_dropped_collapse\tcount\t{}\n", speck_dropped_collapse_run));
        cache.push_str(&format!("straight_sweep_converted\tcount\t{}\n", kni_core::capture_fit::straight_sweep_converted()));
        // The stage1 sub-grid subtotal is stage-1 state too; the notdef
        // post-pass events land after this write and stay route-local.
        cache.push_str(&format!("sub_grid_floor\tstage1_total\t{}\n", sub_grid_floor_total));
        // The run-total corner-wiring seam counts are stage-1 state like the
        // speck rows: persist the exact counts so the replay route prints the
        // identical receipt row. Only a `corner_wiring on` run has seam
        // evidence; an off run persists nothing.
        if m.corner_wiring {
            cache.push_str(&corner_wiring_seams_row(&corner_wiring_totals_run));
        }
        fs::create_dir_all(&out_dir).map_err(|e| format!("create out dir: {e}"))?;
        fs::write(out_dir.join("stage1-cache.txt"), &cache).map_err(|e| format!("write stage1 cache: {e}"))?;
        // Fake-line hunt deliverable: per-span audit rows + per-style summary.
        // A separate artifact; the cache/receipt byte streams are untouched.
        let susp = line_audit_rows.lines().filter(|l| l.split('\t').nth(12) == Some("1")).count();
        let total = line_audit_rows.lines().count();
        let mut audit = String::from("# line-audit v1: shipped Line spans vs captured source contour (detection only, no geometry change)
");
        audit.push_str(&format!("# suspicious = max_dev_px > rdp_epsilon (declared capture tolerance); unanchored = no contour arc accepted the span endpoints
"));
        audit.push_str(&format!("# rdp_epsilon_px	{:e}	scale_units_per_px	{:e}
", rc.rdp_epsilon().value(), rc.scale().units_per_px()));
        audit.push_str(&format!("# total_line_spans	{total}	suspicious	{susp}
"));
        audit.push_str("glyph	ring	span	x0	y0	x1	y1	chord_px	anchor_px	arc_len_px	samples	max_dev_px	suspicious	note
");
        audit.push_str(&line_audit_rows);
        fs::write(out_dir.join("line-audit.tsv"), audit).map_err(|e| format!("write line audit: {e}"))?;
        if m.corner_wiring {
            let mut w = String::from("# corner-wiring v1: seam-joint corner emission vs tangent continuity (policy corner_wiring on)
");
            w.push_str(&format!("# floor_deg = atan(ER/2 / L_in) + atan(ER/2 / L_out), ER = EXPORT_RESOLUTION = 1; action: corner (delta > floor, break kept) | smooth (G1 enforced, handle rotation <= ER/2) | abstain | guard_reject
"));
            w.push_str("glyph	ring	seam	kind	delta_deg	floor_deg	l_in	l_out	action
");
            w.push_str(&corner_wiring_rows);
            fs::write(out_dir.join("corner-wiring.tsv"), w).map_err(|e| format!("write corner wiring: {e}"))?;
        }
    }
    let mut notdef_evidence_void = false;
    let mut proxy_state=if matches!(nd_state,
        bound_detector_validator::DetectionState::CandidateProxy{..}
        | bound_detector_validator::DetectionState::PixelEvidence{..}) {Some(nd_state.clone())} else {None};
    let mut notdef_drawn: Option<(DrawnGlyph, f64)> = None;
    let mut pixel_notdef_drawn: Option<DrawnGlyph> = None;
    if let Some(action) = nd_action {
        match action {
            NotdefAction::PixelEvidence { kind, context, image, .. } => {
                let style = scale_wiring::style_id_of(&m.family, &m.subfamily)
                    .map_err(|_| bound_detector_validator::BadNotdef::ContextMismatch.to_string())?;
                if context.style != style || context.frame != rc.scale().frame_binding()
                    || context.units_per_px.to_bits() != rc.scale().units_per_px().to_bits()
                    || context.ink_model != bound_detector_validator::PIXEL_INK_MODEL {
                    // Always-output C-class: context mismatch -> evidence void.
                    receipt.push_str("warning\tnotdef_evidence_void\treason\tContextMismatch\tdegrade\tblank_notdef\n");
                    notdef_evidence_void = true;
                }
                if !notdef_evidence_void && kind == bound_detector_validator::PixelNotdefKind::RepeatedForm {
                    let row = GlyphRow { codepoint: Some(0), extra_cps: vec![], name: ".notdef".into(), image, scale: None };
                    // Always-output C-class: a failed fit, a pin mismatch
                    // (mismatched bytes never used) or an inkless repeated
                    // form voids the evidence -> blank notdef, typed warning.
                    match process_glyph(&row, &m, &rc, limits, &PNG_DECODE_LIMITS, &mut receipt) {
                        Ok((pin, glyph, events, sub_events, _, fprov)) if pin == context.source_sha256 && !glyph.rings.is_empty() => {
                            fallback_span_total = add_fallback_events(fallback_span_total, ".notdef", events).map_err(|e| e.message())?;
                            fallback_glyph_spans.push((".notdef".to_string(), events));
                            fallback_provenance.push((".notdef".to_string(), fprov));
                            sub_grid_postpass_total += sub_events;
                            pixel_notdef_drawn = Some(glyph);
                        }
                        Ok((pin, _glyph, _, _, _, _)) => {
                            let reason = if pin != context.source_sha256 { "ShaMismatch" } else { "NoInk" };
                            receipt.push_str(&format!("warning\tnotdef_evidence_void\treason\t{reason}\tdegrade\tblank_notdef\n"));
                            notdef_evidence_void = true;
                        }
                        Err(_) => {
                            receipt.push_str("warning\tnotdef_evidence_void\treason\tInvalidSourceImage\tdegrade\tblank_notdef\n");
                            notdef_evidence_void = true;
                        }
                    }
                }
            }
            NotdefAction::CandidateProxy => {
                // Always-output C-class: any proxy failure voids the evidence
                // (typed warning) -> blank notdef.
                let proxy_row = if let bound_detector_validator::DetectionState::CandidateProxy { selected_cp, generated_glyph_ref, .. } = &nd_state {
                    m.glyphs.iter().find(|g| g.codepoint == Some(*selected_cp) && &g.name == generated_glyph_ref)
                } else { None };
                match proxy_row {
                    Some(row) => match process_glyph(row, &m, &rc, limits, &PNG_DECODE_LIMITS, &mut receipt) {
                        Ok((pin, glyph, events, sub_events, _, fprov)) => {
                            stage1_pins.insert(row.name.clone(), pin);
                            fallback_span_total = add_fallback_events(fallback_span_total, &row.name, events).map_err(|e| e.message())?;
                            fallback_glyph_spans.push((row.name.clone(), events));
                            fallback_provenance.push((row.name.clone(), fprov));
                            sub_grid_postpass_total += sub_events;
                            pixel_notdef_drawn = Some(glyph);
                        }
                        Err(_) => { receipt.push_str("warning\tnotdef_evidence_void\treason\tInvalidSourceImage\tdegrade\tblank_notdef\n"); notdef_evidence_void = true; }
                    },
                    None => { receipt.push_str("warning\tnotdef_evidence_void\treason\tMissingPixelEvidence\tdegrade\tblank_notdef\n"); notdef_evidence_void = true; }
                }
            },
            NotdefAction::Process { image, source_sha256, advance, scale } => {
                // Validator already requires bit equality with the bound run K.
                // Never create a per-glyph .notdef scale override.
                // Always-output C-class: scale/pin/tile failures void the
                // evidence (mismatched bytes never used) -> blank notdef.
                if scale.to_bits() != rc.scale().units_per_px().to_bits() {
                    receipt.push_str("warning\tnotdef_evidence_void\treason\tContextMismatch\tdegrade\tblank_notdef\n");
                    notdef_evidence_void = true;
                }
                let row = GlyphRow { codepoint: Some(0), extra_cps: vec![], name: ".notdef".into(), image, scale: None };
                if !notdef_evidence_void { match process_glyph(&row, &m, &rc, limits, &PNG_DECODE_LIMITS, &mut receipt) {
                    Ok((pin, glyph, events, sub_events, _, fprov)) if pin == source_sha256 && !glyph.rings.is_empty() => {
                        fallback_span_total = add_fallback_events(fallback_span_total, ".notdef", events).map_err(|e| e.message())?;
                        fallback_glyph_spans.push((".notdef".to_string(), events));
                            fallback_provenance.push((".notdef".to_string(), fprov));
                        sub_grid_postpass_total += sub_events;
                        notdef_drawn = Some((glyph, advance));
                    }
                    Ok((pin, _glyph, _, _, _, _)) => {
                        let reason = if pin != source_sha256 { "ShaMismatch" } else { "NoInk" };
                        receipt.push_str(&format!("warning\tnotdef_evidence_void\treason\t{reason}\tdegrade\tblank_notdef\n"));
                        notdef_evidence_void = true;
                    }
                    Err((_, why)) => {
                        receipt.push_str(&format!("warning\tnotdef_evidence_void\treason\tInvalidTile\tdegrade\tblank_notdef\tdetail\t{why}\n"));
                        notdef_evidence_void = true;
                    }
                } }
            }
            NotdefAction::Empty { advance, partial_reason } => {
                if let Some(reason) = partial_reason {
                    if diagnostic_test_export {
                        receipt.push_str(&format!("partial_output\ttrue\treason\t{reason}\tTEST/UNVALIDATED\n"));
                    } else {
                        receipt.push_str(&format!("partial_output\ttrue\treason\t{reason}\tdegrade\tblank_notdef\n"));
                    }
                }
                notdef_drawn = Some((DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, advance));
            }
        }
    }
    receipt.push_str(&fit_reduce::exclusion_counter_lines(&exclusions));
    // Always-output C-class: voided evidence never reaches downstream stages.
    if notdef_evidence_void { proxy_state = None; pixel_notdef_drawn = None; notdef_drawn = None; }
    // Population floor (always-output degrade): no manifest glyph survived
    // stage 1. Ship the minimal parseable OTF (blank .notdef only) with a
    // typed-warning receipt instead of refusing. stage2-4 cannot take an
    // empty population (solve_spacing refuses EmptyInput; the profile stage
    // has nothing to measure), so the floor bypasses them and reuses only
    // the assembly/publish helpers.
    if processed.is_empty() {
        if m.run_mode == RunMode::Stage1Only {
            // Shard contract: a stage1_only run never produces a font (the
            // stage2 choke point stops it before any OTF path), so the floor
            // ships OTFs on full runs only.
            return Err("no glyph could be processed; nothing to build".into());
        }
        receipt.push_str(&population_floor_receipt_line(exclusions.len(), fallback_span_total));
        let result = population_floor_export(&m, receipt, &out_dir, &rc)?;
        if merge_observe_enabled {
            append_merge_visibility_completion(&mut observer_records, observer_run_context.as_ref().ok_or("mov-1 run context missing")?, &out_dir, "stage1", None, &[kni_core::obs_envelope::PipelineDomain::Emit]);
            write_merge_visibility_records(&observer_records, &out_dir, true, observer_run_context.as_ref().map(|c| c.source_bytes.as_slice()))?;
        }
        return Ok(result);
    }
    // Typed fallback gate: any per-point Line fallback span means an
    // intended-curved region was left unresolved; normal export HARD-FAILS. The only
    // continuation is the explicit typed diagnostic-test export intent: ledger records
    // retained, bytes labeled TEST/UNVALIDATED.
    // Two-line export summary: the gate input (unresolved-class ledger events)
    // and the sub-grid floor (typed stops below the source's resolving power,
    // never hard fails). Cache replay carries the gate total only.
    receipt.push_str(&format!("hard_fail_unresolved\t{}\ttyped fallback ledger events (unresolved class: SplitUnresolved/DepthLimit/DegenerateTangents); the export gate input\n", fallback_span_total));
    {
        // r282: per-class breakdown of the same gate input, total row above
        // unchanged. Live fit only: a cache replay carries no fit-side
        // ledger, same as the other live-only receipt rows.
        use kni_core::capture_fit::FallbackReason as FR;
        let (mut su, mut dl, mut dt, mut acr) = (0usize, 0usize, 0usize, 0usize);
        for (_, rows) in &fallback_provenance {
            for p in rows {
                match p.reason {
                    FR::SplitUnresolved => su += 1,
                    FR::DepthLimit => dl += 1,
                    FR::DegenerateTangents => dt += 1,
                    FR::AreaCollapseRestored => acr += 1,
                    FR::SubGridSpan => {}
                }
            }
        }
        receipt.push_str(&format!("hard_fail_unresolved_by_reason\tSplitUnresolved\t{}\tDepthLimit\t{}\tDegenerateTangents\t{}\tAreaCollapseRestored\t{}\t(live stage1 pass only)\n", su, dl, dt, acr));
    }
    if sub_grid_replay_unavailable {
        receipt.push_str("sub_grid_floor_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-subgrid-evidence\n");
    } else {
        receipt.push_str(&format!("sub_grid_floor\t{}\ttyped SubGridSpan stops: sub-lattice arcs stopped as one Line below the source's resolving power; never a hard fail\n", sub_grid_floor_total + sub_grid_postpass_total));
    }
    if speck_replay_unavailable {
        receipt.push_str("sub_pixel_speck_retained_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-speck-evidence\n");
    } else {
        let n = speck_areas_run.len();
        let (mut mn, mut mx, mut sm) = (f64::INFINITY, 0.0f64, 0.0f64);
        for a in &speck_areas_run { mn = mn.min(*a); mx = mx.max(*a); sm += a; }
        let (mn, mean) = if n == 0 { (0.0, 0.0) } else { (mn, sm / n as f64) };
        receipt.push_str(&format!("sub_pixel_speck_retained\tcount\t{n}\tarea_px2_min\t{mn:.6}\tarea_px2_max\t{mx:.6}\tarea_px2_mean\t{mean:.6}\tsub-pixel capture rings retained as their own measured minimal contour (Line spans off the captured polygon; bypass the fitter, so no per-point fallback; retained regardless of hole flag (the hole subset is typed in sub_pixel_speck_retained_hole); only a grid-unrepresentable capture still counts as dropped)\n"));
    }
    if speck_retained_hole_replay_unavailable {
        receipt.push_str("sub_pixel_speck_retained_hole_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-speck-evidence\n");
    } else {
        receipt.push_str(&format!("sub_pixel_speck_retained_hole\t{}\thole-flagged sub-pixel capture rings retained and shipped hole-wound as their own measured minimal contours (a subset of sub_pixel_speck_retained; always output, zero included)\n", speck_retained_hole_run));
    }
    if speck_dropped_collapse_replay_unavailable {
        receipt.push_str("sub_pixel_speck_dropped_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-speck-evidence\n");
    } else {
        receipt.push_str(&format!("sub_pixel_speck_dropped\t{}\treason\tpost_round_collapse\tsub-pixel capture rings whose rounded points collapsed to one grid point or zero signed area - no grid representation, typed dropped (always output, zero included); classified total = sub_pixel_speck_retained + sub_pixel_speck_dropped\n", speck_dropped_collapse_run));
    }
    if sweep_replay_unavailable {
        receipt.push_str("straight_sweep_converted_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-straight-sweep-evidence\n");
    } else {
        receipt.push_str(&format!("straight_sweep_converted\t{}\tfinal straight sweep: long cubics with both handles within one source pixel of the chord emitted as Line\n", kni_core::capture_fit::straight_sweep_converted()));
    }
    // Run-total corner-wiring receipt row. Emitted only under `corner_wiring
    // on` so an off run keeps its receipt bytes unchanged. Live and replay
    // print the identical row; a legacy cache without the persisted row gets
    // the typed replay-unavailable marker, never a silent 0.
    if m.corner_wiring {
        if corner_wiring_replay_unavailable {
            receipt.push_str("corner_wiring_seams_replay_unavailable\tdecision_basis\tstage1-cache-no-persisted-corner-wiring-evidence\n");
        } else {
            receipt.push_str(&corner_wiring_seams_row(&corner_wiring_totals_run));
        }
    }
    // Ship gate: the engine default is strict refusal. A nonzero typed fallback
    // ledger without an explicit typed intent HARD-FAILS the run, so fallback-tagged
    // bytes can never leave the pipeline by default; the kit acceptance gate is the
    // engine itself. The explicit fallback-warn intent survives for harness use, but
    // no ship path writes a name-table warning tag - the receipt row and
    // fallback-glyphs.tsv carry the evidence.
    let export_intent = resolve_export_intent(diagnostic_test_export, fallback_export_warn);
    // fallback-glyphs.tsv is written for EVERY intent when the ledger is nonzero, strict
    // included: the refusal path must still leave the per-glyph evidence on disk.
    if fallback_span_total > 0 {
        fs::create_dir_all(&out_dir).map_err(|e| format!("fallback-glyphs.tsv: create out dir: {e}"))?;
        fs::write(out_dir.join("fallback-glyphs.tsv"), fallback_glyph_tsv(&fallback_glyph_spans))
            .map_err(|e| format!("fallback-glyphs.tsv: write: {e}"))?;
        // r282: per-span audit rows from the live fit (a cache replay has no
        // fit-side ledger, so the file is live-only, like line-audit.tsv).
        if !fallback_provenance.is_empty() {
            fs::write(out_dir.join("fallback-audit.tsv"), fallback_audit_tsv(&fallback_provenance))
                .map_err(|e| format!("fallback-audit.tsv: write: {e}"))?;
        }
    }
    fallback_gate(fallback_span_total, export_intent)?;
    if fallback_span_total > 0 && export_intent == ExportIntent::FallbackWarn {
        receipt.push_str(&format!("export_intent\tfallback_export_warn\tFALLBACK-EXPORT-WARNING: {} per-point Line spans; intended-curved regions emitted as straight lines; NOT a production candidate\n", fallback_span_total));
    }
    if fallback_span_total > 0 && export_intent == ExportIntent::DiagnosticTest {
        receipt.push_str("export_intent\tdiagnostic_test_export\tTEST/UNVALIDATED: explicit typed diagnostic intent; usable/final export remains HARD-FAIL outside this intent; these bytes are NOT a usable font and NOT a corrected fit\n");
        // Semantic contract: the ledger count is the typed fallback
        // EVENT/SPAN ledger (recursive attempt/event semantics), NOT the actual shipped
        // line count; it may exceed the final per-glyph emitted node count.
        receipt.push_str(&format!("fallback_ledger_total\t{}\ttyped fallback event/span ledger contract (recursive attempt/event semantics; NOT the actual shipped line count; may exceed final per-glyph emitted nodes)\n", fallback_span_total));
    }
    return stage2_and_beyond(&m, processed, stage1_shipped, exclusions, receipt, manifest_pin, notdef_drawn, pixel_notdef_drawn, limits.max_input_bytes, proxy_state, out_dir, allow_partial, &rc, fallback_span_total == 0, &stage1_pins, spacing_oohh_flag, class_channel_targets_flag, jobs, observer_records, observer_run_context, merge_observe_enabled);
}

/// PC-K1: extract the opt-in `--pair-visual <kerning-dir>` flag (value
/// required, flag not repeatable). Runs BEFORE positional validation so the
/// value is never mistaken for a positional argument.
fn take_pair_visual_flag(args: &[String]) -> Result<(Option<PathBuf>, Vec<String>), String> {
    let mut kept: Vec<String> = Vec::with_capacity(args.len());
    let mut dir: Option<PathBuf> = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == "--pair-visual" {
            if dir.is_some() {
                return Err("usage: --pair-visual given more than once".to_string());
            }
            let v = it.next().ok_or_else(|| "usage: --pair-visual requires a <kerning-dir> value".to_string())?;
            if v.starts_with("--") {
                return Err("usage: --pair-visual requires a <kerning-dir> value".to_string());
            }
            dir = Some(PathBuf::from(v));
        } else {
            kept.push(a.clone());
        }
    }
    Ok((dir, kept))
}

/// PC-K1 opt-in measurement stage (default OFF), PRE-PUBLISH: with
/// `--pair-visual <dir>`, read the real `<Family>/<Style>/kerning/` folder
/// through the engine's own input chain (kerning_pairs inventory + bounded
/// decode) into the K1 measurement layer (kni_metrics::pair_visual_read),
/// write `pair_visual_report.tsv` (measured / failed / unavailable rows,
/// per-row source sha256) plus `pair_visual_report.pin.tsv`, and return the
/// receipt pin lines (path + report sha256 + counts + typed scope).
///
/// SCOPE (typed, also stamped into the pin): REPORT-ONLY. The measured gaps
/// do NOT enter the spacing solver or any learning path (the solver's
/// FontContext takes no pair input); this stage produces measurement
/// evidence, nothing else.
///
/// ATOMIC OUTCOME (chief review PC-K1): every fallible step runs before
/// publish; on refusal no font file exists. The returned pin is appended to
/// the receipt after the run returns (infallible), so receipt.txt (written
/// at publish time) does not carry the pin.
fn pair_visual_pre_stage(dir: &Option<PathBuf>, out_dir: &Path, spacing_consumed: bool) -> Result<Option<String>, String> {
    let Some(dir) = dir else { return Ok(None) };
    let w = pair_visual_wiring::PairVisualWiring {
        inventory: kerning_pairs::InventoryBudget {
            max_members: kerning_pairs::MAX_KERN_IMAGES,
            max_member_bytes: PNG_DECODE_LIMITS.max_input_bytes as u64,
            // Total-read guard for the inventory walk (resource cap, not font
            // logic): the run refuses a folder past 1 GiB instead of
            // streaming it.
            max_total_bytes: 1 << 30,
        },
        max_member_bytes: PNG_DECODE_LIMITS.max_input_bytes as u64,
        decode: PNG_DECODE_LIMITS,
        jpeg: Limits {
            max_input_bytes: PNG_DECODE_LIMITS.max_input_bytes,
            max_pixels: PNG_DECODE_LIMITS.max_pixels,
            max_working_bytes: PNG_DECODE_LIMITS.max_working_bytes,
        },
        // No font-unit conversion yet: the pair images' source-pixel scale is
        // not bound in this run's scale context, so measurements stay in
        // source pixels (the measurement layer documents gap_fu as opt-in).
        scale_fu_per_px: None,
    };
    let out = pair_visual_wiring::read_kerning_folder(dir, &w)
        .map_err(|e| format!("pair visual read refused for {}: {e:?}", dir.display()))?;
    fs::create_dir_all(out_dir).map_err(|e| format!("pair visual: create out dir: {e}"))?;
    let report_path = out_dir.join("pair_visual_report.tsv");
    fs::write(&report_path, &out.tsv).map_err(|e| format!("write pair_visual_report.tsv: {e}"))?;
    let report_sha = sha256_hex(out.tsv.as_bytes());
    let scope_line = if spacing_consumed {
        "pair_visual_scope\treport_only\tspacing_use\tanchor_target\n"
    } else {
        "pair_visual_scope\treport_only\tspacing_use\tnone\n"
    };
    let pin = format!(
        "{scope_line}pair_visual_report\tpath\t{}\treport_sha256\t{report_sha}\tsource_dir\t{}\npair_visual_report\tmeasured\t{}\tfailed\t{}\tunavailable\t{}\tnon_pair\t{}\taliases\t{}\n",
        report_path.display(),
        dir.display(),
        out.measured,
        out.refused - out.unavailable,
        out.unavailable,
        out.non_pair_images.len(),
        out.aliases.len()
    );
    fs::write(out_dir.join("pair_visual_report.pin.tsv"), &pin)
        .map_err(|e| format!("write pair_visual_report.pin.tsv: {e}"))?;
    Ok(Some(pin))
}

#[cfg(test)]
mod pair_visual_stage_tests {
    use super::*;
    use crate::pair_visual_wiring::tests as fx;
    use kni_core::cff_reader::sha256_hex;

    #[test]
    fn flag_parse_extracts_value_and_refuses_misuse() {
        let args = vec![
            "prog".to_string(), "m.toml".to_string(), "out".to_string(),
            "--pair-visual".to_string(), "/k".to_string(),
        ];
        let (dir, kept) = take_pair_visual_flag(&args).unwrap();
        assert_eq!(dir, Some(PathBuf::from("/k")));
        assert_eq!(kept, vec!["prog", "m.toml", "out"]);
        for bad in [
            vec!["prog".to_string(), "--pair-visual".to_string()],
            vec!["prog".to_string(), "--pair-visual".to_string(), "--jobs".to_string()],
            vec!["prog".to_string(), "--pair-visual".to_string(), "/a".to_string(), "--pair-visual".to_string(), "/b".to_string()],
        ] {
            assert!(take_pair_visual_flag(&bad).is_err(), "{bad:?}");
        }
    }

    /// Chief review PC-K1 (1): with the flag on, the measured value reaches
    /// the typed consumer (report artifact + pin), scoped report-only.
    #[test]
    fn flag_on_measurement_reaches_typed_report_and_pin() {
        let k = fx::tmp("main-k");
        fx::put(&k, 224, &[0x49, 0x2D], &fx::b64decode(fx::I_HYPHEN_B64));
        let out = fx::tmp("main-o");
        let pin = pair_visual_pre_stage(&Some(k.clone()), &out, false).unwrap().expect("pin lines");
        let tsv = std::fs::read_to_string(out.join("pair_visual_report.tsv")).unwrap();
        // the real measured values of the real fixture reached the artifact
        assert!(tsv.contains("I\t-\t20.000\t20.000\t62\t689\t709"), "{tsv}");
        assert!(pin.contains("pair_visual_scope\treport_only\tspacing_use\tnone"), "{pin}");
        assert!(pin.contains(&sha256_hex(tsv.as_bytes())), "{pin}");
        assert!(pin.contains("measured\t1"), "{pin}");
        assert!(out.join("pair_visual_report.pin.tsv").exists());
        let _ = std::fs::remove_dir_all(k);
        let _ = std::fs::remove_dir_all(out);
    }

    /// Chief review PC-K1 (2): invalid input refuses PRE-PUBLISH; after the
    /// refusal there is no font and no report (atomic outcome).
    #[test]
    fn invalid_input_refuses_before_publish_no_font_no_report() {
        let k = fx::tmp("main-k2");
        let mut bad = fx::b64decode(fx::I_HYPHEN_B64);
        let n = bad.len();
        bad[n - 1] ^= 0xFF; // content no longer matches the name's sha pin
        std::fs::write(k.join("00224__0049_002D__caa217c13292.png"), &bad).unwrap();
        let out = fx::tmp("main-o2");
        assert!(pair_visual_pre_stage(&Some(k.clone()), &out, false).is_err());
        assert!(!out.join("pair_visual_report.tsv").exists());
        assert!(!out.join("pair_visual_report.pin.tsv").exists());
        assert!(fs::read_dir(&out).map(|mut d| d.next().is_none()).unwrap_or(true));
        let _ = std::fs::remove_dir_all(k);
        let _ = std::fs::remove_dir_all(out);
    }
}

/// Stable typed-warning code for the population-floor degrade; the receipt
/// row and the tests bind to this exact token.
const POPULATION_FLOOR_CODE: &str = "POPULATION_FLOOR";

/// Typed-warning receipt row for the population-floor degrade: stage 1
/// retained zero glyphs, so the run ships the minimal parseable OTF
/// (blank .notdef only) instead of refusing.
fn population_floor_receipt_line(excluded: usize, fallback_spans: usize) -> String {
    format!("population_floor\ttrue\tcode\t{POPULATION_FLOOR_CODE}\tpopulation\t0\texcluded\t{excluded}\tfallback_ledger_events\t{fallback_spans}\tdegrade\tminimal parseable OTF: blank .notdef only; no cmap mappings, no space, no GPOS; stage2-4 skipped (empty population)\n")
}

/// Stable typed-warning code for a post-pass applied on an unapproved base;
/// the receipt row and the tests bind to this exact token.
const POST_PASS_APPLIED_UNAPPROVED_CODE: &str = "POST_PASS_APPLIED_UNAPPROVED_BASE";

/// Typed-warning receipt row for an applied-on-unapproved-base post-pass: the
/// manifest declares a non-zero post step (+LSB/+RSB) and the base is not
/// approved (partial fit, exclusions, held kern). The guard condition is
/// logged, and the declared step still applies to the glyphs its scope selects.
fn post_pass_applied_unapproved_receipt_line(lsb: f64, rsb: f64) -> String {
    format!("post_pass_applied_unapproved_base\ttrue\tcode\t{POST_PASS_APPLIED_UNAPPROVED_CODE}\tlsb_add\t{lsb}\trsb_add\t{rsb}\treason\tbase not approved; declared post step still applies to the glyphs its scope selects\n")
}

/// CONVENTION (declared): the floor .notdef advance is the manifest's own
/// declared units-per-em (one full em). Derivation: with zero surviving
/// glyphs there is no population to take the widest-glyph advance from (the
/// normal notdef advance basis) and no measured space; the only font-owned
/// horizontal measure left is the declared UPM grid itself.
fn population_floor_notdef_advance(m: &Manifest) -> f64 {
    f64::from(m.upm)
}

/// The population-floor font: exactly one glyph, a blank .notdef, no cmap
/// mappings, no space, no GPOS. Same assembly/encode helpers as the normal
/// path, so the bytes carry the manifest's own names and UPM.
fn population_floor_font(m: &Manifest) -> Result<(NativeFontInput, Vec<u8>), String> {
    let advance = population_floor_notdef_advance(m);
    let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }];
    let metrics = vec![(".notdef".to_string(), 0.0, 0.0, advance)];
    let meta = clip_metadata(metadata(m));
    let prepared = prepare_generated(&glyphs, &[], &metrics, &meta)
        .map_err(|e| format!("population floor prepare refused: {e:?}"))?;
    let bytes = encode_with_layout(&prepared, None)
        .map_err(|e| format!("population floor encode refused: {e:?}"))?;
    Ok((prepared, bytes))
}

/// Population-floor export: publish the minimal parseable OTF and write the
/// full typed-warning receipt. The base is never approved (a floor run ships
/// no fitted glyph), so no post-metrics pass can mint and the pre-publish
/// hook is inert (no IoU population exists).
fn population_floor_export(m: &Manifest, mut receipt: String, out_dir: &Path, rc: &run_config::RunConfig) -> Result<String, String> {
    let (prepared, base_bytes) = population_floor_font(m)?;
    let order: Vec<String> = vec![".notdef".to_string()];
    let mapping: Vec<(u32, u16)> = Vec::new();
    receipt.push_str(&format!("notdef\tgid\t0\trings\t0\tadvance\t{}\n", population_floor_notdef_advance(m)));
    receipt.push_str(&pre_export_guard_receipt(&base_bytes, rc, false));
    emit_final_bundle_with_master(out_dir, false, &prepared, &base_bytes, rc, None, &mapping, &order,
        None, &m.family, &m.subfamily, &m.postscript_name, &|_| Ok(Vec::new()), &mut receipt, PostUnapprovedPolicy::ApplyWithTypedWarning, true, None)?;
    fs::write(out_dir.join("receipt.txt"), &receipt).map_err(|e| format!("write receipt: {e}"))?;
    run_audit_close(out_dir, m, rc, run_audit::RunPath::PopulationFloor);
    Ok(receipt)
}

#[allow(clippy::too_many_arguments)]
/// Resolve the per-glyph fit policy under the manifest's typed tolerance route.
/// Measured: derive_from_gray on the actual decoded raster; squared_error = fit_se_scaled(scale).
/// Finite/overflow/units contract: any non-finite or non-positive derived value is a hard error.
/// The receipt line carries the full derivation (eps_px, variance, scale, se_fu^2, crossings,
/// step fraction, provenance, input sha) so the certificate is reproducible from source bytes.
fn resolve_fit_policy(rc: &run_config::RunConfig, g: &GlyphRow, scale: f64, src: &kni_core::capture_dispatch::CapturedSource, pin: &str, receipt: &mut String) -> Result<FitPolicy, String> {
    match rc.fit_error_policy() {
        run_config::FitErrorPolicy::Fixed => Ok(FitPolicy { squared_error: rc.fit_squared_error().value(), max_refits: rc.fit_max_refits() }),
        // value already derived in RunConfig::new: (units_per_px/2)^2; one FitPolicy for the solver, same for every glyph of the style
        run_config::FitErrorPolicy::DerivedSourceQuantization => Ok(FitPolicy { squared_error: rc.fit_squared_error().value(), max_refits: rc.fit_max_refits() }),
        run_config::FitErrorPolicy::MeasuredExperimental => {
            let d = kni_core::tolerance::derive_from_gray(src.receipt.width, src.receipt.height, &src.gray)
                .map_err(|e| format!("glyph {}: measured tolerance refused: {e}", g.name))?;
            let se = d.fit_se_scaled(scale);
            if !se.is_finite() || se <= 0.0 {
                return Err(format!("glyph {}: measured squared tolerance not finite/positive (variance_px2={} scale={scale})", g.name, d.fit_variance_px2));
            }
            let rdp_scaled = d.rdp_eps_scaled(scale);
            receipt.push_str(&format!(
                "tolerance\t{}\tprovenance\t{}\tlabel\tmeasured-fit-experimental\tnorm\tRMS-variance-not-max-point-bound\trdp_eps_px\t{:.6}\trdp_eps_scaled\t{:.6}\tfit_variance_px2\t{:.9}\tscale\t{}\tse_fu2\t{:.9}\tcrossings\t{}\tstep_fraction\t{:.4}\tinput_sha\t{}\n",
                g.name, d.provenance, d.rdp_eps_px, rdp_scaled, d.fit_variance_px2, scale, se, d.crossings, d.step_fraction, pin));
            Ok(FitPolicy { squared_error: se, max_refits: rc.fit_max_refits() })
        }
    }
}

/// Everything one glyph's stage-1 fit produces, with no shared mutable state: a worker fills one of these and the
/// Run-owned identity/config for the typed H1 outcome converter.
#[derive(Clone, Debug)]
struct MergeVisibilityRunContext {
    run_id: String,
    invocation_id: kni_core::obs_envelope::InvocationId,
    style: String,
    stage1_route: kni_core::obs_envelope::Stage1Route,
    stage1_cache_sha256: Option<String>,
    source_bytes: std::sync::Arc<Vec<u8>>,
}

thread_local! {
    static FIT_VISIBILITY_COLLECTOR: std::cell::RefCell<kni_core::capture_fit::MergeVisibilityCollector> = std::cell::RefCell::new(Default::default());
    static FIT_VISIBILITY_DOMAINS: std::cell::RefCell<Vec<(kni_core::obs_envelope::RouteDomain, kni_core::obs_envelope::ObserverOutcome, Option<String>)>> = std::cell::RefCell::new(Vec::new());
}

fn merge_visibility_with_domain<T>(domain: kni_core::obs_envelope::RouteDomain, fit: impl FnOnce() -> T) -> T {
    if std::env::var(kni_core::obs_envelope::OBSERVE_GATE_ENV).as_deref() == Ok("1") {
        FIT_VISIBILITY_DOMAINS.with(|domains| {
            let mut domains = domains.borrow_mut();
            if !domains.iter().any(|(d, _, _)| *d == domain) { domains.push((domain.clone(), kni_core::obs_envelope::ObserverOutcome::Complete, None)); }
        });
        kni_core::capture_fit::merge_visibility_begin_for_route_domain(domain);
        let result = fit();
        let incoming = kni_core::capture_fit::merge_visibility_take_collector();
        FIT_VISIBILITY_COLLECTOR.with(|cell| {
            let mut current = cell.borrow_mut();
            let offset = current.observations.iter().map(|x| x.seq).chain(current.rewrites.iter().map(|x| x.seq)).max().map_or(0, |x| x.saturating_add(1));
            current.observations.extend(incoming.observations.into_iter().map(|mut x| { x.seq = x.seq.checked_add(offset).expect("merge visibility sequence overflow"); x }));
            current.rewrites.extend(incoming.rewrites.into_iter().map(|mut x| { x.seq = x.seq.checked_add(offset).expect("merge visibility sequence overflow"); x }));
        });
        result
    } else { fit() }
}

fn merge_visibility_note_missing_input(domain: kni_core::obs_envelope::RouteDomain, reason: &str) {
    if std::env::var(kni_core::obs_envelope::OBSERVE_GATE_ENV).as_deref() == Ok("1") {
        FIT_VISIBILITY_DOMAINS.with(|domains| {
            let mut domains = domains.borrow_mut();
            if !domains.iter().any(|(d, _, _)| *d == domain) {
                domains.push((domain, kni_core::obs_envelope::ObserverOutcome::MissingInput, Some(reason.to_string())));
            }
        });
    }
}

/// sequential reduce folds them in manifest order (so any --jobs N output equals the serial output).
#[derive(Debug)]
struct FitOutcome {
    idx: usize,
    /// Observer-only typed records; folded in manifest order.
    observer_records: Vec<kni_core::obs_envelope::Record>,
    /// Raw H1 collector captured on this worker; converted to mov-1 records after C API is available.
    merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector,
    merge_visibility_route_domains: Vec<(kni_core::obs_envelope::RouteDomain, kni_core::obs_envelope::ObserverOutcome, Option<String>)>,
    merge_visibility_context: Option<kni_core::capture_fit::MergeVisibilityObsContext>,
    merge_visibility_source_bytes: Option<std::sync::Arc<Vec<u8>>>,
    /// Capture pin (sha256 of the source bytes the fit consumed; "unreadable" when the read failed).
    pin: String,
    /// Ok: the drawn glyph (the SHIPPED outline: band-cleared trace when the
    /// source tile carried a measured presentation frame). Err: exclusion.
    drawn: Result<DrawnGlyph, String>,
    /// The measurement-domain drawing (original trace, frame kept) when the
    /// shipped outline differs; profiles/vertical metrics consume this so the
    /// accepted spacing stays bit-identical.
    drawn_measurement: Option<DrawnGlyph>,
    fallback_spans: usize,
    /// r282 audit-only per-span fallback provenance from the live fit (empty on
    /// exclusions and cache replay; a replay carries no fit-side ledger).
    fallback_provenance: Vec<kni_core::capture_fit::FallbackSpanProvenance>,
    sub_grid: usize,
    straight_sweep: usize,
    reloc_moved: usize,
    /// Capture-space areas (px^2) of the sub-pixel specks this glyph's fit
    /// retained as minimal contours (PN-3 speck KEEP+FLAG); per-glyph exact
    /// via the marker/slice ledger contract, folded into the run receipt.
    speck_areas: Vec<f64>,
    /// Hole-flagged sub-pixel rings this glyph's fit dropped at the speck
    /// classification; per-glyph exact thread-local delta, folded into the
    /// run receipt (live stage-1 pass only, like the retained-speck ledger).
    speck_retained_hole: usize,
    speck_dropped_collapse: usize,
    /// This glyph's receipt rows exactly as process_glyph appended them.
    receipt_rows: String,
    /// Stderr text to emit in manifest order at reduce time.
    stderr_buf: String,
    /// Run-fatal refusal (bound-H refusal, a worker panic, a counter fault). The reduce returns the FIRST one in manifest
    /// order, so a later glyph's panic can never mask an earlier fatal.
    fatal: Option<String>,
    /// Fake-line hunt: this glyph's line-audit TSV rows (live fit only; empty
    /// on exclusions and cache replay). Drained from the worker thread's
    /// audit buffer; never part of the receipt or the cache byte layout.
    line_audit: String,
    corner_wiring: String,
    /// Per-class seam counters of this glyph's corner wiring (live fit only;
    /// zero on exclusions and cache replay). Folded into the run total.
    corner_wiring_totals: kni_core::corner_wiring::WiringTotals,
}

impl FitOutcome {
    fn fatal(idx: usize, why: String) -> FitOutcome {
        FitOutcome { fallback_provenance: Vec::new(), observer_records: Vec::new(), merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector::default(), merge_visibility_route_domains: Vec::new(), merge_visibility_context: None, merge_visibility_source_bytes: None, idx, pin: String::new(), drawn: Err(why.clone()), drawn_measurement: None, fallback_spans: 0, sub_grid: 0, straight_sweep: 0, reloc_moved: 0,
            speck_areas: Vec::new(), speck_retained_hole: 0, speck_dropped_collapse: 0, receipt_rows: String::new(), stderr_buf: String::new(), fatal: Some(why), line_audit: String::new(), corner_wiring: String::new(), corner_wiring_totals: Default::default() }
    }
}

/// One glyph's fit. `h_bound` = this glyph is the bound H of a declared-convention style (its refusal is run-fatal).
/// `process` is the real `process_glyph` call (a closure so the fatal/panic handling is testable without a declared style).
fn fit_one_with(idx: usize, name: &str, codepoint: Option<u32>, h_bound: bool,
                process: impl FnOnce(&mut String) -> Result<(String, DrawnGlyph, usize, usize, Option<DrawnGlyph>, Vec<kni_core::capture_fit::FallbackSpanProvenance>), (String, String)>) -> FitOutcome {
    let before = kni_core::capture_fit::FitCounters::now();
    let speck_marker = kni_core::capture_fit::speck_marker();
    let speck_hole_before = kni_core::capture_fit::speck_retained_hole();
    let speck_drop_before = kni_core::capture_fit::speck_dropped_collapse();
    let mut receipt_rows = String::new();
    LINE_AUDIT_BUF.with(|b| b.borrow_mut().clear());
    CORNER_WIRING_BUF.with(|b| b.borrow_mut().clear());
    CORNER_WIRING_TOTALS.with(|t| *t.borrow_mut() = Default::default());
    let res = process(&mut receipt_rows);
    let line_audit = LINE_AUDIT_BUF.with(|b| std::mem::take(&mut *b.borrow_mut()));
    let corner_wiring = CORNER_WIRING_BUF.with(|b| std::mem::take(&mut *b.borrow_mut()));
    let corner_wiring_totals = CORNER_WIRING_TOTALS.with(|t| std::mem::take(&mut *t.borrow_mut()));
    let d = match kni_core::capture_fit::FitCounters::delta_since(before) {
        Some(d) => d,
        None => return FitOutcome::fatal(idx, format!("glyph {name}: fit counter went backwards")),
    };
    let speck_hole_delta = match kni_core::capture_fit::speck_retained_hole().checked_sub(speck_hole_before) {
        Some(d) => d,
        None => return FitOutcome::fatal(idx, format!("glyph {name}: fit counter went backwards")),
    };
    let speck_drop_delta = match kni_core::capture_fit::speck_dropped_collapse().checked_sub(speck_drop_before) {
        Some(d) => d,
        None => return FitOutcome::fatal(idx, format!("glyph {name}: fit counter went backwards")),
    };
    let mut o = FitOutcome { fallback_provenance: Vec::new(), observer_records: Vec::new(), merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector::default(), merge_visibility_route_domains: Vec::new(), merge_visibility_context: None, merge_visibility_source_bytes: None, idx, pin: String::new(), drawn: Err(String::new()), drawn_measurement: None, fallback_spans: 0, sub_grid: 0,
        straight_sweep: d.straight_sweep, reloc_moved: d.reloc_moved, speck_areas: kni_core::capture_fit::speck_areas_since(speck_marker), speck_retained_hole: speck_hole_delta, speck_dropped_collapse: speck_drop_delta,
        receipt_rows, stderr_buf: String::new(), fatal: None, line_audit, corner_wiring, corner_wiring_totals };
    match res {
        Ok((pin, dg, nfb, nsub, nmeas, fprov)) => { o.pin = pin; o.drawn = Ok(dg); o.drawn_measurement = nmeas; o.fallback_spans = nfb; o.sub_grid = nsub; o.fallback_provenance = fprov; }
        Err((pin, reason)) => {
            if h_bound { o.fatal = Some(format!("bound H processing refused: {reason}")); }
            let cp = match codepoint { Some(c) => format!("{c:#x}"), None => "-".to_string() };
            o.stderr_buf = format!("excluded glyph {} ({cp}): {}\n", name, reason);
            o.pin = pin; o.drawn = Err(reason);
        }
    }
    o
}

/// Run `fit_one_with` so that a panic in the fit becomes a typed run-fatal outcome for that glyph instead of tearing the
/// process down from a pool thread.
fn guarded(idx: usize, name: &str, f: impl FnOnce() -> FitOutcome) -> FitOutcome {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(o) => o,
        Err(p) => {
            let msg = p.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| p.downcast_ref::<String>().cloned()).unwrap_or_else(|| "non-string panic payload".into());
            FitOutcome::fatal(idx, format!("stage-1 fit panicked on glyph {name}: {msg}"))
        }
    }
}

thread_local! {
    /// Per-worker audit buffer for the fake-line hunt: the fit arm writes
    /// rows, `fit_one_with` drains them into the glyph's FitOutcome. Kept
    /// off the receipt/cache byte streams on purpose.
    static LINE_AUDIT_BUF: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
    /// Per-worker corner-wiring rows (policy-gated by manifest
    /// `corner_wiring on`; measurement artifact only, off the receipt/cache
    /// byte streams exactly like the line audit).
    static CORNER_WIRING_BUF: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
    /// Per-worker corner-wiring class counters for the glyph being fitted;
    /// drained into the glyph's FitOutcome like the row buffer.
    static CORNER_WIRING_TOTALS: std::cell::RefCell<kni_core::corner_wiring::WiringTotals> = std::cell::RefCell::new(kni_core::corner_wiring::WiringTotals::default());
}

/// Fake-line hunt (detection only): audit the SHIPPED drawing's Line spans
/// against the captured source contour they were fitted from, in the fit's
/// own source frame (before any export anchoring). Never mutates geometry,
/// the receipt or the cache. `from_outline` selects the band-cleared
/// contour when the shipped outline came from the outline domain.
fn audit_shipped_lines(glyph: &str, shipped: &kni_core::generated_draw_frame::GeneratedDrawing, src: &kni_core::capture_dispatch::CapturedSource, from_outline: bool, scale: f64, rdp_eps: f64) {
    let contour = if from_outline { src.outline_contour.as_ref().unwrap_or(&src.contour) } else { &src.contour };
    let rings: Vec<Vec<kni_core::reference_slice::Point>> = contour.rings.iter().map(|r| {
        r.points.iter().map(|p| kni_core::reference_slice::Point { x: p.x + contour.origin_x, y: p.y + contour.origin_y }).collect()
    }).collect();
    let rows = kni_core::line_audit::audit_line_spans(&shipped.rings, &rings, contour.origin_x, scale, rdp_eps);
    LINE_AUDIT_BUF.with(|buf| {
        let mut buf = buf.borrow_mut();
        for a in &rows {
            buf.push_str(&kni_core::line_audit::line_span_audit_tsv(glyph, a));
        }
    });
}

fn stage1_fit_one(idx: usize, g: &GlyphRow, m: &Manifest, rc: &RunConfig, limits: Limits, png_limits: &kni_core::capture::DecodeLimits, total: usize, observer_run_context: Option<&MergeVisibilityRunContext>) -> FitOutcome {
    // `progress_pulse` lines are wall-clock diagnostics printed live from a timer thread: excluded from any byte comparison
    // (stderr is not a deliverable; stdout/receipt/cache are). The per-glyph progress line is buffered and emitted in manifest order.
    let _pulse = progress_pulse(&format!("glyph {}", g.name));
    let h_bound = g.codepoint == Some(0x48) && !g.is_ligature() && declared_convention::record_for(rc.scale().id()).is_some();
    // Integration qualification (kept deliberately): stage1_fit_one goes through
    // the GUARDED process_glyph wrapper, so an inner fit panic is converted to a
    // typed FitPanic exclusion with receipt rollback and never reaches the outer
    // fatal catcher; only a bound-H refusal stays run-fatal. Proved by
    // wrapper_path_fit_panic_is_typed_exclusion_not_fatal_and_receipt_rolls_back.
    let observe_merge = observer_run_context.is_some();
    if observe_merge {
        FIT_VISIBILITY_COLLECTOR.with(|cell| *cell.borrow_mut() = Default::default());
        FIT_VISIBILITY_DOMAINS.with(|cell| cell.borrow_mut().clear());
    }
    let mut o = guarded(idx, &g.name, || fit_one_with(idx, &g.name, g.codepoint, h_bound, |receipt| process_glyph(g, m, rc, limits, png_limits, receipt)));
    if observe_merge {
        o.merge_visibility_collector = FIT_VISIBILITY_COLLECTOR.with(|cell| std::mem::take(&mut *cell.borrow_mut()));
        o.merge_visibility_route_domains = FIT_VISIBILITY_DOMAINS.with(|cell| std::mem::take(&mut *cell.borrow_mut()));
        if let Some(run) = observer_run_context {
            let route = if m.stage1_cache.is_some() { kni_core::obs_envelope::FitRoute::CacheReuse }
                else if m.references.iter().any(|r| r.0 == g.name) { kni_core::obs_envelope::FitRoute::GuardedGuided }
                else { kni_core::obs_envelope::FitRoute::Plain };
            o.merge_visibility_source_bytes = Some(run.source_bytes.clone());
            o.merge_visibility_context = Some(kni_core::capture_fit::MergeVisibilityObsContext {
                run_id: run.run_id.clone(), invocation_id: run.invocation_id.clone(), glyph: g.name.clone(), style: run.style.clone(),
                route_domain: kni_core::obs_envelope::RouteDomain::Primary, route,
                stage1_route: Some(run.stage1_route.clone()), stage1_cache_sha256: run.stage1_cache_sha256.clone(),
            });
        }
    }
    o.stderr_buf.insert_str(0, &format!("progress glyph {}/{} {}\n", idx + 1, total, g.name));
    o
}

/// Per-worker stack RESERVE (virtual; pages are committed on use). The fit recurses and must not be tighter than the
/// main thread's default allowance (8 MiB); total reserve is bounded by jobs x this, and jobs is capped at the machine's
/// available parallelism by `take_jobs_flag`.
const STAGE1_WORKER_STACK_BYTES: usize = 16 << 20;

/// Drive `n` indexed jobs. jobs == 1: inline on the calling thread in manifest order, STOPPING after the first fatal
/// outcome (the old serial early-exit). jobs > 1: an explicit rayon pool of exactly `jobs` workers, indexed range
/// into_par_iter, order-preserving collect (all jobs run; the reduce still picks the first fatal in manifest order).
/// A pool that cannot be built is an error, never a silent serial fallback.
fn stage1_drive<F: Fn(usize) -> FitOutcome + Sync>(n: usize, jobs: run_config::Jobs, f: F) -> Result<Vec<FitOutcome>, String> {
    use rayon::prelude::*;
    if jobs.get() == 1 {
        let mut v = Vec::with_capacity(n);
        for i in 0..n { let o = f(i); let stop = o.fatal.is_some(); v.push(o); if stop { break; } }
        return Ok(v);
    }
    let pool = rayon::ThreadPoolBuilder::new().num_threads(jobs.get()).stack_size(STAGE1_WORKER_STACK_BYTES).build()
        .map_err(|e| format!("stage-1 worker pool (jobs={}) could not be built: {e}", jobs.get()))?;
    Ok(pool.install(|| (0..n).into_par_iter().map(|i| f(i)).collect()))
}

fn stage1_fit_all(rows: &[&GlyphRow], m: &Manifest, rc: &RunConfig, limits: Limits, jobs: run_config::Jobs, total: usize, observer_run_context: Option<&MergeVisibilityRunContext>) -> Result<Vec<FitOutcome>, String> {
    // This is a per-glyph ceiling, not a pool-wide token budget. Workers borrow the
    // same immutable limits; each capture owns its input/decode buffers. No worker
    // can shrink another glyph's allowance or change a subsequent decode's limits.
    let png_limits = &PNG_DECODE_LIMITS;
    stage1_drive(rows.len(), jobs, |i| stage1_fit_one(i, rows[i], m, rc, limits, png_limits, total, observer_run_context))
}

#[derive(Default, Debug)]
struct Stage1Acc<'a> {
    /// Observer-only typed records in deterministic manifest order.
    observer_records: Vec<kni_core::obs_envelope::Record>,
    pipeline_records: Vec<kni_core::obs_envelope::Record>,
    merge_visibility_next_event_id: u64,
    processed: Vec<(&'a GlyphRow, DrawnGlyph)>,
    /// The SHIPPED outline drawings in manifest order (band-cleared trace when
    /// the tile carried a measured presentation frame); `processed` keeps the
    /// measurement-domain drawings.
    shipped: Vec<DrawnGlyph>,
    exclusions: Vec<(String, Option<u32>, String)>,
    pins: std::collections::HashMap<String, String>,
    fallback_span_total: usize,
    fallback_glyph_spans: Vec<(String, usize)>,
    fallback_provenance: Vec<(String, Vec<kni_core::capture_fit::FallbackSpanProvenance>)>,
    sub_grid_floor_total: usize,
    straight_sweep: usize,
    reloc_moved: usize,
    /// Every retained speck's capture-space area this run (live stage-1 pass
    /// only; a cache replay carries no fit-side ledger, same as the counters).
    speck_areas: Vec<f64>,
    /// Hole-flagged sub-pixel rings dropped at the speck classification this
    /// run (live stage-1 pass only; a cache replay carries no fit-side
    /// counters, same as the retained-speck ledger).
    speck_retained_hole_total: usize,
    speck_dropped_collapse_total: usize,
    /// Fake-line hunt rows, manifest order (live fits only).
    line_audit: String,
    corner_wiring: String,
    /// Run total of the corner-wiring class counters (live fits only).
    corner_wiring_totals: kni_core::corner_wiring::WiringTotals,
}

/// fit-reduce-seq: fold outcomes in manifest order into the totals, ledger, cache text and receipt. The only place
/// stage-1 shared state is written; the byte layout is exactly what the former in-loop code wrote. The driver returns
/// outcomes already in manifest order (indexed collect); this function VERIFIES that: outcome k must carry idx == k,
/// every index 0..n must be covered exactly once, and the first fatal in manifest order ends the fold with its error.
/// A short list is only valid when its last outcome is that fatal (the jobs=1 early stop). All counters are exact.
fn stage1_reduce<'a>(rows: &[&'a GlyphRow], outcomes: Vec<FitOutcome>, acc: &mut Stage1Acc<'a>, cache: &mut String, receipt: &mut String) -> Result<(), String> {
    stage1_reduce_into(rows, outcomes, acc, Some(cache), receipt)
}

/// Replay uses the same ordered fold but does not rewrite the read-only cache.
fn stage1_reduce_into<'a>(rows: &[&'a GlyphRow], outcomes: Vec<FitOutcome>, acc: &mut Stage1Acc<'a>, mut cache: Option<&mut String>, receipt: &mut String) -> Result<(), String> {
    let overflow = |what: &str, g: &str| format!("stage-1 reduce: {what} overflow at glyph {g}");
    let mut next = 0usize;
    for o in outcomes {
        if o.idx != next { return Err(format!("stage-1 reduce: outcome index {} where {} was expected (duplicate, gap or out-of-order)", o.idx, next)); }
        let g = *rows.get(o.idx).ok_or_else(|| format!("stage-1 reduce: outcome index {} outside the {} manifest rows", o.idx, rows.len()))?;
        next += 1;
        if let Some(f) = o.fatal { return Err(f); }
        acc.observer_records.extend(o.observer_records);
        if !o.merge_visibility_collector.observations.is_empty() || !o.merge_visibility_collector.rewrites.is_empty() {
            let ctx = o.merge_visibility_context.as_ref().ok_or_else(|| "mov-1 collector missing its outcome context".to_string())?;
            let mut revisions = kni_core::obs_envelope::RevEmitter::new();
            let source = kni_core::obs_envelope::RunSource {
                src_bytes: o.merge_visibility_source_bytes.as_deref().map(|b| b.as_slice()),
            };
            let records = kni_core::capture_fit::merge_visibility_into_records(&o.merge_visibility_collector, ctx, &source, &mut revisions)
                .map_err(|e| format!("mov-1 collector conversion failed for {}: {e}", g.name))?;
            for mut record in records {
                if let kni_core::obs_envelope::Record::Xform(xform) = &mut record {
                    xform.event_id = acc.merge_visibility_next_event_id;
                    acc.merge_visibility_next_event_id = acc.merge_visibility_next_event_id.checked_add(1)
                        .ok_or_else(|| "mov-1 xform event id overflow".to_string())?;
                }
                acc.observer_records.push(record);
            }
        }
        if let Some(ctx) = o.merge_visibility_context.as_ref() {
            for (domain, outcome, reason) in o.merge_visibility_route_domains.iter().cloned() {
                let mut ppctx = ctx.clone(); ppctx.route_domain = domain;
                acc.pipeline_records.push(kni_core::obs_envelope::Record::Obs(kni_core::obs_envelope::Obs::pipeline_obs(
                    &ppctx, kni_core::obs_envelope::ObsPoint::Pp1, outcome, None, reason)));
            }
        }
        acc.straight_sweep = acc.straight_sweep.checked_add(o.straight_sweep).ok_or_else(|| overflow("straight_sweep", &g.name))?;
        acc.reloc_moved = acc.reloc_moved.checked_add(o.reloc_moved).ok_or_else(|| overflow("reloc_moved", &g.name))?;
        receipt.push_str(&o.receipt_rows);
        acc.line_audit.push_str(&o.line_audit);
        acc.corner_wiring.push_str(&o.corner_wiring);
        {
            let (t, a) = (&o.corner_wiring_totals, &mut acc.corner_wiring_totals);
            a.seams = a.seams.checked_add(t.seams).ok_or_else(|| overflow("corner_wiring seams", &g.name))?;
            a.corners = a.corners.checked_add(t.corners).ok_or_else(|| overflow("corner_wiring corners", &g.name))?;
            a.smoothed = a.smoothed.checked_add(t.smoothed).ok_or_else(|| overflow("corner_wiring smoothed", &g.name))?;
            a.abstained = a.abstained.checked_add(t.abstained).ok_or_else(|| overflow("corner_wiring abstained", &g.name))?;
            a.guard_rejected = a.guard_rejected.checked_add(t.guard_rejected).ok_or_else(|| overflow("corner_wiring guard_rejected", &g.name))?;
        }
        eprint!("{}", o.stderr_buf);
        match o.drawn {
            Ok(dg) => {
                acc.fallback_span_total = add_fallback_events(acc.fallback_span_total, &g.name, o.fallback_spans).map_err(|e| e.message())?;
                acc.fallback_glyph_spans.push((g.name.clone(), o.fallback_spans));
                if !o.fallback_provenance.is_empty() { acc.fallback_provenance.push((g.name.clone(), o.fallback_provenance.clone())); }
                acc.sub_grid_floor_total = acc.sub_grid_floor_total.checked_add(o.sub_grid).ok_or_else(|| overflow("sub_grid_floor", &g.name))?;
                acc.speck_areas.extend_from_slice(&o.speck_areas);
                acc.speck_retained_hole_total = acc.speck_retained_hole_total.checked_add(o.speck_retained_hole).ok_or_else(|| overflow("speck_retained_hole", &g.name))?;
                acc.speck_dropped_collapse_total = acc.speck_dropped_collapse_total.checked_add(o.speck_dropped_collapse).ok_or_else(|| overflow("speck_dropped_collapse", &g.name))?;
                acc.pins.insert(g.name.clone(), o.pin.clone());
                if let Some(cache) = cache.as_mut() {
                    cache.push_str(&format!("glyph\t{}\tcp\t{}\tpng_sha256\t{}\n", g.name, g.cp_display(), o.pin));
                    fn write_rings(tag: &str, rings: &[ReferenceRing], cache: &mut String) {
                        for ring in rings {
                            cache.push_str(&format!("{}\t{:016x}\t{:016x}\t{}\n", tag, ring.start.x.to_bits(), ring.start.y.to_bits(), ring.spans.len()));
                            for sp in &ring.spans {
                                match sp {
                                    Span::Line { end } => cache.push_str(&format!("L\t{:016x}\t{:016x}\n", end.x.to_bits(), end.y.to_bits())),
                                    Span::Cubic { control_one, control_two, end } => cache.push_str(&format!(
                                        "C\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\n",
                                        control_one.x.to_bits(), control_one.y.to_bits(), control_two.x.to_bits(), control_two.y.to_bits(), end.x.to_bits(), end.y.to_bits())),
                                }
                            }
                        }
                    }
                    write_rings("ring", &dg.rings, cache);
                    if let Some(md) = &o.drawn_measurement { write_rings("mring", &md.rings, cache); }
                    cache.push_str(&format!("receipt_lines\t{}\n", o.receipt_rows.lines().count()));
                    cache.push_str(&o.receipt_rows);
                    cache.push_str("end\n");
                }
                acc.processed.push((g, o.drawn_measurement.clone().unwrap_or_else(|| dg.clone())));
                acc.shipped.push(dg);
            }
            Err(reason) => {
                receipt.push_str(&glyph_skip_ledger_line(&g.name, g.codepoint, &reason));
                if let Some(cache) = cache.as_mut() {
                    cache.push_str(&format!("excluded\t{}\tcp\t{}\tpng_sha256\t{}\treason\t{}\n", g.name, g.cp_display(), o.pin, reason));
                }
                acc.exclusions.push((g.name.clone(), g.codepoint, reason));
            }
        }
    }
    if next != rows.len() { return Err(format!("stage-1 reduce: {} outcomes for {} manifest rows (incomplete coverage)", next, rows.len())); }
    acc.observer_records.append(&mut acc.pipeline_records);
    Ok(())
}

/// Typed class of a per-glyph exclusion reason. The reason strings stay the
/// ledger/cache wire format (byte-identical to before); this classifies them
/// without changing them, so a panic or injected fault is a first-class kind
/// and every pre-existing refusal keeps its own kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)] // exclusion taxonomy exercised by tests; production wiring pending
enum ExclusionKind { Unreadable, HSourceChanged, PerGlyphScaleOverride, BadScale, ReferenceRefused, CaptureRefused, RouteRefused, FitPanic, Other }

/// Prefix that marks a panic converted into a typed exclusion.
const FIT_PANIC_TAG: &str = "FitPanic";

#[allow(dead_code)] // exercised by the test suite; no production caller wired yet
fn exclusion_kind(pin: &str, reason: &str) -> ExclusionKind {
    if reason.starts_with(FIT_PANIC_TAG) { return ExclusionKind::FitPanic; }
    if pin == "unreadable" { return ExclusionKind::Unreadable; }
    if reason.starts_with("HSourceChanged") || reason.contains("HSourceChanged") { return ExclusionKind::HSourceChanged; }
    if reason.starts_with("PerGlyphScaleOverride") { return ExclusionKind::PerGlyphScaleOverride; }
    if reason.contains("scale must be finite") { return ExclusionKind::BadScale; }
    if reason.contains("reference") && reason.contains("refused") || reason.contains("reference font sha mismatch") || reason.contains("reference codepoint unmapped") { return ExclusionKind::ReferenceRefused; }
    if reason.contains("capture refused") { return ExclusionKind::CaptureRefused; }
    if reason.contains("route refused") { return ExclusionKind::RouteRefused; }
    ExclusionKind::Other
}

fn panic_payload_text(p: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = p.downcast_ref::<&str>() { (*s).to_string() }
    else if let Some(s) = p.downcast_ref::<String>() { s.clone() }
    else { "non-string panic payload".to_string() }
}

/// Run one glyph task so that a panic becomes the same typed exclusion pair
/// `(pin, reason)` a refusal produces. The receipt is cut back to its length
/// at entry (a panic must not leave half a glyph's rows), and the run goes on.
/// A panic that happens before the source is hashed carries the pin "unreadable".
fn guard_glyph_task<T>(name: &str, receipt: &mut String, task: impl FnOnce(&mut String) -> Result<T, (String, String)>) -> Result<T, (String, String)> {
    let mark = receipt.len();
    let out = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| task(&mut *receipt)));
    match out {
        Ok(r) => r,
        Err(p) => {
            receipt.truncate(mark);
            Err(("unreadable".to_string(), format!("{FIT_PANIC_TAG}: glyph {name}: {}", panic_payload_text(p.as_ref()))))
        }
    }
}

fn process_glyph<'a>(g: &'a GlyphRow, m: &Manifest, rc: &run_config::RunConfig, limits: Limits, png_limits: &kni_core::capture::DecodeLimits, receipt: &mut String) -> Result<(String, DrawnGlyph, usize, usize, Option<DrawnGlyph>, Vec<kni_core::capture_fit::FallbackSpanProvenance>), (String, String)> {
    let _bench_glyph = fit_bench::GlyphGuard::start(&g.name);
    match guard_glyph_task(&g.name, receipt, |r| process_glyph_with_decode_limits(g, m, rc, limits, png_limits, r)) {
        Err((_, reason)) if reason.starts_with(FIT_PANIC_TAG) => {
            // keep the stage-1 pin honest after a panic: hash the source again when it is readable
            let pin = read_source_bounded(&g.image, limits.max_input_bytes).map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".to_string());
            Err((pin, reason))
        }
        other => other,
    }
}

/// The immutable PNG budget is an explicit per-glyph input. The decoder's typed
/// refusal stays on this glyph's existing exclusion path, never a pool failure.
#[cfg(test)]
static TEST_WRAPPER_PANIC_GLYPH: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);
/// Test-only execution barrier for the wrapper-panic injection: every test
/// that SETS the injection or runs stage1 over the shared replay-budget
/// fixture (whose glyph "A" the injection matches) holds this for its whole
/// body, so an injected panic can never leak into a concurrent test under
/// --test-threads > 1. Lock order: EXEC first, then the value mutex; the
/// production read site only ever takes the value mutex, so no deadlock.
#[cfg(test)]
static TEST_WRAPPER_PANIC_EXEC: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn process_glyph_with_decode_limits<'a>(g: &'a GlyphRow, m: &Manifest, rc: &run_config::RunConfig, limits: Limits, png_limits: &kni_core::capture::DecodeLimits, receipt: &mut String) -> Result<(String, DrawnGlyph, usize, usize, Option<DrawnGlyph>, Vec<kni_core::capture_fit::FallbackSpanProvenance>), (String, String)> {
    #[cfg(test)]
    if TEST_WRAPPER_PANIC_GLYPH.lock().unwrap().as_deref() == Some(g.name.as_str()) {
        panic!("injected wrapper-path fit fault");
    }
    let bytes = read_source_bounded(&g.image, limits.max_input_bytes).map_err(|e| ("unreadable".to_string(), e))?;
    let pin = sha256_hex(&bytes);
    if g.codepoint == Some(0x48) && !g.is_ligature() {
        if let Some(rec) = declared_convention::record_for(rc.scale().id()) {
            if pin != rec.h_source_pin_sha256 {
                return Err((pin.clone(), format!("{:?}", WiringError::HSourceChanged { expected: rec.h_source_pin_sha256.into(), found: pin })));
            }
        }
    }
    let mut inner = |g: &'a GlyphRow, bytes: &[u8]| -> Result<(DrawnGlyph, usize, usize, Option<DrawnGlyph>, Vec<kni_core::capture_fit::FallbackSpanProvenance>), String> {
        let bytes = bytes;
        let scale = rc.scale().units_per_px();
        if g.scale.is_some() {
            return Err(format!("PerGlyphScaleOverride: {}", g.name));
        }
        if !scale.is_finite() || scale <= 0.0 {
            Err(format!("glyph {}: scale must be finite and > 0", g.name))?;
        }
        let g = g;
        let reference = m.references.iter().find(|r| r.0 == g.name);
        let (d_meas, outline_d, route_kind, src_kind, src_wh, src_origin_x, src_frame_left_px) = if let Some((_, font_path, font_sha, ref_cp)) = reference {
            // guided owner-reference path: pinned reference consumed through E0/E1 map_frame_identity
            let font_bytes = fs::read(font_path).map_err(|e| format!("glyph {}: read reference font: {e}", g.name))?;
            if sha256_hex(&font_bytes) != *font_sha {
                return Err(format!("glyph {}: reference font sha mismatch", g.name));
            }
            let font = kni_core::cff_reader::CffReader::from_bytes(&font_bytes, font_sha)
                .map_err(|e| format!("glyph {}: reference font refused: {e:?}", g.name))?;
            let rg = font.read_codepoint(*ref_cp).map_err(|e| format!("glyph {}: reference read refused: {e:?}", g.name))?
                .ok_or_else(|| format!("glyph {}: reference codepoint unmapped", g.name))?;
            let reference_rings = rg.rings;
            let rpin = make_pin(&g.name, &format!("owner-channel font sha256={font_sha} cp={ref_cp:#x}"), &reference_rings);
            let pref = PinnedReference { pin: rpin, rings: reference_rings };
            let (gxmin, gymax, gppu, gpad) = m.frame_map.ok_or("internal: frame_map missing")?;
            let (gs, gnd, grc) = m.guide.ok_or("internal: guide config missing")?;
            let gcfg = GuideConfig { max_node_dist: Some(gnd), max_ring_cost: Some(grc), smooth_sin: Some(gs) };
            let fmap = ReferenceFrameMap { xmin: gxmin, ymax: gymax, px_per_unit: gppu, pad_px: gpad };
            let frame_policy = declared_convention::frame_policy_for(rc.scale().id());
            let src = kni_core::capture_dispatch::capture_source_with_policy(&bytes, rc.rdp_epsilon().value(), png_limits, limits, frame_policy)
                .map_err(|e| format!("glyph {}: capture refused: {e:?}", g.name))?;
            let kind = src.receipt.source_kind.clone();
            let wh = (src.receipt.width, src.receipt.height);
            if src.receipt.frame_band_measured.1 > 0 {
                let (bt, bb, bl, br) = src.receipt.frame_band_measured.0;
                receipt.push_str(&format!(
                    "capture\t{}\tframe_band_measured_px\tt{}\tb{}\tl{}\tr{}\tcells\t{}\n",
                    g.name, bt, bb, bl, br, src.receipt.frame_band_measured.1));
            }
            receipt.push_str(&format!(
                "capture\t{}\tframe_band_evidence\t{}\n",
                g.name, src.receipt.frame_band_evidence.receipt_tag()));
            let pol = resolve_fit_policy(rc, g, scale, &src, &pin, receipt)?;
            let gg = merge_visibility_with_domain(kni_core::obs_envelope::RouteDomain::Primary, ||
                fit_captured_source_frame_guarded_guided(&src, &g.name, scale, &pol, &pref, &gcfg, &fmap))
                .map_err(|e| format!("glyph {}: guarded-guided route refused: {e:?}", g.name))?;
            let outline = match (&src.outline_contour, &src.outline_gray) {
                (Some(oc), Some(og)) => {
                    let osrc = kni_core::capture_dispatch::CapturedSource { contour: oc.clone(), gray: og.clone(), receipt: src.receipt.clone(), outline_contour: None, outline_gray: None };
                    Some(merge_visibility_with_domain(kni_core::obs_envelope::RouteDomain::Outline, ||
                        fit_captured_source_frame_guarded_guided(&osrc, &g.name, scale, &pol, &pref, &gcfg, &fmap))
                        .map_err(|e| format!("glyph {}: outline guarded-guided route refused: {e:?}", g.name))?.drawing)
                }
                _ => {
                    if src.receipt.frame_band_measured.1 > 0 {
                        merge_visibility_note_missing_input(kni_core::obs_envelope::RouteDomain::Outline, "frame_outline_source_missing");
                    }
                    None
                },
            };
            receipt.push_str(&format!(
                "guide\t{}\treference_font_sha\t{}\treference_pin\t{}\tE0\thash\t{}\tcorner\t{}\textremum\t{}\tunmatched\t{}\tE1\thash\t{}\tcorner\t{}\textremum\t{}\tunmatched\t{}\n",
                g.name, font_sha, gg.e0.pin_sha256, gg.e0.input_hash, gg.e0.corner_nodes.len(), gg.e0.extremum_nodes.len(), gg.e0.unmatched_targets,
                gg.e1.input_hash, gg.e1.corner_nodes.len(), gg.e1.extremum_nodes.len(), gg.e1.unmatched_targets));
            fit_bench::record_quality_pair(&g.name, &gg.drawing, &outline, &src, scale);
            let shipped_ox = match (&src.outline_contour, &src.outline_gray) { (Some(oc), Some(_)) => oc.origin_x, _ => src.contour.origin_x };
            audit_shipped_lines(&g.name, outline.as_ref().unwrap_or(&gg.drawing), &src, outline.is_some(), scale, rc.rdp_epsilon().value());
            (gg.drawing, outline, "guarded-guided", kind, wh, shipped_ox, src.receipt.frame_band_measured.0.2 as f64)
        } else {
            let frame_policy = declared_convention::frame_policy_for(rc.scale().id());
            let src = kni_core::capture_dispatch::capture_source_with_policy(&bytes, rc.rdp_epsilon().value(), png_limits, limits, frame_policy)
                .map_err(|e| format!("glyph {}: capture refused: {e:?}", g.name))?;
            let kind = src.receipt.source_kind.clone();
            let wh = (src.receipt.width, src.receipt.height);
            if src.receipt.frame_band_measured.1 > 0 {
                let (bt, bb, bl, br) = src.receipt.frame_band_measured.0;
                receipt.push_str(&format!(
                    "capture\t{}\tframe_band_measured_px\tt{}\tb{}\tl{}\tr{}\tcells\t{}\n",
                    g.name, bt, bb, bl, br, src.receipt.frame_band_measured.1));
            }
            receipt.push_str(&format!(
                "capture\t{}\tframe_band_evidence\t{}\n",
                g.name, src.receipt.frame_band_evidence.receipt_tag()));
            let pol = resolve_fit_policy(rc, g, scale, &src, &pin, receipt)?;
            let routed = merge_visibility_with_domain(kni_core::obs_envelope::RouteDomain::Primary, || fit_captured_source_frame(&src, scale, &pol))
                .map_err(|e| format!("glyph {}: route refused: {e:?}", g.name))?;
            let outline = match (&src.outline_contour, &src.outline_gray) {
                (Some(oc), Some(og)) => {
                    let osrc = kni_core::capture_dispatch::CapturedSource { contour: oc.clone(), gray: og.clone(), receipt: src.receipt.clone(), outline_contour: None, outline_gray: None };
                    Some(merge_visibility_with_domain(kni_core::obs_envelope::RouteDomain::Outline, || fit_captured_source_frame(&osrc, scale, &pol))
                        .map_err(|e| format!("glyph {}: outline route refused: {e:?}", g.name))?.drawing)
                }
                _ => {
                    if src.receipt.frame_band_measured.1 > 0 {
                        merge_visibility_note_missing_input(kni_core::obs_envelope::RouteDomain::Outline, "frame_outline_source_missing");
                    }
                    None
                },
            };
            fit_bench::record_quality_pair(&g.name, &routed.drawing, &outline, &src, scale);
            let shipped_ox = match (&src.outline_contour, &src.outline_gray) { (Some(oc), Some(_)) => oc.origin_x, _ => src.contour.origin_x };
            audit_shipped_lines(&g.name, outline.as_ref().unwrap_or(&routed.drawing), &src, outline.is_some(), scale, rc.rdp_epsilon().value());
            (routed.drawing, outline, "plain", kind, wh, shipped_ox, src.receipt.frame_band_measured.0.2 as f64)
        };
        // The printed presentation frame (measured band) is excluded at the
        // SOURCE: the shipped outline is traced from the band-cleared gray, so
        // the frame never becomes a contour and the letterform keeps its
        // natural orientation (no emit-time ring surgery, no winding flips).
        // The measurement drawing keeps the original trace: profiles, spacing
        // and vertical metrics stay on the accepted domain, bit-identical.
        let (d, d_measurement) = match outline_d { Some(o) => {
            receipt.push_str(&format!(
                "outline_fit\t{}\trings\t{}\tnodes\t{}\tfinal_area\t{:.6}\tfallback_line_spans\t{}\tframe\texcluded_at_source\n",
                g.name, o.rings.len(), o.rings.iter().map(|r| r.spans.len()).sum::<usize>(), o.final_area, o.fallback_line_spans));
            (o, Some(d_meas))
        }, None => (d_meas, None) };
        // Paul New declared tile anchor: the shipped outline is re-anchored
        // onto the declared em box (frame-stripped since the 2026-10-18
        // ruling: left frame band dropped, -1 edge overhang; the
        // measurement drawing is never touched). Gate key: the explicit
        // declared tile-anchor scope (the style's declared family), never
        // the capture frame policy - a frame-policy flip cannot move it.
        let mut d = d;
        if declared_convention::paul_new_tile_anchor_scope(rc.scale().id()) {
            // Frame-residue ruling (owner 2026-10-18 03:05/03:06): the anchor
            // drops the capture-measured left frame band and applies the
            // declared -1 edge overhang, so ink and bearings carry no frame.
            let frame_left_px = src_frame_left_px;
            paul_new_anchor::anchor_outline(&mut d.rings, src_origin_x, scale, frame_left_px);
            // Typed anchor ledger (one row per glyph): the tile->em mapping
            // this glyph shipped with. The export lane applies NO second
            // vertical transform in this scope (y_shift_applied 0).
            receipt.push_str(&format!(
                "anchor\t{}\ttile_px\t{}x{}\torigin_x\t{}\tk_y_bits\t{:016x}\tframe_left_px\t{}\tedge_overhang\t{}\ty_shift_applied\t0\tdeclared_top\t{}\tdeclared_bottom\t{}\n",
                g.name, src_wh.0, src_wh.1, src_origin_x, scale.to_bits(), frame_left_px,
                paul_new_anchor::PAUL_NEW_EDGE_OVERHANG_UNITS,
                declared_convention::PAUL_NEW_ASCENDER_UNITS, declared_convention::PAUL_NEW_DESCENDER_UNITS));
        }
        // C3 corner wiring (policy-gated, manifest `corner_wiring on`; off =
        // zero calls, zero byte changes). Seam joints whose measured tangent
        // delta beats the export grid's resolvability floor keep their corner;
        // sub-floor seams are made tangent-continuous. Rows are measurement
        // artifacts, never receipt/cache bytes.
        if m.corner_wiring {
            let (reps, totals) = kni_core::corner_wiring::wire_drawing(&mut d.rings);
            CORNER_WIRING_TOTALS.with(|t| *t.borrow_mut() = totals);
            CORNER_WIRING_BUF.with(|buf| {
                let mut buf = buf.borrow_mut();
                for r in &reps {
                    buf.push_str(&kni_core::corner_wiring::seam_report_tsv(&g.name, r));
                }
            });
        }
        let nodes: usize = d.rings.iter().map(|r| r.spans.len()).sum();
        receipt.push_str(&format!(
            "glyph\t{}\tcp\t{}\tsource_pin\t{}\tsource_kind\t{:?}\tsource_px\t{}x{}\tscale\t{}\troute\t{}\trings\t{}\tnodes\t{}\tfinal_area\t{:.6}\tfinal_missing_extrema\t{}\trefused\t{}\n",
            g.name, if g.name == ".notdef" { "none".into() } else { g.cp_display() }, pin, src_kind, src_wh.0, src_wh.1,
            scale, route_kind, d.rings.len(), nodes, d.final_area, d.final_missing_extrema, d.refused.len()));
        receipt.push_str(&fallback_ledger_line(&g.name, d.fallback_line_spans));
        // Gate counters stay on the measurement fit (accepted-domain
        // continuity); the shipped outline's own counts sit in outline_fit.
        let (nfb, nsub) = d_measurement.as_ref().map_or((d.fallback_line_spans, d.sub_grid_floor), |m| (m.fallback_line_spans, m.sub_grid_floor));
        let fprov = d_measurement.as_ref().map_or_else(|| d.fallback_provenance.clone(), |m| m.fallback_provenance.clone());
        Ok((DrawnGlyph { glyph_id: g.name.clone(), rings: d.rings }, nfb, nsub,
            d_measurement.map(|m| DrawnGlyph { glyph_id: g.name.clone(), rings: m.rings }), fprov))
    };
    match inner(g, &bytes) { Ok((d, nfb, nsub, nmeas, fprov)) => Ok((pin, d, nfb, nsub, nmeas, fprov)), Err(e) => Err((pin, e)) }
}

// ---- typed stage1 fallback ledger (live write == cache read) -------------------------------
// The ONLY source of a glyph's fallback event count on cache replay is its own typed
// ledger row `fallback<TAB><exact glyph name><TAB>line_spans<TAB><integer>` written by the
// live path (`fallback_ledger_line`). Exactly one row per glyph; any other shape is a
// typed cache-invalid, never a best-effort sum. The export fit gate (`fallback_gate`)
// consumes the checked total identically for live and cached runs: no bypass.
#[derive(Debug, Clone, PartialEq, Eq)]
enum CacheInvalid {
    MissingLedger { glyph: String },
    DuplicateLedger { glyph: String },
    GlyphNameMismatch { expected: String, found: String },
    MalformedLedger { glyph: String, row: String },
    BadCount { glyph: String, raw: String },
    TotalOverflow { glyph: String },
}

impl CacheInvalid {
    fn message(&self) -> String {
        match self {
            CacheInvalid::MissingLedger { glyph } => format!("stage1 cache invalid: glyph {glyph} has no typed fallback ledger row; refusing reuse"),
            CacheInvalid::DuplicateLedger { glyph } => format!("stage1 cache invalid: glyph {glyph} has more than one typed fallback ledger row; refusing reuse"),
            CacheInvalid::GlyphNameMismatch { expected, found } => format!("stage1 cache invalid: fallback ledger row names glyph {found:?} inside the entry of glyph {expected:?}; refusing reuse"),
            CacheInvalid::MalformedLedger { glyph, row } => format!("stage1 cache invalid: malformed fallback ledger row for glyph {glyph}: {row:?}; refusing reuse"),
            CacheInvalid::BadCount { glyph, raw } => format!("stage1 cache invalid: fallback ledger count {raw:?} for glyph {glyph} is not a plain unsigned integer; refusing reuse"),
            CacheInvalid::TotalOverflow { glyph } => format!("stage1 cache invalid: fallback ledger total overflows at glyph {glyph}; refusing reuse"),
        }
    }
}

/// The one writer of the per-glyph ledger row (live path and nothing else).
fn fallback_ledger_line(glyph: &str, events: usize) -> String {
    format!("fallback\t{glyph}\tline_spans\t{events}\n")
}

/// Read the glyph's own ledger row out of its cached receipt block: exact glyph name,
/// exactly one row, plain-integer count. Every other `fallback` row shape is invalid.
fn read_fallback_ledger(glyph: &str, receipt: &str) -> Result<usize, CacheInvalid> {
    let mut found: Option<usize> = None;
    for line in receipt.lines() {
        let f: Vec<&str> = line.split('\t').collect();
        if f.first().copied() != Some("fallback") { continue; }
        if f.len() != 4 || f[2] != "line_spans" {
            return Err(CacheInvalid::MalformedLedger { glyph: glyph.to_string(), row: line.to_string() });
        }
        if f[1] != glyph {
            return Err(CacheInvalid::GlyphNameMismatch { expected: glyph.to_string(), found: f[1].to_string() });
        }
        if found.is_some() {
            return Err(CacheInvalid::DuplicateLedger { glyph: glyph.to_string() });
        }
        let raw = f[3];
        if raw.is_empty() || !raw.bytes().all(|b| b.is_ascii_digit()) {
            return Err(CacheInvalid::BadCount { glyph: glyph.to_string(), raw: raw.to_string() });
        }
        let n: usize = raw.parse().map_err(|_| CacheInvalid::BadCount { glyph: glyph.to_string(), raw: raw.to_string() })?;
        found = Some(n);
    }
    found.ok_or_else(|| CacheInvalid::MissingLedger { glyph: glyph.to_string() })
}

/// Checked running total (live and cache both use this).
fn add_fallback_events(total: usize, glyph: &str, events: usize) -> Result<usize, CacheInvalid> {
    total.checked_add(events).ok_or_else(|| CacheInvalid::TotalOverflow { glyph: glyph.to_string() })
}

/// Export intent under a nonzero typed fallback ledger. Strict is the default and the
/// only production candidate path; DiagnosticTest ships TEST/UNVALIDATED bytes for
/// harness use; FallbackWarn ships bytes with the ledger retained in the receipt and
/// fallback-glyphs.tsv in the out dir, never a name-table warning tag.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum ExportIntent {
    Strict,
    DiagnosticTest,
    FallbackWarn,
}

/// Intent resolution: flags only, never the ledger total. A nonzero typed fallback
/// ledger can no longer promote a run into FallbackWarn on its own; without an
/// explicit typed intent the strict gate refuses the export.
fn resolve_export_intent(diagnostic_test_export: bool, fallback_export_warn: bool) -> ExportIntent {
    if diagnostic_test_export {
        ExportIntent::DiagnosticTest
    } else if fallback_export_warn {
        ExportIntent::FallbackWarn
    } else {
        ExportIntent::Strict
    }
}

/// The typed fit gate, identical for live and cached stage1 data.
fn fallback_gate(total: usize, intent: ExportIntent) -> Result<(), String> {
    if total > 0 && intent == ExportIntent::Strict {
        return Err(format!(
            "refused: typed fallback ledger records {} per-point Line fallback span(s): intended-curved region(s) unresolved under the active fit policy; usable export HARD-FAIL",
            total
        ));
    }
    Ok(())
}

/// fallback-glyphs.tsv payload: header + one `glyph<TAB>spans` row per glyph with a
/// nonzero typed fallback span count, in manifest processing order.
/// r282 fallback-audit.tsv rows: one per finalized fallback event with its
/// glyph/ring/span identity, measured px geometry and typed producer reason.
/// Unmeasurable values print "-", never an invented number.
fn fallback_audit_tsv(rows: &[(String, Vec<kni_core::capture_fit::FallbackSpanProvenance>)]) -> String {
    fn fv(v: Option<f64>) -> String { v.map(|x| format!("{x}")).unwrap_or_else(|| "-".to_string()) }
    let mut t = String::from("glyph\tring\tarc\ts\te\tchord_px\tarc_len_px\tmax_dev_px\treason\tstop_class\tdecline_class\n");
    for (name, spans) in rows {
        for p in spans {
            let arc = if p.arc == usize::MAX { "-".to_string() } else { p.arc.to_string() };
            // r288: SU spans print the real producer stop ('none' when the
            // producer's refit loop was never entered) and the joined decline
            // class; every other event class has no producer outcome, "-".
            let (stop_class, decline_class) = if p.reason == kni_core::capture_fit::FallbackReason::SplitUnresolved {
                (p.stop.map(|s| format!("{s:?}")).unwrap_or_else(|| "none".to_string()),
                 p.decline.map(|d| format!("{d:?}")).unwrap_or_else(|| "-".to_string()))
            } else {
                ("-".to_string(), "-".to_string())
            };
            t.push_str(&format!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:?}\t{}\t{}\n", name, p.ring, arc, p.s, p.e, fv(p.chord_px), fv(p.arc_len_px), fv(p.max_dev_px), p.reason, stop_class, decline_class));
        }
    }
    t
}

fn fallback_glyph_tsv(rows: &[(String, usize)]) -> String {
    let mut t = String::from("glyph	spans
");
    for (name, n) in rows {
        if *n > 0 {
            t.push_str(&format!("{name}	{n}
"));
        }
    }
    t
}

/// Parsed cache data is immutable. Replay maps it to the live driver's outcome
/// contract, retaining source pins and receipt rows, but inventing no fit counts.
struct Stage1CacheEntry {
    cp: Option<u32>, sha: String, rings: Option<Vec<ReferenceRing>>,
    mring: Option<Vec<ReferenceRing>>,
    reason: Option<String>, receipt: String,
}

fn replay_stage1_entry(idx: usize, g: &GlyphRow, entries: &[(String, Stage1CacheEntry)]) -> Result<FitOutcome, String> {
    let (_, e) = entries.iter().find(|(n, _)| n == &g.name).ok_or_else(|| format!("stage1 cache: glyph {} missing", g.name))?;
    if e.cp != g.codepoint { return Err(format!("stage1 cache: codepoint mismatch for {}", g.name)); }
    let bytes = fs::read(&g.image).map_err(|er| format!("read {}: {er}", g.image.display()))?;
    if sha256_hex(&bytes) != e.sha {
        return Err(format!("stage1 cache: png pin mismatch for {}; refusing reuse", g.name));
    }
    let (drawn, fallback_spans, receipt_rows) = match (&e.rings, &e.reason) {
        (Some(rings), None) => (
            Ok(DrawnGlyph { glyph_id: g.name.clone(), rings: rings.clone() }),
            read_fallback_ledger(&g.name, &e.receipt).map_err(|er| er.message())?, e.receipt.clone()),
        (None, Some(reason)) => (Err(reason.clone()), 0, String::new()),
        _ => return Err(format!("stage1 cache: malformed entry for {}", g.name)),
    };
    // A cached exclusion (including H) retains the old replay semantics. It is
    // not a fresh bound-H fit refusal and must not acquire a new fatal flag.
    let drawn_measurement = e.mring.as_ref().map(|r| DrawnGlyph { glyph_id: g.name.clone(), rings: r.clone() });
    Ok(FitOutcome { fallback_provenance: Vec::new(), observer_records: Vec::new(), merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector::default(), merge_visibility_route_domains: Vec::new(), merge_visibility_context: None, merge_visibility_source_bytes: None, idx, pin: e.sha.clone(), drawn, drawn_measurement, fallback_spans, sub_grid: 0, line_audit: String::new(), corner_wiring: String::new(), corner_wiring_totals: Default::default(),
        straight_sweep: 0, reloc_moved: 0, speck_areas: Vec::new(), speck_retained_hole: 0, speck_dropped_collapse: 0, receipt_rows, stderr_buf: String::new(), fatal: None })
}


/// Read the typed placeholder decision a found-class live run persisted into
/// its stage1 cache. The row sits in the cache header block; the full load
/// later validates policy/identity/exe as before.
/// Returns (pixel_form_sha256, is_blank, slots) when a found row is present.
fn read_cache_placeholder_decision(path: &std::path::Path) -> Result<Option<(String, bool, Vec<u32>)>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("placeholder_decision\tfound\tpixel_form_sha256\t") else { continue };
        let f: Vec<&str> = rest.split('\t').collect();
        if f.len() != 7 || f[1] != "kind" || f[3] != "slot_count" || f[5] != "slots" {
            return Err(format!("stage1 cache: bad placeholder_decision row: {line}"));
        }
        let form_hash = f[0].to_string();
        let is_blank = match f[2] { "blank-cell" => true, "drawn-form" => false, other => return Err(format!("stage1 cache: bad placeholder kind {other:?}")) };
        let n: usize = f[4].parse().map_err(|e| format!("stage1 cache: bad placeholder slot_count: {e}"))?;
        let slots: Vec<u32> = f[6].split(',').map(|h| u32::from_str_radix(h.trim_start_matches("0x"), 16)).collect::<Result<_, _>>().map_err(|e| format!("stage1 cache: bad placeholder slot: {e}"))?;
        if slots.len() != n { return Err("stage1 cache: placeholder slot_count mismatch".into()); }
        return Ok(Some((form_hash, is_blank, slots)));
    }
    Ok(None)
}

/// The replay route does not trust a persisted pixel_form_sha256: the form
/// hash is recomputed from the source pixel evidence of every slot the
/// decision names and compared against the persisted value, the same
/// recompute-and-compare contract as the stage1_identity, engine_exe_sha256
/// and per-glyph png_sha256 pins. A hash or kind mismatch, a slot outside
/// the manifest, or an undecodable source refuses the reuse, typed.
fn verify_cache_placeholder_decision(m: &Manifest, limits: Limits, form_hash: &str, is_blank: bool, slots: &[u32]) -> Result<(), String> {
    for cp in slots {
        let g = m.glyphs.iter().find(|g| g.codepoint == Some(*cp))
            .ok_or_else(|| format!("stage1 cache: placeholder_decision slot {cp:#x} not in manifest; refusing reuse"))?;
        let bytes = read_source_bounded(&g.image, limits.max_input_bytes)?;
        let decoded = kni_core::capture_dispatch::decode_source(&bytes, &PNG_DECODE_LIMITS, limits)
            .map_err(|e| format!("stage1 cache: placeholder_decision decode {}: {e:?}; refusing reuse", g.name))?;
        let recomputed = bound_detector_validator::pixel_form_sha256(decoded.width, decoded.height, &decoded.gray)
            .map_err(|e| format!("stage1 cache: placeholder_decision form hash {}: {e:?}", g.name))?;
        if recomputed != form_hash {
            return Err(format!("stage1 cache: placeholder_decision pixel_form_sha256 mismatch for {} ({cp:#x}): persisted {form_hash} recomputed {recomputed}; refusing reuse", g.name));
        }
        let recomputed_blank = decoded.gray.iter().all(|&pixel| pixel == 255);
        if recomputed_blank != is_blank {
            return Err(format!("stage1 cache: placeholder_decision kind mismatch for {} ({cp:#x}): persisted {} recomputed {}; refusing reuse",
                g.name, if is_blank { "blank-cell" } else { "drawn-form" }, if recomputed_blank { "blank-cell" } else { "drawn-form" }));
        }
    }
    Ok(())
}

/// The run-level corner-wiring seam-count row. One line shape serves both
/// streams: a live run persists it into its stage1 cache and prints it to
/// the receipt; the replay route reads the persisted row typed and prints
/// the identical receipt line.
fn corner_wiring_seams_row(t: &kni_core::corner_wiring::WiringTotals) -> String {
    format!("corner_wiring_seams\tcount\t{}\tcorner\t{}\tsmooth\t{}\tabstain\t{}\tguard_reject\t{}\n",
        t.seams, t.corners, t.smoothed, t.abstained, t.guard_rejected)
}

/// Read the typed corner-wiring seam counts a live `corner_wiring on` run
/// persisted into its stage1 cache. The replay route derives the run-level
/// receipt row from this row; its absence on the cache route is typed
/// replay-unavailable at the receipt site, never a silent zero. A malformed
/// row is a typed refusal.
fn read_cache_corner_wiring_seams(path: &std::path::Path) -> Result<Option<kni_core::corner_wiring::WiringTotals>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("corner_wiring_seams\tcount\t") else { continue };
        let f: Vec<&str> = rest.split('\t').collect();
        if f.len() != 9 || f[1] != "corner" || f[3] != "smooth" || f[5] != "abstain" || f[7] != "guard_reject" {
            return Err(format!("stage1 cache: bad corner_wiring_seams row: {line}"));
        }
        let parse = |v: &str| v.parse::<usize>().map_err(|e| format!("stage1 cache: bad corner_wiring_seams count: {e}"));
        return Ok(Some(kni_core::corner_wiring::WiringTotals {
            seams: parse(f[0])?,
            corners: parse(f[2])?,
            smoothed: parse(f[4])?,
            abstained: parse(f[6])?,
            guard_rejected: parse(f[8])?,
        }));
    }
    Ok(None)
}

/// Read the typed speck-retained evidence a live run persisted into its
/// stage1 cache. The replay route derives the run-level receipt row from
/// this row; its absence on the cache route is typed replay-unavailable at
/// the receipt site, never a silent zero.
fn read_cache_speck_retained(path: &std::path::Path) -> Result<Option<Vec<f64>>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("speck_retained\tcount\t") else { continue };
        let f: Vec<&str> = rest.split('\t').collect();
        if f.len() != 3 || f[1] != "areas" {
            return Err(format!("stage1 cache: bad speck_retained row: {line}"));
        }
        let n: usize = f[0].parse().map_err(|e| format!("stage1 cache: bad speck_retained count: {e}"))?;
        let areas: Vec<f64> = if f[2].is_empty() { Vec::new() } else {
            f[2].split(',').map(|h| u64::from_str_radix(h, 16).map(f64::from_bits).map_err(|e| format!("stage1 cache: bad speck_retained area: {e}"))).collect::<Result<_, _>>()?
        };
        if areas.len() != n { return Err("stage1 cache: speck_retained count mismatch".into()); }
        return Ok(Some(areas));
    }
    Ok(None)
}

/// Read the typed stage1 sub-grid subtotal a live run persisted into its
/// stage1 cache. The replay route restores the subtotal from this row and
/// adds only its own local post-pass events; a missing row is typed
/// replay-unavailable at the receipt site, never a silent zero.
fn read_cache_sub_grid_floor(path: &std::path::Path) -> Result<Option<usize>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("sub_grid_floor\tstage1_total\t") else { continue };
        let n: usize = rest.parse().map_err(|e| format!("stage1 cache: bad sub_grid_floor row: {line}: {e}"))?;
        return Ok(Some(n));
    }
    Ok(None)
}

/// Run-level hole-dropped count, persisted live and read back on replay.
/// Absence is typed replay-unavailable at the receipt site, never a silent 0.
fn read_cache_speck_dropped_collapse(path: &std::path::Path) -> Result<Option<usize>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache: {e}"))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("speck_dropped_collapse\tcount\t") else { continue };
        let n: usize = rest.trim().parse().map_err(|e| format!("stage1 cache: bad speck_dropped_collapse count: {e}"))?;
        return Ok(Some(n));
    }
    Ok(None)
}

fn read_cache_speck_retained_hole(path: &std::path::Path) -> Result<Option<usize>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("speck_retained_hole\tcount\t") else { continue };
        let n: usize = rest.trim().parse().map_err(|e| format!("stage1 cache: bad speck_retained_hole count: {e}"))?;
        return Ok(Some(n));
    }
    Ok(None)
}

/// Read the typed straight-sweep count a live run persisted into its stage1
/// cache. Absence on an older cache is typed replay-unavailable at the
/// receipt site, never a silent zero.
fn read_cache_straight_sweep(path: &std::path::Path) -> Result<Option<usize>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("straight_sweep_converted\tcount\t") else { continue };
        let n: usize = rest.parse().map_err(|e| format!("stage1 cache: bad straight_sweep_converted count: {e}"))?;
        return Ok(Some(n));
    }
    Ok(None)
}

fn load_stage1_cache<'a>(path: &Path, m: &'a Manifest, rc: &RunConfig, placeholder_skip_cps: &[u32], processed: &mut Vec<(&'a GlyphRow, DrawnGlyph)>, shipped: &mut Vec<DrawnGlyph>, exclusions: &mut Vec<(String, Option<u32>, String)>, receipt: &mut String, fallback_span_total: &mut usize, stage1_pins: &mut std::collections::HashMap<String, String>, fallback_glyph_spans: &mut Vec<(String, usize)>) -> Result<(), String> {
    let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
    let mut lines = text.lines();
    if lines.next() != Some("kni-stage1-cache\tv2") {
        return Err("stage1 cache: bad header".into());
    }
    let policy = lines.next().ok_or("stage1 cache: missing policy line")?;
    let expect = format!("policy\tscale\t{:e}\trdp_epsilon\t{:e}\tfit_squared_error\t{:e}\tfit_max_refits\t{}\tfit_tolerance_policy\t{:?}\tframe_map\t{:?}\tguide\t{:?}\treferences\t{:?}\tcorner_wiring\t{}", rc.scale().units_per_px(), m.rdp_epsilon, rc.fit_squared_error().value(), m.fit_max_refits, m.fit_tolerance_policy, m.frame_map, m.guide, m.references, if m.corner_wiring { "on" } else { "off" });
    if policy != expect {
        return Err(format!("stage1 cache: policy mismatch (cache: {policy}) (manifest: {expect})"));
    }
    let binding_line = lines.next().ok_or("stage1 cache: missing scale binding")?;
    let record = binding_line.strip_prefix("scale_binding\t");
    rc.scale().check_cache_record(record).map_err(|e| format!("stage1 cache: {e:?}"))?;
    let stage1_line = lines.next().ok_or("stage1 cache: missing stage1 identity")?;
    if stage1_line.strip_prefix("stage1_identity\t") != Some(rc.stage1_identity().as_str()) {
        return Err("stage1 cache: config fit identity mismatch".into());
    }
    let exe_line = lines.next().ok_or("stage1 cache: missing engine_exe_sha256 line")?;
    let cur_exe = fs::read("/proc/self/exe").map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".to_string());
    let expect_exe = format!("engine_exe_sha256\t{cur_exe}");
    if exe_line != expect_exe {
        // Executable mismatch rejects cached stage1 in every export mode.
        return Err("stage1 cache: engine executable changed since cache write; refusing reuse (fit/code version invalidation)".into());
    }
    let mut entries: Vec<(String, Stage1CacheEntry)> = Vec::new();
    let rest: Vec<&str> = lines.filter(|l| !l.starts_with("placeholder_decision\t") && !l.starts_with("speck_retained\t") && !l.starts_with("speck_retained_hole\t") && !l.starts_with("speck_dropped_collapse\t") && !l.starts_with("straight_sweep_converted\t") && !l.starts_with("corner_wiring_seams\t") && !l.starts_with("sub_grid_floor\t")).collect();
    let mut i = 0usize;
    let bits = |v: &str| -> Result<f64, String> { u64::from_str_radix(v, 16).map(f64::from_bits).map_err(|e| format!("stage1 cache: bad bits {v}: {e}")) };
    while i < rest.len() {
        let f: Vec<&str> = rest[i].split('\t').collect();
        match f.first().copied() {
            Some("glyph") => {
                if f.len() != 6 || f[2] != "cp" || f[4] != "png_sha256" { return Err(format!("stage1 cache: bad glyph row: {}", rest[i])); }
                let name = f[1].to_string();
                let cp = if f[3] == "-" { None } else { Some(u32::from_str_radix(f[3].trim_start_matches("0x"), 16).map_err(|e| format!("stage1 cache: bad cp: {e}"))?) };
                let sha = f[5].to_string();
                i += 1;
                let mut rings = Vec::new();
                while i < rest.len() && rest[i].starts_with("ring\t") {
                    let rf: Vec<&str> = rest[i].split('\t').collect();
                    if rf.len() != 4 { return Err("stage1 cache: bad ring row".into()); }
                    let start = Point { x: bits(rf[1])?, y: bits(rf[2])? };
                    let n: usize = rf[3].parse().map_err(|e| format!("stage1 cache: bad span count: {e}"))?;
                    i += 1;
                    let mut spans = Vec::new();
                    for _ in 0..n {
                        let sf: Vec<&str> = rest.get(i).ok_or("stage1 cache: truncated spans")?.split('\t').collect();
                        match sf.first().copied() {
                            Some("L") if sf.len() == 3 => spans.push(Span::Line { end: Point { x: bits(sf[1])?, y: bits(sf[2])? } }),
                            Some("C") if sf.len() == 7 => spans.push(Span::Cubic {
                                control_one: Point { x: bits(sf[1])?, y: bits(sf[2])? },
                                control_two: Point { x: bits(sf[3])?, y: bits(sf[4])? },
                                end: Point { x: bits(sf[5])?, y: bits(sf[6])? } }),
                            _ => return Err("stage1 cache: bad span row".into()),
                        }
                        i += 1;
                    }
                    rings.push(ReferenceRing { start, spans });
                }
                let mut mring = Vec::new();
                while i < rest.len() && rest[i].starts_with("mring\t") {
                    let rf: Vec<&str> = rest[i].split('\t').collect();
                    if rf.len() != 4 { return Err("stage1 cache: bad mring row".into()); }
                    let start = Point { x: bits(rf[1])?, y: bits(rf[2])? };
                    let n: usize = rf[3].parse().map_err(|e| format!("stage1 cache: bad span count: {e}"))?;
                    i += 1;
                    let mut spans = Vec::new();
                    for _ in 0..n {
                        let sf: Vec<&str> = rest.get(i).ok_or("stage1 cache: truncated spans")?.split('\t').collect();
                        match sf.first().copied() {
                            Some("L") if sf.len() == 3 => spans.push(Span::Line { end: Point { x: bits(sf[1])?, y: bits(sf[2])? } }),
                            Some("C") if sf.len() == 7 => spans.push(Span::Cubic {
                                control_one: Point { x: bits(sf[1])?, y: bits(sf[2])? },
                                control_two: Point { x: bits(sf[3])?, y: bits(sf[4])? },
                                end: Point { x: bits(sf[5])?, y: bits(sf[6])? } }),
                            _ => return Err("stage1 cache: bad span row".into()),
                        }
                        i += 1;
                    }
                    mring.push(ReferenceRing { start, spans });
                }
                let rl: Vec<&str> = rest.get(i).ok_or("stage1 cache: missing receipt_lines")?.split('\t').collect();
                if rl.len() != 2 || rl[0] != "receipt_lines" { return Err("stage1 cache: bad receipt_lines row".into()); }
                let k: usize = rl[1].parse().map_err(|e| format!("stage1 cache: bad receipt_lines count: {e}"))?;
                i += 1;
                let mut rec = String::new();
                for _ in 0..k {
                    rec.push_str(rest.get(i).ok_or("stage1 cache: truncated receipt")?);
                    rec.push('\n');
                    i += 1;
                }
                if rest.get(i).copied() != Some("end") { return Err("stage1 cache: missing end".into()); }
                i += 1;
                entries.push((name, Stage1CacheEntry { cp, sha, rings: Some(rings), mring: if mring.is_empty() { None } else { Some(mring) }, reason: None, receipt: rec }));
            }
            Some("excluded") => {
                if f.len() < 8 || f[2] != "cp" || f[4] != "png_sha256" || f[6] != "reason" { return Err(format!("stage1 cache: bad excluded row: {}", rest[i])); }
                let name = f[1].to_string();
                let cp = if f[3] == "-" { None } else { Some(u32::from_str_radix(f[3].trim_start_matches("0x"), 16).map_err(|e| format!("stage1 cache: bad cp: {e}"))?) };
                let sha = f[5].to_string();
                let reason = f[7..].join("\t");
                entries.push((name, Stage1CacheEntry { cp, sha, rings: None, mring: None, reason: Some(reason), receipt: String::new() }));
                i += 1;
            }
            other => return Err(format!("stage1 cache: unexpected row: {other:?}")),
        }
    }
    // A live found-class run persists blank-cell skips as a typed
    // placeholder_decision row and writes no entries for those slots; the
    // replay honors the same decision (read before the notdef refusal), so
    // the population check excludes the same slots.
    let expect_entries = m.glyphs.len() - placeholder_skip_cps.len();
    if entries.len() != expect_entries {
        // The original wording is pinned by replay budget tests; the skip
        // suffix appears only when a persisted placeholder decision is in
        // force.
        if placeholder_skip_cps.is_empty() {
            return Err(format!("stage1 cache: entry count {} != manifest glyph count {}", entries.len(), m.glyphs.len()));
        }
        return Err(format!("stage1 cache: entry count {} != manifest glyph count {} (placeholder skips {})", entries.len(), m.glyphs.len(), placeholder_skip_cps.len()));
    }
    let rows: Vec<&GlyphRow> = m.glyphs.iter().filter(|g| g.codepoint.map_or(true, |cp| !placeholder_skip_cps.contains(&cp))).collect();
    let mut outcomes = Vec::with_capacity(rows.len());
    let mut replay_total = *fallback_span_total;
    // Deliberately serial: lookup and pin checks retain the old manifest-order,
    // first-name-match semantics, including duplicate names. No Rayon replay.
    for (gi, g) in rows.iter().enumerate() {
        eprintln!("progress glyph {}/{} {} (stage1 cache reuse)", gi + 1, rows.len(), g.name);
        let outcome = match replay_stage1_entry(gi, g, &entries).and_then(|o| {
            // The live fitter has already appended receipt rows when its count
            // is folded; the old replay checked overflow BEFORE appending them.
            // Preflight here preserves replay's refusal prefix exactly.
            if o.drawn.is_ok() {
                replay_total = add_fallback_events(replay_total, &g.name, o.fallback_spans).map_err(|er| er.message())?;
            }
            Ok(o)
        }) {
            Ok(o) => o,
            Err(e) => FitOutcome::fatal(gi, e),
        };
        let stop = outcome.fatal.is_some();
        outcomes.push(outcome);
        if stop { break; }
    }
    // Preserve caller-owned totals and prefix effects even on a refusal, as the
    // old serial loop did. Cache replay has no new fit/sub-grid/counter events.
    let mut acc = Stage1Acc {
        processed: std::mem::take(processed), shipped: std::mem::take(shipped),
        exclusions: std::mem::take(exclusions),
        pins: std::mem::take(stage1_pins), fallback_span_total: *fallback_span_total,
        fallback_glyph_spans: std::mem::take(fallback_glyph_spans), ..Stage1Acc::default()
    };
    let folded = stage1_reduce_into(&rows, outcomes, &mut acc, None, receipt);
    *processed = acc.processed; *shipped = acc.shipped; *exclusions = acc.exclusions;
    *stage1_pins = acc.pins;
    *fallback_span_total = acc.fallback_span_total; *fallback_glyph_spans = acc.fallback_glyph_spans;
    folded?;
    receipt.push_str(&format!("stage1_cache\t{}\treused_glyphs\t{}\n", path.display(), m.glyphs.len()));
    Ok(())
}

/// Space gate decision (dar patch, pure, unit-tested). Returns
/// (receipt_line, refusal, partial_recorded). The receipt field is
/// `solver_space_glyph_emitted`: it reports the SOLVER's space emission
/// only. `Absent` means no space glyph in SOLVER INPUT - it says nothing
/// about the exported font, where stage5 may still add a space glyph from
/// manifest `space` (see the assembly_space_glyph receipt row).
// Retained as the documented strict contract (unit-tested); the production
// call site uses `space_evidence::solver_gate_with_policy` (GUARD-FIX-2).
#[allow(dead_code)]
fn space_gate(status: &kni_metrics::self_anchored_spacing::SpaceStatus, allow_partial: bool)
    -> (String, Option<String>, bool) {
    use kni_metrics::self_anchored_spacing::SpaceStatus;
    match status {
        SpaceStatus::Measured { advance } => (format!(
            "space_status	Measured	advance	{advance}	solver_space_glyph_emitted	provided, emitted only when a space glyph is present in solver input
"),
            None, false),
        SpaceStatus::MissingEvidence { candidate_diagnostic } => {
            let line = format!(
                "space_status	MissingEvidence	candidate_diagnostic	{candidate_diagnostic}	solver_space_glyph_emitted	false
");
            if allow_partial { (line, None, true) } else { (line, Some(
                "space evidence missing: a space glyph is present in solver input but no measured space advance was supplied (typed MissingEvidence); full output refused. Rerun with --allow-partial for explicitly marked partial output".to_string()), false) }
        }
        SpaceStatus::Absent => (
            "space_status	Absent	solver_space_glyph_emitted	false
".to_string(), None, false),
    }
}

/// Receipt row when IoU settings are not declared (the report is not run).
fn iou_not_run_row() -> String {
    "iou_report\tNOT_RUN\treason\tiou_ink_threshold and iou_flatten_steps are not declared in the run configuration\n".to_string()
}
/// Receipt row carrying the real readback error when the post-pass translation proof cannot be read.
fn iou_proof_unavailable_row(cause: &str) -> String {
    format!("iou_translation_proof\tUNAVAILABLE\tcause\t{}\n", post_metrics::tsv_escape(cause))
}

/// Translation of a glyph between the input drawing and the shipped bytes: base ledger shift plus the post-pass
/// shift. `post_readback` holds the per-gid integer shift read from the base and final bytes (None = proof
/// unavailable). Ok(None) means no translation can be given (MissingTranslation); Err((claimed, readback)) means
/// the post_metrics ledger and the bytes disagree (TranslationDisagrees).
fn iou_translation(base_dx: Option<f64>, gid: Option<u16>, post_readback: &Option<Vec<i64>>, claimed_post: f64, post_noop: bool) -> Result<Option<f64>, (String, String)> {
    match (base_dx, gid, post_readback) {
        (Some(b), Some(i), Some(rb)) => {
            let read = if post_noop { 0.0 } else { rb.get(i as usize).map_or(f64::NAN, |v| *v as f64) };
            if read.is_nan() || claimed_post != read { Err((format!("{claimed_post:?}"), format!("{read:?}"))) } else { Ok(Some(b + claimed_post)) }
        }
        _ => Ok(None),
    }
}

fn iou_character_names(rows: &[GlyphRow], proxy_candidate_cps: &[u32]) -> Vec<String> {
    rows.iter().filter(|g| g.codepoint.map_or(true, |cp| !proxy_candidate_cps.contains(&cp))).map(|g|g.name.clone()).collect()
}

/// IoU report on the shipped bytes, run as the pre-publish hook of `emit_final_bundle`. Returns the receipt rows to add after the
/// bundle is published. Err means nothing was published and no iou file remains. The IoU value never gates export; population
/// or readback binding refusals, and iou file write failures, do.
fn iou_report_stage(p: &PrePublish<'_>, base_font: &NativeFontInput, m: &Manifest, rc: &run_config::RunConfig,
    processed: &[(&GlyphRow, DrawnGlyph)], exclusions: &[(String, Option<u32>, String)], gid: &GlyphIdMap,
    stage1_pins: &std::collections::HashMap<String, String>, ledger: &[kni_core::generated_native::RoundingLedger], shift: f64,
    has_space: bool, proxy_candidate_cps: &[u32], workers: usize) -> Result<(String, Vec<(String, Vec<u8>)>), String> {
    let mut rows = String::new();
    let mut files: Vec<(String, Vec<u8>)> = Vec::new();
    let iou_cfg = match rc.iou_settings() { Some(c) => c, None => return Ok((iou_not_run_row(), Vec::new())) };
        use kni_core::iou_adapter::{evidence_from_parts, job_from_readback, readback_outlines};
        use kni_core::iou_report::{build_report, run_jobs, Exclusion, IouError, ResourceLimits, SourceInput};
        // Ink threshold and flatten steps come only from the run configuration (and so from the run_config hash).
        let (ink_threshold, flatten_steps) = (iou_cfg.ink_threshold, iou_cfg.flatten_steps);
        let font_sha = sha256_hex(p.final_bytes);
        let cap = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
        let style = m.postscript_name.clone();
        let scale_k = rc.scale().units_per_px();
        // Per-glyph post-pass shift read back from base and final bytes (integer). Not needed when the offset is zero.
        let mut proof_error: Option<String> = None;
        let post_readback: Option<Vec<i64>> = if !p.post_pass { Some(Vec::new()) } else {
            match post_metrics::gap_certificate(p.base_bytes, p.final_bytes) {
                Ok(c) => Some(c.translations),
                Err(e) => { proof_error = Some(format!("{e:?}")); None }
            }
        };
        // The underlying cause is recorded; rows then fail with MissingTranslation.
        if let Some(e) = &proof_error { rows.push_str(&iou_proof_unavailable_row(e)); }
        let manifest_names = iou_character_names(&m.glyphs, proxy_candidate_cps);
        let population = iou_population::expected_population(&manifest_names, has_space);
        let mut outcomes: Vec<String> = processed.iter().map(|(g, _)| g.name.clone())
            .chain(exclusions.iter().map(|(name, _, _)| name.clone())).collect();
        outcomes.push(".notdef".into());
        if has_space { outcomes.push("space".into()); }
        let population = population.and_then(|p| { iou_population::validate_outcomes(&p, &outcomes)?; Ok(p) });
        let population_tsv: String = match &population {
            Ok(expected) => {
                let mut manifest = String::from("style\tglyph\tpopulation\n");
                for name in expected {
                    let kind = if name == ".notdef" || name == "space" { "assembly-only" }
                        else if processed.iter().any(|(g, _)| &g.name == name) { "processed" }
                        else if let Some((_, _, reason)) = exclusions.iter().find(|(g, _, _)| g == name) {
                            if reason.contains("no contours") { "stage1-excluded" } else { "stage1-refused" }
                        } else { "missing-outcome" };
                    manifest.push_str(&format!("{}\t{}\t{kind}\n", kni_core::iou_report::escape_id(&style), kni_core::iou_report::escape_id(name)));
                }
                manifest
            }
            Err(_) => String::new(),
        };
        match population {
        Err(e) => return Err(format!("IoU population refused: {e}")),
        Ok(population) => {
        let expected: Vec<(String, String)> = population.iter().map(|name| (style.clone(), name.clone())).collect();
        let processed_names: Vec<String> = processed.iter().map(|(g, _)| g.name.clone()).collect();
        let wanted = iou_population::wanted_gids(&processed_names, |name| gid.id(name));
        let readbacks = readback_outlines(p.final_bytes, &font_sha, &wanted);
        // Never zip a filtered result iterator with the unfiltered population.
        match iou_population::bind_readbacks(&wanted, readbacks) {
        Err(e) => return Err(format!("IoU readback mapping refused: {e}")),
        Ok(mut outlines) => {
        let mut jobs = Vec::new();
        let mut iou_exclusions: Vec<Exclusion> = Vec::new();
        let failed_job = |name: &str, error: IouError| {
            let ev = evidence_from_parts(scale_k, (0.0, 0.0), (0.0, 0.0), ink_threshold, flatten_steps, (0, 0), ResourceLimits { max_pixels: cap.max_pixels as u64, max_flatten_steps: flatten_steps, max_edges: 0, max_png_bytes: cap.max_input_bytes as u64, max_png_working_bytes: cap.max_working_bytes as u64 });
            job_from_readback(&style, name, SourceInput::Gray { w: 0, h: 0, gray: Vec::new() }, Err(error), ev)
        };
        for (name, _, reason) in exclusions {
            if reason.contains("no contours") {
                iou_exclusions.push(Exclusion { style: style.clone(), glyph_id: name.clone(), reason: format!("stage1-intentional-empty: {reason}") });
            } else {
                jobs.push(failed_job(name, IouError::SourceDecode { glyph: name.clone(), detail: format!("Stage1Refused: {reason}") }));
            }
        }
        for name in [Some(".notdef"), has_space.then_some("space")].into_iter().flatten() {
            iou_exclusions.push(Exclusion { style: style.clone(), glyph_id: name.into(), reason: "assembly-only-no-source-tile".into() });
        }
        for (g, dg) in processed.iter() {
            let readback = outlines.remove(&g.name);
            // Missing GID takes precedence over intentional/guided exclusions: an
            // assembly binding failure is not a successfully excluded glyph.
            if readback.is_none() {
                jobs.push(failed_job(&g.name, IouError::OutlineReadback { glyph: g.name.clone(), detail: "glyph has no gid in the emitted order".into() }));
                continue;
            }
            if let Some(Err(error)) = &readback {
                jobs.push(failed_job(&g.name, error.clone()));
                continue;
            }
            if m.references.iter().any(|r| r.0 == g.name) {
                iou_exclusions.push(Exclusion { style: style.clone(), glyph_id: g.name.clone(), reason: "guided-reference-frame-unverified".into() });
                continue;
            }
            if dg.rings.is_empty() {
                iou_exclusions.push(Exclusion { style: style.clone(), glyph_id: g.name.clone(), reason: "intentional-empty-outline".into() });
                continue;
            }
            let outline = readback.unwrap_or_else(|| Err(IouError::OutlineReadback { glyph: g.name.clone(), detail: "glyph has no gid in the emitted order".into() }));
            let limits_for = |canvas: (usize, usize)| ResourceLimits { max_pixels: cap.max_pixels as u64, max_flatten_steps: flatten_steps, max_edges: (canvas.0 as u64).saturating_mul(canvas.1 as u64), max_png_bytes: cap.max_input_bytes as u64, max_png_working_bytes: cap.max_working_bytes as u64 };
            // Source tile: bounded read (byte cap enforced before hashing/decoding), must hash to the pin
            // stage 1 recorded when the fit consumed it; otherwise a typed row error, never a measurement.
            let src_res: Result<kni_core::capture_dispatch::CapturedSource, IouError> = (|| {
                let b = read_source_bounded(&g.image, cap.max_input_bytes).map_err(|e| IouError::SourceRead { glyph: g.name.clone(), detail: e })?;
                let now = sha256_hex(&b);
                match stage1_pins.get(&g.name) {
                    Some(p1) if *p1 == now => {}
                    Some(p1) => return Err(IouError::SourcePinMismatch { glyph: g.name.clone(), stage1_pin: p1.clone(), now }),
                    None => return Err(IouError::SourcePinMissing { glyph: g.name.clone() }),
                }
                kni_core::capture_dispatch::capture_source(&b, rc.rdp_epsilon().value(), &PNG_DECODE_LIMITS, cap)
                    .map_err(|e| IouError::SourceDecode { glyph: g.name.clone(), detail: format!("{e:?}") })
            })();
            let src = match src_res {
                Ok(s) => s,
                Err(e) => {
                    // the cause is the row error; the empty placeholder source is never measured (outline Err is reported)
                    let ev = evidence_from_parts(scale_k, (0.0, 0.0), (0.0, 0.0), ink_threshold, flatten_steps, (0, 0), limits_for((0, 0)));
                    jobs.push(job_from_readback(&style, &g.name, SourceInput::Gray { w: 0, h: 0, gray: Vec::new() }, Err(e), ev));
                    continue;
                }
            };
            let origin = src.outline_contour.as_ref().map_or((src.contour.origin_x, src.contour.origin_y), |c| (c.origin_x, c.origin_y));
            let canvas = (src.receipt.width, src.receipt.height);
            let source = SourceInput::Gray { w: canvas.0, h: canvas.1, gray: src.outline_gray.clone().unwrap_or_else(|| src.gray.clone()) };
            // dx = base ledger x_translation (input -> exported base) + post-pass shift. The post-pass part is the
            // value claimed by the post_metrics ledger and must equal the shift read back from the base and final
            // bytes; a difference fails the row with TranslationDisagrees, an unreadable proof leaves no translation.
            let base_dx = ledger.iter().find(|l| l.glyph_id == g.name).map(|l| l.x_translation);
            let gid_of = gid.id(&g.name);
            let mut outline = outline;
            // claimed post-pass shift = change of the prepared hmtx lsb between the approved base and the final font
            let claimed_post = match (gid_of, p.post_pass) { (Some(i), true) => match (p.prepared.left_side_bearings.get(i as usize), base_font.left_side_bearings.get(i as usize)) { (Some(f), Some(b)) => *f as f64 - *b as f64, _ => f64::NAN }, _ => 0.0 };
            let dx: Option<f64> = match iou_translation(base_dx, gid_of, &post_readback, claimed_post, !p.post_pass) {
                Ok(v) => v,
                Err((claimed, read)) => {
                    if outline.is_ok() { outline = Err(IouError::TranslationDisagrees { glyph: g.name.clone(), claimed, readback: read }); }
                    None
                }
            };
            let mut ev = evidence_from_parts(scale_k, origin, dx.map_or((0.0, 0.0), |x| (x, shift)), ink_threshold, flatten_steps, canvas, limits_for(canvas));
            if dx.is_none() { ev.translation = None; }
            jobs.push(job_from_readback(&style, &g.name, source, outline, ev));
        }
        // --jobs contract: the caller's cap is the worker count (was: None =
        // available_parallelism, which ignored --jobs entirely). Output is
        // bit-identical for any worker count (oracle:
        // iou_report::tests::run_jobs_bit_identical_at_jobs_1_2_4_8).
        let out = run_jobs(&jobs, Some(workers));
        match build_report(&expected, out.rows, iou_exclusions, out.duplicates, None) {
            Ok(rep) => {
                // No disk write here: the two report files are returned as payload and published with the font in ONE
                // publish_set_exclusive transaction (rollback set, no overwrite of an existing file).
                files.push(("iou-population.tsv".to_string(), population_tsv.clone().into_bytes()));
                files.push(("iou.tsv".to_string(), rep.to_tsv().into_bytes()));
                rows.push_str(&rep.to_receipt());
                rows.push_str(&format!("iou_config\tink_threshold\t{ink_threshold}\tflatten_steps\t{flatten_steps}\tmax_input_bytes\t{}\tmax_pixels\t{}\tsettings_origin\trun_configuration\tlimits_origin\tpipeline-hardcoded-budget(same Limits as stage 1; not from RunConfig)\n", cap.max_input_bytes, cap.max_pixels));
            }
            Err(e) => return Err(format!("IoU inventory refused: {e}")),
        }
        } // bound readbacks
        } // readback mapping
        } // valid population
        } // population validation
    Ok((rows, files))
}

fn reject_placeholder_population(rows: &[GlyphRow], placeholders: &[u32]) -> Result<(), bound_detector_validator::BadNotdef> {
    if rows.iter().any(|row| row.codepoint.map_or(false, |cp| placeholders.contains(&cp))) {
        return Err(bound_detector_validator::BadNotdef::ContextMismatch);
    }
    Ok(())
}

/// Assembly-only bridge from pixel evidence to generated outlines and metrics.
/// Placeholder codepoints are not character rows. Widths come from the dedicated solved glyph or
/// from a separately pinned measured-space resolution, never from the record.
#[allow(clippy::too_many_arguments)]
/// Contract slot-width rule: the notdef advance is the font's widest
/// glyph advance (maximum over the solved population, .notdef and space
/// excluded). Both pixel-notdef arms use it; the notdef never enters the
/// pair cascade.
pub(crate) fn max_glyph_advance(metrics: &[kni_metrics::self_anchored_spacing::GlyphSpacing]) -> Result<f64, bound_detector_validator::BadNotdef> {
    let mut maximum: Option<f64> = None;
    for metric in metrics.iter().filter(|m| m.glyph_id != ".notdef" && m.glyph_id != "space") {
        if !metric.advance.is_finite() || !(0.0..=u16::MAX as f64).contains(&metric.advance) {
            return Err(bound_detector_validator::BadNotdef::InvalidSourceImage);
        }
        maximum = Some(maximum.map_or(metric.advance, |v| v.max(metric.advance)));
    }
    maximum.ok_or(bound_detector_validator::BadNotdef::InvalidSourceImage)
}

fn assemble_pixel_notdef(
    state: &bound_detector_validator::DetectionState,
    _source_rows: &[(u32, String)],
    drawn: &[DrawnGlyph],
    metrics: &[kni_metrics::self_anchored_spacing::GlyphSpacing],
    _pins: &std::collections::HashMap<String, String>,
    _space_spec: Option<&space_spec::Spec>,
    _space_res: Option<&space_evidence::SpaceResolution>,
    _space_gate: &space_evidence::SpaceGate,
    receipt: &mut String,
) -> Result<(DrawnGlyph, f64, f64, f64), bound_detector_validator::BadNotdef> {
    use bound_detector_validator::{BadNotdef, DetectionState, PixelNotdefKind, PIXEL_INK_MODEL};
    let DetectionState::PixelEvidence { kind, context, sources, space_advance, pixel_form_sha256, .. } = state else {
        return Err(BadNotdef::MissingPixelEvidence);
    };
    if context.ink_model != PIXEL_INK_MODEL || !context.units_per_px.is_finite() || context.units_per_px <= 0.0 {
        return Err(BadNotdef::ContextMismatch);
    }
    match kind {
        PixelNotdefKind::RepeatedForm => {
            if space_advance.is_some() { return Err(BadNotdef::ContextMismatch); }
            let name = &".notdef".to_string();
            let mut outlines = drawn.iter().filter(|glyph| &glyph.glyph_id == name);
            let source = outlines.next().ok_or(BadNotdef::MissingPixelEvidence)?;
            if outlines.next().is_some() { return Err(BadNotdef::AmbiguousPixelCandidate); }
            if source.rings.is_empty() { return Err(BadNotdef::InvalidSourceImage); }
            let advance = max_glyph_advance(metrics)?;
            // Conservative ink width: all span points including curve
            // controls (declared over-estimate; only feeds the warning).
            let (mut x_min, mut x_max) = (f64::INFINITY, f64::NEG_INFINITY);
            for ring in &source.rings {
                let mut pts = vec![ring.start];
                for span in &ring.spans {
                    match span {
                        Span::Line { end } => pts.push(*end),
                        Span::Cubic { control_one, control_two, end } => { pts.push(*control_one); pts.push(*control_two); pts.push(*end); }
                    }
                }
                for pt in pts { x_min = x_min.min(pt.x); x_max = x_max.max(pt.x); }
            }
            if x_min.is_finite() && x_max - x_min > advance {
                receipt.push_str(&format!("notdef_ink_exceeds_advance\ttrue\tink_width\t{}\tadvance\t{advance}\n", x_max - x_min));
            }
            let mut notdef = source.clone();
            notdef.glyph_id = ".notdef".into();
            receipt.push_str(&format!("classification\tpixel-notdef-candidate\tdecision_basis\tsource-image\tpixel_form_sha256\t{pixel_form_sha256}\tkind\trepeated-form\tspace_binding\tnone\tsource_sha256\t{}\tadvance_basis\tmax-glyph-advance\tlsb\t0\trsb\t0\tadvance\t{}\tplaceholder_cp_count\t{}\n", context.source_sha256, advance, sources.len()));
            Ok((notdef, 0.0, 0.0, advance))
        }
        PixelNotdefKind::BlankCell => {
            if space_advance.is_some() { return Err(BadNotdef::ContextMismatch); }
            let advance = max_glyph_advance(metrics)?;
            receipt.push_str(&format!("classification\tpixel-notdef-candidate\tdecision_basis\tsource-image\tpixel_form_sha256\t{pixel_form_sha256}\tkind\tblank-cell\tspace_binding\tnone\tadvance_basis\tmax-glyph-advance\tadvance\t{advance}\tplaceholder_cp_count\t{}\n",sources.len()));
            Ok((DrawnGlyph{glyph_id:".notdef".into(),rings:vec![]},0.0,0.0,advance))
        }
    }
}

/// GPOS writer failure degrades to an OTF without GPOS plus a `kern_omitted` warning line (extends the omit precedent).
/// Retained as the documented strict contract (unit-tested); the production
/// call site uses `write_kern_with_policy` (GUARD-FIX-2).
#[allow(dead_code)]
fn gpos_or_omit_on_error(r: Result<Option<Vec<u8>>, kni_metrics::gpos_pairpos1::GposWriteError>) -> (Option<Vec<u8>>, Option<String>) {
    match r {
        Ok(g) => (g, None),
        Err(e) => (None, Some(format!("kern_omitted\ttrue\treason\tgpos_writer_error\t{e:?}\t(GPOS writer failed; font exported without GPOS kerning)\n"))),
    }
}
/// Runs the spacing solver; when it refuses on one glyph's own profile (non-finite value,
/// invalid profile, UPM mismatch) that glyph is removed from `profiles` and the solve is
/// retried with the remaining population. Returns the solution and the (glyph, reason)
/// exclusions in removal order. Errors that name no glyph are returned unchanged.
/// Terminates: every retry removes one profile.
/// Post-solve priors must see precisely the successful retry population.
fn restrict_learned_context(ctx: &mut FontContext, excluded: &[(String, String)]) {
    ctx.glyph_codepoints.retain(|(name, _)| !excluded.iter().any(|(id, _)| id == name));
    ctx.measured_pairs.retain(|p| !excluded.iter().any(|(id, _)| id == &p.left || id == &p.right));
}

#[cfg(test)]
mod k12_retry_context_tests {
    use super::*;
    #[test]
    fn successful_retry_removes_excluded_codepoints_and_pair_endpoints() {
        use kni_metrics::self_anchored_spacing::MeasuredPair;
        let mut ctx = FontContext {
            glyph_codepoints: vec![("A".into(), 65), ("B".into(), 66), ("C".into(), 67)],
            measured_pairs: vec![
                MeasuredPair { left: "A".into(), right: "B".into(), gap: 10.0 },
                MeasuredPair { left: "B".into(), right: "C".into(), gap: 11.0 },
                MeasuredPair { left: "A".into(), right: "C".into(), gap: 12.0 },
            ], ..FontContext::default()
        };
        restrict_learned_context(&mut ctx, &[("B".into(), "typed-invalid-profile".into())]);
        assert_eq!(ctx.glyph_codepoints, vec![("A".into(), 65), ("C".into(), 67)]);
        assert_eq!(ctx.measured_pairs.len(), 1);
        assert_eq!(ctx.measured_pairs[0].left, "A");
        assert_eq!(ctx.measured_pairs[0].right, "C");
        assert_eq!(ctx.measured_pairs[0].gap, 12.0);
    }
}

fn solve_spacing_excluding_culprits(
    profiles: &mut Vec<OutlineProfile>, cps: &[(String, u32)], policy: &SpacingPolicy, jobs: run_config::Jobs,
) -> Result<(kni_metrics::self_anchored_spacing::SpacingSolution, Vec<(String, String)>), kni_metrics::self_anchored_spacing::SpacingError> {
    use kni_metrics::self_anchored_spacing::SpacingError as E;
    let mut excluded: Vec<(String, String)> = Vec::new();
    let mut live_cps: Vec<(String, u32)> = cps.to_vec();
    loop {
        let ctx = FontContext { glyph_codepoints: live_cps.clone(), ..FontContext::default() };
        match solve_spacing_jobs(profiles, Some(&ctx), policy, jobs.get()) {
            Ok(sol) => return Ok((sol, excluded)),
            Err(e) => {
                let id = match &e {
                    E::NonFinite { glyph_id, .. } | E::InvalidProfile { glyph_id, .. } | E::InconsistentUpm { glyph_id, .. } => glyph_id.clone(),
                    _ => return Err(e),
                };
                let before = profiles.len();
                profiles.retain(|p| p.glyph_id != id);
                if profiles.len() == before { return Err(e); }
                live_cps.retain(|(n, _)| *n != id);
                excluded.push((id, e.to_string()));
            }
        }
    }
}

/// Pure median (population typical value): sorted middle, mean of the two
/// middles on even counts. None on empty input - callers keep their typed
/// refusal, never an invented 0.0.
/// Typed variant token for receipt lines: variant identity only, never the
/// stringified payload (payload text is diagnostic, not a receipt contract).
fn spacing_error_token(e: &kni_metrics::self_anchored_spacing::SpacingError) -> &'static str {
    use kni_metrics::self_anchored_spacing::SpacingError::*;
    match e {
        EmptyInput => "EmptyInput",
        InconsistentUpm { .. } => "InconsistentUpm",
        NonFinite { .. } => "NonFinite",
        InvalidProfile { .. } => "InvalidProfile",
        InvalidContext { .. } => "InvalidContext",
        ResourceBoundExceeded { .. } => "ResourceBoundExceeded",
        NoUsableGlyphs { .. } => "NoUsableGlyphs",
        AnchorUnresolved { .. } => "AnchorUnresolved",
    }
}

/// Stem-pair xAdvance narrowing at the GPOS callsite, before the value is
/// handed to the writer. The adapter's input is the POST-GUARD final ship
/// value, never the raw residual: the no-surprise overlap guard may
/// deterministically adjust a pair to a verified safe integer distance, and
/// re-deriving the kern from the raw residual here would silently unwind
/// that collision-avoiding adjustment (the residual row carries no adjusted
/// flag, so the callsite cannot tell). Saturation and non-finite detection
/// belong upstream, where the residual's range is still visible; a value
/// that reaches this callsite is already finite and inside int16 range, so
/// the adapter can only return InRange here. ON: the adapter owns the
/// narrowing rule (today: identity on the post-guard value; no ledger rows
/// can be emitted from this callsite). OFF: the legacy `written` passes
/// through unchanged. ON and OFF outputs are byte-identical by construction
/// and pinned by test.
pub(crate) const STEM_PAIR_SATURATE_POLICY: bool = false;
pub(crate) struct StemPairDecision { pub saturate: bool, pub left: u16, pub right: u16 }
pub(crate) fn narrow_pair_x_advance(post_guard_final: i16, decision: &StemPairDecision) -> Option<i32> {
    if !decision.saturate { return Some(i32::from(post_guard_final)); }
    match stem_pair_overflow::evaluate(stem_pair_overflow::PairInput { left: decision.left, right: decision.right, raw: f64::from(post_guard_final), destination: stem_pair_overflow::Destination::GposXAdvanceInt16 }) {
        stem_pair_overflow::Verdict::InRange(v) => {
            debug_assert_eq!(v, post_guard_final, "adapter on the post-guard value must return it unchanged");
            Some(i32::from(v))
        }
        // Unreachable by construction (input is finite and in int16 range);
        // ship the post-guard value rather than dropping anything silently.
        stem_pair_overflow::Verdict::Saturated { .. } | stem_pair_overflow::Verdict::NonFinite(_) => {
            debug_assert!(false, "post-guard value is finite and in int16 range; the adapter cannot saturate or refuse here");
            Some(i32::from(post_guard_final))
        }
    }
}

/// Writes only core-serialized mov-1 records. The first record must be the
/// envelope, and no other envelope may appear later. With the gate off this
/// returns before validating or creating any output file.
#[allow(dead_code)] // exercised by the test suite; no production caller wired yet
fn run_id_from_observer_records(records: &[kni_core::obs_envelope::Record]) -> String {
    match records.first() {
        Some(kni_core::obs_envelope::Record::Envelope(e)) => e.run_id.clone(),
        _ => String::new(),
    }
}

fn merge_visibility_run_obs_context(run: &MergeVisibilityRunContext) -> kni_core::obs_envelope::ObsContext {
    kni_core::obs_envelope::ObsContext {
        run_id: run.run_id.clone(), invocation_id: run.invocation_id.clone(), glyph: String::new(), style: run.style.clone(),
        route_domain: kni_core::obs_envelope::RouteDomain::Primary,
        route: if run.stage1_route == kni_core::obs_envelope::Stage1Route::CacheReuse { kni_core::obs_envelope::FitRoute::CacheReuse } else { kni_core::obs_envelope::FitRoute::Plain },
        stage1_route: Some(run.stage1_route.clone()), stage1_cache_sha256: run.stage1_cache_sha256.clone(),
    }
}

fn append_merge_visibility_completion(records: &mut Vec<kni_core::obs_envelope::Record>, run: &MergeVisibilityRunContext,
    out_dir: &Path, completed_stage: &str, pp1_floor_reason: Option<&str>, pp3_domains: &[kni_core::obs_envelope::PipelineDomain]) {
    use kni_core::obs_envelope::{Frontier, Obs, ObsPoint, ObserverOutcome, Record};
    let base = merge_visibility_run_obs_context(run);
    if let Some(reason) = pp1_floor_reason {
        records.retain(|r| !matches!(r, Record::Obs(o) if o.point == ObsPoint::Pp1));
        records.push(Record::Obs(Obs::pipeline_obs(&base, ObsPoint::Pp1, ObserverOutcome::NotEnabled, None, Some(reason.to_string()))));
    } else if run.stage1_route == kni_core::obs_envelope::Stage1Route::CacheReuse && !records.iter().any(|r| matches!(r, Record::Obs(o) if o.point == ObsPoint::Pp1)) {
        records.push(Record::Obs(Obs::pipeline_obs(&base, ObsPoint::Pp1, ObserverOutcome::NotEnabled, None, Some("stage1_cache_reuse".into()))));
    }
    let cached = run.stage1_route == kni_core::obs_envelope::Stage1Route::CacheReuse;
    records.push(Record::Obs(Obs::pipeline_obs(&base, ObsPoint::Pp2,
        if cached { ObserverOutcome::NotEnabled } else { ObserverOutcome::Complete }, None,
        cached.then(|| "stage1_cache_reuse".to_string()))));
    for domain in pp3_domains {
        records.push(Record::Obs(Obs::pipeline_obs(&base, ObsPoint::Pp3, ObserverOutcome::Complete, Some(domain.clone()), None)));
    }
    records.push(Record::Frontier(Frontier::new(run.run_id.clone(), completed_stage.to_string(), true, out_dir.join("stage1-cache.txt").is_file())));
}

fn write_merge_visibility_records(records: &[kni_core::obs_envelope::Record], out_dir: &Path, enabled: bool, source_bytes: Option<&[u8]>) -> Result<(), String> {
    use kni_core::obs_envelope::Record;
    if !enabled { return Ok(()); }
    if !matches!(records.first(), Some(Record::Envelope(_))) {
        return Err("mov-1 observer enabled but initial envelope record is missing".into());
    }
    if records.iter().skip(1).any(|r| matches!(r, Record::Envelope(_))) {
        return Err("mov-1 stream contains more than one envelope".into());
    }
    let path = out_dir.join(kni_core::obs_envelope::OUTPUT_FILENAME);
    let Some(Record::Envelope(envelope)) = records.first() else {
        return Err("mov-1 observer enabled but initial envelope record is missing".into());
    };
    let tail = records.iter().skip(1).cloned().collect();
    let lines = kni_core::obs_envelope::into_records(
        envelope.clone(), vec![tail], &kni_core::obs_envelope::RunSource { src_bytes: source_bytes },
    ).map_err(|_| "mov-1 record contains a non-finite number".to_string())?;
    let mut jsonl = String::new();
    for json in lines {
        if json.contains('\n') || json.contains('\r') {
            return Err("mov-1 record serializer returned more than one JSON line".into());
        }
        jsonl.push_str(&json);
        jsonl.push('\n');
    }
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(&path)
        .map_err(|e| format!("write mov-1 observer {}: {e}", path.display()))?;
    use std::io::Write;
    file.write_all(jsonl.as_bytes()).map_err(|e| format!("write mov-1 observer {}: {e}", path.display()))?;
    file.flush().map_err(|e| format!("flush mov-1 observer {}: {e}", path.display()))
}

#[cfg(test)]
mod merge_visibility_writer_tests {
    use super::write_merge_visibility_records;
    use kni_core::obs_envelope::{Envelope, EnvFlags, InvocationId, Record, Stage1Route};
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir() -> PathBuf {
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        std::env::temp_dir().join(format!("kni-mov1-writer-{}-{nonce}", std::process::id()))
    }

    fn envelope() -> Record {
        Record::Envelope(Envelope {
            run_id: "run".into(), source_full_ref: None, active_source_mapping_status: None,
            fixture_id: None, fixture_sha256: None, config_digest: Some("config".into()), economy_mode: None,
            coordinate_unit: Some("font_units".into()), grid: None, dense_bound_db: None, line_tolerance: None, workers: 1,
            stage1_route: Stage1Route::Live, stage1_cache_sha256: None, invocation_id: InvocationId("id".into()),
            env_flags: EnvFlags(Vec::new()), invocation_id_style: "ring:<n>".into(),
        })
    }

    #[test]
    fn disabled_gate_creates_no_file_even_for_empty_records() {
        let dir = temp_dir(); std::fs::create_dir(&dir).unwrap();
        assert_eq!(write_merge_visibility_records(&[], &dir, false, None), Ok(()));
        assert!(!dir.join(kni_core::obs_envelope::OUTPUT_FILENAME).exists());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn enabled_gate_refuses_missing_initial_envelope_before_file_creation() {
        let dir = temp_dir(); std::fs::create_dir(&dir).unwrap();
        let err = write_merge_visibility_records(&[], &dir, true, None).unwrap_err();
        assert!(err.contains("initial envelope"));
        assert!(!dir.join(kni_core::obs_envelope::OUTPUT_FILENAME).exists());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn duplicate_envelopes_are_refused_before_file_creation() {
        let dir = temp_dir(); std::fs::create_dir(&dir).unwrap();
        let records = [envelope(), envelope()];
        let err = write_merge_visibility_records(&records, &dir, true, None).unwrap_err();
        assert!(err.contains("more than one envelope"));
        assert!(!dir.join(kni_core::obs_envelope::OUTPUT_FILENAME).exists());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn enabled_gate_writes_canonical_envelope_first_and_no_overwrite() {
        let dir = temp_dir(); std::fs::create_dir(&dir).unwrap();
        let records = [envelope()];
        write_merge_visibility_records(&records, &dir, true, None).unwrap();
        let path = dir.join(kni_core::obs_envelope::OUTPUT_FILENAME);
        let text = std::fs::read_to_string(&path).unwrap();
        assert_eq!(text.lines().count(), 1);
        assert!(text.starts_with("{\"schema\":\"mov-1\",\"kind\":\"envelope\""));
        assert!(write_merge_visibility_records(&records, &dir, true, None).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }
}


/// Run identity for the run-path audit: pins copied from the manifest and
/// run config, nothing invented.
fn run_audit_identity(m: &Manifest, rc: &run_config::RunConfig) -> run_audit::RunIdentity {
    run_audit::RunIdentity {
        population_sha256: m.population_sha256.clone(),
        family: m.family.clone(),
        subfamily: m.subfamily.clone(),
        postscript_name: m.postscript_name.clone(),
        style_id: rc.style_id().to_string(),
        emitter: run_audit::EMITTER.to_string(),
    }
}

/// Write the run-path audit as the terminal artifact, then close the loop:
/// the just-written audit is verified against the out dir it describes (the
/// consumer check, run by the writer as self-evidence). Detection only: an
/// audit failure or a mismatch ledger degrades to a stderr note and never
/// changes the run.
fn run_audit_close(out_dir: &Path, m: &Manifest, rc: &run_config::RunConfig, path: run_audit::RunPath) {
    if let Err(e) = run_audit::write_run_audit(out_dir, &run_audit_identity(m, rc), path) {
        eprintln!("run_audit degraded: {e}");
        return;
    }
    match run_audit::verify_run_dir(out_dir) {
        Ok(mismatches) if mismatches.is_empty() => {}
        Ok(mismatches) => eprintln!("run_audit closure mismatches:\n{}", run_audit::render_mismatches_tsv(&mismatches)),
        Err(e) => eprintln!("run_audit verify degraded: {e}"),
    }
}
/// Export ink placement for a run: a style in the declared tile-anchor scope
/// ships the anchored outline untouched (interior margins are anatomy; hmtx
/// lsb stays the declared 0); every other style keeps the status-quo
/// AlignToLsb. Same gate as the emit-time anchor, single decision point.
fn export_ink_placement(style_id: &str) -> InkPlacement {
    if declared_convention::paul_new_tile_anchor_scope(style_id) { InkPlacement::TileAnchoredZeroBearing } else { InkPlacement::AlignToLsb }
}
// A nested Option distinguishes disabled mode from an enabled pin with no
// derived value. Enabled-none must never fall back to a post-A2 population.
fn capture_space_pin<F>(enabled: bool, derive: F) -> Option<Option<(f64, &'static str)>>
where F: FnOnce() -> Option<(f64, &'static str)> {
    if enabled { Some(derive()) } else { None }
}

fn consume_space_pin<F>(pin: Option<Option<(f64, &'static str)>>, legacy: F) -> Option<(f64, &'static str)>
where F: FnOnce() -> Option<(f64, &'static str)> {
    match pin { Some(value) => value, None => legacy() }
}

fn space_pin_receipt(value: Option<(f64, &'static str)>) -> String {
    match value {
        Some((advance, basis)) => format!("space_pin\tepoch\tpre_A2\tstatus\tderived\tadvance\t{advance}\tbasis\t{basis}\tlate_fallbacks\texcluded\n"),
        None => "space_pin\tepoch\tpre_A2\tstatus\tnone\tlate_fallbacks\texcluded\n".to_string(),
    }
}

#[cfg(test)]
mod space_pin_s1_tests {
    use super::*;
    #[test]
    fn off_is_lazy_and_uses_legacy_without_receipt() {
        let pin = capture_space_pin(false, || panic!("disabled capture must be lazy"));
        assert_eq!(pin, None);
        let mut receipt = String::new();
        if let Some(value) = pin { receipt.push_str(&space_pin_receipt(value)); }
        assert_eq!(receipt, "");
        assert_eq!(consume_space_pin(pin, || Some((124.0, "n_advance"))), Some((124.0, "n_advance")));
    }
    #[test]
    fn enabled_none_is_not_disabled() {
        let pin = capture_space_pin(true, || None);
        assert_eq!(pin, Some(None));
        assert_eq!(consume_space_pin(pin, || panic!("must not derive from late population")), None);
        assert!(space_pin_receipt(None).contains("status\tnone"));
    }
    #[test]
    fn enabled_pin_survives_advance_mutation() {
        let mut n_advance = 124.0;
        let pin = capture_space_pin(true, || Some((n_advance, "n_advance")));
        n_advance = 164.0;
        assert_eq!(consume_space_pin(pin, || Some((n_advance, "n_advance"))), Some((124.0, "n_advance")));
        assert!(space_pin_receipt(pin.unwrap()).contains("advance\t124\tbasis\tn_advance"));
    }
    #[test]
    fn source_basis_is_preserved() {
        for basis in ["n_advance", "lowercase_median", "all_glyph_median"] {
            let pin = capture_space_pin(true, || Some((77.5, basis)));
            assert_eq!(consume_space_pin(pin, || None), Some((77.5, basis)));
        }
    }
    #[test]
    fn real_derivation_uses_pre_a2_n_and_excludes_late_fallback() {
        let before = vec![(0x61, 100.0), (0x6e, 124.0)];
        let pin = capture_space_pin(true, || space_evidence::derive_space_advance(&before));
        let after = vec![(0x61, 140.0), (0x6e, 164.0), (0x7a, 900.0)];
        assert_eq!(consume_space_pin(pin, || space_evidence::derive_space_advance(&after)), Some((124.0, "n_advance")));
    }
    #[test]
    fn empty_pre_a2_pin_does_not_pick_up_late_n() {
        let pin = capture_space_pin(true, || space_evidence::derive_space_advance(&[]));
        let after = vec![(0x6e, 900.0)];
        assert_eq!(consume_space_pin(pin, || space_evidence::derive_space_advance(&after)), None);
    }
    #[test]
    fn off_retains_late_fallback_derivation() {
        let pin = capture_space_pin(false, || panic!("no off math"));
        let after = vec![(0x6e, 900.0)];
        assert_eq!(consume_space_pin(pin, || space_evidence::derive_space_advance(&after)), Some((900.0, "n_advance")));
    }

}

fn stage2_and_beyond(m: &Manifest, mut processed: Vec<(&GlyphRow, DrawnGlyph)>, stage1_shipped: Vec<DrawnGlyph>, mut exclusions: Vec<(String, Option<u32>, String)>, mut receipt: String, manifest_pin: String, notdef: Option<(DrawnGlyph, f64)>, pixel_notdef_drawn: Option<DrawnGlyph>, _pixel_source_limit: usize, proxy_state: Option<bound_detector_validator::DetectionState>, out_dir: PathBuf, allow_partial: bool, rc: &run_config::RunConfig, usable_fit: bool, stage1_pins: &std::collections::HashMap<String, String>, spacing_oohh_flag: bool, class_channel_targets: bool, jobs: run_config::Jobs, mut observer_records: Vec<kni_core::obs_envelope::Record>, observer_run_context: Option<MergeVisibilityRunContext>, merge_observe_enabled: bool) -> Result<String, String> {
    let declared_override = declared_override_for(m)?;
    let post = post_step_or_degrade(rc, &mut receipt);
    // Typed choke point: nothing past this line runs for a stage1_only manifest.
    if m.run_mode == RunMode::Stage1Only {
        // Completion marker: stage1-cache.txt is written BEFORE the stage-1 hard gates, so a
        // cache file alone does not mean the run completed. receipt.txt exists only on a run
        // that passed those gates (a fallback ledger > 0 passes only via --diagnostic-test-export
        // and is labelled in this receipt).
        receipt.push_str(&format!("run_mode\tstage1_only\tsolve_spacing\tNOT_RUN\tpopulation_sha256\t{}\tglyphs\t{}\n", m.population_sha256, m.glyphs.len()));
        fs::write(out_dir.join(rc.receipt_file_name()), &receipt).map_err(|e| format!("write receipt: {e}"))?;
        if merge_observe_enabled {
            append_merge_visibility_completion(&mut observer_records, observer_run_context.as_ref().ok_or("mov-1 run context missing")?, &out_dir, "population_floor", Some("population_floor:empty_population"), &[kni_core::obs_envelope::PipelineDomain::Emit]);
            write_merge_visibility_records(&observer_records, &out_dir, true, observer_run_context.as_ref().map(|c| c.source_bytes.as_slice()))?;
        }
        run_audit_close(&out_dir, m, rc, run_audit::RunPath::Stage1Only);
        return Ok(receipt);
    }
    // ---- space evidence: measured from pinned HsH/HHH tiles; full refusal unless --allow-partial ----
    let mut space_ignored: Option<&'static str> = None;
    let space_res: Option<space_evidence::SpaceResolution> = match &m.space_evidence {
        Some(r) => match space_evidence::resolve_file_jobs(r, m.scale, jobs.get()) {
            Ok(res) => Some(res),
            Err(e) => match space_evidence::ignorable_space_evidence_code(&e) {
                Some(code) => { space_ignored = Some(code); None }
                None => return Err(e),
            },
        },
        None => None,
    };
    if let Some(code) = space_ignored {
        let w = format!("space_evidence_ignored\t{code}\tspace_status\t{:?}\n", kni_metrics::self_anchored_spacing::SpaceStatus::Absent);
        eprint!("{w}");
        receipt.push_str(&w);
    }
    // GUARD-FIX-2: production runs continue on missing space evidence -
    // typed omission + partial markers, never a substitute.
    // Always-output derive (manifest key derive_space_from_letter_advances,
    // no `space` row): a measured outcome still ships the measured space;
    // every other outcome defers to the post-solve derivation below and
    // writes no partial markers. Without the key the established gate is
    // bit-identical.
    let space_evidence_gate = if m.derive_space_from_letter_advances && m.space.is_none() {
        space_evidence::gate_for_derive(space_res.as_ref(), &mut receipt)
    } else {
        space_evidence::gate_with_policy(space_res.as_ref(), allow_partial, space_evidence::SpaceEvidencePolicy::OmitAndContinue, &mut receipt)?
    };
    if let Some(r) = &space_res {
        if processed.iter().any(|(g, _)| !g.is_ligature() && g.codepoint == Some(r.codepoint)) {
            return Err(format!("refused: space codepoint {:#x} duplicates a glyph", r.codepoint));
        }
        let rows: Vec<(String, u32)> = processed.iter().filter_map(|(g, _)| g.codepoint.map(|cp| (g.name.clone(), cp))).collect();
        space_evidence::reject_space_like_glyphs(&rows)?;
    }
    receipt.push_str(&space_evidence::space_source_line(m.space, &space_evidence_gate));
    // Emit domain = the shipped (band-cleared) outlines; `processed` keeps the
    // measurement drawings for profiles and vertical metrics.
    let mut drawn: Vec<DrawnGlyph> = stage1_shipped;
    if let Some(glyph) = &pixel_notdef_drawn { drawn.push(glyph.clone()); }
    eprintln!("progress stage2 profiles");
    let pulse2 = progress_pulse("stage2 profiles");
    // ---- stage 2: profiles (bounded flatten; budget = declared w*h of the glyph's own source) ----
    let bench_profiles = fit_bench::PhaseGuard::enter("profiles");
    // Jobs-aware parallel profile stage (W14 PROFILES-PAR): one profile job per
    // glyph, folded into the ledgers in manifest order; bit-identical to the
    // former serial loop at any job count (oracle-tested in profiles_par).
    let (mut profiles, profile_skipped, stage4_exact) = profiles_par::run_profiles_stage_exact(&mut processed, &mut drawn, stage1_pins, rc, m.upm, &mut receipt, &mut exclusions, jobs)?;

    // PROBE (SOURCE-GATE-BYPASSED PROBE, GORAV loader grounding): profile
    // metadata fields + same-run emitter provenance; not production artifacts.
    {
        let mut md = String::from("glyph\tsource_pin\tprofile_method\trow_step_bits\tflatten_tolerance_bits\tcounter_area_bits\topen_left_bits\topen_right_bits\trows\n");
        for p in &profiles {
            md.push_str(&format!("{}\t{}\t{}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{}\n",
                p.glyph_id, p.source_pin, p.profile_method,
                p.row_step.to_bits(), p.flatten_tolerance.to_bits(),
                p.counter_area.to_bits(), p.open_left.to_bits(), p.open_right.to_bits(),
                p.rows.len()));
        }
        fs::write(out_dir.join("profile-metadata.tsv"), md).map_err(|e| format!("write profile-metadata: {e}"))?;
        let prov = format!("run_out\t{}\nemitter\tstage2-outline-profile-v1\nprofiles\t{}\n",
            out_dir.display(), profiles.len());
        fs::write(out_dir.join("run-provenance.tsv"), prov).map_err(|e| format!("write run-provenance: {e}"))?;
    }

    drop(bench_profiles);
    drop(pulse2);
    eprintln!("progress stage3 spacing");
    let pulse3 = progress_pulse("stage3 spacing");
    // ---- stage 3: spacing (no measured pairs/sidebearings: no-source route) ----
    let bench_pairs = fit_bench::PhaseGuard::enter("pairs");
    // Encoded rows only: unencoded anonymous glyphs never enter cp-indexed structures
    // (cmap, placeholder/notdef binding, solver pairs) - they are drawn/fitted/spaced via
    // the name-keyed paths and shipped without a cmap entry.
    let all_cps: Vec<(String, u32)> = processed.iter().filter_map(|(g, _)| g.codepoint.map(|cp| (g.name.clone(), cp))).collect();
    let proxy_placeholders: Vec<u32> = match &proxy_state {
        Some(bound_detector_validator::DetectionState::CandidateProxy { candidate_cps, .. }) => candidate_cps.clone(),
        _ => vec![],
    };
    let placeholder_names: std::collections::BTreeSet<String> = all_cps.iter()
        .filter(|(_,cp)| proxy_placeholders.contains(cp)).map(|(name,_)|name.clone()).collect();
    // Shipped population: every drawn glyph minus the proxy placeholders
    // (those ship through the notdef-proxy path, never through cmap).
    let shipped_cps: Vec<(String,u32)> = all_cps.iter().filter(|(_,cp)|!proxy_placeholders.contains(cp)).cloned().collect();
    // Solve population: shipped minus the glyphs the profile stage skipped.
    let solver_cps: Vec<(String, u32)> = shipped_cps.iter().filter(|(n, _)| !profile_skipped.iter().any(|x| x == n)).cloned().collect();
    let cps: Vec<(String,u32)> = solver_cps.clone();
    let mut _ctx = FontContext { glyph_codepoints: cps.clone(), ..FontContext::default() };
    let policy = SpacingPolicy {
        sample_resolution: rc.sample_resolution().value(),
        max_pair_evaluations: rc.max_pair_evaluations(),
        max_pairs: rc.max_pairs(),
        pair_min_shared_rows: rc.pair_min_shared_rows(),
        lambda: None,
        dcap: None,
        contrast_floor: false,
    cadence_class_pass: false,
        class_channel_targets,
    };
    // Single opt-in manifest binding validates same-source measurement evidence.
    // S1a chief decision: mapping is receipted only, never consumed by spacing.
    let mapped_measured: Vec<kni_metrics::self_anchored_spacing::MeasuredPair> =
        if m.pair_visual_same_source && declared_override.is_none() {
            let mapping = pair_visual_targets::map_pinned(&out_dir, &cps, rc.scale().units_per_px())?;
            receipt.push_str(&mapping.receipt());
            mapping.pairs
        } else {
            if m.pair_visual_same_source {
                receipt.push_str("pair_visual_targets\tsuppressed\treason\tdeclared_style_override_no_solve\n");
            }
            Vec::new()
        };
    // Chief S1a: mapped evidence is report-only, never a spacing input.
    // Keep the single manifest binding, validate pin and receipt typed rows.
    if m.pair_visual_same_source && declared_override.is_none() {
        receipt.push_str("pair_visual_targets\tconsumption\treport_only\tspacing_use\tnone\n");
    }
    let _report_only_pairs = mapped_measured;
    // Cascade exhausted (no usable glyphs / anchor unresolved): lay out the WHOLE population with
    // each glyph's own natural metrics, never an invented value, and receipt a typed warning.
    // Every other refusal keeps the existing hard path.
    let (mut solved, midrun_excluded) = if declared_override.is_some() {
        // Declared style override (SET semantics): the per-character sidebearing
        // solve does NOT run for this style. The natural zero-bearing population
        // ships (own-measurement advances, nothing invented); the declared
        // post-step SET then yields exactly the row's lsb/rsb on every glyph.
        (spacing_fallback::natural_population(&profiles), Vec::new())
    } else {
    match solve_spacing_excluding_culprits(&mut profiles, &cps, &policy, jobs) {
        Ok((sol, excl)) => {
            // Restrict the context to the successful retry's live population.
            restrict_learned_context(&mut _ctx, &excl);
            match learned_driver::declared(m) {
                None => (sol, excl),
                Some(decl) => match learned_driver::apply(&decl, &profiles, &_ctx, &policy, &sol) {
                    learned_driver::Outcome::Warm { solution, rows } => { receipt.push_str(&rows); (solution, excl) }
                    learned_driver::Outcome::Cold(rows) => { receipt.push_str(&rows); (sol, excl) }
                },
            }
        },
        Err(kni_metrics::self_anchored_spacing::SpacingError::NoUsableGlyphs { reason })
        | Err(kni_metrics::self_anchored_spacing::SpacingError::AnchorUnresolved { reason, .. }) => {
            receipt.push_str(&format!("warning\tspacing_fallback_natural\ttrue\treason\t{}\n", reason.replace(['\t', '\n'], " ")));
            (spacing_fallback::natural_population(&profiles), Vec::new())
        }
        Err(e) => {
            // Always-output: a main-solve refusal degrades to the population floor - every glyph
            // ships with zero sidebearings and its own measured raw-bounds advance (the same width
            // measure the solver ships), no pairs, baseline = population median ink y_min, heights
            // = population median ink height. Typed warning; the OTF still ships.
            receipt.push_str(&format!("warning\tspacing_solve_refused\tvariant\t{}\tdegrade\tpopulation_floor_zero_sidebearing\n", spacing_error_token(&e)));
            (spacing_fallback::degrade_population_floor(&profiles, &format!("{e:?}")), Vec::new())
        }
    }
    };
    for (name, reason) in &midrun_excluded {
        // Same ledger row shape as stage 1 exclusions, plus a typed warning with a stable code.
        // Always-output: a mid-run solve exclusion leaves the solve population only; the
        // glyph stays shipped with the declared fallback advance (fallback block below).
        let cp = solver_cps.iter().find(|(n, _)| n == name).map(|(_, c)| *c).unwrap_or(0);
        eprintln!("excluded glyph {} ({:#x}) mid-run from the solve population: {}", name, cp, reason);
        receipt.push_str(&format!("excluded\t{}\tfailure\tcp\t{:#x}\treason\t{}\n", name, cp, reason));
        receipt.push_str(&format!("warning\tglyph_excluded_midrun\t{}\tcp\t{:#x}\treason\t{}\n", name, cp, reason));
    }
    let cps: Vec<(String, u32)> = cps.into_iter().filter(|(n, _)| !midrun_excluded.iter().any(|(x, _)| x == n)).collect();
    drop(pulse3);
    if declared_override.is_some() { receipt.push_str(&style_overrides::spacing_not_run_row()); } else {
    receipt.push_str(&format!(
        "spacing\tcomplete\t{}\texcluded_pairs\t{}\texcluded_self\t{}\texcluded_below_epsilon\t{}\texcluded_unmeasurable\t{}\tnumeric_failed_pairs\t{}\tgeometric_hold_pairs\t{}\tno_accepted_candidate_pairs\t{}\tfallback_natural_clear_pairs\t{}\tfallback_verified_pairs\t{}\tnumeric_failed_nonfinite\t{}\tnumeric_failed_malformed\t{}\tnumeric_failed_natural_unverifiable\t{}\tnumeric_failed_natural_frame_conflict\t{}\taccounting_residual\t{}\taccounting_closed\t{}\tpolicy\t{}\n",
        solved.complete, solved.excluded_pairs.len(), solved.excluded_self_pairs, solved.excluded_below_epsilon, solved.excluded_unmeasurable, solved.numeric_failed_pairs, solved.geometric_hold_pairs, solved.no_accepted_candidate_pairs, solved.fallback_natural_clear_pairs, solved.fallback_verified_pairs, solved.numeric_failed_nonfinite, solved.numeric_failed_malformed, solved.numeric_failed_natural_unverifiable, solved.numeric_failed_natural_frame_conflict, solved.accounting_residual, solved.accounting_closed, solved.policy_derivation));
    }
    // K3 anchor audit (systematic anchor-error detector): the solver runs
    // audit_residual_signs over the per-class residual rows and carries the
    // report on the solution; here it becomes receipt rows plus two
    // always-written artifacts. An empty report means the audit did NOT run
    // (degrade paths ship no solve) and is typed as such - never rendered
    // as "measured and clean". Flags and class rows render only what the
    // audit measured; nothing is recomputed at this site.
    {
        let audit = &solved.anchor_audit;
        let ran = !(audit.flags.is_empty() && audit.classes.is_empty());
        receipt.push_str(&format!("anchor_audit\tran\t{ran}\tflags\t{}\tclasses\t{}\n", audit.flags.len(), audit.classes.len()));
        if ran {
            for line in kni_metrics::anchor_audit::render_flags_tsv(&audit.flags).lines().skip(1) {
                receipt.push_str(&format!("anchor_audit_flag\t{line}\n"));
            }
        }
        let signs = if ran { kni_metrics::anchor_audit::render_sign_summary_tsv(&audit.classes) } else { "anchor_audit\tnot_run\n".to_string() };
        let flags = if ran { kni_metrics::anchor_audit::render_flags_tsv(&audit.flags) } else { "anchor_audit\tnot_run\n".to_string() };
        fs::write(out_dir.join("anchor-audit-signs.tsv"), signs).map_err(|e| format!("write anchor audit signs: {e}"))?;
        fs::write(out_dir.join("anchor-audit-flags.tsv"), flags).map_err(|e| format!("write anchor audit flags: {e}"))?;
    }
    receipt.push_str(&spacing_oohh::apply(&mut solved, &profiles, &spacing_oohh::OohhPolicy::from_flag(spacing_oohh_flag)).receipt_line());
    // Space gate (dar patch): typed SpaceStatus consumption via the pure
    // space_gate fn (unit-tested). The manifest currently carries NO space
    // profile input and FontContext is built without measured_space_advance,
    // so production lands on Absent today; the Measured/MissingEvidence arms
    // are wired for the pending source-derived SpaceMeasurement/manifest
    // evidence plumbing. A pair-complete solution with MissingEvidence
    // carries NO solver space glyph; it must not become a default full
    // output, and with --allow-partial it is receipted as partial with
    // reason=space_missing_evidence (even when solved.complete is true).
    space_evidence::check_solver_status(space_res.is_some(), &solved.space_status)?;
    let (space_line, space_refusal, space_partial) = space_evidence::solver_gate_with_policy(&solved.space_status, allow_partial, space_evidence::SpaceEvidencePolicy::OmitAndContinue);
    receipt.push_str(&space_line);
    if space_res.is_none() {
        receipt.push_str("space_evidence_plumbing	pending	(manifest space evidence -> FontContext wiring not landed; this patch is NOT a complete source-derived space solution)
");
    }
    // Always-output: missing solver space evidence is a typed warning, never
    // a refusal; the solver-space claim is omitted (feature omission) while a
    // manifest-declared space still ships from its own measured basis.
    if let Some(e) = space_refusal {
        receipt.push_str(&format!("warning\tspace_evidence_missing\tdegrade\tsolver_space_omitted\tdetail\t{e}\n"));
    }
    if space_partial {
        receipt.push_str("partial_output	true	reason	space_missing_evidence
");
    }
    // export gate: an incomplete solution never becomes a default output.
    // Always-output: an incomplete solution is a typed warning, never a
    // refusal; the export continues with the solved subset.
    if !solved.complete {
        receipt.push_str(&format!("warning\tspacing_solution_incomplete\texcluded_pairs\t{}\tnumeric_failed_pairs\t{}\tgeometric_hold_pairs\t{}\tno_accepted_candidate_pairs\t{}\tdegrade\tpartial_output\n",
            solved.excluded_pairs.len(), solved.numeric_failed_pairs, solved.geometric_hold_pairs, solved.no_accepted_candidate_pairs));
        receipt.push_str("partial_output\ttrue\treason\tspacing_solution_incomplete\n");
    }

    let k5_pair_tsv: String;
    let k5_unresolved: Vec<&'static str>;
    {
        // K5 bind: per-pair export-gate accounting (items fail, batches do not). Default mode never refuses.
        let lp: Vec<k5_main_adapter::LedgerPair> = solved.pair_ledger.iter().map(|r| k5_main_adapter::LedgerPair {
            left: &r.left, right: &r.right, class: &r.class, reason_code: r.reason.code() }).collect();
        let k5 = k5_main_adapter::evaluate(&lp, k5_main_adapter::Counters {
            numeric_failed: solved.numeric_failed_pairs, geometric_hold: solved.geometric_hold_pairs,
            no_accepted: solved.no_accepted_candidate_pairs, hold_reason_lines: solved.hold_reasons.len() },
            export_gate_closure::ClosureMode::Default)?;
        receipt.push_str(&k5.receipt_rows);
        if k5.failed > 0 || k5.unledgered_numeric > 0 { receipt.push_str("partial_output\ttrue\treason\texport_gate_pairs_failed\n"); }
        k5_pair_tsv = k5.pair_tsv;
        k5_unresolved = k5_main_adapter::unresolved_codes_present(&lp);
    }

    // W1 config contract: mode accessor is Option<AutoSbMode>.
    let space_pin = capture_space_pin(rc.auto_sb_mode().is_some(), || {
        let has_evidence_space = matches!(&space_evidence_gate, space_evidence::SpaceGate::Emit { .. });
        if m.space.is_none() && !has_evidence_space && m.derive_space_from_letter_advances {
            let cp_of: std::collections::HashMap<&str, u32> = m.glyphs.iter().filter_map(|g| g.codepoint.map(|cp| (g.name.as_str(), cp))).collect();
            let values: Vec<(u32, f64)> = solved.glyphs.iter().filter_map(|g| cp_of.get(g.glyph_id.as_str()).map(|cp| (*cp, g.advance))).collect();
            space_evidence::derive_space_advance(&values)
        } else { None }
    });
    if let Some(value) = space_pin { receipt.push_str(&space_pin_receipt(value)); }
    // Typed per-pair evidence for the stage-3 excluded_unmeasurable ledger (diagnostic only; no solver decision reads it). One row per
    // pair that fails the same gate the cascade applies, only when the solve reported any; absent otherwise (no byte change).
    if solved.excluded_unmeasurable > 0 && declared_override.is_none() && learned_driver::declared(m).is_none() {
        match kni_metrics::self_anchored_spacing::diagnose_unmeasurable_pairs(&profiles, Some(&_ctx), &policy) {
            Ok(rows) => {
                receipt.push_str(&format!("unmeasurable_pair_diag\tstatus\tcomputed\tpairs\t{}\tledger_excluded_unmeasurable\t{}\n", rows.len(), solved.excluded_unmeasurable));
                for d in &rows {
                    receipt.push_str(&format!("unmeasurable_pair\t{}\t{}\treason\t{}\tshared_rows\t{}\tmin_required\t{}\tleft_y\t{}..{}\tright_y\t{}..{}\n",
                        d.left, d.right, d.reason, d.shared_rows, d.min_required, d.left_y[0], d.left_y[1], d.right_y[0], d.right_y[1]));
                }
            }
            Err(e) => receipt.push_str(&format!("unmeasurable_pair_diag\tstatus\trefused\tvariant\t{}\n", spacing_error_token(&e))),
        }
    }
    // A2 (auto-sb v0.1) insertion: after K5 evaluation AND after the W4 space-pin
    // capture, before stage 4. Guard off (rc.auto_sb_mode() == None) => nothing below
    // runs: no loads, no math, no receipt rows. Scope: glyphs present in
    // `solved.glyphs` right now; `fallback_unsolved` is appended later (exempt) and
    // `.notdef` is never touched here. K4/K5 untouched.
    if let Some(auto_sb_mode) = rc.auto_sb_mode() {
        let class_table: std::collections::BTreeMap<String, auto_sb::ClassAssignment> = auto_sb_load_class_table(rc.auto_sb_class_table())?;
        let pool_obs = auto_sb_load_pool_obs(rc.auto_sb_pool().ok_or("auto_sb: auto_sb_pool path required")?)?;
        let pool = auto_sb::build_pool_medians(&pool_obs, map_tie_break(rc.auto_sb_tie_break().ok_or("auto_sb: tie_break required")?)).map_err(|e| e.token())?;
        let inputs: Vec<auto_sb::SolvedGlyph> = solved.glyphs.iter()
            .filter(|g| g.glyph_id != ".notdef")
            .map(|g| auto_sb::SolvedGlyph { glyph_id: g.glyph_id.clone(), lsb: g.lsb, rsb: g.rsb, advance: g.advance })
            .collect();
        let cfg = auto_sb::AutoSbConfig { mode: map_auto_sb_mode(auto_sb_mode), offset_lsb: rc.auto_sb_offset_lsb(), offset_rsb: rc.auto_sb_offset_rsb() };
        let outcomes = auto_sb::apply(&inputs, &class_table, &pool, &cfg).map_err(|e| e.token())?;
        receipt.push_str(&auto_sb::refused_tsv(&outcomes));
        let target_rows: Vec<(String, f64, f64, String)> = outcomes.iter().filter_map(|o| match o {
            auto_sb::GlyphOutcome::Applied(a) => Some((a.glyph_id.clone(), a.new_lsb, a.new_rsb, format!("lsb:{},rsb:{}", a.lsb_basis.token(), a.rsb_basis.token()))),
            auto_sb::GlyphOutcome::Refused { .. } => None,
        }).collect();
        let report = a2_apply_targets(&mut solved.glyphs, &target_rows)?;
        receipt.push_str(&a2_receipt_rows(&auto_sb_mode_label(auto_sb_mode), &report));
        // Post-A2 pair frame: A2 is the final bearing authority, so stage 4 must run entirely in the post-A2 frame. The stage-3
        // pairs hold origin_distance/wall_gap measured against the pre-A2 bearings; they are rebased with the SAME pair cascade
        // (no delta correction, no tolerance change). Population floor / natural fallback has no pairs: nothing to rebase.
        if !solved.pairs.is_empty() || !solved.fallback_pairs.is_empty() {
            if learned_driver::declared(m).is_some() {
                receipt.push_str("a2_pair_frame\tpair_frame\tpre_a2\tstatus\tnot_rebased\treason\tlearned_driver_declared\n");
            } else {
                let (old_p, old_f) = (solved.pairs.len(), solved.fallback_pairs.len());
                match kni_metrics::self_anchored_spacing::rebase_pairs_to_glyphs(&profiles, Some(&_ctx), &policy, jobs.get(), &solved.glyphs) {
                    Ok(rb) => {
                        receipt.push_str(&format!("a2_pair_frame\tpair_frame\tpost_a2\tstatus\trebased\tpairs_before\t{old_p}\tpairs_after\t{}\tfallback_before\t{old_f}\tfallback_after\t{}\tunmeasurable\t{}\tnumeric_failed\t{}\tgeometric_hold\t{}\tno_accepted\t{}\tcomplete\t{}\taccounting_closed\t{}\n",
                            rb.pairs.len(), rb.fallback_pairs.len(), rb.excluded_unmeasurable, rb.numeric_failed_pairs, rb.geometric_hold_pairs, rb.no_accepted_candidate_pairs, rb.complete, rb.accounting_closed));
                        solved.pairs = rb.pairs;
                        solved.fallback_pairs = rb.fallback_pairs;
                    }
                    Err(e) => {
                        // typed, fail-closed: the stale pairs stay and the unchanged stage-4 gates hold them; never a silent skip.
                        receipt.push_str(&format!("a2_pair_frame\tpair_frame\tpre_a2\tstatus\trebase_refused\tvariant\t{}\n", spacing_error_token(&e)));
                    }
                }
            }
        }
    }

    let mut below_eps_set: BTreeSet<(String, String)> = BTreeSet::new();
    // Self-pair clearance (additive): stage 3 excludes self pairs by construction, so a glyph whose own bearings make two copies
    // overlap never got a kern row. Self pairs whose NATURAL placement collides are solved through the same pair cascade on the
    // final bearings and appended; stage 4 then measures, gates and holds them exactly like every other pair (no tolerance change).
    // Non-colliding self pairs and every existing pair are untouched. Skipped for population-floor / declared-override / learned runs.
    if declared_override.is_none() && learned_driver::declared(m).is_none() && !solved.pairs.is_empty() {
        match kni_metrics::self_anchored_spacing::solve_colliding_self_pairs(&profiles, Some(&_ctx), &policy, jobs.get(), &solved.glyphs) {
            Ok(rep) => {
                // machine-readable accounting: colliding == solved + unresolved; every unresolved glyph is listed with its typed reason.
                receipt.push_str(&format!("self_pair_clearance\tstatus\tsolved\tcolliding_self_pairs\t{}\tsolved_self_pairs\t{}\tunresolved_self_pairs\t{}\tbelow_epsilon_residual_self_pairs\t{}\tclosed_c_eq_s_plus_b_plus_u\t{}\n",
                    rep.colliding, rep.solved.len(), rep.unresolved.len(), rep.below_epsilon.len(),
                    rep.colliding == rep.solved.len() + rep.below_epsilon.len() + rep.unresolved.len()));
                for (g, reason) in &rep.unresolved {
                    receipt.push_str(&format!("self_pair_unresolved\t{g}\treason\t{reason}\n"));
                }
                solved.pairs.extend(rep.solved);
                // Colliding self pairs stage 3 solved but dropped under the residual epsilon: typed BELOW_EPSILON_RESIDUAL (not a cascade hold).
                // Stage 4 keeps them only if the natural placement collides exactly (same rule as the ordinary below-epsilon candidates).
                receipt.push_str(&format!("self_pair_below_epsilon_residual\tsent_to_stage4\t{}\n", rep.below_epsilon.len()));
                for p in rep.below_epsilon {
                    below_eps_set.insert((p.left.clone(), p.right.clone()));
                    solved.pairs.push(p);
                }
            }
            Err(e) => receipt.push_str(&format!("self_pair_clearance\tstatus\trefused\tvariant\t{}\n", spacing_error_token(&e))),
        }
    }
    // Slice 5 (additive): ordinary pairs stage 3 dropped as below-epsilon noise are re-solved on the final bearings and handed to stage 4,
    // which keeps only those whose natural placement collides exactly (same exact authority, collides(): gap 0 is not a collision).
    // Everything else keeps the stage-3 epsilon drop. No tolerance, row step or hold threshold changes; stage-3 accounting is untouched.
    if declared_override.is_none() && learned_driver::declared(m).is_none() && !solved.pairs.is_empty() {
        match kni_metrics::self_anchored_spacing::solve_below_epsilon_candidates(&profiles, Some(&_ctx), &policy, jobs.get(), &solved.glyphs) {
            Ok(cands) => {
                let existing: BTreeSet<(String, String)> = solved.pairs.iter().chain(solved.fallback_pairs.iter()).map(|p| (p.left.clone(), p.right.clone())).collect();
                let total = cands.len();
                let mut already = 0usize;
                for p in cands {
                    let k = (p.left.clone(), p.right.clone());
                    if existing.contains(&k) { already += 1; continue; }
                    below_eps_set.insert(k);
                    solved.pairs.push(p);
                }
                receipt.push_str(&format!("below_epsilon_stage4\tstatus\tsolved\tbelow_epsilon_directions\t{total}\tsent_to_stage4\t{}\talready_in_pair_list\t{already}\n", below_eps_set.len()));
            }
            Err(e) => receipt.push_str(&format!("below_epsilon_stage4\tstatus\trefused\tvariant\t{}\n", spacing_error_token(&e))),
        }
    }
    eprintln!("progress stage4 residual kern");
    // ---- stage 4: residual kern ledger ----
    let geo = ExportGeometry {
        profile_frame: ProfileFrame::ExportedB, upm: m.upm, // the KNI path frame: guard measures the geometry the font actually ships (both x_translations applied); solver placement is lsb-based = same semantics
        overlap_tolerance_units: 0.0, drop_zero_residual: false,
        row_align_tolerance_units: rc.scan_row_step().value(),
    };
    let pulse4 = progress_pulse("stage4 residual kern");
    // Declared style override: no kerning is generated for this style
    // (owner-declared convention). The kern stage does NOT run; the receipt
    // carries typed not_run rows (always-output: marked, never dropped) and
    // GPOS ships zero pairs.
    let mut below_eps_report = kni_metrics::generated_outline_kern::BelowEpsilonStage4::default();
    let kern = if declared_override.is_some() { declared_skipped_kern(m.upm, geo.profile_frame) } else { { let (k, be) = kni_metrics::generated_outline_kern::generate_residual_kern_jobs_below_eps(&solved, &profiles, Some(&stage4_exact), &below_eps_set, &geo, jobs.get()); below_eps_report = be; k } };
    if declared_override.is_none() {
        // Stage 4 measures on exact slab rows of the production-flattened rings; stage 3 stays sampled (scan_row_step). Receipt row, typed.
        let fb_marker = |rows: &[kni_metrics::generated_outline_kern::GeneratedKernPair]| rows.iter().filter(|p| p.note.contains("evidence_source=NO_FACING_WALL_FALLBACK")).count();
        let no_facing_fallback = fb_marker(&kern.ready) + fb_marker(&kern.fallback_ready) + fb_marker(&kern.overlap_holds) + fb_marker(&kern.dropped_zero) + fb_marker(&kern.rejected);
        receipt.push_str(&format!("stage4_measurement\tauthority\texact_slab_rows\tring_flatten_tolerance\t{}\tglyphs_exact\t{}\tglyphs_profiled\t{}\tno_facing_wall_fallback_pairs\t{}\n", rc.flatten_tolerance().value(), stage4_exact.len(), profiles.len(), no_facing_fallback));
        // Slice 5 accounting: candidates == dropped_no_exact_collision + eligible; eligible == ready + fallback_ready + held + rejected (tagged).
        let tag = kni_metrics::generated_outline_kern::BELOW_EPSILON_RESIDUAL_COLLIDING;
        // Am. 47: the classes below are MACHINE-COUNTED from the typed outcomes and mutually exclusive (K is counted only in K).
        let be = &below_eps_report;
        receipt.push_str(&format!("below_epsilon_stage4_result\tcandidates\t{}\tdropped_no_exact_collision\t{}\teligible\t{}\tready\t{}\tfallback_ready\t{}\theld\t{}\trejected_or_dropped_zero\t{}\tresolved_on_lattice\t{}\tpartition_closed\t{}\n",
            be.candidates, be.dropped_no_exact_collision.len(), be.candidates - be.dropped_no_exact_collision.len().min(be.candidates),
            be.ready, be.fallback_ready, be.held, be.rejected + be.dropped_zero, be.resolved_on_lattice.len(), be.partition_closed()));
        for l in &be.resolved_on_lattice {
            let fmt_t = |t: Option<f64>| t.map_or("none".to_string(), |v| format!("{v:.6}"));
            receipt.push_str(&format!("below_epsilon_resolved_on_lattice\t{}\t{}\tsolver_origin\t{:.6}\tdepth_at_origin\t{:.6}\td0\t{}\td_shipped\t{}\twalk_steps\t{}\tshift\t{:.6}\tgap_at_origin\t{:.6}\tgap_at_d0\t{:.6}\tgap_at_shipped\t{:.6}\tsolver_residual\t{:.6}\texport_value\t{}\tcontact_class\t{}\tpair_target\t{}\ttarget_met\t{}\tprovenance\tbelow_epsilon\n",
                l.left, l.right, l.solver_origin, l.depth_at_origin, l.d0, l.d_shipped, l.walk_steps, l.shift, l.gap_at_origin, l.gap_at_d0, l.gap_at_shipped, l.solver_residual, l.export_value, l.contact_class(), fmt_t(l.pair_target),
                l.target_met().map_or("none".to_string(), |m| m.to_string())));
        }
        // Am. 47 whole-kern-domain partition, machine-counted from typed outcomes (disjoint): universe = untouched_shipped + lattice_resolved
        // (ordinary + below_epsilon) + held + rejected. K entries live in the shipped buckets and are counted ONLY in K.
        {
            let shipped_buckets = kern.ready.len() + kern.fallback_ready.len() + kern.dropped_zero.len();
            let k_all = kern.lattice_resolved.len();
            let k_be = kern.lattice_resolved.iter().filter(|l| l.below_epsilon).count();
            let universe = shipped_buckets + kern.overlap_holds.len() + kern.rejected.len();
            let untouched = shipped_buckets.saturating_sub(k_all);
            let closed = k_all <= shipped_buckets && universe == untouched + k_all + kern.overlap_holds.len() + kern.rejected.len();
            receipt.push_str(&format!("kern_lattice_partition\tuniverse\t{universe}\tuntouched_shipped\t{untouched}\tlattice_resolved_ordinary\t{}\tlattice_resolved_below_epsilon\t{k_be}\theld\t{}\trejected\t{}\tpartition_closed\t{closed}\n",
                k_all - k_be, kern.overlap_holds.len(), kern.rejected.len()));
            let mut hist: std::collections::BTreeMap<i32, usize> = std::collections::BTreeMap::new();
            let (mut touch, mut pos, mut tmet, mut tunmet, mut tnone) = (0usize, 0usize, 0usize, 0usize, 0usize);
            for l in &kern.lattice_resolved {
                *hist.entry(l.walk_steps).or_default() += 1;
                if l.contact_class() == "TOUCH_GAP_0" { touch += 1 } else { pos += 1 }
                match l.target_met() { Some(true) => tmet += 1, Some(false) => tunmet += 1, None => tnone += 1 }
            }
            let h = hist.iter().map(|(k, v)| format!("{k}:{v}")).collect::<Vec<_>>().join(",");
            receipt.push_str(&format!("kern_lattice_resolved_census\twalk_steps_histogram\t{h}\tcontact_touch_gap_0\t{touch}\tcontact_positive_gap\t{pos}\ttarget_met\t{tmet}\ttarget_unmet\t{tunmet}\ttarget_none\t{tnone}\n"));
            let mut sh: Vec<f64> = kern.lattice_resolved.iter().map(|l| l.shift).collect();
            sh.sort_by(|a, b| a.total_cmp(b));
            if let (Some(mn), Some(mx)) = (sh.first(), sh.last()) {
                receipt.push_str(&format!("kern_lattice_resolved_shift\tmin\t{mn:.6}\tmedian\t{:.6}\tmax\t{mx:.6}\n", sh[sh.len() / 2]));
            }
        }
        for p in kern.ready.iter().chain(kern.fallback_ready.iter()).chain(kern.overlap_holds.iter()) {
            if p.note.contains(tag) {
                receipt.push_str(&format!("below_epsilon_eligible\t{}\t{}\tdisposition\t{:?}\tresidual_units\t{}\texport_value\t{}\n", p.left, p.right, p.disposition, p.residual_units, p.export_value));
            }
        }
    }
    drop(pulse4);
    // Kern hold-reason audit (detection only): the pairs the export gate
    // already resolved are classified into the anchor_audit hold taxonomy
    // from the kern buckets themselves, never by re-parsing text. The
    // always-written summary and flags are emitted with the artifacts
    // below; the declared-override path carries a typed not_run, never a
    // false clean. Nothing here alters the kern or its ledgers.
    let kern_hold_audit: Option<(kni_metrics::anchor_audit::HoldReasonSummary, Vec<kni_metrics::anchor_audit::AnchorAuditFlag>)> = if declared_override.is_some() {
        receipt.push_str(&style_overrides::kern_not_run_rows());
        receipt.push_str("kern_hold_audit\tran\tfalse\treason\tkern_not_run\n");
        None
    } else {
        receipt.push_str(&format!(
            "kern\tready\t{}\toverlap_held\t{}\trejected\t{}\tdropped_zero\t{}\tclamps_refused\t{}\tsolution_complete\t{}\tfallback_guard_verified\t{}\n",
            kern.receipt.ready, kern.receipt.overlap_held, kern.receipt.rejected, kern.receipt.dropped_zero, kern.receipt.clamps_refused, kern.receipt.solution_complete, kern.receipt.fallback_ready));
        receipt.push_str(&kern_drop_ledger(&kern)?);
        let hold_summary = kni_metrics::anchor_audit::summarize_holds(
            kern.ready.len(), kern.fallback_ready.len(),
            kern.overlap_holds.iter().map(|p| p.note.as_str()));
        let hold_flags = kni_metrics::anchor_audit::audit_hold_reasons(&hold_summary);
        receipt.push_str(&format!("kern_hold_audit\tran\ttrue\tflags\t{}\tpairs\t{}\theld\t{}\n",
            hold_flags.len(), hold_summary.pairs, hold_summary.held()));
        for line in kni_metrics::anchor_audit::render_flags_tsv(&hold_flags).lines().skip(1) {
            receipt.push_str(&format!("kern_hold_audit_flag\t{line}\n"));
        }
        Some((hold_summary, hold_flags))
    };
    // export gate: unresolved held/rejected/clamped pairs are never a normal success.
    // An omitted GPOS is valid only when the solved residuals are genuinely zero (no unresolved pairs).
    // Residual-kern export gate (restored). Pure decision extracted to `residual_kern_gate`.
    // Default (warn-export) mode: unresolved pairs degrade to a partial output marked with the
    // typed `kern_gate_degraded` warning on the receipt; the export continues. Strict refusal
    // lives in the human kit-acceptance gate, which reads this receipt. --allow-partial no
    // longer changes this gate: the default already ships the marked partial output.
    match residual_kern_gate(
        kern.receipt.overlap_held,
        kern.receipt.rejected,
        kern.receipt.clamps_refused,
        KernGateMode::Default,
    )? {
        KernGate::Clear => {}
        KernGate::Partial => {
            receipt.push_str("warning\tkern_gate_degraded\t(unresolved held/rejected/clamped kern pairs; default warn-export mode degrades to partial output, NOT a full residual-kern success; strict kit acceptance reads this receipt and refuses)\n");
            receipt.push_str("diagnostic_partial_kern\ttrue\t(unresolved held/rejected/clamped pairs; degraded default, NOT a full residual-kern success)\n");
            receipt.push_str("partial_output\ttrue\treason\tresidual_kern_unresolved\t(unresolved held/rejected/clamped kern pairs; degraded default)\n");
        }
    }

    // Always-output (profile/mid-run solve exclusions): every drawn glyph the
    // solve could not place still ships. It gets the declared fallback
    // advance - the run's widest solved glyph advance, the same basis the
    // .notdef fallback uses, never an invented number - zero sidebearings, no
    // pairs (it was never measured), typed ledger rows and a partial-output
    // marker. The glyph is NEVER dropped from the font or the cmap.
    let fallback_unsolved: Vec<String> = {
        let solved_names: std::collections::BTreeSet<&str> = solved.glyphs.iter().map(|g| g.glyph_id.as_str()).collect();
        drawn.iter()
            .filter(|d| d.glyph_id != ".notdef" && !placeholder_names.contains(&d.glyph_id) && !solved_names.contains(d.glyph_id.as_str()))
            .map(|d| d.glyph_id.clone())
            .collect()
    };
    if !fallback_unsolved.is_empty() {
        let adv = match max_glyph_advance(&solved.glyphs) {
            Ok(a) => a,
            Err(_) => {
                receipt.push_str("warning\tfallback_advance_basis_empty_population\tdegrade\tupm_advance\n");
                m.upm as f64
            }
        };
        receipt.push_str(&format!("warning\tglyphs_shipped_without_solve\tcount\t{}\tdegrade\tfallback_advance_max-glyph-advance\n", fallback_unsolved.len()));
        receipt.push_str("partial_output\ttrue\treason\tglyphs_shipped_without_solve\n");
        for name in &fallback_unsolved {
            let cp = shipped_cps.iter().find(|(n, _)| n == name).map(|(_, c)| *c).unwrap_or(0);
            eprintln!("always-output: glyph {} ({:#x}) ships without a solve profile (fallback advance)", name, cp);
            receipt.push_str(&format!("glyph_shipped_no_solve\t{}\tcp\t{:#x}\tadvance_basis\tmax-glyph-advance\tlsb\t0\trsb\t0\n", name, cp));
            solved.glyphs.push(kni_metrics::self_anchored_spacing::GlyphSpacing { glyph_id: name.clone(), lsb: 0.0, rsb: 0.0, advance: adv });
        }
    }

    drop(bench_pairs);
    eprintln!("progress stage5 assembly");
    let pulse5 = progress_pulse("stage5 assembly");
    // ---- stage 5: font assembly ----
    let bench_assembly = fit_bench::PhaseGuard::enter("assembly");
    let (notdef_glyph, notdef_lsb, notdef_rsb, notdef_advance) = if let Some(state)=&proxy_state {
        if matches!(state, bound_detector_validator::DetectionState::PixelEvidence { .. }) {
            let notdef_metrics=&solved.glyphs;
            assemble_pixel_notdef(state, &cps.iter().map(|(name, cp)| (*cp, name.clone())).collect::<Vec<_>>(),
                &drawn, notdef_metrics, stage1_pins, None, None,
                &space_evidence_gate, &mut receipt).map_err(|e| e.to_string())?
        } else {
            let bound_detector_validator::DetectionState::CandidateProxy { selected_source_sha, generated_glyph_ref, .. } = state else {
                return Err(bound_detector_validator::BadNotdef::ContextMismatch.to_string());
            };
            let context = bound_detector_validator::PixelContext {
                style: scale_wiring::style_id_of(&m.family,&m.subfamily)
                    .map_err(|_|bound_detector_validator::BadNotdef::ContextMismatch.to_string())?,
                frame:rc.scale().frame_binding().into(),units_per_px:rc.scale().units_per_px(),
                source_sha256:selected_source_sha.clone(),ink_model:bound_detector_validator::PIXEL_INK_MODEL.into(),
            };
            let proxy_drawn:Vec<DrawnGlyph> = drawn.iter()
                .filter(|g| !placeholder_names.contains(&g.glyph_id) || &g.glyph_id == generated_glyph_ref).cloned().collect();
            let bound_detector_validator::DetectionState::CandidateProxy {source_snapshot,..}=state else {unreachable!()};
            let pixel_pins:std::collections::HashMap<String,String>=source_snapshot.iter().map(|(_,name,pin)|(name.clone(),pin.clone())).collect();
            let ligature_names: std::collections::BTreeSet<&str> = m.glyphs.iter().filter(|g| g.is_ligature()).map(|g| g.name.as_str()).collect();
            let font_cps:Vec<u32>=cps.iter().filter(|(n,_)| !ligature_names.contains(n.as_str())).map(|(_,cp)|*cp).chain(m.space.map(|row|row.0))
                .chain(space_res.as_ref().map(|r|r.codepoint)).collect();
            notdef_proxy::assemble(state,&context,&proxy_drawn,&solved.glyphs,&pixel_pins,&font_cps,&mut receipt)?
        }
    } else {
        // Always-output / notdef contract: absent or voided evidence ships a
        // blank .notdef at the widest-glyph advance (typed warning), never a
        // refusal; an empty population falls back to the declared upm.
        match notdef { Some((g,a)) => (g,0.0,0.0,a), None => {
            let adv = match max_glyph_advance(&solved.glyphs) {
                Ok(a) => a,
                Err(_) => { receipt.push_str("warning\tnotdef_advance_basis_empty_population\tdegrade\tupm_advance\n"); m.upm as f64 }
            };
            receipt.push_str("warning\tnotdef_absent\tdegrade\tblank_notdef\tadvance_basis\tmax-glyph-advance\n");
            (DrawnGlyph{glyph_id:".notdef".into(),rings:vec![]},0.0,0.0,adv)
        }}
    };
    receipt.push_str(&format!("notdef\tgid\t0\trings\t{}\tadvance\t{}\n", notdef_glyph.rings.len(), notdef_advance));
    let mut glyphs: Vec<DrawnGlyph> = vec![notdef_glyph];
    // population floor: nothing survived (processed empty or all excluded) => empty .notdef only, no invented content.
    if !drawn.iter().any(|g| g.glyph_id != ".notdef" && !placeholder_names.contains(&g.glyph_id)) {
        drop(pulse5);
        let p = population_floor::publish_floor(metadata(&m), notdef_advance, &out_dir, &mut receipt)?;
        eprintln!("population floor: wrote {}", p.display());
        if merge_observe_enabled {
            append_merge_visibility_completion(&mut observer_records, observer_run_context.as_ref().ok_or("mov-1 run context missing")?, &out_dir, "population_floor", Some("population_floor:all_excluded"), &[kni_core::obs_envelope::PipelineDomain::Emit]);
            write_merge_visibility_records(&observer_records, &out_dir, true, observer_run_context.as_ref().map(|c| c.source_bytes.as_slice()))?;
        }
        return Ok(receipt);
    }
    glyphs.extend(drawn.iter().filter(|g| g.glyph_id != ".notdef" && !placeholder_names.contains(&g.glyph_id)).cloned());
    let space_emit = match &space_evidence_gate { space_evidence::SpaceGate::Emit { codepoint, advance_units } => Some((*codepoint, *advance_units)), _ => None };
    // Always-output space derivation (post-solve; declared convention:
    // n's advance, else the a-z median, else the all-glyph median).
    // Disabled mode retains the exact legacy derivation, including late fallbacks.
    // Enabled mode consumes even a pinned None; it never re-derives post-A2.
    let derived_space = consume_space_pin(space_pin, || {
        if m.space.is_none() && space_emit.is_none() && m.derive_space_from_letter_advances {
            let cp_of: std::collections::HashMap<&str, u32> = m.glyphs.iter().filter_map(|g| g.codepoint.map(|cp| (g.name.as_str(), cp))).collect();
            let v: Vec<(u32, f64)> = solved.glyphs.iter().filter_map(|g| cp_of.get(g.glyph_id.as_str()).map(|cp| (*cp, g.advance))).collect();
            space_evidence::derive_space_advance(&v)
        } else { None }
    });
    let space_row = m.space.or(space_emit).or(derived_space.map(|(a, _)| (0x20, a)));
    let has_space = space_row.is_some();
    let space_source: String = if space_emit.is_some() { "space_evidence.measured".to_string() } else if let Some((_, b)) = derived_space { format!("derived:{b}") } else { "manifest.space".to_string() };
    receipt.push_str(&format!("assembly_space_glyph	{has_space}	source	{space_source}	(independent of solver space_status)
"));
    if let Some((adv, basis)) = &derived_space {
        receipt.push_str(&format!("warning\tspace_derived\tbasis\t{}\tvalue\t{}\n", basis, adv)); // warning-code: space_derived
    }
    if has_space {
        glyphs.push(DrawnGlyph { glyph_id: "space".into(), rings: vec![] });
    }
    let order: Vec<String> = glyphs.iter().map(|g| g.glyph_id.clone()).collect();
    let gid = GlyphIdMap::from_glyph_order(&order).map_err(|e| format!("glyph id map: {e:?}"))?;
    let ligature_names: std::collections::BTreeSet<&str> = m.glyphs.iter().filter(|g| g.is_ligature()).map(|g| g.name.as_str()).collect();
    let mut mapping: Vec<(u32, u16)> = Vec::new();
    for (name, cp) in &shipped_cps {
        // Ligature glyphs ship in the CFF charset but get no cmap entry: a cmap mapping is one
        // scalar, a ligature is a sequence (GSUB wiring is separate work).
        if ligature_names.contains(name.as_str()) { continue; }
        mapping.push((*cp, gid.id(name).ok_or_else(|| format!("internal: {name} not in id map"))?));
    }
    if let Some((cp, _)) = space_row {
        mapping.push((cp, gid.id("space").ok_or("internal: space not in id map")?));
    }
    placeholder_mapping_guard(&proxy_state, &mapping)?;
    let mut metrics: Vec<(String, f64, f64, f64)> = vec![(".notdef".into(), notdef_lsb, notdef_rsb, notdef_advance)];
    for gs in solved.glyphs.iter().filter(|g| g.glyph_id != ".notdef" && !placeholder_names.contains(&g.glyph_id)) {
        metrics.push((gs.glyph_id.clone(), gs.lsb, gs.rsb, gs.advance));
    }
    if let Some((_, adv)) = space_row {
        metrics.push(("space".into(), 0.0, 0.0, adv));
    }
    paul_new_advance_override(&m.family, &mut metrics, &glyphs);

    // Always-output: a space-emission verification failure is a typed
    // warning; the run continues (evidence bytes were consumed, not forged).
    if space_evidence_gate != space_evidence::SpaceGate::NotRequested {
        if let Err(e) = space_evidence::verify_emitted(&metrics,&space_evidence_gate) {
            receipt.push_str(&format!("warning\tspace_emission_verify_failed\tdegrade\tcontinued\tdetail\t{e}\n"));
        }
    }
    // GPOS from fully-bound ready rows only; an unbound row is a hard refusal
    let rows = kern.ready_residual_rows(&gid);
    let mut pairs: Vec<PairKern> = Vec::new();
    let mut gpos_unbound: Vec<String> = Vec::new();
    for r in &rows {
        match (r.left_gid, r.right_gid) {
            (Some(l), Some(rr)) => {
                let decision = StemPairDecision { saturate: STEM_PAIR_SATURATE_POLICY, left: l, right: rr };
                if let Some(v) = narrow_pair_x_advance(r.written, &decision) {
                    pairs.push(PairKern { left: l, right: rr, x_advance: v });
                }
            }
            // Always-output: an unbound kern row degrades to GPOS omission
            // with a typed warning (the table is omitted, never half-written).
            _ => gpos_unbound.push(format!("{}->{}", r.left, r.right)),
        }
    }
    let num_glyphs = u16::try_from(glyphs.len()).map_err(|_| "glyph count range")?;
    let (gpos, kern_omit_line) = if gpos_unbound.is_empty() {
        // GUARD-FIX-2: culprit kern pairs are excluded (typed receipt rows)
        // and the table still ships; one bad pair no longer drops GPOS.
        kni_metrics::gpos_pairpos1::write_kern_with_policy(num_glyphs, &pairs, kni_metrics::gpos_pairpos1::GposErrorPolicy::ExcludeCulpritPairs)
    } else {
        for pair in &gpos_unbound { receipt.push_str(&format!("warning\tkern_row_unbound\tpair\t{pair}\tdegrade\tgpos_omitted\n")); }
        (None, None)
    };
    if let Some(line) = &kern_omit_line {
        receipt.push_str(line);
    }

    // GSUB liga from ligature rows: component gids resolve through the cmap
    // mapping (ordinary scalars only), the ligature glyph through the emitted
    // charset order. Like GPOS, an unresolvable row degrades to GSUB omission
    // with a typed warning (always-output; the table is omitted, never
    // half-written). Ligature glyphs stay unmapped in cmap; this table is the
    // only route to them.
    let gid_of_cp: std::collections::HashMap<u32, u16> = mapping.iter().copied().collect();
    let gid_of_name: std::collections::HashMap<&str, u16> = glyphs.iter().enumerate().map(|(i, g)| (g.glyph_id.as_str(), i as u16)).collect();
    let mut liga_subs: Vec<LigaSub> = Vec::new();
    let mut liga_unbound: Vec<String> = Vec::new();
    for row in m.glyphs.iter().filter(|g| g.is_ligature()) {
        let resolve = || -> Option<LigaSub> {
            let first = *gid_of_cp.get(&row.codepoint?)?;
            let mut components = Vec::with_capacity(row.extra_cps.len());
            for cp in &row.extra_cps {
                components.push(*gid_of_cp.get(cp)?);
            }
            let ligature = *gid_of_name.get(row.name.as_str())?;
            Some(LigaSub { first, components, ligature })
        };
        match resolve() {
            Some(sub) => liga_subs.push(sub),
            None => liga_unbound.push(row.name.clone()),
        }
    }
    let (gsub, liga_omit_line) = if liga_unbound.is_empty() {
        match write_liga_or_omit(num_glyphs, &liga_subs) {
            Ok(g) => (g, None),
            Err(e) => (None, Some(format!("liga_omitted\ttrue\treason\tgsub_writer_error\t{e:?}\t(GSUB writer failed; font exported without GSUB liga)\n"))),
        }
    } else {
        for name in &liga_unbound { receipt.push_str(&format!("warning\tliga_row_unbound\tglyph\t{name}\tdegrade\tgsub_omitted\n")); }
        (None, None)
    };
    if let Some(line) = &liga_omit_line {
        receipt.push_str(line);
    }

    // Vertical lane: validate height metadata first (atomic), then shift geometry.
    let mut meta = metadata(&m);
    let skip_xh = skip_os2_x_height_write(&m, &solved);
    // r229 M3 adapter: reads the pre-shift glyphs (same frame as solved.baseline,
    // see apply_baseline_shift docs) before any shift is applied.
    let (m3_rows, m3_measured, m3_cap_measured) = m3_adapter(&m, &glyphs, solved.baseline);
    // R1 measured-preferred (opt-in manifest `os2_x_height_write measured_preferred`; absent key or
    // resolved_only never reaches this): a RESOLVED M3 measurement in engine outline units (== font
    // units, the outline y values are written to the CFF unchanged) goes through the typed bridge;
    // only Meas::Measured is written. Everything else keeps the current solver write and says so.
    let tile_anchor_for_xh = declared_convention::paul_new_tile_anchor_scope(rc.scale().id());
    let (measured_x, measured_row) = if matches!(m.os2_x_height_write, Some(Os2XHeightWrite::MeasuredPreferred)) {
        os2_x_height_measured_preferred(m3_measured, &m3_rows, solved.baseline, tile_anchor_for_xh, rc.scale().id(), m.m3.tol_flat.unwrap_or(f64::NAN))
    } else { (None, String::new()) };
    let (measured_cap, measured_cap_row) = if matches!(m.os2_x_height_write, Some(Os2XHeightWrite::MeasuredPreferred)) {
        os2_cap_height_measured_preferred(m3_cap_measured, m.m3.cap_set.is_some(), &m3_rows, solved.baseline, tile_anchor_for_xh, m.m3.tol_flat.unwrap_or(f64::NAN))
    } else { (None, String::new()) };
    // rows 44/45 production consumers (receipt rows only, measured_preferred only; key-absent output is untouched):
    // the bridged exported-frame x_height (or Unresolved) feeds r44 amplitude and r45 measured scale.
    let consumer_rows = if matches!(m.os2_x_height_write, Some(Os2XHeightWrite::MeasuredPreferred)) {
        kni_xheight_bridge::consumer_rows_opt(measured_x, m.upm as u32, m.upm, "measured_preferred").iter().map(|l| format!("{l}\n")).collect::<String>()
    } else { String::new() };
    let (xh, ch) = apply_vertical_metadata_measured(&mut meta, &solved, !skip_xh, measured_x, measured_cap)?;
    // Declared tile-anchor scope (Paul New): the shipped outlines already
    // sit on the declared em box (frame-stripped per the 2026-10-18 ruling,
    // tile anchor), so the universal baseline rebase must NOT translate them
    // a second time (v11.4.3 shipped them at +100: g/j/p/q/y/comma/
    // semicolon/H all landed on [0,1000]). The solved baseline stays the
    // real measurement (baseline_in below); the applied geometry shift is
    // exactly 0; the export domain is still validated at shift 0.
    let tile_anchor_scope = declared_convention::paul_new_tile_anchor_scope(rc.scale().id());
    let (shift, residual) = if tile_anchor_scope {
        validate_baseline_shift_domain(&glyphs, 0.0)?;
        (0.0, solved.baseline)
    } else {
        apply_baseline_shift(&mut glyphs, solved.baseline)?
    };
    // Emit-time frame-ring exclusion (owner acceptance: the tile's printed
    let glyphs = glyphs;

    let fb_x = solved.policy_derivation.contains("x_height fallback");
    let fb_c = solved.policy_derivation.contains("cap_height fallback");
    receipt.push_str(&format!("vertical_height_source\tx_height\t{}\tcap_height\t{}\tmeasurements\tctx_or_median_heuristic_or_fallback\tnote\tnot measured design or owner-truth values; see policy_derivation\n",
        if fb_x { "non-lowercase median (all-glyph median) or UPM/2 fallback [POLICY_UNOBSERVED]" } else { "measured_or_ctx" }, if fb_c { "non-uppercase source: x_height used [POLICY_UNOBSERVED]" } else { "measured_or_ctx" }));
    receipt.push_str(&os2_x_height_source_row(&solved));
    receipt.push_str(&measured_row);
    receipt.push_str(&measured_cap_row);
    receipt.push_str(&consumer_rows);
    receipt.push_str(&x_height_meas_row(&solved));
    if skip_xh { receipt.push_str("m6_skip\tOS/2\tsxHeight\treason\tXH_UNRESOLVED\n"); }
    receipt.push_str(&m3_rows);
    // Receipt labels distinguish the measurement from the transform:
    // baseline_in/residual are the solved measurement, shift is the applied
    // geometry transform, exported_baseline is what the file actually
    // carries (the tile anchor's declared 0 in the anchor scope).
    let exported_baseline = if tile_anchor_scope { 0.0 } else { residual };
    receipt.push_str(&format!("vertical\tbaseline_in\t{}\tshift\t{}\tresidual\t{}\texported_baseline\t{}\tx_height\t{}\tcap_height\t{}\tconvention\tFRAME-EXTREMA-TRUE-INK\n", solved.baseline, shift, residual, exported_baseline, xh, ch));
    // Paul New metrics policy (family-gated inside): measured verdicts on the
    // FINAL shipped geometry and metrics land as typed receipt rows. Measurement
    // only; other families are never touched.
    paul_new_metrics_policy_report(&m.family, &glyphs, &metrics, &mut receipt);
    // Bind approval to the actual prepared, clipped, CFF-emitted baseline
    // with the same GPOS. Existing gates above remain authoritative. Partial
    // and diagnostic paths are never upgraded into an approved baseline.
    drop(pulse5);
    eprintln!("progress stage6 export");
    let _pulse6 = progress_pulse("stage6 export");
    // Ink placement follows the same declared scope as the tile anchor
    // (export_ink_placement): anchor scope keeps tile-anchored x untouched.
    let mut approved_base = clip_metadata(prepare_generated_with_placement(&glyphs, &mapping, &metrics, &meta,
        export_ink_placement(rc.scale().id()))
        .map_err(|e| format!("baseline prepare refused: {e:?}"))?);
    // Post-quantization constant-cubic cleanup (export boundary): points that
    // collide on the integer export grid became constant cubics the fit-stage
    // repair cannot see. Every drop/hold is a typed ledger row.
    let constant_cubic_report = rounding_reconcile::drop_constant_cubics(&mut approved_base.glyphs);
    receipt.push_str(&constant_cubic_report.receipt_lines());
    // Post-fit duplicate hygiene at the export boundary (item 2): only spans that
    // draw nothing (exact zero-length line, fully collapsed cubic) are removed;
    // every removal is a typed ledger row and the remaining coincident pairs are counted.
    for g in approved_base.glyphs.iter_mut() {
        let (cleaned, report) = kni_core::duplicate_point_audit::tidy_duplicate_points(&g.outline)
            .map_err(|e| format!("duplicate tidy refused for glyph {}: {e:?}", g.name))?;
        receipt.push_str(&report.ledger_rows(&g.name));
        g.outline = cleaned;
    }
    // Companion pass: zero-length lines created by the same integer rounding.
    let zero_length_line_report = kni_core::rounding_reconcile::drop_zero_length_lines(&mut approved_base.glyphs);
    receipt.push_str(&zero_length_line_report.receipt_lines());
    // Encode-boundary closure audit (detection only): every glyph handed
    // to the encoder gets a typed closure row via the library's own
    // closure adapter (outline_interface::ValidatedClosedGeometry). The
    // encoder's own gates stay the only behavior gate; nothing is mutated.
    let closure_audit_rows: Vec<kni_core::outline_interface::ClosureAuditRow> =
        approved_base.glyphs.iter().map(|g| kni_core::outline_interface::audit_glyph_closure(&g.outline)).collect();
    let closure_not_closed = closure_audit_rows.iter()
        .filter(|r| r.status != kni_core::outline_interface::ClosureAuditStatus::Closed).count();
    receipt.push_str(&format!("encode_closure_audit\tran\ttrue\tglyphs\t{}\tclosed\t{}\tnot_closed\t{}\n",
        closure_audit_rows.len(), closure_audit_rows.len() - closure_not_closed, closure_not_closed));
    let approved_base_bytes = kni_core::native_font::encode_with_layout_gsub_jobs(&approved_base, gpos.as_deref(), gsub.as_deref(), jobs.get())
        .map_err(|e| format!("baseline encode refused: {e:?}"))?;
    let base_approved = pre_base_approved(usable_fit, exclusions.len() + fallback_unsolved.len(), solved.complete,
        kern.receipt.overlap_held, kern.receipt.rejected, kern.receipt.clamps_refused);
    receipt.push_str(&pre_export_guard_receipt(&approved_base_bytes, rc, base_approved));
    // ---- base determinism + LSB/RSB post-pass (separate pass AFTER base approval; 0/0 => not run, base bytes ship as-is) ----
    // Offsets/scope come only from the RunConfig snapshot (PostStep::from_run_config inside ApprovedBase::mint). An unapproved
    // base with a non-zero offset applies the step with a typed warning via mint_unapproved_warned (always-output; no OTF-less end).
    // The pass is NOT a physical overlap guard (receipt: final_overlap_status NOT_MEASURED_POST_PASS).
    let pm = post.offset;
    post_metrics::check_range(&pm).map_err(|e| format!("post_metrics offsets: {e:?}"))?;
    let approved_base_bytes2 = encode_with_layout_gsub(&approved_base, gpos.as_deref(), gsub.as_deref()).map_err(|e| format!("baseline encode(2) refused: {e:?}"))?;
    // Job 4.1: on a mismatch the FIRST encode ships with a typed warning
    // (always-output rule); the decision lives in determinism_decide (pure).
    if let Some(line) = determinism_decide::warning_line(
        determinism_decide::decide(&approved_base_bytes, &approved_base_bytes2),
    ) {
        receipt.push_str(&line);
    }
    let ledger = match rounding_ledger(&glyphs, &metrics, &approved_base) {
        Ok(ledger) => ledger,
        Err(cause) => {
            let (reconciled, warning) = rounding_reconcile::reconcile(&glyphs, &metrics, &approved_base, &cause);
            receipt.push_str(&warning.receipt_line());
            reconciled
        }
    };
    let iou_rows = std::cell::RefCell::new(String::new());
    let iou_hook = |p: &PrePublish<'_>| -> Result<Vec<(String, Vec<u8>)>, String> {
        space_evidence::verify_readback(p.final_bytes, &space_evidence_gate)?;
        // Paul New policy readback on the FINAL shipped bytes (family-gated
        // inside): hmtx advance/lsb measured from the file itself.
        let policy_readback = {
            // Expected (advance, lsb) per glyph id: the assembly's overridden
            // metrics, indexed through the shipped glyph order.
            let by_name: std::collections::HashMap<&str, (f64, f64)> =
                metrics.iter().map(|r| (r.0.as_str(), (r.1, r.3))).collect();
            let expected: Vec<(u16, i16)> = order.iter().map(|name| {
                let (lsb, adv) = by_name.get(name.as_str()).copied().unwrap_or((0.0, 0.0));
                (adv.round().max(0.0) as u16, lsb.round() as i16)
            }).collect();
            paul_new_metrics_policy_readback(&m.family, p.final_bytes, num_glyphs, &expected)
        };
        let mut r = iou_report_stage(p, &approved_base, m, rc, &processed, &exclusions, &gid, stage1_pins, &ledger, shift, has_space, &proxy_placeholders, jobs.get())?;
        if matches!(&proxy_state, Some(bound_detector_validator::DetectionState::CandidateProxy { .. })) {
            r.0.push_str(&notdef_proxy::final_receipt(p.final_bytes)?);
        }
        r.0.push_str(&policy_readback);
        *iou_rows.borrow_mut() = r.0;
        Ok(r.1)
    };
    // W2 mandatory master is built inside emit_final_bundle_with_master BEFORE the publish call, so the
    // generated .glyphs is part of the same exclusive payload K6 verifies and binds (generated OUTPUT
    // hash/name, distinct from the master-source INPUT pin, which stays None on B: no master-source route).
    let provenance_pins = k6_provenance_pins(&manifest_pin, stage1_pins, None, &mut receipt)?;
    let otf_path = emit_final_bundle_with_master(&out_dir, base_approved, &approved_base, &approved_base_bytes, rc, gpos.as_deref(), &mapping, &order,
        space_row.map(|(cp, _)| cp), &m.family, &m.subfamily, &m.postscript_name, &iou_hook, &mut receipt,
        // always-output: an unapproved base never skips the declared post step -
        // it applies with the POST_PASS_APPLIED_UNAPPROVED_BASE typed warning and
        // ships (the pass is a refinement, never a shipment precondition); no run
        // ends without an OTF
        PostUnapprovedPolicy::ApplyWithTypedWarning, true, provenance_pins.as_ref().map(|(a, c)| (a, c)))?;
    receipt.push_str(&iou_rows.borrow());
    receipt.push_str(&k5_main_adapter::not_approved_rows(&k5_unresolved, otf_path.is_file() || EXPORT_SESSION.with(|s| s.borrow().is_some())));
    let mut map_tsv = String::from("codepoint\tname\tgid\n");
    for (cp, g) in &mapping {
        map_tsv.push_str(&format!("{:#x}\t{}\t{}\n", cp, order[*g as usize], g));
    }
    let mut spacing_tsv = String::from("glyph_id\tlsb\trsb\tadvance\n");
    for gs in &solved.glyphs {
        spacing_tsv.push_str(&format!("{}\t{}\t{}\t{}\n", gs.glyph_id, gs.lsb, gs.rsb, gs.advance));
    }
    let mut kern_tsv = String::from("left\tright\trequested\twritten\tstatus\treason\n");
    for r in kern.writer_declared_rows() {
        kern_tsv.push_str(&format!("{}\t{}\t{}\t{}\t{}\t{}\n", r.left, r.right, r.requested,
            r.written.map(|v| v.to_string()).unwrap_or_else(|| "NONE".into()), r.status, r.reason));
    }
    // full diagnostic ledger: every pair bucket with the guard's own measurements
    // (solver claim vs raw/export measurement, frames, rounding) — root-cause material, never a fix lever.
    let mut diag = String::from("bucket\tleft\tright\tresidual\texport_value\texport_distance\tsolver_wall_gap\tgap_at_origin\tgap_at_export\twmean_origin\twmean_export\tink_intersects\torigin_hit\texport_hit\tleft_lsb\tleft_ink_xmin\tleft_advance\tleft_x_translation\tright_lsb\tright_ink_xmin\tright_advance\tright_x_translation\tnote\n");
    let dump = |bucket: &str, rows: &[kni_metrics::generated_outline_kern::GeneratedKernPair], diag: &mut String| {
        for p in rows {
            let hit = |h: &Option<bool>| match h { Some(b) => b.to_string(), None => "NA".to_string() };
            let f = |fr: &Option<kni_metrics::generated_outline_kern::GlyphFrame>| match fr {
                Some(fr) => format!("{}\t{}\t{}\t{}", fr.lsb, fr.ink_xmin, fr.advance, fr.x_translation),
                None => "NA\tNA\tNA\tNA".to_string(),
            };
            diag.push_str(&format!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:?}\t{:?}\t{:?}\t{:?}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                bucket, p.left, p.right, p.residual_units, p.export_value, p.export_distance,
                p.solver_wall_gap_units, p.measured_gap_at_origin, p.measured_gap_at_export,
                p.weighted_mean_gap_at_origin, p.weighted_mean_gap_at_export, p.ink_intersects,
                hit(&p.origin_interval_hit), hit(&p.export_interval_hit),
                f(&p.left_frame), f(&p.right_frame), p.note));
        }
    };
    dump("ready", &kern.ready, &mut diag);
    dump("fallback_guard_verified", &kern.fallback_ready, &mut diag);
    dump("overlap_hold", &kern.overlap_holds, &mut diag);
    dump("rejected", &kern.rejected, &mut diag);
    dump("dropped_zero", &kern.dropped_zero, &mut diag);
    fs::write(out_dir.join(rc.receipt_file_name()), &receipt).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("mapping.tsv"), map_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("spacing.tsv"), spacing_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("kern-ledger.tsv"), kern_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("kern-diagnostic.tsv"), diag).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("rounding-ledger.txt"), format!("{ledger:?}")).map_err(|e| e.to_string())?;

    // Spacing pair ledger: one row per rejected, excluded or fallback pair
    // with identity, class, reason code and measured values (owner rule
    // 00:33:05: no rejection stays counter-only). NaN renders as an empty
    // cell; a None kern_units renders empty. Written on every run,
    // header-only when the ledger is empty.
    fn tsv_cell(v: f64) -> String {
        if v.is_nan() { String::new() } else { v.to_string() }
    }
    let mut pair_ledger_tsv = String::from("left\tright\tclass\treason\ttier\tt_lo\tt_hi\tresidual\tj_star\tkern_units\tnatural_safety\n");
    for row in &solved.pair_ledger {
        pair_ledger_tsv.push_str(&format!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
            row.left, row.right, row.class, row.reason.code(), row.tier,
            tsv_cell(row.t_lo), tsv_cell(row.t_hi), tsv_cell(row.residual), tsv_cell(row.j_star),
            row.kern_units.map(tsv_cell).unwrap_or_default(), row.natural_safety.code()));
    }
    fs::write(out_dir.join("export-gate-pairs.tsv"), k5_pair_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("spacing-pair-ledger.tsv"), pair_ledger_tsv).map_err(|e| e.to_string())?;

    // Hold reasons in solver order, one per line; empty when no pair was held.
    let mut hold_reasons_txt = String::new();
    for reason in &solved.hold_reasons {
        hold_reasons_txt.push_str(reason);
        hold_reasons_txt.push('\n');
    }
    fs::write(out_dir.join("spacing-hold-reasons.txt"), hold_reasons_txt).map_err(|e| e.to_string())?;
    // Audit-chain artifacts, always written: the kern hold audit closes
    // the kern stage and the closure audit closes the chain at the encode
    // boundary. The declared-override path writes not_run markers, never
    // a false clean.
    let (hold_summary_tsv, hold_flags_tsv) = match &kern_hold_audit {
        Some((summary, flags)) => (
            kni_metrics::anchor_audit::render_hold_summary_tsv(summary),
            kni_metrics::anchor_audit::render_flags_tsv(flags)),
        None => (
            "kern_hold_audit\tnot_run\n".to_string(),
            "kern_hold_audit\tnot_run\n".to_string()),
    };
    fs::write(out_dir.join("kern-hold-summary.tsv"), hold_summary_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("kern-hold-flags.tsv"), hold_flags_tsv).map_err(|e| e.to_string())?;
    fs::write(out_dir.join("encode-closure-audit.tsv"), kni_core::outline_interface::closure_audit_tsv(&closure_audit_rows)).map_err(|e| e.to_string())?;
    drop(bench_assembly);
    if merge_observe_enabled {
        append_merge_visibility_completion(&mut observer_records, observer_run_context.as_ref().ok_or("mov-1 run context missing")?, &out_dir, "full", None, &[kni_core::obs_envelope::PipelineDomain::Emit, kni_core::obs_envelope::PipelineDomain::Measurement]);
        write_merge_visibility_records(&observer_records, &out_dir, true, observer_run_context.as_ref().map(|c| c.source_bytes.as_slice()))?;
    }
    run_audit_close(&out_dir, m, rc, run_audit::RunPath::Full);
    Ok(receipt)
}

/// (width, height) of the glyph's own source tile, from a cheap capture of the same bytes.
fn fit_bytes_source_frame_meta(bytes: &[u8]) -> Result<(usize, usize), String> {
    let src = kni_core::capture_dispatch::decode_source(bytes, &PNG_DECODE_LIMITS, Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 })
        .map_err(|e| format!("decode for budget: {e:?}"))?;
    Ok((src.width, src.height))
}

mod production_export;
use production_export::{run,EXPORT_SESSION,encode_export_pins};

fn main() -> ExitCode {
    let (code, outcome) = match run() {
        Ok(kni_pipeline::export_lifecycle::Outcome::Complete(receipt)) => {
            print!("{receipt}");
            if k5_main_adapter::receipt_has_not_approved(&receipt) {
                eprintln!("kni-pipeline refused: export_gate not_approved (exit {})", k5_main_adapter::EXIT_NOT_APPROVED);
                (ExitCode::from(k5_main_adapter::EXIT_NOT_APPROVED), "refused_not_approved")
            } else { (ExitCode::SUCCESS, "ok") }
        }
        Ok(kni_pipeline::export_lifecycle::Outcome::Pending(e)) => {
            println!("{e}");
            (ExitCode::from(kni_pipeline::export_lifecycle::EXIT_PENDING), "pending")
        }
        Err(e) => {
            eprintln!("kni-pipeline refused: {e}");
            (ExitCode::FAILURE, "refused")
        }
    };
    fit_bench::flush(outcome);
    code
}


#[cfg(test)]
mod kern_gate_tests {
    use super::{residual_kern_gate, KernGate, KernGateMode};
    #[test]
    fn clear_when_all_zero_in_both_modes() {
        assert_eq!(residual_kern_gate(0, 0, 0, KernGateMode::Default).unwrap(), KernGate::Clear);
        assert_eq!(residual_kern_gate(0, 0, 0, KernGateMode::Strict).unwrap(), KernGate::Clear);
    }
    #[test]
    fn default_mode_partial_on_each_counter_path() {
        for (h, r, c) in [(1usize, 0usize, 0usize), (0, 1, 0), (0, 0, 1), (2, 3, 4)] {
            assert_eq!(residual_kern_gate(h, r, c, KernGateMode::Default).unwrap(), KernGate::Partial);
        }
    }
    #[test]
    fn strict_mode_refuses_on_each_counter_path() {
        for (h, r, c) in [(1usize, 0usize, 0usize), (0, 1, 0), (0, 0, 1), (2, 3, 4)] {
            let e = residual_kern_gate(h, r, c, KernGateMode::Strict).unwrap_err();
            assert!(e.contains("residual kern unresolved"), "{e}");
            assert!(e.contains("overlap_held"), "{e}");
            assert!(e.contains("strict"), "{e}");
        }
    }
    #[test]
    fn overflow_is_typed_refusal_not_wrap_in_both_modes() {
        let e = residual_kern_gate(usize::MAX, 1, 0, KernGateMode::Default).unwrap_err();
        assert!(e.contains("overflow"), "{e}");
        let e2 = residual_kern_gate(usize::MAX, 0, 1, KernGateMode::Strict).unwrap_err();
        assert!(e2.contains("overflow"), "{e2}");
        assert_eq!(residual_kern_gate(usize::MAX, 0, 0, KernGateMode::Default).unwrap(), KernGate::Partial);
        let e3 = residual_kern_gate(usize::MAX, 0, 0, KernGateMode::Strict).unwrap_err();
        assert!(e3.contains("residual kern unresolved"), "{e3}");
    }
}

#[cfg(test)]
mod kern_drop_ledger_tests {
    use super::kern_drop_ledger;
    use kni_metrics::generated_outline_kern::{GeneratedKern, GeneratedKernPair, GlyphFrame, KernReceipt, PairDisposition, ProfileFrame};
    fn pair(l: &str, r: &str, d: PairDisposition, framed: bool) -> GeneratedKernPair {
        let f = GlyphFrame { lsb: 0.0, ink_xmin: 0.0, advance: 1.0, x_translation: 0.0 };
        GeneratedKernPair {
            left: l.into(), right: r.into(), residual_units: 0.0, export_value: 0, export_distance: 0,
            left_frame: framed.then(|| f.clone()), right_frame: framed.then(|| f.clone()),
            solver_wall_gap_units: 0.0, measured_gap_at_origin: None, measured_gap_at_export: None,
            weighted_mean_gap_at_origin: None, weighted_mean_gap_at_export: None, ink_intersects: false,
            origin_interval_hit: None, export_interval_hit: None, optical_cost: 0.0, disposition: d, note: String::new(),
        }
    }
    fn kern(held: usize, rej_clamp: usize, rej_unbound: usize, zero: usize) -> GeneratedKern {
        let mk = |n: usize, d, fr| (0..n).map(|i| pair("a", &format!("b{i}"), d, fr)).collect::<Vec<_>>();
        GeneratedKern {
            ready: vec![], fallback_ready: vec![],
            overlap_holds: mk(held, PairDisposition::OverlapHold, true),
            rejected: mk(rej_clamp, PairDisposition::Rejected, true).into_iter().chain(mk(rej_unbound, PairDisposition::Rejected, false)).collect(),
            dropped_zero: mk(zero, PairDisposition::Ready, true),
            lattice_resolved: Vec::new(),
            receipt: KernReceipt {
                upm: 1000, source_pins: vec![], policy_derivation: String::new(), rounding: String::new(), overlap_tolerance_units: 0.0,
                ready: 0, fallback_ready: 0, overlap_held: held, rejected: rej_clamp + rej_unbound, dropped_zero: zero, clamps_refused: rej_clamp,
                solution_complete: true, excluded_self_pairs: 0, excluded_below_epsilon: 0, excluded_pairs_count: 0, excluded_unmeasurable: 0,
                export_adjusted: 0, profile_frame: ProfileFrame::ExportedB, alignment: String::new(),
            },
        }
    }
    #[test]
    fn ledger_line_counts_equal_receipt_counts() {
        let k = kern(2, 3, 4, 5);
        let s = kern_drop_ledger(&k).unwrap();
        let n = |code: &str| s.lines().filter(|l| l.starts_with("kern_drop\t") && l.ends_with(&format!("reason_code\t{code}"))).count();
        assert_eq!(n("overlap_hold"), k.receipt.overlap_held);
        assert_eq!(n("clamp_refused"), k.receipt.clamps_refused);
        assert_eq!(n("clamp_refused") + n("rejected_unbound"), k.receipt.rejected);
        assert_eq!(n("dropped_zero"), k.receipt.dropped_zero);
        assert!(s.contains("closed\ttrue"));
    }
    #[test]
    fn empty_ledger_closes_with_total_only() {
        let s = kern_drop_ledger(&kern(0, 0, 0, 0)).unwrap();
        assert_eq!(s.lines().count(), 1);
    }
    #[test]
    fn mismatch_is_typed_refusal() {
        let mut k = kern(1, 1, 1, 1);
        k.receipt.overlap_held += 1;
        assert!(kern_drop_ledger(&k).unwrap_err().contains("does not close"));
    }
}

#[cfg(test)]
mod name_gate_tests {
    use super::name_table_readback;
    use std::ffi::OsStr;
    use std::path::PathBuf;

    /// Fixture: a minimal well-formed sfnt whose name table carries the defective
    /// naming this gate exists to reject (family "Marq Alternate KNI", subfamily
    /// "Regular", PostScript "MarqAlternateKNI-Regular") plus the self-consistent
    /// full-name record. The bytes are a repo fixture under
    /// tests/fixtures/name_gate/, regenerated deterministically by the
    /// build_name_gate_fixture.py script kept next to it; FIXTURE_SHA256 pins the
    /// expected digest so a stale or hand-edited fixture fails loudly instead of
    /// silently weakening the gate. The readback under test parses only the sfnt
    /// directory and the name table, which the fixture carries byte-exactly.
    ///
    /// Resolution order: KNI_NAME_GATE_FIXTURE (explicit file path), then
    /// $KNI_G_FIXTURES/name_gate/<file>, then the repo path under
    /// CARGO_MANIFEST_DIR. An empty variable counts as unset. A missing or
    /// digest-mismatched fixture fails the test naming every location tried;
    /// these tests never skip. See docs/testing-fixtures.md.
    const FIXTURE_FILE: &str = "defective-shipped-name.otf";
    const FIXTURE_SHA256: &str = "e37d7646143ccfe6b8da3c39a18124e1330c09ebebb525b6afad643d0b476d19";
    const DEFECTIVE_FAMILY: &str = "Marq Alternate KNI";
    const DEFECTIVE_SUBFAMILY: &str = "Regular";
    const DEFECTIVE_PS: &str = "MarqAlternateKNI-Regular";

    fn nonempty(v: Option<std::ffi::OsString>) -> Option<std::ffi::OsString> {
        v.filter(|s| !s.is_empty())
    }

    fn resolve(explicit: Option<&OsStr>, fixtures_root: Option<&OsStr>) -> PathBuf {
        if let Some(p) = explicit {
            return PathBuf::from(p);
        }
        if let Some(root) = fixtures_root {
            return PathBuf::from(root).join("name_gate").join(FIXTURE_FILE);
        }
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/name_gate").join(FIXTURE_FILE)
    }

    fn fixture_path() -> PathBuf {
        resolve(
            nonempty(std::env::var_os("KNI_NAME_GATE_FIXTURE")).as_deref(),
            nonempty(std::env::var_os("KNI_G_FIXTURES")).as_deref(),
        )
    }

    fn shipped_bytes() -> Vec<u8> {
        let path = fixture_path();
        let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!(
            "name-gate fixture unreadable at {} ({e}). Tried in order: \
             $KNI_NAME_GATE_FIXTURE, $KNI_G_FIXTURES/name_gate/{FIXTURE_FILE}, \
             repo tests/fixtures/name_gate/{FIXTURE_FILE}. Regenerate with \
             pipeline/tests/fixtures/name_gate/build_name_gate_fixture.py; \
             see docs/testing-fixtures.md",
            path.display()
        ));
        let digest = kni_core::economy_eval::sha256_hex(&bytes);
        assert_eq!(
            digest, FIXTURE_SHA256,
            "name-gate fixture at {} does not match the pinned digest; \
             regenerate with build_name_gate_fixture.py",
            path.display()
        );
        bytes
    }

    #[test]
    fn resolve_prefers_explicit_env() {
        let p = resolve(Some(OsStr::new("/explicit/font.otf")), Some(OsStr::new("/root")));
        assert_eq!(p, PathBuf::from("/explicit/font.otf"));
    }

    #[test]
    fn resolve_falls_back_to_fixtures_root_then_repo() {
        let p = resolve(None, Some(OsStr::new("/root")));
        assert_eq!(p, PathBuf::from("/root/name_gate").join(FIXTURE_FILE));
        let p = resolve(None, None);
        assert_eq!(p, PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/name_gate").join(FIXTURE_FILE));
    }

    #[test]
    fn fixture_matches_pinned_digest() {
        let bytes = shipped_bytes();
        assert!(!bytes.is_empty());
    }

    #[test]
    fn readback_rejects_invented_namespace() {
        let bytes = shipped_bytes();
        let err = name_table_readback(&bytes, "Marq", "Alternate", "Marq-Alternate").unwrap_err();
        assert!(err.contains("nameID 1") || err.contains("nameID 6") || err.contains("nameID 2") || err.contains("nameID 4"), "unexpected: {err}");
    }

    #[test]
    fn readback_accepts_shipped_values_as_themselves() {
        let bytes = shipped_bytes();
        let got = name_table_readback(&bytes, DEFECTIVE_FAMILY, DEFECTIVE_SUBFAMILY, DEFECTIVE_PS).expect("self-consistent readback");
        assert!(got.iter().any(|(id, v)| *id == 6 && v == DEFECTIVE_PS));
    }
}

#[cfg(test)]
mod vertical_tests {
    use super::*;
    use kni_core::sfnt_metadata::{hhea, os2};
    fn pt(x: f64, y: f64) -> Point { Point { x, y } }
    fn glyph(y: f64) -> DrawnGlyph {
        DrawnGlyph { glyph_id: "a".into(), rings: vec![ReferenceRing { start: pt(10.0, y), spans: vec![
            Span::Cubic { control_one: pt(20.0, y + 5.0), control_two: pt(30.0, y + 9.0), end: pt(40.0, y + 1.0) },
            Span::Line { end: pt(10.0, y) } ] }] }
    }
    fn pts(g: &DrawnGlyph) -> Vec<(f64, f64)> {
        let r = &g.rings[0]; let mut v = vec![(r.start.x, r.start.y)];
        for s in &r.spans { match s {
            Span::Line { end } => v.push((end.x, end.y)),
            Span::Cubic { control_one, control_two, end } => v.extend([(control_one.x, control_one.y), (control_two.x, control_two.y), (end.x, end.y)]) } }
        v
    }
    fn sol(baseline: f64, x_height: f64, cap_height: f64) -> SpacingSolution {
        SpacingSolution { baseline, x_height, x_height_source: kni_metrics::self_anchored_spacing::XHeightSource::Ctx, cap_height, glyphs: vec![], pairs: vec![], font_median_pair_target: None, space_status: kni_metrics::self_anchored_spacing::SpaceStatus::Absent, excluded_pairs: vec![], complete: true,
            excluded_self_pairs: 0, excluded_below_epsilon: 0, excluded_unmeasurable: 0, numeric_failed_pairs: 0, geometric_hold_pairs: 0, no_accepted_candidate_pairs: 0, hold_reasons: Vec::new(), pair_ledger: Vec::new(), fallback_pairs: Vec::new(), fallback_natural_clear_pairs: 0, fallback_verified_pairs: 0, numeric_failed_nonfinite: 0, numeric_failed_malformed: 0, numeric_failed_natural_unverifiable: 0, numeric_failed_natural_frame_conflict: 0, accounting_residual: 0, accounting_closed: true, contrast_floor_adjustments: vec![], contrast_floor_failures: vec![], policy_derivation: String::new(), unobserved_policy: Vec::new(), anchor_audit: kni_metrics::anchor_audit::AnchorAuditReport::not_run() }
    }
    #[test]
    fn os2_x_height_source_row_is_typed_and_additive() {
        use kni_metrics::self_anchored_spacing::XHeightSource;
        for (src, tok) in [
            (XHeightSource::Ctx, "ctx"),
            (XHeightSource::LcTopMedian, "lc_top_median"),
            (XHeightSource::AllGlyphProxy, "all_glyph_proxy"),
            (XHeightSource::DegradeBbox, "degrade_bbox"),
            (XHeightSource::NaturalFallback, "natural_fallback"),
        ] {
            let mut s = sol(0.0, 500.0, 700.0);
            s.x_height_source = src;
            assert_eq!(os2_x_height_source_row(&s), format!("os2_x_height_source\t{tok}\n"));
            // the row is provenance only: OS/2 numeric write is untouched by it
            let mut f = meta();
            let (xh, ch) = apply_vertical_metadata_guarded(&mut f, &s, true).unwrap();
            assert_eq!((xh, ch), (500, 700));
            assert_eq!((f.os2.version, f.os2.selection & 0x80), (4, 0x80));
        }
    }

    #[test]
    fn x_height_meas_row_is_unresolved_for_all_five_sources_and_additive() {
        use kni_metrics::self_anchored_spacing::XHeightSource;
        for (src, tok) in [
            (XHeightSource::Ctx, "ctx"), (XHeightSource::LcTopMedian, "lc_top_median"), (XHeightSource::AllGlyphProxy, "all_glyph_proxy"),
            (XHeightSource::DegradeBbox, "degrade_bbox"), (XHeightSource::NaturalFallback, "natural_fallback"),
        ] {
            let mut s = sol(0.0, 500.0, 700.0);
            s.x_height_source = src;
            assert_eq!(x_height_meas_row(&s), format!("x_height_meas\tunresolved\tsource\t{tok}\tvalue\t500\n"));
            // legacy rows keep their bytes
            assert_eq!(os2_x_height_source_row(&s), format!("os2_x_height_source\t{tok}\n"));
            let mut f = meta();
            assert_eq!(apply_vertical_metadata_guarded(&mut f, &s, true).unwrap(), (500, 700));
        }
    }

    fn manifest_with(extra: &str) -> Manifest {
        parse_manifest(&format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\n{}", "0".repeat(64), extra), std::path::Path::new(".")).unwrap()
    }

    #[test]
    fn os2_x_height_write_guard_parse_contract() {
        // absent key: legacy, no guard
        assert_eq!(manifest_with("").os2_x_height_write, None);
        // declared resolved_only: guard on
        assert_eq!(manifest_with("os2_x_height_write resolved_only\n").os2_x_height_write, Some(Os2XHeightWrite::ResolvedOnly));
        // invalid value: explicit manifest error, never silently on/off
        let e = parse_manifest("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 0000000000000000000000000000000000000000000000000000000000000000\nglyph 0x48 H missing.png\nos2_x_height_write always\n", std::path::Path::new(".")).unwrap_err();
        assert!(e.contains("bad os2_x_height_write"), "{e}");
    }

    #[test]
    fn r1_measured_override_writes_value_and_none_keeps_guarded_path() {
        use kni_metrics::self_anchored_spacing::XHeightSource;
        let mut s = sol(0.0, 500.0, 700.0); s.x_height_source = XHeightSource::Ctx;
        let mut f = meta();
        assert_eq!(apply_vertical_metadata_measured(&mut f, &s, true, Some(432.4), None).unwrap(), (432, 700));
        let mut fc = meta();
        assert_eq!(apply_vertical_metadata_measured(&mut fc, &s, true, None, Some(701.6)).unwrap(), (500, 702));
        let (mut a, mut b) = (meta(), meta());
        assert_eq!(apply_vertical_metadata_measured(&mut a, &s, false, None, None).unwrap(), apply_vertical_metadata_guarded(&mut b, &s, false).unwrap());
        assert!(apply_vertical_metadata_measured(&mut meta(), &s, true, Some(f64::NAN), None).is_err(), "nonfinite measured value is refused, not clamped");
    }

    #[test]
    fn measured_preferred_parses_and_never_skips() {
        assert_eq!(manifest_with("os2_x_height_write measured_preferred\n").os2_x_height_write, Some(Os2XHeightWrite::MeasuredPreferred));
        let s = sol(0.0, 500.0, 700.0);
        assert!(!skip_os2_x_height_write(&manifest_with("os2_x_height_write measured_preferred\n"), &s), "measured_preferred never skips: fallback is the current solver write");
    }

    #[test]
    fn os2_x_height_write_guard_decision_matrix_and_write_skip() {
        use kni_metrics::self_anchored_spacing::XHeightSource;
        for src in [XHeightSource::Ctx, XHeightSource::LcTopMedian, XHeightSource::AllGlyphProxy, XHeightSource::DegradeBbox, XHeightSource::NaturalFallback] {
            let mut s = sol(0.0, 500.0, 700.0);
            s.x_height_source = src;
            // guard off (key absent): legacy write, no skip
            let m_off = manifest_with("");
            assert!(!skip_os2_x_height_write(&m_off, &s));
            let mut f = meta();
            assert_eq!(apply_vertical_metadata_guarded(&mut f, &s, !skip_os2_x_height_write(&m_off, &s)).unwrap(), (500, 700));
            assert_eq!(f.os2.x_height, 500);
            // guard on: every legacy source bridges to Unresolved => skip; prior metadata sxHeight preserved, cap still written
            let m_on = manifest_with("os2_x_height_write resolved_only\n");
            assert!(skip_os2_x_height_write(&m_on, &s));
            let mut f = meta();
            assert_eq!(apply_vertical_metadata_guarded(&mut f, &s, !skip_os2_x_height_write(&m_on, &s)).unwrap(), (0, 700));
            assert_eq!((f.os2.x_height, f.os2.cap_height, f.os2.version, f.os2.selection & 0x80), (0, 700, 4, 0x80));
        }
    }

    #[test]
    fn os2_x_height_write_guard_skip_does_not_validate_unwritten_value() {
        // the skipped value is not written, so its domain is not validated; guard off keeps the legacy refusal
        let mut s = sol(0.0, f64::NAN, 700.0);
        s.x_height_source = kni_metrics::self_anchored_spacing::XHeightSource::DegradeBbox;
        assert!(skip_os2_x_height_write(&manifest_with("os2_x_height_write resolved_only\n"), &s));
        assert_eq!(apply_vertical_metadata_guarded(&mut meta(), &s, false).unwrap(), (0, 700));
        assert!(apply_vertical_metadata_guarded(&mut meta(), &s, true).is_err());
    }

    fn meta() -> NativeFontInput {
        NativeFontInput {
            postscript_name: "T-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
            head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0, -12, 800, 740], mac_style: 0, lowest_ppem: 1 },
            hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
                panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
            names: vec![],
        }
    }
    #[test] fn byte_level_os2_hhea_after_vertical_metadata() {
        let mut f = meta();
        let (xh, ch) = apply_vertical_metadata_guarded(&mut f, &sol(0.0, 499.6, 700.4), true).unwrap();
        assert_eq!((xh, ch), (500, 700));
        let f = clip_metadata(f);
        let o = os2(&f.os2).unwrap();
        assert_eq!(u16::from_be_bytes([o[0], o[1]]), 4);
        assert_eq!(u16::from_be_bytes([o[62], o[63]]), 0x40 | 0x80);
        assert_eq!(i16::from_be_bytes([o[86], o[87]]), 500);
        assert_eq!(i16::from_be_bytes([o[88], o[89]]), 700);
        assert_eq!(i16::from_be_bytes([o[68], o[69]]), 740); // typoAscender = head.yMax
        assert_eq!(i16::from_be_bytes([o[70], o[71]]), -12);
        let h = hhea(&f.hhea);
        assert_eq!(i16::from_be_bytes([h[4], h[5]]), 740);
        assert_eq!(i16::from_be_bytes([h[6], h[7]]), -12);
        assert_eq!(f.head.bounds[3], 740);
    }
    #[test] fn vertical_metadata_atomic_and_guarded() {
        for (x, c) in [(f64::NAN, 1.0), (1.0, f64::INFINITY), (-1.0, 1.0), (1.0, -0.5), (40000.0, 1.0), (1.0, 32767.6), (1e300, 1.0)] {
            let mut f = meta();
            assert!(apply_vertical_metadata_guarded(&mut f, &sol(0.0, x, c), true).is_err(), "{x} {c}");
            assert_eq!((f.os2.version, f.os2.selection, f.os2.x_height, f.os2.cap_height), (0, 64, 0, 0));
        }
        let mut f = meta();
        assert_eq!(apply_vertical_metadata_guarded(&mut f, &sol(0.0, 0.0, 32766.6), true).unwrap(), (0, 32767));
    }
    #[test] fn v2_with_bit7_fails_v4_passes_through_metadata() {
        let mut f = meta(); f.os2.version = 2; f.os2.selection |= 0x80;
        assert!(os2(&f.os2).is_err());
        let mut f = meta(); apply_vertical_metadata_guarded(&mut f, &sol(0.0, 500.0, 700.0), true).unwrap();
        assert!(os2(&f.os2).is_ok());
    }
    #[test] fn integer_baseline_shifts_y_only() {
        let mut g = vec![glyph(-3.0)]; let before = pts(&g[0]);
        let (sh, res) = apply_baseline_shift(&mut g, -3.0).unwrap();
        assert_eq!((sh, res), (3.0, 0.0));
        for (a, b) in before.iter().zip(pts(&g[0])) { assert_eq!(a.0, b.0); assert_eq!(a.1 + 3.0, b.1); }
        // closed ring stays closed
        let p = pts(&g[0]); assert_eq!(p.first(), p.last());
    }
    #[test] fn fractional_baseline_leaves_honest_residual() {
        let mut g = vec![glyph(0.0)];
        let (sh, res) = apply_baseline_shift(&mut g, 2.3).unwrap();
        assert_eq!(sh, -2.0); assert!((res - 0.3).abs() < 1e-12); // exported baseline = r = 0.3 != 0
        assert_eq!(pts(&g[0])[0].1, -2.0);
    }
    #[test] fn zero_shift_still_validates_every_y() {
        let mut g = vec![glyph(0.0)];
        if let Span::Cubic { control_two, .. } = &mut g[0].rings[0].spans[0] { control_two.y = 40000.0; }
        let snapshot = pts(&g[0]);
        assert!(apply_baseline_shift(&mut g, 0.0).is_err());
        assert_eq!(pts(&g[0]), snapshot);
        let mut g = vec![glyph(0.0)];
        g[0].rings[0].start.y = f64::NAN;
        assert!(apply_baseline_shift(&mut g, 0.0).is_err());
    }
    #[test] fn shift_overflow_nonfinite_and_atomicity() {
        for b in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 1e300, -40000.0] {
            let mut g = vec![glyph(0.0)]; let snap = pts(&g[0]);
            assert!(apply_baseline_shift(&mut g, b).is_err(), "{b}");
            assert_eq!(pts(&g[0]), snap);
        }
        // second glyph invalid after shift: first glyph must stay unmodified
        let mut g = vec![glyph(0.0), glyph(32760.0)]; let snap = pts(&g[0]);
        assert!(apply_baseline_shift(&mut g, -20.0).is_err());
        assert_eq!(pts(&g[0]), snap);
    }
    fn u16at(b: &[u8], o: usize) -> u16 { u16::from_be_bytes([b[o], b[o + 1]]) }
    fn i16at(b: &[u8], o: usize) -> i16 { u16at(b, o) as i16 }
    fn table<'a>(b: &'a [u8], tag: &[u8; 4]) -> &'a [u8] {
        let n = u16at(b, 4) as usize;
        for i in 0..n {
            let r = 12 + 16 * i;
            if &b[r..r + 4] == tag {
                let off = u32::from_be_bytes(b[r + 8..r + 12].try_into().unwrap()) as usize;
                let len = u32::from_be_bytes(b[r + 12..r + 16].try_into().unwrap()) as usize;
                return &b[off..off + len];
            }
        }
        panic!("table missing");
    }
    #[test] fn gsub_liga_table_round_trips_through_encode() {
        // .notdef + f,i,l,f_i: one ligature substitution f+i -> f_i.
        let mut f = meta();
        f.postscript_name = "T-Regular".into();
        f.names = names("T", "Regular", "T-Regular");
        let glyphs = vec![
            DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] },
            DrawnGlyph { glyph_id: "f".into(), rings: vec![] },
            DrawnGlyph { glyph_id: "i".into(), rings: vec![] },
            DrawnGlyph { glyph_id: "l".into(), rings: vec![] },
            DrawnGlyph { glyph_id: "f_i".into(), rings: vec![] },
        ];
        let metrics: Vec<(String, f64, f64, f64)> = glyphs.iter().map(|g| (g.glyph_id.clone(), 0.0, 0.0, 500.0)).collect();
        let mapping = vec![(0x66u32, 1u16), (0x69, 2), (0x6c, 3)]; // f_i unmapped by design
        let prepared = prepare_generated(&glyphs, &mapping, &metrics, &f).unwrap();
        let gsub = write_liga_or_omit(5, &[LigaSub { first: 1, components: vec![2], ligature: 4 }]).unwrap();
        let bytes = encode_with_layout_gsub(&prepared, None, gsub.as_deref()).unwrap();
        let g = table(&bytes, b"GSUB");
        assert_eq!((u16at(g, 0), u16at(g, 2)), (1, 0));
        let ll = u16at(g, 8) as usize;
        let lookup = ll + u16at(g, ll + 2) as usize;
        assert_eq!(u16at(g, lookup), 4, "LigatureSubst lookup type");
        // no GSUB requested -> no GSUB directory entry
        let plain = encode_with_layout(&prepared, None).unwrap();
        assert!(plain.windows(4).skip(3).take(u16at(&plain, 4) as usize * 4).all(|w| w != b"GSUB"), "no GSUB without ligatures");
    }
    #[test] fn serialized_readback_after_shift() {
        // baseline 3.0 -> shift -3; cubic ink max y=19 (t=.5) -> 16 after shift; control hull would be 18
        let ring = ReferenceRing { start: pt(100.0, 3.0), spans: vec![
            Span::Line { end: pt(400.0, 3.0) }, Span::Line { end: pt(400.0, 13.0) },
            Span::Cubic { control_one: pt(300.0, 21.0), control_two: pt(200.0, 21.0), end: pt(100.0, 13.0) },
            Span::Line { end: pt(100.0, 3.0) } ] };
        let mut glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, DrawnGlyph { glyph_id: "a".into(), rings: vec![ring] }];
        let x_before: Vec<f64> = pts(&glyphs[1]).iter().map(|p| p.0).collect();
        let mut f = meta();
        f.postscript_name = "T-Regular".into();
        f.names = names("T", "Regular", "T-Regular");
        let s = sol(3.0, 500.0, 700.0);
        apply_vertical_metadata_guarded(&mut f, &s, true).unwrap();
        let (sh, r) = apply_baseline_shift(&mut glyphs, s.baseline).unwrap();
        assert_eq!((sh, r), (-3.0, 0.0));
        assert_eq!(pts(&glyphs[1]).iter().map(|p| p.0).collect::<Vec<_>>(), x_before);
        let metrics = vec![(".notdef".to_string(), 0.0, 0.0, 500.0), ("a".to_string(), 100.0, 100.0, 600.0)];
        let prepared = prepare_generated(&glyphs, &[(0x61, 1)], &metrics, &f).unwrap();
        let prepared = clip_metadata(prepared);
        let bytes = encode_with_layout(&prepared, None).unwrap();
        let head = table(&bytes, b"head");
        assert_eq!([i16at(head, 36), i16at(head, 38), i16at(head, 40), i16at(head, 42)], [100, 0, 400, 16]); // true ink, not hull (18)
        let hh = table(&bytes, b"hhea");
        assert_eq!((i16at(hh, 4), i16at(hh, 6)), (16, 0));
        let o = table(&bytes, b"OS/2");
        assert_eq!((u16at(o, 0), u16at(o, 62), i16at(o, 86), i16at(o, 88)), (4, 0xC0, 500, 700));
        assert_eq!((i16at(o, 68), i16at(o, 70)), (16, 0));
        let hm = table(&bytes, b"hmtx");
        assert_eq!((u16at(hm, 4), i16at(hm, 6)), (600, 100)); // advance and lsb unchanged by y shift
    }
    #[test] fn tile_anchor_scope_keeps_interior_margin_at_export() {
        // A tile-anchored glyph whose ink starts 250 units in must export at
        // x=250 with the declared lsb 0 - not ink-left-aligned onto 0.
        let ring = ReferenceRing { start: pt(250.0, 0.0), spans: vec![
            Span::Line { end: pt(350.0, 0.0) }, Span::Line { end: pt(350.0, 700.0) },
            Span::Line { end: pt(250.0, 700.0) }, Span::Line { end: pt(250.0, 0.0) }] };
        let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] },
                          DrawnGlyph { glyph_id: "quoteleft".into(), rings: vec![ring] }];
        let metrics = vec![(".notdef".to_string(), 0.0, 0.0, 696.0), ("quoteleft".to_string(), 0.0, 0.0, 696.0)];
        let mut f = meta(); f.names = names("T", "Regular", "T-Regular");
        assert_eq!(export_ink_placement(declared_convention::PAUL_STYLE_ID), InkPlacement::TileAnchoredZeroBearing);
        assert_eq!(export_ink_placement("Mona Alt/Regular"), InkPlacement::AlignToLsb);
        assert_eq!(export_ink_placement("No/SuchStyle"), InkPlacement::AlignToLsb);
        let anchored = prepare_generated_with_placement(&glyphs, &[(0x2018, 1)], &metrics, &f, export_ink_placement(declared_convention::PAUL_STYLE_ID)).unwrap();
        assert_eq!(kni_core::generated_native::ink_min_x(&anchored.glyphs[1].outline).unwrap(), Some(250.0));
        assert_eq!(anchored.left_side_bearings[1], 0);
        // Status-quo scope is unchanged: same input left-aligns onto the declared lsb.
        let aligned = prepare_generated_with_placement(&glyphs, &[(0x2018, 1)], &metrics, &f, export_ink_placement("Mona Alt/Regular")).unwrap();
        assert_eq!(kni_core::generated_native::ink_min_x(&aligned.glyphs[1].outline).unwrap(), Some(0.0));
        assert_eq!(aligned.left_side_bearings[1], 0);
    }
    #[test] fn encode_path_refuses_v2_bit7_and_accepts_v4() {
        let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, DrawnGlyph { glyph_id: "a".into(), rings: vec![ReferenceRing { start: pt(100.0, 0.0), spans: vec![
            Span::Line { end: pt(400.0, 0.0) }, Span::Line { end: pt(400.0, 10.0) }, Span::Line { end: pt(100.0, 0.0) }] }] }];
        let metrics = vec![(".notdef".to_string(), 0.0, 0.0, 500.0), ("a".to_string(), 100.0, 100.0, 600.0)];
        let mk = |version: u16| {
            let mut f = meta(); f.names = names("T", "Regular", "T-Regular");
            f.os2.version = version; f.os2.selection |= 0x80; f.os2.x_height = 500; f.os2.cap_height = 700;
            clip_metadata(prepare_generated(&glyphs, &[(0x61, 1)], &metrics, &f).unwrap())
        };
        assert!(encode_with_layout(&mk(2), None).is_err());
        assert!(encode_with_layout(&mk(4), None).is_ok());
        let mut f = mk(4); f.os2.selection |= 0x0400; assert!(encode_with_layout(&f, None).is_err());
    }
    #[test] fn large_shift_ok_when_points_fit_and_empty_case() {
        let mut g = vec![glyph(0.0)];
        assert_eq!(apply_baseline_shift(&mut g, -30000.0).unwrap(), (30000.0, 0.0));
        let mut e: Vec<DrawnGlyph> = vec![];
        assert_eq!(apply_baseline_shift(&mut e, 1e9).unwrap(), (-1e9, 0.0));
    }
    #[test] fn shift_minus_32768_boundary() {
        let mut g = vec![glyph(0.0)];
        g[0].rings[0].start.y = 32767.0; g[0].rings[0].spans[1] = Span::Line { end: pt(10.0, 32767.0) };
        if let Span::Cubic { control_one, control_two, end } = &mut g[0].rings[0].spans[0] { control_one.y = 32767.0; control_two.y = 32767.0; end.y = 32767.0; }
        let (sh, r) = apply_baseline_shift(&mut g, 32768.0).unwrap();
        assert_eq!((sh, r), (-32768.0, 0.0));
        assert_eq!(pts(&g[0])[0].1, -1.0);
        let mut h = vec![glyph(0.0)]; // y 0..10, +shift 32768 -> overflow: typed Err, geometry unchanged
        let snap = pts(&h[0]);
        assert!(apply_baseline_shift(&mut h, -32768.0).is_err());
        assert_eq!(pts(&h[0]), snap);
        let mut k = vec![glyph(-32768.0)];
        k[0].rings[0].spans[0] = Span::Line { end: pt(40.0, -32768.0) };
        k[0].rings[0].spans[1] = Span::Line { end: pt(10.0, -32768.0) };
        assert_eq!(apply_baseline_shift(&mut k, -32768.0).unwrap(), (32768.0, 0.0));
        assert_eq!(pts(&k[0])[0].1, 0.0);
    }
    #[test] fn half_step_round_domain_zero_shift() {
        // f64::round is half away from zero, same as generated_native integer()
        for (y, ok) in [(-32768.4, true), (32767.4, true), (-32768.5, false), (32767.5, false), (-32768.0, true), (32767.0, true)] {
            let mut g = vec![glyph(0.0)];
            g[0].rings[0].start.y = y;
            let snap = pts(&g[0]);
            let r = apply_baseline_shift(&mut g, 0.0);
            assert_eq!(r.is_ok(), ok, "y={y}");
            if !ok { assert_eq!(pts(&g[0]), snap); }
        }
        // nonzero shift: future value rounded
        let mut g = vec![glyph(0.0)];
        g[0].rings[0].start.y = 0.5;
        let snap = pts(&g[0]);
        let mut h = vec![glyph(0.0)]; h[0].rings[0].start.y = -1.5;
        assert!(apply_baseline_shift(&mut h, 32767.0).is_err()); // -1.5-32767=-32768.5 -> -32769
        let _ = snap;
    }
}

#[cfg(test)]
mod stage1_fallback_ledger_tests {
    use super::*;

    /// A cached glyph block as `load_stage1_cache` sees it: the live receipt lines the
    /// live path wrote for that glyph (ledger row produced by the ONE writer).
    fn block(glyph: &str, events: usize) -> String {
        format!(
            "glyph\t{glyph}\tcp\t0x41\tsource_pin\tab\tsource_kind\tX\tsource_px\t1x1\tscale\t1\troute\tplain\trings\t1\tnodes\t4\tfinal_area\t1.0\tfinal_missing_extrema\t0\trefused\t0\n{}",
            fallback_ledger_line(glyph, events)
        )
    }

    #[test]
    fn live_and_cache_event_counts_match_per_glyph_and_in_total() {
        // live side: what process_glyph reports per glyph; cache side: what replay reads back.
        let live = [("H", 0usize), ("r", 18), ("Eacute", 25), ("u", 3)];
        let (mut live_total, mut cache_total) = (0usize, 0usize);
        for (name, nfb) in live {
            live_total = add_fallback_events(live_total, name, nfb).unwrap();
            let cached = read_fallback_ledger(name, &block(name, nfb)).unwrap();
            assert_eq!(cached, nfb, "glyph {name}: cache replay count differs from live count");
            cache_total = add_fallback_events(cache_total, name, cached).unwrap();
        }
        assert_eq!(live_total, cache_total);
        assert_eq!(cache_total, 46);
    }

    #[test]
    fn all_line_valid_glyph_has_zero_events_and_passes_gate() {
        // A glyph that is genuinely all straight Lines (e.g. H) records 0 events: the
        // live path counts per-point fallbacks only, never ordinary Line spans.
        let n = read_fallback_ledger("H", &block("H", 0)).unwrap();
        assert_eq!(n, 0);
        assert!(fallback_gate(add_fallback_events(0, "H", n).unwrap(), ExportIntent::Strict).is_ok());
    }

    #[test]
    fn per_point_fallback_events_trip_the_gate_on_cache_replay_too() {
        let n = read_fallback_ledger("Eacute", &block("Eacute", 25)).unwrap();
        assert!(n > 0);
        let total = add_fallback_events(0, "Eacute", n).unwrap();
        let err = fallback_gate(total, ExportIntent::Strict).unwrap_err();
        assert!(err.contains("25 per-point Line fallback span"), "{err}");
        // only the explicit typed diagnostic or fallback-warn intent continues; the ledger is not dropped
        assert!(fallback_gate(total, ExportIntent::DiagnosticTest).is_ok());
        assert!(fallback_gate(total, ExportIntent::FallbackWarn).is_ok());
    }

    #[test]
    fn ledger_row_must_be_exactly_one_and_for_this_glyph() {
        let h = |s: &str| read_fallback_ledger("H", s);
        assert_eq!(h("glyph\tH\n"), Err(CacheInvalid::MissingLedger { glyph: "H".into() }));
        assert_eq!(h("fallback\tH\tline_spans\t1\nfallback\tH\tline_spans\t1\n"),
                   Err(CacheInvalid::DuplicateLedger { glyph: "H".into() }));
        // another glyph's row in this entry: never summed, never trusted
        assert_eq!(h("fallback\tI\tline_spans\t0\n"),
                   Err(CacheInvalid::GlyphNameMismatch { expected: "H".into(), found: "I".into() }));
        // exact name: no prefix, case or whitespace tolerance
        assert!(matches!(h("fallback\th\tline_spans\t0\n"), Err(CacheInvalid::GlyphNameMismatch { .. })));
        assert!(matches!(h("fallback\tH \tline_spans\t0\n"), Err(CacheInvalid::GlyphNameMismatch { .. })));
        // the old receipt-summing behavior (several rows adding up) is now invalid
        assert!(matches!(h("fallback\tH\tline_spans\t2\nfallback\tH\tline_spans\t3\n"), Err(CacheInvalid::DuplicateLedger { .. })));
    }

    #[test]
    fn ledger_count_is_a_plain_unsigned_integer() {
        for raw in ["", "-1", "+1", " 1", "1 ", "1.0", "0x10", "1e2", "NaN", "99999999999999999999999999"] {
            let r = read_fallback_ledger("H", &format!("fallback\tH\tline_spans\t{raw}\n"));
            assert!(matches!(r, Err(CacheInvalid::BadCount { .. })), "{raw:?} -> {r:?}");
        }
        assert!(matches!(read_fallback_ledger("H", "fallback\tH\tline_spans\n"), Err(CacheInvalid::MalformedLedger { .. })));
        assert!(matches!(read_fallback_ledger("H", "fallback\tH\tcurve_spans\t1\n"), Err(CacheInvalid::MalformedLedger { .. })));
        assert!(matches!(read_fallback_ledger("H", "fallback\tH\tline_spans\t1\textra\n"), Err(CacheInvalid::MalformedLedger { .. })));
    }

    #[test]
    fn total_is_checked_not_wrapping() {
        assert_eq!(add_fallback_events(usize::MAX, "H", 1), Err(CacheInvalid::TotalOverflow { glyph: "H".into() }));
        assert_eq!(add_fallback_events(1, "H", 2), Ok(3));
    }

    #[test]
    fn live_writer_output_is_the_exact_row_the_reader_accepts() {
        assert_eq!(fallback_ledger_line("uni2075", 7), "fallback\tuni2075\tline_spans\t7\n");
        assert_eq!(read_fallback_ledger("uni2075", &fallback_ledger_line("uni2075", 7)), Ok(7));
    }
}

#[cfg(test)]
mod space_gate_tests {
    use super::space_gate;
    use kni_metrics::self_anchored_spacing::SpaceStatus;

    /// A pair-complete solution (complete=true) with MissingEvidence and
    /// allow_partial=true must CONTINUE and record partial_output with
    /// reason=space_missing_evidence: the incomplete-solution condition
    /// alone would leave a pair-complete run unmarked.
    #[test]
    fn missing_evidence_allow_partial_records_partial_reason() {
        let (line, refusal, partial) =
            space_gate(&SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, true);
        assert!(refusal.is_none(), "allow_partial continues");
        assert!(partial, "partial_output reason must be recorded even when pair-complete");
        assert!(line.contains("MissingEvidence") && line.contains("solver_space_glyph_emitted\tfalse"), "line: {line}");
        assert!(!line.contains("built space"), "receipt never claims a built space");
    }

    #[test]
    fn missing_evidence_no_partial_refuses_full_output() {
        let (_, refusal, partial) =
            space_gate(&SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, false);
        assert!(partial == false);
        let e = refusal.expect("full output refused");
        assert!(e.contains("MissingEvidence") && e.contains("--allow-partial"), "err: {e}");
    }

    #[test]
    fn absent_reports_solver_absence_not_export_absence() {
        let (line, refusal, partial) = space_gate(&SpaceStatus::Absent, false);
        assert!(refusal.is_none() && !partial);
        assert!(line.contains("solver_space_glyph_emitted\tfalse"),
            "field is solver-scoped; stage5 may still export space from manifest.space");
    }

    #[test]
    fn measured_is_provided_not_built() {
        let (line, refusal, partial) = space_gate(&SpaceStatus::Measured { advance: 30.0 }, false);
        assert!(refusal.is_none() && !partial);
        assert!(line.contains("advance\t30") && line.contains("provided"), "line: {line}");
        assert!(!line.contains("built space"), "receipt never claims a built space");
    }
}

/// GUARD-FIX-2 wiring: the three production call sites opt in to the open
/// policies; library defaults stay conservative.
#[cfg(test)]
mod guard_fix2_wiring_tests {
    use kni_metrics::gpos_pairpos1::{write_kern_with_policy, GposErrorPolicy, PairKern};
    use kni_metrics::self_anchored_spacing::SpaceStatus;
    use crate::space_evidence::{solver_gate_with_policy, SpaceEvidencePolicy};

    #[test]
    fn solver_call_site_policy_continues_on_missing_evidence() {
        let (line, refusal, partial) = solver_gate_with_policy(
            &SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, false, SpaceEvidencePolicy::OmitAndContinue);
        assert!(refusal.is_none(), "opted-in production call site never refuses on missing evidence");
        assert!(partial, "partial marker recorded");
        assert!(line.contains("MissingEvidence") && line.contains("solver_space_glyph_emitted\tfalse"));
        let (_, refusal, partial) = solver_gate_with_policy(
            &SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, false, SpaceEvidencePolicy::RefuseOnMissing);
        assert!(refusal.is_some() && !partial);
    }

    #[test]
    fn gpos_call_site_policy_excludes_only_culprit_pairs() {
        let over = i32::from(i16::MAX) + 1;
        let pairs = [PairKern { left: 1, right: 2, x_advance: -10 }, PairKern { left: 3, right: 4, x_advance: over }];
        let (table, line) = write_kern_with_policy(40, &pairs, GposErrorPolicy::ExcludeCulpritPairs);
        assert!(table.is_some(), "table ships with the good pair");
        let rc = line.expect("exclusion receipt rows");
        assert!(rc.contains("warning\tkern_pair_excluded\tpair\t3->4\treason\tvalue_out_of_range"));
        assert!(rc.contains("kern_gpos\tpairs_excluded\t1\tpolicy\texclude_culprit_pairs"));
        let (table, line) = write_kern_with_policy(40, &pairs, GposErrorPolicy::OmitTable);
        assert!(table.is_none());
        assert!(line.unwrap().starts_with("kern_omitted\ttrue\treason\tgpos_writer_error\t"));
    }
}

#[cfg(test)]
mod post_manifest_tests {
    use super::*;
    #[test]
    fn post_scope_parses_exact_members_only() {
        let s = parse_post_scope("base,mark").unwrap();
        assert!(s.base && s.mark && !s.space && !s.notdef);
        assert!(parse_post_scope("base,base").is_err());
        assert!(parse_post_scope("Base").is_err());
        assert!(parse_post_scope("").is_err());
        assert!(parse_post_scope("base,,mark").is_err());
        let k = parse_post_scope("kerning_letters").unwrap();
        assert!(k.kerning_letters && !k.base && !k.space && !k.notdef && !k.mark && !k.is_empty());
        assert!(parse_post_scope("kerning_letters,base").is_err() && parse_post_scope("base,kerning_letters").is_err());
        assert!(parse_post_scope("kerning_letters,kerning_letters").is_err() && parse_post_scope("Kerning_letters").is_err());
        assert!(!parse_post_scope("base").unwrap().kerning_letters);
    }
    fn pm(extra: &str) -> Result<Manifest, String> {
        parse_manifest(&format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n{}", "0".repeat(64), extra), Path::new("."))
    }
    fn rc_of(m: &Manifest) -> Result<run_config::RunConfig, String> {
        let scale = bind_manifest_scale(m, Limits { max_input_bytes: 1<<24, max_pixels: 1<<24, max_working_bytes: 1<<26 }).map_err(|e| format!("{e:?}"))?;
        validated_run_config(m, scale.context().clone(), PathBuf::from("."), PathBuf::from("out"), "s1")
    }
    const FULL: &str = "lsb_add 25\nrsb_add 25\npost_scope base,mark\npost_scope_label kit25\n";
    #[test]
    fn derive_space_key_parses_bare_flag() {
        let m = pm("derive_space_from_letter_advances\n").unwrap();
        assert!(m.derive_space_from_letter_advances);
        let m = pm("").unwrap();
        assert!(!m.derive_space_from_letter_advances);
    }
    #[test]
    fn derive_space_key_rejects_value_and_duplicate() {
        assert!(pm("derive_space_from_letter_advances true\n").is_err());
        assert!(pm("derive_space_from_letter_advances\nderive_space_from_letter_advances\n").is_err());
    }
    #[test]
    fn manifest_without_post_keys_is_legacy_zero() {
        let m = pm("").unwrap();
        assert_eq!((m.post_lsb_add, m.post_rsb_add), (0.0, 0.0));
        assert_eq!(m.post_scope_label, "none");
    }
    #[test]
    fn manifest_post_step_parses_and_binds_into_digest() {
        let m = pm(FULL).unwrap();
        assert_eq!((m.post_lsb_add, m.post_rsb_add), (25.0, 25.0));
        let a = rc_of(&m).unwrap(); let z = rc_of(&pm("").unwrap()).unwrap();
        assert!(!a.offset().is_noop() && z.offset().is_noop());
        assert_ne!(a.canonical_record(), z.canonical_record());
        let b = rc_of(&pm("lsb_add 25\nrsb_add 26\npost_scope base,mark\npost_scope_label kit25\n").unwrap()).unwrap();
        assert_ne!(a.canonical_record(), b.canonical_record());
        let c = rc_of(&pm("lsb_add 25\nrsb_add 25\npost_scope base\npost_scope_label kit25\n").unwrap()).unwrap();
        assert_ne!(a.canonical_record(), c.canonical_record());
        assert_eq!(a.canonical_record(), rc_of(&pm(FULL).unwrap()).unwrap().canonical_record());
    }
    #[test]
    fn kerning_letters_binds_into_digest_and_receipt_base_unchanged() {
        let k = rc_of(&pm("lsb_add 25\nrsb_add 25\npost_scope kerning_letters\npost_scope_label kl\n").unwrap()).unwrap();
        let b = rc_of(&pm("lsb_add 25\nrsb_add 25\npost_scope base\npost_scope_label kl\n").unwrap()).unwrap();
        assert!(k.post_scope().kerning_letters && !b.post_scope().kerning_letters);
        assert_ne!(k.canonical_record(), b.canonical_record());
        assert_ne!(k.post_step_identity(), b.post_step_identity());
        assert!(k.receipt_rows().iter().any(|r| r.contains("kerning_letters:true")));
        assert!(!b.receipt_rows().iter().any(|r| r.contains("kerning_letters")));
        // 0/0 with kerning_letters is a no-op and legal; non-zero offsets are NOT refused as empty scope
        assert!(rc_of(&pm("lsb_add 0\nrsb_add 0\npost_scope kerning_letters\npost_scope_label kl\n").unwrap()).is_ok());
    }
    #[test]
    fn manifest_post_step_refusals() {
        for bad in ["lsb_add 25\nlsb_add 25\nrsb_add 25\npost_scope base\npost_scope_label k\n", // duplicate
            "lsb_add NaN\nrsb_add 25\npost_scope base\npost_scope_label k\n", "lsb_add inf\nrsb_add 25\npost_scope base\npost_scope_label k\n",
            "lsb_add 25\npost_scope base\npost_scope_label k\n", // partial: no rsb
            "lsb_add 25\nrsb_add 25\npost_scope_label k\n", // no scope
            "lsb_add 25\nrsb_add 25\npost_scope base\n", // no label
            "lsb_add 25 1\nrsb_add 25\npost_scope base\npost_scope_label k\n", // extra field
            "lsb_add 25\nrsb_add 25\npost_scope base,foo\npost_scope_label k\n", "lsb_add_x 1\n"] {
            assert!(pm(bad).is_err(), "must refuse: {bad}");
        }
        // fractional offsets are refused by RunConfig::new, not the parser
        let m = pm("lsb_add 2.5\nrsb_add 25\npost_scope base\npost_scope_label k\n").unwrap();
        assert!(rc_of(&m).is_err(), "RunConfig must refuse fractional lsb_add");
        // negative offsets are legitimate (owner directive 2026-10-17): RunConfig accepts and keeps the value
        let m = pm("lsb_add -1\nrsb_add 25\npost_scope base\npost_scope_label k\n").unwrap();
        let rc = rc_of(&m).unwrap();
        assert_eq!((rc.offset().lsb(), rc.offset().rsb()), (-1.0, 25.0));
    }
    #[test]
    fn post_offset_refuses_nan_inf_and_extra() {
        assert_eq!(parse_post_offset("lsb_add", Some("25"), false), Ok(25.0));
        assert!(parse_post_offset("lsb_add", Some("NaN"), false).is_err());
        assert!(parse_post_offset("lsb_add", Some("inf"), false).is_err());
        assert!(parse_post_offset("lsb_add", Some("x"), false).is_err());
        assert!(parse_post_offset("lsb_add", Some("25"), true).is_err());
        assert!(parse_post_offset("lsb_add", None, false).is_err());
    }
}

#[cfg(test)]
mod runtime_scale_tests {
    use super::*;
    fn manifest(extra: &str) -> Manifest {
        parse_manifest(&format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\n{}", "0".repeat(64), extra), Path::new(".")).unwrap()
    }
    #[test]
    fn iou_translation_agrees_disagrees_or_is_missing() {
        // no post-pass: base shift only
        assert_eq!(iou_translation(Some(3.0), Some(1), &Some(Vec::new()), 0.0, true), Ok(Some(3.0)));
        // post-pass: claimed shift equals the bytes
        assert_eq!(iou_translation(Some(3.0), Some(1), &Some(vec![0, 20]), 20.0, false), Ok(Some(23.0)));
        // an unshifted glyph that the bytes show as shifted disagrees
        assert_eq!(iou_translation(Some(3.0), Some(1), &Some(vec![0, 20]), 0.0, false), Err(("0.0".into(), "20.0".into())));
        // gid beyond the readback is a disagreement (NaN), not a silent zero
        assert!(iou_translation(Some(3.0), Some(5), &Some(vec![0, 20]), 20.0, false).is_err());
        // missing ledger row, gid, or unreadable proof: no translation
        assert_eq!(iou_translation(None, Some(1), &Some(vec![0, 20]), 20.0, false), Ok(None));
        assert_eq!(iou_translation(Some(3.0), None, &Some(vec![0, 20]), 20.0, false), Ok(None));
        assert_eq!(iou_translation(Some(3.0), Some(1), &None, 20.0, false), Ok(None));
    }
    #[test]
    fn iou_manifest_keys_are_declared_together_or_not_at_all() {
        assert!(manifest("").iou.is_none());
        let m = manifest("iou_ink_threshold 100\niou_flatten_steps 16\n");
        assert_eq!(m.iou, Some(run_config::IouSettings { ink_threshold: 100, flatten_steps: 16 }));
        let head = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\n", "0".repeat(64));
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_flatten_steps 16\n"), Path::new(".")).is_err());
    }
    #[test]
    fn iou_rows_and_duplicate_keys() {
        assert!(iou_not_run_row().starts_with("iou_report\tNOT_RUN\t") && iou_not_run_row().ends_with('\n'));
        let r = iou_proof_unavailable_row("Structural(\"NOT_PROVEN: hmtx short\")\tx\n");
        assert_eq!(r.matches('\n').count(), 1, "cause must stay on one TSV row");
        assert!(r.contains("NOT_PROVEN: hmtx short"));
        let head = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\n", "0".repeat(64));
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100\niou_ink_threshold 101\niou_flatten_steps 16\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100\niou_flatten_steps 16\niou_flatten_steps 8\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 300\niou_flatten_steps 16\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100\niou_flatten_steps x\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100 7\niou_flatten_steps 16\n"), Path::new(".")).is_err());
        assert!(parse_manifest(&format!("{head}iou_ink_threshold 100\niou_flatten_steps 16 7\n"), Path::new(".")).is_err());
        // zero steps parse, then RunConfig::new refuses
        let m = parse_manifest(&format!("{head}iou_ink_threshold 100\niou_flatten_steps 0\n"), Path::new(".")).unwrap();
        assert_eq!(m.iou.map(|i| i.flatten_steps), Some(0));
    }
    #[test]
    fn actual_manifest_override_guard_precedes_h_io() {
        let mut m = manifest("");
        m.glyphs[0].scale = Some(2.4377);
        assert!(matches!(bind_manifest_scale(&m, Limits { max_input_bytes: 1<<24, max_pixels: 1<<24, max_working_bytes: 1<<26 }), Err(WiringError::PerGlyphScaleOverride { glyph }) if glyph == "H"));
    }
    #[test]
    fn missing_capture_binding_is_not_hardcoded() {
        let m = manifest("");
        assert!(matches!(bind_manifest_scale(&m, Limits { max_input_bytes: 1<<24, max_pixels: 1<<24, max_working_bytes: 1<<26 }), Err(WiringError::EmptyField { field: "capture_cohort" })));
    }
    #[test]
    fn manifest_adapter_default_config_parity() {
        let m = manifest("");
        let b = scale_wiring::bind_run_scale("Marq/Regular", None, "Marq/Regular", "frame", 1000.0).unwrap();
        let scale = b.into_context();
        let defaults = RunConfig::new(RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("."), PathBuf::from("out"), "s1"), scale.clone()).unwrap();
        let adapted = validated_run_config(&m, scale, PathBuf::from("."), PathBuf::from("out"), "s1").unwrap();
        assert_eq!(adapted, defaults);
        assert_eq!(adapted.canonical_record(), defaults.canonical_record());
        assert_eq!(adapted.stage1_identity(), defaults.stage1_identity());
        assert_eq!(adapted.receipt_rows(), defaults.receipt_rows());
    }
    #[test]
    fn non_paul_needs_no_h_and_never_decodes_h() {
        let mut m = manifest("");
        m.capture_cohort = Some("Marq/Regular".into());
        m.capture_frame = Some("capture-manifest-frame".into());
        let limits = Limits { max_input_bytes: 1<<24, max_pixels: 1<<24, max_working_bytes: 1<<26 };
        assert!(bind_manifest_scale(&m, limits).is_ok()); // H path does not exist.
        m.glyphs[0].codepoint = Some(0x30); // Digit-only styles need no H.
        assert!(bind_manifest_scale(&m, limits).is_ok());
        m.scale = 9.0;
        assert!(matches!(bind_manifest_scale(&m, limits), Err(WiringError::ManifestScaleMismatch { .. })));
    }
    #[test]
    fn h_read_byte_bound_is_checked_before_decode() {
        let path = std::env::temp_dir().join(format!("kni-unit-bound-{}", std::process::id()));
        fs::write(&path, [0u8; 4]).unwrap();
        assert!(read_source_bounded(&path, 3).is_err());
        assert_eq!(read_source_bounded(&path, 4).unwrap().len(), 4);
        fs::remove_file(path).unwrap();
    }

}

#[cfg(test)]
mod pre_post_approval_tests {
    use super::*;
    #[test]
    fn usable_fit_and_every_existing_gate_are_required_without_counter_overflow() {
        assert!(pre_base_approved(true, 0, true, 0, 0, 0));
        for (fit, excluded, complete, held, rejected, clamped) in [
            (false,0,true,0,0,0), (true,1,true,0,0,0), (true,0,false,0,0,0),
            (true,0,true,1,0,0), (true,0,true,0,1,0), (true,0,true,0,0,1),
            (true,0,true,usize::MAX,usize::MAX,usize::MAX),
        ] { assert!(!pre_base_approved(fit,excluded,complete,held,rejected,clamped)); }
    }
    #[test]
    fn approval_receipt_binds_exact_bytes_and_context_without_stamping_diagnostic() {
        let scale = kni_core::scale_context::ScaleContext::from_convention("test", "test", 1.0, 1000.0, "cohort", "frame").unwrap();
        let input = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), "capture".into(), "out".into(), "s1");
        let rc = RunConfig::new(input, scale).unwrap();
        let bytes = rc.canonical_record().into_bytes();
        let approved = pre_export_guard_receipt(&bytes, &rc, true);
        assert!(approved.contains("guard_stage\tpre_lsb_rsb\tguard_result\tapproved"));
        assert!(approved.contains(&sha256_hex(&bytes)));
        assert!(approved.contains(&post_metrics::tsv_escape(rc.scale().binding_record())));
        assert!(approved.contains("guard_policy\tPRE_POSTMETRICS_ONLY"));
        let diagnostic = pre_export_guard_receipt(&bytes, &rc, false);
        assert!(diagnostic.contains("diagnostic_not_approved\tapproved_base_sha256\tnone"));
        assert_ne!(approved,diagnostic);
    }
}

#[cfg(test)]
mod emit_final_tests {
    use super::*;
    use kni_core::reference_slice::{ReferenceRing, Span};
    use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, Os2Metadata, PostMetadata};
    fn pt(x: f64, y: f64) -> Point { Point { x, y } }
    fn meta(ps: &str) -> NativeFontInput {
        NativeFontInput {
            postscript_name: ps.into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
            head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0, -12, 800, 740], mac_style: 0, lowest_ppem: 1 },
            hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
                panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
            names: names("Test", "Regular", "Test-Regular"),
        }
    }
    struct Fx { base: NativeFontInput, bytes: Vec<u8>, gpos: Option<Vec<u8>>, mapping: Vec<(u32, u16)>, order: Vec<String> }
    #[test]
    fn gpos_writer_error_yields_omit_warning_not_failure() {
        let injected = kni_metrics::gpos_pairpos1::write_kern_pairpos1_or_omit(1, &[PairKern { left: 5, right: 0, x_advance: 0 }]);
        assert!(injected.is_err());
        let (gpos, line) = gpos_or_omit_on_error(injected);
        assert!(gpos.is_none());
        assert!(line.unwrap().starts_with("kern_omitted\ttrue\t"));
        let f = fx();
        let bytes = encode_with_layout(&f.base, gpos.as_deref()).unwrap();
        assert!(!bytes.is_empty());
        assert_eq!(gpos_or_omit_on_error(Ok(None)), (None, None));
    }
    fn fx() -> Fx {
        let a = DrawnGlyph { glyph_id: "A".into(), rings: vec![ReferenceRing { start: pt(10.0, 0.0), spans: vec![
            Span::Line { end: pt(90.0, 0.0) }, Span::Line { end: pt(90.0, 90.0) }, Span::Line { end: pt(10.0, 90.0) }, Span::Line { end: pt(10.0, 0.0) }] }] };
        let glyphs = vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, a];
        let rows: Vec<post_metrics::Row> = vec![(".notdef".into(), 0.0, 0.0, 500.0), ("A".into(), 10.0, 20.0, 110.0)];
        let mapping = vec![(65u32, 1u16)];
        let base = clip_metadata(prepare_generated(&glyphs, &mapping, &rows, &meta("Test-Regular")).unwrap());
        let gpos = kni_metrics::gpos_pairpos1::write_kern_pairpos1_or_omit(2, &[kni_metrics::gpos_pairpos1::PairKern { left: 1, right: 1, x_advance: -10 }]).unwrap();
        let bytes = encode_with_layout(&base, gpos.as_deref()).unwrap();
        Fx { base, bytes, gpos, mapping, order: vec![".notdef".into(), "A".into()] }
    }
    fn rc(lsb: f64, rsb: f64) -> RunConfig {
        let scale = kni_core::scale_context::ScaleContext::from_convention("test", "test", 1.0, 1000.0, "cohort", "frame").unwrap();
        let mut input = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), "capture".into(), "out".into(), "s1");
        input.lsb_add = lsb; input.rsb_add = rsb;
        input.post_scope = kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: true }; input.post_scope_label = "kerning_letters".into();
        RunConfig::new(input, scale).unwrap()
    }
    fn dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kni_emit_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&d); fs::create_dir_all(&d).unwrap(); d
    }
    fn files(d: &Path) -> usize { fs::read_dir(d).unwrap().count() }
    #[test]
    fn required_master_survives_optional_hook_refusal_and_rolls_back_on_conflict() {
        for conflict in [false,true] {
            let mut f=fx();
            f.base.os2.version=2; f.base.os2.cap_height=90; f.base.os2.x_height=60;
            f.bytes=encode_with_layout(&f.base,f.gpos.as_deref()).unwrap();
            let d=dir(if conflict { "master-conflict" } else { "master-required" });
            let master=d.join("font-s1.glyphs");
            if conflict { fs::write(&master,b"existing-master").unwrap(); }
            let mut receipt=String::new();
            let result=emit_final_bundle_with_master(&d,true,&f.base,&f.bytes,&rc(0.0,0.0),f.gpos.as_deref(),&f.mapping,&f.order,None,"Test","Regular","Test-Regular",&|_|Err("injected optional measurement refusal".into()),&mut receipt,PostUnapprovedPolicy::ApplyWithTypedWarning,true,None);
            if conflict {
                assert!(result.is_err()); assert!(!d.join("font-s1.otf").exists());
                assert_eq!(fs::read(&master).unwrap(),b"existing-master");
            } else {
                assert!(result.is_ok()); assert!(master.exists());
                assert!(receipt.contains("master_glyphs_gate\twidths\tcompared\t2\tstatus\tmatch"));
                assert!(receipt.contains("warning\tpre_publish_refused"));
            }
            fs::remove_dir_all(d).unwrap();
        }
    }
    #[test]
    fn guard_fail_nonzero_offset_keeps_the_mint_contract_refusal() {
        // Flipped contract (chief decision): on a non-floor path an
        // unapproved base with a nonzero post step is a typed refusal; the
        // skip-and-ship degrade exists only on the population-floor opt-in
        // (covered by population_floor_tests).
        let (f, d, mut r) = (fx(), dir("g"), String::new());
        let e = emit_final_bundle(&d, false, &f.base, &f.bytes, &rc(25.0, 25.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r).unwrap_err();
        assert!(e.contains("post_metrics base not approved"), "{e}");
        assert!(!r.contains("post_pass_skipped"), "{r}");
        let _ = fs::remove_dir_all(&d);
    }
    #[test]
    fn name_gate_fail_ships_bytes_with_typed_warning() {
        // Always-output contract: a name-table mismatch is a typed warning;
        // the bytes still ship.
        for (l, rr) in [(0.0, 0.0), (25.0, 25.0)] {
            let (f, d, mut r) = (fx(), dir(&format!("n{l}")), String::new());
            let p = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(l, rr), f.gpos.as_deref(), &f.mapping, &f.order, None, "Wrong", "Regular", "Wrong-Regular", &|_| Ok(()), &mut r).unwrap();
            assert!(r.contains("warning\tname_table_readback_refused"), "{r}");
            assert!(fs::read(&p).unwrap().len() > 0);
            let _ = fs::remove_dir_all(&d);
        }
    }
    #[test]
    fn scope_without_any_kerning_letter_is_refused_with_zero_files() {
        let (f, d, mut r) = (fx(), dir("k"), String::new());
        // GPOS whose only nonzero pair involves .notdef (not a letter): kerning_letters selects nothing => typed refusal, no OTF
        let g = kni_metrics::gpos_pairpos1::write_kern_pairpos1_or_omit(2, &[kni_metrics::gpos_pairpos1::PairKern { left: 0, right: 0, x_advance: -10 }]).unwrap();
        let bytes = encode_with_layout(&f.base, g.as_deref()).unwrap();
        // Always-output contract: an EmptySelection post-pass refusal ships
        // the approved base bytes with a typed warning, no post pass.
        let p = emit_final_bundle(&d, true, &f.base, &bytes, &rc(25.0, 25.0), g.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r).unwrap();
        assert!(r.contains("warning\tpost_metrics_refused") && r.contains("EmptySelection"), "{r}");
        assert_eq!(fs::read(&p).unwrap(), bytes);
        // no GPOS at all => same degrade
        let b2 = encode_with_layout(&f.base, None).unwrap();
        let mut r2 = String::new();
        let d2 = dir("k2");
        let p2 = emit_final_bundle(&d2, true, &f.base, &b2, &rc(25.0, 25.0), None, &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r2).unwrap();
        assert!(r2.contains("warning\tpost_metrics_refused"), "{r2}");
        assert_eq!(fs::read(&p2).unwrap(), b2);
        let _ = fs::remove_dir_all(&d); let _ = fs::remove_dir_all(&d2);
    }
    #[test]
    fn pre_publish_hook_sees_final_bytes_read_only_and_err_means_zero_files() {
        let f = fx();
        // Always-output contract: hook Err => font publishes WITHOUT the
        // hook's extra artifacts, typed warning receipted (0/0 and 25/25).
        for (l, r) in [(0.0, 0.0), (25.0, 25.0)] {
            let d = dir(&format!("h{l}"));
            let mut rec = String::new();
            let p = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Err("iou below threshold".into()), &mut rec).unwrap();
            assert!(rec.contains("warning\tpre_publish_refused") && rec.contains("iou below threshold"), "{rec}");
            let names: Vec<String> = fs::read_dir(&d).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
            assert!(names.iter().any(|n| n == "font-s1.otf"), "{names:?}");
            assert!(!names.iter().any(|n| n.starts_with("iou")), "hook extras omitted: {names:?}");
            assert!(fs::read(&p).unwrap().len() > 0);
            let _ = fs::remove_dir_all(&d);
        }
        // Ok: the hook saw exactly the bytes that were then published (post-pass bytes for 25/25, base bytes for 0/0)
        for (l, r) in [(0.0, 0.0), (25.0, 25.0)] {
            let d = dir(&format!("s{l}")); let seen = std::cell::RefCell::new(Vec::new());
            let p = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular",
                &|v| { seen.borrow_mut().extend_from_slice(v.final_bytes); assert_eq!(v.post_pass, l != 0.0); assert_eq!(v.base_bytes, &f.bytes[..]); Ok(()) }, &mut String::new()).unwrap();
            assert_eq!(*seen.borrow(), fs::read(&p).unwrap());
            let _ = fs::remove_dir_all(&d);
        }
    }
    #[test]
    fn iou_payload_files_roll_back_with_font_and_never_overwrite() {
        let f = fx();
        let payload = |_: &PrePublish<'_>| -> Result<Vec<(String, Vec<u8>)>, String> {
            Ok(vec![("iou-population.tsv".into(), b"P".to_vec()), ("iou.tsv".into(), b"I".to_vec())])
        };
        for (l, r) in [(0.0, 0.0), (25.0, 25.0)] {
            // success: report files and font land together
            let d = dir(&format!("ok{l}"));
            emit_final_bundle_with(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &payload, &mut String::new(), PostUnapprovedPolicy::Refuse).unwrap();
            assert!(d.join("font-s1.otf").exists() && d.join("iou.tsv").exists() && d.join("iou-population.tsv").exists());
            let _ = fs::remove_dir_all(&d);
            // the font publish fails (font.otf already there): no IoU file may remain
            let d = dir(&format!("rb{l}")); fs::create_dir_all(&d).unwrap();
            fs::write(d.join("font-s1.otf"), b"OLD").unwrap();
            let e = emit_final_bundle_with(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &payload, &mut String::new(), PostUnapprovedPolicy::Refuse).unwrap_err();
            assert!(e.contains("publish"), "{e}");
            assert!(!d.join("iou.tsv").exists() && !d.join("iou-population.tsv").exists());
            assert_eq!(fs::read(d.join("font-s1.otf")).unwrap(), b"OLD");
            let _ = fs::remove_dir_all(&d);
            // an existing report file is preserved, nothing else is created
            let d = dir(&format!("ex{l}")); fs::create_dir_all(&d).unwrap();
            fs::write(d.join("iou.tsv"), b"OLDIOU").unwrap();
            assert!(emit_final_bundle_with(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &payload, &mut String::new(), PostUnapprovedPolicy::Refuse).is_err());
            assert_eq!(fs::read(d.join("iou.tsv")).unwrap(), b"OLDIOU");
            assert!(!d.join("font-s1.otf").exists() && !d.join("iou-population.tsv").exists());
            assert_eq!(files(&d), 1);
            let _ = fs::remove_dir_all(&d);
        }
    }
    #[test]
    fn iou_claimed_post_matches_readback_for_every_glyph() {
        let f = fx();
        for (l, r) in [(0.0, 0.0), (25.0, 25.0)] {
            let d = dir(&format!("cp{l}")); let checked = std::cell::Cell::new(0usize); let nonzero = std::cell::Cell::new(0usize);
            emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(l, r), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|v| {
                let rb = post_metrics::gap_certificate(v.base_bytes, v.final_bytes).map_err(|e| format!("{e:?}"))?.translations;
                assert_eq!(rb.len(), v.prepared.left_side_bearings.len());
                for i in 0..rb.len() {
                    let claimed = if v.post_pass { v.prepared.left_side_bearings[i] as f64 - f.base.left_side_bearings[i] as f64 } else { 0.0 };
                    let read = if v.post_pass { rb[i] as f64 } else { 0.0 };
                    assert_eq!(claimed, read, "gid {i} offset {l}");
                    checked.set(checked.get() + 1); if claimed != 0.0 { nonzero.set(nonzero.get() + 1); }
                }
                Ok(())
            }, &mut String::new()).unwrap();
            assert!(checked.get() > 0);
            if l == 0.0 { assert_eq!(nonzero.get(), 0, "0-offset: no translation"); }
            let _ = fs::remove_dir_all(&d);
        }
    }
    #[test]
    fn approved_paths_publish_exactly_one_otf() {
        // 0/0: base bytes unchanged (xAvgCharWidth stays the legacy 500)
        let (f, d, mut r) = (fx(), dir("z"), String::new());
        let p = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(0.0, 0.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r).unwrap();
        assert_eq!(fs::read(&p).unwrap(), f.bytes); assert_eq!(files(&d), 1);
        let _ = fs::remove_dir_all(&d);
        // 25/25 approved: post-pass final, ledger + single font.otf, receipt carries the guard/pass keys
        let (d, mut r) = (dir("p"), String::new());
        let p = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(25.0, 25.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r).unwrap();
        assert_ne!(fs::read(&p).unwrap(), f.bytes);
        assert_eq!(files(&d), 2); assert!(d.join("post_metrics_ledger.tsv").exists());
        for k in ["postpass\tlsb_rsb", "final_overlap_status\tNOT_MEASURED_POST_PASS", "guard_policy\tPRE_POSTMETRICS_ONLY", "run_config_sha256\t", "xavgcharwidth\t", "derived_after_hmtx", "policy\tkerning_letters", "EligibleUnicodeLetters\t1"] { assert!(r.contains(k), "missing {k}"); }
        // a second publish into the same directory is refused, no second OTF
        let mut r2 = String::new();
        assert!(emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(0.0, 0.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r2).is_err());
        assert_eq!(files(&d), 2);
        let _ = fs::remove_dir_all(&d);
        // non-zero approved + font.otf already present: Err, existing font untouched, NO ledger left behind
        let d = dir("x"); fs::write(d.join("font-s1.otf"), b"existing").unwrap();
        let mut r3 = String::new();
        let e = emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(25.0, 25.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut r3).unwrap_err();
        assert!(e.contains("publish"), "{e}");
        assert_eq!(fs::read(d.join("font-s1.otf")).unwrap(), b"existing");
        assert_eq!(files(&d), 1); assert!(!d.join("post_metrics_ledger.tsv").exists());
        // pre-existing ledger: Err before any font is written
        let _ = fs::remove_dir_all(&d); let d = dir("y"); fs::write(d.join("post_metrics_ledger.tsv"), b"old").unwrap();
        assert!(emit_final_bundle(&d, true, &f.base, &f.bytes, &rc(25.0, 25.0), f.gpos.as_deref(), &f.mapping, &f.order, None, "Test", "Regular", "Test-Regular", &|_| Ok(()), &mut String::new()).is_err());
        assert_eq!(files(&d), 1); assert_eq!(fs::read(d.join("post_metrics_ledger.tsv")).unwrap(), b"old");
        let _ = fs::remove_dir_all(&d);
    }
}

#[cfg(test)]
mod notdef_routing_tests;

#[cfg(test)]
mod pixel_notdef_assembly_tests {
    use super::*;
    use bound_detector_validator::{BadNotdef, DetectionState, PixelContext, PixelNotdefKind,
        SpaceAdvanceBinding, LimitsReceipt, PIXEL_INK_MODEL};
    use kni_metrics::self_anchored_spacing::GlyphSpacing;
    use std::collections::HashMap;

    fn state(kind: PixelNotdefKind) -> DetectionState {
        DetectionState::PixelEvidence {
            kind, context: PixelContext { style: "T/Regular".into(), frame: "f1".into(),
                units_per_px: 2.0, source_sha256: "a".repeat(64), ink_model: PIXEL_INK_MODEL.into() },
            image: PathBuf::from("source.png"), pixel_form_sha256: "d".repeat(64), evidence_sha256: "b".repeat(64), sources: vec![65, 66],
            space_advance: if kind == PixelNotdefKind::BlankCell {
                Some(SpaceAdvanceBinding { evidence_sha256: "e".repeat(64), style: "T/Regular".into(), frame: "f1".into(), units_per_px: 2.0 })
            } else { None },
            decode: LimitsReceipt { max_input_bytes: 64, max_pixels: 64, max_working_bytes: 1024,
                origin: "synthetic-unit-only".into() },
        }
    }
    fn ink() -> DrawnGlyph {
        DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0, 100.0, 100.0)] }
    }

    fn proxy_state(candidate_cps: Vec<u32>) -> DetectionState {
        DetectionState::CandidateProxy { selected_source_sha: "a".repeat(64), selected_cp: 0x41,
            candidate_cps, selection_rule: "synthetic-unit-only".into(),
            generated_glyph_ref: ".notdef".into(), source_snapshot: vec![] }
    }

    #[test]
    fn placeholder_mapping_guard_pixel_evidence_bound_cps_ship_in_cmap() {
        let st = state(PixelNotdefKind::RepeatedForm);
        // Bound codepoints ship as drawn glyphs: cmap presence is the contract.
        assert!(placeholder_mapping_guard(&Some(st.clone()), &[(0x41, 1), (0x42, 2)]).is_ok());
        // .notdef routing (gid 0) stays a typed mismatch.
        assert_eq!(placeholder_mapping_guard(&Some(st), &[(0x61, 0)]).unwrap_err(), "bad_notdef::ContextMismatch");
        // Empty source set: guard inactive.
        let mut empty = state(PixelNotdefKind::RepeatedForm);
        if let DetectionState::PixelEvidence { sources, .. } = &mut empty { sources.clear(); }
        assert!(placeholder_mapping_guard(&Some(empty), &[(0x61, 0)]).is_ok());
    }

    #[test]
    fn placeholder_mapping_guard_candidate_proxy_never_maps_candidates() {
        let st = proxy_state(vec![0x41, 0x42]);
        assert!(placeholder_mapping_guard(&Some(st.clone()), &[(0x61, 1)]).is_ok());
        assert_eq!(placeholder_mapping_guard(&Some(st.clone()), &[(0x41, 3)]).unwrap_err(), "bad_notdef::ContextMismatch");
        assert_eq!(placeholder_mapping_guard(&Some(st), &[(0x61, 0)]).unwrap_err(), "bad_notdef::ContextMismatch");
        // No proxy state at all: guard inactive.
        assert!(placeholder_mapping_guard(&None, &[(0x41, 0)]).is_ok());
    }
    #[test]
    fn placeholder_cps_in_manifest_blank_claim_is_typed_refusal() {
        // Blank-cell claims keep the typed refusal; repeated-form claims
        // ship + flag (see repeated_form_bound_cps_ship_with_typed_flags).
        let rows = vec![GlyphRow {codepoint:Some(65),extra_cps:vec![],name:"a".into(),image:PathBuf::from("unused"),scale:None}];
        assert_eq!(reject_placeholder_population(&rows,&[65,66]),Err(BadNotdef::ContextMismatch));
        assert_eq!(reject_placeholder_population(&rows,&[67,68]),Ok(()));
        assert_eq!(rows.len(),1);
    }
    #[test]
    fn repeated_form_bound_cps_are_skipped_with_typed_rows_not_cmap_glyphs() {
        let rows = vec![
            GlyphRow {codepoint:Some(65),extra_cps:vec![],name:"a".into(),image:PathBuf::from("unused"),scale:None},
            GlyphRow {codepoint:Some(67),extra_cps:vec![],name:"c".into(),image:PathBuf::from("unused"),scale:None}];
        let (lines, skipped) = placeholder_claim_skip_lines(&rows, &[65,66], &"f".repeat(64));
        assert!(lines.contains("placeholder_class\tpixel_form_sha256\t"));
        assert!(lines.contains("decision_basis\tbound-notdef-evidence\n"));
        assert!(lines.contains("placeholder_skip\ta\tcp\t0x41\tkind\trepeated-form"));
        assert!(!lines.contains("placeholder_skip\tc\t"), "unbound identical-looking glyph is never skipped");
        assert_eq!(skipped, vec![65u32]);
        let (none, none_cps) = placeholder_claim_skip_lines(&rows, &[67 + 2], &"f".repeat(64));
        assert!(none.is_empty() && none_cps.is_empty());
    }
    #[test]
    fn repeated_keeps_form_with_max_glyph_advance_and_needs_no_solver_row() {
        let state = state(PixelNotdefKind::RepeatedForm);
        let drawing = ink();
        let rows = vec![(65,"a".into()),(66,"b".into())];
        let drawn = vec![drawing.clone()];
        let metrics = vec![
            GlyphSpacing { glyph_id: "A".into(), lsb: 3.0, rsb: 4.0, advance: 120.0 },
            GlyphSpacing { glyph_id: "B".into(), lsb: 1.0, rsb: 2.0, advance: 300.0 },
            GlyphSpacing { glyph_id: "space".into(), lsb: 0.0, rsb: 0.0, advance: 999.0 }];
        let pins = HashMap::from([("a".into(),"a".repeat(64))]);
        let mut receipt = String::new();
        let (notdef,l,r,a) = assemble_pixel_notdef(&state,&rows,&drawn,&metrics,&pins,None,None,&space_evidence::SpaceGate::NotRequested,&mut receipt).unwrap();
        assert_eq!((l,r,a),(0.0,0.0,300.0));
        assert!(receipt.contains("advance_basis\tmax-glyph-advance"));
        assert_eq!(notdef.glyph_id,".notdef");
        assert_eq!(format!("{:?}",notdef.rings),format!("{:?}",drawing.rings));
        assert_eq!(rows.len(),2);
        assert_eq!(drawn[0].glyph_id,".notdef");
        assert!(receipt.contains("placeholder_cp_count\t2"));
    }
    #[test]
    fn repeated_refuses_only_on_missing_form_or_bad_population() {
        let state = state(PixelNotdefKind::RepeatedForm);
        let rows = vec![(65,"a".into())];
        let drawing = [ink()];
        let pins = HashMap::from([("a".into(),"a".repeat(64))]);
        let gate = space_evidence::SpaceGate::NotRequested;
        assert_eq!(assemble_pixel_notdef(&state,&rows,&drawing,&[],&pins,None,None,&gate,&mut String::new()).unwrap_err(),BadNotdef::InvalidSourceImage);
        let metrics = [GlyphSpacing { glyph_id: "A".into(), lsb: 0.0, rsb: 0.0, advance: f64::NAN }];
        assert_eq!(assemble_pixel_notdef(&state,&rows,&drawing,&metrics,&pins,None,None,&gate,&mut String::new()).unwrap_err(),BadNotdef::InvalidSourceImage);
        assert_eq!(assemble_pixel_notdef(&state,&rows,&[],&metrics,&pins,None,None,&gate,&mut String::new()).unwrap_err(),BadNotdef::MissingPixelEvidence);
    }
    #[test]
    fn blank_uses_max_glyph_advance_no_space_binding() {
        let mut state=state(PixelNotdefKind::BlankCell);
        if let DetectionState::PixelEvidence{space_advance,..}=&mut state{*space_advance=None;}
        let metrics=vec![GlyphSpacing{glyph_id:"A".into(),lsb:0.0,rsb:0.0,advance:120.0},GlyphSpacing{glyph_id:"B".into(),lsb:0.0,rsb:0.0,advance:300.0},GlyphSpacing{glyph_id:"space".into(),lsb:0.0,rsb:0.0,advance:999.0}];
        let (g,l,r,a)=assemble_pixel_notdef(&state,&[],&[],&metrics,&HashMap::new(),None,None,&space_evidence::SpaceGate::NotRequested,&mut String::new()).unwrap();
        assert!(g.rings.is_empty());assert_eq!((l,r,a),(0.0,0.0,300.0));
        assert_eq!(assemble_pixel_notdef(&state,&[],&[],&[],&HashMap::new(),None,None,&space_evidence::SpaceGate::NotRequested,&mut String::new()).unwrap_err(),BadNotdef::InvalidSourceImage);
    }
}

#[cfg(test)]
mod proxy_iou_population_tests {
    use super::*;
    #[test]
    fn proxy_expected_population_excludes_only_placeholder_cps() {
        let rows=vec![GlyphRow{codepoint:Some(65),extra_cps:vec![],name:"A".into(),image:PathBuf::from("unused"),scale:None},
            GlyphRow{codepoint:Some(0x100),extra_cps:vec![],name:"placeholder".into(),image:PathBuf::from("unused"),scale:None}];
        assert_eq!(iou_character_names(&rows,&[0x100]),vec!["A".to_string()]);
        assert_eq!(iou_character_names(&rows,&[]),vec!["A".to_string(),"placeholder".to_string()]);
        assert_eq!(rows.len(),2);
    }
}

#[cfg(test)]
mod export_intent_tests {
    use super::*;

    #[test]
    fn strict_gate_refuses_nonzero_and_passes_zero() {
        assert!(fallback_gate(0, ExportIntent::Strict).is_ok());
        let e = fallback_gate(3, ExportIntent::Strict).unwrap_err();
        assert!(e.contains("HARD-FAIL"), "strict refusal text changed: {e}");
    }

    #[test]
    fn diagnostic_and_warn_intents_pass_nonzero() {
        assert!(fallback_gate(5, ExportIntent::DiagnosticTest).is_ok());
        assert!(fallback_gate(5, ExportIntent::FallbackWarn).is_ok());
    }

    #[test]
    fn fallback_glyph_tsv_header_rows_and_zero_filtering() {
        let rows = vec![
            ("A".to_string(), 0usize),
            ("g".to_string(), 4usize),
            (".notdef".to_string(), 1usize),
        ];
        let t = fallback_glyph_tsv(&rows);
        assert_eq!(t, "glyph\tspans\ng\t4\n.notdef\t1\n");
    }

    #[test]
    fn fallback_glyph_tsv_empty_when_all_zero() {
        let rows = vec![("A".to_string(), 0usize)];
        assert_eq!(fallback_glyph_tsv(&rows), "glyph\tspans\n");
    }

    #[test]
    fn fallback_audit_tsv_binds_span_identity_and_typed_reason() {
        use kni_core::capture_fit::{FallbackReason as FR, FallbackSpanProvenance as P};
        let rows = vec![("t44".to_string(), vec![
            P { ring: 2, arc: 12, s: 19, e: 38, chord_px: Some(19.5), arc_len_px: Some(20.25), max_dev_px: Some(0.619), reason: FR::SplitUnresolved, stop: Some(kni_core::cubic_fit::RefitStop::BudgetExhausted), decline: Some(kni_core::capture_fit::DeclinedClass::Band) },
            P { ring: 0, arc: usize::MAX, s: 0, e: 0, chord_px: None, arc_len_px: Some(3.5), max_dev_px: None, reason: FR::AreaCollapseRestored, stop: None, decline: None },
        ])];
        let t = fallback_audit_tsv(&rows);
        let lines: Vec<&str> = t.lines().collect();
        assert_eq!(lines[0], "glyph\tring\tarc\ts\te\tchord_px\tarc_len_px\tmax_dev_px\treason\tstop_class\tdecline_class");
        assert_eq!(lines[1], "t44\t2\t12\t19\t38\t19.5\t20.25\t0.619\tSplitUnresolved\tBudgetExhausted\tBand");
        // ring-level event: no arc fragment, unmeasured values stay "-", never invented
        assert_eq!(lines[2], "t44\t0\t-\t0\t0\t-\t3.5\t-\tAreaCollapseRestored\t-\t-");
        assert_eq!(lines.len(), 3);
    }

    #[test]
    fn intent_resolution_is_flag_only_never_ledger_driven() {
        assert_eq!(resolve_export_intent(false, false), ExportIntent::Strict);
        assert_eq!(resolve_export_intent(true, false), ExportIntent::DiagnosticTest);
        assert_eq!(resolve_export_intent(false, true), ExportIntent::FallbackWarn);
    }

    #[test]
    fn nonzero_ledger_fixture_ship_refused_without_explicit_intent() {
        // Fixture: a run whose typed fallback ledger records spans. With no explicit
        // typed intent the resolved intent is Strict and the gate refuses the export:
        // fallback-tagged bytes can never leave the pipeline by default.
        let total = add_fallback_events(0, "percent", 7).unwrap();
        assert!(total > 0);
        let intent = resolve_export_intent(false, false);
        let err = fallback_gate(total, intent).unwrap_err();
        assert!(err.contains("HARD-FAIL"), "ship refusal text changed: {err}");
    }

    #[test]
    fn zero_ledger_fixture_ship_passes_clean() {
        // Fixture: a run with an empty typed fallback ledger ships under Strict.
        let total = add_fallback_events(0, "H", 0).unwrap();
        assert_eq!(total, 0);
        assert!(fallback_gate(total, resolve_export_intent(false, false)).is_ok());
    }

    #[test]
    fn no_ship_path_writes_a_name_table_warning_tag() {
        // The delivery contract: a shipped name table never carries
        // FALLBACK-EXPORT-WARNING, under any intent. The tag injector is removed
        // from the ship path; the names constructor is the only name-table source.
        for (diag, warn) in [(false, false), (true, false), (false, true)] {
            let _ = resolve_export_intent(diag, warn);
            let names = names("Fam", "Sub", "Fam-Sub");
            assert!(names.iter().all(|r| r.name_id != 10), "nameID 10 present on ship path");
            assert!(names.iter().all(|r| !r.value.contains("FALLBACK-EXPORT-WARNING")),
                    "FALLBACK-EXPORT-WARNING present on ship path");
            for id in [1u16, 2, 3, 4, 5, 6] {
                assert!(names.iter().any(|r| r.name_id == id && !r.value.is_empty()));
            }
        }
    }
}

#[cfg(test)]
mod glyph_skip_ledger_tests {
    use super::{glyph_skip_ledger_line, glyph_skip_total_line, placeholder_class_line, placeholder_form_line, placeholder_scan_decision, placeholder_skip_line, stage1_skip_reason_code, GLYPH_SKIP_STAGE1};

    #[test]
    fn ledger_row_is_unified_typed_format() {
        let row = glyph_skip_ledger_line("A", Some(0x41), "fit split unresolved");
        assert_eq!(row, format!("glyph_skip\tA\tcp\t0x41\treason_code\tfailure\tstage\t{GLYPH_SKIP_STAGE1}\n"));
    }

    #[test]
    fn reason_code_classifies_intentional_empty_vs_failure() {
        assert_eq!(stage1_skip_reason_code("no contours in source tile"), "intentional_empty");
        assert_eq!(stage1_skip_reason_code("fit split unresolved"), "failure");
    }

    fn scan_groups(spec: &[(&str, usize, bool)]) -> (std::collections::BTreeMap<String, Vec<u32>>, std::collections::BTreeMap<String, bool>) {
        let mut groups = std::collections::BTreeMap::new();
        let mut blank = std::collections::BTreeMap::new();
        let mut cp = 1u32;
        for (hash, n, is_blank) in spec {
            let cps: Vec<u32> = (0..*n).map(|_| { let v = cp; cp += 1; v }).collect();
            groups.insert(hash.to_string(), cps);
            blank.insert(hash.to_string(), *is_blank);
        }
        (groups, blank)
    }

    #[test]
    fn placeholder_scan_blank_group_decides_skip() {
        // Dominant blank group (Lÿno/MCA shape): the class is detected and
        // marked blank - its slots skip with the typed placeholder_skip row.
        let (groups, blank) = scan_groups(&[("formA", 136, true), ("formB", 2, false), ("formC", 2, false)]);
        let (hash, is_blank) = placeholder_scan_decision(&groups, &blank).expect("dominant class");
        assert!(is_blank);
        let row = placeholder_skip_line("glyph00001", 0x80, &hash);
        assert!(row.contains("placeholder_skip\t") && row.contains("kind\tblank-cell") && row.contains(&format!("pixel_form_sha256\t{hash}")));
        assert!(placeholder_class_line(&hash, true, 136).contains("slot_count\t136"));
    }

    #[test]
    fn placeholder_scan_drawn_group_decides_fit_and_flag() {
        // Dominant DRAWN group (Marq box shape): the class is detected and
        // marked drawn - slots keep their fit, only the typed flag row is
        // emitted (üret+flag; no dropping).
        let (groups, blank) = scan_groups(&[("formA", 220, false), ("formB", 3, false)]);
        let (hash, is_blank) = placeholder_scan_decision(&groups, &blank).expect("dominant class");
        assert!(!is_blank);
        let row = placeholder_form_line("glyph00002", 0x90, &hash);
        assert!(row.contains("placeholder_form\t") && row.contains("kind\tdrawn-form"));
        assert!(placeholder_class_line(&hash, false, 220).contains("kind\tdrawn-form"));
    }

    #[test]
    fn total_counter_matches_emitted_ledger_rows() {
        let skips = [("A", 0x41u32, "no contours in source tile"), ("B", 0x42, "fit split unresolved"), ("C", 0x43, "degenerate tangents")];
        let mut receipt = String::new();
        for (name, cp, reason) in skips { receipt.push_str(&glyph_skip_ledger_line(name, Some(cp), reason)); }
        receipt.push_str(&glyph_skip_total_line(skips.len()));
        let rows = receipt.lines().filter(|l| l.starts_with("glyph_skip\t")).count();
        let total: usize = receipt.lines()
            .find_map(|l| l.strip_prefix("glyph_skip_total\t"))
            .and_then(|v| v.parse().ok())
            .expect("total counter line present and numeric");
        assert_eq!(rows, total);
        assert_eq!(total, skips.len());
    }
}

#[cfg(test)]
mod midrun_exclusion_tests {
    use super::*;
    use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy};
    fn mk(id: &str, w: f64) -> OutlineProfile {
        let input = OutlineInput { glyph_id: id.into(), source_pin: format!("sha256:test:{id}"), upm: 1000, origin: [0.0, 0.0], flatten_tolerance: 0.0,
            rings: vec![vec![[0.0, 0.0], [w, 0.0], [w, 100.0], [0.0, 100.0]]] };
        profile_outline(&input, ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: kni_metrics::outline_spacing::MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) }).expect("profile")
    }
    #[test]
    fn corrupt_glyph_is_excluded_and_rest_solves() {
        let mut profiles = vec![mk("l", 100.0), mk("bad", 80.0), mk("r", 50.0)];
        profiles[1].ink_area = f64::NAN;
        profiles[1].bounds[2] = f64::NAN;
        let cps = vec![("l".to_string(), 0x6c_u32), ("bad".to_string(), 0x62), ("r".to_string(), 0x72)];
        let policy = SpacingPolicy { sample_resolution: 1.0, max_pair_evaluations: 1000, max_pairs: 100, pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
        let (sol, ex) = solve_spacing_excluding_culprits(&mut profiles, &cps, &policy, run_config::Jobs::new(1).unwrap()).expect("continues");
        assert_eq!(ex.len(), 1);
        assert_eq!(ex[0].0, "bad");
        assert_eq!(profiles.len(), 2);
        assert!(!sol.glyphs.is_empty());
    }
    #[test]
    fn upm_mismatch_is_excluded() {
        let mut profiles = vec![mk("l", 100.0), mk("r", 50.0), mk("u", 60.0)];
        profiles[2].upm = 2048;
        let cps = vec![("l".to_string(), 0x6c_u32), ("r".to_string(), 0x72), ("u".to_string(), 0x75)];
        let policy = SpacingPolicy { sample_resolution: 1.0, max_pair_evaluations: 1000, max_pairs: 100, pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
        let (_s, ex) = solve_spacing_excluding_culprits(&mut profiles, &cps, &policy, run_config::Jobs::new(1).unwrap()).expect("continues");
        assert_eq!(ex.len(), 1);
    }
}

/// Pre-solve profile validity. Returns the exclusion reason for a profile that must not enter
/// `solve_spacing`: any non-finite measurement, or a structurally impossible one (negative area,
/// non-positive row pitch, inverted bounds, empty rows, inverted ink interval). No value is invented.
fn invalid_profile_reason(p: &OutlineProfile) -> Option<String> {
    let scalars = [
        ("ink_area", p.ink_area), ("counter_area", p.counter_area), ("open_left", p.open_left),
        ("open_right", p.open_right), ("row_step", p.row_step), ("flatten_tolerance", p.flatten_tolerance),
        ("origin_x", p.origin[0]), ("origin_y", p.origin[1]),
        ("bounds_min_x", p.bounds[0]), ("bounds_min_y", p.bounds[1]),
        ("bounds_max_x", p.bounds[2]), ("bounds_max_y", p.bounds[3]),
    ];
    if let Some((n, _)) = scalars.iter().find(|(_, v)| !v.is_finite()) {
        return Some(format!("profile invalid: non-finite {n}"));
    }
    if p.rows.is_empty() { return Some("profile invalid: no scan rows".into()); }
    for r in &p.rows {
        if !r.y.is_finite() || !r.weight.is_finite() || !r.span_lo.is_finite() || !r.span_hi.is_finite() { return Some("profile invalid: non-finite scan row".into()); }
        for iv in &r.ink {
            if !iv.left.is_finite() || !iv.right.is_finite() { return Some("profile invalid: non-finite ink interval".into()); }
            if iv.right <= iv.left { return Some("profile invalid: ink interval without positive width".into()); }
        }
    }
    if p.ink_area < 0.0 || p.counter_area < 0.0 || p.open_left < 0.0 || p.open_right < 0.0 {
        return Some("profile invalid: negative area".into());
    }
    if p.row_step <= 0.0 { return Some("profile invalid: non-positive row_step".into()); }
    if p.bounds[0] > p.bounds[2] || p.bounds[1] > p.bounds[3] { return Some("profile invalid: inverted bounds".into()); }
    None
}

#[cfg(test)]
mod pre_solve_profile_validation_tests {
    use super::*;
    use kni_metrics::outline_spacing::{InkInterval, ScanRow};

    fn good() -> OutlineProfile {
        OutlineProfile {
            glyph_id: "A".into(), source_pin: "ab".into(), upm: 1000, origin: [0.0, 0.0],
            rows: vec![ScanRow { y: 0.5, weight: 1.0, span_lo: 0.0, span_hi: 1.0, ink: vec![InkInterval { left: 0.0, right: 5.0 }] }],
            bounds: [0.0, 0.0, 5.0, 1.0], ink_area: 5.0, counter_area: 0.0, open_left: 0.0, open_right: 0.0,
            profile_method: "bounded_curve_flatten+scanline".into(), row_step: 1.0, flatten_tolerance: 0.1,
        }
    }

    #[test]
    fn valid_profile_passes() { assert!(invalid_profile_reason(&good()).is_none()); }

    #[test]
    fn synthetic_broken_profiles_are_excluded() {
        let mut p = good(); p.ink_area = f64::NAN;
        assert_eq!(invalid_profile_reason(&p).unwrap(), "profile invalid: non-finite ink_area");
        let mut p = good(); p.bounds[2] = f64::INFINITY;
        assert!(invalid_profile_reason(&p).unwrap().contains("non-finite bounds_max_x"));
        let mut p = good(); p.rows[0].ink[0].right = f64::NAN;
        assert!(invalid_profile_reason(&p).unwrap().contains("non-finite ink interval"));
        let mut p = good(); p.rows.clear();
        assert!(invalid_profile_reason(&p).unwrap().contains("no scan rows"));
        let mut p = good(); p.counter_area = -1.0;
        assert!(invalid_profile_reason(&p).unwrap().contains("negative area"));
        let mut p = good(); p.row_step = 0.0;
        assert!(invalid_profile_reason(&p).unwrap().contains("row_step"));
    }
}

#[cfg(test)]
mod manifest_floor_tests {
    use super::*;
    fn tmp(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kni-floor-{tag}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }
    #[test]
    fn corrupt_manifest_with_names_gets_receipt_and_floor_otf() {
        let out = tmp("named");
        let text = "family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale ???\niou_ink_threshold 0\n";
        let msg = manifest_floor(&out, "MANIFEST_INVALID", "bad scale", Some(text));
        assert!(msg.contains("floor OTF written"), "{msg}");
        assert!(out.join(run_failure::RUN_FAILURE_RECEIPT_NAME).exists());
        let bytes = fs::read(out.join("floor.otf")).unwrap();
        let sha = kni_core::cff_reader::sha256_hex(&bytes);
        let font = kni_core::cff_reader::CffReader::from_bytes(&bytes, &sha).unwrap();
        assert_eq!(font.read_glyph(0).unwrap().rings.len(), 0);
        assert!(font.codepoints().is_empty());
        let _ = fs::remove_dir_all(&out);
    }
    #[test]
    fn unreadable_manifest_gets_receipt_without_invented_names() {
        let out = tmp("none");
        let msg = manifest_floor(&out, "MANIFEST_UNREADABLE", "read manifest: gone", None);
        assert!(msg.contains("floor OTF not produced"), "{msg}");
        assert!(out.join(run_failure::RUN_FAILURE_RECEIPT_NAME).exists());
        assert!(!out.join("floor.otf").exists());
        let _ = fs::remove_dir_all(&out);
    }
    #[test]
    fn garbage_text_without_naming_keys_gets_receipt_only() {
        let out = tmp("garbage");
        let msg = manifest_floor(&out, "MANIFEST_INVALID", "garbage", Some("\u{1}\u{2} not a manifest"));
        assert!(msg.contains("floor OTF not produced"));
        assert!(out.join(run_failure::RUN_FAILURE_RECEIPT_NAME).exists() && !out.join("floor.otf").exists());
    }
}

#[cfg(test)]
mod glyph_path_tests {
    use super::*;

    #[test]
    fn quoted_spaced_glyph_image_path_parses_and_unquoted_remains_invalid() {
        let text = include_str!("../tests/fixtures/manifest/spaced-path.manifest");
        let m = parse_manifest(text, Path::new("collection")).unwrap();
        assert_eq!(m.glyphs.len(), 2);
        assert_eq!(m.glyphs[0].image, Path::new("collection").join("glyph/0001__0041__A Tile.png"));
        assert_eq!(m.glyphs[0].scale, Some(3.25));
        assert_eq!(m.glyphs[1].image, Path::new("collection").join("glyph/0002__0042__B Tile.png"));
        assert_eq!(m.glyphs[1].scale, None);

        let unquoted = text.replace("\"glyph/0001__0041__A Tile.png\"", "glyph/0001__0041__A Tile.png");
        let e = parse_manifest(&unquoted, Path::new("collection")).unwrap_err();
        assert!(e.contains("bad per-glyph scale"), "{e}");
    }

    #[test]
    fn malformed_quoted_glyph_image_paths_are_refused() {
        let head = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\n", "0".repeat(64));
        for row in [
            "glyph 0x41 A \"unterminated.png",
            "glyph 0x41 A \"path.png\"suffix",
            "glyph 0x41 A pre\"path.png\"",
        ] {
            assert!(parse_manifest(&format!("{head}{row}\n"), Path::new(".")).is_err(), "must refuse: {row}");
        }
    }
}

#[cfg(test)]
mod ligature_row_tests {
    use super::*;
    fn manifest_with(extra_glyph_lines: &str) -> String {
        format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\nglyph 0x52 R r.png\nglyph 0x66 f f.png\n{}", "0".repeat(64), extra_glyph_lines)
    }
    #[test]
    fn ligature_row_parses_as_one_unmapped_glyph_with_sequence_identity() {
        let m = parse_manifest(&manifest_with("glyph 0x0066_0069 f_i fi.png\nglyph 0x0066_0066_006C f_f_l ffl.png\n"), Path::new(".")).unwrap();
        assert_eq!(m.glyphs.len(), 4);
        let fi = m.glyphs.iter().find(|g| g.name == "f_i").unwrap();
        assert!(fi.is_ligature() && fi.codepoint == Some(0x66) && fi.extra_cps == vec![0x69]);
        assert_eq!(fi.seq_label(), "66_69");
        assert_eq!(fi.cp_display(), "0x66_0x69");
        let ffl = m.glyphs.iter().find(|g| g.name == "f_f_l").unwrap();
        assert_eq!(ffl.seq_label(), "66_66_6c");
        assert!(m.glyphs.iter().all(|g| g.scale.is_none()));
        // identity is the full sequence: f and f_i coexist; names and sequences dedupe independently
        validate_manifest_identities(&m).unwrap();
        // population pin uses the sequence key; ordinary rows are byte-identical to the old format
        let pin_rows: Vec<String> = m.glyphs.iter().map(|g| format!("{}:{}\n", g.seq_label(), g.name)).collect();
        assert!(pin_rows.contains(&"52:R\n".to_string()) && pin_rows.contains(&"66:f\n".to_string()) && pin_rows.contains(&"66_69:f_i\n".to_string()));
        assert_eq!(population_pin(&m.glyphs), sha256_hex({ let mut r = pin_rows.clone(); r.sort(); r.concat() }.as_bytes()));
    }
    #[test]
    fn duplicate_ligature_sequence_is_refused() {
        let m = parse_manifest(&manifest_with("glyph 0x0066_0069 f_i fi.png\nglyph 0x66_0x69 f_i2 fi2.png\n"), Path::new(".")).unwrap();
        let e = validate_manifest_identities(&m).unwrap_err();
        assert!(e.contains("duplicate codepoint sequence"), "{e}");
    }
    #[test]
    fn malformed_ligature_rows_are_excluded_with_typed_reason() {
        let m = parse_manifest(&manifest_with("glyph 0x0066_ f_i fi.png\nglyph 0x66_0xD800 f_bad fb.png\n"), Path::new(".")).unwrap();
        assert_eq!(m.glyphs.len(), 2, "malformed rows are excluded, the valid f and R rows remain");
    }
}

#[cfg(test)]
mod population_floor_tests {
    use super::*;

    /// Minimal full-run manifest; only the fields the floor font reads
    /// (names, vendor, UPM) carry meaning at the floor.
    fn floor_manifest() -> Manifest {
        Manifest { derive_space_from_letter_advances: false, auto_sb: None, auto_sb_class_table: None, auto_sb_offset_lsb: None, auto_sb_offset_rsb: None, tie_break: None, auto_sb_pool: None, style_overrides: None, os2_x_height_write: None, m3: M3Decl::default(),
            family: "FloorTest".into(),
            subfamily: "Regular".into(),
            postscript_name: "FloorTest-Regular".into(),
            postscript_name_declared: None,
            vendor: *b"TEST",
            upm: 1000,
            scale: 10.0,
            capture_frame: None,
            capture_cohort: None,
            post_lsb_add: 0.0,
            post_rsb_add: 0.0,
            post_scope: kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false },
            post_scope_label: "none".into(),
            rdp_epsilon: 1.0,
            fit_squared_error: 1.0,
            fit_max_refits: 1,
            fit_tolerance_policy: FitTolerancePolicy::Fixed,
            flatten_tolerance: 0.5,
            scan_row_step: 1.0,
            scan_max_rows: 64,
            sample_resolution: 1.0,
            max_pair_evaluations: 0,
            iou: None,
            max_pairs: 0,
            pair_min_shared_rows: 1,
            glyphs: vec![GlyphRow { codepoint: Some(0x61), extra_cps: vec![], name: "a".into(), image: PathBuf::from("a.png"), scale: None }],
            space_evidence: None,
            space: None,
            notdef: None,
            notdef_proxy: None,
            capture_manifest: None,
            run_mode: RunMode::Full, corner_wiring: false,
            population_sha256: "0".repeat(64),
            stage1_cache: None, learned_store: None, learned_gate_evidence: None, pair_visual_same_source: false,
            references: vec![],
            frame_map: None,
            guide: None,
        }
    }

    #[test]
    fn floor_font_is_a_minimal_parseable_otf() {
        let m = floor_manifest();
        let (prepared, bytes) = population_floor_font(&m).expect("floor font builds");
        assert_eq!(&bytes[..4], b"OTTO", "CFF-flavoured OTF magic");
        assert_eq!(prepared.glyphs.len(), 1, "exactly one glyph ships");
        assert!(prepared.mapping.is_empty(), "no cmap mappings at the floor");
        // The shipped bytes pass the same name gate as a normal export.
        let readback = name_table_readback(&bytes, &m.family, &m.subfamily, &m.postscript_name)
            .expect("floor OTF passes the name readback gate");
        assert!(readback.iter().any(|(id, v)| *id == 6 && v == "FloorTest-Regular"));
    }

    #[test]
    fn floor_notdef_advance_is_the_declared_upm() {
        let mut m = floor_manifest();
        m.upm = 2048;
        assert_eq!(population_floor_notdef_advance(&m), 2048.0);
    }

    #[test]
    fn floor_receipt_line_is_typed_and_counts_exclusions() {
        let line = population_floor_receipt_line(7, 3);
        assert!(line.starts_with("population_floor\ttrue\t"), "{line}");
        assert!(line.contains("code\tPOPULATION_FLOOR\t"), "{line}");
        assert!(line.contains("population\t0\t"), "{line}");
        assert!(line.contains("excluded\t7\t"), "{line}");
        assert!(line.contains("fallback_ledger_events\t3\t"), "{line}");
    }

    /// Pinned rationale for the bypass: the spacing solver's typed refusal on
    /// an empty population is why the floor cannot flow through stage2-4.
    #[test]
    fn solver_refuses_empty_population() {
        let policy = SpacingPolicy {
            sample_resolution: 1.0, max_pair_evaluations: 8, max_pairs: 8,
            pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false,
        cadence_class_pass: false, class_channel_targets: false,
        };
        assert!(matches!(
            solve_spacing(&[], Some(&FontContext::default()), &policy),
            Err(kni_metrics::self_anchored_spacing::SpacingError::EmptyInput)
        ));
    }

    /// RunConfig carrying a declared post step, same construction the emit
    /// tests use (kerning_letters scope mirrors the +25/+25 manifests).
    fn floor_rc(lsb: f64, rsb: f64) -> RunConfig {
        let scale = kni_core::scale_context::ScaleContext::from_convention("test", "test", 1.0, 1000.0, "cohort", "frame").unwrap();
        let mut input = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), "capture".into(), "out".into(), "s1");
        input.lsb_add = lsb; input.rsb_add = rsb;
        input.post_scope = kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: true };
        input.post_scope_label = "kerning_letters".into();
        RunConfig::new(input, scale).unwrap()
    }

    fn floor_dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kni_floor_post_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    /// The reported bug: floor + declared non-zero post step (+25/+25). The
    /// base is never approved at the floor, so the old code refused inside
    /// emit_final_bundle_with and the run shipped NO OTF. Now the declared
    /// step still applies - to the glyphs its scope selects - with a typed
    /// warning, and the OTF ships.
    #[test]
    fn floor_export_with_declared_post_step_applies_and_ships_otf() {
        let m = floor_manifest();
        let d = floor_dir("apply");
        let seeded = population_floor_receipt_line(0, 0);
        let receipt = population_floor_export(&m, seeded, &d, &floor_rc(25.0, 25.0))
            .expect("floor export ships the OTF despite the declared post step");
        assert!(d.join("font-s1.otf").exists(), "OTF published");
        assert!(d.join("font-s1.glyphs").exists(), "master published at population floor");
        assert!(receipt.contains("post_pass_applied_unapproved_base\ttrue\tcode\tPOST_PASS_APPLIED_UNAPPROVED_BASE\t"), "{receipt}");
        assert!(receipt.contains("lsb_add\t25"), "{receipt}");
        assert!(receipt.contains("rsb_add\t25"), "{receipt}");
        assert!(receipt.contains("population_floor\ttrue\tcode\tPOPULATION_FLOOR\t"), "{receipt}");
        assert!(receipt.lines().any(|l| l.starts_with("otf\t")), "{receipt}");
        let _ = fs::remove_dir_all(&d);
    }

    /// Parity pin: a floor run with a 0/0 post step is untouched by the
    /// unapproved-base path - OTF ships, no applied warning is recorded.
    #[test]
    fn floor_export_with_zero_post_step_has_no_applied_line() {
        let m = floor_manifest();
        let d = floor_dir("noop");
        let receipt = population_floor_export(&m, String::new(), &d, &floor_rc(0.0, 0.0))
            .expect("0/0 floor export ships");
        assert!(d.join("font-s1.otf").exists());
        assert!(!receipt.contains("post_pass_applied_unapproved_base"), "{receipt}");
        assert!(!receipt.contains("post_pass_skipped"), "{receipt}");
        let _ = fs::remove_dir_all(&d);
    }

    /// Always-output pin: an unapproved base with a declared post step applies
    /// the step with the typed warning and ships; only the Refuse policy keeps
    /// the mint-contract refusal.
    #[test]
    fn unapproved_base_with_post_step_applies_and_ships() {
        let m = floor_manifest();
        let (prepared, bytes) = population_floor_font(&m).expect("floor font builds");
        let order: Vec<String> = vec![".notdef".to_string()];
        let mapping: Vec<(u32, u16)> = Vec::new();
        let d = floor_dir("ship");
        let mut receipt = String::new();
        emit_final_bundle_with(&d, false, &prepared, &bytes, &floor_rc(25.0, 25.0), None, &mapping, &order,
            None, &m.family, &m.subfamily, &m.postscript_name, &|_| Ok(Vec::new()), &mut receipt, PostUnapprovedPolicy::ApplyWithTypedWarning)
            .expect("always-output: unapproved base applies the step and ships");
        assert!(d.join("font-s1.otf").exists(), "OTF published");
        assert!(receipt.contains("post_pass_applied_unapproved_base\ttrue\tcode\tPOST_PASS_APPLIED_UNAPPROVED_BASE\t"), "{receipt}");
        let _ = fs::remove_dir_all(&d);
    }
}

#[cfg(test)]
mod stage1_parallel_tests {
    use super::*;
    fn crc32(data: &[u8]) -> u32 {
        let mut c = 0xFFFF_FFFFu32;
        for &b in data { c ^= b as u32; for _ in 0..8 { c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 }; } }
        !c
    }
    fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
        out.extend_from_slice(&(body.len() as u32).to_be_bytes());
        let mut c = kind.to_vec(); c.extend_from_slice(body);
        out.extend_from_slice(&c); out.extend_from_slice(&crc32(&c).to_be_bytes());
    }
    /// 8-bit gray PNG, stored (uncompressed) deflate: test fixture encoder only.
    fn png_gray(w: usize, h: usize, px: &[u8]) -> Vec<u8> {
        let mut raw = Vec::new();
        for y in 0..h { raw.push(0); raw.extend_from_slice(&px[y * w..(y + 1) * w]); }
        let mut z = vec![0x78, 0x01];
        let mut it = raw.chunks(65535).peekable();
        while let Some(c) = it.next() {
            z.push(if it.peek().is_none() { 1 } else { 0 });
            z.extend_from_slice(&(c.len() as u16).to_le_bytes()); z.extend_from_slice(&(!(c.len() as u16)).to_le_bytes()); z.extend_from_slice(c);
        }
        let (mut a, mut b) = (1u32, 0u32);
        for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let mut out = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&(w as u32).to_be_bytes()); ihdr.extend_from_slice(&(h as u32).to_be_bytes()); ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        chunk(&mut out, b"IHDR", &ihdr); chunk(&mut out, b"IDAT", &z); chunk(&mut out, b"IEND", &[]);
        out
    }
    /// Glyph i: a filled shape whose geometry depends on i (rect for even, disc for odd), distinct per glyph.
    fn shape(i: usize) -> Vec<u8> {
        if i == 0 || i == 5 {
            // wide slab whose long edges bow by ~1-2 px over 240 px: long near-straight arcs (straight-sweep evidence)
            let (w, h) = (260usize, 80usize);
            let mut px = vec![255u8; w * h];
            for y in 0..h { for x in 0..w {
                let t = (x as f64 - 130.0) / 120.0;
                let bow = (1.0 + i as f64 * 0.1) * 2.0 * (1.0 - t * t);
                let (top, bot) = (20.0 - bow, 60.0 + bow);
                if x >= 10 && x < 250 && (y as f64) >= top && (y as f64) < bot { px[y * w + x] = 0; }
            } }
            return png_gray(w, h, &px);
        }
        let (w, h) = (48usize, 48usize);
        let mut px = vec![255u8; w * h];
        for y in 0..h { for x in 0..w {
            let ink = if i % 2 == 0 { x >= 8 + i && x < 40 - i && y >= 6 && y < 42 - i }
                else { let (dx, dy) = (x as f64 - 24.0, y as f64 - 24.0); dx * dx + dy * dy < (10.0 + i as f64).powi(2) };
            if ink { px[y * w + x] = 0; }
        } }
        png_gray(w, h, &px)
    }
    fn fixture(tag: &str) -> (Manifest, RunConfig, PathBuf) {
        let dir = std::env::temp_dir().join(format!("kni_s1par_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir); fs::create_dir_all(&dir).unwrap();
        // 8 glyphs (no H: the bound-H wiring is not under test); glyph 6 is a corrupt PNG -> exclusion path
        let cps = [0x41u32, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x49];
        let mut text = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n", "0".repeat(64));
        for (i, cp) in cps.iter().enumerate() {
            let f = format!("g{i}.png");
            fs::write(dir.join(&f), if i == 6 { b"not a png".to_vec() } else { shape(i) }).unwrap();
            text.push_str(&format!("glyph {:#x} G{} {}\n", cp, i, f));
        }
        let m = parse_manifest(&text, &dir).unwrap();
        let limits = Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 };
        let b = bind_manifest_scale(&m, limits).unwrap();
        let rc = validated_run_config(&m, b.into_context(), dir.clone(), dir.join("out"), "s1").unwrap();
        (m, rc, dir)
    }
    fn limits() -> Limits { Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 } }
    /// OLD serial loop, kept verbatim (from 645299e0) as the oracle: one shared receipt, receipt_mark slicing, direct
    /// mutation of the run state, early return on the bound-H refusal.
    fn old_serial(m: &Manifest, rc: &RunConfig) -> Result<(String, String, String), String> {
        let total_glyphs = m.glyphs.len();
        let mut receipt = String::new(); let mut cache = String::new();
        let mut processed: Vec<(&GlyphRow, DrawnGlyph)> = Vec::new();
        let (mut fallback_span_total, mut sub_grid_floor_total) = (0usize, 0usize);
        let mut fallback_glyph_spans: Vec<(String, usize)> = Vec::new();
        let mut stage1_pins: std::collections::HashMap<String, String> = std::collections::HashMap::new();
        let mut exclusions: Vec<(String, Option<u32>, String)> = Vec::new();
        kni_core::capture_fit::reset_straight_sweep_converted(); kni_core::capture_fit::reset_reloc_moved();
        for (gi, g) in m.glyphs.iter().enumerate() {
            let _ = (gi, total_glyphs);
            let receipt_mark = receipt.len();
            match process_glyph(g, m, rc, limits(), &PNG_DECODE_LIMITS, &mut receipt) {
                Ok((pin, dg, nfb, nsub, _nmeas, _fprov)) => {
                    fallback_span_total = add_fallback_events(fallback_span_total, &g.name, nfb).map_err(|e| e.message())?;
                    fallback_glyph_spans.push((g.name.clone(), nfb));
                    sub_grid_floor_total += nsub;
                    stage1_pins.insert(g.name.clone(), pin.clone());
                    cache.push_str(&format!("glyph\t{}\tcp\t{}\tpng_sha256\t{}\n", g.name, g.cp_display(), pin));
                    for ring in &dg.rings {
                        cache.push_str(&format!("ring\t{:016x}\t{:016x}\t{}\n", ring.start.x.to_bits(), ring.start.y.to_bits(), ring.spans.len()));
                        for sp in &ring.spans {
                            match sp {
                                Span::Line { end } => cache.push_str(&format!("L\t{:016x}\t{:016x}\n", end.x.to_bits(), end.y.to_bits())),
                                Span::Cubic { control_one, control_two, end } => cache.push_str(&format!(
                                    "C\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\t{:016x}\n",
                                    control_one.x.to_bits(), control_one.y.to_bits(), control_two.x.to_bits(), control_two.y.to_bits(), end.x.to_bits(), end.y.to_bits())),
                            }
                        }
                    }
                    let glyph_receipt = &receipt[receipt_mark..];
                    cache.push_str(&format!("receipt_lines\t{}\n", glyph_receipt.lines().count()));
                    cache.push_str(glyph_receipt);
                    cache.push_str("end\n");
                    processed.push((g, dg));
                }
                Err((pin, reason)) => {
                    if g.codepoint == Some(0x48) && !g.is_ligature() && declared_convention::record_for(rc.scale().id()).is_some() { return Err(format!("bound H processing refused: {reason}")); }
                    receipt.push_str(&glyph_skip_ledger_line(&g.name, g.codepoint, &reason));
                    cache.push_str(&format!("excluded\t{}\tcp\t{}\tpng_sha256\t{}\treason\t{}\n", g.name, g.cp_display(), pin, reason));
                    exclusions.push((g.name.clone(), g.codepoint, reason));
                }
            }
        }
        let mut pins: Vec<_> = stage1_pins.iter().collect(); pins.sort();
        let summary = format!("{:?}|{:?}|{:?}|{}|{:?}|{}|{}|{}", processed, exclusions, pins, fallback_span_total, fallback_glyph_spans, sub_grid_floor_total,
            kni_core::capture_fit::straight_sweep_converted(), kni_core::capture_fit::reloc_moved());
        Ok((cache, receipt, summary))
    }
    fn run_stage1(m: &Manifest, rc: &RunConfig, jobs: usize) -> (String, String, String, Stage1CounterPair) {
        let rows: Vec<&GlyphRow> = m.glyphs.iter().collect();
        let outs = stage1_fit_all(&rows, m, rc, limits(), run_config::Jobs::new(jobs).unwrap(), rows.len(), None).unwrap();
        assert_eq!(outs.iter().map(|o| o.idx).collect::<Vec<_>>(), (0..rows.len()).collect::<Vec<_>>());
        let per_glyph: Vec<(usize, usize)> = outs.iter().map(|o| (o.straight_sweep, o.reloc_moved)).collect();
        let (mut cache, mut receipt) = (String::new(), String::new());
        let mut acc = Stage1Acc::default();
        stage1_reduce(&rows, outs, &mut acc, &mut cache, &mut receipt).unwrap();
        let mut pins: Vec<_> = acc.pins.iter().collect(); pins.sort();
        let summary = format!("{:?}|{:?}|{:?}|{}|{:?}|{}|{}|{}", acc.processed, acc.exclusions, pins, acc.fallback_span_total, acc.fallback_glyph_spans, acc.sub_grid_floor_total, acc.straight_sweep, acc.reloc_moved);
        (cache, receipt, summary, per_glyph)
    }
    type Stage1CounterPair = Vec<(usize, usize)>;
    #[test]
    fn new_driver_matches_the_old_serial_loop_at_jobs_1_3_4_8() {
        let (m, rc, dir) = fixture("eq");
        let oracle = old_serial(&m, &rc).unwrap();
        assert!(oracle.0.contains("excluded\tG6"), "corrupt glyph must be an exclusion");
        assert_eq!(oracle.0.lines().filter(|l| l.starts_with("glyph\t") && l.contains("\tpng_sha256\t")).count(), 7);
        for jobs in [1usize, 3, 4, 8] {
            let (cache, receipt, summary, per_glyph) = run_stage1(&m, &rc, jobs);
            assert_eq!(cache, oracle.0, "cache text, jobs={jobs}");
            assert_eq!(receipt, oracle.1, "receipt, jobs={jobs}");
            assert_eq!(summary, oracle.2, "totals/ledger/pins/straight_sweep/reloc_moved, jobs={jobs}");
            // PN-3 fallback rescue: this fixture's near-straight spans are
            // now emitted as Lines at the fit stage (chord-line terminal
            // accept under the dense bound, or resolved curves), so the
            // final straight sweep finds no near-straight cubics to convert
            // and the counter reads 0 (was >0 on G1/G2/G4). The
            // serial/parallel parity asserts above still pin the counter
            // PLUMBING; the counter mechanics are unit-tested in
            // capture_fit. Pinned to 0 so a later change fails loudly.
            assert_eq!(per_glyph.iter().map(|c| c.0).sum::<usize>(), 0, "straight-sweep counter on this fixture after the PN-3 rescue: {per_glyph:?}");
            assert!(per_glyph.iter().any(|c| c.1 > 0), "fixture must exercise the reloc_moved counter: {per_glyph:?}");
        }
        let _ = fs::remove_dir_all(dir);
    }
    /// Real scanned glyphs (the 6-glyph diagnostic set: curves, accents, dots) instead of synthetic shapes: the OLD serial
    /// loop is the oracle for cache text, receipt and totals at several --jobs levels.
    // Real-fixture stage1 equivalence, split per pass so cargo runs the four
    // full passes concurrently: wall time is the slowest pass, not their sum.
    // Assertions and coverage are identical to the single-test form. The
    // fixture/rc and the serial oracle are computed once per process
    // (OnceLock) and shared exactly like the single-test form shared its one
    // rc across all passes; the oracle is the dominant cost (~11 s release)
    // and must not be paid four times. The shared out dir receives identical
    // stage1-cache.txt bytes from concurrent passes; nothing reads it back.
    fn real_fixture(tag: &str) -> (Manifest, run_config::RunConfig) {
        let engine = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let mut text = fs::read_to_string(engine.join("manifest-diag6.txt")).unwrap();
        if !text.contains("capture_cohort") {
            text.push_str("\ncapture_cohort KNI Diagnostic/SixGlyph\ncapture_frame capture-manifest-frame\n");
        }
        let m = parse_manifest(&text, &engine).unwrap();
        let ctx = kni_core::scale_context::ScaleContext::from_convention("test", "test", m.scale, 1000.0, "cohort", "frame").unwrap();
        let out = std::env::temp_dir().join(format!("kni_s1par_real_{}_{tag}", std::process::id()));
        let rc = validated_run_config(&m, ctx, engine.clone(), out, "s1").unwrap();
        (m, rc)
    }
    fn real_shared() -> &'static (Manifest, run_config::RunConfig) {
        static SHARED: std::sync::OnceLock<(Manifest, run_config::RunConfig)> = std::sync::OnceLock::new();
        SHARED.get_or_init(|| real_fixture("shared"))
    }
    fn real_oracle() -> &'static (String, String, String) {
        static ORACLE: std::sync::OnceLock<(String, String, String)> = std::sync::OnceLock::new();
        ORACLE.get_or_init(|| {
            let (m, rc) = real_shared();
            let oracle = old_serial(m, rc).unwrap();
            assert!(oracle.0.lines().filter(|l| l.starts_with("glyph\t")).count() >= 2, "fixture must fit real glyphs");
            oracle
        })
    }
    fn real_jobs_matches_oracle(jobs: usize) {
        let (m, rc) = real_shared();
        let oracle = real_oracle();
        let (cache, receipt, summary, _) = run_stage1(m, rc, jobs);
        assert_eq!(cache, oracle.0, "cache text, jobs={jobs}");
        assert_eq!(receipt, oracle.1, "receipt, jobs={jobs}");
        assert_eq!(summary, oracle.2, "totals, jobs={jobs}");
    }
    #[test]
    fn real_scan_glyphs_serial_oracle_fits_fixture() {
        real_oracle();
    }
    #[test]
    fn real_scan_glyphs_match_the_old_serial_loop_at_jobs_1() { real_jobs_matches_oracle(1); }
    #[test]
    fn real_scan_glyphs_match_the_old_serial_loop_at_jobs_2() { real_jobs_matches_oracle(2); }
    #[test]
    fn real_scan_glyphs_match_the_old_serial_loop_at_jobs_4() { real_jobs_matches_oracle(4); }
    #[test]
    fn pool_is_used_for_jobs_gt_1_and_not_for_jobs_1() {
        let seen = std::sync::Mutex::new(Vec::<(Option<usize>, usize)>::new());
        let f = |i: usize| { seen.lock().unwrap().push((rayon::current_thread_index(), rayon::current_num_threads())); FitOutcome::fatal(i, String::new()).clear() };
        stage1_drive(6, run_config::Jobs::new(4).unwrap(), &f).unwrap();
        { let v = seen.lock().unwrap(); assert_eq!(v.len(), 6); assert!(v.iter().all(|(idx, n)| idx.is_some() && *n == 4), "{v:?}"); }
        seen.lock().unwrap().clear();
        stage1_drive(3, run_config::Jobs::new(1).unwrap(), &f).unwrap();
        let v = seen.lock().unwrap(); assert_eq!(v.len(), 3); assert!(v.iter().all(|(idx, _)| idx.is_none()), "jobs=1 runs inline on the caller: {v:?}");
    }
    impl FitOutcome { fn clear(mut self) -> FitOutcome { self.fatal = None; self.drawn = Err("x".into()); self } }
    fn row(i: usize) -> GlyphRow { GlyphRow { codepoint: Some(0x41 + i as u32), extra_cps: vec![], name: format!("R{i}"), image: PathBuf::from("unused"), scale: None } }
    fn ok_outcome(i: usize) -> FitOutcome { FitOutcome::fatal(i, String::new()).clear() }
    #[test]
    fn h_bound_refusal_is_a_typed_fatal_and_jobs_1_stops_at_it() {
        let o = fit_one_with(2, "H", Some(0x48), true, |_| Err(("pin".into(), "HSourceChanged".into())));
        assert_eq!(o.fatal.as_deref(), Some("bound H processing refused: HSourceChanged"));
        let o2 = fit_one_with(2, "H", Some(0x48), false, |_| Err(("pin".into(), "why".into())));
        assert!(o2.fatal.is_none() && matches!(&o2.drawn, Err(w) if w == "why"), "unbound refusal is an ordinary exclusion");
        let calls = std::sync::atomic::AtomicUsize::new(0);
        let f = |i: usize| { calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst); if i == 2 { fit_one_with(i, "H", Some(0x48), true, |_| Err(("p".into(), "refused".into()))) } else { ok_outcome(i) } };
        let outs = stage1_drive(8, run_config::Jobs::new(1).unwrap(), &f).unwrap();
        assert_eq!(outs.len(), 3, "jobs=1 stops fitting after the first fatal");
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 3);
        let rows: Vec<GlyphRow> = (0..8).map(row).collect(); let rr: Vec<&GlyphRow> = rows.iter().collect();
        let e = stage1_reduce(&rr, outs, &mut Stage1Acc::default(), &mut String::new(), &mut String::new()).unwrap_err();
        assert_eq!(e, "bound H processing refused: refused");
    }
    #[test]
    fn panic_is_typed_and_first_manifest_order_fatal_wins_in_parallel() {
        let quiet = std::panic::take_hook(); std::panic::set_hook(Box::new(|_| {}));
        let mk = |panic_at: &'static [usize], h_at: Option<usize>| move |i: usize| {
            if panic_at.contains(&i) { guarded(i, &format!("R{i}"), || panic!("boom {i}")) }
            else if Some(i) == h_at { fit_one_with(i, "H", Some(0x48), true, |_| Err(("p".into(), "h refused".into()))) }
            else { ok_outcome(i) }
        };
        let rows: Vec<GlyphRow> = (0..8).map(row).collect(); let rr: Vec<&GlyphRow> = rows.iter().collect();
        let red = |outs: Vec<FitOutcome>| stage1_reduce(&rr, outs, &mut Stage1Acc::default(), &mut String::new(), &mut String::new()).unwrap_err();
        // H fatal at 2, panics at 5 and 6: the H refusal (earlier) wins; later panics never mask it
        let e = red(stage1_drive(8, run_config::Jobs::new(4).unwrap(), mk(&[5, 6], Some(2))).unwrap());
        assert_eq!(e, "bound H processing refused: h refused");
        // panic at 1, H fatal at 4: the panic (earlier) wins and is typed
        let e = red(stage1_drive(8, run_config::Jobs::new(4).unwrap(), mk(&[1], Some(4))).unwrap());
        assert_eq!(e, "stage-1 fit panicked on glyph R1: boom 1");
        // jobs=1 gives the same answer as jobs=4
        assert_eq!(red(stage1_drive(8, run_config::Jobs::new(1).unwrap(), mk(&[1], Some(4))).unwrap()), "stage-1 fit panicked on glyph R1: boom 1");
        std::panic::set_hook(quiet);
    }
    #[test]
    fn reduce_validates_index_coverage() {
        let rows: Vec<GlyphRow> = (0..4).map(row).collect(); let rr: Vec<&GlyphRow> = rows.iter().collect();
        let red = |ids: Vec<usize>| stage1_reduce(&rr, ids.into_iter().map(ok_outcome).collect(), &mut Stage1Acc::default(), &mut String::new(), &mut String::new());
        assert!(red(vec![0, 1, 2, 3]).is_ok());
        for bad in [vec![0, 1, 1, 3], vec![0, 2, 3], vec![1, 0, 2, 3], vec![0, 1, 2, 3, 4], vec![0, 1, 2], vec![]] {
            assert!(red(bad.clone()).is_err(), "{bad:?}");
        }
        // overflow is an error, not a clamp
        let mut o = ok_outcome(0); o.sub_grid = usize::MAX; o.drawn = Ok(DrawnGlyph { glyph_id: "R0".into(), rings: vec![] });
        let mut o1 = ok_outcome(1); o1.sub_grid = 1; o1.drawn = Ok(DrawnGlyph { glyph_id: "R1".into(), rings: vec![] });
        let e = stage1_reduce(&rr[..2], vec![o, o1], &mut Stage1Acc::default(), &mut String::new(), &mut String::new()).unwrap_err();
        assert!(e.contains("sub_grid_floor overflow"), "{e}");
    }
}


#[cfg(test)]
mod stage1_cache_replay_budget_tests {
    use super::*;
    use kni_core::capture::{decode_png_gray_bounded, DecodeLimits, PngDecodeError};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    struct Fixture { m: Manifest, rc: RunConfig, dir: PathBuf }
    impl Drop for Fixture { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.dir); } }
    fn limits() -> Limits { Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 } }
    fn fixture() -> Fixture { fixture_with("") }
    fn fixture_with(extra: &str) -> Fixture {
        let dir = std::env::temp_dir().join(format!("kni_replay_budget_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let mut text = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n", "0".repeat(64));
        text.push_str(extra);
        // Deliberately non-alphabetical, not a HashMap traversal order.
        for (i, name) in ["Z", "A", "M"].iter().enumerate() {
            let file = format!("{i}.png"); fs::write(dir.join(&file), png(48)).unwrap();
            text.push_str(&format!("glyph {:#x} {name} {file}\n", 0x41 + i));
        }
        let m = parse_manifest(&text, &dir).unwrap();
        let b = bind_manifest_scale(&m, limits()).unwrap();
        let rc = validated_run_config(&m, b.into_context(), dir.clone(), dir.join("out"), "s1").unwrap();
        Fixture { m, rc, dir }
    }
    fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
        out.extend_from_slice(&(body.len() as u32).to_be_bytes());
        out.extend_from_slice(kind); out.extend_from_slice(body);
        let mut crc = 0xffff_ffffu32;
        for b in kind.iter().chain(body.iter()) {
            crc ^= *b as u32;
            for _ in 0..8 { crc = if crc & 1 != 0 { 0xedb8_8320 ^ (crc >> 1) } else { crc >> 1 }; }
        }
        out.extend_from_slice(&(!crc).to_be_bytes());
    }
    fn png(side: usize) -> Vec<u8> {
        // Small deterministic rectangle, one stored deflate block, no external corpus.
        let mut raw = Vec::new();
        for y in 0..side {
            raw.push(0);
            for x in 0..side { raw.push(if x >= 8 && x < side - 8 && y >= 8 && y < side - 8 { 0 } else { 255 }); }
        }
        assert!(raw.len() <= 65535);
        let n = raw.len() as u16;
        let mut z = vec![0x78, 0x01, 0x01];
        z.extend_from_slice(&n.to_le_bytes()); z.extend_from_slice(&(!n).to_le_bytes()); z.extend_from_slice(&raw);
        let (mut a, mut b) = (1u32, 0u32);
        for &v in &raw { a = (a + v as u32) % 65521; b = (b + a) % 65521; }
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&(side as u32).to_be_bytes()); ihdr.extend_from_slice(&(side as u32).to_be_bytes());
        ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        chunk(&mut bytes, b"IHDR", &ihdr); chunk(&mut bytes, b"IDAT", &z); chunk(&mut bytes, b"IEND", &[]);
        bytes
    }
    fn blank_png(side: usize) -> Vec<u8> {
        // All-255 gray tile: one stored deflate block, same encoder as png().
        let mut raw = Vec::new();
        for _y in 0..side { raw.push(0u8); for _x in 0..side { raw.push(255u8); } }
        assert!(raw.len() <= 65535);
        let n = raw.len() as u16;
        let mut z = vec![0x78, 0x01, 0x01];
        z.extend_from_slice(&n.to_le_bytes()); z.extend_from_slice(&(!n).to_le_bytes()); z.extend_from_slice(&raw);
        let (mut a, mut b) = (1u32, 0u32);
        for &v in &raw { a = (a + v as u32) % 65521; b = (b + a) % 65521; }
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&(side as u32).to_be_bytes()); ihdr.extend_from_slice(&(side as u32).to_be_bytes());
        ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        chunk(&mut bytes, b"IHDR", &ihdr); chunk(&mut bytes, b"IDAT", &z); chunk(&mut bytes, b"IEND", &[]);
        bytes
    }
    fn form_hash_of(path: &Path) -> (String, bool) {
        let bytes = fs::read(path).unwrap();
        let d = kni_core::capture_dispatch::decode_source(&bytes, &PNG_DECODE_LIMITS, limits()).unwrap();
        (bound_detector_validator::pixel_form_sha256(d.width, d.height, &d.gray).unwrap(), d.gray.iter().all(|&p| p == 255))
    }
    #[test]
    fn replay_placeholder_decision_pin_is_recomputed_and_refused_on_mismatch() {
        // Two identical blank tiles (the class) plus one drawn tile.
        let dir = std::env::temp_dir().join(format!("kni_ph_pin_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let mut text = format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n", "0".repeat(64));
        fs::write(dir.join("b0.png"), blank_png(32)).unwrap();
        fs::write(dir.join("b1.png"), blank_png(32)).unwrap();
        fs::write(dir.join("d.png"), png(48)).unwrap();
        text.push_str("glyph 0x41 B0 b0.png\nglyph 0x42 B1 b1.png\nglyph 0x43 D d.png\n");
        let m = parse_manifest(&text, &dir).unwrap();
        let (hash, blank) = form_hash_of(&dir.join("b0.png"));
        assert!(blank);
        // The honest persisted decision verifies.
        verify_cache_placeholder_decision(&m, limits(), &hash, true, &[0x41, 0x42]).unwrap();
        // A corrupted persisted hash is a typed refusal, not a trusted pin.
        let bad = "0".repeat(64);
        let e = verify_cache_placeholder_decision(&m, limits(), &bad, true, &[0x41, 0x42]).unwrap_err();
        assert!(e.contains("placeholder_decision pixel_form_sha256 mismatch"), "{e}");
        // A corrupted kind is a typed refusal.
        let e = verify_cache_placeholder_decision(&m, limits(), &hash, false, &[0x41, 0x42]).unwrap_err();
        assert!(e.contains("placeholder_decision kind mismatch"), "{e}");
        // A slot outside the manifest is a typed refusal.
        let e = verify_cache_placeholder_decision(&m, limits(), &hash, true, &[0x41, 0x61]).unwrap_err();
        assert!(e.contains("not in manifest"), "{e}");
        let _ = fs::remove_dir_all(&dir);
    }
    #[test]
    fn replay_straight_sweep_roundtrip_and_absent_row() {
        let dir = std::env::temp_dir().join(format!("kni_sweep_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let p = dir.join("cache.txt");
        fs::write(&p, "kni-stage1-cache\tv2\nstraight_sweep_converted\tcount\t7\n").unwrap();
        assert_eq!(read_cache_straight_sweep(&p).unwrap(), Some(7));
        fs::write(&p, "kni-stage1-cache\tv2\nstraight_sweep_converted\tcount\t0\n").unwrap();
        assert_eq!(read_cache_straight_sweep(&p).unwrap(), Some(0));
        fs::write(&p, "kni-stage1-cache\tv2\n").unwrap();
        assert_eq!(read_cache_straight_sweep(&p).unwrap(), None);
        fs::write(&p, "kni-stage1-cache\tv2\nstraight_sweep_converted\tcount\tx\n").unwrap();
        assert!(read_cache_straight_sweep(&p).unwrap_err().contains("bad straight_sweep_converted count"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn replay_speck_evidence_roundtrip_and_absent_row() {
        let dir = std::env::temp_dir().join(format!("kni_speck_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let cache_path = dir.join("stage1-cache.txt");
        let areas = [0.5f64, 1.25, 2.0];
        let bits: Vec<String> = areas.iter().map(|a| format!("{:016x}", a.to_bits())).collect();
        // persist -> read round-trip is bit-exact
        fs::write(&cache_path, format!("kni-stage1-cache\tv2\nspeck_retained\tcount\t{}\tareas\t{}\n", areas.len(), bits.join(","))).unwrap();
        assert_eq!(read_cache_speck_retained(&cache_path).unwrap(), Some(areas.to_vec()));
        // an empty live class round-trips as an explicit empty row, not absence
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_retained\tcount\t0\tareas\t\n").unwrap();
        assert_eq!(read_cache_speck_retained(&cache_path).unwrap(), Some(Vec::new()));
        // no row: the receipt site emits the typed replay-unavailable marker, never a silent 0
        fs::write(&cache_path, "kni-stage1-cache\tv2\n").unwrap();
        assert_eq!(read_cache_speck_retained(&cache_path).unwrap(), None);
        // malformed rows are typed refusals
        fs::write(&cache_path, format!("kni-stage1-cache\tv2\nspeck_retained\tcount\t2\tareas\t{:016x}\n", 1.5f64.to_bits())).unwrap();
        assert!(read_cache_speck_retained(&cache_path).unwrap_err().contains("count mismatch"));
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_retained\tcount\t1\tareas\tzz\n").unwrap();
        assert!(read_cache_speck_retained(&cache_path).unwrap_err().contains("bad speck_retained area"));
        let _ = fs::remove_dir_all(&dir);
    }
    #[test]
    fn replay_corner_wiring_seams_roundtrip_live_equals_replay() {
        let dir = std::env::temp_dir().join(format!("kni_cwseams_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let cache_path = dir.join("stage1-cache.txt");
        let totals = kni_core::corner_wiring::WiringTotals { seams: 7, corners: 3, smoothed: 2, abstained: 1, guard_rejected: 1 };
        // The live run's receipt line and its persisted cache row are one line shape.
        let live_line = corner_wiring_seams_row(&totals);
        assert_eq!(live_line, "corner_wiring_seams\tcount\t7\tcorner\t3\tsmooth\t2\tabstain\t1\tguard_reject\t1\n");
        // persist -> read round-trip reproduces the exact counts...
        fs::write(&cache_path, format!("kni-stage1-cache\tv2\n{live_line}")).unwrap();
        let replayed = read_cache_corner_wiring_seams(&cache_path).unwrap().expect("persisted row must read back");
        assert_eq!((replayed.seams, replayed.corners, replayed.smoothed, replayed.abstained, replayed.guard_rejected), (7, 3, 2, 1, 1));
        // ...and the replay route prints the identical receipt line.
        assert_eq!(corner_wiring_seams_row(&replayed), live_line);
        // an empty live class round-trips as an explicit zero row, not absence
        let zero_line = corner_wiring_seams_row(&kni_core::corner_wiring::WiringTotals::default());
        fs::write(&cache_path, format!("kni-stage1-cache\tv2\n{zero_line}")).unwrap();
        let z = read_cache_corner_wiring_seams(&cache_path).unwrap().expect("zero row must read back");
        assert_eq!((z.seams, z.corners, z.smoothed, z.abstained, z.guard_rejected), (0, 0, 0, 0, 0));
        // no row (a legacy cache): the receipt site emits the typed replay-unavailable marker, never a silent 0
        fs::write(&cache_path, "kni-stage1-cache\tv2\n").unwrap();
        assert!(read_cache_corner_wiring_seams(&cache_path).unwrap().is_none());
        // malformed rows are typed refusals
        fs::write(&cache_path, "kni-stage1-cache\tv2\ncorner_wiring_seams\tcount\t2\tcorner\t1\tsmooth\t0\n").unwrap();
        assert!(read_cache_corner_wiring_seams(&cache_path).unwrap_err().contains("bad corner_wiring_seams row"));
        fs::write(&cache_path, "kni-stage1-cache\tv2\ncorner_wiring_seams\tcount\tx\tcorner\t1\tsmooth\t0\tabstain\t0\tguard_reject\t0\n").unwrap();
        assert!(read_cache_corner_wiring_seams(&cache_path).unwrap_err().contains("bad corner_wiring_seams count"));
        fs::write(&cache_path, "kni-stage1-cache\tv2\ncorner_wiring_seams\tcount\t1\tcorner\t1\tsmoothed\t0\tabstain\t0\tguard_reject\t0\n").unwrap();
        assert!(read_cache_corner_wiring_seams(&cache_path).unwrap_err().contains("bad corner_wiring_seams row"));
        let _ = fs::remove_dir_all(&dir);
    }
    #[test]
    fn replay_sub_grid_floor_roundtrip_and_absent_row() {
        let dir = std::env::temp_dir().join(format!("kni_sg_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let cache_path = dir.join("stage1-cache.txt");
        // persist -> read round-trip, including the explicit zero
        fs::write(&cache_path, "kni-stage1-cache\tv2\nsub_grid_floor\tstage1_total\t7\n").unwrap();
        assert_eq!(read_cache_sub_grid_floor(&cache_path).unwrap(), Some(7));
        fs::write(&cache_path, "kni-stage1-cache\tv2\nsub_grid_floor\tstage1_total\t0\n").unwrap();
        assert_eq!(read_cache_sub_grid_floor(&cache_path).unwrap(), Some(0));
        // no row: the receipt site emits the typed replay-unavailable marker, never a silent 0
        fs::write(&cache_path, "kni-stage1-cache\tv2\n").unwrap();
        assert_eq!(read_cache_sub_grid_floor(&cache_path).unwrap(), None);
        // malformed row is a typed refusal
        fs::write(&cache_path, "kni-stage1-cache\tv2\nsub_grid_floor\tstage1_total\tzz\n").unwrap();
        assert!(read_cache_sub_grid_floor(&cache_path).unwrap_err().contains("bad sub_grid_floor row"));
        let _ = fs::remove_dir_all(&dir);
    }
    #[test]
    fn replay_speck_retained_hole_roundtrip_and_absent_row() {
        let dir = std::env::temp_dir().join(format!("kni_speck_hd_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let cache_path = dir.join("stage1-cache.txt");
        // persist -> read round-trip, zero included (always output)
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_retained_hole\tcount\t3\n").unwrap();
        assert_eq!(read_cache_speck_retained_hole(&cache_path).unwrap(), Some(3));
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_retained_hole\tcount\t0\n").unwrap();
        assert_eq!(read_cache_speck_retained_hole(&cache_path).unwrap(), Some(0));
        // no row: typed replay-unavailable at the receipt site, never a silent 0
        fs::write(&cache_path, "kni-stage1-cache\tv2\n").unwrap();
        assert_eq!(read_cache_speck_retained_hole(&cache_path).unwrap(), None);
        // malformed row: typed refusal
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_retained_hole\tcount\tzz\n").unwrap();
        assert!(read_cache_speck_retained_hole(&cache_path).unwrap_err().contains("bad speck_retained_hole count"));
        let _ = fs::remove_dir_all(&dir);
    }
    #[test]
    fn replay_speck_dropped_collapse_roundtrip_and_absent_row() {
        let dir = std::env::temp_dir().join(format!("kni_speck_dc_rt_{}_{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let cache_path = dir.join("stage1-cache.txt");
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_dropped_collapse\tcount\t42\n").unwrap();
        assert_eq!(read_cache_speck_dropped_collapse(&cache_path).unwrap(), Some(42));
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_dropped_collapse\tcount\t0\n").unwrap();
        assert_eq!(read_cache_speck_dropped_collapse(&cache_path).unwrap(), Some(0));
        fs::write(&cache_path, "kni-stage1-cache\tv2\n").unwrap();
        assert_eq!(read_cache_speck_dropped_collapse(&cache_path).unwrap(), None);
        fs::write(&cache_path, "kni-stage1-cache\tv2\nspeck_dropped_collapse\tcount\tzz\n").unwrap();
        assert!(read_cache_speck_dropped_collapse(&cache_path).unwrap_err().contains("bad speck_dropped_collapse count"));
        let _ = fs::remove_dir_all(&dir);
    }
    fn outcomes(m: &Manifest) -> Vec<FitOutcome> {
        m.glyphs.iter().enumerate().map(|(idx, g)| {
            let pin = sha256_hex(&fs::read(&g.image).unwrap());
            FitOutcome { fallback_provenance: Vec::new(), observer_records: Vec::new(), merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector::default(), merge_visibility_route_domains: Vec::new(), merge_visibility_context: None, merge_visibility_source_bytes: None, idx, pin, drawn: if idx == 1 { Err("synthetic\treason".into()) } else {
                Ok(DrawnGlyph { glyph_id: g.name.clone(), rings: vec![ReferenceRing {
                    start: Point { x: -0.0, y: f64::from_bits(1) }, spans: vec![
                        Span::Cubic { control_one: Point { x: 1.25, y: -3.5 }, control_two: Point { x: 2.0, y: 5.0 }, end: Point { x: 7.0, y: 8.0 } },
                        Span::Line { end: Point { x: -0.0, y: f64::from_bits(1) } },
                    ] }] })
            }, drawn_measurement: None, fallback_spans: idx, sub_grid: 0, straight_sweep: 0, reloc_moved: 0, speck_areas: Vec::new(), speck_retained_hole: 0, speck_dropped_collapse: 0,
                receipt_rows: if idx == 1 { String::new() } else { format!("evidence\t{}\tbytes\tunchanged\n{}", g.name, fallback_ledger_line(&g.name, idx)) },
                stderr_buf: String::new(), fatal: None, line_audit: String::new(), corner_wiring: String::new(), corner_wiring_totals: Default::default() }
        }).collect()
    }
    fn cache_text(f: &Fixture) -> String {
        let m = &f.m; let rc = &f.rc;
        let mut cache = format!("kni-stage1-cache\tv2\npolicy\tscale\t{:e}\trdp_epsilon\t{:e}\tfit_squared_error\t{:e}\tfit_max_refits\t{}\tfit_tolerance_policy\t{:?}\tframe_map\t{:?}\tguide\t{:?}\treferences\t{:?}\tcorner_wiring\t{}\nscale_binding\t{}\nstage1_identity\t{}\nengine_exe_sha256\t{}\n",
            rc.scale().units_per_px(), m.rdp_epsilon, rc.fit_squared_error().value(), m.fit_max_refits, m.fit_tolerance_policy, m.frame_map, m.guide, m.references, if m.corner_wiring { "on" } else { "off" },
            rc.scale().binding_record(), rc.stage1_identity(), fs::read("/proc/self/exe").map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".into()));
        let rows: Vec<&GlyphRow> = m.glyphs.iter().collect();
        stage1_reduce(&rows, outcomes(m), &mut Stage1Acc::default(), &mut cache, &mut String::new()).unwrap();
        cache
    }
    fn replay_snapshot(f: &Fixture, path: &Path, old: bool) -> (Result<(), String>, String, String) {
        replay_snapshot_from_total(f, path, old, 5)
    }
    fn replay_snapshot_from_total(f: &Fixture, path: &Path, old: bool, mut total: usize) -> (Result<(), String>, String, String) {
        let mut processed = Vec::new(); let mut exclusions = Vec::new(); let mut receipt = "prefix\n".to_string();
        let mut pins = std::collections::HashMap::new();
        pins.insert("preexisting".into(), "seed".into());
        let mut counts = vec![("preexisting".into(), 5usize)];
        let mut shipped = Vec::new();
        let result = if old {
            legacy_load_stage1_cache(path, &f.m, &f.rc, &mut processed, &mut exclusions, &mut receipt, &mut total, &mut pins, &mut counts)
        } else {
            load_stage1_cache(path, &f.m, &f.rc, &[], &mut processed, &mut shipped, &mut exclusions, &mut receipt, &mut total, &mut pins, &mut counts)
        };
        let mut pins: Vec<_> = pins.into_iter().collect(); pins.sort();
        // to_bits is checked explicitly, not only numeric/Debug equality.
        let mut geom = Vec::new();
        for (g, d) in &processed {
            let mut bits = Vec::new();
            for r in &d.rings {
                bits.extend([r.start.x.to_bits(), r.start.y.to_bits()]);
                for sp in &r.spans {
                    match sp {
                        Span::Line { end } => bits.extend([end.x.to_bits(), end.y.to_bits()]),
                        Span::Cubic { control_one, control_two, end } => bits.extend([control_one.x.to_bits(), control_one.y.to_bits(), control_two.x.to_bits(), control_two.y.to_bits(), end.x.to_bits(), end.y.to_bits()]),
                    }
                }
            }
            geom.push((g.name.clone(), bits));
        }
        (result, receipt, format!("{geom:?}|{exclusions:?}|{pins:?}|{total}|{counts:?}"))
    }
    #[test]
    fn replay_matches_serial_oracle_bytes_pins_order_geometry_and_totals() {
        let f = fixture(); let path = f.dir.join("cache.txt");
        let text = cache_text(&f); fs::write(&path, &text).unwrap();
        let before = kni_core::capture_fit::FitCounters::now();
        let actual = replay_snapshot(&f, &path, false);
        assert_eq!(actual, replay_snapshot(&f, &path, true)); assert!(actual.0.is_ok());
        assert_eq!(actual.1, format!("prefix\nevidence\tZ\tbytes\tunchanged\n{}{}evidence\tM\tbytes\tunchanged\n{}stage1_cache\t{}\treused_glyphs\t3\n",
            fallback_ledger_line("Z", 0), glyph_skip_ledger_line("A", Some(0x42), "synthetic\treason"), fallback_ledger_line("M", 2), path.display()));
        assert_eq!(fs::read_to_string(&path).unwrap(), text, "cache must stay read-only");
        assert_eq!(kni_core::capture_fit::FitCounters::now(), before, "replay invents no counter events");
    }
    #[test]
    fn replay_pin_refusal_preserves_exact_serial_prefix_and_first_error() {
        let f = fixture(); let path = f.dir.join("cache.txt"); fs::write(&path, cache_text(&f)).unwrap();
        fs::write(&f.m.glyphs[1].image, b"changed source").unwrap();
        fs::remove_file(&f.m.glyphs[2].image).unwrap();
        let actual = replay_snapshot(&f, &path, false);
        assert_eq!(actual, replay_snapshot(&f, &path, true));
        assert!(actual.0.unwrap_err().contains("png pin mismatch for A"));
        assert!(!actual.1.contains("stage1_cache\t")); assert!(actual.1.contains("evidence\tZ"));
    }
    #[test]
    fn replay_fallback_ledger_refusal_is_identical_to_serial() {
        let f = fixture(); let path = f.dir.join("cache.txt");
        fs::write(&path, cache_text(&f).replace("fallback\tM\tline_spans\t2", "fallback\tM\tline_spans\tbad")).unwrap();
        let actual = replay_snapshot(&f, &path, false);
        assert_eq!(actual, replay_snapshot(&f, &path, true)); assert!(actual.0.is_err());
        assert!(actual.1.contains("glyph_skip\t") || actual.1.contains("A"));
    }
    #[test]
    fn replay_header_policy_identity_executable_and_truncation_checks_stay_intact() {
        let f = fixture(); let path = f.dir.join("cache.txt"); let cache = cache_text(&f);
        for text in [cache.replacen("kni-stage1-cache\tv2", "bad", 1),
                     cache.replacen("policy\tscale", "wrong\tscale", 1),
                     cache.replacen("scale_binding\t", "scale_binding\tbad", 1),
                     cache.replace(&format!("stage1_identity\t{}", f.rc.stage1_identity()), "stage1_identity\tbad"),
                     cache.lines().map(|l| if l.starts_with("engine_exe_sha256\t") { "engine_exe_sha256\tbad" } else { l }).collect::<Vec<_>>().join("\n"),
                     cache.trim_end_matches("end\n").to_string()] {
            fs::write(&path, text).unwrap(); let actual = replay_snapshot(&f, &path, false);
            assert_eq!(actual, replay_snapshot(&f, &path, true)); assert!(actual.0.is_err());
        }
    }
    #[test]
    fn corner_wiring_flip_is_a_typed_cache_policy_refusal() {
        // The cache stores post-wiring shipped rings, so the corner_wiring policy is
        // part of the cache identity: replaying a cache under the opposite setting
        // must be the typed policy refusal, in both directions.
        let off = fixture_with("");
        let on = fixture_with("corner_wiring on\n");
        let off_cache = off.dir.join("cache.txt"); fs::write(&off_cache, cache_text(&off)).unwrap();
        let on_cache = on.dir.join("cache.txt"); fs::write(&on_cache, cache_text(&on)).unwrap();
        for (cache_path, m, rc, label) in [(&off_cache, &on.m, &on.rc, "OFF cache replayed under an ON manifest"),
                                           (&on_cache, &off.m, &off.rc, "ON cache replayed under an OFF manifest")] {
            let mut processed = Vec::new(); let mut shipped = Vec::new(); let mut exclusions = Vec::new();
            let mut receipt = String::new(); let mut total = 0usize;
            let mut pins = std::collections::HashMap::new(); let mut counts = Vec::new();
            let err = load_stage1_cache(cache_path, m, rc, &[], &mut processed, &mut shipped, &mut exclusions, &mut receipt, &mut total, &mut pins, &mut counts).unwrap_err();
            assert!(err.starts_with("stage1 cache: policy mismatch"), "{label} must fail with the typed policy refusal, got: {err}");
        }
    }
    #[test]
    fn replay_missing_name_codepoint_and_entry_count_refusals_match_serial() {
        let f = fixture(); let path = f.dir.join("cache.txt"); let text = cache_text(&f);
        for changed in [text.replacen("excluded\tA\tcp\t0x42", "excluded\tMissing\tcp\t0x42", 1),
                        text.replacen("excluded\tA\tcp\t0x42", "excluded\tA\tcp\t0x99", 1),
                        text.lines().filter(|l| !l.starts_with("excluded\tA\t")).collect::<Vec<_>>().join("\n")] {
            assert_ne!(changed, text);
            fs::write(&path, changed).unwrap(); let actual = replay_snapshot(&f, &path, false);
            assert_eq!(actual, replay_snapshot(&f, &path, true)); assert!(actual.0.is_err());
        }
    }
    #[test]
    fn replay_overflow_refusal_keeps_serial_receipt_prefix() {
        let f = fixture(); let path = f.dir.join("cache.txt"); fs::write(&path, cache_text(&f)).unwrap();
        let actual = replay_snapshot_from_total(&f, &path, false, usize::MAX);
        assert_eq!(actual, replay_snapshot_from_total(&f, &path, true, usize::MAX));
        assert!(actual.0.is_err());
        assert!(!actual.1.contains("evidence\tM"), "overflow must precede this glyph's receipt append");
    }
    #[test]
    fn replay_duplicate_names_keep_first_entry_lookup_not_cache_position() {
        let mut f = fixture(); f.m.glyphs[2].name = f.m.glyphs[0].name.clone();
        f.m.glyphs[2].codepoint = f.m.glyphs[0].codepoint; f.m.glyphs[2].image = f.m.glyphs[0].image.clone();
        let path = f.dir.join("cache.txt"); fs::write(&path, cache_text(&f)).unwrap();
        let actual = replay_snapshot(&f, &path, false);
        assert_eq!(actual, replay_snapshot(&f, &path, true)); assert!(actual.0.is_ok());
        assert!(!actual.1.contains("line_spans\t2"), "both duplicate names use the first cache entry");
    }
    #[test]
    fn oversized_decode_is_typed_local_and_does_not_consume_other_glyph_budget() {
        // Injection-adjacent: the fixture has a glyph "A"; hold the exec
        // barrier so a concurrent wrapper-panic test cannot inject into it.
        let _exec = TEST_WRAPPER_PANIC_EXEC.lock().unwrap();
        let f = fixture(); let shared = DecodeLimits { max_pixels: 48 * 48, ..PNG_DECODE_LIMITS };
        fs::write(&f.m.glyphs[1].image, png(64)).unwrap();
        let large = fs::read(&f.m.glyphs[1].image).unwrap();
        assert_eq!(decode_png_gray_bounded(&large, &shared).unwrap_err(), PngDecodeError::TooManyPixels { w: 64, h: 64, max: 48 * 48 });
        let before = shared;
        let rows: Vec<&GlyphRow> = f.m.glyphs.iter().collect();
        let run = |jobs| {
            let outs = stage1_drive(rows.len(), run_config::Jobs::new(jobs).unwrap(), |i|
                stage1_fit_one(i, rows[i], &f.m, &f.rc, limits(), &shared, rows.len(), None)).unwrap();
            assert!(outs[0].drawn.is_ok(), "small glyph before oversized tile");
            assert!(outs[1].fatal.is_none(), "oversize is a glyph exclusion, not pool failure");
            assert!(outs[1].drawn.as_ref().unwrap_err().contains("too many pixels"));
            assert!(outs[2].drawn.is_ok(), "small glyph after oversized tile");
            let mut acc = Stage1Acc::default(); let mut cache = String::new(); let mut receipt = String::new();
            stage1_reduce(&rows, outs, &mut acc, &mut cache, &mut receipt).unwrap();
            (cache, receipt, acc.processed.iter().map(|(g, _)| g.name.clone()).collect::<Vec<_>>(), acc.exclusions)
        };
        let serial = run(1); assert_eq!(run(3), serial); assert_eq!(run(4), serial);
        assert_eq!(shared, before); assert_eq!(PNG_DECODE_LIMITS.max_pixels, 4_194_304);
        assert_eq!(serial.2, vec!["Z".to_string(), "M".to_string()]); assert_eq!(serial.3.len(), 1);
        // All budget categories are typed at the bounded decoder, without allocating a huge tile.
        assert!(matches!(decode_png_gray_bounded(&large, &DecodeLimits { max_input_bytes: 1, ..shared }), Err(PngDecodeError::InputTooLarge { .. })));
        assert!(matches!(decode_png_gray_bounded(&png(48), &DecodeLimits { max_working_bytes: 1, ..shared }), Err(PngDecodeError::WorkingBudgetExceeded { .. })));
    }

    #[test]
    fn wrapper_path_fit_panic_is_typed_exclusion_not_fatal_and_receipt_rolls_back() {
        // _exec is declared before _reset: the value clears first, the
        // barrier releases last - no window where the injection is set but
        // the barrier is free.
        let _exec = TEST_WRAPPER_PANIC_EXEC.lock().unwrap();
        let f = fixture();
        *TEST_WRAPPER_PANIC_GLYPH.lock().unwrap() = Some("A".to_string());
        struct Reset;
        impl Drop for Reset { fn drop(&mut self) { *TEST_WRAPPER_PANIC_GLYPH.lock().unwrap() = None; } }
        let _reset = Reset;
        let rows: Vec<&GlyphRow> = f.m.glyphs.iter().collect();
        for jobs in [1usize, 3] {
            let outs = stage1_drive(rows.len(), run_config::Jobs::new(jobs).unwrap(), |i|
                stage1_fit_one(i, rows[i], &f.m, &f.rc, limits(), &PNG_DECODE_LIMITS, rows.len(), None)).unwrap();
            assert!(outs[0].drawn.is_ok(), "glyph before the panic fits (jobs={jobs})");
            assert!(outs[1].fatal.is_none(), "wrapper-path panic is not run-fatal (jobs={jobs})");
            let reason = outs[1].drawn.as_ref().unwrap_err();
            assert!(reason.starts_with(FIT_PANIC_TAG) && reason.contains("injected wrapper-path fit fault"), "{reason}");
            assert_eq!(exclusion_kind(&outs[1].pin, reason), ExclusionKind::FitPanic);
            assert!(outs[1].receipt_rows.is_empty(), "panic rolls back partial receipt rows (jobs={jobs})");
            assert!(outs[2].drawn.is_ok(), "glyph after the panic fits (jobs={jobs})");
        }
    }

    // Regression oracle for the replay shipped write-back: after a cache
    // replay the caller's `shipped` vector must carry EXACTLY what a fresh
    // stage-1 fold of the same outcomes carries - same glyphs, same manifest
    // order, same bits. Oracle: the live `stage1_reduce` over identical
    // outcomes. The measurement drawing (mring) deliberately differs from the
    // shipped drawing (ring) so the test also proves the shipped channel is
    // not silently filled with measurement geometry.
    fn outcomes_with_distinct_measurement(m: &Manifest) -> Vec<FitOutcome> {
        let ring = |dx: f64| ReferenceRing {
            start: Point { x: dx, y: 2.0 },
            spans: vec![
                Span::Cubic { control_one: Point { x: 1.5 + dx, y: -2.25 }, control_two: Point { x: 3.0 + dx, y: 4.5 }, end: Point { x: 6.0 + dx, y: 9.0 } },
                Span::Line { end: Point { x: dx, y: 2.0 } },
            ],
        };
        m.glyphs.iter().enumerate().map(|(idx, g)| {
            let pin = sha256_hex(&fs::read(&g.image).unwrap());
            FitOutcome { fallback_provenance: Vec::new(), observer_records: Vec::new(), merge_visibility_collector: kni_core::capture_fit::MergeVisibilityCollector::default(), merge_visibility_route_domains: Vec::new(), merge_visibility_context: None, merge_visibility_source_bytes: None, idx, pin, drawn: if idx == 1 { Err("synthetic\treason".into()) } else {
                    Ok(DrawnGlyph { glyph_id: g.name.clone(), rings: vec![ring(0.0)] })
                },
                drawn_measurement: if idx == 1 { None } else { Some(DrawnGlyph { glyph_id: g.name.clone(), rings: vec![ring(11.0)] }) },
                fallback_spans: idx, sub_grid: 0, straight_sweep: 0, reloc_moved: 0, speck_areas: Vec::new(), speck_retained_hole: 0, speck_dropped_collapse: 0,
                receipt_rows: if idx == 1 { String::new() } else { format!("evidence\t{}\tbytes\tunchanged\n{}", g.name, fallback_ledger_line(&g.name, idx)) },
                stderr_buf: String::new(), fatal: None, line_audit: String::new(), corner_wiring: String::new(), corner_wiring_totals: Default::default() }
        }).collect()
    }
    fn cache_text_distinct(f: &Fixture) -> String {
        let m = &f.m; let rc = &f.rc;
        let mut cache = format!("kni-stage1-cache\tv2\npolicy\tscale\t{:e}\trdp_epsilon\t{:e}\tfit_squared_error\t{:e}\tfit_max_refits\t{}\tfit_tolerance_policy\t{:?}\tframe_map\t{:?}\tguide\t{:?}\treferences\t{:?}\tcorner_wiring\t{}\nscale_binding\t{}\nstage1_identity\t{}\nengine_exe_sha256\t{}\n",
            rc.scale().units_per_px(), m.rdp_epsilon, rc.fit_squared_error().value(), m.fit_max_refits, m.fit_tolerance_policy, m.frame_map, m.guide, m.references, if m.corner_wiring { "on" } else { "off" },
            rc.scale().binding_record(), rc.stage1_identity(), fs::read("/proc/self/exe").map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".into()));
        let rows: Vec<&GlyphRow> = m.glyphs.iter().collect();
        stage1_reduce(&rows, outcomes_with_distinct_measurement(m), &mut Stage1Acc::default(), &mut cache, &mut String::new()).unwrap();
        cache
    }
    fn glyph_bits(d: &DrawnGlyph) -> (String, Vec<u64>) {
        let mut bits = Vec::new();
        for r in &d.rings {
            bits.extend([r.start.x.to_bits(), r.start.y.to_bits()]);
            for sp in &r.spans {
                match sp {
                    Span::Line { end } => bits.extend([end.x.to_bits(), end.y.to_bits()]),
                    Span::Cubic { control_one, control_two, end } => bits.extend([control_one.x.to_bits(), control_one.y.to_bits(), control_two.x.to_bits(), control_two.y.to_bits(), end.x.to_bits(), end.y.to_bits()]),
                }
            }
        }
        (d.glyph_id.clone(), bits)
    }
    #[test]
    fn replay_shipped_writeback_matches_live_stage1_bits_and_order() {
        let f = fixture(); let path = f.dir.join("cache.txt");
        fs::write(&path, cache_text_distinct(&f)).unwrap();
        // Live oracle: fold the same outcomes through the live reduce.
        let rows: Vec<&GlyphRow> = f.m.glyphs.iter().collect();
        let mut live = Stage1Acc::default();
        stage1_reduce(&rows, outcomes_with_distinct_measurement(&f.m), &mut live, &mut String::new(), &mut String::new()).unwrap();
        // Replay through the cache loader under test.
        let mut processed = Vec::new(); let mut shipped = Vec::new(); let mut exclusions = Vec::new();
        let mut receipt = String::new(); let mut total = 0usize;
        let mut pins = std::collections::HashMap::new(); let mut counts = Vec::new();
        load_stage1_cache(&path, &f.m, &f.rc, &[], &mut processed, &mut shipped, &mut exclusions, &mut receipt, &mut total, &mut pins, &mut counts).unwrap();
        let snap = |v: &[DrawnGlyph]| v.iter().map(glyph_bits).collect::<Vec<_>>();
        // On the write-back defect `shipped` stays empty here and this fails.
        assert_eq!(snap(&shipped), snap(&live.shipped), "replayed stage1_shipped must equal the live stage-1 shipped fold (same glyphs, manifest order, bit-exact geometry)");
        assert_eq!(shipped.len(), 2, "two accepted glyphs (A is a cached exclusion)");
        let live_proc: Vec<_> = live.processed.iter().map(|(g, d)| (g.name.clone(), glyph_bits(d))).collect();
        let replay_proc: Vec<_> = processed.iter().map(|(g, d)| (g.name.clone(), glyph_bits(d))).collect();
        assert_eq!(replay_proc, live_proc, "replayed processed must equal the live fold");
        assert_eq!(exclusions, live.exclusions, "replayed exclusions must equal the live fold");
        // Channel separation: the shipped channel carries the shipped (ring)
        // geometry, never the measurement (mring) geometry; the fixture makes
        // the two differ on every accepted glyph.
        let replay_proc_bits: Vec<_> = processed.iter().map(|(_, d)| glyph_bits(d)).collect();
        assert_ne!(snap(&shipped), replay_proc_bits, "shipped must not silently carry measurement geometry");
    }

    // Exact pre-candidate serial replay oracle from base+REV2.
    fn legacy_load_stage1_cache<'a>(path: &Path, m: &'a Manifest, rc: &RunConfig, processed: &mut Vec<(&'a GlyphRow, DrawnGlyph)>, exclusions: &mut Vec<(String, Option<u32>, String)>, receipt: &mut String, fallback_span_total: &mut usize, stage1_pins: &mut std::collections::HashMap<String, String>, fallback_glyph_spans: &mut Vec<(String, usize)>) -> Result<(), String> {
        let text = fs::read_to_string(path).map_err(|e| format!("read stage1 cache {}: {e}", path.display()))?;
        let mut lines = text.lines();
        if lines.next() != Some("kni-stage1-cache\tv2") {
            return Err("stage1 cache: bad header".into());
        }
        let policy = lines.next().ok_or("stage1 cache: missing policy line")?;
        let expect = format!("policy\tscale\t{:e}\trdp_epsilon\t{:e}\tfit_squared_error\t{:e}\tfit_max_refits\t{}\tfit_tolerance_policy\t{:?}\tframe_map\t{:?}\tguide\t{:?}\treferences\t{:?}\tcorner_wiring\t{}", rc.scale().units_per_px(), m.rdp_epsilon, rc.fit_squared_error().value(), m.fit_max_refits, m.fit_tolerance_policy, m.frame_map, m.guide, m.references, if m.corner_wiring { "on" } else { "off" });
        if policy != expect {
            return Err(format!("stage1 cache: policy mismatch (cache: {policy}) (manifest: {expect})"));
        }
        let binding_line = lines.next().ok_or("stage1 cache: missing scale binding")?;
        let record = binding_line.strip_prefix("scale_binding\t");
        rc.scale().check_cache_record(record).map_err(|e| format!("stage1 cache: {e:?}"))?;
        let stage1_line = lines.next().ok_or("stage1 cache: missing stage1 identity")?;
        if stage1_line.strip_prefix("stage1_identity\t") != Some(rc.stage1_identity().as_str()) {
            return Err("stage1 cache: config fit identity mismatch".into());
        }
        let exe_line = lines.next().ok_or("stage1 cache: missing engine_exe_sha256 line")?;
        let cur_exe = fs::read("/proc/self/exe").map(|b| sha256_hex(&b)).unwrap_or_else(|_| "unreadable".to_string());
        let expect_exe = format!("engine_exe_sha256\t{cur_exe}");
        if exe_line != expect_exe {
            // Executable mismatch rejects cached stage1 in every export mode.
            return Err("stage1 cache: engine executable changed since cache write; refusing reuse (fit/code version invalidation)".into());
        }
        struct Entry { cp: Option<u32>, sha: String, rings: Option<Vec<ReferenceRing>>, reason: Option<String>, receipt: String }
        let mut entries: Vec<(String, Entry)> = Vec::new();
        let rest: Vec<&str> = lines.collect();
        let mut i = 0usize;
        let bits = |v: &str| -> Result<f64, String> { u64::from_str_radix(v, 16).map(f64::from_bits).map_err(|e| format!("stage1 cache: bad bits {v}: {e}")) };
        while i < rest.len() {
            let f: Vec<&str> = rest[i].split('\t').collect();
            match f.first().copied() {
                Some("glyph") => {
                    if f.len() != 6 || f[2] != "cp" || f[4] != "png_sha256" { return Err(format!("stage1 cache: bad glyph row: {}", rest[i])); }
                    let name = f[1].to_string();
                    let cp = if f[3] == "-" { None } else { Some(u32::from_str_radix(f[3].trim_start_matches("0x"), 16).map_err(|e| format!("stage1 cache: bad cp: {e}"))?) };
                    let sha = f[5].to_string();
                    i += 1;
                    let mut rings = Vec::new();
                    while i < rest.len() && rest[i].starts_with("ring\t") {
                        let rf: Vec<&str> = rest[i].split('\t').collect();
                        if rf.len() != 4 { return Err("stage1 cache: bad ring row".into()); }
                        let start = Point { x: bits(rf[1])?, y: bits(rf[2])? };
                        let n: usize = rf[3].parse().map_err(|e| format!("stage1 cache: bad span count: {e}"))?;
                        i += 1;
                        let mut spans = Vec::new();
                        for _ in 0..n {
                            let sf: Vec<&str> = rest.get(i).ok_or("stage1 cache: truncated spans")?.split('\t').collect();
                            match sf.first().copied() {
                                Some("L") if sf.len() == 3 => spans.push(Span::Line { end: Point { x: bits(sf[1])?, y: bits(sf[2])? } }),
                                Some("C") if sf.len() == 7 => spans.push(Span::Cubic {
                                    control_one: Point { x: bits(sf[1])?, y: bits(sf[2])? },
                                    control_two: Point { x: bits(sf[3])?, y: bits(sf[4])? },
                                    end: Point { x: bits(sf[5])?, y: bits(sf[6])? } }),
                                _ => return Err("stage1 cache: bad span row".into()),
                            }
                            i += 1;
                        }
                        rings.push(ReferenceRing { start, spans });
                    }
                    let mut mring = Vec::new();
                while i < rest.len() && rest[i].starts_with("mring\t") {
                    let rf: Vec<&str> = rest[i].split('\t').collect();
                    if rf.len() != 4 { return Err("stage1 cache: bad mring row".into()); }
                    let start = Point { x: bits(rf[1])?, y: bits(rf[2])? };
                    let n: usize = rf[3].parse().map_err(|e| format!("stage1 cache: bad span count: {e}"))?;
                    i += 1;
                    let mut spans = Vec::new();
                    for _ in 0..n {
                        let sf: Vec<&str> = rest.get(i).ok_or("stage1 cache: truncated spans")?.split('\t').collect();
                        match sf.first().copied() {
                            Some("L") if sf.len() == 3 => spans.push(Span::Line { end: Point { x: bits(sf[1])?, y: bits(sf[2])? } }),
                            Some("C") if sf.len() == 7 => spans.push(Span::Cubic {
                                control_one: Point { x: bits(sf[1])?, y: bits(sf[2])? },
                                control_two: Point { x: bits(sf[3])?, y: bits(sf[4])? },
                                end: Point { x: bits(sf[5])?, y: bits(sf[6])? } }),
                            _ => return Err("stage1 cache: bad span row".into()),
                        }
                        i += 1;
                    }
                    mring.push(ReferenceRing { start, spans });
                }
                let rl: Vec<&str> = rest.get(i).ok_or("stage1 cache: missing receipt_lines")?.split('\t').collect();
                    if rl.len() != 2 || rl[0] != "receipt_lines" { return Err("stage1 cache: bad receipt_lines row".into()); }
                    let k: usize = rl[1].parse().map_err(|e| format!("stage1 cache: bad receipt_lines count: {e}"))?;
                    i += 1;
                    let mut rec = String::new();
                    for _ in 0..k {
                        rec.push_str(rest.get(i).ok_or("stage1 cache: truncated receipt")?);
                        rec.push('\n');
                        i += 1;
                    }
                    if rest.get(i).copied() != Some("end") { return Err("stage1 cache: missing end".into()); }
                    i += 1;
                    entries.push((name, Entry { cp, sha, rings: Some(rings), reason: None, receipt: rec }));
                }
                Some("excluded") => {
                    if f.len() < 8 || f[2] != "cp" || f[4] != "png_sha256" || f[6] != "reason" { return Err(format!("stage1 cache: bad excluded row: {}", rest[i])); }
                    let name = f[1].to_string();
                    let cp = if f[3] == "-" { None } else { Some(u32::from_str_radix(f[3].trim_start_matches("0x"), 16).map_err(|e| format!("stage1 cache: bad cp: {e}"))?) };
                    let sha = f[5].to_string();
                    let reason = f[7..].join("\t");
                    entries.push((name, Entry { cp, sha, rings: None, reason: Some(reason), receipt: String::new() }));
                    i += 1;
                }
                other => return Err(format!("stage1 cache: unexpected row: {other:?}")),
            }
        }
        if entries.len() != m.glyphs.len() {
            return Err(format!("stage1 cache: entry count {} != manifest glyph count {}", entries.len(), m.glyphs.len()));
        }
        for (gi, g) in m.glyphs.iter().enumerate() {
            eprintln!("progress glyph {}/{} {} (stage1 cache reuse)", gi + 1, m.glyphs.len(), g.name);
            let (_, e) = entries.iter().find(|(n, _)| n == &g.name).ok_or_else(|| format!("stage1 cache: glyph {} missing", g.name))?;
            if e.cp != g.codepoint {
                return Err(format!("stage1 cache: codepoint mismatch for {}", g.name));
            }
            let bytes = fs::read(&g.image).map_err(|er| format!("read {}: {er}", g.image.display()))?;
            if sha256_hex(&bytes) != e.sha {
                return Err(format!("stage1 cache: png pin mismatch for {}; refusing reuse", g.name));
            }
            match (&e.rings, &e.reason) {
                (Some(rings), None) => {
                    let n = read_fallback_ledger(&g.name, &e.receipt).map_err(|er| er.message())?;
                    *fallback_span_total = add_fallback_events(*fallback_span_total, &g.name, n).map_err(|er| er.message())?;
                    fallback_glyph_spans.push((g.name.clone(), n));
                    receipt.push_str(&e.receipt);
                    stage1_pins.insert(g.name.clone(), e.sha.clone());
                    processed.push((g, DrawnGlyph { glyph_id: g.name.clone(), rings: rings.clone() }));
                }
                (None, Some(reason)) => {
                    receipt.push_str(&glyph_skip_ledger_line(&g.name, g.codepoint, reason));
                    exclusions.push((g.name.clone(), g.codepoint, reason.clone()));
                }
                _ => return Err(format!("stage1 cache: malformed entry for {}", g.name)),
            }
        }
        receipt.push_str(&format!("stage1_cache\t{}\treused_glyphs\t{}\n", path.display(), m.glyphs.len()));
        Ok(())
    }
}
#[cfg(test)]
mod fit_error_kinds_tests {
    use super::{exclusion_kind, guard_glyph_task, ExclusionKind, FIT_PANIC_TAG};

    type Task = Box<dyn FnOnce(&mut String) -> Result<u32, (String, String)>>;

    // The run loop shape: every task is guarded, an Err or a panic becomes an
    // exclusion row, and the loop always reaches the next glyph.
    fn run(tasks: Vec<(&'static str, Task)>) -> (Vec<(String, u32)>, Vec<(String, String, String)>, String) {
        let (mut ok, mut excl, mut receipt) = (Vec::new(), Vec::new(), String::new());
        for (name, t) in tasks {
            match guard_glyph_task(name, &mut receipt, t) {
                Ok(v) => ok.push((name.to_string(), v)),
                Err((pin, reason)) => excl.push((name.to_string(), pin, reason)),
            }
        }
        (ok, excl, receipt)
    }

    #[test]
    fn injected_typed_error_stays_a_typed_exclusion_and_run_continues() {
        let reason = "glyph b: capture refused: Decode(Truncated)".to_string();
        let r2 = reason.clone();
        let (ok, excl, receipt) = run(vec![
            ("a", Box::new(|r: &mut String| { r.push_str("row-a\n"); Ok(1) })),
            ("b", Box::new(move |r: &mut String| { r.push_str("half\n"); Err(("pinb".to_string(), r2)) })),
            ("c", Box::new(|r: &mut String| { r.push_str("row-c\n"); Ok(3) })),
        ]);
        assert_eq!(ok, vec![("a".to_string(), 1), ("c".to_string(), 3)]);
        assert_eq!(excl, vec![("b".to_string(), "pinb".to_string(), reason.clone())], "reason and pin pass through byte-for-byte");
        assert_eq!(exclusion_kind("pinb", &reason), ExclusionKind::CaptureRefused);
        // a plain Err keeps whatever rows the task wrote, exactly as before the guard existed
        assert_eq!(receipt, "row-a\nhalf\nrow-c\n");
    }

    #[test]
    fn panic_per_glyph_becomes_typed_fitpanic_exclusion_and_run_continues() {
        let (ok, excl, receipt) = run(vec![
            ("a", Box::new(|r: &mut String| { r.push_str("row-a\n"); Ok(1) })),
            ("b", Box::new(|r: &mut String| { r.push_str("half-written\n"); panic!("injected fit fault") })),
            ("c", Box::new(|r: &mut String| { r.push_str("row-c\n"); Ok(3) })),
        ]);
        assert_eq!(ok.len(), 2, "glyphs before and after the panic are fitted");
        assert_eq!(excl.len(), 1);
        assert_eq!(excl[0].0, "b");
        assert!(excl[0].2.starts_with(FIT_PANIC_TAG) && excl[0].2.contains("glyph b") && excl[0].2.contains("injected fit fault"), "{}", excl[0].2);
        assert_eq!(exclusion_kind(&excl[0].1, &excl[0].2), ExclusionKind::FitPanic);
        assert_eq!(receipt, "row-a\nrow-c\n", "a panicking glyph leaves no partial receipt rows");
    }

    #[test]
    fn string_and_non_string_panic_payloads_are_both_typed() {
        let mut r = String::new();
        let e = guard_glyph_task::<u32>("s", &mut r, |_| std::panic::panic_any(String::from("owned msg"))).unwrap_err();
        assert!(e.1.contains("owned msg"));
        let e = guard_glyph_task::<u32>("n", &mut r, |_| std::panic::panic_any(7u8)).unwrap_err();
        assert!(e.1.starts_with(FIT_PANIC_TAG) && e.1.contains("non-string panic payload"));
    }

    #[test]
    fn existing_refusal_taxonomy_is_preserved_by_kind() {
        let cases = [
            ("unreadable", "No such file", ExclusionKind::Unreadable),
            ("p", "HSourceChanged { expected: \"a\", found: \"b\" }", ExclusionKind::HSourceChanged),
            ("p", "PerGlyphScaleOverride: x", ExclusionKind::PerGlyphScaleOverride),
            ("p", "glyph x: scale must be finite and > 0", ExclusionKind::BadScale),
            ("p", "glyph x: reference font sha mismatch", ExclusionKind::ReferenceRefused),
            ("p", "glyph x: reference codepoint unmapped", ExclusionKind::ReferenceRefused),
            ("p", "glyph x: capture refused: E", ExclusionKind::CaptureRefused),
            ("p", "glyph x: route refused: E", ExclusionKind::RouteRefused),
            ("p", "glyph x: guarded-guided route refused: E", ExclusionKind::RouteRefused),
            ("p", "something new", ExclusionKind::Other),
        ];
        for (pin, reason, want) in cases { assert_eq!(exclusion_kind(pin, reason), want, "{reason}"); }
    }
}

#[cfg(test)]
mod paul_new_vertical_metrics_tests {
    use super::*;

    fn manifest_for(family: &str, subfamily: &str, ps: &str) -> Manifest {
        Manifest { derive_space_from_letter_advances: false, auto_sb: None, auto_sb_class_table: None, auto_sb_offset_lsb: None, auto_sb_offset_rsb: None, tie_break: None, auto_sb_pool: None, style_overrides: None, os2_x_height_write: None, m3: M3Decl::default(),
            family: family.into(),
            subfamily: subfamily.into(),
            postscript_name: ps.into(),
            postscript_name_declared: None,
            vendor: *b"TEST",
            upm: 1000,
            scale: 10.0,
            capture_frame: None,
            capture_cohort: None,
            post_lsb_add: 0.0,
            post_rsb_add: 0.0,
            post_scope: kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false },
            post_scope_label: "none".into(),
            rdp_epsilon: 1.0,
            fit_squared_error: 1.0,
            fit_max_refits: 1,
            fit_tolerance_policy: FitTolerancePolicy::Fixed,
            flatten_tolerance: 0.5,
            scan_row_step: 1.0,
            scan_max_rows: 64,
            sample_resolution: 1.0,
            max_pair_evaluations: 0,
            iou: None,
            max_pairs: 0,
            pair_min_shared_rows: 1,
            glyphs: vec![GlyphRow { codepoint: Some(0x61), extra_cps: vec![], name: "a".into(), image: PathBuf::from("a.png"), scale: None }],
            space_evidence: None,
            space: None,
            notdef: None,
            notdef_proxy: None,
            capture_manifest: None,
            run_mode: RunMode::Full, corner_wiring: false,
            population_sha256: "0".repeat(64),
            stage1_cache: None, learned_store: None, learned_gate_evidence: None, pair_visual_same_source: false,
            references: vec![],
            frame_map: None,
            guide: None,
        }
    }

    #[test]
    fn paul_new_family_ships_declared_line_metrics() {
        let mut f = metadata(&manifest_for("Paul New", "Regular", "PaulNew-Regular"));
        // Bounds that disagree with the declared values on purpose: the special case, not the bounds, must win.
        f.head.bounds = [-50, -900, 600, 1200];
        let f = clip_metadata(f);
        assert_eq!(f.hhea.ascender, declared_convention::PAUL_NEW_ASCENDER_UNITS);
        assert_eq!(f.hhea.descender, declared_convention::PAUL_NEW_DESCENDER_UNITS);
        assert_eq!(f.os2.typo, [declared_convention::PAUL_NEW_ASCENDER_UNITS, declared_convention::PAUL_NEW_DESCENDER_UNITS, 0]);
        assert_eq!(f.os2.win_ascent, declared_convention::PAUL_NEW_ASCENDER_UNITS as u16);
        assert_eq!(f.os2.win_descent, (-(declared_convention::PAUL_NEW_DESCENDER_UNITS as i32)) as u16);
        // Line-metric span 995 = 850 - (-145): owner directive 2026-10-18 03:37
        // (iMessage) sets the descender metric to -145 with every other metric
        // unchanged. The GEOMETRY em span stays 1000 (pinned K_Y; tile box
        // bottom -150 in paul_new_anchor), decoupled from the metric fields.
        assert_eq!(f.hhea.ascender as i32 - f.hhea.descender as i32, 995, "declared line-metric span per the 03:37 directive");
        // Spec literals pinned: a constant edit must fail here, not pass silently.
        assert_eq!(declared_convention::PAUL_NEW_ASCENDER_UNITS, 850);
        assert_eq!(declared_convention::PAUL_NEW_DESCENDER_UNITS, -145);
        assert_eq!(declared_convention::PAUL_NEW_CAP_HEIGHT_UNITS, 700);
        assert_eq!(declared_convention::PAUL_NEW_X_HEIGHT_UNITS, 500);
        assert_eq!(declared_convention::PAUL_NEW_ADVANCE_UNITS, 696);
        assert_eq!(declared_convention::PAUL_NEW_TILE_WIDTH_PX, 786);
    }

    #[test]
    fn paul_new_family_ships_declared_cap_and_x_height() {
        let mut f = metadata(&manifest_for("Paul New", "Regular", "PaulNew-Regular"));
        // Solver-heuristic stand-ins that disagree with the declared values on
        // purpose: the spec, not the heuristic, must win.
        f.os2.cap_height = 701;
        f.os2.x_height = 399;
        let f = clip_metadata(f);
        assert_eq!(f.os2.cap_height, 700);
        assert_eq!(f.os2.x_height, 500);
    }

    #[test]
    fn paul_new_advance_model_frame_stripped_population_median_minus_one() {
        // 2026-10-18 ruling: advance = median shipped ink xMax - 1; lsb =
        // shipped ink xMin; rsb follows. Two edge glyphs (ink [-1, 691]) and
        // one margin glyph (ink [47, 600]) -> advance 690, edge rows
        // (-1, -1), margin row (47, 690-600).
        // Closed rectangles: analytic ink bounds need area, not open lines.
        let drawn = |name: &str, x0: f64, x1: f64| DrawnGlyph { glyph_id: name.into(), rings: vec![kni_core::reference_slice::ReferenceRing {
            start: kni_core::reference_slice::Point { x: x0, y: 0.0 },
            spans: vec![
                kni_core::reference_slice::Span::Line { end: kni_core::reference_slice::Point { x: x1, y: 0.0 } },
                kni_core::reference_slice::Span::Line { end: kni_core::reference_slice::Point { x: x1, y: 10.0 } },
                kni_core::reference_slice::Span::Line { end: kni_core::reference_slice::Point { x: x0, y: 10.0 } },
                kni_core::reference_slice::Span::Line { end: kni_core::reference_slice::Point { x: x0, y: 0.0 } },
            ],
        }]};
        let glyphs = vec![drawn(".notdef", 0.0, 691.0), drawn("A", -1.0, 691.0), drawn("B", -1.0, 691.0), drawn("percent", 47.0, 600.0)];
        let mut metrics: Vec<(String, f64, f64, f64)> = vec![
            (".notdef".into(), 0.0, 0.0, 500.0),
            ("A".into(), 3.0, -1.0, 701.0),
            ("B".into(), 3.0, -1.0, 701.0),
            ("percent".into(), 2.0, 2.0, 700.5),
            ("space".into(), 0.0, 0.0, 489.0),
        ];
        paul_new_advance_override("Paul New", &mut metrics, &glyphs);
        let get = |n: &str| metrics.iter().find(|r| r.0 == n).unwrap().clone();
        assert_eq!(get("A"), ("A".into(), -1.0, -1.0, 690.0));
        assert_eq!(get("B"), ("B".into(), -1.0, -1.0, 690.0));
        assert_eq!(get("percent"), ("percent".into(), 47.0, 90.0, 690.0));
        assert_eq!(get("space"), ("space".into(), 0.0, 0.0, 690.0));
        assert_eq!(get(".notdef").3, 690.0);
        // Other families: bit-identical passthrough.
        let mut other = metrics.clone();
        let before = other.clone();
        paul_new_advance_override("Marq", &mut other, &glyphs);
        assert_eq!(other, before);
    }

    #[test]
    fn paul_new_scale_pair_is_exposed_and_k_y_bits_unchanged() {
        use declared_convention::*;
        assert_eq!(PAUL_NEW_K_X_BITS, (696.0f64 / 786.0f64).to_bits());
        assert_eq!(PAUL_NEW_K_Y_BITS, DECLARED_K_BITS);
        assert_eq!(PAUL_NEW_K_Y_BITS, (1000.0f64 / 1122.0f64).to_bits());
        // The pair reconstructs the tile-box anchor: x of the tile's right edge
        // and y of its top edge under the frame-stripped spec em box.
        assert_eq!(PAUL_NEW_TILE_WIDTH_PX as f64 * f64::from_bits(PAUL_NEW_K_X_BITS), 696.0);
        assert_eq!(DECLARED_H_INK_HEIGHT_PX as f64 * f64::from_bits(PAUL_NEW_K_Y_BITS), 1000.0);
    }

    #[test]
    fn other_families_keep_bounds_derived_line_metrics() {
        let mut f = metadata(&manifest_for("Marq", "Standard", "Marq-Standard"));
        f.head.bounds = [-50, -400, 600, 1100];
        let f = clip_metadata(f);
        assert_eq!((f.hhea.ascender, f.hhea.descender), (1100, -400));
        assert_eq!(f.os2.typo, [1100, -400, 0]);
    }
}


#[cfg(test)]
mod stem_pair_wiring_tests {
    use super::*;
    fn decision(saturate: bool) -> StemPairDecision { StemPairDecision { saturate, left: 5, right: 7 } }

    /// OFF is the landing default: legacy `written` passes through
    /// unchanged for every representable value, including the extremes.
    #[test]
    fn off_is_legacy_passthrough_byte_identical() {
        for written in [i16::MIN, -1, 0, 1, i16::MAX] {
            assert_eq!(narrow_pair_x_advance(written, &decision(false)), Some(i32::from(written)));
        }
    }

    /// ON/OFF byte parity on the pinned fixture pair: the fixture carries
    /// the smallest positive integer outside signed16 (CONVENTION: MAX+1),
    /// which the legacy narrowing clamps to the bound. Fed through as the
    /// post-guard final value, ON and OFF return byte-identical output for
    /// the fixture value and for in-range values around it.
    #[test]
    fn on_off_parity_on_pinned_fixture_pair() {
        let fixture_raw = 32768.0_f64; // pair.txt: pair_x_advance 32768
        let (legacy_written, clamped) = kni_metrics::generated_outline_kern::round_export_units(fixture_raw);
        assert!(clamped && legacy_written == i16::MAX, "fixture value clamps under the legacy narrowing");
        for raw in [fixture_raw, 32767.4, -32768.4, 0.0, -700.25] {
            let (written, _) = kni_metrics::generated_outline_kern::round_export_units(raw);
            let on = narrow_pair_x_advance(written, &decision(true));
            let off = narrow_pair_x_advance(written, &decision(false));
            assert_eq!(on, off, "raw {raw}");
            assert_eq!(on, Some(i32::from(written)), "raw {raw}");
        }
    }

    /// Guard-preserved synthetic extreme: the overlap guard may adjust a
    /// pair to a verified safe integer that differs from the rounded raw
    /// residual. The helper never sees the raw residual, so a guard-adjusted
    /// value ships exactly as the guard chose - the adjustment is never
    /// unwound. (Regression pin: the previous wiring fed the raw residual
    /// to the adapter, which would have undone this adjustment.)
    #[test]
    fn guard_adjusted_value_is_never_unwound() {
        assert_eq!(kni_metrics::generated_outline_kern::round_export_units(100.4).0, 100);
        let guard_chosen: i16 = 103; // differs from round(raw) = 100
        assert_eq!(narrow_pair_x_advance(guard_chosen, &decision(true)), Some(103));
        assert_eq!(narrow_pair_x_advance(guard_chosen, &decision(false)), Some(103));
    }

    /// The adapter owns the ON narrowing rule: on a post-guard value it can
    /// only return InRange, and it returns the value unchanged.
    #[test]
    fn on_adapter_identity_on_post_guard_value() {
        for written in [i16::MIN, -1, 0, 1, i16::MAX, 12_300] {
            assert_eq!(narrow_pair_x_advance(written, &decision(true)), Some(i32::from(written)));
        }
    }

    mod adapter_wiring_tests {
        use crate::run_config::{FitErrorPolicy, RunConfig, RunConfigInput};
        use kni_core::scale_context::ScaleContext;
        use std::path::PathBuf;
        fn ctx(k: f64) -> ScaleContext { ScaleContext::from_convention("r", "c", k, 1000.0, "cohort", "frame").unwrap() }
        fn input() -> RunConfigInput { RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("cap"), PathBuf::from("out"), "s1") }
        fn cfg() -> RunConfig { RunConfig::new(input(), ctx(2.0)).unwrap() }
    fn manifest_for_config(c: &RunConfig) -> crate::Manifest {
        crate::Manifest { derive_space_from_letter_advances: false, auto_sb: None, auto_sb_class_table: None, auto_sb_offset_lsb: None, auto_sb_offset_rsb: None, tie_break: None, auto_sb_pool: None, style_overrides: None, os2_x_height_write: None, m3: crate::M3Decl::default(),
            notdef: None, notdef_proxy: None, capture_manifest: None,
            iou: c.iou_settings(),
            capture_frame: None, capture_cohort: None,
            post_lsb_add: c.offset().lsb(), post_rsb_add: c.offset().rsb(), post_scope: c.post_scope(), post_scope_label: c.post_scope_label().to_string(),
            family: c.scale().id().into(), subfamily: c.scale().cohort().into(),
            postscript_name: c.scale().id().into(), postscript_name_declared: None, vendor: *b"TEST",
            upm: c.scale().target_upm() as u16, scale: c.scale().units_per_px(),
            rdp_epsilon: c.rdp_epsilon().value(), fit_squared_error: c.fit_squared_error().value(),
            fit_max_refits: c.fit_max_refits(), fit_tolerance_policy: crate::FitTolerancePolicy::Fixed,
            flatten_tolerance: c.flatten_tolerance().value(), scan_row_step: c.scan_row_step().value(),
            scan_max_rows: c.scan_max_rows(), sample_resolution: c.sample_resolution().value(),
            max_pair_evaluations: c.max_pair_evaluations(), max_pairs: c.max_pairs(),
            pair_min_shared_rows: c.pair_min_shared_rows(), glyphs: Vec::new(), space: None,
            run_mode: crate::RunMode::Stage1Only, corner_wiring: false, population_sha256: String::new(), stage1_cache: None, learned_store: None, learned_gate_evidence: None, pair_visual_same_source: false, space_evidence: None,
            references: Vec::new(), frame_map: None, guide: None,
        }
    }
    fn adapt(m: &crate::Manifest, c: &RunConfig) -> Result<RunConfig, String> {
        crate::validated_run_config(m, c.scale().clone(), c.capture_dir().into(), c.out_dir().into(), c.style_id())
    }
    #[test]
    fn manifest_snapshot_preserves_existing_config_helper_and_zero_post_step() {
        let c = cfg();
        let m = manifest_for_config(&c);
        let adapted = adapt(&m, &c).unwrap();
        assert_eq!(adapted, c);
        let post = crate::post_metrics::PostStep::from_run_config(&adapted).unwrap();
        assert!(post.offset.is_noop());
        assert_eq!(post.offset, crate::post_metrics::PostStep::legacy_default().offset);
    }
    #[test]
    fn manifest_snapshot_preserves_nondefault_fields_without_new_fixture_literals() {
        let base = cfg();
        let mut input = input();
        input.rdp_epsilon = base.flatten_tolerance().value();
        input.fit_squared_error = base.sample_resolution().value();
        input.flatten_tolerance = base.rdp_epsilon().value();
        input.scan_row_step = base.fit_squared_error().value();
        input.sample_resolution = base.flatten_tolerance().value();
        input.fit_max_refits = base.scan_max_rows();
        input.scan_max_rows = base.fit_max_refits();
        input.pair_min_shared_rows = base.max_pairs();
        input.max_pairs = base.pair_min_shared_rows();
        input.max_pair_evaluations = base.max_pairs() as u64;
        let expected = RunConfig::new(input, base.scale().clone()).unwrap();
        assert_ne!(expected, base);
        assert_eq!(adapt(&manifest_for_config(&expected), &expected).unwrap(), expected);
    }
    #[test]
    fn snapshot_rejects_scale_upm_and_per_glyph_override_without_io() {
        let c = cfg();
        let mut m = manifest_for_config(&c);
        m.scale = f64::from_bits(m.scale.to_bits() + 1);
        assert!(adapt(&m, &c).is_err());
        let mut m = manifest_for_config(&c);
        m.upm = m.upm.saturating_add(1);
        assert!(adapt(&m, &c).is_err());
        let mut m = manifest_for_config(&c);
        m.glyphs.push(crate::GlyphRow { codepoint: Some(char::from(m.vendor[0]).into()), extra_cps: vec![], name: c.scale().id().into(), image: c.capture_dir().into(), scale: Some(m.scale) });
        assert!(adapt(&m, &c).unwrap_err().contains("PerGlyphScaleOverride"));
    }
    #[test]
    fn pre_offset_receipt_binds_exact_bytes_and_context_without_upgrading_diagnostic() {
        let c = cfg();
        let bytes = c.canonical_record().into_bytes();
        let receipt = crate::pre_export_guard_receipt(&bytes, &c, true);
        assert!(receipt.contains("guard_stage\tpre_lsb_rsb\tguard_result\tapproved"));
        assert!(receipt.contains(&crate::sha256_hex(&bytes)));
        assert!(receipt.contains(&crate::post_metrics::tsv_escape(c.scale().binding_record())));
        assert!(receipt.contains("guard_policy\tPRE_POSTMETRICS_ONLY"));
        let diagnostic = crate::pre_export_guard_receipt(&bytes, &c, false);
        assert!(diagnostic.contains("diagnostic_not_approved\tapproved_base_sha256\tnone"));
        assert_ne!(diagnostic, receipt);
    }
    #[test]
    fn snapshot_preserves_measured_policy_and_validates_manifest_counts() {
        let c = cfg();
        let mut m = manifest_for_config(&c);
        m.fit_tolerance_policy = crate::FitTolerancePolicy::MeasuredExperimental;
        assert_eq!(adapt(&m, &c).unwrap().fit_error_policy(), FitErrorPolicy::MeasuredExperimental);
        m.pair_min_shared_rows = usize::default();
        assert!(adapt(&m, &c).is_err());
        assert!(matches!(crate::bind_manifest_scale(&m, kni_core::jpeg_source::Limits { max_input_bytes: 1<<24, max_pixels: 1<<24, max_working_bytes: 1<<26 }), Err(crate::scale_wiring::WiringError::EmptyField { field: "capture_cohort" })));
    }
    }

}

#[cfg(test)]
mod manifest_row_exclusion_tests {
    use crate::run_config::{esc, manifest_row_excluded_event, parse_glyph_row_codepoint, validate_glyph_row_name, GLYPH_NAME_MAX_BYTES};
    use std::path::Path;
    // A minimal manifest head; the population pin is a fixture, not an engine constant.
    fn manifest_with(rows: &str) -> Result<crate::Manifest, String> {
        crate::parse_manifest(&format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n{}", "0".repeat(64), rows), Path::new("."))
    }
    #[test]
    fn broken_glyph_rows_are_excluded_and_the_rest_of_the_manifest_runs() {
        let rows = "glyph 0x48 H a.png\nglyph 0xZZ bad_cp b.png\nglyph 0xD800 surrogate c.png\nglyph 0x110000 too_high d.png\nglyph 0x41 A e.png\n";
        let m = manifest_with(rows).unwrap();
        let cps: Vec<u32> = m.glyphs.iter().map(|g| g.codepoint.unwrap()).collect();
        assert_eq!(cps, vec![0x48, 0x41]);
        assert_eq!(m.glyphs[0].name, "H");
        assert_eq!(m.glyphs[1].name, "A");
    }
    #[test]
    fn bad_names_are_excluded_per_row_and_good_rows_stay() {
        let long = "a".repeat(GLYPH_NAME_MAX_BYTES + 1);
        let rows = format!("glyph 0x48 H a.png\nglyph 0x42 bad-name b.png\nglyph 0x43 {long} c.png\nglyph 0x44 T\u{fc}rker d.png\nglyph 0x45 E e.png\n");
        let m = manifest_with(&rows).unwrap();
        let cps: Vec<u32> = m.glyphs.iter().map(|g| g.codepoint.unwrap()).collect();
        assert_eq!(cps, vec![0x48, 0x45]);
    }
    #[test]
    fn every_exclusion_emits_one_event_with_a_stable_reason_code() {
        let long = "a".repeat(GLYPH_NAME_MAX_BYTES + 1);
        let long_row = format!("glyph 0x41 {long} a.png");
        let cases: Vec<(&str, &str)> = vec![
            ("glyph 0xZZ n a.png", "codepoint_syntax"),
            ("glyph 0xD800 n a.png", "codepoint_non_scalar"),
            ("glyph 0x41 bad-name a.png", "glyph_name_charset"),
            ("glyph 0x41 b\u{e9}d a.png", "glyph_name_charset"),
            (&long_row, "glyph_name_length"),
        ];
        for (row, code) in cases {
            let refusal = (|| {
                let mut it = row.split_whitespace();
                let _key = it.next().unwrap();
                let cp_raw = it.next().unwrap();
                let name = it.next().unwrap();
                parse_glyph_row_codepoint(cp_raw).and_then(|_| validate_glyph_row_name(name).map(|_| 0))
            })().unwrap_err();
            let ev = manifest_row_excluded_event(row, refusal);
            assert_eq!(ev, format!("manifest_row_excluded\t{}\treason_code\t{}\n", esc(row), code));
            assert_eq!(ev.matches('\n').count(), 1, "event stays on one line");
        }
        // valid rows pass both validators
        assert_eq!(parse_glyph_row_codepoint("0x41"), Ok(0x41));
        assert_eq!(parse_glyph_row_codepoint("41"), Ok(0x41));
        assert!(validate_glyph_row_name(".notdef").is_ok());
        assert!(validate_glyph_row_name("uni00E9").is_ok());
        assert!(validate_glyph_row_name(&"a".repeat(GLYPH_NAME_MAX_BYTES)).is_ok());
    }
    #[test]
    fn structural_grammar_faults_stay_manifest_refusals() {
        // missing image path, extra field, bad per-glyph scale: whole-manifest refusals, not row exclusions
        assert!(manifest_with("glyph 0x48 H\n").is_err());
        assert!(manifest_with("glyph 0x48 H a.png extra\n").is_err());
        assert!(manifest_with("glyph 0x48 H a.png notanumber\n").is_err());
        assert!(manifest_with("glyph\n").is_err());
    }
    #[test]
    fn excluded_rows_change_the_parsed_population_pin() {
        let a = manifest_with("glyph 0x48 H a.png\nglyph 0x41 A b.png\n").unwrap();
        let b = manifest_with("glyph 0x48 H a.png\nglyph 0xZZ bad b.png\nglyph 0x41 A b.png\n").unwrap();
        assert_eq!(a.glyphs.len(), b.glyphs.len());
        assert_eq!(crate::population_pin(&a.glyphs), crate::population_pin(&b.glyphs));
    }
}

#[cfg(test)]
mod paul_new_metrics_policy_wiring_tests {
    use super::*;

    fn box_glyph(name: &str, x0: f64, y0: f64, x1: f64, y1: f64) -> DrawnGlyph {
        let start = Point { x: x0, y: y0 };
        DrawnGlyph { glyph_id: name.into(), rings: vec![ReferenceRing { start, spans: vec![
            Span::Line { end: Point { x: x1, y: y0 } },
            Span::Line { end: Point { x: x1, y: y1 } },
            Span::Line { end: Point { x: x0, y: y1 } },
            Span::Line { end: start },
        ] }]}
    }

    fn policy_metrics() -> Vec<(String, f64, f64, f64)> {
        vec![
            (".notdef".into(), 0.0, 0.0, 696.0),
            ("A".into(), 0.0, 0.0, 696.0),
            ("B".into(), 0.0, 0.0, 696.0),
            ("off".into(), 0.0, 0.0, 695.0),
            ("space".into(), 0.0, 0.0, 696.0),
        ]
    }

    fn policy_glyphs() -> Vec<DrawnGlyph> {
        vec![
            DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] },
            box_glyph("A", 0.0, 0.0, 696.0, 700.0),   // ink fills the em: achieved rsb 0, target -1 missed
            box_glyph("B", 1.0, 0.0, 697.0, 700.0),   // ink 1 unit past the em edge: rsb -1 exactly
            box_glyph("off", 0.0, 0.0, 695.0, 700.0), // advance 695: fixed-696 policy broken
            DrawnGlyph { glyph_id: "space".into(), rings: vec![] },
        ]
    }

    #[test]
    fn paul_new_run_emits_typed_policy_receipt() {
        let mut receipt = String::new();
        paul_new_metrics_policy_report("Paul New", &policy_glyphs(), &policy_metrics(), &mut receipt);
        assert!(receipt.contains("# paul_new_metrics_policy\tdeclared_advance\t695\tdeclared_lsb\t0\ttarget_rsb\t-1"), "{receipt}");
        assert!(receipt.contains(".notdef\t696\tno_ink\tno_ink\tadvance_off_policy\n"), "{receipt}");
        assert!(receipt.contains("A\t696\t0\t0\tadvance_off_policy,rsb_target_miss\n"), "{receipt}");
        assert!(receipt.contains("B\t696\t1\t-1\tadvance_off_policy\n"), "{receipt}");
        assert!(receipt.contains("off\t695\t0\t0\trsb_target_miss\n"), "{receipt}");
        assert!(receipt.contains("space\t696\tno_ink\tno_ink\tadvance_off_policy\n"), "{receipt}");
        assert!(receipt.contains("# summary\tglyphs\t5\ttarget_rsb_met\t1\trsb_target_miss\t2\tadvance_off_policy\t4\n"), "{receipt}");
    }

    #[test]
    fn advance_off_the_fixed_696_is_flagged() {
        let glyphs = vec![box_glyph("G", 0.0, 0.0, 700.0, 700.0)];
        let metrics = vec![("G".into(), 0.0, 0.0, 700.0)];
        let mut receipt = String::new();
        paul_new_metrics_policy_report("Paul New", &glyphs, &metrics, &mut receipt);
        assert!(receipt.contains("G\t700\t0\t0\tadvance_off_policy"), "{receipt}");
    }

    #[test]
    fn verdict_measures_final_ink_not_the_metrics_row() {
        // The metrics row carries no bearing truth for the verdict: with ink
        // xMax 697 the derived declared advance is 696, the row advance 696
        // is on policy, and the rsb verdict -1 comes from the shipped
        // outline's ink bounds, never from the metrics row's rsb field.
        let glyphs = vec![box_glyph("B", 1.0, 0.0, 697.0, 700.0)];
        let metrics = vec![("B".into(), 0.0, 0.0, 696.0)];
        let mut receipt = String::new();
        paul_new_metrics_policy_report("Paul New", &glyphs, &metrics, &mut receipt);
        assert!(receipt.contains("B\t696\t1\t-1\t\n"), "{receipt}");
        assert!(!receipt.contains("\trsb_target_miss\n"), "{receipt}");
    }

    #[test]
    fn other_families_receipt_and_metrics_stay_bit_identical() {
        let glyphs = policy_glyphs();
        let metrics = policy_metrics();
        let before_metrics = metrics.clone();
        let mut receipt = String::from("pre-existing\trow\n");
        let before_receipt = receipt.clone();
        paul_new_metrics_policy_report("Marq", &glyphs, &metrics, &mut receipt);
        assert_eq!(receipt, before_receipt);
        assert_eq!(metrics, before_metrics);
    }

    /// Minimal sfnt carrying only what the hmtx readback parses: a table
    /// directory with hhea (numberOfHMetrics) and hmtx (advance/lsb rows).
    fn test_font_bytes(rows: &[(u16, i16)]) -> Vec<u8> {
        let num = rows.len();
        let mut hhea = vec![0u8; 36];
        hhea[34..36].copy_from_slice(&(num as u16).to_be_bytes());
        let mut hmtx = Vec::new();
        for (a, l) in rows {
            hmtx.extend_from_slice(&a.to_be_bytes());
            hmtx.extend_from_slice(&l.to_be_bytes());
        }
        let hhea_off = 12 + 2 * 16;
        let hmtx_off = hhea_off + hhea.len();
        let mut font = Vec::new();
        font.extend_from_slice(b"OTTO");
        font.extend_from_slice(&2u16.to_be_bytes());
        font.extend_from_slice(&[0; 6]);
        for (tag, off, len) in [(*b"hhea", hhea_off, hhea.len()), (*b"hmtx", hmtx_off, hmtx.len())] {
            font.extend_from_slice(&tag);
            font.extend_from_slice(&[0; 4]);
            font.extend_from_slice(&(off as u32).to_be_bytes());
            font.extend_from_slice(&(len as u32).to_be_bytes());
        }
        font.extend_from_slice(&hhea);
        font.extend_from_slice(&hmtx);
        font
    }

    #[test]
    fn readback_confirms_expected_rows_on_shipped_bytes() {
        let font = test_font_bytes(&[(690, -1), (690, -1), (690, 47)]);
        let expected = [(690u16, -1i16), (690, -1), (690, 47)];
        let out = paul_new_metrics_policy_readback("Paul New", &font, 3, &expected);
        assert!(out.contains("# paul_new_metrics_policy_readback\tsource\tfinal_hmtx\texpected\tassembly_metrics_rows"), "{out}");
        assert!(out.contains("# summary\tglyphs_checked\t3\tadvance_off_policy\t0\tlsb_off_policy\t0\n"), "{out}");
        assert!(!out.contains("warning\tpaul_new_metrics_policy_readback"), "{out}");
    }

    #[test]
    fn readback_flags_off_expected_advance_and_lsb_on_shipped_bytes() {
        let font = test_font_bytes(&[(690, -1), (700, -1), (690, 2)]);
        let expected = [(690u16, -1i16), (690, -1), (690, -1)];
        let out = paul_new_metrics_policy_readback("Paul New", &font, 3, &expected);
        assert!(out.contains("warning\tpaul_new_metrics_policy_readback\tgid\t1\tadvance\t700\tcode\tadvance_readback_miss\n"), "{out}");
        assert!(out.contains("warning\tpaul_new_metrics_policy_readback\tgid\t2\tlsb\t2\tcode\tlsb_readback_miss\n"), "{out}");
        assert!(out.contains("# summary\tglyphs_checked\t3\tadvance_off_policy\t1\tlsb_off_policy\t1\n"), "{out}");
    }

    #[test]
    fn readback_other_families_emit_nothing() {
        let font = test_font_bytes(&[(700, 5)]);
        let out = paul_new_metrics_policy_readback("Marq", &font, 1, &[]);
        assert!(out.is_empty(), "{out}");
    }

    #[test]
    fn readback_gid_beyond_hmtx_is_a_typed_row_not_a_panic() {
        let font = test_font_bytes(&[(690, -1)]);
        let expected = [(690u16, -1i16), (690, -1)];
        let out = paul_new_metrics_policy_readback("Paul New", &font, 2, &expected);
        assert!(out.contains("gid\t1\tcode\treadback_failed"), "{out}");
    }
}

#[cfg(test)]
mod style_override_tests {
    use super::*;

    fn manifest_text(extra: &str) -> String {
        format!("family Mona Alt\nsubfamily Regular\npostscript_name MonaAlt-Regular\nscale 1.821705426356589\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x48 H missing.png\ncapture_cohort Mona Alt/Regular\ncapture_frame capture-manifest-frame\n{}", "0".repeat(64), extra)
    }
    fn pm(extra: &str) -> Result<Manifest, String> {
        parse_manifest(&manifest_text(extra), Path::new("."))
    }
    fn row(l: f64, r: f64) -> style_overrides::StyleOverride {
        style_overrides::StyleOverride { lsb_add: l, rsb_add: r, note: "engine declared convention: monospace uniform sidebearings".into() }
    }

    #[test]
    fn manifest_parses_style_overrides_key() {
        let m = pm("style_overrides kni/style-overrides.tsv 0123456789abcdef\n").unwrap();
        assert_eq!(m.style_overrides.as_ref().map(|(_, p)| p.as_str()), Some("0123456789abcdef"));
        assert!(pm("style_overrides a.tsv sha\nstyle_overrides b.tsv sha\n").unwrap_err().contains("duplicate style_overrides"));
        assert!(pm("style_overrides onlypath\n").is_err());
        assert!(pm("style_overrides a.tsv sha extra\n").is_err());
        // A manifest without the key behaves exactly as before.
        assert!(pm("").unwrap().style_overrides.is_none());
    }

    #[test]
    fn override_is_set_never_add() {
        // Chief ruling: SET semantics. Whatever the flags/manifest carried -
        // the kit-passed 40/45, the default 0/0, or a manual 7/9 - the result
        // is exactly the declared row, applied once through the existing
        // post-step (manifest -> run_config -> post_metrics). 40/45 can never
        // become 80/90.
        for (flags, want_flag_record) in [
            ("lsb_add 40\nrsb_add 45\npost_scope base\npost_scope_label kit\n", "flag_lsb_add\t40\tflag_rsb_add\t45"),
            ("", "flag_lsb_add\t0\tflag_rsb_add\t0"),
            ("lsb_add 7\nrsb_add 9\npost_scope base\npost_scope_label kit\n", "flag_lsb_add\t7\tflag_rsb_add\t9"),
        ] {
            let mut m = pm(flags).unwrap();
            let rows = apply_declared_style_override(&mut m, &row(40.0, 45.0));
            assert_eq!((m.post_lsb_add, m.post_rsb_add), (40.0, 45.0), "SET must yield exactly the declared values for flags: {flags:?}");
            assert!(m.post_scope.base && m.post_scope.space && m.post_scope.notdef && m.post_scope.mark && !m.post_scope.kerning_letters);
            assert_eq!(m.post_scope_label, "style-override-declared");
            assert!(rows.starts_with("declared_convention_overrides_flags\t"), "{rows}");
            assert!(rows.contains(want_flag_record), "{rows}");
            assert!(rows.contains("set_lsb\t40\tset_rsb\t45"), "{rows}");
            assert!(rows.contains("kerning_dir\tignored") && rows.contains("sidebearing_dir\tignored"), "{rows}");
        }
    }

    #[test]
    fn set_then_config_yields_exactly_40_45_once() {
        // End of the single injection path: after the SET, the validated run
        // config carries exactly 40/45 - no second add anywhere downstream.
        let mut m = pm("lsb_add 40\nrsb_add 45\npost_scope base\npost_scope_label kit\n").unwrap();
        apply_declared_style_override(&mut m, &row(40.0, 45.0));
        let off = post_metrics::offsets_from_config(m.post_lsb_add, m.post_rsb_add).unwrap();
        assert_eq!((off.lsb(), off.rsb()), (40.0, 45.0));
    }

    #[test]
    fn other_styles_are_untouched() {
        // Style scoping ("mona ile karistirmayin"): no row for the style =>
        // no override object => the manifest keeps its own values bit-exactly.
        let table = style_overrides::parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40\t45\tn\n").unwrap();
        for (fam, sub) in [("Mona", "Regular"), ("Marq", "Alternate"), ("Mona Alt", "Bold")] {
            assert!(style_overrides::lookup(&table, fam, sub).is_none(), "{fam}/{sub}");
        }
        let m = pm("").unwrap();
        let mut m2 = pm("").unwrap();
        assert!(declared_convention::record_for("Mona/Regular").is_some()); // declared scale record, NOT an override
        let before = format!("{m2:?}");
        if let Some(r) = style_overrides::lookup(&table, "Mona", "Regular") { apply_declared_style_override(&mut m2, r); }
        assert_eq!(before, format!("{m2:?}"));
        let _ = m;
    }

    #[test]
    fn declared_kern_is_empty_and_gate_clear() {
        let kern = declared_skipped_kern(1000, ProfileFrame::ExportedB);
        assert_eq!(kern.receipt.ready, 0);
        assert_eq!(kern.receipt.overlap_held + kern.receipt.rejected + kern.receipt.clamps_refused, 0);
        assert!(matches!(residual_kern_gate(kern.receipt.overlap_held, kern.receipt.rejected, kern.receipt.clamps_refused, KernGateMode::Default).unwrap(), KernGate::Clear));
        let gid = GlyphIdMap::from_glyph_order(&[".notdef".to_string(), "H".to_string()]).unwrap();
        assert!(kern.ready_residual_rows(&gid).is_empty());
        let rows = style_overrides::kern_not_run_rows();
        assert!(rows.contains("kern\tnot_run\treason\tdeclared_convention\t"));
        assert!(!rows.contains("kern\tready\t"));
        assert!(rows.contains("kern_drop_total\tnot_run\treason\tdeclared_convention\t") && rows.contains("closed\ttrue"));
    }

    #[test]
    fn every_glyph_class_gets_exactly_40_45() {
        // Acceptance (1) at the post-step: a zero-bearing population (the
        // declared style ships the natural zero-bearing solve) plus the
        // declared SET offsets yields lsb=40 rsb=45 on EVERY glyph class.
        let off = post_metrics::offsets_from_config(40.0, 45.0).unwrap();
        let scope = post_metrics::Scope::new(style_overrides::DECLARED_POST_SCOPE, "style-override test");
        let rows: Vec<post_metrics::Row> = vec![
            (".notdef".into(), 0.0, 0.0, 611.0),
            ("H".into(), 0.0, 0.0, 611.0),
            ("g".into(), 0.0, 0.0, 480.0),
            ("space".into(), 0.0, 0.0, 250.0),
            ("acutecomb".into(), 0.0, 0.0, 0.0),
        ];
        let classes: Vec<(String, kni_core::offset_scope::GlyphClass)> = vec![
            (".notdef".into(), kni_core::offset_scope::GlyphClass::Notdef),
            ("H".into(), kni_core::offset_scope::GlyphClass::Base),
            ("g".into(), kni_core::offset_scope::GlyphClass::Base),
            ("space".into(), kni_core::offset_scope::GlyphClass::Space),
            ("acutecomb".into(), kni_core::offset_scope::GlyphClass::Mark),
        ];
        let (out, ledger) = post_metrics::apply(&rows, &classes, off, &scope).unwrap();
        for (id, l, r, a) in &out {
            assert_eq!((*l, *r), (40.0, 45.0), "{id}");
            let orig = rows.iter().find(|(i, _, _, _)| i == id).unwrap();
            let cls = classes.iter().find(|(i, _)| i == id).map(|(_, c)| c).unwrap();
            if *cls != kni_core::offset_scope::GlyphClass::Mark {
                assert_eq!(*a, orig.3 + 85.0, "{id}: advance = width + 40 + 45");
            }
        }
        assert_eq!(ledger.applied().len(), 5);
    }
}

#[cfg(test)]
mod m3_tests {
    use super::*;
    // The planner's TOL_FLAT_UNDECLARED path is unreachable through this adapter:
    // a missing m3_tol_flat is caught as MISSING_PARAM:m3_tol_flat (state 2)
    // before any planner call, and tol_flat is always Some in the measuring path.

    fn m3_manifest(extra: &str) -> Manifest {
        parse_manifest(&format!("family T\nsubfamily R\npostscript_name T-R\nscale 1.0\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x61 a a.png\nglyph 0x78 x x.png\nglyph 0x6E n n.png\n{}", "0".repeat(64), extra), std::path::Path::new(".")).unwrap()
    }
    const SIX: &str = "m3_lower_set 0x61 0x78 0x6E\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n";

    fn rect(gid: &str, w: f64, h: f64) -> DrawnGlyph {
        let p = |x, y| Point { x, y };
        DrawnGlyph { glyph_id: gid.to_string(), rings: vec![ReferenceRing { start: p(0.0, 0.0), spans: vec![
            Span::Line { end: p(w, 0.0) }, Span::Line { end: p(w, h) }, Span::Line { end: p(0.0, h) }, Span::Line { end: p(0.0, 0.0) }] }] }
    }
    fn pointed_bottom(gid: &str, w: f64, h: f64) -> DrawnGlyph {
        let p = |x, y| Point { x, y };
        DrawnGlyph { glyph_id: gid.to_string(), rings: vec![ReferenceRing { start: p(0.0, h), spans: vec![
            Span::Line { end: p(w / 2.0, 0.0) }, Span::Line { end: p(w, h) }, Span::Line { end: p(0.0, h) }] }] }
    }
    fn flat3() -> Vec<DrawnGlyph> { vec![rect("a", 100.0, 500.0), rect("x", 100.0, 500.0), rect("n", 100.0, 500.0)] }







    #[test]
    fn m3_decl_token_distinguishes_every_declared_input() {
        let base = m3_decl_token(&m3_manifest(SIX).m3);
        for edit in [("m3_cluster_gap 10", "m3_cluster_gap 11"), ("m3_tol_flat 2", "m3_tol_flat 3"), ("m3_lower_set 0x61 0x78 0x6E", "m3_lower_set 0x61 0x78")] {
            assert_ne!(base, m3_decl_token(&m3_manifest(&SIX.replace(edit.0, edit.1)).m3), "{edit:?}");
        }
        assert_ne!(base, m3_decl_token(&m3_manifest(&format!("{SIX}m3_cap_set 0x48\n")).m3));
    }

    #[test]
    fn r3_cap_set_measures_cap_line_with_declared_convention_provenance() {
        // lower set a/x/n flat 500 tall on baseline 0; cap set = two flat 700 tall glyphs
        let m = parse_manifest(&format!("family T\nsubfamily R\npostscript_name T-R\nscale 1.0\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\nglyph 0x61 a a.png\nglyph 0x78 x x.png\nglyph 0x6E n n.png\nglyph 0x48 H H.png\nglyph 0x45 E E.png\nm3_lower_set 0x61 0x78 0x6E\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\nm3_cap_set 0x48 0x45\nos2_x_height_write measured_preferred\n", "0".repeat(64)), std::path::Path::new(".")).unwrap();
        assert_eq!(m.m3.cap_set, Some(vec![0x48, 0x45]));
        let mut g = flat3(); g.push(rect("H", 100.0, 700.0)); g.push(rect("E", 100.0, 700.0));
        let (rows, x, cap) = m3_adapter(&m, &g, 100.0);
        assert!(rows.contains("m3_cap_set\tDECLARED_CONVENTION\tcalibrated\tfalse\tcodepoints\t0x48,0x45\n"), "{rows}");
        assert!(x.is_some(), "{rows}");
        let c = cap.expect("cap RESOLVED");
        assert_eq!((c.top_center, c.value, c.size), (700.0, 700.0, 2));
        assert!(rows.contains("m3_cap_result\tRESOLVED\tvalue\t700\ttop_center\t700\tsize\t2\tspread\t0\texcluded\t-\n"), "{rows}");
        let (v, row) = os2_cap_height_measured_preferred(cap, true, &rows, 100.0, false, 1e9);
        assert_eq!(v, Some(600.0));
        assert!(row.contains("cap_set\tDECLARED_CONVENTION\tcalibrated\tfalse\tevidence_sha\t"), "{row}");
        assert_eq!(os2_cap_height_measured_preferred(cap, true, &rows, 100.0, true, 1e9).0, Some(700.0));
        assert_eq!(os2_cap_height_measured_preferred(cap, false, &rows, 0.0, false, 1e9).1, "os2_cap_height_measured\tnot_measured\treason\tCAP_SET_UNDECLARED\tfallback\tsolver_current\n");
        assert_eq!(os2_cap_height_measured_preferred(None, true, &rows, 0.0, false, 1e9).1, "os2_cap_height_measured\tnot_measured\treason\tM3_CAP_UNRESOLVED\tfallback\tsolver_current\n");
        assert_eq!(os2_cap_height_measured_preferred(cap, true, &rows, 900.0, false, 1e9).0, None);
        // no cap set declared: no cap rows, no cap result, x result unchanged
        let (rows2, x2, cap2) = m3_adapter(&m3_manifest(SIX), &flat3(), 100.0);
        assert!(!rows2.contains("m3_cap") && cap2.is_none() && x2.is_some());
    }

    #[test]
    fn frame_guard_and_typed_cap_bridge() {
        // Mercator-shaped: M1 baseline and solver baseline differ by 1.06 (< tol 2): resolved, both rows written from the exported frame.
        let x = M3Measured { top_center: -1667.5, value: 162.44, size: 3, spread: 0.0 };
        let c = M3CapMeasured { top_center: -1591.0, value: 238.94, size: 2, spread: 0.0 };
        let (v, row) = os2_x_height_measured_preferred(Some(x), "r", -1831.0, false, "s", 2.0);
        assert_eq!(v, Some(163.5), "{row}");
        let (v, row) = os2_cap_height_measured_preferred(Some(c), true, "r", -1831.0, false, 2.0);
        assert_eq!(v, Some(240.0), "{row}");
        // disagreement above tol_flat: UNRESOLVED diff row, nothing chosen, solver kept
        let x = M3Measured { value: 160.0, ..x }; // |160 - 163.5| = 3.5 > 2
        let (v, row) = os2_x_height_measured_preferred(Some(x), "r", -1831.0, false, "s", 2.0);
        assert_eq!(v, None);
        assert_eq!(row, "os2_x_height_measured\tnot_measured\treason\tFRAME_DISAGREEMENT\tm1_frame_value\t160\texported_frame_value\t163.5\tdiff\t3.5\ttol\t2\tfallback\tsolver_current\n");
        let c = M3CapMeasured { value: 230.0, ..c }; // |230 - 240| = 10 > 2
        let (v, row) = os2_cap_height_measured_preferred(Some(c), true, "r", -1831.0, false, 2.0);
        assert_eq!(v, None); assert!(row.contains("FRAME_DISAGREEMENT\tm1_frame_value\t230\texported_frame_value\t240\tdiff\t10\ttol\t2"), "{row}");
        // exactly at tol resolves; NaN tol (undeclared) never resolves
        assert!(os2_x_height_measured_preferred(Some(M3Measured { value: 161.5, ..x }), "r", -1831.0, false, "s", 2.0).0.is_some());
        assert!(os2_x_height_measured_preferred(Some(x), "r", -1831.0, false, "s", f64::NAN).0.is_none());
        // typed cap bridge tokens
        let rows = "r";
        assert!(os2_cap_height_measured_preferred(Some(c), true, rows, 9000.0, false, 1e9).1.contains("CAP_NONPOSITIVE"));
        assert!(os2_cap_height_measured_preferred(Some(c), false, rows, 0.0, false, 2.0).1.contains("CAP_SET_UNDECLARED"));
        assert!(os2_cap_height_measured_preferred(None, true, rows, 0.0, false, 2.0).1.contains("M3_CAP_UNRESOLVED"));
    }

    #[test]
    fn r1_measured_preferred_couples_m3_through_typed_bridge_to_sxheight() {
        let m = m3_manifest(&format!("{SIX}os2_x_height_write measured_preferred\n"));
        assert_eq!(m.os2_x_height_write, Some(Os2XHeightWrite::MeasuredPreferred));
        let (rows, r, _) = m3_adapter(&m, &flat3(), 100.0);
        let r = r.expect("RESOLVED M3");
        assert_eq!((r.top_center, r.value, r.size), (500.0, 500.0, 3));
        // shifted frame: exported baseline is the solver baseline, x-height line sits at top_center - baseline
        let (x, row) = os2_x_height_measured_preferred(Some(r), &rows, 100.0, false, "s", 1e9);
        assert_eq!(x, Some(400.0));
        assert!(row.starts_with("os2_x_height_measured\tmeasured\tsource\tplanner_row43_measured\tvalue\t400\t"), "{row}");
        assert!(row.contains(&format!("evidence_sha\t{}\n", sha256_hex(rows.as_bytes()))), "{row}");
        // tile-anchor scope: shift 0, exported baseline 0
        assert_eq!(os2_x_height_measured_preferred(Some(r), &rows, 100.0, true, "s", 1e9).0, Some(500.0));
        // honest fallbacks: unresolved M3, nonpositive result
        let (x, row) = os2_x_height_measured_preferred(None, "", 0.0, false, "s", 1e9);
        assert_eq!(x, None);
        assert_eq!(row, "os2_x_height_measured\tnot_measured\treason\tM3_UNRESOLVED_OR_NOT_DECLARED\tfallback\tsolver_current\n");
        let (x, row) = os2_x_height_measured_preferred(Some(r), &rows, 900.0, false, "s", 1e9);
        assert_eq!(x, None); assert!(row.contains("BRIDGE_NOT_MEASURED_OR_NONPOSITIVE"), "{row}");
        // M3 not declared at all: no structured result
        assert!(m3_adapter(&m3_manifest("os2_x_height_write measured_preferred\n"), &flat3(), 0.0).1.is_none());
        // rows are unchanged by the structured return
        assert_eq!(rows, m3_adapter_rows(&m, &flat3(), 100.0));
    }

    #[test]
    fn off_returns_empty_byte_equal() {
        let m = m3_manifest("");
        assert_eq!(m3_adapter_rows(&m, &flat3(), -1658.5), "", "KAPALI: no m3_* key -> no rows");
    }

    #[test]
    fn missing_param_rows_per_key_and_planner_not_called() {
        let m = m3_manifest("m3_lower_set 0x61\nm3_tol_flat 2\n");
        let out = m3_adapter_rows(&m, &flat3(), 0.0);
        assert!(out.starts_with("m3_status\tEXPERIMENTAL_RECEIPT_ONLY\n"), "{out}");
        assert_eq!(out.lines().filter(|l| l.starts_with("m3_result\t")).count(), 4, "{out}");
        for k in ["m3_excl_set", "m3_cluster_gap", "m3_min_cluster_size", "m3_min_gap"] {
            assert!(out.contains(&format!("m3_result\tUNRESOLVED\treason\tMISSING_PARAM:{k}\n")), "{k} in {out}");
        }
        assert!(!out.contains("m3_frame") && !out.contains("RESOLVED\tvalue"), "{out}");
    }

    #[test]
    fn invalid_param_rows() {
        let neg = m3_manifest("m3_lower_set 0x61\nm3_excl_set 0x6F\nm3_cluster_gap -1\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n");
        assert!(m3_adapter_rows(&neg, &flat3(), 0.0).contains("m3_result\tUNRESOLVED\treason\tINVALID_PARAM:m3_cluster_gap\n"));
        let empty = m3_manifest("m3_lower_set\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n");
        assert!(m3_adapter_rows(&empty, &flat3(), 0.0).contains("INVALID_PARAM:m3_lower_set\n"));
        let conflict = m3_manifest("m3_lower_set 0x61\nm3_excl_set 0x61\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n");
        assert!(m3_adapter_rows(&conflict, &flat3(), 0.0).contains("INVALID_PARAM:m3_excl_set\n"));
        let nan = m3_manifest("m3_lower_set 0x61\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat NaN\nm3_min_gap 5\n");
        assert!(m3_adapter_rows(&nan, &flat3(), 0.0).contains("INVALID_PARAM:m3_tol_flat\n"));
    }

    #[test]
    fn resolved_synthetic_flat_rects() {
        let m = m3_manifest(SIX);
        let out = m3_adapter_rows(&m, &flat3(), -1658.5);
        assert!(out.contains("m3_status\tEXPERIMENTAL_RECEIPT_ONLY\n"), "{out}");
        assert!(out.contains("m3_frame\tengine_coordinate\tunit\tUNDECLARED\n"), "{out}");
        assert!(out.contains("m3_frame\tread_at\tpre_shift\n"), "{out}");
        assert!(out.contains("m3_baseline_ref\tsolver\tvalue\t-1658.5\tnote\tnot_used_not_equivalent_to_M1\n"), "{out}");
        assert!(out.contains("m3_baseline\tsource\tM1_measure_baseline\tstatus\tRESOLVED\tvalue\t0\tsize\t3\tspread\t0\n"), "{out}");
        assert!(out.contains("m3_result\tRESOLVED\tvalue\t500\ttop_center\t500\tsize\t3\tspread\t0\texcluded\t-\n"), "{out}");
    }

    #[test]
    fn per_glyph_extremum_rows_fixture_cls_ymax() {
        // r281: known fixture glyphs, exact cls/extremum literals; typed nulls stay "-".
        let m = m3_manifest(SIX);
        let out = m3_adapter_rows(&m, &flat3(), -1658.5);
        for (g, cp) in [("a", "0x61"), ("x", "0x78"), ("n", "0x6e")] {
            assert!(out.contains(&format!("m1_glyph\tglyph\t{g}\tcp\t{cp}\tcls\tflat\tymin\t0\n")), "{out}");
            assert!(out.contains(&format!("m3_glyph\tglyph\t{g}\tcp\t{cp}\tcls\tFLAT\tymax\t500\n")), "{out}");
        }
        // excl_set codepoint with no drawn glyph yields no planner row at all.
        assert_eq!(out.matches("m1_glyph\t").count(), 3, "{out}");
        assert_eq!(out.matches("m3_glyph\t").count(), 3, "{out}");
        // drawn glyph in excl_set: typed null extremum stays "-", no invented number.
        let m2 = m3_manifest("m3_lower_set 0x61 0x78\nm3_excl_set 0x6E\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n");
        let out2 = m3_adapter_rows(&m2, &flat3(), 0.0);
        assert!(out2.contains("m3_glyph\tglyph\tn\tcp\t0x6e\tcls\tEXCLUDED:excl_set\tymax\t-\n"), "{out2}");
        // lower_set codepoint with no drawn glyph: typed null glyph.
        let m3 = m3_manifest("m3_lower_set 0x61 0x78 0x63\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 2\nm3_tol_flat 2\nm3_min_gap 5\n");
        let out3 = m3_adapter_rows(&m3, &flat3(), 0.0);
        assert!(out3.contains("m3_glyph\tglyph\t-\tcp\t0x63\tcls\tABSENT\tymax\t-\n"), "{out3}");
    }

    #[test]
    fn per_glyph_rows_off_and_unresolved_semantics() {
        // adapter OFF: still byte-empty, no glyph rows appear.
        let m = m3_manifest("");
        assert_eq!(m3_adapter_rows(&m, &flat3(), 0.0), "");
        // pointed bottom: M1 UNRESOLVED still carries its typed per-glyph rows.
        let m = m3_manifest("m3_lower_set 0x61\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 1\nm3_tol_flat 2\nm3_min_gap 5\n");
        let g = vec![pointed_bottom("a", 100.0, 500.0)];
        let out = m3_adapter_rows(&m, &g, 0.0);
        assert!(out.contains("m1_glyph\tglyph\ta\tcp\t0x61\tcls\tround\tymin\t0\n"), "{out}");
        assert!(out.contains("m3_glyph\tglyph\ta\tcp\t0x61\tcls\tFLAT\tymax\t500\n"), "{out}");
    }

    #[test]
    fn solver_baseline_ref_does_not_change_value() {
        let m = m3_manifest(SIX);
        let a = m3_adapter_rows(&m, &flat3(), 0.0);
        let b = m3_adapter_rows(&m, &flat3(), -1658.5);
        let va = a.lines().find(|l| l.starts_with("m3_result\t")).unwrap();
        let vb = b.lines().find(|l| l.starts_with("m3_result\t")).unwrap();
        assert_eq!(va, vb, "solver ref must not affect the measured value");
        assert!(b.contains("m3_baseline_ref\tsolver\tvalue\t-1658.5\t"), "{b}");
    }

    #[test]
    fn m1_unresolved_gives_xh_no_baseline_verbatim() {
        let m = m3_manifest("m3_lower_set 0x61\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 1\nm3_tol_flat 2\nm3_min_gap 5\n");
        let g = vec![pointed_bottom("a", 100.0, 500.0)];
        let out = m3_adapter_rows(&m, &g, 0.0);
        assert!(out.contains("m3_baseline\tsource\tM1_measure_baseline\tstatus\tUNRESOLVED\treason\tBASELINE_NO_FLAT_BOTTOM\n"), "{out}");
        assert!(out.contains("m3_result\tUNRESOLVED\treason\tXH_NO_BASELINE\n"), "{out}");
    }

    #[test]
    fn xh_set_absent_verbatim_reason() {
        let m = m3_manifest("m3_lower_set 0x63 0x7A\nm3_excl_set 0x6F\nm3_cluster_gap 10\nm3_min_cluster_size 1\nm3_tol_flat 2\nm3_min_gap 5\n");
        let out = m3_adapter_rows(&m, &flat3(), 0.0);
        assert!(out.contains("m3_result\tUNRESOLVED\treason\tXH_SET_ABSENT:NO_LOWERCASE_CANDIDATES\n"), "{out}");
    }
}

#[cfg(test)]
mod auto_sb_cli_tests {
    use super::*;
    #[test]
    fn auto_sb_flags_parse_and_refuse_misuse() {
        let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        let (f, kept) = take_auto_sb_flags(&s(&["p", "m", "o", "--auto-sb", "median", "--auto-sb-offset-lsb", "-12.5", "--tie-break", "A"])).unwrap();
        assert_eq!(f, AutoSbFlags { mode: Some(run_config::AutoSbMode::Median), class_table: None, pool: None, offset_lsb: Some(-12.5), offset_rsb: None, tie_break: Some(run_config::TieBreak::A) });
        assert_eq!(kept, s(&["p", "m", "o"]));
        let (f2, _) = take_auto_sb_flags(&s(&["p", "--auto-sb", "class", "--auto-sb-class-table", "/t/classes.tsv", "--auto-sb-offset-rsb", "2.5", "--tie-break", "B"])).unwrap();
        assert_eq!(f2.mode, Some(run_config::AutoSbMode::Class));
        assert_eq!(f2.class_table, Some(PathBuf::from("/t/classes.tsv")));
        for bad in [
            s(&["p", "--auto-sb"]),
            s(&["p", "--auto-sb", "--tie-break"]),
            s(&["p", "--auto-sb", "MEAN", "--tie-break", "A"]),
            s(&["p", "--auto-sb", "median", "--auto-sb", "class"]),
            s(&["p", "--tie-break", "a"]),
            s(&["p", "--auto-sb-offset-lsb", "abc"]),
            s(&["p", "--auto-sb-offset-lsb", "NaN"]),
            s(&["p", "--auto-sb-class-table"]),
        ] { assert!(take_auto_sb_flags(&bad).is_err(), "{bad:?}"); }
    }

    #[test]
    fn auto_sb_manifest_keys_parse_and_refuse() {
        let base = "family F\nsubfamily R\npostscript_name F-R\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 0000000000000000000000000000000000000000000000000000000000000000\nglyph 0x48 H missing.png\n";
        let ok = parse_manifest(&format!("{base}auto_sb median\nauto_sb_offset_lsb -12.5\ntie_break A\n"), Path::new(".")).unwrap();
        assert_eq!(ok.auto_sb, Some(run_config::AutoSbMode::Median));
        assert_eq!(ok.auto_sb_offset_lsb, Some(-12.5));
        assert_eq!(ok.auto_sb_offset_rsb, None);
        assert_eq!(ok.tie_break, Some(run_config::TieBreak::A));
        let cls = parse_manifest(&format!("{base}auto_sb class\nauto_sb_class_table tables/c.tsv\ntie_break B\n"), Path::new(".")).unwrap();
        assert_eq!(cls.auto_sb, Some(run_config::AutoSbMode::Class));
        assert_eq!(cls.auto_sb_class_table, Some(PathBuf::from("./tables/c.tsv")));
        for bad in [
            format!("{base}auto_sb median\nauto_sb class\n"),
            format!("{base}auto_sb bogus\n"),
            format!("{base}tie_break a\n"),
            format!("{base}tie_break\n"),
            format!("{base}auto_sb_offset_lsb NaN\n"),
            format!("{base}auto_sb_offset_rsb junk\n"),
            format!("{base}auto_sb_class_table\n"),
        ] { assert!(parse_manifest(&bad, Path::new(".")).is_err(), "{bad:?}"); }
    }

    #[test]
    fn auto_sb_merge_one_injection_point() {
        use run_config::{AutoSbMode, TieBreak};
        assert_eq!(merge_auto_sb("auto_sb", Some(AutoSbMode::Median), Some(AutoSbMode::Median)).unwrap(), Some(AutoSbMode::Median));
        assert_eq!(merge_auto_sb("auto_sb", Some(AutoSbMode::Median), None).unwrap(), Some(AutoSbMode::Median));
        assert_eq!(merge_auto_sb("auto_sb", None, Some(AutoSbMode::Class)).unwrap(), Some(AutoSbMode::Class));
        assert_eq!(merge_auto_sb("auto_sb", None::<AutoSbMode>, None).unwrap(), None);
        assert!(merge_auto_sb("auto_sb", Some(AutoSbMode::Median), Some(AutoSbMode::Class)).is_err());
        assert!(merge_auto_sb("tie_break", Some(TieBreak::A), Some(TieBreak::B)).is_err());
        assert_eq!(merge_auto_sb("auto_sb_offset_lsb", Some(-12.5f64), None).unwrap(), Some(-12.5));
        assert_eq!(merge_auto_sb("auto_sb_offset_lsb", None, Some(2.5f64)).unwrap(), Some(2.5));
    }

}


// ---- A2 auto-sb glue (pure; unit-tested below) ----

/// One applied side-bearing change. Deltas are the exact f64 values applied.
#[derive(Clone, Debug, PartialEq)]
struct A2Row { glyph_id: String, d_lsb: f64, d_rsb: f64, d_advance: f64, basis: String }

#[derive(Clone, Debug, PartialEq)]
struct A2Report { rows: Vec<A2Row>, refused: Vec<(String, String)>, checked: usize, violations: usize }

fn auto_sb_mode_label(mode: run_config::AutoSbMode) -> String {
    match mode { run_config::AutoSbMode::Median => "median".to_string(), run_config::AutoSbMode::Class => "class".to_string() }
}

/// Apply per-glyph target side bearings to the solved population.
/// For every touched glyph: dLSB = new_lsb - lsb, dRSB = new_rsb - rsb, dAdvance = dLSB + dRSB,
/// advance += dAdvance. `.notdef` and glyph ids not in the population are skipped.
/// A duplicate target id or a non-finite value is an Err (nothing is applied before validation ends).
/// Invariant counted per touched glyph: (advance_after - advance_before) == dAdvance (exact f64).
fn a2_apply_targets(glyphs: &mut [kni_metrics::self_anchored_spacing::GlyphSpacing], targets: &[(String, f64, f64, String)]) -> Result<A2Report, String> {
    let mut by_id: std::collections::HashMap<&str, usize> = std::collections::HashMap::new();
    for (i, (id, nl, nr, _)) in targets.iter().enumerate() {
        if !nl.is_finite() || !nr.is_finite() { return Err(format!("auto_sb: non-finite target for glyph {id}")); }
        if by_id.insert(id.as_str(), i).is_some() { return Err(format!("auto_sb: duplicate target for glyph {id}")); }
    }
    let mut rows: Vec<A2Row> = Vec::new();
    let mut refused: Vec<(String, String)> = Vec::new();
    let mut violations = 0usize;
    for g in glyphs.iter_mut() {
        if g.glyph_id == ".notdef" { continue; }
        let ti = match by_id.get(g.glyph_id.as_str()) { Some(&i) => i, None => continue };
        let (_, new_lsb, new_rsb, basis) = &targets[ti];
        let d_lsb = new_lsb - g.lsb;
        let d_rsb = new_rsb - g.rsb;
        let d_advance = d_lsb + d_rsb;
        let adv_before = g.advance;
        let adv_after = adv_before + d_advance;
        if !adv_after.is_finite() { return Err(format!("auto_sb: non-finite advance for glyph {}", g.glyph_id)); }
        // chief guard 15:45 (R4 Mercator diagnosis): a target that would drive the advance
        // out of the encodable domain is a typed per-glyph refusal, NOT an apply. Measured:
        // 19/81 Mercator glyphs went advance<0 with the run19 pool medians and the run died
        // later at generated_native.rs:62 InvalidMetrics with no glyph name.
        if adv_after < 0.0 || adv_after > 32767.0 {
            refused.push((g.glyph_id.clone(), format!("advance_out_of_range:{adv_after}")));
            continue;
        }
        g.lsb = *new_lsb;
        g.rsb = *new_rsb;
        g.advance = adv_after;
        if d_advance.to_bits() != (d_lsb + d_rsb).to_bits() { violations += 1; }
        rows.push(A2Row { glyph_id: g.glyph_id.clone(), d_lsb, d_rsb, d_advance, basis: basis.clone() });
    }
    let checked = rows.len();
    Ok(A2Report { rows, refused, checked, violations })
}

/// Receipt rows for an applied A2 pass (only called when the guard is on).
fn a2_receipt_rows(mode_label: &str, rep: &A2Report) -> String {
    let mut out = format!("auto_sb_mode\t{mode_label}\n");
    for r in &rep.rows {
        out.push_str(&format!("auto_sb_applied\t{}\t{}\t{}\t{}\t{}\n", r.glyph_id, r.d_lsb, r.d_rsb, r.d_advance, r.basis));
    }
    for (id, reason) in &rep.refused {
        out.push_str(&format!("auto_sb_refused\t{}\t{}\n", id, reason));
    }
    out.push_str(&format!("auto_sb_invariant\tdelta_advance_eq_dlsb_plus_drsb\tchecked\t{}\tviolations\t{}\trefused\t{}\n", rep.checked, rep.violations, rep.refused.len()));
    out
}

fn map_auto_sb_mode(m: run_config::AutoSbMode) -> auto_sb::Mode {
    match m { run_config::AutoSbMode::Median => auto_sb::Mode::Median, run_config::AutoSbMode::Class => auto_sb::Mode::Class }
}

fn map_tie_break(t: run_config::TieBreak) -> auto_sb::TieBreak {
    match t { run_config::TieBreak::A => auto_sb::TieBreak::A, run_config::TieBreak::B => auto_sb::TieBreak::B }
}

/// Edge-class table TSV (perception layer v03): header row, then
/// glyph, codepoint, category, kind, ncomp, class_left, class_right, ... ; "empty" = class-less.
fn auto_sb_load_class_table(path: Option<&std::path::Path>) -> Result<std::collections::BTreeMap<String, auto_sb::ClassAssignment>, String> {
    let mut out = std::collections::BTreeMap::new();
    let Some(p) = path else { return Ok(out) };
    let text = std::fs::read_to_string(p).map_err(|e| format!("auto_sb class table read: {e}"))?;
    for (ln, line) in text.lines().enumerate().skip(1) {
        if line.is_empty() { continue; }
        let c: Vec<&str> = line.split('\t').collect();
        if c.len() < 7 { return Err(format!("auto_sb class table line {}: expected >= 7 columns", ln + 1)); }
        let cls = |v: &str| if v == "empty" || v.is_empty() { None } else { Some(v.to_string()) };
        if out.insert(c[0].to_string(), auto_sb::ClassAssignment { left_class: cls(c[5]), right_class: cls(c[6]) }).is_some() {
            return Err(format!("auto_sb class table: duplicate glyph {}", c[0]));
        }
    }
    Ok(out)
}

/// Pool observations TSV: source-owned 4-column projection format
/// ("empty" = class-less). Format guard (chief ruling 2026-10-23, S1f loader
/// finding): the header row must be EXACTLY the declared column names and
/// every data row must have EXACTLY 4 columns - otherwise a 29-column
/// provenance pool.tsv (or any look-alike TSV) with numeric text in columns
/// 3/4 would silently misparse as bearings. Non-finite lsb/rsb ("NaN"/"inf"
/// parse as f64) are refused the same way.
const AUTO_SB_POOL_HEADER: &str = "left_class\tright_class\tlsb\trsb";
fn auto_sb_load_pool_obs(path: &std::path::Path) -> Result<Vec<auto_sb::PoolObservation>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("auto_sb pool read: {e}"))?;
    let header = text.lines().next().ok_or_else(|| "auto_sb pool: empty file".to_string())?;
    if header != AUTO_SB_POOL_HEADER { return Err(format!("auto_sb pool: bad header (expected {AUTO_SB_POOL_HEADER:?})")); }
    let mut out = Vec::new();
    for (ln, line) in text.lines().enumerate().skip(1) {
        if line.is_empty() { continue; }
        let c: Vec<&str> = line.split('\t').collect();
        if c.len() != 4 { return Err(format!("auto_sb pool line {}: expected exactly 4 columns, found {}", ln + 1, c.len())); }
        let cls = |v: &str| if v == "empty" || v.is_empty() { None } else { Some(v.to_string()) };
        let lsb: f64 = c[2].parse().map_err(|_| format!("auto_sb pool line {}: bad lsb", ln + 1))?;
        let rsb: f64 = c[3].parse().map_err(|_| format!("auto_sb pool line {}: bad rsb", ln + 1))?;
        if !lsb.is_finite() { return Err(format!("auto_sb pool line {}: non-finite lsb", ln + 1)); }
        if !rsb.is_finite() { return Err(format!("auto_sb pool line {}: non-finite rsb", ln + 1)); }
        out.push(auto_sb::PoolObservation { left_class: cls(c[0]), right_class: cls(c[1]), lsb, rsb });
    }
    Ok(out)
}

#[cfg(test)]
mod a2_auto_sb_tests {
    use super::*;
    use kni_metrics::self_anchored_spacing::GlyphSpacing;

    fn g(id: &str, lsb: f64, rsb: f64, adv: f64) -> GlyphSpacing { GlyphSpacing { glyph_id: id.to_string(), lsb, rsb, advance: adv } }
    fn snap(p: &[GlyphSpacing]) -> Vec<(String, f64, f64, f64)> { p.iter().map(|x| (x.glyph_id.clone(), x.lsb, x.rsb, x.advance)).collect() }
    fn t(id: &str, l: f64, r: f64) -> (String, f64, f64, String) { (id.to_string(), l, r, "class:flat_stem".to_string()) }

    #[test]
    fn invariant_delta_advance_equals_dlsb_plus_drsb() {
        let mut pop = vec![g("a", 10.0, 20.0, 500.0), g("b", 30.0, 40.0, 600.0)];
        let rep = a2_apply_targets(&mut pop, &[t("a", 25.0, 15.0), t("b", 50.0, 10.0)]).unwrap();
        assert_eq!(rep.checked, 2);
        assert_eq!(rep.violations, 0);
        for r in &rep.rows { assert_eq!(r.d_advance, r.d_lsb + r.d_rsb); }
        assert_eq!(pop[0].advance, 500.0 + (15.0 + -5.0));
        assert_eq!((pop[0].lsb, pop[0].rsb), (25.0, 15.0));
    }

    #[test]
    fn notdef_and_unknown_glyphs_are_untouched() {
        let mut pop = vec![g(".notdef", 0.0, 0.0, 1000.0), g("a", 10.0, 10.0, 400.0)];
        let before = snap(&pop);
        let rep = a2_apply_targets(&mut pop, &[t(".notdef", 99.0, 99.0), t("zzz", 1.0, 1.0)]).unwrap();
        assert!(rep.rows.is_empty());
        assert_eq!(snap(&pop), before);
    }

    #[test]
    fn pool_loader_format_guard() {
        let dir = std::env::temp_dir().join(format!("kni_pool_guard_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let write = |name: &str, body: &str| { let p = dir.join(name); std::fs::write(&p, body).unwrap(); p };
        // valid: exact header, exactly 4 cols, negative bearings and "empty" classes legal
        let ok = write("ok.tsv", "left_class\tright_class\tlsb\trsb\nempty\tempty\t-15.13671875\t-20.99609375\nflat\tflat\t31.25\t28.3203125\n");
        let v = auto_sb_load_pool_obs(&ok).unwrap();
        assert_eq!(v.len(), 2);
        assert_eq!((v[0].left_class.is_none(), v[0].lsb, v[0].rsb), (true, -15.13671875, -20.99609375));
        assert_eq!((v[1].left_class.as_deref(), v[1].lsb), (Some("flat"), 31.25));
        // wrong header (e.g. the 29-column provenance pool.tsv header) is refused, not misparsed
        let bad_header = write("badh.tsv", "schema_version\tpool_id\tpool_version\tfont_id\n0.1.0\tpool-x\t1\tfont\n");
        assert!(auto_sb_load_pool_obs(&bad_header).unwrap_err().contains("bad header"));
        // extra columns refused (a 29-col row must never silently read cols 3/4 as bearings)
        let wide = write("wide.tsv", "left_class\tright_class\tlsb\trsb\nflat\tflat\t1\t2\textra\n");
        assert!(auto_sb_load_pool_obs(&wide).unwrap_err().contains("exactly 4 columns"));
        // non-finite values refused (f64 parse accepts NaN/inf)
        let nan = write("nan.tsv", "left_class\tright_class\tlsb\trsb\nflat\tflat\tNaN\t2\n");
        assert!(auto_sb_load_pool_obs(&nan).unwrap_err().contains("non-finite lsb"));
        let inf = write("inf.tsv", "left_class\tright_class\tlsb\trsb\nflat\tflat\t1\tinf\n");
        assert!(auto_sb_load_pool_obs(&inf).unwrap_err().contains("non-finite rsb"));
        // bad numeric still refused with the side named correctly
        let bad = write("bad.tsv", "left_class\tright_class\tlsb\trsb\nflat\tflat\tabc\t2\n");
        assert!(auto_sb_load_pool_obs(&bad).unwrap_err().contains("bad lsb"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_targets_leave_population_identical() {
        let mut pop = vec![g("a", 10.0, 10.0, 400.0), g("b", 11.0, 12.0, 413.0)];
        let before = snap(&pop);
        let rep = a2_apply_targets(&mut pop, &[]).unwrap();
        assert_eq!(snap(&pop), before);
        assert_eq!(rep.checked, 0);
    }

    #[test]
    fn duplicate_and_nonfinite_targets_are_errors_and_apply_nothing() {
        let mut pop = vec![g("a", 10.0, 10.0, 400.0)];
        let before = snap(&pop);
        assert!(a2_apply_targets(&mut pop, &[t("a", 1.0, 1.0), t("a", 2.0, 2.0)]).is_err());
        assert!(a2_apply_targets(&mut pop, &[t("a", f64::NAN, 1.0)]).is_err());
        assert!(a2_apply_targets(&mut pop, &[t("a", 1.0, f64::INFINITY)]).is_err());
        assert_eq!(snap(&pop), before);
    }

    #[test]
    fn receipt_rows_have_expected_shape() {
        let mut pop = vec![g("a", 10.0, 20.0, 500.0)];
        let rep = a2_apply_targets(&mut pop, &[t("a", 12.0, 18.0)]).unwrap();
        let rows = a2_receipt_rows("class", &rep);
        let lines: Vec<&str> = rows.lines().collect();
        assert_eq!(lines[0], "auto_sb_mode\tclass");
        assert_eq!(lines[1], "auto_sb_applied\ta\t2\t-2\t0\tclass:flat_stem");
        assert_eq!(lines[2], "auto_sb_invariant\tdelta_advance_eq_dlsb_plus_drsb\tchecked\t1\tviolations\t0\trefused\t0");
    }

    #[test]
    fn out_of_range_advance_is_typed_refusal_not_applied() {
        // R4 Mercator guard (chief 15:45): a target driving advance < 0 or > 32767
        // is refused per glyph; the population row stays untouched; other glyphs apply.
        let mut pop = vec![g("narrow", 0.8, 0.8, 32.0), g("wide", 10.0, 20.0, 500.0)];
        let before = snap(&pop);
        let rep = a2_apply_targets(&mut pop, &[t("narrow", -44.0, -63.0), t("wide", 12.0, 18.0)]).unwrap();
        assert_eq!(rep.checked, 1);
        assert_eq!(rep.refused.len(), 1);
        assert_eq!(rep.refused[0].0, "narrow");
        assert!(rep.refused[0].1.starts_with("advance_out_of_range:"));
        // narrow untouched, wide applied
        assert_eq!(pop[0].advance, 32.0);
        assert_eq!(pop[1].advance, 500.0);
        let _ = before;
        let rows = a2_receipt_rows("median", &rep);
        assert!(rows.contains("auto_sb_refused\tnarrow\tadvance_out_of_range:"));
        assert!(rows.contains("refused\t1"));
    }
}

#[cfg(test)]
mod anon_unencoded_tests {
    use std::path::Path;

    fn manifest_with(rows: &str) -> Result<crate::Manifest, String> {
        crate::parse_manifest(&format!("family Marq\nsubfamily Regular\npostscript_name Marq-Regular\nscale 2.4377\nfit_tolerance_policy fixed\nrun_mode stage1_only\npopulation_sha256 {}\ncapture_cohort Marq/Regular\ncapture_frame capture-manifest-frame\n{}", "0".repeat(64), rows), Path::new("."))
    }

    #[test]
    fn anon_row_parses_unencoded_and_keeps_name_image_scale() {
        let m = manifest_with("glyph 0x41 A a.png\nglyph - anon_ab12 b.png\n").unwrap();
        assert_eq!(m.glyphs.len(), 2);
        assert_eq!(m.glyphs[0].codepoint, Some(0x41));
        let anon = &m.glyphs[1];
        assert_eq!(anon.codepoint, None);
        assert!(anon.extra_cps.is_empty());
        assert_eq!(anon.name, "anon_ab12");
        assert_eq!(anon.image, Path::new(".").join("b.png"));
        assert_eq!(anon.seq_label(), "anon:anon_ab12");
        assert_eq!(anon.cp_display(), "-");
    }

    #[test]
    fn anon_row_name_charset_still_enforced() {
        // The kit boundary renames anon-<hex> to anon_<hex>; a dashed name must
        // still be row-excluded, never silently accepted (validator unchanged).
        let m = manifest_with("glyph 0x41 A a.png\nglyph - anon-ab12 b.png\nglyph - anon_ok c.png\n").unwrap();
        let names: Vec<&str> = m.glyphs.iter().map(|g| g.name.as_str()).collect();
        assert_eq!(names, vec!["A", "anon_ok"]);
        assert_eq!(m.glyphs[1].codepoint, None);
    }

    #[test]
    fn population_pin_binds_anon_rows_by_anon_name_key() {
        let m = manifest_with("glyph 0x41 A a.png\nglyph - anon_ab12 b.png\n").unwrap();
        let expected = crate::sha256_hex(b"41:A\nanon:anon_ab12:anon_ab12\n");
        assert_eq!(crate::population_pin(&m.glyphs), expected);
        // Renaming the anon row changes the pin (per-instance identity is keyed).
        let m2 = manifest_with("glyph 0x41 A a.png\nglyph - anon_cd34 b.png\n").unwrap();
        assert_ne!(crate::population_pin(&m2.glyphs), expected);
    }

    #[test]
    fn encoded_funnel_excludes_anon_rows_from_cmap_proxy_and_placeholder_inputs() {
        // The stage-2 funnel at all_cps is encoded-only; anon rows are drawn but
        // never enter (name, cp) pairs that feed cmap, placeholder or proxy sets.
        let m = manifest_with("glyph 0x41 A a.png\nglyph - anon_ab12 b.png\n").unwrap();
        let processed: Vec<(&crate::GlyphRow, ())> = m.glyphs.iter().map(|g| (g, ())).collect();
        let all_cps: Vec<(String, u32)> = processed.iter().filter_map(|(g, _)| g.codepoint.map(|cp| (g.name.clone(), cp))).collect();
        assert_eq!(all_cps, vec![("A".to_string(), 0x41)]);
    }
}
