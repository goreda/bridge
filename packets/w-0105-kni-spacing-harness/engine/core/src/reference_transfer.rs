//! D4 task 2: owner/team reference transfer, font- and glyph-local.
//! A supplied reference outline (pinned) is matched to a captured glyph; from the match the module
//! learns targets (node roles, extremum axes, handle-tangent directions) and exposes a candidate
//! objective that scores candidate outlines against those targets.
//! Hard rules: a reference applies only to the glyph id in its pin (`GlyphMismatch` otherwise);
//! the pin sha256 must equal the sha256 of the reference's canonical bytes (`PinMismatch`);
//! there is no default node-count or node-position target for any other glyph; every failure is a
//! typed error, never a silent fallback. Pure, deterministic, zero dependencies (own SHA-256).
//! This module does not modify any outline; it only produces targets and scores. Matching happens in
//! a normalised frame (glyph bbox of on-curve nodes mapped to the unit square), so a reference
//! drawn at another scale or offset transfers; tangents are compared as undirected axes, so the
//! reference and capture may wind in opposite directions or start at different nodes.
use crate::reference_slice::{Point, ReferenceRing, Span};

pub const REFERENCE_FORMAT: &str = "KNIREF1";

#[derive(Clone, Debug, PartialEq)]
pub enum TransferError {
    BadPin(String),
    PinMismatch { expected: String, got: String },
    GlyphMismatch { pin: String, captured: String },
    EmptyReference,
    EmptyCaptured,
    NonFinite,
    DegenerateFrame,
    Config(String),
    RingCountMismatch { reference: usize, captured: usize },
    RingUnmatched { reference_ring: usize, cost: f64 },
    /// Rings have different nesting (exterior vs hole depth, or a different parent), or no ring with the same role is left.
    NestingMismatch { reference_ring: usize },
    NoCandidates,
}

/// Pin: sha256 (hex, 64 lowercase) of the canonical reference bytes, glyph id, provenance label.
/// The sha is an integrity check only; it is not proof of authorship.
#[derive(Clone, Debug, PartialEq)]
/// `provenance_reference` is an opaque caller-supplied label; the evidence it points at stays outside the repo.
pub struct ReferencePin { pub sha256_hex: String, pub glyph_id: String, pub provenance_reference: String }

#[derive(Clone, Debug)]
pub struct PinnedReference { pub pin: ReferencePin, pub rings: Vec<ReferenceRing> }

