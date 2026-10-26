//! Paul New outline anchor: the tile box maps onto the declared em box,
//! anisotropic. The measured frame's inner left edge maps to x = -1 (the
//! declared edge overhang), tile top is y=850, tile bottom is y=-150. No
//! ink-left-align, no crop: interior whitespace is anatomy.
//!
//! Supersedes the 2026-10-17 model (tile left edge is x=0): that model left
//! the 2 px printed frame in the shipped metrics (hmtx lsb 0 with ink at +2,
//! rsb +2). Owner directive 2026-10-18 03:05-03:06: the frame is a 2 px
//! source artifact, never design; edge glyphs ship lsb = rsb = -1, glyphs
//! with interior margins ship margin - 1 on each side. K_X is unchanged:
//! the anatomy is never scaled or stretched, only re-origined.
//!
//! TODO(pn1-metrics-merge): K_X and the em-box constants are declared by the
//! PN-1-METRICS lane in declared_convention; at merge, consume them from
//! there and delete the local copies. K_Y is intentionally NOT copied here:
//! it is the declared scale (declared_convention::DECLARED_K_BITS).
use kni_core::reference_slice::{Point, ReferenceRing, Span};

/// Exact IEEE-754 bits of 696.0 / 786.0 = 0.8854961832061069.
pub const PAUL_NEW_K_X_BITS: u64 = 0x3fec_55fc_1773_4c37;
pub const PAUL_NEW_K_X: f64 = f64::from_bits(PAUL_NEW_K_X_BITS);
/// Declared em-box top (tile top) and bottom (tile bottom = top - 1000).
pub const PAUL_NEW_EM_TOP_UNITS: f64 = super::declared_convention::PAUL_NEW_ASCENDER_UNITS as f64;
// Geometry em-box bottom (tile bottom = top - 1000 by the pinned K_Y). This is
// NOT the descender metric: since the 2026-10-18 03:37 owner directive the
// shipped descender metric is declared_convention::PAUL_NEW_DESCENDER_UNITS
// (-145), a line-metric value only; the tile geometry keeps the 1000-unit em.
#[allow(dead_code)]
pub const PAUL_NEW_EM_BOTTOM_UNITS: f64 = PAUL_NEW_EM_TOP_UNITS - 1000.0;
/// Declared advance (em-box width): every Paul New glyph.
// Declared em-box width of every Paul New glyph; the K_X basis. The shipped
// advance is the frame-stripped em box (see module header), never this raw width.
#[allow(dead_code)]
pub const PAUL_NEW_ADVANCE_UNITS: f64 = 696.0;
/// Declared edge overhang in font units (owner directive 2026-10-18 03:06,
/// "-1 olsun lsb rsb"): the tile frame's inner edges anchor to x = -1 and to
/// advance + 1, so an edge-reaching glyph ships lsb = rsb = -1 and a
/// margin glyph ships margin - 1 per side.
pub const PAUL_NEW_EDGE_OVERHANG_UNITS: f64 = 1.0;

fn map_point(p: &mut Point, origin_x: f64, k_y: f64, frame_left_px: f64) {
    // Recover the tile pixel x (the fit emits bbox-local x at uniform k_y),
    // re-add the capture origin, drop the measured left frame band, rescale
    // anisotropically, then apply the declared edge overhang. y is already
    // in the source tile frame (tile top = 0, y-down negative); re-anchor to
    // the declared em box. y is untouched by the frame ruling.
    *p = Point { x: (p.x / k_y + origin_x - frame_left_px) * PAUL_NEW_K_X - PAUL_NEW_EDGE_OVERHANG_UNITS, y: p.y + PAUL_NEW_EM_TOP_UNITS };
}

