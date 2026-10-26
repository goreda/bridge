//! Corner-split gated cubic fitting over captured contour rings.
//!
//! Approach-level basis: FontLab 8.3.0 autotrace pipeline as reconstructed in
//! the byte-verified research under engine/fl-re/ (corner preservation at
//! detected corner nodes; least-squares cubic fitting between special points;
//! no proprietary FontLab code is present here - all Rust below is original).
//!
//! Stages: split ring into arcs at corner indices, merge sub-sample arcs,
//! fit each arc with cubic_fit::fit_run under a caller-side plausibility gate
//! (controls must stay within the arc sample bbox expanded by a small margin;
//! ungated fit_run can emit pathological overshoot solutions on real contour
//! data - see engine/core/tests/fit_run_plausibility_repro.rs), split at the
//! midpoint on rejection, degrade honestly to polyline beyond recursion depth.
//! Final points are rounded to integers for the current integer-only container
//! (declared adaptation; 16.16 fixed-point output is decided but unimplemented).
//!
//! Design principles:
//! - Grid-explainable detail is STRUCTURE, never noise. Tolerances in this
//!   module (plausibility margin, split policy, polyline fallback) exist to
//!   keep pathological solutions out, not to smooth real detail: the 1-unit
//!   terminal staircase, cut-terminal angles and corner pairs must survive
//!   fitting exactly.
//! - Corner detection produces a DETAIL MAP: where structure exists (cut
//!   terminals, corners, staircases) point density rises; in smooth flow
//!   (bowl curves) span economy is preserved and the fitter must not
//!   scatter points. Control-point economy is a quality constraint, not a
//!   convenience.
//! - Terminal handling is per-terminal data-driven, never a global policy:
//!   a flat-cut terminal is two points and a line span; a staircase
//!   terminal keeps its steps. The fitter assumes no terminal type; the
//!   detail map decides.

use crate::capture::CapturedRing;
use crate::cubic_fit::{fit_run, FitOutcome, FitPolicy, RefitStop};
use crate::reference_slice::{Point, ReferenceRing, Span};

// Vertex relocation, following the potrace stage-3 mechanism. Measured on
// the tile set, disabling the equivalent step in potrace lowers mean IoU by
// 0.00472, with 457 of 478 tiles worse.
// For each corner vertex, fit a total-least-squares line to each adjacent
// polygon edge run, turn each edge into a quadratic form, then move the
// vertex to the point inside its 1px unit square minimizing the summed
// squared distance to both edge lines. The 1px square is capture geometry
// (the pixel itself), not a tuned threshold; nothing here is font-specific.
// Count of moved vertices is exposed for test/delivery receipts.
thread_local! {
    static RELOC_MOVED: std::cell::Cell<usize> = std::cell::Cell::new(0);
    static SPECK_AREAS: std::cell::RefCell<Vec<f64>> = std::cell::RefCell::new(Vec::new());
    static SPECK_SPANS: std::cell::Cell<usize> = std::cell::Cell::new(0);
    static SPECK_RETAINED_HOLE: std::cell::Cell<usize> = std::cell::Cell::new(0);
    static SPECK_DROPPED_COLLAPSE: std::cell::Cell<usize> = std::cell::Cell::new(0);
}

/// Total-least-squares line over pts[i0..=j0]: returns (centroid, unit dir).
fn tls_line(pts: &[Point], i0: usize, j0: usize) -> (Point, Point) {
    let n = (j0 - i0 + 1) as f64;
    let (mut x, mut y, mut x2, mut xy, mut y2) = (0.0, 0.0, 0.0, 0.0, 0.0);
    for p in &pts[i0..=j0] {
        x += p.x;
        y += p.y;
        x2 += p.x * p.x;
        xy += p.x * p.y;
        y2 += p.y * p.y;
    }
    let ctr = Point { x: x / n, y: y / n };
    let a = (x2 - x * x / n) / n;
    let b = (xy - x * y / n) / n;
    let c = (y2 - y * y / n) / n;
    let l2 = (a + c + ((a - c) * (a - c) + 4.0 * b * b).sqrt()) / 2.0;
    let (a2, c2) = (a - l2, c - l2);
    let mut dir = Point { x: 0.0, y: 0.0 };
    if a2.abs() >= c2.abs() {
        let l = (a2 * a2 + b * b).sqrt();
        if l != 0.0 {
            dir = Point { x: -b / l, y: a2 / l };
        }
    } else {
        let l = (c2 * c2 + b * b).sqrt();
        if l != 0.0 {
            dir = Point { x: -c2 / l, y: b / l };
        }
    }
    (ctr, dir)
}

type Quad = [[f64; 3]; 3];

fn quad_eval(q: &Quad, x: f64, y: f64) -> f64 {
    q[0][0] * x * x + 2.0 * q[0][1] * x * y + 2.0 * q[0][2] * x + q[1][1] * y * y
        + 2.0 * q[1][2] * y
        + q[2][2]
}

/// Relocate corner vertices of a pixel-space ring. corners indexes pts.
/// Returns the number of vertices moved (beyond f64 noise).
pub fn relocate_corners(pts: &mut [Point], corners: &[usize]) -> usize {
    let n = pts.len();
    let m = corners.len();
    if n < 3 || m == 0 {
        return 0;
    }
    // per-edge quadratic forms from TLS lines over each edge run
    let mut qf: Vec<Quad> = Vec::with_capacity(m);
    for k in 0..m {
        let i0 = corners[k];
        let j0 = corners[(k + 1) % m];
        // edge runs forward from corner k to corner k+1 (cyclic); need >=2 pts
        if j0 <= i0 {
            qf.push([[0.0; 3]; 3]);
            continue;
        }
        let (ctr, dir) = tls_line(pts, i0, j0);
        let d = dir.x * dir.x + dir.y * dir.y;
        let mut q = [[0.0; 3]; 3];
        if d != 0.0 {
            let v = [dir.y, -dir.x, dir.x * ctr.y - dir.y * ctr.x];
            for l in 0..3 {
                for k2 in 0..3 {
                    q[l][k2] = v[l] * v[k2] / d;
                }
            }
        }
        qf.push(q);
    }
    let mut moved = 0usize;
    for k in 0..m {
        let ci = corners[k];
        if ci >= n {
            continue;
        }
        let s = pts[ci];
        // edges meeting at this corner: edge k-1 (incoming) and edge k (outgoing)
        let prev = if k == 0 { m - 1 } else { k - 1 };
        let mut q = [[0.0; 3]; 3];
        for l in 0..3 {
            for k2 in 0..3 {
                q[l][k2] = qf[prev][l][k2] + qf[k][l][k2];
            }
        }
        // minimize q on the unit square around s; singular -> add orthogonal axis
        let w: Point;
        loop {
            let det = q[0][0] * q[1][1] - q[0][1] * q[1][0];
            if det != 0.0 {
                w = Point {
                    x: (-q[0][2] * q[1][1] + q[1][2] * q[0][1]) / det,
                    y: (q[0][2] * q[1][0] - q[1][2] * q[0][0]) / det,
                };
                break;
            }
            let v = if q[0][0] > q[1][1] {
                [-q[0][1], q[0][0]]
            } else if q[1][1] != 0.0 {
                [-q[1][1], q[1][0]]
            } else {
                [1.0, 0.0]
            };
            let d = v[0] * v[0] + v[1] * v[1];
            let v2 = -v[1] * s.y - v[0] * s.x;
            for l in 0..3 {
                for k2 in 0..3 {
                    let vv = [v[0], v[1], v2];
                    q[l][k2] += vv[l] * vv[k2] / d;
                }
            }
        }
        let mut xmin = s.x;
        let mut ymin = s.y;
        if (w.x - s.x).abs() <= 0.5 && (w.y - s.y).abs() <= 0.5 {
            xmin = w.x;
            ymin = w.y;
        } else {
            // boundary minimization: edges then corners
            let mut min = quad_eval(&q, s.x, s.y);
            if q[0][0] != 0.0 {
                for z in 0..2 {
                    let wy = s.y - 0.5 + z as f64;
                    let wx = -(q[0][1] * wy + q[0][2]) / q[0][0];
                    if (wx - s.x).abs() <= 0.5 {
                        let cand = quad_eval(&q, wx, wy);
                        if cand < min {
                            min = cand;
                            xmin = wx;
                            ymin = wy;
                        }
                    }
                }
            }
            if q[1][1] != 0.0 {
                for z in 0..2 {
                    let wx = s.x - 0.5 + z as f64;
                    let wy = -(q[1][0] * wx + q[1][2]) / q[1][1];
                    if (wy - s.y).abs() <= 0.5 {
                        let cand = quad_eval(&q, wx, wy);
                        if cand < min {
                            min = cand;
                            xmin = wx;
                            ymin = wy;
                        }
                    }
                }
            }
            for l in 0..2 {
                for k2 in 0..2 {
                    let wx = s.x - 0.5 + l as f64;
                    let wy = s.y - 0.5 + k2 as f64;
                    let cand = quad_eval(&q, wx, wy);
                    if cand < min {
                        min = cand;
                        xmin = wx;
                        ymin = wy;
                    }
                }
            }
        }
        if (xmin - s.x).abs() > 1e-12 || (ymin - s.y).abs() > 1e-12 {
            pts[ci] = Point { x: xmin, y: ymin };
            moved += 1;
        }
    }
    moved
}

/// Raw boundary points from `a` to `b` going forward (cyclic) along `raw`; both must be raw points.
fn raw_run(raw: &[Point], a: Point, b: Point) -> Option<Vec<Point>> {
    let n = raw.len();
    if n < 2 { return None; }
    let ia = raw.iter().position(|p| p.x == a.x && p.y == a.y)?;
    let mut seg = vec![raw[ia]];
    let mut i = ia;
    for _ in 0..n {
        i = (i + 1) % n;
        seg.push(raw[i]);
        if raw[i].x == b.x && raw[i].y == b.y { return Some(seg); }
    }
    None
}

/// Local straight-run line at a corner: from corner vertex `ci`, extend along the ring (forward or
/// backward, cyclic) up to the neighbouring corner `lim` while the raw boundary points of the run stay
/// within `eps` of the chord; TLS line over those raw points. The first step is always taken, so a
/// single edge always yields a line. None when the run cannot be located or is degenerate.
fn local_line(orig: &[Point], raw: &[Point], ci: usize, lim: usize, fwd: bool, eps: f64) -> Option<(Point, Point)> {
    let n = orig.len();
    let mut best: Option<Vec<Point>> = None;
    for s in 1..n {
        let nt = if fwd { (ci + s) % n } else { (ci + n - s) % n };
        let (a, b) = if fwd { (orig[ci], orig[nt]) } else { (orig[nt], orig[ci]) };
        let run = match raw_run(raw, a, b) { Some(r) => r, None => break };
        let mx = run.iter().map(|p| pt_seg_d2(*p, a, b)).fold(0.0f64, f64::max);
        if mx > eps * eps && best.is_some() { break; }
        best = Some(run);
        if nt == lim { break; }
    }
    let run = best?;
    if run.len() < 2 { return None; }
    let (ctr, dir) = tls_line(&run, 0, run.len() - 1);
    if dir.x == 0.0 && dir.y == 0.0 { return None; }
    Some((ctr, dir))
}

/// Intersection of two lines (centroid, unit dir); None when parallel.
fn line_isect(l1: (Point, Point), l2: (Point, Point)) -> Option<Point> {
    let det = l1.1.x * l2.1.y - l1.1.y * l2.1.x;
    if det == 0.0 { return None; }
    let t = ((l2.0.x - l1.0.x) * l2.1.y - (l2.0.y - l1.0.y) * l2.1.x) / det;
    Some(Point { x: l1.0.x + t * l1.1.x, y: l1.0.y + t * l1.1.y })
}

/// L1 corner targets: each corner moves to the intersection of the local straight-run lines of its two
/// edges, or stays (abstain) when the lines are parallel or the intersection is farther than `eps` (the capture tolerance) from the original vertex.
pub fn local_targets(pts: &mut [Point], corners: &[usize], raw: &[Point], eps: f64) {
    let m = corners.len();
    let n = pts.len();
    if m < 2 { return; }
    let orig: Vec<Point> = pts.to_vec();
    for k in 0..m {
        let ci = corners[k];
        if ci >= n { continue; }
        let prev = corners[if k == 0 { m - 1 } else { k - 1 }];
        let next = corners[(k + 1) % m];
        if next >= n || prev >= n || next == ci || prev == ci { continue; }
        let (Some(l_out), Some(l_in)) = (local_line(&orig, raw, ci, next, true, eps), local_line(&orig, raw, ci, prev, false, eps)) else { continue };
        let Some(w) = line_isect(l_in, l_out) else { continue };
        let d = ((w.x - orig[ci].x).powi(2) + (w.y - orig[ci].y).powi(2)).sqrt();
        if d <= eps { pts[ci] = w; }
    }
}

/// `local_targets` (intersection of the local straight-run lines of each corner's two edges, within `eps` of the vertex) verified against the RAW boundary. A moved corner is kept only if the two edge
/// chords it ends fit the raw boundary points of their edge runs at least as well as before the move
/// (summed squared distance of the raw points to the chord segments does not grow) and the largest raw
/// deviation stays within max(old, eps). A corner whose move fits the boundary worse - the TLS line over
/// the few polygon vertices of a short or curved run overshoots the contour - keeps its position, as does
/// a corner whose edge run cannot be located in the raw ring. `eps` is the capture simplification
/// tolerance (capture px). Each corner's move depends only on the original vertices, so restoring the
/// rejected ones leaves the accepted moves unchanged.
pub fn relocate_corners_verified(pts: &mut [Point], corners: &[usize], raw: &[Point], eps: f64) -> usize {
    let m = corners.len();
    let n = pts.len();
    if m == 0 || n < 3 { return 0; }
    let orig: Vec<Point> = pts.to_vec();
    local_targets(pts, corners, raw, eps);
    let moved_pts: Vec<Point> = pts.to_vec();
    // fit of edge run k (corner k -> corner k+1) with the corner positions given by `at`
    let fit = |k: usize, at: &[Point]| -> Option<(f64, f64)> {
        let (i0, j0) = (corners[k], corners[(k + 1) % m]);
        if i0 >= n || j0 >= n || i0 == j0 { return None; }
        let run = raw_run(raw, orig[i0], orig[j0])?;
        let (mut sum, mut mx) = (0.0f64, 0.0f64);
        for p in &run {
            let d = pt_seg_d2(*p, at[i0], at[j0]);
            sum += d;
            mx = mx.max(d);
        }
        Some((sum, mx))
    };
    let mut moved = 0;
    for k in 0..m {
        let ci = corners[k];
        if ci >= n { continue; }
        if moved_pts[ci].x == orig[ci].x && moved_pts[ci].y == orig[ci].y { continue; }
        let prev = if k == 0 { m - 1 } else { k - 1 };
        let ok = match (fit(prev, &orig), fit(k, &orig), fit(prev, &moved_pts), fit(k, &moved_pts)) {
            (Some(a0), Some(b0), Some(a1), Some(b1)) => {
                a1.0 + b1.0 <= a0.0 + b0.0 + 1e-9
                    && a1.1 <= a0.1
                    && b1.1 <= b0.1
            }
            _ => false,
        };
        if ok { moved += 1; } else { pts[ci] = orig[ci]; }
    }
    moved
}

fn rd(p: Point) -> Point {
    Point { x: p.x.round(), y: p.y.round() }
}

/// Plausibility gate: fitted Bezier controls must remain within the arc's
/// sample bounding box expanded by 15% of its largest dimension plus 2 units.
///
/// STATUS (peer writer review via bridge, adopted for this module): this margin is an UNCALIBRATED
/// local proposal. The control hull is a conservative bound, not the true
/// curve bbox, so valid curves can be rejected; adopting any threshold
/// requires benchmark evidence. Handles are NEVER clamped (clamping would
/// alter shape/tangent/residual without revalidation). Rejection here means
/// source-bound midpoint split and refit, with the polyline fallback as the
/// explicit last resort - never a silent handle edit.
pub fn plausible(samples: &[Point], q: &[Point; 4]) -> bool {
    let mut mnx = f64::INFINITY;
    let mut mny = f64::INFINITY;
    let mut mxx = f64::NEG_INFINITY;
    let mut mxy = f64::NEG_INFINITY;
    for p in samples {
        mnx = mnx.min(p.x);
        mny = mny.min(p.y);
        mxx = mxx.max(p.x);
        mxy = mxy.max(p.y);
    }
    let w = (mxx - mnx).max(1.0);
    let h = (mxy - mny).max(1.0);
    let m = 0.15 * w.max(h) + 2.0;
    q.iter().all(|p| p.x >= mnx - m && p.x <= mxx + m && p.y >= mny - m && p.y <= mxy + m)
}


/// Windowed chord tangent estimator (F1 patch): walk from each arc end
/// accumulating chord lengths until >= L_min = max(5% of arc length, 3 font
/// units), capped at half the arc, so 1-px staircase micro-chords and cut
/// notches do not set the end tangent direction (measured root cause of the
/// tail bulge: adjacent 1-unit chords gave tangents perpendicular to a
/// 218-unit diagonal edge). Degenerate zero-length first/last chord still
/// returns None -> caller's polyline fallback (contract preserved, see
/// tests/capture_fit_r.rs::fallback_flag_set_on_degenerate_ring).
/// Endpoint tangents for the gated fit: TLS
/// one-sided tangent - direction of the largest-eigenvalue eigenvector of
/// the window's 2x2 covariance (closed form, equals the SVD line fit of the
/// window) - over an arc-length window on ONE side of each endpoint. The
/// window rule is unchanged from the chord estimator (derived: 5% of total
/// arc length, clamped to [3, total/2] font units); only the estimator
/// changes: the chord aims at the window's far point and wobbles with it,
/// the TLS direction averages the whole window. Chord fallback when the
/// window has < 3 points or degenerate covariance.
fn tls_dir(win: &[Point]) -> Option<Point> {
    if win.len() < 3 {
        return None;
    }
    let (mut mx, mut my) = (0.0, 0.0);
    for p in win {
        mx += p.x;
        my += p.y;
    }
    mx /= win.len() as f64;
    my /= win.len() as f64;
    let (mut sxx, mut sxy, mut syy) = (0.0, 0.0, 0.0);
    for p in win {
        let dx = p.x - mx;
        let dy = p.y - my;
        sxx += dx * dx;
        sxy += dx * dy;
        syy += dy * dy;
    }
    if !(sxx + syy > 0.0) {
        return None;
    }
    let th = 0.5 * (2.0 * sxy).atan2(sxx - syy);
    let d = Point { x: th.cos(), y: th.sin() };
    if d.x.is_finite() && d.y.is_finite() { Some(d) } else { None }
}

fn windowed_chord_tangents(pts: &[Point]) -> Option<(Point, Point)> {
    let n = pts.len();
    if n < 2 {
        return None;
    }
    let chord = |i: usize| (pts[i + 1].x - pts[i].x).hypot(pts[i + 1].y - pts[i].y);
    if chord(0) == 0.0 || chord(n - 2) == 0.0 {
        return None;
    }
    let total: f64 = (0..n - 1).map(chord).sum();
    if total == 0.0 {
        return None;
    }
    let l_min = crate::thresholds::tangent_l_min(total);
    let mut acc = 0.0;
    let mut j = n - 1;
    for i in 0..n - 1 {
        acc += chord(i);
        if acc >= l_min {
            j = i + 1;
            break;
        }
    }
    let lt = {
        let d = Point { x: pts[j].x - pts[0].x, y: pts[j].y - pts[0].y };
        let l = d.x.hypot(d.y);
        if l == 0.0 || !l.is_finite() {
            return None;
        }
        let chord_dir = Point { x: d.x / l, y: d.y / l };
        match tls_dir(&pts[..=j]) {
            Some(t) if t.x * chord_dir.x + t.y * chord_dir.y >= 0.0 => t,
            Some(t) => Point { x: -t.x, y: -t.y },
            None => chord_dir,
        }
    };
    let mut acc = 0.0;
    let mut j = 0;
    for i in (0..n - 1).rev() {
        acc += chord(i);
        if acc >= l_min {
            j = i;
            break;
        }
    }
    let rt = {
        let d = Point { x: pts[j].x - pts[n - 1].x, y: pts[j].y - pts[n - 1].y };
        let l = d.x.hypot(d.y);
        if l == 0.0 || !l.is_finite() {
            return None;
        }
        let chord_dir = Point { x: d.x / l, y: d.y / l };
        match tls_dir(&pts[j..]) {
            Some(t) if t.x * chord_dir.x + t.y * chord_dir.y >= 0.0 => t,
            Some(t) => Point { x: -t.x, y: -t.y },
            None => chord_dir,
        }
    };
    Some((lt, rt))
}

/// Tangent estimate at an interior
/// adaptive split point, from a symmetric window of the PARENT arc's points
/// around k. Adaptive splits without a nearby smooth extremum previously
/// received no forced tangent (jt/back = None), so each child re-estimated
/// its end tangent from its own point range and the two estimates disagreed
/// at the shared node. Measured on a merged font:
/// 10.16 deg median kink at 1280 non-extremum cubic-cubic
/// junctions; extremum junctions, which do receive forced axis tangents,
/// measure 0.00 deg. One estimate at the split point, forced on both
/// children (left rt_force = -t, right lt_force = t), gives G1 continuity
/// there by construction. Arcs are corner-free here by upstream contract
/// (capture corners segment arcs; sharp_turn_rescue takes >=45 deg turns),
/// so a shared tangent at the split is the design intent, not smoothing
/// over structure. Same estimator family as windowed_chord_tangents:
/// symmetric chord window, TLS direction sign-matched to the chord.
fn split_tangent(pts: &[Point], k: usize) -> Option<Point> {
    let n = pts.len();
    if k == 0 || k + 1 >= n {
        return None;
    }
    let chord = |i: usize| (pts[i + 1].x - pts[i].x).hypot(pts[i + 1].y - pts[i].y);
    let total: f64 = (0..n - 1).map(chord).sum();
    if total == 0.0 {
        return None;
    }
    let l_min = crate::thresholds::tangent_l_min(total);
    let (mut l, mut acc) = (k, 0.0);
    while l > 0 && acc < l_min * 0.5 {
        l -= 1;
        acc += chord(l);
    }
    let (mut r, mut acc2) = (k, 0.0);
    while r < n - 1 && acc2 < l_min * 0.5 {
        acc2 += chord(r);
        r += 1;
    }
    if r <= l + 1 {
        return None;
    }
    let d = Point { x: pts[r].x - pts[l].x, y: pts[r].y - pts[l].y };
    let len = d.x.hypot(d.y);
    if len == 0.0 || !len.is_finite() {
        return None;
    }
    let chord_dir = Point { x: d.x / len, y: d.y / len };
    match tls_dir(&pts[l..=r]) {
        Some(t) if t.x * chord_dir.x + t.y * chord_dir.y >= 0.0 => Some(t),
        Some(t) => Some(Point { x: -t.x, y: -t.y }),
        None => Some(chord_dir),
    }
}

/// Dense one-way excursion (F1 patch): max distance from 65 dense samples of
/// the candidate cubic to the arc's own sample polyline SEGMENTS. The
/// Schneider sampled error is measured only AT sample points; a cubic can
/// thread every sample and still bow arbitrarily far between them (measured:
/// 37.9 font units = 21.5 px on the tail edge with mse 0.000242 << 0.1).
/// The simplified polyline is within capture rdp eps of the true iso-contour
/// by construction, so this is a true-edge-bound proxy, not a sampled proxy.
/// Two-sided dense gate: the one-sided
/// curve->source excursion misses cut corners (the curve can stay near the
/// source while a source corner sits far from the curve). The gate is now
/// max(curve->source, source->curve); it also returns the source-sample
/// index of the worst source->curve distance as the split hint, so a failed
/// fit divides AT the offending feature instead of the midpoint.
pub(crate) fn dense_gate(q: &[Point; 4], samples: &[Point]) -> (f64, usize) {
    fn basis(t: f64) -> [f64; 4] {
        let v = 1.0 - t;
        [v * v * v, 3.0 * t * v * v, 3.0 * t * t * v, t * t * t]
    }
    fn dist_seg(p: Point, a: Point, b: Point) -> f64 {
        let abx = b.x - a.x;
        let aby = b.y - a.y;
        let l2 = abx * abx + aby * aby;
        if l2 == 0.0 {
            return (p.x - a.x).hypot(p.y - a.y);
        }
        let t = (((p.x - a.x) * abx + (p.y - a.y) * aby) / l2).clamp(0.0, 1.0);
        (p.x - (a.x + t * abx)).hypot(p.y - (a.y + t * aby))
    }
    // flattened curve polyline, shared by both directions
    let mut curve = [Point { x: 0.0, y: 0.0 }; 65];
    for (k, cp) in curve.iter_mut().enumerate() {
        let t = k as f64 / 64.0;
        let b = basis(t);
        let mut p = Point { x: 0.0, y: 0.0 };
        for i in 0..4 {
            p.x += b[i] * q[i].x;
            p.y += b[i] * q[i].y;
        }
        *cp = p;
    }
    // curve -> source
    let mut worst = 0.0f64;
    for cp in &curve {
        let mut best = f64::INFINITY;
        for w in 0..samples.len() - 1 {
            best = best.min(dist_seg(*cp, samples[w], samples[w + 1]));
        }
        worst = worst.max(best);
    }
    // source -> curve, with argmax split hint
    let mut argmax = samples.len() / 2;
    for (i, &sp) in samples.iter().enumerate() {
        let mut best = f64::INFINITY;
        for w in 0..curve.len() - 1 {
            best = best.min(dist_seg(sp, curve[w], curve[w + 1]));
        }
        if best > worst {
            worst = best;
            argmax = i;
        }
    }
    (worst, argmax)
}

/// Dense-gate bound: capture default rdp eps (0.5 px) expressed in font
/// units via the caller's scale, plus one linear fit-tolerance unit. Fits
/// legitimately deviate from the chord by at most the rdp sagitta plus the
/// sampled tolerance; anything beyond is unmeasured freedom, not evidence.
/// (A second tolerance unit let small closed rings bulge outward of their
/// vertex polygon by up to 0.5 px: measured signed offset +0.21 px on the
/// small/thin tile class, +0.05 px with one unit.)
// Under FitErrorPolicy::DerivedSourceQuantization, squared_error = (K/2)^2, so sqrt = K/2 and this bound is
// 0.5*K + 0.5*K = 1.0*K: one source pixel. The former double threshold (0.25 px tolerance vs a 0.5K+0.5 dense gate)
// collapses into a single quantity derived from K. SOURCE ONLY - NOT RUN.
fn dense_bound(scale: f64, policy: &FitPolicy) -> f64 {
    0.5 * scale + policy.squared_error.sqrt()
}

/// A fitted span plus the half-open... inclusive source range [s, e] it
/// was fitted against (indices into its arc). P2 junction refinement
/// re-anchors Line-Line nodes to the intersection of the two spans' TLS
/// lines fitted over exactly these source points.
#[derive(Clone)]
pub struct FitSpan {
    pub span: Span,
    pub arc: usize,
    pub s: usize,
    pub e: usize,
}

/// Raw, by-value payload for the Unit 9 merge-visibility observer. This layer
/// deliberately does not hash or serialize: canonical fingerprint and span-ID
/// bytes belong to the shared `obs_envelope` contract.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MergeVisibilityPoint { P0, P1, P2, P3, P4, P5, P6, P7 }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MergeVisibilityDomain { Float, Integer }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MergeVisibilityPass { G2Merge, Staircase, LineJunction, StraightOverCurve, Qf, Closure, Rounding, Economy, Tidy, RescueAdoption }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MergeVisibilityTransform { G2LineRunFold, G2Union, G2Harmonize, StaircaseCollapse, LineJunctionMovement, SocConversion, QfRefinement, SyntheticClosure, Round, ExactCubicLine, ExactLineMerge, ZeroSpanRemoval, CornerAdoption, ArcRescue }

#[derive(Clone, Debug)]
pub struct MergeVisibilitySpan {
    pub arc: Option<usize>,
    pub source_start: Option<usize>,
    pub source_end: Option<usize>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct MergeVisibilitySnapshot {
    pub seq: u64,
    pub route_domain: crate::obs_envelope::RouteDomain,
    pub point: MergeVisibilityPoint,
    pub ring_index: usize,
    pub domain: MergeVisibilityDomain,
    pub start: Point,
    pub spans: Vec<MergeVisibilitySpan>,
    /// Exact arc samples by value, including arcs appended by accepted G2 unions.
    pub source_arcs: Vec<Vec<Point>>,
    pub ledger_counts: std::collections::BTreeMap<String, usize>,
    pub synthetic_closures: usize,
}

#[derive(Clone, Debug)]
pub struct MergeVisibilityRewrite {
    pub seq: u64,
    pub route_domain: crate::obs_envelope::RouteDomain,
    pub ring_index: usize,
    pub pass: MergeVisibilityPass,
    pub transforms: Vec<MergeVisibilityTransform>,
    pub input_start: Option<Point>,
    pub output_start: Option<Point>,
    pub input_spans: Vec<MergeVisibilitySpan>,
    pub output_spans: Vec<MergeVisibilitySpan>,
    pub input_source_arcs: Vec<Vec<Point>>,
    pub output_source_arcs: Vec<Vec<Point>>,
    /// Typed economy decisions preserve the exact rule/count evidence; the
    /// serializer must not infer operation identity from a total delta.
    pub economy_decisions: Vec<crate::economy::EconomyDecision>,
}

#[derive(Clone, Debug, Default)]
pub struct MergeVisibilityCollector {
    pub observations: Vec<MergeVisibilitySnapshot>,
    pub rewrites: Vec<MergeVisibilityRewrite>,
}

#[derive(Default)]
struct MergeVisibilityBuffer {
    enabled: bool,
    next_seq: u64,
    route_domain: crate::obs_envelope::RouteDomain,
    observations: Vec<MergeVisibilitySnapshot>,
    rewrites: Vec<MergeVisibilityRewrite>,
}
thread_local! {
    static MERGE_VISIBILITY: std::cell::RefCell<MergeVisibilityBuffer> = std::cell::RefCell::new(MergeVisibilityBuffer::default());
}

/// Start collection for the current worker thread. Default is OFF; callers
/// must explicitly opt in, then take the result on the same worker thread.
pub fn merge_visibility_begin() {
    MERGE_VISIBILITY.with(|cell| {
        let mut buffer = cell.borrow_mut();
        buffer.observations.clear();
        buffer.rewrites.clear();
        buffer.next_seq = 0;
        buffer.route_domain = crate::obs_envelope::RouteDomain::Primary;
        buffer.enabled = true;
    });
}

/// Stop collection and return its owned records. Does not affect fitting state.
/// Begin capture while pinning the actual fit route branch (primary or outline).
/// This is call-site provenance, not inferred later by the serializer.
pub fn merge_visibility_begin_for_route_domain(domain: crate::obs_envelope::RouteDomain) {
    MERGE_VISIBILITY.with(|cell| {
        let mut buffer = cell.borrow_mut();
        buffer.observations.clear();
        buffer.rewrites.clear();
        buffer.next_seq = 0;
        buffer.route_domain = domain;
        buffer.enabled = true;
    });
}

pub fn merge_visibility_take_collector() -> MergeVisibilityCollector {
    MERGE_VISIBILITY.with(|cell| {
        let mut buffer = cell.borrow_mut();
        buffer.enabled = false;
        MergeVisibilityCollector {
            observations: std::mem::take(&mut buffer.observations),
            rewrites: std::mem::take(&mut buffer.rewrites),
        }
    })
}

/// Compatibility tuple view; production callers should retain the typed collector.
pub fn merge_visibility_take() -> (Vec<MergeVisibilitySnapshot>, Vec<MergeVisibilityRewrite>) {
    let collector = merge_visibility_take_collector();
    (collector.observations, collector.rewrites)
}

pub fn merge_visibility_enabled() -> bool {
    MERGE_VISIBILITY.with(|cell| cell.borrow().enabled)
}

fn visibility_ring_index() -> usize {
    CURRENT_CORNER_SITE.with(|cell| cell.get().0)
}

fn visibility_fit_spans(spans: &[FitSpan]) -> Vec<MergeVisibilitySpan> {
    spans.iter().map(|span| MergeVisibilitySpan {
        arc: Some(span.arc), source_start: Some(span.s), source_end: Some(span.e), span: span.span.clone(),
    }).collect()
}

fn visibility_same_point(a: Point, b: Point) -> bool { a.x.to_bits() == b.x.to_bits() && a.y.to_bits() == b.y.to_bits() }

fn visibility_same_span(a: &Span, b: &Span) -> bool {
    match (a, b) {
        (Span::Line { end: a }, Span::Line { end: b }) => visibility_same_point(*a, *b),
        (Span::Cubic { control_one: a1, control_two: a2, end: a3 },
         Span::Cubic { control_one: b1, control_two: b2, end: b3 }) =>
            visibility_same_point(*a1, *b1) && visibility_same_point(*a2, *b2) && visibility_same_point(*a3, *b3),
        _ => false,
    }
}

fn visibility_same_fit_state(a: &[FitSpan], b: &[FitSpan]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)|
        x.arc == y.arc && x.s == y.s && x.e == y.e && visibility_same_span(&x.span, &y.span))
}

fn visibility_same_plain_state(a: &[Span], b: &[Span]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| visibility_same_span(x, y))
}

fn visibility_plain_spans(spans: &[Span], arcs: &[usize]) -> Vec<MergeVisibilitySpan> {
    spans.iter().enumerate().map(|(i, span)| MergeVisibilitySpan {
        arc: arcs.get(i).copied(), source_start: None, source_end: None, span: span.clone(),
    }).collect()
}

fn visibility_ledger_counts(
    fevents: &[FallbackEvent], astubs: &[AmbiguousStub], declined: &[DeclinedAmbiguity], ring: usize,
) -> std::collections::BTreeMap<String, usize> {
    let mut counts = std::collections::BTreeMap::new();
    counts.insert("fallback_events".to_owned(), fevents.len());
    counts.insert("ambiguous_stubs".to_owned(), astubs.len());
    counts.insert("declined_ambiguities".to_owned(), declined.len());
    CORNER_ADOPTION_RECORDS.with(|records| {
        let records = records.borrow();
        let ring_records = records.iter().filter(|record| record.ring == ring);
        counts.insert("corner_adopted".to_owned(), ring_records.clone().filter(|record| record.corner_adopted).count());
        counts.insert("rescue_adopted".to_owned(), ring_records.filter(|record| record.rescue_adopted).count());
    });
    counts
}

fn merge_visibility_observe_fit(
    point: MergeVisibilityPoint, domain: MergeVisibilityDomain, start: Point, spans: &[FitSpan], arcs: &[Vec<Point>],
    fevents: &[FallbackEvent], astubs: &[AmbiguousStub], declined: &[DeclinedAmbiguity], synthetic_closures: usize,
) {
    if !merge_visibility_enabled() { return; }
    let ring_index = visibility_ring_index();
    MERGE_VISIBILITY.with(|cell| { let mut b = cell.borrow_mut(); let seq = b.next_seq; b.next_seq = b.next_seq.checked_add(1).expect("merge visibility seq overflow"); let route_domain = b.route_domain.clone(); b.observations.push(MergeVisibilitySnapshot {
        seq, route_domain, point, ring_index, domain, start, spans: visibility_fit_spans(spans), source_arcs: arcs.to_vec(),
        ledger_counts: visibility_ledger_counts(fevents, astubs, declined, ring_index), synthetic_closures,
    }); });
}

fn merge_visibility_observe_plain(
    point: MergeVisibilityPoint, domain: MergeVisibilityDomain, start: Point, spans: &[Span], span_arcs: &[usize],
    arcs: &[Vec<Point>], fevents: &[FallbackEvent], astubs: &[AmbiguousStub], declined: &[DeclinedAmbiguity],
    synthetic_closures: usize,
) {
    if !merge_visibility_enabled() { return; }
    let ring_index = visibility_ring_index();
    MERGE_VISIBILITY.with(|cell| { let mut b = cell.borrow_mut(); let seq = b.next_seq; b.next_seq = b.next_seq.checked_add(1).expect("merge visibility seq overflow"); let route_domain = b.route_domain.clone(); b.observations.push(MergeVisibilitySnapshot {
        seq, route_domain, point, ring_index, domain, start, spans: visibility_plain_spans(spans, span_arcs), source_arcs: arcs.to_vec(),
        ledger_counts: visibility_ledger_counts(fevents, astubs, declined, ring_index), synthetic_closures,
    }); });
}

fn merge_visibility_rewrite_fit(
    pass: MergeVisibilityPass, transform: MergeVisibilityTransform, input: &[FitSpan], output: &[FitSpan],
    input_arcs: &[Vec<Point>], output_arcs: &[Vec<Point>],
) {
    merge_visibility_rewrite_fit_with_starts(pass, transform, input, output, input_arcs, output_arcs, None, None);
}