#[derive(Clone, Copy, Debug)]
pub struct TransferConfig {
    /// sin of the largest angle at which a node still counts as smooth / a tangent as axis-aligned.
    pub smooth_sin: f64,
    /// Max distance (normalised units) between a reference node and a captured node to match them.
    pub max_node_dist: f64,
    /// Max ring match cost (|normalised area diff| + centroid distance).
    pub max_ring_cost: f64,
}
impl Default for TransferConfig {
    fn default() -> Self { TransferConfig { smooth_sin: 0.0871557427476582 /* sin 5 deg */, max_node_dist: 0.1, max_ring_cost: 0.25 } }
}
impl TransferConfig {
    fn validate(&self) -> Result<(), TransferError> {
        for (n, v) in [("smooth_sin", self.smooth_sin), ("max_node_dist", self.max_node_dist), ("max_ring_cost", self.max_ring_cost)] {
            if !(v.is_finite() && v > 0.0) { return Err(TransferError::Config(format!("{} must be finite and > 0", n))); }
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum NodeRole { Smooth, Corner }

#[derive(Clone, Debug)]
pub struct NodeTarget {
    pub reference_ring: usize,
    pub reference_node: usize,
    /// Position in the normalised frame.
    pub pos: (f64, f64),
    pub role: NodeRole,
    /// x extremum (vertical tangent) / y extremum (horizontal tangent), smooth nodes only.
    pub extremum_x: bool,
    pub extremum_y: bool,
    /// Undirected unit tangent axis (smooth nodes); None for corners.
    pub tangent: Option<(f64, f64)>,
    /// Matched captured node (ring, node), if any within max_node_dist.
    pub captured: Option<(usize, usize)>,
}

#[derive(Clone, Debug)]
pub struct TransferTargets {
    pub pin: ReferencePin,
    pub cfg: TransferConfig,
    pub frame: Frame,
    pub targets: Vec<NodeTarget>,
    /// reference ring index -> captured ring index
    pub ring_map: Vec<usize>,
    pub reference_nodes: usize,
}

#[derive(Clone, Copy, Debug)]
pub struct Frame { pub min: (f64, f64), pub size: (f64, f64) }
impl Frame {
    fn norm(&self, p: Point) -> (f64, f64) { ((p.x - self.min.0) / self.size.0, (p.y - self.min.1) / self.size.1) }
}

fn end_of(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }
fn rings_finite(rings: &[ReferenceRing]) -> bool {
    rings.iter().all(|r| finite(r.start) && r.spans.iter().all(|s| match s {
        Span::Line { end } => finite(*end),
        Span::Cubic { control_one, control_two, end } => finite(*control_one) && finite(*control_two) && finite(*end),
    }))
}
/// On-curve nodes of a ring: node j is the end of span j (the last equals the start).
fn nodes(r: &ReferenceRing) -> Vec<Point> { r.spans.iter().map(end_of).collect() }

fn frame_of(rings: &[ReferenceRing]) -> Result<Frame, TransferError> {
    let (mut lo, mut hi) = ((f64::INFINITY, f64::INFINITY), (f64::NEG_INFINITY, f64::NEG_INFINITY));
    for r in rings { for p in nodes(r) { lo.0 = lo.0.min(p.x); lo.1 = lo.1.min(p.y); hi.0 = hi.0.max(p.x); hi.1 = hi.1.max(p.y); } }
    let size = (hi.0 - lo.0, hi.1 - lo.1);
    if !(size.0 > 0.0 && size.1 > 0.0 && size.0.is_finite() && size.1.is_finite()) { return Err(TransferError::DegenerateFrame); }
    Ok(Frame { min: lo, size })
}

// ---- SHA-256 (FIPS 180-4) ----
pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 { msg.push(0); }
    msg.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([chunk[4*i], chunk[4*i+1], chunk[4*i+2], chunk[4*i+3]]); }
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
            v = [t1.wrapping_add(t2), v[0], v[1], v[2], v[3].wrapping_add(t1), v[4], v[5], v[6]];
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}

/// Canonical bytes of a reference: format tag, glyph id, then every ring with exact f64 bits.
pub fn canonical_bytes(glyph_id: &str, rings: &[ReferenceRing]) -> Vec<u8> {
    let mut s = format!("{}\n{}\n{}\n", REFERENCE_FORMAT, glyph_id, rings.len());
    let pt = |s: &mut String, p: &Point| s.push_str(&format!("{:016x},{:016x} ", p.x.to_bits(), p.y.to_bits()));
    for r in rings {
        s.push_str(&format!("R {} ", r.spans.len())); pt(&mut s, &r.start);
        for sp in &r.spans { match sp {
            Span::Line { end } => { s.push_str("L "); pt(&mut s, end); }
            Span::Cubic { control_one, control_two, end } => { s.push_str("C "); pt(&mut s, control_one); pt(&mut s, control_two); pt(&mut s, end); }
        } }
        s.push('\n');
    }
    s.into_bytes()
}

/// Build a pin for a reference (used when the team produces the reference).
pub fn make_pin(glyph_id: &str, provenance_reference: &str, rings: &[ReferenceRing]) -> ReferencePin {
    ReferencePin { sha256_hex: sha256_hex(&canonical_bytes(glyph_id, rings)), glyph_id: glyph_id.into(), provenance_reference: provenance_reference.into() }
}

pub fn verify_pin(r: &PinnedReference) -> Result<(), TransferError> {
    let p = &r.pin;
    if p.glyph_id.is_empty() { return Err(TransferError::BadPin("glyph_id empty".into())); }
    if p.provenance_reference.is_empty() { return Err(TransferError::BadPin("provenance_reference empty".into())); }
    if p.sha256_hex.len() != 64 || !p.sha256_hex.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        return Err(TransferError::BadPin("sha256_hex must be 64 lowercase hex chars".into()));
    }
    let got = sha256_hex(&canonical_bytes(&p.glyph_id, &r.rings));
    if got != p.sha256_hex { return Err(TransferError::PinMismatch { expected: p.sha256_hex.clone(), got }); }
    Ok(())
}

