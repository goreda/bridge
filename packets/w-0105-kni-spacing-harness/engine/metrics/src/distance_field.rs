//! STEP 1: distance_field - complement distance transform, integral image,
//! per-height wall profiles.
//!
//! Source grounding: Borgefors 1986 (canonical raster distance transform,
//! chamfer 3-4 weights); typographic area/white methods are distance/area
//! methods in disguise (HT Letterspacer, CounterSpace, EPFL 5768490);
//! per-height LB/RB sidebearing dictionaries = BubbleKern v1's 10-unit scan
//! pattern (code-grounded); integral image = Viola-Jones 2001 (O(1) area
//! queries, infrastructure for every area-based measure). Tier (a).
//!
//! Raster plane now; when contours become the geometric truth, the same
//! features are computed from contour distance and this stays the
//! comparison/evidence backend.

use crate::plane::{GrayImage, InkScan};

/// Chamfer 3-4 distance transform (Borgefors 1986): distance to nearest ink,
/// stored as integer 3x the approximate pixel distance (orthogonal step 3,
/// diagonal step 4; divide by 3 for the approximate distance, within about
/// 8 percent of Euclidean - the documented raster-plane metric, not an exact
/// contour distance).
#[derive(Debug, Clone)]
pub struct DistanceField {
    pub width: u32,
    pub height: u32,
    /// 3x approximate distance to nearest ink, per pixel, row-major.
    pub dist3: Vec<u32>,
}

/// CONVENTION: 3-4 chamfer local distances (orthogonal step, diagonal step).
/// Source: G. Borgefors, "Distance transformations in digital images",
/// Computer Vision, Graphics, and Image Processing 34(3), 1986, 344-371,
/// section "3x3 neighborhood": the integer 3-4 mask approximates the
/// Euclidean distance with an error of at most 8% (figure as stated in the
/// paper's text; not re-derived here). The diagonal 4 is the
/// integer approximation of 3 * sqrt(2) = 4.24.
pub const CHAMFER_ORTHO: u32 = 3;
pub const CHAMFER_DIAG: u32 = 4;

/// CONVENTION: "no ink reached yet" marker. It must exceed every finite
/// path sum, which is at most CHAMFER_DIAG * (width + height) and also stay
/// below u32::MAX - CHAMFER_DIAG so the additions in the two passes cannot
/// overflow. u32::MAX / 4 satisfies both for images up to about 2^28 pixels
/// in width + height.
const INF: u32 = u32::MAX / CHAMFER_DIAG;

impl DistanceField {
    /// Complement distance transform: 0 on ink pixels, chamfer distance to
    /// the nearest ink elsewhere.
    pub fn from_ink(image: &GrayImage) -> Self {
        let w = image.width as usize;
        let h = image.height as usize;
        let mut d = vec![INF; w * h];
        for y in 0..image.height {
            for x in 0..image.width {
                if image.ink_at(x, y) {
                    d[y as usize * w + x as usize] = 0;
                }
            }
        }
        // Forward pass: from top-left.
        for y in 0..h {
            for x in 0..w {
                let i = y * w + x;
                let mut best = d[i];
                if x > 0 {
                    best = best.min(d[i - 1] + CHAMFER_ORTHO);
                    if y > 0 {
                        best = best.min(d[i - 1 - w] + CHAMFER_DIAG);
                    }
                }
                if y > 0 {
                    best = best.min(d[i - w] + CHAMFER_ORTHO);
                    if x + 1 < w {
                        best = best.min(d[i + 1 - w] + CHAMFER_DIAG);
                    }
                }
                d[i] = best;
            }
        }
        // Backward pass: from bottom-right.
        for y in (0..h).rev() {
            for x in (0..w).rev() {
                let i = y * w + x;
                let mut best = d[i];
                if x + 1 < w {
                    best = best.min(d[i + 1] + CHAMFER_ORTHO);
                    if y + 1 < h {
                        best = best.min(d[i + 1 + w] + CHAMFER_DIAG);
                    }
                }
                if y + 1 < h {
                    best = best.min(d[i + w] + CHAMFER_ORTHO);
                    if x > 0 {
                        best = best.min(d[i + w - 1] + CHAMFER_DIAG);
                    }
                }
                d[i] = best;
            }
        }
        Self { width: image.width, height: image.height, dist3: d }
    }

    /// Approximate distance to nearest ink at (x, y), in pixels.
    pub fn at(&self, x: u32, y: u32) -> f64 {
        self.dist3[(y * self.width + x) as usize] as f64 / CHAMFER_ORTHO as f64
    }
}

/// Integral image (summed-area table) over the ink mask: O(1) ink-area
/// queries over axis-aligned rectangles (Viola-Jones 2001 precedent).
#[derive(Debug, Clone)]
pub struct IntegralImage {
    pub width: u32,
    pub height: u32,
    /// (width+1) x (height+1) running sums; cell (0,0) and the first
    /// row/column are zero.
    sums: Vec<u64>,
}

