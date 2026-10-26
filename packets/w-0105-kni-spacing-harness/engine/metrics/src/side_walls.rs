//! STEP 2: side_walls - per-glyph-side polygon wall.
//!
//! Format (BubbleKern v2 code-grounded): y-sorted (x,y) polyline, left side
//! x>=0 inward, right side x<=0 inward (coordinates relative to the glyph's
//! own ink edge; plane units at this step, UPM units when the contour
//! backend lands).
//!
//! WALL SOURCES, tier-ordered:
//! 1. measured wall = per-height ink extent from captures + offset policy
//!    [SURROGATE - in BubbleKern the wall is designer-drawn; any auto offset
//!    policy is OURS, an open parameter, NOT published anywhere. The BubbleKern
//!    author's own statement stands: "the best bubble shape is unknown".]
//! 2. class-propagated wall (tier b, arrives with side_classes, step 3);
//! 3. designer override (BubbleKern native mode; accepted as input).
//!
//! Italic correction per v2 code: wall points are stored UPRIGHT; slant is
//! applied at use with the italic angle about the xHeight/2 pivot. Default
//! wall (no measurement available) = flush vertical line over
//! [descender, ascender] (v2 defaultNodes). Composite/reference inheritance
//! (v2 BubbleKernReferL/R, loop-rejected) arrives with font-level wiring.

use crate::distance_field::WallProfiles;

/// Which side of the glyph a wall belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    /// Left wall: coordinates are distances INWARD from the left ink edge,
    /// x>=0 toward the glyph interior (v2 format).
    Left,
    /// Right wall: x<=0 inward from the right ink edge (v2 format).
    Right,
}

/// Offset policy for deriving a wall from measured ink extents.
///
/// SURROGATE: every automatic offset policy is our surrogate (see module
/// docs); it is an open parameter, never a published result.
#[derive(Debug, Clone, Copy)]
pub enum OffsetPolicy {
    /// Constant outward offset in plane units.
    Constant(f64),
}

/// Per-glyph-side polygon wall: y-sorted (x,y) polyline.
#[derive(Debug, Clone)]
pub struct Wall {
    pub side: Side,
    /// (y, x) points, y ascending. Stored as canvas coordinates of the wall
    /// itself at this step; conversion to the v2 side-relative frame
    /// (Left x>=0 inward, Right x<=0 inward, UPM units) happens at
    /// export/use.
    pub points: Vec<(f64, f64)>,
    /// Provenance of this wall (measured+policy / default / override).
    pub source: WallSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WallSource {
    /// Measured ink extent + an OffsetPolicy (SURROGATE policy parameter).
    Measured,
    /// Flush vertical fallback line (v2 defaultNodes).
    DefaultLine,
    /// Designer-drawn input (BubbleKern native mode).
    DesignerOverride,
    /// Propagated through a side class from measured exemplars (tier b;
    /// arrives with side_classes, step 3).
    ClassPropagated,
}

impl Wall {
    /// Measured wall from per-height ink profiles plus an offset policy.
    ///
    /// Geometry: the wall runs parallel to the ink edge, pushed OUTWARD
    /// (away from the glyph interior) by the offset. Coordinates are stored
    /// as (y, canvas_x) of the wall itself, y ascending; conversion to the
    /// v2 side-relative frame happens at export/use.
    pub fn measured(profiles: &WallProfiles, side: Side, policy: OffsetPolicy) -> Option<Self> {
        if profiles.rows.is_empty() {
            return None;
        }
        let OffsetPolicy::Constant(off) = policy;
        let mut points = Vec::with_capacity(profiles.rows.len());
        for &(y, l, r) in &profiles.rows {
            let x = match side {
                Side::Left => l as f64 - off,
                Side::Right => r as f64 + off,
            };
            points.push((y as f64, x));
        }
        Some(Self { side, points, source: WallSource::Measured })
    }

