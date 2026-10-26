//! Geometry-only training prototypes. All classifications remain proposed.
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}
#[derive(Clone, Debug)]
pub enum Span {
    Line(Point),
    Quadratic(Point, Point),
    Cubic(Point, Point, Point),
}
#[derive(Clone, Debug)]
pub struct Ring {
    pub start: Point,
    pub spans: Vec<Span>,
}
/// No metadata fields: content pins, routing names and case labels are not inputs.
#[derive(Clone, Debug)]
pub struct Geometry {
    pub rings: Vec<Ring>,
    pub advance: f64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GaugeStatistic {
    Median,
    ArithmeticMean,
}
/// Entry counts of the flatten resource guard. Counters only: no limit, value or selection depends on them.
/// A guard "hit" is one trip of the guard (the check that returns the limit error).
/// flatten_depth and flatten_points count the two conditions of the same guard separately
/// (both are counted when both hold at one trip).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct GuardCounts {
    pub flatten_depth: u64,
    pub flatten_points: u64,
}
/// Typed error of `fit`. `as_str` and `Display` give exactly the strings the untyped error carried.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FitError {
    UniqueTrainingResourceLimit,
    Other(String),
}
impl FitError {
    pub fn as_str(&self) -> &str {
        match self {
            FitError::UniqueTrainingResourceLimit => "unique_training_resource_limit",
            FitError::Other(e) => e,
        }
    }
}
impl std::fmt::Display for FitError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}
impl std::error::Error for FitError {}
impl From<String> for FitError {
    fn from(e: String) -> Self {
        if e == "unique_training_resource_limit" {
            FitError::UniqueTrainingResourceLimit
        } else {
            FitError::Other(e)
        }
    }
}
impl From<&str> for FitError {
    fn from(e: &str) -> Self {
        FitError::from(e.to_string())
    }
}
impl From<FitError> for String {
    fn from(e: FitError) -> String {
        e.as_str().to_string()
    }
}
impl PartialEq<&str> for FitError {
    fn eq(&self, o: &&str) -> bool {
        self.as_str() == *o
    }
}
#[derive(Clone, Debug)]
pub struct Rule {
    pub minimum_training: usize,
    pub gauge_statistic: GaugeStatistic,
    pub maximum_unique_training: usize,
    pub coverage_numerator: usize,
    pub coverage_denominator: usize,
    pub flatten_fraction: f64,
    pub bootstrap_replicates: usize,
    pub stability_fraction: f64,
}
impl Rule {
    pub fn canonical(&self) -> String {
        format!("geometry-prototypes-corpus-v6\nCONVENTION.minimum_training={}\nCONVENTION.maximum_unique_training={}\nCONVENTION.minimum_coverage={}/{}\nCONVENTION.flatten_fraction_bits={}\nCONVENTION.bootstrap_replicates={}\nCONVENTION.stability_fraction_bits={}\ncurve_policy=analytic_quadratic;cubic_unsupported\ntt_implied_oncurve=midpoint_between_adjacent_offcurve\ngauge=CONVENTION_{:?}_unique_preliminary_positive_analytic_bounds_height_uniform\nwall_levels=training_endpoint_y_union_and_interval_midpoints\nwall_method=analytic_horizontal_bezier_intersections_extreme_x\nprimary=width,height,analytic_signed_area_fraction,absolute_ymin_over_gauge,absolute_ymax_over_gauge,side_wall;CONVENTION_vertical_position_in_primary\nsecondary=proposed_counter_area,count,depth,pocket_width,depth;failure_does_not_gate_primary\nflatten_resource_policy=max_depth_24;max_points_65536;secondary_unavailable_on_limit\nfitter_wall_resource_policy=CONVENTION_max_integer_rows_1000000\nweights=CONVENTION_equal_total_per_group_1_over_G;within_group_1_over_channel_count;groups_whole_vertical_wall\nnormalization=training_channel_range_zero_range_exact_equality\ndistance=symmetric_euclidean\nhierarchy=complete_link\nselection=max_mean_silhouette_non_singletons;coverage_guard;ties_fewer_clusters_then_geometry_pin\nprototype=medoid;ties_geometry_pin\nradius=CONVENTION.quantile_1_of_within_cluster_LOO_nearest_member_distances\nquery=unique_nearest_medoid;accept_nearest_member_distance_same_magnitude_as_radius\nk1=unavailable\ncase=neutral_x\nstatus=proposed\ngauge_mean_contrast=one_sided_diagnostic;sorted_heights_sum_h_divide_n_fixed_order_not_sum_then_divide\nbootstrap=CONVENTION_deterministic_sha256_counter_indices;resample_training_scaling;frozen_gauge_and_wall_levels;stability_positive_silhouette_and_same_k;diagnostic_no_selection_change\nablations=drop_wall;drop_whole;drop_vertical;add_proposed_structure;no_selection_change\nidentity=CONVENTION_exact_raw_pin_dedupe_fit_once_alias_receipts_every_input;coverage_denominator_unique_geometry;raw_signed_zero_preserved\nresource=CONVENTION_max_unique_training_parameter;cached_pair_and_complete_link_max_update;group_contribution_summary_no_pair_channel_lines\nreceipt_exclusions=sorted_pin_dictionary;sorted_inclusive_index_runs;full_recoverability;typed_error_on_invalid_membership\nfloat_receipt=binary64_hex_bits;ordered_geometry_pin;fixed_sum_order\n",self.minimum_training,self.maximum_unique_training,self.coverage_numerator,self.coverage_denominator,bits(self.flatten_fraction),self.bootstrap_replicates,bits(self.stability_fraction),self.gauge_statistic)
    }

    pub fn pin(&self) -> String {
        hash(self.canonical().as_bytes())
    }
    fn valid(&self) -> bool {
        self.minimum_training >= 4
            && self.maximum_unique_training >= self.minimum_training
            && self.flatten_fraction.is_finite()
            && self.flatten_fraction > 0.
            && self.bootstrap_replicates > 0
            && self.stability_fraction.is_finite()
            && self.stability_fraction >= 0.
            && self.stability_fraction <= 1.
            && self.coverage_denominator > 0
            && self.coverage_numerator > 0
            && self.coverage_numerator <= self.coverage_denominator
    }
}
pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn bits(v: f64) -> String {
    format!("{:016x}", v.to_bits())
}
fn median(v: &[f64]) -> f64 {
    let mut v = v.to_vec();
    v.sort_by(f64::total_cmp);
    let m = v.len() / 2;
    if v.len() % 2 == 0 {
        v[m - 1] / 2. + v[m] / 2.
    } else {
        v[m]
    }
}
fn finite(p: Point) -> bool {
    p.x.is_finite() && p.y.is_finite()
}
fn cross(a: Point, b: Point, c: Point) -> Option<f64> {
    let v = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    v.is_finite().then_some(v)
}
fn within(p: Point, a: Point, b: Point) -> bool {
    p.x >= a.x.min(b.x) && p.x <= a.x.max(b.x) && p.y >= a.y.min(b.y) && p.y <= a.y.max(b.y)
}
fn contact(a: Point, b: Point, c: Point, d: Point) -> Option<bool> {
    let u = cross(a, b, c)?;
    let v = cross(a, b, d)?;
    let w = cross(c, d, a)?;
    let z = cross(c, d, b)?;
    Some(
        (((u < 0. && v > 0.) || (u > 0. && v < 0.)) && ((w < 0. && z > 0.) || (w > 0. && z < 0.)))
            || (u == 0. && within(c, a, b))
            || (v == 0. && within(d, a, b))
            || (w == 0. && within(a, c, d))
            || (z == 0. && within(b, c, d)),
    )
}
fn simple(ps: &[Point]) -> bool {
    let n = ps.len() - 1;
    for i in 0..n {
        if ps[i] == ps[i + 1] {
            return false;
        }
        for j in i + 1..n {
            if j == i + 1 || (i == 0 && j == n - 1) {
                let (a, b, c) = if j == i + 1 {
                    (ps[i], ps[i + 1], ps[j + 1])
                } else {
                    (ps[j], ps[0], ps[1])
                };
                let z = cross(a, b, c);
                if z.is_none() {
                    return false;
                }
                if z == Some(0.) {
                    let dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y);
                    if !dot.is_finite() || dot <= 0. {
                        return false;
                    }
                }
            } else if contact(ps[i], ps[i + 1], ps[j], ps[j + 1]) != Some(false) {
                return false;
            }
        }
    }
    true
}
fn area(ps: &[Point]) -> Option<f64> {
    let v = ps
        .windows(2)
        .map(|w| w[0].x * w[1].y - w[1].x * w[0].y)
        .sum::<f64>()
        / 2.;
    (v.is_finite() && v != 0.).then_some(v)
}
fn inside(p: Point, ps: &[Point]) -> Option<bool> {
    let mut yes = false;
    for w in ps.windows(2) {
        let a = w[0];
        let b = w[1];
        if cross(a, b, p)? == 0. && within(p, a, b) {
            return None;
        }
        if (a.y > p.y) != (b.y > p.y) {
            let x = a.x + (b.x - a.x) * (p.y - a.y) / (b.y - a.y);
            if !x.is_finite() {
                return None;
            }
            if p.x < x {
                yes = !yes
            }
        }
    }
    Some(yes)
}
fn pocket(ps: &[Point]) -> Option<(f64, f64)> {
    let n = ps.len() - 1;
    let mut ix: Vec<_> = (0..n).collect();
    ix.sort_by(|&a, &b| {
        ps[a]
            .x
            .total_cmp(&ps[b].x)
            .then(ps[a].y.total_cmp(&ps[b].y))
    });
    let (mut lo, mut hi) = (Vec::<usize>::new(), Vec::<usize>::new());
    for (c, seq) in [
        (&mut lo, ix.clone()),
        (&mut hi, ix.into_iter().rev().collect()),
    ] {
        for k in seq {
            while c.len() >= 2 {
                let m = c.len();
                if cross(ps[c[m - 2]], ps[c[m - 1]], ps[k])? < 0. {
                    c.pop();
                } else {
                    break;
                }
            }
            c.push(k)
        }
    }
    lo.pop();
    hi.pop();
    lo.extend(hi);
    let signed = area(ps)?;
    let (mut width_sum, mut depth_max) = (0., 0.0f64);
    for k in 0..lo.len() {
        let (mut a, mut b) = (lo[k], lo[(k + 1) % lo.len()]);
        if signed < 0. {
            std::mem::swap(&mut a, &mut b)
        }
        let w = (ps[b].x - ps[a].x).hypot(ps[b].y - ps[a].y);
        if !w.is_finite() || w == 0. {
            return None;
        }
        let mut j = a;
        let mut depth = 0.0f64;
        let mut count = 0;
        while j != b {
            depth = depth.max(cross(ps[a], ps[b], ps[j])?.abs() / w);
            j = (j + 1) % n;
            count += 1;
            if count > n {
                return None;
            }
        }
        if depth > 0. {
            width_sum += w;
            depth_max = depth_max.max(depth)
        }
    }
    (width_sum.is_finite() && depth_max.is_finite()).then_some((width_sum, depth_max))
}
#[derive(Clone, Debug)]
struct Shape {
    pin: String,
    raw_pin: String,
    base: Vec<f64>,
    secondary_reason: Option<String>,
    absolute_y: [f64; 2],
    original: Geometry,
}
fn raw_receipt(g: &Geometry) -> String {
    let mut s = format!("geometry-v1\nadvance={}\n", bits(g.advance));
    for r in &g.rings {
        s += &format!("M {},{}\n", bits(r.start.x), bits(r.start.y));
        for p in &r.spans {
            match p {
                Span::Line(p) => s += &format!("L {},{}\n", bits(p.x), bits(p.y)),
                Span::Quadratic(a, b) => {
                    s += &format!(
                        "Q {},{} {},{}\n",
                        bits(a.x),
                        bits(a.y),
                        bits(b.x),
                        bits(b.y)
                    )
                }
                Span::Cubic(a, b, c) => {
                    s += &format!(
                        "C {},{} {},{} {},{}\n",
                        bits(a.x),
                        bits(a.y),
                        bits(b.x),
                        bits(b.y),
                        bits(c.x),
                        bits(c.y)
                    )
                }
            }
        }
    }
    s
}
/// Float-bit identity for raw geometry, including unsupported curves.
pub fn geometry_pin(g: &Geometry) -> String {
    hash(raw_receipt(g).as_bytes())
}

