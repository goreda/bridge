//! Rasterized IoU between a drawn outline (rings) and its source glyph tile. (v2)
//! SOURCE ONLY: written without compiling or running anything (UNRUN).
//!
//! Rules kept here:
//! - Every job carries its own `FrameEvidence`. The source mask and the outline
//!   raster of one job share that ONE resolved `Frame`. Jobs with different
//!   origins are fine: each row records its own frame pin. Missing evidence is a
//!   typed error, never a default (no assumed scale source).
//! - No hardcoded pass/fail threshold. `target` is only reported.
//! - Public per-job errors (frame resolution, tile decode, outline, rasterization)
//!   become `Err` rows; they do not abort the batch. A worker thread panic or an
//!   allocation failure is a catastrophic bug, NOT a typed failure: it is fatal
//!   (see `run_jobs`). There is no resource cap yet (canvas w*h, flatten steps and
//!   edge count are caller-bounded); the cap contract is intentionally left open.
//! - The report checks inventory as exact SET equality: the caller supplies the
//!   expected (style, glyph) keys; every key must appear in exactly one row or
//!   exactly one exclusion. Duplicate jobs are listed in a separate diagnostics
//!   list and never enlarge the population.
//! - All geometry is validated: input points, transformed points, cubic
//!   intermediates, edge deltas and scanline x crossings must be finite, else
//!   `NonFiniteGeometry`. The clipped `coverage_mask` is parity-only; `iou_glyph` measures outline ink outside the canvas (bounded by max_pixels).
//! - Pixel semantics are INTENDED to equal `economy_eval::render_iou` (pixel
//!   centre sampling, non-zero winding, ink = gray < threshold, image
//!   x = x/k + ox, y = -y/k - oy). Parity is NOT established: the differential
//!   tests below compare against a transcription of that algorithm and are UNRUN.
//! - Ids are escaped to one canonical form before they reach TSV or receipt cells.
use crate::economy_eval::sha256_hex;
use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
use crate::reference_transfer::canonical_bytes;
use std::collections::BTreeSet;
use std::fmt::Write as _;

// ---------------- errors ----------------
#[derive(Clone, Debug, PartialEq)]
pub enum IouError {
    /// scale_k was not supplied. The scale source is never assumed.
    MissingScaleEvidence,
    MissingOriginEvidence,
    MissingThreshold,
    MissingFlattenSteps,
    MissingCanvas,
    InvalidScale(String),
    InvalidOrigin(String),
    InvalidFlattenSteps,
    BadSourceBuffer { glyph: String, detail: String },
    CanvasMismatch { glyph: String, tile: (usize, usize), frame: (usize, usize) },
    /// Non-finite input, transformed point, cubic intermediate, edge delta or crossing.
    NonFiniteGeometry { glyph: String, stage: String },
    /// Ring's last point differs from its start (exact f64 equality).
    UnclosedRing { glyph: String, ring: usize },
    EmptyOutline { glyph: String },
    EmptyUnion { glyph: String },
    GlyphIdMismatch { tile: String, outline: String },
    BadGlyphId,
    BadStyle,
    DuplicateKey { style: String, glyph: String },
    BadTarget,
    NoResults,
    SourceDecode { glyph: String, detail: String },
    MissingResourceLimits,
    /// Emit-frame translation was not supplied (pass (0.0,0.0) explicitly when none applies).
    MissingTranslation,
    /// The emitted font bytes could not be read back, or the glyph is absent.
    OutlineReadback { glyph: String, detail: String },
    /// The source PNG could not be read from disk (OS error text in `detail`).
    SourceRead { glyph: String, detail: String },
    /// The PNG on disk no longer hashes to the pin recorded when stage 1 fitted it.
    SourcePinMismatch { glyph: String, stage1_pin: String, now: String },
    /// No stage-1 pin was recorded for this glyph, so the tile cannot be tied to the fit.
    SourcePinMissing { glyph: String },
    /// The translation claimed from the ledgers differs from the one read back from the shipped bytes.
    TranslationDisagrees { glyph: String, claimed: String, readback: String },
    /// A caller-supplied size exceeds the explicit limit. `what` names the quantity.
    ResourceLimitExceeded { glyph: String, what: String, value: u64, limit: u64 },
    /// Rows of one report must come from one OutlineStage.
    MixedStages,
    /// A GlyphIou failed its own invariants.
    InvalidMeasurement { glyph: String, detail: String },
    /// Inventory is not an exact partition of the expected keys. `sample` holds up to 5
    /// offending escaped `style/glyph` keys.
    InventoryViolation { kind: String, count: usize, sample: Vec<String> },
    /// A frame pin on a row does not match the row's frame.
    FramePinMismatch { glyph: String },
}

impl std::fmt::Display for IouError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingScaleEvidence => write!(f, "MissingScaleEvidence"),
            Self::MissingOriginEvidence => write!(f, "MissingOriginEvidence"),
            Self::MissingThreshold => write!(f, "MissingThreshold"),
            Self::MissingFlattenSteps => write!(f, "MissingFlattenSteps"),
            Self::MissingCanvas => write!(f, "MissingCanvas"),
            Self::InvalidScale(s) => write!(f, "InvalidScale({s})"),
            Self::InvalidOrigin(s) => write!(f, "InvalidOrigin({s})"),
            Self::InvalidFlattenSteps => write!(f, "InvalidFlattenSteps"),
            Self::BadSourceBuffer { glyph, detail } => write!(f, "BadSourceBuffer({glyph}: {detail})"),
            Self::CanvasMismatch { glyph, tile, frame } => write!(f, "CanvasMismatch({glyph}: tile {}x{} frame {}x{})", tile.0, tile.1, frame.0, frame.1),
            Self::NonFiniteGeometry { glyph, stage } => write!(f, "NonFiniteGeometry({glyph}: {stage})"),
            Self::UnclosedRing { glyph, ring } => write!(f, "UnclosedRing({glyph}: ring {ring})"),
            Self::EmptyOutline { glyph } => write!(f, "EmptyOutline({glyph})"),
            Self::EmptyUnion { glyph } => write!(f, "EmptyUnion({glyph})"),
            Self::GlyphIdMismatch { tile, outline } => write!(f, "GlyphIdMismatch(tile {tile} outline {outline})"),
            Self::BadGlyphId => write!(f, "BadGlyphId"),
            Self::BadStyle => write!(f, "BadStyle"),
            Self::DuplicateKey { style, glyph } => write!(f, "DuplicateKey({style}/{glyph})"),
            Self::BadTarget => write!(f, "BadTarget"),
            Self::NoResults => write!(f, "NoResults"),
            Self::SourceDecode { glyph, detail } => write!(f, "SourceDecode({glyph}: {detail})"),
            Self::MissingResourceLimits => write!(f, "MissingResourceLimits"),
            Self::MissingTranslation => write!(f, "MissingTranslation"),
            Self::OutlineReadback { glyph, detail } => write!(f, "OutlineReadback({glyph}: {detail})"),
            Self::SourceRead { glyph, detail } => write!(f, "SourceRead({glyph}: {detail})"),
            Self::SourcePinMismatch { glyph, stage1_pin, now } => write!(f, "SourcePinMismatch({glyph}: stage1 {stage1_pin} != now {now})"),
            Self::SourcePinMissing { glyph } => write!(f, "SourcePinMissing({glyph})"),
            Self::TranslationDisagrees { glyph, claimed, readback } => write!(f, "TranslationDisagrees({glyph}: claimed {claimed} != readback {readback})"),
            Self::ResourceLimitExceeded { glyph, what, value, limit } => write!(f, "ResourceLimitExceeded({glyph}: {what} {value} > {limit})"),
            Self::MixedStages => write!(f, "MixedStages"),
            Self::InvalidMeasurement { glyph, detail } => write!(f, "InvalidMeasurement({glyph}: {detail})"),
            Self::InventoryViolation { kind, count, sample } => write!(f, "InventoryViolation({kind}: {count}; {})", sample.join(",")),
            Self::FramePinMismatch { glyph } => write!(f, "FramePinMismatch({glyph})"),
        }
    }
}
impl std::error::Error for IouError {}

fn nonfinite(glyph: &str, stage: &str) -> IouError {
    IouError::NonFiniteGeometry { glyph: glyph.to_string(), stage: stage.to_string() }
}

// ---------------- canonical id escaping ----------------
/// Keeps ASCII alphanumerics and `.` `_` `-` `+`; every other UTF-8 byte (space, tab,
/// slash, percent, control, non-ASCII) becomes `%XX`. Empty becomes `%EMPTY`.
/// The result has no whitespace, tab, newline or slash, so `style/glyph` is unambiguous
/// and a TSV cell can never split.
pub fn escape_id(s: &str) -> String {
    if s.is_empty() { return "%EMPTY".to_string(); }
    let mut o = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b == b'.' || b == b'_' || b == b'-' || b == b'+' { o.push(b as char); }
        else { let _ = write!(o, "%{:02X}", b); }
    }
    o
}
fn clean_text(s: &str) -> String { s.chars().map(|c| if c.is_control() { ' ' } else { c }).collect() }

// ---------------- frame evidence ----------------
/// Explicit upper bounds on caller-supplied sizes. No default: the caller must choose.
/// Checked by `measure_job` before hashing, cloning or building anything that scales
/// with the input: canvas pixels, flatten steps, gray length/dims, PNG byte length and IHDR
/// dims, estimated flattened edge count. NOT covered: memory used INSIDE `decode_png_gray`
/// (zlib inflate etc.). Byte and IHDR caps narrow it, but there is no memory-safety
/// guarantee for generic untrusted PNG input. Not a quality threshold.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceLimits {
    pub max_pixels: u64,
    pub max_flatten_steps: usize,
    pub max_edges: u64,
    /// Byte-length cap on PNG input, checked before decoding.
    pub max_png_bytes: u64,
    /// Peak working-byte budget for the bounded PNG decode (major payload only:
    /// idat/raw/recon/gray; not allocator/RSS/Huffman scratch). Required, no default.
    pub max_png_working_bytes: u64,
}

/// Caller-supplied evidence. Every field is optional so a missing value surfaces as a
/// typed error from `resolve`, not as a silent default.
#[derive(Clone, Debug, Default)]
pub struct FrameEvidence {
    /// Font units per source pixel (outline = pixel * scale_k). Required.
    pub scale_k: Option<f64>,
    /// Content-bbox origin in capture pixel space (y up), as `MeasuredContour::origin_x/origin_y`.
    pub origin: Option<(f64, f64)>,
    /// Ink when gray < threshold; must be the threshold the source capture used.
    pub ink_threshold: Option<u8>,
    /// Samples per cubic span.
    pub flatten_steps: Option<usize>,
    /// (width, height) of the tile canvas.
    pub canvas: Option<(usize, usize)>,
    /// Font-unit translation (dx, dy) applied between the capture frame and the shipped outline
    /// (baseline shift, lsb translation). Required; (0.0, 0.0) is an explicit value.
    /// Source-frame point = (x - dx, y - dy) before the scale/origin transform.
    pub translation: Option<(f64, f64)>,
    /// Required: see `ResourceLimits`.
    pub limits: Option<ResourceLimits>,
}