    /// Default wall (v2 defaultNodes): a flush vertical line at x over
    /// [descender, ascender].
    pub fn default_line(side: Side, x: f64, descender: f64, ascender: f64) -> Self {
        Self {
            side,
            points: vec![(descender, x), (ascender, x)],
            source: WallSource::DefaultLine,
        }
    }

    /// Designer override input (BubbleKern native mode), points taken as
    /// given (must already be y-sorted).
    pub fn designer(side: Side, points: Vec<(f64, f64)>) -> Self {
        Self { side, points, source: WallSource::DesignerOverride }
    }

    /// Slant at use (v2 italic correction): points are stored upright; this
    /// returns the wall sheared by the italic angle about mline
    /// (= baseline_y - xHeight/2). RASTER PLANE (y down): the shear is
    /// x -= (y - mline) * tan(angle), the same convention as
    /// baseline_htls's italic test (positive angle leans right at top).
    pub fn slanted(&self, angle_deg: f64, mline: f64) -> Wall {
        let t = (angle_deg * std::f64::consts::PI / 180.0).tan();
        Wall {
            side: self.side,
            points: self
                .points
                .iter()
                .map(|&(y, x)| (y, x - (y - mline) * t))
                .collect(),
            source: self.source,
        }
    }

    /// Wall x at row y by linear interpolation between stored points
    /// (exact for polylines; outside the stored range the end values hold).
    pub fn x_at(&self, y: f64) -> Option<f64> {
        let p = &self.points;
        if p.is_empty() {
            return None;
        }
        if y <= p[0].0 {
            return Some(p[0].1);
        }
        if y >= p[p.len() - 1].0 {
            return Some(p[p.len() - 1].1);
        }
        for w in p.windows(2) {
            let (y0, x0) = w[0];
            let (y1, x1) = w[1];
            if y0 <= y && y <= y1 {
                if y1 == y0 {
                    return Some(x0);
                }
                let t = (y - y0) / (y1 - y0);
                return Some(x0 + t * (x1 - x0));
            }
        }
        None
    }
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
    fn measured_wall_offsets_outward_from_ink() {
        let img = rect_image(100, 100, 20, 10, 60, 90);
        let g = RasterGlyph { image: &img };
        let wp = WallProfiles::from_scan(&g).unwrap();
        let lw = Wall::measured(&wp, Side::Left, OffsetPolicy::Constant(5.0)).unwrap();
        let rw = Wall::measured(&wp, Side::Right, OffsetPolicy::Constant(5.0)).unwrap();
        assert_eq!(lw.x_at(10.0), Some(15.0)); // left ink 20, pushed out by 5
        assert_eq!(rw.x_at(10.0), Some(64.0)); // right ink 59, pushed out by 5
        assert_eq!(lw.source, WallSource::Measured);
    }

    #[test]
    fn default_line_is_flush_vertical() {
        let w = Wall::default_line(Side::Left, 0.0, -200.0, 700.0);
        assert_eq!(w.x_at(-200.0), Some(0.0));
        assert_eq!(w.x_at(0.0), Some(0.0));
        assert_eq!(w.x_at(700.0), Some(0.0));
    }

    #[test]
    fn slant_at_use_pivots_at_mline() {
        let w = Wall::default_line(Side::Left, 10.0, 20.0, 120.0);
        let s = w.slanted(12.0, 70.0);
        let t = (12f64 * std::f64::consts::PI / 180.0).tan();
        assert!((s.x_at(70.0).unwrap() - 10.0).abs() < 1e-9); // pivot row: no shift
        assert!((s.x_at(20.0).unwrap() - (10.0 + 50.0 * t)).abs() < 1e-6); // top leans right
    }

    #[test]
    fn x_at_interpolates_between_points() {
        let w = Wall::designer(Side::Left, vec![(0.0, 0.0), (10.0, 20.0)]);
        assert_eq!(w.x_at(5.0), Some(10.0));
        assert_eq!(w.x_at(-5.0), Some(0.0)); // clamped at the end
        assert_eq!(w.x_at(15.0), Some(20.0));
    }
}
