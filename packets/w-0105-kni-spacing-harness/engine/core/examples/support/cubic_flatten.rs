//! Adaptive cubic-to-polygon flattening with explicit, typed workload budgets.
//!
//! Drop-in helper for the span-flattening step in generated_outline_spacing:
//! same acceptance rule (control-hull distance to the chord), same output
//! convention (only subdivision endpoints are pushed; the caller pushes the
//! curve start point), same subdivision (de Casteljau at t = 1/2), same
//! evaluation order (depth-first, left child before right child). The output
//! sequence is identical to the recursive formulation it replaces.
//!
//! Workload bounds are explicit parameters, not derived values:
//! - `depth_budget` caps subdivision depth; exhaustion is a typed error.
//! - `point_budget` caps points this call may push; exhaustion is a typed
//!   error. A caller bounding a whole outline passes its remaining budget per
//!   span and decrements it by the observed `out` length delta.
//!
//! Total work of one call is O(point_budget + depth_budget): every accepted
//! leaf pushes one point, and a full binary tree with L leaves has L-1
//! internal splits. The explicit stack holds at most depth_budget + 1
//! entries, so deep budgets cannot overflow the call stack.
//!
//! On `Err`, `out` may contain partially emitted points; the caller must
//! discard them, exactly as with the recursive formulation.

use kni_core::reference_slice::Point;

/// Typed exhaustion and misuse outcomes for cubic flattening.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlattenError {
    /// `tol` was not finite and strictly positive.
    InvalidTolerance,
    /// A segment still exceeded `tol` with no subdivision depth left.
    DepthBudgetExhausted,
    /// A point push was needed with no point budget left.
    PointBudgetExhausted,
}

impl std::fmt::Display for FlattenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let message = match self {
            FlattenError::InvalidTolerance => "flattening tolerance must be finite and positive",
            FlattenError::DepthBudgetExhausted => "flattening depth budget exhausted",
            FlattenError::PointBudgetExhausted => "flattening point budget exhausted",
        };
        f.write_str(message)
    }
}

impl std::error::Error for FlattenError {}

/// Distance from `p` to the chord `a`-`b`, clamped to the segment.
fn chord_distance(p: Point, a: Point, b: Point) -> f64 {
    let dx = b.x - a.x;
    let dy = b.y - a.y;
    let n = dx * dx + dy * dy;
    if n == 0.0 {
        return (p.x - a.x).hypot(p.y - a.y);
    }
    let t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / n).clamp(0.0, 1.0);
    (p.x - a.x - t * dx).hypot(p.y - a.y - t * dy)
}

fn midpoint(a: Point, b: Point) -> Point {
    Point { x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0 }
}

/// Flatten the cubic `segment` (start, control one, control two, end) into
/// `out`, pushing only subdivision endpoints, at most `point_budget` of them.
///
/// A segment is flat enough when both control points lie within `tol` of the
/// start-end chord. Flat acceptance is checked before the depth budget, so a
/// segment that is flat at depth zero is still accepted, matching the
/// replaced recursion. The curve start point is never pushed here.
pub fn flatten_cubic(
    segment: [Point; 4],
    tol: f64,
    depth_budget: usize,
    point_budget: usize,
    out: &mut Vec<[f64; 2]>,
) -> Result<(), FlattenError> {
    if !tol.is_finite() || tol <= 0.0 {
        return Err(FlattenError::InvalidTolerance);
    }
    let mut remaining = point_budget;
    let mut stack: Vec<([Point; 4], usize)> = vec![(segment, depth_budget)];
    while let Some((p, depth)) = stack.pop() {
        if chord_distance(p[1], p[0], p[3]).max(chord_distance(p[2], p[0], p[3])) <= tol {
            if remaining == 0 {
                return Err(FlattenError::PointBudgetExhausted);
            }
            remaining -= 1;
            out.push([p[3].x, p[3].y]);
            continue;
        }
        if depth == 0 {
            return Err(FlattenError::DepthBudgetExhausted);
        }
        let a = midpoint(p[0], p[1]);
        let b = midpoint(p[1], p[2]);
        let c = midpoint(p[2], p[3]);
        let d = midpoint(a, b);
        let e = midpoint(b, c);
        let f = midpoint(d, e);
        // Right half is pushed first so the left half pops first; this keeps
        // the recursive left-before-right emission order exactly.
        stack.push(([f, e, c, p[3]], depth - 1));
        stack.push(([p[0], a, d, f], depth - 1));
    }
    Ok(())
}
