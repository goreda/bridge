//! Shared lever contract. FREEZE at delivery; bump LEVER_API_VERSION on any change.
//! Pure, deterministic, no env/global state, no HashMap iteration, no threads.
//!
//! SourceMask convention (single, pinned, one test in tests/int_refine.rs):
//! - `ink` is a gray image, row-major, `w*h` bytes, row 0 at the TOP.
//! - Binary source = threshold-128 isoline: a pixel is ink iff gray < 128 (dark = ink).
//!   Area objective uses the binary mask (not gray).
//! - Pixel (i,j) covers the square [i,i+1]x[j,j+1] in pixel space. Pixel centre is (i+.5,j+.5).
//! - Frame: font x = origin.0 + px*scale ; font y = origin.1 - py*scale, where (px,py) is a
//!   pixel-space point (corner convention, py grows downward). `origin` is the font-space
//!   coordinate of the mask's TOP-LEFT CORNER. No rounding is applied by the frame itself;
//!   integer rounding happens only where a lever emits integer coordinates.
//! - Origin by input kind: charstring (integer, translated) input origin = (tx - ox*K, ty - oy*K);
//!   fitted (untranslated float) input origin = (-ox*K, -oy*K). scale = K in both.
//! - Canonical capture frame (CAP690-SCAN128-FITK-CFFINTEGER-RAWORIGIN): for an
//!   audit with capture_origin (ox,oy), translation (tx,ty), K: x_px = ox + (x_char - tx)/K,
//!   y_px = -oy - (y_char - ty)/K, i.e. origin = (tx - ox*K, ty - oy*K), scale = K. Same as above, algebraically.
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const LEVER_API_VERSION: u32 = 3; // v3 = v2 + public error_map/tagged_segments/nearest_segment (additive); v1/v2 signatures and outputs byte-identical

#[derive(Clone, Debug)]
pub struct SourceMask {
    pub w: usize,
    pub h: usize,
    pub ink: Vec<u8>,
    pub scale: f64,
    pub origin: (f64, f64),
}

impl SourceMask {
    pub fn is_ink(&self, i: usize, j: usize) -> bool { self.ink[j * self.w + i] < 128 }
    pub fn to_pixel(&self, p: Point) -> (f64, f64) {
        ((p.x - self.origin.0) / self.scale, (self.origin.1 - p.y) / self.scale)
    }
    pub fn pixel_centre_to_font(&self, i: usize, j: usize) -> Point {
        Point { x: self.origin.0 + (i as f64 + 0.5) * self.scale,
                y: self.origin.1 - (j as f64 + 0.5) * self.scale }
    }
    pub fn valid(&self) -> bool {
        self.w > 0 && self.h > 0 && self.ink.len() == self.w * self.h
            && self.scale.is_finite() && self.scale > 0.0
            && self.origin.0.is_finite() && self.origin.1.is_finite()
    }
}

/// Per-ring and per-glyph node ceilings. A lever must never exceed them; violation is an error.
#[derive(Clone, Debug)]
pub struct NodeBudget {
    pub max_nodes: usize,
    /// Per-ring ceilings, aligned to the input rings; empty = per-ring ceiling is the input count.
    pub max_nodes_per_ring: Vec<usize>,
}

