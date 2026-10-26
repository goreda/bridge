//! STEP 4: stress - min-distance loci, penetration, pressure ridges.
//!
//! Raster-plane implementation over the chamfer distance field (step 1):
//! the inter-glyph channel's distance field IS the hole measure (research
//! pool: the kern "hole" is the ridge/channel of the complement distance
//! field). Min-distance loci and pressure ridge are computed from placed
//! ink masks on a shared canvas. Chamfer 3-4 approximate metric (documented
//! in distance_field); exact contour distance replaces it when the contour
//! backend lands.

use crate::collision::Placement;
use crate::distance_field::DistanceField;
use crate::plane::GrayImage;

/// CONVENTION: numeric tie tolerance for comparing two distances, in plane
/// pixels. Derivation: distances come from `DistanceField::at`, which is a
/// multiple of 1/CHAMFER_ORTHO pixel, so any two different measurable
/// distances differ by at least 1/CHAMFER_ORTHO (about 0.33 px); a tolerance of
/// 1e-12 is an arbitrary-scale choice far below that step, meant to absorb
/// float rounding; it is not a measured error bound.
pub(crate) const TIE_TOLERANCE: f64 = 1e-12;

/// Shared-canvas rasterization of two placed glyphs.
pub(crate) struct PairCanvas {
    pub width: u32,
    pub height: u32,
    pub origin_x: i64,
    pub origin_y: i64,
    pub left_ink: Vec<bool>,
    pub right_ink: Vec<bool>,
}

impl PairCanvas {
    pub(crate) fn build(
        left: &GrayImage,
        left_at: Placement,
        right: &GrayImage,
        right_at: Placement,
    ) -> Option<Self> {
        let boxes = [(left_at, left.width, left.height), (right_at, right.width, right.height)];
        let mut min_x = i64::MAX;
        let mut min_y = i64::MAX;
        let mut max_x = i64::MIN;
        let mut max_y = i64::MIN;
        for (at, w, h) in boxes {
            min_x = min_x.min(at.x);
            min_y = min_y.min(at.y);
            max_x = max_x.max(at.x + w as i64);
            max_y = max_y.max(at.y + h as i64);
        }
        if min_x > max_x {
            return None;
        }
        let w = (max_x - min_x) as u32;
        let h = (max_y - min_y) as u32;
        let mut left_ink = vec![false; (w * h) as usize];
        let mut right_ink = vec![false; (w * h) as usize];
        for y in 0..left.height {
            for x in 0..left.width {
                if left.ink_at(x, y) {
                    let cx = (left_at.x + x as i64 - min_x) as usize;
                    let cy = (left_at.y + y as i64 - min_y) as usize;
                    left_ink[cy * w as usize + cx] = true;
                }
            }
        }
        for y in 0..right.height {
            for x in 0..right.width {
                if right.ink_at(x, y) {
                    let cx = (right_at.x + x as i64 - min_x) as usize;
                    let cy = (right_at.y + y as i64 - min_y) as usize;
                    right_ink[cy * w as usize + cx] = true;
                }
            }
        }
        Some(Self { width: w, height: h, origin_x: min_x, origin_y: min_y, left_ink, right_ink })
    }

    fn to_image(ink: &[bool], w: u32, h: u32) -> GrayImage {
        let px: Vec<u8> = ink.iter().map(|&b| if b { 0 } else { 255 }).collect();
        GrayImage::new(w, h, px)
    }
}

/// Stress features of one pair placement.
#[derive(Debug, Clone)]
pub struct StressReport {
    /// Minimum chamfer distance between the two masks (pixels). 0 when the
    /// masks touch or overlap.
    pub min_distance: f64,
    /// Canvas coordinates of the left-ink pixels attaining the minimum.
    pub loci_left: Vec<(i64, i64)>,
    /// Canvas coordinates of the right-ink pixels attaining the minimum.
    pub loci_right: Vec<(i64, i64)>,
    /// Shared ink cells when the masks interpenetrate (0 when clear).
    pub overlap_px: u64,
    /// Pressure ridge strength: maximum distance-to-ink inside the
    /// inter-glyph channel region (the "hole" depth, pixels). 0 when there
    /// is no channel.
    pub pressure: f64,
}

