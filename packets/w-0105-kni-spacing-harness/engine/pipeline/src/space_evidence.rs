//! Space evidence wiring: manifest -> measurement -> ctx -> assembly.
//!
//! The space advance is never typed into a manifest as a number when it is
//! measured: the manifest points at a pinned space-evidence spec file, the
//! spec names the HsH (and HHH) source tiles with their sha256 pins, the
//! capture shaping record, kern evidence, and scale binding, and
//! `kni_metrics::space_measurement` does the measurement. This module owns
//! spec parsing, tile loading with pin checks, the full-refusal / partial
//! marker gate, and the emitted==measurement and pair invariants.
//!
//! Manifest row (one row, every field required, no defaults):
//!   space_evidence <spec-path> <spec_sha256> <max_input_bytes> <max_pixels> <max_working_bytes>
//! The spec is refused unless its bytes hash to `spec_sha256`; every file read
//! is size-bounded by `max_input_bytes`; decode limits come from the row.
//!
//! Spec file (one `key value...` row per line, `#` comments, no spaces inside
//! a value). Evidence rows carry their own `f=<style_id>/<frame_id>` token so a
//! cross-source frame conflict reaches the measurement instead of being hidden
//! by one copied declaration:
//!   cp <hex>                                      Unicode scalar U+0020 only
//!   style_id <id>
//!   frame_id <id>
//!   hsh_tile f=<s>/<f> <path> <identity_ref> <sha256>
//!   hhh_tile f=<s>/<f> <path> <identity_ref> <sha256>
//!   hh_kern f=<s>/<f> zero <ref> | known <px> <ref>
//!   hsh_kern f=<s>/<f> zero <ref> | known <sum_px> <ref>
//!   hh_explicit f=<s>/<f> <lsb_px> <rsb_px> <ref>
//!   shaping f=<s>/<f> <settings_ref> <ligatures_disabled> <letter_spacing_px> <sha256[,..]>
//!   scale_record f=<s>/<f> <path> <sha256>        calibration record, see below
//!   sidebearing_policy allow_negative|require_nonnegative   (default allow_negative)
//! Scale record file: rows `style_id`, `frame_id`, `units_per_px`,
//! `calibration_source_sha256`, `method`. The scale gets status PinnedConsistent only
//! when the record bytes hash to the pinned sha, its style/frame equal the
//! request, `units_per_px` is bit-equal to the manifest `scale`, and
//! `calibration_source_sha256` is one of the loaded HsH/HHH tile shas. The
//! calibration method itself is recorded, not re-derived here.
//! A missing evidence row reaches the measurement as typed missing evidence. A
//! malformed or duplicate row, a pin mismatch, or a conflicting record is a
//! hard error.

use kni_metrics::plane::GrayImage;
use kni_metrics::space_measurement::{
    CaptureShapingEvidence, HhKernEvidence, HhSpacingEvidence, HsHKernEvidence, ScaleEvidence,
    measure_space_slope, ScaleConsistencyProof, ScaleStatus, SlopeKernEvidence, SlopeTile, SpaceSlopeMeasurement, SpaceSlopeRequest, SourceFrame, SourceTile, SpaceError, SpaceMeasurement, SpaceOutcome,
    SpaceRequest, LEDGER_HEADER,
};
use std::io::Read;
use std::path::{Path, PathBuf};

pub const WIRING_ID: &str = "kni-space-evidence-wiring/v2";

/// Explicit read limits carried by the manifest row. No defaults.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReadLimits {
    pub max_input_bytes: usize,
    pub max_pixels: usize,
    pub max_working_bytes: usize,
}

/// The manifest row: pinned spec + limits.
#[derive(Debug, Clone, PartialEq)]
pub struct SpaceEvidenceRef {
    pub path: PathBuf,
    pub sha256: String,
    pub limits: ReadLimits,
}

