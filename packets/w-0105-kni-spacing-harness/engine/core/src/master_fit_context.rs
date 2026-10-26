//! Master fit context (M1). Fits several masters of ONE glyph so that the outlines are topologically
//! compatible: same ring count, orientation, hole flags, landmark/role sequence, identical span-kind
//! sequence and node count per ring. Compatible multi-master outlines are returned for a caller to
//! consume; variable-font interpolation / export is out of scope and is NOT claimed here.
//!
//! Method: each ring is cut at the caller-supplied homologous landmarks (indices into the capture's raw
//! ring). Every cut segment is fitted separately per master, but the DECISIONS that shape topology are
//! made for the whole master group at once: a segment becomes a Line only if it is straight in every
//! master, otherwise a cubic in every master; if any master fails the cubic fit the segment is split at
//! the same target half arc length in ALL masters - the nearest available
//! interior sample is selected separately in each master, so the actual fractions
//! may differ - and both halves are decided again.
//! The result is identical by construction and re-verified before return. Incompatible input is a
//! typed refusal; there is no independent per-master fallback and no `compatible_topology=true` that
//! was not re-verified.
//!
//! Frame: font point = raw capture point * scale (raw is bbox-relative, y-up, see capture.rs); the
//! per-master origin offset is NOT added to the fit (bbox-relative shape frame is what correspondence needs).
//! captured.origin_x/y and scale are preserved verbatim in the receipt as frame metadata only; no global
//! position / style alignment across masters is performed or claimed.
use crate::capture::MeasuredContour;
use crate::cubic_fit::{fit_run, FitOutcome, FitPolicy};
use crate::lever_api::hash_rings;
use crate::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

#[derive(Clone, Debug, PartialEq)]
pub struct AxisCoordinate { pub tag: [u8; 4], pub value: f64 }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LandmarkRole { Start, XMin, XMax, YMin, YMax, Corner, Smooth }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Orientation { Cw, Ccw }
#[derive(Clone, Debug)]
pub struct LandmarkRef { pub master_id: String, pub ring_index: usize, pub raw_point_index: usize, pub role: LandmarkRole }
#[derive(Clone, Debug)]
pub struct ContourCorrespondence {
    pub correspondence_id: String,
    pub hole: bool,
    pub orientation: Orientation,
    /// landmarks[column][..]: exactly one LandmarkRef per master in each column (homologous landmark).
    pub landmarks: Vec<Vec<LandmarkRef>>,
}
#[derive(Clone, Debug)]
pub struct MasterInput {
    pub master_id: String,
    pub axes: Vec<AxisCoordinate>,
    pub glyph_id: String,
    pub captured: MeasuredContour,
    pub scale: f64,
    /// full source SHA
    pub source_pin: String,
}
#[derive(Clone, Debug)]
pub struct MasterSet { pub inputs: Vec<MasterInput>, pub correspondence: Vec<ContourCorrespondence> }
#[derive(Clone, Debug)]
pub struct MasterOutput { pub master_id: String, pub axes: Vec<AxisCoordinate>, pub outline: DrawnGlyph, pub source_pin: String }
#[derive(Clone, Debug)]
pub struct MasterFitResult { pub glyph_id: String, pub masters: Vec<MasterOutput>, pub compatible_topology: bool, pub receipt: String }
#[derive(Clone, Debug, PartialEq)]
pub enum MasterFitError {
    BadAxes(String), DuplicateMaster(String), MissingCorrespondence(String), InvalidLandmark(String),
    IncompatibleTopology(String), UnsupportedConstraint(String), NonFinite(String),
}
use MasterFitError as E;


// ----- measurement-only fit trace (additive; optional collection) -----

/// Kind of one emitted span, recorded in the trace.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpanKind { Line, Cubic }

/// One emitted span in one master's ring, traced to its decision origin.
/// Identity keys are structural: (correspondence_id, source_column) names the
/// top-level segment, source_path the L/R recursion path of the deciding leaf.
/// No geometry-local sorting anywhere in the trace.
#[derive(Clone, Debug)]
pub struct SpanEmission {
    pub master_index: usize,
    pub span_index_in_ring: usize,
    pub kind: SpanKind,
    pub source_column: usize,
    pub source_path: String,
}

