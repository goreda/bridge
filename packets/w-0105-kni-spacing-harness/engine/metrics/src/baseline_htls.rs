//! STEP 0: baseline_htls - HT Letterspacer-equivalent spacing.
//!
//! Clean-room reimplementation of the published HT Letterspacer METHOD
//! (huertatipografica/HTLetterspacer, htls/engine.py; upstream code GPL-3.0,
//! consulted for formula semantics only, no code copied). The method: area
//! quadrature of the white polygon per glyph side, depth clamp into open
//! counters, 45-degree closure, deslant at the italic angle.
//!
//! Role in the engine: exercises the whole pipeline skeleton
//! with a published formula. It is a HEURISTIC PROXY with designer-set
//! parameters (area measure, not inter-form geometry); later steps replace
//! the target while the pipeline shape (scan -> measure -> solve -> gate ->
//! receipt) stays.

use crate::evidence::{SpacingReceipt, Tier};
use crate::params::MasterParams;
use crate::plane::InkScan;

/// CONVENTION: reference UPM of the published area unit. The HT Letterspacer
/// tutorial states the area parameter in thousands of units "for a text
/// typeface at 1000 UPM" (https://letterspacer.htfonts.com/tutorial/en.html),
/// so areas are rescaled by (upm / REFERENCE_UPM)^2.
const REFERENCE_UPM: f64 = 1000.0;

/// Placeholder for a scanline with no ink: far enough out that the depth
/// clamp always pulls it back to maximum depth (published method).
const DEFAULT_MARGIN: f64 = 1e6;

/// Result for one glyph side, before integer rounding.
#[derive(Debug, Clone, Copy)]
pub struct SideSpacing {
    /// Sidebearing value in plane units.
    pub value: f64,
    /// Area of the measured white polygon (square plane units).
    pub polygon_area: f64,
    /// Depth clamp applied (plane units).
    pub depth: f64,
    /// Distance between the zone extreme and the full-shape extreme.
    pub distance: f64,
}

/// Spacing result for one glyph: integer sidebearings plus audit data.
#[derive(Debug, Clone)]
pub struct BaselineSpacing {
    pub lsb: i64,
    pub rsb: i64,
    pub left: SideSpacing,
    pub right: SideSpacing,
    pub receipt: SpacingReceipt,
}

#[derive(Debug, Clone, Copy)]
struct Pt {
    x: f64,
    y: f64,
}

/// Shoelace area of a closed point list (published method).
fn polygon_area(pts: &[Pt]) -> f64 {
    let mut s = 0.0;
    for i in 0..pts.len() {
        let a = pts[if i == 0 { pts.len() - 1 } else { i - 1 }];
        let b = pts[i];
        s += a.x * b.y - b.x * a.y;
    }
    s.abs() * 0.5
}

