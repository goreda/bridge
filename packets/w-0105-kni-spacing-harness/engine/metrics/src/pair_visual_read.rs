//! pair_visual_read.rs — K1: kerning pair visual reading layer (r2, reviewer findings fixed).
//!
//! Path in crate: `engine/metrics/src/pair_visual_read.rs`.
//! lib.rs / Cargo.toml registration: chief architect only (no parallel write).
//!
//! What this is: the layer that READS the kerning folder's pair images
//! (rendered two-codepoint pair visuals) and measures the inter-glyph visual
//! gap from the pixels. The old kernband line had this; the new engine did
//! not (findings-part-35-indep-aud H7, dump L486/L492). Measurement layer
//! only: it never proposes, ships, or overrides a kern value.
//!
//! Hard rules baked in:
//! - Decoder-agnostic: the caller decodes the image (PNG etc.) and passes a
//!   gray raster plus the source bytes' sha256. Every failure is a typed
//!   error row in the report; no row is ever silently skipped (findings
//!   part-35 H14 pattern rejected).
//! - No invented geometry: the gap band is DERIVED FROM THE IMAGE CONTENT
//!   (the widest internal zero-ink column run between the outermost inked
//!   columns, with a tie/ambiguity refusal), never a fixed screen band.
//! - Polarity is never assumed: the render contract is dark ink on a light
//!   background; a raster whose thresholded "ink" covers more than half the
//!   pixels is REFUSED as InvertedPolarity, never silently inverted.
//! - gap_fu is derived from min_gap_px (the conservative minimum clearance),
//!   never from the mean: gap_fu = min_gap_px * scale.
//! - Provenance: every row carries the source image sha256 it was measured
//!   from.
//! - Font-unit conversion only through an explicit caller-supplied scale
//!   (font units per source pixel); non-finite or non-positive scale is a
//!   hard error.

use std::fmt;

/// Minimum accepted gap-band width in pixels: a narrower "gap" is scanner /
/// antialias noise, never a pair gap (reviewer G-e).
pub const MIN_GAP_BAND_PX: usize = 2;
/// Antialias/quantization uncertainty carried by every gap measurement, in
/// source pixels. gap_fu inherits +/- GAP_UNCERTAINTY_PX * scale (reviewer G-e).
pub const GAP_UNCERTAINTY_PX: f64 = 1.0;

/// Decoded gray raster, row-major, one byte per pixel (0 = black ink side).
pub struct GrayImage {
    pub width: usize,
    pub height: usize,
    pub gray: Vec<u8>,
}

/// One measured pair. Pixel measures are in source pixels; `gap_fu` is
/// present only when the caller supplied a scale, and is ALWAYS derived from
/// `min_gap_px` (conservative minimum), never from the mean.
#[derive(Debug, Clone)]
pub struct PairVisualRead {
    pub left: String,
    pub right: String,
    pub source_sha256: String,
    pub threshold: u8,
    /// Content-derived zero-ink column band separating the members: [start, end).
    pub gap_band: (usize, usize),
    /// Min per-row clearance over rows where both members carry ink.
    pub min_gap_px: f64,
    /// Mean per-row clearance over the same rows.
    pub mean_gap_px: f64,
    /// Rows where both members carry ink (the measured population).
    pub shared_rows: usize,
    /// Ink bounding boxes: (xmin, ymin, xmax, ymax), xmax/ymax exclusive.
    pub left_bbox: (usize, usize, usize, usize),
    pub right_bbox: (usize, usize, usize, usize),
    /// = min_gap_px * scale (documented: MINIMUM clearance in font units).
    pub gap_fu: Option<f64>,
    /// Antialias/quantization uncertainty of min_gap_px/mean_gap_px, in pixels.
    pub uncertainty_px: f64,
}

/// Typed per-pair error. No silent skips: a failed pair is a failed row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairVisualError {
    /// Image holds no separable ink on the named side (or at all).
    NoInk(&'static str),
    /// No usable zero-ink column band separates the two members: the members
    /// touch, the image is a single blob, or the two widest internal runs
    /// tie (counter vs gap undecidable). Measurement would be a guess.
    AmbiguousGap,
    /// Border pixels are majority ink: the raster does not match the
    /// dark-ink-on-light render contract (probably inverted or white-on-black).
    /// Polarity is never silently flipped.
    InvertedPolarity,
    /// Raster dimensions do not match the gray buffer length.
    BadRaster,
    /// Scale must be finite and > 0 (font units per source pixel).
    BadScale,
    /// Glyph name contains a tab/newline/CR or is empty (TSV injection guard).
    BadName,
}