// ---- node roles ----
fn unit(v: (f64, f64)) -> Option<(f64, f64)> { let l = v.0.hypot(v.1); if l > 0.0 { Some((v.0 / l, v.1 / l)) } else { None } }
/// Normalised-frame incoming and outgoing directions at node j (end of span j), falling back to the
/// chord when a handle is degenerate.
fn dirs(r: &ReferenceRing, j: usize, f: &Frame) -> (Option<(f64, f64)>, Option<(f64, f64)>) {
    let n = r.spans.len();
    let at = |p: Point| f.norm(p);
    let node = at(end_of(&r.spans[j]));
    let prev = at(if j == 0 { r.start } else { end_of(&r.spans[j - 1]) });
    let next_span = &r.spans[(j + 1) % n];
    let next = at(end_of(next_span));
    let d = |a: (f64, f64), b: (f64, f64)| (b.0 - a.0, b.1 - a.1);
    let din = match &r.spans[j] {
        Span::Cubic { control_two, .. } => unit(d(at(*control_two), node)).or_else(|| unit(d(prev, node))),
        Span::Line { .. } => unit(d(prev, node)),
    };
    let dout = match next_span {
        Span::Cubic { control_one, .. } => unit(d(node, at(*control_one))).or_else(|| unit(d(node, next))),
        Span::Line { .. } => unit(d(node, next)),
    };
    (din, dout)
}
fn role_at(r: &ReferenceRing, j: usize, f: &Frame, cfg: &TransferConfig) -> (NodeRole, bool, bool, Option<(f64, f64)>) {
    match dirs(r, j, f) {
        (Some(a), Some(b)) => {
            let cross = a.0 * b.1 - a.1 * b.0;
            let dot = a.0 * b.0 + a.1 * b.1;
            if dot > 0.0 && cross.abs() <= cfg.smooth_sin {
                let t = unit((a.0 + b.0, a.1 + b.1)).unwrap_or(b);
                (NodeRole::Smooth, t.0.abs() <= cfg.smooth_sin, t.1.abs() <= cfg.smooth_sin, Some(t))
            } else { (NodeRole::Corner, false, false, None) }
        }
        _ => (NodeRole::Corner, false, false, None),
    }
}


