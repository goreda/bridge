//! STEP 9: tracking - uniform offset, penetration-preserving.
//!
//! Tracking is a UNIFORM offset applied after spacing: every pair distance
//! shifts by the same amount. Because the shift is uniform, relative
//! penetration is preserved: a pair x units tighter than another stays x
//! units tighter, and the contact/penetration ordering of the pair set is
//! untouched (the shift moves all pairs together; it cannot reorder them
//! and cannot change which pairs are tighter than which).
//!
//! BOUNDARY (iKern Width/Tracking distinction): tracking is never
//! conflated with Width. It does not change the measurement basis, the
//! Air0 anchor, or any width-adjacent quantity; it is an output-side
//! offset only. Half of the offset is conventionally applied per side;
//! `apply_tracking` works on a pair distance directly, `split_per_side`
//! exposes the per-side halves.
//!
//! Source grounding: iKern Width/Tracking distinction. Tier (c).

/// Apply a uniform tracking offset to a pair distance (plane units).
/// Positive tracking loosens, negative tightens.
pub fn apply_tracking(distance: f64, tracking: f64) -> f64 {
    distance + tracking
}

/// The per-side halves of a tracking offset (left side, right side).
pub fn split_per_side(tracking: f64) -> (f64, f64) {
    (tracking / 2.0, tracking / 2.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uniform_shift_preserves_relative_penetration() {
        // Two pairs, one tighter by 30 units; tracking must preserve the
        // difference and the ordering exactly.
        let d_tight = -20.0;
        let d_loose = 10.0;
        for tr in [-50.0, -5.0, 0.0, 12.0, 200.0] {
            let a = apply_tracking(d_tight, tr);
            let b = apply_tracking(d_loose, tr);
            assert_eq!(b - a, 30.0, "relative penetration preserved at tracking {tr}");
            assert!(a < b, "ordering preserved");
        }
    }

    #[test]
    fn sign_and_magnitude() {
        assert_eq!(apply_tracking(100.0, -15.0), 85.0);
        assert_eq!(apply_tracking(-30.0, 10.0), -20.0);
    }

    #[test]
    fn per_side_halves_sum_to_offset() {
        let (l, r) = split_per_side(-18.0);
        assert_eq!(l + r, -18.0);
        assert_eq!(l, r);
    }

    #[test]
    fn zero_tracking_is_identity() {
        assert_eq!(apply_tracking(42.5, 0.0), 42.5);
    }
}
