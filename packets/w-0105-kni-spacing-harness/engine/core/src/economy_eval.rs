//! Production FontEconomyEvaluator. Every step that cannot be verified returns None.
//! No mock score, no fallback estimate, no default tolerance. All numeric
//! parameters are supplied by the caller in `EvalConfig` and recorded in the pins.
//! Regions are ring-index regions ("ring{i}"): the snapshot carries no region or
//! construction record, so construction is derived from span kinds and vertex sets
//! only, and `Improved` is never emitted.
use crate::capture::{capture_png, decode_png_gray};
use crate::cff_container::{cff_one, charstring, CffGlyph};
use crate::economy::{ConstructionComparison, FontAssessment, FontEconomyEvaluator, RegionAssessment};
use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

#[derive(Clone, Debug)]
pub struct EvalConfig {
    pub frame_id: String,
    pub scale_k: f64,
    pub threshold: u8,
    pub canvas: (usize, usize),
    pub capture_eps: f64,
    /// Samples per cubic when rasterizing and measuring. A render resolution, recorded in the frame pin.
    pub flatten_steps: usize,
    pub expected_source_sha256: String,
    pub advance: u16,
    /// Caller-declared render resource caps, independent of raster resolution.
    pub render_limits: RenderLimits,
}

/// Vector-payload budgets only, not an RSS or whole-evaluator memory guarantee.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RenderLimits {
    pub max_pixels: usize,
    pub max_flatten_steps: usize,
    pub max_edges: usize,
    pub max_working_bytes: usize,
}

/// A render request cannot wrap its canvas dimensions or abort on the mask allocation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RenderMaskError {
    CanvasOverflow { width: usize, height: usize },
    AllocationFailed { pixels: usize },
    BudgetExceeded { pixels: usize, max_pixels: usize },
    Canonicalization(CanonicalizationError),
    ResourceLimit { resource: &'static str, value: usize, limit: usize },
    ArithmeticOverflow { resource: &'static str },
    VectorAllocationFailed { resource: &'static str, elements: usize },
}
impl std::fmt::Display for RenderMaskError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, "{self:?}") }
}
impl std::error::Error for RenderMaskError {}

/// Bound is a safety guard, not a quality threshold: |coord| <= 2^60
/// implies differences <= 2^61 and sums of products <= 2^123 < i128::MAX.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CanonicalizationError { CoordinateOutsideSafeDomain, AllocationFailed }

pub struct ProductionEvaluator {
    cfg: EvalConfig,
    source_pin: String,
    frame_pin: String,
    domain: String,
    mask: Vec<bool>,
    raw: Vec<Vec<Point>>,
    /// Per raw ring: true when the ring is capture-space degenerate by the fitter's own rule
    /// (shoelace area < 0.5 px^2 over `CapturedRing.points`, capture_fit::fit_captured_economy_observed).
    /// The fitter never emits such rings, so they take no part in the match_rings bijection.
    raw_droppable: Vec<bool>,
    ox: f64,
    oy: f64,
}

// ---------- sha256 (zero dependency) ----------
pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut m = data.to_vec();
    m.push(0x80);
    while m.len() % 64 != 56 { m.push(0); }
    m.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([chunk[4*i],chunk[4*i+1],chunk[4*i+2],chunk[4*i+3]]); }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v[7]=v[6]; v[6]=v[5]; v[5]=v[4]; v[4]=v[3].wrapping_add(t1);
            v[3]=v[2]; v[2]=v[1]; v[1]=v[0]; v[0]=t1.wrapping_add(t2);
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}

// ---------- Type2 decode of the integer charstring this crate emits ----------
fn decode_charstring(b: &[u8], advance: u16) -> Option<Vec<ReferenceRing>> {
    let mut i = 0usize;
    let mut stack: Vec<i64> = Vec::new();
    let mut first = true;
    let mut cur = (0i64, 0i64);
    let mut rings: Vec<ReferenceRing> = Vec::new();
    let pt = |c: (i64, i64)| Point { x: c.0 as f64, y: c.1 as f64 };
    loop {
        let op = *b.get(i)?;
        i += 1;
        if op == 28 {
            let v = i16::from_be_bytes([*b.get(i)?, *b.get(i + 1)?]) as i64;
            i += 2;
            stack.push(v);
            continue;
        }
        if first {
            if stack.is_empty() || stack[0] != advance as i64 { return None; }
            stack.remove(0);
            first = false;
        }
        match op {
            21 => {
                if stack.len() != 2 { return None; }
                if let Some(r) = rings.last() { if r.spans.is_empty() { return None; } }
                cur = (cur.0 + stack[0], cur.1 + stack[1]);
                rings.push(ReferenceRing { start: pt(cur), spans: Vec::new() });
            }
            5 => {
                if stack.len() != 2 { return None; }
                let r = rings.last_mut()?;
                cur = (cur.0 + stack[0], cur.1 + stack[1]);
                r.spans.push(Span::Line { end: pt(cur) });
            }
            8 => {
                if stack.len() != 6 { return None; }
                let r = rings.last_mut()?;
                let c1 = (cur.0 + stack[0], cur.1 + stack[1]);
                let c2 = (c1.0 + stack[2], c1.1 + stack[3]);
                let e = (c2.0 + stack[4], c2.1 + stack[5]);
                r.spans.push(Span::Cubic { control_one: pt(c1), control_two: pt(c2), end: pt(e) });
                cur = e;
            }
            14 => {
                if !stack.is_empty() || i != b.len() { return None; }
                for r in &rings { if r.spans.is_empty() { return None; } }
                return Some(rings);
            }
            _ => return None,
        }
        stack.clear();
    }
}

fn spans_eq(a: &Span, b: &Span) -> bool {
    match (a, b) {
        (Span::Line { end: x }, Span::Line { end: y }) => x == y,
        (Span::Cubic { control_one: a1, control_two: a2, end: a3 }, Span::Cubic { control_one: b1, control_two: b2, end: b3 }) => a1 == b1 && a2 == b2 && a3 == b3,
        _ => false,
    }
}
fn rings_eq(a: &[ReferenceRing], b: &[ReferenceRing]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| x.start == y.start && x.spans.len() == y.spans.len() && x.spans.iter().zip(&y.spans).all(|(p, q)| spans_eq(p, q)))
}