#[derive(Clone, Copy, Debug)]
enum Segment {
    L(Point, Point),
    Q(Point, Point, Point),
}
fn eval(s: Segment, t: f64) -> Point {
    match s {
        Segment::L(a, b) => Point {
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
        },
        Segment::Q(a, c, b) => {
            let u = 1. - t;
            Point {
                x: u * u * a.x + 2. * u * t * c.x + t * t * b.x,
                y: u * u * a.y + 2. * u * t * c.y + t * t * b.y,
            }
        }
    }
}
fn roots(a: f64, b: f64, c: f64) -> Vec<f64> {
    if [a, b, c].iter().any(|v| !v.is_finite()) {
        return vec![f64::NAN];
    }
    if a == 0. {
        if b == 0. {
            return vec![];
        }
        return vec![-c / b];
    }
    let d = b * b - 4. * a * c;
    if !d.is_finite() {
        return vec![f64::NAN];
    }
    if d < 0. {
        return vec![];
    }
    let q = -0.5 * (b + d.sqrt().copysign(b));
    if q == 0. {
        vec![-b / (2. * a)]
    } else {
        let mut r = vec![q / a, c / q];
        r.sort_by(f64::total_cmp);
        r.dedup_by(|a, b| a.to_bits() == b.to_bits());
        r
    }
}
fn green(s: Segment) -> f64 {
    let (a, b, c) = match s {
        Segment::L(p, q) => (
            p,
            Point {
                x: q.x - p.x,
                y: q.y - p.y,
            },
            Point { x: 0., y: 0. },
        ),
        Segment::Q(p, q, r) => (
            p,
            Point {
                x: 2. * (q.x - p.x),
                y: 2. * (q.y - p.y),
            },
            Point {
                x: p.x - 2. * q.x + r.x,
                y: p.y - 2. * q.y + r.y,
            },
        ),
    };
    let cr = |p: Point, q: Point| p.x * q.y - p.y * q.x;
    (cr(a, b) + cr(a, c) + cr(b, c) / 3.) / 2.
}
fn flatten(s: Segment, tol: f64, out: &mut Vec<Point>, guards: &mut GuardCounts) -> Result<(), String> {
    flatten_depth(s, tol, out, 0, guards)
}
fn flatten_depth(s: Segment, tol: f64, out: &mut Vec<Point>, depth: usize, guards: &mut GuardCounts) -> Result<(), String> {
    if !tol.is_finite() || tol <= 0. {
        return Err("flatten_tolerance_unavailable".into());
    }
    let depth_hit = depth > 24;
    let points_hit = out.len() >= 65536;
    if depth_hit || points_hit {
        guards.flatten_depth += depth_hit as u64;
        guards.flatten_points += points_hit as u64;
        return Err("flatten_resource_limit".into());
    }
    match s {
        Segment::L(_, b) => out.push(b),
        Segment::Q(a, c, b) => {
            let dx = b.x - a.x;
            let dy = b.y - a.y;
            let len = dx.hypot(dy);
            let error = if len == 0. {
                (c.x - a.x).hypot(c.y - a.y)
            } else {
                cross(a, b, c).ok_or("flatten_overflow")?.abs() / len
            };
            if !error.is_finite() {
                return Err("flatten_overflow".into());
            }
            if error <= tol {
                out.push(b)
            } else {
                let m = |p: Point, q: Point| Point {
                    x: p.x / 2. + q.x / 2.,
                    y: p.y / 2. + q.y / 2.,
                };
                let ac = m(a, c);
                let cb = m(c, b);
                let mid = m(ac, cb);
                if mid == a || mid == b {
                    return Err("flatten_precision_unavailable".into());
                }
                flatten_depth(Segment::Q(a, ac, mid), tol, out, depth + 1, guards)?;
                flatten_depth(Segment::Q(mid, cb, b), tol, out, depth + 1, guards)?;
            }
        }
    }
    Ok(())
}
fn segments(g: &Geometry) -> Result<Vec<Vec<Segment>>, String> {
    if !g.advance.is_finite() || g.advance < 0. || g.rings.is_empty() {
        return Err("invalid_geometry".into());
    }
    let mut rs = Vec::new();
    for r in &g.rings {
        if !finite(r.start) {
            return Err("nonfinite_geometry".into());
        }
        let mut cur = r.start;
        let mut ss = Vec::new();
        for sp in &r.spans {
            let (seg, e) = match sp {
                Span::Line(b) => (Segment::L(cur, *b), *b),
                Span::Quadratic(c, b) if finite(*c) => (Segment::Q(cur, *c, *b), *b),
                Span::Quadratic(..) => return Err("nonfinite_geometry".into()),
                Span::Cubic(..) => return Err("unsupported_curve_type".into()),
            };
            if !finite(e) {
                return Err("nonfinite_geometry".into());
            }
            ss.push(seg);
            cur = e;
        }
        if ss.is_empty() || cur != r.start {
            return Err("open_or_empty_contour".into());
        }
        rs.push(ss);
    }
    Ok(rs)
}
fn analytic_bounds(rs: &[Vec<Segment>]) -> Result<(f64, f64, f64, f64), String> {
    let mut ps = Vec::new();
    for s in rs.iter().flatten() {
        ps.push(eval(*s, 0.));
        ps.push(eval(*s, 1.));
        if let Segment::Q(a, c, b) = s {
            for (p, q, r) in [(a.x, c.x, b.x), (a.y, c.y, b.y)] {
                let den = p - 2. * q + r;
                if !den.is_finite() || !(p - q).is_finite() {
                    return Err("bounds_numeric_failure".into());
                }
                if den != 0. {
                    let t = (p - q) / den;
                    if t > 0. && t < 1. {
                        ps.push(eval(*s, t));
                    }
                }
            }
        }
    }
    if ps.iter().any(|p| !finite(*p)) {
        return Err("bounds_nonfinite".into());
    }
    Ok((
        ps.iter().map(|p| p.x).reduce(f64::min).unwrap(),
        ps.iter().map(|p| p.x).reduce(f64::max).unwrap(),
        ps.iter().map(|p| p.y).reduce(f64::min).unwrap(),
        ps.iter().map(|p| p.y).reduce(f64::max).unwrap(),
    ))
}
fn preliminary_height(g: &Geometry) -> Result<f64, String> {
    let rs = segments(g)?;
    let (_, _, a, b) = analytic_bounds(&rs)?;
    let h = b - a;
    if h.is_finite() && h > 0. {
        Ok(h)
    } else {
        Err("geometry_gauge_unavailable".into())
    }
}
fn shape(g: &Geometry, tolerance: f64) -> Result<Shape, String> {
    shape_counted(g, tolerance, &mut GuardCounts::default())
}
fn shape_counted(g: &Geometry, tolerance: f64, guards: &mut GuardCounts) -> Result<Shape, String> {
    let rs = segments(g)?;
    let (xmin, xmax, ymin, ymax) = analytic_bounds(&rs)?;
    let width = xmax - xmin;
    let height = ymax - ymin;
    if !width.is_finite() || !height.is_finite() || width <= 0. || height <= 0. {
        return Err("geometry_gauge_unavailable".into());
    }
    let raw_pin = geometry_pin(g);
    let signed: Vec<f64> = rs
        .iter()
        .map(|ss| ss.iter().map(|&seg| green(seg)).sum::<f64>())
        .collect();
    if signed.iter().any(|a| !a.is_finite()) {
        return Err("area_unavailable".into());
    }
    // Secondary proposed structure may abstain without removing analytic primary geometry.
    let secondary = (|| -> Result<(f64, f64, f64, f64, f64), String> {
        let mut polys = Vec::new();
        for ss in &rs {
            let mut ps = vec![eval(ss[0], 0.)];
            for &seg in ss {
                flatten(seg, tolerance, &mut ps, guards)?;
            }
            if ps.len() < 4 || !simple(&ps) {
                return Err("proposed_polygon_topology_unavailable".into());
            }
            for p in &mut ps {
                p.x -= xmin;
                p.y -= ymin;
            }
            polys.push(ps);
        }
        for i in 0..polys.len() {
            for j in i + 1..polys.len() {
                for x in polys[i].windows(2) {
                    for y in polys[j].windows(2) {
                        if contact(x[0], x[1], y[0], y[1]) != Some(false) {
                            return Err("proposed_inter_ring_contact_unavailable".into());
                        }
                    }
                }
            }
        }
        let (mut count, mut ca) = (0., 0.);
        let mut depth = 0;
        let (mut pw, mut pd) = (0., 0.0f64);
        for (i, ps) in polys.iter().enumerate() {
            let mut parents = Vec::new();
            for (j, other) in polys.iter().enumerate() {
                if i != j {
                    match inside(ps[0], other) {
                        Some(true) => parents.push(j),
                        Some(false) => (),
                        None => return Err("proposed_containment_unavailable".into()),
                    }
                }
            }
            depth = depth.max(parents.len());
            if !parents.is_empty() {
                parents.sort_by(|&a, &b| signed[a].abs().total_cmp(&signed[b].abs()));
                if signed[i].is_sign_positive() != signed[parents[0]].is_sign_positive() {
                    count += 1.;
                    ca += signed[i].abs();
                }
            }
            let (w, d) = pocket(ps).ok_or("proposed_pocket_unavailable")?;
            pw += w;
            pd = pd.max(d);
        }
        Ok((ca, count, depth as f64, pw, pd))
    })();
    let denom = width * height;
    if !denom.is_finite() || denom <= 0. {
        return Err("area_normalization_unavailable".into());
    }
    let secondary_reason = secondary.as_ref().err().cloned();
    let (ca, counts, depth, pw, pd) =
        secondary.unwrap_or((f64::NAN, f64::NAN, f64::NAN, f64::NAN, f64::NAN));
    let base = vec![
        width,
        height,
        signed.iter().sum::<f64>().abs() / denom,
        ca / denom,
        counts,
        depth,
        pw,
        pd,
    ];
    if base[..3].iter().any(|v| !v.is_finite()) {
        return Err("descriptor_nonfinite".into());
    }
    // Input content, not names, determines canonical ordering. Raw bits preserved.
    Ok(Shape {
        pin: raw_pin.clone(),
        raw_pin,
        base,
        secondary_reason,
        absolute_y: [ymin, ymax],
        original: g.clone(),
    })
}
fn wall(s: &Shape, y: f64) -> Result<Option<(f64, f64)>, String> {
    let rs = segments(&s.original)?;
    let (xmin, _, ymin, _) = analytic_bounds(&rs)?;
    let target = y + ymin;
    if !target.is_finite() {
        return Err("wall_numeric_failure".into());
    }
    let mut xs = Vec::new();
    for seg in rs.iter().flatten() {
        match *seg {
            Segment::L(a, b) => {
                if a.y == b.y {
                    if target == a.y {
                        xs.push(a.x - xmin);
                        xs.push(b.x - xmin)
                    }
                } else {
                    let dy = b.y - a.y;
                    let delta = target - a.y;
                    if !dy.is_finite() || !delta.is_finite() {
                        return Err("wall_numeric_failure".into());
                    }
                    let t = delta / dy;
                    if !t.is_finite() {
                        return Err("wall_numeric_failure".into());
                    }
                    if t >= 0. && t <= 1. {
                        xs.push(eval(*seg, t).x - xmin)
                    }
                }
            }
            Segment::Q(a, c, b) => {
                if a.y == c.y && c.y == b.y {
                    if target == a.y {
                        xs.push(a.x - xmin);
                        xs.push(b.x - xmin);
                        let den = a.x - 2. * c.x + b.x;
                        if !den.is_finite() {
                            return Err("wall_numeric_failure".into());
                        }
                        if den != 0. {
                            let t = (a.x - c.x) / den;
                            if t > 0. && t < 1. {
                                xs.push(eval(*seg, t).x - xmin)
                            }
                        }
                    }
                } else {
                    for t in roots(a.y - 2. * c.y + b.y, 2. * (c.y - a.y), a.y - target) {
                        if !t.is_finite() {
                            return Err("wall_numeric_failure".into());
                        }
                        if t >= 0. && t <= 1. {
                            xs.push(eval(*seg, t).x - xmin)
                        }
                    }
                }
            }
        }
    }
    if xs.iter().any(|x| !x.is_finite()) {
        return Err("wall_numeric_failure".into());
    }
    if xs.is_empty() {
        Ok(None)
    } else {
        Ok(Some((
            xs.iter().copied().reduce(f64::min).unwrap(),
            xs.iter().copied().reduce(f64::max).unwrap(),
        )))
    }
}

