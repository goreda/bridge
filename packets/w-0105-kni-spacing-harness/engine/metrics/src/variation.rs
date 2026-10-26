//! STEP 8: variation - variable fonts.
//!
//! Rule: interpolate the solver PARAMETERS at axis position t and
//! RE-SOLVE; never interpolate kern values. This module therefore exposes
//! exactly one path: MasterParams interpolation + a fresh solve. There is
//! deliberately no API that interpolates solver outputs.
//!
//! DISCRETE INPUTS (class assignments, mechanism activations) are NOT
//! interpolated: they arrive per master from side_classes/mechanisms and
//! enter each solve as given. A class jump between masters is handled by
//! re-solving with each master's own discrete inputs, never by blending
//! memberships across the jump (tested below).
//!
//! BBLH node interpolation across masters is UNSPECIFIED upstream -
//! [SURROGATE] keep node count/order identical per master and interpolate
//! node positions linearly (`interpolate_points`).
//!
//! Tier (c).

use crate::params::MasterParams;

/// Linear interpolation of the continuous solver parameters at axis
/// position t (t=0 -> a, t=1 -> b; t is not clamped, extrapolation is the
/// caller's declared choice). `freq` is an integer step and rounds.
pub fn interpolate_params(a: &MasterParams, b: &MasterParams, t: f64) -> MasterParams {
    let l = |x: f64, y: f64| x + (y - x) * t;
    MasterParams {
        upm: l(a.upm, b.upm),
        x_height: l(a.x_height, b.x_height),
        baseline_y: l(a.baseline_y, b.baseline_y),
        italic_angle_deg: l(a.italic_angle_deg, b.italic_angle_deg),
        param_area: l(a.param_area, b.param_area),
        param_depth_pct: l(a.param_depth_pct, b.param_depth_pct),
        param_over_pct: l(a.param_over_pct, b.param_over_pct),
        freq: (a.freq as f64 + (b.freq - a.freq) as f64 * t).round() as i64,
        area_factor: l(a.area_factor, b.area_factor),
    }
}

/// The parameter-interpolation path: interpolate parameters, then re-solve. `solve` receives
/// the interpolated parameters plus the caller's per-master discrete
/// inputs (untouched here, by construction).
pub fn solve_at_axis<F, R>(a: &MasterParams, b: &MasterParams, t: f64, solve: F) -> R
where
    F: FnOnce(&MasterParams) -> R,
{
    solve(&interpolate_params(a, b, t))
}

/// [SURROGATE] BBLH wall-node interpolation across masters: node count and
/// order must be identical per master (upstream does not specify a
/// correspondence rule); positions interpolate linearly. Returns None on a
/// count mismatch - never silently resamples.
pub fn interpolate_points(a: &[(i32, i32)], b: &[(i32, i32)], t: f64) -> Option<Vec<(i32, i32)>> {
    if a.len() != b.len() {
        return None;
    }
    Some(
        a.iter()
            .zip(b.iter())
            .map(|(&(ax, ay), &(bx, by))| {
                (
                    (ax as f64 + (bx - ax) as f64 * t).round() as i32,
                    (ay as f64 + (by - ay) as f64 * t).round() as i32,
                )
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn master(x_height: f64, area: f64, angle: f64) -> MasterParams {
        MasterParams { x_height, param_area: area, italic_angle_deg: angle, ..Default::default() }
    }

    #[test]
    fn endpoints_recover_masters() {
        let a = master(500.0, 400.0, 0.0);
        let b = master(520.0, 380.0, 12.0);
        let p0 = interpolate_params(&a, &b, 0.0);
        let p1 = interpolate_params(&a, &b, 1.0);
        assert_eq!(p0.x_height, 500.0);
        assert_eq!(p1.x_height, 520.0);
        assert_eq!(p1.italic_angle_deg, 12.0);
    }

    #[test]
    fn midpoint_is_mean() {
        let a = master(500.0, 400.0, 0.0);
        let b = master(520.0, 380.0, 12.0);
        let m = interpolate_params(&a, &b, 0.5);
        assert_eq!(m.x_height, 510.0);
        assert_eq!(m.param_area, 390.0);
        assert_eq!(m.italic_angle_deg, 6.0);
    }

    #[test]
    fn solve_at_axis_uses_interpolated_params_not_interpolated_outputs() {
        // A solver nonlinear in the params (area * x_height), so
        // solve(interp(p)) != interp(solve(p)): this rule is load-bearing,
        // and this API only offers the correct side of it.
        let a = master(400.0, 300.0, 0.0);
        let b = master(600.0, 500.0, 0.0);
        let solve = |p: &MasterParams| p.param_area * p.x_height;
        let via_params = solve_at_axis(&a, &b, 0.5, solve);
        let via_outputs = (solve(&a) + solve(&b)) / 2.0;
        assert_eq!(via_params, 400.0 * 500.0); // interp params, fresh solve
        assert_eq!(via_outputs, (120_000.0 + 300_000.0) / 2.0);
        assert_ne!(via_params, via_outputs, "outputs are never interpolated");
    }

    #[test]
    fn discrete_inputs_untouched_by_interpolation() {
        // Discrete per-master inputs (here: a class id) pass through the
        // solve unchanged; nothing blends them across a class jump.
        let a = master(500.0, 400.0, 0.0);
        let b = master(520.0, 380.0, 0.0);
        let class_at_a = "round";
        let seen = solve_at_axis(&a, &b, 0.25, move |_p| class_at_a);
        assert_eq!(seen, "round");
    }

    #[test]
    fn point_interpolation_requires_matching_counts() {
        let a = vec![(0, 0), (100, 200)];
        let b = vec![(10, 20), (140, 260)];
        assert_eq!(interpolate_points(&a, &b, 0.5).unwrap(), vec![(5, 10), (120, 230)]);
        let short = vec![(0, 0)];
        assert!(interpolate_points(&a, &short, 0.5).is_none());
    }

    #[test]
    fn deterministic() {
        let a = master(500.0, 400.0, 0.0);
        let b = master(520.0, 380.0, 12.0);
        let x = interpolate_params(&a, &b, 0.3);
        let y = interpolate_params(&a, &b, 0.3);
        assert_eq!(x.x_height, y.x_height);
        assert_eq!(x.param_area, y.param_area);
    }
}