// ---------- geometry ----------
type Key = (i64, i64);
fn key(p: Point) -> Key { (p.x as i64, p.y as i64) }
fn ipt(p: Point) -> (i128, i128) { (p.x as i128, p.y as i128) }
fn span_end(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn first_nonzero(c: &[(i128, i128)]) -> Option<(i128, i128)> { c.iter().copied().find(|d| *d != (0, 0)) }

/// (incoming, outgoing) tangent at the vertex that starts span k.
pub(crate) fn tangents(r: &ReferenceRing, k: usize) -> Option<((i128, i128), (i128, i128))> {
    let n = r.spans.len();
    let start_of = |j: usize| if j == 0 { r.start } else { span_end(&r.spans[j - 1]) };
    let sub = |a: Point, b: Point| { let (ax, ay) = ipt(a); let (bx, by) = ipt(b); (bx - ax, by - ay) };
    let out = |j: usize| -> Option<(i128, i128)> {
        let s = start_of(j);
        match &r.spans[j] {
            Span::Line { end } => first_nonzero(&[sub(s, *end)]),
            Span::Cubic { control_one, control_two, end } => first_nonzero(&[sub(s, *control_one), sub(s, *control_two), sub(s, *end)]),
        }
    };
    let inc = |j: usize| -> Option<(i128, i128)> {
        let s = start_of(j);
        match &r.spans[j] {
            Span::Line { end } => first_nonzero(&[sub(s, *end)]),
            Span::Cubic { control_one, control_two, end } => first_nonzero(&[sub(*control_two, *end), sub(*control_one, *end), sub(s, *end)]),
        }
    };
    let prev = if k == 0 { n - 1 } else { k - 1 };
    Some((inc(prev)?, out(k)?))
}
pub(crate) fn smooth(a: (i128, i128), b: (i128, i128)) -> bool { a.0 * b.1 - a.1 * b.0 == 0 && a.0 * b.0 + a.1 * b.1 > 0 }

fn flatten(r: &ReferenceRing, steps: usize) -> (Vec<Point>, Vec<usize>) {
    flatten_into(r, steps, Vec::new(), Vec::new())
}
fn flatten_into(r: &ReferenceRing, steps: usize, mut pts: Vec<Point>, mut vidx: Vec<usize>) -> (Vec<Point>, Vec<usize>) {
    pts.push(r.start);
    vidx.push(0);
    let mut cur = r.start;
    for (k, s) in r.spans.iter().enumerate() {
        match s {
            Span::Line { end } => { pts.push(*end); cur = *end; }
            Span::Cubic { control_one: a, control_two: b, end } => {
                for i in 1..=steps {
                    let t = i as f64 / steps as f64; let u = 1.0 - t;
                    let (w0, w1, w2, w3) = (u*u*u, 3.0*u*u*t, 3.0*u*t*t, t*t*t);
                    if i == steps { pts.push(*end); } else {
                        pts.push(Point { x: w0*cur.x + w1*a.x + w2*b.x + w3*end.x, y: w0*cur.y + w1*a.y + w2*b.y + w3*end.y });
                    }
                }
                cur = *end;
            }
        }
        if k + 1 < r.spans.len() { vidx.push(pts.len() - 1); }
    }
    // pts ends equal to start (closed); drop the duplicate closing sample
    pts.pop();
    (pts, vidx)
}
/// Exact axis-extremum events. Vertex: the nonzero direction of travel along the axis flips sign at the
/// vertex, decided from integer control-point differences (derivative signs, no flattening). Interior:
/// the cubic's derivative quadratic has simple roots strictly inside (0,1), counted exactly in i128.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ExtremumEvent { Vertex(i64, i64, u8), Interior([(i64, i64); 4], u8, u8) }

fn comp(p: Point, q: Point, axis: u8) -> i128 { let (a, b) = if axis == 0 { (p.x, q.x) } else { (p.y, q.y) }; b as i128 - a as i128 }
fn sgn(v: i128) -> i32 { if v > 0 { 1 } else if v < 0 { -1 } else { 0 } }
/// Derivative coefficients (a,b,c) along the axis for span k of ring r.
fn dcoef(r: &ReferenceRing, k: usize, axis: u8) -> (i128, i128, i128) {
    let s = if k == 0 { r.start } else { span_end(&r.spans[k - 1]) };
    match &r.spans[k] {
        Span::Line { end } => { let d = comp(s, *end, axis); (d, d, d) }
        Span::Cubic { control_one, control_two, end } => (comp(s, *control_one, axis), comp(*control_one, *control_two, axis), comp(*control_two, *end, axis)),
    }
}
fn first_nz(v: [i128; 3]) -> i32 { for x in v { if x != 0 { return sgn(x); } } 0 }
/// Direction just after the vertex that starts span k, using only span k (0 when span k has no motion on the axis).
fn imm_after(r: &ReferenceRing, k: usize, axis: u8) -> i32 { let (a, b, c) = dcoef(r, k, axis); first_nz([a, b, c]) }
/// Direction just before that vertex, using only span k-1.
fn imm_before(r: &ReferenceRing, k: usize, axis: u8) -> i32 { let n = r.spans.len(); let (a, b, c) = dcoef(r, (k + n - 1) % n, axis); first_nz([c, b, a]) }
fn sign_after(r: &ReferenceRing, k: usize, axis: u8) -> i32 {
    let n = r.spans.len();
    for s in 0..n { let v = imm_after(r, (k + s) % n, axis); if v != 0 { return v; } }
    0
}
fn sign_before(r: &ReferenceRing, k: usize, axis: u8) -> i32 {
    let n = r.spans.len();
    for s in 1..=n { let v = imm_before(r, (k + n - s + 1) % n, axis); if v != 0 { return v; } }
    0
}
/// Number of simple sign changes of q(t)=A t^2+B t+C on the open interval (0,1); exact.
fn interior_sign_changes(a: i128, b: i128, c: i128) -> u8 {
    let (qa, qb, qc) = (a - 2 * b + c, 2 * (b - a), a);
    let q1 = c;
    if qa == 0 {
        if qb == 0 { return 0; }
        return if sgn(qc) * sgn(q1) < 0 { 1 } else { 0 };
    }
    if sgn(qc) * sgn(q1) < 0 { return 1; }
    let disc = qb * qb - 4 * qa * qc;
    if disc <= 0 { return 0; }
    if qc == 0 || q1 == 0 {
        // one root at an endpoint; the other is a product/sum relation
        let other_num; let other_den;
        if qc == 0 { other_num = -qb; other_den = qa; } else { other_num = qc; other_den = qa; }
        // q(1)=0: roots multiply to qc/qa, so other = qc/qa; q(0)=0: other = -qb/qa
        let (nn, dd) = if other_den < 0 { (-other_num, -other_den) } else { (other_num, other_den) };
        return if nn > 0 && nn < dd { 1 } else { 0 };
    }
    // same strict sign at both ends, two interior roots iff vertex inside (0,1) and parabola opens toward the endpoint sign (vertex value then has the opposite sign, disc>0)
    let (vn, vd) = if qa < 0 { (qb, -2 * qa) } else { (-qb, 2 * qa) };
    if !(vn > 0 && vn < vd) { return 0; }
    if sgn(qa) != sgn(qc) { return 0; }
    2
}
fn extrema_events(r: &ReferenceRing) -> Vec<ExtremumEvent> {
    let mut out = Vec::new();
    let vs = vertices(r);
    for axis in 0..2u8 {
        for k in 0..r.spans.len() {
            // A vertex strictly inside a plateau (no motion on the axis on both sides) is never an extremum;
            // plateau end vertices carry the event when the direction flips across the whole plateau.
            let (ib, ia) = (imm_before(r, k, axis), imm_after(r, k, axis));
            if ib == 0 && ia == 0 { continue; }
            let (bf, af) = (sign_before(r, k, axis), sign_after(r, k, axis));
            if bf != 0 && af != 0 && bf != af { out.push(ExtremumEvent::Vertex(vs[k].0, vs[k].1, axis)); }
        }
    }
    let mut cur = r.start;
    for (k, sp) in r.spans.iter().enumerate() {
        if let Span::Cubic { control_one, control_two, end } = sp {
            let ks = [key(cur), key(*control_one), key(*control_two), key(*end)];
            for axis in 0..2u8 {
                let (a, b, c) = dcoef(r, k, axis);
                let n = interior_sign_changes(a, b, c);
                if n > 0 { out.push(ExtremumEvent::Interior(ks, axis, n)); }
            }
        }
        cur = span_end(sp);
    }
    out.sort(); out
}
/// Public for diagnostics: exact extremum events of one ring, as strings.
pub fn extrema_vertices(r: &ReferenceRing) -> Vec<String> { extrema_events(r).iter().map(|e| format!("{:?}", e)).collect() }
fn vertices(r: &ReferenceRing) -> Vec<Key> {
    let mut v = vec![key(r.start)];
    for s in &r.spans[..r.spans.len() - 1] { v.push(key(span_end(s))); }
    v
}
fn corner_keys_and_smooth(r: &ReferenceRing) -> Option<Vec<(Key, bool)>> {
    let vs = vertices(r);
    let mut out = Vec::new();
    for k in 0..r.spans.len() { let (a, b) = tangents(r, k)?; out.push((vs[k], smooth(a, b))); }
    Some(out)
}
fn cubic_keys(r: &ReferenceRing) -> Vec<[Key; 4]> {
    let mut v = Vec::new();
    let mut cur = r.start;
    for s in &r.spans {
        if let Span::Cubic { control_one, control_two, end } = s { v.push([key(cur), key(*control_one), key(*control_two), key(*end)]); }
        cur = span_end(s);
    }
    v.sort(); v
}
fn straight_fwd(a: Point, b: Point, c: Point) -> bool {
    let (abx, aby) = (b.x as i128 - a.x as i128, b.y as i128 - a.y as i128);
    let (bcx, bcy) = (c.x as i128 - b.x as i128, c.y as i128 - b.y as i128);
    abx * bcy == aby * bcx && abx * bcx + aby * bcy > 0
}
/// Measurement form: exact forward-collinear integer Line runs collapsed, so geometry-identical
/// outlines yield bit-identical measurements. Structural checks use the original ring.
pub fn canon(r: &ReferenceRing) -> Result<ReferenceRing, CanonicalizationError> {
    const SAFE_COORD: f64 = (1u64 << 60) as f64;
    let safe = |p: Point| p.x.is_finite() && p.y.is_finite() && p.x.abs() <= SAFE_COORD && p.y.abs() <= SAFE_COORD;
    if !safe(r.start) || !r.spans.iter().all(|s| match s {
        Span::Line { end } => safe(*end),
        Span::Cubic { control_one, control_two, end } => safe(*control_one) && safe(*control_two) && safe(*end),
    }) { return Err(CanonicalizationError::CoordinateOutsideSafeDomain); }
    let mut spans: Vec<Span> = Vec::new();
    let mut starts: Vec<Point> = Vec::new();
    spans.try_reserve_exact(r.spans.len()).map_err(|_| CanonicalizationError::AllocationFailed)?;
    starts.try_reserve_exact(r.spans.len()).map_err(|_| CanonicalizationError::AllocationFailed)?;
    Ok(canon_into(r, spans, starts))
}
// Frozen legacy test helper is used only within the proven coordinate domain.
#[cfg(test)]
fn canon_safe(r: &ReferenceRing) -> ReferenceRing { canon_into(r, Vec::new(), Vec::new()) }
fn canon_into(r: &ReferenceRing, mut spans: Vec<Span>, mut starts: Vec<Point>) -> ReferenceRing {
    let mut cur = r.start;
    for s in &r.spans {
        let end = span_end(s);
        if let Span::Line { .. } = s {
            if let Some(Span::Line { end: pe }) = spans.last().cloned() {
                let ps = *starts.last().unwrap();
                if straight_fwd(ps, pe, end) { *spans.last_mut().unwrap() = Span::Line { end }; cur = end; continue; }
            }
        }
        starts.push(cur); spans.push(s.clone()); cur = end;
    }
    ReferenceRing { start: r.start, spans }
}
fn dist_pt_seg(p: Point, a: Point, b: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let l2 = dx*dx + dy*dy;
    let t = if l2 == 0.0 { 0.0 } else { (((p.x - a.x)*dx + (p.y - a.y)*dy) / l2).clamp(0.0, 1.0) };
    let (cx, cy) = (a.x + t*dx, a.y + t*dy);
    ((p.x - cx).powi(2) + (p.y - cy).powi(2)).sqrt()
}
/// The fitter's degenerate-ring rule (capture_fit::fit_captured_economy_observed): a ring whose
/// capture-space shoelace area is below half a pixel square draws nothing at capture resolution and
/// never reaches output. Evaluated on `CapturedRing.points` (post-RDP), exactly as the fitter does.
fn capture_degenerate_area_below_half_px2(p: &[Point]) -> bool {
    let mut a2 = 0.0f64;
    for i in 0..p.len() {
        let u = p[i];
        let v = p[(i + 1) % p.len()];
        a2 += u.x * v.y - v.x * u.y;
    }
    a2.abs() / 2.0 < 0.5
}

fn dist_to_poly(p: Point, poly: &[Point]) -> f64 {
    let n = poly.len();
    (0..n).map(|i| dist_pt_seg(p, poly[i], poly[(i + 1) % n])).fold(f64::INFINITY, f64::min)
}

impl ProductionEvaluator {
    pub fn new(cfg: EvalConfig, source_png: &[u8]) -> Result<Self, String> {
        if !(cfg.scale_k.is_finite() && cfg.scale_k > 0.0) { return Err("scale_k".into()); }
        if cfg.flatten_steps == 0 || cfg.frame_id.is_empty() || cfg.canvas.0 == 0 || cfg.canvas.1 == 0 { return Err("config".into()); }
        if !(cfg.capture_eps.is_finite() && cfg.capture_eps > 0.0) { return Err("capture_eps".into()); }
        let sha = sha256_hex(source_png);
        if sha != cfg.expected_source_sha256 { return Err(format!("source sha mismatch: {sha}")); }
        let (w, h, gray) = decode_png_gray(source_png)?;
        if (w, h) != cfg.canvas { return Err(format!("source dims {w}x{h} differ from canvas")); }
        let mask: Vec<bool> = gray.iter().map(|&g| g < cfg.threshold).collect();
        let mc = capture_png(source_png, cfg.capture_eps)?;
        let raw: Vec<Vec<Point>> = mc.rings.iter().map(|r| r.raw.clone()).collect();
        if raw.is_empty() { return Err("no source rings".into()); }
        let raw_droppable: Vec<bool> = mc.rings.iter().map(|r| capture_degenerate_area_below_half_px2(&r.points)).collect();
        let frame_pin = format!("{}|K={:?}|thr={}|canvas={}x{}|origin=({:?},{:?})|steps={}|eps={:?}", cfg.frame_id, cfg.scale_k, cfg.threshold, w, h, mc.origin_x, mc.origin_y, cfg.flatten_steps, cfg.capture_eps);
        let frame_pin = format!("{frame_pin}|render_limits=px{}/steps{}/edges{}/payload{}", cfg.render_limits.max_pixels, cfg.render_limits.max_flatten_steps, cfg.render_limits.max_edges, cfg.render_limits.max_working_bytes);
        let domain = format!("scan-domain-{}x{}", w, h);
        Ok(Self { source_pin: sha, frame_pin, domain, mask, raw, raw_droppable, ox: mc.origin_x, oy: mc.origin_y, cfg })
    }

    /// Final integer font bytes (CFF) for one glyph, the same container path as emission.
    pub fn final_font_bytes(&self, g: &DrawnGlyph) -> Option<Vec<u8>> {
        let notdef = CffGlyph { name: ".notdef".into(), advance: self.cfg.advance, outline: DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] } };
        let glyph = CffGlyph { name: "glyph".into(), advance: self.cfg.advance, outline: g.clone() };
        cff_one("EconomyEval", &[notdef, glyph]).ok()
    }
    /// Encode to the final integer charstring and parse it back; geometry must round-trip exactly.
    fn roundtrip(&self, g: &DrawnGlyph) -> Option<DrawnGlyph> {
        if g.rings.is_empty() { return None; }
        let cs = charstring(&CffGlyph { name: "glyph".into(), advance: self.cfg.advance, outline: g.clone() }).ok()?;
        self.final_font_bytes(g)?;
        let rings = decode_charstring(&cs, self.cfg.advance)?;
        if !rings_eq(&rings, &g.rings) { return None; }
        Some(DrawnGlyph { glyph_id: g.glyph_id.clone(), rings })
    }
    fn to_px(&self, p: Point) -> Point { Point { x: p.x / self.cfg.scale_k, y: p.y / self.cfg.scale_k } }
    /// Coverage mask of `g` in the pinned frame (w*h, row-major). The rasterizer `render_iou` uses;
    /// public so parity tests can compare masks bit for bit.
    pub fn render_mask(&self, g: &DrawnGlyph) -> Result<Vec<bool>, RenderMaskError> {
        self.render_mask_with_limits(g, self.cfg.render_limits)
    }
    /// Tighten only the pixel cap, retaining the declared edge/step/vector caps.
    pub fn render_mask_with_budget(&self, g: &DrawnGlyph, max_pixels: usize) -> Result<Vec<bool>, RenderMaskError> {
        let mut limits = self.cfg.render_limits;
        limits.max_pixels = limits.max_pixels.min(max_pixels);
        self.render_mask_with_limits(g, limits)
    }
    /// Preflight all ring/span/sample counts before canon or raster vectors allocate.
    /// Payload accounting excludes caller-owned inputs, allocator overhead and stack.
    pub fn render_mask_with_limits(&self, g: &DrawnGlyph, limits: RenderLimits) -> Result<Vec<bool>, RenderMaskError> {
        use RenderMaskError as E;
        let add = |a: usize, b: usize| a.checked_add(b).ok_or(E::ArithmeticOverflow { resource: "render counts" });
        let mul = |a: usize, b: usize| a.checked_mul(b).ok_or(E::ArithmeticOverflow { resource: "render bytes" });
        let (w, h) = self.cfg.canvas;
        let pixels = w.checked_mul(h).ok_or(E::CanvasOverflow { width: w, height: h })?;
        if pixels > limits.max_pixels { return Err(E::BudgetExceeded { pixels, max_pixels: limits.max_pixels }); }
        let steps = self.cfg.flatten_steps;
        if steps == 0 || steps > limits.max_flatten_steps { return Err(E::ResourceLimit { resource: "flatten_steps", value: steps, limit: limits.max_flatten_steps }); }
        let mut edge_count = 0usize;
        let mut max_points = 1usize;
        let mut max_spans = 1usize;
        for r in &g.rings {
            let mut n = 1usize;
            for span in &r.spans { n = add(n, match span { Span::Line { .. } => 1, Span::Cubic { .. } => steps })?; }
            max_points = max_points.max(n);
            max_spans = max_spans.max(r.spans.len());
            // flatten removes the closing duplicate: edge count = n - 1.
            edge_count = add(edge_count, n - 1)?;
            if edge_count > limits.max_edges { return Err(E::ResourceLimit { resource: "edges", value: edge_count, limit: limits.max_edges }); }
        }
        // edges + crossings + flattened points + image points + vertex indices +
        // canonical spans + canonical start points + output mask. Conservative sum
        // includes some buffers that do not overlap in lifetime.
        let mut working = pixels;
        for (count, size) in [
            (edge_count, std::mem::size_of::<(Point, Point)>()),
            (edge_count, std::mem::size_of::<(f64, i32)>()),
            (max_points, 2 * std::mem::size_of::<Point>()),
            (max_spans, std::mem::size_of::<usize>()),
            (max_spans, std::mem::size_of::<Span>() + std::mem::size_of::<Point>()),
        ] { working = add(working, mul(count, size)?)?; }
        if working > limits.max_working_bytes { return Err(E::ResourceLimit { resource: "vector payload bytes", value: working, limit: limits.max_working_bytes }); }
        fn reserve<T>(n: usize, resource: &'static str) -> Result<Vec<T>, RenderMaskError> {
            let mut v = Vec::new();
            v.try_reserve_exact(n).map_err(|_| RenderMaskError::VectorAllocationFailed { resource, elements: n })?;
            Ok(v)
        }
        let mut out = Vec::new();
        out.try_reserve_exact(pixels).map_err(|_| E::AllocationFailed { pixels })?;
        out.resize(pixels, false);
        let mut edges: Vec<(Point, Point)> = reserve(edge_count, "edges")?;
        for r in &g.rings {
            let canonical = canon(r).map_err(E::Canonicalization)?;
            let pts = reserve(max_points, "flattened points")?;
            let vidx = reserve(max_spans, "vertex indices")?;
            let (pts, _) = flatten_into(&canonical, steps, pts, vidx);
            let mut img = reserve(max_points, "image points")?;
            for p in pts { let q = self.to_px(p); img.push(Point { x: q.x + self.ox, y: -q.y - self.oy }); }
            for i in 0..img.len() { edges.push((img[i], img[(i + 1) % img.len()])); }
        }
        let mut xs: Vec<(f64, i32)> = reserve(edge_count, "scanline crossings")?;
        for j in 0..h {
            let yc = j as f64 + 0.5;
            xs.clear();
            for (a, b) in &edges {
                if (a.y <= yc) != (b.y <= yc) {
                    let x = a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x);
                    xs.push((x, if b.y > a.y { 1 } else { -1 }));
                }
            }
            // In-place sort avoids stable-sort scratch allocation. Equal crossings
            // span zero pixel width; their winding increments sum before the next x.
            xs.sort_unstable_by(|p, q| p.0.partial_cmp(&q.0).unwrap_or(std::cmp::Ordering::Equal));
            let mut wind = 0i128;
            for k in 0..xs.len() {
                wind += xs[k].1 as i128;
                if wind != 0 && k + 1 < xs.len() {
                    let lo = (xs[k].0 - 0.5).ceil().max(0.0) as usize;
                    let hi = ((xs[k + 1].0 - 0.5).ceil().max(0.0) as usize).min(w);
                    for i in lo..hi { out[j * w + i] = true; }
                }
            }
        }
        Ok(out)
    }
    /// Source ink mask (gray < threshold), w*h row-major, as pinned at construction.
    pub fn source_mask(&self) -> &[bool] { &self.mask }
    fn render_iou(&self, g: &DrawnGlyph) -> Option<f64> {
        let cover = self.render_mask(g).ok()?;
        let (mut inter, mut uni) = (0u64, 0u64);
        for (i, &c) in cover.iter().enumerate() {
            let s = self.mask[i];
            if c && s { inter += 1; }
            if c || s { uni += 1; }
        }
        if uni == 0 { return None; }
        Some(inter as f64 / uni as f64)
    }
    /// raw ring index matched to each glyph ring; must be a bijection or evidence is unusable.
    /// The bijection ranges over the raw rings the fitter can actually emit: capture-degenerate
    /// raw rings (raw_droppable, same <0.5 px^2 rule as capture_fit) are skipped. With no droppable
    /// ring the kept index list is 0..raw.len() and the search is bit-identical to the old rule.
    fn match_rings(&self, g: &DrawnGlyph) -> Option<Vec<usize>> {
        let kept: Vec<usize> = (0..self.raw.len()).filter(|&j| !self.raw_droppable[j]).collect();
        if g.rings.len() != kept.len() { return None; }
        let polys: Vec<Vec<Point>> = g.rings.iter().map(|r| Some(flatten(&canon(r).ok()?, self.cfg.flatten_steps).0.iter().map(|p| self.to_px(*p)).collect())).collect::<Option<_>>()?;
        let mut taken = vec![false; self.raw.len()];
        let mut out = vec![0usize; polys.len()];
        for &j in &kept {
            let raw = &self.raw[j];
            let mut best = (f64::INFINITY, usize::MAX);
            for (i, poly) in polys.iter().enumerate() {
                let m = raw.iter().map(|p| dist_to_poly(*p, poly)).sum::<f64>() / raw.len() as f64;
                if m < best.0 { best = (m, i); }
            }
            if best.1 == usize::MAX || taken[best.1] { return None; }
            taken[best.1] = true; out[best.1] = j;
        }
        Some(out)
    }
}