/// Stress analysis of one pair placement.
pub fn analyze(
    left: &GrayImage,
    left_at: Placement,
    right: &GrayImage,
    right_at: Placement,
) -> Option<StressReport> {
    let canvas = PairCanvas::build(left, left_at, right, right_at)?;
    let w = canvas.width;
    let h = canvas.height;
    let n = (w * h) as usize;

    let mut overlap_px = 0u64;
    for i in 0..n {
        if canvas.left_ink[i] && canvas.right_ink[i] {
            overlap_px += 1;
        }
    }

    // Min-distance loci, both directions (chamfer distance to the other
    // glyph's ink, sampled on this glyph's ink).
    let df_left = DistanceField::from_ink(&PairCanvas::to_image(&canvas.left_ink, w, h));
    let df_right = DistanceField::from_ink(&PairCanvas::to_image(&canvas.right_ink, w, h));
    let mut min_distance = f64::INFINITY;
    let mut loci_left: Vec<(i64, i64)> = Vec::new();
    let mut loci_right: Vec<(i64, i64)> = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) as usize;
            if canvas.right_ink[i] {
                let d = df_left.at(x, y);
                if d < min_distance - TIE_TOLERANCE {
                    min_distance = d;
                    loci_right.clear();
                }
                if (d - min_distance).abs() < TIE_TOLERANCE {
                    loci_right.push((x as i64 + canvas.origin_x, y as i64 + canvas.origin_y));
                }
            }
            if canvas.left_ink[i] {
                let d = df_right.at(x, y);
                if d < min_distance - TIE_TOLERANCE {
                    min_distance = d;
                    loci_left.clear();
                }
                if (d - min_distance).abs() < TIE_TOLERANCE {
                    loci_left.push((x as i64 + canvas.origin_x, y as i64 + canvas.origin_y));
                }
            }
        }
    }
    if min_distance.is_infinite() {
        min_distance = 0.0;
    }

    // Pressure ridge: max distance-to-ink (union field) inside the channel
    // region between the glyphs' ink extremes over the shared y-range.
    let mut left_max_x: i64 = i64::MIN;
    let mut right_min_x: i64 = i64::MAX;
    let mut y_min = i64::MAX;
    let mut y_max = i64::MIN;
    for y in 0..h {
        for x in 0..w {
            let i = (y * w + x) as usize;
            if canvas.left_ink[i] {
                left_max_x = left_max_x.max(x as i64);
                y_min = y_min.min(y as i64);
                y_max = y_max.max(y as i64);
            }
            if canvas.right_ink[i] {
                right_min_x = right_min_x.min(x as i64);
            }
        }
    }
    let mut union_ink = canvas.left_ink.clone();
    for i in 0..n {
        union_ink[i] = union_ink[i] || canvas.right_ink[i];
    }
    let df_union = DistanceField::from_ink(&PairCanvas::to_image(&union_ink, w, h));
    let mut pressure: f64 = 0.0;
    if left_max_x != i64::MIN && right_min_x != i64::MAX && left_max_x < right_min_x {
        for y in 0..h {
            if (y as i64) < y_min || (y as i64) > y_max {
                continue;
            }
            for x in (left_max_x + 1)..right_min_x {
                pressure = pressure.max(df_union.at(x as u32, y));
            }
        }
    }

    Some(StressReport { min_distance, loci_left, loci_right, overlap_px, pressure })
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn separated_rects_distance_and_pressure() {
        // Left ink x 10..19, right ink x 30..39 (same rows 10..109): the
        // ink-to-ink distance is 11 px; the channel is 20..29 (10 px wide),
        // so the ridge sits about 5 px from the nearer wall.
        let left = rect_image(50, 120, 10, 10, 20, 110);
        let right = rect_image(50, 120, 30, 10, 40, 110);
        let r = analyze(&left, Placement { x: 0, y: 0 }, &right, Placement { x: 0, y: 0 }).unwrap();
        assert!((r.min_distance - 11.0).abs() < 1e-9);
        assert_eq!(r.overlap_px, 0);
        assert!(!r.loci_left.is_empty() && !r.loci_right.is_empty());
        assert!((r.pressure - 5.0).abs() <= 4.0 / 3.0); // chamfer tolerance
    }

    #[test]
    fn overlapping_masks_report_zero_distance_and_overlap() {
        let left = rect_image(50, 50, 10, 10, 20, 20);
        let right = rect_image(50, 50, 30, 10, 40, 20);
        let r = analyze(&left, Placement { x: 0, y: 0 }, &right, Placement { x: -15, y: 0 }).unwrap();
        assert_eq!(r.min_distance, 0.0);
        assert_eq!(r.overlap_px, 50);
    }
}