/// Per-master record of one shared split: the ACTUAL selected raw sample
/// (the sample nearest the target half arc length in THIS master's extracted
/// segment). The measured fraction is recorded; it is never asserted to
/// equal 0.5.
#[derive(Clone, Debug)]
pub struct SplitRecord {
    pub master_index: usize,
    /// index into this master's extracted segment point list (s[i]); it is
    /// RECURSIVE-SEGMENT-LOCAL, not a raw ring index
    pub selected_sample_offset: usize,
    /// absolute index into this master's captured ring raw points
    /// (integer offset walk down the recursion, mod ring length; no
    /// fraction math and no nearest-geometry lookup)
    pub selected_raw_index: usize,
    pub cum_at_split: f64,
    pub total_arc: f64,
    pub actual_fraction: f64,
    pub split_point_scaled: (f64, f64),
}

/// One node of the shared-split decision tree of one top-level segment.
#[derive(Clone, Debug)]
pub enum DecisionNode {
    /// Straight in every master => one Line per master.
    AllStraight,
    /// Cubic fit succeeded in every master => one Cubic per master.
    AllCubic,
    /// Shared split: same target half arc length in every master (nearest
    /// interior sample selected per master), then left/right recursion
    /// (left evaluated first, as coded).
    Split {
        depth: usize,
        /// L/R path from the column root ("" at the root decision).
        path: String,
        splits: Vec<SplitRecord>,
        left: Box<DecisionNode>,
        right: Box<DecisionNode>,
    },
}

/// Trace of one landmark interval column (the top-level segment between two
/// homologous landmark columns).
#[derive(Clone, Debug)]
pub struct ColumnTrace {
    pub column: usize,
    pub role_start: LandmarkRole,
    pub role_end: LandmarkRole,
    /// per master: (master_index, raw index of this column's landmark, raw
    /// index of the next column's landmark) - the actual raw sample positions
    /// bounding the extracted segment; the wrapped root interval is kept
    /// as supplied (e.g. (270, 0)), never unwrapped or re-sorted
    pub raw_interval: Vec<(usize, usize, usize)>,
    pub decision: DecisionNode,
    pub emitted: Vec<SpanEmission>,
}

/// Trace of one supplied ring correspondence.
#[derive(Clone, Debug)]
pub struct RingTrace {
    pub correspondence_id: String,
    /// explicit supplied ring map: (master_index, ring_index), input order
    pub ring_map: Vec<(usize, usize)>,
    /// explicit supplied start map: (master_index, start raw_point_index)
    pub start_map: Vec<(usize, usize)>,
    pub columns: Vec<ColumnTrace>,
}

/// Measurement-only trace of a `fit_master_set` run. Side channel only: it is
/// NOT folded into the receipt string or `hash_rings`.
#[derive(Clone, Debug)]
pub struct MasterFitTrace {
    pub glyph_id: String,
    pub master_ids: Vec<String>,
    pub squared_error: f64,
    pub max_refits: usize,
    pub tangent_lookahead_fraction: f64,
    pub max_split_depth: usize,
    /// DECLARED split target constant (0.5); the measured per-master
    /// fractions live in SplitRecord::actual_fraction.
    pub split_fraction: f64,
    pub rings: Vec<RingTrace>,
}

/// Recursion depth bound of the shared split. A search bound, not a quality threshold; exceeding it refuses.
pub const MAX_SPLIT_DEPTH: usize = 8;
/// End-tangent estimator: direction to the sample this fraction of the segment away (min 1 sample).
pub const TANGENT_LOOKAHEAD_FRACTION: f64 = 0.1;

fn sub(a: Point, b: Point) -> Point { Point { x: a.x - b.x, y: a.y - b.y } }
fn unit(a: Point) -> Option<Point> { let n = a.x.hypot(a.y); if n.is_finite() && n > 0.0 { Some(Point { x: a.x / n, y: a.y / n }) } else { None } }
fn fin(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }

fn area_sign(raw: &[Point]) -> f64 {
    let n = raw.len(); let mut a = 0.0;
    for i in 0..n { let (p, q) = (raw[i], raw[(i + 1) % n]); a += p.x * q.y - q.x * p.y; }
    a
}