fn descriptor(s: &Shape, gauge: f64, levels: &[f64], right: bool) -> Vec<f64> {
    let mut d = s.base[..3].to_vec();
    for k in [0, 1] {
        d[k] /= gauge;
    }
    d.extend(s.absolute_y.iter().map(|y| y / gauge));
    for &level in levels {
        match wall(s, level * gauge) {
            Ok(Some((l, r))) => {
                d.push(1.);
                d.push(if right { r / gauge } else { l / gauge });
            }
            Ok(None) => {
                d.push(0.);
                d.push(0.);
            }
            Err(_) => {
                d.push(f64::NAN);
                d.push(f64::NAN);
            }
        }
    }
    d
}
#[derive(Clone, Debug)]
pub struct Candidate {
    pub k: usize,
    pub silhouette: Option<f64>,
    pub eligible: bool,
    pub excluded_pins: Vec<String>,
    pub coverage: f64,
    pub singleton_count: usize,
    pub singleton_fraction: f64,
    pub retained_count: usize,
    pub retained_clusters: usize,
}
#[derive(Clone, Debug)]
pub struct Cluster {
    pub class: u32,
    pub medoid_pin: String,
    pub prototype: Vec<f64>,
    pub radius: f64,
    pub loo_distances: Vec<f64>,
    pub members: Vec<String>,
    pub member_descriptors: Vec<Vec<f64>>,
}
#[derive(Clone, Debug)]
struct SideModel {
    min: Vec<f64>,
    range: Vec<f64>,
    constant: Vec<f64>,
    weights: Vec<f64>,
    curve: Vec<Candidate>,
    selected_silhouette: Option<f64>,
    clusters: Vec<Cluster>,
}
#[derive(Clone, Debug)]
pub struct Assignment {
    pub outline_pin: String,
    pub geometry_pin: String,
    pub left_class: Option<u32>,
    pub right_class: Option<u32>,
    pub left_distance: Option<f64>,
    pub right_distance: Option<f64>,
    pub query_only: bool,
    pub status: &'static str,
    pub unavailable_reason: Option<String>,
    pub prototype_pin: String,
}
#[derive(Clone, Debug)]
pub struct Artifact {
    rule_pin: String,
    rule: Rule,
    gauge: f64,
    levels: Vec<f64>,
    left: Option<SideModel>,
    right: Option<SideModel>,
    training: Vec<Assignment>,
    unavailable: Option<String>,
    pin: String,
    diagnostic: String,
    input_count: usize,
    aliases: Vec<(String, usize)>,
    guards: GuardCounts,
}
fn normalize(data: &[Vec<f64>]) -> (Vec<f64>, Vec<f64>, Vec<Vec<f64>>) {
    let n = data[0].len();
    let min: Vec<_> = (0..n)
        .map(|j| data.iter().map(|d| d[j]).reduce(f64::min).unwrap())
        .collect();
    let range: Vec<_> = (0..n)
        .map(|j| data.iter().map(|d| d[j]).reduce(f64::max).unwrap() - min[j])
        .collect();
    let out = data
        .iter()
        .map(|d| {
            (0..n)
                .map(|j| {
                    if range[j] == 0. {
                        0.
                    } else {
                        (d[j] - min[j]) / range[j]
                    }
                })
                .collect()
        })
        .collect();
    (min, range, out)
}
fn dist(a: &[f64], b: &[f64]) -> f64 {
    a.iter()
        .zip(b)
        .map(|(a, b)| (a - b) * (a - b))
        .sum::<f64>()
        .sqrt()
}
fn score(groups: &[Vec<usize>], distances: &[Vec<f64>]) -> Option<f64> {
    if groups.len() < 2 {
        return None;
    }
    let mut sum = 0.;
    let mut n = 0;
    for (k, g) in groups.iter().enumerate() {
        for &i in g {
            let a = g
                .iter()
                .filter(|&&j| j != i)
                .map(|&j| distances[i][j])
                .sum::<f64>()
                / (g.len() - 1) as f64;
            let b = groups
                .iter()
                .enumerate()
                .filter(|(j, _)| *j != k)
                .map(|(_, h)| h.iter().map(|&j| distances[i][j]).sum::<f64>() / h.len() as f64)
                .reduce(f64::min)
                .unwrap();
            if !a.is_finite() || !b.is_finite() {
                return None;
            }
            let den = a.max(b);
            sum += if den == 0. { 0. } else { (b - a) / den };
            n += 1
        }
    }
    Some(sum / n as f64)
}
fn side(
    data: &[Vec<f64>],
    pins: &[String],
    rule: &Rule,
    invalid_pins: &[String],
) -> Option<SideModel> {
    let len = data.first()?.len();
    let groups = if len >= 5 {
        vec![3, 2, len - 5]
    } else {
        vec![len]
    };
    side_grouped(data, pins, rule, invalid_pins, &groups)
}
fn side_grouped(
    data: &[Vec<f64>],
    pins: &[String],
    rule: &Rule,
    invalid_pins: &[String],
    group_sizes: &[usize],
) -> Option<SideModel> {
    if data.is_empty() || data.iter().flatten().any(|v| !v.is_finite()) {
        return None;
    }
    if group_sizes.iter().sum::<usize>() != data[0].len() {
        return None;
    }
    let active = group_sizes.iter().filter(|&&n| n > 0).count();
    if active == 0 {
        return None;
    }
    let weights: Vec<_> = group_sizes
        .iter()
        .flat_map(|&n| std::iter::repeat_n(1. / (active * n) as f64, n))
        .collect();
    let (min, range, mut ds) = normalize(data);
    if range
        .iter()
        .chain(ds.iter().flatten())
        .any(|v| !v.is_finite())
    {
        return None;
    }
    for row in &mut ds {
        for (j, v) in row.iter_mut().enumerate() {
            *v *= weights[j].sqrt();
        }
    }
    let mut distances = vec![vec![0.; pins.len()]; pins.len()];
    for i in 0..pins.len() {
        for j in i + 1..pins.len() {
            let d = dist(&ds[i], &ds[j]);
            if !d.is_finite() {
                return None;
            }
            distances[i][j] = d;
            distances[j][i] = d;
        }
    }
    let mut groups: Vec<_> = (0..pins.len()).map(|i| vec![i]).collect();
    let mut linkage = distances.clone();
    let mut curve = Vec::new();
    let mut best: Option<(f64, Vec<Vec<usize>>)> = None;
    loop {
        let kept: Vec<_> = groups.iter().filter(|g| g.len() > 1).cloned().collect();
        let mut excluded_pins: Vec<_> = groups
            .iter()
            .filter(|g| g.len() == 1)
            .map(|g| pins[g[0]].clone())
            .collect();
        let singleton_count = excluded_pins.len();
        let retained = pins.len() - singleton_count;
        excluded_pins.extend_from_slice(invalid_pins);
        excluded_pins.sort();
        let total = pins.len() + invalid_pins.len();
        let coverage = retained as f64 / total as f64;
        let sc = score(&kept, &distances);
        let eligible = retained >= rule.minimum_training
            && kept.len() >= 2
            && sc.is_some()
            && (retained as u128 * rule.coverage_denominator as u128
                >= total as u128 * rule.coverage_numerator as u128);
        curve.push(Candidate {
            k: groups.len(),
            silhouette: sc,
            eligible,
            excluded_pins,
            coverage,
            singleton_count,
            singleton_fraction: singleton_count as f64 / total as f64,
            retained_count: retained,
            retained_clusters: kept.len(),
        });
        if eligible {
            let s = sc.unwrap();
            if best.as_ref().is_none_or(|(b, g)| {
                s > *b
                    || (s == *b && (kept.len() < g.len() || (kept.len() == g.len() && kept < *g)))
            }) {
                best = Some((s, kept.clone()))
            }
        }
        if groups.len() == 1 {
            break;
        }
        let mut choice: Option<(f64, usize, usize)> = None;
        for a in 0..groups.len() {
            for b in a + 1..groups.len() {
                let d = linkage[a][b];
                if choice.is_none_or(|(v, _, _)| d < v) {
                    choice = Some((d, a, b))
                }
            }
        }
        let (_, a, b) = choice.unwrap();
        for j in 0..groups.len() {
            let d = linkage[a][j].max(linkage[b][j]);
            linkage[a][j] = d;
            linkage[j][a] = d;
        }
        linkage.remove(b);
        for row in &mut linkage {
            row.remove(b);
        }
        let g = groups.remove(b);
        groups[a].extend(g);
        groups[a].sort();
        let mut order: Vec<_> = (0..groups.len()).collect();
        order.sort_by(|&i, &j| groups[i].cmp(&groups[j]));
        groups = order.iter().map(|&i| groups[i].clone()).collect();
        linkage = order
            .iter()
            .map(|&i| order.iter().map(|&j| linkage[i][j]).collect())
            .collect();
    }
    let selected_silhouette = best.as_ref().map(|(s, _)| *s);
    let selected = best.map(|(_, g)| g).unwrap_or_default();
    let mut medoids = Vec::new();
    for g in selected {
        let mut med = g[0];
        let mut val = f64::INFINITY;
        for &i in &g {
            let x = g.iter().map(|&j| distances[i][j]).sum::<f64>();
            if x < val {
                val = x;
                med = i
            }
        }
        let mut loo: Vec<_> = g
            .iter()
            .map(|&i| {
                g.iter()
                    .filter(|&&j| j != i)
                    .map(|&j| distances[i][j])
                    .reduce(f64::min)
                    .unwrap()
            })
            .collect();
        loo.sort_by(f64::total_cmp);
        medoids.push((med, g, loo));
    }
    medoids.sort_by_key(|(i, _, _)| pins[*i].clone());
    let mut used = BTreeSet::new();
    let clusters = medoids
        .into_iter()
        .enumerate()
        .map(|(class, (med, g, loo))| {
            for &i in &g {
                used.insert(pins[i].clone());
            }
            Cluster {
                class: class as u32,
                medoid_pin: pins[med].clone(),
                prototype: ds[med].clone(),
                radius: *loo.last().unwrap(),
                loo_distances: loo,
                members: g.iter().map(|&i| pins[i].clone()).collect(),
                member_descriptors: g.iter().map(|&i| ds[i].clone()).collect(),
            }
        })
        .collect();
    Some(SideModel {
        weights,
        constant: min.clone(),
        min,
        range,
        curve,
        selected_silhouette,
        clusters,
    })
}
fn absent(pin: String, query: bool, reason: &str) -> Assignment {
    Assignment {
        outline_pin: pin.clone(),
        geometry_pin: pin,
        left_class: None,
        right_class: None,
        left_distance: None,
        right_distance: None,
        query_only: query,
        status: "proposed",
        unavailable_reason: Some(reason.into()),
        prototype_pin: String::new(),
    }
}
fn member_assignment(model: &SideModel, pin: &str) -> Option<u32> {
    model
        .clusters
        .iter()
        .find(|c| c.members.iter().any(|p| p == pin))
        .map(|c| c.class)
}
fn query_side(m: &SideModel, raw: &[f64]) -> Result<(u32, f64), String> {
    if raw.len() != m.min.len() {
        return Err("descriptor_schema_mismatch".into());
    }
    let mut ds = Vec::new();
    for j in 0..raw.len() {
        if !raw[j].is_finite() {
            return Err("descriptor_nonfinite".into());
        }
        if m.range[j] == 0. {
            if raw[j] != m.constant[j] {
                return Err("constant_channel_mismatch".into());
            }
            ds.push(0.)
        } else {
            ds.push((raw[j] - m.min[j]) / m.range[j] * m.weights[j].sqrt());
        }
    }
    let mut choices: Vec<_> = m
        .clusters
        .iter()
        .map(|c| (dist(&ds, &c.prototype), c))
        .collect();
    if choices.iter().any(|c| !c.0.is_finite()) {
        return Err("distance_numeric_failure".into());
    }
    choices.sort_by(|a, b| {
        a.0.total_cmp(&b.0)
            .then(a.1.medoid_pin.cmp(&b.1.medoid_pin))
    });
    if choices.len() > 1 && choices[0].0 == choices[1].0 {
        return Err("ambiguous_nearest_medoid".into());
    }
    let c = choices[0].1;
    let nearest = c
        .member_descriptors
        .iter()
        .map(|d| dist(&ds, d))
        .reduce(f64::min)
        .unwrap();
    if !nearest.is_finite() || nearest > c.radius {
        return Err("unclassifiable_outside_LOO_radius".into());
    }
    Ok((c.class, nearest))
}
/// Required rule hash is checked before accessing training geometry. No queries.
pub fn fit(training: &[Geometry], rule: Rule, expected_rule_pin: &str) -> Result<Artifact, FitError> {
    if !rule.valid() {
        return Err("invalid_preregistered_rule".into());
    }
    if rule.pin() != expected_rule_pin {
        return Err("rule_pin_mismatch".into());
    }
    let mut guards = GuardCounts::default();
    let mut heights = Vec::new();
    let mut rejected = Vec::new();
    let mut prelim = Vec::new();
    let mut raw_seen = std::collections::BTreeMap::<String, usize>::new();
    for g in training {
        let pin = geometry_pin(g);
        let count = raw_seen.entry(pin.clone()).or_default();
        *count += 1;
        if *count > 1 {
            continue;
        }
        if raw_seen.len() > rule.maximum_unique_training {
            return Err(FitError::UniqueTrainingResourceLimit);
        }
        match preliminary_height(g) {
            Ok(h) => {
                heights.push(h);
                prelim.push(g)
            }
            Err(e) => rejected.push(absent(pin, false, &e)),
        }
    }
    let gauge = if heights.is_empty() {
        0.
    } else {
        match rule.gauge_statistic {
            GaugeStatistic::Median => median(&heights),
            GaugeStatistic::ArithmeticMean => {
                let mut sorted = heights.clone();
                sorted.sort_by(f64::total_cmp);
                sorted.iter().map(|h| h / sorted.len() as f64).sum()
            }
        }
    };
    let tol = gauge * rule.flatten_fraction;
    let mut shapes = Vec::new();
    for g in prelim {
        match shape_counted(g, tol, &mut guards) {
            Ok(s) => shapes.push(s),
            Err(e) => rejected.push(absent(geometry_pin(g), false, &e)),
        }
    }
    shapes.sort_by(|a, b| a.pin.cmp(&b.pin));
    rejected.sort_by(|a, b| a.outline_pin.cmp(&b.outline_pin));
    let mut levels = Vec::new();
    for s in &shapes {
        let rs = segments(&s.original)?;
        let (_, _, ymin, _) = analytic_bounds(&rs)?;
        for ring in rs {
            for seg in ring {
                levels.push((eval(seg, 0.).y - ymin) / gauge);
                levels.push((eval(seg, 1.).y - ymin) / gauge);
            }
        }
    }
    levels.sort_by(f64::total_cmp);
    levels.dedup_by(|a, b| *a == *b);
    let mids: Vec<_> = levels.windows(2).map(|w| w[0] / 2. + w[1] / 2.).collect();
    levels.extend(mids);
    levels.sort_by(f64::total_cmp);
    levels.dedup_by(|a, b| *a == *b);
    let pins: Vec<_> = shapes.iter().map(|s| s.pin.clone()).collect();
    let invalid_pins: Vec<_> = rejected.iter().map(|a| a.outline_pin.clone()).collect();
    let (left, right, unavailable) = if shapes.is_empty() {
        (None, None, Some("insufficient_training_geometry".into()))
    } else {
        let l = side(
            &shapes
                .iter()
                .map(|s| descriptor(s, gauge, &levels, false))
                .collect::<Vec<_>>(),
            &pins,
            &rule,
            &invalid_pins,
        );
        let r = side(
            &shapes
                .iter()
                .map(|s| descriptor(s, gauge, &levels, true))
                .collect::<Vec<_>>(),
            &pins,
            &rule,
            &invalid_pins,
        );
        let reason = if shapes.len() < rule.minimum_training {
            Some("insufficient_training_geometry".into())
        } else if l.is_none() || r.is_none() {
            Some("descriptor_or_normalization_numeric_failure".into())
        } else if l.as_ref().is_none_or(|m| m.clusters.is_empty())
            || r.as_ref().is_none_or(|m| m.clusters.is_empty())
        {
            Some("no_eligible_multiclass_partition_k1_unavailable".into())
        } else {
            None
        };
        (l, r, reason)
    };
    let mut assignments = Vec::new();
    for s in &shapes {
        let mut a = absent(s.raw_pin.clone(), false, "unclassifiable_singleton");
        a.geometry_pin = s.pin.clone();
        if unavailable.is_some() {
            a.unavailable_reason = unavailable.clone();
        } else {
            a.left_class = left.as_ref().and_then(|m| member_assignment(m, &s.pin));
            a.right_class = right.as_ref().and_then(|m| member_assignment(m, &s.pin));
            if a.left_class.is_some() && a.right_class.is_some() {
                a.unavailable_reason = None;
            }
        }
        assignments.push(a)
    }
    assignments.extend(rejected);
    assignments.sort_by(|a, b| a.outline_pin.cmp(&b.outline_pin));
    let mut a = Artifact {
        rule_pin: expected_rule_pin.into(),
        rule,
        gauge,
        levels,
        left,
        right,
        training: assignments,
        unavailable,
        pin: String::new(),
        diagnostic: String::new(),
        input_count: training.len(),
        aliases: raw_seen.into_iter().collect(),
        guards,
    };
    let diagnostic = diagnostics(&a, &shapes).map_err(|e| e.to_string())?;
    a.diagnostic = diagnostic;
    let unique = a.training.clone();
    a.training = unique
        .into_iter()
        .flat_map(|row| {
            let n = a
                .aliases
                .iter()
                .find(|(p, _)| p == &row.outline_pin)
                .unwrap()
                .1;
            std::iter::repeat_n(row, n)
        })
        .collect();
    a.pin = a.canonical_receipt_counted().map_err(|e| e.to_string())?.2;
    for r in &mut a.training {
        r.prototype_pin = a.pin.clone()
    }
    Ok(a)
}
impl Artifact {
    /// Resource guard entry counts recorded while fitting the training set (also in the canonical receipt).
    pub fn guard_counts(&self) -> GuardCounts {
        self.guards
    }
    pub fn pin(&self) -> &str {
        &self.pin
    }
    pub fn training_assignments(&self) -> &[Assignment] {
        &self.training
    }
    pub fn available(&self) -> bool {
        self.unavailable.is_none()
    }
    pub fn unavailable_reason(&self) -> Option<&str> {
        self.unavailable.as_deref()
    }
    pub fn query(&self, g: &Geometry) -> Assignment {
        let p = geometry_pin(g);
        let mut a = absent(p.clone(), true, "unavailable");
        a.prototype_pin = self.pin.clone();
        if let Some(r) = &self.unavailable {
            a.unavailable_reason = Some(r.clone());
            return a;
        }
        if let Some(old) = self.training.iter().find(|r| {
            r.outline_pin == p
                && r.unavailable_reason.as_deref() == Some("unclassifiable_singleton")
        }) {
            a.unavailable_reason = old.unavailable_reason.clone();
            return a;
        }
        let s = match shape(g, self.gauge * self.rule.flatten_fraction) {
            Ok(s) => s,
            Err(e) => {
                a.unavailable_reason = Some(e);
                return a;
            }
        };
        a.geometry_pin = s.pin.clone();
        let l = query_side(
            self.left.as_ref().unwrap(),
            &descriptor(&s, self.gauge, &self.levels, false),
        );
        let r = query_side(
            self.right.as_ref().unwrap(),
            &descriptor(&s, self.gauge, &self.levels, true),
        );
        match (l, r) {
            (Ok((lc, ld)), Ok((rc, rd))) => {
                a.left_class = Some(lc);
                a.right_class = Some(rc);
                a.left_distance = Some(ld);
                a.right_distance = Some(rd);
                a.unavailable_reason = None
            }
            (Err(e), _) | (_, Err(e)) => a.unavailable_reason = Some(e),
        }
        a
    }
    /// Unhashed read-only supplement. Never part of canonical_receipt or pin.
    /// Coverage uses the frozen candidate curve, not a refit. Quantile uses
    /// frozen clusters and LOO distances, with nearest-rank ceil(0.9*n).
    pub fn sensitivity_receipt(&self, queries: &[Geometry]) -> String {
        let mut out = format!("read_only_sensitivity artifact_pin={} rule_pin={} selection_unchanged=true pins_unchanged=true\nbootstrap_replicates={} evidence={} diagnostic_only=true\n", self.pin, self.rule_pin, self.rule.bootstrap_replicates, if self.rule.bootstrap_replicates == 4 { "illustrative_not_precision_or_stability_guarantee" } else { "no_precision_or_stability_guarantee" });
        for (label, model) in [("left", &self.left), ("right", &self.right)] {
            let Some(m) = model else {
                out += &format!("sensitivity side={} unavailable=no_side_model\n", label);
                continue;
            };
            for numerator in [1usize, 3] {
                for c in &m.curve {
                    let total = c.retained_count + c.singleton_count
                        + c.excluded_pins.len().saturating_sub(c.singleton_count);
                    let eligible = c.retained_count >= self.rule.minimum_training
                        && c.retained_clusters >= 2 && c.silhouette.is_some()
                        && (c.retained_count as u128 * 4 >= total as u128 * numerator as u128);
                    out += &format!("coverage_sensitivity side={} threshold={}/4 k={} retained={} denominator={} retained_clusters={} silhouette={} diagnostic_eligible={} frozen_curve=true no_refit=true\n",label,numerator,c.k,c.retained_count,total,c.retained_clusters,c.silhouette.map(bits).unwrap_or_default(),eligible);
                }
            }
            for c in &m.clusters {
                let radius = diagnostic_q90(&c.loo_distances);
                out += &format!("quantile_sensitivity side={} class={} medoid_pin={} q=9/10 convention=nearest_rank_ceil_q_times_n loo_count={} radius={} production_radius={} frozen_cluster=true\n",label,c.class,c.medoid_pin,c.loo_distances.len(),radius.map(bits).unwrap_or_else(||"unavailable".into()),bits(c.radius));
            }
        }
        let mut ordered: Vec<_> = queries.iter().collect();
        ordered.sort_by_key(|g| geometry_pin(g));
        for g in ordered {
            let production = self.query(g);
            let reason = production.unavailable_reason.as_deref().unwrap_or("");
            out += &format!("query_numerical_abstention pin={} production_reason={} diagnostic_reason={}\n",geometry_pin(g),reason,if reason == "constant_channel_mismatch" {"zero_range_exact_equality_mismatch"}else{reason});
            if !self.available() || reason == "unclassifiable_singleton" {
                out += &format!("quantile_query pin={} unavailable={}\n",geometry_pin(g),reason);
                continue;
            }
            let shape = match shape(g, self.gauge * self.rule.flatten_fraction) {
                Ok(s) => s,
                Err(e) => {out += &format!("quantile_query pin={} unavailable={}\n",geometry_pin(g),e);continue;}
            };
            for (label, right, model) in [("left",false,&self.left),("right",true,&self.right)] {
                let Some(model) = model else {continue;};
                let mut contrast = model.clone();
                for c in &mut contrast.clusters {if let Some(r) = diagnostic_q90(&c.loo_distances) {c.radius=r;}}
                let result = query_side(&contrast,&descriptor(&shape,self.gauge,&self.levels,right));
                match result {
                    Ok((class,distance)) => out += &format!("quantile_query pin={} side={} q=9/10 class={} nearest_member_distance={} diagnostic_accepted=true\n",geometry_pin(g),label,class,bits(distance)),
                    Err(e) => out += &format!("quantile_query pin={} side={} q=9/10 diagnostic_accepted=false reason={}\n",geometry_pin(g),label,e),
                }
            }
        }
        out
    }
    pub fn query_receipt(&self, queries: &[Geometry]) -> String {
        let mut rows: Vec<_> = queries.iter().map(|g| self.query(g)).collect();
        rows.sort_by(|a, b| a.outline_pin.cmp(&b.outline_pin));
        let unavailable = rows
            .iter()
            .filter(|a| a.unavailable_reason.is_some())
            .count();
        let mut s=format!("query_only=true\nprototype={}\nquery_count={}\nunavailable_count={}\nabstention_fraction={}\n",self.pin,rows.len(),unavailable,bits(if rows.is_empty(){0.}else{unavailable as f64/rows.len() as f64}));
        for r in rows {
            s += &assignment_receipt(&r);
        }
        s
    }
    pub fn canonical_receipt(&self) -> Result<String, ReceiptError> {
        Ok(self.emit_canonical_receipt(Sink::text())?.text.expect("text sink retains text"))
    }
    /// Stream exactly the canonical receipt bytes into SHA256 and counters.
    /// No full receipt String is collected.
    pub fn canonical_receipt_counted(&self) -> Result<(u64, u64, String), ReceiptError> {
        let sink=self.emit_canonical_receipt(Sink::digest())?;
        Ok((sink.bytes,sink.lines,sink.hex()))
    }
    fn emit_canonical_receipt(&self, mut s: Sink) -> Result<Sink, ReceiptError> {
        s += &format!("prototype-artifact-corpus-v7\nrule={}\nstatus=proposed\ngauge={}\nflatten_tolerance={}\nunavailable={}\ntraining_count={}\nexcluded_count={}\nexcluded_fraction={}\n",self.rule_pin,bits(self.gauge),bits(self.gauge*self.rule.flatten_fraction),self.unavailable.as_deref().unwrap_or(""),self.training.len(),self.training.iter().filter(|r|r.unavailable_reason.is_some()).count(),bits(if self.training.is_empty(){0.}else{self.training.iter().filter(|r|r.unavailable_reason.is_some()).count() as f64/self.training.len() as f64}));
        s += &format!(
            "gauge_statistic={:?} mean_contrast=one_sided_diagnostic_only\n",
            self.rule.gauge_statistic
        );
        s += &format!(
            "guard_hits scope=fit_training flatten_depth={} flatten_points={}\n",
            self.guards.flatten_depth, self.guards.flatten_points
        );
        s+=&format!("wall_level_count={} descriptor_channel_count={} input_count={} unique_geometry_count={} alias_count={}\n",self.levels.len(),5+2*self.levels.len(),self.input_count,self.aliases.len(),self.input_count-self.aliases.len());
        let unique_excluded = self
            .aliases
            .iter()
            .filter(|(p, _)| {
                self.training
                    .iter()
                    .find(|a| &a.outline_pin == p)
                    .is_some_and(|a| a.unavailable_reason.is_some())
            })
            .count();
        s+=&format!("unique_excluded_count={} unique_abstention_fraction={} coverage_denominator=unique_geometry\n",unique_excluded,bits(if self.aliases.is_empty(){0.}else{unique_excluded as f64/self.aliases.len() as f64}));
        for (i, (p, _)) in self.aliases.iter().enumerate() {
            s += &format!("pin_dictionary {} {}\n", i, p);
        }
        for (p, n) in &self.aliases {
            s += &format!("identity pin={} input_occurrences={} fit_once=true\n", p, n);
        }
        for &y in &self.levels {
            s += &format!("level {}\n", bits(y));
        }
        for (label, m) in [("left", &self.left), ("right", &self.right)] {
            s += &format!("side {}\n", label);
            if let Some(m) = m {
                s += &format!(
                    "selected_silhouette={}\n",
                    m.selected_silhouette.map(bits).unwrap_or_default()
                );
                for (j, (&lo, &range)) in m.min.iter().zip(&m.range).enumerate() {
                    s += &format!(
                        "normalization {} {} {} weight={}\n",
                        j,
                        bits(lo),
                        bits(range),
                        bits(m.weights[j])
                    );
                }
                for (name, start, end) in [
                    ("whole", 0, 3),
                    ("vertical", 3, 5),
                    ("wall", 5, m.range.len()),
                ] {
                    s+=&format!("effective_group_weight side={} group={} weight={} nonzero_range_channels={}\n",label,name,bits(effective_weight(m,start,end)),(start..end).filter(|&i|m.range[i]!=0.).count());
                }
                for c in &m.curve {
                    s+=&format!("candidate_counts k={} singletons={} singleton_fraction={} retained={} retained_clusters={}\n",c.k,c.singleton_count,bits(c.singleton_fraction),c.retained_count,c.retained_clusters);
                    s += &format!(
                        "candidate k={} silhouette={} eligible={} coverage={} excluded_index_runs={}\n",
                        c.k,
                        c.silhouette.map(bits).unwrap_or_default(),
                        c.eligible,
                        bits(c.coverage),
                        compact_exclusions(&c.excluded_pins,&self.aliases.iter().map(|(p,_)|p.clone()).collect::<Vec<_>>())?
                    );
                }
                for c in &m.clusters {
                    s += &format!(
                        "cluster {} medoid={} radius={}\n",
                        c.class,
                        c.medoid_pin,
                        bits(c.radius)
                    );
                    for v in &c.prototype {
                        s += &format!("prototype {}\n", bits(*v))
                    }
                    for v in &c.loo_distances {
                        s += &format!("LOO {}\n", bits(*v))
                    }
                    for (p, d) in c.members.iter().zip(&c.member_descriptors) {
                        s += &format!(
                            "member {} {}\n",
                            p,
                            d.iter().copied().map(bits).collect::<Vec<_>>().join(",")
                        );
                    }
                }
            } else {
                s += "model_unavailable\n"
            }
        }
        for r in &self.training {
            s += &assignment_receipt(r)
        }
        s += &self.diagnostic;
        Ok(s)
    }
}