#[derive(Clone, Debug)]
pub struct LeverReport {
    pub lever: &'static str,
    pub lever_id: &'static str,
    pub api_version: u32,
    pub stage_tag: &'static str,
    pub input_hash: u64,
    pub output_hash: u64,
    pub seed: u64,
    pub nodes_before: usize,
    pub nodes_after: usize,
    pub area_before: f64,
    pub area_after: f64,
    /// C2 = missing extrema count of the OUTPUT rings (lever_api::missing_extrema); must be 0.
    pub c2_missing: usize,
    /// Max displacement of any point (node or control) in font units.
    pub max_node_displacement: f64,
    pub notes: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum LeverError {
    BadMask,
    NonClosedRing { ring: usize },
    NonIntegerInput { ring: usize },
    NodeCeiling { ring: usize, got: usize, max: usize },
    ExtremumMoved { ring: usize, node: usize },
    Violation(String),
}

pub type LeverResult = Result<(Vec<ReferenceRing>, LeverReport), LeverError>;

// ---- deterministic hashing (FNV-1a 64 over exact f64 bits) ----
pub fn hash_rings(rings: &[ReferenceRing]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    let mut put = |v: u64| { for b in v.to_le_bytes() { h ^= b as u64; h = h.wrapping_mul(0x100000001b3); } };
    put(rings.len() as u64);
    for r in rings {
        put(r.start.x.to_bits()); put(r.start.y.to_bits()); put(r.spans.len() as u64);
        for s in &r.spans {
            match s {
                Span::Line { end } => { put(1); put(end.x.to_bits()); put(end.y.to_bits()); }
                Span::Cubic { control_one: a, control_two: b, end } => {
                    put(2);
                    for p in [a, b, end] { put(p.x.to_bits()); put(p.y.to_bits()); }
                }
            }
        }
    }
    h
}

pub fn count_nodes(rings: &[ReferenceRing]) -> usize { rings.iter().map(|r| r.spans.len()).sum() }

// ---- shared area objective: L1 distance between exact pixel coverage and the binary mask,
// in font units^2. For crisp coverage this equals the symmetric-difference area. ----
fn flatten_ring(r: &ReferenceRing, m: &SourceMask) -> Vec<(f64, f64)> {
    let mut out = vec![m.to_pixel(r.start)];
    let mut cur = m.to_pixel(r.start);
    for s in &r.spans {
        match s {
            Span::Line { end } => { cur = m.to_pixel(*end); out.push(cur); }
            Span::Cubic { control_one, control_two, end } => {
                let (p0, p1, p2, p3) = (cur, m.to_pixel(*control_one), m.to_pixel(*control_two), m.to_pixel(*end));
                let d = |a: (f64, f64), b: (f64, f64)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
                // chords <= ~1 px: segment count derived from control-polygon length in pixels
                let n = (d(p0, p1) + d(p1, p2) + d(p2, p3)).ceil() as usize + 1;
                for k in 1..=n {
                    let t = k as f64 / n as f64; let u = 1.0 - t;
                    out.push((u*u*u*p0.0 + 3.0*u*u*t*p1.0 + 3.0*u*t*t*p2.0 + t*t*t*p3.0,
                              u*u*u*p0.1 + 3.0*u*u*t*p1.1 + 3.0*u*t*t*p2.1 + t*t*t*p3.1));
                }
                cur = p3;
            }
        }
    }
    out
}

/// Rows `accumulate` has written since the last clear, tracked so a reused scratch
/// buffer can be cleared only where it was written (dirty-row clear). Values are
/// unaffected: rows never written hold exactly 0.0 from the initial zeroing.
#[derive(Default)]
struct RowWrites { dirty: Vec<u32>, touched: Vec<bool>, rmin: Vec<i32>, rmax: Vec<i32>, stride: usize, rows: usize }
impl RowWrites {
    fn mark(&mut self, row: usize) {
        if self.touched.len() <= row { self.touched.resize(row + 1, false); }
        if !self.touched[row] { self.touched[row] = true; self.dirty.push(row as u32); }
    }
    /// Mark `row` as written and widen its written column span to include
    /// x0..=x1 (kernel write span of one chord in that row).
    fn mark_span(&mut self, row: usize, x0: usize, x1: usize) {
        self.mark(row);
        if self.rmin.len() <= row { self.rmin.resize(row + 1, -1); self.rmax.resize(row + 1, -1); }
        if self.rmin[row] < 0 { self.rmin[row] = x0 as i32; self.rmax[row] = x1 as i32; }
        else {
            if (x0 as i32) < self.rmin[row] { self.rmin[row] = x0 as i32; }
            if (x1 as i32) > self.rmax[row] { self.rmax[row] = x1 as i32; }
        }
    }
    /// Written column span of `row` since the last clear; None when the row was
    /// not written (then `a` is exactly 0.0 across the whole row).
    fn row_range(&self, row: usize) -> Option<(usize, usize)> {
        if row < self.rmin.len() && self.rmin[row] >= 0 { Some((self.rmin[row] as usize, self.rmax[row] as usize)) } else { None }
    }
    /// Zero exactly the rows written since the last clear (or, when the buffer is
    /// fresh/resized, nothing - a fresh buffer is already all 0.0).
    fn clear_written(&mut self, a: &mut [f64], stride: usize) {
        for &r in &self.dirty {
            let row = r as usize * stride;
            for v in &mut a[row..row + stride] { *v = 0.0; }
        }
        for &r in &self.dirty {
            let r = r as usize;
            self.touched[r] = false;
            if r < self.rmin.len() { self.rmin[r] = -1; self.rmax[r] = -1; }
        }
        self.dirty.clear();
    }
}

/// Pixel guard width that covers every cell the accumulate kernel can write,
/// measured in pixel indices from the floor/ceil pixel bbox of the
/// rasterised points. Per spanned row accumulate writes exactly the columns
/// floor(x)..=ceil(x) of the clamped chord and nothing else, so the write set
/// already sits inside the undilated floor/ceil bbox; one index of guard on
/// every side is the margin every consumer dilates by. A kernel change that
/// writes wider than floor/ceil must raise this constant to at least the new
/// write reach; the property test below fails when the real reach outgrows it.
pub const COVERAGE_KERNEL_REACH_PX: i64 = 1;

fn accumulate(a: &mut [f64], stride: usize, w: usize, h: usize, p0: (f64, f64), p1: (f64, f64), wr: &mut RowWrites) {
    if p0.1 == p1.1 { return; }
    let (dir, p0, p1) = if p0.1 < p1.1 { (1.0, p0, p1) } else { (-1.0, p1, p0) };
    if p1.1 <= 0.0 || p0.1 >= h as f64 { return; }
    let dxdy = (p1.0 - p0.0) / (p1.1 - p0.1);
    let mut x = p0.0;
    let mut y_start = p0.1;
    if y_start < 0.0 { x -= y_start * dxdy; y_start = 0.0; }
    let y_end = p1.1.min(h as f64);
    let y0 = y_start.floor() as usize;
    let y1 = y_end.ceil() as usize;
    let wf = w as f64;
    for y in y0..y1.min(h) {
        let dy = ((y + 1) as f64).min(y_end) - (y as f64).max(y_start);
        if dy <= 0.0 { continue; }
        let xnext = x + dxdy * dy;
        let d = dy * dir;
        let (xa, xb) = if x < xnext { (x, xnext) } else { (xnext, x) };
        let (xa, xb) = (xa.clamp(0.0, wf), xb.clamp(0.0, wf));
        let x0f = xa.floor(); let x0i = x0f as usize;
        let x1c = xb.ceil(); let x1i = x1c as usize;
        wr.mark_span(y, x0i, x1i);
        let row = y * stride;
        if x1i <= x0i + 1 {
            let xmf = 0.5 * (xa + xb) - x0f;
            a[row + x0i] += d - d * xmf;
            a[row + x0i + 1] += d * xmf;
        } else {
            let s = 1.0 / (xb - xa);
            let x0 = xa - x0f;
            let a0 = 0.5 * s * (1.0 - x0) * (1.0 - x0);
            let x1 = xb - x1c + 1.0;
            let am = 0.5 * s * x1 * x1;
            a[row + x0i] += d * a0;
            if x1i == x0i + 2 {
                a[row + x0i + 1] += d * (1.0 - a0 - am);
            } else {
                let a1 = s * (1.5 - x0);
                a[row + x0i + 1] += d * (a1 - a0);
                for xi in (x0i + 2)..(x1i - 1) { a[row + xi] += d * s; }
                let a2 = a1 + (x1i - x0i - 3) as f64 * s;
                a[row + x1i - 1] += d * (1.0 - a2 - am);
            }
            a[row + x1i] += d * am;
        }
        x = xnext;
    }
}

/// v3: per-pixel |coverage - ink| in pixel units (not scaled), row-major w*h, row 0 at top.
/// Work-buffers are caller-owned: `a` (accumulate, (w+2)*h) and `e` (error, w*h) are
/// cleared and refilled on every call, so a caller that evaluates the map repeatedly
/// (area_error hot loop) can reuse the same allocations across calls. Values written
/// are identical to allocating fresh zeroed buffers each call.
fn error_map_into(rings: &[ReferenceRing], m: &SourceMask, a: &mut Vec<f64>, e: &mut Vec<f64>) {
    let mut wr = RowWrites::default();
    let bb = coverage_accumulate_into(rings, m, a, &mut wr);
    e.clear();
    e.resize(m.w * m.h, 0.0f64);
    coverage_scan(rings, m, a, bb, &wr, |j, i, v| e[j * m.w + i] = v);
}

/// First half of the error map: antialiased winding accumulation of all rings into
/// the zeroed (w+2)*h scratch `a` (cleared and refilled here). Returns the bounding
/// box (x0, y0, x1, y1) in pixel coordinates, expanded by the accumulate kernel's
/// 1px reach and clamped to the frame, of every pixel `a` can have written: outside
/// it `a` is exactly 0.0. None when no ring produced a point.
fn coverage_accumulate_into(rings: &[ReferenceRing], m: &SourceMask, a: &mut Vec<f64>, wr: &mut RowWrites) -> Option<(usize, usize, usize, usize)> {
    let stride = m.w + 2;
    // The reuse key is the frame GEOMETRY (stride, rows), not the buffer
    // length: (w+2)*h collides for different (w, h) — e.g. 13x12 and 10x15
    // both give 180 — and clear_written replays the recorded row dirt at
    // the CURRENT stride, so a same-length/different-stride reuse zeroes
    // the wrong spans and leaks stale winding into the scan (oracle fuzz
    // case 188: area_error 24.65 vs the fresh-buffer 25.0).
    if a.len() != stride * m.h || wr.stride != stride || wr.rows != m.h {
        // dimension change: full zero establishes the invariant (unwritten = 0.0)
        a.clear();
        a.resize(stride * m.h, 0.0f64);
        wr.dirty.clear();
        for t in wr.touched.iter_mut() { *t = false; }
        for v in wr.rmin.iter_mut() { *v = -1; }
        for v in wr.rmax.iter_mut() { *v = -1; }
        wr.stride = stride;
        wr.rows = m.h;
    } else {
        wr.clear_written(a, stride);
    }
    let mut bb: Option<(f64, f64, f64, f64)> = None;
    let mut grow = |p: (f64, f64)| {
        bb = Some(match bb {
            None => (p.0, p.1, p.0, p.1),
            Some((x0, y0, x1, y1)) => (x0.min(p.0), y0.min(p.1), x1.max(p.0), y1.max(p.1)),
        });
    };
    for r in rings {
        let pts = flatten_ring(r, m);
        for p in &pts { grow(*p); }
        for k in 0..pts.len().saturating_sub(1) { accumulate(a, stride, m.w, m.h, pts[k], pts[k + 1], wr); }
        // implicit closure
        if let (Some(f), Some(l)) = (pts.first(), pts.last()) { accumulate(a, stride, m.w, m.h, *l, *f, wr); }
    }
    bb.map(|(x0, y0, x1, y1)| {
        // Kernel reach: accumulate writes columns floor(x)..=ceil(x) of
        // clamped chord endpoints and rows spanned by the chord; the shared
        // constant is the guard on every side.
        let k = COVERAGE_KERNEL_REACH_PX as isize;
        let gx0 = (x0.floor() as isize - k).clamp(0, m.w as isize) as usize;
        let gy0 = (y0.floor() as isize - k).clamp(0, m.h as isize) as usize;
        let gx1 = ((x1.ceil() as isize + k).clamp(0, m.w as isize) as usize).min(m.w.saturating_sub(1));
        let gy1 = ((y1.ceil() as isize + k).clamp(0, m.h as isize) as usize).min(m.h.saturating_sub(1));
        (gx0, gy0, gx1, gy1)
    })
}

/// Second half: row-major prefix scan over `a`, emitting |coverage - ink| per pixel
/// in the exact row-major (j, i) order. The sink sees the identical value sequence
/// that error_map materializes. `bb` is the accumulate bbox: outside it `a` is 0.0,
/// so the prefix sum stays 0.0 (skipping +0.0 adds preserves acc bit-exactly) and
/// the emitted value is |0 - ink| = ink, identical to the full scan.
fn coverage_scan(_rings: &[ReferenceRing], m: &SourceMask, a: &[f64], bb: Option<(usize, usize, usize, usize)>, wr: &RowWrites, mut sink: impl FnMut(usize, usize, f64)) {
    let stride = m.w + 2;
    let (_bx0, by0, _bx1, by1) = bb.unwrap_or((m.w, m.h, 0, 0)); // None => nothing written anywhere
    for j in 0..m.h {
        let mut acc = 0.0;
        // Per-row written span [r0, r1] from the accumulate pass: outside it `a`
        // is exactly 0.0, so skipping those pixels drops only +0.0 adds (acc
        // preserved bit-exactly) and the emitted value is |0 - ink| = ink,
        // identical to the full scan. Rows outside the bbox or with no span
        // (unwritten, or written only in the dead columns >= m.w that the scan
        // never reads) are all-ink.
        let rr = if j < by0 || j > by1 { None } else { wr.row_range(j) };
        let rr = rr.filter(|&(r0, _)| r0 < m.w);
        let Some((r0, r1)) = rr else {
            for i in 0..m.w {
                let ink = if m.is_ink(i, j) { 1.0 } else { 0.0 };
                sink(j, i, (0.0f64 - ink).abs());
            }
            continue;
        };
        let r1 = r1.min(m.w - 1);
        for i in 0..r0 {
            let ink = if m.is_ink(i, j) { 1.0 } else { 0.0 };
            sink(j, i, (0.0f64 - ink).abs());
        }
        for i in r0..=r1 {
            acc += a[j * stride + i];
            let cov = acc.abs().min(1.0);
            let ink = if m.is_ink(i, j) { 1.0 } else { 0.0 };
            sink(j, i, (cov - ink).abs());
        }
        for i in (r1 + 1)..m.w {
            let ink = if m.is_ink(i, j) { 1.0 } else { 0.0 };
            sink(j, i, (0.0f64 - ink).abs());
        }
    }
}

/// Row-major prefix-sum variant of coverage_scan with an exact early exit:
/// every emitted term is nonnegative and f64 addition of nonnegative values
/// is monotone, so once the running row-total scaled like area_error reaches
/// `limit`, the final sum is proven >= limit and None is returned. On Some
/// the accumulated raw sum is exactly what coverage_scan would have produced
/// (same emission order, same association).
fn coverage_scan_below(m: &SourceMask, a: &[f64], bb: Option<(usize, usize, usize, usize)>, wr: &RowWrites, limit: f64) -> Option<f64> {
    let stride = m.w + 2;
    let (_bx0, by0, _bx1, by1) = bb.unwrap_or((m.w, m.h, 0, 0)); // None => nothing written anywhere
    let mut err = 0.0;
    for j in 0..m.h {
        let mut acc = 0.0;
        // Same per-row written-span skip as coverage_scan: outside the span `a`
        // is exactly 0.0, so those terms are |0 - ink| = ink, and the running
        // `acc` is untouched (bit-exact). Rows outside the bbox or unwritten
        // are all-ink.
        let rr = if j < by0 || j > by1 { None } else { wr.row_range(j) };
        let rr = rr.filter(|&(r0, _)| r0 < m.w);
        // One slice per row: the per-pixel `m.is_ink` / `a[j*stride+i]`
        // indexing below carries a bounds check per pixel; the sliced loops
        // carry one per row and auto-vectorize. Bit-identity: every margin
        // term is 0.0 or 1.0, so a margin's f64 sum is an exact integer;
        // counting and adding once per span yields the same `err` bit-for-bit,
        // and the middle loop keeps the exact per-pixel op order.
        let ink_row = &m.ink[j * m.w..(j + 1) * m.w];
        let Some((r0, r1)) = rr else {
            err += ink_row.iter().filter(|&&v| v < 128).count() as f64;
            if (err * m.scale) * m.scale >= limit { return None; }
            continue;
        };
        let r1 = r1.min(m.w - 1);
        err += ink_row[..r0].iter().filter(|&&v| v < 128).count() as f64;
        if r0 <= r1 {
            let arow = &a[j * stride..j * stride + stride];
            for (k, &av) in arow[r0..=r1].iter().enumerate() {
                acc += av;
                let cov = acc.abs().min(1.0);
                let ink = if ink_row[r0 + k] < 128 { 1.0 } else { 0.0 };
                err += (cov - ink).abs();
            }
        }
        err += ink_row[(r1 + 1)..].iter().filter(|&&v| v < 128).count() as f64;
        if (err * m.scale) * m.scale >= limit { return None; }
    }
    Some(err)
}

/// area_error with an exact reject-fast contract for `e < limit` decisions:
/// returns Some(e) with e bit-identical to area_error(rings, m) when the full
/// scan completes, or None as soon as the nonnegative row-major prefix proves
/// the total reaches `limit`. Some(e) therefore carries e < limit exactly
/// when area_error would have compared so; a None is a certain reject and the
/// caller skips no accept. Only the runtime of rejected calls changes.
pub fn area_error_below(rings: &[ReferenceRing], m: &SourceMask, limit: f64) -> Option<f64> {
    let mut out = None;
    // Same thread-local scratch contract as area_error: reuse when free,
    // fresh buffers on a (future) re-entrant borrow.
    let reused = AREA_ERROR_SCRATCH_A.with(|sa| match sa.try_borrow_mut() {
        Ok(mut sc) => {
            let (a, wr) = &mut *sc;
            let bb = coverage_accumulate_into(rings, m, a, wr);
            out = coverage_scan_below(m, a, bb, wr, limit);
            true
        }
        _ => false,
    });
    if !reused {
        let mut a = Vec::new();
        let mut wr = RowWrites::default();
        let bb = coverage_accumulate_into(rings, m, &mut a, &mut wr);
        out = coverage_scan_below(m, &a, bb, &wr, limit);
    }
    out.map(|err| err * m.scale * m.scale)
}

/// v3: per-pixel |coverage - ink| in pixel units (not scaled), row-major w*h, row 0 at top.
pub fn error_map(rings: &[ReferenceRing], m: &SourceMask) -> Vec<f64> {
    let mut a = Vec::new();
    let mut e = Vec::new();
    error_map_into(rings, m, &mut a, &mut e);
    e
}

thread_local! {
    /// Per-thread work buffer for the area_error hot path. One glyph fit evaluates
    /// area_error thousands of times on the same frame; reusing the full-frame
    /// buffer avoids re-faulting a fresh (w+2)*h f64 allocation per call. The
    /// buffer is fully cleared and refilled on every call, so results are
    /// bit-identical to allocating a fresh buffer.
    static AREA_ERROR_SCRATCH_A: std::cell::RefCell<(Vec<f64>, RowWrites)> = std::cell::RefCell::new((Vec::new(), RowWrites::default()));
}

/// Exact-area coverage error vs the binary mask, font units^2. Deterministic, serial.
/// The per-pixel error map is never materialized: the scan's sink adds each pixel's
/// |coverage - ink| into `err` in the identical row-major sequence that summing
/// error_map's output would produce, so the result is bit-identical.
pub fn area_error(rings: &[ReferenceRing], m: &SourceMask) -> f64 {
    let mut err = 0.0;
    // Reuse the thread-local scratch when free; fall back to fresh buffers on any
    // (future) re-entrant borrow so behaviour stays correct.
    let reused = AREA_ERROR_SCRATCH_A.with(|sa| match sa.try_borrow_mut() {
        Ok(mut sc) => {
            let (a, wr) = &mut *sc;
            let bb = coverage_accumulate_into(rings, m, a, wr);
            coverage_scan(rings, m, a, bb, wr, |_, _, v| err += v);
            true
        }
        _ => false,
    });
    if !reused {
        for v in error_map(rings, m) { err += v; }
    }
    err * m.scale * m.scale
}

/// v3: one flattened boundary segment in PIXEL space, tagged with its owning ring and span.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TaggedSegment { pub a: (f64, f64), pub b: (f64, f64), pub ring: usize, pub span: usize }

/// v3: flattened segments in deterministic order (ring, span, sub-segment). Lines give one segment;
/// a cubic gives ceil(control-polygon length in px)+1 chords. This is the exact flattening used by
/// area_error_per_span. Index in the returned Vec is the tie-break index.
pub fn tagged_segments(rings: &[ReferenceRing], m: &SourceMask) -> Vec<TaggedSegment> {
    let mut segs = vec![];
    for (ri, r) in rings.iter().enumerate() {
        let mut cur = m.to_pixel(r.start);
        for (si, s) in r.spans.iter().enumerate() {
            match s {
                Span::Line { end } => { let n = m.to_pixel(*end); segs.push(TaggedSegment { a: cur, b: n, ring: ri, span: si }); cur = n; }
                Span::Cubic { control_one, control_two, end } => {
                    let (p0, p1, p2, p3) = (cur, m.to_pixel(*control_one), m.to_pixel(*control_two), m.to_pixel(*end));
                    let d = |a: (f64, f64), b: (f64, f64)| ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
                    let n = (d(p0, p1) + d(p1, p2) + d(p2, p3)).ceil() as usize + 1;
                    let mut prev = p0;
                    for k in 1..=n {
                        let t = k as f64 / n as f64; let u = 1.0 - t;
                        let q = (u*u*u*p0.0 + 3.0*u*u*t*p1.0 + 3.0*u*t*t*p2.0 + t*t*t*p3.0,
                                 u*u*u*p0.1 + 3.0*u*u*t*p1.1 + 3.0*u*t*t*p2.1 + t*t*t*p3.1);
                        segs.push(TaggedSegment { a: prev, b: q, ring: ri, span: si }); prev = q;
                    }
                    cur = p3;
                }
            }
        }
    }
    segs
}

/// v3 tie contract: index of the segment nearest to pixel-space point `c` (squared Euclidean
/// distance to the closed segment); on EXACT equal distance the LOWEST index wins (strict `<`).
/// None if `segs` is empty.
pub fn nearest_segment(c: (f64, f64), segs: &[TaggedSegment]) -> Option<usize> {
    let mut best = f64::INFINITY; let mut who = None;
    for (idx, sg) in segs.iter().enumerate() {
        let (dx, dy) = (sg.b.0 - sg.a.0, sg.b.1 - sg.a.1);
        let l2 = dx * dx + dy * dy;
        let t = if l2 == 0.0 { 0.0 } else { (((c.0 - sg.a.0) * dx + (c.1 - sg.a.1) * dy) / l2).clamp(0.0, 1.0) };
        let (px, py) = (sg.a.0 + t * dx, sg.a.1 + t * dy);
        let dd = (c.0 - px).powi(2) + (c.1 - py).powi(2);
        if dd < best { best = dd; who = Some(idx); }
    }
    who
}

/// v2 (additive). Per-ring, per-span split of the pixel error (font units^2). Each error pixel goes to
/// the span owning the NEAREST flattened segment (tagged_segments / nearest_segment tie contract);
/// no double counting. Pixels with error <= 0 are skipped, so the total equals area_error up to
/// float summation order. Implemented on the v3 public pieces; output is byte-identical to v2.
pub fn area_error_per_span(rings: &[ReferenceRing], m: &SourceMask) -> Vec<Vec<f64>> {
    let e = error_map(rings, m);
    let segs = tagged_segments(rings, m);
    let mut out: Vec<Vec<f64>> = rings.iter().map(|r| vec![0.0; r.spans.len()]).collect();
    if segs.is_empty() { return out; }
    let k2 = m.scale * m.scale;
    for j in 0..m.h { for i in 0..m.w {
        let v = e[j * m.w + i];
        if v <= 0.0 { continue; }
        let w = nearest_segment((i as f64 + 0.5, j as f64 + 0.5), &segs).unwrap();
        out[segs[w].ring][segs[w].span] += v * k2;
    } }
    out
}

/// Number of sign-changing x/y derivative roots strictly inside (0,1) of one cubic coordinate.
/// Exact arithmetic, no tolerance; a double root (disc == 0) is not an extremum.
pub fn interior_roots(p0: f64, p1: f64, p2: f64, p3: f64) -> u8 {
    let a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    let b = 2.0 * (p0 - 2.0 * p1 + p2);
    let c = p1 - p0;
    let inside = |t: f64| t > 0.0 && t < 1.0;
    if a == 0.0 {
        if b == 0.0 { return 0; }
        return inside(-c / b) as u8;
    }
    let disc = b * b - 4.0 * a * c;
    if disc <= 0.0 { return 0; }
    let s = disc.sqrt();
    inside((-b + s) / (2.0 * a)) as u8 + inside((-b - s) / (2.0 * a)) as u8
}

/// C2: count of x/y extrema lying strictly inside cubic spans, i.e. extrema with no on-curve node.
pub fn missing_extrema(rings: &[ReferenceRing]) -> usize {
    let mut total = 0usize;
    for r in rings {
        let mut cur = r.start;
        for s in &r.spans {
            if let Span::Cubic { control_one: a, control_two: b, end } = s {
                total += interior_roots(cur.x, a.x, b.x, end.x) as usize
                       + interior_roots(cur.y, a.y, b.y, end.y) as usize;
            }
            cur = match s { Span::Line { end } | Span::Cubic { end, .. } => *end };
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pt(x: f64, y: f64) -> Point { Point { x, y } }

    /// Every cell accumulate writes must stay inside the chord endpoints'
    /// floor/ceil pixel bbox dilated by the shared guard. The scratch starts
    /// at -0.0 so any nonzero kernel contribution changes the cell bits.
    #[test]
    fn accumulate_writes_stay_inside_shared_kernel_guard() {
        let (w, h) = (37usize, 29usize);
        let stride = w + 2;
        let mut rng: u64 = 0x9e3779b97f4a7c15;
        let mut next = move || {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            (rng >> 11) as f64 / (1u64 << 53) as f64
        };
        let k = COVERAGE_KERNEL_REACH_PX;
        for _ in 0..20_000 {
            let p0 = (next() * w as f64, next() * h as f64);
            let p1 = (next() * w as f64, next() * h as f64);
            if p0.1 == p1.1 { continue; }
            let mut a = vec![-0.0f64; stride * h];
            let mut wr = RowWrites::default();
            accumulate(&mut a, stride, w, h, p0, p1, &mut wr);
            let x0 = p0.0.min(p1.0).floor() as i64 - k;
            let y0 = p0.1.min(p1.1).floor() as i64 - k;
            let x1 = p0.0.max(p1.0).ceil() as i64 + k;
            let y1 = p0.1.max(p1.1).ceil() as i64 + k;
            for j in 0..h {
                for i in 0..stride {
                    if a[j * stride + i].to_bits() == (-0.0f64).to_bits() { continue; }
                    let (ci, cj) = (i as i64, j as i64);
                    assert!(ci >= x0 && ci <= x1 && cj >= y0 && cj <= y1,
                        "write at ({ci}, {cj}) escaped guard bbox [{x0},{y0}]-[{x1},{y1}] for chord {p0:?}->{p1:?}");
                }
            }
        }
    }

    /// Regression: the thread-local area_error scratch is keyed on the frame
    /// GEOMETRY (stride, rows), not the buffer length. (w+2)*h collides for
    /// 13x12 and 10x15 (both 180); without geometry-keyed reuse, clear_written
    /// replays the recorded row dirt at the CURRENT stride and the second call
    /// accumulates onto stale winding (oracle fuzz case 188: area_error
    /// returned 24.65 where the fresh-buffer value is 25.0). The fresh-buffer
    /// error_map row-major sum is the reference (its contract: bit-identical
    /// to area_error). Red without the geometry key, green with it.
    #[test]
    fn area_error_scratch_reuse_keys_on_frame_geometry() {
        let polluter = vec![ReferenceRing { start: pt(1., 0.), spans: vec![
            Span::Line { end: pt(12., 0.) }, Span::Line { end: pt(12., 12.) },
            Span::Line { end: pt(1., 12.) }, Span::Line { end: pt(1., 0.) }] }];
        let m13 = SourceMask { w: 13, h: 12, ink: vec![255u8; 13 * 12], scale: 1.0, origin: (0., 12.) };
        let victim = vec![ReferenceRing { start: pt(1., 1.), spans: vec![
            Span::Line { end: pt(9., 1.) }, Span::Line { end: pt(9., 14.) },
            Span::Line { end: pt(1., 14.) }, Span::Line { end: pt(1., 1.) }] }];
        let m10 = SourceMask { w: 10, h: 15, ink: vec![255u8; 10 * 15], scale: 1.0, origin: (0., 15.) };
        let reference = {
            let mut s = 0.0f64;
            for v in error_map(&victim, &m10) { s += v; }
            s * m10.scale * m10.scale
        };
        let _ = area_error(&polluter, &m13); // dirt recorded at stride 15
        let got = area_error(&victim, &m10); // same (w+2)*h = 180, stride 12
        assert_eq!(got.to_bits(), reference.to_bits(),
            "scratch reuse must be bit-identical to fresh buffers across same-length different-geometry frames");
    }
}
