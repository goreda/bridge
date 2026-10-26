//! Natural spacing: the "spacing not applied" declaration for one glyph.
//!
//! The advance is the glyph's OWN ink bounding-box width, taken from its
//! outline profile; lsb and rsb are zero. No spacing model ran, so nothing
//! is invented: callers must record the declaration in `DECLARATION`.

use kni_metrics::outline_spacing::OutlineProfile;
use kni_metrics::self_anchored_spacing::GlyphSpacing;

/// Declared in receipts wherever natural spacing replaces solved spacing.
#[allow(dead_code)]
pub const DECLARATION: &str = "spacing not applied";

/// CONVENTION: advance = max_x - min_x of the profile bounds (the glyph's
/// own measurement); lsb = rsb = 0 because no sidebearing was solved.
/// A profile with no usable ink (non-finite or inverted bounds) degrades to
/// advance 0.0, the width of zero ink; no width is invented.
#[allow(dead_code)]
pub fn natural_spacing(profile: &OutlineProfile) -> GlyphSpacing {
    let width = profile.bounds[2] - profile.bounds[0];
    let advance = if width.is_finite() && width > 0.0 { width } else { 0.0 };
    GlyphSpacing { glyph_id: profile.glyph_id.clone(), lsb: 0.0, rsb: 0.0, advance }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prof(id: &str, bounds: [f64; 4]) -> OutlineProfile {
        OutlineProfile {
            glyph_id: id.into(),
            source_pin: String::new(),
            upm: 1000,
            origin: [0.0, 0.0],
            rows: vec![],
            bounds,
            ink_area: 0.0,
            counter_area: 0.0,
            open_left: 0.0,
            open_right: 0.0,
            profile_method: String::new(),
            row_step: 1.0,
            flatten_tolerance: 0.0,
        }
    }

    #[test]
    fn advance_is_ink_bbox_width_with_zero_sidebearings() {
        let s = natural_spacing(&prof("H", [50.0, 0.0, 650.0, 700.0]));
        assert_eq!(s.glyph_id, "H");
        assert_eq!(s.advance, 600.0);
        assert_eq!((s.lsb, s.rsb), (0.0, 0.0));
    }

    #[test]
    fn offset_origin_does_not_change_width() {
        let s = natural_spacing(&prof("o", [-30.0, -10.0, 470.0, 510.0]));
        assert_eq!(s.advance, 500.0);
    }

    #[test]
    fn no_ink_degrades_to_zero_advance() {
        for b in [[f64::NAN, 0.0, 1.0, 1.0], [10.0, 0.0, 5.0, 1.0], [f64::INFINITY, 0.0, f64::INFINITY, 1.0]] {
            assert_eq!(natural_spacing(&prof("x", b)).advance, 0.0);
        }
    }

    #[test]
    fn declaration_text_is_stable() {
        assert_eq!(DECLARATION, "spacing not applied");
    }
}