impl FontEconomyEvaluator for ProductionEvaluator {
    fn assess(&mut self, baseline: &DrawnGlyph, candidate: &DrawnGlyph) -> Option<FontAssessment> {
        let base = self.roundtrip(baseline)?;
        let cand = self.roundtrip(candidate)?;
        if base.rings.len() != cand.rings.len() { return None; }
        let matching = self.match_rings(&base)?;
        let font_iou = self.render_iou(&cand)?;
        if !font_iou.is_finite() { return None; }
        let steps = self.cfg.flatten_steps;
        let mut regions = Vec::new();
        for i in 0..base.rings.len() {
            let (b, c) = (&base.rings[i], &cand.rings[i]);
            let raw = &self.raw[matching[i]];
            let poly: Vec<Point> = flatten(&canon(c).ok()?, steps).0.iter().map(|p| self.to_px(*p)).collect();
            let d1: Vec<f64> = raw.iter().map(|p| dist_to_poly(*p, &poly)).collect();
            let d2: Vec<f64> = poly.iter().map(|p| dist_to_poly(*p, raw)).collect();
            let mean2 = |d: &[f64]| d.iter().map(|x| x * x).sum::<f64>() / d.len() as f64;
            let sfe = (mean2(&d1) + mean2(&d2)) / 2.0;
            let maxdev = d1.iter().chain(d2.iter()).cloned().fold(0.0, f64::max);
            if !(sfe.is_finite() && maxdev.is_finite()) { return None; }
            let (bv, cv) = (vertices(b), vertices(c));
            let bs = corner_keys_and_smooth(b)?;
            let cs = corner_keys_and_smooth(c)?;
            let corners = |s: &[(Key, bool)]| { let mut v: Vec<Key> = s.iter().filter(|x| !x.1).map(|x| x.0).collect(); v.sort(); v };
            let corners_preserved = corners(&bs) == corners(&cs);
            let extrema_preserved = extrema_events(b) == extrema_events(c);
            let continuity_preserved = key(b.start) == key(c.start)
                && cs.iter().all(|(k, sm)| bs.iter().find(|x| x.0 == *k).map_or(false, |x| x.1 == *sm));
            let construction = if key(b.start) != key(c.start) { ConstructionComparison::Unknown }
                else if cubic_keys(b) != cubic_keys(c) || !cv.iter().all(|k| bv.contains(k)) { ConstructionComparison::Regressed }
                else { ConstructionComparison::Preserved };
            regions.push(RegionAssessment { region_id: format!("ring{i}"), squared_fit_error: sfe, maximum_deviation: maxdev, construction, extrema_preserved, corners_preserved, continuity_preserved });
        }
        Some(FontAssessment { source_pin: self.source_pin.clone(), render_frame_pin: self.frame_pin.clone(), domain: self.domain.clone(), threshold: self.cfg.threshold, font_iou, regions })
    }
}