/// Flattened outline (cubics sampled at 16 steps) used only for containment tests.
fn flatten(r: &ReferenceRing) -> Vec<(f64, f64)> {
    let mut v = vec![(r.start.x, r.start.y)];
    let mut p = r.start;
    for s in &r.spans {
        match s {
            Span::Line { end } => { v.push((end.x, end.y)); p = *end; }
            Span::Cubic { control_one: a, control_two: b, end } => {
                for k in 1..=16 { let t = k as f64 / 16.0; let u = 1.0 - t;
                    v.push((u*u*u*p.x + 3.0*u*u*t*a.x + 3.0*u*t*t*b.x + t*t*t*end.x, u*u*u*p.y + 3.0*u*u*t*a.y + 3.0*u*t*t*b.y + t*t*t*end.y)); }
                p = *end;
            }
        }
    }
    v
}
fn inside(pt: (f64, f64), poly: &[(f64, f64)]) -> bool {
    let n = poly.len(); let mut c = false;
    for i in 0..n { let (a, b) = (poly[i], poly[(i + 1) % n]);
        if (a.1 > pt.1) != (b.1 > pt.1) && pt.0 < a.0 + (pt.1 - a.1) / (b.1 - a.1) * (b.0 - a.0) { c = !c; } }
    c
}
fn poly_area(poly: &[(f64, f64)]) -> f64 {
    let n = poly.len(); let mut a = 0.0;
    for i in 0..n { let (p, q) = (poly[i], poly[(i + 1) % n]); a += p.0 * q.1 - q.0 * p.1; }
    (a / 2.0).abs()
}
/// Nesting of each ring: (depth, parent). Ring i is inside ring j when i's start point lies inside
/// j's flattened outline; the parent is the smallest-area container. Depth 0 = exterior, odd = hole.
/// Rings whose start point lies on another outline's boundary are ambiguous only if containment
/// cannot be decided by the start point; that case is not detected here (start-point test only).
pub fn nesting(rings: &[ReferenceRing]) -> Vec<(usize, Option<usize>)> {
    let polys: Vec<Vec<(f64, f64)>> = rings.iter().map(flatten).collect();
    let areas: Vec<f64> = polys.iter().map(|p| poly_area(p)).collect();
    let mut parent = vec![None; rings.len()];
    for i in 0..rings.len() {
        let mut best: Option<usize> = None;
        for j in 0..rings.len() { if i != j && inside(polys[i][0], &polys[j]) && areas[j] > areas[i]
            && best.map_or(true, |b| areas[j] < areas[b]) { best = Some(j); } }
        parent[i] = best;
    }
    (0..rings.len()).map(|i| { let mut d = 0; let mut c = parent[i]; while let Some(p) = c { d += 1; c = parent[p]; if d > rings.len() { break; } } (d, parent[i]) }).collect()
}

fn ring_stats(r: &ReferenceRing, f: &Frame) -> (f64, (f64, f64)) {
    let pts: Vec<(f64, f64)> = nodes(r).into_iter().map(|p| f.norm(p)).collect();
    let n = pts.len();
    let mut a = 0.0;
    for i in 0..n { let (p, q) = (pts[i], pts[(i + 1) % n]); a += p.0 * q.1 - q.0 * p.1; }
    let (mut lo, mut hi) = ((f64::INFINITY, f64::INFINITY), (f64::NEG_INFINITY, f64::NEG_INFINITY));
    for p in &pts { lo.0 = lo.0.min(p.0); lo.1 = lo.1.min(p.1); hi.0 = hi.0.max(p.0); hi.1 = hi.1.max(p.1); }
    ((a / 2.0).abs(), ((lo.0 + hi.0) / 2.0, (lo.1 + hi.1) / 2.0))
}