/// Validated frame, used for BOTH the source mask and the outline raster of one job.
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    scale_k: f64,
    ox: f64,
    oy: f64,
    threshold: u8,
    steps: usize,
    w: usize,
    h: usize,
    tx: f64,
    ty: f64,
    limits: ResourceLimits,
}

impl FrameEvidence {
    pub fn resolve(&self) -> Result<Frame, IouError> {
        let k = self.scale_k.ok_or(IouError::MissingScaleEvidence)?;
        if !(k.is_finite() && k > 0.0) { return Err(IouError::InvalidScale(format!("{k:?}"))); }
        let (ox, oy) = self.origin.ok_or(IouError::MissingOriginEvidence)?;
        if !(ox.is_finite() && oy.is_finite()) { return Err(IouError::InvalidOrigin(format!("({ox:?},{oy:?})"))); }
        let threshold = self.ink_threshold.ok_or(IouError::MissingThreshold)?;
        let steps = self.flatten_steps.ok_or(IouError::MissingFlattenSteps)?;
        if steps == 0 { return Err(IouError::InvalidFlattenSteps); }
        let (w, h) = self.canvas.ok_or(IouError::MissingCanvas)?;
        if w == 0 || h == 0 || w.checked_mul(h).is_none() {
            return Err(IouError::BadSourceBuffer { glyph: String::new(), detail: format!("canvas {w}x{h}") });
        }
        let (tx, ty) = self.translation.ok_or(IouError::MissingTranslation)?;
        if !(tx.is_finite() && ty.is_finite()) { return Err(IouError::InvalidOrigin(format!("translation ({tx:?},{ty:?})"))); }
        let limits = self.limits.ok_or(IouError::MissingResourceLimits)?;
        let rl = |what: &str, value: u64, limit: u64| IouError::ResourceLimitExceeded { glyph: String::new(), what: what.to_string(), value, limit };
        if steps > limits.max_flatten_steps { return Err(rl("flatten_steps", steps as u64, limits.max_flatten_steps as u64)); }
        let px = (w as u64).checked_mul(h as u64).ok_or_else(|| rl("pixels", u64::MAX, limits.max_pixels))?;
        if px > limits.max_pixels { return Err(rl("pixels", px, limits.max_pixels)); }
        Ok(Frame { scale_k: k, ox, oy, threshold, steps, w, h, tx, ty, limits })
    }
}

impl Frame {
    /// Text pin of every parameter that shaped the measurement.
    pub fn pin(&self) -> String {
        format!("iou-frame-v4|K={:?}|origin=({:?},{:?})|thr={}|steps={}|canvas={}x{}|translation=({:?},{:?})|limits=px{}/steps{}/edges{}/png{}/pngwork{}", self.scale_k, self.ox, self.oy, self.threshold, self.steps, self.w, self.h, self.tx, self.ty, self.limits.max_pixels, self.limits.max_flatten_steps, self.limits.max_edges, self.limits.max_png_bytes, self.limits.max_png_working_bytes)
    }
    pub fn canvas(&self) -> (usize, usize) { (self.w, self.h) }
}

// ---------------- source tile ----------------
#[derive(Clone, Debug)]
pub struct SourceTile {
    glyph_id: String,
    w: usize,
    h: usize,
    gray: Vec<u8>,
}

impl SourceTile {
    pub fn from_gray(glyph_id: &str, w: usize, h: usize, gray: Vec<u8>) -> Result<Self, IouError> {
        if glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        match w.checked_mul(h) {
            Some(n) if n > 0 && n == gray.len() => Ok(Self { glyph_id: glyph_id.to_string(), w, h, gray }),
            _ => Err(IouError::BadSourceBuffer { glyph: glyph_id.to_string(), detail: format!("{w}x{h} vs {} bytes", gray.len()) }),
        }
    }
    /// PNG decode through the shared bounded adapter with caller-supplied explicit
    /// limits and a recorded origin. There is no default-limits entry point.
    /// Within-limit output equals the previous decode; larger inputs are refused.
    pub fn from_png(
        glyph_id: &str,
        png: &[u8],
        limits: &crate::capture::DecodeLimits,
        origin: crate::bounded_png_adapter::LimitsOrigin,
    ) -> Result<(Self, crate::bounded_png_adapter::BoundedPngReceipt), IouError> {
        let d = crate::bounded_png_adapter::decode_gray(crate::bounded_png_adapter::Route::Iou, png, limits, origin)
            .map_err(|e| IouError::SourceDecode { glyph: glyph_id.to_string(), detail: e.to_string() })?;
        let receipt = d.receipt.clone();
        Ok((Self::from_gray(glyph_id, d.width, d.height, d.gray)?, receipt))
    }
    pub fn glyph_id(&self) -> &str { &self.glyph_id }
    pub fn dims(&self) -> (usize, usize) { (self.w, self.h) }
}

// ---------------- rasterization ----------------
fn fin(p: &Point) -> bool { p.x.is_finite() && p.y.is_finite() }

/// Estimated flattened edge count against the limit; allocation-free.
fn check_edges(frame: &Frame, glyph: &str, rings: &[ReferenceRing]) -> Result<(), IouError> {
    let mut est: u64 = 0;
    for r in rings {
        for sp in &r.spans {
            est = est.saturating_add(match sp { Span::Line { .. } => 1, Span::Cubic { .. } => frame.steps as u64 });
        }
        est = est.saturating_add(1);
    }
    if est > frame.limits.max_edges {
        return Err(IouError::ResourceLimitExceeded { glyph: glyph.to_string(), what: "edges".into(), value: est, limit: frame.limits.max_edges });
    }
    Ok(())
}

/// Outline edges in image pixel space (y down). Every value checked finite.
fn image_edges(frame: &Frame, glyph: &str, rings: &[ReferenceRing]) -> Result<Vec<(Point, Point)>, IouError> {
    let to_img = |p: Point| -> Result<Point, IouError> {
        if !fin(&p) { return Err(nonfinite(glyph, "input point")); }
        let q = Point { x: (p.x - frame.tx) / frame.scale_k + frame.ox, y: -(p.y - frame.ty) / frame.scale_k - frame.oy };
        if !fin(&q) { return Err(nonfinite(glyph, "transformed point")); }
        Ok(q)
    };
    check_edges(frame, glyph, rings)?;
    let mut edges = Vec::new();
    for (ri, r) in rings.iter().enumerate() {
        if r.spans.is_empty() { return Err(IouError::EmptyOutline { glyph: glyph.to_string() }); }
        // Share the evaluator canonicalizer, including its typed arithmetic-domain refusal.
        let canon_r = crate::economy_eval::canon(r).map_err(|e| nonfinite(glyph, &format!("canonicalization refused: {e:?}")))?;
        let r = &canon_r;
        let mut pts: Vec<Point> = vec![to_img(r.start)?];
        let mut cur = r.start;
        for s in &r.spans {
            match s {
                Span::Line { end } => { pts.push(to_img(*end)?); cur = *end; }
                Span::Cubic { control_one: a, control_two: b, end } => {
                    if !(fin(a) && fin(b)) { return Err(nonfinite(glyph, "input point")); }
                    for i in 1..=frame.steps {
                        if i == frame.steps { pts.push(to_img(*end)?); continue; }
                        let t = i as f64 / frame.steps as f64;
                        let u = 1.0 - t;
                        let (w0, w1, w2, w3) = (u * u * u, 3.0 * u * u * t, 3.0 * u * t * t, t * t * t);
                        let q = Point {
                            x: w0 * cur.x + w1 * a.x + w2 * b.x + w3 * end.x,
                            y: w0 * cur.y + w1 * a.y + w2 * b.y + w3 * end.y,
                        };
                        if !fin(&q) { return Err(nonfinite(glyph, "cubic intermediate")); }
                        pts.push(to_img(q)?);
                    }
                    cur = *end;
                }
            }
        }
        let (first, last) = (r.start, cur);
        if !(first.x == last.x && first.y == last.y) { return Err(IouError::UnclosedRing { glyph: glyph.to_string(), ring: ri }); }
        let n = pts.len();
        for i in 0..n { edges.push((pts[i], pts[(i + 1) % n])); }
    }
    Ok(edges)
}

/// Non-zero-winding coverage at pixel centres, w*h row-major, CLIPPED to the canvas (used for in-canvas parity).
/// `iou_glyph` does not use this clipped view: ink outside the canvas is measured by `coverage_extent`.
pub fn coverage_mask(frame: &Frame, glyph: &str, rings: &[ReferenceRing]) -> Result<Vec<bool>, IouError> {
    let edges = image_edges(frame, glyph, rings)?;
    coverage_region(&edges, glyph, 0, 0, frame.w, frame.h, frame.limits.max_pixels)
}

/// Coverage over the region [x0, x0+w) x [y0, y0+h) of the image plane (pixel centres, absolute coordinates, no shifting of values).
/// Everything that sizes an allocation is checked BEFORE it: exact w*h against `budget`, and the exact number of scanline
/// crossings (sum of rows each edge spans inside the region) against the same `budget` (memory is O(budget): one table entry per crossing plus one row header per row, rows <= budget).
fn coverage_region(edges: &[(Point, Point)], glyph: &str, x0: i64, y0: i64, w: usize, h: usize, budget: u64) -> Result<Vec<bool>, IouError> {
    let rl = |what: &str, value: u64| IouError::ResourceLimitExceeded { glyph: glyph.to_string(), what: what.into(), value, limit: budget };
    let px = w.checked_mul(h).ok_or_else(|| rl("region_pixels", u64::MAX))?;
    if px as u128 > budget as u128 { return Err(rl("region_pixels", px as u64)); }
    let (xf0, yf0) = (x0 as f64, y0 as f64);
    let mut crossings: u64 = 0;
    for (a, b) in edges {
        if a.y == b.y { continue; }
        let (lo, hi) = if a.y < b.y { (a.y, b.y) } else { (b.y, a.y) };
        let r0 = (lo - 0.5).ceil().max(yf0);
        let r1 = (hi - 0.5).ceil().min(yf0 + h as f64);
        if r0 < r1 { crossings = crossings.saturating_add((r1 - r0) as u64); }
        if crossings > budget { return Err(rl("scanline_crossings", crossings)); }
    }
    let mut rows: Vec<Vec<(f64, i32)>> = vec![Vec::new(); h];
    for (a, b) in edges {
        if a.y == b.y { continue; }
        let (dx, dy) = (b.x - a.x, b.y - a.y);
        if !(dx.is_finite() && dy.is_finite()) { return Err(nonfinite(glyph, "edge delta")); }
        let (lo, hi) = if a.y < b.y { (a.y, b.y) } else { (b.y, a.y) };
        // rows with absolute index r, centre yc = r + 0.5 and lo <= yc < hi
        let r0 = (lo - 0.5).ceil().max(yf0);
        let r1 = (hi - 0.5).ceil().min(yf0 + h as f64);
        if !(r0 < r1) { continue; }
        let dir = if b.y > a.y { 1 } else { -1 };
        let (mut r, end) = (r0 as i64, r1 as i64);
        while r < end {
            let yc = r as f64 + 0.5;
            let x = a.x + (yc - a.y) / dy * dx;
            if !x.is_finite() { return Err(nonfinite(glyph, "scanline crossing")); }
            rows[(r - y0) as usize].push((x, dir));
            r += 1;
        }
    }
    let (wf_lo, wf_hi) = (xf0, xf0 + w as f64);
    let mut out = vec![false; w * h];
    for (j, xs) in rows.iter_mut().enumerate() {
        xs.sort_by(|p, q| p.0.total_cmp(&q.0));
        let mut wind = 0i32;
        for k in 0..xs.len() {
            wind += xs[k].1;
            if wind != 0 && k + 1 < xs.len() {
                let lo = ((xs[k].0 - 0.5).ceil().max(wf_lo).min(wf_hi) as i64 - x0) as usize;
                let hi = ((xs[k + 1].0 - 0.5).ceil().max(wf_lo).min(wf_hi) as i64 - x0) as usize;
                let mut i = lo;
                while i < hi { out[j * w + i] = true; i += 1; }
            }
        }
    }
    Ok(out)
}