// ---------- gate measurement fields (additive; assess() is unchanged) ----------
/// Version of the node count definition. The same function counts the glyph's own potrace budget and every lever result.
pub const NODE_COUNT_DEFINITION: &str = "nodecount-v1|decoded-integer-CFF|node=on-curve-point-of-final-outline|vertices()-of-parsed-back-rings|no-collinear-collapse";

/// One gate measurement point: the node count of the final outline and its IoU in the pinned frame.
#[derive(Clone, Debug, PartialEq)]
pub struct CurvePoint {
    pub nodes: usize,
    pub font_iou: f64,
}

/// Potrace budget record for one glyph, counted by the same parser and frame as every other node count.
#[derive(Clone, Debug, PartialEq)]
pub struct PotraceBudget {
    pub potrace_nodes: usize,
    /// sha256 of the final integer font bytes of the potrace outline (per-glyph source identity).
    pub potrace_glyph_sha256: String,
    pub node_count_parser_pin: String,
}

impl ProductionEvaluator {
    /// Pin of the node count definition AND the style frame it is counted in. Budget and measurement must carry the same value.
    pub fn node_count_parser_pin(&self) -> String {
        format!("{}|{}", NODE_COUNT_DEFINITION, self.frame_pin)
    }
    /// On-curve points of the final outline: encode to integer CFF, parse back, require exact round trip, count ring vertices.
    pub fn node_count(&self, g: &DrawnGlyph) -> Option<usize> {
        let r = self.roundtrip(g)?;
        Some(r.rings.iter().map(|ring| vertices(ring).len()).sum())
    }
    /// One (nodes, IoU) point. None when the outline does not verify.
    pub fn curve_point(&self, g: &DrawnGlyph) -> Option<CurvePoint> {
        let r = self.roundtrip(g)?;
        let nodes = r.rings.iter().map(|ring| vertices(ring).len()).sum();
        let font_iou = self.render_iou(&r)?;
        if !font_iou.is_finite() { return None; }
        Some(CurvePoint { nodes, font_iou })
    }
    /// The glyph's own potrace node count, same parser and frame as `node_count`.
    pub fn potrace_budget(&self, potrace: &DrawnGlyph) -> Option<PotraceBudget> {
        let potrace_nodes = self.node_count(potrace)?;
        let bytes = self.final_font_bytes(potrace)?;
        Some(PotraceBudget { potrace_nodes, potrace_glyph_sha256: sha256_hex(&bytes), node_count_parser_pin: self.node_count_parser_pin() })
    }
}