/// Space one glyph with the baseline method.
///
/// `reference` defaults to the glyph itself when None (published default).
/// Returns None when the glyph has no ink inside the reference zone
/// (published abort case) or no ink at all.
pub fn space_glyph<S: InkScan>(
    glyph: &S,
    reference: Option<&S>,
    master: &MasterParams,
) -> Option<BaselineSpacing> {
    let (gy0, gy1) = glyph.y_bounds()?;
    let reference = reference.unwrap_or(glyph);
    let (ry0, ry1) = reference.y_bounds()?;
    let over = master.overshoot();
    let min_y_ref = ry0 as f64 - over;
    let max_y_ref = ry1 as f64 + over;
    let freq = master.freq.max(1);

    // Margin scan over the glyph's own ink bounds (published totalMarginList).
    let mut lmargins: Vec<Pt> = Vec::new();
    let mut rmargins: Vec<Pt> = Vec::new();
    let mut any_in_zone = false;
    let mut y = gy0;
    while y <= gy1 {
        match glyph.row_span(y) {
            Some((l, r)) => {
                lmargins.push(Pt { x: l as f64, y: y as f64 });
                rmargins.push(Pt { x: r as f64, y: y as f64 });
                if y as f64 >= min_y_ref && y as f64 <= max_y_ref {
                    any_in_zone = true;
                }
            }
            None => {
                lmargins.push(Pt { x: DEFAULT_MARGIN, y: y as f64 });
                rmargins.push(Pt { x: -DEFAULT_MARGIN, y: y as f64 });
            }
        }
        y += freq;
    }
    if !any_in_zone {
        return None;
    }

    // Zone filter (published zoneMargins).
    let mut lz: Vec<Pt> = lmargins
        .iter()
        .copied()
        .filter(|p| p.y >= min_y_ref && p.y <= max_y_ref)
        .collect();
    let mut rz: Vec<Pt> = rmargins
        .iter()
        .copied()
        .filter(|p| p.y >= min_y_ref && p.y <= max_y_ref)
        .collect();
    let mut lt = lmargins.clone();
    let mut rt = rmargins.clone();

    // Deslant at the italic angle, pivot at half x-height above the
    // baseline. RASTER-PLANE SIGN (y down): a positive italic angle leans
    // the ink right toward the top, x_italic = x_upright - (y - mline)*t,
    // so deslant ADDS (y - mline)*t. A contour backend presenting font
    // coordinates (y up) must flip the sign at the plane boundary; the
    // InkScan contract is y-down.
    if master.italic_angle_deg != 0.0 {
        let t = (master.italic_angle_deg * std::f64::consts::PI / 180.0).tan();
        let mline = master.baseline_y - master.x_height / 2.0;
        let f = |p: &mut Pt| p.x += (p.y - mline) * t;
        lz.iter_mut().for_each(&f);
        rz.iter_mut().for_each(&f);
        lt.iter_mut().for_each(&f);
        rt.iter_mut().for_each(&f);
    }

    // Extremes (published maxPoints): full shape and zone.
    let l_full = lt.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
    let r_full = rt.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);
    let l_ext = lz.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
    let r_ext = rz.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);

    let lpoly = process_side(&lz, l_ext, true, min_y_ref, max_y_ref, master);
    let rpoly = process_side(&rz, r_ext, false, min_y_ref, max_y_ref, master);
    let depth = master.x_height * master.param_depth_pct / 100.0;

    // Published calculateSBValue.
    let amplitude = max_y_ref - min_y_ref;
    let white_area = master.effective_area() * (master.upm / REFERENCE_UPM).powi(2) * 100.0;
    let prop_area = amplitude * white_area / master.x_height;
    let l_area = polygon_area(&lpoly);
    let r_area = polygon_area(&rpoly);
    let l_val = (prop_area - l_area) / amplitude;
    let r_val = (prop_area - r_area) / amplitude;

    // Published: distance = ceil(zone extreme - full extreme), then
    // newL = ceil(0 - distance + sbValue); same on the right.
    let l_dist = (l_ext - l_full).ceil();
    let r_dist = (r_full - r_ext).ceil();
    let lsb = (0.0 - l_dist + l_val).ceil() as i64;
    let rsb = (0.0 - r_dist + r_val).ceil() as i64;

    Some(BaselineSpacing {
        lsb,
        rsb,
        left: SideSpacing { value: l_val, polygon_area: l_area, depth, distance: l_dist },
        right: SideSpacing { value: r_val, polygon_area: r_area, depth, distance: r_dist },
        receipt: SpacingReceipt {
            method: "baseline_htls: published HT Letterspacer method, clean-room reimplementation",
            tier: Tier::EngineDerived,
            params: *master,
            window: (min_y_ref, max_y_ref),
            notes: String::new(),
        },
    })
}

/// Depth clamp + 45-degree closure + polygon close for one side
/// (published setDepth + diagonize + closeOpenCounters).
fn process_side(
    zone: &[Pt],
    extreme_x: f64,
    left: bool,
    min_y_ref: f64,
    max_y_ref: f64,
    master: &MasterParams,
) -> Vec<Pt> {
    let depth = master.x_height * master.param_depth_pct / 100.0;
    let clamp_line = if left { extreme_x + depth } else { extreme_x - depth };
    let mut m: Vec<Pt> = zone
        .iter()
        .map(|p| Pt {
            x: if left { p.x.min(clamp_line) } else { p.x.max(clamp_line) },
            y: p.y,
        })
        .collect();

    // Extension rows at maximum depth, filling from the zone ends toward the
    // reference bounds (published setDepth).
    let freq = master.freq.max(1) as f64;
    let mut y = m[0].y - freq;
    while y > min_y_ref {
        m.insert(0, Pt { x: clamp_line, y });
        y -= freq;
    }
    let last_y = m[m.len() - 1].y;
    let mut y = last_y + freq;
    while y < max_y_ref {
        m.push(Pt { x: clamp_line, y });
        y += freq;
    }

    // 45-degree closure (published diagonize): forward pass, then backward.
    if m.len() >= 2 {
        let ystep = (m[0].y - m[1].y).abs();
        for i in 0..m.len() - 1 {
            if left {
                if m[i + 1].x - m[i].x > ystep {
                    m[i + 1].x = m[i].x + ystep;
                }
            } else if m[i + 1].x - m[i].x < -ystep {
                m[i + 1].x = m[i].x - ystep;
            }
        }
        for i in (0..m.len() - 1).rev() {
            if left {
                if m[i].x - m[i + 1].x > ystep {
                    m[i].x = m[i + 1].x + ystep;
                }
            } else if m[i].x - m[i + 1].x < -ystep {
                m[i].x = m[i + 1].x - ystep;
            }
        }
    }

    // Close the polygon at the extreme line (published closeOpenCounters).
    m.insert(0, Pt { x: extreme_x, y: min_y_ref });
    m.push(Pt { x: extreme_x, y: max_y_ref });
    m
}