fn validate_inputs(set: &MasterSet, policy: &FitPolicy) -> Result<(), E> {
    if set.inputs.len() < 2 { return Err(E::UnsupportedConstraint("need at least 2 masters".into())); }
    if !policy.squared_error.is_finite() || policy.squared_error < 0.0 { return Err(E::NonFinite("policy.squared_error".into())); }
    for (i, m) in set.inputs.iter().enumerate() {
        if set.inputs[..i].iter().any(|p| p.master_id == m.master_id) { return Err(E::DuplicateMaster(m.master_id.clone())); }
        if !(m.scale.is_finite() && m.scale > 0.0) { return Err(E::NonFinite(format!("{} scale", m.master_id))); }
        if m.axes.is_empty() { return Err(E::BadAxes(format!("{} has no axes", m.master_id))); }
        for (j, a) in m.axes.iter().enumerate() {
            if !a.tag.iter().all(|b| (0x20..=0x7e).contains(b)) || a.tag == *b"    " { return Err(E::BadAxes(format!("{} axis tag must be 4 printable ASCII bytes", m.master_id))); }
            if !a.value.is_finite() { return Err(E::NonFinite(format!("{} axis value", m.master_id))); }
            if m.axes[..j].iter().any(|b| b.tag == a.tag) { return Err(E::BadAxes(format!("{} duplicate axis tag", m.master_id))); }
        }
        let tags0: Vec<[u8; 4]> = { let mut t: Vec<_> = set.inputs[0].axes.iter().map(|a| a.tag).collect(); t.sort(); t };
        let mut t: Vec<_> = m.axes.iter().map(|a| a.tag).collect(); t.sort();
        if t != tags0 { return Err(E::BadAxes(format!("{} axis tags differ from {}", m.master_id, set.inputs[0].master_id))); }
        if m.glyph_id != set.inputs[0].glyph_id { return Err(E::IncompatibleTopology(format!("glyph_id differs: {}", m.master_id))); }
        if m.master_id.trim().is_empty() { return Err(E::UnsupportedConstraint("empty master_id".into())); }
        if m.glyph_id.trim().is_empty() { return Err(E::UnsupportedConstraint(format!("{} empty glyph_id", m.master_id))); }
        if m.source_pin.len() != 64 || !m.source_pin.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) {
            return Err(E::UnsupportedConstraint(format!("{} source_pin must be a full lowercase hex SHA-256 (64 chars)", m.master_id)));
        }
        for r in &m.captured.rings { if !r.raw.iter().all(|p| fin(*p)) { return Err(E::NonFinite(format!("{} raw point", m.master_id))); } }
        if set.inputs[..i].iter().any(|p| axes_equal(&p.axes, &m.axes)) { return Err(E::BadAxes(format!("{} has the same location as another master", m.master_id))); }
    }
    let n0 = set.inputs[0].captured.rings.len();
    if let Some(m) = set.inputs.iter().find(|m| m.captured.rings.len() != n0) {
        return Err(E::IncompatibleTopology(format!("ring count {} vs {} ({})", m.captured.rings.len(), n0, m.master_id)));
    }
    Ok(())
}
fn axes_equal(a: &[AxisCoordinate], b: &[AxisCoordinate]) -> bool {
    a.iter().all(|x| b.iter().any(|y| y.tag == x.tag && y.value == x.value))
}

/// One validated ring correspondence: per master, the ring index and the landmark raw indices and roles.
struct RingPlan { ring: Vec<usize>, idx: Vec<Vec<usize>>, roles: Vec<LandmarkRole> }