#[cfg(test)]
impl ProductionEvaluator {
    fn legacy_row_stream_iou(&self, g: &DrawnGlyph) -> Option<f64> {
        let (w, h) = self.cfg.canvas;
        let mut edges: Vec<(Point, Point)> = Vec::new();
        for r in &g.rings {
            let (pts, _) = flatten(&canon_safe(r), self.cfg.flatten_steps);
            let img: Vec<Point> = pts.iter().map(|p| { let q = self.to_px(*p); Point { x: q.x + self.ox, y: -q.y - self.oy } }).collect();
            for i in 0..img.len() { edges.push((img[i], img[(i + 1) % img.len()])); }
        }
        let (mut inter, mut uni) = (0u64, 0u64);
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
            let mut row = vec![false; w];
            let mut wind = 0;
            for k in 0..xs.len() {
                wind += xs[k].1;
                if wind != 0 && k + 1 < xs.len() {
                    let lo = (xs[k].0 - 0.5).ceil().max(0.0) as usize;
                    let hi = ((xs[k + 1].0 - 0.5).ceil().max(0.0) as usize).min(w);
                    for i in lo..hi { row[i] = true; }
                }
            }
            for i in 0..w {
                let s = self.mask[j * w + i];
                if row[i] && s { inter += 1; }
                if row[i] || s { uni += 1; }
            }
        }
        if uni == 0 { return None; }
        Some(inter as f64 / uni as f64)
    }
}