/// Coverage over the canvas UNION the outline's own pixel extent, so ink that falls outside the source canvas is not clamped away.
/// Returns (x0, y0, w, h, mask) with x0,y0 <= 0 and the canvas inside the region. The region size is bounded by
/// `limits.max_pixels`; a larger extent is a typed `ResourceLimitExceeded`, never a silent clip.
pub fn coverage_extent(frame: &Frame, glyph: &str, rings: &[ReferenceRing]) -> Result<(i64, i64, usize, usize, Vec<bool>), IouError> {
    let edges = image_edges(frame, glyph, rings)?;
    let (mut minx, mut miny, mut maxx, mut maxy) = (0.0f64, 0.0f64, frame.w as f64, frame.h as f64);
    for (a, b) in &edges {
        for p in [a, b] { minx = minx.min(p.x); maxx = maxx.max(p.x); miny = miny.min(p.y); maxy = maxy.max(p.y); }
    }
    let limit = frame.limits.max_pixels;
    let too_big = |value: u64| IouError::ResourceLimitExceeded { glyph: glyph.to_string(), what: "outline_extent_pixels".into(), value, limit };
    // Exact integer representation before any cast. The region contains the canvas and the origin, and the canvas has at least one
    // row/column, so any region whose area fits `max_pixels` has every coordinate within +-max_pixels. The bound is therefore derived from
    // the limit, capped at the exact-integer range of f64 (2^(MANTISSA_DIGITS-1), so pixel centres r+0.5 stay exact); anything beyond is refused, never saturated.
    let lim = limit.min(1u64 << (f64::MANTISSA_DIGITS - 1)) as f64;
    let (fx0, fy0, fx1, fy1) = (minx.floor(), miny.floor(), maxx.ceil(), maxy.ceil());
    if !(fx0 >= -lim && fy0 >= -lim && fx1 <= lim && fy1 <= lim) { return Err(too_big(u64::MAX)); }
    let (x0, y0, x1, y1) = (fx0 as i64, fy0 as i64, fx1 as i64, fy1 as i64);
    let (w, h) = (u64::try_from(x1 - x0).map_err(|_| too_big(u64::MAX))?, u64::try_from(y1 - y0).map_err(|_| too_big(u64::MAX))?);
    let px = (w as u128) * (h as u128);
    if px > limit as u128 { return Err(too_big(u64::try_from(px).unwrap_or(u64::MAX))); }
    let (w, h) = (usize::try_from(w).map_err(|_| too_big(u64::MAX))?, usize::try_from(h).map_err(|_| too_big(u64::MAX))?);
    w.checked_mul(h).ok_or_else(|| too_big(u64::MAX))?; // usize-exact allocation size (32-bit targets)
    let mask = coverage_region(&edges, glyph, x0, y0, w, h, limit)?;
    Ok((x0, y0, w, h, mask))
}

// ---------------- per-glyph measurement ----------------
/// Counts and ratio of one glyph. Fields are private; the only constructor validates.
#[derive(Clone, Debug, PartialEq)]
pub struct GlyphIou {
    glyph_id: String,
    intersection: u64,
    union: u64,
    source_ink: u64,
    outline_ink: u64,
    iou: f64,
}

impl GlyphIou {
    pub fn from_counts(glyph_id: &str, intersection: u64, source_ink: u64, outline_ink: u64) -> Result<Self, IouError> {
        let bad = |d: &str| IouError::InvalidMeasurement { glyph: glyph_id.to_string(), detail: d.to_string() };
        if glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        if intersection > source_ink || intersection > outline_ink { return Err(bad("intersection exceeds an operand")); }
        let union = source_ink.checked_add(outline_ink).ok_or_else(|| bad("overflow"))? - intersection;
        if union == 0 { return Err(IouError::EmptyUnion { glyph: glyph_id.to_string() }); }
        let iou = intersection as f64 / union as f64;
        let g = Self { glyph_id: glyph_id.to_string(), intersection, union, source_ink, outline_ink, iou };
        g.validate()?;
        Ok(g)
    }
    /// Recomputes every invariant; used again by `build_report`.
    pub fn validate(&self) -> Result<(), IouError> {
        let bad = |d: &str| IouError::InvalidMeasurement { glyph: self.glyph_id.clone(), detail: d.to_string() };
        if self.glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        if self.intersection > self.source_ink || self.intersection > self.outline_ink { return Err(bad("intersection exceeds an operand")); }
        let u = self.source_ink.checked_add(self.outline_ink).and_then(|s| s.checked_sub(self.intersection)).ok_or_else(|| bad("union arithmetic"))?;
        if u != self.union || u == 0 { return Err(bad("union count")); }
        if !self.iou.is_finite() || !(0.0..=1.0).contains(&self.iou) { return Err(bad("iou outside 0..=1")); }
        if self.iou != self.intersection as f64 / self.union as f64 { return Err(bad("iou != intersection/union")); }
        Ok(())
    }
    pub fn glyph_id(&self) -> &str { &self.glyph_id }
    pub fn iou(&self) -> f64 { self.iou }
    pub fn intersection(&self) -> u64 { self.intersection }
    pub fn union(&self) -> u64 { self.union }
    pub fn source_ink(&self) -> u64 { self.source_ink }
    pub fn outline_ink(&self) -> u64 { self.outline_ink }
}

/// IoU of one outline against its tile under one frame.
pub fn iou_glyph(frame: &Frame, tile: &SourceTile, outline: &DrawnGlyph) -> Result<GlyphIou, IouError> {
    if tile.glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
    if tile.glyph_id != outline.glyph_id {
        return Err(IouError::GlyphIdMismatch { tile: tile.glyph_id.clone(), outline: outline.glyph_id.clone() });
    }
    let id = &tile.glyph_id;
    if (tile.w, tile.h) != (frame.w, frame.h) {
        return Err(IouError::CanvasMismatch { glyph: id.clone(), tile: (tile.w, tile.h), frame: (frame.w, frame.h) });
    }
    if outline.rings.is_empty() { return Err(IouError::EmptyOutline { glyph: id.clone() }); }
    // Outline ink outside the canvas has no source ink to match: it counts in the union (never clamped away).
    let (x0, y0, rw, rh, cover) = coverage_extent(frame, id, &outline.rings)?;
    let (mut inter, mut src, mut out) = (0u64, 0u64, 0u64);
    for &c in cover.iter() { if c { out += 1; } }
    for j in 0..frame.h {
        for i in 0..frame.w {
            let s = tile.gray[j * frame.w + i] < frame.threshold;
            if s { src += 1; }
            let (ri, rj) = ((i as i64 - x0) as usize, (j as i64 - y0) as usize);
            debug_assert!(ri < rw && rj < rh);
            if s && cover[rj * rw + ri] { inter += 1; }
        }
    }
    GlyphIou::from_counts(id, inter, src, out)
}

// ---------------- jobs and rows ----------------
#[derive(Clone, Debug)]
pub enum SourceInput {
    Png(Vec<u8>),
    Gray { w: usize, h: usize, gray: Vec<u8> },
}

/// Where the outline came from. Recorded per row; never mixed silently.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutlineStage { PreEmit, OtfReadback }
impl OutlineStage {
    fn label(self) -> &'static str { match self { Self::PreEmit => "pre-emit", Self::OtfReadback => "otf-readback" } }
}

/// One unit of work. Build failures upstream (outline read-back, etc.) are passed as `Err`
/// so they become failed rows instead of vanishing.
#[derive(Clone, Debug)]
pub struct IouJob {
    pub style: String,
    pub glyph_id: String,
    pub source: SourceInput,
    pub outline: Result<DrawnGlyph, IouError>,
    pub evidence: FrameEvidence,
    pub stage: OutlineStage,
}

#[derive(Clone, Debug)]
pub struct IouRow {
    style: String,
    glyph_id: String,
    stage: OutlineStage,
    frame: Option<Frame>,
    frame_pin: Option<String>,
    tile_sha256: String,
    outline_sha256: Option<String>,
    result: Result<GlyphIou, IouError>,
}

impl IouRow {
    pub fn style(&self) -> &str { &self.style }
    pub fn glyph_id(&self) -> &str { &self.glyph_id }
    pub fn result(&self) -> &Result<GlyphIou, IouError> { &self.result }
    pub fn frame_pin(&self) -> Option<&str> { self.frame_pin.as_deref() }
    pub fn stage(&self) -> OutlineStage { self.stage }
    pub fn tile_sha256(&self) -> &str { &self.tile_sha256 }
    pub fn outline_sha256(&self) -> Option<&str> { self.outline_sha256.as_deref() }
    fn key(&self) -> (String, String) { (self.style.clone(), self.glyph_id.clone()) }
}

fn source_sha(src: &SourceInput) -> String {
    match src {
        SourceInput::Png(b) => sha256_hex(b),
        // dims bound to the content digest without concatenating a second copy of the pixels
        SourceInput::Gray { w, h, gray } => sha256_hex(format!("gray|{w}x{h}|{}", sha256_hex(gray)).as_bytes()),
    }
}