fn plan_ring(set: &MasterSet, c: &ContourCorrespondence) -> Result<RingPlan, E> {
    let id = &c.correspondence_id;
    if c.landmarks.len() < 2 { return Err(E::UnsupportedConstraint(format!("{} needs >=2 landmarks", id))); }
    let nm = set.inputs.len();
    let mut ring: Vec<Option<usize>> = vec![None; nm];
    let mut idx: Vec<Vec<usize>> = vec![Vec::new(); nm];
    let mut roles = Vec::new();
    for (col, refs) in c.landmarks.iter().enumerate() {
        if refs.len() != nm { return Err(E::InvalidLandmark(format!("{} column {} has {} refs for {} masters", id, col, refs.len(), nm))); }
        for (mi, m) in set.inputs.iter().enumerate() {
            let mut it = refs.iter().filter(|r| r.master_id == m.master_id);
            let (Some(r), None) = (it.next(), it.next()) else {
                return Err(E::InvalidLandmark(format!("{} column {} needs exactly one ref for {}", id, col, m.master_id)));
            };
            match ring[mi] { None => ring[mi] = Some(r.ring_index), Some(x) if x != r.ring_index =>
                return Err(E::InvalidLandmark(format!("{} mixes rings for {}", id, m.master_id))), _ => {} }
            idx[mi].push(r.raw_point_index);
        }
        let role = refs[0].role;
        if refs.iter().any(|r| r.role != role) { return Err(E::InvalidLandmark(format!("{} column {} roles differ across masters", id, col))); }
        roles.push(role);
    }
    let ring: Vec<usize> = ring.into_iter().map(|r| r.unwrap()).collect();
    for (mi, m) in set.inputs.iter().enumerate() {
        let Some(cr) = m.captured.rings.get(ring[mi]) else { return Err(E::InvalidLandmark(format!("{} ring {} missing in {}", id, ring[mi], m.master_id))); };
        let n = cr.raw.len();
        if n < 3 { return Err(E::UnsupportedConstraint(format!("{} raw ring too short in {}", id, m.master_id))); }
        if cr.hole != c.hole { return Err(E::IncompatibleTopology(format!("{} hole flag mismatch in {}", id, m.master_id))); }
        let a = area_sign(&cr.raw);
        let o = if a > 0.0 { Orientation::Ccw } else { Orientation::Cw };
        if a == 0.0 || o != c.orientation { return Err(E::IncompatibleTopology(format!("{} orientation mismatch in {}", id, m.master_id))); }
        let v = &idx[mi];
        if v.iter().any(|&i| i >= n) { return Err(E::InvalidLandmark(format!("{} raw index out of range in {}", id, m.master_id))); }
        // cyclic strictly increasing offsets from the first landmark
        let off: Vec<usize> = v.iter().map(|&i| (i + n - v[0]) % n).collect();
        if off[0] != 0 || off.windows(2).any(|w| w[1] <= w[0]) {
            return Err(E::InvalidLandmark(format!("{} landmarks not strictly ordered along the ring in {}", id, m.master_id)));
        }
        // role position consistency: extremum roles must be extremal in the window between neighbours
        for (col, role) in roles.iter().enumerate() {
            let k = v.len();
            let (prev, next) = (v[(col + k - 1) % k], v[(col + 1) % k]);
            let win: Vec<Point> = { let mut w = Vec::new(); let mut i = prev; loop { w.push(cr.raw[i]); if i == next { break; } i = (i + 1) % n; } w };
            let p = cr.raw[v[col]];
            let ok = match role {
                LandmarkRole::XMin => win.iter().all(|q| p.x <= q.x),
                LandmarkRole::XMax => win.iter().all(|q| p.x >= q.x),
                LandmarkRole::YMin => win.iter().all(|q| p.y <= q.y),
                LandmarkRole::YMax => win.iter().all(|q| p.y >= q.y),
                _ => true,
            };
            if !ok { return Err(E::InvalidLandmark(format!("{} column {} role {:?} not at an extremum in {}", id, col, role, m.master_id))); }
        }
    }
    Ok(RingPlan { ring, idx, roles })
}

