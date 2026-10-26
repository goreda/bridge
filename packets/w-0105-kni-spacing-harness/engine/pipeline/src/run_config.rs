//! Per-run configuration (new file: engine/pipeline/src/run_config.rs). Source only; not executed. STATUS: required
//! compatibility with the current manifest behaviour, pending review and compilation.
//! One validated, immutable snapshot: private fields, getters only, built once by `RunConfig::new`. The scale is not a loose
//! number: it comes from a bound `ScaleContext` (single scale variable per run). Math validation (`new`) never touches the
//! filesystem; path checks are separate (`check_output_dir_available`). Defaults reproduce the current manifest defaults in
//! `legacy_defaults_input`, which takes the fit error policy as a REQUIRED argument (no default exists for it).
//! Not settings (no fields): overlap >= 0, protected-node refusal, finiteness, frame binding, integer grid, full-output
//! refusal, cache compatibility. Font family/style/PostScript names are NOT config values: see `derive_names`.
use kni_core::scale_context::{DimParam, Dimension, ScaleContext};
use kni_core::offset_scope::{ScopePolicy, SignedSideBearingOffset};
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, PartialEq)]
#[allow(dead_code)] // config error taxonomy: variants constructed by the config test surface
pub enum ConfigError {
    /// fit error policy was not supplied (no default exists).
    MissingFitErrorPolicy,
    InvalidValue { field: &'static str },
    ZeroCount { field: &'static str },
    EmptyField { field: &'static str },
    /// `--style-id` flag missing, repeated, or without a value.
    StyleIdFlag { reason: &'static str },
    /// residual epsilon: explicit value negative, zero or non-finite.
    InvalidResidualEpsilon,
    PostMetrics { reason: String },
    /// AUTO-SB (A2) input contract violation (dangling input without a mode, missing tie_break/table).
    AutoSb { reason: &'static str },
    OutputDirExists { path: String },
    Io { op: &'static str, kind: String },
    InvalidPath { field: &'static str },
    Name(NameError),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
/// Fixed: the squared error comes from the input row. MeasuredExperimental: per-glyph, resolved in main.rs (plumbed, no value here).
/// DerivedSourceQuantization: the squared error is DERIVED from the declared scale K (units_per_px, from the style's
/// OwnerDeclaredScaleSet row): (K/2)^2 output units squared. The input `fit_squared_error` is ignored for this variant.
pub enum FitErrorPolicy { Fixed, MeasuredExperimental, DerivedSourceQuantization }
/// Only the mode in use today exists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ObjectiveMode { Strict }

/// AUTO-SB (A2) mode: Median = target sb is the pooled global median; Class = target sb is the
/// per-class median for the glyph side's class (class table required), class-less side falls back
/// to the global median. Off (None in the config) = byte-identical run, no loads, no math.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AutoSbMode { Median, Class }
/// Tie-break rule for an even-n median. Explicit input only: no hidden default exists, an auto-sb
/// run without it is a config refusal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TieBreak { A, B }
impl AutoSbMode {
    pub fn from_flag(s: &str) -> Option<Self> { match s { "median" => Some(Self::Median), "class" => Some(Self::Class), _ => None } }
    pub const fn as_str(self) -> &'static str { match self { Self::Median => "median", Self::Class => "class" } }
}
impl TieBreak {
    pub fn from_flag(s: &str) -> Option<Self> { match s { "A" => Some(Self::A), "B" => Some(Self::B), _ => None } }
    pub const fn as_str(self) -> &'static str { match self { Self::A => "A", Self::B => "B" } }
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[allow(dead_code)] // config error taxonomy: variants constructed by the config test surface
pub enum ResidualEpsilonPolicy {
    /// sample_resolution / 2 (current behaviour).
    DerivedSampleHalf,
    /// explicit value in output units (finite, > 0).
    ExplicitDeclaredUnits(f64),
}

/// Structured calibration measurement record (not a free string): the stated bound model and the threshold it applies to.
#[derive(Clone, Debug, PartialEq)]
pub struct MeasurementPolicy { pub bound_basis: String, pub threshold_label: String }

/// IoU measurement settings. Declared by the run, never defaulted in code: when absent the IoU report is not run
/// (recorded as NOT_RUN in the receipt). Both values enter `canonical_record` and the frame pin.
/// Ink rule: a source pixel is ink when gray < ink_threshold. ink_threshold 0 is refused (nothing could be ink).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct IouSettings { pub ink_threshold: u8, pub flatten_steps: usize }

/// Plain input; every field is validated by `RunConfig::new`.
#[derive(Clone, Debug)]
pub struct RunConfigInput {
    pub lsb_add: f64, pub rsb_add: f64, pub post_scope: ScopePolicy, pub post_scope_label: String,
    pub rdp_epsilon: f64,
    pub fit_error_policy: Option<FitErrorPolicy>, pub fit_squared_error: f64, pub fit_max_refits: usize,
    pub flatten_tolerance: f64, pub scan_row_step: f64, pub scan_max_rows: usize,
    pub sample_resolution: f64, pub pair_min_shared_rows: usize,
    pub residual_epsilon_policy: ResidualEpsilonPolicy,
    pub max_pairs: usize, pub max_pair_evaluations: u64,
    /// None = baseline node count of the input rings as today (no manifest key exists). Some(c) = an upper cap; the effective budget is min(baseline, c).
    pub node_budget_cap: Option<usize>,
    pub measurement_policy: Option<MeasurementPolicy>,
    pub capture_dir: PathBuf, pub out_dir: PathBuf,
    pub iou: Option<IouSettings>,
    /// AUTO-SB (A2): None = off (byte-identical run). Some(mode) = apply side-bearing offsets to the
    /// solved glyph population; guard consumed as `rc.auto_sb_mode().is_some()`.
    pub auto_sb: Option<AutoSbMode>,
    /// Class-mode input: TSV (glyph_id, left_class, right_class), measured externally (perception layer).
    /// Required in class mode; refused as dangling otherwise.
    pub auto_sb_class_table: Option<PathBuf>,
    /// User offsets on the AUTO-SB target side bearings (output units, signed). 0.0 = none.
    pub auto_sb_offset_lsb: f64,
    pub auto_sb_offset_rsb: f64,
    /// Pool observations TSV path (left_class,right_class,lsb,rsb): the pooled median source.
    /// Required whenever auto_sb is on; refused as dangling when off.
    pub auto_sb_pool: Option<PathBuf>,
    /// Explicit even-n median tie rule; required whenever auto_sb is on.
    pub tie_break: Option<TieBreak>,
    /// Required identity of the style this run builds (receipt and OTF file names carry it). No default exists.
    pub style_id: String,
    /// Manifest `os2_x_height_write` token (e.g. "resolved_only"); None = key absent. Enters canonical_record only when Some, so absent configs keep their hash.
    pub os2_x_height_write: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RunConfig {
    scale: ScaleContext, offset: SignedSideBearingOffset, post_scope: ScopePolicy, post_scope_label: String,
    rdp_epsilon: DimParam, fit_error_policy: FitErrorPolicy, fit_squared_error: DimParam, fit_max_refits: usize,
    flatten_tolerance: DimParam, scan_row_step: DimParam, scan_max_rows: usize, sample_resolution: DimParam, pair_min_shared_rows: usize,
    residual_epsilon_policy: ResidualEpsilonPolicy, residual_epsilon: f64,
    max_pairs: usize, max_pair_evaluations: u64, node_budget_cap: Option<usize>, objective_mode: ObjectiveMode,
    measurement_policy: Option<MeasurementPolicy>, capture_dir: PathBuf, out_dir: PathBuf,
    iou: Option<IouSettings>,
    auto_sb: Option<AutoSbMode>, auto_sb_class_table: Option<PathBuf>,
    auto_sb_pool: Option<PathBuf>,
    auto_sb_offset_lsb: f64, auto_sb_offset_rsb: f64, tie_break: Option<TieBreak>,
    style_id: String,
    os2_x_height_write: Option<String>,
}

fn pos(f: &'static str, v: f64) -> Result<f64, ConfigError> { if v.is_finite() && v > 0.0 { Ok(v) } else { Err(ConfigError::InvalidValue { field: f }) } }
fn nz(f: &'static str, v: usize) -> Result<usize, ConfigError> { if v > 0 { Ok(v) } else { Err(ConfigError::ZeroCount { field: f }) } }
fn dp(f: &'static str, v: f64, d: Dimension, prov: &str) -> Result<DimParam, ConfigError> { DimParam::new(f, v, d, prov).map_err(|_| ConfigError::InvalidValue { field: f }) }
fn lp(s: &str) -> String { format!("{}:{};", s.len(), s) }
pub(crate) fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }
fn bits(v: f64) -> String { lp(&format!("{:016x}", v.to_bits())) }

#[allow(dead_code)] // config accessors exercised by tests; production wiring pending
impl RunConfig {
    pub const fn default_units_per_px() -> f64 { 2.4377 }
    /// Pure validation + snapshot. Reads no filesystem. `scale` is the bound ScaleContext (the single scale variable).
    pub fn new(i: RunConfigInput, scale: ScaleContext) -> Result<Self, ConfigError> {
        let fit_error_policy = i.fit_error_policy.ok_or(ConfigError::MissingFitErrorPolicy)?;
        if let Some(iou) = &i.iou { if iou.flatten_steps == 0 { return Err(ConfigError::ZeroCount { field: "iou_flatten_steps" }); }
            // ink is gray < threshold: 0 means no pixel can be ink (empty source mask), so it is refused rather than guessed.
            // 255 is allowed: everything below pure white is ink.
            if iou.ink_threshold == 0 { return Err(ConfigError::InvalidValue { field: "iou_ink_threshold" }); } }
        validate_style_id(&i.style_id)?;
        if i.post_scope_label.is_empty() { return Err(ConfigError::EmptyField { field: "post_scope_label" }); }
        // paths must be non-empty valid UTF-8: identity and receipts record them as text, and lossy display() is never used
        if i.capture_dir.to_str().map_or(true, |t| t.is_empty()) { return Err(ConfigError::InvalidPath { field: "capture_dir" }); }
        if i.out_dir.to_str().map_or(true, |t| t.is_empty()) { return Err(ConfigError::InvalidPath { field: "out_dir" }); }
        if let Some(m) = &i.measurement_policy {
            if m.bound_basis.is_empty() { return Err(ConfigError::EmptyField { field: "measurement_policy.bound_basis" }); }
            if m.threshold_label.is_empty() { return Err(ConfigError::EmptyField { field: "measurement_policy.threshold_label" }); }
        }
                let sample_resolution = dp("sample_resolution", pos("sample_resolution", i.sample_resolution)?, Dimension::DeclaredOutputUnits, "spacing quadrature, output units")?;
        let residual_epsilon = match i.residual_epsilon_policy {
            ResidualEpsilonPolicy::DerivedSampleHalf => { let h = sample_resolution.value() / 2.0; if h.is_finite() && h > 0.0 { h } else { return Err(ConfigError::InvalidResidualEpsilon) } } // tiny/2 may underflow to 0
            ResidualEpsilonPolicy::ExplicitDeclaredUnits(v) => { if v.is_finite() && v > 0.0 { v } else { return Err(ConfigError::InvalidResidualEpsilon) } }
        };
        // post-step offsets: separate DeclaredOutputUnits params, SIGNED (negative offsets are legitimate, owner
        // directive 2026-10-17: L < 0 translates ink left, R < 0 shrinks the advance); result overflow is refused later
        // by the post-step final gate (checked, never clamped)
        let lsb = dp("lsb_add", i.lsb_add, Dimension::DeclaredOutputUnits, "post-step left offset, output units")?;
        let rsb = dp("rsb_add", i.rsb_add, Dimension::DeclaredOutputUnits, "post-step right offset, output units")?;
        let offset = SignedSideBearingOffset::from_params(&lsb, &rsb).map_err(|e| ConfigError::PostMetrics { reason: format!("{e:?}") })?;
        if !offset.is_noop() && i.post_scope.is_empty() {
            return Err(ConfigError::PostMetrics { reason: "non-zero offset with empty scope".to_string() });
        }
        // Derived tolerance: half of one source-pixel quantization step (K/2 output units), squared. No literal enters this value:
        // the only inputs are K and the factor 1/2 of the half-step (a rounding half-interval, not a tuned number).
        let fit_squared_error = match fit_error_policy {
            FitErrorPolicy::DerivedSourceQuantization => {
                let half_step = 0.5 * scale.units_per_px();
                dp("fit_squared_error", pos("fit_squared_error", half_step * half_step)?, Dimension::DeclaredSquaredOutputUnits,
                   "derived: (units_per_px/2)^2 output units squared; source pixel quantization half-step; K from the style OwnerDeclaredScaleSet row")?
            }
            _ => dp("fit_squared_error", pos("fit_squared_error", i.fit_squared_error)?, Dimension::DeclaredSquaredOutputUnits, "fixed policy, output units squared, scale-independent")?,
        };
        // AUTO-SB (A2) input contract: off = byte-identical run, so any auto-sb input without a mode
        // is a hard refusal, never a silent ignore. On = tie_break REQUIRED (explicit, no hidden
        // default); class mode REQUIRES the class table; a class table in median mode is dangling
        // (median uses the pooled global median target only).
        match i.auto_sb {
            None => {
                if i.auto_sb_pool.is_some() { return Err(ConfigError::AutoSb { reason: "auto_sb_pool without auto_sb mode" }); }
                if i.auto_sb_class_table.is_some() { return Err(ConfigError::AutoSb { reason: "auto_sb_class_table without auto_sb mode" }); }
                if i.auto_sb_offset_lsb != 0.0 || i.auto_sb_offset_rsb != 0.0 { return Err(ConfigError::AutoSb { reason: "auto_sb offsets without auto_sb mode" }); }
                if i.tie_break.is_some() { return Err(ConfigError::AutoSb { reason: "tie_break without auto_sb mode" }); }
            }
            Some(AutoSbMode::Median) => {
                if i.auto_sb_pool.is_none() { return Err(ConfigError::AutoSb { reason: "median mode requires auto_sb_pool (pooled median source)" }); }
                if i.auto_sb_class_table.is_some() { return Err(ConfigError::AutoSb { reason: "auto_sb_class_table is dangling in median mode (pooled global median target)" }); }
                if i.tie_break.is_none() { return Err(ConfigError::AutoSb { reason: "median mode requires an explicit tie_break (A|B)" }); }
            }
            Some(AutoSbMode::Class) => {
                if i.auto_sb_pool.is_none() { return Err(ConfigError::AutoSb { reason: "class mode requires auto_sb_pool (pooled median source)" }); }
                match &i.auto_sb_class_table {
                    Some(p) if p.to_str().map_or(false, |t| !t.is_empty()) => {}
                    _ => return Err(ConfigError::AutoSb { reason: "class mode requires auto_sb_class_table (non-empty UTF-8 path)" }),
                }
                if i.tie_break.is_none() { return Err(ConfigError::AutoSb { reason: "class mode requires an explicit tie_break (A|B)" }); }
            }
        }
        if !i.auto_sb_offset_lsb.is_finite() { return Err(ConfigError::InvalidValue { field: "auto_sb_offset_lsb" }); }
        if !i.auto_sb_offset_rsb.is_finite() { return Err(ConfigError::InvalidValue { field: "auto_sb_offset_rsb" }); }
        Ok(RunConfig {
            scale, offset, post_scope: i.post_scope, post_scope_label: i.post_scope_label,
            rdp_epsilon: dp("rdp_epsilon", pos("rdp_epsilon", i.rdp_epsilon)?, Dimension::Pixels, "RDP on raw pixel points before unit conversion")?,
            fit_error_policy,
            fit_squared_error: fit_squared_error,
            fit_max_refits: i.fit_max_refits, // 0 is a legitimate budget (cubic_fit: attempts 0..=max_refits)
            flatten_tolerance: dp("flatten_tolerance", pos("flatten_tolerance", i.flatten_tolerance)?, Dimension::DeclaredOutputUnits, "profile flatten, output units")?,
            scan_row_step: dp("scan_row_step", pos("scan_row_step", i.scan_row_step)?, Dimension::DeclaredOutputUnits, "profile row pitch, output units")?,
            scan_max_rows: i.scan_max_rows, // 0 only refuses every profile (ResourceBound); no gate is loosened
            sample_resolution, pair_min_shared_rows: nz("pair_min_shared_rows", i.pair_min_shared_rows)?, // 0 would disable the solver shared-rows gate: not allowed
            residual_epsilon_policy: i.residual_epsilon_policy, residual_epsilon,
            max_pairs: i.max_pairs, // 0 is legitimate: forces the exclusion ledger (solver test)
            max_pair_evaluations: i.max_pair_evaluations, // hard limit; any value is a refusal bound only
            node_budget_cap: i.node_budget_cap, objective_mode: ObjectiveMode::Strict,
            measurement_policy: i.measurement_policy, capture_dir: i.capture_dir, out_dir: i.out_dir,
            iou: i.iou, style_id: i.style_id, os2_x_height_write: i.os2_x_height_write,
            auto_sb: i.auto_sb, auto_sb_class_table: i.auto_sb_class_table,
            auto_sb_pool: i.auto_sb_pool,
            auto_sb_offset_lsb: i.auto_sb_offset_lsb, auto_sb_offset_rsb: i.auto_sb_offset_rsb, tie_break: i.tie_break,
        })
    }
    /// Current manifest defaults (pipeline manifest parser defaults). The fit error policy is a REQUIRED argument; paths have no default.
    pub fn legacy_defaults_input(fit_error_policy: Option<FitErrorPolicy>, capture_dir: PathBuf, out_dir: PathBuf, style_id: &str) -> RunConfigInput {
        RunConfigInput {
            lsb_add: 0.0, rsb_add: 0.0, post_scope: ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false }, post_scope_label: "none".to_string(),
            rdp_epsilon: 0.25, fit_error_policy, fit_squared_error: 0.25, fit_max_refits: 8,
            flatten_tolerance: 0.5, scan_row_step: 10.0, scan_max_rows: 1000, sample_resolution: 10.0, pair_min_shared_rows: 1,
            residual_epsilon_policy: ResidualEpsilonPolicy::DerivedSampleHalf, max_pairs: 10_000, max_pair_evaluations: 1_000_000,
            node_budget_cap: None, measurement_policy: None, capture_dir, out_dir, iou: None,
            auto_sb: None, auto_sb_class_table: None, auto_sb_pool: None, auto_sb_offset_lsb: 0.0, auto_sb_offset_rsb: 0.0, tie_break: None,
            style_id: style_id.to_string(), os2_x_height_write: None,
        }
    }
    /// Early, advisory precheck only (NOT a safety gate; it can race). Uses lstat, so a broken symlink counts as existing.
    pub fn check_output_dir_available(&self) -> Result<(), ConfigError> {
        match std::fs::symlink_metadata(&self.out_dir) {
            Ok(_) => Err(ConfigError::OutputDirExists { path: self.out_dir.to_string_lossy().into_owned() }),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(ConfigError::Io { op: "lstat out_dir", kind: format!("{:?}", e.kind()) }),
        }
    }
    /// The real no-overwrite gate: exclusive create of the output directory (EEXIST is a refusal; an existing directory, file or
    /// symlink, broken or not, is never reused; the parent must already exist). Call this before any output is written.
    pub fn create_output_dir_exclusive(&self) -> Result<(), ConfigError> {
        // Parents are made on demand: a fresh kit/machine has no out/ root yet and
        // a NotFound from the exclusive leaf create carried no meaning. Exclusivity
        // itself is unchanged - an existing leaf still refuses below.
        if let Some(parent) = std::path::Path::new(&self.out_dir).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| ConfigError::Io { op: "create_dir_all out_dir parent", kind: format!("{:?}", e.kind()) })?;
            }
        }
        match std::fs::create_dir(&self.out_dir) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => Err(ConfigError::OutputDirExists { path: self.out_dir.to_string_lossy().into_owned() }),
            Err(e) => Err(ConfigError::Io { op: "create_dir out_dir", kind: format!("{:?}", e.kind()) }),
        }
    }

    pub fn scale(&self) -> &ScaleContext { &self.scale }
    pub fn iou_settings(&self) -> Option<IouSettings> { self.iou }
    pub fn offset(&self) -> SignedSideBearingOffset { self.offset }
    pub fn post_scope(&self) -> ScopePolicy { self.post_scope }
    pub fn post_scope_label(&self) -> &str { &self.post_scope_label }
    pub fn rdp_epsilon(&self) -> &DimParam { &self.rdp_epsilon }
    pub fn fit_error_policy(&self) -> FitErrorPolicy { self.fit_error_policy }
    pub fn fit_squared_error(&self) -> &DimParam { &self.fit_squared_error }
    pub fn fit_max_refits(&self) -> usize { self.fit_max_refits }
    pub fn flatten_tolerance(&self) -> &DimParam { &self.flatten_tolerance }
    pub fn scan_row_step(&self) -> &DimParam { &self.scan_row_step }
    pub fn scan_max_rows(&self) -> usize { self.scan_max_rows }
    pub fn sample_resolution(&self) -> &DimParam { &self.sample_resolution }
    pub fn pair_min_shared_rows(&self) -> usize { self.pair_min_shared_rows }
    pub fn residual_epsilon_policy(&self) -> ResidualEpsilonPolicy { self.residual_epsilon_policy }
    /// Resolved residual epsilon (derived or explicit).
    pub fn residual_epsilon(&self) -> f64 { self.residual_epsilon }
    pub fn max_pairs(&self) -> usize { self.max_pairs }
    pub fn max_pair_evaluations(&self) -> u64 { self.max_pair_evaluations }
    pub fn objective_mode(&self) -> ObjectiveMode { self.objective_mode }
    pub fn node_budget_cap(&self) -> Option<usize> { self.node_budget_cap }
    /// AUTO-SB (A2) guard: `rc.auto_sb_mode().is_some()` switches the A2 pass; None = byte-identical run.
    pub fn auto_sb_mode(&self) -> Option<AutoSbMode> { self.auto_sb }
    pub fn auto_sb_class_table(&self) -> Option<&Path> { self.auto_sb_class_table.as_deref() }
    pub fn auto_sb_offset_lsb(&self) -> f64 { self.auto_sb_offset_lsb }
    pub fn auto_sb_offset_rsb(&self) -> f64 { self.auto_sb_offset_rsb }
    pub fn tie_break(&self) -> Option<TieBreak> { self.tie_break }
    pub fn auto_sb_tie_break(&self) -> Option<TieBreak> { self.tie_break }
    pub fn auto_sb_pool(&self) -> Option<&Path> { self.auto_sb_pool.as_deref() }
    /// Resolved node budget: the producer baseline (current behaviour) or a LOWER cap; never above the baseline invariant (max_nodes <= baseline).
    pub fn resolve_node_budget(&self, baseline_nodes: usize) -> usize { match self.node_budget_cap { None => baseline_nodes, Some(c) => c.min(baseline_nodes) } }
    pub fn measurement_policy(&self) -> Option<&MeasurementPolicy> { self.measurement_policy.as_ref() }
    pub fn style_id(&self) -> &str { &self.style_id }
    /// OTF file name for this run: `font-<style_id>.otf` (the id is validated file-name safe by `new`).
    pub fn otf_file_name(&self) -> String { format!("font-{}.otf", self.style_id) }
    /// Receipt file name for this run: `receipt-<style_id>.txt`.
    pub fn receipt_file_name(&self) -> String { format!("receipt-{}.txt", self.style_id) }
    pub fn capture_dir(&self) -> &Path { &self.capture_dir }
    pub fn out_dir(&self) -> &Path { &self.out_dir }

    /// Scale-dependent identity (metric stages, caches): the exact ScaleContext record only; offsets are not part of it.
    pub fn scale_identity(&self) -> String { self.scale.cache_identity_component() }
    /// Stage-1 identity: scale record plus the pixel/fit parameters and the node budget cap (the cap changes output). Any future
    /// stage-1 policy dependency must be added here after a full audit; spacing and post-step values are deliberately not included.
    pub fn stage1_identity(&self) -> String {
        let p = |d: &DimParam| format!("{}{}", bits(d.value()), lp(&format!("{:?}", d.dimension())));
        format!("stage1[{}{}{}{}{}{}]", lp(&self.scale.cache_identity_component()), p(&self.rdp_epsilon), lp(&format!("{:?}", self.fit_error_policy)), p(&self.fit_squared_error), lp(&self.fit_max_refits.to_string()), lp(&match self.node_budget_cap { None => "N".to_string(), Some(n) => format!("S{n}") }))
    }
    /// Identity of the post-step: offset bits, scope flags, label, and the scale record it ran under.
    pub fn post_step_identity(&self) -> String {
        format!("post_step[{}{}{}{}{}]", bits(self.offset.lsb()), bits(self.offset.rsb()),
            lp(&format!("{}{}{}{}{}", self.post_scope.base as u8, self.post_scope.space as u8, self.post_scope.notdef as u8, self.post_scope.mark as u8,
                if self.post_scope.kerning_letters { "K" } else { "" })), // "K" only when set: every existing scope keeps its exact digest
            lp(&self.post_scope_label), lp(&self.scale.cache_identity_component()))
    }
    /// Exact canonical record of the whole config (length-prefixed, f64 by bit pattern).
    pub fn canonical_record(&self) -> String {
        let p = |d: &DimParam| format!("{}{}", bits(d.value()), lp(&format!("{:?}", d.dimension())));
        let mp = match &self.measurement_policy { None => "N".to_string(), Some(m) => format!("S{}{}", lp(&m.bound_basis), lp(&m.threshold_label)) };
        let mut r = String::from("run_config_v2;");
        let parts: Vec<String> = vec![lp(self.scale.binding_record()), lp(&self.post_step_identity()), p(&self.rdp_epsilon), lp(&format!("{:?}", self.fit_error_policy)), p(&self.fit_squared_error),
                  lp(&self.fit_max_refits.to_string()), p(&self.flatten_tolerance), p(&self.scan_row_step), lp(&self.scan_max_rows.to_string()), p(&self.sample_resolution),
                  lp(&self.pair_min_shared_rows.to_string()), lp(&format!("{:?}{:016x}", self.residual_epsilon_policy, self.residual_epsilon.to_bits())),
                  lp(&self.max_pairs.to_string()), lp(&self.max_pair_evaluations.to_string()), lp(&format!("{:?}", self.objective_mode)),
                  lp(&match self.node_budget_cap { None => "N".to_string(), Some(n) => format!("S{n}") }), lp(&mp),
                  lp(&self.capture_dir.to_string_lossy().into_owned()), lp(&self.out_dir.to_string_lossy().into_owned())];
        for f in parts { r.push_str(&f); }
        r.push_str(&lp(&format!("style:{}", self.style_id)));
        // appended only when declared, so configs without IoU settings keep their existing record and hash
        if let Some(iou) = &self.iou { r.push_str(&lp(&format!("iou:{}:{}", iou.ink_threshold, iou.flatten_steps))); }
        // same rule for AUTO-SB: off-mode configs keep their existing record and hash byte-identically
        if let Some(mode) = &self.auto_sb {
            let table = self.auto_sb_class_table.as_ref().map(|p| p.to_string_lossy().into_owned());
            let tb = self.tie_break.map(|t| t.as_str()).unwrap_or("-");
            r.push_str(&lp(&format!("auto_sb:{}:{}:{}:{:016x}:{:016x}", mode.as_str(), table.as_deref().unwrap_or("-"), tb, self.auto_sb_offset_lsb.to_bits(), self.auto_sb_offset_rsb.to_bits())));
        }
        if let Some(w) = &self.os2_x_height_write { r.push_str(&lp(&format!("os2_x_height_write:{w}"))); }
        r
    }
    pub fn os2_x_height_write(&self) -> Option<&str> { self.os2_x_height_write.as_deref() }
    /// Receipt rows: name, value, dimension, provenance (one escaped TSV row each).
    pub fn receipt_rows(&self) -> Vec<String> {
        let mut v = vec![format!("run_config\tscale_context\t{}\n", esc(self.scale.receipt_row().trim_end()))];
        for d in [&self.rdp_epsilon, &self.fit_squared_error, &self.flatten_tolerance, &self.scan_row_step, &self.sample_resolution] {
            v.push(format!("run_config\t{}\t{:?}\t{:?}\t{}\n", d.name(), d.value(), d.dimension(), esc(d.provenance())));
        }
        v.push(match self.residual_epsilon_policy {
            ResidualEpsilonPolicy::DerivedSampleHalf => format!("run_config\tresidual_epsilon\t{:?}\tDERIVED(sample_resolution/2)\t-\n", self.residual_epsilon),
            ResidualEpsilonPolicy::ExplicitDeclaredUnits(x) => format!("run_config\tresidual_epsilon\t{:?}\tEXPLICIT(DeclaredOutputUnits)\t-\n", x),
        });
        v.push(format!("run_config\tlsb_add\t{:?}\tDeclaredOutputUnits\tscope_label={}\n", self.offset.lsb(), esc(&self.post_scope_label)));
        let kl = if self.post_scope.kerning_letters { ",kerning_letters:true" } else { "" };
        v.push(format!("run_config\trsb_add\t{:?}\tDeclaredOutputUnits\tscope=base:{},space:{},notdef:{},mark:{}{}\n", self.offset.rsb(), self.post_scope.base, self.post_scope.space, self.post_scope.notdef, self.post_scope.mark, kl));
        for (n, x) in [("fit_max_refits", self.fit_max_refits as u64), ("scan_max_rows", self.scan_max_rows as u64), ("pair_min_shared_rows", self.pair_min_shared_rows as u64),
                       ("max_pairs", self.max_pairs as u64), ("max_pair_evaluations", self.max_pair_evaluations)] {
            v.push(format!("run_config\t{}\t{}\tCOUNT\t-\n", n, x));
        }
        v.push(format!("run_config\tfit_error_policy\t{:?}\tPOLICY\t-\n", self.fit_error_policy));
        v.push(format!("run_config\tobjective_mode\t{:?}\tPOLICY\t-\n", self.objective_mode));
        v.push(format!("run_config\tnode_budget\t{}\tPOLICY\t-\n", match self.node_budget_cap { None => "derived_from_input_nodes".to_string(), Some(n) => format!("min(baseline,{n})") }));
        v.push(match &self.measurement_policy {
            None => "run_config\tmeasurement_policy\tnone\tRECORD\t-\n".to_string(),
            Some(m) => format!("run_config\tmeasurement_policy\tbound_basis={}\tRECORD\tthreshold={}\n", esc(&m.bound_basis), esc(&m.threshold_label)),
        });
        if let Some(iou) = &self.iou { v.push(format!("run_config\tiou_ink_threshold\t{}\tGRAY_LEVEL\tink is gray < threshold\n", iou.ink_threshold)); v.push(format!("run_config\tiou_flatten_steps\t{}\tCOUNT\tsamples per cubic\n", iou.flatten_steps)); }
        if let Some(mode) = &self.auto_sb {
            v.push(format!("run_config\tauto_sb_mode\t{}\tPOLICY\tA2 side-bearing auto-adjust on the solved population; fallback_unsolved exempt, .notdef untouched; off = byte-identical run\n", mode.as_str()));
            v.push(format!("run_config\tauto_sb_class_table\t{}\tPATH\tglyph_id,left_class,right_class; external perception-layer measurement; class mode only\n", match &self.auto_sb_class_table { None => "none".to_string(), Some(p) => esc(&p.to_string_lossy().into_owned()) }));
            v.push(format!("run_config\tauto_sb_offset_lsb\t{:?}\tDeclaredOutputUnits\tuser offset on the target left side bearing (signed)\n", self.auto_sb_offset_lsb));
            v.push(format!("run_config\tauto_sb_offset_rsb\t{:?}\tDeclaredOutputUnits\tuser offset on the target right side bearing (signed)\n", self.auto_sb_offset_rsb));
            v.push(format!("run_config\ttie_break\t{}\tPOLICY\texplicit even-n median tie rule; no hidden default\n", self.tie_break.map(|t| t.as_str()).unwrap_or("none")));
        }
        if let Some(w) = &self.os2_x_height_write { v.push(format!("run_config\tos2_x_height_write\t{}\tPOLICY\tmanifest key, covered by run_config_sha256\n", esc(w))); }
        v.push(format!("run_config\tstyle_id\t{}\tIDENTITY\tfile names font-<id>.otf, receipt-<id>.txt\n", esc(&self.style_id)));
        v.push(format!("run_config\tcapture_dir\t{}\tPATH\t-\n", esc(&self.capture_dir.to_string_lossy().into_owned())));
        v.push(format!("run_config\tout_dir\t{}\tPATH\t-\n", esc(&self.out_dir.to_string_lossy().into_owned())));
        v
    }
}

// ---------------- names derived from file names (no name setting in the config) ----------------
#[derive(Clone, Debug, PartialEq)]
#[allow(dead_code)] // name-source taxonomy: variants constructed by the name-derivation test surface
pub enum NameError {
    /// the label is not exactly "<family>/<style>" with two non-empty parts.
    BadShape,
    EmptyPart,
    /// a control character in family or style.
    Control,
    /// an ASCII character that is forbidden in a PostScript name.
    InvalidPostScriptChar { ch: char },
    /// a non-ASCII character outside the narrow Latin table (no silent guess, no escape).
    UnmappableChar { ch: char },
    /// a combining mark (U+0300..U+036F) that does not follow a mappable letter.
    StrayCombiningMark { ch: char },
    /// derived PostScript name longer than 63 bytes (never truncated, so no truncation collisions).
    PostScriptTooLong { len: usize },
    /// two labels derive the same PostScript name.
    PostScriptCollision { ps: String },
    /// derived names disagree with a declared expectation.
    Mismatch,
}
#[derive(Clone, Debug, PartialEq)]
#[allow(dead_code)] // derivation result type of the reference name deriver mirrored by tools/kit_manifest.py
pub struct DerivedNames { pub family: String, pub subfamily: String, pub postscript_name: String }
#[allow(dead_code)] // PostScript-forbidden character table for the collision check; test-exercised
const PS_FORBIDDEN: &str = "[](){}<>/%";
/// Closed explicit transliteration table: the ONE canonical copy is `translit_table.tsv` (U+XXXX, character, ASCII base letter; 244
/// entries; Latin-1 Supplement and Latin Extended-A/B letters whose canonical decomposition is one ASCII letter plus accents).
/// The Python port reads the same file. Rust embeds it with include_str! and parses it once; a malformed table parses to an EMPTY
/// table, so every non-ASCII character is refused (fails closed). Anything not listed (ae, sharp s, o-stroke, eth, thorn, ligatures
/// such as IJ, other scripts) is refused, never guessed.
const TRANSLIT_TSV: &str = include_str!("translit_table.tsv");
fn parse_translit(tsv: &str) -> Vec<(u32, char)> {
    let mut v: Vec<(u32, char)> = Vec::new();
    for line in tsv.lines() {
        if line.is_empty() { continue; }
        let c: Vec<&str> = line.split('\t').collect();
        let ok = (|| {
            if c.len() != 3 { return None; }
            let cp = u32::from_str_radix(c[0].strip_prefix("U+")?, 16).ok()?;
            let mut a = c[1].chars(); let ch = a.next()?; if a.next().is_some() || ch as u32 != cp || cp < 0x80 { return None; }
            let mut b = c[2].chars(); let base = b.next()?; if b.next().is_some() || !base.is_ascii_alphabetic() { return None; }
            Some((cp, base))
        })();
        match ok { Some(e) => v.push(e), None => return Vec::new() }
    }
    if v.windows(2).all(|w| w[0].0 < w[1].0) { v } else { Vec::new() }
}
fn translit_table() -> &'static [(u32, char)] {
    static T: std::sync::OnceLock<Vec<(u32, char)>> = std::sync::OnceLock::new();
    T.get_or_init(|| parse_translit(TRANSLIT_TSV))
}
fn latin_base(ch: char) -> Option<char> {
    let t = translit_table();
    t.binary_search_by_key(&(ch as u32), |e| e.0).ok().map(|i| t[i].1)
}
impl NameError {
    /// Stable kind name used by the parity corpus (payload-free).
    #[allow(dead_code)] // exercised by the test suite; no production caller wired yet
    pub fn kind(&self) -> &'static str {
        match self {
            NameError::BadShape => "BadShape", NameError::EmptyPart => "EmptyPart", NameError::Control => "Control",
            NameError::InvalidPostScriptChar { .. } => "InvalidPostScriptChar", NameError::UnmappableChar { .. } => "UnmappableChar",
            NameError::StrayCombiningMark { .. } => "StrayCombiningMark", NameError::PostScriptTooLong { .. } => "PostScriptTooLong",
            NameError::PostScriptCollision { .. } => "PostScriptCollision", NameError::Mismatch => "Mismatch",
        }
    }
}
/// ONE derivation function (shared with the kit writer; the S1 Python port must match it exactly). Policy (owner decision "plain
/// translation"):
/// - label = "<family>/<style>" taken from the file/folder names (e.g. `Lÿno/Jean`, `Marq/Alternate`).
/// - family and subfamily are kept VERBATIM as given (Unicode allowed; trimmed; no control chars). No normalization is done and
///   no NFC claim is made.
/// - PostScript name = family and style, each with ASCII spaces removed, joined by "-". Per character: ASCII passes through
///   (including "."), forbidden ASCII is refused; a Latin-1 letter in `latin_base` becomes its plain base letter; a combining
///   mark in the single block U+0300..U+036F directly after a letter that was kept/mapped is dropped (decomposed input; this is a
///   documented narrow policy, not an NFC/NFD implementation: the mark is discarded whatever it is, so `a` + any mark in that block
///   gives `a`), elsewhere refused; combining marks outside that block and any other non-ASCII character are refused. More than 63 bytes is refused (no truncation).
/// - the translation is lossy: `Lyno` and `Lÿno` derive the same name. A single call cannot see other labels; collision safety
///   exists only through `derive_name_set`, which callers must use for a set.
#[allow(dead_code)] // reference derivation mirrored by tools/kit_manifest.py; exercised by parity tests
pub fn derive_names(label: &str) -> Result<DerivedNames, NameError> {
    let parts: Vec<&str> = label.split('/').collect();
    if parts.len() != 2 { return Err(NameError::BadShape); }
    let (f, s) = (parts[0].trim(), parts[1].trim());
    if f.is_empty() || s.is_empty() { return Err(NameError::EmptyPart); }
    for ch in f.chars().chain(s.chars()) { if ch.is_control() { return Err(NameError::Control); } }
    let enc = |t: &str| -> Result<String, NameError> {
        let mut o = String::new();
        let mut prev_letter = false;
        for ch in t.chars() {
            if ch == ' ' { prev_letter = false; continue; }
            if ('\u{0300}'..='\u{036F}').contains(&ch) {
                if prev_letter { continue; }
                return Err(NameError::StrayCombiningMark { ch });
            }
            if ch.is_ascii() {
                if (ch as u32) < 33 || (ch as u32) > 126 || PS_FORBIDDEN.contains(ch) { return Err(NameError::InvalidPostScriptChar { ch }); }
                o.push(ch); prev_letter = ch.is_ascii_alphabetic();
            } else {
                match latin_base(ch) { Some(b) => { o.push(b); prev_letter = true; } None => return Err(NameError::UnmappableChar { ch }) }
            }
        }
        Ok(o)
    };
    let (ef, es) = (enc(f)?, enc(s)?);
    if ef.is_empty() || es.is_empty() { return Err(NameError::EmptyPart); }
    let ps = format!("{}-{}", ef, es);
    if ps.len() > 63 { return Err(NameError::PostScriptTooLong { len: ps.len() }); }
    Ok(DerivedNames { family: f.to_string(), subfamily: s.to_string(), postscript_name: ps })
}
/// Derive names for a whole set of labels and refuse when two share a PostScript name; this is the entry point that guarantees
/// collision safety (calling `derive_names` per label does not).
#[allow(dead_code)] // reference derivation mirrored by tools/kit_manifest.py; exercised by parity tests
pub fn derive_name_set(labels: &[&str]) -> Result<Vec<DerivedNames>, NameError> {
    let v: Result<Vec<DerivedNames>, NameError> = labels.iter().map(|l| derive_names(l)).collect();
    let v = v?; check_postscript_collisions(&v)?; Ok(v)
}
/// Refuse when two derived names share a PostScript name (set-level check).
#[allow(dead_code)] // reference derivation mirrored by tools/kit_manifest.py; exercised by parity tests
pub fn check_postscript_collisions(names: &[DerivedNames]) -> Result<(), NameError> {
    let mut seen = std::collections::BTreeSet::new();
    for n in names { if !seen.insert(n.postscript_name.clone()) { return Err(NameError::PostScriptCollision { ps: n.postscript_name.clone() }); } }
    Ok(())
}
/// Derive and compare with names declared elsewhere (e.g. a legacy manifest); disagreement => Mismatch.
#[allow(dead_code)] // reference derivation mirrored by tools/kit_manifest.py; exercised by parity tests
pub fn derive_names_checked(label: &str, declared: &DerivedNames) -> Result<DerivedNames, NameError> {
    let d = derive_names(label)?;
    if &d == declared { Ok(d) } else { Err(NameError::Mismatch) }
}

/// A style id becomes part of file names, so it must be a single safe path component: non-empty, ASCII letters, digits, `-`, `_`
/// and inner `.` only (no separators, no leading dot, no spaces, no control characters).
pub fn validate_style_id(id: &str) -> Result<(), ConfigError> {
    if id.is_empty() { return Err(ConfigError::EmptyField { field: "style_id" }); }
    if id.starts_with('.') || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.') {
        return Err(ConfigError::InvalidValue { field: "style_id" });
    }
    Ok(())
}
/// Resolve the raw `--style-id` value to the file-safe id used for `font-<id>.otf` and `receipt-<id>.txt`. An id that is
/// already safe is kept verbatim. Otherwise accented Latin letters are folded to their plain base letter through the ONE shared
/// transliteration table (the same mapping `derive_names` uses for PostScript names, so `L\u{00FF}no-Stan` normalizes to
/// `Lyno-Stan`), and a combining mark in U+0300..U+036F directly after a letter is dropped (the documented narrow
/// `derive_names` policy). Every other rule of `validate_style_id` stands on the result: no `/`, no spaces, no control
/// characters, no leading `.`, no unmappable characters (ae, sharp s, other scripts are refused, never guessed), no empty id.
/// The mapping affects FILE NAMES ONLY: cohort and capture_frame identities are derived from the manifest family/subfamily and
/// stay canonical (non-ASCII included).
pub fn normalize_style_id(raw: &str) -> Result<String, ConfigError> {
    if validate_style_id(raw).is_ok() { return Ok(raw.to_string()); }
    let mut out = String::with_capacity(raw.len());
    let mut prev_letter = false;
    for ch in raw.chars() {
        if ('\u{0300}'..='\u{036F}').contains(&ch) {
            if prev_letter { continue; }
            return Err(ConfigError::InvalidValue { field: "style_id" });
        }
        if ch.is_ascii() {
            out.push(ch);
            prev_letter = ch.is_ascii_alphabetic();
        } else {
            match latin_base(ch) {
                Some(b) => { out.push(b); prev_letter = true; }
                None => return Err(ConfigError::InvalidValue { field: "style_id" }),
            }
        }
    }
    validate_style_id(&out)?;
    Ok(out)
}
/// Pull the required `--style-id <value>` (or `--style-id=<value>`) out of the argument list. Returns the id and the remaining
/// arguments with the flag and its value removed (so positional parsing is unchanged). The value goes through
/// `normalize_style_id` (accented Latin letters fold to the shared file-safe form). Missing, repeated or valueless flag is a refusal.
pub fn take_style_id_flag(args: &[String]) -> Result<(String, Vec<String>), ConfigError> {
    let mut id: Option<String> = None; let mut rest = Vec::with_capacity(args.len()); let mut it = args.iter().enumerate();
    while let Some((n, a)) = it.next() {
        let val = if n == 0 { None } else if a == "--style-id" {
            match it.next() { Some((_, v)) if !v.starts_with("--") => Some(v.clone()), _ => return Err(ConfigError::StyleIdFlag { reason: "missing value" }) }
        } else { a.strip_prefix("--style-id=").map(|v| v.to_string()) };
        match val {
            Some(v) => { if id.replace(v).is_some() { return Err(ConfigError::StyleIdFlag { reason: "repeated" }); } }
            None => rest.push(a.clone()),
        }
    }
    let id = id.ok_or(ConfigError::StyleIdFlag { reason: "required flag --style-id is missing" })?;
    let id = normalize_style_id(&id)?;
    Ok((id, rest))
}


/// Stage-1 worker count. NOT a RunConfig field: it never enters the identity, canonical record or receipt rows, so the
/// output of any `--jobs N` run is byte-identical to `--jobs 1` (the serial path).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Jobs(usize);
impl Jobs {
    pub fn new(n: usize) -> Result<Jobs, &'static str> { if n == 0 { Err("--jobs must be >= 1") } else { Ok(Jobs(n)) } }
    pub fn get(self) -> usize { self.0 }
    /// Default when the flag is absent: the machine's available parallelism (1 if it cannot be read).
    pub fn default_parallelism() -> Jobs { Jobs(std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1)) }
}
/// Pull the optional `--jobs <N>` (or `--jobs=<N>`) flag out of the argument list. Absent -> `default`. Repeated, valueless,
/// non-integer, zero or above `max` (the caller passes the machine's available parallelism) is a refusal. Remaining arguments keep their order.
pub fn take_jobs_flag(args: &[String], default: Jobs, max: Jobs) -> Result<(Jobs, Vec<String>), String> {
    let mut jobs: Option<Jobs> = None; let mut rest = Vec::with_capacity(args.len()); let mut it = args.iter().enumerate();
    while let Some((n, a)) = it.next() {
        let raw = if n == 0 { None } else if a == "--jobs" {
            match it.next() { Some((_, v)) if !v.starts_with("--") => Some(v.clone()), _ => return Err("--jobs: missing value".into()) }
        } else { a.strip_prefix("--jobs=").map(|v| v.to_string()) };
        match raw {
            Some(v) => {
                let n: usize = v.parse().map_err(|_| format!("--jobs: not a positive integer: {v}"))?;
                if n > max.get() { return Err(format!("--jobs: {n} exceeds the cap {} (available parallelism)", max.get())); }
                if jobs.replace(Jobs::new(n).map_err(|e| e.to_string())?).is_some() { return Err("--jobs: repeated".into()); }
            }
            None => rest.push(a.clone()),
        }
    }
    Ok((jobs.unwrap_or(default), rest))
}

// ---------------- manifest glyph-row validation (per-row refusal: the row is excluded, the run continues) ----------------
/// A `glyph` row whose codepoint or name fails validation is NOT a manifest refusal: the row is skipped and the run continues
/// with the remaining rows. Each skip is recorded as one `manifest_row_excluded\t<row>\treason_code\t<code>` event line
/// (`manifest_row_excluded_event`). Structural grammar faults (missing fields, extra fields, bad per-glyph scale) stay
/// manifest-level refusals in the parser; only the two row-local value domains below degrade to a row exclusion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GlyphRowRefusal {
    /// codepoint field is not hexadecimal (`0x`-prefixed or bare hex).
    CodepointSyntax,
    /// codepoint parses but is not a Unicode scalar value (surrogate or above U+10FFFF).
    CodepointNotScalar,
    /// glyph name contains a character outside the PostScript glyph-name charset [A-Za-z0-9_.] (AGL name alphabet).
    NameCharset,
    /// glyph name is longer than GLYPH_NAME_MAX_BYTES.
    NameTooLong { len: usize },
}
impl GlyphRowRefusal {
    /// Stable reason code for the exclusion event (never a free-form message).
    pub fn reason_code(&self) -> &'static str {
        match self {
            GlyphRowRefusal::CodepointSyntax => "codepoint_syntax",
            GlyphRowRefusal::CodepointNotScalar => "codepoint_non_scalar",
            GlyphRowRefusal::NameCharset => "glyph_name_charset",
            GlyphRowRefusal::NameTooLong { .. } => "glyph_name_length",
        }
    }
}
/// CONVENTION: PostScript name length limit is 63 bytes (PostScript Language Reference, name objects); the same bound as
/// `NameError::PostScriptTooLong` above and cff_container's InvalidName check. Glyph names share the font's name tables, so
/// the same limit applies; nothing is ever truncated.
pub const GLYPH_NAME_MAX_BYTES: usize = 63;
/// Validate the codepoint field of a manifest `glyph` row: hex (optional `0x`), a Unicode scalar value.
pub fn parse_glyph_row_codepoint(raw: &str) -> Result<u32, GlyphRowRefusal> {
    let cp = u32::from_str_radix(raw.strip_prefix("0x").unwrap_or(raw), 16).map_err(|_| GlyphRowRefusal::CodepointSyntax)?;
    if char::from_u32(cp).is_none() { return Err(GlyphRowRefusal::CodepointNotScalar); }
    Ok(cp)
}
/// A manifest glyph row's codepoint token: one scalar (`0x52`) or a ligature SEQUENCE of 2..=8 scalars
/// joined by `_` (`0x0066_0069` = the f_i ligature glyph). A sequence row describes ONE glyph that is
/// drawn, fitted and spaced like any other but is NOT cmap-mapped (a cmap entry is a single scalar;
/// shaping-level GSUB substitution is separate work). Empty parts, bad hex and non-scalars are refused
/// with the same typed codes as a single-codepoint row.
pub fn parse_glyph_row_codepoints(raw: &str) -> Result<Vec<u32>, GlyphRowRefusal> {
    let parts: Vec<&str> = raw.split('_').collect();
    if parts.len() > 8 { return Err(GlyphRowRefusal::CodepointSyntax); }
    let mut out = Vec::with_capacity(parts.len());
    for part in parts {
        if part.is_empty() { return Err(GlyphRowRefusal::CodepointSyntax); }
        out.push(parse_glyph_row_codepoint(part)?);
    }
    Ok(out)
}
/// Validate a manifest glyph name: non-empty by construction (the parser tokenizes on whitespace), PostScript glyph-name
/// charset, at most GLYPH_NAME_MAX_BYTES bytes. Names failing this would otherwise be written raw into the CFF name INDEX.
pub fn validate_glyph_row_name(name: &str) -> Result<(), GlyphRowRefusal> {
    if !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.') { return Err(GlyphRowRefusal::NameCharset); }
    if name.len() > GLYPH_NAME_MAX_BYTES { return Err(GlyphRowRefusal::NameTooLong { len: name.len() }); }
    Ok(())
}
/// The per-row exclusion event: `manifest_row_excluded\t<row>\treason_code\t<code>\n` (row escaped, single line).
pub fn manifest_row_excluded_event(row: &str, refusal: GlyphRowRefusal) -> String {
    format!("manifest_row_excluded\t{}\treason_code\t{}\n", esc(row), refusal.reason_code())
}

#[cfg(test)]
mod tests {
    use super::{take_jobs_flag, Jobs};
    #[test]
    fn jobs_flag_parses_defaults_and_refuses() {
        let a = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        let d = Jobs::new(7).unwrap(); let mx = Jobs::new(8).unwrap();
        assert_eq!(take_jobs_flag(&a(&["p", "m", "o"]), d, mx).unwrap(), (d, a(&["p", "m", "o"])));
        assert_eq!(take_jobs_flag(&a(&["p", "--jobs", "1", "m"]), d, mx).unwrap(), (Jobs::new(1).unwrap(), a(&["p", "m"])));
        assert_eq!(take_jobs_flag(&a(&["p", "--jobs=4", "m"]), d, mx).unwrap().0.get(), 4);
        for bad in [&["p", "--jobs"][..], &["p", "--jobs", "0"], &["p", "--jobs", "x"], &["p", "--jobs", "1", "--jobs=2"], &["p", "--jobs", "--allow-partial"], &["p", "--jobs", "9"]] {
            assert!(take_jobs_flag(&a(bad), d, mx).is_err(), "{bad:?}");
        }
        assert!(Jobs::default_parallelism().get() >= 1);
    }
    use super::*;
    use kni_core::scale_context::ScaleContext;
    // fixture values are test inputs, not engine constants
    fn ctx(k: f64) -> ScaleContext { ScaleContext::from_convention("r", "c", k, 1000.0, "cohort", "frame").unwrap() }
    fn input() -> RunConfigInput { RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("cap"), PathBuf::from("out"), "s1") }
    fn cfg() -> RunConfig { RunConfig::new(input(), ctx(2.0)).unwrap() }

