//! Minimal silhouette rasterizer for the paired-IoU gate (rule R7).
//! Nonzero-winding union of closed polygons, sampled at pixel centres.

use crate::check::stroke_polygon;
use crate::model::{MasterGlyph, Pt};

/// Flattened polygons of a master glyph (one per stroke contour).
pub fn polygons(g: &MasterGlyph) -> Vec<Vec<Pt>> {
    g.contours.iter().map(stroke_polygon).collect()
}

fn winding(p: Pt, poly: &[Pt]) -> i32 {
    let mut w = 0;
    let n = poly.len();
    for i in 0..n {
        let (a, b) = (poly[i], poly[(i + 1) % n]);
        let cross = (b.0 - a.0) * (p.1 - a.1) - (p.0 - a.0) * (b.1 - a.1);
        if a.1 <= p.1 {
            if b.1 > p.1 && cross > 0.0 {
                w += 1;
            }
        } else if b.1 <= p.1 && cross < 0.0 {
            w -= 1;
        }
    }
    w
}

/// Is `p` inside the nonzero union of all polygons? Each polygon is its own
/// fill (strokes overlap freely and union); polygons of an export outline
/// carry their own winding so counters subtract when the outline is one
/// merged path set: use `inside_merged` for that case.
pub fn inside_union(p: Pt, polys: &[Vec<Pt>]) -> bool {
    polys.iter().any(|poly| winding(p, poly) != 0)
}

/// Nonzero fill over the SUM of windings (export outline with holes).
pub fn inside_merged(p: Pt, polys: &[Vec<Pt>]) -> bool {
    polys.iter().map(|poly| winding(p, poly)).sum::<i32>() != 0
}

pub type Mask = Vec<bool>;

/// Rasterize with pixel size `px` over `bounds` (x0,y0,x1,y1), sample
/// offset `(ox, oy)` in pixel fractions.
pub fn rasterize(
    polys: &[Vec<Pt>],
    merged: bool,
    bounds: (f64, f64, f64, f64),
    px: f64,
    off: (f64, f64),
) -> (usize, usize, Mask) {
    let w = ((bounds.2 - bounds.0) / px).ceil() as usize;
    let h = ((bounds.3 - bounds.1) / px).ceil() as usize;
    let mut m = vec![false; w * h];
    for j in 0..h {
        for i in 0..w {
            let p = (bounds.0 + (i as f64 + off.0) * px, bounds.1 + (j as f64 + off.1) * px);
            m[j * w + i] = if merged { inside_merged(p, polys) } else { inside_union(p, polys) };
        }
    }
    (w, h, m)
}

pub fn bounds_of(sets: &[&[Vec<Pt>]], pad: f64) -> (f64, f64, f64, f64) {
    let (mut x0, mut y0, mut x1, mut y1) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
    for s in sets {
        for poly in s.iter() {
            for p in poly {
                x0 = x0.min(p.0);
                y0 = y0.min(p.1);
                x1 = x1.max(p.0);
                y1 = y1.max(p.1);
            }
        }
    }
    (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
}

/// (iou, union_px, miss_px, excess_px) of mask `a` (master) against `b`
/// (expected). Miss = in b only; excess = in a only.
pub fn paired_iou(a: &Mask, b: &Mask) -> (f64, usize, usize, usize) {
    let (mut inter, mut uni, mut miss, mut exc) = (0, 0, 0, 0);
    for (&x, &y) in a.iter().zip(b.iter()) {
        if x && y {
            inter += 1;
        }
        if x || y {
            uni += 1;
        }
        if y && !x {
            miss += 1;
        }
        if x && !y {
            exc += 1;
        }
    }
    let iou = if uni == 0 { 1.0 } else { inter as f64 / uni as f64 };
    (iou, uni, miss, exc)
}