fn is_sha(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn tok_usize(err: &dyn Fn(&str) -> String, what: &str, v: Option<&str>) -> Result<usize, String> {
    let n: usize = v.ok_or_else(|| err(&format!("{what} missing")))?.parse().map_err(|_| err(&format!("bad {what}")))?;
    if n == 0 {
        return Err(err(&format!("{what} must be > 0")));
    }
    Ok(n)
}

impl SpaceEvidenceRef {
    /// Parse the tokens after the `space_evidence` key. `err` adds position.
    pub fn from_tokens(base: &Path, it: &mut std::str::SplitWhitespace, err: &dyn Fn(&str) -> String) -> Result<Self, String> {
        let path = it.next().ok_or_else(|| err("space_evidence spec path missing"))?;
        let sha = it.next().ok_or_else(|| err("space_evidence spec sha256 missing"))?.to_string();
        if !is_sha(&sha) {
            return Err(err("space_evidence spec sha256 must be 64 lowercase hex"));
        }
        let max_input_bytes = tok_usize(err, "max_input_bytes", it.next())?;
        let max_pixels = tok_usize(err, "max_pixels", it.next())?;
        let max_working_bytes = tok_usize(err, "max_working_bytes", it.next())?;
        Ok(SpaceEvidenceRef {
            path: base.join(path),
            sha256: sha,
            limits: ReadLimits { max_input_bytes, max_pixels, max_working_bytes },
        })
    }
}

/// U+0020 is the only codepoint the `space` glyph may map to: it must be a
/// Unicode scalar value, nonzero, and the space character itself.
pub fn validate_space_cp(cp: u32) -> Result<(), String> {
    if cp == 0 {
        return Err("space codepoint 0 is reserved".into());
    }
    match char::from_u32(cp) {
        None => Err(format!("space codepoint {cp:#x} is not a Unicode scalar value")),
        Some(' ') => Ok(()),
        Some(_) => Err(format!("space codepoint {cp:#x} is not U+0020; the `space` glyph cannot map to an arbitrary codepoint")),
    }
}

use crate::space_spec::*;

fn num(err: &dyn Fn(&str) -> String, what: &str, v: Option<&str>) -> Result<f64, String> {
    let x: f64 = v.ok_or_else(|| err(&format!("{what} missing")))?.parse().map_err(|_| err(&format!("bad {what}")))?;
    if !x.is_finite() {
        return Err(err(&format!("{what} must be finite")));
    }
    Ok(x)
}

/// Parsed scale record file.
struct ScaleRecord {
    style_id: String,
    frame_id: String,
    units_per_px: f64,
    calibration_source_sha256: String,
    method: String,
}

fn parse_scale_record(text: &str) -> Result<ScaleRecord, String> {
    let (mut style, mut frame, mut upp, mut src, mut method) = (None, None, None, None, None);
    for (ln, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let err = |m: &str| format!("scale record line {}: {}", ln + 1, m);
        let mut it = line.split_whitespace();
        let key = it.next().unwrap_or("");
        let slot_dup = |o: bool| if o { Err(err(&format!("duplicate row {key}"))) } else { Ok(()) };
        match key {
            "style_id" => { slot_dup(style.is_some())?; style = Some(it.next().ok_or_else(|| err("value missing"))?.to_string()); }
            "frame_id" => { slot_dup(frame.is_some())?; frame = Some(it.next().ok_or_else(|| err("value missing"))?.to_string()); }
            "units_per_px" => { slot_dup(upp.is_some())?; upp = Some(num(&err, "units_per_px", it.next())?); }
            "calibration_source_sha256" => {
                slot_dup(src.is_some())?;
                let v = it.next().ok_or_else(|| err("value missing"))?.to_string();
                if !is_sha(&v) { return Err(err("calibration_source_sha256 must be 64 lowercase hex")); }
                src = Some(v);
            }
            "method" => { slot_dup(method.is_some())?; method = Some(it.next().ok_or_else(|| err("value missing"))?.to_string()); }
            other => return Err(err(&format!("unknown row {other}"))),
        }
        if it.next().is_some() {
            return Err(err("unexpected extra field"));
        }
    }
    Ok(ScaleRecord {
        style_id: style.ok_or("scale record: style_id missing")?,
        frame_id: frame.ok_or("scale record: frame_id missing")?,
        units_per_px: upp.ok_or("scale record: units_per_px missing")?,
        calibration_source_sha256: src.ok_or("scale record: calibration_source_sha256 missing")?,
        method: method.ok_or("scale record: method missing")?,
    })
}

/// Result of resolving the space evidence for one run.
#[derive(Debug, Clone)]
pub struct SpaceResolution {
    pub codepoint: u32,
    pub outcome: SpaceOutcome,
    pub spec_sha256: String,
    pub manifest_scale: f64,
    /// One record per distinct input (by sha256) actually decoded by `resolve_file`,
    /// carrying the receipt of the decoder that really ran. Empty when decode was an
    /// injected closure (unit tests): nothing is claimed.
    pub decodes: Vec<DecodeRecord>,
    /// Slope route numbers (slope, residuals, status), kept even when not exportable.
    pub slope: Option<SpaceSlopeMeasurement>,
}

/// Which decoder handled one input and what it reported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeKind {
    /// Shared bounded PNG adapter; `line` is the adapter's own rendered receipt.
    PngAdapter { line: String },
    /// JPEG through `decode_source` with the manifest row's limits. No PNG adapter,
    /// no PNG budget/CRC claim.
    Jpeg { limits: ReadLimits, origin: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodeRecord {
    pub input_sha256: String,
    pub kind: DecodeKind,
}
impl DecodeRecord {
    pub fn line(&self) -> String {
        match &self.kind {
            DecodeKind::PngAdapter { line } => {
                format!("space_evidence\tdecode\tinput_sha256\t{}\tkind\tpng_bounded_adapter\t{}\n", self.input_sha256, line)
            }
            DecodeKind::Jpeg { limits, origin } => format!(
                "space_evidence\tdecode\tinput_sha256\t{}\tkind\tjpeg_decode_source\tmax_input_bytes\t{}\tmax_pixels\t{}\tmax_working_bytes\t{}\torigin\t{}\tpng_adapter\tnot_used\n",
                self.input_sha256, limits.max_input_bytes, limits.max_pixels, limits.max_working_bytes, origin
            ),
        }
    }
}

impl SpaceResolution {
    #[allow(dead_code)] // exercised by the test suite; no production caller wired yet
    pub fn measurement(&self) -> Option<&SpaceMeasurement> {
        match &self.outcome {
            SpaceOutcome::Measured(m) => Some(m),
            SpaceOutcome::SlopeMeasured(_) | SpaceOutcome::MissingEvidence(_) => None,
        }
    }

    pub fn receipt_lines(&self) -> String {
        let mut s = format!(
            "space_evidence\twiring\t{WIRING_ID}\tspec_sha256\t{}\tcp\t{:#x}\tmanifest_scale\t{}\n",
            self.spec_sha256, self.codepoint, self.manifest_scale
        );
        if self.decodes.is_empty() {
            s.push_str("space_evidence\tdecode\tnone\t(no decode receipt recorded in this resolution)\n");
        }
        for d in &self.decodes {
            s.push_str(&d.line());
        }
        match &self.outcome {
            SpaceOutcome::Measured(m) => s.push_str(&format!(
                "space_evidence\tstatus\tmeasured\thsh_tile_sha256\t{}\thhh_tile_sha256\t{}\tspace_advance_px\t{}\tspace_advance_units\t{}\tscale_status\t{}\t(consistency of pinned records, not an independent calibration)\tmodule\t{}\n",
                m.hsh_tile_sha256, m.hhh_tile_sha256, m.space_advance_px_slope, m.space_advance_units, m.scale_status, m.module
            )),
            SpaceOutcome::SlopeMeasured(m) => s.push_str(&format!(
                "space_evidence\tstatus\tmeasured_slope\trepresentative_units\t{}\t{}\tmodule\t{}\t(a selected value inside the interval; scale is a consistency claim, not independent calibration)\n",
                m.space_advance_units, m.uncertainty_line(), m.module
            )),
            SpaceOutcome::MissingEvidence(e) => s.push_str(&format!(
                "space_evidence\tstatus\tSpaceMissingEvidence\treason\t{}\n",
                e.to_string().replace(['\t', '\n', '\r'], " ")
            )),
        }
        if let Some(m) = &self.slope {
            s.push_str(&format!(
                "space_evidence\tslope\tspaces\t{:?}\ttile_sha256\t{}\tgaps_px\t{:?}\tincrements_per_space_px\t{:?}\tols_slope_px_descriptive\t{}\tols_residuals_px\t{:?}\tols_max_abs_residual_px\t{}\th_width_deviation_px\t{}\tstatus\t{:?}\n",
                m.spaces, m.tile_sha256.join(","), m.gaps_px, m.increments_per_space_px, m.slope_px, m.residuals_px, m.max_abs_residual_px, m.h_width_deviation_px, m.status
            ));
        }
        s
    }

    /// Ledger file body: header + one row (Measured) or header + a status comment.
    #[allow(dead_code)] // exercised by the test suite; no production caller wired yet
    pub fn ledger_tsv(&self) -> String {
        let mut s = String::from(LEDGER_HEADER);
        s.push('\n');
        match &self.outcome {
            SpaceOutcome::Measured(m) => {
                s.push_str(&m.ledger_row());
                s.push('\n');
            }
            SpaceOutcome::SlopeMeasured(m) => {
                s.push_str(&format!("# slope route {}: spaces {:?} gaps_px {:?} slope_px {} units {}\n", m.module, m.spaces, m.gaps_px, m.slope_px, m.space_advance_units));
            }
            SpaceOutcome::MissingEvidence(e) => {
                s.push_str(&format!("# SpaceMissingEvidence: {}\n", e.to_string().replace(['\t', '\n', '\r'], " ")));
            }
        }
        s
    }
}

/// Injected IO so the logic is testable: bounded byte read, decode, sha.
pub struct Io<'a> {
    pub load: &'a (dyn Fn(&Path, usize) -> Result<Vec<u8>, String> + Send + Sync),
    /// Second argument: bytes of decoder scratch+output this call may use (what is left of the request budget).
    /// Returns the decoded image plus the decode provenance record (None from injected test closures).
    pub decode: &'a (dyn Fn(&[u8], usize) -> Result<(GrayImage, Option<DecodeRecord>), String> + Send + Sync),
    pub sha: &'a (dyn Fn(&[u8]) -> String + Send + Sync),
}

/// Request-wide decoded-byte budget: every decoded image that is retained is charged
/// against `limits.max_working_bytes`; the input bytes held during a decode and the
/// decoder's own scratch must fit in what is left.
fn load_tile(t: &TileSpec, io: &Io, max: usize, budget: &mut usize) -> Result<(SourceTile, Option<DecodeRecord>), String> {
    let bytes = (io.load)(&t.path, max.min(*budget))?;
    let left = budget
        .checked_sub(bytes.len())
        .ok_or_else(|| format!("space tile {}: input {} bytes exceed the remaining max_working_bytes budget {}", t.path.display(), bytes.len(), budget))?;
    let got = (io.sha)(&bytes);
    if got != t.sha256 {
        return Err(format!("space tile {}: sha256 pin mismatch (declared {}, actual {})", t.path.display(), t.sha256, got));
    }
    let (image, record) = (io.decode)(&bytes, left).map_err(|e| format!("space tile {}: {e}", t.path.display()))?;
    if image.px.len() > left {
        return Err(format!("space tile {}: decoded {} bytes exceed the remaining max_working_bytes budget {}", t.path.display(), image.px.len(), left));
    }
    *budget -= image.px.len();
    Ok((SourceTile {
        source_sha256: got,
        frame: Some(t.frame.clone()),
        glyph_identity_ref: t.identity_ref.clone(),
        image,
    }, record))
}

/// Everything about one loaded tile that does not depend on the request
/// budget, so workers can produce it in parallel; the budget is applied
/// afterwards, in manifest order, by the sequential reduce below.
struct TileParts {
    frame: SourceFrame,
    identity_ref: String,
    source_sha256: String,
    bytes_len: usize,
    image: GrayImage,
    record: Option<DecodeRecord>,
}

fn load_tile_parts(t: &TileSpec, io: &Io, load_cap: usize, decode_rem: usize) -> Result<TileParts, String> {
    let bytes = (io.load)(&t.path, load_cap)?;
    let got = (io.sha)(&bytes);
    if got != t.sha256 {
        return Err(format!("space tile {}: sha256 pin mismatch (declared {}, actual {})", t.path.display(), t.sha256, got));
    }
    let (image, record) = (io.decode)(&bytes, decode_rem).map_err(|e| format!("space tile {}: {e}", t.path.display()))?;
    Ok(TileParts { frame: t.frame.clone(), identity_ref: t.identity_ref.clone(), source_sha256: got, bytes_len: bytes.len(), image, record })
}

/// Tiles loaded for one request, in manifest order, with the remaining
/// budget and the deduplicated decode records (first occurrence wins, in
/// tile order - the exact order the old sequential loop collected them).
/// assemble_loaded leaves `records` empty; both drivers fill it in order.
struct LoadedEvidenceTiles {
    hsh: Option<SourceTile>,
    slopes: Vec<SlopeTile>,
    hhh: Option<SourceTile>,
    tile_shas: Vec<String>,
    records: Vec<DecodeRecord>,
    budget_left: usize,
}

fn assemble_loaded(
    spec: &Spec,
    parts: Vec<TileParts>,
    budget_left: usize,
) -> LoadedEvidenceTiles {
    let mut it = parts.into_iter();
    let hsh = spec.hsh.as_ref().map(|_| {
        let p = it.next().expect("hsh parts");
        SourceTile { source_sha256: p.source_sha256, frame: Some(p.frame), glyph_identity_ref: p.identity_ref, image: p.image }
    });
    let mut tile_shas: Vec<String> = hsh.iter().map(|t| t.source_sha256.clone()).collect();
    let mut slopes: Vec<SlopeTile> = Vec::new();
    for st in &spec.slope_tiles {
        let p = it.next().expect("slope parts");
        tile_shas.push(p.source_sha256.clone());
        slopes.push(SlopeTile {
            spaces: st.spaces,
            tile: SourceTile { source_sha256: p.source_sha256, frame: Some(p.frame), glyph_identity_ref: p.identity_ref, image: p.image },
            submitted_text_ref: st.submitted_text_ref.clone(),
        });
    }
    let hhh = spec.hhh.as_ref().map(|_| {
        let p = it.next().expect("hhh parts");
        tile_shas.push(p.source_sha256.clone());
        SourceTile { source_sha256: p.source_sha256, frame: Some(p.frame), glyph_identity_ref: p.identity_ref, image: p.image }
    });
    debug_assert!(it.next().is_none());
    LoadedEvidenceTiles { hsh, slopes, hhh, tile_shas, records: Vec::new(), budget_left }
}

/// The old serial loop, kept verbatim as the jobs=1 driver and as the exact
/// fallback whenever the speculative parallel attempt cannot prove the
/// sequential run would have behaved identically.
fn load_tiles_sequential(spec: &Spec, io: &Io, max: usize, budget: usize) -> Result<LoadedEvidenceTiles, String> {
    let mut budget = budget;
    let mut records: Vec<DecodeRecord> = Vec::new();
    let hsh = match &spec.hsh {
        Some(t) => {
            let (tile, rec) = load_tile(t, io, max, &mut budget)?;
            if let Some(r) = rec { if !records.iter().any(|x| x.input_sha256 == r.input_sha256) { records.push(r); } }
            Some(tile)
        }
        None => None,
    };
    let mut tile_shas: Vec<String> = hsh.iter().map(|t| t.source_sha256.clone()).collect();
    let mut slopes: Vec<SlopeTile> = Vec::new();
    for st in &spec.slope_tiles {
        let (tile, rec) = load_tile(&st.tile, io, max, &mut budget)?;
        if let Some(r) = rec { if !records.iter().any(|x| x.input_sha256 == r.input_sha256) { records.push(r); } }
        tile_shas.push(tile.source_sha256.clone());
        slopes.push(SlopeTile { spaces: st.spaces, tile, submitted_text_ref: st.submitted_text_ref.clone() });
    }
    let hhh = match &spec.hhh {
        Some(t) => {
            let (tile, rec) = load_tile(t, io, max, &mut budget)?;
            if let Some(r) = rec { if !records.iter().any(|x| x.input_sha256 == r.input_sha256) { records.push(r); } }
            tile_shas.push(tile.source_sha256.clone());
            Some(tile)
        }
        None => None,
    };
    Ok(LoadedEvidenceTiles { hsh, slopes, hhh, tile_shas, records, budget_left: budget })
}

/// Would the decoder's own working-bytes refusal have fired with `rem` as the
/// remaining budget? Exact for JPEG (same formula the decoder enforces,
/// exposed as jpeg_source::working_budget_required); a conservative upper
/// bound for the PNG adapter peak (IDAT copy <= input bytes, worst-case
/// 4-channel stride), so a "might exceed" only ever costs a sequential
/// re-run, never a changed result.
fn decode_budget_might_exceed(p: &TileParts, rem: usize, lim: &ReadLimits) -> bool {
    let cap = lim.max_working_bytes.min(rem);
    let jpeg_needed = kni_core::jpeg_source::working_budget_required(p.bytes_len, lim.max_pixels).unwrap_or(usize::MAX);
    let w = p.image.width as usize;
    let h = p.image.height as usize;
    let stride_ub = w.saturating_mul(4);
    let png_ub = p.bytes_len
        .saturating_add(h.saturating_mul(stride_ub.saturating_add(1)))
        .saturating_add(h.saturating_mul(stride_ub))
        .saturating_add(w.saturating_mul(h));
    let needed = match &p.record {
        Some(r) if matches!(r.kind, DecodeKind::Jpeg { .. }) => jpeg_needed,
        Some(r) if matches!(r.kind, DecodeKind::PngAdapter { .. }) => png_ub,
        _ => jpeg_needed.max(png_ub),
    };
    needed > cap
}

/// Speculative parallel load: every tile is read, pinned and decoded on a
/// worker pool of exactly `jobs` threads against the FULL request budget,
/// then the sequential budget accounting is replayed in manifest order.
/// Returns None on ANY deviation (io/sha/decode error, or a budget check the
/// sequential loop could have refused on); the caller then re-runs the
/// sequential loader, which produces the exact sequential outcome. When this
/// returns Some, every check the sequential loop performs has been verified
/// to pass with the sequential budget values, and a bounded decoder's output
/// on success is input-deterministic, so the result is bit-identical.
fn load_tiles_parallel(spec: &Spec, io: &Io, max: usize, budget: usize, lim: &ReadLimits, jobs: usize) -> Option<LoadedEvidenceTiles> {
    let mut specs: Vec<&TileSpec> = Vec::new();
    if let Some(t) = &spec.hsh { specs.push(t); }
    specs.extend(spec.slope_tiles.iter().map(|s| &s.tile));
    if let Some(t) = &spec.hhh { specs.push(t); }
    if specs.len() < 2 || jobs <= 1 { return None; }
    let results: Vec<Result<TileParts, String>> = {
        use rayon::prelude::*;
        let pool = rayon::ThreadPoolBuilder::new().num_threads(jobs).build().ok()?;
        pool.install(|| specs.par_iter().map(|t| load_tile_parts(t, io, max.min(budget), budget)).collect())
    };
    let mut left = budget;
    let mut parts_ok: Vec<TileParts> = Vec::with_capacity(specs.len());
    for r in results {
        let p = r.ok()?;
        if p.bytes_len > max.min(left) { return None; }
        let rem = left - p.bytes_len;
        if decode_budget_might_exceed(&p, rem, lim) { return None; }
        if p.image.px.len() > rem { return None; }
        left -= p.image.px.len();
        parts_ok.push(p);
    }
    // Recompute records here: assemble_loaded drops them for the borrow
    // checker; merge in manifest order with the first-wins dedup.
    let mut records: Vec<DecodeRecord> = Vec::new();
    let mut kept: Vec<TileParts> = Vec::with_capacity(parts_ok.len());
    for p in parts_ok {
        if let Some(r) = &p.record {
            if !records.iter().any(|x| x.input_sha256 == r.input_sha256) { records.push(r.clone()); }
        }
        kept.push(p);
    }
    let mut loaded = assemble_loaded(spec, kept, left);
    loaded.records = records;
    Some(loaded)
}

fn hh_kern_ev(k: &KernSpec) -> HhKernEvidence {
    match k {
        KernSpec::Zero { frame, evidence_ref } => HhKernEvidence::ZeroVerified { frame: Some(frame.clone()), evidence_ref: evidence_ref.clone() },
        KernSpec::Known { frame, px, evidence_ref } => HhKernEvidence::KnownPx { frame: Some(frame.clone()), kern_px: *px, evidence_ref: evidence_ref.clone() },
    }
}

fn hsh_kern_ev(k: &KernSpec) -> HsHKernEvidence {
    match k {
        KernSpec::Zero { frame, evidence_ref } => HsHKernEvidence::ZeroVerified { frame: Some(frame.clone()), evidence_ref: evidence_ref.clone() },
        KernSpec::Known { frame, px, evidence_ref } => HsHKernEvidence::KnownSumPx { frame: Some(frame.clone()), sum_px: *px, evidence_ref: evidence_ref.clone() },
    }
}

/// Validate the pinned scale record against the request. Returns the
/// `ScaleEvidence` (PinnedConsistent only after every check; NOT an independent
/// calibration: units_per_px and method are the record's own claims, checked
/// for consistency with the manifest, style/frame and a loaded tile) or a hard error.
fn scale_from_record(
    rec: &ScaleRecordSpec,
    request_frame: &SourceFrame,
    manifest_scale: f64,
    tile_shas: &[String],
    io: &Io,
    max: usize,
) -> Result<ScaleEvidence, String> {
    let bytes = (io.load)(&rec.path, max)?;
    let got = (io.sha)(&bytes);
    if got != rec.sha256 {
        return Err(format!("scale record {}: sha256 pin mismatch (declared {}, actual {})", rec.path.display(), rec.sha256, got));
    }
    let text = std::str::from_utf8(&bytes).map_err(|_| "scale record: not UTF-8".to_string())?;
    let r = parse_scale_record(text)?;
    let record_frame = SourceFrame { style_id: r.style_id.clone(), frame_id: r.frame_id.clone() };
    let proof = ScaleConsistencyProof::check(
        &rec.sha256, &got, &record_frame, request_frame, r.units_per_px, manifest_scale, &r.calibration_source_sha256, tile_shas,
    )
    .map_err(|e| format!("scale record {}: {e:?}", rec.path.display()))?;
    Ok(ScaleEvidence {
        style_id: r.style_id,
        units_per_px: manifest_scale,
        evidence_ref: format!("scale_record:{}:method:{}:source:{}", got, r.method, r.calibration_source_sha256),
        status: ScaleStatus::PinnedConsistent(proof),
    })
}

/// Build the request and measure. `spec_sha_expected` pins the spec bytes.
#[allow(dead_code)] // exercised by the test suite; no production caller wired yet
pub fn resolve_with(
    spec_text: &str,
    spec_sha_expected: &str,
    base: &Path,
    manifest_scale: f64,
    limits: ReadLimits,
    io: &Io,
) -> Result<SpaceResolution, String> {
    resolve_with_jobs(spec_text, spec_sha_expected, base, manifest_scale, limits, io, 1)
}

/// Jobs-capped variant: tile reads, pin checks and decodes run on a worker
/// pool of exactly `jobs` threads (`jobs <= 1` is the old serial loop). The
/// parallel driver is speculative: it only keeps its result when the
/// sequential budget accounting, replayed in manifest order, proves the
/// serial loop would have behaved identically; otherwise it falls back to
/// that loop, so the resolution (tiles, records, errors) is bit-identical
/// for any worker count (oracle: parallel_tile_loading_* tests).
pub fn resolve_with_jobs(
    spec_text: &str,
    spec_sha_expected: &str,
    base: &Path,
    manifest_scale: f64,
    limits: ReadLimits,
    io: &Io,
    jobs: usize,
) -> Result<SpaceResolution, String> {
    let spec_sha = (io.sha)(spec_text.as_bytes());
    if spec_sha != spec_sha_expected {
        return Err(format!("space evidence spec sha256 pin mismatch (manifest {spec_sha_expected}, actual {spec_sha})"));
    }
    let spec = parse_spec(spec_text, base)?;
    let frame = SourceFrame { style_id: spec.style_id.clone(), frame_id: spec.frame_id.clone() };
    let max = limits.max_input_bytes;
    // Slope route: limits are checked before ANY io or decode.
    if !spec.slope_tiles.is_empty() {
        let mp = spec.slope_max_points.ok_or("space evidence spec: slope_tile rows need slope_max_points (limit missing; refused before any read)")?;
        if spec.slope_tiles.len() > mp {
            return Err(format!("space evidence spec: {} slope_tile rows exceed slope_max_points {mp}; refused before any read", spec.slope_tiles.len()));
        }
    }
    let loaded = if jobs > 1 {
        match load_tiles_parallel(&spec, io, max, limits.max_working_bytes, &limits, jobs) {
            Some(l) => l,
            None => load_tiles_sequential(&spec, io, max, limits.max_working_bytes)?,
        }
    } else {
        load_tiles_sequential(&spec, io, max, limits.max_working_bytes)?
    };
    let LoadedEvidenceTiles { hsh: hsh_tile, slopes: slope_tiles, hhh: hhh_tile, tile_shas, records, budget_left: budget } = loaded;
    let hh_spacing = if let Some(tile) = hhh_tile {
        let kern = match &spec.hh_kern {
            Some(k) => hh_kern_ev(k),
            None => HhKernEvidence::Unverified,
        };
        Some(HhSpacingEvidence::HhhTile { tile, kern })
    } else if let Some((f, l, r, rf)) = &spec.hh_explicit {
        Some(HhSpacingEvidence::Explicit { frame: Some(f.clone()), lsb_px: *l, rsb_px: *r, evidence_ref: rf.clone() })
    } else {
        None
    };
    let hsh_kern = spec.hsh_kern.as_ref().map(hsh_kern_ev);
    let capture_shaping = spec.shaping.as_ref().map(|s| CaptureShapingEvidence {
        frame: Some(s.frame.clone()),
        settings_ref: s.settings_ref.clone(),
        ligatures_disabled: s.ligatures_disabled,
        letter_spacing_px: s.letter_spacing_px,
        covers_tile_sha256: s.covers.clone(),
    });
    // Scale: PinnedConsistent only through a pinned scale record that agrees
    // with the request; a self-declared flag is never accepted. No record ->
    // explicitly unvalidated (typed ScaleNotPinnedConsistent downstream).
    let scale = Some(match &spec.scale_record {
        Some(rec) => {
            if rec.frame != frame {
                return Err(format!(
                    "scale_record row frame {}/{} != request frame {}/{}",
                    rec.frame.style_id, rec.frame.frame_id, frame.style_id, frame.frame_id
                ));
            }
            scale_from_record(rec, &frame, manifest_scale, &tile_shas, io, max.min(budget))?
        }
        None => ScaleEvidence {
            style_id: spec.style_id.clone(),
            units_per_px: manifest_scale,
            evidence_ref: "manifest-scale-without-calibration-record".into(),
            status: ScaleStatus::Unverified,
        },
    });
    if !slope_tiles.is_empty() {
        let sreq = SpaceSlopeRequest {
            frame,
            tiles: slope_tiles,
            kern: Some(match &spec.slope_kern {
                Some(KernSpec::Zero { frame, evidence_ref }) => SlopeKernEvidence::ZeroVerifiedAllSpacePairs { frame: Some(frame.clone()), evidence_ref: evidence_ref.clone() },
                _ => SlopeKernEvidence::Unverified,
            }),
            capture_shaping,
            scale,
            edge_contract: spec.renderer_contract.clone(),
            ink: spec.ink.clone(),
            max_points: spec.slope_max_points,
        };
        let measured = measure_space_slope(&sreq);
        let descriptive = measured.as_ref().ok().cloned();
        return Ok(SpaceResolution {
            codepoint: spec.codepoint,
            outcome: SpaceOutcome::from_slope_result(measured),
            spec_sha256: spec_sha,
            manifest_scale,
            decodes: records,
            slope: descriptive,
        });
    }
    let req = SpaceRequest {
        frame,
        hsh_tile,
        hh_spacing,
        hsh_kern,
        capture_shaping,
        scale,
        sidebearing_policy: spec.policy,
    };
    Ok(SpaceResolution {
        codepoint: spec.codepoint,
        outcome: SpaceOutcome::from_request(&req),
        spec_sha256: spec_sha,
        manifest_scale,
        decodes: records,
        slope: None,
    })
}

/// Size-bounded file read: refuses before reading when metadata says too big
/// and never reads past the bound.
pub fn read_bounded(path: &Path, max: usize) -> Result<Vec<u8>, String> {
    let md = std::fs::metadata(path).map_err(|e| format!("stat {}: {e}", path.display()))?;
    if !md.is_file() {
        return Err(format!("{}: not a regular file", path.display()));
    }
    let max_u64 = u64::try_from(max).map_err(|_| "limit range".to_string())?;
    if md.len() > max_u64 {
        return Err(format!("{}: {} bytes exceeds max_input_bytes {}", path.display(), md.len(), max));
    }
    let f = std::fs::File::open(path).map_err(|e| format!("open {}: {e}", path.display()))?;
    let mut buf = Vec::new();
    f.take(max_u64.checked_add(1).ok_or("limit overflow")?)
        .read_to_end(&mut buf)
        .map_err(|e| format!("read {}: {e}", path.display()))?;
    if buf.len() > max {
        return Err(format!("{}: grew past max_input_bytes {} while reading", path.display(), max));
    }
    Ok(buf)
}

/// Real-IO resolve used by the pipeline. All limits come from the manifest row.
#[allow(dead_code)] // exercised by the test suite; no production caller wired yet
pub fn resolve_file(r: &SpaceEvidenceRef, manifest_scale: f64) -> Result<SpaceResolution, String> {
    resolve_file_jobs(r, manifest_scale, 1)
}

/// Jobs-capped variant: tile decode loops run on a worker pool of exactly
/// `jobs` threads (see resolve_with_jobs for the bit-identity contract).
pub fn resolve_file_jobs(r: &SpaceEvidenceRef, manifest_scale: f64, jobs: usize) -> Result<SpaceResolution, String> {
    let spec_bytes = read_bounded(&r.path, r.limits.max_input_bytes)?;
    let text = String::from_utf8(spec_bytes).map_err(|_| "space evidence spec: not UTF-8".to_string())?;
    let base = r.path.parent().unwrap_or_else(|| Path::new("."));
    let lim = r.limits;
    let jl = kni_core::jpeg_source::Limits {
        max_input_bytes: lim.max_input_bytes,
        max_pixels: lim.max_pixels,
        max_working_bytes: lim.max_working_bytes,
    };
    let png_limits = kni_core::capture::DecodeLimits {
        max_input_bytes: lim.max_input_bytes,
        max_pixels: lim.max_pixels,
        max_working_bytes: lim.max_working_bytes,
    };
    // Decode records are returned per decode call and merged by the loader
    // drivers in tile order (first-wins dedup), so `res.decodes` is identical
    // to the old closure-collected list on every jobs level.
    let io = Io {
        load: &|p, max| read_bounded(p, max),
        decode: &|b, rem| {
            let png_limits = kni_core::capture::DecodeLimits { max_working_bytes: png_limits.max_working_bytes.min(rem), ..png_limits };
            let jl = kni_core::jpeg_source::Limits { max_working_bytes: jl.max_working_bytes.min(rem), ..jl };
            let origin = "manifest space_evidence row".to_string();
            let input_sha = kni_core::cff_reader::sha256_hex(b);
            let (dw, dh, dgray, kind) = if b.starts_with(b"\x89PNG\r\n\x1a\n") {
                let g = kni_core::bounded_png_adapter::decode_gray(
                    kni_core::bounded_png_adapter::Route::Space,
                    b,
                    &png_limits,
                    kni_core::bounded_png_adapter::LimitsOrigin::Explicit(origin),
                )
                .map_err(|e| format!("decode refused: {e:?}"))?;
                let line = g.receipt.render();
                (g.width, g.height, g.gray, DecodeKind::PngAdapter { line })
            } else {
                let d = kni_core::capture_dispatch::decode_source(b, &png_limits, jl).map_err(|e| format!("decode refused: {e:?}"))?;
                (d.width, d.height, d.gray, DecodeKind::Jpeg { limits: lim, origin })
            };
            let w = u32::try_from(dw).map_err(|_| "tile width range".to_string())?;
            let h = u32::try_from(dh).map_err(|_| "tile height range".to_string())?;
            let n = (dw as u64).checked_mul(dh as u64).ok_or("tile pixel count overflow")?;
            if n > lim.max_pixels as u64 {
                return Err("tile exceeds max_pixels".to_string());
            }
            Ok((GrayImage { width: w, height: h, px: dgray }, Some(DecodeRecord { input_sha256: input_sha, kind })))
        },
        sha: &|b| kni_core::cff_reader::sha256_hex(b),
    };
    let mut res = resolve_with_jobs(&text, &r.sha256, base, manifest_scale, lim, &io, jobs)?;
    // Binary pixel-center edge model is a lossless-raster claim: a JPEG-decoded tile
    // cannot carry it, whatever compression_ref says.
    if matches!(res.outcome, SpaceOutcome::SlopeMeasured(_)) && res.decodes.iter().any(|d| matches!(d.kind, DecodeKind::Jpeg { .. })) {
        res.outcome = SpaceOutcome::MissingEvidence(kni_metrics::space_measurement::SpaceError::SlopeNotExportable {
            reason: "a slope tile was decoded from JPEG; the binary pixel-center edge bound does not apply to lossy sources".into(),
        });
    }
    Ok(res)
}

/// Pin/spec mismatches are ignored (evidence unused, no space glyph from
/// evidence, typed status Absent) instead of failing the run. Returns the
/// stable `space_evidence_ignored` code; other errors stay errors.
pub fn ignorable_space_evidence_code(err: &str) -> Option<&'static str> {
    if err.contains("sha256 pin mismatch") { Some("ShaMismatch") }
    else if err.contains("mismatch") { Some("SpecMismatch") }
    else { None }
}