/// Match a pinned reference to a captured glyph and learn targets. `captured_glyph_id` must equal the
/// pin's glyph id; the reference never applies to another glyph.
pub fn learn_targets(reference: &PinnedReference, captured_glyph_id: &str, captured: &[ReferenceRing], cfg: &TransferConfig) -> Result<TransferTargets, TransferError> {
    cfg.validate()?;
    verify_pin(reference)?;
    if reference.pin.glyph_id != captured_glyph_id {
        return Err(TransferError::GlyphMismatch { pin: reference.pin.glyph_id.clone(), captured: captured_glyph_id.into() });
    }
    if reference.rings.is_empty() || reference.rings.iter().any(|r| r.spans.is_empty()) { return Err(TransferError::EmptyReference); }
    if captured.is_empty() || captured.iter().any(|r| r.spans.is_empty()) { return Err(TransferError::EmptyCaptured); }
    if !rings_finite(&reference.rings) || !rings_finite(captured) { return Err(TransferError::NonFinite); }
    if reference.rings.len() != captured.len() { return Err(TransferError::RingCountMismatch { reference: reference.rings.len(), captured: captured.len() }); }
    let (fr, fc) = (frame_of(&reference.rings)?, frame_of(captured)?);
    // ring matching: greedy by (cost, ref idx, cap idx)
    let rs: Vec<_> = reference.rings.iter().map(|r| ring_stats(r, &fr)).collect();
    let cs: Vec<_> = captured.iter().map(|r| ring_stats(r, &fc)).collect();
    let (nr, nc) = (nesting(&reference.rings), nesting(captured));
    {
        let (mut dr, mut dc): (Vec<usize>, Vec<usize>) = (nr.iter().map(|x| x.0).collect(), nc.iter().map(|x| x.0).collect());
        dr.sort(); dc.sort();
        if dr != dc {
            let i = (0..dr.len()).find(|&k| dr[k] != dc[k]).unwrap_or(0);
            let depth = dr[i];
            let ring = (0..nr.len()).find(|&k| nr[k].0 == depth).unwrap_or(0);
            return Err(TransferError::NestingMismatch { reference_ring: ring });
        }
    }
    // Rings are matched outer-first so a hole is only matched to a hole whose parent is the matched parent.
    let mut order: Vec<usize> = (0..rs.len()).collect();
    order.sort_by_key(|&i| (nr[i].0, i));
    let mut ring_map = vec![usize::MAX; rs.len()];
    let mut used = vec![false; cs.len()];
    for &i in &order {
        let want_parent = nr[i].1.map(|p| ring_map[p]);
        let mut best: Option<(f64, usize)> = None;
        for j in 0..cs.len() {
            if used[j] || nc[j].0 != nr[i].0 || nc[j].1 != want_parent { continue; }
            let c = (rs[i].0 - cs[j].0).abs() + (rs[i].1 .0 - cs[j].1 .0).hypot(rs[i].1 .1 - cs[j].1 .1);
            if best.map_or(true, |b| c < b.0) { best = Some((c, j)); }
        }
        let Some((cost, j)) = best else { return Err(TransferError::NestingMismatch { reference_ring: i }); };
        if cost > cfg.max_ring_cost { return Err(TransferError::RingUnmatched { reference_ring: i, cost }); }
        ring_map[i] = j; used[j] = true;
    }
    // node targets
    let mut targets = vec![];
    for (ri, rr) in reference.rings.iter().enumerate() {
        let cr = &captured[ring_map[ri]];
        let cn: Vec<(f64, f64)> = nodes(cr).into_iter().map(|p| fc.norm(p)).collect();
        let mut cand = vec![];
        for (j, p) in nodes(rr).into_iter().enumerate() {
            let q = fr.norm(p);
            for (k, c) in cn.iter().enumerate() { cand.push(((q.0 - c.0).hypot(q.1 - c.1), j, k)); }
        }
        cand.sort_by(|x, y| x.0.partial_cmp(&y.0).unwrap().then(x.1.cmp(&y.1)).then(x.2.cmp(&y.2)));
        let mut m: Vec<Option<usize>> = vec![None; rr.spans.len()];
        let mut taken = vec![false; cn.len()];
        for (d, j, k) in cand { if d <= cfg.max_node_dist && m[j].is_none() && !taken[k] { m[j] = Some(k); taken[k] = true; } }
        for j in 0..rr.spans.len() {
            let (role, ex, ey, tangent) = role_at(rr, j, &fr, cfg);
            targets.push(NodeTarget { reference_ring: ri, reference_node: j, pos: fr.norm(end_of(&rr.spans[j])),
                role, extremum_x: ex, extremum_y: ey, tangent, captured: m[j].map(|k| (ring_map[ri], k)) });
        }
    }
    let reference_nodes = targets.len();
    Ok(TransferTargets { pin: reference.pin.clone(), cfg: *cfg, frame: fc, targets, ring_map, reference_nodes })
}

#[derive(Clone, Debug, PartialEq)]
pub struct ObjectiveScore {
    /// Reference nodes with no candidate node within max_node_dist.
    pub missing_nodes: usize,
    pub role_mismatches: usize,
    pub extremum_misses: usize,
    /// Sum over matched smooth targets of sin(angle between candidate and target tangent axes).
    pub tangent_error: f64,
    /// total = missing + role + extremum + tangent_error. Lower is better.
    pub total: f64,
    /// |candidate nodes - reference nodes|; reported separately, used only as the tie-break.
    pub node_count_delta: usize,
}