/// No allocation proportional to the input; checks lengths and caps only.
fn precheck_source(glyph: &str, src: &SourceInput, l: &ResourceLimits) -> Result<(), IouError> {
    let over = |what: &str, value: u64, limit: u64| IouError::ResourceLimitExceeded { glyph: glyph.to_string(), what: what.to_string(), value, limit };
    match src {
        SourceInput::Png(b) => {
            if b.len() as u64 > l.max_png_bytes { return Err(over("png bytes", b.len() as u64, l.max_png_bytes)); }
            // IHDR width/height (big-endian u32 at bytes 16..24) before decoding
            if b.len() >= 24 && &b[..8] == b"\x89PNG\r\n\x1a\n" {
                let w = u32::from_be_bytes([b[16], b[17], b[18], b[19]]) as u64;
                let h = u32::from_be_bytes([b[20], b[21], b[22], b[23]]) as u64;
                if w * h > l.max_pixels { return Err(over("source pixels", w * h, l.max_pixels)); }
            }
        }
        SourceInput::Gray { w, h, gray } => {
            let px = (*w as u64).saturating_mul(*h as u64);
            if px > l.max_pixels { return Err(over("source pixels", px, l.max_pixels)); }
            if w.checked_mul(*h) != Some(gray.len()) {
                return Err(IouError::BadSourceBuffer { glyph: glyph.to_string(), detail: format!("{w}x{h} vs {} bytes", gray.len()) });
            }
        }
    }
    Ok(())
}

/// Order: frame resolve, then source caps, then outline edge cap, and only then hashing and
/// decoding. Rows rejected before hashing carry "UNHASHED". Every public input problem is
/// returned inside the row; nothing here aborts the batch.
fn measure_job(j: &IouJob) -> IouRow {
    let frame = j.evidence.resolve();
    let (frame_ok, frame_pin) = match &frame { Ok(f) => (Some(f.clone()), Some(f.pin())), Err(_) => (None, None) };
    let mut tile_sha256 = "UNHASHED".to_string();
    let mut outline_sha256: Option<String> = None;
    let result = (|| -> Result<GlyphIou, IouError> {
        if j.style.is_empty() { return Err(IouError::BadStyle); }
        if j.glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        // An upstream outline/source failure carried in the job is the row's cause: report it before frame
        // or source checks can replace it with a secondary error from placeholder evidence.
        if let Err(e) = &j.outline { return Err(e.clone()); }
        let f = frame.clone()?;
        precheck_source(&j.glyph_id, &j.source, &f.limits)?;
        if let Ok(o) = &j.outline { check_edges(&f, &j.glyph_id, &o.rings)?; }
        // caps passed: hashing is now bounded by the limits
        tile_sha256 = source_sha(&j.source);
        if let Ok(o) = &j.outline { outline_sha256 = Some(sha256_hex(&canonical_bytes(&o.glyph_id, &o.rings))); }
        let tile = match &j.source {
            SourceInput::Png(b) => {
                let dl = crate::capture::DecodeLimits {
                    max_input_bytes: usize::try_from(f.limits.max_png_bytes).map_err(|_| IouError::SourceDecode { glyph: j.glyph_id.clone(), detail: "max_png_bytes exceeds usize".into() })?,
                    max_pixels: usize::try_from(f.limits.max_pixels).map_err(|_| IouError::SourceDecode { glyph: j.glyph_id.clone(), detail: "max_pixels exceeds usize".into() })?,
                    max_working_bytes: usize::try_from(f.limits.max_png_working_bytes).map_err(|_| IouError::SourceDecode { glyph: j.glyph_id.clone(), detail: "max_png_working_bytes exceeds usize".into() })?,
                };
                SourceTile::from_png(&j.glyph_id, b, &dl, crate::bounded_png_adapter::LimitsOrigin::Explicit("iou FrameEvidence.limits (ResourceLimits)".to_string()))?.0
            }
            SourceInput::Gray { w, h, gray } => SourceTile::from_gray(&j.glyph_id, *w, *h, gray.clone())?,
        };
        let outline = j.outline.as_ref().map_err(|e| e.clone())?;
        iou_glyph(&f, &tile, outline)
    })();
    IouRow { style: j.style.clone(), glyph_id: j.glyph_id.clone(), stage: j.stage, frame: frame_ok, frame_pin, tile_sha256, outline_sha256, result }
}

/// A job whose (style, glyph) key was already used by an earlier job. Diagnostic only:
/// it is not a row and not part of the population.
#[derive(Clone, Debug, PartialEq)]
pub struct DuplicateDiagnostic { pub style: String, pub glyph_id: String, pub job_index: usize }

#[derive(Clone, Debug)]
pub struct RunOutput {
    /// One row per distinct key (first occurrence), in job order.
    pub rows: Vec<IouRow>,
    pub duplicates: Vec<DuplicateDiagnostic>,
}

/// Run all jobs. Per-job input problems never abort: they become `Err` rows. FATAL cases,
/// deliberately not converted to failures: a worker thread panic (`join().expect`) and
/// allocation failure (unbounded canvas / flatten steps / edge count are not capped here;
/// the caller must bound them). Row order equals job order for any worker count. Repeated
/// keys keep the first occurrence as the row; later ones go to `duplicates`.
pub fn run_jobs(jobs: &[IouJob], workers: Option<usize>) -> RunOutput {
    let n = jobs.len();
    let wanted = workers.unwrap_or_else(|| std::thread::available_parallelism().map(|x| x.get()).unwrap_or(1));
    let nw = wanted.max(1).min(n.max(1));
    let mut all: Vec<IouRow> = Vec::with_capacity(n);
    if nw <= 1 {
        all.extend(jobs.iter().map(measure_job));
    } else {
        let chunk = (n + nw - 1) / nw;
        std::thread::scope(|s| {
            let handles: Vec<_> = jobs.chunks(chunk).map(|c| s.spawn(move || c.iter().map(measure_job).collect::<Vec<_>>())).collect();
            for h in handles { all.extend(h.join().expect("iou worker panicked (fatal bug, not a typed failure)")); }
        });
    }
    let mut seen: BTreeSet<(String, String)> = BTreeSet::new();
    let mut rows = Vec::with_capacity(n);
    let mut duplicates = Vec::new();
    for (i, r) in all.into_iter().enumerate() {
        if seen.insert(r.key()) { rows.push(r); }
        else { duplicates.push(DuplicateDiagnostic { style: r.style, glyph_id: r.glyph_id, job_index: i }); }
    }
    RunOutput { rows, duplicates }
}

// ---------------- report ----------------
/// A glyph deliberately not measured (e.g. blank tile = glyph absent from the font).
#[derive(Clone, Debug)]
pub struct Exclusion { pub style: String, pub glyph_id: String, pub reason: String }

#[derive(Clone, Debug, PartialEq)]
pub struct IouSummary {
    pub scope: String,
    pub total: usize,
    pub measured: usize,
    pub failed: usize,
    pub excluded: usize,
    pub mean: Option<f64>,
    pub median: Option<f64>,
    pub min: Option<f64>,
    pub target: Option<f64>,
    pub below_target: Option<usize>,
}

fn summarize(scope: &str, rows: &[&IouRow], excluded: usize, target: Option<f64>) -> IouSummary {
    let mut v: Vec<f64> = rows.iter().filter_map(|r| r.result.as_ref().ok().map(|g| g.iou)).collect();
    let measured = v.len();
    let (mean, median, min) = if measured == 0 { (None, None, None) } else {
        let mean = v.iter().sum::<f64>() / measured as f64;
        v.sort_by(|a, b| a.total_cmp(b));
        let med = if measured % 2 == 1 { v[measured / 2] } else { (v[measured / 2 - 1] + v[measured / 2]) / 2.0 };
        (Some(mean), Some(med), Some(v[0]))
    };
    let below = target.map(|t| v.iter().filter(|x| **x < t).count());
    IouSummary { scope: scope.to_string(), total: rows.len() + excluded, measured, failed: rows.len() - measured, excluded, mean, median, min, target, below_target: below }
}

#[derive(Clone, Debug)]
pub struct IouReport {
    rows: Vec<IouRow>,
    exclusions: Vec<Exclusion>,
    duplicates: Vec<DuplicateDiagnostic>,
    stage: Option<OutlineStage>,
    expected_total: usize,
    /// Distinct frame pins in first-seen order; rows refer to them by index.
    frames: Vec<String>,
    overall: IouSummary,
    per_style: Vec<IouSummary>,
}

fn show_key(k: &(String, String)) -> String { format!("{}/{}", escape_id(&k.0), escape_id(&k.1)) }
fn violation(kind: &str, keys: &[(String, String)]) -> IouError {
    IouError::InventoryViolation { kind: kind.to_string(), count: keys.len(), sample: keys.iter().take(5).map(show_key).collect() }
}

/// Revalidates everything, then builds the report.
/// Inventory contract: `expected_keys` is the manifest population (unique, non-empty).
/// Every expected key appears in exactly one row OR exactly one exclusion; no row or
/// exclusion key is outside the set; no key is repeated across or within rows/exclusions.
/// `duplicates` are diagnostics only and do not count toward the population.
/// An all-excluded run (no rows) is a valid report: measured 0, failed 0, excluded N.
/// `target` is reported only.
pub fn build_report(expected_keys: &[(String, String)], rows: Vec<IouRow>, exclusions: Vec<Exclusion>, duplicates: Vec<DuplicateDiagnostic>, target: Option<f64>) -> Result<IouReport, IouError> {
    if let Some(t) = target { if !t.is_finite() { return Err(IouError::BadTarget); } }
    if expected_keys.is_empty() { return Err(IouError::NoResults); }
    let mut expected: BTreeSet<(String, String)> = BTreeSet::new();
    let mut dup_expected = Vec::new();
    for k in expected_keys {
        if k.0.is_empty() { return Err(IouError::BadStyle); }
        if k.1.is_empty() { return Err(IouError::BadGlyphId); }
        if !expected.insert(k.clone()) { dup_expected.push(k.clone()); }
    }
    if !dup_expected.is_empty() { return Err(violation("duplicate expected key", &dup_expected)); }

    let stages: BTreeSet<&'static str> = rows.iter().map(|r| r.stage.label()).collect();
    if stages.len() > 1 { return Err(IouError::MixedStages); }
    let stage = rows.first().map(|r| r.stage);
    let mut row_keys: BTreeSet<(String, String)> = BTreeSet::new();
    let mut dup_rows = Vec::new();
    let mut frames: Vec<String> = Vec::new();
    for r in &rows {
        if r.style.is_empty() { return Err(IouError::BadStyle); }
        if r.glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        match (&r.frame, &r.frame_pin) {
            (Some(f), Some(p)) => {
                if &f.pin() != p { return Err(IouError::FramePinMismatch { glyph: r.glyph_id.clone() }); }
                if !frames.contains(p) { frames.push(p.clone()); }
            }
            (None, None) => {}
            _ => return Err(IouError::FramePinMismatch { glyph: r.glyph_id.clone() }),
        }
        if let Ok(g) = &r.result {
            g.validate()?;
            if g.glyph_id != r.glyph_id { return Err(IouError::InvalidMeasurement { glyph: r.glyph_id.clone(), detail: "row id differs from measurement id".into() }); }
            if r.frame.is_none() || r.outline_sha256.is_none() { return Err(IouError::FramePinMismatch { glyph: r.glyph_id.clone() }); }
        }
        // Err rows count toward the inventory exactly like Ok rows.
        if !row_keys.insert(r.key()) { dup_rows.push(r.key()); }
    }
    if !dup_rows.is_empty() { return Err(violation("duplicate row key", &dup_rows)); }

    let mut ex_keys: BTreeSet<(String, String)> = BTreeSet::new();
    let mut dup_ex = Vec::new();
    for e in &exclusions {
        if e.style.is_empty() { return Err(IouError::BadStyle); }
        if e.glyph_id.is_empty() { return Err(IouError::BadGlyphId); }
        if !ex_keys.insert((e.style.clone(), e.glyph_id.clone())) { dup_ex.push((e.style.clone(), e.glyph_id.clone())); }
    }
    if !dup_ex.is_empty() { return Err(violation("duplicate exclusion key", &dup_ex)); }

    let both: Vec<(String, String)> = row_keys.intersection(&ex_keys).cloned().collect();
    if !both.is_empty() { return Err(violation("key in both a row and an exclusion", &both)); }
    let covered: BTreeSet<(String, String)> = row_keys.union(&ex_keys).cloned().collect();
    let unexpected: Vec<(String, String)> = covered.difference(&expected).cloned().collect();
    if !unexpected.is_empty() { return Err(violation("key outside expected set", &unexpected)); }
    let missing: Vec<(String, String)> = expected.difference(&covered).cloned().collect();
    if !missing.is_empty() { return Err(violation("expected key has no row or exclusion", &missing)); }
    // here: rows and exclusions partition `expected` exactly.

    let all: Vec<&IouRow> = rows.iter().collect();
    let overall = summarize("all", &all, exclusions.len(), target);
    let mut order: Vec<String> = Vec::new();
    for k in expected_keys { if !order.contains(&k.0) { order.push(k.0.clone()); } }
    let per_style = order.iter().map(|s| {
        let sub: Vec<&IouRow> = rows.iter().filter(|r| &r.style == s).collect();
        let ex = exclusions.iter().filter(|e| &e.style == s).count();
        summarize(&escape_id(s), &sub, ex, target)
    }).collect();
    Ok(IouReport { rows, exclusions, duplicates, stage, expected_total: expected.len(), frames, overall, per_style })
}

