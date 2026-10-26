//! Declared policy values shared by more than one call site. Each value carries its status and
//! derivation/source; PROVISIONAL means no measurement-backed derivation is recorded yet
//! (see engine/tooling/threshold-inventory.tsv). Values are unchanged from the pre-refactor literals.

/// Corner turn cosine: windowed/local turn sharper than 60 degrees is a corner candidate.
/// PROVISIONAL; was a bare 0.5 at capture.rs (3 sites) and capture_fit.rs staircase test.
pub const CORNER_TURN_COS: f64 = 0.5;

/// Multiplier on t_line for chord/junction deviation limits. PROVISIONAL; was bare 1.5 at
/// capture_fit.rs staircase deviation and line-junction move limit.
pub const T_LINE_SLACK: f64 = 1.5;

/// Tangent-window L_min = clamp(frac*total, floor, total*cap). PROVISIONAL; was duplicated at two
/// capture_fit.rs tangent estimators. floor is in font units (not upm scaled).
pub const TANGENT_L_MIN_FRAC: f64 = 0.05;
pub const TANGENT_L_MIN_FLOOR: f64 = 3.0;
pub const TANGENT_L_MIN_CAP: f64 = 0.5;
pub fn tangent_l_min(total: f64) -> f64 {
    (TANGENT_L_MIN_FRAC * total).max(TANGENT_L_MIN_FLOOR).min(total * TANGENT_L_MIN_CAP)
}