#[cfg(test)]
impl ProductionEvaluator {
    fn legacy_row_stream_mask(&self, g: &DrawnGlyph) -> Vec<bool> {
        let (w, h) = self.cfg.canvas;
        let mut edges: Vec<(Point, Point)> = Vec::new();
        for r in &g.rings {
            let (pts, _) = flatten(&canon_safe(r), self.cfg.flatten_steps);
            let img: Vec<Point> = pts.iter().map(|p| { let q = self.to_px(*p); Point { x: q.x + self.ox, y: -q.y - self.oy } }).collect();
            for i in 0..img.len() { edges.push((img[i], img[(i + 1) % img.len()])); }
        }
        let mut mask = Vec::new();
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
            let mut row = vec![false; w];
            let mut wind = 0;
            for k in 0..xs.len() {
                wind += xs[k].1;
                if wind != 0 && k + 1 < xs.len() {
                    let lo = (xs[k].0 - 0.5).ceil().max(0.0) as usize;
                    let hi = ((xs[k + 1].0 - 0.5).ceil().max(0.0) as usize).min(w);
                    for i in lo..hi { row[i] = true; }
                }
            }
            mask.extend(row);
        }
        mask
    }
}

#[cfg(test)]
mod render_mask_contract_tests {
    use super::*;
    fn evaluator(w: usize, h: usize, ox: f64, oy: f64, mask: Vec<bool>) -> ProductionEvaluator {
        ProductionEvaluator {
            cfg: EvalConfig { frame_id: "synthetic-row-stream-contract".into(), scale_k: 1.25,
                threshold: 128, canvas: (w, h), capture_eps: 0.5, flatten_steps: 17,
                expected_source_sha256: String::new(), advance: 1000, render_limits: RenderLimits { max_pixels: w.checked_mul(h).unwrap_or(usize::MAX), max_flatten_steps: 17, max_edges: 4096, max_working_bytes: 1 << 24 } },
            source_pin: String::new(), frame_pin: String::new(), domain: String::new(),
            mask, raw: vec![], raw_droppable: vec![], ox, oy,
        }
    }
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn ring(points: &[(f64, f64)]) -> ReferenceRing {
        ReferenceRing { start: p(points[0].0, points[0].1), spans: points[1..].iter().map(|&(x, y)| Span::Line { end: p(x, y) }).collect() }
    }
    #[test]
    fn full_mask_matches_frozen_old_row_stream_bits_and_iou() {
        let rect = ring(&[(0.,0.),(8.,0.),(8.,-9.),(0.,-9.),(0.,0.)]);
        let counter = ring(&[(2.,-2.),(2.,-6.),(6.,-6.),(6.,-2.),(2.,-2.)]);
        let clipped = ring(&[(-10.,5.),(40.,5.),(40.,-40.),(-10.,-40.),(-10.,5.)]);
        let bow = ring(&[(0.,0.),(9.,-9.),(0.,-9.),(9.,0.),(0.,0.)]);
        let split = ring(&[(0.,0.),(4.,0.),(8.,0.),(8.,-9.),(0.,-9.),(0.,0.)]);
        let curve = ReferenceRing { start: p(1.,-1.), spans: vec![
            Span::Cubic { control_one: p(20.,3.), control_two: p(-6.,-15.), end: p(8.,-10.) },
            Span::Line { end: p(1.,-1.) }] };
        let cases = vec![vec![], vec![rect.clone()], vec![rect, counter], vec![clipped], vec![bow], vec![split], vec![curve]];
        let mut checked = 0;
        for (w,h) in [(1,1), (17,9), (31,23)] {
            for (ox,oy) in [(0.,0.), (-3.5,2.5), (0.5,-0.5)] {
                for phase in 0..4 {
                    let source: Vec<bool> = (0..w*h).map(|i| match phase { 0 => false, 1 => true, 2 => i % 2 == 0, _ => (i * 37 + 11) % 19 < 7 }).collect();
                    let ev = evaluator(w,h,ox,oy,source);
                    for rings in &cases {
                        let g = DrawnGlyph { glyph_id: "synthetic".into(), rings: rings.clone() };
                        let cover = ev.render_mask(&g).unwrap();
                        assert_eq!(cover, ev.legacy_row_stream_mask(&g), "mask differs at {w}x{h}, origin={ox},{oy}, phase={phase}");
                        assert_eq!(ev.render_iou(&g).map(f64::to_bits), ev.legacy_row_stream_iou(&g).map(f64::to_bits));
                        checked += 1;
                    }
                }
            }
        }
        println!("frozen-row-stream parity: {checked} synthetic mask and IoU comparisons, bit-identical");
    }
    #[test]
    fn full_vec_allocation_delta_is_explicit() {
        let (w,h) = (17,9);
        let ev = evaluator(w,h,0.,0.,vec![false; w*h]);
        let full = ev.render_mask(&DrawnGlyph { glyph_id: "empty".into(), rings: vec![] }).unwrap();
        let old_row = vec![false; w];
        let element_bytes = std::mem::size_of::<bool>();
        assert_eq!(full.len(), w*h);
        assert_eq!(old_row.len(), w);
        assert_eq!(full.capacity() - old_row.capacity(), w*(h-1));
        println!("mask Vec<bool> allocation: old live row={} bytes, new full={} bytes, delta={} bytes; source/edge/xs allocations excluded", old_row.capacity()*element_bytes, full.capacity()*element_bytes, (full.capacity()-old_row.capacity())*element_bytes);
        assert_eq!(ev.render_mask_with_budget(&DrawnGlyph { glyph_id: "empty".into(), rings: vec![] }, w*h-1), Err(RenderMaskError::BudgetExceeded { pixels: w*h, max_pixels: w*h-1 }));
    }
    #[test]
    fn canvas_and_working_arithmetic_overflow_are_typed() {
        let g = DrawnGlyph { glyph_id: "empty".into(), rings: vec![] };
        let ev = evaluator(usize::MAX,2,0.,0.,vec![]);
        assert_eq!(ev.render_mask_with_limits(&g, RenderLimits { max_pixels: usize::MAX, max_flatten_steps: 17, max_edges: 0, max_working_bytes: usize::MAX }), Err(RenderMaskError::CanvasOverflow { width: usize::MAX, height: 2 }));
        let ev = evaluator(usize::MAX,1,0.,0.,vec![]);
        assert_eq!(ev.render_mask_with_limits(&g, RenderLimits { max_pixels: usize::MAX, max_flatten_steps: 17, max_edges: 0, max_working_bytes: usize::MAX }), Err(RenderMaskError::ArithmeticOverflow { resource: "render counts" }));
    }
    #[test]
    fn tiny_canvas_does_not_bypass_step_edge_or_working_caps() {
        let mut ev = evaluator(1,1,0.,0.,vec![false]);
        let g = DrawnGlyph { glyph_id: "tiny".into(), rings: vec![ReferenceRing {
            start: p(0.,0.), spans: vec![Span::Cubic { control_one: p(1.,1.), control_two: p(1.,-1.), end: p(0.,0.) }]
        }] };
        let mut limits = ev.cfg.render_limits;
        limits.max_edges = 16;
        assert_eq!(ev.render_mask_with_limits(&g, limits), Err(RenderMaskError::ResourceLimit { resource: "edges", value: 17, limit: 16 }));
        limits = ev.cfg.render_limits;
        limits.max_flatten_steps = 16;
        assert_eq!(ev.render_mask_with_limits(&g, limits), Err(RenderMaskError::ResourceLimit { resource: "flatten_steps", value: 17, limit: 16 }));
        limits = ev.cfg.render_limits;
        limits.max_working_bytes = 1;
        assert!(matches!(ev.render_mask_with_limits(&g, limits), Err(RenderMaskError::ResourceLimit { resource: "vector payload bytes", .. })));
        ev.cfg.flatten_steps = usize::MAX;
        limits.max_flatten_steps = usize::MAX;
        assert_eq!(ev.render_mask_with_limits(&g, limits), Err(RenderMaskError::ArithmeticOverflow { resource: "render counts" }));
        println!("tiny-canvas preflight: step, edge, vector-byte and sample-overflow refusals before allocations");
    }
    #[test]
    fn canonicalization_refuses_unsafe_domain_before_i128_math() {
        for huge in [f64::MAX, -f64::MAX, f64::INFINITY, f64::NEG_INFINITY, f64::NAN, (1u64 << 61) as f64] {
            let r = ring(&[(huge,0.), (-huge,1.), (huge,2.), (huge,0.)]);
            assert!(matches!(canon(&r), Err(CanonicalizationError::CoordinateOutsideSafeDomain)));
            let ev = evaluator(2,2,0.,0.,vec![false;4]);
            assert!(matches!(ev.render_mask(&DrawnGlyph { glyph_id: "unsafe".into(), rings: vec![r] }), Err(RenderMaskError::Canonicalization(_))));
        }
        let edge = (1u64 << 60) as f64;
        assert!(canon(&ring(&[(edge,edge),(-edge,-edge),(edge,-edge),(edge,edge)])).is_ok());
    }
}