fn opt(v: Option<f64>) -> String { v.map_or("NA".to_string(), |x| format!("{x:.9}")) }

impl IouReport {
    pub fn overall(&self) -> &IouSummary { &self.overall }
    pub fn per_style(&self) -> &[IouSummary] { &self.per_style }
    pub fn rows(&self) -> &[IouRow] { &self.rows }
    fn frame_index(&self, r: &IouRow) -> String {
        r.frame_pin.as_ref().and_then(|p| self.frames.iter().position(|x| x == p)).map_or("NA".to_string(), |i| i.to_string())
    }

    /// Per style/glyph TSV. Every cell is escaped or a number, so cells cannot split.
    pub fn to_tsv(&self) -> String {
        let mut s = String::new();
        for (i, p) in self.frames.iter().enumerate() { let _ = writeln!(s, "# frame {i} {p}"); }
        let _ = writeln!(s, "# stage {}", self.stage.map_or("none", |x| x.label()));
        let _ = writeln!(s, "# expected_total {} rows {} excluded {} duplicate_job_diagnostics {}", self.expected_total, self.rows.len(), self.exclusions.len(), self.duplicates.len());
        for d in &self.duplicates { let _ = writeln!(s, "# duplicate {}/{} job_index {}", escape_id(&d.style), escape_id(&d.glyph_id), d.job_index); }
        let _ = writeln!(s, "style\tglyph\tstatus\tiou\tintersection\tunion\tsource_ink\toutline_ink\tframe\tstage\ttile_sha256\toutline_sha256\terror");
        for r in &self.rows {
            let (st, g) = (escape_id(&r.style), escape_id(&r.glyph_id));
            let tail = format!("{}\t{}\t{}\t{}", self.frame_index(r), r.stage.label(), r.tile_sha256, r.outline_sha256.as_deref().unwrap_or("NA"));
            match &r.result {
                Ok(m) => { let _ = writeln!(s, "{st}\t{g}\tmeasured\t{:.9}\t{}\t{}\t{}\t{}\t{tail}\t", m.iou, m.intersection, m.union, m.source_ink, m.outline_ink); }
                Err(e) => { let _ = writeln!(s, "{st}\t{g}\tfailed\tNA\tNA\tNA\tNA\tNA\t{tail}\t{}", escape_text_cell(&e.to_string())); }
            }
        }
        for e in &self.exclusions {
            let _ = writeln!(s, "{}\t{}\texcluded\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\t{}", escape_id(&e.style), escape_id(&e.glyph_id), escape_text_cell(&e.reason));
        }
        s
    }

    /// Receipt lines: `iou frame`, `iou glyph <id> <val>`, `iou error`, `iou excluded`, `iou summary`.
    /// <id> is `esc(style)/esc(glyph)` when more than one style is present, else `esc(glyph)`;
    /// escaping removes spaces and slashes, so the id is a single unambiguous token.
    pub fn to_receipt(&self) -> String {
        let multi = self.per_style.len() > 1;
        let rid = |st: &str, g: &str| if multi { format!("{}/{}", escape_id(st), escape_id(g)) } else { escape_id(g) };
        let mut s = String::new();
        for (i, p) in self.frames.iter().enumerate() { let _ = writeln!(s, "iou frame {i} {p}"); }
        let _ = writeln!(s, "iou stage {}", self.stage.map_or("none", |x| x.label()));
        let _ = writeln!(s, "iou inventory expected={} rows={} excluded={} duplicate_job_diagnostics={}", self.expected_total, self.rows.len(), self.exclusions.len(), self.duplicates.len());
        for d in &self.duplicates { let _ = writeln!(s, "iou duplicate {} job_index={}", rid(&d.style, &d.glyph_id), d.job_index); }
        for r in &self.rows {
            let id = rid(&r.style, &r.glyph_id);
            match &r.result {
                Ok(m) => { let _ = writeln!(s, "iou glyph {} {:.9}", id, m.iou); }
                Err(e) => { let _ = writeln!(s, "iou error {} {}", id, clean_text(&e.to_string())); }
            }
        }
        for e in &self.exclusions { let _ = writeln!(s, "iou excluded {} {}", rid(&e.style, &e.glyph_id), clean_text(&e.reason)); }
        for sm in self.per_style.iter().chain(std::iter::once(&self.overall)) {
            let _ = writeln!(s, "iou summary {} total={} measured={} failed={} excluded={} mean={} median={} min={} target={} below_target={}",
                sm.scope, sm.total, sm.measured, sm.failed, sm.excluded, opt(sm.mean), opt(sm.median), opt(sm.min),
                opt(sm.target), sm.below_target.map_or("NA".to_string(), |x| x.to_string()));
        }
        s
    }
}

fn escape_text_cell(s: &str) -> String { clean_text(s).replace('\t', " ") }

// ---------------- tests (UNRUN) ----------------
#[cfg(test)]
mod tests {
    // UNRUN: written without compiling or running; run only when the owner lifts the ban.
    use super::*;

    fn ev(w: usize, h: usize) -> FrameEvidence {
        FrameEvidence { scale_k: Some(1.0), origin: Some((0.0, 0.0)), ink_threshold: Some(128), flatten_steps: Some(8), canvas: Some((w, h)), translation: Some((0.0, 0.0)), limits: Some(ResourceLimits { max_pixels: 1_000_000, max_flatten_steps: 64, max_edges: 100_000, max_png_bytes: 1_000_000, max_png_working_bytes: 1 << 26 }) }
    }
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// Rect in IMAGE coordinates (font y = -image y when origin = 0, K = 1).
    fn rect(id: &str, x0: f64, y0: f64, x1: f64, y1: f64) -> DrawnGlyph {
        let q = |x: f64, y: f64| p(x, -y);
        DrawnGlyph { glyph_id: id.into(), rings: vec![ReferenceRing { start: q(x0, y0), spans: vec![
            Span::Line { end: q(x1, y0) }, Span::Line { end: q(x1, y1) }, Span::Line { end: q(x0, y1) }, Span::Line { end: q(x0, y0) } ] }] }
    }
    fn tile_rect(id: &str, w: usize, h: usize, x0: usize, y0: usize, x1: usize, y1: usize) -> SourceTile {
        let mut g = vec![255u8; w * h];
        for j in y0..y1 { for i in x0..x1 { g[j * w + i] = 0; } }
        SourceTile::from_gray(id, w, h, g).unwrap()
    }
    fn gray_of(t: &SourceTile) -> SourceInput { SourceInput::Gray { w: t.w, h: t.h, gray: t.gray.clone() } }
    fn job(style: &str, id: &str, t: &SourceTile, o: DrawnGlyph, e: FrameEvidence) -> IouJob {
        IouJob { style: style.into(), glyph_id: id.into(), source: gray_of(t), outline: Ok(o), evidence: e, stage: OutlineStage::PreEmit }
    }

