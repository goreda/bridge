//! STEP 4: air - normalized white-space features.
//!
//! Features: surface, directionality, asymmetry, density of the inter-glyph
//! white channel. The NORMALIZATION FORM is published (iKern, 2022 panel:
//! AirValue = (Air1 - Air0)/Air0, PropertyValue = Airp/Air0, Air0 a function
//! of user parameters, especially Width). Air0 is anchored on measured
//! Width (space doctrine H-H chain).
//!
//! PROVENANCE BOUNDARY: iKern's Air equations are NOT public. The feature
//! DEFINITIONS below are OUR CANDIDATES (labeled per field), built on the
//! step 1 distance/integral infrastructure. They become the mechanism
//! semantics input for step 5 seed rules.

use crate::collision::Placement;
use crate::plane::GrayImage;
use crate::stress::PairCanvas;

/// White-space features of the inter-glyph channel for one placement.
/// All definitions are OUR CANDIDATES (see module docs).
#[derive(Debug, Clone, Copy)]
pub struct AirFeatures {
    /// CANDIDATE surface: white pixel count of the channel region.
    pub surface: f64,
    /// CANDIDATE directionality: vertical centroid of the channel white,
    /// relative to the channel mid-height, normalized to [-1, 1]
    /// (raster y down: positive = bottom-heavy).
    pub directionality: f64,
    /// CANDIDATE asymmetry: (top white - bottom white) / (top + bottom).
    pub asymmetry: f64,
    /// CANDIDATE density: ink fraction in the two bands flanking the
    /// channel (DENSITY_BAND px deep on each side).
    pub density: f64,
    /// Channel geometry actually measured (canvas coords): x in
    /// [channel_x0, channel_x1), y in [y0, y1).
    pub channel: (i64, i64, i64, i64),
}

/// Depth of the flanking bands for the density feature (plane units).
/// CANDIDATE constant.
pub const DENSITY_BAND: i64 = 4;

/// White features of the channel between two placed glyphs. The channel
/// region: x between the left glyph's ink max and the right glyph's ink
/// min, over the left glyph's ink y-range. None when there is no channel
/// (overlapping extremes or empty input).
pub fn channel_features(
    left: &GrayImage,
    left_at: Placement,
    right: &GrayImage,
    right_at: Placement,
) -> Option<AirFeatures> {
    let canvas = PairCanvas::build(left, left_at, right, right_at)?;
    let w = canvas.width as i64;
    let h = canvas.height as i64;

    // Per-row channel: on each row where BOTH glyphs carry ink, the white
    // run strictly between the left ink max and the right ink min. This
    // follows the shared-y-range discipline of the positions lockstep walk
    // and lets the channel widen where a glyph recedes (T stem rows, C
    // opening rows). Rows where either glyph is absent contribute nothing.
    let mut row_edges: Vec<(i64, i64, i64)> = Vec::new(); // (y, lmax, rmin)
    for y in 0..h {
        let mut lmax = i64::MIN;
        let mut rmin = i64::MAX;
        for x in 0..w {
            let i = (y * w + x) as usize;
            if canvas.left_ink[i] {
                lmax = lmax.max(x);
            }
            if canvas.right_ink[i] {
                rmin = rmin.min(x);
            }
        }
        if lmax != i64::MIN && rmin != i64::MAX && rmin > lmax + 1 {
            row_edges.push((y, lmax, rmin));
        }
    }
    if row_edges.is_empty() {
        return None;
    }
    let sy0 = row_edges.first().unwrap().0;
    let sy1 = row_edges.last().unwrap().0;
    let mid_y = (sy0 + sy1) as f64 / 2.0;
    let half_h = ((sy1 - sy0 + 1) as f64) / 2.0;

    let mut surface = 0.0f64;
    let mut moment_y = 0.0f64;
    let mut top_white = 0.0f64;
    let mut bottom_white = 0.0f64;
    for &(y, lmax, rmin) in &row_edges {
        let white = (rmin - lmax - 1) as f64;
        surface += white;
        moment_y += white * y as f64;
        if (y as f64) < mid_y {
            top_white += white;
        } else {
            bottom_white += white;
        }
    }
    if surface == 0.0 {
        return None;
    }
    let cx0 = row_edges.iter().map(|&(_, l, _)| l).min().unwrap() + 1;
    let cx1 = row_edges.iter().map(|&(_, _, r)| r).max().unwrap();
    let centroid_y = moment_y / surface;
    let directionality = ((centroid_y - mid_y) / half_h).clamp(-1.0, 1.0);
    let asymmetry = (top_white - bottom_white) / (top_white + bottom_white);

    // Density: ink fraction in the two DENSITY_BAND-deep bands flanking the
    // per-row channel edges, over the shared rows.
    let mut band_ink = 0.0f64;
    let mut band_cells = 0.0f64;
    for &(y, lmax, rmin) in &row_edges {
        for x in (lmax + 1 - DENSITY_BAND)..=lmax {
            if x >= 0 {
                band_cells += 1.0;
                if canvas.left_ink[(y * w + x) as usize] {
                    band_ink += 1.0;
                }
            }
        }
        for x in rmin..(rmin + DENSITY_BAND).min(w) {
            band_cells += 1.0;
            if canvas.right_ink[(y * w + x) as usize] {
                band_ink += 1.0;
            }
        }
    }
    let density = if band_cells > 0.0 { band_ink / band_cells } else { 0.0 };

    Some(AirFeatures {
        surface,
        directionality,
        asymmetry,
        density,
        channel: (cx0 + canvas.origin_x, cx1 + canvas.origin_x, sy0 + canvas.origin_y, sy1 + canvas.origin_y),
    })
}