/// What the assembly does with the space.
/// Always-output space derivation (the kit must never die outputless): with
/// no measured and no manifest-declared space, and the manifest key
/// `derive_space_from_letter_advances` present, the space advance is derived
/// from the solved glyphs: (a) the advance of U+006E (n) when present, else
/// (b) the median advance of the present a-z glyphs, else (c) the median
/// advance of all solved glyphs. No hardcoded number; n-first is a declared
/// convention (provenance: the standard type-design starting point for space
/// width is the width of n). Returns (advance_font_units, basis) or None for
/// an empty population (the caller then keeps the established no-space
/// behavior).
pub fn derive_space_advance(glyphs: &[(u32, f64)]) -> Option<(f64, &'static str)> {
    fn median(mut v: Vec<f64>) -> Option<f64> {
        if v.is_empty() { return None; }
        v.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let n = v.len();
        if n % 2 == 1 { Some(v[n / 2]) } else { Some((v[n / 2 - 1] + v[n / 2]) / 2.0) }
    }
    if let Some((_, a)) = glyphs.iter().find(|(cp, _)| *cp == 0x6E) {
        return Some((*a, "n_advance"));
    }
    let lower: Vec<f64> = glyphs.iter().filter(|(cp, _)| (0x61..=0x7A).contains(cp)).map(|(_, a)| *a).collect();
    if let Some(m) = median(lower) { return Some((m, "lowercase_median")); }
    median(glyphs.iter().map(|(_, a)| *a).collect()).map(|m| (m, "all_glyph_median"))
}