#[cfg(test)]
mod match_rings_degenerate_tests {
    use super::*;
    fn ev(raw: Vec<Vec<Point>>, droppable: Vec<bool>) -> ProductionEvaluator {
        ProductionEvaluator {
            cfg: EvalConfig { frame_id: "match-rings-degenerate".into(), scale_k: 1.0,
                threshold: 128, canvas: (32, 32), capture_eps: 0.5, flatten_steps: 16,
                expected_source_sha256: String::new(), advance: 1000,
                render_limits: RenderLimits { max_pixels: 32 * 32, max_flatten_steps: 16, max_edges: 4096, max_working_bytes: 1 << 24 } },
            source_pin: String::new(), frame_pin: String::new(), domain: String::new(),
            mask: vec![false; 32 * 32], raw, raw_droppable: droppable, ox: 0.0, oy: 0.0,
        }
    }
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    fn line_ring(points: &[(f64, f64)]) -> ReferenceRing {
        ReferenceRing { start: p(points[0].0, points[0].1), spans: points[1..].iter().map(|&(x, y)| Span::Line { end: p(x, y) }).collect() }
    }
    // big square in glyph space; with scale_k = 1 and zero origin its to_px polygon equals these coords
    const BIG: [(f64, f64); 5] = [(4., -4.), (28., -4.), (28., -28.), (4., -28.), (4., -4.)];
    const BIG2: [(f64, f64); 5] = [(6., -6.), (12., -6.), (12., -12.), (6., -12.), (6., -6.)];
    fn raw_points(rect: &[(f64, f64); 5]) -> Vec<Point> { rect.iter().map(|&(x, y)| p(x, y)).collect() }
    fn glyph(rings: Vec<ReferenceRing>) -> DrawnGlyph { DrawnGlyph { glyph_id: "g".into(), rings } }

