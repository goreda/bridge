//! Form-analysis stage (F2): evidence-gated primitive recognition between
//! capture and fit. Recognized forms are constructed analytically; anything
//! unrecognized flows to the F1-gated cubic fit. No defaults on ambiguous
//! evidence (owner doctrine); every acceptance carries its residual.
use crate::reference_slice::{Point, ReferenceRing, Span};

fn rd(p: Point) -> Point {
    Point { x: p.x.round(), y: p.y.round() }
}

/// Algebraic (Kasa) circle fit: center, radius, max radial residual.
/// Returns None for fewer than 3 points or a degenerate system.
/// Arc-length resampling of a closed polyline at chord spacing <= `spacing`.
/// Evidence for the circle hypothesis is this DENSE chain, never the RDP
/// vertices (architect position 2026-10-11: a rectangle's 4 corners are
/// concyclic, so vertex-only Kasa residual is ~0 by construction on bars).
fn resample_closed(points: &[Point], spacing: f64) -> Vec<Point> {
    let n = points.len();
    if n < 2 || !(spacing > 0.0) {
        return points.to_vec();
    }
    let mut out = Vec::new();
    for i in 0..n {
        let a = points[i];
        let b = points[(i + 1) % n];
        let l = (b.x - a.x).hypot(b.y - a.y);
        out.push(a);
        if l > spacing {
            let m = (l / spacing).ceil() as usize;
            for j in 1..m {
                let t = j as f64 / m as f64;
                out.push(Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) });
            }
        }
    }
    out
}