fn segment(raw: &[Point], a: usize, b: usize, scale: f64) -> Vec<Point> {
    let n = raw.len(); let mut v = Vec::new(); let mut i = a;
    loop { v.push(Point { x: raw[i].x * scale, y: raw[i].y * scale }); if i == b { break; } i = (i + 1) % n; }
    v
}
fn straight(pts: &[Point], sq: f64) -> bool {
    let (a, b) = (pts[0], *pts.last().unwrap());
    let d = sub(b, a); let l = d.x.hypot(d.y);
    if l == 0.0 { return false; }
    pts.iter().all(|p| { let c = ((p.x - a.x) * d.y - (p.y - a.y) * d.x) / l; c * c <= sq })
}
fn lookahead(len: usize) -> usize { (((len - 1) as f64) * TANGENT_LOOKAHEAD_FRACTION).ceil().max(1.0) as usize }
/// Typed role constraint: X extremum => vertical tangent, Y extremum => horizontal tangent. Sign comes from
/// the direction of travel into the segment. Unavailable (zero component) => None => caller REFUSES.
fn axis_tangent(role: LandmarkRole, toward: Point) -> Option<Point> {
    match role {
        LandmarkRole::XMin | LandmarkRole::XMax => if toward.y != 0.0 { Some(Point { x: 0.0, y: toward.y.signum() }) } else { None },
        LandmarkRole::YMin | LandmarkRole::YMax => if toward.x != 0.0 { Some(Point { x: toward.x.signum(), y: 0.0 }) } else { None },
        _ => None,
    }
}
fn constrained(role: LandmarkRole) -> bool {
    matches!(role, LandmarkRole::XMin | LandmarkRole::XMax | LandmarkRole::YMin | LandmarkRole::YMax)
}
#[derive(Clone, Copy)]
enum Tan { Role(LandmarkRole), Dir(Point) }
/// Err = a role constraint cannot be satisfied (refuse); Ok(None) = estimator failure (degenerate points).
fn end_tangents(pts: &[Point], l: Tan, r: Tan) -> Result<Option<(Point, Point)>, String> {
    let k = lookahead(pts.len()); let n = pts.len();
    let (el, er) = (unit(sub(pts[k], pts[0])), unit(sub(pts[n - 1 - k], pts[n - 1])));
    let pick = |t: Tan, toward: Point, est: Option<Point>, which: &str| -> Result<Option<Point>, String> {
        match t {
            Tan::Dir(d) => Ok(Some(d)),
            Tan::Role(role) if constrained(role) => axis_tangent(role, toward).map(Some)
                .ok_or_else(|| format!("{:?} tangent unavailable at {} end (no travel component along the constraint axis)", role, which)),
            Tan::Role(_) => Ok(est),
        }
    };
    let a = pick(l, sub(pts[k], pts[0]), el, "start")?; let b = pick(r, sub(pts[n - 1 - k], pts[n - 1]), er, "end")?;
    Ok(a.zip(b))
}
/// A line leaving/entering an extremum landmark must itself follow the constrained axis.
fn line_respects_roles(pts: &[Point], l: Tan, r: Tan, sq: f64) -> bool {
    let d = sub(*pts.last().unwrap(), pts[0]); let tol = sq.sqrt();
    let ok = |t: Tan| match t {
        Tan::Role(LandmarkRole::XMin) | Tan::Role(LandmarkRole::XMax) => d.x.abs() <= tol,
        Tan::Role(LandmarkRole::YMin) | Tan::Role(LandmarkRole::YMax) => d.y.abs() <= tol,
        _ => true,
    };
    ok(l) && ok(r)
}