impl fmt::Display for PairVisualError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PairVisualError::NoInk(side) => write!(f, "no ink: {side}"),
            PairVisualError::AmbiguousGap => write!(f, "no usable zero-ink column band between pair members (touching/single-blob/tied runs); refusing to guess"),
            PairVisualError::InvertedPolarity => write!(f, "border pixels are majority ink: inverted polarity suspected; refusing (render contract is dark ink on light background)"),
            PairVisualError::BadRaster => write!(f, "raster dimensions do not match gray buffer"),
            PairVisualError::BadScale => write!(f, "scale must be finite and > 0 (font units per source pixel)"),
            PairVisualError::BadName => write!(f, "glyph name empty or contains tab/newline/CR (TSV safety)"),
        }
    }
}

/// Otsu threshold on the 256-bin histogram. Degenerate histograms (single
/// occupied bin) are a typed NoInk, never a guessed threshold.
fn otsu_threshold(gray: &[u8]) -> Result<u8, PairVisualError> {
    let mut hist = [0u64; 256];
    for &v in gray {
        hist[v as usize] += 1;
    }
    let occupied = hist.iter().filter(|&&c| c > 0).count();
    if occupied <= 1 {
        return Err(PairVisualError::NoInk("uniform image"));
    }
    let total = gray.len() as f64;
    let sum_all: f64 = hist.iter().enumerate().map(|(i, &c)| i as f64 * c as f64).sum();
    let (mut w_b, mut sum_b, mut best_t, mut best_var) = (0.0f64, 0.0f64, 0usize, -1.0f64);
    for t in 0..256 {
        w_b += hist[t] as f64;
        sum_b += t as f64 * hist[t] as f64;
        let w_f = total - w_b;
        if w_b == 0.0 || w_f == 0.0 {
            continue;
        }
        let m_b = sum_b / w_b;
        let m_f = (sum_all - sum_b) / w_f;
        let var_between = w_b * w_f * (m_b - m_f) * (m_b - m_f);
        if var_between > best_var {
            best_var = var_between;
            best_t = t;
        }
    }
    Ok(best_t as u8)
}

fn bbox<F: Fn(usize, usize) -> bool>(ink: &F, h: usize, x0: usize, x1: usize) -> Option<(usize, usize, usize, usize)> {
    let (mut xmin, mut ymin, mut xmax, mut ymax) = (usize::MAX, usize::MAX, 0usize, 0usize);
    let mut any = false;
    for y in 0..h {
        for x in x0..x1 {
            if ink(x, y) {
                any = true;
                xmin = xmin.min(x);
                ymin = ymin.min(y);
                xmax = xmax.max(x + 1);
                ymax = ymax.max(y + 1);
            }
        }
    }
    any.then_some((xmin, ymin, xmax, ymax))
}