fn merge_visibility_rewrite_fit_with_starts(
    pass: MergeVisibilityPass, transform: MergeVisibilityTransform, input: &[FitSpan], output: &[FitSpan],
    input_arcs: &[Vec<Point>], output_arcs: &[Vec<Point>], input_start: Option<Point>, output_start: Option<Point>,
) {
    let start_changed = match (input_start, output_start) {
        (Some(a), Some(b)) => !visibility_same_point(a, b),
        _ => false,
    };
    if !merge_visibility_enabled() || (visibility_same_fit_state(input, output) && !start_changed) { return; }
    MERGE_VISIBILITY.with(|cell| { let mut b = cell.borrow_mut(); let seq = b.next_seq; b.next_seq = b.next_seq.checked_add(1).expect("merge visibility seq overflow"); let route_domain = b.route_domain.clone(); b.rewrites.push(MergeVisibilityRewrite {
        seq, route_domain, ring_index: visibility_ring_index(), pass, transforms: vec![transform], input_start, output_start,
        input_spans: visibility_fit_spans(input), output_spans: visibility_fit_spans(output),
        input_source_arcs: input_arcs.to_vec(), output_source_arcs: output_arcs.to_vec(), economy_decisions: Vec::new(),
    }); });
}

fn merge_visibility_rewrite_plain(
    pass: MergeVisibilityPass, transform: MergeVisibilityTransform, input: &[Span], output: &[Span],
    span_arcs: &[usize], input_arcs: &[Vec<Point>], output_arcs: &[Vec<Point>],
) {
    if !merge_visibility_enabled() || visibility_same_plain_state(input, output) { return; }
    MERGE_VISIBILITY.with(|cell| { let mut b = cell.borrow_mut(); let seq = b.next_seq; b.next_seq = b.next_seq.checked_add(1).expect("merge visibility seq overflow"); let route_domain = b.route_domain.clone(); b.rewrites.push(MergeVisibilityRewrite {
        seq, route_domain, ring_index: visibility_ring_index(), pass, transforms: vec![transform], input_start: None, output_start: None,
        input_spans: visibility_plain_spans(input, span_arcs), output_spans: visibility_plain_spans(output, span_arcs),
        input_source_arcs: input_arcs.to_vec(), output_source_arcs: output_arcs.to_vec(), economy_decisions: Vec::new(),
    }); });
}

fn merge_visibility_rewrite_plain_with_starts(
    pass: MergeVisibilityPass, transform: MergeVisibilityTransform, input: &[Span], output: &[Span],
    span_arcs: &[usize], input_arcs: &[Vec<Point>], output_arcs: &[Vec<Point>], input_start: Option<Point>, output_start: Option<Point>,
) {
    let start_changed = match (input_start, output_start) {
        (Some(a), Some(b)) => !visibility_same_point(a, b),
        _ => false,
    };
    if !merge_visibility_enabled() || (visibility_same_plain_state(input, output) && !start_changed) { return; }
    MERGE_VISIBILITY.with(|cell| { let mut b = cell.borrow_mut(); let seq = b.next_seq; b.next_seq = b.next_seq.checked_add(1).expect("merge visibility seq overflow"); let route_domain = b.route_domain.clone(); b.rewrites.push(MergeVisibilityRewrite {
        seq, route_domain, ring_index: visibility_ring_index(), pass, transforms: vec![transform], input_start, output_start,
        input_spans: visibility_plain_spans(input, span_arcs), output_spans: visibility_plain_spans(output, span_arcs),
        input_source_arcs: input_arcs.to_vec(), output_source_arcs: output_arcs.to_vec(), economy_decisions: Vec::new(),
    }); });
}


fn merge_visibility_attach_economy_decisions(
    transform: MergeVisibilityTransform,
    decisions: Vec<crate::economy::EconomyDecision>,
) {
    if decisions.is_empty() || !merge_visibility_enabled() { return; }
    let ring = visibility_ring_index();
    MERGE_VISIBILITY.with(|cell| {
        let mut b = cell.borrow_mut();
        if let Some(rewrite) = b.rewrites.iter_mut().rev().find(|r|
            r.ring_index == ring && r.pass == MergeVisibilityPass::Economy
                && r.transforms == [transform]) {
            rewrite.economy_decisions.extend(decisions);
        }
    });
}

fn merge_visibility_set_last_snapshot_count(key: &str, value: usize) {
    if !merge_visibility_enabled() { return; }
    let ring = visibility_ring_index();
    MERGE_VISIBILITY.with(|cell| {
        let mut b = cell.borrow_mut();
        if let Some(snapshot) = b.observations.iter_mut().rev().find(|o|
            o.ring_index == ring && o.point == MergeVisibilityPoint::P7) {
            snapshot.ledger_counts.insert(key.to_owned(), value);
        }
    });
}


// RAW_RING holds the pre-RDP ring of the ring currently being fitted. fit_captured MUST set it
// before fit_ring_db runs (see fit_captured); a caller that does not leaves it empty and the
// staircase merge / straight-over-curve pass silently abstain (conservative, never wrong).
thread_local! { static RAW_RING: std::cell::RefCell<Vec<Point>> = std::cell::RefCell::new(Vec::new()); }

/// fit-raw-ring-tls: clear the per-task raw ring. Every fitting task boundary
/// (each fit_captured* glyph task and each standalone fit_ring* ring task)
/// resets BEFORE fitting, so a worker thread reused across tasks (the parallel
/// stage-1 pool) can never read the previous task's ring: a path that never
/// sets it abstains (empty), exactly the documented "leaves it empty" contract.
pub fn reset_raw_ring() { RAW_RING.with(|r| r.borrow_mut().clear()); }

/// Staircase-aware straightness evidence. An arc whose RDP vertices (turn < 60 deg each)
/// zigzag around one line may be a straight edge rasterised as a pixel staircase
/// (RDP facets sit up to ~s*sqrt(2)/2 off the ideal line for step pitch s). Evidence is
/// measured on the RAW traced points between the arc's end vertices: Line if every raw
/// point lies within t_line of the end chord (R8: the raw-chain silent-acceptance
/// rule, same invariant as raw_chord_dev; T_LINE_SLACK no longer licenses a
/// write) AND within t_line of the raw points' own total-least-squares line
/// (R9: staircase evidence filter, unchanged).

/// Raw (pre-RDP) boundary points between two RDP vertices a and b of the current ring.
fn raw_between(a: Point, b: Point) -> Option<Vec<Point>> {
    RAW_RING.with(|r| {
        let raw = r.borrow();
        let n = raw.len();
        if n < 4 { return None; }
        // exact-equality match relies on RDP emitting a SUBSET of the raw points with identical
        // coordinates; if RDP ever smooths its output this lookup fails and the pass abstains.
        let ia = raw.iter().position(|p| p.x == a.x && p.y == a.y)?;
        let mut seg = vec![raw[ia]];
        let mut i = ia;
        for _ in 0..n {
            i = (i + 1) % n;
            seg.push(raw[i]);
            if raw[i].x == b.x && raw[i].y == b.y { return Some(seg); }
        }
        None
    })
}

/// Silent Line acceptance (raw-chain rule): a span may be written as a Line
/// WITHOUT a typed ledger event only when the RAW (pre-RDP) boundary chain
/// between its chord endpoints stays within the derived line tolerance
/// t_line of the emitted chord. Derivation: t_line = rdp_eps + 0.5px pixel
/// quantization (the capture chain's own straightness tolerance, same
/// derivation as T_circle), and a straight-built source's raw chain stays
/// within rdp slack plus quantization of its chord. The retired
/// captured-points-only acceptance measured the post-RDP SUBSET: RDP slack
/// let a captured-clean chord stand up to ~2px of raw bow (the
/// silent-straight defect). Returns the raw chain's max chord deviation, or
/// None when the caller's points ARE the raw source (no separate raw chain
/// set, or a mitre rewrite detached the endpoints): measure those points
/// directly.
fn raw_chord_dev(a: Point, b: Point) -> Option<f64> {
    let seg = raw_between(a, b)?;
    let (abx, aby) = (b.x - a.x, b.y - a.y);
    let l = abx.hypot(aby);
    if l <= 0.0 { return Some(0.0); }
    let mut dev = 0.0f64;
    for p in &seg {
        dev = dev.max((abx * (p.y - a.y) - aby * (p.x - a.x)).abs() / l);
    }
    Some(dev)
}