/// Score one candidate outline (same glyph, captured frame) against learned targets.
pub fn score_candidate(targets: &TransferTargets, candidate: &[ReferenceRing]) -> Result<ObjectiveScore, TransferError> {
    if candidate.is_empty() || candidate.iter().any(|r| r.spans.is_empty()) { return Err(TransferError::EmptyCaptured); }
    if !rings_finite(candidate) { return Err(TransferError::NonFinite); }
    let cfg = &targets.cfg;
    let f = &targets.frame;
    let cnodes: Vec<Vec<(f64, f64)>> = candidate.iter().map(|r| nodes(r).into_iter().map(|p| f.norm(p)).collect()).collect();
    let (mut missing, mut role, mut ext, mut tan) = (0usize, 0usize, 0usize, 0.0f64);
    // match per reference ring to the candidate ring at the same mapped index (candidates keep ring order)
    let mut by_ring: Vec<Vec<&NodeTarget>> = vec![vec![]; targets.ring_map.len()];
    for t in &targets.targets { by_ring[t.reference_ring].push(t); }
    for (ri, ts) in by_ring.iter().enumerate() {
        let ci = targets.ring_map[ri];
        let Some(cn) = cnodes.get(ci) else { missing += ts.len(); continue };
        let mut cand = vec![];
        for (a, t) in ts.iter().enumerate() { for (k, c) in cn.iter().enumerate() { cand.push(((t.pos.0 - c.0).hypot(t.pos.1 - c.1), a, k)); } }
        cand.sort_by(|x, y| x.0.partial_cmp(&y.0).unwrap().then(x.1.cmp(&y.1)).then(x.2.cmp(&y.2)));
        let mut m: Vec<Option<usize>> = vec![None; ts.len()];
        let mut taken = vec![false; cn.len()];
        for (d, a, k) in cand { if d <= cfg.max_node_dist && m[a].is_none() && !taken[k] { m[a] = Some(k); taken[k] = true; } }
        for (a, t) in ts.iter().enumerate() {
            let Some(k) = m[a] else { missing += 1; continue };
            let (r, ex, ey, tg) = role_at(&candidate[ci], k, f, cfg);
            if r != t.role { role += 1; }
            if t.extremum_x && !ex { ext += 1; }
            if t.extremum_y && !ey { ext += 1; }
            if let (Some(a), Some(b)) = (t.tangent, tg) { tan += (a.0 * b.1 - a.1 * b.0).abs(); }
            else if t.tangent.is_some() { tan += 1.0; } // target smooth, candidate corner: already a role mismatch; full tangent penalty
        }
    }
    let cn_total: usize = candidate.iter().map(|r| r.spans.len()).sum();
    Ok(ObjectiveScore { missing_nodes: missing, role_mismatches: role, extremum_misses: ext, tangent_error: tan,
        total: (missing + role + ext) as f64 + tan,
        node_count_delta: cn_total.abs_diff(targets.reference_nodes) })
}