    // ---- AUTO-SB (A2) config contract ----
    fn auto_input(mode: Option<AutoSbMode>, table: Option<&str>, lsb: f64, rsb: f64, tb: Option<TieBreak>) -> RunConfigInput {
        let mut i = input();
        i.auto_sb = mode;
        i.auto_sb_class_table = table.map(PathBuf::from);
        i.auto_sb_offset_lsb = lsb;
        i.auto_sb_offset_rsb = rsb;
        i.tie_break = tb;
        i.auto_sb_pool = if mode.is_some() { Some(PathBuf::from("pool.tsv")) } else { None };
        i
    }
    #[test]
    fn auto_sb_off_is_byte_identical_and_dangling_inputs_refuse() {
        let legacy = cfg();
        assert_eq!(legacy.auto_sb_mode(), None);
        assert!(!legacy.canonical_record().contains("auto_sb"));
        assert!(!legacy.receipt_rows().iter().any(|r| r.contains("auto_sb")));
        assert!(RunConfig::new(auto_input(None, None, 0.0, 0.0, None), ctx(2.0)).is_ok());
        assert!(RunConfig::new(auto_input(None, Some("t.tsv"), 0.0, 0.0, None), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(None, None, 1.0, 0.0, None), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(None, None, 0.0, -2.5, None), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(None, None, 0.0, 0.0, Some(TieBreak::A)), ctx(2.0)).is_err());
    }
    #[test]
    fn auto_sb_mode_accessor_and_receipt_identity() {
        let c = RunConfig::new(auto_input(Some(AutoSbMode::Median), None, -12.5, 3.0, Some(TieBreak::A)), ctx(2.0)).unwrap();
        assert_eq!(c.auto_sb_mode(), Some(AutoSbMode::Median));
        assert_eq!(c.auto_sb_class_table(), None);
        assert_eq!(c.auto_sb_offset_lsb(), -12.5);
        assert_eq!(c.auto_sb_offset_rsb(), 3.0);
        assert_eq!(c.tie_break(), Some(TieBreak::A));
        let rows = c.receipt_rows().concat();
        for row in ["run_config\tauto_sb_mode\tmedian\t", "run_config\tauto_sb_class_table\tnone\t",
                    "run_config\tauto_sb_offset_lsb\t-12.5\t", "run_config\tauto_sb_offset_rsb\t3.0\t", "run_config\ttie_break\tA\t"] {
            assert!(rows.contains(row), "missing receipt row {row:?}");
        }
        assert!(c.canonical_record().contains("auto_sb:median:-:A:"));
        assert!(c.auto_sb_mode().is_some()); // the A2 guard contract
    }
    #[test]
    fn auto_sb_mode_specific_requirements() {
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Median), Some("t.tsv"), 0.0, 0.0, Some(TieBreak::A)), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Class), None, 0.0, 0.0, Some(TieBreak::B)), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Median), None, 0.0, 0.0, None), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Class), Some("t.tsv"), 0.0, 0.0, None), ctx(2.0)).is_err());
        let c = RunConfig::new(auto_input(Some(AutoSbMode::Class), Some("classes.tsv"), 0.0, 0.0, Some(TieBreak::B)), ctx(2.0)).unwrap();
        assert_eq!(c.auto_sb_class_table(), Some(std::path::Path::new("classes.tsv")));
        assert!(c.receipt_rows().concat().contains("run_config\tauto_sb_class_table\tclasses.tsv\t"));
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Median), None, f64::NAN, 0.0, Some(TieBreak::A)), ctx(2.0)).is_err());
        assert!(RunConfig::new(auto_input(Some(AutoSbMode::Median), None, 0.0, f64::INFINITY, Some(TieBreak::A)), ctx(2.0)).is_err());
    }
    #[test]
    fn auto_sb_flag_value_grammar() {
        assert_eq!(AutoSbMode::from_flag("median"), Some(AutoSbMode::Median));
        assert_eq!(AutoSbMode::from_flag("class"), Some(AutoSbMode::Class));
        assert_eq!(AutoSbMode::from_flag("Median"), None);
        assert_eq!(TieBreak::from_flag("A"), Some(TieBreak::A));
        assert_eq!(TieBreak::from_flag("B"), Some(TieBreak::B));
        assert_eq!(TieBreak::from_flag("a"), None);
    }
    #[test]
    fn os2_x_height_write_enters_canonical_record_only_when_declared() {
        let a = cfg(); let mut i = input(); i.os2_x_height_write = Some("resolved_only".into());
        let b = RunConfig::new(i, ctx(2.0)).unwrap();
        assert_ne!(a.canonical_record(), b.canonical_record());
        assert!(b.canonical_record().starts_with(&a.canonical_record()), "absent key must keep the legacy record prefix");
        assert_eq!(a.os2_x_height_write(), None); assert_eq!(b.os2_x_height_write(), Some("resolved_only"));
        assert!(b.receipt_rows().iter().any(|r| r.contains("os2_x_height_write\tresolved_only")));
        assert!(!a.receipt_rows().iter().any(|r| r.contains("os2_x_height_write")));
    }
    #[test]
    fn iou_settings_are_declared_hashed_and_validated() {
        let none = cfg();
        assert!(none.iou_settings().is_none());
        assert!(!none.receipt_rows().iter().any(|r| r.contains("iou_")));
        let mut i = input(); i.iou = Some(IouSettings { ink_threshold: 100, flatten_steps: 16 });
        let a = RunConfig::new(i.clone(), ctx(2.0)).unwrap();
        assert_eq!(a.iou_settings(), Some(IouSettings { ink_threshold: 100, flatten_steps: 16 }));
        assert_ne!(a.canonical_record(), none.canonical_record());
        i.iou = Some(IouSettings { ink_threshold: 101, flatten_steps: 16 });
        let b = RunConfig::new(i.clone(), ctx(2.0)).unwrap();
        assert_ne!(a.canonical_record(), b.canonical_record());
        assert!(a.receipt_rows().iter().any(|r| r.starts_with("run_config\tiou_ink_threshold\t100\t")));
        i.iou = Some(IouSettings { ink_threshold: 100, flatten_steps: 0 });
        assert!(RunConfig::new(i.clone(), ctx(2.0)).is_err());
        i.iou = Some(IouSettings { ink_threshold: 0, flatten_steps: 16 });
        assert!(matches!(RunConfig::new(i.clone(), ctx(2.0)), Err(ConfigError::InvalidValue { field: "iou_ink_threshold" })));
        i.iou = Some(IouSettings { ink_threshold: 255, flatten_steps: 16 });
        assert!(RunConfig::new(i, ctx(2.0)).is_ok());
    }
    fn unique_dir(tag: &str) -> PathBuf {
        let n = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
        std::env::temp_dir().join(format!("run_config_test_{}_{}_{}", tag, std::process::id(), n))
    }

    // Build the adapter input from the existing config helper, not new numeric
    // fixtures. These are wiring tests, not final-overlap measurement evidence.

    #[test]
    fn defaults_match_the_current_manifest_defaults_and_require_a_fit_policy() {
        let c = cfg();
        assert_eq!((c.rdp_epsilon().value(), c.fit_squared_error().value(), c.flatten_tolerance().value(), c.scan_row_step().value(), c.sample_resolution().value()), (0.25, 0.25, 0.5, 10.0, 10.0));
        assert_eq!((c.fit_max_refits(), c.scan_max_rows(), c.pair_min_shared_rows(), c.max_pairs(), c.max_pair_evaluations()), (8, 1000, 1, 10_000, 1_000_000));
        assert_eq!((c.objective_mode(), c.node_budget_cap(), c.fit_error_policy()), (ObjectiveMode::Strict, None, FitErrorPolicy::Fixed));
        assert_eq!(c.residual_epsilon(), 5.0);
        assert!(c.offset().is_noop());
        let missing = RunConfig::legacy_defaults_input(None, PathBuf::from("cap"), PathBuf::from("out"), "s1");
        assert_eq!(RunConfig::new(missing, ctx(2.0)), Err(ConfigError::MissingFitErrorPolicy));
    }
    #[test]
    fn residual_epsilon_policy_is_derived_or_explicit_and_validated() {
        let mut i = input(); i.sample_resolution = 6.0;
        assert_eq!(RunConfig::new(i, ctx(2.0)).unwrap().residual_epsilon(), 3.0);
        let mut i = input(); i.residual_epsilon_policy = ResidualEpsilonPolicy::ExplicitDeclaredUnits(4.0);
        let c = RunConfig::new(i, ctx(2.0)).unwrap();
        assert_eq!(c.residual_epsilon(), 4.0);
        assert!(c.receipt_rows().iter().any(|r| r.starts_with("run_config\tresidual_epsilon\t4.0\tEXPLICIT")));
        assert!(cfg().receipt_rows().iter().any(|r| r.starts_with("run_config\tresidual_epsilon\t5.0\tDERIVED")));
        for bad in [-1.0, 0.0, f64::NAN, f64::INFINITY] {
            let mut i = input(); i.residual_epsilon_policy = ResidualEpsilonPolicy::ExplicitDeclaredUnits(bad);
            assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidResidualEpsilon));
        }
    }
    #[test]
    fn count_domains_and_float_domains_are_enforced() {
        let t: Vec<(Box<dyn Fn(&mut RunConfigInput)>, ConfigError)> = vec![
            (Box::new(|i| i.pair_min_shared_rows = 0), ConfigError::ZeroCount { field: "pair_min_shared_rows" }),
            (Box::new(|i| i.rdp_epsilon = 0.0), ConfigError::InvalidValue { field: "rdp_epsilon" }),
            (Box::new(|i| i.flatten_tolerance = 0.0), ConfigError::InvalidValue { field: "flatten_tolerance" }),
            (Box::new(|i| i.rdp_epsilon = -0.1), ConfigError::InvalidValue { field: "rdp_epsilon" }),
            (Box::new(|i| i.fit_squared_error = f64::NAN), ConfigError::InvalidValue { field: "fit_squared_error" }),
            (Box::new(|i| i.flatten_tolerance = f64::INFINITY), ConfigError::InvalidValue { field: "flatten_tolerance" }),
            (Box::new(|i| i.scan_row_step = 0.0), ConfigError::InvalidValue { field: "scan_row_step" }),
            (Box::new(|i| i.sample_resolution = -2.0), ConfigError::InvalidValue { field: "sample_resolution" }),
        ];
        for (m, e) in t { let mut i = input(); m(&mut i); assert_eq!(RunConfig::new(i, ctx(2.0)), Err(e)); }
        // counts follow the consumers (source-traced): these zeros are legitimate, only pair_min_shared_rows >= 1 is enforced
        let mut i = input(); i.fit_max_refits = 0; i.max_pairs = 0; i.max_pair_evaluations = 0; i.scan_max_rows = 0; i.node_budget_cap = Some(0);
        assert!(RunConfig::new(i, ctx(2.0)).is_ok());
    }
    #[test]
    fn post_metrics_validated_and_overflow_is_left_to_the_post_step_final_gate() {
        let base = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        let mut i = input(); i.lsb_add = 7.0; i.rsb_add = 9.0; i.post_scope = base; i.post_scope_label = "grp".into();
        let c = RunConfig::new(i, ctx(2.0)).unwrap();
        assert_eq!((c.offset().lsb(), c.offset().rsb()), (7.0, 9.0));
        let mut i = input(); i.lsb_add = 7.0; assert!(matches!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::PostMetrics { .. }))); // non-zero with empty scope
        let mut i = input(); i.lsb_add = -1.0; i.post_scope = base; let c = RunConfig::new(i, ctx(2.0)).unwrap(); assert_eq!((c.offset().lsb(), c.offset().rsb()), (-1.0, 0.0)); // negative offsets legitimate (owner 2026-10-17)
        let mut i = input(); i.lsb_add = 2.5; i.post_scope = base; assert!(matches!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::PostMetrics { .. })));
        // a huge but valid offset is accepted here; the post-step final gate (NumericRange/OutOfBounds) refuses its result
        let mut i = input(); i.lsb_add = 1e308; i.rsb_add = 0.0; i.post_scope = base; assert!(RunConfig::new(i, ctx(2.0)).is_ok());
        // finite operands whose facing-gap delta overflows are refused at construction
        let mut i = input(); i.lsb_add = 1e308; i.rsb_add = 1e308; i.post_scope = base; assert!(matches!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::PostMetrics { .. })));
    }
    #[test]
    fn identities_separate_scale_stage1_and_post_step() {
        let a = cfg();
        let mut i = input(); i.lsb_add = 7.0; i.post_scope = ScopePolicy { base: true, space: false, notdef: false, mark: false, kerning_letters: false };
        let b = RunConfig::new(i, ctx(2.0)).unwrap();
        assert_eq!(a.scale_identity(), b.scale_identity());
        assert_eq!(a.stage1_identity(), b.stage1_identity()); // offsets do not invalidate stage 1
        assert_ne!(a.post_step_identity(), b.post_step_identity());
        assert_ne!(a.canonical_record(), b.canonical_record());
        let k3 = RunConfig::new(input(), ctx(3.0)).unwrap();
        assert_ne!(a.scale_identity(), k3.scale_identity());
        assert_ne!(a.stage1_identity(), k3.stage1_identity());
        assert_ne!(a.post_step_identity(), k3.post_step_identity());
        let mut i = input(); i.sample_resolution = 8.0;
        let s = RunConfig::new(i, ctx(2.0)).unwrap();
        let mut i = input(); i.node_budget_cap = Some(5);
        assert_ne!(a.stage1_identity(), RunConfig::new(i, ctx(2.0)).unwrap().stage1_identity()); // the cap changes output
        assert_eq!(a.stage1_identity(), s.stage1_identity()); // spacing does not invalidate stage 1
        assert_ne!(a.canonical_record(), s.canonical_record());
        let mut i = input(); i.rdp_epsilon = 0.5;
        assert_ne!(a.stage1_identity(), RunConfig::new(i, ctx(2.0)).unwrap().stage1_identity());
        let mut i = input(); i.fit_error_policy = Some(FitErrorPolicy::MeasuredExperimental);
        assert_ne!(a.stage1_identity(), RunConfig::new(i, ctx(2.0)).unwrap().stage1_identity());
    }
    #[test]
    fn calibration_measurement_record_is_structured_and_validated() {
        let mut i = input(); i.measurement_policy = Some(MeasurementPolicy { bound_basis: "edge convention".into(), threshold_label: "thr128".into() });
        let c = RunConfig::new(i, ctx(2.0)).unwrap();
        assert!(c.receipt_rows().iter().any(|r| r == "run_config\tmeasurement_policy\tbound_basis=edge convention\tRECORD\tthreshold=thr128\n"));
        assert_ne!(c.canonical_record(), cfg().canonical_record());
        let mut i = input(); i.measurement_policy = Some(MeasurementPolicy { bound_basis: String::new(), threshold_label: "t".into() });
        assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::EmptyField { field: "measurement_policy.bound_basis" }));
        let mut i = input(); i.measurement_policy = Some(MeasurementPolicy { bound_basis: "b".into(), threshold_label: String::new() });
        assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::EmptyField { field: "measurement_policy.threshold_label" }));
    }
    #[test]
    fn math_validation_does_not_touch_the_filesystem_and_path_check_is_separate() {
        // `new` accepts an out_dir that exists; only check_output_dir_available looks at the filesystem
        let dir = unique_dir("exists");
        std::fs::create_dir_all(&dir).unwrap();
        let mut i = input(); i.out_dir = dir.clone();
        let c = RunConfig::new(i, ctx(2.0)).unwrap();
        assert_eq!(c.check_output_dir_available(), Err(ConfigError::OutputDirExists { path: dir.to_string_lossy().into_owned() }));
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(c.check_output_dir_available(), Ok(()));
        let mut i = input(); i.out_dir = PathBuf::new(); assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidPath { field: "out_dir" }));
        let mut i = input(); i.capture_dir = PathBuf::new(); assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidPath { field: "capture_dir" }));
    }
    #[test]
    fn derived_source_quantization_is_half_step_squared_with_provenance_and_identity() {
        let mut i = input(); i.fit_error_policy = Some(FitErrorPolicy::DerivedSourceQuantization);
        i.fit_squared_error = 123.0; // ignored by this variant
        let c = RunConfig::new(i.clone(), ctx(2.0)).unwrap();
        assert_eq!(c.fit_squared_error().value(), 1.0); // K=2 -> (2/2)^2
        assert_eq!(c.fit_squared_error().provenance(), "derived: (units_per_px/2)^2 output units squared; source pixel quantization half-step; K from the style OwnerDeclaredScaleSet row");
        assert!(c.receipt_rows().iter().any(|r| r.starts_with("run_config\tfit_squared_error\t1") && r.contains("\tDeclaredSquaredOutputUnits\tderived: (units_per_px/2)^2")));
        assert_eq!(RunConfig::new(i.clone(), ctx(4.0)).unwrap().fit_squared_error().value(), 4.0);
        // cache identity differs from Fixed even when the numeric value coincides (policy Debug is part of the key)
        let mut f = input(); f.fit_squared_error = 1.0;
        let fixed = RunConfig::new(f, ctx(2.0)).unwrap();
        assert_eq!(fixed.fit_squared_error().value(), c.fit_squared_error().value());
        assert_ne!(fixed.stage1_identity(), c.stage1_identity());
        // and differs across K
        assert_ne!(c.stage1_identity(), RunConfig::new(i, ctx(4.0)).unwrap().stage1_identity());
    }
    #[test]
    fn fixed_policy_behaviour_unchanged() {
        let c = cfg();
        assert_eq!(c.fit_squared_error().value(), 0.25);
        assert_eq!(c.fit_squared_error().provenance(), "fixed policy, output units squared, scale-independent");
    }
    #[test]
    fn receipt_rows_carry_name_value_dimension_provenance_and_are_single_line() {
        let rows = cfg().receipt_rows();
        assert!(rows.iter().all(|r| r.matches('\n').count() == 1 && r.starts_with("run_config\t")));
        assert!(rows.contains(&"run_config\tfit_squared_error\t0.25\tDeclaredSquaredOutputUnits\tfixed policy, output units squared, scale-independent\n".to_string()));
        assert!(rows.iter().any(|r| r.starts_with("run_config\tnode_budget\tderived_from_input_nodes")));
        let mut i = input(); i.out_dir = PathBuf::from("o\tx\n");
        assert!(RunConfig::new(i, ctx(2.0)).unwrap().receipt_rows().iter().any(|r| r.contains("out_dir\to\\tx\\n")));
    }
    #[test]
    fn names_are_derived_from_the_file_label_with_typed_refusals() {
        let d = derive_names("Family Name/Style One").unwrap();
        assert_eq!((d.family.as_str(), d.subfamily.as_str(), d.postscript_name.as_str()), ("Family Name", "Style One", "FamilyName-StyleOne"));
        assert_eq!(derive_names("NoSlash"), Err(NameError::BadShape));
        assert_eq!(derive_names("a/b/c"), Err(NameError::BadShape));
        assert_eq!(derive_names("/Style"), Err(NameError::EmptyPart));
        assert_eq!(derive_names("Fam/ "), Err(NameError::EmptyPart));
        assert_eq!(derive_names("Fa(m/Style"), Err(NameError::InvalidPostScriptChar { ch: '(' }));
        assert_eq!(derive_names_checked("A/B", &DerivedNames { family: "A".into(), subfamily: "B".into(), postscript_name: "A-B".into() }).map(|d| d.postscript_name), Ok("A-B".to_string()));
        assert_eq!(derive_names_checked("A/B", &DerivedNames { family: "A".into(), subfamily: "C".into(), postscript_name: "A-C".into() }), Err(NameError::Mismatch));
        let m = derive_names("Marq/Alternate").unwrap();
        assert_eq!((m.family.as_str(), m.subfamily.as_str(), m.postscript_name.as_str()), ("Marq", "Alternate", "Marq-Alternate")); // existing name contract
        // RunConfig has no name field by construction
    }
    #[test]
    fn measurement_none_and_empty_strings_have_distinct_identity_and_underflow_is_refused() {
        let none = cfg();
        // Some with empty strings is refused, and None vs Some("-","-") differ in identity
        let mut i = input(); i.measurement_policy = Some(MeasurementPolicy { bound_basis: "-".into(), threshold_label: "-".into() });
        assert_ne!(RunConfig::new(i, ctx(2.0)).unwrap().canonical_record(), none.canonical_record());
        let mut i = input(); i.node_budget_cap = Some(7);
        assert_ne!(RunConfig::new(i, ctx(2.0)).unwrap().canonical_record(), none.canonical_record());
        // sample_resolution tiny: halving underflows to 0 -> refused; explicit policy is unaffected
        let mut i = input(); i.sample_resolution = f64::from_bits(1); // smallest subnormal
        assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidResidualEpsilon));
    }
    #[test]
    fn node_budget_never_exceeds_the_producer_baseline() {
        assert_eq!(cfg().resolve_node_budget(40), 40);
        let mut i = input(); i.node_budget_cap = Some(10);
        assert_eq!(RunConfig::new(i, ctx(2.0)).unwrap().resolve_node_budget(40), 10);
        let mut i = input(); i.node_budget_cap = Some(100);
        assert_eq!(RunConfig::new(i, ctx(2.0)).unwrap().resolve_node_budget(40), 40);
    }
    #[cfg(unix)]
    #[test]
    fn non_utf8_paths_are_refused() {
        use std::os::unix::ffi::OsStringExt;
        let bad = PathBuf::from(std::ffi::OsString::from_vec(vec![b'o', 0xFF, b'x']));
        let mut i = input(); i.out_dir = bad.clone(); assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidPath { field: "out_dir" }));
        let mut i = input(); i.capture_dir = bad; assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::InvalidPath { field: "capture_dir" }));
    }
    #[test]
    fn unicode_family_is_verbatim_and_postscript_is_ascii_bounded_and_collision_checked() {
        let d = derive_names("L\u{00FF}no/Jean").unwrap();
        assert_eq!((d.family.as_str(), d.subfamily.as_str(), d.postscript_name.as_str()), ("L\u{00FF}no", "Jean", "Lyno-Jean"));
        assert!(d.postscript_name.is_ascii() && d.postscript_name.len() <= 63);
        // existing validator rule: ASCII 33..126, no delimiters, <= 63 bytes
        assert!(d.postscript_name.bytes().all(|b| (33..=126).contains(&b) && !b"[](){}<>/%".contains(&b)));
        // 63 bytes ok, 64 refused (no truncation)
        let ok = format!("{}/{}", "a".repeat(40), "b".repeat(22)); assert_eq!(derive_names(&ok).unwrap().postscript_name.len(), 63);
        let long = format!("{}/{}", "a".repeat(40), "b".repeat(23)); assert_eq!(derive_names(&long), Err(NameError::PostScriptTooLong { len: 64 }));
        // control characters and decomposed (combining) input are refused
        assert_eq!(derive_names("Fa\u{0007}m/S"), Err(NameError::Control));
        assert_eq!(derive_names("Fa\u{0009}m/S"), Err(NameError::Control));
        // no NFC claim: visible names are verbatim (composed and decomposed spellings stay different strings)
        assert_eq!(derive_names("Ly\u{0308}no/S").unwrap().family, "Ly\u{0308}no");
        // lossy translation: Lyno and Lÿno collide; the set entry point refuses, a lone call cannot know
        let a = derive_names("L\u{00FF}no/Jean").unwrap();
        let b = derive_names("Lyno/Jean").unwrap();
        assert_eq!(a.postscript_name, b.postscript_name);
        assert_eq!(check_postscript_collisions(&[a.clone(), b]), Err(NameError::PostScriptCollision { ps: "Lyno-Jean".into() }));
        assert_eq!(derive_name_set(&["L\u{00FF}no/Jean", "Lyno/Jean"]), Err(NameError::PostScriptCollision { ps: "Lyno-Jean".into() }));
        assert_eq!(derive_name_set(&["Marq/Alternate", "Marq/Standard"]).unwrap().len(), 2);
        // spaces are dropped from PostScript, kept in family
        // vectors shared with the Python port
        for (l, ps) in [("L\u{00FF}no/Jean", "Lyno-Jean"), ("MCA U/3U1.5", "MCAU-3U1.5"), ("MCA U/10U8 IT", "MCAU-10U8IT"), ("Paul New/Regular", "PaulNew-Regular"),
                        ("Marq/Alternate", "Marq-Alternate"), ("\u{00C9}cole/R", "Ecole-R"), ("Ly\u{0308}no/S", "Lyno-S"), ("Na\u{00EF}ve/\u{00FC}", "Naive-u")] {
            assert_eq!(derive_names(l).unwrap().postscript_name, ps, "{l}");
        }
        for ch in ['\u{00C6}', '\u{00F8}', '\u{00DF}', '\u{0132}', '\u{00D0}', '\u{00DE}'] { assert_eq!(derive_names(&format!("{ch}x/S")), Err(NameError::UnmappableChar { ch })); }
        // the embedded table is sorted, unique, ASCII-letter valued, and every entry is accepted by derive_names
        let t = translit_table();
        assert_eq!(t.len(), 244);
        assert!(t.windows(2).all(|w| w[0].0 < w[1].0) && t.iter().all(|e| e.1.is_ascii_alphabetic() && e.0 > 0x7F));
        for (cp, b) in t.iter() { let c = char::from_u32(*cp).unwrap(); assert_eq!(derive_names(&format!("{c}/S")).unwrap().postscript_name, format!("{b}-S")); }
        // a malformed table fails closed (empty), it never half-loads
        assert!(parse_translit("U+00C0\t\u{00C0}\tA\nU+00C1\t\u{00C1}\tAB\n").is_empty());
        assert!(parse_translit("U+00C1\t\u{00C1}\tA\nU+00C0\t\u{00C0}\tA\n").is_empty());
        assert!(parse_translit("U+00C0\tX\tA\n").is_empty());
        assert_eq!(parse_translit("U+00C0\t\u{00C0}\tA\n"), vec![(0xC0, 'A')]);
        assert_eq!(derive_names("\u{0416}/S"), Err(NameError::UnmappableChar { ch: '\u{0416}' }));
        assert_eq!(derive_names("\u{0308}x/S"), Err(NameError::StrayCombiningMark { ch: '\u{0308}' }));
        assert_eq!(derive_names("A \u{0308}/S"), Err(NameError::StrayCombiningMark { ch: '\u{0308}' }));
        assert_eq!(derive_names("Mona Alt/Regular").unwrap().postscript_name, "MonaAlt-Regular");
    }
    #[cfg(unix)]
    #[test]
    fn output_dir_is_created_exclusively_and_never_reused() {
        let base = unique_dir("excl"); std::fs::create_dir_all(&base).unwrap();
        let mk = |p: &PathBuf| { let mut i = input(); i.out_dir = p.clone(); RunConfig::new(i, ctx(2.0)).unwrap() };
        // fresh: precheck ok, exclusive create ok, second create refused, existing content untouched
        let fresh = base.join("out"); let c = mk(&fresh);
        assert_eq!(c.check_output_dir_available(), Ok(()));
        assert_eq!(c.create_output_dir_exclusive(), Ok(()));
        std::fs::write(fresh.join("keep.txt"), b"x").unwrap();
        assert!(matches!(c.create_output_dir_exclusive(), Err(ConfigError::OutputDirExists { .. })));
        assert!(matches!(c.check_output_dir_available(), Err(ConfigError::OutputDirExists { .. })));
        assert_eq!(std::fs::read(fresh.join("keep.txt")).unwrap(), b"x");
        // broken symlink: exists() is false for it, but both the precheck (lstat) and the exclusive create refuse
        let link = base.join("dangling"); std::os::unix::fs::symlink(base.join("nowhere"), &link).unwrap();
        assert!(!link.exists());
        let c = mk(&link);
        assert!(matches!(c.check_output_dir_available(), Err(ConfigError::OutputDirExists { .. })));
        assert!(matches!(c.create_output_dir_exclusive(), Err(ConfigError::OutputDirExists { .. })));
        assert!(!base.join("nowhere").exists()); // nothing was created through the link
        // missing parents are created on demand; the leaf stays exclusive
        let c = mk(&base.join("no_parent").join("out"));
        assert_eq!(c.create_output_dir_exclusive(), Ok(()));
        assert!(matches!(c.create_output_dir_exclusive(), Err(ConfigError::OutputDirExists { .. })));
        let _ = std::fs::remove_dir_all(&base);
    }
    // ---- parity corpus verification (the JSON is written by examples/gen_derive_names_parity.rs; tests only READ and VERIFY it) ----
    const PARITY: &str = include_str!("derive_names_parity.json");
    fn section(name: &str) -> Vec<&'static str> {
        let key = format!("\"{}\":[", name);
        let start = PARITY.find(&key).expect("section") + key.len();
        let rest = &PARITY[start..];
        let end = rest.find("\n]").expect("section end");
        rest[..end].lines().map(|l| l.trim_end_matches(',')).filter(|l| !l.is_empty()).collect()
    }
    fn label_from(cps: &str) -> String { cps.trim_matches(|c| c == '[' || c == ']').split(',').map(|n| char::from_u32(n.parse().unwrap()).unwrap()).collect() }
    #[test]
    fn parity_case_vectors_run_against_the_code() {
        let cases = section("cases");
        assert_eq!(cases.len(), 11);
        for line in cases {
            let body = line.strip_prefix("{\"labels_cps\":[").and_then(|b| b.strip_suffix("\"}")).expect("case shape");
            let (labels, expect) = body.split_once("],\"expect\":\"").expect("case split");
            let labels: Vec<String> = labels.split("],[").map(label_from).collect();
            if labels.len() == 1 {
                let l = &labels[0];
                match derive_names(l) {
                    Ok(d) => {
                        assert_eq!(format!("ok:{}", d.postscript_name), expect, "{l}");
                        // visible names are verbatim: trimmed halves of the label, independent of the derivation
                        let (f, st) = l.split_once('/').unwrap();
                        assert_eq!((d.family.as_str(), d.subfamily.as_str()), (f.trim(), st.trim()), "{l}");
                    }
                    Err(e) => assert_eq!(format!("err:{}", e.kind()), expect, "{l}"),
                }
            } else {
                let refs: Vec<&str> = labels.iter().map(|x| x.as_str()).collect();
                match derive_name_set(&refs) {
                    Ok(v) => { assert_eq!(expect, "ok:set"); assert_eq!(v.len(), refs.len()); for (d, l) in v.iter().zip(&refs) { assert_eq!(d.family, l.split_once('/').unwrap().0.trim()); } }
                    Err(e) => assert_eq!(format!("err:{}", e.kind()), expect),
                }
            }
        }
    }
    #[test]
    fn parity_corpus_covers_every_scalar_value_and_matches_the_code() {
        for (name, prefix) in [("corpus_alone", ""), ("corpus_after_letter_a", "a")] {
            let mut next: u32 = 0; let mut n_ranges = 0;
            for line in section(name) {
                // ["XXXX","YYYY","result"] with \" and \\ escapes in the result
                let inner = line.strip_prefix("[\"").and_then(|l| l.strip_suffix("\"]")).expect("range shape");
                let (from, rest) = inner.split_once("\",\"").unwrap();
                let (to, res) = rest.split_once("\",\"").unwrap();
                let res = res.replace("\\\"", "\"").replace("\\\\", "\\");
                let (from, to) = (u32::from_str_radix(from, 16).unwrap(), u32::from_str_radix(to, 16).unwrap());
                if next == 0xD800 { next = 0xE000; }
                assert_eq!(from, next, "{name}: gap or overlap");
                for cp in from..=to {
                    let c = char::from_u32(cp).expect("scalar");
                    let got = match derive_names(&format!("{prefix}{c}/S")) { Ok(d) => format!("ok:{}", d.postscript_name), Err(e) => format!("err:{}", e.kind()) };
                    assert_eq!(got, res, "{name} U+{cp:04X}");
                }
                next = to + 1; n_ranges += 1;
            }
            assert_eq!(next, 0x110000, "{name}: must end at the last scalar value");
            assert!(n_ranges > 100);
        }
    }

    #[test]
    fn style_id_flag_is_required_validated_and_removed_from_positionals() {
        let a = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        let (id, rest) = take_style_id_flag(&a(&["bin", "m", "--style-id", "marq-alt", "o", "--allow-partial"])).unwrap();
        assert_eq!((id.as_str(), rest), ("marq-alt", a(&["bin", "m", "o", "--allow-partial"])));
        assert_eq!(take_style_id_flag(&a(&["bin", "--style-id=x1", "m", "o"])).unwrap().0, "x1");
        assert!(matches!(take_style_id_flag(&a(&["bin", "m", "o"])), Err(ConfigError::StyleIdFlag { .. })));
        assert!(matches!(take_style_id_flag(&a(&["bin", "m", "o", "--style-id"])), Err(ConfigError::StyleIdFlag { .. })));
        assert!(matches!(take_style_id_flag(&a(&["bin", "--style-id", "--allow-partial"])), Err(ConfigError::StyleIdFlag { .. })));
        assert!(matches!(take_style_id_flag(&a(&["bin", "--style-id", "a", "--style-id=b"])), Err(ConfigError::StyleIdFlag { reason: "repeated" })));
        for bad in ["", ".h", "a/b", "a b", "..", "a\\b", "a\tb"] { assert!(take_style_id_flag(&a(&["bin", "--style-id", bad])).is_err(), "{bad:?}"); }
        let mut i = input(); i.style_id = String::new();
        assert_eq!(RunConfig::new(i, ctx(2.0)), Err(ConfigError::EmptyField { field: "style_id" }));
    }
    #[test]
    fn glyph_row_codepoint_token_accepts_scalar_or_ligature_sequence() {
        assert_eq!(parse_glyph_row_codepoints("0x52").unwrap(), vec![0x52]);
        assert_eq!(parse_glyph_row_codepoints("52").unwrap(), vec![0x52]);
        assert_eq!(parse_glyph_row_codepoints("0x0066_0069").unwrap(), vec![0x66, 0x69]);
        assert_eq!(parse_glyph_row_codepoints("0x0066_0x0066_0x006C").unwrap(), vec![0x66, 0x66, 0x6C]);
        assert_eq!(parse_glyph_row_codepoints("1_2_3_4_5_6_7_8").unwrap(), vec![1, 2, 3, 4, 5, 6, 7, 8]);
        for bad in ["", "0x", "0x66_", "_0x66", "0x66__0x69", "0xGG", "1_2_3_4_5_6_7_8_9", "0x66 0x69"] {
            assert_eq!(parse_glyph_row_codepoints(bad), Err(GlyphRowRefusal::CodepointSyntax), "{bad:?}");
        }
        assert_eq!(parse_glyph_row_codepoints("0x66_0xD800"), Err(GlyphRowRefusal::CodepointNotScalar));
        assert_eq!(parse_glyph_row_codepoints("0x110000"), Err(GlyphRowRefusal::CodepointNotScalar));
    }
    #[test]
    fn style_id_flag_normalizes_accented_latin_letters_to_the_shared_file_safe_form() {
        let a = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        let id = |v: &str| take_style_id_flag(&a(&["bin", "m", "o", "--style-id", v])).map(|(id, _)| id);
        // the reported case: L\u{00FF}no style ids normalize instead of being refused
        assert_eq!(id("L\u{00FF}no-Stan").unwrap(), "Lyno-Stan");
        assert_eq!(id("L\u{00FF}no-Jean").unwrap(), "Lyno-Jean");
        // already-safe ids are kept verbatim (idempotent)
        for safe in ["Lyno-Stan", "marq-alt", "MCAU-3U1.5", "x_1"] { assert_eq!(id(safe).unwrap(), safe); }
        // normalization matches the PostScript derivation exactly (same transliteration table)
        for label in ["L\u{00FF}no/Stan", "Mona Alt/Regular"] {
            let d = derive_names(label).unwrap();
            let slug = format!("{}-{}", d.family.replace(' ', ""), d.subfamily.replace(' ', ""));
            assert_eq!(id(&slug).unwrap(), d.postscript_name, "{label}");
        }
        // a combining mark directly after a letter is dropped (decomposed input, same narrow policy as derive_names)
        assert_eq!(id("Ly\u{0308}no-Stan").unwrap(), "Lyno-Stan");
        // every other refusal stands: separators, spaces, leading dot, stray mark, unmappable characters, empty
        for bad in ["a/b", "a b", ".hidden", "\u{0308}ab", "\u{0416}no", "\u{00E6}sop", "", ".."] { assert!(id(bad).is_err(), "{bad:?}"); }
        // the normalized result is always itself a valid style id
        assert_eq!(normalize_style_id(&normalize_style_id("L\u{00FF}no-Walt").unwrap()).unwrap(), "Lyno-Walt");
    }
    #[test]
    fn style_id_names_receipt_and_otf_and_parallel_runs_do_not_cross_write() {
        let mk = |id: &str| { let mut i = input(); i.style_id = id.to_string(); RunConfig::new(i, ctx(2.0)).unwrap() };
        let (a, b) = (mk("style-a"), mk("style-b"));
        assert_eq!((a.otf_file_name().as_str(), a.receipt_file_name().as_str()), ("font-style-a.otf", "receipt-style-a.txt"));
        assert_ne!(a.canonical_record(), b.canonical_record());
        assert!(a.receipt_rows().iter().any(|r| r.starts_with("run_config\tstyle_id\tstyle-a\t")));
        assert_ne!(a.receipt_rows(), b.receipt_rows());
        let dir = unique_dir("styles"); std::fs::create_dir_all(&dir).unwrap();
        let hs: Vec<_> = [a, b].into_iter().map(|c| { let d = dir.clone(); std::thread::spawn(move || {
            let receipt: String = c.receipt_rows().concat();
            std::fs::write(d.join(c.receipt_file_name()), &receipt).unwrap();
            std::fs::write(d.join(c.otf_file_name()), c.style_id().as_bytes()).unwrap();
            (c.style_id().to_string(), receipt)
        }) }).collect();
        for h in hs {
            let (id, receipt) = h.join().unwrap();
            assert_eq!(std::fs::read_to_string(dir.join(format!("receipt-{id}.txt"))).unwrap(), receipt);
            assert_eq!(std::fs::read(dir.join(format!("font-{id}.otf"))).unwrap(), id.as_bytes());
            assert!(receipt.contains(&format!("style_id\t{id}\t")) && !receipt.contains(if id == "style-a" { "style-b" } else { "style-a" }));
        }
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 4);
        let _ = std::fs::remove_dir_all(&dir);
    }
}