/// Always-output derive gate: a measured outcome still ships the measured
/// space (bit-identical to `gate_with_policy`'s Emit); every other outcome
/// defers to the post-solve derivation in the caller and writes NO partial
/// markers and NO refusal. Used only when the manifest declares
/// `derive_space_from_letter_advances` and carries no `space` row; without
/// the key the established `gate`/`gate_with_policy` behavior is untouched.
pub fn gate_for_derive(res: Option<&SpaceResolution>, receipt: &mut String) -> SpaceGate {
    match res {
        Some(r) => {
            receipt.push_str(&r.receipt_lines());
            match &r.outcome {
                SpaceOutcome::Measured(m) => SpaceGate::Emit { codepoint: r.codepoint, advance_units: m.space_advance_units },
                SpaceOutcome::SlopeMeasured(m) => SpaceGate::Emit { codepoint: r.codepoint, advance_units: m.space_advance_units },
                SpaceOutcome::MissingEvidence(_) => SpaceGate::NotRequested,
            }
        }
        None => SpaceGate::NotRequested,
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum SpaceGate {
    /// No space evidence requested: no measured space glyph.
    NotRequested,
    /// Emit the space glyph with this codepoint and advance (font units).
    Emit { codepoint: u32, advance_units: f64 },
    /// Evidence missing, run allowed partial: no space glyph, markers written.
    OmittedPartial,
}

const PARTIAL_LINE: &str = "partial_output\ttrue\treason\tspace_missing_evidence\n";

/// Full refusal unless `allow_partial`; partial writes the explicit markers
/// (including the standard partial_output line, once).
/// Missing-evidence policy for the space gate. `RefuseOnMissing` (the
/// default) is the established behavior: without --allow-partial a missing
/// measurement refuses the run.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SpaceEvidencePolicy {
    /// Established behavior: MissingEvidence without --allow-partial is a
    /// full-run refusal.
    #[default]
    RefuseOnMissing,
    /// Missing evidence no longer refuses the run: the space glyph is
    /// omitted (never substituted), the run is marked partial with a typed
    /// decision row plus the same partial markers an --allow-partial run
    /// carries, and export continues.
    OmitAndContinue,
}

/// Established gate: strict wrapper over `gate_with_policy` with
/// `RefuseOnMissing` (bit-identical receipt lines, outcomes and errors).
#[allow(dead_code)] // exercised by the test suite; no production caller wired yet
pub fn gate(res: Option<&SpaceResolution>, allow_partial: bool, receipt: &mut String) -> Result<SpaceGate, String> {
    gate_with_policy(res, allow_partial, SpaceEvidencePolicy::RefuseOnMissing, receipt)
}

/// Policy-gated space gate. `RefuseOnMissing` reproduces the established
/// `gate` behavior exactly. `OmitAndContinue` lowers the MissingEvidence
/// full-run refusal to a typed omission (GUARD-FIX-2): the run continues
/// without a space glyph, receipted with a `space_gate decision` row plus the
/// same partial markers an --allow-partial run carries.
pub fn gate_with_policy(res: Option<&SpaceResolution>, allow_partial: bool, policy: SpaceEvidencePolicy, receipt: &mut String) -> Result<SpaceGate, String> {
    let Some(r) = res else { return Ok(SpaceGate::NotRequested) };
    receipt.push_str(&r.receipt_lines());
    match &r.outcome {
        SpaceOutcome::Measured(m) => Ok(SpaceGate::Emit { codepoint: r.codepoint, advance_units: m.space_advance_units }),
        SpaceOutcome::SlopeMeasured(m) => Ok(SpaceGate::Emit { codepoint: r.codepoint, advance_units: m.space_advance_units }),
        SpaceOutcome::MissingEvidence(e) => {
            if allow_partial || policy == SpaceEvidencePolicy::OmitAndContinue {
                if policy == SpaceEvidencePolicy::OmitAndContinue && !allow_partial {
                    receipt.push_str("space_gate\tdecision\tomitted_partial\tpolicy\tomit_and_continue\treason\tspace_missing_evidence\n");
                }
                receipt.push_str(&format!(
                    "diagnostic_partial_space\ttrue\t(space evidence missing: {}; no space glyph emitted, no W_target substitute; NOT a full success)\n",
                    e.to_string().replace(['\t', '\n', '\r'], " ")
                ));
                if !receipt.contains(PARTIAL_LINE) {
                    receipt.push_str(PARTIAL_LINE);
                }
                Ok(SpaceGate::OmittedPartial)
            } else {
                Err(format!("SpaceMissingEvidence: {e}; export refused. Rerun with --allow-partial for an explicitly marked output without a space glyph"))
            }
        }
    }
}

/// Policy-gated variant of main.rs's pure `space_gate` (same
/// `(receipt_line, refusal, partial_recorded)` triple with identical strings;
/// pinned by tests). With `RefuseOnMissing` it is bit-identical to
/// `space_gate`. With `OmitAndContinue`, MissingEvidence records partial and
/// never returns a refusal - the solver-side twin of `gate_with_policy`'s
/// run-continues policy. Optional single-line call-site patch for
/// main.rs:2877: `space_gate(&solved.space_status, allow_partial)` ->
/// `space_evidence::solver_gate_with_policy(&solved.space_status, allow_partial, POLICY)`.
pub fn solver_gate_with_policy(status: &kni_metrics::self_anchored_spacing::SpaceStatus, allow_partial: bool, policy: SpaceEvidencePolicy) -> (String, Option<String>, bool) {
    use kni_metrics::self_anchored_spacing::SpaceStatus;
    match status {
        SpaceStatus::Measured { advance } => (format!(
            "space_status\tMeasured\tadvance\t{advance}\tsolver_space_glyph_emitted\tprovided, emitted only when a space glyph is present in solver input\n"),
            None, false),
        SpaceStatus::MissingEvidence { candidate_diagnostic } => {
            let line = format!(
                "space_status\tMissingEvidence\tcandidate_diagnostic\t{candidate_diagnostic}\tsolver_space_glyph_emitted\tfalse\n");
            if allow_partial || policy == SpaceEvidencePolicy::OmitAndContinue { (line, None, true) } else { (line, Some(
                "space evidence missing: a space glyph is present in solver input but no measured space advance was supplied (typed MissingEvidence); full output refused. Rerun with --allow-partial for explicitly marked partial output".to_string()), false) }
        }
        SpaceStatus::Absent => (
            "space_status\tAbsent\tsolver_space_glyph_emitted\tfalse\n".to_string(), None, false),
    }
}

/// Receipt row separating a measured space from the legacy declared number.
/// The legacy manifest `space` row is a caller-declared advance that bypasses
/// the measurement path; it is labelled, never presented as measured.
pub fn space_source_line(legacy: Option<(u32, f64)>, gate: &SpaceGate) -> String {
    match (legacy, gate) {
        (Some((cp, adv)), _) => format!(
            "space_advance_source\tdeclared_unvalidated\tcp\t{cp:#x}\tadvance\t{adv}\t(manifest `space` row: caller-declared number, not measured, bypasses space evidence)\n"
        ),
        (None, SpaceGate::Emit { codepoint, advance_units }) => format!(
            "space_advance_source\tmeasured\tcp\t{codepoint:#x}\tadvance\t{advance_units}\t(space_evidence measurement)\n"
        ),
        (None, SpaceGate::OmittedPartial) => "space_advance_source\tnone\t(space evidence missing, partial run)\n".to_string(),
        (None, SpaceGate::NotRequested) => "space_advance_source\tnone\t(no space requested)\n".to_string(),
    }
}

/// Emitted metrics must equal the measurement exactly: one `space` row with
/// lsb = rsb = 0 and the measured advance when emitting; no `space` row
/// otherwise (this also catches a solver-produced space).
pub fn verify_emitted(metrics: &[(String, f64, f64, f64)], gate: &SpaceGate) -> Result<(), String> {
    let rows: Vec<&(String, f64, f64, f64)> = metrics.iter().filter(|m| m.0 == "space").collect();
    match gate {
        SpaceGate::Emit { advance_units, .. } => {
            if rows.len() != 1 {
                return Err(format!("space invariant: expected exactly one space metrics row, found {}", rows.len()));
            }
            let r = rows[0];
            if r.1 != 0.0 || r.2 != 0.0 || r.3.to_bits() != advance_units.to_bits() {
                return Err(format!(
                    "space invariant: emitted (lsb {}, rsb {}, advance {}) != measurement (0, 0, {})",
                    r.1, r.2, r.3, advance_units
                ));
            }
            Ok(())
        }
        SpaceGate::NotRequested | SpaceGate::OmittedPartial => {
            if rows.is_empty() {
                Ok(())
            } else {
                Err("space invariant: a space row is present without a measurement".into())
            }
        }
    }
}

/// hmtx advance of `gid` read from sfnt bytes (hhea.numberOfHMetrics bound).
pub fn hmtx_advance(font: &[u8], gid: u16) -> Result<u16, String> {
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
    if g.checked_mul(4).and_then(|v| v.checked_add(2)).map_or(true, |v| v > mlen) {
        return Err("hmtx readback: gid outside the hmtx table".into());
    }
    u16b(at)
}

/// Shipped-bytes equality: cmap maps the space codepoint to a glyph whose hmtx
/// advance is the exporter's rounding (`round`) of the measurement.
pub fn verify_readback(font: &[u8], gate: &SpaceGate) -> Result<(), String> {
    let SpaceGate::Emit { codepoint, advance_units } = gate else { return Ok(()) };
    let expected = advance_units.round();
    if !(0.0..=65535.0).contains(&expected) {
        return Err(format!("space readback: measured advance {advance_units} outside u16 hmtx range"));
    }
    let sha = kni_core::cff_reader::sha256_hex(font);
    let reader = kni_core::cff_reader::CffReader::from_bytes(font, &sha).map_err(|e| format!("space readback: font refused: {e:?}"))?;
    let gid = reader.glyph_for_codepoint(*codepoint).ok_or_else(|| format!("space readback: cmap has no entry for {codepoint:#x}"))?;
    let got = hmtx_advance(font, gid)?;
    if got as f64 != expected {
        return Err(format!("space readback: hmtx advance {got} != round(measured {advance_units}) = {expected}"));
    }
    Ok(())
}

/// Same classification the solver uses for a space glyph (codepoint U+0020, or
/// glyph id `space`, ` ` or `uni0020`, case-insensitive). Used so a measured
/// space is emitted exactly once (stage 5) and never also reaches the solver.
pub fn is_space_like(name: &str, codepoint: u32) -> bool {
    let n = name.to_ascii_lowercase();
    codepoint == 0x20 || n == "space" || n == " " || n == "uni0020"
}

/// With space evidence configured, no manifest glyph row may be space-like:
/// the space comes from the measurement only. Returns the offending glyph.
pub fn reject_space_like_glyphs(glyphs: &[(String, u32)]) -> Result<(), String> {
    match glyphs.iter().find(|(n, cp)| is_space_like(n, *cp)) {
        Some((n, cp)) => Err(format!(
            "refused: manifest glyph {n} (cp {cp:#x}) is space-like but space_evidence is configured; the space glyph is emitted once, from the measurement"
        )),
        None => Ok(()),
    }
}

/// With space evidence configured the solver input carries no space glyph, so
/// the solver status must be Absent. Anything else means a space reached the
/// solver outside the measured path: refuse (this is a consistency check, it
/// does not relax the solver gate).
pub fn check_solver_status(space_evidence_configured: bool, status: &kni_metrics::self_anchored_spacing::SpaceStatus) -> Result<(), String> {
    use kni_metrics::self_anchored_spacing::SpaceStatus;
    if space_evidence_configured && !matches!(status, SpaceStatus::Absent) {
        return Err(format!("space invariant: space_evidence configured but solver space_status is {status:?}, expected Absent"));
    }
    Ok(())
}

#[allow(dead_code)]
fn _typed(_: &SpaceError) {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn fake_sha(b: &[u8]) -> String {
        format!("{:064x}", b.iter().map(|x| *x as u128).sum::<u128>() * 1_000_003 + b.len() as u128)
    }

    fn img(width: u32, h: u32, blocks: &[(u32, u32)]) -> Vec<u8> {
        let mut px = vec![255u8; (width * h) as usize];
        for &(s, w) in blocks {
            for y in 0..h {
                for x in s..s + w {
                    px[(y * width + x) as usize] = 0;
                }
            }
        }
        let mut v = vec![width as u8, h as u8];
        v.extend(px);
        v
    }

    fn decode(b: &[u8], _rem: usize) -> Result<(GrayImage, Option<DecodeRecord>), String> {
        let (w, h) = (b[0] as u32, b[1] as u32);
        Ok((GrayImage { width: w, height: h, px: b[2..].to_vec() }, None))
    }

    struct Fx {
        files: BTreeMap<PathBuf, Vec<u8>>,
        hsh_sha: String,
        hhh_sha: String,
        rec_sha: String,
    }

    fn record_text(style: &str, frame: &str, upp: &str, src: &str) -> String {
        format!("style_id {style}\nframe_id {frame}\nunits_per_px {upp}\ncalibration_source_sha256 {src}\nmethod grid-fit\n")
    }

    fn fx() -> Fx {
        let hsh = img(40, 8, &[(2, 10), (26, 10)]);
        let hhh = img(50, 8, &[(2, 10), (16, 10), (30, 10)]);
        let hsh_sha = fake_sha(&hsh);
        let hhh_sha = fake_sha(&hhh);
        let rec = record_text("unit-regular", "f1", "2", &hsh_sha).into_bytes();
        let rec_sha = fake_sha(&rec);
        let mut files = BTreeMap::new();
        files.insert(PathBuf::from("/t/hsh.png"), hsh);
        files.insert(PathBuf::from("/t/hhh.png"), hhh);
        files.insert(PathBuf::from("/t/scale.txt"), rec);
        Fx { files, hsh_sha, hhh_sha, rec_sha }
    }

    const F: &str = "f=unit-regular/f1";

    fn spec_text(f: &Fx) -> String {
        format!(
            "cp 0x20\nstyle_id unit-regular\nframe_id f1\nhsh_tile {F} hsh.png manifest:hsh {}\nhhh_tile {F} hhh.png manifest:hhh {}\nhh_kern {F} zero kern-off\nhsh_kern {F} zero kern-off\nshaping {F} capture-settings-1 true 0 {},{}\nscale_record {F} scale.txt {}\n",
            f.hsh_sha, f.hhh_sha, f.hsh_sha, f.hhh_sha, f.rec_sha
        )
    }

    const LIM: ReadLimits = ReadLimits { max_input_bytes: 1 << 20, max_pixels: 1 << 20, max_working_bytes: 1 << 20 };

    fn run_scaled(f: &Fx, text: &str, scale: f64) -> Result<SpaceResolution, String> {
        let load = |p: &Path, max: usize| -> Result<Vec<u8>, String> {
            let v = f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()))?;
            if v.len() > max { return Err("too big".into()); }
            Ok(v)
        };
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        resolve_with(text, &fake_sha(text.as_bytes()), Path::new("/t"), scale, LIM, &io)
    }

    fn run(f: &Fx, text: &str) -> Result<SpaceResolution, String> {
        run_scaled(f, text, 2.0)
    }

    fn drop_row(f: &Fx, key: &str) -> String {
        spec_text(f).lines().filter(|l| !l.starts_with(key)).collect::<Vec<_>>().join("\n")
    }

    #[test]
    fn measured_end_to_end_with_pins() {
        let f = fx();
        let r = run(&f, &spec_text(&f)).unwrap();
        let m = r.measurement().expect("measured");
        assert_eq!(m.space_advance_px_slope, 10.0);
        assert_eq!(m.space_advance_units, 20.0);
        assert_eq!(m.hsh_tile_sha256, f.hsh_sha);
        assert_eq!(m.hhh_tile_sha256, f.hhh_sha);
        assert!(m.scale_ref.contains(&f.rec_sha));
        assert!(r.receipt_lines().contains(&f.hsh_sha));
        assert_eq!(r.ledger_tsv().lines().count(), 2);
    }

    #[test]
    fn spec_sha_pin_is_enforced() {
        let f = fx();
        let text = spec_text(&f);
        let load = |p: &Path, _m: usize| f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()));
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        let e = resolve_with(&text, &"0".repeat(64), Path::new("/t"), 2.0, LIM, &io).unwrap_err();
        assert!(e.contains("spec sha256 pin mismatch"));
    }

    #[test]
    fn pin_mismatches_are_ignorable_with_stable_codes() {
        let f = fx();
        let text = spec_text(&f).replace(&format!("manifest:hsh {}", f.hsh_sha), &format!("manifest:hsh {}", "0".repeat(64)));
        let e = run(&f, &text).unwrap_err();
        assert_eq!(ignorable_space_evidence_code(&e), Some("ShaMismatch"));
        let load = |p: &Path, _m: usize| f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()));
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        let e = resolve_with(&spec_text(&f), &"0".repeat(64), Path::new("/t"), 2.0, LIM, &io).unwrap_err();
        assert_eq!(ignorable_space_evidence_code(&e), Some("ShaMismatch"));
        assert_eq!(ignorable_space_evidence_code("space tile: frame mismatch"), Some("SpecMismatch"));
        assert_eq!(ignorable_space_evidence_code("tile exceeds max_pixels"), None);
    }

    #[test]
    fn tile_sha_pin_mismatch_is_hard_error() {
        let f = fx();
        let text = spec_text(&f).replace(&format!("manifest:hsh {}", f.hsh_sha), &format!("manifest:hsh {}", "0".repeat(64)));
        assert!(run(&f, &text).unwrap_err().contains("sha256 pin mismatch"));
    }

    #[test]
    fn missing_rows_become_typed_missing_not_errors() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "shaping")).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(SpaceError::MissingSpaceEvidence { .. })));
    }

    #[test]
    fn no_scale_record_means_unverified_scale() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "scale_record")).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(SpaceError::ScaleNotPinnedConsistent { .. })));
    }

    #[test]
    fn scale_record_conflicts_are_hard_errors() {
        // units_per_px differs from manifest scale (legacy constant case)
        let f = fx();
        assert!(run_scaled(&f, &spec_text(&f), 1.71).unwrap_err().contains("UnitsMismatch"));
        // style/frame mismatch inside the record
        let mut f2 = fx();
        let rec = record_text("other-style", "f1", "2", &f2.hsh_sha).into_bytes();
        let sha = fake_sha(&rec);
        f2.files.insert(PathBuf::from("/t/scale.txt"), rec);
        let text = spec_text(&f2).replace(&f2.rec_sha, &sha);
        assert!(run(&f2, &text).unwrap_err().contains("FrameMismatch"));
        // calibration source not a loaded tile
        let mut f3 = fx();
        let rec = record_text("unit-regular", "f1", "2", &"a".repeat(64)).into_bytes();
        let sha = fake_sha(&rec);
        f3.files.insert(PathBuf::from("/t/scale.txt"), rec);
        let text = spec_text(&f3).replace(&f3.rec_sha, &sha);
        assert!(run(&f3, &text).unwrap_err().contains("SourceNotLoadedTile"));
        // record pin mismatch
        let f4 = fx();
        let text = spec_text(&f4).replace(&f4.rec_sha, &"0".repeat(64));
        assert!(run(&f4, &text).unwrap_err().contains("scale record"));
    }

    #[test]
    fn cross_source_frame_conflict_is_not_hidden() {
        let f = fx();
        // the HHH tile row declares a different frame than the request
        let text = spec_text(&f).replace(&format!("hhh_tile {F}"), "hhh_tile f=unit-regular/f2");
        let r = run(&f, &text).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(SpaceError::FrameMismatch { .. })));
        // a kern row in another style
        let text = spec_text(&f).replace(&format!("hsh_kern {F}"), "hsh_kern f=other/f1");
        let r = run(&f, &text).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(SpaceError::FrameMismatch { .. })));
    }

    #[test]
    fn hhh_without_kern_row_is_unverified() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "hh_kern")).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(SpaceError::UnverifiedHHSpacing { .. })));
    }

    #[test]
    fn parse_errors_are_hard() {
        let base = Path::new("/t");
        assert!(parse_spec("cp 0x20\ncp 0x20\n", base).is_err());
        assert!(parse_spec("style_id a\nframe_id b\n", base).is_err());
        assert!(parse_spec("cp 0x20\nstyle_id a\nframe_id b\nbogus 1\n", base).is_err());
        assert!(parse_spec("cp 0x20\nstyle_id a\nframe_id b\nhsh_tile f=a/b p r short\n", base).is_err());
        assert!(parse_spec("cp 0x20\nstyle_id a\nframe_id b\nhsh_tile p r short\n", base).is_err()); // no f= token
        assert!(parse_spec("cp 0x20\nstyle_id a\nframe_id b\nshaping f=a/b s maybe 0 x\n", base).is_err());
    }

    #[test]
    fn space_cp_semantics() {
        assert!(validate_space_cp(0x20).is_ok());
        assert!(validate_space_cp(0).is_err());
        assert!(validate_space_cp(0xD800).is_err()); // surrogate
        assert!(validate_space_cp(0x110000).is_err());
        assert!(validate_space_cp(0x41).is_err()); // arbitrary cp
        assert!(validate_space_cp(0xA0).is_err()); // NBSP is not the space glyph
        assert!(parse_spec("cp 0x41\nstyle_id a\nframe_id b\n", Path::new("/t")).is_err());
    }

    #[test]
    fn manifest_row_requires_every_field() {
        let mk = |s: &'static str| {
            let mut it = s.split_whitespace();
            let e = |m: &str| m.to_string();
            SpaceEvidenceRef::from_tokens(Path::new("/b"), &mut it, &e)
        };
        let sha = "a".repeat(64);
        let ok = Box::leak(format!("spec.txt {sha} 1000 2000 3000").into_boxed_str());
        let r = mk(ok).unwrap();
        assert_eq!(r.limits, ReadLimits { max_input_bytes: 1000, max_pixels: 2000, max_working_bytes: 3000 });
        let no_sha = Box::leak("spec.txt".to_string().into_boxed_str());
        assert!(mk(no_sha).is_err());
        let no_limits = Box::leak(format!("spec.txt {sha}").into_boxed_str());
        assert!(mk(no_limits).is_err());
        let zero = Box::leak(format!("spec.txt {sha} 0 1 1").into_boxed_str());
        assert!(mk(zero).is_err());
        let badsha = Box::leak("spec.txt abc 1 1 1".to_string().into_boxed_str());
        assert!(mk(badsha).is_err());
    }

    #[test]
    fn bounded_read_refuses_oversize_and_non_files() {
        let dir = std::env::temp_dir().join(format!("kni-space-bounded-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("big.bin");
        std::fs::write(&p, vec![7u8; 100]).unwrap();
        assert_eq!(read_bounded(&p, 100).unwrap().len(), 100);
        assert!(read_bounded(&p, 99).unwrap_err().contains("exceeds"));
        assert!(read_bounded(&dir, 1000).is_err());
        assert!(read_bounded(&dir.join("absent"), 10).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn gate_full_refusal_partial_marker_and_standard_partial_line() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "hsh_kern")).unwrap();
        let mut rc = String::new();
        let e = gate(Some(&r), false, &mut rc).unwrap_err();
        assert!(e.starts_with("SpaceMissingEvidence"));
        let mut rc = String::new();
        assert_eq!(gate(Some(&r), true, &mut rc).unwrap(), SpaceGate::OmittedPartial);
        assert!(rc.contains("diagnostic_partial_space\ttrue"));
        assert!(rc.contains("partial_output\ttrue\treason\tspace_missing_evidence"));
        // the standard line is not duplicated when already present
        let mut rc = String::from(PARTIAL_LINE);
        gate(Some(&r), true, &mut rc).unwrap();
        assert_eq!(rc.matches("partial_output\ttrue").count(), 1);
        assert_eq!(gate(None, false, &mut String::new()).unwrap(), SpaceGate::NotRequested);
    }
    #[test]
    fn gate_with_policy_default_is_bit_identical() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "hsh_kern")).unwrap();
        let (mut a, mut b) = (String::new(), String::new());
        let ea = gate(Some(&r), false, &mut a).unwrap_err();
        let eb = gate_with_policy(Some(&r), false, SpaceEvidencePolicy::RefuseOnMissing, &mut b).unwrap_err();
        assert_eq!(ea, eb);
        assert_eq!(a, b);
        let (mut a, mut b) = (String::new(), String::new());
        assert_eq!(
            gate(Some(&r), true, &mut a).unwrap(),
            gate_with_policy(Some(&r), true, SpaceEvidencePolicy::RefuseOnMissing, &mut b).unwrap()
        );
        assert_eq!(a, b);
        let r2 = run(&f, &spec_text(&f)).unwrap();
        let (mut a, mut b) = (String::new(), String::new());
        assert_eq!(
            gate(Some(&r2), false, &mut a).unwrap(),
            gate_with_policy(Some(&r2), false, SpaceEvidencePolicy::RefuseOnMissing, &mut b).unwrap()
        );
        assert_eq!(a, b);
    }

    #[test]
    fn gate_with_policy_omit_and_continue_marks_partial_and_continues() {
        let f = fx();
        let r = run(&f, &drop_row(&f, "hsh_kern")).unwrap();
        let mut rc = String::new();
        assert_eq!(
            gate_with_policy(Some(&r), false, SpaceEvidencePolicy::OmitAndContinue, &mut rc).unwrap(),
            SpaceGate::OmittedPartial
        );
        assert!(rc.contains("space_gate\tdecision\tomitted_partial\tpolicy\tomit_and_continue\treason\tspace_missing_evidence"));
        assert!(rc.contains("diagnostic_partial_space\ttrue"));
        assert!(rc.contains("partial_output\ttrue\treason\tspace_missing_evidence"));
        // downstream consumers already accept OmittedPartial
        assert!(verify_emitted(&[(".notdef".to_string(), 0.0, 0.0, 0.0)], &SpaceGate::OmittedPartial).is_ok());
        // with --allow-partial the policy adds nothing (no duplicate markers)
        let mut rc2 = String::new();
        assert_eq!(
            gate_with_policy(Some(&r), true, SpaceEvidencePolicy::OmitAndContinue, &mut rc2).unwrap(),
            SpaceGate::OmittedPartial
        );
        assert!(!rc2.contains("policy\tomit_and_continue"));
        assert_eq!(rc2.matches("partial_output\ttrue").count(), 1);
        // NotRequested unchanged
        assert_eq!(
            gate_with_policy(None, false, SpaceEvidencePolicy::OmitAndContinue, &mut String::new()).unwrap(),
            SpaceGate::NotRequested
        );
    }

    #[test]
    fn solver_gate_with_policy_matches_main_rs_space_gate_formats() {
        use kni_metrics::self_anchored_spacing::SpaceStatus;
        let (line, refusal, partial) =
            solver_gate_with_policy(&SpaceStatus::Measured { advance: 30.0 }, false, SpaceEvidencePolicy::RefuseOnMissing);
        assert_eq!(line, "space_status\tMeasured\tadvance\t30\tsolver_space_glyph_emitted\tprovided, emitted only when a space glyph is present in solver input\n");
        assert!(refusal.is_none() && !partial);
        let (line, refusal, partial) =
            solver_gate_with_policy(&SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, false, SpaceEvidencePolicy::RefuseOnMissing);
        assert_eq!(line, "space_status\tMissingEvidence\tcandidate_diagnostic\t25\tsolver_space_glyph_emitted\tfalse\n");
        let e = refusal.expect("strict policy refuses");
        assert!(e.contains("MissingEvidence") && e.contains("--allow-partial"));
        assert!(!partial);
        let (_, refusal, partial) =
            solver_gate_with_policy(&SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, true, SpaceEvidencePolicy::RefuseOnMissing);
        assert!(refusal.is_none() && partial);
        let (line, refusal, partial) =
            solver_gate_with_policy(&SpaceStatus::Absent, false, SpaceEvidencePolicy::RefuseOnMissing);
        assert_eq!(line, "space_status\tAbsent\tsolver_space_glyph_emitted\tfalse\n");
        assert!(refusal.is_none() && !partial);
    }

    #[test]
    fn solver_gate_omit_and_continue_never_refuses() {
        use kni_metrics::self_anchored_spacing::SpaceStatus;
        let (line, refusal, partial) =
            solver_gate_with_policy(&SpaceStatus::MissingEvidence { candidate_diagnostic: 25.0 }, false, SpaceEvidencePolicy::OmitAndContinue);
        assert_eq!(line, "space_status\tMissingEvidence\tcandidate_diagnostic\t25\tsolver_space_glyph_emitted\tfalse\n");
        assert!(refusal.is_none() && partial, "run continues, marked partial");
    }

    #[test]
    fn legacy_declared_space_is_labelled_not_measured() {
        let l = space_source_line(Some((0x20, 25.0)), &SpaceGate::NotRequested);
        assert!(l.contains("declared_unvalidated") && !l.contains("\tmeasured\t"));
        let m = space_source_line(None, &SpaceGate::Emit { codepoint: 0x20, advance_units: 20.0 });
        assert!(m.contains("\tmeasured\t"));
        assert!(space_source_line(None, &SpaceGate::OmittedPartial).contains("none"));
    }

    #[test]
    fn emitted_equals_measurement() {
        let f = fx();
        let r = run(&f, &spec_text(&f)).unwrap();
        let mut rc = String::new();
        let g = gate(Some(&r), false, &mut rc).unwrap();
        assert_eq!(g, SpaceGate::Emit { codepoint: 0x20, advance_units: 20.0 });
        let ok = vec![(".notdef".to_string(), 0.0, 0.0, 0.0), ("space".to_string(), 0.0, 0.0, 20.0)];
        assert!(verify_emitted(&ok, &g).is_ok());
        assert!(verify_emitted(&[("space".to_string(), 0.0, 0.0, 21.0)], &g).is_err());
        assert!(verify_emitted(&[("space".to_string(), 1.0, 0.0, 20.0)], &g).is_err());
        assert!(verify_emitted(&[], &g).is_err());
        let twice = vec![("space".to_string(), 0.0, 0.0, 20.0), ("space".to_string(), 0.0, 0.0, 20.0)];
        assert!(verify_emitted(&twice, &g).is_err());
    }

    #[test]
    fn no_space_row_without_measurement() {
        let stray = vec![("space".to_string(), 0.0, 0.0, 33.0)];
        assert!(verify_emitted(&stray, &SpaceGate::OmittedPartial).is_err());
        assert!(verify_emitted(&stray, &SpaceGate::NotRequested).is_err());
        assert!(verify_emitted(&[(".notdef".to_string(), 0.0, 0.0, 0.0)], &SpaceGate::OmittedPartial).is_ok());
    }

    /// Synthetic sfnt with hhea (numberOfHMetrics at +34) and hmtx.
    fn synthetic_sfnt(advances: &[u16]) -> Vec<u8> {
        let mut hhea = vec![0u8; 36];
        hhea[34..36].copy_from_slice(&(advances.len() as u16).to_be_bytes());
        let mut hmtx = Vec::new();
        for a in advances {
            hmtx.extend_from_slice(&a.to_be_bytes());
            hmtx.extend_from_slice(&0i16.to_be_bytes());
        }
        let dir_len = 12 + 16 * 2;
        let mut out = vec![0u8; dir_len];
        out[4..6].copy_from_slice(&2u16.to_be_bytes());
        let hhea_off = out.len();
        out.extend_from_slice(&hhea);
        let hmtx_off = out.len();
        out.extend_from_slice(&hmtx);
        for (i, (tag, off, len)) in [(*b"hhea", hhea_off, hhea.len()), (*b"hmtx", hmtx_off, hmtx.len())].iter().enumerate() {
            let r = 12 + 16 * i;
            out[r..r + 4].copy_from_slice(tag);
            out[r + 8..r + 12].copy_from_slice(&(*off as u32).to_be_bytes());
            out[r + 12..r + 16].copy_from_slice(&(*len as u32).to_be_bytes());
        }
        out
    }

    #[test]
    fn hmtx_readback_reads_advance_and_bounds() {
        let font = synthetic_sfnt(&[0, 500, 489, 20]);
        assert_eq!(hmtx_advance(&font, 3).unwrap(), 20);
        assert_eq!(hmtx_advance(&font, 2).unwrap(), 489);
        assert!(hmtx_advance(&font, 4).is_err());
        assert!(hmtx_advance(&font[..10], 0).is_err());
    }

    fn two_glyph_profiles() -> Vec<kni_metrics::outline_spacing::OutlineProfile> {
        use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
        let mk = |id: &str, x1: f64| {
            let input = OutlineInput {
                glyph_id: id.into(), source_pin: format!("sha256:test:{id}"), upm: 1000,
                origin: [0.0, 0.0], flatten_tolerance: 0.0,
                rings: vec![vec![[0.0, 0.0], [x1, 0.0], [x1, 100.0], [0.0, 100.0]]],
            };
            let pol = ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
            profile_outline(&input, pol).expect("profile")
        };
        vec![mk("l", 100.0), mk("r", 50.0)]
    }

    /// Stage-3 as the pipeline builds it with space evidence configured: the
    /// ctx carries glyph codepoints only (no space glyph, no measured advance
    /// passed to the solver). The solver status is Absent, so the existing
    /// space_gate does not refuse, and the measured space goes out through
    /// stage 5 only. No gate is relaxed.
    #[test]
    fn measured_space_does_not_trip_solver_space_gate() {
        use kni_metrics::self_anchored_spacing::{solve_spacing, FontContext, SpacingPolicy, SpaceStatus};
        let profiles = two_glyph_profiles();
        let cps = vec![("l".to_string(), 0x6c_u32), ("r".to_string(), 0x72_u32)];
        assert!(reject_space_like_glyphs(&cps).is_ok());
        let ctx = FontContext { glyph_codepoints: cps, ..FontContext::default() };
        let policy = SpacingPolicy { sample_resolution: 1.0, max_pair_evaluations: 1000, max_pairs: 100, pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
        let solved = solve_spacing(&profiles, Some(&ctx), &policy).expect("solve");
        assert!(matches!(solved.space_status, SpaceStatus::Absent));
        assert!(check_solver_status(true, &solved.space_status).is_ok());
        // the real (private, unchanged) gate: Absent + allow_partial=false -> no refusal, no partial
        let (_line, refusal, partial) = crate::space_gate(&solved.space_status, false);
        assert!(refusal.is_none() && !partial);
        // pipeline side: measured gate emits
        let f = fx();
        let r = run(&f, &spec_text(&f)).unwrap();
        let mut rc = String::new();
        assert!(matches!(gate(Some(&r), false, &mut rc).unwrap(), SpaceGate::Emit { .. }));
    }

    #[test]
    fn space_like_glyphs_and_stray_solver_status_are_refused() {
        use kni_metrics::self_anchored_spacing::SpaceStatus;
        assert!(reject_space_like_glyphs(&[("a".into(), 0x20)]).is_err());
        assert!(reject_space_like_glyphs(&[("UNI0020".into(), 0x41)]).is_err());
        assert!(reject_space_like_glyphs(&[("Space".into(), 0x41)]).is_err());
        assert!(reject_space_like_glyphs(&[("a".into(), 0x61)]).is_ok());
        assert!(check_solver_status(true, &SpaceStatus::MissingEvidence { candidate_diagnostic: 1.0 }).is_err());
        assert!(check_solver_status(true, &SpaceStatus::Measured { advance: 1.0 }).is_err());
        assert!(check_solver_status(false, &SpaceStatus::MissingEvidence { candidate_diagnostic: 1.0 }).is_ok());
        // the solver itself still classifies a space-like profile as MissingEvidence without an advance
        use kni_metrics::self_anchored_spacing::{solve_spacing, FontContext, SpacingPolicy};
        let mut profiles = two_glyph_profiles();
        let mut sp = profiles[1].clone();
        sp.glyph_id = "sp".into();
        sp.rows = vec![];
        sp.bounds = [0.0, 0.0, 0.0, 0.0];
        sp.ink_area = 0.0;
        sp.counter_area = 0.0;
        profiles.push(sp);
        let ctx = FontContext { glyph_codepoints: vec![("l".into(), 0x6c), ("r".into(), 0x72), ("sp".into(), 0x20)], ..FontContext::default() };
        let policy = SpacingPolicy { sample_resolution: 1.0, max_pair_evaluations: 1000, max_pairs: 100, pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
        if let Ok(sol) = solve_spacing(&profiles, Some(&ctx), &policy) {
            assert!(matches!(sol.space_status, SpaceStatus::MissingEvidence { .. }));
            let (_l, refusal, _p) = crate::space_gate(&sol.space_status, false);
            assert!(refusal.is_some(), "solver space gate unchanged: still refuses");
        }
    }

    /// Pair-independence invariant (test only, not a runtime gate): the same
    /// fixture solved with and without a measured space advance in the font
    /// context must give identical pair results, and the fixture must carry
    /// at least two pairs so the comparison is not vacuous.
    #[test]
    fn pair_solution_is_independent_of_space_advance_wired_two_pair_fixture() {
        use kni_metrics::outline_spacing::{profile_outline, OutlineInput, ScanPolicy, MERGE_GUARD_UNITS};
        use kni_metrics::self_anchored_spacing::{solve_spacing, FontContext, SpacingPolicy};
        fn prof(id: &str, x1: f64) -> kni_metrics::outline_spacing::OutlineProfile {
            let input = OutlineInput {
                glyph_id: id.into(), source_pin: format!("sha256:test:{id}"), upm: 1000,
                origin: [0.0, 0.0], flatten_tolerance: 0.0,
                rings: vec![vec![[0.0, 0.0], [x1, 0.0], [x1, 100.0], [0.0, 100.0]]],
            };
            let pol = ScanPolicy { row_step: 2.0, max_rows: 4000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
            profile_outline(&input, pol).expect("profile")
        }
        let profiles = vec![prof("l", 100.0), prof("r", 50.0)];
        let policy = SpacingPolicy { sample_resolution: 1.0, max_pair_evaluations: 1000, max_pairs: 100, pair_min_shared_rows: 1, lambda: None, dcap: None, contrast_floor: false, cadence_class_pass: false, class_channel_targets: false };
        let cps = vec![("l".to_string(), 0x6c_u32), ("r".to_string(), 0x72_u32)];
        let ctx_a = FontContext { glyph_codepoints: cps.clone(), ..FontContext::default() };
        let ctx_b = FontContext { glyph_codepoints: cps, measured_space_advance: Some(20.0), ..FontContext::default() };
        let a = solve_spacing(&profiles, Some(&ctx_a), &policy).expect("solve a");
        let b = solve_spacing(&profiles, Some(&ctx_b), &policy).expect("solve b");
        let n_pairs = a.pairs.len() + a.pair_ledger.len();
        assert!(n_pairs >= 2, "fixture must carry at least 2 pair rows (l->r, r->l); got {n_pairs}");
        assert_eq!(format!("{:?}", a.pairs), format!("{:?}", b.pairs));
        assert_eq!(format!("{:?}", a.pair_ledger), format!("{:?}", b.pair_ledger));
        assert_eq!(a.complete, b.complete);
    }

    #[test]
    fn receipt_claims_only_the_decoder_that_ran() {
        let f = fx();
        let mut r = run(&f, &spec_text(&f)).unwrap();
        let t = r.receipt_lines();
        assert!(t.contains("decode\tnone") && !t.contains("png_bounded_adapter") && !t.contains("major_payload_only"), "{t}");
        r.decodes = vec![DecodeRecord {
            input_sha256: "j".repeat(64),
            kind: DecodeKind::Jpeg { limits: LIM, origin: "manifest space_evidence row".into() },
        }];
        let t = r.receipt_lines();
        assert!(t.contains("kind\tjpeg_decode_source") && t.contains("png_adapter\tnot_used"), "{t}");
        assert!(!t.contains("png_bounded_adapter") && !t.contains("major_payload_only") && !t.contains("not_validated"), "{t}");
        r.decodes.push(DecodeRecord { input_sha256: "p".repeat(64), kind: DecodeKind::PngAdapter { line: "png_decode_limits\tX\tcrc\tnot_validated".into() } });
        let t = r.receipt_lines();
        assert!(t.contains(&format!("input_sha256\t{}\tkind\tpng_bounded_adapter\tpng_decode_limits", "p".repeat(64))), "{t}");
        assert_eq!(t.matches("space_evidence\tdecode\t").count(), 2);
    }

    // ---- slope route ----
    fn slope_fx(gaps: [u32; 3]) -> Fx {
        let mut f = fx();
        let mut shas = Vec::new();
        for (i, g) in gaps.iter().enumerate() {
            let w = 2 + 10 + g + 10 + 2;
            let im = img(w, 8, &[(2, 10), (12 + g, 10)]);
            shas.push(fake_sha(&im));
            f.files.insert(PathBuf::from(format!("/t/s{}.png", i + 1)), im);
        }
        let rec = record_text("unit-regular", "f1", "2", &shas[0]).into_bytes();
        f.rec_sha = fake_sha(&rec);
        f.files.insert(PathBuf::from("/t/scale.txt"), rec);
        f.hsh_sha = shas.join(",");
        f
    }

    fn slope_text(f: &Fx, kern: bool, quant: Option<&str>) -> String {
        let shas: Vec<&str> = f.hsh_sha.split(',').collect();
        let mut s = String::from("cp 0x20\nstyle_id unit-regular\nframe_id f1\n");
        for (i, sh) in shas.iter().enumerate() {
            s.push_str(&format!("slope_tile {F} {} s{}.png ledger:H{}H {}\n", i + 1, i + 1, "_".repeat(i + 1), sh));
        }
        if kern {
            s.push_str(&format!("slope_kern {F} zero kern-off\nink_model border_median_delta 8 test:notdef_audit.INK_DELTA\n"));
        }
        s.push_str("slope_max_points 16\n");
        if let Some(q) = quant {
            s.push_str(&format!("renderer_contract {q}\n"));
        }
        s.push_str(&format!("shaping {F} capture-settings-1 true 0 {}\nscale_record {F} scale.txt {}\n", f.hsh_sha, f.rec_sha));
        s
    }

    #[test]
    fn slope_without_bound_is_descriptive_and_refused() {
        let f = slope_fx([10, 20, 30]);
        let r = run(&f, &slope_text(&f, true, None)).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(_)));
        assert!(r.slope.is_some());
        assert!(r.receipt_lines().contains("space_evidence\tslope\t"));
        let mut rec = String::new();
        assert!(gate(Some(&r), false, &mut rec).is_err());
    }

    #[test]
    fn slope_with_kern_and_bound_exports() {
        let f = slope_fx([10, 20, 30]);
        let r = run(&f, &slope_text(&f, true, Some("binary_pixel_center t d f th c cl"))).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::SlopeMeasured(_)), "{:?}", r.outcome);
        let mut rec = String::new();
        assert!(matches!(gate(Some(&r), false, &mut rec), Ok(SpaceGate::Emit { .. })));
    }

    #[test]
    fn slope_missing_kern_is_refused() {
        let f = slope_fx([10, 20, 30]);
        let r = run(&f, &slope_text(&f, false, Some("binary_pixel_center t d f th c cl"))).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(_)));
    }

    #[test]
    fn slope_nonlinear_is_refused() {
        let f = slope_fx([10, 20, 45]);
        let r = run(&f, &slope_text(&f, true, Some("binary_pixel_center t d f th c cl"))).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(_)));
    }

    #[test]
    fn slope_aliased_tiles_are_refused() {
        let f = slope_fx([10, 20, 20]);
        let r = run(&f, &slope_text(&f, true, Some("binary_pixel_center t d f th c cl"))).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(_)));
    }

    #[test]
    fn slope_and_hsh_routes_are_exclusive() {
        let f = slope_fx([10, 20, 30]);
        let text = format!("{}hsh_tile {F} s1.png manifest:hsh {}\n", slope_text(&f, true, None), f.hsh_sha.split(',').next().unwrap());
        assert!(run(&f, &text).unwrap_err().contains("exclusive"));
    }

    // ---- real PNG bytes through the real decoder (resolve_file) ----
    fn crc32(data: &[u8]) -> u32 {
        let mut c = !0u32;
        for &b in data {
            c ^= u32::from(b);
            for _ in 0..8 {
                c = if c & 1 != 0 { (c >> 1) ^ 0xEDB8_8320 } else { c >> 1 };
            }
        }
        !c
    }

    /// Minimal 8-bit grayscale PNG with stored (uncompressed) deflate blocks.
    fn png_gray(width: u32, h: u32, blocks: &[(u32, u32)]) -> Vec<u8> {
        let mut raw = Vec::new();
        for _ in 0..h {
            raw.push(0u8);
            for x in 0..width {
                raw.push(if blocks.iter().any(|&(s, w)| x >= s && x < s + w) { 0 } else { 255 });
            }
        }
        let mut z = vec![0x78, 0x01];
        let chunks: Vec<&[u8]> = raw.chunks(60000).collect();
        for (i, c) in chunks.iter().enumerate() {
            z.push(u8::from(i + 1 == chunks.len()));
            z.extend((c.len() as u16).to_le_bytes());
            z.extend((!(c.len() as u16)).to_le_bytes());
            z.extend(*c);
        }
        let (mut a, mut b) = (1u32, 0u32);
        for &x in &raw {
            a = (a + u32::from(x)) % 65521;
            b = (b + a) % 65521;
        }
        z.extend(((b << 16) | a).to_be_bytes());
        let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
        let mut chunk = |ty: &[u8], d: &[u8]| {
            out.extend((d.len() as u32).to_be_bytes());
            let mut body = ty.to_vec();
            body.extend(d);
            out.extend(&body);
            out.extend(crc32(&body).to_be_bytes());
        };
        let mut ihdr = Vec::new();
        ihdr.extend(width.to_be_bytes());
        ihdr.extend(h.to_be_bytes());
        ihdr.extend([8, 0, 0, 0, 0]);
        chunk(b"IHDR", &ihdr);
        chunk(b"IDAT", &z);
        chunk(b"IEND", &[]);
        out
    }

    #[test]
    fn slope_route_end_to_end_through_real_png_decoder() {
        let dir = std::env::temp_dir().join(format!("kni-slope-e2e-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let sha = |b: &[u8]| kni_core::cff_reader::sha256_hex(b);
        let gaps = [185u32, 293, 399];
        let mut shas = Vec::new();
        for (i, g) in gaps.iter().enumerate() {
            let png = png_gray(2 + 10 + g + 10 + 2, 8, &[(2, 10), (12 + g, 10)]);
            shas.push(sha(&png));
            std::fs::write(dir.join(format!("s{}.png", i + 1)), png).unwrap();
        }
        let rec = record_text("unit-regular", "f1", "2", &shas[0]);
        std::fs::write(dir.join("scale.txt"), &rec).unwrap();
        let mut spec = String::from("cp 0x20\nstyle_id unit-regular\nframe_id f1\n");
        for (i, h) in shas.iter().enumerate() {
            spec.push_str(&format!("slope_tile {F} {} s{}.png ledger:H{}H {h}\n", i + 1, i + 1, "_".repeat(i + 1)));
        }
        spec.push_str(&format!("slope_kern {F} zero kern-off\nslope_max_points 16\nink_model border_median_delta 8 test:notdef_audit.INK_DELTA\nrenderer_contract binary_pixel_center t d f th c cl\nshaping {F} capture-settings-1 true 0 {}\nscale_record {F} scale.txt {}\n", shas.join(","), sha(rec.as_bytes())));
        std::fs::write(dir.join("space.spec"), &spec).unwrap();
        let r = SpaceEvidenceRef { path: dir.join("space.spec"), sha256: sha(spec.as_bytes()), limits: LIM };
        let res = resolve_file(&r, 2.0).unwrap();
        match &res.outcome {
            SpaceOutcome::SlopeMeasured(m) => {
                let (lo, hi) = m.advance_units_interval.unwrap();
                assert!(lo < 214.0 && 214.0 < hi, "interval must contain 2*107 without claiming it exact: {lo} {hi}");
            }
            o => panic!("{o:?}"),
        }
        assert_eq!(res.decodes.len(), 3);
        assert!(res.receipt_lines().contains("interval, not an exact advance"));
        // same bytes, no renderer_contract row: descriptive and refused
        let spec2: String = spec.lines().filter(|l| !l.starts_with("renderer_contract")).map(|l| format!("{l}\n")).collect();
        std::fs::write(dir.join("space2.spec"), &spec2).unwrap();
        let r2 = SpaceEvidenceRef { path: dir.join("space2.spec"), sha256: sha(spec2.as_bytes()), limits: LIM };
        assert!(matches!(resolve_file(&r2, 2.0).unwrap().outcome, SpaceOutcome::MissingEvidence(_)));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn slope_limits_are_checked_before_any_io_and_decode_budget_is_request_wide() {
        let f = slope_fx([10, 20, 30]);
        let loads = std::sync::atomic::AtomicUsize::new(0);
        let load = |p: &Path, _m: usize| {
            loads.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()))
        };
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        let text = slope_text(&f, true, None);
        let go = |t: &str, lim: ReadLimits| resolve_with(t, &fake_sha(t.as_bytes()), Path::new("/t"), 2.0, lim, &io);
        // more rows than slope_max_points: refused, zero reads
        let few = text.replace("slope_max_points 16", "slope_max_points 2");
        assert!(go(&few, LIM).unwrap_err().contains("exceed slope_max_points"));
        // limit row missing: refused, zero reads
        let none: String = text.lines().filter(|l| !l.starts_with("slope_max_points")).map(|l| format!("{l}\n")).collect();
        assert!(go(&none, LIM).unwrap_err().contains("slope_max_points"));
        assert_eq!(loads.load(std::sync::atomic::Ordering::SeqCst), 0);
        // decoded-byte budget: first tile alone fits, the sum does not
        let one = f.files.get(Path::new("/t/s1.png")).unwrap().len();
        let tight = ReadLimits { max_working_bytes: one + (one - 2) / 2, ..LIM };
        let e = go(&text, tight).unwrap_err();
        assert!(e.contains("max_working_bytes budget"), "{e}");
        assert!(go(&text, LIM).is_ok());
        // the read bound handed to io.load is min(max_input_bytes, remaining budget)
        let seen = std::sync::atomic::AtomicUsize::new(usize::MAX);
        let load2 = |p: &Path, m: usize| {
            seen.fetch_min(m, std::sync::atomic::Ordering::SeqCst);
            f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()))
        };
        let io2 = Io { load: &load2, decode: &decode, sha: &fake_sha };
        let lim = ReadLimits { max_working_bytes: 5000, ..LIM };
        let _ = resolve_with(&text, &fake_sha(text.as_bytes()), Path::new("/t"), 2.0, lim, &io2);
        assert!(seen.load(std::sync::atomic::Ordering::SeqCst) <= 5000);
    }

    // ---- P3: parallel tile loading (jobs) ----
    // Limits with headroom so the speculative parallel path is viable (the
    // JPEG budget formula charges the DECLARED max_pixels; LIM's working
    // budget equals it, which would force the fallback on every tile).
    const LIM2: ReadLimits = ReadLimits { max_input_bytes: 1 << 20, max_pixels: 4096, max_working_bytes: 1 << 20 };

    fn load_of(f: &Fx) -> impl Fn(&Path, usize) -> Result<Vec<u8>, String> + Send + Sync + '_ {
        move |p: &Path, max: usize| {
            let v = f.files.get(p).cloned().ok_or_else(|| format!("missing {}", p.display()))?;
            if v.len() > max { return Err("too big".into()); }
            Ok(v)
        }
    }

    #[test]
    fn parallel_tile_loading_bit_identical_to_sequential() {
        let f = slope_fx([10, 20, 30]);
        let text = slope_text(&f, true, None);
        let load = load_of(&f);
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        let seq = resolve_with(&text, &fake_sha(text.as_bytes()), Path::new("/t"), 2.0, LIM2, &io).map(|r| format!("{r:?}"));
        for jobs in [2usize, 4, 8] {
            let par = resolve_with_jobs(&text, &fake_sha(text.as_bytes()), Path::new("/t"), 2.0, LIM2, &io, jobs).map(|r| format!("{r:?}"));
            assert_eq!(seq, par, "parallel tile loading (jobs={jobs}) must be bit-identical to the serial loop");
        }
    }

    #[test]
    fn parallel_driver_direct_contract() {
        let f = slope_fx([10, 20, 30]);
        let text = slope_text(&f, true, None);
        let spec = parse_spec(&text, Path::new("/t")).unwrap();
        let load = load_of(&f);
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        // happy path: the speculative driver engages and matches the serial loader
        let par = load_tiles_parallel(&spec, &io, LIM2.max_input_bytes, LIM2.max_working_bytes, &LIM2, 4).expect("parallel path must engage with headroom");
        let seq = load_tiles_sequential(&spec, &io, LIM2.max_input_bytes, LIM2.max_working_bytes).unwrap();
        assert_eq!(par.budget_left, seq.budget_left);
        assert_eq!(par.tile_shas, seq.tile_shas);
        assert_eq!(par.slopes.len(), 3);
        assert_eq!(format!("{:?}", par.slopes.iter().map(|t| t.tile.image.px.len()).collect::<Vec<_>>()),
                   format!("{:?}", seq.slopes.iter().map(|t| t.tile.image.px.len()).collect::<Vec<_>>()));
        // sha mismatch on any tile: speculative driver declines, serial decides
        let bad = text.replace(&f.hsh_sha.split(',').nth(1).unwrap().to_string(), &"0".repeat(64));
        let spec_bad = parse_spec(&bad, Path::new("/t")).unwrap();
        assert!(load_tiles_parallel(&spec_bad, &io, LIM2.max_input_bytes, LIM2.max_working_bytes, &LIM2, 4).is_none());
        // decoded-pixel sum over the working budget: declines to the serial loop
        let tight = ReadLimits { max_working_bytes: 40, ..LIM2 };
        assert!(load_tiles_parallel(&spec, &io, tight.max_input_bytes, tight.max_working_bytes, &tight, 4).is_none());
        // single tile: nothing to overlap
        let one = parse_spec(&drop_row(&fx(), "hhh_tile"), Path::new("/t")).unwrap();
        assert!(load_tiles_parallel(&one, &io, LIM2.max_input_bytes, LIM2.max_working_bytes, &LIM2, 4).is_none());
    }

    #[test]
    fn parallel_tile_loading_refusals_match_sequential() {
        let f = slope_fx([10, 20, 30]);
        let text = slope_text(&f, true, None);
        let load = load_of(&f);
        let io = Io { load: &load, decode: &decode, sha: &fake_sha };
        let seq_err = |t: &str, lim: ReadLimits| resolve_with(t, &fake_sha(t.as_bytes()), Path::new("/t"), 2.0, lim, &io).unwrap_err();
        let par_err = |t: &str, lim: ReadLimits| resolve_with_jobs(t, &fake_sha(t.as_bytes()), Path::new("/t"), 2.0, lim, &io, 4).unwrap_err();
        // sha pin mismatch on the middle tile
        let bad = text.replace(&f.hsh_sha.split(',').nth(1).unwrap().to_string(), &"0".repeat(64));
        assert_eq!(seq_err(&bad, LIM2), par_err(&bad, LIM2));
        // decoded-pixel sum over the working budget
        let one = f.files.get(Path::new("/t/s1.png")).unwrap().len();
        let tight = ReadLimits { max_working_bytes: one + (one - 2) / 2, ..LIM2 };
        assert_eq!(seq_err(&text, tight), par_err(&text, tight));
        // input cap exceeded
        let tiny = ReadLimits { max_input_bytes: 4, ..LIM2 };
        assert_eq!(seq_err(&text, tiny), par_err(&text, tiny));
        // missing file
        let ghost = text.replace("s2.png", "ghost.png").replace(&f.hsh_sha.split(',').nth(1).unwrap().to_string(), &fake_sha(b"ghost"));
        assert_eq!(seq_err(&ghost, LIM2), par_err(&ghost, LIM2));
    }

    #[test]
    fn parallel_tile_loading_records_ordered_and_deduped() {
        // s1 and s3 share bytes (same sha): first occurrence wins, order is
        // manifest order on every jobs level, exactly the old collection.
        let mut f = slope_fx([10, 20, 30]);
        let dup = f.files.get(Path::new("/t/s1.png")).unwrap().clone();
        let shas: Vec<String> = f.hsh_sha.split(',').map(|x| x.to_string()).collect();
        f.files.insert(PathBuf::from("/t/s3.png"), dup);
        f.hsh_sha = format!("{},{}", shas[..2].join(","), shas[0]);
        let text = slope_text(&f, true, None);
        let decode_rec = |b: &[u8], _rem: usize| -> Result<(GrayImage, Option<DecodeRecord>), String> {
            let (w, h) = (b[0] as u32, b[1] as u32);
            Ok((GrayImage { width: w, height: h, px: b[2..].to_vec() },
                Some(DecodeRecord { input_sha256: fake_sha(b), kind: DecodeKind::Jpeg { limits: LIM2, origin: "test".into() } })))
        };
        let load = load_of(&f);
        let io = Io { load: &load, decode: &decode_rec, sha: &fake_sha };
        let seq = resolve_with(&text, &fake_sha(text.as_bytes()), Path::new("/t"), 2.0, LIM2, &io).unwrap();
        assert_eq!(seq.decodes.len(), 2, "duplicate input sha deduped, first wins");
        assert_eq!(seq.decodes[0].input_sha256, shas[0]);
        for jobs in [2usize, 4, 8] {
            let par = resolve_with_jobs(&text, &fake_sha(text.as_bytes()), Path::new("/t"), 2.0, LIM2, &io, jobs).unwrap();
            assert_eq!(seq.decodes, par.decodes, "decode records identical at jobs={jobs}");
            assert_eq!(format!("{seq:?}"), format!("{par:?}"), "resolution identical at jobs={jobs}");
        }
    }

    // ---- real archive tiles (fixed pinned index, no env config) ----
    // Run explicitly: cargo test --offline -- --ignored real_archive. Needs the v4.16
    // sample archive at COLLECTION_REL; a missing file is a loud failure, not a skip.
    const COLLECTION_REL: &str = "../../../collection/Karl Nawrot Typefaces";
    const E2E_INDEX: &str = include_str!("space_e2e_index.tsv");

    fn e2e_resolve(style: &str, with_contract: bool) -> Result<SpaceResolution, String> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join(COLLECTION_REL).join(style);
        let dir = std::env::temp_dir().join(format!("kni-real-{}-{}", style.replace('/', "_"), std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let sha = |b: &[u8]| kni_core::cff_reader::sha256_hex(b);
        let (mut rows, mut shas) = (Vec::new(), Vec::new());
        for l in E2E_INDEX.lines().filter(|l| !l.starts_with('#') && l.split('\t').next() == Some(style)) {
            let c: Vec<&str> = l.split('\t').collect();
            let bytes = std::fs::read(root.join(c[2])).unwrap_or_else(|e| panic!("pinned tile {} missing: {e}", c[2]));
            assert_eq!(sha(&bytes), c[3], "index pin != file bytes for {}", c[2]);
            std::fs::write(dir.join(format!("s{}.png", c[1])), &bytes).unwrap();
            rows.push(format!("slope_tile {F} {} s{}.png ledger:{} {}\n", c[1], c[1], c[4], c[3]));
            shas.push(c[3].to_string());
        }
        assert!(!rows.is_empty(), "no index rows for {style}");
        // Test-declared records (NOT collection evidence): scale 1, zero kern.
        let rec = record_text("unit-regular", "f1", "1", &shas[0]);
        std::fs::write(dir.join("scale.txt"), &rec).unwrap();
        let mut spec = String::from("cp 0x20\nstyle_id unit-regular\nframe_id f1\n");
        rows.iter().for_each(|r| spec.push_str(r));
        spec.push_str(&format!("slope_kern {F} zero test-declared\nslope_max_points 16\nink_model border_median_delta 8 notdef_audit.py:INK_DELTA:a88d1ad6\n"));
        if with_contract {
            spec.push_str("renderer_contract binary_pixel_center t d f th c cl\n");
        }
        spec.push_str(&format!("shaping {F} capture-settings-1 true 0 {}\nscale_record {F} scale.txt {}\n", shas.join(","), sha(rec.as_bytes())));
        std::fs::write(dir.join("space.spec"), &spec).unwrap();
        let lim = ReadLimits { max_input_bytes: 1 << 24, max_pixels: 1 << 23, max_working_bytes: 1 << 27 };
        let r = SpaceEvidenceRef { path: dir.join("space.spec"), sha256: sha(spec.as_bytes()), limits: lim };
        let out = resolve_file(&r, 1.0);
        std::fs::remove_dir_all(&dir).ok();
        out
    }

    #[test]
    #[ignore]
    fn real_archive_marq_alternate_is_descriptive_without_a_renderer_contract() {
        let r = e2e_resolve("Marq/Alternate", false).unwrap();
        assert!(matches!(r.outcome, SpaceOutcome::MissingEvidence(_)), "{:?}", r.outcome);
        let m = r.slope.as_ref().expect("descriptive numbers kept");
        assert_eq!(m.increments_per_space_px, vec![108.0, 106.0]);
        assert!(m.advance_units_interval.is_none());
        assert!(r.receipt_lines().contains("ols_slope_px_descriptive"));
        let mut rec = String::new();
        assert!(gate(Some(&r), false, &mut rec).is_err());
    }

    #[test]
    #[ignore]
    fn real_archive_unit_regular_aliased_tiles_are_refused() {
        let r = e2e_resolve("Unit/Regular", false);
        match r {
            Ok(res) => assert!(matches!(res.outcome, SpaceOutcome::MissingEvidence(SpaceError::AliasedSlopeTiles { .. })), "{:?}", res.outcome),
            Err(e) => assert!(e.contains("slope") || e.contains("alias") || e.contains("Aliased"), "{e}"),
        }
    }
}