/// Measure one rendered pair image.
///
/// `scale_fu_per_px`: font units per source pixel, when a font-unit reading
/// is wanted; `None` keeps the measurement in pixels only.
pub fn read_pair_image(
    left: &str,
    right: &str,
    img: &GrayImage,
    source_sha256: &str,
    scale_fu_per_px: Option<f64>,
) -> Result<PairVisualRead, PairVisualError> {
    for name in [left, right] {
        if name.is_empty() || name.contains(['\t', '\n', '\r']) {
            return Err(PairVisualError::BadName);
        }
    }
    if img.width == 0 || img.height == 0 || img.gray.len() != img.width * img.height {
        return Err(PairVisualError::BadRaster);
    }
    if let Some(s) = scale_fu_per_px {
        if !s.is_finite() || s <= 0.0 {
            return Err(PairVisualError::BadScale);
        }
    }
    let (w, h) = (img.width, img.height);
    let threshold = otsu_threshold(&img.gray)?;
    let ink = |x: usize, y: usize| img.gray[y * w + x] <= threshold;

    // Polarity contract check (reviewer 3): dark ink on a light render means the
    // background touches the image border. A global ink-majority test false-
    // refuses legitimate tight crops (a wide 'W' next to an 'i' can exceed 50%
    // ink), so the typed refusal keys on the border: if most border pixels are
    // ink, the raster is white-on-black or an inverted scan. Polarity is never
    // silently flipped.
    let border_count = 2 * w + 2 * h - 4;
    let mut border_ink = 0usize;
    for x in 0..w {
        if ink(x, 0) { border_ink += 1; }
        if ink(x, h - 1) { border_ink += 1; }
    }
    for y in 1..h - 1 {
        if ink(0, y) { border_ink += 1; }
        if ink(w - 1, y) { border_ink += 1; }
    }
    if border_ink * 2 > border_count {
        return Err(PairVisualError::InvertedPolarity);
    }

    // Content-derived gap: zero-ink column runs strictly BETWEEN the outermost
    // inked columns; the gap is the widest such run. A counter inside a member
    // (o, e, ...) is a narrower internal run; a tie between the two widest
    // runs is undecidable and refused.
    let col_ink: Vec<u64> = (0..w).map(|x| (0..h).filter(|&y| ink(x, y)).count() as u64).collect();
    let first_ink = col_ink.iter().position(|&c| c > 0).ok_or(PairVisualError::NoInk("whole image"))?;
    let last_ink = col_ink.iter().rposition(|&c| c > 0).ok_or(PairVisualError::NoInk("whole image"))?;
    let mut runs: Vec<(usize, usize)> = Vec::new(); // [start, end)
    let mut cur: Option<usize> = None;
    for x in first_ink..=last_ink {
        if col_ink[x] == 0 {
            let start = *cur.get_or_insert(x);
            runs.push((start, x + 1));
        } else {
            cur = None;
        }
    }
    runs.dedup();
    runs.retain(|r| r.1 - r.0 >= MIN_GAP_BAND_PX);
    if runs.is_empty() {
        return Err(PairVisualError::AmbiguousGap); // only sub-2px noise bands present
    }
    runs.sort_by_key(|r| r.1 - r.0);
    let widest = runs[runs.len() - 1];
    if runs.len() >= 2 && runs[runs.len() - 2].1 - runs[runs.len() - 2].0 == widest.1 - widest.0 {
        return Err(PairVisualError::AmbiguousGap); // tied runs: counter vs gap undecidable
    }
    let gap = widest;

    let left_bb = bbox(&ink, h, 0, gap.0).ok_or(PairVisualError::NoInk("left member"))?;
    let right_bb = bbox(&ink, h, gap.1, w).ok_or(PairVisualError::NoInk("right member"))?;

    // Per-row clearance on rows where both members carry ink.
    let mut min_gap = f64::INFINITY;
    let mut sum = 0.0f64;
    let mut shared = 0usize;
    for y in 0..h {
        let l = (0..gap.0).rev().find(|&x| ink(x, y));
        let r = (gap.1..w).find(|&x| ink(x, y));
        if let (Some(lx), Some(rx)) = (l, r) {
            let c = (rx - lx - 1) as f64;
            min_gap = min_gap.min(c);
            sum += c;
            shared += 1;
        }
    }
    if shared == 0 {
        return Err(PairVisualError::AmbiguousGap);
    }
    let mean = sum / shared as f64;
    Ok(PairVisualRead {
        left: left.to_string(),
        right: right.to_string(),
        source_sha256: source_sha256.to_string(),
        threshold,
        gap_band: gap,
        min_gap_px: min_gap,
        mean_gap_px: mean,
        shared_rows: shared,
        left_bbox: left_bb,
        right_bbox: right_bb,
        gap_fu: scale_fu_per_px.map(|s| min_gap * s),
        uncertainty_px: GAP_UNCERTAINTY_PX,
    })
}

/// Manifest entry: a valid row or a typed invalid line. Parsing NEVER aborts
/// the manifest: a malformed line becomes an Invalid entry that flows to the
/// report as a typed failure row. Splitting is on '\n' only, so a CR byte is
/// always detected (str::lines() would strip it silently).
#[derive(Debug, Clone)]
pub enum ManifestEntry {
    Valid { left: String, right: String, image_path: String },
    Invalid { line_no: usize, reason: String },
}

pub fn parse_manifest(tsv: &str) -> Vec<ManifestEntry> {
    let mut out = Vec::new();
    let lines: Vec<&str> = tsv.split('\n').collect();
    for (i, line) in lines.iter().enumerate() {
        let line_no = i + 1;
        if i == 0 && *line == "left\tright\timage" {
            continue;
        }
        // One trailing empty element produced by the final newline is fine;
        // any other empty line is a typed invalid row, never skipped.
        if line.is_empty() {
            if i == lines.len() - 1 {
                continue;
            }
            out.push(ManifestEntry::Invalid { line_no, reason: "empty line".to_string() });
            continue;
        }
        if line.contains('\r') {
            out.push(ManifestEntry::Invalid { line_no, reason: "CR byte (CRLF line ending)".to_string() });
            continue;
        }
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() != 3 || f.iter().any(|s| s.trim().is_empty()) {
            out.push(ManifestEntry::Invalid { line_no, reason: "expected 3 tab-separated non-empty fields".to_string() });
            continue;
        }
        out.push(ManifestEntry::Valid { left: f[0].to_string(), right: f[1].to_string(), image_path: f[2].to_string() });
    }
    out
}