impl IntegralImage {
    pub fn from_ink(image: &GrayImage) -> Self {
        let w = image.width as usize;
        let h = image.height as usize;
        let mut sums = vec![0u64; (w + 1) * (h + 1)];
        for y in 0..h {
            let mut row = 0u64;
            for x in 0..w {
                if image.ink_at(x as u32, y as u32) {
                    row += 1;
                }
                sums[(y + 1) * (w + 1) + (x + 1)] = sums[y * (w + 1) + (x + 1)] + row;
            }
        }
        Self { width: image.width, height: image.height, sums }
    }

    /// Ink pixel count inside [x0, x1) x [y0, y1), clamped to the image.
    pub fn rect_ink(&self, x0: u32, y0: u32, x1: u32, y1: u32) -> u64 {
        let w = self.width;
        let h = self.height;
        let x0 = x0.min(w);
        let y0 = y0.min(h);
        let x1 = x1.min(w);
        let y1 = y1.min(h);
        if x0 >= x1 || y0 >= y1 {
            return 0;
        }
        let s = |x: u32, y: u32| self.sums[(y as usize) * (w as usize + 1) + x as usize];
        // Ordered so u64 intermediates never go negative (s is
        // monotone in both coordinates).
        (s(x1, y1) + s(x0, y0)) - s(x0, y1) - s(x1, y0)
    }
}

/// Per-height wall profiles (BubbleKern v1's per-height LB/RB pattern,
/// raster-plane equivalent): for every ink row, the leftmost and rightmost
/// ink coordinate. The 10-unit grid of v1 becomes the capture's own row grid.
#[derive(Debug, Clone)]
pub struct WallProfiles {
    /// (y, left_x, right_x) per row containing ink, y ascending.
    pub rows: Vec<(i64, i64, i64)>,
}

impl WallProfiles {
    pub fn from_scan<S: InkScan>(glyph: &S) -> Option<Self> {
        let (y0, y1) = glyph.y_bounds()?;
        let mut rows = Vec::new();
        for y in y0..=y1 {
            if let Some((l, r)) = glyph.row_span(y) {
                rows.push((y, l, r));
            }
        }
        Some(Self { rows })
    }

    /// Left wall value at row y (leftmost ink), None when the row is empty.
    pub fn left_at(&self, y: i64) -> Option<i64> {
        self.rows.iter().find(|(ry, _, _)| *ry == y).map(|(_, l, _)| *l)
    }

    /// Right wall value at row y (rightmost ink), None when the row is empty.
    pub fn right_at(&self, y: i64) -> Option<i64> {
        self.rows.iter().find(|(ry, _, _)| *ry == y).map(|(_, _, r)| *r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn single_pixel(w: u32, h: u32, ix: u32, iy: u32) -> GrayImage {
        let mut px = vec![255u8; (w * h) as usize];
        px[(iy * w + ix) as usize] = 0;
        GrayImage::new(w, h, px)
    }

    #[test]
    fn chamfer_distances_around_single_pixel() {
        let img = single_pixel(30, 30, 10, 10);
        let df = DistanceField::from_ink(&img);
        assert_eq!(df.at(10, 10), 0.0);
        assert!((df.at(11, 10) - 1.0).abs() < 1e-9); // one orthogonal step
        assert!((df.at(11, 11) - 4.0 / 3.0).abs() < 1e-9); // one diagonal step
        assert!((df.at(13, 10) - 3.0).abs() < 1e-9); // three orthogonal steps
        // 3 right + 1 down: one diagonal + two orthogonal = (4+6)/3
        assert!((df.at(13, 11) - 10.0 / 3.0).abs() < 1e-9);
    }

    #[test]
    fn integral_image_counts_ink() {
        let mut px = vec![255u8; 20 * 20];
        for y in 5..15 {
            for x in 5..15 {
                px[(y * 20 + x) as usize] = 0;
            }
        }
        let img = GrayImage::new(20, 20, px);
        let ii = IntegralImage::from_ink(&img);
        assert_eq!(ii.rect_ink(0, 0, 20, 20), 100);
        assert_eq!(ii.rect_ink(5, 5, 15, 15), 100);
        assert_eq!(ii.rect_ink(0, 0, 5, 5), 0);
        assert_eq!(ii.rect_ink(5, 5, 10, 10), 25);
        assert_eq!(ii.rect_ink(14, 14, 20, 20), 1);
    }

    #[test]
    fn wall_profiles_match_row_spans() {
        let mut px = vec![255u8; 50 * 50];
        for y in 10..40 {
            for x in 5..20 {
                px[(y * 50 + x) as usize] = 0;
            }
        }
        let img = GrayImage::new(50, 50, px);
        let g = crate::plane::RasterGlyph { image: &img };
        let wp = WallProfiles::from_scan(&g).unwrap();
        assert_eq!(wp.rows.len(), 30);
        assert_eq!(wp.left_at(10), Some(5));
        assert_eq!(wp.right_at(39), Some(19));
        assert_eq!(wp.left_at(45), None);
    }
}