    // ---- transcription of economy_eval::render_iou's rasterizer (all edges x all rows), mask only ----
    fn legacy_mask(frame: &Frame, rings: &[ReferenceRing]) -> Vec<bool> {
        let (w, h) = (frame.w, frame.h);
        let mut edges: Vec<(Point, Point)> = Vec::new();
        for r in rings {
            let mut pts = vec![r.start];
            let mut cur = r.start;
            for s in &r.spans {
                match s {
                    Span::Line { end } => { pts.push(*end); cur = *end; }
                    Span::Cubic { control_one: a, control_two: b, end } => {
                        for i in 1..=frame.steps {
                            let t = i as f64 / frame.steps as f64; let u = 1.0 - t;
                            let (w0, w1, w2, w3) = (u*u*u, 3.0*u*u*t, 3.0*u*t*t, t*t*t);
                            if i == frame.steps { pts.push(*end); } else {
                                pts.push(p(w0*cur.x + w1*a.x + w2*b.x + w3*end.x, w0*cur.y + w1*a.y + w2*b.y + w3*end.y));
                            }
                        }
                        cur = *end;
                    }
                }
            }
            pts.pop();
            let img: Vec<Point> = pts.iter().map(|q| p((q.x - frame.tx) / frame.scale_k + frame.ox, -(q.y - frame.ty) / frame.scale_k - frame.oy)).collect();
            for i in 0..img.len() { edges.push((img[i], img[(i + 1) % img.len()])); }
        }
        let mut out = vec![false; w * h];
        for j in 0..h {
            let yc = j as f64 + 0.5;
            let mut xs: Vec<(f64, i32)> = Vec::new();
            for (a, b) in &edges {
                if (a.y <= yc) != (b.y <= yc) {
                    let x = a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x);
                    xs.push((x, if b.y > a.y { 1 } else { -1 }));
                }
            }
            xs.sort_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
            let mut wind = 0;
            for k in 0..xs.len() {
                wind += xs[k].1;
                if wind != 0 && k + 1 < xs.len() {
                    let lo = (xs[k].0 - 0.5).ceil().max(0.0) as usize;
                    let hi = ((xs[k + 1].0 - 0.5).ceil().max(0.0) as usize).min(w);
                    for i in lo..hi { out[j * w + i] = true; }
                }
            }
        }
        out
    }
    fn same_mask(e: FrameEvidence, rings: Vec<ReferenceRing>) {
        let f = e.resolve().unwrap();
        assert_eq!(coverage_mask(&f, "g", &rings).unwrap(), legacy_mask(&f, &rings));
    }
    fn circle(cx: f64, cy: f64, r: f64, ccw: bool) -> ReferenceRing {
        let k = 0.5522847498 * r;
        let (a, b, c, d) = (p(cx + r, cy), p(cx, cy + r), p(cx - r, cy), p(cx, cy - r));
        if ccw { ReferenceRing { start: a, spans: vec![
            Span::Cubic { control_one: p(a.x, a.y + k), control_two: p(b.x + k, b.y), end: b },
            Span::Cubic { control_one: p(b.x - k, b.y), control_two: p(c.x, c.y + k), end: c },
            Span::Cubic { control_one: p(c.x, c.y - k), control_two: p(d.x - k, d.y), end: d },
            Span::Cubic { control_one: p(d.x + k, d.y), control_two: p(a.x, a.y - k), end: a } ] } }
        else { ReferenceRing { start: a, spans: vec![
            Span::Cubic { control_one: p(a.x, a.y - k), control_two: p(d.x + k, d.y), end: d },
            Span::Cubic { control_one: p(d.x - k, d.y), control_two: p(c.x, c.y - k), end: c },
            Span::Cubic { control_one: p(c.x, c.y + k), control_two: p(b.x - k, b.y), end: b },
            Span::Cubic { control_one: p(b.x + k, b.y), control_two: p(a.x, a.y + k), end: a } ] } }
    }

    // ---- differential mask parity fixtures (bit-exact vs transcription) ----
    #[test]
    fn parity_centre_on_edge() {
        // image edges exactly on pixel centres (y = 2.5, 6.5; x = 2.5, 6.5)
        same_mask(ev(10, 10), rect("g", 2.5, 2.5, 6.5, 6.5).rings);
        same_mask(ev(10, 10), rect("g", 2.0, 2.5, 7.5, 6.0).rings);
    }
    #[test]
    fn parity_cubic_closure_and_counter() {
        same_mask(ev(40, 40), vec![circle(20.0, -20.0, 15.0, true)]);
        same_mask(ev(40, 40), vec![circle(20.0, -20.0, 15.0, true), circle(20.0, -20.0, 6.0, false)]);
        // same-direction inner ring (no hole under non-zero)
        same_mask(ev(40, 40), vec![circle(20.0, -20.0, 15.0, true), circle(20.0, -20.0, 6.0, true)]);
    }
    #[test]
    fn parity_self_intersection() {
        let q = |x: f64, y: f64| p(x, -y);
        let bow = ReferenceRing { start: q(1.0, 1.0), spans: vec![Span::Line { end: q(9.0, 9.0) }, Span::Line { end: q(9.0, 1.0) }, Span::Line { end: q(1.0, 9.0) }, Span::Line { end: q(1.0, 1.0) }] };
        same_mask(ev(10, 10), vec![bow]);
    }
    #[test]
    fn parity_negative_origin_and_clipping() {
        let mut e = ev(10, 10); e.origin = Some((-3.5, 2.25));
        same_mask(e.clone(), rect("g", -5.0, -4.0, 14.0, 13.0).rings);
        e.scale_k = Some(0.5);
        same_mask(e, vec![circle(3.0, -3.0, 20.0, true)]);
        let mut e2 = ev(10, 10); e2.origin = Some((4.0, -4.0));
        same_mask(e2, rect("g", -30.0, -30.0, 30.0, 30.0).rings);
    }

    // ---- canvas clip: off-canvas outline ink is measured, never clamped away ----
    #[test]
    fn off_canvas_outline_ink_counts_in_the_union() {
        let f = ev(10, 10).resolve().unwrap();
        // source ink 1..5 x 1..5 (16 px); outline covers the same box plus 20 more columns to the right, mostly off canvas
        let tile = tile_rect("a", 10, 10, 1, 1, 5, 5);
        let inside = iou_glyph(&f, &tile, &rect("a", 1.0, 1.0, 5.0, 5.0)).unwrap();
        assert_eq!(inside.iou(), 1.0);
        let wide = iou_glyph(&f, &tile, &rect("a", 1.0, 1.0, 25.0, 5.0)).unwrap();
        // the old clamped measure would have seen only columns 1..10 inside the canvas
        assert_eq!(wide.intersection(), 16);
        assert_eq!(wide.outline_ink(), 24 * 4, "outline ink includes the part outside the canvas");
        assert!(wide.iou() < 0.2);
        // fully off canvas: no source overlap, union is real ink, not an EmptyUnion or a clamped zero
        let off = iou_glyph(&f, &tile, &rect("a", 20.0, 20.0, 30.0, 30.0)).unwrap();
        assert_eq!((off.intersection(), off.outline_ink()), (0, 100));
        // negative side
        let neg = iou_glyph(&f, &tile, &rect("a", -9.0, 1.0, 5.0, 5.0)).unwrap();
        assert_eq!(neg.outline_ink(), 14 * 4);
        assert_eq!(neg.intersection(), 16);
    }
    #[test]
    fn extent_integer_checks_and_crossing_budget_precede_allocation() {
        let f = ev(10, 10).resolve().unwrap();
        let tile = tile_rect("a", 10, 10, 1, 1, 5, 5);
        // beyond 2^31 / near 2^64 area: typed refusal, no saturating cast, no allocation
        for far in [1.0e10, 1.8446744073709552e19, 1.0e300] {
            assert!(matches!(coverage_extent(&f, "a", &rect("a", 1.0, 1.0, far, 5.0).rings), Err(ref e) if matches!(e, IouError::ResourceLimitExceeded { .. } | IouError::NonFiniteGeometry { .. })), "{far} {:?}", coverage_extent(&f, "a", &rect("a", 1.0, 1.0, far, 5.0).rings).map(|x| x.2));
            let r = coverage_extent(&f, "a", &rect("a", -far, 1.0, 5.0, 5.0).rings); assert!(matches!(r, Err(IouError::ResourceLimitExceeded { .. } | IouError::NonFiniteGeometry { .. })), "{far} {:?}", r.map(|x| x.2));
        }
        // exact boundary: region area == max_pixels passes, one more fails
        let mut e = ev(10, 10); e.limits = Some(ResourceLimits { max_pixels: 110, max_flatten_steps: 64, max_edges: 100_000, max_png_bytes: 1_000_000, max_png_working_bytes: 1 << 26 });
        let f2 = e.resolve().unwrap();
        assert!(coverage_extent(&f2, "a", &rect("a", 1.0, 1.0, 11.0, 5.0).rings).is_ok());
        assert!(matches!(coverage_extent(&f2, "a", &rect("a", 1.0, 1.0, 12.0, 5.0).rings), Err(IouError::ResourceLimitExceeded { .. })));
        // crossing work: many tall edges inside a small region exceed the derived budget before the row table is built
        let edges: Vec<(Point, Point)> = (0..50).map(|i| (Point { x: i as f64, y: 0.0 }, Point { x: i as f64, y: 10.0 })).collect();
        assert!(matches!(coverage_region(&edges, "a", 0, 0, 10, 10, 100), Err(IouError::ResourceLimitExceeded { what, .. }) if what == "scanline_crossings"));
        assert!(coverage_region(&edges, "a", 0, 0, 10, 10, 500).is_ok());
        let _ = tile;
    }
    #[test]
    fn extent_is_bounded_by_max_pixels_and_inside_matches_clipped_mask() {
        let mut e = ev(10, 10); e.limits = Some(ResourceLimits { max_pixels: 400, max_flatten_steps: 64, max_edges: 100_000, max_png_bytes: 1_000_000, max_png_working_bytes: 1 << 26 });
        let f = e.resolve().unwrap();
        let tile = tile_rect("a", 10, 10, 1, 1, 5, 5);
        assert!(matches!(iou_glyph(&f, &tile, &rect("a", 1.0, 1.0, 1000.0, 5.0)), Err(IouError::ResourceLimitExceeded { .. })));
        // an outline inside the canvas: extent mask restricted to the canvas equals the clipped mask
        let f2 = ev(10, 10).resolve().unwrap();
        let g = rect("a", 2.0, 3.0, 7.0, 8.0);
        let (x0, y0, w, h, m) = coverage_extent(&f2, "a", &g.rings).unwrap();
        assert_eq!((x0, y0, w, h), (0, 0, 10, 10));
        assert_eq!(m, coverage_mask(&f2, "a", &g.rings).unwrap());
    }

    // ---- evidence ----
    #[test]
    fn missing_evidence_is_typed() {
        let mut e = ev(8, 8); e.scale_k = None; assert_eq!(e.resolve(), Err(IouError::MissingScaleEvidence));
        let mut e = ev(8, 8); e.origin = None; assert_eq!(e.resolve(), Err(IouError::MissingOriginEvidence));
        let mut e = ev(8, 8); e.ink_threshold = None; assert_eq!(e.resolve(), Err(IouError::MissingThreshold));
        let mut e = ev(8, 8); e.flatten_steps = None; assert_eq!(e.resolve(), Err(IouError::MissingFlattenSteps));
        let mut e = ev(8, 8); e.canvas = None; assert_eq!(e.resolve(), Err(IouError::MissingCanvas));
        let mut e = ev(8, 8); e.scale_k = Some(f64::NAN); assert!(matches!(e.resolve(), Err(IouError::InvalidScale(_))));
        e.scale_k = Some(0.0); assert!(matches!(e.resolve(), Err(IouError::InvalidScale(_))));
    }

    // ---- finite-but-overflow ----
    #[test]
    fn subnormal_scale_overflows_transform() {
        let mut e = ev(10, 10); e.scale_k = Some(5e-324);
        let f = e.resolve().unwrap();
        let r = iou_glyph(&f, &tile_rect("a", 10, 10, 1, 1, 5, 5), &rect("a", 1.0, 1.0, 5.0, 5.0));
        assert!(matches!(r, Err(IouError::NonFiniteGeometry { .. })));
    }
    #[test]
    fn huge_origin_overflows_transform() {
        let mut e = ev(10, 10); e.origin = Some((f64::MAX, 0.0));
        let f = e.resolve().unwrap();
        let r = iou_glyph(&f, &tile_rect("a", 10, 10, 1, 1, 5, 5), &rect("a", f64::MAX, 1.0, f64::MAX, 5.0));
        assert!(matches!(r, Err(IouError::NonFiniteGeometry { .. })));
    }
    #[test]
    fn edge_delta_overflow_is_error_not_silent_x() {
        let f = ev(10, 10).resolve().unwrap();
        let q = |x: f64, y: f64| p(x, -y);
        let g = DrawnGlyph { glyph_id: "a".into(), rings: vec![ReferenceRing { start: q(1.0, -1.0e308), spans: vec![
            Span::Line { end: q(1.0, 1.0e308) }, Span::Line { end: q(5.0, 1.0e308) }, Span::Line { end: q(1.0, -1.0e308) } ] }] };
        assert!(matches!(iou_glyph(&f, &tile_rect("a", 10, 10, 1, 1, 5, 5), &g), Err(IouError::NonFiniteGeometry { .. })));
    }
    #[test]
    fn cubic_control_overflow_is_error() {
        let f = ev(10, 10).resolve().unwrap();
        let g = DrawnGlyph { glyph_id: "a".into(), rings: vec![ReferenceRing { start: p(0.0, 0.0), spans: vec![
            Span::Cubic { control_one: p(f64::MAX, f64::MAX), control_two: p(f64::MAX, f64::MAX), end: p(0.0, 0.0) } ] }] };
        let r = iou_glyph(&f, &tile_rect("a", 10, 10, 1, 1, 5, 5), &g);
        // never a silent wrong number: either a typed error, or a measurement that passed every finite check
        if let Err(e) = &r { assert!(matches!(e, IouError::NonFiniteGeometry { .. } | IouError::EmptyUnion { .. })); }
    }
    #[test]
    fn nan_input_and_unclosed_and_empty_typed() {
        let f = ev(10, 10).resolve().unwrap();
        let t = tile_rect("a", 10, 10, 1, 1, 5, 5);
        let mut g = rect("a", 1.0, 1.0, 5.0, 5.0); g.rings[0].start.x = f64::NAN;
        assert!(matches!(iou_glyph(&f, &t, &g), Err(IouError::NonFiniteGeometry { .. })));
        let mut u = rect("a", 1.0, 1.0, 5.0, 5.0); u.rings[0].spans.pop();
        assert!(matches!(iou_glyph(&f, &t, &u), Err(IouError::UnclosedRing { .. })));
        assert!(matches!(iou_glyph(&f, &t, &DrawnGlyph { glyph_id: "a".into(), rings: vec![] }), Err(IouError::EmptyOutline { .. })));
    }

    // ---- measurement ----
    #[test]
    fn source_binding_errors_are_distinct_typed_variants() {
        let all = [
            IouError::SourceRead { glyph: "g".into(), detail: "d".into() },
            IouError::SourcePinMismatch { glyph: "g".into(), stage1_pin: "a".into(), now: "b".into() },
            IouError::SourcePinMissing { glyph: "g".into() },
            IouError::SourceDecode { glyph: "g".into(), detail: "d".into() },
            IouError::TranslationDisagrees { glyph: "g".into(), claimed: "1".into(), readback: "2".into() },
        ];
        let shown: BTreeSet<String> = all.iter().map(|e| e.to_string()).collect();
        assert_eq!(shown.len(), all.len());
        for e in &all { // exhaustive: adding a variant without handling it here is a compile error
            match e { IouError::SourceRead { .. } | IouError::SourcePinMismatch { .. } | IouError::SourcePinMissing { .. } | IouError::SourceDecode { .. } | IouError::TranslationDisagrees { .. } => {} _ => unreachable!() }
        }
    }

    #[test]
    fn upstream_outline_error_is_the_row_cause_not_a_placeholder_frame_error() {
        let cause = IouError::SourcePinMismatch { glyph: "g".into(), stage1_pin: "a".into(), now: "b".into() };
        let mut e = ev(8, 8); e.canvas = None; // placeholder evidence would fail MissingCanvas if checked first
        let j = IouJob { style: "s".into(), glyph_id: "g".into(), source: SourceInput::Gray { w: 0, h: 0, gray: Vec::new() }, outline: Err(cause.clone()), evidence: e, stage: OutlineStage::OtfReadback };
        let out = run_jobs(&[j], Some(1));
        assert_eq!(out.rows[0].result().clone().unwrap_err(), cause);
    }

    #[test]
    fn identical_and_half_overlap() {
        let f = ev(10, 10).resolve().unwrap();
        let r = iou_glyph(&f, &tile_rect("a", 10, 10, 2, 2, 8, 8), &rect("a", 2.0, 2.0, 8.0, 8.0)).unwrap();
        assert_eq!((r.intersection(), r.union(), r.iou()), (36, 36, 1.0));
        let r = iou_glyph(&f, &tile_rect("a", 10, 10, 2, 2, 6, 6), &rect("a", 4.0, 2.0, 8.0, 6.0)).unwrap();
        assert_eq!((r.intersection(), r.union()), (8, 24));
    }
    #[test]
    fn glyphiou_constructor_rejects_inconsistent() {
        assert!(GlyphIou::from_counts("a", 5, 4, 9).is_err());
        assert!(matches!(GlyphIou::from_counts("a", 0, 0, 0), Err(IouError::EmptyUnion { .. })));
        assert!(GlyphIou::from_counts("", 1, 1, 1).is_err());
        let g = GlyphIou::from_counts("a", 3, 4, 5).unwrap();
        assert_eq!(g.union(), 6);
        assert!(g.validate().is_ok());
    }

    // ---- ids / escaping ----
    #[test]
    fn escaping_is_unambiguous() {
        assert_eq!(escape_id("a b/c\t%"), "a%20b%2Fc%09%25");
        assert_eq!(escape_id(""), "%EMPTY");
        assert_ne!(escape_id("a/b"), escape_id("a b"));
        assert!(!escape_id("é\n").contains('\n'));
    }

    // ---- batch behaviour ----
    fn keys(v: &[(&str, &str)]) -> Vec<(String, String)> { v.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect() }
    fn ex(style: &str, g: &str) -> Exclusion { Exclusion { style: style.into(), glyph_id: g.into(), reason: "blank tile".into() } }

    #[test]
    fn heterogeneous_origin_per_row_pin_and_hashes() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let mut e2 = ev(10, 10); e2.origin = Some((1.0, 0.0));
        let jobs = vec![job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10)),
                        job("s", "b", &tile_rect("b", 10, 10, 3, 2, 9, 8), rect("b", 2.0, 2.0, 8.0, 8.0), e2)];
        let out = run_jobs(&jobs, Some(2));
        assert_ne!(out.rows[0].frame_pin(), out.rows[1].frame_pin());
        assert_eq!(out.rows[0].result().as_ref().unwrap().iou(), 1.0);
        assert_eq!(out.rows[1].result().as_ref().unwrap().iou(), 1.0);
        assert_eq!(out.rows[0].tile_sha256().len(), 64);
        let rep = build_report(&keys(&[("s", "a"), ("s", "b")]), out.rows, vec![], out.duplicates, Some(0.99)).unwrap();
        assert!(rep.to_tsv().contains("# frame 1 "));
    }
    #[test]
    fn build_failures_become_rows_and_inventory_is_exact() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let mut noscale = ev(10, 10); noscale.scale_k = None;
        let jobs = vec![
            job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10)),
            job("s", "n", &t, rect("n", 2.0, 2.0, 8.0, 8.0), noscale),
            IouJob { style: "s".into(), glyph_id: "d".into(), source: SourceInput::Png(vec![1, 2, 3]), outline: Ok(rect("d", 1.0, 1.0, 2.0, 2.0)), evidence: ev(10, 10), stage: OutlineStage::PreEmit },
            IouJob { style: "s".into(), glyph_id: "o".into(), source: gray_of(&t), outline: Err(IouError::EmptyOutline { glyph: "o".into() }), evidence: ev(10, 10), stage: OutlineStage::PreEmit },
        ];
        let out = run_jobs(&jobs, Some(3));
        assert_eq!(out.rows.len(), 4);
        assert!(matches!(out.rows[1].result(), Err(IouError::MissingScaleEvidence)));
        assert!(matches!(out.rows[2].result(), Err(IouError::SourceDecode { .. })));
        let exp = keys(&[("s", "a"), ("s", "n"), ("s", "d"), ("s", "o"), ("s", "blank")]);
        let rep = build_report(&exp, out.rows, vec![ex("s", "blank")], out.duplicates, Some(0.99)).unwrap();
        let o = rep.overall();
        assert_eq!((o.total, o.measured, o.failed, o.excluded), (5, 1, 3, 1));
        assert!(rep.to_receipt().contains("iou excluded blank blank tile"));
    }
    #[test]
    fn err_row_plus_same_key_exclusion_is_rejected() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let mut noscale = ev(10, 10); noscale.scale_k = None;
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), noscale)], Some(1));
        let r = build_report(&keys(&[("s", "a")]), out.rows, vec![ex("s", "a")], out.duplicates, None);
        assert!(matches!(r, Err(IouError::InventoryViolation { .. })));
    }
    #[test]
    fn duplicate_exclusions_are_rejected() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10))], Some(1));
        let r = build_report(&keys(&[("s", "a"), ("s", "x")]), out.rows, vec![ex("s", "x"), ex("s", "x")], out.duplicates, None);
        assert!(matches!(r, Err(IouError::InventoryViolation { .. })));
    }
    #[test]
    fn duplicate_job_does_not_stand_in_for_a_missing_glyph() {
        // jobs: a, a (duplicate). Expected: a, b. Old count rows+excl==N would have passed.
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let jobs = vec![job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10)), job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10))];
        let out = run_jobs(&jobs, Some(2));
        assert_eq!(out.rows.len(), 1);
        assert_eq!(out.duplicates, vec![DuplicateDiagnostic { style: "s".into(), glyph_id: "a".into(), job_index: 1 }]);
        let r = build_report(&keys(&[("s", "a"), ("s", "b")]), out.rows.clone(), vec![], out.duplicates.clone(), None);
        assert!(matches!(r, Err(IouError::InventoryViolation { .. })));
        // with b excluded the inventory closes and the duplicate stays a diagnostic outside N
        let rep = build_report(&keys(&[("s", "a"), ("s", "b")]), out.rows, vec![ex("s", "b")], out.duplicates, None).unwrap();
        assert_eq!(rep.overall().total, 2);
        assert!(rep.to_receipt().contains("duplicate_job_diagnostics=1"));
    }
    #[test]
    fn unexpected_and_duplicate_expected_keys_rejected() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10))], Some(1));
        assert!(matches!(build_report(&keys(&[("s", "zzz")]), out.rows.clone(), vec![], vec![], None), Err(IouError::InventoryViolation { .. })));
        assert!(matches!(build_report(&keys(&[("s", "a"), ("s", "a")]), out.rows, vec![], vec![], None), Err(IouError::InventoryViolation { .. })));
    }
    #[test]
    fn all_excluded_is_an_honest_report() {
        let rep = build_report(&keys(&[("s", "x"), ("s", "y")]), vec![], vec![ex("s", "x"), ex("s", "y")], vec![], Some(0.99)).unwrap();
        let o = rep.overall();
        assert_eq!((o.total, o.measured, o.failed, o.excluded), (2, 0, 0, 2));
        assert_eq!((o.mean, o.min, o.below_target), (None, None, Some(0)));
        let rc = rep.to_receipt();
        assert!(rc.contains("iou excluded x blank tile"));
        assert!(rc.contains("measured=0 failed=0 excluded=2"));
        assert!(matches!(build_report(&[], vec![], vec![], vec![], None), Err(IouError::NoResults)));
    }
    #[test]
    fn order_stable_across_worker_counts() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let ids = ["a", "b", "c", "d", "e"];
        let jobs: Vec<IouJob> = ids.iter().map(|i| job("s", i, &t, rect(i, 2.0, 2.0, 8.0, 8.0), ev(10, 10))).collect();
        let names = |o: &RunOutput| o.rows.iter().map(|x| x.glyph_id().to_string()).collect::<Vec<_>>();
        assert_eq!(names(&run_jobs(&jobs, Some(1))), names(&run_jobs(&jobs, Some(4))));
    }
    #[test]
    fn run_jobs_bit_identical_at_jobs_1_2_4_8() {
        // The pipeline passes its --jobs value as the worker count; the full
        // output (rows and duplicate diagnostics, not just ordering) must be
        // bit-identical for every worker count a caller can request.
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let ids = ["a", "b", "c", "d", "e", "f", "g", "h", "a"];
        let jobs: Vec<IouJob> = ids.iter().map(|i| job("s", i, &t, rect(i, 2.0, 2.0, 8.0, 8.0), ev(10, 10))).collect();
        let dump = |o: &RunOutput| format!("{:?}|{:?}", o.rows, o.duplicates);
        let base = dump(&run_jobs(&jobs, Some(1)));
        for w in [2usize, 4, 8] {
            assert_eq!(base, dump(&run_jobs(&jobs, Some(w))), "run_jobs output must be bit-identical at workers={w}");
        }
    }
    #[test]
    fn report_receipt_and_tsv_cells_are_unambiguous() {
        let t = tile_rect("a b", 10, 10, 2, 2, 8, 8);
        let jobs = vec![job("st y", "a b", &t, rect("a b", 2.0, 2.0, 8.0, 8.0), ev(10, 10)),
                        job("st", "y/a b", &t, rect("y/a b", 2.0, 2.0, 8.0, 8.0), ev(10, 10)),
                        job("st y", "a/b", &t, rect("a/b", 2.0, 2.0, 8.0, 8.0), ev(10, 10))];
        let out = run_jobs(&jobs, Some(1));
        let rep = build_report(&keys(&[("st y", "a b"), ("st", "y/a b"), ("st y", "a/b")]), out.rows, vec![], out.duplicates, None).unwrap();
        let rc = rep.to_receipt();
        assert!(rc.contains("iou glyph st%20y/a%20b 1.000000000"));
        for line in rep.to_tsv().lines().filter(|l| !l.starts_with('#') && !l.starts_with("style")) {
            assert_eq!(line.split('\t').count(), 13);
        }
    }
    #[test]
    fn limits_are_required_and_enforced() {
        let mut e = ev(8, 8); e.limits = None; assert_eq!(e.resolve(), Err(IouError::MissingResourceLimits));
        let e = ev(2000, 2000); assert!(matches!(e.resolve(), Err(IouError::ResourceLimitExceeded { .. })));
        let mut e = ev(8, 8); e.flatten_steps = Some(65); assert!(matches!(e.resolve(), Err(IouError::ResourceLimitExceeded { .. })));
        let mut e = ev(10, 10); e.limits = Some(ResourceLimits { max_pixels: 100, max_flatten_steps: 8, max_edges: 3, max_png_bytes: 1000, max_png_working_bytes: 1 << 26 });
        let f = e.resolve().unwrap();
        assert!(matches!(coverage_mask(&f, "a", &rect("a", 1.0, 1.0, 5.0, 5.0).rings), Err(IouError::ResourceLimitExceeded { .. })));
        // oversized gray source and a PNG header claiming a huge canvas become failed rows, not allocations
        let mut e = ev(10, 10); e.limits = Some(ResourceLimits { max_pixels: 50, max_flatten_steps: 8, max_edges: 1000, max_png_bytes: 1000, max_png_working_bytes: 1 << 26 });
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec(); png.extend_from_slice(&[0, 0, 0, 13]); png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&u32::MAX.to_be_bytes()); png.extend_from_slice(&u32::MAX.to_be_bytes());
        let big = IouJob { style: "s".into(), glyph_id: "p".into(), source: SourceInput::Png(png), outline: Ok(rect("p", 1.0, 1.0, 2.0, 2.0)), evidence: ev(10, 10), stage: OutlineStage::PreEmit };
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), e), big], Some(1));
        assert!(matches!(out.rows[0].result(), Err(IouError::ResourceLimitExceeded { .. })));
        assert!(matches!(out.rows[1].result(), Err(IouError::ResourceLimitExceeded { .. })));
    }
    #[test]
    fn caps_run_before_hash_and_clone() {
        let mut e = ev(10, 10); e.limits = Some(ResourceLimits { max_pixels: 100, max_flatten_steps: 8, max_edges: 1000, max_png_bytes: 50, max_png_working_bytes: 1 << 26 });
        let mk = |id: &str, src: SourceInput| IouJob { style: "s".into(), glyph_id: id.into(), source: src, outline: Ok(rect(id, 1.0, 1.0, 2.0, 2.0)), evidence: e.clone(), stage: OutlineStage::PreEmit };
        let out = run_jobs(&[
            mk("g200", SourceInput::Gray { w: 200, h: 200, gray: vec![0u8; 40_000] }),
            mk("glen", SourceInput::Gray { w: 10, h: 10, gray: vec![0u8; 7] }),
            mk("gmax", SourceInput::Gray { w: usize::MAX, h: 2, gray: vec![] }),
            mk("png", SourceInput::Png(vec![0u8; 51])),
        ], Some(1));
        assert!(matches!(out.rows[0].result(), Err(IouError::ResourceLimitExceeded { .. })));
        assert!(matches!(out.rows[1].result(), Err(IouError::BadSourceBuffer { .. })));
        assert!(matches!(out.rows[2].result(), Err(IouError::ResourceLimitExceeded { .. })));
        assert!(matches!(out.rows[3].result(), Err(IouError::ResourceLimitExceeded { .. })));
        for r in &out.rows { assert_eq!(r.tile_sha256(), "UNHASHED"); assert!(r.outline_sha256().is_none()); }
    }
    #[test]
    fn translation_is_required_and_shifts_the_frame() {
        let mut e = ev(10, 10); e.translation = None; assert_eq!(e.resolve(), Err(IouError::MissingTranslation));
        // outline shipped 3 units right and 2 up of the source frame; translation undoes it
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let shifted = { let mut g = rect("a", 2.0, 2.0, 8.0, 8.0); for r in &mut g.rings { r.start.x += 3.0; r.start.y += 2.0; for s in &mut r.spans { if let Span::Line { end } = s { end.x += 3.0; end.y += 2.0; } } } g };
        let mut e = ev(10, 10); e.translation = Some((3.0, 2.0));
        assert_eq!(iou_glyph(&e.resolve().unwrap(), &t, &shifted).unwrap().iou(), 1.0);
        assert!(iou_glyph(&ev(10, 10).resolve().unwrap(), &t, &shifted).unwrap().iou() < 1.0);
        let mut e = ev(10, 10); e.translation = Some((f64::NAN, 0.0)); assert!(e.resolve().is_err());
    }
    #[test]
    fn mixed_stages_rejected() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let mut j2 = job("s", "b", &t, rect("b", 2.0, 2.0, 8.0, 8.0), ev(10, 10));
        j2.stage = OutlineStage::OtfReadback;
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10)), j2], Some(1));
        assert!(matches!(build_report(&keys(&[("s", "a"), ("s", "b")]), out.rows, vec![], vec![], None), Err(IouError::MixedStages)));
    }
    #[test]
    fn report_rejects_bad_target() {
        let t = tile_rect("a", 10, 10, 2, 2, 8, 8);
        let out = run_jobs(&[job("s", "a", &t, rect("a", 2.0, 2.0, 8.0, 8.0), ev(10, 10))], Some(1));
        assert!(matches!(build_report(&keys(&[("s", "a")]), out.rows, vec![], vec![], Some(f64::NAN)), Err(IouError::BadTarget)));
    }
}