/// Re-anchor shipped Paul New outline rings in place. `origin_x` is the
/// capture contour's content-bbox min x in tile pixels; `k_y` the declared
/// uniform scale the fit used. Callers pass the shipped outline only, never
/// the measurement drawing.
pub fn anchor_outline(rings: &mut [ReferenceRing], origin_x: f64, k_y: f64, frame_left_px: f64) {
    assert!(origin_x.is_finite() && k_y.is_finite() && k_y > 0.0 && frame_left_px.is_finite() && frame_left_px >= 0.0, "anchor: finite frame inputs");
    for ring in rings {
        map_point(&mut ring.start, origin_x, k_y, frame_left_px);
        for span in &mut ring.spans {
            match span {
                Span::Line { end } => map_point(end, origin_x, k_y, frame_left_px),
                Span::Cubic { control_one, control_two, end } => {
                    map_point(control_one, origin_x, k_y, frame_left_px);
                    map_point(control_two, origin_x, k_y, frame_left_px);
                    map_point(end, origin_x, k_y, frame_left_px);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn glyph() -> Vec<ReferenceRing> {
        vec![ReferenceRing {
            start: Point { x: 10.0, y: -250.0 },
            spans: vec![Span::Cubic {
                control_one: Point { x: 20.0, y: -300.0 },
                control_two: Point { x: 30.0, y: -350.0 },
                end: Point { x: 40.0, y: -400.0 },
            }],
        }]
    }
    #[test]
    fn anisotropic_x_and_em_box_y() {
        let k_y = 1000.0 / 1122.0;
        let mut g = glyph();
        anchor_outline(&mut g, 0.0, k_y, 0.0);
        // x: (10 / k_y) px * K_X - overhang; y: -250 + 850.
        let want_x = (10.0 / k_y) * PAUL_NEW_K_X - PAUL_NEW_EDGE_OVERHANG_UNITS;
        assert!((g[0].start.x - want_x).abs() < 1e-9, "{} vs {want_x}", g[0].start.x);
        assert_eq!(g[0].start.y, 600.0);
        match &g[0].spans[0] {
            Span::Cubic { control_one, control_two, end } => {
                assert_eq!(control_one.y, 550.0);
                assert_eq!(control_two.y, 500.0);
                assert_eq!(end.y, 450.0);
            }
            _ => panic!("span kind changed"),
        }
    }
    #[test]
    fn interior_margin_is_preserved_not_left_aligned() {
        // Content starting 40 px into the tile keeps its margin: x stays > 0.
        let k_y = 1000.0 / 1122.0;
        let mut g = glyph();
        anchor_outline(&mut g, 40.0, k_y, 0.0);
        let want_x = (10.0 / k_y + 40.0) * PAUL_NEW_K_X - PAUL_NEW_EDGE_OVERHANG_UNITS;
        assert!((g[0].start.x - want_x).abs() < 1e-9);
        assert!(g[0].start.x > 0.0, "interior edge margin must survive");
    }
    #[test]
    fn tile_edges_land_on_the_em_box() {
        // Full-tile ink at uniform k_y spans x in [0, 701] and y in [-1000, 0]:
        // anchored, the tile box lands on [0,696] x [-150,850].
        let k_y = 1000.0 / 1122.0;
        let mut g = vec![ReferenceRing {
            start: Point { x: 0.0, y: 0.0 },
            spans: vec![Span::Line { end: Point { x: 786.0 * k_y, y: -1000.0 } }],
        }];
        anchor_outline(&mut g, 0.0, k_y, 0.0);
        assert!((g[0].start.x - (-PAUL_NEW_EDGE_OVERHANG_UNITS)).abs() < 1e-9);
        assert!((g[0].start.y - PAUL_NEW_EM_TOP_UNITS).abs() < 1e-9);
        match &g[0].spans[0] {
            Span::Line { end } => {
                assert!((end.x - (PAUL_NEW_ADVANCE_UNITS - PAUL_NEW_EDGE_OVERHANG_UNITS)).abs() < 1e-9, "{} vs 695", end.x);
                assert!((end.y - PAUL_NEW_EM_BOTTOM_UNITS).abs() < 1e-9);
            }
            _ => panic!("span kind changed"),
        }
    }
    #[test]
    fn frame_band_and_overhang_leave_ink_at_minus_one() {
        // Regression for the 2026-10-18 frame-residue ruling: a tile whose
        // measured left frame band is 2 px anchors the frame's inner edge to
        // x = -1, not to x = +2K_X (the old residue). Fails on the old
        // signature (no frame_left_px) and on the old mapping.
        let k_y = 1000.0 / 1122.0;
        let mut g = vec![ReferenceRing {
            start: Point { x: 0.0, y: 0.0 },
            // end sits at the right frame's inner edge (tile px 784 on a 786
            // tile): the fit emits bbox-local x, so (784 - origin 2) * k_y.
            spans: vec![Span::Line { end: Point { x: 782.0 * k_y, y: -1000.0 } }],
        }];
        anchor_outline(&mut g, 2.0, k_y, 2.0);
        assert!((g[0].start.x - (-PAUL_NEW_EDGE_OVERHANG_UNITS)).abs() < 1e-9, "frame inner left edge must land at -1");
        match &g[0].spans[0] {
            Span::Line { end } => {
                let want = (784.0 - 2.0) * PAUL_NEW_K_X - PAUL_NEW_EDGE_OVERHANG_UNITS;
                assert!((end.x - want).abs() < 1e-9, "{} vs {want}", end.x);
            }
            _ => panic!("span kind changed"),
        }
    }
}