/// Published normalization form (2022 panel): AirValue = (Air1 - Air0)/Air0.
/// Air0 is the Width-anchored reference (space doctrine H-H chain); the
/// anchor mapping arrives with the Width doctrine wiring.
pub fn air_value(air1: f64, air0: f64) -> f64 {
    (air1 - air0) / air0
}

/// Published normalization form: PropertyValue = Airp / Air0.
pub fn property_value(airp: f64, air0: f64) -> f64 {
    airp / air0
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
    fn symmetric_channel_is_balanced() {
        // 10 px channel (x 20..29) over 100 rows, both walls flat.
        let left = rect_image(50, 120, 10, 10, 20, 110);
        let right = rect_image(50, 120, 30, 10, 40, 110);
        let f = channel_features(&left, Placement { x: 0, y: 0 }, &right, Placement { x: 0, y: 0 }).unwrap();
        assert_eq!(f.surface, 10.0 * 100.0);
        assert!(f.directionality.abs() < 0.05);
        assert!(f.asymmetry.abs() < 1e-9);
        assert!(f.density > 0.99); // both flanks fully inked
    }

    #[test]
    fn receding_left_glyph_widens_channel_below() {
        // T-like left glyph: wide bar at top, narrow stem below. The
        // channel widens on the stem rows: bottom-heavier white.
        let mut left = rect_image(120, 130, 10, 10, 60, 30); // bar
        for y in 30..110u32 {
            for x in 30..40u32 {
                left.px[(y * 120 + x) as usize] = 0; // stem
            }
        }
        let right = rect_image(120, 130, 80, 10, 90, 110);
        let f = channel_features(&left, Placement { x: 0, y: 0 }, &right, Placement { x: 0, y: 0 }).unwrap();
        assert!(f.asymmetry < 0.0, "bottom-heavier white, got {}", f.asymmetry);
        assert!(f.directionality > 0.0, "centroid below mid, got {}", f.directionality);
    }

    #[test]
    fn no_channel_returns_none() {
        let left = rect_image(50, 50, 10, 10, 40, 20);
        let right = rect_image(50, 50, 30, 10, 40, 20);
        // Right glyph's ink min (30) is inside the left glyph's extent.
        assert!(channel_features(&left, Placement { x: 0, y: 0 }, &right, Placement { x: 0, y: 0 }).is_none());
    }

    #[test]
    fn published_normalization_forms() {
        assert!((air_value(120.0, 100.0) - 0.2).abs() < 1e-12);
        assert!((property_value(120.0, 100.0) - 1.2).abs() < 1e-12);
    }
}
