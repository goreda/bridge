//! STEP 0 GATE: collision validator.
//!
//! Today: RASTER-CONSERVATIVE overlap check over placed ink masks. It is a
//! necessary-condition check at capture resolution, not a sub-pixel
//! collision-free proof (known limitation: an 'o'-derived contact floor is NOT a
//! collision-free proof; blur/SDF remains an open alternative for diagonals).
//! When the engine emits trusted outlines, the EXACT outline collision
//! validator implements the same trait and this raster check stays as the
//! fast pre-filter.

use crate::plane::GrayImage;

/// Verdict of one placement check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CollisionVerdict {
    /// No shared ink cells at the current plane resolution.
    Clear,
    /// The two glyphs share ink cells; `pixels` counts the overlap.
    Overlap { pixels: u64 },
}

/// Where an image's pixel (0,0) sits on the shared canvas (plane units).
/// The caller derives placements from origins, advances, sidebearings and
/// kern values; the validator stays geometry-only.
#[derive(Debug, Clone, Copy)]
pub struct Placement {
    pub x: i64,
    pub y: i64,
}

/// Collision validation surface, plane-agnostic by construction: the exact
/// outline validator (future) and the raster validator (today) share it.
pub trait CollisionValidator {
    fn verdict(
        &self,
        left: &GrayImage,
        left_at: Placement,
        right: &GrayImage,
        right_at: Placement,
    ) -> CollisionVerdict;
}

/// Raster-conservative validator: counts shared ink cells between two placed
/// masks. Conservative because rasterization at a fixed scale can hide
/// sub-pixel interpenetration.
pub struct RasterConservativeValidator;

impl CollisionValidator for RasterConservativeValidator {
    fn verdict(
        &self,
        left: &GrayImage,
        left_at: Placement,
        right: &GrayImage,
        right_at: Placement,
    ) -> CollisionVerdict {
        // Left ink bbox on the shared canvas.
        let mut min_x = i64::MAX;
        let mut max_x = i64::MIN;
        let mut min_y = i64::MAX;
        let mut max_y = i64::MIN;
        for iy in 0..left.height {
            for ix in 0..left.width {
                if left.ink_at(ix, iy) {
                    let cx = left_at.x + ix as i64;
                    let cy = left_at.y + iy as i64;
                    min_x = min_x.min(cx);
                    max_x = max_x.max(cx);
                    min_y = min_y.min(cy);
                    max_y = max_y.max(cy);
                }
            }
        }
        if min_x > max_x {
            return CollisionVerdict::Clear;
        }
        let mut pixels = 0u64;
        for iy in 0..right.height {
            for ix in 0..right.width {
                if right.ink_at(ix, iy) {
                    let cx = right_at.x + ix as i64;
                    let cy = right_at.y + iy as i64;
                    if cx < min_x || cx > max_x || cy < min_y || cy > max_y {
                        continue;
                    }
                    let lx = (cx - left_at.x) as u32;
                    let ly = (cy - left_at.y) as u32;
                    if left.ink_at(lx, ly) {
                        pixels += 1;
                    }
                }
            }
        }
        if pixels > 0 {
            CollisionVerdict::Overlap { pixels }
        } else {
            CollisionVerdict::Clear
        }
    }
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
    fn overlap_detected_and_counted() {
        let left = rect_image(50, 50, 10, 10, 20, 20);
        let right = rect_image(50, 50, 30, 10, 40, 20);
        let v = RasterConservativeValidator.verdict(
            &left,
            Placement { x: 0, y: 0 },
            &right,
            Placement { x: -15, y: 0 },
        );
        // Right ink lands at x 15..24, y 10..19; left ink is x 10..19,
        // y 10..19; shared cells: x 15..19 (5) times y 10..19 (10) = 50.
        assert_eq!(v, CollisionVerdict::Overlap { pixels: 50 });
    }

    #[test]
    fn clear_when_separated() {
        let left = rect_image(50, 50, 10, 10, 20, 20);
        let right = rect_image(50, 50, 30, 10, 40, 20);
        let v = RasterConservativeValidator.verdict(
            &left,
            Placement { x: 0, y: 0 },
            &right,
            Placement { x: 0, y: 0 },
        );
        assert_eq!(v, CollisionVerdict::Clear);
    }

    #[test]
    fn clear_when_either_empty() {
        let empty = GrayImage::new(50, 50, vec![255u8; 2500]);
        let inked = rect_image(50, 50, 10, 10, 20, 20);
        let v = RasterConservativeValidator.verdict(
            &empty,
            Placement { x: 0, y: 0 },
            &inked,
            Placement { x: 0, y: 0 },
        );
        assert_eq!(v, CollisionVerdict::Clear);
    }
}