#[cfg(test)]
mod derive_space_tests {
    use super::*;

    #[test]
    fn basis_n_advance_when_n_present() {
        // n present: its own advance wins, whatever the other glyphs carry.
        let g = vec![(0x48u32, 700.0f64), (0x6E, 500.0), (0x61, 480.0)];
        assert_eq!(derive_space_advance(&g), Some((500.0, "n_advance")));
    }

    #[test]
    fn basis_lowercase_median_when_n_absent() {
        // no n: median of the present a-z advances (odd count: middle).
        let g = vec![(0x48u32, 700.0f64), (0x61, 400.0), (0x62, 600.0), (0x63, 500.0)];
        assert_eq!(derive_space_advance(&g), Some((500.0, "lowercase_median")));
        // even count: sorted 400, 500, 600, 700 -> mean of the middles 500, 600 -> 550.
        let g = vec![(0x61u32, 400.0f64), (0x62, 600.0), (0x63, 500.0), (0x64, 700.0)];
        assert_eq!(derive_space_advance(&g), Some((550.0, "lowercase_median")));
    }

    #[test]
    fn basis_all_glyph_median_when_no_lowercase() {
        // no a-z at all: median of every solved glyph's advance.
        let g = vec![(0x41u32, 600.0f64), (0x42, 700.0), (0x30, 500.0)];
        assert_eq!(derive_space_advance(&g), Some((600.0, "all_glyph_median")));
    }

    #[test]
    fn empty_population_derives_nothing() {
        assert_eq!(derive_space_advance(&[]), None);
    }

    #[test]
    fn gate_for_derive_keeps_measured_emit_and_skips_partial() {
        // No evidence bound: NotRequested, no receipt rows, never partial.
        let mut receipt = String::new();
        let g = gate_for_derive(None, &mut receipt);
        assert!(matches!(g, SpaceGate::NotRequested));
        assert!(receipt.is_empty(), "no rows without evidence: {receipt:?}");
        assert!(!receipt.contains("partial_output"));
    }
}