/// Index of the best candidate (lowest total, then lowest node_count_delta, then lowest index).
pub fn select_candidate(targets: &TransferTargets, candidates: &[Vec<ReferenceRing>]) -> Result<(usize, ObjectiveScore), TransferError> {
    if candidates.is_empty() { return Err(TransferError::NoCandidates); }
    let mut best: Option<(usize, ObjectiveScore)> = None;
    for (i, c) in candidates.iter().enumerate() {
        let s = score_candidate(targets, c)?;
        let better = match &best { None => true, Some((_, b)) => s.total < b.total || (s.total == b.total && s.node_count_delta < b.node_count_delta) };
        if better { best = Some((i, s)); }
    }
    Ok(best.unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn p(x: f64, y: f64) -> Point { Point { x, y } }
    /// Rounded rect-ish glyph: 4 smooth extremum nodes (circle) as one ring.
    fn circle(r: f64, k: f64, ox: f64, oy: f64) -> ReferenceRing {
        ReferenceRing { start: p(ox + r, oy), spans: vec![
            Span::Cubic { control_one: p(ox + r, oy + k), control_two: p(ox + k, oy + r), end: p(ox, oy + r) },
            Span::Cubic { control_one: p(ox - k, oy + r), control_two: p(ox - r, oy + k), end: p(ox - r, oy) },
            Span::Cubic { control_one: p(ox - r, oy - k), control_two: p(ox - k, oy - r), end: p(ox, oy - r) },
            Span::Cubic { control_one: p(ox + k, oy - r), control_two: p(ox + r, oy - k), end: p(ox + r, oy) },
        ]}
    }
    fn square(s: f64) -> ReferenceRing {
        ReferenceRing { start: p(0.0, 0.0), spans: vec![
            Span::Line { end: p(s, 0.0) }, Span::Line { end: p(s, s) }, Span::Line { end: p(0.0, s) }, Span::Line { end: p(0.0, 0.0) } ] }
    }
    fn pinned(gid: &str, rings: Vec<ReferenceRing>) -> PinnedReference { PinnedReference { pin: make_pin(gid, "test-provenance", &rings), rings } }
    #[test]
    fn sha256_known_vectors() {
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(sha256_hex(&[b'a'; 1000]).len(), 64);
    }
    #[test]
    fn pin_rules() {
        let mut r = pinned("g", vec![circle(10.0, 5.5, 0.0, 0.0)]);
        assert!(verify_pin(&r).is_ok());
        r.rings[0].start = p(11.0, 0.0);
        assert!(matches!(verify_pin(&r), Err(TransferError::PinMismatch { .. })));
        let mut b = pinned("g", vec![circle(10.0, 5.5, 0.0, 0.0)]); b.pin.sha256_hex = "ABC".into();
        assert!(matches!(verify_pin(&b), Err(TransferError::BadPin(_))));
        let mut e = pinned("g", vec![circle(10.0, 5.5, 0.0, 0.0)]); e.pin.provenance_reference.clear();
        assert!(matches!(verify_pin(&e), Err(TransferError::BadPin(_))));
    }
    #[test]
    fn applies_only_to_pinned_glyph() {
        let r = pinned("g", vec![circle(10.0, 5.5, 0.0, 0.0)]);
        let e = learn_targets(&r, "S", &[circle(10.0, 5.5, 0.0, 0.0)], &TransferConfig::default()).unwrap_err();
        assert!(matches!(e, TransferError::GlyphMismatch { .. }));
    }
    #[test]
    fn scaled_translated_capture_scores_zero_and_is_orientation_free() {
        let r = pinned("g", vec![circle(10.0, 5.5228475, 0.0, 0.0)]);
        // capture: 3x scale, offset, 1 unit rounding of nothing; reversed winding and shifted start
        let mut cap = circle(30.0, 16.5685425, 100.0, 50.0);
        let t = learn_targets(&r, "g", &[cap.clone()], &TransferConfig::default()).unwrap();
        assert_eq!(t.targets.len(), 4);
        assert!(t.targets.iter().all(|x| x.role == NodeRole::Smooth && (x.extremum_x ^ x.extremum_y) && x.captured.is_some()));
        let s = score_candidate(&t, &[cap.clone()]).unwrap();
        assert_eq!(s.missing_nodes + s.role_mismatches + s.extremum_misses, 0);
        assert!(s.tangent_error < 1e-6, "{:?}", s);
        // reversed winding
        let ns: Vec<Point> = cap.spans.iter().map(end_of).collect();
        let k = 16.5685425; let (ox, oy, rr) = (100.0, 50.0, 30.0);
        cap = ReferenceRing { start: p(ox + rr, oy), spans: vec![
            Span::Cubic { control_one: p(ox + rr, oy - k), control_two: p(ox + k, oy - rr), end: p(ox, oy - rr) },
            Span::Cubic { control_one: p(ox - k, oy - rr), control_two: p(ox - rr, oy - k), end: p(ox - rr, oy) },
            Span::Cubic { control_one: p(ox - rr, oy + k), control_two: p(ox - k, oy + rr), end: p(ox, oy + rr) },
            Span::Cubic { control_one: p(ox + k, oy + rr), control_two: p(ox + rr, oy + k), end: p(ox + rr, oy) },
        ]};
        assert_eq!(ns.len(), 4);
        let s2 = score_candidate(&t, &[cap]).unwrap();
        assert!(s2.total < 1e-6, "{:?}", s2);
    }
    #[test]
    fn worse_candidates_score_higher_and_selection_is_deterministic() {
        let r = pinned("g", vec![circle(10.0, 5.5228475, 0.0, 0.0)]);
        let good = circle(30.0, 16.5685425, 0.0, 0.0);
        let t = learn_targets(&r, "g", &[good.clone()], &TransferConfig::default()).unwrap();
        let mut tilted = good.clone(); // tilt one handle off the extremum axis
        if let Span::Cubic { control_one, .. } = &mut tilted.spans[0] { control_one.x -= 8.0; }
        let mut missing = good.clone(); // drop the extremum node at span 0 end by merging spans 0 and 1 into a line
        missing.spans[0] = Span::Line { end: end_of(&good.spans[0]) };
        let sg = score_candidate(&t, &[good.clone()]).unwrap();
        let st = score_candidate(&t, &[tilted.clone()]).unwrap();
        let sm = score_candidate(&t, &[missing.clone()]).unwrap();
        assert!(st.total > sg.total && sm.total > sg.total, "{:?} {:?} {:?}", sg, st, sm);
        let c = vec![vec![tilted], vec![good.clone()], vec![good], vec![missing]];
        let (i, _) = select_candidate(&t, &c).unwrap();
        assert_eq!(i, 1);
        assert_eq!(select_candidate(&t, &[]).unwrap_err(), TransferError::NoCandidates);
    }
    #[test]
    fn hole_matches_hole_not_similar_exterior() {
        // glyph with exterior + hole; the capture lists the rings in the opposite order
        let ext = circle(20.0, 11.0457, 0.0, 0.0);
        let hole = circle(8.0, 4.4183, 0.0, 0.0);
        let r = pinned("o", vec![ext.clone(), hole.clone()]);
        let t = learn_targets(&r, "o", &[hole.clone(), ext.clone()], &TransferConfig::default()).unwrap();
        assert_eq!(t.ring_map, vec![1, 0]);
        assert_eq!(nesting(&[ext.clone(), hole.clone()]), vec![(0, None), (1, Some(0))]);
        // capture without a hole (two separate exteriors) must be refused, not mis-matched
        let far = circle(8.0, 4.4183, 100.0, 0.0);
        let e = learn_targets(&r, "o", &[ext, far], &TransferConfig::default()).unwrap_err();
        assert!(matches!(e, TransferError::NestingMismatch { .. }), "{:?}", e);
    }
    #[test]
    fn corners_are_corners_and_ring_mismatch_is_typed() {
        let r = pinned("H", vec![square(10.0)]);
        let t = learn_targets(&r, "H", &[square(40.0)], &TransferConfig::default()).unwrap();
        assert!(t.targets.iter().all(|x| x.role == NodeRole::Corner && x.tangent.is_none()));
        assert_eq!(score_candidate(&t, &[square(40.0)]).unwrap().total, 0.0);
        let e = learn_targets(&r, "H", &[square(40.0), square(5.0)], &TransferConfig::default()).unwrap_err();
        assert!(matches!(e, TransferError::RingCountMismatch { reference: 1, captured: 2 }));
        let bad = TransferConfig { max_node_dist: 0.0, ..Default::default() };
        assert!(matches!(learn_targets(&r, "H", &[square(40.0)], &bad), Err(TransferError::Config(_))));
        let flat = ReferenceRing { start: p(0.0, 0.0), spans: vec![Span::Line { end: p(5.0, 0.0) }, Span::Line { end: p(0.0, 0.0) }] };
        assert!(matches!(learn_targets(&pinned("H", vec![flat.clone()]), "H", &[flat], &TransferConfig::default()), Err(TransferError::DegenerateFrame)));
    }
}