fn staircase_line(pts: &[Point], t_line: f64) -> bool {
    if pts.len() < 4 { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R1"); } return false; } }
    if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("STAIRTRY len {} first ({:.1},{:.1}) last ({:.1},{:.1})", pts.len(), pts[0].x, pts[0].y, pts[pts.len()-1].x, pts[pts.len()-1].y); }
    let a = pts[0]; let b = pts[pts.len() - 1];
    let l = (b.x - a.x).hypot(b.y - a.y);
    if l < 8.0 * t_line { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R2"); } return false; } }
    // gentle, monotone turning
    let mut sign = 0.0f64;
    for w in pts.windows(3) {
        let v1 = (w[1].x - w[0].x, w[1].y - w[0].y);
        let v2 = (w[2].x - w[1].x, w[2].y - w[1].y);
        let l1 = v1.0.hypot(v1.1); let l2 = v2.0.hypot(v2.1);
        if l1 == 0.0 || l2 == 0.0 { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R3"); } return false; } }
        let cr = v1.0 * v2.1 - v1.1 * v2.0;
        let cs = (v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2);
        if cs < crate::thresholds::CORNER_TURN_COS { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R4"); } return false; } } // turn > 60 deg: a corner, not a facet
        let _ = (cr, &mut sign); // facets of a rasterised straight edge zigzag around it: sign is not evidence
    }
    RAW_RING.with(|r| {
        let raw = r.borrow();
        let n = raw.len();
        if n < 4 { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R6"); } return false; } }
        let ia = match raw.iter().position(|p| p.x == a.x && p.y == a.y) { Some(i) => i, None => return false };
        let mut seg: Vec<Point> = vec![raw[ia]];
        let mut i = ia; let mut found = false;
        for _ in 0..n {
            i = (i + 1) % n;
            seg.push(raw[i]);
            if raw[i].x == b.x && raw[i].y == b.y { found = true; break; }
        }
        if !found || seg.len() < pts.len() { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R7"); } return false; } }
        // chord deviation of raw points
        let (abx, aby) = (b.x - a.x, b.y - a.y);
        for p in &seg { let d = (abx * (p.y - a.y) - aby * (p.x - a.x)).abs() / l; if d > t_line { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R8"); } return false; } } }
        // TLS line of raw points
        let m = seg.len() as f64;
        let (mx, my) = (seg.iter().map(|p| p.x).sum::<f64>() / m, seg.iter().map(|p| p.y).sum::<f64>() / m);
        let (mut sxx, mut syy, mut sxy) = (0.0, 0.0, 0.0);
        for p in &seg { let dx = p.x - mx; let dy = p.y - my; sxx += dx * dx; syy += dy * dy; sxy += dx * dy; }
        let th = 0.5 * (2.0 * sxy).atan2(sxx - syy);
        let (ux, uy) = (th.cos(), th.sin());
        for p in &seg { let d = ((p.x - mx) * uy - (p.y - my) * ux).abs(); if d > t_line { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject R9"); } return false; } } }
        // staircase evidence: residuals of the raw points about their TLS line must zigzag (a gentle curve
        // crosses its best line <= 2 times; a pixel staircase crosses it once per step)
        let res: Vec<f64> = seg.iter().map(|p| (p.x - mx) * uy - (p.y - my) * ux).collect();
        let mut cross = 0usize; let mut last = 0.0f64;
        for &v in &res { if v.abs() < 0.05 { continue; } if last != 0.0 && v.signum() != last { cross += 1; } last = v.signum(); }
        let min_cross: usize = 6;
        if cross < min_cross { { if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("  reject XC {}", cross); } return false; } }
        if std::env::var("KNI_LOG_STAIR").is_ok() { eprintln!("STAIR arc ({:.1},{:.1})->({:.1},{:.1}) pts {} raw {} -> Line", a.x, a.y, b.x, b.y, pts.len(), seg.len()); }
        true
    })
}

/// Typed per-point Line fallback ledger. Every Line span emitted because a
/// curve-intended arc (one that FAILED the measured line-first straightness
/// test) could not be fitted as a cubic carries an event here with its
/// reason. Count + reason enter the receipt; an intended-curved glyph left
/// unresolved HARD-FAILS export (no silent polygonal degradation).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FallbackReason { SplitUnresolved, DepthLimit, DegenerateTangents,
    /// Typed stop (not a silent line): a span whose chord is shorter than the
    /// acquisition lattice step cannot carry measurable curve structure - the
    /// iso chain locates edges to one pixel cell, so any curvature inside a
    /// sub-grid span is below the source's own resolving power and drawing a
    /// curve there would be invention, not reconstruction. The span stops as
    /// one Line and the event keeps the stop auditable.
    SubGridSpan,
    /// Typed restore (not a silent line): the fit collapsed a ring that
    /// carried measurable capture ink to zero emitted area (thin-sliver
    /// corner suppression). The ring ships as the captured polygon in Line
    /// spans; the event keeps the restore auditable in the fallback ledger.
    AreaCollapseRestored }
#[derive(Clone, Copy, Debug)]
pub struct FallbackEvent { pub arc: usize, pub s: usize, pub e: usize, pub reason: FallbackReason, pub stop: Option<RefitStop> }

/// r282 audit-only per-span fallback provenance: glyph/ring/span identity plus
/// measured geometry (chord, arc length, max chord deviation, source-pixel
/// units) and the typed reason from the producer branch. Rows are built from
/// the FINAL adopted event ledger and the producer arc's own samples; no fit
/// decision, geometry, export, spacing or solver code reads them. A metric
/// that cannot be measured from the fragment stays None (printed as "-"),
/// never an invented number. arc == usize::MAX marks a ring-level event
/// (AreaCollapseRestored) that has no arc fragment.
#[derive(Clone, Copy, Debug)]
pub struct FallbackSpanProvenance {
    pub ring: usize,
    pub arc: usize,
    pub s: usize,
    pub e: usize,
    pub chord_px: Option<f64>,
    pub arc_len_px: Option<f64>,
    pub max_dev_px: Option<f64>,
    pub reason: FallbackReason,
    /// r288 audit-only: stop class carried verbatim from the fallback event -
    /// the nearest producer FitOutcome stop on the split cascade above this
    /// span; None for event classes with no cubic-fit producer outcome.
    pub stop: Option<RefitStop>,
    /// r288 audit-only: decline class joined from this ring's finalized
    /// DeclinedAmbiguity ledger at (arc, s, e); SplitUnresolved spans carry a
    /// sibling decline by construction, every other event class stays None.
    pub decline: Option<DeclinedClass>,
}

/// Chord length, polyline arc length, and max chord deviation of
/// samples[s..=e] in the samples' own units; None when the slice is not a
/// measurable fragment.
fn span_fragment_metrics(samples: &[Point], s: usize, e: usize) -> (Option<f64>, Option<f64>, Option<f64>) {
    if s >= e || e >= samples.len() { return (None, None, None); }
    let frag = &samples[s..=e];
    let a = frag[0];
    let b = frag[frag.len() - 1];
    let chord = (b.x - a.x).hypot(b.y - a.y);
    let mut arc_len = 0.0f64;
    for w in frag.windows(2) { arc_len += (w[1].x - w[0].x).hypot(w[1].y - w[0].y); }
    let max_dev = if chord > 0.0 {
        let abx = b.x - a.x;
        let aby = b.y - a.y;
        frag[1..frag.len() - 1].iter().map(|p| (abx * (p.y - a.y) - aby * (p.x - a.x)).abs() / chord).fold(0.0f64, f64::max)
    } else { 0.0 };
    (Some(chord), Some(arc_len), Some(max_dev))
}

thread_local! {
    static STRAIGHT_SWEEP_CONVERTED: std::cell::Cell<usize> = std::cell::Cell::new(0);
}
/// A-PRIME typed ambiguity record (AmbiguousPixelCandidate pattern carried to
/// the outline domain): a stub emitted from a budget-exhausted short arc
/// whose straight reading stays within the dense bound AND whose parent arc
/// carries measured corner evidence (dominant vertex per the sharp-turn
/// convention, both legs line-plausible at the same bound). The write is
/// typed, not "resolved": the span is an intentional straight stub and this
/// record keeps the ambiguity, its derivation, and its justification
/// auditable. Distinct from both an intentional Line (no ambiguity) and a
/// SplitUnresolved event (no honest one-pixel reading).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AmbiguityClass {
    /// Dominant measured vertex AND both leg sagittas within the dense
    /// bound: the corner reading is honest at the lattice's resolving power.
    CornerLeaning,
    /// Dominant measured vertex but at least one leg sagitta beyond the
    /// dense bound: the round reading keeps measurable evidence.
    RoundAmbiguous,
    /// No measured sharp turn at the budget-exhausted parent: neither
    /// reading carries structural evidence.
    TrulyAmbiguous,
}
/// Why a candidate ambiguous stub was NOT written (the SplitUnresolved
/// event stays). Counts derive from the returned ledgers - single source,
/// no side counters.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum DeclinedClass {
    /// Parent lineage round-ambiguous (vertex measured, a leg sagitta beyond
    /// the dense bound): no honest corner reading, no write.
    RoundAmbiguous,
    /// Parent lineage truly-ambiguous (budget exhausted, no measured turn).
    TrulyAmbiguous,
    /// Stub deviation in the (dense_bound, t_line] band: beyond the
    /// one-pixel reading's bound, inside the line tolerance.
    Band,
    /// No lineage evidence at all: the bottom-out arrived without a
    /// corner-classified parent. The deviation measurement is identical in
    /// kind to the ambiguous-lineage classes, so the same in-bound rule
    /// applies (architect decision, PN-3 lineage-None extension of (a)).
    NoLineage,
}
#[derive(Clone, Copy, Debug)]
pub struct DeclinedAmbiguity {
    pub arc: usize, pub s: usize, pub e: usize,
    pub class: DeclinedClass,
    pub lineage_class: Option<AmbiguityClass>,
    pub stub_dev: f64, pub dense_bound: f64,
}
#[derive(Clone, Copy, Debug)]
pub struct AmbiguousStub {
    pub arc: usize, pub s: usize, pub e: usize,
    /// Pixel reading at the acquisition lattice's resolving power; NOT a
    /// glyph-intent claim.
    pub class: AmbiguityClass,
    /// The budget-exhausted parent arc the class evidence was measured on
    /// (derivation reference: sharp_turn_rescue vertex + leg sagittas).
    pub parent_arc: usize, pub parent_s: usize, pub parent_e: usize,
    /// Parent-relative dominant vertex index (sharp_turn_rescue derivation).
    pub vertex: usize,
    pub leg_in_sagitta: f64, pub leg_out_sagitta: f64,
    /// Measured chord deviation of THIS stub's captured (post-RDP) source
    /// points, font units. Zero by construction at len 2. The pre-RDP raw
    /// chain needs no plumbing: its deviation from the same chord is within
    /// rdp_eps by the RDP invariant, and rdp_eps < db (db = rdp_eps + one
    /// linear fit-tolerance unit), so the captured-point measurement bounds
    /// the raw one inside the same gate.
    pub stub_dev: f64,
    /// The dense bound the stub was judged against (within-one-pixel
    /// justification this write stands on).
    pub dense_bound: f64,
}
/// Lineage evidence measured once at a budget-exhausted parent arc and
/// carried down its split subtree; a child that fits as a cubic drops it
/// (the cubic invariant: the marker changes records, never fit outcomes).
#[derive(Clone, Copy, Debug)]
struct LineageEvidence {
    class: AmbiguityClass,
    parent_arc: usize, parent_s: usize, parent_e: usize,
    vertex: Option<usize>,
    leg_in_sagitta: f64, leg_out_sagitta: f64,
}
/// Typed metric: spans the final straight sweep converted Cubic -> Line
/// (long chord, both handles within one source pixel of the chord). The
/// pipeline driver measures per-glyph deltas on the fitting thread (FitCounters) and sums them in manifest order.
pub fn straight_sweep_converted() -> usize { STRAIGHT_SWEEP_CONVERTED.with(|c| c.get()) }
/// Reset the per-run straight-sweep counter.
pub fn reset_straight_sweep_converted() { STRAIGHT_SWEEP_CONVERTED.with(|c| c.set(0)) }
/// Add a count measured on another thread (the parallel stage-1 reduce folds per-glyph deltas back, in manifest order).
/// Exact: an overflow is an error, never a silent clamp.
pub fn add_straight_sweep_converted(n: usize) -> Result<(), &'static str> {
    STRAIGHT_SWEEP_CONVERTED.with(|c| -> Result<(), &'static str> { c.set(c.get().checked_add(n).ok_or("straight_sweep counter overflow")?); Ok(()) })
}
/// Vertices moved by corner relocation on THIS thread since its last reset (per-thread, like the straight-sweep counter).
pub fn reloc_moved() -> usize { RELOC_MOVED.with(|c| c.get()) }

/// Sub-pixel speck ledger (architect decision, PN-3 speck KEEP+FLAG): each
/// retained speck's capture-space polygon area (px^2), appended at emission.
/// Marker/slice reading is exact per glyph under any scheduling, the same
/// contract FitCounters documents for the scalar counters.
pub fn speck_marker() -> usize { SPECK_AREAS.with(|v| v.borrow().len()) }
/// Areas of specks retained on this thread since `marker`.
pub fn speck_areas_since(marker: usize) -> Vec<f64> { SPECK_AREAS.with(|v| v.borrow().get(marker..).unwrap_or(&[]).to_vec()) }
pub fn reset_speck_areas() { SPECK_AREAS.with(|v| v.borrow_mut().clear()) }
fn record_speck(area_px2: f64) { SPECK_AREAS.with(|v| v.borrow_mut().push(area_px2)) }
/// Total spans emitted through the speck minimal-contour path (node-delta measurement).
pub fn speck_spans() -> usize { SPECK_SPANS.with(|c| c.get()) }
pub fn reset_speck_spans() { SPECK_SPANS.with(|c| c.set(0)) }
/// Hole-flagged sub-pixel rings dropped at the speck classification on this
/// thread (typed drop row; always output, zero included).
pub fn speck_retained_hole() -> usize { SPECK_RETAINED_HOLE.with(|c| c.get()) }
pub fn reset_speck_retained_hole() { SPECK_RETAINED_HOLE.with(|c| c.set(0)) }
/// Sub-pixel specks (either hole class) dropped at emission because their
/// rounded points have no grid representation (single-point or zero-area
/// post-round collapse; reason post_round_collapse), this thread.
pub fn speck_dropped_collapse() -> usize { SPECK_DROPPED_COLLAPSE.with(|c| c.get()) }
pub fn reset_speck_dropped_collapse() { SPECK_DROPPED_COLLAPSE.with(|c| c.set(0)) }
/// Reset this thread's relocation counter.
pub fn reset_reloc_moved() { RELOC_MOVED.with(|c| c.set(0)) }
/// Fold a relocation count measured on another thread into this thread's counter (exact; overflow is an error).
pub fn add_reloc_moved(n: usize) -> Result<(), &'static str> {
    RELOC_MOVED.with(|c| -> Result<(), &'static str> { c.set(c.get().checked_add(n).ok_or("reloc_moved counter overflow")?); Ok(()) })
}

/// Empties this thread's RAW_RING on entry and again on exit (also on unwind),
/// so no fit ever sees pre-RDP points left by an earlier glyph on the same
/// thread. Without it the staircase passes of a direct `fit_ring_db*` call
/// would read whatever the previous task on this thread stored, and output
/// would depend on which pool thread ran which glyph.
struct RawRingScope;
impl RawRingScope {
    // Reset BEFORE fitting (the task-boundary contract): a path that never sets RAW_RING
    // abstains empty; what a task leaves afterwards is its own ring.
    fn enter() -> Self { RAW_RING.with(|r| r.borrow_mut().clear()); RawRingScope }
}

/// Per-thread fit counters read around one glyph fit. A parallel driver takes `FitCounters::now()` before and
/// `FitCounters::delta_since` after the fit ON THE SAME THREAD; the delta is exact for that glyph and independent of scheduling.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct FitCounters { pub straight_sweep: usize, pub reloc_moved: usize }
impl FitCounters {
    pub fn now() -> Self { FitCounters { straight_sweep: straight_sweep_converted(), reloc_moved: reloc_moved() } }
    /// Counters accumulated on this thread since `before`. The counters only grow within a fit, so a decrease is a
    /// refusal (None), never a clamped zero.
    pub fn delta_since(before: FitCounters) -> Option<Self> {
        let n = Self::now();
        Some(FitCounters { straight_sweep: n.straight_sweep.checked_sub(before.straight_sweep)?, reloc_moved: n.reloc_moved.checked_sub(before.reloc_moved)? })
    }
}

fn sub_grid_extent(pts: &[Point], grid: f64) -> bool {
    let (mut mnx, mut mxx, mut mny, mut mxy) =
        (f64::INFINITY, f64::NEG_INFINITY, f64::INFINITY, f64::NEG_INFINITY);
    for p in pts {
        mnx = mnx.min(p.x); mxx = mxx.max(p.x);
        mny = mny.min(p.y); mxy = mxy.max(p.y);
    }
    (mxx - mnx) < grid && (mxy - mny) < grid
}

fn fit_gated(pts: &[Point], policy: &FitPolicy, spans: &mut Vec<FitSpan>, depth: usize, fb: &mut bool, db: f64, t_line: f64, grid: f64, depth_cap: usize, arc: usize, base: usize, lt_force: Option<Point>, rt_force: Option<Point>, unresolved: bool, ustop: Option<RefitStop>, fevents: &mut Vec<FallbackEvent>, astubs: &mut Vec<AmbiguousStub>, lineage: Option<LineageEvidence>, declined: &mut Vec<DeclinedAmbiguity>, fit_fn: fn(&[Point], Point, Point, &FitPolicy) -> FitOutcome) {
    // A-PRIME emission decision for unresolved Line bottom-outs. The stub is
    // written as a typed AmbiguousStub only when the TWO-PART gate passes:
    // (a) this stub's own measured deviation stays within the dense bound,
    // (b) the lineage carries corner-classified parent evidence. Without
    // (b) there is no write: the SplitUnresolved event stays, counted under
    // its lineage class. The (dense_bound, t_line] deviation band keeps
    // SplitUnresolved as well, under its own counter.
    let emit_unresolved_line = |arc: usize, s0: usize, e0: usize, stub_dev: f64,
                                lineage: Option<LineageEvidence>,
                                fevents: &mut Vec<FallbackEvent>, astubs: &mut Vec<AmbiguousStub>,
                                declined: &mut Vec<DeclinedAmbiguity>| {
        if stub_dev <= db {
            match lineage {
                Some(ev) if ev.class == AmbiguityClass::CornerLeaning => {
                    astubs.push(AmbiguousStub {
                        arc, s: s0, e: e0, class: AmbiguityClass::CornerLeaning,
                        parent_arc: ev.parent_arc, parent_s: ev.parent_s, parent_e: ev.parent_e,
                        vertex: ev.vertex.unwrap_or(0),
                        leg_in_sagitta: ev.leg_in_sagitta, leg_out_sagitta: ev.leg_out_sagitta,
                        stub_dev, dense_bound: db,
                    });
                }
                Some(ev) => {
                    let class = match ev.class {
                        AmbiguityClass::RoundAmbiguous => DeclinedClass::RoundAmbiguous,
                        _ => DeclinedClass::TrulyAmbiguous,
                    };
                    // Architect decision (PN-3, option a): an in-bound
                    // ambiguous-lineage Line (stub_dev <= dense bound, this
                    // branch) whose fragment carries a REAL measurement -
                    // at least three samples, so the deviation is not the
                    // trivial two-sample zero - is accepted event-free. The
                    // typed DeclinedAmbiguity receipt below is retained in
                    // full: the honesty ledger loses nothing; only the
                    // hard-fail gate input (the SplitUnresolved event) is
                    // suppressed. A two-sample fragment (no interior
                    // measurement) keeps its event.
                    declined.push(DeclinedAmbiguity { arc, s: s0, e: e0, class, lineage_class: Some(ev.class), stub_dev, dense_bound: db });
                    if e0 - s0 + 1 < 3 {
                        fevents.push(FallbackEvent { arc, s: s0, e: e0, reason: FallbackReason::SplitUnresolved, stop: ustop });
                    }
                }
                None => {
                    // Architect decision (PN-3, lineage-None extension of
                    // rule (a)): an in-bound Line WITHOUT lineage evidence
                    // is measured the same way as an ambiguous-lineage one;
                    // the fragment's own sample count, not the presence of
                    // parent evidence, decides whether a real measurement
                    // exists. >=3 samples: accepted event-free, typed
                    // DeclinedAmbiguity receipt retained (this branch
                    // previously wrote NO receipt - the honesty ledger gains
                    // a row, loses nothing). Two samples: event stays.
                    declined.push(DeclinedAmbiguity { arc, s: s0, e: e0, class: DeclinedClass::NoLineage, lineage_class: None, stub_dev, dense_bound: db });
                    if e0 - s0 + 1 < 3 {
                        fevents.push(FallbackEvent { arc, s: s0, e: e0, reason: FallbackReason::SplitUnresolved, stop: ustop });
                    }
                }
            }
        } else {
            declined.push(DeclinedAmbiguity { arc, s: s0, e: e0, class: DeclinedClass::Band, lineage_class: lineage.map(|ev| ev.class), stub_dev, dense_bound: db });
            fevents.push(FallbackEvent { arc, s: s0, e: e0, reason: FallbackReason::SplitUnresolved, stop: ustop });
        }
    };
    if pts.len() == 2 {
        if unresolved {
            emit_unresolved_line(arc, base, base + 1, 0.0, lineage, fevents, astubs, declined);
        }
        spans.push(FitSpan { span: Span::Line { end: pts[1] }, arc, s: base, e: base + 1 });
        return;
    }
    // P1 line-first: measured straightness evidence under the raw-chain
    // silent-acceptance rule (raw_chord_dev): the RAW pre-RDP chain between
    // the chord endpoints must stay within t_line of the emitted chord
    // (derivation at the helper). Captured deviation <= t_line is a
    // necessary precondition (the captured points are a raw subset) and
    // gates the raw lookup's cost. This is POSITIVE evidence for Line -
    // straight-built sources stay straight (design rule); this is not
    // tol-only Line forcing, the deviation is measured per arc.
    {
        let a = pts[0];
        let b = pts[pts.len() - 1];
        let abx = b.x - a.x;
        let aby = b.y - a.y;
        let l = abx.hypot(aby);
        if l > 0.0 {
            let mut dev = 0.0f64;
            for p in &pts[1..pts.len() - 1] {
                let d = (abx * (p.y - a.y) - aby * (p.x - a.x)).abs() / l;
                dev = dev.max(d);
            }
            // r297-REV (chief design): an UNRESOLVED band window (dev > db)
            // must not take the line-first accept - it falls through to the
            // normal fit/split machinery (tangents, fit_fn, Fitted/dense/
            // split/SU arms) instead of a bespoke fit copy. In-band rows and
            // all non-lineage windows are untouched.
            if dev <= t_line && raw_chord_dev(a, b).unwrap_or(dev) <= t_line && !(unresolved && dev > db) {
                if unresolved {
                    emit_unresolved_line(arc, base, base + pts.len() - 1, dev, lineage, fevents, astubs, declined);
                }
                spans.push(FitSpan { span: Span::Line { end: b }, arc, s: base, e: base + pts.len() - 1 });
                return;
            }
        }
    }
    // Depth ceiling derived from the arc's own sample count, not a literal:
    // a split's two children share the boundary sample (sizes sum to m+1), so
    // the longest possible root-to-leaf chain peels one sample per level and
    // reaches depth n-2. Past that there is nothing left to split; the
    // operative early stop is the sub-grid guard at the split sites below.
    if depth > depth_cap {
        // honest fallback: polyline remainder
        *fb = true;
        for (i, p) in pts[1..].iter().enumerate() {
            fevents.push(FallbackEvent { arc, s: base + i, e: base + i + 1, reason: FallbackReason::DepthLimit, stop: None });
            spans.push(FitSpan { span: Span::Line { end: *p }, arc, s: base + i, e: base + i + 1 });
        }
        return;
    }
    let (lt_est, rt_est) = match windowed_chord_tangents(pts) {
        Some(t) => t,
        None => {
            // degenerate chord: tangents undefined -> polyline fallback
            *fb = true;
            for (i, p) in pts[1..].iter().enumerate() {
                fevents.push(FallbackEvent { arc, s: base + i, e: base + i + 1, reason: FallbackReason::DegenerateTangents, stop: None });
                spans.push(FitSpan { span: Span::Line { end: *p }, arc, s: base + i, e: base + i + 1 });
            }
            return;
        }
    };
    // D1: forced axis tangents at extremum-split ends override the
    // windowed estimates; handles are then recomputed by the solve.
    // The KNI_NO_FORCE switch was removed: forced tangents
    // are the only behavior (the unforced path is the kinked output measured
    // and eliminated); git history keeps the A/B.
    let lt = lt_force.unwrap_or(lt_est);
    let rt = rt_force.unwrap_or(rt_est);
    let outcome = fit_fn(pts, lt, rt, policy);
    if std::env::var("KNI_DEBUG3").is_ok() {
        let kind = match &outcome {
            FitOutcome::Fitted { .. } => "Fitted",
            FitOutcome::SplitUnresolved { .. } => "SplitUnresolved",
            FitOutcome::InvalidInput => "InvalidInput",
        };
        eprintln!("DBG3 arc {} base {} len {} lt=({:.2},{:.2}) rt=({:.2},{:.2}) forced=({},{}): {}", arc, base, pts.len(), lt.x, lt.y, rt.x, rt.y, lt_force.is_some(), rt_force.is_some(), kind);
    }
    let budget_exhausted = matches!(
        &outcome,
        FitOutcome::SplitUnresolved { stop: Some(crate::cubic_fit::RefitStop::BudgetExhausted), .. }
    );
    match outcome {
        FitOutcome::Fitted { controls, .. } if plausible(pts, &controls) => {
            let (exc, hint) = dense_gate(&controls, pts);
            if std::env::var("KNI_DEBUG2").is_ok() {
                eprintln!("DBG2 arc {} base {} len {}: fitted exc={:.2} db={:.2} {}", arc, base, pts.len(), exc, db, if exc<=db {"OK"} else {"SPLIT"});
            }
            if exc <= db {
                spans.push(FitSpan {
                    span: Span::Cubic {
                        control_one: controls[1],
                        control_two: controls[2],
                        end: controls[3],
                    },
                    arc, s: base, e: base + pts.len() - 1,
                });
            } else {
                // Sub-grid typed stop: the dense gate demands a split but the
                // span's whole sample extent fits inside one acquisition
                // lattice cell (bbox, never endpoint chord: closed arcs
                // return to their start). Subdivision cannot manufacture
                // evidence the source does not carry (see SubGridSpan): stop
                // as one typed Line instead of grinding into the lattice.
                if sub_grid_extent(pts, grid) {
                    *fb = true;
                    fevents.push(FallbackEvent { arc, s: base, e: base + pts.len() - 1, reason: FallbackReason::SubGridSpan, stop: None });
                    let b = pts[pts.len() - 1];
                    spans.push(FitSpan { span: Span::Line { end: b }, arc, s: base, e: base + pts.len() - 1 });
                    return;
                }
                // argmax split: divide at the offending source feature; clamp
                // so both halves keep >= 2 points, midpoint if degenerate.
                let k = if hint >= 1 && hint <= pts.len() - 2 { hint } else { pts.len() / 2 };
                // Extremum replace: when a smooth extremum sits
                // near the adaptive split point, the extremum REPLACES it -
                // same split count, node at the exact extremum, axis-aligned
                // forced tangents on both children, handles recomputed.
                let (k, jt) = match nearest_extremum(pts, k, grid) {
                    Some((ei, tdir)) if ei != k => (ei, Some(tdir)),
                    _ => (k, split_tangent(pts, k)),
                };
                let back = jt.map(|t| Point { x: -t.x, y: -t.y });
                fit_gated(&pts[..=k], policy, spans, depth + 1, fb, db, t_line, grid, depth_cap, arc, base, lt_force, back, unresolved, ustop, fevents, astubs, lineage, declined, fit_fn);
                fit_gated(&pts[k..], policy, spans, depth + 1, fb, db, t_line, grid, depth_cap, arc, base + k, jt, rt_force, unresolved, ustop, fevents, astubs, lineage, declined, fit_fn);
            }
        }
        _ => {
            // r288: the producer outcome's refit stop rides down to every span
            // that bottoms out unresolved below this split; outcomes without a
            // refit-loop stop (InvalidInput) carry None.
            let out_stop = match &outcome {
                FitOutcome::SplitUnresolved { stop, .. } => *stop,
                _ => None,
            };
            // Sub-grid typed stop, same derivation as the dense-gate branch:
            // the fit failed AND the span fits inside one acquisition lattice
            // cell - further subdivision cannot certify anything measurable.
            if sub_grid_extent(pts, grid) {
                *fb = true;
                fevents.push(FallbackEvent { arc, s: base, e: base + pts.len() - 1, reason: FallbackReason::SubGridSpan, stop: None });
                let b = pts[pts.len() - 1];
                spans.push(FitSpan { span: Span::Line { end: b }, arc, s: base, e: base + pts.len() - 1 });
                return;
            }
            // A-PRIME lineage classification (BudgetExhausted only; every
            // other failure stop keeps the inherited lineage, fitting spans
            // never see this). The parent's class evidence is measured ONCE
            // here: dominant vertex per the sharp-turn convention
            // (sharp_turn_rescue, single source) plus both leg sagittas
            // against the dense bound (line-plausibility at the lattice's
            // own resolving power). The evidence rides the split subtree;
            // the typed write itself happens only at unresolved Line
            // bottom-outs whose OWN deviation also stays within the bound
            // (two-part gate, see emit_unresolved_line). When a vertex is
            // measured the split lands ON it: not to chase cubics (a
            // measured dead arm) but to give both legs clean, separately
            // judgable stubs.
            let lineage = if budget_exhausted {
                match sharp_turn_rescue(pts, t_line) {
                    Some(bi) => {
                        let lin = chord_max_dev(&pts[..=bi], pts[0], pts[bi]);
                        let lout = chord_max_dev(&pts[bi..], pts[bi], pts[pts.len() - 1]);
                        let class = if lin <= db && lout <= db { AmbiguityClass::CornerLeaning } else { AmbiguityClass::RoundAmbiguous };
                        let ev = LineageEvidence { class, parent_arc: arc, parent_s: base, parent_e: base + pts.len() - 1, vertex: Some(bi), leg_in_sagitta: lin, leg_out_sagitta: lout };
                        // MEASURED on 00C9: landing the split ON the vertex
                        // costs cubics (6 -> 2 on ring0) even for
                        // corner-leaning arcs - the forced vertex tangent
                        // misfits children the generic split fits. The cubic
                        // invariant is the harder constraint, so the split
                        // stays generic and the lineage changes RECORDS ONLY:
                        // geometry is byte-identical to the unpatched engine
                        // by construction; only unresolved Line bottom-outs
                        // carry the typed write.
                        Some(ev)
                    }
                    None => {
                        Some(LineageEvidence { class: AmbiguityClass::TrulyAmbiguous, parent_arc: arc, parent_s: base, parent_e: base + pts.len() - 1, vertex: None, leg_in_sagitta: 0.0, leg_out_sagitta: 0.0 })
                    }
                }
            } else {
                lineage
            };
            let mid = pts.len() / 2;
            let (mid, jt) = match nearest_extremum(pts, mid, grid) {
                Some((ei, tdir)) if ei != mid => (ei, Some(tdir)),
                _ => (mid, split_tangent(pts, mid)),
            };
            let back = jt.map(|t| Point { x: -t.x, y: -t.y });
            fit_gated(&pts[..=mid], policy, spans, depth + 1, fb, db, t_line, grid, depth_cap, arc, base, lt_force, back, true, out_stop, fevents, astubs, lineage, declined, fit_fn);
            fit_gated(&pts[mid..], policy, spans, depth + 1, fb, db, t_line, grid, depth_cap, arc, base + mid, jt, rt_force, true, out_stop, fevents, astubs, lineage, declined, fit_fn);
        }
    }
}

/// TLS line over a point set: centroid + principal direction (closed-form
/// largest-eigenvalue eigenvector of the 2x2 covariance; same estimator as
/// tls_dir, with the centroid kept).
fn tls_line_full(p: &[Point]) -> Option<(Point, Point)> {
    if p.len() < 2 {
        return None;
    }
    let (mut mx, mut my) = (0.0, 0.0);
    for q in p {
        mx += q.x;
        my += q.y;
    }
    mx /= p.len() as f64;
    my /= p.len() as f64;
    let (mut sxx, mut sxy, mut syy) = (0.0, 0.0, 0.0);
    for q in p {
        let dx = q.x - mx;
        let dy = q.y - my;
        sxx += dx * dx;
        sxy += dx * dy;
        syy += dy * dy;
    }
    if !(sxx + syy > 0.0) {
        return None;
    }
    let th = 0.5 * (2.0 * sxy).atan2(sxx - syy);
    Some((Point { x: mx, y: my }, Point { x: th.cos(), y: th.sin() }))
}

/// Max perpendicular deviation of points from the chord a->b.
fn chord_max_dev(pts: &[Point], a: Point, b: Point) -> f64 {
    let abx = b.x - a.x;
    let aby = b.y - a.y;
    let l = abx.hypot(aby);
    if l == 0.0 {
        return pts.iter().map(|p| (p.x - a.x).hypot(p.y - a.y)).fold(0.0, f64::max);
    }
    pts.iter().map(|p| (abx * (p.y - a.y) - aby * (p.x - a.x)).abs() / l).fold(0.0, f64::max)
}


fn pt_seg_d2(p: Point, a: Point, b: Point) -> f64 {
    let (vx, vy) = (b.x - a.x, b.y - a.y);
    let l2 = vx * vx + vy * vy;
    let t = if l2 > 0.0 { (((p.x - a.x) * vx + (p.y - a.y) * vy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    let (qx, qy) = (a.x + t * vx, a.y + t * vy);
    (p.x - qx) * (p.x - qx) + (p.y - qy) * (p.y - qy)
}

/// (sum of squared, max squared) distance of source points to a span.
fn span_dev(src: &[Point], start: Point, sp: &Span) -> (f64, f64) {
    let mut poly: Vec<Point> = Vec::new();
    match sp {
        Span::Line { end } => { poly.push(start); poly.push(*end); }
        Span::Cubic { control_one, control_two, end } => {
            for i in 0..=32 {
                poly.push(cubic_eval(start, *control_one, *control_two, *end, i as f64 / 32.0));
            }
        }
    }
    let (mut sum, mut mx) = (0.0f64, 0.0f64);
    for p in src {
        let mut d = f64::INFINITY;
        for w in poly.windows(2) { d = d.min(pt_seg_d2(*p, w[0], w[1])); }
        sum += d;
        mx = mx.max(d);
    }
    (sum, mx)
}

fn n_extrema(start: Point, sp: &Span) -> usize {
    match sp { Span::Line { .. } => 0, Span::Cubic { control_one, control_two, end } => cubic_extrema_ts_eps(start, *control_one, *control_two, *end, 1e-4).len() + 100 * cubic_extrema_ts(start, *control_one, *control_two, *end).len() }
}

fn move_end(sp: &Span, d: Point) -> Span {
    match sp {
        Span::Line { end } => Span::Line { end: Point { x: end.x + d.x, y: end.y + d.y } },
        Span::Cubic { control_one, control_two, end } => Span::Cubic {
            control_one: *control_one,
            control_two: Point { x: control_two.x + d.x, y: control_two.y + d.y },
            end: Point { x: end.x + d.x, y: end.y + d.y },
        },
    }
}

fn rd_span(sp: &Span) -> Span {
    match sp {
        Span::Line { end } => Span::Line { end: rd(*end) },
        Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: rd(*control_one), control_two: rd(*control_two), end: rd(*end) },
    }
}

fn shift_start(sp: &Span, d: Point) -> Span {
    match sp {
        Span::Line { end } => Span::Line { end: *end },
        Span::Cubic { control_one, control_two, end } => Span::Cubic {
            control_one: Point { x: control_one.x + d.x, y: control_one.y + d.y },
            control_two: *control_two, end: *end },
    }
}

/// Junction placement solve: each interior junction node is relocated, on the output
/// integer lattice (the ring is rounded to integer font units downstream, so sub-pixel
/// search on unrounded geometry is not meaningful), within `rad` of its rounded position,
/// to the lattice point minimising the summed squared source deviation of its two adjacent
/// spans, evaluated on the ROUNDED spans (potrace adjust_vertices analogue; direct search so
/// Line-Cubic and Cubic-Cubic junctions are covered). Cubic handles translate with their
/// node (tangent preserved). Accept only on relative gain > `gain` with no increase of max
/// deviation beyond max(old, t_line^2), and no new interior cubic extremum (so the post-fit
/// extrema split cannot add nodes).
fn refine_junction_qf(arcs: &[Vec<Point>], fs: &mut [FitSpan], start: Point, t_line: f64, rad: f64, gain: f64) -> usize {
    let ns = fs.len();
    let mut n = 0;
    let r = rad.ceil() as i32;
    for j in 0..ns.saturating_sub(1) {
        let k = j + 1;
        if fs[j].e + 1 - fs[j].s < 3 || fs[k].e + 1 - fs[k].s < 3 { continue; }
        let src1 = &arcs[fs[j].arc][fs[j].s..=fs[j].e];
        let src2 = &arcs[fs[k].arc][fs[k].s..=fs[k].e];
        let prev = rd(if j == 0 { start } else { match &fs[j - 1].span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end } });
        // Line-Line junctions are owned by refine_line_junctions (TLS intersection); short corner spans
        // pushed by a squared-deviation search regressed thin glyphs (uni0027 -0.0206)
        if matches!(fs[j].span, Span::Line { .. }) && matches!(fs[k].span, Span::Line { .. }) { continue; }
        let sj = rd_span(&fs[j].span);
        let sk = rd_span(&fs[k].span);
        let node = match &sj { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
        let (a0, am0) = span_dev(src1, prev, &sj);
        let (b0, bm0) = span_dev(src2, node, &sk);
        let base = a0 + b0;
        let e1_0 = n_extrema(prev, &sj);
        let e2_0 = n_extrema(node, &sk);
        let lim1 = am0.max(t_line * t_line);
        let lim2 = bm0.max(t_line * t_line);
        let mut best = (base, Point { x: 0.0, y: 0.0 });
        for iy in -r..=r {
            for ix in -r..=r {
                if (ix == 0 && iy == 0) || ((ix * ix + iy * iy) as f64).sqrt() > rad + 1e-9 { continue; }
                let d = Point { x: ix as f64, y: iy as f64 };
                let nn = Point { x: node.x + d.x, y: node.y + d.y };
                let s1 = move_end(&sj, d);
                let s2 = shift_start(&sk, d);
                let (a, am) = span_dev(src1, prev, &s1);
                let (b, bm) = span_dev(src2, nn, &s2);
                if am > lim1 || bm > lim2 { continue; }
                if n_extrema(prev, &s1) > e1_0 || n_extrema(nn, &s2) > e2_0 { continue; }
                if a + b < best.0 { best = (a + b, d); }
            }
        }
        if best.0 < base * (1.0 - gain) && (best.1.x != 0.0 || best.1.y != 0.0) {
            let d = best.1;
            fs[j].span = move_end(&sj, d);
            fs[k].span = shift_start(&sk, d);
            n += 1;
        }
    }
    n
}

/// P2 corner placement
/// (POST-FIT variant): with line-first fitting, adjacent Line spans meet at
/// line-line junctions; the shared node's position is refined to the
/// INTERSECTION of the two spans' TLS lines, each fitted over the span's
/// own recorded source points. Post-fit placement is load-bearing: the
/// lines being intersected are the FITTED span lines (a terminal cap span
/// sits between converging taper edges), never raw flanking contour runs -
/// a pre-fit variant of this refinement overshot tapered terminals by
/// ~1px and regressed the canonical-g tail IoU 0.9919 -> 0.9653
/// (measured; reverted).
/// Evidence gates (ambiguous evidence abstains):
///  - both adjacent spans Line, each with >= 3 recorded source points;
///  - turn between the TLS directions >= 25 deg (the min_turn_deg parameter);
///  - intersection within 1.5*t_line of the current node position;
///  - post-move re-validation against source (P0 regression-bar pattern):
///    both spans' source points must stay within t_line of the NEW chord.
/// Line-Cubic and Cubic-Cubic nodes are untouched; span structure, node
/// order and closure are preserved (the wrap node moves start+last-end
/// together).
fn refine_line_junctions(arcs: &[Vec<Point>], fs: &mut [FitSpan], start: &mut Point, t_line: f64) -> usize {
    let ns = fs.len();
    if ns < 2 {
        return 0;
    }
    let mut refined = 0;
    for j in 0..ns {
        let k = (j + 1) % ns;
        let node = match &fs[j].span {
            Span::Line { end } => *end,
            _ => continue,
        };
        if !matches!(fs[k].span, Span::Line { .. }) {
            continue;
        }
        let (a1, s1, e1) = (fs[j].arc, fs[j].s, fs[j].e);
        let (a2, s2, e2) = (fs[k].arc, fs[k].s, fs[k].e);
        if e1 - s1 + 1 < 3 || e2 - s2 + 1 < 3 {
            continue;
        }
        let src1 = &arcs[a1][s1..=e1];
        let src2 = &arcs[a2][s2..=e2];
        let (c1, d1) = match tls_line_full(src1) { Some(x) => x, None => continue };
        let (c2, d2) = match tls_line_full(src2) { Some(x) => x, None => continue };
        let cos_a = (d1.x * d2.x + d1.y * d2.y).abs().clamp(-1.0, 1.0);
        if cos_a.acos() < 25.0f64.to_radians() {
            continue;
        }
        let cross = d1.x * d2.y - d1.y * d2.x;
        let rx = c2.x - c1.x;
        let ry = c2.y - c1.y;
        let t = (rx * d2.y - ry * d2.x) / cross;
        let ix = c1.x + t * d1.x;
        let iy = c1.y + t * d1.y;
        if !ix.is_finite() || !iy.is_finite() {
            continue;
        }
        let newn = Point { x: ix, y: iy };
        if (ix - node.x).hypot(iy - node.y) > crate::thresholds::T_LINE_SLACK * t_line {
            continue;
        }
        // far ends of the two spans: span j runs [prev_end -> node],
        // span k runs [node -> next_end = its own end].
        let prev_end = if j == 0 { *start } else {
            match &fs[j - 1].span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end }
        };
        let next_end = match &fs[k].span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
        if k == 0 && node != *start {
            // wrap junction with closure still pending: no single node yet
            continue;
        }
        if chord_max_dev(src1, prev_end, newn) > t_line {
            continue;
        }
        if chord_max_dev(src2, newn, next_end) > t_line {
            continue;
        }
        fs[j].span = Span::Line { end: newn };
        if k == 0 {
            *start = newn;
        }
        refined += 1;
    }
    refined
}



/// Extremum nodes: smooth x/y extrema of an arc get nodes at
/// the EXACT extremum sample with axis-aligned (90 deg) tangents, horizontal
/// at y-extrema, vertical at x-extrema. Extrema splits REPLACE
/// curvature-adaptive splits at those positions (they are computed before
/// any error-driven split), and the handles are recomputed against the new
/// node positions by the normal solve (never carried over). Detection is
/// windowed and swing-gated so 1-px staircase wobble never counts: a side
/// must accumulate at least MIN_SWING font units of coordinate travel.
const EXTREMA_WIN: usize = 3;

/// Returns (sample_index, axis_tangent_direction_of_travel) for each smooth
/// extremum in the interior of an open arc, in arc order.
/// Typed ring-closure contract for the extrema scan: Open arcs are
/// corner-delimited slices (endpoints are the arc's boundary landmarks; the
/// scan never crosses them). Closed rings are full cyclic contours whose seam
/// is an arbitrary tracing index - the scan wraps exactly once around the ring
/// (bounded by N samples per direction) so a plateau crossing the seam is
/// found exactly once. Never inferred from endpoint coordinates.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum RingClosure {
    Open,
    Closed,
}

fn extrema_splits(pts: &[Point], grid: f64) -> Vec<(usize, Point)> {
    extrema_splits_typed(pts, RingClosure::Open, grid)
}

/// Cyclic variant for true closed rings (no duplicated endpoint). Same
/// plateau-aware rules as the open scan; indices are modulo N, every scan is
/// bounded by N steps, and dedupe also closes across the seam so one
/// seam-crossing plateau emits one landmark with a deterministic center.
fn extrema_splits_cyclic(pts: &[Point], grid: f64) -> Vec<(usize, Point)> {
    let n = pts.len();
    if n < 3 {
        return vec![];
    }
    let w = EXTREMA_WIN;
    let hp = extremum_window_radius(pts, grid);
    let val = |i: usize, axis: usize| {
        let p = &pts[i % n];
        if axis == 0 { p.x } else { p.y }
    };
    let mut cand: Vec<(usize, Point, f64)> = vec![];
    for i in 0..n {
        for axis in 0..2 {
            let v = val(i, axis);
            let mut j = i;
            let mut steps = 0usize;
            while steps < n && val((j + n - 1) % n, axis) == v {
                j = (j + n - 1) % n;
                steps += 1;
            }
            if steps == n {
                continue; // axis constant around the whole ring
            }
            let dl = (j + n - 1) % n; // first differing sample, left
            let jl = walk_reach(pts, dl, -1, hp, true);
            let pl = v - val(jl, axis);
            let mut k = i;
            let mut steps = 0usize;
            while steps < n && val((k + 1) % n, axis) == v {
                k = (k + 1) % n;
                steps += 1;
            }
            if steps == n {
                continue; // axis constant around the whole ring
            }
            let dr = (k + 1) % n; // first differing sample, right
            let kr = walk_reach(pts, dr, 1, hp, true);
            let pr = val(kr, axis) - v;
            if pl == 0.0 || pr == 0.0 || pl.signum() == pr.signum() {
                continue;
            }
            let swing = pl.abs().min(pr.abs());
            if swing < grid {
                continue; // below one lattice step: not measurable evidence
            }
            // plateau-center snap over the extended window, cyclic order from jl
            let want_max = pl > 0.0;
            let span = (kr + n - jl) % n;
            let mut bv = v;
            for off in 0..=span {
                let vm = val((jl + off) % n, axis);
                if (want_max && vm > bv) || (!want_max && vm < bv) {
                    bv = vm;
                }
            }
            let mut lo: Option<usize> = None;
            let mut hi = 0usize;
            for off in 0..=span {
                if val((jl + off) % n, axis) == bv {
                    if lo.is_none() {
                        lo = Some(off);
                    }
                    hi = off;
                }
            }
            let lo = match lo {
                Some(l) => l,
                None => continue,
            };
            let bi = (jl + (lo + hi) / 2) % n;
            let t = if axis == 0 {
                let dy_post = val((bi + w) % n, 1) - val(bi, 1);
                let dy_pre = val(bi, 1) - val((bi + n - w) % n, 1);
                let dy = if dy_post != 0.0 { dy_post } else { dy_pre };
                if dy == 0.0 {
                    continue;
                }
                Point { x: 0.0, y: dy.signum() }
            } else {
                let dx_post = val((bi + w) % n, 0) - val(bi, 0);
                let dx_pre = val(bi, 0) - val((bi + n - w) % n, 0);
                let dx = if dx_post != 0.0 { dx_post } else { dx_pre };
                if dx == 0.0 {
                    continue;
                }
                Point { x: dx.signum(), y: 0.0 }
            };
            cand.push((bi, t, swing));
        }
    }
    cand.sort_by_key(|c| c.0);
    let mut kept: Vec<(usize, Point, f64)> = vec![];
    for c in cand.into_iter() {
        if let Some(last) = kept.last() {
            if c.0 <= last.0 + 2 * w {
                if c.2 > last.2 {
                    *kept.last_mut().unwrap() = c;
                }
                continue;
            }
        }
        kept.push(c);
    }
    // seam closure of dedupe: first/last within 2w cyclically = one plateau
    if kept.len() > 1 {
        let first = kept[0];
        let last = *kept.last().unwrap();
        if (first.0 + n - last.0) % n <= 2 * w {
            if last.2 > first.2 {
                kept[0] = last;
            }
            kept.pop();
        }
    }
    kept.into_iter().map(|(i, t, _)| (i, t)).collect()
}


/// Circumradius of the arc from its own chord c and measured sagitta s:
/// R = (s^2 + (c/2)^2) / (2s). Exact for circular arcs, first-order correct
/// for smooth ones. None when the chord vanishes (closed loop) or the arc
/// carries no measurable bend (s == 0).
fn circumradius_chord_sagitta(pts: &[Point]) -> Option<f64> {
    let n = pts.len();
    if n < 3 {
        return None;
    }
    let a = pts[0];
    let b = pts[n - 1];
    let (cx, cy) = (b.x - a.x, b.y - a.y);
    let c = cx.hypot(cy);
    if c == 0.0 {
        return None;
    }
    let mut s_max = 0.0f64;
    for p in &pts[1..n - 1] {
        let d = (cx * (p.y - a.y) - cy * (p.x - a.x)).abs() / c;
        s_max = s_max.max(d);
    }
    if s_max == 0.0 {
        return None;
    }
    Some((s_max * s_max + c * c / 4.0) / (2.0 * s_max))
}

/// Extremum measurement window derivation (EXTREMA_MIN_SWING fix).
///
/// Threshold: one lattice step g. Two samples whose true coordinates differ
/// by less than g can quantize to the SAME lattice value, so a coordinate
/// difference below g is not measurable evidence; a difference of g is the
/// smallest measurable swing. The retired 3.0 literal had no acquisition
/// basis and rejected real extremum plateaus whose window swing was 1..3 fu
/// (measured: r=128 half-circle plateau, swing 1 fu undetected).
///
/// Window: the slope is measured one plateau half-length beyond the plateau
/// edge. Plateau half-length hp = sqrt(R*g) (sagitta h^2/(2R) < g/2
/// derivation). At distance hp beyond the edge the true axis drop from the
/// extremum is ((2hp)^2 - hp^2)/(2R) = 3g/2 >= g: the swing there is always
/// measurable when R is the arc's own radius. When the arc carries no bend
/// evidence (circumradius unavailable), hp falls back to the historical
/// (EXTREMA_WIN-1)-sample window expressed in chord length.
fn extremum_window_radius(pts: &[Point], grid: f64) -> f64 {
    match circumradius_chord_sagitta(pts) {
        Some(r) => (r * grid).sqrt(),
        None => {
            let n = pts.len();
            let total: f64 = (0..n - 1).map(|i| (pts[i + 1].x - pts[i].x).hypot(pts[i + 1].y - pts[i].y)).sum();
            let ds = if n > 1 { total / (n - 1) as f64 } else { 0.0 };
            (EXTREMA_WIN - 1) as f64 * ds
        }
    }
}

/// Walk from `start` away from the plateau (direction -1 or +1, cyclic when
/// `cyclic`) until the accumulated chord length reaches `reach` or the chain
/// ends; returns the reached index. Bounded by n steps.
fn walk_reach(pts: &[Point], start: usize, dir: i32, reach: f64, cyclic: bool) -> usize {
    let n = pts.len();
    let mut i = start as i64;
    let mut acc = 0.0f64;
    let mut steps = 0usize;
    loop {
        let nxt = if dir > 0 { i + 1 } else { i - 1 };
        let nxt = if cyclic { nxt.rem_euclid(n as i64) } else { nxt };
        if !cyclic && (nxt < 0 || nxt >= n as i64) {
            return i as usize;
        }
        if cyclic && steps >= n {
            return i as usize;
        }
        let (u, v) = (pts[i as usize], pts[nxt as usize]);
        acc += (v.x - u.x).hypot(v.y - u.y);
        i = nxt;
        steps += 1;
        if acc >= reach {
            return i as usize;
        }
    }
}

fn extrema_splits_typed(pts: &[Point], closure: RingClosure, grid: f64) -> Vec<(usize, Point)> {
    if closure == RingClosure::Closed {
        return extrema_splits_cyclic(pts, grid);
    }
    let n = pts.len();
    if n < 2 * EXTREMA_WIN + 3 {
        return vec![];
    }
    let w = EXTREMA_WIN;
    let hp = extremum_window_radius(pts, grid);
    let extremum = |p: &Point, axis: usize| if axis == 0 { p.x } else { p.y };
    let mut cand: Vec<(usize, Point, f64)> = vec![]; // idx, tangent, swing
    for i in w..n - w {
        for axis in 0..2 {
            // Plateau-aware windowed slope: a raster extremum is a zero-delta
            // run (plateau) that can be LONGER than the window. Scan to the
            // plateau edges first (bounded by the arc ends: finite index
            // loops, no wrap), then measure the windowed slope from the first
            // samples past each edge. Same-sign slopes = straight plateau,
            // not an extremum. Off-plateau i anchors exactly as before
            // (j = i, jl = i - w).
            let v = extremum(&pts[i], axis);
            let mut j = i;
            while j > 0 && extremum(&pts[j - 1], axis) == v {
                j -= 1;
            }
            if j == 0 {
                continue; // constant to the arc start: no left slope evidence
            }
            let jl = walk_reach(pts, j - 1, -1, hp, false);
            let pl = v - extremum(&pts[jl], axis);
            let mut k = i;
            while k + 1 < n && extremum(&pts[k + 1], axis) == v {
                k += 1;
            }
            if k + 1 >= n {
                continue; // constant to the arc end: no right slope evidence
            }
            let kr = walk_reach(pts, k + 1, 1, hp, false);
            let pr = extremum(&pts[kr], axis) - v;
            if pl == 0.0 || pr == 0.0 || pl.signum() == pr.signum() {
                continue;
            }
            let swing = pl.abs().min(pr.abs());
            if swing < grid {
                continue; // below one lattice step: not measurable evidence
            }
            // snap to the true extremum inside the extended window; raster
            // extrema are PLATEAUS of equal-valued samples - take the plateau
            // center (the axis tangent is only geometrically exact there)
            let want_max = pl > 0.0;
            let mut bv = extremum(&pts[i], axis);
            for m in jl..=kr {
                let vm = extremum(&pts[m], axis);
                if (want_max && vm > bv) || (!want_max && vm < bv) {
                    bv = vm;
                }
            }
            let mut lo = i;
            let mut hi = i;
            for m in jl..=kr {
                if extremum(&pts[m], axis) == bv {
                    lo = lo.min(m);
                    hi = hi.max(m);
                }
            }
            let bi = (lo + hi) / 2;
            // travel direction at the node, along the OTHER axis. Use the
            // WINDOWED post-node delta (plateau neighbors can read (0,0) and
            // the immediate next sample can sit on the plateau); fall back
            // to the pre-node window delta, which has the same sign through
            // a smooth extremum.
            let t = if axis == 0 {
                // x-extremum: tangent vertical, sign = post-node travel in y
                let dy_post = pts[(bi + w).min(n - 1)].y - pts[bi].y;
                let dy_pre = pts[bi].y - pts[bi.saturating_sub(w)].y;
                let dy = if dy_post != 0.0 { dy_post } else { dy_pre };
                if dy == 0.0 { continue; }
                Point { x: 0.0, y: dy.signum() }
            } else {
                let dx_post = pts[(bi + w).min(n - 1)].x - pts[bi].x;
                let dx_pre = pts[bi].x - pts[bi.saturating_sub(w)].x;
                let dx = if dx_post != 0.0 { dx_post } else { dx_pre };
                if dx == 0.0 { continue; }
                Point { x: dx.signum(), y: 0.0 }
            };
            cand.push((bi, t, swing));
        }
    }
    // dedupe: keep the strongest swing within 2w of a kept candidate
    cand.sort_by_key(|c| c.0);
    let mut kept: Vec<(usize, Point, f64)> = vec![];
    for c in cand.into_iter() {
        if let Some(last) = kept.last() {
            if c.0 <= last.0 + 2 * w {
                if c.2 > last.2 {
                    *kept.last_mut().unwrap() = c;
                }
                continue;
            }
        }
        kept.push(c);
    }
    kept.into_iter().map(|(i, t, _)| (i, t)).collect()
}


/// D1 helper: the extremum nearest to a proposed adaptive split point,
/// within a reach of one quarter of the arc (so a split keeps its error-
/// reducing purpose). Returns (index, axis travel tangent).
fn nearest_extremum(pts: &[Point], k: usize, grid: f64) -> Option<(usize, Point)> {
    let ex = extrema_splits(pts, grid);
    if ex.is_empty() {
        return None;
    }
    let reach = (pts.len() / 4).max(EXTREMA_WIN * 2);
    ex.into_iter()
        .filter(|(i, _)| *i >= 2 && *i <= pts.len() - 3)
        .filter(|(i, _)| i.abs_diff(k) <= reach)
        .min_by_key(|(i, _)| i.abs_diff(k))
}

/// Measurement records for the PN-3 corner resplit (behavior-neutral:
/// thread-local, never consulted by the fit logic, never rendered into any
/// output). Benches read them to classify accepted corner splits as true
/// G1 corners vs raster staircase artifacts.
#[derive(Clone, Debug)]
pub struct CornerSplitRecord {
    pub ring: usize,
    pub arc: usize,
    pub arc_samples: usize,
    pub depth: usize,
    pub split_index: usize,
    /// k=1 segment turn at the split vertex, degrees
    pub turn_deg: f64,
    /// combined same-sign adjacent-pair turn, degrees (0 when not applicable)
    pub pair_turn_deg: f64,
    /// true when the split vertex reached the 45-deg gate only via the pair rule
    pub via_pair_rule: bool,
    pub left_leg_chord: f64,
    pub right_leg_chord: f64,
}
#[derive(Clone, Debug)]
pub struct CornerAdoptionRecord {
    pub ring: usize,
    pub arc: usize,
    pub arc_samples: usize,
    pub legs: usize,
    /// ledger events: whole-arc damped refit (r), corner-resplit path (c),
    /// original fit (new). corner_adopted = c < r; rescue_adopted = final < new.
    pub r_events: usize,
    pub c_events: usize,
    pub new_events: usize,
    pub corner_adopted: bool,
    pub rescue_adopted: bool,
}
thread_local! {
    static CORNER_SPLIT_RECORDS: std::cell::RefCell<Vec<CornerSplitRecord>> = const { std::cell::RefCell::new(Vec::new()) };
    static CORNER_ADOPTION_RECORDS: std::cell::RefCell<Vec<CornerAdoptionRecord>> = const { std::cell::RefCell::new(Vec::new()) };
    /// (ring, arc) identity of the resplit site currently recording; set by the
    /// fit path per ring / per arc (measurement only, no fit behaviour).
    static CURRENT_CORNER_SITE: std::cell::Cell<(usize, usize)> = std::cell::Cell::new((usize::MAX, usize::MAX));
}
/// Read and reset both record streams. Measurement only.
/// measurement-only site setters (RAW_RING precedent); no fit behaviour.
pub fn corner_record_site_set_ring(ring: usize) { CURRENT_CORNER_SITE.with(|c| c.set((ring, usize::MAX))); }
pub fn corner_record_site_set_arc(arc: usize) { CURRENT_CORNER_SITE.with(|c| { let (r, _) = c.get(); c.set((r, arc)); }); }
pub fn take_corner_resplit_records() -> (Vec<CornerSplitRecord>, Vec<CornerAdoptionRecord>) {
    let a = CORNER_SPLIT_RECORDS.with(|v| std::mem::take(&mut *v.borrow_mut()));
    let b = CORNER_ADOPTION_RECORDS.with(|v| std::mem::take(&mut *v.borrow_mut()));
    (a, b)
}

/// Rescue-pass corner detector (PN-3): a sharp turn spread over TWO adjacent
/// vertices escapes sharp_turn_rescue's single-vertex 45-deg gate (each step
/// reads <45 deg while the vertex PAIR turns ~90 deg; measured on Paul New
/// book-photo tiles, L-shaped arcs bottoming out as unresolved Lines). The
/// evidence reuses the module's own declared bounds: the turn is measured
/// between the two LEG CHORDS at the candidate corner (>= 45 deg, the
/// sharp-turn convention) and BOTH legs must read straight at the line-first
/// tolerance (chord_max_dev <= t_line). No new constants, no smoothing: the
/// split lands ON the measured vertex and the legs ship as what they
/// measure as (straight legs -> intentional Lines, the design's own
/// geometry). A smooth short arc does not qualify: its leg chords turn well
/// under the sharpness bound.
fn best_corner_split(arc: &[Point], t_line: f64) -> Option<usize> {
    let n = arc.len();
    if n < 3 {
        return None;
    }
    // n == 3 is the smallest corner case: one interior vertex, judged by the
    // single-vertex 45-deg gate below (the same bound sharp_turn_rescue
    // declares for spike triples); the adjacent-PAIR rule is inert here.

    for w in arc.windows(2) {
        if w[0].x == w[1].x && w[0].y == w[1].y {
            return None; // degenerate chords stay on the fallback path (same rule as sharp_turn_rescue)
        }
    }
    let whole_dev = chord_max_dev(arc, arc[0], arc[n - 1]);
    if whole_dev <= t_line {
        return None; // line evidence already (same gate as sharp_turn_rescue)
    }
    // k=1 segment turn at interior vertex i (same estimator as
    // sharp_turn_rescue's turn_at(i, 1)).
    let seg_turn = |i: usize| -> f64 {
        let p = arc[i - 1];
        let q = arc[i];
        let r = arc[i + 1];
        let v1 = (q.x - p.x, q.y - p.y);
        let v2 = (r.x - q.x, r.y - q.y);
        let l1 = v1.0.hypot(v1.1);
        let l2 = v2.0.hypot(v2.1);
        if l1 == 0.0 || l2 == 0.0 {
            return 0.0;
        }
        ((v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2)).clamp(-1.0, 1.0).acos().to_degrees()
    };
    let cross = |i: usize| -> f64 {
        let p = arc[i - 1];
        let q = arc[i];
        let r = arc[i + 1];
        (q.x - p.x) * (r.y - q.y) - (q.y - p.y) * (r.x - q.x)
    };
    // Gated split candidates: a single vertex turning >= 45 deg (the
    // module's declared sharpness bound), OR a same-sign adjacent vertex
    // PAIR whose combined turn reaches the same bound (the spread corner:
    // two ~45 deg steps the single-vertex gate misses). No new constants.
    let mut gated: Vec<usize> = Vec::new();
    for i in 1..n - 1 {
        if seg_turn(i) >= 45.0 {
            gated.push(i);
        }
    }
    for i in 1..n - 2 {
        if cross(i) * cross(i + 1) > 0.0 && seg_turn(i) + seg_turn(i + 1) >= 45.0 {
            gated.push(i);
            gated.push(i + 1);
        }
    }
    gated.sort_unstable();
    gated.dedup();
    // Rank gated candidates by measured straightness gain: the split whose
    // worse leg reads straightest. No whole-arc improvement requirement: on
    // a multi-corner arc (two corners share one arc) splitting ONE corner
    // can leave the other leg's deviation above the whole-arc chord's, so an
    // improvement gate rejects every candidate and the arc never splits.
    // Children that still read curved are re-judged by the recursion (and
    // fitted as curves there) - the resplit supplies corner STRUCTURE,
    // never forced Lines.
    let leg_dev = |k: usize| -> f64 {
        let left = &arc[..=k];
        let right = &arc[k..];
        let ldev = if left.len() <= 2 { 0.0 } else { chord_max_dev(left, left[0], left[left.len() - 1]) };
        let rdev = if right.len() <= 2 { 0.0 } else { chord_max_dev(right, right[0], right[right.len() - 1]) };
        ldev.max(rdev)
    };
    let mut best: Option<(f64, usize)> = None;
    for &k in &gated {
        let cost = leg_dev(k);
        best = match best {
            None => Some((cost, k)),
            Some((bc, bk)) => {
                if cost < bc || (cost == bc && k < bk) { Some((cost, k)) } else { Some((bc, bk)) }
            }
        };
    }
    best.map(|(_, k)| k)
}

/// Order-preserving recursive application of best_corner_split (same
/// iteration contract as rescue_in_order: leaves appended left-to-right,
/// honest depth cap).
fn corner_resplit(a: &[Point], t_line: f64, depth: usize, out: &mut Vec<Vec<Point>>) {
    if depth > 32 {
        out.push(a.to_vec());
        return;
    }
    match best_corner_split(a, t_line) {
        Some(k) => {
            // measurement only: recompute the estimator evidence for the chosen
            // vertex (identical formulas to best_corner_split's gates)
            let n = a.len();
            let seg_turn = |i: usize| -> f64 {
                let p = a[i - 1]; let q = a[i]; let r = a[i + 1];
                let v1 = (q.x - p.x, q.y - p.y); let v2 = (r.x - q.x, r.y - q.y);
                let l1 = v1.0.hypot(v1.1); let l2 = v2.0.hypot(v2.1);
                if l1 == 0.0 || l2 == 0.0 { return 0.0; }
                ((v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2)).clamp(-1.0, 1.0).acos().to_degrees()
            };
            let turn = seg_turn(k);
            let pair_turn = if k + 1 < n - 1 { seg_turn(k) + seg_turn(k + 1) } else { 0.0 };
            let chord = |x: &[Point]| (x.last().unwrap().x - x[0].x).hypot(x.last().unwrap().y - x[0].y);
            let (rec_ring, rec_arc) = CURRENT_CORNER_SITE.with(|c| c.get());
            CORNER_SPLIT_RECORDS.with(|v| v.borrow_mut().push(CornerSplitRecord {
                ring: rec_ring, arc: rec_arc,
                arc_samples: n, depth, split_index: k,
                turn_deg: turn, pair_turn_deg: pair_turn, via_pair_rule: turn < 45.0,
                left_leg_chord: chord(&a[..=k]), right_leg_chord: chord(&a[k..]),
            }));
            corner_resplit(&a[..=k], t_line, depth + 1, out);
            corner_resplit(&a[k..], t_line, depth + 1, out);
        }
        None => out.push(a.to_vec()),
    }
}

/// Rescue (candidate rule): a corner-free arc from the windowed
/// detector can still carry a sharp internal turn (measured on race-3: 6-pt
/// arcs with ~90 deg internal corners and 70-418 px chord deviation, missed
/// because the detector window/suppression merges dense corners). A sharp
/// local turn (k=1 vertex turn >= 45 deg) inside an arc that failed the line
/// test is STRUCTURE: split there and let both halves be re-judged. This is
/// turn-angle evidence, never tol-only line construction.
fn sharp_turn_rescue(arc: &[Point], t_line: f64) -> Option<usize> {
    // len 3 is the smallest arc with an interior point: a spike triple whose
    // middle point fails the chord test is corner evidence; a shallow smooth
    // triple reads a small turn angle and is left alone by the 45-deg gate.
    if arc.len() < 3 {
        return None;
    }
    // degenerate chords (duplicate consecutive points) stay on the existing
    // fallback path - rescue must not launder them into silent lines
    for w in arc.windows(2) {
        if w[0].x == w[1].x && w[0].y == w[1].y {
            return None;
        }
    }
    let a = arc[0];
    let b = arc[arc.len() - 1];
    if chord_max_dev(arc, a, b) <= t_line {
        return None; // line evidence already
    }
    // k=1 local turn AND k=2 windowed turn must BOTH be sharp: a staircase
    // wobble on a smooth curve turns sharply at k=1 but the k=2 window still
    // reads the smooth direction; a true corner reads sharp at both scales.
    let turn_at = |i: usize, k: usize| -> f64 {
        let p = arc[i - k];
        let q = arc[i];
        let r = arc[i + k];
        let v1 = (q.x - p.x, q.y - p.y);
        let v2 = (r.x - q.x, r.y - q.y);
        let l1 = v1.0.hypot(v1.1);
        let l2 = v2.0.hypot(v2.1);
        if l1 == 0.0 || l2 == 0.0 {
            return 0.0;
        }
        ((v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2)).clamp(-1.0, 1.0).acos().to_degrees()
    };
    // Confirmation window must be DISTANCE-based, not index-based: on a
    // pixel staircase the RDP keeps ~3 samples per step, so a k=2 index
    // window never leaves the step it sits on and reads the wobble's 90-deg
    // jag as structure (measured: the uni2075 bowl-tail staircase read
    // 91.8/72.1 deg at k=1/k=2 on every step, chopping one capture arc into
    // 28 two/three-point arcs that all shipped as Line facets). Walking
    // each side until the accumulated leg length reaches three lattice
    // cells (3.0 * t_line; t_line IS the lattice step in this frame - one
    // cell is quantization, two cells is the longest staircase period a
    // diagonal edge can take, the third cell is landing slack) averages
    // over the wobble: the same vertices read 0-3.4 deg (smooth curve)
    // while this glyph's true corners keep 121-134 deg at the same window.
    // When the walk hits an arc boundary before the window fills, the
    // boundary point is used: a short remaining leg can only belong to a
    // corner the capture already delimited, never to mid-arc wobble.
    let turn_at_dist = |i: usize, w: f64| -> f64 {
        let mut lo_i = i;
        let mut acc = 0.0f64;
        while lo_i > 0 && acc < w {
            acc += (arc[lo_i].x - arc[lo_i - 1].x).hypot(arc[lo_i].y - arc[lo_i - 1].y);
            lo_i -= 1;
        }
        let mut hi_i = i;
        let mut acc = 0.0f64;
        while hi_i < arc.len() - 1 && acc < w {
            acc += (arc[hi_i + 1].x - arc[hi_i].x).hypot(arc[hi_i + 1].y - arc[hi_i].y);
            hi_i += 1;
        }
        let p = arc[lo_i];
        let q = arc[i];
        let r = arc[hi_i];
        let v1 = (q.x - p.x, q.y - p.y);
        let v2 = (r.x - q.x, r.y - q.y);
        let l1 = v1.0.hypot(v1.1);
        let l2 = v2.0.hypot(v2.1);
        if l1 == 0.0 || l2 == 0.0 {
            return 0.0;
        }
        ((v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2)).clamp(-1.0, 1.0).acos().to_degrees()
    };
    let confirm_w = 3.0 * t_line;
    // On short arcs (<6 pts) a sharp k=1 turn with a failed line test is
    // already corner evidence (staircase wobble needs samples to manifest,
    // so short-arc k=1 sharpness is meaningful); such fragments only reach
    // here from a corner the capture delimited.
    let mut best = 0.0f64;
    let mut bi = 0usize;
    let lo = if arc.len() >= 6 { 2 } else { 1 };
    let hi = if arc.len() >= 6 { arc.len() - 2 } else { arc.len() - 1 };
    for i in lo..hi {
        let d1 = turn_at(i, 1);
        if d1 < 45.0 {
            continue;
        }
        let d2 = if arc.len() >= 6 { turn_at_dist(i, confirm_w) } else { d1 };
        if d2 < 45.0 {
            continue;
        }
        if d1.min(d2) > best {
            best = d1.min(d2);
            bi = i;
        }
    }
    if best >= 45.0 && bi >= 1 && bi <= arc.len() - 2 {
        Some(bi)
    } else {
        None
    }
}

/// Post-rounding tidy: remove zero-length spans (both ends equal after the
/// integer container rounding). A zero-length Line draws nothing, so removal
/// is geometry-neutral; a fully-collapsed Cubic (both controls and end on
/// the span's own start) is likewise invisible and removed. Cubics with
/// distinct controls are real loops and are kept. Closure is preserved:
/// dropping a zero-length final span leaves the previous span ending at
/// `start`. If every span would be removed (fully degenerate ring) the last
/// span is kept so the ring stays encodable. Returns (spans, removed).
fn tidy_zero_spans(start: Point, spans: Vec<Span>) -> (Vec<Span>, usize) {
    let mut out: Vec<Span> = Vec::with_capacity(spans.len());
    let mut current = start;
    let mut removed = 0usize;
    for s in spans.into_iter() {
        let (end, zero) = match s {
            Span::Line { end } => (end, end == current),
            Span::Cubic {
                control_one,
                control_two,
                end,
            } => (
                end,
                end == current && control_one == current && control_two == current,
            ),
        };
        if zero {
            removed += 1;
        } else {
            current = end;
            out.push(s);
        }
    }
    if out.is_empty() {
        // fully degenerate ring: keep a single zero-length span so the ring
        // remains encodable (closure: end == start by construction)
        out.push(Span::Line { end: start });
    }
    (out, removed)
}

/// Fit one captured ring into a ReferenceRing: corner-split, gated fit,
/// exact closure, integer rounding. Returns (ring, span_count, used_fallback).
// ---------- connector-to-mitre pre-pass (betweenLines role coverage) ----------
//
// A small connector between two nonparallel straight runs is replaced by
// the runs' support intersection X when X is a genuine external mitre and
// the rewrite stays within the measured distance tolerance of the source.
// Only the working point list is rewritten (corner indices are remapped);
// the immutable raw ring is never touched and the emitted geometry is still
// re-validated against the raw source downstream.
//
// Detection anchors on the caller's corner list: the connector is the
// corner-delimited arc between two adjacent corners and the straight runs
// are the two neighbouring arcs. Dense capture rings carry no simplified
// record structure, so corner arcs are the run evidence; regions without
// corner anchors fall through to the normal fit unchanged. The connector
// arc that spans the ring's index-0 seam is never a candidate (linear
// arcs only); it falls through unchanged.
//
// Guards (any failure leaves the source untouched; every distance is in
// the caller's t_line framework, no imported constants):
//  - runs A and B are straight: every run point within t_line of the chord
//  - nonparallel: unit support directions with finite nonzero determinant
//  - external mitre: intersection X with u > len(A) and v < 0 on the
//    unit-parametrised supports (X strictly beyond the connector on both)
//  - distance: perpendicular distance of X to the connector chord line is
//    strictly < t_line; |X-S| and |X-E| bounded by chord length + t_line
//  - tolerance bound: every connector source point (endpoints included)
//    stays within t_line of the mitred polyline prev(S) -> X -> next(E)
//    (a fixed tolerance bound, not a comparison against the previous fit's
//    residual)
//  - collapse prevention: the ring keeps >= 3 points and X is not
//    coincident with its new neighbours; this is not a self-intersection
//    or winding proof. Accepted rewrites never touch neighbouring arcs
// Corners at the connector endpoints remap to the mitred junction; corner
// positions elsewhere keep their identity.
fn mitre_connectors(pts: &mut Vec<Point>, corners: &mut Vec<usize>, t_line: f64) -> usize {
    let n = pts.len();
    if n < 6 || corners.len() < 2 || !t_line.is_finite() || t_line <= 0.0 {
        return 0;
    }
    let straight = |arc: &[Point]| -> bool {
        arc.len() >= 3 && chord_max_dev(arc, arc[0], arc[arc.len() - 1]) <= t_line
    };
    let m = corners.len();
    let mut accepted: Vec<(usize, usize, Point)> = vec![]; // (c_lo, c_hi, X), disjoint
    let mut ci = 0usize;
    while ci + 1 < m {
        let c0 = corners[ci].min(n - 1);
        let c1 = corners[ci + 1].min(n - 1);
        let a_lo = if ci == 0 { 0 } else { corners[ci - 1] };
        let b_hi = if ci + 2 < m { corners[ci + 2] } else { n - 1 };
        let a = &pts[a_lo..=c0];
        let c = &pts[c0..=c1];
        let b = &pts[c1..=b_hi];
        let advance = if straight(a) && straight(b) && c.len() >= 2 {
            let (pa0, pa1) = (a[0], a[a.len() - 1]);
            let (pb0, pb1) = (b[0], b[b.len() - 1]);
            let (dx, dy) = (pa1.x - pa0.x, pa1.y - pa0.y);
            let (ex, ey) = (pb1.x - pb0.x, pb1.y - pb0.y);
            let (ld, le) = (dx.hypot(dy), ex.hypot(ey));
            let mut skip = true;
            if ld > 0.0 && le > 0.0 {
                let (dx, dy, ex, ey) = (dx / ld, dy / ld, ex / le, ey / le);
                let det = dx * ey - ex * dy;
                if det.is_finite() && det != 0.0 {
                    let (wx, wy) = (pb0.x - pa0.x, pb0.y - pa0.y);
                    let u = (wx * ey - wy * ex) / det; // X = pa0 + d*u, unit d
                    let v = (wx * dy - wy * dx) / det; // X = pb0 + e*v, unit e
                    let (xx, xy) = (pa0.x + dx * u, pa0.y + dy * u);
                    // external mitre: X strictly beyond the connector on both supports
                    if xx.is_finite() && xy.is_finite() && u > ld && v < 0.0 {
                        let x_pt = Point { x: xx, y: xy };
                        let (s, e) = (pts[c0], pts[c1]);
                        let (cx, cy) = (e.x - s.x, e.y - s.y);
                        let clen = cx.hypot(cy);
                        if clen > 0.0 {
                            let dist = (cx * (xy - s.y) - cy * (xx - s.x)).abs() / clen;
                            let ds = (xx - s.x).hypot(xy - s.y);
                            let de = (xx - e.x).hypot(xy - e.y);
                            if dist < t_line && ds <= clen + t_line && de <= clen + t_line {
                                let prev = pts[(c0 + n - 1) % n];
                                let next = pts[(c1 + 1) % n];
                                if !((xx == prev.x && xy == prev.y) || (xx == next.x && xy == next.y)) {
                                    let mut ok = true;
                                    for k in c0..=c1 {
                                        let d2 = pt_seg_d2(pts[k], prev, x_pt).min(pt_seg_d2(pts[k], x_pt, next));
                                        if d2 > t_line * t_line {
                                            ok = false;
                                            break;
                                        }
                                    }
                                    if ok {
                                        accepted.push((c0, c1, x_pt));
                                        skip = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            skip
        } else {
            true
        };
        // after an accept, the two neighbouring arcs carry moved evidence;
        // they are not re-used as run anchors in this pass
        ci += if advance { 1 } else { 3 };
    }
    if accepted.is_empty() {
        return 0;
    }
    let mut new_pts: Vec<Point> = Vec::with_capacity(n);
    let mut map: Vec<usize> = vec![usize::MAX; n]; // old index -> new index
    let mut k = 0usize;
    for &(lo, hi, x) in &accepted {
        while k < lo {
            map[k] = new_pts.len();
            new_pts.push(pts[k]);
            k += 1;
        }
        for j in lo..=hi {
            map[j] = new_pts.len(); // connector arc folds into X
        }
        new_pts.push(x);
        k = hi + 1;
    }
    while k < n {
        map[k] = new_pts.len();
        new_pts.push(pts[k]);
        k += 1;
    }
    if new_pts.len() < 3 {
        return 0; // collapse prevention only: ring must keep >= 3 points
    }
    let merges = accepted.len();
    let mut nc: Vec<usize> = corners.iter().map(|&c| map[c.min(n - 1)]).collect();
    nc.sort_unstable();
    nc.dedup();
    *pts = new_pts;
    *corners = nc;
    merges
}

// ---------- reference-guided straight constraint (E0 frame callsite) ----------
//
// Consumes learned reference targets on the emitted frame: where two
// adjacent emitted nodes are both matched to reference nodes, those
// reference nodes are adjacent in the same reference ring, and the
// reference span between them is a straight Line, the emitted span between
// them is constrained to Line. A cubic is straightened only when its
// control polygon stays within the measured t_line tolerance of the chord
// (convex-hull bound), so the rewrite can never move geometry by more than
// the tolerance envelope. Spans without complete matched adjacency are
// untouched; nothing is invented for unmatched nodes.
//
// Index convention: node j is the end of span j; span j connects node
// (j + L - 1) % L to node j (the last node equals ring.start).
pub fn constrain_straight_spans(
    ring: &mut ReferenceRing,
    ring_index: usize,
    targets: &crate::reference_transfer::TransferTargets,
    reference: &crate::reference_transfer::PinnedReference,
    t_line: f64,
) -> usize {
    if !t_line.is_finite() || t_line <= 0.0 {
        return 0;
    }
    let l = ring.spans.len();
    if l < 2 {
        return 0;
    }
    // (ring, node) -> target lookup; duplicates keep the first
    let mut matched: std::collections::HashMap<(usize, usize), &crate::reference_transfer::NodeTarget> =
        std::collections::HashMap::new();
    for t in &targets.targets {
        if let Some(key) = t.captured {
            matched.entry(key).or_insert(t);
        }
    }
    let t2 = t_line * t_line;
    let mut flipped = 0usize;
    for j in 0..l {
        let prev_idx = (j + l - 1) % l;
        let (ta, tb) = match (matched.get(&(ring_index, prev_idx)), matched.get(&(ring_index, j))) {
            (Some(a), Some(b)) => (*a, *b),
            _ => continue,
        };
        if ta.reference_ring != tb.reference_ring {
            continue;
        }
        let rr = match reference.rings.get(ta.reference_ring) {
            Some(r) => r,
            None => continue,
        };
        let rn = rr.spans.len();
        if rn == 0 || (ta.reference_node + 1) % rn != tb.reference_node {
            continue; // only adjacent reference nodes carry span intent
        }
        // reference span ending at tb.reference_node must be a straight Line
        match rr.spans.get(tb.reference_node) {
            Some(Span::Line { .. }) => {}
            _ => continue,
        }
        let (p0, p1) = (
            if j == 0 { ring.start } else { end_of_span(&ring.spans[j - 1]) },
            end_of_span(&ring.spans[j]),
        );
        if let Span::Cubic { control_one, control_two, end } = ring.spans[j] {
            // convex-hull bound: the curve stays within the hull of its
            // control polygon, so hull distance to the chord bounds the move
            let d1 = pt_seg_d2(control_one, p0, p1);
            let d2 = pt_seg_d2(control_two, p0, p1);
            if d1.max(d2) <= t2 {
                ring.spans[j] = Span::Line { end };
                flipped += 1;
            }
        }
    }
    flipped
}
fn end_of_span(s: &Span) -> Point {
    match s {
        Span::Line { end } | Span::Cubic { end, .. } => *end,
    }
}
/// G2 joint-repair merge (candidate rule): adjacent Cubic spans whose shared
/// node is NOT a corner - an error-driven adaptive split inside one arc
/// (contiguous source samples, same arc) or a windowed-extremum pre-split
/// (forced axis tangents on both children, marked by a forced left tangent
/// on the right arc) - are refit as ONE cubic over the union of their
/// source samples, keeping the outer tangents of the two spans. The split
/// was introduced by subdivision, not corner evidence; a single cubic is
/// C2 in its interior by construction, so a successful merge removes the
/// G1-only joint's curvature break entirely.
///
/// Acceptance reuses the fitter's own gates - no new constants: fit_run
/// under the caller's FitPolicy, plausible(), and dense_gate within the
/// caller's dense bound. A true corner cannot be tracked by one cubic
/// within the policy error, so corner joints survive by evidence, not by
/// flag. Declined candidates keep the original two spans (no ledger entry:
/// the joint stays measured geometry, not a fallback). Each accepted merge
/// lowers the span count, so the pass count is bounded by the span count.
/// Union arcs are appended to `arcs` so downstream provenance
/// (PreEmissionSpan source samples) and span_arcs stay consistent.
/// Grid-noise curvature floor (candidate rule, shared convention with the
/// curve-stress measurement): every coordinate of the cubic's three
/// end-side control points is independently perturbed by +- half the
/// caller's lattice step (2^6 corners); the floor is the largest |k
/// perturbation|. A curvature jump at or below this band is
/// indistinguishable from integer-rounding noise on the emission lattice.
fn cubic_k_floor(p: &[Point; 4], end: bool, grid: f64) -> f64 {
    let idx: [usize; 3] = if end { [1, 2, 3] } else { [0, 1, 2] };
    let base = cubic_end_k(p, end);
    let half = grid / 2.0;
    let mut worst = 0.0f64;
    for mask in 0..64u32 {
        let mut q = *p;
        for bit in 0..6 {
            let pt = &mut q[idx[bit / 2]];
            let c = if bit % 2 == 0 { &mut pt.x } else { &mut pt.y };
            *c += if (mask >> bit) & 1 == 1 { half } else { -half };
        }
        worst = worst.max((cubic_end_k(&q, end) - base).abs());
    }
    worst
}

/// Joint break test (candidate rule, same convention): at a shared node,
/// severity = |k_in - k_out| * min(chord_in, chord_out) is a break when it
/// exceeds (floor_in + floor_out) * min(chord_in, chord_out). Line sides
/// carry k = 0 and no floor (their curvature is identically zero, not
/// measured). Zero-length handles are unavailable: treated as a break for
/// gating purposes (never accept a rewrite whose joint becomes unreadable).
fn joint_is_break(a_start: Point, sa: &Span, b_start: Point, sb: &Span, grid: f64) -> bool {
    let side = |start: Point, sp: &Span, end_side: bool| -> Option<(f64, f64, f64)> {
        match sp {
            Span::Line { end } => {
                let c = (end.x - start.x).hypot(end.y - start.y);
                if c == 0.0 { None } else { Some((0.0, c, 0.0)) }
            }
            Span::Cubic { control_one, control_two, end } => {
                let p = [start, *control_one, *control_two, *end];
                let h = if end_side {
                    (end.x - control_two.x).hypot(end.y - control_two.y)
                } else {
                    (control_one.x - start.x).hypot(control_one.y - start.y)
                };
                if h == 0.0 { return None; }
                let chord = (end.x - start.x).hypot(end.y - start.y);
                Some((cubic_end_k(&p, end_side), chord, cubic_k_floor(&p, end_side, grid)))
            }
        }
    };
    let (ka, ca, fa) = match side(a_start, sa, true) { Some(v) => v, None => return true };
    let (kb, cb, fb) = match side(b_start, sb, false) { Some(v) => v, None => return true };
    let m = ca.min(cb);
    (ka - kb).abs() * m > (fa + fb) * m
}

/// Joint harmonization for merge_g2_joints: returns the two spans with
/// joint-adjacent handles rescaled to equalize endpoint curvature, or None
/// when the move fails its gates. Same-sign nonzero curvatures only: a sign
/// change at the joint is an inflection feature, not a break.
fn harmonize_g2_joint(
    arcs: &[Vec<Point>],
    a: &FitSpan,
    b: &FitSpan,
    a_start: Point,
    a_end: Point,
    b_end: Point,
    db: f64,
    grid: f64,
) -> Option<(Span, Span)> {
    let (a_p1, a_p2) = match &a.span {
        Span::Cubic { control_one, control_two, .. } => (*control_one, *control_two),
        _ => return None,
    };
    let (b_p1, b_p2) = match &b.span {
        Span::Cubic { control_one, control_two, .. } => (*control_one, *control_two),
        _ => return None,
    };
    let ha = Point { x: a_end.x - a_p2.x, y: a_end.y - a_p2.y };
    let hb = Point { x: b_p1.x - a_end.x, y: b_p1.y - a_end.y };
    let (la, lb) = (ha.x.hypot(ha.y), hb.x.hypot(hb.y));
    if la == 0.0 || lb == 0.0 { return None; }
    let ka = cubic_end_k(&[a_start, a_p1, a_p2, a_end], true);
    let kb = cubic_end_k(&[a_end, b_p1, b_p2, b_end], false);
    if ka == 0.0 || kb == 0.0 || ka.signum() != kb.signum() { return None; }
    let r = (ka / kb).powf(0.25);
    if !r.is_finite() || r <= 0.0 { return None; }

    // r too close to 1: the move is below the lattice's resolving power.
    // Both handle moves below half the caller's lattice step: the equalization
    // is inside the rounding noise and cannot survive emission - skip.
    if (r - 1.0).abs() * la < grid / 2.0 && (1.0 / r - 1.0).abs() * lb < grid / 2.0 { return None; }
    let a_p2n = Point { x: a_end.x - ha.x * r, y: a_end.y - ha.y * r };
    let b_p1n = Point { x: a_end.x + hb.x / r, y: a_end.y + hb.y / r };
    let qa = [a_start, a_p1, a_p2n, a_end];
    let qb = [a_end, b_p1n, b_p2, b_end];
    let kan = cubic_end_k(&qa, true);
    let kbn = cubic_end_k(&qb, false);
    // Improvement certificate: the jump must strictly shrink.
    if (kan - kbn).abs() >= (ka - kb).abs() { return None; }
    let sa = &arcs[a.arc][a.s..=a.e];
    let sb = &arcs[b.arc][b.s..=b.e];
    if !plausible(sa, &qa) || !plausible(sb, &qb) { return None; }
    // Metric gate: within the caller's dense bound, and the joint must STOP
    // reading as a curvature break under the grid-noise convention -
    // harmonization exists to clear measured breaks, not to move them.
    let (ena, _) = dense_gate(&qa, sa);
    let (enb, _) = dense_gate(&qb, sb);
    if ena > db || enb > db { return None; }
    let la = Span::Cubic { control_one: a_p1, control_two: a_p2n, end: a_end };
    let lb = Span::Cubic { control_one: b_p1n, control_two: b_p2, end: b_end };
    if joint_is_break(a_start, &la, a_end, &lb, grid) { return None; }
    Some((la, lb))
}

/// Signed curvature at a cubic's end (t=1 when `end`, t=0 otherwise):
/// k = (B' x B'') / |B'|^3 evaluated at the endpoint.
fn cubic_end_k(p: &[Point; 4], end: bool) -> f64 {
    let (d1, d2) = if end {
        let d1 = Point { x: p[3].x - p[2].x, y: p[3].y - p[2].y };
        let d2 = Point { x: p[3].x - 2.0 * p[2].x + p[1].x, y: p[3].y - 2.0 * p[2].y + p[1].y };
        (d1, d2)
    } else {
        let d1 = Point { x: p[1].x - p[0].x, y: p[1].y - p[0].y };
        let d2 = Point { x: p[2].x - 2.0 * p[1].x + p[0].x, y: p[2].y - 2.0 * p[1].y + p[0].y };
        (d1, d2)
    };
    let n = d1.x.hypot(d1.y).powi(3);
    if n == 0.0 { return 0.0; }
    (d1.x * d2.y - d1.y * d2.x) / n
}

/// Straight-edge guard (declared convention, shared with
/// core/tests/straight_edge_fit.rs::straight_serif_edges_are_not_bowed):
/// a LONG emitted cubic whose controls hug its chord (max control sagitta
/// below 2% of the chord length) is a bowed straight edge - the defect
/// class the straight-over-curve pass exists to remove. The length floor is
/// the test contract's 60 fu converted to source pixels through the kit
/// battery's declared adaptive scale (1000 fu em over a 1050 px source:
/// 60 * 1050 / 1000 = 63 px); the engine works in fu at arbitrary scale,
/// so the floor is stated in pixels and scaled by the caller's grid
/// (one source pixel in fu).
const MERGE_STRAIGHT_EDGE_MIN_PX: f64 = 60.0 * 1050.0 / 1000.0;
const MERGE_STRAIGHT_EDGE_SAG_RATIO: f64 = 0.02;

/// Verdict of the straight-edge guard for one merge/fold candidate cubic.
enum StraightEdgeGuard {
    /// Not a long near-straight cubic: proceed with normal acceptance.
    Clear,
    /// The RAW union chain reads straight (raw_chord_dev within t_line,
    /// the R8 silent-acceptance rule): emit a Line instead of the cubic.
    EmitLine,
    /// Long, near-straight, but the raw chain does NOT read straight:
    /// decline - the original spans passed their own gates, keep them.
    Decline,
}

fn straight_edge_guard(start: Point, control_one: Point, control_two: Point, end: Point, t_line: f64, grid: f64) -> StraightEdgeGuard {
    let (dx, dy) = (end.x - start.x, end.y - start.y);
    let l = dx.hypot(dy);
    if l <= MERGE_STRAIGHT_EDGE_MIN_PX * grid {
        return StraightEdgeGuard::Clear;
    }
    let sag = |c: &Point| (dx * (c.y - start.y) - dy * (c.x - start.x)).abs() / l;
    if sag(&control_one).max(sag(&control_two)) / l >= MERGE_STRAIGHT_EDGE_SAG_RATIO {
        return StraightEdgeGuard::Clear;
    }
    match raw_chord_dev(start, end) {
        Some(dev) if dev <= t_line => StraightEdgeGuard::EmitLine,
        // None: no raw chain bound to these endpoints (forced-tangent
        // boundary); cannot prove straight - decline, never guess.
        _ => StraightEdgeGuard::Decline,
    }
}

fn merge_g2_joints(
    arcs: &mut Vec<Vec<Point>>,
    forces: &[(Option<Point>, Option<Point>)],
    fspans: &mut Vec<FitSpan>,
    start: Point,
    policy: &FitPolicy,
    db: f64,
    t_line: f64,
    grid: f64,
) -> usize {
    // Line-chain to cubic fold (candidate rule): a maximal run of >=2
    // consecutive Line spans inside ONE arc (contiguous source samples,
    // never crossing a corner-anchored boundary - corners split arcs, so
    // same-arc runs are corner-free by construction) is the emission of a
    // shallow wavy edge the piecewise line-first rule cut into segments.
    // The union of the run's source samples is refit under the fitter's own
    // recursive policy (fit_run splits at its own max-error sample, same
    // squared-error budget and refit limit the original spans were produced
    // under): one cubic when it holds, otherwise the fitter's own split
    // sequence of cubics with harmonized internal joints. Accepted only when
    // the fold uses strictly fewer spans than the line run (node reduction),
    // every leaf passes plausible + dense within the caller's bound, no
    // internal joint remains a curvature break under the grid-noise
    // convention, and neither outer joint becomes one. Declined runs keep
    // their Line spans unchanged. No new constants.
    fn fold_samples(
        arcs: &mut Vec<Vec<Point>>,
        u: &[Point],
        lt: Point,
        rt: Point,
        policy: &FitPolicy,
        t_line: f64,
        grid: f64,
        budget: usize,
    ) -> Option<Vec<FitSpan>> {
        if budget == 0 || u.len() < 3 {
            return None;
        }
        // Fold-candidate fit bound (architect-approved derivation): half the
        // source pixel, squared, in fu^2 - grid here is one source pixel in
        // fu, so (grid/2)^2 ~= 1.1 fu^2, the approved fit_se=1.0 equivalent.
        // The leaf excursion gate is the raw-chain line tolerance t_line
        // (rdp_eps + 0.5px quantization, derived at staircase_line),
        // SEPARATE from the dense bound db: a fold may deviate from the
        // captured samples as far as the Line chain it replaces was allowed
        // to deviate from the raw source chain.
        let fold_policy = FitPolicy { squared_error: (grid / 2.0) * (grid / 2.0), max_refits: policy.max_refits };
        match crate::cubic_fit::fit_run(u, lt, rt, &fold_policy) {
            crate::cubic_fit::FitOutcome::Fitted { controls: q, .. } => {
                if !plausible(u, &q) || dense_gate(&q, u).0 > t_line {
                    if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG leafgate n={} plaus={} exc={:.3} t_line={t_line:.3}", u.len(), plausible(u, &q), dense_gate(&q, u).0); }
                    return None;
                }
                arcs.push(u.to_vec());
                let na = arcs.len() - 1;
                Some(vec![FitSpan {
                    span: Span::Cubic { control_one: q[1], control_two: q[2], end: q[3] },
                    arc: na,
                    s: 0,
                    e: u.len() - 1,
                }])
            }
            crate::cubic_fit::FitOutcome::SplitUnresolved { sample_index: Some(k), .. }
                if k >= 1 && k + 1 < u.len() && u.len() >= 5 =>
            {
                // (n >= 5: both halves need the fitter's 3-sample minimum.)
                // The fitter's max-error sample may sit adjacent to an end;
                // a half shorter than the fitter's own structural minimum (3
                // samples, per fit_run's input rule) can never fit, so the
                // split is clamped to the nearest fittable position.
                let k = k.clamp(2, u.len() - 3);
                if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG foldsplit n={} k={k} budget={budget}", u.len()); }
                // Shared mid tangent so the two halves meet G1; the joint's
                // G2 is repaired (or the fold declined) by the caller.
                let dx = u[k + 1].x - u[k - 1].x;
                let dy = u[k + 1].y - u[k - 1].y;
                let n = dx.hypot(dy);
                if n == 0.0 || !n.is_finite() {
                    return None;
                }
                let mid = Point { x: dx / n, y: dy / n };
                let left = fold_samples(arcs, &u[..=k], lt, mid, policy, t_line, grid, budget)?;
                if left.len() >= budget {
                    return None;
                }
                let mut right = fold_samples(arcs, &u[k..], mid, rt, policy, t_line, grid, budget - left.len())?;
                let mut out = left;
                out.append(&mut right);
                Some(out)
            }
            other => {
                if std::env::var("KNI_G2DBG").is_ok() {
                    match &other {
                        crate::cubic_fit::FitOutcome::SplitUnresolved { sample_index, stop } => eprintln!("G2DBG folddecline n={} idx={sample_index:?} stop={stop:?}", u.len()),
                        _ => eprintln!("G2DBG folddecline n={} invalid", u.len()),
                    }
                }
                None
            }
        }
    }
    let fold_enabled = std::env::var("KNI_NO_FOLD").is_err();
    let mut i = 0usize;
    while fold_enabled && i < fspans.len() {
        if !matches!(fspans[i].span, Span::Line { .. }) { i += 1; continue; }
        let mut j = i;
        while j + 1 < fspans.len()
            && matches!(fspans[j + 1].span, Span::Line { .. })
            && fspans[j + 1].arc == fspans[i].arc
            && fspans[j + 1].s == fspans[j].e
        {
            j += 1;
        }
        let run_len = j - i + 1;
        if run_len >= 2 {
            let (s0, e0) = (fspans[i].s, fspans[j].e);
            if e0 < arcs[fspans[i].arc].len() {
                let u = arcs[fspans[i].arc][s0..=e0].to_vec();
                if u.len() >= 3 {
                    if let Some((lt, rt)) = windowed_chord_tangents(&u) {
                        // Source-straight runs (comb/serif edges: sagitta within
                        // half the lattice quantum, i.e. unmeasurable deviation)
                        // KEEP their Line spans - Line is the correct
                        // representation there. Smooth-arc runs convert to the
                        // fitter's own split sequence of cubics; the budget is
                        // the structural maximum (one leaf per 2 samples),
                        // not a node-count cap: representation, not tolerance.
                        let chord = Point { x: u[u.len() - 1].x - u[0].x, y: u[u.len() - 1].y - u[0].y };
                        let cl = chord.x.hypot(chord.y);
                        let sagitta = u.iter().map(|p| {
                            if cl == 0.0 { (p.x - u[0].x).hypot(p.y - u[0].y) } else { ((p.x - u[0].x) * chord.y - (p.y - u[0].y) * chord.x).abs() / cl }
                        }).fold(0.0f64, f64::max);
                        if sagitta <= t_line { i = j + 1; continue; }
                        if let Some(mut leaves) = fold_samples(arcs, &u, lt, rt, policy, t_line, grid, u.len()) {
                            // Internal joints: repair G2 via harmonization;
                            // decline the run if any joint stays a break.
                            let mut internal_ok = true;
                            for w in 0..leaves.len().saturating_sub(1) {
                                let (aa, bb) = (leaves[w].clone(), leaves[w + 1].clone());
                                let a_start = arcs[aa.arc][aa.s];
                                let joint = arcs[aa.arc][aa.e];
                                let b_end = arcs[bb.arc][bb.e];
                                if joint_is_break(a_start, &aa.span, joint, &bb.span, grid) {
                                    match harmonize_g2_joint(arcs, &aa, &bb, a_start, joint, b_end, t_line, grid) {
                                        Some((la, lb)) => {
                                            // Same straight-edge guard as the
                                            // merge loop: a harmonized fold
                                            // leaf flattened below the bow
                                            // convention declines the run.
                                            let guard_ok = [(a_start, &la), (joint, &lb)].iter().all(|(st, sp)| match sp {
                                                Span::Cubic { control_one, control_two, end } =>
                                                    matches!(straight_edge_guard(*st, *control_one, *control_two, *end, t_line, grid), StraightEdgeGuard::Clear),
                                                Span::Line { .. } => true,
                                            });
                                            if !guard_ok {
                                                if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG fold-harmonize straight-edge decline w={w}"); }
                                                internal_ok = false; break;
                                            }
                                            leaves[w].span = la;
                                            leaves[w + 1].span = lb;
                                        }
                                        None => { if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG fold-internal-break w={w}"); } internal_ok = false; break; }
                                    }
                                }
                            }
                            // No-new-break gate on the two outer joints.
                            let first_span = leaves[0].span.clone();
                            let last_span = leaves[leaves.len() - 1].span.clone();
                            let left_ok = if i == 0 {
                                let last = fspans.last().unwrap();
                                let mut p0 = start;
                                for f in fspans.iter().take(fspans.len() - 1) {
                                    p0 = match &f.span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
                                }
                                !joint_is_break(p0, &last.span, u[0], &first_span, grid)
                            } else {
                                let mut p0 = start;
                                for f in fspans.iter().take(i - 1) {
                                    p0 = match &f.span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
                                }
                                !joint_is_break(p0, &fspans[i - 1].span, u[0], &first_span, grid)
                            };
                            let right_ok = if j + 1 < fspans.len() {
                                !joint_is_break(u[0], &last_span, *u.last().unwrap(), &fspans[j + 1].span, grid)
                            } else {
                                !joint_is_break(u[0], &last_span, *u.last().unwrap(), &fspans[0].span, grid)
                            };
                            if std::env::var("KNI_G2DBG").is_ok() && leaves.len() > 1 {
                                eprintln!("G2DBG folddecision run={run_len} leaves={} internal={internal_ok} left={left_ok} right={right_ok}", leaves.len());
                            }
                            if internal_ok && left_ok && right_ok {
                                if std::env::var("KNI_G2DBG").is_ok() {
                                    for lf in &leaves {
                                        if let Span::Cubic { control_one, control_two, end } = &lf.span {
                                            let st = arcs[lf.arc][lf.s];
                                            let h1 = (control_one.x - st.x).hypot(control_one.y - st.y);
                                            let h2 = (end.x - control_two.x).hypot(end.y - control_two.y);
                                            if h1 < grid / 2.0 || h2 < grid / 2.0 {
                                                eprintln!("G2DBG subquantum-handle fold h1={h1:.3} h2={h2:.3} grid={grid}");
                                            }
                                        }
                                    }
                                }
                                if std::env::var("KNI_G2DBG").is_ok() {
                                    eprintln!("G2DBG chainfold arc={} s={s0} e={e0} lines={run_len} leaves={}", fspans[i].arc, leaves.len());
                                }
                                // Straight-edge guard on the fold leaves: a
                                // folded cubic reading as a long near-straight
                                // edge means the run is straight-edge content
                                // and the original Line spans are its correct
                                // representation. Decline the whole run (no
                                // per-leaf Line emit: leaf boundaries come
                                // from the fold's own split points, and a
                                // Line leaf could leave a curvature break
                                // against its harmonized neighbour).
                                let guarded = leaves.iter().any(|lf| match &lf.span {
                                    Span::Cubic { control_one, control_two, end } => {
                                        let st = arcs[lf.arc][lf.s];
                                        !matches!(straight_edge_guard(st, *control_one, *control_two, *end, t_line, grid), StraightEdgeGuard::Clear)
                                    }
                                    Span::Line { .. } => false,
                                });
                                if guarded {
                                    if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG fold-straight-edge-decline run={run_len}"); }
                                    i = j + 1;
                                    continue;
                                }
                                let before_g2 = if merge_visibility_enabled() { Some(fspans.clone()) } else { None };
                                let before_g2_arcs = if merge_visibility_enabled() { Some(arcs.clone()) } else { None };
                                let nleaf = leaves.len();
                                fspans.splice(i..=j, leaves);
                                if let (Some(before), Some(before_arcs)) = (before_g2.as_deref(), before_g2_arcs.as_deref()) {
                                    merge_visibility_rewrite_fit(MergeVisibilityPass::G2Merge, MergeVisibilityTransform::G2LineRunFold,
                                        before, fspans, before_arcs, arcs);
                                }
                                i += nleaf;
                                continue;
                            }
                        }
                    }
                }
            }
        }
        i = j + 1;
    }
    let orig_arcs = arcs.len();

    let mut merges = 0usize; // accepted merges + harmonized joints
    // Every accepted merge removes one span; a pass with no merge ends the loop.
    for _pass in 0..fspans.len().max(1) {
        let mut merged_any = false;
        let mut prev_end = start;
        let mut i = 0usize;
        while i + 1 < fspans.len() {
            let a = fspans[i].clone();
            let b = fspans[i + 1].clone();
            let (a_start, a_end, a_c1, b_end, b_c2) = match (&a.span, &b.span) {
                (
                    Span::Cubic { control_one: c1, end: ae, .. },
                    Span::Cubic { control_two: c2, end: be, .. },
                ) => (prev_end, *ae, *c1, *be, *c2),
                _ => {
                    prev_end = match &a.span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
                    i += 1;
                    continue;
                }
            };
            let union: Option<Vec<Point>> = if a.arc == b.arc && b.s == a.e && b.e < arcs[a.arc].len() {
                Some(arcs[a.arc][a.s..=b.e].to_vec())
            } else if b.arc < orig_arcs
                && b.arc == a.arc + 1
                && forces.get(b.arc).and_then(|f| f.0).is_some()
                && a.e + 1 == arcs[a.arc].len()
                && b.s == 0
                && b.e < arcs[b.arc].len()
            {
                // Extremum pre-split boundary (forced axis tangents, no corner).
                let mut u = arcs[a.arc][a.s..].to_vec();
                u.extend_from_slice(&arcs[b.arc][1..=b.e]);
                Some(u)
            } else {
                None
            };
            let dbg = std::env::var("KNI_G2DBG").is_ok();
            if dbg { eprintln!("G2DBG pair i={i} a.arc={} b.arc={} a.s={} a.e={} b.s={} b.e={} alen={:?} union={:?}",
                a.arc, b.arc, a.s, a.e, b.s, b.e, arcs.get(a.arc).map(|x| x.len()), union.as_ref().map(|u| u.len())); }
            let accepted = union.as_ref().and_then(|u| {
                if u.len() < 3 { return None; }
                let lt = Point { x: a_c1.x - a_start.x, y: a_c1.y - a_start.y };
                let rt = Point { x: b_end.x - b_c2.x, y: b_end.y - b_c2.y };
                match crate::cubic_fit::fit_run(u, lt, rt, policy) {
                    crate::cubic_fit::FitOutcome::Fitted { controls, max_squared_error, .. } if plausible(u, &controls) => {
                        let (exc, _) = dense_gate(&controls, u);
                        if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG   fitted err={max_squared_error:.4} exc={exc:.3} db={db:.3}"); }
                        if exc <= db { Some(controls) } else { None }
                    }
                    other => { if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG   nofit {:?}", match &other { crate::cubic_fit::FitOutcome::Fitted{..} => "Fitted-notplausible", crate::cubic_fit::FitOutcome::SplitUnresolved{..} => "SplitUnresolved", crate::cubic_fit::FitOutcome::InvalidInput => "InvalidInput" }); } None },
                }
            });
            // Straight-edge guard (chief-architect ruling on the u_scan
            // regression, f16d4a31 bounce): an accepted merge candidate that
            // reads as a long near-straight edge is either rewritten to its
            // chord (raw union chain straight at t_line, R8) or declined -
            // the decline falls through to the harmonization branch below,
            // which still repairs the joint without merging.
            let mut line_emit = false;
            let accepted = accepted.and_then(|q| match straight_edge_guard(q[0], q[1], q[2], q[3], t_line, grid) {
                StraightEdgeGuard::Clear => Some(q),
                StraightEdgeGuard::EmitLine => { line_emit = true; Some(q) }
                StraightEdgeGuard::Decline => {
                    if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG   straight-edge decline"); }
                    None
                }
            });
            match (accepted, union) {
                (Some(q), Some(u)) => {
                    let before_g2 = if merge_visibility_enabled() { Some(fspans.clone()) } else { None };
                    let before_g2_arcs = if merge_visibility_enabled() { Some(arcs.clone()) } else { None };
                    arcs.push(u);
                    let na = arcs.len() - 1;
                    let nl = arcs[na].len();
                    fspans[i] = FitSpan {
                        span: if line_emit { Span::Line { end: q[3] } } else { Span::Cubic { control_one: q[1], control_two: q[2], end: q[3] } },
                        arc: na, s: 0, e: nl - 1,
                    };
                    fspans.remove(i + 1);
                    if let (Some(before), Some(before_arcs)) = (before_g2.as_deref(), before_g2_arcs.as_deref()) {
                        merge_visibility_rewrite_fit(MergeVisibilityPass::G2Merge, MergeVisibilityTransform::G2Union,
                            before, fspans, before_arcs, arcs);
                    }
                    merges += 1;
                    merged_any = true;
                    // stay at i: chain the merged span against its next neighbour
                }
                _ => {
                    // G2 approach (candidate rule): the joint is a subdivision
                    // node, not corner evidence (candidate selection above
                    // excludes every corner-anchored boundary), and both
                    // children carry the SAME joint tangent by construction
                    // (forced axis tangent or shared split tangent). Their
                    // curvatures still differ because the handles solve
                    // independently. Rescaling the two joint-adjacent handles
                    // along their tangent directions by reciprocal factors
                    // r and 1/r with r^4 = k_in/k_out equalizes both endpoint
                    // curvatures at their geometric mean while preserving G1
                    // exactly; the move is accepted only with an improvement
                    // certificate (strictly smaller |k_in-k_out|) AND both
                    // sides still passing the fitter's own gates (plausible,
                    // dense excursion within the caller's bound) against
                    // their own source samples. No new constants.
                    if std::env::var("KNI_NO_HARMONIZE").is_err() { if let Some((la, lb)) = harmonize_g2_joint(arcs, &a, &b, a_start, a_end, b_end, db, grid) {
                        let before_g2 = if merge_visibility_enabled() { Some(fspans.clone()) } else { None };
                        let before_g2_arcs = if merge_visibility_enabled() { Some(arcs.clone()) } else { None };
                        // Straight-edge guard on the harmonized pair: rescaling
                        // can flatten a long, mildly bowed cubic below the bow
                        // convention. Decline outright in that case (no Line
                        // rewrite: the span's arc is its own fitted curve, not
                        // a merge union; if its raw chain truly read straight,
                        // the primary straight pass would already have
                        // converted it). The un-harmonized spans passed their
                        // own gates, keeping them is never wrong.
                        let guard_ok = [(a_start, &la), (a_end, &lb)].iter().all(|(st, sp)| match sp {
                            Span::Cubic { control_one, control_two, end } =>
                                matches!(straight_edge_guard(*st, *control_one, *control_two, *end, t_line, grid), StraightEdgeGuard::Clear),
                            Span::Line { .. } => true,
                        });
                        if !guard_ok {
                            if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG   harmonize straight-edge decline i={i}"); }
                            prev_end = a_end; i += 1; continue;
                        }
                        if std::env::var("KNI_G2DBG").is_ok() {
                            for (stp, sp) in [(a_start, &la), (a_end, &lb)] {
                                if let Span::Cubic { control_one, control_two, end } = sp {
                                    let h1 = (control_one.x - stp.x).hypot(control_one.y - stp.y);
                                    let h2 = (end.x - control_two.x).hypot(end.y - control_two.y);
                                    if h1 < grid / 2.0 || h2 < grid / 2.0 {
                                        eprintln!("G2DBG subquantum-handle harmonize h1={h1:.3} h2={h2:.3} grid={grid}");
                                    }
                                }
                            }
                        }
                        fspans[i].span = la;
                        fspans[i + 1].span = lb;
                        if let (Some(before), Some(before_arcs)) = (before_g2.as_deref(), before_g2_arcs.as_deref()) {
                            merge_visibility_rewrite_fit(MergeVisibilityPass::G2Merge, MergeVisibilityTransform::G2Harmonize,
                                before, fspans, before_arcs, arcs);
                        }
                        merges += 1;
                        merged_any = true;
                    } }
                    prev_end = a_end; i += 1;
                }
            }
        }
        if !merged_any { break; }
    }
    if std::env::var("KNI_G2DBG").is_ok() { eprintln!("G2DBG repairs_total={merges}"); }
    merges
}

pub fn fit_ring(
    pts: Vec<Point>,
    corners: Vec<usize>,
    policy: &FitPolicy,
) -> (ReferenceRing, usize, bool) {
    // Scale-1 convenience entry: lattice step = 1 font unit.
    fit_ring_db(pts, corners, policy, dense_bound(1.0, policy), 1.0, 1.0)
}

/// fit_ring with an explicit dense-gate bound (font units). Callers that
/// know the capture->font scale should pass dense_bound(scale, policy).
pub fn fit_ring_db(
    pts: Vec<Point>,
    corners: Vec<usize>,
    policy: &FitPolicy,
    db: f64,
    t_line: f64,
    grid: f64,
) -> (ReferenceRing, usize, bool) {
    let (ring, count, fallback, _) = fit_ring_db_economy_candidate(pts, corners, policy, db, t_line, grid, false);
    (ring, count, fallback)
}

pub fn fit_ring_db_with_economy(
    pts: Vec<Point>, corners: Vec<usize>, policy: &FitPolicy, db: f64, t_line: f64, grid: f64,
) -> (ReferenceRing, usize, bool, Vec<crate::economy::EconomyDecision>) {
    fit_ring_db_economy_candidate(pts, corners, policy, db, t_line, grid, true)
}
fn fit_ring_db_economy_candidate(
    pts: Vec<Point>, corners: Vec<usize>, policy: &FitPolicy, db: f64, t_line: f64, grid: f64,
    enable_economy: bool,
) -> (ReferenceRing, usize, bool, Vec<crate::economy::EconomyDecision>) {
    reset_raw_ring(); // task boundary: a standalone ring fit has no raw source; never inherit one
    // Capture result status derives from the finalized typed fallback ledger:
    // has_unresolved = !events.is_empty(). Intentional lines emit no events, so
    // the intentional-vs-unresolved distinction is preserved. Geometry, split
    // order, and gates are unchanged.
    let mut fevents=Vec::new();
    let mut astubs=Vec::new();
    let mut declined=Vec::new();
    let (ring,count,_mech_fb,decisions)=fit_ring_db_economy_observed(pts,corners,policy,db,t_line,grid,enable_economy,None,&mut fevents,&mut astubs,&mut declined,&mut Vec::new());
    // Anti-laundering: a ring carrying typed ambiguous stubs is NOT clean;
    // the bool covers both ledgers (fevents alone would hide a stub-only ring).
    (ring,count,!fevents.is_empty()||!astubs.is_empty(),decisions)
}
/// SUP-2 unresolved-fit ledger units: typed fallback events (SubGridSpan
/// excluded - a typed stop, not an unresolved fit) plus declined ambiguity
/// receipts whose lineage carried NO measured corner evidence
/// (TrulyAmbiguous, NoLineage). One source for the rescue trigger and the
/// adoption comparison so both sides count the same unit.
fn sup2_unresolved_units(events: &[FallbackEvent], declined: &[DeclinedAmbiguity]) -> usize {
    events.iter().filter(|e| e.reason != FallbackReason::SubGridSpan).count()
        + declined.iter().filter(|d| matches!(d.class, DeclinedClass::NoLineage | DeclinedClass::TrulyAmbiguous)).count()
}

fn fit_ring_db_economy_observed(
    mut pts:Vec<Point>,corners:Vec<usize>,policy:&FitPolicy,db:f64,t_line:f64,grid:f64,
    enable_economy:bool,parents:Option<&mut Vec<crate::source_provenance::PreEmissionSpan>>,
    fevents:&mut Vec<FallbackEvent>,
    astubs:&mut Vec<AmbiguousStub>,
    declined:&mut Vec<DeclinedAmbiguity>,
    fprov:&mut Vec<FallbackSpanProvenance>,
) -> (ReferenceRing,usize,bool,Vec<crate::economy::EconomyDecision>) {
    let visibility_fevents_start = fevents.len();
    let visibility_astubs_start = astubs.len();
    let visibility_declined_start = declined.len();
    // Connector-to-mitre pre-pass: corner-anchored connectors between two
    // nonparallel straight runs fold into the support intersection when the
    // rewrite stays within the measured t_line tolerance of the source.
    // Only the working list is rewritten; the immutable raw ring is untouched.
    let mut corners = corners;
    let _mitre_merges = mitre_connectors(&mut pts, &mut corners, t_line);
    let n=pts.len();
    let mut arcs: Vec<Vec<Point>> = vec![];
    if corners.is_empty() {
        // True closed ring: the seam is an arbitrary tracing index. Scan the
        // cyclic contour for landmarks FIRST; when they exist, rotate the
        // seam onto the first one so the open-arc machinery below yields
        // deterministic landmark-delimited children (>=2 nondegenerate arcs
        // when >=2 distinct landmarks exist) instead of one whole-ring arc.
        let mut c = pts.clone();
        if let Some(&(s0, _)) = extrema_splits_cyclic(&c, grid).first() {
            c.rotate_left(s0);
        }
        c.push(c[0]);
        arcs.push(c);
    } else {
        let k0 = corners[0];
        pts.rotate_left(k0);
        let cs: Vec<usize> = corners.iter().map(|&c| (c + n - k0) % n).collect();
        for w in 0..cs.len() {
            let a = cs[w];
            let b = if w + 1 < cs.len() { cs[w + 1] } else { n };
            let mut seg: Vec<Point> = pts[a..=b.min(n - 1)].to_vec();
            if b == n {
                seg.push(pts[0]);
            }
            arcs.push(seg);
        }
    }
    // merge tiny arcs (<3 points) forward; last tiny arc merges into first
    let mut m: Vec<Vec<Point>> = vec![];
    for seg in arcs.into_iter() {
        if let Some(last) = m.last_mut() {
            if last.len() < 3 {
                let last_pts: Vec<Point> = last.clone();
                let mut p2 = last_pts;
                p2.extend(seg[1..].iter().cloned());
                *last = p2;
                continue;
            }
        }
        m.push(seg);
    }
    if m.len() > 1 && m.last().unwrap().len() < 3 {
        let last = m.pop().unwrap();
        let mut p2 = last;
        p2.extend(m[0][1..].iter().cloned());
        m[0] = p2;
    }
    // D2 rescue: split arcs at sharp internal turns the corner detector
    // missed (structure evidence, see sharp_turn_rescue), repeat until no
    // arc hides a corner; cap iterations honestly.
    // order-preserving: leaves are appended left-to-right so the ring's
    // cyclic arc order is retained (a LIFO queue here scrambles span order)
    fn rescue_in_order(a: &[Point], t_line: f64, depth: usize, out: &mut Vec<Vec<Point>>) {
        if depth > 32 {
            out.push(a.to_vec());
            return;
        }
        match sharp_turn_rescue(a, t_line) {
            Some(k) => {
                rescue_in_order(&a[..=k], t_line, depth + 1, out);
                rescue_in_order(&a[k..], t_line, depth + 1, out);
            }
            None => out.push(a.to_vec()),
        }
    }
    let mut rescued: Vec<Vec<Point>> = vec![];
    for arc in m.into_iter() {
        rescue_in_order(&arc, t_line, 0, &mut rescued);
    }
    // Replace semantics: arcs are
    // partitioned at their windowed extrema BEFORE the fit, so extremum nodes
    // take the place of curvature-adaptive split nodes instead of being added
    // on top. Adaptive splits inside fit_gated still fire when error demands.
    // Each pre-split sub-arc carries forced axis tangents at its extremum
    // ends (exact extremum nodes, axis-aligned tangents). Convention
    // matches the adaptive path: a split at travel direction t gives the left
    // child rt_force=-t and the right child lt_force=t.
    let mut presplit: Vec<(Vec<Point>, Option<Point>, Option<Point>)> = vec![];
    for arc in rescued.into_iter() {
        let xs = extrema_splits(&arc, grid);
        let mut splits: Vec<(usize, Point)> = xs
            .into_iter()
            .filter(|&(i, _)| i >= 1 && i <= arc.len() - 2)
            .collect();
        splits.sort_by(|a, b| a.0.cmp(&b.0));
        splits.dedup_by(|a, b| a.0 == b.0);
        if splits.is_empty() {
            presplit.push((arc, None, None));
            continue;
        }
        let mut lo = 0usize;
        let mut lt: Option<Point> = None;
        for &(i, t) in &splits {
            presplit.push((arc[lo..=i].to_vec(), lt, Some(Point { x: -t.x, y: -t.y })));
            lo = i;
            lt = Some(t);
        }
        presplit.push((arc[lo..].to_vec(), lt, None));
    }
    let mut m: Vec<Vec<Point>> = presplit.iter().map(|(a, _, _)| a.clone()).collect();
    let m_forces: Vec<(Option<Point>, Option<Point>)> =
        presplit.into_iter().map(|(_, l, r)| (l, r)).collect();
    if std::env::var("KNI_DEBUG").is_ok() {
        eprintln!("DBG arcs after rescue: {:?}",
            m.iter().map(|a| (a.len(), extrema_splits(a, grid).len())).collect::<Vec<_>>());
    }
    let mut start = m[0][0];
    let mut fspans: Vec<FitSpan> = vec![];
    let mut fb = false;
    for (ai, arc) in m.iter().enumerate() {
        let (lf, rf) = m_forces[ai];
        let mut visibility_corner_resplit_selected = false;
        // Per-arc depth ceiling: longest possible peel chain is n-2 (see
        // fit_gated). Derived from this arc's sample count, never a literal.
        let depth_cap = arc.len().saturating_sub(2);
        let fe_before = fevents.len();
        let astubs_before = astubs.len();
        let declined_before = declined.len();
        let spans_before = fspans.len();
        let fb_before = fb;
        fit_gated(arc, policy, &mut fspans, 0, &mut fb, db, t_line, grid, depth_cap, ai, 0, lf, rf, false, None, fevents, astubs, None, declined, fit_run);
        // Unresolved-arc rescue (PN-3): when the primary fitter left typed
        // fallback-ledger events on this arc (non-SubGridSpan; the floor
        // class is a typed stop, not an unresolved fit), the arc is re-fitted
        // ONCE with the damped Newton proposal (fit_run_damped, whose
        // all-or-nothing refit rejection is the measured root cause of the
        // unresolved bottom-outs) under the caller's OWN emission bound as
        // the accept threshold (db^2, squared units of the dense bound the
        // emitted span must and will still pass below: dense_gate <= db,
        // plausibility unchanged). Derivation: the emission contract for
        // every accepted cubic is the one-source-pixel dense bound; the
        // rescued span ships under exactly that contract, so no geometry is
        // invented and no tolerance is loosened past what every other span
        // already satisfies. The rescue is adopted ONLY when it resolves
        // every ledger event on the arc; otherwise the original spans and
        // ledger are restored untouched. Arcs with no events never re-fit:
        // outputs that ship strict-clean today are bit-identical by
        // construction (Marq/MCA continuity).
        // The lineage-None extension replaces the n>=3 no-lineage EVENT with a
        // typed DeclinedClass::NoLineage receipt; the rescue's trigger and
        // adoption units must count the receipt as the ledger unit it
        // replaced, otherwise suppressing the event would silently skip
        // rescue passes the pre-extension tree ran. Counting
        // events+NoLineage receipts reproduces the pre-extension
        // trigger/adoption set exactly: every suppressed event is one
        // receipt, 1:1. Ambiguous-lineage receipts were event-free before
        // the extension as well, so they are NOT counted.
        // SUP-2: the same argument now covers TrulyAmbiguous receipts. A
        // truly-ambiguous bottom-out (budget exhausted, no measured turn at
        // ANY lineage level) carries no corner evidence; it is a
        // curve-intended fragment that shipped as a Line only because the
        // primary fitter's own error budget (fit_squared_error, ~quarter
        // pixel at the Marq capture scale) cannot follow pixel-staircase
        // quantization wobble. The damped rescue's budget IS the emission
        // bound (db^2, one source pixel), exactly the contract such a
        // fragment must meet. Trigger and adoption units therefore count
        // events + NoLineage + TrulyAmbiguous, one helper, both sides of
        // the comparison: an arc whose rescue bottom-outs into the same
        // truly-ambiguous lines shows no measured gain and is NOT adopted
        // (CornerLeaning stubs and RoundAmbiguous/Band receipts carry
        // measured corner or deviation evidence and stay out of the count,
        // so true-corner geometry is untouched). Arcs without
        // truly-ambiguous receipts keep the pre-SUP-2 trigger set exactly:
        // same rescue runs, same adoption comparison, bit-identical output.
        let new_ledger_events = sup2_unresolved_units(&fevents[fe_before..], &declined[declined_before..]);
        if new_ledger_events > 0 {
            corner_record_site_set_arc(ai);
            let mut r_spans: Vec<FitSpan> = Vec::new();
            let mut r_fevents: Vec<FallbackEvent> = Vec::new();
            let mut r_astubs: Vec<AmbiguousStub> = Vec::new();
            let mut r_declined: Vec<DeclinedAmbiguity> = Vec::new();
            let mut r_fb = false;
            let rescue_policy = FitPolicy { squared_error: db * db, max_refits: policy.max_refits };
            fit_gated(arc, &rescue_policy, &mut r_spans, 0, &mut r_fb, db, t_line, grid, depth_cap, ai, 0, lf, rf, false, None, &mut r_fevents, &mut r_astubs, None, &mut r_declined, crate::cubic_fit::fit_run_damped);
            let mut r_ledger_events = sup2_unresolved_units(&r_fevents, &r_declined);
            if r_ledger_events > 0 {
                // Curve-first ordering: only when the damped refit of the
                // WHOLE arc still fails (a corner, not a curve, is the
                // evidence) does the corner resplit run; a resolved cubic
                // is never replaced by legs.
                let mut legs: Vec<Vec<Point>> = Vec::new();
                corner_resplit(arc, t_line, 0, &mut legs);
                // legs.len() == 1 (no corner structure found) still runs the
                // leg loop: its chord-line terminal accept is the last
                // resort for near-straight fragments whose hook fails
                // plausibility but reads within the dense bound.
                {
                    let mut c_spans: Vec<FitSpan> = Vec::new();
                    let mut c_fevents: Vec<FallbackEvent> = Vec::new();
                    let mut c_astubs: Vec<AmbiguousStub> = Vec::new();
                    let mut c_declined: Vec<DeclinedAmbiguity> = Vec::new();
                    let mut c_fb = false;
                    let mut base = 0usize;
                    for leg in &legs {
                        let leg_cap = leg.len().saturating_sub(2);
                        let ev_before = c_fevents.len();
                        let sp_before = c_spans.len();
                        let ast_before = c_astubs.len();
                        let dec_before = c_declined.len();
                        fit_gated(leg, &rescue_policy, &mut c_spans, 0, &mut c_fb, db, t_line, grid, leg_cap, ai, base, None, None, false, None, &mut c_fevents, &mut c_astubs, None, &mut c_declined, crate::cubic_fit::fit_run_damped);
                        let leg_events = sup2_unresolved_units(&c_fevents[ev_before..], &c_declined[dec_before..]);
                        if leg_events > 0 && chord_max_dev(leg, leg[0], leg[leg.len() - 1]) <= db {
                            // Chord-line terminal accept: the leg's own
                            // (damped) curve fit failed, and its straight
                            // chord reads WITHIN the caller's dense bound
                            // db - the same acceptance standard dense_gate
                            // applies to every emitted span (<= one source
                            // pixel). The measured deviation, not a switch,
                            // admits the line; the failed fit's spans and
                            // ledger entries are replaced by the Line.
                            c_spans.truncate(sp_before);
                            c_spans.push(FitSpan { span: Span::Line { end: leg[leg.len() - 1] }, arc: ai, s: base, e: base + leg.len() - 1 });
                            c_fevents.truncate(ev_before);
                            c_astubs.truncate(ast_before);
                            c_declined.truncate(dec_before);
                        }
                        base += leg.len() - 1;
                    }
                    let c_ledger_events = sup2_unresolved_units(&c_fevents, &c_declined);
                    let (rec_ring, rec_arc) = CURRENT_CORNER_SITE.with(|c| c.get());
                    CORNER_ADOPTION_RECORDS.with(|v| v.borrow_mut().push(CornerAdoptionRecord {
                        ring: rec_ring, arc: rec_arc,
                        arc_samples: arc.len(), legs: legs.len(),
                        r_events: r_ledger_events, c_events: c_ledger_events, new_events: new_ledger_events,
                        corner_adopted: c_ledger_events < r_ledger_events,
                        rescue_adopted: if c_ledger_events < r_ledger_events { c_ledger_events } else { r_ledger_events } < new_ledger_events,
                    }));
                    if c_ledger_events < r_ledger_events {
                        visibility_corner_resplit_selected = true;
                        r_spans = c_spans;
                        r_fevents = c_fevents;
                        r_astubs = c_astubs;
                        r_declined = c_declined;
                        r_fb = c_fb;
                        r_ledger_events = c_ledger_events;
                    }
                }
            }
            if r_ledger_events < new_ledger_events {
                let before_rescue_adoption = if merge_visibility_enabled() { Some(fspans.clone()) } else { None };
                fspans.truncate(spans_before);
                fspans.extend(r_spans);
                fevents.truncate(fe_before);
                fevents.extend(r_fevents);
                astubs.truncate(astubs_before);
                astubs.extend(r_astubs);
                declined.truncate(declined_before);
                declined.extend(r_declined);
                fb = fb_before || r_fb;
                if let Some(before) = before_rescue_adoption {
                    let transform = if visibility_corner_resplit_selected {
                        MergeVisibilityTransform::CornerAdoption
                    } else {
                        MergeVisibilityTransform::ArcRescue
                    };
                    merge_visibility_rewrite_fit(MergeVisibilityPass::RescueAdoption, transform,
                        &before, &fspans, &m, &m);
                }
            }
        }
    }
    // P0 captures the by-value output of rescue/adoption before G2.
    merge_visibility_observe_fit(MergeVisibilityPoint::P0, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    // G2 joint-repair merge: fold non-corner split joints (adaptive and
    // extremum pre-splits) into single cubics where the fitter's own gates
    // accept the union arc (see merge_g2_joints).
    let _g2_merges = merge_g2_joints(&mut m, &m_forces, &mut fspans, start, policy, db, t_line, grid);
    // P1 is the post-G2 / pre-staircase snapshot. Its predecessor revision is
    // resolved from P0 by the external canonical fingerprint adapter.
    merge_visibility_observe_fit(MergeVisibilityPoint::P1, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    // The KNI_NO_STAIR switch was removed: staircase merge
    // is landed and battery-superior; the pre-merge path is git history.
    {
        // staircase merge (candidate rule): consecutive Line spans of one arc whose source points read as a
        // rasterised straight edge (staircase_line evidence) collapse into one Line. Everything else is untouched.
        let before_spans = fspans.clone();
        let before_arcs = m.clone();
        let mut merged: Vec<FitSpan> = Vec::with_capacity(fspans.len());
        let mut i = 0usize;
        while i < fspans.len() {
            let mut best_j = i;
            if matches!(fspans[i].span, Span::Line { .. }) {
                let mut j = i;
                while j + 1 < fspans.len() && fspans[j + 1].arc == fspans[i].arc && matches!(fspans[j + 1].span, Span::Line { .. }) && fspans[j + 1].s == fspans[j].e { j += 1; }
                let mut jj = j;
                while jj > i {
                    let arc = &m[fspans[i].arc];
                    let (s0, e0) = (fspans[i].s, fspans[jj].e);
                    if e0 < arc.len() && e0 > s0 && staircase_line(&arc[s0..=e0], t_line) { best_j = jj; break; }
                    jj -= 1;
                }
            }
            if best_j > i {
                let arc = &m[fspans[i].arc];
                let e0 = fspans[best_j].e;
                merged.push(FitSpan { span: Span::Line { end: arc[e0] }, arc: fspans[i].arc, s: fspans[i].s, e: e0 });
                i = best_j + 1;
            } else { merged.push(fspans[i].clone()); i += 1; }
        }
        fspans = merged;
        merge_visibility_rewrite_fit(MergeVisibilityPass::Staircase, MergeVisibilityTransform::StaircaseCollapse,
            &before_spans, &fspans, &before_arcs, &m);
    }
    merge_visibility_observe_fit(MergeVisibilityPoint::P2, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    if std::env::var("KNI_DEBUG4").is_ok() {
        let mut per_arc: Vec<usize> = vec![0; m.len()];
        for f in &fspans { per_arc[f.arc] += 1; }
        eprintln!("DBG4 arc_lens={:?} spans_per_arc={:?}", m.iter().map(|a| a.len()).collect::<Vec<_>>(), per_arc);
    }
    // P2 in the legacy fitter comment: Unit 9 P3, post line-junction refinement.
    let before_line_junction = fspans.clone();
    let before_line_junction_start = start;
    let before_line_junction_arcs = m.clone();
    refine_line_junctions(&m, &mut fspans, &mut start, t_line);
    merge_visibility_rewrite_fit_with_starts(MergeVisibilityPass::LineJunction, MergeVisibilityTransform::LineJunctionMovement,
        &before_line_junction, &fspans, &before_line_junction_arcs, &m, Some(before_line_junction_start), Some(start));
    merge_visibility_observe_fit(MergeVisibilityPoint::P3, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    {
        // Straight-over-curve: a Cubic span whose RAW boundary points are fitted at least as well
        // by its end chord as by the cubic itself (and within 2*t_line of the chord) is a straight edge
        // that the fit bowed: emit Line.
        let before_soc = fspans.clone();
        let before_soc_arcs = m.clone();
        let mut prev = start;
        for f in fspans.iter_mut() {
            let endp = match &f.span { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
            let a0 = prev;
            prev = endp;
            // allow rationale: c1/c2 name the Span::Cubic control_one/control_two destructure for the straightness evidence below; values intentionally unread.
            #[allow(unused_variables)]
            let (c1, c2) = match &f.span { Span::Cubic { control_one, control_two, .. } => (*control_one, *control_two), _ => continue };
            if f.e <= f.s { continue; }
            let pa = m[f.arc][f.s]; let pb = m[f.arc][f.e];
            let raw = match raw_between(pa, pb) { Some(r) => r, None => continue };
            if raw.len() < 4 { continue; }
            let l = (pb.x - pa.x).hypot(pb.y - pa.y);
            if l < 6.0 * t_line { continue; }
            let (_sl, ml) = span_dev(&raw, a0, &Span::Line { end: endp });
            // Straightness evidence is ABSOLUTE and carries the raw-chain
            // silent-acceptance rule: every raw boundary point within t_line
            // of the end chord means any residual curvature is below the
            // acquisition chain's own straightness tolerance, so the span is
            // a straight edge. The retired
            // relative guard (chord sum-sq within (1+tol) of the cubic's) coupled
            // conversion to cubic quality: a better cubic fit made straights
            // HARDER to recover (the guard blocks precisely when the fit
            // improves). Dropping it restores the pass's observable behavior.
            if ml.sqrt() <= t_line {
                f.span = Span::Line { end: endp };
            }
        }
        merge_visibility_rewrite_fit(MergeVisibilityPass::StraightOverCurve, MergeVisibilityTransform::SocConversion,
            &before_soc, &fspans, &before_soc_arcs, &m);
    }
    merge_visibility_observe_fit(MergeVisibilityPoint::P4, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    let before_qf = fspans.clone();
    let before_qf_arcs = m.clone();
    refine_junction_qf(&m, &mut fspans, start, t_line, 1.0, 0.05);
    merge_visibility_rewrite_fit(MergeVisibilityPass::Qf, MergeVisibilityTransform::QfRefinement,
        &before_qf, &fspans, &before_qf_arcs, &m);
    let mut span_arcs: Vec<usize> = fspans.iter().map(|f| f.arc).collect();
    merge_visibility_observe_fit(MergeVisibilityPoint::P5, MergeVisibilityDomain::Float, start,
        &fspans, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], 0);
    if let Some(records)=parents {
        let mut current=start;
        for (parent_index,f) in fspans.iter().enumerate() {
            records.push(crate::source_provenance::PreEmissionSpan {
                parent_index,start:current,span:f.span.clone(),
                source:Some(crate::source_provenance::SourceInterval {
                    arc:f.arc,first_sample:f.s,last_sample:f.e,samples:m[f.arc].clone(),
                }),
            });
            current=match f.span {Span::Line{end}|Span::Cubic{end,..}=>end};
        }
        if current!=start {records.push(crate::source_provenance::PreEmissionSpan {
            parent_index:records.len(),start:current,span:Span::Line{end:start},source:None});}
    }
    let mut spans: Vec<Span> = fspans.into_iter().map(|f| f.span).collect();
    // closure: last span end must equal start
    let last_end = match spans.last().unwrap() {
        Span::Line { end } => *end,
        Span::Cubic { end, .. } => *end,
    };
    let before_closure = spans.clone();
    let before_closure_arcs = m.clone();
    let synthetic_closures = usize::from(last_end != start);
    if last_end != start {
        spans.push(Span::Line { end: start });
        // Synthetic closure is its own protected source boundary.
        span_arcs.push(m.len());
    }
    merge_visibility_rewrite_plain(MergeVisibilityPass::Closure, MergeVisibilityTransform::SyntheticClosure,
        &before_closure, &spans, &span_arcs, &before_closure_arcs, &m);
    // Integer rounding (container integer subset) - declared adaptation.
    let pre_rounding = spans.clone();
    let rspan: Vec<Span> = spans
        .into_iter()
        .map(|s| match s {
            Span::Line { end } => Span::Line { end: rd(end) },
            Span::Cubic {
                control_one,
                control_two,
                end,
            } => Span::Cubic {
                control_one: rd(control_one),
                control_two: rd(control_two),
                end: rd(end),
            },
        })
        .collect();
    merge_visibility_rewrite_plain_with_starts(MergeVisibilityPass::Rounding, MergeVisibilityTransform::Round,
        &pre_rounding, &rspan, &span_arcs, &m, &m, Some(start), Some(rd(start)));
    merge_visibility_observe_plain(MergeVisibilityPoint::P6, MergeVisibilityDomain::Integer, rd(start),
        &rspan, &span_arcs, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..],
        synthetic_closures);
    // post-rounding tidy: zero-length spans are invisible duplicates
    let (rspan, decisions) = if enable_economy {
        let before_cubic_economy = rspan.clone();
        let (rspan, cubic_records) = crate::economy::exact_cubic_lines(rd(start), rspan, &span_arcs);
        merge_visibility_rewrite_plain(MergeVisibilityPass::Economy, MergeVisibilityTransform::ExactCubicLine,
            &before_cubic_economy, &rspan, &span_arcs, &m, &m);
        merge_visibility_attach_economy_decisions(MergeVisibilityTransform::ExactCubicLine, cubic_records.clone());
        let before_line_economy = rspan.clone();
        let (rspan, line_records) = crate::economy::exact_line_economy(rd(start), rspan, &span_arcs);
        merge_visibility_rewrite_plain(MergeVisibilityPass::Economy, MergeVisibilityTransform::ExactLineMerge,
            &before_line_economy, &rspan, &span_arcs, &m, &m);
        merge_visibility_attach_economy_decisions(MergeVisibilityTransform::ExactLineMerge, line_records.clone());
        let mut records = cubic_records;
        records.extend(line_records);
        (rspan, records)
    } else { (rspan, Vec::new()) };
    let before_tidy = rspan.clone();
    let (rspan, removed) = tidy_zero_spans(rd(start), rspan);
    merge_visibility_rewrite_plain(MergeVisibilityPass::Tidy, MergeVisibilityTransform::ZeroSpanRemoval,
        &before_tidy, &rspan, &span_arcs, &m, &m);
    merge_visibility_observe_plain(MergeVisibilityPoint::P7, MergeVisibilityDomain::Integer, rd(start),
        &rspan, &span_arcs, &m, &fevents[visibility_fevents_start..], &astubs[visibility_astubs_start..], &declined[visibility_declined_start..], synthetic_closures);
    merge_visibility_set_last_snapshot_count("zero_span_removals", removed);
    let ns = rspan.len();
    // r282 audit-only: provenance rows for this ring's FINAL adopted fallback
    // events (post rescue/adoption), measured from the producer arc samples.
    // Metrics convert font units to source pixels via the fit grid; a missing
    // or degenerate fragment stays None, never invented. ring is tagged by the
    // per-ring driver, which owns the ring index.
    {
        let px = if grid.is_finite() && grid > 0.0 { grid } else { 1.0 };
        for e in &fevents[visibility_fevents_start..] {
            let (chord, arc_len, max_dev) = match m.get(e.arc) {
                Some(arc_samples) => {
                    let (c, l, d) = span_fragment_metrics(arc_samples, e.s, e.e);
                    (c.map(|v| v / px), l.map(|v| v / px), d.map(|v| v / px))
                }
                None => (None, None, None),
            };
            // r288: decline_class joins this ring's finalized declined ledger
            // at (arc, s, e) - a SplitUnresolved span carries a sibling decline
            // by construction; every other event class stays None.
            let decline = if e.reason == FallbackReason::SplitUnresolved {
                declined[visibility_declined_start..].iter().rev()
                    .find(|d| d.arc == e.arc && d.s == e.s && d.e == e.e)
                    .map(|d| d.class)
            } else {
                None
            };
            fprov.push(FallbackSpanProvenance { ring: 0, arc: e.arc, s: e.s, e: e.e, chord_px: chord, arc_len_px: arc_len, max_dev_px: max_dev, reason: e.reason, stop: e.stop, decline });
        }
    }
    (
        ReferenceRing {
            start: rd(start),
            spans: rspan,
        },
        ns,
        fb,
        decisions,
    )
}

/// Fit every ring of a captured contour. `scale` maps capture pixels to font
/// units; scaling is applied before fitting so the policy error bound is in
/// font units.

// Extremum nodes: exact extremum nodes with axis-aligned
// tangents. Every internal x/y extremum of a fitted cubic becomes an
// on-curve node via de Casteljau subdivision; at an x-extremum the tangent
// is vertical, at a y-extremum horizontal. Coordinates are integer-rounded
// like the fitter's own output; after rounding, the handles adjacent to a
// split node are pinned to the node's axis coordinate so axis alignment is
// exact (sub-unit geometry cost, geometry otherwise preserved).
fn cubic_extrema_ts(p0: Point, c1: Point, c2: Point, p3: Point) -> Vec<(f64, u8)> {
    cubic_extrema_ts_eps(p0, c1, c2, p3, 0.02)
}

fn cubic_extrema_ts_eps(p0: Point, c1: Point, c2: Point, p3: Point, eps: f64) -> Vec<(f64, u8)> {
    let mut ts: Vec<(f64, u8)> = vec![];
    for comp in 0..2u8 {
        let (v0, v1, v2, v3) = if comp == 0 {
            (p0.x, c1.x, c2.x, p3.x)
        } else {
            (p0.y, c1.y, c2.y, p3.y)
        };
        let a2 = 3.0 * (-v0 + 3.0 * v1 - 3.0 * v2 + v3);
        let a1 = 6.0 * (v0 - 2.0 * v1 + v2);
        let a0 = 3.0 * (v1 - v0);
        let mut push = |t: f64| {
            if t > eps && t < 1.0 - eps { ts.push((t, comp)); }
        };
        if a2.abs() < 1e-12 {
            if a1.abs() > 1e-12 { push(-a0 / a1); }
        } else {
            let disc = a1 * a1 - 4.0 * a2 * a0;
            if disc > 1e-12 {
                let sq = disc.sqrt();
                push((-a1 + sq) / (2.0 * a2));
                push((-a1 - sq) / (2.0 * a2));
            }
        }
    }
    ts.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
    // merge near-coincident t's into an axis bitmask (3 = both: no axis pin)
    let mut out: Vec<(f64, u8)> = vec![];
    for (t, ax) in ts {
        if let Some(last) = out.last_mut() {
            if (last.0 - t).abs() < 1e-6 {
                last.1 |= ax + 1; // comp 0 -> bit 1, comp 1 -> bit 2
                continue;
            }
        }
        out.push((t, ax + 1));
    }
    for e in out.iter_mut() {
        if e.1 > 2 { e.1 = 3; }
    }
    out
}

fn split_cubic_at(p0: Point, c1: Point, c2: Point, p3: Point, t: f64) -> ((Point, Point, Point), (Point, Point)) {
    let lerp = |a: Point, b: Point| Point { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
    let q0 = lerp(p0, c1);
    let q1 = lerp(c1, c2);
    let q2 = lerp(c2, p3);
    let r0 = lerp(q0, q1);
    let r1 = lerp(q1, q2);
    let s = lerp(r0, r1);
    ((q0, r0, s), (r1, q2))
}

fn split_ring_at_extrema(ring: ReferenceRing) -> ReferenceRing {
    // The KNI_NO_EXTSPLIT switch was removed - the last
    // behavior-affecting env knob. Extrema splitting is unconditional (the
    // knob-unset default all delivered runs used); diagnostics stay on the
    // KNI_DEBUG* family, which never alters output.
    let mut spans = vec![];
    let mut cur = ring.start;
    for sp in ring.spans {
        match sp {
            Span::Line { end } => {
                spans.push(Span::Line { end });
                cur = end;
            }
            Span::Cubic { control_one: c1, control_two: c2, end: p3 } => {
                let ts = cubic_extrema_ts(cur, c1, c2, p3);
                if std::env::var("KNI_DEBUG5").is_ok() && !ts.is_empty() {
                    for &(t, ax) in &ts {
                        let q = cubic_eval(cur, c1, c2, p3, t);
                        eprintln!("DBG5 postpass-split at ({:.1},{:.1}) axis {} t {:.3} cubic ({:.2},{:.2})->({:.2},{:.2}) c1 ({:.2},{:.2}) c2 ({:.2},{:.2})", q.x, q.y, ax, t, cur.x,cur.y,p3.x,p3.y,c1.x,c1.y,c2.x,c2.y);
                    }
                }
                if ts.is_empty() {
                    spans.push(Span::Cubic { control_one: c1, control_two: c2, end: p3 });
                    cur = p3;
                    continue;
                }
                let mut children: Vec<(Point, Point, Point, u8)> = vec![];
                let (mut sp0, mut sc1, mut sc2, se) = (cur, c1, c2, p3);
                let mut t0 = 0.0;
                for &(t, ax) in &ts {
                    let tt = ((t - t0) / (1.0 - t0)).clamp(0.0, 1.0);
                    let ((fc1, fc2, fend), (nc1, nc2)) = split_cubic_at(sp0, sc1, sc2, se, tt);
                    children.push((fc1, fc2, fend, ax));
                    sp0 = fend; sc1 = nc1; sc2 = nc2; t0 = t;
                }
                children.push((sc1, sc2, se, 3));
                let mut outc: Vec<(Point, Point, Point, u8)> =
                    children.iter().map(|&(a, b, c, ax)| (rd(a), rd(b), rd(c), ax)).collect();
                for k in 0..outc.len() - 1 {
                    let node = outc[k].2;
                    match outc[k].3 {
                        1 => { outc[k].1.x = node.x; outc[k + 1].0.x = node.x; }
                        2 => { outc[k].1.y = node.y; outc[k + 1].0.y = node.y; }
                        _ => {}
                    }
                }
                for (a, b, c, _) in outc {
                    spans.push(Span::Cubic { control_one: a, control_two: b, end: c });
                }
                cur = p3;
            }
        }
    }
    ReferenceRing { start: ring.start, spans }
}


// Junction extrema: when an
// existing junction node between two spans sits at a local x/y extremum,
// the handles on either side are pinned to the node's axis coordinate.
// Guarded: if pinning moves the cubic more than 1.0 font unit (16-sample
// pointwise check) the handle keeps its fitted position.
fn cubic_eval(p0: Point, c1: Point, c2: Point, p3: Point, t: f64) -> Point {
    let mt = 1.0 - t;
    Point {
        x: mt * mt * mt * p0.x + 3.0 * mt * mt * t * c1.x + 3.0 * mt * t * t * c2.x + t * t * t * p3.x,
        y: mt * mt * mt * p0.y + 3.0 * mt * mt * t * c1.y + 3.0 * mt * t * t * c2.y + t * t * t * p3.y,
    }
}

fn pin_junction_extrema(ring: &mut ReferenceRing) {
    // No env switch: extrema pinning is part of the normal route and is never
    // skipped by an environment condition.
    let n = ring.spans.len();
    if n < 2 {
        return;
    }
    let ends: Vec<Point> = ring
        .spans
        .iter()
        .map(|s| match s {
            Span::Line { end } | Span::Cubic { end, .. } => *end,
        })
        .collect();
    for i in 0..n {
        let node = ends[i];
        let prev_end = if i == 0 { ring.start } else { ends[i - 1] };
        let next_end = ends[(i + 1) % n];
        for comp in 0..2 {
            let (v, a, b) = if comp == 0 {
                (node.x, prev_end.x, next_end.x)
            } else {
                (node.y, prev_end.y, next_end.y)
            };
            let is_max = v >= a && v >= b && (v > a || v > b);
            let is_min = v <= a && v <= b && (v < a || v < b);
            if !is_max && !is_min {
                continue;
            }
            // pin prev span's control_two and this span's control_one on comp
            for which in 0..2 {
                let idx = if which == 0 { (i + n - 1) % n } else { i };
                let is_c2 = which == 0;
                let orig = match &ring.spans[idx] {
                    Span::Cubic { control_one, control_two, .. } => {
                        if is_c2 { *control_two } else { *control_one }
                    }
                    _ => continue,
                };
                let pinned = if comp == 0 {
                    Point { x: v, y: orig.y }
                } else {
                    Point { x: orig.x, y: v }
                };
                if pinned == orig {
                    continue;
                }
                // deviation guard on the affected cubic
                let (p0, c1, c2, p3) = match &ring.spans[idx] {
                    Span::Cubic { control_one, control_two, end } => {
                        let p0 = if idx == 0 { ring.start } else { ends[idx - 1] };
                        (p0, *control_one, *control_two, *end)
                    }
                    _ => unreachable!(),
                };
                let (nc1, nc2) = if is_c2 { (c1, pinned) } else { (pinned, c2) };
                let mut maxd = 0.0f64;
                for k in 1..16 {
                    let t = k as f64 / 16.0;
                    let a = cubic_eval(p0, c1, c2, p3, t);
                    let bpt = cubic_eval(p0, nc1, nc2, p3, t);
                    maxd = maxd.max((a.x - bpt.x).hypot(a.y - bpt.y));
                }
                if maxd > 1.0 {
                    continue;
                }
                if let Span::Cubic { control_one, control_two, .. } = &mut ring.spans[idx] {
                    if is_c2 { *control_two = pinned; } else { *control_one = pinned; }
                }
            }
        }
    }
}

fn near(a: Point, b: Point, tol: f64) -> bool {
    (a.x - b.x).hypot(a.y - b.y) <= tol
}

/// Post-fit emission hygiene: removes spans that add no shape and normalizes
/// signed zeros. A span is zero-length when its end is within `tol` of the
/// running point and, for a cubic, both controls are too (a cubic that loops
/// away is real geometry and stays). Closure is preserved: if the last end is
/// within `tol` of the start it is snapped to the start exactly. A ring that
/// would lose all spans is returned unchanged. `fit_captured` calls it with
/// tol 0.0: points are already integer after rd(), so only exact coincidence
/// is removed. Retracted handles of real cubics are not touched.
pub fn clean_emitted_ring(ring: ReferenceRing, tol: f64) -> ReferenceRing {
    let original = ring.clone();
    let nz = |p: Point| Point { x: p.x + 0.0, y: p.y + 0.0 }; // -0.0 + 0.0 == +0.0
    let ring = ReferenceRing {
        start: nz(ring.start),
        spans: ring.spans.into_iter().map(|s| match s {
            Span::Line { end } => Span::Line { end: nz(end) },
            Span::Cubic { control_one, control_two, end } =>
                Span::Cubic { control_one: nz(control_one), control_two: nz(control_two), end: nz(end) },
        }).collect(),
    };
    let start = ring.start;
    let mut cur = start;
    let mut spans: Vec<Span> = Vec::with_capacity(ring.spans.len());
    for sp in ring.spans {
        match &sp {
            Span::Line { end } if near(*end, cur, tol) => continue,
            Span::Cubic { control_one, control_two, end }
                if near(*end, cur, tol) && near(*control_one, cur, tol) && near(*control_two, cur, tol) =>
            {
                let _ = end;
                continue;
            }
            _ => {}
        }
        cur = match &sp { Span::Line { end } | Span::Cubic { end, .. } => *end };
        spans.push(sp);
    }
    if let Some(last) = spans.last_mut() {
        let e = match last { Span::Line { end } | Span::Cubic { end, .. } => end };
        if *e != start && near(*e, start, tol) { *e = start; }
    }
    // Guard: a ring that would lose all spans is returned unchanged (the
    // caller's own degenerate-ring policy decides), never silently emptied.
    if spans.is_empty() { return original; }
    ReferenceRing { start, spans }
}

/// Snap every coordinate of a ring to `grid` (e.g. 1.0 = integer font units),
/// then drop spans that became zero-length. Use at the writer, where integer
/// rounding creates them. Exact coincidence only (tol 0).
pub fn round_and_clean_ring(ring: &ReferenceRing, grid: f64) -> ReferenceRing {
    let q = |p: Point| Point { x: (p.x / grid).round() * grid, y: (p.y / grid).round() * grid };
    // Readable-joint rule (declared convention): endpoints round
    // independently per coordinate, so a control point closer than one full
    // lattice step to its anchor can collapse onto it (end=274.49 -> 274,
    // ctrl=273.78 -> 274) and the joint turns unreadable (zero handle =
    // unavailable in the joint curvature metric). A collapsed control is
    // nudged to the nearest lattice point one full step along the
    // pre-rounding handle direction (chord direction when the handle is
    // exactly zero): one step guarantees a distinct lattice point, and the
    // move is bounded by the lattice quantum the emission itself quantizes
    // to. Spans without a collapse round bit-identically to before.
    let mut spans: Vec<Span> = Vec::with_capacity(ring.spans.len());
    let (mut pre_cur, mut cur) = (ring.start, q(ring.start));
    for s in &ring.spans {
        match s {
            Span::Line { end } => {
                let e = q(*end);
                spans.push(Span::Line { end: e });
                pre_cur = *end; cur = e;
            }
            Span::Cubic { control_one, control_two, end } => {
                let (mut qc1, mut qc2, qe) = (q(*control_one), q(*control_two), q(*end));
                let chord = Point { x: end.x - pre_cur.x, y: end.y - pre_cur.y };
                // A cubic that collapses to a POINT (end rounds onto the
                // start as well) is a sub-lattice feature, not a broken
                // joint: leave it for the cleaner's established removal
                // rule. Nudges apply only to spans with a nonzero rounded
                // chord.
                if qe != cur && qc1 == cur {
                    let d = Point { x: control_one.x - pre_cur.x, y: control_one.y - pre_cur.y };
                    let d = if d.x == 0.0 && d.y == 0.0 { chord } else { d };
                    let n = d.x.hypot(d.y);
                    if n > 0.0 { qc1 = q(Point { x: cur.x + grid * d.x / n, y: cur.y + grid * d.y / n }); }
                }
                if qe != cur && qc2 == qe {
                    let d = Point { x: end.x - control_two.x, y: end.y - control_two.y };
                    let d = if d.x == 0.0 && d.y == 0.0 { chord } else { d };
                    let n = d.x.hypot(d.y);
                    if n > 0.0 { qc2 = q(Point { x: qe.x - grid * d.x / n, y: qe.y - grid * d.y / n }); }
                }
                spans.push(Span::Cubic { control_one: qc1, control_two: qc2, end: qe });
                pre_cur = *end; cur = qe;
            }
        }
    }
    clean_emitted_ring(ReferenceRing { start: q(ring.start), spans }, 0.0)
}

/// Signed area x2 (shoelace) of an emitted ring's on-curve polygon.
fn emitted_area2(ring: &ReferenceRing) -> f64 {
    let mut a = 0.0;
    let mut cur = ring.start;
    for s in &ring.spans {
        let e = match s { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
        a += cur.x * e.y - cur.y * e.x;
        cur = e;
    }
    a
}

/// Reverse a closed all-Line ring, keeping its start point: the same polygon
/// walked the other way. Speck minimal contours are Line spans by
/// construction; used to restore exterior (positive-area) winding when
/// integer rounding flipped the captured orientation.
fn reverse_line_ring(ring: &ReferenceRing) -> ReferenceRing {
    let mut pts: Vec<Point> = Vec::with_capacity(ring.spans.len() + 1);
    pts.push(ring.start);
    for s in &ring.spans {
        let e = match s { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
        pts.push(e);
    }
    let mut spans: Vec<Span> = Vec::with_capacity(ring.spans.len());
    for p in pts[1..pts.len() - 1].iter().rev() {
        spans.push(Span::Line { end: *p });
    }
    spans.push(Span::Line { end: ring.start });
    ReferenceRing { start: ring.start, spans }
}

pub fn fit_captured(
    rings: &[CapturedRing],
    scale: f64,
    policy: &FitPolicy,
) -> (Vec<ReferenceRing>, usize, bool, usize) {
    let _raw_ring_scope = RawRingScope::enter();
    let (rings, count, fallback, dropped, _) = fit_captured_economy_candidate(rings, scale, policy, false);
    (rings, count, fallback, dropped)
}

/// Canonical fitting with traceable geometry-identical economy decisions.
/// Each record is paired with its output ring index.
pub fn fit_captured_with_economy(
    rings: &[CapturedRing], scale: f64, policy: &FitPolicy,
) -> (Vec<ReferenceRing>, usize, bool, usize, Vec<(usize, crate::economy::EconomyDecision)>) {
    fit_captured_economy_candidate(rings, scale, policy, true)
}
fn fit_captured_economy_candidate(
    rings: &[CapturedRing], scale: f64, policy: &FitPolicy, enable_economy: bool,
) -> (Vec<ReferenceRing>, usize, bool, usize, Vec<(usize, crate::economy::EconomyDecision)>) {
    // Ledger-derived status, see fit_ring_db_economy_candidate.
    let mut fevents=Vec::new();
    let mut astubs=Vec::new();
    let mut declined=Vec::new();
    let (out,count,_mech_fb,dropped,decisions)=fit_captured_economy_observed(rings,scale,policy,enable_economy,None,&mut fevents,&mut astubs,&mut declined,&mut Vec::new());
    (out,count,!fevents.is_empty()||!astubs.is_empty(),dropped,decisions)
}
/// Measurement-only baseline observer; does not activate economy candidates.
pub fn fit_captured_with_provenance(
    rings:&[CapturedRing],scale:f64,policy:&FitPolicy,
) -> (Vec<ReferenceRing>,usize,bool,usize,Vec<crate::source_provenance::RingProvenance>) {
    let mut records=Vec::new();
    let mut fevents=Vec::new();
    let mut astubs=Vec::new();
    let mut declined=Vec::new();
    // Ledger-derived status, see fit_ring_db_economy_candidate.
    let (out,count,_mech_fb,dropped,_)=fit_captured_economy_observed(rings,scale,policy,false,Some(&mut records),&mut fevents,&mut astubs,&mut declined,&mut Vec::new());
    (out,count,!fevents.is_empty()||!astubs.is_empty(),dropped,records)
}
/// Canonical fitting + typed per-point Line fallback ledger: one event per
/// Line span emitted from an unresolved curve-intended region, with reason.
/// NOTE (A-PRIME): AmbiguousStub records NEVER appear in fevents; they ARE
/// included in the returned fallback bool. List consumers must be stub-aware:
/// use fit_captured_with_typed_ledgers.
pub fn fit_captured_with_fallback_events(
    rings:&[CapturedRing],scale:f64,policy:&FitPolicy,
) -> (Vec<ReferenceRing>,usize,bool,usize,Vec<FallbackEvent>) {
    let mut fevents=Vec::new();
    let mut astubs=Vec::new();
    let mut declined=Vec::new();
    // Ledger-derived status, see fit_ring_db_economy_candidate.
    let (out,count,_mech_fb,dropped,_)=fit_captured_economy_observed(rings,scale,policy,false,None,&mut fevents,&mut astubs,&mut declined,&mut Vec::new());
    (out,count,!fevents.is_empty()||!astubs.is_empty(),dropped,fevents)
}
/// Canonical fitting + BOTH typed ledgers: the per-point Line fallback
/// ledger AND the A-PRIME typed ambiguity ledger. Ambiguous stubs are not
/// fallback events and never join fevents; they are typed resolutions
/// ("tipli belirsiz", not "resolved") with their class and within-one-pixel
/// justification, surfaced here so no write is laundered out of the record.
pub fn fit_captured_with_typed_ledgers(
    rings:&[CapturedRing],scale:f64,policy:&FitPolicy,
) -> (Vec<ReferenceRing>,usize,bool,usize,Vec<FallbackEvent>,Vec<AmbiguousStub>,Vec<DeclinedAmbiguity>) {
    let (out,count,fb,dropped,fevents,astubs,declined,_fprov)=fit_captured_with_span_provenance(rings,scale,policy);
    (out,count,fb,dropped,fevents,astubs,declined)
}

/// fit_captured_with_typed_ledgers plus the r282 audit-only per-span fallback
/// provenance rows (one row per finalized fallback event, in event order).
pub fn fit_captured_with_span_provenance(
    rings:&[CapturedRing],scale:f64,policy:&FitPolicy,
) -> (Vec<ReferenceRing>,usize,bool,usize,Vec<FallbackEvent>,Vec<AmbiguousStub>,Vec<DeclinedAmbiguity>,Vec<FallbackSpanProvenance>) {
    let mut fevents=Vec::new();
    let mut astubs=Vec::new();
    let mut declined=Vec::new();
    let mut fprov=Vec::new();
    let (out,count,_mech_fb,dropped,_)=fit_captured_economy_observed(rings,scale,policy,false,None,&mut fevents,&mut astubs,&mut declined,&mut fprov);
    (out,count,!fevents.is_empty()||!astubs.is_empty(),dropped,fevents,astubs,declined,fprov)
}
fn fit_captured_economy_observed(
    rings:&[CapturedRing],scale:f64,policy:&FitPolicy,enable_economy:bool,
    mut provenance:Option<&mut Vec<crate::source_provenance::RingProvenance>>,
    fevents:&mut Vec<FallbackEvent>,
    astubs:&mut Vec<AmbiguousStub>,
    declined:&mut Vec<DeclinedAmbiguity>,
    fprov:&mut Vec<FallbackSpanProvenance>,
) -> (Vec<ReferenceRing>,usize,bool,usize,Vec<(usize,crate::economy::EconomyDecision)>) {
    let _raw_ring_scope = RawRingScope::enter();
    let mut economy_decisions=Vec::new();
    let mut out = vec![];
    let mut total_spans = 0;
    let mut any_fb = false;
    let mut dropped = 0usize;
    for (captured_ring_index,r) in rings.iter().enumerate() {
        // Sub-pixel specks: the half-pixel-square capture threshold no
        // longer DROPS a small ring - it CLASSIFIES it. The class predicate
        // stays the shared capture::is_degenerate_ring (the curve-stress
        // measurement exemption is the same boundary, kept in one place
        // there). A ring with positive capture-polygon area below half a
        // grid cell carried measured ink; it ships as its natural minimal
        // valid contour: the ring's OWN captured polygon as Line spans
        // (nothing invented - the measured boundary itself), in the same
        // validity class as an AreaCollapseRestored ring. A hole-flagged
        // sub-pixel ring is a speck too: it ships as its own measured
        // minimal contour, hole-wound (negative signed area - the contour
        // is the measured negative space, never a filled blob), and the
        // hole subset is counted in the typed always-output
        // `speck_retained_hole` row. The contour takes the main emission path's rounding and
        // hygiene: points are rounded to the integer emission grid (rd), the
        // ring is routed through clean_emitted_ring, and the emitted contour
        // is normalized to the capture hole flag (holes negative-wound,
        // exteriors positive-wound), so an
        // emitted speck is on-grid, closed, flag-wound and free of
        // zero-length spans exactly like a fitted ring. A speck whose
        // rounded points all collapse onto one grid point has no
        // representation at the grid (the representation base is the grid
        // cell itself, the declared convention) - only such truly
        // unrepresentable captures still count in `dropped`. Bypassing
        // relocation and the fitter is what guarantees no per-point fallback
        // from specks (export-gate condition). Zero-area ink (a collinear
        // streak) is NOT a speck: it takes the normal path, where the
        // zero-area emission guard (AreaCollapseRestored) owns it.
        let captured_area_px2 = crate::capture::ring_area2(&r.points).abs() / 2.0;
        if crate::capture::is_degenerate_ring(&r.points) && captured_area_px2 > 0.0 {
            let pts: Vec<Point> = r.points.iter().map(|p| rd(Point { x: p.x * scale, y: p.y * scale })).collect();
            let start = pts[0];
            if pts.iter().all(|p| *p == start) {
                SPECK_DROPPED_COLLAPSE.with(|c| c.set(c.get() + 1));
                dropped += 1;
                continue;
            }
            // Rounded points collapsed onto one lattice line: zero signed
            // area at the emission grid, no grid representation (the same
            // grid-unrepresentable class as the single-point collapse).
            // Deliberate asymmetry: PRE-round zero-area ink (a collinear
            // streak) is not dropped here - it takes the normal path, where
            // the zero-area emission guard (AreaCollapseRestored) restores
            // it. POST-round zero area means the measured ink has no
            // representation on the integer grid at all, so it drops.
            if crate::capture::ring_area2(&pts) == 0.0 {
                SPECK_DROPPED_COLLAPSE.with(|c| c.set(c.get() + 1));
                dropped += 1;
                continue;
            }
            // The ledger records the CAPTURE-space area (an input
            // measurement), so record_speck correctly precedes emission
            // hygiene: clean_emitted_ring only removes zero-length spans,
            // which cannot change signed area, so the pre-clean checks
            // (not-all-equal points, nonzero polygon area) still hold for
            // the cleaned ring.
            // A hole-flagged speck is retained like any other: it measured
            // NEGATIVE space (a counter), and it ships hole-wound (always
            // output, never dropped for its class). The hole subset is
            // counted in the typed sub_pixel_speck_retained_hole row, and the
            // counter is incremented only here - AFTER the grid-collapse
            // checks - so the row measures retained, not classified, specks
            // (classified = retained + sub_pixel_speck_dropped).
            if r.hole {
                SPECK_RETAINED_HOLE.with(|c| c.set(c.get() + 1));
            }
            record_speck(captured_area_px2);
            let mut spans: Vec<Span> = Vec::with_capacity(pts.len());
            for p in &pts[1..] {
                spans.push(Span::Line { end: *p });
            }
            spans.push(Span::Line { end: start });
            let ring = clean_emitted_ring(ReferenceRing { start, spans }, 0.0);
            // Winding follows the capture hole flag: a hole ships negative-wound
            // (interior), an exterior positive-wound. rd rounding and
            // clean_emitted_ring preserve the sign, so a mismatch means the
            // captured order itself disagrees with the flag - normalize.
            let ring = if (emitted_area2(&ring) < 0.0) == r.hole { ring } else { reverse_line_ring(&ring) };
            total_spans += ring.spans.len();
            SPECK_SPANS.with(|c| c.set(c.get() + ring.spans.len()));
            if let Some(records)=provenance.as_mut(){records.push(crate::source_provenance::bind_emission(captured_ring_index,Vec::new(),&ring));}
            out.push(ring);
            continue;
        }
        if captured_area_px2 == 0.0 && r.points.len() < 3 {
            dropped += 1;
            continue;
        }
        // Vertex relocation (pixel space, before scaling): corner vertices
        // move to the unit-square optimum against their adjacent edge lines.
        let mut rp = r.points.clone();
        let moved = relocate_corners_verified(&mut rp, &r.corners, &r.raw, 1.0);
        RELOC_MOVED.with(|c| c.set(c.get() + moved));
        let pts: Vec<Point> = rp
            .iter()
            .map(|p| Point {
                x: p.x * scale,
                y: p.y * scale,
            })
            .collect();
        // F2/P0: whole-ring circle hypothesis first (evidence-gated; tol =
        // capture default rdp eps in font units); residue goes to the fit.
        if let Some(ring) = crate::form::recognize_circle_ring(&pts, &r.corners, r.hole, 1.0 * scale, 0.5 * scale) {
            total_spans += ring.spans.len();
            if let Some(records)=provenance.as_mut(){records.push(crate::source_provenance::bind_emission(captured_ring_index,Vec::new(),&ring));}
            out.push(ring);
            continue;
        }
        RAW_RING.with(|rr| *rr.borrow_mut() = r.raw.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect());
        corner_record_site_set_ring(captured_ring_index);
        let mut parents=Vec::new();let parent_records=if provenance.is_some(){Some(&mut parents)}else{None};
        let prov_start = fprov.len();
        let (ring,_ns,fb,decisions)=fit_ring_db_economy_observed(pts,r.corners.clone(),policy,dense_bound(scale,policy),1.0*scale,scale,enable_economy,parent_records,fevents, astubs, declined, fprov);
        for p in &mut fprov[prov_start..] { p.ring = captured_ring_index; }
        economy_decisions.extend(decisions.into_iter().map(|d| (out.len(), d)));
        let mut ring = ring;
        pin_junction_extrema(&mut ring);
        let ring = split_ring_at_extrema(ring);
        let ring = clean_emitted_ring(ring, 0.0);
        // Final straight sweep: downstream steps (extrema splitting, junction
        // pinning) can leave a long cubic whose handles sit within one source
        // pixel of its chord. A cubic stays inside its control polygon's
        // convex hull, so the whole curve hugs the chord within one pixel;
        // replacing it with its chord moves the outline by less than the
        // acquisition resolution. Emit Line. The primary straight-over-curve
        // pass cannot see these spans because they are born after it.
        let ring = {
            let px = scale; // one source pixel in font units
            let mut cur = ring.start;
            let mut spans = Vec::with_capacity(ring.spans.len());
            for sp in ring.spans.into_iter() {
                let next = match sp {
                    Span::Cubic { control_one, control_two, end } => {
                        let (dx, dy) = (end.x - cur.x, end.y - cur.y);
                        let l = dx.hypot(dy);
                        let sag = |c: &Point| (dx * (c.y - cur.y) - dy * (c.x - cur.x)).abs() / l.max(f64::EPSILON);
                        if l >= 6.0 * px && sag(&control_one) <= px && sag(&control_two) <= px {
                            STRAIGHT_SWEEP_CONVERTED.with(|c| c.set(c.get() + 1));
                            Span::Line { end }
                        } else {
                            Span::Cubic { control_one, control_two, end }
                        }
                    }
                    other => other,
                };
                cur = match next { Span::Line { end } => end, Span::Cubic { end, .. } => end };
                spans.push(next);
            }
            ReferenceRing { start: ring.start, spans }
        };
        // Zero-area emission guard (always-output contract; MARQ dash class):
        // a ring that carried measurable ink at capture (it passed the
        // degenerate-drop threshold above) must never ship collapsed to a
        // zero-area out-and-back line. Thin slivers (sub-tolerance streak
        // rows, e.g. marker-drawn dashes) lose every corner to the
        // stub-band derivation and fit to a chord there-and-back; the
        // measured area is then destroyed and the profiler sees no ink.
        // Guard: when the emitted ring's chord area is below the same
        // half-pixel-square capture threshold while the captured polygon
        // carried at least that much, re-emit the captured polygon as Line
        // spans (the source's own measured contour, no invented geometry)
        // and ledger a typed fallback event. Rings the fit represents with
        // real area are untouched, bit-identical.
        let ring = {
            let mut va2 = 0.0f64;
            {
                let mut cur = ring.start;
                let mut acc = |a: Point, b: Point| va2 += a.x * b.y - b.x * a.y;
                for sp in &ring.spans {
                    let end = match sp { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
                    acc(cur, end);
                    cur = end;
                }
                acc(cur, ring.start);
            }
            let scale2 = scale * scale;
            if va2.abs() / 2.0 < 0.5 * scale2 && captured_area_px2 >= 0.5 {
                let pts: Vec<Point> = r.points.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
                let mut spans: Vec<Span> = pts[1..].iter().map(|&p| Span::Line { end: p }).collect();
                spans.push(Span::Line { end: pts[0] });
                fevents.push(FallbackEvent { arc: captured_ring_index, s: 0, e: 0, reason: FallbackReason::AreaCollapseRestored, stop: None });
                // r282: ring-level event; the restored ring's own polygon
                // perimeter is the measured arc length (source pixels), chord
                // and deviation have no fragment to measure.
                let perim_px = { let mut l = 0.0f64; for w in pts.windows(2) { l += (w[1].x - w[0].x).hypot(w[1].y - w[0].y); } l += (pts[0].x - pts[pts.len() - 1].x).hypot(pts[0].y - pts[pts.len() - 1].y); l / scale };
                fprov.push(FallbackSpanProvenance { ring: captured_ring_index, arc: usize::MAX, s: 0, e: 0, chord_px: None, arc_len_px: Some(perim_px), max_dev_px: None, reason: FallbackReason::AreaCollapseRestored, stop: None, decline: None });
                any_fb = true;
                ReferenceRing { start: pts[0], spans }
            } else {
                ring
            }
        };
        if let Some(records)=provenance.as_mut(){records.push(crate::source_provenance::bind_emission(captured_ring_index,parents,&ring));}
        total_spans += ring.spans.len();
        any_fb |= fb;
        out.push(ring);
    }
    (out, total_spans, any_fb, dropped, economy_decisions)
}

#[cfg(test)]
mod extrema_plateau_tests {
    use super::*;

    fn pt(x: f64, y: f64) -> Point {
        Point { x, y }
    }

    /// Quantized semicircle-ish staircase chain: integer-grid samples with
    /// plateau runs longer than EXTREMA_WIN at the axis extrema.
    fn stair_arc(a: f64, b: f64, t0: f64, t1: f64, steps: usize) -> Vec<Point> {
        let mut out: Vec<Point> = vec![];
        for i in 0..=steps {
            let t = t0 + (t1 - t0) * (i as f64) / (steps as f64);
            let x = (a * t.cos()).round() * 4.0;
            let y = (b * t.sin()).round() * 4.0;
            let p = pt(x, y);
            if out.last() != Some(&p) {
                out.push(p);
            }
        }
        out
    }

    #[test]
    fn plateau_extrema_found_on_staircase_arc() {
        // three-quarter oval arc: covers top, left, bottom extrema; each is a
        // multi-sample constant-axis plateau (2.0-quantized grid)
        // span 0.5..5.0 rad: interior y-max (pi/2), x-min (pi), y-min (3pi/2);
        // endpoints at 0.5 and 5.0 rad are NOT extrema
        let arc = stair_arc(60.0, 45.0, 0.5, 5.0, 400);
        let xs = extrema_splits(&arc, 1.0);
        let axes: Vec<usize> = vec![];
        let _ = axes;
        assert!(xs.len() >= 3, "expected >=3 landmarks, got {:?}", xs);
        // every landmark index is interior and sorted unique
        for w in xs.windows(2) {
            assert!(w[0].0 < w[1].0);
        }
        // landmarks sit at actual axis extrema of the chain
        let ymax = arc.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
        let ymin = arc.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
        let xmin = arc.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
        let at = |i: usize| arc[i];
        assert!(xs.iter().any(|&(i, _)| at(i).y == ymax), "no y-max landmark: {:?}", xs);
        assert!(xs.iter().any(|&(i, _)| at(i).y == ymin), "no y-min landmark: {:?}", xs);
        assert!(xs.iter().any(|&(i, _)| at(i).x == xmin), "no x-min landmark: {:?}", xs);
        // tangents are axis-aligned unit directions
        for &(_, t) in &xs {
            assert!((t.x.hypot(t.y) - 1.0).abs() < 1e-9);
            assert!(t.x == 0.0 || t.y == 0.0);
        }
    }

    #[test]
    fn monotone_staircase_has_no_extremum() {
        let mut arc: Vec<Point> = vec![];
        for i in 0..40 {
            let p = pt((i * 2) as f64, ((i * 2) + (i % 2)) as f64);
            if arc.last() != Some(&p) {
                arc.push(p);
            }
        }
        assert!(extrema_splits(&arc, 1.0).is_empty());
    }

    #[test]
    fn constant_axis_ring_side_is_not_an_extremum() {
        // straight vertical staircase: x constant, y monotone -> no landmark
        let arc: Vec<Point> = (0..30).map(|i| pt(10.0, (i * 2) as f64)).collect();
        assert!(extrema_splits(&arc, 1.0).is_empty());
    }

    #[test]
    fn tiny_arc_returns_empty() {
        let arc = vec![pt(0.0, 0.0), pt(2.0, 4.0), pt(4.0, 0.0)];
        assert!(extrema_splits(&arc, 1.0).is_empty());
    }

    #[test]
    fn duplicate_zero_spans_are_deterministic() {
        let mut arc = stair_arc(40.0, 30.0, 0.2, 2.8, 120);
        // inject duplicate-zero spans (repeated consecutive samples)
        let mut dup: Vec<Point> = vec![];
        for (i, p) in arc.iter().enumerate() {
            dup.push(*p);
            if i % 7 == 0 {
                dup.push(*p);
                dup.push(*p);
            }
        }
        arc = dup;
        let a = extrema_splits(&arc, 1.0);
        let b = extrema_splits(&arc, 1.0);
        assert_eq!(a, b);
        assert!(!a.is_empty());
    }

    #[test]
    fn smooth_arc_landmarks_unchanged() {
        // no plateaus: dense smooth parabola arc -> landmark at the vertex
        let arc: Vec<Point> = (0..=80)
            .map(|i| {
                let x = i as f64 * 4.0 - 160.0;
                pt(x, 200.0 - x * x / 32.0)
            })
            .collect();
        let xs = extrema_splits(&arc, 1.0);
        assert_eq!(xs.len(), 1, "{:?}", xs);
        let (i, t) = xs[0];
        assert_eq!(i, 40, "vertex index");
        assert_eq!(t.y, 0.0, "y-extremum: axis-aligned horizontal tangent");
    }

    #[test]
    fn cyclic_finds_seam_crossing_plateau_once() {
        // closed staircase oval ring; rotate so the seam (index 0) sits in the
        // MIDDLE of the x-max plateau
        let mut ring = stair_arc(50.0, 35.0, 0.0, std::f64::consts::TAU, 360);
        ring.pop(); // drop duplicated closure sample
        // find an x-max plateau sample and rotate the seam into it
        let xmax = ring.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);
        let at_xmax = ring.iter().position(|p| p.x == xmax).unwrap();
        ring.rotate_left(at_xmax);
        assert_eq!(ring[0].x, xmax, "seam sits on the x-max plateau");
        let xs = extrema_splits_cyclic(&ring, 1.0);
        let n = ring.len();
        // no duplicate indices; all in range
        let mut idx: Vec<usize> = xs.iter().map(|&(i, _)| i).collect();
        idx.sort();
        idx.dedup();
        assert_eq!(idx.len(), xs.len(), "duplicate landmarks: {:?}", xs);
        for &i in &idx {
            assert!(i < n);
        }
        // the four oval landmarks: x-max (at the seam), y-max, x-min, y-min
        let ymax = ring.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
        let ymin = ring.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
        let xmin = ring.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
        let at = |i: usize| ring[i];
        assert!(xs.iter().any(|&(i, _)| at(i).x == xmax), "seam x-max missing: {:?}", xs);
        assert!(xs.iter().any(|&(i, _)| at(i).y == ymax), "{:?}", xs);
        assert!(xs.iter().any(|&(i, _)| at(i).x == xmin), "{:?}", xs);
        assert!(xs.iter().any(|&(i, _)| at(i).y == ymin), "{:?}", xs);
        // seam plateau emitted exactly once
        assert_eq!(xs.iter().filter(|&&(i, _)| at(i).x == xmax).count(), 1, "{:?}", xs);
    }

    #[test]
    fn cyclic_constant_ring_is_bounded_empty() {
        let ring: Vec<Point> = (0..24).map(|_| pt(6.0, 6.0)).collect();
        assert!(extrema_splits_cyclic(&ring, 1.0).is_empty());
    }

    /// Call-chain proof (chief 23:38): a corners-empty synthetic closed ring
    /// through the REAL ring path (fit_ring_db_economy_observed) must not
    /// reach the fitter as one whole-ring arc: the seam rotates onto a cyclic
    /// landmark and the open machinery emits >=2 landmark-delimited child
    /// spans whose junction nodes sit at the ring's axis extrema.
    #[test]
    fn corners_empty_closed_ring_splits_at_landmarks_call_chain() {
        let mut ring = stair_arc(50.0, 35.0, 0.0, std::f64::consts::TAU, 360);
        ring.pop(); // drop the duplicated closure sample: true closed ring
        // move the seam off every landmark so the rotation is observable
        let xmax = ring.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);
        let at = ring.iter().position(|p| p.x == xmax).unwrap();
        let seam = (at + 5) % ring.len();
        ring.rotate_left(seam);
        let pol = FitPolicy { squared_error: 1.0e9, max_refits: 2 };
        let mut fe = vec![];
        let (out, _ns, fb, _dec) =
            fit_ring_db_economy_observed(ring.clone(), vec![], &pol, 1.0e9, 1.0, 1.0, false, None, &mut fe, &mut Vec::new(), &mut Vec::new(), &mut Vec::new());
        let spans = out.spans.len();
        assert!(spans >= 2, "whole-ring single arc reached emission: {} span(s)", spans);
        // fallback must be absent on BOTH signals: the boolean flag and the
        // typed event ledger (a silent-flag regression must not pass)
        assert!(!fb, "no fallback expected with a generous gate");
        assert!(fe.is_empty(), "fallback ledger not empty: {} event(s)", fe.len());
        // span junction nodes must include the ring's axis extrema (landmark
        // children), not an arbitrary seam cut
        let ymax = ring.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
        let ymin = ring.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
        let xmin = ring.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
        let mut nodes: Vec<Point> = vec![out.start];
        for sp in &out.spans {
            match sp {
                Span::Line { end } => nodes.push(*end),
                Span::Cubic { end, .. } => nodes.push(*end),
            }
        }
        // typed per-axis asserts: an x-extremum must match on x, a y-extremum
        // on y - equal-valued extrema must not cross-satisfy the wrong axis.
        // Post-fit junction refinement (refine_junction_qf, rad = 1.0 fu) may
        // move a landmark node within its move radius to cut squared
        // deviation, so the match allows exactly that radius on the extremum
        // sample itself.
        // plateau extrema: ANY sample achieving the extremal coordinate counts
        let near_any = |ext: Vec<Point>| ext.iter().any(|e| nodes.iter().any(|p| (p.x - e.x).abs() <= 1.0 && (p.y - e.y).abs() <= 1.0 && (p.x == e.x || p.y == e.y)));
        let at_x = |v: f64| ring.iter().cloned().filter(|p| p.x == v).collect::<Vec<_>>();
        let at_y = |v: f64| ring.iter().cloned().filter(|p| p.y == v).collect::<Vec<_>>();
        assert!(near_any(at_x(xmax)), "no junction at x-max ({}) - nodes: {:?}", xmax, nodes);
        assert!(near_any(at_x(xmin)), "no junction at x-min ({}) - nodes: {:?}", xmin, nodes);
        assert!(near_any(at_y(ymax)), "no junction at y-max ({}) - nodes: {:?}", ymax, nodes);
        assert!(near_any(at_y(ymin)), "no junction at y-min ({}) - nodes: {:?}", ymin, nodes);
    }
}

#[cfg(test)]
mod solver_subgrid_oracle {
    use super::*;

    /// Sub-grid typed stop: a sub-grid arc (bbox inside one acquisition
    /// lattice cell on both axes) must stop as the typed SubGridSpan Line,
    /// never recurse silently. The stop covers sub-grid arcs produced by
    /// recursion; whole-ring sub-grid is the degenerate-drop gate's job.
    /// This test drives the recursion path directly.
    #[test]
    fn sub_grid_arc_emits_typed_stop_not_recursion() {
        // arc bbox 0.4x0.4 << 1px grid, impossible gate forces the split path
        let arc = vec![
            Point { x: 0.0, y: 0.0 },
            Point { x: 0.2, y: 0.4 },
            Point { x: 0.4, y: 0.2 },
            Point { x: 0.3, y: 0.0 },
        ];
        let policy = FitPolicy { squared_error: 1.0e-9, max_refits: 8 };
        let mut fspans = vec![];
        let mut fb = false;
        let mut events = vec![];
        fit_gated(&arc, &policy, &mut fspans, 0, &mut fb, 1.0e-9, 1.0e-9, 1.0, 2, 0, 0, None, None, false, None, &mut events, &mut Vec::new(), None, &mut Vec::new(), fit_run);
        assert!(
            events.iter().any(|e| e.reason == FallbackReason::SubGridSpan),
            "expected SubGridSpan event, got {:?}", events.iter().map(|e| e.reason).collect::<Vec<_>>()
        );
        assert!(!fspans.is_empty(), "span must still be emitted");
    }
}

#[cfg(test)]
mod extrema_window_swing_tests {
    use super::*;

    /// EXTREMA_MIN_SWING correctness oracle (chief decision): the r=128
    /// half-circle rasterized at 128 steps carries a wide y-max plateau whose
    /// two-sample window swing is 1 fu - under the retired 3.0 literal the
    /// detector missed it entirely (no presplit, no forced axis tangent, the
    /// whole arc hit the solver in one piece). With the derived threshold
    /// (one lattice step) and the hp = sqrt(R*g) measurement window the
    /// extremum must be found with an exact axis-aligned tangent.
    #[test]
    fn wide_plateau_extremum_detected_on_r128_half_circle() {
        let r = 128.0f64;
        let mut pts: Vec<Point> = vec![];
        for i in 0..=128 {
            let t = (i as f64) / 128.0 * std::f64::consts::PI;
            let p = Point { x: (r * t.cos()).round(), y: (r * t.sin()).round() };
            if pts.last() != Some(&p) { pts.push(p); }
        }
        let ymax = pts.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
        let plateau = pts.iter().filter(|p| p.y == ymax).count();
        assert!(plateau >= 7, "fixture drift: plateau {} samples", plateau);
        let xs = extrema_splits(&pts, 1.0);
        assert_eq!(xs.len(), 1, "half circle: exactly one interior axis extremum, got {:?}", xs);
        let (i, t) = xs[0];
        assert_eq!(pts[i].y, ymax, "landmark must sit on the extremal sample");
        assert!(t.y == 0.0 && t.x.abs() == 1.0, "y-max extremum tangent must be horizontal axis unit, got ({},{})", t.x, t.y);
    }

    /// Lattice-threshold boundary: an extremum whose both-side swing is below
    /// one lattice step is not measurable evidence and must be rejected (the
    /// threshold is g, not zero: sub-step differences can quantize away).
    #[test]
    fn sub_lattice_swing_is_not_evidence() {
        let mut pts: Vec<Point> = vec![];
        for i in -16..=16 {
            let x = i as f64;
            let y = (x * x / 4096.0).round();
            let p = Point { x, y };
            if pts.last() != Some(&p) { pts.push(p); }
        }
        assert!(extrema_splits(&pts, 1.0).is_empty(), "sub-lattice swing must not produce a landmark");
    }
}

#[cfg(test)]
mod reloc_tests {
    use super::*;

    fn ring_l() -> (Vec<Point>, Vec<usize>) {
        // L-shaped ring: horizontal edge y=0 from (0,0) to (10,0),
        // vertical edge x=10 from (10,0) to (10,10); corner at index 5 = (10,0)
        let mut pts = vec![];
        for i in 0..=5 {
            pts.push(Point { x: 2.0 * i as f64, y: 0.0 });
        }
        for i in 1..=5 {
            pts.push(Point { x: 10.0, y: 2.0 * i as f64 });
        }
        let corners = vec![0, 5, 10];
        (pts, corners)
    }

    #[test]
    fn exact_corner_stays() {
        let (mut pts, corners) = ring_l();
        let moved = relocate_corners(&mut pts, &corners);
        // exact orthogonal geometry: intersection equals the corner itself
        assert!((pts[5].x - 10.0).abs() < 1e-9 && (pts[5].y - 0.0).abs() < 1e-9);
        let _ = moved; // f64 noise may or may not count; position is the contract
    }

    #[test]
    fn subpixel_crossing_recovers() {
        // two lines y=0.3x and y=-0.3x+6 meeting at (10,3): corner vertex sits
        // at integer (10,3) already; shift so true crossing is (10.25, 3.0):
        // edges y=0.3x-0.075 and y=-0.3x+6.075 cross at x=10.25,y=3.0
        let mut pts = vec![];
        for i in 0..=5 {
            let x = 2.0 * i as f64;
            pts.push(Point { x, y: 0.3 * x - 0.075 });
        }
        for i in 1..=5 {
            let x = 10.0 - 2.0 * i as f64;
            pts.push(Point { x, y: -0.3 * x + 6.075 });
        }
        let corners = vec![0, 5, 10];
        let moved = relocate_corners(&mut pts, &corners);
        assert!(moved >= 1, "expected the corner to move");
        // inclusive TLS fit (corner belongs to both edge runs) recovers the
        // crossing partially toward (10.25, 3.0); potrace semantics, not exact
        assert!(pts[5].x > 10.0 && pts[5].x <= 10.25 + 1e-9, "x={}", pts[5].x);
        assert!(pts[5].y > 2.925 && pts[5].y <= 3.0 + 1e-9, "y={}", pts[5].y);
    }

    #[test]
    fn collinear_edges_no_nan() {
        // corner between two collinear runs: singular Q, orthogonal fallback
        let mut pts: Vec<Point> = (0..=10).map(|i| Point { x: i as f64, y: 5.0 }).collect();
        let corners = vec![0, 5, 10];
        let _ = relocate_corners(&mut pts, &corners);
        assert!(pts[5].x.is_finite() && pts[5].y.is_finite());
        assert!((pts[5].x - 5.0).abs() <= 0.5 && (pts[5].y - 5.0).abs() <= 0.5);
    }

    #[test]
    fn empty_corners_noop() {
        let (mut pts, _) = ring_l();
        let before = pts.clone();
        let moved = relocate_corners(&mut pts, &[]);
        assert_eq!(moved, 0);
        assert_eq!(pts[5].x, before[5].x);
    }

    #[test]
    fn moves_bounded_by_unit_square() {
        // random-ish ring: every relocated vertex stays within 0.5 of origin
        let mut pts: Vec<Point> = (0..40)
            .map(|i| {
                let t = i as f64 * 0.157;
                Point { x: 50.0 + 20.0 * t.cos() + (i % 3) as f64 * 0.13, y: 50.0 + 20.0 * t.sin() }
            })
            .collect();
        let orig = pts.clone();
        let corners = vec![3, 11, 22, 31];
        relocate_corners(&mut pts, &corners);
        for &c in &corners {
            assert!((pts[c].x - orig[c].x).abs() <= 0.5 + 1e-12);
            assert!((pts[c].y - orig[c].y).abs() <= 0.5 + 1e-12);
        }
    }
}

#[cfg(test)]
mod emit_clean_tests {
    use super::*;
    fn pt(x: f64, y: f64) -> Point { Point { x, y } }
    #[test]
    fn drops_zero_length_line_and_degenerate_cubic() {
        let r = ReferenceRing { start: pt(0., 0.), spans: vec![
            Span::Line { end: pt(10., 0.) },
            Span::Line { end: pt(10., 0.) },
            Span::Cubic { control_one: pt(10., 0.), control_two: pt(10., 0.), end: pt(10., 0.) },
            Span::Line { end: pt(10., 10.) },
            Span::Line { end: pt(0., 0.) },
        ]};
        let c = clean_emitted_ring(r, 0.0);
        assert_eq!(c.spans.len(), 3);
    }
    #[test]
    fn keeps_looping_cubic_and_closure() {
        let r = ReferenceRing { start: pt(0., 0.), spans: vec![
            Span::Cubic { control_one: pt(5., 5.), control_two: pt(-5., 5.), end: pt(0., 0.) },
            Span::Line { end: pt(10., 0.) },
            Span::Line { end: pt(0.1, 0.0) },
        ]};
        let c = clean_emitted_ring(r, 0.2);
        assert_eq!(c.spans.len(), 3);
        match c.spans.last().unwrap() { Span::Line { end } => assert_eq!(*end, pt(0., 0.)), _ => panic!() }
    }
    #[test]
    fn rounding_creates_then_removes_zero_length() {
        let r = ReferenceRing { start: pt(0.2, 0.), spans: vec![
            Span::Line { end: pt(10.2, 0.) },
            Span::Line { end: pt(10.4, 0.3) },
            Span::Line { end: pt(0.2, 0.) },
        ]};
        let c = round_and_clean_ring(&r, 1.0);
        assert_eq!(c.spans.len(), 2);
    }
    #[test]
    fn idempotent() {
        let r = ReferenceRing { start: pt(0., 0.), spans: vec![
            Span::Line { end: pt(3., 0.) }, Span::Line { end: pt(3., 0.) }, Span::Line { end: pt(0., 0.) } ]};
        let a = clean_emitted_ring(r, 0.1);
        let b = clean_emitted_ring(a.clone(), 0.1);
        assert_eq!(a.spans.len(), b.spans.len());
    }
}

/// Canonical engine entry for bounded economy candidate selection. Baseline
/// comes from capture and the existing fit. Candidate generation receives that
/// baseline, and the evaluator must measure final integer-font output. Without
/// valid construction/region/font evidence the unchanged baseline is returned.
pub fn fit_captured_select_economy<E, G>(
    glyph_id: &str, rings: &[CapturedRing], scale: f64, policy: &FitPolicy,
    bound: &crate::economy::FontEconomyBound, generate: G, evaluator: &mut E,
) -> (crate::reference_slice::DrawnGlyph, Vec<crate::economy::SelectionRecord>)
where E: crate::economy::FontEconomyEvaluator,
      G: FnOnce(&crate::reference_slice::DrawnGlyph) -> Vec<crate::reference_slice::DrawnGlyph> {
    let (baseline_rings,_,_,_) = fit_captured(rings,scale,policy);
    let baseline=crate::reference_slice::DrawnGlyph { glyph_id:glyph_id.into(), rings: baseline_rings };
    let mut candidates=generate(&baseline);
    let (economy_rings,_,_,_,_) = fit_captured_with_economy(rings,scale,policy);
    candidates.push(crate::reference_slice::DrawnGlyph { glyph_id:glyph_id.into(), rings:economy_rings });
    crate::economy::select_economical_glyph(baseline,candidates,bound,evaluator)
}

#[cfg(test)]
mod mitre_tests {
    use super::*;
    fn pt(x: f64, y: f64) -> Point { Point { x, y } }

    // Rectangle 0..40 with the bottom-right corner chamfered (leg 1):
    // bottom run ends S=(39,0), connector (39,0)->(40,1), right run from E=(40,1).
    // True mitre corner X=(40,0).
    fn chamfered_ring(leg: f64) -> (Vec<Point>, Vec<usize>) {
        let mut pts = vec![];
        let mut i = 0;
        while (i as f64) <= 40.0 - leg - 1.0 { pts.push(pt(i as f64, 0.0)); i += 2; }
        pts.push(pt(40.0 - leg, 0.0)); // S
        let s_idx = pts.len() - 1;
        pts.push(pt(40.0, leg)); // E
        let e_idx = pts.len() - 1;
        let mut j = (leg + 1.0) as i64;
        while j <= 40 { pts.push(pt(40.0, j as f64)); j += 2; }
        let tr_idx = pts.len() - 1;
        let mut k = 38i64;
        while k >= 0 { pts.push(pt(k as f64, 40.0)); k -= 2; }
        let tl_idx = pts.len() - 1;
        let mut l = 38i64;
        while l >= 2 { pts.push(pt(0.0, l as f64)); l -= 2; }
        let corners = vec![0, s_idx, e_idx, tr_idx, tl_idx];
        (pts, corners)
    }

    #[test]
    fn chamfered_corner_mitres_to_intersection() {
        let (mut pts, mut corners) = chamfered_ring(1.0);
        let n0 = pts.len();
        let merges = mitre_connectors(&mut pts, &mut corners, 1.0);
        assert_eq!(merges, 1);
        assert_eq!(pts.len(), n0 - 1);
        assert!(pts.iter().any(|p| p.x == 40.0 && p.y == 0.0), "mitre corner X=(40,0) present");
        // corners at S and E folded into one corner at X
        let xi = pts.iter().position(|p| p.x == 40.0 && p.y == 0.0).unwrap();
        assert!(corners.contains(&xi));
        assert_eq!(corners.len(), 4);
    }

    #[test]
    fn large_chamfer_is_preserved() {
        // leg 3: mitre distance to the chord is ~2.12 >= t_line; no merge
        let (mut pts, mut corners) = chamfered_ring(3.0);
        let n0 = pts.len();
        assert_eq!(mitre_connectors(&mut pts, &mut corners, 1.0), 0);
        assert_eq!(pts.len(), n0);
    }

    #[test]
    fn parallel_runs_never_merge() {
        // two horizontal runs joined by a slope: det == 0
        let mut pts = vec![];
        for i in 0..=5 { pts.push(pt(2.0 * i as f64, 0.0)); }
        let s = pts.len() - 1;
        pts.push(pt(11.0, 1.0));
        let e = pts.len() - 1;
        for i in 1..=5 { pts.push(pt(10.0 + 2.0 * i as f64, 1.0)); }
        for i in 1..=5 { pts.push(pt(20.0, 1.0 + 2.0 * i as f64)); }
        let tr = pts.len() - 1;
        for i in 1..=10 { pts.push(pt(20.0 - 2.0 * i as f64, 11.0)); }
        let tl = pts.len() - 1;
        for i in 1..=4 { pts.push(pt(0.0, 11.0 - 2.0 * i as f64)); }
        let mut corners = vec![0, s, e, tr, tl];
        let n0 = pts.len();
        assert_eq!(mitre_connectors(&mut pts, &mut corners, 1.0), 0);
        assert_eq!(pts.len(), n0);
    }

    #[test]
    fn interior_intersection_is_rejected() {
        // supports cross AT S (u == len(A), not beyond): strict u > len(A) fails
        let mut pts = vec![];
        for i in 0..=5 { pts.push(pt(2.0 * i as f64, 0.0)); } // A ends (10,0)
        let s = pts.len() - 1;
        pts.push(pt(11.0, 1.0)); // E; B direction (1,1) crosses y=0 at (10,0) == S
        let e = pts.len() - 1;
        for i in 1..=5 { pts.push(pt(11.0 + i as f64, 1.0 + i as f64)); }
        for i in 1..=3 { pts.push(pt(16.0, 6.0 + 2.0 * i as f64)); }
        let tr = pts.len() - 1;
        for i in 1..=8 { pts.push(pt(16.0 - 2.0 * i as f64, 12.0)); }
        let tl = pts.len() - 1;
        for i in 1..=5 { pts.push(pt(0.0, 12.0 - 2.0 * i as f64)); }
        let mut corners = vec![0, s, e, tr, tl];
        assert_eq!(mitre_connectors(&mut pts, &mut corners, 1.0), 0);
    }

    #[test]
    fn bulging_connector_is_rejected_by_tolerance_guard() {
        let (mut pts, mut corners) = chamfered_ring(1.0);
        // inject an interior connector point 1.6 off the mitred polyline
        let e = corners[2];
        pts.insert(e, pt(38.5, 1.6));
        for c in corners.iter_mut() { if *c >= e { *c += 1; } }
        let n0 = pts.len();
        assert_eq!(mitre_connectors(&mut pts, &mut corners, 1.0), 0);
        assert_eq!(pts.len(), n0);
    }

    #[test]
    fn zero_length_connector_never_divides() {
        let (mut pts, mut corners) = chamfered_ring(1.0);
        // duplicate E's coordinates at an extra index inside the connector arc
        let e = corners[2];
        pts.insert(e, pts[e - 1]);
        for c in corners.iter_mut() { if *c >= e { *c += 1; } }
        let n0 = pts.len();
        let merges = mitre_connectors(&mut pts, &mut corners, 1.0);
        assert!(merges == 0 || merges == 1);
        assert!(pts.iter().all(|p| p.x.is_finite() && p.y.is_finite()));
        let _ = n0;
    }

    #[test]
    fn corner_remap_keeps_other_corners() {
        let (mut pts, mut corners) = chamfered_ring(1.0);
        let pre: Vec<Point> = corners.iter().map(|&c| pts[c]).collect();
        let merges = mitre_connectors(&mut pts, &mut corners, 1.0);
        assert_eq!(merges, 1);
        // corners outside the connector keep their coordinates
        for c in corners.iter() {
            let p = pts[*c];
            assert!(pre.iter().any(|q| (q.x - p.x).abs() < 1e-9 && (q.y - p.y).abs() < 1e-9)
                || (p.x == 40.0 && p.y == 0.0));
        }
    }

    #[test]
    fn deterministic_across_runs() {
        let (p1, c1) = chamfered_ring(1.0);
        let (p2, c2) = chamfered_ring(1.0);
        let mut a = (p1, c1);
        let mut b = (p2, c2);
        assert_eq!(mitre_connectors(&mut a.0, &mut a.1, 1.0), mitre_connectors(&mut b.0, &mut b.1, 1.0));
        assert!(a.0.iter().zip(b.0.iter()).all(|(x, y)| x.x == y.x && x.y == y.y));
        assert_eq!(a.1, b.1);
    }

    // ---- G2 joint-repair pass: unit coverage ----
    #[test]
    fn cubic_end_k_known_values() {
        // Straight cubic (collinear controls): zero curvature at both ends.
        let straight = [Point { x: 0.0, y: 0.0 }, Point { x: 1.0, y: 0.0 }, Point { x: 2.0, y: 0.0 }, Point { x: 3.0, y: 0.0 }];
        assert_eq!(cubic_end_k(&straight, true), 0.0);
        assert_eq!(cubic_end_k(&straight, false), 0.0);
        // k(0) = (B' x B'')/|B'|^3 = (0*0 - 3*6)/27 = -2/3.
        let bent = [Point { x: 0.0, y: 0.0 }, Point { x: 0.0, y: 1.0 }, Point { x: 1.0, y: 2.0 }, Point { x: 2.0, y: 2.0 }];
        assert!((cubic_end_k(&bent, false) - (-1.0)).abs() < 1e-12);
    }

    #[test]
    fn joint_break_flags_curvature_jump_not_noise() {
        let grid = 1.0;
        // Two straight collinear cubics: k=0 both sides -> no break.
        let a = Span::Cubic { control_one: Point { x: 1.0, y: 0.0 }, control_two: Point { x: 2.0, y: 0.0 }, end: Point { x: 3.0, y: 0.0 } };
        let b = Span::Cubic { control_one: Point { x: 4.0, y: 0.0 }, control_two: Point { x: 5.0, y: 0.0 }, end: Point { x: 6.0, y: 0.0 } };
        assert!(!joint_is_break(Point { x: 0.0, y: 0.0 }, &a, Point { x: 3.0, y: 0.0 }, &b, grid));
        // Long flat cubic into a strongly bent cubic at a G1 joint (10,0):
        // k jumps 0 -> 0.8, far above either side's grid-quantization floor.
        let al = Span::Cubic { control_one: Point { x: 3.33, y: 0.0 }, control_two: Point { x: 6.67, y: 0.0 }, end: Point { x: 10.0, y: 0.0 } };
        let c = Span::Cubic { control_one: Point { x: 20.0, y: 0.0 }, control_two: Point { x: 30.0, y: 80.0 }, end: Point { x: 30.0, y: 160.0 } };
        assert!(joint_is_break(Point { x: 0.0, y: 0.0 }, &al, Point { x: 10.0, y: 0.0 }, &c, grid));
        // Zero-length handle -> unreadable joint -> treated as break (gate safety).
        let z = Span::Cubic { control_one: Point { x: 10.0, y: 0.0 }, control_two: Point { x: 30.0, y: 80.0 }, end: Point { x: 30.0, y: 160.0 } };
        assert!(joint_is_break(Point { x: 0.0, y: 0.0 }, &al, Point { x: 10.0, y: 0.0 }, &z, grid));
    }

    #[test]
    fn harmonize_clears_break_and_preserves_endpoints() {
        // Two cubics sharing a horizontal-tangent joint at (3,0) with
        // same-sign but unequal curvatures.
        let a_pts = [Point { x: 0.0, y: 0.0 }, Point { x: 1.5, y: 1.0 }, Point { x: 2.0, y: 0.4 }, Point { x: 3.0, y: 0.0 }];
        let b_pts = [Point { x: 3.0, y: 0.0 }, Point { x: 4.0, y: -0.4 }, Point { x: 5.5, y: -1.0 }, Point { x: 6.0, y: -1.2 }];
        // samples: dense points ON the two cubics so the dense gate sees the truth
        fn sample(p: &[Point; 4], n: usize) -> Vec<Point> {
            (0..=n).map(|i| {
                let t = i as f64 / n as f64; let mt = 1.0 - t;
                Point {
                    x: mt * mt * mt * p[0].x + 3.0 * mt * mt * t * p[1].x + 3.0 * mt * t * t * p[2].x + t * t * t * p[3].x,
                    y: mt * mt * mt * p[0].y + 3.0 * mt * mt * t * p[1].y + 3.0 * mt * t * t * p[2].y + t * t * t * p[3].y,
                }
            }).collect()
        }
        let arcs = vec![sample(&a_pts, 32), sample(&b_pts, 32)];
        let a = FitSpan { span: Span::Cubic { control_one: a_pts[1], control_two: a_pts[2], end: a_pts[3] }, arc: 0, s: 0, e: 32 };
        let b = FitSpan { span: Span::Cubic { control_one: b_pts[1], control_two: b_pts[2], end: b_pts[3] }, arc: 1, s: 0, e: 32 };
        let ka = cubic_end_k(&a_pts, true);
        let kb = cubic_end_k(&b_pts, false);
        if ka == 0.0 || kb == 0.0 || ka.signum() != kb.signum() {
            // curvatures must be same-sign nonzero for this fixture
            assert!(harmonize_g2_joint(&arcs, &a, &b, a_pts[0], a_pts[3], b_pts[3], 1.0, 1.0).is_none());
            return;
        }
        match harmonize_g2_joint(&arcs, &a, &b, a_pts[0], a_pts[3], b_pts[3], 1.0, 1.0) {
            Some((la, lb)) => {
                // Endpoints preserved (G0 untouched).
                let lae = match &la { Span::Cubic { end, .. } => *end, _ => panic!() };
                assert_eq!(lae, a_pts[3]);
                // Jump strictly reduced.
                let qa = [a_pts[0], a_pts[1], match &la { Span::Cubic { control_two, .. } => *control_two, _ => panic!() }, a_pts[3]];
                let qb = [a_pts[3], match &lb { Span::Cubic { control_one, .. } => *control_one, _ => panic!() }, b_pts[2], b_pts[3]];
                let jnew = (cubic_end_k(&qa, true) - cubic_end_k(&qb, false)).abs();
                assert!(jnew < (ka - kb).abs());
            }
            None => {
                // Declined only when gates refuse: the original pair must remain valid.
                let sa = &arcs[0][0..=32];
                assert!(plausible(sa, &a_pts));
            }
        }
    }

    fn guard_fixture_cubic() -> (Point, Point, Point, Point) {
        // len 100 fu (grid 1.0 -> 100 px, above the 63 px floor),
        // control sagitta 0.5 fu -> ratio 0.005 < 0.02: long + near-straight.
        (Point { x: 0.0, y: 0.0 }, Point { x: 33.0, y: 0.5 }, Point { x: 66.0, y: -0.5 }, Point { x: 100.0, y: 0.0 })
    }

    #[test]
    fn straight_edge_guard_declines_when_raw_bowed() {
        let (a, c1, c2, b) = guard_fixture_cubic();
        // Raw chain bows 2 fu off the chord: NOT straight at t_line = 1.0.
        RAW_RING.with(|r| *r.borrow_mut() = vec![
            a, Point { x: 25.0, y: 2.0 }, Point { x: 50.0, y: 0.1 }, Point { x: 75.0, y: 1.9 }, b,
        ]);
        let v = straight_edge_guard(a, c1, c2, b, 1.0, 1.0);
        RAW_RING.with(|r| r.borrow_mut().clear());
        assert!(matches!(v, StraightEdgeGuard::Decline));
    }

    #[test]
    fn straight_edge_guard_emits_line_when_raw_straight() {
        let (a, c1, c2, b) = guard_fixture_cubic();
        // Raw chain hugs the chord within t_line = 1.0: straight by R8.
        RAW_RING.with(|r| *r.borrow_mut() = vec![
            a, Point { x: 25.0, y: 0.4 }, Point { x: 50.0, y: -0.3 }, Point { x: 75.0, y: 0.2 }, b,
        ]);
        let v = straight_edge_guard(a, c1, c2, b, 1.0, 1.0);
        RAW_RING.with(|r| r.borrow_mut().clear());
        assert!(matches!(v, StraightEdgeGuard::EmitLine));
    }

    #[test]
    fn straight_edge_guard_clears_short_and_bowed_cubics() {
        let (a, c1, c2, b) = guard_fixture_cubic();
        // No raw chain bound: short spans and genuinely bowed spans never
        // reach the raw lookup.
        let short = straight_edge_guard(a, c1, c2, Point { x: 50.0, y: 0.0 }, 1.0, 1.0);
        assert!(matches!(short, StraightEdgeGuard::Clear));
        let bowed = straight_edge_guard(a, Point { x: 33.0, y: 5.0 }, Point { x: 66.0, y: -5.0 }, b, 1.0, 1.0);
        assert!(matches!(bowed, StraightEdgeGuard::Clear));
    }

    #[test]
    fn fit_ring_consumes_mitred_corner() {
        let (pts, corners) = chamfered_ring(1.0);
        let policy = FitPolicy { squared_error: 0.35, max_refits: 8 };
        let (ring, _n, _fb) = fit_ring(pts, corners, &policy);
        let mut pts_out = vec![ring.start];
        for s in &ring.spans {
            match s {
                Span::Line { end } | Span::Cubic { end, .. } => pts_out.push(*end),
            }
        }
        assert!(
            pts_out.iter().any(|p| (p.x - 40.0).abs() < 0.5 && p.y.abs() < 0.5),
            "fit output carries the mitred corner (40,0): {:?}", pts_out
        );
    }
}

#[cfg(test)]
mod straight_constraint_tests {
    use super::*;
    use crate::reference_transfer::*;
    fn pt(x: f64, y: f64) -> Point { Point { x, y } }

    fn pin() -> ReferencePin {
        ReferencePin { sha256_hex: "00".into(), glyph_id: "g".into(), provenance_reference: "test".into() }
    }
    fn cfg() -> TransferConfig {
        TransferConfig { smooth_sin: 0.05233595624294397, max_node_dist: 0.003, max_ring_cost: 0.3 }
    }
    // reference ring: square, all Line spans (straight intent everywhere)
    fn ref_square() -> PinnedReference {
        PinnedReference { pin: pin(), rings: vec![ReferenceRing {
            start: pt(0., 0.),
            spans: vec![
                Span::Line { end: pt(10., 0.) },
                Span::Line { end: pt(10., 10.) },
                Span::Line { end: pt(0., 10.) },
                Span::Line { end: pt(0., 0.) },
            ],
        }] }
    }
    fn targets_for(pairs: &[((usize, usize), (usize, usize))]) -> TransferTargets {
        // pairs: (captured (ring,node)) -> (reference ring, reference node)
        let mut ts = vec![];
        for (cap, refn) in pairs.iter().map(|(a, b)| (*a, *b)) {
            ts.push(NodeTarget {
                reference_ring: refn.0,
                reference_node: refn.1,
                pos: (0.0, 0.0),
                role: NodeRole::Corner,
                extremum_x: false,
                extremum_y: false,
                tangent: None,
                captured: Some(cap),
            });
        }
        TransferTargets {
            pin: pin(),
            cfg: cfg(),
            frame: Frame { min: (0.0, 0.0), size: (1.0, 1.0) },
            targets: ts,
            ring_map: vec![0],
            reference_nodes: 4,
        }
    }
    // emitted ring 0 matching the square but with a cubic on span 0
    fn emitted(dev: f64) -> ReferenceRing {
        ReferenceRing {
            start: pt(0., 0.),
            spans: vec![
                Span::Cubic { control_one: pt(3., dev), control_two: pt(7., dev), end: pt(10., 0.) },
                Span::Line { end: pt(10., 10.) },
                Span::Line { end: pt(0., 10.) },
                Span::Line { end: pt(0., 0.) },
            ],
        }
    }
    // nodes: node j = end of span j; span 0 connects node 3 (start) to node 0
    fn all_matched() -> TransferTargets {
        targets_for(&[
            ((0, 3), (0, 3)), // start node -> ref node 3 (end of last span)
            ((0, 0), (0, 0)),
            ((0, 1), (0, 1)),
            ((0, 2), (0, 2)),
        ])
    }

    #[test]
    fn straight_intent_flips_flat_cubic() {
        let mut ring = emitted(0.3);
        let n = constrain_straight_spans(&mut ring, 0, &all_matched(), &ref_square(), 1.0);
        assert_eq!(n, 1);
        assert!(matches!(ring.spans[0], Span::Line { end } if end == pt(10., 0.)));
    }

    #[test]
    fn deviating_cubic_survives() {
        let mut ring = emitted(2.5);
        let n = constrain_straight_spans(&mut ring, 0, &all_matched(), &ref_square(), 1.0);
        assert_eq!(n, 0);
        assert!(matches!(ring.spans[0], Span::Cubic { .. }));
    }

    #[test]
    fn curved_reference_intent_keeps_cubic() {
        let mut r = ref_square();
        r.rings[0].spans[0] = Span::Cubic { control_one: pt(3., 4.), control_two: pt(7., 4.), end: pt(10., 0.) };
        let mut ring = emitted(0.3);
        let n = constrain_straight_spans(&mut ring, 0, &all_matched(), &r, 1.0);
        assert_eq!(n, 0);
        assert!(matches!(ring.spans[0], Span::Cubic { .. }));
    }

    #[test]
    fn unmatched_nodes_are_untouched() {
        let mut ring = emitted(0.3);
        let t = targets_for(&[((0, 0), (0, 0))]); // only one endpoint matched
        let n = constrain_straight_spans(&mut ring, 0, &t, &ref_square(), 1.0);
        assert_eq!(n, 0);
        assert!(matches!(ring.spans[0], Span::Cubic { .. }));
    }

    #[test]
    fn non_adjacent_reference_nodes_carry_no_intent() {
        let mut ring = emitted(0.3);
        let t = targets_for(&[((0, 3), (0, 0)), ((0, 0), (0, 2))]); // not adjacent
        let n = constrain_straight_spans(&mut ring, 0, &t, &ref_square(), 1.0);
        assert_eq!(n, 0);
    }

    #[test]
    fn wrong_ring_index_is_untouched() {
        let mut ring = emitted(0.3);
        let n = constrain_straight_spans(&mut ring, 7, &all_matched(), &ref_square(), 1.0);
        assert_eq!(n, 0);
    }

    #[test]
    fn deterministic() {
        let mut a = emitted(0.3);
        let mut b = emitted(0.3);
        let t = all_matched();
        let r = ref_square();
        assert_eq!(constrain_straight_spans(&mut a, 0, &t, &r, 1.0), constrain_straight_spans(&mut b, 0, &t, &r, 1.0));
        assert!(matches!(a.spans[0], Span::Line { .. }) && matches!(b.spans[0], Span::Line { .. }));
    }
}

#[cfg(test)]
mod fit_counter_tests {
    use super::*;
    #[test]
    fn counters_are_per_thread_and_delta_is_exact() {
        reset_straight_sweep_converted(); reset_reloc_moved();
        let before = FitCounters::now();
        STRAIGHT_SWEEP_CONVERTED.with(|c| c.set(c.get() + 3));
        RELOC_MOVED.with(|c| c.set(c.get() + 5));
        // another thread's counters never leak into this thread's delta
        std::thread::spawn(|| { STRAIGHT_SWEEP_CONVERTED.with(|c| c.set(c.get() + 100)); assert_eq!(straight_sweep_converted(), 100); }).join().unwrap();
        assert_eq!(FitCounters::delta_since(before), Some(FitCounters { straight_sweep: 3, reloc_moved: 5 }));
        add_straight_sweep_converted(4).unwrap();
        assert_eq!(straight_sweep_converted(), 7);
        add_reloc_moved(2).unwrap();
        assert_eq!(reloc_moved(), 7);
        assert!(add_straight_sweep_converted(usize::MAX).is_err() && add_reloc_moved(usize::MAX).is_err());
        assert_eq!((straight_sweep_converted(), reloc_moved()), (7, 7), "a refused add leaves the counter unchanged");
        let later = FitCounters::now();
        reset_straight_sweep_converted();
        assert_eq!(FitCounters::delta_since(later), None, "a decreasing counter is refused");
        reset_straight_sweep_converted(); reset_reloc_moved();
        assert_eq!(FitCounters::now(), FitCounters::default());
    }
}

#[cfg(test)]
mod raw_ring_task_tests {
    //! fit-raw-ring-tls: RAW_RING is worker-local state reused across tasks by
    //! the parallel stage-1 pool. Every task boundary resets it, so no task
    //! can read the previous task's (another glyph's) raw ring.
    use super::*;
    use crate::cubic_fit::FitPolicy;

    fn raw_ring_state() -> (usize, Option<Point>) { RAW_RING.with(|r| { let b = r.borrow(); (b.len(), b.first().copied()) }) }
    fn policy() -> FitPolicy { FitPolicy { squared_error: 0.25, max_refits: 6 } }

    /// Axis-aligned square, `n` lattice points per edge, raw == points.
    fn square_ring(n: usize, origin: f64) -> crate::capture::CapturedRing {
        let side = n as f64;
        let mut pts = vec![];
        for i in 0..n { pts.push(Point { x: origin + i as f64, y: origin }); }
        for i in 0..n { pts.push(Point { x: origin + side, y: origin + i as f64 }); }
        for i in 0..n { pts.push(Point { x: origin + side - i as f64, y: origin + side }); }
        for i in 0..n { pts.push(Point { x: origin, y: origin + side - i as f64 }); }
        crate::capture::CapturedRing { points: pts.clone(), corners: vec![0, n, 2 * n, 3 * n], hole: false, raw: pts }
    }

    #[test]
    fn captured_task_leaves_its_own_ring() {
        let ring = square_ring(40, 3.0);
        let (want_len, want_first) = (ring.raw.len(), ring.raw[0]);
        let _ = fit_captured(&[ring], 1.0, &policy());
        let (len, first) = raw_ring_state();
        assert_eq!((len, first), (want_len, Some(want_first)), "the task's own ring, not a stale one");
    }

    #[test]
    fn captured_task_resets_before_fitting() {
        let _ = fit_captured(&[square_ring(40, 3.0)], 1.0, &policy());
        assert!(raw_ring_state().0 > 0, "sanity: first task populated RAW_RING");
        // worker reuse: the next task's rings must be what RAW_RING holds
        let ring = square_ring(12, 500.0);
        let (want_len, want_first) = (ring.raw.len(), ring.raw[0]);
        let _ = fit_captured(&[ring], 1.0, &policy());
        assert_eq!(raw_ring_state(), (want_len, Some(want_first)), "second task must not see the first task's ring");
    }

    #[test]
    fn degenerate_only_task_resets_without_setting() {
        let _ = fit_captured(&[square_ring(40, 3.0)], 1.0, &policy());
        assert!(raw_ring_state().0 > 0, "sanity: contaminated");
        // every ring dropped as truly unrepresentable (PN-3 speck KEEP+FLAG:
        // a positive-area sub-pixel ring now SHIPS as its minimal contour, so
        // the only remaining dropped class is a zero-area 1/2-point trace,
        // which has no representable contour at any grid): nothing is fitted,
        // nothing sets RAW_RING; the task-boundary reset still runs
        let tiny = crate::capture::CapturedRing {
            points: vec![Point { x: 0.0, y: 0.0 }, Point { x: 3.0, y: 0.0 }],
            corners: vec![], hole: false, raw: vec![],
        };
        let (_out, _n, _fb, dropped) = fit_captured(&[tiny], 1.0, &policy());
        assert_eq!(dropped, 1, "a zero-area 2-point trace has no representation and is dropped");
        assert_eq!(raw_ring_state().0, 0, "a glyph task that fits nothing must still reset RAW_RING");
    }

    #[test]
    fn standalone_ring_fit_resets_the_raw_ring() {
        // fit_ring* callers hold no raw source: the contract is "leaves it
        // empty". Under worker reuse that requires an explicit reset.
        let _ = fit_captured(&[square_ring(40, 3.0)], 1.0, &policy());
        assert!(raw_ring_state().0 > 0, "sanity: contaminated");
        let q = square_ring(20, 100.0);
        let pol = policy();
        let _ = fit_ring_db(q.points, q.corners, &pol, dense_bound(1.0, &pol), 1.0, 1.0);
        assert_eq!(raw_ring_state().0, 0, "a standalone ring fit must not inherit the previous task's raw ring");
    }
}

#[cfg(test)]
mod fit_counters_reduce_tests {
    //! fit-counters-reduce: the parallel driver measures one FitCounters delta
    //! per glyph task on the worker that ran it; the sequential reduce sums the
    //! deltas in manifest order. On a reused worker (many tasks, one thread)
    //! the ordered sum of deltas must equal the serial run's counter total.
    use super::*;
    use crate::cubic_fit::FitPolicy;

    fn policy() -> FitPolicy { FitPolicy { squared_error: 0.25, max_refits: 6 } }

    /// One task through the captured path whose corner vertex relocates
    /// (reloc_tests geometry: edges y=0.3x-0.075 and y=-0.3x+6.075 cross at
    /// (10.25, 3.0), the integer corner at (10,3) moves).
    fn reloc_task() {
        let mut pts = vec![];
        for i in 0..=5 { let x = 2.0 * i as f64; pts.push(Point { x, y: 0.3 * x - 0.075 }); }
        for i in 1..=5 { let x = 10.0 - 2.0 * i as f64; pts.push(Point { x, y: -0.3 * x + 6.075 }); }
        let ring = crate::capture::CapturedRing { points: pts.clone(), corners: vec![0, 5, 10], hole: false, raw: pts };
        let _ = fit_captured(&[ring], 1.0, &policy());
    }

    #[test]
    fn worker_reuse_deltas_compose_in_order() {
        reset_straight_sweep_converted(); reset_reloc_moved();
        let base = FitCounters::now();
        reloc_task();
        let after_a = FitCounters::now();
        let delta_a = FitCounters::delta_since(base).expect("task A delta is exact");
        reloc_task();
        let after_b = FitCounters::now();
        let delta_b = FitCounters::delta_since(after_a).expect("task B delta is exact");
        assert!(delta_a.reloc_moved > 0, "the task must move at least one corner vertex");
        assert_eq!(delta_a, delta_b, "the same task on a reused worker yields the same delta");
        let reduced = FitCounters {
            straight_sweep: base.straight_sweep + delta_a.straight_sweep + delta_b.straight_sweep,
            reloc_moved: base.reloc_moved + delta_a.reloc_moved + delta_b.reloc_moved,
        };
        assert_eq!(reduced, after_b, "ordered per-task reduce == the serial run counter total");
        reset_straight_sweep_converted(); reset_reloc_moved();
    }
}

#[cfg(test)]
mod fallback_rescue_tests {
    use super::*;

    fn pt(x: f64, y: f64) -> Point { Point { x, y } }

    // Measured on Paul New period (002E), arc 4: two corners, each spread
    // over two adjacent ~44.8-degree steps (raster corner splitting).
    fn measured_two_corner_arc() -> Vec<Point> {
        vec![
            pt(498.66310160427804, 949.1925137044981),
            pt(399.73262032085563, 949.1925137044981),
            pt(399.2869875222816, 948.7451264460872),
            pt(399.2852330624447, 899.7255186029499),
            pt(398.84135472370764, 899.2816402642128),
            pt(299.9108734402852, 899.2816402642128),
        ]
    }

    #[test]
    fn corner_split_detects_spread_corners_the_single_vertex_gate_misses() {
        let arc = measured_two_corner_arc();
        // Each single vertex turns < 45 deg (the sharp_turn_rescue gate
        // misses both corners); the same-sign adjacent PAIR rule (two ~44.8
        // steps summing past the module's declared 45-deg bound) gates them.
        let k = best_corner_split(&arc, 0.25).expect("spread corner must be detected");
        assert!(k == 2 || k == 3, "split lands on a measured corner vertex, got {k}");
    }

    #[test]
    fn corner_resplit_partitions_at_both_corners_in_order() {
        let arc = measured_two_corner_arc();
        let mut legs: Vec<Vec<Point>> = Vec::new();
let _ = take_corner_resplit_records();
        corner_resplit(&arc, 0.25, 0, &mut legs);
        let (recs, _) = take_corner_resplit_records();
        assert!(!recs.is_empty(), "split records must fire on the measured two-corner arc");
        assert!(recs.iter().all(|r| r.turn_deg.is_finite() && r.left_leg_chord.is_finite() && r.right_leg_chord.is_finite()));
        assert!(take_corner_resplit_records().0.is_empty(), "take must reset the stream");
        // Two spread corners: 3+ legs (both vertices of a spread corner can
        // gate, yielding an extra leg boundary inside the corner itself).
        assert!(legs.len() >= 3 && legs.len() <= 4, "two corners -> 3..=4 legs, got {}", legs.len());
        // Order preserved, shared boundary points, full coverage.
        assert_eq!(legs[0][0], arc[0]);
        assert_eq!(*legs.last().unwrap().last().unwrap(), arc[arc.len() - 1]);
        for w in legs.windows(2) {
            assert_eq!(*w[0].last().unwrap(), w[1][0]);
        }
        // Each corner region carries at least one leg boundary: the first
        // corner at vertex 1 or 2, the second at vertex 3 or 4.
        let mut idx = 0usize;
        let mut bounds: Vec<usize> = vec![];
        for leg in &legs[..legs.len() - 1] {
            idx += leg.len() - 1;
            bounds.push(idx);
        }
        assert!(bounds.iter().any(|&b| b == 1 || b == 2), "first corner gated: {bounds:?}");
        assert!(bounds.iter().any(|&b| b == 3 || b == 4), "second corner gated: {bounds:?}");
    }

    #[test]
    fn corner_split_accepts_a_sharp_triple_and_leaves_a_smooth_one() {
        // n == 3 corner case: single-vertex 45-deg gate (same bound
        // sharp_turn_rescue declares for spike triples).
        let corner = vec![pt(400.62, 698.94), pt(399.51, 698.30), pt(399.60, 600.26)];
        assert_eq!(best_corner_split(&corner, 0.25), Some(1));
        // A shallow hook (< 45 deg) is NOT corner structure: it is left for
        // the chord-line terminal accept (its own dense-bound measurement).
        let hook = vec![pt(349.74, 598.48), pt(349.80, 500.44), pt(350.71, 499.40)];
        assert_eq!(best_corner_split(&hook, 0.25), None);
    }

    #[test]
    fn corner_split_refuses_smooth_arcs_and_degenerate_chords() {
        // Smooth quarter-circle samples: no vertex anywhere near 45 deg.
        let n = 10;
        let arc: Vec<Point> = (0..=n)
            .map(|i| {
                let t = std::f64::consts::FRAC_PI_2 * (i as f64) / (n as f64);
                pt(100.0 * t.cos(), 100.0 * t.sin())
            })
            .collect();
        assert_eq!(best_corner_split(&arc, 0.25), None);
        // Duplicate consecutive points stay on the existing fallback path.
        let dup = vec![pt(0.0, 0.0), pt(10.0, 0.0), pt(10.0, 0.0), pt(10.0, 10.0)];
        assert_eq!(best_corner_split(&dup, 0.25), None);
    }
}




/// Metadata from the fitting worker that is not owned by a raw geometry snapshot.
pub type MergeVisibilityObsContext = crate::obs_envelope::ObsContext;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MergeVisibilityConvertError {
    CountOverflow,
    RevisionOverflow,
    MissingP0 { ring_index: usize },
}
impl std::fmt::Display for MergeVisibilityConvertError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CountOverflow => f.write_str("merge-visibility count exceeds mov-1 integer range"),
            Self::RevisionOverflow => f.write_str("merge-visibility revision overflow"),
            Self::MissingP0 { ring_index } => write!(f, "ring {ring_index} has observations but no P0"),
        }
    }
}
impl std::error::Error for MergeVisibilityConvertError {}

fn merge_visibility_obs_point(point: MergeVisibilityPoint) -> crate::obs_envelope::ObsPoint {
    use crate::obs_envelope::ObsPoint;
    match point {
        MergeVisibilityPoint::P0 => ObsPoint::P0, MergeVisibilityPoint::P1 => ObsPoint::P1,
        MergeVisibilityPoint::P2 => ObsPoint::P2, MergeVisibilityPoint::P3 => ObsPoint::P3,
        MergeVisibilityPoint::P4 => ObsPoint::P4, MergeVisibilityPoint::P5 => ObsPoint::P5,
        MergeVisibilityPoint::P6 => ObsPoint::P6, MergeVisibilityPoint::P7 => ObsPoint::P7,
    }
}

fn merge_visibility_span_counts(spans: &[MergeVisibilitySpan]) -> Result<crate::obs_envelope::SpanCounts, MergeVisibilityConvertError> {
    let total = u32::try_from(spans.len()).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
    let line = u32::try_from(spans.iter().filter(|s| matches!(s.span, Span::Line { .. })).count())
        .map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
    let cubic = u32::try_from(spans.iter().filter(|s| matches!(s.span, Span::Cubic { .. })).count())
        .map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
    Ok(crate::obs_envelope::SpanCounts { total, line, cubic })
}

fn merge_visibility_snapshot_ring(snapshot: &MergeVisibilitySnapshot) -> crate::obs_envelope::RingSnapshot {
    fn q(p: &Point) -> crate::obs_envelope::QPoint {
        crate::obs_envelope::QPoint(p.x.round() as i32, p.y.round() as i32)
    }
    let spans: Vec<Span> = snapshot.spans.iter().map(|s| s.span.clone()).collect();
    crate::obs_envelope::RingSnapshot::from_fit(&snapshot.start, &spans, q)
}

fn merge_visibility_span_ids(ring_index: usize, spans: &[MergeVisibilitySpan]) -> Result<Vec<crate::obs_envelope::SpanId>, MergeVisibilityConvertError> {
    let ring = u32::try_from(ring_index).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
    (0..spans.len()).map(|i| {
        let span = u32::try_from(i).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
        Ok(crate::obs_envelope::assign_span_id(ring, span))
    }).collect()
}

fn merge_visibility_xform_pass(pass: MergeVisibilityPass) -> crate::obs_envelope::XformPass {
    use crate::obs_envelope::XformPass;
    match pass {
        MergeVisibilityPass::G2Merge => XformPass::G2Merge, MergeVisibilityPass::Staircase => XformPass::Staircase,
        MergeVisibilityPass::LineJunction => XformPass::LineJunction, MergeVisibilityPass::StraightOverCurve => XformPass::StraightOverCurve,
        MergeVisibilityPass::Qf => XformPass::Qf, MergeVisibilityPass::Closure => XformPass::Closure,
        MergeVisibilityPass::Rounding => XformPass::Rounding, MergeVisibilityPass::Economy => XformPass::Economy,
        MergeVisibilityPass::Tidy => XformPass::Tidy, MergeVisibilityPass::RescueAdoption => XformPass::RescueAdoption,
    }
}

fn merge_visibility_xform_kind(transform: MergeVisibilityTransform) -> crate::obs_envelope::XformKind {
    use crate::obs_envelope::XformKind;
    match transform {
        MergeVisibilityTransform::G2LineRunFold => XformKind::G2LineRunFold,
        MergeVisibilityTransform::G2Union => XformKind::G2Union,
        MergeVisibilityTransform::G2Harmonize => XformKind::G2Harmonize,
        MergeVisibilityTransform::StaircaseCollapse => XformKind::StaircaseCollapse,
        MergeVisibilityTransform::LineJunctionMovement => XformKind::LineJunctionMovement,
        MergeVisibilityTransform::SocConversion => XformKind::SocConversion,
        MergeVisibilityTransform::QfRefinement => XformKind::QfRefinement,
        MergeVisibilityTransform::SyntheticClosure => XformKind::SyntheticClosure,
        MergeVisibilityTransform::Round => XformKind::Round,
        MergeVisibilityTransform::ExactCubicLine => XformKind::ExactCubicLine,
        MergeVisibilityTransform::ExactLineMerge => XformKind::ExactLineMerge,
        MergeVisibilityTransform::ZeroSpanRemoval => XformKind::ZeroSpanRemoval,
        MergeVisibilityTransform::CornerAdoption => XformKind::CornerAdoption,
        MergeVisibilityTransform::ArcRescue => XformKind::ArcRescue,
    }
}

fn merge_visibility_src_relation(rewrite: &MergeVisibilityRewrite) -> Option<crate::obs_envelope::SrcRelation> {
    let source_indices_same = rewrite.input_spans.len() == rewrite.output_spans.len()
        && rewrite.input_spans.iter().zip(&rewrite.output_spans).all(|(a, b)|
            a.arc.is_some() && a.arc == b.arc
                && a.source_start.is_some() && a.source_start == b.source_start
                && a.source_end.is_some() && a.source_end == b.source_end);
    if !source_indices_same || rewrite.input_source_arcs.is_empty() || rewrite.output_source_arcs.is_empty() {
        return None;
    }
    if rewrite.input_source_arcs == rewrite.output_source_arcs {
        Some(crate::obs_envelope::SrcRelation::Preserved)
    } else {
        Some(crate::obs_envelope::SrcRelation::Rebound)
    }
}

/// Converts one worker-local collector. The caller passes the shared
/// per-(glyph, style) RevEmitter so worker completion order never owns IDs.
pub fn merge_visibility_into_records(
    collector: &MergeVisibilityCollector,
    context: &MergeVisibilityObsContext,
    source: &crate::obs_envelope::RunSource<'_>,
    revisions: &mut crate::obs_envelope::RevEmitter,
) -> Result<Vec<crate::obs_envelope::Record>, MergeVisibilityConvertError> {
    use crate::obs_envelope::{LedgerCounts, Obs, ObserverOutcome, Record, Xform};
    #[derive(Clone, Copy)]
    enum Event<'a> { Obs(&'a MergeVisibilitySnapshot), Rewrite(&'a MergeVisibilityRewrite) }
    impl Event<'_> { fn seq(&self) -> u64 { match self { Event::Obs(x) => x.seq, Event::Rewrite(x) => x.seq } } }
    let mut events: Vec<Event<'_>> = collector.observations.iter().map(Event::Obs)
        .chain(collector.rewrites.iter().map(Event::Rewrite)).collect();
    events.sort_by_key(Event::seq);
    let src_fp = source.src_fp();
    let mut current_rev: std::collections::BTreeMap<usize, crate::obs_envelope::Revision> = std::collections::BTreeMap::new();
    let mut last_obs_rev: std::collections::BTreeMap<usize, crate::obs_envelope::Revision> = std::collections::BTreeMap::new();
    let mut records = Vec::new();
    let mut event_id = 0u64;
    for event in events {
        match event {
            Event::Obs(snapshot) => {
                let ring = u32::try_from(snapshot.ring_index).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
                let point = merge_visibility_obs_point(snapshot.point);
                if snapshot.point == MergeVisibilityPoint::P0 {
                    let rev = revisions.next_rev().map_err(|_| MergeVisibilityConvertError::RevisionOverflow)?;
                    current_rev.insert(snapshot.ring_index, rev);
                }
                let rev = *current_rev.get(&snapshot.ring_index)
                    .ok_or(MergeVisibilityConvertError::MissingP0 { ring_index: snapshot.ring_index })?;
                let predecessor = if snapshot.point == MergeVisibilityPoint::P0 { None }
                    else { last_obs_rev.get(&snapshot.ring_index).copied() };
                let ring_snapshot = merge_visibility_snapshot_ring(snapshot);
                let counts = merge_visibility_span_counts(&snapshot.spans)?;
                let count_key = |k: &str| snapshot.ledger_counts.get(k).copied().unwrap_or(0) as u64;
                let economy_decisions = collector.rewrites.iter()
                    .filter(|r| r.ring_index == snapshot.ring_index && r.seq <= snapshot.seq)
                    .map(|r| r.economy_decisions.len() as u64).sum();
                let ledger_counts = LedgerCounts {
                    fallback_events: count_key("fallback_events"),
                    ambiguous_stubs: count_key("ambiguous_stubs"),
                    declined_ambiguity: count_key("declined_ambiguities"),
                    economy_decisions,
                    zero_span_removals: snapshot.ledger_counts.get("zero_span_removals").copied().map(|n| n as u64),
                    synthetic_closures: snapshot.synthetic_closures as u64,
                    corner_adopted: count_key("corner_adopted"),
                    rescue_adopted: count_key("rescue_adopted"),
                };
                let arcs = u32::try_from(snapshot.source_arcs.len()).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
                let synthetic_closures = u32::try_from(snapshot.synthetic_closures).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
                let mut ctx = context.clone();
                ctx.route_domain = snapshot.route_domain.clone();
                let obs = Obs::from_snapshot(
                    &ctx, point, predecessor, ring, &ring_snapshot, src_fp, rev,
                    counts, arcs, synthetic_closures, ledger_counts, ObserverOutcome::Complete,
                    None, None,
                ).expect("integer snapshot geometry is finite");
                records.push(Record::Obs(obs));
                last_obs_rev.insert(snapshot.ring_index, rev);
            }
            Event::Rewrite(rewrite) => {
                // Rescue/adoption is outside the observation window; P0 already
                // captures its accepted output. Ignore earlier worker events.
                let Some(input_rev) = current_rev.get(&rewrite.ring_index).copied() else { continue; };
                let ring = u32::try_from(rewrite.ring_index).map_err(|_| MergeVisibilityConvertError::CountOverflow)?;
                let mut transform_input_rev = input_rev;
                for transform in &rewrite.transforms {
                    let output_rev = revisions.next_rev().map_err(|_| MergeVisibilityConvertError::RevisionOverflow)?;
                    let xform = Xform {
                        run_id: context.run_id.clone(), invocation_id: context.invocation_id.clone(), event_id,
                        pass: merge_visibility_xform_pass(rewrite.pass), transform: merge_visibility_xform_kind(*transform),
                        input_rev: transform_input_rev, output_rev,
                        in_spans: merge_visibility_span_ids(ring as usize, &rewrite.input_spans)?,
                        out_spans: merge_visibility_span_ids(ring as usize, &rewrite.output_spans)?,
                        src_relation: merge_visibility_src_relation(rewrite),
                        economy_decisions: if *transform == MergeVisibilityTransform::ExactCubicLine || *transform == MergeVisibilityTransform::ExactLineMerge {
                            rewrite.economy_decisions.clone()
                        } else { Vec::new() },
                    };
                    records.push(Record::Xform(xform));
                    event_id = event_id.checked_add(1).ok_or(MergeVisibilityConvertError::CountOverflow)?;
                    current_rev.insert(rewrite.ring_index, output_rev);
                    transform_input_rev = output_rev;
                }
            }
        }
    }
    Ok(records)
}

#[cfg(test)]
mod g1_observer_tests {
    use super::*;

    #[test]
    fn captures_by_value_p0_through_p7_snapshots_when_enabled() {
        let mut points = Vec::new();
        for i in 0..64 {
            let t = std::f64::consts::TAU * i as f64 / 64.0;
            points.push(Point { x: 30.0 * t.cos(), y: 20.0 * t.sin() });
        }
        let policy = FitPolicy { squared_error: 0.5, max_refits: 4 };
        reset_raw_ring();
        corner_record_site_set_ring(7);
        merge_visibility_begin();
        let mut fallback = Vec::new();
        let _ = fit_ring_db_economy_observed(
            points, Vec::new(), &policy, 2.0, 1.0, 1.0, true, None,
            &mut fallback, &mut Vec::new(), &mut Vec::new(), &mut Vec::new(),
        );
        let collector = merge_visibility_take_collector();
        assert!(!merge_visibility_enabled());
        let observations = collector.observations;
        let points: Vec<_> = observations.iter().map(|snapshot| snapshot.point).collect();
        assert_eq!(points, vec![
            MergeVisibilityPoint::P0, MergeVisibilityPoint::P1, MergeVisibilityPoint::P2,
            MergeVisibilityPoint::P3, MergeVisibilityPoint::P4, MergeVisibilityPoint::P5,
            MergeVisibilityPoint::P6, MergeVisibilityPoint::P7,
        ]);
        assert!(observations.iter().all(|snapshot| snapshot.ring_index == 7));
        assert!(observations.iter().all(|snapshot| !snapshot.spans.is_empty()));
        assert_ne!(observations[0].spans.as_ptr(), observations[1].spans.as_ptr());
        assert_eq!(observations[4].domain, MergeVisibilityDomain::Float);
        assert_eq!(observations[5].domain, MergeVisibilityDomain::Float);
        assert_eq!(observations[6].domain, MergeVisibilityDomain::Integer);
        assert_eq!(observations[7].domain, MergeVisibilityDomain::Integer);
    }

    #[test]
    fn accepted_rewrite_fact_owns_before_and_after_geometry() {
        let before = vec![FitSpan {
            span: Span::Line { end: Point { x: 10.0, y: 0.0 } }, arc: 0, s: 0, e: 1,
        }];
        let after = vec![FitSpan {
            span: Span::Cubic {
                control_one: Point { x: 3.0, y: 1.0 },
                control_two: Point { x: 7.0, y: 1.0 },
                end: Point { x: 10.0, y: 0.0 },
            }, arc: 1, s: 0, e: 3,
        }];
        merge_visibility_begin();
        merge_visibility_rewrite_fit(MergeVisibilityPass::G2Merge, MergeVisibilityTransform::G2LineRunFold,
            &before, &after, &[vec![Point { x: 0.0, y: 0.0 }, Point { x: 10.0, y: 0.0 }]],
            &[vec![Point { x: 0.0, y: 0.0 }, Point { x: 3.0, y: 1.0 }, Point { x: 7.0, y: 1.0 }, Point { x: 10.0, y: 0.0 }]]);
        let (observations, rewrites) = merge_visibility_take();
        assert!(observations.is_empty());
        assert_eq!(rewrites.len(), 1);
        assert_eq!(rewrites[0].pass, MergeVisibilityPass::G2Merge);
        assert_eq!(rewrites[0].transforms, vec![MergeVisibilityTransform::G2LineRunFold]);
        assert_eq!(rewrites[0].input_spans.len(), 1);
        assert_eq!(rewrites[0].output_spans.len(), 1);
        assert_eq!(rewrites[0].input_source_arcs[0].len(), 2);
        assert_eq!(rewrites[0].output_source_arcs[0].len(), 4);
    }


    #[test]
    fn converter_stable_orders_obs_xform_and_uses_revision_chain() {
        use crate::obs_envelope::{FitRoute, InvocationId, Record, RevEmitter, RouteDomain, RunSource};
        let p = |x, y| Point { x, y };
        let span = |end| MergeVisibilitySpan { arc: Some(0), source_start: Some(0), source_end: Some(1), span: Span::Line { end } };
        let snapshot = |seq, point, end| MergeVisibilitySnapshot {
            seq, route_domain: RouteDomain::Primary, point, ring_index: 0, domain: MergeVisibilityDomain::Float,
            start: p(0.0,0.0), spans: vec![span(p(end, 0.0))], source_arcs: vec![vec![p(0.0,0.0), p(end,0.0)]],
            ledger_counts: std::collections::BTreeMap::new(), synthetic_closures: 0,
        };
        let rewrite = MergeVisibilityRewrite {
            seq: 1, route_domain: RouteDomain::Primary, ring_index: 0, pass: MergeVisibilityPass::G2Merge,
            transforms: vec![MergeVisibilityTransform::G2Union], input_start: None, output_start: None,
            input_spans: vec![span(p(10.0,0.0))], output_spans: vec![MergeVisibilitySpan { arc: Some(0), source_start: Some(0), source_end: Some(2), span: Span::Cubic { control_one: p(3.0,1.0), control_two: p(7.0,1.0), end: p(10.0,0.0) } }],
            input_source_arcs: vec![vec![p(0.0,0.0), p(10.0,0.0)]], output_source_arcs: vec![vec![p(0.0,0.0), p(10.0,0.0)]], economy_decisions: Vec::new(),
        };
        let collector = MergeVisibilityCollector {
            observations: vec![snapshot(0, MergeVisibilityPoint::P0, 10.0), snapshot(2, MergeVisibilityPoint::P1, 10.0)],
            rewrites: vec![rewrite],
        };
        let context = crate::obs_envelope::ObsContext {
            run_id: "r".into(), invocation_id: InvocationId("i".into()), glyph: "g".into(), style: "s".into(),
            route_domain: RouteDomain::Primary, route: FitRoute::Plain, stage1_route: None, stage1_cache_sha256: None,
        };
        let source = RunSource { src_bytes: None };
        let mut revisions = RevEmitter::new();
        let records = merge_visibility_into_records(&collector, &context, &source, &mut revisions).unwrap();
        assert_eq!(records.len(), 3);
        let Record::Obs(p0) = &records[0] else { panic!("P0 first") };
        let Record::Xform(xform) = &records[1] else { panic!("Xform between observations") };
        let Record::Obs(p1) = &records[2] else { panic!("P1 last") };
        assert_eq!(p0.point, crate::obs_envelope::ObsPoint::P0);
        assert_eq!(p0.predecessor_rev, None);
        assert_eq!(p0.fp58, None);
        assert_eq!(xform.input_rev, crate::obs_envelope::Revision(1));
        assert_eq!(xform.output_rev, crate::obs_envelope::Revision(2));
        assert_eq!(p1.point, crate::obs_envelope::ObsPoint::P1);
        assert_eq!(p1.predecessor_rev, Some(crate::obs_envelope::Revision(1)));
        assert_eq!(p1.in_spans, p1.out_spans);
    }

    #[test]
    fn collection_is_off_by_default_and_take_disables_it() {
        MERGE_VISIBILITY.with(|cell| {
            let mut state = cell.borrow_mut();
            state.observations.clear();
            state.rewrites.clear();
            state.enabled = false;
        });
        assert!(!merge_visibility_enabled());
        let (observations, rewrites) = merge_visibility_take();
        assert!(observations.is_empty());
        assert!(rewrites.is_empty());
        assert!(!merge_visibility_enabled());
    }
}

#[cfg(test)]
mod r297_band_window {
    use super::*;
    use crate::cubic_fit::{fit_run_damped, RefitStop};

    fn desc(spans: &[FitSpan]) -> String {
        spans.iter().map(|fs| match &fs.span {
            Span::Line { end } => format!("L(s={},e={},end={:?})", fs.s, fs.e, end),
            Span::Cubic { control_one, control_two, end } =>
                format!("C(s={},e={},c1={:?},c2={:?},end={:?})", fs.s, fs.e, control_one, control_two, end),
        }).collect::<Vec<_>>().join(" ")
    }

    // r297-REV: an unresolved band window (line dev in (db, t_line]) must not
    // take the P1 line-first accept; it falls through to the normal
    // fit/split machinery. Inputs below are the r296 measured real windows
    // (bodoni strict-fixed fixtures, scale 2.4377): g22 ring0 arc16 s6e8 and
    // g16 ring1 arc5 s10e14, with the recursion tangents that actually reach
    // them (leg-stage forced values measured from the run).
    const DB: f64 = 1.71885; // 0.5*scale + sqrt(se)
    const T_LINE: f64 = 2.4377; // measured run value
    const GRID: f64 = 2.4377;

    #[test]
    fn band_window_qualifying_emits_cubic_not_line() {
        let pts = vec![
            Point { x: 131.09867966101694, y: 369.1902165158371 },
            Point { x: 90.26078378378378, y: 495.9506165158371 },
            Point { x: 75.85133188405797, y: 552.0177165158372 },
        ];
        let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
        let mut fspans = vec![];
        let mut fb = false;
        let mut events = vec![];
        let mut declined = vec![];
        fit_gated(&pts, &policy, &mut fspans, 0, &mut fb, DB, T_LINE, GRID, 8, 0, 0,
                  Some(Point { x: -0.29006800227223406, y: 0.95700603658378 }), None,
                  true, Some(RefitStop::CandidateFailed), &mut events, &mut Vec::new(), None, &mut declined, fit_run_damped);
        // actual measured rescue (fit_run_damped, forced lt): one Cubic, no
        // fallback event, no Band decline. Numbers pinned from the actual run.
        assert_eq!(fspans.len(), 1, "{}", desc(&fspans));
        match &fspans[0].span {
            Span::Cubic { control_one, control_two, end } => {
                assert_eq!((fspans[0].s, fspans[0].e), (0, 2));
                assert_eq!(*control_one, Point { x: 68.91597669442805, y: 574.3463235112968 });
                assert_eq!(*control_two, Point { x: 108.01673064088342, y: 426.8623225987982 });
                assert_eq!(*end, Point { x: 75.85133188405797, y: 552.0177165158372 });
            }
            _ => panic!("expected Cubic, got {}", desc(&fspans)),
        }
        assert!(events.is_empty(), "rescued window emits no fallback event: {:?}", events);
        assert!(declined.is_empty(), "rescued window keeps no Band decline: {:?}", declined);
        assert!(!fb);
    }

    #[test]
    fn band_window_unfittable_keeps_existing_fallback() {
        let pts = vec![
            Point { x: 285.93904415584416, y: 566.9216511061946 },
            Point { x: 274.24125, y: 569.4244804955076 },
            Point { x: 269.36585, y: 568.4993503447733 },
            Point { x: 262.05275, y: 572.5815237125777 },
            Point { x: 252.30195, y: 575.2132644864763 },
        ];
        let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
        let mut fspans = vec![];
        let mut fb = false;
        let mut events = vec![];
        let mut declined = vec![];
        fit_gated(&pts, &policy, &mut fspans, 0, &mut fb, DB, T_LINE, GRID, 8, 0, 0,
                  None, Some(Point { x: 0.991049957660624, y: -0.1334915031785744 }),
                  true, Some(RefitStop::BudgetExhausted), &mut events, &mut Vec::new(), None, &mut declined, fit_run_damped);
        // actual measured fallback (fit_run_damped, forced rt): the window's
        // own fit fails, the EXISTING machinery splits at the interior
        // extremum (index 2) and both children accept as in-band Lines.
        // Numbers pinned from the actual run.
        assert_eq!(fspans.len(), 2, "{}", desc(&fspans));
        assert!(matches!(fspans[0].span, Span::Line { end } if end == Point { x: 269.36585, y: 568.4993503447733 }));
        assert_eq!((fspans[0].s, fspans[0].e), (0, 2));
        assert!(matches!(fspans[1].span, Span::Line { end } if end == Point { x: 252.30195, y: 575.2132644864763 }));
        assert_eq!((fspans[1].s, fspans[1].e), (2, 4));
        assert!(events.is_empty(), "children accepted event-free: {:?}", events);
        assert_eq!(declined.len(), 2);
        assert!(declined.iter().all(|d| d.class == DeclinedClass::TrulyAmbiguous), "{:?}", declined);
        assert!(!fb);
    }
}
