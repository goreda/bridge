//! Input-plane abstraction.
//!
//! Pair geometry APIs accept BOTH planes from day one: raster distance field
//! now, contour distance later, same features. The raster plane (captures) is
//! the acquisition/evidence reality today; when the engine emits trusted
//! outlines, a contour-backed implementation of `InkScan` becomes the
//! geometric truth and raster stays the comparison/evidence backend.

/// CONVENTION: ink threshold on the 8-bit scale. Derivation: the midpoint of
/// the representable range 0..=255, rounded up to 128; a pixel below it is
/// ink. It sets the ink mask, so it changes every downstream measurement.
pub const INK_THRESHOLD: u8 = 128;

/// 8-bit grayscale image, row-major, origin top-left, y down (capture
/// convention). Ink is dark: a pixel is ink when its value is below 128
/// (the 0.5 iso at 8-bit, same convention as the measurement harness).
#[derive(Debug, Clone)]
pub struct GrayImage {
    pub width: u32,
    pub height: u32,
    pub px: Vec<u8>,
}

impl GrayImage {
    pub fn new(width: u32, height: u32, px: Vec<u8>) -> Self {
        assert_eq!((width as usize) * (height as usize), px.len());
        Self { width, height, px }
    }

    pub fn ink_at(&self, x: u32, y: u32) -> bool {
        self.px[(y * self.width + x) as usize] < INK_THRESHOLD
    }
}

/// Horizontal ink-span scan of one glyph on any plane.
///
/// This is the minimal geometry surface the spacing/kerning modules need:
/// per scanline, the leftmost and rightmost ink coordinate. The raster
/// backend walks pixels; the future contour backend computes scanline
/// intersections. Coordinates are plane units (capture px today).
pub trait InkScan {
    /// (left, right) ink extremes on scanline `y`, or None when the row is
    /// empty (fully white) or outside the glyph.
    fn row_span(&self, y: i64) -> Option<(i64, i64)>;
    /// (min_y, max_y) of rows containing ink, or None for an empty glyph.
    fn y_bounds(&self) -> Option<(i64, i64)>;
}

/// Raster-backed `InkScan` over a `GrayImage`.
pub struct RasterGlyph<'a> {
    pub image: &'a GrayImage,
}

impl<'a> RasterGlyph<'a> {
    /// (min_x, min_y, max_x, max_y) ink bounding box, None if empty.
    pub fn ink_bbox(&self) -> Option<(i64, i64, i64, i64)> {
        let (min_y, max_y) = self.y_bounds()?;
        let mut min_x = i64::MAX;
        let mut max_x = i64::MIN;
        for y in min_y..=max_y {
            if let Some((l, r)) = self.row_span(y) {
                min_x = min_x.min(l);
                max_x = max_x.max(r);
            }
        }
        Some((min_x, min_y, max_x, max_y))
    }
}

impl<'a> InkScan for RasterGlyph<'a> {
    fn row_span(&self, y: i64) -> Option<(i64, i64)> {
        if y < 0 || y >= self.image.height as i64 {
            return None;
        }
        let y = y as u32;
        let mut left: i64 = -1;
        let mut right: i64 = -1;
        for x in 0..self.image.width {
            if self.image.ink_at(x, y) {
                if left < 0 {
                    left = x as i64;
                }
                right = x as i64;
            }
        }
        if left < 0 {
            None
        } else {
            Some((left, right))
        }
    }

    fn y_bounds(&self) -> Option<(i64, i64)> {
        let mut min_y: i64 = -1;
        let mut max_y: i64 = -1;
        for y in 0..self.image.height as i64 {
            if self.row_span(y).is_some() {
                if min_y < 0 {
                    min_y = y;
                }
                max_y = y;
            }
        }
        if min_y < 0 {
            None
        } else {
            Some((min_y, max_y))
        }
    }
}