    #[test]
    fn degenerate_rule_matches_the_fitter_exactly() {
        // boundary parity with capture_fit::fit_captured_economy_observed (area < 0.5 px^2, post-RDP points)
        assert!(capture_degenerate_area_below_half_px2(&[]));
        assert!(capture_degenerate_area_below_half_px2(&[p(0., 0.), p(1., 0.), p(0., 0.5)])); // area 0.25
        assert!(!capture_degenerate_area_below_half_px2(&[p(0., 0.), p(1., 0.), p(0., 1.)])); // area exactly 0.5: kept (< is strict)
        assert!(capture_degenerate_area_below_half_px2(&[p(0., 0.), p(0., 0.5), p(1., 0.)])); // clockwise, area 0.25: sign-free (abs)
    }

    #[test]
    fn match_rings_skips_capture_degenerate_raw_rings() {
        // the reported failure shape: the source has one sub-half-pixel ring the fitter drops;
        // the produced glyph has one ring fewer than the raw set
        let tiny = vec![p(1., 1.), p(1.4, 1.), p(1., 1.4)]; // area 0.08 px^2
        let ev = ev(vec![tiny, raw_points(&BIG)], vec![true, false]);
        let one = glyph(vec![line_ring(&BIG)]);
        assert_eq!(ev.match_rings(&one), Some(vec![1]), "the single glyph ring must bind to the non-degenerate raw ring 1");
        // the old failure mode inverted: a glyph carrying the dropped ring count no longer fabricates a match
        let two = glyph(vec![line_ring(&BIG), line_ring(&BIG2)]);
        assert_eq!(ev.match_rings(&two), None);
    }

    #[test]
    fn match_rings_equal_count_path_is_unchanged() {
        // no droppable ring: identical behavior to the old bijection over all raw rings
        let ev = ev(vec![raw_points(&BIG), raw_points(&BIG2)], vec![false, false]);
        let both = glyph(vec![line_ring(&BIG), line_ring(&BIG2)]);
        assert_eq!(ev.match_rings(&both), Some(vec![0, 1]));
        let both_swapped = glyph(vec![line_ring(&BIG2), line_ring(&BIG)]);
        assert_eq!(ev.match_rings(&both_swapped), Some(vec![1, 0]));
        let one = glyph(vec![line_ring(&BIG)]);
        assert_eq!(ev.match_rings(&one), None, "count mismatch still refuses when nothing is droppable");
    }
}