#[cfg(test)]
mod bounded_png_tests {
    use super::*;
    use crate::bounded_png_adapter::LimitsOrigin;
    use crate::capture::DecodeLimits;
    fn tiny_png() -> Vec<u8> {
        // 2x2 gray, stored zlib block; CRCs are not validated by the decoder.
        let raw = [0u8, 10, 20, 0, 30, 40];
        let (mut a, mut b) = (1u32, 0u32);
        for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        let mut z = vec![0x78, 0x01, 1, 6, 0, !6u8, 0xff];
        z.extend_from_slice(&raw);
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let ch = |t: &[u8; 4], body: &[u8]| { let mut v = (body.len() as u32).to_be_bytes().to_vec(); v.extend_from_slice(t); v.extend_from_slice(body); v.extend_from_slice(&[0; 4]); v };
        let mut v = b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend(ch(b"IHDR", &[0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 0]));
        v.extend(ch(b"IDAT", &z));
        v.extend(ch(b"IEND", &[]));
        v
    }
    #[test]
    fn from_png_explicit_limits_parity_refusal_and_pin() {
        let p = tiny_png();
        let l = DecodeLimits::default();
        let (t, r) = SourceTile::from_png("a", &p, &l, LimitsOrigin::Explicit("t".into())).unwrap();
        assert_eq!((t.dims(), t.gray.clone()), ((2, 2), vec![10, 20, 30, 40]));
        assert_eq!(r.limits, l);
        let tight = DecodeLimits { max_input_bytes: 1 << 20, max_pixels: 3, max_working_bytes: 1 << 20 };
        assert!(matches!(SourceTile::from_png("a", &p, &tight, LimitsOrigin::Explicit("t".into())), Err(IouError::SourceDecode { .. })));
    }
    #[test]
    fn frame_pin_binds_png_working_budget() {
        let mut e = crate::iou_report::FrameEvidence { translation: Some((0.0,0.0)), scale_k: Some(1.0), origin: Some((0.0, 0.0)), ink_threshold: Some(128), flatten_steps: Some(8), canvas: Some((4, 4)), limits: Some(ResourceLimits { max_pixels: 100, max_flatten_steps: 8, max_edges: 100, max_png_bytes: 1000, max_png_working_bytes: 111 }) };
        let a = e.resolve().unwrap().pin();
        assert!(a.ends_with("/pngwork111"), "{a}");
        e.limits.as_mut().unwrap().max_png_working_bytes = 222;
        assert_ne!(a, e.resolve().unwrap().pin());
    }
}
