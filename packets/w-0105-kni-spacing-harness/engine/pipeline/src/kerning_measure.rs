//! Pair-image -> observed origin distance -> kern residual (measurement target for the source-first kerning layer).
//!
//! Method (candidate, NOT owner- or chief-approved as an algorithm; the owner approved only the direction "learn from the source
//! pair images over KNI's own drawn vectors"): the two glyphs are KNI's generated outlines, rasterised at the pair image's scale. The
//! observed relation is the integer-pixel placement of the left/right templates that maximises ink-IoU against the pair image.
//! `origin_distance_px = right_origin_x - left_origin_x`. residual = observed distance (units) - `model_distance_units` (given by the
//! caller). Nothing is copied from a source font's kern table and nothing is written to GPOS. All limits are explicit inputs.
//! STOPGAP: the template rasteriser here is a private bounded one; it should be replaced by the shared bounded renderer API.
//! Scoring is exact rational (inter/union integers), no tolerance.
use kni_core::reference_slice::{DrawnGlyph, Point, Span};

#[derive(Debug, Clone, PartialEq)]
pub enum MeasureError {
    BadFrame(&'static str),
    BadMask(&'static str),
    BudgetExceeded { work: u128, max: u128 },
    EmptyRange(&'static str),
    NoOverlapEvidence,
    BelowMinIou { best: f64, min: f64 },
    /// Two or more placements share the maximal IoU with different origin distances: the image does not determine the relation.
    /// `distances` lists at most 16 tied distances; `total_tied` is the full count (truncated when total_tied > distances.len()).
    AmbiguousFit { best: f64, distances: Vec<i64>, total_tied: usize },
    NonFinite,
    Overflow(&'static str),
    NoEligiblePlacement,
    OverBudget(&'static str),
    BadFit,
}

/// Binary ink mask, row-major, `bits[y*w+x]`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Mask { w: usize, h: usize, bits: Vec<bool> }

impl Mask {
    pub fn new(w: usize, h: usize, bits: Vec<bool>) -> Result<Mask, MeasureError> {
        if w == 0 || h == 0 || bits.len() != w.checked_mul(h).ok_or(MeasureError::BadMask("size overflow"))? { return Err(MeasureError::BadMask("dimensions")); }
        Ok(Mask { w, h, bits })
    }
    /// Ink = gray < threshold (explicit).
    pub fn from_gray(w: usize, h: usize, px: &[u8], ink_below: u8) -> Result<Mask, MeasureError> {
        Mask::new(w, h, px.iter().map(|&p| p < ink_below).collect())
    }
    pub fn w(&self) -> usize { self.w }
    pub fn h(&self) -> usize { self.h }
    pub fn get(&self, x: usize, y: usize) -> bool { x < self.w && y < self.h && self.bits[y * self.w + x] }
    pub fn count(&self) -> u64 { self.bits.iter().filter(|b| **b).count() as u64 }
}

/// Frame: px = x/units_per_px, py = baseline_y_px - y/units_per_px (origin of the glyph at px 0).
#[derive(Debug, Clone, Copy)]
pub struct Frame { pub units_per_px: f64, pub baseline_y_px: f64, pub flatten_steps: usize }

/// Explicit resource limits for template rasterisation (checked BEFORE any allocation).
#[derive(Debug, Clone, Copy)]
pub struct RasterBudget { pub max_rings: usize, pub max_edges: usize, pub max_pixels: usize, pub max_pixel_edge_work: u128 }

/// Template with its local bounding box: `x0`,`y0` are the pixel coordinates (relative to the glyph origin at x=0 and the image's
/// row 0) of the mask's top-left, so overhang to the left of the origin or above the frame is kept, never clipped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Template { pub mask: Mask, pub x0: i64, pub y0: i64 }

fn flatten(g: &DrawnGlyph, steps: usize, max_rings: usize, max_edges: usize) -> Result<Vec<Vec<Point>>, MeasureError> {
    if steps == 0 { return Err(MeasureError::BadFrame("flatten_steps is 0")); }
    if g.rings.len() > max_rings { return Err(MeasureError::OverBudget("rings")); }
    // every ring costs its start point + closing edge; all counted BEFORE any point vector is allocated
    let mut edges: usize = 0;
    for ring in &g.rings {
        if ring.spans.is_empty() { return Err(MeasureError::BadMask("ring without spans")); }
        edges = edges.checked_add(1).ok_or(MeasureError::Overflow("edge count"))?; // closing edge
        for sp in &ring.spans {
            let n = match sp { Span::Line { .. } => 1, Span::Cubic { .. } => steps };
            edges = edges.checked_add(n).ok_or(MeasureError::Overflow("edge count"))?;
            if edges > max_edges { return Err(MeasureError::OverBudget("edges")); }
        }
        if edges > max_edges { return Err(MeasureError::OverBudget("edges")); }
    }
    let mut out = Vec::new();
    for ring in &g.rings {
        let mut pts = vec![ring.start];
        let mut cur = ring.start;
        for sp in &ring.spans {
            match sp {
                Span::Line { end } => { pts.push(*end); cur = *end; }
                Span::Cubic { control_one: a, control_two: b, end } => {
                    for i in 1..=steps {
                        let t = i as f64 / steps as f64; let u = 1.0 - t;
                        pts.push(Point { x: u*u*u*cur.x + 3.0*u*u*t*a.x + 3.0*u*t*t*b.x + t*t*t*end.x, y: u*u*u*cur.y + 3.0*u*u*t*a.y + 3.0*u*t*t*b.y + t*t*t*end.y });
                    }
                    cur = *end;
                }
            }
        }
        if pts.iter().any(|p| !p.x.is_finite() || !p.y.is_finite()) { return Err(MeasureError::NonFinite); }
        out.push(pts);
    }
    Ok(out)
}

fn winding(p: (f64, f64), poly: &[Point]) -> i32 {
    let mut w = 0;
    let n = poly.len();
    for i in 0..n {
        let (a, b) = (poly[i], poly[(i + 1) % n]);
        let side = (b.x - a.x) * (p.1 - a.y) - (p.0 - a.x) * (b.y - a.y);
        if a.y <= p.1 { if b.y > p.1 && side > 0.0 { w += 1; } } else if b.y <= p.1 && side < 0.0 { w -= 1; }
    }
    w
}

/// Rasterise the generated outline over ITS OWN pixel bbox (nonzero winding, pixel centres). Edge count, bbox pixels and
/// pixels x edges are bounded by `RasterBudget` before allocation; a glyph that does not fit is a typed refusal, never cropped.
pub fn rasterize_template(g: &DrawnGlyph, f: &Frame, b: &RasterBudget) -> Result<Template, MeasureError> {
    if !(f.units_per_px.is_finite() && f.units_per_px > 0.0 && f.baseline_y_px.is_finite()) { return Err(MeasureError::BadFrame("units_per_px/baseline")); }
    let rings = flatten(g, f.flatten_steps, b.max_rings, b.max_edges)?;
    let px: Vec<Vec<Point>> = rings.iter().map(|r| r.iter().map(|p| Point { x: p.x / f.units_per_px, y: f.baseline_y_px - p.y / f.units_per_px }).collect()).collect();
    let pts: Vec<&Point> = px.iter().flatten().collect();
    if pts.is_empty() { return Err(MeasureError::BadMask("empty outline")); }
    let (mut x0, mut x1, mut y0, mut y1) = (f64::MAX, f64::MIN, f64::MAX, f64::MIN);
    for p in &pts { x0 = x0.min(p.x); x1 = x1.max(p.x); y0 = y0.min(p.y); y1 = y1.max(p.y); }
    const LIM: f64 = 1.0e9;
    if !(x0.abs() < LIM && x1.abs() < LIM && y0.abs() < LIM && y1.abs() < LIM) { return Err(MeasureError::Overflow("bbox")); }
    let (ix0, iy0) = (x0.floor() as i64, y0.floor() as i64);
    let (w, h) = ((x1.ceil() as i64 - ix0).max(1) as usize, (y1.ceil() as i64 - iy0).max(1) as usize);
    let pixels = w.checked_mul(h).ok_or(MeasureError::Overflow("pixels"))?;
    if pixels > b.max_pixels { return Err(MeasureError::OverBudget("pixels")); }
    let edges: usize = px.iter().map(|r| r.len()).sum();
    if (pixels as u128).saturating_mul(edges as u128) > b.max_pixel_edge_work { return Err(MeasureError::OverBudget("pixel*edge work")); }
    let mut bits = vec![false; pixels];
    for y in 0..h { for x in 0..w {
        let c = ((ix0 + x as i64) as f64 + 0.5, (iy0 + y as i64) as f64 + 0.5);
        bits[y * w + x] = px.iter().map(|r| winding(c, r)).sum::<i32>() != 0;
    } }
    Ok(Template { mask: Mask::new(w, h, bits)?, x0: ix0, y0: iy0 })
}

#[derive(Debug, Clone, Copy)]
pub struct Search {
    /// Inclusive integer pixel range for the LEFT glyph origin x in image pixels.
    pub left_x: (i64, i64),
    /// Inclusive integer pixel range for origin_distance_px = right_origin - left_origin.
    pub distance: (i64, i64),
    /// Vertical placement offset applied to both templates (explicit; same baseline frame => caller states it).
    pub y_shift: i64,
    /// Minimum accepted IoU as an exact fraction (num, den).
    pub min_iou: (u64, u64),
    /// Max number of distinct origin distances scanned (bounds the per-distance score table).
    pub max_distances: usize,
    /// Upper bound on #placements x (|left ink|+|right ink|); exceeded => typed refusal before any search.
    pub max_work: u128,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fit {
    left_x: i64, origin_distance_px: i64, inter: u64, union: u64,
    /// Best score at any OTHER distance (distance, inter, union): the margin of the argmax. None if only one distance was eligible.
    /// A single argmax is an observation candidate, never training truth by itself.
    runner_up: Option<(i64, u64, u64)>,
}
impl Fit {
    /// The only constructor: union > 0 and inter <= union (also for the runner-up), so iou() is always finite in [0,1].
    pub fn new(left_x: i64, origin_distance_px: i64, inter: u64, union: u64, runner_up: Option<(i64, u64, u64)>) -> Result<Fit, MeasureError> {
        if union == 0 || inter > union { return Err(MeasureError::BadFit); }
        if let Some((_, i, u)) = runner_up { if u == 0 || i > u { return Err(MeasureError::BadFit); } }
        Ok(Fit { left_x, origin_distance_px, inter, union, runner_up })
    }
    pub fn left_x(&self) -> i64 { self.left_x }
    pub fn origin_distance_px(&self) -> i64 { self.origin_distance_px }
    pub fn score(&self) -> (u64, u64) { (self.inter, self.union) }
    pub fn runner_up(&self) -> Option<(i64, u64, u64)> { self.runner_up }
    pub fn iou(&self) -> f64 { self.inter as f64 / self.union as f64 }
}

fn ink_list(m: &Mask) -> Vec<(i64, i64)> {
    let mut v = Vec::new();
    for y in 0..m.h { for x in 0..m.w { if m.bits[y * m.w + x] { v.push((x as i64, y as i64)); } } }
    v
}

/// Dense reference (oracle for tests): whole-image pixel loop, exact counts.
#[cfg(test)]
fn counts_dense(img: &Mask, l: &Template, r: &Template, xl: i64, d: i64, ys: i64) -> (u64, u64) {
    let t = |tp: &Template, ox: i64, x: i64, y: i64| -> bool { let (tx, ty) = (x - ox - tp.x0, y - ys - tp.y0); tx >= 0 && ty >= 0 && tp.mask.get(tx as usize, ty as usize) };
    let (mut inter, mut uni) = (0u64, 0u64);
    for y in 0..img.h as i64 { for x in 0..img.w as i64 {
        let tt = t(l, xl, x, y) || t(r, xl + d, x, y); let i = img.get(x as usize, y as usize);
        if tt && i { inter += 1; } if tt || i { uni += 1; }
    } }
    (inter, uni)
}

/// Exhaustive deterministic EXACT fit with sparse evaluation. A placement is ELIGIBLE only if both templates fully lie inside the
/// image frame (no cropping at the source boundary); ineligible placements are not scored. Scores are exact integers (inter, union);
/// comparison is by cross-multiplication. All placements sharing the maximal score must agree on origin_distance, else AmbiguousFit.
pub fn fit_origin_distance(img: &Mask, left: &Template, right: &Template, s: &Search) -> Result<Fit, MeasureError> {
    if s.min_iou.1 == 0 || s.min_iou.0 > s.min_iou.1 { return Err(MeasureError::BadFrame("min_iou fraction")); }
    if s.left_x.0 > s.left_x.1 { return Err(MeasureError::EmptyRange("left_x")); }
    if s.distance.0 > s.distance.1 { return Err(MeasureError::EmptyRange("distance")); }
    let img_ink = img.count();
    let (lc, rc) = (left.mask.count(), right.mask.count());
    if img_ink == 0 || lc == 0 || rc == 0 { return Err(MeasureError::NoOverlapEvidence); }
    let ink_len = (lc + rc) as usize;
    let nl = (s.left_x.1 as i128 - s.left_x.0 as i128 + 1) as u128; let nd = (s.distance.1 as i128 - s.distance.0 as i128 + 1) as u128;
    if nd > s.max_distances as u128 { return Err(MeasureError::OverBudget("distinct distances")); }
    let work = nl.saturating_mul(nd).saturating_mul(ink_len as u128);
    if work > s.max_work { return Err(MeasureError::BudgetExceeded { work, max: s.max_work }); }
    // allocation only after every budget check: ink lists are bounded by the (already bounded) mask sizes
    let (ll, rl) = (ink_list(&left.mask), ink_list(&right.mask));
    let mut per_d: std::collections::BTreeMap<i64, (u64, u64, i64)> = Default::default(); // distance -> (inter, union, left_x), bounded by max_distances
    let (iw, ih) = (img.w as i128, img.h as i128);
    let fits = |t: &Template, ox: i128| -> bool {
        let (bx, by) = (ox + t.x0 as i128, s.y_shift as i128 + t.y0 as i128);
        bx >= 0 && by >= 0 && bx + t.mask.w as i128 <= iw && by + t.mask.h as i128 <= ih
    };
    let mut eligible = 0u64;
    let better = |a: (u64, u64), b: (u64, u64)| (a.0 as u128) * (b.1 as u128) > (b.0 as u128) * (a.1 as u128);
    for xl in s.left_x.0..=s.left_x.1 { for d in s.distance.0..=s.distance.1 {
        let xr = (xl as i128).checked_add(d as i128).ok_or(MeasureError::Overflow("right origin"))?;
        if !fits(left, xl as i128) || !fits(right, xr) { continue; }
        eligible += 1;
        let (lx, rx) = (xl + left.x0, (xr as i64) + right.x0);
        let (ly, ry) = (s.y_shift + left.y0, s.y_shift + right.y0);
        let (mut tcount, mut inter) = (0u64, 0u64);
        for &(px, py) in &ll { tcount += 1; if img.get((px + lx) as usize, (py + ly) as usize) { inter += 1; } }
        for &(px, py) in &rl {
            let (x, y) = (px + rx, py + ry);
            let (lpx, lpy) = (x - lx, y - ly);
            if lpx >= 0 && lpy >= 0 && left.mask.get(lpx as usize, lpy as usize) { continue; }
            tcount += 1; if img.get(x as usize, y as usize) { inter += 1; }
        }
        let sc = (inter, tcount + img_ink - inter);
        // per distance keep the best score; equal scores at the same distance keep the lowest left_x (distance is what is reported)
        match per_d.get(&d) { Some(&(i0, u0, _)) if !better(sc, (i0, u0)) => {} _ => { per_d.insert(d, (sc.0, sc.1, xl)); } }
    } }
    if eligible == 0 { return Err(MeasureError::NoEligiblePlacement); }
    let mut it = per_d.iter();
    let (mut bd, mut bs) = { let (d, v) = it.next().unwrap(); (*d, *v) };
    for (d, v) in it { if better((v.0, v.1), (bs.0, bs.1)) { bd = *d; bs = *v; } }
    let (bi, bu) = (bs.0, bs.1);
    if (bi as u128) * (s.min_iou.1 as u128) < (s.min_iou.0 as u128) * (bu as u128) { return Err(MeasureError::BelowMinIou { best: bi as f64 / bu as f64, min: s.min_iou.0 as f64 / s.min_iou.1 as f64 }); }
    let tied_all = || per_d.iter().filter(|(_, v)| (v.0 as u128) * (bu as u128) == (bi as u128) * (v.1 as u128)).map(|(d, _)| *d);
    let total_tied = tied_all().count();
    if total_tied != 1 { return Err(MeasureError::AmbiguousFit { best: bi as f64 / bu as f64, distances: tied_all().take(16).collect(), total_tied }); }
    let mut runner: Option<(i64, u64, u64)> = None;
    for (d, v) in &per_d { if *d == bd { continue; } if runner.map_or(true, |r| better((v.0, v.1), (r.1, r.2))) { runner = Some((*d, v.0, v.1)); } }
    Fit::new(bs.2, bd, bi, bu, runner)
}

/// One research observation CANDIDATE (not training truth, not a GPOS value): observed distance and residual against the model's
/// current distance. Training use requires the argmax margin (`Fit::runner_up`) and a held-out reference comparison. No GPOS write.
#[derive(Debug, Clone, PartialEq)]
pub struct PairObservation { pub left: u32, pub right: u32, pub observed_distance_units: f64, pub model_distance_units: f64, pub residual_units: f64, pub iou: f64, pub image_sha256: String }

pub fn observation(left: u32, right: u32, fit: &Fit, units_per_px: f64, model_distance_units: f64, image_sha256: &str) -> Result<PairObservation, MeasureError> {
    if !(units_per_px.is_finite() && units_per_px > 0.0 && model_distance_units.is_finite()) { return Err(MeasureError::NonFinite); }
    let obs = fit.origin_distance_px() as f64 * units_per_px;
    let (observed, resid) = (fit.origin_distance_px() as f64 * units_per_px, fit.origin_distance_px() as f64 * units_per_px - model_distance_units);
    if !observed.is_finite() || !resid.is_finite() { return Err(MeasureError::NonFinite); }
    Ok(PairObservation { left, right, observed_distance_units: obs, model_distance_units, residual_units: obs - model_distance_units, iou: fit.iou(), image_sha256: image_sha256.to_string() })
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_core::reference_slice::ReferenceRing;
    fn rect(x0: f64, x1: f64, y0: f64, y1: f64) -> DrawnGlyph {
        let p = |x, y| Point { x, y };
        DrawnGlyph { glyph_id: "r".into(), rings: vec![ReferenceRing { start: p(x0, y0), spans: vec![Span::Line { end: p(x1, y0) }, Span::Line { end: p(x1, y1) }, Span::Line { end: p(x0, y1) }, Span::Line { end: p(x0, y0) }] }] }
    }
    fn frame() -> Frame { Frame { units_per_px: 10.0, baseline_y_px: 8.0, flatten_steps: 8 } }
    fn budget() -> RasterBudget { RasterBudget { max_rings: 8, max_edges: 1000, max_pixels: 10_000, max_pixel_edge_work: 10_000_000 } }
    fn tpl(g: &DrawnGlyph) -> Template { rasterize_template(g, &frame(), &budget()).unwrap() }
    fn compose(l: &Template, r: &Template, xl: i64, d: i64, w: usize, h: usize) -> Mask {
        let mut b = vec![false; w * h];
        for (t, ox) in [(l, xl), (r, xl + d)] {
            for y in 0..t.mask.h { for x in 0..t.mask.w { if t.mask.get(x, y) {
                let (px, py) = (x as i64 + t.x0 + ox, y as i64 + t.y0);
                if px >= 0 && py >= 0 && (px as usize) < w && (py as usize) < h { b[py as usize * w + px as usize] = true; }
            } } }
        }
        Mask::new(w, h, b).unwrap()
    }
    fn search() -> Search { Search { left_x: (0, 12), distance: (0, 20), y_shift: 0, min_iou: (99, 100), max_distances: 64, max_work: 10_000_000 } }
    #[test]
    fn recovers_known_origin_distance_and_residual_in_units() {
        let l = tpl(&rect(0.0, 40.0, 0.0, 70.0)); let r = tpl(&rect(0.0, 60.0, 0.0, 50.0));
        assert_eq!((l.mask.count(), r.mask.count()), (28, 30));
        let img = compose(&l, &r, 3, 11, 40, 10);
        let fit = fit_origin_distance(&img, &l, &r, &search()).unwrap();
        assert_eq!((fit.left_x(), fit.origin_distance_px(), fit.score()), (3, 11, (58, 58)));
        let ru = fit.runner_up().unwrap(); assert!((ru.1 as u128) * 58 < 58 * (ru.2 as u128)); // runner-up margin is strictly worse
        let o = observation(0x48, 0x48, &fit, 10.0, 100.0, "sha").unwrap();
        assert_eq!((o.observed_distance_units, o.residual_units), (110.0, 10.0));
    }
    #[test]
    fn overhang_left_of_origin_and_above_frame_is_kept_not_clipped() {
        // left overhang of 20 units (2 px) before the origin; shape also rises above row 0 if the frame were clipped
        let l = tpl(&rect(-20.0, 40.0, 0.0, 70.0)); let r = tpl(&rect(0.0, 60.0, 0.0, 50.0));
        assert_eq!(l.x0, -2); assert_eq!(l.mask.count(), 6 * 7);
        let img = compose(&l, &r, 5, 11, 40, 10);
        let fit = fit_origin_distance(&img, &l, &r, &search()).unwrap();
        assert_eq!((fit.left_x(), fit.origin_distance_px()), (5, 11));
        // a placement whose template crosses the image edge is ineligible, not scored with a cropped template
        let mut s = search(); s.left_x = (0, 1); s.distance = (0, 20);
        assert_eq!(fit_origin_distance(&img, &l, &r, &s), Err(MeasureError::NoEligiblePlacement));
    }
    #[test]
    fn raster_budgets_and_arithmetic_are_checked_before_allocation() {
        let g = rect(0.0, 40.0, 0.0, 70.0);
        // empty ring / ring count / closure edge are budgeted before any allocation
        let empty = DrawnGlyph { glyph_id: "e".into(), rings: vec![ReferenceRing { start: Point { x: 0.0, y: 0.0 }, spans: vec![] }] };
        assert_eq!(rasterize_template(&empty, &frame(), &budget()), Err(MeasureError::BadMask("ring without spans")));
        let many = DrawnGlyph { glyph_id: "m".into(), rings: (0..9).map(|_| rect(0.0, 1.0, 0.0, 1.0).rings.remove(0)).collect() };
        assert_eq!(rasterize_template(&many, &frame(), &budget()), Err(MeasureError::OverBudget("rings")));
        let mut b = budget(); b.max_edges = 4; // rect = 4 spans + closing edge = 5 > 4
        assert_eq!(rasterize_template(&g, &frame(), &b), Err(MeasureError::OverBudget("edges")));
        let mut b = budget(); b.max_edges = 3;
        assert_eq!(rasterize_template(&g, &frame(), &b), Err(MeasureError::OverBudget("edges")));
        let mut b = budget(); b.max_pixels = 10;
        assert_eq!(rasterize_template(&g, &frame(), &b), Err(MeasureError::OverBudget("pixels")));
        let mut b = budget(); b.max_pixel_edge_work = 10;
        assert_eq!(rasterize_template(&g, &frame(), &b), Err(MeasureError::OverBudget("pixel*edge work")));
        assert_eq!(rasterize_template(&rect(0.0, 1.0e300, 0.0, 1.0), &frame(), &budget()), Err(MeasureError::Overflow("bbox")));
        let l = tpl(&g); let img = compose(&l, &l, 0, 8, 40, 10);
        let mut s = search(); s.max_distances = 2;
        assert_eq!(fit_origin_distance(&img, &l, &l, &s), Err(MeasureError::OverBudget("distinct distances")));
        assert_eq!(observation(1, 2, &Fit::new(0, i64::MAX, 1, 1, None).unwrap(), f64::MAX, 0.0, "s"), Err(MeasureError::NonFinite));
        let mut s = search(); s.left_x = (i64::MIN, i64::MAX); s.distance = (0, 63);
        assert!(matches!(fit_origin_distance(&img, &l, &l, &s), Err(MeasureError::BudgetExceeded { .. })));
        let mut s = search(); s.left_x = (i64::MAX - 1, i64::MAX); s.distance = (1, 2); s.max_work = u128::MAX;
        assert_eq!(fit_origin_distance(&img, &l, &l, &s), Err(MeasureError::NoEligiblePlacement)); // no overflow panic
    }
    #[test]
    fn refusals_are_typed_and_deterministic() {
        let l = tpl(&rect(0.0, 40.0, 0.0, 70.0)); let r = tpl(&rect(0.0, 60.0, 0.0, 50.0));
        let img = compose(&l, &r, 3, 11, 40, 10);
        let mut s = search(); s.max_work = 10;
        assert!(matches!(fit_origin_distance(&img, &l, &r, &s), Err(MeasureError::BudgetExceeded { .. })));
        let mut s = search(); s.distance = (5, 4);
        assert_eq!(fit_origin_distance(&img, &l, &r, &s), Err(MeasureError::EmptyRange("distance")));
        let mut s = search(); s.distance = (0, 5);
        assert!(matches!(fit_origin_distance(&img, &l, &r, &s), Err(MeasureError::BelowMinIou { .. })));
        let mut s = search(); s.min_iou = (1, 0);
        assert!(matches!(fit_origin_distance(&img, &l, &r, &s), Err(MeasureError::BadFrame(_))));
        // identical templates: (xl=3,d=+8) and (xl=11,d=-8) give the same union => the image does not fix the sign
        let same = compose(&l, &l, 3, 8, 40, 10);
        let mut s = search(); s.left_x = (0, 12); s.distance = (-8, 8);
        assert!(matches!(fit_origin_distance(&same, &l, &l, &s), Err(MeasureError::AmbiguousFit { .. })));
        let e = Mask::new(40, 10, vec![false; 400]).unwrap();
        assert_eq!(fit_origin_distance(&e, &l, &r, &search()), Err(MeasureError::NoOverlapEvidence));
        assert!(Mask::new(3, 3, vec![false; 8]).is_err());
        assert_eq!(Fit::new(0, 0, 0, 0, None), Err(MeasureError::BadFit)); assert_eq!(Fit::new(0, 0, 2, 1, None), Err(MeasureError::BadFit)); assert_eq!(Fit::new(0, 0, 1, 1, Some((1, 2, 1))), Err(MeasureError::BadFit));
        let mut f = frame(); f.units_per_px = 0.0;
        assert!(rasterize_template(&rect(0.0, 1.0, 0.0, 1.0), &f, &budget()).is_err());
        let mut f = frame(); f.flatten_steps = 0;
        assert!(rasterize_template(&rect(0.0, 1.0, 0.0, 1.0), &f, &budget()).is_err());
    }
    #[test]
    fn sparse_fit_counts_equal_dense_counts_for_every_eligible_placement() {
        let l = tpl(&rect(-10.0, 40.0, 0.0, 70.0)); let r = tpl(&rect(0.0, 60.0, 0.0, 50.0));
        let img = compose(&l, &r, 4, 11, 40, 10);
        let ink = |t: &Template| ink_list(&t.mask);
        for xl in 0..30i64 { for d in -5..20i64 { for ys in [0i64] {
            let (iw, ih) = (img.w as i64, img.h as i64);
            let fit = |t: &Template, ox: i64| { let (bx, by) = (ox + t.x0, ys + t.y0); bx >= 0 && by >= 0 && bx + t.mask.w as i64 <= iw && by + t.mask.h as i64 <= ih };
            if !fit(&l, xl) || !fit(&r, xl + d) { continue; }
            let (mut t, mut i) = (0u64, 0u64);
            for &(px, py) in &ink(&l) { t += 1; if img.get((px + xl + l.x0) as usize, (py + ys + l.y0) as usize) { i += 1; } }
            for &(px, py) in &ink(&r) { let (x, y) = (px + xl + d + r.x0, py + ys + r.y0); let (a, b) = (x - xl - l.x0, y - ys - l.y0); if a >= 0 && b >= 0 && l.mask.get(a as usize, b as usize) { continue; } t += 1; if img.get(x as usize, y as usize) { i += 1; } }
            assert_eq!((i, t + img.count() - i), counts_dense(&img, &l, &r, xl, d, ys), "xl {xl} d {d}");
        } } }
    }
    #[test]
    fn cubic_flatten_matches_a_line_for_a_degenerate_cubic() {
        let p = |x, y| Point { x, y };
        let g = DrawnGlyph { glyph_id: "c".into(), rings: vec![ReferenceRing { start: p(0.0, 0.0), spans: vec![
            Span::Cubic { control_one: p(20.0, 0.0), control_two: p(40.0, 0.0), end: p(60.0, 0.0) },
            Span::Line { end: p(60.0, 50.0) }, Span::Line { end: p(0.0, 50.0) }, Span::Line { end: p(0.0, 0.0) }] }] };
        assert_eq!(tpl(&g), tpl(&rect(0.0, 60.0, 0.0, 50.0)));
    }
}