// Internal sink for streaming canonical receipt bytes and counters.
struct Sink { bytes: u64, lines: u64, h: sha2::Sha256, text: Option<String> }
impl Sink {
    fn digest() -> Self { Self { bytes: 0, lines: 0, h: Sha256::new(), text: None } }
    fn text() -> Self { Self { text: Some(String::new()), ..Self::digest() } }
    fn push(&mut self, c: &str) { if let Some(text)=&mut self.text { text.push_str(c); } self.bytes += c.len() as u64; self.lines += c.matches('\n').count() as u64; sha2::Digest::update(&mut self.h, c.as_bytes()); }
    fn hex(self) -> String { format!("{:x}", sha2::Digest::finalize(self.h)) }
}
impl std::ops::AddAssign<&str> for Sink { fn add_assign(&mut self, r: &str) { self.push(r) } }
impl<'a> std::ops::AddAssign<&'a String> for Sink { fn add_assign(&mut self, r: &'a String) { self.push(r) } }

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ReceiptError {
    UnregisteredPin { pin: String },
    InvalidPinDictionary,
    InvalidExclusionOrder,
}
impl std::fmt::Display for ReceiptError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnregisteredPin { pin } => write!(f, "receipt_unregistered_pin:{pin}"),
            Self::InvalidPinDictionary => write!(f, "receipt_invalid_pin_dictionary"),
            Self::InvalidExclusionOrder => write!(f, "receipt_invalid_exclusion_order"),
        }
    }
}
impl std::error::Error for ReceiptError {}
fn compact_exclusions(pins: &[String], dictionary: &[String]) -> Result<String, ReceiptError> {
    if dictionary.windows(2).any(|w| w[0] >= w[1]) {
        return Err(ReceiptError::InvalidPinDictionary);
    }
    if pins.windows(2).any(|w| w[0] >= w[1]) {
        return Err(ReceiptError::InvalidExclusionOrder);
    }
    let ids: Vec<_> = pins
        .iter()
        .map(|p| {
            dictionary
                .binary_search(p)
                .map_err(|_| ReceiptError::UnregisteredPin { pin: p.clone() })
        })
        .collect::<Result<_, _>>()?;
    let mut out = Vec::new();
    let mut i = 0;
    while i < ids.len() {
        let start = ids[i];
        let mut end = start;
        i += 1;
        while i < ids.len() && ids[i] == end + 1 {
            end = ids[i];
            i += 1;
        }
        out.push(if start == end {
            start.to_string()
        } else {
            format!("{start}-{end}")
        });
    }
    Ok(out.join(","))
}
fn effective_weight(m: &SideModel, start: usize, end: usize) -> f64 {
    (start..end)
        .filter(|&i| m.range[i] != 0.)
        .map(|i| m.weights[i])
        .fold(0.0, |sum, w| sum + w)
}
fn assignment_receipt(r: &Assignment) -> String {
    format!("assignment outline={} geometry={} left={:?} right={:?} left_distance={} right_distance={} query_only={} status={} reason={}\n",r.outline_pin,r.geometry_pin,r.left_class,r.right_class,r.left_distance.map(bits).unwrap_or_default(),r.right_distance.map(bits).unwrap_or_default(),r.query_only,r.status,r.unavailable_reason.as_deref().unwrap_or(""))
}
/// Fitter mapping contains no route names. Caller joins outline_pin externally.
#[derive(Clone, Debug, PartialEq)]
pub struct KnowledgeFields {
    pub case: char,
    pub freq_weight: i32,
    pub right_class: u32,
    pub left_class: u32,
}
pub fn knowledge(a: &Assignment) -> Option<KnowledgeFields> {
    if a.unavailable_reason.is_some() {
        None
    } else {
        Some(KnowledgeFields {
            case: 'x',
            freq_weight: 0,
            right_class: a.right_class?,
            left_class: a.left_class?,
        })
    }
}
/// Decode TrueType point streams. Adjacent off-curve points imply midpoint.
#[derive(Clone, Copy, Debug)]
pub struct TTPoint {
    pub point: Point,
    pub on_curve: bool,
}
pub fn truetype_contour(points: &[TTPoint]) -> Result<Ring, String> {
    if points.is_empty() || points.iter().any(|p| !finite(p.point)) {
        return Err("invalid_point_stream".into());
    }
    let n = points.len();
    let midpoint = |a: Point, b: Point| Point {
        x: a.x / 2. + b.x / 2.,
        y: a.y / 2. + b.y / 2.,
    };
    let (start, mut seq) = if points[0].on_curve {
        (points[0].point, points[1..].to_vec())
    } else if points[n - 1].on_curve {
        (points[n - 1].point, points[..n - 1].to_vec())
    } else {
        (
            midpoint(points[n - 1].point, points[0].point),
            points.to_vec(),
        )
    };
    seq.push(TTPoint {
        point: start,
        on_curve: true,
    });
    let mut spans = Vec::new();
    let mut i = 0;
    while i < seq.len() {
        if seq[i].on_curve {
            spans.push(Span::Line(seq[i].point));
            i += 1;
        } else {
            let c = seq[i].point;
            let next = seq.get(i + 1).ok_or("offcurve_unclosed")?;
            if next.on_curve {
                spans.push(Span::Quadratic(c, next.point));
                i += 2;
            } else {
                spans.push(Span::Quadratic(c, midpoint(c, next.point)));
                i += 1;
            }
        }
    }
    Ok(Ring { start, spans })
}
fn diagnostic_q90(distances: &[f64]) -> Option<f64> {
    if distances.is_empty() || distances.iter().any(|d| !d.is_finite() || *d < 0.) { return None; }
    let mut sorted=distances.to_vec();sorted.sort_by(f64::total_cmp);
    let rank=sorted.len() - sorted.len()/10; // ceil(9*n/10), without multiplication overflow
    Some(sorted[rank-1])
}
fn pair_squared_total(values: &[f64]) -> f64 {
    let mut mean = 0.;
    let mut m2 = 0.;
    for (i, &x) in values.iter().enumerate() {
        let delta = x - mean;
        mean += delta / (i + 1) as f64;
        m2 += delta * (x - mean);
    }
    values.len() as f64 * m2
}
fn diagnostics(a: &Artifact, shapes: &[Shape]) -> Result<String, ReceiptError> {
    let mut out = String::from("diagnostics_no_selection_change\n");
    if shapes.len() < a.rule.minimum_training {
        return Ok(out);
    }
    let pins: Vec<_> = shapes.iter().map(|s| s.pin.clone()).collect();
    let mut stable = 0;
    let mut trials = 0;
    let mut failed = 0usize;
    let mut sides_without_bootstrap = 0usize;
    for (label, right) in [("left", false), ("right", true)] {
        let data: Vec<_> = shapes
            .iter()
            .map(|s| descriptor(s, a.gauge, &a.levels, right))
            .collect();
        if data.iter().flatten().any(|v| !v.is_finite()) {
            out += &format!(
                "diagnostic side={} unavailable=descriptor_numeric_failure\n",
                label
            );
            sides_without_bootstrap += 1;
            continue;
        }
        let original = if right { &a.right } else { &a.left };
        // Aggregate all-pair squared contributions in O(n * channels), no pair rows.
        if let Some(m) = original {
            let mut totals = [0.; 3];
            for ch in 0..m.range.len() {
                let values: Vec<_> = data
                    .iter()
                    .map(|row| {
                        if m.range[ch] == 0. {
                            0.
                        } else {
                            (row[ch] - m.min[ch]) / m.range[ch] * m.weights[ch].sqrt()
                        }
                    })
                    .collect();
                let group = if ch < 3 {
                    0
                } else if ch < 5 {
                    1
                } else {
                    2
                };
                totals[group] += pair_squared_total(&values);
            }
            let total: f64 = totals.iter().sum();
            for (j, name) in ["whole", "vertical", "wall"].iter().enumerate() {
                out+=&format!("contribution_group side={} group={} pair_squared_total={} fraction={} total_group_weight={} method=CONVENTION_n_times_Welford_M2\n",label,name,bits(totals[j]),if total==0.{"unavailable".into()}else{bits(totals[j]/total)},bits(m.weights.iter().enumerate().filter(|(ch,_)|if j==0{*ch<3}else if j==1{*ch>=3&&*ch<5}else{*ch>=5}).map(|(_,w)|*w).sum()));
            }
        }
        for (name, ab) in [
            (
                "drop_wall",
                data.iter().map(|d| d[..5].to_vec()).collect::<Vec<_>>(),
            ),
            (
                "drop_whole",
                data.iter().map(|d| d[3..].to_vec()).collect::<Vec<_>>(),
            ),
            (
                "drop_vertical",
                data.iter()
                    .map(|d| {
                        let mut v = d[..3].to_vec();
                        v.extend_from_slice(&d[5..]);
                        v
                    })
                    .collect::<Vec<_>>(),
            ),
            (
                "add_proposed_structure",
                shapes
                    .iter()
                    .zip(&data)
                    .map(|(s, d)| {
                        let mut v = d.clone();
                        for (j, &x) in s.base[3..].iter().enumerate() {
                            v.push(if j >= 3 { x / a.gauge } else { x });
                        }
                        v
                    })
                    .collect::<Vec<_>>(),
            ),
        ] {
            if ab.iter().flatten().any(|v| !v.is_finite()) {
                out += &format!(
                    "ablation side={} group={} unavailable=proposed_structure_unavailable\n",
                    label, name
                );
                continue;
            }
            let invalid: Vec<_> = a
                .training
                .iter()
                .filter(|a| !pins.contains(&a.outline_pin))
                .map(|a| a.outline_pin.clone())
                .collect();
            let groups = match name {
                "drop_wall" => vec![3, 2],
                "drop_whole" => vec![2, ab[0].len() - 2],
                "drop_vertical" => vec![3, ab[0].len() - 3],
                _ => vec![3, 2, data[0].len() - 5, 5],
            };
            let Some(m) = side_grouped(&ab, &pins, &a.rule, &invalid, &groups) else {
                out += &format!(
                    "ablation side={} group={} unavailable=normalization_numeric_failure\n",
                    label, name
                );
                continue;
            };
            out += &format!(
                "ablation side={} group={} selected_clusters={}\n",
                label,
                name,
                m.clusters.len()
            );
            let names = match name {
                "drop_wall" => vec!["whole", "vertical"],
                "drop_whole" => vec!["vertical", "wall"],
                "drop_vertical" => vec!["whole", "wall"],
                _ => vec!["whole", "vertical", "wall", "structure"],
            };
            let mut start = 0;
            for (group, &count) in names.iter().zip(&groups) {
                let end = start + count;
                out+=&format!("ablation_effective_group_weight side={} ablation={} group={} weight={} nonzero_range_channels={}\n",label,name,group,bits(effective_weight(&m,start,end)),(start..end).filter(|&i|m.range[i]!=0.).count());
                start = end;
            }
            for c in m.curve {
                out+=&format!("ablation_candidate_counts k={} singletons={} singleton_fraction={} retained={} retained_clusters={}\n",c.k,c.singleton_count,bits(c.singleton_fraction),c.retained_count,c.retained_clusters);
                out += &format!(
                    "ablation_candidate k={} silhouette={} eligible={} coverage={} excluded_index_runs={}\n",
                    c.k,
                    c.silhouette.map(bits).unwrap_or_default(),
                    c.eligible,
                    bits(c.coverage),
                    compact_exclusions(&c.excluded_pins,&a.aliases.iter().map(|(p,_)|p.clone()).collect::<Vec<_>>())?
                );
            }
        }
        let target = original.as_ref().map(|m| m.clusters.len()).unwrap_or(0);
        for b in 0..a.rule.bootstrap_replicates {
            let mut ids = Vec::new();
            for j in 0..data.len() {
                let h =
                    Sha256::digest(format!("bootstrap-v1:{}:{}:{}", a.rule_pin, b, j).as_bytes());
                let mut bytes = [0u8; 8];
                bytes.copy_from_slice(&h[..8]);
                ids.push((u64::from_be_bytes(bytes) % data.len() as u64) as usize);
            }
            ids.sort();
            let bs: Vec<_> = ids.iter().map(|&i| data[i].clone()).collect();
            let bp: Vec<_> = ids
                .iter()
                .enumerate()
                .map(|(j, &i)| format!("{}:{:020}", pins[i], j))
                .collect();
            let Some(m) = side(&bs, &bp, &a.rule, &[]) else {
                out += &format!(
                    "bootstrap side={} replicate={} unavailable=normalization_numeric_failure\n",
                    label, b
                );
                failed += 1;
                continue;
            };
            let ks = m.clusters.len();
            let sc = m.selected_silhouette;
            out += &format!(
                "bootstrap side={} replicate={} selected_clusters={} silhouette={} indices={:?}\n",
                label,
                b,
                ks,
                sc.map(bits).unwrap_or_default(),
                ids
            );
            if ks == target && ks >= 2 && sc.is_some_and(|s| s > 0.) {
                stable += 1
            }
            trials += 1;
        }
    }
    let fraction = if trials == 0 {
        0.
    } else {
        stable as f64 / trials as f64
    };
    out+=&format!("bootstrap_positive_silhouette_and_cluster_count_agreement={} unstable={} diagnostic_only=true\n",bits(fraction),fraction<a.rule.stability_fraction);
    out += &format!(
        "bootstrap_failed_replicates={} bootstrap_completed_replicates={} sides_without_bootstrap={}\n",
        failed, trials, sides_without_bootstrap
    );
    let mut same = 0;
    let mut pairs = 0;
    if let (Some(l), Some(r)) = (&a.left, &a.right) {
        for i in 0..pins.len() {
            for j in i + 1..pins.len() {
                if let (Some(li), Some(lj), Some(ri), Some(rj)) = (
                    member_assignment(l, &pins[i]),
                    member_assignment(l, &pins[j]),
                    member_assignment(r, &pins[i]),
                    member_assignment(r, &pins[j]),
                ) {
                    same += usize::from((li == lj) == (ri == rj));
                    pairs += 1;
                }
            }
        }
    }
    out += &format!(
        "left_right_coassignment_agreement={} pair_count={}\n",
        if pairs == 0 {
            String::from("unavailable")
        } else {
            bits(same as f64 / pairs as f64)
        },
        pairs
    );
    for s in shapes {
        out += &format!(
            "proposed_structure pin={} reason={}\n",
            s.pin,
            s.secondary_reason.as_deref().unwrap_or("")
        );
        match shape(&s.original, a.gauge * a.rule.flatten_fraction / 2.) {
            Ok(half) => {
                for j in 0..s.base.len() {
                    out += &format!(
                        "half_flatten_tolerance pin={} channel={} delta={} diagnostic_only=true\n",
                        s.pin,
                        j,
                        if half.base[j].is_finite() && s.base[j].is_finite() {
                            bits(half.base[j] - s.base[j])
                        } else {
                            "unavailable".into()
                        }
                    );
                }
            }
            Err(e) => out += &format!("half_flatten_tolerance pin={} unavailable={}\n", s.pin, e),
        }
    }
    Ok(out)
}
/// Geometric wall output matches GlyphWall field types. Integer levels are
/// the original source coordinate convention, not prototype descriptor levels.
#[derive(Clone, Debug)]
pub struct WallFields {
    pub advance: f64,
    pub rows: std::collections::BTreeMap<i32, (f64, f64)>,
}
pub fn fitter_wall(g: &Geometry) -> Result<WallFields, String> {
    fitter_wall_counted(g, &mut 0)
}
/// Same as `fitter_wall`; a trip of the wall row guard is also added to `wall_row_hits`.
/// The fit receipt does not carry this count because `fit` does not call `fitter_wall`.
pub fn fitter_wall_counted(g: &Geometry, wall_row_hits: &mut u64) -> Result<WallFields, String> {
    let rs = segments(g)?;
    let (xmin, _, ymin, ymax) = analytic_bounds(&rs)?;
    if ymin < i32::MIN as f64 || ymax > i32::MAX as f64 {
        return Err("wall_integer_range_unavailable".into());
    }
    let lo = ymin.ceil() as i32;
    let hi = ymax.floor() as i32;
    if hi as i64 - lo as i64 + 1 > 1000000 {
        *wall_row_hits += 1;
        return Err("wall_row_resource_limit".into());
    }
    let s = Shape {
        pin: String::new(),
        raw_pin: String::new(),
        base: vec![],
        secondary_reason: None,
        absolute_y: [0., 0.],
        original: g.clone(),
    };
    let mut rows = std::collections::BTreeMap::new();
    for y in lo..=hi {
        if let Some((a, b)) = wall(&s, y as f64 - ymin)? {
            rows.insert(y, (a + xmin, b + xmin));
        }
    }
    if rows.is_empty() {
        return Err("wall_unavailable".into());
    }
    Ok(WallFields {
        advance: g.advance,
        rows,
    })
}
#[cfg(test)]
mod analytical_tests {
    use super::*;
    #[test]
    fn artifact_serialization_propagates_missing_pin_error() {
        let r = Rule {
            minimum_training: 4,
            gauge_statistic: GaugeStatistic::Median,
            maximum_unique_training: 512,
            coverage_numerator: 1,
            coverage_denominator: 2,
            flatten_fraction: 1. / 1024.,
            bootstrap_replicates: 4,
            stability_fraction: 0.5,
        };
        let mut a = fit(&[], r.clone(), &r.pin()).unwrap();
        a.left = Some(SideModel {
            weights: vec![1.; 5],
            min: vec![0.; 5],
            range: vec![0.; 5],
            constant: vec![0.; 5],
            selected_silhouette: None,
            clusters: vec![],
            curve: vec![Candidate {
                k: 1,
                silhouette: None,
                eligible: false,
                excluded_pins: vec!["unknown".into()],
                coverage: 0.,
                singleton_count: 1,
                singleton_fraction: 1.,
                retained_count: 0,
                retained_clusters: 0,
            }],
        });
        assert_eq!(
            a.canonical_receipt(),
            Err(ReceiptError::UnregisteredPin {
                pin: "unknown".into()
            })
        );
    }