pub fn circle_fit(points: &[Point]) -> Option<(Point, f64, f64)> {
    let n = points.len();
    if n < 3 {
        return None;
    }
    let (mut sx, mut sy, mut sxx, mut syy, mut sxy, mut sxz, mut syz, mut sz) =
        (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for p in points {
        let z = p.x * p.x + p.y * p.y;
        sx += p.x;
        sy += p.y;
        sxx += p.x * p.x;
        syy += p.y * p.y;
        sxy += p.x * p.y;
        sxz += p.x * z;
        syz += p.y * z;
        sz += z;
    }
    // Solve A x = b, A = [[sxx,sxy,sx],[sxy,syy,sy],[sx,sy,n]], b = [-sxz,-syz,-sz]
    let a = [
        [sxx, sxy, sx, -sxz],
        [sxy, syy, sy, -syz],
        [sx, sy, n as f64, -sz],
    ];
    // Gaussian elimination with partial pivot
    let mut m = a;
    for col in 0..3 {
        let mut piv = col;
        for r in col + 1..3 {
            if m[r][col].abs() > m[piv][col].abs() {
                piv = r;
            }
        }
        if m[piv][col].abs() < 1e-12 {
            return None;
        }
        m.swap(col, piv);
        for r in col + 1..3 {
            let f = m[r][col] / m[col][col];
            for c in col..4 {
                m[r][c] -= f * m[col][c];
            }
        }
    }
    let mut x = [0.0; 3];
    for r in (0..3).rev() {
        let mut s = m[r][3];
        for c in r + 1..3 {
            s -= m[r][c] * x[c];
        }
        x[r] = s / m[r][r];
    }
    let (d, e, f) = (x[0], x[1], x[2]);
    let cx = -d / 2.0;
    let cy = -e / 2.0;
    let r2 = (d * d + e * e) / 4.0 - f;
    if !(r2 > 0.0) || !r2.is_finite() {
        return None;
    }
    let r = r2.sqrt();
    let mut worst = 0.0f64;
    for p in points {
        worst = worst.max(((p.x - cx).hypot(p.y - cy) - r).abs());
    }
    Some((Point { x: cx, y: cy }, r, worst))
}

/// P0 whole-ring circle hypothesis (evidence-upgraded per architect position
/// 2026-10-11). Acceptance, all in font units:
/// 1. no declared corners;
/// 2. Kasa fit on the DENSE arc-length-resampled ring (spacing <= rdp_eps):
///    max radial residual <= t_circle (= rdp_eps + 0.5px quantization);
/// 3. bbox check: ring bbox width and height both equal 2r within t_circle
///    (a bar's circumscribed circle has r = half-diagonal and fails);
/// 4. angular coverage: largest angular gap of the dense samples around the
///    fitted center <= 1.5 * g_max, g_max = 2*sqrt(2*rdp_eps/r) derived from
///    the RDP chord bound; if that limit exceeds 45 deg the ring is too
///    small to prove a circle on this evidence -> abstain to the cubic fit;
/// 5. post-rounding re-verification: the emitted integer-rounded circle is
///    re-checked against the dense source samples (incl. the kappa cubic
///    deviation bound 0.0003*r); failure refuses the circle.
/// Emits the exact circle as four kappa cubics, winding matched to `hole`
/// (font coords y-up: outer CCW, hole CW), integer-rounded like every
/// container-bound ring.
pub fn recognize_circle_ring(
    points: &[Point],
    corners: &[usize],
    hole: bool,
    t_circle: f64,
    rdp_eps: f64,
) -> Option<ReferenceRing> {
    if !corners.is_empty() || !t_circle.is_finite() || t_circle < 0.0 || !(rdp_eps > 0.0) {
        return None;
    }
    let dense = resample_closed(points, rdp_eps);
    if dense.len() < 3 {
        return None;
    }
    // Fit on the RING VERTICES (on-contour, unbiased); VALIDATE on the dense
    // resample. Fitting on the resample would import the chord-inward bias
    // (chord midpoints sit inside the true arc by up to the rdp sagitta).
    let (c, r, _) = circle_fit(points)?;
    let mut resid = 0.0f64;
    for p in &dense {
        resid = resid.max(((p.x - c.x).hypot(p.y - c.y) - r).abs());
    }
    if resid > t_circle {
        return None;
    }
    let (mut mnx, mut mny, mut mxx, mut mxy) =
        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for p in &dense {
        mnx = mnx.min(p.x);
        mxx = mxx.max(p.x);
        mny = mny.min(p.y);
        mxy = mxy.max(p.y);
    }
    if ((mxx - mnx) - 2.0 * r).abs() > t_circle || ((mxy - mny) - 2.0 * r).abs() > t_circle {
        return None;
    }
    let limit = 1.5 * 2.0 * (2.0 * rdp_eps / r).sqrt();
    if limit > std::f64::consts::FRAC_PI_4 {
        return None; // too small to prove: abstain to the cubic fit
    }
    let mut ang: Vec<f64> = dense.iter().map(|p| (p.y - c.y).atan2(p.x - c.x)).collect();
    ang.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mut gap = 0.0f64;
    for i in 0..ang.len() {
        let d = if i + 1 < ang.len() {
            ang[i + 1] - ang[i]
        } else {
            ang[0] + std::f64::consts::TAU - ang[i]
        };
        gap = gap.max(d);
    }
    if gap > limit {
        return None;
    }
    let k = 4.0 / 3.0 * (2.0f64.sqrt() - 1.0) * r;
    // CCW (y-up) quarter arcs from angle 0.
    let a0 = Point { x: c.x + r, y: c.y };
    let a1 = Point { x: c.x, y: c.y + r };
    let a2 = Point { x: c.x - r, y: c.y };
    let a3 = Point { x: c.x, y: c.y - r };
    let ccw: Vec<(Point, [Point; 3])> = vec![
        (a0, [Point { x: c.x + r, y: c.y + k }, Point { x: c.x + k, y: c.y + r }, a1]),
        (a1, [Point { x: c.x - k, y: c.y + r }, Point { x: c.x - r, y: c.y + k }, a2]),
        (a2, [Point { x: c.x - r, y: c.y - k }, Point { x: c.x - k, y: c.y - r }, a3]),
        (a3, [Point { x: c.x + k, y: c.y - r }, Point { x: c.x + r, y: c.y - k }, a0]),
    ];
    let mut arcs = ccw;
    if hole {
        arcs.reverse();
        // also reverse each arc's internal control order so traversal is CW
        arcs = arcs
            .into_iter()
            .map(|(s, [c1, c2, e])| (e, [c2, c1, s]))
            .collect();
    }
    let start = rd(arcs[0].0);
    let spans: Vec<Span> = arcs
        .into_iter()
        .map(|(_, [c1, c2, e])| Span::Cubic {
            control_one: rd(c1),
            control_two: rd(c2),
            end: rd(e),
        })
        .collect();
    // Post-rounding re-verification (regression bar): recompute the circle
    // from the emitted integer-rounded anchors and re-check the dense source
    // residual, including the kappa cubic deviation bound.
    let anchors: Vec<Point> = {
        let mut v = vec![start];
        for s in &spans {
            if let Span::Cubic { end, .. } = s {
                v.push(*end);
            }
        }
        v
    };
    if anchors.len() == 5 {
        let cr = Point {
            x: (anchors[0].x + anchors[2].x) / 2.0,
            y: (anchors[0].y + anchors[2].y) / 2.0,
        };
        let rr = (0..4)
            .map(|i| (anchors[i].x - cr.x).hypot(anchors[i].y - cr.y))
            .sum::<f64>()
            / 4.0;
        let mut worst = 0.0f64;
        for p in &dense {
            worst = worst.max(((p.x - cr.x).hypot(p.y - cr.y) - rr).abs());
        }
        // Bound includes the derived output-rounding allowance: integer
        // anchors displace center and radius by <= 0.5*sqrt(2) each (0.5 per
        // axis), so the emitted circle may legitimately sit t_circle +
        // 2*0.5*sqrt(2) from the source. Anything beyond is the bug class
        // this gate exists for (phantom circles: resid ~ 1e2 units).
        if worst + 0.0003 * rr > t_circle + std::f64::consts::SQRT_2 {
            return None;
        }
    }
    Some(ReferenceRing { start, spans })
}