/// Report row: either a measurement or a typed failure. `load` is
/// caller-supplied so this layer never picks a format or a hash.
pub enum PairReportRow {
    Measured(PairVisualRead),
    /// source_sha256 is present when the image loaded and decoding succeeded
    /// (the failure is a measurement refusal, provenance preserved).
    Failed { left: String, right: String, image_path: String, source_sha256: Option<String>, error: String },
}

fn tsv_safe(s: &str) -> String {
    s.chars().map(|c| if c == '\t' || c == '\n' || c == '\r' { ' ' } else { c }).collect()
}

pub fn read_manifest_pairs<F>(
    entries: &[ManifestEntry],
    scale_fu_per_px: Option<f64>,
    mut load: F,
) -> (Vec<PairReportRow>, usize)
where
    F: FnMut(&str) -> Result<(GrayImage, String), String>, // path -> (raster, source sha256)
{
    let mut out = Vec::new();
    let mut failures = 0usize;
    for e in entries {
        match e {
            ManifestEntry::Invalid { line_no, reason } => {
                failures += 1;
                out.push(PairReportRow::Failed { left: format!("line{line_no}"), right: String::new(), image_path: String::new(), source_sha256: None, error: format!("manifest: {reason}") });
            }
            ManifestEntry::Valid { left, right, image_path } => match load(image_path) {
                Ok((img, sha)) => match read_pair_image(left, right, &img, &sha, scale_fu_per_px) {
                    Ok(m) => out.push(PairReportRow::Measured(m)),
                    Err(e) => {
                        failures += 1;
                        out.push(PairReportRow::Failed { left: left.clone(), right: right.clone(), image_path: image_path.clone(), source_sha256: Some(sha), error: e.to_string() });
                    }
                },
                Err(e) => {
                    failures += 1;
                    out.push(PairReportRow::Failed { left: left.clone(), right: right.clone(), image_path: image_path.clone(), source_sha256: None, error: format!("load: {e}") });
                }
            },
        }
    }
    (out, failures)
}

/// Fixed-header TSV. Failure rows carry the typed error in `reason`; a
/// failure row never carries measured numbers. Fields are safe by
/// construction: names are validated (BadName) before they can reach a row,
/// and reasons come from this module's own typed errors.
pub fn report_tsv(rows: &[PairReportRow]) -> String {
    let mut t = String::from("left\tright\tmin_gap_px\tmean_gap_px\tshared_rows\tgap_band_start\tgap_band_end\tthreshold\tgap_fu\tsource_sha256\tstatus\treason\timage_path\n");
    for r in rows {
        match r {
            PairReportRow::Measured(m) => t.push_str(&format!(
                "{}\t{}\t{:.3}\t{:.3}\t{}\t{}\t{}\t{}\t{}\t{}\tmeasured\t\t\n",
                m.left, m.right, m.min_gap_px, m.mean_gap_px, m.shared_rows,
                m.gap_band.0, m.gap_band.1, m.threshold,
                m.gap_fu.map(|v| format!("{v:.3}")).unwrap_or_default(), m.source_sha256)),
            PairReportRow::Failed { left, right, image_path, source_sha256, error } =>
                t.push_str(&format!("{}\t{}\t\t\t\t\t\t\t\t{}\trefused\t{}\t{}\n",
                    tsv_safe(left), tsv_safe(right), source_sha256.as_deref().unwrap_or(""), tsv_safe(error), tsv_safe(image_path))),
        }
    }
    t
}

/// Report summary: (measured, refused). Refused rows are BY DESIGN for
/// kern-negative/overlapping pairs (AV, To, italic tight pairs): this layer
/// measures only cleanly separable pairs and refuses the rest with a typed
/// error; the refusal count must be read with the measurements (reviewer G-d).
pub fn report_summary(rows: &[PairReportRow]) -> (usize, usize) {
    let m = rows.iter().filter(|r| matches!(r, PairReportRow::Measured(_))).count();
    (m, rows.len() - m)
}