    #[test]
    fn missing_exclusion_pin_returns_typed_error() {
        let result = compact_exclusions(&["unknown".into()], &["a".into(), "b".into()]);
        assert_eq!(
            result,
            Err(ReceiptError::UnregisteredPin {
                pin: "unknown".into()
            })
        );
        assert_eq!(
            compact_exclusions(&[], &["b".into(), "a".into()]),
            Err(ReceiptError::InvalidPinDictionary)
        );
        assert_eq!(
            compact_exclusions(&["b".into(), "a".into()], &["a".into(), "b".into()]),
            Err(ReceiptError::InvalidExclusionOrder)
        );
    }

    #[test]
    fn compact_pin_exclusions_are_lossless() {
        let dictionary = (0..10).map(|i| format!("{i:02}")).collect::<Vec<_>>();
        let selected = [0, 1, 2, 5, 7, 8, 9].map(|i| dictionary[i].clone());
        let encoded = compact_exclusions(&selected, &dictionary).unwrap();
        assert_eq!(encoded, "0-2,5,7-9");
        let mut restored = Vec::new();
        for item in encoded.split(',') {
            let endpoints = item
                .split('-')
                .map(|x| x.parse::<usize>().unwrap())
                .collect::<Vec<_>>();
            let end = *endpoints.last().unwrap();
            for i in endpoints[0]..=end {
                restored.push(dictionary[i].clone());
            }
        }
        assert_eq!(restored, selected);
        assert_eq!(compact_exclusions(&[], &dictionary).unwrap(), "");
    }
    #[test]
    fn effective_group_weight_excludes_constant_ranges() {
        let rule = Rule {
            minimum_training: 4,
            gauge_statistic: GaugeStatistic::Median,
            maximum_unique_training: 8,
            coverage_numerator: 1,
            coverage_denominator: 2,
            flatten_fraction: 1. / 1024.,
            bootstrap_replicates: 4,
            stability_fraction: 0.5,
        };
        let data = [0., 0.1, 0.9, 1.].map(|v| vec![v, 0., 0., 0., 0., v, 0.]);
        let m = side(&data, &["a", "b", "c", "d"].map(str::to_string), &rule, &[]).unwrap();
        assert_eq!(effective_weight(&m, 0, 3), 1. / 9.);
        assert_eq!(effective_weight(&m, 3, 5), 0.);
        assert_eq!(effective_weight(&m, 5, 7), 1. / 6.);
    }