/// Step 0 pair driver output: both spacings, the advance, the placements on
/// the shared canvas, and the collision verdict.
#[derive(Debug)]
pub struct PairPlacement {
    pub left: BaselineSpacing,
    pub right: BaselineSpacing,
    pub advance: i64,
    pub kern: i64,
    pub left_at: crate::collision::Placement,
    pub right_at: crate::collision::Placement,
    pub verdict: crate::collision::CollisionVerdict,
}

/// Space two glyphs with the baseline method, place the second at
/// origin + advance + kern, and run the raster collision gate.
///
/// Frame convention (step 0): both images live in the same canvas frame
/// (same pixel height, same baseline row); the left image's pixel (0,0) is
/// the canvas origin. Advance = ink width + lsb + rsb of the left glyph
/// (natural width). kern is normally 0 at this step; pair displacement
/// solving arrives with positions (step 5). The gate catches any placement
/// that overlaps ink (e.g. a forced negative kern).
pub fn place_pair(
    left: &crate::plane::GrayImage,
    right: &crate::plane::GrayImage,
    master: &MasterParams,
    kern: i64,
) -> Option<PairPlacement> {
    use crate::collision::{CollisionValidator, Placement, RasterConservativeValidator};
    let lg = crate::plane::RasterGlyph { image: left };
    let rg = crate::plane::RasterGlyph { image: right };
    let ls = space_glyph(&lg, None, master)?;
    let rs = space_glyph(&rg, None, master)?;
    let (lbx0, _, lbx1, _) = lg.ink_bbox()?;
    let (rbx0, _, _, _) = rg.ink_bbox()?;
    let ink_w = lbx1 - lbx0 + 1;
    let advance = ink_w + ls.lsb + ls.rsb;
    let left_origin = lbx0 - ls.lsb;
    let right_origin = left_origin + advance + kern;
    let left_at = Placement { x: 0, y: 0 };
    let right_at = Placement { x: right_origin + rs.lsb - rbx0, y: 0 };
    let verdict = RasterConservativeValidator.verdict(left, left_at, right, right_at);
    Some(PairPlacement {
        left: ls,
        right: rs,
        advance,
        kern,
        left_at,
        right_at,
        verdict,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plane::{GrayImage, RasterGlyph};

    fn rect_image(w: u32, h: u32, x0: u32, y0: u32, x1: u32, y1: u32) -> GrayImage {
        let mut px = vec![255u8; (w * h) as usize];
        for y in y0..y1 {
            for x in x0..x1 {
                px[(y * w + x) as usize] = 0;
            }
        }
        GrayImage::new(w, h, px)
    }

    #[test]
    fn shoelace_unit_square() {
        let pts = vec![
            Pt { x: 0.0, y: 0.0 },
            Pt { x: 1.0, y: 0.0 },
            Pt { x: 1.0, y: 1.0 },
            Pt { x: 0.0, y: 1.0 },
        ];
        assert!((polygon_area(&pts) - 1.0).abs() < 1e-12);
    }

    #[test]
    fn flat_side_gets_nominal_value() {
        // Flat-sided rectangle: the white polygon degenerates to zero area,
        // so the sidebearing equals white_area / x_height (published
        // behavior: flat sides get the nominal value).
        let img = rect_image(200, 200, 10, 20, 110, 120);
        let g = RasterGlyph { image: &img };
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let s = space_glyph(&g, None, &m).unwrap();
        assert_eq!(s.lsb, 400);
        assert_eq!(s.rsb, 400);
    }

    #[test]
    fn scale_invariance() {
        // Same shape at 2x scale with 2x master parameters: sidebearings
        // double (unit/scale invariance gate).
        let img1 = rect_image(200, 200, 10, 20, 110, 120);
        let img2 = rect_image(400, 400, 20, 40, 220, 240);
        let m1 = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let m2 = MasterParams { upm: 2000.0, x_height: 200.0, ..Default::default() };
        let s1 = space_glyph(&RasterGlyph { image: &img1 }, None, &m1).unwrap();
        let s2 = space_glyph(&RasterGlyph { image: &img2 }, None, &m2).unwrap();
        assert_eq!(s2.lsb, 2 * s1.lsb);
        assert_eq!(s2.rsb, 2 * s1.rsb);
    }

    #[test]
    fn determinism() {
        let img = rect_image(200, 200, 10, 20, 110, 120);
        let m = MasterParams::default();
        let a = space_glyph(&RasterGlyph { image: &img }, None, &m).unwrap();
        let b = space_glyph(&RasterGlyph { image: &img }, None, &m).unwrap();
        assert_eq!(a.lsb, b.lsb);
        assert_eq!(a.rsb, b.rsb);
        assert_eq!(a.left.polygon_area, b.left.polygon_area);
    }

    #[test]
    fn empty_glyph_aborts() {
        let img = GrayImage::new(50, 50, vec![255u8; 2500]);
        assert!(space_glyph(&RasterGlyph { image: &img }, None, &MasterParams::default()).is_none());
    }

    #[test]
    fn indented_side_gets_tighter_value_than_flat() {
        // A side that recedes from its extreme (concave white polygon, area
        // > 0) gets a TIGHTER sidebearing than a flat side: the published
        // compensation for round/open shapes.
        let mut img = rect_image(200, 200, 10, 20, 110, 120);
        // Carve a triangular notch into the left edge: deepest at mid-height.
        for y in 40u32..100 {
            let t = ((y as i64 - 70).abs() as u32).min(30);
            let cut = 30 - t; // 0..30 px of ink removed from the left edge
            for x in 10..10 + cut {
                img.px[(y * 200 + x) as usize] = 255;
            }
        }
        let g = RasterGlyph { image: &img };
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let s = space_glyph(&g, None, &m).unwrap();
        assert!(s.left.polygon_area > 0.0);
        assert!(s.lsb < 400, "indented side should be tighter than nominal 400, got {}", s.lsb);
    }

    fn ellipse_image(w: u32, h: u32, cx: f64, cy: f64, rx: f64, ry: f64) -> GrayImage {
        let mut px = vec![255u8; (w * h) as usize];
        for y in 0..h {
            for x in 0..w {
                let dx = (x as f64 - cx) / rx;
                let dy = (y as f64 - cy) / ry;
                if dx * dx + dy * dy <= 1.0 {
                    px[(y * w + x) as usize] = 0;
                }
            }
        }
        GrayImage::new(w, h, px)
    }

    fn tri_image(w: u32, h: u32, x0: u32, y0: u32, x1: u32, y1: u32, apex_up: bool) -> GrayImage {
        let mut px = vec![255u8; (w * h) as usize];
        let n = (y1 - y0) as f64;
        let cx = (x0 + x1) as f64 / 2.0;
        for y in y0..y1 {
            let t = (y - y0) as f64 / n;
            let half = ((x1 - x0) as f64 / 2.0) * if apex_up { t } else { 1.0 - t };
            let xa = (cx - half).round().max(0.0) as u32;
            let xb = ((cx + half).round() as u32).min(w);
            for x in xa..xb {
                px[(y * w + x) as usize] = 0;
            }
        }
        GrayImage::new(w, h, px)
    }

    fn t_image(w: u32, h: u32) -> GrayImage {
        // Top bar plus centered stem.
        let mut px = vec![255u8; (w * h) as usize];
        for y in 20..40 {
            for x in 10..150 {
                px[(y * w + x) as usize] = 0;
            }
        }
        for y in 40..120 {
            for x in 70..90 {
                px[(y * w + x) as usize] = 0;
            }
        }
        GrayImage::new(w, h, px)
    }

    fn c_image(w: u32, h: u32) -> GrayImage {
        // C-like open counter: full block, right side opened at mid heights.
        let mut img = rect_image(w, h, 10, 20, 110, 120);
        for y in 50..90 {
            for x in 40..110 {
                img.px[(y * w + x) as usize] = 255;
            }
        }
        img
    }

    #[test]
    fn round_side_tighter_than_flat() {
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let h_img = rect_image(200, 200, 10, 20, 110, 120);
        let o_img = ellipse_image(200, 200, 60.0, 70.0, 50.0, 50.0);
        let sh = space_glyph(&RasterGlyph { image: &h_img }, None, &m).unwrap();
        let so = space_glyph(&RasterGlyph { image: &o_img }, None, &m).unwrap();
        assert!(so.left.polygon_area > 0.0);
        assert!(so.lsb < sh.lsb, "round {} should be tighter than flat {}", so.lsb, sh.lsb);
    }

    #[test]
    fn depth_clamp_limits_open_counter_measurement() {
        // Deeper paramDepth measures deeper into the open counter: larger
        // white polygon, tighter sidebearing.
        let img = c_image(200, 200);
        let g = RasterGlyph { image: &img };
        let shallow = MasterParams { upm: 1000.0, x_height: 100.0, param_depth_pct: 15.0, ..Default::default() };
        let deep = MasterParams { param_depth_pct: 100.0, ..shallow };
        let s15 = space_glyph(&g, None, &shallow).unwrap();
        let s100 = space_glyph(&g, None, &deep).unwrap();
        assert!(s100.right.polygon_area > s15.right.polygon_area);
        assert!(s100.rsb < s15.rsb);
    }

    #[test]
    fn pairs_clear_hh_oo_ho() {
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let h = rect_image(200, 200, 10, 20, 110, 120);
        let o = ellipse_image(200, 200, 60.0, 70.0, 50.0, 50.0);
        for (a, b) in [(&h, &h), (&o, &o), (&h, &o), (&o, &h)] {
            let p = place_pair(a, b, &m, 0).unwrap();
            assert_eq!(p.verdict, crate::collision::CollisionVerdict::Clear);
        }
    }

    #[test]
    fn pairs_clear_diagonals_av_va_and_t_a() {
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let a = tri_image(200, 200, 10, 20, 150, 120, true);
        let v = tri_image(200, 200, 10, 20, 150, 120, false);
        let t = t_image(200, 200);
        for (x, y) in [(&a, &v), (&v, &a), (&t, &a), (&a, &t)] {
            let p = place_pair(x, y, &m, 0).unwrap();
            assert_eq!(p.verdict, crate::collision::CollisionVerdict::Clear);
        }
    }

    #[test]
    fn negative_kern_collision_detected() {
        let m = MasterParams { upm: 1000.0, x_height: 100.0, ..Default::default() };
        let h1 = rect_image(200, 200, 10, 20, 110, 120);
        let h2 = rect_image(200, 200, 10, 20, 110, 120);
        let p0 = place_pair(&h1, &h2, &m, 0).unwrap();
        let p = place_pair(&h1, &h2, &m, -(p0.advance + 5)).unwrap();
        assert!(matches!(p.verdict, crate::collision::CollisionVerdict::Overlap { .. }));
    }

    #[test]
    fn italic_deslant_recovers_upright_spacing() {
        // A right-leaning shear of the rectangle, spaced with the matching
        // italic angle, must recover the upright sidebearings.
        let upright = rect_image(300, 200, 40, 20, 140, 120);
        let angle = 12f64;
        let t = (angle * std::f64::consts::PI / 180.0).tan();
        let mline = 70.0f64; // baseline_y(120) - x_height(100)/2
        let mut px = vec![255u8; 300 * 200];
        for y in 20..120u32 {
            let shift = ((mline - y as f64) * t).round() as i64;
            for x in (40 + shift)..(140 + shift) {
                px[(y * 300 + x as u32) as usize] = 0;
            }
        }
        let italic = GrayImage::new(300, 200, px);
        let mu = MasterParams { upm: 1000.0, x_height: 100.0, baseline_y: 120.0, ..Default::default() };
        let mi = MasterParams { italic_angle_deg: angle, ..mu };
        let su = space_glyph(&RasterGlyph { image: &upright }, None, &mu).unwrap();
        let si = space_glyph(&RasterGlyph { image: &italic }, None, &mi).unwrap();
        assert!((si.lsb - su.lsb).abs() <= 1, "italic {} vs upright {}", si.lsb, su.lsb);
        assert!((si.rsb - su.rsb).abs() <= 1, "italic {} vs upright {}", si.rsb, su.rsb);
    }
}