/// Shared group decision implementation. Trace collection is OPTIONAL: when
/// the recorders (`node_rec`, `span_rec`) and the raw-base bookkeeping
/// (`base`/`ring_lens`) are None - the `fit_master_set` path - no trace tree,
/// span-path or base bookkeeping is allocated. The fitting decisions are made
/// by the same code in both modes.
///
/// `base`: per master, the absolute raw ring index of segs[mi][0]; combined
/// with the recursive-segment-local split offset it yields the absolute raw
/// index of a split sample without any nearest-geometry lookup.
fn fit_group_impl(segs: &[Vec<Point>], base: Option<Vec<usize>>, ring_lens: Option<&[usize]>,
                  l: &[Tan], r: &[Tan], policy: &FitPolicy, depth: usize, what: &str, path: &str,
                  node_rec: Option<&mut Option<DecisionNode>>, span_rec: Option<&mut Vec<Vec<String>>>)
    -> Result<Vec<Vec<Span>>, E> {
    if segs.iter().any(|s| s.len() < 2) { return Err(E::UnsupportedConstraint(format!("{} segment too short", what))); }
    let end = |s: &Vec<Point>| Span::Line { end: *s.last().unwrap() };
    if segs.iter().enumerate().all(|(i, s)| (s.len() < 3 || straight(s, policy.squared_error)) && line_respects_roles(s, l[i], r[i], policy.squared_error)) {
        if let Some(slot) = node_rec { *slot = Some(DecisionNode::AllStraight); }
        if let Some(sp) = span_rec { for paths in sp.iter_mut() { paths.push(path.to_string()); } }
        return Ok(segs.iter().map(|s| vec![end(s)]).collect());
    }
    let mut fitted = Vec::new();
    let mut all = true;
    for (i, s) in segs.iter().enumerate() {
        if s.len() < 3 { all = false; break; }
        let t = end_tangents(s, l[i], r[i]).map_err(|m| E::UnsupportedConstraint(format!("{}: {}", what, m)))?;
        let sp = t.and_then(|(a, b)| match fit_run(s, a, b, policy) {
            FitOutcome::Fitted { controls, .. } => Some(Span::Cubic { control_one: controls[1], control_two: controls[2], end: controls[3] }),
            _ => None });
        match sp { Some(sp) => fitted.push(vec![sp]), None => { all = false; break; } }
    }
    if all {
        if let Some(slot) = node_rec { *slot = Some(DecisionNode::AllCubic); }
        if let Some(sp) = span_rec { for paths in sp.iter_mut() { paths.push(path.to_string()); } }
        return Ok(fitted);
    }
    if depth >= MAX_SPLIT_DEPTH { return Err(E::UnsupportedConstraint(format!("{} not fittable within shared split depth", what))); }
    // shared split: same target half arc length in every master; the nearest
    // available interior sample is selected separately in each master, so the
    // actual fractions may differ
    let mut left_s = Vec::new(); let mut right_s = Vec::new(); let mut tl = Vec::new(); let mut tr = Vec::new();
    let mut splits = Vec::new();
    let mut chosen: Vec<usize> = Vec::new();
    for (mi, s) in segs.iter().enumerate() {
        let mut cum = vec![0.0]; for i in 1..s.len() { let d = sub(s[i], s[i - 1]); cum.push(cum[i - 1] + d.x.hypot(d.y)); }
        let half = cum.last().unwrap() / 2.0;
        let i = (1..s.len() - 1).min_by(|&a, &b| (cum[a] - half).abs().partial_cmp(&(cum[b] - half).abs()).unwrap());
        let Some(i) = i else { return Err(E::UnsupportedConstraint(format!("{} cannot be split", what))); };
        let Some(d) = unit(sub(s[i + 1], s[i - 1])) else { return Err(E::UnsupportedConstraint(format!("{} degenerate split tangent", what))); };
        if let (Some(b), Some(lens)) = (&base, ring_lens) {
            chosen.push(i);
            splits.push(SplitRecord { master_index: mi, selected_sample_offset: i,
                selected_raw_index: (b[mi] + i) % lens[mi],
                cum_at_split: cum[i], total_arc: *cum.last().unwrap(),
                actual_fraction: cum[i] / *cum.last().unwrap(),
                split_point_scaled: (s[i].x, s[i].y) });
        }
        left_s.push(s[..=i].to_vec()); right_s.push(s[i..].to_vec());
        tl.push(Tan::Dir(Point { x: -d.x, y: -d.y })); tr.push(Tan::Dir(d));
    }
    let lt: Vec<Tan> = l.to_vec(); let rt: Vec<Tan> = r.to_vec();
    let (left_base, right_base) = match (&base, ring_lens) {
        (Some(b), Some(lens)) =>
            (Some(b.clone()), Some(b.iter().zip(lens).zip(&chosen).map(|((b0, ln), i)| (b0 + i) % ln).collect::<Vec<_>>())),
        _ => (None, None),
    };
    let mut ln: Option<DecisionNode> = None;
    let mut rn: Option<DecisionNode> = None;
    let mut left_paths: Vec<Vec<String>> = Vec::new();
    let mut right_paths: Vec<Vec<String>> = Vec::new();
    let record_nodes = node_rec.is_some();
    let record_spans = span_rec.is_some();
    // L/R path strings are built only when a sink is attached; the untraced
    // recursion passes the incoming path through without allocating.
    let owned_paths = if record_nodes || record_spans {
        Some((format!("{}L", path), format!("{}R", path)))
    } else { None };
    let (lpath, rpath) = match &owned_paths { Some((l, r)) => (l.as_str(), r.as_str()), None => (path, path) };
    let a = fit_group_impl(&left_s, left_base, ring_lens, &lt, &tl, policy, depth + 1, what, lpath,
        if record_nodes { Some(&mut ln) } else { None },
        if record_spans { left_paths = (0..segs.len()).map(|_| Vec::new()).collect(); Some(&mut left_paths) } else { None })?;
    let b = fit_group_impl(&right_s, right_base, ring_lens, &tr, &rt, policy, depth + 1, what, rpath,
        if record_nodes { Some(&mut rn) } else { None },
        if record_spans { right_paths = (0..segs.len()).map(|_| Vec::new()).collect(); Some(&mut right_paths) } else { None })?;
    if let Some(slot) = node_rec {
        *slot = Some(DecisionNode::Split { depth, path: path.to_string(), splits,
            left: Box::new(ln.expect("recorder invariant: every Ok branch sets its node")),
            right: Box::new(rn.expect("recorder invariant: every Ok branch sets its node")) });
    }
    if let Some(sp) = span_rec {
        for (dst, (lp, rp)) in sp.iter_mut().zip(left_paths.into_iter().zip(right_paths.into_iter())) {
            dst.extend(lp); dst.extend(rp);
        }
    }
    Ok(a.into_iter().zip(b).map(|(mut x, y)| { x.extend(y); x }).collect())
}