    #[test]
    fn aggregated_contribution_matches_pair_reference() {
        let v = [-0.3, 0., 0.01, 0.9, 1., 2.];
        let mut reference = 0.;
        for i in 0..v.len() {
            for j in i + 1..v.len() {
                let d = v[i] - v[j];
                reference += d * d;
            }
        }
        assert!((pair_squared_total(&v) - reference).abs() < 1e-12);
        assert_eq!(pair_squared_total(&[0., 0.]), 0.);
    }

    #[test]
    fn absolute_vertical_channel_is_not_translation_erased() {
        let make = |y: f64| Geometry {
            advance: 4.,
            rings: vec![Ring {
                start: Point { x: 0., y },
                spans: vec![
                    Span::Line(Point { x: 2., y }),
                    Span::Line(Point { x: 2., y: y + 10. }),
                    Span::Line(Point { x: 0., y: y + 10. }),
                    Span::Line(Point { x: 0., y }),
                ],
            }],
        };
        let a = descriptor(&shape(&make(0.), 0.01).unwrap(), 10., &[0., 0.5, 1.], false);
        let b = descriptor(
            &shape(&make(-2.), 0.01).unwrap(),
            10.,
            &[0., 0.5, 1.],
            false,
        );
        assert_eq!(&a[..3], &b[..3]);
        assert_eq!(&a[5..], &b[5..]);
        assert_ne!(&a[3..5], &b[3..5]);
        assert_eq!(&b[3..5], &[-0.2, 0.8]);
    }
    #[test]
    fn group_weight_not_wall_channel_count_controls_distance() {
        let rule = Rule {
            minimum_training: 4,
            gauge_statistic: GaugeStatistic::Median,
            maximum_unique_training: 512,
            coverage_numerator: 1,
            coverage_denominator: 2,
            flatten_fraction: 1. / 1024.,
            bootstrap_replicates: 4,
            stability_fraction: 0.5,
        };
        let make = |n: usize| {
            let rows: Vec<_> = [0., 0.1, 0.9, 1.]
                .iter()
                .map(|&v| {
                    let mut d = vec![v; 5];
                    d.extend(std::iter::repeat_n(v, n));
                    d
                })
                .collect();
            side_grouped(
                &rows,
                &["a", "b", "c", "d"].map(str::to_string),
                &rule,
                &[],
                &[3, 2, n],
            )
            .unwrap()
        };
        let a = make(2);
        let b = make(200);
        for m in [&a, &b] {
            assert!((m.weights[..3].iter().sum::<f64>() - 1. / 3.).abs() < 1e-12);
            assert!((m.weights[3..5].iter().sum::<f64>() - 1. / 3.).abs() < 1e-12);
            assert!((m.weights[5..].iter().sum::<f64>() - 1. / 3.).abs() < 1e-12);
        }
        let da = dist(
            &a.clusters[0].member_descriptors[0],
            &a.clusters[0].member_descriptors[1],
        );
        let db = dist(
            &b.clusters[0].member_descriptors[0],
            &b.clusters[0].member_descriptors[1],
        );
        assert!((da - db).abs() < 1e-12);
    }

    #[test]
    fn analytic_numeric_failure_is_not_missing_occupancy() {
        let g = Geometry {
            advance: 3.,
            rings: vec![Ring {
                start: Point { x: 0., y: 0. },
                spans: vec![
                    Span::Quadratic(Point { x: 1., y: 1e200 }, Point { x: 2., y: 0. }),
                    Span::Line(Point { x: 0., y: 0. }),
                ],
            }],
        };
        let ss = Shape {
            pin: String::new(),
            raw_pin: String::new(),
            base: vec![],
            secondary_reason: None,
            absolute_y: [0., 0.],
            original: g,
        };
        assert_eq!(wall(&ss, 1.).unwrap_err(), "wall_numeric_failure");
    }
    #[test]
    fn minimum_n_after_singleton_exclusion() {
        let r = Rule {
            minimum_training: 6,
            gauge_statistic: GaugeStatistic::Median,
            maximum_unique_training: 512,
            coverage_numerator: 1,
            coverage_denominator: 2,
            flatten_fraction: 1. / 1024.,
            bootstrap_replicates: 4,
            stability_fraction: 0.5,
        };
        let d = vec![
            vec![0.],
            vec![0.01],
            vec![0.1],
            vec![0.11],
            vec![0.9],
            vec![1.],
        ];
        let ps = (0..6).map(|i| i.to_string()).collect::<Vec<_>>();
        let m = side(&d, &ps, &r, &[]).unwrap();
        assert!(m
            .curve
            .iter()
            .filter(|c| c.retained_count < 6)
            .all(|c| !c.eligible));
        assert!(m
            .curve
            .iter()
            .any(|c| c.retained_clusters >= 2 && c.retained_count < 6));
    }