fn kinds(r: &ReferenceRing) -> Vec<bool> { r.spans.iter().map(|s| matches!(s, Span::Cubic { .. })).collect() }

pub fn fit_master_set(set: &MasterSet, policy: &FitPolicy) -> Result<MasterFitResult, MasterFitError> {
    fit_master_set_impl(set, policy, false).map(|(result, _)| result)
}

/// Traced variant of `fit_master_set`: same computation through the shared
/// implementation with trace collection enabled. The receipt is constructed
/// identically; the trace is a side channel and is not folded into the
/// receipt or `hash_rings`.
pub fn fit_master_set_traced(set: &MasterSet, policy: &FitPolicy) -> Result<(MasterFitResult, MasterFitTrace), MasterFitError> {
    let (result, trace) = fit_master_set_impl(set, policy, true)?;
    Ok((result, trace.expect("a traced run always produces a trace")))
}

/// Shared implementation. `want_trace == false` (the `fit_master_set` path)
/// allocates no trace tree, no span-path vectors and no raw-base bookkeeping.
fn fit_master_set_impl(set: &MasterSet, policy: &FitPolicy, want_trace: bool) -> Result<(MasterFitResult, Option<MasterFitTrace>), MasterFitError> {
    validate_inputs(set, policy)?;
    let nm = set.inputs.len();
    let nrings = set.inputs[0].captured.rings.len();
    if set.correspondence.is_empty() { return Err(E::MissingCorrespondence("no correspondences".into())); }
    // every captured ring of every master covered exactly once
    let mut plans = Vec::new();
    for (ci, c) in set.correspondence.iter().enumerate() {
        if set.correspondence[..ci].iter().any(|p| p.correspondence_id == c.correspondence_id) {
            return Err(E::InvalidLandmark(format!("duplicate correspondence id {}", c.correspondence_id)));
        }
        plans.push(plan_ring(set, c)?);
    }
    for mi in 0..nm {
        for ri in 0..nrings {
            let n = plans.iter().filter(|p| p.ring[mi] == ri).count();
            if n == 0 { return Err(E::MissingCorrespondence(format!("ring {} of {} has no correspondence", ri, set.inputs[mi].master_id))); }
            if n > 1 { return Err(E::InvalidLandmark(format!("ring {} of {} in several correspondences", ri, set.inputs[mi].master_id))); }
        }
    }
    let mut out: Vec<Vec<ReferenceRing>> = vec![Vec::new(); nm];
    let mut trace_rings: Vec<RingTrace> = Vec::new();
    for (c, plan) in set.correspondence.iter().zip(&plans) {
        let k = plan.roles.len();
        let mut spans: Vec<Vec<Span>> = vec![Vec::new(); nm];
        let mut columns: Vec<ColumnTrace> = Vec::new();
        for col in 0..k {
            let nxt = (col + 1) % k;
            let segs: Vec<Vec<Point>> = (0..nm).map(|mi| {
                let m = &set.inputs[mi];
                segment(&m.captured.rings[plan.ring[mi]].raw, plan.idx[mi][col], plan.idx[mi][nxt], m.scale)
            }).collect();
            let lt = vec![Tan::Role(plan.roles[col]); nm]; let rt = vec![Tan::Role(plan.roles[nxt]); nm];
            let what = format!("{} segment {}", c.correspondence_id, col);
            let mut node: Option<DecisionNode> = None;
            let mut span_paths: Vec<Vec<String>> = if want_trace { (0..nm).map(|_| Vec::new()).collect() } else { Vec::new() };
            let base: Option<Vec<usize>> = if want_trace { Some((0..nm).map(|mi| plan.idx[mi][col]).collect()) } else { None };
            let lens: Option<Vec<usize>> = if want_trace { Some((0..nm).map(|mi| set.inputs[mi].captured.rings[plan.ring[mi]].raw.len()).collect()) } else { None };
            let g = fit_group_impl(&segs, base, lens.as_deref(), &lt, &rt, policy, 0, &what, "",
                if want_trace { Some(&mut node) } else { None },
                if want_trace { Some(&mut span_paths) } else { None })?;
            if want_trace {
                let mut emitted = Vec::new();
                for (mi, s) in g.iter().enumerate() {
                    let span_base = spans[mi].len();
                    for (j, sp) in s.iter().enumerate() {
                        emitted.push(SpanEmission {
                            master_index: mi,
                            span_index_in_ring: span_base + j,
                            kind: match sp { Span::Line { .. } => SpanKind::Line, Span::Cubic { .. } => SpanKind::Cubic },
                            source_column: col,
                            source_path: span_paths[mi][j].clone(),
                        });
                    }
                }
                columns.push(ColumnTrace {
                    column: col,
                    role_start: plan.roles[col],
                    role_end: plan.roles[nxt],
                    raw_interval: (0..nm).map(|mi| (mi, plan.idx[mi][col], plan.idx[mi][nxt])).collect(),
                    decision: node.expect("recorder invariant: every Ok branch sets its node"),
                    emitted,
                });
            }
            for (mi, s) in g.into_iter().enumerate() { spans[mi].extend(s); }
        }
        for mi in 0..nm {
            let m = &set.inputs[mi];
            let raw = &m.captured.rings[plan.ring[mi]].raw;
            let p = raw[plan.idx[mi][0]];
            out[mi].push(ReferenceRing { start: Point { x: p.x * m.scale, y: p.y * m.scale }, spans: std::mem::take(&mut spans[mi]) });
        }
        if want_trace {
            trace_rings.push(RingTrace {
                correspondence_id: c.correspondence_id.clone(),
                ring_map: (0..nm).map(|mi| (mi, plan.ring[mi])).collect(),
                start_map: (0..nm).map(|mi| (mi, plan.idx[mi][0])).collect(),
                columns,
            });
        }
    }
    // independent re-verification: identical ring count, span-kind sequence, node count, closure
    for mi in 1..nm {
        if out[mi].len() != out[0].len() { return Err(E::IncompatibleTopology("ring count after fit".into())); }
        for (ri, (a, b)) in out[0].iter().zip(&out[mi]).enumerate() {
            if kinds(a) != kinds(b) { return Err(E::IncompatibleTopology(format!("span-kind sequence differs, ring {}", ri))); }
        }
    }
    for rings in &out { for r in rings {
        let last = match r.spans.last() { Some(Span::Line { end }) | Some(Span::Cubic { end, .. }) => *end, None => return Err(E::IncompatibleTopology("empty ring".into())) };
        if last != r.start { return Err(E::IncompatibleTopology("ring not closed".into())); }
    } }
    let glyph_id = set.inputs[0].glyph_id.clone();
    let mut receipt = format!("kni.master-fit.v1 tangent_lookahead_fraction={} max_split_depth={} squared_error={} max_refits={} glyph={} masters={} rings={} nodes_per_ring={:?}", TANGENT_LOOKAHEAD_FRACTION, MAX_SPLIT_DEPTH, policy.squared_error, policy.max_refits, glyph_id, nm, out[0].len(),
        out[0].iter().map(|r| r.spans.len()).collect::<Vec<_>>());
    let masters: Vec<MasterOutput> = set.inputs.iter().zip(out).map(|(m, rings)| {
        receipt.push_str(&format!(" {}:{:016x}:origin=({},{}):scale={}", m.master_id, hash_rings(&rings), m.captured.origin_x, m.captured.origin_y, m.scale));
        MasterOutput { master_id: m.master_id.clone(), axes: m.axes.clone(),
            outline: DrawnGlyph { glyph_id: glyph_id.clone(), rings }, source_pin: m.source_pin.clone() }
    }).collect();
    let result = MasterFitResult { glyph_id, masters, compatible_topology: true, receipt };
    let trace = if want_trace {
        Some(MasterFitTrace {
            glyph_id: result.glyph_id.clone(),
            master_ids: set.inputs.iter().map(|m| m.master_id.clone()).collect(),
            squared_error: policy.squared_error,
            max_refits: policy.max_refits as usize,
            tangent_lookahead_fraction: TANGENT_LOOKAHEAD_FRACTION,
            max_split_depth: MAX_SPLIT_DEPTH,
            split_fraction: 0.5,
            rings: trace_rings,
        })
    } else { None };
    Ok((result, trace))
}