    #[test]
    fn quadratic_green_area_and_extrema() {
        let a = Point { x: 0., y: 0. };
        let c = Point { x: 1., y: 2. };
        let b = Point { x: 2., y: 0. };
        let seg = Segment::Q(a, c, b);
        assert_eq!(green(seg), -4. / 3.);
        let bb = analytic_bounds(&[vec![seg]]).unwrap();
        assert_eq!(bb, (0., 2., 0., 1.));
        let r = roots(-4., 4., -1.);
        assert_eq!(r, vec![0.5]);
    }
    #[test]
    fn radius_acceptance_uses_nearest_member_not_medoid() {
        let m = SideModel {
            min: vec![0.],
            range: vec![1.],
            constant: vec![0.],
            weights: vec![1.],
            curve: vec![],
            selected_silhouette: Some(1.),
            clusters: vec![
                Cluster {
                    class: 0,
                    medoid_pin: "a".into(),
                    prototype: vec![0.],
                    radius: 1.,
                    loo_distances: vec![1., 1.],
                    members: vec!["a".into(), "b".into()],
                    member_descriptors: vec![vec![0.], vec![2.]],
                },
                Cluster {
                    class: 1,
                    medoid_pin: "b".into(),
                    prototype: vec![10.],
                    radius: 1.,
                    loo_distances: vec![1., 1.],
                    members: vec!["c".into(), "d".into()],
                    member_descriptors: vec![vec![10.], vec![11.]],
                },
            ],
        };
        assert_eq!(query_side(&m, &[2.5]).unwrap(), (0, 0.5));
        assert!(query_side(&m, &[5.]).is_err());
    }
    #[test]
    fn analytic_wall_quadratic_roots() {
        let g = Geometry {
            advance: 3.,
            rings: vec![Ring {
                start: Point { x: 0., y: 0. },
                spans: vec![
                    Span::Quadratic(Point { x: 1., y: 2. }, Point { x: 2., y: 0. }),
                    Span::Line(Point { x: 0., y: 0. }),
                ],
            }],
        };
        let s = shape(&g, 1. / 1024.).unwrap();
        let (l, r) = wall(&s, 0.75).unwrap().unwrap();
        assert_eq!((l, r), (0.5, 1.5));
    }
}
#[cfg(test)] mod diagnostic_quantile_tests {
    use super::*;
    #[test] fn q90_nearest_rank_and_invalid() {
        assert_eq!(diagnostic_q90(&[]),None);
        assert_eq!(diagnostic_q90(&[f64::NAN]),None);
        assert_eq!(diagnostic_q90(&[-1.]),None);
        assert_eq!(diagnostic_q90(&[3.]),Some(3.));
        assert_eq!(diagnostic_q90(&(1..=10).rev().map(|x|x as f64).collect::<Vec<_>>()),Some(9.));
        assert_eq!(diagnostic_q90(&(1..=11).map(|x|x as f64).collect::<Vec<_>>()),Some(10.));
    }
}

#[cfg(test)]
mod guard_tests {
    use super::*;
    fn pt(x: f64, y: f64) -> Point {
        Point { x, y }
    }
    fn square(side: f64) -> Geometry {
        Geometry {
            rings: vec![Ring {
                start: pt(0., 0.),
                spans: vec![
                    Span::Line(pt(side, 0.)),
                    Span::Line(pt(side, side)),
                    Span::Line(pt(0., side)),
                    Span::Line(pt(0., 0.)),
                ],
            }],
            advance: side,
        }
    }
    fn arch() -> Geometry {
        Geometry {
            rings: vec![Ring {
                start: pt(0., 0.),
                spans: vec![Span::Quadratic(pt(50., 100.), pt(100., 0.)), Span::Line(pt(0., 0.))],
            }],
            advance: 100.,
        }
    }
    fn rule(min: usize, max: usize, flatten_fraction: f64) -> Rule {
        Rule {
            minimum_training: min,
            gauge_statistic: GaugeStatistic::Median,
            maximum_unique_training: max,
            coverage_numerator: 1,
            coverage_denominator: 2,
            flatten_fraction,
            bootstrap_replicates: 4,
            stability_fraction: 0.5,
        }
    }
    #[test]
    fn unique_cap_is_typed_and_keeps_the_old_string() {
        let r = rule(4, 4, 1. / 1024.);
        let training: Vec<Geometry> = (1..=5).map(|i| square(i as f64 * 10.)).collect();
        let e = fit(&training, r.clone(), &r.pin()).unwrap_err();
        assert_eq!(e, FitError::UniqueTrainingResourceLimit);
        assert_eq!(e.as_str(), "unique_training_resource_limit");
        assert_eq!(e.to_string(), "unique_training_resource_limit");
        assert_eq!(e, "unique_training_resource_limit");
        assert_eq!(String::from(e), "unique_training_resource_limit".to_string());
        let other = fit(&training, r, "not-the-pin").unwrap_err();
        assert_eq!(other, FitError::Other("rule_pin_mismatch".into()));
        assert_eq!(other.to_string(), "rule_pin_mismatch");
    }
    #[test]
    fn receipt_records_zero_guard_hits() {
        let r = rule(4, 512, 1. / 1024.);
        let a = fit(&[], r.clone(), &r.pin()).unwrap();
        assert_eq!(a.guard_counts(), GuardCounts::default());
        let text = a.canonical_receipt().unwrap();
        assert!(text.contains("guard_hits scope=fit_training flatten_depth=0 flatten_points=0\n"));
        assert!(text.starts_with("prototype-artifact-corpus-v7\n"));
        assert!(!text.contains("wall_rows"));
    }
    #[test]
    fn receipt_records_bootstrap_failed_replicates() {
        let r = rule(4, 512, 1. / 1024.);
        let training: Vec<Geometry> = (0..8)
            .map(|i| if i % 2 == 0 { square(10. + i as f64) } else { arch() })
            .collect();
        let a = fit(&training, r.clone(), &r.pin()).unwrap();
        let text = a.canonical_receipt().unwrap();
        let line = text
            .lines()
            .find(|l| l.starts_with("bootstrap_failed_replicates="))
            .expect("bootstrap count line");
        assert_eq!(
            line,
            "bootstrap_failed_replicates=0 bootstrap_completed_replicates=8 sides_without_bootstrap=0"
        );
        assert!(text.contains("bootstrap_positive_silhouette_and_cluster_count_agreement="));
    }
    #[test]
    fn flatten_depth_guard_is_counted_and_recorded() {
        let g = arch();
        let mut c = GuardCounts::default();
        assert!(shape_counted(&g, 1e-30, &mut c).is_ok());
        assert_eq!(c, GuardCounts { flatten_depth: 1, flatten_points: 0 });
        let mut ok = GuardCounts::default();
        assert!(shape_counted(&g, 1. / 1024., &mut ok).is_ok());
        assert_eq!(ok, GuardCounts::default());
        let r = rule(4, 512, 1e-30);
        let a = fit(&[g], r.clone(), &r.pin()).unwrap();
        assert_eq!(a.guard_counts().flatten_depth, 1);
        assert!(a
            .canonical_receipt()
            .unwrap()
            .contains("guard_hits scope=fit_training flatten_depth=1 flatten_points=0\n"));
    }
    #[test]
    fn flatten_points_guard_is_counted() {
        let n = 70000usize;
        let mut spans = Vec::new();
        for i in 1..n {
            let t = i as f64 / n as f64 * std::f64::consts::TAU;
            spans.push(Span::Line(pt(1000. * t.cos(), 1000. * t.sin())));
        }
        spans.push(Span::Line(pt(1000., 0.)));
        let g = Geometry { rings: vec![Ring { start: pt(1000., 0.), spans }], advance: 1000. };
        let mut c = GuardCounts::default();
        assert!(shape_counted(&g, 1. / 1024., &mut c).is_ok());
        assert_eq!(c, GuardCounts { flatten_depth: 0, flatten_points: 1 });
    }
    #[test]
    fn wall_row_guard_is_counted_and_error_string_unchanged() {
        let mut c = 0u64;
        assert_eq!(fitter_wall_counted(&square(2_000_000.), &mut c).unwrap_err(), "wall_row_resource_limit");
        assert_eq!(c, 1);
        assert_eq!(fitter_wall(&square(2_000_000.)).unwrap_err(), "wall_row_resource_limit");
        let mut z = 0u64;
        assert!(fitter_wall_counted(&square(10.), &mut z).is_ok());
        assert_eq!(z, 0);
    }
}
